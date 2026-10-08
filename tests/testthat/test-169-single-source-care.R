# tests/testthat/test-169-single-source-care.R
# Phase 167 Plan 01 — TDD fixtures for build_single_source_result()
# Requirements: SRC-01, SRC-02, SRC-03
# Tests: (1) SRC-01 single vs multi source, (2) all-blank patients,
#        (3) no-encounter patients, (4) SRC-02 post-anchor sub-cases,
#        (5) SRC-03 any_blank_source with n_sources=1, (6) primary_source

# Load the pure helper under test; skip if file not yet present
helper_path <- here::here("R/169_single_source_care.R")
if (!file.exists(helper_path)) {
  testthat::skip("R/169_single_source_care.R not yet written")
}
source(helper_path, local = new.env(parent = globalenv()))

library(dplyr)
library(tibble)

# ---------------------------------------------------------------------------
# Shared synthetic fixtures
# ---------------------------------------------------------------------------
# whole_raw columns: ID, n_encounters, n_sources, any_blank_source (integer 0/1)
# post_raw  columns: ID, n_encounters_post, n_sources_post
# anchors   columns: ID, hl_anchor_date
# source_counts columns: ID, SOURCE (already normalised UPPER/TRIM), n_enc_at_source

make_fixtures <- function() {
  whole_raw <- tibble::tibble(
    ID              = c("A", "B", "E", "F"),
    n_encounters    = c(5L, 10L, 4L, 3L),
    n_sources       = c(1L,  3L, 1L, 0L),   # F: all-blank => n_sources 0
    any_blank_source = c(0L, 0L, 1L, 1L)
  )

  post_raw <- tibble::tibble(
    ID                = c("A", "H"),
    n_encounters_post = c(3L, 2L),
    n_sources_post    = c(1L, 0L)    # H: all-blank post => n_sources_post 0
  )

  anchors <- tibble::tibble(
    ID             = c("A", "B", "C", "D", "E", "F", "G", "H"),
    hl_anchor_date = as.Date(c(
      "2010-01-01",   # A: anchor + post exists
      "2009-06-01",   # B: anchor, no post rows (absent from post_raw)
      NA,             # C: no anchor
      "2012-03-15",   # D: anchor, absent from post_raw
      "2011-05-01",   # E: anchor; has blank SOURCE but n_sources = 1
      "2008-01-01",   # F: all-blank patient
      "2013-07-01",   # G: no whole-record rows (absent from whole_raw)
      "2014-02-01"    # H: anchor + post all-blank
    ))
  )

  source_counts <- tibble::tibble(
    ID              = c("A", "B", "B", "B", "E"),
    SOURCE          = c("HOSP1", "HOSP1", "HOSP2", "HOSP3", "HOSP1"),
    n_enc_at_source = c(5L, 2L, 2L, 1L, 4L)
  )

  list(whole_raw = whole_raw, post_raw = post_raw,
       anchors = anchors, source_counts = source_counts)
}

# ---------------------------------------------------------------------------
# (1) SRC-01: single vs multi-source classification
# ---------------------------------------------------------------------------
test_that("(1) SRC-01: single_source_care is 1L for n_sources=1, 0L for n_sources>=2", {
  f <- make_fixtures()
  result <- build_single_source_result(f$whole_raw, f$post_raw, f$anchors, f$source_counts)

  row_A <- result |> dplyr::filter(ID == "A")
  row_B <- result |> dplyr::filter(ID == "B")

  expect_equal(row_A$single_source_care, 1L)
  expect_equal(row_B$single_source_care, 0L)
  # Encounter counts pass through
  expect_equal(row_A$n_encounters, 5L)
  expect_equal(row_B$n_sources,    3L)
})

# ---------------------------------------------------------------------------
# (2) SRC-01 all-blank: patients with n_sources=0 get single_source_care = NA
# ---------------------------------------------------------------------------
test_that("(2) SRC-01 all-blank: single_source_care=NA_integer_, any_blank_source=TRUE, n_encounters carried", {
  f <- make_fixtures()
  result <- build_single_source_result(f$whole_raw, f$post_raw, f$anchors, f$source_counts)

  row_F <- result |> dplyr::filter(ID == "F")

  expect_true(is.na(row_F$single_source_care))
  expect_identical(row_F$single_source_care, NA_integer_)
  expect_true(row_F$any_blank_source)
  expect_equal(row_F$n_encounters, 3L)
})

# ---------------------------------------------------------------------------
# (3) No encounters: patient in anchors but absent from whole_raw
# ---------------------------------------------------------------------------
test_that("(3) No-encounter patient: n_encounters=NA, single_source_care=NA, any_blank_source=FALSE", {
  f <- make_fixtures()
  result <- build_single_source_result(f$whole_raw, f$post_raw, f$anchors, f$source_counts)

  row_G <- result |> dplyr::filter(ID == "G")

  expect_true(is.na(row_G$n_encounters))
  expect_true(is.na(row_G$single_source_care))
  expect_false(row_G$any_blank_source)
})

# ---------------------------------------------------------------------------
# (4) SRC-02 post-anchor: four sub-cases
# ---------------------------------------------------------------------------
test_that("(4) SRC-02 post-anchor: A=1L, C=NA (no anchor), D=NA (absent from post_raw), H=NA (all-blank post)", {
  f <- make_fixtures()
  result <- build_single_source_result(f$whole_raw, f$post_raw, f$anchors, f$source_counts)

  row_A <- result |> dplyr::filter(ID == "A")
  row_C <- result |> dplyr::filter(ID == "C")
  row_D <- result |> dplyr::filter(ID == "D")
  row_H <- result |> dplyr::filter(ID == "H")

  # A: anchor exists, post has 3 enc / 1 source -> 1L
  expect_equal(row_A$single_source_care_post, 1L)

  # C: no anchor -> NA
  expect_true(is.na(row_C$single_source_care_post))

  # D: anchor, absent from post_raw -> flag NA, counts coalesced to 0
  expect_true(is.na(row_D$single_source_care_post))
  expect_equal(row_D$n_encounters_post, 0L)
  expect_equal(row_D$n_sources_post,    0L)

  # H: anchor + post all-blank (n_sources_post=0) -> flag NA, n_encounters_post=2L
  expect_true(is.na(row_H$single_source_care_post))
  expect_equal(row_H$n_encounters_post, 2L)
})

# ---------------------------------------------------------------------------
# (5) SRC-03: any_blank_source stays TRUE even when n_sources=1
# ---------------------------------------------------------------------------
test_that("(5) SRC-03: single_source_care=1L with any_blank_source=TRUE when n_sources=1 and blanks present", {
  f <- make_fixtures()
  result <- build_single_source_result(f$whole_raw, f$post_raw, f$anchors, f$source_counts)

  row_E <- result |> dplyr::filter(ID == "E")

  expect_equal(row_E$single_source_care, 1L)
  expect_true(row_E$any_blank_source)
  expect_equal(row_E$n_sources, 1L)
})

# ---------------------------------------------------------------------------
# (6) primary_source: single site, tiebreak, all-blank -> NA
# ---------------------------------------------------------------------------
test_that("(6) primary_source: single site for A, alphabetical tiebreak for B (HOSP1), NA for F (all-blank)", {
  f <- make_fixtures()
  result <- build_single_source_result(f$whole_raw, f$post_raw, f$anchors, f$source_counts)

  row_A <- result |> dplyr::filter(ID == "A")
  row_B <- result |> dplyr::filter(ID == "B")
  row_F <- result |> dplyr::filter(ID == "F")

  # A: only HOSP1
  expect_equal(row_A$primary_source, "HOSP1")

  # B: HOSP1 (2 enc) tied with HOSP2 (2 enc), HOSP3 (1 enc) -> alphabetical -> "HOSP1"
  expect_equal(row_B$primary_source, "HOSP1")

  # F: all-blank, no source_counts rows -> NA
  expect_true(is.na(row_F$primary_source))
})
