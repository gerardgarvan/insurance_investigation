# ==============================================================================
# 38_delivery_manifest.R
# ==============================================================================
#
# Purpose:
#   Generate delivery manifest xlsx listing all v3.1 + v3.2 output files with
#   validation and metadata. Inventory of Phase 100-107 deliverables for
#   packaging to Amy.
#
# Inputs:
#   - output/ directory (all xlsx and html files from Phases 100-107)
#
# Outputs:
#   - output/delivery_manifest.xlsx (file inventory with metadata)
#
# Dependencies:
#   - openxlsx2, dplyr, glue, lubridate
#
# Requirements:
#   - REPORT-02
#
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP ----
# ==============================================================================

# Clear workspace
rm(list = ls())

# Load libraries
suppressPackageStartupMessages({
  library(openxlsx2)
  library(dplyr)
  library(glue)
  library(lubridate)
})

message("=== R/38: Data Delivery Manifest Generator ===")
message(glue("Generated: {Sys.Date()}"))

# ==============================================================================
# SECTION 2: DEFINE EXPECTED FILES ----
# ==============================================================================

message("\n--- Defining Expected Files ---")

# Create manifest of all v3.1 + v3.2 deliverables
expected_files <- tribble(
  ~filepath, ~description, ~phase, ~gap_ref,
  # v3.1 outputs (Phases 100-103)
  "output/condition_linkage_investigation.xlsx",
    "CONDITION table cancer linkage improvement analysis",
    "100", "G1",
  "output/drug_grouping_instances.xlsx",
    "Broadened drug grouping with cancer_linked flag for all treatment encounters",
    "101", "G2",
  "output/drug_grouping_instances_linked_only.xlsx",
    "Drug grouping filtered to cancer-linked encounters only (backward compatible)",
    "101", "G2",
  "output/co_administration_analysis.xlsx",
    "Single-agent chemotherapy co-administration patterns within 30-day window",
    "102", "G3",
  "output/death_date_summary.xlsx",
    "Death date cross-tab: patients with death dates, last encounter timing, post-death activity",
    "103", "G15",

  # v3.2 outputs (Phases 104-107)
  "output/pre_diagnosis_treatments.xlsx",
    "Pre-diagnosis treatment episodes flagged by type (chemo, radiation, SCT, immunotherapy, proton)",
    "104", "G5",
  "output/secondary_malignancy_table.xlsx",
    "Secondary malignancy table with 7-day gap criterion and pre/post HL split",
    "104", "G5-related",
  "output/code_verification.xlsx",
    "Etanercept (G8), organ transplant code 0362 (G10), SCT diagnosis codes (G11) verification",
    "105", "G8/G10/G11",
  "output/hl_nhl_overlap_validation.xlsx",
    "HL+NHL dual-code patient temporal validation with data quality assessment",
    "105", "G4",
  "output/tableau_table1_encounter_cancer_codes.xlsx",
    "TABLE 1: Each encounter mapped to comma-separated cancer diagnosis codes for Tableau",
    "106", "TABLE-1",
  "output/tableau_table2_chemo_drugs_by_class.xlsx",
    "TABLE 2: Chemotherapy drugs by class/category with cancer codes for Tableau",
    "106", "TABLE-2",
  "output/gap_resolution_report.html",
    "Self-contained HTML report compiling all gap investigation findings",
    "107", "Report",
  "output/delivery_manifest.xlsx",
    "This file: inventory of all v3.1+v3.2 deliverables",
    "107", "Manifest"
)

message(glue("  Defined {nrow(expected_files)} expected files"))

# ==============================================================================
# SECTION 3: VALIDATE AND GATHER METADATA ----
# ==============================================================================

message("\n--- Validating Files and Gathering Metadata ---")

# Check file existence and gather metadata
manifest <- expected_files %>%
  rowwise() %>%
  mutate(
    exists = file.exists(filepath),
    filename = basename(filepath),
    size_kb = if_else(exists, round(file.info(filepath)$size / 1024, 2), NA_real_),
    modified = if_else(
      exists,
      format(as_datetime(file.info(filepath)$mtime), "%Y-%m-%d %H:%M"),
      NA_character_
    ),
    status = if_else(exists, "OK", "MISSING")
  ) %>%
  ungroup() %>%
  select(phase, gap_ref, filename, description, size_kb, modified, status)

n_total <- nrow(manifest)
n_found <- sum(manifest$status == "OK")
n_missing <- sum(manifest$status == "MISSING")

message(glue("  Total files: {n_total}"))
message(glue("  Found: {n_found}"))
message(glue("  Missing: {n_missing}"))

# ==============================================================================
# SECTION 4: CONSOLE SUMMARY ----
# ==============================================================================

if (n_missing > 0) {
  message("\n--- Missing Files ---")
  missing_files <- manifest %>%
    filter(status == "MISSING") %>%
    pull(filename)

  for (f in missing_files) {
    message(glue("  - {f}"))
  }
  message("\nNote: Missing files will be flagged as MISSING in the manifest.")
} else {
  message("\n--- All Files Found ---")
}

# ==============================================================================
# SECTION 5: WRITE XLSX ----
# ==============================================================================

message("\n--- Writing Manifest XLSX ---")

output_path <- "output/delivery_manifest.xlsx"

# Create workbook
wb <- wb_workbook()
wb$add_worksheet("File Inventory")

# Add data
wb$add_data(
  sheet = "File Inventory",
  x = manifest,
  start_col = 1,
  start_row = 1
)

# Header styling (dark gray background, white bold text - project pattern)
wb$add_fill(
  sheet = "File Inventory",
  dims = "A1:G1",
  color = wb_color("FF374151")
)
wb$add_font(
  sheet = "File Inventory",
  dims = "A1:G1",
  bold = TRUE,
  color = wb_color("FFFFFFFF")
)

# Freeze header row
wb$freeze_pane(sheet = "File Inventory", firstActiveRow = 2)

# Autofit column widths
wb$set_col_widths(sheet = "File Inventory", cols = 1:7, widths = "auto")

# Save
wb$save(output_path)

message(glue("  Manifest written to {output_path}"))

# ==============================================================================
# SECTION 6: FINAL SUMMARY ----
# ==============================================================================

message("\n=== Delivery Manifest Complete ===")
message(glue("  Output: {output_path}"))
message(glue("  Total files inventoried: {n_total}"))
message(glue("  Files found: {n_found}"))
message(glue("  Files missing: {n_missing}"))

if (n_missing == 0) {
  message("\nAll deliverables ready for packaging.")
} else {
  message("\nWARNING: Some deliverables are missing. Run investigation scripts before delivery.")
}
