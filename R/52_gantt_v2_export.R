# ==============================================================================
# Phase 52: Enhanced Gantt Export - v2 CSV with Encounter-Level Enrichments
# Updated by Phase 64: Data Quality Cleanup for Tableau Import
# ==============================================================================
#
# Purpose:
#   Produce Gantt v2 CSV files (gantt_episodes_v2.csv, gantt_detail_v2.csv)
#   integrating all v1.8 enhancements (encounter-level cancer categories, HL flags,
#   specific drug names, regimen labels, first-line flags) while preserving
#   existing v1 output files unchanged for backward compatibility.
#
# Inputs:
#   - cache/outputs/treatment_episodes.rds (enriched by Phases 60-62)
#   - cache/outputs/treatment_episode_detail.rds (enriched by Phase 60)
#   - cache/outputs/code_descriptions.rds (Phase 48b: code -> description lookup)
#   - cache/outputs/validated_death_dates.rds (Phase 59: pre-validated death dates)
#   - output/confirmed_hl_cohort.rds (Phase 55: HL diagnosis dates)
#
# Outputs:
#   - output/gantt_episodes_v2.csv (16 columns, Phase 64 cleaned & Phase 78 enriched)
#   - output/gantt_detail_v2.csv (14 columns, Phase 64 cleaned & Phase 78 enriched)
#
# Dependencies:
#   - 00_config (CONFIG paths, TREATMENT_TYPE_COLORS)
#   - utils_duckdb (DuckDB connection helpers)
#   - utils_dates (date parsing utilities)
#
# Requirements:
#   DOC-01, DOC-02, DOC-03
#
#   Phase 64 additions: Data quality cleanup for direct Tableau import —
#   semicolon-separated multi-value fields, simplified drug names, no literal NAs,
#   filled pseudo-treatment descriptions, "Unlinked" cancer category label,
#   and trimmed column set (14 episodes, 13 detail).
#
# v2 SCHEMA DOCUMENTATION (Post-Phase 64 Cleanup, Phase 78 Enhancements):
#
#   gantt_episodes_v2.csv (16 columns):
#     1. patient_id (chr) - Patient identifier
#     2. treatment_type (chr) - Treatment category (Chemotherapy, Radiation, SCT, etc.)
#     3. episode_number (int) - Sequential episode number per patient-type
#     4. episode_start (date) - First treatment date in episode
#     5. episode_stop (date) - Last treatment date in episode
#     6. episode_length_days (int) - Days from start to stop (0 for single-point)
#     7. distinct_dates_in_episode (int) - Number of unique treatment dates
#     8. historical_flag (lgl) - TRUE if episode includes historical treatment dates
#     9. triggering_codes (chr) - Semicolon-separated codes (Phase 64 cleanup)
#    10. drug_names (chr) - Semicolon-separated generic drug names (Phase 64 cleanup)
#    11. triggering_code_descriptions (chr) - Semicolon-separated descriptions (Phase 64 cleanup)
#    12. cancer_category (chr) - Encounter-level cancer category or "Unlinked" (Phase 64)
#    13. regimen_label (chr) - Regimen name: "ABVD", "BV+AVD", "Nivo+AVD", or NA (Phase 61)
#    14. is_first_line (lgl) - TRUE if episode is first-line therapy (Phase 62)
#    15. drug_group (chr) - Semicolon-separated drug category labels (Phase 78)
#    16. cause_of_death (chr) - Mapped cause of death category or NA (Phase 78)
#
#   Dropped columns from Phase 63 v2: encounter_ids, is_hodgkin, cancer_link_method
#
#   gantt_detail_v2.csv (14 columns):
#     1. patient_id (chr) - Patient identifier
#     2. treatment_type (chr) - Treatment category
#     3. treatment_date (date) - Single treatment date
#     4. triggering_code (chr) - Single triggering code (Phase 64 cleanup)
#     5. drug_name (chr) - Single generic drug name (Phase 64 cleanup)
#     6. episode_number (int) - Parent episode number
#     7. episode_start (date) - Parent episode start
#     8. episode_stop (date) - Parent episode stop
#     9. historical_flag (lgl) - Historical treatment flag
#    10. triggering_code_description (chr) - Single code description (Phase 64 cleanup)
#    11. cancer_category (chr) - Encounter-level cancer category or "Unlinked" (Phase 64)
#    12. regimen_label (chr) - Regimen name (from parent episode, Phase 61)
#    13. is_first_line (lgl) - First-line flag (from parent episode, Phase 62)
#    14. cause_of_death (chr) - Mapped cause of death category or NA (Phase 78)
#
#   Dropped columns from Phase 63 v2: ENCOUNTERID, is_hodgkin, cancer_link_method
#
# DECISION TRACEABILITY:
#   D-01: v2 is a superset of v1 — all 14 existing v1 columns plus 3 new columns
#   D-02: cancer_category uses encounter-level data from treatment_episodes.rds (Phase 61)
#   D-03: is_hodgkin derived from encounter-level cancer_category
#   D-04: New standalone R/63_gantt_v2_export.R script — does NOT modify R/49
#   D-05: R/63 reads enriched treatment_episodes.rds directly (columns pre-computed by Phases 61-62)
#   D-06: R/63 is simpler than R/49 because it does NOT re-derive cancer categories from cancer_summary.csv or PREFIX_MAP
#   D-07: Accept code duplication for Death/HL Diagnosis row construction (project pattern)
#   D-08: v2 schema documented in R/63's header comment block
#   D-09: v2 includes Death and HL Diagnosis pseudo-treatment rows (same as v1)
#   D-10: New v2 columns on pseudo-treatment rows: cancer_link_method="none", regimen_label=NA, is_first_line=FALSE
#   D-78-09: cause_of_death appended as last column (non-breaking)
#   D-78-10: Missing/unmapped ICD-10 -> "Unknown or Unspecified"
#   D-78-11: >40% missingness triggers console warning
#   D-78-12: Both gantt_episodes_v2.csv and gantt_detail_v2.csv get cause_of_death
#   D-78-14: drug_group propagated from treatment_episodes.rds to episodes CSV
#
# INPUTS:
#   - cache/outputs/treatment_episodes.rds (enriched by Phases 60-62)
#   - cache/outputs/treatment_episode_detail.rds (enriched by Phase 60)
#   - cache/outputs/code_descriptions.rds (Phase 48b: code -> description lookup)
#   - cache/outputs/validated_death_dates.rds (Phase 59: pre-validated death dates)
#   - output/confirmed_hl_cohort.rds (Phase 55: HL diagnosis dates)
#
# OUTPUTS:
#   - output/gantt_episodes_v2.csv (16 columns, Phase 64 cleaned & Phase 78 enriched)
#   - output/gantt_detail_v2.csv (14 columns, Phase 64 cleaned & Phase 78 enriched)
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

# Input paths: existing RDS artifacts
EPISODES_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
DETAIL_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds")
DESCRIPTIONS_RDS <- file.path(CONFIG$cache$outputs_dir, "code_descriptions.rds")
VALIDATED_DEATHS_RDS <- file.path(CONFIG$cache$outputs_dir, "validated_death_dates.rds")
COHORT_RDS <- file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds")

# Output paths: v2 CSV files for third-party Gantt chart consumption
OUTPUT_EPISODES_V2 <- file.path(CONFIG$output_dir, "gantt_episodes_v2.csv")
OUTPUT_DETAIL_V2 <- file.path(CONFIG$output_dir, "gantt_detail_v2.csv")

# SECTION 0: INPUT VALIDATION ----
# SAFE-01: Validate all input artifacts exist (fail-fast before any loading)
assert_rds_exists(EPISODES_RDS, script_name = "R/52")
assert_rds_exists(DETAIL_RDS, script_name = "R/52")


# --- SECTION 2: LOAD INPUT DATA ----

message("=== Phase 63: Enhanced Gantt Export - v2 CSV ===\n")

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
  required_cols = c("patient_id", "treatment_type", "treatment_date", "code"),
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
if (!"regimen_label" %in% names(episodes)) {
  warning("regimen_label column not found in treatment_episodes.rds — Phase 61 not yet run. Using default NA.")
  episodes <- episodes %>% mutate(regimen_label = NA_character_)
}
if (!"is_first_line" %in% names(episodes)) {
  warning("is_first_line column not found in treatment_episodes.rds — Phase 62 not yet run. Using default FALSE.")
  episodes <- episodes %>% mutate(is_first_line = FALSE)
}
if (!"drug_group" %in% names(episodes)) {
  warning("drug_group column not found in treatment_episodes.rds — Phase 78 R/28 not yet run. Using default NA.")
  episodes <- episodes %>% mutate(drug_group = NA_character_)
}
if (!"triggering_code_description" %in% names(episodes)) {
  warning("triggering_code_description column not found in treatment_episodes.rds — Phase 78 R/28 not yet run. Using default NA.")
  episodes <- episodes %>% mutate(triggering_code_description = NA_character_)
}


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


# --- SECTION 3B: DEATH CAUSE MAPPING ----

# Helper: map single ICD-10 code to cause of death category via DEATH_CAUSE_MAP
# D-78-10: Missing/unmapped -> "Unknown or Unspecified"
map_death_cause <- function(death_cause_code) {
  if (is.na(death_cause_code) || death_cause_code == "") return("Unknown or Unspecified")
  prefix_3char <- str_sub(death_cause_code, 1, 3)
  if (prefix_3char %in% names(DEATH_CAUSE_MAP)) return(DEATH_CAUSE_MAP[[prefix_3char]])
  return("Unknown or Unspecified")
}

# Load quality decision artifact from Plan 01
QUALITY_RESULT_RDS <- file.path(CONFIG$cache$outputs_dir, "death_cause_quality_result.rds")
death_quality <- NULL
cause_of_death_available <- TRUE  # default: proceed with integration
if (file.exists(QUALITY_RESULT_RDS)) {
  death_quality <- readRDS(QUALITY_RESULT_RDS)
  if (!death_quality$death_cause_available) {
    message("  WARNING: DEATH_CAUSE field not available per quality profiling (R/35)")
    cause_of_death_available <- FALSE
  } else if (death_quality$missingness_rate > 60) {
    message(glue("  WARNING: Cause of death {death_quality$missingness_rate}% missing -- column will contain mostly 'Unknown or Unspecified'"))
  }
} else {
  message("  WARNING: death_cause_quality_result.rds not found -- proceeding with cause_of_death integration")
}


# --- SECTION 4: SELECT AND ORDER COLUMNS ----

message("\n--- Building v2 export tables ---")

# v2 episodes: 17 columns (v1 14 + v2 3)
# Per D-05, D-06: cancer_category, cancer_link_method, is_hodgkin, regimen_label, is_first_line
# are already in treatment_episodes.rds — no re-derivation needed
episodes_export <- episodes %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, historical_flag, triggering_codes,
    encounter_ids, drug_names, drug_group
  ) %>%
  mutate(
    triggering_code_descriptions = sapply(triggering_codes, map_codes_to_descriptions, USE.NAMES = FALSE),
    cause_of_death = NA_character_  # Treatment rows get NA per D-78-10
  ) %>%
  # Re-join the base columns that were selected, plus add enriched columns from episodes
  left_join(
    episodes %>% select(
      patient_id, episode_number, treatment_type,
      cancer_category, is_hodgkin, cancer_link_method,
      regimen_label, is_first_line
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
    distinct_dates_in_episode, historical_flag, triggering_codes,
    encounter_ids, drug_names, triggering_code_descriptions,
    cancer_category, is_hodgkin, cancer_link_method, regimen_label, is_first_line,
    drug_group, cause_of_death
  )

message(glue("  Built episodes_export: {format(nrow(episodes_export), big.mark = ',')} rows, {ncol(episodes_export)} columns"))

# v2 detail: 15 columns (v1 13 + v2 2)
# Detail table does NOT have cancer_link_method, regimen_label, is_first_line —
# must join from episodes
episodes_v2_cols <- episodes %>%
  select(
    patient_id, treatment_type, episode_number, cancer_category, is_hodgkin,
    cancer_link_method, regimen_label, is_first_line
  )

detail_export <- detail %>%
  select(
    patient_id, treatment_type, treatment_date, triggering_code,
    ENCOUNTERID, drug_name,
    episode_number, episode_start, episode_stop, historical_flag
  ) %>%
  mutate(
    triggering_code_description = sapply(triggering_code, lookup_description, USE.NAMES = FALSE),
    cause_of_death = NA_character_  # Treatment detail rows get NA per D-78-10
  ) %>%
  left_join(episodes_v2_cols, by = c("patient_id", "treatment_type", "episode_number")) %>%
  mutate(
    cancer_category = ifelse(is.na(cancer_category), "", cancer_category),
    is_hodgkin = ifelse(is.na(is_hodgkin), FALSE, is_hodgkin)
  ) %>%
  select(
    patient_id, treatment_type, treatment_date, triggering_code,
    ENCOUNTERID, drug_name,
    episode_number, episode_start, episode_stop, historical_flag,
    triggering_code_description,
    cancer_category, is_hodgkin, cancer_link_method, regimen_label, is_first_line,
    cause_of_death
  )

message(glue("  Built detail_export: {format(nrow(detail_export), big.mark = ',')} rows, {ncol(detail_export)} columns"))


# --- SECTION 4B: DEATH PSEUDO-TREATMENT ROWS (per D-09, D-10) ---

if (file.exists(VALIDATED_DEATHS_RDS)) {
  message("\n--- Building Death pseudo-treatment rows ---")

  # SAFE-01: Validate RDS exists before loading
  assert_rds_exists(VALIDATED_DEATHS_RDS, script_name = "R/52")
  validated_deaths <- readRDS(VALIDATED_DEATHS_RDS)

  death_data <- validated_deaths %>%
    filter(!is.na(DEATH_DATE))

  # Check if DEATH_CAUSE is available and map to cause_of_death
  if ("DEATH_CAUSE" %in% names(death_data) && cause_of_death_available) {
    death_data <- death_data %>%
      mutate(cause_of_death = sapply(DEATH_CAUSE, map_death_cause, USE.NAMES = FALSE)) %>%
      select(ID, DEATH_DATE, cause_of_death)
  } else if (!"DEATH_CAUSE" %in% names(validated_deaths) && cause_of_death_available) {
    # DEATH_CAUSE not in validated_death_dates.rds -- query DEATH table directly
    message("  DEATH_CAUSE not in validated_death_dates.rds -- querying DEATH table directly")
    USE_DUCKDB <- TRUE
    open_pcornet_con()
    death_cause_data <- get_pcornet_table("DEATH") %>% collect()
    close_pcornet_con()

    if ("DEATH_CAUSE" %in% names(death_cause_data)) {
      death_cause_lookup <- death_cause_data %>%
        select(ID, DEATH_CAUSE) %>%
        filter(!is.na(DEATH_CAUSE) & DEATH_CAUSE != "") %>%
        group_by(ID) %>%
        summarise(DEATH_CAUSE = first(DEATH_CAUSE), .groups = "drop")

      death_data <- death_data %>%
        left_join(death_cause_lookup, by = "ID") %>%
        mutate(cause_of_death = sapply(DEATH_CAUSE, map_death_cause, USE.NAMES = FALSE)) %>%
        select(ID, DEATH_DATE, cause_of_death)
    } else {
      message("  DEATH_CAUSE column not available in DEATH table")
      death_data <- death_data %>%
        mutate(cause_of_death = "Unknown or Unspecified") %>%
        select(ID, DEATH_DATE, cause_of_death)
    }
  } else {
    death_data <- death_data %>%
      mutate(cause_of_death = NA_character_) %>%
      select(ID, DEATH_DATE, cause_of_death)
  }

  if (nrow(death_data) > 0) {
    # Build death_episodes with all 19 v2 columns (Phase 78: +drug_group, +cause_of_death)
    death_episodes <- death_data %>%
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
        triggering_code_descriptions = "",
        cancer_category = "",
        is_hodgkin = FALSE,
        cancer_link_method = "none", # v2 default per D-10
        regimen_label = NA_character_, # v2 default per D-10
        is_first_line = FALSE, # v2 default per D-10
        drug_group = NA_character_  # Death rows have no drug group (Phase 78)
        # cause_of_death already in death_data from mapping above
      ) %>%
      select(
        patient_id, treatment_type, episode_number,
        episode_start, episode_stop, episode_length_days,
        distinct_dates_in_episode, historical_flag, triggering_codes,
        encounter_ids, drug_names, triggering_code_descriptions,
        cancer_category, is_hodgkin, cancer_link_method, regimen_label, is_first_line,
        drug_group, cause_of_death
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

    # Build death_detail with all 16 v2 detail columns (Phase 78: +cause_of_death)
    death_detail <- death_data %>%
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
        triggering_code_description = "",
        cancer_category = "",
        is_hodgkin = FALSE,
        cancer_link_method = "none", # v2 default per D-10
        regimen_label = NA_character_, # v2 default per D-10
        is_first_line = FALSE  # v2 default per D-10
        # cause_of_death already in death_data from mapping above
      ) %>%
      select(
        patient_id, treatment_type, treatment_date, triggering_code,
        ENCOUNTERID, drug_name,
        episode_number, episode_start, episode_stop, historical_flag,
        triggering_code_description,
        cancer_category, is_hodgkin, cancer_link_method, regimen_label, is_first_line,
        cause_of_death
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


# --- SECTION 4C: HL DIAGNOSIS PSEUDO-TREATMENT ROWS (per D-09, D-10) ---

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
    # Build hl_dx_episodes with all 19 v2 columns (Phase 78: +drug_group, +cause_of_death)
    hl_dx_episodes <- hl_dx_data %>%
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
        triggering_code_descriptions = "",
        cancer_category = "Hodgkin Lymphoma",
        is_hodgkin = TRUE,
        cancer_link_method = "none", # v2 default per D-10
        regimen_label = NA_character_, # v2 default per D-10
        is_first_line = FALSE, # v2 default per D-10
        drug_group = NA_character_, # HL Diagnosis rows have no drug group (Phase 78)
        cause_of_death = NA_character_  # HL Diagnosis rows are not death events (Phase 78)
      ) %>%
      select(
        patient_id, treatment_type, episode_number,
        episode_start, episode_stop, episode_length_days,
        distinct_dates_in_episode, historical_flag, triggering_codes,
        encounter_ids, drug_names, triggering_code_descriptions,
        cancer_category, is_hodgkin, cancer_link_method, regimen_label, is_first_line,
        drug_group, cause_of_death
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

    # Build hl_dx_detail with all 16 v2 detail columns (Phase 78: +cause_of_death)
    hl_dx_detail <- hl_dx_data %>%
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
        triggering_code_description = "",
        cancer_category = "Hodgkin Lymphoma",
        is_hodgkin = TRUE,
        cancer_link_method = "none", # v2 default per D-10
        regimen_label = NA_character_, # v2 default per D-10
        is_first_line = FALSE, # v2 default per D-10
        cause_of_death = NA_character_  # HL Diagnosis rows are not death events (Phase 78)
      ) %>%
      select(
        patient_id, treatment_type, treatment_date, triggering_code,
        ENCOUNTERID, drug_name,
        episode_number, episode_start, episode_stop, historical_flag,
        triggering_code_description,
        cancer_category, is_hodgkin, cancer_link_method, regimen_label, is_first_line,
        cause_of_death
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


# --- SECTION 4C2: CAUSE OF DEATH MISSINGNESS WARNING (D-78-11) ----

# Check cause_of_death missingness for Death rows
if (cause_of_death_available && any(!is.na(episodes_export$cause_of_death))) {
  death_rows_export <- episodes_export %>% filter(treatment_type == "Death")
  if (nrow(death_rows_export) > 0) {
    n_unknown <- sum(death_rows_export$cause_of_death == "Unknown or Unspecified" | is.na(death_rows_export$cause_of_death), na.rm = TRUE)
    pct_missing <- round(100 * n_unknown / nrow(death_rows_export), 1)
    if (pct_missing > 40) {
      message(glue("  WARNING: Cause of death missing/unmapped for {pct_missing}% of death rows (D-78-11)"))
    } else {
      message(glue("  Cause of death completeness: {100 - pct_missing}% of death rows have mapped cause"))
    }
  }
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
  values <- unique(values)

  if (length(values) == 0) {
    return("")
  }
  paste(values, collapse = sep_out)
}

# Non-drug stopwords common in RxNorm descriptions (units, dosage forms, salts)
DRUG_STOPWORDS <- c(
  # Units
  "ml", "mg", "gm", "mcg", "ug", "meq", "mmol", "hr",
  # Dosage forms
  "injection", "solution", "tablet", "capsule", "oral", "topical",
  "pack", "kit", "vial", "actuation", "inhalation", "spray",
  "cream", "ointment", "gel", "patch", "suspension", "powder",
  "concentrate", "prefilled", "syringe", "pen", "autoinjector",
  "extended", "release", "delayed", "ophthalmic", "nasal",
  "rectal", "vaginal", "sublingual", "transdermal", "infusion",
  # Salt forms
  "hydrochloride", "sulfate", "sodium", "acetate", "citrate",
  "fumarate", "maleate", "succinate", "tartrate", "mesylate",
  "phosphate", "chloride", "bromide", "vedotin", "pegol",
  "disodium", "potassium", "calcium", "oxide", "bitartrate",
  # Filler words
  "in", "of", "and", "per", "for", "with", "the"
)

# Brand-to-generic mapping for drugs in Hodgkin Lymphoma regimens
BRAND_TO_GENERIC <- c(
  "adcetris"    = "Brentuximab",
  "opdivo"      = "Nivolumab",
  "keytruda"    = "Pembrolizumab",
  "vincasar"    = "Vincristine",
  "oncovin"     = "Vincristine",
  "adriamycin"  = "Doxorubicin",
  "platinol"    = "Cisplatin",
  "paraplatin"  = "Carboplatin",
  "blenoxane"   = "Bleomycin",
  "mustargen"   = "Mechlorethamine",
  "matulane"    = "Procarbazine",
  "velban"      = "Vinblastine",
  "neosar"      = "Cyclophosphamide",
  "cytoxan"     = "Cyclophosphamide"
)

# Helper function: extract generic drug name from RxNorm string
simplify_drug_name <- function(drug_str) {
  if (is.na(drug_str) || drug_str == "" || drug_str == "NA") {
    return("")
  }

  drugs <- str_split(drug_str, ";")[[1]] # Already semicolon-separated after multi-value cleanup
  drugs <- str_trim(drugs)

  simplified <- sapply(drugs, function(d) {
    if (d == "" || is.na(d)) {
      return("")
    }
    d_lower <- tolower(d)

    # Extract all 2+ letter words
    words <- str_extract_all(d_lower, "[a-z]{2,}")[[1]]
    if (length(words) == 0) {
      return(d)
    }

    # Filter out non-drug stopwords
    drug_words <- words[!words %in% DRUG_STOPWORDS]
    if (length(drug_words) == 0) {
      return(d)
    }

    name <- drug_words[1]

    # Apply brand-to-generic mapping (already title-cased in the map)
    if (name %in% names(BRAND_TO_GENERIC)) {
      return(BRAND_TO_GENERIC[[name]])
    }

    # Title case: first letter uppercase
    paste0(toupper(substr(name, 1, 1)), substr(name, 2, nchar(name)))
  }, USE.NAMES = FALSE)

  simplified <- unique(simplified)
  paste(simplified, collapse = ";")
}

# Step 1: Clean multi-value fields (separator + dedup + drop blanks)
episodes_export <- episodes_export %>%
  mutate(
    triggering_codes = sapply(triggering_codes, clean_multi_value, USE.NAMES = FALSE),
    drug_names = sapply(drug_names, clean_multi_value, USE.NAMES = FALSE),
    triggering_code_descriptions = sapply(triggering_code_descriptions, clean_multi_value, USE.NAMES = FALSE)
  )

detail_export <- detail_export %>%
  mutate(
    triggering_code = sapply(triggering_code, clean_multi_value, USE.NAMES = FALSE),
    triggering_code_description = sapply(triggering_code_description, clean_multi_value, USE.NAMES = FALSE)
  )

message("  Multi-value fields cleaned (separator: semicolon, deduped, blanks dropped)")

# Step 2: Simplify drug names
episodes_export <- episodes_export %>%
  mutate(drug_names = sapply(drug_names, simplify_drug_name, USE.NAMES = FALSE))

detail_export <- detail_export %>%
  mutate(drug_name = sapply(drug_name, simplify_drug_name, USE.NAMES = FALSE))

message("  Drug names simplified (generic names only)")

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

# Step 6: Column trimming (drop encounter_ids, is_hodgkin, cancer_link_method per D-02, D-04)
episodes_export <- episodes_export %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, historical_flag,
    triggering_codes, drug_names, triggering_code_descriptions,
    cancer_category, regimen_label, is_first_line,
    drug_group, cause_of_death
  )

detail_export <- detail_export %>%
  select(
    patient_id, treatment_type, treatment_date,
    triggering_code, drug_name, episode_number,
    episode_start, episode_stop, historical_flag,
    triggering_code_description, cancer_category,
    regimen_label, is_first_line,
    cause_of_death
  )

message("  Columns trimmed to Tableau-essential set")
message(glue("  Episodes: {ncol(episodes_export)} columns, Detail: {ncol(detail_export)} columns"))

# Step 7: Column count verification
expected_ep_cols <- 16  # was 14, Phase 78: +drug_group, +cause_of_death
expected_detail_cols <- 14  # was 13, Phase 78: +cause_of_death

if (ncol(episodes_export) != expected_ep_cols) {
  stop(glue("ERROR: episodes_export has {ncol(episodes_export)} columns, expected {expected_ep_cols}"))
}
if (ncol(detail_export) != expected_detail_cols) {
  stop(glue("ERROR: detail_export has {ncol(detail_export)} columns, expected {expected_detail_cols}"))
}

message("  Column count verification: PASSED")


# --- SECTION 5: WRITE CSV OUTPUTS ----

message("\n--- Writing v2 CSV outputs ---")

write.csv(episodes_export, OUTPUT_EPISODES_V2, row.names = FALSE, na = "")
message(glue("  Wrote {OUTPUT_EPISODES_V2}"))
message(glue("    {format(nrow(episodes_export), big.mark = ',')} rows, {ncol(episodes_export)} columns"))

write.csv(detail_export, OUTPUT_DETAIL_V2, row.names = FALSE, na = "")
message(glue("  Wrote {OUTPUT_DETAIL_V2}"))
message(glue("    {format(nrow(detail_export), big.mark = ',')} rows, {ncol(detail_export)} columns"))


# --- SECTION 6: FINAL SUMMARY ----

message("\n=== v2 Gantt Export Complete ===\n")

# Unique patient count
unique_patients <- length(unique(episodes_export$patient_id))
message(glue("  Unique patients: {format(unique_patients, big.mark = ',')}"))

# Total rows
message(glue("  Total episode rows: {format(nrow(episodes_export), big.mark = ',')}"))
message(glue("  Total detail rows: {format(nrow(detail_export), big.mark = ',')}"))

# v2-specific stats
episodes_with_regimen <- episodes_export %>%
  filter(!is.na(regimen_label)) %>%
  nrow()
message(glue("  Episodes with regimen label: {format(episodes_with_regimen, big.mark = ',')} ({round(100 * episodes_with_regimen / nrow(episodes_export), 1)}%)"))

episodes_first_line <- episodes_export %>%
  filter(is_first_line == TRUE) %>%
  nrow()
message(glue("  Episodes flagged as first-line: {format(episodes_first_line, big.mark = ',')} ({round(100 * episodes_first_line / nrow(episodes_export), 1)}%)"))

# Pseudo-treatment row counts
death_rows <- episodes_export %>%
  filter(treatment_type == "Death") %>%
  nrow()
message(glue("  Death pseudo-treatment rows: {format(death_rows, big.mark = ',')}"))

hl_dx_rows <- episodes_export %>%
  filter(treatment_type == "HL Diagnosis") %>%
  nrow()
message(glue("  HL Diagnosis pseudo-treatment rows: {format(hl_dx_rows, big.mark = ',')}"))

# v1 vs v2 column comparison
message("\n  v1 vs v2 column comparison (Phase 64 cleanup, Phase 78 enhancements):")
message("    v1 episodes: 14 columns | v2 episodes: 16 columns (Phase 78: +drug_group, +cause_of_death)")
message("    v1 detail: 13 columns | v2 detail: 14 columns (Phase 78: +cause_of_death)")
message("    Phase 64 dropped: encounter_ids, is_hodgkin, cancer_link_method (internal columns)")

# Cause of death stats
deaths_with_cause <- episodes_export %>%
  filter(treatment_type == "Death" & !is.na(cause_of_death) & cause_of_death != "" & cause_of_death != "Unknown or Unspecified") %>%
  nrow()
message(glue("  Deaths with mapped cause: {format(deaths_with_cause, big.mark = ',')}"))

message("\nDone.")
