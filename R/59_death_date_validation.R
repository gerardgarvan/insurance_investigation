# Phase 59: Death Date Validation & Treatment Timeline Cleanup
# Decision traceability: D-01 through D-12 from 59-CONTEXT.md
# Inputs: DuckDB DEATH table, treatment_episodes.rds, confirmed_hl_cohort.rds,
#         DuckDB ENCOUNTER table, DuckDB DIAGNOSIS table, DuckDB DEMOGRAPHIC table, DuckDB ENROLLMENT table
# Outputs: death_date_validation.xlsx, death_date_validation.csv, validated_death_dates.rds

# ==============================================================================
# SECTION 1: SETUP AND CONFIGURATION
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(lubridate)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/utils_duckdb.R")
source("R/utils_dates.R")

message("=== Phase 59: Death Date Validation & Treatment Timeline Cleanup ===\n")

# Define output paths
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "death_date_validation.xlsx")
OUTPUT_CSV <- file.path(CONFIG$output_dir, "death_date_validation.csv")
OUTPUT_RDS <- file.path(CONFIG$cache$outputs_dir, "validated_death_dates.rds")

# Define input paths
EPISODES_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
COHORT_RDS <- file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds")

message(glue("Output files:"))
message(glue("  XLSX: {OUTPUT_XLSX}"))
message(glue("  CSV:  {OUTPUT_CSV}"))
message(glue("  RDS:  {OUTPUT_RDS}\n"))


# ==============================================================================
# SECTION 2: LOAD DEATH DATA (per D-04, D-11)
# ==============================================================================

message("--- Loading DEATH table ---")

USE_DUCKDB <- TRUE
open_pcornet_con()

death_raw <- get_pcornet_table("DEATH")

if (is.null(death_raw)) {
  stop("DEATH table not found in DuckDB. Re-run R/25_duckdb_ingest.R after config update.")
}

# Collect, parse dates, apply 1900 sentinel filter (reuse R/49 pattern exactly)
death_data <- death_raw %>%
  collect() %>%
  mutate(
    DEATH_DATE = parse_pcornet_date(DEATH_DATE),
    DEATH_DATE = if_else(year(DEATH_DATE) == 1900L, as.Date(NA), DEATH_DATE)
  ) %>%
  filter(!is.na(DEATH_DATE)) %>%
  select(ID, DEATH_DATE, DEATH_SOURCE) %>%
  group_by(ID) %>%
  summarise(
    DEATH_DATE = min(DEATH_DATE),
    DEATH_SOURCE = first(DEATH_SOURCE),
    .groups = "drop"
  )

message(glue("  Patients with valid death dates: {nrow(death_data)}"))

# Population is ALL patients with death dates per D-11


# ==============================================================================
# SECTION 3: LOAD TREATMENT EPISODES AND COMPUTE EARLIEST TREATMENT DATE (per D-01)
# ==============================================================================

message("\n--- Loading treatment episodes ---")

if (!file.exists(EPISODES_RDS)) {
  stop(glue("Treatment episodes RDS not found: {EPISODES_RDS}"))
}

treatment_episodes <- readRDS(EPISODES_RDS)
message(glue("  Loaded treatment episodes: {nrow(treatment_episodes)} rows"))

# Compute earliest treatment date per patient across ALL treatment types
# (no type filtering -- per RESEARCH anti-pattern 2)
earliest_treatment <- treatment_episodes %>%
  group_by(patient_id) %>%
  summarise(earliest_treatment_date = min(episode_start, na.rm = TRUE), .groups = "drop") %>%
  filter(!is.na(earliest_treatment_date))

message(glue("  Patients with treatment records: {nrow(earliest_treatment)}"))


# ==============================================================================
# SECTION 4: IDENTIFY IMPOSSIBLE DEATH DATES (per D-01, D-02)
# ==============================================================================

message("\n--- Identifying impossible death dates ---")

# Join death_data with earliest_treatment
death_with_treatment <- death_data %>%
  inner_join(earliest_treatment, by = c("ID" = "patient_id"))

# Flag impossible deaths (death BEFORE earliest treatment)
impossible_deaths <- death_with_treatment %>%
  filter(DEATH_DATE < earliest_treatment_date) %>%
  mutate(
    death_valid = FALSE,
    validation_reason = "Death date before earliest treatment date"
  )

message(glue("  Impossible death dates (death before treatment): {nrow(impossible_deaths)}"))

# Create valid deaths pool by removing impossible deaths
valid_deaths <- death_data %>%
  anti_join(impossible_deaths, by = "ID") %>%
  mutate(death_valid = TRUE, validation_reason = "")

message(glue("  Valid death dates retained: {nrow(valid_deaths)}"))


# ==============================================================================
# SECTION 4B: IDENTIFY IMPOSSIBLE DEATHS BEFORE HL DIAGNOSIS
# ==============================================================================

message("\n--- Identifying impossible death dates (death before HL Diagnosis) ---")

if (!file.exists(COHORT_RDS)) {
  warning("confirmed_hl_cohort.rds not found. Skipping death-before-HL-diagnosis check.")
} else {
  hl_cohort_for_death_check <- readRDS(COHORT_RDS) %>%
    filter(!is.na(first_hl_dx_date), year(first_hl_dx_date) != 1900L)

  # Check valid_deaths against HL diagnosis dates
  death_vs_hl_dx <- valid_deaths %>%
    inner_join(hl_cohort_for_death_check, by = "ID")

  impossible_before_hl_dx <- death_vs_hl_dx %>%
    filter(DEATH_DATE < first_hl_dx_date) %>%
    mutate(
      death_valid = FALSE,
      validation_reason = "Death date before HL diagnosis date"
    ) %>%
    select(-first_hl_dx_date, -first_hl_dx_source)

  message(glue("  Impossible death dates (death before HL Diagnosis): {nrow(impossible_before_hl_dx)}"))

  if (nrow(impossible_before_hl_dx) > 0) {
    # Add to impossible_deaths pool
    impossible_deaths <- bind_rows(impossible_deaths, impossible_before_hl_dx)

    # Remove from valid_deaths
    valid_deaths <- valid_deaths %>%
      anti_join(impossible_before_hl_dx, by = "ID")

    message(glue("  Valid death dates after HL Diagnosis check: {nrow(valid_deaths)}"))
  }
}


# ==============================================================================
# SECTION 5: DETECT POST-DEATH CLINICAL ACTIVITY (per D-03)
# ==============================================================================

message("\n--- Detecting post-death clinical activity ---")

# Check ENCOUNTER table
message("  Checking ENCOUNTER table...")
encounter_post_death <- get_pcornet_table("ENCOUNTER") %>%
  select(ID, ADMIT_DATE) %>%
  collect() %>%
  mutate(ADMIT_DATE = parse_pcornet_date(ADMIT_DATE)) %>%
  filter(!is.na(ADMIT_DATE)) %>%
  inner_join(valid_deaths %>% select(ID, DEATH_DATE), by = "ID") %>%
  filter(ADMIT_DATE > DEATH_DATE) %>%
  group_by(ID) %>%
  summarise(post_death_encounters = n(), latest_post_death_encounter = max(ADMIT_DATE), .groups = "drop")

message(glue("    Patients with post-death encounters: {nrow(encounter_post_death)}"))

# Check DIAGNOSIS table
message("  Checking DIAGNOSIS table...")
diagnosis_post_death <- get_pcornet_table("DIAGNOSIS") %>%
  select(ID, DX_DATE) %>%
  collect() %>%
  mutate(DX_DATE = parse_pcornet_date(DX_DATE)) %>%
  filter(!is.na(DX_DATE)) %>%
  inner_join(valid_deaths %>% select(ID, DEATH_DATE), by = "ID") %>%
  filter(DX_DATE > DEATH_DATE) %>%
  group_by(ID) %>%
  summarise(post_death_diagnoses = n(), latest_post_death_diagnosis = max(DX_DATE), .groups = "drop")

message(glue("    Patients with post-death diagnoses: {nrow(diagnosis_post_death)}"))

# Check treatment episodes
message("  Checking treatment episodes...")
treatment_post_death <- treatment_episodes %>%
  inner_join(valid_deaths %>% select(ID, DEATH_DATE), by = c("patient_id" = "ID")) %>%
  filter(episode_start > DEATH_DATE) %>%
  group_by(patient_id) %>%
  summarise(post_death_treatments = n(), latest_post_death_treatment = max(episode_start), .groups = "drop") %>%
  rename(ID = patient_id)

message(glue("    Patients with post-death treatments: {nrow(treatment_post_death)}"))

# Combine flags into valid_deaths
valid_deaths <- valid_deaths %>%
  left_join(encounter_post_death, by = "ID") %>%
  left_join(diagnosis_post_death, by = "ID") %>%
  left_join(treatment_post_death, by = "ID") %>%
  mutate(
    post_death_encounters = if_else(is.na(post_death_encounters), 0L, post_death_encounters),
    post_death_diagnoses = if_else(is.na(post_death_diagnoses), 0L, post_death_diagnoses),
    post_death_treatments = if_else(is.na(post_death_treatments), 0L, post_death_treatments),
    post_death_activity = (post_death_encounters > 0L | post_death_diagnoses > 0L | post_death_treatments > 0L)
  )

message(glue("  Total patients with ANY post-death activity: {sum(valid_deaths$post_death_activity)}"))


# ==============================================================================
# SECTION 6: DEATH-ONLY PATIENT INVESTIGATION (per D-05, D-06)
# ==============================================================================

message("\n--- Investigating death-only patients ---")

# Identify death-only patients
death_only_patients <- death_data %>%
  anti_join(treatment_episodes, by = c("ID" = "patient_id"))

message(glue("  Patients with death dates but no treatment records: {nrow(death_only_patients)}"))

# Load confirmed_hl_cohort.rds and check HL status
if (!file.exists(COHORT_RDS)) {
  stop(glue("Confirmed HL cohort RDS not found: {COHORT_RDS}"))
}

confirmed_hl_cohort <- readRDS(COHORT_RDS)
message(glue("  Loaded confirmed HL cohort: {nrow(confirmed_hl_cohort)} patients"))

death_only_with_hl <- death_only_patients %>%
  left_join(confirmed_hl_cohort, by = "ID") %>%
  mutate(
    confirmed_hl = !is.na(first_hl_dx_date),
    first_hl_dx_date = if_else(is.na(first_hl_dx_date), as.Date(NA), first_hl_dx_date)
  )

# Load DEMOGRAPHIC for age/sex
message("  Loading DEMOGRAPHIC for age/sex...")
demographics <- get_pcornet_table("DEMOGRAPHIC") %>%
  select(ID, BIRTH_DATE, SEX, RACE, HISPANIC) %>%
  collect() %>%
  mutate(BIRTH_DATE = parse_pcornet_date(BIRTH_DATE))

# Load ENROLLMENT for coverage
message("  Loading ENROLLMENT for coverage...")
enrollment <- get_pcornet_table("ENROLLMENT") %>%
  select(ID, ENR_START_DATE, ENR_END_DATE) %>%
  collect() %>%
  mutate(
    ENR_START_DATE = parse_pcornet_date(ENR_START_DATE),
    ENR_END_DATE = parse_pcornet_date(ENR_END_DATE)
  ) %>%
  group_by(ID) %>%
  summarise(
    first_enrollment = min(ENR_START_DATE, na.rm = TRUE),
    last_enrollment = max(ENR_END_DATE, na.rm = TRUE),
    enrollment_periods = n(),
    .groups = "drop"
  )

# Count encounters
message("  Counting encounters...")
encounter_counts <- get_pcornet_table("ENCOUNTER") %>%
  select(ID, ADMIT_DATE) %>%
  collect() %>%
  filter(!is.na(ADMIT_DATE)) %>%
  group_by(ID) %>%
  summarise(total_encounters = n(), .groups = "drop")

# Count diagnoses (all, and HL-specific C81 codes)
message("  Counting diagnoses...")
diagnosis_counts <- get_pcornet_table("DIAGNOSIS") %>%
  select(ID, DX, DX_DATE) %>%
  collect() %>%
  group_by(ID) %>%
  summarise(
    total_diagnoses = n(),
    hl_diagnosis_codes = sum(str_detect(DX, "^C81"), na.rm = TRUE),
    .groups = "drop"
  )

# Close DuckDB
close_pcornet_con()

# Build investigation dataset (per D-06 -- two clinical questions)
death_only_investigation <- death_only_with_hl %>%
  left_join(demographics, by = "ID") %>%
  left_join(enrollment, by = "ID") %>%
  left_join(encounter_counts, by = "ID") %>%
  left_join(diagnosis_counts, by = "ID") %>%
  mutate(
    age_at_death = as.numeric(difftime(DEATH_DATE, BIRTH_DATE, units = "days")) / 365.25,
    died_before_first_hl_dx = if_else(!is.na(first_hl_dx_date) & DEATH_DATE < first_hl_dx_date, TRUE, FALSE),
    total_encounters = if_else(is.na(total_encounters), 0L, total_encounters),
    total_diagnoses = if_else(is.na(total_diagnoses), 0L, total_diagnoses),
    hl_diagnosis_codes = if_else(is.na(hl_diagnosis_codes), 0L, hl_diagnosis_codes),
    care_gap_category = case_when(
      !confirmed_hl & hl_diagnosis_codes == 0 ~ "No HL diagnosis codes in data",
      !confirmed_hl & hl_diagnosis_codes > 0  ~ "Has HL codes but not confirmed (< 2 codes or < 7 days)",
      confirmed_hl & died_before_first_hl_dx  ~ "Confirmed HL but died before first HL diagnosis date",
      confirmed_hl & total_encounters == 0     ~ "Confirmed HL, no encounter records",
      confirmed_hl & total_encounters > 0      ~ "Confirmed HL with encounters but no treatment records",
      TRUE ~ "Other / Unknown"
    )
  ) %>%
  select(
    ID, DEATH_DATE, DEATH_SOURCE, confirmed_hl, first_hl_dx_date,
    hl_diagnosis_codes, age_at_death, SEX, RACE,
    total_encounters, total_diagnoses, enrollment_periods,
    first_enrollment, last_enrollment, care_gap_category
  )

message("\n  Death-only patients by care gap category:")
death_only_investigation %>%
  count(care_gap_category) %>%
  arrange(desc(n)) %>%
  {walk2(.$care_gap_category, .$n, ~message(glue("    {.x}: {.y}")))}


# ==============================================================================
# SECTION 7: BUILD COMBINED VALIDATION DATASET AND SAVE RDS (per D-12)
# ==============================================================================

message("\n--- Building combined validation dataset ---")

# Combine impossible_deaths + valid_deaths into full validation dataset
all_validated <- bind_rows(
  impossible_deaths %>% select(ID, DEATH_DATE, DEATH_SOURCE, death_valid, validation_reason, earliest_treatment_date),
  valid_deaths %>% select(ID, DEATH_DATE, DEATH_SOURCE, death_valid, validation_reason, post_death_activity,
                          post_death_encounters, post_death_diagnoses, post_death_treatments)
)

message(glue("  Total validated death records: {nrow(all_validated)}"))

# Save RDS (minimum schema per Claude's discretion: ID, DEATH_DATE, death_valid, post_death_activity)
validated_rds <- valid_deaths %>%
  select(ID, DEATH_DATE, DEATH_SOURCE, death_valid, post_death_activity) %>%
  bind_rows(
    impossible_deaths %>%
      select(ID, DEATH_SOURCE) %>%
      mutate(DEATH_DATE = as.Date(NA), death_valid = FALSE, post_death_activity = NA)
  )

saveRDS(validated_rds, OUTPUT_RDS)
message(glue("\nSaved validated death dates RDS: {OUTPUT_RDS}"))

# Save CSV flat export
write.csv(all_validated, OUTPUT_CSV, row.names = FALSE)
message(glue("Saved CSV export: {OUTPUT_CSV}"))


# ==============================================================================
# SECTION 8: BUILD THREE-SHEET XLSX REPORT (per D-10)
# ==============================================================================

message("\n--- Building three-sheet XLSX report ---")

wb <- wb_workbook()

# ---------- SHEET 1: VALIDATION SUMMARY ----------

wb$add_worksheet("Validation Summary")

# Title row (A1)
wb$add_data(sheet = "Validation Summary", x = "Death Date Validation Report",
            start_row = 1, start_col = 1)
wb$add_font(sheet = "Validation Summary", dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Validation Summary", dims = "A1:D1")

# Subtitle row (A2)
subtitle <- glue("Generated: {Sys.Date()} | Population: All patients with death dates (per D-11)")
wb$add_data(sheet = "Validation Summary", x = subtitle, start_row = 2, start_col = 1)
wb$add_font(sheet = "Validation Summary", dims = "A2",
            name = "Calibri", size = 10, color = wb_color("FF6B7280"))
wb$merge_cells(sheet = "Validation Summary", dims = "A2:D2")

# Summary statistics table starting row 4
summary_stats <- tibble(
  Metric = c(
    "Total patients with death dates",
    "Patients with treatment records",
    "Impossible death dates (total)",
    "  - Death before treatment",
    "  - Death before HL Diagnosis",
    "Valid death dates retained",
    "Patients with post-death clinical activity",
    "  - Post-death encounters",
    "  - Post-death diagnoses",
    "  - Post-death treatments",
    "Patients with death dates but no treatments",
    "  - Confirmed HL patients",
    "  - Not confirmed HL"
  ),
  Count = c(
    nrow(death_data),
    nrow(death_with_treatment),
    nrow(impossible_deaths),
    sum(impossible_deaths$validation_reason == "Death date before earliest treatment date", na.rm = TRUE),
    sum(impossible_deaths$validation_reason == "Death date before HL diagnosis date", na.rm = TRUE),
    sum(valid_deaths$death_valid),
    sum(valid_deaths$post_death_activity),
    sum(valid_deaths$post_death_encounters > 0),
    sum(valid_deaths$post_death_diagnoses > 0),
    sum(valid_deaths$post_death_treatments > 0),
    nrow(death_only_patients),
    sum(death_only_investigation$confirmed_hl),
    sum(!death_only_investigation$confirmed_hl)
  )
)

# Write summary table starting row 4
wb$add_data(sheet = "Validation Summary", x = summary_stats, start_row = 4, start_col = 1)

# Header row styling
wb$add_fill(sheet = "Validation Summary", dims = "A4:B4", color = wb_color("FF374151"))
wb$add_font(sheet = "Validation Summary", dims = "A4:B4",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Number formatting
data_rows <- glue("B5:B{4 + nrow(summary_stats)}")
wb$add_numfmt(sheet = "Validation Summary", dims = data_rows, numfmt = "#,##0")

# Column widths
wb$set_col_widths(sheet = "Validation Summary", cols = 1:2, widths = c(55, 15))

# Freeze pane below header row
wb$freeze_pane(sheet = "Validation Summary", firstActiveRow = 5)


# ---------- SHEET 2: FLAGGED PATIENTS ----------

wb$add_worksheet("Flagged Patients")

# Combine impossible deaths + post-death activity patients
flagged_detail <- bind_rows(
  impossible_deaths %>%
    mutate(flag_type = case_when(
      validation_reason == "Death date before HL diagnosis date" ~ "Impossible death (before HL Diagnosis)",
      TRUE ~ "Impossible death (before treatment)"
    )) %>%
    select(ID, DEATH_DATE, DEATH_SOURCE, earliest_treatment_date, flag_type, validation_reason),
  valid_deaths %>%
    filter(post_death_activity) %>%
    left_join(earliest_treatment, by = c("ID" = "patient_id")) %>%
    mutate(flag_type = "Post-death clinical activity") %>%
    select(ID, DEATH_DATE, DEATH_SOURCE, earliest_treatment_date, flag_type,
           post_death_encounters, post_death_diagnoses, post_death_treatments) %>%
    mutate(validation_reason = glue("{post_death_encounters} encounters, {post_death_diagnoses} diagnoses, {post_death_treatments} treatments after death"))
)

# Write with standard header styling
wb$add_data(sheet = "Flagged Patients", x = flagged_detail, start_row = 1, start_col = 1)
wb$add_fill(sheet = "Flagged Patients", dims = "A1:F1", color = wb_color("FF374151"))
wb$add_font(sheet = "Flagged Patients", dims = "A1:F1",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
wb$set_col_widths(sheet = "Flagged Patients", cols = 1:6, widths = c(15, 15, 15, 20, 35, 50))

# Freeze pane on first row
wb$freeze_pane(sheet = "Flagged Patients", firstActiveRow = 2)


# ---------- SHEET 3: DEATH ONLY PATIENTS ----------

wb$add_worksheet("Death Only Patients")

# Write death_only_investigation with standard header styling
wb$add_data(sheet = "Death Only Patients", x = death_only_investigation, start_row = 1, start_col = 1)
wb$add_fill(sheet = "Death Only Patients", dims = "A1:O1", color = wb_color("FF374151"))
wb$add_font(sheet = "Death Only Patients", dims = "A1:O1",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
wb$set_col_widths(sheet = "Death Only Patients", cols = 1:15,
                  widths = c(15, 15, 15, 12, 15, 15, 12, 8, 15, 15, 15, 15, 15, 15, 50))

# Freeze pane on first row
wb$freeze_pane(sheet = "Death Only Patients", firstActiveRow = 2)

# Save workbook
wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)
message(glue("Saved XLSX report: {OUTPUT_XLSX}"))


# ==============================================================================
# SECTION 9: FINAL SUMMARY
# ==============================================================================

message("\n=== Death Date Validation Complete ===\n")
message("Output files:")
message(glue("  XLSX report (3 sheets): {OUTPUT_XLSX}"))
message(glue("  CSV flat export:        {OUTPUT_CSV}"))
message(glue("  Validated RDS artifact: {OUTPUT_RDS}\n"))

message("Key validation findings:")
message(glue("  Total patients with death dates: {nrow(death_data)}"))
n_before_tx <- sum(impossible_deaths$validation_reason == "Death date before earliest treatment date", na.rm = TRUE)
n_before_hl <- sum(impossible_deaths$validation_reason == "Death date before HL diagnosis date", na.rm = TRUE)
message(glue("  Impossible deaths (total): {nrow(impossible_deaths)}"))
message(glue("    - Before treatment: {n_before_tx}"))
message(glue("    - Before HL Diagnosis: {n_before_hl}"))
message(glue("  Valid deaths retained: {sum(valid_deaths$death_valid)}"))
message(glue("  Patients with post-death activity: {sum(valid_deaths$post_death_activity)}"))
message(glue("  Death-only patients (no treatment records): {nrow(death_only_patients)}"))
message(glue("    - Confirmed HL: {sum(death_only_investigation$confirmed_hl)}"))
message(glue("    - Not confirmed HL: {sum(!death_only_investigation$confirmed_hl)}\n"))
