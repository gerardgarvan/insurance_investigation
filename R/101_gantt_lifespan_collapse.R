# ==============================================================================
# 101_gantt_lifespan_collapse.R -- Lifespan Gantt Collapse (Phase 117)
# ==============================================================================
# Purpose:     Collapse the per-episode Gantt export (output/gantt_episodes.csv)
#              into a "lifespan" CSV: one row per patient_id x treatment_type,
#              spanning that patient's earliest episode_start to latest episode_stop
#              for each treatment type (calendar dates preserved -- NOT normalized).
#
#              Multi-value metadata fields are unioned, deduplicated, and sorted
#              into semicolon-separated lists using the same clean_multi_value()
#              behavior as R/52. Death and HL Diagnosis pseudo-rows are excluded.
#
#              Discretion decisions (per Phase 117 CONTEXT.md):
#                - episode_length_days = span in days (max_stop - min_start), NOT
#                  total active days. Span matches "earliest to latest" semantics.
#                - distinct_dates_in_episode = SUM of per-episode distinct-date
#                  counts across all merged episodes.
#                - age_at_episode = age at the earliest episode_start (min-start row).
#                - episode_number collapses away; replaced by episode_count (number
#                  of episodes merged into this lifespan row).
#                - is_hodgkin re-derived from the unioned cancer_category string,
#                  consistent with R/52 derivation logic (D-07).
#
# Inputs:      output/gantt_episodes.csv (produced by R/52_gantt_v2_export.R)
#
# Outputs:     output/gantt_lifespan.csv
#                20 columns: patient_id, treatment_type, episode_start,
#                episode_stop, episode_length_days, episode_count,
#                distinct_dates_in_episode, triggering_codes, drug_names,
#                triggering_code_descriptions, cancer_category, is_hodgkin,
#                drug_group, code_type, source_table, sct_cross_use_flag,
#                episode_dx_codes, episode_dx_categories,
#                episode_dx_7day_confirmed, age_at_episode
#
# Dependencies: R/00_config.R (CONFIG$output_dir)
#               tidyverse ecosystem: dplyr, glue, stringr, lubridate
#
# Requirements: Phase 117 -- LIFESPAN-01, LIFESPAN-02, LIFESPAN-03, LIFESPAN-04
#
# Usage:       Rscript R/101_gantt_lifespan_collapse.R
#              source("R/101_gantt_lifespan_collapse.R")
#
# Note:        Run R/52_gantt_v2_export.R first to produce output/gantt_episodes.csv.
#              This script reads that file directly -- no DuckDB connection required.
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP AND LIBRARIES ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(lubridate)
})

source("R/00_config.R")

message("=== Phase 117: Lifespan Gantt Collapse ===\n")


# ==============================================================================
# SECTION 2: CONSTANTS AND INPUT VALIDATION ----
# ==============================================================================

INPUT_EPISODES  <- file.path(CONFIG$output_dir, "gantt_episodes.csv")
OUTPUT_LIFESPAN <- file.path(CONFIG$output_dir, "gantt_lifespan.csv")

# Defensive check: fail fast if the upstream Gantt export is missing
if (!file.exists(INPUT_EPISODES)) {
  stop(glue(
    "[R/101] Input not found: {INPUT_EPISODES}\n",
    "  Run R/52_gantt_v2_export.R first to produce gantt_episodes.csv."
  ))
}

message(glue("  Input validated: {INPUT_EPISODES}\n"))

# Collapsed output schema -- 20 columns in exact order required
# (episode_number collapses away; replaced by episode_count)
# age_at_episode is the 20th and final column.
LIFESPAN_SCHEMA <- c(
  "patient_id", "treatment_type",
  "episode_start", "episode_stop", "episode_length_days",
  "episode_count", "distinct_dates_in_episode",
  "triggering_codes", "drug_names", "triggering_code_descriptions",
  "cancer_category", "is_hodgkin",
  "drug_group", "code_type", "source_table", "sct_cross_use_flag",
  "episode_dx_codes", "episode_dx_categories", "episode_dx_7day_confirmed",
  "age_at_episode"
)

message(glue("  LIFESPAN_SCHEMA defined: {length(LIFESPAN_SCHEMA)} columns\n"))


# ==============================================================================
# SECTION 3: HELPER FUNCTIONS ----
# ==============================================================================

# clean_multi_value() -- copied verbatim from R/52_gantt_v2_export.R lines 772-786.
# Standalone copy is acceptable and documented here because R/52 does not export it.
# Behavior: dedup, drop blanks, sort, join with sep_out.
# D-07: reuses R/52's exact sort(unique()) behavior for multi-value field collapsing.
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

# union_field() -- group-level helper for ALREADY semicolon-separated fields.
# When collapsing a group of rows, we first paste all values together with ";",
# then call clean_multi_value(..., sep_in = ";") to union+dedup+sort.
# This correctly handles the fact that gantt_episodes.csv multi-value fields are
# already semicolon-separated (each cell may contain multiple ";"-joined values).
union_field <- function(x) {
  clean_multi_value(paste(x, collapse = ";"), sep_in = ";", sep_out = ";")
}


# ==============================================================================
# SECTION 4: LOAD AND PREPARE EPISODE DATA ----
# ==============================================================================

message("--- Loading gantt_episodes.csv ---")

# Read as character to avoid date/NA coercion surprises; parse types explicitly.
episodes_raw <- read.csv(INPUT_EPISODES, stringsAsFactors = FALSE, colClasses = "character")

message(glue("  Loaded: {format(nrow(episodes_raw), big.mark = ',')} rows, {ncol(episodes_raw)} columns"))

# Parse dates and coerce numerics explicitly
episodes <- episodes_raw %>%
  mutate(
    episode_start             = ymd(episode_start),
    episode_stop              = ymd(episode_stop),
    distinct_dates_in_episode = as.integer(distinct_dates_in_episode),
    age_at_episode            = suppressWarnings(as.integer(age_at_episode))
  )

message(glue(
  "  Date range: {min(episodes$episode_start, na.rm = TRUE)} -- ",
  "{max(episodes$episode_stop, na.rm = TRUE)}"
))


# ==============================================================================
# SECTION 5: EXCLUDE PSEUDO-ROWS (D-08) ----
# ==============================================================================

# D-08: Real treatment types only. Exclude Death and HL Diagnosis pseudo-rows.
# These carry event dates/metadata but are not collapsible treatment bars.
n_before_exclusion <- nrow(episodes)

episodes <- episodes %>%
  filter(!treatment_type %in% c("Death", "HL Diagnosis"))

n_excluded <- n_before_exclusion - nrow(episodes)

message(glue(
  "\n--- Pseudo-row exclusion (D-08) ---\n",
  "  Before: {format(n_before_exclusion, big.mark = ',')} rows\n",
  "  Excluded (Death + HL Diagnosis): {format(n_excluded, big.mark = ',')}\n",
  "  After:  {format(nrow(episodes), big.mark = ',')} rows"
))

# Defensive: confirm no pseudo-rows remain
stopifnot(!any(episodes$treatment_type %in% c("Death", "HL Diagnosis")))


# ==============================================================================
# SECTION 6: COLLAPSE TO LIFESPAN GRAIN ----
# ==============================================================================

# D-03 / D-04: Collapse grain is one row per patient_id x treatment_type.
# D-05: Collapsed bar spans min(episode_start) -> max(episode_stop).
# D-06: treatment_type is the ONLY grouping dimension beyond patient_id.
#       cancer_category, is_hodgkin, 7-day status stay as merged attributes.
# D-07: Multi-value fields unioned via union_field() -> clean_multi_value().

message("\n--- Collapsing to lifespan grain (patient_id x treatment_type) ---")

lifespan <- episodes %>%
  group_by(patient_id, treatment_type) %>%
  summarise(
    # D-05: Span = earliest start -> latest stop (NOT total active days)
    episode_start   = min(episode_start, na.rm = TRUE),
    episode_stop    = max(episode_stop,  na.rm = TRUE),

    # episode_number collapses away; replaced by count of merged episodes
    episode_count   = dplyr::n(),

    # distinct_dates_in_episode: SUM of per-episode distinct-date counts
    # across all merged episodes (cumulative distinct-date coverage)
    distinct_dates_in_episode = sum(distinct_dates_in_episode, na.rm = TRUE),

    # Multi-value fields: union, dedup, sort (D-07, reuses R/52 behavior)
    triggering_codes             = union_field(triggering_codes),
    drug_names                   = union_field(drug_names),
    triggering_code_descriptions = union_field(triggering_code_descriptions),
    cancer_category              = union_field(cancer_category),
    drug_group                   = union_field(drug_group),
    code_type                    = union_field(code_type),
    source_table                 = union_field(source_table),
    sct_cross_use_flag           = union_field(sct_cross_use_flag),
    episode_dx_codes             = union_field(episode_dx_codes),
    episode_dx_categories        = union_field(episode_dx_categories),
    episode_dx_7day_confirmed    = union_field(episode_dx_7day_confirmed),

    # age_at_episode: age at the EARLIEST episode_start (min-start row)
    age_at_episode = age_at_episode[which.min(episode_start)],

    .groups = "drop"
  ) %>%
  mutate(
    # episode_length_days = span in days (max_stop - min_start)
    # This is the SPAN of the treatment lifespan bar, not total active days.
    episode_length_days = as.integer(episode_stop - episode_start),

    # is_hodgkin re-derived from the unioned cancer_category (D-07, consistent
    # with R/52 line 857 derivation: Hodgkin AND NOT Non-Hodgkin)
    is_hodgkin = str_detect(cancer_category, "Hodgkin") &
      !str_detect(cancer_category, "Non-Hodgkin")
  )

message(glue(
  "  Collapsed: {format(nrow(lifespan), big.mark = ',')} lifespan rows\n",
  "  Unique patients:         {format(n_distinct(lifespan$patient_id), big.mark = ',')}\n",
  "  Unique treatment types:  {format(n_distinct(lifespan$treatment_type), big.mark = ',')}"
))


# ==============================================================================
# SECTION 7: COLUMN ORDER, NA CLEANUP, SCHEMA VERIFY, WRITE ----
# ==============================================================================

message("\n--- Column ordering, NA cleanup, schema verification, write ---")

# Convert dates back to "YYYY-MM-DD" character strings for CSV export
lifespan <- lifespan %>%
  mutate(
    episode_start = format(episode_start, "%Y-%m-%d"),
    episode_stop  = format(episode_stop,  "%Y-%m-%d")
  )

# Select columns in exact LIFESPAN_SCHEMA order (all 20 columns)
lifespan_export <- lifespan %>%
  select(all_of(LIFESPAN_SCHEMA))

# NA -> empty string for all character columns (Tableau CSV convention: no NA literals)
# Mirror R/52 lines 838-839: empty string, not NA, in every character cell
lifespan_export <- lifespan_export %>%
  mutate(across(where(is.character), ~ ifelse(is.na(.) | . == "NA", "", .)))

# Dynamic schema verification (mirror R/52 lines 900-905, D-13)
if (!identical(colnames(lifespan_export), LIFESPAN_SCHEMA)) {
  missing_cols <- setdiff(LIFESPAN_SCHEMA, colnames(lifespan_export))
  extra_cols   <- setdiff(colnames(lifespan_export), LIFESPAN_SCHEMA)
  stop(glue(
    "Lifespan schema mismatch: ",
    "missing=[{paste(missing_cols, collapse = ', ')}], ",
    "extra=[{paste(extra_cols, collapse = ', ')}]"
  ))
}

message("  Schema verification: PASSED (20 columns, exact order)")

# Write CSV (D-01: data export only -- no in-R chart rendering)
# D-02: row.names = FALSE, na = "" (Tableau CSV convention)
write.csv(lifespan_export, OUTPUT_LIFESPAN, row.names = FALSE, na = "")

message(glue("  Wrote: {OUTPUT_LIFESPAN}"))


# ==============================================================================
# SECTION 8: FINAL SUMMARY ----
# ==============================================================================

n_rows        <- nrow(lifespan_export)
n_patients    <- n_distinct(lifespan_export$patient_id)
n_tx_types    <- n_distinct(lifespan_export$treatment_type)
n_pseudo_rows <- sum(lifespan_export$treatment_type %in% c("Death", "HL Diagnosis"))

message(glue("\n--- Lifespan export summary ---"))
message(glue("  Rows written:            {format(n_rows, big.mark = ',')}"))
message(glue("  Unique patients:         {format(n_patients, big.mark = ',')}"))
message(glue("  Unique treatment types:  {format(n_tx_types, big.mark = ',')}"))
message(glue("  Pseudo-rows in output:   {n_pseudo_rows} (must be 0)"))

if (n_pseudo_rows > 0) {
  warning(glue(
    "[R/101] Pseudo-rows found in output (Death / HL Diagnosis): {n_pseudo_rows}. ",
    "Check SECTION 5 exclusion logic."
  ))
}

message(glue(
  "\n  Output: {OUTPUT_LIFESPAN}\n",
  "  Schema: {length(LIFESPAN_SCHEMA)} columns (LIFESPAN_SCHEMA verified)\n",
  "  Treatment types present: {paste(sort(unique(lifespan_export$treatment_type)), collapse = ', ')}"
))

message("\nDone. (Phase 117 -- LIFESPAN-01 through LIFESPAN-04)")
