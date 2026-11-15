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

# --- TR COLUMN MAP (from schema probe) ---------------------------------------
# Source: .planning/schemas/202_schema_tr_treatment_cols_20261114.md
# TUMOR_REGISTRY_ALL has no TR1/TR2/TR3 split: stratify by SOURCE (UFH/ORL/TMH).
#
# code_scheme (the meaning of 0 is OPPOSITE between the two schemes):
#   reason_no : REASON_NO_* / R_N_* fields.  0 = treatment GIVEN; other codes =
#               reason not given.
#   naaccr_rx : NAACCR summary codes (*_CODE_SUMMARY, HORMONE_CODE, ...).
#               00 = none; listed given_values = given (01-03 chemo, 01 immuno ...).
#   rx_summ   : RX Summ fields (DRAD_SUM, DBRM_SUM, HTE_SUM).  0 = NONE.
# Unknown codes (counted "unknown", never "not given"):
CODE_UNKNOWN <- list(
  reason_no = c(8L, 9L),
  naaccr_rx = c(88L, 99L),
  rx_summ   = c(8L, 9L, 88L, 99L)
)

tr_map_row <- function(source, trtype, date_col = NA_character_,
                       code_col = NA_character_, code_scheme = NA_character_,
                       given_values = integer(0)) {
  tibble(source = source, trtype = trtype, date_col = date_col,
         code_col = code_col, code_scheme = code_scheme,
         given_values = list(as.integer(given_values)))
}

SCT_GIVEN <- c(10L, 11L, 12L, 20L)   # 10 BMT NOS; 11 auto; 12 allo; 20 SC harvest+infusion

TR_MAP <- bind_rows(
  # UFH (NAACCR summary items)
  tr_map_row("UFH", "chemo",     "CHEMO_START_DATE_SUMMARY",       "CHEMO_CODE_SUMMARY",               "naaccr_rx", 1:3),
  tr_map_row("UFH", "systemic",  "DATE_SYSTEMIC_THERAPY_STARTED"),
  tr_map_row("UFH", "radiation", NA_character_,                    "REASON_NO_RADIATION",              "reason_no", 0L),
  tr_map_row("UFH", "immuno",    "IMMUNO_START_DATE",              "IMMUNOTHERAPY_CODE",               "naaccr_rx", 1L),
  tr_map_row("UFH", "sct",       NA_character_,                    "HEMATOLOGIC_TRANSPLANT_AND_ENDOC", "naaccr_rx", SCT_GIVEN),
  tr_map_row("UFH", "hormone",   "HORMONE_START_DATE",             "HORMONE_CODE",                     "naaccr_rx", 1L),
  # ORL (abstract-style)
  tr_map_row("ORL", "chemo",     "DT_CHEMO",                       "R_N_CHEMO",                        "reason_no", 0L),
  tr_map_row("ORL", "systemic",  "DT_SYS"),
  tr_map_row("ORL", "radiation", "DT_RAD",                         "R_N_RAD",                          "reason_no", 0L),
  tr_map_row("ORL", "immuno",    NA_character_,                    "DBRM_SUM",                         "rx_summ",   1L),
  tr_map_row("ORL", "sct",       NA_character_,                    "HTE_SUM",                          "rx_summ",   SCT_GIVEN),
  tr_map_row("ORL", "hormone",   "DT_HORM",                        "R_N_HORM",                         "reason_no", 0L),
  # TMH (15 TR rows; counts only, no sensitivity). DRAD_SUM: 0 = none; 8/9 unknown;
  # the probe lists no "given" value for it, so given_values is empty.
  tr_map_row("TMH", "chemo",     "DT_CHEMO"),
  tr_map_row("TMH", "systemic",  "DT_SYS"),
  tr_map_row("TMH", "radiation", NA_character_,                    "DRAD_SUM",                         "rx_summ"),
  tr_map_row("TMH", "immuno",    NA_character_,                    "DBRM_SUM",                         "rx_summ",   1L),
  tr_map_row("TMH", "sct",       NA_character_,                    "HTE_SUM",                          "rx_summ",   SCT_GIVEN)
)

# Histology columns used to restrict to HL rows (same two columns and substr(1, 4)
# rule as R/10_cohort_predicates.R:83,92; not listed in the 202 probe).
TR_HIST_COLS <- c("HISTOLOGICAL_TYPE", "MORPH")

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
tr_flags <- readRDS(tr_flags_path)
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

needed_cols <- unique(c("ID", "SOURCE", hist_present, map_cols))
tr_data <- tr_tbl_raw |>
  select(all_of(needed_cols)) |>
  collect()
close_pcornet_con()

tr_hl <- tr_data |>
  mutate(is_hl_row = Reduce(`|`, lapply(hist_present, function(cn)
    substr(as.character(.data[[cn]]), 1, 4) %in% ICD_CODES$hl_histology))) |>
  filter(is_hl_row)
n_tr_rows    <- nrow(tr_data)
n_tr_hl_rows <- nrow(tr_hl)
n_tmh_rows   <- sum(tr_hl$SOURCE == "TMH")
message(glue("  TUMOR_REGISTRY_ALL: {n_tr_rows} rows; {n_tr_hl_rows} HL-histology rows ",
             "({n_distinct(tr_hl$ID)} patients); columns pulled: {length(needed_cols)}"))
message("  HL rows by SOURCE: ",
        paste(names(table(tr_hl$SOURCE)), as.integer(table(tr_hl$SOURCE)), collapse = "; "))

# --- SECTION 3b: PATIENT-LEVEL COLLAPSE --------------------------------------
# Per map row (source x treatment type): row-level evidence on HL rows.
#   row_given   = date present OR code in given_values
#   row_unknown = code in the scheme's unknown codes (88, 99, 8, 9)
# Per patient: tr_given = any HL row given; tr_first_date = earliest non-missing
# date across HL rows; unknown (and not given) is "unknown", not "not_given".
tr_row_evidence <- function(rows, map_row) {
  src_rows <- rows |> filter(SOURCE == map_row$source)
  n <- nrow(src_rows)
  dt <- if (!is.na(map_row$date_col)) as.Date(src_rows[[map_row$date_col]]) else rep(as.Date(NA), n)
  cd <- if (!is.na(map_row$code_col)) {
    suppressWarnings(as.integer(as.character(src_rows[[map_row$code_col]])))
  } else rep(NA_integer_, n)
  unk_codes <- if (is.na(map_row$code_scheme)) integer(0) else CODE_UNKNOWN[[map_row$code_scheme]]
  tibble(
    ID = src_rows$ID, SOURCE = map_row$source, trtype = map_row$trtype,
    row_date    = dt,
    row_given   = !is.na(dt) | cd %in% unlist(map_row$given_values),
    row_unknown = cd %in% unk_codes
  )
}

collapse_evidence <- function(ev, by) {
  ev |>
    group_by(across(all_of(by))) |>
    summarise(
      tr_given       = any(row_given),
      tr_unknown_any = any(row_unknown),
      tr_first_date  = if (any(!is.na(row_date))) min(row_date, na.rm = TRUE) else as.Date(NA),
      .groups = "drop"
    ) |>
    mutate(tr_status = case_when(tr_given ~ "given", tr_unknown_any ~ "unknown", TRUE ~ "not_given"))
}

tr_evidence <- bind_rows(lapply(seq_len(nrow(TR_MAP)), function(i) tr_row_evidence(tr_hl, TR_MAP[i, ])))
tr_pt_src <- collapse_evidence(tr_evidence, c("ID", "SOURCE", "trtype"))              # per source (C, B)
tr_pt_all <- collapse_evidence(filter(tr_evidence, SOURCE %in% SENS_SOURCES),
                               c("ID", "trtype"))                                      # UFH+ORL (A, D, PPV)
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
# Per patient x treatment type (x SOURCE for the source-level table):
#   unknown_code  TR code is unknown (88/99/8/9) and no HL row says given
#   no_registry   TR does not record this treatment as given
#   not_captured  TR given; no Gantt episode of that type (or first dates >90 d apart)
#   not_datable   TR given by code only (no date); Gantt episode exists
#   exact / within_30d / within_90d   |TR first date - Gantt first date|
message("=== Section 6: Capture classification ===")
GIVEN_TIERS <- c("exact", "within_30d", "within_90d", "not_datable", "not_captured")
HIT_TIERS   <- c("exact", "within_30d", "within_90d")

classify_capture <- function(tr_pt, gantt_first_df, ids) {
  tr_pt |>
    filter(ID %in% ids) |>
    inner_join(filter(TYPE_DEF, !is.na(gantt_type)), by = "trtype") |>
    left_join(gantt_first_df, by = c("ID" = "patient_id", "gantt_type" = "treatment_type")) |>
    mutate(
      d = abs(as.integer(tr_first_date - gantt_first_date)),
      capture_tier = case_when(
        tr_status == "unknown"        ~ "unknown_code",
        tr_status != "given"          ~ "no_registry",
        is.na(gantt_first_date)       ~ "not_captured",
        is.na(tr_first_date)          ~ "not_datable",
        d == 0L                       ~ "exact",
        d <= 30L                      ~ "within_30d",
        d <= 90L                      ~ "within_90d",
        TRUE                          ~ "not_captured"
      ),
      treatment_label = label
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
sensitivity_raw <- classified |>
  filter(capture_tier %in% GIVEN_TIERS) |>
  group_by(treatment_label) |>
  summarise(
    n_denom        = n(),
    n_exact        = sum(capture_tier == "exact"),
    n_30d          = sum(capture_tier %in% c("exact", "within_30d")),
    n_90d          = sum(capture_tier %in% HIT_TIERS),
    n_undated      = sum(capture_tier == "not_datable"),
    n_not_captured = sum(capture_tier == "not_captured"),
    .groups = "drop"
  ) |>
  left_join(
    classified |> filter(capture_tier == "unknown_code") |> count(treatment_label, name = "n_unknown"),
    by = "treatment_label"
  ) |>
  mutate(
    n_unknown = coalesce(n_unknown, 0L),
    pct_exact = pct_sup(n_exact, n_denom),
    pct_30d   = pct_sup(n_30d,   n_denom),
    pct_90d   = pct_sup(n_90d,   n_denom),
    n_denom_disp        = sup_col(n_denom),
    n_exact_disp        = sup_col(n_exact),
    n_30d_disp          = sup_col(n_30d),
    n_90d_disp          = sup_col(n_90d),
    n_undated_disp      = sup_col(n_undated),
    n_not_captured_disp = sup_col(n_not_captured),
    n_unknown_disp      = sup_col(n_unknown)
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
    `Captured, TR undated n` = n_undated_disp,
    `Not captured n`     = n_not_captured_disp,
    `TR unknown code n (not in denominator)` = n_unknown_disp
  )
message(glue("  A_sensitivity: {nrow(sheet_A)} rows"))

# --- SECTION 8: B_DATE_DIFF TABLE -------------------------------------------
# Only type/source pairs that have a TR date column (B_PAIRS); only TR-dated rows.
message("=== Section 8: B_date_diff ===")

tiers <- c("exact", "within_30d", "within_90d", "not_captured")
tier_labels <- c("Exact match", "Within 30d", "Within 90d", "Not captured")

sheet_B_main <- classified_src |>
  semi_join(B_PAIRS, by = c("SOURCE" = "source", "trtype")) |>
  filter(capture_tier %in% GIVEN_TIERS, !is.na(tr_first_date)) |>
  group_by(SOURCE, treatment_label, capture_tier) |>
  summarise(n = n(), .groups = "drop") |>
  mutate(
    tier_label = factor(capture_tier, levels = tiers, labels = tier_labels),
    n_disp     = sup_col(n)
  ) |>
  select(
    `SOURCE`         = SOURCE,
    `Treatment Type` = treatment_label,
    `Capture Tier`   = tier_label,
    `Count`          = n_disp
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
  filter(capture_tier %in% GIVEN_TIERS) |>
  group_by(SOURCE, trtype) |>
  summarise(n_sens_denom = n(), n_captured = sum(capture_tier %in% HIT_TIERS), .groups = "drop")

sheet_C_raw <- c_counts |>
  left_join(c_sens, by = c("SOURCE", "trtype")) |>
  left_join(TYPE_DEF |> select(trtype, label), by = "trtype") |>
  mutate(
    pct_captured = pct_sup(n_captured, n_sens_denom),
    note = case_when(
      SOURCE == "TMH"        ~ "TMH: counts only; too few for sensitivity",
      is.na(n_sens_denom)    ~ "no Gantt counterpart / not compared",
      TRUE                   ~ ""
    )
  ) |>
  arrange(SOURCE, label)

sheet_C <- sheet_C_raw |>
  transmute(
    `SOURCE (partner site)` = SOURCE,
    `Treatment Type`        = label,
    `TR given n`            = sup_col(n_given),
    `TR unknown code n`     = sup_col(n_unknown),
    `Pipeline captured n`   = ifelse(SOURCE == "TMH" | is.na(n_captured), NA_character_, sup_col(n_captured)),
    `Sensitivity %`         = ifelse(SOURCE == "TMH", NA_real_, pct_captured),
    Note                    = note
  )
sheet_C <- bind_rows(sheet_C, tibble(
  `SOURCE (partner site)` = "TMH",
  `Treatment Type`        = "(footnote)",
  Note = as.character(glue("n = {fmt_sup(n_tmh_rows)} TR rows; too few for sensitivity"))
))
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
  left_join(cohort_dx, by = "ID")

# Year grouping: define early / late split at median dx_year
yr_median <- median(classified_yr$dx_year, na.rm = TRUE)
message(glue("  Median diagnosis year: {yr_median}"))

classified_yr <- classified_yr |>
  mutate(dx_year_group = ifelse(
    is.na(dx_year), "Unknown",
    ifelse(dx_year <= yr_median, glue("Early (≤{yr_median})"), glue("Late (>{yr_median})"))
  ))

sheet_D <- classified_yr |>
  filter(capture_tier %in% GIVEN_TIERS) |>
  group_by(dx_year_group, treatment_label) |>
  summarise(
    n_denom    = n(),
    n_captured = sum(capture_tier %in% HIT_TIERS),
    .groups    = "drop"
  ) |>
  mutate(
    pct_captured    = pct_sup(n_captured, n_denom),
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
    "Suppression check: any raw count 1-10 in sheet_A",
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
      sensitivity_raw$n_denom   %in% 1:10 |
      sensitivity_raw$n_exact   %in% 1:10 |
      sensitivity_raw$n_90d     %in% 1:10
    )),
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
    "Sheet C_by_source", "Sheet D_by_year",
    "Sheet PPV_reverse",
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
    "exact / within 30 d / within 90 d of first Gantt episode; TR given by code only = 'not datable' (Gantt episode exists); first dates >90 d apart count as not captured.",
    "% of TR-given patients captured by pipeline (exact/30/90 d), by treatment type",
    "Date-difference tiers for type/source pairs with a TR date: chemo UFH/ORL, radiation ORL, immuno UFH, hormone UFH/ORL; footnote rows",
    "Counts by SOURCE for UFH/ORL/TMH; sensitivity for UFH/ORL only",
    "Sensitivity stratified by diagnosis year group",
    "For pipeline captures, fraction with matching registry record (PPV direction; UFH + ORL)",
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
