# ==============================================================================
# 51_post_death_encounter_investigation.R -- Post-Death Encounter Drill-Down Investigation
# ==============================================================================
#
# Purpose:
#   Drill into the ~200 patients flagged with post-death clinical activity,
#   quantifying temporal gaps (days after death) for every encounter, diagnosis,
#   and treatment event. Produces a meeting-ready two-sheet xlsx with per-patient
#   summary (bucket distribution, min/max/median gaps) and per-event detail (raw
#   days, source table labels). Standalone investigation script -- no upstream
#   modification.
#
# Inputs:
#   - cache/outputs/validated_death_dates.rds (from R/53 Phase 59)
#     Columns: ID, DEATH_DATE, DEATH_SOURCE, death_valid, post_death_activity
#   - cache/outputs/treatment_episodes.rds (from R/28 Phase 61)
#     Columns: patient_id, episode_start, episode_number
#   - DuckDB ENCOUNTER table
#   - DuckDB DIAGNOSIS table
#
# Outputs:
#   - output/post_death_encounter_investigation.xlsx (two sheets)
#     Sheet 1: "Patient Summary" with per-patient aggregates and gap buckets
#     Sheet 2: "Event Detail" with raw per-event days_after_death and source_table
#
# Phase 113 Decisions (Post-Death Encounter Investigation):
#   D-01: Two-sheet xlsx output (Patient Summary + Event Detail)
#   D-02: Standalone script -- opens/closes DuckDB connection, no side effects
#   D-03: Four gap buckets: 0-30 days, 31-90 days, 91-365 days, >1 year
#   D-04: Event Detail sheet enables filtering by source_table (ENCOUNTER/DIAGNOSIS/TREATMENT)
#   D-05: Read DuckDB ENCOUNTER/DIAGNOSIS, cached treatment_episodes.rds
#   D-06: source_table column identifies event type in detail sheet
#   D-07: Optional third sheet "Bucket by Activity Type" for meeting context
#   D-08: Styled headers (dark gray FF374151, white bold text, freeze panes)
#
# Dependencies:
#   - R/00_config.R (CONFIG paths)
#   - R/utils/utils_assertions.R (assert_rds_exists, assert_df_valid)
#   - R/utils/utils_duckdb.R (get_pcornet_table, open/close_pcornet_con)
#   - R/utils/utils_dates.R (parse_pcornet_date)
#   - openxlsx2 (styled xlsx output)
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
  library(tidyr)
})

source("R/00_config.R")
source("R/utils/utils_assertions.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_dates.R")

# --- Define file paths ---
DEATH_RDS <- file.path(CONFIG$cache$outputs_dir, "validated_death_dates.rds")
EPISODES_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "post_death_encounter_investigation.xlsx")

message("=== Phase 113: Post-Death Encounter Investigation ===")
message()
message(glue("  Death RDS:     {DEATH_RDS}"))
message(glue("  Episodes RDS:  {EPISODES_RDS}"))
message(glue("  Output:        {OUTPUT_XLSX}"))
message()


# ==============================================================================
# SECTION 2: INPUT VALIDATION ----
# ==============================================================================

message("--- Input validation ---")

assert_rds_exists(DEATH_RDS, script_name = "R/51")
assert_rds_exists(EPISODES_RDS, script_name = "R/51")

message("  Both input RDS files validated.")
message()


# ==============================================================================
# SECTION 3: LOAD AND FILTER DEATH DATES ----
# ==============================================================================

message("--- Loading and filtering death dates ---")

# Load validated death dates (from R/53 Phase 59)
# Columns: ID, DEATH_DATE, DEATH_SOURCE, death_valid, post_death_activity
validated_deaths <- readRDS(DEATH_RDS)
message(glue("  Loaded validated_death_dates.rds: {nrow(validated_deaths)} patients"))

# Filter to valid deaths with post-death activity (the ~200 patient population)
valid_deaths <- validated_deaths %>%
  filter(death_valid == TRUE, post_death_activity == TRUE)

message(glue("  Patients with post-death activity: {nrow(valid_deaths)}"))
message()


# ==============================================================================
# SECTION 4: QUERY POST-DEATH ENCOUNTERS FROM DUCKDB ----
# ==============================================================================

message("--- Querying post-death encounters from DuckDB ---")

open_pcornet_con()

encounter_post_death <- get_pcornet_table("ENCOUNTER") %>%
  select(ID, ADMIT_DATE, ENCOUNTERID) %>%
  collect() %>%
  mutate(ADMIT_DATE = parse_pcornet_date(ADMIT_DATE)) %>%
  filter(!is.na(ADMIT_DATE)) %>%
  inner_join(valid_deaths %>% select(ID, DEATH_DATE), by = "ID") %>%
  filter(ADMIT_DATE > DEATH_DATE) %>%
  mutate(
    days_after_death = as.numeric(ADMIT_DATE - DEATH_DATE),
    event_date = ADMIT_DATE,
    event_id = ENCOUNTERID,
    source_table = "ENCOUNTER"
  ) %>%
  select(ID, DEATH_DATE, event_date, event_id, source_table, days_after_death)

message(glue("  Post-death encounters: {nrow(encounter_post_death)} events from {n_distinct(encounter_post_death$ID)} patients"))


# ==============================================================================
# SECTION 5: QUERY POST-DEATH DIAGNOSES FROM DUCKDB ----
# ==============================================================================

message("--- Querying post-death diagnoses from DuckDB ---")

diagnosis_post_death <- get_pcornet_table("DIAGNOSIS") %>%
  select(ID, DX_DATE, DIAGNOSISID) %>%
  collect() %>%
  mutate(DX_DATE = parse_pcornet_date(DX_DATE)) %>%
  filter(!is.na(DX_DATE)) %>%
  inner_join(valid_deaths %>% select(ID, DEATH_DATE), by = "ID") %>%
  filter(DX_DATE > DEATH_DATE) %>%
  mutate(
    days_after_death = as.numeric(DX_DATE - DEATH_DATE),
    event_date = DX_DATE,
    event_id = DIAGNOSISID,
    source_table = "DIAGNOSIS"
  ) %>%
  select(ID, DEATH_DATE, event_date, event_id, source_table, days_after_death)

close_pcornet_con()

message(glue("  Post-death diagnoses: {nrow(diagnosis_post_death)} events from {n_distinct(diagnosis_post_death$ID)} patients"))
message()


# ==============================================================================
# SECTION 6: QUERY POST-DEATH TREATMENTS FROM RDS ----
# ==============================================================================

message("--- Querying post-death treatments from RDS ---")

# Load treatment episodes (from R/28 Phase 61)
treatment_episodes <- readRDS(EPISODES_RDS)

treatment_post_death <- treatment_episodes %>%
  inner_join(valid_deaths %>% select(ID, DEATH_DATE), by = c("patient_id" = "ID")) %>%
  filter(episode_start > DEATH_DATE) %>%
  mutate(
    days_after_death = as.numeric(episode_start - DEATH_DATE),
    event_date = episode_start,
    event_id = paste0("EP_", episode_number),
    source_table = "TREATMENT",
    ID = patient_id
  ) %>%
  select(ID, DEATH_DATE, event_date, event_id, source_table, days_after_death)

message(glue("  Post-death treatments: {nrow(treatment_post_death)} events from {n_distinct(treatment_post_death$ID)} patients"))
message()


# ==============================================================================
# SECTION 7: COMBINE ALL POST-DEATH EVENTS AND BUCKET ----
# ==============================================================================

message("--- Combining events and assigning gap buckets ---")

# Combine all three event types
post_death_events <- bind_rows(
  encounter_post_death,
  diagnosis_post_death,
  treatment_post_death
)

# Add gap_bucket column (per D-03)
post_death_events <- post_death_events %>%
  mutate(
    gap_bucket = case_when(
      days_after_death <= 30 ~ "0-30 days",
      days_after_death <= 90 ~ "31-90 days",
      days_after_death <= 365 ~ "91-365 days",
      days_after_death > 365 ~ ">1 year",
      TRUE ~ NA_character_
    )
  ) %>%
  arrange(ID, days_after_death)

message(glue("  Total post-death events: {nrow(post_death_events)} across {n_distinct(post_death_events$ID)} patients"))
message(glue("  By source: ENCOUNTER={sum(post_death_events$source_table == 'ENCOUNTER')}, DIAGNOSIS={sum(post_death_events$source_table == 'DIAGNOSIS')}, TREATMENT={sum(post_death_events$source_table == 'TREATMENT')}"))
message()


# ==============================================================================
# SECTION 8: BUILD PER-PATIENT SUMMARY ----
# ==============================================================================

message("--- Building per-patient summary ---")

patient_summary <- post_death_events %>%
  group_by(ID, DEATH_DATE) %>%
  summarise(
    total_events = n(),
    encounter_events = sum(source_table == "ENCOUNTER"),
    diagnosis_events = sum(source_table == "DIAGNOSIS"),
    treatment_events = sum(source_table == "TREATMENT"),
    min_gap_days = min(days_after_death),
    max_gap_days = max(days_after_death),
    median_gap_days = median(days_after_death),
    earliest_post_death_event = min(event_date),
    latest_post_death_event = max(event_date),
    .groups = "drop"
  ) %>%
  mutate(
    gap_bucket = case_when(
      max_gap_days <= 30 ~ "0-30 days",
      max_gap_days <= 90 ~ "31-90 days",
      max_gap_days <= 365 ~ "91-365 days",
      max_gap_days > 365 ~ ">1 year",
      TRUE ~ NA_character_
    )
  ) %>%
  arrange(desc(max_gap_days))

message(glue("  Patient summary computed: {nrow(patient_summary)} patients"))
message()


# ==============================================================================
# SECTION 9: BUCKET DISTRIBUTION SUMMARY ----
# ==============================================================================

message("--- Computing bucket distribution ---")

# Bucket distribution by patient count
bucket_dist <- patient_summary %>%
  count(gap_bucket, name = "patient_count") %>%
  mutate(pct = sprintf("%.1f%%", 100 * patient_count / sum(patient_count)))

message("  Bucket distribution (by patient):")
for (i in seq_len(nrow(bucket_dist))) {
  message(glue("    {bucket_dist$gap_bucket[i]}: {bucket_dist$patient_count[i]} patients ({bucket_dist$pct[i]})"))
}

# Cross-tab: activity type x bucket
activity_type_dist <- post_death_events %>%
  count(source_table, gap_bucket) %>%
  pivot_wider(names_from = gap_bucket, values_from = n, values_fill = 0)

message("  Activity type distribution computed.")
message()


# ==============================================================================
# SECTION 10: CREATE STYLED XLSX ----
# ==============================================================================

message("--- Creating styled xlsx output ---")

wb <- wb_workbook()

# --- Sheet 1: Patient Summary ---
wb$add_worksheet("Patient Summary")

# Title row
wb$add_data(
  sheet = "Patient Summary",
  x = "Post-Death Clinical Activity Investigation",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Patient Summary", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Patient Summary", dims = "A1:K1")

# Subtitle row
subtitle <- glue("Generated: {Sys.Date()} | Population: {nrow(patient_summary)} patients with post-death activity")
wb$add_data(
  sheet = "Patient Summary",
  x = subtitle,
  start_row = 2, start_col = 1
)
wb$add_font(
  sheet = "Patient Summary", dims = "A2",
  name = "Calibri", size = 10, color = wb_color("FF6B7280")
)
wb$merge_cells(sheet = "Patient Summary", dims = "A2:K2")

# Data table starting at row 4
wb$add_data(
  sheet = "Patient Summary",
  x = patient_summary,
  start_row = 4, start_col = 1
)

# Header row styling (row 4 -- dark gray background, white bold text)
wb$add_fill(
  sheet = "Patient Summary", dims = "A4:K4",
  color = wb_color("FF374151")
)
wb$add_font(
  sheet = "Patient Summary", dims = "A4:K4",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)

# Number formatting for integer columns (total_events through median_gap_days: columns C through I)
wb$add_numfmt(
  sheet = "Patient Summary", dims = "C5:I999",
  numfmt = "#,##0"
)

# Column widths
wb$set_col_widths(
  sheet = "Patient Summary",
  cols = 1:11,
  widths = c(15, 15, 12, 14, 14, 14, 12, 12, 14, 20, 20)
)

# Freeze pane below header
wb$freeze_pane(
  sheet = "Patient Summary",
  firstActiveRow = 5
)

# --- Sheet 2: Event Detail ---
wb$add_worksheet("Event Detail")

# Title row
wb$add_data(
  sheet = "Event Detail",
  x = "Post-Death Events -- Per-Event Detail",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Event Detail", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Event Detail", dims = "A1:G1")

# Subtitle row
subtitle2 <- glue("Generated: {Sys.Date()} | Total events: {nrow(post_death_events)}")
wb$add_data(
  sheet = "Event Detail",
  x = subtitle2,
  start_row = 2, start_col = 1
)
wb$add_font(
  sheet = "Event Detail", dims = "A2",
  name = "Calibri", size = 10, color = wb_color("FF6B7280")
)
wb$merge_cells(sheet = "Event Detail", dims = "A2:G2")

# Data table starting at row 4
wb$add_data(
  sheet = "Event Detail",
  x = post_death_events,
  start_row = 4, start_col = 1
)

# Header row styling (row 4)
wb$add_fill(
  sheet = "Event Detail", dims = "A4:G4",
  color = wb_color("FF374151")
)
wb$add_font(
  sheet = "Event Detail", dims = "A4:G4",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)

# Number formatting for days_after_death (column F)
wb$add_numfmt(
  sheet = "Event Detail", dims = "F5:F9999",
  numfmt = "#,##0"
)

# Column widths
wb$set_col_widths(
  sheet = "Event Detail",
  cols = 1:7,
  widths = c(15, 15, 15, 20, 15, 16, 15)
)

# Freeze pane below header
wb$freeze_pane(
  sheet = "Event Detail",
  firstActiveRow = 5
)

# --- Sheet 3: Bucket by Activity Type ---
wb$add_worksheet("Bucket by Activity Type")

# Title row
wb$add_data(
  sheet = "Bucket by Activity Type",
  x = "Gap Distribution Cross-Tabbed by Activity Type",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Bucket by Activity Type", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
ncol_dist <- ncol(activity_type_dist)
last_col_letter <- LETTERS[ncol_dist]
wb$merge_cells(sheet = "Bucket by Activity Type", dims = glue("A1:{last_col_letter}1"))

# Subtitle row
subtitle3 <- glue("Generated: {Sys.Date()} | Event count per bucket by source table")
wb$add_data(
  sheet = "Bucket by Activity Type",
  x = subtitle3,
  start_row = 2, start_col = 1
)
wb$add_font(
  sheet = "Bucket by Activity Type", dims = "A2",
  name = "Calibri", size = 10, color = wb_color("FF6B7280")
)
wb$merge_cells(sheet = "Bucket by Activity Type", dims = glue("A2:{last_col_letter}2"))

# Data table starting at row 4
wb$add_data(
  sheet = "Bucket by Activity Type",
  x = activity_type_dist,
  start_row = 4, start_col = 1
)

# Header row styling (row 4)
wb$add_fill(
  sheet = "Bucket by Activity Type", dims = glue("A4:{last_col_letter}4"),
  color = wb_color("FF374151")
)
wb$add_font(
  sheet = "Bucket by Activity Type", dims = glue("A4:{last_col_letter}4"),
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)

# Number formatting for count columns
wb$add_numfmt(
  sheet = "Bucket by Activity Type", dims = glue("B5:{last_col_letter}999"),
  numfmt = "#,##0"
)

# Column widths
wb$set_col_widths(
  sheet = "Bucket by Activity Type",
  cols = 1:ncol_dist,
  widths = c(20, rep(15, ncol_dist - 1))
)

# Freeze pane below header
wb$freeze_pane(
  sheet = "Bucket by Activity Type",
  firstActiveRow = 5
)

# Save workbook
wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)

message(glue("  Saved: {OUTPUT_XLSX}"))
message()


# ==============================================================================
# SECTION 11: FINAL SUMMARY ----
# ==============================================================================

message("--- Summary ---")
message(glue("  Total patients analyzed: {nrow(patient_summary)}"))
message(glue("  Total post-death events: {nrow(post_death_events)}"))
message("  Bucket distribution (by patient):")
for (i in seq_len(nrow(bucket_dist))) {
  message(glue("    {bucket_dist$gap_bucket[i]}: {bucket_dist$patient_count[i]} ({bucket_dist$pct[i]})"))
}
message()
message("Done.")
