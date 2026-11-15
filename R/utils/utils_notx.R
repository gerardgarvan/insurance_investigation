# ==============================================================================
# utils/utils_notx.R -- Phase 203 no-treatment reason assignment (pure functions)
# ==============================================================================
# Used by R/203_no_treatment_characterization.R. Pure data-frame logic so it can
# be unit tested with synthetic data (tests/testthat/test-203-notx.R).

# Waterfall reasons for no_tx patients, in first-match order.
NOTX_REASON_LEVELS <- c(
  "TR says treated (missed by pipeline)",
  "Dx before EHR coverage (first encounter > dx + 90d)",
  "Short follow-up (< 180d after dx)",
  "Multi-source care",
  "Far from care (> 100 mi, post-anchor)",
  "NLPHL (watch-and-wait plausible)",
  "Unexplained"
)

NOTX_COVERAGE_GRACE_DAYS <- 90L
NOTX_MIN_FOLLOWUP_DAYS   <- 180L

#' Derive the six non-exclusive reason flags.
#' @param df has first_hl_dx_date, first_enc_date, followup_days,
#'   single_source_care (0/1/NA), far_any_post (lgl/NA), nlphl_any (lgl/NA),
#'   tr_any_tx_given (lgl/NA)
#' @return df with f_tr_treated, f_dx_before_coverage, f_short_followup,
#'   f_multi_source, f_far_from_care, f_nlphl (all non-NA logical)
add_notx_flags <- function(df) {
  df |>
    dplyr::mutate(
      f_tr_treated = df$tr_any_tx_given %in% TRUE,
      # no usable encounter (all missing or sentinel) counts as no EHR coverage
      f_dx_before_coverage = !is.na(df$first_hl_dx_date) &
        (is.na(df$first_enc_date) |
           df$first_enc_date > df$first_hl_dx_date + NOTX_COVERAGE_GRACE_DAYS),
      f_short_followup = !is.na(df$followup_days) &
        df$followup_days < NOTX_MIN_FOLLOWUP_DAYS,
      f_multi_source   = df$single_source_care %in% 0L,
      f_far_from_care  = df$far_any_post %in% TRUE,
      f_nlphl          = df$nlphl_any %in% TRUE
    )
}

#' First-match mutually exclusive reason (factor in NOTX_REASON_LEVELS order).
#' @param df output of add_notx_flags()
assign_notx_reason <- function(df) {
  reason <- dplyr::case_when(
    df$f_tr_treated          ~ NOTX_REASON_LEVELS[1],
    df$f_dx_before_coverage  ~ NOTX_REASON_LEVELS[2],
    df$f_short_followup      ~ NOTX_REASON_LEVELS[3],
    df$f_multi_source        ~ NOTX_REASON_LEVELS[4],
    df$f_far_from_care       ~ NOTX_REASON_LEVELS[5],
    df$f_nlphl               ~ NOTX_REASON_LEVELS[6],
    TRUE                     ~ NOTX_REASON_LEVELS[7]
  )
  factor(reason, levels = NOTX_REASON_LEVELS)
}
