# ==============================================================================
# 116_encounter_ses_index.R -- Encounter-Level SES Index Linkage (Phase 144)
# ==============================================================================
# Purpose:     READ-ONLY investigation. For every ENCOUNTER row in the DuckDB
#              CDM (full extract, not HL-cohort-filtered), resolves the active
#              ZIP9/ZIP5 at ADMIT_DATE via get_zip9_at_date() |> approximate_zip9()
#              (which includes the Phase 144 Tier 3 centroid fallback), then joins
#              four SES index scores from probe-first-gated reference files:
#                - SDI  (Robert Graham Center, ZCTA-level via ZIP5; D-01 label)
#                - ADI  (Neighborhood Atlas, ZIP9-keyed 23-state collation; D-05 answer)
#                - SVI  (CDC SVI 2020, derived at ZCTA via findSVI; D-02a-i)
#                - RUCA (USDA 2020 ZIP Code Data, ZIP5; data/reference/RUCA-codes-2020-zipcode.xlsx)
#              Produces a dated encounter-level RDS cache and a 5-sheet summary xlsx.
#              Does NOT modify any pipeline output or write hl_cohort.csv.
#
# Inputs:      ENCOUNTER table (via DuckDB), scoped to PATIDs present in
#              LDS_ADDRESS_HISTORY. Not an HL-cohort filter (that is out of
#              scope per D-07) -- an address-coverage filter, without which
#              every non-extract encounter resolves to ZIP9 = NA.
#              LDS_ADDRESS_HISTORY_Mailhot_V1.csv (via get_zip9_at_date/approximate_zip9)
#              data/reference/RUCA-codes-2020-zipcode.xlsx (Phase 116; always expected)
#              data/reference/zip5_sdi_reference.csv       (SDI; probe-first gated)
#              data/reference/neighborhood_atlas_zip9_adi.csv (ADI; probe-first gated; 478MB gitignored)
#              data/reference/svi_2020_zcta_derived.csv     (SVI derived via findSVI; probe-first gated)
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
RUCA_PATH        <- file.path("data", "reference", "RUCA-codes-2020-zipcode.xlsx")
SDI_PATH         <- file.path("data", "reference", "zip5_sdi_reference.csv")
ADI_PATH         <- file.path("data", "reference", "neighborhood_atlas_zip9_adi.csv")
ADI_SUMMARY_PATH <- here::here("data", "reference", "zip5_adi_summary.csv")
# ADI_PATH points at the 23-state ZIP9-keyed collation (D-05 answer; 478MB; gitignored).
# Transfer to HiPerGator via scp before running. Block-group file is NOT used for R/116.
SVI_PATH  <- file.path("data", "reference", "svi_2020_zcta_derived.csv")
# SVI_PATH points at the findSVI-derived file (D-02a-i). Run R/117_build_svi_zcta.R on
# HiPerGator to produce it. CDC does not publish 2020 ZCTA-level SVI; this is derived.

# SECTION 3: PROBE GATES FOR REFERENCE FILES ----

probe_reference <- function(path, label) {
  exists <- file.exists(path)
  msg <- if (exists) "found" else "NOT found (columns will be NA)"
  message(glue("  [{label}] {path}: {msg}"))
  exists
}

has_ruca        <- probe_reference(RUCA_PATH,        "RUCA")
has_sdi         <- probe_reference(SDI_PATH,         "SDI")
has_adi         <- probe_reference(ADI_PATH,         "ADI")
has_svi         <- probe_reference(SVI_PATH,         "SVI")
has_adi_summary <- probe_reference(ADI_SUMMARY_PATH, "ADI_SUMMARY")

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

zip_resolved_raw <- get_zip9_at_date(
  ids   = encounters_raw$PATID,
  dates = encounters_raw$ADMIT_DATE
)

# Phase 145 D-02 diagnostic: the zip9_source breakdown below is assigned after
# approximation and cannot distinguish "nothing was approximable" from "approximable
# rows had no ZIP5". Print the pre-approximation state so the D-02 branch is decidable.
message("  pre-approximation state (match_type x ZIP9 missing x ZIP5 missing):")
print(with(zip_resolved_raw,
           table(match_type,
                 zip9_na = is.na(ZIP9),
                 zip5_na = is.na(ZIP5),
                 useNA = "ifany")))

# Phase 148 D-03c: ZIP5-level ADI summary join — attaches has_adi_zip5 flag so
# .classify_zip9_source() can fire the zip5_representative branch for rows that
# would otherwise land in zip5_no_zip9. adi_natrank_zip5_median is a DISTINCT
# column from adi_natrank (ZIP9-level) — never coalesced.
if (has_adi_summary) {
  adi_summary <- vroom::vroom(
    ADI_SUMMARY_PATH,
    col_types = vroom::cols(
      ZIP5               = vroom::col_character(),
      adi_natrank_median = vroom::col_double(),
      adi_natrank_p25    = vroom::col_double(),
      adi_natrank_p75    = vroom::col_double(),
      n_zip9_in_zip5     = vroom::col_integer(),
      n_zip9_with_adi    = vroom::col_integer(),
      vintage            = vroom::col_character(),
      method             = vroom::col_character(),
      source             = vroom::col_character()
    ),
    progress = FALSE
  ) |>
    dplyr::select(ZIP5, adi_natrank_zip5_median = adi_natrank_median) |>
    dplyr::mutate(has_adi_zip5 = TRUE)

  zip_resolved_raw <- zip_resolved_raw |>
    dplyr::left_join(adi_summary, by = "ZIP5") |>
    dplyr::mutate(has_adi_zip5 = dplyr::coalesce(has_adi_zip5, FALSE))

  message(glue::glue("  ADI summary staged: {format(nrow(adi_summary), big.mark=',')} ZIP5s"))
} else {
  zip_resolved_raw <- zip_resolved_raw |>
    dplyr::mutate(has_adi_zip5 = FALSE, adi_natrank_zip5_median = NA_real_)
  message("  ADI summary not staged — zip5_representative tier inactive")
}

zip_resolved <- zip_resolved_raw |> approximate_zip9()

# get_zip9_at_date() returns one row per DISTINCT (ID, query_date); join back on
# ID=PATID, query_date=ADMIT_DATE to restore one row per ENCOUNTERID.
#
# relationship = "many-to-one" is deliberate and must NOT be relaxed to
# "many-to-many": one resolved ZIP maps to many encounters (same patient, same
# day), but never the reverse. Declaring many-to-many silenced the dplyr warning
# that would have caught the Phase 144 fan-out (1,950,696 -> 2,210,904 rows).
encounter_zip <- encounters_raw %>%
  left_join(
    zip_resolved %>% dplyr::rename(PATID = ID, ADMIT_DATE = query_date),
    by = c("PATID", "ADMIT_DATE"),
    relationship = "many-to-one"
  )

stopifnot("ZIP resolution fanned out -- zip_resolved has duplicate (PATID, ADMIT_DATE) keys" =
            nrow(encounter_zip) == nrow(encounters_raw))

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

# ADI: Neighborhood Atlas ZIP9-keyed 23-state collation (neighborhood_atlas_zip9_adi.csv).
# D-05 answer: ZIP9-keyed files exist for 23 states. File is 478MB and gitignored;
# transfer to HiPerGator via scp before running. R/116 auto-detects columns:
# Expected columns: ZIP9 key (one of ZIP9, zip9, ADDRESS_ZIP9, zip9_norm, GEOID9, ZIP_PLUS4)
#                   ADI rank: one of adi_natrank, ADI_NATRANK, natrank
# Coverage ceiling: <= 77.7% (zip9_observed share); see Coverage Ceilings sheet.
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

# SVI: CDC SVI 2020 derived at ZCTA via findSVI (D-02a-i).
# Expected file: svi_2020_zcta_derived.csv (produced by R/117_build_svi_zcta.R on HiPerGator).
# CDC does NOT publish 2020 ZCTA-level SVI; this is derived from 2020 ACS via findSVI.
# Expected columns: ZCTA (5-digit char) and RPL_THEMES (composite SVI percentile, 0-1).
# Additional metadata columns (vintage, method, source) are present but not joined.
# Join key is ZIP5 = ZCTA (approximate; ZCTA != ZIP5 in edge cases).
# CAVEAT: RPL_THEMES is percentile-ranked against ZCTAs, NOT comparable to CDC tract SVI.
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
    sdi_score, adi_natrank, adi_natrank_zip5_median, svi_score, ruca_code, ruca_category
  )

# All four lookups are deduplicated on their join key above, so this should hold.
# Assert it rather than rely on it: a future reference file with duplicate ZIP5
# or ZIP9 keys would multiply encounter rows silently.
# Anchored to encounters_raw, not encounter_zip: comparing against an already
# inflated frame is what let the Phase 144 fan-out pass this check.
stopifnot("SES join fanned out -- a reference lookup has duplicate keys" =
            nrow(encounter_ses) == nrow(encounters_raw))

message(glue("  encounter_ses rows: {nrow(encounter_ses)}"))
message(glue("  sdi_score coverage:   {round(100 * mean(!is.na(encounter_ses$sdi_score)),  1)}%"))
message(glue("  adi_natrank coverage: {round(100 * mean(!is.na(encounter_ses$adi_natrank)),1)}%"))
message(glue("  svi_score coverage:   {round(100 * mean(!is.na(encounter_ses$svi_score)),  1)}%"))
message(glue("  ruca_code coverage:   {round(100 * mean(!is.na(encounter_ses$ruca_code)),  1)}%"))

# NOTE (Phase 146 ADI update):
# ADI_PATH now points at neighborhood_atlas_zip9_adi.csv (D-05 answer; 23 states).
# The file is 478MB and gitignored -- transfer to HiPerGator via scp before running.
# ADI coverage is bounded by zip9_observed rows (77.7% ceiling; see Coverage Ceilings sheet).
# Tier 3 centroid fallback remains inert (zip9_source = "zip5_centroid" never fires);
# ADI will still be NA for no_zip5 + none rows (22.3% of encounters). See 144-CONTEXT.md D-01.

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

# Phase 145: year x zip9_source coverage sheet.
# If 'none' clusters in early years the usable SES window is shorter than the
# 2012-01-01 to 2025-03-31 study period; analysts should check the first column.
coverage_by_year <- encounter_ses %>%
  dplyr::mutate(yr = lubridate::year(ADMIT_DATE)) %>%
  dplyr::count(yr, zip9_source) %>%
  tidyr::pivot_wider(names_from = zip9_source, values_from = n, values_fill = 0L) %>%
  dplyr::arrange(yr)

# Phase 145: no-ZIP5 share and ADI ceiling note appended to index_coverage.
# no_zip5 + none rows can receive no index at any geography (14.1% + 8.1% = 22.3%
# of encounters in the 2026-08-17 run). ADI is further limited to zip9_observed rows
# (77.7%); even once the Neighborhood Atlas file is staged, ADI coverage cannot
# exceed that ceiling.
no_zip5_n   <- sum(encounter_ses$zip9_source %in% c("no_zip5", "none"), na.rm = TRUE)
no_zip5_pct <- round(100 * no_zip5_n / nrow(encounter_ses), 1)
adi_ceiling_n   <- sum(encounter_ses$zip9_source == "zip9_observed", na.rm = TRUE)
adi_ceiling_pct <- round(100 * adi_ceiling_n / nrow(encounter_ses), 1)

index_coverage <- index_coverage %>%
  dplyr::bind_rows(tibble(
    index        = "no-ZIP5 (no index possible)",
    n_non_na     = no_zip5_n,
    n_total      = nrow(encounter_ses),
    pct_coverage = no_zip5_pct,
    join_key     = NA_character_,
    file_present = NA
  ),
  tibble(
    index        = "ADI ceiling (zip9_observed rows)",
    n_non_na     = adi_ceiling_n,
    n_total      = nrow(encounter_ses),
    pct_coverage = adi_ceiling_pct,
    join_key     = "ZIP9",
    file_present = NA
  ))

# Phase 146: Coverage Ceilings table (§4 expectations per CONTEXT.md / 146-DISCOVERY.md PART C).
# Rows: per-index geography, best-achievable coverage, limiting factors.
# The 77.7% ceiling = zip9_observed share (1,516,469 / 1,950,696; 2026-08-17 corrected run).
# The ZIP5-with-no-ZCTA unmatched count (second haircut below 77.7% for SDI/SVI) is
# PENDING HiPerGator run of R/diagnostics/146_sdi_coverage_quantifier.R.
coverage_ceilings <- tibble(
  index       = c("RUCA", "SDI", "SVI", "ADI",
                  "NOTE: no-index encounters", "NOTE: SVI ranking caveat"),
  geography   = c("ZIP5", "ZCTA via ZIP5 (D-01)", "ZCTA via ZIP5 derived (D-02a-i)", "ZIP9 (D-05)",
                  NA_character_, NA_character_),
  best_achievable_pct = c(
    "77.7% (achieved)",
    paste0("<=77.7%, minus ZIP5s with no ZCTA (count PENDING HiPerGator run)"),
    paste0("<=77.7%, minus ZCTA match (PENDING HiPerGator run of R/117_build_svi_zcta.R)"),
    "<=77.7%",
    NA_character_, NA_character_
  ),
  limited_by  = c(
    "ZIP availability",
    "ZIP availability, then ZCTA match (PO-box-only/single-building ZIPs unmatched)",
    "ZIP availability, then ZCTA match, then derivation (findSVI Census API)",
    "ZIP9 availability only (23-state collation; 478MB file; transfer via scp)",
    NA_character_, NA_character_
  ),
  note = c(
    NA_character_, NA_character_, NA_character_, NA_character_,
    paste0(
      "22.3% (434,227) of encounters receive no index at any geography: ",
      "14.1% sentinel-ZIP (275,528) + 8.1% no-address-record (158,699). ",
      "This is a data ceiling, not a reference-file problem."
    ),
    paste0(
      "SVI RPL_THEMES is percentile-ranked against ZCTAs, NOT comparable to CDC tract SVI. ",
      "findSVI uses the same ACS variables and CDC methodology but a different reference population."
    )
  )
)

wb <- wb_workbook()
wb <- wb %>%
  wb_add_worksheet("ZIP Source Breakdown") %>%
  wb_add_data(sheet = "ZIP Source Breakdown", x = zip_source_summary, start_row = 1) %>%
  wb_add_worksheet("Index Coverage") %>%
  wb_add_data(sheet = "Index Coverage", x = index_coverage, start_row = 1) %>%
  wb_add_worksheet("Coverage by Year") %>%
  wb_add_data(sheet = "Coverage by Year", x = coverage_by_year, start_row = 2) %>%
  wb_add_data(sheet = "Coverage by Year",
              x = data.frame(note = paste0(
                "Phase 145: zip9_source counts by admission year. ",
                "If 'none' clusters in early years, the usable SES window is shorter ",
                "than the 2012-2025 study period. ",
                "no_zip5 + none = ", no_zip5_n, " (", no_zip5_pct, "%) of all encounters ",
                "can receive no index at any geography. ",
                "ADI ceiling = zip9_observed = ", adi_ceiling_n,
                " (", adi_ceiling_pct, "%) -- see data/reference/README.md."
              )),
              start_row = 1) %>%
  wb_add_worksheet("RUCA Distribution") %>%
  wb_add_data(sheet = "RUCA Distribution", x = ruca_dist, start_row = 1) %>%
  wb_add_worksheet("Coverage Ceilings") %>%
  wb_add_data(sheet = "Coverage Ceilings", x = coverage_ceilings, start_row = 1)

wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)
message(glue("  Saved summary xlsx: {OUTPUT_XLSX}"))
message("=== Phase 144: R/116 complete ===")

# SECTION 10: CLOSE DUCKDB ----

# Close DuckDB connection if R/116 opened it (guard: may already be open from caller)
if (exists("pcornet_con", envir = .GlobalEnv)) {
  close_pcornet_con()
}
