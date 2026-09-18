# ==============================================================================
# utils_distance_hist.R -- Distance histogram helpers (Phase 154)
# ==============================================================================
# Functions:
#   bin_distance()           -- cut distance_mi into histogram bins (linear or log)
#   plot_distance_hist()     -- ggplot2 bar chart with UF brand colors
#   make_distance_histograms() -- produce 4 PNGs + return bin tibble + stats
#   summarise_distance()     -- compute n/median/IQR/p90/p95/p99/max_mi by breakout
#
# Source: bin_distance / plot_distance_hist / make_distance_histograms are
# from Appendix B of MILESTONE_encounter_distance.md, with one addition:
# bin_distance() returns an empty bin table on empty input instead of erroring.
# summarise_distance() is new in Phase 154.
# Dependencies: dplyr, tibble, ggplot2 (all namespace-qualified). No lubridate.
#
# Called from: R/122_encounter_distance.R SECTION 1 (after utils_zip_calendar.R)
# ==============================================================================

# UF brand colors (locked for this deliverable; do not source utils_pptx.R)
UF_BLUE   <- "#0021A5"
UF_ORANGE <- "#FA4616"

# ------------------------------------------------------------------------------
#' Cut distance_mi values into histogram bins.
#'
#' @param mi     Numeric vector of distances in miles.
#' @param scale  "linear" (5-mile bins up to 300 mi then Inf) or
#'               "log"    (0.25-unit log10(1+mi) bins).
#' @param width  Bin width for linear scale (default 5 miles).
#' @param cap    Upper cap for linear bins before the Inf tail (default 300).
#' @return tibble with columns: bin, lower, upper, lower_mi, upper_mi, n, pct, scale.
bin_distance <- function(mi, scale = c("linear", "log"), width = 5, cap = 300) {
  scale <- match.arg(scale)
  mi <- mi[!is.na(mi)]
  if (length(mi) == 0L) {
    return(tibble::tibble(bin = character(0), lower = numeric(0), upper = numeric(0),
                          n = integer(0), pct = numeric(0), scale = character(0),
                          lower_mi = numeric(0), upper_mi = numeric(0)))
  }
  if (scale == "linear") {
    edges <- c(seq(0, cap, by = width), Inf)
    x <- mi
  } else {
    # Upper edge strictly above the max so a value exactly on a 0.25 boundary
    # (e.g. 9 mi -> log10(10) = 1) and the all-zero case (max_log = 0) both
    # yield >= 2 edges. include.lowest = TRUE would also cover the boundary
    # case, but the explicit form is clearer and covers all-zero.
    max_log <- max(log10(1 + mi))
    edges <- seq(0, (floor(max_log / 0.25) + 1) * 0.25, by = 0.25)
    x <- log10(1 + mi)
  }
  cut_x <- cut(x, breaks = edges, right = FALSE, include.lowest = TRUE)
  tibble::tibble(bin = levels(cut_x),
                 lower = head(edges, -1),
                 upper = tail(edges, -1)) |>
    dplyr::left_join(tibble::as_tibble(table(bin = cut_x)), by = "bin") |>
    dplyr::mutate(n = dplyr::coalesce(as.integer(n), 0L),
                  pct = 100 * n / sum(n),
                  scale = scale,
                  lower_mi = if (scale == "log") 10^lower - 1 else lower,
                  upper_mi = if (scale == "log") 10^upper - 1 else upper)
}

# ------------------------------------------------------------------------------
#' Plot a distance histogram with UF brand colors.
#'
#' @param bins     tibble from bin_distance().
#' @param stats    tibble with columns n, n_excluded, median, p90, n_zero.
#' @param level    "encounter" or "patient" (controls axis label).
#' @param cutoffs  Optional numeric vector of candidate cutoffs in miles (dotted lines).
#' @param run_date Date string for caption.
#' @return ggplot2 object.
plot_distance_hist <- function(bins, stats, level = c("encounter", "patient"),
                               cutoffs = NULL, run_date = Sys.Date()) {
  level <- match.arg(level)
  is_log <- unique(bins$scale) == "log"
  bins <- bins |> dplyr::mutate(mid = (lower + pmin(upper, lower + (upper - lower))) / 2)
  if (!is_log) bins$mid[is.infinite(bins$upper)] <- max(bins$lower) + (bins$lower[2] - bins$lower[1]) / 2
  xf <- if (is_log) function(v) log10(1 + v) else identity
  p <- ggplot2::ggplot(bins, ggplot2::aes(x = mid, y = n)) +
    ggplot2::geom_col(width = diff(bins$lower)[1], fill = UF_BLUE, colour = "white", linewidth = 0.2) +
    ggplot2::geom_vline(xintercept = xf(stats$median), colour = UF_ORANGE, linewidth = 0.8) +
    ggplot2::geom_vline(xintercept = xf(stats$p90),    colour = UF_ORANGE, linewidth = 0.8, linetype = "dashed") +
    ggplot2::labs(
      x = if (is_log) "Distance, miles (log10(1 + mi) scale)" else "Distance, miles",
      y = if (level == "encounter") "Encounters" else "Patients",
      title = sprintf("Patient-to-encounter distance, %s level", level),
      subtitle = sprintf("n = %s; median %.1f mi (solid), 90th percentile %.1f mi (dashed)",
                         format(stats$n, big.mark = ","), stats$median, stats$p90),
      caption = sprintf("Distance: zipcodeR::zip_distance() on ZIP5 centroids. Excludes %s %ss with no computable distance. Run %s.",
                        format(stats$n_excluded, big.mark = ","), level, run_date)
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(plot.caption = ggplot2::element_text(hjust = 0, colour = "grey30"))
  if (!is.null(cutoffs))
    p <- p + ggplot2::geom_vline(xintercept = xf(cutoffs), colour = UF_ORANGE, linetype = "dotted", linewidth = 0.6)
  if (is_log) {
    ticks <- c(0, 1, 5, 10, 25, 50, 100, 250, 500, 1000)
    p <- p + ggplot2::scale_x_continuous(breaks = log10(1 + ticks), labels = ticks)
  }
  p
}

# ------------------------------------------------------------------------------
#' Produce 4 histogram PNGs and return bin tibble + stats tibble.
#'
#' @param dist     enc_distance tibble (must have columns distance_status, distance_mi, ID).
#' @param out_dir  Output directory; PNGs go to out_dir/figures/.
#' @param run_date Date string used in file names (default today YYYYMMDD).
#' @param cutoffs  Optional numeric vector of candidate cutoffs in miles.
#' @return list(bins = <tibble>, stats = <tibble with level column>).
make_distance_histograms <- function(dist, out_dir, run_date = format(Sys.Date(), "%Y%m%d"),
                                     cutoffs = NULL) {
  dir.create(file.path(out_dir, "figures"), showWarnings = FALSE, recursive = TRUE)
  enc <- dist |> dplyr::filter(distance_status == "computed")
  if (nrow(enc) == 0L) {
    warning("make_distance_histograms(): no computed rows; no PNGs written")
    empty_bins <- bin_distance(numeric(0)) |> dplyr::mutate(level = character(0), .before = 1)
    return(list(bins = empty_bins,
                stats = tibble::tibble(level = c("encounter", "patient"), n = 0L,
                                       n_excluded = c(nrow(dist), dplyr::n_distinct(dist$ID)),
                                       median = NA_real_, p90 = NA_real_, n_zero = 0L)))
  }
  pat <- enc |> dplyr::group_by(ID) |> dplyr::summarise(distance_mi = median(distance_mi), .groups = "drop")
  summ <- function(d, n_total) tibble::tibble(
    n = nrow(d), n_excluded = n_total - nrow(d),
    median = median(d$distance_mi), p90 = quantile(d$distance_mi, .90),
    n_zero = sum(d$distance_mi == 0))
  levels <- list(
    encounter = list(d = enc, stats = summ(enc, nrow(dist))),
    patient   = list(d = pat, stats = summ(pat, dplyr::n_distinct(dist$ID))))
  bins_out <- list()
  for (lv in names(levels)) {
    for (sc in c("linear", "log")) {
      b <- bin_distance(levels[[lv]]$d$distance_mi, scale = sc)
      bins_out[[paste(lv, sc)]] <- dplyr::mutate(b, level = lv, .before = 1)
      g <- plot_distance_hist(b, levels[[lv]]$stats, level = lv, cutoffs = cutoffs, run_date = run_date)
      ggplot2::ggsave(file.path(out_dir, "figures", sprintf("encounter_distance_hist_%s_%s_%s.png", lv, sc, run_date)),
                      g, width = 8, height = 5, dpi = 300, bg = "white")
    }
  }
  list(bins = dplyr::bind_rows(bins_out),
       stats = dplyr::bind_rows(lapply(levels, `[[`, "stats"), .id = "level"))
}

# ------------------------------------------------------------------------------
#' Summarise distance_mi for computed encounters, with a breakout label column.
#'
#' @param enc_distance tibble with columns distance_status, distance_mi, ADMIT_DATE,
#'                     ENC_TYPE, facility_state.
#' @param by           One of "overall", "year", "ENC_TYPE", "facility_state".
#' @return tibble with columns breakout, n, median_mi, IQR_mi, p90_mi, p95_mi, p99_mi, max_mi.
summarise_distance <- function(enc_distance, by = c("overall", "year", "ENC_TYPE", "facility_state")) {
  by <- match.arg(by)

  # Same definition as computed_rows in R/122; the status/NA invariant is asserted upstream.
  computed <- enc_distance |> dplyr::filter(distance_status == "computed")

  .summarise_one <- function(df, label) {
    tibble::tibble(
      breakout   = label,
      n          = nrow(df),
      median_mi  = median(df$distance_mi, na.rm = TRUE),
      IQR_mi     = IQR(df$distance_mi,    na.rm = TRUE),
      p90_mi     = quantile(df$distance_mi, 0.90, na.rm = TRUE),
      p95_mi     = quantile(df$distance_mi, 0.95, na.rm = TRUE),
      p99_mi     = quantile(df$distance_mi, 0.99, na.rm = TRUE),
      max_mi     = max(df$distance_mi,    na.rm = TRUE)
    )
  }

  if (by == "overall") {
    return(.summarise_one(computed, "overall"))
  }

  group_col <- switch(by,
    "year"           = dplyr::mutate(computed, .grp = format(ADMIT_DATE, "%Y")),
    "ENC_TYPE"       = dplyr::mutate(computed, .grp = as.character(ENC_TYPE)),
    "facility_state" = dplyr::mutate(computed, .grp = as.character(facility_state))
  ) |>
    dplyr::mutate(.grp = dplyr::coalesce(.grp, "unmatched"))

  prefix <- switch(by,
    "year"           = "year_",
    "ENC_TYPE"       = "enc_type_",
    "facility_state" = "state_"
  )

  group_col |>
    dplyr::group_by(.grp) |>
    dplyr::group_modify(~ .summarise_one(.x, paste0(prefix, .y$.grp))) |>
    dplyr::ungroup() |>
    dplyr::select(-".grp")
}
