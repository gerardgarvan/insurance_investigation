# ==============================================================================
# 25_duckdb_ingest.R -- Ingest PCORnet CDM tables from RDS cache into DuckDB
# ==============================================================================
#
# Reads all 13 PCORnet tables from RDS cache (Phase 15) and writes them
# into a single DuckDB file with atomic write guarantee.
#
# Usage:
#   source("R/00_config.R")
#   source("R/25_duckdb_ingest.R")
#
# Output:
#   - DuckDB file at CONFIG$cache$duckdb_path (per D-01)
#   - Ingest log CSV at output/logs/duckdb_ingest_<EXTRACT_DATE>.csv
#
# Behavior:
#   - Always rebuilds from scratch (per D-02: no cache-check)
#   - Aborts on any table failure (per D-03: .tmp not swapped)
#   - Sequential table ingestion with gc() between tables
#   - Note: TUMOR_REGISTRY_ALL is NOT ingested -- it is a derived table (TR1+TR2+TR3)
#
# Requirements: DBING-01, DBING-02
# ==============================================================================

source("R/00_config.R")

library(duckdb)
library(DBI)
library(dplyr)
library(readr)
library(glue)

# ==============================================================================
# CONSTANTS
# ==============================================================================

# Tables to ingest (same as PCORNET_TABLES from 00_config.R, 13 tables)
# Note: TUMOR_REGISTRY_ALL is NOT ingested -- it's a derived bind_rows(TR1+TR2+TR3)
TABLES_TO_INGEST <- PCORNET_TABLES

DUCKDB_PATH <- CONFIG$cache$duckdb_path
DUCKDB_DIR  <- CONFIG$cache$duckdb_dir
TMP_PATH    <- paste0(DUCKDB_PATH, ".tmp")

# ==============================================================================
# CREATE OUTPUT DIRECTORIES
# ==============================================================================

if (!dir.exists(DUCKDB_DIR)) {
  dir.create(DUCKDB_DIR, recursive = TRUE, showWarnings = FALSE)
  message(glue("Created DuckDB directory: {DUCKDB_DIR}"))
}
if (!dir.exists("output/logs")) {
  dir.create("output/logs", recursive = TRUE, showWarnings = FALSE)
}

# ==============================================================================
# CLEAN UP STALE .TMP FROM PRIOR INTERRUPTED RUN
# ==============================================================================

if (file.exists(TMP_PATH)) {
  message(glue("Removing stale .tmp file from prior interrupted run: {TMP_PATH}"))
  file.remove(TMP_PATH)
}

# ==============================================================================
# OPEN DUCKDB CONNECTION TO .TMP PATH
# ==============================================================================

message(strrep("=", 60))
message(glue("DuckDB Ingest: {length(TABLES_TO_INGEST)} tables from RDS cache"))
message(glue("Target: {DUCKDB_PATH}"))
message(glue("Building at: {TMP_PATH}"))
message(strrep("=", 60))

build_start <- Sys.time()

con <- DBI::dbConnect(duckdb::duckdb(), dbdir = TMP_PATH)
on.exit({
  tryCatch(DBI::dbDisconnect(con, shutdown = TRUE), error = function(e) NULL)
  # Clean up .tmp on error (per D-03: don't swap partial builds)
  if (file.exists(TMP_PATH)) {
    message(glue("Cleaning up .tmp file after error: {TMP_PATH}"))
    file.remove(TMP_PATH)
  }
}, add = TRUE)

# ==============================================================================
# INITIALIZE INGEST LOG
# ==============================================================================

ingest_log <- tibble(
  table_name   = character(),
  row_count    = integer(),
  col_count    = integer(),
  duration_sec = numeric()
)

# ==============================================================================
# SEQUENTIAL TABLE INGESTION LOOP
# ==============================================================================

for (tbl_name in TABLES_TO_INGEST) {
  rds_path <- file.path(CONFIG$cache$raw_dir, paste0(tbl_name, ".rds"))

  if (!file.exists(rds_path)) {
    stop(glue("RDS file not found for {tbl_name}: {rds_path}"))
  }

  message(glue("\n[{which(TABLES_TO_INGEST == tbl_name)}/{length(TABLES_TO_INGEST)}] Ingesting {tbl_name}..."))
  tbl_start <- Sys.time()

  # Load from RDS cache
  df <- readRDS(rds_path)
  message(glue("  Loaded RDS: {format(nrow(df), big.mark=',')} rows x {ncol(df)} cols"))

  # Write to DuckDB (per D-02: overwrite = TRUE for clean rebuild)
  DBI::dbWriteTable(con, tbl_name, df, overwrite = TRUE)

  # Record metrics
  duration <- as.numeric(difftime(Sys.time(), tbl_start, units = "secs"))
  ingest_log <- bind_rows(ingest_log, tibble(
    table_name   = tbl_name,
    row_count    = nrow(df),
    col_count    = ncol(df),
    duration_sec = round(duration, 2)
  ))

  message(glue("  Written to DuckDB in {round(duration, 1)}s"))

  # Free memory before next table
  rm(df)
  gc(verbose = FALSE)
}

# ==============================================================================
# ATOMIC SWAP: DISCONNECT AND RENAME .TMP TO CANONICAL PATH
# ==============================================================================

# Disconnect cleanly before file operations
DBI::dbDisconnect(con, shutdown = TRUE)
on.exit()  # Clear the on.exit hook (build succeeded, don't clean up .tmp)

# Atomic swap: remove old canonical, rename .tmp to canonical
if (file.exists(DUCKDB_PATH)) {
  file.remove(DUCKDB_PATH)
  message(glue("Removed previous DuckDB file: {DUCKDB_PATH}"))
}
file.rename(TMP_PATH, DUCKDB_PATH)

build_duration <- as.numeric(difftime(Sys.time(), build_start, units = "secs"))
file_size_mb <- round(file.info(DUCKDB_PATH)$size / 1024^2, 1)

# ==============================================================================
# WRITE INGEST LOG CSV
# ==============================================================================

log_path <- file.path("output", "logs", glue("duckdb_ingest_{EXTRACT_DATE}.csv"))
readr::write_csv(ingest_log, log_path)

# ==============================================================================
# PRINT SUMMARY
# ==============================================================================

message(strrep("=", 60))
message(glue("DuckDB Ingest COMPLETE"))
message(glue("  File: {DUCKDB_PATH}"))
message(glue("  Size: {file_size_mb} MB"))
message(glue("  Tables: {nrow(ingest_log)}"))
message(glue("  Total rows: {format(sum(ingest_log$row_count), big.mark=',')}"))
message(glue("  Build time: {round(build_duration, 1)}s ({round(build_duration/60, 1)} min)"))
message(glue("  Ingest log: {log_path}"))
message(strrep("=", 60))

# ==============================================================================
# End of script
# ==============================================================================
