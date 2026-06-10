# ==============================================================================
# utils/utils_dt.R -- data.table conversion helpers
# ==============================================================================
#
# Purpose:
#   Provides 3 helper functions for safe tibble/data.table boundary management.
#   Used by Phase 96+ functions that operate in data.table internally but return
#   tibbles for dplyr pipeline compatibility. Follows the same defensive coding
#   pattern as utils_assertions.R (checkmate-style error messages with glue).
#
# Inputs:
#   - None (utility function library, not a standalone script)
#
# Outputs:
#   - None (defines functions loaded into calling scripts' environment)
#     - ensure_dt(): Convert input to data.table with NULL/empty guards
#     - to_tibble_safe(): Convert data.table back to tibble with NULL/empty guards
#     - get_lookup_dt(): Retrieve keyed data.table from LOOKUP_TABLES_DT by name
#
# Dependencies:
#   - data.table: is.data.table(), as.data.table() (loaded in R/00_config.R)
#   - tibble: is_tibble(), as_tibble() (loaded via tidyverse in calling scripts)
#   - glue: String interpolation for error messages (loaded in R/00_config.R)
#
# Requirements:
#   - INFRA-02: Conversion helpers for tibble/data.table boundary management
#
# ==============================================================================

#' Convert input to data.table defensively
#'
#' Converts input to data.table with NULL/empty guards following defensive coding
#' patterns from utils_assertions.R. NULL inputs cause immediate stop. Empty inputs
#' (0 rows) emit warning but return empty data.table preserving column structure.
#' Already-data.table inputs are returned as-is (no-op). Otherwise, creates a copy
#' via as.data.table() (not setDT() per anti-pattern guidance).
#'
#' @param df Data frame or data.table. Input to convert
#' @param name Character. Descriptive name for error messages (default: "input")
#' @param script_name Character. Calling script identifier (default: "unknown")
#' @return data.table (always; stops on NULL, warns on empty)
#'
#' @examples
#' # Convert tibble to data.table for keyed join
#' enrollment_dt <- ensure_dt(enrollment, name = "ENROLLMENT", script_name = "R/96")
#'
#' # No-op if already data.table
#' lookup_dt <- ensure_dt(LOOKUP_TABLES_DT$AMC_PAYER_LOOKUP, script_name = "R/96")
ensure_dt <- function(df, name = "input", script_name = "unknown") {
  # NULL check: immediate stop
  if (is.null(df)) {
    stop(glue::glue("[{script_name} ERROR] {name} is NULL"))
  }

  # Empty check: warning, then return empty data.table preserving structure
  if (nrow(df) == 0) {
    warning(glue::glue("[{script_name} WARNING] {name} is empty (0 rows)"))
    return(data.table::as.data.table(df))
  }

  # Already data.table: no-op
  if (data.table::is.data.table(df)) {
    return(df)
  }

  # Otherwise: convert to data.table (creates copy, does NOT mutate input)
  data.table::as.data.table(df)
}

#' Convert data.table back to tibble for dplyr pipeline compatibility
#'
#' Converts data.table to tibble with NULL/empty guards. NULL inputs cause
#' immediate stop. Empty inputs (0 rows) emit warning but return empty tibble
#' preserving column structure. Already-tibble inputs are returned as-is (no-op).
#' Otherwise, converts via as_tibble().
#'
#' @param dt Data frame, tibble, or data.table. Input to convert
#' @param name Character. Descriptive name for error messages (default: "output")
#' @param script_name Character. Calling script identifier (default: "unknown")
#' @return tibble (always; stops on NULL, warns on empty)
#'
#' @examples
#' # Convert data.table result back to tibble for dplyr pipeline
#' payer_summary_tbl <- to_tibble_safe(
#'   payer_summary_dt,
#'   name = "payer_summary",
#'   script_name = "R/96"
#' )
#'
#' # No-op if already tibble
#' result_tbl <- to_tibble_safe(existing_tibble, script_name = "R/96")
to_tibble_safe <- function(dt, name = "output", script_name = "unknown") {
  # NULL check: immediate stop
  if (is.null(dt)) {
    stop(glue::glue("[{script_name} ERROR] {name} is NULL"))
  }

  # Empty check: warning, then return empty tibble preserving structure
  if (nrow(dt) == 0) {
    warning(glue::glue("[{script_name} WARNING] {name} is empty (0 rows)"))
    return(tibble::as_tibble(dt))
  }

  # Already tibble: no-op
  if (tibble::is_tibble(dt)) {
    return(dt)
  }

  # Otherwise: convert to tibble
  tibble::as_tibble(dt)
}

#' Retrieve keyed data.table from LOOKUP_TABLES_DT by name
#'
#' Retrieves a keyed data.table from the LOOKUP_TABLES_DT list by string name.
#' Validates that table_name is character and exists in lookup_list. Provides
#' informative error with available table names if lookup fails.
#'
#' @param table_name Character. Name of lookup table to retrieve
#'   (e.g., "AMC_PAYER_LOOKUP", "DRUG_GROUPINGS", "CANCER_SITE_MAP")
#' @param lookup_list Named list. List of keyed data.tables (default: LOOKUP_TABLES_DT)
#' @return data.table from lookup_list (always; stops if table_name invalid or not found)
#'
#' @examples
#' # Retrieve payer lookup table
#' payer_lookup <- get_lookup_dt("AMC_PAYER_LOOKUP")
#'
#' # Use in join context
#' enrollment_with_payer <- enrollment_dt[
#'   get_lookup_dt("AMC_PAYER_LOOKUP"),
#'   on = .(RAW_PAYER_SOURCE_VALUE = code),
#'   payer_category := i.payer_category
#' ]
get_lookup_dt <- function(table_name, lookup_list = LOOKUP_TABLES_DT) {
  # Validate table_name is character
  if (!is.character(table_name) || length(table_name) != 1) {
    stop(glue::glue(
      "[get_lookup_dt ERROR] table_name must be character, got {class(table_name)[1]}"
    ))
  }

  # Validate table_name exists in lookup_list
  if (!table_name %in% names(lookup_list)) {
    stop(glue::glue(
      "[get_lookup_dt ERROR] '{table_name}' not found in lookup list. ",
      "Available: {paste(names(lookup_list), collapse=', ')}"
    ))
  }

  # Return the requested lookup table
  lookup_list[[table_name]]
}
