# ==============================================================================
# tests/testthat/test-utils_address_approximate_zip9.R
# Phase 139 -- acceptance + unit tests for approximate_zip9()
# ==============================================================================
#
# AMEND-07: 12 test cases (0-11) covering integration path, all zip9_source
# branches, tie-breaks, schema invariants, and determinism.
#
# Run: testthat::test_file("tests/testthat/test-utils_address_approximate_zip9.R")
# Or:  testthat::test_dir("tests/testthat", filter = "utils_address_approximate_zip9")
#
# Dependencies: testthat (>= 3.0), withr, dplyr, tibble, vroom, glue
# ==============================================================================

library(testthat)
library(dplyr)
library(tibble)
library(stringr)
library(glue)
library(vroom)

# Bootstrap minimal environment for utils_address.R without sourcing the full
# 00_config.R (which transitively requires DBI, duckdb, openxlsx2, etc.).
# We replicate only what utils_address.R actually needs:
#   1. CONFIG list with $data_dir
#   2. parse_pcornet_date() from utils_dates.R
{
  proj_root <- here::here()

  # Minimal CONFIG with data_dir pointing at the fixtures dir (default for IS_LOCAL)
  if (!exists("CONFIG", envir = .GlobalEnv)) {
    CONFIG <<- list(data_dir = file.path(proj_root, "tests", "fixtures"))
  }

  # Source only the two utility files we need
  source(file.path(proj_root, "R", "utils", "utils_dates.R"))
  source(file.path(proj_root, "R", "utils", "utils_address.R"))
}

# ---- Helper: write a synthetic LDS CSV to a temp directory ------------------

write_lds_csv <- function(dir, rows) {
  # rows: list of named lists or a data.frame; column names must match LDS schema
  tbl <- as_tibble(rows)
  # Ensure required columns present with character type
  if (!"ADDRESS_PERIOD_END" %in% names(tbl)) tbl$ADDRESS_PERIOD_END <- NA_character_
  path <- file.path(dir, "LDS_ADDRESS_HISTORY_Mailhot_V1.csv")
  write.csv(tbl, path, row.names = FALSE, quote = TRUE)
  invisible(path)
}

# ---- Helper: save/restore CONFIG$data_dir (AMEND-07c) ----------------------
# CONFIG is a list in the global env; withr::local_options() won't work.
# Use withr::defer() to restore it on test exit.

set_data_dir <- function(path) {
  old <- CONFIG$data_dir
  CONFIG$data_dir <<- path
  withr::defer(
    { CONFIG$data_dir <<- old },
    envir = parent.frame()
  )
}

# ---- Synthetic LDS data used by multiple tests ------------------------------

lds_base <- tribble(
  ~ID,    ~ADDRESS_ZIP9, ~ADDRESS_PERIOD_START, ~ADDRESS_PERIOD_END,
  # ZIP5 12345: 3 records -> ZIP9 123450001 (modal, 2 patients), 123450002 (1 patient)
  "P01",  "123450001",   "2020-01-01",           "2022-12-31",
  "P02",  "123450001",   "2021-03-01",           NA,
  "P03",  "123450002",   "2022-01-01",           NA,
  # ZIP5 99999: only bare-5-digit or invalid values -> no modal
  "P04",  "99999",       "2020-06-01",           NA,
  "P05",  "99999",       "2021-01-01",           NA,
  # ZIP5 12345 bare record that triggered AMEND-01: should become ZIP5 via coalesce
  "P10",  "12345",       "2019-01-01",           "2021-12-31"
)

# ---- Test 0 (integration — acceptance gate, AMEND-07a) ----------------------

test_that("Test 0: integration path yields at least one zip5_modal row", {
  td <- withr::local_tempdir()

  # Write LDS CSV including a row with bare ZIP5 in ADDRESS_ZIP9 (AMEND-01 trigger)
  write_lds_csv(td, lds_base)

  # Set CONFIG$data_dir to temp dir
  old_dir <- CONFIG$data_dir
  CONFIG$data_dir <<- td
  on.exit(CONFIG$data_dir <<- old_dir, add = TRUE)

  # Invalidate memo cache so we pick up the new file
  .zip5_lookup_cache$key   <<- NULL
  .zip5_lookup_cache$value <<- NULL

  # P10 has a bare ZIP5 ("12345") in ADDRESS_ZIP9; after AMEND-01 fix, get_zip9_at_date()
  # should return ZIP5 = "12345" and ZIP9 = NA for that patient. approximate_zip9()
  # should then fill ZIP9 from the modal (123450001).
  ids   <- c("P10")
  dates <- as.Date(c("2020-06-01"))

  result <- get_zip9_at_date(ids, dates) |> approximate_zip9()

  expect_true(
    sum(result$zip9_source == "zip5_modal", na.rm = TRUE) > 0,
    info = "Expected at least one zip5_modal row from real get_zip9_at_date() + approximate_zip9()"
  )
})

# ---- Shared fixture builder for unit tests ----------------------------------

# Build a minimal result_tbl as if get_zip9_at_date() produced it
make_result_row <- function(ID, query_date, ZIP9, ZIP5, match_type) {
  tibble(
    ID         = ID,
    query_date = as.Date(query_date),
    ZIP9       = ZIP9,
    ZIP5       = ZIP5,
    match_type = match_type
  )
}

run_approx <- function(result_tbl, lds_rows) {
  td <- withr::local_tempdir()
  write_lds_csv(td, lds_rows)
  old_dir <- CONFIG$data_dir
  CONFIG$data_dir <<- td
  on.exit(CONFIG$data_dir <<- old_dir, add = TRUE)
  # Reset memo cache each test
  .zip5_lookup_cache$key   <<- NULL
  .zip5_lookup_cache$value <<- NULL
  approximate_zip9(result_tbl)
}

# ---- Test 1: zip5_modal -------------------------------------------------------

test_that("Test 1: zip5_modal -- ZIP9 filled from clear modal", {
  input <- make_result_row("P01", "2021-01-01", NA_character_, "12345", "interval")
  out   <- run_approx(input, lds_base)

  expect_equal(out$zip9_source, "zip5_modal")
  expect_equal(out$ZIP9, "123450001")
  expect_equal(out$match_type, "interval")     # match_type unchanged
  expect_false(is.na(out$zip5_modal_freq))
  expect_false(is.na(out$zip5_n_candidates))
  expect_false(is.na(out$zip5_modal_share))
})

# ---- Test 2: zip5_no_zip9 ----------------------------------------------------

test_that("Test 2: zip5_no_zip9 -- ZIP5 exists but no valid ZIP9 in LDS", {
  input <- make_result_row("P04", "2021-01-01", NA_character_, "99999", "interval")

  lds_no_zip9 <- tribble(
    ~ID,   ~ADDRESS_ZIP9, ~ADDRESS_PERIOD_START,
    "PA",  "99999",       "2020-01-01",           # bare ZIP5 -- no valid ZIP9
    "PB",  "99999",       "2021-01-01"
  )

  out <- run_approx(input, lds_no_zip9)

  expect_equal(out$zip9_source, "zip5_no_zip9")
  expect_true(is.na(out$ZIP9))
  expect_equal(out$match_type, "interval")
  expect_true(is.na(out$zip5_modal_freq))
})

# ---- Test 3: none unchanged --------------------------------------------------

test_that("Test 3: none -- match_type=none rows returned unchanged", {
  input <- make_result_row("P99", "2021-01-01", NA_character_, NA_character_, "none")
  out   <- run_approx(input, lds_base)

  expect_equal(out$zip9_source, "none")
  expect_true(is.na(out$ZIP9))
  expect_equal(out$match_type, "none")
  expect_true(is.na(out$zip5_modal_freq))
})

# ---- Test 4: zip9_observed ---------------------------------------------------

test_that("Test 4: zip9_observed -- already-filled ZIP9 rows returned unchanged", {
  input <- make_result_row("P01", "2021-01-01", "123450001", "12345", "interval")
  out   <- run_approx(input, lds_base)

  expect_equal(out$zip9_source, "zip9_observed")
  expect_equal(out$ZIP9, "123450001")
  expect_equal(out$match_type, "interval")
  expect_true(is.na(out$zip5_modal_freq))
  expect_true(is.na(out$zip5_n_candidates))
  expect_true(is.na(out$zip5_modal_share))
})

# ---- Test 5: probe-first gate ------------------------------------------------

test_that("Test 5: probe-first gate -- absent LDS file returns input unchanged (no error)", {
  td <- withr::local_tempdir()  # no CSV written
  old_dir <- CONFIG$data_dir
  CONFIG$data_dir <<- td
  on.exit(CONFIG$data_dir <<- old_dir, add = TRUE)
  .zip5_lookup_cache$key   <<- NULL
  .zip5_lookup_cache$value <<- NULL

  input <- make_result_row("P01", "2021-01-01", NA_character_, "12345", "interval")

  # Should not error or stop; should emit a message
  expect_message(
    out <- approximate_zip9(input),
    regexp = "LDS_ADDRESS_HISTORY not found"
  )
  expect_equal(nrow(out), nrow(input))
  expect_equal(names(out), names(input))  # no extra columns
})

# ---- Test 6: tie-break by recency --------------------------------------------

test_that("Test 6: tie-break by recency -- equal freq, more recent wins", {
  # ZIP5 55555: two ZIP9s each seen by 1 distinct patient; more recent wins
  lds_tiebreak <- tribble(
    ~ID,  ~ADDRESS_ZIP9, ~ADDRESS_PERIOD_START,
    "PA", "555550001",   "2019-01-01",
    "PB", "555550002",   "2022-06-01"   # <- more recent, should win
  )

  input <- make_result_row("PX", "2021-01-01", NA_character_, "55555", "interval")
  out   <- run_approx(input, lds_tiebreak)

  expect_equal(out$zip9_source, "zip5_modal")
  expect_equal(out$ZIP9, "555550002")
})

# ---- Test 7: schema -----------------------------------------------------------

test_that("Test 7: schema -- output has exactly input columns + 4 new, no modal_zip9", {
  input <- bind_rows(
    make_result_row("P01", "2021-01-01", NA_character_, "12345", "interval"),
    make_result_row("P02", "2021-01-01", "123450001",   "12345", "interval")
  )
  out <- run_approx(input, lds_base)

  expected_cols <- c(names(input), "zip9_source", "zip5_modal_freq",
                     "zip5_n_candidates", "zip5_modal_share")
  expect_setequal(names(out), expected_cols)
  expect_false("modal_zip9" %in% names(out))
  expect_equal(nrow(out), nrow(input))
})

# ---- Test 8: determinism -----------------------------------------------------

test_that("Test 8: determinism -- two consecutive calls return identical results", {
  td <- withr::local_tempdir()
  write_lds_csv(td, lds_base)
  old_dir <- CONFIG$data_dir
  CONFIG$data_dir <<- td
  on.exit(CONFIG$data_dir <<- old_dir, add = TRUE)
  .zip5_lookup_cache$key   <<- NULL
  .zip5_lookup_cache$value <<- NULL

  input <- make_result_row("P01", "2021-01-01", NA_character_, "12345", "interval")

  r1 <- approximate_zip9(input)
  r2 <- approximate_zip9(input)
  expect_true(identical(r1, r2))
})

# ---- Test 9: match_type invariance -------------------------------------------

test_that("Test 9: match_type invariance -- no row's match_type is changed", {
  input <- bind_rows(
    make_result_row("P01", "2021-01-01", NA_character_, "12345", "interval"),
    make_result_row("P02", "2021-01-01", NA_character_, "12345", "most_recent_before"),
    make_result_row("P99", "2021-01-01", NA_character_, NA_character_, "none"),
    make_result_row("P03", "2021-01-01", "123450001",   "12345", "interval")
  )
  out <- run_approx(input, lds_base)

  # approximate_zip9() sorts output by (ID, query_date); align input the same way
  input_sorted <- input %>% arrange(ID, query_date)
  out_sorted   <- out   %>% arrange(ID, query_date)
  expect_equal(out_sorted$match_type, input_sorted$match_type)
})

# ---- Test 10: no_zip5 --------------------------------------------------------

test_that("Test 10: no_zip5 -- ZIP9=NA, ZIP5=NA, match_type != none -> no_zip5", {
  input <- make_result_row("PX", "2021-01-01", NA_character_, NA_character_, "most_recent_before")
  out   <- run_approx(input, lds_base)

  expect_equal(out$zip9_source, "no_zip5")
  expect_true(is.na(out$ZIP9))
  expect_equal(out$match_type, "most_recent_before")
})

# ---- Test 11: modal counts patients not rows ---------------------------------

test_that("Test 11: modal counts patients (not rows) -- 3-patient ZIP9-B beats 1-patient ZIP9-A", {
  # One patient has 10 rows at ZIP9-A; 3 distinct patients have 1 row each at ZIP9-B
  lds_patient_count <- tribble(
    ~ID,   ~ADDRESS_ZIP9, ~ADDRESS_PERIOD_START,
    "PA",  "111110001",   "2019-01-01",
    "PA",  "111110001",   "2019-02-01",
    "PA",  "111110001",   "2019-03-01",
    "PA",  "111110001",   "2019-04-01",
    "PA",  "111110001",   "2019-05-01",
    "PA",  "111110001",   "2019-06-01",
    "PA",  "111110001",   "2019-07-01",
    "PA",  "111110001",   "2019-08-01",
    "PA",  "111110001",   "2019-09-01",
    "PA",  "111110001",   "2019-10-01",
    "PB",  "111110002",   "2021-01-01",
    "PC",  "111110002",   "2021-02-01",
    "PD",  "111110002",   "2021-03-01"
  )

  input <- make_result_row("PX", "2021-01-01", NA_character_, "11111", "interval")
  out   <- run_approx(input, lds_patient_count)

  # ZIP9-B (111110002) has 3 distinct patients vs ZIP9-A (111110001) has 1
  expect_equal(out$zip9_source, "zip5_modal")
  expect_equal(out$ZIP9, "111110002")
})
