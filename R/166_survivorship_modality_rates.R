# ==============================================================================
# 166_survivorship_modality_rates.R -- Survivorship Modality Rate Tables
# ==============================================================================
# INTERNAL — contains patient IDs. Not for release outside the secure enclave.
#
# Purpose:  Compute per-patient modality rates (n_dates_post_primary /
#           person_years) for every surveillance modality in R/147's output.
#           Also builds dated post-anchor events (option-a function chain) for
#           the follow-up-year interval breakdown (B_rates_by_fu_year) and
#           saves them for reuse in Plan 03 (echo-timing block).
#
# Inputs:
#   surveillance_modality_patient_<date>.rds   -- from R/147 (build_patient_modality)
#   DuckDB: PROCEDURES, LAB_RESULT_CM           -- for option-a event rebuild
#
# Outputs (CONFIG$cache$outputs_dir):
#   survivorship_modality_rates_parts_<date>.rds   -- named list (INTERNAL)
#   survivorship_dated_events_<date>.rds            -- ID x modality x event_date (INTERNAL)
#
# Depends:   R/00_config.R (auto-sources R/utils/*.R including utils_surveillance_rates.R)
#            R/147_surveillance_modality_frequency.R (must have been run first)
#
# Usage (HiPerGator):
#   module load R/4.4.2
#   Rscript R/166_survivorship_modality_rates.R
#
# Requirements: SRATE-02
# Decisions:    166-CONTEXT.md D-01..D-14; 166-AUDIT.md
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(glue)
})

source(here::here("R/00_config.R"))

# utils_surveillance_rates.R is auto-sourced by R/00_config.R if it reads
# all utils modules. Guard in case it is not:
if (!exists("compute_modality_rates")) {
  source(here::here("R/utils/utils_surveillance_rates.R"))
}
# utils_surveillance.R provides the option-a function chain
if (!exists("load_surveillance_codeset")) {
  source(here::here("R/utils/utils_surveillance.R"))
}
if (!exists("get_hl_any_dx_ids")) {
  source(here::here("R/utils/utils_treatment.R"))
}
if (!exists("get_last_activity")) {
  source(here::here("R/utils/utils_activity.R"))
}
if (!exists("resolve_death_date")) {
  source(here::here("R/utils/utils_death.R"))
}

run_date <- format(Sys.Date(), "%Y%m%d")
out_dir  <- CONFIG$cache$outputs_dir

message(glue("=== Survivorship modality rates (run {run_date}) ==="))

# ==============================================================================
# SECTION 1: LOAD PATIENT-MODALITY TABLE (from R/147) ----
# ==============================================================================

rds_files <- list.files(
  out_dir,
  pattern    = "^surveillance_modality_patient_.*\\.rds$",
  full.names = TRUE
)
if (length(rds_files) == 0) {
  stop("No surveillance_modality_patient_*.rds found in ", out_dir, ". ",
       "Run R/147_surveillance_modality_frequency.R first.")
}
latest_rds <- rds_files[order(file.info(rds_files)$mtime, decreasing = TRUE)[1]]
message("Loading: ", basename(latest_rds))
patient_modality <- readRDS(latest_rds)

message(glue("  patient_modality: {nrow(patient_modality)} rows, ",
             "{n_distinct(patient_modality$ID)} patients, ",
             "{n_distinct(patient_modality$modality)} modalities"))

# ==============================================================================
# SECTION 2: FOLLOW-UP TABLE ----
# ==============================================================================

followup <- dplyr::distinct(patient_modality,
                             .data$ID, .data$hl_anchor_date,
                             .data$follow_end, .data$person_years)
stopifnot(
  "follow_end must be present in patient_modality" =
    "follow_end" %in% names(patient_modality),
  "followup must have one row per ID" =
    !anyDuplicated(followup$ID)
)
message(glue("  followup: {nrow(followup)} patients"))

# ==============================================================================
# SECTION 3: LONG AND WIDE RATE TABLES (A) ----
# ==============================================================================

n_dates_col <- "n_dates_post_primary"

long_rates <- compute_modality_rates(patient_modality,
                                     n_dates_col = n_dates_col)
stopifnot(
  "long_rates must have unique ID x modality rows" =
    !anyDuplicated(long_rates[, c("ID", "modality")])
)
message(glue("  long_rates: {nrow(long_rates)} rows"))

wide_rates <- rates_wide(long_rates)
stopifnot(
  "wide_rates must have unique IDs" = !anyDuplicated(wide_rates$ID)
)
message(glue("  wide_rates: {nrow(wide_rates)} patients x ",
             "{ncol(wide_rates) - 1} modality columns"))

A_rates_summary <- rates_summary(long_rates)
message(glue("  A_rates_summary: {nrow(A_rates_summary)} modalities"))

# ==============================================================================
# SECTION 4: DATED POST-ANCHOR EVENTS (option-a function chain) ----
# ==============================================================================
# Reproduces events_win from R/147 via the same pure-function chain, then
# applies the reconciliation filter. Requires DuckDB to be open.

message("Building dated post-anchor events (option-a function chain) ...")

ANCHOR_DAY_IS_POST <- FALSE   # matches R/147 line 54 (D-25)
EXTRACT_CUTOFF     <- as.Date(EXTRACT_DATE)
CODESET_PATH       <- file.path("data", "reference", "surveillance_codeset.xlsx")
EXCLUDED_CDM_TABLES <- c("DIAGNOSIS")   # 163 D-01

# Open DuckDB connection
if (!exists("pcornet_con", envir = .GlobalEnv)) open_pcornet_con()

# Load codeset (same as R/147)
codeset_full <- load_surveillance_codeset()
codeset      <- codeset_full |> dplyr::filter(!.data$cdm_table %in% EXCLUDED_CDM_TABLES)
analytes     <- load_lab_analytes(codeset = codeset)

# Denominator and follow-up (must match R/147's denominator)
denom_all     <- get_hl_any_dx_ids()
confirmed_ids <- get_hl_patient_ids()
denominator   <- denom_all   # full any-dx denominator

activity <- get_last_activity(pcornet_con, denominator, EXTRACT_CUTOFF)

death_raw <- dplyr::tbl(pcornet_con, "DEATH") |>
  dplyr::semi_join(
    dplyr::tibble(ID = denom_all$ID),
    by = "ID", copy = TRUE
  ) |>
  dplyr::select(dplyr::any_of(c("ID", "DEATH_DATE", "DEATH_SOURCE"))) |>
  dplyr::collect()
death_rows <- dplyr::tibble(
  ID           = death_raw$ID,
  DEATH_DATE   = parse_pcornet_date(death_raw$DEATH_DATE),
  DEATH_SOURCE = if ("DEATH_SOURCE" %in% names(death_raw)) death_raw$DEATH_SOURCE
                 else NA_character_
)
death_resolved <- resolve_death_date(death_rows, activity, grace_days = 30L)
followup_full  <- compute_followup(denominator, activity, death_resolved, EXTRACT_CUTOFF)

# pick_date: coalesce date columns in priority order, parsing each (mirrors R/147)
pick_date_166 <- function(df, cols) {
  out <- rep(as.Date(NA), nrow(df))
  for (cl in intersect(cols, names(df)))
    out <- dplyr::coalesce(out, parse_pcornet_date(df[[cl]]))
  out
}

# Pull raw events for the function chain
hl_ids_tbl <- dplyr::copy_to(pcornet_con,
                              dplyr::tibble(ID = denom_all$ID),
                              name = "hl_ids_166", overwrite = TRUE)

proc_raw <- dplyr::tbl(pcornet_con, "PROCEDURES") |>
  dplyr::semi_join(hl_ids_tbl, by = "ID") |>
  dplyr::select(dplyr::any_of(c("ID", "PX", "PX_TYPE", "PX_DATE", "ADMIT_DATE"))) |>
  dplyr::collect()
proc_events_in <- dplyr::tibble(
  ID           = proc_raw$ID,
  code_raw     = proc_raw$PX,
  type_val     = proc_raw$PX_TYPE,
  event_date   = pick_date_166(proc_raw, c("PX_DATE", "ADMIT_DATE")),
  source_table = "PROCEDURES",
  code_data    = proc_raw$PX
)

lab_raw <- dplyr::tbl(pcornet_con, "LAB_RESULT_CM") |>
  dplyr::semi_join(hl_ids_tbl, by = "ID") |>
  dplyr::select(dplyr::any_of(c("ID", "LAB_LOINC", "RESULT_DATE",
                                 "SPECIMEN_DATE", "LAB_ORDER_DATE"))) |>
  dplyr::collect()
lab_events_in <- dplyr::tibble(
  ID           = lab_raw$ID,
  code_raw     = lab_raw$LAB_LOINC,
  type_val     = "",
  event_date   = pick_date_166(lab_raw, c("RESULT_DATE", "SPECIMEN_DATE", "LAB_ORDER_DATE")),
  source_table = "LAB_RESULT_CM",
  code_data    = lab_raw$LAB_LOINC
)

# Step-by-step function chain (mirrors R/147 SECTION 7)
matched_coded <- match_coded_events(
  dplyr::bind_rows(proc_events_in, lab_events_in) |>
    dplyr::filter(!is.na(.data$event_date)),
  codeset
)
comp     <- build_component_events(
  lab_events_in |> dplyr::select("ID", "code_raw", "event_date"),
  codeset
)
an_rules <- build_analyte_events(
  map_analyte_hits(lab_events_in, analytes),
  codeset
)
matched_all <- dplyr::bind_rows(matched_coded, comp$events, an_rules$events)

events_win <- classify_event_window(matched_all, followup_full,
                                    anchor_day_is_post = ANCHOR_DAY_IS_POST)

# Apply reconciliation filter (option-a: 166-AUDIT.md §5)
events_dated <- build_dated_post_events(events_win, followup_full)
message(glue("  events_dated: {nrow(events_dated)} rows ",
             "({n_distinct(events_dated$ID)} patients, ",
             "{n_distinct(events_dated$modality)} modalities)"))

# Save for Plan 03
saveRDS(events_dated,
        file.path(out_dir,
                  glue("survivorship_dated_events_{run_date}.rds")))
message(glue("  Saved: survivorship_dated_events_{run_date}.rds"))

# ==============================================================================
# SECTION 5: FOLLOW-UP-YEAR INTERVAL BREAKDOWN (B) ----
# ==============================================================================

B_rates_by_fu_year <- split_followup_intervals(followup, events_dated)
message(glue("  B_rates_by_fu_year: {nrow(B_rates_by_fu_year)} rows"))

# ==============================================================================
# SECTION 6: INTERVAL RECONCILIATION QC ----
# ==============================================================================
# Per ID x modality: compare summed interval py to person_years (tol 1e-6)
# and summed dates to n_dates_post. Not a hard stop — logged for Plan 04 QC.

recon_py <- B_rates_by_fu_year |>
  dplyr::group_by(.data$ID, .data$modality) |>
  dplyr::summarise(
    sum_interval_py    = sum(.data$person_years_in_interval, na.rm = TRUE),
    sum_interval_dates = sum(.data$dates_in_interval, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::left_join(
    long_rates |> dplyr::select("ID", "modality", "person_years", "n_dates_post"),
    by = c("ID", "modality")
  ) |>
  dplyr::mutate(
    py_ok    = abs(.data$sum_interval_py - .data$person_years) < 1e-6,
    dates_ok = .data$sum_interval_dates == .data$n_dates_post
  )

n_checked  <- nrow(recon_py)
n_py_fail  <- sum(!recon_py$py_ok,    na.rm = TRUE)
n_dt_fail  <- sum(!recon_py$dates_ok, na.rm = TRUE)
message(glue("  Interval reconciliation: {n_checked} ID x modality rows checked; ",
             "{n_py_fail} py failures, {n_dt_fail} dates failures."))

qc_interval_recon_summary <- dplyr::tibble(
  n_checked        = n_checked,
  n_py_fail        = n_py_fail,
  n_dates_fail     = n_dt_fail,
  recon_py_pass    = n_py_fail == 0L,
  recon_dates_pass = n_dt_fail == 0L
)

# Keep first 50 failing rows for inspection (INTERNAL)
qc_interval_fail <- recon_py |>
  dplyr::filter(!.data$py_ok | !.data$dates_ok) |>
  dplyr::slice_head(n = 50)

# ==============================================================================
# SECTION 7: ZERO-PY COUNT ----
# ==============================================================================

n_zero_py_patients <- sum(
  followup$person_years == 0 | is.na(followup$person_years)
)
message(glue("  Patients with zero or NA person_years: {n_zero_py_patients}"))

# ==============================================================================
# SECTION 8: SAVE NAMED LIST ----
# ==============================================================================

out_list <- list(
  long_rates                  = long_rates,
  wide_rates                  = wide_rates,
  A_rates_summary             = A_rates_summary,
  B_rates_by_fu_year          = B_rates_by_fu_year,
  qc_interval_recon_summary   = qc_interval_recon_summary,
  qc_interval_fail            = qc_interval_fail,
  n_zero_py_patients          = n_zero_py_patients,
  n_dates_col                 = n_dates_col,
  run_date                    = run_date
)

out_path <- file.path(out_dir,
                      glue("survivorship_modality_rates_parts_{run_date}.rds"))
saveRDS(out_list, out_path)
message(glue("  Saved: survivorship_modality_rates_parts_{run_date}.rds"))
message(glue("=== Done (run {run_date}) ==="))
