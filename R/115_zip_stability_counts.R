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
