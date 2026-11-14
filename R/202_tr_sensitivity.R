# ==============================================================================
# 202_tr_sensitivity.R
# ==============================================================================
#
# Purpose:
#   Tumor-registry treatment sensitivity analysis.
#   Compares registry first-course treatment fields against Gantt pipeline
#   capture for TR-HL patients in gantt_episodes_180 (denominator approx 600).
#   Reports sensitivity by treatment type, SOURCE, and diagnosis year;
#   reverse (PPV-direction) agreement; date-difference distribution.
#   The 121 TR-HL patients outside confirmed_hl_cohort.rds are reported as
#   a footnote row, not in the sensitivity denominator.
#
# Inputs (all pinned):
#   - R202_GANTT_180      gantt_episodes_180 CSV (HiPerGator only)
#   - R202_TR_FLAGS       tr_lymphoma_flags_all_patients RDS from R/193
#   - R202_COHORT_RDS     confirmed_hl_cohort.rds (used in Section 10 D_by_year)
#   - R202_TR_DATA        TUMOR_REGISTRY_ALL treatment columns (queried live)
#   - R202_OUTPUT_DIR     output directory (default: output/)
#
# Outputs:
#   - output/202_tr_sensitivity_YYYYMMDD.xlsx
#       Sheets: KEY, A_sensitivity, B_date_diff, C_by_source, D_by_year, QC
#
# Phase 202 TRVAL-01 through TRVAL-07
#
# Run interactively on HiPerGator:
#   module load R/4.5; R --no-save
#   source("R/202_tr_sensitivity.R", local = new.env(parent = globalenv()))
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
  library(glue)
  library(vroom)
  library(writexl)
  library(openxlsx)
})

source("R/00_config.R")
source("R/utils/utils_duckdb.R")
message("=== R/202: Tumor-registry treatment sensitivity ===\n")

# --- IS_LOCAL GUARD -----------------------------------------------------------
# TUMOR_REGISTRY_ALL and gantt_episodes_180 exist only on HiPerGator.
if (IS_LOCAL) {
  stop(paste0(
    "R/202 reads gantt_episodes_180 and TUMOR_REGISTRY_ALL, which exist only on HiPerGator. ",
    "Run this script interactively after `module load R/4.5` on a HiPerGator compute node."
  ))
}

# --- SMALL-CELL SUPPRESSION HELPER -------------------------------------------
fmt_sup <- function(n) {
  if (is.na(n)) return(NA_character_)
  n <- as.integer(n)
  if (n >= 1L & n <= 10L) "<11" else format(n, big.mark = ",")
}
sup_col <- function(x) vapply(x, fmt_sup, character(1))

# --- PINNED INPUTS -----------------------------------------------------------
gantt_180_path <- {
  ev <- Sys.getenv("R202_GANTT_180", unset = "")
  if (ev != "") ev else CONFIG$gantt_180_snapshot_path
}
if (is.null(gantt_180_path) || gantt_180_path == "" || !file.exists(gantt_180_path)) {
  stop(glue("R202: gantt_180 not found at '{gantt_180_path}'. ",
            "Set R202_GANTT_180 or confirm CONFIG$gantt_180_snapshot_path."))
}

tr_flags_path <- Sys.getenv("R202_TR_FLAGS",
  unset = "/blue/erin.mobley-hl.bcu/insurance_investigation/output/internal/tr_lymphoma_flags_all_patients_<DATED>.rds")
if (!file.exists(tr_flags_path))
  stop("[R202] R202_TR_FLAGS file not found: ", tr_flags_path,
       "\nSet R202_TR_FLAGS to the Phase 201/193 TR flags RDS path.")

cohort_rds_path <- Sys.getenv("R202_COHORT_RDS",
  unset = file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds"))
if (!file.exists(cohort_rds_path))
  stop("[R202] confirmed_hl_cohort.rds not found: ", cohort_rds_path,
       "\nSet R202_COHORT_RDS to the path of confirmed_hl_cohort.rds.")

output_dir <- {
  ev <- Sys.getenv("R202_OUTPUT_DIR", unset = "")
  if (ev != "") ev else CONFIG$output_dir
}
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

message(glue("  gantt_180:   {gantt_180_path}"))
message(glue("  tr_flags:    {tr_flags_path}"))
message(glue("  cohort_rds:  {cohort_rds_path}"))
message(glue("  output_dir:  {output_dir}\n"))

# --- TR COLUMN CONSTANTS (PENDING-PROBE) ------------------------------------
# Source: R/10_cohort_predicates.R (lines 248-249, 398-399, 558, 568-571).
# Confirm column names with probe output in .planning/schemas/202_schema_*.md
# before running the comparison section below.

# Chemotherapy: TR1 uses CHEMO_START_DATE_SUMMARY; TR2/TR3 use DT_CHEMO
TR_CHEMO_COLS <- c("CHEMO_START_DATE_SUMMARY", "DT_CHEMO")  # PENDING-PROBE

# Radiation: TR1 uses RAD_START_DATE_SUMMARY; TR2/TR3 use DT_RAD
TR_RAD_COLS   <- c("RAD_START_DATE_SUMMARY", "DT_RAD")      # PENDING-PROBE

# Immunotherapy: column name unknown — PENDING PROBE
# Common candidates: RX_SUMM_IMMUNO, DT_IMMUNO, IMMUNO_DATE_SUMMARY
TR_IMMUNO_COLS <- character(0)  # PENDING-PROBE: fill after schema probe

# Transplant/SCT:
#   TR1: HEMATOLOGIC_TRANSPLANT_AND_ENDOC (code; non-NA/non-""/non-"00" = flagged)
#   TR2/TR3: DT_HTE, DT_SCT (dates)
TR_SCT_CODE_COL  <- "HEMATOLOGIC_TRANSPLANT_AND_ENDOC"  # PENDING-PROBE (TR1)
TR_SCT_DATE_COLS <- c("DT_HTE", "DT_SCT", "DT_TRANSPLANT", "HCT_DATE",
                      "TRANSPLANT_DATE", "SCT_DATE", "BMT_DATE") # PENDING-PROBE (TR2/3)

# --- SECTION 1: LOAD GANTT_EPISODES_180 -------------------------------------
message("=== Section 1: Load gantt_episodes_180 ===")
gantt <- vroom(gantt_180_path, col_types = cols(
  patient_id    = col_character(),
  treatment_type = col_character(),
  episode_start = col_date(format = ""),
  episode_stop  = col_date(format = ""),
  tr_hl_dx      = col_logical(),
  tr_nhl_dx     = col_logical(),
  .default      = col_character()
), show_col_types = FALSE)

# Patient-level gantt population (one row per patient)
gantt_pts <- gantt |>
  distinct(patient_id, tr_hl_dx, tr_nhl_dx, SOURCE) |>
  # tr_hl_dx/tr_nhl_dx are constant within patient_id (checked by R/88 Phase 201)
  group_by(patient_id) |>
  slice(1L) |>
  ungroup()

n_gantt_pts <- n_distinct(gantt$patient_id)
message(glue("  gantt_episodes_180: {nrow(gantt)} rows, {n_gantt_pts} distinct patients"))

# --- SECTION 2: LOAD TR FLAGS ------------------------------------------------
message("=== Section 2: Load TR flags (R/193 output) ===")
tr_flags <- readRDS(tr_flags_path)
n_tr_hl_all <- sum(tr_flags$tr_hl_dx == TRUE, na.rm = TRUE)
message(glue("  TR flags: {nrow(tr_flags)} patients; {n_tr_hl_all} with tr_hl_dx TRUE"))

# --- SECTION 3: LOAD TR TREATMENT COLUMNS -----------------------------------
# Collect only columns needed for comparison (avoid loading full table).
message("=== Section 3: Load TR treatment columns from TUMOR_REGISTRY_ALL ===")
open_pcornet_con()
tr_tbl_raw <- get_pcornet_table("TUMOR_REGISTRY_ALL")
tr_all_cols <- colnames(tr_tbl_raw)

# Intersect with known column sets (PENDING-PROBE: update constants above)
tr_chemo_present  <- intersect(TR_CHEMO_COLS,    tr_all_cols)
tr_rad_present    <- intersect(TR_RAD_COLS,      tr_all_cols)
tr_immuno_present <- intersect(TR_IMMUNO_COLS,   tr_all_cols)
tr_sct_code_pres  <- TR_SCT_CODE_COL %in% tr_all_cols
tr_sct_date_pres  <- intersect(TR_SCT_DATE_COLS, tr_all_cols)

needed_cols <- unique(c(
  "ID",
  tr_chemo_present, tr_rad_present, tr_immuno_present,
  if (tr_sct_code_pres) TR_SCT_CODE_COL,
  tr_sct_date_pres
))

tr_data <- tr_tbl_raw |>
  select(all_of(needed_cols)) |>
  collect()
close_pcornet_con()
message(glue("  TUMOR_REGISTRY_ALL: {nrow(tr_data)} rows; columns: {paste(needed_cols, collapse=', ')}"))

# --- SECTION 4: BUILD POPULATIONS -------------------------------------------
# pop_denom   = TR-HL patients who ARE in gantt_episodes_180 (sensitivity denominator)
# pop_footnote = TR-HL patients NOT in gantt_episodes_180 (D-201-04; footnote only)
message("=== Section 4: Build denominator and footnote populations ===")

# TR-HL patient IDs (from tr_flags, confirmed by tr_hl_dx == TRUE)
tr_hl_ids <- tr_flags |>
  filter(tr_hl_dx == TRUE) |>
  pull(ID)

gantt_pt_ids <- gantt_pts$patient_id

# Denominator: in gantt AND tr_hl_dx TRUE
pop_denom <- gantt_pts |>
  filter(patient_id %in% tr_hl_ids) |>
  left_join(tr_data, by = c("patient_id" = "ID"))

# Footnote: tr_hl_dx TRUE but NOT in gantt
pop_footnote_ids <- setdiff(tr_hl_ids, gantt_pt_ids)
pop_footnote <- tr_flags |>
  filter(ID %in% pop_footnote_ids) |>
  left_join(tr_data, by = "ID")

n_denom    <- nrow(pop_denom)
n_footnote <- nrow(pop_footnote)
message(glue("  Denominator (in gantt + TR-HL): {n_denom} patients (expected approx 600)"))
message(glue("  Footnote (TR-HL not in gantt):  {n_footnote} patients (expected 121)"))

if (n_denom < 500L || n_denom > 700L)
  warning(glue("R202: denominator {n_denom} outside expected 500-700 range — verify inputs"))
if (n_footnote < 100L || n_footnote > 150L)
  warning(glue("R202: footnote count {n_footnote} outside expected 100-150 range — verify inputs"))
