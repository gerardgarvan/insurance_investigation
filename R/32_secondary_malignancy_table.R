# ==============================================================================
# 32_secondary_malignancy_table.R -- Secondary Malignancy Table (TIMING-02)
# ==============================================================================
#
# Purpose:
#   Produce a secondary malignancy table for confirmed HL patients using 7-day
#   gap confirmation criterion for BOTH HL diagnosis AND secondary cancers.
#   Pre/post HL temporal split with population-based percentage columns. Answers
#   meeting gap requirement for secondary malignancy table (columns K-N based on
#   population E/E3). Standalone investigation script producing meeting-ready
#   xlsx output.
#
# Inputs:
#   - output/confirmed_hl_cohort.rds (from R/47 via R/20)
#     Columns: ID, first_hl_dx_date, first_hl_dx_source
#   - DuckDB DIAGNOSIS table (queried via get_pcornet_table)
#     For all non-HL cancer diagnoses
#
# Outputs:
#   - output/secondary_malignancy_table.xlsx (two-sheet meeting-presentable xlsx)
#     Sheet 1 "Summary": Counts by cancer category and timing (pre/post HL) with
#                        population-based percentages
#     Sheet 2 "Detail": Patient-level rows with diagnosis dates and timing classification
#
# Phase 104 Decisions (Secondary Malignancy Table):
#   D-04: Separate standalone output file (NOT an enhancement of R/49)
#   D-05: Population restricted to confirmed HL patients (7-day gap confirmation)
#   D-06: Secondary malignancies also require 7-day confirmation
#   D-07: Pre/post HL split with population-based percentages (total cohort as denominator)
#   D-08: Standalone investigation script (no upstream modification)
#   D-09: Raw counts without HIPAA suppression (manual suppression before sharing)
#
# Dependencies:
#   - R/00_config.R (CONFIG paths, CANCER_SITE_MAP, ICD9_CANCER_SITE_MAP)
#   - R/utils/utils_assertions.R (assert_rds_exists, assert_df_valid)
#   - R/utils/utils_cancer.R (is_cancer_code, classify_codes)
#   - R/utils/utils_duckdb.R (get_pcornet_table)
#   - R/utils/utils_dates.R (parse_pcornet_date)
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
source("R/utils/utils_cancer.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_dates.R")

USE_DUCKDB <- TRUE
open_pcornet_con()

# --- Define file paths ---
INPUT_COHORT <- file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds")
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "secondary_malignancy_table.xlsx")

message("=== R/32: Secondary Malignancy Table (TIMING-02) ===")
message()
message(glue("  Cohort RDS: {INPUT_COHORT}"))
message(glue("  Output:     {OUTPUT_XLSX}"))
message()


# ==============================================================================
# SECTION 2: INPUT VALIDATION AND DATA LOADING ----
# ==============================================================================

message("--- Input validation and data loading ---")

# Validate cohort file exists
assert_rds_exists(INPUT_COHORT, script_name = "R/32")

# Load confirmed HL cohort (from R/47 via R/20)
# Columns: ID, first_hl_dx_date, first_hl_dx_source
cohort <- readRDS(INPUT_COHORT)

# Per D-05, D-07: Total cohort size is denominator for ALL percentages
total_cohort <- nrow(cohort)
message(glue("  Loaded {format(total_cohort, big.mark=',')} confirmed HL patients"))

# Validate expected columns exist
assert_df_valid(cohort, "confirmed_hl_cohort", c("ID", "first_hl_dx_date"), "R/32")

message()


# ==============================================================================
# SECTION 3: QUERY NON-HL CANCER DIAGNOSES FROM DUCKDB ----
# ==============================================================================

message("--- Querying non-HL cancer diagnoses from DIAGNOSIS table ---")

# Query DuckDB DIAGNOSIS table for all diagnosis records
dx_raw <- get_pcornet_table("DIAGNOSIS") %>%
  select(ID, DX, DX_TYPE, DX_DATE) %>%
  collect()

message(glue("  Loaded {format(nrow(dx_raw), big.mark=',')} diagnosis records"))

# Normalize codes and filter to cancer codes
dx_cancer <- dx_raw %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(is_cancer_code(DX))

message(glue("  Cancer codes: {format(nrow(dx_cancer), big.mark=',')} rows"))

# CRITICAL (Pitfall 2): Exclude BOTH ICD-10 C81 and ICD-9 201 HL codes
# This prevents HL from appearing as a "secondary malignancy"
dx_non_hl <- dx_cancer %>%
  filter(!str_detect(DX_norm, "^C81|^201"))

message(glue("  Non-HL cancer codes: {format(nrow(dx_non_hl), big.mark=',')} rows"))

# Filter to confirmed HL cohort only (per D-05)
dx_cohort <- dx_non_hl %>%
  inner_join(cohort %>% select(ID), by = "ID")

message(glue("  Restricted to confirmed HL cohort: {format(nrow(dx_cohort), big.mark=',')} rows for {format(n_distinct(dx_cohort$ID), big.mark=',')} patients"))

# Parse dates
dx_cohort <- dx_cohort %>%
  mutate(DX_DATE = parse_pcornet_date(DX_DATE))

message()


# ==============================================================================
# SECTION 4: APPLY 7-DAY GAP CRITERION (D-06) ----
# ==============================================================================

message("--- Applying 7-day gap criterion for secondary malignancies ---")

# Per D-06: Secondary malignancies also require 7-day confirmation
# Copy R/45 lines 266-302 logic verbatim
confirmed_secondary <- dx_cohort %>%
  group_by(ID, DX_norm) %>%
  summarise(
    n_unique_dates = n_distinct(DX_DATE[!is.na(DX_DATE)]),
    confirmed = as.integer({
      dates <- DX_DATE[!is.na(DX_DATE)]
      ud <- unique(dates)
      if (length(ud) >= 2) {
        as.numeric(max(ud) - min(ud)) >= 7
      } else {
        FALSE
      }
    }),
    earliest_dx = min_or_na(DX_DATE),
    .groups = "drop"
  ) %>%
  filter(confirmed == 1L)

message(glue("  Confirmed {format(nrow(confirmed_secondary), big.mark=',')} secondary malignancy patient-code combinations across {format(n_distinct(confirmed_secondary$ID), big.mark=',')} patients"))

# Classify confirmed secondary cancers into site categories
confirmed_secondary <- confirmed_secondary %>%
  mutate(category = classify_codes(DX_norm))

# Count categories
n_with_category <- sum(!is.na(confirmed_secondary$category))
message(glue("  Classified into cancer site categories: {format(n_with_category, big.mark=',')} / {format(nrow(confirmed_secondary), big.mark=',')} codes"))

message()


# ==============================================================================
# SECTION 5: PRE/POST HL TEMPORAL SPLIT AND AGGREGATION (D-07) ----
# ==============================================================================

message("--- Pre/post HL temporal split and aggregation ---")

# Join to cohort for first_hl_dx_date
secondary_with_dx <- confirmed_secondary %>%
  inner_join(cohort %>% select(ID, first_hl_dx_date), by = "ID")

# Filter sentinel dates (Pitfall 5 guard)
secondary_with_dx <- secondary_with_dx %>%
  filter(!is.na(first_hl_dx_date), year(first_hl_dx_date) > 1900)

message(glue("  After sentinel date filtering: {format(nrow(secondary_with_dx), big.mark=',')} rows"))

# Split pre/post HL (per D-07): using earliest_dx date vs first_hl_dx_date
pre_hl <- secondary_with_dx %>%
  filter(earliest_dx < first_hl_dx_date)

post_hl <- secondary_with_dx %>%
  filter(earliest_dx >= first_hl_dx_date)

message(glue("  Pre-HL secondary cancers: {format(nrow(pre_hl), big.mark=',')} patient-code combinations ({format(n_distinct(pre_hl$ID), big.mark=',')} patients)"))
message(glue("  Post-HL secondary cancers: {format(nrow(post_hl), big.mark=',')} patient-code combinations ({format(n_distinct(post_hl$ID), big.mark=',')} patients)"))

# Build summary table with cancer category, timing, patient counts, percentages
summary_pre <- pre_hl %>%
  filter(!is.na(category)) %>%
  group_by(category) %>%
  summarise(
    timing = "Pre-HL",
    n_patients = n_distinct(ID),
    pct_of_cohort = n_distinct(ID) / total_cohort,
    .groups = "drop"
  )

summary_post <- post_hl %>%
  filter(!is.na(category)) %>%
  group_by(category) %>%
  summarise(
    timing = "Post-HL",
    n_patients = n_distinct(ID),
    pct_of_cohort = n_distinct(ID) / total_cohort,
    .groups = "drop"
  )

summary_table <- bind_rows(summary_pre, summary_post) %>%
  arrange(category, timing)

# Add total rows (per Pitfall 4 note: patients can appear in both pre and post)
total_pre <- tibble(
  category = "Any Secondary Cancer",
  timing = "Pre-HL",
  n_patients = n_distinct(pre_hl$ID),
  pct_of_cohort = n_distinct(pre_hl$ID) / total_cohort
)

total_post <- tibble(
  category = "Any Secondary Cancer",
  timing = "Post-HL",
  n_patients = n_distinct(post_hl$ID),
  pct_of_cohort = n_distinct(post_hl$ID) / total_cohort
)

total_any <- tibble(
  category = "Any Secondary Cancer",
  timing = "Any Timing",
  n_patients = n_distinct(secondary_with_dx$ID),
  pct_of_cohort = n_distinct(secondary_with_dx$ID) / total_cohort
)

summary_table <- bind_rows(summary_table, total_pre, total_post, total_any)

message(glue("  Summary table: {nrow(summary_table)} rows"))
message()


# ==============================================================================
# SECTION 6: CREATE STYLED XLSX ----
# ==============================================================================

message("--- Creating styled xlsx ---")

wb <- wb_workbook()

# --- Sheet 1: Summary ---
wb$add_worksheet("Summary")

# Title row (Calibri 16pt bold, dark gray)
wb$add_data(
  sheet = "Summary",
  x = "Secondary Malignancy Table -- Confirmed HL Cohort",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Summary", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Summary", dims = "A1:D1")

# Subtitle row (Calibri 10pt)
subtitle <- glue("Cohort Size: {format(total_cohort, big.mark=',')} confirmed HL patients | 7-day gap confirmation required for both HL and secondary cancers")
wb$add_data(
  sheet = "Summary",
  x = subtitle,
  start_row = 2, start_col = 1
)
wb$add_font(
  sheet = "Summary", dims = "A2",
  name = "Calibri", size = 10
)
wb$merge_cells(sheet = "Summary", dims = "A2:D2")

# Note row (Pitfall 4 documentation)
note <- "Note: Patients may appear in both Pre-HL and Post-HL rows (per meeting notes: split is per diagnosis, not per patient)"
wb$add_data(
  sheet = "Summary",
  x = note,
  start_row = 3, start_col = 1
)
wb$add_font(
  sheet = "Summary", dims = "A3",
  name = "Calibri", size = 10, italic = TRUE
)
wb$merge_cells(sheet = "Summary", dims = "A3:D3")

# Header row 5 (dark gray background FF374151, white bold text)
headers_summary <- c("Cancer Category", "Timing", "Patients", "% of Cohort")
for (i in seq_along(headers_summary)) {
  wb$add_data(sheet = "Summary", x = headers_summary[i], start_row = 5, start_col = i)
}
wb$add_fill(sheet = "Summary", dims = "A5:D5", color = wb_color("FF374151"))
wb$add_font(
  sheet = "Summary", dims = "A5:D5",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)

# Data rows starting at row 6
wb$add_data(sheet = "Summary", x = summary_table, start_row = 6, col_names = FALSE)

# Number formatting
last_row_summary <- 5 + nrow(summary_table)
wb$add_numfmt(sheet = "Summary", dims = glue("C6:C{last_row_summary}"), numfmt = "#,##0")
wb$add_numfmt(sheet = "Summary", dims = glue("D6:D{last_row_summary}"), numfmt = "0.0%")

# Column widths
wb$set_col_widths(sheet = "Summary", cols = 1:4, widths = c(30, 12, 12, 14))

# Freeze pane below header
wb$freeze_pane(sheet = "Summary", firstActiveRow = 6)


# --- Sheet 2: Detail ---
wb$add_worksheet("Detail")

# Title row
wb$add_data(
  sheet = "Detail",
  x = "Patient-Level Secondary Malignancy Detail",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Detail", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Detail", dims = "A1:G1")

# Header row 3 (dark gray background, white bold text)
headers_detail <- c("ID", "DX Code (normalized)", "Cancer Category", "Timing", "Earliest Dx Date", "First HL Dx Date", "Unique Dx Dates")
for (i in seq_along(headers_detail)) {
  wb$add_data(sheet = "Detail", x = headers_detail[i], start_row = 3, start_col = i)
}
wb$add_fill(sheet = "Detail", dims = "A3:G3", color = wb_color("FF374151"))
wb$add_font(
  sheet = "Detail", dims = "A3:G3",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)

# Build detail data
detail_table <- secondary_with_dx %>%
  mutate(timing = ifelse(earliest_dx < first_hl_dx_date, "Pre-HL", "Post-HL")) %>%
  select(ID, DX_norm, category, timing, earliest_dx, first_hl_dx_date, n_unique_dates) %>%
  arrange(category, timing, ID)

# Data rows starting at row 4
wb$add_data(sheet = "Detail", x = detail_table, start_row = 4, col_names = FALSE)

# Number formatting for n_unique_dates column (column G)
last_row_detail <- 3 + nrow(detail_table)
wb$add_numfmt(sheet = "Detail", dims = glue("G4:G{last_row_detail}"), numfmt = "#,##0")

# Column widths
wb$set_col_widths(sheet = "Detail", cols = 1:7, widths = c(15, 18, 25, 10, 14, 16, 14))

# Freeze pane below header
wb$freeze_pane(sheet = "Detail", firstActiveRow = 4)

# Save workbook
wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)

message(glue("  Saved: {OUTPUT_XLSX}"))
message()


# ==============================================================================
# SECTION 7: FINAL SUMMARY ----
# ==============================================================================

message("=== R/32 Secondary Malignancy Table Complete ===")
message()
message("  Top 5 cancer categories by patient count:")

top_categories <- summary_table %>%
  filter(category != "Any Secondary Cancer") %>%
  group_by(category) %>%
  summarise(total_patients = sum(n_patients), .groups = "drop") %>%
  arrange(desc(total_patients)) %>%
  head(5)

for (i in seq_len(nrow(top_categories))) {
  message(glue("    {top_categories$category[i]}: {top_categories$total_patients[i]} patients"))
}

message()
message("  Pre vs Post HL breakdown:")
message(glue("    Pre-HL secondary cancers:  {n_distinct(pre_hl$ID)} patients ({sprintf('%.1f%%', 100 * n_distinct(pre_hl$ID) / total_cohort)})"))
message(glue("    Post-HL secondary cancers: {n_distinct(post_hl$ID)} patients ({sprintf('%.1f%%', 100 * n_distinct(post_hl$ID) / total_cohort)})"))
message(glue("    Any timing:                {n_distinct(secondary_with_dx$ID)} patients ({sprintf('%.1f%%', 100 * n_distinct(secondary_with_dx$ID) / total_cohort)})"))
message()
message(glue("  Output: {OUTPUT_XLSX}"))
message()

close_pcornet_con()
message("Done.")
