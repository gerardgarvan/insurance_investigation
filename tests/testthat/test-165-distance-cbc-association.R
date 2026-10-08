# tests/testthat/test-165-distance-cbc-association.R
# ==============================================================================
# Real unit tests for R/utils/utils_distance_cbc.R helpers (Phase 165).
# Run on HiPerGator via: testthat::test_file("tests/testthat/test-165-distance-cbc-association.R")
# ==============================================================================

skip_if_not(file.exists(here::here("R/utils/utils_distance_cbc.R")))

suppressPackageStartupMessages(library(dplyr))

source(here::here("R/utils/utils_distance_cbc.R"))

# ==============================================================================
# Test 1: naive_or_se() integer-overflow regression
# ==============================================================================
test_that("naive_or_se() handles large integer-storage counts without overflow", {
  # Realistic scale from Phase 165 prototype (hundreds of thousands per cell).
  # Integer storage was the specific overflow mode that broke candidate C1.
  ct <- matrix(c(120000L, 85000L, 95000L, 65000L), nrow = 2)
  # Orientation: rows = far (0=not far, 1=far); cols = CBC (0=no, 1=yes)
  # ct[1,1]=120000 (far=0, cbc=0), ct[2,1]=85000 (far=1, cbc=0)
  # ct[1,2]=95000  (far=0, cbc=1), ct[2,2]=65000 (far=1, cbc=1)
  res <- naive_or_se(ct)

  expect_true(is.finite(res$log_or))
  expect_true(is.finite(res$se))
  expect_true(res$se > 0)
  expect_false(res$haldane)  # no zero cell

  # OR = (ct[2,2] * ct[1,1]) / (ct[2,1] * ct[1,2]) computed in double
  expected_or <- (65000 * 120000) / (85000 * 95000)
  expect_equal(exp(res$log_or), expected_or, tolerance = 1e-9)
})

# ==============================================================================
# Test 2: suppress_display() boundary values
# ==============================================================================
test_that("suppress_display() suppresses 1-10 and passes 0 and 11+", {
  expect_equal(suppress_display(1L),  "<11")
  expect_equal(suppress_display(5L),  "<11")
  expect_equal(suppress_display(10L), "<11")
  expect_equal(suppress_display(0L),  "0")
  expect_equal(suppress_display(11L), "11")
})

# ==============================================================================
# Test 3: build_enc_analysis() — one row per ENCOUNTERID; inpatient CBC match
# ==============================================================================
test_that("build_enc_analysis() returns one row per ENCOUNTERID with cbc_in_encounter", {
  # Two-day inpatient stay (ADMIT_DATE = day 1, DISCHARGE_DATE = day 2).
  # CBC events on both days — should collapse to one row with cbc_in_encounter = 1.
  anchor_date <- as.Date("2022-01-01")
  admit       <- as.Date("2022-06-01")
  discharge   <- as.Date("2022-06-02")

  enc_distance <- tibble::tibble(
    ID             = "P001",
    ENCOUNTERID    = "E001",
    ADMIT_DATE     = admit,
    ENC_TYPE       = "IP",
    distance_mi    = 150,
    distance_status = "computed"
  )

  cbc_events <- tibble::tibble(
    ID       = c("P001", "P001"),
    cbc_date = c(admit, discharge)
  )

  anchors <- tibble::tibble(
    ID             = "P001",
    hl_anchor_date = anchor_date
  )

  enc_dates <- tibble::tibble(
    ENCOUNTERID    = "E001",
    DISCHARGE_DATE = discharge,
    SOURCE         = "UFH"
  )

  result <- build_enc_analysis(
    enc_distance = enc_distance,
    cbc_events   = cbc_events,
    anchors      = anchors,
    enc_dates    = enc_dates,
    cutoff       = 100
  )

  # Must return exactly one row for E001
  expect_equal(nrow(result), 1L)
  expect_equal(result$ENCOUNTERID, "E001")
  expect_equal(result$cbc_in_encounter, 1L)
})

# ==============================================================================
# Test 4: build_pat_analysis() post-anchor window exclusion
# ==============================================================================
test_that("build_pat_analysis() excludes anchor-day events from post-window; includes next-day CBC", {
  anchor_date <- as.Date("2022-06-01")

  # Shared enc_distance with two encounters:
  #   E001: on anchor day (post_anchor = 0)
  #   E002: day after anchor (post_anchor = 1)
  enc_distance <- tibble::tibble(
    ID             = c("P001", "P001"),
    ENCOUNTERID    = c("E001", "E002"),
    ADMIT_DATE     = c(anchor_date, anchor_date + 1L),
    ENC_TYPE       = c("AV", "AV"),
    distance_mi    = c(150, 150),
    distance_status = c("computed", "computed")
  )

  anchors <- tibble::tibble(
    ID             = "P001",
    hl_anchor_date = anchor_date
  )

  enc_dates <- tibble::tibble(
    ENCOUNTERID    = c("E001", "E002"),
    DISCHARGE_DATE = c(NA_Date_, NA_Date_),
    SOURCE         = c("UFH", "UFH")
  )

  # Build encounter-level set once (used for both assertions below)
  enc_analysis <- build_enc_analysis(
    enc_distance = enc_distance,
    cbc_events   = tibble::tibble(ID = character(0), cbc_date = as.Date(character(0))),
    anchors      = anchors,
    enc_dates    = enc_dates,
    cutoff       = 100
  )

  # --- Fixture A: CBC only on the anchor day ---
  # The anchor-day encounter has post_anchor = 0 → excluded from post window.
  # Patient has no post-window encounter → absent from build_pat_analysis output.
  cbc_anchor_only <- tibble::tibble(
    ID       = "P001",
    cbc_date = anchor_date   # anchor day: not post-anchor
  )

  res_anchor <- build_pat_analysis(
    enc_analysis = enc_analysis,
    cbc_events   = cbc_anchor_only,
    anchors      = anchors,
    window       = "post"
  )

  # Denominator: patients with >= 1 post-anchor encounter (post_anchor == 1).
  # E002 (ADMIT_DATE = anchor_date + 1) has post_anchor = 1 → P001 IS in the denominator.
  # any_cbc (post window): cbc_date > hl_anchor_date → anchor_date is NOT > anchor_date → 0.
  expect_true("P001" %in% res_anchor$ID)
  expect_equal(res_anchor$any_cbc[res_anchor$ID == "P001"], 0L)

  # --- Fixture B: CBC on day AFTER anchor ---
  # This proves the test can fail (any_cbc must be 1 in post window).
  cbc_post_anchor <- tibble::tibble(
    ID       = "P001",
    cbc_date = anchor_date + 1L   # day after anchor: post-anchor = TRUE
  )

  res_post <- build_pat_analysis(
    enc_analysis = enc_analysis,
    cbc_events   = cbc_post_anchor,
    anchors      = anchors,
    window       = "post"
  )

  expect_true("P001" %in% res_post$ID)
  expect_equal(res_post$any_cbc[res_post$ID == "P001"], 1L)
})
