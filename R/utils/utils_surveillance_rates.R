# ==============================================================================
# utils_surveillance_rates.R -- Phase 166 per-patient modality rate helpers
# ==============================================================================
# Pure functions (no DuckDB, no CONFIG, no setwd) — unit-testable locally.
#
# NA rule (D-04): rate_per_py is NA_real_ when person_years is 0 or NA.
#   Zero-event patients (n_dates_post = 0) are kept; their rate is 0, not NA.
#
# Half-open boundary rule: intervals are half-open on days since anchor (0, X].
#   cut(..., right = TRUE) gives (lo, hi] so day 365 -> Y1 (0,365],
#   day 366 -> Y2 (365,730].
#
# Reconciliation invariant (D-03b): interval person-years summed across Y1/Y2/
#   Y3-5/5+ equal person_years per ID x modality; interval dates sum to
#   n_dates_post_primary. Checked in R/166 driver as QC (not a hard stop).
#
# Contents:
#   build_dated_post_events()    -- option-a filter chain for dated events
#   compute_modality_rates()     -- long rate table per ID x modality
#   rates_wide()                 -- pivot to one row per ID
#   split_followup_intervals()   -- Y1/Y2/Y3-5/5+ breakdown
#   rates_summary()              -- per-modality summary statistics
# ==============================================================================

library(dplyr)
library(tidyr)

# ------------------------------------------------------------------------------
#' Build deduplicated post-anchor primary dated events (option-a reconciliation)
#'
#' Applies the reconciliation contract from 166-AUDIT.md §5:
#'   filter(type_ok, tier == "primary", window == "post") |>
#'   distinct(ID, modality, event_date)
#'
#' This exactly reproduces n_dates_post_primary from build_patient_modality().
#' Anchor day (window == "pre") and post-follow_end dates (window ==
#' "after_followup") are excluded because classify_event_window() in R/147
#' assigns window = "post" only when event_date > hl_anchor_date AND
#' event_date <= follow_end (ANCHOR_DAY_IS_POST = FALSE).
#'
#' @param events_win   Tibble produced by classify_event_window(); must contain
#'   columns: ID, modality, event_date, tier, type_ok, window.
#' @param followup     Tibble with columns ID, hl_anchor_date, follow_end
#'   (used only for documentation / join validation; the window column in
#'   events_win already encodes the anchor and follow_end boundaries).
#' @return Tibble with columns ID, modality, event_date (distinct rows).
# ------------------------------------------------------------------------------
build_dated_post_events <- function(events_win, followup) {
  events_win |>
    dplyr::filter(.data$type_ok, .data$tier == "primary",
                  .data$window == "post") |>
    dplyr::distinct(.data$ID, .data$modality, .data$event_date)
}

# ------------------------------------------------------------------------------
#' Compute per-patient per-modality rate
#'
#' Rate formula: rate_per_py = n / person_years.
#' NA rule (D-04): rate_per_py is NA_real_ when person_years is 0 or NA.
#' Zero-event patients (n_dates_post = 0, person_years > 0) get rate 0.
#' All rows are kept (zero-event patients stay in the denominator).
#'
#' @param patient_modality  Tibble with one row per ID x modality containing
#'   at minimum: ID, modality, <n_dates_col>, person_years.
#' @param n_dates_col  Character name of the numerator column
#'   (e.g. "n_dates_post_primary"). Default "n_dates_post_primary".
#' @return Long tibble: ID, modality, n_dates_post, person_years, rate_per_py.
# ------------------------------------------------------------------------------
compute_modality_rates <- function(patient_modality,
                                   n_dates_col = "n_dates_post_primary") {
  patient_modality |>
    dplyr::rename(n_dates_post = dplyr::all_of(n_dates_col)) |>
    dplyr::mutate(
      rate_per_py = dplyr::if_else(
        is.na(.data$person_years) | .data$person_years == 0,
        NA_real_,
        as.double(.data$n_dates_post) / .data$person_years
      )
    ) |>
    dplyr::select("ID", "modality", "n_dates_post", "person_years",
                  "rate_per_py")
}

# ------------------------------------------------------------------------------
#' Pivot long rate table to wide (one row per ID)
#'
#' @param long   Output of compute_modality_rates().
#' @return Wide tibble with ID plus one column per modality named
#'   <modality>_rate_per_py.
# ------------------------------------------------------------------------------
rates_wide <- function(long) {
  long |>
    tidyr::pivot_wider(
      id_cols     = "ID",
      names_from  = "modality",
      values_from = "rate_per_py",
      names_glue  = "{modality}_rate_per_py"
    )
}

# ------------------------------------------------------------------------------
#' Split follow-up into Y1 / Y2 / Y3-5 / 5+ intervals
#'
#' Half-open boundary rule: intervals are (lo, hi] on days since anchor.
#' Default breaks: c(365, 730, 1825) → labels Y1, Y2, Y3-5, 5+.
#'
#' followed_days = as.numeric(follow_end - hl_anchor_date), floored at 0.
#' Person-time per interval = overlap of (0, followed_days] with each
#' interval boundary, divided by 365.25.
#'
#' Every ID x modality x interval the patient's follow-up reaches is
#' included (with dates_in_interval = 0 for intervals with no events).
#' rate_per_py_interval is NA when person_years_in_interval == 0.
#'
#' @param followup      Tibble: ID, hl_anchor_date, follow_end, person_years.
#' @param events_dated  Tibble: ID, modality, event_date (post-anchor primary).
#' @param breaks        Numeric vector of day-boundary cuts (default c(365,730,1825)).
#' @return Long tibble: ID, modality, interval (factor), dates_in_interval,
#'   person_years_in_interval, rate_per_py_interval.
# ------------------------------------------------------------------------------
split_followup_intervals <- function(followup, events_dated,
                                     breaks = c(365, 730, 1825)) {
  labels <- c("Y1", "Y2", "Y3-5", "5+")

  # All modalities present in events_dated
  all_modalities <- unique(events_dated$modality)
  if (length(all_modalities) == 0) {
    all_modalities <- character(0)
  }

  # Build the full grid of ID x modality x interval that each patient reaches
  interval_bounds <- data.frame(
    interval = factor(labels, levels = labels),
    int_lo   = c(0, breaks),
    int_hi   = c(breaks, Inf)
  )

  followup_aug <- followup |>
    dplyr::mutate(
      followed_days = pmax(
        as.numeric(.data$follow_end - .data$hl_anchor_date), 0
      )
    )

  # For each patient, determine which intervals they reach (followed_days > int_lo)
  # and compute per-interval person-time
  patient_intervals <- followup_aug |>
    dplyr::select("ID", "hl_anchor_date", "followed_days") |>
    tidyr::crossing(interval_bounds) |>
    dplyr::filter(.data$followed_days > .data$int_lo) |>
    dplyr::mutate(
      # Overlap of (int_lo, min(int_hi, followed_days)]
      effective_hi = pmin(.data$int_hi, .data$followed_days),
      person_years_in_interval = (.data$effective_hi - .data$int_lo) / 365.25
    ) |>
    dplyr::select("ID", "interval", "person_years_in_interval", "hl_anchor_date")

  # Expand to ID x modality x interval (zero-date intervals included)
  if (length(all_modalities) > 0) {
    modality_frame <- data.frame(modality = all_modalities,
                                 stringsAsFactors = FALSE)
    grid <- patient_intervals |>
      tidyr::crossing(modality_frame)
  } else {
    grid <- patient_intervals |>
      dplyr::mutate(modality = NA_character_)
  }

  # Classify events into intervals
  events_classified <- events_dated |>
    dplyr::left_join(
      followup_aug |> dplyr::select("ID", "hl_anchor_date"),
      by = "ID"
    ) |>
    dplyr::mutate(
      days_post = as.numeric(.data$event_date - .data$hl_anchor_date)
    ) |>
    dplyr::mutate(
      interval = cut(
        .data$days_post,
        breaks = c(0, breaks, Inf),
        labels = labels,
        right  = TRUE
      )
    ) |>
    dplyr::count(.data$ID, .data$modality, .data$interval,
                 name = "dates_in_interval")

  # Join dates onto the full grid, fill 0 for missing
  result <- grid |>
    dplyr::left_join(events_classified, by = c("ID", "modality", "interval")) |>
    dplyr::mutate(
      dates_in_interval = dplyr::coalesce(.data$dates_in_interval, 0L),
      rate_per_py_interval = dplyr::if_else(
        is.na(.data$person_years_in_interval) |
          .data$person_years_in_interval == 0,
        NA_real_,
        as.double(.data$dates_in_interval) / .data$person_years_in_interval
      )
    ) |>
    dplyr::select("ID", "modality", "interval", "dates_in_interval",
                  "person_years_in_interval", "rate_per_py_interval") |>
    dplyr::arrange(.data$ID, .data$modality, .data$interval)

  result
}

# ------------------------------------------------------------------------------
#' Per-modality summary statistics
#'
#' @param long  Output of compute_modality_rates(): ID, modality, n_dates_post,
#'   person_years, rate_per_py.
#' @return Tibble one row per modality with:
#'   n_patients, n_zero_event, mean/median/q25/q75 of rate_per_py (NA excluded),
#'   pooled_rate = sum(n_dates_post[py > 0]) / sum(person_years[py > 0]).
# ------------------------------------------------------------------------------
rates_summary <- function(long) {
  long |>
    dplyr::group_by(.data$modality) |>
    dplyr::summarise(
      n_patients    = dplyr::n(),
      n_zero_event  = sum(.data$n_dates_post == 0L, na.rm = TRUE),
      mean_rate     = mean(.data$rate_per_py,   na.rm = TRUE),
      median_rate   = stats::median(.data$rate_per_py, na.rm = TRUE),
      q25_rate      = stats::quantile(.data$rate_per_py, 0.25, na.rm = TRUE),
      q75_rate      = stats::quantile(.data$rate_per_py, 0.75, na.rm = TRUE),
      pooled_rate   = sum(.data$n_dates_post[
                            !is.na(.data$person_years) & .data$person_years > 0
                          ], na.rm = TRUE) /
                      sum(.data$person_years[
                            !is.na(.data$person_years) & .data$person_years > 0
                          ], na.rm = TRUE),
      .groups = "drop"
    )
}
