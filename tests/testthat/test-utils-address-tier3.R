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
#
# BASELINE: .BASELINE_N_ZIP9_RESOLVED must be recorded from a HiPerGator run made
# BEFORE the Tier 3 edit, using the same sample below:
#     cohort <- get_hl_patient_ids(); ids <- head(sort(cohort), 500)
#     sum(!is.na(approximate_zip9(get_zip9_at_date(ids, rep(as.Date("2020-01-01"), 500)))$ZIP9))
# Until that number is recorded, leave it NULL and the test skips rather than errors.
.BASELINE_N_ZIP9_RESOLVED <- NULL

test_that("Tier 3 absent leaves existing behaviour identical", {
  skip_if_not(file.exists(file.path(CONFIG$data_dir, "LDS_ADDRESS_HISTORY_Mailhot_V1.csv")))
  skip_if(file.exists(file.path("data", "reference", "zip5_centroid_zip9_crosswalk.csv")),
          "crosswalk present — this test covers the absent case")
  skip_if(is.null(.BASELINE_N_ZIP9_RESOLVED),
          "baseline not recorded yet — see comment above this test")

  sample_ids   <- head(sort(get_hl_patient_ids()), 500)
  sample_dates <- rep(as.Date("2020-01-01"), length(sample_ids))

  fixture <- get_zip9_at_date(sample_ids, sample_dates)
  out     <- approximate_zip9(fixture)

  # The taxonomy this function actually emits (see .classify_zip9_source):
  #   zip9_observed, zip5_modal, zip5_centroid, zip5_no_zip9, no_zip5,
  #   invalid_input, none, reference_unavailable
  # There is no "already_has_zip9" and no "not_attempted".
  # Subset rather than setequal: a 500-patient sample need not exercise every level.
  expect_true(all(unique(out$zip9_source) %in%
                    c("zip9_observed", "zip5_modal", "zip5_no_zip9", "no_zip5",
                      "invalid_input", "none", "reference_unavailable")))
  expect_false("zip5_centroid" %in% out$zip9_source)
  expect_identical(sum(!is.na(out$ZIP9)), .BASELINE_N_ZIP9_RESOLVED)
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
  skip_if_not(file.exists(file.path(CONFIG$data_dir, "LDS_ADDRESS_HISTORY_Mailhot_V1.csv")),
              "approximate_zip9 returns early via its address probe gate before reaching Tier 3")

  ref_dir <- withr::local_tempdir()
  utils::write.csv(
    data.frame(ZIP5 = "32611", centroid_zip9 = "326110000"),
    file.path(ref_dir, "zip5_centroid_zip9_crosswalk.csv"),
    row.names = FALSE)

  # approximate_zip9() resolves centroid_path from CONFIG$reference_dir when set,
  # so point it at the staged directory rather than changing the working directory
  # (which no longer affects the probe now that the path is project-root anchored).
  old_ref <- CONFIG$reference_dir
  CONFIG$reference_dir <<- ref_dir
  withr::defer(CONFIG$reference_dir <<- old_ref)

  inp <- make_result_tbl("P1", "2020-01-01", NA_character_, "32611", "interval")
  expect_error(approximate_zip9(inp), "synthetic placeholders")
})
