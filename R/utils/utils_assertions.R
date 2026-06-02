# ==============================================================================
# utils/utils_assertions.R -- Defensive coding assertion helpers
# ==============================================================================
#
# Purpose:
#   Provides 5 helper functions for defensive input validation using checkmate.
#   Reduces boilerplate in production scripts (decades 00-69) by wrapping checkmate
#   assertions with glue()-based error messages following the [R/XX ACTION] format.
#   All functions fail-fast with informative context (script name, file paths,
#   expected vs actual values, fix hints).
#
# Inputs:
#   - None (utility function library, not a standalone script)
#
# Outputs:
#   - None (defines functions loaded into calling scripts' environment)
#     - assert_rds_exists(): File existence check with context
#     - assert_df_valid(): Data frame structure + column presence check
#     - assert_col_types(): Key identifier type validation
#     - warn_date_range(): Date value range warnings
#     - warn_row_count(): Row count sanity check warnings
#
# Dependencies:
#   - checkmate: Fast argument validation (loaded in R/00_config.R)
#   - glue: String interpolation for error messages (loaded in R/00_config.R)
#   - dplyr: Data frame filtering for date range checks
#
# Requirements:
#   - SAFE-01: Input file existence validation
#   - SAFE-02: Data structure validation after critical loads and joins
#   - SAFE-03: Error messages include context using glue()
#
# ==============================================================================

#' Check that an RDS file exists and is readable
#'
#' Validates file existence with read access before attempting to load RDS cache.
#' Fails with informative error message including file path and fix hint.
#'
#' @param path Character. Full path to RDS file
#' @param script_name Character. Calling script identifier (e.g., "R/26")
#' @return Invisible path (assertion passes) or stops with error
#'
#' @examples
#' assert_rds_exists(
#'   file.path(CONFIG$cache$outputs_dir, "treatment_durations.rds"),
#'   script_name = "R/26"
#' )
assert_rds_exists <- function(path, script_name) {
  checkmate::assert_file_exists(
    path,
    access = "r",
    .var.name = glue::glue("[{script_name} ERROR] Expected RDS file")
  )

  invisible(path)
}

#' Validate data frame structure and required columns
#'
#' Checks that object is a data frame, has at least one row (unless allow_empty),
#' and contains all required columns. Two-stage validation: structure first,
#' then column presence.
#'
#' @param df Data frame. Object to validate
#' @param name Character. Descriptive name for error messages (e.g., "ENROLLMENT")
#' @param required_cols Character vector. Column names that must be present
#' @param script_name Character. Calling script identifier (e.g., "R/14")
#' @param allow_empty Logical. Allow zero-row data frames? Default FALSE
#' @return Invisible df (assertion passes) or stops with error
#'
#' @examples
#' assert_df_valid(
#'   enrollment,
#'   name = "ENROLLMENT",
#'   required_cols = c("ID", "ENR_START_DATE", "ENR_END_DATE"),
#'   script_name = "R/14"
#' )
assert_df_valid <- function(df, name, required_cols, script_name, allow_empty = FALSE) {
  # Check 1: Is it a data frame with rows?
  checkmate::assert_data_frame(
    df,
    min.rows = if (allow_empty) 0 else 1,
    .var.name = glue::glue("[{script_name} ERROR] {name}")
  )

  # Check 2: Does it have required columns?
  checkmate::assert_names(
    colnames(df),
    must.include = required_cols,
    .var.name = glue::glue("[{script_name} ERROR] {name} columns")
  )

  invisible(df)
}

#' Validate key column types (IDs, dates, numeric counts)
#'
#' Checks that critical columns have correct types to prevent silent bugs.
#' Only validates key identifiers (PATID, ENCOUNTERID, date columns, counts),
#' not all columns. Stops with informative error including expected vs actual
#' type and fix hint.
#'
#' @param df Data frame. Object to validate
#' @param type_spec Named list. Expected types (e.g., list(ID = "character", date = "Date"))
#' @param script_name Character. Calling script identifier (e.g., "R/26")
#' @return Invisible df (assertion passes) or stops with error
#'
#' @examples
#' assert_col_types(
#'   treatment_durations,
#'   type_spec = list(
#'     ID = "character",
#'     first_date = "Date",
#'     episode_count = "integer"
#'   ),
#'   script_name = "R/26"
#' )
assert_col_types <- function(df, type_spec, script_name) {
  for (col_name in names(type_spec)) {
    expected_class <- type_spec[[col_name]]

    if (!col_name %in% colnames(df)) {
      stop(glue::glue("[{script_name} ERROR] Column '{col_name}' not found in data frame"))
    }

    actual_class <- class(df[[col_name]])[1]

    # Date class check
    if (expected_class == "Date" && !inherits(df[[col_name]], "Date")) {
      stop(glue::glue(
        "[{script_name} ERROR] Column '{col_name}' must be Date class, got {actual_class} -- ",
        "use parse_pcornet_date() or as.Date()"
      ))
    }

    # Character class check (for IDs)
    if (expected_class == "character" && !is.character(df[[col_name]])) {
      stop(glue::glue(
        "[{script_name} ERROR] Column '{col_name}' must be character, got {actual_class} -- ",
        "IDs should be col_character() in vroom specs"
      ))
    }

    # Numeric class check (integer/numeric both accepted as numeric)
    if (expected_class %in% c("integer", "numeric") && !is.numeric(df[[col_name]])) {
      stop(glue::glue(
        "[{script_name} ERROR] Column '{col_name}' must be numeric, got {actual_class}"
      ))
    }
  }

  invisible(df)
}

#' Warn when date values fall outside plausible range
#'
#' Checks date column values against boundaries (default 1990-2030). Emits
#' warning (not error) for out-of-range dates. Pre-2012 dates are legitimate
#' in tumor registry data. Handles NA values gracefully.
#'
#' @param df Data frame. Object to validate
#' @param col Character. Date column name to check
#' @param lo Date. Lower bound (inclusive)
#' @param hi Date. Upper bound (inclusive)
#' @param script_name Character. Calling script identifier (e.g., "R/26")
#' @return Invisible df (always returns, warning may be emitted)
#'
#' @examples
#' warn_date_range(
#'   treatment_episodes,
#'   col = "episode_start",
#'   lo = as.Date("1990-01-01"),
#'   hi = as.Date("2030-12-31"),
#'   script_name = "R/26"
#' )
warn_date_range <- function(df, col, lo, hi, script_name) {
  if (!col %in% colnames(df)) {
    warning(glue::glue("[{script_name} WARNING] Column '{col}' not found for date range check"))
    return(invisible(df))
  }

  if (!inherits(df[[col]], "Date")) {
    warning(glue::glue("[{script_name} WARNING] Column '{col}' not Date class, skipping range check"))
    return(invisible(df))
  }

  out_of_range <- df %>%
    dplyr::filter(!is.na(.data[[col]]) & (.data[[col]] < lo | .data[[col]] > hi))

  n_out <- nrow(out_of_range)

  if (n_out > 0) {
    range_actual <- range(out_of_range[[col]], na.rm = TRUE)
    warning(glue::glue(
      "[{script_name} WARNING] {n_out} dates outside {lo} to {hi} range in '{col}' -- ",
      "range: {range_actual[1]} to {range_actual[2]} -- ",
      "tumor registry may include pre-2012 dates (legitimate)"
    ))
  }

  invisible(df)
}

#' Warn when row counts are suspiciously low or high
#'
#' Sanity check for post-join/filter row counts. Warns (not errors) when actual
#' row count falls outside expected bounds. Detects data loss (too few rows) or
#' cartesian products (too many rows).
#'
#' @param df Data frame. Object to validate
#' @param name Character. Descriptive name for warning messages
#' @param min_expected Numeric. Minimum expected row count (NULL to skip check)
#' @param max_expected Numeric. Maximum expected row count (NULL to skip check)
#' @param script_name Character. Calling script identifier (e.g., "R/14")
#' @return Invisible df (always returns, warning may be emitted)
#'
#' @examples
#' n_before <- nrow(cohort)
#' cohort_with_payer <- cohort %>% left_join(payer_summary, by = "ID")
#'
#' warn_row_count(
#'   cohort_with_payer,
#'   name = "cohort after payer join",
#'   min_expected = n_before,
#'   max_expected = n_before * 1.05,
#'   script_name = "R/14"
#' )
warn_row_count <- function(df, name, min_expected = NULL, max_expected = NULL, script_name) {
  actual <- nrow(df)

  if (!is.null(min_expected) && actual < min_expected) {
    warning(glue::glue(
      "[{script_name} WARNING] {name} has {actual} rows, expected >= {min_expected} -- ",
      "possible data loss from join/filter"
    ))
  }

  if (!is.null(max_expected) && actual > max_expected) {
    warning(glue::glue(
      "[{script_name} WARNING] {name} has {actual} rows, expected <= {max_expected} -- ",
      "possible cartesian product from join"
    ))
  }

  invisible(df)
}
