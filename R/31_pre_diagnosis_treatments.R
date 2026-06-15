# ==============================================================================
# 31_pre_diagnosis_treatments.R -- Pre-Diagnosis Treatment Flagging (TIMING-01)
# ==============================================================================
#
# Purpose:
#   Flag and quantify all treatment episodes occurring before a patient's first
#   confirmed HL diagnosis date. Answers team question G5 (radiation before HL dx)
#   and provides comprehensive view across all 5 treatment types. Standalone
#   investigation script producing meeting-ready xlsx output.
#
# Inputs:
#   - cache/outputs/treatment_episodes.rds (from R/26)
#     Columns: patient_id, treatment_type, episode_start, episode_stop,
#              episode_length_days, distinct_dates_in_episode, historical_flag,
#              triggering_codes, encounter_ids, drug_names
#   - output/confirmed_hl_cohort.rds (from R/47 via R/20)
#     Columns: ID, first_hl_dx_date, first_hl_dx_source
#
# Outputs:
#   - output/pre_diagnosis_treatments.xlsx (two-sheet meeting-presentable xlsx)
#     Sheet 1 "Summary": Counts by treatment type (episodes, patients, days before dx)
#     Sheet 2 "Detail": Patient-level rows with full code context for clinical review
#
# Phase 104 Decisions (Pre-Diagnosis Treatment Flagging):
#   D-01: Output as xlsx with two sheets (summary counts + patient-level detail)
#   D-02: Include ALL 5 treatment types (Chemotherapy, Radiation, SCT, Immunotherapy, Proton Therapy)
#   D-03: Detail rows include full code context (ID, treatment_type, episode_start, episode_stop,
#         first_hl_dx_date, days_before_dx, triggering_codes, drug_names)
#   D-08: Standalone investigation script (no upstream modification)
#   D-09: Raw counts without HIPAA suppression (manual suppression before sharing)
#
# Dependencies:
#   - R/00_config.R (CONFIG paths)
#   - R/utils/utils_assertions.R (assert_rds_exists, assert_df_valid)
#
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP AND CONFIGURATION ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(lubridate)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/utils/utils_assertions.R")

# --- Define file paths ---
INPUT_EPISODES <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
INPUT_COHORT <- file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds")
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "pre_diagnosis_treatments.xlsx")

message("=== R/31: Pre-Diagnosis Treatment Flagging (TIMING-01) ===")
message()
message(glue("  Episodes RDS: {INPUT_EPISODES}"))
message(glue("  Cohort RDS:   {INPUT_COHORT}"))
message(glue("  Output:       {OUTPUT_XLSX}"))
message()


# ==============================================================================
# SECTION 2: INPUT VALIDATION ----
# ==============================================================================

message("--- Input validation ---")

assert_rds_exists(INPUT_EPISODES, script_name = "R/31")
assert_rds_exists(INPUT_COHORT, script_name = "R/31")

message("  Both input RDS files validated.")
message()


# ==============================================================================
# SECTION 3: LOAD DATA ----
# ==============================================================================

message("--- Loading data ---")

# Load treatment episodes (from R/26)
# Columns: patient_id, treatment_type, episode_number, episode_start, episode_stop,
#          episode_length_days, distinct_dates_in_episode, historical_flag,
#          triggering_codes, encounter_ids, drug_names
episodes <- readRDS(INPUT_EPISODES)
message(glue("  Loaded treatment_episodes.rds: {nrow(episodes)} episodes for {n_distinct(episodes$patient_id)} patients"))

# Load confirmed HL cohort (from R/47 via R/20)
# Columns: ID, first_hl_dx_date, first_hl_dx_source
cohort <- readRDS(INPUT_COHORT)
message(glue("  Loaded confirmed_hl_cohort.rds: {nrow(cohort)} patients"))

# Validate expected columns exist
assert_df_valid(episodes, "treatment_episodes", c("patient_id", "treatment_type", "episode_start", "episode_stop", "triggering_codes", "drug_names"), "R/31")
assert_df_valid(cohort, "confirmed_hl_cohort", c("ID", "first_hl_dx_date"), "R/31")

message()


# ==============================================================================
# SECTION 4: IDENTIFY PRE-DIAGNOSIS EPISODES ----
# ==============================================================================

message("--- Identifying pre-diagnosis episodes ---")

# Join episodes to cohort (inner join = confirmed HL patients only)
# CRITICAL: treatment_episodes uses "patient_id", confirmed_hl_cohort uses "ID"
episodes_with_dx <- episodes %>%
  inner_join(cohort %>% select(ID, first_hl_dx_date), by = c("patient_id" = "ID"))

message(glue("  After join to confirmed HL cohort: {nrow(episodes_with_dx)} episodes"))

# Filter pre-diagnosis episodes
# Pitfall 5 guard: Exclude sentinel dates (year <= 1900)
pre_dx_episodes <- episodes_with_dx %>%
  filter(!is.na(first_hl_dx_date)) %>%
  filter(year(first_hl_dx_date) > 1900) %>%
  filter(episode_start < first_hl_dx_date) %>%
  mutate(days_before_dx = as.numeric(first_hl_dx_date - episode_start))

message(glue("  Found {nrow(pre_dx_episodes)} pre-diagnosis episodes across {n_distinct(pre_dx_episodes$patient_id)} patients"))

# Log breakdown by treatment type
type_counts <- pre_dx_episodes %>%
  group_by(treatment_type) %>%
  summarise(n = n(), .groups = "drop") %>%
  arrange(desc(n))

message("  Breakdown by treatment type:")
for (i in seq_len(nrow(type_counts))) {
  message(glue("    {type_counts$treatment_type[i]}: {type_counts$n[i]} episodes"))
}

message()


# ==============================================================================
# SECTION 5: BUILD SUMMARY AND DETAIL TABLES ----
# ==============================================================================

message("--- Building summary and detail tables ---")

# Sheet 1 summary: counts by treatment type (per D-01)
summary_table <- pre_dx_episodes %>%
  group_by(treatment_type) %>%
  summarise(
    n_episodes = n(),
    n_patients = n_distinct(patient_id),
    median_days_before = median(days_before_dx),
    min_days_before = min(days_before_dx),
    max_days_before = max(days_before_dx),
    .groups = "drop"
  ) %>%
  mutate(pct_of_total = sprintf("%.1f%%", 100 * n_episodes / sum(n_episodes))) %>%
  arrange(desc(n_episodes))

# Add total row
total_row <- tibble(
  treatment_type = "TOTAL",
  n_episodes = sum(summary_table$n_episodes),
  n_patients = n_distinct(pre_dx_episodes$patient_id),
  median_days_before = median(pre_dx_episodes$days_before_dx),
  min_days_before = min(pre_dx_episodes$days_before_dx),
  max_days_before = max(pre_dx_episodes$days_before_dx),
  pct_of_total = "100.0%"
)

summary_table <- bind_rows(summary_table, total_row)

message(glue("  Summary table: {nrow(summary_table)} rows (5 treatment types + total)"))

# Sheet 2 detail: patient-level rows (per D-01, D-03)
# Columns: ID, treatment_type, episode_start, episode_stop, first_hl_dx_date,
#          days_before_dx, triggering_codes, drug_names
detail_table <- pre_dx_episodes %>%
  select(
    ID = patient_id,
    treatment_type,
    episode_start,
    episode_stop,
    first_hl_dx_date,
    days_before_dx,
    triggering_codes,
    drug_names
  ) %>%
  arrange(treatment_type, desc(days_before_dx))

message(glue("  Detail table: {nrow(detail_table)} rows"))
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
  x = "Pre-Diagnosis Treatment Episodes",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Summary", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Summary", dims = "A1:G1")

# Subtitle row (Calibri 11pt, italic)
subtitle <- glue("Confirmed HL Cohort: {format(nrow(cohort), big.mark=',')} patients | Pre-Dx Episodes: {format(nrow(pre_dx_episodes), big.mark=',')}")
wb$add_data(
  sheet = "Summary",
  x = subtitle,
  start_row = 2, start_col = 1
)
wb$add_font(
  sheet = "Summary", dims = "A2",
  name = "Calibri", size = 11, italic = TRUE
)
wb$merge_cells(sheet = "Summary", dims = "A2:G2")

# Header row 4 (dark gray background FF374151, white bold text)
headers_summary <- c("Treatment Type", "Episodes", "Patients", "Median Days Before Dx", "Min Days", "Max Days", "% of Total")
for (i in seq_along(headers_summary)) {
  wb$add_data(sheet = "Summary", x = headers_summary[i], start_row = 4, start_col = i)
}
wb$add_fill(sheet = "Summary", dims = "A4:G4", color = wb_color("FF374151"))
wb$add_font(
  sheet = "Summary", dims = "A4:G4",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)

# Data rows starting at row 5
wb$add_data(sheet = "Summary", x = summary_table, start_row = 5, col_names = FALSE)

# Number formatting for count columns
last_row_summary <- 4 + nrow(summary_table)
wb$add_numfmt(sheet = "Summary", dims = glue("B5:F{last_row_summary}"), numfmt = "#,##0")

# Column widths
wb$set_col_widths(sheet = "Summary", cols = 1:7, widths = c(20, 12, 12, 20, 12, 12, 12))

# Freeze pane below header
wb$freeze_pane(sheet = "Summary", firstActiveRow = 5)


# --- Sheet 2: Detail ---
wb$add_worksheet("Detail")

# Title row
wb$add_data(
  sheet = "Detail",
  x = "Patient-Level Pre-Diagnosis Treatment Detail",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Detail", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Detail", dims = "A1:H1")

# Header row 3 (dark gray background, white bold text)
headers_detail <- c("ID", "Treatment Type", "Episode Start", "Episode Stop", "First HL Dx Date", "Days Before Dx", "Triggering Codes", "Drug Names")
for (i in seq_along(headers_detail)) {
  wb$add_data(sheet = "Detail", x = headers_detail[i], start_row = 3, start_col = i)
}
wb$add_fill(sheet = "Detail", dims = "A3:H3", color = wb_color("FF374151"))
wb$add_font(
  sheet = "Detail", dims = "A3:H3",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)

# Data rows starting at row 4
wb$add_data(sheet = "Detail", x = detail_table, start_row = 4, col_names = FALSE)

# Number formatting for days_before_dx column (column F)
last_row_detail <- 3 + nrow(detail_table)
wb$add_numfmt(sheet = "Detail", dims = glue("F4:F{last_row_detail}"), numfmt = "#,##0")

# Column widths
wb$set_col_widths(sheet = "Detail", cols = 1:8, widths = c(15, 18, 14, 14, 16, 16, 30, 30))

# Freeze pane below header
wb$freeze_pane(sheet = "Detail", firstActiveRow = 4)

# Save workbook
wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)

message(glue("  Saved: {OUTPUT_XLSX}"))
message()


# ==============================================================================
# SECTION 7: FINAL SUMMARY ----
# ==============================================================================

message("=== R/31 Pre-Diagnosis Treatment Flagging Complete ===")
message()
message("  Summary by treatment type:")
for (i in seq_len(nrow(summary_table))) {
  message(glue("    {summary_table$treatment_type[i]}: {summary_table$n_episodes[i]} episodes"))
}
message()
message(glue("  Output: {OUTPUT_XLSX}"))
message()
message("Done.")
