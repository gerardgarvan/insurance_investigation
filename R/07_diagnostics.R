# ==============================================================================
# 07_diagnostics.R -- Reusable data quality diagnostic script
# ==============================================================================
#
# Permanent diagnostic tool (per D-11) for auditing PCORnet CDM data quality.
# Produces BOTH console summaries (via message()) AND detailed CSVs in
# output/diagnostics/ (per D-12).
#
# Sections:
#   1. Date Parsing Failures Audit (D-01, D-02, D-03)
#   2. Column Detection Regex Audit (D-03)
#   3. Column Type and Missing Value Audit (D-15, D-16, D-17, D-19)
#   4. HL Identification Source Comparison (D-04, D-07, D-08, D-09)
#   5. Payer Mapping Audit (D-20)
#   6. Numeric Range Checks (D-18)
#
# Usage:
#   source("R/07_diagnostics.R")  # Runs all diagnostics
#   # Or: Rscript R/07_diagnostics.R
#
# Dependencies: Loads 01_load_pcornet.R (which loads 00_config.R + utils)
# ==============================================================================

source("R/01_load_pcornet.R")  # Loads data and config

library(dplyr)
library(readr)
library(stringr)
library(janitor)
library(glue)
library(here)

message(strrep("=", 60))
message("PCORnet Data Quality Diagnostics")
message(glue("Run date: {Sys.Date()}"))
message(strrep("=", 60))

# Create diagnostics output directory
dir.create(file.path(CONFIG$output_dir, "diagnostics"), showWarnings = FALSE, recursive = TRUE)

# ==============================================================================
# SECTION 1: Date Parsing Failures Audit (D-01, D-02)
# ==============================================================================

message("\n", strrep("-", 60))
message("SECTION 1: Date Parsing Failures Audit")
message(strrep("-", 60))

# Date detection regex from 01_load_pcornet.R
date_regex <- "(?i)(DATE|^DT_|^BDATE$|^DOD$|^DT_FU$|DXDATE|_DT$|RECUR_DT|COMBINED_LAST_CONTACT|ADDRESS_PERIOD_START|ADDRESS_PERIOD_END)"

# Initialize results containers
date_parse_results <- list()
date_range_results <- list()

# Process each loaded table
for (table_name in names(pcornet)) {
  if (is.null(pcornet[[table_name]])) {
    next  # Skip NULL tables (missing files)
  }

  df <- pcornet[[table_name]]

  # Find date columns by regex
  date_cols <- names(df)[str_detect(names(df), date_regex)]

  if (length(date_cols) == 0) {
    next
  }

  message(glue("\n{table_name}: {length(date_cols)} date columns found"))

  # Audit each date column
  for (col in date_cols) {
    n_total <- nrow(df)
    col_data <- df[[col]]

    # Check if parsed as Date
    if (inherits(col_data, "Date")) {
      n_na <- sum(is.na(col_data))
      na_pct <- round(100 * n_na / n_total, 2)

      # Record parse failure metrics
      date_parse_results[[length(date_parse_results) + 1]] <- tibble(
        table = table_name,
        column = col,
        type_detected = "Date",
        n_total = n_total,
        n_na = n_na,
        na_percent = na_pct,
        sample_raw_values = NA_character_
      )

      # Check date ranges (sanity bounds)
      non_na_dates <- col_data[!is.na(col_data)]
      if (length(non_na_dates) > 0) {
        n_before_1900 <- sum(non_na_dates < as.Date("1900-01-01"))
        n_future <- sum(non_na_dates > Sys.Date())
        min_date <- min(non_na_dates, na.rm = TRUE)
        max_date <- max(non_na_dates, na.rm = TRUE)

        if (n_before_1900 > 0 || n_future > 0) {
          date_range_results[[length(date_range_results) + 1]] <- tibble(
            table = table_name,
            column = col,
            n_before_1900 = n_before_1900,
            n_future = n_future,
            min_date = as.character(min_date),
            max_date = as.character(max_date)
          )
        }
      }

      message(glue("  {col}: Date type, {n_na} NAs ({na_pct}%)"))

    } else if (is.character(col_data)) {
      # Still character = parse failure
      n_na <- sum(is.na(col_data) | nchar(trimws(col_data)) == 0)
      na_pct <- round(100 * n_na / n_total, 2)

      # Sample unparsed values
      non_empty <- col_data[!is.na(col_data) & nchar(trimws(col_data)) > 0]
      sample_values <- if (length(non_empty) > 0) {
        paste(head(unique(non_empty), 5), collapse = " | ")
      } else {
        NA_character_
      }

      date_parse_results[[length(date_parse_results) + 1]] <- tibble(
        table = table_name,
        column = col,
        type_detected = "character",
        n_total = n_total,
        n_na = n_na,
        na_percent = na_pct,
        sample_raw_values = sample_values
      )

      message(glue("  {col}: character (PARSE FAILURE), {n_na} NAs ({na_pct}%)"))
    }
  }
}

# Write date parsing failures
date_parse_df <- bind_rows(date_parse_results)
if (nrow(date_parse_df) > 0) {
  write_csv(date_parse_df, file.path(CONFIG$output_dir, "diagnostics", "date_parsing_failures.csv"))
  message(glue("\nWrote {nrow(date_parse_df)} date column audits to date_parsing_failures.csv"))
}

# Write date range issues
date_range_df <- bind_rows(date_range_results)
if (nrow(date_range_df) > 0) {
  write_csv(date_range_df, file.path(CONFIG$output_dir, "diagnostics", "date_range_issues.csv"))
  message(glue("Wrote {nrow(date_range_df)} date range issues to date_range_issues.csv"))
}

# ==============================================================================
# SECTION 2: Column Detection Regex Audit (D-03)
# ==============================================================================

message("\n", strrep("-", 60))
message("SECTION 2: Column Detection Regex Audit")
message(strrep("-", 60))

# Read csv_columns.txt and extract all column names from all 22 tables
csv_columns_path <- "csv_columns.txt"
if (file.exists(csv_columns_path)) {
  csv_text <- readLines(csv_columns_path, warn = FALSE)

  # Parse table names and column names
  # Format: "File: TABLE_Mailhot_V1.csv" followed by "Columns:" then numbered lines

  regex_audit_results <- list()
  current_table <- NULL

  for (line in csv_text) {
    # Detect table name
    if (str_detect(line, "^File: ")) {
      table_match <- str_match(line, "File: ([A-Z_0-9]+)_Mailhot_V1\\.csv")
      if (!is.na(table_match[1, 2])) {
        current_table <- table_match[1, 2]
      }
    }

    # Detect column name (format: " 1. COLUMN_NAME" or "10. COLUMN_NAME")
    if (!is.null(current_table) && str_detect(line, "^\\s*\\d+\\.\\s+\\S+")) {
      col_match <- str_match(line, "^\\s*\\d+\\.\\s+(\\S+)")
      if (!is.na(col_match[1, 2])) {
        col_name <- col_match[1, 2]

        # Check if matches date regex
        regex_match <- str_detect(col_name, date_regex)

        regex_audit_results[[length(regex_audit_results) + 1]] <- tibble(
          table = current_table,
          column = col_name,
          regex_match = regex_match,
          notes = if_else(regex_match, "Matched date regex", "No match")
        )
      }
    }
  }

  regex_audit_df <- bind_rows(regex_audit_results)

  # Write audit
  write_csv(regex_audit_df, file.path(CONFIG$output_dir, "diagnostics", "date_column_regex_audit.csv"))

  n_matched <- sum(regex_audit_df$regex_match)
  n_total_cols <- nrow(regex_audit_df)
  message(glue("\nDate column regex audit:"))
  message(glue("  Total columns across 22 tables: {n_total_cols}"))
  message(glue("  Columns matching date regex: {n_matched}"))
  message(glue("  Columns NOT matching: {n_total_cols - n_matched}"))
  message(glue("  Wrote audit to date_column_regex_audit.csv"))

  # Identify potentially missed date columns (heuristic)
  unmatched <- regex_audit_df %>% filter(!regex_match)
  potential_dates <- unmatched %>%
    filter(str_detect(column, "(?i)(TIME|YEAR|AGE|PERIOD)"))

  if (nrow(potential_dates) > 0) {
    message(glue("\n  Potentially missed date/time columns ({nrow(potential_dates)}):"))
    for (i in 1:min(10, nrow(potential_dates))) {
      message(glue("    {potential_dates$table[i]}.{potential_dates$column[i]}"))
    }
  }
} else {
  message("WARNING: csv_columns.txt not found. Skipping regex audit.")
}

# ==============================================================================
# SECTION 3: Column Type and Missing Value Audit (D-15, D-16, D-17, D-19)
# ==============================================================================

message("\n", strrep("-", 60))
message("SECTION 3: Column Type and Missing Value Audit")
message(strrep("-", 60))

# Initialize results containers
column_discrepancy_results <- list()
missing_value_results <- list()
encoding_results <- list()
tr_type_audit_results <- list()

for (table_name in names(pcornet)) {
  if (is.null(pcornet[[table_name]])) {
    next
  }

  df <- pcornet[[table_name]]

  # D-15: Type mismatch check
  # Compare actual columns against spec
  spec <- TABLE_SPECS[[table_name]]

  if (!is.null(spec)) {
    spec_cols <- names(spec$cols)
    actual_cols <- names(df)

    # Columns in spec but missing from data
    missing_from_data <- setdiff(spec_cols, actual_cols)
    for (col in missing_from_data) {
      column_discrepancy_results[[length(column_discrepancy_results) + 1]] <- tibble(
        table = table_name,
        column = col,
        status = "missing_from_data",
        expected_type = class(spec$cols[[col]])[1],
        actual_type = NA_character_
      )
    }

    # Columns in data but not in spec
    extra_in_data <- setdiff(actual_cols, spec_cols)
    for (col in extra_in_data) {
      column_discrepancy_results[[length(column_discrepancy_results) + 1]] <- tibble(
        table = table_name,
        column = col,
        status = "extra_in_data",
        expected_type = NA_character_,
        actual_type = class(df[[col]])[1]
      )
    }
  }

  # D-17: Missing value audit (>10% threshold)
  for (col in names(df)) {
    n_total <- nrow(df)
    n_missing <- sum(is.na(df[[col]]) | (is.character(df[[col]]) & nchar(trimws(df[[col]])) == 0))
    pct_missing <- round(100 * n_missing / n_total, 2)

    if (pct_missing > 10) {
      missing_value_results[[length(missing_value_results) + 1]] <- tibble(
        table = table_name,
        column = col,
        type = class(df[[col]])[1],
        n_total = n_total,
        n_missing = n_missing,
        pct_missing = pct_missing
      )
    }
  }

  # D-17: Encoding check for character columns
  char_cols <- names(df)[sapply(df, is.character)]
  for (col in char_cols) {
    if (nrow(df) > 0) {
      # Check for non-ASCII
      non_ascii_count <- sum(str_detect(df[[col]], "[^\\x00-\\x7F]"), na.rm = TRUE)
      # Check first row for BOM
      first_val <- df[[col]][1]
      has_bom <- !is.na(first_val) && str_detect(first_val, "^\\xEF\\xBB\\xBF")

      if (non_ascii_count > 0 || has_bom) {
        encoding_results[[length(encoding_results) + 1]] <- tibble(
          table = table_name,
          column = col,
          non_ascii_count = non_ascii_count,
          has_bom = has_bom
        )
      }
    }
  }

  # D-19: TUMOR_REGISTRY type audit
  if (str_starts(table_name, "TUMOR_REGISTRY")) {
    char_cols <- names(df)[sapply(df, is.character)]

    for (col in char_cols) {
      # Sample first 100 non-NA values
      non_na_vals <- df[[col]][!is.na(df[[col]]) & nchar(trimws(df[[col]])) > 0]
      if (length(non_na_vals) > 0) {
        sample_size <- min(100, length(non_na_vals))
        sample <- head(non_na_vals, sample_size)

        # Check if numeric-like
        numeric_like <- sum(str_detect(sample, "^-?\\d+\\.?\\d*$"))
        pct_numeric <- round(100 * numeric_like / sample_size, 1)

        # Check if date-like (YYYY-MM-DD or DDMMMYYYY or YYYYMMDD or numeric >1000)
        date_like <- sum(str_detect(sample, "\\d{4}-\\d{2}-\\d{2}|\\d{2}[A-Z]{3}\\d{4}|^\\d{8}$") |
                         (str_detect(sample, "^\\d+$") & as.numeric(sample) > 1000 & as.numeric(sample) < 100000))
        pct_datelike <- round(100 * date_like / sample_size, 1)

        # Flag if >80% numeric or date-like
        if (pct_numeric > 80 || pct_datelike > 80) {
          recommendation <- if_else(pct_numeric > 80, "Consider col_double()", "Consider col_date()")

          tr_type_audit_results[[length(tr_type_audit_results) + 1]] <- tibble(
            table = table_name,
            column = col,
            current_type = "character",
            n_sampled = sample_size,
            pct_numeric = pct_numeric,
            pct_datelike = pct_datelike,
            recommendation = recommendation
          )
        }
      }
    }
  }
}

# Write results
if (length(column_discrepancy_results) > 0) {
  column_discrepancy_df <- bind_rows(column_discrepancy_results)
  write_csv(column_discrepancy_df, file.path(CONFIG$output_dir, "diagnostics", "column_discrepancies.csv"))
  message(glue("\nColumn discrepancies: {nrow(column_discrepancy_df)} issues found"))
  message(glue("  Wrote to column_discrepancies.csv"))
}

if (length(missing_value_results) > 0) {
  missing_value_df <- bind_rows(missing_value_results) %>% arrange(desc(pct_missing))
  write_csv(missing_value_df, file.path(CONFIG$output_dir, "diagnostics", "missing_values_audit.csv"))
  message(glue("\nMissing value audit: {nrow(missing_value_df)} columns with >10% missing"))
  message(glue("  Wrote to missing_values_audit.csv"))

  # Show top 5 most problematic columns
  top5 <- head(missing_value_df, 5)
  message("  Top 5 columns by missing rate:")
  for (i in 1:nrow(top5)) {
    message(glue("    {top5$table[i]}.{top5$column[i]}: {top5$pct_missing[i]}%"))
  }
}

if (length(encoding_results) > 0) {
  encoding_df <- bind_rows(encoding_results)
  write_csv(encoding_df, file.path(CONFIG$output_dir, "diagnostics", "encoding_issues.csv"))
  message(glue("\nEncoding issues: {nrow(encoding_df)} columns with non-ASCII or BOM"))
  message(glue("  Wrote to encoding_issues.csv"))
}

if (length(tr_type_audit_results) > 0) {
  tr_type_audit_df <- bind_rows(tr_type_audit_results)
  write_csv(tr_type_audit_df, file.path(CONFIG$output_dir, "diagnostics", "tr_type_audit.csv"))
  message(glue("\nTUMOR_REGISTRY type audit: {nrow(tr_type_audit_df)} columns flagged for type change"))
  message(glue("  Wrote to tr_type_audit.csv"))
}

# ==============================================================================
# End of Section 3 (Sections 4-6 to be added in Task 2)
# ==============================================================================

message("\n", strrep("=", 60))
message("Sections 1-3 complete (Task 1)")
message("Sections 4-6 will be added in Task 2")
message(strrep("=", 60))
