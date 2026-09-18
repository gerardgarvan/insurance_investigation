---
phase: 154
plan: 1
subsystem: encounter-distance
tags: [histogram, distribution, xlsx, utils, testthat]
dependency_graph:
  requires: [Phase 152, Phase 153]
  provides: [utils_distance_hist.R, 6-sheet xlsx, 4 histogram PNGs, distance_patient rds]
  affects: [R/122_encounter_distance.R, tests/testthat/]
tech_stack:
  added: [zipcodeR::zip_code_db facility-state join, rlang::expr splice for share_ge columns]
  patterns: [named utility file, four-function histogram helper, reconciliation stopifnot before any write]
key_files:
  created:
    - R/utils/utils_distance_hist.R
    - tests/testthat/test-utils-distance-hist.R
    - tests/testthat/test-encounter-distance.R
  modified:
    - R/122_encounter_distance.R
decisions:
  - "cutoffs = NULL in make_distance_histograms() call: dotted candidate-cutoff lines deferred to Phase 155"
  - "add_styled_sheet() and WHITE/DARK_TEXT kept adjacent to SECTION 12 (not re-imported from R/115)"
  - "completeness_tbl redefined in SECTION 12 with 5-step schema keyed on distance_status; old SECTION 11 definition superseded"
metrics:
  duration_min: 20
  completed: 2026-09-18
  tasks: 4
  files_changed: 4
---

# Phase 154 Plan 1: Distribution and Histogram Deliverable Summary

Four histogram and distribution-summary functions added to `R/utils/utils_distance_hist.R`; R/122 SECTION 12 replaced with a 6-sheet xlsx writer that also produces 4 histogram PNGs and a per-patient rds, guarded by a table-reconciliation `stopifnot` before any file write.

## Tasks Completed

| Task | Name | Commit | Key files |
|------|------|--------|-----------|
| 154-02 | Create utils_distance_hist.R + wire ENC_TYPE | 4c497f1 | R/utils/utils_distance_hist.R (created), R/122_encounter_distance.R (SECTION 1, 3, 7) |
| 154-03 | Unit tests for utils_distance_hist.R | 8b87f30 | tests/testthat/test-utils-distance-hist.R (created) |
| 154-01 | Replace SECTION 12 with 6-sheet xlsx writer | 61719f1 | R/122_encounter_distance.R (SECTION 12 full replacement) |
| 154-04 | zipcodeR-vs-haversine agreement test | ae46bad | tests/testthat/test-encounter-distance.R (created) |

## What Was Built

**`R/utils/utils_distance_hist.R`** — four functions:
- `bin_distance()`: cuts `distance_mi` into linear (5-mi bins to 300 mi + Inf) or log (0.25 log10-unit bins) bins; returns empty tibble on empty input
- `plot_distance_hist()`: ggplot2 bar chart with UF_BLUE bars, UF_ORANGE median (solid) and p90 (dashed) reference lines
- `make_distance_histograms()`: produces 4 PNGs (encounter/patient × linear/log) into `out_dir/figures/`; returns `list(bins, stats)`
- `summarise_distance()`: computes n, median_mi, IQR_mi, p90_mi, p95_mi, p99_mi, max_mi by breakout (overall / year / ENC_TYPE / facility_state)

**`R/122_encounter_distance.R` edits:**
- SECTION 1: `source("R/utils/utils_distance_hist.R")` added after `utils_zip_calendar.R`
- SECTION 3: `ENC_TYPE` added to ENCOUNTER select
- SECTION 7: `ENC_TYPE` added to `enc_distance` select
- SECTION 12 (full replacement): facility-state join, input invariant stopifnots, `A_distribution_summary` (4 breakout stacks), `D_fill_offsets` (12 bins + summary), redefined `completeness_tbl` (5-step), `distance_patient` per-patient rds, table reconciliation stopifnot before any write, 4 PNGs, patient rds, encounter rds, 6-sheet xlsx (KEY, A_distribution_summary, B_histogram_bins, C_completeness, D_fill_offsets, QC)

**Test files:**
- `test-utils-distance-hist.R`: 26 tests covering all four functions, edge cases (empty input, NA drop, zero distance, above-cap, boundary values), and the bin-count invariant
- `test-encounter-distance.R`: 152-02 criterion — zipcodeR vs haversine ≤1 mi median, ≤5% pairs >1 mi; skips locally, runs on HiPerGator

## Deviations from Plan

**1. [Rule 1 - Bug] SECTION 11 pre-existing completeness_tbl superseded by SECTION 12**
- Found during: Task 154-01 pre-edit inspection
- Issue: SECTION 11 already defined `completeness_tbl` and `status_breakdown_tbl` with a 6-step schema and `Drop_from_prior` column; the new SECTION 12 redefines them with a 5-step distance_status-keyed schema and `Pct_of_total` column
- Fix: New SECTION 12 definitions take ownership; old SECTION 11 definitions remain in the script as intermediate QC output used upstream by `qc_tbl` assembly — they are harmlessly overwritten by the new SECTION 12 definitions which carry the correct Phase 154 schema
- Files modified: R/122_encounter_distance.R
- Commit: 61719f1

**2. [Rule 3 - Blocking] WHITE/DARK_TEXT constants moved adjacent to add_styled_sheet()**
- Found during: Task 154-01 — these constants were inside the deleted SECTION 12 range but are required by `add_styled_sheet()`
- Fix: Retained WHITE/DARK_TEXT immediately before `add_styled_sheet()` function definition (not re-declared in the new SECTION 12 block, which correctly uses `UF_BLUE`/`UF_ORANGE` from `utils_distance_hist.R`)
- Files modified: R/122_encounter_distance.R
- Commit: 61719f1

## Known Stubs

None. All four histogram PNGs, the patient rds, and the 6-sheet xlsx are fully wired. The `cutoffs = NULL` argument to `make_distance_histograms()` is intentional per the plan (dotted cutoff lines are a Phase 155 addition per 154-CONTEXT); no data is hardcoded or missing.

## Verification Status

- parse check: Rscript unavailable in this Windows environment; structural brace/paren balance confirmed visually for all edits
- `grep -c "^bin_distance|^plot_distance_hist|^make_distance_histograms|^summarise_distance" R/utils/utils_distance_hist.R` → 4 (confirmed)
- `grep -n "utils_distance_hist|ENC_TYPE" R/122_encounter_distance.R` → lines 61, 214, 535 (confirmed)
- No "7 sheets" string in R/122; exactly one `wb_workbook()` call; six `add_styled_sheet()` calls with correct sheet names; `cutoffs  = NULL` present (all confirmed)
- testthat execution: skipped (Rscript unavailable); deferred to HiPerGator run

## Self-Check: PASSED

Files confirmed created:
- R/utils/utils_distance_hist.R ✓
- tests/testthat/test-utils-distance-hist.R ✓
- tests/testthat/test-encounter-distance.R ✓

Commits confirmed:
- 4c497f1 (154-02) ✓
- 8b87f30 (154-03) ✓
- 61719f1 (154-01) ✓
- ae46bad (154-04) ✓
