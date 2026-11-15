# ==============================================================================
# utils_tr_sensitivity.R
# ==============================================================================
# Pure helpers for R/202_tr_sensitivity.R (no data access; unit-tested in
# tests/testthat/test-202-tr-sensitivity.R).
#
# Capture tiers (per patient x treatment type), signed diff = TR date - first
# Gantt date:
#   unknown_code / no_registry   TR side (not in denominator)
#   exact / within_30d / within_90d   |diff| <= 0 / 30 / 90   (mutually exclusive)
#   not_datable   TR given by code only, Gantt episode exists
#   no_pipeline   TR given, no Gantt episode of that type
#   pipe_before   Gantt first date > 90 d BEFORE TR date  (diff >  90)
#   pipe_after    Gantt first date > 90 d AFTER  TR date  (diff < -90)
# ==============================================================================

TR_GIVEN_TIERS <- c("exact", "within_30d", "within_90d", "not_datable",
                    "no_pipeline", "pipe_before", "pipe_after")
TR_HIT_TIERS   <- c("exact", "within_30d", "within_90d")
TR_NOTCAP_TIERS <- c("no_pipeline", "pipe_before", "pipe_after")

#' Assign a capture tier from TR status and the two dates.
#' @param tr_status "given" / "unknown" / "not_given"
#' @param tr_date,gantt_date Date vectors (NA allowed)
tr_capture_tier <- function(tr_status, tr_date, gantt_date) {
  diff_d <- as.integer(tr_date - gantt_date)   # >0: Gantt record earlier than TR
  dplyr::case_when(
    tr_status == "unknown"   ~ "unknown_code",
    tr_status != "given"     ~ "no_registry",
    is.na(gantt_date)        ~ "no_pipeline",
    is.na(tr_date)           ~ "not_datable",
    abs(diff_d) == 0L        ~ "exact",
    abs(diff_d) <= 30L       ~ "within_30d",
    abs(diff_d) <= 90L       ~ "within_90d",
    diff_d > 90L             ~ "pipe_before",
    TRUE                     ~ "pipe_after"
  )
}

#' Signed day difference (TR - Gantt) kept only for the two mismatch tiers.
tr_signed_diff <- function(tr_date, gantt_date) as.integer(tr_date - gantt_date)

#' Median and IQR text ("med (Q1-Q3)") of days; absolute values, suppressed if n < 11.
tr_median_iqr <- function(days) {
  days <- abs(days[!is.na(days)])
  if (length(days) < 11L) return(NA_character_)
  q <- stats::quantile(days, c(0.25, 0.5, 0.75), names = FALSE)
  sprintf("%.0f (%.0f-%.0f)", q[2], q[1], q[3])
}

#' Counts for the per-group not-captured split. `df` needs capture_tier and
#' signed_diff. Returns one-row tibble of raw counts + median/IQR text.
tr_summarise_tiers <- function(df) {
  given <- df[df$capture_tier %in% TR_GIVEN_TIERS, , drop = FALSE]
  tibble::tibble(
    n_denom      = nrow(given),
    n_exact      = sum(given$capture_tier == "exact"),
    n_30d        = sum(given$capture_tier %in% c("exact", "within_30d")),
    n_90d        = sum(given$capture_tier %in% TR_HIT_TIERS),
    n_undated    = sum(given$capture_tier == "not_datable"),
    n_no_pipe    = sum(given$capture_tier == "no_pipeline"),
    n_before     = sum(given$capture_tier == "pipe_before"),
    n_after      = sum(given$capture_tier == "pipe_after"),
    med_before   = tr_median_iqr(given$signed_diff[given$capture_tier == "pipe_before"]),
    med_after    = tr_median_iqr(given$signed_diff[given$capture_tier == "pipe_after"])
  )
}

#' Restrict TR-dated rows to dates on/after the patient's first encounter.
#' Undated rows (tr_first_date NA) cannot be placed against the window and are retained.
#' @param df has ID, tr_first_date
#' @param first_enc tibble ID, first_enc_date
#' @return list(in_window = df, n_excluded_pre_encounter, n_no_encounter): patients
#'   with a TR date before first encounter / with a TR date but no ENCOUNTER record
tr_coverage_filter <- function(df, first_enc) {
  j <- dplyr::left_join(df, first_enc, by = "ID")
  dated <- !is.na(j$tr_first_date)
  pre   <- dated & !is.na(j$first_enc_date) & j$tr_first_date < j$first_enc_date
  noenc <- dated & is.na(j$first_enc_date)
  keep  <- !pre & !noenc
  list(
    in_window = j[keep, , drop = FALSE],
    n_excluded_pre_encounter = dplyr::n_distinct(j$ID[pre]),
    n_no_encounter           = dplyr::n_distinct(j$ID[noenc])
  )
}

TR_YEAR_BANDS <- c("<=2009", "2010-2012", "2013-2015", "2016-2018", "2019+")

#' Diagnosis-year band; NA year -> "Unknown".
tr_year_band <- function(yr) {
  out <- dplyr::case_when(
    is.na(yr)   ~ "Unknown",
    yr <= 2009  ~ "<=2009",
    yr <= 2012  ~ "2010-2012",
    yr <= 2015  ~ "2013-2015",
    yr <= 2018  ~ "2016-2018",
    TRUE        ~ "2019+"
  )
  factor(out, levels = c(TR_YEAR_BANDS, "Unknown"))
}

#' Convert tr_hl_dx / tr_nhl_dx from CSV text (blank / "TRUE" / "FALSE") to logical.
tr_flag_to_logical <- function(x) {
  if (is.logical(x)) return(x)
  v <- toupper(trimws(as.character(x)))
  dplyr::case_when(v == "TRUE" ~ TRUE, v == "FALSE" ~ FALSE, TRUE ~ NA)
}
