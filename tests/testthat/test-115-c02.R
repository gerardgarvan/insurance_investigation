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
