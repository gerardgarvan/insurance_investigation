# Phase 159-01: codeset loader extensions, Lab_Analytes, Modalities
# Run from repo root: testthat::test_file("tests/testthat/test-159-codeset-loader.R")

repo_root <- testthat::test_path("..", "..")
if (!exists("load_lab_analytes"))
  source(file.path(repo_root, "R", "utils", "utils_surveillance.R"))
staged <- file.path(repo_root, "data", "reference", "surveillance_codeset.xlsx")

base_cs <- function(...) {
  utils::modifyList(list(
    codeset_row_id = "SC001", modality = "BMP", submodality = "",
    code_system = "ANALYTE", code = "SODIUM;POTASSIUM", code_norm = "SODIUM;POTASSIUM",
    cdm_table = "", cdm_column = "", type_filter = "", match = "analyte_all_same_day",
    tier = "primary", plausibility = "", min_analyte_count = ""), list(...))
}
base_la <- function(...) {
  utils::modifyList(list(
    analyte_row_id = "LA001", analyte = "SODIUM", code_system = "LOINC",
    code = "2951-2", code_norm = "2951-2", cdm_table = "LAB_RESULT_CM",
    type_filter = ""), list(...))
}
write_book <- function(cs_rows, la_rows = list(base_la(), base_la(analyte_row_id = "LA002",
                        analyte = "POTASSIUM", code = "2823-3", code_norm = "2823-3")),
                       mods = data.frame(modality = "BMP", column_prefix = "bmp",
                                         display_order = "1")) {
  tmp <- tempfile(fileext = ".xlsx")
  writexl::write_xlsx(list(
    Analysis_Codeset = dplyr::bind_rows(lapply(cs_rows, tibble::as_tibble)),
    Lab_Analytes     = dplyr::bind_rows(lapply(la_rows, tibble::as_tibble)),
    Modalities       = mods), tmp)
  tmp
}

test_that("staged codeset: Phase 158 rows intact, Phase 159 rows and sheets valid", {
  cs <- load_surveillance_codeset(staged)
  expect_true(all(vapply(cs, is.character, logical(1))))
  expect_equal(sum(startsWith(cs$codeset_row_id, "SC") &
                     as.integer(sub("SC", "", cs$codeset_row_id)) <= 108), 108L)
  for (m in c("BMP", "CMP", "LIPID", "LFT", "KIDNEY")) {
    r <- cs[cs$modality == m, ]
    expect_true(any(r$match == "exact"), info = m)
    expect_equal(sum(r$match == "analyte_all_same_day"), 1L, info = m)
    expect_equal(sum(r$match == "analyte_min_same_day"), 1L, info = m)
  }
  expect_equal(cs$min_analyte_count[cs$modality == "BMP" & cs$match == "analyte_min_same_day"], "4")
  kid_sens <- cs$code_norm[cs$modality == "KIDNEY" & cs$match == "analyte_min_same_day"]
  expect_false("CREATININE" %in% surv_components(kid_sens))   # review item 6
  # D-01 nesting: CMP panel 80053 under BMP, CMP, LFT, KIDNEY
  expect_setequal(cs$modality[cs$code_norm == "80053"], c("BMP", "CMP", "LFT", "KIDNEY"))

  la <- load_lab_analytes(staged, codeset = cs)
  expect_gt(nrow(la), 0)
  expect_false(anyDuplicated(la$analyte_row_id) > 0)
  expect_true(all(la$code_norm[la$code_system == "CPT"] %in% c(
    "82565", "82947", "82310", "84295", "84132", "82374", "82435", "84520", "82040",
    "84155", "84450", "84460", "84075", "82247", "82465", "83718", "84478", "82610")))
  expect_false(any(la$code_norm %in% c("2340-8", "11557-6", "5804-0")))  # strip, pCO2, UA dipstick

  lk <- load_modality_lookup(staged, codeset = cs)
  expect_setequal(names(lk), unique(cs$modality))
  expect_equal(unname(lk[c("Complete blood count", "Mammogram")]), c("cbc", "mammo"))
})

test_that("Phase 158-era files without min_analyte_count still load", {
  tmp <- tempfile(fileext = ".xlsx")
  row <- base_cs(code_system = "CPT", code = "93306", code_norm = "93306",
                 cdm_table = "PROCEDURES", cdm_column = "PX", type_filter = "CH",
                 match = "exact", modality = "Echocardiogram")
  row$min_analyte_count <- NULL
  writexl::write_xlsx(list(Analysis_Codeset = tibble::as_tibble(row)), tmp)
  expect_equal(load_surveillance_codeset(tmp)$min_analyte_count, "")
})

test_that("numeric panel CPT cell reads back as text", {
  df <- tibble::as_tibble(base_cs(code_system = "CPT", cdm_table = "PROCEDURES",
                                  cdm_column = "PX", type_filter = "CH", match = "exact"))
  df$code <- 80048; df$code_norm <- 80048
  tmp <- tempfile(fileext = ".xlsx")
  writexl::write_xlsx(list(Analysis_Codeset = df), tmp)
  expect_identical(load_surveillance_codeset(tmp)$code_norm, "80048")
})

test_that("rule rows: all and min rows may share modality x code_norm", {
  cs <- load_surveillance_codeset(write_book(list(
    base_cs(),
    base_cs(codeset_row_id = "SC002", match = "analyte_min_same_day",
            tier = "sensitivity", min_analyte_count = "1"))))
  expect_equal(nrow(cs), 2L)
})

test_that("loader rejects bad rule rows", {
  expect_error(load_surveillance_codeset(write_book(list(base_cs(cdm_table = "LAB_RESULT_CM")))),
               "blank cdm_table")
  expect_error(load_surveillance_codeset(write_book(list(base_cs(min_analyte_count = "1")))),
               "must be blank")
  for (k in c("2", "0", "1.5", "x", "")) {
    expect_error(load_surveillance_codeset(write_book(list(base_cs(
      match = "analyte_min_same_day", tier = "sensitivity", min_analyte_count = k)))),
      "min_analyte_count", info = k)
  }
})

test_that("Lab_Analytes validation", {
  cs <- load_surveillance_codeset(write_book(list(base_cs(code = "SODIUM;MAGNESIUM",
                                                          code_norm = "SODIUM;MAGNESIUM"))))
  expect_error(load_lab_analytes(write_book(list(base_cs())), codeset = cs),
               "MAGNESIUM not found in Lab_Analytes")
  dup <- list(base_la(), base_la(analyte_row_id = "LA002"))
  expect_error(load_lab_analytes(write_book(list(base_cs()), la_rows = dup)), "duplicate")
  expect_error(load_lab_analytes(write_book(list(base_cs()),
                                            la_rows = list(base_la(cdm_table = "DIAGNOSIS")))),
               "cdm_table")
  expect_error(load_lab_analytes(write_book(list(base_cs()),
                                            la_rows = list(base_la(cdm_table = "PROCEDURES",
                                                                   type_filter = "PX_TYPE='CH'")))),
               "type_filter")
})

test_that("Modalities sheet must cover every codeset modality", {
  cs <- load_surveillance_codeset(write_book(list(base_cs())))
  p <- write_book(list(base_cs()), mods = data.frame(modality = "CMP", column_prefix = "cmp",
                                                     display_order = "1"))
  expect_error(load_modality_lookup(p, codeset = cs), "missing codeset modalities: BMP")
  p2 <- write_book(list(base_cs()), mods = data.frame(modality = "BMP", column_prefix = "B MP",
                                                      display_order = "1"))
  expect_error(load_modality_lookup(p2), "column_prefix")
})
