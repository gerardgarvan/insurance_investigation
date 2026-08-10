# ==============================================================================
# test-115-c02.R -- Behavioral tests for C-02 reconciliation (Phase 140)
# ==============================================================================
# Purpose: Synthetic-fixture tests for compute_c02(), defined in
#          R/115_zip_stability_counts.R SECTION 1B. Per 140-08-PATCH FIX-16,
#          C-02/date-classification fixtures live here (a sibling to
#          test-115-validation-curve.R) so that single shared file does not
#          keep absorbing every plan's fixtures across all of Phase 140. This
#          file grows across Plans 01/03 of Phase 140 -- each plan appends its
#          own test_that() block once its function/behavior exists in SECTION
#          1B.
#
# Sourcing pattern: R/115_zip_stability_counts.R has a probe gate (SECTION 2)
# that stop()s/quit()s when LDS_ADDRESS_HISTORY is not found -- expected on
# this (Windows, no source CSV) machine. sys.source() into a fresh environment
# (.test_env) captures every SECTION 1B function definition BEFORE that probe
# gate is reached, since SECTION 1B is placed ahead of SECTION 2 in the file.
# The tryCatch() below swallows the expected stop()/quit() from the probe gate;
# it does NOT swallow real errors raised while parsing/defining SECTION 1B's
# functions themselves (those happen before the gate and would still bubble up
# through sys.source() as a normal condition on the same call).
#
# testthat::test_file()/test_dir() run test files with the working directory
# set to the test file's own directory (tests/testthat), not the project root
# -- see vignette("special-files"). R/115_zip_stability_counts.R's own
# source("R/00_config.R") call (and this file's project-relative sourcing)
# both assume a project-root working directory, matching how every other
# script in R/ is invoked (Rscript R/xxx.R from repo root). withr::with_dir()
# temporarily restores a project-root working directory (located via
# here::here(), which walks up from the current directory looking for project
# markers such as .git -- reliable regardless of testthat's cwd convention)
# for the duration of both source() calls, then restores the prior directory.
# ==============================================================================

library(testthat)
library(dplyr)
library(tibble)

.project_root <- here::here()

withr::with_dir(.project_root, source("R/00_config.R"))

.test_env <- new.env()
tryCatch(
  withr::with_dir(.project_root, sys.source("R/115_zip_stability_counts.R", envir = .test_env)),
  error = function(e) invisible(NULL)   # expected: SECTION 2's probe gate stop()s once reached --
                                         # everything in SECTION 1B is already captured by then.
)


# ==============================================================================
# Task 1 (139-04 / moved here 140-01 per FIX-16): compute_c02() -- cohort-
# scoped C-02 reconciliation, extended (140-01) with the present-vs-absent
# breakdown (n_present_no_usable_zip5).
# ==============================================================================

test_that("cohort patient absent from addr_coal counts toward n_patients_no_zip5_ever (FIX-03)", {
  # cohort_ids has 3 patients: P6 (has a usable ZIP5 in addr_coal), P7 (has a row in
  # addr_coal but zip5_coalesced is NA), and P8 (does NOT appear anywhere in addr_coal --
  # e.g. dropped by Plan 01's study-period/unparseable-date filters, or never in
  # LDS_ADDRESS_HISTORY at all). Under the pre-patch design (all(is.na(...)) grouped over
  # addr_coal's OWN patient set), P8 would be invisible to group_by() and NOT counted --
  # this is the exact defect FIX-03 corrects.
  cohort_ids_fixture <- c("P6", "P7", "P8")

  addr_coal_fixture <- tibble(
    ID = c("P6", "P7"),
    zip5_coalesced = c("32611", NA_character_)
  )

  result <- .test_env$compute_c02(cohort_ids_fixture, addr_coal_fixture)

  # P7 (record present, ZIP5 NA) and P8 (absent entirely) both count toward the numerator;
  # P6 (has a usable ZIP5) does not. So n_patients_no_zip5_ever == 2, not 1 (which is what
  # the pre-patch group_by()-over-addr_coal's-own-patients design would have silently
  # produced by never seeing P8 at all).
  expect_equal(result$n_patients_no_zip5_ever, 2)
  expect_equal(result$n_cohort_absent_from_addr, 1)
  expect_true(nrow(result$c02_tbl) == 3)
})

test_that("140-01 P-01a: n_present_no_usable_zip5 isolates cohort patients present in addr_coal with no usable ZIP5", {
  # 4-patient cohort: A is entirely absent from addr_coal; B has one addr_coal row with
  # zip5_coalesced = NA; C has one addr_coal row with a real zip5_coalesced; D has two
  # addr_coal rows both NA. n_present_no_usable_zip5 is the only population a genuine
  # ZIP5-coalescing defect could actually produce (B, D) -- distinct from the
  # coverage-question population (A, entirely absent from addr_coal).
  cohort_ids_fixture <- c("A", "B", "C", "D")

  addr_coal_fixture <- tibble(
    ID             = c("B", "C", "D", "D"),
    zip5_coalesced = c(NA_character_, "32611", NA_character_, NA_character_)
  )

  result <- .test_env$compute_c02(cohort_ids_fixture, addr_coal_fixture)

  expect_equal(result$n_patients_no_zip5_ever, 3)     # A, B, D
  expect_equal(result$n_cohort_absent_from_addr, 1)   # A
  expect_equal(result$n_present_no_usable_zip5, 2)    # B, D
})


# ==============================================================================
# 140-03 P-02a: classify_unparseable_dates_vec() / classify_unparseable_dates() -- failure-
# mode classification of raw date strings that FAILED parse_pcornet_date().
# ==============================================================================

test_that("classify_unparseable_dates_vec() categorizes raw unparseable date strings correctly", {
  raw_values <- c(NA, "", "NULL", "20259931", "not-a-date", "13FOOO2020", "###")

  result <- .test_env$classify_unparseable_dates_vec(raw_values)

  expect_equal(
    result,
    c(
      "blank_or_null", "blank_or_null", "blank_or_null",
      "numeric_looking_but_invalid",
      "text_looking_but_invalid", "text_looking_but_invalid",
      "other_unrecognized"
    )
  )
})

test_that("classify_unparseable_dates() returns per-category counts, descending", {
  raw_values <- c(NA, "", "NULL", "20259931", "not-a-date", "13FOOO2020", "###")

  result <- .test_env$classify_unparseable_dates(raw_values)

  expect_equal(result$n[result$category == "blank_or_null"], 3)
  expect_equal(result$n[result$category == "numeric_looking_but_invalid"], 1)
  expect_equal(result$n[result$category == "text_looking_but_invalid"], 2)
  expect_equal(result$n[result$category == "other_unrecognized"], 1)
})


# ==============================================================================
# 140-09-PATCH FIX-17 / Task 1: compute_c02_baseline() -- pre-coalesce baseline for the
# C-02a coalescing-monotonicity invariant. Coalescing can only ADD a ZIP5 value, never
# remove one, so the post-coalesce n_present_no_usable_zip5 must be <= this baseline.
# ==============================================================================

test_that("compute_c02_baseline() counts cohort patients present in addr_raw with no usable raw ZIP5, and demonstrates monotone recovery vs compute_c02()'s post-coalesce figure", {
  # 4-patient cohort: A is absent from addr_raw entirely; B has raw ZIP5 present; C has raw
  # ZIP5 absent but is recoverable by coalescing (its zip5_coalesced ends up populated,
  # e.g. derived from a valid ZIP9); D has neither raw nor coalesced ZIP5.
  cohort_ids_fixture <- c("A", "B", "C", "D")

  addr_raw_fixture <- tibble(
    ID            = c("B", "C", "D"),
    ADDRESS_ZIP9  = c(NA_character_, NA_character_, NA_character_),
    ADDRESS_ZIP5  = c("32611", NA_character_, NA_character_)
  )

  baseline <- .test_env$compute_c02_baseline(cohort_ids_fixture, addr_raw_fixture)

  # A is absent from addr_raw (compute_c02_baseline restricts to PRESENT patients, per its
  # own contract -- absent patients are C-02c's business). B has a usable raw ZIP5. C and D
  # do not: baseline == 2.
  expect_equal(baseline, 2)

  # Post-coalesce: simulate coalesce_zip5() having recovered C's ZIP5 (e.g. from a ZIP9 that
  # carried it), leaving only D with no usable ZIP5 anywhere.
  addr_coal_fixture <- tibble(
    ID             = c("B", "C", "D"),
    zip5_coalesced = c("32611", "32601", NA_character_)
  )
  post_result <- .test_env$compute_c02(cohort_ids_fixture, addr_coal_fixture)

  expect_equal(post_result$n_present_no_usable_zip5, 1)   # D only -- C was recovered

  # C-02a itself: post-coalesce (1) <= pre-coalesce (2) -- coalescing only added a value.
  c02a_monotone <- post_result$n_present_no_usable_zip5 <= baseline
  expect_true(c02a_monotone)
})

test_that("compute_c02_baseline() vs a synthetic monotonicity VIOLATION -- c02a_monotone must be able to fail", {
  # An invariant never observed failing is an invariant never tested. Construct a case where
  # a "coalesce" step incorrectly DROPS a ZIP5 value that was present pre-coalesce -- this is
  # the unambiguous coalesce_zip5() defect C-02a exists to catch.
  cohort_ids_fixture <- c("E", "F")

  addr_raw_fixture <- tibble(
    ID           = c("E", "F"),
    ADDRESS_ZIP9 = c(NA_character_, NA_character_),
    ADDRESS_ZIP5 = c("32611", "32601")   # both patients have a usable raw ZIP5
  )
  baseline <- .test_env$compute_c02_baseline(cohort_ids_fixture, addr_raw_fixture)
  expect_equal(baseline, 0)   # neither E nor F is missing a raw ZIP5

  # Buggy "post-coalesce" table: E's ZIP5 was dropped (zip5_coalesced NA) despite having a
  # usable raw ZIP5 above -- coalesce_zip5() must never do this, but the invariant has to be
  # able to detect it if it did.
  addr_coal_buggy <- tibble(
    ID             = c("E", "F"),
    zip5_coalesced = c(NA_character_, "32601")
  )
  post_result <- .test_env$compute_c02(cohort_ids_fixture, addr_coal_buggy)
  expect_equal(post_result$n_present_no_usable_zip5, 1)   # E, incorrectly

  c02a_monotone <- post_result$n_present_no_usable_zip5 <= baseline
  expect_false(c02a_monotone)   # 1 <= 0 is FALSE -- the violation is caught
})
