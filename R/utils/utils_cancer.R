# ==============================================================================
# utils/utils_cancer.R -- Cancer site classification utilities
# ==============================================================================
#
# Purpose:
#   Provides is_cancer_code() for detecting cancer/neoplasm codes and
#   classify_codes() for mapping ICD-10/ICD-O-3/ICD-9 codes to cancer site
#   categories using the CANCER_SITE_MAP and ICD9_CANCER_SITE_MAP constants
#   from R/00_config.R. Used by 10+ cancer analysis scripts (R/28, R/40,
#   R/43-R/49, R/51, R/56).
#
# Inputs:
#   - None (utility function library, not a standalone script)
#
# Outputs:
#   - None (defines functions loaded into calling scripts' environment)
#
# Dependencies:
#   - CANCER_SITE_MAP from R/00_config.R (ICD-10 prefix-to-category mapping)
#   - ICD9_CANCER_SITE_MAP from R/00_config.R (ICD-9 prefix-to-category mapping)
#   - stringr package (for str_remove in code normalization)
#
# Requirements: DRY-02 (extract repeated pattern to shared utility), CANCER-01,
#               ICD-06 (shared is_cancer_code utility)
#
# ==============================================================================

#' Detect whether diagnosis codes are cancer/neoplasm codes (vectorized)
#'
#' Uses map-based detection: checks if code prefix exists in CANCER_SITE_MAP
#' (ICD-10) or ICD9_CANCER_SITE_MAP (ICD-9). This ensures gap-free coverage --
#' every code detected as cancer can be classified by classify_codes().
#'
#' WHY map-based (not range-based): Range-based detection (140-239) would include
#' benign/in-situ/uncertain ICD-9 codes (210-239) that classify_codes() cannot
#' classify, creating "detected but unclassified" records. Map-based detection
#' only detects codes that have map entries (140-209 malignant range).
#'
#' @param dx Character vector of diagnosis codes (any format -- dotted or undotted)
#' @return Logical vector (TRUE if cancer code, FALSE otherwise)
#'
#' @examples
#' is_cancer_code(c("C81.90", "201.90", "J44.1", "250.00"))
#' # Returns: c(TRUE, TRUE, FALSE, FALSE)
#'
is_cancer_code <- function(dx) {
  dx_clean <- str_remove(dx, "\\.")  # Normalize: remove dots for prefix matching

  # ICD-10: check 4-char then 3-char prefix against CANCER_SITE_MAP keys
  icd10_match <- substr(dx_clean, 1, 4) %in% names(CANCER_SITE_MAP) |
                 substr(dx_clean, 1, 3) %in% names(CANCER_SITE_MAP)

  # ICD-9: check 4-char then 3-char prefix against ICD9_CANCER_SITE_MAP keys
  icd9_match <- substr(dx_clean, 1, 4) %in% names(ICD9_CANCER_SITE_MAP) |
                substr(dx_clean, 1, 3) %in% names(ICD9_CANCER_SITE_MAP)

  icd10_match | icd9_match
}

#' Classify ICD-10, ICD-O-3, or ICD-9 codes into cancer site categories
#'
#' Maps codes to cancer site categories using hierarchical prefix matching with
#' unified 4-tier cascade:
#' 1. Try 4-character prefix in CANCER_SITE_MAP (ICD-10 subcategory, e.g., C810 -> NLPHL)
#' 2. Fall back to 3-character prefix in CANCER_SITE_MAP (ICD-10 category, e.g., C81 -> classical HL)
#' 3. Try 4-character prefix in ICD9_CANCER_SITE_MAP (ICD-9 subcategory, e.g., 2014 -> NLPHL)
#' 4. Fall back to 3-character prefix in ICD9_CANCER_SITE_MAP (ICD-9 category, e.g., 201 -> classical HL)
#' 5. Return NA for unclassified codes
#'
#' Codes are normalized (dots stripped) at entry for consistent prefix extraction
#' across dotted (201.40) and undotted (20140) formats.
#'
#' WHY 4-char before 3-char: Enables C810/2014 -> "NLPHL" without C81/201 ->
#' "Hodgkin Lymphoma (non-NLPHL)" intercepting first. Checking longer prefix
#' first ensures subcategory specificity.
#'
#' WHY unified cascade: Replaces old ICD-9 201.x exact-match logic with map
#' lookup. The 4-char key "2014" in ICD9_CANCER_SITE_MAP catches NLPHL
#' (formerly handled by ICD9_NLPHL_CODES exact match). The 3-char key "201"
#' catches remaining HL (formerly handled by regex).
#'
#' @param codes Character vector of diagnosis codes (dotted or undotted format)
#' @return Character vector of category names (NA for unclassified codes)
#'
#' @examples
#' classify_codes(c("C810", "C501", "D051"))
#' # Returns: c("NLPHL", "Breast", "In Situ Neoplasms")
#'
#' classify_codes(c("201.40", "162.0", "153"))
#' # Returns: c("NLPHL", "Lung and Bronchus", "Colon")
#'
classify_codes <- function(codes) {
  # Step 0: Normalize all codes (strip dots for consistent prefix extraction)
  # WHY: ICD-9 codes appear in dotted (201.90) and undotted (20190) formats.
  # ICD-10 codes are already undotted in CANCER_SITE_MAP keys. Stripping dots
  # at entry ensures consistent substr() results for both coding systems.
  codes_clean <- str_remove(codes, "\\.")

  # Step 1: Extract prefixes at both specificity levels
  prefix4 <- substr(codes_clean, 1, 4)  # Subcategory (C810, 2014)
  prefix3 <- substr(codes_clean, 1, 3)  # Category (C81, 201)

  # Step 2: ICD-10 4-char match (most specific -- e.g., C810 -> NLPHL)
  match_icd10_4 <- CANCER_SITE_MAP[prefix4]

  # Step 3: ICD-10 3-char fallback (e.g., C81 -> Hodgkin Lymphoma (non-NLPHL))
  match_icd10_3 <- CANCER_SITE_MAP[prefix3]

  # Step 4: ICD-9 4-char match (e.g., 2014 -> NLPHL, 2015 -> classical HL)
  match_icd9_4 <- ICD9_CANCER_SITE_MAP[prefix4]

  # Step 5: ICD-9 3-char fallback (e.g., 201 -> Hodgkin Lymphoma, 162 -> Lung)
  match_icd9_3 <- ICD9_CANCER_SITE_MAP[prefix3]

  # Step 6: Apply priority cascade (per D-05 detection order)
  categories <- ifelse(!is.na(match_icd10_4), match_icd10_4,
                ifelse(!is.na(match_icd10_3), match_icd10_3,
                ifelse(!is.na(match_icd9_4),  match_icd9_4,
                ifelse(!is.na(match_icd9_3),  match_icd9_3,
                       NA_character_))))

  # Remove names from vector indexing to return clean character vector
  unname(categories)
}
