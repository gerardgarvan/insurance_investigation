# ==============================================================================
# tests/testthat/test-utils-distance-cbc.R
# Unit tests for assign_analytic_source() and build_flm_sensitivity_set()
# (Phase 192.3)
# ==============================================================================

library(testthat)
library(dplyr)
library(lubridate)


# Minimal config for tests
test_config <- list(claims_source_codes = c("FLM"))

# Helper: build a minimal addr_full tibble
make_addr <- function(id, source, start, end) {
  data.frame(
    ID                   = id,
    ADDRESS_PERIOD_START = start,
    ADDRESS_PERIOD_END   = end,
    SOURCE               = source,
    stringsAsFactors     = FALSE
  )
}

# Helper: build a minimal enc tibble
make_enc <- function(id, encounterid, admit_date, source) {
  data.frame(
    ID          = id,
    ENCOUNTERID = encounterid,
    ADMIT_DATE  = as.Date(admit_date),
    SOURCE      = source,
    stringsAsFactors = FALSE
  )
}

# Helper: build a minimal enc_all tibble
make_enc_all <- function(ids, sources, admit_dates) {
  data.frame(
    ID         = ids,
    SOURCE     = sources,
    ADMIT_DATE = as.Date(admit_dates),
    stringsAsFactors = FALSE
  )
}

# ------------------------------------------------------------------------------
# Test 1: Non-claims encounter → not_reassigned
# ------------------------------------------------------------------------------
test_that("Non-claims encounter keeps SOURCE_raw; method = not_reassigned", {
  enc <- make_enc("P1", "E1", "2020-06-01", "UFH")
  enc_all <- make_enc_all(c("P1"), c("UFH"), c("2020-06-01"))
  addr <- make_addr("P1", "UFH", "2020-01-01", "2021-01-01")

  result <- assign_analytic_source(enc, enc_all, addr, test_config)

  expect_equal(result$SOURCE_raw, "UFH")
  expect_equal(result$SOURCE_analytic, "UFH")
  expect_equal(result$source_reassigned, 0L)
  expect_equal(result$source_reassign_method, "not_reassigned")
})

# ------------------------------------------------------------------------------
# Test 2: Claims encounter, valid non-claims address (interval match) → address
# ------------------------------------------------------------------------------
test_that("Claims encounter with interval-match non-claims address → method = address", {
  enc <- make_enc("P1", "E1", "2020-06-01", "FLM")
  enc_all <- make_enc_all(c("P1"), c("FLM"), c("2020-06-01"))
  addr <- make_addr("P1", "UFH", "2020-01-01", "2021-01-01")

  result <- assign_analytic_source(enc, enc_all, addr, test_config)

  expect_equal(result$SOURCE_analytic, "UFH")
  expect_equal(result$source_reassign_method, "address")
  expect_equal(result$source_reassigned, 1L)
})

# ------------------------------------------------------------------------------
# Test 3: Claims encounter, valid non-claims address (recency fallback only) → address
# ------------------------------------------------------------------------------
test_that("Claims encounter with recency-fallback address → method = address", {
  enc <- make_enc("P1", "E1", "2020-06-01", "FLM")
  enc_all <- make_enc_all(c("P1"), c("FLM"), c("2020-06-01"))
  # Address starts 2019-01-01 with open end — will NOT match interval (no end bound),
  # but period_end = "9999-12-31" means it DOES match interval actually.
  # For recency-only test: address period ended before ADMIT_DATE
  addr <- make_addr("P1", "UFH", "2019-01-01", "2019-12-31")

  result <- assign_analytic_source(enc, enc_all, addr, test_config)

  # period_end (2019-12-31) < ADMIT_DATE (2020-06-01): no interval match
  # recency fallback: period_start (2019-01-01) <= ADMIT_DATE (2020-06-01): match
  expect_equal(result$source_reassign_method, "address")
  expect_equal(result$SOURCE_analytic, "UFH")
  expect_equal(result$source_reassigned, 1L)
})

# ------------------------------------------------------------------------------
# Test 4: Claims encounter, no valid address, qualifying non-claims in enc_all → modal
# ------------------------------------------------------------------------------
test_that("Claims encounter with no valid address but non-claims in enc_all → method = modal_encounter", {
  enc <- make_enc("P1", "E1", "2020-06-01", "FLM")
  # enc_all has non-claims encounters for P1
  enc_all <- make_enc_all(
    c("P1", "P1", "P1"),
    c("FLM", "UFH", "UFH"),
    c("2020-01-01", "2020-02-01", "2020-03-01")
  )
  # Addr: also FLM-sourced → unusable (claims source)
  addr <- make_addr("P1", "FLM", "2020-01-01", "2021-01-01")

  result <- assign_analytic_source(enc, enc_all, addr, test_config)

  expect_equal(result$source_reassign_method, "modal_encounter")
  expect_equal(result$SOURCE_analytic, "UFH")
  expect_equal(result$source_reassigned, 1L)
})

# ------------------------------------------------------------------------------
# Test 5: Claims encounter, no valid address, no non-claims in enc_all → unresolved
# ------------------------------------------------------------------------------
test_that("Claims encounter with no valid address and no non-claims in enc_all → Claims_unresolved", {
  enc <- make_enc("P1", "E1", "2020-06-01", "FLM")
  enc_all <- make_enc_all(c("P1"), c("FLM"), c("2020-06-01"))
  addr <- make_addr("P1", "FLM", "2020-01-01", "2021-01-01")

  result <- assign_analytic_source(enc, enc_all, addr, test_config)

  expect_equal(result$source_reassign_method, "unresolved")
  expect_equal(result$SOURCE_analytic, "Claims_unresolved")
  expect_equal(result$source_reassigned, 0L)
})

# ------------------------------------------------------------------------------
# Test 6: Tie in modal frequency — most recent ADMIT_DATE wins; alpha breaks further ties
# ------------------------------------------------------------------------------
test_that("Modal tiebreak: most recent ADMIT_DATE in enc_all wins, then alpha SOURCE", {
  enc <- make_enc("P1", "E1", "2020-06-01", "FLM")
  enc_all <- make_enc_all(
    c("P1", "P1", "P1", "P1"),
    c("FLM", "UFH", "UAB", "UFH"),   # UFH has n=2 (tied with UAB n=1 at most? No: UFH=2, UAB=1)
    c("2020-01-01", "2020-02-01", "2020-03-01", "2020-04-01")
  )
  # UFH appears twice (most frequent) — should win
  addr <- make_addr("P1", "FLM", "2020-01-01", "2021-01-01")

  result <- assign_analytic_source(enc, enc_all, addr, test_config)
  expect_equal(result$SOURCE_analytic, "UFH")
  expect_equal(result$source_reassign_method, "modal_encounter")

  # Test alphabetical tiebreak — two sources with equal frequency, equal max date
  enc_all_tied <- make_enc_all(
    c("P1", "P1", "P1", "P1"),
    c("FLM", "UFH", "UAB", "FLM"),   # UAB=1, UFH=1 after removing FLM
    c("2020-01-01", "2020-04-01", "2020-04-01", "2020-01-01")
  )
  result_tied <- assign_analytic_source(enc, enc_all_tied, addr, test_config)
  # UAB < UFH alphabetically
  expect_equal(result_tied$SOURCE_analytic, "UAB")
  expect_equal(result_tied$source_reassign_method, "modal_encounter")
})

# ------------------------------------------------------------------------------
# Test 7: REGRESSION GUARD — enc_all broader than enc
# Modal SOURCE drawn from enc_all MUST differ from modal that would be computed from enc alone.
# ------------------------------------------------------------------------------
test_that("enc_all broader than enc: modal drawn from enc_all, not from enc", {
  # enc contains only the FLM encounter being analysed (which has distance computed)
  enc <- make_enc("P1", "E1", "2020-06-01", "FLM")

  # enc_all contains all encounters including NON-claims ones NOT in enc
  # The non-claims encounters in enc_all (not in enc) are predominantly UAB
  enc_all <- make_enc_all(
    c("P1", "P1", "P1", "P1"),
    c("FLM", "UAB", "UAB", "UAB"),    # UAB is modal in enc_all (but absent from enc)
    c("2020-06-01", "2019-01-01", "2019-02-01", "2019-03-01")
  )

  # If we computed modal from enc alone: enc has only FLM (claims) → no non-claims → unresolved
  # enc_all has UAB x3 → modal = UAB
  addr <- make_addr("P1", "FLM", "2020-01-01", "2021-01-01")

  result <- assign_analytic_source(enc, enc_all, addr, test_config)

  # enc_all broader → modal = UAB; if only enc used → Claims_unresolved
  expect_equal(result$SOURCE_analytic, "UAB",
    info = "modal SOURCE should come from enc_all (broader), not from enc alone")
  expect_equal(result$source_reassign_method, "modal_encounter")
  expect_equal(result$source_reassigned, 1L)
})

# ------------------------------------------------------------------------------
# Test 8: REGRESSION GUARD — usable non-claims address rows present but dates
# parse to NA (simulates the ymd() silent-failure that the guard was written to catch).
# assign_analytic_source() must stop() with the guard message.
# ------------------------------------------------------------------------------
test_that("Guard fires when usable addr rows exist but dates are NA (parse failure simulation)", {
  enc     <- make_enc("P1", "E1", "2020-06-01", "FLM")
  enc_all <- make_enc_all(c("P1"), c("FLM"), c("2020-06-01"))
  # Non-claims SOURCE (UFH) — usable — but ADDRESS_PERIOD_START is NA,
  # simulating what happens when a date format fails to parse.
  addr_bad <- data.frame(
    ID                   = "P1",
    ADDRESS_PERIOD_START = NA_character_,
    ADDRESS_PERIOD_END   = NA_character_,
    SOURCE               = "UFH",
    stringsAsFactors     = FALSE
  )
  expect_error(
    assign_analytic_source(enc, enc_all, addr_bad, test_config),
    regexp = "0 claims encounters reassigned via address"
  )
})

# ==============================================================================
# Tests for build_flm_sensitivity_set()
# ==============================================================================

test_that("build_flm_sensitivity_set: FLM rows get SOURCE_analytic = SOURCE_raw", {
  enc_ws <- data.frame(
    SOURCE_raw      = c("FLM", "FLM", "UFH"),
    SOURCE_analytic = c("UFH", "UAB", "UFH"),
    source_reassign_method = c("address", "modal_encounter", "not_reassigned"),
    source_reassigned = c(1L, 1L, 0L),
    stringsAsFactors = FALSE
  )
  result <- build_flm_sensitivity_set(enc_ws, test_config)
  expect_equal(result$SOURCE_analytic[1], "FLM")
  expect_equal(result$SOURCE_analytic[2], "FLM")
  expect_equal(result$SOURCE_analytic[3], "UFH")
})

test_that("build_flm_sensitivity_set: non-claims rows unchanged", {
  enc_ws <- data.frame(
    SOURCE_raw      = c("UFH", "UAB"),
    SOURCE_analytic = c("UFH", "UAB"),
    source_reassign_method = c("not_reassigned", "not_reassigned"),
    source_reassigned = c(0L, 0L),
    stringsAsFactors = FALSE
  )
  result <- build_flm_sensitivity_set(enc_ws, test_config)
  expect_equal(result$SOURCE_analytic, c("UFH", "UAB"))
})
