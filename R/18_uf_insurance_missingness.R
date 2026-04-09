# ==============================================================================
# 18_uf_insurance_missingness.R -- UFH payer data missingness diagnostic
# ==============================================================================
#
# Phase 19: Investigate Insurance Missingness Source UF Specifically
# Requirements: UFMISS-01, UFMISS-02, UFMISS-03, UFMISS-04
#
# Purpose: Characterize why insurance/payer data is missing for University of
#          Florida (UFH) patients in the OneFlorida+ HL cohort. Profiles both
#          raw ENCOUNTER PAYER_TYPE fields and derived harmonized categories,
#          with breakdowns by year, encounter type, and their combination.
#
# Hypothesis: Data submission gap -- certain encounter types or time periods
#             may systematically lack payer information from UF.
#
# Output: 5 CSV files in output/tables/:
#   - uf_payer_raw_value_distribution.csv
#   - uf_payer_missingness_by_year.csv
#   - uf_payer_missingness_by_enc_type.csv
#   - uf_payer_missingness_year_x_enc_type.csv
#   - uf_payer_raw_vs_harmonized.csv
#
# Usage: source("R/18_uf_insurance_missingness.R")
#
# Dependencies: Sources 02_harmonize_payer.R which loads the full chain
#   (02 -> 01 -> 00 + utils). Provides:
#   - pcornet$ENCOUNTER (raw PAYER_TYPE fields)
#   - pcornet$DEMOGRAPHIC (SOURCE column for UFH identification)
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
message("UFH PAYER MISSINGNESS DIAGNOSTIC")
message("Phase 19: Investigate Insurance Missingness Source UF Specifically")
message(strrep("=", 70))

# ==============================================================================
# SECTION 1: Identify UFH patients
# ==============================================================================

message("\n--- SECTION 1: Identify UFH Patients ---")

ufh_patients <- pcornet$DEMOGRAPHIC %>%
  filter(SOURCE == "UFH") %>%
  select(ID, SOURCE) %>%
  distinct()

message(glue("UFH patients in dataset: {format(nrow(ufh_patients), big.mark=',')}"))

# ==============================================================================
# SECTION 2: Build UFH encounter dataset with missingness flags
# ==============================================================================

message("\n--- SECTION 2: Build UFH Encounter Dataset with Missingness Flags ---")

# Define missingness indicators per D-01 to D-04:
#   Sentinel values (NI, UN, OT) + unavailable codes (99, 9999)
missing_indicators <- c(PAYER_MAPPING$sentinel_values, PAYER_MAPPING$unavailable_codes)

message(glue("Missing indicators: {paste(missing_indicators, collapse=', ')}"))

# Inner join to UFH patients and add missingness columns
ufh_encounters <- pcornet$ENCOUNTER %>%
  inner_join(ufh_patients, by = "ID") %>%
  mutate(
    primary_missing = is.na(PAYER_TYPE_PRIMARY) |
                      nchar(trimws(PAYER_TYPE_PRIMARY)) == 0 |
                      PAYER_TYPE_PRIMARY %in% missing_indicators,
    secondary_missing = is.na(PAYER_TYPE_SECONDARY) |
                        nchar(trimws(PAYER_TYPE_SECONDARY)) == 0 |
                        PAYER_TYPE_SECONDARY %in% missing_indicators,
    both_missing = primary_missing & secondary_missing
  )

n_ufh_encounters <- nrow(ufh_encounters)
n_primary_miss <- sum(ufh_encounters$primary_missing)
n_secondary_miss <- sum(ufh_encounters$secondary_missing)
n_both_miss <- sum(ufh_encounters$both_missing)

message(glue("\nTotal UFH encounters: {format(n_ufh_encounters, big.mark=',')}"))
message(glue("  PRIMARY missing:   {format(n_primary_miss, big.mark=',')} ({round(100 * n_primary_miss / n_ufh_encounters, 1)}%)"))
message(glue("  SECONDARY missing: {format(n_secondary_miss, big.mark=',')} ({round(100 * n_secondary_miss / n_ufh_encounters, 1)}%)"))
message(glue("  BOTH missing:      {format(n_both_miss, big.mark=',')} ({round(100 * n_both_miss / n_ufh_encounters, 1)}%)"))

# ==============================================================================
# SECTION 3: Raw PAYER_TYPE_PRIMARY value distribution (UFMISS-01)
# ==============================================================================

message("\n--- SECTION 3: Raw PAYER_TYPE Value Distribution (UFMISS-01) ---")

# PRIMARY distribution
primary_dist <- ufh_encounters %>%
  count(PAYER_TYPE_PRIMARY, sort = TRUE) %>%
  mutate(pct = round(100 * n / sum(n), 1))

# SECONDARY distribution
secondary_dist <- ufh_encounters %>%
  count(PAYER_TYPE_SECONDARY, sort = TRUE) %>%
  mutate(pct = round(100 * n / sum(n), 1))

# Combine into a single CSV with field indicator
raw_value_dist <- bind_rows(
  primary_dist %>%
    rename(value = PAYER_TYPE_PRIMARY) %>%
    mutate(field = "PRIMARY"),
  secondary_dist %>%
    rename(value = PAYER_TYPE_SECONDARY) %>%
    mutate(field = "SECONDARY")
) %>%
  # Replace NA values in the value column with "<NA>" for CSV readability
  mutate(value = if_else(is.na(value), "<NA>", value)) %>%
  select(field, value, n, pct)

# Ensure output directory exists
output_dir <- file.path(CONFIG$output_dir, "tables")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

write_csv(raw_value_dist, file.path(output_dir, "uf_payer_raw_value_distribution.csv"))

# Log top 5 PRIMARY values
message("\nTop 5 PAYER_TYPE_PRIMARY values for UFH:")
top5_primary <- primary_dist %>% head(5)
for (i in seq_len(nrow(top5_primary))) {
  r <- top5_primary[i, ]
  val_label <- if_else(is.na(r$PAYER_TYPE_PRIMARY), "<NA>", r$PAYER_TYPE_PRIMARY)
  message(glue("  {val_label}: {format(r$n, big.mark=',')} ({r$pct}%)"))
}

# ==============================================================================
# SECTION 4: Temporal breakdown by year (UFMISS-02, D-07)
# ==============================================================================

message("\n--- SECTION 4: Temporal Breakdown by Year (UFMISS-02) ---")

# Log and count encounters with NA ADMIT_DATE
n_no_admit_date <- sum(is.na(ufh_encounters$ADMIT_DATE))
message(glue("Encounters with NA ADMIT_DATE: {format(n_no_admit_date, big.mark=',')}"))

# Log and count encounters with 1900 sentinel dates
n_sentinel_dates <- sum(year(ufh_encounters$ADMIT_DATE) == 1900L, na.rm = TRUE)
message(glue("Encounters with 1900 sentinel ADMIT_DATE: {format(n_sentinel_dates, big.mark=',')}"))

# Filter out NA dates and 1900 sentinels
ufh_encounters_valid <- ufh_encounters %>%
  filter(!is.na(ADMIT_DATE) & year(ADMIT_DATE) != 1900L) %>%
  mutate(admit_year = year(ADMIT_DATE))

message(glue("Valid encounters for temporal analysis: {format(nrow(ufh_encounters_valid), big.mark=',')}"))

# Year-level breakdown
missingness_by_year <- ufh_encounters_valid %>%
  group_by(admit_year) %>%
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
  arrange(admit_year)

write_csv(missingness_by_year, file.path(output_dir, "uf_payer_missingness_by_year.csv"))

# Log each year's primary missingness
message("\nYear-by-year PRIMARY missingness:")
for (i in seq_len(nrow(missingness_by_year))) {
  r <- missingness_by_year[i, ]
  message(glue("  {r$admit_year}: {format(r$n_primary_missing, big.mark=',')}/{format(r$n_encounters, big.mark=',')} ({r$pct_primary_missing}%) missing"))
}

# ==============================================================================
# SECTION 5: Encounter type breakdown (UFMISS-02, D-07)
# ==============================================================================

message("\n--- SECTION 5: Encounter Type Breakdown (UFMISS-02) ---")

# Preserve NA ENC_TYPE as "<NA>" for visibility (per Pitfall 3)
ufh_encounters_valid <- ufh_encounters_valid %>%
  mutate(ENC_TYPE_LABEL = if_else(is.na(ENC_TYPE), "<NA>", ENC_TYPE))

# Encounter type breakdown
missingness_by_enc_type <- ufh_encounters_valid %>%
  group_by(ENC_TYPE_LABEL) %>%
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
  arrange(desc(n_encounters))

write_csv(missingness_by_enc_type, file.path(output_dir, "uf_payer_missingness_by_enc_type.csv"))

# Log each encounter type's missingness
message("\nEncounter type PRIMARY missingness:")
for (i in seq_len(nrow(missingness_by_enc_type))) {
  r <- missingness_by_enc_type[i, ]
  message(glue("  {r$ENC_TYPE_LABEL}: {format(r$n_primary_missing, big.mark=',')}/{format(r$n_encounters, big.mark=',')} ({r$pct_primary_missing}%) missing"))
}

# ==============================================================================
# SECTION 6: Year x Encounter Type crosstab (UFMISS-02, D-07)
# ==============================================================================

message("\n--- SECTION 6: Year x Encounter Type Crosstab (UFMISS-02) ---")

# Year x encounter type crosstab (uses ufh_encounters_valid with ENC_TYPE_LABEL already defined)
missingness_year_x_enc <- ufh_encounters_valid %>%
  group_by(admit_year, ENC_TYPE_LABEL) %>%
  summarise(
    n_encounters = n(),
    n_primary_missing = sum(primary_missing),
    pct_primary_missing = round(100 * n_primary_missing / n_encounters, 1),
    .groups = "drop"
  ) %>%
  arrange(admit_year, ENC_TYPE_LABEL)

write_csv(missingness_year_x_enc, file.path(output_dir, "uf_payer_missingness_year_x_enc_type.csv"))

# Log top 10 year x type combinations with highest missingness pct (min 10 encounters)
top_missing_combos <- missingness_year_x_enc %>%
  filter(n_encounters >= 10) %>%
  arrange(desc(pct_primary_missing)) %>%
  head(10)

message("\nTop 10 year x encounter type combinations with highest PRIMARY missingness (min 10 encounters):")
for (i in seq_len(nrow(top_missing_combos))) {
  r <- top_missing_combos[i, ]
  message(glue("  {r$admit_year} {r$ENC_TYPE_LABEL}: {r$n_primary_missing}/{r$n_encounters} ({r$pct_primary_missing}%) missing"))
}

# ==============================================================================
# SECTION 7: Raw vs Harmonized comparison (UFMISS-03, D-08)
# ==============================================================================

message("\n--- SECTION 7: Raw vs Harmonized Comparison (UFMISS-03) ---")

# Get encounter-level harmonized categories from the `encounters` tibble
# (produced by 02_harmonize_payer.R sourced in dependencies)
ufh_encounters_harmonized <- encounters %>%
  inner_join(ufh_patients, by = "ID") %>%
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

# Overall comparison (single summary row)
overall_comparison <- ufh_encounters_harmonized %>%
  summarise(
    n_encounters = n(),
    n_raw_primary_missing = sum(primary_missing),
    pct_raw_primary = round(100 * n_raw_primary_missing / n_encounters, 1),
    n_harmonized_missing = sum(harmonized_missing),
    pct_harmonized = round(100 * n_harmonized_missing / n_encounters, 1),
    .groups = "drop"
  ) %>%
  mutate(year = "OVERALL")

# Per-year comparison
yearly_comparison <- ufh_encounters_harmonized %>%
  group_by(admit_year) %>%
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
  overall_comparison %>% select(year, n_encounters, n_raw_primary_missing, pct_raw_primary, n_harmonized_missing, pct_harmonized),
  yearly_comparison %>% select(year, n_encounters, n_raw_primary_missing, pct_raw_primary, n_harmonized_missing, pct_harmonized)
)

write_csv(raw_vs_harmonized, file.path(output_dir, "uf_payer_raw_vs_harmonized.csv"))

# Log overall comparison with interpretation
message(glue("\nOverall raw vs harmonized comparison:"))
message(glue("  Raw PRIMARY missing:     {overall_comparison$n_raw_primary_missing}/{overall_comparison$n_encounters} ({overall_comparison$pct_raw_primary}%)"))
message(glue("  Harmonized missing:      {overall_comparison$n_harmonized_missing}/{overall_comparison$n_encounters} ({overall_comparison$pct_harmonized}%)"))

delta <- overall_comparison$pct_harmonized - overall_comparison$pct_raw_primary
if (abs(delta) < 0.5) {
  message(glue("  Interpretation: Raw and harmonized missingness rates are similar (delta: {delta} pp)."))
  message("  This suggests the gap originates at data SUBMISSION, not harmonization.")
} else if (delta > 0) {
  message(glue("  Interpretation: Harmonized missingness is HIGHER than raw by {delta} pp."))
  message("  Harmonization is increasing apparent missingness (sentinel fallback to Unknown/Unavailable).")
} else {
  message(glue("  Interpretation: Harmonized missingness is LOWER than raw by {abs(delta)} pp."))
  message("  Harmonization is recovering some payer info (e.g., SECONDARY fallback for sentinel PRIMARY).")
}

# ==============================================================================
# SECTION 8: Console summary (D-14, exploratory)
# ==============================================================================

message("\n", strrep("=", 70))
message("UFH PAYER MISSINGNESS SUMMARY")
message(strrep("=", 70))

message(glue("\nTotal UFH patients:     {format(nrow(ufh_patients), big.mark=',')}"))
message(glue("Total UFH encounters:   {format(n_ufh_encounters, big.mark=',')}"))
message(glue("  Excluded: {format(n_no_admit_date, big.mark=',')} with no ADMIT_DATE"))
message(glue("  Excluded: {format(n_sentinel_dates, big.mark=',')} with 1900 sentinel ADMIT_DATE"))
message(glue("  Valid for temporal analysis: {format(nrow(ufh_encounters_valid), big.mark=',')}"))

message(glue("\nOverall missingness rates (all UFH encounters):"))
message(glue("  PRIMARY missing:   {round(100 * n_primary_miss / n_ufh_encounters, 1)}%"))
message(glue("  SECONDARY missing: {round(100 * n_secondary_miss / n_ufh_encounters, 1)}%"))
message(glue("  BOTH missing:      {round(100 * n_both_miss / n_ufh_encounters, 1)}%"))

# Year range with highest primary missingness (>50%)
high_miss_years <- missingness_by_year %>%
  filter(pct_primary_missing > 50)

if (nrow(high_miss_years) > 0) {
  year_range <- glue("{min(high_miss_years$admit_year)}-{max(high_miss_years$admit_year)}")
  message(glue("\nYears with >50% PRIMARY missingness: {year_range}"))
  message(glue("  ({nrow(high_miss_years)} year(s): {paste(high_miss_years$admit_year, collapse=', ')})"))
} else {
  message("\nNo years with >50% PRIMARY missingness found.")
}

# Encounter type with highest primary missingness rate (minimum 10 encounters)
worst_enc_type <- missingness_by_enc_type %>%
  filter(n_encounters >= 10) %>%
  arrange(desc(pct_primary_missing)) %>%
  head(1)

if (nrow(worst_enc_type) > 0) {
  message(glue("\nEncounter type with highest PRIMARY missingness (min 10 encounters):"))
  message(glue("  {worst_enc_type$ENC_TYPE_LABEL}: {worst_enc_type$pct_primary_missing}% ({worst_enc_type$n_primary_missing}/{worst_enc_type$n_encounters})"))
}

# Raw vs harmonized delta
message(glue("\nRaw vs Harmonized delta: {delta} percentage points"))

# List of CSV files written
message(glue("\nCSV files written to {output_dir}:"))
message("  - uf_payer_raw_value_distribution.csv")
message("  - uf_payer_missingness_by_year.csv")
message("  - uf_payer_missingness_by_enc_type.csv")
message("  - uf_payer_missingness_year_x_enc_type.csv")
message("  - uf_payer_raw_vs_harmonized.csv")

message("\n", strrep("=", 70))
message("UFH PAYER MISSINGNESS DIAGNOSTIC COMPLETE")
message(strrep("=", 70))
