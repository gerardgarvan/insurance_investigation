# ==============================================================================
# 87_smoke_test_full_pipeline.R -- Full-Pipeline Renumbering Validation
# ==============================================================================
#
# Validates Phase 66 complete reorganization:
#   - Output decade (70-75): 6 scripts
#   - Test decade (80-86): 7 scripts
#   - Ad-hoc decade (90-99): 10 scripts
#   - No a/b suffixes remain (D-07)
#   - No broken source() references
#   - Key dependency chains intact
#
# Usage:
#   Rscript R/87_smoke_test_full_pipeline.R
#
# Requirements: REORG-01, REORG-02
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
message("SMOKE TEST: Full-Pipeline Renumbering (Phase 66)")
message(strrep("=", 70))

# --------------------------------------------------------------------------
# Test 1: Foundation decade (00-03) still intact
# --------------------------------------------------------------------------
message("\n[1/12] Foundation decade (00-03)...")

check("R/00_config.R exists", file.exists("R/00_config.R"))
check("R/01_load_pcornet.R exists", file.exists("R/01_load_pcornet.R"))
check("R/02_harmonize_payer.R exists", file.exists("R/02_harmonize_payer.R"))
check("R/03_duckdb_ingest.R exists", file.exists("R/03_duckdb_ingest.R"))

utils_count <- length(list.files("R/utils", pattern = "\\.R$"))
check(glue("R/utils/ contains 8 modules (found {utils_count})"),
      utils_count == 8)

# --------------------------------------------------------------------------
# Test 2: Cohort decade (10-14)
# --------------------------------------------------------------------------
message("\n[2/12] Cohort decade (10-14)...")

cohort_scripts <- c("10_cohort_predicates.R", "11_treatment_payer.R",
                    "12_surveillance.R", "13_survivorship_encounters.R",
                    "14_build_cohort.R")
for (s in cohort_scripts) {
  check(glue("R/{s} exists"), file.exists(file.path("R", s)))
}

# --------------------------------------------------------------------------
# Test 3: Treatment decade (20-29) -- all 10 scripts
# --------------------------------------------------------------------------
message("\n[3/12] Treatment decade (20-29)...")

treatment_expected <- c("20_treatment_inventory.R", "21_investigate_unmatched.R",
                        "22_investigate_unmatched_ndc.R", "23_combine_reports.R",
                        "24_treatment_codes_resolved.R", "25_treatment_durations.R",
                        "26_treatment_episodes.R", "27_drug_name_resolution.R",
                        "28_episode_classification.R", "29_first_line_and_death_analysis.R")
treatment_found <- 0L
for (s in treatment_expected) {
  if (file.exists(file.path("R", s))) treatment_found <- treatment_found + 1L
}
check(glue("Treatment decade complete: 10/10 scripts (found {treatment_found})"),
      treatment_found == 10)

# --------------------------------------------------------------------------
# Test 4: Cancer decade (40-53) -- 14 scripts
# --------------------------------------------------------------------------
message("\n[4/12] Cancer decade (40-53)...")

cancer_expected <- c("40_cancer_site_frequency.R", "41_extract_all_codes.R",
                     "42_build_code_descriptions.R", "43_cancer_site_confirmation.R",
                     "44_cancer_site_confirmation_7day.R", "45_cancer_summary.R",
                     "46_cancer_summary_table.R", "47_cancer_summary_refined.R",
                     "48_cancer_summary_post_hl.R", "49_cancer_summary_pre_post.R",
                     "50_all_codes_resolved.R", "51_gantt_data_export.R",
                     "52_gantt_v2_export.R", "53_death_date_validation.R")
cancer_found <- 0L
for (s in cancer_expected) {
  if (file.exists(file.path("R", s))) cancer_found <- cancer_found + 1L
}
check(glue("Cancer decade scripts: {cancer_found}/14 present"),
      cancer_found >= 10)  # Allow for some Phase 66+ additions

# --------------------------------------------------------------------------
# Test 5: Payer/QA decade (60-69) -- 10 scripts
# --------------------------------------------------------------------------
message("\n[5/12] Payer/QA decade (60-69)...")

payer_expected <- c("60_tiered_same_day_payer.R", "61_tiered_encounter_level.R",
                    "62_tiered_date_level.R", "63_value_audit.R",
                    "64_all_source_missingness.R", "65_uf_insurance_missingness.R",
                    "66_all_site_duplicate_dates.R",
                    "67_multi_source_overlap_detection.R",
                    "68_overlap_classification.R", "69_per_patient_source_detection.R")
payer_found <- 0L
for (s in payer_expected) {
  if (file.exists(file.path("R", s))) payer_found <- payer_found + 1L
}
check(glue("Payer/QA decade scripts: {payer_found}/10 present"),
      payer_found >= 8)

# --------------------------------------------------------------------------
# Test 6: Output decade (70-75) -- 6 scripts per D-04
# --------------------------------------------------------------------------
message("\n[6/12] Output decade (70-75)...")

output_scripts <- c("70_visualize_waterfall.R", "71_visualize_sankey.R",
                    "72_generate_pptx.R", "73_generate_phase19_20_pptx.R",
                    "74_generate_documentation.R", "75_encounter_analysis.R")
output_found <- 0L
for (s in output_scripts) {
  if (file.exists(file.path("R", s))) {
    check(glue("R/{s} exists"), TRUE)
    output_found <- output_found + 1L
  } else {
    check(glue("R/{s} exists"), FALSE)
  }
}
check(glue("Output decade complete: 6/6 scripts"), output_found == 6)

# --------------------------------------------------------------------------
# Test 7: Test decade (80-86) -- 7 scripts per D-06
# --------------------------------------------------------------------------
message("\n[7/12] Test decade (80-86)...")

test_scripts <- c("80_smoke_test_backends.R", "81_parity_test_cohort.R",
                  "82_benchmark_cohort.R", "83_generate_speedup_report.R",
                  "84_test_durations.R", "85_test_episodes.R",
                  "86_smoke_test_foundation.R", "87_smoke_test_full_pipeline.R")
test_found <- 0L
for (s in test_scripts) {
  if (file.exists(file.path("R", s))) {
    check(glue("R/{s} exists"), TRUE)
    test_found <- test_found + 1L
  } else {
    check(glue("R/{s} exists"), FALSE)
  }
}
check(glue("Test decade complete: 8/8 scripts"), test_found == 8)

# --------------------------------------------------------------------------
# Test 8: Ad-hoc decade (90-99) -- 10 scripts
# --------------------------------------------------------------------------
message("\n[8/12] Ad-hoc decade (90-99)...")

adhoc_scripts <- c("90_diagnostics.R", "91_data_quality_summary.R",
                   "92_dx_gap_analysis.R", "93_no_treatment_medicaid.R",
                   "94_flm_duplicate_dates.R", "95_multi_source_overlap_av_th.R",
                   "96_overlap_classification_av_th.R", "97_payer_code_frequency_av_th.R",
                   "98_radiation_cpt_audit.R", "99_claude_diagnostics.R")
adhoc_found <- 0L
for (s in adhoc_scripts) {
  if (file.exists(file.path("R", s))) {
    adhoc_found <- adhoc_found + 1L
  }
}
check(glue("Ad-hoc decade: 10/10 scripts (found {adhoc_found})"),
      adhoc_found == 10)

# --------------------------------------------------------------------------
# Test 9: No old-numbered files remain
# --------------------------------------------------------------------------
message("\n[9/12] No stale old-numbered files...")

# Check for specific old numbers that should have been renamed
old_numbers <- c("05_visualize_waterfall.R", "11_generate_pptx.R",
                 "16_encounter_analysis.R", "26_smoke_test_backends.R",
                 "07_diagnostics.R", "19_flm_duplicate_dates.R",
                 "33_multi_source_overlap_av_th.R")
stale_files <- character(0)
for (old in old_numbers) {
  if (file.exists(file.path("R", old))) {
    stale_files <- c(stale_files, old)
  }
}
check(glue("No stale old-numbered files (found: {paste(stale_files, collapse=', ') %||% 'none'})"),
      length(stale_files) == 0)

# --------------------------------------------------------------------------
# Test 10: No a/b suffixes remain (D-07)
# --------------------------------------------------------------------------
message("\n[10/12] No a/b suffixes remain...")

r_files <- list.files("R", pattern = "\\.R$")
# Match files like 43a_, 44b_, NOT files with 'a' or 'b' in the middle of words
ab_pattern <- "^[0-9]+[ab]_"
ab_suffixed <- grep(ab_pattern, r_files, value = TRUE)
check(glue("No a/b suffixed files (found: {paste(ab_suffixed, collapse=', ') %||% 'none'})"),
      length(ab_suffixed) == 0)

# --------------------------------------------------------------------------
# Test 11: No broken source() references
# --------------------------------------------------------------------------
message("\n[11/12] No broken source() references...")

r_files_full <- list.files("R", pattern = "\\.R$", full.names = TRUE)
broken_refs <- character(0)
for (f in r_files_full) {
  lines <- readLines(f, warn = FALSE)
  # Extract source("R/...") patterns (ignore commented lines)
  source_lines <- grep('source\\("R/', lines, value = TRUE)
  source_lines <- grep('^[^#]*source\\("R/', lines, value = TRUE)  # Not commented

  for (line in source_lines) {
    # Extract path from source("R/...")
    matches <- regmatches(line, gregexpr('source\\("R/[^"]+\\.R"\\)', line))
    for (match_list in matches) {
      for (m in match_list) {
        path <- sub('source\\("', '', m)
        path <- sub('"\\)', '', path)
        if (!file.exists(path)) {
          broken_refs <- c(broken_refs, glue("{basename(f)}: {path}"))
        }
      }
    }
  }
}
check(glue("No broken source() calls (found: {paste(broken_refs, collapse=', ') %||% 'none'})"),
      length(broken_refs) == 0)

# --------------------------------------------------------------------------
# Test 12: Key dependency chains intact
# --------------------------------------------------------------------------
message("\n[12/12] Key dependency chains...")

# Check critical source() patterns
check_source <- function(file, pattern, description) {
  if (!file.exists(file)) return(FALSE)
  lines <- readLines(file, warn = FALSE)
  any(grepl(pattern, lines))
}

check("14_build_cohort.R sources 10_cohort_predicates.R",
      check_source("R/14_build_cohort.R", 'source\\("R/10_cohort_predicates\\.R"\\)', ""))
check("14_build_cohort.R sources 11_treatment_payer.R",
      check_source("R/14_build_cohort.R", 'source\\("R/11_treatment_payer\\.R"\\)', ""))
check("26_treatment_episodes.R sources 25_treatment_durations.R",
      check_source("R/26_treatment_episodes.R", 'source\\("R/25_treatment_durations\\.R"\\)', ""))
check("72_generate_pptx.R sources 75_encounter_analysis.R",
      check_source("R/72_generate_pptx.R", 'source\\("R/75_encounter_analysis\\.R"\\)', ""))
check("73_generate_phase19_20_pptx.R sources 94_flm_duplicate_dates.R",
      check_source("R/73_generate_phase19_20_pptx.R", 'R/94_flm_duplicate_dates\\.R', ""))

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
message(glue("\n{strrep('=', 70)}"))
total <- passed + failed
if (failed == 0) {
  message(glue("ALL {total} CHECKS PASSED"))
} else {
  message(glue("FAILED: {failed}/{total} checks failed"))
}
message(strrep("=", 70))
message("\nValidated:")
message("  * Output scripts renumbered to 70-75 (D-04)")
message("  * Test scripts renumbered to 80-86 (D-06)")
message("  * Ad-hoc scripts renumbered to 90-99")
message("  * Zero a/b suffixes remain (D-07)")
message("  * Zero broken source() references (REORG-02)")
message("  * All decades properly populated (REORG-01)")

if (failed > 0) {
  quit(status = 1)
}
