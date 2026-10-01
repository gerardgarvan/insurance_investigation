# ==============================================================================
# tests/testthat/test-161-death-plausibility.R
# Phase 161: resolve_death_date() and compute_followup() unit tests
# ==============================================================================
#
# Fixtures are pure in-memory tibbles -- no DuckDB, no real CSVs.
# Covers:
#   - All 5 death_flag values (resolve_death_date)
#   - Grace boundary (exactly 30d = plausible; 31d = implausible)
#   - Source priority D3 (N > S > D > L > T)
#   - Duplicate same-date with two sources (picks highest-priority source)
#   - No DEATH row for a cohort ID -> no_death_record
#   - NA last_observed treated as consistent
#   - DEATH row for ID not in cohort -> absent from output
#   - post_death_activity_days correctness
#   - death_sensitivity_table() properties
#   - compute_followup() outcomes (D2, D6, cutoff cap, zero, posthumous_dx)
#   - compute_followup() legacy argument warning
#   - compute_followup() missing-argument error
# ==============================================================================

library(testthat)
library(tibble)
library(dplyr)

# Source utilities directly (no DuckDB needed)
source(here::here("R/utils/utils_death.R"))
source(here::here("R/utils/utils_surveillance.R"))

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

# Build a minimal death_tbl row
d <- function(id, date, src = NA_character_) {
  tibble::tibble(
    ID           = as.character(id),
    DEATH_DATE   = as.Date(date),
    DEATH_SOURCE = as.character(src)
  )
}

# Build a minimal activity_tbl row
a <- function(id, last_observed, last_enc_any = last_observed) {
  tibble::tibble(
    ID               = as.character(id),
    last_enc_any     = as.Date(last_enc_any),
    last_activity_any = as.Date(last_observed),
    last_observed    = as.Date(last_observed)
  )
}

# Pull the single row for an ID from a resolved result
one <- function(res, id) {
  res[res$ID == as.character(id), ]
}

# Standard cutoff used by compute_followup tests
CUTOFF <- as.Date("2025-12-31")

# ---------------------------------------------------------------------------
# Test group 1: resolve_death_date() -- basic flag values
# ---------------------------------------------------------------------------

test_that("fixture 1: single death, activity >30d after -> implausible_post_activity", {
  # death 2010-01-01; last activity 2015-06-01 -> 1977 days gap
  death_tbl    <- d("P1", "2010-01-01", "N")
  activity_tbl <- a("P1", "2015-06-01")

  res <- resolve_death_date(death_tbl, activity_tbl, grace_days = 30L)
  row <- one(res, "P1")

  expect_equal(row$death_flag, "implausible_post_activity")
  expect_true(is.na(row$death_date_resolved))
  expect_equal(row$post_death_activity_days, 1977L)
})

test_that("fixture 2: two death dates, both implausible -> conflicting_unresolved", {
  # Both 2010-01-01 and 2011-03-15 are far before last_observed 2015-06-01
  death_tbl <- bind_rows(
    d("P2", "2010-01-01", "N"),
    d("P2", "2011-03-15", "S")
  )
  activity_tbl <- a("P2", "2015-06-01")

  res <- resolve_death_date(death_tbl, activity_tbl, grace_days = 30L)
  row <- one(res, "P2")

  expect_equal(row$death_flag, "conflicting_unresolved")
  expect_true(is.na(row$death_date_resolved))
})

test_that("fixture 3: two death dates, one consistent -> conflicting_resolved, uses consistent date", {
  # death 2010-01-01 inconsistent (activity 2020-07-15, gap > 30d)
  # death 2020-08-10 consistent (last_observed 2020-07-15, death > last_observed - 30)
  death_tbl <- bind_rows(
    d("P3", "2010-01-01", "L"),
    d("P3", "2020-08-10", "N")
  )
  activity_tbl <- a("P3", "2020-07-15")

  res <- resolve_death_date(death_tbl, activity_tbl, grace_days = 30L)
  row <- one(res, "P3")

  expect_equal(row$death_flag, "conflicting_resolved")
  expect_equal(row$death_date_resolved, as.Date("2020-08-10"))
})

test_that("fixture 4: single death 19d before last activity -> plausible", {
  # death 2021-03-01; last_observed 2021-03-20 (gap = 19d < 30d)
  death_tbl    <- d("P4", "2021-03-01", "N")
  activity_tbl <- a("P4", "2021-03-20")

  res <- resolve_death_date(death_tbl, activity_tbl, grace_days = 30L)
  row <- one(res, "P4")

  expect_equal(row$death_flag, "plausible")
  expect_equal(row$death_date_resolved, as.Date("2021-03-01"))
  expect_equal(row$post_death_activity_days, 19L)
})

test_that("fixture 5: single death 75d before last activity -> implausible_post_activity", {
  death_tbl    <- d("P5", "2021-03-01", "N")
  activity_tbl <- a("P5", "2021-05-15")

  res <- resolve_death_date(death_tbl, activity_tbl, grace_days = 30L)
  row <- one(res, "P5")

  expect_equal(row$death_flag, "implausible_post_activity")
  expect_true(is.na(row$death_date_resolved))
})

# ---------------------------------------------------------------------------
# Test group 2: grace boundary (exactly 30d vs 31d)
# ---------------------------------------------------------------------------

test_that("fixture 6a: exactly 30d gap -> plausible (boundary inclusive)", {
  # death 2021-03-01; last_observed 2021-03-31 => gap = 30d
  death_tbl    <- d("P6a", "2021-03-01", "N")
  activity_tbl <- a("P6a", "2021-03-31")

  res <- resolve_death_date(death_tbl, activity_tbl, grace_days = 30L)
  row <- one(res, "P6a")

  expect_equal(row$death_flag, "plausible")
  expect_equal(row$death_date_resolved, as.Date("2021-03-01"))
})

test_that("fixture 6b: 31d gap -> implausible_post_activity (just over boundary)", {
  # death 2021-03-01; last_observed 2021-04-01 => gap = 31d
  death_tbl    <- d("P6b", "2021-03-01", "N")
  activity_tbl <- a("P6b", "2021-04-01")

  res <- resolve_death_date(death_tbl, activity_tbl, grace_days = 30L)
  row <- one(res, "P6b")

  expect_equal(row$death_flag, "implausible_post_activity")
  expect_true(is.na(row$death_date_resolved))
})

# ---------------------------------------------------------------------------
# Test group 3: source priority D3
# ---------------------------------------------------------------------------

test_that("fixture 7: conflicting dates, N outranks L -> use N date", {
  # death 2021-03-01 src L; death 2021-03-05 src N; last_observed 2021-02-20
  # both consistent (death > last_observed - 30 = 2021-01-21)
  death_tbl <- bind_rows(
    d("P7", "2021-03-01", "L"),
    d("P7", "2021-03-05", "N")
  )
  activity_tbl <- a("P7", "2021-02-20")

  res <- resolve_death_date(death_tbl, activity_tbl, grace_days = 30L)
  row <- one(res, "P7")

  # Two distinct dates, both consistent -> conflicting_resolved
  expect_equal(row$death_flag, "conflicting_resolved")
  # D3: highest-priority source (N rank=1) wins; among ties, earliest date.
  # N is on 2021-03-05 but has lower src_rank than L, so N wins.
  expect_equal(row$death_date_resolved, as.Date("2021-03-05"))
  expect_equal(row$death_source_resolved, "N")
})

test_that("fixture 8: same date from L and N sources -> plausible, source = N", {
  death_tbl <- bind_rows(
    d("P8", "2021-03-01", "L"),
    d("P8", "2021-03-01", "N")
  )
  activity_tbl <- a("P8", "2021-02-20")

  res <- resolve_death_date(death_tbl, activity_tbl, grace_days = 30L)
  row <- one(res, "P8")

  # n_distinct(DEATH_DATE) = 1 -> plausible (if consistent)
  expect_equal(row$death_flag, "plausible")
  expect_equal(row$death_date_resolved, as.Date("2021-03-01"))
  expect_equal(row$death_source_resolved, "N")
})

# ---------------------------------------------------------------------------
# Test group 4: no death record
# ---------------------------------------------------------------------------

test_that("fixture 9: no DEATH row for cohort ID -> no_death_record", {
  death_tbl    <- d("OTHER", "2021-03-01", "N")  # different ID
  activity_tbl <- a("P9", "2021-06-01")

  res <- resolve_death_date(death_tbl, activity_tbl, grace_days = 30L)
  row <- one(res, "P9")

  expect_equal(row$death_flag, "no_death_record")
  expect_true(is.na(row$death_date_resolved))
  expect_equal(row$post_death_activity_days, 0L)
})

# ---------------------------------------------------------------------------
# Test group 5: NA last_observed treated as consistent
# ---------------------------------------------------------------------------

test_that("fixture 10: last_observed NA -> death treated as plausible (no counter-evidence)", {
  death_tbl <- d("P10", "2021-03-01", "N")
  activity_tbl <- tibble::tibble(
    ID                = "P10",
    last_enc_any      = as.Date(NA),
    last_activity_any = as.Date(NA),
    last_observed     = as.Date(NA)
  )

  res <- resolve_death_date(death_tbl, activity_tbl, grace_days = 30L)
  row <- one(res, "P10")

  expect_equal(row$death_flag, "plausible")
  expect_equal(row$death_date_resolved, as.Date("2021-03-01"))
})

# ---------------------------------------------------------------------------
# Test group 6: DEATH row for ID not in cohort -> absent from output
# ---------------------------------------------------------------------------

test_that("fixture 11: DEATH row for non-cohort ID is excluded from output", {
  death_tbl <- bind_rows(
    d("COHORT_ID", "2021-03-01", "N"),
    d("UNKNOWN_ID", "2019-01-01", "L")
  )
  activity_tbl <- a("COHORT_ID", "2021-02-01")

  res <- resolve_death_date(death_tbl, activity_tbl, grace_days = 30L)

  expect_false("UNKNOWN_ID" %in% res$ID)
  expect_true("COHORT_ID" %in% res$ID)
})

# ---------------------------------------------------------------------------
# Test group 7: one row per cohort ID; post_death_activity_days for #1 = 1977
# ---------------------------------------------------------------------------

test_that("output has exactly one row per cohort ID", {
  death_tbl <- bind_rows(
    d("A", "2021-01-01", "N"),
    d("A", "2021-06-01", "S"),
    d("B", "2020-05-10", "L")
  )
  activity_tbl <- bind_rows(
    a("A", "2021-02-01"),
    a("B", "2019-01-01")
  )

  res <- resolve_death_date(death_tbl, activity_tbl, grace_days = 30L)
  expect_equal(nrow(res), 2L)
  expect_equal(sort(res$ID), c("A", "B"))
})

test_that("post_death_activity_days = 1977 for fixture 1 (death 2010-01-01, obs 2015-06-01)", {
  death_tbl    <- d("P1b", "2010-01-01", "N")
  activity_tbl <- a("P1b", "2015-06-01")

  res <- resolve_death_date(death_tbl, activity_tbl, grace_days = 30L)
  expect_equal(one(res, "P1b")$post_death_activity_days, 1977L)
})

test_that("post_death_activity_days = 0 for no_death_record patient", {
  death_tbl    <- d("NOMATCH", "2020-01-01", "N")
  activity_tbl <- a("P9b", "2021-06-01")

  res <- resolve_death_date(death_tbl, activity_tbl, grace_days = 30L)
  expect_equal(one(res, "P9b")$post_death_activity_days, 0L)
})

# ---------------------------------------------------------------------------
# Test group 8: death_sensitivity_table()
# ---------------------------------------------------------------------------

test_that("death_sensitivity_table() returns one row per grace value", {
  death_tbl <- bind_rows(
    d("S1", "2021-03-01", "N"),
    d("S2", "2021-03-01", "L"),
    d("S3", "2021-03-01", "N"),
    d("S3", "2021-09-01", "S"),
    d("S4", "2021-03-01", "N"),
    d("S4", "2021-09-01", "S")
  )
  activity_tbl <- bind_rows(
    a("S1", "2021-02-01"),   # plausible at grace=30
    a("S2", "2021-05-15"),   # implausible at grace=30 (75d gap)
    a("S3", "2021-02-01"),   # conflicting_resolved
    a("S4", "2021-05-15"),   # conflicting_unresolved (both inconsistent)
    a("S5", "2021-06-01")    # no_death_record (5 cohort IDs)
  )

  tbl <- death_sensitivity_table(death_tbl, activity_tbl,
                                  grace_values = c(0L, 30L, 60L, 90L, 365L))

  expect_equal(nrow(tbl), 5L)
  expect_true("grace_days" %in% names(tbl))
  expect_true("n_no_credible_death" %in% names(tbl))
})

test_that("n_no_credible_death is non-increasing as grace_days increases", {
  death_tbl <- bind_rows(
    d("G1", "2021-03-01", "N"),
    d("G2", "2021-03-01", "N"),
    d("G3", "2021-03-01", "N")
  )
  activity_tbl <- bind_rows(
    a("G1", "2021-04-15"),   # 45d gap: implausible at grace=30, plausible at grace=60
    a("G2", "2021-05-01"),   # 61d gap: implausible at grace=60, plausible at grace=90
    a("G3", "2021-07-01")    # 122d gap: implausible at grace=90, plausible at grace=365
  )

  tbl <- death_sensitivity_table(death_tbl, activity_tbl,
                                  grace_values = c(0L, 30L, 60L, 90L, 365L))

  credible <- tbl$n_no_credible_death
  # Should be weakly decreasing
  expect_true(all(diff(credible) <= 0))
})

# ---------------------------------------------------------------------------
# Test group 9: compute_followup() scenarios
# ---------------------------------------------------------------------------

test_that("fixture 12: no death, follow_end = last_enc_any, positive", {
  denom <- tibble::tibble(ID = "F12", hl_anchor_date = as.Date("2020-06-10"))
  act   <- a("F12", "2020-06-18")
  dr    <- tibble::tibble(ID = "F12",
                          death_date_resolved = as.Date(NA),
                          death_flag = "no_death_record")

  fu <- compute_followup(denom, act, dr, CUTOFF)
  row <- fu[fu$ID == "F12", ]

  expect_equal(row$follow_end, as.Date("2020-06-18"))
  expect_equal(row$fu_status, "positive")
})

test_that("fixture 13: last_observed == anchor -> zero follow-up, same_day_last_contact", {
  denom <- tibble::tibble(ID = "F13", hl_anchor_date = as.Date("2020-06-10"))
  act   <- a("F13", "2020-06-10")
  dr    <- tibble::tibble(ID = "F13",
                          death_date_resolved = as.Date(NA),
                          death_flag = "no_death_record")

  fu <- compute_followup(denom, act, dr, CUTOFF)
  row <- fu[fu$ID == "F13", ]

  expect_equal(row$fu_status, "zero")
  expect_equal(row$fu_reason, "same_day_last_contact")
})

test_that("fixture 14: implausible death (death_resolved=NA) -> censored at last_observed, positive", {
  denom <- tibble::tibble(ID = "F14", hl_anchor_date = as.Date("2016-01-01"))
  act   <- a("F14", "2023-04-01")
  dr    <- tibble::tibble(ID = "F14",
                          death_date_resolved = as.Date(NA),
                          death_flag = "implausible_post_activity")

  fu <- compute_followup(denom, act, dr, CUTOFF)
  row <- fu[fu$ID == "F14", ]

  expect_equal(row$follow_end, as.Date("2023-04-01"))
  expect_equal(row$fu_status, "positive")
  # death_flag propagated; patient not marked deceased
  expect_equal(row$death_flag, "implausible_post_activity")
})

test_that("fixture 15: posthumous_dx (death before anchor) -> follow_end = anchor, zero or positive, posthumous_dx reason", {
  # death 2021-03-01 (plausible); anchor 2021-03-15 (14d later = posthumous dx)
  # last_observed 2021-03-20
  denom <- tibble::tibble(ID = "F15", hl_anchor_date = as.Date("2021-03-15"))
  act   <- a("F15", "2021-03-20")
  dr    <- tibble::tibble(ID = "F15",
                          death_date_resolved = as.Date("2021-03-01"),
                          death_flag = "plausible")

  fu <- compute_followup(denom, act, dr, CUTOFF)
  row <- fu[fu$ID == "F15", ]

  expect_true(row$posthumous_dx)
  # D6: follow_end overridden to anchor
  expect_equal(row$follow_end, as.Date("2021-03-15"))
  # anchor == anchor => zero
  expect_equal(row$fu_status, "zero")
  expect_equal(row$fu_reason, "posthumous_dx")
})

test_that("fixture 16: last_observed after cutoff -> follow_end capped at cutoff", {
  denom <- tibble::tibble(ID = "F16", hl_anchor_date = as.Date("2024-01-01"))
  act   <- a("F16", "2026-03-01")
  dr    <- tibble::tibble(ID = "F16",
                          death_date_resolved = as.Date(NA),
                          death_flag = "no_death_record")

  fu <- compute_followup(denom, act, dr, CUTOFF)
  row <- fu[fu$ID == "F16", ]

  expect_equal(row$follow_end, as.Date("2025-12-31"))
  expect_equal(row$fu_status, "positive")
})

test_that("fixture 17: calling compute_followup without activity or death_resolved raises error", {
  # Call with only denominator; activity and death_resolved missing
  denom <- tibble::tibble(ID = "X", hl_anchor_date = as.Date("2020-01-01"))
  expect_error(
    compute_followup(denom),
    regexp = "161-04"
  )
})

test_that("fixture 18: legacy 'death =' argument triggers warning", {
  denom <- tibble::tibble(ID = "F18", hl_anchor_date = as.Date("2020-01-01"))
  act   <- a("F18", "2021-01-01")
  # Simulate legacy death tibble (has death_date column, not death_date_resolved)
  legacy_death <- tibble::tibble(ID = "F18", death_date = as.Date("2020-06-01"))

  expect_warning(
    compute_followup(denom, act, legacy_death, CUTOFF, death = legacy_death),
    regexp = "161-04"
  )
})

# ---------------------------------------------------------------------------
# Test group 10: no negative fu_status in any fixture
# ---------------------------------------------------------------------------

test_that("no fixture produces fu_status == 'negative'", {
  all_fu <- list()

  fixtures <- list(
    list(d = tibble::tibble(ID = "N1", hl_anchor_date = as.Date("2020-06-10")),
         a = a("N1", "2020-06-18"),
         dr = tibble::tibble(ID = "N1", death_date_resolved = as.Date(NA), death_flag = "no_death_record")),
    list(d = tibble::tibble(ID = "N2", hl_anchor_date = as.Date("2020-06-10")),
         a = a("N2", "2020-06-10"),
         dr = tibble::tibble(ID = "N2", death_date_resolved = as.Date(NA), death_flag = "no_death_record")),
    list(d = tibble::tibble(ID = "N3", hl_anchor_date = as.Date("2021-03-15")),
         a = a("N3", "2021-03-20"),
         dr = tibble::tibble(ID = "N3", death_date_resolved = as.Date("2021-03-01"), death_flag = "plausible")),
    list(d = tibble::tibble(ID = "N4", hl_anchor_date = as.Date("2024-01-01")),
         a = a("N4", "2026-03-01"),
         dr = tibble::tibble(ID = "N4", death_date_resolved = as.Date(NA), death_flag = "no_death_record"))
  )

  for (fx in fixtures) {
    fu <- compute_followup(fx$d, fx$a, fx$dr, CUTOFF)
    all_fu[[length(all_fu) + 1]] <- fu
  }

  combined <- dplyr::bind_rows(all_fu)
  n_neg <- sum(combined$fu_status == "negative", na.rm = TRUE)
  expect_equal(n_neg, 0L)
})

# ---------------------------------------------------------------------------
# Test group 11: DEATH_SOURCE priority -- NDI (N) beats SSA (S)
# ---------------------------------------------------------------------------

test_that("NDI source (N) outranks SSA source (S) when dates differ", {
  # N gives 2021-04-01; S gives 2021-03-01; both consistent
  # D3: N (rank 1) wins -> resolved to N's date 2021-04-01
  death_tbl <- bind_rows(
    d("PRI1", "2021-03-01", "S"),
    d("PRI1", "2021-04-01", "N")
  )
  activity_tbl <- a("PRI1", "2021-02-01")

  res <- resolve_death_date(death_tbl, activity_tbl, grace_days = 30L)
  row <- one(res, "PRI1")

  expect_equal(row$death_source_resolved, "N")
  expect_equal(row$death_date_resolved, as.Date("2021-04-01"))
})
