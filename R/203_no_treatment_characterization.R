# ==============================================================================
# Script:  203_no_treatment_characterization.R
# Phase:   203 — no-treatment-patient-characterization
# Purpose: Split confirmed_hl_cohort.rds into a no-treatment group (no Gantt
#          treatment episode) and a treated group; profile both side by side and
#          explain the no-treatment group with a first-match reason waterfall.
#          No cohort-membership change — the split is analytic-only.
# Schema:  .planning/schemas/203_schema_inputs_20261114.md (HiPerGator probe).
#          Every column name below comes from that file.
# Inputs:  confirmed_hl_cohort.rds        (env R203_COHORT_RDS)
#          gantt_episodes_180.csv         (env R203_GANTT180_CSV)
#          single_source_care_*.rds R/169 (env R203_R169_RDS; excludes *_parts_*)
#          tr_lymphoma_flags_all_patients (env R203_TRFLAGS_RDS; rds, else csv)
#          enc_far_from_care.rds          (env R203_FARCARE_RDS)
#          DuckDB: DIAGNOSIS, ENCOUNTER, TUMOR_REGISTRY_ALL; payer_summary
# Outputs: output/203_no_treatment_characterization_<date>.xlsx
#            (KEY, A_profile, B_reasons_waterfall, C_by_source,
#             D_candidate_rules, E_by_primary_source, QC)
#          output/internal/203_no_treatment_characterization_<date>.rds  (patient-level)
# Run:     module load R/4.5; R --no-save
#          source("R/203_no_treatment_characterization.R", local = new.env(parent = globalenv()))
# ==============================================================================

# ==============================================================================
# SECTION 0: SETUP ----
# ==============================================================================

source(here::here("R", "00_config.R"), local = FALSE)
source(here::here("R", "utils", "utils_tr_sensitivity.R"))  # tr_flag_to_logical()

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(lubridate)
  library(glue)
  library(here)
  library(openxlsx)
  library(vroom)
})

RUN_DATE <- Sys.getenv("RUN_DATE", format(Sys.Date(), "%Y%m%d"))
message(glue("==== R/203 no_treatment_characterization -- RUN DATE {RUN_DATE} ===="))

# Small-cell suppression: counts 1-10 -> "<11" (same as R/202 fmt_sup).
fmt_sup <- function(n) {
  if (is.na(n)) return(NA_character_)
  n <- as.integer(n)
  if (n >= 1L & n <= 10L) "<11" else format(n, big.mark = ",")
}
sup_col <- function(x) vapply(x, fmt_sup, character(1))
pct_sup <- function(num, den) {
  ifelse(!is.na(num) & num >= 11L & den >= 11L, sprintf("%.1f%%", 100 * num / den), "")
}

need_cols <- function(df, cols, what) {
  miss <- setdiff(cols, names(df))
  if (length(miss) > 0L)
    stop("[R203] ", what, ": missing columns ", paste(miss, collapse = ", "),
         ". Available: ", paste(sort(names(df)), collapse = ", "))
  invisible(df)
}

# duck_query: open, query, close in one helper (single shared connection;
# close with close_pcornet_con(), never DBI::dbDisconnect).
duck_query <- function(sql) {
  open_pcornet_con()
  on.exit(try(close_pcornet_con(), silent = TRUE), add = TRUE)
  DBI::dbGetQuery(pcornet_con, sql)
}

# ==============================================================================
# SECTION 1: PINNED INPUTS ----
# Env var overrides; otherwise the dated/newest-by-name default below. "Newest"
# means last in sorted file names (dates are in the names), never file.mtime.
# ==============================================================================

newest_by_name <- function(dir, pattern, exclude = NULL) {
  f <- list.files(dir, pattern = pattern, full.names = TRUE)
  if (!is.null(exclude)) f <- f[!grepl(exclude, basename(f))]
  if (length(f) == 0L) return(NA_character_)
  sort(f)[length(f)]
}
pin <- function(env, default) {
  v <- Sys.getenv(env, unset = "")
  list(path = if (nzchar(v)) v else default, pinned = nzchar(v))
}
must_exist <- function(p, env) {
  if (is.na(p$path) || !file.exists(p$path))
    stop("[R203] input not found for ", env, ": ", p$path,
         ". Set ", env, " to an existing file.")
  p
}

internal_dir <- file.path(CONFIG$output_dir, "internal")

pin_cohort <- must_exist(pin("R203_COHORT_RDS",
  file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds")), "R203_COHORT_RDS")
pin_gantt  <- must_exist(pin("R203_GANTT180_CSV",
  file.path(CONFIG$output_dir, "gantt_episodes_180.csv")), "R203_GANTT180_CSV")
pin_r169   <- must_exist(pin("R203_R169_RDS",
  newest_by_name(internal_dir, "^single_source_care_.*\\.rds$", exclude = "_parts_")),
  "R203_R169_RDS")
pin_trflags <- must_exist(pin("R203_TRFLAGS_RDS", {
  rds <- newest_by_name(internal_dir, "^tr_lymphoma_flags_all_patients_.*\\.rds$")
  if (!is.na(rds)) rds else
    newest_by_name(CONFIG$output_dir, "^tr_lymphoma_flags_all_patients_.*\\.csv$")
}), "R203_TRFLAGS_RDS")
pin_far    <- must_exist(pin("R203_FARCARE_RDS",
  file.path(CONFIG$output_dir, "enc_far_from_care.rds")), "R203_FARCARE_RDS")

pin_info <- list(cohort_rds = pin_cohort, gantt180_csv = pin_gantt, r169_rds = pin_r169,
                 trflags = pin_trflags, farcare_rds = pin_far)
message("[R203] Pin status:")
for (nm in names(pin_info))
  message(glue("  {nm}: {pin_info[[nm]]$path}  [pinned={pin_info[[nm]]$pinned}]"))

# ==============================================================================
# SECTION 2: LOAD COHORT + GANTT; SPLIT POPULATIONS ----
# ==============================================================================

TX_TYPES <- c("Chemotherapy", "Immunotherapy", "Radiation", "SCT", "Proton Therapy")
EXPECTED_NO_TX   <- 3246L
EXPECTED_TREATED <- 4450L
POP_TOLERANCE    <- 50L

cohort <- readRDS(pin_cohort$path)
need_cols(cohort, c("ID", "first_hl_dx_date", "first_hl_dx_source"), "confirmed_hl_cohort.rds")
cohort <- cohort |>
  transmute(ID = as.character(ID), first_hl_dx_date = as.Date(first_hl_dx_date),
            first_hl_dx_source)
message(glue("[R203] Cohort: {nrow(cohort)} rows, {n_distinct(cohort$ID)} distinct IDs"))

# Gantt key is patient_id; renamed to ID once, here.
gantt <- vroom(
  pin_gantt$path,
  col_select = c(patient_id, treatment_type, age_at_episode),
  col_types = cols_only(patient_id = col_character(), treatment_type = col_character(),
                        age_at_episode = col_integer()),
  show_col_types = FALSE
) |>
  rename(ID = patient_id)
message(glue("[R203] Gantt: {nrow(gantt)} rows, {n_distinct(gantt$ID)} distinct IDs"))

gantt_tx_ids  <- unique(gantt$ID[gantt$treatment_type %in% TX_TYPES])
gantt_all_ids <- unique(gantt$ID)

cohort <- cohort |>
  mutate(group = if_else(ID %in% gantt_tx_ids, "treated", "no_treatment"))
n_notx    <- sum(cohort$group == "no_treatment")
n_treated <- sum(cohort$group == "treated")
n_treated_total <- n_treated
message(glue("[R203] no_tx {n_notx}; treated {n_treated}; total {nrow(cohort)}"))
stopifnot("Split must be exhaustive and non-overlapping" = n_notx + n_treated == nrow(cohort))

pop_ok <- abs(n_notx - EXPECTED_NO_TX) <= POP_TOLERANCE &&
  abs(n_treated - EXPECTED_TREATED) <= POP_TOLERANCE
if (!pop_ok)
  warning(glue("[R203] population counts outside expected {EXPECTED_NO_TX}/{EXPECTED_TREATED} ",
               "+/- {POP_TOLERANCE}: got {n_notx}/{n_treated}"))

# Non-cohort Gantt patients: reported in QC only.
n_death_only <- length(setdiff(setdiff(gantt_all_ids, cohort$ID), gantt_tx_ids))
n_tx_only    <- length(setdiff(gantt_tx_ids, cohort$ID))
message(glue("[R203] not in cohort: death-only {n_death_only} (expect 166); ",
             "tx-only {n_tx_only} (expect 558)"))

# Age at dx: Gantt HL Diagnosis row (age_at_episode), one per patient.
age_dx <- gantt |>
  filter(treatment_type == "HL Diagnosis") |>
  group_by(ID) |>
  summarise(age_at_dx = suppressWarnings(min(age_at_episode, na.rm = TRUE)), .groups = "drop") |>
  mutate(age_at_dx = if_else(is.finite(age_at_dx), age_at_dx, NA_integer_))
rm(gantt)

# ==============================================================================
# SECTION 3: DERIVE CHARACTERIZATION VARIABLES (schema section 5) ----
# ==============================================================================

# --- NLPHL (DIAGNOSIS + classify_codes) and encounter dates (ENCOUNTER) -------
# Own query helper calls; IDs joined in R (no IN() lists). Encounter dates before
# ENC_DATE_SENTINEL_BEFORE (1990-01-01) are sentinels and excluded.
NLPHL_LABEL    <- "NLPHL"
HL_OTHER_LABEL <- "Hodgkin Lymphoma (non-NLPHL)"

dx_rows <- duck_query(
  "SELECT DISTINCT CAST(ID AS VARCHAR) AS ID, DX
   FROM DIAGNOSIS
   WHERE DX LIKE 'C81%' OR DX LIKE '201%'"
) |> mutate(ID = as.character(ID), site = classify_codes(DX)) |>
  filter(site %in% c(NLPHL_LABEL, HL_OTHER_LABEL))

nlphl_pt <- dx_rows |>
  group_by(ID) |>
  summarise(has_hl_dx_rows = TRUE,
            nlphl_any  = any(site == NLPHL_LABEL),
            nlphl_only = any(site == NLPHL_LABEL) && !any(site == HL_OTHER_LABEL),
            .groups = "drop")
rm(dx_rows)

enc_pt <- duck_query(glue(
  "SELECT CAST(ID AS VARCHAR) AS ID,
          MIN(TRY_CAST(ADMIT_DATE AS DATE)) AS first_enc_date,
          MAX(TRY_CAST(ADMIT_DATE AS DATE)) AS last_enc_date
   FROM ENCOUNTER
   WHERE TRY_CAST(ADMIT_DATE AS DATE) >= DATE '{format(ENC_DATE_SENTINEL_BEFORE)}'
   GROUP BY ID"
)) |> mutate(ID = as.character(ID),
             first_enc_date = as.Date(first_enc_date), last_enc_date = as.Date(last_enc_date))
message(glue("[R203] DIAGNOSIS HL patients {nrow(nlphl_pt)}; ENCOUNTER patients {nrow(enc_pt)}"))

# --- Probable prevalent HL, component (a): personal-history-of-HL codes ---------
# ICD-10 Z85.71, ICD-9 V10.72. DX is matched dot-insensitively (same convention as
# normalize_icd(): uppercase, dots removed) so dotted and undotted forms both hit.
HIST_HL_CODES <- c("Z8571", "V1072")
hist_in_list <- paste0("'", HIST_HL_CODES, "'", collapse = ", ")
hist_rows <- duck_query(glue(
  "SELECT CAST(ID AS VARCHAR) AS ID, DX, DX_DATE
   FROM DIAGNOSIS
   WHERE REPLACE(UPPER(CAST(DX AS VARCHAR)), '.', '') IN ({hist_in_list})"
)) |>
  mutate(ID = as.character(ID),
         dx_norm = normalize_icd(as.character(DX)),
         hist_date = suppressWarnings(as.Date(substr(as.character(DX_DATE), 1, 10)))) |>
  filter(dx_norm %in% HIST_HL_CODES)
message(glue("[R203] history-of-HL DX rows: {nrow(hist_rows)} ",
             "({n_distinct(hist_rows$ID)} patients); DX forms seen: ",
             "{paste(sort(unique(as.character(hist_rows$DX))), collapse = ', ')}"))
hist_pt <- hist_rows |>
  group_by(ID) |>
  summarise(first_hist_dx_date = if (all(is.na(hist_date))) as.Date(NA) else
              min(hist_date, na.rm = TRUE), .groups = "drop")
rm(hist_rows)

# --- Component (b): earliest TR diagnosis date on HL-histology rows -------------
# UFH DATE_OF_DIAGNOSIS; ORL/TMH DXDATE (same column map as R/202 TR_DX_DATE_COLS).
TR_DX_DATE_COLS <- c(UFH = "DATE_OF_DIAGNOSIS", ORL = "DXDATE", TMH = "DXDATE")
open_pcornet_con()
tr_dx_raw <- local({
  on.exit(try(close_pcornet_con(), silent = TRUE), add = TRUE)
  tbl <- get_pcornet_table("TUMOR_REGISTRY_ALL")
  all_cols <- colnames(tbl)
  hist_present <- intersect(TR_HIST_COLS, all_cols)
  dx_present   <- intersect(unique(TR_DX_DATE_COLS), all_cols)
  if (!"SOURCE" %in% all_cols || length(hist_present) == 0L || length(dx_present) == 0L)
    stop("[R203] TUMOR_REGISTRY_ALL lacks SOURCE / histology / dx-date columns. Available: ",
         paste(all_cols, collapse = ", "))
  tbl |>
    dplyr::select(dplyr::all_of(unique(c("ID", "SOURCE", hist_present, dx_present)))) |>
    dplyr::collect() |>
    dplyr::filter(dplyr::if_any(dplyr::all_of(hist_present),
      ~ substr(as.character(.x), 1, 4) %in% ICD_CODES$hl_histology))
})
tr_dx_pt <- bind_rows(lapply(names(TR_DX_DATE_COLS), function(src) {
  col <- TR_DX_DATE_COLS[[src]]
  if (!col %in% names(tr_dx_raw)) return(tibble(ID = character(), tr_dx_date = as.Date(character())))
  tr_dx_raw |>
    filter(SOURCE == src) |>
    transmute(ID = as.character(ID),
              tr_dx_date = suppressWarnings(as.Date(substr(as.character(.data[[col]]), 1, 10))))
})) |>
  filter(!is.na(tr_dx_date)) |>
  group_by(ID) |>
  summarise(tr_dx_date = min(tr_dx_date), .groups = "drop")
rm(tr_dx_raw)
message(glue("[R203] TR HL dx dates: {nrow(tr_dx_pt)} patients"))

# --- Single-source care (R/169 tibble) -----------------------------------------
ssc <- readRDS(pin_r169$path)
if (!is.data.frame(ssc))
  stop("[R203] R169 input is not a data frame (a *_parts_* list file?): ", pin_r169$path)
need_cols(ssc, c("ID", "single_source_care", "primary_source"), "R/169 single_source_care")
ssc <- ssc |>
  transmute(ID = as.character(ID), single_source_care = as.integer(single_source_care),
            primary_source)

# --- Far from care (patient-level rollup of enc_far_from_care.rds) -------------
far_enc <- readRDS(pin_far$path)
need_cols(far_enc, c("ID", "far_from_care_100mi", "post_anchor", "distance_mi"),
          "enc_far_from_care.rds")
far_pt <- far_enc |>
  transmute(ID = as.character(ID), far = as.integer(far_from_care_100mi),
            post = as.integer(post_anchor), distance_mi) |>
  group_by(ID) |>
  summarise(far_any_post = any(far == 1L & post == 1L, na.rm = TRUE),
            median_distance_mi_post = if (any(post == 1L, na.rm = TRUE))
              median(distance_mi[post %in% 1L], na.rm = TRUE) else NA_real_,
            .groups = "drop")
rm(far_enc)

# --- Payer: load_payer_summary() returns ID + PAYER_CATEGORY_PRIMARY (already the
# patient-level payer category). classify_payer_tier() needs encounter-level
# PAYER_TYPE_PRIMARY/SECONDARY/SOURCE, so it does not apply to this input; the
# category is reported as stored.
payer <- load_payer_summary(cohort$ID)
payer_path <- attr(payer, "source_path")
# One missing definition for A_profile and QC: NA after the join, or an explicit
# Missing / NI / UN / Unknown category -> "Missing" (applied in SECTION 4).
PAYER_MISSING_LABELS <- c("MISSING", "NI", "UN", "UNKNOWN")
payer <- payer |> transmute(ID = as.character(ID), payer_category = PAYER_CATEGORY_PRIMARY)

# --- TR flags (tr_hl_dx / tr_nhl_dx) -------------------------------------------
tr_flags <- if (grepl("\\.rds$", pin_trflags$path, ignore.case = TRUE)) {
  readRDS(pin_trflags$path)
} else {
  vroom(pin_trflags$path, col_types = cols(.default = col_character()), show_col_types = FALSE)
}
need_cols(tr_flags, c("ID", "tr_hl_dx", "tr_nhl_dx"), "tr_lymphoma_flags_all_patients")
tr_flags <- tr_flags |>
  transmute(ID = as.character(ID), tr_hl_dx = tr_flag_to_logical(tr_hl_dx),
            tr_nhl_dx = tr_flag_to_logical(tr_nhl_dx))

# --- TR first-course treatment (shared function, R/utils/utils_cancer.R) --------
# Types that map to a pipeline treatment type (Chemotherapy, Immunotherapy,
# Radiation incl. proton, SCT). Hormone/systemic have no Gantt counterpart.
TR_NOTX_TYPES <- c("chemo", "radiation", "immuno", "sct")
tr_tx <- build_tr_treatment_flags(ids = cohort$ID)
tr_tx_pt <- tr_tx |>
  filter(trtype %in% TR_NOTX_TYPES) |>
  group_by(ID) |>
  summarise(tr_any_tx_given = any(tr_given), tr_any_tx_unknown = any(tr_unknown),
            .groups = "drop")
message(glue("[R203] TR treatment flags: {nrow(tr_tx)} patient x type rows; ",
             "{n_distinct(tr_tx$ID)} patients with HL TR rows"))

# ==============================================================================
# SECTION 4: ASSEMBLE PATIENT-LEVEL FRAME ----
# ==============================================================================

char_pt <- cohort |>
  left_join(age_dx,   by = "ID") |>
  left_join(nlphl_pt, by = "ID") |>
  left_join(enc_pt,   by = "ID") |>
  left_join(ssc,      by = "ID") |>
  left_join(far_pt,   by = "ID") |>
  left_join(payer,    by = "ID") |>
  left_join(tr_flags, by = "ID") |>
  left_join(tr_tx_pt, by = "ID") |>
  left_join(hist_pt,  by = "ID") |>
  left_join(tr_dx_pt, by = "ID") |>
  mutate(
    payer_category = if_else(is.na(payer_category) |
                               toupper(trimws(payer_category)) %in% PAYER_MISSING_LABELS,
                             "Missing", payer_category),
    has_hl_dx_rows = coalesce(has_hl_dx_rows, FALSE),
    nlphl_any      = coalesce(nlphl_any, FALSE),
    nlphl_only     = coalesce(nlphl_only, FALSE),
    followup_days  = as.integer(last_enc_date - first_hl_dx_date),
    age_group_dx = case_when(
      is.na(age_at_dx) ~ NA_character_,
      age_at_dx < 18   ~ "0-17",
      age_at_dx < 40   ~ "18-39",
      age_at_dx < 60   ~ "40-59",
      TRUE             ~ "60+"
    ),
    hl_subtype = case_when(
      nlphl_only     ~ "NLPHL only",
      nlphl_any      ~ "NLPHL + other HL codes",
      has_hl_dx_rows ~ "cHL only",
      TRUE           ~ "No HL code in DIAGNOSIS"
    ),
    followup_band = case_when(
      is.na(followup_days) ~ NA_character_,
      followup_days < 180  ~ "<180d",
      followup_days < 730  ~ "180-729d",
      followup_days < 1825 ~ "730-1824d",
      TRUE                 ~ "1825d+"
    ),
    far_from_care = case_when(
      is.na(far_any_post) ~ NA_character_,
      far_any_post        ~ "far (>100 mi, post-anchor)",
      TRUE                ~ "not far"
    ),
    single_source_lbl = case_when(
      is.na(single_source_care) ~ NA_character_,
      single_source_care == 1L  ~ "single source",
      TRUE                      ~ "multi source"
    )
  ) |>
  add_notx_flags()

char_pt$notx_reason <- ifelse(char_pt$group == "no_treatment",
                              as.character(assign_notx_reason(char_pt)), NA_character_)
char_pt$notx_reason <- factor(char_pt$notx_reason, levels = NOTX_REASON_LEVELS)

stopifnot(nrow(char_pt) == nrow(cohort), !anyDuplicated(char_pt$ID))
message(glue("[R203] char_pt: {nrow(char_pt)} rows, {ncol(char_pt)} columns"))

# Internal patient-level frame (IDs, dates) — output/internal only.
out_rds <- file.path(internal_dir, glue("203_no_treatment_characterization_{RUN_DATE}.rds"))
dir.create(dirname(out_rds), showWarnings = FALSE, recursive = TRUE)
saveRDS(char_pt, out_rds)
message(glue("[R203] char_pt saved: {out_rds}"))

notx_pt <- char_pt |> filter(group == "no_treatment")
n_tr_missed <- sum(notx_pt$f_tr_treated)
n_prevalent <- sum(notx_pt$f_prevalent_hl)
message(glue("[R203] probable prevalent HL among no_tx: {fmt_sup(n_prevalent)} ",
             "(hist code {fmt_sup(sum(notx_pt$f_hist_code))}; ",
             "TR dx > 365d earlier {fmt_sup(sum(notx_pt$f_tr_early_dx))})"))
message(glue("[R203] KEY FINDING: TR says treated among no_tx: {fmt_sup(n_tr_missed)} of {n_notx}"))

# ==============================================================================
# SECTION 5: NOTX-05 — CANDIDATE "TREATMENT OBSERVABLE" RULE ----
# RULE NOT APPLIED — proposed team decision item (D-203-01). Never used to filter
# the cohort or the Gantt file.
# ==============================================================================
# treatment_observable = dx date present AND an encounter within the EHR coverage
# window (first usable encounter <= dx + 90d) AND >= 180d follow-up after dx.
# Multi-source care and far-from-care are NOT part of the rule (reported as
# sensitivity flags in B_reasons_waterfall).
char_pt <- char_pt |>
  mutate(
    dates_missing = is.na(first_hl_dx_date),
    treatment_observable = !dates_missing & !f_dx_before_coverage & !f_short_followup
  )
# Cleanest pipeline-capture miss count: TR says treated AND observable (D rule).
n_tr_obs_missed <- sum(char_pt$group == "no_treatment" & char_pt$treatment_observable &
                         char_pt$f_tr_treated)
n_notx_observable <- sum(char_pt$group == "no_treatment" & char_pt$treatment_observable)
message(glue("[R203] no_tx observable {n_notx_observable}; of those TR-treated ",
             "{fmt_sup(n_tr_obs_missed)}"))

# ==============================================================================
# SECTION 6: WORKBOOK ASSEMBLY ----
# KEY leftmost, then A_profile, B_reasons_waterfall, C_by_source,
# D_candidate_rules, QC. fmt_sup applied to every displayed count.
# ==============================================================================

UF_BLUE   <- "#0021A5"
UF_ORANGE <- "#FA4616"
hdr_style <- openxlsx::createStyle(fgFill = UF_BLUE, fontColour = "white",
  textDecoration = "bold", fontName = "Arial", fontSize = 11, halign = "left")
accent_style <- openxlsx::createStyle(fgFill = UF_ORANGE, fontColour = "white",
  textDecoration = "bold", fontName = "Arial", fontSize = 11)

write_sheet <- function(wb, sheet_name, df, accent_first = FALSE, col_widths = 22) {
  openxlsx::addWorksheet(wb, sheet_name)
  openxlsx::writeData(wb, sheet_name, df, startRow = 1, headerStyle = hdr_style)
  openxlsx::setColWidths(wb, sheet_name, cols = seq_len(ncol(df)), widths = col_widths)
  if (accent_first && nrow(df) >= 1)
    openxlsx::addStyle(wb, sheet_name, accent_style, rows = 2,
                       cols = seq_len(ncol(df)), stack = FALSE)
}

# A_profile: no_treatment and treated adjacent columns per characteristic.
profile_section <- function(df, var, name) {
  df |>
    mutate(category = as.character(.data[[var]]),
           category = if_else(is.na(category), "Missing", category)) |>
    count(group, category, name = "n") |>
    complete(group = c("no_treatment", "treated"), category, fill = list(n = 0L)) |>
    pivot_wider(names_from = group, values_from = n, values_fill = 0L) |>
    mutate(characteristic = name,
           no_treatment = sup_col(no_treatment), treated = sup_col(treated)) |>
    select(characteristic, category, no_treatment, treated)
}

char_flags <- char_pt |>
  mutate(
    tr_hl_dx_lbl     = case_when(is.na(tr_hl_dx) ~ "not in TR", tr_hl_dx ~ "TR HL TRUE", TRUE ~ "TR HL FALSE"),
    tr_says_treated  = if_else(f_tr_treated, "TR says treated", "TR does not say treated"),
    dx_before_cov    = if_else(f_dx_before_coverage, "dx before EHR coverage", "covered"),
    nlphl_any_lbl    = if_else(nlphl_any, "NLPHL any", "no NLPHL code"),
    prevalent_lbl    = if_else(f_prevalent_hl, "probable prevalent / history-of HL", "not flagged"),
    nlphl_only_lbl   = if_else(nlphl_only, "NLPHL only", "not NLPHL only")
  )

sheet_A <- bind_rows(
  tibble(characteristic = "group size", category = "all cohort patients",
         no_treatment = sup_col(n_notx), treated = sup_col(n_treated)),
  profile_section(char_flags, "age_group_dx",       "age at dx (Gantt HL Diagnosis row)"),
  profile_section(char_flags, "hl_subtype",         "HL subtype (DIAGNOSIS)"),
  profile_section(char_flags, "nlphl_any_lbl",      "nlphl_any"),
  profile_section(char_flags, "nlphl_only_lbl",     "nlphl_only"),
  profile_section(char_flags, "first_hl_dx_source", "first_hl_dx_source"),
  profile_section(char_flags, "prevalent_lbl",      "probable prevalent HL (hist code or early TR dx)"),
  profile_section(char_flags, "dx_before_cov",      "EHR coverage (first encounter vs dx + 90d)"),
  profile_section(char_flags, "followup_band",      "follow-up after dx"),
  profile_section(char_flags, "single_source_lbl",  "single-source care (R/169)"),
  profile_section(char_flags, "primary_source",     "primary source (R/169)"),
  profile_section(char_flags, "far_from_care",      "far from care (100 mi)"),
  profile_section(char_flags, "payer_category",     "payer category (payer_summary)"),
  profile_section(char_flags, "tr_hl_dx_lbl",       "tumor registry HL flag"),
  profile_section(char_flags, "tr_says_treated",    "TR first-course treatment")
)

# B_reasons_waterfall: no_tx patients; first-match (exclusive) + non-exclusive flags.
# Flag rows carry the treated-group count/% and ratio (no_tx % / treated %).
b_excl <- notx_pt |>
  count(notx_reason, .drop = FALSE) |>
  mutate(section = "first-match (mutually exclusive)", reason = as.character(notx_reason))
b_flag_defs <- c(
  f_tr_treated         = "TR says treated (missed by pipeline)",
  f_hist_code          = "Prevalent component (a): history-of-HL code (Z85.71 / V10.72) on/before dx + 30d",
  f_tr_early_dx        = "Prevalent component (b): TR dx date > 365d before first_hl_dx_date",
  f_prevalent_hl       = "Probable prevalent / history-of HL (a or b)",
  f_short_followup     = "Short follow-up (< 180d after dx)",
  f_dx_before_coverage = "Dx before EHR coverage (first encounter > dx + 90d)",
  f_nlphl_only         = "NLPHL only",
  f_nlphl_any          = "NLPHL any (reference; higher among treated)",
  f_multi_source       = "Multi-source care (not a reason)",
  f_far_from_care      = "Far from care (> 100 mi, post-anchor; not a reason)"
)
treated_pt <- char_pt |> filter(group == "treated")
b_flag <- tibble(
  section = "flag present (not exclusive; overlaps)",
  reason  = unname(b_flag_defs),
  n         = vapply(names(b_flag_defs), function(f) sum(notx_pt[[f]]), integer(1)),
  n_treated = vapply(names(b_flag_defs), function(f) sum(treated_pt[[f]]), integer(1))
) |>
  mutate(
    ratio_no_tx_over_treated = if_else(
      n >= 11L & n_treated >= 11L,
      sprintf("%.2f", (n / n_notx) / (n_treated / n_treated_total)), ""),
    pct_of_treated = pct_sup(n_treated, n_treated_total),
    n_treated = sup_col(n_treated)
  )
sheet_B <- bind_rows(
  tibble(section = "population", reason = "no_treatment patients (total)", n = n_notx),
  b_excl |> select(section, reason, n),
  b_flag |> mutate(n = as.integer(n))
) |>
  mutate(pct_of_no_treatment = pct_sup(n, n_notx), n = sup_col(n)) |>
  select(section, reason, n, pct_of_no_treatment,
         any_of(c("n_treated", "pct_of_treated", "ratio_no_tx_over_treated")))

# C_by_source: R/169 primary_source x group.
c_one <- function(df, var, name) {
  df |>
    mutate(category = as.character(.data[[var]]),
           category = if_else(is.na(category), "Missing", category),
           SOURCE = coalesce(primary_source, "Unknown")) |>
    count(group, SOURCE, category, name = "n") |>
    mutate(characteristic = name)
}
sheet_C <- bind_rows(
  c_one(char_flags, "dx_before_cov",     "EHR coverage"),
  c_one(char_flags, "single_source_lbl", "single-source care"),
  c_one(char_flags, "payer_category",    "payer category"),
  c_one(char_flags, "tr_says_treated",   "TR first-course treatment"),
  c_one(filter(char_pt, group == "no_treatment"), "notx_reason", "no_tx reason (first-match)")
) |>
  arrange(group, SOURCE, characteristic, category) |>
  mutate(n = sup_col(n)) |>
  select(group, SOURCE, characteristic, category, n)

# D_candidate_rules: rule definition (text) + per-group counts. NOT APPLIED.
d_def <- tibble(
  item = c("status", "rule (NOTX-05)", "TRUE means", "FALSE reasons", "not in rule",
           "application"),
  value = c(
    "RULE NOT APPLIED — proposed team decision item (D-203-01)",
    "treatment_observable = first_hl_dx_date present AND first usable encounter <= dx + 90d AND last encounter - dx >= 180d",
    "an absent treatment record is informative: the patient was observable in the EHR around dx and afterwards",
    "dates_missing; dx before EHR coverage (first encounter > dx + 90d or no usable encounter); short follow-up (< 180d)",
    "multi-source care and far-from-care are reported as flags only; TR-says-treated patients are a pipeline-capture gap, not an observability gap",
    "Not applied to the cohort or to gantt_episodes_180. Counts below are descriptive."
  )
)
d_counts <- char_pt |>
  group_by(group) |>
  summarise(
    n_total                = n(),
    n_observable_true      = sum(treatment_observable),
    n_observable_false     = sum(!treatment_observable),
    n_false_dates_missing  = sum(dates_missing),
    n_false_dx_before_coverage = sum(!dates_missing & f_dx_before_coverage),
    n_false_short_followup = sum(!dates_missing & !f_dx_before_coverage & f_short_followup),
    n_observable_and_tr_treated = sum(treatment_observable & f_tr_treated),
    .groups = "drop"
  ) |>
  mutate(across(starts_with("n_"), sup_col))

# E_by_primary_source: one row per R/169 primary_source. Observable = D rule
# (descriptive only; not applied).
sheet_E_num <- char_pt |>
  mutate(SOURCE = coalesce(primary_source, "Unknown")) |>
  group_by(SOURCE) |>
  summarise(
    n_no_tx           = sum(group == "no_treatment"),
    n_treated         = sum(group == "treated"),
    n_no_tx_observable = sum(group == "no_treatment" & treatment_observable),
    n_observable_all  = sum(treatment_observable),
    .groups = "drop"
  ) |>
  arrange(desc(n_no_tx + n_treated))
sheet_E <- sheet_E_num |>
  transmute(
    primary_source = SOURCE,
    n_no_tx = sup_col(n_no_tx), n_treated = sup_col(n_treated),
    pct_no_tx = pct_sup(n_no_tx, n_no_tx + n_treated),
    n_no_tx_observable = sup_col(n_no_tx_observable),
    n_observable_all = sup_col(n_observable_all),
    pct_no_tx_among_observable = pct_sup(n_no_tx_observable, n_observable_all)
  )

# QC
n_missing <- function(x) sum(is.na(x))
sheet_QC <- tibble(
  check = c(
    "no_treatment (expected 3,246 +/- 50)", "treated (expected 4,450 +/- 50)", "total cohort",
    "population assertion within tolerance",
    "not in cohort: death-only Gantt patients (expected 166)",
    "not in cohort: tx-only Gantt patients (expected 558)",
    "missing: age at dx (no Gantt HL Diagnosis row)",
    "missing: first usable encounter (none, or sentinel only)",
    "missing: R/169 single_source_care join",
    "missing: far-from-care patient rollup",
    "missing: payer category",
    "tr_hl_dx NA (patient not in TR)",
    "patients with HL TR treatment rows (build_tr_treatment_flags)",
    "patients with no HL code in DIAGNOSIS",
    "no_tx patients: TR says treated (key finding)",
    "no_tx patients: TR says treated AND observable (D rule) -- cleanest pipeline-capture misses",
    "no_tx patients: observable (D rule)",
    "no_tx patients: probable prevalent / history-of HL (a or b)",
    "payer missing definition",
    "payer_summary file", "encounter sentinel guard", "suppression"
  ),
  value = c(
    fmt_sup(n_notx), fmt_sup(n_treated), fmt_sup(nrow(char_pt)),
    as.character(pop_ok),
    fmt_sup(n_death_only), fmt_sup(n_tx_only),
    fmt_sup(n_missing(char_pt$age_at_dx)),
    fmt_sup(n_missing(char_pt$first_enc_date)),
    fmt_sup(n_missing(char_pt$single_source_care)),
    fmt_sup(n_missing(char_pt$far_any_post)),
    fmt_sup(sum(char_pt$payer_category == "Missing")),
    fmt_sup(n_missing(char_pt$tr_hl_dx) ),
    fmt_sup(n_distinct(tr_tx$ID)),
    fmt_sup(sum(!char_pt$has_hl_dx_rows)),
    fmt_sup(n_tr_missed),
    fmt_sup(n_tr_obs_missed),
    fmt_sup(n_notx_observable),
    fmt_sup(n_prevalent),
    "NA after join OR payer category in Missing/NI/UN/Unknown (A_profile 'Missing' uses the same rule)",
    as.character(payer_path),
    paste0("ENCOUNTER.ADMIT_DATE < ", format(ENC_DATE_SENTINEL_BEFORE), " excluded from first/last encounter"),
    "YES — counts 1-10 shown as <11; percentages only when numerator and denominator >= 11"
  )
)

# KEY
sheet_KEY <- tibble(
  item = c(
    "run_date", "script", "schema probe",
    "input: cohort_rds", "input: gantt180_csv", "input: r169_rds", "input: trflags",
    "input: farcare_rds", "input: payer_summary",
    "pinned: cohort_rds", "pinned: gantt180_csv", "pinned: r169_rds", "pinned: trflags",
    "pinned: farcare_rds",
    "group: no_treatment", "group: treated",
    "TR says treated",
    "TR says treated AND observable",
    "prevalent_hl_probable",
    "payer missing",
    "waterfall order",
    "payer",
    "sheet: A_profile", "sheet: B_reasons_waterfall", "sheet: C_by_source",
    "sheet: D_candidate_rules", "sheet: E_by_primary_source", "sheet: QC",
    "suppression_note", "D-203-01"
  ),
  value = c(
    RUN_DATE, "R/203_no_treatment_characterization.R",
    ".planning/schemas/203_schema_inputs_20261114.md",
    pin_cohort$path, pin_gantt$path, pin_r169$path, pin_trflags$path, pin_far$path,
    as.character(payer_path),
    as.character(pin_cohort$pinned), as.character(pin_gantt$pinned),
    as.character(pin_r169$pinned), as.character(pin_trflags$pinned),
    as.character(pin_far$pinned),
    "cohort patients with no Gantt treatment_type in Chemotherapy, Immunotherapy, Radiation, SCT, Proton Therapy",
    "cohort patients with >= 1 Gantt episode of those types",
    paste0("registry first-course treatment (UFH + ORL, types ", paste(TR_NOTX_TYPES, collapse = "/"),
           ") documented while the pipeline captured none; function build_tr_treatment_flags() in R/utils/utils_cancer.R"),
    "TR says treated AND observable (D rule): no_tx patients the registry documents as treated while the pipeline captured none and the patient was observable; cleanest count of true pipeline-capture misses (other TR-treated patients are explained by coverage or follow-up). Also a QC row.",
    paste0("first_hl_dx_date is the first HL code in the data, so it cannot reveal prevalent cases. TRUE if (a) Z85.71 / V10.72 in DIAGNOSIS on/before first_hl_dx_date + ", NOTX_HISTORY_GRACE_DAYS, "d, or (b) TR dx date (UFH DATE_OF_DIAGNOSIS; ORL/TMH DXDATE) > ", NOTX_TR_EARLY_DX_DAYS, "d before first_hl_dx_date. Components reported separately in B."),
    "NA after join OR category Missing/NI/UN/Unknown, collapsed to 'Missing' (same rule in A_profile and QC)",
    paste0("first-match, mutually exclusive: ", paste(seq_along(NOTX_REASON_LEVELS), NOTX_REASON_LEVELS, sep = ". ", collapse = " | "), ". Multi-source and far-from-care are non-exclusive flags only (more common among treated); NLPHL uses nlphl_only."),
    "PAYER_CATEGORY_PRIMARY from load_payer_summary(); classify_payer_tier() is encounter-level and not applied",
    "side-by-side profile: no_treatment vs treated",
    "no_treatment reasons: first-match exclusive counts plus non-exclusive flags with treated n/%, ratio = no_tx % / treated %",
    "primary_source (R/169) x group",
    "proposed treatment_observable rule — NOT APPLIED (D-203-01)",
    "per R/169 primary_source: no_tx n, treated n, % no_tx, % no_tx among observable (D rule)",
    "population reconciliation, join completeness, non-cohort Gantt patients",
    "Patient counts 1-10 are shown as <11. Percentages only when numerator and denominator >= 11.",
    "RULE NOT APPLIED — proposed team decision item"
  )
)

# --- Assemble workbook ----------------------------------------------------------
wb <- openxlsx::createWorkbook()
write_sheet(wb, "KEY",                 sheet_KEY, accent_first = TRUE)   # leftmost
write_sheet(wb, "A_profile",           sheet_A)
write_sheet(wb, "B_reasons_waterfall", sheet_B)
write_sheet(wb, "C_by_source",         sheet_C)
write_sheet(wb, "D_candidate_rules",   d_def, accent_first = TRUE, col_widths = c(22, 120))
openxlsx::writeData(wb, "D_candidate_rules", d_counts,
                    startRow = nrow(d_def) + 3, headerStyle = hdr_style)
write_sheet(wb, "E_by_primary_source", sheet_E)
write_sheet(wb, "QC",                  sheet_QC, col_widths = c(60, 60))

out_path <- file.path(CONFIG$output_dir, glue("203_no_treatment_characterization_{RUN_DATE}.xlsx"))
dir.create(CONFIG$output_dir, showWarnings = FALSE, recursive = TRUE)
openxlsx::saveWorkbook(wb, out_path, overwrite = TRUE)

message(glue("[R203] Workbook written: {out_path}"))
message(glue(
  "[R203] Sheets: KEY ({nrow(sheet_KEY)} rows), A_profile ({nrow(sheet_A)}), ",
  "B_reasons_waterfall ({nrow(sheet_B)}), C_by_source ({nrow(sheet_C)}), ",
  "D_candidate_rules ({nrow(d_def)}+{nrow(d_counts)}), ",
  "E_by_primary_source ({nrow(sheet_E)}), QC ({nrow(sheet_QC)})"
))
message("[R203] Done. Patient-level RDS in output/internal/ only; workbook has no patient IDs.")
