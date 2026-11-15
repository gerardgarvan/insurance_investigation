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

test_that("waterfall: first-match order and non-exclusive flags", {
  d0 <- as.Date("2015-01-01")
  df <- tibble::tibble(
    first_hl_dx_date = rep(d0, 9),
    first_enc_date   = c(d0, d0 + 200, d0, d0, d0, d0, d0 + 91, d0 + 90, NA),
    followup_days    = c(1000L, 1000L, 100L, 1000L, 1000L, 1000L, 1000L, 1000L, NA),
    single_source_care = c(1L, 1L, 1L, 0L, 1L, 1L, 1L, 1L, 1L),
    far_any_post     = c(FALSE, FALSE, FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, FALSE),
    nlphl_any        = c(FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, FALSE, FALSE, FALSE),
    tr_any_tx_given  = c(TRUE, TRUE, NA, NA, NA, NA, NA, NA, NA)
  )
  fl <- add_notx_flags(df)
  r  <- as.character(assign_notx_reason(fl))
  expect_equal(r[1], NOTX_REASON_LEVELS[1])   # TR beats everything
  expect_equal(r[2], NOTX_REASON_LEVELS[1])   # TR beats coverage gap
  expect_equal(r[3], NOTX_REASON_LEVELS[3])   # short follow-up
  expect_equal(r[4], NOTX_REASON_LEVELS[4])   # multi-source
  expect_equal(r[5], NOTX_REASON_LEVELS[5])   # far
  expect_equal(r[6], NOTX_REASON_LEVELS[6])   # NLPHL
  expect_equal(r[7], NOTX_REASON_LEVELS[2])   # first enc = dx + 91 -> coverage gap
  expect_equal(r[8], NOTX_REASON_LEVELS[7])   # exactly dx + 90 -> not a gap -> unexplained
  expect_equal(r[9], NOTX_REASON_LEVELS[2])   # no usable encounter -> coverage gap
  expect_true(fl$f_dx_before_coverage[2] && fl$f_tr_treated[2])   # overlap kept in flags
  expect_false(anyNA(r))
  expect_equal(levels(assign_notx_reason(fl)), NOTX_REASON_LEVELS)
})
