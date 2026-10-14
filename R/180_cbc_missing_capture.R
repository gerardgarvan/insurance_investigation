# ==============================================================================
# 180_cbc_missing_capture.R -- Missing-exposure bounding (MISS-01..03) and
#                               CBC capture check (MISS-04)
# ==============================================================================
#
# Purpose:
#   Read-only checks on the Phase 179 patient-year analysis.
#   (1) MISS-01: Break down patients with missing exposure by reason.
#   (2) MISS-02/03: Bound the Phase 179 OR by assigning missing patients far=1
#       or far=0 and refitting. Apply locked D-05 decision rule.
#   (3) MISS-04: Per-patient-year flags for any non-CBC lab (any_lab_year) and
#       any in-system encounter (any_enc_year); fit capture-sensitivity models;
#       apply locked D-09 decision rule.
#   All counts 1-10 suppressed; rates only when both counts >= 11.
#
# Inputs:
#   Phase 179 RDS: env R180_P179_RDS, else output/internal/cbc_patient_year_20261013.rds
#   R/122 enc_distance RDS: env R180_R122_RDS, else most recent encounter_distance*.rds
#   R/169 single_source_care RDS: env R180_R169_RDS, else most recent single_source_care*.rds
#   DuckDB: ENCOUNTER (enc_dates), LAB_RESULT_CM (lab_dates, source fields)
#
# Outputs:
#   output/cbc_missing_capture_<YYYYMMDD>.xlsx  (KEY | MISS-01 | MISS-02-03 | MISS-04)
#   output/internal/cbc_missing_capture_<YYYYMMDD>.rds  (Phase 179 cols + flags + reason)
#
# Requirements: MISS-01, MISS-02, MISS-03, MISS-04   Decisions: 180-CONTEXT D-01..D-12
#
# Usage (HiPerGator, repo root):
#   module load R/4.5 ; R
#   source("R/180_cbc_missing_capture.R", local = new.env(parent = globalenv()))
# ==============================================================================

# ==============================================================================
# SECTION 0: SETUP ----
# ==============================================================================

source("R/00_config.R")

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(geepack)
  library(openxlsx)
  library(glue)
})
stopifnot("dplyr >= 1.1.0 required for inequality joins" =
            utils::packageVersion("dplyr") >= "1.1.0")

RUN_DATE <- format(Sys.Date(), "%Y%m%d")
message(glue("==== R/180 cbc_missing_capture -- RUN DATE {RUN_DATE} ===="))

CUTOFF <- CONFIG$far_from_care_cutoff_mi
stopifnot("far_from_care_cutoff_mi must be a positive number" =
            is.numeric(CUTOFF) && length(CUTOFF) == 1L && !is.na(CUTOFF) && CUTOFF > 0)

GEE_CORSTR <- CONFIG$distance_gee_corstr
stopifnot("distance_gee_corstr must be a non-empty string" =
            is.character(GEE_CORSTR) && length(GEE_CORSTR) == 1L && nzchar(GEE_CORSTR))
if (GEE_CORSTR == "unstructured")
  warning("corstr = 'unstructured' with unequal cluster sizes can be slow or unstable.")

stopifnot("EXTRACT_DATE must be defined by R/00_config.R" =
            exists("EXTRACT_DATE") && nzchar(as.character(EXTRACT_DATE)))
CDM_CUTOFF <- if (inherits(EXTRACT_DATE, "Date")) EXTRACT_DATE else
  as.Date(as.character(EXTRACT_DATE), tryFormats = c("%Y-%m-%d", "%Y%m%d"), optional = TRUE)
stopifnot("EXTRACT_DATE could not be parsed as a date (expected YYYY-MM-DD or YYYYMMDD)" =
            length(CDM_CUTOFF) == 1L && !is.na(CDM_CUTOFF))

message(glue("  CDM cutoff {CDM_CUTOFF} | far > {CUTOFF} mi | corstr {GEE_CORSTR}"))

# CBC + hematology LOINCs excluded from the non-CBC lab flag (D-06)
EXCLUDE_LOINCS <- c("6690-2", "718-7", "777-3", "4544-3", "789-8", "787-2", "785-6",
                    "786-4", "788-0", "770-8", "26499-4", "731-0", "58410-2",
                    "57021-8", "57782-5")

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

run_gee <- function(data, outcome, exposure, label) {
  d <- data |>
    dplyr::filter(!is.na(.data[[exposure]])) |>
    dplyr::arrange(ID, year_index) |>
    dplyr::mutate(year_index_cat = droplevels(year_index_cat),
                  y  = .data[[outcome]],
                  x  = .data[[exposure]],
                  cl = as.integer(factor(ID, levels = unique(ID))))
  base <- list(label = label, n_py = nrow(d), n_pat = dplyr::n_distinct(d$ID))
  warns <- character(0)
  t0 <- Sys.time()
  fit <- tryCatch(
    withCallingHandlers(
      geepack::geeglm(y ~ x + year_index_cat, data = d, id = cl,
                      family = binomial("logit"), corstr = GEE_CORSTR),
      warning = function(w) { warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning") }),
    error = function(e) e)
  secs <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)

  if (inherits(fit, "error")) {
    m <- matrix(as.numeric(table(factor(d$x, 0:1), factor(d$y, 0:1))), 2)
    return(c(base, list(method = "CRUDE FALLBACK (GEE error)",
                        or = crude_or(m[1, 1], m[1, 2], m[2, 1], m[2, 2]),
                        ci_lo = NA_real_, ci_hi = NA_real_, p = NA_real_,
                        warnings = paste(unique(warns), collapse = " | "),
                        error = conditionMessage(fit), secs = secs)))
  }
  if (!is.null(fit$geese$error) && fit$geese$error != 0)
    warns <- c(warns, glue("geese error code {fit$geese$error} (possible non-convergence)"))
  cf <- summary(fit)$coefficients
  b <- cf["x", "Estimate"]; se <- cf["x", "Std.err"]
  c(base, list(method = glue("GEE ({GEE_CORSTR})"),
               or = exp(b), ci_lo = exp(b - 1.96 * se), ci_hi = exp(b + 1.96 * se),
               p = cf["x", "Pr(>|W|)"],
               warnings = paste(unique(warns), collapse = " | "),
               error = NA_character_, secs = secs))
}

fmt_result <- function(r) {
  if (grepl("FALLBACK", r$method))
    return(glue("{r$label}: FALLBACK crude OR {round(r$or, 2)} (no CI); error: {r$error}"))
  glue("{r$label}: OR {round(r$or, 2)} ({round(r$ci_lo, 2)}-{round(r$ci_hi, 2)}), ",
       "p={format.pval(r$p, digits = 3)}, {r$method}, {r$secs}s",
       "{if (nzchar(r$warnings)) paste0('; WARNINGS: ', r$warnings) else ''}")
}

KEY_META <- list()   # accumulates rows for the KEY sheet

# ==============================================================================
# SECTION 1: PINNED INPUTS ----
# ==============================================================================

# --- 1a. Phase 179 RDS --------------------------------------------------------
p179_override <- Sys.getenv("R180_P179_RDS", unset = "")
if (nzchar(p179_override)) {
  stopifnot("R180_P179_RDS file not found" = file.exists(p179_override))
  p179_path <- p179_override; p179_pinned <- TRUE
} else {
  p179_path <- file.path(CONFIG$output_dir, "internal", "cbc_patient_year_20261013.rds")
  p179_pinned <- FALSE
}
stopifnot("Phase 179 RDS not found -- set R180_P179_RDS or confirm cbc_patient_year_20261013.rds exists" =
            file.exists(p179_path))
KEY_META[["p179_rds"]] <- basename(p179_path)
message(glue("  Phase 179 RDS: {basename(p179_path)} (pinned={p179_pinned})"))

py_raw <- readRDS(p179_path)

# Required columns check
req_cols <- c("ID", "year_index", "year_start", "year_end", "cbc_year", "cbc_year_broad",
              "median_distance", "far", "exposure_missing", "triage")
missing_cols <- setdiff(req_cols, names(py_raw))
stopifnot("Phase 179 RDS missing required columns" = length(missing_cols) == 0L)

py_raw <- py_raw |>
  dplyr::mutate(ID = as_id(ID))

# Rebuild year_index_cat (needed for run_gee)
py_raw <- py_raw |>
  dplyr::mutate(year_index_cat = factor(
    dplyr::if_else(year_index >= 5L, "5+", as.character(year_index)),
    levels = c("1", "2", "3", "4", "5+")))

message(glue("  Phase 179 RDS: {format(nrow(py_raw), big.mark = ',')} patient-years, ",
             "{dplyr::n_distinct(py_raw$ID)} patients"))

# --- 1b. enc_distance (R/122) -------------------------------------------------
r122_override <- Sys.getenv("R180_R122_RDS", unset = "")
if (nzchar(r122_override)) {
  stopifnot("R180_R122_RDS file not found" = file.exists(r122_override))
  enc_dist_path <- r122_override; r122_pinned <- TRUE
} else {
  cand <- list.files(CONFIG$output_dir, "^encounter_distance.*\\.rds$", full.names = TRUE)
  stopifnot("enc_distance RDS not found -- run R/122 or set R180_R122_RDS" = length(cand) > 0L)
  enc_dist_path <- cand[which.max(file.mtime(cand))]; r122_pinned <- FALSE
}
enc_distance <- readRDS(enc_dist_path)
stopifnot("enc_distance missing required columns" =
            all(c("ID", "ADMIT_DATE", "distance_status") %in% names(enc_distance)))
enc_distance <- enc_distance |>
  dplyr::mutate(ID = as_id(ID), ADMIT_DATE = as.Date(ADMIT_DATE))
KEY_META[["r122_rds"]] <- glue("{basename(enc_dist_path)} (pinned={r122_pinned})")
message(glue("  enc_distance: {basename(enc_dist_path)} ({format(nrow(enc_distance), big.mark = ',')} rows; pinned={r122_pinned})"))

# --- 1c. R/169 single_source_care ---------------------------------------------
r169_override <- Sys.getenv("R180_R169_RDS", unset = "")
if (nzchar(r169_override)) {
  stopifnot("R180_R169_RDS file not found" = file.exists(r169_override))
  r169_path <- r169_override; r169_pinned <- TRUE
} else {
  cand <- list.files(file.path(CONFIG$output_dir, "internal"),
                     "^single_source_care.*\\.rds$", full.names = TRUE)
  if (length(cand) == 0L)
    cand <- list.files(CONFIG$output_dir, "^single_source_care.*\\.rds$", full.names = TRUE)
  stopifnot("R/169 single_source_care RDS not found -- run R/169 or set R180_R169_RDS" = length(cand) > 0L)
  r169_path <- cand[which.max(file.mtime(cand))]; r169_pinned <- FALSE
}
r169_raw <- readRDS(r169_path)
# accept data.frame or list
ssc_df <- if (is.data.frame(r169_raw)) r169_raw else r169_raw
ssc_key <- intersect(c("ID", "PATID"), names(ssc_df))[1]
stopifnot("R/169 RDS lacks ID/PATID or single_source_care_post" =
            !is.na(ssc_key) && "single_source_care_post" %in% names(ssc_df))
ssc_map <- ssc_df |>
  dplyr::transmute(ID = as_id(.data[[ssc_key]]),
                   single_source_care_post = single_source_care_post) |>
  dplyr::distinct(ID, .keep_all = TRUE)
KEY_META[["r169_rds"]] <- glue("{basename(r169_path)} (pinned={r169_pinned})")
message(glue("  R/169 single_source_care: {basename(r169_path)} ({nrow(ssc_map)} patients; pinned={r169_pinned})"))

# --- 1d. Triage from Phase 179 RDS --------------------------------------------
# No separate R/121 load; use `triage` column already in py_raw (D-01)

# ==============================================================================
# SECTION 1e: REPRODUCTION CHECK ----
# ==============================================================================

py_primary_ref <- py_raw |>
  dplyr::filter(!exposure_missing, year_index >= 2L)

ref <- run_gee(py_primary_ref, "cbc_year", "far", "Phase 179 primary (recomputed)")

# Phase 182 D-22a: Read expected OR/CI from the Phase 179 workbook matching the pinned RDS.
# Derive the xlsx date from the RDS name (cbc_patient_year_YYYYMMDD.rds).
P179_PRIMARY_LABEL <- "Primary: years 2+"  # exact label in Model_Results (R/179 line ~439)
.p179_rds_date_match <- regmatches(basename(p179_path), regexpr("\\d{8}", basename(p179_path)))
if (length(.p179_rds_date_match) == 1L && nzchar(.p179_rds_date_match)) {
  .p179_xlsx_path <- file.path(CONFIG$output_dir, glue("cbc_patient_year_{.p179_rds_date_match}.xlsx"))
} else {
  .p179_xlsx_path <- ""
}
stopifnot(
  "Phase 179 workbook not found for reproduction check (D-22a) -- confirm xlsx exists alongside RDS" =
    nzchar(.p179_xlsx_path) && file.exists(.p179_xlsx_path)
)
.p179_model_results <- tryCatch(
  openxlsx::read.xlsx(.p179_xlsx_path, sheet = "Model_Results"),
  error = function(e) stop(glue("D-22a: Cannot read Model_Results from {basename(.p179_xlsx_path)}: {e$message}"))
)
stopifnot("D-22a: Model_Results sheet missing Analysis column" = "Analysis" %in% names(.p179_model_results))
.p179_primary_rows <- .p179_model_results[.p179_model_results$Analysis == P179_PRIMARY_LABEL, ]
if (nrow(.p179_primary_rows) != 1L) stop(glue(
  "D-22a: exactly one row matching '{P179_PRIMARY_LABEL}' required in Model_Results; ",
  "found {nrow(.p179_primary_rows)} (check label or workbook)"
))
.p179_ref <- .p179_primary_rows[1, ]
message(glue("  D-22a repro reference: OR={round(as.numeric(.p179_ref$OR), 2)}, ",
             "CI={round(as.numeric(.p179_ref$CI_low), 2)}-{round(as.numeric(.p179_ref$CI_high), 2)}, ",
             "from {basename(.p179_xlsx_path)} '{P179_PRIMARY_LABEL}'"))

if (round(ref$or, 2) != round(as.numeric(.p179_ref$OR), 2)) stop(glue(
  "Reproduction check FAILED: round(OR, 2) != {round(as.numeric(.p179_ref$OR), 2)}  ",
  "-- verify you are using the Phase 179 RDS matching {basename(.p179_xlsx_path)}"
))
if (round(ref$ci_lo, 2) != round(as.numeric(.p179_ref$CI_low), 2)) stop(glue(
  "Reproduction check FAILED: round(CI_low, 2) != {round(as.numeric(.p179_ref$CI_low), 2)}"
))
if (round(ref$ci_hi, 2) != round(as.numeric(.p179_ref$CI_high), 2)) stop(glue(
  "Reproduction check FAILED: round(CI_high, 2) != {round(as.numeric(.p179_ref$CI_high), 2)}"
))
message(glue("  Reproduction check PASSED: {fmt_result(ref)}"))

KEY_META[["repro_check"]] <- glue("PASSED: {fmt_result(ref)}")

# ==============================================================================
# SECTION 2: DUCKDB PULLS ----
# ==============================================================================

cohort_ids <- unique(py_raw$ID)
id_sql     <- paste(sprintf("'%s'", gsub("'", "''", cohort_ids)), collapse = ", ")

opened_here <- FALSE
if (!exists("pcornet_con", envir = .GlobalEnv)) { open_pcornet_con(); opened_here <- TRUE }

# Resolve ENCOUNTER id field
enc_fld <- toupper(DBI::dbListFields(pcornet_con, "ENCOUNTER"))
enc_id  <- intersect(c("ID", "PATID"), enc_fld)[1]
stopifnot("ENCOUNTER has neither ID nor PATID" = !is.na(enc_id))

# enc_dates: all ENC_TYPE, cohort only
enc_dates_raw <- DBI::dbGetQuery(pcornet_con, sprintf(
  "SELECT DISTINCT %s AS ID, TRY_CAST(ADMIT_DATE AS DATE) AS admit_date
   FROM ENCOUNTER
   WHERE %s IN (%s)
     AND ADMIT_DATE IS NOT NULL",
  enc_id, enc_id, id_sql))
enc_dates <- enc_dates_raw |>
  dplyr::transmute(ID = as_id(ID), admit_date = as.Date(admit_date)) |>
  dplyr::filter(!is.na(admit_date)) |>
  dplyr::distinct()
message(glue("  enc_dates: {format(nrow(enc_dates), big.mark = ',')} patient-dates from ENCOUNTER"))

# Resolve LAB_RESULT_CM id field
lab_fld <- toupper(DBI::dbListFields(pcornet_con, "LAB_RESULT_CM"))
lab_id  <- intersect(c("ID", "PATID"), lab_fld)[1]
stopifnot("LAB_RESULT_CM has neither ID nor PATID" = !is.na(lab_id))

exclude_loinc_sql <- paste(sprintf("'%s'", EXCLUDE_LOINCS), collapse = ", ")

# lab_dates: non-CBC/hematology labs, cohort only (single push-down query)
lab_dates_raw <- DBI::dbGetQuery(pcornet_con, sprintf(
  "SELECT DISTINCT %s AS ID,
          COALESCE(TRY_CAST(RESULT_DATE AS DATE),
                   TRY_CAST(SPECIMEN_DATE AS DATE),
                   TRY_CAST(LAB_ORDER_DATE AS DATE)) AS lab_date
   FROM LAB_RESULT_CM
   WHERE %s IN (%s)
     AND LAB_LOINC NOT IN (%s)",
  lab_id, lab_id, id_sql, exclude_loinc_sql))
lab_dates <- lab_dates_raw |>
  dplyr::transmute(ID = as_id(ID), lab_date = as.Date(lab_date)) |>
  dplyr::filter(!is.na(lab_date)) |>
  dplyr::distinct()
message(glue("  lab_dates: {format(nrow(lab_dates), big.mark = ',')} patient-dates (non-CBC/hematology labs)"))

# Source fields: LAB_RESULT_SOURCE, RESULT_LOC, and any column with SOURCE or LOC
src_cols <- lab_fld[grepl("SOURCE|LOC", lab_fld, ignore.case = FALSE)]
message(glue("  Lab source columns found: {paste(src_cols, collapse = ', ')}"))

lab_source_df <- do.call(rbind, lapply(src_cols, function(col) {
  q <- sprintf(
    "SELECT '%s' AS field, CAST(%s AS VARCHAR) AS value, COUNT(*) AS n
     FROM LAB_RESULT_CM
     WHERE %s IN (%s)
     GROUP BY CAST(%s AS VARCHAR)
     ORDER BY n DESC",
    col, col, lab_id, id_sql, col)
  res <- DBI::dbGetQuery(pcornet_con, q)
  res$n_display <- sup(res$n)
  res[, c("field", "value", "n_display")]
}))
if (is.null(lab_source_df) || nrow(lab_source_df) == 0L)
  lab_source_df <- data.frame(field = character(0), value = character(0), n_display = character(0),
                               stringsAsFactors = FALSE)

# Build lab-source caveat text
external_keywords <- c("EXTERNAL", "OUTSIDE", "EXT_")
any_external <- any(grepl(paste(external_keywords, collapse = "|"),
                           toupper(lab_source_df$value), fixed = FALSE), na.rm = TRUE)
lab_source_caveat <- if (any_external) {
  "At least one source field value may indicate an external result; see MISS-04 source counts."
} else {
  "External origin of lab results could not be determined from available fields -- absence of an 'external' category in these fields is not evidence of absence of outside results."
}
message(glue("  Lab source caveat: {lab_source_caveat}"))

if (opened_here) close_pcornet_con()

# ==============================================================================
# SECTION 3: MISS-01 AND MISS-02/03 ----
# ==============================================================================

# --- 3a. MISS-01: Anchor and reason assignment --------------------------------

# Anchor = year_start of year_index == 1 (present for every patient)
anchors_m1 <- py_raw |>
  dplyr::filter(year_index == 1L) |>
  dplyr::select(ID, anchor = year_start)

miss_pts <- py_raw |>
  dplyr::filter(exposure_missing) |>
  dplyr::distinct(ID, triage) |>
  dplyr::left_join(anchors_m1, by = "ID")

stopifnot("Some missing-exposure patients have no anchor (year_index=1)" =
            !any(is.na(miss_pts$anchor)))

# Post-anchor encounters: admit_date > anchor AND <= CDM_CUTOFF
post_enc <- enc_dates |>
  dplyr::inner_join(anchors_m1, by = "ID") |>
  dplyr::filter(admit_date > anchor, admit_date <= CDM_CUTOFF)

has_post_enc <- unique(post_enc$ID)

# Post-anchor enc_distance rows for missing-exposure patients
enc_dist_miss <- enc_distance |>
  dplyr::filter(ID %in% miss_pts$ID) |>
  dplyr::inner_join(anchors_m1, by = "ID") |>
  dplyr::filter(ADMIT_DATE > anchor, ADMIT_DATE <= CDM_CUTOFF)

has_enc_dist <- unique(enc_dist_miss$ID)

# Status-level flags per patient (among those in enc_distance)
has_computed_no_dist <- enc_dist_miss |>
  dplyr::filter(distance_status == "computed", is.na(distance_mi) | !is.finite(distance_mi)) |>
  dplyr::pull(ID) |> unique()

has_pzip_missing <- enc_dist_miss |>
  dplyr::filter(distance_status == "patient_zip_missing") |>
  dplyr::pull(ID) |> unique()

has_fzip_oor <- enc_dist_miss |>
  dplyr::filter(distance_status %in% c("facility_zip_missing", "zip_not_in_db")) |>
  dplyr::pull(ID) |> unique()

# Assign one reason per patient (priority order c, f, e, a, b, d)
assign_miss_reason <- function(id) {
  if (!id %in% has_post_enc)      return("(c) no post-anchor encounter in ENCOUNTER")
  if (!id %in% has_enc_dist)      return("(f) post-anchor encounter but not in enc_distance")
  if (id %in% has_computed_no_dist) return("(e) computed status but no distance value")
  p <- id %in% has_pzip_missing
  f <- id %in% has_fzip_oor
  if (p && !f)  return("(a) all patient_zip_missing")
  if (!p && f)  return("(b) all facility_zip_missing or zip_not_in_db")
  if (p && f)   return("(d) mixed patient_zip_missing and facility/zip issues")
  # Fallback: in enc_distance but none of the known statuses
  return("(f) post-anchor encounter but not in enc_distance")
}

miss_pts$miss_reason <- vapply(miss_pts$ID, assign_miss_reason, character(1L))

# Assert every missing patient has exactly one reason
stopifnot("Not every missing-exposure patient has exactly one miss_reason" =
            !any(is.na(miss_pts$miss_reason)))
stopifnot("Duplicate ID in miss_pts" = !anyDuplicated(miss_pts$ID))

reason_levels <- c(
  "(c) no post-anchor encounter in ENCOUNTER",
  "(f) post-anchor encounter but not in enc_distance",
  "(e) computed status but no distance value",
  "(a) all patient_zip_missing",
  "(b) all facility_zip_missing or zip_not_in_db",
  "(d) mixed patient_zip_missing and facility/zip issues"
)
miss_pts$miss_reason <- factor(miss_pts$miss_reason, levels = reason_levels)

message("  MISS-01 reason counts:")
print(table(miss_pts$miss_reason))

# Join miss_reason back to py_raw for the full dataset
py_all_m1 <- py_raw |>
  dplyr::left_join(dplyr::select(miss_pts, ID, miss_reason), by = "ID")

# Per-group summary table (patients, patient-years, CBC-year rate) -- all years and years 2+
build_miss01_summary <- function(py, miss_pts, subset_label) {
  # Missing groups
  miss_rows <- lapply(reason_levels, function(r) {
    ids_r   <- miss_pts$ID[miss_pts$miss_reason == r]
    py_r    <- dplyr::filter(py, ID %in% ids_r)
    n_pts   <- length(ids_r)
    n_py    <- nrow(py_r)
    n_cbc   <- sum(py_r$cbc_year)
    data.frame(Group = r, Patients = sup(n_pts), Patient_years = sup(n_py),
               CBC_year_rate = show_rate(n_cbc, n_py),
               stringsAsFactors = FALSE)
  })
  # Observed-exposure group
  obs_py  <- dplyr::filter(py, !exposure_missing)
  obs_pts <- dplyr::n_distinct(obs_py$ID)
  obs_cbc <- sum(obs_py$cbc_year)
  obs_row <- data.frame(
    Group = "Observed exposure (all)", Patients = sup(obs_pts),
    Patient_years = sup(nrow(obs_py)), CBC_year_rate = show_rate(obs_cbc, nrow(obs_py)),
    stringsAsFactors = FALSE)
  tbl <- rbind(do.call(rbind, miss_rows), obs_row)
  tbl$Subset <- subset_label
  tbl
}

miss01_all  <- build_miss01_summary(py_raw, miss_pts, "All years")
miss01_yr2p <- build_miss01_summary(
  dplyr::filter(py_raw, year_index >= 2L), miss_pts, "Years 2+")
miss01_df <- rbind(miss01_all, miss01_yr2p)

# Triage x reason cross-tab
triage_x_reason <- miss_pts |>
  dplyr::count(triage, miss_reason) |>
  dplyr::mutate(n_display = sup(n)) |>
  dplyr::select(triage, miss_reason, n_display) |>
  tidyr::pivot_wider(names_from = miss_reason, values_from = n_display, values_fill = "0")

message("  MISS-01 triage x reason cross-tab built")

# --- 3b. MISS-02/03: Bounding -------------------------------------------------
py_yr2p <- py_raw |> dplyr::filter(year_index >= 2L)

# Assign all missing-exposure patients far=1 (bound 1)
py_bound_far1 <- py_yr2p |>
  dplyr::mutate(far_bound = dplyr::if_else(exposure_missing, 1L, far))

# Assign all missing-exposure patients far=0 (bound 2)
py_bound_far0 <- py_yr2p |>
  dplyr::mutate(far_bound = dplyr::if_else(exposure_missing, 0L, far))

res_far1 <- run_gee(py_bound_far1, "cbc_year", "far_bound",
                    "MISS-02: missing assigned far=1, years 2+")
res_far0 <- run_gee(py_bound_far0, "cbc_year", "far_bound",
                    "MISS-03: missing assigned far=0, years 2+")

message(glue("  Phase 179 ref: {fmt_result(ref)}"))
message(glue("  MISS-02 (far=1): {fmt_result(res_far1)}"))
message(glue("  MISS-03 (far=0): {fmt_result(res_far0)}"))

# D-05 locked rule: both bounded ORs on same side of 1 as ref$or?
ref_side     <- if (ref$or > 1) "above" else "below"
far1_side    <- if (!is.na(res_far1$or) && res_far1$or > 1) "above" else "below"
far0_side    <- if (!is.na(res_far0$or) && res_far0$or > 1) "above" else "below"
both_same    <- (far1_side == ref_side) && (far0_side == ref_side)

d05_branch <- if (both_same) {
  "same side: add limitation row to R/179 KEY"
} else {
  "crosses 1: flag to Amy/Erin with D-165-01"
}

message(glue("  D-05 branch: {d05_branch}"))
KEY_META[["d05_branch"]] <- d05_branch
KEY_META[["miss02_or"]] <- glue("far=1: OR {round(res_far1$or, 3)} ({round(res_far1$ci_lo, 3)}-{round(res_far1$ci_hi, 3)})")
KEY_META[["miss03_or"]] <- glue("far=0: OR {round(res_far0$or, 3)} ({round(res_far0$ci_lo, 3)}-{round(res_far0$ci_hi, 3)})")

# MISS-02/03 summary table
miss0203_df <- data.frame(
  Analysis = c("Phase 179 primary (recomputed)", "MISS-02: missing -> far=1", "MISS-03: missing -> far=0"),
  Method   = c(ref$method, res_far1$method, res_far0$method),
  Patient_years = sup(c(ref$n_py, res_far1$n_py, res_far0$n_py)),
  Patients      = sup(c(ref$n_pat, res_far1$n_pat, res_far0$n_pat)),
  OR      = round(c(ref$or, res_far1$or, res_far0$or), 3),
  CI_low  = round(c(ref$ci_lo, res_far1$ci_lo, res_far0$ci_lo), 3),
  CI_high = round(c(ref$ci_hi, res_far1$ci_hi, res_far0$ci_hi), 3),
  p       = c(format.pval(ref$p, digits = 3), format.pval(res_far1$p, digits = 3),
              format.pval(res_far0$p, digits = 3)),
  D05_branch = c("reference", d05_branch, d05_branch),
  stringsAsFactors = FALSE)

# ==============================================================================
# SECTION 4: MISS-04 CAPTURE ----
# ==============================================================================

# --- 4a. Patient-year flags via inequality joins ------------------------------
py_keys <- dplyr::select(py_raw, ID, year_index, year_start, year_end)

any_lab_flag <- py_keys |>
  dplyr::inner_join(lab_dates,
                    by = dplyr::join_by(ID, year_start < lab_date, year_end >= lab_date)) |>
  dplyr::distinct(ID, year_index) |>
  dplyr::mutate(any_lab_year = 1L)

any_enc_flag <- py_keys |>
  dplyr::inner_join(enc_dates,
                    by = dplyr::join_by(ID, year_start < admit_date, year_end >= admit_date)) |>
  dplyr::distinct(ID, year_index) |>
  dplyr::mutate(any_enc_year = 1L)

py_m4 <- py_raw |>
  dplyr::left_join(any_lab_flag, by = c("ID", "year_index")) |>
  dplyr::left_join(any_enc_flag, by = c("ID", "year_index")) |>
  dplyr::mutate(
    any_lab_year = dplyr::coalesce(any_lab_year, 0L),
    any_enc_year = dplyr::coalesce(any_enc_year, 0L)
  ) |>
  dplyr::left_join(ssc_map, by = "ID") |>
  dplyr::left_join(dplyr::select(miss_pts, ID, miss_reason), by = "ID")

stopifnot("Row count changed in MISS-04 joins" = nrow(py_m4) == nrow(py_raw))
message(glue("  MISS-04 flags: {format(sum(py_m4$any_lab_year), big.mark=',')} py with non-CBC lab, ",
             "{format(sum(py_m4$any_enc_year), big.mark=',')} py with encounter"))

# --- 4b. Descriptives (D-07): far vs not-far share ---------------------------
desc_d07 <- function(py_sub, label) {
  far1  <- dplyr::filter(py_sub, far == 1L)
  far0  <- dplyr::filter(py_sub, far == 0L)
  data.frame(
    Subset       = label,
    PY_far       = sup(nrow(far1)),
    PY_notfar    = sup(nrow(far0)),
    AnyLab_far   = show_rate(sum(far1$any_lab_year), nrow(far1)),
    AnyLab_notfar= show_rate(sum(far0$any_lab_year), nrow(far0)),
    AnyEnc_far   = show_rate(sum(far1$any_enc_year), nrow(far1)),
    AnyEnc_notfar= show_rate(sum(far0$any_enc_year), nrow(far0)),
    stringsAsFactors = FALSE)
}

py_obs_all  <- dplyr::filter(py_m4, !exposure_missing)
py_obs_yr2p <- dplyr::filter(py_obs_all, year_index >= 2L)

desc07_df <- rbind(
  desc_d07(py_obs_all,  "All years (observed exposure)"),
  desc_d07(py_obs_yr2p, "Years 2+ (observed exposure)"))

# --- 4c. Models (D-08) and D-09 rule -----------------------------------------
pct_change <- function(or_r, or_ref) 100 * (1 - log(or_r) / log(or_ref))

d09_label <- function(chg) {
  if (is.na(chg))    return("not estimable")
  if (chg >= 25)     return("moves toward 1: consistent with out-of-system care (non-capture)")
  if (chg <= -25)    return("moves away from 1: consistent with a true difference in CBC receipt")
  return("no material change: consistent with a true difference in CBC receipt")
}

# Primary restriction: within any_lab_year == 1, years 2+
py_anylab  <- dplyr::filter(py_obs_yr2p, any_lab_year == 1L)
py_anyenc  <- dplyr::filter(py_obs_yr2p, any_enc_year == 1L)
py_ssc1    <- dplyr::filter(py_obs_yr2p, single_source_care_post == 1L)
py_ssc0    <- dplyr::filter(py_obs_yr2p, single_source_care_post == 0L)

res_anylab <- run_gee(py_anylab, "cbc_year", "far", "D-08 primary: within any_lab_year=1, years 2+")
res_anyenc <- run_gee(py_anyenc, "cbc_year", "far", "D-08 secondary: within any_enc_year=1, years 2+")
res_ssc1   <- run_gee(py_ssc1,   "cbc_year", "far", "D-08 single_source_care_post=1, years 2+")
res_ssc0   <- run_gee(py_ssc0,   "cbc_year", "far", "D-08 single_source_care_post=0, years 2+")

for (r in list(res_anylab, res_anyenc, res_ssc1, res_ssc0))
  message("  ", fmt_result(r))

# D-09 for each
make_d09_row <- function(r, is_primary = FALSE) {
  chg <- pct_change(r$or, ref$or)
  lbl <- d09_label(chg)
  data.frame(
    Analysis     = r$label,
    Primary      = if (is_primary) "YES (D-09 label)" else "",
    Method       = r$method,
    Patient_years= sup(r$n_py),
    Patients     = sup(r$n_pat),
    OR           = round(r$or, 3),
    CI_low       = round(r$ci_lo, 3),
    CI_high      = round(r$ci_hi, 3),
    p            = format.pval(r$p, digits = 3),
    Pct_change   = if (is.na(chg)) "NA" else paste0(round(chg, 1), "%"),
    D09_label    = lbl,
    Threshold_rule = ">=25%: toward 1 (non-capture); <=-25%: away from 1 (true diff); else no material change",
    stringsAsFactors = FALSE)
}

miss04_models_df <- rbind(
  make_d09_row(ref,      is_primary = FALSE),
  make_d09_row(res_anylab, is_primary = TRUE),
  make_d09_row(res_anyenc),
  make_d09_row(res_ssc1),
  make_d09_row(res_ssc0))

# Primary D-09 branch (from any_lab_year restriction)
chg_primary <- pct_change(res_anylab$or, ref$or)
d09_branch  <- d09_label(chg_primary)
message(glue("  D-09 branch (primary): {d09_branch} (pct_change={round(chg_primary, 1)}%)"))

KEY_META[["d09_branch"]] <- d09_branch
KEY_META[["d09_pct_change"]] <- glue("{round(chg_primary, 1)}%")

# ==============================================================================
# SECTION 5: WORKBOOK, RDS, REGISTRATION ----
# ==============================================================================

# --- 5a. KEY sheet ------------------------------------------------------------
key_df <- data.frame(
  Field = c(
    "Analysis", "Relation to Phase 179", "Run date",
    "Phase 179 RDS (pinned)", "enc_distance RDS", "single_source_care RDS",
    "Triage source",
    "Phase 179 reproduction check",
    "CDM cutoff", "far cutoff (mi)", "GEE corstr",
    "MISS-02 (missing -> far=1)", "MISS-03 (missing -> far=0)",
    "D-05 branch",
    "D-08 primary OR (within any_lab_year=1)",
    "D-09 branch (primary)",
    "D-09 pct change (primary)",
    "D-09 threshold rule",
    "Lab-source caveat",
    "Suppression",
    "Phase 180 RDS basename"),
  Value = c(
    "MISS-01 missing-exposure breakdown; MISS-02/03 bounding; MISS-04 CBC capture check",
    "Read-only checks on cbc_patient_year_20261013.rds. Phase 179 primary OR reproduced before any check runs.",
    RUN_DATE,
    KEY_META[["p179_rds"]],
    KEY_META[["r122_rds"]],
    KEY_META[["r169_rds"]],
    "triage column in Phase 179 RDS (from R/121 at the time R/179 was run)",
    KEY_META[["repro_check"]],
    as.character(CDM_CUTOFF),
    as.character(CUTOFF),
    GEE_CORSTR,
    KEY_META[["miss02_or"]],
    KEY_META[["miss03_or"]],
    d05_branch,
    fmt_result(res_anylab),
    d09_branch,
    KEY_META[["d09_pct_change"]],
    ">=25%: moves toward 1 (non-capture); <=-25%: moves away from 1 (true diff in CBC receipt); else: no material change",
    lab_source_caveat,
    "Counts 1-10 shown as <11; rates shown only when both underlying counts are >=11",
    glue("cbc_missing_capture_{RUN_DATE}.rds")),
  stringsAsFactors = FALSE)

# --- 5b. MISS-01 sheet --------------------------------------------------------
miss01_out <- dplyr::bind_rows(
  list(
    miss01_df[, c("Subset", "Group", "Patients", "Patient_years", "CBC_year_rate")],
    data.frame(Subset = "Note", Group = "(c): no in-system contact after anchor -- directly relevant to capture",
               Patients = "", Patient_years = "", CBC_year_rate = "", stringsAsFactors = FALSE)
  )
)

# Add triage x reason below
triage_note <- data.frame(Subset = "Triage x Reason", Group = "", Patients = "",
                           Patient_years = "", CBC_year_rate = "", stringsAsFactors = FALSE)

# --- 5c. Build workbook -------------------------------------------------------
hdr  <- openxlsx::createStyle(fgFill = "#0021A5", fontColour = "#FFFFFF", textDecoration = "bold")
sec  <- openxlsx::createStyle(fgFill = "#FA4616", fontColour = "#FFFFFF", textDecoration = "bold")
wrap <- openxlsx::createStyle(wrapText = TRUE, valign = "top")

wb <- openxlsx::createWorkbook()

# KEY
openxlsx::addWorksheet(wb, "KEY")
openxlsx::writeData(wb, "KEY", key_df, headerStyle = hdr)
openxlsx::addStyle(wb, "KEY", wrap, rows = 2:(nrow(key_df) + 1), cols = 1:2, gridExpand = TRUE)
openxlsx::setColWidths(wb, "KEY", 1:2, c(34, 120))

# MISS-01
openxlsx::addWorksheet(wb, "MISS-01")
openxlsx::writeData(wb, "MISS-01", "Missing-exposure breakdown (MISS-01)", startRow = 1)
openxlsx::addStyle(wb, "MISS-01", sec, rows = 1, cols = 1)
openxlsx::writeData(wb, "MISS-01", miss01_out, startRow = 2, headerStyle = hdr)
r0 <- nrow(miss01_out) + 4
openxlsx::writeData(wb, "MISS-01", "Triage x Reason cross-tab", startRow = r0)
openxlsx::addStyle(wb, "MISS-01", sec, rows = r0, cols = 1)
openxlsx::writeData(wb, "MISS-01", triage_x_reason, startRow = r0 + 1, headerStyle = hdr)
openxlsx::setColWidths(wb, "MISS-01", 1:6, c(52, 20, 14, 16, 16, 16))

# MISS-02-03
openxlsx::addWorksheet(wb, "MISS-02-03")
openxlsx::writeData(wb, "MISS-02-03", "Bounding analysis (MISS-02/03, D-04, D-05)", startRow = 1)
openxlsx::addStyle(wb, "MISS-02-03", sec, rows = 1, cols = 1)
openxlsx::writeData(wb, "MISS-02-03", miss0203_df, startRow = 2, headerStyle = hdr)
openxlsx::setColWidths(wb, "MISS-02-03", 1:ncol(miss0203_df),
                       c(46, 22, 14, 10, 8, 8, 8, 10, 40))

# MISS-04
openxlsx::addWorksheet(wb, "MISS-04")
openxlsx::writeData(wb, "MISS-04", "Capture descriptives (D-07)", startRow = 1)
openxlsx::addStyle(wb, "MISS-04", sec, rows = 1, cols = 1)
openxlsx::writeData(wb, "MISS-04", desc07_df, startRow = 2, headerStyle = hdr)
r0b <- nrow(desc07_df) + 4
openxlsx::writeData(wb, "MISS-04", "Capture models (D-08) and D-09 labels", startRow = r0b)
openxlsx::addStyle(wb, "MISS-04", sec, rows = r0b, cols = 1)
openxlsx::writeData(wb, "MISS-04", miss04_models_df, startRow = r0b + 1, headerStyle = hdr)
r0c <- r0b + nrow(miss04_models_df) + 3
openxlsx::writeData(wb, "MISS-04", "Lab source field value counts (D-10)", startRow = r0c)
openxlsx::addStyle(wb, "MISS-04", sec, rows = r0c, cols = 1)
openxlsx::writeData(wb, "MISS-04", lab_source_df, startRow = r0c + 1, headerStyle = hdr)
openxlsx::writeData(wb, "MISS-04", data.frame(Caveat = lab_source_caveat),
                    startRow = r0c + nrow(lab_source_df) + 3, headerStyle = hdr)
openxlsx::setColWidths(wb, "MISS-04", 1:max(ncol(desc07_df), ncol(miss04_models_df), 3), 18)

wb_path <- file.path(CONFIG$output_dir, glue("cbc_missing_capture_{RUN_DATE}.xlsx"))
openxlsx::saveWorkbook(wb, wb_path, overwrite = TRUE)
message(glue("  Workbook saved: {wb_path}"))

# --- 5d. Internal RDS ---------------------------------------------------------
internal_dir <- file.path(CONFIG$output_dir, "internal")
dir.create(internal_dir, recursive = TRUE, showWarnings = FALSE)
rds_out <- file.path(internal_dir, glue("cbc_missing_capture_{RUN_DATE}.rds"))

py_export <- py_m4 |>
  dplyr::select(ID, year_index, year_start, year_end, cbc_year, cbc_year_broad,
                median_distance, far, far_year_median, exposure_missing, triage,
                any_lab_year, any_enc_year, miss_reason)
saveRDS(py_export, rds_out)
message(glue("  RDS saved: {rds_out} ({format(nrow(py_export), big.mark=',')} rows)"))

# ==============================================================================
# SECTION 6: SUMMARY ----
# ==============================================================================

message(glue(
  "==== R/180 COMPLETE -- {RUN_DATE} ====\n",
  "  Workbook : {wb_path}\n",
  "  RDS      : {rds_out}\n",
  "  Reproduction check: {KEY_META[['repro_check']]}\n",
  "  D-05 branch: {d05_branch}\n",
  "  D-09 branch (primary): {d09_branch} ({KEY_META[['d09_pct_change']]} change)\n",
  "  Lab-source caveat: {lab_source_caveat}"))
