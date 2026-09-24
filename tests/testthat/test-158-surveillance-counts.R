# Phase 158-02: matching, presence, follow-up, window, frequency, suppression
# Run from repo root: testthat::test_file("tests/testthat/test-158-surveillance-counts.R")

repo_root <- testthat::test_path("..", "..")
if (!exists("match_coded_events"))
  source(file.path(repo_root, "R", "utils", "utils_surveillance.R"))

d <- as.Date
cs <- tibble::tribble(
  ~codeset_row_id, ~modality,           ~submodality, ~code_norm,           ~cdm_table,      ~type_filter, ~match,                   ~tier,
  "SC01", "Echocardiogram",    "",        "93306",              "PROCEDURES",    "CH", "exact",                  "primary",
  "SC02", "Echocardiogram",    "",        "93350",              "PROCEDURES",    "CH", "exact",                  "primary",
  "SC03", "Stress test",       "",        "93350",              "PROCEDURES",    "CH", "exact",                  "primary",
  "SC04", "Echocardiogram",    "",        "B24",                "PROCEDURES",    "10", "prefix",                 "primary",
  "SC05", "Electrocardiogram", "",        "93000",              "PROCEDURES",    "CH", "exact",                  "primary",
  "SC06", "Electrocardiogram", "",        "93010",              "PROCEDURES",    "CH", "exact",                  "primary",
  "SC07", "Echocardiogram",    "",        "Z136",               "DIAGNOSIS",     "10", "exact",                  "sensitivity",
  "SC08", "Thyroid function",  "TSH",     "84443",              "PROCEDURES",    "CH", "exact",                  "primary",
  "SC09", "Thyroid function",  "TSH",     "3016-3",             "LAB_RESULT_CM", "",   "exact",                  "primary",
  "SC10", "Thyroid function",  "Free T4", "3024-7",             "LAB_RESULT_CM", "",   "exact",                  "primary",
  "SC11", "Complete blood count", "",     "6690-2;718-7;777-3", "LAB_RESULT_CM", "",   "component_all_same_day", "sensitivity",
  "SC12", "Mammogram",         "",        "77055",              "PROCEDURES",    "CH", "exact",                  "primary"
)

raw <- tibble::tribble(
  ~ID,  ~code_raw,  ~type_val, ~event_date,        ~source_table,
  "P1", "93000",    "CH",      d("2021-03-01"),    "PROCEDURES",   # ECG pro+tech same day
  "P1", "93010",    "CH",      d("2021-03-01"),    "PROCEDURES",
  "P1", "93350",    "CH",      d("2021-04-01"),    "PROCEDURES",   # stress echo -> 2 modalities
  "P1", "B246ZZZ",  "10",      d("2021-05-01"),    "PROCEDURES",   # prefix hit
  "P2", "93306",    "C4",      d("2021-06-01"),    "PROCEDURES",   # legacy PX_TYPE: not counted
  "P2", "93306",    "CH",      d("2021-07-01"),    "PROCEDURES",
  "P2", "Z13.6",    "10",      d("2021-07-01"),    "DIAGNOSIS",    # sensitivity, same day as primary
  "P3", "Z13.6",    "10",      d("2021-08-01"),    "DIAGNOSIS",    # sensitivity only
  "P1", "84443",    "CH",      d("2021-09-01"),    "PROCEDURES",
  "P1", "3024-7",   "",        d("2021-09-01"),    "LAB_RESULT_CM" # TSH + FT4 same day
)

lab <- tibble::tribble(
  ~ID,  ~code_raw, ~event_date,
  "P1", "6690-2",  d("2021-10-01"),
  "P1", "718-7",   d("2021-10-01"),
  "P1", "777-3",   d("2021-10-01"),
  "P2", "6690-2",  d("2021-10-02"),
  "P2", "718-7",   d("2021-10-02")
)

matched <- match_coded_events(raw, cs)
comp    <- build_component_events(lab, cs)
all_ev  <- dplyr::bind_rows(matched, comp$events)

test_that("A_code_presence: one row per codeset row, from pre-dedup events", {
  A <- build_code_presence(cs, all_ev)
  expect_equal(nrow(A), nrow(cs))
  expect_true(all(A$present[A$codeset_row_id %in% c("SC05", "SC06")]))  # both ECG codes survive
  expect_true(A$present[A$codeset_row_id == "SC04"])                    # prefix row joins by row id
  expect_true(all(A$present[A$codeset_row_id %in% c("SC02", "SC03")]))  # dual-modality
  expect_false(A$present[A$codeset_row_id == "SC12"])                   # zero-count row kept
  sc01 <- A[A$codeset_row_id == "SC01", ]
  expect_equal(sc01$n_records, 1L)                                      # C4 row excluded ...
  expect_equal(sc01$n_records_other_type, 1L)                           # ... but reported
  expect_equal(sc01$other_types, "C4")
  expect_equal(A$n_records[A$codeset_row_id == "SC11"], 1L)             # 1 qualifying CBC day
})

test_that("component rule: all components required; partial days reported", {
  expect_equal(nrow(comp$events), 1L)
  expect_equal(comp$events$ID, "P1")
  expect_equal(comp$near_miss$n_partial_id_dates, 1L)
})

denom <- tibble::tibble(ID = c("P1", "P2", "P3", "P4"),
                        hl_anchor_date = d(c("2021-03-01", "2021-01-01", "2021-01-01", "2021-01-01")),
                        in_confirmed_cohort = c(TRUE, TRUE, FALSE, FALSE))
last_enc <- tibble::tibble(ID = c("P1", "P2", "P3"),
                           last_enc_date = d(c("2021-12-31", "2021-12-31", "2021-01-01")))
death <- tibble::tibble(ID = c("P2", "P2"), death_date = d(c("2021-09-30", "2021-11-30")))
fu <- compute_followup(denom, last_enc, death, cutoff = d("2025-09-15"))

test_that("follow-up: earliest death wins, zero and missing follow-up flagged", {
  expect_equal(nrow(fu), 4L)                                  # no fan-out from 2 DEATH rows
  expect_equal(fu$follow_end[fu$ID == "P2"], d("2021-09-30"))
  expect_equal(fu$fu_status[fu$ID == "P3"], "zero_or_negative")
  expect_equal(fu$fu_status[fu$ID == "P4"], "no_followup_date")
  expect_equal(fu$person_years[fu$ID %in% c("P3", "P4")], c(0, 0))
})

win <- classify_event_window(all_ev, fu)

test_that("window: anchor day is pre by default; after follow-up excluded", {
  ecg <- win[win$codeset_row_id == "SC05", ]
  expect_equal(ecg$window, "pre")                              # 2021-03-01 == P1 anchor
  expect_equal(classify_event_window(all_ev, fu, anchor_day_is_post = TRUE) |>
                 dplyr::filter(codeset_row_id == "SC05") |> dplyr::pull(window), "post")
  expect_equal(win$window[win$ID == "P2" & win$codeset_row_id == "SC01" & win$type_ok], "post")
  expect_equal(unique(win$window[win$ID == "P3"]), "after_followup")  # P3 follow-up ended at anchor
})

keys <- dplyr::distinct(cs, modality)

test_that("frequency counts patients, not events; PY pooled over whole denominator", {
  B <- compute_modality_stats(win, fu, keys, tiers = "primary")
  expect_equal(nrow(B), nrow(keys))
  echo <- B[B$modality == "Echocardiogram", ]
  expect_equal(echo$n_patients, 2L)                          # P1 (93350, B24), P2 (93306)
  expect_equal(echo$total_event_dates, 3L)
  expect_equal(echo$events_per_person_year, 3 / sum(fu$person_years))
  expect_equal(echo$pct_of_denominator, 100 * 2 / 4)
  expect_equal(B$n_patients[B$modality == "Electrocardiogram"], 0L)  # anchor-day ECG is pre
  expect_equal(B$n_patients[B$modality == "Mammogram"], 0L)
})

test_that("primary <= any <= denominator; sensitivity-only patient appears only in any", {
  P  <- compute_modality_stats(win, fu, keys, tiers = "primary")
  A  <- compute_modality_stats(win, fu, keys, tiers = c("primary", "sensitivity"))
  expect_true(all(P$n_patients <= A$n_patients))
  expect_true(all(A$n_patients <= nrow(fu)))
  echo_any <- A[A$modality == "Echocardiogram", ]
  expect_equal(echo_any$n_patients, 2L)                      # P3 Z13.6 is after follow-up
  expect_equal(echo_any$total_event_dates, 3L)               # P2 7/1 primary+sens = one date
})

test_that("submodality sub-counts use the same grain and are not additive", {
  sk <- cs |> dplyr::filter(submodality != "") |> dplyr::distinct(modality, submodality)
  S  <- compute_modality_stats(win, fu, sk, tiers = "primary", by = c("modality", "submodality"))
  P  <- compute_modality_stats(win, fu, keys, tiers = "primary")
  expect_equal(S$n_patients[S$submodality == "TSH"], 1L)     # CPT 84443 counted as TSH
  expect_equal(S$n_patients[S$submodality == "Free T4"], 1L)
  expect_equal(P$total_event_dates[P$modality == "Thyroid function"], 1L)  # same day = 1
})

test_that("patient-level output is one row per ID x modality", {
  pm <- build_patient_modality(win, fu)
  expect_false(anyDuplicated(pm[, c("ID", "modality")]) > 0)
  p1 <- pm[pm$ID == "P1" & pm$modality == "Electrocardiogram", ]
  expect_equal(p1$n_dates_pre_any, 1L)
  expect_equal(p1$n_dates_post_any, 0L)
})

test_that("suppression masks 1-10 and blanks derived columns", {
  df <- tibble::tibble(n_patients = c(0L, 5L, 25L), pct = c(0, 1.2, 6))
  s  <- suppress_table(df, list(n_patients = "pct"))
  expect_equal(s$n_patients, c("0", "<11", "25"))
  expect_equal(s$pct, c("0", "", "6"))
})
