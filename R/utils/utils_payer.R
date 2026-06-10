# ==============================================================================
# utils/utils_payer.R -- Shared payer classification and comparison helpers
# ==============================================================================
#
# Purpose:
#   Shared payer classification and comparison helpers. Provides is_missing_payer()
#   and payer category validation functions. Used across payer harmonization,
#   overlap classification, and tiered payer resolution scripts. Detects missing
#   payer values (NA, empty string, PCORnet sentinels NI/UN/OT), maps AMC 8
#   categories to resolution tiers, and provides validation helpers for payer logic.
#
# Inputs:
#   - None (utility function library, not a standalone script)
#
# Outputs:
#   - None (defines functions loaded into calling scripts' environment)
#
# Dependencies:
#   - dplyr: case_when() for tier mapping logic
#
# Requirements: N/A (utility module)
#
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
    payer_category == "Medicaid" ~ "Medicaid",
    payer_category == "Medicare" ~ "Medicare",
    payer_category == "Private" ~ "Private",
    payer_category == "Other govt" ~ "Other govt",
    payer_category == "Other" ~ "Other",
    payer_category == "Self-pay" ~ "Self-pay",
    payer_category == "Uninsured" ~ "Uninsured",
    payer_category == "Missing" ~ "Missing",
    is.na(payer_category) ~ "Missing",
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
  one_na <- xor(is.na(val1), is.na(val2))
  both_na | (!one_na & !is.na(val1) & (val1 == val2))
}

#' Classify encounter rows into payer tiers (row-level)
#'
#' Performs the full payer classification chain: effective_payer resolution,
#' AMC 8-category mapping (direct lookup + prefix fallback), tier assignment,
#' special code overrides (93/14), and tier_rank assignment.
#'
#' @param df Data frame with columns: PAYER_TYPE_PRIMARY,
#'   PAYER_TYPE_SECONDARY, SOURCE
#' @param include_dual Logical. If TRUE, compute dual_eligible flag (default
#'   TRUE). R/60 and R/61 use TRUE; R/62 uses FALSE.
#' @param flm_override Logical. If TRUE, override tier to "Medicaid" when
#'   SOURCE == "FLM" (default FALSE). R/61 and R/62 use TRUE; R/60 uses FALSE
#'   (handles FLM in same-day resolution).
#' @return Data frame with added columns: effective_payer, payer_category,
#'   tier, tier_rank, and optionally dual_eligible
#'
#' @examples
#' enc %>% classify_payer_tier(include_dual = TRUE, flm_override = FALSE)
#'
classify_payer_tier <- function(df, include_dual = TRUE, flm_override = FALSE) {
  result <- df %>%
    mutate(
      PAYER_TYPE_PRIMARY = as.character(PAYER_TYPE_PRIMARY),
      PAYER_TYPE_SECONDARY = as.character(PAYER_TYPE_SECONDARY),
      SOURCE = as.character(SOURCE),
      # Effective payer: primary if valid, else secondary, else NA
      effective_payer = case_when(
        !is.na(PAYER_TYPE_PRIMARY) & nchar(trimws(PAYER_TYPE_PRIMARY)) > 0 &
          !PAYER_TYPE_PRIMARY %in% PAYER_MAPPING$sentinel_values ~
          PAYER_TYPE_PRIMARY,
        !is.na(PAYER_TYPE_SECONDARY) &
          nchar(trimws(PAYER_TYPE_SECONDARY)) > 0 &
          !PAYER_TYPE_SECONDARY %in% PAYER_MAPPING$sentinel_values ~
          PAYER_TYPE_SECONDARY,
        TRUE ~ NA_character_
      ),
      # Map to AMC 8-category: direct lookup + prefix fallback
      payer_category = {
        looked_up <- AMC_PAYER_LOOKUP[effective_payer]
        prefix_cat <- case_when(
          startsWith(effective_payer, "1") ~ "Medicare",
          startsWith(effective_payer, "2") ~ "Medicaid",
          startsWith(effective_payer, "5") | startsWith(effective_payer, "6") ~
            "Private",
          startsWith(effective_payer, "3") | startsWith(effective_payer, "4") ~
            "Other govt",
          startsWith(effective_payer, "7") ~ "Private",
          startsWith(effective_payer, "8") ~ "Uninsured",
          startsWith(effective_payer, "9") ~ "Other",
          TRUE ~ "Other"
        )
        result <- if_else(!is.na(looked_up), looked_up, prefix_cat)
        if_else(is.na(effective_payer), "Missing", result)
      },
      # Map to tier
      tier = CODE_TO_TIER(payer_category),
      # Override with special codes 93/14
      tier = coalesce(
        case_when(
          PAYER_TYPE_PRIMARY %in% c("93", "14") ~ "Medicaid",
          PAYER_TYPE_SECONDARY %in% c("93", "14") ~ "Medicaid",
          TRUE ~ NA_character_
        ),
        tier
      )
    )

  # Conditional FLM source override (R/61, R/62 use it; R/60 does not)
  if (flm_override) {
    result <- result %>%
      mutate(tier = if_else(SOURCE == "FLM" & !is.na(SOURCE), "Medicaid",
        tier))
  }

  # Safety net + tier rank assignment
  result <- result %>%
    mutate(
      tier = if_else(is.na(tier), "Missing", tier),
      tier_rank = unlist(TIER_MAPPING[tier]),
      tier_rank = if_else(is.na(tier_rank), 8L, tier_rank)
    )

  # Conditional dual_eligible flag (R/60, R/61 use it; R/62 does not)
  if (include_dual) {
    result <- result %>%
      mutate(
        dual_eligible = {
          dual_codes <- PAYER_MAPPING$dual_eligible_codes
          sec_missing <- is.na(PAYER_TYPE_SECONDARY) |
            nchar(trimws(PAYER_TYPE_SECONDARY)) == 0
          has_dual <- PAYER_TYPE_PRIMARY %in% dual_codes |
            PAYER_TYPE_SECONDARY %in% dual_codes
          cross_payer <- (startsWith(PAYER_TYPE_PRIMARY, "1") &
            startsWith(PAYER_TYPE_SECONDARY, "2")) |
            (startsWith(PAYER_TYPE_PRIMARY, "2") &
              startsWith(PAYER_TYPE_SECONDARY, "1"))
          case_when(sec_missing ~ 0L, has_dual ~ 1L, cross_payer ~ 1L,
            TRUE ~ 0L)
        }
      )
  }

  result
}

#' Classify encounter rows into payer tiers (data.table variant)
#'
#' Data.table variant of classify_payer_tier() using keyed joins and fcase()
#' for significant performance gains on large datasets. Produces identical
#' output to the dplyr version -- same columns, same values, same types.
#'
#' Internally operates on data.table with reference semantics. Uses copy() at
#' entry to prevent mutation of caller's input (reference semantics defense).
#' Returns tibble for dplyr pipeline compatibility.
#'
#' @param df Data frame with columns: PAYER_TYPE_PRIMARY,
#'   PAYER_TYPE_SECONDARY, SOURCE
#' @param include_dual Logical. If TRUE, compute dual_eligible flag (default
#'   TRUE). R/60 and R/61 use TRUE; R/62 uses FALSE.
#' @param flm_override Logical. If TRUE, override tier to "Medicaid" when
#'   SOURCE == "FLM" (default FALSE). R/61 and R/62 use TRUE; R/60 uses FALSE
#'   (handles FLM in same-day resolution).
#' @return tibble with added columns: effective_payer, payer_category,
#'   tier, tier_rank, and optionally dual_eligible (same as dplyr version)
#'
#' @note Reference semantics defense: copy() wraps ensure_dt() at entry to
#'   prevent mutation of caller's input via data.table's := operator.
#' @note Phase 96 v3.0: Created as data.table variant for performance
#'   optimization. Callers switch in Phase 97/98; this phase only creates
#'   and validates.
#'
#' @examples
#' enc %>% classify_payer_tier_dt(include_dual = TRUE, flm_override = FALSE)
#'
classify_payer_tier_dt <- function(df, include_dual = TRUE, flm_override = FALSE) {

  # ==========================================================================
  # Step 1: Defensive copy (reference semantics defense)
  # ==========================================================================
  # copy() wraps ensure_dt() to prevent reference mutation of caller's input.
  # Without copy(), := operations below would modify df in caller's environment.
  dt <- copy(ensure_dt(df, name = "input", script_name = "classify_payer_tier_dt"))

  # ==========================================================================
  # Step 2: Explicit character coercion (factor input defense)
  # ==========================================================================
  # PCORnet data may load payer codes as factors. Factor-to-character joins
  # fail silently (factor levels don't match character keys). Coerce at entry.
  dt[, `:=`(
    PAYER_TYPE_PRIMARY = as.character(PAYER_TYPE_PRIMARY),
    PAYER_TYPE_SECONDARY = as.character(PAYER_TYPE_SECONDARY),
    SOURCE = as.character(SOURCE)
  )]

  # ==========================================================================
  # Step 3: Effective payer resolution via fcase()
  # ==========================================================================
  # Primary if valid (not NA, not empty/whitespace, not sentinel), else
  # secondary if valid, else NA. Matches dplyr version's case_when() logic.
  sentinels <- PAYER_MAPPING$sentinel_values
  dt[, effective_payer := fcase(
    !is.na(PAYER_TYPE_PRIMARY) & nchar(trimws(PAYER_TYPE_PRIMARY)) > 0 &
      !PAYER_TYPE_PRIMARY %in% sentinels,
    PAYER_TYPE_PRIMARY,
    !is.na(PAYER_TYPE_SECONDARY) & nchar(trimws(PAYER_TYPE_SECONDARY)) > 0 &
      !PAYER_TYPE_SECONDARY %in% sentinels,
    PAYER_TYPE_SECONDARY,
    default = NA_character_
  )]

  # ==========================================================================
  # Step 4: AMC 8-category mapping via keyed join
  # ==========================================================================
  # Update-join syntax: X[Y, on=, col := i.col] assigns payer_category from
  # the right table to matching rows in dt. Unmatched rows get NA (left join).
  amc_lookup <- get_lookup_dt("AMC_PAYER_LOOKUP")
  dt[amc_lookup, on = .(effective_payer = code), payer_category := i.payer_category]

  # ==========================================================================
  # Step 5: Prefix fallback for unmapped codes
  # ==========================================================================
  # When direct AMC lookup returns NA, use first digit of effective_payer
  # to assign payer category. Matches dplyr version's prefix_cat logic.
  dt[is.na(payer_category) & !is.na(effective_payer), payer_category := fcase(
    startsWith(effective_payer, "1"), "Medicare",
    startsWith(effective_payer, "2"), "Medicaid",
    startsWith(effective_payer, "5") | startsWith(effective_payer, "6"), "Private",
    startsWith(effective_payer, "3") | startsWith(effective_payer, "4"), "Other govt",
    startsWith(effective_payer, "7"), "Private",
    startsWith(effective_payer, "8"), "Uninsured",
    startsWith(effective_payer, "9"), "Other",
    default = "Other"
  )]

  # ==========================================================================
  # Step 6: Missing fallback
  # ==========================================================================
  # When effective_payer is NA (both primary and secondary invalid),
  # payer_category defaults to "Missing".
  dt[is.na(effective_payer), payer_category := "Missing"]

  # ==========================================================================
  # Step 7: Tier assignment via fcase (equivalent to CODE_TO_TIER)
  # ==========================================================================
  # 1:1 mapping from payer_category to tier. Same strings, same logic
  # as CODE_TO_TIER() function above.
  dt[, tier := fcase(
    payer_category == "Medicaid", "Medicaid",
    payer_category == "Medicare", "Medicare",
    payer_category == "Private", "Private",
    payer_category == "Other govt", "Other govt",
    payer_category == "Other", "Other",
    payer_category == "Self-pay", "Self-pay",
    payer_category == "Uninsured", "Uninsured",
    payer_category == "Missing", "Missing",
    default = "Missing"
  )]

  # ==========================================================================
  # Step 8: Special code override (93/14 -> Medicaid)
  # ==========================================================================
  # Codes 93 and 14 always override tier to Medicaid, regardless of
  # payer_category assignment. Replicates coalesce(case_when(...), tier)
  # from the dplyr version.
  dt[, tier := fcase(
    PAYER_TYPE_PRIMARY %in% c("93", "14"), "Medicaid",
    PAYER_TYPE_SECONDARY %in% c("93", "14"), "Medicaid",
    default = tier
  )]

  # ==========================================================================
  # Step 9: Conditional FLM source override (if flm_override == TRUE)
  # ==========================================================================
  # When enabled, encounters from FLM (Florida Medicaid) source get tier
  # overridden to Medicaid. Used by R/61 and R/62; R/60 handles FLM
  # in same-day resolution instead.
  if (flm_override) {
    dt[SOURCE == "FLM" & !is.na(SOURCE), tier := "Medicaid"]
  }

  # ==========================================================================
  # Step 10: Tier safety net (NA -> "Missing")
  # ==========================================================================
  # Any remaining NA tier values default to "Missing".
  dt[is.na(tier), tier := "Missing"]

  # ==========================================================================
  # Step 11: Tier rank assignment via keyed join on TIER_MAPPING
  # ==========================================================================
  # TIER_MAPPING data.table: payer_category (character key) -> tier (integer rank).
  # Join matches dt$tier (e.g., "Medicaid") to tier_lookup$payer_category
  # (e.g., "Medicaid"), assigns tier_lookup$tier (integer rank) to dt$tier_rank.
  tier_lookup <- get_lookup_dt("TIER_MAPPING")
  dt[tier_lookup, on = .(tier = payer_category), tier_rank := i.tier]
  dt[is.na(tier_rank), tier_rank := 8L]

  # ==========================================================================
  # Step 12: Conditional dual_eligible flag (if include_dual == TRUE)
  # ==========================================================================
  # Detects dual-eligible patients (Medicare + Medicaid) via:
  # 1. Specific dual-eligible codes (14, 141, 142)
  # 2. Cross-payer detection (primary/secondary from different systems)
  # sec_missing branch comes first in fcase() to short-circuit NA inputs
  # before startsWith() is evaluated on potentially NA PAYER_TYPE_SECONDARY.
  if (include_dual) {
    dual_codes <- PAYER_MAPPING$dual_eligible_codes
    dt[, dual_eligible := {
      sec_missing <- is.na(PAYER_TYPE_SECONDARY) |
                     nchar(trimws(PAYER_TYPE_SECONDARY)) == 0
      has_dual <- PAYER_TYPE_PRIMARY %in% dual_codes |
                  PAYER_TYPE_SECONDARY %in% dual_codes
      cross_payer <- (startsWith(PAYER_TYPE_PRIMARY, "1") &
                      startsWith(PAYER_TYPE_SECONDARY, "2")) |
                     (startsWith(PAYER_TYPE_PRIMARY, "2") &
                      startsWith(PAYER_TYPE_SECONDARY, "1"))
      fcase(
        sec_missing, 0L,
        has_dual, 1L,
        cross_payer, 1L,
        default = 0L
      )
    }]
  }

  # ==========================================================================
  # Step 13: Return tibble (dplyr pipeline compatibility)
  # ==========================================================================
  # Per D-04: return tibble for compatibility with R/60, R/61, R/62 callers
  # which use dplyr pipelines downstream.
  to_tibble_safe(dt, name = "result", script_name = "classify_payer_tier_dt")
}
