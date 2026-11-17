# tests/testthat/test-210-abvd-avd-flags.R
# Phase 210: unit tests for compute_abvd_avd_flags(), patient_ever_flag(), abvd_flag_dictionary()

library(testthat)

repo_root <- testthat::test_path("..", "..")
suppressMessages(source(file.path(repo_root, "R", "00_config.R")))

CHEMO <- "Chemotherapy"
flags <- function(d, tt = CHEMO, bv = TRUE, ...) {
  compute_abvd_avd_flags(d, rep_len(tt, length(d)), avd_includes_bv_nivo = bv, ...)
}
expect_flags <- function(res, abvd, avd, fb = FALSE) {
  expect_identical(res$abvd_episode, abvd)
  expect_identical(res$avd_episode, avd)
  expect_identical(res$abvd_jcode_fallback, fb)
}

ABVD4 <- "Bleomycin;Dacarbazine;Doxorubicin;Vinblastine"

test_that("ABVD and ABVD_PLUS and ABVD+BV are abvd TRUE", {
  for (bv in c(TRUE, FALSE)) {
    expect_flags(flags(ABVD4, bv = bv), TRUE, FALSE)
    expect_flags(flags("Bleomycin;Dacarbazine;Doxorubicin;Rituximab;Vinblastine", bv = bv), TRUE, FALSE)
    expect_flags(flags("Bleomycin;Brentuximab Vedotin;Dacarbazine;Doxorubicin;Vinblastine", bv = bv), TRUE, FALSE)
  }
})

test_that("AVD variants", {
  for (bv in c(TRUE, FALSE)) {
    expect_flags(flags("Dacarbazine;Doxorubicin;Vinblastine", bv = bv), FALSE, TRUE)
    expect_flags(flags("Dacarbazine;Doxorubicin;Rituximab;Vinblastine", bv = bv), FALSE, TRUE)
    expect_flags(flags("Dacarbazine;Doxorubicin;Leuprolide;Vinblastine", bv = bv), FALSE, TRUE)
    expect_flags(flags("Doxorubicin, Vinblastine, Dacarbazine", bv = bv), FALSE, TRUE)
    expect_flags(flags("doxorubicin hydrochloride;Vinblastine Sulfate;DACARBAZINE", bv = bv), FALSE, TRUE)
  }
})

test_that("BV+AVD and Nivo+AVD follow the setting", {
  bvavd <- "Brentuximab Vedotin;Dacarbazine;Doxorubicin;Vinblastine"
  nivo  <- "Dacarbazine;Doxorubicin;Nivolumab;Vinblastine"
  expect_flags(flags(bvavd, bv = TRUE), FALSE, TRUE)
  expect_flags(flags(bvavd, bv = FALSE), FALSE, FALSE)
  expect_flags(flags(nivo, bv = TRUE), FALSE, TRUE)
  expect_flags(flags(nivo, bv = FALSE), FALSE, FALSE)
})

test_that("partial, blank and non-chemo rows are FALSE", {
  expect_flags(flags(c("Doxorubicin;Vinblastine", "Bleomycin;Doxorubicin;Vinblastine",
                       "Bleomycin;Dacarbazine;Doxorubicin")), rep(FALSE, 3), rep(FALSE, 3), rep(FALSE, 3))
  expect_flags(flags(c("", NA_character_)), rep(FALSE, 2), rep(FALSE, 2), rep(FALSE, 2))
  expect_flags(flags(ABVD4, tt = "Immunotherapy"), FALSE, FALSE)
  expect_flags(compute_abvd_avd_flags(ABVD4, NA_character_, avd_includes_bv_nivo = TRUE), FALSE, FALSE)
})

test_that("blank drugs with JCODE_ABVD falls back to abvd TRUE", {
  r <- flags(c("", NA_character_), abvd_class = c("JCODE_ABVD", "JCODE_ABVD"))
  expect_flags(r, c(TRUE, TRUE), c(FALSE, FALSE), c(TRUE, TRUE))
  # non-chemo row with JCODE_ABVD is not flagged
  r2 <- flags("", tt = "Radiation", abvd_class = "JCODE_ABVD")
  expect_flags(r2, FALSE, FALSE, FALSE)
})

test_that("blank drugs with other or NA abvd_class gives F/F, no fallback", {
  r <- flags(c("", "", ""), abvd_class = c(NA, "ABVD", "OTHER"))
  expect_flags(r, rep(FALSE, 3), rep(FALSE, 3), rep(FALSE, 3))
  expect_flags(flags("", abvd_class = NULL), FALSE, FALSE)
})

test_that("J-code evidence with blank drug_names", {
  expect_flags(flags("", code_text = "J9000;J9040;J9360;J9130"), TRUE, FALSE)
  expect_flags(flags("", code_text = "J9000 J9360 J9130"), FALSE, TRUE)
  expect_flags(flags("", code_text = "J9000|J9040|J9360|J9130", abvd_class = "JCODE_ABVD"), TRUE, FALSE)
  expect_flags(flags(NA_character_, code_text = "J9000,J9360,J9130"), FALSE, TRUE)
})

test_that("J9042 / J9299 respect AVD_INCLUDES_BV_NIVO", {
  for (cd in c("J9042;J9000;J9360;J9130", "J9299;J9000;J9360;J9130")) {
    expect_flags(flags("", code_text = cd, bv = TRUE), FALSE, TRUE)
    expect_flags(flags("", code_text = cd, bv = FALSE), FALSE, FALSE)
  }
})

test_that("J-code evidence combines with drug_names", {
  expect_flags(flags("Doxorubicin;Vinblastine", code_text = "J9130"), FALSE, TRUE)
  expect_flags(flags("Doxorubicin;Vinblastine;Dacarbazine", code_text = "J9040"), TRUE, FALSE)
})

test_that("JCODE_ABVD with partial evidence follows evidence, no fallback", {
  expect_flags(flags("", code_text = "J9000;J9360", abvd_class = "JCODE_ABVD"), FALSE, FALSE)
  expect_flags(flags("Doxorubicin", abvd_class = "JCODE_ABVD"), FALSE, FALSE)
  expect_flags(flags("", code_text = "J9000;J9360;J9130", abvd_class = "JCODE_ABVD"), FALSE, TRUE)
})

test_that("unrecognised code text is not evidence", {
  expect_flags(flags("", code_text = "J9999;99213", abvd_class = "JCODE_ABVD"), TRUE, FALSE, TRUE)
})

test_that("mutual exclusion, no NA, shape", {
  d <- c(ABVD4, "Dacarbazine;Doxorubicin;Vinblastine", "", NA_character_,
         "Brentuximab Vedotin;Dacarbazine;Doxorubicin;Vinblastine")
  for (bv in c(TRUE, FALSE)) {
    r <- flags(d, bv = bv, abvd_class = rep("JCODE_ABVD", 5), code_text = rep(NA_character_, 5))
    expect_equal(nrow(r), length(d))
    expect_false(anyNA(r))
    expect_false(any(r$abvd_episode & r$avd_episode))
    expect_true(all(vapply(r, is.logical, logical(1))))
  }
})

test_that("argument validation", {
  expect_error(compute_abvd_avd_flags(c("a", "b"), "Chemotherapy"))
  expect_error(compute_abvd_avd_flags("a", "Chemotherapy", avd_includes_bv_nivo = NA))
  expect_error(compute_abvd_avd_flags("a", "Chemotherapy", avd_includes_bv_nivo = c(TRUE, FALSE)))
  expect_error(compute_abvd_avd_flags("a", "Chemotherapy", code_text = c("x", "y")))
})

test_that("default setting equals AVD_INCLUDES_BV_NIVO", {
  skip_if(nzchar(Sys.getenv("AVD_INCLUDES_BV_NIVO")))
  expect_true(AVD_INCLUDES_BV_NIVO)
  d <- "Brentuximab Vedotin;Dacarbazine;Doxorubicin;Vinblastine"
  expect_identical(compute_abvd_avd_flags(d, CHEMO),
                   compute_abvd_avd_flags(d, CHEMO, avd_includes_bv_nivo = AVD_INCLUDES_BV_NIVO))
})

test_that("patient_ever_flag", {
  id <- c("A", "A", "A", "B", "B")
  f  <- c(TRUE, FALSE, FALSE, FALSE, FALSE)
  r <- patient_ever_flag(id, f)
  expect_identical(r, c(TRUE, TRUE, TRUE, FALSE, FALSE))
  expect_error(patient_ever_flag(id, c(f[1:4], NA)))
  expect_error(patient_ever_flag(id, f[1:4]))
})

test_that("abvd_flag_dictionary", {
  d <- abvd_flag_dictionary(avd_includes_bv_nivo = FALSE)
  expect_true(all(c("column", "level", "definition", "status") %in% names(d)))
  expect_true(all(c("abvd_episode", "avd_episode", "ever_abvd", "ever_avd",
                    "ever_abvd_plus", "abvd_class") %in% d$column))
  expect_identical(d$status[d$column == "ever_abvd_plus"], "deprecated")
  expect_identical(d$definition[grepl("AVD_INCLUDES_BV_NIVO", d$column)], "FALSE")
  expect_true(grepl("JCODE_ABVD", d$definition[d$column == "abvd_episode"]))
})
