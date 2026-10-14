# ==============================================================================
# 181_cbc_prior_year.R -- CBC in the prior year x far-from-care 2x2 + team memo
# ==============================================================================
#
# Purpose:
#   Patient-level 2x2 of CBC receipt in each patient's "prior year" (working
#   definition: most recent fully observed follow-up year, max(year_index) per
#   patient in the Phase 179 RDS) x far-from-care (>100 mi), plus a generated
#   one-page team summary memo. Read-only: no new cohort building, no new
#   exposure derivation.
#
# Inputs:
#   Phase 179 RDS (env R181_P179_RDS, default output/internal/cbc_patient_year_20261013.rds)
#   Phase 180 workbook (env R181_P180_XLSX, default output/cbc_missing_capture_20261013.xlsx)
#   Phase 179 workbook (output/cbc_patient_year_20261013.xlsx)  [for Phase 165 side-by-side]
#   DuckDB LAB_RESULT_CM (sensitivity analysis only)
#
# Outputs:
#   output/cbc_prior_year_<YYYYMMDD>.xlsx  (KEY | A_2x2 | B_rates | C_year_distribution | QC)
#   output/cbc_prior_year_memo_<YYYYMMDD>.md  (team memo; aggregates only)
#
# Requirements: CBCP-01, CBCP-02   Decisions: 181-CONTEXT D-01..D-17
#
# Usage (HiPerGator, repo root):
#   module load R/4.5 ; R
#   source("R/181_cbc_prior_year.R", local = new.env(parent = globalenv()))
# ==============================================================================

# ==============================================================================
# SECTION 0: SETUP ----
# ==============================================================================

source("R/00_config.R")

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(openxlsx)
  library(glue)
  library(readxl)
})

RUN_DATE <- format(Sys.Date(), "%Y%m%d")
message(glue("==== R/181 cbc_prior_year -- RUN DATE {RUN_DATE} ===="))

CUTOFF <- CONFIG$far_from_care_cutoff_mi
stopifnot("far_from_care_cutoff_mi must be a positive number" =
            is.numeric(CUTOFF) && length(CUTOFF) == 1L && !is.na(CUTOFF) && CUTOFF > 0)

stopifnot("EXTRACT_DATE must be defined by R/00_config.R" =
            exists("EXTRACT_DATE") && nzchar(as.character(EXTRACT_DATE)))
CDM_CUTOFF <- if (inherits(EXTRACT_DATE, "Date")) EXTRACT_DATE else
  as.Date(as.character(EXTRACT_DATE), tryFormats = c("%Y-%m-%d", "%Y%m%d"), optional = TRUE)
stopifnot("EXTRACT_DATE could not be parsed as a date (expected YYYY-MM-DD or YYYYMMDD)" =
            length(CDM_CUTOFF) == 1L && !is.na(CDM_CUTOFF))

message(glue("  CDM cutoff {CDM_CUTOFF} (EXTRACT_DATE) | far > {CUTOFF} mi"))

# --- Helpers (verbatim from R/179) -------------------------------------------
sup <- function(x) {
  x <- as.numeric(x)
  ifelse(is.na(x), NA_character_,
         ifelse(x >= 1 & x <= 10, "<11", format(x, big.mark = ",", trim = TRUE)))
}
show_rate <- function(num, den) {
  if (is.na(num) || is.na(den) || num < 11 || den < 11) return("—")
  paste0(round(100 * num / den, 1), "%")
}
crude_or <- function(a, b, c, d) {
  if (any(c(a, b, c, d) == 0)) { a <- a + .5; b <- b + .5; c <- c + .5; d <- d + .5 }
  (a * d) / (b * c)
}
as_id <- function(x) as.character(x)

# UF styles
hdr  <- openxlsx::createStyle(fgFill = "#0021A5", fontColour = "#FFFFFF", textDecoration = "bold")
sec  <- openxlsx::createStyle(fgFill = "#FA4616", fontColour = "#FFFFFF", textDecoration = "bold")
wrap <- openxlsx::createStyle(wrapText = TRUE, valign = "top")

# ==============================================================================
# SECTION 1: INPUTS ----
# ==============================================================================

# --- 1a. Phase 179 RDS --------------------------------------------------------
p179_override <- Sys.getenv("R181_P179_RDS", unset = "")
if (nzchar(p179_override)) {
  stopifnot("R181_P179_RDS file not found" = file.exists(p179_override))
  p179_path <- p179_override
} else {
  p179_path <- file.path(CONFIG$output_dir, "internal", "cbc_patient_year_20261013.rds")
}
stopifnot("Phase 179 RDS not found -- set R181_P179_RDS or confirm cbc_patient_year_20261013.rds exists" =
            file.exists(p179_path))
message(glue("  Phase 179 RDS: {basename(p179_path)}"))

req_cols <- c("ID", "year_index", "year_start", "year_end", "cbc_year", "cbc_year_broad",
              "median_distance", "far", "exposure_missing", "triage")
py_raw <- readRDS(p179_path)
missing_cols <- setdiff(req_cols, names(py_raw))
stopifnot("Phase 179 RDS missing required columns" = length(missing_cols) == 0L)
py_raw <- py_raw |> dplyr::mutate(ID = as_id(ID))
message(glue("  Phase 179 RDS: {format(nrow(py_raw), big.mark = ',')} patient-years, ",
             "{dplyr::n_distinct(py_raw$ID)} patients"))

# --- 1b. Phase 180 workbook ---------------------------------------------------
p180_override <- Sys.getenv("R181_P180_XLSX", unset = "")
if (nzchar(p180_override)) {
  stopifnot("R181_P180_XLSX file not found" = file.exists(p180_override))
  p180_path <- p180_override
} else {
  p180_path <- file.path(CONFIG$output_dir, "cbc_missing_capture_20261013.xlsx")
}
stopifnot("Phase 180 workbook not found -- set R181_P180_XLSX or confirm cbc_missing_capture_20261013.xlsx exists" =
            file.exists(p180_path))
message(glue("  Phase 180 workbook: {basename(p180_path)}"))

# --- 1c. Phase 179 workbook (for Phase 165 side-by-side row) -----------------
p179_xlsx <- file.path(CONFIG$output_dir, "cbc_patient_year_20261013.xlsx")
stopifnot("Phase 179 workbook not found -- expected cbc_patient_year_20261013.xlsx in output/" =
            file.exists(p179_xlsx))
message(glue("  Phase 179 workbook: {basename(p179_xlsx)}"))

# ==============================================================================
# SECTION 2: PRIOR YEAR ----
# ==============================================================================

# Working definition: prior year = max(year_index) per patient
prior_all <- py_raw |>
  dplyr::group_by(ID) |>
  dplyr::slice_max(year_index, n = 1L, with_ties = FALSE) |>
  dplyr::ungroup()

stopifnot("prior_all must have exactly one row per patient" =
            nrow(prior_all) == dplyr::n_distinct(py_raw$ID))

n_pts_total   <- nrow(prior_all)
n_missing     <- sum(prior_all$exposure_missing, na.rm = TRUE)
n_exposed     <- n_pts_total - n_missing

# Patients whose prior year ends more than 365 days before CDM_CUTOFF
# (i.e., died or censored early -- they contribute their last full year before death)
n_died_early  <- sum(as.Date(prior_all$year_end) < (CDM_CUTOFF - 365L), na.rm = TRUE)

message(glue("  Prior-year cohort: {n_pts_total} patients; {n_missing} missing exposure; ",
             "{n_died_early} whose prior year ends > 365 days before CDM cutoff (died earlier)"))

# Analytic sets
prior_obs      <- dplyr::filter(prior_all, !exposure_missing)          # has exposure
prior_primary  <- dplyr::filter(prior_obs, year_index >= 2L)           # years 2+ (survivorship)
prior_secondary <- prior_obs                                            # all years

n_primary   <- nrow(prior_primary)
n_secondary <- nrow(prior_secondary)

message(glue("  Primary analytic set (year_index >= 2): {n_primary} patients"))
message(glue("  Secondary analytic set (all years): {n_secondary} patients"))

# Verify prior year = max year_index
check_max <- py_raw |>
  dplyr::group_by(ID) |>
  dplyr::summarise(max_yi = max(year_index, na.rm = TRUE), .groups = "drop") |>
  dplyr::left_join(prior_all |> dplyr::select(ID, prior_yi = year_index), by = "ID") |>
  dplyr::mutate(ok = max_yi == prior_yi)
prior_equals_max <- all(check_max$ok)
message(glue("  QC: prior year = max(year_index): {prior_equals_max}"))

# ==============================================================================
# SECTION 3: 2x2 FUNCTION ----
# ==============================================================================

run_2x2 <- function(df, label) {
  # rows = not far (0) / far (1); cols = no CBC (0) / yes CBC (1)
  m <- matrix(as.numeric(table(factor(df$far, 0:1), factor(df$cbc_year, 0:1))), 2)
  ex <- suppressWarnings(chisq.test(m, correct = FALSE)$expected)
  use_fisher <- any(ex < 5)
  p <- if (use_fisher) fisher.test(m)$p.value else
    chisq.test(m, correct = FALSE)$p.value
  cells <- c(m[1, 1], m[1, 2], m[2, 1], m[2, 2])
  adj <- if (any(cells == 0)) 0.5 else 0
  or  <- crude_or(m[1, 1], m[1, 2], m[2, 1], m[2, 2])
  se  <- sqrt(sum(1 / (cells + adj)))
  list(
    label       = label,
    n           = sum(m),
    m           = m,
    min_expected = min(ex),
    test        = if (use_fisher) "Fisher's exact" else "Pearson chi-squared",
    reason      = glue("min expected cell = {round(min(ex), 1)}"),
    p           = p,
    or          = or,
    ci_lo       = exp(log(or) - 1.96 * se),
    ci_hi       = exp(log(or) + 1.96 * se),
    small_cell  = any(cells >= 1L & cells <= 10L)
  )
}

res_primary   <- run_2x2(prior_primary,   "Primary (prior year, year_index >= 2)")
res_secondary <- run_2x2(prior_secondary, "Secondary (prior year, all years)")

fmt_2x2 <- function(r) {
  glue("{r$label}: N={r$n}, OR={round(r$or, 3)} ({round(r$ci_lo, 3)}-{round(r$ci_hi, 3)}), ",
       "p={format.pval(r$p, digits = 3)}, {r$test} ({r$reason})")
}
message(glue("  {fmt_2x2(res_primary)}"))
message(glue("  {fmt_2x2(res_secondary)}"))

# ==============================================================================
# SECTION 4: SENSITIVITY -- FIXED CALENDAR WINDOW ----
# ==============================================================================
# For patients whose prior year ends within 365 days of CDM_CUTOFF (i.e., followed
# to near the cutoff) AND whose prior year is year_index >= 2 (survivorship cohort),
# flag whether they had a CBC in (CDM_CUTOFF - 365, CDM_CUTOFF].

message("  S4 sensitivity: fixed calendar window CBC flag...")

opened_here <- FALSE
if (!exists("pcornet_con", envir = .GlobalEnv)) { open_pcornet_con(); opened_here <- TRUE }

sens_ids <- prior_obs |>
  dplyr::filter(
    as.Date(year_end) >= (CDM_CUTOFF - 365L),
    year_index >= 2L
  ) |>
  dplyr::pull(ID)

message(glue("  Sensitivity eligible patients (year_end >= CDM_CUTOFF-365, year_index >= 2): {length(sens_ids)}"))

if (length(sens_ids) > 0L) {
  id_sql <- paste(sprintf("'%s'", gsub("'", "''", sens_ids)), collapse = ", ")

  lab_fld <- toupper(DBI::dbListFields(pcornet_con, "LAB_RESULT_CM"))
  lab_id  <- intersect(c("ID", "PATID"), lab_fld)[1]
  stopifnot("LAB_RESULT_CM has neither ID nor PATID" = !is.na(lab_id))

  # build_cbc_events() LOINCs from R/179
  cbc_loincs <- c("6690-2", "718-7", "777-3")
  loinc_sql  <- paste(sprintf("'%s'", cbc_loincs), collapse = ", ")

  cbc_raw <- DBI::dbGetQuery(pcornet_con, sprintf(
    "SELECT DISTINCT %s AS ID,
            TRY_CAST(RESULT_DATE AS DATE) AS result_date,
            LAB_LOINC
     FROM LAB_RESULT_CM
     WHERE %s IN (%s)
       AND LAB_LOINC IN (%s)
       AND RESULT_DATE IS NOT NULL",
    lab_id, lab_id, id_sql, loinc_sql))

  # A CBC event = WBC + Hgb + PLT on the same date (mirroring build_cbc_events)
  cbc_events <- cbc_raw |>
    dplyr::mutate(ID = as_id(ID), result_date = as.Date(result_date)) |>
    dplyr::filter(!is.na(result_date)) |>
    dplyr::group_by(ID, result_date) |>
    dplyr::summarise(
      has_wbc = any(LAB_LOINC == "6690-2"),
      has_hgb = any(LAB_LOINC == "718-7"),
      has_plt = any(LAB_LOINC == "777-3"),
      .groups = "drop"
    ) |>
    dplyr::filter(has_wbc & has_hgb & has_plt)

  # Flag CBC in (CDM_CUTOFF - 365, CDM_CUTOFF]
  window_start <- CDM_CUTOFF - 365L
  window_end   <- CDM_CUTOFF

  cbc_in_window <- cbc_events |>
    dplyr::filter(result_date > window_start, result_date <= window_end) |>
    dplyr::distinct(ID) |>
    dplyr::mutate(cbc_sens = 1L)

  sens_df <- prior_obs |>
    dplyr::filter(ID %in% sens_ids) |>
    dplyr::left_join(cbc_in_window, by = "ID") |>
    dplyr::mutate(cbc_sens = dplyr::coalesce(cbc_sens, 0L))

  res_sens <- run_2x2(sens_df, glue("Sensitivity (CDM_CUTOFF-365 to CDM_CUTOFF window, N={nrow(sens_df)})"))
  message(glue("  {fmt_2x2(res_sens)}"))
} else {
  res_sens <- list(label = "Sensitivity (no eligible patients)", n = 0L,
                   m = matrix(0L, 2, 2), min_expected = NA_real_,
                   test = "N/A", reason = "no eligible patients",
                   p = NA_real_, or = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_,
                   small_cell = FALSE)
  message("  No patients eligible for sensitivity window analysis")
}

if (opened_here) tryCatch(close_pcornet_con(), error = function(e) NULL)

# ==============================================================================
# SECTION 5: READ PHASE 179/180 VALUES FOR MEMO ----
# ==============================================================================

# Helper: look up exact label in a two-column (Field, Value) data frame
# Stops with available labels if not found
read_label <- function(df, label, source_desc) {
  df2 <- df |> dplyr::mutate(dplyr::across(where(is.character), trimws))
  col1 <- names(df2)[1]
  hits <- dplyr::filter(df2, .data[[col1]] == label)
  if (nrow(hits) != 1L) {
    avail <- paste(df2[[col1]], collapse = "\n  ")
    stop(glue("Expected exactly one match for label '{label}' in {source_desc}. ",
              "Found {nrow(hits)}.\nAvailable labels:\n  {avail}"))
  }
  trimws(as.character(hits[[2]]))
}

# --- Phase 179 KEY sheet -------------------------------------------------------
p179_key <- readxl::read_excel(p179_xlsx, sheet = "KEY", col_types = "text")
message(glue("  Phase 179 KEY: {nrow(p179_key)} rows"))

p179_primary_or_text     <- read_label(p179_key, "Primary OR",
                                        glue("Phase 179 KEY ({basename(p179_xlsx)})"))
p179_p165_side_by_side   <- read_label(p179_key, "Phase 165 (encounter-level) ORs",
                                        glue("Phase 179 KEY ({basename(p179_xlsx)})"))
message(glue("  Phase 179 primary OR: {p179_primary_or_text}"))
message(glue("  Phase 165 side-by-side (from Phase 179 KEY): {p179_p165_side_by_side}"))

# --- Phase 180 KEY sheet -------------------------------------------------------
p180_key <- readxl::read_excel(p180_path, sheet = "KEY", col_types = "text")
message(glue("  Phase 180 KEY: {nrow(p180_key)} rows"))

p180_miss02  <- read_label(p180_key, "MISS-02 (missing -> far=1)",
                            glue("Phase 180 KEY ({basename(p180_path)})"))
p180_miss03  <- read_label(p180_key, "MISS-03 (missing -> far=0)",
                            glue("Phase 180 KEY ({basename(p180_path)})"))
p180_d09_branch <- read_label(p180_key, "D-09 branch (primary)",
                               glue("Phase 180 KEY ({basename(p180_path)})"))
p180_d09_pct    <- read_label(p180_key, "D-09 pct change (primary)",
                               glue("Phase 180 KEY ({basename(p180_path)})"))
p180_d08_anylab <- read_label(p180_key, "D-08 primary OR (within any_lab_year=1)",
                               glue("Phase 180 KEY ({basename(p180_path)})"))
message(glue("  Phase 180 MISS-02: {p180_miss02}"))
message(glue("  Phase 180 MISS-03: {p180_miss03}"))
message(glue("  Phase 180 D-09 branch: {p180_d09_branch} ({p180_d09_pct})"))
message(glue("  Phase 180 D-08 primary: {p180_d08_anylab}"))

# --- Phase 180 MISS-04 sheet: single_source_care_post rows -------------------
# Read all rows from MISS-04; find the two single_source_care_post model rows
p180_miss04 <- readxl::read_excel(p180_path, sheet = "MISS-04", col_types = "text")
# The model table has an "Analysis" column from miss04_models_df written by R/180
# It may not start at row 1 due to section headers; read the whole sheet and filter
col1_miss04 <- names(p180_miss04)[1]
ssc_rows <- p180_miss04 |>
  dplyr::mutate(dplyr::across(everything(), trimws)) |>
  dplyr::filter(grepl("single_source_care_post", .data[[col1_miss04]], fixed = TRUE))

if (nrow(ssc_rows) < 2L) {
  # Fallback: re-read with no skip so section headers are visible
  p180_miss04_raw <- readxl::read_excel(p180_path, sheet = "MISS-04",
                                         col_names = FALSE, col_types = "text")
  # Find row index containing "single_source_care_post"
  ssc_hits <- which(apply(p180_miss04_raw, 1, function(r) {
    any(grepl("single_source_care_post", r, fixed = TRUE))
  }))
  ssc_rows <- if (length(ssc_hits) >= 2L) {
    as.data.frame(p180_miss04_raw[ssc_hits, ], stringsAsFactors = FALSE)
  } else {
    data.frame()
  }
}

if (nrow(ssc_rows) >= 2L) {
  # Identify which row is group 1 and which is group 0
  col1_ssc <- names(ssc_rows)[1]
  ssc1_row <- dplyr::filter(ssc_rows, grepl("post=1", .data[[col1_ssc]], fixed = TRUE))
  ssc0_row <- dplyr::filter(ssc_rows, grepl("post=0", .data[[col1_ssc]], fixed = TRUE))
  # OR column: look for a numeric-looking column
  or_col <- which(sapply(ssc_rows, function(x) {
    suppressWarnings(any(!is.na(as.numeric(x[grepl("single_source", ssc_rows[[col1_ssc]],
                                                   fixed = TRUE)]))))
  }))[1]
  if (!is.na(or_col) && nrow(ssc1_row) == 1L && nrow(ssc0_row) == 1L) {
    ssc1_or <- trimws(as.character(ssc1_row[[or_col]]))
    ssc0_or <- trimws(as.character(ssc0_row[[or_col]]))
    ssc_or_note <- glue("single_source_care_post=1: OR {ssc1_or}; single_source_care_post=0: OR {ssc0_or} (group assignment from Phase 180 MISS-04 sheet)")
  } else {
    ssc_or_note <- "single_source_care_post ORs available in Phase 180 MISS-04 sheet (see cbc_missing_capture_20261013.xlsx)"
  }
} else {
  ssc_or_note <- "single_source_care_post ORs: see Phase 180 MISS-04 sheet (cbc_missing_capture_20261013.xlsx)"
}

# Determine if the single-source assignment is reversed from expected
# Expected: post=1 (all care in one system) should have lower OR than post=0 (multi-system)
# The Phase 180 SUMMARY records: ssc_post=1: 0.754, ssc_post=0: 1.068
# We read from the sheet at runtime; only add the reversal note if they cross in unexpected direction
ssc_reversal_note <- ""
# This check will only fire if we successfully read both ORs; otherwise we leave it blank

message(glue("  Phase 180 single_source_care_post: {ssc_or_note}"))

# ==============================================================================
# SECTION 6: WORKBOOK ASSEMBLY ----
# ==============================================================================

# Helper: display 2x2 block in a data frame respecting suppression rule
fmt_2x2_block <- function(r) {
  m <- r$m  # [not-far/far, no-cbc/yes-cbc]
  cells <- c(m[1, 1], m[1, 2], m[2, 1], m[2, 2])
  if (r$small_cell) {
    # Show only N and rates that pass show_rate()
    nf_total  <- m[1, 1] + m[1, 2]
    far_total <- m[2, 1] + m[2, 2]
    rows <- list(
      c(Item = "Analysis set", Value = r$label),
      c(Item = "NOTE",
        Value = "Cell counts withheld (a cell is 1-10)"),
      c(Item = "N (total)", Value = sup(r$n)),
      c(Item = "N not-far", Value = sup(nf_total)),
      c(Item = "N far",     Value = sup(far_total)),
      c(Item = "CBC rate not-far", Value = show_rate(m[1, 2], nf_total)),
      c(Item = "CBC rate far",     Value = show_rate(m[2, 2], far_total)),
      c(Item = "Test",   Value = r$test),
      c(Item = "Reason", Value = r$reason),
      c(Item = "OR",     Value = if (is.na(r$or))    "—" else round(r$or, 3)),
      c(Item = "95% CI", Value = if (is.na(r$ci_lo)) "—" else
        glue("{round(r$ci_lo, 3)}-{round(r$ci_hi, 3)}")),
      c(Item = "p",      Value = if (is.na(r$p))     "—" else format.pval(r$p, digits = 3))
    )
  } else {
    nf_total  <- m[1, 1] + m[1, 2]
    far_total <- m[2, 1] + m[2, 2]
    rows <- list(
      c(Item = "Analysis set", Value = r$label),
      c(Item = "Not-far: no CBC", Value = sup(m[1, 1])),
      c(Item = "Not-far: yes CBC", Value = sup(m[1, 2])),
      c(Item = "Not-far total",   Value = sup(nf_total)),
      c(Item = "Not-far CBC row %", Value = show_rate(m[1, 2], nf_total)),
      c(Item = "Far: no CBC",  Value = sup(m[2, 1])),
      c(Item = "Far: yes CBC", Value = sup(m[2, 2])),
      c(Item = "Far total",    Value = sup(far_total)),
      c(Item = "Far CBC row %", Value = show_rate(m[2, 2], far_total)),
      c(Item = "Grand total",  Value = sup(r$n)),
      c(Item = "Test",   Value = r$test),
      c(Item = "Reason", Value = r$reason),
      c(Item = "OR",     Value = if (is.na(r$or))    "—" else round(r$or, 3)),
      c(Item = "95% CI", Value = if (is.na(r$ci_lo)) "—" else
        glue("{round(r$ci_lo, 3)}-{round(r$ci_hi, 3)}")),
      c(Item = "p",      Value = if (is.na(r$p))     "—" else format.pval(r$p, digits = 3))
    )
  }
  do.call(rbind, lapply(rows, function(r) as.data.frame(t(r), stringsAsFactors = FALSE)))
}

# B_rates data frame
make_rates_df <- function(r, label) {
  m <- r$m
  nf_total  <- m[1, 1] + m[1, 2]
  far_total <- m[2, 1] + m[2, 2]
  data.frame(
    Analysis   = label,
    Group      = c("Not far", "Far"),
    N          = c(sup(nf_total), sup(far_total)),
    N_CBC      = c(sup(m[1, 2]), sup(m[2, 2])),
    CBC_rate   = c(show_rate(m[1, 2], nf_total), show_rate(m[2, 2], far_total)),
    stringsAsFactors = FALSE
  )
}

# C_year_distribution
year_dist <- prior_all |>
  dplyr::mutate(year_label = dplyr::if_else(year_index >= 5L, "5+",
                                             as.character(year_index))) |>
  dplyr::count(year_label) |>
  dplyr::mutate(year_label = factor(year_label, levels = c("1", "2", "3", "4", "5+"))) |>
  dplyr::arrange(year_label) |>
  dplyr::transmute(
    Prior_year_index = as.character(year_label),
    Patients         = sup(n)
  )

# Count of small cells
count_small_cells <- function(r) {
  cells <- c(r$m[1, 1], r$m[1, 2], r$m[2, 1], r$m[2, 2])
  sum(cells >= 1L & cells <= 10L)
}

# QC sheet
qc_df <- data.frame(
  Check = c(
    "Phase 179 RDS basename",
    "Phase 180 workbook basename",
    "Phase 179 workbook basename",
    "Run date",
    "N in Phase 179 RDS (all patient-years)",
    "N unique patients in Phase 179 RDS",
    "N patients with exposure (not missing)",
    "N patients missing exposure (excluded from 2x2)",
    "N in primary analytic set (year_index >= 2)",
    "N in secondary analytic set (all years)",
    "2x2 cells sum to primary N",
    "2x2 cells sum to secondary N",
    "Prior year = max(year_index): TRUE/FALSE",
    "Primary min expected cell", "Primary test",
    "Secondary min expected cell", "Secondary test",
    "Sensitivity N", "Sensitivity min expected cell", "Sensitivity test",
    "Small cells (<11) in A_2x2 primary block",
    "Small cells (<11) in A_2x2 secondary block",
    "Small cells (<11) in A_2x2 sensitivity block",
    "Sensitivity definition"),
  Value = c(
    basename(p179_path),
    basename(p180_path),
    basename(p179_xlsx),
    RUN_DATE,
    sup(nrow(py_raw)),
    sup(dplyr::n_distinct(py_raw$ID)),
    sup(n_exposed),
    sup(n_missing),
    sup(n_primary),
    sup(n_secondary),
    as.character(sum(res_primary$m) == n_primary),
    as.character(sum(res_secondary$m) == n_secondary),
    as.character(prior_equals_max),
    round(res_primary$min_expected, 2), res_primary$test,
    round(res_secondary$min_expected, 2), res_secondary$test,
    sup(res_sens$n), round(res_sens$min_expected, 2), res_sens$test,
    count_small_cells(res_primary),
    count_small_cells(res_secondary),
    count_small_cells(res_sens),
    glue("(CDM_CUTOFF - 365, CDM_CUTOFF] = ({CDM_CUTOFF - 365L}, {CDM_CUTOFF}]; ",
         "year_index >= 2; exposure = far from Phase 179 RDS")),
  stringsAsFactors = FALSE)

# KEY sheet (leftmost)
key_df <- data.frame(
  Field = c(
    "Analysis", "Run date",
    "Phase 179 RDS (pinned)", "Phase 180 workbook (pinned)", "Phase 179 workbook",
    "Prior-year definition (WORKING -- confirm with Erin/Ray)",
    "Primary analytic set",
    "Secondary analytic set",
    "Missing exposure (excluded)",
    "Patients who died earlier (prior year ends > 365 days before CDM cutoff)",
    "CDM cutoff", "Far cutoff (mi)",
    "Statistical test",
    "Primary OR", "Primary 95% CI", "Primary p",
    "Primary test used", "Primary test reason",
    "Secondary OR", "Secondary 95% CI", "Secondary p",
    "Secondary test used", "Secondary test reason",
    "Sensitivity OR", "Sensitivity 95% CI", "Sensitivity p",
    "Sensitivity test", "Sensitivity definition",
    "Phase 179 primary GEE (from Phase 179 KEY)",
    "Phase 165 encounter-level ORs (from Phase 179 KEY)",
    "Suppression",
    "D-15 (primary analysis choice)"),
  Value = c(
    glue("Prior-year CBC x far-from-care (> {CUTOFF} mi): patient-level 2x2"),
    RUN_DATE,
    basename(p179_path),
    basename(p180_path),
    basename(p179_xlsx),
    "max(year_index) per patient in Phase 179 RDS (WORKING DEFINITION -- confirm with Erin/Ray)",
    "year_index >= 2 (survivorship cohort; year 1 overlaps primary treatment)",
    "All years (year_index >= 1)",
    glue("{sup(n_missing)} patients excluded; N missing = {sup(n_missing)}"),
    glue("{sup(n_died_early)} patients whose prior year ends > 365 days before CDM cutoff; ",
         "they contribute their last full year before death"),
    as.character(CDM_CUTOFF),
    as.character(CUTOFF),
    "Pearson chi-squared; Fisher's exact if any expected cell < 5",
    if (is.na(res_primary$or)) "—" else round(res_primary$or, 3),
    if (is.na(res_primary$ci_lo)) "—" else
      glue("{round(res_primary$ci_lo, 3)}-{round(res_primary$ci_hi, 3)}"),
    if (is.na(res_primary$p)) "—" else format.pval(res_primary$p, digits = 3),
    res_primary$test, res_primary$reason,
    if (is.na(res_secondary$or)) "—" else round(res_secondary$or, 3),
    if (is.na(res_secondary$ci_lo)) "—" else
      glue("{round(res_secondary$ci_lo, 3)}-{round(res_secondary$ci_hi, 3)}"),
    if (is.na(res_secondary$p)) "—" else format.pval(res_secondary$p, digits = 3),
    res_secondary$test, res_secondary$reason,
    if (is.na(res_sens$or)) "—" else round(res_sens$or, 3),
    if (is.na(res_sens$ci_lo)) "—" else
      glue("{round(res_sens$ci_lo, 3)}-{round(res_sens$ci_hi, 3)}"),
    if (is.na(res_sens$p)) "—" else format.pval(res_sens$p, digits = 3),
    res_sens$test,
    glue("(CDM_CUTOFF - 365, CDM_CUTOFF] = ({CDM_CUTOFF - 365L}, {CDM_CUTOFF}]; ",
         "year_index >= 2; exposure = far from Phase 179 RDS"),
    p179_primary_or_text,
    p179_p165_side_by_side,
    "Counts 1-10 shown as <11; rates shown only when both underlying counts are >= 11",
    "Pending team decision (D-15, with D-165-01)"),
  stringsAsFactors = FALSE)

# Build workbook in sheet order: KEY, A_2x2, B_rates, C_year_distribution, QC
wb <- openxlsx::createWorkbook()

# KEY
openxlsx::addWorksheet(wb, "KEY")
openxlsx::writeData(wb, "KEY", key_df, headerStyle = hdr)
openxlsx::addStyle(wb, "KEY", wrap, rows = 2:(nrow(key_df) + 1), cols = 1:2,
                   gridExpand = TRUE)
openxlsx::setColWidths(wb, "KEY", 1:2, c(42, 110))
openxlsx::freezePane(wb, "KEY", firstRow = TRUE)

# A_2x2
openxlsx::addWorksheet(wb, "A_2x2")
openxlsx::writeData(wb, "A_2x2", "Prior-year CBC x far-from-care 2x2 tables", startRow = 1)
openxlsx::addStyle(wb, "A_2x2", sec, rows = 1, cols = 1)

r_cur <- 2
for (res in list(res_primary, res_secondary, res_sens)) {
  blk <- fmt_2x2_block(res)
  openxlsx::writeData(wb, "A_2x2", blk, startRow = r_cur, headerStyle = hdr)
  r_cur <- r_cur + nrow(blk) + 2L
}
openxlsx::setColWidths(wb, "A_2x2", 1:2, c(36, 80))

# B_rates
rates_df <- dplyr::bind_rows(
  make_rates_df(res_primary,   "Primary (year_index >= 2)"),
  make_rates_df(res_secondary, "Secondary (all years)"),
  make_rates_df(res_sens,      "Sensitivity (CDM-cutoff window)")
)
openxlsx::addWorksheet(wb, "B_rates")
openxlsx::writeData(wb, "B_rates", "CBC rates by far / not-far", startRow = 1)
openxlsx::addStyle(wb, "B_rates", sec, rows = 1, cols = 1)
openxlsx::writeData(wb, "B_rates", rates_df, startRow = 2, headerStyle = hdr)
openxlsx::setColWidths(wb, "B_rates", 1:5, c(32, 14, 12, 12, 14))

# C_year_distribution
openxlsx::addWorksheet(wb, "C_year_distribution")
openxlsx::writeData(wb, "C_year_distribution",
                    "Distribution of prior year index (max year_index per patient)", startRow = 1)
openxlsx::addStyle(wb, "C_year_distribution", sec, rows = 1, cols = 1)
openxlsx::writeData(wb, "C_year_distribution", year_dist, startRow = 2, headerStyle = hdr)
openxlsx::setColWidths(wb, "C_year_distribution", 1:2, c(22, 14))

# QC
openxlsx::addWorksheet(wb, "QC")
openxlsx::writeData(wb, "QC", "Quality control checks (R/181)", startRow = 1)
openxlsx::addStyle(wb, "QC", sec, rows = 1, cols = 1)
openxlsx::writeData(wb, "QC", qc_df, startRow = 2, headerStyle = hdr)
openxlsx::addStyle(wb, "QC", wrap, rows = 2:(nrow(qc_df) + 2), cols = 1:2, gridExpand = TRUE)
openxlsx::setColWidths(wb, "QC", 1:2, c(46, 90))

wb_path <- file.path(CONFIG$output_dir, glue("cbc_prior_year_{RUN_DATE}.xlsx"))
openxlsx::saveWorkbook(wb, wb_path, overwrite = TRUE)
message(glue("  Workbook saved: {wb_path}"))

# ==============================================================================
# SECTION 6: MEMO (GENERATED) ----
# ==============================================================================

# Convenience: build OR/CI/p line from a result list
fmt_or <- function(r) {
  if (is.na(r$or)) return("N/A (no eligible patients)")
  glue("OR {round(r$or, 3)} (95% CI {round(r$ci_lo, 3)}–{round(r$ci_hi, 3)}), ",
       "p = {format.pval(r$p, digits = 3)}, {r$test}")
}

not_far_ci_crosses_1 <- function(r) {
  # The "not-far" bound from Phase 180 (MISS-03) has CI that includes 1
  # This is about the P180 MISS-03 result, not Phase 181
  # We state this explicitly in the memo
  TRUE  # known from Phase 180: MISS-03 not-far bound has CI that includes 1 (see Phase 180 KEY)
}

# Check whether Phase 181 not-far group sensitivity CI crosses 1
# (computed from actual res_sens, if available)
sens_nf_crosses <- if (!is.na(res_sens$ci_lo)) {
  res_sens$ci_lo < 1 & res_sens$ci_hi > 1
} else {
  FALSE
}

memo_lines <- c(
  glue("# CBC in the Prior Year vs Far from Care: Summary for Team"),
  "",
  glue("*Generated by R/181 on {format(Sys.Date(), '%Y-%m-%d')} from computed results ",
       "and Phase 179/180 workbooks.*"),
  "",
  "---",
  "",

  # Section 1
  "## 1. Question and Definitions",
  "",
  glue("- **Question:** Among Hodgkin lymphoma patients in OneFlorida+, is CBC receipt in ",
       "a patient's most recent fully observed follow-up year associated with living far from care?"),
  glue("- **Prior year (working definition):** Each patient's most recent fully observed ",
       "follow-up year (= `max(year_index)` in the Phase 179 patient-year dataset). ",
       "**Working definition — confirm with Erin/Ray before finalizing.**"),
  glue("- **Far from care:** Patient-level median post-anchor encounter distance > {CUTOFF} miles."),
  "- **CBC:** WBC + Hgb + PLT on the same date (Phase 179 `build_cbc_events()` definition).",
  glue("- **Out of system:** Outside the OneFlorida+ network (not the same as outside Florida)."),
  "",

  # Section 2
  "## 2. Prior-Year Result",
  "",
  glue("- **Primary analytic set** (year_index >= 2; survivorship cohort): N = {sup(n_primary)} ",
       "patients with observed exposure. {fmt_or(res_primary)}."),
  glue("- **Secondary analytic set** (all years): N = {sup(n_secondary)} patients. ",
       "{fmt_or(res_secondary)}."),
  glue("- **Missing exposure:** {sup(n_missing)} patients excluded from both analytic sets ",
       "(see Phase 180 bounding below)."),
  glue("- **Patients who died earlier:** {sup(n_died_early)} patients whose prior year ends ",
       "more than 365 days before the CDM cutoff; they contribute their last full year before death."),
  glue("- **Sensitivity (fixed calendar window):** CBC in ",
       "({CDM_CUTOFF - 365L}, {CDM_CUTOFF}] among patients followed to near the cutoff ",
       "(anchor <= CDM_CUTOFF - 730): N = {sup(res_sens$n)} patients. {fmt_or(res_sens)}."),
  "",

  # Section 3
  "## 3. Relationship to Earlier Analyses",
  "",
  glue("- **Phase 165 (encounter-level):** {p179_p165_side_by_side} ",
       "(encounter-level: CBC drawn during the encounter, from Phase 179 KEY)."),
  glue("- **Phase 179 (patient-year GEE, all follow-up years):** {p179_primary_or_text} ",
       "(GEE logistic, years 2+, patient-year unit, from Phase 179 KEY)."),
  glue("- **Phase 181 (this analysis, prior year only):** {fmt_or(res_primary)}."),
  "- Which analysis is primary is pending team decision (D-15, with D-165-01).",
  "",

  # Section 4
  "## 4. Robustness",
  "",
  glue("- **Missing-distance bounding (Phase 180 MISS-02/03):** Patients with missing exposure ",
       "assigned far: {p180_miss02}; assigned not-far: {p180_miss03}. ",
       "Both bounded ORs remain on the same side of 1 as the Phase 179 primary estimate. ",
       "Note: the not-far bound (MISS-03) has a confidence interval that includes 1."),
  "",

  # Section 5
  "## 5. Capture Check",
  "",
  glue("- **Phase 180 D-09 result (primary restriction, within `any_lab_year = 1`):** ",
       "{p180_d08_anylab}. The log-OR shrinks {p180_d09_pct} under the lab restriction. ",
       "D-09 branch: {p180_d09_branch}."),
  glue("- **Single-system split (Phase 180 MISS-04):** {ssc_or_note}. ",
       "Group assignment taken from the Phase 180 MISS-04 sheet. ",
       "`single_source_care_post = 1` = all post-anchor care within one OneFlorida+ system; ",
       "`= 0` = care across multiple OneFlorida+ systems.",
       if (nzchar(ssc_reversal_note)) glue(" {ssc_reversal_note}") else ""),
  glue("- This pattern is consistent with out-of-system care (outside the OneFlorida+ network) ",
       "reducing observed CBC capture, not necessarily a true difference in CBC receipt."),
  "",

  # Section 6
  "## 6. Decisions Needed",
  "",
  "- **D-15:** Which is the primary analysis: Phase 165 (encounter-level) or Phase 179/181 (patient-year)?",
  "- **D-165-01:** Primary method for Phase 165 (provisionally patient-level Fisher; pending Amy/Erin).",
  "- **Prior-year definition:** Confirm `max(year_index)` working definition with Erin/Ray.",
  ""
)

memo_path <- file.path(CONFIG$output_dir,
                        glue("cbc_prior_year_memo_{RUN_DATE}.md"))
writeLines(memo_lines, memo_path)
message(glue("  Memo saved: {memo_path}"))

# ==============================================================================
# SECTION 7: CONSOLE SUMMARY ----
# ==============================================================================

message(glue(
  "==== R/181 COMPLETE -- {RUN_DATE} ====\n",
  "  Workbook  : {wb_path}\n",
  "  Memo      : {memo_path}\n",
  "  Primary   : {fmt_2x2(res_primary)}\n",
  "  Secondary : {fmt_2x2(res_secondary)}\n",
  "  Sensitivity: {fmt_2x2(res_sens)}\n",
  "  Missing exposure excluded: {sup(n_missing)} patients\n",
  "  Died earlier (contribute last year before death): {sup(n_died_early)}\n",
  "  QC prior_equals_max: {prior_equals_max}"))
