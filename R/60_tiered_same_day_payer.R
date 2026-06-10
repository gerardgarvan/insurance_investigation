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
#   AMC_PAYER_LOOKUP, TIER_MAPPING, LOOKUP_TABLES_DT, classify_payer_tier_dt() from
#   R/utils/utils_payer.R, ensure_dt()/to_tibble_safe()/get_lookup_dt() from
#   R/utils/utils_dt.R). Conditionally sources R/01_load_pcornet.R.
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
library(data.table)
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

# classify_payer_tier_dt(), CODE_TO_TIER() provided by R/utils/utils_payer.R
# TIER_MAPPING, LOOKUP_TABLES_DT provided by R/00_config.R (centralized, not defined here)
# ensure_dt(), to_tibble_safe(), get_lookup_dt() provided by R/utils/utils_dt.R

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

# SECTION 1b: INPUT VALIDATION ----
# SAFE-02: Validate ENCOUNTER table is available and has required columns
assert_df_valid(
  enc_raw, "ENCOUNTER",
  required_cols = c("ID", "ENCOUNTERID", "ADMIT_DATE", "ENC_TYPE",
                    "PAYER_TYPE_PRIMARY"),
  script_name = "R/60"
)

# Classify payer tier for each encounter row
# classify_payer_tier() provided by R/utils/utils_payer.R (via R/00_config.R)
# TIER_MAPPING and AMC_PAYER_LOOKUP provided by R/00_config.R
enc <- enc_raw %>%
  classify_payer_tier_dt(include_dual = TRUE, flm_override = FALSE) %>%
  mutate(admit_date_parsed = as.Date(ADMIT_DATE, format = "%Y-%m-%d"))

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

  # --- PRIMARY frequency table ---
  enc_dt <- copy(ensure_dt(enc_scope, name = "enc_scope", script_name = "R/60"))
  enc_dt[, code := fcase(
    is.na(PAYER_TYPE_PRIMARY), "<NA>",
    PAYER_TYPE_PRIMARY == "", "<EMPTY>",
    default = PAYER_TYPE_PRIMARY
  )]
  primary_freq_dt <- enc_dt[, .(n = .N), by = .(code)]
  # Keyed join for AMC category (replaces AMC_PAYER_LOOKUP[code] named-vector lookup)
  amc_lookup <- get_lookup_dt("AMC_PAYER_LOOKUP")
  primary_freq_dt[amc_lookup, on = .(code), amc_category := i.payer_category]
  # Missing codes
  primary_freq_dt[code %in% c("<NA>", "<EMPTY>"), amc_category := "Missing"]
  # Prefix fallback for unmapped codes (where amc_category is still NA after join)
  primary_freq_dt[is.na(amc_category), amc_category := fcase(
    startsWith(code, "1"), "Medicare",
    startsWith(code, "2"), "Medicaid",
    startsWith(code, "5") | startsWith(code, "6") | startsWith(code, "7"), "Private",
    startsWith(code, "3") | startsWith(code, "4"), "Other govt",
    startsWith(code, "8"), "Uninsured",
    startsWith(code, "9"), "Other",
    default = "Other"
  )]
  primary_freq_dt[, pct := round(100 * n / total_enc, 2)]
  setorder(primary_freq_dt, -n)
  primary_freq_dt <- primary_freq_dt[, .(code, amc_category, n, pct)]
  primary_freq <- to_tibble_safe(primary_freq_dt, name = "primary_freq", script_name = "R/60")

  # --- SECONDARY frequency table ---
  # (same pattern as primary but uses PAYER_TYPE_SECONDARY)
  enc_dt2 <- copy(ensure_dt(enc_scope, name = "enc_scope", script_name = "R/60"))
  enc_dt2[, code := fcase(
    is.na(PAYER_TYPE_SECONDARY), "<NA>",
    PAYER_TYPE_SECONDARY == "", "<EMPTY>",
    default = PAYER_TYPE_SECONDARY
  )]
  secondary_freq_dt <- enc_dt2[, .(n = .N), by = .(code)]
  secondary_freq_dt[amc_lookup, on = .(code), amc_category := i.payer_category]
  secondary_freq_dt[code %in% c("<NA>", "<EMPTY>"), amc_category := "Missing"]
  secondary_freq_dt[is.na(amc_category), amc_category := fcase(
    startsWith(code, "1"), "Medicare",
    startsWith(code, "2"), "Medicaid",
    startsWith(code, "5") | startsWith(code, "6") | startsWith(code, "7"), "Private",
    startsWith(code, "3") | startsWith(code, "4"), "Other govt",
    startsWith(code, "8"), "Uninsured",
    startsWith(code, "9"), "Other",
    default = "Other"
  )]
  secondary_freq_dt[, pct := round(100 * n / total_enc, 2)]
  setorder(secondary_freq_dt, -n)
  secondary_freq_dt <- secondary_freq_dt[, .(code, amc_category, n, pct)]
  secondary_freq <- to_tibble_safe(secondary_freq_dt, name = "secondary_freq", script_name = "R/60")

  # --- Category-level summary ---
  primary_cat_dt <- primary_freq_dt[, .(n = sum(n)), by = .(amc_category)]
  primary_cat_dt[, `:=`(field = "PRIMARY", pct = round(100 * n / total_enc, 2))]
  primary_cat_dt <- primary_cat_dt[, .(field, amc_category, n, pct)]
  setorder(primary_cat_dt, -n)

  secondary_cat_dt <- secondary_freq_dt[, .(n = sum(n)), by = .(amc_category)]
  secondary_cat_dt[, `:=`(field = "SECONDARY", pct = round(100 * n / total_enc, 2))]
  secondary_cat_dt <- secondary_cat_dt[, .(field, amc_category, n, pct)]
  setorder(secondary_cat_dt, -n)

  category_summary <- to_tibble_safe(
    rbindlist(list(primary_cat_dt, secondary_cat_dt)),
    name = "category_summary", script_name = "R/60"
  )

  # Write CSVs (same filenames, same output_dir)
  write_csv(primary_freq, file.path(output_dir, paste0("payer_primary_code_freq", suffix, ".csv")))
  write_csv(secondary_freq, file.path(output_dir, paste0("payer_secondary_code_freq", suffix, ".csv")))
  write_csv(category_summary, file.path(output_dir, paste0("payer_category_summary", suffix, ".csv")))

  # Preserve ALL existing message() calls exactly as-is
  message(glue("  Written: payer_primary_code_freq{suffix}.csv ({nrow(primary_freq)} rows)"))
  message(glue("  Written: payer_secondary_code_freq{suffix}.csv ({nrow(secondary_freq)} rows)"))
  message(glue("  Written: payer_category_summary{suffix}.csv ({nrow(category_summary)} rows)"))

  # Fallback diagnostics -- use original named vector for this diagnostic count
  # (not on hot path; exact backward compatibility of message output matters more)
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

  # --- Resolved detail (data.table aggregation) ---
  enc_dt <- copy(ensure_dt(enc_scope, name = "enc_scope", script_name = "R/60"))
  enc_dt <- enc_dt[!is.na(admit_date_parsed)]
  setkey(enc_dt, ID, admit_date_parsed)  # KEY OPTIMIZATION: setkey before [, by=]

  resolved_detail_dt <- enc_dt[, .(
    n_encounters = .N,
    n_distinct_tiers = length(unique(tier)),
    has_flm = any(SOURCE == "FLM", na.rm = TRUE),
    has_special_code = any(PAYER_TYPE_PRIMARY %in% c("93", "14") |
      PAYER_TYPE_SECONDARY %in% c("93", "14"), na.rm = TRUE),
    original_tiers = paste(sort(unique(tier)), collapse = "+"),
    original_codes_primary = paste(sort(unique(na.omit(PAYER_TYPE_PRIMARY))), collapse = ","),
    resolved_payer = fcase(
      any(SOURCE == "FLM", na.rm = TRUE), "Medicaid",
      any(PAYER_TYPE_PRIMARY %in% c("93", "14") |
        PAYER_TYPE_SECONDARY %in% c("93", "14"), na.rm = TRUE), "Medicaid",
      default = tier[which.min(tier_rank)]
    ),
    resolution_reason = {
      n_enc <- .N
      n_tiers <- length(unique(tier))
      fcase(
        n_enc == 1L, "single encounter",
        any(SOURCE == "FLM", na.rm = TRUE), "FLM source override",
        any(PAYER_TYPE_PRIMARY %in% c("93", "14") |
          PAYER_TYPE_SECONDARY %in% c("93", "14"), na.rm = TRUE), "special code override (93/14)",
        n_tiers == 1L, "all encounters same tier",
        default = paste0("tier hierarchy (", n_tiers, " tiers)")
      )
    }
  ), by = .(ID, admit_date_parsed)]

  setnames(resolved_detail_dt, "admit_date_parsed", "ADMIT_DATE")
  setorder(resolved_detail_dt, ID, ADMIT_DATE)
  resolved_detail <- to_tibble_safe(resolved_detail_dt, name = "resolved_detail", script_name = "R/60")

  # CSV A: Per-patient-per-date detail
  write_csv(resolved_detail, file.path(output_dir, paste0("payer_resolved_detail", suffix, ".csv")))
  message(glue("  Written: payer_resolved_detail{suffix}.csv ({nrow(resolved_detail)} rows)"))

  # --- CSV B: Patient-level modal summary ---
  rd_dt <- copy(ensure_dt(resolved_detail, name = "resolved_detail", script_name = "R/60"))
  patient_total_dates <- rd_dt[, .(total_dates = .N), by = .(ID)]

  patient_summary_dt <- rd_dt[, .(n_dates_with_payer = .N), by = .(ID, resolved_payer)]
  setorder(patient_summary_dt, ID, -n_dates_with_payer, resolved_payer)
  patient_summary_dt <- patient_summary_dt[, .SD[1], by = .(ID)]
  setnames(patient_summary_dt, "resolved_payer", "modal_resolved_payer")
  patient_summary_dt[patient_total_dates, on = .(ID), total_dates := i.total_dates]
  patient_summary <- to_tibble_safe(patient_summary_dt, name = "patient_summary", script_name = "R/60")

  write_csv(patient_summary, file.path(output_dir, paste0("payer_resolved_patient_summary", suffix, ".csv")))
  message(glue("  Written: payer_resolved_patient_summary{suffix}.csv ({nrow(patient_summary)} rows)"))

  # --- CSV C: Before vs after impact ---
  enc_dt_impact <- copy(ensure_dt(enc_scope, name = "enc_scope", script_name = "R/60"))
  enc_dt_impact <- enc_dt_impact[!is.na(admit_date_parsed)]

  tier_order <- names(TIER_MAPPING)
  before_dt <- enc_dt_impact[, .(n_encounters_before = .N), by = .(tier)]
  before_dt[, tier_ord := match(tier, tier_order)]
  setorder(before_dt, tier_ord)
  before_dt[, tier_ord := NULL]

  rd_dt2 <- copy(ensure_dt(resolved_detail, name = "resolved_detail", script_name = "R/60"))
  after_dt <- rd_dt2[, .(n_patient_dates_after = .N), by = .(resolved_payer)]
  after_dt[, payer_ord := match(resolved_payer, tier_order)]
  setorder(after_dt, payer_ord)
  after_dt[, payer_ord := NULL]

  # Full join equivalent in data.table: merge with all=TRUE
  impact_dt <- merge(before_dt, after_dt, by.x = "tier", by.y = "resolved_payer", all = TRUE)
  impact_dt[is.na(n_encounters_before), n_encounters_before := 0L]
  impact_dt[is.na(n_patient_dates_after), n_patient_dates_after := 0L]
  total_before <- sum(impact_dt$n_encounters_before)
  total_after <- sum(impact_dt$n_patient_dates_after)
  impact_dt[, `:=`(
    pct_encounters_before = round(100 * n_encounters_before / total_before, 2),
    pct_patient_dates_after = round(100 * n_patient_dates_after / total_after, 2)
  )]
  setnames(impact_dt, "tier", "category")
  impact <- to_tibble_safe(impact_dt, name = "impact", script_name = "R/60")

  write_csv(impact, file.path(output_dir, paste0("payer_resolved_impact", suffix, ".csv")))
  message(glue("  Written: payer_resolved_impact{suffix}.csv ({nrow(impact)} rows)"))

  # Log summary (unchanged logic, use resolved_detail tibble)
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
