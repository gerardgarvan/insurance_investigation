# ==============================================================================
# Search All Tables for C8190 (Hodgkin lymphoma, unspecified, extranodal)
# ==============================================================================
# Searches every PCORnet CDM table for occurrences of C8190 / C81.90 across
# all character columns. Reports frequencies per table and column.
#
# Inputs:
#   - DuckDB backend (all 13 tables + TUMOR_REGISTRY_ALL view)
#
# Outputs:
#   - Console output: frequencies per table/column
#
# Usage:
#   Rscript R/55_search_C8190.R
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(DBI)
  library(duckdb)
  library(glue)
  library(stringr)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")

message("\n", strrep("=", 70))
message("SEARCHING ALL TABLES FOR C8190 / C81.90")
message(strrep("=", 70))

# Target code in both forms
TARGET_DOTTED   <- "C81.90"
TARGET_UNDOTTED <- "C8190"

# Tables to search (skip TUMOR_REGISTRY_ALL view to avoid double-counting TR1/2/3)
TABLES_TO_SEARCH <- c(
  "ENROLLMENT", "DIAGNOSIS", "PROCEDURES", "PRESCRIBING",
  "ENCOUNTER", "DEMOGRAPHIC",
  "TUMOR_REGISTRY1", "TUMOR_REGISTRY2", "TUMOR_REGISTRY3",
  "DISPENSING", "MED_ADMIN", "LAB_RESULT_CM", "PROVIDER"
)

# Store results
all_results <- list()

for (tbl_name in TABLES_TO_SEARCH) {
  message(glue("\n--- {tbl_name} ---"))

  # Check table exists in DuckDB
  tbl_ref <- get_pcornet_table(tbl_name)
  if (is.null(tbl_ref)) {
    message("  Table not found, skipping.")
    next
  }

  # Get column names and types from DuckDB
  col_info <- DBI::dbGetQuery(pcornet_con, glue(
    "SELECT column_name, data_type FROM information_schema.columns
     WHERE table_name = '{tbl_name}' ORDER BY ordinal_position"
  ))

  # Filter to character/string columns only
  char_cols <- col_info$column_name[col_info$data_type %in% c("VARCHAR", "TEXT", "CHAR")]

  if (length(char_cols) == 0) {
    message("  No character columns, skipping.")
    next
  }

  # Build SQL: for each character column, count rows matching C8190 or C81.90
  # Use UPPER() for case-insensitive matching and check both dotted/undotted
  found_any <- FALSE

  for (col in char_cols) {
    # Use SQL to count matches (avoids materializing the full table)
    query <- glue(
      "SELECT COUNT(*) AS n FROM {tbl_name}
       WHERE UPPER(\"{col}\") = '{TARGET_UNDOTTED}'
          OR UPPER(\"{col}\") = '{TARGET_DOTTED}'
          OR UPPER(\"{col}\") LIKE '%{TARGET_UNDOTTED}%'
          OR UPPER(\"{col}\") LIKE '%{TARGET_DOTTED}%'"
    )

    result <- tryCatch(
      DBI::dbGetQuery(pcornet_con, query),
      error = function(e) {
        message(glue("  Error querying {col}: {e$message}"))
        return(data.frame(n = 0))
      }
    )

    if (result$n > 0) {
      found_any <- TRUE

      # Get frequency breakdown: exact vs partial match
      detail_query <- glue(
        "SELECT
           \"{col}\" AS value,
           COUNT(*) AS freq
         FROM {tbl_name}
         WHERE UPPER(\"{col}\") = '{TARGET_UNDOTTED}'
            OR UPPER(\"{col}\") = '{TARGET_DOTTED}'
            OR UPPER(\"{col}\") LIKE '%{TARGET_UNDOTTED}%'
            OR UPPER(\"{col}\") LIKE '%{TARGET_DOTTED}%'
         GROUP BY \"{col}\"
         ORDER BY freq DESC
         LIMIT 50"
      )

      detail <- tryCatch(
        DBI::dbGetQuery(pcornet_con, detail_query),
        error = function(e) data.frame(value = character(), freq = integer())
      )

      message(glue("  ** {col}: {result$n} total rows matching **"))
      for (i in seq_len(nrow(detail))) {
        message(glue("       '{detail$value[i]}' = {format(detail$freq[i], big.mark=',')}"))
      }

      # Also get unique patient count if ID column exists
      if ("ID" %in% col_info$column_name) {
        pt_query <- glue(
          "SELECT COUNT(DISTINCT ID) AS n_patients FROM {tbl_name}
           WHERE UPPER(\"{col}\") = '{TARGET_UNDOTTED}'
              OR UPPER(\"{col}\") = '{TARGET_DOTTED}'
              OR UPPER(\"{col}\") LIKE '%{TARGET_UNDOTTED}%'
              OR UPPER(\"{col}\") LIKE '%{TARGET_DOTTED}%'"
        )
        pt_result <- tryCatch(
          DBI::dbGetQuery(pcornet_con, pt_query),
          error = function(e) data.frame(n_patients = NA)
        )
        message(glue("       Unique patients: {format(pt_result$n_patients, big.mark=',')}"))
      }

      # Store result
      all_results[[length(all_results) + 1]] <- tibble(
        table = tbl_name,
        column = col,
        total_rows = result$n,
        distinct_values = nrow(detail)
      )
    }
  }

  if (!found_any) {
    message("  No matches found in any column.")
  }
}

# ==============================================================================
# SUMMARY
# ==============================================================================

message("\n", strrep("=", 70))
message("SUMMARY: C8190 / C81.90 across all tables")
message(strrep("=", 70))

if (length(all_results) > 0) {
  summary_df <- bind_rows(all_results)
  for (i in seq_len(nrow(summary_df))) {
    row <- summary_df[i, ]
    message(glue("  {row$table}.{row$column}: {format(row$total_rows, big.mark=',')} rows"))
  }
} else {
  message("  No matches found in any table.")
}

# ==============================================================================
# DEEP DIVE: DIAGNOSIS table breakdown (if matches found there)
# ==============================================================================

dx_matches <- Filter(function(r) r$table == "DIAGNOSIS", all_results)
if (length(dx_matches) > 0) {
  message("\n", strrep("=", 70))
  message("DIAGNOSIS DEEP DIVE: C8190 / C81.90")
  message(strrep("=", 70))

  # By DX_TYPE
  q1 <- glue(
    "SELECT DX_TYPE, COUNT(*) AS freq, COUNT(DISTINCT ID) AS n_patients
     FROM DIAGNOSIS
     WHERE UPPER(DX) = '{TARGET_UNDOTTED}'
        OR UPPER(DX) = '{TARGET_DOTTED}'
        OR UPPER(DX) LIKE '%{TARGET_UNDOTTED}%'
        OR UPPER(DX) LIKE '%{TARGET_DOTTED}%'
     GROUP BY DX_TYPE
     ORDER BY freq DESC"
  )
  dx_by_type <- DBI::dbGetQuery(pcornet_con, q1)
  message("\n  By DX_TYPE:")
  for (i in seq_len(nrow(dx_by_type))) {
    message(glue("    DX_TYPE='{dx_by_type$DX_TYPE[i]}': {format(dx_by_type$freq[i], big.mark=',')} rows, {format(dx_by_type$n_patients[i], big.mark=',')} patients"))
  }

  # By DX_SOURCE
  q2 <- glue(
    "SELECT DX_SOURCE, COUNT(*) AS freq, COUNT(DISTINCT ID) AS n_patients
     FROM DIAGNOSIS
     WHERE UPPER(DX) = '{TARGET_UNDOTTED}'
        OR UPPER(DX) = '{TARGET_DOTTED}'
        OR UPPER(DX) LIKE '%{TARGET_UNDOTTED}%'
        OR UPPER(DX) LIKE '%{TARGET_DOTTED}%'
     GROUP BY DX_SOURCE
     ORDER BY freq DESC"
  )
  dx_by_source <- DBI::dbGetQuery(pcornet_con, q2)
  message("\n  By DX_SOURCE:")
  for (i in seq_len(nrow(dx_by_source))) {
    message(glue("    DX_SOURCE='{dx_by_source$DX_SOURCE[i]}': {format(dx_by_source$freq[i], big.mark=',')} rows, {format(dx_by_source$n_patients[i], big.mark=',')} patients"))
  }

  # By ENC_TYPE
  q3 <- glue(
    "SELECT ENC_TYPE, COUNT(*) AS freq, COUNT(DISTINCT ID) AS n_patients
     FROM DIAGNOSIS
     WHERE UPPER(DX) = '{TARGET_UNDOTTED}'
        OR UPPER(DX) = '{TARGET_DOTTED}'
        OR UPPER(DX) LIKE '%{TARGET_UNDOTTED}%'
        OR UPPER(DX) LIKE '%{TARGET_DOTTED}%'
     GROUP BY ENC_TYPE
     ORDER BY freq DESC"
  )
  dx_by_enc <- DBI::dbGetQuery(pcornet_con, q3)
  message("\n  By ENC_TYPE:")
  for (i in seq_len(nrow(dx_by_enc))) {
    message(glue("    ENC_TYPE='{dx_by_enc$ENC_TYPE[i]}': {format(dx_by_enc$freq[i], big.mark=',')} rows, {format(dx_by_enc$n_patients[i], big.mark=',')} patients"))
  }

  # Date range
  q4 <- glue(
    "SELECT MIN(DX_DATE) AS earliest, MAX(DX_DATE) AS latest
     FROM DIAGNOSIS
     WHERE UPPER(DX) = '{TARGET_UNDOTTED}'
        OR UPPER(DX) = '{TARGET_DOTTED}'
        OR UPPER(DX) LIKE '%{TARGET_UNDOTTED}%'
        OR UPPER(DX) LIKE '%{TARGET_DOTTED}%'"
  )
  dx_dates <- DBI::dbGetQuery(pcornet_con, q4)
  message(glue("\n  Date range: {dx_dates$earliest} to {dx_dates$latest}"))
}

# ==============================================================================
# CLEANUP
# ==============================================================================

close_pcornet_con()
message("\n=== Search complete ===")
