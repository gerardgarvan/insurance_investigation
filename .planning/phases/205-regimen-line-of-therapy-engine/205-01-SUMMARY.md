---
phase: 205-regimen-line-of-therapy-engine
plan: "01"
subsystem: regimen-classification
tags: [regimen, lot, utils, config, unit-tests]
dependency_graph:
  requires: []
  provides: [assign_regimen, assign_lot, REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS, LOT_GAP_DAYS]
  affects: [R/utils/utils_regimen.R, R/00_config.R]
tech_stack:
  added: [utils_regimen.R]
  patterns: [pure-function-utils, named-predicate-pattern, testthat-synthetic-data]
key_files:
  created:
    - R/utils/utils_regimen.R
    - tests/testthat/test-205-regimen-dict.R
    - tests/testthat/test-205-lot-counter.R
  modified:
    - R/00_config.R
decisions:
  - "REGIMEN_DICT uses Title Case drug names matching DRUG_NAME_ALIASES values (not underscore-lowercase as shown illustratively in the plan)"
  - "LOT_GAP_DAYS = 90L (open REGL-06 — confirm with SME)"
  - "CONCURRENCY_WINDOW_DAYS = 7L (REGL-02)"
  - "MAINTENANCE_DRUG_CLASSES = c(BV_consolidation, Rituximab_mono)"
  - "Test files define fallback constants locally when R/00_config.R cannot fully load in local test environment"
metrics:
  duration_minutes: 15
  completed_date: "2026-11-14"
  tasks_completed: 3
  tasks_total: 3
  files_created: 3
  files_modified: 1
---

# Phase 205 Plan 01: Regimen + LOT Config and Utils Summary

**One-liner:** Pure-function regimen classifier (10-family REGIMEN_DICT) and LOT counter (gap, post-SCT, maintenance rules) added to R/utils/utils_regimen.R and R/00_config.R, with 14 passing unit tests.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add regimen config constants to R/00_config.R | 36ca42c | R/00_config.R |
| 2 | Create R/utils/utils_regimen.R | 77b6b87 | R/utils/utils_regimen.R |
| 3 | Write unit tests | ae49cae | tests/testthat/test-205-regimen-dict.R, test-205-lot-counter.R |

## What Was Built

**R/00_config.R** — appended Phase 205 config block:
- `CONCURRENCY_WINDOW_DAYS <- 7L` (REGL-02)
- `LOT_GAP_DAYS <- 90L` (REGL-03; open REGL-06)
- `MAINTENANCE_DRUG_CLASSES <- c("BV_consolidation", "Rituximab_mono")`
- `REGIMEN_DICT` — 10-entry named list (ABVD, AVD, BV+AVD, Nivo+AVD, BEACOPP, escBEACOPP, Pediatric, NLPHL, Salvage, BV_consolidation)

**R/utils/utils_regimen.R** — new utility module (auto-sourced via R/00_config.R):
- `match_regimen_family(canonical_drugs, family_def)` — internal; inclusive and exclusive matching
- `assign_regimen(date_level_df, regimen_dict, window_days)` — episode-level regimen labeling; processes Immunotherapy rows (REGL-04)
- `assign_lot(episode_df, lot_gap_days, maintenance_classes, sct_dates_df)` — LOT counter with gap, post-SCT, and maintenance rules; NULL-safe SCT handling

**Unit tests** — 14 test_that blocks across two files; all pass locally:
- test-205-regimen-dict.R (8 blocks): ABVD, AVD, BV+AVD, NLPHL, Salvage, Other, exclusive flag, window enforcement
- test-205-lot-counter.R (6 blocks): single episode, gap < threshold, gap >= threshold, post-SCT, maintenance-inherit, three-line patient

## Verification

```
tools/rcheck.sh parse R/00_config.R R/utils/utils_regimen.R \
  tests/testthat/test-205-regimen-dict.R tests/testthat/test-205-lot-counter.R
# → 4 files parsed, 0 failed

tools/rcheck.sh test 205
# → files: 2 | expectations failed: 0 | errors: 0 | skipped: 0
```

## Deviations from Plan

**1. [Rule 1 - Adaptation] Drug name canonical format**
- **Found during:** Task 2
- **Issue:** Plan's REGIMEN_DICT code block showed underscore-lowercase drug names (e.g., `"brentuximab_vedotin"`), but `DRUG_NAME_ALIASES` values are Title Case with spaces (e.g., `"Brentuximab Vedotin"`). Using plan's format would cause all BV-containing regimens to fail to match.
- **Fix:** Used actual DRUG_NAME_ALIASES values (Title Case). `assign_regimen()` performs case-insensitive matching so the lookup is robust to case variation.
- **Files modified:** R/00_config.R, R/utils/utils_regimen.R

**2. [Rule 2 - Missing functionality] Test-time fallback constants**
- **Found during:** Task 3
- **Issue:** `helper-utils.R` sources all utils/*.R files but not R/00_config.R, so REGIMEN_DICT / LOT_GAP_DAYS / CONCURRENCY_WINDOW_DAYS are unavailable in the test environment when config fails to source (data files absent locally).
- **Fix:** Each test file defines fallback constants if config sourcing fails. Fallback values match canonical config values exactly — this is a test-environment-only workaround, not a weakening of assertions.
- **Files modified:** tests/testthat/test-205-regimen-dict.R, tests/testthat/test-205-lot-counter.R

## Known Stubs

None. No pipeline scripts modified. Functions are pure logic; data wiring happens in Plan 02.

## Open Items Carried Forward

- REGL-06: SME confirmation needed for LOT_GAP_DAYS (90d default), escBEACOPP vs BEACOPP dose distinction, Pediatric regimen drugs, and Salvage drug set.
- Plan 02: Wire assign_regimen() and assign_lot() into R/28 and R/142.
- Plan 03: Pipeline script using the LOT engine end-to-end.

## Self-Check: PASSED

Files confirmed present:
- R/utils/utils_regimen.R — FOUND
- tests/testthat/test-205-regimen-dict.R — FOUND
- tests/testthat/test-205-lot-counter.R — FOUND

Commits confirmed:
- 36ca42c (Task 1 — R/00_config.R)
- 77b6b87 (Task 2 — utils_regimen.R)
- ae49cae (Task 3 — test files)
