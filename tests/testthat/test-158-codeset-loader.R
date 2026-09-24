# Phase 158-01: codeset loader + HL denominator helper
# Run from repo root: testthat::test_file("tests/testthat/test-158-codeset-loader.R")

# Paths resolve from the test directory (testthat sets wd to tests/testthat)
repo_root <- testthat::test_path("..", "..")
if (!exists("load_surveillance_codeset"))
  source(file.path(repo_root, "R", "utils", "utils_surveillance.R"))

cs_row <- function(...) {
  base <- list(codeset_row_id = "SC001", modality = "Echocardiogram",
               submodality = "", code_system = "CPT", code = "93306",
               code_norm = "93306", cdm_table = "PROCEDURES", cdm_column = "PX",
               type_filter = "CH", match = "exact", tier = "primary",
               plausibility = "")
  utils::modifyList(base, list(...))
}
write_cs <- function(rows) {
  df <- dplyr::bind_rows(lapply(rows, tibble::as_tibble))
  tmp <- tempfile(fileext = ".xlsx")
  writexl::write_xlsx(list(Analysis_Codeset = df), tmp)
  tmp
}

test_that("staged codeset loads and satisfies D-18/D-20/D-21/D-22 invariants", {
  cs <- load_surveillance_codeset(
    file.path(repo_root, "data", "reference", "surveillance_codeset.xlsx"))
  expect_gt(nrow(cs), 0)
  expect_false(anyDuplicated(cs$codeset_row_id) > 0)
  expect_true(all(vapply(cs, is.character, logical(1))))
  expect_equal(sum(cs$modality == "Stress test" &
                     cs$code_norm %in% c("93350", "93351", "93352")), 3L)
  expect_equal(sum(cs$modality == "Echocardiogram" &
                     cs$code_norm %in% c("93350", "93351", "93352")), 3L)
  expect_false(any(cs$modality == "Thyroid stimulating hormone"))
  expect_setequal(unique(cs$submodality[cs$modality == "Thyroid function"]),
                  c("TSH", "Free T4"))
  expect_equal(cs$code_norm[cs$match == "component_all_same_day"],
               "6690-2;718-7;777-3")
})

test_that("Excel numeric CPT cell is read back as the character code", {
  df <- tibble::as_tibble(cs_row())
  df$code_norm <- 77063     # numeric cell, as Excel stores typed CPT codes
  df$code      <- 77063
  tmp <- tempfile(fileext = ".xlsx")
  writexl::write_xlsx(list(Analysis_Codeset = df), tmp)
  cs <- load_surveillance_codeset(tmp)
  expect_type(cs$code_norm, "character")
  expect_equal(cs$code_norm, "77063")
})

test_that("trailing space and dot are normalized ('Z13.6 ' -> 'Z136')", {
  cs <- load_surveillance_codeset(write_cs(list(cs_row(
    code = "Z13.6 ", code_norm = "Z13.6 ", cdm_table = "DIAGNOSIS",
    cdm_column = "DX", type_filter = "10", tier = "sensitivity"))))
  expect_equal(cs$code_norm, "Z136")
})

test_that("blank cells become empty strings, not NA", {
  cs <- load_surveillance_codeset(write_cs(list(cs_row(
    code_system = "LOINC", code = "3016-3", code_norm = "3016-3",
    cdm_table = "LAB_RESULT_CM", cdm_column = "LAB_LOINC", type_filter = NA,
    submodality = NA))))
  expect_identical(cs$submodality, "")
  expect_identical(cs$type_filter, "")
})

test_that("loader rejects structural violations", {
  expect_error(load_surveillance_codeset(write_cs(list(cs_row(tier = "intermediate")))), "tier")
  expect_error(load_surveillance_codeset(write_cs(list(cs_row(match = "fuzzy")))), "match")
  expect_error(load_surveillance_codeset(write_cs(list(cs_row(type_filter = "PX_TYPE='CH'")))),
               "type_filter")
  expect_error(load_surveillance_codeset(write_cs(list(cs_row(),
                                                       cs_row(codeset_row_id = "SC002")))),
               "Duplicate")
  expect_error(load_surveillance_codeset(write_cs(list(cs_row(),
                                                       cs_row(codeset_row_id = "SC002",
                                                              code = "93307", code_norm = "93307")))),
               "unique")
  expect_error(load_surveillance_codeset(write_cs(list(cs_row(
    code = "6690-2", code_norm = "6690-2", cdm_table = "LAB_RESULT_CM",
    cdm_column = "LAB_LOINC", type_filter = "", match = "component_all_same_day",
    tier = "sensitivity")))), "component")
  tmp <- tempfile(fileext = ".xlsx")
  writexl::write_xlsx(list(Analysis_Codeset = data.frame(modality = "X")), tmp)
  expect_error(load_surveillance_codeset(tmp), "missing required columns")
})

test_that("surv_code_where builds normalized IN / LIKE clauses", {
  w <- surv_code_where("PX", exact = c("93306", "O'X"), prefix = "B24")
  expect_match(w, "REPLACE(UPPER(TRIM(PX)), '.', '') IN ('93306', 'O''X')", fixed = TRUE)
  expect_match(w, "LIKE 'B24%'", fixed = TRUE)
  expect_identical(surv_code_where("PX"), "FALSE")
})

dx <- function(ID, DX, DX_TYPE, DX_DATE = NA, ADMIT_DATE = NA)
  tibble::tibble(ID = ID, DX = DX, DX_TYPE = DX_TYPE,
                 DX_DATE = as.Date(DX_DATE), ADMIT_DATE = as.Date(ADMIT_DATE))

test_that("ICD-9 201.xx patient enters the denominator with the earliest date", {
  r <- hl_any_dx_from_tibble(dplyr::bind_rows(
    dx("P1", "201.50", "09", "2015-03-01"),
    dx("P1", "C81.10", "10", "2016-01-01")))
  expect_equal(r$hl_anchor_date[r$ID == "P1"], as.Date("2015-03-01"))
})

test_that("C81 with the wrong DX_TYPE is excluded; DX_TYPE whitespace tolerated", {
  r <- hl_any_dx_from_tibble(dplyr::bind_rows(
    dx("P2", "C81.0", "99", "2018-06-15"),
    dx("P3", "c81.90", "10 ", "2019-01-01")))
  expect_false("P2" %in% r$ID)
  expect_true("P3" %in% r$ID)
})

test_that("anchor falls back to ADMIT_DATE; no usable date gives NA", {
  r <- hl_any_dx_from_tibble(dplyr::bind_rows(
    dx("P4", "C81.1", "10", NA, "2020-02-02"),
    dx("P5", "C81.1", "10", NA, NA)))
  expect_equal(r$hl_anchor_date[r$ID == "P4"], as.Date("2020-02-02"))
  expect_true(is.na(r$hl_anchor_date[r$ID == "P5"]))
})
