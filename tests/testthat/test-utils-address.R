# ==============================================================================
# test-utils-address.R -- Behavioral tests for get_zip9_at_date() (Phase 140)
# ==============================================================================
# Purpose: Synthetic-fixture tests for get_zip9_at_date(), defined in
#          R/utils/utils_address.R. Per 140-08-PATCH FIX-16, this is a NEW,
#          dedicated file -- it does NOT use the .test_env/sys.source() pattern
#          test-115-c02.R / test-115-scenarios.R / test-115-validation-curve.R
#          use to reach past R/115_zip_stability_counts.R's SECTION 2 probe
#          gate. get_zip9_at_date() is a shared production utility, not a
#          R/115 SECTION 1B function -- it is sourced normally, via
#          source("R/00_config.R")'s standard R/utils/*.R auto-sourcing loop
#          (R/00_config.R lines ~4083-4093), exactly how any other script in
#          this project loads it.
#
# addr_full column-type contract (P-07c, 140-08-PATCH FIX-10): when supplied,
# get_zip9_at_date()'s optional addr_full injection seam MUST have columns
# that are character or Date -- matching what the CSV load path (vroom with
# col_types = cols(.default = "c"), or the read.csv() fallback) produces. A
# POSIXct column is NOT guaranteed to survive get_zip9_at_date()'s internal
# as.character() coercion into a format parse_pcornet_date() can parse (e.g.
# it would coerce to "2020-01-01 00:00:00", not the ISO "2020-01-01" this
# fixture uses). This seam is a test seam only, not a general-purpose
# data-loader replacement -- see get_zip9_at_date()'s own roxygen block for
# the same contract stated at the function definition.
#
# testthat::test_file()/test_dir() run test files with the working directory
# set to the test file's own directory (tests/testthat), not the project root
# -- see vignette("special-files"). R/00_config.R's own relative paths (e.g.
# "R/utils") assume a project-root working directory. withr::with_dir()
# temporarily restores a project-root working directory (located via
# here::here(), which walks up from the current directory looking for project
# markers such as .git) for the duration of the source() call, then restores
# the prior directory.
# ==============================================================================

library(testthat)
library(dplyr)
library(tibble)

.project_root <- here::here()

withr::with_dir(.project_root, source("R/00_config.R"))


# ==============================================================================
# Task 2 (140-07): get_zip9_at_date() addr_full injection seam (P-07c, FIX-10)
# ==============================================================================

test_that("get_zip9_at_date(addr_full = ...) covers interval/most_recent_before/none, no file I/O", {
  # Synthetic address history, character/Date columns only (per the documented
  # contract) -- no CONFIG$data_dir, no vroom/read.csv call.
  #   P1: one open interval-covering record for the query date -> "interval"
  #   P2: one closed record ending BEFORE the query date, no other record
  #       covering it -> "most_recent_before"
  #   P3: no address record at all -> "none"
  addr_full_fixture <- tibble(
    ID                    = c("P1", "P2"),
    ADDRESS_ZIP9          = c("326111234", "326229999"),
    ADDRESS_PERIOD_START  = as.Date(c("2020-01-01", "2020-01-01")),
    ADDRESS_PERIOD_END    = as.Date(c("2020-12-31", "2020-06-30"))
  )

  ids   <- c("P1", "P2", "P3")
  dates <- as.Date(c("2020-06-15", "2021-01-01", "2020-06-15"))

  result <- get_zip9_at_date(ids, dates, addr_full = addr_full_fixture)

  expect_equal(nrow(result), 3)

  p1_row <- result[result$ID == "P1", ]
  expect_equal(p1_row$match_type, "interval")
  expect_equal(p1_row$ZIP9, "326111234")
  expect_equal(p1_row$ZIP5, "32611")

  p2_row <- result[result$ID == "P2", ]
  expect_equal(p2_row$match_type, "most_recent_before")
  expect_equal(p2_row$ZIP9, "326229999")
  expect_equal(p2_row$ZIP5, "32622")

  p3_row <- result[result$ID == "P3", ]
  expect_equal(p3_row$match_type, "none")
  expect_true(is.na(p3_row$ZIP9))
  expect_true(is.na(p3_row$ZIP5))
})

test_that("get_zip9_at_date(addr_full = NULL) default arg preserves existing signature", {
  # Not a behavioral test of the load-on-demand path itself (that requires
  # CONFIG$data_dir / a real LDS_ADDRESS_HISTORY file, unavailable in this
  # environment) -- only confirms the default argument exists and that
  # omitting addr_full does not error at the formals-matching stage before
  # CONFIG$data_dir is even touched.
  expect_true("addr_full" %in% names(formals(get_zip9_at_date)))
  expect_null(formals(get_zip9_at_date)$addr_full)
})
