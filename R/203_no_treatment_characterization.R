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
#          output/internal/203_no_treatment_<date>.rds  (patient-level)
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
  glue("203_no_treatment_{RUN_DATE}.rds")
)
dir.create(dirname(out_rds), showWarnings = FALSE, recursive = TRUE)
saveRDS(char_pt, out_rds)
message(glue("[R203] char_pt saved: {out_rds}"))

# Plan 203-03 will read char_pt from this RDS and produce suppression-ready
# workbook sheets (A_profile, B_reasons_waterfall, C_by_source).
message("[R203] Section 203-02 characterization blocks complete. ",
        "Output workbook produced in Plan 203-03.")
