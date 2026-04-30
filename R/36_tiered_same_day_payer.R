# ==============================================================================
# 36_tiered_same_day_payer.R -- Tiered same-day payer categorization
# ==============================================================================
#
# Phase 35: Tiered same-day payer categorization
# Requirements: Per Amy Crisp framework (payer_framework.txt)
#
# Purpose: Produce two deliverables per Amy Crisp's framework:
#
# 1. Raw payer frequency tables with PayerVariable.xlsx cross-reference for BOTH
#    all-encounter and AV+TH scopes (6 frequency CSVs)
# 2. Hierarchical same-day payer resolution using the priority hierarchy:
#    Medicaid > Medicare > Private > Other > Self-pay > Uninsured > Missing
#    for BOTH scopes (6 resolution CSVs)
#
# Output: 12 CSV files in output/tables/:
#   Frequency tables (6):
#     - payer_primary_code_freq_all.csv
#     - payer_secondary_code_freq_all.csv
#     - payer_category_summary_all.csv
#     - payer_primary_code_freq_av_th_v2.csv
#     - payer_secondary_code_freq_av_th_v2.csv
#     - payer_category_summary_av_th_v2.csv
#
#   Resolution tables (6):
#     - payer_resolved_detail_all.csv            (CSV A: per-patient-per-date)
#     - payer_resolved_detail_av_th.csv
#     - payer_resolved_patient_summary_all.csv   (CSV B: patient-level modal)
#     - payer_resolved_patient_summary_av_th.csv
#     - payer_resolved_impact_all.csv            (CSV C: before vs after)
#     - payer_resolved_impact_av_th.csv
#
# Usage: source("R/36_tiered_same_day_payer.R")
#
# Dependencies: Sources R/00_config.R (CONFIG, output_dir, USE_DUCKDB, PAYER_MAPPING).
#   Conditionally sources R/01_load_pcornet.R for pcornet tables.
#   Requires: get_pcornet_table("ENCOUNTER") (ID, ENCOUNTERID, ENC_TYPE,
#     ADMIT_DATE, SOURCE, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY)
#   Requires: readxl package for reading PayerVariable.xlsx
#
# DuckDB migration (Phase 32): Uses get_pcornet_table() for backend-transparent
#   access. Materializes immediately after loading because all downstream logic
#   (count, left_join, group_by, date arithmetic) requires in-memory data.
#
# Standalone script -- NOT part of the main pipeline sequence.
# ==============================================================================

# ==============================================================================
# SECTION 0: Setup and Tier Configuration
# ==============================================================================

source("R/00_config.R")
library(dplyr)
library(glue)
library(readr)
library(readxl)
library(stringr)
library(lubridate)

# Path to PayerVariable.xlsx (repo root)
PAYER_XLSX_PATH <- "PayerVariable.xlsx"

# Load tables if not already loaded (RDS mode)
if (!USE_DUCKDB && !exists("pcornet")) source("R/01_load_pcornet.R")
# DuckDB mode: open connection if needed
if (USE_DUCKDB && !exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}

message(glue("\n{strrep('=', 70)}"))
message("TIERED SAME-DAY PAYER CATEGORIZATION")
message("Phase 35: Dual-scope frequency + hierarchical same-day resolution")
message(glue("{strrep('=', 70)}\n"))

# ==========================================================================
# TIER HIERARCHY CONFIGURATION (per Amy Crisp framework)
# Lower rank = higher priority. PIs can edit this with one-line changes.
# ==========================================================================
TIER_MAPPING <- list(
  Medicaid   = 1L,  # Highest priority (includes dual-eligible, codes 93/14, FLM source)
  Medicare   = 2L,
  Private    = 3L,
  Other      = 4L,
  "Self-pay" = 5L,
  Uninsured  = 6L,
  Missing    = 7L   # Lowest priority
)

# Map the AMC 8-category payer scheme to the 7 tiers
# AMC categories already align closely with tiers; "Other govt" collapses to "Other"
CODE_TO_TIER <- function(payer_category) {
  case_when(
    payer_category == "Medicaid"  ~ "Medicaid",
    payer_category == "Medicare"  ~ "Medicare",
    payer_category == "Private"   ~ "Private",
    payer_category == "Other govt" ~ "Other",
    payer_category == "Other"     ~ "Other",
    payer_category == "Self-pay"  ~ "Self-pay",
    payer_category == "Uninsured" ~ "Uninsured",
    payer_category == "Missing"   ~ "Missing",
    is.na(payer_category)         ~ "Missing",
    TRUE ~ "Missing"
  )
}

# Replicate compute_effective_payer logic inline (no source R/02_harmonize_payer.R)
compute_effective_payer_local <- function(primary, secondary) {
  sentinel_values <- PAYER_MAPPING$sentinel_values  # c("NI", "UN", "OT")

  primary_valid <- !is.na(primary) &
                   nchar(trimws(primary)) > 0 &
                   !primary %in% sentinel_values

  secondary_valid <- !is.na(secondary) &
                     nchar(trimws(secondary)) > 0 &
                     !secondary %in% sentinel_values

  case_when(
    primary_valid ~ primary,
    secondary_valid ~ secondary,
    TRUE ~ NA_character_
  )
}

# Replicate detect_dual_eligible logic inline (informational flag only)
detect_dual_eligible_local <- function(primary, secondary) {
  dual_codes <- PAYER_MAPPING$dual_eligible_codes  # c("14", "141", "142")

  secondary_missing <- is.na(secondary) | nchar(trimws(secondary)) == 0

  has_dual_code <- primary %in% dual_codes | secondary %in% dual_codes

  cross_payer <- (str_starts(primary, "1") & str_starts(secondary, "2")) |
                 (str_starts(primary, "2") & str_starts(secondary, "1"))

  case_when(
    secondary_missing ~ 0L,
    has_dual_code ~ 1L,
    cross_payer ~ 1L,
    TRUE ~ 0L
  )
}

# Replicate map_payer_category logic inline (AMC 8-category system)
map_payer_category_local <- function(effective_payer) {
  # Direct lookup from AMC table
  looked_up <- AMC_PAYER_LOOKUP[effective_payer]

  # Prefix-based fallback for codes not in AMC_PAYER_LOOKUP
  prefix_category <- case_when(
    str_starts(effective_payer, "1") ~ "Medicare",
    str_starts(effective_payer, "2") ~ "Medicaid",
    str_starts(effective_payer, "5") | str_starts(effective_payer, "6") ~ "Private",
    str_starts(effective_payer, "3") | str_starts(effective_payer, "4") ~ "Other govt",
    str_starts(effective_payer, "7") ~ "Private",
    str_starts(effective_payer, "8") ~ "Uninsured",
    str_starts(effective_payer, "9") ~ "Other",
    TRUE ~ "Other"
  )

  result <- if_else(!is.na(looked_up), looked_up, prefix_category)
  result <- if_else(is.na(effective_payer), "Missing", result)
  result
}

# ==============================================================================
# SECTION 1: Load PayerVariable.xlsx
# ==============================================================================

message("--- SECTION 1: Load PayerVariable.xlsx ---")

payer_lookup <- readxl::read_excel(PAYER_XLSX_PATH, sheet = "Sheet2")

# Rename columns for R-friendliness
names(payer_lookup) <- c("code", "description", "category")

# Trim whitespace and convert all to character
payer_lookup <- payer_lookup %>%
  mutate(across(everything(), ~trimws(as.character(.))))

message(glue("Loaded {nrow(payer_lookup)} rows from PayerVariable.xlsx (Sheet2)"))
message(glue("Unique categories in xlsx: {paste(sort(unique(payer_lookup$category)), collapse = ', ')}"))
message(glue("Number of unique categories: {n_distinct(payer_lookup$category)}"))

message("\nFirst 5 rows:")
for (i in seq_len(min(5, nrow(payer_lookup)))) {
  r <- payer_lookup[i, ]
  message(glue("  code={r$code} | desc={r$description} | cat={r$category}"))
}

# ==============================================================================
# SECTION 2: Load ENCOUNTER table and prepare both scopes
# ==============================================================================

message(glue("\n--- SECTION 2: Load ENCOUNTER Table (All + AV+TH Scopes) ---"))

enc_raw <- get_pcornet_table("ENCOUNTER") %>% materialize()

message(glue("Total encounters loaded: {format(nrow(enc_raw), big.mark=',')}"))

# Ensure columns are character, parse ADMIT_DATE
enc <- enc_raw %>%
  mutate(
    PAYER_TYPE_PRIMARY   = as.character(PAYER_TYPE_PRIMARY),
    PAYER_TYPE_SECONDARY = as.character(PAYER_TYPE_SECONDARY),
    SOURCE               = as.character(SOURCE),
    admit_date_parsed    = as.Date(ADMIT_DATE, format = "%Y-%m-%d"),
    # Compute effective payer (primary if valid, else secondary)
    effective_payer = compute_effective_payer_local(PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY),
    # Detect dual-eligible (informational flag only)
    dual_eligible = detect_dual_eligible_local(PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY),
    # Map to AMC 8-category
    payer_category = map_payer_category_local(effective_payer),
    # Map to tier
    tier = CODE_TO_TIER(payer_category),
    # Override with special codes 93/14 (check raw codes, not effective)
    tier = coalesce(
      case_when(
        PAYER_TYPE_PRIMARY %in% c("93", "14") ~ "Medicaid",
        PAYER_TYPE_SECONDARY %in% c("93", "14") ~ "Medicaid",
        TRUE ~ NA_character_
      ),
      tier
    ),
    # Safety net: ensure tier is never NA (maps to Missing)
    tier = if_else(is.na(tier), "Missing", tier),
    # Assign tier rank
    tier_rank = unlist(TIER_MAPPING[tier]),
    # Safety net: ensure tier_rank is never NA
    tier_rank = if_else(is.na(tier_rank), 7L, tier_rank)
  )

# Create two scoped datasets
enc_all <- enc
enc_av_th <- enc %>% filter(ENC_TYPE %in% c("AV", "TH"))

message(glue("Total encounters (all scope): {format(nrow(enc_all), big.mark=',')}"))
message(glue("Total encounters (AV+TH scope): {format(nrow(enc_av_th), big.mark=',')}"))
message(glue("Total patients (all scope): {format(n_distinct(enc_all$ID), big.mark=',')}"))
message(glue("Total patients (AV+TH scope): {format(n_distinct(enc_av_th$ID), big.mark=',')}"))

# ==============================================================================
# SECTION 3: Frequency Tables (dual scope)
# ==============================================================================

message(glue("\n--- SECTION 3: Building Frequency Tables (Dual Scope) ---"))

build_frequency_tables <- function(enc_scope, suffix, payer_lookup, output_dir) {
  total_enc <- nrow(enc_scope)

  # PRIMARY frequency table
  primary_freq <- enc_scope %>%
    mutate(
      code = case_when(
        is.na(PAYER_TYPE_PRIMARY) ~ "<NA>",
        PAYER_TYPE_PRIMARY == "" ~ "<EMPTY>",
        TRUE ~ PAYER_TYPE_PRIMARY
      )
    ) %>%
    count(code, name = "n") %>%
    arrange(desc(n)) %>%
    left_join(payer_lookup, by = "code") %>%
    mutate(
      description = ifelse(is.na(description) & !code %in% c("<NA>", "<EMPTY>"),
                           "NOT IN XLSX", description),
      category    = ifelse(is.na(category) & !code %in% c("<NA>", "<EMPTY>"),
                           "NOT IN XLSX", category),
      pct = round(100 * n / total_enc, 2)
    ) %>%
    select(code, description, category, n, pct) %>%
    arrange(desc(n))

  # SECONDARY frequency table
  secondary_freq <- enc_scope %>%
    mutate(
      code = case_when(
        is.na(PAYER_TYPE_SECONDARY) ~ "<NA>",
        PAYER_TYPE_SECONDARY == "" ~ "<EMPTY>",
        TRUE ~ PAYER_TYPE_SECONDARY
      )
    ) %>%
    count(code, name = "n") %>%
    arrange(desc(n)) %>%
    left_join(payer_lookup, by = "code") %>%
    mutate(
      description = ifelse(is.na(description) & !code %in% c("<NA>", "<EMPTY>"),
                           "NOT IN XLSX", description),
      category    = ifelse(is.na(category) & !code %in% c("<NA>", "<EMPTY>"),
                           "NOT IN XLSX", category),
      pct = round(100 * n / total_enc, 2)
    ) %>%
    select(code, description, category, n, pct) %>%
    arrange(desc(n))

  # Category-level summary
  primary_cat <- primary_freq %>%
    group_by(category) %>%
    summarise(n = sum(n), .groups = "drop") %>%
    mutate(
      field = "PRIMARY",
      pct   = round(100 * n / total_enc, 2)
    ) %>%
    select(field, category, n, pct) %>%
    arrange(desc(n))

  secondary_cat <- secondary_freq %>%
    group_by(category) %>%
    summarise(n = sum(n), .groups = "drop") %>%
    mutate(
      field = "SECONDARY",
      pct   = round(100 * n / total_enc, 2)
    ) %>%
    select(field, category, n, pct) %>%
    arrange(desc(n))

  category_summary <- bind_rows(primary_cat, secondary_cat)

  # Write CSVs
  write_csv(primary_freq, file.path(output_dir, paste0("payer_primary_code_freq", suffix, ".csv")))
  write_csv(secondary_freq, file.path(output_dir, paste0("payer_secondary_code_freq", suffix, ".csv")))
  write_csv(category_summary, file.path(output_dir, paste0("payer_category_summary", suffix, ".csv")))

  message(glue("  Written: payer_primary_code_freq{suffix}.csv ({nrow(primary_freq)} rows)"))
  message(glue("  Written: payer_secondary_code_freq{suffix}.csv ({nrow(secondary_freq)} rows)"))
  message(glue("  Written: payer_category_summary{suffix}.csv ({nrow(category_summary)} rows)"))

  n_not_in_xlsx_primary <- sum(primary_freq$description == "NOT IN XLSX", na.rm = TRUE)
  n_not_in_xlsx_secondary <- sum(secondary_freq$description == "NOT IN XLSX", na.rm = TRUE)

  message(glue("  Distinct PRIMARY codes: {nrow(primary_freq)} ({n_not_in_xlsx_primary} NOT IN XLSX)"))
  message(glue("  Distinct SECONDARY codes: {nrow(secondary_freq)} ({n_not_in_xlsx_secondary} NOT IN XLSX)"))
}

output_dir <- file.path(CONFIG$output_dir, "tables")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# All encounters
message("\n=== All Encounters Scope ===")
build_frequency_tables(enc_all, "_all", payer_lookup, output_dir)

# AV+TH encounters
message("\n=== AV+TH Encounters Scope ===")
build_frequency_tables(enc_av_th, "_av_th_v2", payer_lookup, output_dir)

# ==============================================================================
# SECTION 4: Same-Day Payer Resolution (dual scope)
# ==============================================================================

message(glue("\n--- SECTION 4: Same-Day Payer Resolution (Dual Scope) ---"))

resolve_same_day_payer <- function(enc_scope, suffix, output_dir) {
  # Early exit guard: check for valid ADMIT_DATE values
  if (sum(!is.na(enc_scope$admit_date_parsed)) == 0) {
    message(glue("  WARNING: No valid ADMIT_DATE values in {suffix} scope -- skipping resolution"))
    return(invisible(NULL))
  }

  # Group by patient + date, resolve payer
  resolved_detail <- enc_scope %>%
    filter(!is.na(admit_date_parsed)) %>%
    group_by(ID, admit_date_parsed) %>%
    summarise(
      n_encounters = n(),
      n_distinct_tiers = n_distinct(tier),
      has_flm = any(SOURCE == "FLM", na.rm = TRUE),
      has_special_code = any(PAYER_TYPE_PRIMARY %in% c("93", "14") |
                             PAYER_TYPE_SECONDARY %in% c("93", "14"), na.rm = TRUE),
      original_tiers = paste(sort(unique(tier)), collapse = "+"),
      original_codes_primary = paste(sort(unique(na.omit(PAYER_TYPE_PRIMARY))), collapse = ","),
      # Resolution logic: FLM override > special code override > tier hierarchy
      resolved_payer = case_when(
        any(SOURCE == "FLM", na.rm = TRUE) ~ "Medicaid",           # FLM override
        any(PAYER_TYPE_PRIMARY %in% c("93", "14") |
            PAYER_TYPE_SECONDARY %in% c("93", "14"), na.rm = TRUE) ~ "Medicaid",  # Code override
        TRUE ~ tier[which.min(tier_rank)]                            # Tier hierarchy
      ),
      resolution_reason = case_when(
        n() == 1 ~ "single encounter",
        any(SOURCE == "FLM", na.rm = TRUE) ~ "FLM source override",
        any(PAYER_TYPE_PRIMARY %in% c("93", "14") |
            PAYER_TYPE_SECONDARY %in% c("93", "14"), na.rm = TRUE) ~ "special code override (93/14)",
        n_distinct(tier) == 1 ~ "all encounters same tier",
        TRUE ~ paste0("tier hierarchy (", n_distinct(tier), " tiers)")
      ),
      .groups = "drop"
    ) %>%
    rename(ADMIT_DATE = admit_date_parsed) %>%
    arrange(ID, ADMIT_DATE)

  # CSV A: Per-patient-per-date detail
  write_csv(resolved_detail, file.path(output_dir, paste0("payer_resolved_detail", suffix, ".csv")))
  message(glue("  Written: payer_resolved_detail{suffix}.csv ({nrow(resolved_detail)} rows)"))

  # CSV B: Patient-level modal summary
  patient_total_dates <- resolved_detail %>%
    group_by(ID) %>%
    summarise(total_dates = n(), .groups = "drop")

  patient_summary <- resolved_detail %>%
    count(ID, resolved_payer, name = "n_dates_with_payer") %>%
    arrange(ID, desc(n_dates_with_payer), resolved_payer) %>%
    group_by(ID) %>%
    slice(1) %>%
    ungroup() %>%
    rename(modal_resolved_payer = resolved_payer) %>%
    left_join(patient_total_dates, by = "ID")

  write_csv(patient_summary, file.path(output_dir, paste0("payer_resolved_patient_summary", suffix, ".csv")))
  message(glue("  Written: payer_resolved_patient_summary{suffix}.csv ({nrow(patient_summary)} rows)"))

  # CSV C: Before vs after impact
  before_resolution <- enc_scope %>%
    filter(!is.na(admit_date_parsed)) %>%
    count(tier, name = "n_encounters_before") %>%
    arrange(match(tier, names(TIER_MAPPING)))

  after_resolution <- resolved_detail %>%
    count(resolved_payer, name = "n_patient_dates_after") %>%
    arrange(match(resolved_payer, names(TIER_MAPPING)))

  impact <- before_resolution %>%
    full_join(after_resolution, by = c("tier" = "resolved_payer")) %>%
    mutate(
      n_encounters_before = coalesce(n_encounters_before, 0L),
      n_patient_dates_after = coalesce(n_patient_dates_after, 0L),
      pct_encounters_before = round(100 * n_encounters_before / sum(n_encounters_before, na.rm = TRUE), 2),
      pct_patient_dates_after = round(100 * n_patient_dates_after / sum(n_patient_dates_after, na.rm = TRUE), 2)
    ) %>%
    rename(category = tier)

  write_csv(impact, file.path(output_dir, paste0("payer_resolved_impact", suffix, ".csv")))
  message(glue("  Written: payer_resolved_impact{suffix}.csv ({nrow(impact)} rows)"))

  # Log summary
  message(glue("  Total patient-dates: {format(nrow(resolved_detail), big.mark=',')}"))
  single_enc <- sum(resolved_detail$n_encounters == 1)
  multi_enc <- sum(resolved_detail$n_encounters > 1)
  message(glue("  Single-encounter dates: {format(single_enc, big.mark=',')} ({round(100*single_enc/nrow(resolved_detail), 1)}%)"))
  message(glue("  Multi-encounter dates: {format(multi_enc, big.mark=',')} ({round(100*multi_enc/nrow(resolved_detail), 1)}%)"))
}

# All encounters
message("\n=== All Encounters Scope ===")
resolve_same_day_payer(enc_all, "_all", output_dir)

# AV+TH encounters
message("\n=== AV+TH Encounters Scope ===")
resolve_same_day_payer(enc_av_th, "_av_th", output_dir)

# ==============================================================================
# SECTION 5: Console Summary
# ==============================================================================

message(glue("\n{strrep('=', 70)}"))
message("TIERED SAME-DAY PAYER CATEGORIZATION -- SUMMARY")
message(glue("{strrep('=', 70)}"))

message(glue("\nTotal encounters analyzed:"))
message(glue("  All scope:   {format(nrow(enc_all), big.mark=',')}"))
message(glue("  AV+TH scope: {format(nrow(enc_av_th), big.mark=',')}"))

message(glue("\nTotal patients:"))
message(glue("  All scope:   {format(n_distinct(enc_all$ID), big.mark=',')}"))
message(glue("  AV+TH scope: {format(n_distinct(enc_av_th$ID), big.mark=',')}"))

message(glue("\nCSV files written to {output_dir}/:"))
message("\n--- Frequency Tables (6 files) ---")
message("  payer_primary_code_freq_all.csv")
message("  payer_secondary_code_freq_all.csv")
message("  payer_category_summary_all.csv")
message("  payer_primary_code_freq_av_th_v2.csv")
message("  payer_secondary_code_freq_av_th_v2.csv")
message("  payer_category_summary_av_th_v2.csv")

message("\n--- Resolution Tables (6 files) ---")
message("  payer_resolved_detail_all.csv")
message("  payer_resolved_detail_av_th.csv")
message("  payer_resolved_patient_summary_all.csv")
message("  payer_resolved_patient_summary_av_th.csv")
message("  payer_resolved_impact_all.csv")
message("  payer_resolved_impact_av_th.csv")

message(glue("\n{strrep('=', 70)}"))
message("END OF TIERED SAME-DAY PAYER CATEGORIZATION")
message(glue("{strrep('=', 70)}"))

# ==============================================================================
# Script end
# ==============================================================================
