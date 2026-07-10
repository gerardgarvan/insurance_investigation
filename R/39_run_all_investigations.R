# ==============================================================================
# R/39_run_all_investigations.R
# ==============================================================================
#
# Purpose:
#   Run the full pipeline end-to-end: data loading, cohort building, episode
#   classification, DuckDB ingest, all investigation scripts, cancer site
#   analysis, code resolution, exports, visualizations, then render the gap
#   resolution report and generate the delivery manifest.
#
# Outputs:
#   Upstream:
#     - cache/outputs/treatment_episodes.rds
#     - cache/outputs/treatment_episode_detail.rds
#     - output/confirmed_hl_cohort.rds
#     - cache/outputs/validated_death_dates.rds
#     - cache/outputs/code_descriptions.rds
#   Investigation:
#     - output/condition_linkage_investigation.xlsx (G1)
#     - output/drug_grouping_instances.xlsx (G2)
#     - output/co_administration_analysis.xlsx (G3)
#     - output/death_date_summary.xlsx (G15)
#     - output/pre_diagnosis_treatments.xlsx (G5)
#     - output/secondary_malignancy_table.xlsx
#     - output/code_verification.xlsx (G8/G10/G11)
#     - output/hl_nhl_overlap_validation.xlsx (G4)
#     - output/death_cause_quality.xlsx
#     - output/tableau_table1_encounter_cancer_codes.xlsx (TABLE-1)
#     - output/tableau_table2_chemo_drugs_by_class.xlsx (TABLE-2)
#     - output/episode_level_drug_grouping_tables.xlsx
#   Cancer Site:
#     - output/tables/cancer_site_frequency.xlsx
#     - output/tables/all_codes_inventory.xlsx
#     - output/tables/cancer_site_confirmation.xlsx
#     - output/tables/cancer_site_confirmation_7day.xlsx
#     - output/tables/cancer_summary.xlsx
#     - output/tables/cancer_summary_table.xlsx
#     - output/tables/cancer_summary_post_hl.xlsx
#     - output/tables/cancer_summary_table_pre_post.xlsx
#   Code Analysis & Exports:
#     - output/all_codes_resolved.xlsx
#     - output/source_coverage_analysis.xlsx
#     - output/venn_lymphoma_3way_summary.csv
#     - output/tables/code_reference.xlsx
#     - output/gantt_episodes.csv
#     - output/gantt_detail.csv
#   Visualization:
#     - output/figures/waterfall_attrition.png
#     - output/figures/sankey_patient_flow.png
#     - output/figures/venn_hl_nlphl.png
#     - output/<date>_insurance_tables.pptx
#   Report & Manifest:
#     - output/gap_resolution_report.html (compiled report)
#     - output/delivery_manifest.xlsx (file inventory)
#
# Dependencies:
#   Raw PCORnet CDM CSV files on filesystem (paths in R/00_config.R)
#   For R/42: cache/outputs/unmatched_codes_classified.rds and
#             cache/outputs/unmatched_ndc_classified.rds from prior R/21+R/22 runs
#
# Requirements: REPORT-01, REPORT-02
# ==============================================================================

rm(list = ls())

# ==============================================================================
# SECTION 1: CONFIGURATION ----
# ==============================================================================

# Guard: Must run from project root (all relative paths assume it)
if (!file.exists("R/00_config.R")) {
  # Try to find project root and set it
  if (file.exists(here::here("R/00_config.R"))) {
    setwd(here::here())
    message("  Working directory set to project root: ", getwd())
  } else {
    stop("R/39 must be run from the project root directory (where R/00_config.R lives).\n",
         "  Current directory: ", getwd(), "\n",
         "  Fix: setwd() to project root, then source this script.")
  }
}

message("\n", paste(rep("=", 70), collapse = ""))
message("  R/39: Full Pipeline + Investigation Scripts + Report")
message(paste(rep("=", 70), collapse = ""), "\n")

start_time <- Sys.time()

# Helper to run a script with error handling and handler cleanup
run_script <- function(script, results_df) {
  message(paste(rep("-", 70), collapse = ""))
  message(paste0("  Running: ", script))
  message(paste(rep("-", 70), collapse = ""))

  globalCallingHandlers(NULL)

  status <- tryCatch({
    source(script, local = new.env(parent = globalenv()))
    "OK"
  }, error = function(e) {
    conditionMessage(e)
  })

  globalCallingHandlers(NULL)

  if (status == "OK") {
    message(paste0("\n  ** ", script, " -- OK **\n"))
  } else {
    message(paste0("\n  ** ", script, " -- FAILED: ", status, " **\n"))
  }

  rbind(results_df, data.frame(
    script = script,
    status = if (status == "OK") "OK" else "FAILED",
    error_msg = if (status == "OK") "" else status,
    stringsAsFactors = FALSE
  ))
}

results <- data.frame(
  script = character(),
  status = character(),
  error_msg = character(),
  stringsAsFactors = FALSE
)

# ==============================================================================
# SECTION 2: UPSTREAM PIPELINE -- Data Loading & Cohort Building ----
# ==============================================================================

message(paste(rep("=", 70), collapse = ""))
message("  STAGE 1: Upstream Pipeline (data loading -> episode classification)")
message(paste(rep("=", 70), collapse = ""), "\n")

# R/14 auto-sources: R/02 -> R/01 -> R/00 -> utils, plus R/10, R/11, R/12, R/13
results <- run_script("R/14_build_cohort.R", results)

# R/03 ingests RDS cache into DuckDB (needed by investigation scripts)
results <- run_script("R/03_duckdb_ingest.R", results)

# R/47 produces output/confirmed_hl_cohort.rds (needs R/01 data in memory)
# R/47 auto-sources: R/00, R/01
results <- run_script("R/47_cancer_summary_refined.R", results)

# R/26 produces treatment_episodes.rds and treatment_episode_detail.rds
# R/26 auto-sources: R/00, R/01, R/25
results <- run_script("R/26_treatment_episodes.R", results)

# R/28 enriches treatment_episodes.rds with cancer linkage + regimen detection
# R/28 auto-sources: R/00, utils
results <- run_script("R/28_episode_classification.R", results)

# R/29 adds first-line flags and death validation
# R/29 auto-sources: R/00, utils
results <- run_script("R/29_first_line_and_death_analysis.R", results)

# R/53 produces validated_death_dates.rds (needed by R/59, R/52)
# R/53 auto-sources: R/00, utils
results <- run_script("R/53_death_date_validation.R", results)

# R/42 builds code_descriptions.rds lookup (needed by R/52, R/58_code_reference)
# Depends on cached outputs from R/21+R/22 (API scripts run separately)
# R/42 auto-sources: R/00
results <- run_script("R/42_build_code_descriptions.R", results)

upstream_count <- 8

# ==============================================================================
# SECTION 3: INVESTIGATION SCRIPTS ----
# ==============================================================================

message(paste(rep("=", 70), collapse = ""))
message("  STAGE 2: Investigation Scripts (gap analyses)")
message(paste(rep("=", 70), collapse = ""), "\n")

investigation_scripts <- c(
  "R/30_condition_linkage_investigation.R",    # G1:  CONDITION table linkage
  "R/57_drug_grouping_instances.R",            # G2:  Broadened drug grouping
  "R/58_co_administration_analysis.R",         # G3:  Co-administration patterns
  "R/59_death_date_summary.R",                 # G15: Death date cross-tab
  "R/51_post_death_encounter_investigation.R", # Post-death encounter drill-down (Phase 113)
  "R/79_drug_name_consistency_audit.R",        # Drug name consistency audit (Phase 114)
  "R/31_pre_diagnosis_treatments.R",           # G5:  Pre-diagnosis treatments
  "R/32_secondary_malignancy_table.R",         # Secondary malignancy table
  "R/33_code_verification.R",                  # G8/G10/G11: Code verification
  "R/34_hl_nhl_overlap_validation.R",          # G4:  HL+NHL overlap
  "R/35_death_cause_quality.R",                # Death cause quality analysis
  "R/36_tableau_ready_tables.R",               # TABLE-1 and TABLE-2
  "R/56_new_tables_from_groupings.R",          # Episode-level drug grouping tables
  "R/100_ruca_rurality_summary.R",             # RUCA rurality summary (Phase 116)
  "R/101_gantt_lifespan_collapse.R",           # Lifespan Gantt collapse (Phase 117); consumes gantt_episodes.csv (produced by R/52)
  "R/103_death_cause_diagnostic.R",           # Cause-of-death signal inventory diagnostic (Phase 119; read-only)
  "R/102_death_cause_nhl_flag.R"              # Cause-of-death NHL three-state flag CSV (Phase 118; fixed Phase 119 to read DEATH_CAUSE table)
)

for (script in investigation_scripts) {
  results <- run_script(script, results)
}

# ==============================================================================
# SECTION 4: CANCER SITE ANALYSIS ----
# ==============================================================================

message(paste(rep("=", 70), collapse = ""))
message("  STAGE 3: Cancer Site Analysis")
message(paste(rep("=", 70), collapse = ""), "\n")

cancer_site_scripts <- c(
  "R/40_cancer_site_frequency.R",              # Cancer site frequency inventory
  "R/41_extract_all_codes.R",                  # All ICD-10 + ICD-O-3 code inventory
  "R/43_cancer_site_confirmation.R",           # Cancer site confirmation (exact)
  "R/44_cancer_site_confirmation_7day.R",      # Cancer site confirmation (7-day gap)
  "R/45_cancer_summary.R",                     # Patient-level cancer summary
  "R/46_cancer_summary_table.R",               # Aggregated cancer summary (needs R/45)
  "R/48_cancer_summary_post_hl.R",             # Post-HL cancer summary (needs R/47, R/46)
  "R/49_cancer_summary_pre_post.R"             # Pre/post cancer summary (needs R/47, R/45)
)

for (script in cancer_site_scripts) {
  results <- run_script(script, results)
}

# ==============================================================================
# SECTION 5: CODE ANALYSIS & EXPORTS ----
# ==============================================================================

message(paste(rep("=", 70), collapse = ""))
message("  STAGE 4: Code Analysis & Exports")
message(paste(rep("=", 70), collapse = ""), "\n")

export_scripts <- c(
  "R/50_all_codes_resolved.R",                 # All resolved treatment codes (6-sheet xlsx)
  "R/76_treatment_source_coverage.R",          # Tumor registry treatment coverage
  "R/78_venn_lymphoma_3way.R",                 # 3-way lymphoma Venn data
  "R/77_venn_hl_nlphl.R",                      # HL vs NLPHL Venn diagram
  "R/58_code_reference_tables.R",              # Code reference tables (needs R/49, R/56)
  "R/52_gantt_v2_export.R"                     # Gantt CSVs for Tableau (needs R/28, R/42, R/53)
)

for (script in export_scripts) {
  results <- run_script(script, results)
}

# ==============================================================================
# SECTION 6: VISUALIZATION ----
# ==============================================================================

message(paste(rep("=", 70), collapse = ""))
message("  STAGE 5: Visualization")
message(paste(rep("=", 70), collapse = ""), "\n")

viz_scripts <- c(
  "R/70_visualize_waterfall.R",                # Cohort attrition waterfall
  "R/71_visualize_sankey.R",                   # Payer-stratified Sankey diagram
  "R/72_generate_pptx.R"                       # 52-slide PPTX (auto-chains R/75)
)

for (script in viz_scripts) {
  results <- run_script(script, results)
}

# ==============================================================================
# SECTION 7: RENDER GAP RESOLUTION REPORT ----
# ==============================================================================

message(paste(rep("=", 70), collapse = ""))
message("  STAGE 6: Report & Manifest")
message(paste(rep("=", 70), collapse = ""), "\n")

globalCallingHandlers(NULL)

# Pre-render check: verify investigation outputs exist
expected_xlsx <- c(
  "condition_linkage_investigation.xlsx",
  "drug_grouping_instances.xlsx",
  "co_administration_analysis.xlsx",
  "hl_nhl_overlap_validation.xlsx",
  "pre_diagnosis_treatments.xlsx",
  "secondary_malignancy_table.xlsx",
  "code_verification.xlsx",
  "death_date_summary.xlsx",
  "tableau_table1_encounter_cancer_codes.xlsx",
  "tableau_table2_chemo_drugs_by_class.xlsx"
)
found <- file.exists(file.path("output", expected_xlsx))
message("  Report data files: ", sum(found), "/", length(expected_xlsx), " present")
if (any(!found)) {
  message("  Missing (will show 'File not available' in report):")
  for (f in expected_xlsx[!found]) message("    - ", f)
}

message("\n  Rendering R/37 gap resolution report...")
report_status <- tryCatch({
  rmarkdown::render(
    "R/37_gap_resolution_report.Rmd",
    output_file = "gap_resolution_report.html",
    output_dir = "output",
    quiet = TRUE
  )
  "OK"
}, error = function(e) {
  conditionMessage(e)
})

if (report_status == "OK") {
  message("\n  ** Report rendered: output/gap_resolution_report.html -- OK **\n")
} else {
  message(paste0("\n  ** Report render FAILED: ", report_status, " **\n"))
}

# ==============================================================================
# SECTION 8: RUN DELIVERY MANIFEST ----
# ==============================================================================

globalCallingHandlers(NULL)

message("  Running R/38 delivery manifest...")
manifest_status <- tryCatch({
  source("R/38_delivery_manifest.R", local = new.env(parent = globalenv()))
  "OK"
}, error = function(e) {
  conditionMessage(e)
})

if (manifest_status == "OK") {
  message("\n  ** Manifest generated: output/delivery_manifest.xlsx -- OK **\n")
} else {
  message(paste0("\n  ** Manifest FAILED: ", manifest_status, " **\n"))
}

# ==============================================================================
# SECTION 9: SUMMARY ----
# ==============================================================================

elapsed <- round(difftime(Sys.time(), start_time, units = "mins"), 1)

message(paste(rep("=", 70), collapse = ""))
message("  SUMMARY")
message(paste(rep("=", 70), collapse = ""), "\n")

n_ok <- sum(results$status == "OK")
n_fail <- sum(results$status == "FAILED")

# Print results by stage
stage_names <- c(
  "UPSTREAM PIPELINE",
  "INVESTIGATION SCRIPTS",
  "CANCER SITE ANALYSIS",
  "CODE ANALYSIS & EXPORTS",
  "VISUALIZATION"
)
stage_counts <- c(
  upstream_count,
  length(investigation_scripts),
  length(cancer_site_scripts),
  length(export_scripts),
  length(viz_scripts)
)

offset <- 0
for (s in seq_along(stage_names)) {
  message(paste0("\n  ", stage_names[s], ":"))
  for (i in seq(offset + 1, offset + stage_counts[s])) {
    if (i <= nrow(results)) {
      flag <- if (results$status[i] == "OK") "OK" else "FAIL"
      message(paste0("    [", flag, "] ", results$script[i]))
    }
  }
  offset <- offset + stage_counts[s]
}

message(paste0("\n  [", if (report_status == "OK") "OK" else "FAIL", "] R/37 gap resolution report"))
message(paste0("  [", if (manifest_status == "OK") "OK" else "FAIL", "] R/38 delivery manifest"))

message(paste0("\n  Scripts: ", n_ok, " passed, ", n_fail, " failed out of ", nrow(results)))
message(paste0("  Report: ", report_status))
message(paste0("  Manifest: ", manifest_status))
message(paste0("  Elapsed: ", elapsed, " minutes"))

if (n_fail > 0) {
  message("\n  Failed scripts:")
  for (i in which(results$status == "FAILED")) {
    message(paste0("    ", results$script[i], ": ", results$error_msg[i]))
  }
}

message(paste0("\n", paste(rep("=", 70), collapse = "")))
message("  Done.")
message(paste(rep("=", 70), collapse = ""), "\n")
