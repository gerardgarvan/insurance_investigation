# ==============================================================================
# utils_duckdb.R -- DuckDB utility functions
# ==============================================================================
#
# Phase 29: verify_duckdb_roundtrip() for ingest validation
# Phase 30: Will add get_pcornet_table(), open_pcornet_con(), close_pcornet_con(),
#           materialize(), and USE_DUCKDB dispatcher logic
#
# ==============================================================================

library(DBI)
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
