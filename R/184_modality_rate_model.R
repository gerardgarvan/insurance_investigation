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
LBL_CBC         <- "CBC (Phase 165 definition)"  # reference level (D-08); replaces R/166 "Complete blood count" (see Section 3a)

# Phase 179 workbook: sheet "Model_Results", column "Analysis" (R/183 reader pattern)
LBL_P179_SHEET  <- "Model_Results"
LBL_P179_COL    <- "Analysis"
LBL_P179_OR     <- "OR"
LBL_P179_LO     <- "CI_low"
LBL_P179_HI     <- "CI_high"
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

# --- duck_query: open connection, query, close via close_pcornet_con() (removes globalenv ref) ---
# open_pcornet_con() is a SINGLE shared connection; a new call closes any existing pcornet_con
# (see utils_duckdb.R line 128). DBI::dbDisconnect() alone leaves a stale pcornet_con object in
# globalenv, causing the next block's !exists() guard to silently skip reopening. Must use
# close_pcornet_con() so pcornet_con is removed from globalenv after the query.
duck_query <- function(sql) {
  open_pcornet_con()
  on.exit(try(close_pcornet_con(), silent = TRUE), add = TRUE)
  DBI::dbGetQuery(pcornet_con, sql)
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

# EVENTS_COVERAGE_END: R/147/R/166 event collection ends at EXTRACT_CUTOFF (R/00_config.R line 85,
# R/147 line 53). Used in D-29 to restrict the model sample to patient-years fully within coverage.
EVENTS_COVERAGE_END <- as.Date(EXTRACT_DATE)   # "2025-09-15"; R/00_config.R line 85

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
  ci_lo <- as.numeric(rows$CI_low)
  ci_hi <- as.numeric(rows$CI_high)
  if (length(or) != 1L || is.na(or) ||
      length(ci_lo) != 1L || is.na(ci_lo) ||
      length(ci_hi) != 1L || is.na(ci_hi)) {
    stop(glue("read_p179_or: OR/CI_low/CI_high must each be a single non-NA numeric. ",
              "Got OR={deparse(or)}, CI_low={deparse(ci_lo)}, CI_high={deparse(ci_hi)}. ",
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
  n_py       = nrow(py_gate),
  n_pat      = dplyr::n_distinct(py_gate$ID),
  n_pat_far1 = dplyr::n_distinct(py_gate$ID[py_gate[[COL_FAR]] == 1L]),
  n_pat_far0 = dplyr::n_distinct(py_gate$ID[py_gate[[COL_FAR]] == 0L]),
  n_py_far1  = sum(py_gate[[COL_FAR]] == 1L, na.rm = TRUE),
  n_py_far0  = sum(py_gate[[COL_FAR]] == 0L, na.rm = TRUE)
)
message(glue("  GATE counts (years 2+, complete-case):"))
message(glue("    patient-years total : {format(GATE$n_py,  big.mark=',')}"))
message(glue("    patient-years far=1 : {format(GATE$n_py_far1, big.mark=',')}"))
message(glue("    patient-years far=0 : {format(GATE$n_py_far0, big.mark=',')}"))
message(glue("    patients      total : {format(GATE$n_pat, big.mark=',')}"))
message(glue("    patients      far=1 : {sup(GATE$n_pat_far1)}"))
message(glue("    patients      far=0 : {sup(GATE$n_pat_far0)}"))

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

LBL_R166_CBC <- "Complete blood count"  # R/166 label — excluded below; NOT used in the model

mod_labels_r166 <- sort(unique(events_rds$modality))
message(glue("  events_rds (R/166): {format(nrow(events_rds), big.mark = ',')} rows, ",
             "{dplyr::n_distinct(events_rds$ID)} patients, ",
             "{length(mod_labels_r166)} modalities: {paste(mod_labels_r166, collapse = ', ')}"))
if (!LBL_R166_CBC %in% mod_labels_r166)
  stop(glue("[R/184] R/166 events missing '{LBL_R166_CBC}'. ",
            "Found: {paste(mod_labels_r166, collapse = ', ')}"), call. = FALSE)

# Drop R/166 "Complete blood count" — its definition differs from Phase 165/179 CBC.
# Diagnostic (2026-10-16): 5,919 patient-years had Phase 179 cbc_year=1 but no R/166 CBC event;
# 3,959 belonged to patients with NO R/166 CBC events at all; median gap to nearest R/166 CBC
# event was 539 days — not a window-alignment issue. R/147 "Complete blood count" is a different
# measure from Phase 165/179 (WBC 6690-2 + Hgb 718-7 + PLT 777-3 same date).
events_rds <- dplyr::filter(events_rds, modality != LBL_R166_CBC)
message(glue("  Dropped R/166 '{LBL_R166_CBC}' rows. Remaining: ",
             "{format(nrow(events_rds), big.mark=',')}"))

# Phase 165 CBC events will be built below in section 3b after cc_patient_ids is defined.

# 3b. Eligibility frame (D-07): one row per ID × modality
#
#   Source check: R/147 saves surveillance_modality_patient_<date>.rds (build_patient_modality,
#   R/utils/utils_surveillance.R line 610) — one row per ID × modality for patients who HAD
#   events; it is an events summary, not a denominator eligibility frame. R/166 saves
#   survivorship_dated_events_<date>.rds and survivorship_modality_rates_parts_<date>.rds —
#   also events-based, not eligible-population frames. No prebuilt eligibility RDS exists;
#   derivation follows.
#
#   Rules (sources cited):
#   - All complete-case patients: eligible for every modality without sex restriction.
#     Source: R/147 line 83 (modality_eligible_sex returns "" for unrestricted modalities),
#             data/reference/README.md line 285.
#   - Mammogram, Breast MRI: eligible only for patients with DEMOGRAPHIC.SEX = "F".
#     Source: data/reference/README.md line 285; R/147 line 83 (eligible_sex = "F" on these).
#   - Echocardiogram, MUGA, Pulmonary function test, Stress test: NO eligibility restriction.
#     R/166/R/147 applies none; modality_eligible_sex() returns "" for these (R/utils/utils_surveillance.R
#     line 256; eligible_sex column blank in Modalities sheet per data/reference/README.md line 285).
#     echo_post_anthracycline (R/utils/utils_anthracycline_echo.R line 304) is a separate R/166
#     Plan 03 output and does not appear in survivorship_dated_events.
#
SEX_RESTRICTED <- c("Mammogram", "Breast MRI")   # data/reference/README.md line 285

# Sex lookup: full-table query inside the DuckDB block below, join in R (avoids IN-list and PATID).
cc_patient_ids <- unique(py_cc$ID)

# One DuckDB block: CBC events + DEMOGRAPHIC sex lookup.
# open_pcornet_con() is a SINGLE shared connection — any call to open_pcornet_con() (including
# inside duck_query) closes the previous connection. All DuckDB queries must happen between ONE
# open and ONE close_pcornet_con() call; no duck_query or other open_pcornet_con() call may
# occur between open and close.
# Pattern copied verbatim from R/179_cbc_patient_year.R lines 186-232 (open / query / close).
message("  DuckDB block: Phase 165 CBC events + DEMOGRAPHIC sex lookup ...")
db184_opened <- FALSE
if (!exists("pcornet_con", envir = .GlobalEnv) ||
    !DBI::dbIsValid(get("pcornet_con", envir = .GlobalEnv))) { open_pcornet_con(); db184_opened <- TRUE }

# Phase 165 CBC events (build_cbc_events; R/utils/utils_distance_cbc.R line 108)
# Verbatim from R/179 lines 191-194: transmute, filter NA, distinct; all collected in-block.
cbc165_events <- build_cbc_events(pcornet_con, cc_patient_ids) |>   # R/utils/utils_distance_cbc.R line 108
  dplyr::transmute(ID = as_id(ID), cbc_date = as.Date(cbc_date)) |>
  dplyr::filter(!is.na(cbc_date)) |>
  dplyr::distinct() |>
  dplyr::transmute(ID, modality = LBL_CBC, event_date = cbc_date)
message(glue("  Phase 165 CBC events: {format(nrow(cbc165_events), big.mark=',')} ",
             "patient-dates, {dplyr::n_distinct(cbc165_events$ID)} patients"))

# DEMOGRAPHIC sex lookup — full-table query, join in R (no IN-list, no PATID; CLAUDE.md rule).
demo_raw_184 <- DBI::dbGetQuery(pcornet_con, "SELECT ID, BIRTH_DATE, SEX FROM DEMOGRAPHIC")

if (db184_opened) close_pcornet_con()   # close BEFORE any further code; no lazy tbl() survives

demo_raw_184$ID <- as_id(demo_raw_184$ID)

events_rds <- dplyr::bind_rows(events_rds, cbc165_events) |>
  dplyr::distinct(ID, modality, event_date)

# Print max event_date per modality (D-29 QC)
max_evt_by_mod <- events_rds |>
  dplyr::group_by(modality) |>
  dplyr::summarise(max_event_date = max(event_date, na.rm = TRUE), .groups = "drop") |>
  dplyr::arrange(modality)
message(glue("  EVENTS_COVERAGE_END (D-29): {EVENTS_COVERAGE_END} (EXTRACT_DATE, R/00_config.R line 85)"))
message("  Max event_date per modality:")
print(as.data.frame(max_evt_by_mod))

mod_labels <- sort(unique(events_rds$modality))
if (!LBL_CBC %in% mod_labels)
  stop(glue("[R/184] LBL_CBC='{LBL_CBC}' not found after replacing CBC events. ",
            "Found: {paste(mod_labels, collapse = ', ')}"), call. = FALSE)

# Join to complete-case cohort BEFORE making sex a factor (prevents empty-level errors).
# Merge categories with < 11 cohort patients into "Other/Unknown"; droplevels().
# Copied from R/183 lines 421-444.
sex_184 <- demo_raw_184 |>
  dplyr::filter(ID %in% cc_patient_ids) |>
  dplyr::select(ID, sex_raw = SEX)
sex_counts_184 <- table(sex_184$sex_raw, useNA = "no")
rare_sex_184 <- names(sex_counts_184)[sex_counts_184 < 11L]
if (length(rare_sex_184) > 0L)
  sex_184 <- sex_184 |>
    dplyr::mutate(sex_raw = dplyr::if_else(sex_raw %in% rare_sex_184, "Other/Unknown", sex_raw))
sex_184 <- sex_184 |> dplyr::mutate(sex = droplevels(factor(sex_raw)))
female_ids <- sex_184$ID[sex_184$sex_raw %in% "F"]
message(glue("  sex_lookup: {nrow(sex_184)} of {length(cc_patient_ids)} ",
             "complete-case patients in DEMOGRAPHIC; female (SEX='F'): {length(female_ids)}"))

# Build eligibility: all patients × unrestricted modalities + female × sex-restricted
cc_ids    <- dplyr::distinct(py_cc, ID)
unrestricted <- setdiff(mod_labels, SEX_RESTRICTED)
elig_unrest  <- tidyr::expand_grid(ID = cc_ids$ID,  modality = unrestricted)
elig_sexrest <- tidyr::expand_grid(ID = female_ids, modality = intersect(SEX_RESTRICTED, mod_labels))
elig <- dplyr::bind_rows(elig_unrest, elig_sexrest)
message(glue("  elig: {format(nrow(elig), big.mark = ',')} rows ",
             "(unrestricted: {format(nrow(elig_unrest), big.mark=',')}, ",
             "sex-restricted to females: {format(nrow(elig_sexrest), big.mark=',')})"))

# Eligible-N per modality — internal consistency check.
# R/166 survivorship_modality_rates_long has rows only for patients with a recorded event
# (Mammogram 1,223, MUGA 497, echo_post_anthracycline 2,387, ...) — it is not a denominator
# eligibility frame, so R/184 eligible N cannot be compared against it. No R184_R166_XLSX pin.
# Primary eligibility: sex restriction only (D-07); anthracycline echo/MUGA sensitivity is Plan 02.
n_cc     <- length(cc_patient_ids)
n_female <- length(female_ids)
elig_n_by_mod <- elig |>
  dplyr::count(modality, name = "n_eligible") |>
  dplyr::mutate(
    expected = dplyr::if_else(modality %in% SEX_RESTRICTED, n_female, n_cc),
    ok       = (n_eligible == expected)) |>
  dplyr::arrange(modality)
bad_elig <- dplyr::filter(elig_n_by_mod, !ok)
if (nrow(bad_elig) > 0L)
  stop(glue("[R/184] Eligibility mismatch for {nrow(bad_elig)} modality(ies):\n",
            paste(sprintf("  %s: got %d, expected %d",
                          bad_elig$modality, bad_elig$n_eligible, bad_elig$expected),
                  collapse = "\n")), call. = FALSE)
message("  Eligible patients per modality:")
print(as.data.frame(dplyr::select(elig_n_by_mod, modality, n_eligible, expected)))

# 3c. Confirm CBC is eligible for every complete-case patient (CBC is unrestricted)
cbc_elig_ids <- dplyr::filter(elig, modality == LBL_CBC)$ID
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

# 3f-ii. D-29 coverage-end diagnostic: print max event_date boundary and coverage constant.
# The actual D-29 filter on long_df is applied in section 3h-ii, AFTER the CBC CHECK,
# so D-16a/b use the full Phase 179 years as required.

# 3f-iii. Event-count construction check (hard stop).
# For each modality, events in long_df must equal an independent recount from events_rds:
# events for eligible cohort patients whose event_date falls in a patient-year window
# (year_start < event_date <= year_end). Both counts printed with sup().
py_windows <- py_cc |> dplyr::select(ID, year_start, year_end)
recount_events <- elig |>
  dplyr::inner_join(events_rds, by = c("ID", "modality")) |>
  dplyr::inner_join(py_windows, by = "ID") |>
  dplyr::filter(event_date > year_start, event_date <= year_end) |>
  dplyr::count(modality, name = "recount")
longdf_counts <- long_df |>
  dplyr::group_by(modality) |>
  dplyr::summarise(longdf_n = sum(count), .groups = "drop")
count_check <- longdf_counts |>
  dplyr::left_join(recount_events, by = "modality") |>
  dplyr::mutate(recount = dplyr::coalesce(recount, 0L), match = (longdf_n == recount))
message("  Event-count construction check (long_df vs independent recount):")
print(as.data.frame(dplyr::mutate(count_check,
  longdf_sup  = sup(longdf_n),
  recount_sup = sup(recount))))
bad_counts <- dplyr::filter(count_check, !match)
if (nrow(bad_counts) > 0L)
  stop(glue("[R/184] Event-count mismatch for {nrow(bad_counts)} modality(ies):\n",
            paste(sprintf("  %s: long_df=%s recount=%s",
                          bad_counts$modality, sup(bad_counts$longdf_n), sup(bad_counts$recount)),
                  collapse = "\n")), call. = FALSE)
message("  Event-count construction check: OK for all ", length(mod_labels), " modalities")

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

# 3h-ii. D-29: restrict long_df to patient-years within events coverage.
# Applied AFTER CBC CHECK so D-16a/b use the full Phase 179 years.
# For modality rates and the model, keep only year_end <= EVENTS_COVERAGE_END so all
# modalities are compared over the same observation window.
long_df_pre_d29_n   <- nrow(long_df)
long_df_pre_d29_pat <- dplyr::n_distinct(long_df$ID)
long_df <- dplyr::filter(long_df, year_end <= EVENTS_COVERAGE_END)
removed_py  <- long_df_pre_d29_n   - nrow(long_df)
removed_pat <- long_df_pre_d29_pat - dplyr::n_distinct(long_df$ID)
message(glue("  D-29 coverage filter (year_end <= {EVENTS_COVERAGE_END}): ",
             "kept {format(nrow(long_df), big.mark=',')} patient-years, ",
             "{format(dplyr::n_distinct(long_df$ID), big.mark=',')} patients; ",
             "removed {sup(removed_py)} patient-years, {sup(removed_pat)} patients"))

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
