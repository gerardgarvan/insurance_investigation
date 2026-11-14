# ==============================================================================
# utils/utils_regimen.R -- Regimen classification and line-of-therapy helpers
# ==============================================================================
#
# Purpose:
#   Pure functions for assigning regimen labels and line-of-therapy (LOT) numbers
#   to treatment episode data frames. No I/O, no side effects. Intended to be
#   sourced via R/00_config.R auto-sourcing. Phase: 205.
#
# Inputs:
#   - None (utility function library, not a standalone script)
#
# Outputs:
#   - None (defines functions loaded into calling scripts' environment)
#
# Dependencies:
#   - dplyr: group_by, arrange, mutate, summarise
#   - tibble: tibble construction
#   - R/00_config.R: REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS, LOT_GAP_DAYS,
#                    MAINTENANCE_DRUG_CLASSES
#
# Requirements: REGL-01, REGL-02, REGL-03, REGL-04, REGL-08
#
# ==============================================================================


# ------------------------------------------------------------------------------
# match_regimen_family()
# Internal helper: test whether a character vector of canonical drug names
# satisfies a single REGIMEN_DICT family definition.
#
# Args:
#   canonical_drugs  character vector — drugs present in the episode window
#   family_def       one element of REGIMEN_DICT (a list with $drugs, $exclusive)
#
# Returns: TRUE/FALSE
# ------------------------------------------------------------------------------
match_regimen_family <- function(canonical_drugs, family_def) {
  required   <- family_def$drugs
  exclusive  <- isTRUE(family_def$exclusive)

  # All required drugs must be present (case-insensitive).
  all_present <- all(tolower(required) %in% tolower(canonical_drugs))
  if (!all_present) return(FALSE)

  # For exclusive families, no drug outside the required set may be present.
  # Compare lowercased drug tokens; ignore drugs that ARE in the required set.
  if (exclusive) {
    extra <- setdiff(tolower(canonical_drugs), tolower(required))
    if (length(extra) > 0L) return(FALSE)
  }

  TRUE
}


# ------------------------------------------------------------------------------
# assign_regimen()
# REGL-01, REGL-02, REGL-04
#
# Given a date-level drug administration data frame, identifies which regimen
# family each episode belongs to by matching the drugs present within
# window_days of the episode start date against REGIMEN_DICT.
#
# Treatment type filtering: immunotherapy rows ARE processed alongside
# chemotherapy rows (REGL-04 — BV, nivolumab are immuno-chemo combos).
#
# Args:
#   date_level_df  data frame with columns:
#                    ID             patient identifier
#                    treatment_date Date — drug administration date
#                    treatment_type character — e.g. "Chemotherapy", "Immunotherapy"
#                    canonical_drug character — canonical drug name
#                    episode_number integer or character — episode identifier
#                    start_date     Date — episode start date
#
#   regimen_dict   named list — defaults to REGIMEN_DICT from R/00_config.R
#   window_days    integer — half-width of concurrency window in days;
#                  defaults to CONCURRENCY_WINDOW_DAYS
#
# Returns: tibble with one row per (ID, episode_number):
#   ID, episode_number, regimen_label (character)
# ------------------------------------------------------------------------------
assign_regimen <- function(date_level_df,
                           regimen_dict  = REGIMEN_DICT,
                           window_days   = CONCURRENCY_WINDOW_DAYS) {

  stopifnot(
    is.data.frame(date_level_df),
    all(c("ID", "treatment_date", "canonical_drug",
          "episode_number", "start_date") %in% names(date_level_df)),
    is.numeric(window_days) || is.integer(window_days),
    length(window_days) == 1L
  )

  # For each episode, collect drugs within the concurrency window.
  episode_drugs <- date_level_df %>%
    dplyr::mutate(
      days_from_start = as.integer(.data$treatment_date - .data$start_date)
    ) %>%
    dplyr::filter(
      .data$days_from_start >= -as.integer(window_days) &
      .data$days_from_start <=  as.integer(window_days)
    ) %>%
    dplyr::group_by(.data$ID, .data$episode_number) %>%
    dplyr::summarise(
      drugs_in_window = list(unique(.data$canonical_drug[!is.na(.data$canonical_drug)])),
      .groups = "drop"
    )

  # Match each episode's drug set against REGIMEN_DICT in order.
  episode_drugs <- episode_drugs %>%
    dplyr::mutate(
      regimen_label = vapply(.data$drugs_in_window, function(drug_vec) {
        for (family_name in names(regimen_dict)) {
          if (match_regimen_family(drug_vec, regimen_dict[[family_name]])) {
            return(family_name)
          }
        }
        "Other"
      }, character(1L))
    ) %>%
    dplyr::select("ID", "episode_number", "regimen_label")

  episode_drugs
}


# ------------------------------------------------------------------------------
# assign_lot()
# REGL-03
#
# Assigns a line-of-therapy (LOT) integer to each episode per patient.
# Rules:
#   1. LOT starts at 1 for the first episode.
#   2. LOT increments when the gap from the previous episode's end_date to the
#      current episode's start_date is >= lot_gap_days AND the new episode's
#      regimen_label is NOT in maintenance_classes.
#   3. Post-SCT episodes: start_date > sct_date triggers a LOT increment
#      regardless of gap length (SCT resets therapy counting).
#   4. Maintenance episodes (regimen_label in maintenance_classes) inherit the
#      current LOT — never increment.
#
# Args:
#   episode_df         data frame with columns:
#                        ID             patient identifier
#                        episode_number integer or character
#                        start_date     Date
#                        end_date       Date
#                        regimen_label  character (from assign_regimen())
#
#   lot_gap_days       integer — treatment-free gap to trigger new LOT;
#                      defaults to LOT_GAP_DAYS
#   maintenance_classes character — regimen labels that never start a new LOT;
#                      defaults to MAINTENANCE_DRUG_CLASSES
#   sct_dates_df       NULL or data frame with (ID, sct_date Date).
#                      NULL if no SCT patients in the cohort subset.
#
# Returns: episode_df with added column line_of_therapy (integer).
# ------------------------------------------------------------------------------
assign_lot <- function(episode_df,
                       lot_gap_days        = LOT_GAP_DAYS,
                       maintenance_classes = MAINTENANCE_DRUG_CLASSES,
                       sct_dates_df        = NULL) {

  stopifnot(
    is.data.frame(episode_df),
    all(c("ID", "episode_number", "start_date", "end_date",
          "regimen_label") %in% names(episode_df)),
    is.numeric(lot_gap_days) || is.integer(lot_gap_days),
    length(lot_gap_days) == 1L,
    is.character(maintenance_classes),
    is.null(sct_dates_df) || (is.data.frame(sct_dates_df) &&
      all(c("ID", "sct_date") %in% names(sct_dates_df)))
  )

  # Attach earliest SCT date per patient (NULL-safe).
  if (!is.null(sct_dates_df) && nrow(sct_dates_df) > 0L) {
    earliest_sct <- sct_dates_df %>%
      dplyr::group_by(.data$ID) %>%
      dplyr::summarise(earliest_sct = min(.data$sct_date, na.rm = TRUE),
                       .groups = "drop")
    episode_df <- dplyr::left_join(episode_df, earliest_sct, by = "ID")
  } else {
    episode_df <- dplyr::mutate(episode_df, earliest_sct = as.Date(NA))
  }

  # Sort episodes per patient by start_date, then compute LOT.
  episode_df <- episode_df %>%
    dplyr::arrange(.data$ID, .data$start_date, .data$episode_number) %>%
    dplyr::group_by(.data$ID) %>%
    dplyr::mutate(
      line_of_therapy = {
        n_ep      <- dplyr::n()
        lot_vec   <- integer(n_ep)
        lot_vec[1] <- 1L
        if (n_ep > 1L) {
          for (i in seq(2L, n_ep)) {
            prev_end    <- .data$end_date[i - 1L]
            curr_start  <- .data$start_date[i]
            curr_label  <- .data$regimen_label[i]
            is_maint    <- curr_label %in% maintenance_classes

            # Maintenance episodes inherit current LOT.
            if (is_maint) {
              lot_vec[i] <- lot_vec[i - 1L]
              next
            }

            # Post-SCT: increment if start_date > earliest_sct.
            sct_date_val <- .data$earliest_sct[1L]
            post_sct <- !is.na(sct_date_val) && curr_start > sct_date_val &&
                        (i == 2L || .data$start_date[i - 1L] <= sct_date_val)

            # Gap rule.
            gap_days <- as.integer(curr_start - prev_end)
            gap_trigger <- !is.na(gap_days) && gap_days >= as.integer(lot_gap_days)

            if (post_sct || gap_trigger) {
              lot_vec[i] <- lot_vec[i - 1L] + 1L
            } else {
              lot_vec[i] <- lot_vec[i - 1L]
            }
          }
        }
        lot_vec
      }
    ) %>%
    dplyr::ungroup() %>%
    dplyr::select(-"earliest_sct")

  episode_df
}
