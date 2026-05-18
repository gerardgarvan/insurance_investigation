# ==============================================================================
# utils_payer.R -- Shared payer classification and comparison helpers
# ==============================================================================
# Provides utility functions used across payer analysis and overlap
# classification scripts. Auto-sourced by 00_config.R.
# ==============================================================================

#' Check if payer value represents missing data
#'
#' Detects NA, empty string, or PCORnet sentinel values (NI, UN, OT, 99, 9999).
#' Phase 32: Uses direct empty-string check (DuckDB translation gap #7).
#'
#' @param payer_value Character. Payer type or source value from PCORnet
#' @return Logical. TRUE if payer is missing/unknown
is_missing_payer <- function(payer_value) {
  is.na(payer_value) |
    payer_value == "" |
    payer_value %in% c("NI", "UN", "OT", "99", "9999")
}

#' Map AMC 8-category payer scheme to resolution tiers
#'
#' One-to-one mapping from 8 AMC categories to 8 resolution tiers.
#' Used for same-day payer tier resolution (Phase 36+).
#'
#' @param payer_category Character. AMC payer category from PAYER_MAPPING
#' @return Character. Tier name for hierarchical resolution
CODE_TO_TIER <- function(payer_category) {
  case_when(
    payer_category == "Medicaid"  ~ "Medicaid",
    payer_category == "Medicare"  ~ "Medicare",
    payer_category == "Private"   ~ "Private",
    payer_category == "Other govt" ~ "Other govt",
    payer_category == "Other"     ~ "Other",
    payer_category == "Self-pay"  ~ "Self-pay",
    payer_category == "Uninsured" ~ "Uninsured",
    payer_category == "Missing"   ~ "Missing",
    is.na(payer_category)         ~ "Missing",
    TRUE ~ "Missing"
  )
}

#' NA-safe field comparison for overlap detection
#'
#' Returns TRUE if both values are NA, or both are non-NA and equal.
#' Used for payer overlap classification (Phase 23+).
#'
#' @param val1 Any. First value to compare
#' @param val2 Any. Second value to compare
#' @return Logical. TRUE if fields match (including both-NA case)
field_match <- function(val1, val2) {
  both_na <- is.na(val1) & is.na(val2)
  one_na  <- xor(is.na(val1), is.na(val2))
  both_na | (!one_na & !is.na(val1) & (val1 == val2))
}
