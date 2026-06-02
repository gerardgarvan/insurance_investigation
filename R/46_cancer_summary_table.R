# ==============================================================================
# 46_cancer_summary_table.R
# ==============================================================================
# Purpose: Category-level and code-level cancer summary aggregation with styled
#          xlsx output for clinical review. High-level companion to cancer_summary.xlsx
#          providing aggregate picture without patient-level detail.
#
# Inputs:  output/tables/cancer_summary.csv (Phase 45 patient-code level dataset)
#          DIAGNOSIS DuckDB table (for record counts)
#
# Outputs: output/tables/cancer_summary_table.xlsx (two-sheet styled workbook)
#          - Sheet 1 "Category Summary": one row per cancer site category
#          - Sheet 2 "Code Summary": one row per unique ICD-10 code
#
# Dependencies: R/00_config.R, R/01_load_pcornet.R, CANCER_SITE_MAP (R/00_config.R),
#               classify_codes() (R/utils/utils_cancer.R)
#
# Requirements: Aggregate patient counts, confirmation rates, date distribution,
#               encounter volume at both category and code levels
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP ----
# ==============================================================================
# WHY both category-level and code-level aggregation: Category gives broad overview
#   of cancer burden by site (e.g., all lung cancers), code-level gives clinical
#   specificity for review (e.g., NSCLC vs SCLC subtypes).
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")

# SECTION 0: INPUT VALIDATION ----
# SAFE-02: Validate DIAGNOSIS table is available
assert_df_valid(
  pcornet$DIAGNOSIS, "DIAGNOSIS",
  required_cols = c("ID", "DX", "DX_TYPE"),
  script_name = "R/46"
)

OUTPUT_PATH <- build_output_path("tables", "cancer_summary_table.xlsx")

message("=== Phase 7: Cancer Summary Table ===")
message(glue("Output: {OUTPUT_PATH}"))

# CANCER_SITE_MAP and classify_codes() provided by R/00_config.R + R/utils/utils_cancer.R

message(glue("Defined {length(unique(CANCER_SITE_MAP))} cancer site categories covering {length(CANCER_SITE_MAP)} prefixes"))

# ==============================================================================
# SECTION 3: LOAD SOURCE DATA ----
# ==============================================================================
# Read Phase 6 output (patient-code level dataset)

INPUT_CSV <- file.path(CONFIG$output_dir, "tables", "cancer_summary.csv")

# SAFE-01: Validate input CSV exists
checkmate::assert_file_exists(INPUT_CSV, access = "r",
  .var.name = glue("[R/46 ERROR] Cancer summary CSV -- run R/45 first"))

message(glue("\nLoading Phase 6 data from {INPUT_CSV}..."))

cancer_summary <- read.csv(INPUT_CSV, stringsAsFactors = FALSE)
message(glue("  Loaded {format(nrow(cancer_summary), big.mark=',')} patient-code rows"))

# Classify codes to add category column
cancer_summary$category <- classify_codes(cancer_summary$cancer_code)

# Handle unclassified codes
n_unclassified <- sum(is.na(cancer_summary$category))
if (n_unclassified > 0) {
  unclass_codes <- unique(cancer_summary$cancer_code[is.na(cancer_summary$category)])
  message(glue("  WARNING: {n_unclassified} rows ({length(unclass_codes)} unique codes) unclassified"))
  message(glue("    Codes: {paste(head(unclass_codes, 20), collapse=', ')}"))
  cancer_summary$category[is.na(cancer_summary$category)] <- "Unclassified"
}

message(glue("  Unique patients: {format(n_distinct(cancer_summary$ID), big.mark=',')}"))
message(glue("  Unique codes: {format(n_distinct(cancer_summary$cancer_code), big.mark=',')}"))
message(glue("  Categories: {n_distinct(cancer_summary$category)}"))

# ==============================================================================
# SECTION 4: QUERY RECORD COUNTS FROM DIAGNOSIS (DUCKDB) ----
# ==============================================================================
# Per D-07: record counts are total DIAGNOSIS rows, not unique dates.

message("\nQuerying DIAGNOSIS for record counts...")

dx_record_counts <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^[CD]")) %>%
  group_by(DX_norm) %>%
  summarise(record_count = n(), .groups = "drop") %>%
  collect()

message(glue("  Found record counts for {nrow(dx_record_counts)} unique codes"))

# Join record counts to patient-level data
cancer_summary <- cancer_summary %>%
  left_join(dx_record_counts, by = c("cancer_code" = "DX_norm")) %>%
  mutate(record_count = ifelse(is.na(record_count), 0L, as.integer(record_count)))

message(glue("  Total records across all codes: {format(sum(cancer_summary$record_count), big.mark=',')}"))

# ==============================================================================
# SECTION 5: CATEGORY-LEVEL AGGREGATION ----
# ==============================================================================
# Per D-01, D-02, D-04, D-05, D-06, D-07, D-14

message("\nAggregating to category level...")

category_summary <- cancer_summary %>%
  group_by(category) %>%
  summarise(
    total_patients = n_distinct(ID),
    confirmed_2date = n_distinct(ID[two_or_more_unique_dates == 1]),
    pct_confirmed_2date = n_distinct(ID[two_or_more_unique_dates == 1]) / n_distinct(ID),
    confirmed_7day = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]),
    pct_confirmed_7day = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]) / n_distinct(ID),
    mean_unique_dates = mean(unique_dates_total, na.rm = TRUE),
    median_unique_dates = median(unique_dates_total, na.rm = TRUE),
    mean_dates_7day_sep = mean(unique_dates_with_sep_gt_7, na.rm = TRUE),
    median_dates_7day_sep = median(unique_dates_with_sep_gt_7, na.rm = TRUE),
    total_records = sum(record_count, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(total_patients))

message(glue("  Category summary: {nrow(category_summary)} rows"))

# ==============================================================================
# SECTION 6: CODE-LEVEL AGGREGATION ----
# ==============================================================================
# Per D-01, D-03: same metrics grouped by cancer_code + category

message("Aggregating to code level...")

code_summary <- cancer_summary %>%
  group_by(cancer_code, category) %>%
  summarise(
    total_patients = n_distinct(ID),
    confirmed_2date = n_distinct(ID[two_or_more_unique_dates == 1]),
    pct_confirmed_2date = n_distinct(ID[two_or_more_unique_dates == 1]) / n_distinct(ID),
    confirmed_7day = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]),
    pct_confirmed_7day = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]) / n_distinct(ID),
    mean_unique_dates = mean(unique_dates_total, na.rm = TRUE),
    median_unique_dates = median(unique_dates_total, na.rm = TRUE),
    mean_dates_7day_sep = mean(unique_dates_with_sep_gt_7, na.rm = TRUE),
    median_dates_7day_sep = median(unique_dates_with_sep_gt_7, na.rm = TRUE),
    total_records = sum(record_count, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(total_patients))

message(glue("  Code summary: {nrow(code_summary)} rows"))

# ==============================================================================
# SECTION 7: BUILD TOTALS ROWS ----
# ==============================================================================
# Follow R/50 pattern: sum counts, NA for rates/means

totals_category <- tibble(
  category              = "TOTAL",
  total_patients        = sum(category_summary$total_patients),
  confirmed_2date       = sum(category_summary$confirmed_2date),
  pct_confirmed_2date   = NA_real_,
  confirmed_7day        = sum(category_summary$confirmed_7day),
  pct_confirmed_7day    = NA_real_,
  mean_unique_dates     = NA_real_,
  median_unique_dates   = NA_real_,
  mean_dates_7day_sep   = NA_real_,
  median_dates_7day_sep = NA_real_,
  total_records         = sum(category_summary$total_records)
)

totals_code <- tibble(
  cancer_code           = "TOTAL",
  category              = "",
  total_patients        = sum(code_summary$total_patients),
  confirmed_2date       = sum(code_summary$confirmed_2date),
  pct_confirmed_2date   = NA_real_,
  confirmed_7day        = sum(code_summary$confirmed_7day),
  pct_confirmed_7day    = NA_real_,
  mean_unique_dates     = NA_real_,
  median_unique_dates   = NA_real_,
  mean_dates_7day_sep   = NA_real_,
  median_dates_7day_sep = NA_real_,
  total_records         = sum(code_summary$total_records)
)

# ==============================================================================
# SECTION 8: WRITE STYLED XLSX ----
# ==============================================================================
# Per D-08, D-09: two-sheet xlsx with dark header styling matching R/40, R/43

message(glue("\nWriting styled xlsx to {OUTPUT_PATH}..."))

# Styling constants (same as R/50)
DARK_HEADER_FILL <- "FF374151"
WHITE_FONT <- "FFFFFFFF"
TITLE_FONT_COLOR <- "FF1F2937"
TOTALS_FILL <- "FFE5E7EB"

wb <- wb_workbook()

# ---------------------------------------------------------------------------
# Sheet 1: "Category Summary"
# ---------------------------------------------------------------------------
SHEET1 <- "Category Summary"
wb$add_worksheet(SHEET1)

# Row 1: Title
wb$add_data(
  sheet = SHEET1, x = "Cancer Summary Table - By Category",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = SHEET1, dims = "A1",
  name = "Calibri", size = 16, bold = TRUE,
  color = wb_color(TITLE_FONT_COLOR)
)
wb$merge_cells(sheet = SHEET1, dims = "A1:K1")

# Row 2: Headers
headers1 <- c(
  "Cancer Site Category",
  "Total Patients",
  "Confirmed (2+ Dates)",
  "Rate (2+ Dates)",
  "Confirmed (7-Day Gap)",
  "Rate (7-Day Gap)",
  "Mean Unique Dates",
  "Median Unique Dates",
  "Mean Dates (7-Day Sep)",
  "Median Dates (7-Day Sep)",
  "Total Records"
)
for (i in seq_along(headers1)) {
  wb$add_data(sheet = SHEET1, x = headers1[i], start_row = 2, start_col = i)
}
wb$add_fill(sheet = SHEET1, dims = "A2:K2", color = wb_color(DARK_HEADER_FILL))
wb$add_font(
  sheet = SHEET1, dims = "A2:K2",
  name = "Calibri", size = 11, bold = TRUE,
  color = wb_color(WHITE_FONT)
)

# Freeze pane
wb$freeze_pane(sheet = SHEET1, first_active_row = 3, first_active_col = 1)

# Data rows starting at row 3
data_start1 <- 3
n_data1 <- nrow(category_summary)
data_end1 <- data_start1 + n_data1 - 1

wb$add_data(
  sheet = SHEET1, x = as.data.frame(category_summary),
  start_row = data_start1, col_names = FALSE
)

# Number formatting
# Columns B, C, E (integer counts): "#,##0"
wb$add_numfmt(sheet = SHEET1, dims = glue("B{data_start1}:B{data_end1}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET1, dims = glue("C{data_start1}:C{data_end1}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET1, dims = glue("E{data_start1}:E{data_end1}"), numfmt = "#,##0")
# Columns D, F (percentage rates): "0.0%"
wb$add_numfmt(sheet = SHEET1, dims = glue("D{data_start1}:D{data_end1}"), numfmt = "0.0%")
wb$add_numfmt(sheet = SHEET1, dims = glue("F{data_start1}:F{data_end1}"), numfmt = "0.0%")
# Columns G, H, I, J (mean/median decimals): "0.0"
wb$add_numfmt(sheet = SHEET1, dims = glue("G{data_start1}:G{data_end1}"), numfmt = "0.0")
wb$add_numfmt(sheet = SHEET1, dims = glue("H{data_start1}:H{data_end1}"), numfmt = "0.0")
wb$add_numfmt(sheet = SHEET1, dims = glue("I{data_start1}:I{data_end1}"), numfmt = "0.0")
wb$add_numfmt(sheet = SHEET1, dims = glue("J{data_start1}:J{data_end1}"), numfmt = "0.0")
# Column K (total records): "#,##0"
wb$add_numfmt(sheet = SHEET1, dims = glue("K{data_start1}:K{data_end1}"), numfmt = "#,##0")

# Totals row
totals_row1 <- data_end1 + 1
wb$add_data(
  sheet = SHEET1, x = as.data.frame(totals_category),
  start_row = totals_row1, col_names = FALSE
)
wb$add_fill(
  sheet = SHEET1,
  dims = glue("A{totals_row1}:K{totals_row1}"),
  color = wb_color(TOTALS_FILL)
)
wb$add_font(
  sheet = SHEET1,
  dims = glue("A{totals_row1}:K{totals_row1}"),
  name = "Calibri", size = 11, bold = TRUE,
  color = wb_color(TITLE_FONT_COLOR)
)
wb$add_numfmt(
  sheet = SHEET1,
  dims = glue("B{totals_row1}:B{totals_row1}"),
  numfmt = "#,##0"
)
wb$add_numfmt(
  sheet = SHEET1,
  dims = glue("C{totals_row1}:C{totals_row1}"),
  numfmt = "#,##0"
)
wb$add_numfmt(
  sheet = SHEET1,
  dims = glue("E{totals_row1}:E{totals_row1}"),
  numfmt = "#,##0"
)
wb$add_numfmt(
  sheet = SHEET1,
  dims = glue("K{totals_row1}:K{totals_row1}"),
  numfmt = "#,##0"
)

# Column widths
wb$set_col_widths(
  sheet = SHEET1, cols = 1:11,
  widths = c(40, 14, 18, 14, 18, 14, 16, 16, 18, 18, 14)
)

# ---------------------------------------------------------------------------
# Sheet 2: "Code Summary"
# ---------------------------------------------------------------------------
SHEET2 <- "Code Summary"
wb$add_worksheet(SHEET2)

# Row 1: Title
wb$add_data(
  sheet = SHEET2, x = "Cancer Summary Table - By ICD-10 Code",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = SHEET2, dims = "A1",
  name = "Calibri", size = 16, bold = TRUE,
  color = wb_color(TITLE_FONT_COLOR)
)
wb$merge_cells(sheet = SHEET2, dims = "A1:L1")

# Row 2: Headers
headers2 <- c(
  "ICD-10 Code",
  "Cancer Site Category",
  "Total Patients",
  "Confirmed (2+ Dates)",
  "Rate (2+ Dates)",
  "Confirmed (7-Day Gap)",
  "Rate (7-Day Gap)",
  "Mean Unique Dates",
  "Median Unique Dates",
  "Mean Dates (7-Day Sep)",
  "Median Dates (7-Day Sep)",
  "Total Records"
)
for (i in seq_along(headers2)) {
  wb$add_data(sheet = SHEET2, x = headers2[i], start_row = 2, start_col = i)
}
wb$add_fill(sheet = SHEET2, dims = "A2:L2", color = wb_color(DARK_HEADER_FILL))
wb$add_font(
  sheet = SHEET2, dims = "A2:L2",
  name = "Calibri", size = 11, bold = TRUE,
  color = wb_color(WHITE_FONT)
)

# Freeze pane
wb$freeze_pane(sheet = SHEET2, first_active_row = 3, first_active_col = 1)

# Data rows starting at row 3
data_start2 <- 3
n_data2 <- nrow(code_summary)
data_end2 <- data_start2 + n_data2 - 1

wb$add_data(
  sheet = SHEET2, x = as.data.frame(code_summary),
  start_row = data_start2, col_names = FALSE
)

# Number formatting
# Columns C, D, F (integer counts): "#,##0"
wb$add_numfmt(sheet = SHEET2, dims = glue("C{data_start2}:C{data_end2}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET2, dims = glue("D{data_start2}:D{data_end2}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET2, dims = glue("F{data_start2}:F{data_end2}"), numfmt = "#,##0")
# Columns E, G (percentage rates): "0.0%"
wb$add_numfmt(sheet = SHEET2, dims = glue("E{data_start2}:E{data_end2}"), numfmt = "0.0%")
wb$add_numfmt(sheet = SHEET2, dims = glue("G{data_start2}:G{data_end2}"), numfmt = "0.0%")
# Columns H, I, J, K (mean/median decimals): "0.0"
wb$add_numfmt(sheet = SHEET2, dims = glue("H{data_start2}:H{data_end2}"), numfmt = "0.0")
wb$add_numfmt(sheet = SHEET2, dims = glue("I{data_start2}:I{data_end2}"), numfmt = "0.0")
wb$add_numfmt(sheet = SHEET2, dims = glue("J{data_start2}:J{data_end2}"), numfmt = "0.0")
wb$add_numfmt(sheet = SHEET2, dims = glue("K{data_start2}:K{data_end2}"), numfmt = "0.0")
# Column L (total records): "#,##0"
wb$add_numfmt(sheet = SHEET2, dims = glue("L{data_start2}:L{data_end2}"), numfmt = "#,##0")

# Totals row
totals_row2 <- data_end2 + 1
wb$add_data(
  sheet = SHEET2, x = as.data.frame(totals_code),
  start_row = totals_row2, col_names = FALSE
)
wb$add_fill(
  sheet = SHEET2,
  dims = glue("A{totals_row2}:L{totals_row2}"),
  color = wb_color(TOTALS_FILL)
)
wb$add_font(
  sheet = SHEET2,
  dims = glue("A{totals_row2}:L{totals_row2}"),
  name = "Calibri", size = 11, bold = TRUE,
  color = wb_color(TITLE_FONT_COLOR)
)
wb$add_numfmt(
  sheet = SHEET2,
  dims = glue("C{totals_row2}:C{totals_row2}"),
  numfmt = "#,##0"
)
wb$add_numfmt(
  sheet = SHEET2,
  dims = glue("D{totals_row2}:D{totals_row2}"),
  numfmt = "#,##0"
)
wb$add_numfmt(
  sheet = SHEET2,
  dims = glue("F{totals_row2}:F{totals_row2}"),
  numfmt = "#,##0"
)
wb$add_numfmt(
  sheet = SHEET2,
  dims = glue("L{totals_row2}:L{totals_row2}"),
  numfmt = "#,##0"
)

# Column widths
wb$set_col_widths(
  sheet = SHEET2, cols = 1:12,
  widths = c(14, 40, 14, 18, 14, 18, 14, 16, 16, 18, 18, 14)
)

# ---------------------------------------------------------------------------
# Save workbook
# ---------------------------------------------------------------------------
wb$save(OUTPUT_PATH)

message(glue("\nWrote {OUTPUT_PATH}"))
message(glue("  Sheet '{SHEET1}': {n_data1} data rows + 1 totals row"))
message(glue("  Sheet '{SHEET2}': {n_data2} data rows + 1 totals row"))

# ==============================================================================
# SECTION 9: CLEANUP ----
# ==============================================================================

close_pcornet_con()

message("\n=== Phase 7 complete ===")
