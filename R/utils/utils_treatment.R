# ==============================================================================
# utils/utils_treatment.R -- Shared treatment analysis helpers
# ==============================================================================
#
# Purpose:
#   Shared treatment analysis helpers. Provides safe_table(), get_hl_patient_ids(),
#   and empty_result() for treatment pipeline scripts. safe_table() wraps
#   get_pcornet_table() with null-guard for missing tables (returns NULL instead
#   of error). get_hl_patient_ids() queries DIAGNOSIS for HL cohort. empty_result()
#   returns zero-row tibble matching code inventory schema for graceful handling
#   of missing data sources.
#
# Inputs:
#   - None (utility function library, not a standalone script)
#
# Outputs:
#   - None (defines functions loaded into calling scripts' environment)
#
# Dependencies:
#   - dplyr: Data manipulation for HL patient ID query
#   - tibble: empty_result() tibble creation
#   - glue: String formatting for messages
#
# Requirements: N/A (utility module)
#
# ==============================================================================

#' Safely access a PCORnet table with null-guard
#'
#' Wraps get_pcornet_table() in tryCatch to handle missing tables gracefully.
#' Returns NULL (not an error) when a table doesn't exist.
#'
#' @param name Character. PCORnet table name (e.g., "PROCEDURES", "DISPENSING")
#' @return A dplyr-compatible object (tibble or tbl_dbi), or NULL if not found
safe_table <- function(name) {
  tryCatch(
    get_pcornet_table(name),
    error = function(e) {
      message(glue::glue("  Table {name} not found; skipping"))
      NULL
    }
  )
}

#' Create empty result tibble for missing tables
#'
#' Returns a zero-row tibble matching the standard code inventory schema.
#' @return Tibble with columns: code, code_type, source_table, n, drug_name
empty_result <- function() {
  tibble::tibble(
    code = character(), code_type = character(), source_table = character(),
    n = integer(), drug_name = character()
  )
}

#' Get patient IDs with a Hodgkin Lymphoma diagnosis
#'
#' Queries DIAGNOSIS table for any patient with an HL ICD-10 or ICD-9 code.
#' Used to pull ALL drugs for HL patients (not just curated TREATMENT_CODES).
#'
#' @return Character vector of unique patient IDs
get_hl_patient_ids <- function() {
  dx_tbl <- safe_table("DIAGNOSIS")
  if (is.null(dx_tbl)) {
    message("  Warning: DIAGNOSIS table not found, cannot identify HL patients")
    return(character(0))
  }

  tryCatch({
    hl_ids <- dx_tbl %>%
      dplyr::filter(
        (DX_TYPE == "10" & DX %in% ICD_CODES$hl_icd10) |
        (DX_TYPE == "09" & DX %in% ICD_CODES$hl_icd9)
      ) %>%
      dplyr::select(ID) %>%
      dplyr::distinct() %>%
      dplyr::collect() %>%
      dplyr::pull(ID)
    message(glue::glue("  Found {format(length(hl_ids), big.mark = ',')} patients with HL diagnosis"))
    hl_ids
  }, error = function(e) {
    message(glue::glue("  Warning: HL patient lookup failed: {e$message}"))
    character(0)
  })
}

#' Helper: return nrow or 0 for NULL tibbles (for logging)
#' @param df A data frame or NULL
#' @return Integer row count (0 if NULL)
nrow_or_0 <- function(df) if (is.null(df)) 0L else nrow(df)

#' Verify output file exists and log size
#'
#' Checks if a file exists and prints formatted size message.
#' Used for post-run verification of RDS/XLSX outputs.
#'
#' @param path Character. File path to check
#' @param label Character. Human-readable label for the file
check_file <- function(path, label) {
  if (file.exists(path)) {
    sz <- file.size(path)
    message(glue("  OK: {label} ({round(sz/1024, 1)} KB)"))
  } else {
    message(glue("  MISSING: {label}"))
  }
}
