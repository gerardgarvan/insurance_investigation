# ==============================================================================
# Multi-format date parsing for PCORnet CDM data
# ==============================================================================
#
# PCORnet sites export dates in different formats depending on SAS configuration:
#   - YYYY-MM-DD (ISO format, most common in recent exports)
#   - DDMMMYYYY (SAS DATE9 format, e.g., 15JAN2020)
#   - YYYYMMDD (compact format, no separators)
#   - Excel serial numbers (rare, from Excel-origin exports)
#
# This parser tries each format in sequence and keeps the first successful parse.
# Requirement: LOAD-02 (< 5% NA rate for date parsing)
#
# ==============================================================================

library(lubridate)
library(janitor)
library(stringr)
library(glue)

#' Parse PCORnet dates with multi-format fallback
#'
#' @param date_char Character vector of dates in various formats
#' @return Date vector with NA for unparseable values
#'
#' @examples
#' parse_pcornet_date(c("2020-01-15", "15JAN2020", "20200115", "44562"))
#' parse_pcornet_date(c(NA, "", "2020-01-15"))
#'
parse_pcornet_date <- function(date_char) {

  # Handle edge cases
  if (length(date_char) == 0) {
    return(as.Date(character(0)))
  }

  if (all(is.na(date_char))) {
    return(as.Date(rep(NA, length(date_char))))
  }

  # If already Date type, return as-is (defensive check)
  if (inherits(date_char, "Date")) {
    return(date_char)
  }

  # Initialize result vector
  result <- rep(as.Date(NA), length(date_char))

  # ------------------------------------------------------------------------------
  # Attempt 1: YYYY-MM-DD (ISO format, most common)
  # ------------------------------------------------------------------------------
  parsed <- suppressWarnings(ymd(date_char, quiet = TRUE))
  result[!is.na(parsed)] <- parsed[!is.na(parsed)]

  # ------------------------------------------------------------------------------
  # Attempt 2: Excel serial numbers (numeric strings like "44562")
  # ------------------------------------------------------------------------------
  remaining <- is.na(result) & !is.na(date_char)
  if (any(remaining)) {
    numeric_vals <- suppressWarnings(as.numeric(date_char[remaining]))
    # Valid Excel serial: between 1 (1900-01-01) and 100000 (2174-10-09)
    valid_serial <- !is.na(numeric_vals) & numeric_vals > 1 & numeric_vals < 100000
    if (any(valid_serial)) {
      parsed_excel <- excel_numeric_to_date(numeric_vals[valid_serial])
      # Need to update result using proper indexing
      idx_in_remaining <- which(remaining)[valid_serial]
      result[idx_in_remaining] <- parsed_excel
    }
  }

  # ------------------------------------------------------------------------------
  # Attempt 3: SAS DATE9 (DDMMMYYYY like 15JAN2020)
  # ------------------------------------------------------------------------------
  remaining <- is.na(result) & !is.na(date_char)
  if (any(remaining)) {
    parsed_date9 <- suppressWarnings(
      parse_date_time(date_char[remaining], orders = "dby", quiet = TRUE)
    )
    if (any(!is.na(parsed_date9))) {
      idx_in_remaining <- which(remaining)[!is.na(parsed_date9)]
      result[idx_in_remaining] <- as.Date(parsed_date9[!is.na(parsed_date9)])
    }
  }

  # ------------------------------------------------------------------------------
  # Attempt 4: YYYYMMDD (compact format, no separators)
  # ------------------------------------------------------------------------------
  remaining <- is.na(result) & !is.na(date_char)
  if (any(remaining)) {
    # Only try for 8-character strings
    eight_char <- str_length(date_char[remaining]) == 8
    if (any(eight_char)) {
      parsed_compact <- suppressWarnings(
        ymd(date_char[remaining][eight_char], quiet = TRUE)
      )
      if (any(!is.na(parsed_compact))) {
        idx_in_remaining <- which(remaining)[eight_char][!is.na(parsed_compact)]
        result[idx_in_remaining] <- parsed_compact[!is.na(parsed_compact)]
      }
    }
  }

  # ------------------------------------------------------------------------------
  # Log unparseable dates (but don't fail — per D-10)
  # ------------------------------------------------------------------------------
  unparsed_count <- sum(is.na(result) & !is.na(date_char))
  if (unparsed_count > 0) {
    unparsed_pct <- round(100 * unparsed_count / length(date_char), 1)
    message(glue("  WARNING: {unparsed_count} ({unparsed_pct}%) dates could not be parsed"))
  }

  return(result)
}

# ==============================================================================
# End of utils_dates.R
# ==============================================================================
