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

# ── REGL-03: Post-SCT episode increments regardless of gap ────────────────────
test_that("REGL-03: Post-SCT episode increments LOT regardless of gap length", {
  df <- dplyr::bind_rows(
    make_ep("P001", 1, "2022-01-01", "2022-04-01", "ABVD"),
    make_ep("P001", 2, "2022-05-01", "2022-08-01", "BV_consolidation")  # gap = 30 days
  )
  sct <- tibble::tibble(ID = "P001", sct_date = as.Date("2022-04-15"))
  result <- assign_lot(df, lot_gap_days = LOT_GAP_DAYS,
                       maintenance_classes = character(0),  # not maintenance for this test
                       sct_dates_df = sct)
  # Episode 2 starts after SCT → line 2
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

# ── REGL-03: Three-line patient ───────────────────────────────────────────────
test_that("REGL-03: Three-line patient — gap + SCT + gap → lines 1, 2, 3", {
  df <- dplyr::bind_rows(
    make_ep("P001", 1, "2021-01-01", "2021-06-01", "ABVD"),          # LOT 1
    make_ep("P001", 2, "2021-11-01", "2022-02-01", "Salvage"),       # gap 153d → LOT 2
    make_ep("P001", 3, "2023-01-01", "2023-04-01", "BV_consolidation")  # post-SCT → LOT 3
  )
  sct <- tibble::tibble(ID = "P001", sct_date = as.Date("2022-06-01"))
  result <- assign_lot(df, lot_gap_days = LOT_GAP_DAYS,
                       maintenance_classes = character(0),  # not maintenance for ep3
                       sct_dates_df = sct)
  expect_equal(result$line_of_therapy, c(1L, 2L, 3L))
})
