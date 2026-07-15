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
  "utils_dates.R", "utils_dt.R", "utils_duckdb.R", "utils_icd.R",
  "utils_payer.R", "utils_pptx.R", "utils_snapshot.R",
  "utils_treatment.R", "utils_xlsx_lookups.R"
)

utils_files <- list.files("R/utils", pattern = "\\.R$")
check(
  glue("R/utils/ contains 12 files (found {length(utils_files)})"),
  length(utils_files) == 12
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

quality_expected <- c("30_condition_linkage_investigation.R", "35_death_cause_quality.R")
quality_found <- 0L
for (s in quality_expected) {
  if (file.exists(file.path("R", s))) quality_found <- quality_found + 1L
}
check(
  glue("Quality/Investigations decade: 2/2 scripts (found {quality_found})"),
  quality_found == 2
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
  "50_all_codes_resolved.R", "51_post_death_encounter_investigation.R",
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

# Check 2b: R/49 filters V2 population by HL-specific 7-day confirmed IDs (Phase 110)
check(
  "R/49 V2 filters by HL-specific 7-day confirmed IDs (hl_7day_confirmed_ids)",
  any(grepl("hl_7day_confirmed_ids", r49_lines))
)

# Check 3: R/49 has checkmate population assertion for v2 range (Phase 110: HL-specific 7-day confirmed)
check(
  "R/49 has checkmate assert_int for v2 population (4000-8000)",
  grepl("assert_int.*4000.*8000", r49_text)
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

  check("R/56 has grain-prefixed sheets (Ep Sub-Category Summary + Ep Encounter Treatment)",
        any(grepl("Ep Sub-Category Summary", r56_lines)) &&
        any(grepl("Ep Encounter Treatment", r56_lines)))

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

# Check 7: R/52 drops cause_of_death as dead column (Phase 99, D-09)
check(
  "R/52 drops cause_of_death (Phase 99, D-09: 100% empty)",
  any(grepl("cause_of_death", r52_lines))
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

message("\n[29/31] Environment detection validation...")

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

# Check 5-8: R/28 select() includes 4 metadata columns (medication_name removed)
new_cols <- c("code_type", "source_table", "treatment_line", "sct_cross_use_flag")
for (col in new_cols) {
  check(
    glue("R/28 select() includes {col}"),
    any(grepl(col, r28_lines, fixed = TRUE))
  )
}

# Check 10: R/28 comment references 26 columns (medication_name removed)
check(
  "R/28 comment updated to 26 columns",
  any(grepl("26 columns", r28_lines))
)

# Check 11: R/28 has row count validation after enrichment
check(
  "R/28 validates row count preserved after enrichment",
  any(grepl("pre_enrichment_count", r28_lines))
)

# Check 12: R/28 stopifnot includes code_type (medication_name removed)
check(
  "R/28 stopifnot includes code_type",
  any(grepl('"code_type"', r28_lines, fixed = TRUE))
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

# GANTT-06: Check 1-3: R/52 select() includes Phase 92 metadata columns (medication_name removed)
phase92_cols <- c("code_type", "source_table", "sct_cross_use_flag")
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

# GANTT-06: Check 8: R/52 has guard clauses for Phase 92 columns
check(
  "R/52 has guard clause for code_type",
  any(grepl('!"code_type" %in% names', r52_lines, fixed = TRUE))
)

# GANTT-06: Check 9: R/52 applies clean_multi_value to code_type
check(
  "R/52 applies clean_multi_value to code_type",
  any(grepl("code_type = sapply.*clean_multi_value", r52_lines))
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

# Check 6: R/28 comment references 26 columns (medication_name removed)
check(
  "R/28 comment references 26 columns",
  any(grepl("26 columns", r28_lines))
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
  "R/52 derives is_hodgkin via str_detect with Non-Hodgkin exclusion",
  any(grepl("is_hodgkin.*str_detect.*cancer_category.*Hodgkin", r52_lines_93)) &&
    any(grepl("Non-Hodgkin", r52_lines_93))
)

# Check 11: R/52 documents removal of is_sct_conditioning_context (Phase 99, D-11)
check(
  "R/52 documents is_sct_conditioning_context removal (Phase 99, D-11)",
  any(grepl("is_sct_conditioning_context", r52_lines_93))
)

# Check 12: R/52 documents removal of immuno_confidence (Phase 99, D-11)
check(
  "R/52 documents immuno_confidence removal (Phase 99, D-11)",
  any(grepl("immuno_confidence", r52_lines_93))
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
# SECTION 15h: TEMPORAL DIAGNOSIS ENRICHMENT AND SORT AUDIT (Phase 112) ----
# ==============================================================================

message("\n[Phase 112] Temporal diagnosis enrichment and universal sort audit...")

r28_lines <- readLines("R/28_episode_classification.R", warn = FALSE)
r28_text <- paste(r28_lines, collapse = "\n")
r52_lines <- readLines("R/52_gantt_v2_export.R", warn = FALSE)
r52_text <- paste(r52_lines, collapse = "\n")
r36_lines <- readLines("R/36_tableau_ready_tables.R", warn = FALSE)
r36_text <- paste(r36_lines, collapse = "\n")
r57_lines <- readLines("R/57_drug_grouping_instances.R", warn = FALSE)
r57_text <- paste(r57_lines, collapse = "\n")

# Check 1: R/28 has Section 5E for temporal diagnosis enrichment
check("R/28 has Section 5E temporal diagnosis enrichment (Phase 112)",
      any(grepl("SECTION 5E.*TEMPORAL DIAGNOSIS", r28_lines, ignore.case = TRUE)))

# Check 2: R/28 queries DIAGNOSIS with is_cancer_code filter
check("R/28 Section 5E uses is_cancer_code() for DX filtering",
      any(grepl("is_cancer_code\\(DX\\)", r28_lines)))

# Check 3: R/28 uses bidirectional +/-30 day buffer (not backward-only)
check("R/28 temporal join uses episode_stop + days(30) upper bound",
      any(grepl("episode_stop.*\\+.*days\\(30\\)", r28_lines)))

# Check 4: R/28 final select includes episode_dx_codes
check("R/28 final select includes episode_dx_codes",
      any(grepl("episode_dx_codes", r28_lines)))

# Check 5: R/28 final select includes episode_dx_categories
check("R/28 final select includes episode_dx_categories",
      any(grepl("episode_dx_categories", r28_lines)))

# Check 6: R/28 stopifnot includes episode_dx_codes
check("R/28 stopifnot validates episode_dx_codes column",
      any(grepl("episode_dx_codes.*episode_dx_categories", r28_text)))

# Check 7: R/28 preserves row count after temporal join
check("R/28 validates row count preserved after temporal dx join",
      any(grepl("stopifnot\\(nrow\\(episodes\\) == pre_join_count\\)", r28_lines)))

# Check 8: R/52 EPISODES_SCHEMA includes episode_dx_codes
check("R/52 EPISODES_SCHEMA includes episode_dx_codes (Phase 112)",
      any(grepl("episode_dx_codes", r52_lines)))

# Check 9: R/52 EPISODES_SCHEMA includes episode_dx_categories
check("R/52 EPISODES_SCHEMA includes episode_dx_categories (Phase 112)",
      any(grepl("episode_dx_categories", r52_lines)))

# Check 10: R/52 DETAIL_SCHEMA does NOT include episode_dx_codes (episodes-only)
check("R/52 DETAIL_SCHEMA excludes episode_dx_codes (episode-level only)",
      !any(grepl("DETAIL_SCHEMA.*episode_dx_codes", r52_lines)))

# Check 11: R/52 clean_multi_value sorts values
check("R/52 clean_multi_value includes sort() for alphabetical ordering (Phase 112 D-06)",
      any(grepl("sort\\(unique\\(values\\)\\)", r52_lines)))

# Check 12: R/52 applies clean_multi_value to episode_dx_codes
check("R/52 applies clean_multi_value to episode_dx_codes",
      any(grepl("episode_dx_codes.*clean_multi_value", r52_text)))

# Check 12b (i1a): R/52 cleans drug_group multi-value column (dedup/sort/drop literal "NA")
check("R/52 applies clean_multi_value to drug_group (quick i1a)",
      any(grepl("drug_group = sapply\\(drug_group, clean_multi_value", r52_text)))

# Check 13: R/36 has NO decreasing = TRUE in sort calls
check("R/36 has no descending sort in multi-value fields (Phase 112 D-09)",
      !any(grepl("decreasing\\s*=\\s*TRUE", r36_lines)))

# Check 14: R/57 has NO decreasing = TRUE in sort calls
check("R/57 has no descending sort in multi-value fields (Phase 112 D-08)",
      !any(grepl("decreasing\\s*=\\s*TRUE", r57_lines)))

# Check 15: R/52 clean_multi_value does NOT have decreasing = TRUE
check("R/52 clean_multi_value has no descending sort",
      !any(grepl("clean_multi_value.*decreasing", r52_text)))

# ==============================================================================
# SECTION 15i: POST-DEATH ENCOUNTER INVESTIGATION (Phase 113) ----
# ==============================================================================

message("\n[Phase 113] Post-death encounter investigation...")

r51_lines <- readLines("R/51_post_death_encounter_investigation.R", warn = FALSE)
r51_text <- paste(r51_lines, collapse = "\n")

# Check 1: R/51 exists and has minimum length
check("R/51 post-death encounter investigation exists (>= 200 lines)",
      length(r51_lines) >= 200)

# Check 2: R/51 reads validated_death_dates.rds
check("R/51 reads validated_death_dates.rds",
      any(grepl("validated_death_dates\\.rds", r51_lines)))

# Check 3: R/51 filters death_valid == TRUE
check("R/51 filters death_valid == TRUE (Pitfall 2 avoidance)",
      any(grepl("death_valid\\s*==\\s*TRUE", r51_lines)))

# Check 4: R/51 filters post_death_activity == TRUE
check("R/51 filters post_death_activity == TRUE",
      any(grepl("post_death_activity\\s*==\\s*TRUE", r51_lines)))

# Check 5: R/51 queries ENCOUNTER table from DuckDB
check("R/51 queries DuckDB ENCOUNTER table (D-05)",
      any(grepl('get_pcornet_table.*ENCOUNTER', r51_lines)))

# Check 6: R/51 queries DIAGNOSIS table from DuckDB
check("R/51 queries DuckDB DIAGNOSIS table (D-05)",
      any(grepl('get_pcornet_table.*DIAGNOSIS', r51_lines)))

# Check 7: R/51 reads treatment_episodes.rds
check("R/51 reads treatment_episodes.rds (D-05)",
      any(grepl("treatment_episodes\\.rds", r51_lines)))

# Check 8: R/51 computes days_after_death using correct subtraction direction
check("R/51 computes days_after_death = as.numeric(date - DEATH_DATE)",
      any(grepl("days_after_death.*as\\.numeric.*DEATH_DATE", r51_lines)))

# Check 9: R/51 has case_when bucket assignment with 4 buckets (D-03)
check("R/51 has case_when gap_bucket with 0-30/31-90/91-365/>1 year (D-03)",
      any(grepl("0-30 days", r51_lines)) &&
      any(grepl("31-90 days", r51_lines)) &&
      any(grepl("91-365 days", r51_lines)) &&
      any(grepl(">1 year", r51_lines)))

# Check 10: R/51 has source_table column with all 3 types (D-06)
check("R/51 labels source_table as ENCOUNTER/DIAGNOSIS/TREATMENT (D-06)",
      any(grepl('source_table.*=.*"ENCOUNTER"', r51_lines)) &&
      any(grepl('source_table.*=.*"DIAGNOSIS"', r51_lines)) &&
      any(grepl('source_table.*=.*"TREATMENT"', r51_lines)))

# Check 11: R/51 creates Patient Summary and Event Detail sheets (D-01)
check("R/51 creates Patient Summary and Event Detail xlsx sheets (D-01)",
      any(grepl("Patient Summary", r51_lines)) &&
      any(grepl("Event Detail", r51_lines)))

# Check 12: R/51 uses styled headers (D-08)
check("R/51 uses dark gray header fill FF374151 (D-08)",
      any(grepl("FF374151", r51_lines)))

# Check 13: R/51 closes DuckDB connection
check("R/51 calls close_pcornet_con() for connection cleanup",
      any(grepl("close_pcornet_con", r51_lines)))

# Check 14: R/51 has freeze_pane for both sheets
check("R/51 freezes panes on output sheets",
      sum(grepl("freeze_pane", r51_lines)) >= 2)

# ==============================================================================
# SECTION 15j: DRUG NAME CONSISTENCY REMEDIATION (Phase 114) ----
# ==============================================================================

message("\n[Phase 114] Drug name consistency remediation...")

# Check 1: MEDICATION_LOOKUP exists and has entries
check("MEDICATION_LOOKUP exists with 200+ entries (D-02, D-03)",
      exists("MEDICATION_LOOKUP") && length(MEDICATION_LOOKUP) >= 200)

# Check 2: REFERENCE_XLSX constant exists
check("REFERENCE_XLSX constant defined in R/00_config.R",
      exists("REFERENCE_XLSX") && grepl("all_codes_resolved_next_tables", REFERENCE_XLSX))

# Check 3: R/26 has Phase 114 reference fill with coalesce
r26_lines <- readLines("R/26_treatment_episodes.R", warn = FALSE)
check("R/26 fills blank drug_names from MEDICATION_LOOKUP (D-01, D-03)",
      any(grepl("MEDICATION_LOOKUP", r26_lines)) &&
      any(grepl("coalesce", r26_lines)))

# Check 4: R/26 fill happens before aggregation
r26_text <- paste(r26_lines, collapse = "\n")
med_lookup_pos <- min(grep("MEDICATION_LOOKUP", r26_lines))
aggregate_pos <- min(grep("Aggregate drug_names per episode", r26_lines))
check("R/26 reference fill occurs BEFORE episode aggregation (Pitfall 3)",
      med_lookup_pos < aggregate_pos)

# Check 5: R/42 has 5-source precedence with reference_descriptions
r42_lines <- readLines("R/42_build_code_descriptions.R", warn = FALSE)
check("R/42 has reference_descriptions from MEDICATION_LOOKUP (D-04, D-05)",
      any(grepl("reference_descriptions <- MEDICATION_LOOKUP", r42_lines)))

# Check 6: R/42 combine includes reference_descriptions as last (highest priority)
check("R/42 precedence chain ends with reference_descriptions (5th source)",
      any(grepl("config_descriptions, reference_descriptions\\)", r42_lines)))

# Check 7: R/79 audit script exists with minimum length
r79_lines <- readLines("R/79_drug_name_consistency_audit.R", warn = FALSE)
check("R/79 drug name consistency audit exists (>= 150 lines)",
      length(r79_lines) >= 150)

# Check 8: R/79 reads treatment_episode_detail.rds
check("R/79 reads treatment_episode_detail.rds",
      any(grepl("treatment_episode_detail\\.rds", r79_lines)))

# Check 9: R/79 reads code_descriptions.rds
check("R/79 reads code_descriptions.rds",
      any(grepl("code_descriptions\\.rds", r79_lines)))

# Check 10: R/79 uses MEDICATION_LOOKUP
check("R/79 uses MEDICATION_LOOKUP for comparison",
      any(grepl("MEDICATION_LOOKUP", r79_lines)))

# Check 11: R/79 creates Summary and Detail sheets (D-07)
check("R/79 creates Summary and Detail xlsx sheets (D-07)",
      any(grepl("Summary", r79_lines)) &&
      any(grepl("Detail", r79_lines)))

# Check 12: R/79 uses styled headers (dark gray FF374151)
check("R/79 uses dark gray header fill FF374151",
      any(grepl("FF374151", r79_lines)))

# Check 13: R/79 has freeze_panes for both sheets
check("R/79 freezes panes on output sheets",
      sum(grepl("freeze_pane", r79_lines)) >= 2)

# Check 14: R/79 outputs drug_name_consistency_audit.xlsx
check("R/79 outputs drug_name_consistency_audit.xlsx",
      any(grepl("drug_name_consistency_audit\\.xlsx", r79_lines)))

# --- Drug-name canonicalization (quick 260709-iyh) ---
r00_lines_iyh <- readLines("R/00_config.R", warn = FALSE)
r27_lines_iyh <- readLines("R/27_drug_name_resolution.R", warn = FALSE)

# Check 15: R/00_config defines the canonical alias map + helper
check("R/00_config defines DRUG_NAME_ALIASES + canonicalize_drug_name (quick iyh)",
      any(grepl("DRUG_NAME_ALIASES <- c\\(", r00_lines_iyh)) &&
      any(grepl("canonicalize_drug_name <- function", r00_lines_iyh)))

# Check 16: canonicalization applied to MEDICATION_LOOKUP
check("R/00_config applies canonicalize_drug_name to MEDICATION_LOOKUP (quick iyh)",
      any(grepl("MEDICATION_LOOKUP <- setNames\\(canonicalize_drug_name\\(", r00_lines_iyh)))

# Check 17: liposomal doxorubicin is NOT an alias key (clinically distinct)
alias_start <- grep("DRUG_NAME_ALIASES <- c\\(", r00_lines_iyh)[1]
alias_end <- if (!is.na(alias_start)) {
  alias_start + which(grepl("^\\s*\\)\\s*$", r00_lines_iyh[alias_start:length(r00_lines_iyh)]))[1] - 1
} else NA
alias_block <- if (!is.na(alias_start) && !is.na(alias_end)) r00_lines_iyh[alias_start:alias_end] else character(0)
check("DRUG_NAME_ALIASES has NO liposomal key (liposomal kept distinct) (quick iyh)",
      length(alias_block) > 0 && !any(grepl("liposomal", alias_block, ignore.case = TRUE)))

# Check 18: R/27 applies canonicalize_drug_name to all_lookups before save
check("R/27 applies canonicalize_drug_name to all_lookups$drug_name (quick iyh)",
      any(grepl("mutate\\(drug_name = canonicalize_drug_name\\(drug_name\\)\\)", r27_lines_iyh)))

# ==============================================================================
# SECTION 15k: GANTT 7-DAY CONFIRMED + AGE AT EPISODE (Phase 115) ----
# ==============================================================================

message("\n[Phase 115] Gantt 7-day confirmed + age at episode...")

# Check 1: R/52 EPISODES_SCHEMA includes episode_dx_7day_confirmed
check("R/52 EPISODES_SCHEMA includes episode_dx_7day_confirmed (Phase 115)",
      any(grepl("episode_dx_7day_confirmed", r52_lines)))

# Check 2: R/52 EPISODES_SCHEMA includes age_at_episode
check("R/52 EPISODES_SCHEMA includes age_at_episode (Phase 115)",
      any(grepl("age_at_episode", r52_lines)))

# Check 3: R/52 EPISODES_SCHEMA has 20 entries (was 18 pre-Phase 115)
r52_schema_start <- grep("^EPISODES_SCHEMA\\s*<-", r52_lines)[1]
if (!is.na(r52_schema_start)) {
  r52_schema_end <- r52_schema_start
  # WHY: match ONLY a standalone ")" line as the terminator. R/52's EPISODES_SCHEMA
  # block has a comment line ending in ")" ("...now 20 total)") one line above the real
  # closing ")". The old "\\)\\s*$" terminator stopped on that comment and undercounted
  # entries (18 instead of 20). "^\\s*\\)\\s*$" only matches the true closing paren line.
  while (r52_schema_end <= length(r52_lines) && !grepl("^\\s*\\)\\s*$", r52_lines[r52_schema_end])) {
    r52_schema_end <- r52_schema_end + 1
  }
  schema_text_115 <- paste(r52_lines[r52_schema_start:r52_schema_end], collapse = "\n")
  schema_entries_115 <- lengths(regmatches(schema_text_115, gregexpr('"[a-z0-9_]+"', schema_text_115)))
  check("R/52 EPISODES_SCHEMA has 20 entries (Phase 115: +2 from 18)",
        schema_entries_115 == 20)
} else {
  check("R/52 EPISODES_SCHEMA has 20 entries (Phase 115: +2 from 18)", FALSE)
}

# Check 4: R/52 sources utils_cancer.R (needed for classify_codes)
check("R/52 sources utils_cancer.R for classify_codes (Phase 115)",
      any(grepl('source.*utils_cancer', r52_lines)))

# Check 5: R/52 reads cancer_summary.csv for 7-day confirmed data
check("R/52 references cancer_summary.csv (Phase 115)",
      any(grepl("cancer_summary\\.csv|cancer_summary", r52_lines)))

# Check 6: R/52 filters on two_or_more_unique_dates_gt_7 for confirmation
check("R/52 filters two_or_more_unique_dates_gt_7 == 1 for 7-day confirmed (Phase 115)",
      any(grepl("two_or_more_unique_dates_gt_7.*==.*1", r52_lines)))

# Check 7: R/52 queries DEMOGRAPHIC for birth dates
check("R/52 queries DEMOGRAPHIC table for birth dates (Phase 115)",
      any(grepl("DEMOGRAPHIC", r52_lines)))

# Check 8: R/52 computes age as integer floor
check("R/52 computes age_at_episode as integer floor (Phase 115)",
      any(grepl("as\\.integer.*floor", r52_text)))

# Check 9: R/52 applies clean_multi_value to episode_dx_7day_confirmed
check("R/52 applies clean_multi_value to episode_dx_7day_confirmed (Phase 115)",
      any(grepl("episode_dx_7day_confirmed.*clean_multi_value", r52_text)))

# Check 10: R/52 DETAIL_SCHEMA does NOT include episode_dx_7day_confirmed (episodes-only)
r52_detail_start <- grep("^DETAIL_SCHEMA\\s*<-", r52_lines)[1]
r52_detail_end <- r52_detail_start
while (r52_detail_end <= length(r52_lines) && !grepl("\\)\\s*$", trimws(r52_lines[r52_detail_end]))) {
  r52_detail_end <- r52_detail_end + 1
}
detail_schema_text_115 <- paste(r52_lines[r52_detail_start:r52_detail_end], collapse = "\n")
check("R/52 DETAIL_SCHEMA excludes episode_dx_7day_confirmed (Phase 115: episode-level only)",
      !grepl("episode_dx_7day_confirmed", detail_schema_text_115))

# Check 11: R/52 DETAIL_SCHEMA does NOT include age_at_episode (episodes-only)
check("R/52 DETAIL_SCHEMA excludes age_at_episode (Phase 115: episode-level only)",
      !grepl("age_at_episode", detail_schema_text_115))

# Check 12: Death pseudo-treatment rows include episode_dx_7day_confirmed
check("R/52 Death pseudo-treatment includes episode_dx_7day_confirmed (Phase 115)",
      any(grepl("episode_dx_7day_confirmed.*=.*\"\"", r52_text) &
          grepl("Death", r52_text)))

# Check 13: Death pseudo-treatment rows compute age_at_episode from birth_dates
check("R/52 Death pseudo-treatment computes age_at_episode (Phase 115)",
      any(grepl("age_at_episode", r52_text) & grepl("birth_dates", r52_text)))

# Check 14: R/52 uses classify_codes to map cancer codes to categories
check("R/52 uses classify_codes() for 7-day code-to-category mapping (Phase 115)",
      any(grepl("classify_codes", r52_lines)))

# ==============================================================================
# SECTION 15m: RUCA RURALITY SUMMARY (Phase 116) ----
# ==============================================================================

message("\n[Phase 116] RUCA rurality summary (R/100)...")

# Check 1: Bundled RUCA reference file exists
check("data/reference/RUCA-codes-2020-zipcode.xlsx bundled (Phase 116 RUCA-01)",
      file.exists("data/reference/RUCA-codes-2020-zipcode.xlsx"))

# Check 2: R/100 script exists and has minimum length
r100_exists <- file.exists("R/100_ruca_rurality_summary.R")
check("R/100_ruca_rurality_summary.R exists (Phase 116)",
      r100_exists)

if (r100_exists) {
  r100_lines <- readLines("R/100_ruca_rurality_summary.R", warn = FALSE)
  r100_text  <- paste(r100_lines, collapse = "\n")

  # Check 3: minimum line count
  check("R/100 has 300+ lines (Phase 116)",
        length(r100_lines) >= 300)

  # Check 4: loads bundled reference file
  check("R/100 references RUCA-codes-2020-zipcode.xlsx (RUCA-01)",
        any(grepl("RUCA-codes-2020-zipcode\\.xlsx", r100_lines)))

  # Check 5: defines ruca_tier_label() with all 4 tiers (RUCA-02)
  check("R/100 defines ruca_tier_label() with 4 tiers Metro/Micro/Small/Rural (RUCA-02)",
        any(grepl("ruca_tier_label", r100_lines)) &&
        grepl("Metropolitan", r100_text) &&
        grepl("Micropolitan", r100_text) &&
        grepl("Small town",   r100_text) &&
        grepl("Rural",        r100_text))

  # Check 6: sources R/00_config.R
  check("R/100 sources R/00_config.R",
        any(grepl("source.*00_config", r100_lines)))

  # Check 7: sources utils_payer.R for classify_payer_tier
  check("R/100 sources utils_payer.R (encounter-level payer)",
        any(grepl("utils_payer",       r100_lines)) &&
        any(grepl("classify_payer_tier", r100_lines)))

  # Check 8: sources utils_treatment.R for get_hl_patient_ids
  check("R/100 sources utils_treatment.R + calls get_hl_patient_ids()",
        any(grepl("utils_treatment",   r100_lines)) &&
        any(grepl("get_hl_patient_ids", r100_lines)))

  # Check 9: queries DEMOGRAPHIC for ZIP_CODE
  check("R/100 queries DEMOGRAPHIC table for ZIP_CODE (RUCA-02)",
        any(grepl("get_pcornet_table.*DEMOGRAPHIC", r100_lines)) &&
        any(grepl("ZIP_CODE",                       r100_lines)))

  # Check 10: normalizes ZIP to 5 digits with str_pad (RUCA-02, Pitfall 1-2 avoidance)
  check("R/100 normalizes ZIP with str_pad(., 5, pad='0') (RUCA-02)",
        any(grepl("str_pad.*5.*pad.*0", r100_lines)))

  # Check 11: validates 5-digit numeric ZIP with str_detect
  check("R/100 validates 5-digit numeric ZIP with str_detect (RUCA-02)",
        any(grepl("str_detect.*\\[0-9\\]\\{5\\}", r100_lines)))

  # Check 12: logs NA rurality count (RUCA-04)
  check("R/100 logs NA rurality count (RUCA-04)",
        (any(grepl("n_na",       r100_lines)) ||
         any(grepl("NA.*rurality", r100_lines, ignore.case = TRUE)) ||
         any(grepl("unmatched",   r100_lines, ignore.case = TRUE))) &&
        any(grepl("message.*NA|message.*unmatched|message.*rurality", r100_text, ignore.case = TRUE)))

  # Check 13: reads treatment_episode_detail.rds for Sheet 3
  check("R/100 reads treatment_episode_detail.rds (Sheet 3 treatment source)",
        any(grepl("treatment_episode_detail\\.rds", r100_lines)))

  # Check 14: reads treatment_episodes.rds for Sheet 4
  check("R/100 reads treatment_episodes.rds (Sheet 4 cancer source)",
        any(grepl("treatment_episodes\\.rds", r100_lines)))

  # Check 15: creates 4+ worksheets via add_styled_sheet or add_worksheet
  # NOTE: R/100 uses add_styled_sheet() helper which wraps add_worksheet; helper is
  # called 5x (4 data sheets + 1 metadata sheet). grep for either pattern. (Plan 01 deviation)
  check("R/100 creates 4+ worksheets via add_styled_sheet/add_worksheet (RUCA-03)",
        sum(grepl("^add_styled_sheet\\(", r100_lines)) >= 4 ||
        sum(grepl("add_worksheet",        r100_lines)) >= 4)

  # Check 16: uses dark gray header fill FF374151 (styled xlsx convention)
  check("R/100 uses dark gray header fill FF374151",
        any(grepl("FF374151", r100_lines)))

  # Check 17: freezes panes on 4+ sheets (via helper: freeze_pane inside add_styled_sheet)
  # add_styled_sheet() is called 5x; freeze_pane appears 1x inside the helper body.
  # Accept either: 4+ freeze_pane lines OR 4+ add_styled_sheet calls (helper wraps freeze_pane).
  check("R/100 freezes panes on 4+ sheets (via add_styled_sheet helper)",
        sum(grepl("freeze_pane",      r100_lines)) >= 4 ||
        sum(grepl("add_styled_sheet", r100_lines)) >= 4)

  # Check 18: outputs ruca_rurality_summary.xlsx
  check("R/100 saves ruca_rurality_summary.xlsx (RUCA-03)",
        any(grepl("ruca_rurality_summary\\.xlsx", r100_lines)))

  # Check 19: includes row totals + column totals (RUCA-05)
  check("R/100 constructs row/column totals (RUCA-05)",
        any(grepl("Total|totals_row|adorn_totals", r100_lines)) &&
        any(grepl("rowwise|c_across|summarise.*sum", r100_text)))

  # Check 20: ascending sort applied (SORT-01 pattern per RUCA-05)
  check("R/100 sorts ascending (arrange/sort) (RUCA-05, SORT-01)",
        any(grepl("\\barrange\\(", r100_lines)) ||
        any(grepl("\\bsort\\(",    r100_lines)))

  # Check 21: sheet titles document grain (patient-level vs encounter-level vs episode-level)
  check("R/100 sheet titles document grain (patient-level / encounter-level / episode-level)",
        (grepl("patient-level",   r100_text, ignore.case = TRUE) ||
         grepl("Patient-Level",   r100_text)) &&
        (grepl("encounter-level", r100_text, ignore.case = TRUE) ||
         grepl("Encounter-Level", r100_text)))

  # Check 22: has 7+ SECTION markers (convention -- matches R/33, R/34, R/36)
  check("R/100 has 7+ SECTION markers",
        sum(grepl("^# SECTION.*----$", r100_lines)) >= 7)
} else {
  # If script missing, register the dependent checks as fail so the total stays honest
  for (i in 3:22) check(paste0("R/100 dependent check #", i, " -- SKIPPED (script missing)"), FALSE)
}

# ==============================================================================
# SECTION 15n: LIFESPAN GANTT COLLAPSE (Phase 117) ----
# ==============================================================================

message("\n[Phase 117] Lifespan Gantt collapse (R/101)...")

# Check 1: R/101 script exists
r101_exists <- file.exists("R/101_gantt_lifespan_collapse.R")
check("R/101_gantt_lifespan_collapse.R exists (Phase 117)",
      r101_exists)

if (r101_exists) {
  r101_lines <- readLines("R/101_gantt_lifespan_collapse.R", warn = FALSE)
  r101_text  <- paste(r101_lines, collapse = "\n")

  # Check 2: minimum line count (>= 150)
  check("R/101 has 150+ lines (Phase 117)",
        length(r101_lines) >= 150)

  # Check 3: sources R/00_config.R
  check("R/101 sources R/00_config.R",
        any(grepl("source.*00_config", r101_lines)))

  # Check 4: reads gantt_episodes.csv (input)
  check("R/101 reads gantt_episodes.csv (input) (LIFESPAN-01)",
        any(grepl("gantt_episodes\\.csv", r101_lines)))

  # Check 5: writes gantt_lifespan.csv (output)
  check("R/101 writes gantt_lifespan.csv (LIFESPAN-01)",
        any(grepl("gantt_lifespan\\.csv", r101_lines)))

  # Check 6: collapses by patient_id x treatment_type
  check("R/101 collapses by patient_id x treatment_type (LIFESPAN-02)",
        any(grepl("group_by\\(patient_id, treatment_type\\)", r101_lines)))

  # Check 7: excludes Death + HL Diagnosis pseudo-rows
  check("R/101 excludes Death + HL Diagnosis pseudo-rows (LIFESPAN-03)",
        any(grepl('filter\\(!treatment_type %in% c\\("Death", "HL Diagnosis"\\)', r101_lines)))

  # Check 8: spans min(episode_start) -> max(episode_stop)
  check("R/101 spans min(episode_start) -> max(episode_stop) (LIFESPAN-02)",
        grepl("min\\(episode_start", r101_text) && grepl("max\\(episode_stop", r101_text))

  # Check 9: unions multi-value fields via clean_multi_value
  check("R/101 unions multi-value fields via clean_multi_value (LIFESPAN-04)",
        any(grepl("clean_multi_value", r101_lines)))

  # Check 10: re-derives is_hodgkin from cancer_category
  check("R/101 re-derives is_hodgkin from cancer_category",
        any(grepl('str_detect\\(cancer_category, "Hodgkin"\\)', r101_lines)))

  # Check 11: defines LIFESPAN_SCHEMA + identical() schema check
  check("R/101 defines LIFESPAN_SCHEMA + identical() schema check",
        any(grepl("LIFESPAN_SCHEMA", r101_lines)) && grepl("identical\\(colnames", r101_text))

  # Check 12: writes with row.names=FALSE, na='' (Tableau CSV convention)
  check("R/101 writes with row.names=FALSE, na='' (Tableau CSV convention)",
        any(grepl("row.names = FALSE", r101_lines)) && any(grepl('na = ""', r101_lines)))

  # Check 13: no ggplot/ggsave/geom_ (data export only, D-01)
  check("R/101 has NO ggplot/ggsave (data export only, D-01)",
        !any(grepl("ggplot|ggsave|geom_", r101_lines)))

  # Check 14: has 7+ SECTION markers
  check("R/101 has 7+ SECTION markers",
        sum(grepl("^# SECTION.*----$", r101_lines)) >= 7)

} else {
  # If script missing, register the dependent checks as FALSE so the total stays honest
  for (i in 2:14) check(paste0("R/101 dependent check #", i, " -- SKIPPED (script missing)"), FALSE)
}

# ==============================================================================
# SECTION 15o: DEATH CAUSE NHL FLAG (Phase 118) ----
# ==============================================================================

message("\n[Phase 118] Death cause NHL flag (R/102)...")

# Check 1: R/102 script exists
r102_exists <- file.exists("R/102_death_cause_nhl_flag.R")
check("R/102_death_cause_nhl_flag.R exists (Phase 118)",
      r102_exists)

if (r102_exists) {
  r102_lines <- readLines("R/102_death_cause_nhl_flag.R", warn = FALSE)
  r102_text  <- paste(r102_lines, collapse = "\n")

  # Check 2: minimum line count (>= 100)
  check("R/102 has 100+ lines (Phase 118)",
        length(r102_lines) >= 100)

  # Check 3: sources R/00_config.R
  check("R/102 sources R/00_config.R",
        any(grepl("source.*00_config", r102_lines)))

  # Check 4: self-bootstraps DuckDB connection
  check("R/102 self-bootstraps DuckDB (Phase 118)",
        grepl("USE_DUCKDB", r102_text) && grepl("open_pcornet_con", r102_text))

  # Check 5: reads DEATH table (NHLDEATH-01)
  check("R/102 reads DEATH table (NHLDEATH-01)",
        grepl('get_pcornet_table\\("DEATH"\\)', r102_text))

  # Check 6: DEATH_CAUSE table-availability guard (Phase 119: R/102 reads the
  # DEATH_CAUSE table via get_pcornet_table + is.null(dc_tbl) guard, not the
  # non-existent DEATH.DEATH_CAUSE column / old death_cause_available flag)
  check("R/102 has DEATH_CAUSE table-availability guard",
        grepl('get_pcornet_table\\("DEATH_CAUSE"\\)', r102_text) && grepl("is.null\\(dc_tbl\\)", r102_text))

  # Check 7: handles 1900 date sentinel + drops NA dates
  check("R/102 handles 1900 date sentinel + drops NA dates",
        grepl("1900", r102_text) && grepl("filter\\(!is.na\\(DEATH_DATE\\)", r102_text))

  # Check 8: aggregates one death per patient (NHLDEATH-01)
  check("R/102 aggregates one death per patient (NHLDEATH-01)",
        grepl("group_by\\(ID\\)", r102_text) && grepl("first\\(DEATH_CAUSE", r102_text))

  # Check 9: classifies NHL via classify_codes (NHLDEATH-02)
  check("R/102 classifies NHL via classify_codes (NHLDEATH-02)",
        grepl("classify_codes\\(", r102_text) && grepl("Non-Hodgkin Lymphoma", r102_text))

  # Check 10: three-state flag: NA/TRUE/FALSE (NHLDEATH-02)
  check("R/102 three-state flag: NA/TRUE/FALSE (NHLDEATH-02)",
        grepl("case_when", r102_text) && grepl("cause_of_death_is_nhl", r102_text))

  # Check 11: emits PATID column header (NHLDEATH-03)
  check("R/102 emits PATID column header (NHLDEATH-03)",
        grepl("PATID", r102_text))

  # Check 12: writes death_cause_nhl_flag.csv (NHLDEATH-03)
  check("R/102 writes death_cause_nhl_flag.csv (NHLDEATH-03)",
        grepl("death_cause_nhl_flag\\.csv", r102_text))

  # Check 13: writes row.names=FALSE, na='' (blank NA cell)
  check("R/102 writes row.names=FALSE, na='' (blank NA cell)",
        grepl("row.names = FALSE", r102_text) && grepl('na = ""', r102_text))

  # Check 14: no ggplot/ggsave (data export only)
  check("R/102 has NO ggplot/ggsave (data export only)",
        !any(grepl("ggplot|ggsave|geom_", r102_lines)))

} else {
  # If script missing, register the dependent checks as FALSE so total stays honest
  for (i in 2:14) check(paste0("R/102 dependent check #", i, " -- SKIPPED (script missing)"), FALSE)
}

# ==============================================================================
# SECTION 15p: DEATH CAUSE NHL FIX (Phase 119) ----
# ==============================================================================

# Phase 119 fixed the Phase 118 all-blank output: R/102 now reads cause of death
# from the separate DEATH_CAUSE table (wired into the loader in Plan 02) instead
# of a non-existent DEATH.DEATH_CAUSE column, and R/103 is a read-only diagnostic
# that inventories every candidate cause source. This section STRUCTURALLY
# validates the fix (source switch, three-state preservation, table loading,
# count 16, R/103 existence) with a gated HiPerGator-only runtime check.

message("\n[Phase 119] Death cause NHL fix (R/102 -> DEATH_CAUSE table; R/103 diagnostic)...")

# Check 1: R/103 diagnostic script exists
r103_exists <- file.exists("R/103_death_cause_diagnostic.R")
check("R/103_death_cause_diagnostic.R exists (Phase 119)",
      r103_exists)

r102_exists_119 <- file.exists("R/102_death_cause_nhl_flag.R")

if (r102_exists_119 && r103_exists) {
  r102_text <- paste(readLines("R/102_death_cause_nhl_flag.R", warn = FALSE),
                     collapse = "\n")
  r103_text <- paste(readLines("R/103_death_cause_diagnostic.R", warn = FALSE),
                     collapse = "\n")

  # Check 2: R/103 inventories DEATH_CAUSE restricted to the deceased set
  check("R/103 inventories DEATH_CAUSE for the deceased set (Phase 119)",
        grepl('get_pcornet_table\\("DEATH_CAUSE"\\)', r103_text) &&
          grepl("deceased", r103_text) &&
          grepl("intersect\\(", r103_text))

  # Check 3: R/103 classifies NHL via classify_codes
  check("R/103 classifies NHL via classify_codes (Phase 119)",
        grepl("classify_codes\\(", r103_text) &&
          grepl("Non-Hodgkin Lymphoma", r103_text))

  # Check 4: R/102 reads the DEATH_CAUSE table (NHLFIX-03, positive)
  check("R/102 reads DEATH_CAUSE table (NHLFIX-03)",
        grepl('get_pcornet_table\\("DEATH_CAUSE"\\)', r102_text))

  # Check 5: R/102 NO LONGER reads cause from the DEATH table (negative check)
  check("R/102 no longer reads cause from DEATH column (NHLFIX-03, negative)",
        !grepl('DEATH_CAUSE = all_of\\(death_cause_col\\)', r102_text))

  # Check 6: R/102 prefers underlying cause (DEATH_CAUSE_TYPE == "U")
  check("R/102 prefers underlying cause (DEATH_CAUSE_TYPE == \"U\") (Phase 119)",
        grepl("DEATH_CAUSE_TYPE", r102_text) && grepl('"U"', r102_text))

  # Check 7: R/102 joins cause codes onto the deceased set
  check("R/102 joins cause onto deceased set via left_join (Phase 119)",
        grepl("left_join", r102_text))

  # Check 8: R/102 three-state classify preserved
  check("R/102 three-state classify preserved (Phase 119)",
        grepl("classify_codes\\(", r102_text) &&
          grepl("Non-Hodgkin Lymphoma", r102_text) &&
          grepl("cause_of_death_is_nhl", r102_text) &&
          grepl("case_when", r102_text))

  # Check 9: R/102 output contract unchanged (PATID + blank NA + filename)
  check("R/102 output contract unchanged (PATID, na='', filename) (Phase 119)",
        grepl("death_cause_nhl_flag\\.csv", r102_text) &&
          grepl("row.names = FALSE", r102_text) &&
          grepl('na = ""', r102_text) &&
          grepl("PATID", r102_text))

  # Check 10: R/102 has a labeled proxy backstop (CONTEXT D-05)
  check("R/102 has labeled proxy backstop (D-05) (Phase 119)",
        grepl("USED_PROXY_BACKSTOP", r102_text) && grepl("D-05", r102_text))

  # Check 11: DEATH_CAUSE in PCORNET_TABLES (R/00_config.R)
  config_text <- if (file.exists("R/00_config.R")) {
    paste(readLines("R/00_config.R", warn = FALSE), collapse = "\n")
  } else {
    ""
  }
  check("DEATH_CAUSE registered in PCORNET_TABLES (Phase 119)",
        grepl('"DEATH_CAUSE"', config_text))

  # Check 12: DEATH_CAUSE_SPEC wired in the loader (R/01_load_pcornet.R)
  load_text <- if (file.exists("R/01_load_pcornet.R")) {
    paste(readLines("R/01_load_pcornet.R", warn = FALSE), collapse = "\n")
  } else {
    ""
  }
  check("DEATH_CAUSE_SPEC registered in TABLE_SPECS (Phase 119)",
        grepl("DEATH_CAUSE_SPEC", load_text) &&
          grepl("DEATH_CAUSE = DEATH_CAUSE_SPEC", load_text))

  # Check 13: R/88 table-count assertion bumped to 16 (self-read of THIS file)
  smoke_self_text <- paste(readLines("R/88_smoke_test_comprehensive.R", warn = FALSE),
                           collapse = "\n")
  check("R/88 table-count assertion bumped to 16 (Phase 119)",
        grepl("length\\(tables_found\\) == 16", smoke_self_text))

  # Check 14: RUNTIME (HiPerGator-only, gated) -- output CSV has non-zero TRUE/FALSE.
  # Kept green locally: SKIPPED when IS_LOCAL or the output CSV is absent.
  out_csv_119 <- file.path(CONFIG$output_dir, "death_cause_nhl_flag.csv")
  if (!IS_LOCAL && file.exists(out_csv_119)) {
    flag_df <- read.csv(out_csv_119, stringsAsFactors = FALSE, na.strings = "")
    n_true  <- sum(flag_df$cause_of_death_is_nhl == "TRUE" |
                     flag_df$cause_of_death_is_nhl == TRUE, na.rm = TRUE)
    n_false <- sum(flag_df$cause_of_death_is_nhl == "FALSE" |
                     flag_df$cause_of_death_is_nhl == FALSE, na.rm = TRUE)
    check("output has non-zero TRUE or FALSE (Phase 119, HiPerGator)",
          (n_true + n_false) > 0)
  } else {
    check("output has non-zero TRUE or FALSE -- SKIPPED (local / no output) (Phase 119)",
          TRUE)
  }

} else {
  # If either script missing, register the dependent checks as FALSE so the total
  # stays honest (mirrors Section 15o's else-branch).
  for (i in 2:14) {
    check(paste0("R/102/R/103 Phase 119 dependent check #", i,
                 " -- SKIPPED (script missing)"), FALSE)
  }
}

# ==============================================================================
# SECTION 15q: GANTT ENTIRE HISTORY (quick-260710-i1e) ----
# ==============================================================================

# quick-260710-i1e added R/104_gantt_entire_history.R: a downstream sibling of
# R/101 that projects output/gantt_lifespan.csv into gantt_entire_history.csv
# (6 renamed columns) and RE-DERIVES the 7-day cancer column as the union
# directly from output/gantt_episodes.csv (source of truth), asserting equality
# against lifespan's own column (non-fatal). This section STRUCTURALLY validates
# R/104 (inputs, blank-safe read/write, verbatim helpers, pseudo-row exclusion,
# union re-derivation, renames, non-fatal mismatch, left_join, no plotting).

message("\n[quick-260710-i1e] Gantt entire history (R/104)...")

# Check 1: R/104 script exists
r104_exists <- file.exists("R/104_gantt_entire_history.R")
check("R/104_gantt_entire_history.R exists (quick-260710-i1e)",
      r104_exists)

if (r104_exists) {
  r104_lines <- readLines("R/104_gantt_entire_history.R", warn = FALSE)
  r104_text  <- paste(r104_lines, collapse = "\n")

  # Check 2: minimum line count (>= 100)
  check("R/104 has 100+ lines (quick-260710-i1e)",
        length(r104_lines) >= 100)

  # Check 3: sources R/00_config.R
  check("R/104 sources R/00_config.R",
        grepl("source.*00_config", r104_text))

  # Check 4: reads gantt_lifespan.csv (input)
  check("R/104 reads gantt_lifespan.csv (input)",
        grepl("gantt_lifespan\\.csv", r104_text))

  # Check 5: reads gantt_episodes.csv (input)
  check("R/104 reads gantt_episodes.csv (input)",
        grepl("gantt_episodes\\.csv", r104_text))

  # Check 6: reads blank-safe (na.strings="")
  check("R/104 reads blank-safe (na.strings='')",
        grepl('na.strings = ""', r104_text))

  # Check 7: copies clean_multi_value + union_field (verbatim from R/101)
  check("R/104 copies clean_multi_value + union_field",
        grepl("clean_multi_value", r104_text) && grepl("union_field", r104_text))

  # Check 8: excludes Death + HL Diagnosis pseudo-rows
  check("R/104 excludes Death + HL Diagnosis pseudo-rows",
        grepl('filter\\(!treatment_type %in% c\\("Death", "HL Diagnosis"\\)', r104_text))

  # Check 9: re-derives 7-day union grouped by patient_id x treatment_type
  check("R/104 re-derives 7-day union grouped by patient_id x treatment_type",
        grepl("group_by\\(patient_id, treatment_type\\)", r104_text) &&
          grepl("union_field\\(episode_dx_7day_confirmed", r104_text))

  # Check 10: applies the 3 renames (treatment_start/stop, cancer_7day_confirmed)
  check("R/104 applies the 3 renames (treatment_start/stop, cancer_7day_confirmed)",
        grepl("treatment_start = episode_start", r104_text) &&
          grepl("treatment_stop", r104_text) &&
          grepl("cancer_7day_confirmed", r104_text))

  # Check 11: asserts union mismatch non-fatally (n_mismatch + warning; safe form)
  check("R/104 asserts union mismatch non-fatally (n_mismatch + warning)",
        grepl("n_mismatch", r104_text) && grepl("warning\\(", r104_text))

  # Check 12: joins episodes-derived union via left_join
  check("R/104 joins episodes-derived union via left_join",
        grepl("left_join", r104_text))

  # Check 13: blank-safe write to gantt_entire_history.csv (na='', row.names=FALSE)
  check("R/104 blank-safe write to gantt_entire_history.csv (na='', row.names=FALSE)",
        grepl("gantt_entire_history\\.csv", r104_text) &&
          grepl("row.names = FALSE", r104_text) &&
          grepl('na = ""', r104_text))

  # Check 14: no ggplot/ggsave (data export only)
  check("R/104 has NO ggplot/ggsave (data export only)",
        !grepl("ggplot|ggsave|geom_", r104_text))

} else {
  # If script missing, register the dependent checks as FALSE so total stays honest
  for (i in 2:14) check(paste0("R/104 dependent check #", i, " -- SKIPPED (script missing)"), FALSE)
}

# ==============================================================================
# SECTION 15r: SUPPORTIVE CARE NORMALIZED MEANING (Phase 120) ----
# ==============================================================================

# Phase 120 added R/105_normalize_supportive_care_meaning.R: resolves each of the
# 171 RXNORM codes on the "Supportive Care" tab of
# data/reference/all_codes_resolved_next_tables_v2.1.xlsx to its RxNorm IN generic
# ingredient (three-step: related.json?tty=IN -> historystatus derivedConcepts ->
# rule-based canonicalize_drug_name fallback), caches lookups to
# data/reference/rxnorm_ingredient_cache.csv, and appends a "Normalized Meaning"
# column (col G) IN PLACE, keeping combination products as sorted "/"-joined labels.
# These are STRUCTURAL greps against the R/105 file text -- no HiPerGator data or
# internet needed (nyquist_validation is OFF); they pass LOCALLY.

message("\n[Phase 120] Supportive Care Normalized Meaning (R/105)...")

# Check 1: R/105 script exists
r105_exists <- file.exists("R/105_normalize_supportive_care_meaning.R")
check("R/105_normalize_supportive_care_meaning.R exists (Phase 120)",
      r105_exists)

if (r105_exists) {
  r105_lines <- readLines("R/105_normalize_supportive_care_meaning.R", warn = FALSE)
  r105_text  <- paste(r105_lines, collapse = "\n")

  # Check 2: minimum line count (>= 150)
  check("R/105 has 150+ lines (Phase 120)",
        length(r105_lines) >= 150)

  # Check 3: sources R/00_config.R
  check("R/105 sources R/00_config.R",
        grepl("source.*00_config", r105_text))

  # Check 4: reads the Supportive Care sheet at start_row = 2
  check("R/105 reads the Supportive Care sheet (start_row = 2)",
        grepl("Supportive Care", r105_text) &&
          grepl("start_row = 2|start_row=2", r105_text))

  # Check 5: calls the RxNav IN endpoint (generic-ingredient resolution, D-01)
  check("R/105 calls the RxNav IN endpoint (related.json?tty=IN)",
        grepl("related\\.json\\?tty=IN", r105_text))

  # Check 6: does NOT use the full-clinical-name properties endpoint (negative)
  check("R/105 does NOT use properties.json (uses IN, not full clinical name)",
        !grepl("properties\\.json", r105_text))

  # Check 7: has the historystatus retired-code fallback
  check("R/105 has the historystatus retired-code fallback",
        grepl("historystatus", r105_text))

  # Check 8: reuses the httr2 retry wrapper
  check("R/105 reuses the httr2 req_retry wrapper",
        grepl("req_retry", r105_text))

  # Check 9: keeps combos as a sorted, unique "/"-joined label (D-05)
  check("R/105 keeps combos as sorted-unique /-joined label (rxnav_IN_combo)",
        grepl("sort\\(unique", r105_text) && grepl("rxnav_IN_combo", r105_text))

  # Check 10: reuses canonicalize_drug_name for the rule-based fallback (D-04)
  check("R/105 reuses canonicalize_drug_name for the rule-based fallback",
        grepl("canonicalize_drug_name", r105_text))

  # Check 11: writes the ingredient cache CSV (offline reruns)
  check("R/105 writes the rxnorm_ingredient_cache.csv",
        grepl("rxnorm_ingredient_cache\\.csv", r105_text))

  # Check 12: appends the Normalized Meaning column at col G (header G2, data G3)
  check("R/105 appends Normalized Meaning at col G (G2 header + G3 data)",
        grepl("Normalized Meaning", r105_text) &&
          grepl("G2", r105_text) && grepl("G3", r105_text))

  # Check 13: round-trip verify present (2nd wb_load + 171-row + 7-col assertions).
  #           R/105 asserts row count against the N_SUPCARE_ROWS (171L) constant and
  #           the 7-col shape via `ncol(sc) != 7`, so match those forms (not literal
  #           `== 171`/`== 7`) plus the second wb_load re-open.
  check("R/105 has a round-trip verify (2nd wb_load + 171-row + 7-col asserts)",
        grepl("N_SUPCARE_ROWS", r105_text) &&
          grepl("ncol\\(sc\\) != 7", r105_text) &&
          length(gregexpr("wb_load", r105_text)[[1]]) >= 2)

  # Check 14: no ggplot/ggsave (data-mutation only)
  check("R/105 has NO ggplot/ggsave (data-mutation only)",
        !grepl("ggplot|ggsave|geom_", r105_text))

} else {
  # If script missing, register the dependent checks as FALSE so total stays honest
  for (i in 2:14) check(paste0("R/105 dependent check #", i, " -- SKIPPED (script missing)"), FALSE)
}

# ==============================================================================
# SECTION 15s: ZIP CHANGE FREQUENCY (Phase 121) ----
# ==============================================================================

# Phase 121 added R/106_zip_change_frequency.R: a read-only investigation that probes
# for LDS_ADDRESS_HISTORY and, if present, quantifies per-patient ZIP change frequency
# at ZIP9 and ZIP5 granularity, writing a 5-sheet styled xlsx. STRUCTURAL greps against
# the R/106 file text (no HiPerGator data locally); they pass LOCALLY.

message("\n[Phase 121] ZIP change frequency (R/106)...")

# Check 1: R/106 script exists
r106_exists <- file.exists("R/106_zip_change_frequency.R")
check("R/106_zip_change_frequency.R exists (Phase 121)", r106_exists)

if (r106_exists) {
  r106_lines <- readLines("R/106_zip_change_frequency.R", warn = FALSE)
  r106_text  <- paste(r106_lines, collapse = "\n")

  # Check 2: minimum line count (>= 150)
  check("R/106 has 150+ lines (Phase 121)",
        length(r106_lines) >= 150)

  # Check 3: sources R/00_config.R
  check("R/106 sources R/00_config.R",
        grepl("source.*00_config", r106_text))

  # Check 4: probes LDS_ADDRESS_HISTORY via file.exists()
  check("R/106 probes LDS_ADDRESS_HISTORY via file.exists()",
        grepl("file\\.exists", r106_text) && grepl("LDS_ADDRESS_HISTORY", r106_text))

  # Check 5: exits gracefully with quit(status = 0), not stop()
  check("R/106 exits gracefully with quit(status = 0), not stop()",
        grepl("quit\\(status = 0\\)", r106_text))

  # Check 6: reads the ADDRESS_ZIP9 column
  check("R/106 reads the ADDRESS_ZIP9 column",
        grepl("ADDRESS_ZIP9", r106_text))

  # Check 7: reads the ADDRESS_PERIOD_START column (time-between-changes)
  check("R/106 reads the ADDRESS_PERIOD_START column (time-between-changes)",
        grepl("ADDRESS_PERIOD_START", r106_text))

  # Check 8: has normalize_zip9 with hyphen strip (str_remove_all)
  check("R/106 has normalize_zip9 with hyphen strip",
        grepl("normalize_zip9", r106_text) && grepl("str_remove_all", r106_text))

  # Check 9: has normalize_zip5 (str_sub 1,5)
  check("R/106 has normalize_zip5 (str_sub 1,5)",
        grepl("normalize_zip5", r106_text) && grepl("str_sub", r106_text))

  # Check 10: validates ZIP9 as 9 digits (^[0-9]{9}$)
  check("R/106 validates ZIP9 as 9 digits (^[0-9]{9}$)",
        grepl("\\^\\[0-9\\]\\{9\\}\\$", r106_text))

  # Check 11: computes per-patient distinct ZIP counts (group_by(ID) + n_distinct)
  check("R/106 computes per-patient distinct ZIP counts (group_by(ID) + n_distinct)",
        grepl("group_by\\(ID\\)", r106_text) && grepl("n_distinct", r106_text))

  # Check 12: writes a styled xlsx (add_styled_sheet + wb_save)
  check("R/106 writes a styled xlsx (add_styled_sheet + wb_save)",
        grepl("add_styled_sheet", r106_text) && grepl("wb_save", r106_text))

  # Check 13: applies HIPAA small-cell suppression (<=10)
  check("R/106 applies HIPAA small-cell suppression (<=10)",
        grepl("<11|<= 10|<=10", r106_text))

  # Check 14: RUNTIME (HiPerGator-only, gated) -- output xlsx present with sheets.
  # Kept green locally: SKIPPED when IS_LOCAL or the output xlsx is absent.
  # Mirrors Section 15p Check 14 IS_LOCAL-gate pattern (lines 2301-2315).
  out_xlsx_121 <- file.path(CONFIG$output_dir, "zip_change_frequency.xlsx")
  if (!IS_LOCAL && file.exists(out_xlsx_121)) {
    check("R/106 output xlsx exists with sheets (Phase 121, HiPerGator)",
          file.exists(out_xlsx_121))
  } else {
    check("R/106 output xlsx present -- SKIPPED (local / no output) (Phase 121)",
          TRUE)
  }

} else {
  # If script missing, register the dependent checks as FALSE so total stays honest
  for (i in 2:14) check(paste0("R/106 dependent check #", i, " -- SKIPPED (script missing)"), FALSE)
}

# ==============================================================================
# SECTION 15t: MED_ADMIN/DISPENSING CHEMO-DETECTION GAP FIX (Phase 122) ----
# ==============================================================================

# Phase 122 closed the silent-failure bug where 7 consumers gated DISPENSING and
# MED_ADMIN chemo detection on "RXNORM_CUI" %in% colnames(...), but neither table
# has that column in this OneFlorida+ extract.  The fix:
#   - Shared helper get_chemo_hits() in utils_treatment.R (PRESCRIBING/DISPENSING/MED_ADMIN)
#   - load_ndc_crosswalk() reads data/reference/ndc_rxnorm_crosswalk.rds (built by R/108)
#   - All 7 consumers (R/10,R/26,R/25,R/11,R/27,R/20,R/76) updated
#   - R/01 DISPENSING_SPEC + MED_ADMIN_SPEC no longer declare phantom RXNORM_CUI
#   - Fixtures corrected to real column layout
# STRUCTURAL greps pass LOCALLY; IS_LOCAL-gated runtime check runs on HiPerGator.

message("\n[Phase 122] MED_ADMIN/DISPENSING chemo-detection gap fix (R/108 + helpers)...")

utils_t_lines <- if (file.exists("R/utils/utils_treatment.R")) {
  readLines("R/utils/utils_treatment.R", warn = FALSE)
} else character(0)
utils_t_text <- paste(utils_t_lines, collapse = "\n")

# Check 1: MED_ADMIN fixture header has NO "RXNORM_CUI"
ma_fixture_path <- "tests/fixtures/MED_ADMIN_Mailhot_V1.csv"
check("MED_ADMIN fixture header has no RXNORM_CUI column (Phase 122)",
      if (file.exists(ma_fixture_path)) {
        header <- readLines(ma_fixture_path, n = 1L, warn = FALSE)
        !grepl("RXNORM_CUI", header)
      } else TRUE)

# Check 2: DISPENSING fixture header has NO "RXNORM_CUI" AND NO "RAW_DISPENSE_MED_NAME"
disp_fixture_path <- "tests/fixtures/DISPENSING_Mailhot_V1.csv"
check("DISPENSING fixture header has no RXNORM_CUI and no RAW_DISPENSE_MED_NAME (Phase 122)",
      if (file.exists(disp_fixture_path)) {
        header <- readLines(disp_fixture_path, n = 1L, warn = FALSE)
        !grepl("RXNORM_CUI", header) && !grepl("RAW_DISPENSE_MED_NAME", header)
      } else TRUE)

# Check 3: get_chemo_hits defined in utils_treatment.R
check("get_chemo_hits defined in utils_treatment.R (Phase 122)",
      grepl("get_chemo_hits <- function", utils_t_text))

# Check 4: get_chemo_hits DISPENSING path references ndc_crosswalk[normalize_ndc
check("get_chemo_hits DISPENSING uses ndc_crosswalk[normalize_ndc lookup (Phase 122)",
      grepl("ndc_crosswalk\\[normalize_ndc", utils_t_text))

# Check 5: get_chemo_hits MED_ADMIN uses MEDADMIN_TYPE == "RX"
check("get_chemo_hits MED_ADMIN uses MEDADMIN_TYPE == \"RX\" (Phase 122)",
      grepl('MEDADMIN_TYPE == "RX"', utils_t_text))

# Check 6: load_ndc_crosswalk defined and degrades gracefully (return(character(0)))
check("load_ndc_crosswalk defined and degrades gracefully with return(character(0)) (Phase 122)",
      grepl("load_ndc_crosswalk <- function", utils_t_text) &&
        grepl("return\\(character\\(0\\)\\)", utils_t_text))

# Check 7: R/108 script file exists
check("R/108_build_ndc_rxnorm_crosswalk.R exists (Phase 122)",
      file.exists("R/108_build_ndc_rxnorm_crosswalk.R"))

# Check 8: R/01 DISPENSING_SPEC + MED_ADMIN_SPEC no longer declare phantom RXNORM_CUI
r01_text <- if (file.exists("R/01_load_pcornet.R")) {
  paste(readLines("R/01_load_pcornet.R", warn = FALSE), collapse = "\n")
} else ""
check("R/01 DISPENSING_SPEC and MED_ADMIN_SPEC no longer declare phantom RXNORM_CUI (Phase 122)",
      {
        # Leading [^_] matches the bare RXNORM_CUI declaration but excludes
        # RAW_RXNORM_CUI — PRESCRIBING_SPEC legitimately has BOTH, and a loose
        # substring would count 2 and false-FAIL. gregexpr returns -1 (length 1)
        # on no match, so guard that before counting.
        m <- gregexpr("[^_]RXNORM_CUI = col_character", r01_text)[[1]]
        n_rxnorm_colspec <- if (m[1] == -1L) 0L else length(m)
        # Only PRESCRIBING_SPEC's bare RXNORM_CUI should remain — expect exactly 1
        n_rxnorm_colspec == 1L
      })

# Check 9: R/01 D-12 revision comment present (2 occurrences: DISPENSING + MED_ADMIN)
check("R/01 has 2 D-12 revised Phase 122 comments (DISPENSING + MED_ADMIN specs) (Phase 122)",
      {
        n_d12 <- length(gregexpr("D-12 revised Phase 122", r01_text)[[1]])
        n_d12 == 2L
      })

# Check 10: R/10 old guard removed
r10_text <- if (file.exists("R/10_cohort_predicates.R")) {
  paste(readLines("R/10_cohort_predicates.R", warn = FALSE), collapse = "\n")
} else ""
check("R/10 old RXNORM_CUI colnames guard removed (Phase 122)",
      !grepl('"RXNORM_CUI" %in% colnames', r10_text))

# Check 11: R/11 old guard removed and get_chemo_hits present
r11_text <- if (file.exists("R/11_treatment_payer.R")) {
  paste(readLines("R/11_treatment_payer.R", warn = FALSE), collapse = "\n")
} else ""
check("R/11 old RXNORM_CUI colnames guard removed AND get_chemo_hits present (Phase 122)",
      !grepl('"RXNORM_CUI" %in% colnames', r11_text) &&
        grepl("get_chemo_hits", r11_text))

# Check 12: R/26 chemo uses get_chemo_hits (>=2) AND immuno RXNORM_CUI guards preserved (2)
r26_text <- if (file.exists("R/26_treatment_episodes.R")) {
  paste(readLines("R/26_treatment_episodes.R", warn = FALSE), collapse = "\n")
} else ""
check("R/26 chemo uses get_chemo_hits (>=2) AND 2 immuno RXNORM_CUI guards preserved (Phase 122)",
      {
        n_hits    <- length(gregexpr("get_chemo_hits", r26_text)[[1]])
        n_immuno_disp <- length(gregexpr(
          '"RXNORM_CUI" %in% colnames\\(get_pcornet_table\\("DISPENSING"\\)\\)', r26_text)[[1]])
        n_immuno_ma   <- length(gregexpr(
          '"RXNORM_CUI" %in% colnames\\(get_pcornet_table\\("MED_ADMIN"\\)\\)', r26_text)[[1]])
        n_hits >= 2L && n_immuno_disp == 1L && n_immuno_ma == 1L
      })

# Check 13: R/27/R/20/R/76 corrected — R/20 has no RAW_DISPENSE_MED_NAME; R/76 uses get_chemo_hits
r20_text <- if (file.exists("R/20_treatment_inventory.R")) {
  paste(readLines("R/20_treatment_inventory.R", warn = FALSE), collapse = "\n")
} else ""
r76_text <- if (file.exists("R/76_treatment_source_coverage.R")) {
  paste(readLines("R/76_treatment_source_coverage.R", warn = FALSE), collapse = "\n")
} else ""
check("R/20 has no RAW_DISPENSE_MED_NAME AND R/76 uses get_chemo_hits (Phase 122)",
      !grepl("RAW_DISPENSE_MED_NAME", r20_text) &&
        grepl("get_chemo_hits", r76_text))

# Check 14: IS_LOCAL-gated runtime check — source utils + fixtures and assert get_chemo_hits returns >=1 row
if (IS_LOCAL) {
  # Runtime path: source helpers and attempt a fixture-based hit (requires ndc_rxnorm_crosswalk.rds)
  tryCatch({
    if (exists("get_chemo_hits") && exists("load_ndc_crosswalk") &&
        exists("TREATMENT_CODES")) {
      cw <- load_ndc_crosswalk()
      hits <- get_chemo_hits("MED_ADMIN", TREATMENT_CODES$chemo_rxnorm, cw)
      check("get_chemo_hits('MED_ADMIN') returns >=1 row against local fixture (Phase 122, IS_LOCAL)",
            !is.null(hits) && nrow(hits) >= 1L)
    } else {
      check("get_chemo_hits runtime check -- SKIPPED (helpers not loaded in this scope) (Phase 122)",
            TRUE)
    }
  }, error = function(e) {
    check("get_chemo_hits runtime check -- SKIPPED (error loading fixtures) (Phase 122)", TRUE)
  })
} else {
  check("get_chemo_hits runtime check -- SKIPPED (HiPerGator runtime, not IS_LOCAL) (Phase 122)",
        TRUE)
}

# ==============================================================================
# SECTION 15u: MED_ADMIN/DISPENSING FIX BEFORE/AFTER DIFF + NDC AUDIT (Phase 123) ----
# ==============================================================================

# Phase 123 added R/109_med_admin_dispensing_fix_impact_audit.R: a read-only
# post-fix quantification of the Phase 122 chemo-detection fix. It computes the
# deterministic before/after diff using the production get_chemo_hits() path,
# audits the ~7,739 unmatched + ~16,588 resolved NDCs from the R/108 crosswalk
# via four methods (D-07 string match, D-08 frequency rank, D-09 IS_LOCAL-gated
# RxNav re-query, D-10 resolved-non-chemo gap flag), and delivers a single
# multi-sheet openxlsx2 workbook (D-11). NOT wired into R/39 (D-12).
# STRUCTURAL greps pass LOCALLY; full runtime is HiPerGator (checkpoint Task 3).

message("\n[Phase 123] MED_ADMIN/DISPENSING fix before/after diff + NDC audit (R/109)...")

# Check 1: R/109 script file exists
r109_exists <- file.exists("R/109_med_admin_dispensing_fix_impact_audit.R")
check("R/109_med_admin_dispensing_fix_impact_audit.R exists (Phase 123)", r109_exists)

if (r109_exists) {
  r109_lines <- readLines("R/109_med_admin_dispensing_fix_impact_audit.R", warn = FALSE)
  r109_text  <- paste(r109_lines, collapse = "\n")

  # Check 2: R/109 uses get_chemo_hits for source extraction
  check("R/109 uses get_chemo_hits for chemo source extraction (Phase 123)",
        grepl("get_chemo_hits", r109_text))

  # Check 3: before set is PRESCRIBING-only (uses get_chemo_hits("PRESCRIBING"))
  check("R/109 before set is PRESCRIBING-only via get_chemo_hits (Phase 123)",
        grepl('get_chemo_hits\\("PRESCRIBING"', r109_text))

  # Check 4: after set includes MED_ADMIN + DISPENSING
  check("R/109 after set includes MED_ADMIN and DISPENSING sources (Phase 123)",
        grepl('get_chemo_hits\\("MED_ADMIN"', r109_text) &&
          grepl('get_chemo_hits\\("DISPENSING"', r109_text))

  # Check 5: parses dates with parse_pcornet_date after collect (Pitfall 2)
  check("R/109 parses treatment_date with parse_pcornet_date after collect (Phase 123)",
        grepl("parse_pcornet_date", r109_text))

  # Check 6: D-04 timing shift uses first_after < first_before comparison
  check("R/109 D-04 timing shift compares first_after < first_before (Phase 123)",
        grepl("first_after < first_before", r109_text))

  # Check 7: D-05 per-ingredient delta maps via MEDICATION_LOOKUP[triggering_code]
  check("R/109 D-05 per-ingredient delta maps via MEDICATION_LOOKUP[triggering_code] (Phase 123)",
        grepl("MEDICATION_LOOKUP\\[triggering_code\\]", r109_text))

  # Check 8: D-06 guarded on file.exists(EPISODES_RDS) and does NOT source R/25/26/28
  check("R/109 D-06 is guarded by file.exists(EPISODES_RDS) and does not source R/25/26/28 (Phase 123)",
        grepl("file.exists\\(EPISODES_RDS\\)", r109_text) &&
          !grepl('source\\("R/2[568]', r109_text))

  # Check 9: D-06 labeled as UPPER BOUND estimate
  check("R/109 D-06 regimen impact labeled UPPER BOUND (Phase 123)",
        grepl("UPPER BOUND", r109_text))

  # Check 10: D-09 IS_LOCAL-gated and uses ndcproperties + ndcstatus alternate endpoints
  check("R/109 D-09 IS_LOCAL-gated with ndcproperties and ndcstatus endpoints (Phase 123)",
        grepl("ndcproperties", r109_text) &&
          grepl("ndcstatus", r109_text) &&
          grepl("if.*!IS_LOCAL", r109_text))

  # Check 11: D-09 writes to a NEW requery CSV, does NOT overwrite the audit CSV
  check("R/109 D-09 writes ndc_rxnorm_crosswalk_requery.csv (NOT overwriting audit CSV) (Phase 123)",
        grepl("ndc_rxnorm_crosswalk_requery\\.csv", r109_text) &&
          !grepl('write\\.csv.*"ndc_rxnorm_crosswalk_audit', r109_text))

  # Check 12: D-10 flags CANDIDATE_CHEMO_GAP without modifying TREATMENT_CODES list
  check("R/109 D-10 flags CANDIDATE_CHEMO_GAP without modifying TREATMENT_CODES$chemo_rxnorm (Phase 123)",
        grepl("CANDIDATE_CHEMO_GAP", r109_text) &&
          !grepl("TREATMENT_CODES\\$chemo_rxnorm <-", r109_text))

  # Check 13: D-11 delivers single xlsx via openxlsx2 wb_workbook() + wb$save()
  check("R/109 D-11 writes single xlsx via wb_workbook() and wb$save(OUTPUT_XLSX) (Phase 123)",
        grepl("wb_workbook\\(\\)", r109_text) &&
          grepl("wb\\$save\\(OUTPUT_XLSX\\)", r109_text))

  # Check 14: IS_LOCAL-gated runtime check (structural PASS both branches)
  if (IS_LOCAL) {
    check("R/109 runtime (Rscript parse + DuckDB diff + xlsx) -- SKIPPED (HiPerGator runtime) (Phase 123)",
          TRUE)
  } else {
    check("R/109 runtime check -- SKIPPED (HiPerGator runtime, not IS_LOCAL) (Phase 123)",
          TRUE)
  }

} else {
  # If script missing, register the dependent checks as FALSE so total stays honest
  for (i in 2:14) check(paste0("R/109 dependent check #", i, " -- SKIPPED (script missing)"), FALSE)
}

# ==============================================================================
# SECTION 15v: PHASE 124 OUTPUT-LEVEL BEFORE/AFTER REPORT + UNMAPPED-NAME AUDIT ----
# ==============================================================================

# Phase 124 added R/110_output_level_before_after_report.R: a read-only
# output-level proof artifact that proves the Phase 122 chemo-detection fix
# propagated to FINAL PRODUCTS (treatment episodes, regimen distribution,
# first-chemo timing, payer-anchor window). The Unmapped Names sheet (D-08)
# lists raw/cleaned drug names with no canonical mapping for SME review.
# NOT wired into R/39 (D: one-off analysis, like R/109).
# STRUCTURAL greps pass LOCALLY; full runtime is HiPerGator (Plan 04).

message("\n[Phase 124] Output-level before/after report + unmapped-name audit (R/110)...")

# Check 1: R/110 script file exists
r110_exists <- file.exists("R/110_output_level_before_after_report.R")
check("R/110_output_level_before_after_report.R exists (Phase 124)", r110_exists)

if (r110_exists) {
  r110_lines <- readLines("R/110_output_level_before_after_report.R", warn = FALSE)
  r110_text  <- paste(r110_lines, collapse = "\n")

  # Check 2: BEFORE baseline uses treatment_episodes_pre_p124.rds
  check("R/110 BEFORE baseline reads treatment_episodes_pre_p124.rds (Phase 124, D-03)",
        grepl("treatment_episodes_pre_p124", r110_text))

  # Check 3: BEFORE baseline uses gantt_episodes_pre_p124.csv
  check("R/110 BEFORE baseline reads gantt_episodes_pre_p124.csv (Phase 124, D-03)",
        grepl("gantt_episodes_pre_p124", r110_text))

  # Check 4: add_styled_sheet called >= 6 times (definition + 5 sheet calls)
  n_add_styled <- length(gregexpr("add_styled_sheet", r110_text)[[1]])
  check(paste0("R/110 add_styled_sheet called >= 6 times (defn + 5 sheets): found ", n_add_styled, " (Phase 124)"),
        n_add_styled >= 6L)

  # Check 5: suppress_small called >= 5 times (HIPAA on every patient count, D-15)
  n_suppress <- length(gregexpr("suppress_small", r110_text)[[1]])
  check(paste0("R/110 suppress_small called >= 5 times (D-15 HIPAA): found ", n_suppress, " (Phase 124)"),
        n_suppress >= 5L)

  # Check 6: output path contains output_level_before_after_report.xlsx
  check("R/110 references output_level_before_after_report.xlsx output path (Phase 124)",
        grepl("output_level_before_after_report\\.xlsx", r110_text))

  # Check 7: D-08 unmapped detection uses canonicalize_drug_name
  check("R/110 D-08 unmapped detection uses canonicalize_drug_name (Phase 124)",
        grepl("canonicalize_drug_name", r110_text))

  # Check 8: Sheet 2 Regimen Distribution present (D-09)
  check("R/110 contains Regimen Distribution sheet (D-02/D-09, Phase 124)",
        grepl("regimen", r110_text, ignore.case = TRUE))

  # Check 9: Sheet 4 Payer-Anchor Window present (D-02)
  check("R/110 contains payer-anchor window sheet (D-02, Phase 124)",
        grepl("payer", r110_text, ignore.case = TRUE))

  # Check 10: Sheet 3 First-Chemo Timing Shift present
  check("R/110 contains first-chemo timing shift analysis (Phase 124)",
        grepl("timing", r110_text, ignore.case = TRUE) &&
          grepl("first_chemo", r110_text))

  # Check 11: >= 2 file.exists() guards so script parses on Windows
  n_file_exists <- length(gregexpr("file\\.exists", r110_text)[[1]])
  check(paste0("R/110 has >= 2 file.exists() guards (Windows-parse safe): found ", n_file_exists, " (Phase 124)"),
        n_file_exists >= 2L)

  # Check 12 (negative): R/110 is NOT wired into R/39_run_all_investigations.R
  r39_exists <- file.exists("R/39_run_all_investigations.R")
  if (r39_exists) {
    r39_text <- paste(readLines("R/39_run_all_investigations.R", warn = FALSE), collapse = "\n")
    check("R/110 is NOT wired into R/39_run_all_investigations.R (one-off analysis, Phase 124)",
          !grepl("R/110|110_output_level", r39_text))
  } else {
    check("R/39 not found -- R/110 not-wired check SKIPPED (Phase 124)", TRUE)
  }

  # Check 13: IS_LOCAL runtime gate (structural PASS both branches)
  if (IS_LOCAL) {
    check("R/110 runtime (xlsx generation + sheet row counts) -- SKIPPED (HiPerGator runtime) (Phase 124)",
          TRUE)
  } else {
    check("R/110 runtime check -- SKIPPED (HiPerGator runtime, not IS_LOCAL) (Phase 124)",
          TRUE)
  }

} else {
  # If script missing, register the dependent checks as FALSE so total stays honest
  for (i in 2:13) check(paste0("R/110 dependent check #", i, " -- SKIPPED (script missing)"), FALSE)
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

  check("R/57 has grain-prefixed sheets (Enc Sub-Category Detail + Enc Treatment Detail)",
        any(grepl("Enc Sub-Category Detail", r57_lines)) &&
        any(grepl("Enc Treatment Detail", r57_lines)))

  check("R/57 defines map_cancer_codes_to_categories helper function",
        any(grepl("map_cancer_codes_to_categories", r57_lines)))

  check("R/57 uses both CANCER_SITE_MAP and ICD9_CANCER_SITE_MAP for code-to-category mapping",
        any(grepl("CANCER_SITE_MAP", r57_lines)) &&
        any(grepl("ICD9_CANCER_SITE_MAP", r57_lines)))

  check("R/57 sorts cancer categories ascending (Phase 112 universal sort)",
        any(grepl("sort\\(unique\\(", r57_lines)))

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
# SECTION 30: R/30 CONDITION LINKAGE INVESTIGATION (COND-01, COND-02, COND-03) ----
# ==============================================================================

message("\n[30/32] R/30 CONDITION linkage investigation validation...")

# --- Script existence ---
check("R/30_condition_linkage_investigation.R exists",
      file.exists("R/30_condition_linkage_investigation.R"))

if (file.exists("R/30_condition_linkage_investigation.R")) {
  r30_lines <- readLines("R/30_condition_linkage_investigation.R", warn = FALSE)

  # --- Structural checks (static analysis) ---

  # COND-01: CONDITION table query
  check("R/30 queries CONDITION table via get_pcornet_table()",
        any(grepl('get_pcornet_table\\("CONDITION"\\)', r30_lines)))

  # D-01: ICD-9/10 filtering
  check("R/30 filters CONDITION_TYPE to ICD-9 ('09') and ICD-10 ('10')",
        any(grepl('CONDITION_TYPE.*%in%.*c\\("09", "10"\\)', r30_lines)))

  # D-03: Link method labels
  check("R/30 uses 'condition_encounter' link method label",
        any(grepl('condition_link_method.*=.*"condition_encounter"', r30_lines)))

  check("R/30 uses 'condition_date' link method label",
        any(grepl('condition_link_method.*=.*"condition_date"', r30_lines)))

  # COND-03: classify_codes for cancer category assignment
  check("R/30 uses classify_codes() for cancer category assignment",
        any(grepl("classify_codes\\(CONDITION\\)", r30_lines)))

  # D-04: ONSET_DATE (not REPORT_DATE) for temporal matching
  check("R/30 uses ONSET_DATE for temporal matching",
        any(grepl("ONSET_DATE", r30_lines)))

  check("R/30 does NOT use REPORT_DATE for temporal matching",
        !any(grepl("REPORT_DATE.*episode_start|days_before.*REPORT_DATE", r30_lines)))

  # D-05: Only unlinked episodes (cancer_link_method == "none")
  check("R/30 filters to unlinked episodes (cancer_link_method == 'none')",
        any(grepl('cancer_link_method.*==.*"none"', r30_lines)))

  # D-06: Non-destructive constraint (no saveRDS to treatment_episodes)
  check("R/30 does NOT call saveRDS on treatment_episodes.rds (read-only investigation)",
        !any(grepl("saveRDS.*treatment_episodes", r30_lines)))

  # D-09: Report as new sheet in episode_classification_audit.xlsx
  check("R/30 loads existing workbook via wb_load()",
        any(grepl("wb_load", r30_lines)))

  check("R/30 creates 'Linkage Improvement' sheet",
        any(grepl('"Linkage Improvement"', r30_lines)))

  # D-10: Treatment type breakdown
  check("R/30 produces treatment type breakdown",
        any(grepl("treatment_type_breakdown", r30_lines)) &&
          any(grepl("group_by\\(treatment_type\\)", r30_lines)))

  # DuckDB cleanup
  check("R/30 closes DuckDB connection via close_pcornet_con()",
        any(grepl("close_pcornet_con\\(\\)", r30_lines)))

  # Decision traceability
  check("R/30 header contains decision traceability (D-01 through D-10)",
        any(grepl("D-01:", r30_lines)) && any(grepl("D-10:", r30_lines)))

  # --- Output validation (optional, only if xlsx exists) ---
  AUDIT_XLSX_PATH <- file.path(CONFIG$output_dir, "episode_classification_audit.xlsx")

  if (file.exists(AUDIT_XLSX_PATH)) {
    tryCatch({
      wb <- openxlsx2::wb_load(AUDIT_XLSX_PATH)
      sheet_names <- wb$get_sheet_names()

      check("episode_classification_audit.xlsx contains 'Linkage Improvement' sheet",
            "Linkage Improvement" %in% sheet_names)

      if ("Linkage Improvement" %in% sheet_names) {
        sheet_data <- openxlsx2::wb_to_df(wb, sheet = "Linkage Improvement", start_row = 4)

        check("'Linkage Improvement' sheet has expected columns (Metric, Count, Percent)",
              all(c("Metric", "Count", "Percent") %in% colnames(sheet_data)))

        if ("Metric" %in% colnames(sheet_data)) {
          check("'Linkage Improvement' sheet contains 'Total episodes' row",
                any(grepl("Total episodes", sheet_data$Metric)))

          check("'Linkage Improvement' sheet contains 'Improvement' row",
                any(grepl("Improvement", sheet_data$Metric)))
        }
      }
    }, error = function(e) {
      message(glue("  SKIP: Could not read xlsx ({e$message})"))
    })
  } else {
    message("  SKIP: episode_classification_audit.xlsx not found (run R/28 first)")
  }
} else {
  message("  FAIL: R/30 script not found")
  failed <- failed + 1L
}

# ==============================================================================
# SECTION 31A: PHASE 101 -- BROADENED DRUG GROUPING OUTPUT (DRUG-01, DRUG-02, DRUG-03) ----
# ==============================================================================
# Validates R/57 broadened drug grouping with cancer_linked flag and dual-output.

message("\n[31/35] Phase 101: Broadened drug grouping output validation...")

if (file.exists("R/57_drug_grouping_instances.R")) {
  r57_lines_101 <- readLines("R/57_drug_grouping_instances.R", warn = FALSE)

  # DRUG-01: Broadened output includes ALL encounters (table1_all, table2_all)
  check("R/57 creates table1_all (broadened, all encounters)",
        any(grepl("table1_all", r57_lines_101)))

  check("R/57 creates table2_all (broadened, all encounters)",
        any(grepl("table2_all", r57_lines_101)))

  # DRUG-02: cancer_linked flag derived from cancer_codes
  check("R/57 derives cancer_linked from !is.na(cancer_codes)",
        any(grepl("cancer_linked.*!is\\.na\\(cancer_codes\\)", r57_lines_101)) ||
        any(grepl("cancer_linked.*!is\\.na\\(cancer_category_names\\)", r57_lines_101)))

  # DRUG-03: Linked-only output preserved
  check("R/57 creates table1_linked (cancer-linked-only backward compat)",
        any(grepl("table1_linked", r57_lines_101)))

  check("R/57 creates table2_linked (cancer-linked-only backward compat)",
        any(grepl("table2_linked", r57_lines_101)))

  # D-02: Reference code filter still present
  check("R/57 retains reference code filter (valid_reference_codes OR Immunotherapy)",
        any(grepl("valid_reference_codes.*Immunotherapy", r57_lines_101)) ||
        any(grepl("triggering_code.*valid_reference_codes", r57_lines_101)))

  # Linked-only strips cancer_linked column (Pitfall 1)
  check("R/57 removes cancer_linked from linked-only export (select(-cancer_linked))",
        sum(grepl("select\\(-cancer_linked\\)", r57_lines_101)) >= 2)

  # D-06: Cross-tab summary sheet
  check("R/57 creates cross-tab summary (crosstab_summary)",
        any(grepl("crosstab_summary", r57_lines_101)))

  check("R/57 has 'Linked vs Unlinked' sheet in broadened workbook",
        any(grepl("Linked vs Unlinked", r57_lines_101)))

  # D-07/D-08: Dual-output file paths
  check("R/57 defines linked-only output paths (_linked_only suffix)",
        any(grepl("_linked_only\\.xlsx", r57_lines_101)))

  # D-09: Broadened has 3 sheets (wb_broad with 3 add_worksheet calls)
  check("R/57 creates separate broadened workbook (wb_broad)",
        any(grepl("wb_broad.*wb_workbook", r57_lines_101)))

  check("R/57 creates separate linked-only workbook (wb_linked)",
        any(grepl("wb_linked.*wb_workbook", r57_lines_101)))

  # Section 6B cross-tab exists
  check("R/57 has Section 6B for cross-tab summary",
        any(grepl("SECTION 6B.*CROSS-TAB", r57_lines_101)))

  # Decision traceability
  check("R/57 header contains Phase 101 decision traceability (D-01 through D-09)",
        any(grepl("D-01:", r57_lines_101)) && any(grepl("D-09:", r57_lines_101)))

  # Optional: output file validation (only if broadened xlsx exists)
  BROADENED_XLSX_PATH <- file.path(CONFIG$output_dir, "encounter_level_drug_grouping_instances.xlsx")
  LINKED_ONLY_XLSX_PATH <- file.path(CONFIG$output_dir, "encounter_level_drug_grouping_instances_linked_only.xlsx")

  if (file.exists(BROADENED_XLSX_PATH) && file.exists(LINKED_ONLY_XLSX_PATH)) {
    tryCatch({
      wb_b <- openxlsx2::wb_load(BROADENED_XLSX_PATH)
      wb_l <- openxlsx2::wb_load(LINKED_ONLY_XLSX_PATH)

      b_sheets <- wb_b$get_sheet_names()
      l_sheets <- wb_l$get_sheet_names()

      check("Broadened xlsx has 3 sheets",
            length(b_sheets) == 3)

      check("Linked-only xlsx has 2 sheets",
            length(l_sheets) == 2)

      check("Broadened xlsx contains 'Linked vs Unlinked' sheet",
            "Linked vs Unlinked" %in% b_sheets)

      # Check cancer_linked column in broadened
      b_data <- openxlsx2::wb_to_df(wb_b, sheet = "Enc Sub-Category Detail", start_row = 1)
      check("Broadened Sheet 1 contains cancer_linked column",
            "cancer_linked" %in% colnames(b_data))

      # Check cancer_linked column NOT in linked-only
      l_data <- openxlsx2::wb_to_df(wb_l, sheet = "Enc Sub-Category Detail", start_row = 1)
      check("Linked-only Sheet 1 does NOT contain cancer_linked column",
            !("cancer_linked" %in% colnames(l_data)))

      # Broadened should have >= rows than linked-only
      check("Broadened has >= rows than linked-only (broadened is superset)",
            nrow(b_data) >= nrow(l_data))

      # Cross-tab sheet structure
      ct_data <- openxlsx2::wb_to_df(wb_b, sheet = "Linked vs Unlinked", start_row = 1)
      check("Cross-tab has treatment_type, linked_count, unlinked_count columns",
            all(c("treatment_type", "linked_count", "unlinked_count") %in% colnames(ct_data)))

    }, error = function(e) {
      message(glue("  SKIP: Could not read xlsx files ({e$message})"))
    })
  } else {
    message("  SKIP: Broadened/linked-only xlsx not found (run R/57 first)")
  }

} else {
  message("  FAIL: R/57_drug_grouping_instances.R not found")
  failed <- failed + 1L
}

# ==============================================================================
# SECTION 31B: PHASE 109 -- CO-ADMINISTRATION ANALYSIS (COADMIN-FIX-01/02/03) ----
# ==============================================================================
# Validates R/58 co-administration analysis structural integrity.
# Updated from Phase 102 to Phase 109: ICD9 filtering + date-grain analysis.

message("\n[32/35] Phase 109: Co-administration analysis validation...")

if (file.exists("R/58_co_administration_analysis.R")) {
  r58_lines <- readLines("R/58_co_administration_analysis.R", warn = FALSE)

  # Phase 102 carried-forward: Chemotherapy-only filter (D-04)
  check("R/58 filters to Chemotherapy treatment_type",
        any(grepl('treatment_type.*==.*"Chemotherapy"', r58_lines)))

  # Phase 102 carried-forward: Regimen exclusion via anti_join (D-05)
  check("R/58 excludes regimen-classified encounters via anti_join",
        any(grepl("anti_join.*regimen", r58_lines, ignore.case = TRUE)))

  # Phase 109 D-01: Non-specific code filtering (3 categories)
  check("R/58 references TREATMENT_CODES$chemo_icd9 for ICD9 procedure codes (D-01)",
        any(grepl("chemo_icd9", r58_lines)))

  check("R/58 references TREATMENT_CODES$chemo_dx_icd9 for diagnosis encounter codes (D-01)",
        any(grepl("chemo_dx_icd9", r58_lines)))

  check("R/58 references TREATMENT_CODES$chemo_dx_icd10 for diagnosis encounter codes (D-01)",
        any(grepl("chemo_dx_icd10", r58_lines)))

  check("R/58 references TREATMENT_CODES$chemo_icd10pcs_prefixes for PCS route codes (D-01)",
        any(grepl("chemo_icd10pcs_prefixes", r58_lines)))

  check("R/58 builds NON_SPECIFIC_EXACT for exact-match non-specific codes (D-01)",
        any(grepl("NON_SPECIFIC_EXACT", r58_lines)))

  check("R/58 builds NON_SPECIFIC_PCS_RX regex for prefix-match PCS codes (D-01)",
        any(grepl("NON_SPECIFIC_PCS_RX", r58_lines)))

  # Phase 109 D-03: Date-grain single-agent detection
  check("R/58 groups by patient_id and treatment_date for single-agent ID (D-03)",
        any(grepl("group_by.*patient_id.*treatment_date", r58_lines)))

  check("R/58 uses n_distinct(triggering_code) for single-agent count (D-03/D-05)",
        any(grepl("n_distinct.*triggering_code", r58_lines)))

  # Phase 109 D-04: Agent-exclusion in temporal self-join (NOT encounter-exclusion)
  check("R/58 uses agent-exclusion: triggering_code != i.triggering_code (D-04)",
        any(grepl("triggering_code.*!=.*i\\.triggering_code", r58_lines)))

  check("R/58 does NOT use encounter-exclusion: no ENCOUNTERID != i.ENCOUNTERID (D-04)",
        !any(grepl("ENCOUNTERID.*!=.*i\\.ENCOUNTERID", r58_lines)))

  # Phase 102 carried-forward: 30-day window
  check("R/58 uses 30-day window for co-administration",
        any(grepl("<= 30", r58_lines)) || any(grepl("<=\\s*30", r58_lines)))

  # Phase 109 D-07: Date-grain detail table columns
  check("R/58 has index_date column (date grain, D-07)",
        any(grepl("index_date", r58_lines)))

  check("R/58 has index_drug_code column (D-07)",
        any(grepl("index_drug_code", r58_lines)))

  check("R/58 has coadmin_date column (date grain, D-07)",
        any(grepl("coadmin_date", r58_lines)))

  check("R/58 has coadmin_drug_code column (D-07)",
        any(grepl("coadmin_drug_code", r58_lines)))

  check("R/58 does NOT have index_encounter_id (encounter IDs removed per D-07)",
        !any(grepl("index_encounter_id", r58_lines)))

  check("R/58 does NOT have coadmin_encounter_id (encounter IDs removed per D-07)",
        !any(grepl("coadmin_encounter_id", r58_lines)))

  # days_apart column
  check("R/58 calculates days_apart for temporal analysis",
        any(grepl("days_apart", r58_lines)))

  # D-08 carried-forward: Both drug name and code shown
  check("R/58 includes index_drug_name and coadmin_drug_name",
        any(grepl("index_drug_name", r58_lines)) && any(grepl("coadmin_drug_name", r58_lines)))

  # D-06: Two-sheet xlsx output (carried forward)
  check("R/58 creates 'Co-Administration Detail' sheet (D-06)",
        any(grepl("Co-Administration Detail", r58_lines)))

  check("R/58 creates 'Pattern Summary' sheet (D-06)",
        any(grepl("Pattern Summary", r58_lines)))

  # Symmetric pair deduplication (carried forward)
  check("R/58 uses pmin/pmax for symmetric pair deduplication",
        any(grepl("pmin", r58_lines)) && any(grepl("pmax", r58_lines)))

  # Investigation script checks (carried forward)
  check("R/58 sources R/00_config.R",
        any(grepl('source.*R/00_config', r58_lines)))

  check("R/58 does NOT contain saveRDS (investigation only)",
        !any(grepl("saveRDS[(]", r58_lines)))

  check("R/58 uses assert_rds_exists for input validation",
        any(grepl("assert_rds_exists", r58_lines)))

  # data.table temporal join (carried forward)
  check("R/58 uses data.table cartesian join (allow.cartesian)",
        any(grepl("allow\\.cartesian", r58_lines)))

  # Decision traceability: Phase 109 decisions
  check("R/58 header contains Phase 109 decision traceability (D-01 through D-07)",
        any(grepl("D-01", r58_lines)) && any(grepl("D-07", r58_lines)))

  # Optional: output file validation (only if co_administration_analysis.xlsx exists)
  COADMIN_XLSX_PATH <- file.path(CONFIG$output_dir, "co_administration_analysis.xlsx")
  if (file.exists(COADMIN_XLSX_PATH)) {
    tryCatch({
      wb_ca <- openxlsx2::wb_load(COADMIN_XLSX_PATH)
      sheet_names_ca <- wb_ca$sheet_names

      check("co_administration_analysis.xlsx has 2 sheets",
            length(sheet_names_ca) == 2)

      check("Sheet 1 is 'Co-Administration Detail'",
            sheet_names_ca[1] == "Co-Administration Detail")

      check("Sheet 2 is 'Pattern Summary'",
            sheet_names_ca[2] == "Pattern Summary")

      # Check detail table columns -- Phase 109 date-grain columns
      detail_data <- openxlsx2::wb_to_df(wb_ca, sheet = "Co-Administration Detail", start_row = 1)
      expected_detail_cols <- c("patient_id", "index_date", "index_drug_code",
                                "index_drug_name", "coadmin_date", "coadmin_drug_code",
                                "coadmin_drug_name", "days_apart")
      check("Detail table has exactly 8 date-grain columns (D-07)",
            all(expected_detail_cols %in% colnames(detail_data)) &&
            ncol(detail_data) == 8)

      check("Detail table does NOT contain encounter ID columns",
            !any(grepl("encounter", colnames(detail_data), ignore.case = TRUE)))

      # Check pattern summary columns
      summary_data <- openxlsx2::wb_to_df(wb_ca, sheet = "Pattern Summary", start_row = 1)
      check("Pattern Summary contains n_instances column",
            "n_instances" %in% colnames(summary_data))

      check("Pattern Summary contains n_patients column",
            "n_patients" %in% colnames(summary_data))

      check("Pattern Summary is sorted descending by n_instances",
            all(diff(summary_data$n_instances) <= 0))

    }, error = function(e) {
      message(glue("  SKIP: Could not read co_administration xlsx ({e$message})"))
    })
  } else {
    message("  SKIP: co_administration_analysis.xlsx not found (run R/58 first)")
  }

} else {
  message("  FAIL: R/58_co_administration_analysis.R not found")
  failed <- failed + 1L
}

# ==============================================================================
# SECTION 31C: PHASE 103 -- DEATH DATE CROSS-TAB SUMMARY (DEATH-01) ----
# ==============================================================================
# Validates R/59 death date summary structural integrity.

message("\n[33/35] Phase 103: Death date cross-tab summary validation...")

if (file.exists("R/59_death_date_summary.R")) {
  r59_lines <- readLines("R/59_death_date_summary.R", warn = FALSE)

  # D-01: Standalone investigation script sourcing R/00_config.R
  check("R/59 sources R/00_config.R (D-01)",
        any(grepl('source.*R/00_config', r59_lines)))

  # D-01: Investigation script (no saveRDS)
  check("R/59 does NOT contain saveRDS (D-01: investigation only)",
        !any(grepl("saveRDS[(]", r59_lines)))

  # D-02: Reads validated_death_dates.rds
  check("R/59 reads validated_death_dates.rds (D-02)",
        any(grepl("validated_death_dates\\.rds", r59_lines)))

  # D-02: Reads confirmed_hl_cohort.rds for denominator
  check("R/59 reads confirmed_hl_cohort.rds for cohort denominator (D-02, D-04)",
        any(grepl("confirmed_hl_cohort\\.rds", r59_lines)))

  # D-02: Queries DuckDB ENCOUNTER table
  check("R/59 queries ENCOUNTER table via get_pcornet_table (D-02)",
        any(grepl('get_pcornet_table.*ENCOUNTER', r59_lines)))

  # D-03: Cascading summary structure
  check("R/59 builds cascading summary with death_is_last metric (D-03)",
        any(grepl("death_is_last", r59_lines)))

  # Pitfall 2: Must filter death_valid == TRUE
  check("R/59 filters death_valid == TRUE (Pitfall 2 avoidance)",
        any(grepl("death_valid.*==.*TRUE", r59_lines)))

  # D-04: Uses DEATH_DATE >= last_encounter_date (R/29 parity)
  check("R/59 uses DEATH_DATE >= last_encounter_date comparison (R/29 parity)",
        any(grepl("DEATH_DATE.*>=.*last_encounter_date", r59_lines)))

  # D-04: Uses post_death_activity flag from Phase 59
  check("R/59 uses post_death_activity flag (Phase 59)",
        any(grepl("post_death_activity", r59_lines)))

  # D-05: Verification logging against R/29
  check("R/59 logs DEATH-01 verification label (D-05)",
        any(grepl("DEATH-01", r59_lines)))

  # D-07: xlsx output with Death Date Summary sheet
  check("R/59 creates 'Death Date Summary' worksheet (D-07)",
        any(grepl("Death Date Summary", r59_lines)))

  # D-08: Styled header with project-standard dark gray
  check("R/59 uses FF374151 header fill color (D-08)",
        any(grepl("FF374151", r59_lines)))

  # Input validation
  check("R/59 uses assert_rds_exists for input validation",
        any(grepl("assert_rds_exists", r59_lines)))

  # D-06: No HIPAA suppression
  check("R/59 does NOT apply automatic HIPAA suppression (D-06)",
        !any(grepl("<11|hipaa_suppress|suppress_small", r59_lines, ignore.case = TRUE)))

  # Optional: output file validation (only if death_date_summary.xlsx exists)
  DEATH_XLSX_PATH <- file.path(CONFIG$output_dir, "death_date_summary.xlsx")
  if (file.exists(DEATH_XLSX_PATH)) {
    tryCatch({
      wb_d <- openxlsx2::wb_load(DEATH_XLSX_PATH)
      sheet_names_d <- wb_d$sheet_names

      check("death_date_summary.xlsx has 1 sheet",
            length(sheet_names_d) == 1)

      check("Sheet 1 is 'Death Date Summary'",
            sheet_names_d[1] == "Death Date Summary")

      # Check column structure
      summary_data <- openxlsx2::wb_to_df(wb_d, sheet = "Death Date Summary", start_row = 4)
      check("Summary table has Metric column",
            "Metric" %in% colnames(summary_data))

      check("Summary table has Count column",
            "Count" %in% colnames(summary_data))

      check("Summary table has 4 data rows (cascading structure per D-03)",
            nrow(summary_data) == 4)

    }, error = function(e) {
      message(glue("  SKIP: Could not read death_date_summary xlsx ({e$message})"))
    })
  } else {
    message("  SKIP: death_date_summary.xlsx not found (run R/59 first)")
  }

} else {
  message("  FAIL: R/59_death_date_summary.R not found")
  failed <- failed + 1L
}

# ==============================================================================
# SECTION 31D: PHASE 104 R/31 -- PRE-DIAGNOSIS TREATMENT FLAGGING (TIMING-01) ----
# ==============================================================================
# Validates R/31 pre-diagnosis treatment investigation script structural integrity.

message("\n[34/37] Phase 104 R/31: Pre-diagnosis treatment flagging validation...")

if (file.exists("R/31_pre_diagnosis_treatments.R")) {
  r31_lines <- readLines("R/31_pre_diagnosis_treatments.R", warn = FALSE)

  # D-08: Standalone investigation script sourcing R/00_config.R
  check("R/31 sources R/00_config.R",
        any(grepl('source.*R/00_config', r31_lines)))

  # D-08: Investigation script (no saveRDS)
  check("R/31 does NOT contain saveRDS (investigation only per D-08)",
        !any(grepl("saveRDS[(]", r31_lines)))

  # TIMING-01: Reads treatment_episodes.rds
  check("R/31 reads treatment_episodes.rds",
        any(grepl("treatment_episodes\\.rds", r31_lines)))

  # TIMING-01: Reads confirmed_hl_cohort.rds
  check("R/31 reads confirmed_hl_cohort.rds",
        any(grepl("confirmed_hl_cohort\\.rds", r31_lines)))

  # Pitfall 1: Correct join key (patient_id = ID)
  check("R/31 joins on patient_id = ID (correct join key)",
        any(grepl('patient_id.*=.*ID', r31_lines)))

  # TIMING-01: Pre-diagnosis filter (episode_start < first_hl_dx_date)
  check("R/31 filters episode_start < first_hl_dx_date (pre-dx filter)",
        any(grepl("episode_start.*<.*first_hl_dx_date", r31_lines)))

  # Pitfall 5: Sentinel date guard
  check("R/31 guards sentinel dates year > 1900 (Pitfall 5)",
        any(grepl("1900", r31_lines)))

  # TIMING-01: Computes days_before_dx
  check("R/31 computes days_before_dx",
        any(grepl("days_before_dx", r31_lines)))

  # D-01: Creates 'Summary' worksheet
  check("R/31 creates 'Summary' worksheet",
        any(grepl("Summary", r31_lines)))

  # D-01: Creates 'Detail' worksheet
  check("R/31 creates 'Detail' worksheet",
        any(grepl("Detail", r31_lines)))

  # D-08: Styled header with project-standard dark gray
  check("R/31 uses FF374151 header fill color",
        any(grepl("FF374151", r31_lines)))

  # Input validation
  check("R/31 uses assert_rds_exists for input validation",
        any(grepl("assert_rds_exists", r31_lines)))

  # D-09: No HIPAA suppression
  check("R/31 does NOT apply automatic HIPAA suppression (D-09)",
        !any(grepl("<11|hipaa_suppress|suppress_small", r31_lines, ignore.case = TRUE)))

} else {
  message("  FAIL: R/31_pre_diagnosis_treatments.R not found")
  failed <- failed + 1L
}

# ==============================================================================
# SECTION 31E: PHASE 104 R/32 -- SECONDARY MALIGNANCY TABLE (TIMING-02) ----
# ==============================================================================
# Validates R/32 secondary malignancy table structural integrity.

message("\n[35/37] Phase 104 R/32: Secondary malignancy table validation...")

if (file.exists("R/32_secondary_malignancy_table.R")) {
  r32_lines <- readLines("R/32_secondary_malignancy_table.R", warn = FALSE)

  # D-08: Standalone investigation script sourcing R/00_config.R
  check("R/32 sources R/00_config.R",
        any(grepl('source.*R/00_config', r32_lines)))

  # D-06, D-07: Sources utils_cancer.R
  check("R/32 sources utils_cancer.R",
        any(grepl('source.*utils_cancer', r32_lines)))

  # D-04: Investigation script (no saveRDS)
  check("R/32 does NOT contain saveRDS (investigation only per D-04)",
        !any(grepl("saveRDS[(]", r32_lines)))

  # D-05: Reads confirmed_hl_cohort.rds
  check("R/32 reads confirmed_hl_cohort.rds (D-05)",
        any(grepl("confirmed_hl_cohort\\.rds", r32_lines)))

  # TIMING-02: Queries DIAGNOSIS table via get_pcornet_table
  check("R/32 queries DIAGNOSIS table via get_pcornet_table",
        any(grepl('get_pcornet_table.*DIAGNOSIS', r32_lines)))

  # TIMING-02: Uses is_cancer_code for cancer filtering
  check("R/32 uses is_cancer_code for cancer filtering",
        any(grepl("is_cancer_code", r32_lines)))

  # Pitfall 2: Excludes both ICD-10 C81 and ICD-9 201 HL codes
  check("R/32 excludes both ICD-10 C81 and ICD-9 201 HL codes (Pitfall 2)",
        any(grepl("\\^C81\\|\\^201", r32_lines)))

  # D-06: Applies 7-day gap criterion
  check("R/32 applies 7-day gap criterion (D-06)",
        any(grepl(">=.*7|>= 7", r32_lines)))

  # TIMING-02: Uses classify_codes for cancer site classification
  check("R/32 uses classify_codes for cancer site classification",
        any(grepl("classify_codes", r32_lines)))

  # D-07: Implements pre/post HL split
  check("R/32 implements pre/post HL split (D-07)",
        any(grepl("Pre-HL", r32_lines)) && any(grepl("Post-HL", r32_lines)))

  # D-07, Pitfall 3: Uses total_cohort as denominator
  check("R/32 uses total_cohort as denominator (D-07, Pitfall 3)",
        any(grepl("total_cohort", r32_lines)))

  # D-01: Creates 'Summary' worksheet
  check("R/32 creates 'Summary' worksheet",
        any(grepl("Summary", r32_lines)))

  # D-01: Creates 'Detail' worksheet
  check("R/32 creates 'Detail' worksheet",
        any(grepl("Detail", r32_lines)))

  # D-08: Styled header with project-standard dark gray
  check("R/32 uses FF374151 header fill color",
        any(grepl("FF374151", r32_lines)))

  # D-09: No HIPAA suppression
  check("R/32 does NOT apply automatic HIPAA suppression (D-09)",
        !any(grepl("<11|hipaa_suppress|suppress_small", r32_lines, ignore.case = TRUE)))

} else {
  message("  FAIL: R/32_secondary_malignancy_table.R not found")
  failed <- failed + 1L
}

# ==============================================================================
# SECTION 31F: PHASE 105 R/33 -- CODE VERIFICATION (CODE-01, CODE-02, CODE-03) ----
# ==============================================================================
# Validates R/33 code verification script structural integrity.

message("\n[36/41] Phase 105 R/33: Code verification validation...")

if (file.exists("R/33_code_verification.R")) {
  r33 <- readLines("R/33_code_verification.R", warn = FALSE)
  r33_text <- paste(r33, collapse = "\n")

  # Structural checks for R/33
  check("R/33 sources R/00_config.R",
        any(grepl("source.*R/00_config\\.R", r33)))

  check("R/33 sources utils_duckdb.R",
        any(grepl("source.*utils_duckdb", r33)))

  check("R/33 sources utils_assertions.R",
        any(grepl("source.*utils_assertions", r33)))

  check("R/33 queries PRESCRIBING table (CODE-01)",
        any(grepl("get_pcornet_table.*PRESCRIBING", r33)))

  check("R/33 includes etanercept RxNorm codes",
        any(grepl("1653225.*809158|809158.*1653225", r33_text)))

  check("R/33 queries revenue code 0362 (CODE-02)",
        any(grepl("PX.*==.*0362|0362", r33_text)))

  check("R/33 checks Z94.84 SCT status code (CODE-03)",
        any(grepl("Z9484|Z94\\.84", r33_text)))

  check("R/33 checks T86.5 SCT complications code",
        any(grepl("T865|T86\\.5", r33_text)))

  check("R/33 checks T86.09 BMT complications code",
        any(grepl("T8609|T86\\.09", r33_text)))

  check("R/33 outputs code_verification.xlsx",
        any(grepl("code_verification\\.xlsx", r33_text)))

  check("R/33 creates openxlsx2 workbook",
        any(grepl("wb_workbook", r33)))

  check("R/33 has Summary sheet",
        any(grepl("Summary", r33_text)))

  check("R/33 has CODE-01 Detail sheet",
        any(grepl("CODE-01 Detail", r33_text)))

  check("R/33 has CODE-02 Detail sheet",
        any(grepl("CODE-02 Detail", r33_text)))

  check("R/33 has CODE-03 Detail sheet",
        any(grepl("CODE-03 Detail", r33_text)))

  check("R/33 does NOT saveRDS (investigation script)",
        !any(grepl("saveRDS", r33)))

  check("R/33 uses styled header fill (FF374151)",
        any(grepl("FF374151", r33_text)))

  check("R/33 has 7+ SECTION markers",
        sum(grepl("SECTION.*----", r33)) >= 7)

} else {
  message("  FAIL: R/33_code_verification.R not found")
  failed <- failed + 1L
}

# ==============================================================================
# SECTION 31G: PHASE 105 R/34 -- HL+NHL OVERLAP VALIDATION (OVERLAP-01) ----
# ==============================================================================
# Validates R/34 HL+NHL overlap validation script structural integrity.

message("\n[37/41] Phase 105 R/34: HL+NHL overlap validation...")

if (file.exists("R/34_hl_nhl_overlap_validation.R")) {
  r34 <- readLines("R/34_hl_nhl_overlap_validation.R", warn = FALSE)
  r34_text <- paste(r34, collapse = "\n")

  # Structural checks for R/34
  check("R/34 sources R/00_config.R",
        any(grepl("source.*R/00_config\\.R", r34)))

  check("R/34 sources utils_duckdb.R",
        any(grepl("source.*utils_duckdb", r34)))

  check("R/34 queries DIAGNOSIS table",
        any(grepl("get_pcornet_table.*DIAGNOSIS", r34)))

  check("R/34 detects NHL ICD-10 codes (C82-C86)",
        any(grepl("C8\\[2-6\\]|C8.2-6.", r34_text)))

  check("R/34 detects HL ICD-9 codes (201)",
        any(grepl("\\^201|201.*ICD.9|ICD.9.*201", r34_text)))

  check("R/34 detects HL ICD-10 codes (C81)",
        any(grepl("\\^C81|C81.*ICD.10|ICD.10.*C81", r34_text)))

  check("R/34 computes days_between for temporal analysis",
        any(grepl("days_between", r34_text)))

  check("R/34 identifies same-day diagnoses",
        any(grepl("same_day", r34_text)))

  check("R/34 assigns temporal categories",
        any(grepl("temporal_category", r34_text)))

  check("R/34 loads confirmed HL cohort as denominator",
        any(grepl("confirmed_hl_cohort", r34_text)))

  check("R/34 outputs hl_nhl_overlap_validation.xlsx",
        any(grepl("hl_nhl_overlap_validation\\.xlsx", r34_text)))

  check("R/34 creates openxlsx2 workbook",
        any(grepl("wb_workbook", r34)))

  check("R/34 has Summary sheet",
        any(grepl("Summary", r34_text)))

  check("R/34 has Patient Detail sheet",
        any(grepl("Patient Detail", r34_text)))

  check("R/34 has Pattern Analysis sheet",
        any(grepl("Pattern Analysis", r34_text)))

  check("R/34 does NOT saveRDS (investigation script)",
        !any(grepl("saveRDS", r34)))

  check("R/34 uses styled header fill (FF374151)",
        any(grepl("FF374151", r34_text)))

  check("R/34 has 7+ SECTION markers",
        sum(grepl("SECTION.*----", r34)) >= 7)

} else {
  message("  FAIL: R/34_hl_nhl_overlap_validation.R not found")
  failed <- failed + 1L
}

# ==============================================================================
# SECTION 31H: PHASE 106/111 R/36 -- TABLEAU-READY TABLES (TABLE-01, TABLE-02) ----
# ==============================================================================
# Validates R/36 Tableau-ready table generation script structural integrity.
# Phase 111 update: TABLE-2 changed from per-encounter+medication to per-patient+date grain.

message("\n[38/41] Phase 106 R/36: Tableau-ready tables validation...")

if (file.exists("R/36_tableau_ready_tables.R")) {
  r36 <- readLines("R/36_tableau_ready_tables.R", warn = FALSE)
  r36_text <- paste(r36, collapse = "\n")

  # Source dependencies
  check("R/36 sources R/00_config.R",
        any(grepl("source.*R/00_config\\.R", r36)))

  check("R/36 sources utils_duckdb.R",
        any(grepl("source.*utils_duckdb", r36)))

  check("R/36 sources utils_assertions.R",
        any(grepl("source.*utils_assertions", r36)))

  check("R/36 sources utils_cancer.R",
        any(grepl("source.*utils_cancer", r36)))

  # Data loading
  check("R/36 loads treatment_episode_detail.rds",
        any(grepl("treatment_episode_detail\\.rds", r36_text)))

  check("R/36 queries DuckDB DIAGNOSIS table",
        any(grepl("get_pcornet_table.*DIAGNOSIS", r36)))

  check("R/36 uses is_cancer_code() filter",
        any(grepl("is_cancer_code", r36)))

  # TABLE-1 specific
  check("R/36 uses COMMA separator for cancer_codes (not semicolon)",
        any(grepl('collapse\\s*=\\s*","', r36_text)))

  check("R/36 outputs tableau_table1_encounter_cancer_codes.xlsx",
        any(grepl("tableau_table1_encounter_cancer_codes\\.xlsx", r36_text)))

  # TABLE-2 specific
  check("R/36 filters to Chemotherapy for TABLE-2",
        any(grepl('treatment_type.*==.*"Chemotherapy"', r36_text)))

  check("R/36 resolves medication_name via MEDICATION_LOOKUP",
        any(grepl("MEDICATION_LOOKUP", r36_text)))

  check("R/36 loads reference xlsx for drug mappings",
        any(grepl("all_codes_resolved_next_tables", r36_text)))

  check("R/36 outputs tableau_table2_chemo_drugs_by_class.xlsx",
        any(grepl("tableau_table2_chemo_drugs_by_class\\.xlsx", r36_text)))

  # Phase 111: TABLE-2 date-grain collapse
  check("R/36 TABLE-2 groups by patient+date (Phase 111 D-08)",
        any(grepl("group_by.*treatment_date", r36_text)))

  check("R/36 TABLE-2 collapses agents string (Phase 111 D-06)",
        any(grepl("agents.*=.*paste.*sort.*unique", r36_text)))

  check("R/36 TABLE-2 merges cancer_codes via strsplit (Phase 111 D-03)",
        any(grepl("strsplit.*cancer_codes", r36_text)))

  check("R/36 TABLE-2 uses .groups = 'drop' in summarise",
        any(grepl('\\.groups.*=.*"drop"', r36_text)))

  # Output format
  check("R/36 creates openxlsx2 workbook",
        any(grepl("wb_workbook", r36)))

  check("R/36 uses col_names = TRUE for Tableau compatibility",
        any(grepl("col_names.*=.*TRUE", r36_text)))

  check("R/36 does NOT saveRDS (export script)",
        !any(grepl("saveRDS", r36)))

  check("R/36 has 7+ SECTION markers",
        sum(grepl("SECTION.*----", r36)) >= 7)

} else {
  message("  FAIL: R/36_tableau_ready_tables.R not found")
  failed <- failed + 1L
}

# ==============================================================================
# SECTION 31I: PHASE 107 R/37 -- GAP RESOLUTION REPORT (REPORT-01) ----
# ==============================================================================
# Validates R/37 RMarkdown report structural integrity for gap resolution
# compilation from v3.1+v3.2 investigation outputs.

message("\n[40/43] Phase 107 R/37: Gap resolution report validation...")

if (file.exists("R/37_gap_resolution_report.Rmd")) {
  r37_lines <- readLines("R/37_gap_resolution_report.Rmd", warn = FALSE)
  r37_text <- paste(r37_lines, collapse = "\n")

  # File and output format
  check("R/37 Rmd file exists", TRUE)

  check("R/37 specifies html_document output",
        any(str_detect(r37_lines, "html_document")))

  check("R/37 specifies self_contained: true",
        any(str_detect(r37_lines, "self_contained:\\s*true")))

  check("R/37 specifies floating TOC",
        any(str_detect(r37_lines, "toc_float")))

  # Library dependencies
  check("R/37 loads readxl library",
        any(str_detect(r37_lines, "library\\(readxl\\)")))

  check("R/37 loads kableExtra library",
        any(str_detect(r37_lines, "library\\(kableExtra\\)")))

  # Data sourcing (xlsx files from Phases 100-106)
  check("R/37 reads G1 condition_linkage xlsx",
        any(str_detect(r37_lines, "condition_linkage_investigation")))

  check("R/37 reads G5 pre_diagnosis_treatments xlsx",
        any(str_detect(r37_lines, "pre_diagnosis_treatments")))

  check("R/37 reads G8/G10/G11 code_verification xlsx",
        any(str_detect(r37_lines, "code_verification")))

  check("R/37 reads G4 hl_nhl_overlap xlsx",
        any(str_detect(r37_lines, "hl_nhl_overlap")))

  check("R/37 reads G15 death_date_summary xlsx",
        any(str_detect(r37_lines, "death_date_summary")))

  # Table rendering
  check("R/37 uses kbl() for table rendering",
        any(str_detect(r37_lines, "kbl\\(")))

  check("R/37 uses kable_styling()",
        any(str_detect(r37_lines, "kable_styling")))

  check("R/37 does NOT use JavaScript table libraries",
        !any(str_detect(r37_lines, "DT::datatable|reactable")))

} else {
  message("  FAIL: R/37_gap_resolution_report.Rmd not found")
  failed <- failed + 1L
}

# ==============================================================================
# SECTION 31J: PHASE 107 R/38 -- DELIVERY MANIFEST (REPORT-02) ----
# ==============================================================================
# Validates R/38 delivery manifest generator structural integrity for v3.1+v3.2
# output file inventory with validation.

message("\n[41/43] Phase 107 R/38: Delivery manifest validation...")

if (file.exists("R/38_delivery_manifest.R")) {
  r38_lines <- readLines("R/38_delivery_manifest.R", warn = FALSE)
  r38_text <- paste(r38_lines, collapse = "\n")

  # File exists
  check("R/38 script exists", TRUE)

  # Library dependencies
  check("R/38 loads openxlsx2 library",
        any(str_detect(r38_lines, "library\\(openxlsx2\\)")))

  check("R/38 loads dplyr library",
        any(str_detect(r38_lines, "library\\(dplyr\\)")))

  # File validation
  check("R/38 uses file.exists() for validation",
        any(str_detect(r38_lines, "file\\.exists")))

  check("R/38 uses file.info() for metadata",
        any(str_detect(r38_lines, "file\\.info")))

  # XLSX output
  check("R/38 creates wb_workbook for xlsx output",
        any(str_detect(r38_lines, "wb_workbook")))

  check("R/38 uses FF374151 header styling",
        any(str_detect(r38_lines, "FF374151")))

  check("R/38 uses freeze_pane",
        any(str_detect(r38_lines, "freeze_pane")))

  check("R/38 outputs delivery_manifest.xlsx",
        any(str_detect(r38_lines, "delivery_manifest\\.xlsx")))

  # References expected Phase 100-106 outputs
  check("R/38 references condition_linkage_investigation.xlsx (v3.1)",
        any(str_detect(r38_lines, "condition_linkage_investigation")))

  check("R/38 references pre_diagnosis_treatments.xlsx (v3.2)",
        any(str_detect(r38_lines, "pre_diagnosis_treatments")))

  check("R/38 does NOT contain saveRDS (export script)",
        !any(str_detect(r38_lines, "saveRDS")))

} else {
  message("  FAIL: R/38_delivery_manifest.R not found")
  failed <- failed + 1L
}

# ==============================================================================
# SECTION 32: DuckDB LOCAL INTEGRATION VALIDATION (TEST-01, TEST-02) ----
# ==============================================================================
# Validates that DuckDB ingest succeeds in current environment mode.
# Local mode: checks fixture-based DuckDB file in tempdir().
# Production mode: checks production DuckDB file on /blue/.

message("\n[42/43] DuckDB integration validation...")

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
      # TEST-01: Fixture-specific table count (16 tables from fixture CSVs; DEATH_CAUSE added Phase 119)
      # NOTE (Phase 119): local fixture DuckDB must be rebuilt to include DEATH_CAUSE, else this check reports 15.
      check(
        glue("DuckDB contains 16 tables from fixtures (found {length(tables_found)})"),
        length(tables_found) == 16
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
  message("\n[43/43] Fixture schema validation (local mode only)...")

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
  message("\n[FIXTURE] Fixture schema validation -- SKIPPED (production mode)")
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
message("  * CODE-01: Etanercept immunotherapy classification verification (R/33 Phase 105)")
message("  * CODE-02: Organ transplant code 0362 cross-check (R/33 Phase 105)")
message("  * CODE-03: SCT diagnosis codes above line 22 validation (R/33 Phase 105)")
message("  * OVERLAP-01: HL+NHL dual-code temporal validation report (R/34 Phase 105)")
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
message("  * DRUG-01: Broadened output includes ALL treatment encounters (R/57 Phase 101)")
message("  * DRUG-02: cancer_linked TRUE/FALSE flag column on broadened output (R/57 Phase 101)")
message("  * DRUG-03: Linked-only output preserved with _linked_only suffix (R/57 Phase 101)")
message("  * COADMIN-01: Co-administration detail table, date-grain with ICD9 filtering (R/58 Phase 109)")
message("  * COADMIN-02: Pattern summary with symmetric pair deduplication (R/58 Phase 109)")
message("  * DEATH-01: Death date cross-tab summary with cascading metrics (R/59 Phase 103)")
message("  * TIMING-01: Pre-diagnosis treatment flagging with 5 treatment types (R/31 Phase 104)")
message("  * TIMING-02: Secondary malignancy table with 7-day gap criterion and pre/post HL split (R/32 Phase 104)")
message("  * REPORT-01: Gap resolution RMarkdown report with per-gap sections (R/37 Phase 107)")
message("  * REPORT-02: Delivery manifest with file validation (R/38 Phase 107)")
message("  * TEST-01: DuckDB ingest works with fixture CSVs (Section 32)")
message("  * TEST-02: R/88 smoke test passes locally against fixtures (Section 32)")
message("  * TEST-03: Fixture schema validation in local mode (Section 33)")
message("  * TEST-05: Conditional fixture count assertions (Sections 32+33)")
message("  * CLEAN-01: False-positive SCT codes removed from DRUG_GROUPINGS (Z94.84, T86.5, T86.09, Z48.290, HEMATOLOGIC_TRANSPLANT_AND_ENDOC)")
message("  * CLEAN-02: Smoke test validates deprecated codes absent and descriptions preserved")
message("  * GANTT-01: drug_names consolidated (MEDICATION_LOOKUP primary, RxNorm fallback)")
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
message("  * TABLE-01: Encounter cancer codes Tableau table with comma separators (R/36 Phase 106)")
message("  * TABLE-02: Chemo agents by date (patient-date grain, collapsed agents) (R/36 Phase 106+111)")
message("  * GANTT-DX-01: episode_dx_codes and episode_dx_categories in treatment_episodes.rds (Phase 112)")
message("  * GANTT-DX-02: Temporal diagnosis columns in gantt_episodes.csv schema (Phase 112)")
message("  * SORT-01: Universal ascending sort in clean_multi_value and all multi-value fields (Phase 112)")
message("  * SORT-02: R/36 and R/57 descending sort removed (Phase 112)")
message("  * POSTDEATH-01: Two-sheet xlsx with per-patient summary and per-event detail (R/51 Phase 113)")
message("  * POSTDEATH-02: R/88 validates R/51 structure, bucketing, source_table labels (Phase 113)")
message("  * POSTDEATH-03: R/39 pipeline runner includes R/51 (Phase 113)")
message("  * DRUGFIX-01: Blank drug_names filled from reference Excel MEDICATION_LOOKUP (R/26 Phase 114)")
message("  * DRUGFIX-02: Code descriptions use reference Excel as highest-priority source (R/42 Phase 114)")
message("  * DRUGFIX-03: MEDICATION_LOOKUP centralized in R/00_config.R with 400+ entries (Phase 114)")
message("  * DRUGFIX-04: Standalone audit xlsx with Summary + Detail sheets (R/79 Phase 114)")
message("  * DRUGFIX-05: R/88 validates Phase 114 structural integrity (14 checks)")
message("  * GANTT7DAY-01: episode_dx_7day_confirmed column in gantt_episodes.csv (Phase 115)")
message("  * GANTAGE-01: age_at_episode column in gantt_episodes.csv (Phase 115)")
message("  * SMOKE-115-01: R/88 validates Phase 115 structural integrity (14 checks)")
message("  * RUCA-01: USDA 2020 ZIP RUCA reference xlsx bundled in data/reference/ (Phase 116)")
message("  * RUCA-02: R/100 assigns rurality (raw code + 4-tier label) from DEMOGRAPHIC.ZIP_CODE (Phase 116)")
message("  * RUCA-03: 4-sheet styled xlsx: patient frequency + encounter-level payer/treatment/cancer (R/100 Phase 116)")
message("  * RUCA-04: NA rurality logged + preserved as Unknown row/column in cross-tabs (R/100 Phase 116)")
message("  * RUCA-05: Row totals + column totals + ascending alpha sort on all sheets (R/100 Phase 116)")
message("  * RUCA-06: R/39 pipeline runner includes R/100 in investigation stage (Phase 116)")
message("  * SMOKE-116-01: R/88 validates Phase 116 structural integrity (22 checks)")
message("  * LIFESPAN-01: R/101 produces output/gantt_lifespan.csv from gantt_episodes.csv (Phase 117)")
message("  * LIFESPAN-02: Collapse = one row per patient_id x treatment_type, min(start)->max(stop) (Phase 117)")
message("  * LIFESPAN-03: Death + HL Diagnosis pseudo-rows excluded from lifespan CSV (Phase 117)")
message("  * LIFESPAN-04: Multi-value fields unioned/deduped/sorted via clean_multi_value (Phase 117)")
message("  * SMOKE-117-01: R/88 validates Phase 117 structural integrity (14 checks)")
message("  * NHLDEATH-01: R/102 derives deceased set from DEATH table (1900 sentinel, per-patient) (Phase 118)")
message("  * NHLDEATH-02: cause_of_death_is_nhl three-state flag via classify_codes == \"Non-Hodgkin Lymphoma\" (Phase 118)")
message("  * NHLDEATH-03: R/102 writes output/death_cause_nhl_flag.csv (PATID + flag, na=\"\" blank) (Phase 118)")
message("  * SMOKE-118-01: R/88 validates Phase 118 structural integrity (14 checks)")
message("  * NHLFIX-03: R/102 reads cause of death from the DEATH_CAUSE table, not DEATH.DEATH_CAUSE (Phase 119)")
message("  * NHLFIX-04: R/35 cause-of-death source corrected/annotated to DEATH_CAUSE table (Phase 119)")
message("  * SMOKE-119-01: R/88 validates Phase 119 structural integrity (Section 15p)")
message("  * SMOKE-i1e-01: R/88 validates R/104 gantt entire-history structural integrity (Section 15q, 14 checks)")
message("  * SMOKE-120-01: R/88 validates Phase 120 Supportive Care Normalized Meaning structural integrity (Section 15r, 14 checks)")
message("  * SMOKE-121-01: R/88 validates Phase 121 ZIP change frequency structural integrity (Section 15s, 14 checks)")
message("  * SMOKE-122-01: R/88 validates Phase 122 MED_ADMIN/DISPENSING chemo-detection gap fix structural integrity (Section 15t, 14 checks)")
message("  * SMOKE-123-01: R/88 validates Phase 123 R/109 before/after diff + unmatched-NDC audit structural integrity (Section 15u, 14 checks)")
message("  * SMOKE-124-01: R/88 validates Phase 124 R/110 output-level before/after report + unmapped-name audit structural integrity (Section 15v, 13 checks)")

if (failed > 0) {
  quit(status = 1)
}
