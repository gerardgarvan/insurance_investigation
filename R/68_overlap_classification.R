# ==============================================================================
# 68_overlap_classification.R -- Overlap classification and recommendations
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
# Usage: source("R/68_overlap_classification.R")
#
# Dependencies: Sources R/00_config.R (CONFIG, output_dir).
#   Conditionally sources R/01_load_pcornet.R for pcornet tables.
#   Requires: get_pcornet_table("ENCOUNTER"), get_pcornet_table("DEMOGRAPHIC")
#   Requires: Phase 25 CSVs in output/tables/:
#             multi_source_same_date_detail.csv
#             multi_source_same_week_detail.csv
#
# DuckDB migration (Phase 32): Uses get_pcornet_table() for backend-transparent
#   access. Materializes early because downstream logic uses self-joins, nrow(),
#   field_match() comparisons, and iterative loops requiring in-memory data.
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
# SECTION 0: Helper functions
# ==============================================================================

# is_missing_payer() provided by R/utils_payer.R (via R/00_config.R)
# field_match() provided by R/utils_payer.R (via R/00_config.R)

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
    n_sources = col_integer(),
    n_encounters = col_integer(),
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

# Phase 32: Use get_pcornet_table() and materialize for in-memory operations
enc_prepared <- get_pcornet_table("ENCOUNTER") %>%
  materialize() %>%
  rename(ENCOUNTER_SOURCE = SOURCE)

# Parse ADMIT_DATE and DISCHARGE_DATE
enc_prepared <- enc_prepared %>%
  mutate(admit_date_parsed = as.Date(ADMIT_DATE, format = "%Y-%m-%d"))

n_admit_raw <- sum(!is.na(enc_prepared$ADMIT_DATE) & enc_prepared$ADMIT_DATE != "")
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

n_discharge_raw <- sum(!is.na(enc_prepared$DISCHARGE_DATE) & enc_prepared$DISCHARGE_DATE != "")
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
# Phase 32: Use get_pcornet_table() for DEMOGRAPHIC access
enc_prepared <- enc_prepared %>%
  left_join(get_pcornet_table("DEMOGRAPHIC") %>% select(ID, SOURCE) %>% materialize(), by = "ID") %>%
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
# Build source_combo from the pair's ENCOUNTER_SOURCE values (alphabetically sorted by filter above)
sd_pairs <- sd_pairs %>%
  mutate(
    source_combo = paste0(ENCOUNTER_SOURCE_1, "+", ENCOUNTER_SOURCE_2),
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

# Per-source-combo profile for same-date pairs
# Group by source_combo (encounter source pair) -- not DEMOGRAPHIC.SOURCE which is
# a single "home" site per patient and collapses all multi-source overlap into one site
sd_site_profile <- sd_pairs %>%
  group_by(source_combo) %>%
  summarise(
    n_pairs = n(),
    n_identical = sum(classification == "Identical"),
    n_partial = sum(classification == "Partial"),
    n_distinct_class = sum(classification == "Distinct"),
    .groups = "drop"
  ) %>%
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

message(glue("Same-date per-source-combo profiles computed for {nrow(sd_site_profile)} combos"))

# Per-source-combo profile for same-week pairs
sw_site_profile <- sw_pairs %>%
  group_by(source_combo) %>%
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

message(glue("Same-week per-source-combo profiles computed for {nrow(sw_site_profile)} combos"))

# Note: source_combo profiles only include combos that actually have overlap pairs
# (no need to fill missing combos -- absence means no overlap detected)

# ==============================================================================
# SECTION 6: Preferred source from payer completeness (D-08)
# ==============================================================================

message(glue("\n--- SECTION 6: Preferred Source from Payer Completeness (D-08) ---"))

# From same-date encounter pairs data, compute per ENCOUNTER_SOURCE payer completeness
# across all multi-source encounters (not per DEMOGRAPHIC site)
source_completeness <- sd_encounters %>%
  filter(!is.na(ENCOUNTER_SOURCE)) %>%
  group_by(ENCOUNTER_SOURCE) %>%
  summarise(
    n_encounters = n(),
    n_primary_present = sum(!is_missing_payer(PAYER_TYPE_PRIMARY)),
    pct_primary_present = round(100 * n_primary_present / n_encounters, 1),
    n_secondary_present = sum(!is_missing_payer(PAYER_TYPE_SECONDARY)),
    pct_secondary_present = round(100 * n_secondary_present / n_encounters, 1),
    .groups = "drop"
  )

message(glue("Source completeness computed for {nrow(source_completeness)} ENCOUNTER_SOURCE values"))

# For each source_combo, identify preferred source as the one with highest pct_primary_present
# Split source_combo back into its two sources and look up completeness for each
preferred_by_combo <- sd_site_profile %>%
  select(source_combo) %>%
  mutate(
    src_1 = str_extract(source_combo, "^[^+]+"),
    src_2 = str_extract(source_combo, "[^+]+$")
  ) %>%
  left_join(source_completeness %>% select(ENCOUNTER_SOURCE, pct_1 = pct_primary_present),
            by = c("src_1" = "ENCOUNTER_SOURCE")) %>%
  left_join(source_completeness %>% select(ENCOUNTER_SOURCE, pct_2 = pct_primary_present),
            by = c("src_2" = "ENCOUNTER_SOURCE")) %>%
  mutate(
    preferred_source = if_else(coalesce(pct_1, 0) >= coalesce(pct_2, 0), src_1, src_2),
    preferred_source_pct = pmax(coalesce(pct_1, 0), coalesce(pct_2, 0))
  ) %>%
  select(source_combo, preferred_source, preferred_source_pct)

message(glue("Preferred source identified for {nrow(preferred_by_combo)} source combos"))

# Join preferred source back to per-combo profile
sd_site_profile <- sd_site_profile %>%
  left_join(preferred_by_combo, by = "source_combo")

# Update recommendation text for combos with pct_identical >= 70 to include preferred source
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
  left_join(preferred_by_combo, by = "source_combo") %>%
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
csv1 <- sd_pairs %>%
  select(
    source_combo, ID, ADMIT_DATE, ENCOUNTER_SOURCE_1, ENCOUNTER_SOURCE_2,
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
    source_combo, ID, admit_date_1, source_1, admit_date_2, source_2, day_gap,
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
    source_combo = "ALL",
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
    recommendation = "See per-combo recommendations"
  )

all_sw <- sw_pairs %>%
  summarise(
    source_combo = "ALL",
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
    recommendation = "See per-combo recommendations"
  )

csv3 <- bind_rows(csv3, all_sd, all_sw)

write_csv(csv3, file.path(output_dir, "per_site_overlap_profile.csv"))
message(glue("  Written: per_site_overlap_profile.csv ({nrow(csv3)} rows)"))

# --- CSV 4: overlap_source_payer_completeness.csv ---
csv4 <- source_completeness

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

message(glue("\n--- Per-Source-Combo Summary (Same-Date) ---"))
for (i in seq_len(nrow(sd_site_profile))) {
  r <- sd_site_profile[i, ]
  if (r$n_pairs > 0) {
    rec_short <- if_else(r$pct_identical >= 70, "Safe to dedup",
                 if_else(r$pct_identical >= 30, "Mixed", "Retain all"))
    message(glue(
      "  {r$source_combo}: {format(r$n_pairs, big.mark=',')} pairs | ",
      "{r$pct_identical}% Identical | {r$pct_partial}% Partial | {r$pct_distinct}% Distinct | ",
      "Rec: {rec_short}"
    ))
  }
}

message(glue("\n--- Per-Source-Combo Recommendations (OUTPT-03) ---"))
for (i in seq_len(nrow(sd_site_profile))) {
  r <- sd_site_profile[i, ]
  if (r$n_pairs > 0) {
    message(glue("  {r$source_combo}: {r$recommendation}"))
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
