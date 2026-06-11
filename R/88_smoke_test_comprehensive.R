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

# Clear stale log handler from previous source() in same session
try(close(.log_con), silent = TRUE)
globalCallingHandlers(NULL)

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
message("SMOKE TEST: Comprehensive Pipeline Validation (v2.2 + Phase 87-89)")
message(strrep("=", 70))

# ==============================================================================
# SECTION 2: UTILS MODULE COMPLETENESS ----
# ==============================================================================

message("\n[1/29] Utils module completeness...")

check("R/utils/ directory exists", dir.exists("R/utils"))

expected_utils <- c(
  "utils_assertions.R", "utils_attrition.R", "utils_cancer.R",
  "utils_dates.R", "utils_duckdb.R", "utils_icd.R",
  "utils_payer.R", "utils_pptx.R", "utils_snapshot.R",
  "utils_treatment.R", "utils_xlsx_lookups.R"
)

utils_files <- list.files("R/utils", pattern = "\\.R$")
check(
  glue("R/utils/ contains 11 files (found {length(utils_files)})"),
  length(utils_files) == 11
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

message("\n[2/29] Config loading and auto-sourcing...")

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

message("\n[3/29] Foundation script chain...")

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
message("\n[4/29] Cohort decade (10-14)...")

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
message("\n[5/29] Treatment decade (20-29)...")

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
# Quality/Investigations decade (30-39)
# --------------------------------------------------------------------------
message("\n[6/29] Quality/Investigations decade (30-39)...")

quality_expected <- c("35_death_cause_quality.R")
quality_found <- 0L
for (s in quality_expected) {
  if (file.exists(file.path("R", s))) quality_found <- quality_found + 1L
}
check(
  glue("Quality/Investigations decade: 1/1 scripts (found {quality_found})"),
  quality_found == 1
)

# --------------------------------------------------------------------------
# Cancer decade (40-56)
# --------------------------------------------------------------------------
message("\n[7/29] Cancer decade (40-56)...")

cancer_expected <- c(
  "40_cancer_site_frequency.R", "41_extract_all_codes.R",
  "42_build_code_descriptions.R", "43_cancer_site_confirmation.R",
  "44_cancer_site_confirmation_7day.R", "45_cancer_summary.R",
  "46_cancer_summary_table.R", "47_cancer_summary_refined.R",
  "48_cancer_summary_post_hl.R", "49_cancer_summary_pre_post.R",
  "50_all_codes_resolved.R",
  "52_gantt_v2_export.R", "53_death_date_validation.R",
  "54_investigate_sct_0362.R", "55_verify_replaced_by_codes.R",
  "56_new_tables_from_groupings.R"
)
cancer_found <- 0L
for (s in cancer_expected) {
  if (file.exists(file.path("R", s))) cancer_found <- cancer_found + 1L
}
check(
  glue("Cancer decade: 17/17 scripts (found {cancer_found})"),
  cancer_found == 17
)

# --------------------------------------------------------------------------
# Payer/QA decade (60-69)
# --------------------------------------------------------------------------
message("\n[8/29] Payer/QA decade (60-69)...")

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
# Output decade (70-76)
# --------------------------------------------------------------------------
message("\n[9/29] Output decade (70-76)...")

output_scripts <- c(
  "70_visualize_waterfall.R", "71_visualize_sankey.R",
  "72_generate_pptx.R", "73_generate_phase19_20_pptx.R",
  "74_generate_documentation.R", "75_encounter_analysis.R",
  "76_treatment_source_coverage.R"
)
output_found <- 0L
for (s in output_scripts) {
  if (file.exists(file.path("R", s))) output_found <- output_found + 1L
}
check(
  glue("Output decade: 7/7 scripts (found {output_found})"),
  output_found == 7
)

# --------------------------------------------------------------------------
# Test decade (80-88)
# --------------------------------------------------------------------------
message("\n[10/29] Test decade (80-88)...")

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
message("\n[11/29] Ad-hoc decade (90-99)...")

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

message("\n[12/29] No stale files...")

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

message("\n[13/29] Source() reference validation...")

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

message("\n[14/29] Key dependency chains...")

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

message("\n[15/29] DRY consolidation validation...")

# Check no PREFIX_MAP definitions outside R/00_config.R
scripts_to_check_prefix <- c(
  "R/28_episode_classification.R",
  "R/40_cancer_site_frequency.R", "R/41_extract_all_codes.R",
  "R/43_cancer_site_confirmation.R", "R/44_cancer_site_confirmation_7day.R",
  "R/45_cancer_summary.R", "R/46_cancer_summary_table.R",
  "R/47_cancer_summary_refined.R", "R/48_cancer_summary_post_hl.R",
  "R/49_cancer_summary_pre_post.R",
  "R/52_gantt_v2_export.R"
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

message("\n[16/29] Defensive coding infrastructure...")

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

message("\n[17/29] Archive validation...")

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

message("\n[18/29] Cross-platform data availability...")

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

message("\n[19/29] NLPHL classification & death cause validation...")

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

message("\n[20/29] TR removal validation...")

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

message("\n[21/29] Drug groupings validation...")

# Check 1: DRUG_GROUPINGS exists and has sufficient entries
check(
  glue("DRUG_GROUPINGS has >= 200 entries (found {length(DRUG_GROUPINGS)})"),
  exists("DRUG_GROUPINGS") && length(DRUG_GROUPINGS) >= 200
)

# Check 2: CODE_SUBCATEGORY_MAP exists and has sufficient entries (Phase 81)
check(
  "CODE_SUBCATEGORY_MAP defined with >= 200 entries",
  exists("CODE_SUBCATEGORY_MAP") && length(CODE_SUBCATEGORY_MAP) >= 200
)

check(
  "CODE_SUBCATEGORY_MAP contains J9035 (Bevacizumab)",
  exists("CODE_SUBCATEGORY_MAP") && "J9035" %in% names(CODE_SUBCATEGORY_MAP)
)

# Check 2: All 6 core categories present
core_categories <- c("Chemotherapy", "Radiation", "Proton Therapy", "SCT", "Immunotherapy", "Supportive Care")
found_categories <- intersect(core_categories, unique(DRUG_GROUPINGS))
check(
  glue("DRUG_GROUPINGS covers 6 core categories ({length(found_categories)}/6 found)"),
  length(found_categories) == 6
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
# SECTION 13D: 7-DAY GAP EXTENSION & R/49 V2 VALIDATION ----
# ==============================================================================
# Phase 77 (CANCER-01, CANCER-02): Validates 7-day gap extension and R/49 dual output.

message("\n[22/29] 7-day gap extension & R/49 v2 validation...")

# Check 1: R/49 contains v2 output path definitions
r49_lines <- readLines("R/49_cancer_summary_pre_post.R")
r49_text <- paste(r49_lines, collapse = "\n")

check(
  "R/49 defines OUTPUT_TABLE_V2_XLSX path",
  any(grepl("OUTPUT_TABLE_V2_XLSX", r49_lines))
)

# Check 2: R/49 filters by two_or_more_unique_dates_gt_7
check(
  "R/49 filters cancer_summary_v2 by two_or_more_unique_dates_gt_7 == 1",
  any(grepl("two_or_more_unique_dates_gt_7 == 1", r49_lines, fixed = TRUE))
)

# Check 3: R/49 has checkmate population assertion for v2 range (widened for ICD-9 cohort expansion)
check(
  "R/49 has checkmate assert_int for v2 population (6300-7500)",
  grepl("assert_int.*6300.*7500", r49_text)
)

# Check 4: R/49 has NLPHL diagnostic split
check(
  "R/49 has NLPHL vs Classical HL diagnostic output",
  any(grepl("NLPHL.*C81\\.0", r49_lines))
)

# Check 5: R/49 produces v2 RDS output
check(
  "R/49 saves v2 RDS output (saveRDS with v2)",
  any(grepl("saveRDS.*OUTPUT_RDS_V2", r49_lines))
)

# Check 6: R/49 category NA logic uses NLPHL-aware category names
check(
  "R/49 category NA logic includes 'Hodgkin Lymphoma (non-NLPHL)' (not just 'Hodgkin Lymphoma')",
  any(grepl("Hodgkin Lymphoma \\(non-NLPHL\\)", r49_lines))
)

# Check 7: V2 comparison table is console-only (no file write for comparison per D-03)
v2_comparison_write <- sum(grepl("write.*comparison", r49_lines, ignore.case = TRUE))
check(
  glue("V1 vs V2 comparison table is console-only (no file writes found: {v2_comparison_write})"),
  v2_comparison_write == 0
)

# ==============================================================================
# SECTION 13E: SCT 0362 INVESTIGATION (CODE-02) ----
# ==============================================================================
# Phase 79 (CODE-02): Validates R/54 SCT code 0362 investigation script.

message("\n[23/29] Phase 79: SCT 0362 investigation (CODE-02)...")

check("R/54_investigate_sct_0362.R exists", file.exists("R/54_investigate_sct_0362.R"))

if (file.exists("R/54_investigate_sct_0362.R")) {
  r54_lines <- readLines("R/54_investigate_sct_0362.R", warn = FALSE)

  check("R/54 sources R/00_config.R",
        any(grepl('source\\("R/00_config.R"\\)', r54_lines)))

  check("R/54 sources R/utils/utils_duckdb.R",
        any(grepl('source\\("R/utils/utils_duckdb.R"\\)', r54_lines)))

  check("R/54 references TREATMENT_CODES for SCT code lookup",
        any(grepl("TREATMENT_CODES", r54_lines)))

  check("R/54 outputs sct_0362_investigation.xlsx",
        any(grepl("sct_0362_investigation\\.xlsx", r54_lines)))

  check("R/54 uses openxlsx2 for multi-sheet workbook",
        any(grepl("library\\(openxlsx2\\)", r54_lines)))

  n_sections_r54 <- sum(grepl("^# --- SECTION.*----", r54_lines))
  check(glue("R/54 has >= 6 section headers (found: {n_sections_r54})"),
        n_sections_r54 >= 6)

  check("R/54 has automated recommendation logic",
        any(grepl("recommendation.*case_when|case_when.*recommendation", r54_lines)))
}

# ==============================================================================
# SECTION 13F: REPLACED-BY CODE VERIFICATION (CODE-01) ----
# ==============================================================================
# Phase 79 (CODE-01): Validates R/55 replaced-by code verification with igraph.

message("\n[24/29] Phase 79: Replaced-by code verification (CODE-01)...")

check("R/55_verify_replaced_by_codes.R exists", file.exists("R/55_verify_replaced_by_codes.R"))

if (file.exists("R/55_verify_replaced_by_codes.R")) {
  r55_lines <- readLines("R/55_verify_replaced_by_codes.R", warn = FALSE)

  check("R/55 sources R/00_config.R",
        any(grepl('source\\("R/00_config.R"\\)', r55_lines)))

  check("R/55 uses igraph for graph analysis",
        any(grepl("library\\(igraph\\)", r55_lines)))

  check("R/55 calls is_dag() for cycle detection",
        any(grepl("is_dag", r55_lines)))

  check("R/55 references DRUG_GROUPINGS for code verification",
        any(grepl("DRUG_GROUPINGS", r55_lines)))

  check("R/55 outputs replaced_by_verification.xlsx",
        any(grepl("replaced_by_verification\\.xlsx", r55_lines)))

  check("R/55 has 3-sheet workbook structure",
        any(grepl("Pairwise Verification", r55_lines)) &&
        any(grepl("Chain Analysis", r55_lines)) &&
        any(grepl("Summary Statistics", r55_lines)))

  n_sections_r55 <- sum(grepl("^# --- SECTION.*----", r55_lines))
  check(glue("R/55 has >= 6 section headers (found: {n_sections_r55})"),
        n_sections_r55 >= 6)
}

# ==============================================================================
# SECTION 13G: DRUG GROUPING SUMMARY TABLES (TREAT-03) ----
# ==============================================================================
# Phase 79 (TREAT-03): Validates R/56 drug grouping summary tables.

message("\n[25/29] Phase 79: Drug grouping summary tables (TREAT-03)...")

check("R/56_new_tables_from_groupings.R exists", file.exists("R/56_new_tables_from_groupings.R"))

if (file.exists("R/56_new_tables_from_groupings.R")) {
  r56_lines <- readLines("R/56_new_tables_from_groupings.R", warn = FALSE)

  check("R/56 sources R/00_config.R",
        any(grepl('source\\("R/00_config.R"\\)', r56_lines)))

  check("R/56 sources R/utils/utils_assertions.R",
        any(grepl('source\\("R/utils/utils_assertions.R"\\)', r56_lines)))

  check("R/56 references DRUG_GROUPINGS for treatment groupings",
        any(grepl("DRUG_GROUPINGS", r56_lines)))

  check("R/56 reads treatment_episodes.rds input",
        any(grepl("treatment_episodes\\.rds", r56_lines)))

  check("R/56 outputs episode_level_drug_grouping_tables.xlsx (new) and drug_grouping_tables.xlsx (compat)",
        any(grepl("episode_level_drug_grouping_tables\\.xlsx", r56_lines)) &&
        any(grepl("drug_grouping_tables\\.xlsx", r56_lines)))

  check("R/56 has grain-prefixed sheets (Ep: Sub-Category Summary + Ep: Encounter Treatment)",
        any(grepl("Ep: Sub-Category Summary", r56_lines)) &&
        any(grepl("Ep: Encounter Treatment", r56_lines)))

  n_sections_r56 <- sum(grepl("^# SECTION.*----", r56_lines))
  check(glue("R/56 has >= 6 section headers (found: {n_sections_r56})"),
        n_sections_r56 >= 6)

  # Phase 81 additions
  check("R/56 references CODE_SUBCATEGORY_MAP for Tier 2 sub-category resolution",
        any(grepl("CODE_SUBCATEGORY_MAP", r56_lines)))

  check("R/56 filters NA cancer_codes instead of replacing with Unknown",
        any(grepl("filter\\(!is\\.na\\(cancer_codes\\)\\)", r56_lines)) &&
        !any(grepl('if_else\\(is\\.na\\(cancer_codes\\).*Unknown', r56_lines)))

  check("R/56 derives category from DRUG_GROUPINGS with treatment_type fallback",
        any(grepl("DRUG_GROUPINGS", r56_lines)))

  check("R/56 Table 1 selects category, sub_category, treatment_code, code_type, cancer_codes",
        any(grepl("select\\(category.*sub_category.*treatment_code.*code_type.*cancer_codes", r56_lines)))

  check("R/56 has 3-tier sub-category lookup (xlsx, CODE_SUBCATEGORY_MAP, fallback)",
        any(grepl("Tier 1", r56_lines)) &&
        any(grepl("Tier 2", r56_lines)) &&
        any(grepl("Tier 3", r56_lines)))
}

# ==============================================================================
# SECTION 13H: ENCOUNTER DX DEDUPLICATION (Phase 82) ----
# ==============================================================================

message("\n[26/29] Phase 82: Encounter Dx deduplication in R/56...")

# Check 1: R/57 exploration script exists
check(
  "R/57_explore_dx_deduplication.R exists",
  file.exists("R/57_explore_dx_deduplication.R")
)

# Check 2-9: R/56 Phase 82 integration checks (only if R/56 exists, which it does from Section 13G)
check(
  "R/56 has Section 5B header for encounter-level deduplication",
  any(grepl("SECTION 5B.*ENCOUNTER.*DEDUPLICATION", r56_lines, ignore.case = TRUE))
)

check(
  "R/56 uses str_detect pattern matching for Encounter Dx (not hardcoded list, per D-10)",
  any(grepl('str_detect\\(sub_category.*Encounter Dx', r56_lines))
)

check(
  "R/56 has is_non_informative flag variable",
  any(grepl("is_non_informative", r56_lines))
)

check(
  "R/56 joins episode_codes to episode_encounters for encounter-level analysis",
  any(grepl("inner_join", r56_lines)) && any(grepl("episode_encounters", r56_lines))
)

check(
  "R/56 checks per-encounter helpful code co-occurrence (group_by ENCOUNTERID)",
  any(grepl("group_by\\(ENCOUNTERID\\)", r56_lines))
)

check(
  "R/56 uses dx_only internally for dedup logic (per D-05: preserve orphan encounters)",
  any(grepl("dx_only", r56_lines))
)

check(
  "R/56 Table 1 uses episode_codes_dedup (deduplicated source)",
  any(grepl("episode_codes_dedup", r56_lines))
)

# R/57 checks (if file exists)
if (file.exists("R/57_explore_dx_deduplication.R")) {
  r57_lines <- readLines("R/57_explore_dx_deduplication.R", warn = FALSE)

  check("R/57 sources R/00_config.R",
        any(grepl('source\\("R/00_config.R"\\)', r57_lines)))

  check("R/57 uses str_detect for Encounter Dx pattern matching",
        any(grepl('str_detect.*Encounter Dx', r57_lines)))

  check("R/57 has diagnostic output comparing before/after Table 1",
        any(grepl("table1_before", r57_lines)) &&
        any(grepl("table1_after", r57_lines)))
}

# ==============================================================================
# SECTION 14: DEATH QUALITY PROFILING VALIDATION (DEATH-01) ----
# ==============================================================================

message("\n[27/29] Death quality profiling validation (DEATH-01)...")

# Check 1: R/35_death_cause_quality.R exists
check(
  "R/35_death_cause_quality.R exists",
  file.exists("R/35_death_cause_quality.R")
)

# Check 2-7: R/35 detailed checks (only if file exists)
if (file.exists("R/35_death_cause_quality.R")) {
  r35_lines <- readLines("R/35_death_cause_quality.R", warn = FALSE)

  check(
    "R/35 sources R/00_config.R",
    any(grepl('source\\("R/00_config.R"\\)', r35_lines))
  )

  # Check 3: R/35 references DEATH_CAUSE_MAP
  check(
    "R/35 references DEATH_CAUSE_MAP for cause mapping",
    any(grepl("DEATH_CAUSE_MAP", r35_lines))
  )

  # Check 4: R/35 has DEATH_CAUSE field availability guard
  check(
    "R/35 has DEATH_CAUSE field availability check",
    any(grepl("death_cause_available|DEATH_CAUSE.*names", r35_lines))
  )

  # Check 5: R/35 outputs death_cause_quality.xlsx
  check(
    "R/35 outputs death_cause_quality.xlsx",
    any(grepl("death_cause_quality\\.xlsx", r35_lines))
  )

  # Check 6: R/35 saves quality decision artifact
  check(
    "R/35 saves death_cause_quality_result.rds",
    any(grepl("death_cause_quality_result\\.rds", r35_lines))
  )

  # Check 7: R/35 has proper section headers
  n_sections_r35 <- sum(grepl("^# SECTION.*----", r35_lines) | grepl("^# ---.*SECTION.*----", r35_lines))
  check(
    glue("R/35 has >= 6 section headers (found: {n_sections_r35})"),
    n_sections_r35 >= 6
  )
} else {
  message("  SKIP: R/35_death_cause_quality.R not found -- skipping detail checks")
}

# ==============================================================================
# SECTION 15: EPISODE ENRICHMENT AND GANTT INTEGRATION (CANCER-03, DEATH-02) ----
# ==============================================================================

message("\n[28/29] Episode enrichment and Gantt integration (CANCER-03, DEATH-02)...")

# Check 1: R/28 has triggering_code_description column in final select
r28_lines <- readLines("R/28_episode_classification.R", warn = FALSE)

check(
  "R/28 final select includes triggering_code_description",
  any(grepl("triggering_code_description", r28_lines))
)

# Check 2: R/28 has drug_group column in final select
check(
  "R/28 final select includes drug_group",
  any(grepl("drug_group", r28_lines))
)

# Check 3: R/28 references DRUG_GROUPINGS
check(
  "R/28 references DRUG_GROUPINGS for drug group mapping",
  any(grepl("DRUG_GROUPINGS", r28_lines))
)

# Check 4: R/28 references code_descriptions.rds
check(
  "R/28 references code_descriptions.rds for description lookup",
  any(grepl("code_descriptions\\.rds", r28_lines))
)

# Check 5: R/52 has cause_of_death in episodes export
r52_lines <- readLines("R/52_gantt_v2_export.R", warn = FALSE)

check(
  "R/52 episodes export includes cause_of_death",
  any(grepl("cause_of_death", r52_lines))
)

# Check 6: R/52 has drug_group in episodes export
check(
  "R/52 episodes export includes drug_group",
  any(grepl("drug_group", r52_lines))
)

# Check 7: R/52 has DEATH_CAUSE_MAP reference
check(
  "R/52 references DEATH_CAUSE_MAP for cause mapping",
  any(grepl("DEATH_CAUSE_MAP", r52_lines))
)

# Check 8: R/52 uses EPISODES_SCHEMA for dynamic verification (Phase 99, D-13)
check(
  "R/52 defines EPISODES_SCHEMA vector (Phase 99: dynamic schema verification)",
  any(grepl("EPISODES_SCHEMA\\s*<-\\s*c\\(", r52_lines))
)

# Check 9: R/52 uses DETAIL_SCHEMA for dynamic verification (Phase 99, D-13)
check(
  "R/52 defines DETAIL_SCHEMA vector (Phase 99: dynamic schema verification)",
  any(grepl("DETAIL_SCHEMA\\s*<-\\s*c\\(", r52_lines))
)

# Check 10: R/52 has missingness warning threshold
check(
  "R/52 has cause_of_death missingness warning (>40% threshold)",
  any(grepl("40", r52_lines) & grepl("missing|WARNING", r52_lines, ignore.case = TRUE))
)

# ==============================================================================
# SECTION 15b: ENVIRONMENT DETECTION (Phase 83: ENV-01 through ENV-06) ----
# ==============================================================================

message("\n[29/29] Environment detection validation...")

# ENV-01: IS_LOCAL flag defined and logical
check("IS_LOCAL flag is defined", exists("IS_LOCAL"))
check("IS_LOCAL is logical type", is.logical(IS_LOCAL))

# ENV-02: R_TESTING_ENV env var readable (does not crash)
check(
  "R_TESTING_ENV env var readable (empty string if unset)",
  is.character(Sys.getenv("R_TESTING_ENV"))
)

# ENV-06: THREAD_COUNT defined and valid
check("THREAD_COUNT is defined", exists("THREAD_COUNT"))
check("THREAD_COUNT is integer >= 1", is.integer(THREAD_COUNT) && THREAD_COUNT >= 1L)

# Conditional checks based on current environment mode
if (IS_LOCAL) {
  # ENV-03: Local mode path validation
  check(
    "Local mode: data_dir points to tests/fixtures",
    grepl("tests.*fixtures", CONFIG$data_dir, ignore.case = TRUE)
  )
  check(
    "Local mode: DuckDB path in tempdir()",
    grepl(normalizePath(tempdir(), winslash = "/", mustWork = FALSE),
          normalizePath(CONFIG$cache$duckdb_path, winslash = "/", mustWork = FALSE),
          fixed = TRUE)
  )
  check(
    "Local mode: cache_dir in tempdir()",
    grepl(normalizePath(tempdir(), winslash = "/", mustWork = FALSE),
          normalizePath(CONFIG$cache$cache_dir, winslash = "/", mustWork = FALSE),
          fixed = TRUE)
  )
  check(
    "Local mode: 1 thread configured",
    CONFIG$performance$num_threads == 1
  )
} else {
  # ENV-04: Production mode path validation (safe defaults)
  check(
    "Production mode: data_dir points to /orange/",
    grepl("^/orange/", CONFIG$data_dir)
  )
  check(
    "Production mode: DuckDB path in /blue/",
    grepl("^/blue/", CONFIG$cache$duckdb_path)
  )
  check(
    "Production mode: thread count >= 1",
    CONFIG$performance$num_threads >= 1
  )
}

# INFRA-01: Validate file.path() usage in PCORNET_PATHS (no hardcoded separators)
for (table_name in names(PCORNET_PATHS)) {
  path <- PCORNET_PATHS[[table_name]]
  # Paths should not contain double-separators (// or \\) which indicate paste0 misuse
  has_double_sep <- grepl("//", path) || grepl("\\\\\\\\", path)
  check(
    glue("PCORNET_PATHS${table_name}: no hardcoded double-separators"),
    !has_double_sep
  )
}

# INFRA-03: Required directories exist (created by SECTION 1b of 00_config.R)
check("output/ directory exists", dir.exists(CONFIG$output_dir))
check("output/figures/ directory exists", dir.exists(file.path(CONFIG$output_dir, "figures")))
check("output/tables/ directory exists", dir.exists(file.path(CONFIG$output_dir, "tables")))
check("cache directory exists", dir.exists(CONFIG$cache$cache_dir))
check("DuckDB directory exists", dir.exists(CONFIG$cache$duckdb_dir))

# INFRA-04: .Renviron.example exists
check(".Renviron.example template exists", file.exists(".Renviron.example"))

# ==============================================================================
# SECTION 15c: FALSE-POSITIVE SCT CODE REMOVAL (CLEAN-01, CLEAN-02) ----
# ==============================================================================

message("\n[CLEAN] False-positive SCT code removal validation (CLEAN-01, CLEAN-02)...")

# Read R/00_config.R and find DRUG_GROUPINGS section boundaries
config_lines <- readLines("R/00_config.R", warn = FALSE)
drug_groupings_start <- which(grepl("^DRUG_GROUPINGS <- c\\(", config_lines))
drug_groupings_end <- which(grepl("^\\)$", config_lines) &
                            seq_along(config_lines) > drug_groupings_start)[1]
drug_groupings_section <- config_lines[drug_groupings_start:drug_groupings_end]

# CLEAN-01: Each deprecated code is absent from DRUG_GROUPINGS
deprecated_codes <- c("Z94.84", "T86.5", "T86.09", "Z48.290",
                      "HEMATOLOGIC_TRANSPLANT_AND_ENDOC")

for (code in deprecated_codes) {
  check(
    glue("DRUG_GROUPINGS does not contain deprecated code {code}"),
    !any(grepl(paste0('"', code, '"'), drug_groupings_section, fixed = TRUE))
  )
}

# CLEAN-01: SCT section comment updated to reflect 36 codes
check(
  "SCT section comment updated to 36 codes (was 41)",
  any(grepl("# SCT \\(36 codes\\)", drug_groupings_section))
)

# CLEAN-02: Code descriptions still preserved (not accidentally removed from R/42)
check(
  "R/42 still has Z94.84 code description (not accidentally removed)",
  any(grepl("Z94\\.84", readLines("R/42_build_code_descriptions.R", warn = FALSE)))
)

# CLEAN-02: Cohort predicates still reference these codes (not accidentally removed from R/10)
r10_lines <- readLines("R/10_cohort_predicates.R", warn = FALSE)
check(
  "R/10 has_sct() still references Z94.84 for cohort inclusion",
  any(grepl("Z94\\.84", r10_lines))
)

# ==============================================================================
# SECTION 15d: XLSX METADATA ENRICHMENT VALIDATION (GANTT-01 through GANTT-05) ----
# ==============================================================================

message("\n[GANTT] Treatment metadata enrichment validation (GANTT-01 through GANTT-05)...")

# Check 1: utils_xlsx_lookups.R exists
check(
  "R/utils/utils_xlsx_lookups.R exists",
  file.exists("R/utils/utils_xlsx_lookups.R")
)

# Check 2: utils_xlsx_lookups.R exports load_xlsx_lookups function
if (file.exists("R/utils/utils_xlsx_lookups.R")) {
  xlsx_lookup_lines <- readLines("R/utils/utils_xlsx_lookups.R", warn = FALSE)
  check(
    "utils_xlsx_lookups.R contains load_xlsx_lookups function",
    any(grepl("load_xlsx_lookups <- function", xlsx_lookup_lines, fixed = TRUE))
  )

  # Check 3: utils_xlsx_lookups.R has deduplication validation
  check(
    "utils_xlsx_lookups.R validates no duplicate codes",
    any(grepl("duplicated|Duplicate codes", xlsx_lookup_lines))
  )

  # Check 3b: utils_xlsx_lookups.R builds from config (no openxlsx2 dependency)
  check(
    "utils_xlsx_lookups.R builds lookups from config (no XLSX dependency)",
    !any(grepl("openxlsx2|wb_load|wb_to_df", xlsx_lookup_lines))
  )
}

# Check 4: R/28 sources utils_xlsx_lookups.R
check(
  "R/28 sources utils_xlsx_lookups.R",
  any(grepl('source.*utils_xlsx_lookups', r28_lines))
)

# Check 5-9: R/28 select() includes all 5 new columns
new_cols <- c("medication_name", "code_type", "source_table", "treatment_line", "sct_cross_use_flag")
for (col in new_cols) {
  check(
    glue("R/28 select() includes {col}"),
    any(grepl(col, r28_lines, fixed = TRUE))
  )
}

# Check 10: R/28 comment references 22 columns (Phase 91)
check(
  "R/28 comment updated to 22 columns",
  any(grepl("22 columns", r28_lines))
)

# Check 11: R/28 has row count validation after enrichment
check(
  "R/28 validates row count preserved after enrichment",
  any(grepl("pre_enrichment_count", r28_lines))
)

# Check 12: R/28 stopifnot includes medication_name
check(
  "R/28 stopifnot includes medication_name",
  any(grepl('"medication_name"', r28_lines, fixed = TRUE))
)

# Check 13: aggregate_treatment_line implements F > S > E > N priority (per D-03)
check(
  "R/28 aggregate_treatment_line has F > S > E > N priority",
  any(grepl('if.*"F".*%in%.*labels.*return.*"F"', r28_lines)) ||
  any(grepl('"F" %in% labels', r28_lines, fixed = TRUE))
)

# Check 14: R/28 has TBD code export section (per D-07)
check(
  "R/28 has TBD code export section for SME review",
  any(grepl("unresolved_codes_for_review", r28_lines))
)

# ==============================================================================
# SECTION 15e: GANTT V2 SCHEMA EXTENSION VALIDATION (GANTT-06, GANTT-07) ----
# ==============================================================================

message("\n[GANTT] Gantt v2 schema extension validation (GANTT-06, GANTT-07)...")

r52_lines <- readLines("R/52_gantt_v2_export.R", warn = FALSE)

# GANTT-06: Check 1-5: R/52 select() includes all 5 new Phase 92 columns
phase92_cols <- c("medication_name", "code_type", "source_table", "treatment_line", "sct_cross_use_flag")
for (col in phase92_cols) {
  check(
    glue("R/52 select() includes {col} (GANTT-06)"),
    any(grepl(col, r52_lines, fixed = TRUE))
  )
}

# GANTT-06: Check 6: R/52 uses EPISODES_SCHEMA for verification (Phase 99)
check(
  "R/52 episodes schema verification uses EPISODES_SCHEMA (Phase 99)",
  any(grepl("identical.*colnames.*episodes_export.*EPISODES_SCHEMA", r52_lines))
)

# GANTT-06: Check 7: R/52 uses DETAIL_SCHEMA for verification (Phase 99)
check(
  "R/52 detail schema verification uses DETAIL_SCHEMA (Phase 99)",
  any(grepl("identical.*colnames.*detail_export.*DETAIL_SCHEMA", r52_lines))
)

# GANTT-06: Check 8: R/52 has guard clauses for Phase 91 columns
check(
  "R/52 has guard clause for medication_name",
  any(grepl('!"medication_name" %in% names', r52_lines, fixed = TRUE))
)

# GANTT-06: Check 9: Death pseudo-rows include new columns with NA
check(
  "R/52 death_episodes has medication_name = NA_character_",
  any(grepl("medication_name = NA_character_", r52_lines, fixed = TRUE))
)

# GANTT-06: Check 10: Multi-value cleanup applied to medication_name
check(
  "R/52 applies clean_multi_value to medication_name",
  any(grepl("medication_name = sapply.*clean_multi_value", r52_lines))
)

# GANTT-07: Check 11: R/51 v1 export deprecated (Phase 99, D-01)
check(
  "R/51 v1 export deleted (Phase 99: v2 is canonical)",
  !file.exists("R/51_gantt_data_export.R")
)

# ==============================================================================
# SECTION 15f: PHASE 93 CROSS-USE FLAG VALIDATION (IMMU-01, IMMU-02) ----
# ==============================================================================

message("\n[IMMU] Phase 93: Cross-use flag implementation validation (IMMU-01, IMMU-02)...")

r28_lines <- readLines("R/28_episode_classification.R", warn = FALSE)
r52_lines_93 <- readLines("R/52_gantt_v2_export.R", warn = FALSE)
config_lines_93 <- readLines("R/00_config.R", warn = FALSE)

# Check 1: QUESTIONABLE_IMMUNO_CODES exists in R/00_config.R (D-05)
check(
  "R/00_config.R defines QUESTIONABLE_IMMUNO_CODES (D-05)",
  any(grepl("QUESTIONABLE_IMMUNO_CODES", config_lines_93, fixed = TRUE))
)

# Check 2: QUESTIONABLE_IMMUNO_CODES has 11 entries (D-08)
check(
  "QUESTIONABLE_IMMUNO_CODES has 11 entries (8 vitamin + 3 CAR-T)",
  length(QUESTIONABLE_IMMUNO_CODES) == 11
)

# Check 3: R/28 includes immuno_confidence computation via data.table keyed join (Phase 98)
check(
  "R/28 computes immuno_confidence via data.table keyed join",
  any(grepl("immuno_codes_dt", r28_lines, fixed = TRUE)) &&
  any(grepl("immuno_agg", r28_lines, fixed = TRUE))
)

# Check 4: R/28 includes is_sct_conditioning_context computation
check(
  "R/28 computes is_sct_conditioning_context",
  any(grepl("is_sct_conditioning_context", r28_lines, fixed = TRUE))
)

# Check 5: R/28 includes immuno_confidence computation
check(
  "R/28 computes immuno_confidence",
  any(grepl("immuno_confidence", r28_lines, fixed = TRUE))
)

# Check 6: R/28 comment updated to 25 columns (Phase 93)
check(
  "R/28 comment updated to 25 columns (Phase 93)",
  any(grepl("25 columns", r28_lines))
)

# Check 7: is_sct_conditioning_context removed from R/52 Gantt export (Phase 99, D-11)
episodes_schema_start <- grep("EPISODES_SCHEMA\\s*<-", r52_lines_93)[1]
episodes_schema_end <- episodes_schema_start + 12
check(
  "R/52 does NOT include is_sct_conditioning_context in EPISODES_SCHEMA (Phase 99, D-11)",
  !any(grepl("is_sct_conditioning_context", r52_lines_93[episodes_schema_start:episodes_schema_end]))
)

# Check 8: immuno_confidence removed from R/52 Gantt export (Phase 99, D-11)
check(
  "R/52 does NOT include immuno_confidence in EPISODES_SCHEMA (Phase 99, D-11)",
  !any(grepl("immuno_confidence", r52_lines_93[episodes_schema_start:episodes_schema_end]))
)

# Check 9: R/52 includes is_hodgkin in EPISODES_SCHEMA (Phase 99, D-07)
check(
  "R/52 EPISODES_SCHEMA includes is_hodgkin (Phase 99, D-07)",
  any(grepl('"is_hodgkin"', r52_lines_93, fixed = TRUE))
)

# Check 10: R/52 derives is_hodgkin from cancer_category (Phase 99, D-07)
check(
  "R/52 derives is_hodgkin via str_detect(cancer_category, 'Hodgkin Lymphoma')",
  any(grepl("is_hodgkin.*str_detect.*cancer_category.*Hodgkin", r52_lines_93))
)

# Check 11: R/52 has defensive fallback for is_sct_conditioning_context
check(
  "R/52 has guard clause for is_sct_conditioning_context",
  any(grepl('!"is_sct_conditioning_context" %in% names', r52_lines_93, fixed = TRUE))
)

# Check 12: R/52 has defensive fallback for immuno_confidence
check(
  "R/52 has guard clause for immuno_confidence",
  any(grepl('!"immuno_confidence" %in% names', r52_lines_93, fixed = TRUE))
)

# Runtime validation (if treatment_episodes.rds exists)
if (file.exists(file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds"))) {
  episodes_93 <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds"))

  # Check 13: is_sct_conditioning_context only appears on Chemotherapy episodes (D-02, D-13)
  non_chemo_with_flag <- episodes_93 %>%
    filter(treatment_type != "Chemotherapy" & is_sct_conditioning_context == TRUE)
  check(
    "is_sct_conditioning_context flag only on Chemotherapy episodes (D-02)",
    nrow(non_chemo_with_flag) == 0
  )

  # Check 14: Non-chemotherapy episodes have NA for conditioning flag (D-04)
  non_chemo <- episodes_93 %>% filter(treatment_type != "Chemotherapy")
  check(
    "Non-chemotherapy episodes have NA for is_sct_conditioning_context (D-04)",
    all(is.na(non_chemo$is_sct_conditioning_context))
  )

  # Check 15: immuno_confidence has only expected values (D-10)
  valid_confidence_values <- c("questionable-vitamin", "questionable-CAR-T vs immunotherapy")
  check(
    "immuno_confidence contains only valid values (D-10)",
    all(episodes_93$immuno_confidence %in% valid_confidence_values | is.na(episodes_93$immuno_confidence))
  )

  # Check 16: Mutual exclusivity preserved -- each (patient_id, treatment_type, episode_number) triple is unique (D-13)
  # episode_number is scoped per patient per treatment_type in R/26 build_episodes()
  dup_episodes <- episodes_93 %>%
    count(patient_id, treatment_type, episode_number) %>%
    filter(n > 1)
  check(
    "Each episode has exactly one row (mutual exclusivity preserved, D-13)",
    nrow(dup_episodes) == 0
  )

  rm(episodes_93)
} else {
  message("  SKIP: treatment_episodes.rds not available -- runtime checks skipped")
}

# ==============================================================================
# SECTION 15g: PROTON THERAPY CATEGORY SPLIT VALIDATION (PROTON-05, PROTON-06) ----
# ==============================================================================

message("\n[PROTON] Proton therapy category split validation (Phase 94)...")

# Check 1: TREATMENT_TYPES has 5 elements
check(
  "TREATMENT_TYPES has 5 elements (was 4 before Phase 94)",
  length(TREATMENT_TYPES) == 5
)

# Check 2: "Proton Therapy" is in TREATMENT_TYPES
check(
  "TREATMENT_TYPES contains 'Proton Therapy'",
  "Proton Therapy" %in% TREATMENT_TYPES
)

# Check 3: 4 proton codes map to "Proton Therapy" via LOOKUP_TABLES_DT keyed join (Phase 98)
proton_codes <- c("77520", "77522", "77523", "77525")
drug_lookup <- get_lookup_dt("DRUG_GROUPINGS")
proton_dt <- data.table(code = proton_codes)
proton_dt[drug_lookup, on = .(code), drug_group := i.drug_group]
check(
  "All 4 proton codes (77520, 77522, 77523, 77525) map to 'Proton Therapy' via LOOKUP_TABLES_DT keyed join",
  all(!is.na(proton_dt$drug_group)) && all(proton_dt$drug_group == "Proton Therapy")
)

# Check 4: Proton codes are NOT in radiation_cpt (no double-counting)
check(
  "Proton codes (77520, 77522, 77523, 77525) are NOT in TREATMENT_CODES$radiation_cpt",
  !any(proton_codes %in% TREATMENT_CODES$radiation_cpt)
)

# Check 5: proton_cpt list exists in TREATMENT_CODES
check(
  "TREATMENT_CODES$proton_cpt exists with 4 codes",
  !is.null(TREATMENT_CODES$proton_cpt) && length(TREATMENT_CODES$proton_cpt) == 4
)

# Check 6: Proton Therapy has color in TREATMENT_TYPE_COLORS
check(
  "TREATMENT_TYPE_COLORS has 'Proton Therapy' entry",
  "Proton Therapy" %in% names(TREATMENT_TYPE_COLORS)
)

# Check 7: has_proton() function exists in R/10
r10_lines <- readLines("R/10_cohort_predicates.R", warn = FALSE)
check(
  "R/10 defines has_proton() function",
  any(grepl("has_proton <- function", r10_lines, fixed = TRUE))
)

# Check 8: R/14 calls has_proton() and joins HAD_PROTON
r14_lines <- readLines("R/14_build_cohort.R", warn = FALSE)
check(
  "R/14 calls has_proton()",
  any(grepl("has_proton()", r14_lines, fixed = TRUE))
)

check(
  "R/14 joins HAD_PROTON to cohort",
  any(grepl("HAD_PROTON", r14_lines))
)

# Check 9: R/26 has extract_proton_dates_with_codes() function
r26_lines <- readLines("R/26_treatment_episodes.R", warn = FALSE)
check(
  "R/26 defines extract_proton_dates_with_codes()",
  any(grepl("extract_proton_dates_with_codes <- function", r26_lines, fixed = TRUE))
)

# Check 10: R/25 has extract_proton_dates() function
r25_lines <- readLines("R/25_treatment_durations.R", warn = FALSE)
check(
  "R/25 defines extract_proton_dates()",
  any(grepl("extract_proton_dates <- function", r25_lines, fixed = TRUE))
)

# Check 11: R/20 has extract_proton_codes() function
r20_lines <- readLines("R/20_treatment_inventory.R", warn = FALSE)
check(
  "R/20 defines extract_proton_codes()",
  any(grepl("extract_proton_codes <- function", r20_lines, fixed = TRUE))
)

# Check 12: Radiation section updated to 11 codes
config_lines_dg <- config_lines[drug_groupings_start:drug_groupings_end]
check(
  "DRUG_GROUPINGS Radiation section updated to 11 codes (was 15)",
  any(grepl("# Radiation \\(11 codes\\)", config_lines_dg))
)

# ==============================================================================
# SECTION 30: PHASE 87 -- ICD-9 CANCER CODE INFRASTRUCTURE ----
# ==============================================================================
# Validates ICD9_CANCER_SITE_MAP, shared is_cancer_code(), and updated
# classify_codes() for ICD-9/ICD-10 harmonization (Phase 87).

message("\n[30/33] Phase 87: ICD-9 cancer code infrastructure...")

# Check 1: ICD9_CANCER_SITE_MAP exists with expected entries
if (exists("ICD9_CANCER_SITE_MAP") && length(ICD9_CANCER_SITE_MAP) >= 70) {
  message(glue("  PASS: ICD9_CANCER_SITE_MAP exists ({length(ICD9_CANCER_SITE_MAP)} entries)"))
  passed <- passed + 1L
} else {
  message("  FAIL: ICD9_CANCER_SITE_MAP missing or insufficient entries")
  failed <- failed + 1L
}

# Check 2: All assigned malignant ICD-9 prefixes (140-209, excluding unassigned gaps) present
# ICD-9-CM codes 166-169 and 177-178 were never assigned (reserved gaps in classification)
icd9_unassigned <- c("166", "167", "168", "169", "177", "178")
icd9_prefixes_expected <- setdiff(as.character(140:209), icd9_unassigned)
icd9_prefixes_present <- intersect(names(ICD9_CANCER_SITE_MAP), icd9_prefixes_expected)
if (length(icd9_prefixes_present) == length(icd9_prefixes_expected)) {
  message(glue("  PASS: All {length(icd9_prefixes_expected)} assigned malignant ICD-9 prefixes mapped (6 unassigned gaps excluded)"))
  passed <- passed + 1L
} else {
  missing_pfx <- setdiff(icd9_prefixes_expected, names(ICD9_CANCER_SITE_MAP))
  message(glue("  FAIL: Missing {length(missing_pfx)} ICD-9 prefixes: {paste(head(missing_pfx, 10), collapse=', ')}"))
  failed <- failed + 1L
}

# Check 3: No benign/uncertain ICD-9 codes (210-239) in map (per D-02)
benign_in_map <- intersect(names(ICD9_CANCER_SITE_MAP), as.character(210:239))
if (length(benign_in_map) == 0) {
  message("  PASS: No benign/uncertain ICD-9 codes (210-239) in ICD9_CANCER_SITE_MAP")
  passed <- passed + 1L
} else {
  message(glue("  FAIL: Benign codes found in map: {paste(benign_in_map, collapse=', ')}"))
  failed <- failed + 1L
}

# Check 4: ICD-9 HL subcategory discrimination (2014=NLPHL, 201=classical)
if (exists("ICD9_CANCER_SITE_MAP")) {
  nlphl_ok <- identical(unname(ICD9_CANCER_SITE_MAP["2014"]), "NLPHL")
  classical_ok <- identical(unname(ICD9_CANCER_SITE_MAP["201"]), "Hodgkin Lymphoma (non-NLPHL)")
  if (nlphl_ok && classical_ok) {
    message("  PASS: ICD-9 HL subcategory discrimination correct (2014=NLPHL, 201=classical)")
    passed <- passed + 1L
  } else {
    message(glue("  FAIL: ICD-9 HL mapping -- 2014={ICD9_CANCER_SITE_MAP['2014']}, 201={ICD9_CANCER_SITE_MAP['201']}"))
    failed <- failed + 1L
  }
}

# Check 5: Shared is_cancer_code() function available
utils_cancer_lines <- readLines("R/utils/utils_cancer.R")
if (any(grepl("is_cancer_code <- function", utils_cancer_lines))) {
  message("  PASS: is_cancer_code() defined in R/utils/utils_cancer.R")
  passed <- passed + 1L
} else {
  message("  FAIL: is_cancer_code() not found in R/utils/utils_cancer.R")
  failed <- failed + 1L
}

# Check 6: R/56 uses shared utility (no local is_cancer_code definition)
r56_lines <- readLines("R/56_new_tables_from_groupings.R")
if (!any(grepl("is_cancer_code <- function", r56_lines))) {
  message("  PASS: R/56 uses shared is_cancer_code() (no local definition)")
  passed <- passed + 1L
} else {
  message("  FAIL: R/56 still has local is_cancer_code() definition")
  failed <- failed + 1L
}

# Check 7: No DX_TYPE == "10" hard-filters in cancer summary pipeline (per D-01)
dx_type_scripts <- c("R/45_cancer_summary.R", "R/47_cancer_summary_refined.R",
                      "R/48_cancer_summary_post_hl.R", "R/49_cancer_summary_pre_post.R")
dx_type_violations <- character()
for (script in dx_type_scripts) {
  if (file.exists(script)) {
    script_lines <- readLines(script)
    if (any(grepl('filter.*DX_TYPE.*==.*"10"', script_lines))) {
      dx_type_violations <- c(dx_type_violations, script)
    }
  }
}
if (length(dx_type_violations) == 0) {
  message("  PASS: No DX_TYPE==\"10\" hard-filters in cancer summary pipeline")
  passed <- passed + 1L
} else {
  message(glue("  FAIL: DX_TYPE==\"10\" still in: {paste(dx_type_violations, collapse=', ')}"))
  failed <- failed + 1L
}

# Check 8: Category string consistency between ICD-9 and ICD-10 maps
icd9_categories <- unique(unname(ICD9_CANCER_SITE_MAP))
icd10_categories <- unique(unname(CANCER_SITE_MAP))
novel_icd9_categories <- setdiff(icd9_categories, icd10_categories)
if (length(novel_icd9_categories) == 0) {
  message(glue("  PASS: All {length(icd9_categories)} ICD-9 categories match ICD-10 category strings"))
  passed <- passed + 1L
} else {
  message(glue("  FAIL: ICD-9 categories not in ICD-10: {paste(novel_icd9_categories, collapse=', ')}"))
  failed <- failed + 1L
}

# ==============================================================================
# SECTION 31: PHASE 88 -- INSTANCE-LEVEL DRUG GROUPING TABLES ----
# ==============================================================================
# Validates R/57 drug grouping instance-level tables (Phase 88).

message("\n[31/33] Phase 88: Instance-level drug grouping tables...")

check("R/57_drug_grouping_instances.R exists", file.exists("R/57_drug_grouping_instances.R"))

if (file.exists("R/57_drug_grouping_instances.R")) {
  r57_lines <- readLines("R/57_drug_grouping_instances.R", warn = FALSE)

  check("R/57 sources R/00_config.R",
        any(grepl('source\\("R/00_config.R"\\)', r57_lines)))

  check("R/57 sources R/utils/utils_assertions.R",
        any(grepl('source\\("R/utils/utils_assertions.R"\\)', r57_lines)))

  check("R/57 sources R/utils/utils_duckdb.R",
        any(grepl('source\\("R/utils/utils_duckdb.R"\\)', r57_lines)))

  check("R/57 sources R/utils/utils_cancer.R",
        any(grepl('source\\("R/utils/utils_cancer.R"\\)', r57_lines)))

  check("R/57 reads treatment_episode_detail.rds input (encounter-level)",
        any(grepl("treatment_episode_detail\\.rds", r57_lines)))

  check("R/57 outputs encounter_level_drug_grouping_instances.xlsx (new) and drug_grouping_instances.xlsx (compat)",
        any(grepl("encounter_level_drug_grouping_instances\\.xlsx", r57_lines)) &&
        any(grepl("drug_grouping_instances\\.xlsx", r57_lines)))

  check("R/57 has grain-prefixed sheets (Enc: Sub-Category Detail + Enc: Treatment Detail)",
        any(grepl("Enc: Sub-Category Detail", r57_lines)) &&
        any(grepl("Enc: Treatment Detail", r57_lines)))

  check("R/57 defines map_cancer_codes_to_categories helper function",
        any(grepl("map_cancer_codes_to_categories", r57_lines)))

  check("R/57 uses both CANCER_SITE_MAP and ICD9_CANCER_SITE_MAP for code-to-category mapping",
        any(grepl("CANCER_SITE_MAP", r57_lines)) &&
        any(grepl("ICD9_CANCER_SITE_MAP", r57_lines)))

  check("R/57 sorts cancer categories descending (per D-04)",
        any(grepl("decreasing\\s*=\\s*TRUE", r57_lines)))

  check("R/57 uses 3-tier sub-category lookup (xlsx, CODE_SUBCATEGORY_MAP, fallback)",
        any(grepl("code_to_subcategory", r57_lines)) &&
        any(grepl("CODE_SUBCATEGORY_MAP", r57_lines)))

  n_sections_r57 <- sum(grepl("^# SECTION.*----", r57_lines))
  check(glue("R/57 has >= 7 section headers (found: {n_sections_r57})"),
        n_sections_r57 >= 7)

  check("R/57 does NOT aggregate with encounter_count (instance-level output)",
        !any(grepl("encounter_count", r57_lines)))

  check("R/57 uses is_cancer_code() from shared utility",
        any(grepl("is_cancer_code", r57_lines)) &&
        !any(grepl("is_cancer_code <- function", r57_lines)))

  # Validate Table 2 uses encounter-level grain (ENCOUNTERID column)
  check("R/57 Table 2 uses ENCOUNTERID for encounter-level grain",
        any(grepl("ENCOUNTERID", r57_lines)))
}

# ==============================================================================
# SECTION 32: DuckDB LOCAL INTEGRATION VALIDATION (TEST-01, TEST-02) ----
# ==============================================================================
# Validates that DuckDB ingest succeeds in current environment mode.
# Local mode: checks fixture-based DuckDB file in tempdir().
# Production mode: checks production DuckDB file on /blue/.

message("\n[32/33] DuckDB integration validation...")

if (file.exists(CONFIG$cache$duckdb_path)) {
  con <- tryCatch(
    DBI::dbConnect(duckdb::duckdb(), CONFIG$cache$duckdb_path, read_only = TRUE),
    error = function(e) NULL
  )

  if (!is.null(con)) {
    tables_found <- DBI::dbListTables(con)

    check(
      glue("DuckDB file accessible at CONFIG path ({basename(CONFIG$cache$duckdb_path)})"),
      TRUE
    )

    if (IS_LOCAL) {
      # TEST-01: Fixture-specific table count (15 tables from fixture CSVs)
      check(
        glue("DuckDB contains 15 tables from fixtures (found {length(tables_found)})"),
        length(tables_found) == 15
      )

      # Validate critical tables exist
      critical_tables <- c("ENROLLMENT", "DIAGNOSIS", "ENCOUNTER", "DEMOGRAPHIC",
                           "PROCEDURES", "PRESCRIBING", "DEATH")
      missing_critical <- setdiff(critical_tables, tables_found)
      check(
        glue("All 7 critical tables present (missing: {if (length(missing_critical) == 0) 'none' else paste(missing_critical, collapse=', ')})"),
        length(missing_critical) == 0
      )

      # TEST-05: Conditional fixture row count assertions
      enrollment_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM ENROLLMENT")$n
      check(
        glue("ENROLLMENT has 20 fixture patients (found {enrollment_count})"),
        enrollment_count == 20
      )

      diagnosis_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM DIAGNOSIS")$n
      check(
        glue("DIAGNOSIS has 18 fixture rows (found {diagnosis_count})"),
        diagnosis_count == 18
      )

      encounter_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM ENCOUNTER")$n
      check(
        glue("ENCOUNTER has 19 fixture rows (found {encounter_count})"),
        encounter_count == 19
      )

      prescribing_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM PRESCRIBING")$n
      check(
        glue("PRESCRIBING has 4 fixture rows (found {prescribing_count})"),
        prescribing_count == 4
      )

    } else {
      # Production: just check tables exist (counts are data-dependent)
      check(
        glue("DuckDB contains >= 13 tables (found {length(tables_found)})"),
        length(tables_found) >= 13
      )
    }

    DBI::dbDisconnect(con, shutdown = TRUE)
  } else {
    check("DuckDB file accessible (connection failed)", FALSE)
  }
} else {
  message("  SKIP: DuckDB file not found at CONFIG path (run R/01 + R/03 first)")
}

# ==============================================================================
# SECTION 33: FIXTURE SCHEMA & EDGE CASE VALIDATION (TEST-03, TEST-05) ----
# ==============================================================================
# Validates fixture-specific edge case data when running in local mode.
# Requires pcornet list from R/01_load_pcornet.R in global environment.
# Production mode: skipped entirely (fixture data not present).

if (IS_LOCAL) {
  message("\n[33/33] Fixture schema validation (local mode only)...")

  if (exists("pcornet", envir = .GlobalEnv) && is.list(pcornet) && length(pcornet) > 0) {

    # TEST-03: Fixture row counts match FIXTURE_DESIGN.md specifications
    check(
      glue("Fixture ENROLLMENT has 20 patients (found {nrow(pcornet$ENROLLMENT)})"),
      nrow(pcornet$ENROLLMENT) == 20
    )

    check(
      glue("Fixture DIAGNOSIS has 18 rows (found {nrow(pcornet$DIAGNOSIS)})"),
      nrow(pcornet$DIAGNOSIS) == 18
    )

    check(
      glue("Fixture DEMOGRAPHIC has 20 rows (found {nrow(pcornet$DEMOGRAPHIC)})"),
      nrow(pcornet$DEMOGRAPHIC) == 20
    )

    check(
      glue("Fixture ENCOUNTER has 19 rows (found {nrow(pcornet$ENCOUNTER)})"),
      nrow(pcornet$ENCOUNTER) == 19
    )

    check(
      glue("Fixture PRESCRIBING has 4 rows (found {nrow(pcornet$PRESCRIBING)})"),
      nrow(pcornet$PRESCRIBING) == 4
    )

    check(
      glue("Fixture PROCEDURES has 1 row (found {nrow(pcornet$PROCEDURES)})"),
      nrow(pcornet$PROCEDURES) == 1
    )

    check(
      glue("Fixture DEATH has 1 row (found {nrow(pcornet$DEATH)})"),
      nrow(pcornet$DEATH) == 1
    )

    # TEST-05: Edge case patient validation
    # Edge case 1: PT002 dual-eligible (payer code "14")
    pt002_dual <- pcornet$ENCOUNTER %>%
      dplyr::filter(ID == "PT002")
    check(
      "PT002 (dual-eligible) exists in ENCOUNTER",
      nrow(pt002_dual) > 0
    )

    # Edge case 2: PT003 NLPHL (C81.00)
    pt003_nlphl <- pcornet$DIAGNOSIS %>%
      dplyr::filter(ID == "PT003", DX == "C81.00")
    check(
      "PT003 has NLPHL diagnosis (C81.00)",
      nrow(pt003_nlphl) > 0
    )

    # Edge case 3: PT004 SCT (CPT 38241)
    pt004_sct <- pcornet$PROCEDURES %>%
      dplyr::filter(ID == "PT004", PX == "38241")
    check(
      "PT004 has SCT procedure (CPT 38241)",
      nrow(pt004_sct) > 0
    )

    # Edge case 4: PT007 orphan dx (Z51.11)
    pt007_orphan <- pcornet$DIAGNOSIS %>%
      dplyr::filter(ID == "PT007", DX == "Z51.11")
    check(
      "PT007 has orphan dx code (Z51.11)",
      nrow(pt007_orphan) > 0
    )

    # Edge case 5: PT009 sentinel date (1900-01-01)
    pt009_sentinel <- pcornet$ENROLLMENT %>%
      dplyr::filter(ID == "PT009")
    check(
      "PT009 exists in ENROLLMENT (1900 sentinel date patient)",
      nrow(pt009_sentinel) > 0
    )

    # Edge case 6: PT010 ICD-9/ICD-10 cross-system
    pt010_dx <- pcornet$DIAGNOSIS %>%
      dplyr::filter(ID == "PT010")
    check(
      glue("PT010 has 2 diagnoses for cross-system HL (found {nrow(pt010_dx)})"),
      nrow(pt010_dx) == 2
    )

    # Edge case 7: PT012 ABVD regimen (4 RXNORM_CUIs)
    pt012_abvd <- pcornet$PRESCRIBING %>%
      dplyr::filter(ID == "PT012")
    expected_cuis <- c("3639", "11213", "67228", "3946")
    found_cuis <- pt012_abvd$RXNORM_CUI
    check(
      glue("PT012 has 4 ABVD drugs (found {length(found_cuis)}: {paste(found_cuis, collapse=', ')})"),
      length(found_cuis) == 4 && all(expected_cuis %in% found_cuis)
    )

    # Edge case 8: PT006 death record
    pt006_death <- pcornet$DEATH %>%
      dplyr::filter(ID == "PT006")
    check(
      "PT006 has death record",
      nrow(pt006_death) == 1
    )

  } else {
    message("  SKIP: pcornet list not loaded (run R/01_load_pcornet.R first)")
    message("  To run full validation: source R/01 before R/88")
  }

} else {
  message("\n[33/33] Fixture schema validation -- SKIPPED (production mode)")
}

# ==============================================================================
# SECTION 16: SUMMARY ----
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
message("  * CANCER-01: NLPHL diagnostic split in R/49 console output")
message("  * CANCER-02: 7-day gap extension applied to all cancer categories in R/49 v2 output")
message("  * CANCER-03: Per-episode triggering_code_description and drug_group columns (R/28)")
message("  * DEATH-01: Death cause quality profiling (R/35)")
message("  * DEATH-02: Cause of death in Gantt v2 exports (R/52)")
message("  * DEATH-01/02: DEATH_CAUSE_MAP structure and coverage")
message("  * TREAT-01: Tumor registry source removed from treatment pipeline")
message("  * TREAT-01: Coverage analysis output validates removal impact")
message("  * TREAT-02: DRUG_GROUPINGS centralization from xlsx")
message("  * CODE-01: Replaced-by code verification (R/55)")
message("  * CODE-02: SCT 0362 investigation (R/54)")
message("  * TREAT-03: Drug grouping summary tables (R/56)")
message("  * P82-INTEGRATE: Encounter-level dx deduplication in R/56 Table 1")
message("  * P82-FLAG: dx_only used internally for dedup (not in Table 1 output)")
message("  * ENV-01: IS_LOCAL auto-detection via Sys.info()")
message("  * ENV-02: R_TESTING_ENV override readable")
message("  * ENV-03: Local mode paths (tests/fixtures, tempdir)")
message("  * ENV-04: Production mode safe defaults (/orange, /blue)")
message("  * ENV-05: Startup logging (validated by sourcing 00_config.R)")
message("  * ENV-06: THREAD_COUNT configuration")
message("  * INFRA-01: file.path() usage (no hardcoded separators)")
message("  * INFRA-03: Automatic directory creation")
message("  * INFRA-04: .Renviron.example template exists")
message("  * ICD-06: Shared is_cancer_code() utility in R/utils/utils_cancer.R")
message("  * ICD-07: R/56 uses shared utility (no local is_cancer_code)")
message("  * ICD-08: No DX_TYPE=='10' hard-filters in R/45, R/47, R/48, R/49")
message("  * ICD-09: ICD9_CANCER_SITE_MAP completeness (70 malignant prefixes)")
message("  * ICD-10: No benign/uncertain codes (210-239) in ICD9_CANCER_SITE_MAP")
message("  * ICD-11: ICD-9 HL subcategory discrimination (2014=NLPHL, 201=classical)")
message("  * ICD-12: Category string consistency across ICD-9/ICD-10 maps")
message("  * P88-D01/D02: Instance-level tables in separate xlsx (R/57)")
message("  * P88-D03: Sub-category names via 3-tier resolution")
message("  * P88-D04: Cancer site category names from CANCER_SITE_MAP + ICD9_CANCER_SITE_MAP")
message("  * P88-D05/D06: Per-episode rows with patient_id, dates, treatment_category")
message("  * P88-D07/D08: New encounter_level_drug_grouping_instances.xlsx with 2 sheets, per-encounter grain")
message("  * TEST-01: DuckDB ingest works with fixture CSVs (Section 32)")
message("  * TEST-02: R/88 smoke test passes locally against fixtures (Section 32)")
message("  * TEST-03: Fixture schema validation in local mode (Section 33)")
message("  * TEST-05: Conditional fixture count assertions (Sections 32+33)")
message("  * CLEAN-01: False-positive SCT codes removed from DRUG_GROUPINGS (Z94.84, T86.5, T86.09, Z48.290, HEMATOLOGIC_TRANSPLANT_AND_ENDOC)")
message("  * CLEAN-02: Smoke test validates deprecated codes absent and descriptions preserved")
message("  * GANTT-01: medication_name column in treatment_episodes.rds (Phase 91)")
message("  * GANTT-02: code_type column in treatment_episodes.rds (Phase 91)")
message("  * GANTT-03: source_table column in treatment_episodes.rds (Phase 91)")
message("  * GANTT-04: treatment_line column with F>S>E>N priority (Phase 91)")
message("  * GANTT-05: sct_cross_use_flag column in treatment_episodes.rds (Phase 91)")
message("  * GANTT-06: 5 metadata columns in gantt_detail.csv at per-date level (Phase 92)")
message("  * GANTT-07: v1 Gantt export (R/51) deprecated -- R/52 is canonical (Phase 99)")
message("  * D-07: is_hodgkin column added to Gantt export (Phase 99)")
message("  * D-11: is_sct_conditioning_context and immuno_confidence removed from Gantt export (Phase 99)")
message("  * D-13: Dynamic schema verification replaces hardcoded column counts (Phase 99)")
message("  * IMMU-01: immuno_confidence column flags questionable immunotherapy codes (Phase 93)")
message("  * IMMU-02: Distinct flag values for vitamin combos vs CAR-T ambiguity (Phase 93)")

if (failed > 0) {
  quit(status = 1)
}
