# ==============================================================================
# 61_tiered_encounter_level.R -- Tiered payer at the encounter level
# ==============================================================================
#
# Purpose: Assign AMC 8-category payer tiers to every individual encounter without
#   same-day collapsing -- preserves encounter-level granularity for downstream
#   analysis. Each ENCOUNTERID gets its own tier.
#
# Inputs:
#   - get_pcornet_table("ENCOUNTER"): ID, ENCOUNTERID, ENC_TYPE, ADMIT_DATE,
#     SOURCE, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY
#   - AMC_PAYER_LOOKUP from R/00_config.R
#
# Outputs: 4 CSV files in output/tables/:
#   - encounter_tier_detail_all.csv, encounter_tier_detail_av_th.csv (every encounter with tier)
#   - encounter_tier_summary_all.csv, encounter_tier_summary_av_th.csv (tier frequency counts)
#
# Dependencies: Sources R/00_config.R (CONFIG, USE_DUCKDB, PAYER_MAPPING, AMC_PAYER_LOOKUP, CODE_TO_TIER).
#
# Requirements: AMC 8-category payer mapping with encounter-level granularity.
#
# Standalone script -- NOT part of the main pipeline sequence.
# ==============================================================================

# ==============================================================================
# SECTION 1: Setup and Tier Configuration ----
# ==============================================================================
# WHY encounter-level (no collapsing) differs from same-day approach (R/60):
#   - Same-day collapsing (R/60): collapses multiple encounters on same date to one payer
#     per patient-date, useful for daily-level analysis
#   - Encounter-level (this script): preserves granularity -- each encounter keeps its
#     own payer assignment, enabling analysis that needs individual encounter payer
#     information (e.g., per-encounter cost analysis, provider-level payer mix)
#   - Both approaches needed: same-day for temporal trends, encounter-level for granular
#     encounter-specific analysis

source("R/00_config.R")
library(dplyr)
library(glue)
library(readr)

# Load tables if not already loaded (RDS mode)
if (!USE_DUCKDB && !exists("pcornet")) source("R/01_load_pcornet.R")
# DuckDB mode: open connection if needed
if (USE_DUCKDB && !exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}

message(glue("\n{strrep('=', 70)}"))
message("TIERED PAYER -- ENCOUNTER LEVEL")
message("Each encounter gets its own tier (no same-day collapsing)")
message(glue("{strrep('=', 70)}\n"))

# ==========================================================================
# TIER HIERARCHY (same as script 36, per Amy Crisp framework)
# Lower rank = higher priority.
# ==========================================================================
TIER_MAPPING <- list(
  Medicaid     = 1L,
  Medicare     = 2L,
  Private      = 3L,
  "Other govt" = 4L,
  Other        = 5L,
  "Self-pay"   = 6L,
  Uninsured    = 7L,
  Missing      = 8L
)

# CODE_TO_TIER() provided by R/utils_payer.R (via R/00_config.R)

# ==============================================================================
# SECTION 2: Load ENCOUNTER table and assign tiers per encounter ----
# ==============================================================================

message("--- Loading ENCOUNTER table ---")

enc_raw <- get_pcornet_table("ENCOUNTER") %>% materialize()
message(glue("Total encounters loaded: {format(nrow(enc_raw), big.mark=',')}"))

# SECTION 1b: INPUT VALIDATION ----
# SAFE-02: Validate ENCOUNTER table is available and has required columns
assert_df_valid(
  enc_raw, "ENCOUNTER",
  required_cols = c("ID", "ENCOUNTERID", "ADMIT_DATE", "ENC_TYPE",
                    "PAYER_TYPE_PRIMARY"),
  script_name = "R/61"
)

enc <- enc_raw %>%
  mutate(
    PAYER_TYPE_PRIMARY = as.character(PAYER_TYPE_PRIMARY),
    PAYER_TYPE_SECONDARY = as.character(PAYER_TYPE_SECONDARY),
    SOURCE = as.character(SOURCE),
    # Effective payer: primary if valid, else secondary, else NA
    effective_payer = case_when(
      !is.na(PAYER_TYPE_PRIMARY) & nchar(trimws(PAYER_TYPE_PRIMARY)) > 0 &
        !PAYER_TYPE_PRIMARY %in% PAYER_MAPPING$sentinel_values ~ PAYER_TYPE_PRIMARY,
      !is.na(PAYER_TYPE_SECONDARY) & nchar(trimws(PAYER_TYPE_SECONDARY)) > 0 &
        !PAYER_TYPE_SECONDARY %in% PAYER_MAPPING$sentinel_values ~ PAYER_TYPE_SECONDARY,
      TRUE ~ NA_character_
    ),
    # Dual-eligible flag (informational)
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
    # Override with special codes 93/14
    tier = coalesce(
      case_when(
        PAYER_TYPE_PRIMARY %in% c("93", "14") ~ "Medicaid",
        PAYER_TYPE_SECONDARY %in% c("93", "14") ~ "Medicaid",
        TRUE ~ NA_character_
      ),
      tier
    ),
    # FLM source override
    tier = if_else(SOURCE == "FLM" & !is.na(SOURCE), "Medicaid", tier),
    # Safety net
    tier = if_else(is.na(tier), "Missing", tier),
    tier_rank = unlist(TIER_MAPPING[tier]),
    tier_rank = if_else(is.na(tier_rank), 8L, tier_rank)
  )

# ==============================================================================
# SECTION 3: Build encounter-level detail for both scopes ----
# ==============================================================================

output_dir <- file.path(CONFIG$output_dir, "tables")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

build_encounter_tier <- function(enc_scope, suffix, output_dir) {
  total_enc <- nrow(enc_scope)
  n_patients_total <- n_distinct(enc_scope$ID)

  message(glue("\n=== {suffix} Scope ==="))
  message(glue("  Encounters: {format(total_enc, big.mark=',')}"))
  message(glue("  Patients:   {format(n_patients_total, big.mark=',')}"))

  # --- Detail: one row per encounter ---
  detail <- enc_scope %>%
    select(
      ENCOUNTERID, ID, ENC_TYPE, ADMIT_DATE, SOURCE,
      PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY,
      effective_payer, dual_eligible, payer_category, tier, tier_rank
    ) %>%
    arrange(ID, ADMIT_DATE, ENCOUNTERID)

  detail_path <- file.path(output_dir, paste0("encounter_tier_detail", suffix, ".csv"))
  write_csv(detail, detail_path)
  message(glue("  Written: encounter_tier_detail{suffix}.csv ({format(nrow(detail), big.mark=',')} rows)"))

  # --- Summary: tier frequency ---
  tier_order <- names(TIER_MAPPING)

  summary_tbl <- enc_scope %>%
    count(tier, name = "n_encounters") %>%
    mutate(
      pct_encounters = round(100 * n_encounters / total_enc, 2)
    ) %>%
    left_join(
      enc_scope %>%
        distinct(ID, tier) %>%
        count(tier, name = "n_patients"),
      by = "tier"
    ) %>%
    mutate(
      pct_patients = round(100 * n_patients / n_patients_total, 2)
    ) %>%
    arrange(match(tier, tier_order)) %>%
    select(tier, n_encounters, pct_encounters, n_patients, pct_patients)

  summary_path <- file.path(output_dir, paste0("encounter_tier_summary", suffix, ".csv"))
  write_csv(summary_tbl, summary_path)
  message(glue("  Written: encounter_tier_summary{suffix}.csv ({nrow(summary_tbl)} rows)"))

  # Print summary to console
  message(glue("\n  Tier Distribution ({suffix}):"))
  for (i in seq_len(nrow(summary_tbl))) {
    row <- summary_tbl[i, ]
    message(glue("    {format(row$tier, width=10)} : {format(row$n_encounters, big.mark=',', width=10)} encounters ({row$pct_encounters}%) | {format(row$n_patients, big.mark=',', width=7)} patients ({row$pct_patients}%)"))
  }
}

# All encounters
build_encounter_tier(enc, "_all", output_dir)

# AV+TH encounters only
enc_av_th <- enc %>% filter(ENC_TYPE %in% c("AV", "TH"))
build_encounter_tier(enc_av_th, "_av_th", output_dir)

# ==============================================================================
# SECTION 4: Console Summary ----
# ==============================================================================

message(glue("\n{strrep('=', 70)}"))
message("TIERED PAYER (ENCOUNTER LEVEL) -- SUMMARY")
message(glue("{strrep('=', 70)}"))

message(glue("\nTotal encounters analyzed:"))
message(glue("  All scope:   {format(nrow(enc), big.mark=',')}"))
message(glue("  AV+TH scope: {format(nrow(enc_av_th), big.mark=',')}"))

message(glue("\nTotal patients:"))
message(glue("  All scope:   {format(n_distinct(enc$ID), big.mark=',')}"))
message(glue("  AV+TH scope: {format(n_distinct(enc_av_th$ID), big.mark=',')}"))

message(glue("\nCSV files written to {output_dir}/:"))
message("  encounter_tier_detail_all.csv      (every encounter with tier)")
message("  encounter_tier_detail_av_th.csv")
message("  encounter_tier_summary_all.csv     (tier frequency counts)")
message("  encounter_tier_summary_av_th.csv")

message(glue("\n{strrep('=', 70)}"))
message("END OF TIERED PAYER (ENCOUNTER LEVEL)")
message(glue("{strrep('=', 70)}"))

# ==============================================================================
# Script end
# ==============================================================================
