# ==============================================================================
# FLM Duplicate Date Investigation (Phase 20)
# ==============================================================================
# Standalone diagnostic script -- not part of the main pipeline sequence.
# Investigates whether FLM-sourced patients have duplicate ENCOUNTER rows on
# the same date from multiple data sources. Quantifies duplication, compares
# payer completeness across sources, and recommends preferred source.
#
# Decisions: D-01 to D-18 from 20-CONTEXT.md
# Requirements: FLMDUP-01, FLMDUP-02, FLMDUP-03, FLMDUP-04
#
# Usage: source("R/19_flm_duplicate_dates.R")
# ==============================================================================

source("R/00_config.R")
library(dplyr)
library(lubridate)
library(glue)
library(readr)
library(stringr)
library(janitor)
library(tidyr)

# Load tables if not already loaded
if (!exists("pcornet")) source("R/01_load_pcornet.R")

# ==============================================================================
# Missingness Definition (Phase 19 pattern, D-10)
# ==============================================================================
# Missing = NA, empty string, NI, UN, OT, 99, 9999
is_missing_payer <- function(payer_value) {
  is.na(payer_value) |
    nchar(trimws(payer_value)) == 0 |
    payer_value %in% c("NI", "UN", "OT", "99", "9999")
}

# ==============================================================================
# SECTION 1: Identify FLM patients (D-05, D-06)
# ==============================================================================
# D-06: ALL FLM patients from DEMOGRAPHIC, not just HL cohort members

message(glue("\n{strrep('=', 60)}"))
message("FLM DUPLICATE DATE INVESTIGATION")
message(glue("{strrep('=', 60)}\n"))

flm_patient_ids <- pcornet$DEMOGRAPHIC %>%
  filter(SOURCE == "FLM") %>%
  pull(ID) %>%
  unique()

message(glue("FLM patients in DEMOGRAPHIC: {format(length(flm_patient_ids), big.mark=',')}"))

# ==============================================================================
# SECTION 2: Filter ENCOUNTER to FLM patients (D-07, D-09, D-10)
# ==============================================================================
# D-07: ENCOUNTER table only -- do not touch DIAGNOSIS, PROCEDURES, etc.

message(glue("\n--- SECTION 2: Filter ENCOUNTER to FLM Patients ---"))

flm_encounters <- pcornet$ENCOUNTER %>%
  filter(ID %in% flm_patient_ids)

message(glue("FLM encounters: {format(nrow(flm_encounters), big.mark=',')}"))

# Check NA count for ENCOUNTER.SOURCE (Pitfall 2)
n_na_source <- sum(is.na(flm_encounters$SOURCE))
pct_na_source <- round(100 * n_na_source / nrow(flm_encounters), 1)
message(glue("ENCOUNTER.SOURCE NA count: {format(n_na_source, big.mark=',')} ({pct_na_source}%)"))

if (pct_na_source > 5) {
  message(glue("  ** WARNING: >{5}% of FLM encounters have NA SOURCE -- may affect multi-source analysis"))
}

# Log unique ENCOUNTER.SOURCE values
enc_sources <- sort(unique(na.omit(flm_encounters$SOURCE)))
message(glue("ENCOUNTER.SOURCE values: {paste(enc_sources, collapse=', ')}"))

# ==============================================================================
# SECTION 3: Detect same-date duplicates on ADMIT_DATE (D-01, D-03, FLMDUP-01)
# ==============================================================================
# D-01: Group by ID + date only (not ENC_TYPE)
# D-03: Check ADMIT_DATE (primary) and DISCHARGE_DATE (secondary)

message(glue("\n--- SECTION 3: Same-Date Duplicate Detection ---"))

# Parse dates -- ENCOUNTER columns are all col_character()
# Try standard ISO format first, fall back to parse_pcornet_date if needed
flm_encounters <- flm_encounters %>%
  mutate(
    admit_date_parsed = as.Date(ADMIT_DATE, format = "%Y-%m-%d"),
    discharge_date_parsed = as.Date(DISCHARGE_DATE, format = "%Y-%m-%d")
  )

# Check if standard format parsing succeeded
n_admit_raw <- sum(!is.na(flm_encounters$ADMIT_DATE) & nchar(trimws(flm_encounters$ADMIT_DATE)) > 0)
n_admit_parsed <- sum(!is.na(flm_encounters$admit_date_parsed))
admit_parse_rate <- if (n_admit_raw > 0) round(100 * n_admit_parsed / n_admit_raw, 1) else 100

if (n_admit_raw > 0 && admit_parse_rate < 50) {
  message(glue("  Standard date parse rate only {admit_parse_rate}% -- trying parse_pcornet_date()"))
  if (file.exists("R/utils_dates.R")) {
    source("R/utils_dates.R")
    flm_encounters <- flm_encounters %>%
      mutate(
        admit_date_parsed = parse_pcornet_date(ADMIT_DATE),
        discharge_date_parsed = parse_pcornet_date(DISCHARGE_DATE)
      )
    n_admit_parsed <- sum(!is.na(flm_encounters$admit_date_parsed))
    message(glue("  After parse_pcornet_date: {format(n_admit_parsed, big.mark=',')} parsed"))
  } else {
    message("  utils_dates.R not found -- continuing with standard parsing")
  }
}

n_no_admit_date <- sum(is.na(flm_encounters$admit_date_parsed))
message(glue("ADMIT_DATE parsed: {format(n_admit_parsed, big.mark=',')} of {format(n_admit_raw, big.mark=',')} non-empty values"))
message(glue("ADMIT_DATE NA after parsing: {format(n_no_admit_date, big.mark=',')}"))

# --- ADMIT_DATE same-date duplicates ---
admit_date_dupes <- flm_encounters %>%
  filter(!is.na(admit_date_parsed)) %>%
  add_count(ID, admit_date_parsed, name = "n_encounters_same_date") %>%
  filter(n_encounters_same_date > 1) %>%
  arrange(ID, admit_date_parsed, SOURCE)

n_dupe_rows <- nrow(admit_date_dupes)
n_dupe_patient_dates <- admit_date_dupes %>%
  distinct(ID, admit_date_parsed) %>%
  nrow()
n_dupe_patients <- n_distinct(admit_date_dupes$ID)

message(glue("\nADMIT_DATE same-date duplicates:"))
message(glue("  Duplicate encounter rows: {format(n_dupe_rows, big.mark=',')}"))
message(glue("  Unique patient-dates with duplicates: {format(n_dupe_patient_dates, big.mark=',')}"))
message(glue("  Unique patients with at least one duplicate date: {format(n_dupe_patients, big.mark=',')}"))

# --- DISCHARGE_DATE same-date duplicates (D-03, secondary analysis) ---
discharge_date_dupes <- flm_encounters %>%
  filter(!is.na(discharge_date_parsed)) %>%
  add_count(ID, discharge_date_parsed, name = "n_encounters_same_date") %>%
  filter(n_encounters_same_date > 1)

n_discharge_dupe_patient_dates <- discharge_date_dupes %>%
  distinct(ID, discharge_date_parsed) %>%
  nrow()

message(glue("\nDISCHARGE_DATE same-date duplicates:"))
message(glue("  Patient-dates with duplicates: {format(n_discharge_dupe_patient_dates, big.mark=',')}"))

if (n_discharge_dupe_patient_dates < 100) {
  message("  (Low count -- DISCHARGE_DATE duplicates are minimal, skipping detailed analysis)")
}

# ==============================================================================
# SECTION 4: Detect exact row duplicates (D-02, FLMDUP-01)
# ==============================================================================

message(glue("\n--- SECTION 4: Exact Row Duplicate Detection ---"))

# Exact row duplicates (all original columns, excluding parsed date columns)
exact_dupes <- flm_encounters %>%
  select(-admit_date_parsed, -discharge_date_parsed) %>%
  get_dupes()

if (nrow(exact_dupes) > 0) {
  n_exact_patients <- n_distinct(exact_dupes$ID)
  message(glue("Exact row duplicates: {format(nrow(exact_dupes), big.mark=',')} rows ({n_exact_patients} patients)"))
} else {
  message("No exact row duplicates found")
}

# Near-exact duplicates (same on all columns except ENCOUNTERID)
near_exact_dupes <- flm_encounters %>%
  select(-admit_date_parsed, -discharge_date_parsed, -ENCOUNTERID) %>%
  get_dupes()

if (nrow(near_exact_dupes) > 0) {
  n_near_exact_patients <- n_distinct(near_exact_dupes$ID)
  message(glue("Near-exact duplicates (excl. ENCOUNTERID): {format(nrow(near_exact_dupes), big.mark=',')} rows ({n_near_exact_patients} patients)"))
} else {
  message("No near-exact duplicates found (excluding ENCOUNTERID)")
}

# ==============================================================================
# SECTION 5: Identify multi-source dates (D-04, FLMDUP-02)
# ==============================================================================

message(glue("\n--- SECTION 5: Multi-Source Date Identification ---"))

# Per-patient-date summary from admit date duplicates
patient_date_summary <- admit_date_dupes %>%
  group_by(ID, admit_date_parsed) %>%
  summarize(
    n_encounters = n(),
    n_sources = n_distinct(SOURCE, na.rm = TRUE),
    sources = paste(sort(unique(na.omit(SOURCE))), collapse = ", "),
    enc_types = paste(sort(unique(na.omit(ENC_TYPE))), collapse = ", "),
    n_enc_types = n_distinct(ENC_TYPE, na.rm = TRUE),
    .groups = "drop"
  )

multi_source_dates <- patient_date_summary %>%
  filter(n_sources > 1)

message(glue("Total patient-dates with duplicates: {format(nrow(patient_date_summary), big.mark=',')}"))
message(glue("Patient-dates with multiple SOURCEs: {format(nrow(multi_source_dates), big.mark=',')}"))

# Breakdown: same-source vs multi-source (Pitfall 3)
same_source_dates <- patient_date_summary %>%
  filter(n_sources <= 1)

message(glue("\nBreakdown of duplicate patient-dates:"))
message(glue("  Same-source duplicates: {format(nrow(same_source_dates), big.mark=',')}"))
message(glue("  Multi-source duplicates: {format(nrow(multi_source_dates), big.mark=',')}"))

# Within same-source: same ENC_TYPE vs different ENC_TYPE
if (nrow(same_source_dates) > 0) {
  same_source_same_enc <- same_source_dates %>%
    filter(n_enc_types == 1) %>%
    nrow()
  same_source_diff_enc <- same_source_dates %>%
    filter(n_enc_types > 1) %>%
    nrow()
  message(glue("  Same-source, same ENC_TYPE (potential true duplication): {format(same_source_same_enc, big.mark=',')}"))
  message(glue("  Same-source, different ENC_TYPE (clinically valid): {format(same_source_diff_enc, big.mark=',')}"))
}

# Most common source combinations for multi-source dates
if (nrow(multi_source_dates) > 0) {
  source_combos <- multi_source_dates %>%
    count(sources, sort = TRUE) %>%
    head(10)
  message(glue("\nMost common multi-source combinations:"))
  for (i in seq_len(nrow(source_combos))) {
    message(glue("  {source_combos$sources[i]}: {format(source_combos$n[i], big.mark=',')} patient-dates"))
  }
}

# ==============================================================================
# SECTION 6: Payer completeness comparison (D-08, D-09, D-10, D-11, FLMDUP-03)
# ==============================================================================

message(glue("\n--- SECTION 6: Payer Completeness Comparison Across Sources ---"))

# Get actual encounter rows for multi-source dates
multi_source_encounters <- admit_date_dupes %>%
  semi_join(multi_source_dates, by = c("ID", "admit_date_parsed"))

if (nrow(multi_source_encounters) == 0) {
  message("No multi-source dates found -- skipping payer completeness comparison")
  # Create empty source_completeness for downstream CSV generation
  source_completeness <- tibble(
    SOURCE = character(),
    n_encounters = integer(),
    n_primary_present = integer(),
    pct_primary_present = double(),
    n_secondary_present = integer(),
    pct_secondary_present = double(),
    n_both_present = integer(),
    pct_both_present = double(),
    n_either_present = integer(),
    pct_either_present = double()
  )
} else {
  message(glue("Multi-source encounter rows: {format(nrow(multi_source_encounters), big.mark=',')}"))

  # Per-source payer completeness
  source_completeness <- multi_source_encounters %>%
    filter(!is.na(SOURCE)) %>%
    group_by(SOURCE) %>%
    summarize(
      n_encounters = n(),
      n_primary_present = sum(!is_missing_payer(PAYER_TYPE_PRIMARY)),
      pct_primary_present = round(100 * n_primary_present / n_encounters, 1),
      n_secondary_present = sum(!is_missing_payer(PAYER_TYPE_SECONDARY)),
      pct_secondary_present = round(100 * n_secondary_present / n_encounters, 1),
      n_both_present = sum(!is_missing_payer(PAYER_TYPE_PRIMARY) & !is_missing_payer(PAYER_TYPE_SECONDARY)),
      pct_both_present = round(100 * n_both_present / n_encounters, 1),
      n_either_present = sum(!is_missing_payer(PAYER_TYPE_PRIMARY) | !is_missing_payer(PAYER_TYPE_SECONDARY)),
      pct_either_present = round(100 * n_either_present / n_encounters, 1),
      .groups = "drop"
    ) %>%
    arrange(desc(pct_primary_present))

  # Log per-source completeness
  message(glue("\nPayer completeness by SOURCE (multi-source encounters only):"))
  for (i in seq_len(nrow(source_completeness))) {
    row <- source_completeness[i, ]
    message(glue("  SOURCE={row$SOURCE}: {row$n_encounters} encounters | Primary: {row$pct_primary_present}% | Secondary: {row$pct_secondary_present}% | Either: {row$pct_either_present}%"))
  }

  # Supplementary: per-source per-ENC_TYPE completeness (Pitfall 5)
  source_enctype_completeness <- multi_source_encounters %>%
    filter(!is.na(SOURCE)) %>%
    group_by(SOURCE, ENC_TYPE) %>%
    summarize(
      n_encounters = n(),
      pct_primary_present = round(100 * mean(!is_missing_payer(PAYER_TYPE_PRIMARY)), 1),
      .groups = "drop"
    ) %>%
    arrange(SOURCE, desc(n_encounters))

  # Log ENC_TYPE distribution caveat
  enc_type_dist <- multi_source_encounters %>%
    filter(!is.na(SOURCE)) %>%
    count(SOURCE, ENC_TYPE) %>%
    group_by(SOURCE) %>%
    mutate(pct = round(100 * n / sum(n), 1)) %>%
    ungroup()

  message(glue("\nENC_TYPE distribution by SOURCE (multi-source encounters):"))
  for (src in unique(enc_type_dist$SOURCE)) {
    src_rows <- enc_type_dist %>% filter(SOURCE == src) %>% arrange(desc(n))
    types_str <- paste(glue("{src_rows$ENC_TYPE}({src_rows$pct}%)"), collapse = ", ")
    message(glue("  {src}: {types_str}"))
  }

  # Generate recommendation (D-14)
  if (nrow(source_completeness) >= 2) {
    best_source <- source_completeness$SOURCE[1]
    best_pct <- source_completeness$pct_primary_present[1]
    second_source <- source_completeness$SOURCE[2]
    second_pct <- source_completeness$pct_primary_present[2]

    message(glue("\nRECOMMENDATION: Prefer SOURCE='{best_source}' for payer data when duplicates exist"))
    message(glue("  Primary payer completeness: {best_pct}% vs {second_source} at {second_pct}%"))
  } else if (nrow(source_completeness) == 1) {
    message(glue("\nRECOMMENDATION: Only one source ({source_completeness$SOURCE[1]}) found in multi-source encounters -- recommendation is trivial"))
  }
}

# ==============================================================================
# SECTION 7: Build and write CSV outputs (D-15, D-16, D-17, FLMDUP-04)
# ==============================================================================

message(glue("\n--- SECTION 7: Writing CSV Outputs ---"))

output_dir <- file.path(CONFIG$output_dir, "tables")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# --- CSV 1: Patient-level duplicate summary ---
# Pre-compute per patient-date
patient_date_stats <- flm_encounters %>%
  filter(!is.na(admit_date_parsed)) %>%
  group_by(ID, admit_date_parsed) %>%
  summarize(
    n_enc_this_date = n(),
    n_sources_this_date = n_distinct(SOURCE, na.rm = TRUE),
    .groups = "drop"
  )

patient_summary <- patient_date_stats %>%
  group_by(ID) %>%
  summarize(
    n_unique_dates = n(),
    n_total_encounters = sum(n_enc_this_date),
    n_duplicate_dates = sum(n_enc_this_date > 1),
    n_multi_source_dates = sum(n_sources_this_date > 1),
    .groups = "drop"
  )

# Add per-patient payer completeness and source info
patient_payer <- flm_encounters %>%
  filter(!is.na(admit_date_parsed)) %>%
  group_by(ID) %>%
  summarize(
    sources_in_encounters = paste(sort(unique(na.omit(SOURCE))), collapse = ", "),
    pct_primary_present = round(100 * mean(!is_missing_payer(PAYER_TYPE_PRIMARY)), 1),
    pct_secondary_present = round(100 * mean(!is_missing_payer(PAYER_TYPE_SECONDARY)), 1),
    .groups = "drop"
  )

patient_summary <- patient_summary %>%
  left_join(patient_payer, by = "ID") %>%
  arrange(desc(n_multi_source_dates), desc(n_duplicate_dates))

write_csv(patient_summary, file.path(output_dir, "flm_patient_duplicate_summary.csv"))
message(glue("  Written: flm_patient_duplicate_summary.csv ({format(nrow(patient_summary), big.mark=',')} patients)"))

# --- CSV 2: Date-level detail for multi-source encounters ---
if (nrow(multi_source_encounters) > 0) {
  date_detail <- multi_source_encounters %>%
    select(ID, admit_date_parsed, SOURCE, ENC_TYPE, ENCOUNTERID,
           ADMIT_TIME, DISCHARGE_DATE, DISCHARGE_TIME,
           PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY) %>%
    mutate(
      primary_missing = is_missing_payer(PAYER_TYPE_PRIMARY),
      secondary_missing = is_missing_payer(PAYER_TYPE_SECONDARY)
    ) %>%
    arrange(ID, admit_date_parsed, SOURCE)
} else {
  # Write empty data frame with expected columns
  date_detail <- tibble(
    ID = character(),
    admit_date_parsed = as.Date(character()),
    SOURCE = character(),
    ENC_TYPE = character(),
    ENCOUNTERID = character(),
    ADMIT_TIME = character(),
    DISCHARGE_DATE = character(),
    DISCHARGE_TIME = character(),
    PAYER_TYPE_PRIMARY = character(),
    PAYER_TYPE_SECONDARY = character(),
    primary_missing = logical(),
    secondary_missing = logical()
  )
  message("  (No multi-source encounters -- writing empty date detail file)")
}

write_csv(date_detail, file.path(output_dir, "flm_date_level_duplicate_detail.csv"))
message(glue("  Written: flm_date_level_duplicate_detail.csv ({format(nrow(date_detail), big.mark=',')} rows)"))

# --- CSV 3: Aggregate summary ---
aggregate_summary <- tibble(
  metric = c(
    "Total FLM patients (DEMOGRAPHIC)",
    "Total FLM encounters",
    "FLM encounters with valid ADMIT_DATE",
    "Encounters with NA ADMIT_DATE",
    "Encounters with NA ENCOUNTER.SOURCE",
    "Unique patient-dates",
    "Patient-dates with same-date duplicates",
    "Patient-dates with multiple SOURCEs",
    "Exact row duplicates (all columns)",
    "Near-exact duplicates (all except ENCOUNTERID)",
    "DISCHARGE_DATE same-date duplicate patient-dates"
  ),
  value = c(
    length(flm_patient_ids),
    nrow(flm_encounters),
    sum(!is.na(flm_encounters$admit_date_parsed)),
    n_no_admit_date,
    n_na_source,
    nrow(patient_date_stats),
    sum(patient_date_stats$n_enc_this_date > 1),
    nrow(multi_source_dates),
    nrow(exact_dupes),
    nrow(near_exact_dupes),
    n_distinct(paste(discharge_date_dupes$ID, discharge_date_dupes$discharge_date_parsed))
  )
)

# Append source completeness rows if multi-source encounters exist
if (nrow(source_completeness) > 0) {
  source_rows <- source_completeness %>%
    mutate(
      metric = glue("SOURCE={SOURCE}: primary payer present %"),
      value = pct_primary_present
    ) %>%
    select(metric, value)
  aggregate_summary <- bind_rows(aggregate_summary, source_rows)
}

write_csv(aggregate_summary, file.path(output_dir, "flm_duplicate_aggregate_summary.csv"))
message(glue("  Written: flm_duplicate_aggregate_summary.csv ({nrow(aggregate_summary)} metrics)"))

# Also write source completeness as a separate CSV if available
if (nrow(source_completeness) > 0) {
  write_csv(source_completeness, file.path(output_dir, "flm_source_payer_completeness.csv"))
  message(glue("  Written: flm_source_payer_completeness.csv ({nrow(source_completeness)} sources)"))
}

# ==============================================================================
# SECTION 8: Console summary (D-18)
# ==============================================================================

message(glue("\n{strrep('=', 60)}"))
message("FLM DUPLICATE DATE INVESTIGATION -- SUMMARY")
message(glue("{strrep('=', 60)}"))

total_patient_dates <- nrow(patient_date_stats)
dupe_patient_dates <- sum(patient_date_stats$n_enc_this_date > 1)
dupe_rate <- if (total_patient_dates > 0) round(100 * dupe_patient_dates / total_patient_dates, 2) else 0
multi_source_rate <- if (dupe_patient_dates > 0) round(100 * nrow(multi_source_dates) / dupe_patient_dates, 2) else 0

message(glue("\nFLM patients: {format(length(flm_patient_ids), big.mark=',')}"))
message(glue("FLM encounters: {format(nrow(flm_encounters), big.mark=',')}"))
message(glue("Unique patient-dates: {format(total_patient_dates, big.mark=',')}"))
message(glue("\nADMIT_DATE duplicate rate: {format(dupe_patient_dates, big.mark=',')} / {format(total_patient_dates, big.mark=',')} patient-dates ({dupe_rate}%)"))
message(glue("Multi-source rate (of duplicates): {format(nrow(multi_source_dates), big.mark=',')} / {format(dupe_patient_dates, big.mark=',')} ({multi_source_rate}%)"))
message(glue("Exact row duplicates: {format(nrow(exact_dupes), big.mark=',')}"))
message(glue("DISCHARGE_DATE duplicate patient-dates: {format(n_discharge_dupe_patient_dates, big.mark=',')}"))

# Source completeness summary
if (nrow(source_completeness) > 0) {
  message(glue("\nSource payer completeness (multi-source encounters):"))
  for (i in seq_len(nrow(source_completeness))) {
    row <- source_completeness[i, ]
    message(glue("  {row$SOURCE}: Primary={row$pct_primary_present}%, Secondary={row$pct_secondary_present}%, Either={row$pct_either_present}%"))
  }

  if (nrow(source_completeness) >= 2) {
    message(glue("\nRECOMMENDATION: Prefer SOURCE='{source_completeness$SOURCE[1]}' when resolving duplicate-date encounters"))
  }
}

message(glue("\nCSV files written to {output_dir}/:"))
message("  - flm_patient_duplicate_summary.csv")
message("  - flm_date_level_duplicate_detail.csv")
message("  - flm_duplicate_aggregate_summary.csv")
if (nrow(source_completeness) > 0) {
  message("  - flm_source_payer_completeness.csv")
}

message(glue("\n{strrep('=', 60)}"))
message("END OF FLM DUPLICATE DATE INVESTIGATION")
message(glue("{strrep('=', 60)}"))
