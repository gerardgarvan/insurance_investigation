# tests/testthat/test-201-abvd-tr-flags.R
# Phase 201: Unit tests for classify_abvd_episode()
# build_tr_lymphoma_flags() requires a live DB; tested on HiPerGator only.

library(testthat)

# Source 00_config.R from repo root (testthat sets wd to tests/testthat)
repo_root <- testthat::test_path("..", "..")
suppressMessages(source(file.path(repo_root, "R", "00_config.R")))

# ---------------------------------------------------------------------------
# classify_abvd_episode() tests
# ---------------------------------------------------------------------------

test_that("full ABVD (sorted semicolons) -> ABVD", {
  result <- classify_abvd_episode(
    "Bleomycin;Dacarbazine;Doxorubicin;Vinblastine",
    NA_character_
  )
  expect_equal(result, "ABVD")
})

test_that("AVD (no Bleomycin) -> AVD", {
  result <- classify_abvd_episode(
    "Dacarbazine;Doxorubicin;Vinblastine",
    NA_character_
  )
  expect_equal(result, "AVD")
})

test_that("BV+AVD (Brentuximab Vedotin present) -> NA", {
  result <- classify_abvd_episode(
    "Brentuximab Vedotin;Dacarbazine;Doxorubicin;Vinblastine",
    NA_character_
  )
  expect_true(is.na(result))
})

test_that("ABVD + extra agent (Rituximab) -> ABVD_PLUS", {
  result <- classify_abvd_episode(
    "Bleomycin;Dacarbazine;Doxorubicin;Rituximab;Vinblastine",
    NA_character_
  )
  expect_equal(result, "ABVD_PLUS")
})

test_that("variant tokens collapse to 4 families -> ABVD", {
  # Doxorubicin Hydrochloride maps to ^doxorubicin family
  # Vinblastine Sulfate maps to ^vinblastine family
  # Net: doxorubicin, bleomycin, vinblastine, dacarbazine -> n_families = 4 -> ABVD
  result <- classify_abvd_episode(
    "Bleomycin;Dacarbazine;Doxorubicin Hydrochloride;Vinblastine;Vinblastine Sulfate",
    NA_character_
  )
  expect_equal(result, "ABVD")
})

test_that("blank drug_names with r28 == ABVD -> JCODE_ABVD", {
  result <- classify_abvd_episode("", "ABVD")
  expect_equal(result, "JCODE_ABVD")
})

test_that("blank drug_names with r28 == NA -> NA", {
  result <- classify_abvd_episode("", NA_character_)
  expect_true(is.na(result))
})

test_that("non-ABVD regimen (CHOP-like) -> NA", {
  result <- classify_abvd_episode(
    "Cyclophosphamide;Doxorubicin;Vincristine",
    NA_character_
  )
  expect_true(is.na(result))
})

test_that("vectorized over multiple rows", {
  drug_vec <- c(
    "Bleomycin;Dacarbazine;Doxorubicin;Vinblastine",
    "Dacarbazine;Doxorubicin;Vinblastine",
    "",
    "Cyclophosphamide;Doxorubicin;Vincristine"
  )
  r28_vec  <- c(NA, NA, "ABVD", NA)
  result   <- classify_abvd_episode(drug_vec, r28_vec)
  expect_equal(result, c("ABVD", "AVD", "JCODE_ABVD", NA_character_))
})
