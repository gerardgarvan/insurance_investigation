# ==============================================================================
# 116_encounter_ses_index.R -- Encounter-Level SES Index Linkage (Phase 144)
# ==============================================================================
# Purpose:     READ-ONLY investigation. For every ENCOUNTER row in the DuckDB
#              CDM (full extract, not HL-cohort-filtered), resolves the active
#              ZIP9/ZIP5 at ADMIT_DATE via get_zip9_at_date() |> approximate_zip9()
#              (which includes the Phase 144 Tier 3 centroid fallback), then joins
#              four SES index scores from probe-first-gated reference files:
#                - SDI  (Robert Graham Center, ZIP5-level)
#                - ADI  (Neighborhood Atlas, ZIP9/block-group; pending P-03a)
#                - SVI  (CDC Social Vulnerability Index, ZIP5 approximate)
#                - RUCA (USDA 2020 ZIP Code Data, ZIP5; data/reference/RUCA-codes-2020-zipcode.xlsx)
#              Produces a dated encounter-level RDS cache and a 3-sheet summary xlsx.
#              Does NOT modify any pipeline output or write hl_cohort.csv.
#
# Inputs:      ENCOUNTER table (via DuckDB), scoped to PATIDs present in
#              LDS_ADDRESS_HISTORY. Not an HL-cohort filter (that is out of
#              scope per D-07) -- an address-coverage filter, without which
#              every non-extract encounter resolves to ZIP9 = NA.
#              LDS_ADDRESS_HISTORY_Mailhot_V1.csv (via get_zip9_at_date/approximate_zip9)
#              data/reference/RUCA-codes-2020-zipcode.xlsx (Phase 116; always expected)
#              data/reference/zip5_sdi_reference.csv       (SDI; probe-first gated)
#              data/reference/neighborhood_atlas_block_group_crosswalk.csv (ADI; probe-first gated)
#              data/reference/svi_2020_us_by_zcta.csv      (SVI; probe-first gated)
#
# Outputs:     output/encounter_ses_index_YYYYMMDD.rds
#              output/encounter_ses_index_summary_YYYYMMDD.xlsx
#
# Dependencies: R/00_config.R (auto-sources utils chain: utils_address, utils_duckdb, etc.)
#               dplyr, glue, stringr, openxlsx2, tibble, readxl, vroom
#
# Requirements: Phase 144 -- SES-01, SES-02, SES-03, SES-04
#
# Usage:       Rscript R/116_encounter_ses_index.R
#              source("R/116_encounter_ses_index.R")
#
# Note:        READ-ONLY investigation. Structural verification is runnable locally
#              (grep-based checks). Runtime (DuckDB + LDS_ADDRESS_HISTORY) requires
#              HiPerGator with the ENCOUNTER table and address CSV present.
# ==============================================================================

# SECTION 1: SETUP AND LIBRARIES ----

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(openxlsx2)
  library(tibble)
  library(readxl)
  library(vroom)
})

source("R/00_config.R")

message("=== Phase 144: Encounter-Level SES Index Linkage ===")

# SECTION 2: CONSTANTS AND OUTPUT PATHS ----

RUN_DATE    <- format(Sys.Date(), "%Y%m%d")
OUTPUT_RDS  <- file.path(CONFIG$output_dir, glue("encounter_ses_index_{RUN_DATE}.rds"))
OUTPUT_XLSX <- file.path(CONFIG$output_dir, glue("encounter_ses_index_summary_{RUN_DATE}.xlsx"))

# Reference file paths (all probe-first gated in SECTION 3)
RUCA_PATH <- file.path("data", "reference", "RUCA-codes-2020-zipcode.xlsx")
SDI_PATH  <- file.path("data", "reference", "zip5_sdi_reference.csv")
ADI_PATH  <- file.path("data", "reference", "neighborhood_atlas_block_group_crosswalk.csv")
SVI_PATH  <- file.path("data", "reference", "svi_2020_us_by_zcta.csv")

# SECTION 3: PROBE GATES FOR REFERENCE FILES ----

probe_reference <- function(path, label) {
  exists <- file.exists(path)
  msg <- if (exists) "found" else "NOT found (columns will be NA)"
  message(glue("  [{label}] {path}: {msg}"))
  exists
}

has_ruca <- probe_reference(RUCA_PATH, "RUCA")
has_sdi  <- probe_reference(SDI_PATH,  "SDI")
has_adi  <- probe_reference(ADI_PATH,  "ADI")
has_svi  <- probe_reference(SVI_PATH,  "SVI")

if (!exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}

# SECTION 4: ENCOUNTER PULL (D-07) ----
# Scope: patients present in LDS_ADDRESS_HISTORY. Pulling the full CDM would return
# one row per encounter with ZIP9 = NA for every patient outside the address extract,
# since LDS_ADDRESS_HISTORY_Mailhot_V1.csv covers the HL cohort only.

ADDR_FILENAME <- "LDS_ADDRESS_HISTORY_Mailhot_V1.csv"
addr_path     <- file.path(CONFIG$data_dir, ADDR_FILENAME)

addr_ids <- unique(readr::read_csv(addr_path, show_col_types = FALSE)[["ID"]])
message(glue("  Address history covers {length(addr_ids)} patients"))

enc_tbl <- get_pcornet_table("ENCOUNTER") %>% dplyr::rename_with(toupper)

# Get total CDM encounter count for coverage summary
total_cdm_encounters <- enc_tbl %>%
  dplyr::filter(!is.na(ADMIT_DATE)) %>%
  dplyr::tally() %>%
  dplyr::collect() %>%
  dplyr::pull(n)

message(glue("  Total CDM ENCOUNTER rows (non-NA ADMIT_DATE): {total_cdm_encounters}"))

# NOTE: PCORnet CDM uses "ID" as the patient identifier column, not "PATID".
# Rename to PATID here so downstream code is consistent with the rest of the pipeline.
encounters_raw <- enc_tbl %>%
  dplyr::filter(ID %in% !!addr_ids, !is.na(ADMIT_DATE)) %>%
  dplyr::select(PATID = ID, ENCOUNTERID, ADMIT_DATE) %>%
  dplyr::collect()

stopifnot("encounter pull returned 0 rows" = nrow(encounters_raw) > 0)
message(glue("  {nrow(encounters_raw)} encounters for {dplyr::n_distinct(encounters_raw$PATID)} patients"))

n_excluded <- total_cdm_encounters - nrow(encounters_raw)
pct_excluded <- if (total_cdm_encounters > 0) {
  round(100 * n_excluded / total_cdm_encounters, 1)
} else {
  NA_real_
}
message(glue("  {n_excluded} CDM encounters ({pct_excluded}%) excluded for lack of address data"))

# SECTION 5: ZIP9 RESOLUTION ----

message("--- Resolving ZIP9/ZIP5 per encounter ---")

zip_resolved <- get_zip9_at_date(
  ids   = encounters_raw$PATID,
  dates = encounters_raw$ADMIT_DATE
) |> approximate_zip9()

# get_zip9_at_date returns one row per DISTINCT (ID, query_date) -- join back
# on ID=PATID, query_date=ADMIT_DATE to restore one row per ENCOUNTERID.
encounter_zip <- encounters_raw %>%
  left_join(
    zip_resolved %>% dplyr::rename(PATID = ID, ADMIT_DATE = query_date),
    by = c("PATID", "ADMIT_DATE"),
    relationship = "many-to-many"
  )

message(glue("  ZIP resolution complete. zip9_source breakdown:"))
print(table(encounter_zip$zip9_source, useNA = "ifany"))

# SECTION 6: LOAD REFERENCE FILES (probe-first) ----

message("--- Loading reference files ---")

# RUCA: sheet "RUCA 2020 ZIP Code Data", skip=1, columns ZIPCode (1) + PrimaryRUCA (5)
if (has_ruca) {
  ruca_raw <- readxl::read_excel(RUCA_PATH, sheet = "RUCA 2020 ZIP Code Data",
                                  skip = 1, col_types = "text")
  ruca_lookup <- ruca_raw %>%
    select(ZIP5 = ZIPCode, ruca_code = PrimaryRUCA) %>%
    mutate(
      ZIP5      = normalize_zip5_raw(ZIP5),
      ruca_code = suppressWarnings(as.integer(floor(as.numeric(ruca_code)))),
      ruca_category = dplyr::case_when(
        ruca_code %in% 1:3   ~ "Metropolitan",
        ruca_code %in% 4:6   ~ "Micropolitan",
        ruca_code %in% 7:9   ~ "Small town",
        ruca_code == 10L     ~ "Rural",
        ruca_code == 99L     ~ "Not coded",
        TRUE                 ~ NA_character_
      )
    ) %>%
    filter(!is.na(ZIP5)) %>%
    distinct(ZIP5, .keep_all = TRUE)
  message(glue("  RUCA: {nrow(ruca_lookup)} ZIP5 rows loaded"))
} else {
  ruca_lookup <- tibble(ZIP5 = character(), ruca_code = integer(), ruca_category = character())
  message("  RUCA: reference absent -- ruca_code and ruca_category will be NA")
}

# SDI: Robert Graham Center ZIP5-level index
# Expected columns: ZIP5 (char, 5-digit), SDI_score (numeric, 0-100)
# If the staged file uses different column names, update the select() below.
if (has_sdi) {
  sdi_raw <- tryCatch(
    vroom::vroom(SDI_PATH, col_types = vroom::cols(.default = "c"), progress = FALSE),
    error = function(e) {
      message(glue("  SDI: read failed ({conditionMessage(e)}) -- sdi_score will be NA"))
      NULL
    }
  )
  if (!is.null(sdi_raw) && "ZIP5" %in% names(sdi_raw) && "SDI_score" %in% names(sdi_raw)) {
    sdi_lookup <- sdi_raw %>%
      select(ZIP5, sdi_score = SDI_score) %>%
      mutate(ZIP5 = normalize_zip5_raw(ZIP5), sdi_score = suppressWarnings(as.numeric(sdi_score))) %>%
      filter(!is.na(ZIP5)) %>%
      distinct(ZIP5, .keep_all = TRUE)
    message(glue("  SDI: {nrow(sdi_lookup)} ZIP5 rows loaded"))
  } else {
    message(glue("  SDI: file found but expected columns ZIP5/SDI_score not present. ",
                 "Available: {if (!is.null(sdi_raw)) paste(names(sdi_raw), collapse=', ') else 'NA'}"))
    sdi_lookup <- tibble(ZIP5 = character(), sdi_score = numeric())
  }
} else {
  sdi_lookup <- tibble(ZIP5 = character(), sdi_score = numeric())
}

# ADI: Neighborhood Atlas block-group-level; joined on ZIP9.
# Expected columns: ZIP9 key (one of ZIP9, zip9, ADDRESS_ZIP9, zip9_norm, GEOID9, ZIP_PLUS4)
#                   ADI rank: one of adi_natrank, ADI_NATRANK, natrank
if (has_adi) {
  adi_raw <- tryCatch(
    vroom::vroom(ADI_PATH, col_types = vroom::cols(.default = "c"), progress = FALSE),
    error = function(e) {
      message(glue("  ADI: read failed ({conditionMessage(e)}) -- adi_natrank will be NA"))
      NULL
    }
  )
  adi_zip9_col <- NULL
  adi_rank_col <- NULL
  if (!is.null(adi_raw)) {
    candidate_zip9 <- intersect(c("ZIP9","zip9","ADDRESS_ZIP9","zip9_norm","GEOID9","ZIP_PLUS4"), names(adi_raw))
    candidate_rank <- intersect(c("adi_natrank","ADI_NATRANK","natrank"), names(adi_raw))
    if (length(candidate_zip9) > 0) adi_zip9_col <- candidate_zip9[1]
    if (length(candidate_rank) > 0) adi_rank_col <- candidate_rank[1]
  }
  if (!is.null(adi_zip9_col) && !is.null(adi_rank_col)) {
    adi_lookup <- adi_raw %>%
      select(ZIP9_key = all_of(adi_zip9_col), adi_natrank = all_of(adi_rank_col)) %>%
      mutate(ZIP9_key   = normalize_zip9(ZIP9_key),
             adi_natrank = suppressWarnings(as.integer(adi_natrank))) %>%
      filter(!is.na(ZIP9_key)) %>%
      distinct(ZIP9_key, .keep_all = TRUE)
    message(glue("  ADI: {nrow(adi_lookup)} ZIP9 rows loaded (cols: {adi_zip9_col}, {adi_rank_col})"))
  } else {
    message(glue("  ADI: file found but expected ZIP9/adi_natrank columns not identified -- adi_natrank will be NA. ",
                 "Available: {if (!is.null(adi_raw)) paste(names(adi_raw), collapse=', ') else 'NA'}"))
    adi_lookup <- tibble(ZIP9_key = character(), adi_natrank = integer())
  }
} else {
  adi_lookup <- tibble(ZIP9_key = character(), adi_natrank = integer())
}

# SVI: CDC Social Vulnerability Index 2020 by ZCTA.
# Expected file: svi_2020_us_by_zcta.csv (download from CDC GRASP portal)
# Expected columns: ZCTA (5-digit char) and RPL_THEMES (composite SVI percentile, 0-1)
# Join key is ZIP5 = ZCTA (approximate; ZCTA != ZIP5 in edge cases)
if (has_svi) {
  svi_raw <- tryCatch(
    vroom::vroom(SVI_PATH, col_types = vroom::cols(.default = "c"), progress = FALSE),
    error = function(e) {
      message(glue("  SVI: read failed ({conditionMessage(e)}) -- svi_score will be NA"))
      NULL
    }
  )
  if (!is.null(svi_raw) && "ZCTA" %in% names(svi_raw) && "RPL_THEMES" %in% names(svi_raw)) {
    svi_lookup <- svi_raw %>%
      select(ZIP5 = ZCTA, svi_score = RPL_THEMES) %>%
      mutate(ZIP5      = normalize_zip5_raw(ZIP5),
             svi_score = suppressWarnings(as.numeric(svi_score)),
             svi_score = if_else(svi_score < 0, NA_real_, svi_score)) %>%  # CDC uses -999 for missing
      filter(!is.na(ZIP5)) %>%
      distinct(ZIP5, .keep_all = TRUE)
    message(glue("  SVI: {nrow(svi_lookup)} ZCTA rows loaded"))
  } else {
    message(glue("  SVI: file found but expected columns ZCTA/RPL_THEMES not present. ",
                 "Available: {if (!is.null(svi_raw)) paste(names(svi_raw), collapse=', ') else 'NA'}"))
    svi_lookup <- tibble(ZIP5 = character(), svi_score = numeric())
  }
} else {
  svi_lookup <- tibble(ZIP5 = character(), svi_score = numeric())
}

# SECTION 7: JOIN SES SCORES ----

message("--- Joining SES scores to encounter-level ZIP resolution ---")

encounter_ses <- encounter_zip %>%
  # RUCA: join on ZIP5
  left_join(ruca_lookup %>% select(ZIP5, ruca_code, ruca_category), by = "ZIP5", na_matches = "never") %>%
  # SDI: join on ZIP5
  left_join(sdi_lookup,  by = "ZIP5", na_matches = "never") %>%
  # SVI: join on ZIP5
  left_join(svi_lookup,  by = "ZIP5", na_matches = "never") %>%
  # ADI: join on ZIP9 (block-group level)
  left_join(adi_lookup %>% rename(ZIP9 = ZIP9_key), by = "ZIP9", na_matches = "never") %>%
  select(
    PATID, ENCOUNTERID, ADMIT_DATE,
    ZIP9, ZIP5, match_type, zip9_source,
    sdi_score, adi_natrank, svi_score, ruca_code, ruca_category
  )

# All four lookups are deduplicated on their join key above, so this should hold.
# Assert it rather than rely on it: a future reference file with duplicate ZIP5
# or ZIP9 keys would multiply encounter rows silently.
stopifnot("SES join fanned out -- a reference lookup has duplicate keys" =
            nrow(encounter_ses) == nrow(encounter_zip))

message(glue("  encounter_ses rows: {nrow(encounter_ses)}"))
message(glue("  sdi_score coverage:   {round(100 * mean(!is.na(encounter_ses$sdi_score)),  1)}%"))
message(glue("  adi_natrank coverage: {round(100 * mean(!is.na(encounter_ses$adi_natrank)),1)}%"))
message(glue("  svi_score coverage:   {round(100 * mean(!is.na(encounter_ses$svi_score)),  1)}%"))
message(glue("  ruca_code coverage:   {round(100 * mean(!is.na(encounter_ses$ruca_code)),  1)}%"))

# NOTE (P1-07 -- Tier 3 inert for ADI):
# Tier 3 is currently inert -- no crosswalk exists, so zip9_source = "zip5_centroid" never fires.
# ADI (adi_natrank) will be entirely null as a result (both because the Neighborhood Atlas
# crosswalk is pending P-03a acquisition, AND because ZIP9 resolution via centroid is
# unavailable). This is the honest state of the data; see 144-CONTEXT.md D-01.

# SECTION 8: SAVE RDS CACHE ----

message(glue("--- Saving RDS cache: {OUTPUT_RDS} ---"))
saveRDS(encounter_ses, OUTPUT_RDS)
message(glue("  Saved {nrow(encounter_ses)} rows to {OUTPUT_RDS}"))

# SECTION 9: BUILD SUMMARY XLSX (openxlsx2, following R/115 pattern) ----

message(glue("--- Building summary xlsx: {OUTPUT_XLSX} ---"))

zip_source_summary <- encounter_ses %>%
  count(zip9_source, name = "n") %>%
  mutate(pct = round(100 * n / sum(n), 1)) %>%
  arrange(desc(n))

index_coverage <- tibble(
  index        = c("SDI", "ADI", "SVI", "RUCA"),
  n_non_na     = c(sum(!is.na(encounter_ses$sdi_score)),
                   sum(!is.na(encounter_ses$adi_natrank)),
                   sum(!is.na(encounter_ses$svi_score)),
                   sum(!is.na(encounter_ses$ruca_code))),
  n_total      = nrow(encounter_ses),
  pct_coverage = round(100 * n_non_na / n_total, 1),
  join_key     = c("ZIP5","ZIP9","ZIP5","ZIP5"),
  file_present = c(has_sdi, has_adi, has_svi, has_ruca)
)

ruca_dist <- encounter_ses %>%
  count(ruca_category, name = "n") %>%
  mutate(pct = round(100 * n / sum(n), 1)) %>%
  arrange(desc(n))

wb <- wb_workbook()
wb <- wb %>%
  wb_add_worksheet("ZIP Source Breakdown") %>%
  wb_add_data(sheet = "ZIP Source Breakdown", x = zip_source_summary, start_row = 1) %>%
  wb_add_worksheet("Index Coverage") %>%
  wb_add_data(sheet = "Index Coverage", x = index_coverage, start_row = 1) %>%
  wb_add_worksheet("RUCA Distribution") %>%
  wb_add_data(sheet = "RUCA Distribution", x = ruca_dist, start_row = 1)

wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)
message(glue("  Saved summary xlsx: {OUTPUT_XLSX}"))
message("=== Phase 144: R/116 complete ===")

# SECTION 10: CLOSE DUCKDB ----

# Close DuckDB connection if R/116 opened it (guard: may already be open from caller)
if (exists("pcornet_con", envir = .GlobalEnv)) {
  close_pcornet_con()
}
