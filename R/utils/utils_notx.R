# ==============================================================================
# utils/utils_notx.R -- Phase 203 no-treatment reason assignment (pure functions)
# ==============================================================================
# Used by R/203_no_treatment_characterization.R. Pure data-frame logic so it can
# be unit tested with synthetic data (tests/testthat/test-203-notx.R).

# Waterfall reasons for no_tx patients, in first-match order (quick 261114-rbs).
# Multi-source care and far-from-care are NOT reasons: they are more common among
# treated patients, so they are reported as non-exclusive flags only.
NOTX_REASON_LEVELS <- c(
  "TR says treated (missed by pipeline)",
  "Probable prevalent / history-of HL",
  "Short follow-up (< 180d after dx)",
  "Dx before EHR coverage (first encounter > dx + 90d)",
  "NLPHL only (watch-and-wait plausible)",
  "Unexplained"
)

NOTX_COVERAGE_GRACE_DAYS <- 90L
NOTX_MIN_FOLLOWUP_DAYS   <- 180L
NOTX_HISTORY_GRACE_DAYS  <- 30L   # history-of-HL code counts if on/before dx + 30d
NOTX_TR_EARLY_DX_DAYS    <- 365L  # TR dx date > 365d before first_hl_dx_date

#' Derive the non-exclusive reason flags.
#' @param df has first_hl_dx_date, first_enc_date, followup_days,
#'   single_source_care (0/1/NA), far_any_post (lgl/NA), nlphl_any, nlphl_only
#'   (lgl/NA), tr_any_tx_given (lgl/NA), first_hist_dx_date (Date/NA; earliest
#'   personal-history-of-HL code), tr_dx_date (Date/NA; earliest TR HL dx date)
#' @return df with f_tr_treated, f_hist_code, f_tr_early_dx, f_prevalent_hl,
#'   f_dx_before_coverage, f_short_followup, f_multi_source, f_far_from_care,
#'   f_nlphl_any, f_nlphl_only (all non-NA logical)
add_notx_flags <- function(df) {
  df |>
    dplyr::mutate(
      f_tr_treated = df$tr_any_tx_given %in% TRUE,
      # (a) Z85.71 / V10.72 on or before first HL dx + 30d
      f_hist_code = !is.na(df$first_hist_dx_date) & !is.na(df$first_hl_dx_date) &
        df$first_hist_dx_date <= df$first_hl_dx_date + NOTX_HISTORY_GRACE_DAYS,
      # (b) TR diagnosis date more than 365d before first HL dx in the data
      f_tr_early_dx = !is.na(df$tr_dx_date) & !is.na(df$first_hl_dx_date) &
        as.integer(df$first_hl_dx_date - df$tr_dx_date) > NOTX_TR_EARLY_DX_DAYS,
      f_prevalent_hl = f_hist_code | f_tr_early_dx,
      # no usable encounter (all missing or sentinel) counts as no EHR coverage
      f_dx_before_coverage = !is.na(df$first_hl_dx_date) &
        (is.na(df$first_enc_date) |
           df$first_enc_date > df$first_hl_dx_date + NOTX_COVERAGE_GRACE_DAYS),
      f_short_followup = !is.na(df$followup_days) &
        df$followup_days < NOTX_MIN_FOLLOWUP_DAYS,
      f_multi_source   = df$single_source_care %in% 0L,
      f_far_from_care  = df$far_any_post %in% TRUE,
      f_nlphl_any      = df$nlphl_any %in% TRUE,
      f_nlphl_only     = df$nlphl_only %in% TRUE
    )
}

#' First-match mutually exclusive reason (factor in NOTX_REASON_LEVELS order).
#' @param df output of add_notx_flags()
assign_notx_reason <- function(df) {
  reason <- dplyr::case_when(
    df$f_tr_treated          ~ NOTX_REASON_LEVELS[1],
    df$f_prevalent_hl        ~ NOTX_REASON_LEVELS[2],
    df$f_short_followup      ~ NOTX_REASON_LEVELS[3],
    df$f_dx_before_coverage  ~ NOTX_REASON_LEVELS[4],
    df$f_nlphl_only          ~ NOTX_REASON_LEVELS[5],
    TRUE                     ~ NOTX_REASON_LEVELS[6]
  )
  factor(reason, levels = NOTX_REASON_LEVELS)
}
