# ==============================================================================
# 56_new_tables_from_groupings.R -- Drug Grouping Summary Tables
# ==============================================================================
#
# Purpose:
#   Generate two drug grouping summary tables matching all_codes_resolved_next_tables.xlsx
#   Sheet1 templates: (1) treatment-type-level summary stratified by cancer codes,
#   (2) drug-level summary stratified by cancer codes. Provides encounter counts
#   by treatment type and individual drug/treatment code crossed with raw diagnosis codes.
#
# Inputs:
#   - cache/outputs/treatment_episodes.rds (from R/28, 17 columns including
#     triggering_codes, cancer_category, drug_group, ENCOUNTERID)
#   - DuckDB DIAGNOSIS table (for raw ICD cancer codes per encounter)
#   - R/00_config.R (DRUG_GROUPINGS named vector, CONFIG paths)
#
# Outputs:
#   - output/drug_grouping_tables.xlsx (2-sheet workbook:
#     Sheet 1 = "Treatment Type Summary", Sheet 2 = "Drug Level Summary")
#
# Dependencies:
#   - R/00_config.R (DRUG_GROUPINGS, CONFIG paths)
#   - R/utils/utils_assertions.R (assert_rds_exists, assert_df_valid, warn_row_count)
#   - R/utils/utils_duckdb.R (open_pcornet_con, get_pcornet_table)
#   - openxlsx2 (multi-sheet xlsx output)
#
# Requirements:
#   - TREAT-03: Two new summary tables matching all_codes_resolved_next_tables.xlsx
#     Sheet1 templates with treatment-type-level and drug-level summaries
#   - QUAL-01: v2.0 script standards (documentation, assertions, section structure)
#
# Decision Traceability:
#   - D-12: Single xlsx output with 2 sheets matching templates
#   - D-13: Table 1 (treatment-type-level): treatment_type | cancer_codes | encounter_count
#   - D-14: Table 2 (drug-level): treatment_code | cancer_codes | encounter_count
#   - D-15: Cancer codes = raw ICD codes (semicolon-separated), not category labels
#   - D-16: Data source = treatment_episodes.rds + DuckDB DIAGNOSIS join via ENCOUNTERID
#
# WHY semicolon-separated cancer codes: Matches all_codes_resolved_next_tables.xlsx
# template format (D-15). Distinguishes cancer codes (semicolons) from treatment
# codes (commas in triggering_codes field).
#
# WHY encounter-level cancer linkage: treatment_episodes.rds contains ENCOUNTERID
# from R/28 Phase 61 encounter-level cancer linkage. Most reliable connection
# between treatment and diagnosis codes (same admission/visit context).
#
# ==============================================================================

# SECTION 1: SETUP AND CONFIGURATION ----

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(glue)
  library(stringr)
  library(openxlsx2)
  library(checkmate)
})

source("R/00_config.R")
source("R/utils/utils_assertions.R")
source("R/utils/utils_duckdb.R")

EPISODES_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "drug_grouping_tables.xlsx")

message("=== Phase 79: Drug Grouping Summary Tables ===\n")
message(glue("  Input:  {EPISODES_RDS}"))
message(glue("  Output: {OUTPUT_XLSX}\n"))


# SECTION 2: LOAD AND VALIDATE INPUT DATA ----

message("--- Loading treatment episodes ---")

assert_rds_exists(EPISODES_RDS, script_name = "R/56")
episodes <- readRDS(EPISODES_RDS)

assert_df_valid(
  episodes,
  name = "treatment_episodes",
  required_cols = c("patient_id", "treatment_type", "triggering_codes", "cancer_category", "ENCOUNTERID"),
  script_name = "R/56"
)

message(glue("  Loaded {nrow(episodes)} treatment episodes"))
message(glue("  Treatment types: {paste(unique(episodes$treatment_type), collapse = ', ')}"))


# SECTION 3: PREPARE CANCER CODES FROM ENCOUNTER-LEVEL LINKAGE ----

message("\n--- Extracting raw cancer ICD codes from encounter linkage ---")

# Treatment episodes have ENCOUNTERID from Phase 61 encounter-level cancer linkage.
# Query DuckDB DIAGNOSIS table to get raw ICD codes for each encounter.

USE_DUCKDB <- TRUE
open_pcornet_con()

# Get all diagnosis codes for encounters in treatment_episodes
dx_data <- get_pcornet_table("DIAGNOSIS") %>%
  filter(ENCOUNTERID %in% !!unique(na.omit(episodes$ENCOUNTERID))) %>%
  select(ENCOUNTERID, DX, DX_TYPE) %>%
  collect()

message(glue("  Loaded {nrow(dx_data)} diagnosis records"))
message(glue("  Unique encounters with diagnoses: {n_distinct(dx_data$ENCOUNTERID)}"))

# Aggregate diagnosis codes per encounter (semicolon-separated per D-15)
encounter_dx <- dx_data %>%
  group_by(ENCOUNTERID) %>%
  summarise(
    cancer_codes = paste(sort(unique(DX)), collapse = ";"),
    .groups = "drop"
  )

message(glue("  Created cancer code sets for {nrow(encounter_dx)} encounters"))

# Join cancer codes to episodes
pre_join_rows <- nrow(episodes)

episode_dx <- episodes %>%
  left_join(encounter_dx, by = "ENCOUNTERID")

# Cartesian product guard (Pitfall 3 from RESEARCH.md)
warn_row_count(
  episode_dx,
  name = "episode_dx_joined",
  expected_min = pre_join_rows,
  expected_max = pre_join_rows * 1.1,
  script_name = "R/56"
)

message(glue("  Joined cancer codes to episodes: {nrow(episode_dx)} rows (expected {pre_join_rows})"))

# Handle episodes without ENCOUNTERID match
n_missing_cancer <- sum(is.na(episode_dx$cancer_codes))
if (n_missing_cancer > 0) {
  message(glue("  WARNING: {n_missing_cancer} episodes without cancer codes (no ENCOUNTERID match)"))
}


# SECTION 4: TABLE 1 -- TREATMENT-TYPE-LEVEL SUMMARY (per D-13) ----

message("\n--- Building Table 1: Treatment-Type-Level Summary ---")

# One row per unique treatment-type + cancer-code-set combination
table1 <- episode_dx %>%
  mutate(cancer_codes = if_else(is.na(cancer_codes), "Unknown", cancer_codes)) %>%
  group_by(treatment_type, cancer_codes) %>%
  summarise(encounter_count = n(), .groups = "drop") %>%
  arrange(treatment_type, desc(encounter_count))

message(glue("  Table 1: {nrow(table1)} unique treatment-type x cancer-code combinations"))

# Log per-type totals
type_summary <- episode_dx %>%
  group_by(treatment_type) %>%
  summarise(total_episodes = n(), .groups = "drop")

for (i in seq_len(nrow(type_summary))) {
  message(glue("    {type_summary$treatment_type[i]}: {type_summary$total_episodes[i]} episodes"))
}


# SECTION 5: TABLE 2 -- DRUG-LEVEL SUMMARY (per D-14) ----

message("\n--- Building Table 2: Drug-Level Summary ---")

# Split triggering_codes (comma-separated) into individual codes per episode
episode_codes <- episode_dx %>%
  mutate(code_list = str_split(triggering_codes, ",\\s*")) %>%
  unnest(code_list) %>%
  filter(!is.na(code_list), code_list != "") %>%
  rename(treatment_code = code_list)

message(glue("  Expanded to {nrow(episode_codes)} treatment code instances"))

# Aggregate by treatment code x cancer code combination
table2 <- episode_codes %>%
  mutate(cancer_codes = if_else(is.na(cancer_codes), "Unknown", cancer_codes)) %>%
  group_by(treatment_code, cancer_codes) %>%
  summarise(encounter_count = n(), .groups = "drop") %>%
  arrange(treatment_code, desc(encounter_count))

message(glue("  Table 2: {nrow(table2)} unique treatment-code x cancer-code combinations"))
message(glue("  Unique treatment codes: {n_distinct(table2$treatment_code)}"))


# SECTION 6: WRITE XLSX OUTPUT (per D-12) ----

message("\n--- Writing multi-sheet XLSX output ---")

wb <- wb_workbook()

# Sheet 1: Treatment Type Summary
wb$add_worksheet("Treatment Type Summary")
wb$add_data("Treatment Type Summary", table1, start_row = 1, col_names = TRUE)

# Sheet 2: Drug Level Summary
wb$add_worksheet("Drug Level Summary")
wb$add_data("Drug Level Summary", table2, start_row = 1, col_names = TRUE)

wb$save(OUTPUT_XLSX)
message(glue("\nSaved: {OUTPUT_XLSX}"))


# SECTION 7: CONSOLE SUMMARY ----

message("\n=== Summary ===")
message(glue("  Total episodes processed: {nrow(episodes)}"))
message(glue("  Episodes with cancer codes: {sum(!is.na(episode_dx$cancer_codes))}"))
message(glue("  Episodes without cancer codes: {sum(is.na(episode_dx$cancer_codes))}"))
message(glue("\n  Table 1 (Treatment Type Summary):"))
message(glue("    Total rows: {nrow(table1)}"))
for (i in seq_len(nrow(type_summary))) {
  type_rows <- table1 %>% filter(treatment_type == type_summary$treatment_type[i]) %>% nrow()
  message(glue("    {type_summary$treatment_type[i]}: {type_rows} unique cancer-code combinations"))
}
message(glue("\n  Table 2 (Drug Level Summary):"))
message(glue("    Total rows: {nrow(table2)}"))
message(glue("    Unique treatment codes: {n_distinct(table2$treatment_code)}"))
message("\nDone.")
