# ==============================================================================
# 66_all_site_duplicate_dates.R -- All-site duplicate date investigation
# ==============================================================================
#
# Purpose: All-site duplicate date investigation: extends original FLM-only analysis
#   to all 5 sites, identifying same-date duplicate encounters.
#
# Inputs:
#   - get_pcornet_table("DEMOGRAPHIC"): SOURCE column for site identification
#   - get_pcornet_table("ENCOUNTER"): all encounter records
#
# Outputs: 5 CSV files in output/tables/:
#   - all_site_patient_duplicate_summary.csv, all_site_date_level_duplicate_detail.csv
#   - all_site_duplicate_aggregate_summary.csv, all_site_source_payer_completeness.csv
#   - all_site_cross_site_summary.csv
#
# Dependencies: Sources R/00_config.R (CONFIG, PAYER_MAPPING, is_missing_payer utility).
#
# Requirements: ALLDUP-01 through ALLDUP-05 (Phase 22).
#
# Standalone script -- NOT part of the main pipeline sequence.
# ==============================================================================

source("R/00_config.R")
library(dplyr)
library(lubridate)
library(glue)
library(readr)
library(stringr)
library(janitor)
library(tidyr)

# Load tables if not already loaded (RDS mode)
if (!USE_DUCKDB && !exists("pcornet")) source("R/01_load_pcornet.R")
# DuckDB mode: open connection if needed
if (USE_DUCKDB && !exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}

# ==============================================================================
# Missingness Definition (Phase 19/20 pattern, D-04)
# ==============================================================================
# is_missing_payer() provided by R/utils_payer.R (via R/00_config.R)

# ==============================================================================
# SECTION 1: Identify all patients per site from DEMOGRAPHIC (D-01, D-02) ---- ----
# ==============================================================================
# D-01: Analyze ALL patients per site from DEMOGRAPHIC (not just HL cohort)
# D-02: Patients assigned to sites via DEMOGRAPHIC.SOURCE
# WHY duplicate dates matter:
#   - Same-date encounters from different sources may represent the same clinical
#     event recorded twice (true duplicates), inflating encounter counts
#   - Or they may represent distinct legitimate encounters on the same date
#     (e.g., lab visit + clinic visit)
#   - Investigation needed to determine which pattern dominates at each site
# WHY FLM was original focus:
#   - Florida Medicaid (FLM) had the highest duplicate rate in initial analysis
#   - FLM is claims-only data source (not EHR), prone to billing duplicates

message(glue("\n{strrep('=', 70)}"))
message("ALL-SITE DUPLICATE DATE INVESTIGATION")
message("Phase 22: Generalize Phase 20 to All Sites")
message(glue("{strrep('=', 70)}\n"))

message("--- SECTION 1: Identify All Patients per Site from DEMOGRAPHIC ---")

# Phase 32: Use get_pcornet_table() and materialize for in-memory operations
demographic_tbl <- get_pcornet_table("DEMOGRAPHIC") %>% materialize()

all_sites <- sort(unique(demographic_tbl$SOURCE))
message(glue("Sites found in DEMOGRAPHIC.SOURCE: {paste(all_sites, collapse=', ')}"))
message(glue("Total unique sites: {length(all_sites)}"))

# Log N patients per site
for (site in all_sites) {
  n_site <- demographic_tbl %>%
    filter(SOURCE == site) %>%
    n_distinct(.$ID)
  message(glue("  {site}: {format(n_site, big.mark=',')} patients"))
}

total_patients <- n_distinct(demographic_tbl$ID)
message(glue("\nTotal patients across all sites: {format(total_patients, big.mark=',')}"))

# ==============================================================================
# SECTION 2: Build all-site encounter dataset (D-02, D-03) ----
# ==============================================================================
# D-02: Examine ENCOUNTER.SOURCE within each patient's encounters
# CRITICAL: Handle SOURCE column collision (ENCOUNTER.SOURCE vs DEMOGRAPHIC.SOURCE)
# Pattern from Phase 21 SUMMARY: rename ENCOUNTER.SOURCE, then join DEMOGRAPHIC.SOURCE

message(glue("\n--- SECTION 2: Build All-Site Encounter Dataset ---"))

# Phase 32: Use get_pcornet_table() and materialize after join
all_encounters <- get_pcornet_table("ENCOUNTER") %>%
  rename(ENCOUNTER_SOURCE = SOURCE) %>%
  left_join(demographic_tbl %>% select(ID, SOURCE), by = "ID") %>%
  rename(SITE = SOURCE) %>%
  materialize()

# Handle encounters with no DEMOGRAPHIC record
n_no_site <- sum(is.na(all_encounters$SITE))
if (n_no_site > 0) {
  message(glue("  WARNING: {format(n_no_site, big.mark=',')} encounters have no DEMOGRAPHIC record (NA SITE)"))
  all_encounters <- all_encounters %>%
    mutate(SITE = if_else(is.na(SITE), "<No Site>", SITE))
}

# Log N encounters per SITE
enc_per_site <- all_encounters %>%
  group_by(SITE) %>%
  summarise(n_encounters = n(), .groups = "drop") %>%
  arrange(SITE)

message(glue("\nEncounters per SITE:"))
for (i in seq_len(nrow(enc_per_site))) {
  r <- enc_per_site[i, ]
  message(glue("  {r$SITE}: {format(r$n_encounters, big.mark=',')} encounters"))
}

# Log NA ENCOUNTER_SOURCE counts per SITE
na_enc_source_per_site <- all_encounters %>%
  group_by(SITE) %>%
  summarise(
    n_total = n(),
    n_na_enc_source = sum(is.na(ENCOUNTER_SOURCE)),
    pct_na = round(100 * n_na_enc_source / n_total, 1),
    .groups = "drop"
  )

message(glue("\nNA ENCOUNTER_SOURCE per SITE:"))
for (i in seq_len(nrow(na_enc_source_per_site))) {
  r <- na_enc_source_per_site[i, ]
  message(glue("  {r$SITE}: {format(r$n_na_enc_source, big.mark=',')} ({r$pct_na}%)"))
}

# Log unique ENCOUNTER_SOURCE values per SITE
message(glue("\nUnique ENCOUNTER_SOURCE values per SITE:"))
for (site in sort(unique(all_encounters$SITE))) {
  site_enc_sources <- all_encounters %>%
    filter(SITE == site) %>%
    pull(ENCOUNTER_SOURCE) %>%
    na.omit() %>%
    unique() %>%
    sort()
  message(glue("  {site}: {paste(site_enc_sources, collapse=', ')}"))
}

# ==============================================================================
# SECTION 3: Same-date duplicate detection (D-03, ALLDUP-01) ----
# ==============================================================================
# D-03: Same duplicate definitions as Phase 20 -- group by ID + date only
#        (not ENC_TYPE), check ADMIT_DATE primary + DISCHARGE_DATE secondary

message(glue("\n--- SECTION 3: Same-Date Duplicate Detection ---"))

# Parse dates -- ENCOUNTER columns are all col_character()
all_encounters <- all_encounters %>%
  mutate(
    admit_date_parsed = as.Date(ADMIT_DATE, format = "%Y-%m-%d"),
    discharge_date_parsed = as.Date(DISCHARGE_DATE, format = "%Y-%m-%d")
  )

# Check if standard format parsing succeeded
n_admit_raw <- sum(!is.na(all_encounters$ADMIT_DATE) & all_encounters$ADMIT_DATE != "")
n_admit_parsed <- sum(!is.na(all_encounters$admit_date_parsed))
admit_parse_rate <- if (n_admit_raw > 0) round(100 * n_admit_parsed / n_admit_raw, 1) else 100

if (n_admit_raw > 0 && admit_parse_rate < 50) {
  message(glue("  Standard date parse rate only {admit_parse_rate}% -- trying parse_pcornet_date()"))
  if (file.exists("R/utils/utils_dates.R")) {
    source("R/utils/utils_dates.R")
    all_encounters <- all_encounters %>%
      mutate(
        admit_date_parsed = parse_pcornet_date(ADMIT_DATE),
        discharge_date_parsed = parse_pcornet_date(DISCHARGE_DATE)
      )
    n_admit_parsed <- sum(!is.na(all_encounters$admit_date_parsed))
    message(glue("  After parse_pcornet_date: {format(n_admit_parsed, big.mark=',')} parsed"))
  } else {
    message("  utils_dates.R not found -- continuing with standard parsing")
  }
}

n_no_admit_date <- sum(is.na(all_encounters$admit_date_parsed))
message(glue("ADMIT_DATE parse rate: {admit_parse_rate}% ({format(n_admit_parsed, big.mark=',')} of {format(n_admit_raw, big.mark=',')} non-empty values)"))
message(glue("ADMIT_DATE NA after parsing: {format(n_no_admit_date, big.mark=',')}"))

# --- ADMIT_DATE same-date duplicates (per SITE) ---
admit_date_dupes <- all_encounters %>%
  filter(!is.na(admit_date_parsed)) %>%
  add_count(SITE, ID, admit_date_parsed, name = "n_encounters_same_date") %>%
  filter(n_encounters_same_date > 1) %>%
  arrange(SITE, ID, admit_date_parsed, ENCOUNTER_SOURCE)

# Log per-SITE duplicate counts
message(glue("\nADMIT_DATE same-date duplicates per SITE:"))
for (site in sort(unique(all_encounters$SITE))) {
  site_dupes <- admit_date_dupes %>% filter(SITE == site)
  n_dupe_rows <- nrow(site_dupes)
  n_dupe_patient_dates <- site_dupes %>% distinct(ID, admit_date_parsed) %>% nrow()
  n_dupe_patients <- n_distinct(site_dupes$ID)
  message(glue("  {site}: {format(n_dupe_rows, big.mark=',')} dupe rows, {format(n_dupe_patient_dates, big.mark=',')} patient-dates, {format(n_dupe_patients, big.mark=',')} patients"))
}

# --- DISCHARGE_DATE same-date duplicates (per SITE) ---
discharge_date_dupes <- all_encounters %>%
  filter(!is.na(discharge_date_parsed)) %>%
  add_count(SITE, ID, discharge_date_parsed, name = "n_encounters_same_date") %>%
  filter(n_encounters_same_date > 1)

message(glue("\nDISCHARGE_DATE same-date duplicates per SITE:"))
for (site in sort(unique(all_encounters$SITE))) {
  site_discharge_dupes <- discharge_date_dupes %>% filter(SITE == site)
  n_discharge_patient_dates <- site_discharge_dupes %>% distinct(ID, discharge_date_parsed) %>% nrow()
  message(glue("  {site}: {format(n_discharge_patient_dates, big.mark=',')} patient-dates"))
}

# ==============================================================================
# SECTION 4: Exact row duplicates (D-03, ALLDUP-01) ----
# ==============================================================================

message(glue("\n--- SECTION 4: Exact Row Duplicate Detection ---"))

# Exact row duplicates (all original columns, excluding parsed date columns and SITE)
exact_dupes <- all_encounters %>%
  select(-admit_date_parsed, -discharge_date_parsed, -SITE) %>%
  get_dupes()

# Near-exact duplicates (same on all columns except ENCOUNTERID)
near_exact_dupes <- all_encounters %>%
  select(-admit_date_parsed, -discharge_date_parsed, -SITE, -ENCOUNTERID) %>%
  get_dupes()

# Log counts per SITE by joining back to SITE assignment
if (nrow(exact_dupes) > 0) {
  exact_dupes_with_site <- exact_dupes %>%
    left_join(demographic_tbl %>% select(ID, SOURCE), by = "ID") %>%
    rename(SITE = SOURCE) %>%
    mutate(SITE = if_else(is.na(SITE), "<No Site>", SITE))

  message(glue("Exact row duplicates total: {format(nrow(exact_dupes), big.mark=',')} rows"))
  for (site in sort(unique(exact_dupes_with_site$SITE))) {
    n <- exact_dupes_with_site %>% filter(SITE == site) %>% nrow()
    message(glue("  {site}: {format(n, big.mark=',')} rows"))
  }
} else {
  exact_dupes_with_site <- tibble()
  message("No exact row duplicates found across any site")
}

if (nrow(near_exact_dupes) > 0) {
  near_exact_dupes_with_site <- near_exact_dupes %>%
    left_join(demographic_tbl %>% select(ID, SOURCE), by = "ID") %>%
    rename(SITE = SOURCE) %>%
    mutate(SITE = if_else(is.na(SITE), "<No Site>", SITE))

  message(glue("\nNear-exact duplicates (excl. ENCOUNTERID) total: {format(nrow(near_exact_dupes), big.mark=',')} rows"))
  for (site in sort(unique(near_exact_dupes_with_site$SITE))) {
    n <- near_exact_dupes_with_site %>% filter(SITE == site) %>% nrow()
    message(glue("  {site}: {format(n, big.mark=',')} rows"))
  }
} else {
  near_exact_dupes_with_site <- tibble()
  message("No near-exact duplicates found (excluding ENCOUNTERID)")
}

# ==============================================================================
# SECTION 5: Multi-source date identification (D-02, ALLDUP-02) ----
# ==============================================================================

message(glue("\n--- SECTION 5: Multi-Source Date Identification ---"))

# Per-patient-date summary from admit date duplicates
patient_date_summary <- admit_date_dupes %>%
  group_by(SITE, ID, admit_date_parsed) %>%
  summarize(
    n_encounters = n(),
    n_sources = n_distinct(ENCOUNTER_SOURCE, na.rm = TRUE),
    sources = paste(sort(unique(na.omit(ENCOUNTER_SOURCE))), collapse = ", "),
    enc_types = paste(sort(unique(na.omit(ENC_TYPE))), collapse = ", "),
    n_enc_types = n_distinct(ENC_TYPE, na.rm = TRUE),
    .groups = "drop"
  )

multi_source_dates <- patient_date_summary %>%
  filter(n_sources > 1)

message(glue("Total patient-dates with duplicates: {format(nrow(patient_date_summary), big.mark=',')}"))
message(glue("Patient-dates with multiple ENCOUNTER_SOURCEs: {format(nrow(multi_source_dates), big.mark=',')}"))

# Breakdown per SITE: same-source vs multi-source duplicates
message(glue("\nBreakdown per SITE (same-source vs multi-source duplicates):"))
for (site in sort(unique(patient_date_summary$SITE))) {
  site_summary <- patient_date_summary %>% filter(SITE == site)
  n_same <- site_summary %>% filter(n_sources <= 1) %>% nrow()
  n_multi <- site_summary %>% filter(n_sources > 1) %>% nrow()
  message(glue("  {site}: {format(nrow(site_summary), big.mark=',')} dupe patient-dates | same-source: {format(n_same, big.mark=',')} | multi-source: {format(n_multi, big.mark=',')}"))

  # Within same-source: same ENC_TYPE vs different ENC_TYPE
  same_source <- site_summary %>% filter(n_sources <= 1)
  if (nrow(same_source) > 0) {
    same_enc <- same_source %>% filter(n_enc_types == 1) %>% nrow()
    diff_enc <- same_source %>% filter(n_enc_types > 1) %>% nrow()
    message(glue("    Same-source, same ENC_TYPE (potential true duplication): {format(same_enc, big.mark=',')}"))
    message(glue("    Same-source, different ENC_TYPE (clinically valid): {format(diff_enc, big.mark=',')}"))
  }
}

# Log most common source combinations per SITE (top 5 per site)
message(glue("\nMost common multi-source combinations per SITE (top 5):"))
for (site in sort(unique(multi_source_dates$SITE))) {
  site_multi <- multi_source_dates %>% filter(SITE == site)
  if (nrow(site_multi) == 0) {
    message(glue("  {site}: (none)"))
    next
  }
  source_combos <- site_multi %>%
    count(sources, sort = TRUE) %>%
    head(5)
  message(glue("  {site}:"))
  for (i in seq_len(nrow(source_combos))) {
    message(glue("    {source_combos$sources[i]}: {format(source_combos$n[i], big.mark=',')} patient-dates"))
  }
}

# ==============================================================================
# SECTION 6: Payer completeness comparison (D-08, D-09, ALLDUP-03) ----
# ==============================================================================
# D-08: Per-site source-preference recommendations
# D-09: Each site gets its own recommendation based on its own payer completeness rates

message(glue("\n--- SECTION 6: Payer Completeness Comparison Across Sources ---"))

# Get multi-source encounter rows via semi_join on multi_source_dates
multi_source_encounters <- admit_date_dupes %>%
  semi_join(multi_source_dates, by = c("SITE", "ID", "admit_date_parsed"))

# Per-SITE, per-ENCOUNTER_SOURCE completeness
source_completeness_list <- list()
site_recommendations <- tibble(
  SITE = character(),
  recommended_source = character(),
  recommended_source_completeness_pct = double()
)

for (site in sort(unique(all_encounters$SITE))) {
  site_multi_enc <- multi_source_encounters %>% filter(SITE == site)

  if (nrow(site_multi_enc) == 0) {
    message(glue("\n  {site}: No multi-source dates found -- skipping payer completeness"))
    next
  }

  message(glue("\n  {site}: {format(nrow(site_multi_enc), big.mark=',')} multi-source encounter rows"))

  site_completeness <- site_multi_enc %>%
    filter(!is.na(ENCOUNTER_SOURCE)) %>%
    group_by(ENCOUNTER_SOURCE) %>%
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
    mutate(SITE = site) %>%
    arrange(desc(pct_primary_present))

  source_completeness_list[[site]] <- site_completeness

  # Log per-source completeness for this site
  for (i in seq_len(nrow(site_completeness))) {
    row <- site_completeness[i, ]
    message(glue("    ENCOUNTER_SOURCE={row$ENCOUNTER_SOURCE}: {row$n_encounters} encounters | Primary: {row$pct_primary_present}% | Secondary: {row$pct_secondary_present}% | Either: {row$pct_either_present}%"))
  }

  # Generate per-site recommendation
  if (nrow(site_completeness) >= 2) {
    best <- site_completeness[1, ]
    second <- site_completeness[2, ]
    message(glue("    RECOMMENDATION for {site}: Prefer ENCOUNTER_SOURCE='{best$ENCOUNTER_SOURCE}' (Primary: {best$pct_primary_present}% vs {second$ENCOUNTER_SOURCE} at {second$pct_primary_present}%)"))
    site_recommendations <- bind_rows(site_recommendations, tibble(
      SITE = site,
      recommended_source = best$ENCOUNTER_SOURCE,
      recommended_source_completeness_pct = best$pct_primary_present
    ))
  } else if (nrow(site_completeness) == 1) {
    message(glue("    RECOMMENDATION for {site}: Only one source ({site_completeness$ENCOUNTER_SOURCE[1]}) -- recommendation trivial"))
    site_recommendations <- bind_rows(site_recommendations, tibble(
      SITE = site,
      recommended_source = site_completeness$ENCOUNTER_SOURCE[1],
      recommended_source_completeness_pct = site_completeness$pct_primary_present[1]
    ))
  }
}

# Combine all source completeness data
source_completeness <- bind_rows(source_completeness_list)

# ==============================================================================
# SECTION 7: Build and write CSV outputs (D-05, D-06, D-07, ALLDUP-04, ALLDUP-05) ----
# ==============================================================================
# D-05: 5 CSV files with SITE column + cross-site summary
# D-06: all_site_ prefix
# D-07: output to output/tables/

message(glue("\n--- SECTION 7: Writing CSV Outputs ---"))

output_dir <- file.path(CONFIG$output_dir, "tables")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# --- CSV 1: Patient-level duplicate summary (all_site_patient_duplicate_summary.csv) ---
# Pre-compute per patient-date stats (per SITE)
patient_date_stats <- all_encounters %>%
  filter(!is.na(admit_date_parsed)) %>%
  group_by(SITE, ID, admit_date_parsed) %>%
  summarize(
    n_enc_this_date = n(),
    n_sources_this_date = n_distinct(ENCOUNTER_SOURCE, na.rm = TRUE),
    .groups = "drop"
  )

patient_summary <- patient_date_stats %>%
  group_by(SITE, ID) %>%
  summarize(
    n_unique_dates = n(),
    n_total_encounters = sum(n_enc_this_date),
    n_duplicate_dates = sum(n_enc_this_date > 1),
    n_multi_source_dates = sum(n_sources_this_date > 1),
    .groups = "drop"
  )

# Add per-patient payer completeness and source info
patient_payer <- all_encounters %>%
  filter(!is.na(admit_date_parsed)) %>%
  group_by(SITE, ID) %>%
  summarize(
    sources_in_encounters = paste(sort(unique(na.omit(ENCOUNTER_SOURCE))), collapse = ", "),
    pct_primary_present = round(100 * mean(!is_missing_payer(PAYER_TYPE_PRIMARY)), 1),
    pct_secondary_present = round(100 * mean(!is_missing_payer(PAYER_TYPE_SECONDARY)), 1),
    .groups = "drop"
  )

patient_summary <- patient_summary %>%
  left_join(patient_payer, by = c("SITE", "ID")) %>%
  arrange(SITE, desc(n_multi_source_dates), desc(n_duplicate_dates))

write_csv(patient_summary, file.path(output_dir, "all_site_patient_duplicate_summary.csv"))
message(glue("  Written: all_site_patient_duplicate_summary.csv ({format(nrow(patient_summary), big.mark=',')} patients)"))

# --- CSV 2: Date-level detail for multi-source encounters (all_site_date_level_duplicate_detail.csv) ---
if (nrow(multi_source_encounters) > 0) {
  date_detail <- multi_source_encounters %>%
    select(SITE, ID, admit_date_parsed, ENCOUNTER_SOURCE, ENC_TYPE, ENCOUNTERID,
           ADMIT_TIME, DISCHARGE_DATE, DISCHARGE_TIME,
           PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY) %>%
    mutate(
      primary_missing = is_missing_payer(PAYER_TYPE_PRIMARY),
      secondary_missing = is_missing_payer(PAYER_TYPE_SECONDARY)
    ) %>%
    arrange(SITE, ID, admit_date_parsed, ENCOUNTER_SOURCE)
} else {
  # Write empty data frame with expected columns
  date_detail <- tibble(
    SITE = character(),
    ID = character(),
    admit_date_parsed = as.Date(character()),
    ENCOUNTER_SOURCE = character(),
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

write_csv(date_detail, file.path(output_dir, "all_site_date_level_duplicate_detail.csv"))
message(glue("  Written: all_site_date_level_duplicate_detail.csv ({format(nrow(date_detail), big.mark=',')} rows)"))

# --- CSV 3: Aggregate summary per SITE (all_site_duplicate_aggregate_summary.csv) ---
aggregate_rows <- list()

for (site in sort(unique(all_encounters$SITE))) {
  site_enc <- all_encounters %>% filter(SITE == site)
  site_pds <- patient_date_stats %>% filter(SITE == site)
  n_site_patients <- demographic_tbl %>% filter(SOURCE == site) %>% n_distinct(.$ID)

  # Exact/near-exact counts for this site
  n_exact_site <- if (nrow(exact_dupes_with_site) > 0) {
    exact_dupes_with_site %>% filter(SITE == site) %>% nrow()
  } else { 0 }
  n_near_exact_site <- if (nrow(near_exact_dupes_with_site) > 0) {
    near_exact_dupes_with_site %>% filter(SITE == site) %>% nrow()
  } else { 0 }

  # Discharge date duplicate count for this site
  n_discharge_dupe_site <- discharge_date_dupes %>%
    filter(SITE == site) %>%
    distinct(ID, discharge_date_parsed) %>%
    nrow()

  # Multi-source dates for this site
  n_multi_source_site <- multi_source_dates %>% filter(SITE == site) %>% nrow()

  # NA ENCOUNTER_SOURCE for this site
  n_na_enc_source_site <- na_enc_source_per_site %>%
    filter(SITE == site) %>%
    pull(n_na_enc_source)
  if (length(n_na_enc_source_site) == 0) n_na_enc_source_site <- 0

  site_agg <- tibble(
    SITE = site,
    metric = c(
      "Total patients (DEMOGRAPHIC)",
      "Total encounters",
      "Encounters with valid ADMIT_DATE",
      "Encounters with NA ADMIT_DATE",
      "Encounters with NA ENCOUNTER_SOURCE",
      "Unique patient-dates",
      "Patient-dates with same-date duplicates",
      "Patient-dates with multiple SOURCEs",
      "Exact row duplicates",
      "Near-exact duplicates",
      "DISCHARGE_DATE same-date duplicate patient-dates"
    ),
    value = c(
      n_site_patients,
      nrow(site_enc),
      sum(!is.na(site_enc$admit_date_parsed)),
      sum(is.na(site_enc$admit_date_parsed)),
      n_na_enc_source_site,
      nrow(site_pds),
      sum(site_pds$n_enc_this_date > 1),
      n_multi_source_site,
      n_exact_site,
      n_near_exact_site,
      n_discharge_dupe_site
    )
  )

  # Append source completeness rows if available for this site
  if (site %in% names(source_completeness_list)) {
    sc <- source_completeness_list[[site]]
    sc_rows <- sc %>%
      mutate(
        metric = glue("ENCOUNTER_SOURCE={ENCOUNTER_SOURCE}: primary payer present %"),
        value = pct_primary_present
      ) %>%
      select(metric, value) %>%
      mutate(SITE = site)
    site_agg <- bind_rows(site_agg, sc_rows)
  }

  aggregate_rows[[site]] <- site_agg
}

aggregate_summary <- bind_rows(aggregate_rows)
write_csv(aggregate_summary, file.path(output_dir, "all_site_duplicate_aggregate_summary.csv"))
message(glue("  Written: all_site_duplicate_aggregate_summary.csv ({nrow(aggregate_summary)} metrics across {length(unique(aggregate_summary$SITE))} sites)"))

# --- CSV 4: Source payer completeness per SITE (all_site_source_payer_completeness.csv) ---
if (nrow(source_completeness) > 0) {
  source_completeness_out <- source_completeness %>%
    select(SITE, ENCOUNTER_SOURCE, n_encounters, n_primary_present, pct_primary_present,
           n_secondary_present, pct_secondary_present, n_both_present, pct_both_present,
           n_either_present, pct_either_present) %>%
    arrange(SITE, desc(pct_primary_present))
  write_csv(source_completeness_out, file.path(output_dir, "all_site_source_payer_completeness.csv"))
  message(glue("  Written: all_site_source_payer_completeness.csv ({nrow(source_completeness_out)} rows)"))
} else {
  # Write empty file with expected columns
  empty_sc <- tibble(
    SITE = character(), ENCOUNTER_SOURCE = character(),
    n_encounters = integer(), n_primary_present = integer(), pct_primary_present = double(),
    n_secondary_present = integer(), pct_secondary_present = double(),
    n_both_present = integer(), pct_both_present = double(),
    n_either_present = integer(), pct_either_present = double()
  )
  write_csv(empty_sc, file.path(output_dir, "all_site_source_payer_completeness.csv"))
  message("  Written: all_site_source_payer_completeness.csv (empty -- no multi-source encounters)")
}

# --- CSV 5: Cross-site summary (all_site_cross_site_summary.csv) ---
cross_site_rows <- list()

for (site in sort(unique(all_encounters$SITE))) {
  site_enc <- all_encounters %>% filter(SITE == site)
  site_pds <- patient_date_stats %>% filter(SITE == site)
  n_site_patients <- demographic_tbl %>% filter(SOURCE == site) %>% n_distinct(.$ID)

  n_unique_dates <- nrow(site_pds)
  n_dupe_pd <- sum(site_pds$n_enc_this_date > 1)
  pct_dup_rate <- if (n_unique_dates > 0) round(100 * n_dupe_pd / n_unique_dates, 2) else 0
  n_multi_src <- multi_source_dates %>% filter(SITE == site) %>% nrow()
  pct_multi_of_dupes <- if (n_dupe_pd > 0) round(100 * n_multi_src / n_dupe_pd, 2) else 0

  n_exact_site <- if (nrow(exact_dupes_with_site) > 0) {
    exact_dupes_with_site %>% filter(SITE == site) %>% nrow()
  } else { 0 }
  n_near_exact_site <- if (nrow(near_exact_dupes_with_site) > 0) {
    near_exact_dupes_with_site %>% filter(SITE == site) %>% nrow()
  } else { 0 }

  # Get recommendation for this site
  site_rec <- site_recommendations %>% filter(SITE == site)
  rec_source <- if (nrow(site_rec) > 0) site_rec$recommended_source[1] else NA_character_
  rec_pct <- if (nrow(site_rec) > 0) site_rec$recommended_source_completeness_pct[1] else NA_real_

  cross_site_rows[[site]] <- tibble(
    SITE = site,
    n_patients = n_site_patients,
    n_encounters = nrow(site_enc),
    n_unique_dates = n_unique_dates,
    n_dupe_patient_dates = n_dupe_pd,
    pct_duplicate_rate = pct_dup_rate,
    n_multi_source_dates = n_multi_src,
    pct_multi_source_of_dupes = pct_multi_of_dupes,
    n_exact_row_dupes = n_exact_site,
    n_near_exact_dupes = n_near_exact_site,
    recommended_source = rec_source,
    recommended_source_completeness_pct = rec_pct
  )
}

cross_site_summary <- bind_rows(cross_site_rows)

# Add "ALL" aggregate row
all_pds <- patient_date_stats
all_n_unique <- nrow(all_pds)
all_n_dupe <- sum(all_pds$n_enc_this_date > 1)
all_pct_dup <- if (all_n_unique > 0) round(100 * all_n_dupe / all_n_unique, 2) else 0
all_n_multi <- nrow(multi_source_dates)
all_pct_multi <- if (all_n_dupe > 0) round(100 * all_n_multi / all_n_dupe, 2) else 0

all_row <- tibble(
  SITE = "ALL",
  n_patients = total_patients,
  n_encounters = nrow(all_encounters),
  n_unique_dates = all_n_unique,
  n_dupe_patient_dates = all_n_dupe,
  pct_duplicate_rate = all_pct_dup,
  n_multi_source_dates = all_n_multi,
  pct_multi_source_of_dupes = all_pct_multi,
  n_exact_row_dupes = nrow(exact_dupes),
  n_near_exact_dupes = nrow(near_exact_dupes),
  recommended_source = NA_character_,
  recommended_source_completeness_pct = NA_real_
)

# Sort by desc(pct_duplicate_rate), then ALL row last
cross_site_summary <- cross_site_summary %>%
  arrange(desc(pct_duplicate_rate)) %>%
  bind_rows(all_row)

write_csv(cross_site_summary, file.path(output_dir, "all_site_cross_site_summary.csv"))
message(glue("  Written: all_site_cross_site_summary.csv ({nrow(cross_site_summary)} rows incl. ALL aggregate)"))

# ==============================================================================
# SECTION 8: Console summary (ALLDUP-05) ----
# ==============================================================================

message(glue("\n{strrep('=', 70)}"))
message("ALL-SITE DUPLICATE DATE INVESTIGATION -- SUMMARY")
message(glue("{strrep('=', 70)}"))

message(glue("\nTotal patients: {format(total_patients, big.mark=',')}"))
message(glue("Total encounters: {format(nrow(all_encounters), big.mark=',')}"))
message(glue("ADMIT_DATE parse rate: {admit_parse_rate}%"))

# Per-site breakdown (compact one-line-per-site format)
message(glue("\nPer-site breakdown:"))
for (i in seq_len(nrow(cross_site_summary))) {
  r <- cross_site_summary[i, ]
  rec_str <- if (!is.na(r$recommended_source)) glue(", rec: {r$recommended_source} ({r$recommended_source_completeness_pct}%)") else ""
  message(glue("  {r$SITE}: {format(r$n_patients, big.mark=',')} patients, {format(r$n_encounters, big.mark=',')} encounters, {r$pct_duplicate_rate}% duplicate rate, {format(r$n_multi_source_dates, big.mark=',')} multi-source dates{rec_str}"))
}

# Per-site source recommendations
if (nrow(site_recommendations) > 0) {
  message(glue("\nPer-site source recommendations:"))
  for (i in seq_len(nrow(site_recommendations))) {
    r <- site_recommendations[i, ]
    message(glue("  {r$SITE}: Prefer ENCOUNTER_SOURCE='{r$recommended_source}' (Primary payer present: {r$recommended_source_completeness_pct}%)"))
  }
} else {
  message("\nNo multi-source encounters found at any site -- no source recommendations generated")
}

# List of 5 CSV files written
message(glue("\nCSV files written to {output_dir}/:"))
message("  - all_site_patient_duplicate_summary.csv")
message("  - all_site_date_level_duplicate_detail.csv")
message("  - all_site_duplicate_aggregate_summary.csv")
message("  - all_site_source_payer_completeness.csv")
message("  - all_site_cross_site_summary.csv")

message(glue("\n{strrep('=', 70)}"))
message("END OF ALL-SITE DUPLICATE DATE INVESTIGATION")
message(glue("{strrep('=', 70)}"))
