# Phase 160-02: A3 diagnostic, eligible-sex statistics, suppression, codeset summary
# Run from repo root: testthat::test_file("tests/testthat/test-160-diagnostic-and-eligibility.R")

repo_root <- testthat::test_path("..", "..")
if (!exists("summarise_missing_analyte"))
  source(file.path(repo_root, "R", "utils", "utils_surveillance.R"))

d <- as.Date
BMP8 <- c("SODIUM", "POTASSIUM", "CHLORIDE", "CO2", "BUN", "CREATININE", "GLUCOSE", "CALCIUM")
rule <- function(id, mod, an, match, tier, k = "")
  tibble::tibble(codeset_row_id = id, modality = mod, submodality = "", code = paste(an, collapse = ";"),
                 code_norm = paste(an, collapse = ";"), cdm_table = "", type_filter = "",
                 match = match, tier = tier, min_analyte_count = k)
cs <- dplyr::bind_rows(
  rule("SC125", "BMP", BMP8, "analyte_all_same_day", "primary"),
  rule("SC126", "BMP", BMP8, "analyte_min_same_day", "sensitivity", "4"),
  rule("SC166", "KIDNEY", "CREATININE", "analyte_all_same_day", "primary"),
  rule("SC167", "KIDNEY", c("EGFR", "CYSTATIN_C"), "analyte_min_same_day", "sensitivity", "1"))
hit <- function(ID, an, date) tibble::tibble(ID = ID, analyte_row_id = "x", analyte = an,
                                             event_date = d(date), type_ok = TRUE, type_val = "")
no_co2 <- setdiff(BMP8, "CO2")
hits <- dplyr::bind_rows(
  hit("P1", no_co2, "2019-05-01"), hit("P1", no_co2, "2019-05-01"),   # duplicate rows, one day
  hit("P2", no_co2, "2020-02-02"),
  hit("P3", setdiff(BMP8, "CALCIUM"), "2020-03-03"),
  hit("P4", BMP8, "2020-04-04"), hit("P5", BMP8, "2021-01-01"),       # complete days
  hit("P6", BMP8[1:5], "2021-02-02"),                                  # 5 of 8: neither
  hit("P7", "EGFR", "2021-03-03"))

sm <- summarise_missing_analyte(hits, cs)

test_that("block 1: n-1 days attributed to the missing analyte, at ID x date grain", {
  o <- sm$overall
  expect_equal(o$n_id_dates[o$missing_analyte == "CO2"], 2L)
  expect_equal(o$n_id_dates[o$missing_analyte == "CALCIUM"], 1L)
  expect_equal(sum(o$n_id_dates), 3L)
  ne <- build_analyte_events(hits, cs)$near_miss
  expect_equal(sum(o$n_id_dates),
               ne$n_id_dates[ne$codeset_row_id == "SC125" & ne$n_analytes_present == 7])
})

test_that("block 1: only analyte_all_same_day rules with >= 2 analytes", {
  expect_setequal(unique(sm$overall$codeset_row_id), "SC125")
  expect_false(any(sm$days$codeset_row_id %in% c("SC126", "SC166", "SC167")))
})

test_that("block 1: by-year totals sum to overall; complete days kept as comparison group", {
  expect_equal(sum(sm$by_year$n_id_dates), sum(sm$overall$n_id_dates))
  expect_setequal(sm$by_year$calendar_year[sm$by_year$missing_analyte == "CO2"], c(2019L, 2020L))
  cmp <- sm$days[sm$days$day_type == "complete", ]
  expect_setequal(cmp$ID, c("P4", "P5"))
  expect_true(all(is.na(cmp$missing_analyte)))
})

test_that("sampling: one day per patient per group, capped, and order-independent", {
  many <- tibble::tibble(codeset_row_id = "SC125", modality = "BMP",
                         ID = rep(sprintf("Q%02d", 1:30), each = 2),
                         event_date = rep(d(c("2020-01-01", "2020-06-01")), 30),
                         day_type = "near_miss", missing_analyte = "CO2")
  s1 <- select_a3_sample(many, n_max = 10, seed = 7)
  s2 <- select_a3_sample(many[sample(nrow(many)), ], n_max = 10, seed = 7)
  expect_equal(nrow(s1), 10L)
  expect_false(anyDuplicated(s1$ID) > 0)
  expect_identical(s1, s2)
})

test_that("SQL date expression per dialect", {
  expect_identical(surv_sql_date_expr("RESULT_DATE", "sqlite"), "DATE(RESULT_DATE)")
  x <- surv_sql_date_expr(c("RESULT_DATE", "SPECIMEN_DATE"), "duckdb")
  expect_match(x, "^COALESCE\\(COALESCE\\(TRY_CAST")
  expect_match(x, "%m/%d/%Y", fixed = TRUE)
})

samp <- tibble::tribble(
  ~codeset_row_id, ~modality, ~ID,  ~event_date,      ~day_type,   ~missing_analyte,
  "SC125",         "BMP",     "N1", d("2020-01-01"),  "near_miss", "CO2",
  "SC125",         "BMP",     "N2", d("2020-01-02"),  "near_miss", "CO2",
  "SC125",         "BMP",     "N3", d("2020-01-03"),  "near_miss", "CO2",
  "SC125",         "BMP",     "N4", d("2020-01-04"),  "near_miss", "CO2",
  "SC125",         "BMP",     "C1", d("2020-02-01"),  "complete",  NA,
  "SC125",         "BMP",     "C2", d("2020-02-02"),  "complete",  NA)
cand_row <- function(ID, date, loinc = NA, raw = NA, name = NA)
  tibble::tibble(ID = ID, event_date = d(date), LAB_LOINC = loinc, LAB_PX = NA_character_,
                 LAB_PX_TYPE = NA_character_, RAW_LAB_CODE = raw, RAW_LAB_NAME = name, RESULT_UNIT = "mmol/L")
cands <- dplyr::bind_rows(
  # replacement CO2 code: every near-miss day, no complete day
  cand_row(c("N1", "N2", "N3", "N4"), c("2020-01-01", "2020-01-02", "2020-01-03", "2020-01-04"),
           loinc = "57922-7", name = "CO2 CALC"),
  # hemoglobin: on every day of both kinds
  cand_row(c("N1", "N2", "N3", "N4", "C1", "C2"),
           c("2020-01-01", "2020-01-02", "2020-01-03", "2020-01-04", "2020-02-01", "2020-02-02"),
           loinc = "718-7", name = "HGB"),
  # a Lab_Analytes code: never a candidate
  cand_row("N1", "2020-01-01", loinc = "2951-2"),
  # site-local code with no LOINC, on 2 near-miss days
  cand_row(c("N1", "N2"), c("2020-01-01", "2020-01-02"), raw = "LOC123", name = "TCO2 LOCAL"),
  # a row on a day that was not sampled
  cand_row("N1", "2020-05-05", loinc = "99999-9"))
analytes <- tibble::tibble(analyte_row_id = "LA001", analyte = "SODIUM", code_norm = "2951-2")
excluded <- tibble::tibble(code = "57922-7", reason = "calculated from blood gas")
rk <- rank_candidate_codes(cands, samp, analytes, excluded, master_codes = c("57922-7", "718-7"))

test_that("block 2: contrast ranking puts the replacement code first, routine labs last", {
  expect_equal(rk$code_norm[1], "57922-7")
  expect_equal(rk$coverage_near[1], 1)
  expect_equal(rk$coverage_control[1], 0)
  expect_equal(rk$lift[rk$code_norm == "718-7"], 0)
  expect_gt(match("718-7", rk$code_norm), match("LOC123", rk$code_norm))
})

test_that("block 2: Lab_Analytes codes dropped; excluded, MASTER and RAW sources flagged", {
  expect_false(any(rk$code_norm %in% c("2951-2", "99999-9")))
  top <- rk[1, ]
  expect_true(top$in_excluded)
  expect_equal(top$excluded_reason, "calculated from blood gas")
  expect_true(top$in_master)
  expect_equal(top$top_raw_name, "CO2 CALC")
  loc <- rk[rk$code_norm == "LOC123", ]
  expect_equal(loc$code_source, "RAW")
  expect_false(loc$in_master)
  expect_equal(loc$n_near_sampled, 4L)
  expect_equal(loc$n_control_sampled, 2L)
})

fu <- tibble::tibble(ID = c("F1", "F2", "F3", "M1", "M2", "U1"),
                     hl_anchor_date = d("2020-01-01"), follow_end = d("2022-01-01"),
                     person_years = c(2, 2, 2, 1, 1, 1), in_confirmed_cohort = TRUE)
sex <- tibble::tibble(ID = c("F1", "F2", "F3", "M1", "M2"), sex = c("F", "F", "F", "M", " m "))
ev <- tibble::tribble(
  ~ID,  ~modality,    ~tier,     ~window, ~type_ok, ~event_date,
  "F1", "Mammogram",  "primary", "post",  TRUE,     d("2020-06-01"),
  "F1", "Mammogram",  "primary", "post",  TRUE,     d("2021-06-01"),
  "F2", "Mammogram",  "primary", "post",  TRUE,     d("2020-07-01"),
  "M1", "Mammogram",  "primary", "post",  TRUE,     d("2020-08-01"),
  "U1", "Mammogram",  "primary", "post",  TRUE,     d("2020-09-01"),
  "F1", "BMP",        "primary", "post",  TRUE,     d("2020-06-01"))
keys <- tibble::tibble(modality = "Mammogram")
es <- compute_eligible_modality_stats(ev, fu, keys, "primary", sex, "F")
plain <- compute_modality_stats(ev, fu, keys, "primary")

test_that("eligible view: female denominator and person-years; all-patient columns identical", {
  expect_equal(es$n_patients_eligible, 2L)
  expect_equal(es$denominator_eligible, 3L)
  expect_equal(es$pct_of_eligible, 100 * 2 / 3)
  expect_equal(es$person_years_eligible, 6)
  expect_equal(es$events_per_person_year_eligible, 3 / 6)
  expect_identical(es[, names(plain)], plain)
})

test_that("male and unknown-sex events stay visible in other-sex columns", {
  expect_equal(es$n_patients, 4L)                       # all-patient count includes M1 and U1
  expect_equal(es$n_patients_other_sex, 2L)             # M1 + U1 (not in DEMOGRAPHIC)
  expect_equal(es$total_event_dates_other_sex, 2L)
  expect_equal(es$n_patients_eligible + es$n_patients_other_sex, es$n_patients)
})

test_that("blank eligible_sex returns plain stats; zero eligible denominator gives NA pct", {
  expect_identical(compute_eligible_modality_stats(ev, fu, keys, "primary", sex, ""), plain)
  none <- compute_eligible_modality_stats(ev, fu, keys, "primary",
                                          dplyr::mutate(sex, sex = "M"), "F")
  expect_true(is.na(none$pct_of_eligible))
  expect_equal(none$denominator_eligible, 0L)
})

test_that("complementary suppression withholds both sides when either is small", {
  df <- tibble::tibble(n_patients = c(500L, 40L), n_patients_eligible = c(495L, 25L),
                       pct_of_eligible = c(10, 5), n_patients_other_sex = c(5L, 15L),
                       total_event_dates_eligible = c(900L, 60L),
                       events_per_person_year_eligible = c(0.2, 0.1),
                       total_event_dates_other_sex = c(8L, 30L))
  s <- suppress_eligible_columns(df)
  expect_equal(s$n_patients_other_sex, c("<11", "15"))
  expect_equal(s$n_patients_eligible, c("", "25"))      # 495 = 500 - 5 would reveal the 5
  expect_equal(s$pct_of_eligible, c("", "5"))
  expect_equal(s$total_event_dates_eligible, c("", "60"))
  expect_equal(s$events_per_person_year_eligible, c("", "0.1"))
  p <- suppress_eligible_columns(dplyr::rename_with(df, ~ paste0("primary_", .x)), prefix = "primary_")
  expect_equal(p$primary_n_patients_eligible, c("", "25"))
})

test_that("codeset summary: modality x tier x match block and analyte block", {
  cs2 <- dplyr::bind_rows(cs, tibble::tibble(codeset_row_id = c("SC001", "SC002"),
                                             modality = "Mammogram", submodality = "",
                                             code = c("77067", "77066"), code_norm = c("77067", "77066"),
                                             match = "exact", tier = "primary", min_analyte_count = ""))
  an <- tibble::tibble(analyte_row_id = c("LA1", "LA2", "LA3"), analyte = c("CO2", "CO2", "SODIUM"),
                       code = c("2028-9", "1963-8", "2951-2"), code_norm = c("2028-9", "1963-8", "2951-2"))
  pres <- dplyr::mutate(an, present = c(TRUE, FALSE, TRUE))
  sm2 <- build_codeset_summary(cs2, an, pres)
  m <- sm2$by_modality
  expect_equal(m$n_codes[m$modality == "Mammogram"], 2L)
  expect_equal(m$codes[m$modality == "Mammogram"], "77066; 77067")
  expect_equal(m$threshold[m$modality == "BMP" & m$match == "analyte_min_same_day"],
               ">= 4 listed analytes")
  expect_equal(m$threshold[m$modality == "BMP" & m$match == "analyte_all_same_day"], "all listed")
  a <- sm2$by_analyte
  expect_equal(a$n_codes[a$analyte == "CO2"], 2L)
  expect_equal(a$n_codes_present[a$analyte == "CO2"], 1L)
})
