# Phase 159-02: analyte mapping, rule events, A2 presence, per-patient table
# Run from repo root: testthat::test_file("tests/testthat/test-159-analyte-rules.R")

repo_root <- testthat::test_path("..", "..")
if (!exists("build_analyte_events"))
  source(file.path(repo_root, "R", "utils", "utils_surveillance.R"))

d <- as.Date
BMP8  <- c("SODIUM", "POTASSIUM", "CHLORIDE", "CO2", "BUN", "CREATININE", "GLUCOSE", "CALCIUM")
CMP14 <- c(BMP8, "ALBUMIN", "TOTAL_PROTEIN", "ALP", "ALT", "AST", "TOTAL_BILIRUBIN")
LFT4  <- c("ALT", "AST", "ALP", "TOTAL_BILIRUBIN")
KSENS <- c("EGFR", "CYSTATIN_C", "URINE_ALBUMIN_CREATININE_RATIO", "URINE_PROTEIN")
rule <- function(id, mod, an, match, tier, k = "")
  tibble::tibble(codeset_row_id = id, modality = mod, submodality = "",
                 code_norm = paste(an, collapse = ";"), cdm_table = "", type_filter = "",
                 match = match, tier = tier, min_analyte_count = k)
cs <- dplyr::bind_rows(
  tibble::tibble(codeset_row_id = c("SC901", "SC902", "SC903"),
                 modality = c("BMP", "CMP", "KIDNEY"), submodality = "",
                 code_norm = "80053", cdm_table = "PROCEDURES", type_filter = "CH",
                 match = "exact", tier = "primary", min_analyte_count = ""),
  rule("SC910", "BMP", BMP8, "analyte_all_same_day", "primary"),
  rule("SC911", "BMP", BMP8, "analyte_min_same_day", "sensitivity", "4"),
  rule("SC920", "CMP", CMP14, "analyte_all_same_day", "primary"),
  rule("SC921", "CMP", CMP14, "analyte_min_same_day", "sensitivity", "7"),
  rule("SC930", "LFT", LFT4, "analyte_all_same_day", "primary"),
  rule("SC931", "LFT", LFT4, "analyte_min_same_day", "sensitivity", "2"),
  rule("SC940", "KIDNEY", "CREATININE", "analyte_all_same_day", "primary"),
  rule("SC941", "KIDNEY", KSENS, "analyte_min_same_day", "sensitivity", "1"))

analytes <- tibble::tribble(
  ~analyte_row_id, ~analyte, ~cdm_table, ~code_norm, ~type_filter,
  "LA01", "CREATININE", "LAB_RESULT_CM", "2160-0", "",
  "LA02", "CREATININE", "PROCEDURES",    "82565",  "CH",
  "LA03", "CREATININE", "LAB_RESULT_CM", "38483-4", "",
  "LA04", "EGFR",       "LAB_RESULT_CM", "62238-1", "")

hit <- function(ID, an, date) tibble::tibble(ID = ID, analyte_row_id = paste0("LA_", an),
                                             analyte = an, event_date = d(date),
                                             type_ok = TRUE, type_val = "")
hits <- dplyr::bind_rows(
  hit("P01", CMP14, "2021-03-01"),                 # full CMP by components
  hit("P02", BMP8[1:7], "2021-06-15"),             # 7 of 8 BMP
  hit("P04", c("SODIUM", "GLUCOSE"), "2021-07-01"),# 2 of 8: neither tier
  hit("P05", "EGFR", "2021-08-01"),                # kidney sensitivity only
  hit("P01", "CREATININE", "2021-03-01"))          # duplicate analyte, 2nd source

ae <- build_analyte_events(hits, cs)
ev_for <- function(id, row) ae$events[ae$events$ID == id & ae$events$codeset_row_id == row, ]

test_that("map_analyte_hits joins on table + code and checks PX_TYPE", {
  raw <- tibble::tribble(
    ~ID,   ~code_raw, ~type_val, ~event_date,      ~cdm_table,
    "P01", "2160-0",  "",        d("2021-01-01"),  "LAB_RESULT_CM",
    "P01", "82565",   "CH",      d("2021-01-01"),  "PROCEDURES",
    "P02", "82565",   "C4",      d("2021-01-02"),  "PROCEDURES",
    "P03", "82565",   "",        d("2021-01-03"),  "LAB_RESULT_CM")   # wrong table: no match
  m <- map_analyte_hits(raw, analytes)
  expect_equal(nrow(m), 3L)
  expect_equal(m$type_ok[m$ID == "P02"], FALSE)
  expect_true(all(m$analyte == "CREATININE"))
})

test_that("full CMP day qualifies CMP, BMP, LFT and KIDNEY rules (D-01 nesting)", {
  for (r in c("SC910", "SC920", "SC930", "SC940")) expect_equal(nrow(ev_for("P01", r)), 1L, info = r)
})

test_that("7 of 8 BMP analytes is sensitivity, not primary; 2 of 8 is neither", {
  expect_equal(nrow(ev_for("P02", "SC910")), 0L)
  expect_equal(nrow(ev_for("P02", "SC911")), 1L)
  expect_equal(nrow(ev_for("P04", "SC911")), 0L)
})

test_that("the same analyte from two sources counts once", {
  nm <- ae$near_miss
  expect_equal(nm$n_id_dates[nm$codeset_row_id == "SC920" & nm$n_analytes_present == 14], 1L)
  expect_equal(nrow(ev_for("P01", "SC940")), 1L)
})

test_that("kidney sensitivity: eGFR alone qualifies; creatinine is not in the sensitivity list", {
  expect_equal(nrow(ev_for("P05", "SC941")), 1L)
  expect_equal(nrow(ev_for("P01", "SC941")), 0L)
  expect_equal(nrow(ev_for("P05", "SC940")), 0L)
})

test_that("near-miss table: long format, no zero-analyte rows, qualifies flag", {
  nm <- ae$near_miss
  expect_false(any(nm$n_analytes_present == 0))
  b <- nm[nm$codeset_row_id == "SC910", ]
  expect_equal(b$n_id_dates[b$n_analytes_present == 7], 1L)
  expect_false(b$qualifies[b$n_analytes_present == 7])
  expect_true(all(nm$qualifies == (nm$n_analytes_present >= nm$threshold)))
})

test_that("events have the standard schema and flow through Phase 158 functions", {
  expect_true(all(c("codeset_row_id", "type_ok", "code_data", "source_table",
                    "submodality") %in% names(ae$events)))
  fu <- tibble::tibble(ID = c("P01", "P02", "P03", "P04", "P05"),
                       hl_anchor_date = d("2020-01-01"), follow_end = d("2022-12-31"),
                       person_years = 3, in_confirmed_cohort = TRUE)
  coded <- tibble::tibble(codeset_row_id = "SC901", ID = "P03", code_data = "80053",
                          type_val = "CH", event_date = d("2021-09-01"),
                          source_table = "PROCEDURES", modality = "BMP",
                          submodality = "", tier = "primary", type_ok = TRUE)
  all_ev <- dplyr::bind_rows(coded, ae$events)
  A <- build_code_presence(cs, all_ev)
  expect_equal(nrow(A), nrow(cs))
  expect_true(A$present[A$codeset_row_id == "SC910"])
  expect_false(A$present[A$codeset_row_id == "SC902"])
  win <- classify_event_window(all_ev, fu)
  B <- compute_modality_stats(win, fu, dplyr::distinct(cs, modality), tiers = "primary")
  expect_equal(B$n_patients[B$modality == "BMP"], 2L)          # P01 components, P03 panel

  lookup <- c(BMP = "bmp", CMP = "cmp", LFT = "lft", KIDNEY = "kidney", Mammogram = "mammo")
  pw <- build_patient_modality_dates(win, fu, lookup)
  expect_equal(nrow(pw), nrow(fu))
  expect_equal(pw$n_dates_bmp[pw$ID == "P02"], 0L)
  expect_equal(pw$n_dates_bmp_any[pw$ID == "P02"], 1L)
  expect_identical(pw$n_dates_mammo, rep(0L, 5))                # modality with no events
  expect_identical(names(pw)[6:9], c("n_dates_bmp", "n_dates_bmp_any", "n_dates_cmp", "n_dates_cmp_any"))
  expect_true(all(pw$n_dates_bmp <= pw$n_dates_bmp_any))
  expect_true(all(pw$n_dates_cmp <= pw$n_dates_bmp))
  expect_equal(sum(pw$n_dates_bmp > 0), B$n_patients[B$modality == "BMP"])
  expect_error(build_patient_modality_dates(win, fu, lookup[-1]), "without a column prefix")
})

test_that("pre-anchor and after-follow-up events are not counted", {
  fu <- tibble::tibble(ID = "P01", hl_anchor_date = d("2021-03-01"), follow_end = d("2022-01-01"),
                       person_years = 1, in_confirmed_cohort = TRUE)
  win <- classify_event_window(ae$events, fu)                    # P01 events are on the anchor day
  pw <- build_patient_modality_dates(win, fu, c(BMP = "bmp", CMP = "cmp", LFT = "lft", KIDNEY = "kidney"))
  expect_equal(pw$n_dates_bmp, 0L)
})

test_that("A2 presence is per Lab_Analytes row", {
  h <- tibble::tribble(
    ~ID,   ~analyte_row_id, ~analyte,     ~event_date,     ~type_ok, ~type_val,
    "P01", "LA01",          "CREATININE", d("2021-01-01"), TRUE,     "",
    "P02", "LA01",          "CREATININE", d("2021-01-02"), TRUE,     "",
    "P02", "LA02",          "CREATININE", d("2021-01-02"), FALSE,    "C4")
  A2 <- build_analyte_presence(analytes, h)
  expect_equal(nrow(A2), nrow(analytes))
  expect_equal(A2$n_results[A2$analyte_row_id == "LA01"], 2L)
  expect_false(A2$present[A2$analyte_row_id == "LA02"])
  expect_equal(A2$n_results_other_type[A2$analyte_row_id == "LA02"], 1L)
  expect_false(A2$present[A2$analyte_row_id == "LA03"])
})
