# ==============================================================================
# 60_tiered_same_day_payer.R -- Tiered same-day payer categorization
# ==============================================================================
#
# Purpose: Tiered same-day payer categorization with AMC 8-category hierarchy for
#   both all-encounter and AV+TH scopes. Produces 12 CSV deliverables (6 frequency
#   + 6 resolution). Implements Amy Crisp payer framework with hierarchical
#   same-day resolution to resolve conflicts when patients have multiple encounters
#   on the same date with different payer codes.
#
# Inputs:
#   - get_pcornet_table("ENCOUNTER"): ID, ENCOUNTERID, ENC_TYPE, ADMIT_DATE,
#     SOURCE, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY
#   - AMC_PAYER_LOOKUP from R/00_config.R (centralized 8-category mapping)
#   - TIER_MAPPING hierarchy (Medicaid=1 > Medicare=2 > Private=3 > ...)
#
# Outputs: 12 CSV files in output/tables/:
#   Frequency tables (6):
#     - payer_primary_code_freq_all.csv, payer_secondary_code_freq_all.csv, payer_category_summary_all.csv
#     - payer_primary_code_freq_av_th_v2.csv, payer_secondary_code_freq_av_th_v2.csv, payer_category_summary_av_th_v2.csv
#   Resolution tables (6):
#     - payer_resolved_detail_all.csv, payer_resolved_detail_av_th.csv (per-patient-per-date)
#     - payer_resolved_patient_summary_all.csv, payer_resolved_patient_summary_av_th.csv (patient-level modal)
#     - payer_resolved_impact_all.csv, payer_resolved_impact_av_th.csv (before vs after)
#
# Dependencies: Sources R/00_config.R (CONFIG, output_dir, USE_DUCKDB, PAYER_MAPPING,
#   AMC_PAYER_LOOKUP, CODE_TO_TIER utility). Conditionally sources R/01_load_pcornet.R.
#
# Requirements: Implements Amy Crisp payer framework (payer_framework.txt). Phase 60.
#
# Standalone script -- NOT part of the main pipeline sequence.
# ==============================================================================

# ==============================================================================
# SECTION 1: Setup and Tier Configuration ----
# ==============================================================================

source("R/00_config.R")
library(dplyr)
library(glue)
library(readr)
library(lubridate)

# Load tables if not already loaded (RDS mode)
if (!USE_DUCKDB && !exists("pcornet")) source("R/01_load_pcornet.R")
# DuckDB mode: open connection if needed
if (USE_DUCKDB && !exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}

message(glue("\n{strrep('=', 70)}"))
message("TIERED SAME-DAY PAYER CATEGORIZATION")
message("Phase 36: AMC 8-category payer frequency + same-day resolution")
message(glue("{strrep('=', 70)}\n"))

# ==========================================================================
# TIER HIERARCHY CONFIGURATION (per Amy Crisp framework)
# Lower rank = higher priority. PIs can edit this with one-line changes.
#
# WHY this hierarchy order:
#   Medicaid > Medicare > Private > Other govt > Other > Self-pay > Uninsured > Missing
#   - Medicaid has the most restrictive eligibility requirements (income/asset limits)
#     so it is the strongest signal of coverage status
#   - Medicare indicates age 65+ or disability eligibility
#   - Private insurance is purchased coverage (employer or individual)
#   - Hierarchy resolves same-day conflicts by prioritizing the most-informative payer
#   - When a patient has multiple encounters on the same date with different payers,
#     we select the tier with the lowest rank (highest priority) as the "true" payer
#     for that date
# ==========================================================================
TIER_MAPPING <- list(
  Medicaid     = 1L, # Highest priority (includes dual-eligible, codes 93/14, FLM source)
  Medicare     = 2L,
  Private      = 3L,
  "Other govt" = 4L, # VA, TRICARE, state agencies, corrections
  Other        = 5L, # Generic other (worker's comp, auto insurance, etc.)
  "Self-pay"   = 6L,
  Uninsured    = 7L,
  Missing      = 8L # Lowest priority
)

# CODE_TO_TIER() provided by R/utils_payer.R (via R/00_config.R)

# ==============================================================================
# SECTION 2: Load ENCOUNTER table and prepare both scopes ----
# ==============================================================================
# WHY both all-encounter and AV+TH scopes:
#   - All-encounter scope: complete patient encounter history across all care settings
#   - AV+TH scope: Ambulatory (AV) + Hospital (TH) encounters are the clinically
#     relevant types for treatment analysis -- filters out ancillary encounters
#     (lab-only visits, telehealth, etc.) that may not represent meaningful care episodes
#   - Both scopes needed for comparison: all-encounter shows complete picture,
#     AV+TH shows treatment-focused subset

message(glue("\n--- SECTION 2: Load ENCOUNTER Table (All + AV+TH Scopes) ---"))

enc_raw <- get_pcornet_table("ENCOUNTER") %>% materialize()

message(glue("Total encounters loaded: {format(nrow(enc_raw), big.mark=',')}"))

# Ensure columns are character, parse ADMIT_DATE
enc <- enc_raw %>%
  mutate(
    PAYER_TYPE_PRIMARY = as.character(PAYER_TYPE_PRIMARY),
    PAYER_TYPE_SECONDARY = as.character(PAYER_TYPE_SECONDARY),
    SOURCE = as.character(SOURCE),
    admit_date_parsed = as.Date(ADMIT_DATE, format = "%Y-%m-%d"),
    # Compute effective payer: primary if valid, else secondary, else NA
    effective_payer = case_when(
      !is.na(PAYER_TYPE_PRIMARY) & nchar(trimws(PAYER_TYPE_PRIMARY)) > 0 &
        !PAYER_TYPE_PRIMARY %in% PAYER_MAPPING$sentinel_values ~ PAYER_TYPE_PRIMARY,
      !is.na(PAYER_TYPE_SECONDARY) & nchar(trimws(PAYER_TYPE_SECONDARY)) > 0 &
        !PAYER_TYPE_SECONDARY %in% PAYER_MAPPING$sentinel_values ~ PAYER_TYPE_SECONDARY,
      TRUE ~ NA_character_
    ),
    # Dual-eligible flag (informational only, does not override category)
    dual_eligible = {
      dual_codes <- PAYER_MAPPING$dual_eligible_codes
      sec_missing <- is.na(PAYER_TYPE_SECONDARY) | nchar(trimws(PAYER_TYPE_SECONDARY)) == 0
      has_dual <- PAYER_TYPE_PRIMARY %in% dual_codes | PAYER_TYPE_SECONDARY %in% dual_codes
      cross_payer <- (startsWith(PAYER_TYPE_PRIMARY, "1") & startsWith(PAYER_TYPE_SECONDARY, "2")) |
        (startsWith(PAYER_TYPE_PRIMARY, "2") & startsWith(PAYER_TYPE_SECONDARY, "1"))
      case_when(sec_missing ~ 0L, has_dual ~ 1L, cross_payer ~ 1L, TRUE ~ 0L)
    },
    # Map to AMC 8-category: direct lookup + prefix fallback
    payer_category = {
      looked_up <- AMC_PAYER_LOOKUP[effective_payer]
      prefix_cat <- case_when(
        startsWith(effective_payer, "1") ~ "Medicare",
        startsWith(effective_payer, "2") ~ "Medicaid",
        startsWith(effective_payer, "5") | startsWith(effective_payer, "6") ~ "Private",
        startsWith(effective_payer, "3") | startsWith(effective_payer, "4") ~ "Other govt",
        startsWith(effective_payer, "7") ~ "Private",
        startsWith(effective_payer, "8") ~ "Uninsured",
        startsWith(effective_payer, "9") ~ "Other",
        TRUE ~ "Other"
      )
      result <- if_else(!is.na(looked_up), looked_up, prefix_cat)
      if_else(is.na(effective_payer), "Missing", result)
    },
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
    tier_rank = if_else(is.na(tier_rank), 8L, tier_rank)
  )

# Create two scoped datasets
enc_all <- enc
enc_av_th <- enc %>% filter(ENC_TYPE %in% c("AV", "TH"))

message(glue("Total encounters (all scope): {format(nrow(enc_all), big.mark=',')}"))
message(glue("Total encounters (AV+TH scope): {format(nrow(enc_av_th), big.mark=',')}"))
message(glue("Total patients (all scope): {format(n_distinct(enc_all$ID), big.mark=',')}"))
message(glue("Total patients (AV+TH scope): {format(n_distinct(enc_av_th$ID), big.mark=',')}"))

# ==============================================================================
# SECTION 3: Frequency Tables (dual scope) ----
# ==============================================================================

message(glue("\n--- SECTION 3: Building Frequency Tables (Dual Scope) ---"))

build_frequency_tables <- function(enc_scope, suffix, output_dir) {
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
    mutate(
      amc_category = case_when(
        code %in% c("<NA>", "<EMPTY>") ~ "Missing",
        !is.na(AMC_PAYER_LOOKUP[code]) ~ unname(AMC_PAYER_LOOKUP[code]),
        substr(code, 1, 1) == "1" ~ "Medicare",
        substr(code, 1, 1) == "2" ~ "Medicaid",
        substr(code, 1, 1) %in% c("5", "6", "7") ~ "Private",
        substr(code, 1, 1) %in% c("3", "4") ~ "Other govt",
        substr(code, 1, 1) == "8" ~ "Uninsured",
        substr(code, 1, 1) == "9" ~ "Other",
        TRUE ~ "Other"
      ),
      pct = round(100 * n / total_enc, 2)
    ) %>%
    select(code, amc_category, n, pct) %>%
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
    mutate(
      amc_category = case_when(
        code %in% c("<NA>", "<EMPTY>") ~ "Missing",
        !is.na(AMC_PAYER_LOOKUP[code]) ~ unname(AMC_PAYER_LOOKUP[code]),
        substr(code, 1, 1) == "1" ~ "Medicare",
        substr(code, 1, 1) == "2" ~ "Medicaid",
        substr(code, 1, 1) %in% c("5", "6", "7") ~ "Private",
        substr(code, 1, 1) %in% c("3", "4") ~ "Other govt",
        substr(code, 1, 1) == "8" ~ "Uninsured",
        substr(code, 1, 1) == "9" ~ "Other",
        TRUE ~ "Other"
      ),
      pct = round(100 * n / total_enc, 2)
    ) %>%
    select(code, amc_category, n, pct) %>%
    arrange(desc(n))

  # Category-level summary
  primary_cat <- primary_freq %>%
    group_by(amc_category) %>%
    summarise(n = sum(n), .groups = "drop") %>%
    mutate(
      field = "PRIMARY",
      pct   = round(100 * n / total_enc, 2)
    ) %>%
    select(field, amc_category, n, pct) %>%
    arrange(desc(n))

  secondary_cat <- secondary_freq %>%
    group_by(amc_category) %>%
    summarise(n = sum(n), .groups = "drop") %>%
    mutate(
      field = "SECONDARY",
      pct   = round(100 * n / total_enc, 2)
    ) %>%
    select(field, amc_category, n, pct) %>%
    arrange(desc(n))

  category_summary <- bind_rows(primary_cat, secondary_cat)

  # Write CSVs
  write_csv(primary_freq, file.path(output_dir, paste0("payer_primary_code_freq", suffix, ".csv")))
  write_csv(secondary_freq, file.path(output_dir, paste0("payer_secondary_code_freq", suffix, ".csv")))
  write_csv(category_summary, file.path(output_dir, paste0("payer_category_summary", suffix, ".csv")))

  message(glue("  Written: payer_primary_code_freq{suffix}.csv ({nrow(primary_freq)} rows)"))
  message(glue("  Written: payer_secondary_code_freq{suffix}.csv ({nrow(secondary_freq)} rows)"))
  message(glue("  Written: payer_category_summary{suffix}.csv ({nrow(category_summary)} rows)"))

  n_fallback_primary <- sum(is.na(AMC_PAYER_LOOKUP[primary_freq$code]) &
    !primary_freq$code %in% c("<NA>", "<EMPTY>"), na.rm = TRUE)
  n_fallback_secondary <- sum(is.na(AMC_PAYER_LOOKUP[secondary_freq$code]) &
    !secondary_freq$code %in% c("<NA>", "<EMPTY>"), na.rm = TRUE)

  message(glue("  Distinct PRIMARY codes: {nrow(primary_freq)} ({n_fallback_primary} via prefix fallback)"))
  message(glue("  Distinct SECONDARY codes: {nrow(secondary_freq)} ({n_fallback_secondary} via prefix fallback)"))
}

output_dir <- file.path(CONFIG$output_dir, "tables")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# All encounters
message("\n=== All Encounters Scope ===")
build_frequency_tables(enc_all, "_all", output_dir)

# AV+TH encounters
message("\n=== AV+TH Encounters Scope ===")
build_frequency_tables(enc_av_th, "_av_th_v2", output_dir)

# ==============================================================================
# SECTION 4: Same-Day Payer Resolution (dual scope) ----
# ==============================================================================
# WHY same-day collapsing is needed:
#   - Patients may have multiple encounters on the same date with different payer codes
#     (e.g., lab visit coded as Private, same-day clinic visit coded as Medicaid)
#   - These represent the same patient on the same date but with conflicting payer info
#   - Resolution logic uses tier hierarchy to deterministically select one payer per
#     patient-date, enabling downstream daily-level payer analysis without duplicates
#   - Without collapsing, daily counts would be inflated and payer assignment ambiguous

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
        any(SOURCE == "FLM", na.rm = TRUE) ~ "Medicaid", # FLM override
        any(PAYER_TYPE_PRIMARY %in% c("93", "14") |
          PAYER_TYPE_SECONDARY %in% c("93", "14"), na.rm = TRUE) ~ "Medicaid", # Code override
        TRUE ~ tier[which.min(tier_rank)] # Tier hierarchy
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
# SECTION 5: Console Summary ----
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
