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

# --- TREATMENT TYPE MAPPING --------------------------------------------------
# Maps analysis labels to:
#   tr_date_cols: columns in pop_denom that signal TR records this treatment
#   gantt_type:   treatment_type value in gantt_episodes_180
# PENDING-PROBE: tr_immuno_cols is empty until probe confirms immunotherapy column name.

TRTYPES <- list(
  chemo = list(
    label        = "Chemotherapy",
    tr_date_cols = tr_chemo_present,     # e.g. CHEMO_START_DATE_SUMMARY / DT_CHEMO
    tr_code_col  = NULL,
    tr_code_vals = NULL,
    gantt_type   = "Chemotherapy"
  ),
  radiation = list(
    label        = "Radiation",
    tr_date_cols = tr_rad_present,       # e.g. RAD_START_DATE_SUMMARY / DT_RAD
    tr_code_col  = NULL,
    tr_code_vals = NULL,
    gantt_type   = "Radiation"
  ),
  immunotherapy = list(
    label        = "Immunotherapy",
    tr_date_cols = tr_immuno_present,    # PENDING-PROBE: empty until probe
    tr_code_col  = NULL,
    tr_code_vals = NULL,
    gantt_type   = "Immunotherapy"
  ),
  sct = list(
    label        = "Stem Cell Transplant",
    tr_date_cols = tr_sct_date_pres,
    tr_code_col  = if (tr_sct_code_pres) TR_SCT_CODE_COL else NULL,
    tr_code_vals = c("00"),              # "00" = not done; anything else = flagged
    gantt_type   = "Stem Cell Transplant"
  )
)

# Returns the first TR date for a treatment type column set,
# or NA if no non-NA value found. For SCT code columns, returns
# as.Date("1900-01-01") as a sentinel when code is non-"00"/non-NA/non-"".
tr_first_date <- function(row, type_def) {
  # Date-column approach (chemo, rad, immuno, sct date cols)
  for (col in type_def$tr_date_cols) {
    if (col %in% names(row) && !is.na(row[[col]])) {
      d <- suppressWarnings(as.Date(row[[col]]))
      if (!is.na(d)) return(d)
    }
  }
  # Code-column approach (SCT TR1: HEMATOLOGIC_TRANSPLANT_AND_ENDOC)
  if (!is.null(type_def$tr_code_col)) {
    code_col <- type_def$tr_code_col
    if (code_col %in% names(row)) {
      v <- row[[code_col]]
      if (!is.na(v) && v != "" && !v %in% type_def$tr_code_vals) {
        return(as.Date("1900-01-01"))  # sentinel: TR says yes but no date
      }
    }
  }
  return(NA_Date_)
}

# --- SECTION 5: GANTT FIRST-EPISODE DATES PER PATIENT ----------------------
message("=== Section 5: Gantt first-episode dates per patient x treatment type ===")
gantt_first <- gantt |>
  filter(patient_id %in% pop_denom$patient_id) |>
  filter(!is.na(episode_start)) |>
  group_by(patient_id, treatment_type) |>
  summarise(gantt_first_date = min(episode_start, na.rm = TRUE), .groups = "drop")
message(glue("  gantt_first: {nrow(gantt_first)} patient x type rows"))

# --- SECTION 6: CAPTURE CLASSIFICATION --------------------------------------
# Classifies each denominator patient x treatment type into one of:
#   exact         tr_date == gantt_date (same day)
#   within_30d    |tr_date - gantt_date| <= 30
#   within_90d    |tr_date - gantt_date| <= 90
#   not_captured  TR says treatment given; no matching gantt episode
#   no_registry   TR does not record this treatment (not in denominator for this type)
#
# Note: immunotherapy classification will be "no_registry" for all patients
# until PENDING-PROBE fills TR_IMMUNO_COLS. This is correct behavior —
# the probe must confirm the column before any captures can be classified.
message("=== Section 6: Capture classification ===")

classify_capture <- function(denom_df, gantt_first_df, type_key, type_def) {
  gtype <- type_def$gantt_type
  g_dates <- gantt_first_df |>
    filter(treatment_type == gtype) |>
    select(patient_id, gantt_first_date)

  denom_df |>
    rowwise() |>
    mutate(
      tr_date = tr_first_date(across(everything()), type_def),
      has_tr  = !is.na(tr_date)
    ) |>
    ungroup() |>
    left_join(g_dates, by = "patient_id") |>
    mutate(
      capture_tier = case_when(
        !has_tr                                              ~ "no_registry",
        !is.na(gantt_first_date) & tr_date == as.Date("1900-01-01") ~ "not_datable",
        !is.na(gantt_first_date) & abs(as.integer(tr_date - gantt_first_date)) == 0 ~ "exact",
        !is.na(gantt_first_date) & abs(as.integer(tr_date - gantt_first_date)) <= 30 ~ "within_30d",
        !is.na(gantt_first_date) & abs(as.integer(tr_date - gantt_first_date)) <= 90 ~ "within_90d",
        is.na(gantt_first_date)                              ~ "not_captured",
        TRUE                                                 ~ "not_captured"
      ),
      treatment_label = type_def$label
    ) |>
    select(patient_id, SOURCE, treatment_label, tr_date, gantt_first_date, capture_tier)
}

classified <- bind_rows(lapply(names(TRTYPES), function(k) {
  classify_capture(pop_denom, gantt_first, k, TRTYPES[[k]])
}))
message(glue("  Classified rows: {nrow(classified)} ({n_distinct(classified$patient_id)} patients x treatment types)"))

# --- SECTION 7: A_SENSITIVITY TABLE -----------------------------------------
message("=== Section 7: A_sensitivity ===")

# Denominator per treatment type = patients where TR records treatment (has_tr TRUE)
# Numerator = patients classified as exact / within_30d / within_90d (any capture)
sensitivity_raw <- classified |>
  filter(capture_tier != "no_registry") |>  # denominator: TR records treatment
  group_by(treatment_label) |>
  summarise(
    n_denom   = n(),
    n_exact   = sum(capture_tier == "exact"),
    n_30d     = sum(capture_tier %in% c("exact", "within_30d")),
    n_90d     = sum(capture_tier %in% c("exact", "within_30d", "within_90d")),
    n_captured = n_90d,
    n_not_captured = sum(capture_tier == "not_captured"),
    .groups = "drop"
  ) |>
  mutate(
    pct_exact     = ifelse(n_denom >= 11L, round(100 * n_exact / n_denom, 1), NA_real_),
    pct_30d       = ifelse(n_denom >= 11L, round(100 * n_30d  / n_denom, 1), NA_real_),
    pct_90d       = ifelse(n_denom >= 11L, round(100 * n_90d  / n_denom, 1), NA_real_),
    # Suppress patient counts < 11
    n_denom_disp       = sup_col(n_denom),
    n_exact_disp       = sup_col(n_exact),
    n_30d_disp         = sup_col(n_30d),
    n_90d_disp         = sup_col(n_90d),
    n_not_captured_disp = sup_col(n_not_captured)
  )

sheet_A <- sensitivity_raw |>
  select(
    `Treatment Type`     = treatment_label,
    `TR n (denominator)` = n_denom_disp,
    `Exact match n`      = n_exact_disp,
    `Exact match %`      = pct_exact,
    `Within 30d n`       = n_30d_disp,
    `Within 30d %`       = pct_30d,
    `Within 90d n`       = n_90d_disp,
    `Within 90d %`       = pct_90d,
    `Not captured n`     = n_not_captured_disp
  )
message(glue("  A_sensitivity: {nrow(sheet_A)} rows"))

# --- SECTION 8: B_DATE_DIFF TABLE -------------------------------------------
message("=== Section 8: B_date_diff ===")

tiers <- c("exact", "within_30d", "within_90d", "not_captured")
tier_labels <- c("Exact match", "Within 30d", "Within 90d", "Not captured")

sheet_B_main <- classified |>
  filter(capture_tier != "no_registry") |>
  group_by(treatment_label, capture_tier) |>
  summarise(n = n(), .groups = "drop") |>
  mutate(
    tier_label = factor(capture_tier, levels = tiers, labels = tier_labels),
    n_disp     = sup_col(n)
  ) |>
  select(
    `Treatment Type` = treatment_label,
    `Capture Tier`   = tier_label,
    `Count`          = n_disp
  ) |>
  arrange(`Treatment Type`, `Capture Tier`)

# Footnote row: TR-HL patients not in pipeline (D-201-04; not in denominator)
footnote_row <- tibble(
  `Treatment Type` = "(footnote) TR-HL patients not in confirmed cohort (excluded from denominator)",
  `Capture Tier`   = "N/A",
  `Count`          = as.character(n_footnote)   # 121 — not patient-level, so no suppression needed
)

sheet_B <- bind_rows(sheet_B_main, footnote_row)
message(glue("  B_date_diff: {nrow(sheet_B)} rows (including footnote row)"))

# --- SECTION 9: C_BY_SOURCE TABLE -------------------------------------------
message("=== Section 9: C_by_source ===")

sheet_C <- classified |>
  filter(capture_tier != "no_registry") |>
  group_by(SOURCE, treatment_label) |>
  summarise(
    n_denom    = n(),
    n_captured = sum(capture_tier %in% c("exact", "within_30d", "within_90d")),
    .groups    = "drop"
  ) |>
  mutate(
    pct_captured    = ifelse(n_denom >= 11L, round(100 * n_captured / n_denom, 1), NA_real_),
    n_denom_disp    = sup_col(n_denom),
    n_captured_disp = sup_col(n_captured)
  ) |>
  select(
    `SOURCE (partner site)` = SOURCE,
    `Treatment Type`        = treatment_label,
    `TR n`                  = n_denom_disp,
    `Pipeline captured n`   = n_captured_disp,
    `Sensitivity %`         = pct_captured
  ) |>
  arrange(`SOURCE (partner site)`, `Treatment Type`)
message(glue("  C_by_source: {nrow(sheet_C)} rows"))

# --- SECTION 10: D_BY_YEAR TABLE --------------------------------------------
# first_hl_dx_date read from confirmed_hl_cohort.rds via cohort_rds_path
# (env var R202_COHORT_RDS, pinned in the scaffold section above).
message("=== Section 10: D_by_year ===")

cohort_dx <- readRDS(cohort_rds_path) |>
  select(ID, first_hl_dx_date) |>
  mutate(dx_year = year(first_hl_dx_date))
message(glue("  cohort_dx: {nrow(cohort_dx)} patients with dx year"))

classified_yr <- classified |>
  left_join(cohort_dx, by = c("patient_id" = "ID"))

# Year grouping: define early / late split at median dx_year
yr_median <- median(classified_yr$dx_year, na.rm = TRUE)
message(glue("  Median diagnosis year: {yr_median}"))

classified_yr <- classified_yr |>
  mutate(dx_year_group = ifelse(
    is.na(dx_year), "Unknown",
    ifelse(dx_year <= yr_median, glue("Early (≤{yr_median})"), glue("Late (>{yr_median})"))
  ))

sheet_D <- classified_yr |>
  filter(capture_tier != "no_registry") |>
  group_by(dx_year_group, treatment_label) |>
  summarise(
    n_denom    = n(),
    n_captured = sum(capture_tier %in% c("exact", "within_30d", "within_90d")),
    .groups    = "drop"
  ) |>
  mutate(
    pct_captured    = ifelse(n_denom >= 11L, round(100 * n_captured / n_denom, 1), NA_real_),
    n_denom_disp    = sup_col(n_denom),
    n_captured_disp = sup_col(n_captured)
  ) |>
  select(
    `Dx Year Group`       = dx_year_group,
    `Treatment Type`      = treatment_label,
    `TR n`                = n_denom_disp,
    `Pipeline captured n` = n_captured_disp,
    `Sensitivity %`       = pct_captured
  ) |>
  arrange(`Dx Year Group`, `Treatment Type`)
message(glue("  D_by_year: {nrow(sheet_D)} rows"))

# --- SECTION 11: PPV_REVERSE SHEET ------------------------------------------
# For each pipeline treatment type: what fraction of pipeline-captured episodes
# have a matching registry record of that type?
# Denominator = distinct patients in gantt with that treatment_type.
# Numerator   = those patients who also have a TR flag for that type (tr_date non-NA).
message("=== Section 11: PPV_reverse ===")

gantt_pts_treated <- gantt |>
  filter(patient_id %in% pop_denom$patient_id,
         treatment_type %in% c("Chemotherapy", "Radiation", "Immunotherapy",
                               "Stem Cell Transplant")) |>
  distinct(patient_id, treatment_type)

ppv_raw <- gantt_pts_treated |>
  left_join(
    classified |> select(patient_id, treatment_label, capture_tier),
    by = c("patient_id", "treatment_type" = "treatment_label")
  ) |>
  group_by(treatment_type) |>
  summarise(
    n_pipeline = n(),
    n_in_registry = sum(!is.na(capture_tier) & capture_tier != "no_registry", na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(
    ppv_pct         = ifelse(n_pipeline >= 11L, round(100 * n_in_registry / n_pipeline, 1), NA_real_),
    n_pipeline_disp = sup_col(n_pipeline),
    n_in_reg_disp   = sup_col(n_in_registry)
  )

sheet_PPV <- ppv_raw |>
  select(
    `Treatment Type (Pipeline)`  = treatment_type,
    `Pipeline captured n`        = n_pipeline_disp,
    `With matching registry n`   = n_in_reg_disp,
    `Registry agreement % (PPV)` = ppv_pct
  )
message(glue("  PPV_reverse: {nrow(sheet_PPV)} rows"))

# --- SECTION 12: QC SHEET ---------------------------------------------------
message("=== Section 12: QC sheet ===")
run_dt <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
sheet_QC <- tibble(
  Item  = c(
    "Run timestamp",
    "gantt_180_path",
    "tr_flags_path",
    "cohort_rds_path",
    "Gantt patients (all treatment types)",
    "TR-HL patients (all in extract)",
    "Denominator (in gantt AND TR-HL)",
    "Footnote (TR-HL not in gantt)",
    "TR chemo columns found",
    "TR radiation columns found",
    "TR immunotherapy columns found (PENDING-PROBE if 0)",
    "TR SCT code column found",
    "TR SCT date columns found",
    "Suppression check: any raw count 1-10 in sheet_A"
  ),
  Value = c(
    run_dt,
    gantt_180_path,
    tr_flags_path,
    cohort_rds_path,
    as.character(n_gantt_pts),
    as.character(n_tr_hl_all),
    as.character(n_denom),
    as.character(n_footnote),
    paste(tr_chemo_present,  collapse = ", "),
    paste(tr_rad_present,    collapse = ", "),
    paste(tr_immuno_present, collapse = ", "),
    as.character(tr_sct_code_pres),
    paste(tr_sct_date_pres,  collapse = ", "),
    as.character(any(
      sensitivity_raw$n_denom   %in% 1:10 |
      sensitivity_raw$n_exact   %in% 1:10 |
      sensitivity_raw$n_90d     %in% 1:10
    ))
  )
)

# --- SECTION 13: KEY SHEET --------------------------------------------------
sheet_KEY <- tibble(
  Item = c(
    "Script", "Phase", "Run date",
    "Input: gantt_episodes_180", "Input: tr_flags (R/193 output)",
    "Input: confirmed_hl_cohort.rds",
    "Denominator",
    "Footnote (not in denominator)",
    "Sheet A_sensitivity", "Sheet B_date_diff",
    "Sheet C_by_source", "Sheet D_by_year",
    "Sheet PPV_reverse",
    "Suppression rule"
  ),
  Value = c(
    "R/202_tr_sensitivity.R",
    "202 — Tumor-Registry Treatment Sensitivity",
    format(Sys.Date(), "%Y-%m-%d"),
    gantt_180_path,
    tr_flags_path,
    cohort_rds_path,
    glue("{n_denom} TR-HL patients present in gantt_episodes_180"),
    glue("{n_footnote} TR-HL patients outside confirmed cohort (D-201-04); excluded from sensitivity denominator"),
    "% of TR-flagged treatments captured by pipeline, by treatment type",
    "Counts at exact/+/-30d/+/-90d/not-captured tiers; footnote row for excluded patients",
    "Sensitivity stratified by SOURCE (partner site)",
    "Sensitivity stratified by diagnosis year group",
    "For pipeline captures, fraction with matching registry record (PPV direction)",
    "Patient counts 1-10 displayed as '<11'"
  )
)

# --- SECTION 14: WRITE XLSX -------------------------------------------------
message("=== Section 14: Write xlsx ===")
out_date  <- format(Sys.Date(), "%Y%m%d")
out_fname <- glue("202_tr_sensitivity_{out_date}.xlsx")
out_path  <- file.path(output_dir, out_fname)

uf_blue   <- "#0021A5"
uf_orange <- "#FA4616"

wb <- createWorkbook()
header_style <- createStyle(
  fontColour = "#FFFFFF",
  fgFill     = uf_blue,
  textDecoration = "bold",
  halign     = "left"
)

write_sheet <- function(wb, name, df) {
  addWorksheet(wb, name)
  writeData(wb, name, df, headerStyle = header_style)
  setColWidths(wb, name, cols = seq_len(ncol(df)), widths = "auto")
}

# KEY leftmost — added first
write_sheet(wb, "KEY",           sheet_KEY)
write_sheet(wb, "A_sensitivity", sheet_A)
write_sheet(wb, "B_date_diff",   sheet_B)
write_sheet(wb, "C_by_source",   sheet_C)
write_sheet(wb, "D_by_year",     sheet_D)
write_sheet(wb, "PPV_reverse",   sheet_PPV)
write_sheet(wb, "QC",            sheet_QC)

# Apply orange accent to KEY sheet label row (row 1 background)
addStyle(wb, "KEY", createStyle(fgFill = uf_orange, fontColour = "#FFFFFF",
                                 textDecoration = "bold"),
         rows = 1, cols = seq_len(ncol(sheet_KEY)), stack = FALSE)

saveWorkbook(wb, out_path, overwrite = TRUE)
message(glue("\n  Output written: {out_path}"))
message(glue("  Sheets: KEY, A_sensitivity, B_date_diff, C_by_source, D_by_year, PPV_reverse, QC"))
message("\n=== R/202 complete ===")
