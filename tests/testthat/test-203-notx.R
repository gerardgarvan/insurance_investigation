# tests/testthat/test-203-notx.R
# Synthetic tests: build_tr_treatment_flags() (pre-loaded rows) and the Phase 203
# waterfall assignment. R/203 itself needs HiPerGator data and is not run here.

library(testthat)
suppressPackageStartupMessages({library(dplyr)})
root <- testthat::test_path("..", "..")
suppressMessages(source(file.path(root, "R", "utils", "utils_cancer.R")))
suppressMessages(source(file.path(root, "R", "utils", "utils_notx.R")))

# One row per HL TR record; only columns the TR_MAP reads for the tested sources.
tr_rows <- tibble::tibble(
  ID = c("a", "a", "b", "c", "d", "e"),
  SOURCE = c("UFH", "UFH", "UFH", "ORL", "ORL", "UFH"),
  CHEMO_START_DATE_SUMMARY = c("2015-03-01", NA, NA, NA, NA, NA),
  CHEMO_CODE_SUMMARY = c("1", "0", "0", NA, NA, "88"),
  REASON_NO_RADIATION = c(NA, NA, "1", NA, NA, NA),
  DT_CHEMO = c(NA, NA, NA, "2016-01-10", NA, NA),
  R_N_CHEMO = c(NA, NA, NA, "1", "9", NA)
)

# Real TUMOR_REGISTRY_ALL has every TR_MAP column; add the unused ones as NA.
for (cc in setdiff(unique(stats::na.omit(c(TR_MAP$date_col, TR_MAP$code_col))), names(tr_rows)))
  tr_rows[[cc]] <- NA_character_

test_that("build_tr_treatment_flags: given / unknown / first date", {
  out <- build_tr_treatment_flags(tr_hl = tr_rows, sources = c("UFH", "ORL"))
  expect_true(all(c("ID", "trtype", "tr_given", "tr_unknown", "tr_first_date") %in% names(out)))
  expect_equal(anyDuplicated(out[c("ID", "trtype")]), 0L)
  g <- function(id, ty) out[out$ID == id & out$trtype == ty, ]
  expect_true(g("a", "chemo")$tr_given)                       # dated + code 1
  expect_equal(g("a", "chemo")$tr_first_date, as.Date("2015-03-01"))
  expect_false(g("b", "chemo")$tr_given)                      # code 0 in naaccr_rx = none
  expect_true(g("c", "chemo")$tr_given)                       # ORL date present
  expect_false(g("d", "chemo")$tr_given)                      # R_N_CHEMO 9 = unknown
  expect_true(g("d", "chemo")$tr_unknown)
  expect_equal(g("d", "chemo")$tr_status, "unknown")
  expect_true(g("e", "chemo")$tr_unknown)                     # naaccr 88 unknown
  expect_false(g("b", "radiation")$tr_given)                  # reason_no 1 = not given
})

test_that("build_tr_treatment_flags: ids filter and by_source", {
  out <- build_tr_treatment_flags(ids = c("a", "c"), tr_hl = tr_rows)
  expect_setequal(unique(out$ID), c("a", "c"))
  bs <- build_tr_treatment_flags(tr_hl = tr_rows, by_source = TRUE)
  expect_true("SOURCE" %in% names(bs))
  expect_equal(anyDuplicated(bs[c("ID", "SOURCE", "trtype")]), 0L)
  empty <- build_tr_treatment_flags(ids = "zzz", tr_hl = tr_rows)
  expect_equal(nrow(empty), 0L)
})

test_that("waterfall: first-match order, prevalent flag, non-exclusive flags", {
  d0 <- as.Date("2015-01-01")
  n  <- 12
  df <- tibble::tibble(
    first_hl_dx_date = rep(d0, n),
    first_enc_date   = c(d0, d0 + 200, d0, d0, d0, d0, d0 + 91, d0 + 90, NA, d0, d0, d0),
    followup_days    = c(1000L, 1000L, 100L, 1000L, 1000L, 1000L, 1000L, 1000L, NA, 100L, 1000L, 1000L),
    single_source_care = c(1L, 1L, 1L, 0L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L),
    far_any_post     = c(FALSE, FALSE, FALSE, FALSE, TRUE, FALSE, rep(FALSE, 6)),
    nlphl_any        = c(rep(FALSE, 5), TRUE, rep(FALSE, 3), FALSE, TRUE, TRUE),
    nlphl_only       = c(rep(FALSE, 5), TRUE, rep(FALSE, 6)),
    tr_any_tx_given  = c(TRUE, TRUE, rep(NA, 10)),
    first_hist_dx_date = as.Date(c(NA, NA, NA, NA, NA, NA, NA, NA, NA, "2015-01-31", NA, NA)),
    tr_dx_date       = as.Date(c(NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, "2013-12-31", NA))
  )
  fl <- add_notx_flags(df)
  r  <- as.character(assign_notx_reason(fl))
  expect_equal(r[1], NOTX_REASON_LEVELS[1])   # TR beats everything
  expect_equal(r[2], NOTX_REASON_LEVELS[1])   # TR beats coverage gap
  expect_equal(r[3], NOTX_REASON_LEVELS[3])   # short follow-up
  expect_equal(r[4], NOTX_REASON_LEVELS[6])   # multi-source is no longer a reason
  expect_equal(r[5], NOTX_REASON_LEVELS[6])   # far-from-care is no longer a reason
  expect_equal(r[6], NOTX_REASON_LEVELS[5])   # NLPHL only
  expect_equal(r[7], NOTX_REASON_LEVELS[4])   # first enc = dx + 91 -> coverage gap
  expect_equal(r[8], NOTX_REASON_LEVELS[6])   # exactly dx + 90 -> not a gap
  expect_equal(r[9], NOTX_REASON_LEVELS[4])   # no usable encounter -> coverage gap
  # prevalent: history code at dx + 30d (boundary, TRUE) beats short follow-up
  expect_true(fl$f_hist_code[10]); expect_true(fl$f_short_followup[10])
  expect_equal(r[10], NOTX_REASON_LEVELS[2])
  # TR dx 366d before first dx -> prevalent (b)
  expect_true(fl$f_tr_early_dx[11]); expect_false(fl$f_hist_code[11])
  expect_equal(r[11], NOTX_REASON_LEVELS[2])
  # nlphl_any alone (not only) does not drive the waterfall
  expect_true(fl$f_nlphl_any[12]); expect_false(fl$f_nlphl_only[12])
  expect_equal(r[12], NOTX_REASON_LEVELS[6])
  expect_true(fl$f_dx_before_coverage[2] && fl$f_tr_treated[2])   # overlap kept in flags
  expect_false(anyNA(r))
  expect_equal(levels(assign_notx_reason(fl)), NOTX_REASON_LEVELS)
})

test_that("prevalent flag boundaries", {
  d0 <- as.Date("2015-01-01")
  df <- tibble::tibble(
    first_hl_dx_date = rep(d0, 4),
    first_enc_date = d0, followup_days = 1000L, single_source_care = 1L,
    far_any_post = FALSE, nlphl_any = FALSE, nlphl_only = FALSE, tr_any_tx_given = NA,
    first_hist_dx_date = as.Date(c("2015-01-31", "2015-02-01", NA, NA)),
    tr_dx_date = as.Date(c(NA, NA, "2014-01-01", "2013-12-31"))
  )
  fl <- add_notx_flags(df)
  expect_equal(fl$f_hist_code, c(TRUE, FALSE, FALSE, FALSE))     # dx + 30d inclusive
  expect_equal(fl$f_tr_early_dx, c(FALSE, FALSE, FALSE, TRUE))   # 365d not > 365; 366d is
  expect_equal(fl$f_prevalent_hl, c(TRUE, FALSE, FALSE, TRUE))
})

test_that("build_sheet_E: arithmetic on raw counts, suppression at the end", {
  fmt_sup <- function(n) {
    if (is.na(n)) return(NA_character_)
    n <- as.integer(n)
    if (n >= 1L & n <= 10L) "<11" else format(n, big.mark = ",")
  }
  sup_col <- function(x) vapply(x, fmt_sup, character(1))
  pct_sup <- function(num, den) {
    ifelse(!is.na(num) & num >= 11L & den >= 11L, sprintf("%.1f%%", 100 * num / den), "")
  }
  mk <- function(src, grp, obs, n) tibble::tibble(
    primary_source = src, group = grp, treatment_observable = obs)[rep(1, n), ]
  cp <- dplyr::bind_rows(
    mk("UFH", "no_treatment", TRUE, 20), mk("UFH", "treated", TRUE, 60),
    mk("ORL", "no_treatment", FALSE, 5), mk("ORL", "treated", TRUE, 30),
    mk(NA_character_, "treated", FALSE, 12)
  )
  e <- build_sheet_E(cp, sup_col, pct_sup)
  expect_true(is.character(e$n_no_tx))
  u <- e[e$primary_source == "UFH", ]
  expect_equal(u$n_no_tx, "20"); expect_equal(u$n_treated, "60")
  expect_equal(u$pct_no_tx, "25.0%")                       # 20 / 80
  expect_equal(u$pct_no_tx_among_observable, "25.0%")      # 20 / 80
  o <- e[e$primary_source == "ORL", ]
  expect_equal(o$n_no_tx, "<11"); expect_equal(o$pct_no_tx, "")
  expect_equal(o$pct_no_tx_among_observable, "")           # num 0 < 11
  expect_true("Unknown" %in% e$primary_source)
  expect_equal(e$primary_source[1], "UFH")                 # sorted by total desc
})
