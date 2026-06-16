# ==============================================================================
# R/39_run_all_investigations.R
# ==============================================================================
#
# Purpose:
#   Run the full pipeline end-to-end: data loading, cohort building, episode
#   classification, DuckDB ingest, all v3.1+v3.2 investigation scripts, then
#   render the gap resolution report and generate the delivery manifest.
#
# Outputs:
#   - cache/outputs/treatment_episodes.rds (upstream)
#   - cache/outputs/treatment_episode_detail.rds (upstream)
#   - output/confirmed_hl_cohort.rds (upstream)
#   - cache/outputs/validated_death_dates.rds (upstream)
#   - output/condition_linkage_investigation.xlsx (G1)
#   - output/drug_grouping_instances.xlsx (G2)
#   - output/co_administration_analysis.xlsx (G3)
#   - output/death_date_summary.xlsx (G15)
#   - output/pre_diagnosis_treatments.xlsx (G5)
#   - output/secondary_malignancy_table.xlsx (Secondary Malignancy)
#   - output/code_verification.xlsx (G8/G10/G11)
#   - output/hl_nhl_overlap_validation.xlsx (G4)
#   - output/tableau_table1_encounter_cancer_codes.xlsx (TABLE-1)
#   - output/tableau_table2_chemo_drugs_by_class.xlsx (TABLE-2)
#   - output/gap_resolution_report.html (compiled report)
#   - output/delivery_manifest.xlsx (file inventory)
#
# Dependencies:
#   Raw PCORnet CDM CSV files on filesystem (paths in R/00_config.R)
#
# Requirements: REPORT-01, REPORT-02
# ==============================================================================

rm(list = ls())

# ==============================================================================
# SECTION 1: CONFIGURATION ----
# ==============================================================================

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

# R/53 produces validated_death_dates.rds (needed by R/59)
# R/53 auto-sources: R/00, utils
results <- run_script("R/53_death_date_validation.R", results)

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
  "R/31_pre_diagnosis_treatments.R",           # G5:  Pre-diagnosis treatments
  "R/32_secondary_malignancy_table.R",         # Secondary malignancy table
  "R/33_code_verification.R",                  # G8/G10/G11: Code verification
  "R/34_hl_nhl_overlap_validation.R",          # G4:  HL+NHL overlap
  "R/36_tableau_ready_tables.R"                # TABLE-1 and TABLE-2
)

for (script in investigation_scripts) {
  results <- run_script(script, results)
}

# ==============================================================================
# SECTION 4: RENDER GAP RESOLUTION REPORT ----
# ==============================================================================

message(paste(rep("=", 70), collapse = ""))
message("  STAGE 3: Report & Manifest")
message(paste(rep("=", 70), collapse = ""), "\n")

globalCallingHandlers(NULL)

message("  Rendering R/37 gap resolution report...")
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
# SECTION 5: RUN DELIVERY MANIFEST ----
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
# SECTION 6: SUMMARY ----
# ==============================================================================

elapsed <- round(difftime(Sys.time(), start_time, units = "mins"), 1)

message(paste(rep("=", 70), collapse = ""))
message("  SUMMARY")
message(paste(rep("=", 70), collapse = ""), "\n")

n_ok <- sum(results$status == "OK")
n_fail <- sum(results$status == "FAILED")

message("  UPSTREAM PIPELINE:")
upstream_count <- 7  # first 7 scripts are upstream
for (i in seq_len(min(upstream_count, nrow(results)))) {
  flag <- if (results$status[i] == "OK") "OK" else "FAIL"
  message(paste0("    [", flag, "] ", results$script[i]))
}

message("\n  INVESTIGATION SCRIPTS:")
for (i in seq(upstream_count + 1, nrow(results))) {
  flag <- if (results$status[i] == "OK") "OK" else "FAIL"
  message(paste0("    [", flag, "] ", results$script[i]))
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
