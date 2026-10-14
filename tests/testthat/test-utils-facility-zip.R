source(here::here("R/00_config.R"))
source(here::here("R/utils/utils_facility_zip.R"))

# ==============================================================================
# test-utils-facility-zip.R -- Unit tests for facility ZIP fill helpers
# Phase 182: Facility ZIP Recovery
# ==============================================================================

# Helper: build a minimal enc_raw data frame for build_facility_zip_lookup()
make_enc_raw <- function(SOURCE, FACILITYID, enc_zip_raw) {
  data.frame(
    SOURCE      = SOURCE,
    FACILITYID  = FACILITYID,
    enc_zip_raw = enc_zip_raw,
    stringsAsFactors = FALSE
  )
}

# Helper: build a minimal enc_for_dist data frame for apply_facility_zip_fill()
make_enc_for_dist <- function(SOURCE, FACILITYID, zip5_facility) {
  data.frame(
    SOURCE        = SOURCE,
    FACILITYID    = FACILITYID,
    zip5_facility = zip5_facility,
    ENCOUNTERID   = seq_along(SOURCE),
    stringsAsFactors = FALSE
  )
}

# ------------------------------------------------------------------------------
# Test 1: Tier 1 fills with 3 identical ZIPs
# ------------------------------------------------------------------------------
test_that("tier 1 fills when 3 encounters share exactly one ZIP", {
  enc_raw <- make_enc_raw(
    SOURCE      = rep("UF", 3),
    FACILITYID  = rep("FAC001", 3),
    enc_zip_raw = rep("32601", 3)
  )
  lk <- build_facility_zip_lookup(enc_raw)
  expect_equal(nrow(lk), 1L)
  expect_equal(lk$fill_status, "filled_tier1")
  expect_equal(lk$fill_zip, "32601")
  expect_equal(lk$n_supporting, 3L)
  expect_equal(lk$n_distinct_zips, 1L)
})

# ------------------------------------------------------------------------------
# Test 2: 2 identical ZIPs -> no_donor, NA fill
# ------------------------------------------------------------------------------
test_that("2 supporting encounters produce no_donor with NA fill", {
  enc_raw <- make_enc_raw(
    SOURCE      = rep("UF", 2),
    FACILITYID  = rep("FAC002", 2),
    enc_zip_raw = rep("32601", 2)
  )
  lk <- build_facility_zip_lookup(enc_raw)
  expect_equal(lk$fill_status, "no_donor")
  expect_true(is.na(lk$fill_zip))
  expect_equal(lk$n_supporting, 2L)
})

# ------------------------------------------------------------------------------
# Test 3: Disagreeing ZIPs -> ambiguous, n_distinct_zips == 2
# ------------------------------------------------------------------------------
test_that("disagreeing ZIPs produce ambiguous status with n_distinct_zips == 2", {
  enc_raw <- make_enc_raw(
    SOURCE      = rep("UF", 4),
    FACILITYID  = rep("FAC003", 4),
    enc_zip_raw = c("32601", "32601", "32608", "32608")
  )
  lk <- build_facility_zip_lookup(enc_raw)
  expect_equal(lk$fill_status, "ambiguous")
  expect_equal(lk$n_distinct_zips, 2L)
  expect_true(is.na(lk$fill_zip))
})

# ------------------------------------------------------------------------------
# Test 4: All ZIPs unparseable -> no_donor, n_supporting == 0
# ------------------------------------------------------------------------------
test_that("all unparseable ZIPs produce no_donor with n_supporting == 0", {
  enc_raw <- make_enc_raw(
    SOURCE      = rep("UF", 3),
    FACILITYID  = rep("FAC004", 3),
    enc_zip_raw = rep("GARBAGE", 3)
  )
  lk <- build_facility_zip_lookup(enc_raw)
  expect_equal(lk$fill_status, "no_donor")
  expect_equal(lk$n_supporting, 0L)
  expect_true(is.na(lk$fill_zip))
})

# ------------------------------------------------------------------------------
# Test 5: Same FACILITYID under two SOURCEs -> two rows, each its own ZIP
# ------------------------------------------------------------------------------
test_that("same FACILITYID under two SOURCEs produces two independent lookup rows", {
  enc_raw <- make_enc_raw(
    SOURCE      = c(rep("UF", 3), rep("FLH", 3)),
    FACILITYID  = rep("FAC005", 6),
    enc_zip_raw = c(rep("32601", 3), rep("33101", 3))
  )
  lk <- build_facility_zip_lookup(enc_raw)
  expect_equal(nrow(lk), 2L)
  lk_uf  <- lk[lk$SOURCE == "UF", ]
  lk_flh <- lk[lk$SOURCE == "FLH", ]
  expect_equal(lk_uf$fill_zip,  "32601")
  expect_equal(lk_flh$fill_zip, "33101")
  expect_equal(lk_uf$fill_status,  "filled_tier1")
  expect_equal(lk_flh$fill_status, "filled_tier1")
})

# ------------------------------------------------------------------------------
# Test 6: 19 x "32601" + 1 x "32608" -> ambiguous, sens_fill_ok TRUE
# ------------------------------------------------------------------------------
test_that("19/20 modal ZIP -> ambiguous tier1, sens_fill_ok TRUE (modal share 0.95)", {
  enc_raw <- make_enc_raw(
    SOURCE      = rep("UF", 20),
    FACILITYID  = rep("FAC006", 20),
    enc_zip_raw = c(rep("32601", 19), "32608")
  )
  lk <- build_facility_zip_lookup(enc_raw)
  expect_equal(lk$fill_status, "ambiguous")
  expect_equal(lk$sens_modal_zip, "32601")
  expect_equal(lk$sens_modal_share, 19 / 20)
  expect_true(lk$sens_fill_ok)
  expect_true(is.na(lk$fill_zip))  # Not filled in primary tier
})

# ------------------------------------------------------------------------------
# Test 7: NA and blank FACILITYID -> no lookup rows; NA-ZIP encounters stay NA
# ------------------------------------------------------------------------------
test_that("NA and blank FACILITYID are excluded from lookup; encounters get not_filled_no_key", {
  # 5 encounters: FACILITYID NA (3 with ZIP, 2 without)
  # 3 encounters: FACILITYID ""
  enc_raw <- make_enc_raw(
    SOURCE      = rep("UF", 8),
    FACILITYID  = c(NA, NA, NA, NA, NA, "", "", ""),
    enc_zip_raw = c("32601", "32601", "32601", NA, NA, "32601", "32601", "32601")
  )
  lk <- build_facility_zip_lookup(enc_raw)
  # No rows: both NA and blank are excluded
  expect_equal(nrow(lk), 0L)

  # apply should produce not_filled_no_key for all
  enc_dist <- make_enc_for_dist(
    SOURCE        = rep("UF", 5),
    FACILITYID    = c(NA, NA, NA, NA, ""),
    zip5_facility = c(NA, NA, NA, NA, NA)
  )
  out <- apply_facility_zip_fill(enc_dist, lk, apply = TRUE)
  expect_true(all(out$facility_zip_source == "not_filled_no_key"))
  expect_true(all(is.na(out$zip5_facility)))
  expect_equal(nrow(out), 5L)
})

# ------------------------------------------------------------------------------
# Test 8: Placeholder FACILITYID "UNKNOWN" treated as no key
# ------------------------------------------------------------------------------
test_that("FACILITYID 'UNKNOWN' is treated as no key (placeholder)", {
  enc_raw <- make_enc_raw(
    SOURCE      = rep("UF", 3),
    FACILITYID  = rep("UNKNOWN", 3),
    enc_zip_raw = rep("32601", 3)
  )
  lk <- build_facility_zip_lookup(enc_raw)
  expect_equal(nrow(lk), 0L)

  enc_dist <- make_enc_for_dist(
    SOURCE        = "UF",
    FACILITYID    = "UNKNOWN",
    zip5_facility = NA_character_
  )
  out <- apply_facility_zip_fill(enc_dist, lk, apply = TRUE)
  expect_equal(out$facility_zip_source, "not_filled_no_key")
})

# ------------------------------------------------------------------------------
# Test 9: Observed ZIP never overwritten; row count unchanged
# ------------------------------------------------------------------------------
test_that("observed zip5_facility is never overwritten; row count preserved", {
  # Build a tier1 lookup
  enc_raw <- make_enc_raw(
    SOURCE      = rep("UF", 3),
    FACILITYID  = rep("FAC009", 3),
    enc_zip_raw = rep("32601", 3)
  )
  lk <- build_facility_zip_lookup(enc_raw)

  # enc_for_dist: one row has observed ZIP "99999" (should stay), one has NA (should be filled)
  enc_dist <- make_enc_for_dist(
    SOURCE        = c("UF", "UF"),
    FACILITYID    = c("FAC009", "FAC009"),
    zip5_facility = c("99999", NA_character_)
  )
  out <- apply_facility_zip_fill(enc_dist, lk, apply = TRUE)
  expect_equal(nrow(out), 2L)
  # Observed row: zip5_facility unchanged, source = "observed"
  expect_equal(out$zip5_facility[1], "99999")
  expect_equal(out$facility_zip_source[1], "observed")
  # NA row: filled from tier1, source = "filled_tier1"
  expect_equal(out$zip5_facility[2], "32601")
  expect_equal(out$facility_zip_source[2], "filled_tier1")
})

# ------------------------------------------------------------------------------
# Test 10: apply = FALSE -> no fills, sources observed/not_filled only
# ------------------------------------------------------------------------------
test_that("apply = FALSE produces no filled_tier1 rows; only observed and not_filled", {
  enc_raw <- make_enc_raw(
    SOURCE      = rep("UF", 3),
    FACILITYID  = rep("FAC010", 3),
    enc_zip_raw = rep("32601", 3)
  )
  lk <- build_facility_zip_lookup(enc_raw)
  expect_equal(lk$fill_status, "filled_tier1")

  enc_dist <- make_enc_for_dist(
    SOURCE        = c("UF", "UF"),
    FACILITYID    = c("FAC010", "FAC010"),
    zip5_facility = c("99999", NA_character_)
  )
  out <- apply_facility_zip_fill(enc_dist, lk, apply = FALSE)
  expect_true(all(out$facility_zip_source %in% c("observed", "not_filled")))
  expect_false("filled_tier1" %in% out$facility_zip_source)
  # NA row stays NA
  expect_true(is.na(out$zip5_facility[2]))
})
