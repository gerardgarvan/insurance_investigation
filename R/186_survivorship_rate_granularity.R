# =============================================================================
# R/186_survivorship_rate_granularity.R
# Phase 186: Survivorship Rate Granularity
# =============================================================================
# Purpose: Reader + stacker. Pins the Phase 185 / R/184 output workbook, reads
# the annual (years 2+) and half-year/biannual (years 2+) rate blocks by exact
# section header, stacks them to one long team-facing table (one row per
# modality x far x window x half), applies a complementary suppression pass,
# and writes a dated xlsx with KEY (leftmost), Primary (years 2+), and
# Secondary (all-years) sheets.
#
# Source-of-truth citations (CLAUDE.md: schema probes win over guesses):
#   Default R184_OUTPUT from 185-01-SUMMARY.md Section 1:
#     output/modality_rate_model_20261022.xlsx
#   Section headers and rate unit confirmed against
#     .planning/schemas/185_schema_20261022.md (probed 2026-10-22)
#
# Run (HiPerGator interactive):
#   module load R/4.5
#   R --no-save
#   source("R/00_config.R")
#   source("R/186_survivorship_rate_granularity.R", local = new.env(parent = globalenv()))
#
# No new patient-year computation. R/184 is not modified (read-only).
# All values carried verbatim from the pinned workbook, including "<11".
# The complementary pass can only add suppression, never remove it.
# =============================================================================

message("==== R/186: Survivorship Rate Granularity ====")

# ==============================================================================
# SECTION 0: PINNED INPUT ----
# ==============================================================================

# R184_OUTPUT: path to the Phase 185 / R/184 dated output workbook.
# Default from 185-01-SUMMARY.md Section 1. Override with env var R184_OUTPUT.
R184_OUTPUT_DEFAULT <- "output/modality_rate_model_20261022.xlsx"

r184_output_path <- here::here(Sys.getenv("R184_OUTPUT", R184_OUTPUT_DEFAULT))
pinned_r184      <- nzchar(Sys.getenv("R184_OUTPUT"))   # TRUE if env override used

message(glue::glue(
  "[R/186] R184_OUTPUT: {r184_output_path}",
  " (pinned={pinned_r184}, override={if (pinned_r184) 'YES (env var)' else 'NO (default from 185-01-SUMMARY.md)'})"))

if (!file.exists(r184_output_path)) {
  stop(glue::glue(
    "[R/186] R184_OUTPUT not found: {r184_output_path}. ",
    "Set env var R184_OUTPUT to the dated R/184 workbook ",
    "(default from 185-01-SUMMARY.md: {R184_OUTPUT_DEFAULT})."),
    call. = FALSE)
}

# ==============================================================================
# SECTION 1: BLOCK READER + READ BLOCKS ----
# ==============================================================================

# ---- 1a. Section-header constants (from 185_schema_20261022.md + R/184 lines 1274-1304) ----
# Em dash written as "—" -- never as a literal character (Windows -> HiPerGator sync guard).
ANNUAL_HDR     <- paste0("Annual rates (years 2+) ", "\u2014", " by modality x far")
ANNUAL_ALL_HDR <- paste0("Annual rates (all years) ", "\u2014", " by modality x far")
YIC_HDR        <- "Annual rates by year_index_cat (years 2+)"   # terminator only, not read
HALF_HDR       <- "Half-year rates (years 2+)"
HALF_ALL_HDR   <- "Half-year rates (all years)"
ALL_RATES_HDRS <- c(ANNUAL_HDR, ANNUAL_ALL_HDR, YIC_HDR, HALF_HDR, HALF_ALL_HDR)

# ---- 1b. Block reader (adapted from R/184 lines 266-291 one-match-or-stop style) ----
# Reads the whole Rates sheet with colNames=FALSE because the first section header
# appears as the sheet's column-name row when colNames=TRUE. Later headers appear as
# values in col 1. We locate each block by trimmed col-1 exact match.
read_rates_block <- function(path, section_header) {
  raw <- openxlsx::read.xlsx(path, sheet = "Rates", colNames = FALSE)
  # col-1 as character, trimmed
  col1 <- trimws(as.character(raw[[1]]))
  # find rows matching the section header
  hdr_rows <- which(col1 == section_header)
  n <- length(hdr_rows)
  if (n != 1L) {
    avail <- paste(head(col1[!is.na(col1) & nzchar(col1)], 30), collapse = " | ")
    stop(glue::glue(
      "[R/186] Expected 1 section header '{section_header}' in Rates sheet; ",
      "found {n}. Available: {avail}"), call. = FALSE)
  }
  hdr_row <- hdr_rows[1L]
  # row immediately after the header = column-name row
  col_name_row <- hdr_row + 1L
  col_names    <- trimws(as.character(unlist(raw[col_name_row, ])))
  # data starts on the row after that
  data_start   <- hdr_row + 2L
  if (data_start > nrow(raw)) {
    stop(glue::glue("[R/186] Block '{section_header}': no data rows after column-name row."),
         call. = FALSE)
  }
  # Find the end of this block: next row where col-1 matches any RATES_HDR, or end of sheet
  remaining_col1 <- col1[data_start:nrow(raw)]
  term_idx <- which(remaining_col1 %in% ALL_RATES_HDRS)
  if (length(term_idx) > 0L) {
    data_end <- data_start + term_idx[1L] - 2L   # row before the next header
  } else {
    data_end <- nrow(raw)
  }
  # Subset data rows
  data_rows <- raw[data_start:data_end, , drop = FALSE]
  # Drop rows where col-1 is NA or blank (blank gap rows that survived read.xlsx)
  keep <- !is.na(data_rows[[1]]) & nzchar(trimws(as.character(data_rows[[1]])))
  data_rows <- data_rows[keep, , drop = FALSE]
  # Assign column names; drop trailing empty columns from xlsx
  names(data_rows) <- col_names
  keep_cols <- nzchar(col_names) & !is.na(col_names)
  data_rows  <- data_rows[, keep_cols, drop = FALSE]
  col_names  <- col_names[keep_cols]
  # Convert all columns to character -- carry suppressed "<11" verbatim, no coercion
  data_rows <- dplyr::mutate(data_rows,
                             dplyr::across(dplyr::everything(), as.character))
  tibble::as_tibble(data_rows)
}

# ---- 1c. Read Annual (years 2+) block ----
message("[R/186] Reading Annual (years 2+) block ...")
annual_raw <- read_rates_block(r184_output_path, ANNUAL_HDR)

# Validate expected column names (R/184 line 1276)
ANNUAL_EXPECTED_COLS <- c("period", "modality", "far", "n_patients_sup",
                          "patient_years_sup", "n_events_sup", "rate")
missing_annual <- setdiff(ANNUAL_EXPECTED_COLS, names(annual_raw))
if (length(missing_annual) > 0L) {
  stop(glue::glue(
    "[R/186] Annual block missing expected columns: {paste(missing_annual, collapse=', ')}. ",
    "Found: {paste(names(annual_raw), collapse=', ')}"), call. = FALSE)
}
message(glue::glue("[R/186] Annual block: {nrow(annual_raw)} rows, cols: {paste(names(annual_raw), collapse=', ')}"))

# ---- 1d. Read Half-year (years 2+) block ----
message("[R/186] Reading Half-year (years 2+) block ...")
half_raw <- read_rates_block(r184_output_path, HALF_HDR)

# Validate expected column names (R/184 line 1296, extra `half` column)
HALF_EXPECTED_COLS <- c("period", "modality", "far", "half", "n_patients_sup",
                        "patient_years_sup", "n_events_sup", "rate")
missing_half <- setdiff(HALF_EXPECTED_COLS, names(half_raw))
if (length(missing_half) > 0L) {
  stop(glue::glue(
    "[R/186] Half-year block missing expected columns: {paste(missing_half, collapse=', ')}. ",
    "Found: {paste(names(half_raw), collapse=', ')}"), call. = FALSE)
}
message(glue::glue("[R/186] Half-year block: {nrow(half_raw)} rows, cols: {paste(names(half_raw), collapse=', ')}"))

# ---- 1e. D-09 Rate unit guard ----
# Both blocks must use patient_years_sup as their denominator column (same unit, no rescale).
# If this fires, record the conversion formula in 186-CONTEXT.md before proceeding.
has_py_annual <- "patient_years_sup" %in% names(annual_raw)
has_py_half   <- "patient_years_sup" %in% names(half_raw)
if (!(has_py_annual && has_py_half)) {
  stop(glue::glue(
    "[R/186] D-09 HALT: expected 'patient_years_sup' denominator in both annual and ",
    "half-year blocks (same unit, no rescale). Annual cols: {paste(names(annual_raw), collapse=', ')}; ",
    "Half cols: {paste(names(half_raw), collapse=', ')}. If units differ, record the conversion ",
    "formula in 186-CONTEXT.md before writing output."), call. = FALSE)
}
rate_unit <- "per patient-year"
message(glue::glue("[R/186] D-09 guard: both blocks use patient_years_sup denominator. ",
                   "rate_unit = '{rate_unit}'. No rescaling applied."))

# ---- 1f. Read All-years blocks (for Secondary sheet, D-08) ----
message("[R/186] Reading Annual (all years) block ...")
annual_all_raw <- read_rates_block(r184_output_path, ANNUAL_ALL_HDR)
missing_annual_all <- setdiff(ANNUAL_EXPECTED_COLS, names(annual_all_raw))
if (length(missing_annual_all) > 0L) {
  stop(glue::glue(
    "[R/186] Annual all-years block missing expected columns: ",
    "{paste(missing_annual_all, collapse=', ')}. Found: {paste(names(annual_all_raw), collapse=', ')}"),
    call. = FALSE)
}
message(glue::glue("[R/186] Annual all-years block: {nrow(annual_all_raw)} rows"))

message("[R/186] Reading Half-year (all years) block ...")
half_all_raw <- read_rates_block(r184_output_path, HALF_ALL_HDR)
missing_half_all <- setdiff(HALF_EXPECTED_COLS, names(half_all_raw))
if (length(missing_half_all) > 0L) {
  stop(glue::glue(
    "[R/186] Half-year all-years block missing expected columns: ",
    "{paste(missing_half_all, collapse=', ')}. Found: {paste(names(half_all_raw), collapse=', ')}"),
    call. = FALSE)
}
message(glue::glue("[R/186] Half-year all-years block: {nrow(half_all_raw)} rows"))

# ==============================================================================
# SECTION 2: STACK + COMPLEMENTARY SUPPRESSION ----
# ==============================================================================

# dash marker: same as R/184 rate_or_dash() (R/184 line 116)
DASH <- "\u2014"

# ---- FIXTURES (run before real data; stopifnot) ----
# (a) Rule 2: annual "40", H1 "<11", H2 "33" -> H2 becomes "<11" (40-33=7 recoverable)
# (b) Rule 1: events "<11", patient_years "120.5", rate "0.05" -> rate becomes DASH
# (c) Rule 0: no suppression -> comes back identical
# (d) nested=FALSE: Rule 2 does NOT fire even when one cell is back-calculable

# Minimal helper call we'll test after the helper is defined. Declare fixtures now,
# run assertions after apply_complementary_suppression is defined below.

# ---- PERIOD handling ----
# For each block, if period has exactly one unique value, record it for KEY and drop the column.
# If more than one, keep period as a key column.
handle_period <- function(blk, label) {
  vals <- unique(trimws(blk$period))
  vals <- vals[!is.na(vals) & nzchar(vals)]
  if (length(vals) == 1L) {
    message(glue::glue("[R/186] {label}: period has one value '{vals}'. Recording for KEY; dropping from output."))
    list(df = dplyr::select(blk, -dplyr::any_of("period")), period_val = vals, keep_period = FALSE)
  } else {
    message(glue::glue("[R/186] {label}: period has {length(vals)} values ({paste(vals, collapse=', ')}). Keeping as key column."))
    list(df = blk, period_val = paste(vals, collapse = "; "), keep_period = TRUE)
  }
}

annual_period  <- handle_period(annual_raw,      "Annual yr2+")
half_period    <- handle_period(half_raw,         "Half-year yr2+")
ann_all_period <- handle_period(annual_all_raw,   "Annual all-years")
half_all_period<- handle_period(half_all_raw,     "Half-year all-years")

# Record period values for KEY
period_annual <- annual_period$period_val
period_half   <- half_period$period_val

# ---- Build PRIMARY long table (years 2+) ----
build_annual_long <- function(blk_info, rate_unit_val) {
  df <- blk_info$df
  base <- dplyr::transmute(df,
    modality,
    far,
    window = "annual",
    half   = NA_character_,
    patients      = n_patients_sup,
    patient_years = patient_years_sup,
    events        = n_events_sup,
    rate,
    rate_unit     = rate_unit_val
  )
  if (blk_info$keep_period) base <- dplyr::mutate(base, period = df$period, .before = 1)
  base
}

build_half_long <- function(blk_info, rate_unit_val) {
  df <- blk_info$df
  base <- dplyr::transmute(df,
    modality,
    far,
    window = "biannual",
    half   = as.character(half),
    patients      = n_patients_sup,
    patient_years = patient_years_sup,
    events        = n_events_sup,
    rate,
    rate_unit     = rate_unit_val
  )
  if (blk_info$keep_period) base <- dplyr::mutate(base, period = df$period, .before = 1)
  base
}

annual_long <- build_annual_long(annual_period, rate_unit)
half_long   <- build_half_long(half_period, rate_unit)
primary_tbl <- dplyr::bind_rows(annual_long, half_long)

# Assert unique key
key_cols <- c(
  if (annual_period$keep_period || half_period$keep_period) "period" else NULL,
  "modality", "far", "window", "half"
)
key_cols <- intersect(key_cols, names(primary_tbl))
stopifnot(
  "[R/186] primary_tbl key is not unique (modality x far x window x half)" =
    !anyDuplicated(primary_tbl[, key_cols])
)
message(glue::glue("[R/186] primary_tbl: {nrow(primary_tbl)} rows. Key unique: OK."))

# ---- Keep annual snapshot BEFORE complementary pass (for annual match check) ----
annual_snapshot <- annual_long

# ---- NESTING CHECK: annual == H1 + H2 for events and patient_years? ----
nesting_check <- function(primary_df) {
  # Work only where both annual and two halves are visible numbers
  num_re <- "^[0-9,.]+$"
  annual_rows <- dplyr::filter(primary_df, window == "annual")
  half_rows   <- dplyr::filter(primary_df, window == "biannual")

  # Summarise half by modality x far: need exactly 2 halves per group
  half_grp <- half_rows |>
    dplyr::group_by(modality, far) |>
    dplyr::summarise(
      n_halves   = dplyr::n(),
      ev_h1      = dplyr::first(events),
      ev_h2      = dplyr::last(events),
      py_h1      = dplyr::first(patient_years),
      py_h2      = dplyr::last(patient_years),
      .groups    = "drop"
    ) |>
    dplyr::filter(n_halves == 2L)

  combined <- dplyr::inner_join(
    annual_rows |> dplyr::select(modality, far, ann_ev = events, ann_py = patient_years),
    half_grp,
    by = c("modality", "far")
  )

  # Testable rows: all three cells visible numbers
  is_num <- function(x) grepl("^[0-9,]+$", gsub("\\.", "", x))
  testable <- combined |>
    dplyr::filter(
      is_num(ann_ev) & is_num(ev_h1) & is_num(ev_h2),
      is_num(ann_py) & is_num(py_h1) & is_num(py_h2)
    )

  if (nrow(testable) == 0L) {
    message("[R/186] Nesting check: no fully visible rows to test. Assuming nested=TRUE (conservative).")
    return(list(nested = TRUE, testable = 0L, matched = 0L, details = "no testable rows"))
  }

  parse_n <- function(x) as.numeric(gsub(",", "", x))
  testable <- testable |>
    dplyr::mutate(
      ann_ev_n = parse_n(ann_ev), ev_h1_n = parse_n(ev_h1), ev_h2_n = parse_n(ev_h2),
      ann_py_n = parse_n(ann_py), py_h1_n = parse_n(py_h1), py_h2_n = parse_n(py_h2),
      ev_match = abs(ann_ev_n - (ev_h1_n + ev_h2_n)) < 0.5,   # exact for integer events
      py_match = abs(ann_py_n - (py_h1_n + py_h2_n)) < 0.01   # tolerance for patient_years
    )

  n_testable <- nrow(testable)
  n_matched  <- sum(testable$ev_match & testable$py_match, na.rm = TRUE)
  nested     <- (n_matched == n_testable)

  message(glue::glue(
    "[R/186] Nesting check: {n_testable} testable rows; {n_matched} matched ",
    "(annual = H1+H2). nested={nested}"))
  if (!nested) {
    message("[R/186] NOTE: windows not additive -- cross-window Rule 2 suppression skipped.")
  }
  list(nested = nested, testable = n_testable, matched = n_matched)
}

nc_primary <- nesting_check(primary_tbl)
nested     <- nc_primary$nested

# ---- COMPLEMENTARY SUPPRESSION HELPER ----
# Rules 0-3; iterates until stable.
# dash = exact marker from R/184 rate_or_dash() (R/184 line 116)
apply_complementary_suppression <- function(df, nested, dash = DASH) {
  SUPPRESSED <- "<11"
  is_sup <- function(x) !is.na(x) & trimws(x) == SUPPRESSED
  is_vis_num <- function(x) {
    !is.na(x) & !is_sup(x) & trimws(x) != dash &
      grepl("^[0-9,\\.]+$", trimws(x))
  }

  changed <- list(rate = 0L, events = 0L, patient_years = 0L, patients = 0L)

  repeat {
    any_changed <- FALSE

    # Rule 1: rate leak (row level)
    # If events or patient_years is "<11" in any row, set rate to dash
    rule1_rows <- which((is_sup(df$events) | is_sup(df$patient_years)) &
                          !is.na(df$rate) & trimws(df$rate) != dash)
    if (length(rule1_rows) > 0L) {
      df$rate[rule1_rows] <- dash
      changed$rate <- changed$rate + length(rule1_rows)
      any_changed <- TRUE
    }

    # Rule 2: cross-window (only if nested == TRUE)
    # For events and patient_years: within each modality x far (x period if present),
    # group = {annual, H1, H2} with annual = H1 + H2.
    # If exactly one cell of the group is "<11", suppress the smallest visible half
    # (ties: prefer H2). If annual is suppressed, suppress the smaller half.
    if (nested) {
      period_col <- if ("period" %in% names(df)) "period" else NULL
      grp_vars   <- c(period_col, "modality", "far")

      for (col_nm in c("events", "patient_years")) {
        ann_rows  <- which(df$window == "annual")
        half_rows <- which(df$window == "biannual")

        ann_df  <- df[ann_rows, c(grp_vars, col_nm), drop = FALSE]
        half_df <- df[half_rows, c(grp_vars, "half", col_nm), drop = FALSE]

        # For each annual row, find matching halves
        for (i in seq_len(nrow(ann_df))) {
          ann_key <- as.list(ann_df[i, grp_vars, drop = FALSE])
          ann_val <- ann_df[[col_nm]][i]

          # Match half rows by grp_vars
          match_expr <- rep(TRUE, nrow(half_df))
          for (gv in grp_vars) {
            match_expr <- match_expr & (half_df[[gv]] == ann_key[[gv]])
          }
          h_idx <- which(match_expr)
          if (length(h_idx) != 2L) next   # need exactly two halves

          h1_global <- half_rows[h_idx[1]]
          h2_global <- half_rows[h_idx[2]]
          h1_val    <- df[[col_nm]][h1_global]
          h2_val    <- df[[col_nm]][h2_global]
          ann_global<- ann_rows[i]

          n_sup <- sum(is_sup(c(ann_val, h1_val, h2_val)))

          if (n_sup == 1L) {
            parse_n <- function(x) as.numeric(gsub(",", "", trimws(x)))

            if (is_sup(ann_val)) {
              # annual is the suppressed one: suppress the smaller visible half
              if (is_vis_num(h1_val) && is_vis_num(h2_val)) {
                if (parse_n(h1_val) <= parse_n(h2_val)) {
                  df[[col_nm]][h1_global] <- SUPPRESSED
                  changed[[col_nm]] <- changed[[col_nm]] + 1L
                  any_changed <- TRUE
                } else {
                  df[[col_nm]][h2_global] <- SUPPRESSED
                  changed[[col_nm]] <- changed[[col_nm]] + 1L
                  any_changed <- TRUE
                }
              }
            } else if (is_sup(h1_val) || is_sup(h2_val)) {
              # one half is suppressed: suppress the smaller visible half (the other half)
              # if h1 suppressed, suppress h2 only if it is visible and annual is visible
              # if h2 suppressed, suppress h1 only if it is visible and annual is visible
              if (is_sup(h1_val) && is_vis_num(h2_val) && is_vis_num(ann_val)) {
                # h2 must be suppressed (annual - h2 = h1, but h1 is already suppressed;
                # h2 alone is visible -> recovery if not suppressed)
                df[[col_nm]][h2_global] <- SUPPRESSED
                changed[[col_nm]] <- changed[[col_nm]] + 1L
                any_changed <- TRUE
              } else if (is_sup(h2_val) && is_vis_num(h1_val) && is_vis_num(ann_val)) {
                df[[col_nm]][h1_global] <- SUPPRESSED
                changed[[col_nm]] <- changed[[col_nm]] + 1L
                any_changed <- TRUE
              }
            }
          }
          # 0 or >= 2 suppressed: nothing to add
        }
      }
    }

    if (!any_changed) break
  }

  list(df = df, changed = changed)
}

# ---- FIXTURES (a)-(d): run before real data ----
{
  make_fixture_tbl <- function() {
    tibble::tibble(
      modality      = c("TestMod", "TestMod", "TestMod"),
      far           = c("far",     "far",     "far"),
      window        = c("annual",  "biannual","biannual"),
      half          = c(NA_character_, "1", "2"),
      patients      = c("50",  "25",  "28"),
      patient_years = c("120", "60",  "60"),
      events        = c("40",  "<11", "33"),
      rate          = c("0.33","0.05","0.55"),
      rate_unit     = rep("per patient-year", 3)
    )
  }

  # (a) Rule 2: H2 should become "<11" (annual "40" - H2 "33" = 7, recoverable)
  fix_a <- apply_complementary_suppression(make_fixture_tbl(), nested = TRUE, dash = DASH)
  stopifnot(
    "[R/186] Fixture (a) FAIL: H2 events should be suppressed" =
      fix_a$df$events[3] == "<11"
  )
  stopifnot(
    "[R/186] Fixture (a) FAIL: annual events should remain '40'" =
      fix_a$df$events[1] == "40"
  )
  message("[R/186] Fixture (a) PASS: H2 suppressed when back-calculable from annual and H1.")

  # (b) Rule 1: rate should become dash when events is "<11"
  fix_b_tbl <- tibble::tibble(
    modality      = "TestMod2",
    far           = "close",
    window        = "annual",
    half          = NA_character_,
    patients      = "50",
    patient_years = "120.5",
    events        = "<11",
    rate          = "0.05",
    rate_unit     = "per patient-year"
  )
  fix_b <- apply_complementary_suppression(fix_b_tbl, nested = FALSE, dash = DASH)
  stopifnot(
    "[R/186] Fixture (b) FAIL: rate should be DASH when events is suppressed" =
      fix_b$df$rate[1] == DASH
  )
  message("[R/186] Fixture (b) PASS: rate set to dash when events '<11'.")

  # (c) Rule 0: no suppression -> identical
  fix_c_tbl <- tibble::tibble(
    modality      = c("Mod3", "Mod3", "Mod3"),
    far           = c("far",  "far",  "far"),
    window        = c("annual","biannual","biannual"),
    half          = c(NA_character_, "1", "2"),
    patients      = c("55", "30", "30"),
    patient_years = c("100","50", "50"),
    events        = c("40", "20", "20"),
    rate          = c("0.4","0.4","0.4"),
    rate_unit     = rep("per patient-year", 3)
  )
  fix_c <- apply_complementary_suppression(fix_c_tbl, nested = TRUE, dash = DASH)
  stopifnot(
    "[R/186] Fixture (c) FAIL: no-suppression table should be identical after pass" =
      identical(fix_c$df, fix_c_tbl)
  )
  message("[R/186] Fixture (c) PASS: table unchanged when no suppression needed.")

  # (d) nested=FALSE: Rule 2 does NOT fire; H2 "33" stays "33"
  fix_d <- apply_complementary_suppression(make_fixture_tbl(), nested = FALSE, dash = DASH)
  stopifnot(
    "[R/186] Fixture (d) FAIL: with nested=FALSE, H2 events should remain '33'" =
      fix_d$df$events[3] == "33"
  )
  message("[R/186] Fixture (d) PASS: Rule 2 skipped when nested=FALSE.")

  message("[R/186] All four fixtures PASSED.")
}

# ---- Apply complementary suppression to PRIMARY ----
message("[R/186] Applying complementary suppression to primary_tbl ...")
cs_primary <- apply_complementary_suppression(primary_tbl, nested = nested, dash = DASH)
primary_tbl_final <- cs_primary$df
message(glue::glue("[R/186] Primary suppression pass cells changed: ",
                   "events={cs_primary$changed$events}, ",
                   "patient_years={cs_primary$changed$patient_years}, ",
                   "rate={cs_primary$changed$rate}"))

# ---- Annual match check (check in code: R/184 values carried verbatim) ----
message("[R/186] Annual match check: re-reading annual block from pinned workbook ...")
annual_reread <- read_rates_block(r184_output_path, ANNUAL_HDR)
# Re-read and rename to team-facing names for comparison
annual_reread_long <- dplyr::transmute(annual_reread,
  modality,
  far,
  patients      = n_patients_sup,
  patient_years = patient_years_sup,
  events        = n_events_sup,
  rate
)
# Get the annual rows from the final table
final_annual_rows <- dplyr::filter(primary_tbl_final, window == "annual")
check_cols <- c("patients", "patient_years", "events", "rate")
n_identical  <- 0L
n_added_sup  <- 0L
for (r in seq_len(nrow(annual_reread_long))) {
  mod_r <- annual_reread_long$modality[r]
  far_r <- annual_reread_long$far[r]
  out_r <- dplyr::filter(final_annual_rows, modality == mod_r, far == far_r)
  if (nrow(out_r) != 1L) next
  for (col in check_cols) {
    orig <- trimws(annual_reread_long[[col]][r])
    out_v <- trimws(out_r[[col]][1])
    if (identical(orig, out_v)) {
      n_identical <- n_identical + 1L
    } else if (out_v == "<11" || out_v == DASH) {
      # complementary pass added suppression -- allowed
      n_added_sup <- n_added_sup + 1L
    } else {
      stop(glue::glue(
        "[R/186] Annual match check FAIL: modality={mod_r}, far={far_r}, col={col}: ",
        "original='{orig}', output='{out_v}'. Output must equal original or be '<11'/DASH."),
        call. = FALSE)
    }
  }
}
message(glue::glue(
  "[R/186] annual cells match R/184: {n_identical} identical, {n_added_sup} added suppression"))
annual_match_note <- glue::glue("PASS: {n_identical} identical, {n_added_sup} added suppression")

# ---- Build SECONDARY table (all-years) ----
ann_all_long   <- build_annual_long(ann_all_period, rate_unit)
half_all_long  <- build_half_long(half_all_period, rate_unit)
secondary_pre  <- dplyr::bind_rows(ann_all_long, half_all_long)

key_cols_sec <- c(
  if (ann_all_period$keep_period || half_all_period$keep_period) "period" else NULL,
  "modality", "far", "window", "half"
)
key_cols_sec <- intersect(key_cols_sec, names(secondary_pre))
stopifnot(
  "[R/186] secondary_pre key is not unique" =
    !anyDuplicated(secondary_pre[, key_cols_sec])
)

nc_secondary <- nesting_check(secondary_pre)
nested_all   <- nc_secondary$nested
message(glue::glue("[R/186] secondary_pre: {nrow(secondary_pre)} rows. nested_all={nested_all}"))

message("[R/186] Applying complementary suppression to secondary_tbl ...")
cs_secondary  <- apply_complementary_suppression(secondary_pre, nested = nested_all, dash = DASH)
secondary_tbl <- cs_secondary$df
message(glue::glue("[R/186] Secondary suppression pass cells changed: ",
                   "events={cs_secondary$changed$events}, ",
                   "patient_years={cs_secondary$changed$patient_years}, ",
                   "rate={cs_secondary$changed$rate}"))

# ==============================================================================
# SECTION 3: WRITE OUTPUT WORKBOOK ----
# ==============================================================================

UF_BLUE   <- "#0021A5"
UF_ORANGE <- "#FA4616"

# Helper bodies copied verbatim from R/184 lines 1203-1215 (cite: R/184_modality_rate_model.R:1203)
add_section_header <- function(wb, sheet, row, text) {
  openxlsx::writeData(wb, sheet, data.frame(V1 = text), startRow = row,
                      startCol = 1, colNames = FALSE)
  openxlsx::addStyle(wb, sheet,
                     style = openxlsx::createStyle(fgFill = UF_ORANGE, fontColour = "white",
                                                   textDecoration = "bold"),
                     rows = row, cols = 1, gridExpand = TRUE)
}

style_header_row <- function(wb, sheet, row, ncols) {
  openxlsx::addStyle(wb, sheet,
                     style = openxlsx::createStyle(fgFill = UF_BLUE, fontColour = "white",
                                                   textDecoration = "bold", halign = "center"),
                     rows = row, cols = seq_len(ncols), gridExpand = TRUE)
}

wb <- openxlsx::createWorkbook()

# ---- KEY sheet (leftmost) ----
openxlsx::addWorksheet(wb, "KEY")
key_data <- data.frame(
  Parameter = c(
    "run_date",
    "host",
    "R184_OUTPUT (pin)",
    "R184_OUTPUT pinned",
    "biannual definition",
    "rate unit",
    "rate unit note",
    "suppression note",
    "period (annual block)",
    "period (half-year block)",
    "windows additive - primary (nested)",
    "windows additive - secondary (nested_all)",
    "nesting check - primary testable rows",
    "nesting check - primary matched rows",
    "nesting check - secondary testable rows",
    "nesting check - secondary matched rows",
    "cells changed by complementary pass - primary events",
    "cells changed by complementary pass - primary patient_years",
    "cells changed by complementary pass - primary rate",
    "cells changed by complementary pass - secondary events",
    "cells changed by complementary pass - secondary patient_years",
    "cells changed by complementary pass - secondary rate",
    "annual match check",
    "source"
  ),
  Value = c(
    format(Sys.Date()),
    Sys.info()[["nodename"]],
    r184_output_path,
    as.character(pinned_r184),
    "every 6 months (twice yearly); D-186-01 (provisional, pending team confirmation)",
    rate_unit,
    paste0("Annual and half-year blocks both use patient_years_sup as denominator; ",
           "same unit; no rescaling applied (D-09)."),
    paste0("Suppressed cells ('<11') carried verbatim from R/184. A complementary pass adds suppression only: ",
           "rate shown as a dash where events or patient-years is suppressed; across windows, where annual = H1 + H2, ",
           "a second half-year cell is suppressed when one cell would otherwise be recoverable. ",
           "No un-suppression or recomputation (D-06)."),
    period_annual,
    period_half,
    as.character(nested),
    as.character(nested_all),
    as.character(nc_primary$testable),
    as.character(nc_primary$matched),
    as.character(nc_secondary$testable),
    as.character(nc_secondary$matched),
    as.character(cs_primary$changed$events),
    as.character(cs_primary$changed$patient_years),
    as.character(cs_primary$changed$rate),
    as.character(cs_secondary$changed$events),
    as.character(cs_secondary$changed$patient_years),
    as.character(cs_secondary$changed$rate),
    annual_match_note,
    "Values read by exact section header from the pinned R/184 Rates sheet; no recomputation."
  ),
  stringsAsFactors = FALSE
)
openxlsx::writeData(wb, "KEY", key_data, startRow = 1)
style_header_row(wb, "KEY", 1, 2)

# ---- Primary sheet (years 2+) ----
openxlsx::addWorksheet(wb, "Primary")
cur_row <- 1L
add_section_header(wb, "Primary", cur_row,
  "Survivorship rates (years 2+) - annual and biannual, per modality x far x window x half")
cur_row <- cur_row + 1L
openxlsx::writeData(wb, "Primary", primary_tbl_final, startRow = cur_row)
style_header_row(wb, "Primary", cur_row, ncol(primary_tbl_final))

# ---- Secondary sheet (all years) ----
openxlsx::addWorksheet(wb, "Secondary")
cur_row_s <- 1L
add_section_header(wb, "Secondary", cur_row_s,
  "All-years rates (annual and biannual) - sensitivity, per modality x far x window x half")
cur_row_s <- cur_row_s + 1L
openxlsx::writeData(wb, "Secondary", secondary_tbl, startRow = cur_row_s)
style_header_row(wb, "Secondary", cur_row_s, ncol(secondary_tbl))

# ---- Save workbook ----
out_path <- here::here(glue::glue("output/survivorship_rate_granularity_{format(Sys.Date(), '%Y%m%d')}.xlsx"))
openxlsx::saveWorkbook(wb, out_path, overwrite = TRUE)
message(glue::glue("[R/186] wrote {out_path}"))

# Pin R186_OUTPUT for downstream Phase 188
message(glue::glue(
  "[R/186] PIN for Phase 188: set env var R186_OUTPUT='{out_path}' ",
  "to read this workbook. Default path (no env override): {basename(out_path)}"))

message("==== R/186: COMPLETE ====")
