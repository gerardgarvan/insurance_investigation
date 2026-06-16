# ==============================================================================
# R/39_run_all_investigations.R
# ==============================================================================
#
# Purpose:
#   Run all v3.1 + v3.2 investigation scripts in dependency order, then render
#   the gap resolution report to self-contained HTML.
#
# Inputs:
#   - Upstream cached RDS files (from R/26, R/47, R/53)
#   - DuckDB database (from R/01-03)
#   - data/reference/all_codes_resolved_next_tables_v2.1.xlsx
#
# Outputs:
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
#   Requires upstream pipeline (R/00 through R/26, R/47, R/53) to have been
#   run previously so cached RDS files and DuckDB tables exist.
#
# Requirements: REPORT-01, REPORT-02
# ==============================================================================

rm(list = ls())

# ==============================================================================
# SECTION 1: CONFIGURATION ----
# ==============================================================================

message("\n", paste(rep("=", 70), collapse = ""))
message("  R/39: Run All Investigation Scripts + Render Report")
message(paste(rep("=", 70), collapse = ""), "\n")

# Investigation scripts in dependency order
# All depend on upstream cache (R/26, R/47, R/53) but are independent of each other
scripts <- c(
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

# ==============================================================================
# SECTION 2: VERIFY UPSTREAM DEPENDENCIES ----
# ==============================================================================

message("--- Checking upstream dependencies ---\n")

upstream_files <- c(
  "cache/outputs/treatment_episodes.rds",
  "cache/outputs/treatment_episode_detail.rds",
  "output/confirmed_hl_cohort.rds"
)

all_present <- TRUE
for (f in upstream_files) {
  if (file.exists(f)) {
    message(paste0("  OK: ", f))
  } else {
    message(paste0("  MISSING: ", f))
    all_present <- FALSE
  }
}

# validated_death_dates.rds is only needed by R/59 -- warn but don't block
if (file.exists("cache/outputs/validated_death_dates.rds")) {
  message("  OK: cache/outputs/validated_death_dates.rds")
} else {
  message("  WARN: cache/outputs/validated_death_dates.rds (only needed for R/59)")
}

if (!all_present) {
  stop("Missing required upstream files. Run the upstream pipeline (R/00 through R/26, R/47) first.")
}

message()

# ==============================================================================
# SECTION 3: RUN INVESTIGATION SCRIPTS ----
# ==============================================================================

results <- data.frame(
  script = character(),
  status = character(),
  error_msg = character(),
  stringsAsFactors = FALSE
)

for (script in scripts) {
  message(paste(rep("-", 70), collapse = ""))
  message(paste0("  Running: ", script))
  message(paste(rep("-", 70), collapse = ""))

  # Clear any stale globalCallingHandlers from previous scripts
  globalCallingHandlers(NULL)

  status <- tryCatch({
    source(script, local = new.env(parent = globalenv()))
    "OK"
  }, error = function(e) {
    conditionMessage(e)
  })

  if (status == "OK") {
    message(paste0("\n  ** ", script, " -- OK **\n"))
    results <- rbind(results, data.frame(script = script, status = "OK", error_msg = "", stringsAsFactors = FALSE))
  } else {
    message(paste0("\n  ** ", script, " -- FAILED: ", status, " **\n"))
    results <- rbind(results, data.frame(script = script, status = "FAILED", error_msg = status, stringsAsFactors = FALSE))
  }
}

# Clear handlers one final time before rendering
globalCallingHandlers(NULL)

# ==============================================================================
# SECTION 4: RENDER GAP RESOLUTION REPORT ----
# ==============================================================================

message(paste(rep("=", 70), collapse = ""))
message("  Rendering R/37 gap resolution report...")
message(paste(rep("=", 70), collapse = ""))

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

message(paste(rep("=", 70), collapse = ""))
message("  Running R/38 delivery manifest...")
message(paste(rep("=", 70), collapse = ""))

globalCallingHandlers(NULL)

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

message(paste(rep("=", 70), collapse = ""))
message("  SUMMARY")
message(paste(rep("=", 70), collapse = ""), "\n")

n_ok <- sum(results$status == "OK")
n_fail <- sum(results$status == "FAILED")

for (i in seq_len(nrow(results))) {
  flag <- if (results$status[i] == "OK") "OK" else "FAIL"
  message(paste0("  [", flag, "] ", results$script[i]))
}

message(paste0("\n  [", if (report_status == "OK") "OK" else "FAIL", "] R/37 gap resolution report"))
message(paste0("  [", if (manifest_status == "OK") "OK" else "FAIL", "] R/38 delivery manifest"))

message(paste0("\n  Scripts: ", n_ok, " passed, ", n_fail, " failed out of ", nrow(results)))
message(paste0("  Report: ", report_status))
message(paste0("  Manifest: ", manifest_status))

if (n_fail > 0) {
  message("\n  Failed scripts:")
  for (i in which(results$status == "FAILED")) {
    message(paste0("    ", results$script[i], ": ", results$error_msg[i]))
  }
}

message(paste0("\n", paste(rep("=", 70), collapse = "")))
message("  Done.")
message(paste(rep("=", 70), collapse = ""), "\n")
