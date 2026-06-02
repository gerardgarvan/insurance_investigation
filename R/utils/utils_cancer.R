# ==============================================================================
# utils/utils_cancer.R -- Cancer site classification utilities
# ==============================================================================
#
# Purpose:
#   Provides classify_codes() for mapping ICD-10/ICD-O-3 codes to cancer site
#   categories using the CANCER_SITE_MAP constant from R/00_config.R. Used by
#   10+ cancer analysis scripts (R/28, R/40, R/43-R/49, R/51).
#
# Inputs:
#   - None (utility function library, not a standalone script)
#
# Outputs:
#   - None (defines functions loaded into calling scripts' environment)
#
# Dependencies:
#   - CANCER_SITE_MAP from R/00_config.R (must be loaded before this module)
#
# Requirements: DRY-02 (extract repeated pattern to shared utility)
#
# ==============================================================================

#' Classify ICD-10 or ICD-O-3 codes into cancer site categories
#'
#' Maps codes to cancer site categories by matching the first 3 characters
#' against CANCER_SITE_MAP (324-entry lookup defined in R/00_config.R).
#' Returns NA for codes whose 3-char prefix has no mapping.
#'
#' @param codes Character vector of normalized codes (uppercase, no dots)
#' @return Character vector of category names (NA for unclassified codes)
#'
#' @examples
#' classify_codes(c("C810", "C501", "D051"))
#' # Returns: c("Hodgkin Lymphoma", "Breast", "In Situ Neoplasms")
#'
classify_codes <- function(codes) {
  prefix3 <- substr(codes, 1, 3)
  categories <- unname(CANCER_SITE_MAP[prefix3])
  categories
}
