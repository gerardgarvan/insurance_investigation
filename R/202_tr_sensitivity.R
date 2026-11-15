# ==============================================================================
# 202_tr_sensitivity.R
# ==============================================================================
#
# Purpose:
#   Tumor-registry treatment sensitivity analysis.
#   Compares registry first-course treatment fields against Gantt pipeline
#   capture for TR-HL patients in gantt_episodes_180 (denominator approx 600).
#   Reports sensitivity by treatment type, SOURCE (UFH/ORL/TMH), and diagnosis year;
#   reverse (PPV-direction) agreement; date-difference distribution.
#   The 121 TR-HL patients outside confirmed_hl_cohort.rds are reported as
#   a footnote row, not in the sensitivity denominator.
#
# Inputs (all pinned):
#   - R202_GANTT_180      gantt_episodes_180 CSV (default output/gantt_episodes_180.csv)
#   - R202_TR_FLAGS       tr_lymphoma_flags_all_patients .csv or .rds from R/193
#                         (default: newest output/tr_lymphoma_flags_all_patients_*.csv)
#   - R202_COHORT_RDS     confirmed_hl_cohort.rds (used in Section 10 D_by_year)
#   - R202_TR_DATA        TUMOR_REGISTRY_ALL treatment columns (queried live)
#   - R202_OUTPUT_DIR     output directory (default: output/)
#
# Outputs:
#   - output/202_tr_sensitivity_YYYYMMDD.xlsx
#       Sheets: KEY, A_sensitivity, B_date_diff, C_by_source, D_by_year,
#       E_coverage_window, PPV_reverse, QC
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
source("R/utils/utils_tr_sensitivity.R")
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
  if (ev != "") ev else file.path(CONFIG$output_dir, "gantt_episodes_180.csv")
}
if (is.null(gantt_180_path) || gantt_180_path == "" || !file.exists(gantt_180_path)) {
  stop(glue("R202: gantt_180 not found at '{gantt_180_path}'. ",
            "Set R202_GANTT_180 to the gantt_episodes_180 CSV."))
}

# TR flags: env var wins; otherwise newest dated CSV from R/193 in output/.
# (Newest-file default requested by the user for this input, 2026-11-14.)
tr_flags_path <- {
  ev <- Sys.getenv("R202_TR_FLAGS", unset = "")
  if (ev != "") ev else {
    cands <- list.files(CONFIG$output_dir,
                        pattern = "^tr_lymphoma_flags_all_patients_.*[.]csv$",
                        full.names = TRUE)
    if (length(cands) == 0L) "" else sort(cands, decreasing = TRUE)[1L]  # YYYYMMDD in name
  }
}
if (tr_flags_path == "" || !file.exists(tr_flags_path))
  stop("[R202] TR flags file not found: '", tr_flags_path,
       "'
Set R202_TR_FLAGS to the R/193 tr_lymphoma_flags_all_patients .csv or .rds path.")

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

# --- TR COLUMN MAP -----------------------------------------------------------
# TR_MAP, CODE_UNKNOWN, SCT_GIVEN, tr_map_row() and TR_HIST_COLS moved to
# R/utils/utils_cancer.R (shared with R/203). Probe:
# .planning/schemas/202_schema_tr_treatment_cols_20261114.md

# Treatment type -> label and Gantt treatment_type. systemic has no Gantt
# counterpart (descriptive counts only). "Hormone" is an UNCONFIRMED Gantt label:
# it is checked against gantt$treatment_type at run time (Section 5).
TYPE_DEF <- tibble(
  trtype     = c("chemo", "radiation", "immuno", "sct", "hormone", "systemic"),
  label      = c("Chemotherapy", "Radiation", "Immunotherapy",
                 "Stem Cell Transplant", "Hormone", "Systemic therapy"),
  gantt_type = c("Chemotherapy", "Radiation", "Immunotherapy",
                 "Stem Cell Transplant", "Hormone", NA_character_)
)

# Type/source pairs with a TR date column: only these get B_date_diff rows.
# Transplant is code-only (no date anywhere), so it has no B row.
B_PAIRS <- tibble(
  source = c("UFH", "ORL", "ORL", "UFH", "UFH", "ORL"),
  trtype = c("chemo", "chemo", "radiation", "immuno", "hormone", "hormone")
)
stopifnot(nrow(semi_join(TR_MAP |> filter(!is.na(date_col)), B_PAIRS,
                         by = c("source", "trtype"))) == nrow(B_PAIRS))

# Sources with sensitivity computed (TMH reported as counts only)
SENS_SOURCES <- c("UFH", "ORL")

# Reference values shown as percentages only when numerator and denominator >= 11
pct_sup <- function(num, den) ifelse(num >= 11L & den >= 11L, round(100 * num / den, 1), NA_real_)

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
  distinct(patient_id, tr_hl_dx, tr_nhl_dx) |>
  # tr_hl_dx/tr_nhl_dx are constant within patient_id (checked by R/88 Phase 201)
  group_by(patient_id) |>
  slice(1L) |>
  ungroup()

n_gantt_pts <- n_distinct(gantt$patient_id)
message(glue("  gantt_episodes_180: {nrow(gantt)} rows, {n_gantt_pts} distinct patients"))

# --- SECTION 2: LOAD TR FLAGS ------------------------------------------------
message("=== Section 2: Load TR flags (R/193 output) ===")
tr_flags <- if (grepl("\\.rds$", tr_flags_path, ignore.case = TRUE)) {
  readRDS(tr_flags_path)
} else {
  vroom(tr_flags_path, col_types = cols(.default = col_character()), show_col_types = FALSE)
}
# CSV carries blank / "TRUE" / "FALSE"; make the flags logical (no-op for RDS)
tr_flags <- tr_flags |>
  mutate(ID = as.character(ID),
         tr_hl_dx  = tr_flag_to_logical(tr_hl_dx),
         tr_nhl_dx = tr_flag_to_logical(tr_nhl_dx))
n_tr_hl_all <- sum(tr_flags$tr_hl_dx == TRUE, na.rm = TRUE)
message(glue("  TR flags: {nrow(tr_flags)} patients; {n_tr_hl_all} with tr_hl_dx TRUE"))

# --- SECTION 3: LOAD TR TREATMENT COLUMNS, RESTRICT TO HL ROWS --------------
# Collect only columns needed (avoid loading the full 483-column table).
message("=== Section 3: Load TR treatment columns from TUMOR_REGISTRY_ALL ===")
open_pcornet_con()
tr_tbl_raw <- get_pcornet_table("TUMOR_REGISTRY_ALL")
tr_all_cols <- colnames(tr_tbl_raw)

map_cols <- unique(na.omit(c(TR_MAP$date_col, TR_MAP$code_col)))
missing_map_cols <- setdiff(map_cols, tr_all_cols)
if (length(missing_map_cols) > 0L) {
  close_pcornet_con()
  stop("[R202] TR_MAP columns not in TUMOR_REGISTRY_ALL: ",
       paste(missing_map_cols, collapse = ", "),
       "\nAvailable columns matching DT_|CODE|R_N_|SUM: ",
       paste(grep("^DT_|CODE|^R_N_|SUM", tr_all_cols, value = TRUE), collapse = ", "))
}
hist_present <- intersect(TR_HIST_COLS, tr_all_cols)
if (!"SOURCE" %in% tr_all_cols || length(hist_present) == 0L) {
  close_pcornet_con()
  stop("[R202] SOURCE or histology column (", paste(TR_HIST_COLS, collapse = "/"),
       ") missing from TUMOR_REGISTRY_ALL")
}

# TR diagnosis-date columns for the D_by_year fallback (named in the task spec; not
# in the 202 probe, so they are used only if present in the table).
TR_DX_DATE_COLS <- c(UFH = "DATE_OF_DIAGNOSIS", ORL = "DXDATE", TMH = "DXDATE")
dx_cols_present <- intersect(unique(TR_DX_DATE_COLS), tr_all_cols)
message("  TR dx-date columns present: ",
        if (length(dx_cols_present)) paste(dx_cols_present, collapse = ", ") else "NONE (no TR dx-year fallback)")

needed_cols <- unique(c("ID", "SOURCE", hist_present, map_cols, dx_cols_present))
tr_data <- tr_tbl_raw |>
  select(all_of(needed_cols)) |>
  collect()
close_pcornet_con()

tr_hl <- tr_data |>
  filter(if_any(all_of(hist_present),
                ~ substr(as.character(.x), 1, 4) %in% !!ICD_CODES$hl_histology))
n_tr_rows    <- nrow(tr_data)
n_tr_hl_rows <- nrow(tr_hl)
n_tmh_rows   <- sum(tr_hl$SOURCE == "TMH")
message(glue("  TUMOR_REGISTRY_ALL: {n_tr_rows} rows; {n_tr_hl_rows} HL-histology rows ",
             "({n_distinct(tr_hl$ID)} patients); columns pulled: {length(needed_cols)}"))
message("  HL rows by SOURCE: ",
        paste(names(table(tr_hl$SOURCE)), as.integer(table(tr_hl$SOURCE)), collapse = "; "))

# --- SECTION 3b: PATIENT-LEVEL COLLAPSE --------------------------------------
# TR_MAP, tr_row_evidence() and collapse_evidence() now live in
# R/utils/utils_cancer.R (shared with R/203) via build_tr_treatment_flags().
# Per patient: tr_given = any HL row given; tr_first_date = earliest non-missing
# date across HL rows; unknown (and not given) is "unknown", not "not_given".
tr_pt_src <- build_tr_treatment_flags(sources = unique(TR_MAP$source), by_source = TRUE,
                                      tr_hl = tr_hl)                    # per source (C, B)
tr_pt_all <- build_tr_treatment_flags(sources = SENS_SOURCES, tr_hl = tr_hl)  # UFH+ORL (A, D, PPV)
# Earliest TR diagnosis year per patient (HL rows; UFH DATE_OF_DIAGNOSIS, ORL/TMH DXDATE)
tr_dx_year <- bind_rows(lapply(names(TR_DX_DATE_COLS), function(src) {
  col <- TR_DX_DATE_COLS[[src]]
  if (!col %in% names(tr_hl)) return(tibble(ID = character(), dx_year_tr = integer()))
  tr_hl |>
    filter(SOURCE == src) |>
    rename(dx_raw = all_of(col)) |>
    transmute(ID = as.character(ID),
              dx_year_tr = year(suppressWarnings(as.Date(substr(as.character(dx_raw), 1, 10)))))
})) |>
  filter(!is.na(dx_year_tr)) |>
  group_by(ID) |>
  summarise(dx_year_tr = min(dx_year_tr), .groups = "drop")

message(glue("  tr_pt_src: {nrow(tr_pt_src)} patient x source x type rows; ",
             "tr_pt_all: {nrow(tr_pt_all)} patient x type rows"))

# --- SECTION 4: BUILD POPULATIONS -------------------------------------------
# pop_denom   = TR-HL patients who ARE in gantt_episodes_180 (sensitivity denominator)
# pop_footnote = TR-HL patients NOT in gantt_episodes_180 (D-201-04; footnote only)
message("=== Section 4: Build denominator and footnote populations ===")

tr_hl_ids <- tr_flags |>
  filter(tr_hl_dx == TRUE) |>
  pull(ID)

gantt_pt_ids <- gantt_pts$patient_id

pop_denom <- gantt_pts |>
  filter(patient_id %in% tr_hl_ids)
denom_ids <- pop_denom$patient_id

pop_footnote_ids <- setdiff(tr_hl_ids, gantt_pt_ids)

n_denom    <- nrow(pop_denom)
n_footnote <- length(pop_footnote_ids)
message(glue("  Denominator (in gantt + TR-HL): {n_denom} patients (expected approx 600)"))
message(glue("  Footnote (TR-HL not in gantt):  {n_footnote} patients (expected 121)"))

if (n_denom < 500L || n_denom > 700L)
  warning(glue("R202: denominator {n_denom} outside expected 500-700 range — verify inputs"))
if (n_footnote < 100L || n_footnote > 150L)
  warning(glue("R202: footnote count {n_footnote} outside expected 100-150 range — verify inputs"))

# --- SECTION 5: GANTT FIRST-EPISODE DATES PER PATIENT -----------------------
message("=== Section 5: Gantt first-episode dates per patient x treatment type ===")
gantt_first <- gantt |>
  filter(patient_id %in% denom_ids) |>
  filter(!is.na(episode_start)) |>
  group_by(patient_id, treatment_type) |>
  summarise(gantt_first_date = min(episode_start, na.rm = TRUE), .groups = "drop")
message(glue("  gantt_first: {nrow(gantt_first)} patient x type rows"))

# Hormone: Gantt label unconfirmed. If absent, hormone is not compared.
gantt_labels <- sort(unique(gantt$treatment_type))
hormone_comparable <- "Hormone" %in% gantt_labels
if (!hormone_comparable) {
  message("  NOTE: no 'Hormone' treatment_type in gantt; hormone not compared. Labels: ",
          paste(gantt_labels, collapse = ", "))
  TYPE_DEF$gantt_type[TYPE_DEF$trtype == "hormone"] <- NA_character_
}

# --- SECTION 6: CAPTURE CLASSIFICATION --------------------------------------
# Per patient x treatment type (x SOURCE for the source-level table). Tier logic
# lives in R/utils/utils_tr_sensitivity.R (tr_capture_tier; unit-tested):
#   unknown_code  TR code is unknown (88/99/8/9) and no HL row says given
#   no_registry   TR does not record this treatment as given
#   no_pipeline   TR given; no Gantt episode of that type
#   pipe_before   TR given; first Gantt episode > 90 d BEFORE TR date
#   pipe_after    TR given; first Gantt episode > 90 d AFTER TR date
#   not_datable   TR given by code only (no date); Gantt episode exists
#   exact / within_30d / within_90d   |TR first date - Gantt first date|
message("=== Section 6: Capture classification ===")
GIVEN_TIERS <- TR_GIVEN_TIERS
HIT_TIERS   <- TR_HIT_TIERS

L_NOPIPE <- "No pipeline record of this type"
L_BEFORE <- "Pipeline record > 90d BEFORE TR date"
L_AFTER  <- "Pipeline record > 90d AFTER TR date"

classify_capture <- function(tr_pt, gantt_first_df, ids) {
  tr_pt |>
    filter(ID %in% ids) |>
    inner_join(filter(TYPE_DEF, !is.na(gantt_type)), by = "trtype") |>
    left_join(gantt_first_df, by = c("ID" = "patient_id", "gantt_type" = "treatment_type")) |>
    mutate(
      signed_diff  = tr_signed_diff(tr_first_date, gantt_first_date),
      capture_tier = tr_capture_tier(tr_status, tr_first_date, gantt_first_date),
      treatment_label = label
    )
}

# Group + summarise tiers (raw counts, median/IQR text), then add display columns.
summ_by <- function(df, ...) {
  df |>
    group_by(...) |>
    group_modify(~ tr_summarise_tiers(.x)) |>
    ungroup()
}
tier_display <- function(raw) {
  raw |>
    mutate(
      pct_exact = pct_sup(n_exact, n_denom),
      pct_30d   = pct_sup(n_30d,   n_denom),
      pct_90d   = pct_sup(n_90d,   n_denom),
      n_captured_incl_undated = n_90d + n_undated
    )
}

classified     <- classify_capture(tr_pt_all, gantt_first, denom_ids)
classified_src <- classify_capture(filter(tr_pt_src, SOURCE %in% SENS_SOURCES),
                                   gantt_first, denom_ids)
message(glue("  classified: {nrow(classified)} patient x type rows; ",
             "classified_src: {nrow(classified_src)} patient x source x type rows"))

# --- SECTION 7: A_SENSITIVITY TABLE -----------------------------------------
message("=== Section 7: A_sensitivity ===")

# Denominator per type = patients with TR evidence of treatment (given).
# Unknown-code patients are reported separately, not in the denominator.
# Exact / <=30d / <=90d are CUMULATIVE tiers; the not-captured tiers are exclusive.
sensitivity_raw <- classified |>
  summ_by(treatment_label) |>
  left_join(
    classified |> filter(capture_tier == "unknown_code") |> count(treatment_label, name = "n_unknown"),
    by = "treatment_label"
  ) |>
  mutate(n_unknown = coalesce(n_unknown, 0L)) |>
  tier_display()

sheet_A <- sensitivity_raw |>
  transmute(
    `Treatment Type`     = treatment_label,
    `TR n (denominator)` = sup_col(n_denom),
    `Exact match n`      = sup_col(n_exact),
    `Exact match %`      = pct_exact,
    `≤30d (incl. exact) n` = sup_col(n_30d),
    `≤30d (incl. exact) %` = pct_30d,
    `≤90d (incl. ≤30d) n`  = sup_col(n_90d),
    `≤90d (incl. ≤30d) %`  = pct_90d,
    `Captured, TR undated n` = sup_col(n_undated),
    `No pipeline record of this type n`          = sup_col(n_no_pipe),
    `Pipeline record > 90d BEFORE TR date n`     = sup_col(n_before),
    `Pipeline record > 90d BEFORE TR date, median (IQR) days` = med_before,
    `Pipeline record > 90d AFTER TR date n`      = sup_col(n_after),
    `Pipeline record > 90d AFTER TR date, median (IQR) days`  = med_after,
    `TR unknown code n (not in denominator)` = sup_col(n_unknown)
  )
message(glue("  A_sensitivity: {nrow(sheet_A)} rows"))

# --- SECTION 8: B_DATE_DIFF TABLE -------------------------------------------
# Only type/source pairs that have a TR date column (B_PAIRS); only TR-dated rows.
# Tiers here are MUTUALLY EXCLUSIVE (each patient in exactly one row).
message("=== Section 8: B_date_diff ===")

tiers <- c("exact", "within_30d", "within_90d", "pipe_before", "pipe_after", "no_pipeline")
tier_labels <- c("Exact match", "Within 30d", "Within 90d", L_BEFORE, L_AFTER, L_NOPIPE)

b_dated <- classified_src |>
  semi_join(B_PAIRS, by = c("SOURCE" = "source", "trtype")) |>
  filter(capture_tier %in% GIVEN_TIERS, !is.na(tr_first_date))

sheet_B_main <- b_dated |>
  group_by(SOURCE, treatment_label, capture_tier) |>
  summarise(
    n = n(),
    med = if (first(capture_tier) %in% c("pipe_before", "pipe_after"))
            tr_median_iqr(signed_diff) else NA_character_,
    .groups = "drop"
  ) |>
  mutate(tier_label = factor(capture_tier, levels = tiers, labels = tier_labels)) |>
  transmute(
    `SOURCE`         = SOURCE,
    `Treatment Type` = treatment_label,
    `Capture Tier`   = tier_label,
    `Count`          = sup_col(n),
    `Median (IQR) days, |TR date - first pipeline date|` = med
  ) |>
  arrange(`SOURCE`, `Treatment Type`, `Capture Tier`)

footnote_rows <- tibble(
  `SOURCE`         = "N/A",
  `Treatment Type` = c("(footnote) TR-HL patients not in confirmed cohort (excluded from denominator)",
                       "(footnote) Stem Cell Transplant is code-only; no TR date, so no date-difference row"),
  `Capture Tier`   = "N/A",
  `Count`          = c(fmt_sup(n_footnote), "N/A")
)
if (!hormone_comparable) {
  footnote_rows <- bind_rows(footnote_rows, tibble(
    `SOURCE` = "N/A",
    `Treatment Type` = "(footnote) Hormone not compared: no 'Hormone' treatment_type in gantt_episodes_180",
    `Capture Tier` = "N/A", `Count` = "N/A"))
}

sheet_B <- bind_rows(sheet_B_main, footnote_rows)
message(glue("  B_date_diff: {nrow(sheet_B)} rows (including footnote rows)"))

# --- SECTION 9: C_BY_SOURCE TABLE -------------------------------------------
# All sources incl. TMH (counts only). Sensitivity for UFH/ORL only.
# "Pipeline captured n" = dated hits + code-only (TR undated) matches, the same
# way A_sensitivity reports "Captured, TR undated n". Sensitivity % = dated hits
# (<=90d) / TR given, as in A_sensitivity.
message("=== Section 9: C_by_source ===")

c_counts <- tr_pt_src |>
  filter(ID %in% denom_ids) |>
  group_by(SOURCE, trtype) |>
  summarise(
    n_given   = sum(tr_status == "given"),
    n_unknown = sum(tr_status == "unknown"),
    .groups = "drop"
  )
c_sens <- classified_src |>
  summ_by(SOURCE, trtype) |>
  tier_display()

sheet_C_raw <- c_counts |>
  left_join(c_sens, by = c("SOURCE", "trtype")) |>
  left_join(TYPE_DEF |> select(trtype, label), by = "trtype") |>
  mutate(
    note = case_when(
      SOURCE == "TMH"        ~ "TMH: counts only; too few for sensitivity",
      is.na(n_denom)         ~ "no Gantt counterpart / not compared",
      TRUE                   ~ ""
    )
  ) |>
  arrange(SOURCE, label)

c_blank <- function(x, src) ifelse(src == "TMH" | is.na(x), NA_character_, sup_col(x))
sheet_C <- sheet_C_raw |>
  transmute(
    `SOURCE (partner site)` = SOURCE,
    `Treatment Type`        = label,
    `TR given n`            = sup_col(n_given),
    `TR unknown code n`     = sup_col(n_unknown),
    `Pipeline captured n (incl. TR undated)` = c_blank(n_captured_incl_undated, SOURCE),
    `of which TR undated (code-only) n`      = c_blank(n_undated, SOURCE),
    `Sensitivity % (dated, ≤90d)`            = ifelse(SOURCE == "TMH", NA_real_, pct_90d),
    `No pipeline record of this type n`      = c_blank(n_no_pipe, SOURCE),
    `Pipeline record > 90d BEFORE TR date n` = c_blank(n_before, SOURCE),
    `Pipeline record > 90d BEFORE TR date, median (IQR) days` = ifelse(SOURCE == "TMH", NA_character_, med_before),
    `Pipeline record > 90d AFTER TR date n`  = c_blank(n_after, SOURCE),
    `Pipeline record > 90d AFTER TR date, median (IQR) days`  = ifelse(SOURCE == "TMH", NA_character_, med_after),
    Note                    = note
  )
sheet_C <- bind_rows(sheet_C, tibble(
  `SOURCE (partner site)` = "TMH",
  `Treatment Type`        = "(footnote)",
  Note = as.character(glue("n = {fmt_sup(n_tmh_rows)} TR rows; too few for sensitivity"))
))
message(glue("  C_by_source: {nrow(sheet_C)} rows"))

# --- SECTION 10: D_BY_YEAR TABLE --------------------------------------------
# Dx year: first_hl_dx_date from confirmed_hl_cohort.rds (R202_COHORT_RDS); when
# missing, fall back to the year of the TR diagnosis date (tr_dx_year, Section 3b).
message("=== Section 10: D_by_year ===")

cohort_dx <- readRDS(cohort_rds_path) |>
  select(ID, first_hl_dx_date) |>
  mutate(dx_year_cohort = year(first_hl_dx_date)) |>
  select(ID, dx_year_cohort)
message(glue("  cohort_dx: {nrow(cohort_dx)} patients; ",
             "{sum(!is.na(cohort_dx$dx_year_cohort))} with dx year"))

classified_yr <- classified |>
  left_join(cohort_dx, by = "ID") |>
  left_join(tr_dx_year, by = "ID") |>
  mutate(
    dx_year = coalesce(dx_year_cohort, dx_year_tr),
    dx_year_group = tr_year_band(dx_year)
  )
message(glue("  dx year source (patient x type rows): cohort {sum(!is.na(classified_yr$dx_year_cohort))}; ",
             "TR fallback {sum(is.na(classified_yr$dx_year_cohort) & !is.na(classified_yr$dx_year_tr))}; ",
             "still unknown {sum(is.na(classified_yr$dx_year))}"))

sheet_D <- classified_yr |>
  summ_by(dx_year_group, treatment_label) |>
  filter(n_denom > 0L) |>
  tier_display() |>
  transmute(
    `Dx Year Group`       = as.character(dx_year_group),
    `Treatment Type`      = treatment_label,
    `TR n`                = sup_col(n_denom),
    `Pipeline captured n (≤90d)` = sup_col(n_90d),
    `Sensitivity %`       = pct_90d,
    `Captured, TR undated n` = sup_col(n_undated),
    `No pipeline record of this type n`      = sup_col(n_no_pipe),
    `Pipeline record > 90d BEFORE TR date n` = sup_col(n_before),
    `Pipeline record > 90d BEFORE TR date, median (IQR) days` = med_before,
    `Pipeline record > 90d AFTER TR date n`  = sup_col(n_after),
    `Pipeline record > 90d AFTER TR date, median (IQR) days`  = med_after
  ) |>
  arrange(factor(`Dx Year Group`, levels = c(TR_YEAR_BANDS, "Unknown")), `Treatment Type`)
message(glue("  D_by_year: {nrow(sheet_D)} rows"))

# --- SECTION 10b: E_COVERAGE_WINDOW -----------------------------------------
# Restrict to TR treatment dates on/after the patient's first ENCOUNTER.ADMIT_DATE
# in the CDM (EHR coverage window). One row per patient: min(ADMIT_DATE).
# Aggregated in DuckDB; no patient-ID IN() list. Own open/close block.
message("=== Section 10b: E_coverage_window ===")
open_pcornet_con()
first_enc <- get_pcornet_table("ENCOUNTER") |>
  filter(ADMIT_DATE >= !!ENC_DATE_SENTINEL_BEFORE) |>   # drop sentinel dates (e.g. 1901-01-01)
  group_by(ID) |>
  summarise(first_enc_date = min(ADMIT_DATE, na.rm = TRUE)) |>
  collect()
close_pcornet_con()
first_enc <- first_enc |>
  mutate(ID = as.character(ID), first_enc_date = as.Date(first_enc_date))
message(glue("  first encounter: {nrow(first_enc)} patients; ",
             "{sum(!is.na(first_enc$first_enc_date))} with ADMIT_DATE"))

e_raw <- bind_rows(lapply(unique(classified$treatment_label), function(lbl) {
  cf <- tr_coverage_filter(filter(classified, treatment_label == lbl), first_enc)
  summ_by(cf$in_window, treatment_label) |>
    tier_display() |>
    mutate(treatment_label = lbl,
           n_pre_enc = cf$n_excluded_pre_encounter, n_no_enc = cf$n_no_encounter)
}))

sheet_E <- e_raw |>
  transmute(
    `Treatment Type`      = treatment_label,
    `TR n in window`      = sup_col(n_denom),
    `Captured within 90d n` = sup_col(n_90d),
    `Sensitivity % (within 90d)` = pct_90d,
    `Captured, TR undated n` = sup_col(n_undated),
    `No pipeline record of this type n`      = sup_col(n_no_pipe),
    `Pipeline record > 90d BEFORE TR date n` = sup_col(n_before),
    `Pipeline record > 90d BEFORE TR date, median (IQR) days` = med_before,
    `Pipeline record > 90d AFTER TR date n`  = sup_col(n_after),
    `Pipeline record > 90d AFTER TR date, median (IQR) days`  = med_after,
    `TR-dated patients excluded: TR date before first encounter n` = sup_col(n_pre_enc),
    `TR-dated patients excluded: no ENCOUNTER record n`            = sup_col(n_no_enc)
  ) |>
  arrange(`Treatment Type`)
message(glue("  E_coverage_window: {nrow(sheet_E)} rows"))

# --- SECTION 11: PPV_REVERSE SHEET ------------------------------------------
# For each pipeline treatment type: what fraction of pipeline-captured patients
# have a matching registry record (TR given, UFH/ORL) of that type?
message("=== Section 11: PPV_reverse ===")

gantt_pts_treated <- gantt |>
  filter(patient_id %in% denom_ids,
         treatment_type %in% c("Chemotherapy", "Radiation", "Immunotherapy",
                               "Stem Cell Transplant")) |>
  distinct(patient_id, treatment_type)

ppv_raw <- gantt_pts_treated |>
  left_join(
    classified |> select(ID, treatment_label, capture_tier),
    by = c("patient_id" = "ID", "treatment_type" = "treatment_label")
  ) |>
  group_by(treatment_type) |>
  summarise(
    n_pipeline    = n(),
    n_in_registry = sum(capture_tier %in% GIVEN_TIERS, na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(
    ppv_pct         = pct_sup(n_in_registry, n_pipeline),
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

# ORL chemo disagreement: DT_CHEMO present vs R_N_CHEMO == 0 (HL rows, row-level counts)
orl_chemo_cross <- tr_hl |>
  filter(SOURCE == "ORL") |>
  transmute(
    dt_chemo = ifelse(!is.na(as.Date(DT_CHEMO)), "DT_CHEMO present", "DT_CHEMO missing"),
    rn = {
      v <- suppressWarnings(as.integer(as.character(R_N_CHEMO)))
      case_when(is.na(v) ~ "R_N_CHEMO missing", v == 0L ~ "R_N_CHEMO = 0 (given)",
                TRUE ~ "R_N_CHEMO other code")
    }
  ) |>
  count(dt_chemo, rn, name = "n")
orl_chemo_grid <- expand.grid(
  dt_chemo = c("DT_CHEMO present", "DT_CHEMO missing"),
  rn = c("R_N_CHEMO = 0 (given)", "R_N_CHEMO other code", "R_N_CHEMO missing"),
  stringsAsFactors = FALSE
) |>
  left_join(orl_chemo_cross, by = c("dt_chemo", "rn")) |>
  mutate(n = coalesce(n, 0L))

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
    "TUMOR_REGISTRY_ALL rows / HL-histology rows",
    "HL rows: UFH / ORL / TMH",
    "TR_MAP columns verified present",
    "Histology columns used",
    "Hormone compared to Gantt (label 'Hormone' present)",
    "Raw counts 1-10 present before suppression (all displayed as <11)",
    "First-encounter dates (ENCOUNTER, patients with ADMIT_DATE)",
    paste0("ORL chemo (HL rows): ", orl_chemo_grid$dt_chemo, " x ", orl_chemo_grid$rn)
  ),
  Value = c(
    run_dt,
    gantt_180_path,
    tr_flags_path,
    cohort_rds_path,
    as.character(n_gantt_pts),
    as.character(n_tr_hl_all),
    as.character(n_denom),
    fmt_sup(n_footnote),
    paste(fmt_sup(n_tr_rows), "/", fmt_sup(n_tr_hl_rows)),
    paste(vapply(c("UFH", "ORL", "TMH"), function(s) fmt_sup(sum(tr_hl$SOURCE == s)), character(1)),
          collapse = " / "),
    paste(map_cols, collapse = ", "),
    paste(hist_present, collapse = ", "),
    as.character(hormone_comparable),
    as.character(any(
      unlist(sensitivity_raw[c("n_denom", "n_exact", "n_30d", "n_90d", "n_undated",
                               "n_no_pipe", "n_before", "n_after", "n_unknown")]) %in% 1:10
    )),
    as.character(sum(!is.na(first_enc$first_enc_date))),
    vapply(orl_chemo_grid$n, fmt_sup, character(1))
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
    "Stratification",
    "Patient-level collapse",
    "Code scheme: reason_no (REASON_NO_*, R_N_*)",
    "Code scheme: naaccr_rx (NAACCR summary codes)",
    "Code scheme: rx_summ (DRAD_SUM, DBRM_SUM, HTE_SUM)",
    "Meaning of 0 (opposite between schemes)",
    "Unknown codes",
    "Given values",
    "TMH",
    "Transplant (SCT)",
    "Hormone / Systemic",
    "Capture tiers",
    "Sheet A_sensitivity", "Sheet B_date_diff",
    "Sheet C_by_source", "Sheet D_by_year", "Sheet E_coverage_window",
    "Sheet PPV_reverse",
    "Not-captured tiers", "Immunotherapy note", "Radiation note",
    "Suppression rule"
  ),
  Value = c(
    "R/202_tr_sensitivity.R",
    "202 — Tumor-Registry Treatment Sensitivity",
    format(Sys.Date(), "%Y-%m-%d"),
    paste0(gantt_180_path, " (pinned: ", nzchar(Sys.getenv("R202_GANTT_180")), ")"),
    paste0(tr_flags_path, " (pinned: ", nzchar(Sys.getenv("R202_TR_FLAGS")), ")"),
    paste0(cohort_rds_path, " (pinned: ", nzchar(Sys.getenv("R202_COHORT_RDS")), ")"),
    glue("{fmt_sup(n_denom)} TR-HL patients present in gantt_episodes_180"),
    glue("{fmt_sup(n_footnote)} TR-HL patients outside confirmed cohort (D-201-04); excluded from sensitivity denominator"),
    "By TR SOURCE (UFH / ORL / TMH); the table has no TR1/TR2/TR3 split. A/D/PPV pool UFH + ORL.",
    paste0("HL-histology rows only (substr(", paste(hist_present, collapse = "/"),
           ", 1, 4) in ICD_CODES$hl_histology). tr_given = any HL row with a date OR a code in given values; ",
           "tr_first_date = earliest non-missing date across HL rows."),
    "0 = treatment GIVEN. Other codes = reason not given (R_N_CHEMO, R_N_RAD, R_N_HORM, REASON_NO_RADIATION).",
    "00 = none. Given: chemo 01/02/03; immuno 01; hormone 01; SCT 10/11/12/20 (HEMATOLOGIC_TRANSPLANT_AND_ENDOC).",
    "0 = NONE. Given: DBRM_SUM 1; HTE_SUM 10/11/12/20. DRAD_SUM: 0 none, 8/9 unknown (no given value in probe).",
    "reason_no: 0 means given. rx_summ: 0 means none. Do not compare codes across schemes.",
    "reason_no 8/9; naaccr_rx 88/99; rx_summ 8/9/88/99. Counted 'unknown', not 'not given'; shown separately, outside the denominator.",
    "Date present OR given code. UFH chemo CHEMO_CODE_SUMMARY, ORL chemo R_N_CHEMO; see TR_MAP in script.",
    glue("n = {fmt_sup(n_tmh_rows)} TR rows; counts only in C_by_source, no sensitivity"),
    "Code-only (no TR date in any source). Shown in A_sensitivity; no date-difference row in B_date_diff.",
    "Hormone compared to Gantt only if a 'Hormone' treatment_type exists (QC row). Systemic: descriptive counts only (C_by_source).",
    paste0("exact / within 30 d / within 90 d of first Gantt episode; TR given by code only = 'not datable' (Gantt episode exists). ",
           "TR given but not captured is split into three tiers (see 'Not-captured tiers')."),
    "% of TR-given patients captured by pipeline, by treatment type. Tiers are CUMULATIVE: '≤30d (incl. exact)' includes exact matches; '≤90d (incl. ≤30d)' includes both. Not-captured tiers are exclusive.",
    "Date-difference tiers for type/source pairs with a TR date: chemo UFH/ORL, radiation ORL, immuno UFH, hormone UFH/ORL; footnote rows. Tiers are MUTUALLY EXCLUSIVE (each patient in exactly one tier). Median (IQR) days shown for the two date-mismatch tiers (NA if n < 11).",
    "Counts by SOURCE for UFH/ORL/TMH; sensitivity for UFH/ORL only. 'Pipeline captured n' includes code-only (TR undated) matches, as in A_sensitivity; Sensitivity % uses dated hits (≤90d) only.",
    "Sensitivity stratified by diagnosis-year band (<=2009, 2010-2012, 2013-2015, 2016-2018, 2019+). Year from confirmed_hl_cohort.rds first_hl_dx_date; if missing, year of the TR diagnosis date (UFH DATE_OF_DIAGNOSIS, ORL/TMH DXDATE); residual Unknown only if both missing.",
    paste0("Sensitivity restricted to TR treatment dates on/after the patient's first ENCOUNTER.ADMIT_DATE in the CDM (EHR coverage window). ",
           "Registry treatment dated before the first encounter cannot be in the pipeline by construction, so this removes pre-coverage dates. ",
           "TR-undated (code-only) rows cannot be placed against the window and are retained. ",
           "Excluded patients (TR date before first encounter; no ENCOUNTER record) are counted per treatment type. ",
           "First encounter ignores sentinel ADMIT_DATE values before 1990-01-01 (guard added in quick task 261114-r5e); this can shift E counts slightly versus earlier runs."),
    "For pipeline captures, fraction with matching registry record (PPV direction; UFH + ORL)",
    paste0("No pipeline record of this type = TR given, no Gantt episode of that type. ",
           "Pipeline record > 90d BEFORE TR date = first Gantt episode more than 90 d earlier than the TR date. ",
           "Pipeline record > 90d AFTER TR date = first Gantt episode more than 90 d later. Based on the first Gantt episode of the type only."),
    paste0("Registry first-course coding records brentuximab vedotin as chemotherapy, and later-line nivolumab/pembrolizumab are not first course. ",
           "A low immunotherapy agreement (PPV) is a definitional difference, not a pipeline error."),
    "UFH has no TR radiation date: UFH radiation is code-only (REASON_NO_RADIATION), so it appears as 'Captured, TR undated' and never in a date tier.",
    "Counts 1-10 displayed as '<11'; percentages only when numerator and denominator >= 11"
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
write_sheet(wb, "E_coverage_window", sheet_E)
write_sheet(wb, "PPV_reverse",   sheet_PPV)
write_sheet(wb, "QC",            sheet_QC)

# Apply orange accent to KEY sheet label row (row 1 background)
addStyle(wb, "KEY", createStyle(fgFill = uf_orange, fontColour = "#FFFFFF",
                                 textDecoration = "bold"),
         rows = 1, cols = seq_len(ncol(sheet_KEY)), stack = FALSE)

saveWorkbook(wb, out_path, overwrite = TRUE)
message(glue("\n  Output written: {out_path}"))
message(glue("  Sheets: KEY, A_sensitivity, B_date_diff, C_by_source, D_by_year, E_coverage_window, PPV_reverse, QC"))
message("\n=== R/202 complete ===")
