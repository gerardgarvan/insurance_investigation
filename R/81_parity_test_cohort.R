# ==============================================================================
# 81_parity_test_cohort.R -- RDS vs DuckDB cohort parity verification
# ==============================================================================
#
# Purpose:
#   Full cohort build parity verification: builds complete HL cohort using RDS
#   backend and DuckDB backend, compares results via waldo::compare(). WHY
#   waldo::compare over identical(): waldo shows detailed diffs, not just TRUE/FALSE
#   -- critical for debugging parity failures.
#
# Inputs:
#   - Full PCORnet CDM data
#
# Outputs:
#   - Console output (PASS/FAIL with diff details)
#
# Dependencies:
#   - R/00_config.R, R/01_load_pcornet.R, R/14_build_cohort.R
#
# Requirements:
#   - DBCOH-02
#
# Usage:
#   source("R/81_parity_test_cohort.R")
#
# ==============================================================================

library(dplyr)
library(glue)
library(waldo)

message("\n", strrep("=", 70))
message("PARITY TEST: RDS vs DuckDB Cohort Build")
message(strrep("=", 70))

# Record start time
test_start <- Sys.time()

# ==============================================================================
# RDS BASELINE RUN (D-07)
# ==============================================================================

message("\n--- Running RDS baseline ---")
USE_DUCKDB <<- FALSE

# Clear any prior cohort artifacts
if (exists("hl_cohort")) rm(hl_cohort)
if (exists("attrition_log")) rm(attrition_log)

# Source config first to ensure pcornet list is loaded
source("R/00_config.R")
n # ==============================================================================
# SECTION 1: SETUP ----
# ==============================================================================
source("R/01_load_pcornet.R") # Loads pcornet$ list

# Now run the cohort build pipeline
source("R/14_build_cohort.R")

cohort_rds <- hl_cohort
attrition_rds <- attrition_log
message(glue("RDS cohort: {nrow(cohort_rds)} rows, {ncol(cohort_rds)} cols"))
message(glue("RDS attrition log: {nrow(attrition_rds)} steps"))

# ==============================================================================
# DUCKDB RUN
# ==============================================================================

message("\n--- Running DuckDB backend ---")
USE_DUCKDB <<- TRUE

# Open DuckDB connection
if (!exists("pcornet_con", envir = .GlobalEnv)) {
  source("R/utils/utils_duckdb.R") # Load DuckDB utilities
  open_pcornet_con()
}

# Clear cohort artifacts
if (exists("hl_cohort")) rm(hl_cohort)
if (exists("attrition_log")) rm(attrition_log)

# Run the cohort build pipeline under DuckDB backend
source("R/14_build_cohort.R")

cohort_ddb <- hl_cohort
attrition_ddb <- attrition_log
message(glue("DuckDB cohort: {nrow(cohort_ddb)} rows, {ncol(cohort_ddb)} cols"))
message(glue("DuckDB attrition log: {nrow(attrition_ddb)} steps"))

# ==============================================================================
# TYPE COERCION (D-08)
# ==============================================================================

message("\n--- Type coercion (D-08) ---")

coerce_types <- function(ddb_df, rds_df) {
  result <- ddb_df
  coercions <- character(0)

  for (col in names(result)) {
    if (col %in% names(rds_df)) {
      rds_class <- class(rds_df[[col]])[1]
      ddb_class <- class(result[[col]])[1]

      if (rds_class == "integer" && ddb_class == "numeric") {
        result[[col]] <- as.integer(result[[col]])
        coercions <- c(coercions, glue("{col}: numeric -> integer"))
      } else if (rds_class == "Date" && ddb_class == "POSIXct") {
        result[[col]] <- as.Date(result[[col]])
        coercions <- c(coercions, glue("{col}: POSIXct -> Date"))
      }
    }
  }

  if (length(coercions) > 0) {
    message("Coercions applied:")
    for (c in coercions) {
      message(glue("  {c}"))
    }
  } else {
    message("No type coercions needed")
  }

  result
}

cohort_ddb_coerced <- coerce_types(cohort_ddb, cohort_rds)
attrition_ddb_coerced <- coerce_types(attrition_ddb, attrition_rds)

# ==============================================================================
# ROW ORDER NORMALIZATION (Pitfall 5)
# ==============================================================================

message("\n--- Sorting for row order normalization ---")

cohort_rds_sorted <- cohort_rds %>% arrange(ID)
cohort_ddb_sorted <- cohort_ddb_coerced %>% arrange(ID)

# Attrition log has no ID; sort by step_name
attrition_rds_sorted <- attrition_rds %>% arrange(step_name)
attrition_ddb_sorted <- attrition_ddb_coerced %>% arrange(step_name)

# ==============================================================================
# THREE-LEVEL PARITY CHECK (D-09)
# ==============================================================================

message("\n--- Three-level parity check (D-09) ---")

# Level 1: Row count
check_1_cohort <- nrow(cohort_rds) == nrow(cohort_ddb)
check_1_attrition <- nrow(attrition_rds) == nrow(attrition_ddb)

message(glue("Level 1 - Row count:"))
message(glue("  Cohort: {ifelse(check_1_cohort, 'PASS', 'FAIL')} ({nrow(cohort_rds)} vs {nrow(cohort_ddb)})"))
message(glue("  Attrition: {ifelse(check_1_attrition, 'PASS', 'FAIL')} ({nrow(attrition_rds)} vs {nrow(attrition_ddb)})"))

# Level 2: PATID set equality
check_2_rds_only <- setdiff(cohort_rds$ID, cohort_ddb$ID)
check_2_ddb_only <- setdiff(cohort_ddb$ID, cohort_rds$ID)
check_2 <- length(check_2_rds_only) == 0 && length(check_2_ddb_only) == 0

message(glue("\nLevel 2 - PATID set equality: {ifelse(check_2, 'PASS', 'FAIL')}"))
if (!check_2) {
  message(glue("  In RDS only: {length(check_2_rds_only)} IDs"))
  message(glue("  In DuckDB only: {length(check_2_ddb_only)} IDs"))
  if (length(check_2_rds_only) > 0 && length(check_2_rds_only) <= 10) {
    message(glue("    RDS-only IDs: {paste(check_2_rds_only, collapse=', ')}"))
  }
  if (length(check_2_ddb_only) > 0 && length(check_2_ddb_only) <= 10) {
    message(glue("    DuckDB-only IDs: {paste(check_2_ddb_only, collapse=', ')}"))
  }
}

# Level 3: Structural equality (waldo::compare)
message("\nLevel 3 - Structural equality (waldo::compare):")

diff_cohort <- waldo::compare(cohort_rds_sorted, cohort_ddb_sorted, tolerance = 1e-10)
check_3_cohort <- length(diff_cohort) == 0

message(glue("  Cohort: {ifelse(check_3_cohort, 'PASS', 'FAIL')}"))
if (!check_3_cohort) {
  message("  Cohort differences:")
  print(diff_cohort)
}

diff_attrition <- waldo::compare(attrition_rds_sorted, attrition_ddb_sorted, tolerance = 1e-10)
check_3_attrition <- length(diff_attrition) == 0

message(glue("  Attrition: {ifelse(check_3_attrition, 'PASS', 'FAIL')}"))
if (!check_3_attrition) {
  message("  Attrition differences:")
  print(diff_attrition)
}

# ==============================================================================
# RDS REGRESSION CHECK
# ==============================================================================

message("\n--- RDS Regression Check ---")
USE_DUCKDB <<- FALSE
message("USE_DUCKDB = FALSE: pipeline executes without error (verified by completing the RDS baseline run above)")

# ==============================================================================
# CLEANUP
# ==============================================================================

if (exists("pcornet_con", envir = .GlobalEnv)) {
  close_pcornet_con()
}
USE_DUCKDB <<- FALSE # Restore default

# ==============================================================================
# SUMMARY
# ==============================================================================

test_end <- Sys.time()
test_duration <- difftime(test_end, test_start, units = "secs")

message("\n", strrep("=", 70))
message("PARITY TEST RESULTS")
message(strrep("=", 70))
message(glue("Test duration: {round(test_duration, 1)} seconds"))
message("")
message(glue("Level 1 - Row count: cohort {ifelse(check_1_cohort, 'PASS', 'FAIL')} ({nrow(cohort_rds)} vs {nrow(cohort_ddb)})"))
message(glue("Level 1 - Row count: attrition {ifelse(check_1_attrition, 'PASS', 'FAIL')} ({nrow(attrition_rds)} vs {nrow(attrition_ddb)})"))
message(glue("Level 2 - PATID set: {ifelse(check_2, 'PASS', 'FAIL')}"))
if (!check_2) {
  message(glue("  In RDS only: {length(check_2_rds_only)} IDs"))
  message(glue("  In DuckDB only: {length(check_2_ddb_only)} IDs"))
}
message(glue("Level 3 - Structural: cohort {ifelse(check_3_cohort, 'PASS', 'FAIL')}"))
message(glue("Level 3 - Structural: attrition {ifelse(check_3_attrition, 'PASS', 'FAIL')}"))

all_pass <- check_1_cohort && check_1_attrition && check_2 && check_3_cohort && check_3_attrition
message("")
message(glue("OVERALL: {ifelse(all_pass, 'ALL CHECKS PASSED', 'SOME CHECKS FAILED')}"))
message(strrep("=", 70))

# Return result invisibly for programmatic use
invisible(list(
  all_pass = all_pass,
  # ==============================================================================
  # SECTION 2: OUTPUT ----
  # ==============================================================================

  check_1_cohort = check_1_cohort,
  check_1_attrition = check_1_attrition,
  check_2_patid_set = check_2,
  check_3_cohort = check_3_cohort,
  check_3_attrition = check_3_attrition,
  cohort_rds_nrow = nrow(cohort_rds),
  cohort_ddb_nrow = nrow(cohort_ddb),
  rds_only_count = length(check_2_rds_only),
  ddb_only_count = length(check_2_ddb_only),
  duration_secs = as.numeric(test_duration)
))
