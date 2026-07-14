# ==============================================================================
# 107_med_admin_dispensing_gap_diagnostic.R -- MED_ADMIN / DISPENSING
#   Chemo-Gap Sizing Diagnostic (quick-260714-end)
# ==============================================================================
# Purpose:     READ-ONLY diagnostic that SIZES the confirmed latent gap where
#              DISPENSING and MED_ADMIN silently contribute ZERO chemo treatment
#              detection in R/26. Both tables are gated on
#              `"RXNORM_CUI" %in% colnames(...)` — a column this OneFlorida+
#              extract lacks in those two tables — so every R/26 consumer drops
#              them entirely. Meanwhile MED_ADMIN rows with MEDADMIN_TYPE=='RX'
#              carry RxNorm CUIs directly in MEDADMIN_CODE, which could be matched
#              against TREATMENT_CODES$chemo_rxnorm. DISPENSING has NDC only and
#              cannot be chemo-matched without a crosswalk not present in this repo.
#
#              This script quantifies, BEFORE deciding whether to fix R/26:
#                1. PRESCRIBING RXNORM_CUI baseline (what R/26 already captures).
#                2. MED_ADMIN INCREMENTAL contribution beyond PRESCRIBING:
#                     - New patients (in MED_ADMIN chemo but NOT in PRESCRIBING).
#                     - New (ID, date) pairs not in PRESCRIBING.
#                     - Patients whose earliest MED_ADMIN chemo date is EARLIER
#                       than their PRESCRIBING first-chemo date (first-date shifts).
#                3. MED_ADMIN MEDADMIN_TYPE=='ND' volume — would need NDC->RxNorm
#                     crosswalk; reported as footprint only, not matched.
#                4. DISPENSING footprint (rows / patients / dates) — NDC-only;
#                     NO chemo match performed; explicitly flagged as needing
#                     an NDC->RxNorm crosswalk before any chemo inference.
#
# Inputs:      DuckDB PRESCRIBING table (RXNORM_CUI baseline)
#              DuckDB MED_ADMIN table   (MEDADMIN_TYPE, MEDADMIN_CODE,
#                                        MEDADMIN_START_DATE, RAW_MEDADMIN_MED_NAME)
#              DuckDB DISPENSING table  (DISPENSE_DATE, NDC — no RXNORM_CUI)
#
# Outputs:     output/med_admin_dispensing_gap_diagnostic.csv
#                Columns: scope, source, n_rows, n_patients, n_id_date_pairs,
#                         n_distinct_codes, note
#              (Console) per-section counts + HEADLINE increment summary.
#
# Dependencies: R/00_config.R (provides TREATMENT_CODES$chemo_rxnorm,
#               CONFIG$output_dir, auto-sources utils_duckdb + utils_dates +
#               utils_treatment + utils_cancer)
#               R/utils/utils_duckdb.R (open_pcornet_con, get_pcornet_table,
#                                       close_pcornet_con)
#               R/utils/utils_dates.R  (parse_pcornet_date)
#               R/utils/utils_treatment.R (get_hl_patient_ids)
#               tidyverse ecosystem: dplyr, glue, stringr, lubridate
#
# Requirements: quick-260714-end (QUICK-260714-END)
#
# Usage:       Rscript R/107_med_admin_dispensing_gap_diagnostic.R
#              source("R/107_med_admin_dispensing_gap_diagnostic.R")
#
# Note:        READ-ONLY investigation. Structural-only verification on Windows
#              (no Rscript; local fixtures lack real column layout). Full run with
#              counts is HiPerGator ONLY (requires DuckDB PCORnet data with the
#              real DISPENSING/MED_ADMIN CSVs). This script must NOT touch R/26,
#              R/00_config, or any cohort/episode output file.
#
# REGISTRATION NOTE: This is a ONE-OFF sizing diagnostic — NOT wired into R/39
#              and NOT registered in R/88 sections. Registration is limited to
#              SCRIPT_INDEX.md only (see Post-Renumber Investigations table).
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

# get_hl_patient_ids is auto-sourced by R/00_config via utils_treatment; source
# defensively if not yet on search path (e.g. partial standalone source).
if (!exists("get_hl_patient_ids")) {
  source("R/utils/utils_treatment.R")
}

message("=== quick-260714-end: MED_ADMIN / DISPENSING Chemo-Gap Sizing Diagnostic ===\n")


# ==============================================================================
# SECTION 2: CONSTANTS AND HIPAA HELPER ----
# ==============================================================================

CHEMO_RXNORM <- TREATMENT_CODES$chemo_rxnorm
message(glue("Chemo RxNorm CUI list: {length(CHEMO_RXNORM)} codes loaded from TREATMENT_CODES$chemo_rxnorm\n"))

OUTPUT_CSV <- file.path(CONFIG$output_dir, "med_admin_dispensing_gap_diagnostic.csv")
message(glue("Diagnostic artifact target: {OUTPUT_CSV}\n"))

# HIPAA helper: patient counts 1-10 are suppressed in any persisted/printed
# per-group breakdown to prevent re-identification. Applies to n_patients fields
# in the output CSV and to per-group patient-count console lines.
suppress_small <- function(n) {
  if (!is.na(n) && n >= 1L && n <= 10L) NA_integer_ else as.integer(n)
}


# ==============================================================================
# SECTION 3: SELF-BOOTSTRAP DUCKDB ----
# ==============================================================================

# Self-bootstrap the DuckDB connection so R/107 runs standalone in a fresh
# session (consistent with R/103, R/102). open_pcornet_con() is idempotent.
USE_DUCKDB <- TRUE
if (!exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}


# ==============================================================================
# SECTION 4: COHORT SCOPE (HL PATIENT IDS) ----
# ==============================================================================

message("--- Section 4: Cohort scope ---")
hl_ids <- get_hl_patient_ids()
n_hl <- length(hl_ids)
message(glue("  HL cohort patient count: {format(n_hl, big.mark = ',')}"))

if (n_hl == 0L) {
  message("  WARNING: get_hl_patient_ids() returned 0 IDs (DIAGNOSIS table absent or empty?).")
  message("  Falling back to ALL-PATIENT scope for cohort fields — counts will be inflated.\n")
  cohort_fallback <- TRUE
} else {
  cohort_fallback <- FALSE
  message(glue("  Using HL cohort (n = {format(n_hl, big.mark = ',')}) for cohort-scoped metrics.\n"))
}

# Internal helper: apply cohort filter or return data unchanged (fallback).
filter_to_cohort <- function(df) {
  if (cohort_fallback) return(df)
  df %>% filter(ID %in% hl_ids)
}


# ==============================================================================
# SECTION 5: PRESCRIBING BASELINE ----
# What R/26 already captures via RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm
# ==============================================================================

message("--- Section 5: PRESCRIBING baseline ---")

# Initialise empty baseline sets (used in Section 6 incremental calcs).
rx_patients   <- character(0)
rx_pairs      <- tibble(ID = character(0), treatment_date = as.Date(character(0)))
rx_first_date <- tibble(ID = character(0), rx_min_date = as.Date(character(0)))

pr_tbl <- get_pcornet_table("PRESCRIBING")

if (is.null(pr_tbl)) {
  message("  PRESCRIBING table NOT found in DuckDB — baseline set to empty. Skipping.\n")
} else if (!("RXNORM_CUI" %in% colnames(pr_tbl))) {
  message("  PRESCRIBING table found but RXNORM_CUI column is ABSENT — this extract lacks it.")
  message("  Baseline set to empty. (Unexpected: R/26 assumes PRESCRIBING has RXNORM_CUI.)\n")
} else {
  pr <- pr_tbl %>%
    filter(RXNORM_CUI %in% CHEMO_RXNORM) %>%
    mutate(treatment_date = coalesce(RX_ORDER_DATE, RX_START_DATE)) %>%
    filter(!is.na(treatment_date)) %>%
    select(ID, treatment_date, RXNORM_CUI) %>%
    collect()

  # Parse dates
  pr <- pr %>%
    mutate(treatment_date = parse_pcornet_date(treatment_date))

  pr_all <- pr %>% filter(!is.na(treatment_date))
  pr_coh <- pr_all %>% filter_to_cohort()

  # All-patient metrics
  n_rx_all_rows     <- nrow(pr_all)
  n_rx_all_patients <- n_distinct(pr_all$ID)
  n_rx_all_pairs    <- nrow(pr_all %>% distinct(ID, treatment_date))
  n_rx_all_codes    <- n_distinct(pr_all$RXNORM_CUI)

  # Cohort metrics
  n_rx_coh_rows     <- nrow(pr_coh)
  n_rx_coh_patients <- n_distinct(pr_coh$ID)
  n_rx_coh_pairs    <- nrow(pr_coh %>% distinct(ID, treatment_date))
  n_rx_coh_codes    <- n_distinct(pr_coh$RXNORM_CUI)

  message(glue("  All-patient: {format(n_rx_all_rows, big.mark=',')} rows, {format(n_rx_all_patients, big.mark=',')} patients, {format(n_rx_all_pairs, big.mark=',')} (ID,date) pairs, {n_rx_all_codes} distinct codes"))
  message(glue("  Cohort:      {format(n_rx_coh_rows, big.mark=',')} rows, {format(n_rx_coh_patients, big.mark=',')} patients, {format(n_rx_coh_pairs, big.mark=',')} (ID,date) pairs\n"))

  # Build reference sets for Section 6 increment calculations (cohort-scoped).
  rx_patients <- pr_coh %>% distinct(ID) %>% pull(ID)
  rx_pairs    <- pr_coh %>% distinct(ID, treatment_date)
  rx_first_date <- pr_coh %>%
    group_by(ID) %>%
    summarise(rx_min_date = min(treatment_date, na.rm = TRUE), .groups = "drop")

  # Store all-patient objects for CSV row
  pr_row_all <- list(
    scope = "all", source = "PRESCRIBING_baseline",
    n_rows = n_rx_all_rows, n_patients = suppress_small(n_rx_all_patients),
    n_id_date_pairs = n_rx_all_pairs, n_distinct_codes = n_rx_all_codes,
    note = "R/26 already captures these via RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm"
  )
  pr_row_coh <- list(
    scope = "cohort", source = "PRESCRIBING_baseline",
    n_rows = n_rx_coh_rows, n_patients = suppress_small(n_rx_coh_patients),
    n_id_date_pairs = n_rx_coh_pairs, n_distinct_codes = n_rx_coh_codes,
    note = "R/26 already captures these via RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm"
  )
}


# ==============================================================================
# SECTION 6: MED_ADMIN INCREMENTAL CONTRIBUTION ----
# MEDADMIN_TYPE=='RX' rows carry RxNorm CUIs in MEDADMIN_CODE (directly comparable
# to TREATMENT_CODES$chemo_rxnorm). The RXNORM_CUI guard in R/26 drops these.
# ==============================================================================

message("--- Section 6: MED_ADMIN incremental contribution ---")

# Initialise increment counters (used in Section 8 HEADLINE).
n_new_ma_patients <- 0L
n_new_ma_dates    <- 0L
n_earlier_dates   <- 0L

ma_tbl <- get_pcornet_table("MED_ADMIN")

if (is.null(ma_tbl)) {
  message("  MED_ADMIN table NOT found in DuckDB — SKIP.\n")
} else {
  # Guard required columns individually; log and skip if any missing.
  ma_cols <- colnames(ma_tbl)
  required_ma_cols <- c("MEDADMIN_TYPE", "MEDADMIN_CODE", "MEDADMIN_START_DATE")
  missing_ma_cols  <- required_ma_cols[!required_ma_cols %in% ma_cols]

  if (length(missing_ma_cols) > 0) {
    message(glue("  MED_ADMIN missing required columns: {paste(missing_ma_cols, collapse=', ')} — SKIP.\n"))
  } else {

    # ---- 6a: RX-coded chemo administrations (MEDADMIN_TYPE == 'RX') -----------
    message("  6a: MED_ADMIN MEDADMIN_TYPE=='RX' chemo match ...")
    ma_rx <- ma_tbl %>%
      filter(MEDADMIN_TYPE == "RX", MEDADMIN_CODE %in% CHEMO_RXNORM,
             !is.na(MEDADMIN_START_DATE)) %>%
      select(ID, MEDADMIN_CODE, MEDADMIN_START_DATE) %>%
      collect() %>%
      mutate(treatment_date = parse_pcornet_date(MEDADMIN_START_DATE)) %>%
      filter(!is.na(treatment_date))

    ma_rx_all <- ma_rx
    ma_rx_coh <- ma_rx %>% filter_to_cohort()

    n_ma_rx_all_rows    <- nrow(ma_rx_all)
    n_ma_rx_all_pts     <- n_distinct(ma_rx_all$ID)
    n_ma_rx_all_pairs   <- nrow(ma_rx_all %>% distinct(ID, treatment_date))
    n_ma_rx_all_codes   <- n_distinct(ma_rx_all$MEDADMIN_CODE)

    n_ma_rx_coh_rows    <- nrow(ma_rx_coh)
    n_ma_rx_coh_pts     <- n_distinct(ma_rx_coh$ID)
    n_ma_rx_coh_pairs   <- nrow(ma_rx_coh %>% distinct(ID, treatment_date))
    n_ma_rx_coh_codes   <- n_distinct(ma_rx_coh$MEDADMIN_CODE)

    message(glue("  All-patient: {format(n_ma_rx_all_rows, big.mark=',')} rows, {format(n_ma_rx_all_pts, big.mark=',')} patients, {format(n_ma_rx_all_pairs, big.mark=',')} (ID,date) pairs, {n_ma_rx_all_codes} distinct codes"))
    message(glue("  Cohort:      {format(n_ma_rx_coh_rows, big.mark=',')} rows, {format(n_ma_rx_coh_pts, big.mark=',')} patients, {format(n_ma_rx_coh_pairs, big.mark=',')} (ID,date) pairs"))

    # ---- 6b: Increment beyond PRESCRIBING (cohort-scoped) --------------------
    message("  6b: MED_ADMIN increment BEYOND PRESCRIBING baseline (cohort-scoped) ...")

    ma_rx_coh_pairs <- ma_rx_coh %>% distinct(ID, treatment_date)

    # New patients: in MED_ADMIN chemo but NOT in PRESCRIBING baseline.
    new_patients_vec <- setdiff(
      ma_rx_coh %>% distinct(ID) %>% pull(ID),
      rx_patients
    )
    n_new_ma_patients <- length(new_patients_vec)
    message(glue("  New patients beyond PRESCRIBING: {n_new_ma_patients}"))

    # New (ID, date) pairs: MED_ADMIN pairs not in PRESCRIBING pairs.
    new_pairs_df <- ma_rx_coh_pairs %>%
      anti_join(rx_pairs, by = c("ID", "treatment_date"))
    n_new_ma_dates <- nrow(new_pairs_df)
    message(glue("  New (ID, date) pairs beyond PRESCRIBING: {format(n_new_ma_dates, big.mark=',')}"))

    # Earlier first-chemo-date shifts: patients whose earliest MED_ADMIN chemo
    # date is strictly earlier than their PRESCRIBING first-chemo date.
    ma_first_date <- ma_rx_coh %>%
      group_by(ID) %>%
      summarise(ma_min_date = min(treatment_date, na.rm = TRUE), .groups = "drop")

    # Patients present in BOTH sources (can have a "shift").
    both_sources <- inner_join(ma_first_date, rx_first_date, by = "ID")
    n_earlier_dates <- sum(both_sources$ma_min_date < both_sources$rx_min_date, na.rm = TRUE)

    # Patients ONLY in MED_ADMIN chemo (no PRESCRIBING row) count as new-patient adds.
    n_ma_only_patients <- length(setdiff(ma_first_date$ID, rx_first_date$ID))
    message(glue("  Patients with earlier first-chemo date in MED_ADMIN vs PRESCRIBING: {n_earlier_dates}"))
    message(glue("  Patients with chemo in MED_ADMIN only (no PRESCRIBING baseline): {n_ma_only_patients}"))

    # ---- 6c: MEDADMIN_TYPE=='ND' volume (NDC-coded; needs crosswalk) ---------
    message("  6c: MED_ADMIN MEDADMIN_TYPE=='ND' volume (NDC-coded, needs NDC->RxNorm crosswalk) ...")
    ma_nd <- ma_tbl %>%
      filter(MEDADMIN_TYPE == "ND") %>%
      select(ID, MEDADMIN_CODE, MEDADMIN_START_DATE) %>%
      collect()

    ma_nd_all <- ma_nd
    ma_nd_coh <- ma_nd %>% filter_to_cohort()

    n_ma_nd_all_rows  <- nrow(ma_nd_all)
    n_ma_nd_all_pts   <- n_distinct(ma_nd_all$ID)
    n_ma_nd_coh_rows  <- nrow(ma_nd_coh)
    n_ma_nd_coh_pts   <- n_distinct(ma_nd_coh$ID)

    message(glue("  All-patient: {format(n_ma_nd_all_rows, big.mark=',')} rows, {format(n_ma_nd_all_pts, big.mark=',')} patients"))
    message(glue("  Cohort:      {format(n_ma_nd_coh_rows, big.mark=',')} rows, {format(n_ma_nd_coh_pts, big.mark=',')} patients"))
    message("  NOTE: MEDADMIN_TYPE=='ND' administrations are NDC-coded — NOT matched against")
    message("        TREATMENT_CODES$chemo_rxnorm (would require an NDC->RxNorm crosswalk).\n")

    # Store CSV row objects
    ma_rx_row_all <- list(
      scope = "all", source = "MED_ADMIN_RX_increment",
      n_rows = n_ma_rx_all_rows, n_patients = suppress_small(n_ma_rx_all_pts),
      n_id_date_pairs = n_ma_rx_all_pairs, n_distinct_codes = n_ma_rx_all_codes,
      note = "MEDADMIN_TYPE=='RX': MEDADMIN_CODE holds RxNorm CUI; matched against TREATMENT_CODES$chemo_rxnorm"
    )
    ma_rx_row_coh <- list(
      scope = "cohort", source = "MED_ADMIN_RX_increment",
      n_rows = n_ma_rx_coh_rows, n_patients = suppress_small(n_ma_rx_coh_pts),
      n_id_date_pairs = n_ma_rx_coh_pairs, n_distinct_codes = n_ma_rx_coh_codes,
      note = "MEDADMIN_TYPE=='RX': MEDADMIN_CODE holds RxNorm CUI; matched against TREATMENT_CODES$chemo_rxnorm"
    )
    ma_nd_row_all <- list(
      scope = "all", source = "MED_ADMIN_ND_volume",
      n_rows = n_ma_nd_all_rows, n_patients = suppress_small(n_ma_nd_all_pts),
      n_id_date_pairs = NA_integer_, n_distinct_codes = NA_integer_,
      note = "MEDADMIN_TYPE=='ND': NDC-coded — NOT chemo-matched; needs NDC->RxNorm crosswalk"
    )
    ma_nd_row_coh <- list(
      scope = "cohort", source = "MED_ADMIN_ND_volume",
      n_rows = n_ma_nd_coh_rows, n_patients = suppress_small(n_ma_nd_coh_pts),
      n_id_date_pairs = NA_integer_, n_distinct_codes = NA_integer_,
      note = "MEDADMIN_TYPE=='ND': NDC-coded — NOT chemo-matched; needs NDC->RxNorm crosswalk"
    )
  }
}


# ==============================================================================
# SECTION 7: DISPENSING FOOTPRINT ----
# NDC-only extract: no RXNORM_CUI, no in-repo NDC->RxNorm crosswalk.
# Report volume / patient / date footprint ONLY. Explicitly flag no chemo match.
# ==============================================================================

message("--- Section 7: DISPENSING footprint (NDC only — no chemo match) ---")
message("  DISPENSING chemo-specific matching NOT possible without an NDC->RxNorm")
message("  crosswalk (this extract has NDC only, no RXNORM_CUI, no crosswalk in-repo).")

dp_tbl <- get_pcornet_table("DISPENSING")

if (is.null(dp_tbl)) {
  message("  DISPENSING table NOT found in DuckDB — SKIP.\n")
} else {
  dp_all <- dp_tbl %>%
    select(ID, DISPENSE_DATE) %>%
    collect()

  dp_coh <- dp_all %>% filter_to_cohort()

  n_dp_all_rows  <- nrow(dp_all)
  n_dp_all_pts   <- n_distinct(dp_all$ID)
  n_dp_all_dates <- n_distinct(dp_all$DISPENSE_DATE)

  n_dp_coh_rows  <- nrow(dp_coh)
  n_dp_coh_pts   <- n_distinct(dp_coh$ID)
  n_dp_coh_dates <- n_distinct(dp_coh$DISPENSE_DATE)

  message(glue("  All-patient: {format(n_dp_all_rows, big.mark=',')} rows, {format(n_dp_all_pts, big.mark=',')} patients, {n_dp_all_dates} distinct DISPENSE_DATEs"))
  message(glue("  Cohort:      {format(n_dp_coh_rows, big.mark=',')} rows, {format(n_dp_coh_pts, big.mark=',')} patients, {n_dp_coh_dates} distinct DISPENSE_DATEs\n"))

  dp_row_all <- list(
    scope = "all", source = "DISPENSING_footprint",
    n_rows = n_dp_all_rows, n_patients = suppress_small(n_dp_all_pts),
    n_id_date_pairs = n_dp_all_dates, n_distinct_codes = NA_integer_,
    note = "NDC-only; no RXNORM_CUI; no crosswalk in-repo — chemo match NOT possible"
  )
  dp_row_coh <- list(
    scope = "cohort", source = "DISPENSING_footprint",
    n_rows = n_dp_coh_rows, n_patients = suppress_small(n_dp_coh_pts),
    n_id_date_pairs = n_dp_coh_dates, n_distinct_codes = NA_integer_,
    note = "NDC-only; no RXNORM_CUI; no crosswalk in-repo — chemo match NOT possible"
  )
}


# ==============================================================================
# SECTION 8: CONSOLE HEADLINE + WRITE DIAGNOSTIC CSV ----
# ==============================================================================

message("--- Section 8: HEADLINE + CSV output ---")

# HEADLINE: key actionable numbers (HIPAA-suppressed if 1-10).
headline_new_patients <- suppress_small(n_new_ma_patients)
headline_new_dates    <- n_new_ma_dates   # (ID,date) pairs — not a patient count
headline_earlier      <- suppress_small(n_earlier_dates)

message(glue(
  "HEADLINE: MED_ADMIN would add {ifelse(is.na(headline_new_patients), '<11', format(headline_new_patients, big.mark=','))} patients / ",
  "{format(headline_new_dates, big.mark=',')} chemo dates beyond PRESCRIBING; ",
  "{ifelse(is.na(headline_earlier), '<11', format(headline_earlier, big.mark=','))} patients would get an earlier first-chemo date."
))

# Build the output tibble. Collect available rows; fall back to empty if a
# table was absent (objects may not be defined if guard skipped them).
rows_list <- list()

if (exists("pr_row_all"))      rows_list <- c(rows_list, list(pr_row_all))
if (exists("pr_row_coh"))      rows_list <- c(rows_list, list(pr_row_coh))
if (exists("ma_rx_row_all"))   rows_list <- c(rows_list, list(ma_rx_row_all))
if (exists("ma_rx_row_coh"))   rows_list <- c(rows_list, list(ma_rx_row_coh))
if (exists("ma_nd_row_all"))   rows_list <- c(rows_list, list(ma_nd_row_all))
if (exists("ma_nd_row_coh"))   rows_list <- c(rows_list, list(ma_nd_row_coh))
if (exists("dp_row_all"))      rows_list <- c(rows_list, list(dp_row_all))
if (exists("dp_row_coh"))      rows_list <- c(rows_list, list(dp_row_coh))

if (length(rows_list) == 0L) {
  message("  WARNING: No source data collected — writing empty diagnostic CSV.\n")
  result_df <- tibble::tibble(
    scope = character(0), source = character(0),
    n_rows = integer(0), n_patients = integer(0),
    n_id_date_pairs = integer(0), n_distinct_codes = integer(0),
    note = character(0)
  )
} else {
  result_df <- dplyr::bind_rows(lapply(rows_list, tibble::as_tibble))
}

write.csv(result_df, OUTPUT_CSV, row.names = FALSE, na = "")
message(glue("Wrote diagnostic CSV: {OUTPUT_CSV}"))

close_pcornet_con()

message("\nDone. (quick-260714-end -- MED_ADMIN/DISPENSING chemo-gap sizing diagnostic)")
