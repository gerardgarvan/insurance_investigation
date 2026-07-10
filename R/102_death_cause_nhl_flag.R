# ==============================================================================
# 102_death_cause_nhl_flag.R -- Cause-of-Death NHL Flag CSV (Phase 118 / 119)
# ==============================================================================
# Purpose:     Produce a per-patient CSV flagging whether each deceased patient's
#              cause of death classifies as Non-Hodgkin Lymphoma (NHL). The flag
#              is a three-state logical: TRUE (NHL cause), FALSE (other coded
#              cause), or blank/NA (cause of death uncoded or missing).
#
#              Phase 119 FIX: cause of death is read from the DEATH_CAUSE table
#              (a separate PCORnet CDM table joined to DEATH by ID), NOT from a
#              DEATH.DEATH_CAUSE column -- that column does not exist in this
#              OneFlorida+ extract, which is why the Phase 118 output was 100%
#              blank. The DEATH table carries only DEATH_DATE (deceased-set
#              derivation); the ICD cause codes live in DEATH_CAUSE (wired into
#              the loader in Plan 02). The underlying cause (DEATH_CAUSE_TYPE ==
#              "U") is preferred; otherwise the first available cause per patient.
#
#              The three-state design is deliberate: DEATH_CAUSE is frequently
#              uncoded in PCORnet data (see R/35 completeness profiling), and
#              collapsing "missing" into FALSE would misrepresent the data
#              (CONTEXT.md D-04). Alive patients are excluded entirely (D-02).
#
#              NHL classification uses classify_codes() == "Non-Hodgkin Lymphoma",
#              covering ICD-10 C82-C86, C88 and ICD-9 200, 202. Hodgkin (C81)
#              is NOT NHL (D-05/D-06).
#
#              A documented PROXY BACKSTOP (CONTEXT D-05) exists but is OFF by
#              default: it only activates if the DEATH_CAUSE table yields ZERO
#              coded causes for the entire deceased set, in which case it falls
#              back to NHL-in-DIAGNOSIS-history as an explicitly-labeled proxy.
#
# Inputs:      DuckDB DEATH table       (ID, DEATH_DATE -- deceased set)
#              DuckDB DEATH_CAUSE table (ID, DEATH_CAUSE, DEATH_CAUSE_TYPE, ...)
#
# Outputs:     output/death_cause_nhl_flag.csv
#                Columns: PATID, cause_of_death_is_nhl
#                One row per deceased patient (valid DEATH_DATE).
#                cause_of_death_is_nhl: TRUE / FALSE / blank (NA -> na="")
#
# Dependencies: R/00_config.R (auto-sources utils_duckdb, utils_dates,
#               utils_cancer; provides CONFIG$output_dir)
#               R/utils/utils_duckdb.R  (get_pcornet_table, open_pcornet_con)
#               R/utils/utils_dates.R   (parse_pcornet_date)
#               R/utils/utils_cancer.R  (classify_codes)
#               tidyverse ecosystem: dplyr, glue, stringr, lubridate
#
# Requirements: Phase 118 -- NHLDEATH-01, NHLDEATH-02, NHLDEATH-03
#               Phase 119 -- NHLFIX-03, NHLFIX-04
#
# Usage:       Rscript R/102_death_cause_nhl_flag.R
#              source("R/102_death_cause_nhl_flag.R")
#
# Note:        Tested structurally on Windows (no data). Full run with row
#              counts is HiPerGator-only (requires DuckDB PCORnet data, including
#              the DEATH_CAUSE table loaded via Plan 02's R/01 + R/03 rebuild).
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP AND LIBRARIES ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(lubridate)
})

source("R/00_config.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_dates.R")

message("=== Phase 118/119: Cause-of-Death NHL Flag (DEATH_CAUSE table) ===\n")


# ==============================================================================
# SECTION 2: CONSTANTS ----
# ==============================================================================

OUTPUT_CSV  <- file.path(CONFIG$output_dir, "death_cause_nhl_flag.csv")
NHL_CATEGORY <- "Non-Hodgkin Lymphoma"  # exact classify_codes() label (D-05)

message(glue("Output file: {OUTPUT_CSV}"))


# ==============================================================================
# SECTION 3: SELF-BOOTSTRAP DUCKDB ----
# ==============================================================================

# Self-bootstrap the DuckDB connection so R/102 runs standalone in a fresh
# session (consistent with sibling scripts R/27-R/36). open_pcornet_con() is
# idempotent — it closes any existing connection first — so re-opening later
# in a sourced context is safe.
USE_DUCKDB <- TRUE
if (!exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}


# ==============================================================================
# SECTION 4: LOAD AND DERIVE DECEASED SET ----
# ==============================================================================

# Phase 119: the DEATH table in this extract has NO cause-of-death column
# (columns are ID, DEATH_DATE, DEATH_DATE_IMPUTE, DEATH_SOURCE,
# DEATH_MATCH_CONFIDENCE, SOURCE). It is used ONLY to derive the deceased set.
# The ICD cause codes come from the separate DEATH_CAUSE table (Section 4b).

message("--- Loading DEATH table from DuckDB (deceased-set derivation) ---")

death_raw <- get_pcornet_table("DEATH") %>% collect()

message(glue("  Raw DEATH table: {nrow(death_raw)} rows"))

# Parse dates, coerce 1900 sentinel to NA, drop patients with no valid death date.
# Aggregate to one row per patient (earliest valid death date). No cause read here.
deceased_set <- death_raw %>%
  mutate(DEATH_DATE = parse_pcornet_date(DEATH_DATE)) %>%
  mutate(DEATH_DATE = if_else(year(DEATH_DATE) == 1900L, as.Date(NA), DEATH_DATE)) %>%
  filter(!is.na(DEATH_DATE)) %>%
  group_by(ID) %>%
  summarise(DEATH_DATE = min(DEATH_DATE), .groups = "drop")

message(glue("  Deceased patients (valid death date, one row each): {nrow(deceased_set)}"))


# ==============================================================================
# SECTION 4b: LOAD CAUSE CODES FROM THE DEATH_CAUSE TABLE ----
# ==============================================================================

# Phase 119 PRIMARY PATH (RESEARCH "Case A"): cause of death lives in the
# separate PCORnet CDM DEATH_CAUSE table (columns ID, DEATH_CAUSE,
# DEATH_CAUSE_CODE, DEATH_CAUSE_TYPE, DEATH_CAUSE_SOURCE, DEATH_CAUSE_CONFIDENCE,
# SOURCE). One patient can have multiple cause records (underlying / contributing
# / other / inferred). We PREFER the underlying cause (DEATH_CAUSE_TYPE == "U")
# and fall back to the first available cause per patient (RESEARCH Pitfall 2 --
# a hard "U" filter could drop everyone if the provider populated only "C"/blank).
# DEATH_CAUSE holds the ICD cause code passed to classify_codes() (it normalizes
# internally); DEATH_CAUSE_CODE is only the coding-system indicator (09/10/OT/UN).

message("--- Loading DEATH_CAUSE table from DuckDB (underlying-cause preferred) ---")

dc_tbl <- get_pcornet_table("DEATH_CAUSE")
if (is.null(dc_tbl)) {
  message("  WARNING: DEATH_CAUSE table not in DuckDB -- run R/01 (force_reload) + R/03 to load it.")
  message("           cause_of_death_is_nhl will be NA (blank) for all rows until then.")
  death_cause_by_patient <- tibble(ID = character(), DEATH_CAUSE = character())
} else {
  death_cause_by_patient <- dc_tbl %>%
    collect() %>%
    mutate(type_rank = case_when(
      DEATH_CAUSE_TYPE == "U" ~ 1L, # underlying cause preferred
      DEATH_CAUSE_TYPE == "C" ~ 2L, # contributing
      TRUE                    ~ 3L  # other / inferred / blank
    )) %>%
    filter(!is.na(DEATH_CAUSE), trimws(DEATH_CAUSE) != "") %>%
    arrange(ID, type_rank) %>%
    group_by(ID) %>%
    summarise(DEATH_CAUSE = first(DEATH_CAUSE), .groups = "drop")

  message(glue("  Patients with >=1 coded DEATH_CAUSE: {nrow(death_cause_by_patient)}"))
}

# Join cause codes onto the deceased set. Deceased patients with no DEATH_CAUSE
# record get NA (rendered blank) -- preserving the three-state contract.
death_data <- deceased_set %>%
  left_join(death_cause_by_patient, by = "ID")

close_pcornet_con()


# ==============================================================================
# SECTION 5: THREE-STATE NHL FLAG ----
# ==============================================================================

# Build the three-state flag using classify_codes() (D-05/D-06/D-07):
#   TRUE  — DEATH_CAUSE classifies as "Non-Hodgkin Lymphoma" (ICD-10 C82-C86,
#            C88; ICD-9 200, 202)
#   FALSE — DEATH_CAUSE is a different, coded cause (not NHL)
#   NA    — DEATH_CAUSE is missing, empty, or uncoded (renders as blank cell)
#
# classify_codes() normalizes internally (strips dots), so raw PCORnet codes
# are passed without pre-processing (D-07). Do NOT broaden to C96/C91 (D-06).
#
# cause_of_death_is_nhl is a logical vector so write.csv(na="") renders NA as
# a blank cell while TRUE/FALSE print literally.

message("--- Computing three-state NHL cause-of-death flag ---")

death_flagged <- death_data %>%
  mutate(
    cause_missing = is.na(DEATH_CAUSE) | trimws(DEATH_CAUSE) == "",
    cause_category = if_else(
      cause_missing,
      NA_character_,
      classify_codes(DEATH_CAUSE)
    ),
    cause_of_death_is_nhl = case_when(
      cause_missing                  ~ NA,    # blank/uncoded -> NA -> blank cell (D-04)
      cause_category == NHL_CATEGORY ~ TRUE,  # NHL cause of death (D-05)
      TRUE                           ~ FALSE  # other coded cause
    )
  )

n_nhl   <- sum(death_flagged$cause_of_death_is_nhl == TRUE,  na.rm = TRUE)
n_other <- sum(death_flagged$cause_of_death_is_nhl == FALSE, na.rm = TRUE)
n_blank <- sum(is.na(death_flagged$cause_of_death_is_nhl))

message(glue("  NHL cause (TRUE):    {n_nhl}"))
message(glue("  Other coded (FALSE): {n_other}"))
message(glue("  Uncoded/missing (blank NA): {n_blank}"))


# ==============================================================================
# SECTION 5b: PROXY BACKSTOP (CONTEXT D-05 -- LAST RESORT, OFF BY DEFAULT) ----
# ==============================================================================

# PROXY BACKSTOP (CONTEXT D-05): this branch only fires if NO coded cause of
# death exists for ANY deceased patient (i.e. the real cause-of-death signal is
# genuinely unavailable in DEATH_CAUSE). RESEARCH confirmed the DEATH_CAUSE
# table exists, so this stays OFF by default. When it fires, it flags a deceased
# patient TRUE when their CONFIRMED cancer DIAGNOSIS history includes NHL via
# classify_codes() on the DIAGNOSIS table. This is a PROXY -- it means
# "NHL in cancer diagnosis history", NOT literal cause of death -- and every log
# line + the USED_PROXY_BACKSTOP flag make that unmistakable.

n_coded             <- sum(!is.na(death_flagged$cause_of_death_is_nhl))
USED_PROXY_BACKSTOP <- FALSE

if (n_coded == 0) {
  message("  NOTE: No coded cause of death found for ANY deceased patient.")
  message("        Falling back to DIAGNOSIS-history PROXY (D-05, last resort).")
  message("        PROXY MEANING: 'NHL in cancer diagnosis history', NOT literal cause of death.")
  USED_PROXY_BACKSTOP <- TRUE

  # Re-open the connection (Section 4b closed it) to read DIAGNOSIS.
  if (!exists("pcornet_con", envir = .GlobalEnv)) open_pcornet_con()

  dx_tbl <- get_pcornet_table("DIAGNOSIS")
  if (is.null(dx_tbl)) {
    message("  WARNING: DIAGNOSIS table not in DuckDB -- proxy cannot run; leaving flags NA.")
  } else {
    nhl_history_ids <- dx_tbl %>%
      select(ID, DX) %>%  # this extract keys DIAGNOSIS on ID (not PATID)
      collect() %>%
      filter(!is.na(DX), trimws(DX) != "") %>%
      mutate(dx_category = classify_codes(DX)) %>%
      filter(dx_category == NHL_CATEGORY) %>%
      distinct(ID) %>%
      pull(ID)

    # Three-state preserved: every deceased patient gets TRUE/FALSE from the
    # proxy (no NA), since the proxy is a full-cohort determination.
    death_flagged <- death_flagged %>%
      mutate(cause_of_death_is_nhl = ID %in% nhl_history_ids)

    message(glue("  PROXY: deceased patients with NHL in DIAGNOSIS history (TRUE): ",
                 "{sum(death_flagged$cause_of_death_is_nhl)}"))
  }

  close_pcornet_con()
}


# ==============================================================================
# SECTION 6: BUILD AND WRITE CSV ----
# ==============================================================================

# Export exactly two columns: PATID (renamed from DEATH table's ID) and the
# three-state flag. Rows ordered by PATID for reproducibility.
# write.csv with na="" renders logical NA as a blank cell (D-03/D-04).

message(glue("\n--- Writing CSV to {OUTPUT_CSV} ---"))

nhl_export <- death_flagged %>%
  transmute(
    PATID                = ID,
    cause_of_death_is_nhl
  ) %>%
  arrange(PATID)

write.csv(nhl_export, OUTPUT_CSV, row.names = FALSE, na = "")

message(glue("  Wrote: {OUTPUT_CSV}"))
message(glue("  Rows written: {nrow(nhl_export)}"))


# ==============================================================================
# SECTION 7: FINAL SUMMARY ----
# ==============================================================================

n_rows  <- nrow(nhl_export)
n_true  <- sum(nhl_export$cause_of_death_is_nhl == TRUE,  na.rm = TRUE)
n_false <- sum(nhl_export$cause_of_death_is_nhl == FALSE, na.rm = TRUE)
n_blank <- sum(is.na(nhl_export$cause_of_death_is_nhl))

message(glue("\n--- NHL cause-of-death flag export summary ---"))
message(glue("  Total rows (deceased patients): {format(n_rows, big.mark = ',')}"))
message(glue("  cause_of_death_is_nhl = TRUE  (NHL):          {format(n_true,  big.mark = ',')}"))
message(glue("  cause_of_death_is_nhl = FALSE (other coded):  {format(n_false, big.mark = ',')}"))
message(glue("  cause_of_death_is_nhl = blank (uncoded/NA):   {format(n_blank, big.mark = ',')}"))
message(glue("\n  Output: {OUTPUT_CSV}"))
message(glue("  Columns: PATID, cause_of_death_is_nhl"))
message(glue("  Cause source: {if (USED_PROXY_BACKSTOP) 'DIAGNOSIS-history PROXY (D-05)' else 'DEATH_CAUSE table (underlying-cause preferred)'}"))

message("\nDone. (Phase 118 -- NHLDEATH-01..03; Phase 119 fix (DEATH_CAUSE table) -- NHLFIX-03, NHLFIX-04)")
