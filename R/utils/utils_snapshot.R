# ==============================================================================
# utils/utils_snapshot.R -- Snapshot helper for consistent RDS output creation
# ==============================================================================
#
# Purpose:
#   Snapshot helper for consistent RDS output creation. Provides save_output_data()
#   with timestamped filenames and metadata. Standardizes RDS output path construction,
#   automatic directory creation (cohort/ or outputs/ subdirs), and console logging
#   with row/column counts. Used for cohort filter step snapshots (14_build_cohort.R)
#   and figure/table backing datasets (70-75 output scripts).
#
# Inputs:
#   - None (utility function library, not a standalone script)
#
# Outputs:
#   - None (defines functions loaded into calling scripts' environment)
#
# Dependencies:
#   - glue: String formatting for paths and log messages
#
# Requirements: N/A (utility module)
#
# ==============================================================================

#' Save output data snapshot
#'
#' Saves a data frame to an RDS file under CONFIG$cache$cache_dir/{subdir}/
#' with standardized naming and console logging.
#'
#' @param df Data frame to save
#' @param name Base name for the snapshot (without .rds extension)
#' @param subdir Subdirectory under cache_dir (default: "outputs")
#' @return Invisible NULL (side effect: creates .rds file)
#'
#' @examples
#' save_output_data(attrition_plot_data, "waterfall_attrition_data")
#' save_output_data(sankey_data, "sankey_patient_flow_data")
#' save_output_data(cohort, "cohort_00_initial_population", subdir = "cohort")
#'
save_output_data <- function(df, name, subdir = "outputs") {
  # Validate inputs
  if (!is.data.frame(df)) {
    stop("save_output_data: df must be a data frame")
  }
  if (is.null(CONFIG$cache$cache_dir)) {
    stop("save_output_data: CONFIG$cache$cache_dir not configured")
  }
  if (!subdir %in% c("cohort", "outputs")) {
    stop(glue("save_output_data: Invalid subdir '{subdir}'. Must be 'cohort' or 'outputs'."))
  }

  # Construct target directory
  target_dir <- file.path(CONFIG$cache$cache_dir, subdir)

  # Create directory if needed (idempotent)
  if (!dir.exists(target_dir)) {
    created <- dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
    if (!created) {
      stop(glue("save_output_data: Failed to create directory '{target_dir}'. Check permissions."))
    }
    message(glue("  Created snapshot directory: {subdir}/"))
  }

  # Construct full path
  snapshot_path <- file.path(target_dir, paste0(name, ".rds"))

  # Save with compression
  saveRDS(df, snapshot_path, compress = TRUE)

  # Log to console
  message(glue("  Snapshot: {name}.rds ({nrow(df)} rows, {ncol(df)} cols)"))

  invisible(NULL)
}
