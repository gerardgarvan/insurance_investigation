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
# SECTION 5: PLACEHOLDER — NOTX tables added in Plan 203-02 ----
# ==============================================================================

# NOTX tables added in Plan 203-02
