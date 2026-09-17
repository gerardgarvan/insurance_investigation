---
phase: 153-patient-zip-calendar-and-best-zip-selection
plan: "01"
subsystem: utils
tags: [zip, calendar, distance, patient-zip, best-zip, DIST-02, DIST-03]
dependency_graph:
  requires:
    - R/utils/utils_address.R (normalize_zip9, normalize_zip5, is_sentinel_zip5)
    - Phase 152 (R/122_encounter_distance.R, zipcodeR in renv)
  provides:
    - R/utils/utils_zip_calendar.R (build_patient_zip_calendar, pick_best_zip, compute_encounter_distance)
  affects:
    - R/122_encounter_distance.R (Plan 02 will wire compute_encounter_distance in)
tech_stack:
  added: []
  patterns:
    - Pure functions defined before any probe gate (SECTION 1B convention from R/115)
    - D-04 two-zone arrange: in-range beats out-of-range; within in-range ZIP9 > ZIP5;
      within out-of-range rank by abs(days_offset) only (zip tier ignored)
    - D-05 tie-break: desc(days_offset) puts earlier period (positive offset) ahead
    - Distinct-pairs performance pattern for zip_distance() calls
    - facility_zip_missing classified first in case_when (no facility imputation)
key_files:
  created:
    - R/utils/utils_zip_calendar.R
  modified: []
decisions:
  - "D-04 two-zone arrange implemented exactly as specified: if_else(in_range, -zip_len, 0L)
    ascending puts ZIP9 (-9) before ZIP5 (-5) for in-range rows and applies 0 uniformly
    to out-of-range rows so their zip tier has no effect on ordering"
  - "All three functions written in a single file creation (not sequential appends) for
    consistency and to avoid partial-state commits; functionally identical to the plan's
    Task-1-then-Task-2 append design"
metrics:
  duration_minutes: 2
  completed_date: "2026-09-17"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 0
requirements_met: [DIST-02, DIST-03]
---

# Phase 153 Plan 01: Patient ZIP Calendar and Best-ZIP Selection — Summary

**One-liner:** `utils_zip_calendar.R` with three pure functions implementing AM rules 2–3: calendar-based patient ZIP with D-04 two-zone ZIP9/ZIP5 ranking, signed-integer days_offset provenance, and distinct-pairs zipcodeR distance with four-value distance_status set.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create utils_zip_calendar.R with build_patient_zip_calendar() and pick_best_zip() | 75ed764 | R/utils/utils_zip_calendar.R (created) |
| 2 | Add compute_encounter_distance() with distance_status classification | 75ed764 | R/utils/utils_zip_calendar.R (same commit — see Deviations) |

## Acceptance Criteria Verification

**Task 1:**
- `build_patient_zip_calendar <- function` — PASS
- `pick_best_zip <- function` — PASS
- `desc(in_range)` AND `abs(days_offset)` AND `desc(days_offset)` in same arrange region — PASS
- All four zip5_patient_source labels present — PASS (`in_range_zip9`, `in_range_zip5`, `nearest_zip9`, `nearest_zip5`)
- `n_candidates_in_range = sum(in_range)` — PASS
- `is_sentinel_zip5(zip5)` filter present — PASS
- `normalize_zip9 <- function` count in file = 0 — PASS (not redefined)
- `as.Date("2025-03-31")` present — PASS

**Task 2:**
- `compute_encounter_distance <- function` — PASS
- All four distance_status values present — PASS (`facility_zip_missing`, `patient_zip_missing`, `zip_not_in_db`, `computed`)
- `zip_distance(` and `units = "miles"` — PASS
- `distance_km = distance_mi * 1.609344` — PASS
- `distinct(zip5_patient, zip5_facility)` — PASS
- `facility_zip_missing` appears BEFORE `patient_zip_missing` in case_when — PASS

**Overall verification:**
- Exactly 3 top-level functions defined — PASS
- None of normalize_zip9/normalize_zip5/normalize_zip5_raw/is_sentinel_zip5 redefined — PASS
- `utils_address.R` untouched (`git diff --stat` shows no change) — PASS

## Deviations from Plan

### Auto-implementation adjustment (not a deviation from requirements)

**[Scope] All three functions written in a single Write operation**
- **Found during:** Task 1
- **Issue:** The plan structured Task 1 as "create with functions A and B" and Task 2 as "append function C". Given that all three functions are tightly interdependent (compute_encounter_distance calls pick_best_zip, which reads the calendar format), writing them together in one operation avoided an intermediate partial-state file. Both tasks' acceptance criteria are fully satisfied.
- **Fix:** Wrote all three functions in a single file creation. Task 2's acceptance criteria all pass via grep verification.
- **Files modified:** R/utils/utils_zip_calendar.R
- **Commit:** 75ed764 (covers both tasks)

## Known Stubs

None — the file contains no hardcoded empty values, placeholder text, or unconnected data sources. The functions are pure and testable; their connection to R/122 is Plan 02's responsibility.

## Self-Check: PASSED

- R/utils/utils_zip_calendar.R: FOUND
- Commit 75ed764: FOUND (`git log --oneline -1` confirms)
- utils_address.R unchanged: CONFIRMED (`git diff --stat` empty)
