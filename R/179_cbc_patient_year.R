# ==============================================================================
# 179_cbc_patient_year.R -- CBC within each follow-up year (patient-year analysis)
# ==============================================================================
#
# Purpose:
#   Patient-year re-specification of the Phase 165 question. For every HL cohort
#   patient with a known hl_anchor_date (R/147), build fully observed follow-up
#   years (anchor + 365*(k-1), anchor + 365*k], flag >= 1 CBC in each year, and
#   estimate the association with living far from care (patient-level median
#   post-anchor encounter distance > CONFIG$far_from_care_cutoff_mi) using GEE.
#   Companion to Phase 165 (encounter-level); which is primary is pending (D-15).
#
# Inputs:
#   R/147 patient RDS via the Phase 170 pointer output/logs/147_verify_last_pass.txt
#   R/122 enc_distance RDS (pin with R179_R122_RDS; else most recent)
#   R/121 zip_problem_inventory RDS (pin with R179_R121_RDS; else most recent)
#   DuckDB: LAB_RESULT_CM (build_cbc_events() + broad hematology), DEATH (if present)
#   EXTRACT_DATE (R/00_config.R) = CDM data cutoff
#   Phase 165 workbook distance_cbc_association_20261008.xlsx (KEY side-by-side)
#
# Outputs:
#   output/internal/cbc_patient_year_<YYYYMMDD>.rds   (patient-year detail; Phase 180 input)
#   output/cbc_patient_year_<YYYYMMDD>.xlsx           (KEY | Descriptives | Per_Year | Model_Results)
#
# Requirements: CBCY-01 .. CBCY-05   Decisions: 179-CONTEXT D-01 .. D-19
#
# Usage (HiPerGator, repo root):
#   module load R/4.5 ; R
#   source("R/179_cbc_patient_year.R", local = new.env(parent = globalenv()))
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
message(glue("==== R/179 cbc_patient_year -- RUN DATE {RUN_DATE} ===="))

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

message(glue("  CDM cutoff {CDM_CUTOFF} (EXTRACT_DATE) | far > {CUTOFF} mi | corstr {GEE_CORSTR}"))

BROAD_LOINCS <- c("6690-2", "718-7", "777-3", "4544-3", "789-8", "787-2", "785-6",
                  "786-4", "788-0", "770-8", "26499-4", "731-0", "58410-2",
                  "57021-8", "57782-5")

# Phase 165 side-by-side: read from B_test sheet (Window / OR / CI_lo / CI_hi / p_svyglm).
# Exact column names required; stops with a message if any are missing.
P165_XLSX <- file.path(CONFIG$output_dir, "distance_cbc_association_20261008.xlsx")
# Expected exact values in the Window column:
P165_WINDOWS <- c("Whole record", "Post-anchor")

# --- Helpers ------------------------------------------------------------------
sup <- function(x) {                       # counts 1-10 -> "<11" (vectorised)
  x <- as.numeric(x)
  ifelse(is.na(x), NA_character_,
         ifelse(x >= 1 & x <= 10, "<11", format(x, big.mark = ",", trim = TRUE)))
}
show_rate <- function(num, den) {          # rate only if both >= 11
  if (is.na(num) || is.na(den) || num < 11 || den < 11) return("—")
  paste0(round(100 * num / den, 1), "%")
}
crude_or <- function(a, b, c, d) {         # a,b = not-far no/yes ; c,d = far no/yes
  if (any(c(a, b, c, d) == 0)) { a <- a + .5; b <- b + .5; c <- c + .5; d <- d + .5 }
  (a * d) / (b * c)
}
as_id <- function(x) as.character(x)

# ==============================================================================
# SECTION 1: INPUTS ----
# ==============================================================================

# --- 1a. Anchors from the verified R/147 run (Phase 170 pointer) ---------------
ptr_path <- file.path(CONFIG$output_dir, "logs", "147_verify_last_pass.txt")
stopifnot("Phase 170 pointer 147_verify_last_pass.txt not found -- run the R/147 verify first" =
            file.exists(ptr_path))
ptr_lines <- readLines(ptr_path, warn = FALSE)
ptr_get <- function(key) {
  hit <- grep(paste0("^", key, "\\s*="), ptr_lines, value = TRUE)
  if (length(hit) == 0L) return(NA_character_)
  trimws(sub("^[^=]*=", "", hit[1]))
}
r147_rds <- ptr_get("rds_path")
if (is.na(r147_rds)) r147_rds <- ptr_get("rds")
if (is.na(r147_rds)) {
  r147_run_date <- ptr_get("run_date")
  stopifnot("Pointer has neither rds/rds_path nor run_date" = !is.na(r147_run_date))
  r147_rds <- file.path(CONFIG$cache$outputs_dir,
                        sprintf("surveillance_modality_patient_%s.rds", r147_run_date))
}
stopifnot("R/147 patient RDS named by the pointer does not exist" = file.exists(r147_rds))
message(glue("  R/147 anchor RDS (verified pointer): {basename(r147_rds)}"))

r147_raw <- readRDS(r147_rds)
stopifnot("R/147 RDS lacks ID or hl_anchor_date" =
            all(c("ID", "hl_anchor_date") %in% names(r147_raw)))
anchors <- r147_raw |>
  dplyr::transmute(ID = as_id(ID), hl_anchor_date = as.Date(hl_anchor_date)) |>
  dplyr::distinct()
stopifnot("R/147 RDS has more than one anchor date for some patients" =
            !anyDuplicated(anchors$ID))
anchor_source <- glue("R/147 RDS {basename(r147_rds)} (via 147_verify_last_pass.txt)")
n_anchor_na <- sum(is.na(anchors$hl_anchor_date))
message(glue("  Anchors: {nrow(anchors)} patients; {n_anchor_na} with missing hl_anchor_date."))

# Cohort cross-check vs Phase 165 source (informational; never replaces anchors)
xcheck_text <- tryCatch({
  a165 <- get_hl_any_dx_ids()
  ids165 <- unique(as_id(a165$ID[!is.na(a165$hl_anchor_date)]))
  ids179 <- unique(anchors$ID[!is.na(anchors$hl_anchor_date)])
  txt <- glue("Phase 165 source {length(ids165)} pts; R/179 {length(ids179)} pts; ",
              "in 179 not 165: {sum(!ids179 %in% ids165)}; in 165 not 179: {sum(!ids165 %in% ids179)}")
  message("  Cohort cross-check: ", txt)
  txt
}, error = function(e) {
  message("  Cohort cross-check not run: ", conditionMessage(e))
  paste("not run:", conditionMessage(e))
})

# --- 1b. enc_distance (R/122) -------------------------------------------------
r122_override <- Sys.getenv("R179_R122_RDS", unset = "")
if (nzchar(r122_override)) {
  stopifnot("R179_R122_RDS file not found" = file.exists(r122_override))
  enc_dist_path <- r122_override; r122_pinned <- TRUE
} else {
  cand <- list.files(CONFIG$output_dir, "^encounter_distance.*\\.rds$", full.names = TRUE)
  stopifnot("enc_distance RDS not found -- run R/122 or set R179_R122_RDS" = length(cand) > 0L)
  enc_dist_path <- cand[which.max(file.mtime(cand))]; r122_pinned <- FALSE
}
enc_distance <- readRDS(enc_dist_path)
stopifnot("enc_distance missing required columns" =
            all(c("ID", "ADMIT_DATE", "distance_status", "distance_mi") %in% names(enc_distance)))
enc_distance <- enc_distance |>
  dplyr::mutate(ID = as_id(ID), ADMIT_DATE = as.Date(ADMIT_DATE))
message(glue("  enc_distance: {basename(enc_dist_path)} ({format(nrow(enc_distance), big.mark = ',')} rows; pinned={r122_pinned})"))

# --- 1c. R/121 triage ---------------------------------------------------------
r121_override <- Sys.getenv("R179_R121_RDS", unset = "")
if (nzchar(r121_override)) {
  stopifnot("R179_R121_RDS file not found" = file.exists(r121_override))
  r121_path <- r121_override
} else {
  cand <- list.files(CONFIG$output_dir, "^zip_problem_inventory.*\\.rds$", full.names = TRUE)
  stopifnot("R/121 RDS not found -- run R/121 or set R179_R121_RDS" = length(cand) > 0L)
  r121_path <- cand[which.max(file.mtime(cand))]
}
r121_raw <- readRDS(r121_path)
pat121 <- if (is.list(r121_raw) && !is.data.frame(r121_raw) && "patients" %in% names(r121_raw))
  r121_raw$patients else r121_raw
key121 <- intersect(c("ID", "PATID"), names(pat121))[1]
stopifnot("R/121 patients table lacks ID/PATID or triage" =
            !is.na(key121) && "triage" %in% names(pat121))
triage_map <- pat121 |>
  dplyr::transmute(ID = as_id(.data[[key121]]), triage = as.character(triage)) |>
  dplyr::distinct(ID, .keep_all = TRUE)
message(glue("  R/121 triage: {basename(r121_path)} ({nrow(triage_map)} patients)"))

# --- 1d-1h. DuckDB: CBC events, broad hematology, death -----------------------
opened_here <- FALSE
if (!exists("pcornet_con", envir = .GlobalEnv)) { open_pcornet_con(); opened_here <- TRUE }

cohort_ids <- unique(anchors$ID[!is.na(anchors$hl_anchor_date)])

cbc_events <- build_cbc_events(pcornet_con, cohort_ids) |>
  dplyr::transmute(ID = as_id(ID), cbc_date = as.Date(cbc_date)) |>
  dplyr::filter(!is.na(cbc_date)) |>
  dplyr::distinct()
message(glue("  cbc_events: {format(nrow(cbc_events), big.mark = ',')} patient-dates"))

tables  <- toupper(DBI::dbListTables(pcornet_con))
id_sql  <- paste(sprintf("'%s'", gsub("'", "''", cohort_ids)), collapse = ", ")
lab_fld <- toupper(DBI::dbListFields(pcornet_con, "LAB_RESULT_CM"))
lab_id  <- intersect(c("ID", "PATID"), lab_fld)[1]
stopifnot("LAB_RESULT_CM has neither ID nor PATID" = !is.na(lab_id))

broad_sql <- sprintf("
  SELECT DISTINCT %s AS ID,
         COALESCE(TRY_CAST(RESULT_DATE AS DATE), TRY_CAST(SPECIMEN_DATE AS DATE),
                  TRY_CAST(LAB_ORDER_DATE AS DATE)) AS lab_date
  FROM LAB_RESULT_CM
  WHERE %s IN (%s) AND LAB_LOINC IN (%s)",
  lab_id, lab_id, id_sql, paste(sprintf("'%s'", BROAD_LOINCS), collapse = ", "))
broad_events <- DBI::dbGetQuery(pcornet_con, broad_sql) |>
  dplyr::transmute(ID = as_id(ID), lab_date = as.Date(lab_date)) |>
  dplyr::filter(!is.na(lab_date)) |>
  dplyr::distinct()
message(glue("  broad hematology: {format(nrow(broad_events), big.mark = ',')} patient-dates"))

if ("DEATH" %in% tables) {
  d_fld <- toupper(DBI::dbListFields(pcornet_con, "DEATH"))
  d_id  <- intersect(c("ID", "PATID"), d_fld)[1]
  stopifnot("DEATH has neither ID nor PATID" = !is.na(d_id), "DEATH lacks DEATH_DATE" = "DEATH_DATE" %in% d_fld)
  death_dates <- DBI::dbGetQuery(pcornet_con, sprintf("
    SELECT %s AS ID, MIN(TRY_CAST(DEATH_DATE AS DATE)) AS death_date
    FROM DEATH WHERE %s IN (%s) AND DEATH_DATE IS NOT NULL GROUP BY %s",
    d_id, d_id, id_sql, d_id)) |>
    dplyr::transmute(ID = as_id(ID), death_date = as.Date(death_date))
  death_source <- glue("DEATH table ({nrow(death_dates)} cohort patients with a death date)")
} else {
  death_dates  <- dplyr::tibble(ID = character(0), death_date = as.Date(character(0)))
  death_source <- "DEATH table absent -- no death censoring"
}
message("  Death: ", death_source)

if (opened_here) close_pcornet_con()

# ==============================================================================
# SECTION 2: PATIENT-YEAR TABLE (D-01, D-03, D-04) ----
# ==============================================================================

anchors_known <- dplyr::filter(anchors, !is.na(hl_anchor_date))
anchors_kmax <- anchors_known |>
  dplyr::mutate(k_max = as.integer(floor(as.numeric(CDM_CUTOFF - hl_anchor_date) / 365))) |>
  dplyr::filter(k_max >= 1L)

py_raw <- anchors_kmax |>
  tidyr::uncount(k_max, .id = "year_index") |>
  dplyr::mutate(year_index = as.integer(year_index),
                year_start = hl_anchor_date + 365L * (year_index - 1L),
                year_end   = hl_anchor_date + 365L * year_index)
stopifnot(all(py_raw$year_end <= CDM_CUTOFF))

py <- py_raw |>
  dplyr::left_join(death_dates, by = "ID") |>
  dplyr::filter(is.na(death_date) | death_date > year_end) |>
  dplyr::select(-death_date)

n_py_before <- nrow(py_raw); n_py_after <- nrow(py)
message(glue(
  "  Patients with anchor: {nrow(anchors_known)}; with >=1 full year: {nrow(anchors_kmax)}\n",
  "  Patient-years: {format(n_py_before, big.mark = ',')} before death censoring; ",
  "{format(n_py_after, big.mark = ',')} after"))

py_keys <- dplyr::select(py, ID, year_index, year_start, year_end)

# ==============================================================================
# SECTION 3: FLAGS AND RDS (D-05 .. D-09, D-17) ----
# ==============================================================================

# 3a/3b. Outcomes via inequality joins: event in (year_start, year_end]
cbc_flag <- py_keys |>
  dplyr::inner_join(cbc_events, by = dplyr::join_by(ID, year_start < cbc_date, year_end >= cbc_date)) |>
  dplyr::distinct(ID, year_index) |>
  dplyr::mutate(cbc_year = 1L)

broad_flag <- py_keys |>
  dplyr::inner_join(broad_events, by = dplyr::join_by(ID, year_start < lab_date, year_end >= lab_date)) |>
  dplyr::distinct(ID, year_index) |>
  dplyr::mutate(cbc_year_broad = 1L)

# 3c. Primary exposure: patient median over post-anchor computed encounters
enc_computed <- enc_distance |>
  dplyr::filter(distance_status == "computed", !is.na(ADMIT_DATE), !is.na(distance_mi)) |>
  dplyr::select(ID, ADMIT_DATE, distance_mi)

pat_exposure <- enc_computed |>
  dplyr::inner_join(anchors_known, by = "ID") |>
  dplyr::filter(ADMIT_DATE > hl_anchor_date, ADMIT_DATE <= CDM_CUTOFF) |>
  dplyr::group_by(ID) |>
  dplyr::summarise(median_distance = stats::median(distance_mi), .groups = "drop")

# 3d. Sensitivity exposure: per-year median
year_exposure <- py_keys |>
  dplyr::inner_join(enc_computed, by = dplyr::join_by(ID, year_start < ADMIT_DATE, year_end >= ADMIT_DATE)) |>
  dplyr::group_by(ID, year_index) |>
  dplyr::summarise(year_median_dist = stats::median(distance_mi), .groups = "drop")

py_final <- py |>
  dplyr::left_join(cbc_flag,   by = c("ID", "year_index")) |>
  dplyr::left_join(broad_flag, by = c("ID", "year_index")) |>
  dplyr::left_join(pat_exposure, by = "ID") |>
  dplyr::left_join(year_exposure, by = c("ID", "year_index")) |>
  dplyr::left_join(triage_map, by = "ID") |>
  dplyr::mutate(
    cbc_year         = dplyr::coalesce(cbc_year, 0L),
    cbc_year_broad   = dplyr::coalesce(cbc_year_broad, 0L),
    exposure_missing = is.na(median_distance),
    far              = dplyr::if_else(exposure_missing, NA_integer_, as.integer(median_distance > CUTOFF)),
    far_year_median  = dplyr::if_else(is.na(year_median_dist), NA_integer_, as.integer(year_median_dist > CUTOFF)),
    triage           = dplyr::coalesce(triage, "not in R/121")
  ) |>
  dplyr::select(ID, year_index, year_start, year_end, cbc_year, cbc_year_broad,
                median_distance, far, far_year_median, exposure_missing, triage)

stopifnot(
  "Row count changed in flag joins"        = nrow(py_final) == n_py_after,
  "Duplicate (ID, year_index)"             = !anyDuplicated(py_final[, c("ID", "year_index")]),
  "cbc_year not 0/1"                       = all(py_final$cbc_year %in% 0:1),
  "cbc_year_broad not 0/1"                 = all(py_final$cbc_year_broad %in% 0:1),
  "far not NA for missing exposure"        = all(is.na(py_final$far[py_final$exposure_missing])),
  "year_end beyond CDM cutoff"             = all(py_final$year_end <= CDM_CUTOFF)
)

internal_dir <- file.path(CONFIG$output_dir, "internal")
dir.create(internal_dir, recursive = TRUE, showWarnings = FALSE)
rds_out <- file.path(internal_dir, glue("cbc_patient_year_{RUN_DATE}.rds"))
saveRDS(py_final, rds_out)
message(glue("  Saved {rds_out} ({format(nrow(py_final), big.mark = ',')} patient-years, ",
             "{dplyr::n_distinct(py_final$ID)} patients)"))

# ==============================================================================
# SECTION 4: SUBSETS AND DESCRIPTIVES (D-10, D-12, D-13) ----
# ==============================================================================

py <- py_final |>
  dplyr::mutate(year_index_cat = factor(dplyr::if_else(year_index >= 5L, "5+", as.character(year_index)),
                                        levels = c("1", "2", "3", "4", "5+")))
py_all     <- dplyr::filter(py, !exposure_missing)
py_primary <- dplyr::filter(py_all, year_index >= 2L)
py_yr1     <- dplyr::filter(py_all, year_index == 1L)

n_missing_pat <- dplyr::n_distinct(py$ID[py$exposure_missing])
n_missing_py  <- sum(py$exposure_missing)
message(glue(
  "  Subsets: all-exposure {nrow(py_all)} py / {dplyr::n_distinct(py_all$ID)} pts; ",
  "years 2+ {nrow(py_primary)} py / {dplyr::n_distinct(py_primary$ID)} pts; ",
  "year 1 {nrow(py_yr1)} py; missing exposure {n_missing_py} py / {n_missing_pat} pts"))

# 4a. Exposure distribution (patients)
pat_level <- dplyr::distinct(py, ID, median_distance, far)
q_probs   <- c(.05, .10, .25, .50, .75, .90, .95)
dist_q    <- stats::quantile(pat_level$median_distance, q_probs, na.rm = TRUE)
desc_4a <- data.frame(
  Metric = c(paste0("Patient median distance (mi), P", q_probs * 100),
             "Patients: far", "Patients: not far", "Patients: missing exposure"),
  Value  = c(as.character(round(dist_q, 1)),
             sup(sum(pat_level$far == 1L, na.rm = TRUE)),
             sup(sum(pat_level$far == 0L, na.rm = TRUE)),
             sup(sum(is.na(pat_level$far)))),
  stringsAsFactors = FALSE)

# 4b. Per year index
desc_4b <- do.call(rbind, lapply(levels(py_all$year_index_cat), function(yr) {
  d <- dplyr::filter(py_all, year_index_cat == yr)
  n_f <- sum(d$far == 1L); n_n <- sum(d$far == 0L)
  y_f <- sum(d$cbc_year[d$far == 1L]); y_n <- sum(d$cbc_year[d$far == 0L])
  cells <- c(n_n - y_n, y_n, n_f - y_f, y_f)
  or_txt <- if (n_f == 0 || n_n == 0) "—"
            else if (any(cells >= 1 & cells <= 10)) "suppressed"
            else as.character(round(crude_or(cells[1], cells[2], cells[3], cells[4]), 2))
  data.frame(Year_index = yr,
             PY_far = sup(n_f), PY_not_far = sup(n_n),
             CBC_years_far = sup(y_f), CBC_years_not_far = sup(y_n),
             Rate_far = show_rate(y_f, n_f), Rate_not_far = show_rate(y_n, n_n),
             Crude_OR = or_txt, stringsAsFactors = FALSE)
}))

# 4c. Year 1 2x2 -- full table only if no interior cell is 1-10
t1 <- table(factor(py_yr1$far, levels = 0:1), factor(py_yr1$cbc_year, levels = 0:1))
m1 <- matrix(as.numeric(t1), 2)            # rows far 0/1; cols CBC no/yes
if (any(m1 >= 1 & m1 <= 10)) {
  desc_4c <- data.frame(
    Item  = c("Year-1 patient-years (all)", "CBC rate, not far", "CBC rate, far",
              "Note"),
    Value = c(sup(sum(m1)), show_rate(m1[1, 2], sum(m1[1, ])), show_rate(m1[2, 2], sum(m1[2, ])),
              "Cell counts withheld: at least one cell is 1-10"),
    stringsAsFactors = FALSE)
} else {
  desc_4c <- data.frame(
    Exposure = c("not far", "far", "Total"),
    CBC_no   = sup(c(m1[1, 1], m1[2, 1], sum(m1[, 1]))),
    CBC_yes  = sup(c(m1[1, 2], m1[2, 2], sum(m1[, 2]))),
    Total    = sup(c(sum(m1[1, ]), sum(m1[2, ]), sum(m1))),
    stringsAsFactors = FALSE)
}

# ==============================================================================
# SECTION 5: GEE MODELS (D-11 .. D-13) ----
# ==============================================================================

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
  b <- cf["x", "Estimate"]; se <- cf["x", "Std.err"]     # robust (sandwich) SE
  c(base, list(method = glue("GEE ({GEE_CORSTR})"),
               or = exp(b), ci_lo = exp(b - 1.96 * se), ci_hi = exp(b + 1.96 * se),
               p = cf["x", "Pr(>|W|)"],
               warnings = paste(unique(warns), collapse = " | "),
               error = NA_character_, secs = secs))
}

message(glue("  GEE input sizes: years 2+ {nrow(py_primary)} rows, ",
             "{dplyr::n_distinct(py_primary$ID)} clusters, max cluster {if (nrow(py_primary)) max(table(py_primary$ID)) else 0}"))

res_primary   <- run_gee(py_primary, "cbc_year",       "far",             "Primary: years 2+")
res_secondary <- run_gee(py_all,     "cbc_year",       "far",             "Secondary: all years")
py_sens_yr    <- dplyr::filter(py_primary, !is.na(far_year_median))
message(glue("  Per-year exposure sensitivity drops {nrow(py_primary) - nrow(py_sens_yr)} py and ",
             "{dplyr::n_distinct(py_primary$ID) - dplyr::n_distinct(py_sens_yr$ID)} patients vs primary"))
res_sens_exp  <- run_gee(py_sens_yr, "cbc_year",       "far_year_median", "Sensitivity: per-year median exposure, years 2+")
res_sens_out  <- run_gee(py_primary, "cbc_year_broad", "far",             "Sensitivity: broad hematology outcome, years 2+")
all_fits <- list(res_primary, res_secondary, res_sens_exp, res_sens_out)

fmt_result <- function(r) {
  if (grepl("FALLBACK", r$method))
    return(glue("{r$label}: FALLBACK crude OR {round(r$or, 2)} (no CI); error: {r$error}"))
  glue("{r$label}: OR {round(r$or, 2)} ({round(r$ci_lo, 2)}-{round(r$ci_hi, 2)}), ",
       "p={format.pval(r$p, digits = 3)}, {r$method}, {r$secs}s",
       "{if (nzchar(r$warnings)) paste0('; WARNINGS: ', r$warnings) else ''}")
}
for (r in all_fits) message("  ", fmt_result(r))

# ==============================================================================
# SECTION 6: WORKBOOK (D-16) ----
# ==============================================================================

p165_text <- if (!file.exists(P165_XLSX)) {
  glue("{basename(P165_XLSX)} not found -- cannot add Phase 165 side-by-side")
} else {
  b165 <- readxl::read_excel(P165_XLSX, sheet = "B_test", col_types = "text")
  req_cols <- c("Window", "Method", "OR", "CI_lo", "CI_hi", "p_svyglm")
  missing_cols <- setdiff(req_cols, names(b165))
  if (length(missing_cols) > 0L)
    stop("B_test sheet missing required columns: ", paste(missing_cols, collapse = ", "))
  missing_windows <- setdiff(P165_WINDOWS, trimws(b165$Window))
  if (length(missing_windows) > 0L)
    stop("B_test sheet missing expected Window values: ", paste(missing_windows, collapse = ", "))
  rows <- lapply(P165_WINDOWS, function(w) {
    r <- b165[trimws(b165$Window) == w, , drop = FALSE]
    glue("{w} ({r$Method[1]}): OR {r$OR[1]} ({r$CI_lo[1]}–{r$CI_hi[1]}), p={r$p_svyglm[1]}")
  })
  paste(rows, collapse = "; ")
}
if (grepl("not found", p165_text))
  message("  [ACTION] Phase 165 side-by-side: ", p165_text)

key_df <- data.frame(
  Field = c("Analysis", "Relation to Phase 165", "Run date", "Unit", "Fully observed years",
            "CDM cutoff", "Anchor source", "Cohort cross-check", "Death source",
            "enc_distance file", "R/121 file", "Primary outcome", "Sensitivity outcome",
            "Primary exposure", "Sensitivity exposure", "Model", "Why years 2+ are primary",
            "Missing exposure (excluded)",
            "Primary OR", "Secondary OR", "Sensitivity OR (per-year exposure)",
            "Sensitivity OR (broad outcome)", "Phase 165 (encounter-level) ORs",
            "Primary analysis choice", "Suppression", "Patient-year RDS",
            "Missing-exposure limitation (Phase 180, D-05)"),
  Value = c(
    "Far from care (>100 mi) x CBC within each follow-up year (patient-year)",
    "Companion to Phase 165 (encounter-level: CBC drawn during the encounter). Which is primary is pending (D-15, with D-165-01).",
    RUN_DATE,
    "Patient-year: year k = (anchor + 365*(k-1), anchor + 365*k]; anchor day = pre",
    "Year end <= CDM cutoff and patient alive at year end; not based on last in-system contact",
    glue("{CDM_CUTOFF} (EXTRACT_DATE, R/00_config.R)"),
    anchor_source, xcheck_text, death_source,
    glue("{basename(enc_dist_path)} (pinned via R179_R122_RDS: {r122_pinned})"),
    basename(r121_path),
    "cbc_year: >=1 CBC event (WBC 6690-2 + Hgb 718-7 + PLT 777-3 same date; build_cbc_events()) in the year",
    "cbc_year_broad: >=1 result for any of 15 hematology LOINCs in the year",
    glue("Patient median distance_mi over post-anchor computed encounters (R/122); far = median > {CUTOFF} mi"),
    "Median distance over computed encounters within that year (years without one excluded)",
    glue("geepack::geeglm, binomial logit, corstr = {GEE_CORSTR}, clustered on patient, adjusted for year index (1,2,3,4,5+); robust 95% CI"),
    "Year 1 overlaps primary treatment, when CBCs are near-universal; year 1 shown descriptively only",
    glue("{sup(n_missing_pat)} patients / {sup(n_missing_py)} patient-years (analysed in Phase 180)"),
    fmt_result(res_primary), fmt_result(res_secondary), fmt_result(res_sens_exp), fmt_result(res_sens_out),
    p165_text,
    "Pending team decision (D-15, with D-165-01)",
    "Counts 1-10 shown as <11; rates and crude ORs shown only when underlying counts are >= 11",
    basename(rds_out),
    paste0("Phase 180 bounding (D-05): missing-exposure patients assigned far=1 -> OR 0.776 (0.693-0.867); ",
           "far=0 -> OR 0.872 (0.751-1.012). Both bounded ORs below 1 (same side as primary OR 0.845). ",
           "D-05 branch: same side -> stated limitation. Limitation: patients with missing exposure are excluded; ",
           "bounding shows the primary association is robust to their exclusion (bounded ORs remain below 1), ",
           "but confidence intervals widen when missing patients are assigned far=0. Source: Phase 180 workbook ",
           "cbc_missing_capture_20261013.xlsx.")),
  stringsAsFactors = FALSE)

model_df <- do.call(rbind, lapply(all_fits, function(r) data.frame(
  Analysis = r$label, Method = r$method,
  Patient_years = sup(r$n_py), Patients = sup(r$n_pat),
  OR = round(r$or, 3), CI_low = round(r$ci_lo, 3), CI_high = round(r$ci_hi, 3),
  p = if (is.na(r$p)) NA_character_ else format.pval(r$p, digits = 3),
  Seconds = r$secs, Warnings = r$warnings,
  Error = if (is.na(r$error)) "" else r$error, stringsAsFactors = FALSE)))

hdr <- openxlsx::createStyle(fgFill = "#0021A5", fontColour = "#FFFFFF", textDecoration = "bold")
sec <- openxlsx::createStyle(fgFill = "#FA4616", fontColour = "#FFFFFF", textDecoration = "bold")
wrap <- openxlsx::createStyle(wrapText = TRUE, valign = "top")

wb <- openxlsx::createWorkbook()
openxlsx::addWorksheet(wb, "KEY")
openxlsx::writeData(wb, "KEY", key_df, headerStyle = hdr)
openxlsx::addStyle(wb, "KEY", wrap, rows = 2:(nrow(key_df) + 1), cols = 1:2, gridExpand = TRUE)
openxlsx::setColWidths(wb, "KEY", 1:2, c(34, 110))

openxlsx::addWorksheet(wb, "Descriptives")
openxlsx::writeData(wb, "Descriptives", "Patient-level exposure distribution", startRow = 1)
openxlsx::addStyle(wb, "Descriptives", sec, rows = 1, cols = 1)
openxlsx::writeData(wb, "Descriptives", desc_4a, startRow = 2, headerStyle = hdr)
r0 <- nrow(desc_4a) + 4
openxlsx::writeData(wb, "Descriptives", "Year 1 -- descriptive only, not in the primary model", startRow = r0)
openxlsx::addStyle(wb, "Descriptives", sec, rows = r0, cols = 1)
openxlsx::writeData(wb, "Descriptives", desc_4c, startRow = r0 + 1, headerStyle = hdr)
openxlsx::setColWidths(wb, "Descriptives", 1:4, c(40, 18, 18, 18))

openxlsx::addWorksheet(wb, "Per_Year")
openxlsx::writeData(wb, "Per_Year", desc_4b, headerStyle = hdr)
openxlsx::setColWidths(wb, "Per_Year", 1:ncol(desc_4b), 16)

openxlsx::addWorksheet(wb, "Model_Results")
openxlsx::writeData(wb, "Model_Results", model_df, headerStyle = hdr)
fb <- which(grepl("FALLBACK", model_df$Method) | nzchar(model_df$Warnings)) + 1L
if (length(fb)) openxlsx::addStyle(wb, "Model_Results", sec, rows = fb, cols = 1:ncol(model_df), gridExpand = TRUE)
openxlsx::setColWidths(wb, "Model_Results", 1:ncol(model_df), c(46, 22, 14, 10, 8, 8, 8, 10, 8, 40, 30))

wb_path <- file.path(CONFIG$output_dir, glue("cbc_patient_year_{RUN_DATE}.xlsx"))
openxlsx::saveWorkbook(wb, wb_path, overwrite = TRUE)

# ==============================================================================
# SECTION 7: SUMMARY ----
# ==============================================================================

message(glue(
  "==== R/179 COMPLETE -- {RUN_DATE} ====\n",
  "  RDS      : {rds_out}\n",
  "  Workbook : {wb_path}\n",
  "  {fmt_result(res_primary)}\n",
  "  {fmt_result(res_secondary)}\n",
  "  {fmt_result(res_sens_exp)}\n",
  "  {fmt_result(res_sens_out)}\n",
  "  Phase 165 side-by-side: {p165_text}\n",
  "  Primary-analysis choice (165 vs 179): pending (D-15 / D-165-01)"))
