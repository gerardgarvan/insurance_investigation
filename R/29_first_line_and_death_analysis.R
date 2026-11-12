# ==============================================================================
# 29_first_line_and_death_analysis.R -- First-Line Therapy Flagging and Death Validation
# ==============================================================================
# [161-07 audit] Exempt: raw-data study — cross-references recorded DEATH_DATE against treatment
# timelines to detect impossible deaths. Raw dates are required; resolved dates would hide the
# anomalies under investigation (post-death activity is the subject, not an endpoint to censor).
# Purpose:     First-line therapy flagging (60-day clean period before first treatment)
#              and death date validation cross-referenced against treatment timeline.
#
# Inputs:      treatment_episodes_stage2.rds (from R/28; D-197 staged chain), treatment_episode_detail.rds,
#              validated_death_dates.rds (from R/53), PCORnet DEATH table
#
# Outputs:     cache/outputs/treatment_episodes.rds (modified with is_first_line),
#              cache/outputs/first_line_therapy.rds, output/death_analysis.xlsx
#
# Dependencies: R/00_config.R, R/utils/utils_duckdb.R, R/utils/utils_dates.R
#
# Requirements: Phase 62 first-line flagging + death date analysis
#
# WHY 60-day clean period: Standard oncology definition of first-line therapy. No
# prior chemotherapy in 60 days before regimen start means this is the first course
# of treatment (not continuation or relapse therapy).
#
# WHY death date validation cross-reference: Impossible deaths (death date before last
# treatment date) indicate data quality issues. Post-death activity stratified by
# ENC_TYPE reveals administrative vs clinical encounter patterns.
#
# Part 1: First-line therapy flagging (adults 21+, 60-day clean period)
# Part 2: Death date data quality analysis (validated deaths, impossible deaths)

# SECTION 1: SETUP AND CONFIGURATION ----

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(lubridate)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_dates.R")

# Input: enriched from R/28 (stage2); Output: canonical treatment_episodes.rds (sole final writer per D-197-01)
INPUT_RDS  <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes_stage2.rds")
OUTPUT_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
DETAIL_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds")
DEATH_RDS  <- file.path(CONFIG$cache$outputs_dir, "validated_death_dates.rds")
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "death_analysis.xlsx")
OUTPUT_CSV <- file.path(CONFIG$output_dir, "death_analysis.csv")

message("=== Phase 62: First-Line Therapy & Death Analysis ===\n")
message("Input files:")
message(glue("  treatment_episodes_stage2.rds: {INPUT_RDS}"))
message(glue("  treatment_episode_detail.rds: {DETAIL_RDS}"))
message(glue("  validated_death_dates.rds: {DEATH_RDS}"))
message("\nOutput files:")
message(glue("  treatment_episodes.rds (modified): {OUTPUT_RDS}"))
message(glue("  death_analysis.xlsx: {OUTPUT_XLSX}"))
message(glue("  death_analysis.csv: {OUTPUT_CSV}\n"))

# ==============================================================================
# SECTION 2: LOAD DATA
# ==============================================================================

message("--- Loading data ---")

# SAFE-01: Validate all 3 input RDS files exist before loading
assert_rds_exists(INPUT_RDS,  script_name = "R/29")
assert_rds_exists(DETAIL_RDS, script_name = "R/29")
assert_rds_exists(DEATH_RDS,  script_name = "R/29")

# Load treatment episodes (stage1 from R/26)
episodes <- readRDS(INPUT_RDS)
message(glue("  Loaded treatment_episodes_stage2.rds: {nrow(episodes)} episodes"))

# Load treatment episode detail (for individual chemo dates)
episode_detail <- readRDS(DETAIL_RDS)
message(glue("  Loaded treatment_episode_detail.rds: {nrow(episode_detail)} rows"))

# Load validated death dates (Phase 59 artifact)
validated_deaths <- readRDS(DEATH_RDS)
message(glue("  Loaded validated_death_dates.rds: {nrow(validated_deaths)} patients"))

# SAFE-02: Validate data frame structure
assert_df_valid(episodes, "treatment_episodes",
                required_cols = c("patient_id", "treatment_type", "episode_number"),
                script_name = "R/29")
assert_df_valid(episode_detail, "treatment_episode_detail",
                required_cols = c("patient_id", "treatment_type"),
                script_name = "R/29")
assert_df_valid(validated_deaths, "validated_deaths",
                required_cols = c("ID"),
                script_name = "R/29", allow_empty = TRUE)

# Assert R/28 enrichment columns are present — stop() if missing (D-197; stage2 must come from R/28)
req_cols_from_r28 <- c("regimen_label", "drug_names", "cancer_category",
                        "cancer_link_method", "is_hodgkin",
                        "triggering_code_description", "drug_group")
missing_r28 <- setdiff(req_cols_from_r28, names(episodes))
if (length(missing_r28) > 0)
  stop("[R/29] R/28 enrichment columns missing from input — run R/28 before R/29. Missing: ",
       paste(missing_r28, collapse = ", "))

# Open DuckDB connection
USE_DUCKDB <- TRUE
open_pcornet_con()

# Query DEMOGRAPHIC table for age calculation
demographics <- get_pcornet_table("DEMOGRAPHIC") %>%
  select(ID, BIRTH_DATE) %>%
  collect() %>%
  mutate(BIRTH_DATE = parse_pcornet_date(BIRTH_DATE)) %>%
  filter(!is.na(BIRTH_DATE))
message(glue("  Loaded DEMOGRAPHIC table: {nrow(demographics)} patients with birth dates"))

# ==============================================================================
# SECTION 3: FIRST-LINE THERAPY IDENTIFICATION
# ==============================================================================

message("\n--- First-Line Therapy Identification ---")

# Step 3a: Filter to eligible episodes (per D-01: must have regimen_label)
eligible_episodes <- episodes %>%
  filter(treatment_type == "Chemotherapy") %>%
  filter(!is.na(regimen_label))

message(glue("  Episodes with regimen labels: {nrow(eligible_episodes)} from {n_distinct(eligible_episodes$patient_id)} patients"))

# Step 3b: Join demographics and filter to adults 21+ (per D-02)
eligible_episodes <- eligible_episodes %>%
  left_join(demographics, by = c("patient_id" = "ID")) %>%
  mutate(age_at_treatment = as.numeric(difftime(episode_start, BIRTH_DATE, units = "days")) / 365.25) %>%
  filter(age_at_treatment >= 21)

message(glue("  Adults 21+ at treatment: {nrow(eligible_episodes)} episodes from {n_distinct(eligible_episodes$patient_id)} patients"))

# Step 3c: Check 60-day clean period using ALL individual chemo dates (per D-03)
# Extract ALL chemo dates from episode_detail (NOT episode boundaries)
all_chemo_dates <- episode_detail %>%
  filter(treatment_type == "Chemotherapy") %>%
  select(patient_id, treatment_date) %>%
  distinct()

message(glue("  Total distinct chemotherapy dates: {nrow(all_chemo_dates)} from {n_distinct(all_chemo_dates$patient_id)} patients"))

# For each eligible episode, check if ANY prior chemo date falls within 60 days BEFORE episode_start
episodes_with_lookback <- eligible_episodes %>%
  select(patient_id, episode_number, episode_start) %>%
  left_join(all_chemo_dates, by = "patient_id", relationship = "many-to-many") %>%
  mutate(
    days_before = as.numeric(difftime(episode_start, treatment_date, units = "days")),
    is_prior_chemo_in_window = (days_before > 0 & days_before <= 60)
  ) %>%
  group_by(patient_id, episode_number) %>%
  summarise(
    has_prior_chemo_within_60d = any(is_prior_chemo_in_window, na.rm = TRUE),
    .groups = "drop"
  )

# Filter to episodes with clean 60-day period
clean_episodes <- eligible_episodes %>%
  left_join(episodes_with_lookback, by = c("patient_id", "episode_number")) %>%
  filter(!has_prior_chemo_within_60d | is.na(has_prior_chemo_within_60d))

message(glue("  Episodes with 60-day clean period: {nrow(clean_episodes)} from {n_distinct(clean_episodes$patient_id)} patients"))

# Step 3d: Flag ONLY first qualifying episode per patient (per D-04)
first_line_flags <- clean_episodes %>%
  group_by(patient_id) %>%
  arrange(episode_start) %>%
  mutate(rank = row_number()) %>%
  ungroup() %>%
  mutate(is_first_line = (rank == 1)) %>%
  select(patient_id, treatment_type, episode_number, is_first_line)

# Keep only is_first_line=TRUE rows (the first qualifying per patient)
first_line_ids <- first_line_flags %>%
  filter(is_first_line) %>%
  select(patient_id, treatment_type, episode_number)

message(glue("  First-line episodes identified: {nrow(first_line_ids)} patients"))

# Step 3e: Enrich treatment_episodes.rds in-place (per D-09)
if (nrow(first_line_ids) == 0) {
  episodes$is_first_line <- FALSE
} else {
  episodes <- episodes %>%
    left_join(
      first_line_ids %>% mutate(is_first_line = TRUE),
      by = c("patient_id", "treatment_type", "episode_number")
    ) %>%
    mutate(is_first_line = if_else(is.na(is_first_line), FALSE, is_first_line))
}

# --- pre-write validation then atomic save (D-197-02) -----------------------
# Validate the in-memory object; write only if all guards pass.
local({
  # 1. Required columns from R/26, R/28, and R/29
  req_cols <- c("patient_id", "episode_start", "episode_stop",
                "treatment_type", "episode_number",
                "regimen_label", "cancer_category", "cancer_link_method",
                "is_hodgkin", "is_first_line")
  missing_out <- setdiff(req_cols, names(episodes))
  if (length(missing_out) > 0)
    stop("[R/29] required output columns missing: ", paste(missing_out, collapse = ", "))

  # 2. No duplicate on (patient_id, treatment_type, episode_start) — same-day
  #    episodes of different treatment types are valid (D-197-03)
  dup_keys <- episodes |>
    dplyr::count(patient_id, treatment_type, episode_start) |>
    dplyr::filter(n > 1)
  if (nrow(dup_keys) > 0)
    stop("[R/29] treatment_episodes.rds has ", nrow(dup_keys),
         " duplicate (patient_id, treatment_type, episode_start) rows")

  # 3. is_first_line is logical
  if (!is.logical(episodes$is_first_line))
    stop("[R/29] is_first_line is not logical — found: ",
         class(episodes$is_first_line))

  # 4. At least one first-line patient (guard against stage1 regression)
  n_fl <- sum(episodes$is_first_line, na.rm = TRUE)
  if (n_fl == 0)
    stop("[R/29] is_first_line is all FALSE — regimen_label enrichment from R/28 may be missing")

  # 5. is_first_line TRUE only on Chemotherapy rows with non-NA regimen_label
  bad_fl <- episodes %>%
    dplyr::filter(is_first_line) %>%
    dplyr::filter(treatment_type != "Chemotherapy" | is.na(regimen_label))
  if (nrow(bad_fl) > 0)
    stop("[R/29] is_first_line TRUE on ", nrow(bad_fl),
         " non-Chemotherapy or NA-regimen rows — join key fan-out detected")

  # 6. Exactly one is_first_line TRUE per patient
  multi_fl <- episodes %>%
    dplyr::filter(is_first_line) %>%
    dplyr::count(patient_id) %>%
    dplyr::filter(n > 1)
  if (nrow(multi_fl) > 0)
    stop("[R/29] ", nrow(multi_fl), " patients have more than one is_first_line=TRUE row")

  message("[R/29] Pre-write validation: PASS — ",
          nrow(episodes), " rows, ",
          dplyr::n_distinct(episodes$patient_id), " patients, ",
          n_fl, " first-line")
}, envir = environment())

# Atomic write: tmp → rename so a failed save never truncates the target
tmp_rds <- paste0(OUTPUT_RDS, ".tmp")
saveRDS(episodes, tmp_rds)
file.rename(tmp_rds, OUTPUT_RDS)
message(glue("[R/29] treatment_episodes.rds written (canonical) — {nrow(episodes)} rows, is_first_line: {sum(episodes$is_first_line)} TRUE, {sum(!episodes$is_first_line)} FALSE"))
# ---------------------------------------------------------------------------

# Step 3f: Build first-line summary for xlsx (Claude's discretion — add as Sheet 3)
first_line_summary <- episodes %>%
  filter(is_first_line) %>%
  select(
    patient_id, treatment_type, episode_number, episode_start,
    episode_stop, regimen_label, drug_names, is_first_line
  )

# Regimen distribution summary
regimen_dist <- first_line_summary %>%
  count(regimen_label, name = "n_patients") %>%
  arrange(desc(n_patients))

message("\n  First-line regimen distribution:")
print(regimen_dist)

# ==============================================================================
# SECTION 4: DEATH ANALYSIS
# ==============================================================================

message("\n--- Death Analysis ---")

# Step 4a: Filter to validated deaths only (per D-05)
valid_deaths <- validated_deaths %>%
  filter(death_valid == TRUE)

n_with_death <- nrow(valid_deaths)
message(glue("  DEATH-01: Patients with validated death dates: {n_with_death}"))

# Step 4b: Death as last encounter (per D-06)
# Query ENCOUNTER table for max ADMIT_DATE per patient
last_encounters <- get_pcornet_table("ENCOUNTER") %>%
  select(ID, ADMIT_DATE) %>%
  collect() %>%
  mutate(ADMIT_DATE = parse_pcornet_date(ADMIT_DATE)) %>%
  filter(!is.na(ADMIT_DATE)) %>%
  group_by(ID) %>%
  summarise(last_encounter_date = max(ADMIT_DATE), .groups = "drop")

message(glue("  Loaded last encounter dates for {nrow(last_encounters)} patients"))

# Join validated deaths to last encounter and compare
death_vs_encounter <- valid_deaths %>%
  left_join(last_encounters, by = "ID") %>%
  mutate(
    has_encounters = !is.na(last_encounter_date),
    death_is_last = case_when(
      is.na(last_encounter_date) ~ TRUE, # No encounters → death is "last" by default
      DEATH_DATE >= last_encounter_date ~ TRUE,
      TRUE ~ FALSE
    )
  )

n_death_is_last <- sum(death_vs_encounter$death_is_last, na.rm = TRUE)
n_no_encounters <- sum(!death_vs_encounter$has_encounters)
message(glue("  DEATH-02: Death is last encounter: {n_death_is_last} (includes {n_no_encounters} with no encounter records)"))

# Step 4c: Post-death encounters stratified by ENC_TYPE (per D-07, D-08)
# Total count using Phase 59's flag (per D-08)
n_post_death <- sum(valid_deaths$post_death_activity, na.rm = TRUE)
message(glue("  DEATH-03: Patients with post-death activity: {n_post_death} (from Phase 59 flag)"))

# Query ENCOUNTER for NEW ENC_TYPE stratification (per D-07)
post_death_by_enc_type <- get_pcornet_table("ENCOUNTER") %>%
  select(ID, ADMIT_DATE, ENC_TYPE) %>%
  collect() %>%
  mutate(ADMIT_DATE = parse_pcornet_date(ADMIT_DATE)) %>%
  filter(!is.na(ADMIT_DATE)) %>%
  inner_join(valid_deaths %>% select(ID, DEATH_DATE), by = "ID") %>%
  filter(ADMIT_DATE > DEATH_DATE)

# Patient-level count by ENC_TYPE (unique patients per type, not encounter count)
enc_type_patient_counts <- post_death_by_enc_type %>%
  distinct(ID, ENC_TYPE) %>%
  count(ENC_TYPE, name = "n_patients") %>%
  arrange(desc(n_patients))

# Encounter-level count by ENC_TYPE
enc_type_encounter_counts <- post_death_by_enc_type %>%
  count(ENC_TYPE, name = "n_encounters") %>%
  arrange(desc(n_encounters))

# Combine into detail table
enc_type_detail <- enc_type_encounter_counts %>%
  left_join(enc_type_patient_counts, by = "ENC_TYPE") %>%
  arrange(desc(n_encounters))

message("\n  Post-death encounters by ENC_TYPE:")
print(enc_type_detail)

# ==============================================================================
# SECTION 5: OUTPUT — XLSX
# ==============================================================================

message("\n--- Creating xlsx workbook ---")

wb <- wb_workbook()

# Sheet 1: "Death Analysis Summary"
wb$add_worksheet("Death Analysis Summary")

summary_stats <- tibble(
  Metric = c(
    "Total patients with validated death dates (DEATH-01)",
    "Death is last encounter (DEATH-02)",
    "  - With encounter records",
    "  - Without encounter records (death is last by default)",
    "Patients with post-death clinical activity (DEATH-03)",
    "",
    "First-Line Therapy Summary",
    "Total first-line episodes identified",
    "Unique regimens among first-line"
  ),
  Count = c(
    n_with_death,
    n_death_is_last,
    n_death_is_last - n_no_encounters,
    n_no_encounters,
    n_post_death,
    NA_integer_,
    NA_integer_,
    nrow(first_line_summary),
    n_distinct(first_line_summary$regimen_label)
  )
)

wb$add_data(sheet = "Death Analysis Summary", x = summary_stats, start_row = 1, start_col = 1)

# Style header row
wb$add_fill(sheet = "Death Analysis Summary", dims = "A1:B1", color = wb_color("FF374151"))
wb$add_font(
  sheet = "Death Analysis Summary", dims = "A1:B1",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)
wb$set_col_widths(sheet = "Death Analysis Summary", cols = 1:2, widths = c(60, 15))
wb$freeze_pane(sheet = "Death Analysis Summary", firstActiveRow = 2)

# Sheet 2: "Post-Death Encounters by Type"
wb$add_worksheet("Post-Death Encounters by Type")

wb$add_data(sheet = "Post-Death Encounters by Type", x = enc_type_detail, start_row = 1, start_col = 1)

# Style header row
wb$add_fill(sheet = "Post-Death Encounters by Type", dims = "A1:C1", color = wb_color("FF374151"))
wb$add_font(
  sheet = "Post-Death Encounters by Type", dims = "A1:C1",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)
wb$set_col_widths(sheet = "Post-Death Encounters by Type", cols = 1:3, widths = c(15, 20, 20))
wb$freeze_pane(sheet = "Post-Death Encounters by Type", firstActiveRow = 2)

# Sheet 3: "First-Line Patient Detail" (Claude's discretion — QA review sheet)
wb$add_worksheet("First-Line Patient Detail")

wb$add_data(sheet = "First-Line Patient Detail", x = first_line_summary, start_row = 1, start_col = 1)

# Style header row
wb$add_fill(sheet = "First-Line Patient Detail", dims = "A1:H1", color = wb_color("FF374151"))
wb$add_font(
  sheet = "First-Line Patient Detail", dims = "A1:H1",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)
wb$freeze_pane(sheet = "First-Line Patient Detail", firstActiveRow = 2)

# Save workbook
wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)
message(glue("  Saved death_analysis.xlsx: {OUTPUT_XLSX}"))

# ==============================================================================
# SECTION 6: OUTPUT — CSV
# ==============================================================================

message("\n--- Creating CSV export ---")

death_csv <- death_vs_encounter %>%
  select(
    ID, DEATH_DATE, DEATH_SOURCE, death_valid, post_death_activity,
    has_encounters, last_encounter_date, death_is_last
  )

write.csv(death_csv, OUTPUT_CSV, row.names = FALSE)
message(glue("  Saved death_analysis.csv: {OUTPUT_CSV}"))

# ==============================================================================
# SECTION 7: FINAL SUMMARY
# ==============================================================================

message("\n=== Phase 62 Complete ===")
message("\nOutput files:")
message(glue("  treatment_episodes.rds (modified): {OUTPUT_RDS}"))
message(glue("  death_analysis.xlsx: {OUTPUT_XLSX}"))
message(glue("  death_analysis.csv: {OUTPUT_CSV}"))

message("\nKey metrics:")
message(glue("  First-line episodes: {sum(episodes$is_first_line)}"))
message(glue("  DEATH-01 (validated deaths): {n_with_death}"))
message(glue("  DEATH-02 (death is last encounter): {n_death_is_last}"))
message(glue("  DEATH-03 (post-death activity): {n_post_death}"))

message("\nFirst-line regimen distribution:")
print(regimen_dist)

# ==============================================================================
# SECTION 2: OUTPUT ----
# ==============================================================================

message("\n=== Analysis complete ===\n")
