# ==============================================================================
# test-205-lot-counter.R -- Unit tests for assign_lot() (Phase 205)
# ==============================================================================
# Coverage:
#   REGL-03: Gap-triggered LOT increment
#   REGL-03: Post-SCT LOT increment
#   REGL-03: Maintenance episodes inherit current LOT
#   REGL-03: Three-line patient (gap + SCT + gap)
#   Single episode baseline
#   Two episodes within gap — no increment
# ==============================================================================

# Source config (provides LOT_GAP_DAYS, MAINTENANCE_DRUG_CLASSES) ─────────────
# helper-utils.R sources utils_regimen.R (assign_lot) but not 00_config.R,
# so config constants may be absent. Source config silently; if it fails (data
# files absent locally), fall back to canonical test-time values.
if (!exists("LOT_GAP_DAYS")) {
  suppressWarnings(tryCatch(
    source("R/00_config.R", local = FALSE),
    error = function(e) NULL
  ))
}

# Fallback constants for local unit-test runs where 00_config.R cannot fully load.
if (!exists("LOT_GAP_DAYS"))              LOT_GAP_DAYS              <- 90L
if (!exists("MAINTENANCE_DRUG_CLASSES"))  MAINTENANCE_DRUG_CLASSES  <- c("BV_consolidation", "Rituximab_mono")

if (!exists("assign_lot")) {
  skip("assign_lot not available (utils_regimen.R could not be sourced by helper-utils.R)")
}

# Helper: build an episode tibble ─────────────────────────────────────────────
make_ep <- function(id, ep_num, start, end, label) {
  tibble::tibble(
    ID             = id,
    episode_number = as.integer(ep_num),
    start_date     = as.Date(start),
    end_date       = as.Date(end),
    regimen_label  = label
  )
}

# ── REGL-03: Single episode → line 1 ──────────────────────────────────────────
test_that("REGL-03: Single episode gets line_of_therapy = 1", {
  df <- make_ep("P001", 1, "2022-01-01", "2022-04-01", "ABVD")
  result <- assign_lot(df, lot_gap_days = LOT_GAP_DAYS,
                       maintenance_classes = MAINTENANCE_DRUG_CLASSES,
                       sct_dates_df = NULL)
  expect_equal(result$line_of_therapy, 1L)
})

# ── REGL-03: Two episodes with gap < LOT_GAP_DAYS — no increment ──────────────
test_that("REGL-03: Gap < LOT_GAP_DAYS — both episodes get line 1", {
  df <- dplyr::bind_rows(
    make_ep("P001", 1, "2022-01-01", "2022-04-01", "ABVD"),
    make_ep("P001", 2, "2022-05-01", "2022-08-01", "ABVD")  # gap = 30 days
  )
  result <- assign_lot(df, lot_gap_days = LOT_GAP_DAYS,
                       maintenance_classes = MAINTENANCE_DRUG_CLASSES,
                       sct_dates_df = NULL)
  expect_equal(result$line_of_therapy, c(1L, 1L))
})

# ── REGL-03: Two episodes with gap >= LOT_GAP_DAYS — increment ────────────────
test_that("REGL-03: Gap >= LOT_GAP_DAYS triggers new line", {
  df <- dplyr::bind_rows(
    make_ep("P001", 1, "2022-01-01", "2022-04-01", "ABVD"),
    make_ep("P001", 2, "2022-08-01", "2022-11-01", "Salvage")  # gap = 122 days
  )
  result <- assign_lot(df, lot_gap_days = LOT_GAP_DAYS,
                       maintenance_classes = MAINTENANCE_DRUG_CLASSES,
                       sct_dates_df = NULL)
  expect_equal(result$line_of_therapy, c(1L, 2L))
})

# ── REGL-03: Maintenance episode inherits LOT ─────────────────────────────────
test_that("REGL-03: Maintenance episode inherits current LOT, does not increment", {
  df <- dplyr::bind_rows(
    make_ep("P001", 1, "2022-01-01", "2022-04-01", "ABVD"),
    make_ep("P001", 2, "2022-08-01", "2022-11-01", "BV_consolidation")  # gap >= 90d but maintenance
  )
  result <- assign_lot(df, lot_gap_days = LOT_GAP_DAYS,
                       maintenance_classes = MAINTENANCE_DRUG_CLASSES,
                       sct_dates_df = NULL)
  # BV_consolidation is maintenance → stays at line 1
  expect_equal(result$line_of_therapy, c(1L, 1L))
})
# Post-SCT increment and SCT-gap three-line tests removed (quick 261114-sir):
# SCT no longer starts a line. New LOT rules are tested in test-205-regimen-revision.R.


# ==============================================================================
# W-COMBO (candidate): cross-type combined lot_family via combine_cross_type = TRUE
# ==============================================================================
lot_w <- function(eps, combine = FALSE) {
  assign_lot(eps, lot_gap_days = LOT_GAP_DAYS,
             maintenance_classes = MAINTENANCE_DRUG_CLASSES,
             same_family_restart_days = 365L,
             combine_cross_type = combine, concurrency_window_days = 7L)
}
make_ep_t <- function(id, ep_num, start, end, label, type) {
  dplyr::mutate(make_ep(id, ep_num, start, end, label), treatment_type = type)
}

test_that("combine_cross_type merges BV mono + Bendamustine mono into one line", {
  eps <- dplyr::bind_rows(
    make_ep_t("P1", 1, "2020-01-01", "2020-03-01", "BV mono", "Immunotherapy"),
    make_ep_t("P1", 1, "2020-01-05", "2020-03-05", "Bendamustine mono", "Chemotherapy"))
  off <- lot_w(eps)
  on  <- lot_w(eps, TRUE)
  expect_equal(sort(unique(off$line_of_therapy)), 1:2)   # default: unchanged, 2 lines
  expect_false("lot_family" %in% names(off))
  expect_equal(on$line_of_therapy, c(1L, 1L))
  expect_equal(unique(on$lot_family), "BV+Bendamustine")
  expect_equal(on$regimen_label, c("BV mono", "Bendamustine mono"))  # labels unchanged
})

test_that("combine_cross_type merges PD-1 mono + Salvage; starts within window count", {
  eps <- dplyr::bind_rows(
    make_ep_t("P1", 1, "2020-01-01", "2020-01-20", "PD-1 mono", "Immunotherapy"),
    make_ep_t("P1", 1, "2020-01-25", "2020-03-01", "Salvage", "Chemotherapy"))
  on <- lot_w(eps, TRUE)
  expect_equal(on$line_of_therapy, c(1L, 1L))
  expect_equal(unique(on$lot_family), "PD-1+Salvage")
})

test_that("combine_cross_type does not merge outside the window", {
  eps <- dplyr::bind_rows(
    make_ep_t("P1", 1, "2020-01-01", "2020-01-20", "BV mono", "Immunotherapy"),
    make_ep_t("P1", 1, "2020-02-15", "2020-04-01", "Salvage", "Chemotherapy"))
  on <- lot_w(eps, TRUE)
  expect_equal(on$line_of_therapy, c(1L, 2L))
  expect_equal(on$lot_family, c("BV mono", "Salvage"))
})

test_that("combine_cross_type leaves ABVD-family chemo alone (BV+AVD handled already)", {
  eps <- dplyr::bind_rows(
    make_ep_t("P1", 1, "2020-01-01", "2020-03-01", "BV mono", "Immunotherapy"),
    make_ep_t("P1", 1, "2020-01-02", "2020-03-01", "BV+AVD", "Chemotherapy"))
  on <- lot_w(eps, TRUE)
  expect_equal(on$lot_family[on$regimen_label == "BV+AVD"], "ABVD family")
  expect_equal(on$lot_family[on$regimen_label == "BV mono"], "BV mono")
})

test_that("combine_cross_type keeps the 365-day same-family restart rule", {
  eps <- dplyr::bind_rows(
    make_ep_t("P1", 1, "2020-01-01", "2020-02-01", "BV mono", "Immunotherapy"),
    make_ep_t("P1", 1, "2020-01-03", "2020-02-01", "Salvage", "Chemotherapy"),
    make_ep_t("P1", 2, "2020-06-01", "2020-07-01", "BV mono", "Immunotherapy"),
    make_ep_t("P1", 2, "2020-06-03", "2020-07-01", "Salvage", "Chemotherapy"),
    make_ep_t("P1", 3, "2021-09-01", "2021-10-01", "BV mono", "Immunotherapy"),
    make_ep_t("P1", 3, "2021-09-02", "2021-10-01", "Salvage", "Chemotherapy"))
  on <- lot_w(eps, TRUE)
  # 2020-06 restart is < 365 d after previous end -> same line; 2021-09 is > 365 d -> new
  expect_equal(on$line_of_therapy, c(1L, 1L, 1L, 1L, 2L, 2L))
  expect_true(all(on$lot_family == "BV+Salvage"))
})

test_that("combine_cross_type: patients are independent", {
  eps <- dplyr::bind_rows(
    make_ep_t("A", 1, "2020-01-01", "2020-02-01", "BV mono", "Immunotherapy"),
    make_ep_t("B", 1, "2020-01-02", "2020-02-01", "Salvage", "Chemotherapy"))
  on <- lot_w(eps, TRUE)
  expect_equal(on$lot_family, c("BV mono", "Salvage"))
})
