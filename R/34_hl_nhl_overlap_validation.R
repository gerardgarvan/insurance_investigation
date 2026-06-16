# ==============================================================================
# 34_hl_nhl_overlap_validation.R -- HL+NHL Overlap Validation (OVERLAP-01)
# ==============================================================================
#
# Purpose:
#   Validates HL+NHL dual-code patient data quality by extending R/78's 3-way Venn
#   analysis with patient-level temporal detail. Addresses team meeting concern G4
#   about ~4,000/8,000 dual-code rate -- investigates whether same-day coding is
#   primary driver vs genuine sequential diagnoses. Standalone investigation script
#   producing meeting-ready xlsx with temporal pattern analysis.
#
# Inputs:
#   - output/confirmed_hl_cohort.rds (from R/47 via R/20)
#     Columns: ID, first_hl_dx_date, first_hl_dx_source
#   - DuckDB DIAGNOSIS table (via get_pcornet_table)
#     For all HL and NHL diagnosis codes
#
# Outputs:
#   - output/hl_nhl_overlap_validation.xlsx (three-sheet meeting-presentable xlsx)
#     Sheet 1 "Summary": Counts and temporal pattern breakdown
#     Sheet 2 "Patient Detail": Per-patient temporal data (first dx dates, days between)
#     Sheet 3 "Pattern Analysis": Grouped statistics and data quality assessment
#
# Phase 105 Decisions (HL+NHL Overlap Validation):
#   D-07: Patient-level temporal detail (first HL dx, first NHL dx, days between, same-day flag)
#   D-08: Temporal categorization (same-day, <30d, 30-180d, >180d) for pattern analysis
#   D-09: Three-tab xlsx output (Summary, Patient Detail, Pattern Analysis)
#   D-10: Report-only -- no modifications to existing scripts
#   D-11: Raw counts without HIPAA suppression (manual suppression before sharing)
#
# Dependencies:
#   - R/00_config.R (CONFIG paths)
#   - R/utils/utils_assertions.R (assert_rds_exists, assert_df_valid)
#   - R/utils/utils_duckdb.R (get_pcornet_table)
#   - R/utils/utils_dates.R (parse_pcornet_date, if available)
#
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP AND CONFIGURATION ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(lubridate)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/utils/utils_assertions.R")
source("R/utils/utils_duckdb.R")

USE_DUCKDB <- TRUE
open_pcornet_con()

# Try to source utils_dates.R for parse_pcornet_date (graceful fallback if missing)
if (file.exists("R/utils/utils_dates.R")) {
  source("R/utils/utils_dates.R")
} else {
  # Fallback: define simple date parser
  parse_pcornet_date <- function(date_col) {
    lubridate::ymd(date_col, quiet = TRUE)
  }
}

# --- Define file paths ---
INPUT_COHORT <- file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds")
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "hl_nhl_overlap_validation.xlsx")

message("=== R/34: HL+NHL Overlap Validation (OVERLAP-01) ===")
message()
message(glue("  Cohort RDS: {INPUT_COHORT}"))
message(glue("  Output:     {OUTPUT_XLSX}"))
message()


# ==============================================================================
# SECTION 2: INPUT VALIDATION AND DATA LOADING ----
# ==============================================================================

message("--- Input validation and data loading ---")

# Validate cohort file exists
assert_rds_exists(INPUT_COHORT, script_name = "R/34")

# Load confirmed HL cohort (from R/47 via R/20)
# Columns: ID, first_hl_dx_date, first_hl_dx_source
cohort <- readRDS(INPUT_COHORT)

# Validate expected columns exist
assert_df_valid(cohort, "confirmed_hl_cohort", c("ID", "first_hl_dx_date"), "R/34")

# Total cohort is denominator for percentages
total_cohort <- nrow(cohort)
message(glue("  Loaded confirmed HL cohort: {format(total_cohort, big.mark=',')} patients"))

message()


# ==============================================================================
# SECTION 3: QUERY HL AND NHL DIAGNOSES ----
# ==============================================================================

message("--- Querying HL and NHL diagnoses from DIAGNOSIS table ---")

# Define patterns (same as R/78)
NHL_ICD10_PATTERN <- "^C8[2-6]"
NHL_ICD9_PATTERN <- "^(200|202)"

# Query all HL diagnoses from DuckDB
# ICD-10: C81 (all subtypes)
# ICD-9: 201 (all subtypes)
hl_dx <- get_pcornet_table("DIAGNOSIS") %>%
  filter((DX_TYPE == "10" & str_detect(DX, "^C81")) |
         (DX_TYPE == "09" & str_detect(DX, "^201"))) %>%
  select(ID, DX, DX_TYPE, DX_DATE) %>%
  collect() %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\.")))

message(glue("  Found {format(nrow(hl_dx), big.mark=',')} HL diagnosis records for {format(n_distinct(hl_dx$ID), big.mark=',')} patients"))

# Query all NHL diagnoses from DuckDB
# ICD-10: C82-C86 (follicular, non-follicular, mature T/NK-cell, other NHL, etc.)
# ICD-9: 200 (lymphosarcoma/reticulosarcoma), 202 (other malignant lymphoid/histiocytic)
nhl_dx <- get_pcornet_table("DIAGNOSIS") %>%
  filter((DX_TYPE == "10" & str_detect(DX, "^C8[2-6]")) |
         (DX_TYPE == "09" & str_detect(DX, "^(200|202)"))) %>%
  select(ID, DX, DX_TYPE, DX_DATE) %>%
  collect() %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\.")))

message(glue("  Found {format(nrow(nhl_dx), big.mark=',')} NHL diagnosis records for {format(n_distinct(nhl_dx$ID), big.mark=',')} patients"))

message()


# ==============================================================================
# SECTION 4: IDENTIFY DUAL-CODE PATIENTS AND COMPUTE TEMPORAL DETAIL ----
# ==============================================================================

message("--- Identifying dual-code patients and computing temporal detail ---")

# Parse dates
hl_dx <- hl_dx %>%
  mutate(DX_DATE = parse_pcornet_date(DX_DATE))

nhl_dx <- nhl_dx %>%
  mutate(DX_DATE = parse_pcornet_date(DX_DATE))

# Get first dx date per patient per type (per D-07)
hl_first <- hl_dx %>%
  filter(!is.na(DX_DATE)) %>%
  group_by(ID) %>%
  summarise(
    first_hl_dx = min(DX_DATE, na.rm = TRUE),
    hl_dx_count = n(),
    .groups = "drop"
  )

nhl_first <- nhl_dx %>%
  filter(!is.na(DX_DATE)) %>%
  group_by(ID) %>%
  summarise(
    first_nhl_dx = min(DX_DATE, na.rm = TRUE),
    nhl_dx_count = n(),
    .groups = "drop"
  )

message(glue("  HL patients with valid first dx date: {format(nrow(hl_first), big.mark=',')}"))
message(glue("  NHL patients with valid first dx date: {format(nrow(nhl_first), big.mark=',')}"))

# Identify dual-code patients via inner join
dual_code <- hl_first %>%
  inner_join(nhl_first, by = "ID") %>%
  mutate(
    # Pitfall 3 guard: Use abs() for symmetric days_between
    days_between = as.numeric(abs(first_hl_dx - first_nhl_dx)),
    same_day = (days_between == 0),
    hl_first = (first_hl_dx < first_nhl_dx),
    nhl_first = (first_nhl_dx < first_hl_dx),
    # Temporal categorization per D-08
    temporal_category = case_when(
      same_day ~ "Same day",
      days_between < 30 ~ "<30 days apart",
      days_between < 180 ~ "30-180 days apart",
      TRUE ~ ">180 days apart"
    )
  )

message(glue("  Dual-code patients (HL + NHL): {format(nrow(dual_code), big.mark=',')} of {format(nrow(hl_first), big.mark=',')} HL patients"))
message(glue("    Dual-code rate: {sprintf('%.1f%%', 100 * nrow(dual_code) / nrow(hl_first))}"))

message()


# ==============================================================================
# SECTION 5: PATTERN ANALYSIS AND SUMMARIES ----
# ==============================================================================

message("--- Building pattern summaries ---")

# Pattern summary (temporal buckets per D-08)
pattern_summary <- dual_code %>%
  group_by(temporal_category) %>%
  summarise(
    n_patients = n(),
    pct_of_dual = sprintf("%.1f%%", 100 * n() / nrow(dual_code)),
    median_days = median(days_between),
    min_days = min(days_between),
    max_days = max(days_between),
    .groups = "drop"
  ) %>%
  arrange(factor(temporal_category, levels = c("Same day", "<30 days apart", "30-180 days apart", ">180 days apart")))

message("  Temporal pattern breakdown:")
for (i in seq_len(nrow(pattern_summary))) {
  message(glue("    {pattern_summary$temporal_category[i]}: {pattern_summary$n_patients[i]} patients ({pattern_summary$pct_of_dual[i]})"))
}

# Direction summary (who was diagnosed first)
direction_summary <- dual_code %>%
  summarise(
    total_dual = n(),
    same_day = sum(same_day),
    hl_diagnosed_first = sum(hl_first, na.rm = TRUE),
    nhl_diagnosed_first = sum(nhl_first, na.rm = TRUE)
  )

message(glue("  Same-day diagnoses: {direction_summary$same_day} ({sprintf('%.1f%%', 100 * direction_summary$same_day / direction_summary$total_dual)})"))
message(glue("  HL diagnosed first: {direction_summary$hl_diagnosed_first}"))
message(glue("  NHL diagnosed first: {direction_summary$nhl_diagnosed_first}"))

# Overall summary (for Summary tab)
overall_summary <- tibble(
  Metric = c(
    "Total HL patients (confirmed cohort)",
    "Total patients with NHL codes",
    "Dual-code patients (HL + NHL)",
    "Dual-code rate (of HL cohort)",
    "Same-day diagnoses",
    "Same-day rate (of dual-code)"
  ),
  Value = c(
    as.character(total_cohort),
    as.character(n_distinct(nhl_first$ID)),
    as.character(nrow(dual_code)),
    sprintf("%.1f%%", 100 * nrow(dual_code) / total_cohort),
    as.character(sum(dual_code$same_day)),
    sprintf("%.1f%%", 100 * sum(dual_code$same_day) / nrow(dual_code))
  )
)

message()


# ==============================================================================
# SECTION 6: CREATE STYLED XLSX ----
# ==============================================================================

message("--- Creating styled xlsx output ---")

wb <- wb_workbook()

# ==============================================================================
# Sheet 1: Summary ----
# ==============================================================================

wb$add_worksheet("Summary")

# Title row (Calibri 16pt bold, dark gray)
wb$add_data(sheet = "Summary", x = "HL+NHL Dual-Code Overlap Validation", start_row = 1, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A1", name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Summary", dims = "A1:B1")

# Subtitle row 2
wb$add_data(sheet = "Summary", x = glue("Generated: {Sys.Date()} | Confirmed HL Cohort: {format(total_cohort, big.mark=',')} patients"), start_row = 2, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A2", name = "Calibri", size = 10, color = wb_color("FF6B7280"))
wb$merge_cells(sheet = "Summary", dims = "A2:B2")

# Blank row 3

# Sub-header row 4: Overall Metrics
wb$add_data(sheet = "Summary", x = "Overall Metrics", start_row = 4, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A4", name = "Calibri", size = 14, bold = TRUE)

# Header row 5
overall_headers <- c("Metric", "Value")
for (i in seq_along(overall_headers)) {
  wb$add_data(sheet = "Summary", x = overall_headers[i], start_row = 5, start_col = i)
}
wb$add_fill(sheet = "Summary", dims = "A5:B5", color = wb_color("FF374151"))
wb$add_font(sheet = "Summary", dims = "A5:B5", name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Data rows 6-11
wb$add_data(sheet = "Summary", x = overall_summary, start_row = 6, col_names = FALSE)

# Skip row 12, sub-header row 13: Temporal Pattern Breakdown
wb$add_data(sheet = "Summary", x = "Temporal Pattern Breakdown", start_row = 13, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A13", name = "Calibri", size = 14, bold = TRUE)

# Header row 14
pattern_headers <- c("Temporal Category", "N Patients", "Pct of Dual", "Median Days", "Min Days", "Max Days")
for (i in seq_along(pattern_headers)) {
  wb$add_data(sheet = "Summary", x = pattern_headers[i], start_row = 14, start_col = i)
}
wb$add_fill(sheet = "Summary", dims = "A14:F14", color = wb_color("FF374151"))
wb$add_font(sheet = "Summary", dims = "A14:F14", name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Data rows 15+
wb$add_data(sheet = "Summary", x = pattern_summary, start_row = 15, col_names = FALSE)

# Freeze pane below first header row
wb$freeze_pane(sheet = "Summary", firstActiveRow = 6)

# Column widths
wb$set_col_widths(sheet = "Summary", cols = 1:6, widths = c(40, 20, 15, 15, 12, 12))


# ==============================================================================
# Sheet 2: Patient Detail ----
# ==============================================================================

wb$add_worksheet("Patient Detail")

# Title row
wb$add_data(sheet = "Patient Detail", x = "Dual-Code Patient Detail -- Temporal Analysis", start_row = 1, start_col = 1)
wb$add_font(sheet = "Patient Detail", dims = "A1", name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Patient Detail", dims = "A1:J1")

# Blank row 2, header row 3
detail_headers <- c("ID", "First_HL_Dx", "First_NHL_Dx", "Days_Between", "Same_Day", "HL_First", "NHL_First", "Temporal_Category", "HL_Dx_Count", "NHL_Dx_Count")
for (i in seq_along(detail_headers)) {
  wb$add_data(sheet = "Patient Detail", x = detail_headers[i], start_row = 3, start_col = i)
}
wb$add_fill(sheet = "Patient Detail", dims = "A3:J3", color = wb_color("FF374151"))
wb$add_font(sheet = "Patient Detail", dims = "A3:J3", name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Data rows (sort by days_between ascending -- same-day first per D-07)
dual_code_sorted <- dual_code %>%
  arrange(days_between) %>%
  select(ID, first_hl_dx, first_nhl_dx, days_between, same_day, hl_first, nhl_first, temporal_category, hl_dx_count, nhl_dx_count)

if (nrow(dual_code_sorted) > 0) {
  wb$add_data(sheet = "Patient Detail", x = dual_code_sorted, start_row = 4, col_names = FALSE)
}

# Freeze pane
wb$freeze_pane(sheet = "Patient Detail", firstActiveRow = 4)

# Column widths
wb$set_col_widths(sheet = "Patient Detail", cols = 1:10, widths = c(15, 12, 12, 12, 10, 10, 10, 20, 12, 12))


# ==============================================================================
# Sheet 3: Pattern Analysis ----
# ==============================================================================

wb$add_worksheet("Pattern Analysis")

# Title row
wb$add_data(sheet = "Pattern Analysis", x = "Temporal Pattern Analysis -- Grouped Statistics", start_row = 1, start_col = 1)
wb$add_font(sheet = "Pattern Analysis", dims = "A1", name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Pattern Analysis", dims = "A1:F1")

# Blank row 2

# Sub-header row 3: Temporal Distribution
wb$add_data(sheet = "Pattern Analysis", x = "Temporal Distribution", start_row = 3, start_col = 1)
wb$add_font(sheet = "Pattern Analysis", dims = "A3", name = "Calibri", size = 14, bold = TRUE)

# Header row 4
pattern_headers2 <- c("Temporal Category", "N Patients", "Pct of Dual", "Median Days", "Min Days", "Max Days")
for (i in seq_along(pattern_headers2)) {
  wb$add_data(sheet = "Pattern Analysis", x = pattern_headers2[i], start_row = 4, start_col = i)
}
wb$add_fill(sheet = "Pattern Analysis", dims = "A4:F4", color = wb_color("FF374151"))
wb$add_font(sheet = "Pattern Analysis", dims = "A4:F4", name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Data rows 5+
wb$add_data(sheet = "Pattern Analysis", x = pattern_summary, start_row = 5, col_names = FALSE)

# Skip row after pattern_summary, sub-header: Direction of First Diagnosis
next_row <- 5 + nrow(pattern_summary) + 2
wb$add_data(sheet = "Pattern Analysis", x = "Direction of First Diagnosis", start_row = next_row, start_col = 1)
wb$add_font(sheet = "Pattern Analysis", dims = glue("A{next_row}"), name = "Calibri", size = 14, bold = TRUE)

# Direction summary table
next_row <- next_row + 1
direction_headers <- c("Metric", "Count")
for (i in seq_along(direction_headers)) {
  wb$add_data(sheet = "Pattern Analysis", x = direction_headers[i], start_row = next_row, start_col = i)
}
wb$add_fill(sheet = "Pattern Analysis", dims = glue("A{next_row}:B{next_row}"), color = wb_color("FF374151"))
wb$add_font(sheet = "Pattern Analysis", dims = glue("A{next_row}:B{next_row}"), name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

next_row <- next_row + 1
direction_data <- tibble(
  Metric = c("Total dual-code patients", "Same-day diagnoses", "HL diagnosed first", "NHL diagnosed first"),
  Count = c(direction_summary$total_dual, direction_summary$same_day, direction_summary$hl_diagnosed_first, direction_summary$nhl_diagnosed_first)
)
wb$add_data(sheet = "Pattern Analysis", x = direction_data, start_row = next_row, col_names = FALSE)

# Data Quality Assessment text block
next_row <- next_row + nrow(direction_data) + 2
wb$add_data(sheet = "Pattern Analysis", x = "Data Quality Assessment", start_row = next_row, start_col = 1)
wb$add_font(sheet = "Pattern Analysis", dims = glue("A{next_row}"), name = "Calibri", size = 14, bold = TRUE)

next_row <- next_row + 1
same_day_pct <- 100 * sum(dual_code$same_day) / nrow(dual_code)
assessment_text <- if (same_day_pct > 50) {
  glue("Majority of dual codes ({sprintf('%.1f%%', same_day_pct)}) occur on the same encounter day, suggesting potential coding quality concern (same-encounter bilateral coding).")
} else {
  glue("Dual codes are temporally distributed (same-day: {sprintf('%.1f%%', same_day_pct)}), suggesting many represent genuine sequential diagnoses.")
}
wb$add_data(sheet = "Pattern Analysis", x = assessment_text, start_row = next_row, start_col = 1)
wb$merge_cells(sheet = "Pattern Analysis", dims = glue("A{next_row}:F{next_row}"))

# Freeze pane
wb$freeze_pane(sheet = "Pattern Analysis", firstActiveRow = 5)

# Column widths
wb$set_col_widths(sheet = "Pattern Analysis", cols = 1:6, widths = c(25, 15, 15, 15, 12, 12))


# ==============================================================================
# Save workbook ----
# ==============================================================================

wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)
message(glue("  Saved: {OUTPUT_XLSX}"))
message()


# ==============================================================================
# SECTION 7: FINAL SUMMARY ----
# ==============================================================================

message("=== R/34 HL+NHL Overlap Validation Complete ===")
message()
message("Dual-code patient summary:")
message(glue("  Total dual-code patients: {format(nrow(dual_code), big.mark=',')} of {format(total_cohort, big.mark=',')} confirmed HL patients"))
message(glue("  Dual-code rate: {sprintf('%.1f%%', 100 * nrow(dual_code) / total_cohort)}"))
message()
message("Temporal pattern breakdown:")
for (i in seq_len(nrow(pattern_summary))) {
  message(glue("  {pattern_summary$temporal_category[i]}: {format(pattern_summary$n_patients[i], big.mark=',')} patients ({pattern_summary$pct_of_dual[i]})"))
}
message()
message(glue("Same-day percentage: {sprintf('%.1f%%', same_day_pct)} (KEY FINDING -- {if (same_day_pct > 50) 'majority' else 'minority'} of dual codes)"))
message()
message(glue("Output file: {OUTPUT_XLSX}"))

close_pcornet_con()
message("Done.")
