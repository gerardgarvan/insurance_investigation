# ==============================================================================
# 98_validate_r28_migration.R -- Phase 98 R/28 migration parity validation
# ==============================================================================
#
# Purpose:
#   Validates R/28 output identical before/after Phase 98 keyed join migration.
#   Two modes:
#     1. Baseline capture: if no baseline exists, saves current as baseline
#     2. Comparison: if baseline exists, compares current vs baseline
#
# Usage:
#   1. BEFORE Phase 98: source("R/98_validate_r28_migration.R") (captures baseline)
#   2. AFTER Phase 98: Re-run R/28, then source("R/98_validate_r28_migration.R")
#
# Expected output:
#   Baseline mode: Saves baseline and exits
#   Comparison mode: Series of [PASS] / [FAIL] messages. All must show [PASS].
#
# Requirements:
#   - PERF-03: Named vector lookups eliminated (DRUG_GROUPINGS, CODE_SUBCATEGORY_MAP)
#   - PERF-04: R/28 structure validation (columns, order, types)
#   - VALID-01: Content parity (row-by-row match)
#
# ==============================================================================

source("R/00_config.R")
library(dplyr)
library(data.table)
library(glue)

# ==============================================================================
# Section 1: Setup
# ==============================================================================

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

message("\n======================================================================")
message("Phase 98: R/28 Migration Parity Validation")
message("======================================================================\n")

# ==============================================================================
# Section 2: Load current output
# ==============================================================================

message("--- Section 2: Load current output ---")

OUTPUT_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
BASELINE_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes_pre98_baseline.rds")

if (!file.exists(OUTPUT_RDS)) {
  stop(glue("ERROR: Output file not found: {OUTPUT_RDS}\nRun R/28 first to generate treatment_episodes.rds"))
}

current <- readRDS(OUTPUT_RDS)
message(sprintf("Loaded current output: %s rows, %s columns",
                format(nrow(current), big.mark = ","),
                ncol(current)))

# ==============================================================================
# Section 3: Baseline mode handling
# ==============================================================================

message("\n--- Section 3: Baseline mode handling ---")

if (!file.exists(BASELINE_RDS)) {
  message("BASELINE MODE: No baseline file found. Saving current output as baseline.")
  saveRDS(current, BASELINE_RDS)
  message(sprintf("Baseline saved to: %s", BASELINE_RDS))
  message("\nNEXT STEPS:")
  message("  1. Apply Phase 98 changes to R/28")
  message("  2. Re-run R/28_episode_classification.R")
  message("  3. Re-run this validation script (it will compare against baseline)")
  message("\nExiting with status 0 (baseline capture successful).")
  quit(status = 0L)
}

# Baseline exists - load and proceed to comparison
baseline <- readRDS(BASELINE_RDS)
message(sprintf("Loaded baseline: %s rows, %s columns",
                format(nrow(baseline), big.mark = ","),
                ncol(baseline)))

# ==============================================================================
# Section 4: Structure validation (PERF-04)
# ==============================================================================

message("\n--- Section 4: Structure validation (PERF-04) ---")

# Expected 24 columns (medication_name removed — drug_names from R/26 is canonical)
EXPECTED_COLS <- c(
  "patient_id", "treatment_type", "episode_number", "episode_start", "episode_stop",
  "episode_length_days", "distinct_dates_in_episode", "historical_flag",
  "triggering_codes", "encounter_ids", "drug_names",
  "cancer_category", "cancer_link_method", "is_hodgkin", "regimen_label",
  "triggering_code_description", "drug_group",
  "code_type", "source_table", "treatment_line",
  "sct_cross_use_flag", "is_sct_conditioning_context", "days_to_nearest_sct",
  "immuno_confidence"
)

check("Current output has 24 columns", ncol(current) == 24)
check("Baseline has 24 columns", ncol(baseline) == 24)
check("Current and baseline have same column names",
      identical(names(current), names(baseline)))
check("Column names match expected order",
      identical(names(current), EXPECTED_COLS))
check("Current and baseline have same row count",
      nrow(current) == nrow(baseline))

# Column type validation
message("\n  Checking column types...")
for (col in EXPECTED_COLS) {
  check(sprintf("Column type match: %s", col),
        identical(class(current[[col]]), class(baseline[[col]])))
}

# ==============================================================================
# Section 5: Content parity (VALID-01)
# ==============================================================================

message("\n--- Section 5: Content parity (VALID-01) ---")

# Sort both data frames to make comparison order-independent (per Phase 97 lesson)
message("\n  Sorting both data frames for order-independent comparison...")
current_sorted <- current %>%
  arrange(patient_id, treatment_type, episode_number)
baseline_sorted <- baseline %>%
  arrange(patient_id, treatment_type, episode_number)

message("  Comparing columns row-by-row...")
for (col in EXPECTED_COLS) {
  current_col <- current_sorted[[col]]
  baseline_col <- baseline_sorted[[col]]

  if (is.numeric(current_col) && is.numeric(baseline_col)) {
    # Numeric: use all.equal with tolerance for floating-point rounding
    col_match <- isTRUE(all.equal(current_col, baseline_col, tolerance = 1e-8))
  } else if (is.logical(current_col) && is.logical(baseline_col)) {
    # Logical: exact match
    col_match <- identical(current_col, baseline_col)
  } else {
    # Character/factor/date: coerce to character and compare
    col_match <- identical(as.character(current_col), as.character(baseline_col))
  }

  check(sprintf("Content match: %s", col), col_match)
}

# ==============================================================================
# Section 6: Key column spot checks
# ==============================================================================

message("\n--- Section 6: Key column spot checks ---")

# Check NA counts for columns that may have missingness
check("NA count match: drug_group",
      sum(is.na(current_sorted$drug_group)) == sum(is.na(baseline_sorted$drug_group)))
check("NA count match: triggering_code_description",
      sum(is.na(current_sorted$triggering_code_description)) == sum(is.na(baseline_sorted$triggering_code_description)))
check("NA count match: treatment_line",
      sum(is.na(current_sorted$treatment_line)) == sum(is.na(baseline_sorted$treatment_line)))
check("NA count match: sct_cross_use_flag",
      sum(is.na(current_sorted$sct_cross_use_flag)) == sum(is.na(baseline_sorted$sct_cross_use_flag)))
check("NA count match: immuno_confidence",
      sum(is.na(current_sorted$immuno_confidence)) == sum(is.na(baseline_sorted$immuno_confidence)))

# ==============================================================================
# Section 7: Named vector elimination verification (PERF-03)
# ==============================================================================

message("\n--- Section 7: Named vector elimination verification (PERF-03) ---")

# Check R/28 source code for named vector lookups
r28_path <- "R/28_episode_classification.R"
if (file.exists(r28_path)) {
  r28_lines <- readLines(r28_path)

  # Check for DRUG_GROUPINGS[ pattern
  drug_matches <- grep("DRUG_GROUPINGS\\[", r28_lines, value = FALSE)
  check("R/28 has zero DRUG_GROUPINGS[ lookups", length(drug_matches) == 0)

  # Check for CODE_SUBCATEGORY_MAP[ pattern
  subcategory_matches <- grep("CODE_SUBCATEGORY_MAP\\[", r28_lines, value = FALSE)
  check("R/28 has zero CODE_SUBCATEGORY_MAP[ lookups", length(subcategory_matches) == 0)

  # Check for sapply(triggering_codes pattern (should be replaced with data.table)
  sapply_matches <- grep("sapply\\(triggering_codes", r28_lines, value = FALSE)
  check("R/28 has zero sapply(triggering_codes patterns", length(sapply_matches) == 0)
} else {
  check("R/28 file exists", FALSE)
}

# Check all 7 sweep files (55-58 + 88)
sweep_files <- c(
  "R/55_cancer_summary_table_pre_post.R",
  "R/56_gantt_chart_csv_export.R",
  "R/57_drug_groupings_tables.R",
  "R/58_gantt_v2_export.R",
  "R/88_smoke_test_comprehensive.R"
)

message("\n  Checking sweep files for DRUG_GROUPINGS[ pattern...")
for (file_path in sweep_files) {
  if (file.exists(file_path)) {
    lines <- readLines(file_path)
    drug_matches <- grep("DRUG_GROUPINGS\\[", lines, value = FALSE)
    check(sprintf("%s has zero DRUG_GROUPINGS[ lookups", basename(file_path)),
          length(drug_matches) == 0)
  } else {
    check(sprintf("%s exists", basename(file_path)), FALSE)
  }
}

# Check applicable sweep files for CODE_SUBCATEGORY_MAP[ pattern
# (56, 57, 58 use subcategory mapping; 55, 88 do not)
subcategory_files <- c(
  "R/56_gantt_chart_csv_export.R",
  "R/57_drug_groupings_tables.R",
  "R/58_gantt_v2_export.R"
)

message("\n  Checking sweep files for CODE_SUBCATEGORY_MAP[ pattern...")
for (file_path in subcategory_files) {
  if (file.exists(file_path)) {
    lines <- readLines(file_path)
    subcategory_matches <- grep("CODE_SUBCATEGORY_MAP\\[", lines, value = FALSE)
    check(sprintf("%s has zero CODE_SUBCATEGORY_MAP[ lookups", basename(file_path)),
          length(subcategory_matches) == 0)
  } else {
    check(sprintf("%s exists", basename(file_path)), FALSE)
  }
}

# Check utils_xlsx_lookups.R (uses DRUG_GROUPINGS and CODE_SUBCATEGORY_MAP)
utils_path <- "R/utils/utils_xlsx_lookups.R"
if (file.exists(utils_path)) {
  utils_lines <- readLines(utils_path)

  drug_matches <- grep("DRUG_GROUPINGS\\[", utils_lines, value = FALSE)
  check("utils_xlsx_lookups.R has zero DRUG_GROUPINGS[ lookups",
        length(drug_matches) == 0)

  subcategory_matches <- grep("CODE_SUBCATEGORY_MAP\\[", utils_lines, value = FALSE)
  check("utils_xlsx_lookups.R has zero CODE_SUBCATEGORY_MAP[ lookups",
        length(subcategory_matches) == 0)
} else {
  check("utils_xlsx_lookups.R exists", FALSE)
}

# ==============================================================================
# Section 8: Summary
# ==============================================================================

message(sprintf("\n=== VALIDATION SUMMARY ==="))
message(sprintf("Total checks: %d", pass_count + fail_count))
message(sprintf("Passed: %d", pass_count))
message(sprintf("Failed: %d", fail_count))

if (fail_count > 0) {
  message(sprintf("\nFAILURES detected: %d checks failed. Investigate mismatches above.", fail_count))
  message("\n======================================================================")
  message("END OF Phase 98 R/28 Migration Parity Validation (FAILED)")
  message("======================================================================")
  quit(status = 1L)
} else {
  message("\nAll checks passed! R/28 data.table migration produces identical output.")
  message("Named vector lookups successfully eliminated across all 8 files.")
  message("\n======================================================================")
  message("END OF Phase 98 R/28 Migration Parity Validation (SUCCESS)")
  message("======================================================================")
}
