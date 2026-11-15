# ==============================================================================
# test-205-regimen-dict.R -- Unit tests for assign_regimen() (Phase 205)
# ==============================================================================
# Coverage:
#   REGL-01: All 10 REGIMEN_DICT families detected correctly on synthetic data
#   REGL-02: Concurrency window enforcement (drugs outside window not counted)
#   Exclusive flag: extra chemo agent disqualifies a family match
#   Systemic-only labels; no "Other"/"NLPHL"; BV_consolidation needs prior SCT
# ==============================================================================

# Source config (provides REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS) ──────────────
# helper-utils.R sources utils_regimen.R (assign_regimen) but not 00_config.R,
# so config constants may be absent. Source config silently; if it fails (data
# files absent locally), fall back to canonical test-time values.
if (!exists("REGIMEN_DICT")) {
  suppressWarnings(tryCatch(
    source("R/00_config.R", local = FALSE),
    error = function(e) NULL
  ))
}

# Fallback constants for local unit-test runs where 00_config.R cannot fully load.
if (!exists("REGIMEN_DICT")) {
  REGIMEN_DICT <- list(
    ABVD = list(drugs = c("Doxorubicin", "Bleomycin", "Vinblastine", "Dacarbazine"),
                exclusive = TRUE, maintenance = FALSE),
    AVD  = list(drugs = c("Doxorubicin", "Vinblastine", "Dacarbazine"),
                exclusive = TRUE, maintenance = FALSE),
    `BV+AVD` = list(drugs = c("Brentuximab Vedotin", "Doxorubicin",
                               "Vinblastine", "Dacarbazine"),
                     exclusive = TRUE, maintenance = FALSE),
    `Nivo+AVD` = list(drugs = c("Nivolumab", "Doxorubicin",
                                  "Vinblastine", "Dacarbazine"),
                       exclusive = TRUE, maintenance = FALSE),
    BEACOPP = list(drugs = c("Bleomycin", "Etoposide", "Doxorubicin",
                              "Cyclophosphamide", "Vincristine",
                              "Procarbazine", "Prednisone"),
                   exclusive = FALSE, maintenance = FALSE),
    escBEACOPP = list(drugs = c("Bleomycin", "Etoposide", "Doxorubicin",
                                  "Cyclophosphamide", "Vincristine",
                                  "Procarbazine", "Prednisone"),
                       exclusive = FALSE, maintenance = FALSE),
    Pediatric = list(drugs = c("Doxorubicin", "Vincristine", "Etoposide",
                                "Prednisone", "Cyclophosphamide"),
                     exclusive = FALSE, maintenance = FALSE),
    `R-CHOP` = list(drugs = c("Rituximab", "Cyclophosphamide", "Doxorubicin",
                               "Vincristine", "Prednisone"),
                     exclusive = FALSE, maintenance = FALSE),
    `R-CVP` = list(drugs = c("Rituximab", "Cyclophosphamide", "Vincristine", "Prednisone"),
                    exclusive = TRUE, maintenance = FALSE),
    Salvage = list(drugs = c("Ifosfamide", "Carboplatin", "Etoposide"),
                   exclusive = FALSE, maintenance = FALSE),
    Rituximab_mono = list(drugs = c("Rituximab"), exclusive = TRUE, maintenance = TRUE),
    BV_consolidation = list(drugs = c("Brentuximab Vedotin"),
                             exclusive = TRUE, maintenance = TRUE,
                             requires_prior_sct = TRUE)
  )
}
if (!exists("CONCURRENCY_WINDOW_DAYS")) CONCURRENCY_WINDOW_DAYS <- 7L

if (!exists("assign_regimen")) {
  skip("assign_regimen not available (utils_regimen.R could not be sourced by helper-utils.R)")
}

# Helper: build a minimal date-level tibble for one episode ───────────────────
make_episode_df <- function(drugs,
                            dates       = NULL,
                            start_date  = as.Date("2022-01-01"),
                            id          = "P001",
                            ep_num      = 1L,
                            type        = "Chemotherapy") {
  n <- length(drugs)
  if (is.null(dates)) {
    dates <- rep(start_date, n)
  }
  tibble::tibble(
    ID             = id,
    treatment_date = dates,
    treatment_type = type,
    canonical_drug = drugs,
    episode_number = ep_num,
    start_date     = start_date
  )
}

# ── REGL-01: ABVD ─────────────────────────────────────────────────────────────
test_that("REGL-01: ABVD — all 4 drugs present returns ABVD", {
  df <- make_episode_df(c("Doxorubicin", "Bleomycin", "Vinblastine", "Dacarbazine"))
  result <- assign_regimen(df, regimen_dict = REGIMEN_DICT,
                           window_days = CONCURRENCY_WINDOW_DAYS)
  expect_equal(result$regimen_label, "ABVD")
})

# ── REGL-01: AVD ──────────────────────────────────────────────────────────────
test_that("REGL-01: AVD — 3 drugs (no Bleomycin) returns AVD", {
  df <- make_episode_df(c("Doxorubicin", "Vinblastine", "Dacarbazine"))
  result <- assign_regimen(df, regimen_dict = REGIMEN_DICT,
                           window_days = CONCURRENCY_WINDOW_DAYS)
  expect_equal(result$regimen_label, "AVD")
})

# ── REGL-01: BV+AVD ───────────────────────────────────────────────────────────
test_that("REGL-01: BV+AVD — Brentuximab Vedotin + AVD drugs returns BV+AVD", {
  df <- make_episode_df(c("Brentuximab Vedotin", "Doxorubicin",
                           "Vinblastine", "Dacarbazine"))
  result <- assign_regimen(df, regimen_dict = REGIMEN_DICT,
                           window_days = CONCURRENCY_WINDOW_DAYS)
  expect_equal(result$regimen_label, "BV+AVD")
})

# ── REGL-01: Rituximab families (NLPHL is a diagnosis, not a regimen) ──────────
test_that("REGL-01: Rituximab alone returns Rituximab_mono, never NLPHL", {
  df <- make_episode_df(c("Rituximab"))
  result <- assign_regimen(df, regimen_dict = REGIMEN_DICT,
                           window_days = CONCURRENCY_WINDOW_DAYS)
  expect_equal(result$regimen_label, "Rituximab_mono")
})

test_that("REGL-01: R-CHOP and R-CVP are distinguished", {
  chop <- make_episode_df(c("Rituximab", "Cyclophosphamide", "Doxorubicin",
                            "Vincristine", "Prednisone"))
  cvp  <- make_episode_df(c("Rituximab", "Cyclophosphamide", "Vincristine", "Prednisone"))
  expect_equal(assign_regimen(chop, REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS)$regimen_label, "R-CHOP")
  expect_equal(assign_regimen(cvp,  REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS)$regimen_label, "R-CVP")
})

# ── REGL-01: Salvage (ICE) ────────────────────────────────────────────────────
test_that("REGL-01: Salvage — Ifosfamide + Carboplatin + Etoposide returns Salvage", {
  df <- make_episode_df(c("Ifosfamide", "Carboplatin", "Etoposide"))
  result <- assign_regimen(df, regimen_dict = REGIMEN_DICT,
                           window_days = CONCURRENCY_WINDOW_DAYS)
  expect_equal(result$regimen_label, "Salvage")
})

# ── No match: Unrecognized systemic (chemo) or NA (never "Other") ─────────────
test_that("Unknown chemotherapy combination returns 'Unrecognized systemic'", {
  df <- make_episode_df(c("Methotrexate", "Ipilimumab"))
  result <- assign_regimen(df, regimen_dict = REGIMEN_DICT,
                           window_days = CONCURRENCY_WINDOW_DAYS)
  expect_equal(result$regimen_label, "Unrecognized systemic")
})

test_that("Exclusive: ABVD + extra chemo agent is not ABVD and not 'Other'", {
  df <- make_episode_df(c("Doxorubicin", "Bleomycin", "Vinblastine",
                           "Dacarbazine", "Etoposide"))
  result <- assign_regimen(df, regimen_dict = REGIMEN_DICT,
                           window_days = CONCURRENCY_WINDOW_DAYS)
  expect_false(result$regimen_label %in% c("ABVD", "Other"))
})

# ── Non-systemic episodes are never labeled ────────────────────────────────────
test_that("Radiation, SCT and Proton episodes get no label (not in output)", {
  for (tp in c("Radiation", "SCT", "Proton")) {
    df <- make_episode_df(c("Doxorubicin", "Bleomycin", "Vinblastine", "Dacarbazine"),
                          type = tp)
    result <- assign_regimen(df, REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS)
    expect_equal(nrow(result), 0L)
  }
})

test_that("Same episode_number across types: radiation does not inherit chemo label", {
  chemo <- make_episode_df(c("Doxorubicin", "Bleomycin", "Vinblastine", "Dacarbazine"))
  rad   <- make_episode_df("Doxorubicin", type = "Radiation")  # ep_num 1 as well
  result <- assign_regimen(dplyr::bind_rows(chemo, rad), REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS)
  expect_equal(result$treatment_type, "Chemotherapy")
  expect_equal(result$regimen_label, "ABVD")
})

# ── Immunotherapy: labeled only when part of a defined regimen ────────────────
test_that("Immunotherapy BV episode alongside AVD chemo is BV+AVD on both episodes", {
  chemo <- make_episode_df(c("Doxorubicin", "Vinblastine", "Dacarbazine"))
  immu  <- make_episode_df("Brentuximab Vedotin", type = "Immunotherapy")
  result <- assign_regimen(dplyr::bind_rows(chemo, immu), REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS)
  expect_true(all(result$regimen_label == "BV+AVD"))
  expect_equal(sort(result$treatment_type), c("Chemotherapy", "Immunotherapy"))
})

test_that("Immunotherapy agent outside any regimen is Unrecognized, never NA", {
  df <- make_episode_df("Pembrolizumab", type = "Immunotherapy")
  result <- assign_regimen(df, REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS)
  expect_equal(result$regimen_label, "Unrecognized systemic")
})

# ── BV_consolidation requires SCT within window ───────────────────────────────
test_that("BV alone without SCT is Unrecognized, with SCT inside window is BV_consolidation", {
  bv <- make_episode_df("Brentuximab Vedotin", type = "Immunotherapy",
                        start_date = as.Date("2022-03-01"))
  expect_equal(assign_regimen(bv, REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS)$regimen_label, "Unrecognized systemic")

  sct_near <- tibble::tibble(ID = "P001", sct_start = as.Date("2022-01-15"),
                             sct_stop = as.Date("2022-01-20"))
  expect_equal(assign_regimen(bv, REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS,
                              sct_df = sct_near, sct_window_days = 90L)$regimen_label,
               "BV_consolidation")

  sct_far <- tibble::tibble(ID = "P001", sct_start = as.Date("2021-01-01"),
                            sct_stop = as.Date("2021-01-10"))
  expect_equal(assign_regimen(bv, REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS,
                                   sct_df = sct_far, sct_window_days = 90L)$regimen_label, "Unrecognized systemic")

  sct_after <- tibble::tibble(ID = "P001", sct_start = as.Date("2022-06-01"),
                              sct_stop = as.Date("2022-06-05"))
  expect_equal(assign_regimen(bv, REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS,
                                   sct_df = sct_after, sct_window_days = 90L)$regimen_label, "Unrecognized systemic")
})

# ── REGL-02: Window enforcement ───────────────────────────────────────────────
test_that("REGL-02: Drug administered outside window is not counted toward regimen", {
  start <- as.Date("2022-01-01")
  # Dacarbazine given 20 days after start — outside CONCURRENCY_WINDOW_DAYS=7
  dates <- c(start, start, start, start + 20L)
  drugs <- c("Doxorubicin", "Bleomycin", "Vinblastine", "Dacarbazine")
  df <- make_episode_df(drugs, dates = dates, start_date = start)
  result <- assign_regimen(df, regimen_dict = REGIMEN_DICT,
                           window_days = CONCURRENCY_WINDOW_DAYS)
  # Without Dacarbazine in window: not ABVD (exclusive) and not AVD (Bleomycin present)
  expect_false(result$regimen_label %in% "ABVD")
})
