# ==============================================================================
# 106_zip_change_frequency.R -- ZIP Change Frequency Investigation (Phase 121)
# ==============================================================================
# Purpose:     READ-ONLY investigation that probes for the PCORnet CDM
#              LDS_ADDRESS_HISTORY table (the only CDM source with a time-varying
#              9-digit ZIP code), and -- if present -- quantifies how often an
#              individual patient's ZIP code changes at BOTH ZIP9 and ZIP5
#              granularity.
#
#              The PURPOSE is to INFORM a downstream decision on how ZIP-code data
#              should feed socioeconomic indices (ADI needs ZIP9 block-group
#              precision; SVI needs only ZIP5). This script does NOT compute any
#              SES index and does NOT add LDS_ADDRESS_HISTORY to the permanent
#              PCORNET_TABLES load set -- both are explicitly deferred.
#
#              Gives the team a defensible, data-driven answer to "is a single
#              ZIP per patient good enough, or do we need time-varying handling?"
#              before any SES-index work begins.
#
# Inputs:      LDS_ADDRESS_HISTORY_Mailhot_V1.csv  (probed in CONFIG$data_dir)
#              R/00_config.R                        (auto-sources utils chain)
#
# Outputs:     output/zip_change_frequency.xlsx  (5-sheet styled workbook)
#                Sheet 1: ZIP Change Distribution  (ZIP9 + ZIP5 side-by-side)
#                Sheet 2: Change Rates & Histogram  (% ever-changed, ZIP9-change-
#                          only, HIPAA-suppressed histogram)
#                Sheet 3: Time Between Changes      (gap-days from PERIOD_START)
#                Sheet 4: Tie-Break Comparison      (most-recent vs modal)
#                Sheet 5: Recommendation & Metadata
#              (Console) Headline stats before xlsx write
#
# Dependencies: R/00_config.R (auto-sources utils_duckdb, utils_dates,
#               utils_cancer, utils_treatment; provides CONFIG)
#               dplyr, glue, stringr, tidyr, openxlsx2, tibble, lubridate
#               vroom (primary CSV loader; base read.csv fallback)
#
# Requirements: Phase 121 -- ZIP-01 (probe gate), ZIP-02 (per-patient metrics),
#               ZIP-03 (5-sheet xlsx), ZIP-04 (registration), SMOKE-121-01
#
# Usage:       Rscript R/106_zip_change_frequency.R
#              source("R/106_zip_change_frequency.R")
#
# Note:        READ-ONLY investigation. Structural verification is runnable
#              locally on Windows (grep-based R/88 Section 15s). Runtime --
#              loading the CSV, computing ZIP metrics, and writing the xlsx --
#              requires HiPerGator with LDS_ADDRESS_HISTORY present.
#              This script does NOT modify any pipeline output or config.
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
})

source("R/00_config.R")   # auto-sources utils (parse_pcornet_date, etc.)

message("=== Phase 121: ZIP Change Frequency ===\n")


# ==============================================================================
# SECTION 2: CONSTANTS AND PROBE (D-02) ----
# ==============================================================================

# Runtime unknown: actual HiPerGator filename may differ. Default
# {TABLE}_Mailhot_V1.csv pattern. If the data custodian named it differently,
# update ADDR_FILENAME (same override pattern as LAB_RESULT_CM in R/00_config.R).
ADDR_FILENAME <- "LDS_ADDRESS_HISTORY_Mailhot_V1.csv"
OUTPUT_XLSX   <- file.path(CONFIG$output_dir, "zip_change_frequency.xlsx")

# Study/data-collection period for LDS_ADDRESS_HISTORY dates used in
# Section 9's gap-day computation. Narrower than
# CONFIG$analysis$date_range_min/max (1901-01-01 to 2025-03-31), which is
# a loose, project-wide sentinel-catching bound. This is the actual
# LDS_ADDRESS_HISTORY study window: 2012-01-01 matches the project's
# HISTORICAL_CUTOFF convention (R/26_treatment_episodes.R); 2025-03-31
# matches CONFIG$analysis$date_range_max, the documented end of the data
# collection period.
ZIP_STUDY_PERIOD_MIN <- as.Date("2012-01-01")
ZIP_STUDY_PERIOD_MAX <- as.Date("2025-03-31")

addr_path <- file.path(CONFIG$data_dir, ADDR_FILENAME)
message(glue("  CSV probe: {addr_path}"))
message(glue("  File exists? {file.exists(addr_path)}"))

if (!file.exists(addr_path)) {
  message(glue(
    "\n[R/106] LDS_ADDRESS_HISTORY not found at expected path.\n",
    "  Expected: {addr_path}\n",
    "  This table is NOT in the permanent PCORNET_TABLES load set.\n",
    "  Confirm the exact filename with the data custodian and re-run on HiPerGator.\n",
    "  Phase 121 investigation requires HiPerGator with this file present.\n",
    "  If the file is named differently, update ADDR_FILENAME at the top of this script.\n"
  ))
  # Graceful exit, NOT stop() (D-02 / Pitfall precedent) -- but quit() only
  # when run standalone via `Rscript R/106...`. When source()-d by the
  # orchestrator (R/39) into a local env, quit() would kill the whole R
  # session and silently abort every later investigation script -- raise a
  # condition instead so the orchestrator's tryCatch logs this one script as
  # skipped and continues.
  if (identical(environment(), globalenv())) {
    quit(status = 0)
  } else {
    stop("[R/106] LDS_ADDRESS_HISTORY not found -- skipped (not a real failure; see message above)", call. = FALSE)
  }
}


# ==============================================================================
# SECTION 3: LOAD ADDRESS TABLE ----
# ==============================================================================

# LDS_ADDRESS_HISTORY is NOT in PCORNET_TABLES -- read directly by path,
# NOT via get_pcornet_table("LDS_ADDRESS_HISTORY").
message("--- Loading LDS_ADDRESS_HISTORY ---")

addr <- tryCatch(
  vroom::vroom(addr_path, col_types = vroom::cols(.default = "c"), progress = FALSE),
  error = function(e) {
    message(glue("  vroom failed ({conditionMessage(e)}); falling back to read.csv"))
    read.csv(addr_path, colClasses = "character", na.strings = c("", "NA"))
  }
)

n_rows <- nrow(addr)
message(glue("  Rows loaded: {n_rows}"))

# Validate required columns (ID not PATID -- Pitfall 4; ADDRESS_ZIP9 required)
required_cols <- c("ID", "ADDRESS_ZIP9")
missing_cols <- setdiff(required_cols, names(addr))
if (length(missing_cols) > 0) {
  stop(glue(
    "Required column(s) missing from {ADDR_FILENAME}: {paste(missing_cols, collapse=', ')}\n",
    "  Available columns: {paste(names(addr), collapse=', ')}"
  ))
}

n_patients_raw <- n_distinct(addr$ID)
message(glue("  Distinct patients (ID): {n_patients_raw}"))

# Log fill rates for open questions (OQ2, OQ3)
n_addr_zip9_nonNA  <- sum(!is.na(addr$ADDRESS_ZIP9) & trimws(addr$ADDRESS_ZIP9) != "", na.rm = TRUE)
n_addr_zip5_nonNA  <- if ("ADDRESS_ZIP5" %in% names(addr)) {
  sum(!is.na(addr$ADDRESS_ZIP5) & trimws(addr$ADDRESS_ZIP5) != "", na.rm = TRUE)
} else { 0L }
n_preferred_Y      <- if ("ADDRESS_PREFERRED" %in% names(addr)) {
  sum(addr$ADDRESS_PREFERRED == "Y", na.rm = TRUE)
} else { 0L }

message(glue("  ADDRESS_ZIP9 non-NA:     {n_addr_zip9_nonNA} / {n_rows} ({round(100*n_addr_zip9_nonNA/n_rows,1)}%)"))
message(glue("  ADDRESS_ZIP5 non-NA:     {n_addr_zip5_nonNA} / {n_rows} ({round(100*n_addr_zip5_nonNA/n_rows,1)}%)"))
message(glue("  ADDRESS_PREFERRED == Y:  {n_preferred_Y} / {n_rows} ({round(100*n_preferred_Y/n_rows,1)}%)"))


# ==============================================================================
# SECTION 4: HELPER FUNCTIONS ----
# ==============================================================================

# Normalize ZIP9: strip hyphen, then accept ONLY 8- or 9-digit numeric strings
# (8 = a genuine ZIP9 that dropped its single leading zero). Left-pad 8 -> 9.
# Anything else (bare ZIP5, too-short, non-numeric) -> NA rather than being mangled.
normalize_zip9 <- function(zip) {
  z <- str_remove_all(str_trim(zip), "-")
  z <- if_else(str_detect(z, "^[0-9]{8,9}$"), str_pad(z, 9, pad = "0"), NA_character_)
  if_else(str_detect(z, "^[0-9]{9}$"), z, NA_character_)
}

# Normalize ZIP5: first 5 characters of a clean ZIP9.
normalize_zip5 <- function(zip9_clean) {
  str_sub(zip9_clean, 1, 5)
}

# Normalize a raw ZIP5 column: trim, pad to 5, validate ^[0-9]{5}$.
normalize_zip5_raw <- function(zip) {
  z <- str_remove_all(str_trim(zip), "-")
  z <- str_pad(z, 5, pad = "0")
  if_else(str_detect(z, "^[0-9]{5}$"), z, NA_character_)
}

# HIPAA small-cell suppression: replace counts 1-10 with "<11".
# This is the project's standard HIPAA rule for shareable output.
suppress_small <- function(n) {
  if_else(n >= 1 & n <= 10, "<11", as.character(n))
}


# ==============================================================================
# SECTION 5: ZIP NORMALIZATION AND ZIP5 SOURCING (Pitfall 3) ----
# ==============================================================================

message("--- Normalizing ZIP codes ---")

addr <- addr %>%
  mutate(
    zip9_norm = normalize_zip9(ADDRESS_ZIP9)
  )

# ZIP5 SOURCING RULE (Pitfall 3): prefer ADDRESS_ZIP5 column when populated;
# derive from normalize_zip9() when ADDRESS_ZIP5 is blank/NA.
if ("ADDRESS_ZIP5" %in% names(addr)) {
  addr <- addr %>%
    mutate(
      zip5_from_col    = normalize_zip5_raw(ADDRESS_ZIP5),
      zip5_from_zip9   = normalize_zip5(zip9_norm),
      # Use the explicit column if non-NA; fall back to derived
      zip5_norm = if_else(!is.na(zip5_from_col), zip5_from_col, zip5_from_zip9)
    )
  # Log mismatch count (data quality awareness)
  n_mismatch <- sum(
    !is.na(addr$zip5_from_col) & !is.na(addr$zip5_from_zip9) &
    addr$zip5_from_col != addr$zip5_from_zip9,
    na.rm = TRUE
  )
  message(glue("  ZIP5 column vs derived mismatch: {n_mismatch} records"))
} else {
  # ADDRESS_ZIP5 column absent -- derive entirely from ZIP9
  addr <- addr %>%
    mutate(zip5_norm = normalize_zip5(zip9_norm))
  n_mismatch <- 0L
  message("  ADDRESS_ZIP5 column not present -- ZIP5 derived entirely from ADDRESS_ZIP9")
}

n_na_zip9  <- sum(is.na(addr$zip9_norm))
n_na_zip5  <- sum(is.na(addr$zip5_norm))
message(glue("  NA ZIP9 after normalization:  {n_na_zip9}"))
message(glue("  NA ZIP5 after normalization:  {n_na_zip5}"))


# ==============================================================================
# SECTION 6 (DATA PREP): PER-PATIENT ZIP METRICS grouped by ID ----
# ==============================================================================

# Filter !is.na on each zip BEFORE n_distinct (Pitfall 5a: NA would count as distinct)
patient_zip9 <- addr %>%
  filter(!is.na(zip9_norm)) %>%
  group_by(ID) %>%
  summarise(
    n_zip9_distinct   = n_distinct(zip9_norm),
    .groups = "drop"
  )

patient_zip5 <- addr %>%
  filter(!is.na(zip5_norm)) %>%
  group_by(ID) %>%
  summarise(
    n_zip5_distinct = n_distinct(zip5_norm),
    .groups = "drop"
  )

# Patients dropped because ALL ZIP values were NA
all_ids <- tibble(ID = unique(addr$ID))
n_all_na_zip9 <- nrow(all_ids) - nrow(patient_zip9)
n_all_na_zip5 <- nrow(all_ids) - nrow(patient_zip5)
message(glue("  Patients dropped (all ZIP9 NA): {n_all_na_zip9}"))
message(glue("  Patients dropped (all ZIP5 NA): {n_all_na_zip5}"))

# Join ZIP9 and ZIP5 per-patient summaries
patient_metrics <- all_ids %>%
  left_join(patient_zip9, by = "ID") %>%
  left_join(patient_zip5, by = "ID") %>%
  mutate(
    n_zip9_distinct    = replace_na(n_zip9_distinct, 0L),
    n_zip5_distinct    = replace_na(n_zip5_distinct, 0L),
    zip9_ever_changed  = n_zip9_distinct > 1,
    zip5_ever_changed  = n_zip5_distinct > 1,
    # Assumes n_zip9_distinct and n_zip5_distinct are computed over the same row
    # set. Harmless when ZIP5 is derived entirely from ZIP9, but when an explicit
    # ADDRESS_ZIP5 column is present, zip5_norm can be valid on rows where
    # zip9_norm is NA -- the two counts then come from different row sets and
    # this flag can misclassify.
    zip9_change_only   = n_zip9_distinct > 1 & n_zip5_distinct == 1
  )

n_patients_total <- nrow(patient_metrics)


# ==============================================================================
# SECTION 7 (SHEET 1): ZIP CHANGE DISTRIBUTION ----
# ==============================================================================
# Rows: distinct-count bucket (1=never changed, 2, 3, 4+)
# Columns: n_patients_zip9 + pct_zip9 + n_patients_zip5 + pct_zip5 + Total row
# Patient-count distribution. Small cells ARE possible here -- counts are HIPAA-suppressed below.

zip9_dist <- patient_metrics %>%
  filter(n_zip9_distinct > 0) %>%
  mutate(bucket = case_when(
    n_zip9_distinct == 1 ~ "1 (never changed)",
    n_zip9_distinct == 2 ~ "2",
    n_zip9_distinct == 3 ~ "3",
    TRUE                 ~ "4+"
  )) %>%
  group_by(bucket) %>%
  summarise(n_patients_zip9 = n(), .groups = "drop") %>%
  mutate(pct_zip9 = round(100 * n_patients_zip9 / sum(n_patients_zip9), 1))

zip5_dist <- patient_metrics %>%
  filter(n_zip5_distinct > 0) %>%
  mutate(bucket = case_when(
    n_zip5_distinct == 1 ~ "1 (never changed)",
    n_zip5_distinct == 2 ~ "2",
    n_zip5_distinct == 3 ~ "3",
    TRUE                 ~ "4+"
  )) %>%
  group_by(bucket) %>%
  summarise(n_patients_zip5 = n(), .groups = "drop") %>%
  mutate(pct_zip5 = round(100 * n_patients_zip5 / sum(n_patients_zip5), 1))

bucket_order <- c("1 (never changed)", "2", "3", "4+")
sheet1 <- tibble(bucket = bucket_order) %>%
  left_join(zip9_dist, by = "bucket") %>%
  left_join(zip5_dist, by = "bucket") %>%
  replace_na(list(n_patients_zip9 = 0L, pct_zip9 = 0, n_patients_zip5 = 0L, pct_zip5 = 0)) %>%
  rename(`Distinct ZIP Count` = bucket,
         `N Patients (ZIP9)`  = n_patients_zip9,
         `Pct (ZIP9)`         = pct_zip9,
         `N Patients (ZIP5)`  = n_patients_zip5,
         `Pct (ZIP5)`         = pct_zip5)

# Add total row (computed BEFORE suppression converts N columns to strings)
total_row <- tibble(
  `Distinct ZIP Count` = "Total",
  `N Patients (ZIP9)`  = sum(sheet1$`N Patients (ZIP9)`),
  `Pct (ZIP9)`         = round(sum(sheet1$`Pct (ZIP9)`), 1),
  `N Patients (ZIP5)`  = sum(sheet1$`N Patients (ZIP5)`),
  `Pct (ZIP5)`         = round(sum(sheet1$`Pct (ZIP5)`), 1)
)
sheet1 <- bind_rows(sheet1, total_row)

# HIPAA small-cell suppression on displayed counts (Total row stays exact --
# it's the full published denominator, not a suppressible cell).
sheet1 <- sheet1 %>%
  mutate(
    `N Patients (ZIP9)` = if_else(`Distinct ZIP Count` == "Total",
                                  as.character(`N Patients (ZIP9)`),
                                  suppress_small(`N Patients (ZIP9)`)),
    `N Patients (ZIP5)` = if_else(`Distinct ZIP Count` == "Total",
                                  as.character(`N Patients (ZIP5)`),
                                  suppress_small(`N Patients (ZIP5)`))
  )


# ==============================================================================
# SECTION 8 (SHEET 2): CHANGE RATES, ZIP9-CHANGE-ONLY, HISTOGRAM ----
# ==============================================================================

n_zip9_changed     <- sum(patient_metrics$zip9_ever_changed, na.rm = TRUE)
n_zip5_changed     <- sum(patient_metrics$zip5_ever_changed, na.rm = TRUE)
n_zip9_change_only <- sum(patient_metrics$zip9_change_only, na.rm = TRUE)

pct_ever_changed_zip9  <- round(100 * n_zip9_changed / n_patients_total, 1)
pct_ever_changed_zip5  <- round(100 * n_zip5_changed / n_patients_total, 1)
pct_zip9_change_only   <- round(100 * n_zip9_change_only / n_patients_total, 1)

med_zip9   <- median(patient_metrics$n_zip9_distinct[patient_metrics$n_zip9_distinct > 0], na.rm = TRUE)
p25_zip9   <- quantile(patient_metrics$n_zip9_distinct[patient_metrics$n_zip9_distinct > 0], 0.25, na.rm = TRUE)
p75_zip9   <- quantile(patient_metrics$n_zip9_distinct[patient_metrics$n_zip9_distinct > 0], 0.75, na.rm = TRUE)
med_zip5   <- median(patient_metrics$n_zip5_distinct[patient_metrics$n_zip5_distinct > 0], na.rm = TRUE)
p25_zip5   <- quantile(patient_metrics$n_zip5_distinct[patient_metrics$n_zip5_distinct > 0], 0.25, na.rm = TRUE)
p75_zip5   <- quantile(patient_metrics$n_zip5_distinct[patient_metrics$n_zip5_distinct > 0], 0.75, na.rm = TRUE)

headline_stats <- tibble(
  Metric = c(
    "Total patients in LDS_ADDRESS_HISTORY",
    "N patients with any ZIP9 change",
    "% patients with any ZIP9 change",
    "N patients with any ZIP5 change",
    "% patients with any ZIP5 change",
    "N patients ZIP9-change-only (ZIP9 changed, ZIP5 unchanged)",
    "% patients ZIP9-change-only",
    "Median distinct ZIP9 values (patients with valid ZIP9)",
    "p25 distinct ZIP9",
    "p75 distinct ZIP9",
    "Median distinct ZIP5 values (patients with valid ZIP5)",
    "p25 distinct ZIP5",
    "p75 distinct ZIP5"
  ),
  Value = c(
    as.character(n_patients_total),
    suppress_small(n_zip9_changed),      as.character(pct_ever_changed_zip9),
    suppress_small(n_zip5_changed),      as.character(pct_ever_changed_zip5),
    suppress_small(n_zip9_change_only),  as.character(pct_zip9_change_only),
    as.character(med_zip9), as.character(p25_zip9), as.character(p75_zip9),
    as.character(med_zip5), as.character(p25_zip5), as.character(p75_zip5)
  )
)

# Change-count histogram (n_changes = n_distinct - 1)
# HIPAA suppression: replace cells with 1-10 patients with "<11" (Pitfall 5b)
zip9_hist <- patient_metrics %>%
  filter(n_zip9_distinct > 0) %>%
  mutate(n_changes = n_zip9_distinct - 1L,
         bucket = case_when(
           n_changes == 0 ~ "0 changes",
           n_changes == 1 ~ "1 change",
           n_changes == 2 ~ "2 changes",
           TRUE           ~ "3+ changes"
         )) %>%
  group_by(bucket) %>%
  summarise(n_patients_raw = n(), .groups = "drop") %>%
  mutate(
    n_patients = suppress_small(n_patients_raw),  # HIPAA small-cell suppression (<=10 -> "<11")
    zip_type   = "ZIP9"
  ) %>%
  select(zip_type, bucket, n_patients)

zip5_hist <- patient_metrics %>%
  filter(n_zip5_distinct > 0) %>%
  mutate(n_changes = n_zip5_distinct - 1L,
         bucket = case_when(
           n_changes == 0 ~ "0 changes",
           n_changes == 1 ~ "1 change",
           n_changes == 2 ~ "2 changes",
           TRUE           ~ "3+ changes"
         )) %>%
  group_by(bucket) %>%
  summarise(n_patients_raw = n(), .groups = "drop") %>%
  mutate(
    n_patients = suppress_small(n_patients_raw),
    zip_type   = "ZIP5"
  ) %>%
  select(zip_type, bucket, n_patients)

change_hist <- bind_rows(zip9_hist, zip5_hist) %>%
  rename(`ZIP Type` = zip_type, `Change Bucket` = bucket, `N Patients (HIPAA suppressed if <=10)` = n_patients)

sheet2_stats <- headline_stats
sheet2_hist  <- change_hist


# ==============================================================================
# SECTION 9 (SHEET 3): TIME BETWEEN CHANGES ----
# ==============================================================================

message("--- Computing time between ZIP changes ---")

# Parse ADDRESS_PERIOD_START (uses parse_pcornet_date from utils_dates)
# Guard: do NOT filter on ADDRESS_PERIOD_END (open-ended addresses have NA end -- Pitfall 2)
if ("ADDRESS_PERIOD_START" %in% names(addr)) {
  addr_dates_parsed <- addr %>%
    mutate(period_start_dt = parse_pcornet_date(ADDRESS_PERIOD_START))

  # Exclude ADDRESS_PERIOD_START values outside the LDS_ADDRESS_HISTORY
  # study period (2012-01-01 to 2025-03-31) BEFORE computing gap-days --
  # out-of-range/garbage dates (epoch sentinels, post-cutoff dates) would
  # otherwise silently pollute the median/p25/p75 gap stats and the
  # Sheet 5 recommendation text derived from them.
  n_period_start_out_of_range <- sum(
    !is.na(addr_dates_parsed$period_start_dt) &
      (addr_dates_parsed$period_start_dt < ZIP_STUDY_PERIOD_MIN |
         addr_dates_parsed$period_start_dt > ZIP_STUDY_PERIOD_MAX)
  )
  message(glue(
    "  ADDRESS_PERIOD_START rows dropped for being outside study period ",
    "({ZIP_STUDY_PERIOD_MIN} to {ZIP_STUDY_PERIOD_MAX}): {n_period_start_out_of_range}"
  ))

  addr_with_dates <- addr_dates_parsed %>%
    filter(
      !is.na(period_start_dt),
      period_start_dt >= ZIP_STUDY_PERIOD_MIN,
      period_start_dt <= ZIP_STUDY_PERIOD_MAX,
      !is.na(zip9_norm)
    )

  # Time BETWEEN ZIP9 CHANGES: order each patient's records by date, collapse
  # consecutive same-ZIP periods to their first date, then diff those change points.
  gap_rows <- addr_with_dates %>%
    select(ID, period_start_dt, zip9_norm) %>%
    distinct() %>%
    arrange(ID, period_start_dt) %>%
    group_by(ID) %>%
    mutate(is_change = is.na(lag(zip9_norm)) | zip9_norm != lag(zip9_norm)) %>%
    filter(is_change) %>%                                   # keep first date of each ZIP run
    mutate(gaps_days = as.numeric(difftime(period_start_dt,
                                           lag(period_start_dt), units = "days"))) %>%
    ungroup() %>%
    filter(!is.na(gaps_days)) %>%
    select(ID, gaps_days)

  n_patients_1date <- addr_with_dates %>%
    distinct(ID, period_start_dt) %>%
    count(ID) %>%
    summarise(n = sum(n <= 1)) %>%
    pull(n)

  message(glue("  Patients with only 1 distinct ADDRESS_PERIOD_START (no gap): {n_patients_1date}"))
  message(glue("  Total ZIP-change gap observations: {nrow(gap_rows)}"))

  if (nrow(gap_rows) > 0) {
    gap_summary <- tibble(
      Metric = c("N gap observations", "Median gap (days)", "p25 gap (days)",
                 "p75 gap (days)", "Min gap (days)", "Max gap (days)"),
      Value  = as.character(c(
        nrow(gap_rows),
        round(median(gap_rows$gaps_days, na.rm = TRUE), 1),
        round(quantile(gap_rows$gaps_days, 0.25, na.rm = TRUE), 1),
        round(quantile(gap_rows$gaps_days, 0.75, na.rm = TRUE), 1),
        round(min(gap_rows$gaps_days, na.rm = TRUE), 1),
        round(max(gap_rows$gaps_days, na.rm = TRUE), 1)
      ))
    )

    # Histogram buckets with HIPAA suppression
    gap_hist <- gap_rows %>%
      mutate(bucket = case_when(
        gaps_days < 30                    ~ "<30 days",
        gaps_days < 181                   ~ "30-180 days",
        gaps_days < 366                   ~ "181-365 days",
        gaps_days < 731                   ~ "1-2 years",
        TRUE                              ~ ">2 years"
      )) %>%
      group_by(bucket) %>%
      summarise(n_gaps_raw = n(), .groups = "drop") %>%
      mutate(
        n_gaps = suppress_small(n_gaps_raw)  # HIPAA suppression <=10
      ) %>%
      select(bucket, n_gaps) %>%
      rename(`Gap Duration Bucket` = bucket, `N Gaps (HIPAA suppressed if <=10)` = n_gaps)
  } else {
    gap_summary <- tibble(Metric = "No gap data available", Value = "0 patients with 2+ address dates")
    gap_hist    <- tibble(`Gap Duration Bucket` = character(0), `N Gaps (HIPAA suppressed if <=10)` = character(0))
  }

  sheet3_summary <- gap_summary
  sheet3_hist    <- gap_hist

} else {
  message("  ADDRESS_PERIOD_START column not found -- Sheet 3 will contain placeholder")
  sheet3_summary <- tibble(Metric = "ADDRESS_PERIOD_START not available", Value = "column absent from extract")
  sheet3_hist    <- tibble(`Gap Duration Bucket` = "N/A", `N Gaps (HIPAA suppressed if <=10)` = "N/A")
}


# ==============================================================================
# SECTION 10 (SHEET 4): TIE-BREAK COMPARISON (D-11) ----
# ==============================================================================

message("--- Computing tie-break disagreement ---")

# For patients with 2+ distinct ZIP9, compare:
#   most_recent_zip9: ZIP9 on the record with max ADDRESS_PERIOD_START
#                     (break ties by ADDRESS_PREFERRED == "Y" WHEN populated)
#   modal_zip9:       most frequent ZIP9 (ties broken by recency)
# Report only agree/disagree counts -- NOT individual ZIP9 values (HIPAA)

has_period_start   <- "ADDRESS_PERIOD_START" %in% names(addr)
has_preferred      <- "ADDRESS_PREFERRED"    %in% names(addr)
pref_fill_rate     <- if (has_preferred) n_preferred_Y / n_rows else 0

# FALLBACK: if ADDRESS_PREFERRED is <5% populated, use recency alone
use_preferred <- has_preferred && pref_fill_rate >= 0.05

tiebreak_subtitle <- if (use_preferred) {
  glue("Most-recent vs modal tie-break using ADDRESS_PERIOD_START + ADDRESS_PREFERRED (fill rate {round(100*pref_fill_rate,1)}%)")
} else {
  glue("Most-recent vs modal tie-break using ADDRESS_PERIOD_START only (ADDRESS_PREFERRED fill rate {round(100*pref_fill_rate,1)}% < 5% threshold)")
}

multi_zip_patients <- patient_metrics %>%
  filter(n_zip9_distinct >= 2) %>%
  pull(ID)

n_patients_evaluated <- length(multi_zip_patients)
message(glue("  Patients with 2+ distinct ZIP9 (evaluated for tie-break): {n_patients_evaluated}"))

if (n_patients_evaluated > 0 && has_period_start) {
  addr_multi <- addr %>%
    filter(ID %in% multi_zip_patients, !is.na(zip9_norm)) %>%
    mutate(period_start_dt = parse_pcornet_date(ADDRESS_PERIOD_START))

  # Most-recent: max period_start_dt, break ties by ADDRESS_PREFERRED == "Y"
  if (use_preferred) {
    most_recent_tbl <- addr_multi %>%
      group_by(ID) %>%
      arrange(desc(period_start_dt), desc(ADDRESS_PREFERRED == "Y"), .by_group = TRUE) %>%
      slice(1) %>%
      ungroup() %>%
      select(ID, most_recent_zip9 = zip9_norm)
  } else {
    most_recent_tbl <- addr_multi %>%
      group_by(ID) %>%
      arrange(desc(period_start_dt), .by_group = TRUE) %>%
      slice(1) %>%
      ungroup() %>%
      select(ID, most_recent_zip9 = zip9_norm)
  }

  # Modal: most frequent ZIP9; ties broken by recency (most recent of the tied modals)
  modal_tbl <- addr_multi %>%
    group_by(ID, zip9_norm) %>%
    summarise(
      freq          = n(),
      latest_date   = suppressWarnings(max(period_start_dt, na.rm = TRUE)),
      .groups = "drop"
    ) %>%
    group_by(ID) %>%
    arrange(desc(freq), desc(latest_date), .by_group = TRUE) %>%
    slice(1) %>%
    ungroup() %>%
    select(ID, modal_zip9 = zip9_norm)

  tiebreak_compare <- most_recent_tbl %>%
    inner_join(modal_tbl, by = "ID") %>%
    mutate(agree = most_recent_zip9 == modal_zip9)

  n_agree    <- sum(tiebreak_compare$agree, na.rm = TRUE)
  n_disagree <- sum(!tiebreak_compare$agree, na.rm = TRUE)
  pct_disagree <- round(100 * n_disagree / n_patients_evaluated, 1)

} else {
  n_agree      <- 0L
  n_disagree   <- 0L
  pct_disagree <- 0
}

# Output ONLY the agree/disagree counts -- NOT individual ZIP9 values (HIPAA)
sheet4 <- tibble(
  Metric = c(
    "Patients with 2+ distinct ZIP9 (evaluated)",
    "Agree (most-recent == modal)",
    "Disagree (most-recent != modal)",
    "% disagreement (pct_disagree)"
  ),
  Value = as.character(c(
    n_patients_evaluated, n_agree, n_disagree, pct_disagree
  ))
)


# ==============================================================================
# SECTION 11: CONSOLE SUMMARY (D-09) ----
# ==============================================================================

message("\n=== Phase 121: ZIP Change Frequency -- Headline Stats ===")
message(glue("  n_patients_total:          {n_patients_total}"))
message(glue("  pct_ever_changed_zip9:     {pct_ever_changed_zip9}%"))
message(glue("  pct_ever_changed_zip5:     {pct_ever_changed_zip5}%"))
message(glue("  pct_zip9_change_only:      {pct_zip9_change_only}%  (ZIP9 changed, ZIP5 did not)"))
message(glue("  median_distinct_zip9:      {med_zip9}"))
message(glue("  n_with_na_zip9:            {n_na_zip9}  (records with no valid ZIP9 after normalization)"))
message(glue("  pct_disagree (tie-break):  {pct_disagree}%  (most-recent != modal for patients with 2+ ZIP9)"))
message("=======================================================\n")


# ==============================================================================
# SECTION 12 (SHEET 5): RECOMMENDATION AND METADATA ----
# ==============================================================================

# HL cohort overlap footnote (use get_hl_patient_ids() if available -- OQ4)
hl_overlap_note <- tryCatch({
  hl_ids <- get_hl_patient_ids()
  n_hl   <- length(hl_ids)
  n_overlap <- sum(unique(addr$ID) %in% hl_ids)
  glue("HL cohort overlap: {n_overlap} of {n_hl} HL patients present in LDS_ADDRESS_HISTORY")
}, error = function(e) {
  "HL cohort overlap: not computed (get_hl_patient_ids() unavailable or errored)"
})

# Recommendation text keyed off pct_ever_changed and pct_disagree
recommendation_text <- if (pct_ever_changed_zip5 < 10) {
  glue(
    "Only {pct_ever_changed_zip5}% of patients ever changed ZIP5 and {pct_ever_changed_zip9}% ever changed ZIP9. ",
    "A single ZIP5 per patient is likely defensible for SVI (census-tract-based) given the low change rate. ",
    "ZIP9 change-only cases ({pct_zip9_change_only}%) represent intra-ZIP5 moves that matter for ADI (block-group precision) ",
    "but the overall stability suggests a single most-recent or modal ZIP9 is adequate for most SES index work. ",
    "Tie-break disagreement rate of {pct_disagree}% should inform which selection rule is used."
  )
} else if (pct_ever_changed_zip5 < 30) {
  glue(
    "{pct_ever_changed_zip5}% of patients changed ZIP5 at least once and {pct_ever_changed_zip9}% changed ZIP9. ",
    "A single ZIP5 per patient may be acceptable for SVI linkage given moderate change rates, but the {pct_zip9_change_only}% ",
    "ZIP9-change-only cases and {pct_disagree}% tie-break disagreement rate suggest the selection rule (most-recent vs modal) ",
    "materially affects ADI linkage results. Time-varying handling is worth considering for ADI."
  )
} else {
  glue(
    "{pct_ever_changed_zip5}% of patients changed ZIP5 and {pct_ever_changed_zip9}% changed ZIP9. ",
    "The high ZIP change rate makes a single ZIP per patient a meaningful simplification. ",
    "Time-varying ZIP handling is recommended for ADI (block-group) and should be considered for SVI. ",
    "Tie-break disagreement rate of {pct_disagree}% confirms that the choice of most-recent vs modal ZIP rules is non-trivial."
  )
}

zip5_source_note <- if ("ADDRESS_ZIP5" %in% names(addr)) {
  glue("ZIP5 sourced from ADDRESS_ZIP5 column ({n_addr_zip5_nonNA} records); derived from ADDRESS_ZIP9 for remaining records where ZIP5 was blank.")
} else {
  "ZIP5 derived entirely from ADDRESS_ZIP9 (ADDRESS_ZIP5 column absent from extract)."
}

sheet5 <- tibble(
  Field = c(
    "Source file",
    "Row count",
    "Distinct patient count",
    "Run date",
    "NA ZIP9 count (after normalization)",
    "NA ZIP5 count (after normalization)",
    "ADDRESS_ZIP5 vs derived mismatch count",
    "ADDRESS_PREFERRED fill rate",
    "ZIP5 source note",
    "HL cohort overlap",
    "Recommendation"
  ),
  Value = c(
    basename(addr_path),
    as.character(n_rows),
    as.character(n_patients_raw),
    as.character(Sys.Date()),
    as.character(n_na_zip9),
    as.character(n_na_zip5),
    as.character(n_mismatch),
    glue("{round(100*pref_fill_rate,1)}% ADDRESS_PREFERRED == 'Y'"),
    zip5_source_note,
    hl_overlap_note,
    recommendation_text
  )
)


# ==============================================================================
# SECTION 13: WRITE STYLED XLSX ----
# ==============================================================================

# add_styled_sheet helper and color constants copied VERBATIM from
# R/100_ruca_rurality_summary.R lines 328-367
DARK_GRAY <- wb_color("FF374151")
WHITE     <- wb_color("FFFFFFFF")
DARK_TEXT <- wb_color("FF1F2937")

#' Add a styled sheet to the workbook
#'
#' Writes a data table to a new sheet with a title row (row 1), subtitle row
#' (row 2), dark-gray header row (row 4), and frozen top rows. Data starts at
#' row 4 so rows 1-2 are informational text above the header.
#'
#' @param wb An openxlsx2 workbook object (modified in place via reference).
#' @param sheet_name Character. Name for the new worksheet.
#' @param title_text Character. Title string written to A1.
#' @param subtitle_text Character. Subtitle / grain description written to A2.
#' @param data_tbl Data frame. Table to write starting at A4.
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
  wb$add_fill(sheet = sheet_name, dims = header_range, color = DARK_GRAY)
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
    wb$add_fill(sheet = sheet_name, dims = extra_hdr_rng, color = DARK_GRAY)
    wb$add_font(sheet = sheet_name, dims = extra_hdr_rng,
                name = "Calibri", size = 11, bold = TRUE, color = WHITE)
  }

  wb$freeze_pane(sheet = sheet_name, firstActiveRow = 5)
  wb$set_col_widths(sheet = sheet_name, cols = 1:max(n_cols, ncol(extra_tbl %||% data_tbl)),
                    widths = "auto")
}

message("--- Writing zip_change_frequency.xlsx ---")

wb <- wb_workbook()

add_styled_sheet(
  wb, "ZIP Change Distribution",
  title_text    = "ZIP Change Distribution -- Patient-Level Distinct ZIP Counts",
  subtitle_text = "Grain: unique patient (ID). Rows = n_distinct_zip bucket. ZIP9 and ZIP5 shown side-by-side (D-05). Counts are patient counts, not individual ZIP codes (HIPAA-safe). Percentages are of patients with >=1 valid ZIP of that type.",
  data_tbl      = sheet1
)

add_styled_sheet(
  wb, "Change Rates & Histogram",
  title_text    = "Change Rates & Histogram -- ZIP9, ZIP5, and ZIP9-Change-Only",
  subtitle_text = glue("Headline stats + change-count histogram. ZIP9-change-only = ZIP9 changed but ZIP5 did not ({pct_zip9_change_only}%). HIPAA: cells <=10 replaced with '<11'. Percentages are of all {n_patients_total} patients in the table (incl. those with no valid ZIP)."),
  data_tbl      = sheet2_stats,
  extra_tbl     = sheet2_hist,
  extra_label   = "Change-count histogram (patients, HIPAA suppressed if <=10)"
)

add_styled_sheet(
  wb, "Time Between Changes",
  title_text    = "Time Between ZIP Changes -- Gap-Day Distribution",
  subtitle_text = "Derived from ADDRESS_PERIOD_START, measured between actual ZIP9 changes (consecutive same-ZIP periods collapsed). HIPAA suppression applied.",
  data_tbl      = sheet3_summary,
  extra_tbl     = sheet3_hist,
  extra_label   = "Gap-duration histogram (gaps, HIPAA suppressed if <=10)"
)

add_styled_sheet(
  wb, "Tie-Break Comparison",
  title_text    = "Most-Recent vs Modal ZIP9 Tie-Break Comparison (D-11)",
  subtitle_text = tiebreak_subtitle,
  data_tbl      = sheet4
)

add_styled_sheet(
  wb, "Recommendation & Metadata",
  title_text    = "Recommendation & Metadata -- Phase 121 ZIP Change Frequency",
  subtitle_text = glue("Run {Sys.Date()}. Source: {basename(addr_path)}. Script: R/106_zip_change_frequency.R (Phase 121)."),
  data_tbl      = sheet5
)

wb_save(wb, OUTPUT_XLSX)
message(glue("[R/106] xlsx written to: {OUTPUT_XLSX}"))
message("[R/106] Phase 121 ZIP change frequency investigation complete.")
