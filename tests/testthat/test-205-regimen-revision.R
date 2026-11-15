# ==============================================================================
# test-205-regimen-revision.R -- Quick 261114-sir: Phase 205 revision tests
# ==============================================================================
# Coverage: new REGIMEN_DICT entries, separator handling, episode-basis
# fallback, recognized-only LOT rules, first-line eligibility.
# ==============================================================================

# 00_config.R cannot fully load without HiPerGator data, so evaluate only the
# Phase 205 constant assignments straight from the parsed config (no data access).
{
  want <- c("REGIMEN_DICT", "BEAM_SCT_WINDOW_DAYS", "LOT_GAP_DAYS",
            "MAINTENANCE_DRUG_CLASSES", "CONCURRENCY_WINDOW_DAYS",
            "BV_CONSOLIDATION_SCT_WINDOW_DAYS")
  for (e in parse(here::here("R", "00_config.R"))) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) &&
        is.name(e[[2]]) && as.character(e[[2]]) %in% want) {
      eval(e, envir = environment())
    }
  }
}
if (!exists("REGIMEN_DICT") || is.null(REGIMEN_DICT[["BEAM_conditioning"]])) {
  skip("REGIMEN_DICT with Phase 205 revision entries not found in R/00_config.R")
}
if (!exists("LOT_GAP_DAYS"))             LOT_GAP_DAYS <- 90L
if (!exists("MAINTENANCE_DRUG_CLASSES")) MAINTENANCE_DRUG_CLASSES <- c("BV_consolidation", "Rituximab_mono")
if (!exists("CONCURRENCY_WINDOW_DAYS"))  CONCURRENCY_WINDOW_DAYS <- 7L

date_rows <- function(drugs, type = "Chemotherapy", ep = 1L, start = "2022-01-01", id = "P001") {
  tibble::tibble(ID = id, treatment_date = as.Date(start), treatment_type = type,
                 canonical_drug = drugs, episode_number = as.integer(ep),
                 start_date = as.Date(start))
}
lab <- function(drugs, ...) {
  assign_regimen(date_rows(drugs), REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS, ...)
}
ep_row <- function(id, type, ep, start, drugs) {
  tibble::tibble(ID = id, treatment_type = type, episode_number = as.integer(ep),
                 start_date = as.Date(start), drug_names = drugs)
}
no_dates <- date_rows("Doxorubicin")[0, ]

# ── Dictionary additions ──────────────────────────────────────────────────────
test_that("BEACOPP with and without procarbazine/prednisone", {
  core <- c("Bleomycin", "Cyclophosphamide", "Doxorubicin", "Etoposide", "Vincristine")
  expect_equal(lab(core)$regimen_label, "BEACOPP")
  expect_equal(lab(c(core, "Procarbazine", "Prednisone"))$regimen_label, "BEACOPP")
})

test_that("CHOP, R-CHOP, CHOEP backbones", {
  expect_equal(lab(c("Cyclophosphamide", "Doxorubicin", "Vincristine"))$regimen_label, "CHOP")
  expect_equal(lab(c("Cyclophosphamide", "Doxorubicin", "Vincristine", "Prednisone"))$regimen_label, "CHOP")
  expect_equal(lab(c("Cyclophosphamide", "Doxorubicin", "Rituximab", "Vincristine"))$regimen_label, "R-CHOP")
  expect_equal(lab(c("Cyclophosphamide", "Doxorubicin", "Etoposide", "Vincristine"))$regimen_label, "CHOEP")
})

test_that("BR and Bendamustine mono", {
  expect_equal(lab("Bendamustine")$regimen_label, "Bendamustine mono")
  expect_equal(lab(c("Bendamustine", "Rituximab"))$regimen_label, "BR")
})

test_that("BEAM: Conditioning near SCT, Salvage otherwise (with detail)", {
  beam <- c("Carmustine", "Etoposide")
  near <- tibble::tibble(ID = "P001", sct_start = as.Date("2022-01-10"), sct_stop = as.Date("2022-01-12"))
  far  <- tibble::tibble(ID = "P001", sct_start = as.Date("2023-01-10"), sct_stop = as.Date("2023-01-12"))
  expect_equal(lab(beam, sct_df = near)$regimen_label, "Conditioning (BEAM)")
  r <- lab(beam, sct_df = far)
  expect_equal(r$regimen_label, "Salvage")
  expect_match(r$regimen_detail, "BEAM")
  expect_equal(lab(beam)$regimen_label, "Salvage")
})

test_that("Salvage families share one label and record regimen_detail", {
  expect_equal(lab(c("Ifosfamide", "Carboplatin", "Etoposide"))$regimen_detail, "ICE")
  expect_equal(lab(c("Cisplatin", "Cytarabine"))$regimen_detail, "DHAP")
  expect_equal(lab(c("Etoposide", "Cisplatin", "Cytarabine"))$regimen_detail, "ESHAP")
  expect_equal(lab(c("Gemcitabine", "Cisplatin"))$regimen_detail, "GDP")
  expect_equal(lab(c("Gemcitabine", "Vinorelbine", "Doxorubicin"))$regimen_detail, "GVD")
  for (d in c("Gemcitabine", "Cisplatin", "Carboplatin")) {
    expect_equal(lab(d)$regimen_label, "Salvage")
  }
  expect_equal(lab("Gemcitabine")$regimen_detail, "gemcitabine-based")
  expect_equal(lab("Carboplatin")$regimen_detail, "platinum-based")
})

test_that("Partial ABVD/AVD sets label 'ABVD/AVD partial'; one drug stays Unrecognized", {
  expect_equal(lab(c("Bleomycin", "Dacarbazine", "Doxorubicin"))$regimen_label, "ABVD/AVD partial")
  expect_equal(lab(c("Dacarbazine", "Doxorubicin"))$regimen_label, "ABVD/AVD partial")
  expect_equal(lab("Doxorubicin")$regimen_label, "Unrecognized systemic")
})

test_that("ABVD_PLUS: AVD + other agent (not BV/nivo) keeps the Phase 201 class", {
  expect_equal(lab(c("Doxorubicin", "Bleomycin", "Vinblastine", "Dacarbazine", "Etoposide"))$regimen_label, "ABVD_PLUS")
  expect_equal(lab(c("Doxorubicin", "Vinblastine", "Dacarbazine", "Rituximab"))$regimen_label, "ABVD_PLUS")
  expect_equal(lab(c("Doxorubicin", "Bleomycin", "Vinblastine", "Dacarbazine"))$regimen_label, "ABVD")
})

test_that("Leuprolide and methotrexate-alone-with-autoimmune are supportive", {
  expect_equal(lab("Leuprolide")$regimen_label, "Non-lymphoma / supportive")
  expect_equal(lab("Methotrexate")$regimen_label, "Unrecognized systemic")
  expect_equal(lab("Methotrexate", immune_ids = "P001")$regimen_label, "Non-lymphoma / supportive")
  expect_equal(lab("Methotrexate", immune_ids = "P999")$regimen_label, "Unrecognized systemic")
  expect_equal(lab(c("Methotrexate", "Vincristine"), immune_ids = "P001")$regimen_label, "Unrecognized systemic")
})

# ── Separators ────────────────────────────────────────────────────────────────
test_that("split_drug_names handles comma and semicolon separators", {
  expect_equal(split_drug_names("Bleomycin;Dacarbazine;Doxorubicin;Vinblastine"),
               c("Bleomycin", "Dacarbazine", "Doxorubicin", "Vinblastine"))
  expect_equal(split_drug_names("Bleomycin, Dacarbazine,Doxorubicin ; Vinblastine"),
               c("Bleomycin", "Dacarbazine", "Doxorubicin", "Vinblastine"))
  expect_equal(split_drug_names(NA_character_), character(0))
  expect_equal(split_drug_names(""), character(0))
})

# ── Episode-basis fallback ────────────────────────────────────────────────────
test_that("Episode fallback: no date-level rows, either separator, never NA", {
  for (dn in c("Bleomycin;Dacarbazine;Doxorubicin;Vinblastine",
               "Bleomycin, Dacarbazine, Doxorubicin, Vinblastine")) {
    r <- assign_regimen(no_dates, REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS,
                        episode_df = ep_row("P001", "Chemotherapy", 1, "2022-01-01", dn))
    expect_equal(r$regimen_label, "ABVD")
    expect_equal(r$regimen_basis, "episode")
  }
  r <- assign_regimen(no_dates, REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS,
                      episode_df = ep_row("P001", "Chemotherapy", 1, "2022-01-01",
                                          "Dacarbazine;Doxorubicin;Vinblastine"))
  expect_equal(r$regimen_label, "AVD")
  r <- assign_regimen(no_dates, REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS,
                      episode_df = ep_row("P001", "Chemotherapy", 1, "2022-01-01", "Mitotane"))
  expect_equal(r$regimen_label, "Unrecognized systemic")
})

test_that("Episode fallback pools across episodes (BV immuno + AVD chemo)", {
  eps <- dplyr::bind_rows(
    ep_row("P001", "Chemotherapy", 1, "2022-01-01", "Dacarbazine;Doxorubicin;Vinblastine"),
    ep_row("P001", "Immunotherapy", 1, "2022-01-02", "Brentuximab Vedotin"))
  r <- assign_regimen(no_dates, REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS, episode_df = eps)
  expect_equal(nrow(r), 2L)
  expect_true(all(r$regimen_label == "BV+AVD"))
})

# Round 4 (quick 261114): an agent in another row within +/-7 days of the episode's
# chemo dates makes an exact-ABVD episode ABVD_PLUS (Phase 201 date-level rule), so
# the neighbouring prednisone row now yields ABVD_PLUS; a far-away one stays ABVD.
test_that("Neighbouring agent within window -> ABVD_PLUS; outside window stays ABVD; date basis when no episode_df", {
  dates <- dplyr::bind_rows(
    date_rows(c("Doxorubicin", "Bleomycin", "Vinblastine", "Dacarbazine")),
    date_rows("Prednisone", ep = 2L, start = "2022-01-03"))
  eps <- ep_row("P001", "Chemotherapy", 1, "2022-01-01", "Bleomycin;Dacarbazine;Doxorubicin;Vinblastine")
  r1 <- assign_regimen(dates, REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS, episode_df = eps)
  r1 <- r1[r1$episode_number == 1L, ]
  expect_equal(r1$regimen_label, "ABVD_PLUS")
  expect_equal(r1$regimen_basis, "episode")
  far <- dplyr::bind_rows(
    date_rows(c("Doxorubicin", "Bleomycin", "Vinblastine", "Dacarbazine")),
    date_rows("Prednisone", ep = 2L, start = "2022-03-01"))
  rf <- assign_regimen(far, REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS, episode_df = eps)
  expect_equal(rf$regimen_label[rf$episode_number == 1L], "ABVD")
  r0 <- assign_regimen(date_rows(c("Doxorubicin", "Bleomycin", "Vinblastine", "Dacarbazine")),
                       REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS)
  expect_equal(r0$regimen_basis, "date")
})

# ── LOT rules ─────────────────────────────────────────────────────────────────
mk <- function(id, n, start, end, label, type = "Chemotherapy") {
  tibble::tibble(ID = id, episode_number = as.integer(n), start_date = as.Date(start),
                 end_date = as.Date(end), regimen_label = label, treatment_type = type)
}
lot_of <- function(df) {
  assign_lot(df, lot_gap_days = LOT_GAP_DAYS, maintenance_classes = MAINTENANCE_DRUG_CLASSES)$line_of_therapy
}

test_that("Radiation, SCT, Proton episodes get NA line_of_therapy", {
  df <- dplyr::bind_rows(
    mk("P1", 1, "2022-01-01", "2022-04-01", "ABVD"),
    mk("P1", 1, "2022-02-01", "2022-03-01", NA_character_, "Radiation"),
    mk("P1", 1, "2022-05-01", "2022-05-10", NA_character_, "SCT"),
    mk("P1", 1, "2022-06-01", "2022-06-10", NA_character_, "Proton"))
  expect_equal(lot_of(df), c(1L, NA, NA, NA))
})

test_that("Unrecognized and Non-lymphoma episodes get NA and do not start a line", {
  df <- dplyr::bind_rows(
    mk("P1", 1, "2022-01-01", "2022-04-01", "ABVD"),
    mk("P1", 2, "2022-04-10", "2022-04-20", "Unrecognized systemic"),
    mk("P1", 3, "2022-04-25", "2022-05-01", "Non-lymphoma / supportive"),
    mk("P1", 4, "2022-05-10", "2022-06-01", "AVD"))
  expect_equal(lot_of(df), c(1L, NA, NA, 1L))
})

test_that("Regimen family change starts a new line; same family inside the gap does not", {
  df <- dplyr::bind_rows(
    mk("P1", 1, "2022-01-01", "2022-03-01", "ABVD"),
    mk("P1", 2, "2022-03-10", "2022-05-01", "BV+AVD"),
    mk("P1", 3, "2022-05-10", "2022-06-01", "Salvage"))
  expect_equal(lot_of(df), c(1L, 1L, 2L))
})

test_that("Same family restarting after gap >= LOT_GAP_DAYS is a new line", {
  df <- dplyr::bind_rows(
    mk("P1", 1, "2022-01-01", "2022-03-01", "ABVD"),
    mk("P1", 2, "2022-08-01", "2022-10-01", "ABVD"))
  expect_equal(lot_of(df), c(1L, 2L))
})

test_that("BV_consolidation and BEAM conditioning attach to the current line", {
  df <- dplyr::bind_rows(
    mk("P1", 1, "2022-01-01", "2022-03-01", "ABVD"),
    mk("P1", 2, "2022-09-01", "2022-10-01", "Salvage"),
    mk("P1", 3, "2022-11-01", "2022-11-08", "Conditioning (BEAM)"),
    mk("P1", 1, "2022-11-10", "2022-11-12", NA_character_, "SCT"),
    mk("P1", 4, "2022-12-15", "2023-03-01", "BV_consolidation", "Immunotherapy"),
    mk("P1", 5, "2022-12-01", "2022-12-10", "Salvage"))
  expect_equal(lot_of(df), c(1L, 2L, 2L, NA, 2L, 2L))  # sorted by start: Salvage(12-01) then BV(12-15)
})

test_that("Conditioning before any line has no line", {
  expect_true(is.na(lot_of(mk("P1", 1, "2022-01-01", "2022-01-08", "Conditioning (BEAM)"))))
})

# ── First-line eligibility ────────────────────────────────────────────────────
test_that("first_line_eligible keeps recognized regimens, drops the rest", {
  ok <- c("ABVD", "AVD", "ABVD_PLUS", "ABVD/AVD partial", "BV+AVD", "Nivo+AVD",
          "BEACOPP", "CHOP", "R-CHOP", "CHOEP")
  expect_true(all(first_line_eligible(ok)))
  bad <- c("Unrecognized systemic", "Salvage", "Conditioning (BEAM)",
           "Non-lymphoma / supportive", "BV_consolidation", "Rituximab_mono", NA)
  expect_false(any(first_line_eligible(bad)))
})

# ── Methotrexate relabel (R/142 helper) ───────────────────────────────────────
test_that("relabel_methotrexate_autoimmune only touches MTX-alone Unrecognized in immune patients", {
  lbl <- rep("Unrecognized systemic", 4)
  dn  <- c("Methotrexate", "Methotrexate;Vincristine", "methotrexate", "Methotrexate")
  imm <- c(TRUE, TRUE, FALSE, NA)
  expect_equal(relabel_methotrexate_autoimmune(lbl, dn, imm),
               c("Non-lymphoma / supportive", "Unrecognized systemic",
                 "Unrecognized systemic", "Unrecognized systemic"))
  expect_equal(relabel_methotrexate_autoimmune("ABVD", "Methotrexate", TRUE), "ABVD")
})
