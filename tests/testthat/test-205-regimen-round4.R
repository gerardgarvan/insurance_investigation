# ==============================================================================
# test-205-regimen-round4.R -- Phase 205 fix round 4
# ==============================================================================
# Coverage: exact CHOP/BEACOPP drug sets, immunotherapy-alone labels + LOT,
# episode-anchored BV+AVD / Nivo+AVD rule, ABVD_PLUS plus-agent / supportive rule.
# ==============================================================================

{
  want <- c("REGIMEN_DICT", "BEAM_SCT_WINDOW_DAYS", "LOT_GAP_DAYS",
            "MAINTENANCE_DRUG_CLASSES", "CONCURRENCY_WINDOW_DAYS",
            "BV_CONSOLIDATION_SCT_WINDOW_DAYS", "SUPPORTIVE_AGENTS")
  for (e in parse(here::here("R", "00_config.R"))) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) &&
        is.name(e[[2]]) && as.character(e[[2]]) %in% want) {
      eval(e, envir = environment())
    }
  }
}
if (!exists("SUPPORTIVE_AGENTS") || is.null(REGIMEN_DICT[["PD-1 mono"]])) {
  skip("round-4 config entries not found in R/00_config.R")
}

if (!exists("LOT_GAP_DAYS"))             LOT_GAP_DAYS <- 90L
if (!exists("MAINTENANCE_DRUG_CLASSES")) MAINTENANCE_DRUG_CLASSES <- c("BV_consolidation", "Rituximab_mono")
if (!exists("CONCURRENCY_WINDOW_DAYS"))  CONCURRENCY_WINDOW_DAYS <- 7L

rows <- function(drugs, type = "Chemotherapy", ep = 1L, date = "2022-01-01", id = "P001") {
  tibble::tibble(ID = id, treatment_date = as.Date(date), treatment_type = type,
                 canonical_drug = drugs, episode_number = as.integer(ep),
                 start_date = as.Date(date))
}
lab1 <- function(df, type = "Chemotherapy", ep = 1L) {
  r <- assign_regimen(df, REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS)
  r[r$treatment_type == type & r$episode_number == ep, ]
}

# -- 1. Exact CHOP / BEACOPP sets; order- and separator-independent ------------
test_that("CHOP family exact drug sets resolve", {
  expect_equal(lab1(rows(c("Cyclophosphamide", "Doxorubicin", "Vincristine")))$regimen_label, "CHOP")
  expect_equal(lab1(rows(c("Vincristine", "Rituximab", "Doxorubicin", "Cyclophosphamide")))$regimen_label, "R-CHOP")
  expect_equal(lab1(rows(c("Bleomycin", "Cyclophosphamide", "Doxorubicin", "Etoposide", "Vincristine")))$regimen_label, "BEACOPP")
  expect_equal(lab1(rows(c("Cyclophosphamide", "Doxorubicin", "Etoposide", "Vincristine")))$regimen_label, "CHOEP")
})

test_that("episode-level drug_names with commas or semicolons, any order", {
  for (sep in c(", ", "; ", ",")) {
    dn <- paste(c("Vincristine", "Doxorubicin", "Cyclophosphamide", "Etoposide"), collapse = sep)
    ep <- tibble::tibble(ID = "P1", treatment_type = "Chemotherapy", episode_number = 1L,
                         start_date = as.Date("2022-01-01"), drug_names = dn)
    r <- assign_regimen(rows("Doxorubicin")[0, ], REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS, episode_df = ep)
    expect_equal(r$regimen_label, "CHOEP")
  }
})

test_that("salt / parenthetical suffixes still match", {
  expect_equal(normalize_regimen_drug(c("Pembrolizumab (IV)", "Vincristine Sulfate", "Doxorubicin")),
               c("Pembrolizumab", "Vincristine", "Doxorubicin"))
  expect_equal(lab1(rows(c("Cyclophosphamide", "Doxorubicin Hydrochloride", "Vincristine Sulfate")))$regimen_label, "CHOP")
})

test_that("CHOP / BEACOPP are first-line eligible", {
  expect_true(all(first_line_eligible(c("CHOP", "R-CHOP", "CHOEP", "BEACOPP"))))
})

# -- 2. Immunotherapy agents alone ---------------------------------------------
im <- function(drugs) lab1(rows(drugs, type = "Immunotherapy"), type = "Immunotherapy")
test_that("immunotherapy-alone labels and detail", {
  expect_equal(im("Brentuximab Vedotin")$regimen_label, "BV mono")
  r <- im("Nivolumab");     expect_equal(r$regimen_label, "PD-1 mono"); expect_equal(r$regimen_detail, "Nivolumab")
  r <- im("Pembrolizumab"); expect_equal(r$regimen_label, "PD-1 mono"); expect_equal(r$regimen_detail, "Pembrolizumab")
  expect_equal(im(c("Brentuximab Vedotin", "Nivolumab"))$regimen_label, "BV+Nivo")
  expect_equal(im(c("Brentuximab Vedotin", "Pembrolizumab"))$regimen_label, "BV+PD-1")
  r <- im(c("Nivolumab", "Pembrolizumab"))
  expect_equal(r$regimen_label, "PD-1 mono"); expect_match(r$regimen_detail, "switch")
})

test_that("other checkpoint and non-HL agents", {
  for (d in list("Durvalumab", "Atezolizumab", "Ipilimumab", "Cemiplimab",
                 c("Ipilimumab", "Nivolumab"), c("Atezolizumab", "Nivolumab"))) {
    expect_equal(im(d)$regimen_label, "Other checkpoint (non-HL)")
  }
  expect_equal(im("Pentostatin")$regimen_label, "Non-HL agent")
  expect_equal(im("Mogamulizumab")$regimen_label, "Non-HL agent")
})

test_that("BV mono after SCT is BV_consolidation, else BV mono", {
  sct <- tibble::tibble(ID = "P001", sct_start = as.Date("2021-12-01"), sct_stop = as.Date("2021-12-20"))
  r <- assign_regimen(rows("Brentuximab Vedotin", type = "Immunotherapy"),
                      REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS, sct_df = sct)
  expect_equal(r$regimen_label, "BV_consolidation")
})

test_that("LOT: salvage immuno labels count, non-HL labels do not", {
  ep <- tibble::tibble(
    ID = "P1", episode_number = 1:4,
    start_date = as.Date("2022-01-01") + c(0, 200, 400, 600),
    end_date   = as.Date("2022-01-10") + c(0, 200, 400, 600),
    regimen_label = c("ABVD", "BV mono", "Other checkpoint (non-HL)", "PD-1 mono"))
  out <- assign_lot(ep, lot_gap_days = LOT_GAP_DAYS, maintenance_classes = MAINTENANCE_DRUG_CLASSES)
  expect_equal(out$line_of_therapy, c(1L, 2L, NA, 3L))
  expect_false(first_line_eligible("BV mono"))
  expect_false(first_line_eligible("Non-HL agent"))
})

# -- 3 / 4. Episode-anchored ABVD-family rule ----------------------------------
abvd3 <- c("Doxorubicin", "Vinblastine", "Dacarbazine")
abvd4 <- c(abvd3, "Bleomycin")
two_ep <- function(own, own_dates, other, other_type, other_date, other_ep = 1L) {
  a <- tibble::tibble(ID = "P1", treatment_type = "Chemotherapy", episode_number = 1L,
                      start_date = as.Date(own_dates[1]),
                      treatment_date = as.Date(rep(own_dates, length.out = length(own))),
                      canonical_drug = own)
  b <- tibble::tibble(ID = "P1", treatment_type = other_type, episode_number = other_ep,
                      start_date = as.Date(other_date), treatment_date = as.Date(other_date),
                      canonical_drug = other)
  dplyr::bind_rows(a, b)
}
chemo_label <- function(df) {
  r <- assign_regimen(df, REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS)
  r[r$treatment_type == "Chemotherapy" & r$episode_number == 1L, ]
}

test_that("BV+AVD: BV in any treatment_type row within +/-7 days of ANY chemo date", {
  # BV 6 days after the LAST chemo date, 20 days after episode start -> still BV+AVD
  df <- two_ep(rep(abvd3, 2), rep(c("2022-01-01", "2022-01-15"), each = 3),
               "Brentuximab Vedotin", "Immunotherapy", "2022-01-21")
  expect_equal(chemo_label(df)$regimen_label, "BV+AVD")
  # 8 days after last chemo date -> outside the window -> AVD
  df <- two_ep(rep(abvd3, 2), rep(c("2022-01-01", "2022-01-15"), each = 3),
               "Brentuximab Vedotin", "Immunotherapy", "2022-01-23")
  expect_equal(chemo_label(df)$regimen_label, "AVD")
  # BV recorded under a Chemotherapy-type row of another episode also counts
  df <- two_ep(abvd3, "2022-01-01", "Brentuximab Vedotin", "Chemotherapy", "2022-01-05", other_ep = 2L)
  expect_equal(chemo_label(df)$regimen_label, "BV+AVD")
})

test_that("Nivo+AVD, and BV wins over nivolumab", {
  df <- two_ep(abvd3, "2022-01-01", "Nivolumab", "Immunotherapy", "2022-01-03")
  expect_equal(chemo_label(df)$regimen_label, "Nivo+AVD")
  both <- dplyr::bind_rows(df, two_ep(abvd3, "2022-01-01", "Brentuximab Vedotin", "Immunotherapy", "2022-01-04", 2L))
  expect_equal(chemo_label(both)$regimen_label, "BV+AVD")
})

test_that("ABVD + concurrent BV / nivolumab is ABVD_PLUS (Phase 201)", {
  df <- two_ep(abvd4, "2022-01-01", "Brentuximab Vedotin", "Immunotherapy", "2022-01-03")
  expect_equal(chemo_label(df)$regimen_label, "ABVD_PLUS")
})

test_that("supportive agents never make plus", {
  for (s in c("Leuprolide", "Goserelin")) {
    own_in <- chemo_label(two_ep(c(abvd4, s), "2022-01-01", "Nivolumab", "Immunotherapy", "2022-06-01"))
    expect_equal(own_in$regimen_label, "ABVD")
    other_row <- chemo_label(two_ep(abvd4, "2022-01-01", s, "Chemotherapy", "2022-01-03", 2L))
    expect_equal(other_row$regimen_label, "ABVD")
  }
})

test_that("any other antineoplastic with ABVD / AVD is ABVD_PLUS", {
  for (x in c("Vincristine", "Cyclophosphamide", "Etoposide", "Procarbazine", "Carboplatin",
              "Ifosfamide", "Rituximab", "Methotrexate", "Prednisone")) {
    r <- chemo_label(rows(c(abvd4, x)))
    expect_equal(r$regimen_label, "ABVD_PLUS", info = x)
    expect_match(r$regimen_detail, x, info = x)
  }
  r <- chemo_label(rows(c(abvd3, "Rituximab")))
  expect_equal(r$regimen_label, "ABVD_PLUS")
  # ABVD + BEACOPP components
  r <- chemo_label(rows(c(abvd4, "Cyclophosphamide", "Etoposide", "Procarbazine", "Vincristine")))
  expect_equal(r$regimen_label, "ABVD_PLUS")
})

test_that("episode-level exact ABVD becomes plus when another row's agent is within window", {
  # (c) agent in another row/type within +/-7 days of the chemo dates
  df <- two_ep(abvd4, "2022-01-01", "Rituximab", "Immunotherapy", "2022-01-06")
  expect_equal(chemo_label(df)$regimen_label, "ABVD_PLUS")
  df <- two_ep(abvd4, "2022-01-01", "Rituximab", "Immunotherapy", "2022-01-20")
  expect_equal(chemo_label(df)$regimen_label, "ABVD")
})

test_that("classify_abvd_set pure rule", {
  expect_equal(classify_abvd_set(abvd4)$label, "ABVD")
  expect_equal(classify_abvd_set(abvd3)$label, "AVD")
  expect_equal(classify_abvd_set(c(abvd3, "Brentuximab Vedotin"))$label, "BV+AVD")
  expect_equal(classify_abvd_set(c(abvd3, "Nivolumab"))$label, "Nivo+AVD")
  expect_equal(classify_abvd_set(c(abvd4, "Leuprolide"))$label, "ABVD")
  expect_equal(classify_abvd_set(c(abvd3, "Goserelin", "Vincristine"))$label, "ABVD_PLUS")
})
