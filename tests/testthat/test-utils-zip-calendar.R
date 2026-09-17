# ==============================================================================
# test-utils-zip-calendar.R -- Unit tests for utils_zip_calendar.R (Phase 153)
# ==============================================================================
# Purpose:
#   Behaviorally tests all three functions from R/utils/utils_zip_calendar.R:
#     - build_patient_zip_calendar()
#     - pick_best_zip()
#     - compute_encounter_distance()
#
#   Tests exercise pure functions with small in-memory frames.
#   No HiPerGator data required. The test file sources R/00_config.R (which
#   auto-sources all R/utils/*.R files), then sources utils_zip_calendar.R
#   explicitly (since it is NOT in the auto-sourced set -- it is sourced
#   explicitly by R/122 only, per SCRIPT_INDEX.md).
#
# Sourcing convention: follows test-utils-address.R's withr::with_dir() pattern
#   to restore a project-root working directory before calling source(), since
#   testthat sets the working directory to tests/testthat/ during a run.
#
# Tests 1-5, 7, 8: build_patient_zip_calendar() / pick_best_zip() -- pure,
#   no external API calls, MUST NOT be skipped.
# Test 6: compute_encounter_distance() with patient_zip_missing path -- the
#   patient ZIP is NA, so zipcodeR::zip_distance() is never called with real
#   ZIPs. Wrapped in skip_if_not_installed("zipcodeR") as a safety net for
#   environments where zipcodeR is absent, but the patient_zip_missing
#   classification path itself does not resolve any centroid.
#
# Behavioral assertions locked:
#   - D-04 two-zone ranking (in-range ZIP9 > in-range ZIP5 > out-of-range any)
#   - D-05 equal-|days_offset| tie-break (earlier period wins)
#   - Duplicate collapse to one calendar row
#   - Overlapping same-ZIP period merge
#   - Open ADDRESS_PERIOD_END closed at study_end (2025-03-31)
#   - No-address patient yields patient_zip_missing
#   - Out-of-range: ZIP tier ignored (nearest wins regardless of zip_len)
# ==============================================================================

library(testthat)
library(dplyr)
library(tibble)

.project_root <- here::here()

# Source R/00_config.R (auto-loads utils_address.R and other utils)
withr::with_dir(.project_root, source("R/00_config.R"))

# Source utils_zip_calendar.R explicitly (not in R/00_config.R auto-load list)
withr::with_dir(.project_root, source("R/utils/utils_zip_calendar.R"))


# ==============================================================================
# Test 1: Duplicate address periods collapse to ONE calendar row
# ==============================================================================

test_that("Duplicate address periods collapse to one calendar row", {
  dup_addr <- tibble(
    ID                   = c("P1", "P1"),
    ADDRESS_ZIP9         = c("326111234", "326111234"),
    ADDRESS_ZIP5         = c("32611",     "32611"),
    ADDRESS_PERIOD_START = c("2015-01-01", "2015-01-01"),
    ADDRESS_PERIOD_END   = c("2020-12-31", "2020-12-31")
  )

  cal <- build_patient_zip_calendar(dup_addr)

  expect_equal(nrow(cal), 1L,
    label = "Two identical (ID, ZIP, period) rows must collapse to exactly one calendar row")
  expect_equal(cal$start, as.Date("2015-01-01"))
  expect_equal(cal$end,   as.Date("2020-12-31"))
  expect_equal(cal$zip5,  "32611")
})


# ==============================================================================
# Test 2: Overlapping / touching same-ZIP periods merge into one run
# ==============================================================================

test_that("Overlapping same-ZIP periods merge; start = min, end = max", {
  overlap_addr <- tibble(
    ID                   = c("P2", "P2"),
    ADDRESS_ZIP9         = c("326111234", "326111234"),
    ADDRESS_ZIP5         = c("32611",     "32611"),
    ADDRESS_PERIOD_START = c("2015-01-01", "2016-06-01"),
    ADDRESS_PERIOD_END   = c("2017-03-31", "2020-12-31")
  )

  cal <- build_patient_zip_calendar(overlap_addr)

  expect_equal(nrow(cal), 1L,
    label = "Overlapping same-ZIP periods must merge into one run")
  expect_equal(cal$start, as.Date("2015-01-01"))
  expect_equal(cal$end,   as.Date("2020-12-31"))
})


# ==============================================================================
# Test 3: ZIP9 in-range wins over ZIP5 in-range (D-04)
# ==============================================================================

test_that("In-range ZIP9 beats in-range ZIP5 on the same ADMIT_DATE (D-04)", {
  # Build a calendar with two overlapping periods on the admit date:
  #   zip9 period (zip_len = 9) and zip5-only period (zip_len = 5).
  # Both cover the admit date. ZIP9 must win.
  cal <- tibble(
    ID      = c("P3", "P3"),
    zip9    = c("326111234", NA_character_),
    zip5    = c("32611",     "32612"),
    zip_len = c(9L, 5L),
    start   = as.Date(c("2018-01-01", "2018-01-01")),
    end     = as.Date(c("2020-12-31", "2020-12-31"))
  )

  enc <- tibble(
    ID          = "P3",
    ENCOUNTERID = "E3",
    ADMIT_DATE  = as.Date("2019-06-15")
  )

  result <- pick_best_zip(enc, cal)

  expect_equal(result$zip5_patient_source, "in_range_zip9",
    label = "ZIP9 in-range period must win over ZIP5 in-range period")
  expect_equal(result$n_candidates_in_range, 2L,
    label = "Both in-range periods must be counted as n_candidates_in_range = 2")
})


# ==============================================================================
# Test 4: Equal |days_offset| -> earlier period wins (D-05)
# ==============================================================================

test_that("Equal |days_offset| tie-break: earlier (positive offset) period wins (D-05)", {
  # Encounter on 2019-06-15 with no covering period.
  # Period A ends 2019-06-10 (5 days before -> offset +5, positive, EARLIER).
  # Period B starts 2019-06-20 (5 days after -> offset -5, negative, LATER).
  # D-05: prefer the earlier period -> days_offset must be POSITIVE.
  # Both periods are out-of-range (Zone 2), so ZIP tier is irrelevant for ranking.
  cal <- tibble(
    ID      = c("P4", "P4"),
    zip9    = c("326111234", "326229999"),
    zip5    = c("32611",     "32622"),
    zip_len = c(9L, 9L),
    start   = as.Date(c("2018-01-01", "2019-06-20")),
    end     = as.Date(c("2019-06-10", "2021-12-31"))
  )

  enc <- tibble(
    ID          = "P4",
    ENCOUNTERID = "E4",
    ADMIT_DATE  = as.Date("2019-06-15")
  )

  result <- pick_best_zip(enc, cal)

  expect_true(result$days_offset > 0,
    label = "D-05: equal |days_offset| -> earlier (positive offset) period must win")
  expect_equal(result$zip5_patient, "32611",
    label = "Earlier period's ZIP5 must be selected")
})


# ==============================================================================
# Test 5: In-range ZIP5 beats out-of-range ZIP9 (Zone 1 always beats Zone 2)
# ==============================================================================

test_that("In-range ZIP5 beats out-of-range ZIP9 (D-04 Zone 1 > Zone 2)", {
  # Calendar: one ZIP5-only in-range period, one ZIP9 out-of-range period.
  # The in-range ZIP5 must win despite the higher zip_len of the ZIP9.
  cal <- tibble(
    ID      = c("P5", "P5"),
    zip9    = c(NA_character_, "326229999"),
    zip5    = c("32611",       "32622"),
    zip_len = c(5L, 9L),
    start   = as.Date(c("2018-01-01", "2015-01-01")),
    end     = as.Date(c("2020-12-31", "2016-12-31"))
  )

  enc <- tibble(
    ID          = "P5",
    ENCOUNTERID = "E5",
    ADMIT_DATE  = as.Date("2019-06-15")  # covered by ZIP5 period, not ZIP9 period
  )

  result <- pick_best_zip(enc, cal)

  expect_equal(result$zip5_patient_source, "in_range_zip5",
    label = "In-range ZIP5 must beat out-of-range ZIP9")
  expect_equal(result$zip5_patient, "32611")
})


# ==============================================================================
# Test 6: No address history -> distance_status == "patient_zip_missing"
# ==============================================================================

test_that("Patient with no address history yields patient_zip_missing", {
  skip_if_not_installed("zipcodeR")

  # Empty calendar (no rows for patient P6).
  empty_cal <- tibble(
    ID      = character(0),
    zip9    = character(0),
    zip5    = character(0),
    zip_len = integer(0),
    start   = as.Date(character(0)),
    end     = as.Date(character(0))
  )

  enc <- tibble(
    ID             = "P6",
    ENCOUNTERID    = "E6",
    ADMIT_DATE     = as.Date("2019-06-15"),
    zip5_facility  = "32608"
  )

  result <- compute_encounter_distance(enc, empty_cal)

  expect_equal(result$distance_status, "patient_zip_missing",
    label = "Patient with no calendar rows must yield distance_status == 'patient_zip_missing'")
})


# ==============================================================================
# Test 7: Open-ended ADDRESS_PERIOD_END closes at study end (2025-03-31)
# ==============================================================================

test_that("Open ADDRESS_PERIOD_END (NA) closes at study end 2025-03-31", {
  open_addr <- tibble(
    ID                   = "P7",
    ADDRESS_ZIP9         = "326111234",
    ADDRESS_ZIP5         = "32611",
    ADDRESS_PERIOD_START = "2015-01-01",
    ADDRESS_PERIOD_END   = NA_character_
  )

  cal <- build_patient_zip_calendar(open_addr)

  expect_equal(cal$end, as.Date("2025-03-31"),
    label = "Open ADDRESS_PERIOD_END must close at as.Date('2025-03-31')")
  expect_equal(nrow(cal), 1L)
})


# ==============================================================================
# Test 8: Out-of-range nearest -- ZIP tier ignored (D-04 Zone 2)
# ==============================================================================

test_that("Out-of-range nearest: ZIP5 period nearer in time beats ZIP9 farther away (D-04 Zone 2)", {
  # Encounter on 2019-06-15, no covering period.
  # ZIP9 period ends 2018-01-01 (offset +530 days -- far before).
  # ZIP5 period ends 2019-06-01 (offset +14 days -- near before).
  # D-04: in Zone 2, ZIP tier is irrelevant -> ZIP5 (nearer) wins.
  cal <- tibble(
    ID      = c("P8", "P8"),
    zip9    = c("326229999", NA_character_),
    zip5    = c("32622",     "32611"),
    zip_len = c(9L, 5L),
    start   = as.Date(c("2015-01-01", "2017-01-01")),
    end     = as.Date(c("2018-01-01", "2019-06-01"))
  )

  enc <- tibble(
    ID          = "P8",
    ENCOUNTERID = "E8",
    ADMIT_DATE  = as.Date("2019-06-15")
  )

  result <- pick_best_zip(enc, cal)

  expect_equal(result$zip5_patient_source, "nearest_zip5",
    label = "Nearer ZIP5 period must win over farther ZIP9 (Zone 2: ZIP tier ignored)")
  expect_equal(result$zip5_patient, "32611",
    label = "ZIP5 (nearer) wins in Zone 2 regardless of zip_len")
})


# ==============================================================================
# Test 9: Adjacent periods merge into one run
# ==============================================================================

test_that("Adjacent same-ZIP periods (touching, no gap) merge into one run", {
  # Period A: 2020-01-01 to 2020-06-30
  # Period B: 2020-07-01 to 2020-12-31
  # They are adjacent (end+1 == next start), so they should merge to 2020-01-01..2020-12-31.
  adj_addr <- tibble(
    ID                   = c("P9", "P9"),
    ADDRESS_ZIP9         = c("326111234", "326111234"),
    ADDRESS_ZIP5         = c("32611",     "32611"),
    ADDRESS_PERIOD_START = c("2020-01-01", "2020-07-01"),
    ADDRESS_PERIOD_END   = c("2020-06-30", "2020-12-31")
  )

  cal <- build_patient_zip_calendar(adj_addr)

  expect_equal(nrow(cal), 1L,
    label = "Adjacent same-ZIP periods must merge into one run")
  expect_equal(cal$start, as.Date("2020-01-01"))
  expect_equal(cal$end,   as.Date("2020-12-31"))
})


# ==============================================================================
# Test 10: Gap periods stay as two runs
# ==============================================================================

test_that("Same ZIP with gap between periods stays as two runs", {
  # Period A: 2020-01-01 to 2020-03-31
  # Period B: 2020-06-01 to 2020-12-31
  # Gap: 2020-04-01 to 2020-05-31 (61 days). Must stay as two rows.
  gap_addr <- tibble(
    ID                   = c("P10", "P10"),
    ADDRESS_ZIP9         = c("326111234", "326111234"),
    ADDRESS_ZIP5         = c("32611",     "32611"),
    ADDRESS_PERIOD_START = c("2020-01-01", "2020-06-01"),
    ADDRESS_PERIOD_END   = c("2020-03-31", "2020-12-31")
  )

  cal <- build_patient_zip_calendar(gap_addr)

  expect_equal(nrow(cal), 2L,
    label = "Same ZIP with a gap between periods must yield two calendar rows")
  expect_equal(cal$start[1], as.Date("2020-01-01"))
  expect_equal(cal$end[1],   as.Date("2020-03-31"))
  expect_equal(cal$start[2], as.Date("2020-06-01"))
  expect_equal(cal$end[2],   as.Date("2020-12-31"))
})


# ==============================================================================
# Test 11: Row with NA ADDRESS_PERIOD_START is dropped with a message
# ==============================================================================

test_that("Row with NA ADDRESS_PERIOD_START is dropped and a message is emitted", {
  na_start_addr <- tibble(
    ID                   = c("P11", "P11"),
    ADDRESS_ZIP9         = c("326111234", "326111234"),
    ADDRESS_ZIP5         = c("32611",     "32611"),
    ADDRESS_PERIOD_START = c(NA_character_, "2020-01-01"),
    ADDRESS_PERIOD_END   = c("2020-12-31",  "2020-12-31")
  )

  expect_message(
    cal <- build_patient_zip_calendar(na_start_addr),
    regexp = "dropping.*NA ADDRESS_PERIOD_START"
  )
  # Only the valid row should remain
  expect_equal(nrow(cal), 1L,
    label = "The row with NA start must be dropped")
})


# ==============================================================================
# Test 12: compute_encounter_distance() output has no ADMIT_DATE column
# ==============================================================================

test_that("compute_encounter_distance() output has no ADMIT_DATE column", {
  skip_if_not_installed("zipcodeR")

  cal <- tibble(
    ID      = "P12",
    zip9    = "326111234",
    zip5    = "32611",
    zip_len = 9L,
    start   = as.Date("2015-01-01"),
    end     = as.Date("2025-03-31")
  )

  enc <- tibble(
    ID            = "P12",
    ENCOUNTERID   = "E12",
    ADMIT_DATE    = as.Date("2019-06-15"),
    zip5_facility = "32608"
  )

  result <- compute_encounter_distance(enc, cal)

  expect_false(
    "ADMIT_DATE" %in% names(result),
    label = "compute_encounter_distance() must NOT return an ADMIT_DATE column"
  )
})
