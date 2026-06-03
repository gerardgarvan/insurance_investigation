# ==============================================================================
# 88_smoke_test_comprehensive.R -- Comprehensive Structural Smoke Test
# ==============================================================================
#
# Purpose:
#   Comprehensive structural smoke test validating pipeline integrity after v2.0
#   codebase cleanup. Consolidates R/86 + R/87 checks and adds DRY consolidation,
#   defensive coding, and config constant validation. WHY comprehensive: Final
#   validation layer superseding R/86 and R/87 by including all their checks plus
#   Phase 72-73 work (assertions, DRY compliance).
#   Phase 76 TR removal (TREAT-01) validation.
#   WHY standalone: Runs via Rscript with zero external dependencies on data
#   availability.
#
# Inputs:
#   - R/ directory filesystem structure
#   - R/00_config.R (sourced for constant validation)
#
# Outputs:
#   - Console output (PASS/FAIL per check group)
#   - Exit code 1 on any failure (SLURM-compatible)
#
# Dependencies:
#   - glue (string interpolation for logging)
#
# Requirements:
#   - REORG-05: Smoke test validates no broken cross-references
#   - SAFE-06: Comprehensive smoke test suite
#
# Usage:
#   Rscript R/88_smoke_test_comprehensive.R
#
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP ----
# ==============================================================================

# Clear workspace to avoid stale references
rm(list = ls())

library(glue)

passed <- 0L
failed <- 0L

check <- function(description, condition) {
  if (condition) {
    message(glue("  PASS: {description}"))
    passed <<- passed + 1L
  } else {
    message(glue("  FAIL: {description}"))
    failed <<- failed + 1L
  }
}

message(strrep("=", 70))
message("SMOKE TEST: Comprehensive Pipeline Validation (v2.1)")
message(strrep("=", 70))

# ==============================================================================
# SECTION 2: UTILS MODULE COMPLETENESS ----
# ==============================================================================

message("\n[1/19] Utils module completeness...")

check("R/utils/ directory exists", dir.exists("R/utils"))

expected_utils <- c(
  "utils_assertions.R", "utils_attrition.R", "utils_cancer.R",
  "utils_dates.R", "utils_duckdb.R", "utils_icd.R",
  "utils_payer.R", "utils_pptx.R", "utils_snapshot.R",
  "utils_treatment.R"
)

utils_files <- list.files("R/utils", pattern = "\\.R$")
check(
  glue("R/utils/ contains 10 files (found {length(utils_files)})"),
  length(utils_files) == 10
)

missing_utils <- setdiff(expected_utils, utils_files)
check(
  glue("All expected utils present (missing: {paste(missing_utils, collapse=', ') %||% 'none'})"),
  length(missing_utils) == 0
)

# No stale utils files in R/ root
stale_utils <- list.files("R", pattern = "^utils_.*\\.R$")
check(
  glue("No utils_*.R in R/ root (found: {paste(stale_utils, collapse=', ') %||% 'none'})"),
  length(stale_utils) == 0
)

# ==============================================================================
# SECTION 3: CONFIG LOADING AND AUTO-SOURCING ----
# ==============================================================================

message("\n[2/19] Config loading and auto-sourcing...")

tryCatch(
  {
    source("R/00_config.R")
    check("00_config.R loads without error", TRUE)
  },
  error = function(e) {
    check(glue("00_config.R loads without error -- {e$message}"), FALSE)
  }
)

# Validate 11 expected config constants
config_constants <- c(
  "CONFIG", "EXTRACT_DATE", "PCORNET_TABLES", "PCORNET_PATHS",
  "ICD_CODES", "PAYER_MAPPING", "AMC_PAYER_LOOKUP", "TREATMENT_CODES",
  "CANCER_SITE_MAP", "TIER_MAPPING"
)

for (const_name in config_constants) {
  check(glue("{const_name} defined in config"), exists(const_name))
}

# Validate CANCER_SITE_MAP structure
if (exists("CANCER_SITE_MAP")) {
  check(
    "CANCER_SITE_MAP is named character vector",
    is.character(CANCER_SITE_MAP) && !is.null(names(CANCER_SITE_MAP))
  )
  check(
    glue("CANCER_SITE_MAP contains >= 100 mappings (found {length(CANCER_SITE_MAP)})"),
    length(CANCER_SITE_MAP) >= 100
  )
}

# Validate TIER_MAPPING structure
if (exists("TIER_MAPPING")) {
  check("TIER_MAPPING is list", is.list(TIER_MAPPING))
  check(
    glue("TIER_MAPPING contains 8 tiers (found {length(TIER_MAPPING)})"),
    length(TIER_MAPPING) == 8
  )
}

# Validate key auto-sourced functions exist
key_functions <- list(
  utils_dates      = "parse_pcornet_date",
  utils_attrition  = "log_attrition",
  utils_icd        = "normalize_icd",
  utils_snapshot   = c("save_output_data", "build_output_path"),
  utils_duckdb     = "open_pcornet_con",
  utils_treatment  = "safe_table",
  utils_payer      = c("is_missing_payer", "classify_payer_tier"),
  utils_pptx       = "style_table",
  utils_assertions = c("assert_rds_exists", "assert_df_valid", "assert_col_types"),
  utils_cancer     = "classify_codes"
)

for (module in names(key_functions)) {
  func_names <- key_functions[[module]]
  for (func_name in func_names) {
    check(glue("{module}: {func_name}() exists"), exists(func_name))
  }
}

# ==============================================================================
# SECTION 4: FOUNDATION CHAIN ----
# ==============================================================================

message("\n[3/19] Foundation script chain...")

check("R/00_config.R exists", file.exists("R/00_config.R"))
check("R/01_load_pcornet.R exists", file.exists("R/01_load_pcornet.R"))
check("R/02_harmonize_payer.R exists", file.exists("R/02_harmonize_payer.R"))
check("R/03_duckdb_ingest.R exists", file.exists("R/03_duckdb_ingest.R"))
check(
  "R/25_duckdb_ingest.R removed (old location)",
  !file.exists("R/25_duckdb_ingest.R")
)

# ==============================================================================
# SECTION 5: DECADE VALIDATION ----
# ==============================================================================

# --------------------------------------------------------------------------
# Cohort decade (10-14)
# --------------------------------------------------------------------------
message("\n[4/19] Cohort decade (10-14)...")

cohort_scripts <- c(
  "10_cohort_predicates.R", "11_treatment_payer.R",
  "12_surveillance.R", "13_survivorship_encounters.R",
  "14_build_cohort.R"
)
cohort_found <- 0L
for (s in cohort_scripts) {
  if (file.exists(file.path("R", s))) cohort_found <- cohort_found + 1L
}
check(
  glue("Cohort decade: 5/5 scripts (found {cohort_found})"),
  cohort_found == 5
)

# --------------------------------------------------------------------------
# Treatment decade (20-29)
# --------------------------------------------------------------------------
message("\n[5/19] Treatment decade (20-29)...")

treatment_expected <- c(
  "20_treatment_inventory.R", "21_investigate_unmatched.R",
  "22_investigate_unmatched_ndc.R", "23_combine_reports.R",
  "24_treatment_codes_resolved.R", "25_treatment_durations.R",
  "26_treatment_episodes.R", "27_drug_name_resolution.R",
  "28_episode_classification.R", "29_first_line_and_death_analysis.R"
)
treatment_found <- 0L
for (s in treatment_expected) {
  if (file.exists(file.path("R", s))) treatment_found <- treatment_found + 1L
}
check(
  glue("Treatment decade: 10/10 scripts (found {treatment_found})"),
  treatment_found == 10
)

# --------------------------------------------------------------------------
# Cancer decade (40-53)
# --------------------------------------------------------------------------
message("\n[6/19] Cancer decade (40-53)...")

cancer_expected <- c(
  "40_cancer_site_frequency.R", "41_extract_all_codes.R",
  "42_build_code_descriptions.R", "43_cancer_site_confirmation.R",
  "44_cancer_site_confirmation_7day.R", "45_cancer_summary.R",
  "46_cancer_summary_table.R", "47_cancer_summary_refined.R",
  "48_cancer_summary_post_hl.R", "49_cancer_summary_pre_post.R",
  "50_all_codes_resolved.R", "51_gantt_data_export.R",
  "52_gantt_v2_export.R", "53_death_date_validation.R"
)
cancer_found <- 0L
for (s in cancer_expected) {
  if (file.exists(file.path("R", s))) cancer_found <- cancer_found + 1L
}
check(
  glue("Cancer decade: 14/14 scripts (found {cancer_found})"),
  cancer_found == 14
)

# --------------------------------------------------------------------------
# Payer/QA decade (60-69)
# --------------------------------------------------------------------------
message("\n[7/19] Payer/QA decade (60-69)...")

payer_expected <- c(
  "60_tiered_same_day_payer.R", "61_tiered_encounter_level.R",
  "62_tiered_date_level.R", "63_value_audit.R",
  "64_all_source_missingness.R", "65_uf_insurance_missingness.R",
  "66_all_site_duplicate_dates.R",
  "67_multi_source_overlap_detection.R",
  "68_overlap_classification.R", "69_per_patient_source_detection.R"
)
payer_found <- 0L
for (s in payer_expected) {
  if (file.exists(file.path("R", s))) payer_found <- payer_found + 1L
}
check(
  glue("Payer/QA decade: 10/10 scripts (found {payer_found})"),
  payer_found == 10
)

# --------------------------------------------------------------------------
# Output decade (70-75)
# --------------------------------------------------------------------------
message("\n[8/19] Output decade (70-75)...")

output_scripts <- c(
  "70_visualize_waterfall.R", "71_visualize_sankey.R",
  "72_generate_pptx.R", "73_generate_phase19_20_pptx.R",
  "74_generate_documentation.R", "75_encounter_analysis.R"
)
output_found <- 0L
for (s in output_scripts) {
  if (file.exists(file.path("R", s))) output_found <- output_found + 1L
}
check(
  glue("Output decade: 6/6 scripts (found {output_found})"),
  output_found == 6
)

# --------------------------------------------------------------------------
# Test decade (80-88)
# --------------------------------------------------------------------------
message("\n[9/19] Test decade (80-88)...")

test_scripts <- c(
  "80_smoke_test_backends.R", "81_parity_test_cohort.R",
  "82_benchmark_cohort.R", "83_generate_speedup_report.R",
  "84_test_durations.R", "85_test_episodes.R",
  "86_smoke_test_foundation.R", "87_smoke_test_full_pipeline.R",
  "88_smoke_test_comprehensive.R"
)
test_found <- 0L
for (s in test_scripts) {
  if (file.exists(file.path("R", s))) test_found <- test_found + 1L
}
check(
  glue("Test decade: 9/9 scripts (found {test_found})"),
  test_found == 9
)

# --------------------------------------------------------------------------
# Ad-hoc decade (90-99)
# --------------------------------------------------------------------------
message("\n[10/19] Ad-hoc decade (90-99)...")

adhoc_scripts <- c(
  "90_diagnostics.R", "91_data_quality_summary.R",
  "92_dx_gap_analysis.R", "93_no_treatment_medicaid.R",
  "94_flm_duplicate_dates.R", "95_multi_source_overlap_av_th.R",
  "96_overlap_classification_av_th.R", "97_payer_code_frequency_av_th.R",
  "98_radiation_cpt_audit.R", "99_claude_diagnostics.R"
)
adhoc_found <- 0L
for (s in adhoc_scripts) {
  if (file.exists(file.path("R", s))) adhoc_found <- adhoc_found + 1L
}
check(
  glue("Ad-hoc decade: 10/10 scripts (found {adhoc_found})"),
  adhoc_found == 10
)

# ==============================================================================
# SECTION 6: NO STALE FILES ----
# ==============================================================================

message("\n[11/19] No stale files...")

# Check for specific old numbers that should have been renamed
old_numbers <- c(
  "05_visualize_waterfall.R", "11_generate_pptx.R",
  "16_encounter_analysis.R", "26_smoke_test_backends.R",
  "07_diagnostics.R", "19_flm_duplicate_dates.R",
  "33_multi_source_overlap_av_th.R"
)
stale_files <- character(0)
for (old in old_numbers) {
  if (file.exists(file.path("R", old))) {
    stale_files <- c(stale_files, old)
  }
}
check(
  glue("No stale old-numbered files (found: {paste(stale_files, collapse=', ') %||% 'none'})"),
  length(stale_files) == 0
)

# Check no a/b suffixed files
r_files <- list.files("R", pattern = "\\.R$")
ab_pattern <- "^[0-9]+[ab]_"
ab_suffixed <- grep(ab_pattern, r_files, value = TRUE)
check(
  glue("No a/b suffixed files (found: {paste(ab_suffixed, collapse=', ') %||% 'none'})"),
  length(ab_suffixed) == 0
)

# ==============================================================================
# SECTION 7: SOURCE() REFERENCE VALIDATION ----
# ==============================================================================

message("\n[12/19] Source() reference validation...")

r_files_full <- list.files("R", pattern = "\\.R$", full.names = TRUE)
broken_refs <- character(0)
for (f in r_files_full) {
  lines <- readLines(f, warn = FALSE)
  # Extract source("R/...") patterns (ignore commented lines)
  source_lines <- grep('^[^#]*source\\("R/', lines, value = TRUE)

  for (line in source_lines) {
    # Extract path from source("R/...")
    matches <- regmatches(line, gregexpr('source\\("R/[^"]+\\.R"\\)', line))
    for (match_list in matches) {
      for (m in match_list) {
        path <- sub('source\\("', "", m)
        path <- sub('"\\)', "", path)
        if (!file.exists(path)) {
          broken_refs <- c(broken_refs, glue("{basename(f)}: {path}"))
        }
      }
    }
  }
}
check(
  glue("No broken source() calls (found: {paste(broken_refs, collapse=', ') %||% 'none'})"),
  length(broken_refs) == 0
)

# Check no old-style utils source paths (exclude smoke test files which
# contain the pattern in grep strings, not actual source() calls)
stale_utils_refs <- character(0)
smoke_test_files <- c("86_smoke_test_foundation.R", "87_smoke_test_full_pipeline.R",
                       "88_smoke_test_comprehensive.R")
for (f in r_files_full) {
  if (basename(f) %in% smoke_test_files) next
  lines <- readLines(f, warn = FALSE)
  # Match source("R/utils_ but NOT source("R/utils/utils_
  hits <- grep('source\\("R/utils_', lines)
  if (length(hits) > 0) {
    stale_utils_refs <- c(stale_utils_refs, glue("{basename(f)}:{hits}"))
  }
}
check(
  glue("No old-style source() paths (found: {paste(stale_utils_refs, collapse=', ') %||% 'none'})"),
  length(stale_utils_refs) == 0
)

# ==============================================================================
# SECTION 8: KEY DEPENDENCY CHAINS ----
# ==============================================================================

message("\n[13/19] Key dependency chains...")

# Check critical source() patterns
check_source <- function(file, pattern, description) {
  if (!file.exists(file)) {
    return(FALSE)
  }
  lines <- readLines(file, warn = FALSE)
  any(grepl(pattern, lines))
}

check(
  "14_build_cohort.R sources 10_cohort_predicates.R",
  check_source("R/14_build_cohort.R", 'source\\("R/10_cohort_predicates\\.R"\\)', "")
)
check(
  "14_build_cohort.R sources 11_treatment_payer.R",
  check_source("R/14_build_cohort.R", 'source\\("R/11_treatment_payer\\.R"\\)', "")
)
check(
  "26_treatment_episodes.R sources 25_treatment_durations.R",
  check_source("R/26_treatment_episodes.R", 'source\\("R/25_treatment_durations\\.R"\\)', "")
)
check(
  "72_generate_pptx.R sources 75_encounter_analysis.R",
  check_source("R/72_generate_pptx.R", 'source\\("R/75_encounter_analysis\\.R"\\)', "")
)
check(
  "73_generate_phase19_20_pptx.R sources 94_flm_duplicate_dates.R",
  check_source("R/73_generate_phase19_20_pptx.R", "R/94_flm_duplicate_dates\\.R", "")
)

# ==============================================================================
# SECTION 9: DRY CONSOLIDATION VALIDATION ----
# ==============================================================================

message("\n[14/19] DRY consolidation validation...")

# Check no PREFIX_MAP definitions outside R/00_config.R
scripts_to_check_prefix <- c(
  "R/28_episode_classification.R",
  "R/40_cancer_site_frequency.R", "R/41_extract_all_codes.R",
  "R/43_cancer_site_confirmation.R", "R/44_cancer_site_confirmation_7day.R",
  "R/45_cancer_summary.R", "R/46_cancer_summary_table.R",
  "R/47_cancer_summary_refined.R", "R/48_cancer_summary_post_hl.R",
  "R/49_cancer_summary_pre_post.R",
  "R/51_gantt_data_export.R", "R/52_gantt_v2_export.R"
)

duplicate_prefix_map <- character(0)
for (script in scripts_to_check_prefix) {
  if (file.exists(script)) {
    lines <- readLines(script, warn = FALSE)
    # Remove comments
    uncommented <- gsub("#.*$", "", lines)
    # Check for PREFIX_MAP <-
    if (any(grepl("^PREFIX_MAP\\s*<-", uncommented))) {
      duplicate_prefix_map <- c(duplicate_prefix_map, basename(script))
    }
  }
}
check(
  glue("No duplicate PREFIX_MAP outside R/00_config.R (found: {paste(duplicate_prefix_map, collapse=', ') %||% 'none'})"),
  length(duplicate_prefix_map) == 0
)

# Check no TIER_MAPPING definitions outside R/00_config.R
scripts_to_check_tier <- c(
  "R/60_tiered_same_day_payer.R",
  "R/61_tiered_encounter_level.R",
  "R/62_tiered_date_level.R"
)

duplicate_tier_mapping <- character(0)
for (script in scripts_to_check_tier) {
  if (file.exists(script)) {
    lines <- readLines(script, warn = FALSE)
    uncommented <- gsub("#.*$", "", lines)
    if (any(grepl("^TIER_MAPPING\\s*<-", uncommented))) {
      duplicate_tier_mapping <- c(duplicate_tier_mapping, basename(script))
    }
  }
}
check(
  glue("No duplicate TIER_MAPPING outside R/00_config.R (found: {paste(duplicate_tier_mapping, collapse=', ') %||% 'none'})"),
  length(duplicate_tier_mapping) == 0
)

# Check no classify_codes function definitions outside R/utils/utils_cancer.R
duplicate_classify_codes <- character(0)
for (script in scripts_to_check_prefix) {
  if (file.exists(script)) {
    lines <- readLines(script, warn = FALSE)
    uncommented <- gsub("#.*$", "", lines)
    if (any(grepl("^classify_codes\\s*<-", uncommented))) {
      duplicate_classify_codes <- c(duplicate_classify_codes, basename(script))
    }
  }
}
check(
  glue("No duplicate classify_codes() outside R/utils/utils_cancer.R (found: {paste(duplicate_classify_codes, collapse=', ') %||% 'none'})"),
  length(duplicate_classify_codes) == 0
)

# ==============================================================================
# SECTION 10: DEFENSIVE CODING INFRASTRUCTURE ----
# ==============================================================================

message("\n[15/19] Defensive coding infrastructure...")

# Check library(checkmate) appears in R/00_config.R
config_lines <- readLines("R/00_config.R", warn = FALSE)
check(
  "library(checkmate) loaded in R/00_config.R",
  any(grepl("library\\(checkmate\\)", config_lines))
)

# Check R/utils/utils_assertions.R exists
check("R/utils/utils_assertions.R exists", file.exists("R/utils/utils_assertions.R"))

# Check key assertion functions exist after config load
assertion_functions <- c("assert_rds_exists", "assert_df_valid", "assert_col_types", "warn_date_range", "warn_row_count")
for (func in assertion_functions) {
  check(glue("Assertion helper: {func}() exists"), exists(func))
}

# ==============================================================================
# SECTION 11: ARCHIVE VALIDATION ----
# ==============================================================================

message("\n[16/19] Archive validation...")

check("R/archive/ directory exists", dir.exists("R/archive"))
check("R/archive/README.md exists", file.exists("R/archive/README.md"))

expected_archived <- c(
  "check_deleted_proton_code.R", "date_range_check.R",
  "payer_frequency_from_resolved.R", "run_phase12_outputs.R",
  "sct_code_inventory.R", "search_C8190.R",
  "tiered_payer_summary.R", "treatment_cross_reference.R"
)
archived_files <- list.files("R/archive", pattern = "\\.R$")
check(
  glue("R/archive/ contains 8 files (found {length(archived_files)})"),
  length(archived_files) == 8
)

# ==============================================================================
# SECTION 12: CROSS-PLATFORM DATA AVAILABILITY ----
# ==============================================================================

message("\n[17/19] Cross-platform data availability...")

# Detect data availability
if (exists("CONFIG")) {
  DATA_AVAILABLE <- dir.exists(CONFIG$data_dir)
  PLATFORM <- .Platform$OS.type

  message(glue("\nPlatform: {PLATFORM}"))
  message(glue("Data available: {DATA_AVAILABLE}"))

  if (DATA_AVAILABLE) {
    # Check ENROLLMENT CSV exists (uses PCORNET_PATHS which handles the actual filename)
    if (exists("PCORNET_PATHS") && "ENROLLMENT" %in% names(PCORNET_PATHS)) {
      enrollment_path <- PCORNET_PATHS[["ENROLLMENT"]]
    } else {
      enrollment_path <- file.path(CONFIG$data_dir, "ENROLLMENT.csv")
    }
    check(glue("ENROLLMENT CSV exists at data_dir ({basename(enrollment_path)})"),
          file.exists(enrollment_path))

    # Check cache directories exist
    check("cache$raw_dir exists", dir.exists(CONFIG$cache$raw_dir))
    check("cache$cohort_dir exists", dir.exists(CONFIG$cache$cohort_dir))
  } else {
    message("\n[Skipping data-dependent checks -- data not available on this platform]")
  }
} else {
  message("\n[CONFIG not loaded -- skipping data availability check]")
}

# ==============================================================================
# SECTION 13: NLPHL CLASSIFICATION & DEATH CAUSE VALIDATION ----
# ==============================================================================
# Phase 75 (CANCER-01): Validates NLPHL breakout mutual exclusivity.
# Phase 75 (DEATH-01/DEATH-02): Validates DEATH_CAUSE_MAP structure.

message("\n[18/19] NLPHL classification & death cause validation...")

# --- NLPHL ICD-10 mutual exclusivity ---

# Test data: codes that MUST classify as NLPHL
nlphl_icd10 <- c("C810", "C8100", "C8105", "C8109")
nlphl_icd9 <- c("201.4", "201.40", "201.45", "201.48")

# Test data: codes that MUST classify as classical HL (non-NLPHL)
classical_icd10 <- c("C811", "C8110", "C812", "C8120", "C819", "C8190")
classical_icd9 <- c("201.0", "201.00", "201.5", "201.50", "201.9", "201.90")

# Classify all test codes
nlphl_10_results <- classify_codes(nlphl_icd10)
nlphl_9_results <- classify_codes(nlphl_icd9)
classical_10_results <- classify_codes(classical_icd10)
classical_9_results <- classify_codes(classical_icd9)

# Check 1: NLPHL ICD-10 codes -> "NLPHL"
check(
  "ICD-10 C81.0x codes classify as 'NLPHL'",
  all(nlphl_10_results == "NLPHL", na.rm = TRUE)
)

# Check 2: NLPHL ICD-9 codes -> "NLPHL"
check(
  "ICD-9 201.4x codes classify as 'NLPHL'",
  all(nlphl_9_results == "NLPHL", na.rm = TRUE)
)

# Check 3: Classical HL ICD-10 codes -> "Hodgkin Lymphoma (non-NLPHL)"
check(
  "ICD-10 C81.1-C81.9 codes classify as 'Hodgkin Lymphoma (non-NLPHL)'",
  all(classical_10_results == "Hodgkin Lymphoma (non-NLPHL)", na.rm = TRUE)
)

# Check 4: Classical HL ICD-9 codes -> "Hodgkin Lymphoma (non-NLPHL)"
check(
  "ICD-9 201.0-201.9 (except 201.4x) classify as 'Hodgkin Lymphoma (non-NLPHL)'",
  all(classical_9_results == "Hodgkin Lymphoma (non-NLPHL)", na.rm = TRUE)
)

# Check 5: Mutual exclusivity — NLPHL count + classical count = total
all_hl_codes <- c(nlphl_icd10, nlphl_icd9, classical_icd10, classical_icd9)
all_hl_results <- classify_codes(all_hl_codes)
nlphl_count <- sum(all_hl_results == "NLPHL", na.rm = TRUE)
classical_count <- sum(all_hl_results == "Hodgkin Lymphoma (non-NLPHL)", na.rm = TRUE)
total_hl <- length(all_hl_codes)

check(
  glue("Mutual exclusivity: NLPHL ({nlphl_count}) + classical ({classical_count}) = total ({total_hl})"),
  (nlphl_count + classical_count) == total_hl
)

# Check 6: CANCER_SITE_MAP contains C810 entry
check(
  "CANCER_SITE_MAP has 'C810' = 'NLPHL'",
  "C810" %in% names(CANCER_SITE_MAP) && CANCER_SITE_MAP["C810"] == "NLPHL"
)

# Check 7: CANCER_SITE_MAP contains C81 entry with updated name
check(
  "CANCER_SITE_MAP has 'C81' = 'Hodgkin Lymphoma (non-NLPHL)'",
  "C81" %in% names(CANCER_SITE_MAP) && CANCER_SITE_MAP["C81"] == "Hodgkin Lymphoma (non-NLPHL)"
)

# Check 8: ICD9_NLPHL_CODES has expected count
check(
  glue("ICD9_NLPHL_CODES contains 10 codes (found {length(ICD9_NLPHL_CODES)})"),
  length(ICD9_NLPHL_CODES) == 10
)

# --- DEATH_CAUSE_MAP validation ---

# Check 9: DEATH_CAUSE_MAP exists and has sufficient coverage
check(
  glue("DEATH_CAUSE_MAP has >= 30 entries (found {length(DEATH_CAUSE_MAP)})"),
  exists("DEATH_CAUSE_MAP") && length(DEATH_CAUSE_MAP) >= 30
)

# Check 10: DEATH_CAUSE_MAP has UNK fallback
check(
  "DEATH_CAUSE_MAP has 'UNK' = 'Unknown or Unspecified'",
  "UNK" %in% names(DEATH_CAUSE_MAP) &&
    DEATH_CAUSE_MAP["UNK"] == "Unknown or Unspecified"
)

# Check 11: DEATH_CAUSE_MAP covers major ICD-10 chapters
major_chapters <- c("C81", "I25", "J44", "E11", "G30")
chapter_hits <- sum(major_chapters %in% names(DEATH_CAUSE_MAP))
check(
  glue("DEATH_CAUSE_MAP covers major ICD-10 chapters ({chapter_hits}/5 present)"),
  chapter_hits == 5
)

# ==============================================================================
# SECTION 13B: TR REMOVAL VALIDATION ----
# ==============================================================================
# Phase 76 (TREAT-01): Validates tumor registry source removed from R/26.

message("\n[19/21] TR removal validation...")

# Read R/26 source code for static analysis
r26_lines <- readLines("R/26_treatment_episodes.R")
r26_text <- paste(r26_lines, collapse = "\n")

# Check 1: No live tr_dates assignments (blocks should be deleted)
tr_dates_assignments <- sum(grepl("tr_dates <- NULL", r26_lines, fixed = TRUE))
check(
  glue("R/26 has no tr_dates <- NULL assignments (found {tr_dates_assignments})"),
  tr_dates_assignments == 0
)

# Check 2: No TR in any sources list
tr_source_refs <- sum(grepl("TR = tr_dates", r26_lines, fixed = TRUE))
check(
  glue("R/26 has no TR = tr_dates in sources lists (found {tr_source_refs})"),
  tr_source_refs == 0
)

# Check 3: No live TUMOR_REGISTRY_ALL calls (only in comments)
# Lines that call get_pcornet_table("TUMOR_REGISTRY_ALL") should not exist
# Comments (lines starting with #) are acceptable
live_tr_lines <- r26_lines[!grepl("^\\s*#", r26_lines)]
live_tr_refs <- sum(grepl("TUMOR_REGISTRY_ALL", live_tr_lines, fixed = TRUE))
check(
  glue("R/26 has no live TUMOR_REGISTRY_ALL references (found {live_tr_refs})"),
  live_tr_refs == 0
)

# Check 4: Phase 76 removal comments present (one per extraction function)
removal_comments <- sum(grepl("Phase 76: Tumor registry source removed", r26_lines, fixed = TRUE))
check(
  glue("R/26 has 3 Phase 76 removal comments (found {removal_comments})"),
  removal_comments == 3
)

# Check 5: EPISODE_COUNT_BASELINE defined
baseline_def <- sum(grepl("EPISODE_COUNT_BASELINE", r26_lines, fixed = TRUE))
check(
  glue("R/26 defines EPISODE_COUNT_BASELINE (found {baseline_def} refs)"),
  baseline_def >= 2
)

# Check 6: Chemo sources list has 6 entries (no TR)
# Find the chemo stack_and_dedup_with_codes call and verify source count
chemo_section <- r26_text
chemo_has_6 <- grepl(
  "PX = px_dates.*RX = rx_dates.*DX = dx_dates.*DRG = drg_dates.*DISP = disp_dates.*MA = ma_dates",
  chemo_section
) && !grepl("TR = tr_dates.*type_name = .Chemotherapy", chemo_section)
check("Chemotherapy uses 6 sources (PX, RX, DX, DRG, DISP, MA)", chemo_has_6)

# Check 7: Radiation sources list has 3 entries (no TR)
rad_has_3 <- grepl(
  'sources = list\\(PX = px_dates, DX = dx_dates, DRG = drg_dates\\)',
  r26_text
)
check("Radiation uses 3 sources (PX, DX, DRG)", rad_has_3)

# Check 8: SCT sources list has 2 entries (no TR)
sct_has_2 <- grepl(
  'sources = list\\(PX = px_dates, DRG = drg_dates\\)',
  r26_text
)
check("SCT uses 2 sources (PX, DRG)", sct_has_2)

# Check 9: Coverage analysis output exists (from 76-01)
coverage_csv <- file.path(CONFIG$output_dir, "source_coverage_analysis.csv")
check(
  glue("Coverage analysis output exists: {coverage_csv}"),
  file.exists(coverage_csv)
)

# Check 10: R/76 coverage script exists
check(
  "R/76_treatment_source_coverage.R exists",
  file.exists("R/76_treatment_source_coverage.R")
)

# ==============================================================================
# SECTION 13C: DRUG GROUPINGS VALIDATION ----
# ==============================================================================
# Phase 77 (TREAT-02): Validates DRUG_GROUPINGS centralization from xlsx.

message("\n[20/21] Drug groupings validation...")

# Check 1: DRUG_GROUPINGS exists and has sufficient entries
check(
  glue("DRUG_GROUPINGS has >= 200 entries (found {length(DRUG_GROUPINGS)})"),
  exists("DRUG_GROUPINGS") && length(DRUG_GROUPINGS) >= 200
)

# Check 2: All 5 core categories present
core_categories <- c("Chemotherapy", "Radiation", "SCT", "Immunotherapy", "Supportive Care")
found_categories <- intersect(core_categories, unique(DRUG_GROUPINGS))
check(
  glue("DRUG_GROUPINGS covers 5 core categories ({length(found_categories)}/5 found)"),
  length(found_categories) == 5
)

# Check 3: No NA keys (all codes are valid strings)
check(
  "DRUG_GROUPINGS has no NA keys",
  !any(is.na(names(DRUG_GROUPINGS)))
)

# Check 4: No NA values (all categories are valid strings)
check(
  "DRUG_GROUPINGS has no NA values",
  !any(is.na(DRUG_GROUPINGS))
)

# Check 5: Versioned xlsx snapshot exists
check(
  "data/reference/all_codes_resolved_next_tables_v2.1.xlsx exists",
  file.exists("data/reference/all_codes_resolved_next_tables_v2.1.xlsx")
)

# ==============================================================================
# SECTION 14: SUMMARY ----
# ==============================================================================

message(glue("\n{strrep('=', 70)}"))
total <- passed + failed
if (failed == 0) {
  message(glue("ALL {total} CHECKS PASSED"))
} else {
  message(glue("FAILED: {failed}/{total} checks failed"))
}
message(strrep("=", 70))

message("\nValidated requirements:")
message("  * REORG-01: Script renumbering across all decades")
message("  * REORG-02: Source() reference resolution")
message("  * REORG-03: Utils auto-sourcing from R/utils/")
message("  * REORG-04: Archive structure")
message("  * REORG-05: No broken cross-references")
message("  * SAFE-06: Comprehensive smoke test suite")
message("  * DRY-01: No duplicate PREFIX_MAP/TIER_MAPPING/classify_codes")
message("  * SAFE-01: assert_rds_exists() infrastructure")
message("  * SAFE-02: assert_df_valid() infrastructure")
message("  * SAFE-03: Error messages with context (glue)")
message("  * CANCER-01: NLPHL mutual exclusivity (classify_codes)")
message("  * DEATH-01/02: DEATH_CAUSE_MAP structure and coverage")
message("  * TREAT-01: Tumor registry source removed from treatment pipeline")
message("  * TREAT-01: Coverage analysis output validates removal impact")
message("  * TREAT-02: DRUG_GROUPINGS centralization from xlsx")

if (failed > 0) {
  quit(status = 1)
}
