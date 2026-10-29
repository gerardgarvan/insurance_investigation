# tests/testthat/test_autoimmune_flags.R
# Phase 192.1 Plan 01 — TDD fixtures for is_autoimmune_code() and summarise_autoimmune_dx()
# Requirements: AUTOIMMUNE-FLAG-05
# Run on HiPerGator: testthat::test_file("tests/testthat/test_autoimmune_flags.R")

# Load config (provides AUTOIMMUNE_DX_CODES, AUTOIMMUNE_DX_TYPE_ACCEPT, SENTINEL_CUTOFF,
# and auto-sources utils including utils_doi.R which provides is_autoimmune_code() etc.)
config_path <- here::here("R/00_config.R")
if (!file.exists(config_path)) {
  testthat::skip("R/00_config.R not found")
}
source(config_path, local = new.env(parent = globalenv()))

library(dplyr)
library(tibble)

# ---------------------------------------------------------------------------
# Synthetic code/accept lists for isolated unit tests (do not depend on config)
# ---------------------------------------------------------------------------
test_codes <- list(
  icd10 = c(
    "M05"   = "Seropositive RA",
    "M06"   = "Other RA",
    "M313"  = "GPA",
    "M317"  = "MPA",
    "L100"  = "Pemphigus vulgaris",
    "M083"  = "Juvenile RA pauciarticular",
    "M0809" = "Juvenile RA unspec site",
    "M0800" = "Juvenile RA unspec",
    "L40"   = "Psoriasis"
  ),
  icd9 = c(
    "7140"  = "RA",
    "4464"  = "GPA",
    "4460"  = "Polyarteritis nodosa (broader)",
    "6944"  = "Pemphigus (broader)",
    "6961"  = "Other psoriasis",
    "71430" = "JRA unspec"
  )
)

test_accept <- list(
  icd10 = c("10"),
  icd9  = c("09")
)

sentinel <- as.Date("1910-01-01")

# ===========================================================================
# SECTION 1: is_autoimmune_code()
# ===========================================================================

testthat::test_that("is_autoimmune_code: ICD-10 family prefix match (M05.79/'10') -> TRUE", {
  result <- is_autoimmune_code("M05.79", "10", codes = test_codes, accept = test_accept)
  testthat::expect_true(result)
})

testthat::test_that("is_autoimmune_code: terminal ICD-10 match (L10.0/'10') -> TRUE", {
  result <- is_autoimmune_code("L10.0", "10", codes = test_codes, accept = test_accept)
  testthat::expect_true(result)
})

testthat::test_that("is_autoimmune_code: 5-char ICD-10 key M08.09 -> TRUE", {
  result <- is_autoimmune_code("M08.09", "10", codes = test_codes, accept = test_accept)
  testthat::expect_true(result)
})

testthat::test_that("is_autoimmune_code: 5-char ICD-10 key M08.00 -> TRUE", {
  result <- is_autoimmune_code("M08.00", "10", codes = test_codes, accept = test_accept)
  testthat::expect_true(result)
})

testthat::test_that("is_autoimmune_code: M31.30 matches M313 prefix -> TRUE", {
  result <- is_autoimmune_code("M31.30", "10", codes = test_codes, accept = test_accept)
  testthat::expect_true(result)
})

testthat::test_that("is_autoimmune_code: M31.31 matches M313 prefix -> TRUE", {
  result <- is_autoimmune_code("M31.31", "10", codes = test_codes, accept = test_accept)
  testthat::expect_true(result)
})

testthat::test_that("is_autoimmune_code: ICD-10 code with wrong system (M05.9/'09') -> FALSE", {
  result <- is_autoimmune_code("M05.9", "09", codes = test_codes, accept = test_accept)
  testthat::expect_false(result)
})

testthat::test_that("is_autoimmune_code: ICD-9 RA code with correct system (7140/'09') -> TRUE", {
  result <- is_autoimmune_code("714.0", "09", codes = test_codes, accept = test_accept)
  testthat::expect_true(result)
})

testthat::test_that("is_autoimmune_code: 5-char ICD-9 key (71430/'09') -> TRUE", {
  result <- is_autoimmune_code("714.30", "09", codes = test_codes, accept = test_accept)
  testthat::expect_true(result)
})

testthat::test_that("is_autoimmune_code: DX_TYPE NA -> FALSE", {
  result <- is_autoimmune_code("M05.9", NA_character_, codes = test_codes, accept = test_accept)
  testthat::expect_false(result)
})

testthat::test_that("is_autoimmune_code: DX_TYPE 'SM' (SNOMED) -> FALSE", {
  result <- is_autoimmune_code("M05.9", "SM", codes = test_codes, accept = test_accept)
  testthat::expect_false(result)
})

testthat::test_that("is_autoimmune_code: DX_TYPE 'OT' -> FALSE", {
  result <- is_autoimmune_code("M05.9", "OT", codes = test_codes, accept = test_accept)
  testthat::expect_false(result)
})

testthat::test_that("is_autoimmune_code: trimmed whitespace in DX_TYPE ' 10 ' -> not accepted (exact match required)", {
  # The accept list has exact "10"; " 10 " is not in it -> FALSE
  result <- is_autoimmune_code("M05.9", " 10 ", codes = test_codes, accept = test_accept)
  testthat::expect_false(result)
})

testthat::test_that("is_autoimmune_code: parapsoriasis 696.2/'09' (not in ICD-9 set) -> FALSE", {
  result <- is_autoimmune_code("696.2", "09", codes = test_codes, accept = test_accept)
  testthat::expect_false(result)
})

testthat::test_that("is_autoimmune_code: cancer code C81.90/'10' -> FALSE", {
  result <- is_autoimmune_code("C81.90", "10", codes = test_codes, accept = test_accept)
  testthat::expect_false(result)
})

testthat::test_that("is_autoimmune_code: empty input -> logical(0)", {
  result <- is_autoimmune_code(character(0), character(0), codes = test_codes, accept = test_accept)
  testthat::expect_equal(result, logical(0))
})

testthat::test_that("is_autoimmune_code: vectorised mix", {
  dx    <- c("M05.79", "714.0",  "C81.90", "M05.9")
  dtype <- c("10",     "09",     "10",     "09"   )
  result <- is_autoimmune_code(dx, dtype, codes = test_codes, accept = test_accept)
  testthat::expect_equal(result, c(TRUE, TRUE, FALSE, FALSE))
})

testthat::test_that("is_autoimmune_code: real config constant — ICD-10 keys present", {
  testthat::expect_true("M05"   %in% names(AUTOIMMUNE_DX_CODES$icd10))
  testthat::expect_true("L40"   %in% names(AUTOIMMUNE_DX_CODES$icd10))
  testthat::expect_true("M0809" %in% names(AUTOIMMUNE_DX_CODES$icd10))
})

testthat::test_that("is_autoimmune_code: real config constant — icd9 slot is empty (ICD-9 excluded 2026-10-29)", {
  testthat::expect_equal(length(AUTOIMMUNE_DX_CODES$icd9), 0L)
})

testthat::test_that("is_autoimmune_code: 714.0/'09' -> FALSE with real constant (empty icd9 slot)", {
  # Confirms the empty icd9 slot silently passes through without matching any code
  result <- is_autoimmune_code("714.0", "09")   # uses real AUTOIMMUNE_DX_CODES from config
  testthat::expect_false(result)
})

# ===========================================================================
# SECTION 2: summarise_autoimmune_dx()
# ===========================================================================

make_dx <- function(ID, DX, DX_TYPE, DX_DATE, ADMIT_DATE) {
  tibble::tibble(ID = ID, DX = DX, DX_TYPE = DX_TYPE,
                 DX_DATE = as.Date(DX_DATE), ADMIT_DATE = as.Date(ADMIT_DATE))
}

testthat::test_that("summarise_autoimmune_dx: no qualifying codes -> FALSE/NA for all cohort IDs", {
  dx <- make_dx("P1", "C81.90", "10", "2020-01-01", "2020-01-01")
  out <- summarise_autoimmune_dx(dx, cohort_ids = c("P1", "P2"), sentinel = sentinel)
  testthat::expect_equal(nrow(out), 2L)
  testthat::expect_true(all(!out$has_autoimmune_dx))
  testthat::expect_true(all(is.na(out$first_autoimmune_dx_date)))
})

testthat::test_that("summarise_autoimmune_dx: one dated ICD-10 -> TRUE/date", {
  dx <- make_dx("P1", "M05.79", "10", "2020-06-15", "2020-06-14")
  out <- summarise_autoimmune_dx(dx, cohort_ids = "P1", sentinel = sentinel)
  testthat::expect_true(out$has_autoimmune_dx)
  testthat::expect_equal(out$first_autoimmune_dx_date, as.Date("2020-06-15"))
})

testthat::test_that("summarise_autoimmune_dx: one dated ICD-9 -> TRUE/date", {
  dx <- make_dx("P1", "714.0", "09", "2018-03-01", NA)
  out <- summarise_autoimmune_dx(dx, cohort_ids = "P1", sentinel = sentinel)
  testthat::expect_true(out$has_autoimmune_dx)
  testthat::expect_equal(out$first_autoimmune_dx_date, as.Date("2018-03-01"))
})

testthat::test_that("summarise_autoimmune_dx: multiple dates -> earliest", {
  dx <- rbind(
    make_dx("P1", "M05.79", "10", "2020-06-15", NA),
    make_dx("P1", "M06.00", "10", "2019-11-01", NA)
  )
  out <- summarise_autoimmune_dx(dx, cohort_ids = "P1", sentinel = sentinel)
  testthat::expect_equal(out$first_autoimmune_dx_date, as.Date("2019-11-01"))
})

testthat::test_that("summarise_autoimmune_dx: sentinel-only dates -> FALSE/NA and qc TRUE", {
  dx <- make_dx("P1", "M05.79", "10", "1900-01-01", "1900-01-01")
  out <- summarise_autoimmune_dx(dx, cohort_ids = "P1", sentinel = sentinel)
  testthat::expect_false(out$has_autoimmune_dx)
  testthat::expect_true(is.na(out$first_autoimmune_dx_date))
  testthat::expect_true(out$qc_qualifying_no_valid_date)
})

testthat::test_that("summarise_autoimmune_dx: invalid DX_DATE + valid ADMIT_DATE -> uses ADMIT_DATE", {
  dx <- make_dx("P1", "M05.79", "10", "1900-01-01", "2021-05-10")
  out <- summarise_autoimmune_dx(dx, cohort_ids = "P1", sentinel = sentinel)
  testthat::expect_true(out$has_autoimmune_dx)
  testthat::expect_equal(out$first_autoimmune_dx_date, as.Date("2021-05-10"))
})

testthat::test_that("summarise_autoimmune_dx: mixed dated/undated rows -> TRUE, qc FALSE", {
  # One row has valid date, one has only sentinel dates
  dx <- rbind(
    make_dx("P1", "M05.79", "10", "2020-06-15", NA),
    make_dx("P1", "M05.79", "10", "1900-01-01", "1900-01-01")
  )
  out <- summarise_autoimmune_dx(dx, cohort_ids = "P1", sentinel = sentinel)
  testthat::expect_true(out$has_autoimmune_dx)
  # qc_qualifying_no_valid_date should be FALSE because patient has at least one valid date
  testthat::expect_false(out$qc_qualifying_no_valid_date)
})

testthat::test_that("summarise_autoimmune_dx: duplicate rows collapse to one row per ID", {
  dx <- rbind(
    make_dx("P1", "M05.79", "10", "2020-06-15", NA),
    make_dx("P1", "M05.79", "10", "2020-06-15", NA)
  )
  out <- summarise_autoimmune_dx(dx, cohort_ids = "P1", sentinel = sentinel)
  testthat::expect_equal(nrow(out), 1L)
})

testthat::test_that("summarise_autoimmune_dx: cohort ID with no DIAGNOSIS rows -> present, FALSE/NA", {
  dx <- make_dx("P1", "M05.79", "10", "2020-01-01", NA)
  out <- summarise_autoimmune_dx(dx, cohort_ids = c("P1", "P2"), sentinel = sentinel)
  p2 <- out[out$ID == "P2", ]
  testthat::expect_equal(nrow(p2), 1L)
  testthat::expect_false(p2$has_autoimmune_dx)
  testthat::expect_true(is.na(p2$first_autoimmune_dx_date))
})

testthat::test_that("summarise_autoimmune_dx: output rows == n distinct cohort IDs", {
  dx <- rbind(
    make_dx("P1", "M05.79", "10", "2020-01-01", NA),
    make_dx("P2", "L40.0",  "10", "2021-03-01", NA),
    make_dx("P2", "L40.0",  "10", "2020-12-01", NA)
  )
  cohort <- c("P1", "P2", "P3")
  out <- summarise_autoimmune_dx(dx, cohort_ids = cohort, sentinel = sentinel)
  testthat::expect_equal(nrow(out), dplyr::n_distinct(cohort))
})

testthat::test_that("summarise_autoimmune_dx: join test — multi-row episodes table preserves row count and value consistency", {
  dx <- make_dx("P1", "M05.79", "10", "2020-01-15", NA)
  flags <- summarise_autoimmune_dx(dx, cohort_ids = c("P1", "P2"), sentinel = sentinel) |>
    dplyr::select(patient_id = ID, has_autoimmune_dx, first_autoimmune_dx_date)

  episodes <- tibble::tibble(
    patient_id    = c("P1", "P1", "P2"),
    episode_number = c(1L,  2L,  1L),
    treatment_type = c("Chemotherapy", "Radiation", "Chemotherapy")
  )
  n0 <- nrow(episodes)
  joined <- dplyr::left_join(episodes, flags, by = "patient_id")
  testthat::expect_equal(nrow(joined), n0)
  # All rows for P1 have the same flag value
  p1_rows <- joined[joined$patient_id == "P1", ]
  testthat::expect_equal(length(unique(p1_rows$has_autoimmune_dx)), 1L)
  testthat::expect_equal(length(unique(as.character(p1_rows$first_autoimmune_dx_date))), 1L)
})
