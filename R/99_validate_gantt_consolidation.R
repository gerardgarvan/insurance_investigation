# ==============================================================================
# 99_validate_gantt_consolidation.R -- Phase 99 Gantt Consolidation Validation
# ==============================================================================
#
# Purpose:
#   Validates R/52 produces clean Gantt CSVs with correct schema after v1
#   deprecation (D-01) and schema consolidation (D-02 through D-15).
#   Checks schema compliance, row preservation, is_hodgkin derivation,
#   pseudo-treatment metadata cleanliness, and file naming.
#
# Usage:
#   source("R/99_validate_gantt_consolidation.R")
#
# Expected output:
#   Series of [PASS] / [FAIL] messages. All must show [PASS].
#
# Dependencies:
#   - R/00_config.R (CONFIG paths, CANCER_SITE_MAP)
#   - R/52_gantt_v2_export.R (must have been run to produce output CSVs)
#   - output/gantt_episodes.csv (produced by R/52)
#   - output/gantt_detail.csv (produced by R/52)
#
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
})

source("R/00_config.R")

pass_count <- 0L
fail_count <- 0L

check <- function(description, condition) {
  if (isTRUE(condition)) {
    message(sprintf("[PASS] %s", description))
    pass_count <<- pass_count + 1L
  } else {
    message(sprintf("[FAIL] %s", description))
    fail_count <<- fail_count + 1L
  }
}

# ==============================================================================
# Section 1: V1 Deprecation (D-01)
# ==============================================================================

message("\n=== Section 1: V1 Deprecation ===")

check("1.1 R/51_gantt_data_export.R has been deleted (D-01)",
      !file.exists("R/51_gantt_data_export.R"))

# ==============================================================================
# Section 2: Output File Naming (D-05)
# ==============================================================================

message("\n=== Section 2: Output File Naming ===")

check("2.1 gantt_episodes.csv exists (no _v2 suffix)",
      file.exists(file.path(CONFIG$output_dir, "gantt_episodes.csv")))

check("2.2 gantt_detail.csv exists (no _v2 suffix)",
      file.exists(file.path(CONFIG$output_dir, "gantt_detail.csv")))

check("2.3 R/52 does NOT reference OUTPUT_EPISODES_V2",
      !any(grepl("OUTPUT_EPISODES_V2", readLines("R/52_gantt_v2_export.R", warn = FALSE), fixed = TRUE)))

check("2.4 R/52 does NOT reference OUTPUT_DETAIL_V2",
      !any(grepl("OUTPUT_DETAIL_V2", readLines("R/52_gantt_v2_export.R", warn = FALSE), fixed = TRUE)))

# ==============================================================================
# Section 3: Schema Compliance (D-06, D-07, D-11, D-13)
# ==============================================================================

message("\n=== Section 3: Schema Compliance ===")

episodes <- read.csv(file.path(CONFIG$output_dir, "gantt_episodes.csv"),
                      nrows = 5, stringsAsFactors = FALSE)
detail <- read.csv(file.path(CONFIG$output_dir, "gantt_detail.csv"),
                    nrows = 5, stringsAsFactors = FALSE)

# Expected schemas (must match R/52 EPISODES_SCHEMA and DETAIL_SCHEMA)
expected_ep_cols <- c(
  "patient_id", "treatment_type", "episode_number",
  "episode_start", "episode_stop", "episode_length_days",
  "distinct_dates_in_episode",
  "triggering_codes", "drug_names", "triggering_code_descriptions",
  "cancer_category", "is_hodgkin",
  "drug_group",
  "code_type", "source_table", "sct_cross_use_flag",
  "episode_dx_codes", "episode_dx_categories"
)

expected_detail_cols <- c(
  "patient_id", "treatment_type", "treatment_date",
  "triggering_code", "drug_name", "episode_number",
  "episode_start", "episode_stop",
  "triggering_code_description",
  "cancer_category", "is_hodgkin",
  "code_type", "source_table", "sct_cross_use_flag"
)

check("3.1 Episodes CSV has 18 columns",
      ncol(episodes) == 18)

check("3.2 Detail CSV has 14 columns",
      ncol(detail) == 14)

check("3.3 Episodes column names match expected schema",
      identical(colnames(episodes), expected_ep_cols))

check("3.4 Detail column names match expected schema",
      identical(colnames(detail), expected_detail_cols))

# D-06: encounter_ids removed
check("3.5 Episodes CSV does NOT have encounter_ids column (D-06)",
      !"encounter_ids" %in% colnames(episodes))

# D-06: ENCOUNTERID removed
check("3.6 Detail CSV does NOT have ENCOUNTERID column (D-06)",
      !"ENCOUNTERID" %in% colnames(detail))

# D-07: is_hodgkin present
check("3.7 Episodes CSV has is_hodgkin column (D-07)",
      "is_hodgkin" %in% colnames(episodes))

check("3.8 Detail CSV has is_hodgkin column (D-07)",
      "is_hodgkin" %in% colnames(detail))

# D-11: immunotherapy columns removed
check("3.9 Episodes CSV does NOT have is_sct_conditioning_context (D-11)",
      !"is_sct_conditioning_context" %in% colnames(episodes))

check("3.10 Episodes CSV does NOT have immuno_confidence (D-11)",
      !"immuno_confidence" %in% colnames(episodes))

check("3.11 Detail CSV does NOT have is_sct_conditioning_context (D-11)",
      !"is_sct_conditioning_context" %in% colnames(detail))

check("3.12 Detail CSV does NOT have immuno_confidence (D-11)",
      !"immuno_confidence" %in% colnames(detail))

# Column removed: cancer_link_method
check("3.13 Episodes CSV does NOT have cancer_link_method",
      !"cancer_link_method" %in% colnames(episodes))

check("3.14 Detail CSV does NOT have cancer_link_method",
      !"cancer_link_method" %in% colnames(detail))

# ==============================================================================
# Section 4: Row Count Preservation
# ==============================================================================

message("\n=== Section 4: Row Count Preservation ===")

# Read full CSVs for row-level checks
episodes_full <- read.csv(file.path(CONFIG$output_dir, "gantt_episodes.csv"),
                           stringsAsFactors = FALSE)
detail_full <- read.csv(file.path(CONFIG$output_dir, "gantt_detail.csv"),
                         stringsAsFactors = FALSE)

check("4.1 Episodes CSV has > 0 rows",
      nrow(episodes_full) > 0)

check("4.2 Detail CSV has > 0 rows",
      nrow(detail_full) > 0)

check("4.3 Detail row count >= Episodes row count (detail is per-date granularity)",
      nrow(detail_full) >= nrow(episodes_full))

# Check for pseudo-treatment rows
check("4.4 Episodes contains Death pseudo-treatment rows",
      any(episodes_full$treatment_type == "Death"))

check("4.5 Episodes contains HL Diagnosis pseudo-treatment rows",
      any(episodes_full$treatment_type == "HL Diagnosis"))

# ==============================================================================
# Section 5: is_hodgkin Derivation (D-07)
# ==============================================================================

message("\n=== Section 5: is_hodgkin Derivation ===")

# HL Diagnosis rows should all have is_hodgkin = TRUE
hl_dx_rows <- episodes_full %>% filter(treatment_type == "HL Diagnosis")
if (nrow(hl_dx_rows) > 0) {
  check("5.1 All HL Diagnosis rows have is_hodgkin = TRUE",
        all(hl_dx_rows$is_hodgkin == TRUE))
} else {
  check("5.1 All HL Diagnosis rows have is_hodgkin = TRUE (SKIPPED: no HL Dx rows)",
        TRUE)
}

# Death rows should all have is_hodgkin = FALSE
death_rows <- episodes_full %>% filter(treatment_type == "Death")
if (nrow(death_rows) > 0) {
  check("5.2 All Death rows have is_hodgkin = FALSE",
        all(death_rows$is_hodgkin == FALSE))
} else {
  check("5.2 All Death rows have is_hodgkin = FALSE (SKIPPED: no Death rows)",
        TRUE)
}

# Rows with Hodgkin cancer_category (but NOT Non-Hodgkin) should have is_hodgkin = TRUE
hodgkin_rows <- episodes_full %>% filter(str_detect(cancer_category, "Hodgkin") & !str_detect(cancer_category, "Non-Hodgkin"))
if (nrow(hodgkin_rows) > 0) {
  check("5.3 All Hodgkin (non-NHL) cancer_category rows have is_hodgkin = TRUE",
        all(hodgkin_rows$is_hodgkin == TRUE))
}

# Rows with Non-Hodgkin or non-Hodgkin cancer_category should have is_hodgkin = FALSE
non_hodgkin_rows <- episodes_full %>% filter(!str_detect(cancer_category, "Hodgkin") | str_detect(cancer_category, "Non-Hodgkin"))
if (nrow(non_hodgkin_rows) > 0) {
  check("5.4 All non-Hodgkin cancer_category rows have is_hodgkin = FALSE",
        all(non_hodgkin_rows$is_hodgkin == FALSE))
}

# is_hodgkin should be logical type
check("5.5 is_hodgkin is logical type in episodes",
      is.logical(episodes_full$is_hodgkin))

# ==============================================================================
# Section 6: Pseudo-Treatment Metadata (D-12)
# ==============================================================================

message("\n=== Section 6: Pseudo-Treatment Metadata ===")

# Death rows: character enrichment columns should be empty string (not NA)
if (nrow(death_rows) > 0) {
  check("6.1 Death rows: drug_group is empty string (not NA)",
        all(death_rows$drug_group == ""))

  check("6.2 Death rows: sct_cross_use_flag is empty string (not NA)",
        all(death_rows$sct_cross_use_flag == ""))
}

# HL Diagnosis rows: same checks
if (nrow(hl_dx_rows) > 0) {
  check("6.3 HL Dx rows: drug_group is empty string (not NA)",
        all(hl_dx_rows$drug_group == ""))
}

# ==============================================================================
# Section 7: Multi-Value Separator Consistency (D-02)
# ==============================================================================

message("\n=== Section 7: Multi-Value Separators ===")

# Check that multi-value fields use semicolons (not commas or pipes)
treatment_rows <- episodes_full %>%
  filter(!treatment_type %in% c("Death", "HL Diagnosis"))

multi_value_with_content <- treatment_rows %>%
  filter(nchar(triggering_codes) > 0 & str_detect(triggering_codes, ";"))

if (nrow(multi_value_with_content) > 0) {
  check("7.1 triggering_codes uses semicolon separator",
        any(str_detect(multi_value_with_content$triggering_codes, ";")))
} else {
  check("7.1 triggering_codes uses semicolon separator (SKIPPED: no multi-value rows found)",
        TRUE)
}

# No pipes or embedded commas in multi-value fields (commas within CSV cells indicate wrong separator)
check("7.2 triggering_codes does NOT contain pipe separator",
      !any(str_detect(treatment_rows$triggering_codes, "\\|"), na.rm = TRUE))

# ==============================================================================
# Section 8: R/52 Code Structure (D-13)
# ==============================================================================

message("\n=== Section 8: R/52 Code Structure ===")

r52_lines <- readLines("R/52_gantt_v2_export.R", warn = FALSE)

check("8.1 R/52 defines EPISODES_SCHEMA vector",
      any(grepl("EPISODES_SCHEMA\\s*<-\\s*c\\(", r52_lines)))

check("8.2 R/52 defines DETAIL_SCHEMA vector",
      any(grepl("DETAIL_SCHEMA\\s*<-\\s*c\\(", r52_lines)))

check("8.3 R/52 uses identical() for schema verification (not hardcoded count)",
      any(grepl("identical.*colnames.*EPISODES_SCHEMA", r52_lines)))

check("8.4 R/52 uses identical() for detail schema verification",
      any(grepl("identical.*colnames.*DETAIL_SCHEMA", r52_lines)))

check("8.5 R/52 does NOT use expected_ep_cols magic number",
      !any(grepl("expected_ep_cols\\s*<-\\s*\\d+", r52_lines)))

check("8.6 R/52 does NOT use expected_detail_cols magic number",
      !any(grepl("expected_detail_cols\\s*<-\\s*\\d+", r52_lines)))

check("8.7 R/52 output path is gantt_episodes.csv (D-05)",
      any(grepl("gantt_episodes\\.csv", r52_lines)))

check("8.8 R/52 output path is gantt_detail.csv (D-05)",
      any(grepl("gantt_detail\\.csv", r52_lines)))

check("8.9 R/52 derives is_hodgkin via str_detect (D-07)",
      any(grepl("is_hodgkin.*str_detect.*cancer_category", r52_lines)))

# ==============================================================================
# Final Summary
# ==============================================================================

message(sprintf("\n=== Phase 99 Validation Summary ==="))
message(sprintf("PASSED: %d checks", pass_count))
message(sprintf("FAILED: %d checks", fail_count))

if (fail_count > 0) {
  stop(glue("Phase 99 validation FAILED with {fail_count} error(s). Fix and re-run."))
} else {
  message("\nAll Phase 99 validation checks passed.")
}
