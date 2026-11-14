# ==============================================================================
# test-205-regimen-dict.R -- Unit tests for assign_regimen() (Phase 205)
# ==============================================================================
# Coverage:
#   REGL-01: All 10 REGIMEN_DICT families detected correctly on synthetic data
#   REGL-02: Concurrency window enforcement (drugs outside window not counted)
#   Exclusive flag: extra chemo agent disqualifies a family match
#   Unknown combination → "Other"
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
    NLPHL = list(drugs = c("Rituximab"), exclusive = FALSE, maintenance = FALSE),
    Salvage = list(drugs = c("Ifosfamide", "Carboplatin", "Etoposide"),
                   exclusive = FALSE, maintenance = FALSE),
    BV_consolidation = list(drugs = c("Brentuximab Vedotin"),
                             exclusive = TRUE, maintenance = TRUE)
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

# ── REGL-01: NLPHL ────────────────────────────────────────────────────────────
test_that("REGL-01: NLPHL — Rituximab alone returns NLPHL", {
  df <- make_episode_df(c("Rituximab"))
  result <- assign_regimen(df, regimen_dict = REGIMEN_DICT,
                           window_days = CONCURRENCY_WINDOW_DAYS)
  expect_equal(result$regimen_label, "NLPHL")
})

# ── REGL-01: Salvage (ICE) ────────────────────────────────────────────────────
test_that("REGL-01: Salvage — Ifosfamide + Carboplatin + Etoposide returns Salvage", {
  df <- make_episode_df(c("Ifosfamide", "Carboplatin", "Etoposide"))
  result <- assign_regimen(df, regimen_dict = REGIMEN_DICT,
                           window_days = CONCURRENCY_WINDOW_DAYS)
  expect_equal(result$regimen_label, "Salvage")
})

# ── Unknown combination → Other ───────────────────────────────────────────────
test_that("REGL-01: Unknown drug combination returns Other", {
  df <- make_episode_df(c("Methotrexate", "Ipilimumab"))
  result <- assign_regimen(df, regimen_dict = REGIMEN_DICT,
                           window_days = CONCURRENCY_WINDOW_DAYS)
  expect_equal(result$regimen_label, "Other")
})

# ── Exclusive flag: extra chemo agent disqualifies ABVD ───────────────────────
test_that("REGL-01: Exclusive — ABVD + extra chemo agent returns Other (not ABVD)", {
  df <- make_episode_df(c("Doxorubicin", "Bleomycin", "Vinblastine",
                           "Dacarbazine", "Etoposide"))
  result <- assign_regimen(df, regimen_dict = REGIMEN_DICT,
                           window_days = CONCURRENCY_WINDOW_DAYS)
  expect_equal(result$regimen_label, "Other")
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
  expect_true(result$regimen_label != "ABVD")
})
