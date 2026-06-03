# =============================================================================
# Phase 51: Gantt Chart Data Export
# =============================================================================
#
# Purpose:
#   Combine treatment episode and detail RDS artifacts into two CSV files
#   for third-party Gantt chart visualization (v1 schema with cancer categories)
#
# Inputs:
#   - cache/outputs/treatment_episodes.rds (episode-level)
#   - cache/outputs/treatment_episode_detail.rds (detail-level)
#   - cache/outputs/code_descriptions.rds (Phase 02: code -> description lookup)
#   - output/tables/cancer_summary.csv (Phase 55/57: cancer code -> category mapping)
#   - cache/outputs/confirmed_hl_cohort.rds (Phase 59: HL diagnosis dates for treatment rows)
#   - cache/outputs/validated_death_dates.rds (Phase 59: pre-validated death dates, impossible deaths excluded)
#
# Outputs:
#   - output/gantt_episodes.csv (bars: one row per patient/type/episode)
#   - output/gantt_detail.csv (ticks: one row per patient/date/code)
#
# Dependencies:
#   - 00_config (CONFIG paths, CANCER_SITE_MAP for cancer classification)
#   - utils_duckdb (get_pcornet_table, connection management)
#   - utils_dates (parse_pcornet_date)
#   - utils_cancer (classify_codes function)
#
# Requirements:
#   DOC-01, DOC-02, DOC-03
#
# =============================================================================


# --- SECTION 1: SETUP AND CONFIGURATION ----

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(lubridate)
})

source("R/00_config.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_dates.R")

# Input paths: existing RDS artifacts from R/44a_treatment_episodes.R
EPISODES_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
DETAIL_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds")

# Output paths: CSV files for third-party Gantt chart consumption
OUTPUT_EPISODES <- file.path(CONFIG$output_dir, "gantt_episodes.csv")
OUTPUT_DETAIL <- file.path(CONFIG$output_dir, "gantt_detail.csv")

# Code description lookup (built by R/48b_build_code_descriptions.R)
DESCRIPTIONS_RDS <- file.path(CONFIG$cache$outputs_dir, "code_descriptions.rds")

# Cancer summary source (R/55 output, patient-code level with cancer_code column)
CANCER_SUMMARY_CSV <- file.path(CONFIG$output_dir, "tables", "cancer_summary.csv")

# Validated death dates (built by R/59_death_date_validation.R, Phase 59)
VALIDATED_DEATHS_RDS <- file.path(CONFIG$cache$outputs_dir, "validated_death_dates.rds")

# Confirmed HL cohort (built by R/55_cancer_summary_refined.R, Phase 55)
COHORT_RDS <- file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds")

# SECTION 0: INPUT VALIDATION ----
# SAFE-01: Validate all input artifacts exist (fail-fast before any loading)
assert_rds_exists(EPISODES_RDS, script_name = "R/51")
assert_rds_exists(DETAIL_RDS, script_name = "R/51")


# --- SECTION 2: LOAD INPUT DATA ----

message("=== Phase 01: Gantt Chart Data Export ===\n")

# Load episode-level data (bars: one row per patient/type/episode)
episodes <- readRDS(EPISODES_RDS)
message(glue("  Loaded {format(nrow(episodes), big.mark = ',')} episode rows"))

# SAFE-02: Validate structure after loading
assert_df_valid(episodes, "treatment_episodes",
  required_cols = c("patient_id", "treatment_type", "episode_start", "episode_stop"),
  script_name = "R/51")

# Load detail-level data (ticks: one row per patient/date/code)
detail <- readRDS(DETAIL_RDS)
message(glue("  Loaded {format(nrow(detail), big.mark = ',')} detail rows"))

# SAFE-02: Validate structure after loading
assert_df_valid(detail, "treatment_episode_detail",
  required_cols = c("patient_id", "treatment_type", "treatment_date", "triggering_code"),
  script_name = "R/51")


# --- SECTION 2B: LOAD AND AGGREGATE CANCER CATEGORIES (per D-01, D-02, D-03) ---

message("\n--- Loading cancer categories ---")

# Cancer summary CSV has columns: ID, cancer_code, description, ...
# It does NOT have a "category" column -- we must derive it via CANCER_SITE_MAP
checkmate::assert_file_exists(CANCER_SUMMARY_CSV, access = "r",
  .var.name = glue("[R/51 ERROR] Cancer summary CSV -- run R/47 first"))

cancer_summary <- read.csv(CANCER_SUMMARY_CSV, stringsAsFactors = FALSE)
message(glue("  Loaded {format(nrow(cancer_summary), big.mark = ',')} cancer summary rows"))

# CANCER_SITE_MAP and classify_codes() provided by R/00_config.R + R/utils/utils_cancer.R

# Derive category for each cancer code
cancer_summary$category <- classify_codes(cancer_summary$cancer_code)
cancer_summary$category[is.na(cancer_summary$category)] <- "Unclassified"

# Aggregate to patient level: comma-separated sorted list of distinct categories (per D-02)
# Alphabetical sort for reproducibility (Claude's discretion, see RESEARCH.md Pitfall 1)
cancer_categories_per_patient <- cancer_summary %>%
  group_by(ID) %>%
  summarise(
    cancer_category = paste(sort(unique(category)), collapse = ","),
    .groups = "drop"
  ) %>%
  mutate(
    is_hodgkin = str_detect(cancer_category, "Hodgkin Lymphoma") # per D-03
  )

message(glue("  Cancer categories aggregated for {format(nrow(cancer_categories_per_patient), big.mark = ',')} patients"))
message(glue("  Hodgkin Lymphoma patients: {sum(cancer_categories_per_patient$is_hodgkin)}"))


# --- SECTION 2C: LOAD VALIDATED DEATH DATA (Phase 59: D-01, D-02) ---

message("\n--- Loading validated death dates (Phase 59) ---")

if (!file.exists(VALIDATED_DEATHS_RDS)) {
  warning("validated_death_dates.rds not found. Run R/59_death_date_validation.R first. Falling back to raw DEATH table.")
  # Fallback: original DuckDB loading pattern (backward compatibility)
  USE_DUCKDB <- TRUE
  open_pcornet_con()
  death_raw <- get_pcornet_table("DEATH")
  if (is.null(death_raw)) {
    warning("DEATH table not found in DuckDB. Death rows will be skipped.")
    death_data <- tibble(ID = character(), DEATH_DATE = as.Date(character()))
  } else {
    death_data <- death_raw %>%
      collect() %>%
      mutate(
        DEATH_DATE = parse_pcornet_date(DEATH_DATE),
        DEATH_DATE = if_else(year(DEATH_DATE) == 1900L, as.Date(NA), DEATH_DATE)
      ) %>%
      filter(!is.na(DEATH_DATE)) %>%
      select(ID, DEATH_DATE) %>%
      group_by(ID) %>%
      summarise(DEATH_DATE = min(DEATH_DATE), .groups = "drop")
  }
  close_pcornet_con()
} else {
  # SAFE-01: Validate RDS exists before loading
  assert_rds_exists(VALIDATED_DEATHS_RDS, script_name = "R/51")
  validated_deaths <- readRDS(VALIDATED_DEATHS_RDS)
  # Keep all patients but only use non-NA death dates (impossible deaths have DEATH_DATE = NA)
  death_data <- validated_deaths %>%
    filter(!is.na(DEATH_DATE)) %>%
    select(ID, DEATH_DATE)

  n_excluded <- sum(validated_deaths$death_valid == FALSE, na.rm = TRUE)
  message(glue("  Loaded validated death dates: {nrow(death_data)} valid, {n_excluded} impossible excluded (per D-02)"))
}

message(glue("  Patients with valid death dates for Gantt: {nrow(death_data)}"))


# --- SECTION 2D: LOAD HL COHORT FOR DIAGNOSIS ROWS (Phase 59: D-07, D-08) ---

message("\n--- Loading HL cohort for diagnosis treatment rows ---")

if (!file.exists(COHORT_RDS)) {
  warning("confirmed_hl_cohort.rds not found. Run R/55_cancer_summary_refined.R first. HL Diagnosis rows will be skipped.")
  hl_cohort <- tibble(
    ID = character(),
    first_hl_dx_date = as.Date(character()),
    first_hl_dx_source = character()
  )
} else {
  # SAFE-01: Validate RDS exists before loading
  assert_rds_exists(COHORT_RDS, script_name = "R/51")
  hl_cohort <- readRDS(COHORT_RDS)
  # Apply 1900 sentinel filtering to HL diagnosis dates (same pattern as death dates)
  hl_cohort <- hl_cohort %>%
    mutate(first_hl_dx_date = if_else(year(first_hl_dx_date) == 1900L, as.Date(NA), first_hl_dx_date)) %>%
    filter(!is.na(first_hl_dx_date))
  message(glue("  Loaded {nrow(hl_cohort)} HL patients with valid first diagnosis dates"))
}


# --- SECTION 3: VALIDATE COLUMN STRUCTURE ----

# Expected columns per D-01 (episode-level bars table)
# Phase 60: added encounter_ids and drug_names
expected_episode_cols <- c(
  "patient_id", "treatment_type", "episode_number",
  "episode_start", "episode_stop", "episode_length_days",
  "distinct_dates_in_episode", "historical_flag", "triggering_codes",
  "encounter_ids", "drug_names"
)

# Expected columns per D-01 (detail-level ticks table)
# Phase 60: added ENCOUNTERID and drug_name
expected_detail_cols <- c(
  "patient_id", "treatment_type", "treatment_date", "triggering_code",
  "ENCOUNTERID", "drug_name",
  "episode_number", "episode_start", "episode_stop", "historical_flag"
)

# Check for missing columns in episode data
missing_episode_cols <- setdiff(expected_episode_cols, colnames(episodes))
if (length(missing_episode_cols) > 0) {
  stop(glue("ERROR: Episodes RDS missing expected columns: {paste(missing_episode_cols, collapse = ', ')}"))
}

# Check for missing columns in detail data
missing_detail_cols <- setdiff(expected_detail_cols, colnames(detail))
if (length(missing_detail_cols) > 0) {
  stop(glue("ERROR: Detail RDS missing expected columns: {paste(missing_detail_cols, collapse = ', ')}"))
}

message("  Column validation passed")


# --- SECTION 3B: LOAD CODE DESCRIPTIONS (Phase 02) ----

# SAFE-01: Validate RDS exists before loading
assert_rds_exists(DESCRIPTIONS_RDS, script_name = "R/51")

code_descriptions <- readRDS(DESCRIPTIONS_RDS)
message(glue("  Loaded {format(length(code_descriptions), big.mark = ',')} code descriptions"))


# Helper: map a single code to its description (empty string if missing, per D-05)
lookup_description <- function(code) {
  if (is.na(code) || code == "") {
    return("")
  }
  if (code %in% names(code_descriptions)) {
    return(code_descriptions[[code]])
  }
  return("")
}

# Helper: map comma-separated codes to comma-separated descriptions (per D-04)
# Preserves input order — does NOT sort. Per RESEARCH.md Pitfall 1.
map_codes_to_descriptions <- function(codes_str) {
  if (is.na(codes_str) || codes_str == "") {
    return("")
  }
  codes <- str_split(codes_str, ",")[[1]]
  descriptions <- sapply(codes, lookup_description, USE.NAMES = FALSE)
  paste(descriptions, collapse = ",")
}


# --- SECTION 4: SELECT AND ORDER COLUMNS (per D-01) ---

# Episode-level bars table: 9 original columns + encounter_ids + drug_names + triggering_code_descriptions + cancer_category + is_hodgkin
episodes_export <- episodes %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, historical_flag, triggering_codes,
    encounter_ids, drug_names
  ) %>%
  mutate(
    triggering_code_descriptions = sapply(triggering_codes, map_codes_to_descriptions, USE.NAMES = FALSE)
  ) %>%
  left_join(cancer_categories_per_patient, by = c("patient_id" = "ID")) %>%
  mutate(
    cancer_category = ifelse(is.na(cancer_category), "", cancer_category),
    is_hodgkin = ifelse(is.na(is_hodgkin), FALSE, is_hodgkin)
  )

# Detail-level ticks table: 8 original columns + ENCOUNTERID + drug_name + triggering_code_description + cancer_category + is_hodgkin
detail_export <- detail %>%
  select(
    patient_id, treatment_type, treatment_date, triggering_code,
    ENCOUNTERID, drug_name,
    episode_number, episode_start, episode_stop, historical_flag
  ) %>%
  mutate(
    triggering_code_description = sapply(triggering_code, lookup_description, USE.NAMES = FALSE)
  ) %>%
  left_join(cancer_categories_per_patient, by = c("patient_id" = "ID")) %>%
  mutate(
    cancer_category = ifelse(is.na(cancer_category), "", cancer_category),
    is_hodgkin = ifelse(is.na(is_hodgkin), FALSE, is_hodgkin)
  )


# --- SECTION 4B: BUILD AND APPEND DEATH PSEUDO-TREATMENT ROWS (per D-06, D-07) ---

if (nrow(death_data) > 0) {
  message("\n--- Building death pseudo-treatment rows ---")

  # Join cancer categories to death data (Claude's discretion: Death rows get patient's categories)
  death_with_categories <- death_data %>%
    left_join(cancer_categories_per_patient, by = "ID") %>%
    mutate(
      cancer_category = ifelse(is.na(cancer_category), "", cancer_category),
      is_hodgkin = ifelse(is.na(is_hodgkin), FALSE, is_hodgkin)
    )

  # Build death rows for episodes table (per D-06)
  death_episodes <- death_with_categories %>%
    mutate(
      patient_id = ID,
      treatment_type = "Death",
      episode_number = 1L,
      episode_start = DEATH_DATE,
      episode_stop = DEATH_DATE,
      episode_length_days = 0L,
      distinct_dates_in_episode = 1L,
      historical_flag = FALSE,
      triggering_codes = "",
      encounter_ids = "",
      drug_names = "",
      triggering_code_descriptions = ""
    ) %>%
    select(
      patient_id, treatment_type, episode_number,
      episode_start, episode_stop, episode_length_days,
      distinct_dates_in_episode, historical_flag,
      triggering_codes, encounter_ids, drug_names,
      triggering_code_descriptions,
      cancer_category, is_hodgkin
    )

  # Build death rows for detail table (per D-06, D-07)
  death_detail <- death_with_categories %>%
    mutate(
      patient_id = ID,
      treatment_type = "Death",
      treatment_date = DEATH_DATE,
      triggering_code = "",
      ENCOUNTERID = NA_character_,
      drug_name = NA_character_,
      episode_number = 1L,
      episode_start = DEATH_DATE,
      episode_stop = DEATH_DATE,
      historical_flag = FALSE,
      triggering_code_description = ""
    ) %>%
    select(
      patient_id, treatment_type, treatment_date,
      triggering_code, ENCOUNTERID, drug_name,
      episode_number, episode_start,
      episode_stop, historical_flag,
      triggering_code_description,
      cancer_category, is_hodgkin
    )

  # Verify column alignment before binding (per RESEARCH.md Pitfall 4)
  expected_ep_cols <- colnames(episodes_export)
  death_ep_cols <- colnames(death_episodes)
  missing_in_death_ep <- setdiff(expected_ep_cols, death_ep_cols)
  extra_in_death_ep <- setdiff(death_ep_cols, expected_ep_cols)

  if (length(missing_in_death_ep) > 0) {
    stop(glue("Death episodes missing columns: {paste(missing_in_death_ep, collapse = ', ')}"))
  }
  if (length(extra_in_death_ep) > 0) {
    warning(glue("Death episodes has extra columns: {paste(extra_in_death_ep, collapse = ', ')}"))
  }

  expected_det_cols <- colnames(detail_export)
  death_det_cols <- colnames(death_detail)
  missing_in_death_det <- setdiff(expected_det_cols, death_det_cols)
  extra_in_death_det <- setdiff(death_det_cols, expected_det_cols)

  if (length(missing_in_death_det) > 0) {
    stop(glue("Death detail missing columns: {paste(missing_in_death_det, collapse = ', ')}"))
  }
  if (length(extra_in_death_det) > 0) {
    warning(glue("Death detail has extra columns: {paste(extra_in_death_det, collapse = ', ')}"))
  }

  # Append death rows (per D-07: both CSVs)
  episodes_export <- bind_rows(episodes_export, death_episodes) %>%
    arrange(patient_id, episode_start, treatment_type)

  detail_export <- bind_rows(detail_export, death_detail) %>%
    arrange(patient_id, treatment_date, treatment_type)

  message(glue("  Added {nrow(death_episodes)} death episode rows"))
  message(glue("  Added {nrow(death_detail)} death detail rows"))
} else {
  message("\n--- No valid death dates found; skipping death rows ---")
}


# --- SECTION 4C: BUILD AND APPEND HL DIAGNOSIS TREATMENT ROWS (Phase 59: D-07, D-08, D-09) ---

if (nrow(hl_cohort) > 0) {
  message("\n--- Building HL Diagnosis treatment rows ---")

  # HL Diagnosis rows for episodes table (per D-07, D-09: treatment category, date = min(DIAGNOSIS, TUMOR_REGISTRY))
  hl_dx_episodes <- hl_cohort %>%
    left_join(cancer_categories_per_patient, by = "ID") %>%
    mutate(
      cancer_category = ifelse(is.na(cancer_category), "Hodgkin Lymphoma", cancer_category),
      is_hodgkin = TRUE
    ) %>%
    mutate(
      patient_id = ID,
      treatment_type = "HL Diagnosis",
      episode_number = 1L,
      episode_start = first_hl_dx_date,
      episode_stop = first_hl_dx_date,
      episode_length_days = 0L,
      distinct_dates_in_episode = 1L,
      historical_flag = FALSE,
      triggering_codes = "",
      encounter_ids = "",
      drug_names = "",
      triggering_code_descriptions = ""
    ) %>%
    select(
      patient_id, treatment_type, episode_number,
      episode_start, episode_stop, episode_length_days,
      distinct_dates_in_episode, historical_flag,
      triggering_codes, encounter_ids, drug_names,
      triggering_code_descriptions,
      cancer_category, is_hodgkin
    )

  # HL Diagnosis rows for detail table (per D-07, D-09: treatment category)
  hl_dx_detail <- hl_cohort %>%
    left_join(cancer_categories_per_patient, by = "ID") %>%
    mutate(
      cancer_category = ifelse(is.na(cancer_category), "Hodgkin Lymphoma", cancer_category),
      is_hodgkin = TRUE
    ) %>%
    mutate(
      patient_id = ID,
      treatment_type = "HL Diagnosis",
      treatment_date = first_hl_dx_date,
      triggering_code = "",
      ENCOUNTERID = NA_character_,
      drug_name = NA_character_,
      episode_number = 1L,
      episode_start = first_hl_dx_date,
      episode_stop = first_hl_dx_date,
      historical_flag = FALSE,
      triggering_code_description = ""
    ) %>%
    select(
      patient_id, treatment_type, treatment_date,
      triggering_code, ENCOUNTERID, drug_name,
      episode_number, episode_start,
      episode_stop, historical_flag,
      triggering_code_description,
      cancer_category, is_hodgkin
    )

  # Verify column alignment before binding (same pattern as Death row validation)
  expected_ep_cols <- colnames(episodes_export)
  hl_dx_ep_cols <- colnames(hl_dx_episodes)
  missing_in_hl_dx_ep <- setdiff(expected_ep_cols, hl_dx_ep_cols)
  extra_in_hl_dx_ep <- setdiff(hl_dx_ep_cols, expected_ep_cols)

  if (length(missing_in_hl_dx_ep) > 0) {
    stop(glue("HL Diagnosis episodes missing columns: {paste(missing_in_hl_dx_ep, collapse = ', ')}"))
  }
  if (length(extra_in_hl_dx_ep) > 0) {
    warning(glue("HL Diagnosis episodes has extra columns: {paste(extra_in_hl_dx_ep, collapse = ', ')}"))
  }

  expected_det_cols <- colnames(detail_export)
  hl_dx_det_cols <- colnames(hl_dx_detail)
  missing_in_hl_dx_det <- setdiff(expected_det_cols, hl_dx_det_cols)
  extra_in_hl_dx_det <- setdiff(hl_dx_det_cols, expected_det_cols)

  if (length(missing_in_hl_dx_det) > 0) {
    stop(glue("HL Diagnosis detail missing columns: {paste(missing_in_hl_dx_det, collapse = ', ')}"))
  }
  if (length(extra_in_hl_dx_det) > 0) {
    warning(glue("HL Diagnosis detail has extra columns: {paste(extra_in_hl_dx_det, collapse = ', ')}"))
  }

  # Append HL Diagnosis treatment rows (per D-09: chronological order with other treatments)
  episodes_export <- bind_rows(episodes_export, hl_dx_episodes) %>%
    arrange(patient_id, episode_start, treatment_type)

  detail_export <- bind_rows(detail_export, hl_dx_detail) %>%
    arrange(patient_id, treatment_date, treatment_type)

  message(glue("  Added {nrow(hl_dx_episodes)} HL Diagnosis episode rows"))
  message(glue("  Added {nrow(hl_dx_detail)} HL Diagnosis detail rows"))
} else {
  message("\n--- No valid HL diagnosis dates found; skipping HL Diagnosis treatment rows ---")
}


# --- SECTION 5: WRITE CSV OUTPUTS ----

message("\n--- Writing CSV outputs ---")

write.csv(episodes_export, OUTPUT_EPISODES, row.names = FALSE)
message(glue("  Wrote {OUTPUT_EPISODES} ({format(nrow(episodes_export), big.mark = ',')} rows)"))

write.csv(detail_export, OUTPUT_DETAIL, row.names = FALSE)
message(glue("  Wrote {OUTPUT_DETAIL} ({format(nrow(detail_export), big.mark = ',')} rows)"))


# --- SECTION 6: FINAL SUMMARY ----

message("\n=== Phase 01 Complete ===")
message(glue("  Unique patients in episodes: {format(n_distinct(episodes_export$patient_id), big.mark = ',')}"))
message(glue("  Total episodes: {format(nrow(episodes_export), big.mark = ',')}"))
message(glue("  Total detail rows: {format(nrow(detail_export), big.mark = ',')}"))

# Phase 02 description coverage stats
detail_has_desc <- sum(detail_export$triggering_code_description != "", na.rm = TRUE)
detail_total <- sum(!is.na(detail_export$triggering_code) & detail_export$triggering_code != "", na.rm = TRUE)
message(glue("  Detail rows with descriptions: {format(detail_has_desc, big.mark = ',')} / {format(detail_total, big.mark = ',')} codes"))

# Phase 57 cancer category and death stats
message(glue("  Episodes with cancer_category: {sum(episodes_export$cancer_category != '', na.rm = TRUE)}"))
message(glue("  Episodes with is_hodgkin=TRUE: {sum(episodes_export$is_hodgkin, na.rm = TRUE)}"))
n_death_rows <- sum(episodes_export$treatment_type == "Death", na.rm = TRUE)
message(glue("  Death pseudo-treatment rows in episodes: {format(n_death_rows, big.mark = ',')}"))
n_hl_dx_rows <- sum(episodes_export$treatment_type == "HL Diagnosis", na.rm = TRUE)
message(glue("  HL Diagnosis treatment rows in episodes: {format(n_hl_dx_rows, big.mark = ',')}"))

# Phase 60 drug name and encounter ID coverage stats
detail_has_drug <- sum(!is.na(detail_export$drug_name) & detail_export$drug_name != "", na.rm = TRUE)
message(glue("  Detail rows with drug names: {format(detail_has_drug, big.mark = ',')}"))

episodes_has_drugs <- sum(episodes_export$drug_names != "", na.rm = TRUE)
message(glue("  Episodes with drug_names: {format(episodes_has_drugs, big.mark = ',')}"))

episodes_has_encounters <- sum(episodes_export$encounter_ids != "", na.rm = TRUE)
message(glue("  Episodes with encounter_ids: {format(episodes_has_encounters, big.mark = ',')}"))

message(glue("\n  Episode bars:  {OUTPUT_EPISODES}"))
message(glue("  Detail ticks:  {OUTPUT_DETAIL}"))
