library(testthat)

# Source the utils so functions are available
source("R/00_config.R")  # sets CONFIG, auto-sources utils_address.R

# --- Fixture ---
make_result_tbl <- function(ID, query_date, ZIP9, ZIP5, match_type) {
  tibble::tibble(ID = ID, query_date = as.Date(query_date),
                 ZIP9 = ZIP9, ZIP5 = ZIP5, match_type = match_type)
}

test_that("Tier 3: zip5_centroid fires when modal lookup has no hit but centroid lookup does", {
  inp <- make_result_tbl("P1", "2020-01-01", NA_character_, "32611", "interval")
  modal_lkp    <- tibble::tibble(ZIP5 = character(), modal_zip9 = character(),
                                  zip5_modal_freq = integer(),
                                  zip5_n_candidates = integer(),
                                  zip5_modal_share = double())
  centroid_lkp <- tibble::tibble(ZIP5 = "32611", centroid_zip9 = "326111234")
  out <- .classify_zip9_source(inp, modal_lkp, unavailable = FALSE,
                                centroid_lookup = centroid_lkp)
  expect_equal(out$zip9_source, "zip5_centroid")
  expect_equal(out$ZIP9, "326111234")
})

test_that("Tier 3: zip5_no_zip9 fires when neither modal nor centroid has a hit", {
  inp <- make_result_tbl("P1", "2020-01-01", NA_character_, "32611", "interval")
  modal_lkp    <- tibble::tibble(ZIP5 = character(), modal_zip9 = character(),
                                  zip5_modal_freq = integer(),
                                  zip5_n_candidates = integer(),
                                  zip5_modal_share = double())
  centroid_lkp <- tibble::tibble(ZIP5 = character(), centroid_zip9 = character())
  out <- .classify_zip9_source(inp, modal_lkp, unavailable = FALSE,
                                centroid_lookup = centroid_lkp)
  expect_equal(out$zip9_source, "zip5_no_zip9")
  expect_true(is.na(out$ZIP9))
})

test_that("Tier 3: zip5_modal takes priority over centroid when both are available", {
  inp <- make_result_tbl("P1", "2020-01-01", NA_character_, "32611", "interval")
  modal_lkp <- tibble::tibble(ZIP5 = "32611", modal_zip9 = "326111234",
                               zip5_modal_freq = 10L, zip5_n_candidates = 1L,
                               zip5_modal_share = 1.0)
  centroid_lkp <- tibble::tibble(ZIP5 = "32611", centroid_zip9 = "326111234")
  out <- .classify_zip9_source(inp, modal_lkp, unavailable = FALSE,
                                centroid_lookup = centroid_lkp)
  expect_equal(out$zip9_source, "zip5_modal")
  expect_equal(out$ZIP9, "326111234")
})

test_that("Tier 3: zip9_observed rows are not touched by centroid tier", {
  inp <- make_result_tbl("P1", "2020-01-01", "326114567", "32611", "interval")
  modal_lkp    <- tibble::tibble(ZIP5 = character(), modal_zip9 = character(),
                                  zip5_modal_freq = integer(),
                                  zip5_n_candidates = integer(),
                                  zip5_modal_share = double())
  centroid_lkp <- tibble::tibble(ZIP5 = "32611", centroid_zip9 = "326111234")
  out <- .classify_zip9_source(inp, modal_lkp, unavailable = FALSE,
                                centroid_lookup = centroid_lkp)
  expect_equal(out$zip9_source, "zip9_observed")
  expect_equal(out$ZIP9, "326114567")
})

test_that("Tier 3: row count is preserved (stopifnot guard)", {
  inp <- make_result_tbl(c("P1","P2"), c("2020-01-01","2020-06-01"),
                          c(NA_character_, "326115678"),
                          c("32611", "32611"),
                          c("interval", "interval"))
  modal_lkp    <- tibble::tibble(ZIP5 = character(), modal_zip9 = character(),
                                  zip5_modal_freq = integer(),
                                  zip5_n_candidates = integer(),
                                  zip5_modal_share = double())
  centroid_lkp <- tibble::tibble(ZIP5 = "32611", centroid_zip9 = "326111234")
  out <- .classify_zip9_source(inp, modal_lkp, unavailable = FALSE,
                                centroid_lookup = centroid_lkp)
  expect_equal(nrow(out), 2L)
})

# P1-02: Existing-tier regression — crosswalk absent leaves behaviour identical
# NOTE: Record .baseline_n_zip9_resolved from a HiPerGator run BEFORE the Tier 3 edit.
test_that("Tier 3 absent leaves existing behaviour identical", {
  skip_if_not(file.exists(file.path(CONFIG$data_dir, "LDS_ADDRESS_HISTORY_Mailhot_V1.csv")))
  skip_if(file.exists(file.path("data", "reference", "zip5_centroid_zip9_crosswalk.csv")),
          "crosswalk present — this test covers the absent case")

  fixture <- get_zip9_at_date(sample_ids, sample_dates)
  out     <- approximate_zip9(fixture)

  expect_setequal(unique(out$zip9_source),
                  c("already_has_zip9", "zip5_modal", "zip5_no_zip9", "not_attempted"))
  expect_false("zip5_centroid" %in% out$zip9_source)
  expect_identical(sum(!is.na(out$ZIP9)), .baseline_n_zip9_resolved)   # recorded constant
})

# P1-03a: approximate_zip9() on a fixture with crosswalk absent -> no zip5_centroid, warning emitted
test_that("approximate_zip9: no zip5_centroid rows when crosswalk absent", {
  # Uses injection: pass empty centroid_lookup directly to .classify_zip9_source
  inp <- make_result_tbl("P1", "2020-01-01", NA_character_, "32611", "interval")
  modal_lkp    <- tibble::tibble(ZIP5 = character(), modal_zip9 = character(),
                                  zip5_modal_freq = integer(),
                                  zip5_n_candidates = integer(),
                                  zip5_modal_share = double())
  out <- .classify_zip9_source(inp, modal_lkp, unavailable = FALSE, centroid_lookup = NULL)
  expect_false("zip5_centroid" %in% out$zip9_source)
})

# P1-03b: approximate_zip9() with a two-row synthetic crosswalk -> zip5_centroid fires for covered ZIP5
test_that("approximate_zip9: zip5_centroid fires for ZIP5 in crosswalk, not for others", {
  inp <- make_result_tbl(c("P1","P2"), c("2020-01-01","2020-01-01"),
                          c(NA_character_, NA_character_),
                          c("32611", "32612"), c("interval","interval"))
  modal_lkp    <- tibble::tibble(ZIP5 = character(), modal_zip9 = character(),
                                  zip5_modal_freq = integer(),
                                  zip5_n_candidates = integer(),
                                  zip5_modal_share = double())
  centroid_lkp <- tibble::tibble(ZIP5 = "32611", centroid_zip9 = "326110001")
  out <- .classify_zip9_source(inp, modal_lkp, unavailable = FALSE,
                                centroid_lookup = centroid_lkp)
  expect_equal(out$zip9_source[out$ID == "P1"], "zip5_centroid")
  expect_equal(out$zip9_source[out$ID == "P2"], "zip5_no_zip9")
})

# P1-03c: the 0000 guard raises on a crosswalk containing a synthetic ZIP9
test_that("0000 guard raises on synthetic ZIP9 in crosswalk", {
  # Exercises the guard inside approximate_zip9() via a staged crosswalk file.
  # Do NOT inline a copy of the guard body here -- that would pass even if the
  # real guard were broken (as it was when it read $ZIP9 instead of $centroid_zip9).
  tmp_ref <- withr::local_tempdir()
  dir.create(file.path(tmp_ref, "data", "reference"), recursive = TRUE)
  utils::write.csv(
    data.frame(ZIP5 = "32611", centroid_zip9 = "326110000"),
    file.path(tmp_ref, "data", "reference", "zip5_centroid_zip9_crosswalk.csv"),
    row.names = FALSE)

  # The cache is keyed by (path, mtime, size), so a newly staged file rebuilds
  # it automatically -- no reset helper is needed or defined.
  withr::with_dir(tmp_ref, {
    inp <- make_result_tbl("P1", "2020-01-01", NA_character_, "32611", "interval")
    expect_error(approximate_zip9(inp), "synthetic placeholders")
  })
})
