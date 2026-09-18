# Drop-in replacement for plot_distance_hist() in R/utils/utils_distance_hist.R
# Requires UF_BLUE / UF_ORANGE defined in the same file.

# ------------------------------------------------------------------------------
#' Plot a distance histogram with UF brand colors.
#'
#' Layout rules (8 x 5 in at 300 dpi, base_size 12):
#'   - title/subtitle/caption are left-aligned to the plot edge (plot.title.position = "plot")
#'     so long strings never clip against the panel;
#'   - caption is split over two lines; nothing longer than ~90 characters per line;
#'   - x axis on the linear scale labels the open top bin as "<cap>+";
#'   - y axis uses comma separators; bars sit on the axis (no lower expansion);
#'   - reference lines are explained in the subtitle, not annotated on the panel
#'     (annotations overflow when the median sits near an axis edge).
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
  bw     <- bins$upper[1] - bins$lower[1]                     # bin width in axis units
  cap    <- if (is_log) NA_real_ else max(bins$lower)          # open top bin starts here
  bins   <- bins |> dplyr::mutate(mid = ifelse(is.infinite(upper), lower + bw / 2, (lower + upper) / 2))

  xf   <- if (is_log) function(v) log10(1 + v) else identity
  unit <- if (level == "encounter") "encounters" else "patients"

  p <- ggplot2::ggplot(bins, ggplot2::aes(x = mid, y = n)) +
    ggplot2::geom_col(width = bw, fill = UF_BLUE, colour = "white", linewidth = 0.2) +
    ggplot2::geom_vline(xintercept = xf(stats$median), colour = UF_ORANGE, linewidth = 0.8) +
    ggplot2::geom_vline(xintercept = xf(stats$p90),    colour = UF_ORANGE, linewidth = 0.8,
                        linetype = "dashed") +
    ggplot2::scale_y_continuous(labels = scales::label_comma(),
                                expand = ggplot2::expansion(mult = c(0, 0.05))) +
    ggplot2::labs(
      x = if (is_log) "Distance, miles (log scale)" else "Distance, miles",
      y = if (level == "encounter") "Encounters" else "Patients",
      title    = sprintf("Patient-to-encounter distance, %s level", level),
      subtitle = sprintf("n = %s. Median %.1f mi (solid line); 90th percentile %.1f mi (dashed line).",
                         format(stats$n, big.mark = ","), stats$median, stats$p90),
      caption  = sprintf("Distance: zipcodeR::zip_distance() between ZIP5 codes.\nExcludes %s %s with no computable distance. Run %s.",
                         format(stats$n_excluded, big.mark = ","), unit, run_date)
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      plot.title.position   = "plot",
      plot.caption.position = "plot",
      plot.title    = ggplot2::element_text(face = "bold", size = 13),
      plot.subtitle = ggplot2::element_text(size = 10, colour = "grey20", margin = ggplot2::margin(b = 8)),
      plot.caption  = ggplot2::element_text(hjust = 0, size = 8.5, colour = "grey30", lineheight = 1.1,
                                            margin = ggplot2::margin(t = 8)),
      panel.grid.minor   = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_blank(),
      axis.title = ggplot2::element_text(size = 10),
      axis.text  = ggplot2::element_text(size = 9),
      plot.margin = ggplot2::margin(10, 14, 8, 10)
    )

  if (is_log) {
    ticks <- c(0, 1, 2, 5, 10, 25, 50, 100, 250, 500, 1000, 2500)
    ticks <- ticks[log10(1 + ticks) <= max(bins$upper)]
    p <- p + ggplot2::scale_x_continuous(breaks = log10(1 + ticks), labels = scales::label_comma()(ticks),
                                         expand = ggplot2::expansion(mult = c(0.01, 0.02)))
  } else {
    step   <- if (cap >= 200) 50 else if (cap >= 100) 25 else 10
    brks   <- seq(0, cap, by = step)
    labs_x <- as.character(brks)
    top    <- cap + bw / 2
    p <- p + ggplot2::scale_x_continuous(breaks = c(brks, top), labels = c(labs_x, paste0(cap, "+")),
                                         expand = ggplot2::expansion(mult = c(0.01, 0.02)))
  }

  if (!is.null(cutoffs))
    p <- p + ggplot2::geom_vline(xintercept = xf(cutoffs), colour = UF_ORANGE,
                                 linetype = "dotted", linewidth = 0.6)
  p
}

