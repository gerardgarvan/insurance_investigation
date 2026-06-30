# ==============================================================================
# Phase 52: Enhanced Gantt Export - v2 CSV with Encounter-Level Enrichments
# Updated by Phase 64: Data Quality Cleanup for Tableau Import
# Updated by Phase 92: 5 Phase 91 metadata columns appended at end (non-breaking)
# Updated by Phase 99: v1 deprecated, schema consolidated (D-01 through D-15)
# ==============================================================================
#
# Purpose:
#   Produce Gantt CSV files (gantt_episodes.csv, gantt_detail.csv)
#   integrating all v1.8 enhancements (encounter-level cancer categories, HL flags,
#   specific drug names, regimen labels, first-line flags).
#
# Inputs:
#   - cache/outputs/treatment_episodes.rds (enriched by Phases 60-62, 91)
#   - cache/outputs/treatment_episode_detail.rds (enriched by Phase 60)
#   - cache/outputs/code_descriptions.rds (Phase 48b: code -> description lookup)
#   - cache/outputs/validated_death_dates.rds (Phase 59: pre-validated death dates)
#   - output/confirmed_hl_cohort.rds (Phase 55: HL diagnosis dates)
#
# Outputs:
#   - output/gantt_episodes.csv (20 columns, dead columns dropped)
#   - output/gantt_detail.csv (14 columns, dead columns dropped)
#
# Dependencies:
#   - 00_config (CONFIG paths, TREATMENT_TYPE_COLORS)
#   - utils_duckdb (DuckDB connection helpers)
#   - utils_dates (date parsing utilities)
#   - utils_cancer (classify_codes for 7-day confirmed mapping)
#
# Requirements:
#   DOC-01, DOC-02, DOC-03, GANTT-06, GANTT-07
#
#   Phase 64 additions: Data quality cleanup for direct Tableau import —
#   semicolon-separated multi-value fields, simplified drug names, no literal NAs,
#   filled pseudo-treatment descriptions, "Unlinked" cancer category label,
#   and trimmed column set.
#
# v2 SCHEMA DOCUMENTATION (Post-Phase 99 Consolidation):
#
#   gantt_episodes.csv (20 columns):
#     1. patient_id (chr) - Patient identifier
#     2. treatment_type (chr) - Treatment category (Chemotherapy, Radiation, SCT, etc.)
#     3. episode_number (int) - Sequential episode number per patient-type
#     4. episode_start (date) - First treatment date in episode
#     5. episode_stop (date) - Last treatment date in episode
#     6. episode_length_days (int) - Days from start to stop (0 for single-point)
#     7. distinct_dates_in_episode (int) - Number of unique treatment dates
#     8. triggering_codes (chr) - Semicolon-separated codes (Phase 64 cleanup)
#     9. drug_names (chr) - Semicolon-separated canonical drug names from reference Excel
#    10. triggering_code_descriptions (chr) - Semicolon-separated descriptions (Phase 64 cleanup)
#    11. cancer_category (chr) - Encounter-level cancer category or "Unlinked" (Phase 64)
#    12. is_hodgkin (lgl) - TRUE if cancer_category contains "Hodgkin" but not "Non-Hodgkin" (Phase 99)
#    13. drug_group (chr) - Semicolon-separated drug category labels (Phase 78)
#    14. code_type (chr) - Semicolon-separated code types: RXNORM, CPT/HCPCS, ICD-10-CM (Phase 92)
#    15. source_table (chr) - Semicolon-separated source tables: PRESCRIBING, PROCEDURES, DIAGNOSIS (Phase 92)
#    16. sct_cross_use_flag (chr) - SCT cross-use flag or empty (Phase 92)
#    17. episode_dx_codes (chr) - Semicolon-separated cancer DX codes within +/-30 days of episode (Phase 112)
#    18. episode_dx_categories (chr) - Semicolon-separated cancer category names within +/-30 days of episode (Phase 112)
#    19. episode_dx_7day_confirmed (chr) - Semicolon-separated 7-day confirmed cancer categories (subset of episode_dx_categories) (Phase 115)
#    20. age_at_episode (int) - Patient age in integer years (floor) at episode_start (Phase 115)
#
#   Phase 99 removed: encounter_ids, is_sct_conditioning_context, immuno_confidence (not visualization-relevant)
#
#   gantt_detail.csv (14 columns):
#     1. patient_id (chr) - Patient identifier
#     2. treatment_type (chr) - Treatment category
#     3. treatment_date (date) - Single treatment date
#     4. triggering_code (chr) - Single triggering code (Phase 64 cleanup)
#     5. drug_name (chr) - Single canonical drug name from reference Excel
#     6. episode_number (int) - Parent episode number
#     7. episode_start (date) - Parent episode start
#     8. episode_stop (date) - Parent episode stop
#     9. triggering_code_description (chr) - Single code description (Phase 64 cleanup)
#    10. cancer_category (chr) - Encounter-level cancer category or "Unlinked" (Phase 64)
#    11. is_hodgkin (lgl) - TRUE if cancer_category contains "Hodgkin" but not "Non-Hodgkin" (Phase 99)
#    12. code_type (chr) - Semicolon-separated code types: RXNORM, CPT/HCPCS, ICD-10-CM (Phase 92)
#    13. source_table (chr) - Semicolon-separated source tables: PRESCRIBING, PROCEDURES, DIAGNOSIS (Phase 92)
#    14. sct_cross_use_flag (chr) - SCT cross-use flag or empty (Phase 92)
#
#   Phase 99 removed: ENCOUNTERID, is_sct_conditioning_context, immuno_confidence
#
# DECISION TRACEABILITY:
#   D-01: v2 is the canonical export — v1 (R/51) deprecated and deleted
#   D-02: Keep semicolons for multi-value field separators (Phase 64 standard)
#   D-03: Keep v2 cleanup behavior: empty strings instead of NA, "Unlinked" for blank cancer_category
#   D-04: Drug names use canonical reference Excel names (MEDICATION_LOOKUP primary, RxNorm fallback)
#   D-05: Rename output files from gantt_*_v2.csv to gantt_*.csv
#   D-06: Drop encounter_ids (episodes) and ENCOUNTERID (detail) columns
#   D-07: Add is_hodgkin back as convenience boolean derived from cancer_category
#   D-08: (removed) regimen_label and is_first_line dropped — too sparse to be useful
#   D-09: Keep drug_group column; cause_of_death dropped (100% empty)
#   D-10: Keep source metadata columns: code_type, source_table, sct_cross_use_flag
#         medication_name removed (consolidated into drug_names), treatment_line dropped (100% empty)
#   D-11: Remove immunotherapy context columns from Gantt export: is_sct_conditioning_context, immuno_confidence
#   D-12: Clean up pseudo-treatment row metadata (empty strings for character enrichment columns)
#   D-13: Replace hardcoded column count verification with dynamic schema vectors
#   D-78-09: cause_of_death appended (non-breaking)
#   D-78-10: Missing/unmapped ICD-10 -> "Unknown or Unspecified"
#   D-78-11: >40% missingness triggers console warning
#   D-78-12: Both gantt_episodes.csv and gantt_detail.csv get cause_of_death
#   D-78-14: drug_group propagated from treatment_episodes.rds to episodes CSV
#   D-92-01: 5 Phase 91 metadata columns appended at end (non-breaking)
#
# INPUTS:
#   - cache/outputs/treatment_episodes.rds (enriched by Phases 60-62, 91)
#   - cache/outputs/treatment_episode_detail.rds (enriched by Phase 60)
#   - cache/outputs/code_descriptions.rds (Phase 48b: code -> description lookup)
#   - cache/outputs/validated_death_dates.rds (Phase 59: pre-validated death dates)
#   - output/confirmed_hl_cohort.rds (Phase 55: HL diagnosis dates)
#
# OUTPUTS:
#   - output/gantt_episodes.csv (20 columns, dead columns dropped)
#   - output/gantt_detail.csv (14 columns, dead columns dropped)
#
# ==============================================================================


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
source("R/utils/utils_cancer.R")  # Phase 115: classify_codes() for 7-day confirmed mapping

# Input paths: existing RDS artifacts
EPISODES_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
DETAIL_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds")
DESCRIPTIONS_RDS <- file.path(CONFIG$cache$outputs_dir, "code_descriptions.rds")
VALIDATED_DEATHS_RDS <- file.path(CONFIG$cache$outputs_dir, "validated_death_dates.rds")
COHORT_RDS <- file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds")
CANCER_SUMMARY_CSV <- build_output_path("tables", "cancer_summary.csv")  # Phase 115: 7-day confirmed data

# Output paths: CSV files for third-party Gantt chart consumption (Phase 99: no _v2 suffix)
OUTPUT_EPISODES <- file.path(CONFIG$output_dir, "gantt_episodes.csv")
OUTPUT_DETAIL <- file.path(CONFIG$output_dir, "gantt_detail.csv")

# --- SCHEMA DEFINITIONS (Phase 99, D-13: dynamic verification) ---
EPISODES_SCHEMA <- c(
  "patient_id", "treatment_type", "episode_number",
  "episode_start", "episode_stop", "episode_length_days",
  "distinct_dates_in_episode",
  "triggering_codes", "drug_names", "triggering_code_descriptions",
  "cancer_category", "is_hodgkin",
  "drug_group",
  "code_type", "source_table", "sct_cross_use_flag",
  "episode_dx_codes", "episode_dx_categories",
  # Phase 115: 7-day confirmed subset + age (+2 columns, now 20 total)
  "episode_dx_7day_confirmed", "age_at_episode"
)

DETAIL_SCHEMA <- c(
  "patient_id", "treatment_type", "treatment_date",
  "triggering_code", "drug_name", "episode_number",
  "episode_start", "episode_stop",
  "triggering_code_description",
  "cancer_category", "is_hodgkin",
  "code_type", "source_table", "sct_cross_use_flag"
)

# SECTION 0: INPUT VALIDATION ----
# SAFE-01: Validate all input artifacts exist (fail-fast before any loading)
assert_rds_exists(EPISODES_RDS, script_name = "R/52")
assert_rds_exists(DETAIL_RDS, script_name = "R/52")


# --- SECTION 2: LOAD INPUT DATA ----

message("=== Phase 99: Consolidated Gantt Export ===\n")

# Load episode-level data (bars: one row per patient/type/episode)
episodes <- readRDS(EPISODES_RDS)
message(glue("  Loaded {format(nrow(episodes), big.mark = ',')} episode rows"))

# SAFE-02: Validate structure after loading
assert_df_valid(episodes, "treatment_episodes",
  required_cols = c("patient_id", "treatment_type", "episode_start", "episode_stop"),
  script_name = "R/52")

# Load detail-level data (ticks: one row per patient/date/code)
detail <- readRDS(DETAIL_RDS)
message(glue("  Loaded {format(nrow(detail), big.mark = ',')} detail rows"))

# SAFE-02: Validate structure after loading
assert_df_valid(detail, "treatment_episode_detail",
  required_cols = c("patient_id", "treatment_type", "treatment_date", "triggering_code"),
  script_name = "R/52")

# Guard clauses for missing Phase 61/62 columns (per R/62 pattern, lines 79-85)
if (!"cancer_category" %in% names(episodes)) {
  warning("cancer_category column not found in treatment_episodes.rds — Phase 61 not yet run. Using default empty string.")
  episodes <- episodes %>% mutate(cancer_category = "")
}
if (!"cancer_link_method" %in% names(episodes)) {
  warning("cancer_link_method column not found in treatment_episodes.rds — Phase 61 not yet run. Using default 'none'.")
  episodes <- episodes %>% mutate(cancer_link_method = "none")
}
if (!"is_hodgkin" %in% names(episodes)) {
  warning("is_hodgkin column not found in treatment_episodes.rds — Phase 61 not yet run. Using default FALSE.")
  episodes <- episodes %>% mutate(is_hodgkin = FALSE)
}
if (!"drug_group" %in% names(episodes)) {
  warning("drug_group column not found in treatment_episodes.rds — Phase 78 R/28 not yet run. Using default NA.")
  episodes <- episodes %>% mutate(drug_group = NA_character_)
}
if (!"triggering_code_description" %in% names(episodes)) {
  warning("triggering_code_description column not found in treatment_episodes.rds — Phase 78 R/28 not yet run. Using default NA.")
  episodes <- episodes %>% mutate(triggering_code_description = NA_character_)
}
if (!"code_type" %in% names(episodes)) {
  warning("code_type column not found in treatment_episodes.rds — Phase 91 not yet run. Using default NA.")
  episodes <- episodes %>% mutate(code_type = NA_character_)
}
if (!"source_table" %in% names(episodes)) {
  warning("source_table column not found in treatment_episodes.rds — Phase 91 not yet run. Using default NA.")
  episodes <- episodes %>% mutate(source_table = NA_character_)
}
if (!"sct_cross_use_flag" %in% names(episodes)) {
  warning("sct_cross_use_flag column not found in treatment_episodes.rds — Phase 91 not yet run. Using default NA.")
  episodes <- episodes %>% mutate(sct_cross_use_flag = NA_character_)
}
if (!"episode_dx_codes" %in% names(episodes)) {
  warning("episode_dx_codes column not found in treatment_episodes.rds — Phase 112 not yet run. Using default NA.")
  episodes <- episodes %>% mutate(episode_dx_codes = NA_character_)
}
if (!"episode_dx_categories" %in% names(episodes)) {
  warning("episode_dx_categories column not found in treatment_episodes.rds — Phase 112 not yet run. Using default NA.")
  episodes <- episodes %>% mutate(episode_dx_categories = NA_character_)
}


# --- SECTION 2B: 7-DAY CONFIRMED CATEGORIES LOOKUP (Phase 115, D-01 through D-05) ---

message("\n--- Building patient-level 7-day confirmed categories lookup ---")

patient_7day_categories <- NULL
if (file.exists(CANCER_SUMMARY_CSV)) {
  cancer_summary_raw <- read.csv(CANCER_SUMMARY_CSV, stringsAsFactors = FALSE)
  message(glue("  Loaded cancer_summary.csv: {nrow(cancer_summary_raw)} patient-code rows"))

  # Filter to 7-day confirmed rows only (per D-04)
  confirmed_rows <- cancer_summary_raw %>%
    filter(two_or_more_unique_dates_gt_7 == 1)

  message(glue("  7-day confirmed rows: {nrow(confirmed_rows)}"))

  # Map cancer_code to category name using classify_codes() (per D-03, D-04)
  confirmed_rows <- confirmed_rows %>%
    mutate(category = classify_codes(cancer_code))

  # Aggregate to patient level: set of confirmed category names per patient
  patient_7day_categories <- confirmed_rows %>%
    filter(!is.na(category)) %>%
    group_by(ID) %>%
    summarise(
      confirmed_categories = list(sort(unique(category))),
      .groups = "drop"
    )

  message(glue("  Patients with 7-day confirmed categories: {nrow(patient_7day_categories)}"))
} else {
  message("  WARNING: cancer_summary.csv not found. episode_dx_7day_confirmed will be empty.")
}


# --- SECTION 2C: DEMOGRAPHIC BIRTH DATE LOOKUP (Phase 115, D-06, D-07) ---

message("\n--- Loading DEMOGRAPHIC birth dates for age_at_episode ---")

birth_dates <- NULL
tryCatch({
  open_pcornet_con()
  birth_dates <- get_pcornet_table("DEMOGRAPHIC") %>%
    select(ID, BIRTH_DATE) %>%
    collect() %>%
    mutate(BIRTH_DATE = parse_pcornet_date(BIRTH_DATE)) %>%
    filter(!is.na(BIRTH_DATE))
  close_pcornet_con()
  # Flag patients with placeholder 1900 birth year (PCORnet masked/unknown DOB)
  n_masked <- sum(year(birth_dates$BIRTH_DATE) == 1900)
  if (n_masked > 0) {
    message(glue("  {n_masked} patients have 1900 placeholder birth date — age will be set to 90"))
    masked_ids <- birth_dates$ID[year(birth_dates$BIRTH_DATE) == 1900]
  } else {
    masked_ids <- character(0)
  }
  message(glue("  Loaded {nrow(birth_dates)} patients with valid birth dates"))
}, error = function(e) {
  message(glue("  WARNING: Could not load DEMOGRAPHIC birth dates: {conditionMessage(e)}"))
  try(close_pcornet_con(), silent = TRUE)
})


# --- SECTION 3: CODE DESCRIPTION LOOKUP ----

# Load code descriptions (Phase 48b) — non-fatal if missing
code_descriptions <- NULL
if (file.exists(DESCRIPTIONS_RDS)) {
  # SAFE-01: Validate RDS exists before loading
  assert_rds_exists(DESCRIPTIONS_RDS, script_name = "R/52")
  code_descriptions <- readRDS(DESCRIPTIONS_RDS)
  message(glue("  Loaded {format(length(code_descriptions), big.mark = ',')} code descriptions"))
} else {
  message("  WARNING: code_descriptions.rds not found. Description columns will be empty.")
}

# Helper: map a single code to its description (empty string if missing)
# code_descriptions is a named character vector (from R/48b), not a dataframe
lookup_description <- function(code) {
  if (is.null(code_descriptions) || is.na(code) || code == "") {
    return("")
  }
  if (code %in% names(code_descriptions)) {
    return(code_descriptions[[code]])
  }
  return("")
}

# Helper: map comma-separated codes to comma-separated descriptions
map_codes_to_descriptions <- function(codes_str) {
  if (is.na(codes_str) || codes_str == "") {
    return("")
  }
  codes <- str_split(codes_str, ",")[[1]]
  descriptions <- sapply(codes, lookup_description, USE.NAMES = FALSE)
  paste(descriptions, collapse = ",")
}


# --- SECTION 4: SELECT AND ORDER COLUMNS ----

message("\n--- Building export tables ---")

# Episodes: build intermediate (trimmed to 20 columns by Step 6)
episodes_export <- episodes %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, triggering_codes,
    encounter_ids, drug_names, drug_group
  ) %>%
  mutate(
    triggering_code_descriptions = sapply(triggering_codes, map_codes_to_descriptions, USE.NAMES = FALSE)
  ) %>%
  # Re-join the base columns that were selected, plus add enriched columns from episodes
  left_join(
    episodes %>% select(
      patient_id, episode_number, treatment_type,
      cancer_category, is_hodgkin, cancer_link_method,
      # --- Phase 92: metadata columns (GANTT-06) ---
      code_type, source_table, sct_cross_use_flag,
      # --- Phase 112: Temporal diagnosis columns (GANTT-DX-02) ---
      episode_dx_codes, episode_dx_categories
    ),
    by = c("patient_id", "episode_number", "treatment_type")
  ) %>%
  mutate(
    cancer_category = ifelse(is.na(cancer_category), "", cancer_category),
    is_hodgkin = ifelse(is.na(is_hodgkin), FALSE, is_hodgkin)
  ) %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, triggering_codes,
    encounter_ids, drug_names, triggering_code_descriptions,
    cancer_category, is_hodgkin, cancer_link_method,
    drug_group,
    # --- Phase 92: metadata columns (GANTT-06) ---
    code_type, source_table, sct_cross_use_flag,
    # --- Phase 112: Temporal diagnosis columns (GANTT-DX-02) ---
    episode_dx_codes, episode_dx_categories
  )

message(glue("  Built episodes_export: {format(nrow(episodes_export), big.mark = ',')} rows, {ncol(episodes_export)} columns"))

# Detail: 14 columns
# Detail table joins cancer_category, is_hodgkin, metadata from episodes
episodes_v2_cols <- episodes %>%
  select(
    patient_id, treatment_type, episode_number, cancer_category, is_hodgkin,
    cancer_link_method,
    # --- Phase 92: metadata columns (GANTT-06) ---
    code_type, source_table, sct_cross_use_flag
  )

detail_export <- detail %>%
  select(
    patient_id, treatment_type, treatment_date, triggering_code,
    ENCOUNTERID, drug_name,
    episode_number, episode_start, episode_stop
  ) %>%
  mutate(
    triggering_code_description = sapply(triggering_code, lookup_description, USE.NAMES = FALSE)
  ) %>%
  left_join(episodes_v2_cols, by = c("patient_id", "treatment_type", "episode_number")) %>%
  mutate(
    cancer_category = ifelse(is.na(cancer_category), "", cancer_category),
    is_hodgkin = ifelse(is.na(is_hodgkin), FALSE, is_hodgkin)
  ) %>%
  select(
    patient_id, treatment_type, treatment_date, triggering_code,
    ENCOUNTERID, drug_name,
    episode_number, episode_start, episode_stop,
    triggering_code_description,
    cancer_category, is_hodgkin, cancer_link_method,
    # --- Phase 92: metadata columns (GANTT-06) ---
    code_type, source_table, sct_cross_use_flag
  )

message(glue("  Built detail_export: {format(nrow(detail_export), big.mark = ',')} rows, {ncol(detail_export)} columns"))


# --- Phase 115: Compute episode_dx_7day_confirmed (D-01 through D-05, D-09) ---
if (!is.null(patient_7day_categories)) {
  # Helper: intersect episode categories with patient's confirmed categories
  # NOTE: At this point episode_dx_categories is comma-separated (pre-clean_multi_value)
  get_confirmed_subset <- function(patient_id_val, dx_categories_str) {
    if (is.na(dx_categories_str) || dx_categories_str == "") return("")

    # Parse episode categories (comma-separated before clean_multi_value)
    ep_cats <- str_split(dx_categories_str, ",")[[1]]
    ep_cats <- str_trim(ep_cats)
    ep_cats <- ep_cats[ep_cats != ""]

    if (length(ep_cats) == 0) return("")

    # Look up patient's confirmed categories
    patient_row <- patient_7day_categories %>% filter(ID == patient_id_val)
    if (nrow(patient_row) == 0) return("")

    confirmed <- patient_row$confirmed_categories[[1]]
    matched <- intersect(ep_cats, confirmed)

    if (length(matched) == 0) return("")
    paste(sort(matched), collapse = ",")
  }

  episodes_export <- episodes_export %>%
    mutate(
      episode_dx_7day_confirmed = mapply(
        get_confirmed_subset,
        patient_id, episode_dx_categories,
        USE.NAMES = FALSE
      )
    )
  n_with_confirmed <- sum(episodes_export$episode_dx_7day_confirmed != "", na.rm = TRUE)
  message(glue("  Phase 115: {n_with_confirmed} episodes with 7-day confirmed dx categories"))
} else {
  episodes_export <- episodes_export %>%
    mutate(episode_dx_7day_confirmed = "")
  message("  Phase 115: episode_dx_7day_confirmed defaulted to empty (no cancer_summary.csv)")
}

# --- Phase 115: Compute age_at_episode (D-06, D-07) ---
if (!is.null(birth_dates)) {
  episodes_export <- episodes_export %>%
    left_join(birth_dates, by = c("patient_id" = "ID")) %>%
    mutate(
      age_at_episode = as.integer(floor(
        as.numeric(difftime(episode_start, BIRTH_DATE, units = "days")) / 365.25
      ))
    ) %>%
    select(-BIRTH_DATE)

  # Override age to 90 for patients with masked (1900) birth dates
  episodes_export <- episodes_export %>%
    mutate(age_at_episode = ifelse(patient_id %in% masked_ids, 90L, age_at_episode))

  n_with_age <- sum(!is.na(episodes_export$age_at_episode))
  message(glue("  Phase 115: {n_with_age}/{nrow(episodes_export)} episodes with age_at_episode"))
} else {
  episodes_export <- episodes_export %>%
    mutate(age_at_episode = NA_integer_)
  message("  Phase 115: age_at_episode defaulted to NA (no DEMOGRAPHIC data)")
}


# --- SECTION 4B: DEATH PSEUDO-TREATMENT ROWS (per D-09, D-12) ---

if (file.exists(VALIDATED_DEATHS_RDS)) {
  message("\n--- Building Death pseudo-treatment rows ---")

  # SAFE-01: Validate RDS exists before loading
  assert_rds_exists(VALIDATED_DEATHS_RDS, script_name = "R/52")
  validated_deaths <- readRDS(VALIDATED_DEATHS_RDS)

  death_data <- validated_deaths %>%
    filter(!is.na(DEATH_DATE)) %>%
    select(ID, DEATH_DATE)

  if (nrow(death_data) > 0) {
    # Build death_episodes (20 columns after dead-column removal)
    death_episodes <- death_data %>%
      mutate(
        patient_id = ID,
        treatment_type = "Death",
        episode_number = 1L,
        episode_start = DEATH_DATE,
        episode_stop = DEATH_DATE,
        episode_length_days = 0L,
        distinct_dates_in_episode = 1L,
        triggering_codes = "",
        encounter_ids = "",
        drug_names = "",
        triggering_code_descriptions = "",
        cancer_category = "",
        is_hodgkin = FALSE,
        cancer_link_method = "none",
        drug_group = "",
        code_type = "",
        source_table = "",
        sct_cross_use_flag = "",
        episode_dx_codes = NA_character_,
        episode_dx_categories = NA_character_,
        episode_dx_7day_confirmed = ""
      )

    # Compute age_at_episode for Death rows using birth_dates
    if (!is.null(birth_dates)) {
      death_episodes <- death_episodes %>%
        left_join(birth_dates, by = c("patient_id" = "ID")) %>%
        mutate(
          age_at_episode = as.integer(floor(
            as.numeric(difftime(episode_start, BIRTH_DATE, units = "days")) / 365.25
          ))
        ) %>%
        select(-BIRTH_DATE) %>%
        mutate(age_at_episode = ifelse(patient_id %in% masked_ids, 90L, age_at_episode))
    } else {
      death_episodes <- death_episodes %>%
        mutate(age_at_episode = NA_integer_)
    }

    death_episodes <- death_episodes %>%
      select(
        patient_id, treatment_type, episode_number,
        episode_start, episode_stop, episode_length_days,
        distinct_dates_in_episode, triggering_codes,
        encounter_ids, drug_names, triggering_code_descriptions,
        cancer_category, is_hodgkin, cancer_link_method,
        drug_group,
        code_type, source_table, sct_cross_use_flag,
        episode_dx_codes, episode_dx_categories,
        episode_dx_7day_confirmed, age_at_episode
      )

    # Verify column alignment before binding (R/49 pattern, lines 734-756)
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

    # Build death_detail (14 columns after dead-column removal)
    death_detail <- death_data %>%
      mutate(
        patient_id = ID,
        treatment_type = "Death",
        treatment_date = DEATH_DATE,
        triggering_code = "",
        ENCOUNTERID = NA_character_,
        drug_name = "",
        episode_number = 1L,
        episode_start = DEATH_DATE,
        episode_stop = DEATH_DATE,
        triggering_code_description = "",
        cancer_category = "",
        is_hodgkin = FALSE,
        cancer_link_method = "none",
        code_type = "",
        source_table = "",
        sct_cross_use_flag = ""
      ) %>%
      select(
        patient_id, treatment_type, treatment_date, triggering_code,
        ENCOUNTERID, drug_name,
        episode_number, episode_start, episode_stop,
        triggering_code_description,
        cancer_category, is_hodgkin, cancer_link_method,
        code_type, source_table, sct_cross_use_flag
      )

    # Verify column alignment for detail
    expected_detail_cols <- colnames(detail_export)
    death_detail_cols <- colnames(death_detail)
    missing_in_death_detail <- setdiff(expected_detail_cols, death_detail_cols)
    extra_in_death_detail <- setdiff(death_detail_cols, expected_detail_cols)

    if (length(missing_in_death_detail) > 0) {
      stop(glue("Death detail missing columns: {paste(missing_in_death_detail, collapse = ', ')}"))
    }
    if (length(extra_in_death_detail) > 0) {
      warning(glue("Death detail has extra columns: {paste(extra_in_death_detail, collapse = ', ')}"))
    }

    # Append Death rows
    episodes_export <- bind_rows(episodes_export, death_episodes) %>%
      arrange(patient_id, episode_start, treatment_type)

    detail_export <- bind_rows(detail_export, death_detail) %>%
      arrange(patient_id, treatment_date, treatment_type)

    message(glue("  Added {nrow(death_episodes)} Death episode rows"))
    message(glue("  Added {nrow(death_detail)} Death detail rows"))
  } else {
    message("  No validated death dates found — skipping Death rows")
  }
} else {
  message("  WARNING: validated_death_dates.rds not found — skipping Death rows")
}


# --- SECTION 4C: HL DIAGNOSIS PSEUDO-TREATMENT ROWS (per D-09, D-12) ---

if (file.exists(COHORT_RDS)) {
  message("\n--- Building HL Diagnosis pseudo-treatment rows ---")

  # SAFE-01: Validate RDS exists before loading
  assert_rds_exists(COHORT_RDS, script_name = "R/52")
  hl_cohort <- readRDS(COHORT_RDS)

  # Filter for valid first_hl_dx_date
  hl_dx_data <- hl_cohort %>%
    filter(!is.na(first_hl_dx_date)) %>%
    select(ID, first_hl_dx_date)

  if (nrow(hl_dx_data) > 0) {
    # Build hl_dx_episodes (20 columns after dead-column removal)
    hl_dx_episodes <- hl_dx_data %>%
      mutate(
        patient_id = ID,
        treatment_type = "HL Diagnosis",
        episode_number = 1L,
        episode_start = first_hl_dx_date,
        episode_stop = first_hl_dx_date,
        episode_length_days = 0L,
        distinct_dates_in_episode = 1L,
        triggering_codes = "",
        encounter_ids = "",
        drug_names = "",
        triggering_code_descriptions = "",
        cancer_category = "Hodgkin Lymphoma",
        is_hodgkin = TRUE,
        cancer_link_method = "none",
        drug_group = "",
        code_type = "",
        source_table = "",
        sct_cross_use_flag = "",
        episode_dx_codes = NA_character_,
        episode_dx_categories = NA_character_,
        episode_dx_7day_confirmed = ""
      )

    # Compute age_at_episode for HL Diagnosis rows using birth_dates
    if (!is.null(birth_dates)) {
      hl_dx_episodes <- hl_dx_episodes %>%
        left_join(birth_dates, by = c("patient_id" = "ID")) %>%
        mutate(
          age_at_episode = as.integer(floor(
            as.numeric(difftime(episode_start, BIRTH_DATE, units = "days")) / 365.25
          ))
        ) %>%
        select(-BIRTH_DATE) %>%
        mutate(age_at_episode = ifelse(patient_id %in% masked_ids, 90L, age_at_episode))
    } else {
      hl_dx_episodes <- hl_dx_episodes %>%
        mutate(age_at_episode = NA_integer_)
    }

    hl_dx_episodes <- hl_dx_episodes %>%
      select(
        patient_id, treatment_type, episode_number,
        episode_start, episode_stop, episode_length_days,
        distinct_dates_in_episode, triggering_codes,
        encounter_ids, drug_names, triggering_code_descriptions,
        cancer_category, is_hodgkin, cancer_link_method,
        drug_group,
        code_type, source_table, sct_cross_use_flag,
        episode_dx_codes, episode_dx_categories,
        episode_dx_7day_confirmed, age_at_episode
      )

    # Verify column alignment before binding
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

    # Build hl_dx_detail (14 columns after dead-column removal)
    hl_dx_detail <- hl_dx_data %>%
      mutate(
        patient_id = ID,
        treatment_type = "HL Diagnosis",
        treatment_date = first_hl_dx_date,
        triggering_code = "",
        ENCOUNTERID = NA_character_,
        drug_name = "",
        episode_number = 1L,
        episode_start = first_hl_dx_date,
        episode_stop = first_hl_dx_date,
        triggering_code_description = "",
        cancer_category = "Hodgkin Lymphoma",
        is_hodgkin = TRUE,
        cancer_link_method = "none",
        code_type = "",
        source_table = "",
        sct_cross_use_flag = ""
      ) %>%
      select(
        patient_id, treatment_type, treatment_date, triggering_code,
        ENCOUNTERID, drug_name,
        episode_number, episode_start, episode_stop,
        triggering_code_description,
        cancer_category, is_hodgkin, cancer_link_method,
        code_type, source_table, sct_cross_use_flag
      )

    # Verify column alignment for detail
    expected_detail_cols <- colnames(detail_export)
    hl_dx_detail_cols <- colnames(hl_dx_detail)
    missing_in_hl_dx_detail <- setdiff(expected_detail_cols, hl_dx_detail_cols)
    extra_in_hl_dx_detail <- setdiff(hl_dx_detail_cols, expected_detail_cols)

    if (length(missing_in_hl_dx_detail) > 0) {
      stop(glue("HL Diagnosis detail missing columns: {paste(missing_in_hl_dx_detail, collapse = ', ')}"))
    }
    if (length(extra_in_hl_dx_detail) > 0) {
      warning(glue("HL Diagnosis detail has extra columns: {paste(extra_in_hl_dx_detail, collapse = ', ')}"))
    }

    # Append HL Diagnosis rows
    episodes_export <- bind_rows(episodes_export, hl_dx_episodes) %>%
      arrange(patient_id, episode_start, treatment_type)

    detail_export <- bind_rows(detail_export, hl_dx_detail) %>%
      arrange(patient_id, treatment_date, treatment_type)

    message(glue("  Added {nrow(hl_dx_episodes)} HL Diagnosis episode rows"))
    message(glue("  Added {nrow(hl_dx_detail)} HL Diagnosis detail rows"))
  } else {
    message("  No HL diagnosis dates found — skipping HL Diagnosis rows")
  }
} else {
  message("  WARNING: confirmed_hl_cohort.rds not found — skipping HL Diagnosis rows")
}


# --- SECTION 4D: DATA QUALITY CLEANUP ----

message("\n--- Section 4D: Data Quality Cleanup (Phase 64) ---")

# Helper function: clean multi-value field (dedup, drop blanks, change separator)
clean_multi_value <- function(field_str, sep_in = ",", sep_out = ";") {
  if (is.na(field_str) || field_str == "" || field_str == "NA") {
    return("")
  }

  values <- str_split(field_str, sep_in)[[1]]
  values <- str_trim(values)
  values <- values[values != "" & !is.na(values)]
  values <- sort(unique(values))

  if (length(values) == 0) {
    return("")
  }
  paste(values, collapse = sep_out)
}

# Step 1: Clean multi-value fields (separator + dedup + drop blanks)
episodes_export <- episodes_export %>%
  mutate(
    triggering_codes = sapply(triggering_codes, clean_multi_value, USE.NAMES = FALSE),
    drug_names = sapply(drug_names, clean_multi_value, USE.NAMES = FALSE),
    triggering_code_descriptions = sapply(triggering_code_descriptions, clean_multi_value, USE.NAMES = FALSE),
    # Phase 92: 2 multi-value columns (code_type, source_table)
    # NOTE: sct_cross_use_flag is single-value — skip cleanup
    code_type = sapply(code_type, clean_multi_value, USE.NAMES = FALSE),
    source_table = sapply(source_table, clean_multi_value, USE.NAMES = FALSE),
    # Phase 112: 2 multi-value temporal diagnosis columns
    episode_dx_codes = sapply(episode_dx_codes, clean_multi_value, USE.NAMES = FALSE),
    episode_dx_categories = sapply(episode_dx_categories, clean_multi_value, USE.NAMES = FALSE),
    # Phase 115: 7-day confirmed multi-value field
    episode_dx_7day_confirmed = sapply(episode_dx_7day_confirmed, clean_multi_value, USE.NAMES = FALSE)
  )

detail_export <- detail_export %>%
  mutate(
    triggering_code = sapply(triggering_code, clean_multi_value, USE.NAMES = FALSE),
    triggering_code_description = sapply(triggering_code_description, clean_multi_value, USE.NAMES = FALSE),
    # Phase 92: 2 multi-value columns (same pattern)
    code_type = sapply(code_type, clean_multi_value, USE.NAMES = FALSE),
    source_table = sapply(source_table, clean_multi_value, USE.NAMES = FALSE)
  )

message("  Multi-value fields cleaned (separator: semicolon, deduped, blanks dropped)")

# Step 3: Fill pseudo-treatment descriptions
episodes_export <- episodes_export %>%
  mutate(
    triggering_code_descriptions = case_when(
      treatment_type %in% c("Death", "HL Diagnosis") &
        (triggering_code_descriptions == "" | is.na(triggering_code_descriptions)) ~ treatment_type,
      TRUE ~ triggering_code_descriptions
    )
  )

detail_export <- detail_export %>%
  mutate(
    triggering_code_description = case_when(
      treatment_type %in% c("Death", "HL Diagnosis") &
        (triggering_code_description == "" | is.na(triggering_code_description)) ~ treatment_type,
      TRUE ~ triggering_code_description
    )
  )

message("  Pseudo-treatment descriptions filled")

# Step 4: Convert NA to empty strings
episodes_export <- episodes_export %>%
  mutate(across(where(is.character), ~ ifelse(is.na(.) | . == "NA", "", .)))

detail_export <- detail_export %>%
  mutate(across(where(is.character), ~ ifelse(is.na(.) | . == "NA", "", .)))

message("  NA values converted to empty strings")

# Step 5: Fill blank cancer_category with "Unlinked"
episodes_export <- episodes_export %>%
  mutate(cancer_category = ifelse(cancer_category == "", "Unlinked", cancer_category))

detail_export <- detail_export %>%
  mutate(cancer_category = ifelse(cancer_category == "", "Unlinked", cancer_category))

message("  Blank cancer_category filled with 'Unlinked'")

# Phase 99: Derive is_hodgkin from cancer_category (D-07)
episodes_export <- episodes_export %>%
  mutate(is_hodgkin = str_detect(cancer_category, "Hodgkin") & !str_detect(cancer_category, "Non-Hodgkin"))

detail_export <- detail_export %>%
  mutate(is_hodgkin = str_detect(cancer_category, "Hodgkin") & !str_detect(cancer_category, "Non-Hodgkin"))

message("  is_hodgkin derived from cancer_category")

# Step 6: Column trimming (drop encounter_ids, cancer_link_method per D-06, D-11)
# Also drops: historical_flag, regimen_label, is_first_line, cause_of_death, treatment_line (dead columns)
episodes_export <- episodes_export %>%
  select(
    # Core identifiers
    patient_id, treatment_type, episode_number,
    # Episode boundaries
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode,
    # Code details (semicolon-separated per D-02)
    triggering_codes, drug_names, triggering_code_descriptions,
    # Cancer classification (D-07: is_hodgkin after cancer_category)
    cancer_category, is_hodgkin,
    # Drug info (D-09)
    drug_group,
    # Source metadata (D-10)
    code_type, source_table, sct_cross_use_flag,
    # Phase 112: Temporal diagnosis enrichment (GANTT-DX-02)
    episode_dx_codes, episode_dx_categories,
    # Phase 115: 7-day confirmed subset + age (+2 columns, now 20 total)
    episode_dx_7day_confirmed, age_at_episode
  )

detail_export <- detail_export %>%
  select(
    patient_id, treatment_type, treatment_date,
    triggering_code, drug_name, episode_number,
    episode_start, episode_stop,
    triggering_code_description,
    cancer_category, is_hodgkin,
    code_type, source_table, sct_cross_use_flag
  )

message("  Columns trimmed to Tableau-essential set")
message(glue("  Episodes: {ncol(episodes_export)} columns, Detail: {ncol(detail_export)} columns"))

# Step 7: Schema verification (Phase 99, D-13: dynamic schema validation)
if (!identical(colnames(episodes_export), EPISODES_SCHEMA)) {
  missing <- setdiff(EPISODES_SCHEMA, colnames(episodes_export))
  extra <- setdiff(colnames(episodes_export), EPISODES_SCHEMA)
  stop(glue("Episodes schema mismatch: missing=[{paste(missing, collapse=', ')}], extra=[{paste(extra, collapse=', ')}]"))
}
if (!identical(colnames(detail_export), DETAIL_SCHEMA)) {
  missing <- setdiff(DETAIL_SCHEMA, colnames(detail_export))
  extra <- setdiff(colnames(detail_export), DETAIL_SCHEMA)
  stop(glue("Detail schema mismatch: missing=[{paste(missing, collapse=', ')}], extra=[{paste(extra, collapse=', ')}]"))
}

message(glue("  Schema verification: PASSED ({length(EPISODES_SCHEMA)} episode cols, {length(DETAIL_SCHEMA)} detail cols)"))


# --- SECTION 5: WRITE CSV OUTPUTS ----

message("\n--- Writing CSV outputs ---")

write.csv(episodes_export, OUTPUT_EPISODES, row.names = FALSE, na = "")
message(glue("  Wrote {OUTPUT_EPISODES}"))
message(glue("    {format(nrow(episodes_export), big.mark = ',')} rows, {ncol(episodes_export)} columns"))

write.csv(detail_export, OUTPUT_DETAIL, row.names = FALSE, na = "")
message(glue("  Wrote {OUTPUT_DETAIL}"))
message(glue("    {format(nrow(detail_export), big.mark = ',')} rows, {ncol(detail_export)} columns"))


# --- SECTION 6: FINAL SUMMARY ----

message("\n=== Gantt Export Complete ===\n")

# Unique patient count
unique_patients <- length(unique(episodes_export$patient_id))
message(glue("  Unique patients: {format(unique_patients, big.mark = ',')}"))

# Total rows
message(glue("  Total episode rows: {format(nrow(episodes_export), big.mark = ',')}"))
message(glue("  Total detail rows: {format(nrow(detail_export), big.mark = ',')}"))

# Pseudo-treatment row counts
death_rows <- episodes_export %>%
  filter(treatment_type == "Death") %>%
  nrow()
message(glue("  Death pseudo-treatment rows: {format(death_rows, big.mark = ',')}"))

hl_dx_rows <- episodes_export %>%
  filter(treatment_type == "HL Diagnosis") %>%
  nrow()
message(glue("  HL Diagnosis pseudo-treatment rows: {format(hl_dx_rows, big.mark = ',')}"))

# Schema summary
message(glue("\n  Schema: {length(EPISODES_SCHEMA)} episode columns, {length(DETAIL_SCHEMA)} detail columns"))

# Drug name coverage stat
episodes_with_drugs <- episodes_export %>%
  filter(drug_names != "" & !is.na(drug_names) & !treatment_type %in% c("Death", "HL Diagnosis")) %>%
  nrow()
treatment_episodes_count <- episodes_export %>%
  filter(!treatment_type %in% c("Death", "HL Diagnosis")) %>%
  nrow()
message(glue("  Episodes with drug_names: {format(episodes_with_drugs, big.mark = ',')} / {format(treatment_episodes_count, big.mark = ',')} treatment episodes ({round(100 * episodes_with_drugs / max(treatment_episodes_count, 1), 1)}%)"))

message("\nDone.")
