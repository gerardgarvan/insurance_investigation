# ==============================================================================
# Attrition logging for cohort construction
# ==============================================================================
#
# Tracks patient counts (unique IDs) through sequential filter steps.
# Produces a data frame ready for waterfall chart visualization.
#
# Usage:
#   source("R/00_config.R")  # Auto-loads this file
#   attrition_log <- init_attrition_log()
#   attrition_log <- log_attrition(attrition_log, "Initial cohort", n_distinct(df$ID))
#   attrition_log <- log_attrition(attrition_log, "Has HL diagnosis", n_distinct(filtered$ID))
#
# Note: Pass PATIENT counts (unique IDs), not row counts (per D-17)
#
# ==============================================================================

library(glue)

#' Initialize attrition log data frame
#'
#' Creates an empty data frame with standardized columns for tracking
#' patient attrition through cohort filter steps.
#'
#' @return Data frame with columns: step, n_before, n_after, n_excluded, pct_excluded
#'
#' @examples
#' attrition_log <- init_attrition_log()
#'
init_attrition_log <- function() {
  data.frame(
    step = character(),
    n_before = integer(),
    n_after = integer(),
    n_excluded = integer(),
    pct_excluded = numeric(),
    stringsAsFactors = FALSE
  )
}

#' Log attrition step
#'
#' Appends a new row to the attrition log with calculated exclusion statistics.
#' Infers n_before from the previous step's n_after (or uses n_after if first step).
#'
#' @param log_df Existing attrition log data frame
#' @param step_name Character string describing the filter step
#' @param n_after Integer count of patients remaining after this step (unique IDs)
#' @return Updated attrition log data frame with new row appended
#'
#' @examples
#' attrition_log <- init_attrition_log()
#' attrition_log <- log_attrition(attrition_log, "Initial cohort", 5000)
#' attrition_log <- log_attrition(attrition_log, "Has enrollment", 4800)
#'
log_attrition <- function(log_df, step_name, n_after) {

  # Infer n_before from previous step's n_after
  # If this is the first step, n_before = n_after (no exclusions yet)
  if (nrow(log_df) > 0) {
    n_before <- tail(log_df$n_after, 1)
  } else {
    n_before <- n_after  # First step: initial population size
  }

  # Calculate exclusions
  n_excluded <- n_before - n_after
  pct_excluded <- if (n_before > 0) {
    round(100 * n_excluded / n_before, 1)
  } else {
    0
  }

  # Print message to console (per D-22: simple message() calls)
  message(glue(
    "[Attrition] {step_name}: {n_before} -> {n_after} ",
    "({n_excluded} excluded, {pct_excluded}%)"
  ))

  # Create new row
  new_row <- data.frame(
    step = step_name,
    n_before = n_before,
    n_after = n_after,
    n_excluded = n_excluded,
    pct_excluded = pct_excluded,
    stringsAsFactors = FALSE
  )

  # Append and return
  rbind(log_df, new_row)
}

# ==============================================================================
# End of utils_attrition.R
# ==============================================================================
