# ==============================================================================
# Phase 63 Plan 01: Enhanced Gantt Export - v2 CSV with Encounter-Level Enrichments
# ==============================================================================
#
# PURPOSE:
#   Produce Gantt v2 CSV files (gantt_episodes_v2.csv, gantt_detail_v2.csv)
#   integrating all v1.8 enhancements (encounter-level cancer categories, HL flags,
#   specific drug names, regimen labels, first-line flags) while preserving
#   existing v1 output files unchanged for backward compatibility.
#
# v2 SCHEMA DOCUMENTATION:
#
#   gantt_episodes_v2.csv (17 columns):
#     1. patient_id (chr) - Patient identifier
#     2. treatment_type (chr) - Treatment category (Chemotherapy, Radiation, SCT, etc.)
#     3. episode_number (int) - Sequential episode number per patient-type
#     4. episode_start (date) - First treatment date in episode
#     5. episode_stop (date) - Last treatment date in episode
#     6. episode_length_days (int) - Days from start to stop (0 for single-point)
#     7. distinct_dates_in_episode (int) - Number of unique treatment dates
#     8. historical_flag (lgl) - TRUE if episode includes historical treatment dates
#     9. triggering_codes (chr) - Comma-separated codes triggering this episode
#    10. encounter_ids (chr) - Comma-separated ENCOUNTERIDs (Phase 60)
#    11. drug_names (chr) - Comma-separated drug names (Phase 60)
#    12. triggering_code_descriptions (chr) - Comma-separated descriptions
#    13. cancer_category (chr) - Encounter-level cancer category from Phase 61
#    14. is_hodgkin (lgl) - TRUE if cancer_category is "Hodgkin Lymphoma"
#    15. cancer_link_method (chr) - Linkage method: "encounterid", "temporal", "none" (Phase 61)
#    16. regimen_label (chr) - Regimen name: "ABVD", "BV+AVD", "Nivo+AVD", or NA (Phase 61)
#    17. is_first_line (lgl) - TRUE if episode is first-line therapy (Phase 62)
#
#   gantt_detail_v2.csv (15 columns):
#     1. patient_id (chr) - Patient identifier
#     2. treatment_type (chr) - Treatment category
#     3. treatment_date (date) - Single treatment date
#     4. triggering_code (chr) - Single triggering code for this date
#     5. ENCOUNTERID (chr) - Single encounter ID (Phase 60)
#     6. drug_name (chr) - Single drug name (Phase 60)
#     7. episode_number (int) - Parent episode number
#     8. episode_start (date) - Parent episode start
#     9. episode_stop (date) - Parent episode stop
#    10. historical_flag (lgl) - Historical treatment flag
#    11. triggering_code_description (chr) - Single code description
#    12. cancer_category (chr) - Encounter-level cancer category (from parent episode)
#    13. is_hodgkin (lgl) - HL flag (from parent episode)
#    14. cancer_link_method (chr) - Linkage method (from parent episode, Phase 61)
#    15. regimen_label (chr) - Regimen name (from parent episode, Phase 61)
#    16. is_first_line (lgl) - First-line flag (from parent episode, Phase 62)
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
#
# INPUTS:
#   - cache/outputs/treatment_episodes.rds (enriched by Phases 60-62)
#   - cache/outputs/treatment_episode_detail.rds (enriched by Phase 60)
#   - cache/outputs/code_descriptions.rds (Phase 48b: code -> description lookup)
#   - cache/outputs/validated_death_dates.rds (Phase 59: pre-validated death dates)
#   - output/confirmed_hl_cohort.rds (Phase 55: HL diagnosis dates)
#
# OUTPUTS:
#   - output/gantt_episodes_v2.csv (17 columns)
#   - output/gantt_detail_v2.csv (15 columns)
#
# ==============================================================================


# --- SECTION 1: SETUP AND CONFIGURATION ---

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(lubridate)
})

source("R/00_config.R")
source("R/utils_duckdb.R")
source("R/utils_dates.R")

# Input paths: existing RDS artifacts
EPISODES_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
DETAIL_RDS   <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds")
DESCRIPTIONS_RDS <- file.path(CONFIG$cache$outputs_dir, "code_descriptions.rds")
VALIDATED_DEATHS_RDS <- file.path(CONFIG$cache$outputs_dir, "validated_death_dates.rds")
COHORT_RDS <- file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds")

# Output paths: v2 CSV files for third-party Gantt chart consumption
OUTPUT_EPISODES_V2 <- file.path(CONFIG$output_dir, "gantt_episodes_v2.csv")
OUTPUT_DETAIL_V2   <- file.path(CONFIG$output_dir, "gantt_detail_v2.csv")


# --- SECTION 2: LOAD INPUT DATA ---

message("=== Phase 63: Enhanced Gantt Export - v2 CSV ===\n")

# Verify RDS artifacts exist before attempting to load
if (!file.exists(EPISODES_RDS)) {
  stop(glue("ERROR: {EPISODES_RDS} not found. Run R/44a_treatment_episodes.R first."))
}
if (!file.exists(DETAIL_RDS)) {
  stop(glue("ERROR: {DETAIL_RDS} not found. Run R/44a_treatment_episodes.R first."))
}

# Load episode-level data (bars: one row per patient/type/episode)
episodes <- readRDS(EPISODES_RDS)
message(glue("  Loaded {format(nrow(episodes), big.mark = ',')} episode rows"))

# Load detail-level data (ticks: one row per patient/date/code)
detail <- readRDS(DETAIL_RDS)
message(glue("  Loaded {format(nrow(detail), big.mark = ',')} detail rows"))

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


# --- SECTION 3: CODE DESCRIPTION LOOKUP ---

# Load code descriptions (Phase 48b) — non-fatal if missing
code_descriptions <- NULL
if (file.exists(DESCRIPTIONS_RDS)) {
  code_descriptions <- readRDS(DESCRIPTIONS_RDS)
  message(glue("  Loaded {format(length(code_descriptions), big.mark = ',')} code descriptions"))
} else {
  message("  WARNING: code_descriptions.rds not found. Description columns will be empty.")
}

# Helper: map a single code to its description (empty string if missing)
# code_descriptions is a named character vector (from R/48b), not a dataframe
lookup_description <- function(code) {
  if (is.null(code_descriptions) || is.na(code) || code == "") return("")
  if (code %in% names(code_descriptions)) return(code_descriptions[[code]])
  return("")
}

# Helper: map comma-separated codes to comma-separated descriptions
map_codes_to_descriptions <- function(codes_str) {
  if (is.na(codes_str) || codes_str == "") return("")
  codes <- str_split(codes_str, ",")[[1]]
  descriptions <- sapply(codes, lookup_description, USE.NAMES = FALSE)
  paste(descriptions, collapse = ",")
}


# --- SECTION 4: SELECT AND ORDER COLUMNS ---

message("\n--- Building v2 export tables ---")

# v2 episodes: 17 columns (v1 14 + v2 3)
# Per D-05, D-06: cancer_category, cancer_link_method, is_hodgkin, regimen_label, is_first_line
# are already in treatment_episodes.rds — no re-derivation needed
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
  # Re-join the base columns that were selected, plus add enriched columns from episodes
  left_join(
    episodes %>% select(patient_id, episode_number, treatment_type,
                        cancer_category, is_hodgkin, cancer_link_method,
                        regimen_label, is_first_line),
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
    cancer_category, is_hodgkin, cancer_link_method, regimen_label, is_first_line
  )

message(glue("  Built episodes_export: {format(nrow(episodes_export), big.mark = ',')} rows, {ncol(episodes_export)} columns"))

# v2 detail: 15 columns (v1 13 + v2 2)
# Detail table does NOT have cancer_link_method, regimen_label, is_first_line —
# must join from episodes
episodes_v2_cols <- episodes %>%
  select(patient_id, episode_number, cancer_category, is_hodgkin,
         cancer_link_method, regimen_label, is_first_line)

detail_export <- detail %>%
  select(
    patient_id, treatment_type, treatment_date, triggering_code,
    ENCOUNTERID, drug_name,
    episode_number, episode_start, episode_stop, historical_flag
  ) %>%
  mutate(
    triggering_code_description = sapply(triggering_code, lookup_description, USE.NAMES = FALSE)
  ) %>%
  left_join(episodes_v2_cols, by = c("patient_id", "episode_number")) %>%
  mutate(
    cancer_category = ifelse(is.na(cancer_category), "", cancer_category),
    is_hodgkin = ifelse(is.na(is_hodgkin), FALSE, is_hodgkin)
  ) %>%
  select(
    patient_id, treatment_type, treatment_date, triggering_code,
    ENCOUNTERID, drug_name,
    episode_number, episode_start, episode_stop, historical_flag,
    triggering_code_description,
    cancer_category, is_hodgkin, cancer_link_method, regimen_label, is_first_line
  )

message(glue("  Built detail_export: {format(nrow(detail_export), big.mark = ',')} rows, {ncol(detail_export)} columns"))


# --- SECTION 4B: DEATH PSEUDO-TREATMENT ROWS (per D-09, D-10) ---

if (file.exists(VALIDATED_DEATHS_RDS)) {
  message("\n--- Building Death pseudo-treatment rows ---")

  validated_deaths <- readRDS(VALIDATED_DEATHS_RDS)

  death_data <- validated_deaths %>%
    filter(!is.na(DEATH_DATE)) %>%
    select(ID, DEATH_DATE)

  if (nrow(death_data) > 0) {
    # Build death_episodes with all 17 v2 columns
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
        cancer_link_method = "none",      # v2 default per D-10
        regimen_label = NA_character_,    # v2 default per D-10
        is_first_line = FALSE             # v2 default per D-10
      ) %>%
      select(
        patient_id, treatment_type, episode_number,
        episode_start, episode_stop, episode_length_days,
        distinct_dates_in_episode, historical_flag, triggering_codes,
        encounter_ids, drug_names, triggering_code_descriptions,
        cancer_category, is_hodgkin, cancer_link_method, regimen_label, is_first_line
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

    # Build death_detail with all 15 v2 detail columns
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
        cancer_link_method = "none",      # v2 default per D-10
        regimen_label = NA_character_,    # v2 default per D-10
        is_first_line = FALSE             # v2 default per D-10
      ) %>%
      select(
        patient_id, treatment_type, treatment_date, triggering_code,
        ENCOUNTERID, drug_name,
        episode_number, episode_start, episode_stop, historical_flag,
        triggering_code_description,
        cancer_category, is_hodgkin, cancer_link_method, regimen_label, is_first_line
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

  hl_cohort <- readRDS(COHORT_RDS)

  # Filter for valid first_hl_dx_date
  hl_dx_data <- hl_cohort %>%
    filter(!is.na(first_hl_dx_date)) %>%
    select(ID, first_hl_dx_date)

  if (nrow(hl_dx_data) > 0) {
    # Build hl_dx_episodes with all 17 v2 columns
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
        cancer_link_method = "none",      # v2 default per D-10
        regimen_label = NA_character_,    # v2 default per D-10
        is_first_line = FALSE             # v2 default per D-10
      ) %>%
      select(
        patient_id, treatment_type, episode_number,
        episode_start, episode_stop, episode_length_days,
        distinct_dates_in_episode, historical_flag, triggering_codes,
        encounter_ids, drug_names, triggering_code_descriptions,
        cancer_category, is_hodgkin, cancer_link_method, regimen_label, is_first_line
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

    # Build hl_dx_detail with all 15 v2 detail columns
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
        cancer_link_method = "none",      # v2 default per D-10
        regimen_label = NA_character_,    # v2 default per D-10
        is_first_line = FALSE             # v2 default per D-10
      ) %>%
      select(
        patient_id, treatment_type, treatment_date, triggering_code,
        ENCOUNTERID, drug_name,
        episode_number, episode_start, episode_stop, historical_flag,
        triggering_code_description,
        cancer_category, is_hodgkin, cancer_link_method, regimen_label, is_first_line
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


# --- SECTION 5: WRITE CSV OUTPUTS ---

message("\n--- Writing v2 CSV outputs ---")

write.csv(episodes_export, OUTPUT_EPISODES_V2, row.names = FALSE)
message(glue("  Wrote {OUTPUT_EPISODES_V2}"))
message(glue("    {format(nrow(episodes_export), big.mark = ',')} rows, {ncol(episodes_export)} columns"))

write.csv(detail_export, OUTPUT_DETAIL_V2, row.names = FALSE)
message(glue("  Wrote {OUTPUT_DETAIL_V2}"))
message(glue("    {format(nrow(detail_export), big.mark = ',')} rows, {ncol(detail_export)} columns"))


# --- SECTION 6: FINAL SUMMARY ---

message("\n=== v2 Gantt Export Complete ===\n")

# Unique patient count
unique_patients <- length(unique(episodes_export$patient_id))
message(glue("  Unique patients: {format(unique_patients, big.mark = ',')}"))

# Total rows
message(glue("  Total episode rows: {format(nrow(episodes_export), big.mark = ',')}"))
message(glue("  Total detail rows: {format(nrow(detail_export), big.mark = ',')}"))

# v2-specific stats
episodes_with_cancer_link <- episodes_export %>%
  filter(cancer_link_method != "none") %>%
  nrow()
message(glue("  Episodes with cancer linkage: {format(episodes_with_cancer_link, big.mark = ',')} ({round(100 * episodes_with_cancer_link / nrow(episodes_export), 1)}%)"))

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
message("\n  v1 vs v2 column comparison:")
message("    v1 episodes: 14 columns | v2 episodes: 17 columns (+cancer_link_method, +regimen_label, +is_first_line)")
message("    v1 detail: 13 columns | v2 detail: 15 columns (+cancer_link_method, +regimen_label, +is_first_line)")

message("\nDone.")
