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
  on.exit(try(DBI::dbDisconnect(con183), silent = TRUE), add = TRUE)
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
  on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)
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
  dplyr::left_join(ssc, by = "ID") |>
  dplyr::left_join(dplyr::select(adi_lkp, pat_zip5, adi), by = "pat_zip5")

if (demo_avail && !is.null(age_sex)) {
  age_sex_pat <- age_sex |>
    dplyr::left_join(anchors, by = "ID") |>
    dplyr::transmute(
      ID,
      age_at_anchor = as.numeric(difftime(anchor, BIRTH_DATE, units = "days")) / 365.25,
      sex = factor(SEX))
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
       ci_lo = as.numeric(rows$CI_lo),
       ci_hi = as.numeric(rows$CI_hi))
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

message("==== R/183 Plan 01 complete: stopped after reproduction gate ====")
