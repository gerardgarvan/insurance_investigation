# ==============================================================================
# test-115-scenarios.R -- Behavioral tests for ordered scenario assignment (Phase 140)
# ==============================================================================
# Purpose: Synthetic-fixture tests for assign_scenarios(), defined in
#          R/115_zip_stability_counts.R SECTION 1B (added by 140-04, P-06b: S1
#          folded into S3 universally in the ordered assignment). This file is
#          shared with 140-05 (140-08-PATCH FIX-16), which appends its own
#          test_that() block later once its own function exists.
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
# Task 1 (140-04): assign_scenarios() -- S1-collapsed, dual-mode ordered assignment (P-06b)
# ==============================================================================

test_that("assign_scenarios() folds S1 into S3 universally and varies S2 by mode", {
  # Synthetic 4-row encounter_zip-shaped tibble, one row per case:
  #   (a) has_direct_zip9 = TRUE -> "already_has_zip9" in both modes
  #   (b) forward-only S2 (has_direct_zip5_only = FALSE, s2_backward = FALSE,
  #       s2_either = TRUE) -> "S2" under backward_only = FALSE but
  #       "unresolvable" under backward_only = TRUE
  #   (c) an old S1-forward-only case (has_direct_zip5_only = TRUE,
  #       s1_backward = FALSE, s1_forward = TRUE) -> "S3" in BOTH modes,
  #       proving the fold-in is universal, not conditional
  #   (d) none of the above -> "unresolvable" in both modes
  fixture <- tibble(
    case                  = c("a_already_zip9", "b_forward_only_s2", "c_old_s1_forward_only", "d_none"),
    has_direct_zip9       = c(TRUE,  FALSE, FALSE, FALSE),
    has_direct_zip5_only  = c(FALSE, FALSE, TRUE,  FALSE),
    s1_backward           = c(FALSE, FALSE, FALSE, FALSE),
    s1_forward            = c(FALSE, FALSE, TRUE,  FALSE),
    s1_either             = c(FALSE, FALSE, TRUE,  FALSE),
    s2_backward           = c(FALSE, FALSE, FALSE, FALSE),
    s2_forward            = c(FALSE, TRUE,  FALSE, FALSE),
    s2_either             = c(FALSE, TRUE,  FALSE, FALSE)
  )

  forward_inclusive <- .test_env$assign_scenarios(fixture, backward_only = FALSE)
  backward_only      <- .test_env$assign_scenarios(fixture, backward_only = TRUE)

  expect_equal(
    as.character(forward_inclusive$scenario_assigned),
    c("already_has_zip9", "S2", "S3", "unresolvable")
  )
  expect_equal(
    as.character(backward_only$scenario_assigned),
    c("already_has_zip9", "unresolvable", "S3", "unresolvable")
  )

  # Both variants use the collapsed 4-level factor (no separate "S1" level).
  expect_equal(levels(forward_inclusive$scenario_assigned),
               c("already_has_zip9", "S2", "S3", "unresolvable"))
  expect_equal(levels(backward_only$scenario_assigned),
               c("already_has_zip9", "S2", "S3", "unresolvable"))
})


# ==============================================================================
# Task 1 (140-05): compute_gap_days_at_assignment() -- two independently-computed signed
# gap covariates (P-04a, 140-08-PATCH FIX-01/FIX-02/FIX-08)
# ==============================================================================

test_that("compute_gap_days_at_assignment() computes both gap columns per the documented sign convention", {
  ADMIT <- as.Date("2020-06-01")

  # One row per case (a)-(f), keyed by (ID, ENCOUNTERID, ADMIT_DATE).
  encounter_zip_flagged <- tibble(
    ID                      = c("a", "b", "c", "d", "e", "f"),
    ENCOUNTERID             = c("a", "b", "c", "d", "e", "f"),
    ADMIT_DATE              = rep(ADMIT, 6),
    has_direct_zip9         = c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE),
    direct_zip_period_start = as.Date(c("2020-05-22", NA, NA, NA, NA, NA))
  )

  # s1_matches: (b) S3-resolved backward-only (40 days prior); (c) S3-resolved forward-only
  # (15 days after); (f) S3-resolved with an exact tie (30 days before AND 30 days after).
  s1_matches <- tibble(
    ID              = c("b", "c", "f", "f"),
    ENCOUNTERID     = c("b", "c", "f", "f"),
    ADMIT_DATE      = rep(ADMIT, 4),
    period_start_dt = as.Date(c("2020-04-22", "2020-06-16", "2020-05-02", "2020-07-01")),
    direction       = c("backward", "forward", "backward", "forward")
  )

  # s2_matches: (e) FIX-01 forward-only S2 (20 days after ADMIT_DATE, no backward candidate).
  s2_matches <- tibble(
    ID              = c("e"),
    ENCOUNTERID     = c("e"),
    ADMIT_DATE      = rep(ADMIT, 1),
    period_start_dt = as.Date(c("2020-06-21")),
    direction       = c("forward")
  )

  result <- .test_env$compute_gap_days_at_assignment(encounter_zip_flagged, s1_matches, s2_matches)
  by_case <- result %>% arrange(ID) %>% select(ID, gap_days_at_assignment, gap_days_at_assignment_backward_only)

  # (a) already_has_zip9, covering record 10 days before ADMIT_DATE -> both columns == 10.
  expect_equal(by_case$gap_days_at_assignment[by_case$ID == "a"], 10)
  expect_equal(by_case$gap_days_at_assignment_backward_only[by_case$ID == "a"], 10)

  # (b) S3-resolved via a backward match 40 days prior (no forward candidate) -> both == 40.
  expect_equal(by_case$gap_days_at_assignment[by_case$ID == "b"], 40)
  expect_equal(by_case$gap_days_at_assignment_backward_only[by_case$ID == "b"], 40)

  # (c) S3-resolved via a FORWARD-ONLY match 15 days after ADMIT_DATE (no backward candidate)
  # -> gap_days_at_assignment == -15 (negative, forward inference); backward-only == NA
  # (140-08-PATCH FIX-02: never carries a forward-inferred value).
  expect_equal(by_case$gap_days_at_assignment[by_case$ID == "c"], -15)
  expect_true(is.na(by_case$gap_days_at_assignment_backward_only[by_case$ID == "c"]))

  # (d) unresolvable under both specifications (no rows in s1_matches/s2_matches, no direct
  # ZIP9) -> NA in both columns.
  expect_true(is.na(by_case$gap_days_at_assignment[by_case$ID == "d"]))
  expect_true(is.na(by_case$gap_days_at_assignment_backward_only[by_case$ID == "d"]))

  # (e) 140-08-PATCH FIX-01: forward-only S2, 20 days after ADMIT_DATE -> gap_days_at_assignment
  # == -20 (resolved under forward-inclusive S2); backward-only == NA (unresolvable under
  # backward-only, since no backward S2 candidate exists).
  expect_equal(by_case$gap_days_at_assignment[by_case$ID == "e"], -20)
  expect_true(is.na(by_case$gap_days_at_assignment_backward_only[by_case$ID == "e"]))

  # (f) 140-08-PATCH FIX-08: S3-resolved with two candidates, exactly 30 days before AND
  # exactly 30 days after ADMIT_DATE -> gap_days_at_assignment == 30 (backward wins the exact
  # tie, not row order) AND gap_days_at_assignment_backward_only == 30 (the backward candidate
  # is also the only one available to the backward-only reduction).
  expect_equal(by_case$gap_days_at_assignment[by_case$ID == "f"], 30)
  expect_equal(by_case$gap_days_at_assignment_backward_only[by_case$ID == "f"], 30)

  # 140-08-PATCH FIX-02: the never-negative invariant, asserted the same way the production
  # script asserts it.
  expect_true(all(result$gap_days_at_assignment_backward_only >= 0, na.rm = TRUE))
})
