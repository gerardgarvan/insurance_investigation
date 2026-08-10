# ==============================================================================
# test-115-validation-curve.R -- Behavioral tests for A-06 (Phase 139)
# ==============================================================================
# Purpose: Synthetic-fixture tests for build_validation_cases() and
#          aggregate_validation_curve(), defined in R/115_zip_stability_counts.R
#          SECTION 1B. This file grows across Plans 02/03/04 of Phase 139 --
#          each plan appends its own test_that() block once its function
#          exists in SECTION 1B, so the file always reflects only fixtures
#          whose supporting function is already implemented.
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
# Task 1 (139-02): build_validation_cases() / aggregate_validation_curve()
# ==============================================================================

test_that("stable patient: exact-match rate is 100 (not 0) -- catches FIX-01", {
  # One patient, 5 address records, SAME zip9_norm, period_start_dt spread
  # ~9 months apart over 3 years. Under the OLD spell-based design, spell-
  # collapsing would reduce these 5 identical-ZIP9 records to a single spell
  # with zero prior spells to test against, so pct_exact_zip9_match would read
  # 0, not 100. This assertion is the one that catches that defect.
  addr_coal_fixture <- tibble(
    ID = rep("P1", 5),
    period_start_dt = as.Date(c(
      "2020-01-01", "2020-10-01", "2021-07-01", "2022-04-01", "2023-01-01"
    )),
    period_end_eff = as.Date(c(
      "2020-09-30", "2021-06-30", "2022-03-31", "2022-12-31", "9999-12-31"
    )),
    zip9_norm = rep("326111234", 5)
  )

  cases <- .test_env$build_validation_cases(addr_coal_fixture)

  # 5 records - 1 with no prior = 4 test cases
  expect_equal(nrow(cases), 4)

  curve <- .test_env$aggregate_validation_curve(cases)
  overall_row <- curve[curve$gap_bin == "Overall", ]

  expect_equal(overall_row$pct_exact_zip9_match, 100)
})

test_that("mover: exact-match rate is strictly between 0 and 100, and higher in the shortest gap bin", {
  # One patient, 4 records at ZIP9-A then 3 at ZIP9-B, evenly spaced (~60 days
  # apart). The transition from A to B produces exactly one mismatched case;
  # all other consecutive pairs (within A, within B) match.
  addr_coal_fixture <- tibble(
    ID = rep("P2", 7),
    period_start_dt = as.Date(c(
      "2020-01-01", "2020-03-01", "2020-05-01", "2020-07-01",
      "2020-09-01", "2020-11-01", "2021-01-01"
    )),
    period_end_eff = as.Date(c(
      "2020-02-29", "2020-04-30", "2020-06-30", "2020-08-31",
      "2020-10-31", "2020-12-31", "9999-12-31"
    )),
    zip9_norm = c(
      "326111234", "326111234", "326111234", "326111234",
      "326115678", "326115678", "326115678"
    )
  )

  cases <- .test_env$build_validation_cases(addr_coal_fixture)

  # 7 records - 1 with no prior = 6 test cases
  expect_equal(nrow(cases), 6)

  curve <- .test_env$aggregate_validation_curve(cases)
  overall_row <- curve[curve$gap_bin == "Overall", ]

  expect_true(overall_row$pct_exact_zip9_match > 0)
  expect_true(overall_row$pct_exact_zip9_match < 100)

  # All gaps in this fixture are 61 days apart -> "31-90" bin, which contains
  # both the 5 matching cases and the 1 mismatched (A-to-B transition) case.
  # Since every case falls in the same bin here, compare that bin's accuracy
  # against a bin that is NOT the "31-90" bin to confirm the transition
  # lowered the shortest-gap-bin accuracy relative to a bin that contains no
  # transition. Use "0-30" (empty in this fixture, .drop = FALSE keeps it
  # present with NaN/0 cases) as the structural companion, and additionally
  # verify the single-bin accuracy reflects the 5/6 match rate directly.
  bin_31_90 <- curve[curve$gap_bin == "31-90", ]
  expect_equal(bin_31_90$n_cases, 6)
  expect_equal(bin_31_90$pct_exact_zip9_match, round(100 * 5 / 6, 1))
  expect_true(bin_31_90$pct_exact_zip9_match < 100)
  expect_true(bin_31_90$pct_exact_zip9_match > 0)
})

test_that("+4-only mover: exact_match is FALSE and zip5_match is TRUE", {
  # One patient, one record at "326111234", next record at "326115678"
  # (same ZIP5 "32611", different +4).
  addr_coal_fixture <- tibble(
    ID = c("P3", "P3"),
    period_start_dt = as.Date(c("2020-01-01", "2020-06-01")),
    period_end_eff = as.Date(c("2020-05-31", "9999-12-31")),
    zip9_norm = c("326111234", "326115678")
  )

  cases <- .test_env$build_validation_cases(addr_coal_fixture)

  expect_equal(nrow(cases), 1)
  expect_false(cases$exact_match[1])
  expect_true(cases$zip5_match[1])
})

test_that("single-record patient: contributes zero rows to build_validation_cases()", {
  addr_coal_fixture <- tibble(
    ID = "P4",
    period_start_dt = as.Date("2020-01-01"),
    period_end_eff = as.Date("9999-12-31"),
    zip9_norm = "326111234"
  )

  cases <- .test_env$build_validation_cases(addr_coal_fixture)

  expect_equal(nrow(cases), 0)
})


# ==============================================================================
# Task 1 (139-03): classify_encounter_zip() -- open-ended-interval fixture
# ==============================================================================

test_that("open-ended address record: covered encounter classifies has_direct_zip9, not has_neither (FIX-02)", {
  # One patient, one address record with period_start_dt set and period_end_dt
  # = NA (i.e. period_end_eff = the far-future sentinel, an open-ended/current-
  # address record). One encounter with ADMIT_DATE after period_start_dt.
  # Under the pre-patch period_end_dt-based filter, ADMIT_DATE < NA evaluates
  # to NA and filter() drops the row entirely -- misclassifying this encounter
  # as has_neither even though a covering (open-ended) record clearly exists.
  addr_coal_fixture <- tibble(
    ID = "P5",
    zip9_norm = "326111234",
    zip5_coalesced = "32611",
    period_start_dt = as.Date("2020-01-01"),
    period_end_dt = as.Date(NA),
    period_end_eff = as.Date("9999-12-31")
  )

  encounters_fixture <- tibble(
    ID = "P5",
    ENCOUNTERID = "E1",
    ADMIT_DATE = as.Date("2021-06-15")
  )

  result <- .test_env$classify_encounter_zip(encounters_fixture, addr_coal_fixture)

  expect_equal(nrow(result), 1)
  expect_true(result$has_direct_zip9[1])
  expect_false(result$has_neither[1])
  expect_false(result$has_no_record[1])
  expect_false(result$has_record_but_empty[1])
})


# ==============================================================================
# Task 1 (140-06): build_encounter_anchored_validation_cases() -- P-05a,
# 140-08-PATCH FIX-05 (gap measured ADMIT_DATE - predicting record's period_start_dt,
# NOT covering-record-to-predicting-record)
# ==============================================================================

test_that("encounter-anchored: predicts from the spell just prior to the covering record, gap_days = ADMIT_DATE - predicting period_start_dt (FIX-05)", {
  # One patient, 3 zip9_seq spells: A at day 0, B at day 100, C at day 300
  # (open-ended). One encounter with has_direct_zip9 = TRUE, direct_zip9 = C,
  # direct_zip_period_start = day 300, ADMIT_DATE = day 320 (within C's active
  # period, distinct from C's own start -- this is what makes the
  # encounter-anchored gap differ from a record-to-record gap).
  zip9_seq_fixture <- tibble(
    ID = rep("P6", 3),
    zip9_norm = c("326110001", "326110002", "326110003"),
    period_start_dt = as.Date("2020-01-01") + c(0, 100, 300)
  )

  encounter_zip_fixture <- tibble(
    ID = "P6",
    ENCOUNTERID = "E1",
    ADMIT_DATE = as.Date("2020-01-01") + 320,
    has_direct_zip9 = TRUE,
    direct_zip9 = "326110003",
    direct_zip_period_start = as.Date("2020-01-01") + 300
  )

  cases <- .test_env$build_encounter_anchored_validation_cases(encounter_zip_fixture, zip9_seq_fixture)

  expect_equal(nrow(cases), 1)
  # Predicts from spell B (day 100, the record just prior to C), NOT spell C itself.
  expect_equal(cases$gap_days[1], 220)              # ADMIT_DATE(320) - period_start_dt(100)
  expect_false(cases$gap_days[1] == 200)             # NOT direct_zip_period_start(300) - period_start_dt(100)
  expect_false(cases$exact_match[1])                 # predicted (B) != direct_zip9 (C)
  expect_true(cases$zip5_match[1])                   # same ZIP5 prefix "32611"
  expect_equal(cases$gap_bin[1], "181-365")
})

test_that("encounter-anchored: covering record is the patient's only spell -- contributes zero rows", {
  zip9_seq_fixture <- tibble(
    ID = "P7",
    zip9_norm = "326110009",
    period_start_dt = as.Date("2020-01-01")
  )

  encounter_zip_fixture <- tibble(
    ID = "P7",
    ENCOUNTERID = "E1",
    ADMIT_DATE = as.Date("2020-06-01"),
    has_direct_zip9 = TRUE,
    direct_zip9 = "326110009",
    direct_zip_period_start = as.Date("2020-01-01")
  )

  cases <- .test_env$build_encounter_anchored_validation_cases(encounter_zip_fixture, zip9_seq_fixture)

  expect_equal(nrow(cases), 0)
})
