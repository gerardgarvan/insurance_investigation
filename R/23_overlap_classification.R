# ==============================================================================
# 23_overlap_classification.R -- Overlap classification and recommendations
# ==============================================================================
#
# Phase 26: Overlap Classification and Recommendations
# Requirements: OVRLP-01, OVRLP-02, OVRLP-03, OVRLP-04, OUTPT-01, OUTPT-02, OUTPT-03
#
# Purpose: Classify each multi-source encounter group (same-date and same-week)
#          from Phase 25 output as Identical, Partial, or Distinct via field-by-field
#          comparison. Outputs CSV files with classified detail, per-site overlap
#          profiles, console summary, and per-site actionable recommendations with
#          preferred source suggestions.
#
# Output: 4 CSV files in output/tables/:
#   - classified_same_date_detail.csv        (OVRLP-01, OVRLP-02)
#   - classified_same_week_detail.csv        (OVRLP-04)
#   - per_site_overlap_profile.csv           (OVRLP-03)
#   - overlap_source_payer_completeness.csv  (OVRLP-03)
#
# Usage: source("R/23_overlap_classification.R")
#
# Dependencies: Sources R/00_config.R (CONFIG, output_dir).
#   Conditionally sources R/01_load_pcornet.R for pcornet tables.
#   Requires: pcornet$ENCOUNTER (ID, ADMIT_DATE, ENC_TYPE, PAYER_TYPE_PRIMARY,
#             PAYER_TYPE_SECONDARY, PROVIDERID, DISCHARGE_DATE, SOURCE)
#             pcornet$DEMOGRAPHIC (ID, SOURCE)
#   Requires: Phase 25 CSVs in output/tables/:
#             multi_source_same_date_detail.csv
#             multi_source_same_week_detail.csv
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
# SECTION 0: Helper functions
# ==============================================================================

# Missing payer definition (copy from R/21_all_site_duplicate_dates.R lines 48-52, D-03)
is_missing_payer <- function(payer_value) {
  is.na(payer_value) |
    nchar(trimws(payer_value)) == 0 |
    payer_value %in% c("NI", "UN", "OT", "99", "9999")
}

# HIPAA suppression helpers (copy from R/22_multi_source_overlap_detection.R lines 47-60)
hipaa_suppress <- function(x) {
  x_num <- suppressWarnings(as.numeric(x))
  ifelse(!is.na(x_num) & x_num >= 1 & x_num <= 10, "<11", as.character(x))
}

suppress_counts <- function(df) {
  count_cols <- grep("^n_|^n$|_count$|_pairs$|_affected$|_dates$|_encounters$|_patients$|^rank$",
                     names(df), value = TRUE)
  count_cols <- count_cols[!grepl("pct_|_rate$|_pct$", count_cols)]
  df %>%
    mutate(across(all_of(count_cols), ~ hipaa_suppress(.x)))
}

# Field comparison helper (D-01, D-02)
field_match <- function(val1, val2) {
  both_na <- is.na(val1) & is.na(val2)
  one_na  <- xor(is.na(val1), is.na(val2))
  both_na | (!one_na & !is.na(val1) & (val1 == val2))
}

# ==============================================================================
# SECTION 1: Load Phase 25 CSVs and prepare ENCOUNTER data
# ==============================================================================

message(glue("\n{strrep('=', 70)}"))
message("OVERLAP CLASSIFICATION AND RECOMMENDATIONS")
message("Phase 26: Classify multi-source encounters as Identical/Partial/Distinct")
message(glue("{strrep('=', 70)}\n"))

message("--- SECTION 1: Load Phase 25 CSVs and Prepare ENCOUNTER Data ---")

output_dir <- file.path(CONFIG$output_dir, "tables")

# Read Phase 25 same-date detail
same_date_detail <- read_csv(
  file.path(output_dir, "multi_source_same_date_detail.csv"),
  col_types = cols(
    ID = col_character(),
    ADMIT_DATE = col_date(format = "%Y-%m-%d"),
    n_sources = col_character(),      # HIPAA-suppressed string
    n_encounters = col_character(),   # HIPAA-suppressed string
    source_combo = col_character(),
    sources_list = col_character()
  ),
  show_col_types = FALSE
)
message(glue("Loaded multi_source_same_date_detail.csv: {format(nrow(same_date_detail), big.mark=',')} rows"))

# Read Phase 25 same-week detail
same_week_detail <- read_csv(
  file.path(output_dir, "multi_source_same_week_detail.csv"),
  col_types = cols(
    ID = col_character(),
    admit_date_1 = col_date(format = "%Y-%m-%d"),
    source_1 = col_character(),
    admit_date_2 = col_date(format = "%Y-%m-%d"),
    source_2 = col_character(),
    day_gap = col_integer(),
    source_combo = col_character()
  ),
  show_col_types = FALSE
)
message(glue("Loaded multi_source_same_week_detail.csv: {format(nrow(same_week_detail), big.mark=',')} rows"))

# Prepare ENCOUNTER data
message(glue("\nPreparing ENCOUNTER data for field comparison..."))

enc_prepared <- pcornet$ENCOUNTER %>%
  rename(ENCOUNTER_SOURCE = SOURCE)

# Parse ADMIT_DATE and DISCHARGE_DATE
enc_prepared <- enc_prepared %>%
  mutate(admit_date_parsed = as.Date(ADMIT_DATE, format = "%Y-%m-%d"))

n_admit_raw <- sum(!is.na(enc_prepared$ADMIT_DATE) & nchar(trimws(enc_prepared$ADMIT_DATE)) > 0)
n_admit_parsed <- sum(!is.na(enc_prepared$admit_date_parsed))
admit_parse_rate <- if (n_admit_raw > 0) round(100 * n_admit_parsed / n_admit_raw, 1) else 100

if (n_admit_raw > 0 && admit_parse_rate < 50) {
  message(glue("  Standard date parse rate only {admit_parse_rate}% -- trying parse_pcornet_date()"))
  if (exists("parse_pcornet_date")) {
    enc_prepared <- enc_prepared %>%
      mutate(admit_date_parsed = parse_pcornet_date(ADMIT_DATE))
    n_admit_parsed <- sum(!is.na(enc_prepared$admit_date_parsed))
    admit_parse_rate <- if (n_admit_raw > 0) round(100 * n_admit_parsed / n_admit_raw, 1) else 100
    message(glue("  After parse_pcornet_date: {format(n_admit_parsed, big.mark=',')} parsed"))
  } else {
    message("  parse_pcornet_date not found -- continuing with standard parsing")
  }
}

message(glue("ADMIT_DATE parse rate: {admit_parse_rate}% ({format(n_admit_parsed, big.mark=',')} of {format(n_admit_raw, big.mark=',')} non-empty values)"))

# Parse DISCHARGE_DATE
enc_prepared <- enc_prepared %>%
  mutate(discharge_date_parsed = as.Date(DISCHARGE_DATE, format = "%Y-%m-%d"))

n_discharge_raw <- sum(!is.na(enc_prepared$DISCHARGE_DATE) & nchar(trimws(enc_prepared$DISCHARGE_DATE)) > 0)
n_discharge_parsed <- sum(!is.na(enc_prepared$discharge_date_parsed))
discharge_parse_rate <- if (n_discharge_raw > 0) round(100 * n_discharge_parsed / n_discharge_raw, 1) else 100

if (n_discharge_raw > 0 && discharge_parse_rate < 50) {
  message(glue("  Standard discharge date parse rate only {discharge_parse_rate}% -- trying parse_pcornet_date()"))
  if (exists("parse_pcornet_date")) {
    enc_prepared <- enc_prepared %>%
      mutate(discharge_date_parsed = parse_pcornet_date(DISCHARGE_DATE))
    n_discharge_parsed <- sum(!is.na(enc_prepared$discharge_date_parsed))
    discharge_parse_rate <- if (n_discharge_raw > 0) round(100 * n_discharge_parsed / n_discharge_raw, 1) else 100
    message(glue("  After parse_pcornet_date: {format(n_discharge_parsed, big.mark=',')} parsed"))
  }
}

message(glue("DISCHARGE_DATE parse rate: {discharge_parse_rate}% ({format(n_discharge_parsed, big.mark=',')} of {format(n_discharge_raw, big.mark=',')} non-empty values)"))

# Normalize payer fields per D-03
enc_prepared <- enc_prepared %>%
  mutate(
    payer_primary_norm = if_else(is_missing_payer(PAYER_TYPE_PRIMARY), NA_character_, PAYER_TYPE_PRIMARY),
    payer_secondary_norm = if_else(is_missing_payer(PAYER_TYPE_SECONDARY), NA_character_, PAYER_TYPE_SECONDARY)
  )

# Join to DEMOGRAPHIC for SITE
enc_prepared <- enc_prepared %>%
  left_join(pcornet$DEMOGRAPHIC %>% select(ID, SOURCE), by = "ID") %>%
  rename(SITE = SOURCE)

n_no_site <- sum(is.na(enc_prepared$SITE))
if (n_no_site > 0) {
  message(glue("  WARNING: {format(n_no_site, big.mark=',')} encounters have no DEMOGRAPHIC record (NA SITE)"))
  enc_prepared <- enc_prepared %>%
    mutate(SITE = if_else(is.na(SITE), "<No Site>", SITE))
}

message(glue("ENCOUNTER data prepared: {format(nrow(enc_prepared), big.mark=',')} encounters"))

# ==============================================================================
# SECTION 2: Same-date field comparison (OVRLP-01, D-04)
# ==============================================================================

message(glue("\n--- SECTION 2: Same-Date Field Comparison (OVRLP-01) ---"))

# For each unique (ID, ADMIT_DATE) in same_date_detail, fetch all encounters
sd_encounters <- same_date_detail %>%
  select(ID, ADMIT_DATE) %>%
  distinct() %>%
  inner_join(enc_prepared, by = c("ID", "ADMIT_DATE" = "admit_date_parsed"))

message(glue("Fetched {format(nrow(sd_encounters), big.mark=',')} encounter rows for same-date multi-source groups"))

# Create pairwise comparisons within each (ID, ADMIT_DATE) group where ENCOUNTER_SOURCE differs
# Use self-join with SOURCE_1 < SOURCE_2 deduplication convention (D-05)
sd_pairs <- sd_encounters %>%
  inner_join(
    sd_encounters,
    by = c("ID", "ADMIT_DATE"),
    suffix = c("_1", "_2"),
    relationship = "many-to-many"
  ) %>%
  filter(ENCOUNTER_SOURCE_1 < ENCOUNTER_SOURCE_2)

message(glue("Created {format(nrow(sd_pairs), big.mark=',')} pairwise comparisons for same-date groups"))

# Apply field_match() to create 5 boolean match columns per D-04
sd_pairs <- sd_pairs %>%
  mutate(
    enc_type_match = field_match(ENC_TYPE_1, ENC_TYPE_2),
    payer_pri_match = field_match(payer_primary_norm_1, payer_primary_norm_2),
    payer_sec_match = field_match(payer_secondary_norm_1, payer_secondary_norm_2),
    providerid_match = field_match(PROVIDERID_1, PROVIDERID_2),
    discharge_match = field_match(discharge_date_parsed_1, discharge_date_parsed_2)
  )

# ==============================================================================
# SECTION 3: Same-date classification (OVRLP-02, D-05, D-06)
# ==============================================================================

message(glue("\n--- SECTION 3: Same-Date Classification (OVRLP-02) ---"))

# Count matches per pair
sd_pairs <- sd_pairs %>%
  mutate(
    match_count = as.integer(enc_type_match) + as.integer(payer_pri_match) +
                  as.integer(payer_sec_match) + as.integer(providerid_match) +
                  as.integer(discharge_match),
    n_fields = 5L
  )

# Apply classification per D-05
sd_pairs <- sd_pairs %>%
  mutate(
    classification = case_when(
      match_count == n_fields ~ "Identical",
      match_count == 0L ~ "Distinct",
      TRUE ~ "Partial"
    )
  )

# Create detailed label per D-06
sd_pairs <- sd_pairs %>%
  mutate(
    classification_detail = paste0(classification, " (", match_count, "/", n_fields, ")"),
    basis = "same_date (5 fields)"
  )

# Log classification distribution
classification_counts <- sd_pairs %>%
  count(classification) %>%
  mutate(pct = round(100 * n / sum(n), 1))

message("Same-date classification distribution:")
for (i in seq_len(nrow(classification_counts))) {
  r <- classification_counts[i, ]
  message(glue("  {r$classification}: {format(r$n, big.mark=',')} pairs ({r$pct}%)"))
}

# ==============================================================================
# SECTION 4: Same-week field comparison and classification (OVRLP-04, D-09, D-10)
# ==============================================================================

message(glue("\n--- SECTION 4: Same-Week Field Comparison and Classification (OVRLP-04) ---"))

# For each same-week pair row, fetch encounter data for both encounters
# Need to pick one representative encounter per (ID, date, source) to avoid Cartesian explosion
enc_for_week <- enc_prepared %>%
  group_by(ID, admit_date_parsed, ENCOUNTER_SOURCE) %>%
  slice_min(ENCOUNTERID, n = 1, with_ties = FALSE) %>%
  ungroup()

message(glue("Representative encounters for same-week matching: {format(nrow(enc_for_week), big.mark=',')} rows"))

# Join same_week_detail to enc_for_week twice: once for encounter 1, once for encounter 2
sw_pairs <- same_week_detail %>%
  left_join(
    enc_for_week %>% select(ID, admit_date_parsed, ENCOUNTER_SOURCE, SITE, ENC_TYPE,
                            payer_primary_norm, payer_secondary_norm, PROVIDERID),
    by = c("ID", "admit_date_1" = "admit_date_parsed", "source_1" = "ENCOUNTER_SOURCE"),
    suffix = c("", "_1")
  ) %>%
  rename(
    SITE_1 = SITE,
    ENC_TYPE_1 = ENC_TYPE,
    payer_primary_norm_1 = payer_primary_norm,
    payer_secondary_norm_1 = payer_secondary_norm,
    PROVIDERID_1 = PROVIDERID
  ) %>%
  left_join(
    enc_for_week %>% select(ID, admit_date_parsed, ENCOUNTER_SOURCE, SITE, ENC_TYPE,
                            payer_primary_norm, payer_secondary_norm, PROVIDERID),
    by = c("ID", "admit_date_2" = "admit_date_parsed", "source_2" = "ENCOUNTER_SOURCE"),
    suffix = c("", "_2")
  ) %>%
  rename(
    SITE_2 = SITE,
    ENC_TYPE_2 = ENC_TYPE,
    payer_primary_norm_2 = payer_primary_norm,
    payer_secondary_norm_2 = payer_secondary_norm,
    PROVIDERID_2 = PROVIDERID
  )

# Use SITE from encounter 1 (both should be the same for single-site patients)
sw_pairs <- sw_pairs %>%
  mutate(SITE = coalesce(SITE_1, SITE_2))

message(glue("Joined same-week pairs with encounter fields: {format(nrow(sw_pairs), big.mark=',')} pairs"))

# Apply field_match() to 4 fields per D-09 (exclude DISCHARGE_DATE)
sw_pairs <- sw_pairs %>%
  mutate(
    enc_type_match = field_match(ENC_TYPE_1, ENC_TYPE_2),
    payer_pri_match = field_match(payer_primary_norm_1, payer_primary_norm_2),
    payer_sec_match = field_match(payer_secondary_norm_1, payer_secondary_norm_2),
    providerid_match = field_match(PROVIDERID_1, PROVIDERID_2),
    match_count = as.integer(enc_type_match) + as.integer(payer_pri_match) +
                  as.integer(payer_sec_match) + as.integer(providerid_match),
    n_fields = 4L
  )

# Same classification logic: Identical=4/4, Partial=1-3/4, Distinct=0/4 (D-05)
sw_pairs <- sw_pairs %>%
  mutate(
    classification = case_when(
      match_count == n_fields ~ "Identical",
      match_count == 0L ~ "Distinct",
      TRUE ~ "Partial"
    ),
    classification_detail = paste0(classification, " (", match_count, "/", n_fields, ")"),
    basis = "same_week (4 fields)"
  )

# Log classification distribution
sw_classification_counts <- sw_pairs %>%
  count(classification) %>%
  mutate(pct = round(100 * n / sum(n), 1))

message("Same-week classification distribution:")
for (i in seq_len(nrow(sw_classification_counts))) {
  r <- sw_classification_counts[i, ]
  message(glue("  {r$classification}: {format(r$n, big.mark=',')} pairs ({r$pct}%)"))
}

# ==============================================================================
# SECTION 5: Per-site overlap profiles (OVRLP-03, D-07)
# ==============================================================================

message(glue("\n--- SECTION 5: Per-Site Overlap Profiles (OVRLP-03) ---"))

# Per-site profile for same-date pairs
sd_site_profile <- sd_pairs %>%
  group_by(SITE_1) %>%
  summarise(
    n_pairs = n(),
    n_identical = sum(classification == "Identical"),
    n_partial = sum(classification == "Partial"),
    n_distinct_class = sum(classification == "Distinct"),
    .groups = "drop"
  ) %>%
  rename(SITE = SITE_1) %>%
  mutate(
    pct_identical = round(100 * n_identical / n_pairs, 1),
    pct_partial = round(100 * n_partial / n_pairs, 1),
    pct_distinct = round(100 * n_distinct_class / n_pairs, 1),
    basis = "same_date (5 fields)"
  )

# Apply D-07 recommendation thresholds
sd_site_profile <- sd_site_profile %>%
  mutate(
    recommendation = case_when(
      pct_identical >= 70 ~ "Safe to deduplicate by keeping preferred source",
      pct_identical >= 30 ~ "Mixed overlap -- review partial matches before deduplication",
      TRUE ~ "Encounters are largely distinct -- retain all"
    )
  )

message(glue("Same-date per-site profiles computed for {nrow(sd_site_profile)} sites"))

# Per-site profile for same-week pairs
sw_site_profile <- sw_pairs %>%
  filter(!is.na(SITE)) %>%
  group_by(SITE) %>%
  summarise(
    n_pairs = n(),
    n_identical = sum(classification == "Identical", na.rm = TRUE),
    n_partial = sum(classification == "Partial", na.rm = TRUE),
    n_distinct_class = sum(classification == "Distinct", na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    pct_identical = round(100 * n_identical / n_pairs, 1),
    pct_partial = round(100 * n_partial / n_pairs, 1),
    pct_distinct = round(100 * n_distinct_class / n_pairs, 1),
    basis = "same_week (4 fields)"
  )

# Apply D-07 recommendation thresholds
sw_site_profile <- sw_site_profile %>%
  mutate(
    recommendation = case_when(
      pct_identical >= 70 ~ "Safe to deduplicate by keeping preferred source",
      pct_identical >= 30 ~ "Mixed overlap -- review partial matches before deduplication",
      TRUE ~ "Encounters are largely distinct -- retain all"
    )
  )

message(glue("Same-week per-site profiles computed for {nrow(sw_site_profile)} sites"))

# Ensure all 5 sites appear even if zero multi-source pairs
all_sites <- sort(unique(na.omit(enc_prepared$SITE)))
sd_site_profile <- sd_site_profile %>%
  complete(SITE = all_sites, fill = list(
    n_pairs = 0, n_identical = 0, n_partial = 0, n_distinct_class = 0,
    pct_identical = 0, pct_partial = 0, pct_distinct = 0,
    basis = "same_date (5 fields)",
    recommendation = "No multi-source encounters"
  ))

sw_site_profile <- sw_site_profile %>%
  complete(SITE = all_sites, fill = list(
    n_pairs = 0, n_identical = 0, n_partial = 0, n_distinct_class = 0,
    pct_identical = 0, pct_partial = 0, pct_distinct = 0,
    basis = "same_week (4 fields)",
    recommendation = "No multi-source encounters"
  ))

# ==============================================================================
# SECTION 6: Preferred source from payer completeness (D-08)
# ==============================================================================

message(glue("\n--- SECTION 6: Preferred Source from Payer Completeness (D-08) ---"))

# From same-date encounter pairs data (before classification aggregation),
# compute per (SITE, ENCOUNTER_SOURCE) payer completeness
source_completeness <- sd_encounters %>%
  filter(!is.na(SITE), !is.na(ENCOUNTER_SOURCE)) %>%
  group_by(SITE, ENCOUNTER_SOURCE) %>%
  summarise(
    n_encounters = n(),
    n_primary_present = sum(!is_missing_payer(PAYER_TYPE_PRIMARY)),
    pct_primary_present = round(100 * n_primary_present / n_encounters, 1),
    n_secondary_present = sum(!is_missing_payer(PAYER_TYPE_SECONDARY)),
    pct_secondary_present = round(100 * n_secondary_present / n_encounters, 1),
    .groups = "drop"
  )

message(glue("Source completeness computed for {nrow(source_completeness)} (SITE, ENCOUNTER_SOURCE) combinations"))

# Per site, identify preferred source as the one with highest pct_primary_present
preferred_source <- source_completeness %>%
  group_by(SITE) %>%
  slice_max(pct_primary_present, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(SITE, preferred_source = ENCOUNTER_SOURCE, preferred_source_pct = pct_primary_present)

message(glue("Preferred source identified for {nrow(preferred_source)} sites"))

# Join preferred source back to per-site profile (same-date only, as recommendation applies to same-date)
sd_site_profile <- sd_site_profile %>%
  left_join(preferred_source, by = "SITE")

# Update recommendation text for sites with pct_identical >= 70 to include preferred source
sd_site_profile <- sd_site_profile %>%
  mutate(
    recommendation = case_when(
      pct_identical >= 70 & !is.na(preferred_source) ~
        glue("Safe to deduplicate -- prefer {preferred_source} ({preferred_source_pct}% payer completeness)"),
      TRUE ~ recommendation
    )
  )

# Same for same-week profile
sw_site_profile <- sw_site_profile %>%
  left_join(preferred_source, by = "SITE") %>%
  mutate(
    recommendation = case_when(
      pct_identical >= 70 & !is.na(preferred_source) ~
        glue("Safe to deduplicate -- prefer {preferred_source} ({preferred_source_pct}% payer completeness)"),
      TRUE ~ recommendation
    )
  )

# ==============================================================================
# SECTION 7: Write CSV outputs (OUTPT-01)
# ==============================================================================

message(glue("\n--- SECTION 7: Writing CSV Outputs ---"))

dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# --- CSV 1: classified_same_date_detail.csv ---
# Build source_combo from the pair's ENCOUNTER_SOURCE values
csv1 <- sd_pairs %>%
  mutate(source_combo = paste0(ENCOUNTER_SOURCE_1, " + ", ENCOUNTER_SOURCE_2)) %>%
  select(
    SITE = SITE_1, ID, ADMIT_DATE, ENCOUNTER_SOURCE_1, ENCOUNTER_SOURCE_2, source_combo,
    ENC_TYPE_1, ENC_TYPE_2, enc_type_match,
    payer_primary_norm_1, payer_primary_norm_2, payer_pri_match,
    payer_secondary_norm_1, payer_secondary_norm_2, payer_sec_match,
    PROVIDERID_1, PROVIDERID_2, providerid_match,
    discharge_date_parsed_1, discharge_date_parsed_2, discharge_match,
    match_count, n_fields, classification, classification_detail, basis
  )

write_csv(csv1, file.path(output_dir, "classified_same_date_detail.csv"))
message(glue("  Written: classified_same_date_detail.csv ({format(nrow(csv1), big.mark=',')} rows)"))

# --- CSV 2: classified_same_week_detail.csv ---
csv2 <- sw_pairs %>%
  select(
    SITE, ID, admit_date_1, source_1, admit_date_2, source_2, day_gap, source_combo,
    ENC_TYPE_1, ENC_TYPE_2, enc_type_match,
    payer_primary_norm_1, payer_primary_norm_2, payer_pri_match,
    payer_secondary_norm_1, payer_secondary_norm_2, payer_sec_match,
    PROVIDERID_1, PROVIDERID_2, providerid_match,
    match_count, n_fields, classification, classification_detail, basis
  )

write_csv(csv2, file.path(output_dir, "classified_same_week_detail.csv"))
message(glue("  Written: classified_same_week_detail.csv ({format(nrow(csv2), big.mark=',')} rows)"))

# --- CSV 3: per_site_overlap_profile.csv ---
# Two rows per site (one for same_date, one for same_week) plus an ALL aggregate row for each basis
csv3 <- bind_rows(sd_site_profile, sw_site_profile)

# Add ALL aggregate rows
all_sd <- sd_pairs %>%
  summarise(
    SITE = "ALL",
    n_pairs = n(),
    n_identical = sum(classification == "Identical"),
    n_partial = sum(classification == "Partial"),
    n_distinct_class = sum(classification == "Distinct"),
    pct_identical = round(100 * n_identical / n_pairs, 1),
    pct_partial = round(100 * n_partial / n_pairs, 1),
    pct_distinct = round(100 * n_distinct_class / n_pairs, 1),
    basis = "same_date (5 fields)",
    preferred_source = NA_character_,
    preferred_source_pct = NA_real_,
    recommendation = "See per-site recommendations"
  )

all_sw <- sw_pairs %>%
  summarise(
    SITE = "ALL",
    n_pairs = n(),
    n_identical = sum(classification == "Identical", na.rm = TRUE),
    n_partial = sum(classification == "Partial", na.rm = TRUE),
    n_distinct_class = sum(classification == "Distinct", na.rm = TRUE),
    pct_identical = round(100 * n_identical / n_pairs, 1),
    pct_partial = round(100 * n_partial / n_pairs, 1),
    pct_distinct = round(100 * n_distinct_class / n_pairs, 1),
    basis = "same_week (4 fields)",
    preferred_source = NA_character_,
    preferred_source_pct = NA_real_,
    recommendation = "See per-site recommendations"
  )

csv3 <- bind_rows(csv3, all_sd, all_sw) %>%
  suppress_counts()

write_csv(csv3, file.path(output_dir, "per_site_overlap_profile.csv"))
message(glue("  Written: per_site_overlap_profile.csv ({nrow(csv3)} rows)"))

# --- CSV 4: overlap_source_payer_completeness.csv ---
csv4 <- source_completeness %>%
  suppress_counts()

write_csv(csv4, file.path(output_dir, "overlap_source_payer_completeness.csv"))
message(glue("  Written: overlap_source_payer_completeness.csv ({nrow(csv4)} rows)"))

# ==============================================================================
# SECTION 8: Console summary (OUTPT-02, OUTPT-03)
# ==============================================================================

message(glue("\n{strrep('=', 70)}"))
message("OVERLAP CLASSIFICATION AND RECOMMENDATIONS -- SUMMARY")
message(glue("Phase 26: Overlap classification for multi-source encounters"))
message(glue("{strrep('=', 70)}"))

message(glue("\nTotal same-date pairs classified:  {format(nrow(sd_pairs), big.mark=',')}"))
message(glue("Total same-week pairs classified:  {format(nrow(sw_pairs), big.mark=',')}"))

message(glue("\n--- Same-Date Classification Breakdown ---"))
for (i in seq_len(nrow(classification_counts))) {
  r <- classification_counts[i, ]
  message(glue("  {r$classification}: {format(r$n, big.mark=',')} ({r$pct}%)"))
}

message(glue("\n--- Same-Week Classification Breakdown ---"))
for (i in seq_len(nrow(sw_classification_counts))) {
  r <- sw_classification_counts[i, ]
  message(glue("  {r$classification}: {format(r$n, big.mark=',')} ({r$pct}%)"))
}

message(glue("\n--- Per-Site Summary (Same-Date) ---"))
for (i in seq_len(nrow(sd_site_profile))) {
  r <- sd_site_profile[i, ]
  if (r$n_pairs > 0) {
    rec_short <- if_else(r$pct_identical >= 70, "Safe to dedup",
                 if_else(r$pct_identical >= 30, "Mixed", "Retain all"))
    message(glue(
      "  {r$SITE}: {format(r$n_pairs, big.mark=',')} pairs | ",
      "{r$pct_identical}% Identical | {r$pct_partial}% Partial | {r$pct_distinct}% Distinct | ",
      "Rec: {rec_short}"
    ))
  }
}

message(glue("\n--- Per-Site Recommendations (OUTPT-03) ---"))
for (i in seq_len(nrow(sd_site_profile))) {
  r <- sd_site_profile[i, ]
  if (r$n_pairs > 0) {
    message(glue("  {r$SITE}: {r$recommendation}"))
  }
}

message(glue("\nCSV files written to {output_dir}/:"))
message("  - classified_same_date_detail.csv")
message("  - classified_same_week_detail.csv")
message("  - per_site_overlap_profile.csv")
message("  - overlap_source_payer_completeness.csv")

message(glue("\nPhase 26 complete: {format(nrow(sd_pairs), big.mark=',')} same-date pairs and {format(nrow(sw_pairs), big.mark=',')} same-week pairs classified"))

message(glue("\n{strrep('=', 70)}"))
message("END OF OVERLAP CLASSIFICATION AND RECOMMENDATIONS")
message(glue("{strrep('=', 70)}"))
