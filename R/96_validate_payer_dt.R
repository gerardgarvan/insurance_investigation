# ==============================================================================
# 96_validate_payer_dt.R -- Phase 96 payer classification parity validation
# ==============================================================================
#
# Purpose:
#   Validates that classify_payer_tier_dt() produces identical output to
#   classify_payer_tier() across all parameter combinations and edge cases.
#   Runs both functions on test data and compares output columns row-by-row.
#
# Usage:
#   source("R/96_validate_payer_dt.R")
#
# Expected output:
#   Series of [PASS] / [FAIL] messages. All must show [PASS].
#
# Requirements:
#   - PAYER-01: classify_payer_tier_dt() function exists
#   - PAYER-02: Output parity with classify_payer_tier()
#
# ==============================================================================

source("R/00_config.R")

pass_count <- 0L
fail_count <- 0L

check <- function(description, condition) {
  if (isTRUE(condition)) {
    message(sprintf("[PASS] %s", description))
    pass_count <<- pass_count + 1L
  } else {
    message(sprintf("[FAIL] %s", description))
    fail_count <<- fail_count + 1L
  }
}

# ==============================================================================
# Section 1: Function existence checks (PAYER-01)
# ==============================================================================

message("")
message("--- Section 1: Function existence checks (PAYER-01) ---")

check("classify_payer_tier_dt exists", exists("classify_payer_tier_dt"))
check("classify_payer_tier_dt is a function", is.function(classify_payer_tier_dt))

# Check parameter count and names
dt_params <- formals(classify_payer_tier_dt)
check("classify_payer_tier_dt has 3 parameters",
      length(dt_params) == 3)
check("classify_payer_tier_dt params are (df, include_dual, flm_override)",
      identical(names(dt_params), c("df", "include_dual", "flm_override")))

# Check defaults match dplyr version
dplyr_params <- formals(classify_payer_tier)
check("include_dual default matches dplyr version (TRUE)",
      identical(dt_params$include_dual, dplyr_params$include_dual))
check("flm_override default matches dplyr version (FALSE)",
      identical(dt_params$flm_override, dplyr_params$flm_override))

# ==============================================================================
# Section 2: Fixture data construction
# ==============================================================================
# Build comprehensive test tibble covering all edge cases.
# Codes verified against AMC_PAYER_LOOKUP in R/00_config.R:
#   "219" -> "Medicaid" (direct lookup)
#   "11"  -> "Medicare" (direct lookup)
#   "511" -> "Private"  (direct lookup)

message("")
message("--- Section 2: Fixture data construction ---")

fixture <- tibble::tibble(
  PAYER_TYPE_PRIMARY = c(
    "219",    # Row 1:  Direct AMC lookup: Medicaid code
    "11",     # Row 2:  Direct AMC lookup: Medicare code
    "511",    # Row 3:  Direct AMC lookup: Private code
    "93",     # Row 4:  Special code override -> Medicaid
    "14",     # Row 5:  Special code override -> Medicaid (dual_eligible_codes member)
    "NI",     # Row 6:  Sentinel value -> fall to secondary
    "UN",     # Row 7:  Sentinel value -> fall to secondary
    "",       # Row 8:  Empty string -> fall to secondary
    NA_character_,  # Row 9:  NA primary -> fall to secondary
    "1XX",    # Row 10: Prefix fallback: starts with "1" -> Medicare
    "2YY",    # Row 11: Prefix fallback: starts with "2" -> Medicaid
    "5ZZ",    # Row 12: Prefix fallback: starts with "5" -> Private
    "3AA",    # Row 13: Prefix fallback: starts with "3" -> Other govt
    "8BB",    # Row 14: Prefix fallback: starts with "8" -> Uninsured
    "9CC",    # Row 15: Prefix fallback: starts with "9" -> Other
    NA_character_,  # Row 16: Both NA -> Missing
    "141",    # Row 17: Dual-eligible code (in PAYER_MAPPING$dual_eligible_codes)
    "11",     # Row 18: Cross-payer: Medicare primary + Medicaid secondary
    "219"     # Row 19: Cross-payer: Medicaid primary + Medicare secondary
  ),
  PAYER_TYPE_SECONDARY = c(
    NA_character_,  # Row 1:  No secondary
    "219",    # Row 2:  Secondary present but primary valid (ignored)
    NA_character_,  # Row 3:  No secondary
    NA_character_,  # Row 4:  No secondary (93 override)
    NA_character_,  # Row 5:  No secondary (14 override)
    "219",    # Row 6:  Sentinel primary -> use secondary: Medicaid
    "511",    # Row 7:  Sentinel primary -> use secondary: Private
    "11",     # Row 8:  Empty primary -> use secondary: Medicare
    "219",    # Row 9:  NA primary -> use secondary: Medicaid
    NA_character_,  # Row 10: No secondary (prefix fallback)
    NA_character_,  # Row 11: No secondary (prefix fallback)
    NA_character_,  # Row 12: No secondary (prefix fallback)
    NA_character_,  # Row 13: No secondary (prefix fallback)
    NA_character_,  # Row 14: No secondary (prefix fallback)
    NA_character_,  # Row 15: No secondary (prefix fallback)
    NA_character_,  # Row 16: Both missing -> Missing
    "219",    # Row 17: Secondary for dual-eligible test
    "219",    # Row 18: Secondary: Medicaid (cross-payer with Medicare primary)
    "11"      # Row 19: Secondary: Medicare (cross-payer with Medicaid primary)
  ),
  SOURCE = c(
    "ENC", "ENC", "ENC", "ENC", "ENC",
    "ENC", "ENC", "ENC", "ENC", "ENC",
    "ENC", "ENC", "ENC", "ENC", "ENC",
    "ENC", "ENC", "ENC", "FLM"   # Row 19: FLM source for override test
  )
)

check("Fixture has 19 rows", nrow(fixture) == 19)
check("Fixture has 3 columns (PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY, SOURCE)",
      ncol(fixture) == 3 &&
      all(c("PAYER_TYPE_PRIMARY", "PAYER_TYPE_SECONDARY", "SOURCE") %in% names(fixture)))

message(sprintf("  Fixture constructed: %d rows x %d columns", nrow(fixture), ncol(fixture)))

# ==============================================================================
# Section 3: Parity test -- default parameters (include_dual=TRUE, flm_override=FALSE)
# ==============================================================================

message("")
message("--- Section 3: Parity test (include_dual=TRUE, flm_override=FALSE) ---")

result_dplyr <- classify_payer_tier(fixture, include_dual = TRUE, flm_override = FALSE)
result_dt <- classify_payer_tier_dt(fixture, include_dual = TRUE, flm_override = FALSE)

check("Row count matches", nrow(result_dplyr) == nrow(result_dt))
check("Column count matches", ncol(result_dplyr) == ncol(result_dt))
check("Column names identical",
      all(sort(names(result_dplyr)) == sort(names(result_dt))))

# Compare each output column row-by-row
# Use a helper that handles NA comparison correctly
cols_to_compare <- c("effective_payer", "payer_category", "tier", "tier_rank", "dual_eligible")
for (col in cols_to_compare) {
  if (col %in% names(result_dplyr) && col %in% names(result_dt)) {
    dplyr_col <- result_dplyr[[col]]
    dt_col <- result_dt[[col]]
    # identical() handles NA comparison correctly (NA == NA -> TRUE)
    # unname() strips vector name attributes (dplyr's named-vector lookups produce
    # named columns; data.table keyed joins produce unnamed columns -- values are
    # identical but names differ, causing identical() to fail)
    is_match <- identical(unname(dplyr_col), unname(dt_col))
    check(sprintf("Column '%s' matches row-by-row (default params)", col), is_match)
    if (!is_match) {
      # Log which rows differ for debugging
      for (i in seq_along(dplyr_col)) {
        if (!identical(unname(dplyr_col[i]), unname(dt_col[i]))) {
          message(sprintf("  Row %d mismatch: dplyr='%s', dt='%s'",
                          i, as.character(dplyr_col[i]), as.character(dt_col[i])))
        }
      }
    }
  } else {
    check(sprintf("Column '%s' exists in both outputs", col), FALSE)
  }
}

# ==============================================================================
# Section 4: Parity test -- include_dual=TRUE, flm_override=TRUE
# ==============================================================================

message("")
message("--- Section 4: Parity test (include_dual=TRUE, flm_override=TRUE) ---")

result_dplyr_flm <- classify_payer_tier(fixture, include_dual = TRUE, flm_override = TRUE)
result_dt_flm <- classify_payer_tier_dt(fixture, include_dual = TRUE, flm_override = TRUE)

check("Row count matches (flm_override=TRUE)",
      nrow(result_dplyr_flm) == nrow(result_dt_flm))
check("Column count matches (flm_override=TRUE)",
      ncol(result_dplyr_flm) == ncol(result_dt_flm))

# Row 19 should have tier="Medicaid" due to FLM override
check("FLM row (row 19) has tier='Medicaid' in dplyr output",
      result_dplyr_flm$tier[19] == "Medicaid")
check("FLM row (row 19) has tier='Medicaid' in dt output",
      result_dt_flm$tier[19] == "Medicaid")

# Compare all output columns with FLM override
cols_flm <- c("effective_payer", "payer_category", "tier", "tier_rank", "dual_eligible")
for (col in cols_flm) {
  if (col %in% names(result_dplyr_flm) && col %in% names(result_dt_flm)) {
    is_match <- identical(unname(result_dplyr_flm[[col]]), unname(result_dt_flm[[col]]))
    check(sprintf("Column '%s' matches row-by-row (flm_override=TRUE)", col), is_match)
    if (!is_match) {
      for (i in seq_along(result_dplyr_flm[[col]])) {
        if (!identical(unname(result_dplyr_flm[[col]][i]), unname(result_dt_flm[[col]][i]))) {
          message(sprintf("  Row %d mismatch: dplyr='%s', dt='%s'",
                          i,
                          as.character(result_dplyr_flm[[col]][i]),
                          as.character(result_dt_flm[[col]][i])))
        }
      }
    }
  }
}

# ==============================================================================
# Section 5: Parity test -- include_dual=FALSE, flm_override=TRUE
# ==============================================================================

message("")
message("--- Section 5: Parity test (include_dual=FALSE, flm_override=TRUE) ---")

result_dplyr_nodual <- classify_payer_tier(fixture, include_dual = FALSE, flm_override = TRUE)
result_dt_nodual <- classify_payer_tier_dt(fixture, include_dual = FALSE, flm_override = TRUE)

check("Row count matches (include_dual=FALSE)",
      nrow(result_dplyr_nodual) == nrow(result_dt_nodual))

# dual_eligible column should NOT exist
check("dual_eligible column absent in dplyr output (include_dual=FALSE)",
      !("dual_eligible" %in% names(result_dplyr_nodual)))
check("dual_eligible column absent in dt output (include_dual=FALSE)",
      !("dual_eligible" %in% names(result_dt_nodual)))

# Compare non-dual columns
cols_nodual <- c("effective_payer", "payer_category", "tier", "tier_rank")
for (col in cols_nodual) {
  if (col %in% names(result_dplyr_nodual) && col %in% names(result_dt_nodual)) {
    is_match <- identical(unname(result_dplyr_nodual[[col]]), unname(result_dt_nodual[[col]]))
    check(sprintf("Column '%s' matches row-by-row (include_dual=FALSE)", col), is_match)
    if (!is_match) {
      for (i in seq_along(result_dplyr_nodual[[col]])) {
        if (!identical(unname(result_dplyr_nodual[[col]][i]), unname(result_dt_nodual[[col]][i]))) {
          message(sprintf("  Row %d mismatch: dplyr='%s', dt='%s'",
                          i,
                          as.character(result_dplyr_nodual[[col]][i]),
                          as.character(result_dt_nodual[[col]][i])))
        }
      }
    }
  }
}

# ==============================================================================
# Section 6: Reference semantics safety test
# ==============================================================================

message("")
message("--- Section 6: Reference semantics safety test ---")

fixture_copy <- tibble::tibble(
  PAYER_TYPE_PRIMARY = c("219", "11"),
  PAYER_TYPE_SECONDARY = c(NA_character_, NA_character_),
  SOURCE = c("ENC", "ENC")
)
original_ncol <- ncol(fixture_copy)
original_names <- names(fixture_copy)
result_ref <- classify_payer_tier_dt(fixture_copy)
check("Input not mutated (ncol unchanged)", ncol(fixture_copy) == original_ncol)
check("Input not mutated (no new columns)",
      !("effective_payer" %in% names(fixture_copy)))
check("Input not mutated (column names unchanged)",
      identical(names(fixture_copy), original_names))

# ==============================================================================
# Section 7: Factor input defense test
# ==============================================================================

message("")
message("--- Section 7: Factor input defense test ---")

fixture_factor <- fixture
fixture_factor$PAYER_TYPE_PRIMARY <- as.factor(fixture_factor$PAYER_TYPE_PRIMARY)
fixture_factor$PAYER_TYPE_SECONDARY <- as.factor(fixture_factor$PAYER_TYPE_SECONDARY)
result_factor <- classify_payer_tier_dt(fixture_factor, include_dual = TRUE, flm_override = FALSE)
result_char <- classify_payer_tier_dt(fixture, include_dual = TRUE, flm_override = FALSE)
check("Factor input produces same payer_category as character input",
      identical(result_factor$payer_category, result_char$payer_category))
check("Factor input produces same tier as character input",
      identical(result_factor$tier, result_char$tier))
check("Factor input produces same tier_rank as character input",
      identical(result_factor$tier_rank, result_char$tier_rank))
check("Factor input produces same dual_eligible as character input",
      identical(result_factor$dual_eligible, result_char$dual_eligible))

# ==============================================================================
# Section 8: Return type verification
# ==============================================================================

message("")
message("--- Section 8: Return type verification ---")

result_type <- classify_payer_tier_dt(fixture)
check("Return type is tibble", tibble::is_tibble(result_type))
check("Return type is NOT data.table", !data.table::is.data.table(result_type))

# ==============================================================================
# Section 9: Summary
# ==============================================================================

message("")
message(sprintf("========================================"))
message(sprintf("Phase 96 Validation: %d PASS, %d FAIL", pass_count, fail_count))
if (fail_count == 0) {
  message("All checks passed -- classify_payer_tier_dt() validated for Phase 97")
} else {
  message(sprintf("WARNING: %d check(s) failed -- review output above", fail_count))
}
message(sprintf("========================================"))
