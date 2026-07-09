# ==============================================================================
# 102_death_cause_nhl_flag.R -- Cause-of-Death NHL Flag CSV (Phase 118)
# ==============================================================================
# Purpose:     Produce a per-patient CSV flagging whether each deceased patient's
#              cause of death classifies as Non-Hodgkin Lymphoma (NHL). The flag
#              is a three-state logical: TRUE (NHL cause), FALSE (other coded
#              cause), or blank/NA (cause of death uncoded or missing).
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
# Inputs:      DuckDB DEATH table (DEATH_DATE, DEATH_CAUSE / DEATH_CAUSE_CODE,
#              ID columns)
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
#
# Usage:       Rscript R/102_death_cause_nhl_flag.R
#              source("R/102_death_cause_nhl_flag.R")
#
# Note:        Tested structurally on Windows (no data). Full run with row
#              counts is HiPerGator-only (requires DuckDB PCORnet data).
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

message("=== Phase 118: Cause-of-Death NHL Flag ===\n")


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

message("--- Loading DEATH table from DuckDB ---")

death_raw <- get_pcornet_table("DEATH") %>% collect()

message(glue("  Raw DEATH table: {nrow(death_raw)} rows"))

# Field-availability guard (D-78-01): DEATH_CAUSE column name varies by site
death_cause_available <- FALSE
death_cause_col       <- NULL

if ("DEATH_CAUSE" %in% names(death_raw)) {
  death_cause_col       <- "DEATH_CAUSE"
  death_cause_available <- TRUE
  message("  Found DEATH_CAUSE column")
} else if ("DEATH_CAUSE_CODE" %in% names(death_raw)) {
  death_cause_col       <- "DEATH_CAUSE_CODE"
  death_cause_available <- TRUE
  message("  Found DEATH_CAUSE_CODE column (alternative name)")
} else {
  message("  WARNING: DEATH_CAUSE field not available in DEATH table")
  message("           cause_of_death_is_nhl will be NA (blank) for all rows")
}

# Parse dates, coerce 1900 sentinel to NA, drop patients with no valid death date
death_data <- death_raw %>%
  mutate(DEATH_DATE = parse_pcornet_date(DEATH_DATE)) %>%
  mutate(DEATH_DATE = if_else(year(DEATH_DATE) == 1900L, as.Date(NA), DEATH_DATE)) %>%
  filter(!is.na(DEATH_DATE))

message(glue("  Patients with valid death dates: {nrow(death_data)}"))

# Align DEATH_CAUSE column (or substitute NA_character_ if field absent)
if (death_cause_available) {
  death_data <- death_data %>%
    select(ID, DEATH_DATE, DEATH_CAUSE = all_of(death_cause_col))
} else {
  death_data <- death_data %>%
    mutate(DEATH_CAUSE = NA_character_) %>%
    select(ID, DEATH_DATE, DEATH_CAUSE)
}

# Aggregate to one death record per patient (earliest valid death date, first cause)
death_data <- death_data %>%
  group_by(ID) %>%
  summarise(
    DEATH_DATE  = min(DEATH_DATE),
    DEATH_CAUSE = first(DEATH_CAUSE),
    .groups     = "drop"
  )

message(glue("  Patients after per-patient aggregation: {nrow(death_data)}"))

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

message("\nDone. (Phase 118 -- NHLDEATH-01 through NHLDEATH-03)")
