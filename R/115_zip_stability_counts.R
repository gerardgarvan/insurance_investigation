# ==============================================================================
# 115_zip_stability_counts.R -- ZIP Stability and Imputation Occurrence Counts
#                                (Phase 139)
# ==============================================================================
# Purpose:     READ-ONLY investigation, deferred from Phase 139 (source: team
#              meeting notes 08/04 and 07/21-24/2026), that measures ZIP
#              stability and imputation-scenario occurrence counts to INFORM
#              (not decide) the team's carry-forward/imputation design for
#              time-varying ZIP data. See
#              .planning/phases/139-zip-stability-imputation-occurrence-counts/139-CONTEXT.md.
#
#              This script does NOT write any imputed ZIP values and does NOT
#              add LDS_ADDRESS_HISTORY to the permanent PCORNET_TABLES load
#              set. get_zip9_at_date() and approximate_zip9() are Out of Scope
#              for modification here -- this script does its own ZIP5
#              coalescing locally via coalesce_zip5() (SECTION 1B below),
#              mirroring R/106's already-proven pattern.
#
# Inputs:      LDS_ADDRESS_HISTORY_Mailhot_V1.csv  (probed in CONFIG$data_dir)
#              ENCOUNTER table (via DuckDB; probed for availability here, used
#                starting Plan 03 of this phase)
#              R/00_config.R                        (auto-sources utils chain)
#
# Outputs:     output/zip_stability_counts_YYYYMMDD.xlsx  (xlsx assembly is
#                Plan 04 -- this plan produces console-verifiable stats only)
#              (Console) Row counts, drop counts, Part A-01..A-05 headline stats
#
# Dependencies: R/00_config.R (auto-sources utils_duckdb, utils_dates,
#               utils_address, utils_cancer, utils_treatment; provides CONFIG)
#               dplyr, glue, stringr, tidyr, openxlsx2, tibble, lubridate, vroom
#               vroom (primary CSV loader; base read.csv fallback)
#
# Requirements: Phase 139 -- A-01, A-02, A-03, A-04, A-05
#
# Usage:       Rscript R/115_zip_stability_counts.R
#              source("R/115_zip_stability_counts.R")
#
# Note:        READ-ONLY investigation. Structural verification is runnable
#              locally on Windows (grep-based checks / parse-only). Runtime --
#              loading the CSV, opening DuckDB, and computing ZIP metrics --
#              requires HiPerGator with LDS_ADDRESS_HISTORY and the ENCOUNTER
#              table present. This script does NOT modify any pipeline output
#              or config.
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP AND LIBRARIES ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(tidyr)
  library(openxlsx2)
  library(tibble)
  library(lubridate)
  library(vroom)
})

source("R/00_config.R")   # auto-sources utils (parse_pcornet_date, is_sentinel_zip5, etc.)

message("=== Phase 139: ZIP Stability and Imputation Occurrence Counts ===")


# ==============================================================================
# SECTION 1B: TESTABLE CORE FUNCTIONS ----
# ==============================================================================
# Pure functions only (synthetic input -> output, no I/O). Defined here, before
# the probe gate (SECTION 2), so tests/testthat/test-115-validation-curve.R can
# source this file into a fresh environment and capture these definitions even
# when LDS_ADDRESS_HISTORY is absent (139-05-PATCH FIX-05). Do not add anything
# here that reads a file, opens a DB connection, or depends on script-level data
# (addr_coal, encounters, etc.) except via its own arguments.
#
# Populated across this phase's plans:
#   139-01 (this plan): coalesce_zip5()
#   139-02:              build_validation_cases(), aggregate_validation_curve()
#   139-03:              classify_encounter_zip()
#   139-04:              compute_c02()

coalesce_zip5 <- function(df) {
  df %>%
    mutate(
      zip9_norm      = normalize_zip9(ADDRESS_ZIP9),
      zip5_from_zip9 = normalize_zip5(zip9_norm),
      zip5_from_col  = normalize_zip5_raw(ADDRESS_ZIP5),
      zip5_coalesced = if_else(!is.na(zip5_from_col), zip5_from_col, zip5_from_zip9)
    )
}


# ==============================================================================
# SECTION 2: CONSTANTS AND DUAL PROBE GATE ----
# ==============================================================================

ADDR_FILENAME <- "LDS_ADDRESS_HISTORY_Mailhot_V1.csv"
OUTPUT_XLSX   <- file.path(CONFIG$output_dir, glue("zip_stability_counts_{format(Sys.Date(), '%Y%m%d')}.xlsx"))
addr_path     <- file.path(CONFIG$data_dir, ADDR_FILENAME)

# Study/data-collection period for LDS_ADDRESS_HISTORY dates. Reuse R/106's
# exact bounds -- do not invent new ones.
ZIP_STUDY_PERIOD_MIN <- as.Date("2012-01-01")
ZIP_STUDY_PERIOD_MAX <- as.Date("2025-03-31")

# 139-05-PATCH FIX-04b: named alias for the data-extraction-date proxy used to
# cap open-ended exposure spans (see SECTION 5). A separate name, not a new
# value, so the intent at each call site is self-documenting.
DATA_THROUGH <- ZIP_STUDY_PERIOD_MAX

# 139-05-PATCH FIX-02: far-future sentinel used for INTERVAL-MATCHING purposes
# ONLY -- NOT for span/exposure math, which uses DATA_THROUGH instead (a
# sentineled end date would make every open-ended patient's span ~7970 years
# and drive every rate toward zero).
PERIOD_END_SENTINEL <- as.Date("9999-12-31")

message(glue("  CSV probe: {addr_path}"))
message(glue("  File exists? {file.exists(addr_path)}"))

# Probe gate 1 (CSV): copy verbatim from R/106 lines 95-115, adapt message
# prefix to [R/115]. Makes local Windows structural-only verification safe.
if (!file.exists(addr_path)) {
  message(glue(
    "\n[R/115] LDS_ADDRESS_HISTORY not found at expected path.\n",
    "  Expected: {addr_path}\n",
    "  This table is NOT in the permanent PCORNET_TABLES load set.\n",
    "  Confirm the exact filename with the data custodian and re-run on HiPerGator.\n",
    "  Phase 139 investigation requires HiPerGator with this file present.\n",
    "  If the file is named differently, update ADDR_FILENAME at the top of this script.\n"
  ))
  if (identical(environment(), globalenv())) {
    quit(status = 0)
  } else {
    stop("[R/115] LDS_ADDRESS_HISTORY not found -- skipped (not a real failure; see message above)", call. = FALSE)
  }
}

# Probe gate 2 (ENCOUNTER availability): this script also needs the ENCOUNTER
# table (used starting Plan 03 of this phase), but declare the requirement
# here so a HiPerGator run fails fast and consistently rather than partway
# through. Only reached after probe gate 1 has already passed, so a Windows
# structural run never reaches this line (DuckDB is not expected to be
# available locally, consistent with R/111's header note).
USE_DUCKDB <- TRUE
if (!exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}


# ==============================================================================
# SECTION 3: LOAD LDS_ADDRESS_HISTORY AND BUILD COALESCED ADDRESS TABLE ----
# ==============================================================================

message("--- Loading LDS_ADDRESS_HISTORY ---")

addr_raw <- tryCatch(
  vroom::vroom(addr_path, col_types = vroom::cols(.default = "c"), progress = FALSE),
  error = function(e) {
    message(glue("  vroom failed ({conditionMessage(e)}); falling back to read.csv"))
    read.csv(addr_path, colClasses = "character", na.strings = c("", "NA"))
  }
)

n_rows <- nrow(addr_raw)
message(glue("  Rows loaded: {n_rows}"))

n_patients_raw <- n_distinct(addr_raw$ID)
message(glue("  Distinct patients (ID): {n_patients_raw}"))

# Validate required columns (ID not PATID; ADDRESS_ZIP9 required)
required_cols <- c("ID", "ADDRESS_ZIP9")
missing_cols <- setdiff(required_cols, names(addr_raw))
if (length(missing_cols) > 0) {
  stop(glue(
    "[R/115] Required column(s) missing from {ADDR_FILENAME}: {paste(missing_cols, collapse=', ')}\n",
    "  Available columns: {paste(names(addr_raw), collapse=', ')}"
  ))
}

# 139-05-PATCH FIX-04a -- ADDRESS_ZIP5 branch is this phase's single point of
# failure. Do NOT silently degrade to derived-from-ZIP9-only when the raw
# column is absent -- that is the exact state this phase exists to escape.
has_raw_zip5 <- "ADDRESS_ZIP5" %in% names(addr_raw)
message(glue("[R/115] raw ADDRESS_ZIP5 column {if (has_raw_zip5) 'FOUND' else 'NOT FOUND'}"))
if (!has_raw_zip5) {
  message("[R/115] Without a raw ZIP5 column, ZIP5 can only be derived from ZIP9 and every ",
          "ZIP5-only record remains invisible. This phase's premise does not hold. ",
          "Print names(addr_raw), identify the correct source column, and re-run.")
  print(names(addr_raw))
  quit(status = 0)
}

# Build addr_coal, the reusable coalesced-address tibble used by ALL later
# plans in this phase (Plan 02/03/04 read this variable's column contract from
# this task's SUMMARY -- do not rename these columns). Call SECTION 1B's
# coalesce_zip5() rather than re-deriving the same logic. period_start_dt /
# period_end_dt are parsed WITHOUT a sentinel here -- period_end_dt keeps NA
# for open-ended records; the sentinel is applied in a SEPARATE follow-up
# mutate below (139-05-PATCH FIX-02) so period_end_open can distinguish
# "genuinely open-ended" from "already coalesced".
addr_coal <- coalesce_zip5(addr_raw) %>%
  mutate(
    period_start_dt = parse_pcornet_date(ADDRESS_PERIOD_START),
    period_end_dt   = parse_pcornet_date(ADDRESS_PERIOD_END)   # NA preserved -- do NOT coalesce here
  )

# Log the ZIP5 column-vs-derived mismatch count the same way R/106 does --
# data-quality awareness, not a filter.
n_mismatch <- sum(
  !is.na(addr_coal$zip5_from_col) & !is.na(addr_coal$zip5_from_zip9) &
    addr_coal$zip5_from_col != addr_coal$zip5_from_zip9,
  na.rm = TRUE
)
message(glue("  ZIP5 column vs derived mismatch: {n_mismatch} records"))

# 139-05-PATCH FIX-02 / FIX-04b -- open-ended interval sentinel. period_end_eff
# is what every INTERVAL-MATCHING consumer (Plan 03's classify_encounter_zip())
# filters against; period_end_dt itself stays NA-preserving so period_end_open
# remains meaningful and so Task 3's exposure-span math (which must NOT use
# the far-future sentinel directly) can tell the difference.
addr_coal <- addr_coal %>%
  mutate(
    period_end_open = is.na(period_end_dt),
    period_end_eff  = coalesce(period_end_dt, PERIOD_END_SENTINEL)
  )

message(glue("[R/115] {sum(addr_coal$period_end_open)} address record(s) are open-ended ",
             "(NA period_end_dt); treated as current through {PERIOD_END_SENTINEL} for interval ",
             "matching (period_end_eff). Report this count on the QC sheet (Plan 04) -- if it is ",
             "zero, verify against the raw file before trusting it; an address history with no ",
             "open intervals is unusual and more likely indicates end dates were imputed upstream."))

# Unparseable-date drop count (Pitfall 3): a missing START date is unrelated
# to an open END date, so period_end_dt/period_end_open/period_end_eff are
# unaffected by this filter.
n_unparseable_dates <- sum(is.na(addr_coal$period_start_dt))
message(glue("  Rows dropped for unparseable period_start_dt: {n_unparseable_dates}"))

addr_coal <- addr_coal %>%
  filter(!is.na(period_start_dt))

# Sentinel filtering (Pitfall 2, uses Task 1's is_sentinel_zip5()): null out
# (set to NA) any zip9_norm whose first-5-digit prefix is sentinel, and any
# zip5_coalesced that is itself sentinel. Count and message() each BEFORE
# nulling.
n_zip9_sentinel_nulled <- sum(!is.na(addr_coal$zip9_norm) & is_sentinel_zip5(substr(addr_coal$zip9_norm, 1, 5)), na.rm = TRUE)
n_zip5_sentinel_nulled <- sum(!is.na(addr_coal$zip5_coalesced) & is_sentinel_zip5(addr_coal$zip5_coalesced), na.rm = TRUE)

message(glue("  ZIP9 records sentinel-nulled (00000/99999/repeated-digit prefix): {n_zip9_sentinel_nulled}"))
message(glue("  ZIP5 records sentinel-nulled (00000/99999/repeated-digit): {n_zip5_sentinel_nulled}"))

addr_coal <- addr_coal %>%
  mutate(
    zip9_norm      = if_else(!is.na(zip9_norm) & is_sentinel_zip5(substr(zip9_norm, 1, 5)), NA_character_, zip9_norm),
    zip5_coalesced = if_else(!is.na(zip5_coalesced) & is_sentinel_zip5(zip5_coalesced), NA_character_, zip5_coalesced)
  )

# Out-of-study-period guard (same as R/106 Section 9) BEFORE any gap/transition
# math in Task 3, logging the drop count the same way R/106 does.
n_period_start_out_of_range <- sum(
  addr_coal$period_start_dt < ZIP_STUDY_PERIOD_MIN |
    addr_coal$period_start_dt > ZIP_STUDY_PERIOD_MAX
)
message(glue(
  "  Rows dropped for period_start_dt outside study period ",
  "({ZIP_STUDY_PERIOD_MIN} to {ZIP_STUDY_PERIOD_MAX}): {n_period_start_out_of_range}"
))

addr_coal <- addr_coal %>%
  filter(
    period_start_dt >= ZIP_STUDY_PERIOD_MIN,
    period_start_dt <= ZIP_STUDY_PERIOD_MAX
  )

# Keep addr_coal (post-filtering, still one row per original address record --
# spell collapsing happens in Task 3) AND addr_raw (unfiltered, needed by
# Plan 04's C-02 pre-filter comparison -- do not rm() it).
message(glue(
  "[R/115] addr_coal retained {nrow(addr_coal)} of {n_rows} rows after filtering. ",
  "Drop counts -- unparseable dates: {n_unparseable_dates}, out-of-range dates: {n_period_start_out_of_range}, ",
  "ZIP9 sentinel-nulled: {n_zip9_sentinel_nulled}, ZIP5 sentinel-nulled: {n_zip5_sentinel_nulled}, ",
  "open-ended (period_end_open) records among retained rows: {sum(addr_coal$period_end_open)}."
))
