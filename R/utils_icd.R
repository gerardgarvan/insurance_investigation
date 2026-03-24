# ==============================================================================
# ICD code normalization and HL diagnosis matching
# ==============================================================================
#
# This utility provides functions for working with ICD diagnosis codes
# in the context of Hodgkin Lymphoma (HL) cohort identification.
#
# Functions:
#   - normalize_icd(icd_code): Remove dots from ICD codes for consistent matching
#   - is_hl_diagnosis(icd_code, icd_type): Check if ICD code is HL diagnosis
#
# Usage:
#   source("R/00_config.R")  # Auto-loads this file
#   dx_clean <- normalize_icd(c("C81.00", "C8100", "201.90"))
#   is_hl <- is_hl_diagnosis(dx$DX, dx$DX_TYPE)
#
# ==============================================================================

library(stringr)

#' Remove dots from ICD codes for consistent matching
#'
#' PCORnet sites export ICD codes in both dotted (C81.00) and undotted (C8100)
#' formats. This function normalizes to undotted format for reliable matching.
#'
#' @param icd_code Character vector of ICD codes (may contain dots)
#' @return Character vector with dots removed
#'
#' @examples
#' normalize_icd(c("C81.00", "C8100", "201.90", "20190"))
#' # Returns: c("C8100", "C8100", "20190", "20190")
#'
#' normalize_icd(c(NA, "C81.00", NA))
#' # Returns: c(NA, "C8100", NA)
#'
normalize_icd <- function(icd_code) {
  # Handle NA gracefully: NA in -> NA out
  if (all(is.na(icd_code))) {
    return(icd_code)
  }

  # Remove all dots
  str_remove_all(icd_code, "\\.")
}

#' Check if ICD code is a Hodgkin Lymphoma diagnosis
#'
#' Matches against the 149 HL diagnosis codes defined in 00_config.R:
#'   - 77 ICD-10 codes: C81.00–C81.99 (7 subtypes × 10 anatomic sites + C81.4x)
#'   - 72 ICD-9 codes: 201.00–201.98 (8 subtypes × 9 anatomic sites)
#'
#' Both input codes and config codes are normalized (dots removed) before matching.
#'
#' @param icd_code Character vector of ICD codes from DIAGNOSIS.DX column
#' @param icd_type Character vector of ICD type codes from DIAGNOSIS.DX_TYPE
#'                 ("09" for ICD-9, "10" for ICD-10)
#' @return Logical vector indicating HL diagnosis matches
#'
#' @examples
#' is_hl_diagnosis(c("C81.00", "E11.9", "201.90"), c("10", "10", "09"))
#' # Returns: c(TRUE, FALSE, TRUE)
#'
#' is_hl_diagnosis(c(NA, "C81.00", "C81.00"), c(NA, "10", NA))
#' # Returns: c(FALSE, TRUE, FALSE)
#'
is_hl_diagnosis <- function(icd_code, icd_type) {

  # Handle edge cases: if icd_code or icd_type is NA, return FALSE
  if (length(icd_code) == 0) {
    return(logical(0))
  }

  # Initialize result as all FALSE
  result <- rep(FALSE, length(icd_code))

  # Handle NA: if icd_code or icd_type is NA, result is FALSE (already initialized)
  valid <- !is.na(icd_code) & !is.na(icd_type)

  if (!any(valid)) {
    return(result)
  }

  # Normalize input codes (remove dots)
  icd_clean <- normalize_icd(icd_code)

  # Build normalized reference lists from config
  # ICD_CODES is defined in 00_config.R (auto-sourced before this file)
  icd10_clean <- normalize_icd(ICD_CODES$hl_icd10)
  icd9_clean <- normalize_icd(ICD_CODES$hl_icd9)

  # Match against appropriate reference list based on icd_type
  # DX_TYPE: "09" for ICD-9, "10" for ICD-10
  result[valid] <- (
    (icd_type[valid] == "10" & icd_clean[valid] %in% icd10_clean) |
    (icd_type[valid] == "09" & icd_clean[valid] %in% icd9_clean)
  )

  return(result)
}

# ==============================================================================
# End of utils_icd.R
# ==============================================================================
