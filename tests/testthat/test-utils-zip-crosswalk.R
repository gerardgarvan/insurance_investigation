source(here::here("R/00_config.R"))

# ==============================================================================
# test-utils-zip-crosswalk.R -- Unit tests for HRSA crosswalk helpers
# Phase 182.1: ZIP Centroid Mapping for Unique/PO-Box and Placeholder ZIPs
# ==============================================================================
# Tests run on HiPerGator (Phase 182.1 Plan 04). Local runs use in-memory
# fixtures only -- no real crosswalk file required.
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
# Test block 1: load_hrsa_crosswalk() -- header variants and padding
# ==============================================================================
test_that("load_hrsa_crosswalk accepts ZIP_CODE/ZCTA headers and pads to 5 digits", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))

  # ZIP_CODE column name, lower-case ZCTA, raw unpadded values
  write.csv(
    data.frame(ZIP_CODE = c("501", "32608"), zcta = c("501", "32608"),
               stringsAsFactors = FALSE),
    tmp, row.names = FALSE
  )

  xwalk <- load_hrsa_crosswalk(tmp)
  expect_true(is.data.frame(xwalk))
  expect_true(all(c("ZIP", "ZCTA") %in% names(xwalk)))
  # "501" should be left-padded to "00501"
  expect_true("00501" %in% xwalk$ZIP)
  expect_true("00501" %in% xwalk$ZCTA)
  expect_equal(attr(xwalk, "source_file"), basename(tmp))
})

test_that("load_hrsa_crosswalk accepts ZIP (not ZIP_CODE) column name", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))

  write.csv(
    data.frame(ZIP = "32610", ZCTA = "32608", stringsAsFactors = FALSE),
    tmp, row.names = FALSE
  )

  xwalk <- load_hrsa_crosswalk(tmp)
  expect_equal(xwalk$ZIP,  "32610")
  expect_equal(xwalk$ZCTA, "32608")
})

# ==============================================================================
# Test block 2: load_hrsa_crosswalk() -- error cases
# ==============================================================================
test_that("load_hrsa_crosswalk stops with clear message when file is missing", {
  expect_error(
    load_hrsa_crosswalk("/nonexistent/path/crosswalk.csv"),
    regexp = "HRSA ZIP.*ZCTA crosswalk not found"
  )
})

test_that("load_hrsa_crosswalk stops when required columns are absent", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  write.csv(
    data.frame(ZIPCODE = "32610", ZCTA5 = "32608", stringsAsFactors = FALSE),
    tmp, row.names = FALSE
  )
  expect_error(
    load_hrsa_crosswalk(tmp),
    regexp = "crosswalk needs ZIP_CODE.*and ZCTA columns"
  )
})

test_that("load_hrsa_crosswalk stops with clear message when path is NULL", {
  expect_error(
    load_hrsa_crosswalk(NULL),
    regexp = "HRSA ZIP.*ZCTA crosswalk not found"
  )
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
