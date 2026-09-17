---
phase: 153-patient-zip-calendar-and-best-zip-selection
plan: "02"
subsystem: R/122_encounter_distance
tags: [distance, zip-calendar, zipcodeR, completeness-waterfall, qc]
dependency_graph:
  requires: [153-01]
  provides: [wired-compute-encounter-distance, completeness-waterfall-sheet, n-candidates-qc, script-index-registration]
  affects: [R/122_encounter_distance.R, R/SCRIPT_INDEX.md]
tech_stack:
  added: []
  patterns: [distance_status-keyed-waterfall, row-for-row-stopifnot-reconciliation, nearest-fill-sensitivity-reporting]
key_files:
  created: []
  modified:
    - R/122_encounter_distance.R
    - R/SCRIPT_INDEX.md
decisions:
  - "SECTION 6 res_zip9/res_zip5 references corrected to zip9_patient/zip5_patient (Phase 153 column rename)"
  - "Phase 152 fallback sensitivity row (res_match_fallback) replaced with nearest-fill days_offset distribution"
  - "completeness waterfall uses five independent counts (not waterfall subtraction) so row-for-row reconciliation stopifnot is unambiguous"
  - "E_completeness sheet inserted before QC sheet so KEY remains leftmost"
metrics:
  duration_minutes: 45
  completed_date: "2026-09-17"
  tasks_completed: 2
  files_modified: 2
---

# Phase 153 Plan 02: Wire compute_encounter_distance + Completeness Waterfall Summary

Wire `compute_encounter_distance()` (Plan 01) into `R/122_encounter_distance.R` by completing the Phase 153 SECTION 4 replacement, fixing all downstream stale column references introduced by the Phase 152 → Phase 153 column rename (res_zip9/res_zip5 → zip9_patient/zip5_patient), and adding a distance_status-keyed completeness waterfall sheet, n_candidates_in_range QC count, nearest-fill days_offset distribution, and utils_zip_calendar.R registration in SCRIPT_INDEX.md.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Replace SECTION 4 with calendar + compute_encounter_distance() | aff4874 | R/122_encounter_distance.R |
| 2 | Add completeness waterfall sheet + n_candidates_in_range QC + SCRIPT_INDEX registration | e9fc79d | R/122_encounter_distance.R, R/SCRIPT_INDEX.md |

## What Was Built

### Task 1: SECTION 4 wiring + downstream column-rename fixes

`R/122_encounter_distance.R` SECTION 1 already had `source("R/utils/utils_zip_calendar.R")` from Plan 01. The full SECTION 4 replacement was confirmed present. The following stale Phase 152 references were corrected throughout the file:

- **SECTION 6**: `encounters$res_zip9` → `encounters$zip9_patient`, `encounters$res_zip5` → `encounters$zip5_patient` (two sites: the ZIP9_CROSSWALK_AVAILABLE branch and the ZIP5-only fallback branch)
- **SECTION 7 enc_distance mutate**: Removed erroneous `distance_km_haversine = distance_km` overwrite (the correct haversine was already computed in the encounters mutate above; the old line silently overwrote it with the zipcodeR distance)
- **SECTION 8 comment**: Updated from `res_match_fallback` to `zip5_patient_source nearest-*`
- **SECTION 10 D_flags**: Replaced `res_zip9, res_zip5, res_match_type, res_match_fallback` with `zip5_facility, zip9_patient, zip5_patient, zip5_patient_source, days_offset, distance_mi, distance_status`
- **SECTION 11 unmatched_zip9**: `coalesce(enc_zip_norm, res_zip9, res_zip5)` → `coalesce(enc_zip_norm, zip9_patient, zip5_patient)`
- **SECTION 11 fallback sensitivity**: Replaced `res_match_fallback` filter with `zip5_patient_source %in% c("nearest_zip9","nearest_zip5")` filter; added `days_offset` distribution reporting
- **KEY sheet**: Updated Residence ZIP source, Distance method, provenance columns description, D_flags columns, QC contents

Fan-out assertion present:
```r
stopifnot(
  "compute_encounter_distance join fanned out -- review join keys" =
    nrow(encounters) == nrow(encounters_raw)
)
```

### Task 2: Completeness waterfall + QC rows + SCRIPT_INDEX

**Completeness waterfall (SECTION 11):**

Five-step waterfall keyed on `distance_status`, with five independent counts (not sequential subtractions) enabling a clean row-for-row reconciliation:
- `n_encounters_total` (raw DuckDB cohort ENCOUNTER before date filter)
- `n_admit_date_usable` (ADMIT_DATE non-missing and parseable)
- `n_with_facility_zip` (`sum(!is.na(enc_distance$zip5_facility))`)
- `n_with_in_range_patient_zip` (`zip5_patient_source %in% c("in_range_zip9","in_range_zip5")`)
- `n_with_nearest_patient_zip` (`zip5_patient_source %in% c("nearest_zip9","nearest_zip5")`)
- `n_distance_computed` (`distance_status == "computed"`)

Row-for-row reconciliation stopifnot (two assertions):
```r
stopifnot(
  "waterfall does not reconcile with distance_status counts" =
    n_status_computed == n_distance_computed,
  "distance_status categories do not sum to nrow(enc_distance)" =
    nrow(enc_distance) == (n_facility_missing + n_patient_missing +
                           n_zip_not_in_db    + n_status_computed)
)
```

**QC additions (SECTION 11):**
- `n_candidates_in_range > 1` count row: `sum(enc_distance$n_candidates_in_range > 1, na.rm = TRUE)` with note explaining pick_best_zip() ZIP9 > ZIP5 Zone-1 selection
- Nearest-fill days_offset distribution row: filters to `nearest_zip9 | nearest_zip5`, reports p25/p50/p75/min/max of `abs(days_offset)` via `quantile()`

**E_completeness sheet (SECTION 12):**

New sheet added via `add_styled_sheet()` before QC (so KEY remains leftmost):
- Main table: `completeness_tbl` (6-row waterfall)
- Subtable: `status_breakdown_tbl` (4-row distance_status breakdown with independently counted Ns)
- Sheet name: `E_completeness`

**SCRIPT_INDEX.md:**

Two entries updated:
1. `R/122_encounter_distance.R` entry: updated to reflect Phase 152/153 dual-phase description, compute_encounter_distance() wiring, new output columns, E_completeness sheet, added `utils/utils_zip_calendar` to Sources column
2. New `utils/utils_zip_calendar.R` entry added alongside `utils_address.R`: documents all three functions (`build_patient_zip_calendar`, `pick_best_zip`, `compute_encounter_distance`), D-04/D-05 two-zone ranking, distance_status values, and the explicit note that get_zip9_at_date() is kept in utils_address.R for Phase 139/141 consumers

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed stale res_zip9/res_zip5 column references throughout file**
- **Found during:** Task 1 — reading the file after Plan 01's SECTION 4 replacement
- **Issue:** Phase 153 SECTION 4 replaced `get_zip9_at_date()` output (res_zip9, res_zip5, res_match_type, res_match_fallback) with compute_encounter_distance() output (zip9_patient, zip5_patient, zip5_patient_source). Five downstream sites in SECTION 6, 8, 10, 11 still referenced the Phase 152 column names, which would have caused runtime `object not found` errors.
- **Fix:** Updated all five sites (SECTION 6 both branches, SECTION 8 comment, SECTION 10 D_flags select(), SECTION 11 unmatched_zip9 coalesce(), SECTION 11 fallback sensitivity filter)
- **Files modified:** R/122_encounter_distance.R
- **Commit:** aff4874

**2. [Rule 1 - Bug] Fixed erroneous distance_km_haversine = distance_km overwrite in enc_distance mutate**
- **Found during:** Task 1
- **Issue:** The `enc_distance <- encounters %>% dplyr::mutate(enc_zip_norm = ..., distance_km_haversine = distance_km)` line silently overwrote the SECTION 7 haversine result (already named `distance_km_haversine` in `encounters`) with `distance_km` from the zipcodeR dist_result join. The overwrite was then not selected anyway, so the net effect was a dead overwrite — but it was confusing and factually wrong as written.
- **Fix:** Removed the erroneous assignment; left a comment noting both columns exist in `encounters` from their respective sources
- **Files modified:** R/122_encounter_distance.R
- **Commit:** aff4874

## Known Stubs

None — all columns written to enc_distance are sourced from compute_encounter_distance() (real zipcodeR computation on HiPerGator) or from the encounter pull. The completeness waterfall and QC rows depend on distance_status, which is computed by compute_encounter_distance(). Runtime verification requires HiPerGator (DuckDB + LDS_ADDRESS_HISTORY + zipcodeR package).

## Self-Check: PASSED

- R/122_encounter_distance.R: FOUND
- R/SCRIPT_INDEX.md: FOUND
- 153-02-SUMMARY.md: FOUND
- Commit aff4874: FOUND (feat(153-02): wire compute_encounter_distance() into R/122 SECTION 4)
- Commit e9fc79d: FOUND (feat(153-02): add completeness waterfall sheet + n_candidates QC + SCRIPT_INDEX)
