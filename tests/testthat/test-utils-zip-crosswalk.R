source(here::here("R/00_config.R"))

# ==============================================================================
# test-utils-zip-crosswalk.R -- Unit tests for ZIP-to-ZCTA crosswalk helpers
# Phase 182.1: ZIP Centroid Mapping for Unique/PO-Box and Placeholder ZIPs
# ==============================================================================
# Tests run on HiPerGator (Phase 182.1 Plan 04). Local runs use in-memory
# fixtures only -- no network call or crosswalk file required.
# ==============================================================================

# Helper: tiny in-memory crosswalk ------------------------------------------------
make_xwalk <- function() {
  data.frame(
    ZIP  = c("32608", "32610", "32601", "34201", "32800"),
    ZCTA = c("32608", "32608", "32601", "34201", "32800"),
    stringsAsFactors = FALSE
  )
}

# ==============================================================================
# Test block 1: zi_normalise_xwalk() -- column detection and padding
# ==============================================================================
test_that("zi_normalise_xwalk accepts ZIP_CODE/ZCTA headers and pads to 5 digits", {
  raw <- data.frame(ZIP_CODE = c("501", "32608"), zcta = c("501", "32608"),
                    stringsAsFactors = FALSE)
  xwalk <- zi_normalise_xwalk(raw, label = "test")
  expect_true(is.data.frame(xwalk))
  expect_true(all(c("ZIP", "ZCTA") %in% names(xwalk)))
  expect_true("00501" %in% xwalk$ZIP)
  expect_true("00501" %in% xwalk$ZCTA)
  expect_equal(attr(xwalk, "source_file"), "test")
})

test_that("zi_normalise_xwalk accepts ZIP (not ZIP_CODE) column name", {
  raw <- data.frame(ZIP = "32610", ZCTA = "32608", stringsAsFactors = FALSE)
  xwalk <- zi_normalise_xwalk(raw)
  expect_equal(xwalk$ZIP,  "32610")
  expect_equal(xwalk$ZCTA, "32608")
})

test_that("zi_normalise_xwalk stops when required columns are absent", {
  raw <- data.frame(ZIPCODE = "32610", ZCTA5 = "32608", stringsAsFactors = FALSE)
  expect_error(
    zi_normalise_xwalk(raw),
    regexp = "crosswalk needs ZIP_CODE.*and ZCTA columns"
  )
})

test_that("zi_normalise_xwalk deduplicates on ZIP, keeping first row", {
  raw <- data.frame(
    ZIP_CODE = c("32608", "32608"),
    ZCTA     = c("32608", "99999"),
    stringsAsFactors = FALSE
  )
  xwalk <- zi_normalise_xwalk(raw)
  expect_equal(nrow(xwalk), 1L)
  expect_equal(xwalk$ZCTA, "32608")
})

# ==============================================================================
# Test block 2: load_hrsa_crosswalk() -- structure check (requires zippeR)
# ==============================================================================
test_that("load_hrsa_crosswalk() returns ZIP/ZCTA data.frame via zippeR", {
  skip_if_not_installed("zippeR")
  xwalk <- load_hrsa_crosswalk()
  expect_true(is.data.frame(xwalk))
  expect_true(all(c("ZIP", "ZCTA") %in% names(xwalk)))
  expect_true(nrow(xwalk) > 1000)
  expect_equal(attr(xwalk, "source_file"), "zippeR::zi_load_crosswalk(UDS,2023)")
  # All ZIPs should be exactly 5 characters
  expect_true(all(nchar(xwalk$ZIP) == 5))
})

# ==============================================================================
# Test block 3: map_zip_to_zcta()
# ==============================================================================
test_that("map_zip_to_zcta returns ZCTA for known ZIPs and NA for unknown", {
  xwalk <- make_xwalk()

  # Known ZIP
  expect_equal(map_zip_to_zcta("32610", xwalk), "32608")
  expect_equal(map_zip_to_zcta("32608", xwalk), "32608")

  # Unknown ZIP
  expect_true(is.na(map_zip_to_zcta("99999", xwalk)))

  # Hyphenated ZIP+4 -- normalize_zip5_raw strips the +4 and returns "32610"
  expect_equal(map_zip_to_zcta("32610-1234", xwalk), "32608")
})

test_that("map_zip_to_zcta returns NA vector for all-unknown input", {
  xwalk <- make_xwalk()
  result <- map_zip_to_zcta(c("00001", "00002"), xwalk)
  expect_equal(length(result), 2L)
  expect_true(all(is.na(result)))
})

# ==============================================================================
# Test block 4: is_placeholder_facility_zip5()
# ==============================================================================
test_that("is_placeholder_facility_zip5 flags 000xx and absent ZIP3+00 codes", {
  xwalk <- make_xwalk()   # "32800" IS in xwalk; "32700" is NOT

  # 000xx patterns -- always placeholder
  expect_true(is_placeholder_facility_zip5("00000", xwalk))
  expect_true(is_placeholder_facility_zip5("00007", xwalk))

  # ZIP3+"00" absent from crosswalk -- placeholder
  expect_true(is_placeholder_facility_zip5("32700", xwalk))

  # ZIP3+"00" present in crosswalk -- NOT a placeholder (32800 is in make_xwalk())
  expect_false(is_placeholder_facility_zip5("32800", xwalk))

  # Real ZIP with non-"00" ending -- not a placeholder
  expect_false(is_placeholder_facility_zip5("32608", xwalk))

  # NA input -> NA output
  expect_true(is.na(is_placeholder_facility_zip5(NA_character_, xwalk)))
})

test_that("is_placeholder_facility_zip5 vectorises correctly", {
  xwalk <- make_xwalk()
  result <- is_placeholder_facility_zip5(c("00000", "32608", NA, "32700"), xwalk)
  expect_equal(result, c(TRUE, FALSE, NA, TRUE))
})
