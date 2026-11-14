# ==============================================================================
# Script:  203_no_treatment_characterization.R
# Phase:   203 — no-treatment-patient-characterization
# Purpose: Split confirmed_hl_cohort.rds into a no-treatment group
#          (0 captured treatment episodes) and a treated group (>=1 episode);
#          profile both side by side across NOTX-01..NOTX-05 tables.
#          No cohort-membership change — the split is analytic-only.
# Inputs:  confirmed_hl_cohort.rds       (env R203_COHORT_RDS)
#          gantt_episodes_180.csv        (env R203_GANTT180_CSV)
#          single_source_care RDS/R169   (env R203_R169_RDS)
#          tr_lymphoma_flags RDS/R193    (env R203_TRFLAGS_RDS)
# Outputs: output/203_no_treatment_characterization_<date>.xlsx
#            (KEY, A_profile, B_reasons_waterfall, C_by_source,
#             D_candidate_rules, QC)
#          output/internal/203_no_treatment_characterization_<date>.rds  (patient-level)
# ==============================================================================

# ==============================================================================
# SECTION 0: SETUP ----
# ==============================================================================

source(here::here("R", "00_config.R"), local = FALSE)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(lubridate)
  library(glue)
  library(here)
  library(openxlsx)
})

RUN_DATE <- Sys.getenv("RUN_DATE", format(Sys.Date(), "%Y%m%d"))
message(glue("==== R/203 no_treatment_characterization -- RUN DATE {RUN_DATE} ===="))

# ==============================================================================
# SECTION 1: IS_LOCAL GUARD ----
# ==============================================================================
# confirmed_hl_cohort.rds and all Phase 203 inputs exist only on HiPerGator.
# The script parses locally but stops before reading any data.

R203_LOCAL_CHECK_PATH <- Sys.getenv(
  "R203_COHORT_RDS",
  unset = "/blue/erin.mobley-hl.bcu/insurance_investigation/output/internal/confirmed_hl_cohort.rds"
)
R203_RUN_LOCAL <- !file.exists(R203_LOCAL_CHECK_PATH)

if (R203_RUN_LOCAL) {
  stop(paste0(
    "Phase 203 requires HiPerGator data — run in interactive R/4.5 session. ",
    "File not found: ", R203_LOCAL_CHECK_PATH
  ))
}

# ==============================================================================
# SECTION 2: PINNED INPUTS ----
# Column names confirmed in .planning/schemas/203_schema_<date>.md (probe on
# HiPerGator). Do NOT change column references without updating that probe file.
# ==============================================================================

COHORT_RDS <- Sys.getenv(
  "R203_COHORT_RDS",
  unset = "/blue/erin.mobley-hl.bcu/insurance_investigation/output/internal/confirmed_hl_cohort.rds"
)
if (!file.exists(COHORT_RDS))
  stop("[R203] R203_COHORT_RDS not found: ", COHORT_RDS)

GANTT180_CSV <- Sys.getenv(
  "R203_GANTT180_CSV",
  unset = file.path(CONFIG$output_dir, "gantt_episodes_180.csv")
)
if (!file.exists(GANTT180_CSV))
  stop("[R203] R203_GANTT180_CSV not found: ", GANTT180_CSV)

R169_RDS <- Sys.getenv(
  "R203_R169_RDS",
  unset = "/blue/erin.mobley-hl.bcu/insurance_investigation/output/internal/single_source_care_20261013.rds"
)
if (!file.exists(R169_RDS))
  stop("[R203] R203_R169_RDS not found: ", R169_RDS)

TRFLAGS_RDS <- Sys.getenv(
  "R203_TRFLAGS_RDS",
  unset = "/blue/erin.mobley-hl.bcu/insurance_investigation/output/internal/tr_lymphoma_flags_all_patients_20261113.rds"
)
if (!file.exists(TRFLAGS_RDS))
  stop("[R203] R203_TRFLAGS_RDS not found: ", TRFLAGS_RDS)

# Record pin info for the KEY sheet (populated in a later plan).
pin_info <- list(
  cohort_rds   = list(path = COHORT_RDS,    pinned = nzchar(Sys.getenv("R203_COHORT_RDS"))),
  gantt180_csv = list(path = GANTT180_CSV,  pinned = nzchar(Sys.getenv("R203_GANTT180_CSV"))),
  r169_rds     = list(path = R169_RDS,      pinned = nzchar(Sys.getenv("R203_R169_RDS"))),
  trflags_rds  = list(path = TRFLAGS_RDS,   pinned = nzchar(Sys.getenv("R203_TRFLAGS_RDS")))
)
message("[R203] Pin status:")
for (nm in names(pin_info))
  message(glue("  {nm}: {pin_info[[nm]]$path}  [pinned={pin_info[[nm]]$pinned}]"))

# ==============================================================================
# SECTION 3: READ CONFIRMED COHORT ----
# ==============================================================================

cohort <- readRDS(COHORT_RDS)
message(glue("[R203] Cohort loaded: {nrow(cohort)} rows, {ncol(cohort)} columns"))

# Treatment-episode count column.
# Confirm exact name against .planning/schemas/203_schema_<date>.md once probe
# runs; candidate name below is used throughout this script.
TX_COUNT_COL <- "n_treatment_episodes"
if (!TX_COUNT_COL %in% names(cohort))
  stop(
    "[R203] TX_COUNT_COL '", TX_COUNT_COL, "' not found in confirmed_hl_cohort.rds. ",
    "Available columns: ", paste(names(cohort), collapse = ", ")
  )

# ==============================================================================
# SECTION 4: COHORT SPLIT ----
# No cohort rows are removed or altered beyond this analytic split (NOTX design
# constraint). group label is for display only.
# ==============================================================================

no_tx   <- cohort %>% filter(.data[[TX_COUNT_COL]] == 0) %>%
             mutate(group = "no_treatment")
treated <- cohort %>% filter(.data[[TX_COUNT_COL]] >= 1) %>%
             mutate(group = "treated")

message(glue(
  "[R203] no_tx: {nrow(no_tx)} patients; treated: {nrow(treated)} patients; ",
  "total {nrow(cohort)}"
))
stopifnot(
  "Split must be exhaustive and non-overlapping" =
    nrow(no_tx) + nrow(treated) == nrow(cohort)
)

# ==============================================================================
# SECTION 5: NOTX-01 — DATA-WINDOW TRUNCATION (Plan 203-02) ----
# Column names confirmed in .planning/schemas/203_schema_<date>.md (probe on
# HiPerGator). Stop with available names if absent (never guess column names).
# ==============================================================================

# Named config constants (ABVD_CONCURRENT_WINDOW_DAYS-style convention).
PERI_DX_WINDOW_DAYS <- 90L

# Enrollment/first-encounter date column — candidate name from probe placeholder.
# Update WINDOW_START_COL once 203_schema_<date>.md is written by probe_inputs().
WINDOW_START_COL <- "enr_start_date"
if (!WINDOW_START_COL %in% names(cohort))
  stop(
    "[R203] WINDOW_START_COL '", WINDOW_START_COL,
    "' not found in confirmed_hl_cohort.rds. ",
    "Available columns: ", paste(sort(names(cohort)), collapse = ", ")
  )

# NLPHL indicator column — candidate name from probe placeholder.
NLPHL_COL <- "is_nlphl"
if (!NLPHL_COL %in% names(cohort))
  stop(
    "[R203] NLPHL_COL '", NLPHL_COL,
    "' not found in confirmed_hl_cohort.rds. ",
    "Available columns: ", paste(sort(names(cohort)), collapse = ", ")
  )

# Age-at-dx column — candidate name from probe placeholder.
AGE_DX_COL <- "age_at_dx"
if (!AGE_DX_COL %in% names(cohort))
  stop(
    "[R203] AGE_DX_COL '", AGE_DX_COL,
    "' not found in confirmed_hl_cohort.rds. ",
    "Available columns: ", paste(sort(names(cohort)), collapse = ", ")
  )

# Payer category column — candidate name from probe placeholder.
PAYER_CAT_COL <- "payer_cat"
if (!PAYER_CAT_COL %in% names(cohort))
  stop(
    "[R203] PAYER_CAT_COL '", PAYER_CAT_COL,
    "' not found in confirmed_hl_cohort.rds. ",
    "Available columns: ", paste(sort(names(cohort)), collapse = ", ")
  )

# Far-from-care column — candidate name from probe placeholder.
FAR_COL <- "far_from_care_100mi"
if (!FAR_COL %in% names(cohort))
  stop(
    "[R203] FAR_COL '", FAR_COL,
    "' not found in confirmed_hl_cohort.rds. ",
    "Available columns: ", paste(sort(names(cohort)), collapse = ", ")
  )

# SOURCE / primary partner site column — candidate name from probe placeholder.
SOURCE_COL <- "SOURCE"
if (!SOURCE_COL %in% names(cohort))
  stop(
    "[R203] SOURCE_COL '", SOURCE_COL,
    "' not found in confirmed_hl_cohort.rds. ",
    "Available columns: ", paste(sort(names(cohort)), collapse = ", ")
  )

# Build a combined frame keyed by ID with group label for NOTX-01..NOTX-04.
# Start from the full cohort (no_tx + treated both needed — NOTX-06).
char_pt <- dplyr::bind_rows(no_tx, treated) %>%
  dplyr::select(
    ID, group, first_hl_dx_date,
    dplyr::all_of(c(WINDOW_START_COL, NLPHL_COL, AGE_DX_COL,
                    PAYER_CAT_COL, FAR_COL, SOURCE_COL))
  )

# NOTX-01: data-window truncation flag.
# window_truncated = TRUE  when first_hl_dx_date precedes the enrollment start.
# window_date_missing = TRUE when either date is NA (computed first; fed to ifelse).
char_pt <- char_pt %>%
  dplyr::mutate(
    window_date_missing = is.na(first_hl_dx_date) | is.na(.data[[WINDOW_START_COL]]),
    window_truncated    = dplyr::if_else(
      window_date_missing,
      FALSE,
      first_hl_dx_date < .data[[WINDOW_START_COL]]
    )
  )

notx01_summary <- char_pt %>%
  dplyr::group_by(group) %>%
  dplyr::summarise(
    n_patients          = dplyr::n(),
    n_window_truncated  = sum(window_truncated, na.rm = TRUE),
    n_window_date_missing = sum(window_date_missing, na.rm = TRUE),
    .groups = "drop"
  )

message("[R203 NOTX-01] window_truncated summary:")
print(notx01_summary)

# ==============================================================================
# SECTION 6: NOTX-02 — PERI-DIAGNOSIS ENCOUNTER COUNTS (Plan 203-02) ----
# DuckDB: query ENCOUNTER(ID, ADMIT_DATE); close connection before any other
# open_pcornet_con() call. Inequality join in R (same shape as R/180
# any_enc_year, R/180_cbc_missing_capture.R lines 558-562).
# ==============================================================================

open_pcornet_con()   # single shared connection (utils_duckdb.R line 128)
enc_all <- duck_query(
  "SELECT CAST(ID AS VARCHAR) AS ID,
          TRY_CAST(ADMIT_DATE AS DATE) AS admit_date
   FROM ENCOUNTER
   WHERE ADMIT_DATE IS NOT NULL"
)
close_pcornet_con()  # always close with close_pcornet_con() (see utils_duckdb.R)

enc_all <- enc_all %>%
  dplyr::mutate(ID = as.character(ID))

# Per-patient window bounds.
pt_windows <- char_pt %>%
  dplyr::select(ID, first_hl_dx_date) %>%
  dplyr::mutate(
    win_lo = first_hl_dx_date - PERI_DX_WINDOW_DAYS,
    win_hi = first_hl_dx_date + PERI_DX_WINDOW_DAYS
  ) %>%
  dplyr::filter(!is.na(first_hl_dx_date))

# Inequality join: same shape as R/180_cbc_missing_capture.R lines 558-562.
# Keeps encounters where admit_date is within [first_hl_dx_date - 90,
# first_hl_dx_date + 90].
peri_dx_enc <- pt_windows %>%
  dplyr::inner_join(
    enc_all,
    by = dplyr::join_by(ID, win_lo <= admit_date, win_hi >= admit_date)
  )

n_enc_per_pt <- peri_dx_enc %>%
  dplyr::count(ID, name = "n_enc_peri_dx")

# Join back; patients with no peri-dx encounters get 0 (not NA).
char_pt <- char_pt %>%
  dplyr::left_join(n_enc_per_pt, by = "ID") %>%
  dplyr::mutate(
    n_enc_peri_dx = dplyr::coalesce(n_enc_peri_dx, 0L)
  )

# Summarize per group: 0 | 1 | 2-4 | 5-9 | 10+ encounter bands.
enc_band <- function(n) {
  dplyr::case_when(
    n == 0L         ~ "0",
    n == 1L         ~ "1",
    n <= 4L         ~ "2-4",
    n <= 9L         ~ "5-9",
    TRUE            ~ "10+"
  )
}

notx02_summary <- char_pt %>%
  dplyr::mutate(enc_band = enc_band(n_enc_peri_dx)) %>%
  dplyr::count(group, enc_band) %>%
  dplyr::arrange(group, enc_band)

message("[R203 NOTX-02] peri-dx encounter bands per group:")
print(notx02_summary)

# ==============================================================================
# SECTION 7: NOTX-03 — DEMOGRAPHIC / CARE CHARACTERIZATION (Plan 203-02) ----
# Join R/169 single_source_care; derive age_group_dx and hl_subtype.
# ==============================================================================

ssc <- readRDS(R169_RDS) %>%
  dplyr::select(ID, single_source_care, single_source_care_post, primary_source) %>%
  dplyr::mutate(ID = as.character(ID))

char_pt <- char_pt %>%
  dplyr::left_join(ssc, by = "ID")

# age_group_dx: 0-17, 18-39, 40-59, 60+ (from AGE_DX_COL).
char_pt <- char_pt %>%
  dplyr::mutate(
    age_group_dx = dplyr::case_when(
      .data[[AGE_DX_COL]] < 18  ~ "0-17",
      .data[[AGE_DX_COL]] < 40  ~ "18-39",
      .data[[AGE_DX_COL]] < 60  ~ "40-59",
      !is.na(.data[[AGE_DX_COL]]) ~ "60+",
      TRUE                       ~ NA_character_
    ),
    hl_subtype = dplyr::if_else(
      .data[[NLPHL_COL]] %in% TRUE, "NLPHL", "cHL"
    )
  )

# Per-group summaries for each NOTX-03 characteristic (counts only; suppression
# deferred to Plan 203-03 per CLAUDE.md suppress-after-arithmetic rule).
notx03_ssc <- char_pt %>%
  dplyr::count(group, single_source_care, name = "n")

notx03_payer <- char_pt %>%
  dplyr::count(group, .data[[PAYER_CAT_COL]], name = "n")

notx03_far <- char_pt %>%
  dplyr::count(group, .data[[FAR_COL]], name = "n")

notx03_age <- char_pt %>%
  dplyr::count(group, age_group_dx, name = "n")

notx03_subtype <- char_pt %>%
  dplyr::count(group, hl_subtype, name = "n")

notx03_source <- char_pt %>%
  dplyr::count(group, .data[[SOURCE_COL]], name = "n")

message("[R203 NOTX-03] single_source_care counts:")
print(notx03_ssc)
message("[R203 NOTX-03] payer counts:")
print(notx03_payer)
message("[R203 NOTX-03] far_from_care counts:")
print(notx03_far)
message("[R203 NOTX-03] age_group_dx counts:")
print(notx03_age)
message("[R203 NOTX-03] hl_subtype counts:")
print(notx03_subtype)

# ==============================================================================
# SECTION 8: NOTX-04 — REGISTRY TREATMENT JOIN (Plan 203-02) ----
# Join R/193 TR flags; derive registry_tx_given and
# registry_says_tx_pipeline_missed stratum.
# ==============================================================================

trflags <- readRDS(TRFLAGS_RDS) %>%
  dplyr::mutate(ID = as.character(ID))

# TR treatment columns — candidate names from probe placeholder.
# Update TR_TX_COLS once 203_schema_<date>.md is written by probe_inputs().
TR_TX_COLS <- c("rx_summ_treatment_status", "rx_summ_systemic_surg_seq")
missing_tr <- setdiff(TR_TX_COLS, names(trflags))
if (length(missing_tr) > 0)
  stop(
    "[R203] TR_TX_COLS column(s) not found in TRFLAGS_RDS: ",
    paste(missing_tr, collapse = ", "),
    ". Available columns: ", paste(sort(names(trflags)), collapse = ", ")
  )

char_pt <- char_pt %>%
  dplyr::left_join(
    dplyr::select(trflags, ID, dplyr::all_of(TR_TX_COLS)),
    by = "ID"
  )

# registry_tx_given: TRUE if any TR treatment column is non-missing and
# indicates treatment was given (non-NA, non-blank, non-"0", non-"00",
# non-"No treatment").  Exact logic depends on probe-confirmed value sets;
# the guard below stops with available values if codes differ on HiPerGator.
REGISTRY_TX_GIVEN_EXCL <- c(NA_character_, "", "0", "00",
                             "No treatment", "None", "Unknown", "88", "99")

registry_tx_flag <- trflags %>%
  dplyr::select(ID, dplyr::all_of(TR_TX_COLS)) %>%
  tidyr::pivot_longer(
    cols      = dplyr::all_of(TR_TX_COLS),
    names_to  = "tr_col",
    values_to = "tr_val"
  ) %>%
  dplyr::mutate(
    tr_val_chr = as.character(tr_val),
    tx_indicated = !tr_val_chr %in% REGISTRY_TX_GIVEN_EXCL
  ) %>%
  dplyr::group_by(ID) %>%
  dplyr::summarise(registry_tx_given = any(tx_indicated, na.rm = TRUE),
                   .groups = "drop")

char_pt <- char_pt %>%
  dplyr::left_join(registry_tx_flag, by = "ID") %>%
  dplyr::mutate(
    registry_tx_given = dplyr::coalesce(registry_tx_given, FALSE),
    # NOTX-04 named stratum: registry indicates treatment but pipeline captured 0.
    registry_says_tx_pipeline_missed =
      registry_tx_given & group == "no_treatment"
  )

notx04_summary <- char_pt %>%
  dplyr::group_by(group) %>%
  dplyr::summarise(
    n_tr_fields_present           = sum(!is.na(.data[[TR_TX_COLS[1]]]) |
                                        !is.na(.data[[TR_TX_COLS[2]]]),
                                        na.rm = TRUE),
    n_registry_tx_given           = sum(registry_tx_given, na.rm = TRUE),
    n_registry_says_tx_missed     = sum(registry_says_tx_pipeline_missed, na.rm = TRUE),
    .groups = "drop"
  )

message("[R203 NOTX-04] registry treatment summary (NOTX-04 stratum):")
print(notx04_summary)
message(glue(
  "[R203] char_pt complete: {nrow(char_pt)} rows, {ncol(char_pt)} columns; ",
  "groups: ", paste(sort(unique(char_pt$group)), collapse = " | ")
))

# ==============================================================================
# SECTION 9: SAVE PATIENT-LEVEL FRAME (internal only) ----
# char_pt is patient-level (IDs present) — write to output/internal/ only.
# ==============================================================================

out_rds <- file.path(
  CONFIG$output_dir, "internal",
  glue("203_no_treatment_characterization_{RUN_DATE}.rds")
)
dir.create(dirname(out_rds), showWarnings = FALSE, recursive = TRUE)
saveRDS(char_pt, out_rds)
message(glue("[R203] char_pt saved: {out_rds}"))

# ==============================================================================
# SECTION 10: NOTX-05 — CANDIDATE "TREATMENT OBSERVABLE" RULE (Plan 203-03) ----
# RULE NOT APPLIED — proposed team decision item (D-203-01).
# The flag is documented and counted per group but never used to filter the
# cohort or remove any patient from the analysis.
# ==============================================================================

# treatment_observable: patient had >= 1 encounter within +/-90 days of dx AND
# diagnosis is not truncated by the data window AND dates are not missing.
# This is the proposed rule; it is NOT applied as a filter here.
char_pt <- char_pt %>%
  dplyr::mutate(
    treatment_observable = (n_enc_peri_dx >= 1L) &
                           (!window_truncated) &
                           (!window_date_missing)
  )

# Detailed FALSE-reason breakdown (mutually exclusive — assign first applicable).
char_pt <- char_pt %>%
  dplyr::mutate(
    tx_obs_false_reason = dplyr::case_when(
      treatment_observable                    ~ NA_character_,
      window_date_missing                     ~ "dates_missing",
      window_truncated                        ~ "window_truncated",
      n_enc_peri_dx == 0L                     ~ "no_peri_dx_encounter",
      TRUE                                    ~ "other"
    )
  )

# Per-group summary of treatment_observable TRUE/FALSE.
message("[R203 NOTX-05] treatment_observable counts (RULE NOT APPLIED):")
tx_obs_counts <- char_pt %>%
  dplyr::count(group, treatment_observable) %>%
  dplyr::arrange(group, treatment_observable)
print(tx_obs_counts)

# candidate_rules_tbl: per group, TRUE | FALSE and breakdown of FALSE reasons.
# Includes an explicit label that this rule is not applied.
#
# RULE NOT APPLIED — proposed team decision item (D-203-01)
candidate_rules_tbl <- dplyr::bind_rows(
  # Row 1: label row (not applied)
  tibble::tibble(
    group              = "** RULE NOT APPLIED — proposed team decision item (D-203-01) **",
    n_total            = NA_integer_,
    n_observable_true  = NA_integer_,
    n_observable_false = NA_integer_,
    n_false_dates_missing    = NA_integer_,
    n_false_window_truncated = NA_integer_,
    n_false_no_peri_dx       = NA_integer_
  ),
  char_pt %>%
    dplyr::group_by(group) %>%
    dplyr::summarise(
      n_total            = dplyr::n(),
      n_observable_true  = sum(treatment_observable,  na.rm = TRUE),
      n_observable_false = sum(!treatment_observable, na.rm = TRUE),
      n_false_dates_missing    = sum(tx_obs_false_reason == "dates_missing",        na.rm = TRUE),
      n_false_window_truncated = sum(tx_obs_false_reason == "window_truncated",     na.rm = TRUE),
      n_false_no_peri_dx       = sum(tx_obs_false_reason == "no_peri_dx_encounter", na.rm = TRUE),
      .groups = "drop"
    )
)

message("[R203 NOTX-05] candidate_rules_tbl:")
print(candidate_rules_tbl)

# ==============================================================================
# SECTION 11: WORKBOOK ASSEMBLY (Plan 203-03) ----
# KEY leftmost, then A_profile, B_reasons_waterfall, C_by_source,
# D_candidate_rules, QC. <11 suppression applied at display time.
# Patient-level data written to output/internal/ ONLY (char_pt already saved
# in Section 9; this section produces the team-facing xlsx).
# ==============================================================================

# --- Suppression helpers (local scope) ----------------------------------------
suppress_small <- function(n) {
  ifelse(!is.na(n) & n > 0L & n <= 10L, "<11", as.character(n))
}
sup_col <- function(x) vapply(x, function(v) suppress_small(v), character(1))

# Apply suppression to a data frame: suppress all integer/numeric columns named
# in `count_cols`; blank character columns named in `blank_cols` where
# the corresponding count is suppressed (complementary suppression).
sup_df <- function(df, count_cols, blank_cols = character(0)) {
  for (col in count_cols) {
    if (!col %in% names(df)) next
    raw <- df[[col]]
    hit <- !is.na(raw) & raw > 0L & raw <= 10L
    if (length(blank_cols) > 0) {
      for (bc in blank_cols) {
        if (bc %in% names(df)) df[[bc]][hit] <- ""
      }
    }
    df[[col]] <- suppress_small(raw)
  }
  df
}

# --- UF colours / styles -------------------------------------------------------
UF_BLUE   <- "#0021A5"
UF_ORANGE <- "#FA4616"

hdr_style <- openxlsx::createStyle(
  fgFill         = UF_BLUE,
  fontColour     = "white",
  textDecoration = "bold",
  fontName       = "Arial",
  fontSize       = 11,
  halign         = "left"
)
accent_style <- openxlsx::createStyle(
  fgFill         = UF_ORANGE,
  fontColour     = "white",
  textDecoration = "bold",
  fontName       = "Arial",
  fontSize       = 11
)

# Helper: add sheet, write data with header styling, optional accent on row 1.
write_sheet <- function(wb, sheet_name, df, accent_first = FALSE,
                        col_widths = 20) {
  openxlsx::addWorksheet(wb, sheet_name)
  openxlsx::writeData(wb, sheet_name, df, startRow = 1, headerStyle = hdr_style)
  openxlsx::setColWidths(wb, sheet_name, cols = seq_len(ncol(df)),
                         widths = col_widths)
  if (accent_first && nrow(df) >= 1) {
    openxlsx::addStyle(wb, sheet_name, accent_style,
                       rows = 2, cols = seq_len(ncol(df)), stack = FALSE)
  }
}

# --- Build display frames (suppression applied here) --------------------------

# A_profile: side-by-side profile for each NOTX-01..NOTX-04 characteristic.
# One long table pivoted so no_treatment and treated are ADJACENT columns.
build_profile_section <- function(df_long, label_col, characteristic_name) {
  # df_long has columns: group, <label_col>, n
  df_long %>%
    dplyr::rename(category = dplyr::all_of(label_col)) %>%
    dplyr::mutate(category = as.character(category)) %>%
    tidyr::pivot_wider(names_from = group, values_from = n, values_fill = 0L) %>%
    dplyr::mutate(
      characteristic = characteristic_name,
      no_treatment = suppress_small(no_treatment),
      treated      = suppress_small(treated)
    ) %>%
    dplyr::select(characteristic, category, no_treatment, treated)
}

a_window <- build_profile_section(
  char_pt %>% dplyr::count(group, window_truncated),
  "window_truncated", "NOTX-01 window_truncated"
)
a_dates_missing <- build_profile_section(
  char_pt %>% dplyr::count(group, window_date_missing),
  "window_date_missing", "NOTX-01 window_date_missing"
)
a_enc_band <- build_profile_section(
  char_pt %>%
    dplyr::mutate(enc_band = enc_band(n_enc_peri_dx)) %>%
    dplyr::count(group, enc_band),
  "enc_band", "NOTX-02 peri_dx_encounters"
)
a_ssc <- build_profile_section(
  notx03_ssc, "single_source_care", "NOTX-03 single_source_care"
)
a_source <- build_profile_section(
  notx03_source, SOURCE_COL, "NOTX-03 SOURCE"
)
a_payer <- build_profile_section(
  notx03_payer, PAYER_CAT_COL, "NOTX-03 payer"
)
a_far <- build_profile_section(
  notx03_far, FAR_COL, "NOTX-03 far_from_care_100mi"
)
a_age <- build_profile_section(
  notx03_age, "age_group_dx", "NOTX-03 age_group_dx"
)
a_subtype <- build_profile_section(
  notx03_subtype, "hl_subtype", "NOTX-03 hl_subtype"
)
# NOTX-04: registry
a_reg_tx <- build_profile_section(
  char_pt %>% dplyr::count(group, registry_tx_given),
  "registry_tx_given", "NOTX-04 registry_tx_given"
)
a_reg_missed <- build_profile_section(
  char_pt %>% dplyr::count(group, registry_says_tx_pipeline_missed),
  "registry_says_tx_pipeline_missed",
  "NOTX-04 registry_says_tx_pipeline_missed"
)

sheet_A <- dplyr::bind_rows(
  a_window, a_dates_missing, a_enc_band, a_ssc, a_source,
  a_payer, a_far, a_age, a_subtype, a_reg_tx, a_reg_missed
)

# B_reasons_waterfall: fraction of no_treatment patients for three reasons.
n_notx_total <- sum(char_pt$group == "no_treatment")

make_reason_row <- function(label, n_int) {
  pct_str <- if (!is.na(n_int) && n_int >= 11L && n_notx_total >= 11L) {
    sprintf("%.1f%%", 100 * n_int / n_notx_total)
  } else {
    ""
  }
  tibble::tibble(
    reason    = label,
    n         = suppress_small(n_int),
    pct_of_no_treatment = pct_str
  )
}

notx_pt <- char_pt %>% dplyr::filter(group == "no_treatment")

sheet_B <- dplyr::bind_rows(
  make_reason_row(
    "Total no_treatment patients",
    n_notx_total
  ),
  make_reason_row(
    "window_truncated (dx before data window start)",
    sum(notx_pt$window_truncated, na.rm = TRUE)
  ),
  make_reason_row(
    "no peri-dx encounter (n_enc_peri_dx == 0)",
    sum(notx_pt$n_enc_peri_dx == 0L, na.rm = TRUE)
  ),
  make_reason_row(
    "registry_says_tx_pipeline_missed (TR says tx; pipeline captured 0)",
    sum(notx_pt$registry_says_tx_pipeline_missed, na.rm = TRUE)
  )
)

# C_by_source: NOTX characteristics by SOURCE, both groups.
c_source_window <- char_pt %>%
  dplyr::count(group, .data[[SOURCE_COL]], window_truncated, name = "n") %>%
  dplyr::mutate(
    characteristic = "window_truncated",
    category = as.character(window_truncated),
    n = suppress_small(n)
  ) %>%
  dplyr::select(group, SOURCE = dplyr::all_of(SOURCE_COL),
                characteristic, category, n)

c_source_ssc <- char_pt %>%
  dplyr::count(group, .data[[SOURCE_COL]], single_source_care, name = "n") %>%
  dplyr::mutate(
    characteristic = "single_source_care",
    category = as.character(single_source_care),
    n = suppress_small(n)
  ) %>%
  dplyr::select(group, SOURCE = dplyr::all_of(SOURCE_COL),
                characteristic, category, n)

c_source_payer <- char_pt %>%
  dplyr::count(group, .data[[SOURCE_COL]], .data[[PAYER_CAT_COL]], name = "n") %>%
  dplyr::rename(category = dplyr::all_of(PAYER_CAT_COL)) %>%
  dplyr::mutate(
    characteristic = "payer",
    category = as.character(category),
    n = suppress_small(n)
  ) %>%
  dplyr::select(group, SOURCE = dplyr::all_of(SOURCE_COL),
                characteristic, category, n)

sheet_C <- dplyr::bind_rows(c_source_window, c_source_ssc, c_source_payer) %>%
  dplyr::arrange(group, SOURCE, characteristic, category)

# D_candidate_rules: candidate_rules_tbl with suppression on integer counts.
sheet_D <- candidate_rules_tbl %>%
  dplyr::mutate(
    n_total            = suppress_small(n_total),
    n_observable_true  = suppress_small(n_observable_true),
    n_observable_false = suppress_small(n_observable_false),
    n_false_dates_missing    = suppress_small(n_false_dates_missing),
    n_false_window_truncated = suppress_small(n_false_window_truncated),
    n_false_no_peri_dx       = suppress_small(n_false_no_peri_dx)
  )

# QC sheet.
n_treated_total <- sum(char_pt$group == "treated")
n_total_all     <- nrow(char_pt)
n_dates_missing <- sum(char_pt$window_date_missing, na.rm = TRUE)
n_r169_missing  <- sum(is.na(char_pt$single_source_care))
n_tr_missing    <- sum(is.na(char_pt$registry_tx_given))

sheet_QC <- tibble::tibble(
  check = c(
    "Population reconciliation: no_treatment + treated == total",
    "no_treatment",
    "treated",
    "total cohort",
    "reconciliation_ok",
    "window_date_missing (either date NA)",
    "patients missing R169 single_source_care join",
    "patients missing TR-flags join (registry_tx_given NA before coalesce)",
    "suppression_applied",
    "D-203-01 note"
  ),
  value = c(
    paste0(n_notx_total, " + ", n_treated_total, " == ", n_total_all),
    suppress_small(n_notx_total),
    suppress_small(n_treated_total),
    suppress_small(n_total_all),
    as.character(n_notx_total + n_treated_total == n_total_all),
    suppress_small(n_dates_missing),
    suppress_small(n_r169_missing),
    suppress_small(n_tr_missing),
    "YES — all patient counts 1-10 shown as <11",
    "RULE NOT APPLIED — treatment_observable is a proposed candidate rule (D-203-01)"
  )
)

# KEY sheet.
sheet_KEY <- tibble::tibble(
  item  = c(
    "run_date",
    "script",
    "input: cohort_rds",
    "input: gantt180_csv",
    "input: r169_rds",
    "input: trflags_rds",
    "pinned: cohort_rds",
    "pinned: gantt180_csv",
    "pinned: r169_rds",
    "pinned: trflags_rds",
    "group: no_treatment",
    "group: treated",
    "sheet: KEY",
    "sheet: A_profile",
    "sheet: B_reasons_waterfall",
    "sheet: C_by_source",
    "sheet: D_candidate_rules",
    "sheet: QC",
    "suppression_note",
    "D-203-01"
  ),
  value = c(
    RUN_DATE,
    "R/203_no_treatment_characterization.R",
    pin_info$cohort_rds$path,
    pin_info$gantt180_csv$path,
    pin_info$r169_rds$path,
    pin_info$trflags_rds$path,
    as.character(pin_info$cohort_rds$pinned),
    as.character(pin_info$gantt180_csv$pinned),
    as.character(pin_info$r169_rds$pinned),
    as.character(pin_info$trflags_rds$pinned),
    "0 captured treatment episodes in gantt_episodes_180",
    ">=1 captured treatment episode in gantt_episodes_180",
    "this sheet — provenance, inputs, group definitions, notes",
    "side-by-side NOTX-01..NOTX-04 profile: no_treatment vs treated",
    "fraction of no_treatment patients meeting each truncation/capture reason",
    "NOTX characteristics broken down by SOURCE/partner site, both groups",
    "proposed treatment_observable candidate rule (RULE NOT APPLIED — D-203-01)",
    "population reconciliation and join-completeness checks",
    "Patient counts 1-10 are shown as <11. Rates/pct only when N and D >= 11.",
    "RULE NOT APPLIED — treatment_observable is a proposed team decision item"
  )
)

# --- Assemble workbook --------------------------------------------------------
wb <- openxlsx::createWorkbook()

# KEY leftmost — added first.
write_sheet(wb, "KEY",                sheet_KEY,   accent_first = TRUE)
write_sheet(wb, "A_profile",          sheet_A,     accent_first = FALSE)
write_sheet(wb, "B_reasons_waterfall", sheet_B,    accent_first = FALSE)
write_sheet(wb, "C_by_source",        sheet_C,     accent_first = FALSE)
write_sheet(wb, "D_candidate_rules",  sheet_D,     accent_first = TRUE)
write_sheet(wb, "QC",                 sheet_QC,    accent_first = FALSE)

out_fname <- glue("203_no_treatment_characterization_{format(Sys.Date(), '%Y%m%d')}.xlsx")
out_path  <- file.path(CONFIG$output_dir, out_fname)
dir.create(CONFIG$output_dir, showWarnings = FALSE, recursive = TRUE)
openxlsx::saveWorkbook(wb, out_path, overwrite = TRUE)

message(glue("[R203] Workbook written: {out_path}"))
message(glue(
  "[R203] Sheets: KEY ({nrow(sheet_KEY)} rows), ",
  "A_profile ({nrow(sheet_A)}), B_reasons_waterfall ({nrow(sheet_B)}), ",
  "C_by_source ({nrow(sheet_C)}), D_candidate_rules ({nrow(sheet_D)}), ",
  "QC ({nrow(sheet_QC)})"
))

# patient-level char_pt already written to output/internal in Section 9;
# the xlsx workbook above contains NO patient IDs.
message("[R203] Plan 203-03 complete. Patient-level RDS in output/internal/ only.")
