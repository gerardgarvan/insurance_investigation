# ==============================================================================
# run_phase12_outputs.R -- HiPerGator execution helper for Phase 12 outputs
# ==============================================================================
#
# Purpose:
#   Single script to generate all Phase 12 outputs (4 encounter analysis PNGs +
#   final PPTX) on HiPerGator where patient data resides. Closes verification
#   gaps PPTX2-04 (histogram with 6+Missing payer facets and overflow bin
#   annotations) and PPTX2-07 (age group bar chart with no label clipping).
#
# Usage:
#   On HiPerGator RStudio, set working directory to project root, then:
#   source("R/run_phase12_outputs.R")
#
# Generated files:
#   - output/figures/encounters_per_person_by_payor.png (PPTX2-04)
#   - output/figures/post_tx_encounters_by_dx_year.png
#   - output/figures/total_encounters_by_dx_year.png
#   - output/figures/post_tx_by_age_group.png (PPTX2-07)
#   - insurance_tables_YYYY-MM-DD.pptx
#
# ==============================================================================

message("\n", strrep("=", 80))
message("Phase 12 Output Generation -- HiPerGator Execution Helper")
message(strrep("=", 80))
message("\nThis script generates all Phase 12 outputs:")
message("  1. Four encounter analysis PNG figures (16_encounter_analysis.R)")
message("  2. Final insurance tables PowerPoint (11_generate_pptx.R)")
message("\nClosing verification gaps:")
message("  - PPTX2-04: Histogram with 6+Missing payer facets and overflow bin")
message("  - PPTX2-07: Age group bar chart with no label clipping at top")
message("")

# ==============================================================================
# SECTION 1: ENVIRONMENT CHECKS
# ==============================================================================

message("--- Pre-flight checks ---")

# Check working directory structure
if (!dir.exists("R")) {
  stop("\nERROR: R/ directory not found in current working directory.\n",
       "Please set your working directory to the project root (the directory ",
       "containing R/, output/, etc.) before sourcing this script.\n\n",
       "Example: setwd(\"/blue/ufhscprojects/research/projects/insurance_investigation\")")
}

if (!dir.exists("output")) {
  stop("\nERROR: output/ directory not found in current working directory.\n",
       "Please set your working directory to the project root before sourcing this script.")
}

message("  \u2713 Working directory structure verified (R/ and output/ directories found)")

# Create output/figures/ directory if needed
if (!dir.exists("output/figures")) {
  dir.create("output/figures", recursive = TRUE, showWarnings = FALSE)
  message("  \u2713 Created output/figures/ directory")
} else {
  message("  \u2713 output/figures/ directory exists")
}

# ==============================================================================
# SECTION 2: GENERATE ENCOUNTER ANALYSIS PNGS
# ==============================================================================

message("\n--- Generating encounter analysis PNGs (16_encounter_analysis.R) ---")
message("This script sources R/04_build_cohort.R (may take several minutes to load data)...")

# Wrap source() in tryCatch for clear error reporting
tryCatch({
  source("R/16_encounter_analysis.R")
  message("  \u2713 16_encounter_analysis.R completed successfully")
}, error = function(e) {
  stop("\nERROR: 16_encounter_analysis.R failed with error:\n  ", e$message, "\n\n",
       "Check that:\n",
       "  1. Data files are accessible (paths in R/00_config.R)\n",
       "  2. All required packages are installed (ggplot2, dplyr, scales, etc.)\n",
       "  3. R/04_build_cohort.R and dependencies are present\n")
})

# ==============================================================================
# SECTION 3: VERIFY PNG FILES EXIST
# ==============================================================================

message("\n--- Verifying generated PNG files ---")

expected_pngs <- c(
  "output/figures/encounters_per_person_by_payor.png",
  "output/figures/post_tx_encounters_by_dx_year.png",
  "output/figures/total_encounters_by_dx_year.png",
  "output/figures/post_tx_by_age_group.png"
)

all_present <- TRUE
for (png_path in expected_pngs) {
  if (file.exists(png_path)) {
    file_size <- file.info(png_path)$size
    message(sprintf("  \u2713 %s (%s KB)", png_path, round(file_size / 1024, 1)))
  } else {
    message(sprintf("  \u2717 MISSING: %s", png_path))
    all_present <- FALSE
  }
}

if (!all_present) {
  stop("\nERROR: One or more expected PNG files were not generated.\n",
       "Check the console output above for error messages from 16_encounter_analysis.R.")
}

message("  \u2713 All 4 PNG files successfully generated")

# ==============================================================================
# SECTION 4: GENERATE PPTX
# ==============================================================================

message("\n--- Generating insurance tables PowerPoint (11_generate_pptx.R) ---")

tryCatch({
  source("R/11_generate_pptx.R")
  message("  \u2713 11_generate_pptx.R completed successfully")
}, error = function(e) {
  stop("\nERROR: 11_generate_pptx.R failed with error:\n  ", e$message, "\n\n",
       "Check that:\n",
       "  1. officer and flextable packages are installed\n",
       "  2. R/04_build_cohort.R has been sourced (cohort data in environment)\n",
       "  3. PNG files exist in output/figures/\n")
})

# ==============================================================================
# SECTION 5: VISUAL VERIFICATION CHECKLIST
# ==============================================================================

message("\n", strrep("=", 80))
message("OUTPUT GENERATION COMPLETE")
message(strrep("=", 80))
message("\nAll files generated successfully. Now perform visual verification:")
message("")
message("STEP 1: Open output/figures/encounters_per_person_by_payor.png")
message("  Verify:")
message("    [  ] Exactly 7 facets visible: Medicare, Medicaid, Dual eligible, Private,")
message("         Other government, No payment / Self-pay, Missing")
message("    [  ] No facets labeled 'Other', 'Unavailable', or 'Unknown' (consolidated to Missing)")
message("    [  ] Each facet shows overflow bin annotation in top-right: '>500: N'")
message("         (where N is the count of patients with >500 encounters in that category)")
message("")
message("STEP 2: Open output/figures/post_tx_by_age_group.png")
message("  Verify:")
message("    [  ] Bar chart shows 4 age groups: 0-17, 18-39, 40-64, 65+")
message("    [  ] Count labels above bars (e.g., '123 (45.6%)') are fully visible")
message("    [  ] No label clipping at top edge of plot area")
message("")
message("STEP 3: Open insurance_tables_", Sys.Date(), ".pptx")
message("  Verify:")
message("    [  ] Slide 1 is 'Definitions and Glossary' (not a data table)")
message("    [  ] All slides have footnotes at bottom (8pt italic gray text)")
message("    [  ] Slide 17 shows the histogram from Step 1 (embedded PNG)")
message("    [  ] Slide 21 shows the age group bar chart from Step 2 (embedded PNG)")
message("    [  ] All table slides show 7 payer rows (6 categories + Missing) + Total row")
message("")
message("If all checks pass:")
message("  - PPTX2-04 verification gap is CLOSED (histogram with 6+Missing facets + overflow bin)")
message("  - PPTX2-07 verification gap is CLOSED (age group bar chart with no label clipping)")
message("")
message("Report verification status back to the development environment.")
message(strrep("=", 80))
message("")
