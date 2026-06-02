# ==============================================================================
# utils/utils_cancer.R -- Cancer site classification utilities
# ==============================================================================
#
# Purpose:
#   Provides classify_codes() for mapping ICD-10/ICD-O-3/ICD-9 codes to cancer
#   site categories using the CANCER_SITE_MAP constant from R/00_config.R. Used
#   by 10+ cancer analysis scripts (R/28, R/40, R/43-R/49, R/51).
#
# Inputs:
#   - None (utility function library, not a standalone script)
#
# Outputs:
#   - None (defines functions loaded into calling scripts' environment)
#
# Dependencies:
#   - CANCER_SITE_MAP from R/00_config.R (must be loaded before this module)
#   - ICD9_NLPHL_CODES from R/00_config.R (for ICD-9 NLPHL classification)
#
# Requirements: DRY-02 (extract repeated pattern to shared utility), CANCER-01
#
# ==============================================================================

#' Classify ICD-10, ICD-O-3, or ICD-9 codes into cancer site categories
#'
#' Maps codes to cancer site categories using hierarchical prefix matching:
#' 1. Try 4-character prefix lookup (subcategory, e.g., C810 -> NLPHL)
#' 2. Fall back to 3-character prefix lookup (category, e.g., C81 -> classical HL)
#' 3. Check ICD-9 codes against ICD9_NLPHL_CODES for exact NLPHL matching
#'
#' Both lookups use the 324-entry CANCER_SITE_MAP defined in R/00_config.R.
#' Returns NA for codes whose prefix has no mapping in CANCER_SITE_MAP.
#'
#' WHY 4-char before 3-char: Enables C81.0x -> "NLPHL" without C81 ->
#' "Hodgkin Lymphoma (non-NLPHL)" intercepting first. The 4-char key "C810"
#' exists in CANCER_SITE_MAP alongside "C81"; checking longer prefix first
#' ensures subcategory specificity.
#'
#' WHY ICD-9 exact match: ICD-9 codes (e.g., 201.40) use dotted format where
#' prefix extraction doesn't cleanly isolate subcategories. The ICD9_NLPHL_CODES
#' list provides exact match for the 10 NLPHL-specific ICD-9 codes.
#'
#' @param codes Character vector of normalized codes (uppercase, no dots for
#'   ICD-10; dotted format for ICD-9, e.g., "201.40")
#' @return Character vector of category names (NA for unclassified codes)
#'
#' @examples
#' classify_codes(c("C810", "C501", "D051"))
#' # Returns: c("NLPHL", "Breast", "In Situ Neoplasms")
#'
#' classify_codes(c("C811", "C819"))
#' # Returns: c("Hodgkin Lymphoma (non-NLPHL)", "Hodgkin Lymphoma (non-NLPHL)")
#'
#' classify_codes(c("201.40", "201.90"))
#' # Returns: c("NLPHL", "Hodgkin Lymphoma (non-NLPHL)")
#'
classify_codes <- function(codes) {
  # Step 1: Extract prefixes at both specificity levels (ICD-10)
  prefix4 <- substr(codes, 1, 4)  # Subcategory level (e.g., C810)
  prefix3 <- substr(codes, 1, 3)  # Category level (e.g., C81)

  # Step 2: Attempt 4-char match first (more specific wins)
  match4 <- CANCER_SITE_MAP[prefix4]

  # Step 3: Fallback to 3-char match (broader category)
  match3 <- CANCER_SITE_MAP[prefix3]

  # Step 4: Use 4-char result if available, else 3-char
  categories <- ifelse(!is.na(match4), match4, match3)

  # Step 5: ICD-9 NLPHL override (exact match, dotted format)
  # WHY separate check: ICD-9 codes use dotted format (201.40) where substr()
  # produces "201." not "2014", so prefix matching doesn't work cleanly.
  is_icd9_nlphl <- codes %in% ICD9_NLPHL_CODES
  categories[is_icd9_nlphl] <- "NLPHL"

  # Remove names from vector indexing to return clean character vector
  unname(categories)
}
