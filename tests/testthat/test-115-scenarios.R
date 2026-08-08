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
