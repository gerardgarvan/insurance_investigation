# ==============================================================================
# 20_all_source_missingness.R -- All-source payer data missingness diagnostic
# ==============================================================================
#
# Phase 21: Generalize Phase 19 to All Sources
# Requirements: ALLMISS-01, ALLMISS-02, ALLMISS-03, ALLMISS-04, ALLMISS-05
#
# Purpose: Characterize payer data missingness across ALL partner sites
#          (AMS, UMI, FLM, VRT, UFH) in the OneFlorida+ HL cohort. Extends
#          Phase 19's UFH-specific investigation to a cross-site comparison.
#          Profiles both raw ENCOUNTER PAYER_TYPE fields and derived harmonized
#          categories, with breakdowns by year, encounter type, and their
#          combination, grouped by SOURCE.
#
# Output: 6 CSV files in output/tables/:
#   - all_source_payer_raw_value_distribution.csv   (ALLMISS-01)
#   - all_source_payer_missingness_by_year.csv       (ALLMISS-02)
#   - all_source_payer_missingness_by_enc_type.csv   (ALLMISS-02)
#   - all_source_payer_missingness_year_x_enc_type.csv (ALLMISS-02)
#   - all_source_payer_raw_vs_harmonized.csv         (ALLMISS-03)
#   - all_source_cross_site_summary.csv              (ALLMISS-04)
#
# Usage: source("R/20_all_source_missingness.R")
#
# Dependencies: Sources 02_harmonize_payer.R which loads the full chain
#   (02 -> 01 -> 00 + utils). Provides:
#   - pcornet$ENCOUNTER (raw PAYER_TYPE fields)
#   - pcornet$DEMOGRAPHIC (SOURCE column for site identification)
#   - encounters tibble (with payer_category from harmonization)
#   - PAYER_MAPPING config (sentinel_values, unavailable_codes)
#
# Standalone script -- NOT part of the main pipeline sequence.
# ==============================================================================

source("R/02_harmonize_payer.R")  # Loads 01 -> 00 chain; provides encounters tibble with payer_category

library(dplyr)
library(lubridate)
library(glue)
library(readr)
library(stringr)
library(tidyr)

message("\n", strrep("=", 70))
message("ALL-SOURCE PAYER MISSINGNESS DIAGNOSTIC")
message("Phase 21: Generalize Phase 19 to All Sources")
message(strrep("=", 70))

# ==============================================================================
# SECTION 1: Identify HL cohort patients (D-05: HL cohort only)
# ==============================================================================

message("\n--- SECTION 1: Identify HL Cohort Patients ---")

# Source cohort builder if hl_cohort not already in environment
if (!exists("hl_cohort")) source("R/04_build_cohort.R")

hl_patients <- hl_cohort %>%
  select(ID) %>%
  distinct()

message(glue("HL patients in dataset: {format(nrow(hl_patients), big.mark=',')}"))

# Log per-site patient counts by joining to DEMOGRAPHIC
hl_patients_by_source <- hl_patients %>%
  left_join(pcornet$DEMOGRAPHIC %>% select(ID, SOURCE), by = "ID") %>%
  group_by(SOURCE) %>%
  summarise(n_patients = n_distinct(ID), .groups = "drop") %>%
  arrange(SOURCE)

message("\nHL patients per site:")
for (i in seq_len(nrow(hl_patients_by_source))) {
  r <- hl_patients_by_source[i, ]
  message(glue("  {r$SOURCE}: {format(r$n_patients, big.mark=',')} patients"))
}

# ==============================================================================
# SECTION 2: Build all-source encounter dataset with missingness flags (D-07, D-08)
# ==============================================================================

message("\n--- SECTION 2: Build All-Source Encounter Dataset with Missingness Flags ---")

# Define missingness indicators per D-08:
#   Sentinel values (NI, UN, OT) + unavailable codes (99, 9999)
missing_indicators <- c(PAYER_MAPPING$sentinel_values, PAYER_MAPPING$unavailable_codes)

message(glue("Missing indicators: {paste(missing_indicators, collapse=', ')}"))

# Join encounters to HL patients and attach SOURCE from DEMOGRAPHIC (Pitfall 1)
all_encounters <- pcornet$ENCOUNTER %>%
  inner_join(hl_patients, by = "ID") %>%
  left_join(pcornet$DEMOGRAPHIC %>% select(ID, SOURCE), by = "ID") %>%
  mutate(
    primary_missing = is.na(PAYER_TYPE_PRIMARY) |
                      nchar(trimws(PAYER_TYPE_PRIMARY)) == 0 |
                      PAYER_TYPE_PRIMARY %in% missing_indicators,
    secondary_missing = is.na(PAYER_TYPE_SECONDARY) |
                        nchar(trimws(PAYER_TYPE_SECONDARY)) == 0 |
                        PAYER_TYPE_SECONDARY %in% missing_indicators,
    both_missing = primary_missing & secondary_missing
  )

n_all_encounters <- nrow(all_encounters)
n_primary_miss <- sum(all_encounters$primary_missing)
n_secondary_miss <- sum(all_encounters$secondary_missing)
n_both_miss <- sum(all_encounters$both_missing)

message(glue("\nTotal encounters (all sites): {format(n_all_encounters, big.mark=',')}"))
message(glue("  PRIMARY missing:   {format(n_primary_miss, big.mark=',')} ({round(100 * n_primary_miss / n_all_encounters, 1)}%)"))
message(glue("  SECONDARY missing: {format(n_secondary_miss, big.mark=',')} ({round(100 * n_secondary_miss / n_all_encounters, 1)}%)"))
message(glue("  BOTH missing:      {format(n_both_miss, big.mark=',')} ({round(100 * n_both_miss / n_all_encounters, 1)}%)"))

# Per-SOURCE encounter counts
enc_by_source <- all_encounters %>%
  group_by(SOURCE) %>%
  summarise(
    n_encounters = n(),
    n_primary_missing = sum(primary_missing),
    pct_primary = round(100 * n_primary_missing / n_encounters, 1),
    .groups = "drop"
  ) %>%
  arrange(SOURCE)

message("\nEncounters per site:")
for (i in seq_len(nrow(enc_by_source))) {
  r <- enc_by_source[i, ]
  message(glue("  {r$SOURCE}: {format(r$n_encounters, big.mark=',')} encounters ({r$pct_primary}% PRIMARY missing)"))
}

# ==============================================================================
# SECTION 3: Raw PAYER_TYPE value distribution (D-01, D-04, D-09 -- ALLMISS-01)
# ==============================================================================

message("\n--- SECTION 3: Raw PAYER_TYPE Value Distribution (ALLMISS-01) ---")

# PRIMARY distribution grouped by SOURCE
primary_dist <- all_encounters %>%
  group_by(SOURCE, PAYER_TYPE_PRIMARY) %>%
  summarise(n = n(), .groups = "drop") %>%
  group_by(SOURCE) %>%
  mutate(pct = round(100 * n / sum(n), 1)) %>%
  ungroup()

# SECONDARY distribution grouped by SOURCE
secondary_dist <- all_encounters %>%
  group_by(SOURCE, PAYER_TYPE_SECONDARY) %>%
  summarise(n = n(), .groups = "drop") %>%
  group_by(SOURCE) %>%
  mutate(pct = round(100 * n / sum(n), 1)) %>%
  ungroup()

# Combine into a single CSV with field indicator
raw_value_dist <- bind_rows(
  primary_dist %>%
    rename(value = PAYER_TYPE_PRIMARY) %>%
    mutate(field = "PRIMARY"),
  secondary_dist %>%
    rename(value = PAYER_TYPE_SECONDARY) %>%
    mutate(field = "SECONDARY")
) %>%
  mutate(value = if_else(is.na(value), "<NA>", value)) %>%
  select(SOURCE, field, value, n, pct) %>%
  arrange(SOURCE, field, desc(n))

# Ensure output directory exists
output_dir <- file.path(CONFIG$output_dir, "tables")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

write_csv(raw_value_dist, file.path(output_dir, "all_source_payer_raw_value_distribution.csv"))

# Log top 3 PRIMARY values per site
message("\nTop 3 PAYER_TYPE_PRIMARY values per site:")
for (src in sort(unique(all_encounters$SOURCE))) {
  src_primary <- primary_dist %>%
    filter(SOURCE == src) %>%
    arrange(desc(n)) %>%
    head(3)
  message(glue("\n  {src}:"))
  for (j in seq_len(nrow(src_primary))) {
    r <- src_primary[j, ]
    val_label <- if_else(is.na(r$PAYER_TYPE_PRIMARY), "<NA>", r$PAYER_TYPE_PRIMARY)
    message(glue("    {val_label}: {format(r$n, big.mark=',')} ({r$pct}%)"))
  }
}

# ==============================================================================
# SECTION 4: Temporal breakdown by year (D-04, D-09 -- ALLMISS-02)
# ==============================================================================

message("\n--- SECTION 4: Temporal Breakdown by Year (ALLMISS-02) ---")

# Log and count encounters with NA ADMIT_DATE
n_no_admit_date <- sum(is.na(all_encounters$ADMIT_DATE))
message(glue("Encounters with NA ADMIT_DATE: {format(n_no_admit_date, big.mark=',')}"))

# Log and count encounters with 1900 sentinel dates
n_sentinel_dates <- sum(year(all_encounters$ADMIT_DATE) == 1900L, na.rm = TRUE)
message(glue("Encounters with 1900 sentinel ADMIT_DATE: {format(n_sentinel_dates, big.mark=',')}"))

# Filter out NA dates and 1900 sentinels
all_encounters_valid <- all_encounters %>%
  filter(!is.na(ADMIT_DATE) & year(ADMIT_DATE) != 1900L) %>%
  mutate(admit_year = year(ADMIT_DATE))

message(glue("Valid encounters for temporal analysis: {format(nrow(all_encounters_valid), big.mark=',')}"))

# Year-level breakdown grouped by SOURCE
missingness_by_year <- all_encounters_valid %>%
  group_by(SOURCE, admit_year) %>%
  summarise(
    n_encounters = n(),
    n_primary_missing = sum(primary_missing),
    n_secondary_missing = sum(secondary_missing),
    n_both_missing = sum(both_missing),
    pct_primary_missing = round(100 * n_primary_missing / n_encounters, 1),
    pct_secondary_missing = round(100 * n_secondary_missing / n_encounters, 1),
    pct_both_missing = round(100 * n_both_missing / n_encounters, 1),
    .groups = "drop"
  ) %>%
  arrange(SOURCE, admit_year)

write_csv(missingness_by_year, file.path(output_dir, "all_source_payer_missingness_by_year.csv"))

# Log per-SOURCE year range and overall primary missingness
message("\nYear ranges and overall PRIMARY missingness per site:")
for (src in sort(unique(missingness_by_year$SOURCE))) {
  src_years <- missingness_by_year %>% filter(SOURCE == src)
  total_enc <- sum(src_years$n_encounters)
  total_miss <- sum(src_years$n_primary_missing)
  overall_pct <- round(100 * total_miss / total_enc, 1)
  message(glue("  {src}: years {min(src_years$admit_year)}-{max(src_years$admit_year)}, overall PRIMARY missing: {overall_pct}%"))
}

# ==============================================================================
# SECTION 5: Encounter type breakdown (D-04, D-09 -- ALLMISS-02)
# ==============================================================================

message("\n--- SECTION 5: Encounter Type Breakdown (ALLMISS-02) ---")

# Preserve NA ENC_TYPE as "<NA>" for visibility (Pitfall 3)
all_encounters_valid <- all_encounters_valid %>%
  mutate(ENC_TYPE_LABEL = if_else(is.na(ENC_TYPE), "<NA>", ENC_TYPE))

# Encounter type breakdown grouped by SOURCE
missingness_by_enc_type <- all_encounters_valid %>%
  group_by(SOURCE, ENC_TYPE_LABEL) %>%
  summarise(
    n_encounters = n(),
    n_primary_missing = sum(primary_missing),
    n_secondary_missing = sum(secondary_missing),
    n_both_missing = sum(both_missing),
    pct_primary_missing = round(100 * n_primary_missing / n_encounters, 1),
    pct_secondary_missing = round(100 * n_secondary_missing / n_encounters, 1),
    pct_both_missing = round(100 * n_both_missing / n_encounters, 1),
    .groups = "drop"
  ) %>%
  arrange(SOURCE, desc(n_encounters))

write_csv(missingness_by_enc_type, file.path(output_dir, "all_source_payer_missingness_by_enc_type.csv"))

# Log per-SOURCE top 3 encounter types by missingness
message("\nTop 3 encounter types with highest PRIMARY missingness per site (min 10 encounters):")
for (src in sort(unique(missingness_by_enc_type$SOURCE))) {
  src_types <- missingness_by_enc_type %>%
    filter(SOURCE == src & n_encounters >= 10) %>%
    arrange(desc(pct_primary_missing)) %>%
    head(3)
  message(glue("\n  {src}:"))
  for (j in seq_len(nrow(src_types))) {
    r <- src_types[j, ]
    message(glue("    {r$ENC_TYPE_LABEL}: {r$pct_primary_missing}% ({r$n_primary_missing}/{r$n_encounters})"))
  }
}

# ==============================================================================
# SECTION 6: Year x Encounter type crosstab (D-04, D-09 -- ALLMISS-02)
# ==============================================================================

message("\n--- SECTION 6: Year x Encounter Type Crosstab (ALLMISS-02) ---")

# Year x encounter type crosstab grouped by SOURCE
missingness_year_x_enc <- all_encounters_valid %>%
  group_by(SOURCE, admit_year, ENC_TYPE_LABEL) %>%
  summarise(
    n_encounters = n(),
    n_primary_missing = sum(primary_missing),
    pct_primary_missing = round(100 * n_primary_missing / n_encounters, 1),
    .groups = "drop"
  ) %>%
  arrange(SOURCE, admit_year, ENC_TYPE_LABEL)

write_csv(missingness_year_x_enc, file.path(output_dir, "all_source_payer_missingness_year_x_enc_type.csv"))

# Log top 10 SOURCE x year x type combinations with highest PRIMARY missingness (min 10 encounters)
top_missing_combos <- missingness_year_x_enc %>%
  filter(n_encounters >= 10) %>%
  arrange(desc(pct_primary_missing)) %>%
  head(10)

message("\nTop 10 SOURCE x year x encounter type combinations with highest PRIMARY missingness (min 10 encounters):")
for (i in seq_len(nrow(top_missing_combos))) {
  r <- top_missing_combos[i, ]
  message(glue("  {r$SOURCE} {r$admit_year} {r$ENC_TYPE_LABEL}: {r$n_primary_missing}/{r$n_encounters} ({r$pct_primary_missing}%) missing"))
}

# ==============================================================================
# SECTION 7: Raw vs harmonized comparison (D-04, D-09 -- ALLMISS-03)
# ==============================================================================

message("\n--- SECTION 7: Raw vs Harmonized Comparison (ALLMISS-03) ---")

# Get encounter-level harmonized categories from the `encounters` tibble
# (produced by 02_harmonize_payer.R sourced in dependencies)
all_encounters_harmonized <- encounters %>%
  inner_join(hl_patients, by = "ID") %>%
  left_join(pcornet$DEMOGRAPHIC %>% select(ID, SOURCE), by = "ID") %>%
  filter(!is.na(ADMIT_DATE) & year(ADMIT_DATE) != 1900L) %>%
  mutate(
    admit_year = year(ADMIT_DATE),
    # Harmonized missingness: payer_category is NA, Unknown, or Unavailable
    harmonized_missing = is.na(payer_category) |
                         payer_category %in% c("Unknown", "Unavailable"),
    # Raw primary missingness (same logic as Section 2)
    primary_missing = is.na(PAYER_TYPE_PRIMARY) |
                      nchar(trimws(PAYER_TYPE_PRIMARY)) == 0 |
                      PAYER_TYPE_PRIMARY %in% missing_indicators
  )

# Per-SOURCE overall comparison
overall_comparison <- all_encounters_harmonized %>%
  group_by(SOURCE) %>%
  summarise(
    n_encounters = n(),
    n_raw_primary_missing = sum(primary_missing),
    pct_raw_primary = round(100 * n_raw_primary_missing / n_encounters, 1),
    n_harmonized_missing = sum(harmonized_missing),
    pct_harmonized = round(100 * n_harmonized_missing / n_encounters, 1),
    .groups = "drop"
  ) %>%
  mutate(year = "OVERALL")

# Per-SOURCE per-year comparison
yearly_comparison <- all_encounters_harmonized %>%
  group_by(SOURCE, admit_year) %>%
  summarise(
    n_encounters = n(),
    n_raw_primary_missing = sum(primary_missing),
    pct_raw_primary = round(100 * n_raw_primary_missing / n_encounters, 1),
    n_harmonized_missing = sum(harmonized_missing),
    pct_harmonized = round(100 * n_harmonized_missing / n_encounters, 1),
    .groups = "drop"
  ) %>%
  mutate(year = as.character(admit_year)) %>%
  select(-admit_year)

# Combine overall + per-year
raw_vs_harmonized <- bind_rows(
  overall_comparison %>% select(SOURCE, year, n_encounters, n_raw_primary_missing, pct_raw_primary, n_harmonized_missing, pct_harmonized),
  yearly_comparison %>% select(SOURCE, year, n_encounters, n_raw_primary_missing, pct_raw_primary, n_harmonized_missing, pct_harmonized)
) %>%
  arrange(SOURCE, year)

write_csv(raw_vs_harmonized, file.path(output_dir, "all_source_payer_raw_vs_harmonized.csv"))

# Log per-SOURCE raw vs harmonized delta
message("\nPer-site raw vs harmonized comparison:")
for (i in seq_len(nrow(overall_comparison))) {
  r <- overall_comparison[i, ]
  delta <- r$pct_harmonized - r$pct_raw_primary
  message(glue("  {r$SOURCE}: raw PRIMARY missing {r$pct_raw_primary}%, harmonized missing {r$pct_harmonized}%, delta: {delta} pp"))
}

# ==============================================================================
# SECTION 8: Cross-site summary (D-02, D-03, D-10 -- ALLMISS-04)
# ==============================================================================

message("\n--- SECTION 8: Cross-Site Summary (ALLMISS-04) ---")

# Per-site summary
cross_site_summary <- all_encounters %>%
  group_by(SOURCE) %>%
  summarise(
    n_patients = n_distinct(ID),
    n_encounters = n(),
    n_primary_missing = sum(primary_missing),
    pct_primary_missing = round(100 * n_primary_missing / n_encounters, 1),
    n_secondary_missing = sum(secondary_missing),
    pct_secondary_missing = round(100 * n_secondary_missing / n_encounters, 1),
    n_both_missing = sum(both_missing),
    pct_both_missing = round(100 * n_both_missing / n_encounters, 1),
    .groups = "drop"
  ) %>%
  arrange(SOURCE)

# Add "ALL" aggregate row
overall_summary <- all_encounters %>%
  summarise(
    SOURCE = "ALL",
    n_patients = n_distinct(ID),
    n_encounters = n(),
    n_primary_missing = sum(primary_missing),
    pct_primary_missing = round(100 * n_primary_missing / n_encounters, 1),
    n_secondary_missing = sum(secondary_missing),
    pct_secondary_missing = round(100 * n_secondary_missing / n_encounters, 1),
    n_both_missing = sum(both_missing),
    pct_both_missing = round(100 * n_both_missing / n_encounters, 1),
    .groups = "drop"
  )

cross_site_summary <- bind_rows(cross_site_summary, overall_summary)

write_csv(cross_site_summary, file.path(output_dir, "all_source_cross_site_summary.csv"))

# Console output: per-site patient and encounter counts (D-10, D-03: numbers only)
message("\nPer-site patient and encounter counts:")
for (i in seq_len(nrow(cross_site_summary))) {
  r <- cross_site_summary[i, ]
  message(glue("  {r$SOURCE}: {format(r$n_patients, big.mark=',')} patients, {format(r$n_encounters, big.mark=',')} encounters"))
}

# Console output: per-site PRIMARY missingness
message("\nPer-site PRIMARY missingness:")
for (i in seq_len(nrow(cross_site_summary))) {
  r <- cross_site_summary[i, ]
  message(glue("  {r$SOURCE}: {format(r$n_primary_missing, big.mark=',')}/{format(r$n_encounters, big.mark=',')} ({r$pct_primary_missing}%) PRIMARY missing"))
}

# ==============================================================================
# SECTION 9: Console summary (D-10 -- ALLMISS-05)
# ==============================================================================

message("\n", strrep("=", 70))
message("ALL-SOURCE PAYER MISSINGNESS SUMMARY")
message(strrep("=", 70))

# Per-site patient and encounter counts
message(glue("\nTotal HL patients:    {format(nrow(hl_patients), big.mark=',')}"))
message(glue("Total encounters:     {format(n_all_encounters, big.mark=',')}"))

message("\nPer-site breakdown:")
for (i in seq_len(nrow(hl_patients_by_source))) {
  r <- hl_patients_by_source[i, ]
  enc_r <- enc_by_source %>% filter(SOURCE == r$SOURCE)
  if (nrow(enc_r) > 0) {
    message(glue("  {r$SOURCE}: {format(r$n_patients, big.mark=',')} patients, {format(enc_r$n_encounters, big.mark=',')} encounters"))
  } else {
    message(glue("  {r$SOURCE}: {format(r$n_patients, big.mark=',')} patients, 0 encounters"))
  }
}

# Overall missingness rates across all sites combined
message(glue("\nOverall missingness rates (all sites combined):"))
message(glue("  PRIMARY missing:   {round(100 * n_primary_miss / n_all_encounters, 1)}%"))
message(glue("  SECONDARY missing: {round(100 * n_secondary_miss / n_all_encounters, 1)}%"))
message(glue("  BOTH missing:      {round(100 * n_both_miss / n_all_encounters, 1)}%"))

# Per-site PRIMARY missingness rates (compact table format)
message("\nPer-site PRIMARY missingness rates:")
# Exclude the ALL row for per-site display
per_site_rows <- cross_site_summary %>% filter(SOURCE != "ALL")
for (i in seq_len(nrow(per_site_rows))) {
  r <- per_site_rows[i, ]
  flag <- if_else(r$pct_primary_missing > 50, " *** >50% ***", "")
  message(glue("  {r$SOURCE}: {r$pct_primary_missing}%{flag}"))
}

# Sites with >50% PRIMARY missingness highlighted
high_miss_sites <- per_site_rows %>% filter(pct_primary_missing > 50)
if (nrow(high_miss_sites) > 0) {
  message(glue("\nSites with >50% PRIMARY missingness: {paste(high_miss_sites$SOURCE, collapse=', ')}"))
} else {
  message("\nNo sites with >50% PRIMARY missingness found.")
}

# Per-site worst encounter type by PRIMARY missingness
message("\nWorst encounter type (PRIMARY missingness) per site (min 10 encounters):")
for (src in sort(unique(missingness_by_enc_type$SOURCE))) {
  worst <- missingness_by_enc_type %>%
    filter(SOURCE == src & n_encounters >= 10) %>%
    arrange(desc(pct_primary_missing)) %>%
    head(1)
  if (nrow(worst) > 0) {
    message(glue("  {src}: {worst$ENC_TYPE_LABEL} at {worst$pct_primary_missing}% ({worst$n_primary_missing}/{worst$n_encounters})"))
  }
}

# List of 6 CSV files written
message(glue("\nCSV files written to {output_dir}:"))
message("  - all_source_payer_raw_value_distribution.csv")
message("  - all_source_payer_missingness_by_year.csv")
message("  - all_source_payer_missingness_by_enc_type.csv")
message("  - all_source_payer_missingness_year_x_enc_type.csv")
message("  - all_source_payer_raw_vs_harmonized.csv")
message("  - all_source_cross_site_summary.csv")

message("\n", strrep("=", 70))
message("ALL-SOURCE PAYER MISSINGNESS DIAGNOSTIC COMPLETE")
message(strrep("=", 70))
