# ==============================================================================
# 17_value_audit.R -- Comprehensive value audit for all PCORnet CDM tables
# ==============================================================================
#
# Produces one CSV per loaded PCORnet CDM table enumerating every distinct value
# for every column with frequency counts and summary statistics. Designed to be
# fed to Claude for interactive review of coding inconsistencies.
#
# Output: output/tables/value_audit/<TABLE_NAME>_values.csv (13+ files)
#
# Column types handled:
#   - Character/factor: value + count + percentage frequency table
#   - Numeric/integer: min, max, mean, median, n_missing, n_valid, n_distinct
#   - Date: min, max, n_missing, n_valid
#   - Logical (_VALID flags): converted to character frequency table
#
# HIPAA compliance: All counts 1-10 are suppressed as "<11"
#
# Usage:
#   source("R/17_value_audit.R")
#   # Optionally source R/02_harmonize_payer.R and/or R/04_build_cohort.R first
#   # to include derived variable audits.
#
# ==============================================================================

source("R/01_load_pcornet.R")

library(dplyr)
library(purrr)
library(stringr)
library(glue)
library(readr)
library(tidyr)

# Output directory
output_dir <- file.path(CONFIG$output_dir, "tables", "value_audit")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

#' Apply HIPAA small-cell suppression to a count vector
#'
#' Counts 1-10 become "<11". Zero stays "0". NA stays NA. Values >10 formatted.
#'
#' @param n_vec Numeric vector of counts
#' @return Character vector with suppressed values
suppress_hipaa <- function(n_vec) {
  case_when(
    is.na(n_vec) ~ NA_character_,
    n_vec == 0 ~ "0",
    n_vec >= 1 & n_vec <= 10 ~ "<11",
    TRUE ~ format(n_vec, big.mark = ",", trim = TRUE)
  )
}

#' Audit a single character/factor column
#'
#' @param df Data frame
#' @param col_name Column name (string)
#' @return Tibble with column_name, column_type, value, n, pct, stat
audit_character_column <- function(df, col_name) {
  vals <- df[[col_name]]
  total <- length(vals)

  freq <- tibble(value = vals) %>%
    mutate(value = ifelse(is.na(value), "[NA]", as.character(value))) %>%
    count(value, name = "n") %>%
    arrange(desc(n)) %>%
    mutate(pct = round(n / total * 100, 2))

  freq %>%
    mutate(
      column_name = col_name,
      column_type = "character",
      stat = NA_character_,
      .before = 1
    )
}

#' Audit a single numeric/integer column
#'
#' @param df Data frame
#' @param col_name Column name (string)
#' @return Tibble with summary stats
audit_numeric_column <- function(df, col_name) {
  vals <- df[[col_name]]
  n_missing <- sum(is.na(vals))
  n_valid <- sum(!is.na(vals))
  n_dist <- n_distinct(vals, na.rm = TRUE)

  # If n_valid is 1-10, suppress all stats (HIPAA)
  if (n_valid >= 1 & n_valid <= 10) {
    stats <- tibble(
      stat = c("min", "max", "mean", "median", "n_missing", "n_valid", "n_distinct"),
      value = c(rep("suppressed", 4), as.character(n_missing), "<11", "suppressed"),
      n = NA_real_,
      pct = NA_real_
    )
  } else if (n_valid == 0) {
    stats <- tibble(
      stat = c("min", "max", "mean", "median", "n_missing", "n_valid", "n_distinct"),
      value = c(rep(NA_character_, 4), as.character(n_missing), "0", "0"),
      n = NA_real_,
      pct = NA_real_
    )
  } else {
    stats <- tibble(
      stat = c("min", "max", "mean", "median", "n_missing", "n_valid", "n_distinct"),
      value = c(
        as.character(min(vals, na.rm = TRUE)),
        as.character(max(vals, na.rm = TRUE)),
        as.character(round(mean(vals, na.rm = TRUE), 4)),
        as.character(median(vals, na.rm = TRUE)),
        as.character(n_missing),
        as.character(n_valid),
        as.character(n_dist)
      ),
      n = NA_real_,
      pct = NA_real_
    )
  }

  stats %>%
    mutate(
      column_name = col_name,
      column_type = "numeric",
      .before = 1
    )
}

#' Audit a single date column
#'
#' @param df Data frame
#' @param col_name Column name (string)
#' @return Tibble with date range stats
audit_date_column <- function(df, col_name) {
  vals <- df[[col_name]]
  n_missing <- sum(is.na(vals))
  n_valid <- sum(!is.na(vals))

  # If n_valid is 1-10, suppress all stats (HIPAA)
  if (n_valid >= 1 & n_valid <= 10) {
    stats <- tibble(
      stat = c("min", "max", "n_missing", "n_valid"),
      value = c("suppressed", "suppressed", as.character(n_missing), "<11"),
      n = NA_real_,
      pct = NA_real_
    )
  } else if (n_valid == 0) {
    stats <- tibble(
      stat = c("min", "max", "n_missing", "n_valid"),
      value = c(NA_character_, NA_character_, as.character(n_missing), "0"),
      n = NA_real_,
      pct = NA_real_
    )
  } else {
    stats <- tibble(
      stat = c("min", "max", "n_missing", "n_valid"),
      value = c(
        as.character(min(vals, na.rm = TRUE)),
        as.character(max(vals, na.rm = TRUE)),
        as.character(n_missing),
        as.character(n_valid)
      ),
      n = NA_real_,
      pct = NA_real_
    )
  }

  stats %>%
    mutate(
      column_name = col_name,
      column_type = "date",
      .before = 1
    )
}

#' Audit all columns in a single table
#'
#' @param df Data frame (tibble)
#' @param table_name Table name (string) for labeling
#' @return Combined tibble with audit rows for all columns
audit_table <- function(df, table_name) {
  col_results <- map(names(df), function(col_name) {
    col_data <- df[[col_name]]

    if (inherits(col_data, "Date") || inherits(col_data, "POSIXct")) {
      audit_date_column(df, col_name)
    } else if (is.logical(col_data)) {
      # Convert logical to character for frequency counting
      df_tmp <- df %>% mutate(!!col_name := as.character(!!sym(col_name)))
      audit_character_column(df_tmp, col_name) %>%
        mutate(column_type = "logical")
    } else if (is.numeric(col_data) || is.integer(col_data)) {
      audit_numeric_column(df, col_name)
    } else {
      audit_character_column(df, col_name)
    }
  })

  result <- bind_rows(col_results)
  result %>% mutate(table_name = table_name, .before = 1)
}

# ==============================================================================
# MAIN AUDIT LOOP
# ==============================================================================

message("\n", strrep("=", 60))
message("Value Audit: Enumerating all values across PCORnet CDM tables")
message(strrep("=", 60))

audit_results <- list()

for (tbl_name in names(pcornet)) {
  df <- pcornet[[tbl_name]]
  if (is.null(df)) {
    message(glue("  SKIP: {tbl_name} (NULL -- file not found during loading)"))
    next
  }

  message(glue("\nAuditing {tbl_name}: {format(nrow(df), big.mark=',')} rows, {ncol(df)} columns..."))

  result <- audit_table(df, tbl_name)
  audit_results[[tbl_name]] <- result

  # Apply HIPAA suppression to character frequency counts (n column)
  result <- result %>%
    mutate(
      n_raw = suppressWarnings(as.numeric(n)),
      n = case_when(
        is.na(n_raw) ~ as.character(n),
        n_raw >= 1 & n_raw <= 10 ~ "<11",
        n_raw == 0 ~ "0",
        TRUE ~ format(n_raw, big.mark = ",", trim = TRUE)
      ),
      pct = case_when(
        n == "<11" ~ "suppressed",
        TRUE ~ as.character(pct)
      )
    ) %>%
    select(-n_raw)

  # Write CSV
  output_file <- file.path(output_dir, glue("{tbl_name}_values.csv"))
  write_csv(result, output_file)
  message(glue("  Wrote {format(nrow(result), big.mark=',')} rows to {output_file}"))
}

# ==============================================================================
# DERIVED VARIABLE AUDIT
# ==============================================================================

message("\n", strrep("=", 60))
message("Derived Variable Audit")
message(strrep("=", 60))

derived_audits <- list()

# Check for payer_summary from 02_harmonize_payer.R
if (exists("payer_summary", envir = .GlobalEnv)) {
  message("  Found: payer_summary (from 02_harmonize_payer.R)")
  cols_to_audit <- intersect(
    c("PAYER_CATEGORY_PRIMARY", "PAYER_CATEGORY_AT_FIRST_DX",
      "DUAL_ELIGIBLE", "PAYER_TRANSITION", "SOURCE"),
    names(payer_summary)
  )
  if (length(cols_to_audit) > 0) {
    result <- audit_table(
      payer_summary %>% select(all_of(cols_to_audit)),
      "payer_summary_derived"
    )
    derived_audits[["payer_summary_derived"]] <- result
  }
}

# Check for hl_cohort from 04_build_cohort.R
if (exists("hl_cohort", envir = .GlobalEnv)) {
  message("  Found: hl_cohort (from 04_build_cohort.R)")
  cols_to_audit <- intersect(
    c("HL_SOURCE", "HAD_CHEMO", "HAD_RADIATION", "HAD_SCT",
      "PAYER_CATEGORY_PRIMARY", "PAYER_AT_CHEMO", "PAYER_AT_RADIATION", "PAYER_AT_SCT"),
    names(hl_cohort)
  )
  if (length(cols_to_audit) > 0) {
    result <- audit_table(
      hl_cohort %>% select(all_of(cols_to_audit)),
      "hl_cohort_derived"
    )
    derived_audits[["hl_cohort_derived"]] <- result
  }
}

# Write derived audit CSVs
if (length(derived_audits) > 0) {
  for (name in names(derived_audits)) {
    result <- derived_audits[[name]]

    # Apply HIPAA suppression
    result <- result %>%
      mutate(
        n_raw = suppressWarnings(as.numeric(n)),
        n = case_when(
          is.na(n_raw) ~ as.character(n),
          n_raw >= 1 & n_raw <= 10 ~ "<11",
          n_raw == 0 ~ "0",
          TRUE ~ format(n_raw, big.mark = ",", trim = TRUE)
        ),
        pct = case_when(
          n == "<11" ~ "suppressed",
          TRUE ~ as.character(pct)
        )
      ) %>%
      select(-n_raw)

    output_file <- file.path(output_dir, glue("{name}_values.csv"))
    write_csv(result, output_file)
    message(glue("  Wrote {format(nrow(result), big.mark=',')} rows to {output_file}"))
  }
} else {
  message("  No derived variables found in environment.")
  message("  To include them, source R/02_harmonize_payer.R and/or R/04_build_cohort.R before running this script.")
}

# ==============================================================================
# CONSOLE SUMMARY
# ==============================================================================

message("\n", strrep("=", 60))
message("Value Audit Complete")
message(strrep("=", 60))
message(glue("Tables audited: {length(audit_results)}"))
message(glue("Derived audits: {length(derived_audits)}"))
message(glue("Output directory: {output_dir}"))
message("")
for (name in names(audit_results)) {
  message(glue("  {name}: {format(nrow(audit_results[[name]]), big.mark=',')} audit rows"))
}
if (length(derived_audits) > 0) {
  for (name in names(derived_audits)) {
    message(glue("  {name}: {format(nrow(derived_audits[[name]]), big.mark=',')} audit rows"))
  }
}

message("\n", strrep("=", 60))
message("Done. Review CSVs in output/tables/value_audit/ for coding consistency.")
message(strrep("=", 60))

# ==============================================================================
# End of script
# ==============================================================================
