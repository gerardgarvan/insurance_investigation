---
phase: 153-patient-zip-calendar-and-best-zip-selection
plan: "03"
subsystem: testing
tags: [testing, zip-calendar, smoke-test, unit-tests, phase-153]
dependency_graph:
  requires: [153-01]
  provides: [tests/testthat/test-utils-zip-calendar.R, R/88 Section 15ai]
  affects: [R/88_smoke_test_comprehensive.R, R/utils/utils_zip_calendar.R]
tech_stack:
  added: []
  patterns: [testthat unit tests with in-memory fixtures, R/88 check_N() counter pattern]
key_files:
  created:
    - tests/testthat/test-utils-zip-calendar.R
  modified:
    - R/88_smoke_test_comprehensive.R
decisions:
  - "Tests source R/00_config.R (which auto-loads utils_address.R) then source utils_zip_calendar.R explicitly, since it is not in the R/00_config.R auto-load list"
  - "Test 6 (patient_zip_missing via compute_encounter_distance) wrapped in skip_if_not_installed('zipcodeR') as a safety net; Tests 1-5,7,8 exercise build_patient_zip_calendar/pick_best_zip only and are never skipped"
  - "Section 15ai added immediately after Section 15ah following the check_N()/p153_pass/p153_fail counter pattern exactly"
metrics:
  duration_minutes: 18
  completed_date: "2026-09-17"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 1
requirements_completed: [DIST-07]
---

# Phase 153 Plan 03: Unit Tests and R/88 Section 15ai Summary

**One-liner:** 8 computed-value testthat assertions locking D-04 two-zone ranking and D-05 tie-break behavior, plus 14-check R/88 Section 15ai structural guard for the utils_zip_calendar.R module.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Write test-utils-zip-calendar.R (8 test_that blocks) | 2c47ed6 | tests/testthat/test-utils-zip-calendar.R |
| 2 | Add R/88 Section 15ai Phase 153 structural checks | ef7263b | R/88_smoke_test_comprehensive.R |

## What Was Built

### Task 1: tests/testthat/test-utils-zip-calendar.R

8 `test_that` blocks covering all three functions with small in-memory frames — no HiPerGator data required:

- **Test 1 (duplicate collapse):** Two identical `(ID, ZIP, period)` rows produce exactly `nrow == 1L` from `build_patient_zip_calendar()`.
- **Test 2 (overlap merge):** Two overlapping same-ZIP periods merge to `start = min(start)`, `end = max(end)`.
- **Test 3 (ZIP9 wins in-range, D-04):** An encounter covered by both a ZIP5 and a ZIP9 period picks `zip5_patient_source == "in_range_zip9"` with `n_candidates_in_range == 2L`.
- **Test 4 (D-05 tie-break, equal offsets):** Two out-of-range periods at equal `|days_offset|` (one 5 days before, one 5 days after) picks the earlier (positive offset) period — asserts `days_offset > 0`.
- **Test 5 (in-range ZIP5 beats out-of-range ZIP9):** `zip5_patient_source == "in_range_zip5"` when the ZIP5 covers the admit date and the ZIP9 does not.
- **Test 6 (patient_zip_missing):** `compute_encounter_distance()` for a patient with no calendar rows yields `distance_status == "patient_zip_missing"`. Wrapped in `skip_if_not_installed("zipcodeR")`; the empty-`pairs` path never calls `zip_distance()` with real ZIPs.
- **Test 7 (open period closes at 2025-03-31):** `NA ADDRESS_PERIOD_END` produces `end == as.Date("2025-03-31")`.
- **Test 8 (out-of-range: ZIP tier ignored, D-04 Zone 2):** Nearer-in-time ZIP5 period beats farther-in-time ZIP9 period in Zone 2 — `zip5_patient_source == "nearest_zip5"`.

Sourcing convention follows `test-utils-address.R`'s `withr::with_dir(.project_root, source("R/00_config.R"))` pattern, then sources `utils_zip_calendar.R` explicitly.

### Task 2: R/88 Section 15ai (14 checks)

Added immediately after Section 15ah, using the `check_152()` / `p152_pass` / `p152_fail` counter pattern exactly. Checks (all grep/file-existence, no HiPerGator data):

1. `R/utils/utils_zip_calendar.R` exists
2. `build_patient_zip_calendar` defined exactly once
3. `pick_best_zip` defined exactly once
4. `compute_encounter_distance` defined exactly once
5. `normalize_zip9 <- function` NOT in `utils_zip_calendar.R` (avoids shadowing `utils_address.R`)
6. Two-zone arrange present: `desc(in_range)`, `abs(days_offset)`, `desc(days_offset)`
7. All four `zip5_patient_source` labels present
8. All four `distance_status` labels present
9. R/122 sources `utils_zip_calendar.R`
10. R/122 calls `compute_encounter_distance()`
11. R/122 does NOT call `res_lookup <- get_zip9_at_date` (old lookup replaced)
12. R/122 reports `n_candidates_in_range > 1` (QC)
13. `tests/testthat/test-utils-zip-calendar.R` exists
14. `utils_zip_calendar` present in `R/SCRIPT_INDEX.md`

`SMOKE-153-01` footer line added to Section 16 summary block.

## Verification

- `test-utils-zip-calendar.R` contains 8 `test_that(` blocks (confirmed via grep)
- All asserted values present: `in_range_zip9`, `in_range_zip5`, `nearest_zip5`, `as.Date("2025-03-31")`, `days_offset > 0`, `patient_zip_missing`, all three function names
- R/88 Section 15ai grep checks pass: `Section 15ai`, `check_153`, `p153_pass`, `p153_fail`, `SMOKE-153-01`, `message(glue("\nSection 15ai: {p153_pass} PASS, {p153_fail} FAIL"))`
- `Rscript` unavailable in Windows environment — execution of `testthat::test_file()` deferred to HiPerGator run

## Deviations from Plan

None — plan executed exactly as written. The Section 15ah pattern was copied precisely (counter initialization, `check_N()` helper definition, `read_or_null()` for file loads, closing `message(glue(...))` line).

## Self-Check: PASSED

- FOUND: tests/testthat/test-utils-zip-calendar.R
- FOUND: .planning/phases/153-patient-zip-calendar-and-best-zip-selection/153-03-SUMMARY.md
- FOUND: commit 2c47ed6 (test task 1)
- FOUND: commit ef7263b (feat task 2)
