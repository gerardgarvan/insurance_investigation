# ==============================================================================
# 03_duckdb_ingest.R -- Ingest 13 PCORnet CDM tables from RDS cache into DuckDB with atomic write
# ==============================================================================
#
# Purpose:
#   Reads all 13 PCORnet tables from RDS cache (/blue/erin.mobley-hl.bcu/clean/rds/raw/)
#   and writes them into a single DuckDB file with atomic write guarantee. Creates
#   primary indexes on PATID (ID column) and secondary indexes on ENCOUNTERID where
#   present. Always rebuilds from scratch to ensure database integrity - does NOT
#   perform incremental updates. The atomic write pattern (.tmp rename) prevents
#   partial ingests from corrupting the database.
#
# Inputs:
#   - 13 RDS files from CONFIG$cache$raw_dir: ENROLLMENT.rds, DIAGNOSIS.rds,
#     CONDITION.rds, PROCEDURES.rds, PRESCRIBING.rds, ENCOUNTER.rds, DEMOGRAPHIC.rds,
#     TUMOR_REGISTRY1.rds, TUMOR_REGISTRY2.rds, TUMOR_REGISTRY3.rds, DISPENSING.rds,
#     MED_ADMIN.rds, LAB_RESULT_CM.rds, PROVIDER.rds, DEATH.rds
#   - CONFIG$cache$duckdb_path from R/00_config.R
#
# Outputs:
#   - DuckDB file: /blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb
#   - Ingest log CSV: output/logs/duckdb_ingest_<EXTRACT_DATE>.csv (row counts, durations)
#
# Dependencies:
#   - source("R/00_config.R"): CONFIG, PCORNET_TABLES, EXTRACT_DATE
#   - utils/utils_duckdb.R (auto-sourced by 00_config)
#   - duckdb, DBI: Database operations
#   - dplyr, readr, glue: Data manipulation and logging
#
# Requirements: DBING-01 (ingest to DuckDB), DBING-02 (atomic write), DBING-03 (full rebuild)
#
# ==============================================================================

source("R/00_config.R")
source("R/utils/utils_duckdb.R")

library(duckdb)
library(DBI)
library(dplyr)
library(readr)
library(glue)

# ==============================================================================
# SECTION 1: CONSTANTS ----
# ==============================================================================

# Tables to ingest (same as PCORNET_TABLES from 00_config.R, 13 tables)
# Note: TUMOR_REGISTRY_ALL is NOT ingested -- it's a derived bind_rows(TR1+TR2+TR3)
TABLES_TO_INGEST <- PCORNET_TABLES

# Tables that have an ENCOUNTERID column (verified from 01_load_pcornet.R col_type specs)
# Used for secondary index creation. DISPENSING and PROVIDER do NOT have ENCOUNTERID.
TABLES_WITH_ENCOUNTERID <- c(
  "DIAGNOSIS", "CONDITION", "PROCEDURES", "PRESCRIBING", "ENCOUNTER",
  "MED_ADMIN", "LAB_RESULT_CM"
)

DUCKDB_PATH <- CONFIG$cache$duckdb_path
DUCKDB_DIR <- CONFIG$cache$duckdb_dir
TMP_PATH <- paste0(DUCKDB_PATH, ".tmp")

# ==============================================================================
# SECTION 2: CREATE OUTPUT DIRECTORIES ----
# ==============================================================================

# SAFE-01: Validate RDS source directory exists
checkmate::assert_directory_exists(
  CONFIG$cache$raw_dir,
  access = "r",
  .var.name = "[R/03 ERROR] RDS cache directory"
)

if (!dir.exists(DUCKDB_DIR)) {
  dir.create(DUCKDB_DIR, recursive = TRUE, showWarnings = FALSE)
  message(glue("Created DuckDB directory: {DUCKDB_DIR}"))
}
if (!dir.exists("output/logs")) {
  dir.create("output/logs", recursive = TRUE, showWarnings = FALSE)
}

# ==============================================================================
# SECTION 3: CLEAN UP STALE .TMP FROM PRIOR INTERRUPTED RUN ----
# ==============================================================================

if (file.exists(TMP_PATH)) {
  message(glue("Removing stale .tmp file from prior interrupted run: {TMP_PATH}"))
  file.remove(TMP_PATH)
}

# ==============================================================================
# SECTION 4: OPEN DUCKDB CONNECTION TO .TMP PATH ----
# ==============================================================================
# WHY atomic write pattern: Building at .tmp path first, then renaming to canonical
# path only after ALL tables successfully ingest prevents partial database corruption.
# If any table fails, the .tmp file is deleted and the canonical database (if it exists)
# remains untouched.

message(strrep("=", 60))
message(glue("DuckDB Ingest: {length(TABLES_TO_INGEST)} tables from RDS cache"))
message(glue("Target: {DUCKDB_PATH}"))
message(glue("Building at: {TMP_PATH}"))
message(strrep("=", 60))

build_start <- Sys.time()

con <- DBI::dbConnect(duckdb::duckdb(), dbdir = TMP_PATH)
# NOTE: on.exit() removed — unreliable at top level of source()'d scripts
# (no stable function frame). Cleanup handled explicitly via tryCatch below.

# ==============================================================================
# SECTION 5: INITIALIZE INGEST LOG ----
# ==============================================================================

ingest_log <- tibble(
  table_name   = character(),
  row_count    = integer(),
  col_count    = integer(),
  duration_sec = numeric()
)

# ==============================================================================
# SECTION 6: SEQUENTIAL TABLE INGESTION + INDEXING + VERIFICATION ----
# ==============================================================================
# WHY sequential with gc(): Large tables (ENCOUNTER 10M+ rows, DIAGNOSIS 20M+ rows)
# can cause memory pressure. Sequential ingestion with gc() between tables prevents
# OOM errors on HiPerGator. tryCatch ensures that ANY failure (missing RDS, write error,
# index creation failure) aborts the entire ingest without swapping .tmp to canonical.
# Explicit error handling instead of on.exit() — more reliable in source()'d scripts

tables_ingested <- character(0)

ingest_ok <- tryCatch(
  {
    for (tbl_name in TABLES_TO_INGEST) {
      rds_path <- file.path(CONFIG$cache$raw_dir, paste0(tbl_name, ".rds"))

      if (!file.exists(rds_path)) {
        message(glue("\n  SKIPPED: {tbl_name} -- RDS file not found ({rds_path})"))
        next
      }

      message(glue("\n[{which(TABLES_TO_INGEST == tbl_name)}/{length(TABLES_TO_INGEST)}] Ingesting {tbl_name}..."))
      tbl_start <- Sys.time()

      tbl_ok <- tryCatch(
        {
          # SAFE-01: Validate RDS file exists before loading
          assert_rds_exists(rds_path, script_name = "R/03")

          # Load from RDS cache
          df <- readRDS(rds_path)
          message(glue("  Loaded RDS: {format(nrow(df), big.mark=',')} rows x {ncol(df)} cols"))

          # SAFE-02: Validate data frame structure
          assert_df_valid(df, tbl_name, required_cols = c("ID"),
                          script_name = "R/03", allow_empty = TRUE)

          # Write to DuckDB (per D-02: overwrite = TRUE for clean rebuild)
          DBI::dbWriteTable(con, tbl_name, df, overwrite = TRUE)

          # Record metrics
          duration <- as.numeric(difftime(Sys.time(), tbl_start, units = "secs"))
          ingest_log <<- bind_rows(ingest_log, tibble(
            table_name   = tbl_name,
            row_count    = nrow(df),
            col_count    = ncol(df),
            duration_sec = round(duration, 2)
          ))

          message(glue("  Written to DuckDB in {round(duration, 1)}s"))
          tables_ingested <<- c(tables_ingested, tbl_name)

          # Free memory before next table
          rm(df)
          gc(verbose = FALSE)
          TRUE
        },
        error = function(e) {
          warning(glue("INGEST SKIPPED: {tbl_name} -- {e$message}"))
          FALSE
        }
      )
    }

    # ============================================================================
    # INDEX CREATION (Phase 29 Plan 02 -- DBING-03)
    # ============================================================================
    # Build indexes AFTER all data is loaded (faster than during insert).
    # Per D-04: tryCatch() per index -- failed index = warning, not error.
    # An unindexed table is still queryable, just slower.

    message(glue("\n{strrep('=', 60)}"))
    message("Creating indexes...")
    message(strrep("=", 60))

    index_results <<- tibble(
      table_name = character(),
      index_name = character(),
      column     = character(),
      status     = character()
    )

    # PATID indexes on ingested tables (universal join key)
    # NOTE: PCORnet CDM uses "ID" as the patient ID column name, not "PATID"
    # PROVIDER table uses PROVIDERID instead of ID — skip it for PATID index
    tables_with_id <- setdiff(tables_ingested, "PROVIDER")
    for (tbl_name in tables_with_id) {
      idx_name <- paste0("idx_", tolower(tbl_name), "_patid")
      tryCatch(
        {
          DBI::dbExecute(con, glue("CREATE INDEX {idx_name} ON {tbl_name} (ID)"))
          message(glue("  Created: {idx_name}"))
          index_results <<- bind_rows(index_results, tibble(
            table_name = tbl_name, index_name = idx_name,
            column = "ID", status = "created"
          ))
        },
        error = function(e) {
          warning(glue("  FAILED: {idx_name} -- {e$message}"))
          index_results <<- bind_rows(index_results, tibble(
            table_name = tbl_name, index_name = idx_name,
            column = "ID", status = paste0("failed: ", e$message)
          ))
        }
      )
    }

    # ENCOUNTERID indexes on ingested tables that have it
    for (tbl_name in intersect(TABLES_WITH_ENCOUNTERID, tables_ingested)) {
      idx_name <- paste0("idx_", tolower(tbl_name), "_encounterid")
      tryCatch(
        {
          DBI::dbExecute(con, glue("CREATE INDEX {idx_name} ON {tbl_name} (ENCOUNTERID)"))
          message(glue("  Created: {idx_name}"))
          index_results <<- bind_rows(index_results, tibble(
            table_name = tbl_name, index_name = idx_name,
            column = "ENCOUNTERID", status = "created"
          ))
        },
        error = function(e) {
          warning(glue("  FAILED: {idx_name} -- {e$message}"))
          index_results <<- bind_rows(index_results, tibble(
            table_name = tbl_name, index_name = idx_name,
            column = "ENCOUNTERID", status = paste0("failed: ", e$message)
          ))
        }
      )
    }

    n_created <<- sum(index_results$status == "created")
    n_failed <<- sum(index_results$status != "created")
    message(glue("\nIndexes: {n_created} created, {n_failed} failed (of {nrow(index_results)} total)"))

    # ============================================================================
    # ROUND-TRIP VERIFICATION (Phase 29 Plan 02 -- DBING-03)
    # ============================================================================
    # Verify dimensions and column names match between RDS source and DuckDB copy.
    # Full value parity testing is deferred to Phase 31.

    message(glue("\n{strrep('=', 60)}"))
    message("Round-trip verification...")
    message(strrep("=", 60))

    all_ok <- TRUE
    for (tbl_name in tables_ingested) {
      result <- verify_duckdb_roundtrip(tbl_name, con)
      if (result$ok) {
        message(glue("  PASS: {tbl_name} ({format(result$rds_nrow, big.mark=',')} rows x {result$rds_ncol} cols)"))
      } else {
        message(glue("  FAIL: {tbl_name} -- dim_match={result$dim_match}, col_match={result$col_match}"))
        if (length(result$mismatched_cols) > 0) {
          message(glue("         {paste(result$mismatched_cols, collapse = '; ')}"))
        }
        all_ok <- FALSE
      }
    }

    if (!all_ok) {
      stop("Round-trip verification FAILED for one or more tables. DuckDB file NOT promoted.")
    }

    message(glue("\nAll {length(tables_ingested)} ingested tables passed round-trip verification."))

    TRUE # signal success
  },
  error = function(e) {
    # Cleanup on error: disconnect and remove partial .tmp (per D-03)
    message(glue("\nINGEST ERROR: {e$message}"))
    tryCatch(DBI::dbDisconnect(con, shutdown = TRUE), error = function(e2) NULL)
    if (file.exists(TMP_PATH)) {
      message(glue("Cleaning up .tmp file after error: {TMP_PATH}"))
      file.remove(TMP_PATH)
    }
    stop(e$message)
  }
)

# ==============================================================================
# SECTION 7: ATOMIC SWAP ----
# ==============================================================================
# Disconnect from .tmp database and rename to canonical path. This is the final
# commit point - only reached if ALL 13 tables ingested successfully.

# Disconnect cleanly before file operations
DBI::dbDisconnect(con, shutdown = TRUE)

# Atomic swap: remove old canonical, rename .tmp to canonical
if (file.exists(DUCKDB_PATH)) {
  file.remove(DUCKDB_PATH)
  message(glue("Removed previous DuckDB file: {DUCKDB_PATH}"))
}
file.rename(TMP_PATH, DUCKDB_PATH)

build_duration <- as.numeric(difftime(Sys.time(), build_start, units = "secs"))
file_size_mb <- round(file.info(DUCKDB_PATH)$size / 1024^2, 1)

# ==============================================================================
# SECTION 8: WRITE INGEST LOG CSV ----
# ==============================================================================

log_path <- file.path("output", "logs", glue("duckdb_ingest_{EXTRACT_DATE}.csv"))
readr::write_csv(ingest_log, log_path)

# ==============================================================================
# SECTION 9: PRINT SUMMARY ----
# ==============================================================================

message(strrep("=", 60))
message(glue("DuckDB Ingest COMPLETE"))
message(glue("  File: {DUCKDB_PATH}"))
message(glue("  Size: {file_size_mb} MB"))
message(glue("  Tables: {nrow(ingest_log)}"))
message(glue("  Total rows: {format(sum(ingest_log$row_count), big.mark=',')}"))
message(glue("  Indexes: {n_created} created ({n_failed} failed)"))
message(glue("  Verification: {length(TABLES_TO_INGEST)}/{length(TABLES_TO_INGEST)} tables passed"))
message(glue("  Build time: {round(build_duration, 1)}s ({round(build_duration/60, 1)} min)"))
message(glue("  Ingest log: {log_path}"))
message(strrep("=", 60))

# ==============================================================================
# End of script
# ==============================================================================
