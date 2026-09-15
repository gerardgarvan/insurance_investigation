---
phase: 152-encounter-zip-to-residence-distance
plan: "02"
subsystem: encounter-distance
tags: [geospatial, encounter, haversine, centroid, zip-resolution]
dependency_graph:
  requires: [152-01]
  provides: [R/122 SECTION 1-7 encounter-distance engine]
  affects: [152-03]
tech_stack:
  added: []
  patterns:
    - "level_from_source() pure helper: centroid_source -> zip9|zip5 basis label"
    - "ZIP9_CROSSWALK_AVAILABLE flag: probe gate 2 degrades instead of blocking"
    - "Fan-out stopifnot after get_zip9_at_date() left_join"
key_files:
  created:
    - R/122_encounter_distance.R (SECTION 1-7 only; SECTION 8-12 in Plan 03)
  modified: []
decisions:
  - "FACILITY_LOCATION (not ZIP/ZIPCODE) is the encounter-side ZIP column"
  - "get_zip9_at_date() result joined on (ID, ADMIT_DATE=query_date), never cbind"
  - "level_from_source() derives distance_basis level from centroid_source, not from zip9 string presence — a ZIP9 that fell back to gazetteer is zip5 basis"
  - "ZIP9 crosswalk probe gate is non-blocking: sets ZIP9_CROSSWALK_AVAILABLE=FALSE and resolves everything at ZIP5 level"
metrics:
  duration_minutes: 25
  completed_date: "2026-09-15"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 0
---

# Phase 152 Plan 02: Encounter-Distance Computational Core Summary

**One-liner:** R/122 SECTION 1–7 built with FACILITY_LOCATION encounter pull, get_zip9_at_date joined on (ID, query_date) with fan-out stopifnot, both-side centroid resolution via get_zip_centroid(), haversine_km distance, and all four distance_basis labels.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | SECTION 1-2 — header, setup, SECTION 1B, probe gates | 8298cbd | R/122_encounter_distance.R |
| 2 | SECTION 3-7 — encounter pull, residence resolution, ZIP normalization, centroid resolution, distance | 8298cbd | R/122_encounter_distance.R |

Note: Both tasks committed in a single atomic commit since the file is a single unit (Task 1 created the file scaffold, Task 2 completed it; written as one Write operation).

## What Was Built

`R/122_encounter_distance.R` SECTION 1 through SECTION 7, producing the `enc_distance` encounter-level tibble in memory. Plan 03 will consume it for SECTION 8–12 (patient summary, distribution, flags, QC waterfall, xlsx assembly + rds write).

### SECTION 1B: Pure Helper

`level_from_source(src)` — maps `centroid_source` strings to `"zip9"` or `"zip5"` basis label for `distance_basis`. Defined before probe gates so it is testable in a no-HiPerGator context. Not file I/O.

### SECTION 2: Three Probe Gates

| Gate | File / Resource | Behavior on Absence |
|------|-----------------|---------------------|
| 1 (ZCTA gazetteer) | `CONFIG$zcta_gazetteer_path` | `stop()` with Census URL |
| 2 (ZIP9 crosswalk) | `CONFIG$zip9_bg_centroid_path` | `warning()` + `ZIP9_CROSSWALK_AVAILABLE <- FALSE` (degrading) |
| 3 (DuckDB ENCOUNTER) | `get_pcornet_table("ENCOUNTER")` | `stop()` with connection message |

Gate 2's degraded path resolves all centroids at ZIP5 level only; `distance_basis` will only contain `"zip5-zip5"` in that run.

### SECTION 3: Encounter Pull

- `FACILITY_LOCATION` is the sole ZIP-like column (no `ZIP`, `ZIPCODE`, or `FACILITY_ZIP`)
- `n_enc_cohort_raw` captured before date filters (QC waterfall row 1)
- `n_enc_admit_missing` computed after both date filters (QC waterfall row 2)
- Column kept as `ID` (not renamed to PATID) to match `get_zip9_at_date()` contract

### SECTION 4: Residence Resolution

- `get_zip9_at_date(encounters_raw$ID, encounters_raw$ADMIT_DATE)` returns distinct (ID, query_date)
- Joined via `left_join(..., by = c("ID" = "ID", "ADMIT_DATE" = "query_date"))` — never cbind
- `stopifnot(nrow(encounters) == nrow(encounters_raw))` guards against fan-out

### SECTION 5: Encounter ZIP Normalization

- `normalize_zip9(enc_zip_raw)` → `enc_zip9`
- `normalize_zip5_raw(enc_zip_raw)` → `enc_zip5` (free-text safe)
- Logged: `n_enc_with_norm_zip9`, `n_enc_with_norm_zip5`, `n_enc_zip_na`

### SECTION 6: Centroid Resolution

- When `ZIP9_CROSSWALK_AVAILABLE` is TRUE: encounter side prefers ZIP9, falls back to ZIP5; residence side likewise via `get_zip_centroid()`
- When `ZIP9_CROSSWALK_AVAILABLE` is FALSE: both sides resolved at ZIP5 only (all `centroid_source` values `"zip5_gazetteer"` or `"zip5_fallback"`)
- `enc_level` / `res_level` derived from `centroid_source` via `level_from_source()`, not from zip9 string presence

### SECTION 7: Distance Computation

- `distance_km = haversine_km(enc_lat, enc_lon, res_lat, res_lon)` (from utils_address.R)
- `distance_basis` covers all four combinations: `"zip9-zip9"`, `"zip9-zip5"`, `"zip5-zip9"`, `"zip5-zip5"`
- `enc_distance` tibble assembled with exact A_encounter_distance columns: `ID, ENCOUNTERID, ADMIT_DATE, enc_zip_norm, res_zip9, res_zip5, res_match_type, res_match_fallback, distance_km, distance_basis, enc_centroid_source, res_centroid_source`
- No output written (deferred to Plan 03)

## Deviations from Plan

None — plan executed exactly as written. The two tasks were implemented in one Write call (no deviation from plan intent; both tasks describe the same file, with Task 1 defining the first four sections and Task 2 defining sections 3–7 which continue the same file). Both tasks verified via grep acceptance criteria before commit.

## Known Stubs

None — `enc_distance` is an in-memory tibble with no hardcoded values. All data flows from DuckDB + reference files at runtime. Plan 03 will add the xlsx/rds output.

## Rscript Verification Note

`Rscript` is not available in this Windows planning environment. Structural verification was performed via grep-based acceptance criteria checks. All acceptance criteria passed:

- `enc_zip_raw = FACILITY_LOCATION` present (line 187)
- `cbind` appears only in anti-pattern comments (lines 206–207), not in code
- Join key `"ADMIT_DATE" = "query_date"` present (line 218)
- `stopifnot(nrow(encounters) == nrow(encounters_raw))` present (line 232)
- `haversine_km(enc_lat, enc_lon, res_lat, res_lon)` present (line 422)
- All four distance_basis values present (lines 424–427)
- `wb_workbook`, `saveRDS`, `wb_save` count = 0 (no output writing)
- `level_from_source` defined in SECTION 1B and used in SECTION 6
- `n_enc_cohort_raw` present (line 180)
- `haversine_km <- function` / `get_zip_centroid <- function` count = 0 (not redefined)

True R parse check is deferred to the first HiPerGator run.

## Self-Check: PASSED

- [x] `R/122_encounter_distance.R` exists
- [x] Commit `8298cbd` present in git log
- [x] All Task 1 acceptance criteria matched via grep
- [x] All Task 2 acceptance criteria matched via grep
- [x] No output files written (saveRDS / wb_save count = 0)
