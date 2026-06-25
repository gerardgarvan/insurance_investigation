# ==============================================================================
# 79_drug_name_consistency_audit.R -- Drug Name Consistency Audit
# ==============================================================================
# Purpose:     Standalone investigation comparing pipeline drug_names and
#              triggering_code_descriptions against the canonical treatment
#              reference Excel (all_codes_resolved_next_tables_v2.1.xlsx).
#              Produces a two-sheet styled xlsx documenting blanks filled
#              and discrepancies identified.
#
# Inputs:      cache/outputs/treatment_episode_detail.rds
#              cache/outputs/code_descriptions.rds
#              R/00_config.R (MEDICATION_LOOKUP)
#
# Outputs:     output/drug_name_consistency_audit.xlsx
#
# Dependencies: R/00_config.R
#
# Requirements: Phase 114 — D-07 (before/after audit xlsx), D-08 (standalone script)
#
# Usage:       Rscript R/79_drug_name_consistency_audit.R
#              source("R/79_drug_name_consistency_audit.R")
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP AND LIBRARIES ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(openxlsx2)
  library(tibble)
})

source("R/00_config.R")
source("R/utils/utils_assertions.R")

message("=== Phase 114: Drug Name Consistency Audit ===\n")


# ==============================================================================
# SECTION 2: INPUT VALIDATION ----
# ==============================================================================

message("--- Input validation ---")

# Validate MEDICATION_LOOKUP exists and has entries
if (!exists("MEDICATION_LOOKUP") || length(MEDICATION_LOOKUP) == 0) {
  stop("[R/79] MEDICATION_LOOKUP not found or empty. Ensure R/00_config.R loaded successfully.")
}
message(glue("  MEDICATION_LOOKUP: {length(MEDICATION_LOOKUP)} entries"))

# Define file paths
DETAIL_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds")
CODE_DESC_RDS <- file.path(CONFIG$cache$outputs_dir, "code_descriptions.rds")
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "drug_name_consistency_audit.xlsx")

# Validate input RDS files exist
assert_rds_exists(DETAIL_RDS, script_name = "R/79")
assert_rds_exists(CODE_DESC_RDS, script_name = "R/79")

message("  All input files validated.")
message()


# ==============================================================================
# SECTION 3: LOAD CURRENT STATE ----
# ==============================================================================

message("--- Loading current pipeline outputs ---")

# Load treatment episode detail (from R/26)
detail <- readRDS(DETAIL_RDS)
message(glue("  treatment_episode_detail.rds: {nrow(detail)} rows"))

# Load code descriptions (from R/42)
code_descs <- readRDS(CODE_DESC_RDS)
message(glue("  code_descriptions.rds: {length(code_descs)} codes"))
message()


# ==============================================================================
# SECTION 4: DRUG NAME SOURCE ANALYSIS ----
# ==============================================================================

message("--- Analyzing drug_name sources ---")

# Classify detail rows by name source:
#   - Rows with triggering_code in MEDICATION_LOOKUP → reference Excel name
#   - Rows with drug_name but triggering_code NOT in MEDICATION_LOOKUP → RxNorm-only name
#   - Rows with blank drug_name → unresolved
rows_with_code <- detail %>%
  filter(!is.na(triggering_code), triggering_code != "") %>%
  mutate(
    in_reference = triggering_code %in% names(MEDICATION_LOOKUP),
    ref_medication = MEDICATION_LOOKUP[triggering_code],
    has_drug_name = !is.na(drug_name) & drug_name != ""
  )

n_ref_sourced <- sum(rows_with_code$in_reference)
n_rxnorm_only <- sum(!rows_with_code$in_reference & rows_with_code$has_drug_name)
n_blank_total <- sum(!rows_with_code$has_drug_name)
n_no_code <- sum(is.na(detail$triggering_code) | detail$triggering_code == "")

message(glue("  Total detail rows: {nrow(detail)}"))
message(glue("  Reference Excel sourced: {n_ref_sourced}"))
message(glue("  RxNorm-only sourced (not in reference): {n_rxnorm_only}"))
message(glue("  Blank drug_name: {n_blank_total}"))
message(glue("  No triggering_code: {n_no_code}"))

# Create per-code summary for RxNorm-only names
rxnorm_only_codes <- rows_with_code %>%
  filter(!in_reference & has_drug_name) %>%
  group_by(triggering_code) %>%
  summarize(
    n_detail_rows = n(),
    current_drug_name = first(drug_name),
    .groups = "drop"
  ) %>%
  arrange(desc(n_detail_rows))

# Blank drug_name codes summary
blank_codes_summary <- rows_with_code %>%
  filter(!has_drug_name) %>%
  group_by(triggering_code) %>%
  summarize(
    n_detail_rows = n(),
    in_reference = first(in_reference),
    ref_medication = first(ref_medication),
    .groups = "drop"
  ) %>%
  arrange(desc(n_detail_rows))

n_unique_rxnorm_only <- nrow(rxnorm_only_codes)
n_unique_blank <- nrow(blank_codes_summary)

message(glue("  Unique triggering_codes with RxNorm-only names: {n_unique_rxnorm_only}"))
message(glue("  Unique triggering_codes with blank drug_name: {n_unique_blank}"))
message()


# ==============================================================================
# SECTION 5: CODE DESCRIPTION INCONSISTENCY ANALYSIS ----
# ==============================================================================

message("--- Analyzing code description inconsistencies ---")

# Compare current code_descriptions against MEDICATION_LOOKUP
desc_comparison <- tibble(
  code = names(code_descs),
  current_description = unname(code_descs)
) %>%
  mutate(
    ref_medication = MEDICATION_LOOKUP[code],
    has_reference = !is.na(ref_medication),
    is_inconsistent = has_reference &
      str_to_lower(str_trim(current_description)) != str_to_lower(str_trim(ref_medication))
  )

inconsistencies <- desc_comparison %>% filter(is_inconsistent)

message(glue("  Code descriptions in code_descriptions.rds: {length(code_descs)}"))
message(glue("    Codes also in reference Excel: {sum(desc_comparison$has_reference)}"))
message(glue("    Codes with inconsistent description vs reference: {nrow(inconsistencies)}"))
message()


# ==============================================================================
# SECTION 6: BUILD SUMMARY TABLE (Sheet 1) ----
# ==============================================================================

message("--- Building summary statistics table ---")

summary_stats <- tibble(
  Metric = c(
    "Total detail rows",
    "  Reference Excel sourced (MEDICATION_LOOKUP)",
    "  RxNorm-only sourced (not in reference)",
    "  Blank drug_name",
    "  No triggering_code at all",
    "",
    "Unique triggering_codes with RxNorm-only names",
    "Unique triggering_codes with blank drug_name",
    "",
    "Code descriptions in code_descriptions.rds",
    "  Codes also in reference Excel",
    "  Codes with inconsistent description vs reference",
    "",
    "MEDICATION_LOOKUP entries (reference Excel total)"
  ),
  Count = c(
    nrow(detail),
    n_ref_sourced,
    n_rxnorm_only,
    n_blank_total,
    n_no_code,
    NA_integer_,
    n_unique_rxnorm_only,
    n_unique_blank,
    NA_integer_,
    length(code_descs),
    sum(desc_comparison$has_reference),
    nrow(inconsistencies),
    NA_integer_,
    length(MEDICATION_LOOKUP)
  )
)

message(glue("  Summary table: {nrow(summary_stats)} rows"))


# ==============================================================================
# SECTION 7: BUILD DETAIL TABLE (Sheet 2) ----
# ==============================================================================

message("--- Building detail table ---")

# Part A: RxNorm-only codes (one row per unique triggering_code)
rxnorm_detail <- rxnorm_only_codes %>%
  transmute(
    triggering_code,
    issue_type = "rxnorm_only",
    current_value = current_drug_name,
    reference_value = NA_character_,
    n_detail_rows
  )

# Part B: Blank drug_name codes (one row per unique triggering_code)
blank_detail <- blank_codes_summary %>%
  transmute(
    triggering_code,
    issue_type = "blank_drug_name",
    current_value = NA_character_,
    reference_value = ref_medication,
    n_detail_rows
  )

# Part C: Inconsistent descriptions (one row per code)
inconsistent_detail <- inconsistencies %>%
  transmute(
    triggering_code = code,
    issue_type = "inconsistent_description",
    current_value = current_description,
    reference_value = ref_medication,
    n_detail_rows = NA_integer_
  )

# Combine all parts
detail_table <- bind_rows(rxnorm_detail, blank_detail, inconsistent_detail) %>%
  arrange(issue_type, triggering_code)

message(glue("  Detail table: {nrow(detail_table)} rows"))
message(glue("    rxnorm_only issues: {sum(detail_table$issue_type == 'rxnorm_only')}"))
message(glue("    blank_drug_name issues: {sum(detail_table$issue_type == 'blank_drug_name')}"))
message(glue("    inconsistent_description issues: {sum(detail_table$issue_type == 'inconsistent_description')}"))
message()


# ==============================================================================
# SECTION 8: CREATE STYLED XLSX ----
# ==============================================================================

message("--- Creating styled xlsx output ---")

wb <- wb_workbook()

# --- Sheet 1: Summary ---
wb$add_worksheet("Summary")

# Title row (A1:B1 merged)
wb$add_data(
  sheet = "Summary", x = "Drug Name Consistency Audit",
  dims = "A1", na.strings = NULL
)
wb$add_font(
  sheet = "Summary", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Summary", dims = "A1:B1")

# Data starting at row 3
wb$add_data(
  sheet = "Summary", x = summary_stats,
  dims = "A3", na.strings = "", col_names = TRUE
)

# Header row styling (row 3 — dark gray background, white bold text)
wb$add_fill(
  sheet = "Summary", dims = "A3:B3",
  color = wb_color("FF374151")
)
wb$add_font(
  sheet = "Summary", dims = "A3:B3",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)

# Column widths
wb$set_col_widths(
  sheet = "Summary",
  cols = c(1, 2),
  widths = c(50, 15)
)

# Freeze panes below header
wb$freeze_pane(
  sheet = "Summary",
  firstActiveRow = 4
)

# --- Sheet 2: Detail ---
wb$add_worksheet("Detail")

# Add data with filter
wb$add_data(
  sheet = "Detail", x = detail_table,
  dims = "A1", na.strings = "", col_names = TRUE
)

# Header row styling (row 1 — dark gray background, white bold text)
wb$add_fill(
  sheet = "Detail", dims = "A1:E1",
  color = wb_color("FF374151")
)
wb$add_font(
  sheet = "Detail", dims = "A1:E1",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)

# Add filter to header row
wb$add_filter(
  sheet = "Detail",
  rows = 1,
  cols = 1:5
)

# Column widths
wb$set_col_widths(
  sheet = "Detail",
  cols = 1:5,
  widths = c(18, 22, 35, 35, 15)
)

# Freeze panes below header
wb$freeze_pane(
  sheet = "Detail",
  firstActiveRow = 2
)

# Save workbook
wb$save(OUTPUT_XLSX)

message(glue("  Audit xlsx saved: {OUTPUT_XLSX}"))
message()


# ==============================================================================
# SECTION 9: CONSOLE SUMMARY ----
# ==============================================================================

message("\n=== Phase 114: Drug Name Consistency Audit Complete ===")
message(glue("  Reference Excel sourced: {n_ref_sourced} rows"))
message(glue("  RxNorm-only sourced: {n_rxnorm_only} rows ({n_unique_rxnorm_only} unique codes)"))
message(glue("  Blank drug_names: {n_blank_total} rows ({n_unique_blank} unique codes)"))
message(glue("  Description inconsistencies: {nrow(inconsistencies)}"))
message(glue("  Output: {OUTPUT_XLSX}"))
message()
