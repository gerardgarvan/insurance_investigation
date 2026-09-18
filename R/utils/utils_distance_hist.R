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
# Dependencies: dplyr, tibble, ggplot2, scales (ggplot2 dependency); all namespace-qualified. No lubridate.
#
# Called from: R/122_encounter_distance.R SECTION 1 (after utils_zip_calendar.R)
# Log bins (A1, 2026-09-18): [0,1) mi first bin, then quarter-decade bins on log10(mi).
# Linear defaults: 10-mile bins, 350-mile cap (set from R/122; see 154-D7).
# ==============================================================================

# UF brand colors (locked for this deliverable; do not source utils_pptx.R)
UF_BLUE   <- "#0021A5"
UF_ORANGE <- "#FA4616"

# ------------------------------------------------------------------------------
#' Cut distance_mi values into histogram bins.
#'
#' Linear: fixed-width bins from 0 to `cap`, then one open bin [cap, Inf).
#' Log:    first bin is [0, 1) mi (holds same-ZIP zeros and sub-mile pairs);
#'         then quarter-decade bins on log10(mi), so 1, 10, 100, 1000 mi are
#'         bin edges and coincide with the axis ticks.
#'
#' @param mi     Numeric vector of distances in miles (NA dropped).
#' @param scale  "linear" or "log".
#' @param width  Linear bin width in miles (default 10).
#' @param cap    Linear cap in miles; values >= cap go to the open top bin (default 350).
#' @return tibble: bin, lower, upper (axis units: miles for linear, log10(mi) for log;
#'         the log first bin has lower = -0.25, upper = 0), lower_mi, upper_mi, n, pct, scale.
bin_distance <- function(mi, scale = c("linear", "log"), width = 10, cap = 350) {
  scale <- match.arg(scale)
  mi <- mi[!is.na(mi)]
  empty <- tibble::tibble(bin = character(0), lower = numeric(0), upper = numeric(0),
                          n = integer(0), pct = numeric(0), scale = character(0),
                          lower_mi = numeric(0), upper_mi = numeric(0))
  if (length(mi) == 0L) return(empty)
  stopifnot("bin_distance(): negative distances" = all(mi >= 0))

  if (scale == "linear") {
    edges <- c(seq(0, cap, by = width), Inf)
    x <- mi
  } else {
    x <- ifelse(mi < 1, -0.125, log10(mi))
    top <- (floor(max(x) / 0.25) + 1) * 0.25   # strictly above max, >= 0.25
    edges <- c(-0.25, seq(0, top, by = 0.25))
  }
  cut_x <- cut(x, breaks = edges, right = FALSE, include.lowest = TRUE)
  out <- tibble::tibble(bin = levels(cut_x),
                        lower = head(edges, -1),
                        upper = tail(edges, -1)) |>
    dplyr::left_join(tibble::as_tibble(table(bin = cut_x)), by = "bin") |>
    dplyr::mutate(n = dplyr::coalesce(as.integer(n), 0L),
                  pct = 100 * n / sum(n),
                  scale = scale)
  if (scale == "linear") {
    out |> dplyr::mutate(lower_mi = lower, upper_mi = upper)
  } else {
    out |> dplyr::mutate(lower_mi = dplyr::if_else(lower < 0, 0, 10^lower),
                         upper_mi = 10^upper)
  }
}

# ------------------------------------------------------------------------------
#' Plot a distance histogram with UF brand colors.
#'
#' Layout (8 x 5 in, 300 dpi, base_size 12):
#'   - title/subtitle/caption left-aligned to the plot edge (plot.title.position = "plot")
#'     so long strings never clip against the y-axis labels;
#'   - subtitle and caption each on two lines, no line over ~85 characters;
#'   - linear x axis labels the open top bin as "<cap>+"; log x axis ticks sit on
#'     bin edges (1, 3, 10, 30, ...); the sub-1-mile bar is named in the axis title;
#'   - y axis uses comma separators and bars sit on the axis (no lower expansion);
#'   - reference lines are explained in the subtitle, never annotated on the panel.
#'
#' @param bins     tibble from bin_distance().
#' @param stats    tibble with columns n, n_excluded, median, p90, n_zero.
#' @param level    "encounter" or "patient" (controls axis label).
#' @param cutoffs  Optional numeric vector of candidate cutoffs in miles (dotted lines).
#' @param run_date Date string for caption.
#' @return ggplot2 object.
plot_distance_hist <- function(bins, stats, level = c("encounter", "patient"),
                               cutoffs = NULL, run_date = Sys.Date()) {
  level  <- match.arg(level)
  is_log <- unique(bins$scale) == "log"
  unit   <- if (level == "encounter") "encounters" else "patients"
  bw     <- bins$upper[1] - bins$lower[1]                 # bin width in axis units
  cap    <- if (is_log) NA_real_ else max(bins$lower)     # open top bin starts here
  bins   <- bins |>
    dplyr::mutate(mid = ifelse(is.infinite(upper), lower + bw / 2, (lower + upper) / 2))

  xf <- if (is_log) function(v) ifelse(v < 1, -0.125, log10(v)) else identity

  p <- ggplot2::ggplot(bins, ggplot2::aes(x = mid, y = n)) +
    ggplot2::geom_col(width = bw, fill = UF_BLUE, colour = "white", linewidth = 0.2) +
    ggplot2::geom_vline(xintercept = xf(stats$median), colour = UF_ORANGE, linewidth = 0.8) +
    ggplot2::geom_vline(xintercept = xf(stats$p90),    colour = UF_ORANGE, linewidth = 0.8,
                        linetype = "dashed") +
    ggplot2::scale_y_continuous(labels = scales::label_comma(),
                                expand = ggplot2::expansion(mult = c(0, 0.05))) +
    ggplot2::labs(
      x = if (is_log) "Distance, miles (log scale; first bar = under 1 mile)" else "Distance, miles",
      y = if (level == "encounter") "Encounters" else "Patients",
      title    = sprintf("Patient-to-encounter distance, %s level", level),
      subtitle = sprintf("n = %s. Median %.1f mi (solid); 90th percentile %.1f mi (dashed).\n%s same-ZIP %s at 0 mi.",
                         format(stats$n, big.mark = ","), stats$median, stats$p90,
                         format(stats$n_zero, big.mark = ","), unit),
      caption  = sprintf("Distance: zipcodeR::zip_distance() between ZIP5 codes.\nExcludes %s %s with no computable distance. Run %s.",
                         format(stats$n_excluded, big.mark = ","), unit, run_date)
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      plot.title.position   = "plot",
      plot.caption.position = "plot",
      plot.title    = ggplot2::element_text(face = "bold", size = 13),
      plot.subtitle = ggplot2::element_text(size = 9.5, colour = "grey20", lineheight = 1.1,
                                            margin = ggplot2::margin(b = 8)),
      plot.caption  = ggplot2::element_text(hjust = 0, size = 8.5, colour = "grey30",
                                            lineheight = 1.1, margin = ggplot2::margin(t = 8)),
      panel.grid.minor   = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_blank(),
      axis.title  = ggplot2::element_text(size = 10),
      axis.text   = ggplot2::element_text(size = 9),
      plot.margin = ggplot2::margin(10, 14, 8, 10)
    )

  if (is_log) {
    ticks <- c(1, 3, 10, 30, 100, 300, 1000, 3000)
    ticks <- ticks[log10(ticks) <= max(bins$upper)]
    # No "<1" tick: it would sit 0.125 log-units from "1" and collide. The first
    # bar is identified by the axis title instead.
    p <- p + ggplot2::scale_x_continuous(
      breaks = log10(ticks),
      labels = scales::label_comma()(ticks),
      expand = ggplot2::expansion(mult = c(0.01, 0.02)))
  } else {
    step <- if (cap >= 200) 50 else if (cap >= 100) 25 else 10
    brks <- seq(0, cap, by = step)
    brks <- brks[brks < cap]          # the cap itself is labelled once, as "<cap>+", over the open bin
    top  <- cap + bw / 2
    p <- p + ggplot2::scale_x_continuous(
      breaks = c(brks, top),
      labels = c(as.character(brks), paste0(cap, "+")),
      expand = ggplot2::expansion(mult = c(0.01, 0.02)))
  }

  if (!is.null(cutoffs))
    p <- p + ggplot2::geom_vline(xintercept = xf(cutoffs), colour = UF_ORANGE,
                                 linetype = "dotted", linewidth = 0.6)
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
                                     cutoffs = NULL, linear_width = 10, linear_cap = 350) {
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
      b <- if (sc == "linear") {
        bin_distance(levels[[lv]]$d$distance_mi, scale = "linear", width = linear_width, cap = linear_cap)
      } else {
        bin_distance(levels[[lv]]$d$distance_mi, scale = "log")
      }
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
