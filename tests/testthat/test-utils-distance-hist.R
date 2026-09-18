# ==============================================================================
# test-utils-distance-hist.R -- Unit tests for R/utils/utils_distance_hist.R
# Phase 154
# ==============================================================================
# Run with: testthat::test_file("tests/testthat/test-utils-distance-hist.R")
# No DuckDB, HiPerGator, or live data required.

library(testthat)
library(dplyr)
library(tibble)
library(withr)

# Follow the sourcing convention used by the existing test-utils-address*.R files.
# testthat::test_path() resolves relative to tests/testthat/, so this works under
# both test_file() and test_dir().
source(testthat::test_path("..", "..", "R", "utils", "utils_distance_hist.R"))

# ---- Synthetic data ----
set.seed(154)
mi_vec <- c(0, 1.5, 5, 10, 25, 50, 75, 100, 200, 300, 500)

make_enc_distance <- function(n = 30) {
  tibble::tibble(
    ID              = rep(paste0("P", 1:10), each = 3)[seq_len(n)],
    ADMIT_DATE      = seq(as.Date("2020-01-01"), by = "month", length.out = n),
    ENC_TYPE        = rep(c("AV", "IP", "ED"), length.out = n),
    zip5_facility   = rep(c("32601", "32603", "33101"), length.out = n),
    facility_state  = rep(c("FL", "FL", "FL"), length.out = n),
    distance_mi     = c(runif(n - 3, 0, 200), NA, NA, NA),
    distance_status = c(rep("computed", n - 3), "patient_zip_missing", "facility_zip_missing", "zip_not_in_db"),
    zip5_patient_source = rep("in_range_zip5", n),
    days_offset     = rep(0L, n)
  )
}

enc_dist <- make_enc_distance()

# ==============================================================================
# bin_distance()
# ==============================================================================

test_that("bin_distance linear: n sums to length of input", {
  b <- bin_distance(mi_vec, scale = "linear")
  expect_equal(sum(b$n), length(mi_vec))
})

test_that("bin_distance linear: pct sums to 100", {
  b <- bin_distance(mi_vec, scale = "linear")
  expect_equal(round(sum(b$pct), 5), 100)
})

test_that("bin_distance log: n sums to length of input", {
  b <- bin_distance(mi_vec, scale = "log")
  expect_equal(sum(b$n), length(mi_vec))
})

test_that("bin_distance: NAs in input are silently dropped", {
  b <- bin_distance(c(10, NA, 50, NA), scale = "linear")
  expect_equal(sum(b$n), 2L)
})

test_that("bin_distance linear: scale column is 'linear'", {
  b <- bin_distance(mi_vec, scale = "linear")
  expect_true(all(b$scale == "linear"))
})

test_that("bin_distance log: scale column is 'log'", {
  b <- bin_distance(mi_vec, scale = "log")
  expect_true(all(b$scale == "log"))
})

test_that("bin_distance: zero distance falls in first bin", {
  b <- bin_distance(c(0, 10), scale = "linear")
  first_bin_n <- b$n[b$lower == 0]
  expect_true(first_bin_n >= 1L)
})

test_that("bin_distance: empty input returns an empty bin table, both scales", {
  for (sc in c("linear", "log")) {
    b <- bin_distance(numeric(0), scale = sc)
    expect_equal(nrow(b), 0L)
    expect_true(all(c("bin", "lower", "upper", "n", "pct", "scale", "lower_mi", "upper_mi") %in% names(b)))
  }
  b <- bin_distance(c(NA_real_, NA_real_), scale = "log")
  expect_equal(nrow(b), 0L)
})

test_that("bin_distance: all-zero input lands entirely in the first bin", {
  b <- bin_distance(rep(0, 7), scale = "linear")
  expect_equal(b$n[1], 7L)
  expect_equal(sum(b$n[-1]), 0L)
  b_log <- bin_distance(rep(0, 7), scale = "log")
  expect_equal(sum(b_log$n), 7L)
  expect_equal(b_log$n[1], 7L)                        # all in the [0,1) first bin
  expect_gte(nrow(b_log), 2L)
})

test_that("bin_distance log: decade values sit on bin edges and are counted", {
  b <- bin_distance(c(0, 0.5, 1, 10, 100), scale = "log")
  expect_equal(sum(b$n), 5L)
  expect_true(all(c(0, 1, 2) %in% b$lower))          # 1, 10, 100 mi are edges
  expect_equal(b$n[b$lower == -0.25], 2L)             # 0 and 0.5 -> first bin
  expect_equal(b$n[b$lower == 0], 1L)                 # 1 mi -> [1, 1.78)
  expect_equal(b$lower_mi[b$lower == -0.25], 0)
  expect_equal(b$upper_mi[b$lower == -0.25], 1)
})

test_that("bin_distance: negative or infinite input is not silently binned", {
  expect_error(bin_distance(c(-1, 5), scale = "linear"), "negative")
})

test_that("bin_distance: single value above cap goes to the open top bin", {
  b <- bin_distance(1234, scale = "linear", cap = 300)
  expect_equal(b$n[is.infinite(b$upper)], 1L)
  expect_equal(sum(b$n), 1L)
})

# ==============================================================================
# plot_distance_hist()
# ==============================================================================

test_that("plot_distance_hist returns a ggplot for linear bins", {
  b <- bin_distance(mi_vec, scale = "linear")
  stats <- tibble::tibble(n = length(mi_vec), n_excluded = 0L,
                           median = median(mi_vec), p90 = quantile(mi_vec, 0.9),
                           n_zero = sum(mi_vec == 0))
  p <- plot_distance_hist(b, stats, level = "encounter")
  expect_s3_class(p, "ggplot")
})

test_that("plot_distance_hist returns a ggplot for log bins", {
  b <- bin_distance(mi_vec, scale = "log")
  stats <- tibble::tibble(n = length(mi_vec), n_excluded = 0L,
                           median = median(mi_vec), p90 = quantile(mi_vec, 0.9),
                           n_zero = sum(mi_vec == 0))
  p <- plot_distance_hist(b, stats, level = "patient")
  expect_s3_class(p, "ggplot")
})

# ==============================================================================
# make_distance_histograms()
# ==============================================================================

test_that("make_distance_histograms returns list with bins and stats", {
  tmp <- withr::local_tempdir()
  result <- make_distance_histograms(enc_dist, out_dir = tmp, run_date = "20260918")
  expect_named(result, c("bins", "stats"))
})

test_that("make_distance_histograms bins has level column with encounter and patient", {
  tmp <- withr::local_tempdir()
  result <- make_distance_histograms(enc_dist, out_dir = tmp, run_date = "20260918")
  expect_true(all(c("encounter", "patient") %in% result$bins$level))
})

test_that("make_distance_histograms bins has scale column with linear and log", {
  tmp <- withr::local_tempdir()
  result <- make_distance_histograms(enc_dist, out_dir = tmp, run_date = "20260918")
  expect_true(all(c("linear", "log") %in% result$bins$scale))
})

test_that("make_distance_histograms writes exactly the 4 expected PNG file names", {
  tmp <- withr::local_tempdir()
  result <- make_distance_histograms(enc_dist, out_dir = tmp, run_date = "20260918")
  expected <- sprintf("encounter_distance_hist_%s_%s_20260918.png",
                      rep(c("encounter", "patient"), each = 2), rep(c("linear", "log"), 2))
  pngs <- list.files(file.path(tmp, "figures"), pattern = "\\.png$", full.names = FALSE)
  expect_setequal(pngs, expected)
})

test_that("make_distance_histograms bin counts sum to computed n at every level/scale", {
  tmp <- withr::local_tempdir()
  result <- make_distance_histograms(enc_dist, out_dir = tmp, run_date = "20260918")
  n_enc <- nrow(dplyr::filter(enc_dist, distance_status == "computed"))
  n_pat <- dplyr::n_distinct(dplyr::filter(enc_dist, distance_status == "computed")$ID)
  for (lv in c("encounter", "patient")) for (sc in c("linear", "log")) {
    got <- sum(result$bins$n[result$bins$level == lv & result$bins$scale == sc])
    expect_equal(got, if (lv == "encounter") n_enc else n_pat, info = paste(lv, sc))
  }
})

test_that("make_distance_histograms with no computed rows warns and writes nothing", {
  tmp <- withr::local_tempdir()
  none <- dplyr::mutate(enc_dist, distance_status = "patient_zip_missing", distance_mi = NA_real_)
  expect_warning(result <- make_distance_histograms(none, out_dir = tmp, run_date = "20260918"),
                 "no computed rows")
  expect_equal(nrow(result$bins), 0L)
  expect_equal(length(list.files(file.path(tmp, "figures"))), 0L)
})

test_that("make_distance_histograms encounter stats$n equals nrow of computed rows", {
  tmp <- withr::local_tempdir()
  result <- make_distance_histograms(enc_dist, out_dir = tmp, run_date = "20260918")
  n_computed <- nrow(dplyr::filter(enc_dist, distance_status == "computed"))
  enc_stat_n <- result$stats |> dplyr::filter(level == "encounter") |> dplyr::pull(n)
  expect_equal(enc_stat_n, n_computed)
})

# ==============================================================================
# summarise_distance()
# ==============================================================================

test_that("summarise_distance overall returns one row with breakout = 'overall'", {
  out <- summarise_distance(enc_dist, by = "overall")
  expect_equal(nrow(out), 1L)
  expect_equal(out$breakout, "overall")
})

test_that("summarise_distance overall n equals nrow of computed non-NA distance rows", {
  out <- summarise_distance(enc_dist, by = "overall")
  expected_n <- nrow(dplyr::filter(enc_dist, distance_status == "computed", !is.na(distance_mi)))
  expect_equal(out$n, expected_n)
})

test_that("summarise_distance by year has breakout values prefixed year_", {
  out <- summarise_distance(enc_dist, by = "year")
  expect_true(all(startsWith(out$breakout, "year_")))
})

test_that("summarise_distance by ENC_TYPE has breakout values prefixed enc_type_", {
  out <- summarise_distance(enc_dist, by = "ENC_TYPE")
  expect_true(all(startsWith(out$breakout, "enc_type_")))
})

test_that("summarise_distance by facility_state has breakout values prefixed state_", {
  out <- summarise_distance(enc_dist, by = "facility_state")
  expect_true(all(startsWith(out$breakout, "state_")))
})

test_that("summarise_distance returns required stat columns", {
  out <- summarise_distance(enc_dist, by = "overall")
  expect_named(out, c("breakout", "n", "median_mi", "IQR_mi", "p90_mi", "p95_mi", "p99_mi", "max_mi"))
})

test_that("summarise_distance: facility_state NA maps to state_unmatched", {
  d <- dplyr::mutate(enc_dist, facility_state = NA_character_)
  out <- summarise_distance(d, by = "facility_state")
  expect_equal(out$breakout, "state_unmatched")
})

test_that("summarise_distance: p90 >= median for overall", {
  out <- summarise_distance(enc_dist, by = "overall")
  expect_true(out$p90_mi >= out$median_mi)
})

test_that("bin_distance linear defaults are 10-mile bins to 350", {
  b <- bin_distance(c(5, 355), scale = "linear")
  expect_equal(b$upper[1], 10)
  expect_equal(max(b$lower), 350)
  expect_equal(b$n[is.infinite(b$upper)], 1L)
})

test_that("make_distance_histograms passes linear_width / linear_cap through", {
  tmp <- withr::local_tempdir()
  r <- make_distance_histograms(enc_dist, out_dir = tmp, run_date = "20260918",
                                linear_width = 25, linear_cap = 200)
  lin <- r$bins[r$bins$level == "encounter" & r$bins$scale == "linear", ]
  expect_equal(lin$upper[1], 25)
  expect_equal(max(lin$lower), 200)
})

test_that("plot_distance_hist log axis has a '<1' tick", {
  b <- bin_distance(mi_vec, scale = "log")
  stats <- tibble::tibble(n = length(mi_vec), n_excluded = 0L, median = median(mi_vec),
                          p90 = quantile(mi_vec, 0.9), n_zero = sum(mi_vec == 0))
  p <- plot_distance_hist(b, stats, level = "encounter")
  lbls <- ggplot2::ggplot_build(p)$layout$panel_params[[1]]$x$get_labels()
  expect_true("<1" %in% lbls)
})
