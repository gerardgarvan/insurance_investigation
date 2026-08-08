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
#   139-01: coalesce_zip5()
#   139-02: build_validation_cases(), aggregate_validation_curve()
#   139-03: classify_encounter_zip()
#   140-04: assign_scenarios()
#   140-09: compute_c02_baseline()
#   139-04: compute_c02()

coalesce_zip5 <- function(df) {
  df %>%
    mutate(
      zip9_norm      = normalize_zip9(ADDRESS_ZIP9),
      zip5_from_zip9 = normalize_zip5(zip9_norm),
      zip5_from_col  = normalize_zip5_raw(ADDRESS_ZIP5),
      zip5_coalesced = if_else(!is.na(zip5_from_col), zip5_from_col, zip5_from_zip9)
    )
}

build_validation_cases <- function(addr_coal) {
  # 139-05-PATCH FIX-01 (F1): hold out one address RECORD, not a spell -- predict it from the
  # most recent PRIOR record with a non-NA ZIP9, the same rule get_zip9_at_date() applies.
  # Operates on addr_coal, NOT zip9_seq: spell-collapsing removes exactly the unchanged-address
  # cases carry-forward is supposed to get right, leaving only failures in the test population.
  holdout_base <- addr_coal %>%
    filter(!is.na(zip9_norm), !is.na(period_start_dt)) %>%
    arrange(ID, period_start_dt, desc(period_end_eff))

  validation_cases <- holdout_base %>%
    group_by(ID) %>%
    mutate(
      predicted_zip9  = lag(zip9_norm),         # prior RECORD -- may repeat the same address
      predicted_start = lag(period_start_dt),
      gap_days        = as.numeric(period_start_dt - predicted_start)
    ) %>%
    ungroup() %>%
    filter(!is.na(predicted_zip9))

  validation_cases %>%
    mutate(
      exact_match = predicted_zip9 == zip9_norm,
      zip5_match  = substr(predicted_zip9, 1, 5) == substr(zip9_norm, 1, 5),
      gap_bin = case_when(
        gap_days == 0   ~ "0 (same-day)",   # version corrections, not elapsed-time tests
        gap_days <= 30  ~ "0-30",           # redefined: 1 <= gap_days <= 30 (same-day split out)
        gap_days <= 90  ~ "31-90",
        gap_days <= 180 ~ "91-180",
        gap_days <= 365 ~ "181-365",
        TRUE            ~ "366+"
      )
    )
}

aggregate_validation_curve <- function(validation_cases) {
  bin_levels <- c("0 (same-day)", "0-30", "31-90", "91-180", "181-365", "366+")
  curve <- validation_cases %>%
    mutate(gap_bin = factor(gap_bin, levels = bin_levels)) %>%
    group_by(gap_bin, .drop = FALSE) %>%
    summarise(
      n_cases = n(),
      pct_exact_zip9_match = round(100 * mean(exact_match), 1),
      pct_same_zip5_match  = round(100 * mean(zip5_match), 1),
      .groups = "drop"
    ) %>%
    mutate(gap_bin = as.character(gap_bin))

  overall_row <- tibble(
    gap_bin = "Overall",
    n_cases = nrow(validation_cases),
    pct_exact_zip9_match = round(100 * mean(validation_cases$exact_match), 1),
    pct_same_zip5_match  = round(100 * mean(validation_cases$zip5_match), 1)
  )

  bind_rows(curve, overall_row)
}

classify_encounter_zip <- function(encounters, addr_coal) {
  # 139-05-PATCH FIX-04c: semi_join pre-filter is now the DEFAULT (not conditional on
  # profiling) -- it is free, strictly reducing, and the many-to-many join below is the
  # largest operation in the script.
  addr_pref <- addr_coal %>%
    semi_join(encounters, by = "ID") %>%
    select(ID, zip9_norm, zip5_coalesced, period_start_dt, period_end_eff)

  # 139-05-PATCH FIX-02: filter against period_end_eff (sentineled), NOT period_end_dt
  # (NA-preserving for open-ended records). ADMIT_DATE < NA evaluates to NA and filter() drops
  # NA rows -- under a period_end_dt-based filter, EVERY encounter covered by an open-ended
  # (current) address record is misclassified as has_neither.
  top1 <- encounters %>%
    left_join(addr_pref, by = "ID", relationship = "many-to-many") %>%
    filter(period_start_dt <= ADMIT_DATE, ADMIT_DATE < period_end_eff) %>%
    group_by(ID, ENCOUNTERID, ADMIT_DATE) %>%
    arrange(is.na(zip9_norm), desc(period_start_dt), .by_group = TRUE) %>%
    slice(1) %>%
    ungroup() %>%
    mutate(has_covering_record = TRUE) %>%
    select(ID, ENCOUNTERID, ADMIT_DATE, direct_zip9 = zip9_norm, direct_zip5 = zip5_coalesced, has_covering_record)

  encounters %>%
    left_join(top1, by = c("ID", "ENCOUNTERID", "ADMIT_DATE")) %>%
    mutate(
      has_covering_record   = coalesce(has_covering_record, FALSE),
      has_direct_zip9       = !is.na(direct_zip9),
      has_direct_zip5_only  = is.na(direct_zip9) & !is.na(direct_zip5),
      # 139-05-PATCH FIX-04e: "no covering record exists" and "a covering record exists with
      # both fields NA" are different data conditions -- the notes' S2 presumes a record
      # exists. Split rather than conflate; has_neither remains their union.
      has_no_record         = !has_covering_record,
      has_record_but_empty  = has_covering_record & is.na(direct_zip9) & is.na(direct_zip5),
      has_neither            = has_no_record | has_record_but_empty
    )
}

# 140-04 P-06b (140-08-PATCH FIX-03: coherent only because D-2 = option-a, ZIP5 as analysis
# unit, decided in 140-02): S1 is folded into S3 UNIVERSALLY in the ordered assignment -- S1
# buys only 1.7pp and is definitionally entangled with S3 (an encounter eligible only via
# S1-forward is assigned S1 by the old ordered rule while remaining S3-eligible under S3's own
# complement-of-S1-backward definition). s1_backward/s1_forward/s1_either/s2_backward/
# s2_forward/s2_either/s3_eligible are all UNCHANGED by this fold -- SECTION 11 still computes
# them exactly as before, feeding B_direction_split's unordered reporting. Parameterized
# backward_only controls only the S2 test (s2_either vs s2_backward); the S3 test
# (has_direct_zip5_only, the FULL set, not the narrower s3_eligible) is identical in both
# modes since S3 is inherently backward-only already. This is the single reversible site if
# D-2 is later reconsidered.
assign_scenarios <- function(encounter_zip_flagged, backward_only = FALSE) {
  encounter_zip_flagged %>%
    mutate(
      .s2_test = if (backward_only) s2_backward else s2_either,
      scenario_assigned = case_when(
        has_direct_zip9       ~ "already_has_zip9",
        .s2_test              ~ "S2",
        has_direct_zip5_only  ~ "S3",   # 140-04 P-06b: S1 folded into S3 universally, no separate ordered bucket
        TRUE                   ~ "unresolvable"
      ),
      scenario_assigned = factor(scenario_assigned,
        levels = c("already_has_zip9", "S2", "S3", "unresolvable"))
    ) %>%
    select(-.s2_test)
}

# 140-09-PATCH FIX-17: pre-coalesce baseline -- raw ADDRESS_ZIP5 only, no ZIP9-derived
# fallback. normalize_zip5_raw() is called, not modified (Out of Scope, 140-CONTEXT.md
# Section 11). Restricted to cohort patients PRESENT in addr_raw so the result is
# directly comparable to compute_c02()'s post-coalesce n_present_no_usable_zip5 -- cohort
# patients entirely absent from addr_raw are a coverage question (pct_cohort_with_any_address,
# reported only per D-5, resolved 2026-08-07), not this function's business.
compute_c02_baseline <- function(cohort_ids, addr_raw) {
  base_tbl <- addr_raw %>%
    mutate(.zip5_raw_only = normalize_zip5_raw(ADDRESS_ZIP5)) %>%
    group_by(ID) %>%
    summarise(has_any_zip5 = any(!is.na(.zip5_raw_only)), .groups = "drop")

  present_ids <- intersect(cohort_ids, addr_raw$ID)

  tibble(ID = present_ids) %>%
    left_join(base_tbl, by = "ID") %>%
    mutate(has_any_zip5 = coalesce(has_any_zip5, FALSE)) %>%
    summarise(n = sum(!has_any_zip5)) %>%
    pull(n)
}

compute_c02 <- function(cohort_ids, addr_coal) {
  # 139-05-PATCH FIX-03b: C-02 is computed over the STUDY COHORT (cohort_ids), not over
  # addr_coal's own patient set -- a cohort patient with ZERO rows in addr_coal (dropped by
  # Plan 01's study-period/unparseable-date filters, or never present in
  # LDS_ADDRESS_HISTORY at all) must count toward "no usable ZIP5 ever", not be invisible to
  # group_by(). left_join() + coalesce(FALSE) (not an inner join / semi_join) is what makes
  # that absence visible.
  zip5_ever <- addr_coal %>%
    group_by(ID) %>%
    summarise(has_any_zip5 = any(!is.na(zip5_coalesced)), .groups = "drop")

  c02_tbl <- tibble(ID = cohort_ids) %>%
    left_join(zip5_ever, by = "ID") %>%
    mutate(has_any_zip5 = coalesce(has_any_zip5, FALSE))   # absent from addr_coal => no ZIP5

  n_no_zip5_ever     <- sum(!c02_tbl$has_any_zip5)
  n_absent_from_addr <- sum(!(cohort_ids %in% addr_coal$ID))

  list(
    c02_tbl = c02_tbl,
    n_patients_no_zip5_ever   = n_no_zip5_ever,
    n_cohort_absent_from_addr = n_absent_from_addr,
    # 140-01 P-01a: patients who DO have at least one addr_coal row but none carry a usable
    # ZIP5 -- the only population a genuine ZIP5-coalescing defect could actually produce.
    # Arithmetic on the two values already returned above, not a second group_by/summarise.
    n_present_no_usable_zip5 = n_no_zip5_ever - n_absent_from_addr
  )
}

# 140-03 P-02a (refactored per 140-08-PATCH FIX-13): classify_unparseable_dates_vec() is the
# vectorised per-element classifier (reused directly by SECTION 3's top-20-raw-value examples
# table); classify_unparseable_dates() is a thin counting wrapper around it. Categories mirror
# parse_pcornet_date()'s own blank-handling list (utils_dates.R lines 58-60) so
# "recognized-as-blank" (already handled, not a parser gap) is distinguished from
# "attempted-and-failed" (a genuine parser gap or genuinely bad data).
classify_unparseable_dates_vec <- function(raw_values) {
  is_blank <- is.na(raw_values) |
    raw_values %in% c("", "NULL", "null", ".") |
    str_detect(coalesce(raw_values, "NA_PLACEHOLDER"), "^\\s*$")
  is_blank[is.na(raw_values)] <- TRUE

  case_when(
    is_blank ~ "blank_or_null",
    str_detect(raw_values, "^[0-9/\\-: ]+$") ~ "numeric_looking_but_invalid",
    str_detect(raw_values, "[A-Za-z]") ~ "text_looking_but_invalid",
    TRUE ~ "other_unrecognized"
  )
}

classify_unparseable_dates <- function(raw_values) {
  tibble(category = classify_unparseable_dates_vec(raw_values)) %>%
    count(category, name = "n") %>%
    arrange(desc(n))
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

# 140-03 P-02a/P-02b (140-08-PATCH FIX-13): capture and classify the raw ADDRESS_PERIOD_START
# strings BEFORE the filter below drops them, so the failure-mode breakdown and the top-20
# most frequent raw values per category are available from a single HiPerGator run.
unparseable_raw_sample <- addr_coal$ADDRESS_PERIOD_START[is.na(addr_coal$period_start_dt)]
unparseable_date_breakdown <- classify_unparseable_dates(unparseable_raw_sample)

# 140-08-PATCH FIX-13: counts alone cannot answer P-02b -- carry the actual strings so
# the parser-extension decision can be made from one run, not two. LDS_ADDRESS_HISTORY
# is a Limited Data Set, so raw date strings are permitted in the workbook; cap at 20
# per category regardless.
unparseable_date_examples <- tibble(raw_value = unparseable_raw_sample) %>%
  mutate(category = classify_unparseable_dates_vec(raw_value)) %>%
  count(category, raw_value, name = "n") %>%
  group_by(category) %>%
  slice_max(n, n = 20, with_ties = FALSE) %>%
  ungroup() %>%
  arrange(category, desc(n))

message("--- Unparseable period_start_dt breakdown (P-02a) ---")
print(unparseable_date_breakdown)
message(glue(
  "[R/115] Whether any category above is RECOVERABLE via extending parse_pcornet_date() (P-02b) is a ",
  "follow-up decision requiring review of this REAL breakdown from a HiPerGator run -- not resolved by ",
  "this script. If 'numeric_looking_but_invalid' or 'text_looking_but_invalid' account for a material ",
  "share, inspect unparseable_date_examples (top-20 raw values per category, on the QC sheet) directly ",
  "and consider extending R/utils/utils_dates.R's parse_pcornet_date() (out of scope for this plan)."
))

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


# ==============================================================================
# SECTION 4: SPELL DEDUP AND PER-PATIENT TRANSITION METRICS (A-01, A-02, A-03) ----
# ==============================================================================

message("--- Computing ZIP9/ZIP5 spell dedup and transition metrics ---")

# Per A-02, ZIP9 and ZIP5 transitions are computed on TWO INDEPENDENT
# sequences per patient: drop NA rows for that ZIP-type FIRST (not carried
# through as gaps), THEN collapse consecutive-identical values into spells
# (A-03). A 32611-1234 -> NA -> 32611-1234 sequence collapses to a single
# spell (zero transitions) because the NA row is dropped before dedup, not
# treated as a distinct value.
#
# Tie-break rule (Pitfall 5): order by (ID, period_start_dt ascending); when
# two rows share the same period_start_dt, prefer the one with the LATER
# period_end_eff (the more "current"/authoritative version of that period).
# 139-05-PATCH FIX-02: use period_end_eff, not period_end_dt, for this
# tie-break -- period_end_dt can be NA (open-ended records are no longer
# pre-sentineled at parse time), and dplyr::arrange() always sorts NA last
# regardless of asc/desc, which would silently reverse the intended
# "prefer more current" rule for exactly the open-ended records this
# tie-break exists to prioritize. period_end_eff (sentineled) sorts correctly.

zip9_seq <- addr_coal %>%
  filter(!is.na(zip9_norm)) %>%
  arrange(ID, period_start_dt, desc(period_end_eff)) %>%
  group_by(ID) %>%
  mutate(is_new_spell = row_number() == 1 | zip9_norm != lag(zip9_norm)) %>%
  filter(is_new_spell) %>%
  ungroup()

zip5_seq <- addr_coal %>%
  filter(!is.na(zip5_coalesced)) %>%
  arrange(ID, period_start_dt, desc(period_end_eff)) %>%
  group_by(ID) %>%
  mutate(is_new_spell = row_number() == 1 | zip5_coalesced != lag(zip5_coalesced)) %>%
  filter(is_new_spell) %>%
  ungroup()

# Per-patient A-01 metrics: n_distinct_zip9/zip5, n_zip9/zip5_transitions
# (spell count - 1, floored at 0).
zip9_patient_stats <- zip9_seq %>%
  group_by(ID) %>%
  summarise(
    n_distinct_zip9 = n_distinct(zip9_norm),
    n_spells_zip9   = n(),
    .groups = "drop"
  ) %>%
  mutate(n_zip9_transitions = pmax(n_spells_zip9 - 1L, 0L))

zip5_patient_stats <- zip5_seq %>%
  group_by(ID) %>%
  summarise(
    n_distinct_zip5 = n_distinct(zip5_coalesced),
    n_spells_zip5   = n(),
    .groups = "drop"
  ) %>%
  mutate(n_zip5_transitions = pmax(n_spells_zip5 - 1L, 0L))

# n_plus4_only_transitions: for each patient's zip9_seq (already spell-
# deduped, so every row after the first IS a transition by construction),
# count consecutive spell pairs where the ZIP5 prefix did NOT change --
# i.e. the ZIP9 changed but the ZIP5 prefix did not. zip9_seq's row order
# within each ID group is already (period_start_dt asc, period_end_eff desc)
# from the arrange() above; grouping again preserves that order, so no
# re-arrange is needed here.
plus4_only_stats <- zip9_seq %>%
  group_by(ID) %>%
  mutate(
    is_plus4_only_transition = row_number() > 1 &
      substr(zip9_norm, 1, 5) == substr(lag(zip9_norm), 1, 5)
  ) %>%
  summarise(n_plus4_only_transitions = sum(is_plus4_only_transition, na.rm = TRUE), .groups = "drop")

# Patients with zero valid ZIP9/ZIP5 records anywhere (dropped entirely by
# the filter(!is.na(...)) above) get 0 for all above metrics, matching
# R/106 Section 6's "all_ids" pattern -- do not silently omit them from
# patient_stability, since C-02's reconciliation later in this phase needs
# the FULL patient universe including these.
all_ids <- tibble(ID = unique(addr_coal$ID))

patient_stability <- all_ids %>%
  left_join(zip9_patient_stats %>% select(ID, n_distinct_zip9, n_zip9_transitions), by = "ID") %>%
  left_join(zip5_patient_stats %>% select(ID, n_distinct_zip5, n_zip5_transitions), by = "ID") %>%
  left_join(plus4_only_stats, by = "ID") %>%
  mutate(
    n_distinct_zip9          = replace_na(n_distinct_zip9, 0L),
    n_zip9_transitions       = replace_na(n_zip9_transitions, 0L),
    n_distinct_zip5          = replace_na(n_distinct_zip5, 0L),
    n_zip5_transitions       = replace_na(n_zip5_transitions, 0L),
    n_plus4_only_transitions = replace_na(n_plus4_only_transitions, 0L)
  )

n_patients_total <- nrow(patient_stability)
message(glue("  n_patients_total (patient_stability): {n_patients_total}"))


# ==============================================================================
# SECTION 5: EXPOSURE DENOMINATOR (A-04) ----
# ==============================================================================

message("--- Computing per-patient exposure denominator ---")

# Per patient, observation span in years, computed over ALL of addr_coal
# (not just the ZIP9/ZIP5 sequences -- this is about how long the patient
# was observed, not how many ZIP values they had).
#
# 139-05-PATCH FIX-04b: max(period_start_dt) - min(period_start_dt) (the
# naive formula) ignores period_end entirely -- a patient with two records
# 30 days apart, the second of which runs open-ended for ten years, would
# get a 30-day span and a wildly inflated transitions-per-year rate. Use
# period_end_eff instead, but NOT the FIX-02 far-future sentinel directly --
# a sentineled end date makes every open-ended patient's span ~7970 years
# and drives every rate toward zero, the opposite failure. Cap at
# DATA_THROUGH (an alias for ZIP_STUDY_PERIOD_MAX, the data-extraction-date
# proxy) before taking the max.
exposure <- addr_coal %>%
  group_by(ID) %>%
  summarise(
    obs_span_days = as.numeric(max(pmin(period_end_eff, DATA_THROUGH)) - min(period_start_dt)),
    .groups = "drop"
  ) %>%
  mutate(obs_span_years = obs_span_days / 365.25)

patient_stability <- patient_stability %>%
  left_join(exposure, by = "ID") %>%
  mutate(
    # Guard: patients with exactly one address record (obs_span_days == 0)
    # get NA_real_, NOT Inf or 0 -- a single record is absence of
    # observation, not evidence of stability (A-04's explicit point).
    zip9_transitions_per_patient_year = if_else(
      obs_span_years > 0, n_zip9_transitions / obs_span_years, NA_real_
    )
  )

obs_span_summary <- tibble(
  Metric = c("Median obs_span_years", "p25 obs_span_years", "p75 obs_span_years"),
  Value  = as.character(c(
    round(median(patient_stability$obs_span_years, na.rm = TRUE), 2),
    round(quantile(patient_stability$obs_span_years, 0.25, na.rm = TRUE), 2),
    round(quantile(patient_stability$obs_span_years, 0.75, na.rm = TRUE), 2)
  ))
)

message(glue("  Median obs_span_years: {obs_span_summary$Value[1]}"))


# ==============================================================================
# SECTION 6: TIME BETWEEN CHANGES (A-05) ----
# ==============================================================================

message("--- Computing gap-time distribution between ZIP9 changes ---")

# Adapt R/106 Section 9's gap-day computation but operate on zip9_seq's
# period_start_dt directly (spells are ALREADY deduped from Section 4 above --
# do not re-derive from addr_coal from scratch, that would duplicate work
# and risk a different tie-break rule from Section 4's).
gap_rows <- zip9_seq %>%
  group_by(ID) %>%
  arrange(period_start_dt, .by_group = TRUE) %>%
  mutate(gaps_days = as.numeric(difftime(period_start_dt, lag(period_start_dt), units = "days"))) %>%
  ungroup() %>%
  filter(!is.na(gaps_days))

message(glue("  Total ZIP9-change gap observations: {nrow(gap_rows)}"))

gaps_days_vec <- gap_rows$gaps_days

# A-05 explicitly requires "median, IQR, deciles" -- the fixed-bucket
# histogram alone does NOT satisfy that. Deciles are data-driven
# equal-frequency cutpoints (e.g. "90% of gaps are under N days"), distinct
# from the fixed-width buckets below.
gap_days_deciles <- quantile(gaps_days_vec, probs = seq(0.1, 0.9, 0.1), na.rm = TRUE)

# Fixed-bucket histogram -- SAME bucket boundaries as R/106 Section 9
# (<30, 30-180, 181-365, 1-2 years, >2 years); keep consistent with the
# existing precedent rather than inventing new buckets.
gap_days_histogram <- gap_rows %>%
  mutate(bucket = case_when(
    gaps_days < 30  ~ "<30 days",
    gaps_days < 181 ~ "30-180 days",
    gaps_days < 366 ~ "181-365 days",
    gaps_days < 731 ~ "1-2 years",
    TRUE            ~ ">2 years"
  )) %>%
  group_by(bucket) %>%
  summarise(n_gaps = n(), .groups = "drop")

# Assemble median/p25/p75/min/max/gap_days_deciles/histogram into a single
# named object called exactly `gap_days_summary` so Plan 04 can pull it
# directly into the A_stability_summary sheet without re-deriving any of it.
# Includes a labeled (NOT assumed) reference to the diagnosis-episode window
# currently in use (~90 days per the 06/23 notes referenced in
# 139-CONTEXT.md A-05) -- do NOT assume the dx window transfers to ZIP
# behavior; just report it as a labeled reference point.
gap_days_summary <- list(
  n_gap_observations         = nrow(gap_rows),
  median_days                = round(median(gaps_days_vec, na.rm = TRUE), 1),
  p25_days                   = round(quantile(gaps_days_vec, 0.25, na.rm = TRUE), 1),
  p75_days                   = round(quantile(gaps_days_vec, 0.75, na.rm = TRUE), 1),
  min_days                   = round(min(gaps_days_vec, na.rm = TRUE), 1),
  max_days                   = round(max(gaps_days_vec, na.rm = TRUE), 1),
  deciles                    = gap_days_deciles,
  histogram                  = gap_days_histogram,
  reference_dx_window_days   = 90,
  reference_note             = "Reference: diagnosis-episode window (~90 days, NOT assumed to apply to ZIP)"
)

message(glue("  Median gap-days between ZIP9 changes: {gap_days_summary$median_days}"))


# ==============================================================================
# SECTION 7: CONSOLE HEADLINE STATS ----
# ==============================================================================

median_n_zip9_transitions <- median(patient_stability$n_zip9_transitions, na.rm = TRUE)
pct_zero_transition_zip9  <- round(100 * sum(patient_stability$n_zip9_transitions == 0, na.rm = TRUE) / n_patients_total, 1)
total_zip9_transitions    <- sum(patient_stability$n_zip9_transitions, na.rm = TRUE)
total_plus4_only          <- sum(patient_stability$n_plus4_only_transitions, na.rm = TRUE)
pct_plus4_only_of_all     <- if (total_zip9_transitions > 0) {
  round(100 * total_plus4_only / total_zip9_transitions, 1)
} else {
  NA_real_
}
median_obs_span_years <- median(patient_stability$obs_span_years, na.rm = TRUE)

message("\n=== Phase 139: ZIP Stability -- Headline Stats ===")
message(glue("  n_patients_total:                    {n_patients_total}"))
# Pitfall 6: do NOT report a mean here -- median and % zero-transition only.
message(glue("  median n_zip9_transitions:            {median_n_zip9_transitions}"))
message(glue("  % patients with zero ZIP9 transitions: {pct_zero_transition_zip9}%"))
message(glue("  n_plus4_only_transitions as % of all ZIP9 transitions: {pct_plus4_only_of_all}%"))
message(glue("  median obs_span_years:                {median_obs_span_years}"))
message(glue("  median gap-days between ZIP9 changes: {gap_days_summary$median_days}"))
message("===================================================\n")


# ==============================================================================
# SECTION 8: A-06 CARRY-FORWARD VALIDATION CURVE ----
# ==============================================================================
# 139-05-PATCH FIX-01 (F1): hold-out test operates on addr_coal RECORDS
# (address-history universe, per Pitfall 1), not zip9_seq spells. See SECTION
# 1B's build_validation_cases()/aggregate_validation_curve() for the pure-
# function implementation (this section calls them against the real,
# script-level addr_coal).

message("--- Computing A-06 carry-forward validation curve ---")

validation_cases <- build_validation_cases(addr_coal)

n_excluded_no_prior <- addr_coal %>%
  filter(!is.na(zip9_norm), !is.na(period_start_dt)) %>%
  pull(ID) %>% n_distinct() - n_distinct(validation_cases$ID)
message(glue("A-06: {n_excluded_no_prior} patients excluded from hold-out test (single usable record, no prior to predict from)"))
message(glue("A-06: {nrow(validation_cases)} hold-out test cases across {n_distinct(validation_cases$ID)} patients"))

# 139-05-PATCH FIX-01 reporting additions:
pct_unchanged <- round(100 * mean(validation_cases$exact_match), 1)
n_same_day    <- sum(validation_cases$gap_days == 0, na.rm = TRUE)
message(glue("A-06: {pct_unchanged}% of test cases were unchanged-address (base rate the curve measures against)"))
message(glue("A-06: {n_same_day} same-day record pairs (gap_days == 0) -- reported in their own bin, not folded into 0-30"))

# Block-group tier probe (done once, before calling aggregate_validation_curve()).
# Neighborhood Atlas crosswalk file: confirmed absent from this repo as of
# Phase 139 planning (see 139-CONTEXT.md/139-05-PATCH.md). Probe here rather
# than assume -- if a future HiPerGator run has this file, the tier activates
# automatically; if not, it degrades to a documented NA, not an error or a
# silent omission.
NEIGHBORHOOD_ATLAS_PATH <- file.path("data", "reference", "neighborhood_atlas_block_group_crosswalk.csv")
has_block_group_crosswalk <- file.exists(NEIGHBORHOOD_ATLAS_PATH)
message(glue("A-06: Neighborhood Atlas block-group crosswalk {if (has_block_group_crosswalk) 'found' else 'NOT found'} at {NEIGHBORHOOD_ATLAS_PATH}"))

block_group_tier_status <- "not available (crosswalk file not found)"

if (has_block_group_crosswalk) {
  # Load crosswalk (ZIP9 -> block_group_id, one row per ZIP9). Column name
  # expectations are unknown ahead of time -- inspect the header row first and
  # adapt the join key name accordingly. If the expected ZIP9-keyed join
  # produces near-zero matches (a data problem, not a code problem), fall back
  # to reporting the tier as "found but unusable" rather than publishing a
  # misleading near-zero accuracy number.
  crosswalk_raw <- tryCatch(
    vroom::vroom(NEIGHBORHOOD_ATLAS_PATH, col_types = vroom::cols(.default = "c"), progress = FALSE),
    error = function(e) {
      message(glue("A-06: failed to read Neighborhood Atlas crosswalk ({conditionMessage(e)})"))
      NULL
    }
  )

  crosswalk_zip9_col <- NULL
  if (!is.null(crosswalk_raw)) {
    candidate_cols <- intersect(
      c("ZIP9", "zip9", "ADDRESS_ZIP9", "zip9_norm", "GEOID9", "ZIP_PLUS4"),
      names(crosswalk_raw)
    )
    if (length(candidate_cols) > 0) crosswalk_zip9_col <- candidate_cols[1]
  }

  candidate_bg_cols <- if (!is.null(crosswalk_raw)) {
    intersect(c("block_group_id", "block_group", "BLOCK_GROUP", "GEOID_BG", "bg_id"), names(crosswalk_raw))
  } else {
    character(0)
  }
  crosswalk_bg_col <- if (length(candidate_bg_cols) > 0) candidate_bg_cols[1] else NULL

  if (is.null(crosswalk_zip9_col) || is.null(crosswalk_bg_col)) {
    message(glue(
      "A-06: Neighborhood Atlas crosswalk found but expected ZIP9/block-group columns not identified ",
      "(available columns: {if (!is.null(crosswalk_raw)) paste(names(crosswalk_raw), collapse = ', ') else 'NA (read failed)'}). ",
      "Treating block-group tier as found-but-unusable."
    ))
    block_group_tier_status <- "found but unusable (expected ZIP9/block-group columns not identified)"
  } else {
    crosswalk_lookup <- crosswalk_raw %>%
      select(all_of(c(crosswalk_zip9_col, crosswalk_bg_col))) %>%
      rename(zip9_norm = all_of(crosswalk_zip9_col), block_group_id = all_of(crosswalk_bg_col)) %>%
      distinct(zip9_norm, .keep_all = TRUE)

    # 140-08-PATCH FIX-12: match-rate QC row -- how much of the DISTINCT ZIP9 universe
    # actually observed in this run's addr_coal is covered by the crosswalk, not just the
    # validation_cases join outcome computed below (a different, narrower measure). File
    # existence alone is not sufficient evidence the crosswalk is usable.
    BLOCK_GROUP_MATCH_THRESHOLD <- 0.90  # suggested; PENDING TEAM CONFIRMATION (data/reference/README.md)
    n_zip9_distinct_observed        <- n_distinct(addr_coal$zip9_norm[!is.na(addr_coal$zip9_norm)])
    n_zip9_matched_to_block_group   <- n_distinct(intersect(addr_coal$zip9_norm, crosswalk_lookup$zip9_norm))
    pct_zip9_matched_to_block_group <- round(100 * n_zip9_matched_to_block_group / n_zip9_distinct_observed, 1)

    if (n_zip9_matched_to_block_group / n_zip9_distinct_observed < BLOCK_GROUP_MATCH_THRESHOLD) {
      block_group_tier_status <- "found but coverage insufficient"
      message(glue(
        "A-06: Neighborhood Atlas crosswalk match rate ({pct_zip9_matched_to_block_group}%, ",
        "{n_zip9_matched_to_block_group} of {n_zip9_distinct_observed} distinct ZIP9s) is below the ",
        "{BLOCK_GROUP_MATCH_THRESHOLD * 100}% threshold (pending team confirmation, 140-08-PATCH FIX-12) -- ",
        "treating block-group tier as found-but-insufficient-coverage rather than publishing a percentage ",
        "computed on a non-random subset of the data."
      ))
    } else {
      message(glue(
        "A-06: Neighborhood Atlas crosswalk match rate {pct_zip9_matched_to_block_group}% ",
        "({n_zip9_matched_to_block_group} of {n_zip9_distinct_observed} distinct ZIP9s) -- meets the ",
        "{BLOCK_GROUP_MATCH_THRESHOLD * 100}% threshold."
      ))
    }

    validation_cases <- validation_cases %>%
      left_join(crosswalk_lookup %>% rename(predicted_block_group = block_group_id), by = c("predicted_zip9" = "zip9_norm")) %>%
      left_join(crosswalk_lookup %>% rename(actual_block_group = block_group_id), by = c("zip9_norm" = "zip9_norm")) %>%
      mutate(block_group_match = predicted_block_group == actual_block_group)

    n_bg_matched <- sum(!is.na(validation_cases$block_group_match))
    if (n_bg_matched == 0 || n_bg_matched / nrow(validation_cases) < 0.01) {
      message(glue(
        "A-06: Neighborhood Atlas crosswalk join produced near-zero matches ",
        "({n_bg_matched} of {nrow(validation_cases)} cases) -- likely a data problem, not a code ",
        "problem. Treating block-group tier as found-but-unusable rather than publishing a ",
        "misleading near-zero accuracy figure."
      ))
      block_group_tier_status <- "found but unusable (near-zero join match rate)"
      validation_cases$block_group_match <- NA
    } else {
      block_group_tier_status <- "available"
      message(glue("A-06: block-group tier computed ({n_bg_matched} of {nrow(validation_cases)} cases matched to a block group)"))
    }
  }
}


# ==============================================================================
# SECTION 9: A-06 AGGREGATION AND CONSOLE SUMMARY ----
# ==============================================================================

validation_curve <- aggregate_validation_curve(validation_cases)

# If has_block_group_crosswalk is TRUE and the join succeeded, add
# pct_block_group_match the same way (per-bin mean of block_group_match, plus
# the Overall row); if FALSE (or found-but-unusable), add the column filled
# with NA_real_ and rely on the sheet subtitle (Plan 04) to explain why.
if (has_block_group_crosswalk && "block_group_match" %in% names(validation_cases) && block_group_tier_status == "available") {
  bg_by_bin <- validation_cases %>%
    mutate(gap_bin = factor(gap_bin, levels = c("0 (same-day)", "0-30", "31-90", "91-180", "181-365", "366+"))) %>%
    group_by(gap_bin, .drop = FALSE) %>%
    summarise(pct_block_group_match = round(100 * mean(block_group_match, na.rm = TRUE), 1), .groups = "drop") %>%
    mutate(gap_bin = as.character(gap_bin))

  bg_overall <- tibble(
    gap_bin = "Overall",
    pct_block_group_match = round(100 * mean(validation_cases$block_group_match, na.rm = TRUE), 1)
  )

  bg_all <- bind_rows(bg_by_bin, bg_overall)
  validation_curve <- validation_curve %>% left_join(bg_all, by = "gap_bin")
} else {
  validation_curve <- validation_curve %>% mutate(pct_block_group_match = NA_real_)
}

message("\n=== A-06: Carry-Forward Validation Curve (Address-History Universe, Record-Anchored) ===")
print(validation_curve)
message(glue("Block-group tier available: {has_block_group_crosswalk} (status: {block_group_tier_status})"))
message(glue("Base rate (unchanged-address test cases): {pct_unchanged}%  |  Same-day pairs: {n_same_day}"))
message("==========================================================================\n")


# ==============================================================================
# SECTION 10: PART B -- ENCOUNTER-LEVEL ZIP CLASSIFICATION (B-01..B-04) ----
# ==============================================================================
# Pitfall 1: Part B's universe is ENCOUNTERS (one row per (ID, ENCOUNTERID,
# ADMIT_DATE)), NOT address-history records -- distinct from Part A's
# addr_coal-anchored universe above. Do not conflate encounter counts with
# address-record counts when reading console output below.
#
# 139-05-PATCH FIX-03a: Part B's population is the study cohort
# (get_hl_patient_ids(), the pattern already established by R/106/R/111/R/100/
# R/107/R/109) -- reused verbatim here, not re-invented. This is what makes C-02's
# reconciliation (SECTION 12; invariant-based as of 140-09-PATCH FIX-17) cohort-scoped
# and internally consistent.

message("--- Part B: cohort-restricted ENCOUNTER pull + per-encounter ZIP classification ---")

if (!exists("get_hl_patient_ids")) source("R/utils/utils_treatment.R")
COHORT_IDS <- get_hl_patient_ids()
message(glue("[R/115] Study cohort (HL patients) size: {length(COHORT_IDS)}"))

# USE_DUCKDB / pcornet_con already set/opened by SECTION 2's probe gate 2 --
# do not re-open the connection here.
enc_tbl <- get_pcornet_table("ENCOUNTER")
if (is.null(enc_tbl)) stop("ENCOUNTER table not found in DuckDB -- cannot compute Part B scenario counts.")

encounters <- enc_tbl %>%
  filter(!is.na(ADMIT_DATE), ID %in% COHORT_IDS) %>%
  select(ID, ENCOUNTERID, ADMIT_DATE) %>%
  collect() %>%
  mutate(ADMIT_DATE = parse_pcornet_date(ADMIT_DATE)) %>%
  filter(!is.na(ADMIT_DATE))

n_encounters_total <- nrow(encounters)
message(glue("[R/115] Part B: {n_encounters_total} cohort-restricted encounters with a parseable ADMIT_DATE, across {n_distinct(encounters$ID)} patients"))

# classify_encounter_zip() (SECTION 1B) reuses addr_coal directly (NOT
# get_zip9_at_date()) -- see this plan's <interfaces> block for why: coalesced
# ZIP5 needs to stay visible alongside ZIP9 for S1/S3 classification, which
# get_zip9_at_date()'s own derived-only ZIP5 output would mask.
encounter_zip <- classify_encounter_zip(encounters, addr_coal)

n_has_direct_zip9      <- sum(encounter_zip$has_direct_zip9)
n_has_direct_zip5_only <- sum(encounter_zip$has_direct_zip5_only)
n_has_no_record        <- sum(encounter_zip$has_no_record)
n_has_record_but_empty <- sum(encounter_zip$has_record_but_empty)
n_has_neither          <- sum(encounter_zip$has_neither)

message("\n=== Part B: Encounter ZIP-Availability Headline Counts (encounter-level) ===")
message(glue("  n_encounters_total:       {n_encounters_total}"))
message(glue("  has_direct_zip9:          {n_has_direct_zip9} ({round(100 * n_has_direct_zip9 / n_encounters_total, 1)}%)"))
message(glue("  has_direct_zip5_only:     {n_has_direct_zip5_only} ({round(100 * n_has_direct_zip5_only / n_encounters_total, 1)}%)"))
message(glue("  has_no_record:            {n_has_no_record} ({round(100 * n_has_no_record / n_encounters_total, 1)}%)"))
message(glue("  has_record_but_empty:     {n_has_record_but_empty} ({round(100 * n_has_record_but_empty / n_encounters_total, 1)}%)"))
message(glue("  has_neither (union of the above two): {n_has_neither} ({round(100 * n_has_neither / n_encounters_total, 1)}%)"))
message("==========================================================================\n")


# ==============================================================================
# SECTION 11: PART B -- S1-S4 SCENARIO ELIGIBILITY + ORDERED/UNORDERED COUNTS ----
# ==============================================================================
# Forward-lookup logic is new, local code this plan adds -- get_zip9_at_date()
# only looks backward, so the forward variant is implemented here directly
# against zip9_seq/zip5_seq (SECTION 4), not by changing utils_address.R.
# B-01/B-04 ask whether ANY such spell exists on the correct side of
# ADMIT_DATE, not specifically the nearest one (except S2's resolution_path,
# which is reporting-only, computed from the nearest backward spell).

message("--- Part B: S1-S4 scenario eligibility (unordered) + ordered assignment ---")

# ---- S1 eligibility: has_direct_zip5_only AND a zip9_seq spell whose ZIP5 matches direct_zip5 ----
zip5_only_enc <- encounter_zip %>%
  filter(has_direct_zip5_only) %>%
  select(ID, ENCOUNTERID, ADMIT_DATE, direct_zip5)

s1_matches <- zip5_only_enc %>%
  left_join(
    zip9_seq %>% select(ID, zip9_norm, period_start_dt),
    by = "ID", relationship = "many-to-many"
  ) %>%
  filter(!is.na(zip9_norm), substr(zip9_norm, 1, 5) == direct_zip5) %>%
  mutate(direction = if_else(period_start_dt <= ADMIT_DATE, "backward", "forward"))

s1_elig <- zip5_only_enc %>%
  select(ID, ENCOUNTERID, ADMIT_DATE) %>%
  left_join(
    s1_matches %>%
      group_by(ID, ENCOUNTERID, ADMIT_DATE) %>%
      summarise(
        s1_backward = any(direction == "backward"),
        s1_forward  = any(direction == "forward"),
        .groups = "drop"
      ),
    by = c("ID", "ENCOUNTERID", "ADMIT_DATE")
  ) %>%
  mutate(
    s1_backward = coalesce(s1_backward, FALSE),
    s1_forward  = coalesce(s1_forward, FALSE),
    s1_either   = s1_backward | s1_forward
  )

# ---- S2 eligibility: has_neither AND a zip5_seq spell exists (backward/forward/either) ----
# zip5_seq (not zip9_seq) is used because S2 covers BOTH the "take a ZIP9 from another
# encounter" path and the "ZIP5 centroid" path -- any backward zip5_seq spell satisfies at
# least the centroid path. resolution_path is computed for reporting transparency only
# (take_zip9 vs centroid_only), NOT used to gate S2 eligibility itself.
neither_enc <- encounter_zip %>%
  filter(has_neither) %>%
  select(ID, ENCOUNTERID, ADMIT_DATE)

s2_matches <- neither_enc %>%
  left_join(
    zip5_seq %>% select(ID, zip5_coalesced, zip9_norm, period_start_dt),
    by = "ID", relationship = "many-to-many"
  ) %>%
  filter(!is.na(zip5_coalesced)) %>%
  mutate(direction = if_else(period_start_dt <= ADMIT_DATE, "backward", "forward"))

# Nearest backward zip5_seq spell per encounter (resolution_path reporting only).
s2_nearest_backward <- s2_matches %>%
  filter(direction == "backward") %>%
  group_by(ID, ENCOUNTERID, ADMIT_DATE) %>%
  slice_max(period_start_dt, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  mutate(resolution_path = if_else(!is.na(zip9_norm), "take_zip9", "centroid_only")) %>%
  select(ID, ENCOUNTERID, ADMIT_DATE, resolution_path)

s2_elig <- neither_enc %>%
  left_join(
    s2_matches %>%
      group_by(ID, ENCOUNTERID, ADMIT_DATE) %>%
      summarise(
        s2_backward = any(direction == "backward"),
        s2_forward  = any(direction == "forward"),
        .groups = "drop"
      ),
    by = c("ID", "ENCOUNTERID", "ADMIT_DATE")
  ) %>%
  left_join(s2_nearest_backward, by = c("ID", "ENCOUNTERID", "ADMIT_DATE")) %>%
  mutate(
    s2_backward = coalesce(s2_backward, FALSE),
    s2_forward  = coalesce(s2_forward, FALSE),
    s2_either   = s2_backward | s2_forward
    # resolution_path stays NA when no backward zip5_seq spell exists at all (nothing to
    # resolve) -- not coalesced to a placeholder value.
  )

# ---- S3 eligibility (backward only, per S3's own definition): has_direct_zip5_only AND
# NOT s1_backward. S1-backward and S3 are complements within the has_direct_zip5_only set
# by construction -- a ZIP5-only encounter either matches some earlier ZIP9's ZIP5 (S1) or
# it does not (S3). No direction split for S3 -- it is inherently backward-only.
s3_elig <- s1_elig %>%
  mutate(s3_eligible = !s1_backward) %>%
  select(ID, ENCOUNTERID, ADMIT_DATE, s3_eligible)

# Join all eligibility flags onto encounter_zip; encounters outside each scenario's own
# precondition (e.g. not has_direct_zip5_only for S1/S3, not has_neither for S2) get FALSE.
encounter_zip <- encounter_zip %>%
  left_join(s1_elig, by = c("ID", "ENCOUNTERID", "ADMIT_DATE")) %>%
  left_join(s2_elig, by = c("ID", "ENCOUNTERID", "ADMIT_DATE")) %>%
  left_join(s3_elig, by = c("ID", "ENCOUNTERID", "ADMIT_DATE")) %>%
  mutate(
    s1_backward = coalesce(s1_backward, FALSE),
    s1_forward  = coalesce(s1_forward, FALSE),
    s1_either   = coalesce(s1_either, FALSE),
    s2_backward = coalesce(s2_backward, FALSE),
    s2_forward  = coalesce(s2_forward, FALSE),
    s2_either   = coalesce(s2_either, FALSE),
    s3_eligible = coalesce(s3_eligible, FALSE)
  )

# S4 (complete-case comparator, reported separately, NOT part of the ordered assignment):
# complement of has_direct_zip9 -- every encounter that is NOT already-has-ZIP9.
n_s4_excluded_encounters <- sum(!encounter_zip$has_direct_zip9)
n_s4_excluded_patients   <- n_distinct(encounter_zip$ID[!encounter_zip$has_direct_zip9])

# ---- Ordered assignment: S1 folded into S3 (140-04 P-06b, 140-08-PATCH FIX-03: coherent
# only because D-2 = option-a, ZIP5 as analysis unit -- see assign_scenarios(), SECTION 1B) ----
# 140-08-PATCH FIX-09: direct $ assignment -- NOT from inside mutate(), which would reference
# the outer (pre-assignment) encounter_zip from inside its own mutate() call, relying on
# row-order stability between the outer frame and the function's return, and evaluating the
# full tibble twice. Two independent calls: forward-inclusive (s2_either) and backward-only
# (s2_backward), each producing its own scenario_assigned column.
encounter_zip$scenario_assigned <-
  assign_scenarios(encounter_zip, backward_only = FALSE)$scenario_assigned
encounter_zip$scenario_assigned_backward_only <-
  assign_scenarios(encounter_zip, backward_only = TRUE)$scenario_assigned

# NOTE (140-04 P-06b, amended by 140-08-PATCH FIX-04): S1 is no longer a distinct ordered
# bucket -- every has_direct_zip5_only encounter is assigned "S3" regardless of
# S1-eligibility. Unordered s1_backward/s1_forward/s1_either counts remain reported on
# B_direction_split for transparency (reporting-only), but do not correspond to any ordered
# scenario_assigned level any more. The ordered S3 count now EXCEEDS B_direction_split's
# unordered "S3-eligible" count by exactly the S1-backward count (s3_eligible retains its
# complement-of-S1-backward definition) -- see the KEY sheet for the full explanation (Plan 04
# Task 2).
message(glue(
  "NOTE (140-04 P-06b, amended by 140-08-PATCH FIX-04): S1 is no longer a distinct ordered ",
  "bucket -- every has_direct_zip5_only encounter is assigned 'S3' regardless of ",
  "S1-eligibility. Unordered s1_backward/s1_forward/s1_either counts remain reported on ",
  "B_direction_split for transparency (reporting-only), but do not correspond to any ordered ",
  "scenario_assigned level any more. The ordered S3 count now EXCEEDS B_direction_split's ",
  "unordered 'S3-eligible' count by exactly the S1-backward count (s3_eligible retains its ",
  "complement-of-S1-backward definition) -- see the KEY sheet for the full explanation."
))

# ---- Summary table 1: ordered assignment counts (B-03), encounter + patient level ----
n_patients_with_encounters <- n_distinct(encounter_zip$ID)

scenario_counts_encounter <- encounter_zip %>%
  group_by(scenario_assigned, .drop = FALSE) %>%
  summarise(n_encounters = n(), .groups = "drop") %>%
  mutate(pct_of_encounters = round(100 * n_encounters / n_encounters_total, 1))

# Patient-level presence: a patient can appear under multiple scenarios if different
# encounters resolve differently -- this reports patient-level PRESENCE, not a forced
# single category per patient.
scenario_counts_patient <- encounter_zip %>%
  distinct(ID, scenario_assigned) %>%
  group_by(scenario_assigned, .drop = FALSE) %>%
  summarise(n_patients = n_distinct(ID), .groups = "drop") %>%
  mutate(pct_of_patients = round(100 * n_patients / n_patients_with_encounters, 1))

# ---- Summary table 2: unordered eligible-for counts (B-03 overlap visibility) + direction
# split (B-04), encounter + patient level. S3 stays backward-only (one row, no direction
# split, per S3's own definition) -- this is the "S3-eligible" figure FIX-04d requires
# alongside the ordered "S3" count above. S4 is the complete-case comparator (B-01).
unordered_encounter <- tibble(
  scenario  = c("S1", "S1", "S1", "S2", "S2", "S2", "S3-eligible", "S4-excluded"),
  direction = c("backward", "forward", "either", "backward", "forward", "either", "backward", "n/a"),
  n_encounters = c(
    sum(encounter_zip$s1_backward),
    sum(encounter_zip$s1_forward),
    sum(encounter_zip$s1_either),
    sum(encounter_zip$s2_backward),
    sum(encounter_zip$s2_forward),
    sum(encounter_zip$s2_either),
    sum(encounter_zip$s3_eligible),
    n_s4_excluded_encounters
  )
) %>%
  mutate(pct_of_encounters = round(100 * n_encounters / n_encounters_total, 1))

unordered_patient <- tibble(
  scenario  = c("S1", "S1", "S1", "S2", "S2", "S2", "S3-eligible", "S4-excluded"),
  direction = c("backward", "forward", "either", "backward", "forward", "either", "backward", "n/a"),
  n_patients = c(
    n_distinct(encounter_zip$ID[encounter_zip$s1_backward]),
    n_distinct(encounter_zip$ID[encounter_zip$s1_forward]),
    n_distinct(encounter_zip$ID[encounter_zip$s1_either]),
    n_distinct(encounter_zip$ID[encounter_zip$s2_backward]),
    n_distinct(encounter_zip$ID[encounter_zip$s2_forward]),
    n_distinct(encounter_zip$ID[encounter_zip$s2_either]),
    n_distinct(encounter_zip$ID[encounter_zip$s3_eligible]),
    n_s4_excluded_patients
  )
) %>%
  mutate(pct_of_patients = round(100 * n_patients / n_patients_with_encounters, 1))

# ---- Console headline stats ----
n_s3_eligible_unordered   <- sum(encounter_zip$s3_eligible)
pct_s3_eligible_unordered <- round(100 * n_s3_eligible_unordered / n_encounters_total, 1)

message("\n=== Part B: Ordered Scenario Assignment (S1 then S2 then S3), Encounter Level ===")
print(scenario_counts_encounter)
message(glue("Denominator: n_encounters_total = {n_encounters_total}"))

message("\n=== Part B: Ordered Scenario Assignment, Patient Level ===")
print(scenario_counts_patient)
message(glue("Denominator: n_patients_with_encounters = {n_patients_with_encounters} (patients can appear under multiple scenarios)"))

message("\n=== Part B: Unordered Eligible-For Counts (overlap visible) + Direction Split, Encounter Level ===")
print(unordered_encounter)
message(glue("Denominator: n_encounters_total = {n_encounters_total}"))

message("\n=== Part B: Unordered Eligible-For Counts + Direction Split, Patient Level ===")
print(unordered_patient)
message(glue("Denominator: n_patients_with_encounters = {n_patients_with_encounters}"))

message(glue(
  "\nPart B: S3-eligible (unordered) = {n_s3_eligible_unordered} encounters ",
  "({pct_s3_eligible_unordered}%). S3 resolution still pending as of 08/04 notes -- count ",
  "reported, not presenting either resolution as decided."
))
message("==========================================================================\n")


# ==============================================================================
# SECTION 12: PART C -- COMPLETENESS WATERFALL + C-02 RECONCILIATION (C-01, C-02) ----
# ==============================================================================
# Pitfall 1: Part C's universe is ENCOUNTERS for the waterfall (same as Part B above), but
# C-02's reconciliation is over the STUDY COHORT (patients), not encounters or addr_coal's
# own patient set -- see compute_c02() (SECTION 1B) and 139-05-PATCH FIX-03b/FIX-03c/FIX-03d.

message("--- Part C: completeness waterfall (C-01) + C-02 cohort-scoped reconciliation ---")

# ---- C-01: encounter-level stepwise waterfall (forward-inclusive, SENSITIVITY spec) ----
# Built directly from Part B's scenario_assigned column (now the collapsed 4-level
# already_has_zip9 > S2 > S3 > unresolvable assignment, per 140-04 P-06b -- S1 no
# longer a distinct ordered bucket) -- the waterfall is a straightforward cumulative
# count over its factor levels in order. Each row's count is the CUMULATIVE total
# after that step; the final row equals n_encounters_total by construction, so no
# separate "total" row is needed.
waterfall_encounter <- encounter_zip %>%
  count(scenario_assigned) %>%
  mutate(scenario_assigned = factor(scenario_assigned,
           levels = c("already_has_zip9", "S2", "S3", "unresolvable"))) %>%
  arrange(scenario_assigned) %>%
  mutate(cumulative_n = cumsum(n), cumulative_pct = round(100 * cumulative_n / sum(n), 1))

# ---- C-01: patient-level stepwise waterfall (forward-inclusive, SENSITIVITY spec) ----
# Patient-level bucket is the FURTHEST resolved scenario across all of a patient's
# encounters, in the same priority order (already_has_zip9 > S2 > S3 > unresolvable):
# a patient counts as "already_has_zip9" if ANY encounter already has one; else "S2" if any
# encounter resolves via S2; and so on, down to "unresolvable" only if EVERY encounter is
# unresolvable. This differs from Part B's scenario_counts_patient (which reports PRESENCE
# across scenarios, allowing a patient to appear under multiple buckets) -- the waterfall
# needs one mutually-exclusive bucket per patient so the cumulative sum reconciles to the
# full patient count. Priority rank matches the factor level order (lower rank = resolved
# earlier/more-preferred); slice_min() selects each patient's single best (lowest-rank) row.
scenario_priority <- c(already_has_zip9 = 1L, S2 = 2L, S3 = 3L, unresolvable = 4L)

waterfall_patient <- encounter_zip %>%
  mutate(scenario_rank = scenario_priority[as.character(scenario_assigned)]) %>%
  group_by(ID) %>%
  slice_min(scenario_rank, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  count(scenario_assigned) %>%
  mutate(scenario_assigned = factor(scenario_assigned,
           levels = c("already_has_zip9", "S2", "S3", "unresolvable"))) %>%
  arrange(scenario_assigned) %>%
  mutate(cumulative_n = cumsum(n), cumulative_pct = round(100 * cumulative_n / sum(n), 1))

# ---- C-01 (140-04 P-06a): INDEPENDENT backward-only waterfall, PRIMARY spec ----
# Computed from scenario_assigned_backward_only via its own count()/arrange()/cumsum() call --
# NOT derived from the forward-inclusive waterfall_encounter/waterfall_patient tables above by
# subtraction. get_zip9_at_date() is backward-only by design (Phase 137, Out of Scope); the
# ~86% headline coverage figure this produces must never be computed by summing
# B_direction_split rows (those are unordered and overlapping).
waterfall_encounter_backward <- encounter_zip %>%
  count(scenario_assigned_backward_only) %>%
  mutate(scenario_assigned_backward_only = factor(scenario_assigned_backward_only,
           levels = c("already_has_zip9", "S2", "S3", "unresolvable"))) %>%
  arrange(scenario_assigned_backward_only) %>%
  mutate(
    cumulative_n_backward_only   = cumsum(n),
    cumulative_pct_backward_only = round(100 * cumulative_n_backward_only / sum(n), 1)
  ) %>%
  rename(n_backward_only = n)

waterfall_encounter <- waterfall_encounter %>%
  left_join(
    waterfall_encounter_backward %>% rename(scenario_assigned = scenario_assigned_backward_only),
    by = "scenario_assigned"
  )

# Patient-level bucket recomputed independently against scenario_assigned_backward_only --
# a patient's furthest-resolved scenario can differ between the two orderings (e.g. a patient
# resolved only via forward-only S2 reaches "S2" under forward-inclusive but "unresolvable"
# under backward-only).
waterfall_patient_backward <- encounter_zip %>%
  mutate(scenario_rank = scenario_priority[as.character(scenario_assigned_backward_only)]) %>%
  group_by(ID) %>%
  slice_min(scenario_rank, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  count(scenario_assigned_backward_only) %>%
  mutate(scenario_assigned_backward_only = factor(scenario_assigned_backward_only,
           levels = c("already_has_zip9", "S2", "S3", "unresolvable"))) %>%
  arrange(scenario_assigned_backward_only) %>%
  mutate(
    cumulative_n_backward_only   = cumsum(n),
    cumulative_pct_backward_only = round(100 * cumulative_n_backward_only / sum(n), 1)
  ) %>%
  rename(n_backward_only = n)

waterfall_patient <- waterfall_patient %>%
  left_join(
    waterfall_patient_backward %>% rename(scenario_assigned = scenario_assigned_backward_only),
    by = "scenario_assigned"
  )

message("\n=== Part C: Completeness Waterfall (C-01), Encounter Level ===")
print(waterfall_encounter)
message(glue("Denominator: n_encounters_total = {n_encounters_total}"))

message("\n=== Part C: Completeness Waterfall (C-01), Patient Level ===")
print(waterfall_patient)
message(glue("Denominator: n_patients_with_encounters = {n_patients_with_encounters} (one mutually-exclusive bucket per patient, furthest-resolved scenario)"))

message("\n=== Part C: Backward-Only (Primary) vs Forward-Inclusive (Sensitivity) Waterfall Comparison ===")
print(waterfall_encounter %>% select(scenario_assigned, n, cumulative_pct, n_backward_only, cumulative_pct_backward_only))
message("NOTE (P-06): the backward-only cumulative_pct_backward_only figure above is computed from its own independent ordered assignment (assign_scenarios(backward_only = TRUE)) -- NEVER derived by summing B_direction_split rows, which are unordered and overlapping.")

# 140-08-PATCH FIX-04: the S1 fold-in is coverage-neutral by construction (old already_has_zip9
# + S1 + S2 + S3 = new already_has_zip9 + S2 + S3, since S1's encounters are a subset of
# has_direct_zip5_only and therefore already counted within the new S3 bucket). Any drift here
# means assign_scenarios() changed scope, not just labels.
stopifnot(
  sum(encounter_zip$scenario_assigned != "unresolvable") ==
    sum(!encounter_zip$has_direct_zip9 &
        (encounter_zip$s2_either | encounter_zip$has_direct_zip5_only)) +
    sum(encounter_zip$has_direct_zip9)
)

# ---- C-02: cohort-scoped reconciliation ----
# 139-05-PATCH FIX-03b: compute_c02() (SECTION 1B) takes COHORT_IDS (139-03 Task 1, still in
# scope as a script-level variable) and addr_coal (post-filter) -- NOT addr_coal's own
# patient set. A cohort patient entirely absent from addr_coal counts toward the numerator.
c02_result <- compute_c02(COHORT_IDS, addr_coal)
n_patients_no_zip5_ever <- c02_result$n_patients_no_zip5_ever
n_present_no_usable_zip5 <- c02_result$n_present_no_usable_zip5

message(glue("[R/115] Cohort N: {length(COHORT_IDS)}"))
message(glue("[R/115] Cohort patients entirely absent from addr_coal: {c02_result$n_cohort_absent_from_addr}"))

# 140-01 P-01a/P-01b: break the C-02 gap down into its two component populations directly
# from the script, not just asserted in a planning document -- coverage question (zero rows
# in addr_coal) vs the only population a genuine coalescing defect could produce (present in
# addr_coal, no usable ZIP5).
message(glue(
  "[R/115] C-02 breakdown: {c02_result$n_cohort_absent_from_addr} of {c02_result$n_patients_no_zip5_ever} ",
  "({round(100 * c02_result$n_cohort_absent_from_addr / c02_result$n_patients_no_zip5_ever, 1)}%) are cohort ",
  "patients with ZERO rows in addr_coal (a coverage question); {c02_result$n_present_no_usable_zip5} are cohort ",
  "patients present in addr_coal with no usable ZIP5 (the only population a coalescing defect could produce). ",
  "See 140-CONTEXT.md Section 2 for the working hypothesis on why C02_EXPECTED may be stale."
))

C02_EXPECTED <- 26L
C02_TOLERANCE <- 5L   # 139-05-PATCH FIX-03d: covers cohort-DEFINITION drift only (e.g. exact
                      # membership criteria differing slightly from the notes' own count) --
                      # NOT slack for denominator or methodological uncertainty, now that the
                      # denominator itself is cohort-scoped and correct. Documented in the KEY
                      # sheet (Plan 04 Task 2) as this narrowed claim, not general-purpose slack.
                      # 140-01 D-1 (user-directed, recorded 2026-08-06): C02_EXPECTED and
                      # C02_TOLERANCE themselves are left UNCHANGED by that decision. As of
                      # 140-09-PATCH FIX-17 (2026-08-06), both are retired from the gate
                      # expression entirely -- see immediately below.

# 140-01 D-1 (user-directed, recorded 2026-08-06) corrected the comparison BASIS to
# n_present_no_usable_zip5 (9) instead of the conflated n_patients_no_zip5_ever (665). That
# correction stands. What it compared against -- C02_EXPECTED (26L), a constant whose exact
# denominator population could not be confirmed from this codebase or the team -- could not.
# 140-09-PATCH FIX-17/FIX-18 (2026-08-06): the 26-patient control total is RETIRED as a gate
# input. Its provenance is not going to be confirmed, and the phase should not stay blocked on
# an archaeological question about a meeting note. There was also a directional problem
# independent of the constant's value: coalesce_zip5() can only ADD ZIP5 values, so a correctly
# working fix drives n_present_no_usable_zip5 DOWN -- a symmetric tolerance band around a
# pre-fix figure tested "nothing changed," the opposite of what the fix does.
#
# C02_EXPECTED and C02_TOLERANCE remain defined below (NOT deleted) and are reported on the KEY
# sheet as a superseded historical footnote with provenance marked unknown -- they are no longer
# load-bearing. C-02 is now gated on two invariants checkable against the pipeline itself:
#   C-02a (monotonicity)      -- coalescing can only recover ZIP5, never remove it, so the
#                                 post-coalesce count must be <= the pre-coalesce baseline.
#   C-02b (partition identity) -- n_present_no_usable_zip5, recomputed independently (not via
#                                 the subtraction compute_c02() already performs), must match.
# D-5 (resolved 2026-08-07): "no floor -- report only." The share of the cohort with ANY
# address row (pct_cohort_with_any_address) is a data-delivery question about
# LDS_ADDRESS_HISTORY, independent of coalescing -- reported on the QC sheet as its own named
# figure, but NOT gated. c02_reconciled therefore rests on C-02a/b alone (option-c of the D-5
# checkpoint in 140-09-PLAN.md Task 3).
n_present_no_usable_zip5_precoalesce <- compute_c02_baseline(COHORT_IDS, addr_raw)

c02a_monotone <- n_present_no_usable_zip5 <= n_present_no_usable_zip5_precoalesce

# C-02b: independent computation over c02_tbl (filter + nrow), NOT the subtraction
# compute_c02() already performs internally -- an identity asserted against its own
# derivation is circular and catches nothing.
n_present_no_usable_zip5_direct <- c02_result$c02_tbl %>%
  filter(ID %in% addr_coal$ID, !has_any_zip5) %>%
  nrow()
c02b_partition <- identical(
  as.integer(n_present_no_usable_zip5_direct),
  as.integer(n_present_no_usable_zip5)
)

# D-5 (2026-08-07): no floor -- reported only, not gated. pct_cohort_with_any_address is
# still computed and surfaced on the QC sheet (option-c's stated pro) so a reader can see the
# figure and judge for themselves; it is deliberately not compared against any threshold.
pct_cohort_with_any_address <- 1 - (c02_result$n_cohort_absent_from_addr / n_distinct(COHORT_IDS))

n_zip5_recovered_by_coalesce <- n_present_no_usable_zip5_precoalesce - n_present_no_usable_zip5

c02_reconciled <- c02a_monotone && c02b_partition

message(glue(
  "[R/115] C-02a (coalescing monotonicity): pre-coalesce {n_present_no_usable_zip5_precoalesce}, ",
  "post-coalesce {n_present_no_usable_zip5} -- {if (c02a_monotone) 'PASS' else 'FAIL'} ",
  "(recovered {n_zip5_recovered_by_coalesce} patients)."
))
message(glue(
  "[R/115] C-02b (partition identity): independent count {n_present_no_usable_zip5_direct} vs ",
  "compute_c02()'s {n_present_no_usable_zip5} -- {if (c02b_partition) 'PASS' else 'FAIL'}."
))
message(glue(
  "[R/115] Cohort address coverage (D-5, resolved 2026-08-07 as 'no floor -- report only'): ",
  "{round(100 * pct_cohort_with_any_address, 1)}% of cohort has any address row. Reported only ",
  "-- not part of the c02_reconciled gate."
))

if (!c02_reconciled) {
  failed_invariants <- c(
    if (!c02a_monotone) "C-02a (monotonicity)",
    if (!c02b_partition) "C-02b (partition identity)"
  )
  message(glue(
    "\n*** C-02 RECONCILIATION FAILURE ***\n",
    "Failed invariant(s): {paste(failed_invariants, collapse = ', ')}.\n",
    "This is a real defect in coalesce_zip5() or its accounting -- investigate before shipping.\n",
    "*** DO NOT SHIP output/{basename(OUTPUT_XLSX)} TO ERIN/AMY UNTIL THIS IS RESOLVED ***\n"
  ))
} else {
  message(glue(
    "C-02 reconciliation OK: both invariants pass (C-02a monotonicity, C-02b partition ",
    "identity; D-5 resolved as no coverage floor, reported only). The historical ",
    "C02_EXPECTED={C02_EXPECTED} control total is retained on the KEY sheet for provenance ",
    "only and is not part of this gate (140-09-PATCH FIX-17)."
  ))
}

# 139-05-PATCH FIX-03c: pre-filter comparison. Compute the SAME "no usable ZIP5 ever"
# statistic against addr_raw (unfiltered, from SECTION 3), reusing coalesce_zip5() (NOT a
# second coalescing implementation) so the study-period/unparseable-date filters' effect on
# the denominator is visible.
addr_prefilter <- coalesce_zip5(addr_raw)
c02_prefilter_result <- compute_c02(COHORT_IDS, addr_prefilter)
n_patients_no_zip5_ever_prefilter <- c02_prefilter_result$n_patients_no_zip5_ever

message(glue(
  "[R/115] C-02 pre-filter comparison: {n_patients_no_zip5_ever_prefilter} (before study-period/",
  "unparseable-date filters) vs {n_patients_no_zip5_ever} (post-filter). NOTE: neither figure ",
  "feeds the C-02a/b/c gate above (140-09-PATCH FIX-17) -- {n_present_no_usable_zip5} ",
  "(n_present_no_usable_zip5) and {n_present_no_usable_zip5_precoalesce} ",
  "(n_present_no_usable_zip5_precoalesce) are what the gate actually uses. A large gap here means ",
  "the study-period/unparseable-date filters are removing a material share of cohort patients -- ",
  "see P-02c below for the named figure."
))

# 140-03 P-02c: explicit, named 280-patient filter-loss figure -- arithmetic on two values
# ALREADY computed above (n_patients_no_zip5_ever_prefilter, n_patients_no_zip5_ever), not a
# new computation. Reported here explicitly, not left implicit in the pre/post comparison alone.
n_patients_lost_to_filters_c02 <- n_patients_no_zip5_ever - n_patients_no_zip5_ever_prefilter
message(glue(
  "[R/115] P-02c: {n_patients_lost_to_filters_c02} cohort patients lose EVERY usable-ZIP5 address row to ",
  "the study-period/unparseable-date filters (post-filter {n_patients_no_zip5_ever} minus pre-filter ",
  "{n_patients_no_zip5_ever_prefilter}). Reported explicitly here -- not left implicit in the pre/post ",
  "comparison alone."
))

message("==========================================================================\n")


# ==============================================================================
# SECTION 13: QC SHEET DATA -- CONSOLIDATED DROP/EXCLUSION COUNTS ----
# ==============================================================================
# Single place a reviewer checks before trusting the rest of the workbook.
# Consolidates every drop/exclusion count logged across Plans 01-04.

n_period_end_open <- sum(addr_coal$period_end_open)

qc_tbl <- tibble(
  Metric = c(
    "n_unparseable_dates (period_start_dt, dropped)",
    "n_out_of_range_dates (outside study period, dropped)",
    "n_zip9_sentinel_nulled",
    "n_zip5_sentinel_nulled",
    "period_end_open count (retained, open-ended address records)",
    "n_excluded_no_prior (A-06 hold-out, single-record patients)",
    "cohort N (study cohort, Part B/C population)",
    "n_cohort_absent_from_addr (cohort patients with zero addr_coal rows -- coverage gap, reported only)",
    "n_present_no_usable_zip5 (post-coalesce -- C-02a/b input, cohort patients IN addr_coal with no usable ZIP5)",
    "n_present_no_usable_zip5_precoalesce (C-02a monotonicity baseline, raw ZIP5 only, 140-09-PATCH FIX-17)",
    "n_zip5_recovered_by_coalesce (reported, not gated -- coalescing fix's measured yield, 140-09-PATCH FIX-17)",
    "pct_cohort_with_any_address (D-5 resolved 2026-08-07 as 'no floor -- report only' -- NOT gated, see KEY sheet)",
    "c02a_monotone (post-coalesce <= pre-coalesce, 140-09-PATCH FIX-17)",
    "c02b_partition (independent recount matches compute_c02(), 140-09-PATCH FIX-17)",
    "C02_EXPECTED (superseded historical control total, 140-09-PATCH FIX-17 -- provenance UNKNOWN, no longer gate input, see KEY sheet)",
    "n_patients_no_zip5_ever (C-02, post-filter, conflates coverage gap + coalescing-defect population -- not used by any gate)",
    "n_patients_no_zip5_ever_prefilter (C-02, pre-filter comparison)",
    "n_patients_lost_to_filters_c02 (P-02c, cohort patients who lose every usable-ZIP5 row to filters)",
    "c02_reconciled",
    "has_block_group_crosswalk (A-06 optional enrichment tier)"
  ),
  Value = c(
    as.character(n_unparseable_dates),
    as.character(n_period_start_out_of_range),
    as.character(n_zip9_sentinel_nulled),
    as.character(n_zip5_sentinel_nulled),
    as.character(n_period_end_open),
    as.character(n_excluded_no_prior),
    as.character(length(COHORT_IDS)),
    as.character(c02_result$n_cohort_absent_from_addr),
    as.character(c02_result$n_present_no_usable_zip5),
    as.character(n_present_no_usable_zip5_precoalesce),
    as.character(n_zip5_recovered_by_coalesce),
    as.character(round(100 * pct_cohort_with_any_address, 1)),
    if (c02a_monotone) "PASS" else "FAIL",
    if (c02b_partition) "PASS" else "FAIL",
    as.character(C02_EXPECTED),
    as.character(n_patients_no_zip5_ever),
    as.character(n_patients_no_zip5_ever_prefilter),
    as.character(n_patients_lost_to_filters_c02),
    if (c02_reconciled) "PASS" else "FAIL -- SEE ABOVE",
    as.character(has_block_group_crosswalk)
  )
)

# 140-03 P-02a (140-08-PATCH FIX-13): fold the per-category unparseable-date COUNT breakdown
# into qc_tbl itself as individual named rows -- the QC sheet's single extra_tbl slot (SECTION
# 15) is used for the higher-value unparseable_date_examples table (top-20 raw values per
# category) instead.
unparseable_breakdown_rows <- unparseable_date_breakdown %>%
  transmute(
    Metric = glue("n_unparseable_{category} (P-02a breakdown)"),
    Value  = as.character(n)
  )
qc_tbl <- bind_rows(qc_tbl, unparseable_breakdown_rows)

# 140-08-PATCH FIX-12: expose the crosswalk match-rate coverage figure on the QC sheet
# regardless of block_group_tier_status's final value. Guarded because
# n_zip9_matched_to_block_group / pct_zip9_matched_to_block_group only exist inside
# SECTION 8's has_block_group_crosswalk branch (crosswalk-found + columns-identified path).
if (has_block_group_crosswalk && exists("n_zip9_matched_to_block_group")) {
  qc_tbl <- bind_rows(
    qc_tbl,
    tibble(
      Metric = c(
        "n_zip9_matched_to_block_group (A-06 crosswalk coverage, distinct ZIP9s)",
        "pct_zip9_matched_to_block_group (A-06 crosswalk coverage, vs 90% pending-confirmation threshold)"
      ),
      Value = c(
        as.character(n_zip9_matched_to_block_group),
        as.character(pct_zip9_matched_to_block_group)
      )
    )
  )
}

message("--- QC sheet data assembled (Section 13) ---")
print(qc_tbl)


# ==============================================================================
# SECTION 14: KEY SHEET DATA -- DEFINITIONS, UNIVERSE, DENOMINATORS ----
# ==============================================================================
# Written FIRST as the leftmost tab (see Section 15). Language throughout is
# measured and neutral -- describes what was counted and under what
# definition, WITHOUT characterizing whether the resulting completeness is
# adequate (that is the team's call, not this script's).

key_tbl <- tibble(
  Field = c(
    "Script / Phase",
    "Run date",
    "Source file (Part A sheets)",
    "Source table (Part B/C sheets)",
    "Universe -- Part A sheets (A_stability_patient, A_stability_summary, A_validation_curve)",
    "Universe -- Part B/C sheets (B_scenario_counts, B_direction_split, C_completeness)",
    "Cohort N (Part B/C population)",
    "A-06 sampling frame (139-05-PATCH FIX-01)",
    "Ordered vs unordered S3 (140-04 P-06b, amended by 140-08-PATCH FIX-04)",
    "C-02 historical control total (superseded by 140-09-PATCH FIX-17)",
    "C-02 gate design (140-09-PATCH FIX-17, 2026-08-06)",
    "C-02 status (140-09-PATCH FIX-17/FIX-18, 2026-08-06)",
    "Analysis unit (D-2, recorded 2026-08-06)",
    "ZIP5 coalescing",
    "QC sheet"
  ),
  Value = c(
    "R/115_zip_stability_counts.R, Phase 139, amended by 139-05-PATCH.md",
    as.character(Sys.Date()),
    basename(ADDR_FILENAME),
    "ENCOUNTER (DuckDB, cohort-restricted)",
    "Address-history records (addr_coal, one row per LDS_ADDRESS_HISTORY record after date/sentinel filtering). Per Pitfall 1, these sheets are computed on address history, not encounters.",
    "Encounters (one row per cohort-restricted (ID, ENCOUNTERID, ADMIT_DATE) with a parseable ADMIT_DATE). Per Pitfall 1, these sheets are computed on encounters, not address history.",
    glue("{length(COHORT_IDS)} (via get_hl_patient_ids(), the study cohort -- same population Part B and Part C count over)"),
    paste(
      "A-06 is computed on address-history records (addr_coal), using each record's",
      "period_start_dt as the lookup date. This measures the same carry-forward rule",
      "get_zip9_at_date() applies in production. Per Pitfall 1, Part A sheets are computed",
      "on address history, not encounters."
    ),
    paste(
      "Ordered vs unordered S3 (140-04 P-06b, amended by 140-08-PATCH FIX-04): S1 is no longer",
      "a distinct ordered bucket -- every has_direct_zip5_only encounter is assigned \"S3\".",
      "The ordered S3 count therefore now EXCEEDS B_direction_split's unordered \"S3-eligible\"",
      "count by exactly the S1-backward count, because s3_eligible retains its",
      "complement-of-S1-backward definition. This is the inverse of the pre-fold relationship",
      "described by 139-05-PATCH FIX-04d (which had ordered S3 UNDERCOUNTING unordered",
      "S3-eligible, because an encounter eligible only via S1-forward was assigned \"S1\" by the",
      "old ordered rule). Use the ordered count for the assignment; use \"S3-eligible\" only for",
      "continuity with Phase 139 outputs."
    ),
    paste(
      glue("A prior team note (08/04/2026 meeting) recorded {C02_EXPECTED} patients with no"),
      "5-digit ZIP at any point, with a tolerance of +/-", glue("{C02_TOLERANCE}"), "patients.",
      "The population that figure was computed over was never established and its provenance",
      "is not going to be confirmed, so as of 140-09-PATCH FIX-17/FIX-18 (2026-08-06) it is",
      "RETIRED as a gate input -- not deleted, retained here for provenance only, marked",
      "UNKNOWN. C02_EXPECTED and C02_TOLERANCE remain defined in the script but no longer",
      "appear in the c02_reconciled expression. See 'C-02 gate design' below for what replaced it."
    ),
    paste(
      "140-09-PATCH FIX-17 (2026-08-06): C-02 is gated on two invariants checkable against",
      "the pipeline itself, neither of which require the historical 26-patient figure above.",
      "C-02a (coalescing monotonicity): coalesce_zip5() can only ADD a ZIP5 value, never",
      "remove one, so the post-coalesce count of cohort patients present in addr_coal with no",
      "usable ZIP5 (n_present_no_usable_zip5) must be <= the pre-coalesce baseline over raw",
      "ADDRESS_ZIP5 only (n_present_no_usable_zip5_precoalesce, via compute_c02_baseline()). A",
      "violation is an unambiguous coalescing defect. C-02b (partition identity):",
      "n_present_no_usable_zip5 is recomputed independently (filter + nrow over c02_tbl, not",
      "the subtraction compute_c02() performs internally) and must match. A third candidate",
      "invariant, C-02c (coverage floor) -- gating on the share of the cohort with any address",
      "row at all (pct_cohort_with_any_address) against a team-set floor -- was proposed but",
      "D-5 (resolved 2026-08-07) chose 'no floor -- report only': pct_cohort_with_any_address",
      "is reported as its own QC figure but does not gate c02_reconciled. The coalescing fix's",
      "measured yield (n_zip5_recovered_by_coalesce = pre-coalesce minus post-coalesce) is",
      "likewise reported, not inferred from the gate outcome. See the QC sheet for all values."
    ),
    paste(
      "c02_reconciled = c02a_monotone AND c02b_partition (140-09-PATCH FIX-17/FIX-18,",
      "2026-08-06; D-5 resolved 2026-08-07 as no coverage floor, so C-02c is not part of this",
      "expression). This design has a reachable PASS state -- the prior design (comparing",
      "n_present_no_usable_zip5 against the unconfirmed 26-patient control total) did not. See",
      "the QC sheet for each invariant's individual PASS/FAIL and the underlying figures, plus",
      "the reported (non-gating) pct_cohort_with_any_address. A FAIL here is a real",
      "coalesce_zip5() defect, not an artifact of an unverifiable external constant or an",
      "address-coverage shortfall -- do not ship the workbook to Erin/Amy until c02_reconciled",
      "reads TRUE."
    ),
    paste(
      "ZIP5 (D-2, recorded 2026-08-06). Decided on the ZIP5-vs-ZIP9 accuracy comparison in",
      "A_validation_curve. The block-group tier -- which would measure whether ZIP9's +4",
      "carries geographic information the ZIP5 comparison cannot see -- was not available at",
      "the time of decision and remains unpopulated (P-03a deferred, per 140-02-SUMMARY.md).",
      "If it is later populated and disagrees, this decision was made WITHOUT that evidence,",
      "not AGAINST it (140-09-PATCH FIX-23)."
    ),
    paste(
      "ZIP5 coalescing (preferring the raw ADDRESS_ZIP5 column with derived-from-ZIP9",
      "fallback) is applied locally in this script via the single coalesce_zip5() function",
      "(SECTION 1B), since no separate prior phase shipped this as a shared utility."
    ),
    "Consolidates every drop/exclusion count logged across Plans 01-04 -- check this sheet before trusting the rest of the workbook."
  )
)

message("--- KEY sheet data assembled (Section 14) ---")
print(key_tbl)


# ==============================================================================
# SECTION 15: WRITE STYLED XLSX (FULL 8-SHEET WORKBOOK) ----
# ==============================================================================

message("--- Writing zip_stability_counts_YYYYMMDD.xlsx (8 sheets) ---")

# UF brand colors, per 139-CONTEXT.md's deliverable spec ("Charts use UF colors (#0021A5,
# #FA4616)"). NOTE: this is a DIFFERENT blue than utils_pptx.R's UF_BLUE ("#003087") --
# 139-CONTEXT.md's explicit hex values are locked and take precedence for this deliverable;
# do not reuse utils_pptx.R's constant or source that file.
UF_BLUE   <- "#0021A5"
UF_ORANGE <- "#FA4616"
WHITE     <- wb_color(hex = "#FFFFFF")
DARK_TEXT <- wb_color(hex = "#1F2937")

# add_styled_sheet() copied VERBATIM (structure) from R/106 lines 750-797 / R/114 lines
# 234-282 per this project's "copy, don't source" convention for this helper -- adapted here
# to use UF_BLUE (not R/106's generic DARK_GRAY) as the header fill color.
add_styled_sheet <- function(wb, sheet_name, title_text, subtitle_text, data_tbl,
                              extra_tbl = NULL, extra_label = NULL) {
  wb$add_worksheet(sheet_name)
  n_cols           <- ncol(data_tbl)
  last_col_letter  <- openxlsx2::int2col(n_cols)

  wb$add_data(sheet = sheet_name, x = title_text,    dims = "A1")
  wb$add_data(sheet = sheet_name, x = subtitle_text, dims = "A2")
  wb$add_data(sheet = sheet_name, x = data_tbl,      dims = "A4", col_names = TRUE)

  wb$merge_cells(sheet = sheet_name, dims = paste0("A1:", last_col_letter, "1"))
  wb$merge_cells(sheet = sheet_name, dims = paste0("A2:", last_col_letter, "2"))

  wb$add_font(sheet = sheet_name, dims = "A1",
              name = "Calibri", size = 14, bold = TRUE, color = DARK_TEXT)
  wb$add_font(sheet = sheet_name, dims = "A2",
              name = "Calibri", size = 10, italic = TRUE, color = DARK_TEXT)

  header_range <- paste0("A4:", last_col_letter, "4")
  wb$add_fill(sheet = sheet_name, dims = header_range, color = wb_color(hex = UF_BLUE))
  wb$add_font(sheet = sheet_name, dims = header_range,
              name = "Calibri", size = 11, bold = TRUE, color = WHITE)

  # Optional second table, written a few rows below the first.
  if (!is.null(extra_tbl) && nrow(extra_tbl) > 0) {
    gap_rows_offset <- 4 + nrow(data_tbl) + 2      # blank row + label row
    label_row       <- gap_rows_offset
    header_row      <- gap_rows_offset + 1

    if (!is.null(extra_label)) {
      wb$add_data(sheet = sheet_name, x = extra_label, dims = paste0("A", label_row))
      wb$add_font(sheet = sheet_name, dims = paste0("A", label_row),
                  name = "Calibri", size = 11, bold = TRUE, color = DARK_TEXT)
    }

    wb$add_data(sheet = sheet_name, x = extra_tbl,
                dims = paste0("A", header_row), col_names = TRUE)

    extra_last_col <- openxlsx2::int2col(ncol(extra_tbl))
    extra_hdr_rng  <- paste0("A", header_row, ":", extra_last_col, header_row)
    wb$add_fill(sheet = sheet_name, dims = extra_hdr_rng, color = wb_color(hex = UF_BLUE))
    wb$add_font(sheet = sheet_name, dims = extra_hdr_rng,
                name = "Calibri", size = 11, bold = TRUE, color = WHITE)
  }

  wb$freeze_pane(sheet = sheet_name, firstActiveRow = 5)
  wb$set_col_widths(sheet = sheet_name, cols = 1:max(n_cols, ncol(extra_tbl %||% data_tbl)),
                    widths = "auto")
}

# ---- A_stability_patient: patient-level distribution (bucketed, HIPAA-safe -- no raw ID
# rows), grain = unique patient (ID), per Part A's addr_coal-anchored universe. ----
bucket_transitions <- function(x) {
  case_when(
    x == 0             ~ "0",
    x == 1             ~ "1",
    x >= 2 & x <= 5    ~ "2-5",
    x >= 6             ~ "6+"
  )
}

zip9_transition_dist <- patient_stability %>%
  mutate(bucket = bucket_transitions(n_zip9_transitions)) %>%
  count(bucket, name = "n_patients") %>%
  mutate(
    metric = "n_zip9_transitions",
    pct_of_patients = round(100 * n_patients / n_patients_total, 1)
  )

zip5_transition_dist <- patient_stability %>%
  mutate(bucket = bucket_transitions(n_zip5_transitions)) %>%
  count(bucket, name = "n_patients") %>%
  mutate(
    metric = "n_zip5_transitions",
    pct_of_patients = round(100 * n_patients / n_patients_total, 1)
  )

plus4_only_dist <- patient_stability %>%
  mutate(bucket = bucket_transitions(n_plus4_only_transitions)) %>%
  count(bucket, name = "n_patients") %>%
  mutate(
    metric = "n_plus4_only_transitions",
    pct_of_patients = round(100 * n_patients / n_patients_total, 1)
  )

stability_patient_tbl <- bind_rows(zip9_transition_dist, zip5_transition_dist, plus4_only_dist) %>%
  select(metric, bucket, n_patients, pct_of_patients) %>%
  arrange(metric, factor(bucket, levels = c("0", "1", "2-5", "6+")))

# ---- A_stability_summary: gap_days_summary (median/p25/p75/min/max/deciles), fixed-bucket
# histogram, obs_span_years summary, and headline transition stats. gap_days_deciles is
# included in FULL (A-05's explicit "median, IQR, deciles" requirement), not dropped in
# favor of the histogram alone. ----
gap_deciles_tbl <- tibble(
  Percentile = names(gap_days_summary$deciles),
  Gap_Days   = round(as.numeric(gap_days_summary$deciles), 1)
)

stability_summary_tbl <- tibble(
  Metric = c(
    "n_patients_total",
    "median_n_zip9_transitions",
    "pct_zero_transition_zip9",
    "n_plus4_only_transitions (total)",
    "pct_plus4_only_of_all_zip9_transitions",
    "median_obs_span_years",
    "p25_obs_span_years",
    "p75_obs_span_years",
    "gap_days: n_gap_observations",
    "gap_days: median_days",
    "gap_days: p25_days",
    "gap_days: p75_days",
    "gap_days: min_days",
    "gap_days: max_days",
    "gap_days: reference_note"
  ),
  Value = c(
    as.character(n_patients_total),
    as.character(median_n_zip9_transitions),
    as.character(pct_zero_transition_zip9),
    as.character(total_plus4_only),
    as.character(pct_plus4_only_of_all),
    as.character(median_obs_span_years),
    as.character(obs_span_summary$Value[2]),
    as.character(obs_span_summary$Value[3]),
    as.character(gap_days_summary$n_gap_observations),
    as.character(gap_days_summary$median_days),
    as.character(gap_days_summary$p25_days),
    as.character(gap_days_summary$p75_days),
    as.character(gap_days_summary$min_days),
    as.character(gap_days_summary$max_days),
    gap_days_summary$reference_note
  )
)

# ---- Assemble workbook: KEY first (leftmost tab), then A/B/C sheets, then QC. ----
wb <- wb_workbook()

add_styled_sheet(
  wb, "KEY",
  title_text    = "KEY -- Definitions, Universe, and Design Notes",
  subtitle_text = "Read this sheet first. Definitions describe what was counted and under what definition -- not whether the resulting completeness is adequate (that is the team's call).",
  data_tbl      = key_tbl
)

add_styled_sheet(
  wb, "A_stability_patient",
  title_text    = "A_stability_patient -- ZIP Stability Distribution (Patient-Level)",
  subtitle_text = "Grain: unique patient (ID), Part A universe (address-history records, addr_coal). Bucketed distributions of n_zip9_transitions, n_zip5_transitions, and n_plus4_only_transitions across patients (HIPAA-safe: no raw ID rows).",
  data_tbl      = stability_patient_tbl
)

gap_histogram_and_deciles_tbl <- bind_rows(
  gap_days_summary$histogram %>%
    transmute(Type = "Histogram (fixed bucket)", Label = bucket, Value = as.character(n_gaps)),
  gap_deciles_tbl %>%
    transmute(Type = "Decile (10th-90th pctile, days)", Label = Percentile, Value = as.character(Gap_Days))
)

add_styled_sheet(
  wb, "A_stability_summary",
  title_text    = "A_stability_summary -- Headline Stability Stats, Gap-Day Distribution (A-05)",
  subtitle_text = "Median/IQR/deciles + fixed-bucket histogram of gap-days between ZIP9 changes (A-05), plus median n_zip9_transitions, % zero-transition (Pitfall 6: median reported, never mean), and exposure-denominator (obs_span_years) summary.",
  data_tbl      = stability_summary_tbl,
  extra_tbl     = gap_histogram_and_deciles_tbl,
  extra_label   = "Gap-day histogram (fixed buckets) + deciles (10th-90th percentile cutpoints, days) -- A-05's explicit 'median, IQR, deciles' requirement"
)

add_styled_sheet(
  wb, "A_validation_curve",
  title_text    = "A_validation_curve -- Carry-Forward Hold-Out Validation (A-06)",
  subtitle_text = glue(
    "Record-anchored hold-out (139-05-PATCH FIX-01): hold out one addr_coal record, predict ",
    "from the most recent PRIOR record with a non-NA ZIP9, binned by elapsed gap-days. ",
    "{n_excluded_no_prior} patients excluded (single usable record, no prior to predict from). ",
    "Base rate (unchanged-address test cases): {pct_unchanged}%. Same-day pairs: {n_same_day}. ",
    "Block-group tier: {block_group_tier_status}."
  ),
  data_tbl      = validation_curve
)

add_styled_sheet(
  wb, "B_scenario_counts",
  title_text    = "B_scenario_counts -- Ordered already_has_zip9-then-S2-then-S3 Scenario Assignment (B-03)",
  subtitle_text = glue(
    "Grain: cohort-restricted encounters (Part B/C universe). Ordered, mutually-exclusive ",
    "assignment (case_when: already_has_zip9 > S2 > S3 > unresolvable). 140-04 P-06b: S1 is no ",
    "longer a distinct ordered bucket (folded into S3 universally) -- collapsed from the prior ",
    "5-level scheme to this 4-level one. See KEY sheet and B_direction_split for the unordered ",
    "S3-eligible count and the S1 backward/forward/either counts (reporting-only, 140-08-PATCH ",
    "FIX-04) -- do not read this sheet's 'S3' row alone as the complete S3-eligible population, ",
    "and note the relationship has INVERTED (ordered S3 now EXCEEDS unordered S3-eligible)."
  ),
  data_tbl      = scenario_counts_encounter,
  extra_tbl     = scenario_counts_patient,
  extra_label   = "Patient-level (presence across scenarios -- a patient can appear under multiple rows)"
)

add_styled_sheet(
  wb, "B_direction_split",
  title_text    = "B_direction_split -- Unordered Eligible-For Counts + Backward/Forward Split (B-04)",
  subtitle_text = glue(
    "Grain: cohort-restricted encounters. Unordered per-scenario eligibility (overlap visible, ",
    "unlike the ordered assignment on B_scenario_counts). S3-eligible = complete S3 count ",
    "(139-05-PATCH FIX-04d), backward-only per S3's own definition. S4-excluded = complete-case ",
    "comparator (complement of has_direct_zip9, B-01)."
  ),
  data_tbl      = unordered_encounter,
  extra_tbl     = unordered_patient,
  extra_label   = "Patient-level"
)

add_styled_sheet(
  wb, "C_completeness",
  title_text    = "C_completeness -- Stepwise Completeness Waterfall (C-01), Forward-Inclusive + Backward-Only",
  subtitle_text = glue(
    "Grain: cohort-restricted encounters (encounter-level table) / patients (patient-level ",
    "table, furthest-resolved scenario per patient). Two INDEPENDENTLY-COMPUTED cumulative ",
    "stepwise waterfalls, in fixed order already_has_zip9 -> +S2 -> +S3 -> unresolvable ",
    "(residual): the forward-inclusive SENSITIVITY spec (n / cumulative_n / cumulative_pct, ",
    "S2 tested via s2_either) and the backward-only PRIMARY spec (n_backward_only / ",
    "cumulative_n_backward_only / cumulative_pct_backward_only, S2 tested via s2_backward). ",
    "140-CONTEXT.md Section 7 (P-06a): the backward-only figure is never derived by summing ",
    "B_direction_split rows -- it comes from its own ordered assign_scenarios(backward_only = ",
    "TRUE) call. Each bottom row's cumulative_n(/_backward_only) equals the full universe by ",
    "construction -- no separate total row. See KEY sheet for the D-4 primary-spec decision ",
    "and QC sheet for the C-02 cohort-scoped reconciliation check."
  ),
  data_tbl      = waterfall_encounter,
  extra_tbl     = waterfall_patient,
  extra_label   = "Patient level (one mutually-exclusive bucket per patient, furthest-resolved scenario)"
)

add_styled_sheet(
  wb, "QC",
  title_text    = "QC -- Consolidated Drop/Exclusion Counts + C-02 Reconciliation",
  subtitle_text = glue(
    "Single place to check before trusting the rest of the workbook. As of 140-09-PATCH ",
    "FIX-17 (2026-08-06), c02_reconciled = C-02a (coalescing monotonicity) AND C-02b ",
    "(partition identity) -- two invariants checkable against the pipeline itself. D-5 ",
    "(resolved 2026-08-07) chose no coverage floor: pct_cohort_with_any_address is reported ",
    "below but does not gate. The historical {C02_EXPECTED}-patient control total ",
    "(+/-{C02_TOLERANCE}) is retained below for provenance only and is not part of this gate ",
    "-- see KEY sheet. A FAIL on either invariant is a real coalesce_zip5() defect; do not ",
    "ship this workbook to Erin/Amy until c02_reconciled reads TRUE."
  ),
  data_tbl      = qc_tbl,
  extra_tbl     = unparseable_date_examples,
  extra_label   = "Unparseable period_start_dt raw-value examples (top 20 per category, P-02a/140-08-PATCH FIX-13) -- whether any category is recoverable via extending parse_pcornet_date() (P-02b) requires reviewing this table on a real HiPerGator run"
)

# 139-05-PATCH FIX-03: if C-02 did not reconcile, flag it prominently on the xlsx itself --
# not just the console -- since the xlsx is what gets forwarded to Erin/Amy.
if (!c02_reconciled) {
  c02_row_idx <- match("c02_reconciled", qc_tbl$Metric)
  c02_xlsx_row <- 4 + c02_row_idx   # header at row 4, data starts row 5
  wb$add_fill(sheet = "QC", dims = glue("A{c02_xlsx_row}:B{c02_xlsx_row}"), color = wb_color(hex = UF_ORANGE))
  wb$add_font(sheet = "QC", dims = glue("A{c02_xlsx_row}:B{c02_xlsx_row}"),
              name = "Calibri", size = 11, bold = TRUE, color = WHITE)
  message(glue("[R/115] QC sheet C-02 row ({c02_xlsx_row}) flagged UF_ORANGE -- reconciliation FAILED."))
}

wb_save(wb, OUTPUT_XLSX)
message(glue("[R/115] xlsx written to: {OUTPUT_XLSX}"))
message("[R/115] Phase 139 ZIP stability and imputation occurrence counts investigation complete.")
