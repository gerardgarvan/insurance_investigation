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
csv_columns_path <- here("csv_columns.txt")
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
    # Exclude _VALID validation columns added by load_pcornet_table() (Phase 6, Plan 02)
    extra_in_data <- setdiff(actual_cols, spec_cols)
    extra_in_data <- extra_in_data[!str_detect(extra_in_data, "_VALID$")]
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
# SECTION 4: HL Identification Source Comparison -- Venn Breakdown (D-04, D-07, D-08, D-09)
# ==============================================================================

message("\n", strrep("-", 60))
message("SECTION 4: HL Identification Source Comparison")
message(strrep("-", 60))

# 1. DIAGNOSIS source: patients with HL diagnosis codes
dx_patients <- pcornet$DIAGNOSIS %>%
  filter(is_hl_diagnosis(DX, DX_TYPE)) %>%
  mutate(dx_icd_type = if_else(DX_TYPE == "10", "ICD-10", "ICD-9")) %>%
  group_by(ID) %>%
  summarise(
    has_dx_code = 1L,
    dx_icd_type = first(dx_icd_type),  # Take first match if multiple
    .groups = "drop"
  )

message(glue("DIAGNOSIS source: {nrow(dx_patients)} patients with HL diagnosis codes"))

# 2. TUMOR_REGISTRY source: patients with HL histology codes
tr_patients_list <- list()

# TR1: HISTOLOGICAL_TYPE
if (!is.null(pcornet$TUMOR_REGISTRY1) && "HISTOLOGICAL_TYPE" %in% names(pcornet$TUMOR_REGISTRY1)) {
  tr1_hl <- pcornet$TUMOR_REGISTRY1 %>%
    filter(is_hl_histology(HISTOLOGICAL_TYPE)) %>%
    select(ID) %>%
    mutate(tr_table = "TR1")
  tr_patients_list <- c(tr_patients_list, list(tr1_hl))
  message(glue("  TR1 (HISTOLOGICAL_TYPE): {nrow(tr1_hl)} patients"))
}

# TR2: MORPH
if (!is.null(pcornet$TUMOR_REGISTRY2) && "MORPH" %in% names(pcornet$TUMOR_REGISTRY2)) {
  tr2_hl <- pcornet$TUMOR_REGISTRY2 %>%
    filter(is_hl_histology(MORPH)) %>%
    select(ID) %>%
    mutate(tr_table = "TR2")
  tr_patients_list <- c(tr_patients_list, list(tr2_hl))
  message(glue("  TR2 (MORPH): {nrow(tr2_hl)} patients"))
}

# TR3: MORPH
if (!is.null(pcornet$TUMOR_REGISTRY3) && "MORPH" %in% names(pcornet$TUMOR_REGISTRY3)) {
  tr3_hl <- pcornet$TUMOR_REGISTRY3 %>%
    filter(is_hl_histology(MORPH)) %>%
    select(ID) %>%
    mutate(tr_table = "TR3")
  tr_patients_list <- c(tr_patients_list, list(tr3_hl))
  message(glue("  TR3 (MORPH): {nrow(tr3_hl)} patients"))
}

# Combine TR sources
if (length(tr_patients_list) > 0) {
  tr_patients <- bind_rows(tr_patients_list) %>%
    group_by(ID) %>%
    summarise(
      has_tr_code = 1L,
      tr_table = paste(unique(tr_table), collapse = "+"),  # Show which TR tables
      .groups = "drop"
    )
} else {
  tr_patients <- tibble(ID = character(), has_tr_code = integer(), tr_table = character())
}

message(glue("TUMOR_REGISTRY source: {nrow(tr_patients)} patients with HL histology codes"))

# 3. Full outer join against DEMOGRAPHIC (all patients)
hl_venn <- pcornet$DEMOGRAPHIC %>%
  select(ID, SOURCE) %>%
  left_join(dx_patients, by = "ID") %>%
  left_join(tr_patients, by = "ID") %>%
  mutate(
    has_dx_code = coalesce(has_dx_code, 0L),
    has_tr_code = coalesce(has_tr_code, 0L),
    hl_source = case_when(
      has_dx_code == 1 & has_tr_code == 1 ~ "Both DIAGNOSIS and TR",
      has_dx_code == 1 & has_tr_code == 0 ~ "DIAGNOSIS only",
      has_dx_code == 0 & has_tr_code == 1 ~ "TR only",
      TRUE ~ "Neither (data quality issue)"
    )
  )

# 4. Site-stratified breakdown (D-08)
message("\n=== HL Identification by Source and Site ===")
hl_venn_tabyl <- hl_venn %>%
  tabyl(SOURCE, hl_source) %>%
  adorn_totals(c("row", "col"))

print(hl_venn_tabyl)

# Write detailed output
hl_venn_summary <- hl_venn %>%
  count(SOURCE, hl_source, name = "n")

write_csv(hl_venn_summary, file.path(CONFIG$output_dir, "diagnostics", "hl_identification_venn.csv"))

hl_detail <- hl_venn %>%
  select(ID, SOURCE, has_dx_code, has_tr_code, hl_source, dx_icd_type, tr_table)

write_csv(hl_detail, file.path(CONFIG$output_dir, "diagnostics", "hl_identification_detail.csv"))

message(glue("\nWrote HL identification breakdown to hl_identification_venn.csv and hl_identification_detail.csv"))

# 5. Method breakdown (D-08)
message("\n=== HL Identification Method Breakdown ===")
dx_method <- dx_patients %>% count(dx_icd_type, name = "n")
message("DIAGNOSIS source by ICD type:")
for (i in 1:nrow(dx_method)) {
  message(glue("  {dx_method$dx_icd_type[i]}: {dx_method$n[i]}"))
}

tr_method <- tr_patients %>% count(tr_table, name = "n")
message("\nTUMOR_REGISTRY source by table:")
for (i in 1:nrow(tr_method)) {
  message(glue("  {tr_method$tr_table[i]}: {tr_method$n[i]}"))
}

# 6. Extract scope check (D-09)
n_neither <- sum(hl_venn$hl_source == "Neither (data quality issue)")
if (n_neither > 0) {
  message("\n", strrep("!", 60))
  message(glue("WARNING: {n_neither} patients in Mailhot HL extract have NO HL evidence"))
  message("in DIAGNOSIS or TUMOR_REGISTRY. This is unexpected for a pre-filtered HL cohort.")
  message(strrep("!", 60))
} else {
  message("\nExtract scope check: ALL patients have HL evidence in at least one source")
}

# 7. Check for excluded patients file (D-02, Phase 6 Plan 01)
excl_path <- file.path(CONFIG$output_dir, "cohort", "excluded_no_hl_evidence.csv")
if (file.exists(excl_path)) {
  excl_df <- read_csv(excl_path, show_col_types = FALSE)
  message(glue("\n  Excluded patients (Neither): {nrow(excl_df)} (written to excluded_no_hl_evidence.csv)"))
  if ("HL_SOURCE" %in% names(excl_df)) {
    message(glue("  HL_SOURCE values: {paste(unique(excl_df$HL_SOURCE), collapse = ', ')}"))
  }
} else {
  message("\n  No excluded patients file found (no 'Neither' patients excluded yet, or pipeline not yet rebuilt)")
}

# ==============================================================================
# SECTION 5: Payer Mapping Audit (D-20)
# ==============================================================================

message("\n", strrep("-", 60))
message("SECTION 5: Payer Mapping Audit")
message(strrep("-", 60))

# Check if payer_summary exists (from sourcing 02_harmonize_payer.R upstream)
if (!exists("payer_summary")) {
  payer_csv <- file.path(CONFIG$output_dir, "tables", "payer_summary.csv")
  if (file.exists(payer_csv)) {
    payer_summary <- read_csv(payer_csv, show_col_types = FALSE)
    message("  Loaded payer_summary from CSV")
  } else {
    message("  WARNING: payer_summary not found. Run 02_harmonize_payer.R first. Skipping payer audit.")
    payer_summary <- NULL
  }
}

if (!is.null(payer_summary)) {
  # 2. Category distribution
  category_dist <- payer_summary %>%
    filter(!is.na(PAYER_CATEGORY_PRIMARY)) %>%
    count(PAYER_CATEGORY_PRIMARY, name = "n_patients") %>%
    mutate(pct_of_total = round(100 * n_patients / sum(n_patients), 2)) %>%
    arrange(desc(n_patients))

  message("\n=== Payer Category Distribution ===")
  for (i in 1:nrow(category_dist)) {
    message(glue("  {category_dist$PAYER_CATEGORY_PRIMARY[i]}: {category_dist$n_patients[i]} ({category_dist$pct_of_total[i]}%)"))
  }

  # Check for missing expected categories
  expected_categories <- PAYER_MAPPING$categories
  found_categories <- category_dist$PAYER_CATEGORY_PRIMARY
  missing_categories <- setdiff(expected_categories, found_categories)
  if (length(missing_categories) > 0) {
    message(glue("\n  Missing categories: {paste(missing_categories, collapse = ', ')}"))
  } else {
    message("\n  All 9 expected categories are represented")
  }

  # 3. Dual-eligible validation
  n_dual <- sum(payer_summary$DUAL_ELIGIBLE == 1, na.rm = TRUE)
  n_medicare <- sum(payer_summary$PAYER_CATEGORY_PRIMARY == "Medicare", na.rm = TRUE)
  n_medicaid <- sum(payer_summary$PAYER_CATEGORY_PRIMARY == "Medicaid", na.rm = TRUE)
  medicare_medicaid_total <- n_medicare + n_medicaid

  message(glue("\n=== Dual-Eligible Validation ==="))
  message(glue("  Dual-eligible patients: {n_dual}"))
  if (medicare_medicaid_total > 0) {
    dual_pct <- round(100 * n_dual / medicare_medicaid_total, 1)
    message(glue("  Dual-eligible rate (% of Medicare+Medicaid): {dual_pct}%"))
    if (dual_pct < 10 || dual_pct > 20) {
      message(glue("  WARNING: Dual-eligible rate ({dual_pct}%) outside expected 10-20% range"))
    } else {
      message(glue("  Dual-eligible rate within expected 10-20% range"))
    }
  }

  # 4. Raw payer code distribution
  payer_raw_primary <- pcornet$ENCOUNTER %>%
    filter(!is.na(PAYER_TYPE_PRIMARY) & nchar(trimws(PAYER_TYPE_PRIMARY)) > 0) %>%
    count(PAYER_TYPE_PRIMARY, name = "n_encounters") %>%
    arrange(desc(n_encounters)) %>%
    mutate(field = "primary") %>%
    head(20)

  payer_raw_secondary <- pcornet$ENCOUNTER %>%
    filter(!is.na(PAYER_TYPE_SECONDARY) & nchar(trimws(PAYER_TYPE_SECONDARY)) > 0) %>%
    count(PAYER_TYPE_SECONDARY, name = "n_encounters") %>%
    arrange(desc(n_encounters)) %>%
    mutate(field = "secondary") %>%
    head(20)

  message("\n=== Top 20 Raw Payer Codes (Primary) ===")
  for (i in 1:min(20, nrow(payer_raw_primary))) {
    message(glue("  {payer_raw_primary$PAYER_TYPE_PRIMARY[i]}: {payer_raw_primary$n_encounters[i]} encounters"))
  }

  # 5. Unmapped codes check
  # Codes that don't match any prefix rule or exact-match override
  unmapped_codes <- pcornet$ENCOUNTER %>%
    filter(!is.na(PAYER_TYPE_PRIMARY) & nchar(trimws(PAYER_TYPE_PRIMARY)) > 0) %>%
    filter(
      !str_starts(PAYER_TYPE_PRIMARY, "1") &
      !str_starts(PAYER_TYPE_PRIMARY, "2") &
      !str_starts(PAYER_TYPE_PRIMARY, "3") &
      !str_starts(PAYER_TYPE_PRIMARY, "4") &
      !str_starts(PAYER_TYPE_PRIMARY, "5") &
      !str_starts(PAYER_TYPE_PRIMARY, "6") &
      !str_starts(PAYER_TYPE_PRIMARY, "7") &
      !str_starts(PAYER_TYPE_PRIMARY, "8") &
      !str_starts(PAYER_TYPE_PRIMARY, "9") &
      !PAYER_TYPE_PRIMARY %in% PAYER_MAPPING$unavailable_codes &
      !PAYER_TYPE_PRIMARY %in% PAYER_MAPPING$unknown_codes &
      !PAYER_TYPE_PRIMARY %in% PAYER_MAPPING$dual_eligible_codes
    ) %>%
    count(PAYER_TYPE_PRIMARY, name = "n_encounters") %>%
    arrange(desc(n_encounters))

  if (nrow(unmapped_codes) > 0) {
    message(glue("\n  WARNING: {nrow(unmapped_codes)} payer codes don't match any mapping rule:"))
    for (i in 1:min(10, nrow(unmapped_codes))) {
      message(glue("    {unmapped_codes$PAYER_TYPE_PRIMARY[i]}: {unmapped_codes$n_encounters[i]} encounters"))
    }
  } else {
    message("\n  All payer codes match at least one mapping rule")
  }

  # Write outputs
  write_csv(category_dist, file.path(CONFIG$output_dir, "diagnostics", "payer_mapping_audit.csv"))

  payer_raw_codes <- bind_rows(
    payer_raw_primary %>% rename(payer_type = PAYER_TYPE_PRIMARY),
    payer_raw_secondary %>% rename(payer_type = PAYER_TYPE_SECONDARY)
  )
  write_csv(payer_raw_codes, file.path(CONFIG$output_dir, "diagnostics", "payer_raw_codes.csv"))

  message(glue("\nWrote payer audit to payer_mapping_audit.csv and payer_raw_codes.csv"))
}

# ==============================================================================
# SECTION 6: Numeric Range Checks (D-18)
# ==============================================================================

message("\n", strrep("-", 60))
message("SECTION 6: Numeric Range Checks")
message(strrep("-", 60))

numeric_range_issues <- list()

# 1. Age checks (TR1, TR2, TR3)
for (table_name in c("TUMOR_REGISTRY1", "TUMOR_REGISTRY2", "TUMOR_REGISTRY3")) {
  if (!is.null(pcornet[[table_name]])) {
    df <- pcornet[[table_name]]

    # TR1: AGE_AT_DIAGNOSIS
    if (table_name == "TUMOR_REGISTRY1" && "AGE_AT_DIAGNOSIS" %in% names(df)) {
      age_col <- df$AGE_AT_DIAGNOSIS
      n_negative <- sum(age_col < 0, na.rm = TRUE)
      n_extreme <- sum(age_col > 120, na.rm = TRUE)

      if (n_negative > 0) {
        sample_vals <- paste(head(sort(age_col[age_col < 0]), 5), collapse = " | ")
        numeric_range_issues[[length(numeric_range_issues) + 1]] <- tibble(
          table = table_name,
          column = "AGE_AT_DIAGNOSIS",
          issue_type = "negative_age",
          n_affected = n_negative,
          sample_values = sample_vals
        )
      }

      if (n_extreme > 0) {
        sample_vals <- paste(head(sort(age_col[age_col > 120 & !is.na(age_col)]), 5), collapse = " | ")
        numeric_range_issues[[length(numeric_range_issues) + 1]] <- tibble(
          table = table_name,
          column = "AGE_AT_DIAGNOSIS",
          issue_type = "extreme_age",
          n_affected = n_extreme,
          sample_values = sample_vals
        )
      }
    }

    # TR2/TR3: DXAGE
    if (table_name %in% c("TUMOR_REGISTRY2", "TUMOR_REGISTRY3") && "DXAGE" %in% names(df)) {
      age_col <- df$DXAGE
      n_negative <- sum(age_col < 0, na.rm = TRUE)
      n_extreme <- sum(age_col > 120, na.rm = TRUE)

      if (n_negative > 0) {
        sample_vals <- paste(head(sort(age_col[age_col < 0]), 5), collapse = " | ")
        numeric_range_issues[[length(numeric_range_issues) + 1]] <- tibble(
          table = table_name,
          column = "DXAGE",
          issue_type = "negative_age",
          n_affected = n_negative,
          sample_values = sample_vals
        )
      }

      if (n_extreme > 0) {
        sample_vals <- paste(head(sort(age_col[age_col > 120 & !is.na(age_col)]), 5), collapse = " | ")
        numeric_range_issues[[length(numeric_range_issues) + 1]] <- tibble(
          table = table_name,
          column = "DXAGE",
          issue_type = "extreme_age",
          n_affected = n_extreme,
          sample_values = sample_vals
        )
      }
    }
  }
}

# 2. Date sanity (already covered in Section 1, but add explicit check summary)
# Re-use date_range_results from Section 1
if (length(date_range_results) > 0) {
  for (i in 1:length(date_range_results)) {
    dr <- date_range_results[[i]]
    if (dr$n_before_1900 > 0) {
      numeric_range_issues[[length(numeric_range_issues) + 1]] <- tibble(
        table = dr$table,
        column = dr$column,
        issue_type = "pre_1900_date",
        n_affected = dr$n_before_1900,
        sample_values = dr$min_date
      )
    }
    if (dr$n_future > 0) {
      numeric_range_issues[[length(numeric_range_issues) + 1]] <- tibble(
        table = dr$table,
        column = dr$column,
        issue_type = "future_date",
        n_affected = dr$n_future,
        sample_values = dr$max_date
      )
    }
  }
}

# 3. Tumor size checks (TR1 only)
if (!is.null(pcornet$TUMOR_REGISTRY1)) {
  df <- pcornet$TUMOR_REGISTRY1

  for (size_col in c("TUMOR_SIZE_SUMMARY", "TUMOR_SIZE_CLINICAL", "TUMOR_SIZE_PATHOLOGIC")) {
    if (size_col %in% names(df)) {
      size_vals <- df[[size_col]]
      n_negative <- sum(size_vals < 0, na.rm = TRUE)
      n_extreme <- sum(size_vals > 999, na.rm = TRUE)

      if (n_negative > 0) {
        sample_vals <- paste(head(sort(size_vals[size_vals < 0]), 5), collapse = " | ")
        numeric_range_issues[[length(numeric_range_issues) + 1]] <- tibble(
          table = "TUMOR_REGISTRY1",
          column = size_col,
          issue_type = "negative_size",
          n_affected = n_negative,
          sample_values = sample_vals
        )
      }

      if (n_extreme > 0) {
        sample_vals <- paste(head(sort(size_vals[size_vals > 999 & !is.na(size_vals)]), 5), collapse = " | ")
        numeric_range_issues[[length(numeric_range_issues) + 1]] <- tibble(
          table = "TUMOR_REGISTRY1",
          column = size_col,
          issue_type = "extreme_size",
          n_affected = n_extreme,
          sample_values = sample_vals
        )
      }
    }
  }
}

# 4. Summarize _VALID column results (Phase 6, Plan 02 validation columns)
message("\n=== Validation Column Summary (_VALID) ===")
valid_col_summary <- list()
for (tbl_name in names(pcornet)) {
  if (is.null(pcornet[[tbl_name]])) next
  valid_cols <- names(pcornet[[tbl_name]])[str_detect(names(pcornet[[tbl_name]]), "_VALID$")]
  for (vcol in valid_cols) {
    n_total <- sum(!is.na(pcornet[[tbl_name]][[vcol]]))
    n_invalid <- sum(!pcornet[[tbl_name]][[vcol]], na.rm = TRUE)
    n_valid <- sum(pcornet[[tbl_name]][[vcol]], na.rm = TRUE)
    if (n_total > 0) {
      valid_col_summary[[length(valid_col_summary) + 1]] <- tibble(
        table = tbl_name,
        column = vcol,
        n_valid = n_valid,
        n_invalid = n_invalid,
        n_na = nrow(pcornet[[tbl_name]]) - n_total,
        pct_invalid = round(100 * n_invalid / n_total, 2)
      )
      if (n_invalid > 0) {
        message(glue("  {tbl_name}.{vcol}: {n_invalid} invalid values ({round(100 * n_invalid / n_total, 1)}%)"))
      }
    }
  }
}

if (length(valid_col_summary) > 0) {
  valid_col_df <- bind_rows(valid_col_summary)
  write_csv(valid_col_df, file.path(CONFIG$output_dir, "diagnostics", "validation_column_summary.csv"))
  message(glue("  Wrote {nrow(valid_col_df)} validation column summaries to validation_column_summary.csv"))
} else {
  message("  No _VALID columns found (run pipeline with updated 01_load_pcornet.R first)")
}

# Write numeric range issues
if (length(numeric_range_issues) > 0) {
  numeric_range_df <- bind_rows(numeric_range_issues)
  write_csv(numeric_range_df, file.path(CONFIG$output_dir, "diagnostics", "numeric_range_issues.csv"))

  message(glue("\n=== Numeric Range Issues ==="))
  issue_summary <- numeric_range_df %>%
    count(issue_type, name = "n_occurrences") %>%
    arrange(desc(n_occurrences))

  for (i in 1:nrow(issue_summary)) {
    message(glue("  {issue_summary$issue_type[i]}: {issue_summary$n_occurrences[i]} occurrences"))
  }

  message(glue("\nWrote {nrow(numeric_range_df)} numeric range issues to numeric_range_issues.csv"))
} else {
  message("\nNo numeric range issues detected")
}

# ==============================================================================
# FOOTER
# ==============================================================================

message("\n", strrep("=", 60))
message("Diagnostics complete.")
message(glue("Results written to: {file.path(CONFIG$output_dir, 'diagnostics')}"))
message(strrep("=", 60))
