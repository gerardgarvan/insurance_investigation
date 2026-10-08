# tests/testthat/test-166-rates.R
# Phase 166 Plan 02 — TDD fixtures for utils_surveillance_rates.R
# Tests: (a) rate formula, (b) zero-event retention, (c) py=0 → NA,
#        (d) boundary rule, (e) reconciliation invariants, (f) anchor/follow_end exclusion

# Load the functions under test
source(here::here("R/utils/utils_surveillance_rates.R"))

library(dplyr)
library(tibble)

# ---------------------------------------------------------------------------
# (a) Rate formula: 6 dates / 2.0 py → rate = 3.0
# ---------------------------------------------------------------------------
test_that("(a) rate formula: n/py computed correctly", {
  pm <- tibble(
    ID                   = "P001",
    modality             = "Echo",
    n_dates_post_primary = 6L,
    person_years         = 2.0
  )
  result <- compute_modality_rates(pm, n_dates_col = "n_dates_post_primary")
  expect_equal(nrow(result), 1L)
  expect_equal(result$rate_per_py, 3.0, tolerance = 1e-9)
})

# ---------------------------------------------------------------------------
# (b) Zero-event patient retained; rate = 0
# ---------------------------------------------------------------------------
test_that("(b) zero-event patient kept in denominator with rate 0", {
  pm <- tibble(
    ID                   = c("P001", "P002"),
    modality             = "Echo",
    n_dates_post_primary = c(0L, 5L),
    person_years         = c(1.5, 2.0)
  )
  result <- compute_modality_rates(pm, n_dates_col = "n_dates_post_primary")
  expect_equal(nrow(result), 2L)
  p001 <- result |> filter(ID == "P001")
  expect_equal(p001$rate_per_py, 0.0, tolerance = 1e-9)
})

# ---------------------------------------------------------------------------
# (c) py = 0 → rate NA
# ---------------------------------------------------------------------------
test_that("(c) person_years = 0 produces NA rate", {
  pm <- tibble(
    ID                   = "P001",
    modality             = "Echo",
    n_dates_post_primary = 3L,
    person_years         = 0.0
  )
  result <- compute_modality_rates(pm, n_dates_col = "n_dates_post_primary")
  expect_true(is.na(result$rate_per_py))
})

# Also test NA person_years → NA rate
test_that("(c) NA person_years produces NA rate", {
  pm <- tibble(
    ID                   = "P001",
    modality             = "Echo",
    n_dates_post_primary = 3L,
    person_years         = NA_real_
  )
  result <- compute_modality_rates(pm, n_dates_col = "n_dates_post_primary")
  expect_true(is.na(result$rate_per_py))
})

# ---------------------------------------------------------------------------
# (d) Boundary rule: event at day 365 → Y1; event at day 366 → Y2
# ---------------------------------------------------------------------------
test_that("(d) half-open boundary: day 365 in Y1, day 366 in Y2", {
  anchor <- as.Date("2020-01-01")
  followup <- tibble(
    ID             = "P001",
    hl_anchor_date = anchor,
    follow_end     = anchor + 2000,
    person_years   = 2000 / 365.25
  )
  events_at_365 <- tibble(ID = "P001", modality = "Echo",
                          event_date = anchor + 365)
  events_at_366 <- tibble(ID = "P001", modality = "Echo",
                          event_date = anchor + 366)

  result_365 <- split_followup_intervals(followup, events_at_365)
  result_366 <- split_followup_intervals(followup, events_at_366)

  # day 365 should be in Y1
  row_365 <- result_365 |> filter(modality == "Echo", dates_in_interval > 0)
  expect_equal(as.character(row_365$interval[1]), "Y1")

  # day 366 should be in Y2
  row_366 <- result_366 |> filter(modality == "Echo", dates_in_interval > 0)
  expect_equal(as.character(row_366$interval[1]), "Y2")
})

# ---------------------------------------------------------------------------
# (e) Reconciliation: followed 1000 days, events at days 100/400/800
#     interval py sum = 1000/365.25 (tol 1e-9)
#     dates sum = 3
#     Y3-5 py = (1000-730)/365.25
# ---------------------------------------------------------------------------
test_that("(e) reconciliation: interval py and dates sum correctly", {
  anchor <- as.Date("2020-01-01")
  followup <- tibble(
    ID             = "P001",
    hl_anchor_date = anchor,
    follow_end     = anchor + 1000,
    person_years   = 1000 / 365.25
  )
  events <- tibble(
    ID         = "P001",
    modality   = "Echo",
    event_date = anchor + c(100L, 400L, 800L)
  )

  result <- split_followup_intervals(followup, events)
  p001 <- result |> filter(ID == "P001", modality == "Echo")

  # Total py sum
  total_py <- sum(p001$person_years_in_interval, na.rm = TRUE)
  expect_equal(total_py, 1000 / 365.25, tolerance = 1e-9)

  # Total dates sum
  total_dates <- sum(p001$dates_in_interval, na.rm = TRUE)
  expect_equal(total_dates, 3L)

  # Y3-5 py = (1000 - 730) / 365.25 = 270 / 365.25
  y35 <- p001 |> filter(interval == "Y3-5")
  expect_equal(y35$person_years_in_interval, 270 / 365.25, tolerance = 1e-9)
})

# ---------------------------------------------------------------------------
# (f) build_dated_post_events() excludes anchor-day events and post-follow_end events
# ---------------------------------------------------------------------------
test_that("(f) build_dated_post_events excludes anchor-day and post-follow_end events", {
  anchor <- as.Date("2020-06-01")
  follow_end <- as.Date("2022-06-01")

  # Simulate events_win as a tibble (option-a: already filtered by classify_event_window)
  # We test the function's own filter contract using a fixture events_win
  events_win <- tibble(
    ID         = rep("P001", 4),
    modality   = "Echo",
    event_date = c(
      anchor,          # anchor day — should be excluded (pre, not post)
      anchor + 1L,     # valid post-anchor
      anchor + 100L,   # valid post-anchor
      follow_end + 1L  # after follow_end — should be excluded
    ),
    tier       = "primary",
    type_ok    = TRUE,
    window     = c("pre", "post", "post", "after_followup"),
    hl_anchor_date = anchor,
    follow_end = follow_end
  )

  followup <- tibble(
    ID             = "P001",
    hl_anchor_date = anchor,
    follow_end     = follow_end
  )

  result <- build_dated_post_events(events_win, followup)

  # Should keep only the 2 post-anchor, on-or-before-follow_end, primary events
  expect_equal(nrow(result), 2L)
  expect_true(all(result$event_date > anchor))
  expect_true(all(result$event_date <= follow_end))
})
