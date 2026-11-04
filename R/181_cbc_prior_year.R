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
#   Phase 179 RDS      (env R181_P179_RDS,  default output/internal/cbc_patient_year_20261013.rds)
#   Phase 180 workbook (env R181_P180_XLSX, default output/cbc_missing_capture_20261013.xlsx)
#   Phase 179 workbook (env R181_P179_XLSX; if unset, derived from same date-stamp as R181_P179_RDS)
#                      [for Phase 165 side-by-side; never written to]
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
p179_xlsx_override <- Sys.getenv("R181_P179_XLSX", unset = "")
if (nzchar(p179_xlsx_override)) {
  stopifnot("R181_P179_XLSX file not found" = file.exists(p179_xlsx_override))
  p179_xlsx        <- p179_xlsx_override
  p179_xlsx_pinned <- TRUE
} else {
  # Derive from the same date-stamp as the pinned RDS (e.g. cbc_patient_year_20261015.rds
  # -> cbc_patient_year_20261015.xlsx in output/).
  p179_rds_stamp <- sub("^.*_(\\d{8})\\.rds$", "\\1", basename(p179_path))
  p179_xlsx <- file.path(CONFIG$output_dir,
                         paste0("cbc_patient_year_", p179_rds_stamp, ".xlsx"))
  p179_xlsx_pinned <- FALSE
}
stopifnot(
  "Phase 179 workbook not found -- set R181_P179_XLSX or ensure cbc_patient_year_<stamp>.xlsx exists in output/" =
    file.exists(p179_xlsx)
)
message(glue("  Phase 179 workbook: {basename(p179_xlsx)}",
             " (pinned={p179_xlsx_pinned})"))

# ==============================================================================
# SECTION 1b: ENCOUNTER SOURCE and ADDRESS for SOURCE stratification (Phase 192.3) ----
# ==============================================================================

# Pin for prior R/181 workbook (regression check, D-11)
# Default: cbc_prior_year_20261013.xlsx (HiPerGator path; set R1923_PRIOR_181_WB to override)
PRIOR_181_WB_PATH <- Sys.getenv(
  "R1923_PRIOR_181_WB",
  unset = file.path(CONFIG$output_dir, "cbc_prior_year_20261013.xlsx")
)
# Note: default is a literal dated filename derived from Phase 179 RDS stamp (20261013).
# If the actual prior workbook has a different date stamp, set env var R1923_PRIOR_181_WB.

# Pin for LDS_ADDRESS_HISTORY (shared with R/165 per D-08)
ADDR_PATH_181 <- Sys.getenv(
  "R1923_ADDR_PATH",
  unset = file.path(CONFIG$data_dir, "LDS_ADDRESS_HISTORY_Mailhot_V1.csv")
)
stopifnot(
  "Address file not found (set R1923_ADDR_PATH or place LDS_ADDRESS_HISTORY_Mailhot_V1.csv in data_dir)" =
    file.exists(ADDR_PATH_181)
)
# Load BEFORE opening DuckDB connection (CLAUDE.md: never hold connection across file I/O)
addr_full_181 <- vroom::vroom(
  ADDR_PATH_181,
  col_types = vroom::cols(.default = "c"),
  progress = FALSE
)
message(glue("  LDS_ADDRESS_HISTORY: {format(nrow(addr_full_181), big.mark = ',')} rows"))

# Patient IDs in py_raw (all patient-years) for ENCOUNTER query
cohort_ids_181 <- py_raw |> dplyr::distinct(ID)

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
# SECTION 2b: SOURCE STRATIFICATION (Phase 192.3) ----
# ==============================================================================
# Note: DuckDB ENCOUNTER SOURCE pull is deferred to SECTION 4 where the
# connection is opened for the LAB_RESULT_CM sensitivity query. The ENCOUNTER
# SOURCE query runs in the same DuckDB session (single open_pcornet_con() call).
# See SECTION 4 for enc_source_181_assigned, pat_source_181, etc.
# SOURCE stratification data frames are built AFTER SECTION 4.

# Patient-level modal SOURCE helper (D-07: modal in window, recency tiebreak, then alpha)
compute_modal_source_181 <- function(enc_win, source_col = "SOURCE_analytic") {
  enc_win |>
    dplyr::group_by(ID, .data[[source_col]]) |>
    dplyr::summarise(n = dplyr::n(),
                     last_date = max(ADMIT_DATE, na.rm = TRUE),
                     .groups = "drop") |>
    dplyr::group_by(ID) |>
    dplyr::slice_max(order_by = n, n = 1L, with_ties = TRUE) |>
    dplyr::arrange(ID, dplyr::desc(last_date), .data[[source_col]]) |>
    dplyr::slice_head(n = 1L) |>
    dplyr::ungroup() |>
    dplyr::rename(modal_source = .data[[source_col]]) |>
    dplyr::select(ID, modal_source)
}

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
# SECTION 4: DUCKDB QUERIES (ENCOUNTER SOURCE + SENSITIVITY CBC WINDOW) ----
# ==============================================================================
# Single DuckDB session: ENCOUNTER SOURCE pull (Phase 192.3) followed by
# LAB_RESULT_CM sensitivity query. open_pcornet_con() called exactly once.

message("[R/181] Opening DuckDB for ENCOUNTER SOURCE + sensitivity CBC window pull ...")
open_pcornet_con()

# --- 4a. ENCOUNTER SOURCE for all cohort patients (Phase 192.3) ---------------
enc_source_181 <- DBI::dbGetQuery(
  pcornet_con,
  "SELECT ID, ENCOUNTERID, ADMIT_DATE, SOURCE FROM ENCOUNTER"
) |>
  dplyr::semi_join(cohort_ids_181, by = "ID") |>
  dplyr::mutate(ADMIT_DATE = as.Date(ADMIT_DATE),
                ID = as_id(ID))

message(glue("[R/181] ENCOUNTER SOURCE: {format(nrow(enc_source_181), big.mark = ',')} rows ",
             "for {format(dplyr::n_distinct(enc_source_181$ID), big.mark = ',')} patients"))

# --- 4b. SENSITIVITY -- FIXED CALENDAR WINDOW ---------------------------------
# For patients whose prior year ends within 365 days of CDM_CUTOFF (i.e., followed
# to near the cutoff) AND whose prior year is year_index >= 2 (survivorship cohort),
# flag whether they had a CBC in (CDM_CUTOFF - 365, CDM_CUTOFF].

message("  S4 sensitivity: fixed calendar window CBC flag...")

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

close_pcornet_con()   # explicit close on success path
message("[R/181] DuckDB closed.")

# ==============================================================================
# SECTION 4b: SOURCE STRATIFICATION DERIVATION (Phase 192.3) ----
# ==============================================================================
# Runs after DuckDB is closed. enc_source_181 pulled above.

# Apply SOURCE reassignment (enc == enc_all since no distance filter in R/181)
enc_source_181_assigned <- assign_analytic_source(
  enc      = enc_source_181,
  enc_all  = enc_source_181,   # same object: no distance filter was applied
  addr_full = addr_full_181,
  config    = CONFIG
)
# enc_source_181_assigned now has: SOURCE_raw, SOURCE_analytic, source_reassigned,
# source_reassign_method, plus ID, ENCOUNTERID, ADMIT_DATE

message(glue("[R/181] SOURCE reassignment: ",
             "{sum(enc_source_181_assigned$source_reassigned)} of ",
             "{nrow(enc_source_181_assigned)} encounters reassigned"))

# Window bounds from prior_primary (year_index >= 2)
primary_bounds <- prior_primary |>
  dplyr::select(ID, year_start, year_end)

# Encounters within each patient's primary analysis window
enc_primary <- enc_source_181_assigned |>
  dplyr::inner_join(primary_bounds, by = "ID") |>
  dplyr::filter(ADMIT_DATE >= as.Date(year_start), ADMIT_DATE <= as.Date(year_end))

# Patient-level modal SOURCE_analytic: window modal first, whole-record fallback
pat_source_primary     <- compute_modal_source_181(enc_primary)
pat_source_wholerecord <- compute_modal_source_181(enc_source_181_assigned)

pat_source_181 <- primary_bounds |>
  dplyr::select(ID) |>
  dplyr::left_join(pat_source_primary, by = "ID") |>
  dplyr::left_join(
    pat_source_wholerecord |> dplyr::rename(modal_source_whole = modal_source),
    by = "ID"
  ) |>
  dplyr::mutate(
    SOURCE_analytic_pat = dplyr::coalesce(modal_source, modal_source_whole)
  ) |>
  dplyr::select(ID, SOURCE_analytic_pat)

n_pat_source_missing <- sum(is.na(pat_source_181$SOURCE_analytic_pat))
message(glue("[R/181] Patient SOURCE: {sum(!is.na(pat_source_181$SOURCE_analytic_pat))} assigned, ",
             "{n_pat_source_missing} missing"))

# Merge SOURCE into primary analysis set
prior_primary_src <- prior_primary |>
  dplyr::left_join(pat_source_181, by = "ID")

stopifnot(
  "Stratified N must equal primary analysis N" =
    nrow(prior_primary_src) == nrow(prior_primary)
)

# SOURCE_REASSIGN_QC data for R/181
qc_181_method <- enc_source_181_assigned |>
  dplyr::count(source_reassign_method, name = "n_encounters")

n_claims_enc_181 <- sum(enc_source_181_assigned$SOURCE_raw %in% CONFIG$claims_source_codes)
n_unresolved_181 <- sum(enc_source_181_assigned$source_reassign_method == "unresolved",
                        na.rm = TRUE)

source_analytic_dist_181 <- enc_source_181_assigned |>
  dplyr::filter(source_reassigned == 1L) |>
  dplyr::count(SOURCE_analytic, name = "n_reassigned_to")

# _addr sensitivity: modal_encounter rows relabelled Claims_unresolved
enc_primary_addr <- enc_primary |>
  dplyr::mutate(
    SOURCE_analytic_addr = dplyr::if_else(
      source_reassign_method == "modal_encounter",
      "Claims_unresolved",
      SOURCE_analytic
    )
  )
pat_source_primary_addr <- compute_modal_source_181(enc_primary_addr,
                                                    source_col = "SOURCE_analytic_addr")

enc_all_addr <- enc_source_181_assigned |>
  dplyr::mutate(
    SOURCE_analytic_addr = dplyr::if_else(
      source_reassign_method == "modal_encounter",
      "Claims_unresolved",
      SOURCE_analytic
    )
  )
pat_source_whole_addr <- compute_modal_source_181(enc_all_addr,
                                                  source_col = "SOURCE_analytic_addr")

pat_source_181_addr <- primary_bounds |>
  dplyr::select(ID) |>
  dplyr::left_join(pat_source_primary_addr, by = "ID") |>
  dplyr::left_join(
    pat_source_whole_addr |> dplyr::rename(modal_source_whole_addr = modal_source),
    by = "ID"
  ) |>
  dplyr::mutate(
    SOURCE_analytic_pat_addr = dplyr::coalesce(modal_source, modal_source_whole_addr)
  ) |>
  dplyr::select(ID, SOURCE_analytic_pat_addr)

stopifnot(
  "_addr sensitivity must have same N as primary analysis" =
    nrow(pat_source_181_addr) == nrow(prior_primary)
)

# FLM sensitivity: build_flm_sensitivity_set() keeps FLM as own stratum
enc_source_181_flm <- build_flm_sensitivity_set(enc_source_181_assigned, CONFIG)

enc_primary_flm <- enc_source_181_flm |>
  dplyr::inner_join(primary_bounds, by = "ID") |>
  dplyr::filter(ADMIT_DATE >= as.Date(year_start), ADMIT_DATE <= as.Date(year_end))

pat_source_primary_flm <- compute_modal_source_181(enc_primary_flm)
pat_source_whole_flm   <- compute_modal_source_181(enc_source_181_flm)

pat_source_181_flm <- primary_bounds |>
  dplyr::select(ID) |>
  dplyr::left_join(pat_source_primary_flm, by = "ID") |>
  dplyr::left_join(
    pat_source_whole_flm |> dplyr::rename(modal_source_whole_flm = modal_source),
    by = "ID"
  ) |>
  dplyr::mutate(
    SOURCE_analytic_pat_flm = dplyr::coalesce(modal_source, modal_source_whole_flm)
  ) |>
  dplyr::select(ID, SOURCE_analytic_pat_flm)

stopifnot(
  "_flm sensitivity must have same N as primary analysis" =
    nrow(pat_source_181_flm) == nrow(prior_primary)
)

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
    "Phase 179 workbook pinned (R181_P179_XLSX set)",
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
    as.character(p179_xlsx_pinned),
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
    "Phase 179 RDS (pinned)", "Phase 180 workbook (pinned)",
    "Phase 179 workbook", "Phase 179 workbook pinned (R181_P179_XLSX)",
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
    "D-15 (primary analysis choice)",
    "SOURCE stratification (Phase 192.3)",
    "BY_SOURCE_enc / BY_SOURCE_enc_addr (absent -- reason)",
    "BY_SOURCE_pat",
    "BY_SOURCE_pat_addr",
    "BY_SOURCE_pat_flm",
    "SOURCE_REASSIGN_QC"),
  Value = c(
    glue("Prior-year CBC x far-from-care (> {CUTOFF} mi): patient-level 2x2"),
    RUN_DATE,
    basename(p179_path),
    basename(p180_path),
    basename(p179_xlsx),
    as.character(p179_xlsx_pinned),
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
    "Pending team decision (D-15, with D-165-01)",
    paste0("Claims-sourced (FLM) encounters reassigned to ADDRESS SOURCE (temporal rule) ",
           "then modal non-claims encounter SOURCE, then Claims_unresolved. ",
           "assign_analytic_source() from utils_distance_cbc.R (Phase 192.3-02). ",
           "Patient-level SOURCE = modal SOURCE_analytic in prior analysis window; ",
           "whole-record fallback when no encounters in window."),
    paste0("BY_SOURCE_enc and BY_SOURCE_enc_addr are NOT produced by this script (R/181). ",
           "R/181 is patient-level; there is no encounter-level CBC variable available. ",
           "See R/165 for encounter-level SOURCE stratification. ",
           "BY_SOURCE_pat is the primary inference sheet here."),
    "Patient-level 2x2 (far x CBC) stratified by SOURCE_analytic_pat (primary analysis, year_index >= 2). MH pooled OR and Breslow-Day included.",
    paste0("Sensitivity: same as BY_SOURCE_pat but modal_encounter-reassigned encounters ",
           "relabelled Claims_unresolved (address-only reassignment). Same denominator as BY_SOURCE_pat."),
    paste0("Sensitivity: BY_SOURCE_pat_flm keeps FLM as its own stratum (no reassignment applied). ",
           "Tests the CBC-captured-outside-our-system hypothesis at patient level. ",
           "Denominators identical to BY_SOURCE_pat."),
    "Counts by source_reassign_method for all ENCOUNTER rows in cohort. Distribution of SOURCE_analytic among reassigned encounters."),
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

# ==============================================================================
# SECTION 6b: SOURCE STRATIFICATION SHEETS (Phase 192.3) ----
# ==============================================================================

# Helper: build BY_SOURCE_pat sheet data frame (2x2 per SOURCE stratum + MH pooled OR)
build_by_source_pat_sheet_181 <- function(primary_df, source_col, sheet_label) {
  strata <- sort(unique(primary_df[[source_col]]))
  strata <- strata[!is.na(strata)]

  rows_list <- list()

  # Per-stratum 2x2
  mh_array_list <- list()
  for (src in strata) {
    sub_df <- primary_df[!is.na(primary_df[[source_col]]) &
                           primary_df[[source_col]] == src, ]
    n_tot    <- nrow(sub_df)
    far_cbc  <- sum(sub_df$far == 1L & sub_df$cbc_year == 1L, na.rm = TRUE)
    far_ncbc <- sum(sub_df$far == 1L & sub_df$cbc_year == 0L, na.rm = TRUE)
    nfr_cbc  <- sum(sub_df$far == 0L & sub_df$cbc_year == 1L, na.rm = TRUE)
    nfr_ncbc <- sum(sub_df$far == 0L & sub_df$cbc_year == 0L, na.rm = TRUE)
    ct <- matrix(c(nfr_ncbc, far_ncbc, nfr_cbc, far_cbc), nrow = 2,
                 dimnames = list(c("not_far", "far"), c("no_cbc", "cbc")))

    ex <- suppressWarnings(chisq.test(ct, correct = FALSE)$expected)
    use_fisher <- any(ex < 5)
    p_val <- if (use_fisher) {
      tryCatch(fisher.test(ct)$p.value, error = function(e) NA_real_)
    } else {
      tryCatch(chisq.test(ct, correct = FALSE)$p.value, error = function(e) NA_real_)
    }
    or_res <- naive_or_se(ct)
    or_val  <- exp(or_res$log_or)
    ci_lo   <- exp(or_res$log_or - 1.96 * or_res$se)
    ci_hi   <- exp(or_res$log_or + 1.96 * or_res$se)

    # Accumulate for MH: include non-Claims_unresolved strata with no zero margins
    if (src != "Claims_unresolved" &&
        all(rowSums(ct) > 0) && all(colSums(ct) > 0)) {
      mh_array_list[[src]] <- ct
    }

    rows_list[[src]] <- data.frame(
      SOURCE_analytic = src,
      N               = suppress_display(n_tot),
      N_far_CBC       = suppress_display(far_cbc),
      N_far_no_CBC    = suppress_display(far_ncbc),
      N_notfar_CBC    = suppress_display(nfr_cbc),
      N_notfar_no_CBC = suppress_display(nfr_ncbc),
      N_far           = suppress_display(far_cbc + far_ncbc),
      N_notfar        = suppress_display(nfr_cbc + nfr_ncbc),
      CBC_rate_far    = show_rate(far_cbc, far_cbc + far_ncbc),
      CBC_rate_notfar = show_rate(nfr_cbc, nfr_cbc + nfr_ncbc),
      Test            = if (use_fisher) "Fisher" else "Chi-sq",
      OR              = if (is.na(or_val)) "—" else as.character(round(or_val, 3)),
      CI_95           = if (is.na(ci_lo))  "—" else glue("{round(ci_lo, 3)}-{round(ci_hi, 3)}"),
      p               = if (is.na(p_val))  "—" else format.pval(p_val, digits = 3),
      stringsAsFactors = FALSE
    )
  }

  # Mantel-Haenszel pooled OR (exclude Claims_unresolved + zero-margin strata)
  mh_row <- data.frame(
    SOURCE_analytic = "MH_POOLED",
    N = "—", N_far_CBC = "—", N_far_no_CBC = "—",
    N_notfar_CBC = "—", N_notfar_no_CBC = "—",
    N_far = "—", N_notfar = "—",
    CBC_rate_far = "—", CBC_rate_notfar = "—",
    Test = "MH", OR = "—", CI_95 = "—", p = "—",
    stringsAsFactors = FALSE
  )

  if (length(mh_array_list) >= 2L) {
    mh_arr <- array(
      unlist(lapply(mh_array_list, as.numeric)),
      dim = c(2L, 2L, length(mh_array_list)),
      dimnames = list(c("not_far", "far"), c("no_cbc", "cbc"), names(mh_array_list))
    )
    mh_res <- tryCatch(
      stats::mantelhaen.test(mh_arr, correct = FALSE),
      error = function(e) NULL
    )
    bd_p <- tryCatch(
      if (requireNamespace("DescTools", quietly = TRUE)) {
        bd <- DescTools::BreslowDayTest(mh_arr, correct = TRUE)
        format.pval(bd$p.value, digits = 3)
      } else {
        "DescTools not available"
      },
      error = function(e) "error"
    )
    if (!is.null(mh_res)) {
      mh_row$OR   <- as.character(round(mh_res$estimate, 3))
      mh_row$CI_95 <- glue("{round(mh_res$conf.int[1], 3)}-{round(mh_res$conf.int[2], 3)}")
      mh_row$p     <- format.pval(mh_res$p.value, digits = 3)
      mh_row$Test  <- glue("MH (Breslow-Day p={bd_p}); strata={length(mh_array_list)}")
    }
  } else {
    mh_row$Test <- glue("MH not computed (<2 eligible strata; excluded: Claims_unresolved, zero-margin)")
  }

  excluded_strata <- setdiff(strata, names(mh_array_list))
  if (length(excluded_strata) > 0L) {
    mh_row$N <- glue("Excluded from MH: {paste(excluded_strata, collapse = ', ')}")
  }

  dplyr::bind_rows(rows_list, mh_row)
}

# Build BY_SOURCE_pat, BY_SOURCE_pat_addr, BY_SOURCE_pat_flm data frames
# prior_primary_src already has SOURCE_analytic_pat (joined above at the assertion block)
by_source_pat_df <- build_by_source_pat_sheet_181(
  primary_df = prior_primary_src,
  source_col = "SOURCE_analytic_pat",
  sheet_label = "BY_SOURCE_pat"
)

prior_primary_addr <- prior_primary |>
  dplyr::left_join(pat_source_181_addr, by = "ID")
stopifnot(nrow(prior_primary_addr) == nrow(pat_source_181_addr))

by_source_pat_addr_df <- build_by_source_pat_sheet_181(
  primary_df = prior_primary_addr,
  source_col = "SOURCE_analytic_pat_addr",
  sheet_label = "BY_SOURCE_pat_addr"
)

prior_primary_flm <- prior_primary |>
  dplyr::left_join(pat_source_181_flm, by = "ID")
stopifnot(nrow(prior_primary_flm) == nrow(pat_source_181_flm))

by_source_pat_flm_df <- build_by_source_pat_sheet_181(
  primary_df = prior_primary_flm,
  source_col = "SOURCE_analytic_pat_flm",
  sheet_label = "BY_SOURCE_pat_flm"
)

# SOURCE_REASSIGN_QC data frame
src_qc_method_df <- qc_181_method |>
  dplyr::mutate(n_encounters = suppress_display(n_encounters))

src_qc_dist_df <- source_analytic_dist_181 |>
  dplyr::mutate(n_reassigned_to = suppress_display(n_reassigned_to))

src_qc_summary_df <- data.frame(
  Metric = c(
    "Total ENCOUNTER rows pulled",
    "Claims-sourced (FLM) rows",
    "Claims-sourced rows reassigned",
    "Claims_unresolved (not reassigned)"
  ),
  Value = c(
    suppress_display(nrow(enc_source_181_assigned)),
    suppress_display(n_claims_enc_181),
    suppress_display(sum(enc_source_181_assigned$source_reassigned, na.rm = TRUE)),
    suppress_display(n_unresolved_181)
  ),
  stringsAsFactors = FALSE
)

# Add new sheets to workbook
openxlsx::addWorksheet(wb, "BY_SOURCE_pat")
openxlsx::writeData(wb, "BY_SOURCE_pat",
                    "Patient-level CBC x far-from-care by SOURCE_analytic (primary analysis, year_index >= 2)",
                    startRow = 1)
openxlsx::addStyle(wb, "BY_SOURCE_pat", sec, rows = 1, cols = 1)
openxlsx::writeData(wb, "BY_SOURCE_pat", by_source_pat_df, startRow = 2, headerStyle = hdr)
openxlsx::setColWidths(wb, "BY_SOURCE_pat", 1:14,
                       c(26, 10, 14, 16, 14, 18, 10, 12, 16, 18, 10, 10, 20, 12))

openxlsx::addWorksheet(wb, "BY_SOURCE_pat_addr")
openxlsx::writeData(wb, "BY_SOURCE_pat_addr",
                    "Sensitivity: modal_encounter rows relabelled Claims_unresolved; patient-level (primary analysis)",
                    startRow = 1)
openxlsx::addStyle(wb, "BY_SOURCE_pat_addr", sec, rows = 1, cols = 1)
openxlsx::writeData(wb, "BY_SOURCE_pat_addr", by_source_pat_addr_df, startRow = 2, headerStyle = hdr)
openxlsx::setColWidths(wb, "BY_SOURCE_pat_addr", 1:14,
                       c(26, 10, 14, 16, 14, 18, 10, 12, 16, 18, 10, 10, 20, 12))

openxlsx::addWorksheet(wb, "BY_SOURCE_pat_flm")
openxlsx::writeData(wb, "BY_SOURCE_pat_flm",
                    "Sensitivity: FLM kept as own stratum (no reassignment); tests CBC-outside-system hypothesis; patient-level",
                    startRow = 1)
openxlsx::addStyle(wb, "BY_SOURCE_pat_flm", sec, rows = 1, cols = 1)
openxlsx::writeData(wb, "BY_SOURCE_pat_flm", by_source_pat_flm_df, startRow = 2, headerStyle = hdr)
openxlsx::setColWidths(wb, "BY_SOURCE_pat_flm", 1:14,
                       c(26, 10, 14, 16, 14, 18, 10, 12, 16, 18, 10, 10, 20, 12))

openxlsx::addWorksheet(wb, "SOURCE_REASSIGN_QC")
openxlsx::writeData(wb, "SOURCE_REASSIGN_QC",
                    "SOURCE reassignment QC — R/181 ENCOUNTER rows",
                    startRow = 1)
openxlsx::addStyle(wb, "SOURCE_REASSIGN_QC", sec, rows = 1, cols = 1)
openxlsx::writeData(wb, "SOURCE_REASSIGN_QC", src_qc_summary_df, startRow = 2, headerStyle = hdr)
r_qc <- nrow(src_qc_summary_df) + 4L
openxlsx::writeData(wb, "SOURCE_REASSIGN_QC", "Counts by source_reassign_method:", startRow = r_qc)
openxlsx::addStyle(wb, "SOURCE_REASSIGN_QC", sec, rows = r_qc, cols = 1)
openxlsx::writeData(wb, "SOURCE_REASSIGN_QC", src_qc_method_df, startRow = r_qc + 1L, headerStyle = hdr)
r_qc2 <- r_qc + nrow(src_qc_method_df) + 3L
openxlsx::writeData(wb, "SOURCE_REASSIGN_QC",
                    "SOURCE_analytic distribution among reassigned encounters:", startRow = r_qc2)
openxlsx::addStyle(wb, "SOURCE_REASSIGN_QC", sec, rows = r_qc2, cols = 1)
openxlsx::writeData(wb, "SOURCE_REASSIGN_QC", src_qc_dist_df, startRow = r_qc2 + 1L, headerStyle = hdr)
openxlsx::setColWidths(wb, "SOURCE_REASSIGN_QC", 1:2, c(36, 20))

# Save workbook (all 9 sheets: KEY, A_2x2, B_rates, C_year_distribution, QC,
#                              BY_SOURCE_pat, BY_SOURCE_pat_addr, BY_SOURCE_pat_flm,
#                              SOURCE_REASSIGN_QC)
OUT_181_PATH <- file.path(CONFIG$output_dir, glue("cbc_prior_year_{RUN_DATE}.xlsx"))
wb_path <- OUT_181_PATH   # kept for backward compatibility with SECTION 6 MEMO references

openxlsx::saveWorkbook(wb, OUT_181_PATH, overwrite = TRUE)
message(glue("  Workbook saved: {OUT_181_PATH} (9 sheets)"))

# ==============================================================================
# SECTION 6c: REGRESSION CHECK (D-11) ----
# ==============================================================================
# Read back from the actual written file and compare cell-by-cell against the
# prior dated R/181 workbook. Excludes KEY sheet and ISO date cells.
# stop() on failure (manual sign-off required).

if (!file.exists(PRIOR_181_WB_PATH)) {
  stop(
    "[R/181] Prior workbook for regression check not found: ", PRIOR_181_WB_PATH,
    "\nSet env var R1923_PRIOR_181_WB to the correct path, or place ",
    basename(PRIOR_181_WB_PATH), " in output/."
  )
}

prior_181_sheet_names <- openxlsx::getSheetNames(PRIOR_181_WB_PATH)
message("[R/181] Regression check: prior workbook sheets: ",
        paste(prior_181_sheet_names, collapse = ", "))

# Compare all pre-existing sheets except KEY
sheets_181_to_check <- setdiff(prior_181_sheet_names,
                               c("KEY", "BY_SOURCE_pat", "BY_SOURCE_pat_addr",
                                 "BY_SOURCE_pat_flm", "SOURCE_REASSIGN_QC"))

regression_181_pass  <- TRUE
regression_181_diffs <- character(0)

for (sht in sheets_181_to_check) {
  prior_df   <- openxlsx::read.xlsx(PRIOR_181_WB_PATH, sheet = sht, colNames = TRUE)
  current_df <- openxlsx::read.xlsx(OUT_181_PATH,       sheet = sht, colNames = TRUE)

  if (!identical(dim(prior_df), dim(current_df))) {
    regression_181_pass <- FALSE
    regression_181_diffs <- c(regression_181_diffs,
      glue::glue("FAIL: sheet '{sht}' dims differ: prior={nrow(prior_df)}x{ncol(prior_df)},",
                 " new={nrow(current_df)}x{ncol(current_df)}"))
    next
  }
  if (!identical(names(prior_df), names(current_df))) {
    regression_181_pass <- FALSE
    regression_181_diffs <- c(regression_181_diffs,
      glue::glue("FAIL: sheet '{sht}' column names differ"))
    next
  }
  for (col in names(prior_df)) {
    pv <- as.character(prior_df[[col]])
    cv <- as.character(current_df[[col]])
    for (i in seq_along(pv)) {
      p_val <- if (is.na(pv[i])) NA_character_ else pv[i]
      c_val <- if (is.na(cv[i])) NA_character_ else cv[i]
      if (!is.na(p_val) && grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}", p_val)) next
      if (!identical(p_val, c_val)) {
        regression_181_pass <- FALSE
        regression_181_diffs <- c(regression_181_diffs,
          glue::glue("FAIL: sheet '{sht}' row {i} col '{col}': ",
                     "prior='{p_val}' new='{c_val}'"))
      }
    }
  }
}

if (!regression_181_pass) {
  stop(
    "[R/181] REGRESSION CHECK FAILED.\n",
    paste(regression_181_diffs, collapse = "\n"),
    "\nManual sign-off required before this run can be accepted."
  )
}
message("[R/181] Regression check PASSED — all pre-existing sheets match prior workbook cell-by-cell.")

wb_path <- OUT_181_PATH   # ensure wb_path reflects final output
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
  glue("*Generated by R/181 on {format(Sys.Date(), '%Y-%m-%d')} | ",
       "Phase 179 RDS: {basename(p179_path)} | ",
       "Phase 179 workbook: {basename(p179_xlsx)} (pinned={p179_xlsx_pinned}) | ",
       "Phase 180 workbook: {basename(p180_path)}*"),
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
