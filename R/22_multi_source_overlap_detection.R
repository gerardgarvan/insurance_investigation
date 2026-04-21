# ==============================================================================
# 22_multi_source_overlap_detection.R -- Multi-source overlap detection
# ==============================================================================
#
# Phase 25: Multi-Source Overlap Detection
# Requirements: SAMEDT-01, SAMEDT-02, SAMEDT-03, SAMEWK-01, SAMEWK-02, SAMEWK-03
#
# Purpose: Detect same-date and same-week (within +/-7 days) encounter pairs
#          from different ENCOUNTER.SOURCE values across ALL patients in ENCOUNTER.
#          Outputs feed Phase 26 (R/23_overlap_classification.R) for field-by-field
#          comparison of overlapping encounters.
#
#          Note: Uses ENCOUNTER.SOURCE directly. No DEMOGRAPHIC join needed.
#          Analyzes all patients in ENCOUNTER, not just HL cohort.
#
# Output: 4 CSV files in output/tables/:
#   - multi_source_same_date_detail.csv     (SAMEDT-01)
#   - multi_source_same_week_detail.csv     (SAMEWK-01)
#   - multi_source_combo_frequencies.csv    (SAMEDT-03, SAMEWK-03)
#   - multi_source_per_source_summary.csv   (SAMEDT-02, SAMEWK-02)
#
# Usage: source("R/22_multi_source_overlap_detection.R")
#
# Dependencies: Sources R/00_config.R (CONFIG, output_dir).
#   Conditionally sources R/01_load_pcornet.R for pcornet tables.
#   Optionally sources R/utils_dates.R if date parse rate < 50%.
#   Requires: pcornet$ENCOUNTER (ID, ENCOUNTERID, ADMIT_DATE, SOURCE, etc.)
#
# Standalone script -- NOT part of the main pipeline sequence.
# ==============================================================================

source("R/00_config.R")
library(dplyr)
library(lubridate)
library(glue)
library(readr)
library(stringr)
library(tidyr)

# Load tables if not already loaded
if (!exists("pcornet")) source("R/01_load_pcornet.R")

# ==============================================================================
# HIPAA suppression helper
# ==============================================================================
# Replace count values 1-10 with "<11" in CSV outputs (not console).
hipaa_suppress <- function(x) {
  x_num <- suppressWarnings(as.numeric(x))
  ifelse(!is.na(x_num) & x_num >= 1 & x_num <= 10, "<11", as.character(x))
}

# Apply HIPAA suppression to all count/n_ columns in a data frame
suppress_counts <- function(df) {
  count_cols <- grep("^n_|^n$|_count$|_pairs$|_affected$|_dates$|_encounters$|_patients$|^rank$",
                     names(df), value = TRUE)
  # Exclude columns that are not counts (rates, pcts)
  count_cols <- count_cols[!grepl("pct_|_rate$|_pct$", count_cols)]
  df %>%
    mutate(across(all_of(count_cols), ~ hipaa_suppress(.x)))
}

# ==============================================================================
# SECTION 1: Load and prepare encounters
# ==============================================================================

message(glue("\n{strrep('=', 70)}"))
message("MULTI-SOURCE OVERLAP DETECTION")
message("Phase 25: Same-date and same-week multi-source encounter detection")
message(glue("{strrep('=', 70)}\n"))

message("--- SECTION 1: Load and Prepare Encounters ---")

enc <- pcornet$ENCOUNTER

total_encounters <- nrow(enc)
total_patients <- n_distinct(enc$ID)
message(glue("Total encounters loaded: {format(total_encounters, big.mark=',')}"))
message(glue("Total unique patients: {format(total_patients, big.mark=',')}"))

# Log unique ENCOUNTER.SOURCE values
enc_sources <- sort(unique(na.omit(enc$SOURCE)))
message(glue("Unique ENCOUNTER.SOURCE values: {paste(enc_sources, collapse=', ')}"))
message(glue("Encounters with NA SOURCE: {format(sum(is.na(enc$SOURCE)), big.mark=',')}"))

# Parse ADMIT_DATE
enc <- enc %>%
  mutate(admit_date_parsed = as.Date(ADMIT_DATE, format = "%Y-%m-%d"))

n_admit_raw <- sum(!is.na(enc$ADMIT_DATE) & nchar(trimws(enc$ADMIT_DATE)) > 0)
n_admit_parsed <- sum(!is.na(enc$admit_date_parsed))
admit_parse_rate <- if (n_admit_raw > 0) round(100 * n_admit_parsed / n_admit_raw, 1) else 100

if (n_admit_raw > 0 && admit_parse_rate < 50) {
  message(glue("  Standard date parse rate only {admit_parse_rate}% -- trying parse_pcornet_date()"))
  if (file.exists("R/utils_dates.R")) {
    source("R/utils_dates.R")
    enc <- enc %>%
      mutate(admit_date_parsed = parse_pcornet_date(ADMIT_DATE))
    n_admit_parsed <- sum(!is.na(enc$admit_date_parsed))
    admit_parse_rate <- if (n_admit_raw > 0) round(100 * n_admit_parsed / n_admit_raw, 1) else 100
    message(glue("  After parse_pcornet_date: {format(n_admit_parsed, big.mark=',')} parsed"))
  } else {
    message("  utils_dates.R not found -- continuing with standard parsing")
  }
}

message(glue("ADMIT_DATE parse rate: {admit_parse_rate}% ({format(n_admit_parsed, big.mark=',')} of {format(n_admit_raw, big.mark=',')} non-empty values)"))
message(glue("ADMIT_DATE NA after parsing: {format(sum(is.na(enc$admit_date_parsed)), big.mark=',')}"))

# Work with encounters that have a valid ADMIT_DATE and non-NA SOURCE
enc_valid <- enc %>%
  filter(!is.na(admit_date_parsed), !is.na(SOURCE))

message(glue("Encounters with valid ADMIT_DATE and SOURCE: {format(nrow(enc_valid), big.mark=',')}"))

# ==============================================================================
# SECTION 2: Same-date multi-source detection (SAMEDT-01)
# ==============================================================================

message(glue("\n--- SECTION 2: Same-Date Multi-Source Detection (SAMEDT-01) ---"))

# Group by patient + date; keep groups with >1 distinct SOURCE
same_date_groups <- enc_valid %>%
  group_by(ID, admit_date_parsed) %>%
  summarise(
    n_sources    = n_distinct(SOURCE),
    n_encounters = n(),
    source_combo = paste(sort(unique(SOURCE)), collapse = "+"),
    sources_list = paste(sort(unique(SOURCE)), collapse = ", "),
    .groups = "drop"
  ) %>%
  filter(n_sources > 1)

same_date_detail <- same_date_groups %>%
  rename(ADMIT_DATE = admit_date_parsed) %>%
  arrange(source_combo, ID, ADMIT_DATE)

message(glue("Total same-date multi-source patient-date pairs: {format(nrow(same_date_detail), big.mark=',')}"))
message(glue("Patients with at least one same-date multi-source event: {format(n_distinct(same_date_detail$ID), big.mark=',')}"))

# ==============================================================================
# SECTION 3: Per-ENCOUNTER.SOURCE summary for same-date (SAMEDT-02)
# ==============================================================================

message(glue("\n--- SECTION 3: Per-Source Summary for Same-Date (SAMEDT-02) ---"))

# Total encounters per source (denominator for overlap rate)
total_per_source <- enc_valid %>%
  group_by(SOURCE) %>%
  summarise(total_encounters = n(), .groups = "drop")

# Encounters on multi-source dates (for pct_encounters_overlapping)
multi_source_dates_set <- same_date_detail %>%
  select(ID, ADMIT_DATE)

enc_on_multi_dates <- enc_valid %>%
  rename(ADMIT_DATE = admit_date_parsed) %>%
  semi_join(multi_source_dates_set, by = c("ID", "ADMIT_DATE"))

per_source_overlap_counts <- enc_on_multi_dates %>%
  group_by(SOURCE) %>%
  summarise(
    n_encounters_on_multi_dates = n(),
    n_multi_source_dates        = n_distinct(paste(ID, ADMIT_DATE)),
    n_patients_affected         = n_distinct(ID),
    .groups = "drop"
  )

per_source_same_date <- total_per_source %>%
  left_join(per_source_overlap_counts, by = "SOURCE") %>%
  mutate(
    n_encounters_on_multi_dates = coalesce(n_encounters_on_multi_dates, 0L),
    n_multi_source_dates        = coalesce(n_multi_source_dates, 0L),
    n_patients_affected         = coalesce(n_patients_affected, 0L),
    pct_encounters_overlapping  = round(100 * n_encounters_on_multi_dates / total_encounters, 2)
  ) %>%
  arrange(SOURCE)

message("Per-ENCOUNTER.SOURCE same-date overlap counts:")
for (i in seq_len(nrow(per_source_same_date))) {
  r <- per_source_same_date[i, ]
  message(glue("  {r$SOURCE}: {format(r$total_encounters, big.mark=',')} total encounters | {format(r$n_patients_affected, big.mark=',')} patients affected | {r$pct_encounters_overlapping}% overlapping"))
}

# ==============================================================================
# SECTION 4: Source combination frequencies for same-date (SAMEDT-03)
# ==============================================================================

message(glue("\n--- SECTION 4: Source Combination Frequencies for Same-Date (SAMEDT-03) ---"))

# For each source_combo: count patient-date pairs and total encounters
same_date_combo_freq <- same_date_detail %>%
  group_by(source_combo) %>%
  summarise(
    n_patient_dates    = n(),
    n_total_encounters = sum(n_encounters),
    .groups = "drop"
  ) %>%
  arrange(desc(n_patient_dates)) %>%
  mutate(rank = row_number())

message(glue("Unique same-date source combinations: {nrow(same_date_combo_freq)}"))
message("Top 10 same-date source combinations:")
top10_sd <- head(same_date_combo_freq, 10)
for (i in seq_len(nrow(top10_sd))) {
  r <- top10_sd[i, ]
  message(glue("  #{r$rank} {r$source_combo}: {format(r$n_patient_dates, big.mark=',')} patient-dates, {format(r$n_total_encounters, big.mark=',')} encounters"))
}

# ==============================================================================
# SECTION 5: Same-week near-duplicate detection (SAMEWK-01, SAMEWK-02)
# ==============================================================================

message(glue("\n--- SECTION 5: Same-Week Near-Duplicate Detection (SAMEWK-01) ---"))
message("Finding encounter pairs from different sources within 1-7 calendar days (pairwise)...")

# Pairwise self-join on ID; filter different SOURCE and 1-7 day gap
# Deduplicate using SOURCE_x < SOURCE_y OR (SOURCE_x == SOURCE_y AND admit_date_x < admit_date_y)
# to avoid counting (A,B) and (B,A) as separate pairs.
# Strategy: limit to SOURCE_x <= SOURCE_y and use tie-breaking for equal sources (impossible since SOURCE_x != SOURCE_y)

enc_for_join <- enc_valid %>%
  select(ID, ENCOUNTERID, admit_date_parsed, SOURCE) %>%
  rename(admit_date = admit_date_parsed)

same_week_pairs <- enc_for_join %>%
  inner_join(enc_for_join, by = "ID", suffix = c("_x", "_y")) %>%
  filter(
    SOURCE_x != SOURCE_y,
    abs(as.integer(admit_date_x - admit_date_y)) >= 1,
    abs(as.integer(admit_date_x - admit_date_y)) <= 7
  ) %>%
  # Deduplicate: canonical ordering by SOURCE (alphabetical) to keep one direction
  filter(SOURCE_x < SOURCE_y | (SOURCE_x == SOURCE_y & admit_date_x <= admit_date_y)) %>%
  mutate(
    day_gap     = as.integer(abs(admit_date_x - admit_date_y)),
    source_combo = paste(pmin(SOURCE_x, SOURCE_y), pmax(SOURCE_x, SOURCE_y), sep = "+")
  ) %>%
  select(
    ID,
    admit_date_1 = admit_date_x,
    source_1     = SOURCE_x,
    admit_date_2 = admit_date_y,
    source_2     = SOURCE_y,
    day_gap,
    source_combo
  ) %>%
  arrange(source_combo, ID, admit_date_1)

same_week_detail <- same_week_pairs

message(glue("Total same-week near-duplicate pairs: {format(nrow(same_week_detail), big.mark=',')}"))
message(glue("Patients with at least one same-week near-duplicate: {format(n_distinct(same_week_detail$ID), big.mark=',')}"))

# Verify day_gap range (0 should not appear — same-date is excluded)
day_gap_range <- range(same_week_detail$day_gap, na.rm = TRUE)
if (nrow(same_week_detail) > 0) {
  message(glue("Day gap range: {day_gap_range[1]} to {day_gap_range[2]} (expect 1-7, never 0)"))
}

# ==============================================================================
# SECTION 6: Per-source summary and combo frequencies for same-week (SAMEWK-02, SAMEWK-03)
# ==============================================================================

message(glue("\n--- SECTION 6: Per-Source Summary for Same-Week (SAMEWK-02, SAMEWK-03) ---"))

# Per-source near-duplicate summary
# Count pairs involving each source (appear as source_1 or source_2)
sw_as_source1 <- same_week_detail %>%
  group_by(SOURCE = source_1) %>%
  summarise(
    n_near_dup_pairs_as_src1 = n(),
    n_patients_as_src1       = n_distinct(ID),
    .groups = "drop"
  )

sw_as_source2 <- same_week_detail %>%
  group_by(SOURCE = source_2) %>%
  summarise(
    n_near_dup_pairs_as_src2 = n(),
    n_patients_as_src2       = n_distinct(ID),
    .groups = "drop"
  )

per_source_same_week <- total_per_source %>%
  left_join(sw_as_source1, by = "SOURCE") %>%
  left_join(sw_as_source2, by = "SOURCE") %>%
  mutate(
    n_near_dup_pairs_as_src1 = coalesce(n_near_dup_pairs_as_src1, 0L),
    n_near_dup_pairs_as_src2 = coalesce(n_near_dup_pairs_as_src2, 0L),
    n_patients_as_src1       = coalesce(n_patients_as_src1, 0L),
    n_patients_as_src2       = coalesce(n_patients_as_src2, 0L),
    n_near_duplicate_pairs   = n_near_dup_pairs_as_src1 + n_near_dup_pairs_as_src2,
    # Patients affected: union across both roles (recount from detail)
    n_patients_affected      = NA_integer_  # filled below
  ) %>%
  select(SOURCE, total_encounters, n_near_duplicate_pairs)

# Recount patients per source properly (union of source_1 and source_2 roles)
patients_per_source_sw <- bind_rows(
  same_week_detail %>% select(SOURCE = source_1, ID),
  same_week_detail %>% select(SOURCE = source_2, ID)
) %>%
  group_by(SOURCE) %>%
  summarise(n_patients_affected_sw = n_distinct(ID), .groups = "drop")

per_source_same_week <- per_source_same_week %>%
  left_join(patients_per_source_sw, by = "SOURCE") %>%
  mutate(n_patients_affected_sw = coalesce(n_patients_affected_sw, 0L)) %>%
  arrange(SOURCE)

message("Per-ENCOUNTER.SOURCE same-week near-duplicate counts:")
for (i in seq_len(nrow(per_source_same_week))) {
  r <- per_source_same_week[i, ]
  message(glue("  {r$SOURCE}: {format(r$n_near_duplicate_pairs, big.mark=',')} near-dup pairs | {format(r$n_patients_affected_sw, big.mark=',')} patients"))
}

# Same-week combo frequencies
same_week_combo_freq <- same_week_detail %>%
  group_by(source_combo) %>%
  summarise(
    n_pairs            = n(),
    n_total_encounters = n_distinct(paste(ID, admit_date_1)) + n_distinct(paste(ID, admit_date_2)),
    .groups = "drop"
  ) %>%
  arrange(desc(n_pairs)) %>%
  mutate(rank = row_number())

message(glue("\nUnique same-week source combinations: {nrow(same_week_combo_freq)}"))
message("Top 10 same-week source combinations:")
top10_sw <- head(same_week_combo_freq, 10)
for (i in seq_len(nrow(top10_sw))) {
  r <- top10_sw[i, ]
  message(glue("  #{r$rank} {r$source_combo}: {format(r$n_pairs, big.mark=',')} pairs"))
}

# Side-by-side comparison per source
message(glue("\nSide-by-side same-date vs same-week per ENCOUNTER.SOURCE:"))
combined_src <- per_source_same_date %>%
  select(SOURCE, same_date_patients = n_patients_affected) %>%
  full_join(
    per_source_same_week %>% select(SOURCE, same_week_patients = n_patients_affected_sw),
    by = "SOURCE"
  ) %>%
  mutate(
    same_date_patients  = coalesce(same_date_patients, 0L),
    same_week_patients  = coalesce(same_week_patients, 0L)
  ) %>%
  arrange(SOURCE)

for (i in seq_len(nrow(combined_src))) {
  r <- combined_src[i, ]
  message(glue("  {r$SOURCE}: same-date patients={format(r$same_date_patients, big.mark=',')}, same-week patients={format(r$same_week_patients, big.mark=',')}"))
}

# ==============================================================================
# SECTION 7: Write CSV outputs and console summary
# ==============================================================================

message(glue("\n--- SECTION 7: Writing CSV Outputs ---"))

output_dir <- file.path(CONFIG$output_dir, "tables")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# --- CSV 1: multi_source_same_date_detail.csv ---
# Columns: ID, ADMIT_DATE, n_sources, n_encounters, source_combo, sources_list
# HIPAA suppression on n_sources, n_encounters
csv1 <- same_date_detail %>%
  mutate(
    n_sources    = hipaa_suppress(n_sources),
    n_encounters = hipaa_suppress(n_encounters)
  )

write_csv(csv1, file.path(output_dir, "multi_source_same_date_detail.csv"))
message(glue("  Written: multi_source_same_date_detail.csv ({format(nrow(csv1), big.mark=',')} rows)"))

# --- CSV 2: multi_source_same_week_detail.csv ---
# Columns: ID, admit_date_1, source_1, admit_date_2, source_2, day_gap, source_combo
# No suppression needed on day_gap (not a count)
csv2 <- same_week_detail

write_csv(csv2, file.path(output_dir, "multi_source_same_week_detail.csv"))
message(glue("  Written: multi_source_same_week_detail.csv ({format(nrow(csv2), big.mark=',')} rows)"))

# --- CSV 3: multi_source_combo_frequencies.csv ---
# Two sections stacked: same_date combos then same_week combos
# Columns: match_type, source_combo, n_patient_dates (or n_pairs), n_total_encounters, rank
csv3_same_date <- same_date_combo_freq %>%
  mutate(match_type = "same_date") %>%
  rename(n_patient_dates = n_patient_dates) %>%
  select(match_type, source_combo, n_patient_dates, n_total_encounters, rank)

csv3_same_week <- same_week_combo_freq %>%
  mutate(
    match_type      = "same_week",
    n_patient_dates = n_pairs  # reuse column name for consistency
  ) %>%
  select(match_type, source_combo, n_patient_dates, n_total_encounters, rank)

csv3 <- bind_rows(csv3_same_date, csv3_same_week) %>%
  mutate(
    n_patient_dates    = hipaa_suppress(n_patient_dates),
    n_total_encounters = hipaa_suppress(n_total_encounters)
  )

write_csv(csv3, file.path(output_dir, "multi_source_combo_frequencies.csv"))
message(glue("  Written: multi_source_combo_frequencies.csv ({nrow(csv3)} rows: {nrow(csv3_same_date)} same-date + {nrow(csv3_same_week)} same-week)"))

# --- CSV 4: multi_source_per_source_summary.csv ---
# Columns: SOURCE, total_encounters, n_same_date_multi_source_dates, n_same_date_patients_affected,
#          pct_same_date_overlapping, n_same_week_near_dup_pairs, n_same_week_patients_affected
csv4 <- per_source_same_date %>%
  select(
    SOURCE,
    total_encounters,
    n_same_date_multi_source_dates = n_multi_source_dates,
    n_same_date_patients_affected  = n_patients_affected,
    pct_same_date_overlapping      = pct_encounters_overlapping
  ) %>%
  left_join(
    per_source_same_week %>%
      select(SOURCE,
             n_same_week_near_dup_pairs = n_near_duplicate_pairs,
             n_same_week_patients_affected = n_patients_affected_sw),
    by = "SOURCE"
  ) %>%
  mutate(
    n_same_week_near_dup_pairs    = coalesce(n_same_week_near_dup_pairs, 0L),
    n_same_week_patients_affected = coalesce(n_same_week_patients_affected, 0L)
  ) %>%
  arrange(SOURCE) %>%
  # HIPAA suppression on count columns
  mutate(
    total_encounters                  = hipaa_suppress(total_encounters),
    n_same_date_multi_source_dates    = hipaa_suppress(n_same_date_multi_source_dates),
    n_same_date_patients_affected     = hipaa_suppress(n_same_date_patients_affected),
    n_same_week_near_dup_pairs        = hipaa_suppress(n_same_week_near_dup_pairs),
    n_same_week_patients_affected     = hipaa_suppress(n_same_week_patients_affected)
  )

write_csv(csv4, file.path(output_dir, "multi_source_per_source_summary.csv"))
message(glue("  Written: multi_source_per_source_summary.csv ({nrow(csv4)} rows)"))

# ==============================================================================
# Final console summary
# ==============================================================================

message(glue("\n{strrep('=', 70)}"))
message("MULTI-SOURCE OVERLAP DETECTION -- SUMMARY")
message(glue("{strrep('=', 70)}"))

message(glue("\nTotal encounters analyzed:      {format(total_encounters, big.mark=',')}"))
message(glue("Total unique patients:          {format(total_patients, big.mark=',')}"))
message(glue("ADMIT_DATE parse rate:          {admit_parse_rate}%"))

message(glue("\n--- Same-Date Results ---"))
message(glue("Multi-source patient-date pairs: {format(nrow(same_date_detail), big.mark=',')}"))
message(glue("Patients affected (same-date):   {format(n_distinct(same_date_detail$ID), big.mark=',')}"))

message(glue("\n--- Same-Week Results ---"))
message(glue("Near-duplicate pairs (1-7 days): {format(nrow(same_week_detail), big.mark=',')}"))
message(glue("Patients affected (same-week):   {format(n_distinct(same_week_detail$ID), big.mark=',')}"))

message(glue("\nPer-source breakdown (same-date patients | same-week pairs):"))
for (i in seq_len(nrow(combined_src))) {
  r <- combined_src[i, ]
  sw_pairs <- per_source_same_week %>%
    filter(SOURCE == r$SOURCE) %>%
    pull(n_near_duplicate_pairs)
  sw_pairs_val <- if (length(sw_pairs) > 0) sw_pairs else 0
  message(glue("  {r$SOURCE}: same-date={format(r$same_date_patients, big.mark=',')} patients | same-week={format(sw_pairs_val, big.mark=',')} pairs"))
}

message(glue("\nTop 10 same-date source combos:"))
top10_sd_final <- head(same_date_combo_freq, 10)
for (i in seq_len(nrow(top10_sd_final))) {
  r <- top10_sd_final[i, ]
  message(glue("  #{r$rank} {r$source_combo}: {format(r$n_patient_dates, big.mark=',')} patient-dates"))
}

message(glue("\nTop 10 same-week source combos:"))
top10_sw_final <- head(same_week_combo_freq, 10)
for (i in seq_len(nrow(top10_sw_final))) {
  r <- top10_sw_final[i, ]
  message(glue("  #{r$rank} {r$source_combo}: {format(r$n_pairs, big.mark=',')} pairs"))
}

message(glue("\nCSV files written to {output_dir}/:"))
message("  - multi_source_same_date_detail.csv")
message("  - multi_source_same_week_detail.csv")
message("  - multi_source_combo_frequencies.csv")
message("  - multi_source_per_source_summary.csv")

message(glue("\nPhase 26 note: These outputs feed R/23_overlap_classification.R for field-by-field comparison"))

message(glue("\n{strrep('=', 70)}"))
message("END OF MULTI-SOURCE OVERLAP DETECTION")
message(glue("{strrep('=', 70)}"))
