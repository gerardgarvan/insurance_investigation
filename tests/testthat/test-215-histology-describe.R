# Phase 215: describe_histology() with small in-test lookups (labels are synthetic,
# not real ICD-O terms). The real-reference tests skip when the reference files are absent.
terms <- data.frame(
  Value = c("9650", "9650", "9651", "9659", "8510", "8345", "8000", "8000", "8000"),
  strHistologyBehaviour = c("3", "3", "3", "3", "3", "3", "0", "1", "3"),
  Preferred = c("TRUE", "FALSE", "TRUE", "TRUE", "TRUE", "TRUE", "TRUE", "TRUE", "TRUE"),
  label = c("T9650-3", "T9650-3 synonym", "T9651-3", "T9659-3", "T8510-3", "T8345-3",
            "T8000-0", "T8000-1", "T8000-3"),
  stringsAsFactors = FALSE)
conv <- data.frame(
  icdo2_code5 = c("96573", "96603", "85103", "85103"),
  icdo3_code5 = c("96513", "96593", "85103", "83453"),
  site        = c("", "", "", "C73"),
  site_dependent = c("FALSE", "FALSE", "TRUE", "TRUE"),
  stringsAsFactors = FALSE)
lk <- build_histology_lookup(terms, conv)
dh <- function(code, site = NULL) describe_histology(code, site, lookup = lk)

test_that("lookup keeps preferred terms only and has no duplicate keys", {
  expect_false(anyDuplicated(lk$l5$key5) > 0)
  expect_false(anyDuplicated(lk$l4$hist4) > 0)
  expect_equal(lk$l5$description[lk$l5$key5 == "96503"], "T9650-3")
})

test_that("4-digit lookup prefers behavior 3", {
  expect_equal(lk$l4$description[lk$l4$hist4 == "8000"], "T8000-3")
})

test_that("duplicate preferred keys stop the build", {
  bad <- rbind(terms, terms[1, ])
  expect_error(build_histology_lookup(bad, conv), "duplicate preferred")
})

test_that("5-digit and slash forms match ICD-O-3 directly", {
  r <- dh(c("96503", "9650/3", " 96503 "))
  expect_equal(r$desc_source, rep("icdo3", 3))
  expect_equal(r$description, rep("T9650-3", 3))
  expect_equal(r$behavior, rep("3", 3)); expect_equal(r$hist4, rep("9650", 3))
})

test_that("4-digit code uses the 4-digit lookup", {
  r <- dh("9650")
  expect_equal(r$description, "T9650-3"); expect_equal(r$desc_source, "icdo3")
  expect_equal(r$match_level, "4digit"); expect_true(is.na(r$behavior))
})

test_that("ICD-O-2 codes convert", {
  r <- dh(c("96573", "96603"))
  expect_equal(r$icdo3_code, c("96513", "96593"))
  expect_equal(r$desc_source, rep("icdo3_via_icdo2_conversion", 2))
  expect_equal(r$description, c("T9651-3", "T9659-3"))
  expect_equal(r$raw_code, c("96573", "96603"))
})

test_that("5-digit code with unpaired behavior falls back to 4-digit term", {
  r <- dh("96500")
  expect_equal(r$description, "T9650-3"); expect_equal(r$match_level, "4digit")
})

test_that("site-dependent conversion: site row when it matches, else non-site row", {
  expect_equal(dh("85103", "C73")$icdo3_code, "85103")   # exact ICD-O-3 key wins
  lk2 <- build_histology_lookup(terms[terms$Value != "8510", ], conv)
  a <- describe_histology("85103", "C73.9", lookup = lk2)
  b <- describe_histology("85103", "C50", lookup = lk2)
  expect_equal(a$icdo3_code, "83453"); expect_equal(a$desc_source, "icdo3_via_icdo2_conversion")
  expect_equal(b$desc_source, "unmatched")  # non-site row 85103 -> 85103 not in terms
})

test_that("malformed, NA and empty codes are unmatched with raw value kept", {
  r <- dh(c("850003", NA, "", "ABCD", "965"))
  expect_equal(r$desc_source, rep("unmatched", 5))
  expect_equal(r$raw_code, c("850003", NA, "", "ABCD", "965"))
  expect_true(all(is.na(r$description)))
})

test_that("output length equals input length, in input order, with repeats and NAs", {
  x <- c("96503", NA, "96503", "9650", "96573", "850003", "96573", NA)
  r <- dh(x)
  expect_equal(nrow(r), length(x))
  expect_equal(r$raw_code, x)
  expect_equal(nrow(dh(character(0))), 0L)
  expect_equal(nrow(dh(x, site = "C73")), length(x))
})

test_that("joining the result back to rows does not change the row count", {
  rows <- data.frame(id = 1:6, code = c("96503", "96503", NA, "96573", "850003", "9650"))
  d <- dh(rows$code)
  out <- dplyr::bind_cols(rows, d[, c("icdo3_code", "description", "desc_source")])
  expect_equal(nrow(out), nrow(rows))
})

test_that("real reference files: structure and known codes (skips if absent)", {
  tp <- here::here("data", "reference", "Histology3_v27_20260821.xlsx")
  cp <- here::here("data", "reference", "icdo2_to_icdo3_conversion.csv")
  skip_if_not(file.exists(tp) && file.exists(cp), "reference files not staged here")
  rl <- build_histology_lookup(readxl::read_excel(tp, col_types = "text"),
                               utils::read.csv(cp, colClasses = "character",
                                               na.strings = character(0)))
  expect_false(anyDuplicated(rl$l5$key5) > 0)
  r <- describe_histology(c("96503", "9650", "96573", "96603", "850003", NA), lookup = rl)
  expect_equal(r$description[1], r$description[2])
  expect_equal(r$icdo3_code[3:4], c("96513", "96593"))
  expect_equal(r$desc_source[5:6], c("unmatched", "unmatched"))
})
