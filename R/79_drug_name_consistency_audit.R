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
# SECTION 4: BLANK DRUG_NAME ANALYSIS ----
# ==============================================================================

message("--- Analyzing blank drug_names ---")

# Find rows with blank drug_name (NA or empty string)
blank_rows <- detail %>%
  filter(is.na(drug_name) | drug_name == "")

n_blank_total <- nrow(blank_rows)
message(glue("  Total detail rows with blank drug_name: {n_blank_total}"))

# Of blank rows, find those with a triggering_code
blank_with_code <- blank_rows %>%
  filter(!is.na(triggering_code), triggering_code != "")

n_blank_with_code <- nrow(blank_with_code)

# Of blank rows, find those without a triggering_code
blank_no_code <- blank_rows %>%
  filter(is.na(triggering_code) | triggering_code == "")

n_no_code <- nrow(blank_no_code)

# For rows with triggering_code, check if code is in MEDICATION_LOOKUP
blank_with_code <- blank_with_code %>%
  mutate(
    ref_medication = MEDICATION_LOOKUP[triggering_code],
    fillable = !is.na(ref_medication)
  )

n_fillable <- sum(blank_with_code$fillable)
n_unfillable <- sum(!blank_with_code$fillable)

message(glue("  Blank with triggering_code: {n_blank_with_code}"))
message(glue("    Fillable (code in reference): {n_fillable}"))
message(glue("    Unfillable (code not in reference): {n_unfillable}"))
message(glue("  Blank with no triggering_code: {n_no_code}"))

# Create per-code summary for blank drug_names
blank_codes_summary <- blank_with_code %>%
  group_by(triggering_code) %>%
  summarize(
    n_detail_rows = n(),
    fillable = first(fillable),
    ref_medication = first(ref_medication),
    .groups = "drop"
  ) %>%
  arrange(desc(n_detail_rows))

n_unique_blank_codes <- nrow(blank_codes_summary)
n_unique_mappable <- sum(blank_codes_summary$fillable)
n_unique_unmappable <- sum(!blank_codes_summary$fillable)

message(glue("  Unique triggering_codes with blank drug_name: {n_unique_blank_codes}"))
message(glue("    Mappable to reference: {n_unique_mappable}"))
message(glue("    Not in reference: {n_unique_unmappable}"))
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
    "Detail rows with blank drug_name",
    "  Blank with triggering_code in reference (fillable)",
    "  Blank without triggering_code in reference (unfillable)",
    "  Blank with no triggering_code at all",
    "",
    "Unique triggering_codes with blank drug_name",
    "  Codes mappable to reference Excel",
    "  Codes not in reference Excel",
    "",
    "Code descriptions in code_descriptions.rds",
    "  Codes also in reference Excel",
    "  Codes with inconsistent description vs reference",
    "",
    "MEDICATION_LOOKUP entries (reference Excel total)"
  ),
  Count = c(
    nrow(detail),
    n_blank_total,
    n_fillable,
    n_unfillable,
    n_no_code,
    NA_integer_,
    n_unique_blank_codes,
    n_unique_mappable,
    n_unique_unmappable,
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

# Part A: Blank drug_name codes (one row per unique triggering_code)
blank_detail <- blank_codes_summary %>%
  transmute(
    triggering_code,
    issue_type = "blank_drug_name",
    current_value = NA_character_,  # Blank drug_name means NA
    reference_value = ref_medication,
    fillable,
    n_detail_rows
  )

# Part B: Inconsistent descriptions (one row per code)
inconsistent_detail <- inconsistencies %>%
  transmute(
    triggering_code = code,
    issue_type = "inconsistent_description",
    current_value = current_description,
    reference_value = ref_medication,
    fillable = TRUE,  # All inconsistencies are fillable
    n_detail_rows = NA_integer_  # N/A for description issues
  )

# Combine both parts
detail_table <- bind_rows(blank_detail, inconsistent_detail) %>%
  arrange(issue_type, triggering_code)

message(glue("  Detail table: {nrow(detail_table)} rows"))
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
  sheet = "Detail", dims = "A1:F1",
  color = wb_color("FF374151")
)
wb$add_font(
  sheet = "Detail", dims = "A1:F1",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)

# Add filter to header row
wb$add_filter(
  sheet = "Detail",
  rows = 1,
  cols = 1:6
)

# Column widths
wb$set_col_widths(
  sheet = "Detail",
  cols = 1:6,
  widths = c(18, 22, 35, 35, 10, 15)
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
message(glue("  Blank drug_names: {n_blank_total} ({n_fillable} fillable, {n_unfillable} unfillable)"))
message(glue("  Description inconsistencies: {nrow(inconsistencies)}"))
message(glue("  Output: {OUTPUT_XLSX}"))
message()
