# ==============================================================================
# R/183_mice_sensitivity_distance.R -- MICE Sensitivity for Distance Exposure
# ==============================================================================
#
# Purpose:
#   Multiple imputation (MICE, m = 20) for 614 patients with missing distance
#   exposure after Phase 182. Two separate runs:
#     D-01 (primary): impute log_dist by PMM; derive far from threshold.
#     D-02 (sensitivity): impute far directly by logreg.
#   Refits Phase 179 GEE in each completed dataset; pools with Rubin's rules.
#   Produces a comparison workbook and a script-generated memo.
#
# Inputs (pinned, D-15):
#   R183_P179_RDS  -- output/internal/cbc_patient_year_20261015.rds
#   R183_P179_XLSX -- output/cbc_patient_year_20261015.xlsx
#   R183_P180_XLSX -- output/cbc_missing_capture_20261015.xlsx
#   R183_R122_RDS  -- output/encounter_distance_20261015.rds
#   R183_R169_RDS  -- output/internal/single_source_care_20261008.rds
#   R183_ADI_CSV   -- data/reference/zip5_adi_summary.csv
#
# Outputs:
#   output/mice_sensitivity_distance_<YYYYMMDD>.xlsx  (KEY, MICE-01, MICE-02)
#   output/mice_trace_<YYYYMMDD>.png
#   output/mice_density_<YYYYMMDD>.png
#   output/183-MEMO_<YYYYMMDD>.md
#   output/internal/mice_input_patient_<YYYYMMDD>.rds   (patient IDs — internal)
#   output/internal/mice_mids_<YYYYMMDD>.rds             (mids objects — internal)
#
# Usage (interactive R on HiPerGator, repo root):
#   module load R/4.5
#   R
#   source("R/183_mice_sensitivity_distance.R", local = new.env(parent = globalenv()))
#
# ==============================================================================

source("R/00_config.R")

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(geepack)
  library(mice)
  library(glue)
  library(checkmate)
  library(readxl)
  library(openxlsx)
})

# ==============================================================================
# SECTION 0: CONSTANTS AND HELPERS ----
# ==============================================================================

RUN_DATE    <- format(Sys.Date(), "%Y%m%d")
MICE_M      <- 20L
MICE_MAXIT  <- 20L
MICE_SEED   <- 20261015L
CUTOFF      <- CONFIG$far_from_care_cutoff_mi    # 100
GEE_CORSTR  <- CONFIG$distance_gee_corstr        # "exchangeable"

# --- Column name constants (Task 0) ---
# Phase 179 RDS columns (R/179_cbc_patient_year.R, final select line 309):
COL_ID              <- "ID"
COL_YEAR_INDEX      <- "year_index"
COL_YEAR_START      <- "year_start"
COL_YEAR_END        <- "year_end"
COL_CBC_YEAR        <- "cbc_year"
COL_MEDIAN_DIST     <- "median_distance"   # R/179 line 287: median_distance
COL_FAR             <- "far"
COL_EXP_MISSING     <- "exposure_missing"
COL_TRIAGE          <- "triage"

# R/122 RDS columns (R/122_encounter_distance.R, select lines 685-707):
# NOTE: SOURCE is not in the final enc_distance select; retrieved from DuckDB ENCOUNTER.
COL_122_ID          <- "ID"
COL_122_ADMIT_DATE  <- "ADMIT_DATE"
COL_122_ZIP5_PAT    <- "zip5_patient"
COL_122_ZIP5_FAC    <- "zip5_facility"
COL_122_DIST_STATUS <- "distance_status"

# R/169 RDS: output/internal/single_source_care_<YYYYMMDD>.rds
# Columns (R/169_single_source_care.R lines 44-86):
COL_169_ID          <- "ID"
COL_169_SSC_POST    <- "single_source_care_post"

# ADI CSV columns (data/reference/zip5_adi_summary.csv header):
COL_ADI_ZIP5        <- "ZIP5"
COL_ADI_VALUE       <- "adi_natrank_median"

# Phase 179 workbook exact labels
# (R/180_cbc_missing_capture.R line 236: P179_PRIMARY_LABEL):
LBL_P179_PRIMARY    <- "Primary: years 2+"
# (R/179 line 440): "Secondary: all years" — Task 0 check: only use if exact
# label exists in Model_Results; verified below.
LBL_P179_SECONDARY  <- "Secondary: all years"

# Phase 180 KEY exact labels
# (R/182_facility_zip_recovery_report.R lines 242-249):
LBL_P180_FAR1       <- "MISS-02 (missing -> far=1)"
LBL_P180_FAR0       <- "MISS-03 (missing -> far=0)"

# Helpers copied verbatim from R/179_cbc_patient_year.R (lines 81-88)
# copied verbatim from R/179 lines 81-94; do not edit
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

# run_gee() copied verbatim from R/179_cbc_patient_year.R lines 398-434; do not edit
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

# need_cols(): stop with available names printed if any column is missing
need_cols <- function(df, cols, what) {
  missing <- setdiff(cols, names(df))
  if (length(missing) > 0L)
    stop(glue("[R/183] {what}: missing columns {paste(missing, collapse=', ')}. ",
              "Available: {paste(names(df), collapse=', ')}"), call. = FALSE)
  invisible(df)
}

DROPPED <- list()  # name -> reason for optional dropped variables

# ==============================================================================
# SECTION 1: PINNED INPUTS (D-15) ----
# ==============================================================================

pin <- function(var, default) {
  v <- Sys.getenv(var, unset = ""); p <- if (nzchar(v)) v else default
  if (!file.exists(p)) stop(glue("[R/183] {var}: file not found: {p}"), call. = FALSE)
  list(var = var, path = p, pinned = nzchar(v))
}

PINS <- list(
  p179_rds  = pin("R183_P179_RDS",  "output/internal/cbc_patient_year_20261015.rds"),
  p179_xlsx = pin("R183_P179_XLSX", "output/cbc_patient_year_20261015.xlsx"),
  p180_xlsx = pin("R183_P180_XLSX", "output/cbc_missing_capture_20261015.xlsx"),
  r122_rds  = pin("R183_R122_RDS",  "output/encounter_distance_20261015.rds"),
  r169_rds  = pin("R183_R169_RDS",  "output/internal/single_source_care_20261008.rds"),
  adi_csv   = pin("R183_ADI_CSV",   "data/reference/zip5_adi_summary.csv")
)

message("==== R/183 mice_sensitivity_distance -- RUN DATE ", RUN_DATE, " ====")
for (nm in names(PINS)) {
  p <- PINS[[nm]]
  message(glue("  {p$var}: {p$path} (pinned={p$pinned})"))
}

# ==============================================================================
# SECTION 2: ONE ROW PER PATIENT ----
# ==============================================================================

# 2a. Load Phase 179 RDS (all rows, no exposure filter)
py_full <- readRDS(PINS$p179_rds$path)
need_cols(py_full, c(COL_ID, COL_YEAR_INDEX, COL_YEAR_START, COL_YEAR_END,
                     COL_CBC_YEAR, COL_MEDIAN_DIST, COL_FAR,
                     COL_EXP_MISSING, COL_TRIAGE), "Phase 179 RDS")
py_full <- py_full |> dplyr::mutate(ID = as_id(.data[[COL_ID]]))

n_patients <- dplyr::n_distinct(py_full$ID)
n_py       <- nrow(py_full)
n_missing  <- sum(py_full[[COL_EXP_MISSING]])
message(glue("  P179 RDS: {n_patients} patients, {n_py} patient-years, ",
             "{n_missing} patient-years with exposure_missing"))

# year_index_cat needed by run_gee() (copied from R/179 line 333)
py_full <- py_full |>
  dplyr::mutate(year_index_cat = factor(
    dplyr::if_else(.data[[COL_YEAR_INDEX]] >= 5L, "5+", as.character(.data[[COL_YEAR_INDEX]])),
    levels = c("1", "2", "3", "4", "5+")))

# 2a. Anchor: min(year_start) per patient (D-07a)
anchors <- py_full |>
  dplyr::group_by(ID) |>
  dplyr::summarise(anchor = min(.data[[COL_YEAR_START]]), .groups = "drop")

# 2b. Outcome (all RDS rows, no exposure filter; D-05)
pat_outcome <- py_full |>
  dplyr::group_by(ID) |>
  dplyr::summarise(prop_cbc_years   = mean(.data[[COL_CBC_YEAR]]),
                   n_years_observed = dplyr::n(),
                   .groups = "drop")

# 2c. Exposure: one row per patient
pat_exp_check <- py_full |>
  dplyr::group_by(ID) |>
  dplyr::summarise(n_dist_vals = dplyr::n_distinct(.data[[COL_MEDIAN_DIST]], na.rm = TRUE),
                   .groups = "drop")
bad_ids <- pat_exp_check$ID[pat_exp_check$n_dist_vals > 1L]
if (length(bad_ids) > 0L)
  stop(glue("[R/183] {length(bad_ids)} patients have >1 distinct median_distance"), call. = FALSE)

pat_exposure <- py_full |>
  dplyr::distinct(ID, .data[[COL_MEDIAN_DIST]], .data[[COL_FAR]],
                  .data[[COL_EXP_MISSING]], miss_reason = .data[[COL_TRIAGE]]) |>
  dplyr::mutate(log_dist = log1p(.data[[COL_MEDIAN_DIST]]))

# 2d. Encounters from R/122 RDS
enc <- readRDS(PINS$r122_rds$path)
need_cols(enc, c(COL_122_ID, COL_122_ADMIT_DATE, COL_122_ZIP5_PAT,
                 COL_122_DIST_STATUS), "R/122 RDS")
enc <- enc |> dplyr::mutate(ID = as_id(.data[[COL_122_ID]]))

# SOURCE is not in the final enc_distance RDS (R/122 dropped it in the select).
# Retrieve from DuckDB ENCOUNTER (read-only) and join by ENCOUNTERID.
message("  Fetching SOURCE from DuckDB ENCOUNTER ...")
enc_source <- tryCatch({
  con183 <- open_pcornet_con()
  on.exit(try(close_pcornet_con(), silent = TRUE), add = TRUE)
  src_raw <- DBI::dbGetQuery(con183,
    "SELECT ENCOUNTERID, SOURCE FROM ENCOUNTER WHERE ENCOUNTERID IS NOT NULL")
  src_raw
}, error = function(e) {
  stop(glue("[R/183] DuckDB ENCOUNTER SOURCE fetch failed: {e$message}"), call. = FALSE)
})
enc <- enc |>
  dplyr::left_join(dplyr::distinct(enc_source, ENCOUNTERID, SOURCE), by = "ENCOUNTERID")
message(glue("  SOURCE joined: {sum(!is.na(enc$SOURCE))} of {nrow(enc)} rows have SOURCE"))

enc_post <- enc |>
  dplyr::left_join(anchors, by = "ID") |>
  dplyr::filter(.data[[COL_122_ADMIT_DATE]] > anchor)

pat_enc <- enc_post |>
  dplyr::group_by(ID) |>
  dplyr::summarise(
    post_anchor_enc_count = dplyr::n(),
    main_source  = {
      tbl <- sort(table(SOURCE), decreasing = TRUE)
      names(tbl)[1]
    },
    pat_zip5 = {
      zips <- .data[[COL_122_ZIP5_PAT]]
      zips <- zips[!is.na(zips)]
      if (length(zips) == 0L) NA_character_ else {
        tbl <- sort(table(zips), decreasing = TRUE); names(tbl)[1]
      }
    },
    .groups = "drop"
  )

# 2e. Auxiliary distance: dist_to_source_facility_mi (D-06)
# Modal facility ZIP5 per SOURCE (from distance_status == "computed" rows, all patients)
src_fac_zip <- enc |>
  dplyr::filter(.data[[COL_122_DIST_STATUS]] == "computed",
                !is.na(.data[[COL_122_ZIP5_FAC]])) |>
  dplyr::count(SOURCE, zip5_facility = .data[[COL_122_ZIP5_FAC]]) |>
  dplyr::group_by(SOURCE) |>
  dplyr::slice_max(n, n = 1L, with_ties = FALSE) |>
  dplyr::ungroup()

message(glue("  Source facility ZIPs: {nrow(src_fac_zip)} SOURCEs with modal facility ZIP"))

# Gazetteer centroids via get_zip_centroid()
# get_zip_centroid() from R/utils/utils_address.R returns tibble with
# lat, lon (from INTPTLAT and INTPTLONG/INTPTLON columns of gazetteer)
fac_centroids <- tryCatch(
  get_zip_centroid(src_fac_zip$zip5_facility, level = "zip5"),
  error = function(e) {
    message("[R/183] get_zip_centroid (facility): ", conditionMessage(e))
    NULL
  }
)

if (!is.null(fac_centroids) && nrow(fac_centroids) == nrow(src_fac_zip)) {
  src_fac_zip <- src_fac_zip |>
    dplyr::mutate(fac_lat = fac_centroids$lat, fac_lon = fac_centroids$lon)
} else {
  src_fac_zip <- src_fac_zip |> dplyr::mutate(fac_lat = NA_real_, fac_lon = NA_real_)
}

# Join SOURCE modal facility centroid to patients via main_source
pat_aux <- pat_enc |>
  dplyr::left_join(dplyr::select(src_fac_zip, SOURCE, fac_lat, fac_lon),
                   by = c("main_source" = "SOURCE"))

# Patient ZIP5 centroids
pat_zip5_unique <- unique(na.omit(pat_aux$pat_zip5))
if (length(pat_zip5_unique) > 0L) {
  pat_centroids_raw <- tryCatch(
    get_zip_centroid(pat_zip5_unique, level = "zip5"),
    error = function(e) { message("[R/183] get_zip_centroid (patient): ", conditionMessage(e)); NULL }
  )
  if (!is.null(pat_centroids_raw) && nrow(pat_centroids_raw) == length(pat_zip5_unique)) {
    pat_centroid_lookup <- data.frame(
      pat_zip5 = pat_zip5_unique,
      pat_lat  = pat_centroids_raw$lat,
      pat_lon  = pat_centroids_raw$lon,
      stringsAsFactors = FALSE
    )
  } else {
    pat_centroid_lookup <- data.frame(pat_zip5 = pat_zip5_unique,
                                      pat_lat = NA_real_, pat_lon = NA_real_,
                                      stringsAsFactors = FALSE)
  }
  pat_aux <- pat_aux |>
    dplyr::left_join(pat_centroid_lookup, by = "pat_zip5")
} else {
  pat_aux <- pat_aux |> dplyr::mutate(pat_lat = NA_real_, pat_lon = NA_real_)
}

# haversine_km returns km; convert to miles (* 0.621371) per R/122 line 399
pat_aux <- pat_aux |>
  dplyr::mutate(
    dist_to_source_facility_mi = haversine_km(pat_lat, pat_lon, fac_lat, fac_lon) * 0.621371
  )

# 2f. Single-source care post from R/169
ssc <- readRDS(PINS$r169_rds$path)
need_cols(ssc, c(COL_169_ID, COL_169_SSC_POST), "R/169 RDS")
ssc <- ssc |>
  dplyr::transmute(ID = as_id(.data[[COL_169_ID]]),
                   single_source_care_post = factor(.data[[COL_169_SSC_POST]]))

# 2g. ADI
adi_raw <- read.csv(PINS$adi_csv$path, stringsAsFactors = FALSE, check.names = FALSE)
need_cols(adi_raw, c(COL_ADI_ZIP5, COL_ADI_VALUE), "ADI CSV")
adi_lkp <- adi_raw |>
  dplyr::transmute(pat_zip5 = as.character(.data[[COL_ADI_ZIP5]]),
                   adi = suppressWarnings(as.numeric(.data[[COL_ADI_VALUE]])))

# 2h. Demographics: age_at_anchor and sex
# Source: DuckDB DEMOGRAPHIC table (ID, BIRTH_DATE, SEX)
# (R/179 uses R/147 anchors; demographics are from the CDM DEMOGRAPHIC table)
demo_avail <- FALSE
age_sex <- tryCatch({
  con <- open_pcornet_con()
  on.exit(try(close_pcornet_con(), silent = TRUE), add = TRUE)
  demo_raw <- DBI::dbGetQuery(con,
    "SELECT ID, BIRTH_DATE, SEX FROM DEMOGRAPHIC")
  demo_raw$ID <- as_id(demo_raw$ID)
  demo_raw$BIRTH_DATE <- suppressWarnings(as.Date(demo_raw$BIRTH_DATE))
  demo_avail <- TRUE
  demo_raw
}, error = function(e) {
  message("[R/183] DuckDB DEMOGRAPHIC read failed: ", conditionMessage(e),
          " -- age_at_anchor and sex will be dropped (D-07b)")
  NULL
})

# 2h. Payer: PAYER_CATEGORY_PRIMARY from payer_summary RDS (R/165 line 156-170)
payer_avail <- FALSE
payer_lkp <- tryCatch({
  payer_files <- list.files(CONFIG$output_dir, pattern = "^payer_summary.*\\.rds$",
                            full.names = TRUE)
  if (length(payer_files) == 0L) stop("payer_summary RDS not found")
  payer_path <- payer_files[order(file.mtime(payer_files), decreasing = TRUE)[1L]]
  message(glue("  Loading payer_summary: {basename(payer_path)}"))
  ps <- readRDS(payer_path) |> dplyr::select(ID, PAYER_CATEGORY_PRIMARY)
  ps$ID <- as_id(ps$ID)
  payer_avail <- TRUE
  ps
}, error = function(e) {
  message("[R/183] payer_summary not found or read failed: ", conditionMessage(e),
          " -- payer will be dropped (D-07b)")
  NULL
})

if (!payer_avail) DROPPED[["payer"]] <- "payer_summary RDS not found"

# 2i. Assemble pat_mice
pat_mice <- anchors |>
  dplyr::left_join(pat_outcome, by = "ID") |>
  dplyr::left_join(pat_exposure, by = "ID") |>
  dplyr::left_join(
    dplyr::select(pat_aux, ID, post_anchor_enc_count, main_source, pat_zip5,
                  dist_to_source_facility_mi),
    by = "ID") |>
  dplyr::mutate(
    # Patients with no post-anchor encounters in R/122 get count=0, not NA.
    # main_source stays NA so MICE can impute it.
    post_anchor_enc_count = dplyr::coalesce(post_anchor_enc_count, 0L)
  ) |>
  dplyr::left_join(ssc, by = "ID") |>
  dplyr::left_join(dplyr::select(adi_lkp, pat_zip5, adi), by = "pat_zip5")

if (demo_avail && !is.null(age_sex)) {
  age_sex_pat <- age_sex |>
    dplyr::left_join(anchors, by = "ID") |>
    dplyr::transmute(
      ID,
      age_at_anchor = as.numeric(difftime(anchor, BIRTH_DATE, units = "days")) / 365.25,
      sex_raw = SEX)
  # Join to cohort patients BEFORE creating factor — prevents empty-level polyreg failures.
  # Merge any category with fewer than 11 cohort patients into "Other/Unknown".
  age_sex_pat <- age_sex_pat |>
    dplyr::filter(ID %in% anchors$ID)
  sex_counts <- table(age_sex_pat$sex_raw, useNA = "no")
  rare_levels <- names(sex_counts)[sex_counts < 11L]
  if (length(rare_levels) > 0L) {
    msg <- glue("sex levels merged into 'Other/Unknown' (<11 patients): ",
                "{paste(rare_levels, collapse=', ')}")
    DROPPED[["sex_merge_note"]] <- msg
    message(glue("  [R/183] {msg}"))
    age_sex_pat <- age_sex_pat |>
      dplyr::mutate(sex_raw = dplyr::if_else(sex_raw %in% rare_levels, "Other/Unknown", sex_raw))
  }
  age_sex_pat <- age_sex_pat |>
    dplyr::mutate(sex = droplevels(factor(sex_raw))) |>
    dplyr::select(ID, age_at_anchor, sex)
  pat_mice <- pat_mice |> dplyr::left_join(age_sex_pat, by = "ID")
} else {
  DROPPED[["age_at_anchor"]] <- "DEMOGRAPHIC table unavailable"
  DROPPED[["sex"]]           <- "DEMOGRAPHIC table unavailable"
  pat_mice <- pat_mice |>
    dplyr::mutate(age_at_anchor = NA_real_, sex = factor(NA_character_))
}

if (payer_avail && !is.null(payer_lkp)) {
  pat_mice <- pat_mice |>
    dplyr::left_join(payer_lkp, by = "ID") |>
    dplyr::mutate(payer = factor(PAYER_CATEGORY_PRIMARY)) |>
    dplyr::select(-PAYER_CATEGORY_PRIMARY)
} else {
  pat_mice <- pat_mice |> dplyr::mutate(payer = factor(NA_character_))
  if (!("payer" %in% names(DROPPED)))
    DROPPED[["payer"]] <- "payer_summary RDS not found"
}

# Convert character/logical predictors to factor (D-08a)
pat_mice <- pat_mice |>
  dplyr::mutate(
    main_source = factor(main_source),
    far         = as.integer(far)
  )

# adi: drop if missing for all patients (D-07b)
if (all(is.na(pat_mice$adi))) {
  DROPPED[["adi"]] <- "adi_natrank_median is NA for all patients"
  pat_mice <- pat_mice |> dplyr::select(-adi)
}

# payer: drop if missing for all patients (D-07b)
if ("payer" %in% names(pat_mice) && all(is.na(pat_mice$payer))) {
  DROPPED[["payer"]] <- "PAYER_CATEGORY_PRIMARY is NA for all patients after join"
  pat_mice <- pat_mice |> dplyr::select(-payer)
}

# age/sex: drop if missing for all patients (D-07b)
if ("age_at_anchor" %in% names(pat_mice) && all(is.na(pat_mice$age_at_anchor))) {
  DROPPED[["age_at_anchor"]] <- "age_at_anchor is NA for all patients"
  pat_mice <- pat_mice |> dplyr::select(-age_at_anchor)
}
if ("sex" %in% names(pat_mice) && all(is.na(pat_mice$sex))) {
  DROPPED[["sex"]] <- "sex is NA for all patients"
  pat_mice <- pat_mice |> dplyr::select(-sex)
}

# Drop unused factor levels and guard against empty levels that break polyreg/logreg.
factor_cols <- names(pat_mice)[sapply(pat_mice, is.factor)]
for (fc in factor_cols) {
  pat_mice[[fc]] <- droplevels(pat_mice[[fc]])
  empty <- levels(pat_mice[[fc]])[table(pat_mice[[fc]]) == 0L]
  if (length(empty) > 0L)
    stop(glue("[R/183] Factor '{fc}' still has empty levels after droplevels: ",
              "{paste(empty, collapse=', ')}"), call. = FALSE)
}

# Final column selection (D-07): ID, log_dist, far, prop_cbc_years, n_years_observed,
# dist_to_source_facility_mi, age_at_anchor?, sex?, main_source,
# post_anchor_enc_count, single_source_care_post, payer?, adi?,
# exposure_missing, miss_reason
desired_cols <- c("ID", "log_dist", "far", "prop_cbc_years", "n_years_observed",
                  "dist_to_source_facility_mi", "age_at_anchor", "sex", "main_source",
                  "post_anchor_enc_count", "single_source_care_post", "payer", "adi",
                  "exposure_missing", "miss_reason")
pat_mice <- pat_mice |> dplyr::select(dplyr::any_of(desired_cols))

stopifnot(!anyDuplicated(pat_mice$ID),
          nrow(pat_mice) == dplyr::n_distinct(py_full$ID))

# 2j. Availability table (printed and saved for MICE-01)
avail_vars <- setdiff(names(pat_mice),
                      c("ID", "exposure_missing", "miss_reason", "log_dist", "far"))
avail_tbl <- do.call(rbind, lapply(avail_vars, function(v) {
  is_miss <- is.na(pat_mice[[v]])
  exp_miss <- pat_mice$exposure_missing
  data.frame(
    Variable         = v,
    n_missing_all    = sum(is_miss),
    n_missing_exp    = sum(is_miss & exp_miss),
    pct_missing_all  = show_rate(sum(is_miss), nrow(pat_mice)),
    stringsAsFactors = FALSE
  )
}))
message("\n  Availability table:")
print(avail_tbl)
if (length(DROPPED) > 0L) {
  message("  DROPPED variables:")
  for (nm in names(DROPPED)) message(glue("    {nm}: {DROPPED[[nm]]}"))
}

dir.create(file.path("output", "internal"), recursive = TRUE, showWarnings = FALSE)
saveRDS(pat_mice, file.path("output", "internal",
                             glue("mice_input_patient_{RUN_DATE}.rds")))
message(glue("  Saved: output/internal/mice_input_patient_{RUN_DATE}.rds"))

# ==============================================================================
# SECTION 3: REPRODUCTION GATE (D-16a) ----
# ==============================================================================

# Helper: read Phase 179 OR from workbook by exact label (R/180 reader pattern)
# (R/180_cbc_missing_capture.R lines 248, 560-580)
read_p179_or <- function(path, label) {
  sheet_df <- tryCatch(
    openxlsx::read.xlsx(path, sheet = "Model_Results"),
    error = function(e) stop(glue("Cannot read Model_Results from {basename(path)}: {e$message}")))
  if (!"Analysis" %in% names(sheet_df))
    stop(glue("Model_Results in {basename(path)} missing 'Analysis' column"))
  rows <- sheet_df[trimws(as.character(sheet_df$Analysis)) == label, ]
  if (nrow(rows) != 1L) {
    avail <- paste(head(trimws(as.character(sheet_df$Analysis)), 30), collapse = ", ")
    stop(glue("Expected 1 row with Analysis='{label}' in {basename(path)}; ",
              "found {nrow(rows)}. Available: {avail}"), call. = FALSE)
  }
  list(or    = as.numeric(rows$OR),
       ci_lo = as.numeric(rows$CI_low),
       ci_hi = as.numeric(rows$CI_high))
}

P179_REF <- read_p179_or(PINS$p179_xlsx$path, LBL_P179_PRIMARY)
message(glue("  Phase 179 reference ({LBL_P179_PRIMARY}): ",
             "OR={round(P179_REF$or, 3)} ({round(P179_REF$ci_lo, 3)}-{round(P179_REF$ci_hi, 3)})"))

# Check if "Secondary: all years" label exists in the workbook
p179_model_df <- openxlsx::read.xlsx(PINS$p179_xlsx$path, sheet = "Model_Results")
P179_HAS_SECONDARY <- LBL_P179_SECONDARY %in% trimws(as.character(p179_model_df$Analysis))
message(glue("  Phase 179 '{LBL_P179_SECONDARY}' label found: {P179_HAS_SECONDARY}"))
if (P179_HAS_SECONDARY) {
  P179_REF_ALL <- read_p179_or(PINS$p179_xlsx$path, LBL_P179_SECONDARY)
} else {
  P179_REF_ALL <- NULL
}

# Complete-case GEE reproducing Phase 179 primary (years 2+ subset)
py_cc     <- dplyr::filter(py_full, !.data[[COL_EXP_MISSING]])
py_cc_pri <- dplyr::filter(py_cc, .data[[COL_YEAR_INDEX]] >= 2L)
t0_fit    <- run_gee(py_cc_pri, COL_CBC_YEAR, COL_FAR, LBL_P179_PRIMARY)

diff_or <- abs(t0_fit$or - P179_REF$or)
diff_lo <- abs(t0_fit$ci_lo - P179_REF$ci_lo)
diff_hi <- abs(t0_fit$ci_hi - P179_REF$ci_hi)
if (any(c(diff_or, diff_lo, diff_hi) > 0.005))
  stop(glue("Task-0 FAIL: complete-case OR {round(t0_fit$or, 3)} ",
            "({round(t0_fit$ci_lo, 3)}-{round(t0_fit$ci_hi, 3)}) ",
            "does not reproduce Phase 179 '{LBL_P179_PRIMARY}' ",
            "OR {round(P179_REF$or, 3)} ({round(P179_REF$ci_lo, 3)}-{round(P179_REF$ci_hi, 3)}). ",
            "Max diff: OR={round(diff_or, 4)}, lo={round(diff_lo, 4)}, hi={round(diff_hi, 4)}"),
       call. = FALSE)

message(glue("Task-0 PASS: complete-case OR {round(t0_fit$or, 3)} ",
             "({round(t0_fit$ci_lo, 3)}-{round(t0_fit$ci_hi, 3)}) matches ",
             "Phase 179 {round(P179_REF$or, 3)} ({round(P179_REF$ci_lo, 3)}-{round(P179_REF$ci_hi, 3)})"))


# ==============================================================================
# SECTION 4: MICE IMPUTATION — TWO SEPARATE RUNS (D-01 and D-02) ----
# ==============================================================================

# Predictor set: exclude ID, targets, miss_reason (D-07c), and exposure_missing
PRED <- setdiff(names(pat_mice), c("ID", "log_dist", "far", "exposure_missing", "miss_reason"))

run_mice <- function(target, method_target) {
  d <- pat_mice[, c(target, PRED)]
  ini  <- mice::mice(d, maxit = 0, printFlag = FALSE)
  meth <- ini$method
  meth[target] <- method_target
  imp  <- mice::mice(d, m = MICE_M, maxit = MICE_MAXIT, method = meth,
                     predictorMatrix = ini$predictorMatrix, seed = MICE_SEED,
                     printFlag = FALSE)
  # D-09.1: no NA in target after imputation
  for (i in seq_len(MICE_M)) {
    ci <- mice::complete(imp, i)
    if (anyNA(ci[[target]]))
      stop(glue("D-09 FAIL: NA in {target} after imputation, dataset {i}"), call. = FALSE)
  }
  # D-09.2: mandatory predictors not removed by mice
  le   <- imp$loggedEvents
  must <- c("prop_cbc_years", "n_years_observed", "dist_to_source_facility_mi")
  if (!is.null(le) && any(le$out %in% must))
    stop(glue("D-09 FAIL: mice removed {paste(intersect(le$out, must), collapse=', ')}"),
         call. = FALSE)
  imp
}

# D-02: far stored as factor with levels "0","1" (convert back via as.integer(as.character(.)))
pat_mice$far <- factor(pat_mice$far, levels = c(0, 1), labels = c("0", "1"))

message("\n==== SECTION 4: MICE D-01 (log_dist, pmm) ====")
imp_d01 <- run_mice("log_dist", "pmm")
message(glue("  D-01 complete: m={MICE_M}, maxit={MICE_MAXIT}, seed={MICE_SEED}"))

message("\n==== SECTION 4: MICE D-02 (far, logreg) ====")
imp_d02 <- run_mice("far", "logreg")
message(glue("  D-02 complete: m={MICE_M}, maxit={MICE_MAXIT}, seed={MICE_SEED}"))

# Save mids objects (patient-level — internal only, D-17)
mids_path <- file.path("output", "internal", glue("mice_mids_{RUN_DATE}.rds"))
saveRDS(list(d01 = imp_d01, d02 = imp_d02), mids_path)
message(glue("  Saved: {mids_path}"))

# --- D-10: Diagnostics (non-blocking) ---

# loggedEvents
message("\n  D-10: loggedEvents D-01:")
if (is.null(imp_d01$loggedEvents)) message("    None") else print(imp_d01$loggedEvents)
message("  D-10: loggedEvents D-02:")
if (is.null(imp_d02$loggedEvents)) message("    None") else print(imp_d02$loggedEvents)

# n patients imputed per target
n_imp_d01 <- sup(sum(pat_mice$exposure_missing & !is.na(pat_mice$exposure_missing)))
message(glue("  D-10: patients missing (exposure_missing): {n_imp_d01}"))

# Observed far proportion
obs_far_prop <- mean(as.integer(as.character(pat_mice$far[!pat_mice$exposure_missing])), na.rm = TRUE)
message(glue("  D-10: observed far proportion (non-missing): {round(obs_far_prop, 4)}"))

# Per-dataset imputed far proportion across m datasets (D-01: derived; D-02: direct)
far_props_d01 <- sapply(seq_len(MICE_M), function(i) {
  ci <- mice::complete(imp_d01, i)
  imp_rows <- pat_mice$exposure_missing
  mean(as.integer(expm1(ci$log_dist[imp_rows]) > CUTOFF), na.rm = TRUE)
})
far_props_d02 <- sapply(seq_len(MICE_M), function(i) {
  ci <- mice::complete(imp_d02, i)
  imp_rows <- pat_mice$exposure_missing
  mean(as.integer(as.character(ci$far[imp_rows])), na.rm = TRUE)
})
message(glue("  D-10: D-01 imputed far proportion (missing patients, over m): ",
             "mean={round(mean(far_props_d01), 4)}, ",
             "min={round(min(far_props_d01), 4)}, ",
             "max={round(max(far_props_d01), 4)}"))
message(glue("  D-10: D-02 imputed far proportion (missing patients, over m): ",
             "mean={round(mean(far_props_d02), 4)}, ",
             "min={round(min(far_props_d02), 4)}, ",
             "max={round(max(far_props_d02), 4)}"))

# Trace plots: chainMean / chainVar for both runs (2x2 panels)
trace_png <- file.path("output", glue("mice_trace_{RUN_DATE}.png"))
png(trace_png, width = 1200, height = 800)
par(mfrow = c(2, 2), mar = c(4, 4, 3, 1))
# D-01 chainMean / chainVar for log_dist
target_d01 <- "log_dist"
if (!is.null(imp_d01$chainMean) && target_d01 %in% dimnames(imp_d01$chainMean)[[1]]) {
  matplot(t(imp_d01$chainMean[target_d01, , ]), type = "l", lty = 1,
          xlab = "Iteration", ylab = "Chain Mean", main = "D-01: log_dist chain mean")
  matplot(t(imp_d01$chainVar[target_d01, , ]), type = "l", lty = 1,
          xlab = "Iteration", ylab = "Chain Var", main = "D-01: log_dist chain var")
} else {
  plot.new(); title("D-01: chainMean not available")
  plot.new(); title("D-01: chainVar not available")
}
# D-02 chainMean / chainVar for far
target_d02 <- "far"
if (!is.null(imp_d02$chainMean) && target_d02 %in% dimnames(imp_d02$chainMean)[[1]]) {
  matplot(t(imp_d02$chainMean[target_d02, , ]), type = "l", lty = 1,
          xlab = "Iteration", ylab = "Chain Mean", main = "D-02: far chain mean")
  matplot(t(imp_d02$chainVar[target_d02, , ]), type = "l", lty = 1,
          xlab = "Iteration", ylab = "Chain Var", main = "D-02: far chain var")
} else {
  plot.new(); title("D-02: chainMean not available")
  plot.new(); title("D-02: chainVar not available")
}
dev.off()
message(glue("  D-10 trace PNG: {trace_png}"))

# Density / proportion PNG
density_png <- file.path("output", glue("mice_density_{RUN_DATE}.png"))
png(density_png, width = 1200, height = 500)
par(mfrow = c(1, 2), mar = c(4, 4, 3, 1))
# D-01: observed vs imputed log_dist (pooled over m datasets)
obs_log_dist <- pat_mice$log_dist[!pat_mice$exposure_missing]
imp_log_dist  <- unlist(lapply(seq_len(MICE_M), function(i)
  mice::complete(imp_d01, i)$log_dist[pat_mice$exposure_missing]))
plot(density(obs_log_dist, na.rm = TRUE), col = "steelblue", lwd = 2,
     main = "D-01: log_dist distribution", xlab = "log_dist")
lines(density(imp_log_dist, na.rm = TRUE), col = "tomato", lwd = 2, lty = 2)
legend("topright", c("Observed", "Imputed"), col = c("steelblue", "tomato"),
       lwd = 2, lty = c(1, 2), bty = "n", cex = 0.8)
# D-02: bar of observed vs imputed far proportion
obs_far_bar <- obs_far_prop
imp_far_bar <- mean(far_props_d02)
barplot(c(obs_far_bar, imp_far_bar), names.arg = c("Observed", "Imputed (D-02)"),
        ylab = "Proportion far=1", main = "D-02: far proportion (observed vs imputed)",
        col = c("steelblue", "tomato"), ylim = c(0, max(obs_far_bar, imp_far_bar) * 1.3))
dev.off()
message(glue("  D-10 density PNG: {density_png}"))

# Store loggedEvents for workbook
LE_D01 <- imp_d01$loggedEvents
LE_D02 <- imp_d02$loggedEvents

# ==============================================================================
# SECTION 5: REFIT AND POOL (Rubin 1987; Barnard-Rubin df) ----
# ==============================================================================

# far_from: how to derive far (integer 0/1) from each completed dataset per branch
far_from <- list(
  d01 = function(ci) as.integer(expm1(ci$log_dist) > CUTOFF),
  d02 = function(ci) as.integer(as.character(ci$far))
)

# Rubin (1987); df per Barnard & Rubin form for large complete-data df
pool_rubin <- function(Q, SE) {
  m  <- length(Q)
  U  <- mean(SE^2)
  B  <- var(Q)
  Tv <- U + (1 + 1/m) * B
  r  <- (1 + 1/m) * B / U
  df <- if (B > 0) (m - 1) * (1 + 1/r)^2 else Inf
  q  <- qt(0.975, df)
  list(
    or  = exp(mean(Q)),
    lo  = exp(mean(Q) - q * sqrt(Tv)),
    hi  = exp(mean(Q) + q * sqrt(Tv)),
    fmi = (r + 2 / (df + 3)) / (r + 1),
    df  = df,
    U   = U,
    B   = B,
    T   = Tv,
    m   = m
  )
}

# Prepare complete-case py subsets for all-years (D-12a)
py_cc_all <- dplyr::filter(py_full, !.data[[COL_EXP_MISSING]])

mids_list  <- list(d01 = imp_d01, d02 = imp_d02)
subsets    <- list(
  pri = list(label = "years 2+",  filter_fn = function(d) dplyr::filter(d, year_index >= 2L)),
  all = list(label = "all years", filter_fn = function(d) d)
)

pooled_results <- list()

for (branch in c("d01", "d02")) {
  imp_obj <- mids_list[[branch]]
  for (sname in c("pri", "all")) {
    sub_label  <- subsets[[sname]]$label
    filter_fn  <- subsets[[sname]]$filter_fn
    result_key <- paste0(branch, "_", sname)

    Q_vec  <- numeric(MICE_M)
    SE_vec <- numeric(MICE_M)

    for (i in seq_len(MICE_M)) {
      ci <- mice::complete(imp_obj, i)
      # Derive far for imputed patients; observed far unchanged
      far_imp_vec <- far_from[[branch]](ci)

      # Assert observed far is unchanged for non-missing patients
      obs_idx <- !pat_mice$exposure_missing
      obs_far_orig <- as.integer(as.character(pat_mice$far[obs_idx]))
      obs_far_imp  <- far_imp_vec[obs_idx]
      if (!identical(obs_far_orig, obs_far_imp))
        stop(glue("D-09 FAIL: observed far changed for non-missing patients in branch {branch} dataset {i}"),
             call. = FALSE)

      imp_far_tbl <- tibble::tibble(ID = pat_mice$ID, far_imp = far_imp_vec)

      # Build patient-year frame: join imputed far for missing patients only
      py_imp <- py_full |>
        dplyr::left_join(imp_far_tbl, by = "ID") |>
        dplyr::mutate(
          far = dplyr::if_else(.data[[COL_EXP_MISSING]], far_imp, as.integer(as.character(.data[[COL_FAR]])))
        ) |>
        dplyr::select(-far_imp)

      py_sub <- filter_fn(py_imp)

      fit <- tryCatch(
        run_gee(py_sub, COL_CBC_YEAR, "far",
                glue("{branch} {sub_label} dataset {i}")),
        error = function(e)
          stop(glue("D-09 FAIL: GEE error branch {branch} subset {sname} dataset {i}: {e$message}"),
               call. = FALSE)
      )
      if (!is.null(fit$error) && !is.na(fit$error))
        stop(glue("D-09 FAIL: GEE error branch {branch} subset {sname} dataset {i}: {fit$error}"),
             call. = FALSE)

      b  <- log(fit$or)
      se <- (log(fit$ci_hi) - log(fit$ci_lo)) / (2 * 1.96)
      Q_vec[i]  <- b
      SE_vec[i] <- se
    }

    pooled <- pool_rubin(Q_vec, SE_vec)
    pooled_results[[result_key]] <- c(pooled, list(branch = branch, subset = sub_label))

    message(glue("  Pooled [{branch} {sub_label}]: OR={round(pooled$or, 3)} ",
                 "({round(pooled$lo, 3)}-{round(pooled$hi, 3)}) ",
                 "FMI={round(pooled$fmi, 3)} df={round(pooled$df, 1)}"))
  }
}

# ==============================================================================
# SECTION 6: REFERENCE VALUES AND WORKBOOK ----
# ==============================================================================

# --- 6a. Phase 180 KEY reader (R/182 exact-label pattern) ---
read_p180_key_val <- function(path, label) {
  key_df <- tryCatch(
    openxlsx::read.xlsx(path, sheet = "KEY"),
    error = function(e)
      stop(glue("Cannot read KEY sheet from {basename(path)}: {e$message}"), call. = FALSE)
  )
  col1 <- names(key_df)[1]
  rows <- key_df[trimws(as.character(key_df[[col1]])) == label, ]
  if (nrow(rows) != 1L) {
    avail <- paste(head(trimws(as.character(key_df[[col1]])), 30), collapse = ", ")
    stop(glue("Expected 1 row with Field='{label}' in KEY of {basename(path)}; ",
              "found {nrow(rows)}. Available: {avail}"), call. = FALSE)
  }
  # Return second column as character
  as.character(rows[[2L]][1L])
}

# Phase 180 bounding rows (MISS-02, MISS-03).
# The KEY Value column stores a formatted string e.g. "far=1: OR 0.692 (0.614-0.781)".
# Parse OR and CI bounds from the string using the R/182 approach.
parse_or_string <- function(s, label) {
  m <- regmatches(s, regexpr("OR\\s+([0-9.]+)\\s+\\(([0-9.]+)-([0-9.]+)\\)", s, perl = TRUE))
  if (length(m) == 0L || !nzchar(m))
    stop(glue("[R/183] Cannot parse OR/CI from Phase 180 KEY string for '{label}': '{s}'"),
         call. = FALSE)
  parts <- regmatches(m, regexec("OR\\s+([0-9.]+)\\s+\\(([0-9.]+)-([0-9.]+)\\)", m, perl = TRUE))[[1L]]
  vals <- list(or = as.numeric(parts[2L]), ci_lo = as.numeric(parts[3L]), ci_hi = as.numeric(parts[4L]))
  if (any(is.na(unlist(vals))))
    stop(glue("[R/183] NA after parsing OR/CI from Phase 180 KEY for '{label}': '{s}'"),
         call. = FALSE)
  vals
}

p180_miss2_raw <- read_p180_key_val(PINS$p180_xlsx$path, LBL_P180_FAR1)
p180_miss3_raw <- read_p180_key_val(PINS$p180_xlsx$path, LBL_P180_FAR0)
message(glue("  Phase 180 {LBL_P180_FAR1}: {p180_miss2_raw}"))
message(glue("  Phase 180 {LBL_P180_FAR0}: {p180_miss3_raw}"))

P180_FAR1_REF <- parse_or_string(p180_miss2_raw, LBL_P180_FAR1)
P180_FAR0_REF <- parse_or_string(p180_miss3_raw, LBL_P180_FAR0)

# Complete-case all years (P179 secondary — only include if label exists)
if (P179_HAS_SECONDARY) {
  P179_REF_ALL_USED <- P179_REF_ALL
} else {
  P179_REF_ALL_USED <- NULL
}

# --- 6b. Comparison table (D-13a) ---
fmt3 <- function(x) if (is.na(x)) "—" else formatC(round(x, 3), format = "f", digits = 3)

make_comp_row <- function(analysis, or, lo, hi, fmi = NA, df_val = NA, source = "") {
  data.frame(
    Analysis = analysis,
    OR       = fmt3(or),
    CI_lo    = fmt3(lo),
    CI_hi    = fmt3(hi),
    FMI      = if (is.na(fmi)) "—" else fmt3(fmi),
    df       = if (is.na(df_val) || is.infinite(df_val)) "—" else as.character(round(df_val, 1)),
    Source   = source,
    stringsAsFactors = FALSE
  )
}

comp_rows <- list()

# Row 1: Complete-case years 2+ (Phase 179 primary)
comp_rows[["cc_pri"]] <- make_comp_row(
  glue("Complete-case ({LBL_P179_PRIMARY})"),
  P179_REF$or, P179_REF$ci_lo, P179_REF$ci_hi,
  source = "Phase 179 workbook"
)

# Row 2: Complete-case all years (Phase 179 secondary — only if label exists)
if (!is.null(P179_REF_ALL_USED)) {
  comp_rows[["cc_all"]] <- make_comp_row(
    glue("Complete-case ({LBL_P179_SECONDARY})"),
    P179_REF_ALL_USED$or, P179_REF_ALL_USED$ci_lo, P179_REF_ALL_USED$ci_hi,
    source = "Phase 179 workbook"
  )
}

# Row 3: Phase 180 missing -> far=1
comp_rows[["p180_far1"]] <- make_comp_row(
  LBL_P180_FAR1,
  P180_FAR1_REF$or, P180_FAR1_REF$ci_lo, P180_FAR1_REF$ci_hi,
  source = "Phase 180 workbook KEY"
)

# Row 4: Phase 180 missing -> far=0
comp_rows[["p180_far0"]] <- make_comp_row(
  LBL_P180_FAR0,
  P180_FAR0_REF$or, P180_FAR0_REF$ci_lo, P180_FAR0_REF$ci_hi,
  source = "Phase 180 workbook KEY"
)

# Rows 5-8: Four pooled MICE estimates (D-12a)
for (rk in names(pooled_results)) {
  pr <- pooled_results[[rk]]
  label <- glue("MICE {pr$branch} ({pr$subset})")
  comp_rows[[rk]] <- make_comp_row(label, pr$or, pr$lo, pr$hi,
                                   fmi = pr$fmi, df_val = pr$df,
                                   source = "MICE (this script)")
}

comp_tbl <- do.call(rbind, comp_rows)
rownames(comp_tbl) <- NULL
message("\n  Comparison table (MICE-02):")
print(comp_tbl)

# --- 6c. Build workbook ---
hdr  <- openxlsx::createStyle(fgFill = "#0021A5", fontColour = "#FFFFFF", textDecoration = "bold")
sec  <- openxlsx::createStyle(fgFill = "#FA4616", fontColour = "#FFFFFF", textDecoration = "bold")
wrap <- openxlsx::createStyle(wrapText = TRUE, valign = "top")

wb <- openxlsx::createWorkbook()

# KEY sheet
key_rows <- c(
  Field = "Field", Value = "Value",  # header placeholder (writeData adds its own header)
  list(
    list(Field = "Run date",       Value = RUN_DATE),
    list(Field = "Host",           Value = Sys.info()[["nodename"]]),
    list(Field = "MICE_M",         Value = as.character(MICE_M)),
    list(Field = "MICE_MAXIT",     Value = as.character(MICE_MAXIT)),
    list(Field = "MICE_SEED",      Value = as.character(MICE_SEED)),
    list(Field = "D-01 target",    Value = "log_dist (pmm)"),
    list(Field = "D-02 target",    Value = "far (logreg)"),
    list(Field = "Predictor list", Value = paste(PRED, collapse = ", ")),
    list(Field = "DROPPED variables",
         Value = if (length(DROPPED) == 0L) "None"
                 else paste(names(DROPPED), unlist(DROPPED), sep = ": ", collapse = "; ")),
    list(Field = "Task-0 line",
         Value = glue("PASS: OR={round(t0_fit$or, 3)} ({round(t0_fit$ci_lo, 3)}-{round(t0_fit$ci_hi, 3)})")),
    list(Field = "D-09 status",    Value = "PASS (script reached workbook step)"),
    list(Field = "Privacy note",   Value = paste0(
      "Patient-level RDS in output/internal/ only. ",
      "No patient IDs or ZIPs in this workbook. Counts 1-10 as <11.")),
    list(Field = "PNG: trace",     Value = basename(trace_png)),
    list(Field = "PNG: density",   Value = basename(density_png))
  )
)

# Add PIN rows to KEY
for (nm in names(PINS)) {
  p <- PINS[[nm]]
  key_rows <- c(key_rows,
    list(list(Field = glue("PIN: {p$var}"),
              Value = glue("{p$path} (pinned={p$pinned})"))))
}

key_df <- data.frame(
  Field = sapply(key_rows[-(1:2)], `[[`, "Field"),
  Value = sapply(key_rows[-(1:2)], `[[`, "Value"),
  stringsAsFactors = FALSE
)

openxlsx::addWorksheet(wb, "KEY")
openxlsx::writeData(wb, "KEY", key_df, headerStyle = hdr)
openxlsx::addStyle(wb, "KEY", wrap, rows = 2:(nrow(key_df) + 1), cols = 1:2, gridExpand = TRUE)
openxlsx::freezePane(wb, "KEY", firstRow = TRUE)
openxlsx::setColWidths(wb, "KEY", cols = 1:2, widths = c(30, 60))

# MICE-01 sheet: methods, loggedEvents, availability, imputed counts, far proportion, FMI
openxlsx::addWorksheet(wb, "MICE-01")
cur_row <- 1L

write_sec <- function(sheet, label, row) {
  openxlsx::writeData(wb, sheet, label, startRow = row)
  openxlsx::addStyle(wb, sheet, sec, rows = row, cols = 1)
  row + 1L
}

cur_row <- write_sec("MICE-01", "Methods per variable (D-01: log_dist target, pmm)", cur_row)
meth_d01_df <- data.frame(
  Variable = names(imp_d01$method),
  Method   = unname(imp_d01$method),
  stringsAsFactors = FALSE
)
openxlsx::writeData(wb, "MICE-01", meth_d01_df, startRow = cur_row, headerStyle = hdr)
cur_row <- cur_row + nrow(meth_d01_df) + 2L

cur_row <- write_sec("MICE-01", "Methods per variable (D-02: far target, logreg)", cur_row)
meth_d02_df <- data.frame(
  Variable = names(imp_d02$method),
  Method   = unname(imp_d02$method),
  stringsAsFactors = FALSE
)
openxlsx::writeData(wb, "MICE-01", meth_d02_df, startRow = cur_row, headerStyle = hdr)
cur_row <- cur_row + nrow(meth_d02_df) + 2L

cur_row <- write_sec("MICE-01", "loggedEvents — D-01", cur_row)
le_d01_df <- if (is.null(LE_D01)) data.frame(Note = "None") else as.data.frame(LE_D01)
openxlsx::writeData(wb, "MICE-01", le_d01_df, startRow = cur_row, headerStyle = hdr)
cur_row <- cur_row + nrow(le_d01_df) + 2L

cur_row <- write_sec("MICE-01", "loggedEvents — D-02", cur_row)
le_d02_df <- if (is.null(LE_D02)) data.frame(Note = "None") else as.data.frame(LE_D02)
openxlsx::writeData(wb, "MICE-01", le_d02_df, startRow = cur_row, headerStyle = hdr)
cur_row <- cur_row + nrow(le_d02_df) + 2L

cur_row <- write_sec("MICE-01", "Predictor availability", cur_row)
openxlsx::writeData(wb, "MICE-01", avail_tbl, startRow = cur_row, headerStyle = hdr)
cur_row <- cur_row + nrow(avail_tbl) + 2L

cur_row <- write_sec("MICE-01", "Imputed far proportion (missing patients)", cur_row)
far_prop_df <- data.frame(
  Branch   = c("D-01 (derived)", "D-02 (direct)", "Observed (non-missing)"),
  Mean     = c(round(mean(far_props_d01), 4), round(mean(far_props_d02), 4), round(obs_far_prop, 4)),
  Min      = c(round(min(far_props_d01),  4), round(min(far_props_d02),  4), NA_real_),
  Max      = c(round(max(far_props_d01),  4), round(max(far_props_d02),  4), NA_real_),
  stringsAsFactors = FALSE
)
openxlsx::writeData(wb, "MICE-01", far_prop_df, startRow = cur_row, headerStyle = hdr)
cur_row <- cur_row + nrow(far_prop_df) + 2L

cur_row <- write_sec("MICE-01", "FMI and df per pooled estimate", cur_row)
fmi_rows <- do.call(rbind, lapply(names(pooled_results), function(rk) {
  pr <- pooled_results[[rk]]
  data.frame(
    Estimate = glue("{pr$branch} ({pr$subset})"),
    FMI      = round(pr$fmi, 4),
    df       = round(pr$df, 2),
    m        = pr$m,
    stringsAsFactors = FALSE
  )
}))
openxlsx::writeData(wb, "MICE-01", fmi_rows, startRow = cur_row, headerStyle = hdr)
cur_row <- cur_row + nrow(fmi_rows) + 2L

openxlsx::freezePane(wb, "MICE-01", firstRow = FALSE)

# MICE-02 sheet: comparison table
openxlsx::addWorksheet(wb, "MICE-02")
openxlsx::writeData(wb, "MICE-02", "Comparison table (D-13a): OR (3 dp), 95% CI, FMI, df",
                    startRow = 1)
openxlsx::addStyle(wb, "MICE-02", sec, rows = 1, cols = 1)
openxlsx::writeData(wb, "MICE-02", comp_tbl, startRow = 2, headerStyle = hdr)
openxlsx::freezePane(wb, "MICE-02", firstRow = FALSE, firstActiveRow = 3)
openxlsx::setColWidths(wb, "MICE-02", cols = 1:7, widths = c(40, 10, 10, 10, 10, 10, 25))

wb_path <- file.path("output", glue("mice_sensitivity_distance_{RUN_DATE}.xlsx"))
openxlsx::saveWorkbook(wb, wb_path, overwrite = TRUE)
message(glue("  Workbook saved: {wb_path}"))

# ==============================================================================
# SECTION 7: MEMO ----
# ==============================================================================

# Determine agreement: does pooled primary (D-01 years 2+) OR lie within +-0.05 of complete-case?
pool_pri <- pooled_results[["d01_pri"]]
cc_or    <- P179_REF$or
agree_diff <- abs(pool_pri$or - cc_or)
agree_word <- if (agree_diff <= 0.05) "similar to" else "differs from"
agree_rule <- glue("Agreement rule: pooled primary OR within +-0.05 of complete-case on OR scale ",
                   "(|{round(pool_pri$or, 3)} - {round(cc_or, 3)}| = {round(agree_diff, 3)}).")

pool_d02_pri <- pooled_results[["d02_pri"]]
d02_agree_diff <- abs(pool_d02_pri$or - cc_or)
d02_agree_word <- if (d02_agree_diff <= 0.05) "similar to" else "differs from"

memo_path <- file.path("output", glue("183-MEMO_{RUN_DATE}.md"))
memo_lines <- c(
  glue("# MICE Sensitivity Analysis for Distance Exposure — Memo ({RUN_DATE})"),
  "",
  glue("**Script:** R/183_mice_sensitivity_distance.R  |  **Run date:** {RUN_DATE}"),
  "",
  "## Background",
  "",
  glue("Of {n_patients} cohort patients with {n_py} patient-years, ",
       "{sup(sum(pat_mice$exposure_missing, na.rm = TRUE))} patients have missing ",
       "distance exposure after Phase 182. Two multiple-imputation runs (m = {MICE_M}) ",
       "were conducted:"),
  glue("- **D-01 (primary):** Impute `log_dist` by PMM; derive `far` via threshold ",
       "({CUTOFF} mi)."),
  glue("- **D-02 (sensitivity):** Impute `far` directly by logistic regression."),
  "",
  "## Results",
  "",
  glue("The pooled primary estimate (D-01, years 2+): OR = {round(pool_pri$or, 3)} ",
       "({round(pool_pri$lo, 3)}–{round(pool_pri$hi, 3)}), ",
       "FMI = {round(pool_pri$fmi, 3)}, df = {round(pool_pri$df, 1)}."),
  glue("This is {agree_word} the complete-case estimate ",
       "(OR = {round(cc_or, 3)}, {round(P179_REF$ci_lo, 3)}–{round(P179_REF$ci_hi, 3)}). ",
       agree_rule),
  "",
  glue("The D-02 sensitivity estimate (years 2+): OR = {round(pool_d02_pri$or, 3)} ",
       "({round(pool_d02_pri$lo, 3)}–{round(pool_d02_pri$hi, 3)}) is ",
       "{d02_agree_word} the complete-case."),
  "",
  "## Comparison to bounding analyses (Phase 180)",
  "",
  glue("- Missing assigned far=1 (Phase 180 MISS-02): {p180_miss2_raw}"),
  glue("- Missing assigned far=0 (Phase 180 MISS-03): {p180_miss3_raw}"),
  "",
  "## Method notes",
  "",
  glue("- Imputation at patient level (one row per patient, n = {n_patients})."),
  glue("- MICE settings: m = {MICE_M}, maxit = {MICE_MAXIT}, seed = {MICE_SEED}."),
  "- Predictors: prop_cbc_years, n_years_observed (outcome summary), ",
  "  dist_to_source_facility_mi (auxiliary), and available demographic/",
  "  clinical variables.",
  paste("- DROPPED variables:", if (length(DROPPED) == 0L) "None"
        else paste(names(DROPPED), unlist(DROPPED), sep = ": ", collapse = "; ")),
  "- Phase 179 GEE refitted in each completed dataset; Rubin's rules with ",
  "  Barnard–Rubin degrees of freedom and t quantile (not z).",
  "- Observed far values are never changed; only missing-exposure patients ",
  "  receive imputed values.",
  "",
  "## Outputs",
  "",
  glue("- Workbook: {basename(wb_path)}"),
  glue("- Trace PNG: {basename(trace_png)}"),
  glue("- Density PNG: {basename(density_png)}"),
  glue("- Patient-level mids: {basename(mids_path)} (output/internal/)"),
  ""
)
writeLines(memo_lines, memo_path)
message(glue("  Memo saved: {memo_path}"))

# ==============================================================================
# SECTION 8: OUTPUT PATHS AND CLOSE ----
# ==============================================================================

message("\n==== R/183 output paths ====")
message(glue("  Workbook:    {wb_path}"))
message(glue("  Trace PNG:   {trace_png}"))
message(glue("  Density PNG: {density_png}"))
message(glue("  Memo:        {memo_path}"))
message(glue("  mids RDS:    {mids_path}"))
message(glue("  Input RDS:   output/internal/mice_input_patient_{RUN_DATE}.rds"))
message("\n==== R/183 mice_sensitivity_distance COMPLETE ====")
