# =============================================================================
# Phase 01: Gantt Chart Data Export
# =============================================================================
# Combines treatment episode and episode detail RDS artifacts into two CSV files
# for third-party Gantt chart visualization.
#
# Decision traceability:
#   D-01: Two-table output (bars + ticks) with exact column specs
#   D-02: Detail table preserves one-row-per-code granularity
#   D-03: Separate rows by treatment type (concurrent as separate rows)
#   D-04: Full cohort (no filtering)
#   D-05: No payer tier data
#   D-06: CSV output only
#   D-07: Load from existing RDS artifacts
#   D-03 (Phase 02): triggering_code_description column in detail CSV
#   D-04 (Phase 02): triggering_code_descriptions column in episodes CSV (comma-separated, same order)
#   D-05 (Phase 02): Empty string for missing descriptions
#   D-06 (Phase 02): Description columns in CSVs only
#
# Inputs:
#   - cache/outputs/treatment_episodes.rds (episode-level)
#   - cache/outputs/treatment_episode_detail.rds (detail-level)
#   - cache/outputs/code_descriptions.rds (Phase 02: code -> description lookup)
#
# Outputs:
#   - output/gantt_episodes.csv (bars: one row per patient/type/episode)
#   - output/gantt_detail.csv (ticks: one row per patient/date/code)
# =============================================================================


# --- SECTION 1: SETUP AND CONFIGURATION ---

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
})

source("R/00_config.R")

# Input paths: existing RDS artifacts from R/44_treatment_episodes.R
EPISODES_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
DETAIL_RDS   <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds")

# Output paths: CSV files for third-party Gantt chart consumption
OUTPUT_EPISODES <- file.path(CONFIG$output_dir, "gantt_episodes.csv")
OUTPUT_DETAIL   <- file.path(CONFIG$output_dir, "gantt_detail.csv")

# Code description lookup (built by R/48_build_code_descriptions.R)
DESCRIPTIONS_RDS <- file.path(CONFIG$cache$outputs_dir, "code_descriptions.rds")


# --- SECTION 2: LOAD INPUT DATA ---

message("=== Phase 01: Gantt Chart Data Export ===\n")

# Verify RDS artifacts exist before attempting to load
if (!file.exists(EPISODES_RDS)) {
  stop(glue("ERROR: {EPISODES_RDS} not found. Run R/44_treatment_episodes.R first."))
}
if (!file.exists(DETAIL_RDS)) {
  stop(glue("ERROR: {DETAIL_RDS} not found. Run R/44_treatment_episodes.R first."))
}

# Load episode-level data (bars: one row per patient/type/episode)
episodes <- readRDS(EPISODES_RDS)
message(glue("  Loaded {format(nrow(episodes), big.mark = ',')} episode rows"))

# Load detail-level data (ticks: one row per patient/date/code)
detail <- readRDS(DETAIL_RDS)
message(glue("  Loaded {format(nrow(detail), big.mark = ',')} detail rows"))


# --- SECTION 3: VALIDATE COLUMN STRUCTURE ---

# Expected columns per D-01 (episode-level bars table)
expected_episode_cols <- c(
  "patient_id", "treatment_type", "episode_number",
  "episode_start", "episode_stop", "episode_length_days",
  "distinct_dates_in_episode", "historical_flag", "triggering_codes"
)

# Expected columns per D-01 (detail-level ticks table)
expected_detail_cols <- c(
  "patient_id", "treatment_type", "treatment_date", "triggering_code",
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


# --- SECTION 3B: LOAD CODE DESCRIPTIONS (Phase 02) ---

if (!file.exists(DESCRIPTIONS_RDS)) {
  stop(glue("ERROR: {DESCRIPTIONS_RDS} not found. Run R/48_build_code_descriptions.R first."))
}

code_descriptions <- readRDS(DESCRIPTIONS_RDS)
message(glue("  Loaded {format(length(code_descriptions), big.mark = ',')} code descriptions"))


# Helper: map a single code to its description (empty string if missing, per D-05)
lookup_description <- function(code) {
  if (is.na(code) || code == "") return("")
  if (code %in% names(code_descriptions)) return(code_descriptions[[code]])
  return("")
}

# Helper: map comma-separated codes to comma-separated descriptions (per D-04)
# Preserves input order — does NOT sort. Per RESEARCH.md Pitfall 1.
map_codes_to_descriptions <- function(codes_str) {
  if (is.na(codes_str) || codes_str == "") return("")
  codes <- str_split(codes_str, ",")[[1]]
  descriptions <- sapply(codes, lookup_description, USE.NAMES = FALSE)
  paste(descriptions, collapse = ",")
}


# --- SECTION 4: SELECT AND ORDER COLUMNS (per D-01) ---

# Episode-level bars table: 9 original columns + triggering_code_descriptions (per D-04)
episodes_export <- episodes %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, historical_flag, triggering_codes
  ) %>%
  mutate(
    triggering_code_descriptions = sapply(triggering_codes, map_codes_to_descriptions, USE.NAMES = FALSE)
  )

# Detail-level ticks table: 8 original columns + triggering_code_description (per D-03)
detail_export <- detail %>%
  select(
    patient_id, treatment_type, treatment_date, triggering_code,
    episode_number, episode_start, episode_stop, historical_flag
  ) %>%
  mutate(
    triggering_code_description = sapply(triggering_code, lookup_description, USE.NAMES = FALSE)
  )


# --- SECTION 5: WRITE CSV OUTPUTS ---

message("\n--- Writing CSV outputs ---")

write.csv(episodes_export, OUTPUT_EPISODES, row.names = FALSE)
message(glue("  Wrote {OUTPUT_EPISODES} ({format(nrow(episodes_export), big.mark = ',')} rows)"))

write.csv(detail_export, OUTPUT_DETAIL, row.names = FALSE)
message(glue("  Wrote {OUTPUT_DETAIL} ({format(nrow(detail_export), big.mark = ',')} rows)"))


# --- SECTION 6: FINAL SUMMARY ---

message("\n=== Phase 01 Complete ===")
message(glue("  Unique patients in episodes: {format(n_distinct(episodes_export$patient_id), big.mark = ',')}"))
message(glue("  Total episodes: {format(nrow(episodes_export), big.mark = ',')}"))
message(glue("  Total detail rows: {format(nrow(detail_export), big.mark = ',')}"))

# Phase 02 description coverage stats
detail_has_desc <- sum(detail_export$triggering_code_description != "", na.rm = TRUE)
detail_total <- sum(!is.na(detail_export$triggering_code) & detail_export$triggering_code != "", na.rm = TRUE)
message(glue("  Detail rows with descriptions: {format(detail_has_desc, big.mark = ',')} / {format(detail_total, big.mark = ',')} codes"))

message(glue("\n  Episode bars:  {OUTPUT_EPISODES}"))
message(glue("  Detail ticks:  {OUTPUT_DETAIL}"))
