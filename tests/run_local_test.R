# ==============================================================================
# run_local_test.R -- End-to-end local pipeline integration test
# ==============================================================================
#
# Purpose:
#   Runs the full PCORnet pipeline locally against test fixtures to validate
#   environment detection, CSV loading, DuckDB ingest, and smoke test pass.
#   Measures total execution time against 2-minute target (TEST-04).
#
# Usage:
#   From project root in RStudio:
#     source("tests/run_local_test.R")
#
#   Or from command line:
#     Rscript tests/run_local_test.R
#
# Prerequisites:
#   - R with tidyverse, duckdb, DBI, vroom, glue packages installed
#   - tests/fixtures/ directory populated with 15 PCORnet CDM CSVs (Phase 84)
#   - Must be run from the project root directory (where R/ and tests/ are)
#
# Requirements: TEST-01, TEST-02, TEST-03, TEST-04, TEST-05
#
# ==============================================================================

cat(strrep("=", 70), "\n")
cat("LOCAL INTEGRATION TEST: Full Pipeline Validation\n")
cat(strrep("=", 70), "\n\n")

# Track overall timing
pipeline_start <- Sys.time()

# --------------------------------------------------------------------------
# STEP 1: Environment detection (R/00_config.R)
# --------------------------------------------------------------------------
cat("[Step 1/5] Sourcing R/00_config.R...\n")
step1_start <- Sys.time()

# Force clean environment for pcornet reload
if (exists("pcornet", envir = .GlobalEnv)) rm(pcornet, envir = .GlobalEnv)

source("R/00_config.R")

if (!IS_LOCAL) {
  stop(paste0(
    "ABORT: IS_LOCAL is FALSE. This test must run in local mode.\n",
    "  Current OS: ", Sys.info()["sysname"], "\n",
    "  Fix: Set R_TESTING_ENV=local in project-root .Renviron\n",
    "  Or: Run on a Windows machine (auto-detected as local)"
  ))
}

step1_time <- as.numeric(difftime(Sys.time(), step1_start, units = "secs"))
cat(sprintf("  Done (%.1fs) -- IS_LOCAL=%s, data_dir=%s\n\n",
            step1_time, IS_LOCAL, CONFIG$data_dir))

# --------------------------------------------------------------------------
# STEP 2: Load fixture CSVs (R/01_load_pcornet.R)
# --------------------------------------------------------------------------
cat("[Step 2/5] Sourcing R/01_load_pcornet.R (fixture CSV loading)...\n")
step2_start <- Sys.time()

source("R/01_load_pcornet.R")

step2_time <- as.numeric(difftime(Sys.time(), step2_start, units = "secs"))
tables_loaded <- sum(!sapply(pcornet, is.null))
total_rows <- sum(sapply(pcornet, function(x) if (!is.null(x)) nrow(x) else 0L))
cat(sprintf("  Done (%.1fs) -- %d tables loaded, %d total rows\n\n",
            step2_time, tables_loaded, total_rows))

# --------------------------------------------------------------------------
# STEP 3: DuckDB ingest (R/03_duckdb_ingest.R)
# --------------------------------------------------------------------------
cat("[Step 3/5] Sourcing R/03_duckdb_ingest.R (RDS -> DuckDB ingest)...\n")
step3_start <- Sys.time()

source("R/03_duckdb_ingest.R")

step3_time <- as.numeric(difftime(Sys.time(), step3_start, units = "secs"))
cat(sprintf("  Done (%.1fs) -- DuckDB at %s\n\n",
            step3_time, CONFIG$cache$duckdb_path))

# --------------------------------------------------------------------------
# STEP 4: DuckDB content validation
# --------------------------------------------------------------------------
cat("[Step 4/5] Validating DuckDB content...\n")
step4_start <- Sys.time()

val_errors <- character()

if (file.exists(CONFIG$cache$duckdb_path)) {
  con <- DBI::dbConnect(duckdb::duckdb(), CONFIG$cache$duckdb_path, read_only = TRUE)

  # Check table count
  db_tables <- DBI::dbListTables(con)
  if (length(db_tables) != 15) {
    val_errors <- c(val_errors,
      sprintf("Expected 15 DuckDB tables, found %d", length(db_tables)))
  }

  # Check fixture row counts
  expected_counts <- list(
    ENROLLMENT = 20L, DIAGNOSIS = 18L, ENCOUNTER = 19L,
    DEMOGRAPHIC = 20L, PRESCRIBING = 4L, PROCEDURES = 1L,
    DEATH = 1L, PROVIDER = 2L, CONDITION = 1L
  )

  for (tbl in names(expected_counts)) {
    if (tbl %in% db_tables) {
      actual <- DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM %s", tbl))$n
      if (actual != expected_counts[[tbl]]) {
        val_errors <- c(val_errors,
          sprintf("%s: expected %d rows, found %d", tbl, expected_counts[[tbl]], actual))
      }
    }
  }

  # Check edge case patients in DuckDB
  pt003_count <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM DIAGNOSIS WHERE ID = 'PT003' AND DX = 'C81.00'")$n
  if (pt003_count == 0) {
    val_errors <- c(val_errors, "PT003 NLPHL (C81.00) not found in DuckDB DIAGNOSIS")
  }

  pt012_count <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM PRESCRIBING WHERE ID = 'PT012'")$n
  if (pt012_count != 4) {
    val_errors <- c(val_errors,
      sprintf("PT012 ABVD: expected 4 prescribing rows, found %d", pt012_count))
  }

  DBI::dbDisconnect(con, shutdown = TRUE)
} else {
  val_errors <- c(val_errors, "DuckDB file not found after ingest")
}

step4_time <- as.numeric(difftime(Sys.time(), step4_start, units = "secs"))
if (length(val_errors) == 0) {
  cat(sprintf("  Done (%.1fs) -- All DuckDB validations passed\n\n", step4_time))
} else {
  cat(sprintf("  Done (%.1fs) -- %d validation errors:\n", step4_time, length(val_errors)))
  for (err in val_errors) cat(sprintf("    ERROR: %s\n", err))
  cat("\n")
}

# --------------------------------------------------------------------------
# STEP 5: Smoke test (R/88_smoke_test_comprehensive.R)
# --------------------------------------------------------------------------
cat("[Step 5/5] Sourcing R/88_smoke_test_comprehensive.R (full smoke test)...\n")
step5_start <- Sys.time()

# R/88 clears workspace with rm(list = ls()) at top, so save what we need
saved_pipeline_start <- pipeline_start
saved_step_times <- c(step1_time, step2_time, step3_time, step4_time)
saved_val_errors <- val_errors

source("R/88_smoke_test_comprehensive.R")

step5_time <- as.numeric(difftime(Sys.time(), step5_start, units = "secs"))

# Restore saved values (R/88 cleared the environment)
pipeline_start <- saved_pipeline_start
step_times <- saved_step_times
val_errors <- saved_val_errors

# --------------------------------------------------------------------------
# SUMMARY
# --------------------------------------------------------------------------
pipeline_end <- Sys.time()
total_seconds <- as.numeric(difftime(pipeline_end, pipeline_start, units = "secs"))

cat("\n", strrep("=", 70), "\n")
cat("LOCAL INTEGRATION TEST: SUMMARY\n")
cat(strrep("=", 70), "\n\n")

cat(sprintf("  Step 1 (config):     %6.1fs\n", step_times[1]))
cat(sprintf("  Step 2 (CSV load):   %6.1fs\n", step_times[2]))
cat(sprintf("  Step 3 (DuckDB):     %6.1fs\n", step_times[3]))
cat(sprintf("  Step 4 (validate):   %6.1fs\n", step_times[4]))
cat(sprintf("  Step 5 (smoke test): %6.1fs\n", step5_time))
cat(sprintf("  %-20s %6.1fs\n", "TOTAL:", total_seconds))
cat("\n")

# TEST-04: 2-minute performance target
if (total_seconds <= 120) {
  cat(sprintf("  PASS: Pipeline completed in %.1fs (under 2-minute target)\n", total_seconds))
} else {
  cat(sprintf("  WARNING: Pipeline took %.1fs (exceeded 2-minute target of 120s)\n", total_seconds))
}

# DuckDB validation results
if (length(val_errors) == 0) {
  cat("  PASS: All DuckDB content validations passed\n")
} else {
  cat(sprintf("  FAIL: %d DuckDB validation errors\n", length(val_errors)))
}

# Smoke test results (passed/failed from R/88 are in global env)
if (exists("passed") && exists("failed")) {
  cat(sprintf("  Smoke test: %d passed, %d failed\n", passed, failed))
}

cat("\n", strrep("=", 70), "\n")

# Exit with error if any failures
if (length(val_errors) > 0 || (exists("failed") && failed > 0)) {
  cat("RESULT: FAILED\n")
  if (!interactive()) quit(status = 1)
} else {
  cat("RESULT: ALL TESTS PASSED\n")
}
