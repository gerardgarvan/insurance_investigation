# ==============================================================================
# Multi-format date parsing for PCORnet CDM data
# ==============================================================================
#
# PCORnet sites export dates in different formats depending on SAS configuration:
#   - YYYY-MM-DD (ISO format, most common in recent exports)
#   - MM/DD/YYYY (US format, common in some site exports)
#   - DDMMMYYYY / DD-MMM-YYYY (SAS DATE9 format, e.g., 15JAN2020)
#   - YYYYMMDD (compact format, no separators)
#   - Excel serial numbers (rare, from Excel-origin exports)
#
# This parser tries each format in sequence and keeps the first successful parse.
# Attempt order matters for ambiguous dates (e.g., 01/02/2020):
#   US format (mdy) wins over European (dmy) since this is US health data.
#
# Requirement: LOAD-02 (< 5% NA rate for date parsing)
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
#' parse_pcornet_date(c("2020-01-15", "01/15/2020", "15JAN2020", "20200115", "44562"))
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

  # Treat "NULL", "null", empty strings, and whitespace-only as NA
  date_char[date_char %in% c("NULL", "null", "", ".")] <- NA_character_
  date_char[!is.na(date_char) & str_detect(date_char, "^\\s*$")] <- NA_character_

  # Strip SAS datetime suffixes (e.g., "05NOV1998:00:00:00.000000" -> "05NOV1998")
  # Also handles "2020-01-15T00:00:00" ISO datetime and "01/15/2020 12:00:00"
  date_char <- str_replace(date_char, "[T: ]\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?$", "")

  # Initialize result vector
  result <- rep(as.Date(NA), length(date_char))

  # ------------------------------------------------------------------------------
  # Attempt 1: YYYY-MM-DD (ISO format, most common)
  # Also catches YYYYMMDD compact format
  # ------------------------------------------------------------------------------
  parsed <- suppressWarnings(ymd(date_char, quiet = TRUE))
  result[!is.na(parsed)] <- parsed[!is.na(parsed)]

  # ------------------------------------------------------------------------------
  # Attempt 2: MM/DD/YYYY (US format, e.g., 01/15/2020 or 1/15/2020)
  # ONLY for numeric-only strings (digits + separators) — skip strings with
  # letters (like 07SEP1939) to avoid mdy() misinterpreting DDMMMYYYY formats
  # ------------------------------------------------------------------------------
  remaining <- is.na(result) & !is.na(date_char)
  if (any(remaining)) {
    is_numeric_date <- remaining & !str_detect(date_char, "[A-Za-z]")
    if (any(is_numeric_date)) {
      parsed_mdy <- suppressWarnings(mdy(date_char[is_numeric_date], quiet = TRUE))
      if (any(!is.na(parsed_mdy))) {
        idx_in_remaining <- which(is_numeric_date)[!is.na(parsed_mdy)]
        result[idx_in_remaining] <- parsed_mdy[!is.na(parsed_mdy)]
      }
    }
  }

  # ------------------------------------------------------------------------------
  # Attempt 3: DDMMMYYYY / DD-MMM-YYYY / DD MMM YYYY (SAS DATE9 and variants)
  # e.g., 15JAN2020, 07SEP1939, 15-Jan-2020, 15 January 2020
  # Uses dmy() which handles text month names in all these formats
  # ------------------------------------------------------------------------------
  remaining <- is.na(result) & !is.na(date_char)
  if (any(remaining)) {
    parsed_dmy <- suppressWarnings(dmy(date_char[remaining], quiet = TRUE))
    if (any(!is.na(parsed_dmy))) {
      idx_in_remaining <- which(remaining)[!is.na(parsed_dmy)]
      result[idx_in_remaining] <- parsed_dmy[!is.na(parsed_dmy)]
    }
  }

  # ------------------------------------------------------------------------------
  # Attempt 4: Excel serial numbers (numeric strings like "44562")
  # Checked after all text formats to avoid misinterpreting short date strings
  # ------------------------------------------------------------------------------
  remaining <- is.na(result) & !is.na(date_char)
  if (any(remaining)) {
    numeric_vals <- suppressWarnings(as.numeric(date_char[remaining]))
    # Valid Excel serial: between 1 (1900-01-01) and 100000 (2174-10-09)
    valid_serial <- !is.na(numeric_vals) & numeric_vals > 1 & numeric_vals < 100000
    if (any(valid_serial)) {
      parsed_excel <- excel_numeric_to_date(numeric_vals[valid_serial])
      idx_in_remaining <- which(remaining)[valid_serial]
      result[idx_in_remaining] <- parsed_excel
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
