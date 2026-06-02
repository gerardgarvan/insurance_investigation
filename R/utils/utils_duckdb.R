# ==============================================================================
# utils/utils_duckdb.R -- DuckDB utility functions for backend-agnostic data access
# ==============================================================================
#
# Purpose:
#   DuckDB utility functions for backend-agnostic data access. Provides
#   get_pcornet_table(), connection management, and lazy-to-eager materialization.
#   The get_pcornet_table() dispatcher transparently switches between RDS in-memory
#   tibbles (pcornet$TABLE_NAME) and DuckDB lazy queries (tbl(con, "TABLE_NAME"))
#   based on USE_DUCKDB flag. Also provides verify_duckdb_roundtrip() for ingest
#   validation (dimension and column name checks, not value comparison).
#
# Inputs:
#   - None (utility function library, not a standalone script)
#
# Outputs:
#   - None (defines functions loaded into calling scripts' environment)
#
# Dependencies:
#   - DBI, duckdb: Database connection and query execution
#   - dplyr: tbl(), collect() for lazy query handling
#   - glue: String formatting for messages
#
# Requirements: N/A (utility module)
#
# ==============================================================================

library(DBI)
library(duckdb)
library(dplyr)
library(glue)

# ------------------------------------------------------------------------------
# verify_duckdb_roundtrip()
# ------------------------------------------------------------------------------
#' Verify round-trip integrity of a single table in DuckDB
#'
#' Compares dimension (nrow x ncol) and column names between the RDS source
#' and the DuckDB copy. Does NOT compare values (that's Phase 31 parity testing).
#'
#' @param table_name Character. Name of the table (e.g., "ENROLLMENT")
#' @param con DBI connection to DuckDB file
#' @param raw_dir Character. Path to RDS cache directory (default: CONFIG$cache$raw_dir)
#'
#' @return List with elements:
#'   - ok: logical, TRUE if dimensions and column names match
#'   - table_name: character
#'   - rds_nrow, rds_ncol: integer, dimensions from RDS source
#'   - ddb_nrow, ddb_ncol: integer, dimensions from DuckDB table
#'   - dim_match: logical, TRUE if nrow and ncol match
#'   - col_match: logical, TRUE if column names match (order-sensitive)
#'   - mismatched_cols: character vector of column names that differ (empty if match)
#'
verify_duckdb_roundtrip <- function(table_name, con, raw_dir = CONFIG$cache$raw_dir) {
  # Read RDS source dimensions (without loading full data)
  rds_path <- file.path(raw_dir, paste0(table_name, ".rds"))
  if (!file.exists(rds_path)) {
    warning(glue("RDS file not found for verification: {rds_path}"))
    return(list(
      ok = FALSE, table_name = table_name,
      rds_nrow = NA, rds_ncol = NA,
      ddb_nrow = NA, ddb_ncol = NA,
      dim_match = FALSE, col_match = FALSE,
      mismatched_cols = "RDS file not found"
    ))
  }

  rds_df <- readRDS(rds_path)
  rds_dims <- dim(rds_df)
  rds_cols <- colnames(rds_df)
  rm(rds_df)
  gc(verbose = FALSE)

  # Read DuckDB table dimensions via SQL (avoids materializing full table)
  ddb_nrow <- DBI::dbGetQuery(con, glue("SELECT COUNT(*) AS n FROM {table_name}"))$n
  ddb_cols <- DBI::dbListFields(con, table_name)
  ddb_ncol <- length(ddb_cols)

  # Compare dimensions
  dim_match <- (rds_dims[1] == ddb_nrow) && (rds_dims[2] == ddb_ncol)

  # Compare column names (order-sensitive)
  col_match <- identical(rds_cols, ddb_cols)
  mismatched <- character()
  if (!col_match) {
    in_rds_not_ddb <- setdiff(rds_cols, ddb_cols)
    in_ddb_not_rds <- setdiff(ddb_cols, rds_cols)
    if (length(in_rds_not_ddb) > 0) {
      mismatched <- c(mismatched, paste0("in RDS only: ", paste(in_rds_not_ddb, collapse = ", ")))
    }
    if (length(in_ddb_not_rds) > 0) {
      mismatched <- c(mismatched, paste0("in DuckDB only: ", paste(in_ddb_not_rds, collapse = ", ")))
    }
    if (length(mismatched) == 0 && !identical(rds_cols, ddb_cols)) {
      mismatched <- "column order differs"
    }
  }

  ok <- dim_match && col_match

  list(
    ok = ok,
    table_name = table_name,
    rds_nrow = rds_dims[1],
    rds_ncol = rds_dims[2],
    ddb_nrow = ddb_nrow,
    ddb_ncol = ddb_ncol,
    dim_match = dim_match,
    col_match = col_match,
    mismatched_cols = if (length(mismatched) > 0) mismatched else character()
  )
}

# ------------------------------------------------------------------------------
# open_pcornet_con() -- Phase 30
# ------------------------------------------------------------------------------
#' Open a read-only DuckDB connection and store as global pcornet_con
#'
#' Creates a DBI connection to the PCORnet DuckDB file with read_only = TRUE.
#' Also creates the TUMOR_REGISTRY_ALL view (D-03: SQL VIEW combining TR1/TR2/TR3).
#' Stores connection as pcornet_con in the global environment (D-04).
#'
#' @param db_path Character. Path to DuckDB file. Default: CONFIG$cache$duckdb_path
#' @param read_only Logical. Enforce read-only mode. Default: TRUE
#' @return DBI connection object (invisibly)
#'
open_pcornet_con <- function(db_path = CONFIG$cache$duckdb_path, read_only = TRUE) {
  if (exists("pcornet_con", envir = .GlobalEnv)) {
    warning("DuckDB connection already open. Closing and reopening.")
    close_pcornet_con()
  }

  con <- DBI::dbConnect(
    duckdb::duckdb(),
    dbdir = db_path,
    read_only = read_only
  )

  # Create TUMOR_REGISTRY_ALL view (D-03)
  # TEMP view: session-local, works in read-only mode (no persistent DDL needed)
  DBI::dbExecute(con, "
    CREATE TEMP VIEW IF NOT EXISTS TUMOR_REGISTRY_ALL AS
    SELECT * FROM TUMOR_REGISTRY1
    UNION ALL BY NAME
    SELECT * FROM TUMOR_REGISTRY2
    UNION ALL BY NAME
    SELECT * FROM TUMOR_REGISTRY3
  ")

  assign("pcornet_con", con, envir = .GlobalEnv)
  message(glue("[DuckDB] Connection opened (read_only={read_only}): {db_path}"))
  invisible(con)
}

# ------------------------------------------------------------------------------
# close_pcornet_con() -- Phase 30
# ------------------------------------------------------------------------------
#' Close the global DuckDB connection
#'
#' Disconnects pcornet_con and removes it from the global environment.
#' Warns if no connection exists.
#'
close_pcornet_con <- function() {
  if (!exists("pcornet_con", envir = .GlobalEnv)) {
    warning("No DuckDB connection to close.")
    return(invisible(NULL))
  }

  con <- get("pcornet_con", envir = .GlobalEnv)
  DBI::dbDisconnect(con, shutdown = TRUE)
  rm(pcornet_con, envir = .GlobalEnv)
  message("[DuckDB] Connection closed.")
  invisible(NULL)
}

# ------------------------------------------------------------------------------
# get_pcornet_table() -- Phase 30
# ------------------------------------------------------------------------------
#' Get a PCORnet table from either RDS or DuckDB backend
#'
#' Dispatcher function returning a dplyr-compatible object:
#'   - RDS mode (USE_DUCKDB = FALSE): returns in-memory tibble from pcornet$ list (D-01)
#'   - DuckDB mode (USE_DUCKDB = TRUE): returns tbl_dbi lazy query object
#'
#' Accesses pcornet$ list as a global variable (D-02). No signature changes
#' needed in downstream code.
#'
#' @param table_name Character. PCORnet table name (e.g., "DIAGNOSIS", "ENROLLMENT")
#' @param con DBI connection (optional). If NULL, uses global pcornet_con.
#' @return A dplyr-compatible object (tibble or tbl_dbi)
#'
get_pcornet_table <- function(table_name, con = NULL) {
  if (!exists("USE_DUCKDB", envir = .GlobalEnv) || !get("USE_DUCKDB", envir = .GlobalEnv)) {
    # RDS mode: return tibble from global pcornet list (D-01, D-02)
    # Returns NULL for missing tables (matches original pcornet$TABLE semantics)
    if (!exists("pcornet", envir = .GlobalEnv)) {
      stop(glue("pcornet list not found. Run source('R/01_load_pcornet.R') first."))
    }
    pcornet_list <- get("pcornet", envir = .GlobalEnv)
    if (!table_name %in% names(pcornet_list)) {
      return(NULL)
    }
    return(pcornet_list[[table_name]])
  } else {
    # DuckDB mode: return tbl_dbi lazy query object
    if (is.null(con)) {
      if (!exists("pcornet_con", envir = .GlobalEnv)) {
        stop("DuckDB connection not found. Run open_pcornet_con() first.")
      }
      con <- get("pcornet_con", envir = .GlobalEnv)
    }
    # Returns NULL for missing tables (matches original pcornet$TABLE semantics)
    tryCatch(
      dplyr::tbl(con, table_name),
      error = function(e) NULL
    )
  }
}

# ------------------------------------------------------------------------------
# materialize() -- Phase 30
# ------------------------------------------------------------------------------
#' Convert a lazy DuckDB query to an in-memory tibble
#'
#' Wrapper around dplyr::collect() for consistent API. In RDS mode, this is
#' a no-op pass-through (tibbles are already in memory). In DuckDB mode,
#' executes the lazy query and returns results as a tibble.
#'
#' @param lazy_tbl A dplyr-compatible object (tibble or tbl_dbi)
#' @return A tibble (in-memory data frame)
#'
materialize <- function(lazy_tbl) {
  if (inherits(lazy_tbl, "tbl_lazy")) {
    dplyr::collect(lazy_tbl)
  } else {
    # Already a tibble/data.frame -- no-op pass-through
    lazy_tbl
  }
}
