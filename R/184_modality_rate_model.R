# ==============================================================================
# 184_modality_rate_model.R -- Modality Rate Model: far × modality interaction
# ==============================================================================
#
# Purpose:
#   Per-modality surveillance rate tables (MODR-01) and a Poisson GEE count
#   model with a far × modality interaction (MODR-02). Uses the Phase 179
#   pinned patient-year cohort and the R/166 dated modality events.
#   Plan 01: Sections 0-3 (setup, pins, gate, long frame).
#   Plan 02: Sections 4+ (rates, models, workbook, memo, registration).
#
# Inputs (pinned via env vars, D-25):
#   R184_P179_RDS   output/internal/cbc_patient_year_20261015.rds
#   R184_P179_XLSX  output/cbc_patient_year_20261015.xlsx
#   R184_EVENTS_RDS output/internal/survivorship_dated_events_<YYYYMMDD>.rds
#   R/147 patient-modality RDS (via 147_verify_last_pass.txt pointer)
#
# Outputs (Plan 01):
#   output/internal/modality_long_<YYYYMMDD>.rds   (long patient-year frame)
#
# Requirements: MODR-01, MODR-02   Decisions: 184-CONTEXT D-01..D-28
#
# Usage (HiPerGator, repo root):
#   module load R/4.5 ; R
#   source("R/184_modality_rate_model.R", local = new.env(parent = globalenv()))
# ==============================================================================

# ==============================================================================
# SECTION 0: SETUP ----
# ==============================================================================

source("R/00_config.R")

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(geepack)
  library(MASS)
  library(glue)
  library(readxl)
  library(openxlsx)
})
if (requireNamespace("sandwich", quietly = TRUE)) {
  library(sandwich)
  message("  sandwich loaded (available for NB sensitivity SEs)")
} else {
  message("  NOTE: sandwich package not found in renv; NB sensitivity robust SEs unavailable.",
          " Install interactively and renv::snapshot() if needed.")
}

stopifnot("dplyr >= 1.1.0 required for inequality joins" =
            utils::packageVersion("dplyr") >= "1.1.0")

RUN_DATE <- format(Sys.Date(), "%Y%m%d")
message(glue("==== R/184 modality_rate_model -- RUN DATE {RUN_DATE} ===="))

CUTOFF       <- CONFIG$far_from_care_cutoff_mi
P179_CORSTR  <- CONFIG$distance_gee_corstr   # "exchangeable" -- gate only
MODR_CORSTR  <- "independence"               # D-04: modality model working corstr

stopifnot(
  "far_from_care_cutoff_mi must be a positive number" =
    is.numeric(CUTOFF) && length(CUTOFF) == 1L && !is.na(CUTOFF) && CUTOFF > 0,
  "distance_gee_corstr must be a non-empty string" =
    is.character(P179_CORSTR) && nzchar(P179_CORSTR)
)

# --- Task 0 name constants (D-26) ---
# Phase 179 RDS columns (R/179 select line 309):
COL_ID          <- "ID"
COL_YEAR_INDEX  <- "year_index"
COL_YEAR_START  <- "year_start"
COL_YEAR_END    <- "year_end"
COL_CBC_YEAR    <- "cbc_year"
COL_FAR         <- "far"
COL_EXP_MISSING <- "exposure_missing"

# R/166 survivorship_dated_events columns:
COL_EVT_ID      <- "ID"
COL_EVT_MOD     <- "modality"
COL_EVT_DATE    <- "event_date"

# Modality label constants (from surveillance_codeset.xlsx Modalities sheet)
LBL_CBC         <- "CBC"   # reference level (D-08)

# Phase 179 workbook: sheet "Model_Results", column "Analysis" (R/183 reader pattern)
LBL_P179_SHEET  <- "Model_Results"
LBL_P179_COL    <- "Analysis"
LBL_P179_OR     <- "OR"
LBL_P179_LO     <- "CI_lo"
LBL_P179_HI     <- "CI_hi"
LBL_P179_PRIMARY <- "Primary: years 2+"

# UF colours
UF_BLUE   <- "#0021A5"
UF_ORANGE <- "#FA4616"

# --- Helpers (copied verbatim from R/179 lines 81-94; do not edit) ---
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

# --- rate_or_dash: "—" unless both numerator and denominator are >= 11 (D-17) ---
rate_or_dash <- function(num, den) {
  if (is.na(num) || is.na(den) || num < 11 || den < 11) return("—")
  round(num / den, 4)
}

# --- need_cols: stop with available names if any column is missing ---
need_cols <- function(df, cols, what) {
  missing <- setdiff(cols, names(df))
  if (length(missing) > 0L)
    stop(glue("[R/184] {what}: missing columns {paste(missing, collapse = ', ')}. ",
              "Available: {paste(names(df), collapse = ', ')}"), call. = FALSE)
  invisible(df)
}

# --- run_gee: copied verbatim from R/179_cbc_patient_year.R lines 398-434; do not edit ---
# NOTE: uses global GEE_CORSTR; set GEE_CORSTR <- P179_CORSTR immediately before gate.
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

message(glue("  Constants: CUTOFF={CUTOFF} mi | P179_CORSTR={P179_CORSTR} | MODR_CORSTR={MODR_CORSTR}"))

# ==============================================================================
# SECTION 1: PINNED INPUTS (D-25) ----
# ==============================================================================

pin <- function(var, default) {
  v <- Sys.getenv(var, unset = ""); p <- if (nzchar(v)) v else default
  if (!file.exists(p)) stop(glue("[R/184] {var}: file not found: {p}"), call. = FALSE)
  list(var = var, path = p, pinned = nzchar(v))
}

# --- R/147 pointer (Phase 170 gate pattern; same as R/166 and R/179) -----------
ptr_path <- file.path(CONFIG$output_dir, "logs", "147_verify_last_pass.txt")
stopifnot("Phase 170 pointer 147_verify_last_pass.txt not found" = file.exists(ptr_path))
ptr_lines <- readLines(ptr_path, warn = FALSE)
ptr_get <- function(key) {
  hit <- grep(paste0("^", key, "\\s*="), ptr_lines, value = TRUE)
  if (length(hit) == 0L) return(NA_character_)
  trimws(sub("^[^=]*=", "", hit[1]))
}
r147_run_date <- ptr_get("run_date")
r147_rds <- ptr_get("rds_path")
if (is.na(r147_rds)) r147_rds <- ptr_get("rds")
if (is.na(r147_rds)) {
  stopifnot("Pointer has neither rds/rds_path nor run_date" = !is.na(r147_run_date))
  r147_rds <- file.path(CONFIG$cache$outputs_dir,
                        sprintf("surveillance_modality_patient_%s.rds", r147_run_date))
}
stopifnot("R/147 patient-modality RDS named by the pointer does not exist" = file.exists(r147_rds))
message(glue("  R/147 pointer: run_date={r147_run_date} | rds={basename(r147_rds)}"))

PINS <- list(
  p179_rds  = pin("R184_P179_RDS",  "output/internal/cbc_patient_year_20261015.rds"),
  p179_xlsx = pin("R184_P179_XLSX", "output/cbc_patient_year_20261015.xlsx"),
  events    = pin("R184_EVENTS_RDS",
                  file.path(CONFIG$cache$outputs_dir,
                            sprintf("survivorship_dated_events_%s.rds", r147_run_date)))
)
message("  PINS:")
for (nm in names(PINS)) {
  p <- PINS[[nm]]
  message(glue("    {p$var}: {p$path} (pinned={p$pinned})"))
}
message(glue("  R/147 pointer value (run_date key): {r147_run_date}"))

# need_cols checks will run at load time below

# ==============================================================================
# SECTION 2: GATE — reproduce Phase 179 (D-16) ----
# ==============================================================================

# 2a. Load Phase 179 RDS
py_raw <- readRDS(PINS$p179_rds$path)
py_raw <- py_raw |>
  dplyr::mutate(ID = as_id(.data[[COL_ID]]))
need_cols(py_raw,
          c(COL_ID, COL_YEAR_INDEX, COL_YEAR_START, COL_YEAR_END,
            COL_CBC_YEAR, COL_FAR, COL_EXP_MISSING),
          "Phase 179 RDS")

# 2b. year_index_cat — built exactly as R/179 (D-09); copied verbatim from R/179 line 333
py_raw <- py_raw |>
  dplyr::mutate(year_index_cat = factor(
    dplyr::if_else(year_index >= 5L, "5+", as.character(year_index)),
    levels = c("1", "2", "3", "4", "5+")))

# 2c. Complete-case on exposure (D-06)
py_cc <- py_raw |> dplyr::filter(!.data[[COL_EXP_MISSING]])

# 2d. person_years (D-05b): expected == 1 for every row (Phase 179 keeps fully observed years)
py_cc <- py_cc |>
  dplyr::mutate(person_years = as.numeric(year_end - year_start) / 365)
py_range <- range(py_cc$person_years, na.rm = TRUE)
message(glue("  person_years range: [{round(py_range[1], 4)}, {round(py_range[2], 4)}]"))
if (any(py_cc$person_years < 0.99 | py_cc$person_years > 1.01, na.rm = TRUE)) {
  bad <- py_cc |> dplyr::filter(person_years < 0.99 | person_years > 1.01)
  stop(glue("[R/184] person_years outside [0.99, 1.01] for {nrow(bad)} patient-years. ",
            "Phase 179 is expected to keep only fully observed years. Range: ",
            "[{round(py_range[1], 4)}, {round(py_range[2], 4)}]"), call. = FALSE)
}

# 2e. Exact-label reader (copied verbatim from R/183 lines 548-562)
read_p179_or <- function(path, label) {
  sheet_df <- tryCatch(
    openxlsx::read.xlsx(path, sheet = "Model_Results"),
    error = function(e) stop(glue("Cannot read Model_Results from {basename(path)}: {e$message}")))
  if (!"Analysis" %in% names(sheet_df))
    stop(glue("Model_Results in {basename(path)} missing 'Analysis' column. ",
              "Columns found: {paste(names(sheet_df), collapse=', ')}"))
  rows <- sheet_df[trimws(as.character(sheet_df$Analysis)) == label, ]
  if (nrow(rows) != 1L) {
    avail <- paste(head(trimws(as.character(sheet_df$Analysis)), 30), collapse = ", ")
    stop(glue("Expected 1 row with Analysis='{label}' in {basename(path)}; ",
              "found {nrow(rows)}. Available: {avail}"), call. = FALSE)
  }
  or    <- as.numeric(rows$OR)
  ci_lo <- as.numeric(rows$CI_lo)
  ci_hi <- as.numeric(rows$CI_hi)
  if (length(or) != 1L || is.na(or) ||
      length(ci_lo) != 1L || is.na(ci_lo) ||
      length(ci_hi) != 1L || is.na(ci_hi)) {
    stop(glue("read_p179_or: OR/CI_lo/CI_hi must each be a single non-NA numeric. ",
              "Got OR={deparse(or)}, CI_lo={deparse(ci_lo)}, CI_hi={deparse(ci_hi)}. ",
              "Sheet columns: {paste(names(sheet_df), collapse=', ')}"), call. = FALSE)
  }
  list(or = or, ci_lo = ci_lo, ci_hi = ci_hi)
}

P179_REF <- read_p179_or(PINS$p179_xlsx$path, LBL_P179_PRIMARY)
message(glue("  Phase 179 reference ({LBL_P179_PRIMARY}): ",
             "OR={round(P179_REF$or, 3)} ({round(P179_REF$ci_lo, 3)}-{round(P179_REF$ci_hi, 3)})"))

# 2f. Gate: refit Phase 179 model on pinned RDS (D-16)
GEE_CORSTR <- P179_CORSTR   # required by run_gee(); scoped to gate only
message(glue("  Running reproduction gate (GEE_CORSTR={GEE_CORSTR}) ..."))
g <- run_gee(dplyr::filter(py_cc, year_index >= 2L), COL_CBC_YEAR, COL_FAR,
             LBL_P179_PRIMARY)

if (anyNA(c(g$or, g$ci_lo, g$ci_hi, P179_REF$or, P179_REF$ci_lo, P179_REF$ci_hi)))
  stop(glue("REPRODUCTION GATE FAIL: NA in gate values — ",
            "g=({g$or},{g$ci_lo},{g$ci_hi}) P179=({P179_REF$or},{P179_REF$ci_lo},{P179_REF$ci_hi})"),
       call. = FALSE)

delta_or <- abs(g$or    - P179_REF$or)
delta_lo <- abs(g$ci_lo - P179_REF$ci_lo)
delta_hi <- abs(g$ci_hi - P179_REF$ci_hi)

if (delta_or > 0.005 || delta_lo > 0.005 || delta_hi > 0.005) {
  stop(glue("REPRODUCTION GATE FAIL: ",
            "R/184 OR={round(g$or, 4)} ({round(g$ci_lo, 4)}-{round(g$ci_hi, 4)}) vs ",
            "Phase 179 OR={round(P179_REF$or, 4)} ({round(P179_REF$ci_lo, 4)}-{round(P179_REF$ci_hi, 4)}); ",
            "|deltaOR|={round(delta_or, 4)} |deltaLo|={round(delta_lo, 4)} |deltaHi|={round(delta_hi, 4)}: ",
            "all must be <= 0.005"), call. = FALSE)
}

message(glue("REPRODUCTION GATE PASSED: OR {round(g$or, 4)} ({round(g$ci_lo, 4)}-{round(g$ci_hi, 4)}) ",
             "vs Phase 179 {round(P179_REF$or, 4)} ({round(P179_REF$ci_lo, 4)}-{round(P179_REF$ci_hi, 4)})"))

# 2g. Gate summary counts
py_gate <- dplyr::filter(py_cc, year_index >= 2L)
GATE <- list(
  n_py      = nrow(py_gate),
  n_pat     = dplyr::n_distinct(py_gate$ID),
  n_far1    = sum(py_gate[[COL_FAR]] == 1L, na.rm = TRUE),
  n_far0    = sum(py_gate[[COL_FAR]] == 0L, na.rm = TRUE)
)
message(glue("  GATE counts (years 2+): {GATE$n_py} patient-years, {GATE$n_pat} patients, ",
             "far=1: {sup(GATE$n_far1)}, far=0: {sup(GATE$n_far0)}"))

rm(GEE_CORSTR)   # do not reuse; MODR_CORSTR is used in Plan 02

# ==============================================================================
# SECTION 3: LONG PATIENT × MODALITY × YEAR FRAME (D-05, D-07, D-16a, D-16b) ----
# ==============================================================================

# 3a. Load modality events (R/166 survivorship_dated_events)
events_rds <- readRDS(PINS$events$path)
need_cols(events_rds, c(COL_EVT_ID, COL_EVT_MOD, COL_EVT_DATE), "R/166 events RDS")
events_rds <- events_rds |>
  dplyr::mutate(
    ID         = as_id(.data[[COL_EVT_ID]]),
    modality   = as.character(.data[[COL_EVT_MOD]]),
    event_date = as.Date(.data[[COL_EVT_DATE]])
  ) |>
  dplyr::distinct(ID, modality, event_date)

mod_labels <- sort(unique(events_rds$modality))
message(glue("  events_rds: {format(nrow(events_rds), big.mark = ',')} rows, ",
             "{dplyr::n_distinct(events_rds$ID)} patients, ",
             "{length(mod_labels)} modalities: {paste(mod_labels, collapse = ', ')}"))

# 3b. Eligibility frame (D-07): one row per ID × modality
#   Eligibility is patient-level: all Phase 179 complete-case patients are
#   eligible for modalities with no sex restriction. Sex-restricted modalities
#   (Mammogram, Breast MRI) require female sex from DEMOGRAPHIC.
#   For this plan, we use all-patient eligibility and note sex restrictions in QC.
#   Future: sex-restriction can be added via DuckDB DEMOGRAPHIC query.
cc_ids <- dplyr::distinct(py_cc, ID)
elig <- tidyr::expand_grid(
  ID       = cc_ids$ID,
  modality = mod_labels
)
message(glue("  elig (all-modality for complete-case patients): {format(nrow(elig), big.mark = ',')} rows"))
message("  NOTE: sex-restricted modalities (Mammogram, Breast MRI) not yet filtered;",
        " full restriction added in Plan 02 when DuckDB DEMOGRAPHIC is read.")

# 3c. Confirm CBC is eligible for every complete-case patient
cbc_elig_ids <- dplyr::filter(elig, modality == LBL_CBC)$ID
cc_patient_ids <- unique(py_cc$ID)
if (!all(cc_patient_ids %in% cbc_elig_ids)) {
  missing_n <- sum(!cc_patient_ids %in% cbc_elig_ids)
  stop(glue("[R/184] {missing_n} complete-case patients missing from CBC eligibility frame ",
            "(expected all {length(cc_patient_ids)})"), call. = FALSE)
}
message(glue("  CBC eligible for all {sup(length(cc_patient_ids))} complete-case patients: OK"))

# 3d. Long base: one row per ID × year × eligible modality
long_base <- py_cc |>
  dplyr::select(ID, year_index, year_start, year_end, far, person_years, year_index_cat) |>
  dplyr::inner_join(elig, by = "ID", relationship = "many-to-many")

stopifnot(
  "Duplicate (ID, modality, year_index) in long_base" =
    !anyDuplicated(long_base[, c("ID", "modality", "year_index")])
)
message(glue("  long_base: {format(nrow(long_base), big.mark = ',')} rows ",
             "(ID x year x modality)"))

# 3e. Count events per (ID, modality, year_index) using year_start < event_date <= year_end
event_counts <- long_base |>
  dplyr::select(ID, modality, year_index, year_start, year_end) |>
  dplyr::inner_join(
    dplyr::select(events_rds, ID, modality, event_date),
    by = dplyr::join_by(ID, modality, year_start < event_date, year_end >= event_date)
  ) |>
  dplyr::count(ID, modality, year_index, name = "count")

# 3f. Left join counts; NA -> 0L
long_df <- long_base |>
  dplyr::left_join(event_counts, by = c("ID", "modality", "year_index")) |>
  dplyr::mutate(count = dplyr::coalesce(count, 0L))

# 3g. modality as factor with CBC as reference (D-08)
long_df <- long_df |>
  dplyr::mutate(modality = factor(modality, levels = c(LBL_CBC, setdiff(mod_labels, LBL_CBC)))) |>
  droplevels()

stopifnot(
  "CBC must be the reference level of modality" =
    levels(long_df$modality)[1] == LBL_CBC
)

# 3h. D-16a/b checks: CBC rows must reproduce Phase 179 cbc_year
cbc <- dplyr::filter(long_df, modality == LBL_CBC)
stopifnot(
  "D-16b: CBC patient-years != complete-case patient-years" =
    nrow(cbc) == nrow(py_cc)
)
chk <- dplyr::inner_join(cbc,
                          dplyr::select(py_cc, ID, year_index, cbc_year = !!COL_CBC_YEAR),
                          by = c("ID", "year_index"))
agree <- table(count_pos = as.integer(chk$count > 0), cbc_year = chk$cbc_year)
message("  CBC agreement table (count_pos vs cbc_year):")
print(agree)

n_disagree <- sum(agree) - sum(diag(agree))
if (n_disagree > 0) {
  message("  Suppressed agreement table cells (1-10 shown as <11):")
  for (i in seq_len(nrow(agree))) {
    for (j in seq_len(ncol(agree))) {
      message(glue("    [{rownames(agree)[i]}, {colnames(agree)[j]}] = {sup(agree[i, j])}"))
    }
  }
  stop("CBC CHECK FAIL: R/184 CBC events do not reproduce Phase 179 cbc_year — ",
       "event definitions differ (see Task 0 item 5)", call. = FALSE)
}
message("  D-16a: CBC count_pos == cbc_year for all ", format(nrow(chk), big.mark = ","),
        " patient-years: OK")

# 3i. QC objects
QC_ELIG <- dplyr::bind_rows(
  long_df |>
    dplyr::group_by(modality) |>
    dplyr::summarise(
      period     = "all years",
      n_py       = dplyr::n(),
      n_patients = dplyr::n_distinct(ID),
      n_far1_py  = sum(far == 1L, na.rm = TRUE),
      n_far0_py  = sum(far == 0L, na.rm = TRUE),
      n_events   = sum(count),
      .groups    = "drop"
    ),
  long_df |>
    dplyr::filter(year_index >= 2L) |>
    dplyr::group_by(modality) |>
    dplyr::summarise(
      period     = "years 2+",
      n_py       = dplyr::n(),
      n_patients = dplyr::n_distinct(ID),
      n_far1_py  = sum(far == 1L, na.rm = TRUE),
      n_far0_py  = sum(far == 0L, na.rm = TRUE),
      n_events   = sum(count),
      .groups    = "drop"
    )
) |>
  dplyr::arrange(modality, period) |>
  dplyr::mutate(
    n_py_sup       = sup(n_py),
    n_patients_sup = sup(n_patients),
    n_events_sup   = sup(n_events)
  )

message("  QC_ELIG (eligible patients and events per modality):")
print(as.data.frame(dplyr::select(QC_ELIG, modality, period, n_py_sup, n_patients_sup, n_events_sup)))

# 3j. Save long frame
internal_dir <- file.path(CONFIG$output_dir, "internal")
dir.create(internal_dir, recursive = TRUE, showWarnings = FALSE)
long_out <- file.path(internal_dir, glue("modality_long_{RUN_DATE}.rds"))
saveRDS(long_df, long_out)
message(glue("  Saved: {long_out} ({format(nrow(long_df), big.mark = ',')} rows)"))

message("==== R/184 Plan 01 complete: stopped after long-frame checks ====")
