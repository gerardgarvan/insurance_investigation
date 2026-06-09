# ==============================================================================
# 47_cancer_summary_refined.R
# ==============================================================================
# Purpose: Refined cancer summary: removes D-codes (in-situ/benign), enforces HL
#          cohort confirmation status, computes first HL diagnosis date per patient.
#          Consolidates R/45+R/46 output generation into single source of truth.
#
# Inputs:  output/tables/cancer_summary.csv (Phase 45 output from R/45)
#          DIAGNOSIS DuckDB table (C81 cohort confirmation, record counts)
#          TUMOR_REGISTRY_ALL DuckDB table (first HL diagnosis date)
#
# Outputs: output/tables/cancer_summary.csv (overwritten: D-codes removed, HL cohort only)
#          output/tables/cancer_summary.xlsx (overwritten: single flat sheet)
#          output/tables/cancer_summary_table.xlsx (overwritten: two-sheet styled workbook)
#          output/confirmed_hl_cohort.rds (for Phase 56, 57 consumption)
#
# Dependencies: R/00_config.R, R/01_load_pcornet.R, CANCER_SITE_MAP (R/00_config.R),
#               classify_codes() (R/utils/utils_cancer.R)
#
# Requirements: CREF-01: Remove D-codes (in-situ/benign neoplasms) and ICD-9 210-239
#               CREF-02: Filter to patients with 2+ HL codes (C81 + 201.x) 7+ days apart
#               CREF-03: Compute first HL diagnosis date (DIAGNOSIS + TUMOR_REGISTRY)
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP ----
# ==============================================================================
# WHY D-codes are removed: D-codes (D00-D48) represent in-situ, benign, and
#   uncertain-behavior neoplasms -- clinically distinct from invasive cancer (C-codes).
#   Removing D-codes focuses the summary on malignant neoplasms only.
#
# WHY HL cohort confirmation is enforced: Ensures only patients meeting cohort
#   criteria (2+ C81 codes 7+ days apart) are included in refined summary, eliminating
#   incidental or rule-out HL diagnoses.
#
# WHY first HL diagnosis date is computed: Anchor point for temporal analysis in
#   downstream scripts (R/48 post-HL, R/49 pre/post partitioning).
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(openxlsx2)
  library(lubridate)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")
source("R/utils/utils_cancer.R")

# SECTION 0: INPUT VALIDATION ----
# SAFE-02: Validate DIAGNOSIS table is available
assert_df_valid(
  pcornet$DIAGNOSIS, "DIAGNOSIS",
  required_cols = c("ID", "DX", "DX_TYPE", "DX_DATE"),
  script_name = "R/47"
)

# Define output paths
INPUT_CSV <- file.path(CONFIG$output_dir, "tables", "cancer_summary.csv")
OUTPUT_CSV <- build_output_path("tables", "cancer_summary.csv")
OUTPUT_XLSX <- build_output_path("tables", "cancer_summary.xlsx")
OUTPUT_TABLE_XLSX <- build_output_path("tables", "cancer_summary_table.xlsx")
OUTPUT_RDS <- file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds")

message("=== Phase 8: Cancer Summary Refined (D-code removal + HL cohort confirmation) ===")
message(glue("Input CSV:  {INPUT_CSV}"))
message(glue("Output CSV: {OUTPUT_CSV}"))
message(glue("Output XLSX: {OUTPUT_XLSX}"))
message(glue("Output Table XLSX: {OUTPUT_TABLE_XLSX}"))
message(glue("Output RDS: {OUTPUT_RDS}"))

# CANCER_SITE_MAP and classify_codes() provided by R/00_config.R + R/utils/utils_cancer.R
# All 309 entries including D-codes are needed because classify_codes() is called
# on the input data before D-code filtering.

message(glue("Defined {length(unique(CANCER_SITE_MAP))} cancer site categories covering {length(CANCER_SITE_MAP)} prefixes"))

# ==============================================================================
# SECTION 3: LOAD AND FILTER INPUT DATA (CREF-01)
# ==============================================================================

# SAFE-01: Validate input CSV exists
checkmate::assert_file_exists(INPUT_CSV, access = "r",
  .var.name = glue("[R/47 ERROR] Cancer summary CSV -- run R/45 first"))

message(glue("\nLoading {INPUT_CSV}..."))

cancer_summary <- read.csv(INPUT_CSV, stringsAsFactors = FALSE)
n_loaded <- nrow(cancer_summary)
message(glue("  Loaded {format(n_loaded, big.mark=',')} patient-code rows"))

# Remove ICD-10 D-codes (per CREF-01) and ICD-9 benign/uncertain/in-situ (210-239, per D-02)
# is_cancer_code() upstream already excludes these, but defense-in-depth prevents data leaks
n_before_dcode_removal <- nrow(cancer_summary)
cancer_summary <- cancer_summary %>%
  filter(!str_detect(cancer_code, "^D")) %>%
  filter(!substr(cancer_code, 1, 3) %in% as.character(210:239))
n_removed_dcodes <- n_before_dcode_removal - nrow(cancer_summary)

message(glue("Removed {format(n_removed_dcodes, big.mark=',')} D-code rows ({format(nrow(cancer_summary), big.mark=',')} remaining)"))
message(glue("  Unique patients after D-code removal: {format(n_distinct(cancer_summary$ID), big.mark=',')}"))
message(glue("  Unique codes after D-code removal: {format(n_distinct(cancer_summary$cancer_code), big.mark=',')}"))

# ==============================================================================
# SECTION 4: COHORT CONFIRMATION -- C81 codes, 7-day gap (CREF-02)
# ==============================================================================

message("\nQuerying DIAGNOSIS for HL cohort confirmation (C81 + 201.x)...")

# Query all HL diagnosis codes: ICD-10 C81 + ICD-9 201.x (per D-09)
dx_hl <- get_pcornet_table("DIAGNOSIS") %>%
  select(ID, DX, DX_TYPE, DX_DATE) %>%
  collect() %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^C81") | str_detect(DX_norm, "^201"))

message(glue("  Found {format(nrow(dx_hl), big.mark=',')} HL diagnosis rows (C81 + 201.x)"))

# Deduplicate before date span calculation (Pitfall 1)
# Group by ID only (not per sub-code) -- different HL sub-codes (C81.x + 201.x) count toward threshold together (per D-10)
confirmed_patients <- dx_hl %>%
  filter(!is.na(DX_DATE)) %>%
  distinct(ID, DX_DATE) %>%
  group_by(ID) %>%
  filter(as.numeric(max(DX_DATE) - min(DX_DATE)) >= 7) %>%
  ungroup() %>%
  distinct(ID)

message(glue("Confirmed HL cohort: {format(nrow(confirmed_patients), big.mark=',')} patients (2+ C81/201.x codes, 7-day gap)"))

# ==============================================================================
# SECTION 5: COMPUTE FIRST HL DIAGNOSIS DATE (CREF-03)
# ==============================================================================

message("\nComputing first HL diagnosis date from DIAGNOSIS and TUMOR_REGISTRY...")

# DIAGNOSIS earliest HL date per patient (C81 + 201.x, reuse dx_hl from Section 4)
dx_dates <- dx_hl %>%
  filter(!is.na(DX_DATE)) %>%
  group_by(ID) %>%
  summarise(first_dx_date_diagnosis = min(DX_DATE, na.rm = TRUE), .groups = "drop")

message(glue("  DIAGNOSIS: {format(nrow(dx_dates), big.mark=',')} patients with HL dates (C81 + 201.x)"))

# TUMOR_REGISTRY earliest DATE_OF_DIAGNOSIS per patient
tr_tbl <- tryCatch(get_pcornet_table("TUMOR_REGISTRY_ALL"), error = function(e) NULL)
if (!is.null(tr_tbl) && "DATE_OF_DIAGNOSIS" %in% colnames(tr_tbl)) {
  tr_dates <- tr_tbl %>%
    filter(!is.na(DATE_OF_DIAGNOSIS)) %>%
    group_by(ID) %>%
    summarise(first_dx_date_tr = min(DATE_OF_DIAGNOSIS, na.rm = TRUE), .groups = "drop") %>%
    collect()
  message(glue("  TUMOR_REGISTRY: {format(nrow(tr_dates), big.mark=',')} patients with diagnosis dates"))
} else {
  tr_dates <- data.frame(ID = character(), first_dx_date_tr = as.Date(character()), stringsAsFactors = FALSE)
  message("  TUMOR_REGISTRY: table not found or missing DATE_OF_DIAGNOSIS column")
}

# Compute TRUE minimum with source attribution (per D-05)
first_dx <- dx_dates %>%
  full_join(tr_dates, by = "ID") %>%
  mutate(
    first_hl_dx_date = pmin(first_dx_date_diagnosis, first_dx_date_tr, na.rm = TRUE),
    first_hl_dx_source = case_when(
      is.na(first_dx_date_diagnosis) & !is.na(first_dx_date_tr) ~ "TUMOR_REGISTRY",
      !is.na(first_dx_date_diagnosis) & is.na(first_dx_date_tr) ~ "DIAGNOSIS",
      !is.na(first_dx_date_diagnosis) & !is.na(first_dx_date_tr) &
        first_dx_date_diagnosis == first_dx_date_tr ~ "Both",
      !is.na(first_dx_date_diagnosis) & !is.na(first_dx_date_tr) &
        first_dx_date_diagnosis < first_dx_date_tr ~ "DIAGNOSIS",
      !is.na(first_dx_date_diagnosis) & !is.na(first_dx_date_tr) &
        first_dx_date_tr < first_dx_date_diagnosis ~ "TUMOR_REGISTRY",
      TRUE ~ NA_character_
    )
  ) %>%
  select(ID, first_hl_dx_date, first_hl_dx_source) %>%
  collect()

# Nullify 1900 sentinel dates (Pitfall 3)
n_sentinel <- sum(year(first_dx$first_hl_dx_date) == 1900L, na.rm = TRUE)
if (n_sentinel > 0) {
  message(glue("  Nullifying {n_sentinel} sentinel first-diagnosis dates (year 1900)"))
  first_dx <- first_dx %>%
    mutate(first_hl_dx_date = if_else(year(first_hl_dx_date) == 1900L, as.Date(NA), first_hl_dx_date))
}

# Log source distribution
source_dist <- first_dx %>%
  filter(!is.na(first_hl_dx_source)) %>%
  count(first_hl_dx_source, name = "n_patients")
message("  First HL diagnosis source distribution:")
for (i in seq_len(nrow(source_dist))) {
  message(glue("    {source_dist$first_hl_dx_source[i]}: {format(source_dist$n_patients[i], big.mark=',')}"))
}

# ==============================================================================
# SECTION 6: SAVE CONFIRMED HL COHORT RDS (D-10)
# ==============================================================================

# Inner join confirmed_patients with first_dx to get only confirmed patients with their dates
confirmed_hl_cohort <- confirmed_patients %>%
  inner_join(first_dx, by = "ID") %>%
  select(ID, first_hl_dx_date, first_hl_dx_source)

saveRDS(confirmed_hl_cohort, OUTPUT_RDS)
message(glue("\nSaved confirmed HL cohort to {OUTPUT_RDS} ({nrow(confirmed_hl_cohort)} patients)"))

# ==============================================================================
# SECTION 7: FILTER CANCER SUMMARY TO CONFIRMED COHORT
# ==============================================================================

n_patients_before_cohort_filter <- n_distinct(cancer_summary$ID)
n_rows_before_cohort_filter <- nrow(cancer_summary)

# Inner join to keep only confirmed HL cohort patients
cancer_summary <- cancer_summary %>%
  inner_join(confirmed_patients, by = "ID")

n_patients_after_cohort_filter <- n_distinct(cancer_summary$ID)
n_rows_after_cohort_filter <- nrow(cancer_summary)

message(glue("\nFiltered to confirmed HL cohort:"))
message(glue("  Patients: {format(n_patients_before_cohort_filter, big.mark=',')} -> {format(n_patients_after_cohort_filter, big.mark=',')}"))
message(glue("  Rows: {format(n_rows_before_cohort_filter, big.mark=',')} -> {format(n_rows_after_cohort_filter, big.mark=',')}"))

# Add category column via classify_codes()
cancer_summary$category <- classify_codes(cancer_summary$cancer_code)

# Handle unclassified codes
n_unclassified <- sum(is.na(cancer_summary$category))
if (n_unclassified > 0) {
  unclass_codes <- unique(cancer_summary$cancer_code[is.na(cancer_summary$category)])
  message(glue("  WARNING: {n_unclassified} rows ({length(unclass_codes)} unique codes) unclassified"))
  message(glue("    Codes: {paste(head(unclass_codes, 20), collapse=', ')}"))
  cancer_summary$category[is.na(cancer_summary$category)] <- "Unclassified"
}

# ==============================================================================
# SECTION 8: QUERY RECORD COUNTS FROM DIAGNOSIS (DuckDB)
# ==============================================================================

message("\nQuerying DIAGNOSIS for record counts...")

# Record counts query: all cancer codes (ICD-9 + ICD-10)
dx_record_counts <- get_pcornet_table("DIAGNOSIS") %>%
  select(ID, DX, DX_TYPE) %>%
  collect() %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(is_cancer_code(DX)) %>%
  filter(!str_detect(DX_norm, "^D")) %>%
  filter(!substr(DX_norm, 1, 3) %in% as.character(210:239)) %>%
  group_by(DX_norm) %>%
  summarise(record_count = n(), .groups = "drop")

message(glue("  Found record counts for {nrow(dx_record_counts)} unique codes"))

# Left join record counts to cancer_summary
cancer_summary <- cancer_summary %>%
  left_join(dx_record_counts, by = c("cancer_code" = "DX_norm")) %>%
  mutate(record_count = ifelse(is.na(record_count), 0L, as.integer(record_count)))

message(glue("  Total records across all codes: {format(sum(cancer_summary$record_count), big.mark=',')}"))

# ==============================================================================
# SECTION 9: CATEGORY-LEVEL AGGREGATION
# ==============================================================================

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
# SECTION 10: CODE-LEVEL AGGREGATION
# ==============================================================================

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

# Build totals rows
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
# SECTION 11: WRITE OUTPUTS
# ==============================================================================

message(glue("\nWriting outputs..."))

# -----------------------------------------------
# 11a. Write cancer_summary.csv (7-column format)
# -----------------------------------------------
cancer_summary_output <- cancer_summary %>%
  select(
    ID,
    cancer_code,
    description,
    two_or_more_unique_dates,
    two_or_more_unique_dates_gt_7,
    unique_dates_total,
    unique_dates_with_sep_gt_7
  )

write.csv(cancer_summary_output, OUTPUT_CSV, row.names = FALSE)
message(glue("  Wrote {OUTPUT_CSV} ({nrow(cancer_summary_output)} rows)"))

# -----------------------------------------------
# 11b. Write cancer_summary.xlsx (single flat sheet)
# -----------------------------------------------
wb_flat <- wb_workbook()
wb_flat$add_worksheet("Cancer Summary")

# Write data with headers
wb_flat$add_data(
  sheet = "Cancer Summary", x = as.data.frame(cancer_summary_output),
  start_row = 1, col_names = TRUE
)

# Integer number format for columns 4-7
if (nrow(cancer_summary_output) > 0) {
  last_row <- 1 + nrow(cancer_summary_output)
  wb_flat$add_numfmt(
    sheet = "Cancer Summary",
    dims = glue("D2:G{last_row}"), numfmt = "0"
  )
}

# Auto column widths
wb_flat$set_col_widths(sheet = "Cancer Summary", cols = 1:7, widths = "auto")

# Freeze top row
wb_flat$freeze_pane(sheet = "Cancer Summary", first_row = TRUE)

wb_flat$save(OUTPUT_XLSX)
message(glue("  Wrote {OUTPUT_XLSX}"))

# -----------------------------------------------
# 11c. Write cancer_summary_table.xlsx (two-sheet styled workbook)
# -----------------------------------------------

# Styling constants (same as R/54)
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
wb$save(OUTPUT_TABLE_XLSX)

message(glue("  Wrote {OUTPUT_TABLE_XLSX}"))
message(glue("    Sheet '{SHEET1}': {n_data1} data rows + 1 totals row"))
message(glue("    Sheet '{SHEET2}': {n_data2} data rows + 1 totals row"))

# ==============================================================================
# SECTION 12: CLEANUP
# ==============================================================================

close_pcornet_con()

# ==============================================================================
# SECTION 2: OUTPUT ----
# ==============================================================================

message("\n=== Phase 8 complete ===")
