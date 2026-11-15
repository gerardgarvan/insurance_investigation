# tests/testthat/test-202-tr-sensitivity.R
# Phase 202: synthetic tests for the not-captured split, coverage-window filter,
# year bands, and flag conversion (helpers in R/utils/utils_tr_sensitivity.R).
# R/202 itself needs HiPerGator data and is not run here.

library(testthat)
suppressMessages(source(file.path(testthat::test_path("..", ".."), "R", "utils", "utils_tr_sensitivity.R")))

d0 <- as.Date("2015-06-01")

test_that("not-captured split: tiers and sign convention", {
  tier <- tr_capture_tier(
    tr_status  = rep("given", 8),
    tr_date    = c(d0, d0, d0, d0, d0, d0, NA, d0),
    gantt_date = c(d0, d0 - 20, d0 + 60, d0 - 200, d0 + 200, NA, d0, NA)
  )
  expect_equal(tier, c("exact", "within_30d", "within_90d",
                       "pipe_before", "pipe_after", "no_pipeline",
                       "not_datable", "no_pipeline"))
  # boundary: exactly 90 d is within_90d; 91 d is a mismatch tier
  expect_equal(tr_capture_tier("given", d0, d0 - 90), "within_90d")
  expect_equal(tr_capture_tier("given", d0, d0 - 91), "pipe_before")
  expect_equal(tr_capture_tier("given", d0, d0 + 91), "pipe_after")
  expect_equal(tr_capture_tier(c("unknown", "not_given"), d0, d0),
               c("unknown_code", "no_registry"))
})

test_that("tier summary: counts, cumulative hits, median/IQR suppression", {
  n_b <- 12L
  df <- tibble::tibble(
    capture_tier = c(rep("pipe_before", n_b), rep("pipe_after", 3), "exact", "within_30d",
                     "within_90d", "not_datable", "no_pipeline", "no_pipeline", "unknown_code"),
    signed_diff  = c(seq(100, 100 + n_b - 1), 150L, 160L, 170L, rep(NA_integer_, 7))
  )
  s <- tr_summarise_tiers(df)
  expect_equal(s$n_denom, 12 + 3 + 1 + 1 + 1 + 1 + 2)      # unknown_code excluded
  expect_equal(s$n_30d, 2L)                                   # exact + within_30d
  expect_equal(s$n_90d, 3L)                                   # cumulative
  expect_equal(s$n_before, 12L)
  expect_equal(s$n_after, 3L)
  expect_equal(s$n_no_pipe, 2L)
  expect_equal(s$n_undated, 1L)
  expect_equal(s$med_before, "106 (103-108)")                 # n >= 11
  expect_true(is.na(s$med_after))                             # n = 3 < 11: suppressed
  # not-captured tiers are exclusive and sum with captured to the denominator
  expect_equal(s$n_90d + s$n_undated + s$n_no_pipe + s$n_before + s$n_after, s$n_denom)
})

test_that("coverage window keeps dates on/after first encounter", {
  df <- tibble::tibble(
    ID = c("a", "b", "c", "d", "e"),
    tr_first_date = as.Date(c("2012-01-01", "2014-01-01", "2016-01-01", "2016-01-01", NA))
  )
  enc <- tibble::tibble(
    ID = c("a", "b", "c", "e"),
    first_enc_date = as.Date(c("2013-01-01", "2014-01-01", "2013-06-01", "2020-01-01"))
  )
  r <- tr_coverage_filter(df, enc)
  expect_equal(sort(r$in_window$ID), c("b", "c", "e"))   # a pre-encounter; d no encounter; e undated kept
  expect_equal(r$n_excluded_pre_encounter, 1L)           # a
  expect_equal(r$n_no_encounter, 1L)                     # d (dated, no ENCOUNTER)
})

test_that("year bands and fallback to Unknown", {
  b <- tr_year_band(c(2005, 2009, 2010, 2012, 2013, 2015, 2016, 2018, 2019, 2024, NA))
  expect_equal(as.character(b), c("<=2009", "<=2009", "2010-2012", "2010-2012", "2013-2015",
                                  "2013-2015", "2016-2018", "2016-2018", "2019+", "2019+", "Unknown"))
  # cohort year wins, TR year fills the gap, residual stays Unknown
  yr <- dplyr::coalesce(c(2011L, NA, NA), c(2014L, 2017L, NA))
  expect_equal(as.character(tr_year_band(yr)), c("2010-2012", "2016-2018", "Unknown"))
})

test_that("CSV flags blank/TRUE/FALSE -> logical", {
  expect_equal(tr_flag_to_logical(c("TRUE", "FALSE", "", NA, " true ")),
               c(TRUE, FALSE, NA, NA, TRUE))
  expect_equal(tr_flag_to_logical(c(TRUE, NA)), c(TRUE, NA))
})
