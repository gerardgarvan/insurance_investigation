# ==============================================================================
# 33_multi_source_overlap_av_th.R -- Multi-source overlap detection (AV+TH only)
# ==============================================================================
#
# Phase 33: Multi-Source Overlap Detection for AV+TH encounters only
# Requirements: AVTH-DET-01, AVTH-DET-02, AVTH-DET-03, AVTH-DET-04, AVTH-DET-05, AVTH-DET-06
#
# Purpose: Detect same-date and same-week (within +/-7 days) encounter pairs
#          from different ENCOUNTER.SOURCE values across ALL patients in ENCOUNTER.
#          (AV=Ambulatory Visit, TH=Telehealth only)
#          Outputs feed Phase 34 (R/34_overlap_classification_av_th.R) for field-by-field
#          comparison of overlapping encounters.
#
#          Note: Uses ENCOUNTER.SOURCE directly. No DEMOGRAPHIC join needed.
#          Analyzes all patients in ENCOUNTER, not just HL cohort.
#
# Output: 4 CSV files in output/tables/:
#   - multi_source_same_date_detail_av_th.csv     (AVTH-DET-01)
#   - multi_source_same_week_detail_av_th.csv     (AVTH-DET-01)
#   - multi_source_combo_frequencies_av_th.csv    (AVTH-DET-03)
#   - multi_source_per_source_summary_av_th.csv   (AVTH-DET-02)
#
# Usage: source("R/33_multi_source_overlap_av_th.R")
#
# Dependencies: Sources R/00_config.R (CONFIG, output_dir).
#   Conditionally sources R/01_load_pcornet.R for pcornet tables.
#   Optionally sources R/utils/utils_dates.R if date parse rate < 50%.
#   Requires: get_pcornet_table("ENCOUNTER") (ID, ENCOUNTERID, ADMIT_DATE, SOURCE, ENC_TYPE, etc.)
#
# DuckDB migration (Phase 32): Uses get_pcornet_table() for backend-transparent
#   access. Materializes immediately after loading because all downstream logic
#   (split, self-join in loop, nrow, n_distinct) requires in-memory data.
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

# Load tables if not already loaded (RDS mode)
if (!USE_DUCKDB && !exists("pcornet")) source("R/01_load_pcornet.R")
# DuckDB mode: open connection if needed
if (USE_DUCKDB && !exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}

# ==============================================================================
# SECTION 1: Load and prepare encounters
# ==============================================================================

message(glue("\n{strrep('=', 70)}"))
message("MULTI-SOURCE OVERLAP DETECTION (AV+TH ONLY)")
message("Phase 33: Same-date and same-week multi-source encounter detection (AV+TH encounters only)")
message(glue("{strrep('=', 70)}\n"))

message("--- SECTION 1: Load and Prepare Encounters ---")

# Phase 32: Use get_pcornet_table() and materialize for in-memory operations
enc <- get_pcornet_table("ENCOUNTER") %>%
  materialize() %>%
  filter(ENC_TYPE %in% c("AV", "TH"))

# Log ENC_TYPE distribution after filter
enc_type_dist <- enc %>%
  count(ENC_TYPE, SOURCE) %>%
  arrange(SOURCE, desc(n))

message(glue("\nENC_TYPE distribution after AV+TH filter:"))
for (i in seq_len(nrow(enc_type_dist))) {
  r <- enc_type_dist[i, ]
  message(glue("  {r$SOURCE} | {r$ENC_TYPE}: {format(r$n, big.mark=',')} encounters"))
}

# Warn about sites with zero AV or TH encounters
sites_with_av <- enc %>% filter(ENC_TYPE == "AV") %>% pull(SOURCE) %>% unique()
sites_with_th <- enc %>% filter(ENC_TYPE == "TH") %>% pull(SOURCE) %>% unique()
all_sites <- unique(enc$SOURCE)

if (length(sites_with_av) < length(all_sites)) {
  missing_av <- setdiff(all_sites, sites_with_av)
  message(glue("  WARNING: {length(missing_av)} site(s) have zero AV encounters: {paste(missing_av, collapse=', ')}"))
}
if (length(sites_with_th) < length(all_sites)) {
  missing_th <- setdiff(all_sites, sites_with_th)
  message(glue("  WARNING: {length(missing_th)} site(s) have zero TH encounters: {paste(missing_th, collapse=', ')}"))
}

total_encounters <- nrow(enc)
total_patients <- n_distinct(enc$ID)
message(glue("Total AV+TH encounters loaded: {format(total_encounters, big.mark=',')}"))
message(glue("Total unique patients: {format(total_patients, big.mark=',')}"))

# Log unique ENCOUNTER.SOURCE values
enc_sources <- sort(unique(na.omit(enc$SOURCE)))
message(glue("Unique ENCOUNTER.SOURCE values: {paste(enc_sources, collapse=', ')}"))
message(glue("Encounters with NA SOURCE: {format(sum(is.na(enc$SOURCE)), big.mark=',')}"))

# Parse ADMIT_DATE
enc <- enc %>%
  mutate(admit_date_parsed = as.Date(ADMIT_DATE, format = "%Y-%m-%d"))

n_admit_raw <- if (inherits(enc$ADMIT_DATE, "Date")) {
  sum(!is.na(enc$ADMIT_DATE))
} else {
  sum(!is.na(enc$ADMIT_DATE) & enc$ADMIT_DATE != "")
}
n_admit_parsed <- sum(!is.na(enc$admit_date_parsed))
admit_parse_rate <- if (n_admit_raw > 0) round(100 * n_admit_parsed / n_admit_raw, 1) else 100

if (n_admit_raw > 0 && admit_parse_rate < 50) {
  message(glue("  Standard date parse rate only {admit_parse_rate}% -- trying parse_pcornet_date()"))
  if (file.exists("R/utils/utils_dates.R")) {
    source("R/utils/utils_dates.R")
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
  semi_join(multi_source_dates_set, by = c("ID", "admit_date_parsed" = "ADMIT_DATE"))

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
message("Finding encounter pairs from different sources within 1-7 calendar days...")
message("Strategy: iterate day-by-day through calendar, compare each day's encounters to next 7 days")

# Pre-filter: only patients with encounters from 2+ distinct sources can produce pairs
enc_for_join <- enc_valid %>%
  select(ID, ENCOUNTERID, admit_date_parsed, SOURCE) %>%
  rename(admit_date = admit_date_parsed)

multi_source_ids <- enc_for_join %>%
  group_by(ID) %>%
  summarise(n_src = n_distinct(SOURCE), .groups = "drop") %>%
  filter(n_src > 1) %>%
  pull(ID)

message(glue("Patients with 2+ sources: {format(length(multi_source_ids), big.mark=',')} ",
             "(skipping {format(n_distinct(enc_for_join$ID) - length(multi_source_ids), big.mark=',')} single-source patients)"))

enc_multi <- enc_for_join %>% filter(ID %in% multi_source_ids)

# Build a lookup: for each date, which patients have encounters and from which sources
# Key insight: index by date, not by patient — avoids any patient-level self-join
enc_by_date <- split(
  enc_multi %>% select(ID, admit_date, SOURCE),
  enc_multi$admit_date
)

# Get the full date range present in data
all_dates <- sort(unique(enc_multi$admit_date))
n_dates <- length(all_dates)
message(glue("Date range: {min(all_dates)} to {max(all_dates)} ({n_dates} unique dates with encounters)"))

# Day-by-day iteration with progress bar
# For each date D: get encounters on D, get encounters on D+1..D+7, find cross-source same-patient pairs
same_week_list <- vector("list", n_dates)
total_pairs <- 0L
progress_interval <- max(1L, n_dates %/% 50)  # update ~50 times

message(glue("\nProcessing {n_dates} dates:"))
message(strrep("-", 52))
bar_chars <- 0L

for (idx in seq_along(all_dates)) {
  day_d <- all_dates[idx]
  enc_day_d <- enc_by_date[[as.character(day_d)]]

  if (is.null(enc_day_d) || nrow(enc_day_d) == 0) next

  # Collect encounters from the next 1-7 days
  future_dates <- as.character(seq(day_d + 1, day_d + 7, by = 1))
  enc_window <- bind_rows(lapply(future_dates, function(fd) enc_by_date[[fd]]))

  if (is.null(enc_window) || nrow(enc_window) == 0) next

  # Cross-join day_d encounters with window encounters on same patient, different source
  pairs <- inner_join(
    enc_day_d %>% rename(admit_date_1 = admit_date, source_1 = SOURCE),
    enc_window %>% rename(admit_date_2 = admit_date, source_2 = SOURCE),
    by = "ID",
    relationship = "many-to-many"
  ) %>%
    filter(source_1 != source_2) %>%
    mutate(
      day_gap = as.integer(admit_date_2 - admit_date_1),
      src_lo  = pmin(source_1, source_2),
      src_hi  = pmax(source_1, source_2),
      source_combo = paste(src_lo, src_hi, sep = "+"),
      source_1 = src_lo,
      source_2 = src_hi
    ) %>%
    select(ID, admit_date_1, source_1, admit_date_2, source_2, day_gap, source_combo) %>%
    distinct()

  if (nrow(pairs) > 0) {
    same_week_list[[idx]] <- pairs
    total_pairs <- total_pairs + nrow(pairs)
  }

  # Progress bar: print a '#' every ~2% of dates
  if (idx %% progress_interval == 0 || idx == n_dates) {
    new_chars <- round(50 * idx / n_dates) - bar_chars
    if (new_chars > 0) {
      cat(strrep("#", new_chars))
      bar_chars <- bar_chars + new_chars
    }
  }
}
cat("\n")
message(strrep("-", 52))
message(glue("Day-by-day scan complete: {format(total_pairs, big.mark=',')} pairs across {n_dates} dates"))

same_week_detail <- bind_rows(same_week_list) %>%
  distinct(ID, admit_date_1, source_1, admit_date_2, source_2, .keep_all = TRUE) %>%
  arrange(source_combo, ID, admit_date_1)

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

# --- CSV 1: multi_source_same_date_detail_av_th.csv ---
# Columns: ID, ADMIT_DATE, n_sources, n_encounters, source_combo, sources_list
csv1 <- same_date_detail

write_csv(csv1, file.path(output_dir, "multi_source_same_date_detail_av_th.csv"))
message(glue("  Written: multi_source_same_date_detail_av_th.csv ({format(nrow(csv1), big.mark=',')} rows)"))

# --- CSV 2: multi_source_same_week_detail_av_th.csv ---
# Columns: ID, admit_date_1, source_1, admit_date_2, source_2, day_gap, source_combo
# No suppression needed on day_gap (not a count)
csv2 <- same_week_detail

write_csv(csv2, file.path(output_dir, "multi_source_same_week_detail_av_th.csv"))
message(glue("  Written: multi_source_same_week_detail_av_th.csv ({format(nrow(csv2), big.mark=',')} rows)"))

# --- CSV 3: multi_source_combo_frequencies_av_th.csv ---
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

csv3 <- bind_rows(csv3_same_date, csv3_same_week)

write_csv(csv3, file.path(output_dir, "multi_source_combo_frequencies_av_th.csv"))
message(glue("  Written: multi_source_combo_frequencies_av_th.csv ({nrow(csv3)} rows: {nrow(csv3_same_date)} same-date + {nrow(csv3_same_week)} same-week)"))

# --- CSV 4: multi_source_per_source_summary_av_th.csv ---
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
  arrange(SOURCE)

write_csv(csv4, file.path(output_dir, "multi_source_per_source_summary_av_th.csv"))
message(glue("  Written: multi_source_per_source_summary_av_th.csv ({nrow(csv4)} rows)"))

# --- CSV 5: multi_source_encounter_payer_av_th.csv ---
# Per-encounter detail for same-date multi-source patient-dates, with decoded payer.
# Joins same_date_detail back to ENCOUNTER to get SOURCE and raw payer codes,
# then decodes PAYER_TYPE_PRIMARY/SECONDARY using PCORnet CDM prefix rules.
decode_payer <- function(code) {
  # Use AMC_PAYER_LOOKUP for direct lookup, with prefix fallback
  looked_up <- AMC_PAYER_LOOKUP[code]
  prefix_cat <- case_when(
    is.na(code) | code == ""                       ~ NA_character_,
    str_starts(code, "1")                          ~ "Medicare",
    str_starts(code, "2")                          ~ "Medicaid",
    str_starts(code, "5") | str_starts(code, "6")  ~ "Private",
    str_starts(code, "3") | str_starts(code, "4")  ~ "Other govt",
    str_starts(code, "7")                          ~ "Private",
    str_starts(code, "8")                          ~ "Uninsured",
    str_starts(code, "9")                          ~ "Other",
    TRUE                                           ~ "Other"
  )
  result <- if_else(!is.na(looked_up), looked_up, prefix_cat)
  result <- if_else(is.na(code) | code == "", NA_character_, result)
  result
}

csv5 <- same_date_detail %>%
  select(ID, ADMIT_DATE, n_sources, source_combo) %>%
  inner_join(
    enc_valid %>% select(ID, ADMIT_DATE = admit_date_parsed, SOURCE, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY),
    by = c("ID", "ADMIT_DATE")
  ) %>%
  mutate(
    PAYER_PRIMARY_DECODED   = decode_payer(PAYER_TYPE_PRIMARY),
    PAYER_SECONDARY_DECODED = decode_payer(PAYER_TYPE_SECONDARY)
  ) %>%
  select(ID, ADMIT_DATE, n_sources, source_combo, SOURCE,
         PAYER_TYPE_PRIMARY, PAYER_PRIMARY_DECODED,
         PAYER_TYPE_SECONDARY, PAYER_SECONDARY_DECODED) %>%
  arrange(desc(n_sources), ID, ADMIT_DATE, SOURCE)

write_csv(csv5, file.path(output_dir, "multi_source_encounter_payer_av_th.csv"))
message(glue("  Written: multi_source_encounter_payer_av_th.csv ({format(nrow(csv5), big.mark=',')} rows)"))

# ==============================================================================
# Final console summary
# ==============================================================================

message(glue("\n{strrep('=', 70)}"))
message("MULTI-SOURCE OVERLAP DETECTION (AV+TH ONLY) -- SUMMARY")
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
message("  - multi_source_same_date_detail_av_th.csv")
message("  - multi_source_same_week_detail_av_th.csv")
message("  - multi_source_combo_frequencies_av_th.csv")
message("  - multi_source_per_source_summary_av_th.csv")
message("  - multi_source_encounter_payer_av_th.csv")

message(glue("\nPhase 26 note: These outputs feed R/34_overlap_classification_av_th.R for field-by-field comparison"))

message(glue("\n{strrep('=', 70)}"))
message("END OF MULTI-SOURCE OVERLAP DETECTION (AV+TH ONLY)")
message(glue("{strrep('=', 70)}"))
