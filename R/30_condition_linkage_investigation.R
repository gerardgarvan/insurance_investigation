# ==============================================================================
# 30_condition_linkage_investigation.R -- CONDITION Table Cancer Linkage Investigation
# ==============================================================================
#
# Purpose:
#   Investigate CONDITION table as 3rd-tier cancer linkage supplement.
#   Read-only analysis: does NOT modify treatment_episodes.rds or existing outputs.
#   Applies the same 2-tier linkage cascade (ENCOUNTERID direct match -> 30-day
#   temporal fallback) used in R/28 DIAGNOSIS linkage, but using CONDITION table
#   data instead. Goal: quantify potential improvement in cancer linkage rates if
#   CONDITION is added as 3rd tier in production pipeline.
#
# Inputs:
#   - treatment_episodes.rds (read-only)
#   - DuckDB CONDITION table
#
# Outputs:
#   - New "Linkage Improvement" sheet in episode_classification_audit.xlsx
#
# Dependencies:
#   - R/00_config.R (CONFIG, CANCER_SITE_MAP)
#   - R/utils/utils_duckdb.R (open_pcornet_con, close_pcornet_con, get_pcornet_table)
#   - R/utils/utils_cancer.R (is_cancer_code, classify_codes)
#   - R/utils/utils_dates.R (parse_pcornet_date)
#   - R/utils/utils_assertions.R (assert_rds_exists, assert_df_valid)
#
# Requirements: COND-01, COND-02, COND-03
#
# DECISION TRACEABILITY:
#   D-01: Only ICD-10 (CONDITION_TYPE = "10") and ICD-9 ("09") from CONDITION
#   D-02: No filtering on CONDITION_STATUS or CONDITION_SOURCE
#   D-03: Two link method labels: "condition_encounter" and "condition_date"
#   D-04: Use ONSET_DATE (not REPORT_DATE) for temporal fallback
#   D-05: Only episodes with cancer_link_method == "none" are candidates
#   D-06: Investigation only -- results NOT merged into treatment_episodes.rds
#   D-07: Standalone script, NOT a modification to R/28
#   D-08: No existing datasets, reports, or outputs affected
#   D-09: Report as new "Linkage Improvement" sheet in episode_classification_audit.xlsx
#   D-10: Breakdown by treatment type (Chemo, RT, SCT, Immuno, Proton)
#
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP AND CONFIGURATION ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(lubridate)
  library(openxlsx2)
  library(tibble)
  library(tidyr)
})

source("R/00_config.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_dates.R")

# Output paths
OUTPUT_RDS_READ <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
AUDIT_XLSX <- file.path(CONFIG$output_dir, "episode_classification_audit.xlsx")
STANDALONE_XLSX <- file.path(CONFIG$output_dir, "condition_linkage_investigation.xlsx")

message("\n=== R/30: CONDITION Table Cancer Linkage Investigation ===")


# ==============================================================================
# SECTION 2: LOAD DATA ----
# ==============================================================================

message("\n--- Loading treatment episodes ---")

# SAFE-01: Validate input RDS artifacts
assert_rds_exists(OUTPUT_RDS_READ, script_name = "R/30")

# Read treatment episodes (READ-ONLY, never saveRDS)
episodes <- readRDS(OUTPUT_RDS_READ)

# SAFE-02: Validate data frame structure
assert_df_valid(
  episodes,
  "treatment_episodes",
  required_cols = c("patient_id", "treatment_type", "episode_number",
                    "episode_start", "encounter_ids", "cancer_link_method"),
  script_name = "R/30"
)

n_total <- nrow(episodes)
unlinked_episodes <- episodes %>%
  filter(cancer_link_method == "none")  # D-05: only unlinked candidates

n_unlinked <- nrow(unlinked_episodes)

message(glue("  Total episodes: {n_total}"))
message(glue("  Unlinked episodes (cancer_link_method == 'none'): {n_unlinked} ({round(100 * n_unlinked / n_total, 1)}%)"))

# Open DuckDB connection and query CONDITION table
message("\n--- Querying CONDITION table via DuckDB ---")

USE_DUCKDB <- TRUE
open_pcornet_con()

condition_data <- get_pcornet_table("CONDITION") %>%
  select(ID, ENCOUNTERID, CONDITION, CONDITION_TYPE, ONSET_DATE) %>%
  collect() %>%
  mutate(ONSET_DATE = parse_pcornet_date(ONSET_DATE)) %>%
  filter(CONDITION_TYPE %in% c("09", "10")) %>%  # D-01: ICD-10 and ICD-9 only
  filter(!is.na(ONSET_DATE))  # D-04: ONSET_DATE required for temporal matching

message(glue("  CONDITION query: {nrow(condition_data)} ICD-9/10 rows with ONSET_DATE"))

# Filter to cancer codes only
condition_cancer <- condition_data %>%
  filter(is_cancer_code(CONDITION))

message(glue("  CONDITION cancer codes: {nrow(condition_cancer)} rows"))


# ==============================================================================
# SECTION 3: CONDITION LINKAGE INVESTIGATION ----
# ==============================================================================

message("\n--- CONDITION Linkage Investigation ---")

# --- 3a: ENCOUNTERID direct match (Tier 1) ---

# Extract encounter IDs from unlinked episodes (mirror R/28 pattern)
unlinked_encounters <- unlinked_episodes %>%
  filter(!is.na(encounter_ids) & encounter_ids != "") %>%
  mutate(encounter_ids_list = str_split(encounter_ids, ",")) %>%
  tidyr::unnest(cols = encounter_ids_list) %>%
  filter(!is.na(encounter_ids_list) & encounter_ids_list != "") %>%
  select(patient_id, treatment_type, episode_number, ENCOUNTERID = encounter_ids_list)

message(glue("  Episode encounters extracted: {nrow(unlinked_encounters)} encounter IDs from {n_distinct(paste(unlinked_encounters$patient_id, unlinked_encounters$treatment_type, unlinked_encounters$episode_number))} episodes"))

# Direct ENCOUNTERID match against condition_cancer
condition_with_encounter <- condition_cancer %>%
  filter(!is.na(ENCOUNTERID) & ENCOUNTERID != "")

condition_encounter_linked <- unlinked_encounters %>%
  inner_join(condition_with_encounter, by = "ENCOUNTERID", relationship = "many-to-many") %>%
  mutate(cancer_category = classify_codes(CONDITION)) %>%
  group_by(patient_id, treatment_type, episode_number) %>%
  arrange(desc(cancer_category == "Hodgkin Lymphoma"), .by_group = TRUE) %>%
  slice(1) %>%
  ungroup() %>%
  mutate(condition_link_method = "condition_encounter") %>%  # D-03 label
  select(patient_id, treatment_type, episode_number, cancer_category, condition_link_method)

n_condition_encounter <- nrow(condition_encounter_linked)
message(glue("  CONDITION ENCOUNTERID match: {n_condition_encounter} episodes linked"))


# --- 3b: Temporal fallback using ONSET_DATE (Tier 2) ---

# Identify still-unlinked episodes after ENCOUNTERID match
still_unlinked <- unlinked_episodes %>%
  anti_join(condition_encounter_linked, by = c("patient_id", "treatment_type", "episode_number"))

message(glue("  Still unlinked after CONDITION ENCOUNTERID: {nrow(still_unlinked)}"))

# Get CONDITION cancer rows for still-unlinked patients
still_unlinked_patients <- unique(still_unlinked$patient_id)
condition_for_unlinked <- condition_cancer %>%
  filter(ID %in% still_unlinked_patients)

# Temporal matching: ONSET_DATE within 30 days before episode_start (D-04)
condition_temporal_linked <- still_unlinked %>%
  left_join(condition_for_unlinked, by = c("patient_id" = "ID"), relationship = "many-to-many") %>%
  filter(!is.na(ONSET_DATE)) %>%
  filter(ONSET_DATE <= episode_start) %>%
  mutate(days_before = as.numeric(episode_start - ONSET_DATE)) %>%
  filter(days_before <= 30) %>%
  mutate(cancer_category = classify_codes(CONDITION)) %>%
  group_by(patient_id, treatment_type, episode_number) %>%
  arrange(days_before, desc(cancer_category == "Hodgkin Lymphoma"), .by_group = TRUE) %>%
  slice(1) %>%
  ungroup() %>%
  mutate(condition_link_method = "condition_date") %>%  # D-03 label
  select(patient_id, treatment_type, episode_number, cancer_category, condition_link_method)

n_condition_temporal <- nrow(condition_temporal_linked)
message(glue("  CONDITION temporal fallback (30-day): {n_condition_temporal} episodes linked"))


# --- 3c: Combine results ---

condition_linkage <- bind_rows(condition_encounter_linked, condition_temporal_linked)
n_condition_total <- nrow(condition_linkage)


# ==============================================================================
# SECTION 4: IMPROVEMENT ANALYSIS ----
# ==============================================================================

message("\n--- Improvement Analysis ---")

# --- 4a: Aggregate before/after counts ---

pct_unlinked_before <- round(100 * n_unlinked / n_total, 1)
pct_unlinked_after <- round(100 * (n_unlinked - n_condition_total) / n_total, 1)
pct_improvement <- round(pct_unlinked_before - pct_unlinked_after, 1)

improvement_summary <- tibble(
  Metric = c(
    "Total episodes",
    "Unlinked before CONDITION",
    "Would link via CONDITION encounter",
    "Would link via CONDITION date",
    "Total would-be linked via CONDITION",
    "Would remain unlinked",
    "Improvement (percentage points)"
  ),
  Count = c(
    n_total,
    n_unlinked,
    n_condition_encounter,
    n_condition_temporal,
    n_condition_total,
    n_unlinked - n_condition_total,
    NA_integer_
  ),
  Percent = c(
    100.0,
    pct_unlinked_before,
    round(100 * n_condition_encounter / n_total, 1),
    round(100 * n_condition_temporal / n_total, 1),
    round(100 * n_condition_total / n_total, 1),
    pct_unlinked_after,
    pct_improvement
  )
)


# --- 4b: Treatment type breakdown (D-10) ---

condition_improvement <- unlinked_episodes %>%
  left_join(condition_linkage, by = c("patient_id", "treatment_type", "episode_number")) %>%
  mutate(would_link = !is.na(condition_link_method))

treatment_type_breakdown <- condition_improvement %>%
  group_by(treatment_type) %>%
  summarise(
    total_unlinked = n(),
    would_link_via_condition = sum(would_link),
    would_remain_unlinked = sum(!would_link),
    pct_improvement = round(100 * would_link_via_condition / total_unlinked, 1),
    .groups = "drop"
  ) %>%
  arrange(desc(pct_improvement))


# --- 4c: Cancer category distribution for newly-linked episodes ---

category_distribution <- condition_linkage %>%
  count(cancer_category, condition_link_method, name = "n_episodes") %>%
  arrange(desc(n_episodes))


# ==============================================================================
# SECTION 5: REPORT GENERATION (D-09) ----
# ==============================================================================

message("\n--- Creating 'Linkage Improvement' sheet ---")

# Load existing workbook
wb <- wb_load(AUDIT_XLSX)

# Remove sheet if it exists (idempotent re-runs)
if ("Linkage Improvement" %in% wb$get_sheet_names()) {
  wb$remove_worksheet("Linkage Improvement")
}

# Add new sheet
wb$add_worksheet("Linkage Improvement")

# --- Title row (A1) ---
wb$add_data(
  sheet = "Linkage Improvement",
  x = "CONDITION Table Linkage Improvement Investigation",
  start_row = 1,
  start_col = 1
)
wb$add_font(
  sheet = "Linkage Improvement",
  dims = "A1",
  name = "Calibri",
  size = 16,
  bold = TRUE,
  color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Linkage Improvement", dims = "A1:C1")

# --- Subtitle row (A2) ---
subtitle <- glue("Generated: {Sys.Date()} | Investigation only - NOT applied to treatment_episodes.rds")
wb$add_data(
  sheet = "Linkage Improvement",
  x = subtitle,
  start_row = 2,
  start_col = 1
)
wb$add_font(
  sheet = "Linkage Improvement",
  dims = "A2",
  name = "Calibri",
  size = 10,
  color = wb_color("FF6B7280")
)
wb$merge_cells(sheet = "Linkage Improvement", dims = "A2:C2")

# --- Aggregate summary table starting at row 4 ---
wb$add_data(
  sheet = "Linkage Improvement",
  x = improvement_summary,
  start_row = 4,
  start_col = 1
)

# Header styling
wb$add_fill(
  sheet = "Linkage Improvement",
  dims = "A4:C4",
  color = wb_color("FF1F2937")
)
wb$add_font(
  sheet = "Linkage Improvement",
  dims = "A4:C4",
  bold = TRUE,
  color = wb_color("FFFFFFFF")
)

# --- Treatment type breakdown section ---
treatment_start_row <- 4 + nrow(improvement_summary) + 3

wb$add_data(
  sheet = "Linkage Improvement",
  x = "Treatment Type Breakdown",
  start_row = treatment_start_row,
  start_col = 1
)
wb$add_font(
  sheet = "Linkage Improvement",
  dims = glue("A{treatment_start_row}"),
  name = "Calibri",
  size = 14,
  bold = TRUE
)

treatment_table_row <- treatment_start_row + 2
wb$add_data(
  sheet = "Linkage Improvement",
  x = treatment_type_breakdown,
  start_row = treatment_table_row,
  start_col = 1
)

# Header styling
treatment_header_dims <- glue("A{treatment_table_row}:E{treatment_table_row}")
wb$add_fill(
  sheet = "Linkage Improvement",
  dims = treatment_header_dims,
  color = wb_color("FF1F2937")
)
wb$add_font(
  sheet = "Linkage Improvement",
  dims = treatment_header_dims,
  bold = TRUE,
  color = wb_color("FFFFFFFF")
)

# --- Cancer category distribution section ---
category_start_row <- treatment_table_row + nrow(treatment_type_breakdown) + 3

wb$add_data(
  sheet = "Linkage Improvement",
  x = "Cancer Category Distribution (Would-Be Linked Episodes)",
  start_row = category_start_row,
  start_col = 1
)
wb$add_font(
  sheet = "Linkage Improvement",
  dims = glue("A{category_start_row}"),
  name = "Calibri",
  size = 14,
  bold = TRUE
)

category_table_row <- category_start_row + 2
wb$add_data(
  sheet = "Linkage Improvement",
  x = category_distribution,
  start_row = category_table_row,
  start_col = 1
)

# Header styling
category_header_dims <- glue("A{category_table_row}:C{category_table_row}")
wb$add_fill(
  sheet = "Linkage Improvement",
  dims = category_header_dims,
  color = wb_color("FF1F2937")
)
wb$add_font(
  sheet = "Linkage Improvement",
  dims = category_header_dims,
  bold = TRUE,
  color = wb_color("FFFFFFFF")
)

# --- Freeze pane and autofit ---
wb$freeze_pane(sheet = "Linkage Improvement", first_active_row = 5)
wb$set_col_widths(sheet = "Linkage Improvement", cols = 1:5, widths = "auto")

# Save workbook
wb_save(wb, AUDIT_XLSX, overwrite = TRUE)
message(glue("  Added 'Linkage Improvement' sheet to {AUDIT_XLSX}"))


# --- Standalone xlsx for delivery manifest (condition_linkage_investigation.xlsx) ---

message("\n--- Creating standalone condition_linkage_investigation.xlsx ---")

wb_standalone <- wb_workbook()

# Sheet 1: Improvement Summary (read by R/37 gap_resolution_report.Rmd)
wb_standalone$add_worksheet("Improvement Summary")
wb_standalone$add_data(sheet = "Improvement Summary", x = improvement_summary, start_row = 1, start_col = 1)
wb_standalone$add_fill(sheet = "Improvement Summary", dims = "A1:C1", color = wb_color("FF1F2937"))
wb_standalone$add_font(sheet = "Improvement Summary", dims = "A1:C1", bold = TRUE, color = wb_color("FFFFFFFF"))
wb_standalone$set_col_widths(sheet = "Improvement Summary", cols = 1:3, widths = "auto")

# Sheet 2: Treatment Type Breakdown
wb_standalone$add_worksheet("Treatment Type Breakdown")
wb_standalone$add_data(sheet = "Treatment Type Breakdown", x = treatment_type_breakdown, start_row = 1, start_col = 1)
wb_standalone$add_fill(sheet = "Treatment Type Breakdown", dims = "A1:E1", color = wb_color("FF1F2937"))
wb_standalone$add_font(sheet = "Treatment Type Breakdown", dims = "A1:E1", bold = TRUE, color = wb_color("FFFFFFFF"))
wb_standalone$set_col_widths(sheet = "Treatment Type Breakdown", cols = 1:5, widths = "auto")

# Sheet 3: Cancer Category Distribution
wb_standalone$add_worksheet("Cancer Category Distribution")
wb_standalone$add_data(sheet = "Cancer Category Distribution", x = category_distribution, start_row = 1, start_col = 1)
wb_standalone$add_fill(sheet = "Cancer Category Distribution", dims = "A1:C1", color = wb_color("FF1F2937"))
wb_standalone$add_font(sheet = "Cancer Category Distribution", dims = "A1:C1", bold = TRUE, color = wb_color("FFFFFFFF"))
wb_standalone$set_col_widths(sheet = "Cancer Category Distribution", cols = 1:3, widths = "auto")

wb_save(wb_standalone, STANDALONE_XLSX, overwrite = TRUE)
message(glue("  Created {STANDALONE_XLSX}"))


# ==============================================================================
# SECTION 6: CLEANUP AND SUMMARY ----
# ==============================================================================

close_pcornet_con()

message(glue("\n=== CONDITION Linkage Investigation Complete ==="))
message(glue("  Unlinked before: {n_unlinked} ({pct_unlinked_before}%)"))
message(glue("  Would link via CONDITION: {n_condition_total} ({round(100 * n_condition_total / n_total, 1)}%)"))
message(glue("    - ENCOUNTERID match: {n_condition_encounter}"))
message(glue("    - Temporal fallback: {n_condition_temporal}"))
message(glue("  Would remain unlinked: {n_unlinked - n_condition_total} ({pct_unlinked_after}%)"))
message(glue("  Improvement: {pct_improvement} percentage points"))
message(glue("  Report: {AUDIT_XLSX} ('Linkage Improvement' sheet)"))
message(glue("  Standalone: {STANDALONE_XLSX}"))
message(glue("\nNOTE: This is investigation only. No existing data was modified."))
