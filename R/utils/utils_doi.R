# ==============================================================================
# utils/utils_doi.R -- Diagnosis-of-Interest (DoI) classification utilities
# ==============================================================================
#
# Purpose:
#   is_doi_code(dx, dx_type)  -- DX_TYPE-gated detector for non-malignant
#     rituximab/methotrexate indication codes (autoimmune/inflammatory/
#     hematologic). Prefix-matches against DOI_CODE_MAP from R/00_config.R.
#   classify_doi_codes(codes) -- maps ICD-10/ICD-9 codes to DoI categories via
#     the 4-char-before-3-char prefix cascade over DOI_CODE_MAP.
#
#   WHY parallel to utils_cancer.R but NOT merged: classify_codes() has 10+
#   consumers that assume cancer-site output; merging would corrupt them.
#   Auto-sourced via the R/utils/*.R glob at the end of R/00_config.R.
#
#   WHY is_doi_code() is DX_TYPE-gated (unlike is_cancer_code()): ICD-9 RA is
#   "714" and there is no ICD-10 code beginning "714", but bare-numeric prefix
#   keys (714, 710, 446, 287, 283, 341, 358, 696, 555, 556) MUST only match
#   ICD-9 records. Gating on dx_type ("09"/"10", NA/SNOMED -> FALSE) mirrors
#   is_hl_diagnosis() and prevents ICD-9/ICD-10 numeric collision (PITFALLS 1).
#
# Dependencies: DOI_CODE_MAP from R/00_config.R; normalize_icd() from
#   utils_icd.R; stringr.
# ==============================================================================

library(stringr)

# Which DOI_CODE_MAP keys are ICD-9 (bare numeric) vs ICD-10 (alpha-leading).
# Computed once at source time from the map so the two systems never cross-match.
.doi_keys_icd9  <- grep("^[0-9]", names(DOI_CODE_MAP), value = TRUE)
.doi_keys_icd10 <- grep("^[0-9]", names(DOI_CODE_MAP), value = TRUE, invert = TRUE)

#' Detect whether diagnosis codes are non-malignant DoI codes (DX_TYPE-gated)
#'
#' Prefix-matches against DOI_CODE_MAP from R/00_config.R, gated on DX_TYPE so
#' that numeric ICD-9 keys (714, 710, 446, ...) only match ICD-9 records and
#' alpha-leading ICD-10 keys (M05, D692, ...) only match ICD-10 records.
#' NA or non-"09"/"10" DX_TYPE values (e.g. "SM" for SNOMED) return FALSE.
#'
#' @param dx      Character vector of diagnosis codes (dotted or undotted)
#' @param dx_type Character vector of DX_TYPE values ("09" ICD-9, "10" ICD-10;
#'   NA / "SM" / anything else -> FALSE)
#' @return Logical vector; TRUE only when the code's prefix is in DOI_CODE_MAP
#'   AND dx_type matches the coding system that key belongs to.
#'
#' @examples
#' is_doi_code(c("M05.9", "714.0", "714.0", "C81.90"), c("10", "09", "10", "10"))
#' # Returns: c(TRUE, TRUE, FALSE, FALSE)
#'
#' is_doi_code(c("M05.9", "M05.9"), c(NA, "SM"))
#' # Returns: c(FALSE, FALSE)
is_doi_code <- function(dx, dx_type) {
  if (length(dx) == 0) return(logical(0))
  result <- rep(FALSE, length(dx))

  # Gate: both values present AND dx_type is a recognized ICD coding system
  valid <- !is.na(dx) & !is.na(dx_type) & dx_type %in% c("09", "10")
  if (!any(valid)) return(result)

  dx_clean <- normalize_icd(dx)          # reuse: uppercase + strip dots
  p4 <- substr(dx_clean, 1, 4)
  p3 <- substr(dx_clean, 1, 3)

  is10 <- valid & dx_type == "10"
  is09 <- valid & dx_type == "09"

  # ICD-10 records: match against alpha-leading DOI_CODE_MAP keys only
  result[is10] <- (p4[is10] %in% .doi_keys_icd10) | (p3[is10] %in% .doi_keys_icd10)

  # ICD-9 records: match against numeric DOI_CODE_MAP keys only
  result[is09] <- (p4[is09] %in% .doi_keys_icd9) | (p3[is09] %in% .doi_keys_icd9)

  result
}

#' Classify ICD-10/ICD-9 codes into DoI categories (4-char before 3-char)
#'
#' Mirrors classify_codes() from utils_cancer.R: normalizes codes (dots
#' stripped), tries the 4-character prefix against DOI_CODE_MAP first (so
#' D692 -> "Vasculitis" and D693 -> "Hematologic Autoimmune" resolve before
#' the 3-char "D69" prefix would be attempted), then falls back to the
#' 3-character prefix, and returns NA for codes with no map entry.
#'
#' NOT DX_TYPE-gated -- callers that need gating should filter rows with
#' is_doi_code() first, matching the contract of classify_codes() which
#' classifies only codes already known to be in scope.
#'
#' @param codes Character vector of diagnosis codes (dotted or undotted)
#' @return Character vector of DoI category names (NA if no map entry)
#'
#' @examples
#' classify_doi_codes(c("M05.9", "D69.2", "D69.3", "K50.90"))
#' # Returns: c("Rheumatoid Arthritis", "Vasculitis",
#' #            "Hematologic Autoimmune", "Inflammatory Bowel Disease")
#'
#' classify_doi_codes("C81.90")
#' # Returns: NA  (HL code, no DOI_CODE_MAP entry)
classify_doi_codes <- function(codes) {
  # Normalize: strip first dot for prefix extraction
  # (str_remove removes only the first occurrence, matching classify_codes())
  codes_clean <- str_remove(codes, "\\.")
  p4 <- substr(codes_clean, 1, 4)
  p3 <- substr(codes_clean, 1, 3)

  # 4-char lookup (most specific -- disambiguates D692/D693, H460/H461/H468/H469)
  m4 <- DOI_CODE_MAP[p4]

  # 3-char fallback (catches M05, M06, K50, K51, L40, M30, M31, etc.)
  m3 <- DOI_CODE_MAP[p3]

  # Apply 4-char-before-3-char priority; return unnamed vector
  unname(ifelse(!is.na(m4), m4, ifelse(!is.na(m3), m3, NA_character_)))
}

# ==============================================================================
# End of utils_doi.R
# ==============================================================================
