# ==============================================================================
# utils_anthracycline_echo.R -- Phase 166 Plan 03: anthracycline-to-echo helpers
# ==============================================================================
# Pure functions (no DuckDB, no CONFIG, no setwd) — unit-testable locally.
#
# Contents:
#   last_anthracycline_dose()   -- last dose date per ID, first-line and ever
#   echo_time_to_event()        -- TTE tibble with competing-risk factor
#   echo_cif_km()               -- AJ CIF + 1-KM at specified horizons
#   echo_rate_post_dose()       -- per-patient echo rate after last dose
#
# Must-haves (166-03-PLAN.md):
#   - All inputs are tibbles keyed on ID; joins performed inside functions
#   - Primary clock = last included-anthracycline date within first-line episodes
#   - Sensitivity = latest-ever; doxorubicin-only sensitivity also supported
#   - Echo events come from dated_events filtered to the echo modality
#   - First echo counted only if STRICTLY AFTER the last dose
#   - Death (resolved) is the competing event
#   - Patients with follow_end <= last dose are excluded and counted
#   - CIF extracted by state name from fit$states
#   - n at risk reported at 1/2/5 years; NA beyond last observed time
#   - If mitoxantrone patients > 0, CIF/rate sensitivity rows include it
#
# D-08a note: first_line column is absent from treatment_episode_detail_180.rds.
#   last_dose_firstline_dt is computed as max admin_date over all episodes for
#   the included drugs (functionally equivalent to last_dose_ever_dt in this
#   dataset). Documented in the driver as D-166-02 fallback.
#
# Dependencies: dplyr, survival
# ==============================================================================

library(dplyr)

# Helper: safe max(Date) returning NA_Date_ instead of -Inf when no rows
.safe_max_date <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0L) return(as.Date(NA))
  max(x)
}

# ------------------------------------------------------------------------------
#' Last anthracycline dose per patient
#'
#' Returns one row per patient who received any drug in `drugs`.
#' Columns:
#'   ID                    patient identifier
#'   last_dose_firstline_dt  max admin_date where first_line == TRUE (NA if none)
#'   last_dose_ever_dt       max admin_date across all episodes for included drugs
#'
#' D-08a: When first_line is absent (all FALSE/NA), last_dose_firstline_dt is NA
#' for all patients and last_dose_ever_dt holds the usable clock.
#'
#' @param episodes  Tibble: ID, drug_name (after DRUG_NAME_ALIASES collapse),
#'                  admin_date (Date), first_line (logical), episode_id.
#' @param drugs     Character vector of drug names to include in the clock.
#' @return Tibble: ID, last_dose_firstline_dt (Date), last_dose_ever_dt (Date).
# ------------------------------------------------------------------------------
last_anthracycline_dose <- function(episodes, drugs) {
  included <- episodes |>
    dplyr::filter(.data$drug_name %in% drugs)

  if (nrow(included) == 0L) {
    return(tibble::tibble(
      ID                    = character(0),
      last_dose_firstline_dt = as.Date(character(0)),
      last_dose_ever_dt      = as.Date(character(0))
    ))
  }

  firstline_doses <- included |>
    dplyr::filter(.data$first_line == TRUE) |>
    dplyr::group_by(.data$ID) |>
    dplyr::summarise(
      last_dose_firstline_dt = .safe_max_date(.data$admin_date),
      .groups = "drop"
    )

  ever_doses <- included |>
    dplyr::group_by(.data$ID) |>
    dplyr::summarise(
      last_dose_ever_dt = .safe_max_date(.data$admin_date),
      .groups = "drop"
    )

  ever_doses |>
    dplyr::left_join(firstline_doses, by = "ID") |>
    dplyr::select("ID", "last_dose_firstline_dt", "last_dose_ever_dt")
}

# ------------------------------------------------------------------------------
#' Build time-to-event tibble for first post-dose echo (competing risk: death)
#'
#' @param doses        Output of last_anthracycline_dose(); one row per ID.
#' @param echo_events  Tibble: ID, modality (unused; caller pre-filters),
#'                     event_date (Date).
#' @param followup     Tibble: ID, hl_anchor_date (Date), follow_end (Date).
#' @param deaths       Tibble: ID, death_date_resolved (Date).
#' @param dose_col     Name of the dose-date column in `doses` to use as the
#'                     clock start. Default "last_dose_firstline_dt".
#' @return Named list:
#'   data                       Tibble with one row per analysable patient:
#'     ID, dose_date, first_echo, follow_end, death_date_resolved,
#'     time_days (numeric), event_status (chr), event_factor (factor).
#'   n_no_time_after_last_dose  Count of patients with follow_end <= dose_date.
# ------------------------------------------------------------------------------
echo_time_to_event <- function(doses, echo_events, followup, deaths,
                               dose_col = "last_dose_firstline_dt") {

  # Rename chosen dose column to a fixed name for joining
  doses_clean <- doses |>
    dplyr::rename(dose_date = dplyr::all_of(dose_col)) |>
    dplyr::filter(!is.na(.data$dose_date)) |>
    dplyr::select("ID", "dose_date")

  # Join followup
  df <- doses_clean |>
    dplyr::inner_join(
      followup |> dplyr::select("ID", "follow_end"),
      by = "ID"
    )

  # Join deaths (left join; NA when no death recorded)
  df <- df |>
    dplyr::left_join(
      deaths |> dplyr::select("ID", "death_date_resolved"),
      by = "ID"
    )

  # Exclude patients with no usable time (follow_end <= dose_date)
  n_no_time <- sum(df$follow_end <= df$dose_date, na.rm = TRUE)
  df <- df |> dplyr::filter(.data$follow_end > .data$dose_date)

  # First echo STRICTLY AFTER dose_date and <= follow_end
  first_echo_tbl <- echo_events |>
    dplyr::select("ID", "event_date") |>
    dplyr::inner_join(
      df |> dplyr::select("ID", "dose_date", "follow_end"),
      by = "ID"
    ) |>
    dplyr::filter(
      .data$event_date > .data$dose_date,
      .data$event_date <= .data$follow_end
    ) |>
    dplyr::group_by(.data$ID) |>
    dplyr::summarise(first_echo = min(.data$event_date), .groups = "drop")

  df <- df |>
    dplyr::left_join(first_echo_tbl, by = "ID")

  # Determine event status and time
  df <- df |>
    dplyr::mutate(
      event_status = dplyr::case_when(
        !is.na(.data$first_echo)
          ~ "echo",
        !is.na(.data$death_date_resolved) &
          .data$death_date_resolved > .data$dose_date &
          .data$death_date_resolved <= .data$follow_end
          ~ "death",
        TRUE
          ~ "censored"
      ),
      time_days = as.numeric(dplyr::case_when(
        .data$event_status == "echo"   ~ .data$first_echo - .data$dose_date,
        .data$event_status == "death"  ~ .data$death_date_resolved - .data$dose_date,
        TRUE                           ~ .data$follow_end - .data$dose_date
      )),
      event_factor = factor(.data$event_status,
                            levels = c("censored", "echo", "death"))
    )

  list(
    data                      = df,
    n_no_time_after_last_dose = n_no_time
  )
}

# ------------------------------------------------------------------------------
#' Aalen-Johansen CIF and 1-KM at specified horizons
#'
#' @param tte       Output of echo_time_to_event()$data; must contain
#'                  time_days (numeric) and event_factor (factor with levels
#'                  c("censored","echo","death")).
#' @param horizons  Numeric vector of day horizons. Default c(365, 730, 1825).
#' @return Tibble: horizon_days, cif_aj, one_minus_km, n_risk.
#'   CIF and 1-KM are set to NA for horizons > max(time_days).
# ------------------------------------------------------------------------------
echo_cif_km <- function(tte, horizons = c(365, 730, 1825)) {
  if (!requireNamespace("survival", quietly = TRUE)) {
    stop("Package 'survival' is required. Install with: renv::install('survival'); renv::snapshot()")
  }

  max_time <- max(tte$time_days, na.rm = TRUE)

  # Aalen-Johansen: survfit with factor event (censored, echo, death)
  aj_fit  <- survival::survfit(
    survival::Surv(time_days, event_factor) ~ 1,
    data = tte
  )

  # Extract the echo-column position from fit$states
  echo_state_idx <- which(aj_fit$states == "echo")
  if (length(echo_state_idx) == 0L) {
    stop("'echo' not found in fit$states: ", paste(aj_fit$states, collapse = ", "))
  }

  aj_sum  <- summary(aj_fit, times = horizons, extend = TRUE)

  # pstate is a matrix [time x state]; extract echo column
  cif_aj_vals <- aj_sum$pstate[, echo_state_idx]
  n_risk_vals <- aj_sum$n.risk

  # 1 - KM: treat echo as binary event (deaths censored)
  km_fit  <- survival::survfit(
    survival::Surv(time_days, event_factor == "echo") ~ 1,
    data = tte
  )
  km_sum  <- summary(km_fit, times = horizons, extend = TRUE)

  # Match summary times to requested horizons (some may be absent if beyond data)
  match_times <- function(requested, actual, values) {
    sapply(requested, function(h) {
      idx <- which(actual == h)
      if (length(idx) == 0L) NA_real_ else values[idx[1L]]
    })
  }

  one_minus_km_vals <- 1 - match_times(horizons, km_sum$time, km_sum$surv)
  n_risk_matched    <- match_times(horizons, aj_sum$time, n_risk_vals)

  # Set to NA for horizons beyond max observed time
  beyond <- horizons > max_time
  cif_aj_vals[beyond]      <- NA_real_
  one_minus_km_vals[beyond] <- NA_real_
  n_risk_matched[beyond]    <- NA_real_

  tibble::tibble(
    horizon_days = horizons,
    cif_aj       = cif_aj_vals,
    one_minus_km = one_minus_km_vals,  # label: "overestimate: deaths censored"
    n_risk       = n_risk_matched
  )
}

# ------------------------------------------------------------------------------
#' Per-patient echo rate after last anthracycline dose
#'
#' Rate = echo dates strictly after dose_date and <= follow_end, divided by
#' person-years from dose_date to follow_end. NA when person-time <= 0.
#'
#' @param doses        Output of last_anthracycline_dose().
#' @param echo_events  Tibble: ID, event_date (Date).
#' @param followup     Tibble: ID, hl_anchor_date (Date), follow_end (Date).
#' @param dose_col     Name of dose date column in `doses`. Default "last_dose_firstline_dt".
#' @return Long tibble: ID, modality, n_dates_post, person_years, rate_per_py.
#   Matches the shape of Plan 02's long rate table.
# ------------------------------------------------------------------------------
echo_rate_post_dose <- function(doses, echo_events, followup,
                                dose_col = "last_dose_firstline_dt") {

  doses_clean <- doses |>
    dplyr::rename(dose_date = dplyr::all_of(dose_col)) |>
    dplyr::filter(!is.na(.data$dose_date)) |>
    dplyr::select("ID", "dose_date")

  # Join followup to get follow_end
  df <- doses_clean |>
    dplyr::left_join(
      followup |> dplyr::select("ID", "follow_end"),
      by = "ID"
    ) |>
    dplyr::mutate(
      person_years = dplyr::if_else(
        is.na(.data$follow_end) | .data$follow_end <= .data$dose_date,
        NA_real_,
        as.numeric(.data$follow_end - .data$dose_date) / 365.25
      )
    )

  # Count echoes strictly after dose_date and <= follow_end
  echo_counts <- echo_events |>
    dplyr::select("ID", "event_date") |>
    dplyr::inner_join(
      df |> dplyr::select("ID", "dose_date", "follow_end"),
      by = "ID"
    ) |>
    dplyr::filter(
      .data$event_date > .data$dose_date,
      .data$event_date <= .data$follow_end
    ) |>
    dplyr::group_by(.data$ID) |>
    dplyr::summarise(n_dates_post = dplyr::n_distinct(.data$event_date),
                     .groups = "drop")

  df <- df |>
    dplyr::left_join(echo_counts, by = "ID") |>
    dplyr::mutate(
      n_dates_post = dplyr::coalesce(.data$n_dates_post, 0L),
      rate_per_py  = dplyr::if_else(
        is.na(.data$person_years) | .data$person_years <= 0,
        NA_real_,
        as.double(.data$n_dates_post) / .data$person_years
      ),
      modality     = "echo_post_anthracycline"
    ) |>
    dplyr::select("ID", "modality", "n_dates_post", "person_years", "rate_per_py")

  df
}
