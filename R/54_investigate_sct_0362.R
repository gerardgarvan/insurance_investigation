# ==============================================================================
# 54_investigate_sct_0362.R -- SCT Code 0362 Investigation
# ==============================================================================
#
# Purpose:
#   Investigate SCT code 0362 encounter-level data quality for ~90 patients.
#   Determines whether revenue code 0362 represents true SCT procedures or coding
#   artifacts by cross-referencing against standard SCT codes (CPT 38204-38241,
#   HCPCS S2140/S2142/S2150, revenue 0815) within the same encounters. Produces
#   automated recommendation based on overlap rate.
#
# Inputs:
#   - DuckDB PROCEDURES table (PX, PX_TYPE, PATID, ENCOUNTERID, PX_DATE)
#   - DuckDB DIAGNOSIS table (DX, DX_TYPE, PATID, ENCOUNTERID)
#   - R/00_config.R (TREATMENT_CODES$sct_cpt, sct_hcpcs, sct_revenue)
#
# Outputs:
#   - output/sct_0362_investigation.xlsx (3-sheet workbook)
#     - Sheet 1: Patient Summary (one row per patient)
#     - Sheet 2: Encounter Detail (one row per encounter)
#     - Sheet 3: Summary Statistics (overlap rate and recommendation)
#
# Dependencies:
#   - R/00_config.R (TREATMENT_CODES, CONFIG paths)
#   - R/utils/utils_duckdb.R (open_pcornet_con, get_pcornet_table)
#   - R/utils/utils_assertions.R (assert_df_valid, warn_row_count)
#   - openxlsx2 (multi-sheet workbook output)
#   - checkmate (input validation)
#
# Requirements:
#   - CODE-02: Resolve SCT code 0362 provenance question
#   - QUAL-01: Quality gates for code verification
#
# Decision Traceability:
#   - D-05: Pull full encounter profiles (all procedures + diagnoses per encounter)
#   - D-06: Three-sheet output format (Patient Summary, Encounter Detail, Summary Statistics)
#   - D-07: Automated recommendation based on overlap rate (>80%, <30%, 30-80%)
#
# ==============================================================================

# --- SECTION 1: SETUP AND CONFIGURATION ----

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(openxlsx2)
  library(checkmate)
})

source("R/00_config.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_assertions.R")

OUTPUT_XLSX <- file.path(CONFIG$output_dir, "sct_0362_investigation.xlsx")

message("=== Phase 79: SCT Code 0362 Investigation ===\n")
message(glue("Output: {OUTPUT_XLSX}\n"))


# --- SECTION 2: IDENTIFY 0362 ENCOUNTERS ----

message("--- Loading PROCEDURES table and identifying 0362 encounters ---")

USE_DUCKDB <- TRUE
open_pcornet_con()

# Query PROCEDURES for revenue code 0362
encounters_0362 <- get_pcornet_table("PROCEDURES") %>%
  filter(PX == "0362", PX_TYPE == "RE") %>%
  select(ID, ENCOUNTERID) %>%
  distinct() %>%
  collect()

n_patients <- n_distinct(encounters_0362$ID)
n_encounters <- nrow(encounters_0362)

message(glue("  Found {n_patients} patients with {n_encounters} encounters"))

# Validate results
assert_df_valid(
  encounters_0362,
  name = "encounters_0362",
  required_cols = c("ID", "ENCOUNTERID"),
  script_name = "R/54",
  allow_empty = FALSE
)


# --- SECTION 3: PULL FULL ENCOUNTER PROFILES ----

message("--- Pulling full encounter profiles (all procedures + diagnoses) ---")

# Pull ALL procedures for these encounters
procedures_full <- get_pcornet_table("PROCEDURES") %>%
  semi_join(encounters_0362, by = c("ID", "ENCOUNTERID")) %>%
  select(ID, ENCOUNTERID, PX, PX_TYPE, PX_DATE, ADMIT_DATE) %>%
  collect()

message(glue("  Procedures: {nrow(procedures_full)} records"))

# Pull ALL diagnoses for these encounters
diagnoses_full <- get_pcornet_table("DIAGNOSIS") %>%
  semi_join(encounters_0362, by = c("ID", "ENCOUNTERID")) %>%
  select(ID, ENCOUNTERID, DX, DX_TYPE) %>%
  collect()

message(glue("  Diagnoses: {nrow(diagnoses_full)} records"))

# Validate
assert_df_valid(
  procedures_full,
  name = "procedures_full",
  required_cols = c("ID", "ENCOUNTERID", "PX"),
  script_name = "R/54"
)

assert_df_valid(
  diagnoses_full,
  name = "diagnoses_full",
  required_cols = c("ID", "ENCOUNTERID", "DX"),
  script_name = "R/54"
)


# --- SECTION 4: DETECT STANDARD SCT CODES ----

message("--- Detecting standard SCT codes in same encounters ---")

# Define standard SCT codes (CPT, HCPCS, revenue 0815)
standard_sct_codes <- c(
  TREATMENT_CODES$sct_cpt,
  TREATMENT_CODES$sct_hcpcs,
  "0815" # revenue code 0815 = allogeneic stem cell acquisition
)

message(glue("  Standard SCT codes: {paste(standard_sct_codes, collapse=', ')}"))

# Mark procedures that are standard SCT codes
procedures_with_sct_flag <- procedures_full %>%
  mutate(is_standard_sct = PX %in% standard_sct_codes)

# Summarize per encounter: does it have any standard SCT codes?
encounter_sct_summary <- procedures_with_sct_flag %>%
  group_by(ID, ENCOUNTERID) %>%
  summarize(
    has_standard_sct = any(is_standard_sct),
    other_sct_codes = paste(unique(PX[is_standard_sct]), collapse = ", "),
    n_procedures = n(),
    .groups = "drop"
  ) %>%
  mutate(other_sct_codes = if_else(other_sct_codes == "", NA_character_, other_sct_codes))

# Summarize per patient
patient_sct_summary <- encounter_sct_summary %>%
  group_by(ID) %>%
  summarize(
    encounter_count = n(),
    has_other_sct = any(has_standard_sct),
    other_sct_codes_found = paste(unique(na.omit(other_sct_codes)), collapse = ", "),
    n_procedures_total = sum(n_procedures),
    .groups = "drop"
  ) %>%
  mutate(other_sct_codes_found = if_else(other_sct_codes_found == "", NA_character_, other_sct_codes_found))

# Add diagnosis counts per patient
patient_dx_counts <- diagnoses_full %>%
  group_by(ID) %>%
  summarize(n_diagnoses_total = n(), .groups = "drop")

patient_summary <- patient_sct_summary %>%
  left_join(patient_dx_counts, by = "ID") %>%
  mutate(n_diagnoses_total = if_else(is.na(n_diagnoses_total), 0L, as.integer(n_diagnoses_total)))

# Calculate overlap rate
n_with_sct <- sum(patient_summary$has_other_sct)
n_total <- nrow(patient_summary)
overlap_rate_pct <- round(100 * n_with_sct / n_total, 1)

message(glue("  Overlap rate: {overlap_rate_pct}% ({n_with_sct}/{n_total} patients have standard SCT codes)"))


# --- SECTION 5: BUILD OUTPUT TABLES ----

message("--- Building output tables ---")

# Sheet 1: Patient Summary
patient_summary_output <- patient_summary %>%
  select(
    PATID = ID,
    encounter_count,
    has_other_sct,
    other_sct_codes_found,
    n_procedures_total,
    n_diagnoses_total
  ) %>%
  arrange(desc(has_other_sct), PATID)

# Sheet 2: Encounter Detail
# Build all_procedures and all_diagnoses comma-separated lists
encounter_procedures <- procedures_full %>%
  group_by(ID, ENCOUNTERID) %>%
  summarize(
    all_procedures = paste(unique(PX), collapse = ", "),
    encounter_date = min(coalesce(PX_DATE, ADMIT_DATE), na.rm = TRUE),
    .groups = "drop"
  )

encounter_diagnoses <- diagnoses_full %>%
  group_by(ID, ENCOUNTERID) %>%
  summarize(
    all_diagnoses = paste(unique(DX), collapse = ", "),
    .groups = "drop"
  )

encounter_detail_output <- encounter_sct_summary %>%
  left_join(encounter_procedures, by = c("ID", "ENCOUNTERID")) %>%
  left_join(encounter_diagnoses, by = c("ID", "ENCOUNTERID")) %>%
  select(
    PATID = ID,
    ENCOUNTERID,
    encounter_date,
    all_procedures,
    all_diagnoses,
    has_standard_sct
  ) %>%
  arrange(PATID, ENCOUNTERID)

# Sheet 3: Summary Statistics with automated recommendation
recommendation <- case_when(
  overlap_rate_pct > 80 ~ "CONFIRMED SCT: >80% of 0362 patients have standard SCT codes",
  overlap_rate_pct < 30 ~ "LIKELY CODING ARTIFACT: <30% have standard SCT codes",
  TRUE ~ "MANUAL REVIEW NEEDED: 30-80% overlap rate"
)

summary_stats <- tibble(
  metric = c(
    "total_patients",
    "total_encounters",
    "patients_with_other_sct",
    "patients_without_other_sct",
    "overlap_rate_pct",
    "recommendation"
  ),
  value = c(
    as.character(n_total),
    as.character(n_encounters),
    as.character(n_with_sct),
    as.character(n_total - n_with_sct),
    as.character(overlap_rate_pct),
    recommendation
  )
)


# --- SECTION 6: WRITE XLSX OUTPUT ----

message("--- Writing multi-sheet workbook ---")

wb <- wb_workbook()

# Sheet 1
wb$add_worksheet("Patient Summary")
wb$add_data("Patient Summary", patient_summary_output, start_row = 1, col_names = TRUE)

# Sheet 2
wb$add_worksheet("Encounter Detail")
wb$add_data("Encounter Detail", encounter_detail_output, start_row = 1, col_names = TRUE)

# Sheet 3
wb$add_worksheet("Summary Statistics")
wb$add_data("Summary Statistics", summary_stats, start_row = 1, col_names = TRUE)

wb$save(OUTPUT_XLSX)

message(glue("  Wrote: {OUTPUT_XLSX}"))


# --- SECTION 7: CONSOLE SUMMARY ----

message("\n=== INVESTIGATION COMPLETE ===\n")
message(glue("Total patients: {n_total}"))
message(glue("Total encounters: {n_encounters}"))
message(glue("Patients with standard SCT codes: {n_with_sct} ({overlap_rate_pct}%)"))
message(glue("Patients without standard SCT codes: {n_total - n_with_sct} ({round(100 - overlap_rate_pct, 1)}%)"))
message(glue("\nRecommendation: {recommendation}\n"))
