# ==============================================================================
# 69_per_patient_source_detection.R -- Per-patient source detection by date
# ==============================================================================
#
# Purpose: Per-patient source detection by date: identifies which ENCOUNTER.SOURCE
#   values are present for each patient on each date.
#
# Inputs:
#   - get_pcornet_table("ENCOUNTER"): ID, ENCOUNTERID, ADMIT_DATE, SOURCE
#
# Outputs: 3 CSV files in output/tables/:
#   - patient_date_source_detail.csv (one row per patient-date with source_combo)
#   - source_combo_frequencies.csv (combo frequency summary)
#   - per_source_summary.csv (per-source encounter/patient counts)
#
# Dependencies: Sources R/00_config.R. Uses data.table for performance.
#
# Requirements: PDSRC-01 through PDSRC-05 (Phase 28).
#
# Standalone script -- NOT part of the main pipeline sequence.
# ==============================================================================

# ==============================================================================
# SECTION 1: Setup ----
# ==============================================================================
# WHY per-patient-per-date granularity:
#   - Enables downstream analysis to identify patients seen at multiple facilities
#     on the same date (multi-source dates)
#   - Relevant for payer assignment when sources disagree on same date
#   - Simpler than pairwise overlap approach (R/67-68) -- just enumerate sources per date
#   - data.table used for performance (large ENCOUNTER table grouping operations)

source("R/00_config.R")
library(data.table)
library(glue)
library(readr)

# Load tables if not already loaded (RDS mode)
if (!USE_DUCKDB && !exists("pcornet")) source("R/01_load_pcornet.R")
# DuckDB mode: open connection if needed
if (USE_DUCKDB && !exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}

# ==============================================================================
# SECTION 2: Load and Prepare Encounters ----
# ==============================================================================

message(glue("\n{strrep('=', 70)}"))
message("PER-PATIENT SOURCE DETECTION BY DATE")
message("Phase 28: Per-date source enumeration using data.table")
message(glue("{strrep('=', 70)}\n"))

message("--- SECTION 2: Load and Prepare Encounters ---")

# Load ENCOUNTER table
# Phase 32: Use get_pcornet_table() then materialize before data.table conversion
enc <- get_pcornet_table("ENCOUNTER") %>% materialize()

# Convert to data.table (data.table retained as documented exception -- see header)
enc_dt <- as.data.table(enc)

# Log table dimensions
total_encounters <- nrow(enc_dt)
total_patients <- enc_dt[, uniqueN(ID)]
message(glue("Total encounters loaded: {format(total_encounters, big.mark=',')}"))
message(glue("Total unique patients: {format(total_patients, big.mark=',')}"))

# Log unique ENCOUNTER.SOURCE values
enc_sources <- sort(unique(na.omit(enc_dt$SOURCE)))
message(glue("Unique ENCOUNTER.SOURCE values: {paste(enc_sources, collapse=', ')}"))
message(glue("Encounters with NA SOURCE: {format(sum(is.na(enc_dt$SOURCE)), big.mark=',')}"))

# Parse ADMIT_DATE
enc_dt[, admit_date_parsed := as.Date(ADMIT_DATE, format = "%Y-%m-%d")]

n_admit_raw <- sum(!is.na(enc_dt$ADMIT_DATE) & enc_dt$ADMIT_DATE != "")
n_admit_parsed <- sum(!is.na(enc_dt$admit_date_parsed))
admit_parse_rate <- if (n_admit_raw > 0) round(100 * n_admit_parsed / n_admit_raw, 1) else 100

if (n_admit_raw > 0 && admit_parse_rate < 50) {
  message(glue("  Standard date parse rate only {admit_parse_rate}% -- trying parse_pcornet_date()"))
  if (file.exists("R/utils/utils_dates.R")) {
    source("R/utils/utils_dates.R")
    enc_dt[, admit_date_parsed := parse_pcornet_date(ADMIT_DATE)]
    n_admit_parsed <- sum(!is.na(enc_dt$admit_date_parsed))
    admit_parse_rate <- if (n_admit_raw > 0) round(100 * n_admit_parsed / n_admit_raw, 1) else 100
    message(glue("  After parse_pcornet_date: {format(n_admit_parsed, big.mark=',')} parsed"))
  } else {
    message("  utils_dates.R not found -- continuing with standard parsing")
  }
}

message(glue("ADMIT_DATE parse rate: {admit_parse_rate}% ({format(n_admit_parsed, big.mark=',')} of {format(n_admit_raw, big.mark=',')} non-empty values)"))

# Overwrite ADMIT_DATE with parsed date and drop temp column
enc_dt[, ADMIT_DATE := admit_date_parsed]
enc_dt[, admit_date_parsed := NULL]

# Filter to valid rows
enc_dt <- enc_dt[!is.na(ADMIT_DATE) & !is.na(SOURCE)]
message(glue("Encounters with valid ADMIT_DATE and SOURCE: {format(nrow(enc_dt), big.mark=',')}"))

# ==============================================================================
# SECTION 3: Per-Patient-Date Source Enumeration (PDSRC-01) ----
# ==============================================================================

message(glue("\n--- SECTION 3: Per-Patient-Date Source Enumeration (PDSRC-01) ---"))

# Per D-01, include ALL dates (1+ sources), not just multi-source dates
patient_date_detail <- enc_dt[, .(
  n_sources    = uniqueN(SOURCE),
  source_combo = paste(sort(unique(SOURCE)), collapse = "+"),
  n_encounters = .N
), by = .(ID, ADMIT_DATE)]

message(glue("Total patient-date rows: {format(nrow(patient_date_detail), big.mark=',')}"))

# Calculate single-source vs multi-source breakdown
n_single <- patient_date_detail[n_sources == 1, .N]
n_multi <- patient_date_detail[n_sources > 1, .N]
pct_single <- if (nrow(patient_date_detail) > 0) round(100 * n_single / nrow(patient_date_detail), 1) else 0
pct_multi <- if (nrow(patient_date_detail) > 0) round(100 * n_multi / nrow(patient_date_detail), 1) else 0

message(glue("Single-source dates: {format(n_single, big.mark=',')} ({pct_single}%)"))
message(glue("Multi-source dates: {format(n_multi, big.mark=',')} ({pct_multi}%)"))

# Patients with at least one multi-source date
n_patients_with_multi <- patient_date_detail[n_sources > 1, uniqueN(ID)]
message(glue("Patients with at least one multi-source date: {format(n_patients_with_multi, big.mark=',')}"))

# Sort for CSV output
setorder(patient_date_detail, source_combo, ID, ADMIT_DATE)

# ==============================================================================
# SECTION 4: Source Combination Frequencies (PDSRC-02) ----
# ==============================================================================

message(glue("\n--- SECTION 4: Source Combination Frequencies (PDSRC-02) ---"))

# Per D-02, aggregate summary of source combination frequencies
combo_freq <- patient_date_detail[, .(
  n_patient_dates    = .N,
  n_total_encounters = sum(n_encounters)
), by = source_combo][
  order(-n_patient_dates)
][
  , rank := .I
]

message(glue("Unique source combinations: {nrow(combo_freq)}"))

# Log top 10 combinations
message("\nTop 10 source combinations by patient-date frequency:")
top_n <- min(10, nrow(combo_freq))
for (i in 1:top_n) {
  row <- combo_freq[i, ]
  message(glue("  #{row$rank} {row$source_combo}: {format(row$n_patient_dates, big.mark=',')} patient-dates, {format(row$n_total_encounters, big.mark=',')} encounters"))
}

# Log multi-source combinations separately
multi_combos <- combo_freq[grepl("\\+", source_combo), ]
message(glue("\nMulti-source combinations: {nrow(multi_combos)} total"))
if (nrow(multi_combos) > 0) {
  message("Multi-source combination list:")
  for (i in 1:nrow(multi_combos)) {
    row <- multi_combos[i, ]
    message(glue("  {row$source_combo}: {format(row$n_patient_dates, big.mark=',')} patient-dates"))
  }
}

# ==============================================================================
# SECTION 5: Per-Source Summary Counts (PDSRC-03) ----
# ==============================================================================

message(glue("\n--- SECTION 5: Per-Source Summary Counts (PDSRC-03) ---"))

# Per D-02, per-source aggregate
per_source_summary <- enc_dt[, .(
  total_encounters = .N,
  n_patient_dates  = uniqueN(paste(ID, ADMIT_DATE)),
  n_patients       = uniqueN(ID)
), by = SOURCE][
  order(SOURCE)
]

message("\nPer-source summary:")
for (i in 1:nrow(per_source_summary)) {
  row <- per_source_summary[i, ]
  message(glue("  {row$SOURCE}: {format(row$total_encounters, big.mark=',')} encounters | {format(row$n_patient_dates, big.mark=',')} patient-dates | {format(row$n_patients, big.mark=',')} patients"))
}

# ==============================================================================
# SECTION 6: CSV Output (PDSRC-04) ----
# ==============================================================================

message(glue("\n--- SECTION 6: CSV Output (PDSRC-04) ---"))

output_dir <- file.path(CONFIG$output_dir, "tables")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# CSV 1: patient_date_source_detail.csv
csv1_path <- file.path(output_dir, "patient_date_source_detail.csv")
write_csv(patient_date_detail, csv1_path)
message(glue("Wrote {format(nrow(patient_date_detail), big.mark=',')} rows to {csv1_path}"))

# CSV 2: source_combo_frequencies.csv
csv2_path <- file.path(output_dir, "source_combo_frequencies.csv")
write_csv(combo_freq, csv2_path)
message(glue("Wrote {format(nrow(combo_freq), big.mark=',')} rows to {csv2_path}"))

# CSV 3: per_source_summary.csv
csv3_path <- file.path(output_dir, "per_source_summary.csv")
write_csv(per_source_summary, csv3_path)
message(glue("Wrote {format(nrow(per_source_summary), big.mark=',')} rows to {csv3_path}"))

# ==============================================================================
# SECTION 7: Final Console Summary (PDSRC-05) ----
# ==============================================================================

message(glue("\n{strrep('=', 70)}"))
message("PER-PATIENT SOURCE DETECTION BY DATE -- SUMMARY")
message(glue("{strrep('=', 70)}"))

message(glue("\nTotal encounters analyzed: {format(total_encounters, big.mark=',')}"))
message(glue("Total unique patients: {format(total_patients, big.mark=',')}"))
message(glue("ADMIT_DATE parse rate: {admit_parse_rate}%"))

message(glue("\nTotal patient-date rows: {format(nrow(patient_date_detail), big.mark=',')}"))
message(glue("Single-source dates: {format(n_single, big.mark=',')} ({pct_single}%)"))
message(glue("Multi-source dates: {format(n_multi, big.mark=',')} ({pct_multi}%)"))
message(glue("Patients with at least one multi-source date: {format(n_patients_with_multi, big.mark=',')}"))

message("\nPer-source breakdown:")
for (i in 1:nrow(per_source_summary)) {
  row <- per_source_summary[i, ]
  message(glue("  {row$SOURCE}: {format(row$total_encounters, big.mark=',')} encounters | {format(row$n_patient_dates, big.mark=',')} patient-dates | {format(row$n_patients, big.mark=',')} patients"))
}

message("\nTop 10 source combinations:")
top_n <- min(10, nrow(combo_freq))
for (i in 1:top_n) {
  row <- combo_freq[i, ]
  message(glue("  #{row$rank} {row$source_combo}: {format(row$n_patient_dates, big.mark=',')} patient-dates, {format(row$n_total_encounters, big.mark=',')} encounters"))
}

message("\nCSV files written to output/tables/:")
message(glue("  - patient_date_source_detail.csv ({format(nrow(patient_date_detail), big.mark=',')} rows)"))
message(glue("  - source_combo_frequencies.csv ({format(nrow(combo_freq), big.mark=',')} rows)"))
message(glue("  - per_source_summary.csv ({format(nrow(per_source_summary), big.mark=',')} rows)"))

message(glue("\n{strrep('=', 70)}"))
message("END OF PER-PATIENT SOURCE DETECTION BY DATE")
message(glue("{strrep('=', 70)}\n"))
