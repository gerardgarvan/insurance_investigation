# Phase 160-01: CMP threshold in the staged codeset; Modalities eligible_sex
# Run from repo root: testthat::test_file("tests/testthat/test-160-loader-eligible-sex.R")

repo_root <- testthat::test_path("..", "..")
if (!exists("modality_eligible_sex"))
  source(file.path(repo_root, "R", "utils", "utils_surveillance.R"))
staged <- file.path(repo_root, "data", "reference", "surveillance_codeset.xlsx")

mods_book <- function(mods) {
  tmp <- tempfile(fileext = ".xlsx")
  writexl::write_xlsx(list(Modalities = mods), tmp)
  tmp
}
base_mods <- data.frame(modality = c("Mammogram", "BMP"), column_prefix = c("mammo", "bmp"),
                        display_order = c("1", "2"))

test_that("staged codeset: CMP threshold keeps a full BMP out; eligible_sex on breast imaging", {
  cs <- load_surveillance_codeset(staged)
  k <- as.integer(cs$min_analyte_count[cs$modality == "CMP" & cs$match == "analyte_min_same_day"])
  expect_gt(k, 8L)                       # 8 = a full BMP; the rule, not a literal value
  expect_equal(k, 11L)                   # 160 D-01
  lk <- load_modality_lookup(staged, codeset = cs)
  es <- modality_eligible_sex(lk)
  expect_setequal(names(es)[es == "F"], c("Mammogram", "Breast MRI"))
  expect_true(all(es[!names(es) %in% c("Mammogram", "Breast MRI")] == ""))
})

test_that("a Modalities sheet without eligible_sex loads unchanged", {
  lk <- load_modality_lookup(mods_book(base_mods))
  expect_identical(as.vector(lk), c("mammo", "bmp"))
  expect_identical(names(lk), c("Mammogram", "BMP"))
  expect_identical(unname(modality_eligible_sex(lk)), c("", ""))
})

test_that("eligible_sex F and M are read back; the named vector is unchanged", {
  m <- base_mods; m$eligible_sex <- c("F", "m")
  lk <- load_modality_lookup(mods_book(m))
  expect_identical(lk[["Mammogram"]], "mammo")
  expect_identical(modality_eligible_sex(lk)[["Mammogram"]], "F")
  expect_identical(modality_eligible_sex(lk)[["BMP"]], "M")
  expect_identical(modality_eligible_sex(c(a = "x")), c(a = ""))   # no attribute
})

test_that("an invalid eligible_sex value stops the load", {
  m <- base_mods; m$eligible_sex <- c("X", "")
  expect_error(load_modality_lookup(mods_book(m)), "eligible_sex")
})
