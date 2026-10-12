---
phase: 177-needs-temporal-match-sizing-memo
plan: 01
subsystem: distance-analysis
tags: [zip, temporal-match, sizing, investigation, read-only]
dependency_graph:
  requires: [R/121 zip_problem_inventory RDS, R/122 encounter_distance RDS, DuckDB ENCOUNTER + LAB_RESULT_CM]
  provides: [temporal_match_sizing_YYYYMMDD.xlsx, temporal_match_sizing_encounters_YYYYMMDD.rds]
  affects: [Phase 177 Plan 02 memo, decision on NEEDS_TEMPORAL_MATCH handling]
tech_stack:
  added: []
  patterns: [build_enc_analysis replication, zipcodeR::zip_distance projection, get_zip9_at_date temporal lookup]
key_files:
  created: [R/177_temporal_match_sizing.R]
  modified: [R/39_run_all_investigations.R, R/SCRIPT_INDEX.md]
decisions:
  - "Used openxlsx (not openxlsx2) matching R/165 convention"
  - "Distance projection uses zipcodeR::zip_distance() on distinct ZIP5 pairs — exact R/122 method"
  - "NEEDS_TEMPORAL_MATCH context row built from enc_now (Phase 165 set) filtered to those patient IDs"
  - "r121_pinned left as empty string; operator sets R177_R121_RDS or updates the variable before HiPerGator run"
metrics:
  duration: ~30 min
  completed: 2026-10-12
  tasks: 3
  files: 3
---

# Phase 177 Plan 01: Temporal Match Sizing Script — Summary

## One-liner

Read-only R/177 investigation script that replicates Phase 165's analysis set, runs a temporal ZIP lookup on patient_zip_missing candidates, projects distances via R/122's own zipcodeR method, and applies the locked D-03 tier rule with a D-04 cross-tab.

## What Was Built

`R/177_temporal_match_sizing.R` — a read-only investigation script that:

1. Loads R/121 and R/122 RDS inputs (pinned or most-recent by mtime, with env-var overrides).
2. Replicates the Phase 165 analysis set exactly: `build_enc_analysis(enc_distance, cbc_events, anchors, enc_dates_for_build, CUTOFF)` — same function, same arguments, same CUTOFF.
3. Isolates `patient_zip_missing` encounters satisfying all other R/165 filters (candidate set).
4. Attaches R/121 triage to candidates via `PATID`/`ID` join; `NA` → "not in R/121".
5. Builds a context row: all Phase 165 analysis encounters belonging to NEEDS_TEMPORAL_MATCH patients.
6. Runs `get_zip9_at_date()` on distinct `(ID, Date)` keys; asserts row count unchanged after join.
7. Sets `coverable = match_type == "interval" & !is.na(ZIP5_matched)`.
8. Projects distances for coverable rows via `zipcodeR::zip_distance()` on distinct ZIP5 pairs (exact R/122 method from `compute_encounter_distance()`).
9. Computes whole-record and post-anchor shares and far-ratios; applies the locked D-03 rule.
10. Produces the D-04 cross-tab (R/122 patient_zip_missing patients × R/121 triage).
11. Writes `output/temporal_match_sizing_YYYYMMDD.xlsx` (KEY, A_counts, B_by_triage, C_d04_crosstab) and `output/internal/temporal_match_sizing_encounters_YYYYMMDD.rds`.

Registered in `R/39_run_all_investigations.R` and `R/SCRIPT_INDEX.md`.

## Real Column Names and Signatures Discovered (Task 1)

### R/121 RDS

- **Path pattern**: `output/zip_problem_inventory_YYYYMMDD.rds`
- **Elements**: `$patients`, `$roster`, `$flag_summary`, `$triage_summary`, `$record_mismatches`, `$reconciliation`, `$qc`
- **Patient key column**: `PATID` (standardized from `ID` or `PATID` depending on CSV column)
- **Triage column**: `triage`
- **Triage values**:
  - `NO_MISSING_ZIP5` — no missing ZIP5 records
  - `SAME_ROW_BACKFILL_ALL` — every missing-ZIP5 row has a same-row ZIP9
  - `SAME_ROW_BACKFILL_PARTIAL` — some same-row backfill, rest need temporal matching
  - `NEEDS_TEMPORAL_MATCH` — `F05_other_row_zip9_only`: has missing ZIP5 + usable ZIP9, but NOT on the same row as the missing-ZIP5 records
  - `UNREACHABLE_NO_ZIP9` — no usable ZIP9 anywhere

### R/122 RDS

- **Path pattern**: `output/encounter_distance_YYYYMMDD.rds`
- **Key columns**: `ID`, `ENCOUNTERID`, `ADMIT_DATE` (Date), `enc_zip_raw`, `enc_zip9`, `enc_zip5`, `zip9_patient`, `zip5_patient`, `zip5_patient_source`, `days_offset`, `n_candidates_in_range`, `zip5_facility`, `distance_mi`, `distance_km`, `distance_status`
- **`patient_zip_missing`** = `distance_status == "patient_zip_missing"` (no address history for patient; classified AFTER `facility_zip_missing`)
- **`distance_status` values**: `{computed, facility_zip_missing, patient_zip_missing, zip_not_in_db}`

### R/122 distance method (from `utils_zip_calendar.R`)

```r
# compute_encounter_distance() calls pick_best_zip(), then:
pairs <- out |> distinct(zip5_patient, zip5_facility) |>
  filter(!is.na(zip5_patient), !is.na(zip5_facility))
zd <- zip_distance(pairs$zip5_patient, pairs$zip5_facility, units = "miles")
pairs$distance_mi <- zd$distance
```

R/177 reuses this identically on distinct `(ZIP5_matched, zip5_facility)` pairs.

### `build_enc_analysis()` signature

```r
build_enc_analysis(enc_distance, cbc_events, anchors, enc_dates, cutoff)
```

- `enc_distance`: R/122 tibble — must have `ID`, `ENCOUNTERID`, `ADMIT_DATE` (Date), `distance_mi`, `distance_status`
- `cbc_events`: `tibble(ID, cbc_date)` from `build_cbc_events()`
- `anchors`: `tibble(ID, hl_anchor_date)` from `get_hl_any_dx_ids()`
- `enc_dates`: `tibble(ENCOUNTERID, DISCHARGE_DATE, SOURCE)` from DuckDB ENCOUNTER
- `cutoff`: `CONFIG$far_from_care_cutoff_mi`
- **Keeps**: `distance_status == "computed"` + inner join on anchor date
- **Returns**: `ID, ENCOUNTERID, ADMIT_DATE, ENC_TYPE, SOURCE, distance_mi, far_from_care_100mi (int), post_anchor (int), cbc_in_encounter (int)`
- **post_anchor**: `as.integer(ADMIT_DATE > hl_anchor_date)` — anchor day is pre-anchor

### `get_zip9_at_date()` signature

```r
get_zip9_at_date(ids, dates, addr_full = NULL)
```

- `ids`: character vector of patient IDs
- `dates`: Date vector, parallel to `ids`
- Returns `tibble(ID, query_date, ZIP9, ZIP5, match_type)`
- **One row per DISTINCT (ID, query_date)** — NOT parallel to input
- **Callers MUST join** on `c("ID", "query_date")`
- `match_type` values: `"interval"` | `"most_recent_before"` | `"none"`
- `ZIP5` column name in output = `ZIP5` (renamed to `ZIP5_matched` in R/177 to avoid collision)

### `suppress_small_vec()` signature

```r
suppress_small_vec(n)   # returns NA_integer_ for counts 1-10; 0 and >10 unchanged
```

### Workbook package

R/165 uses `openxlsx` (not openxlsx2). R/177 matches.

## Verification Grep Results

All greps run after writing R/177_temporal_match_sizing.R:

| Check | Expected | Observed |
|-------|----------|----------|
| `source("R/00_config.R")` | 1 | 1 |
| `build_enc_analysis` | >= 1 | 7 |
| `get_zip9_at_date` | >= 1 | 5 |
| `stopifnot(nrow(cand) == n0)` | 1 | 1 |
| `far_from_care_cutoff_mi` | >= 1 | 1 |
| `suppress_small_vec` | >= 1 | 10 |
| `suppress_small <- function` | 0 | 0 |
| `R/.planning` | 0 | 0 |
| `saveWorkbook` / `saveRDS` lines | 2 outputs only | lines 626 + 635 (2 total) |
| R/177 in R/39 | 1 | 1 |
| R/177 in SCRIPT_INDEX | 1 | 1 |

## Commits

- `031a0f0` — `feat(177-01): write temporal_match_sizing investigation script`
- `f314ef7` — `chore(177-01): register R/177 in R/39 and SCRIPT_INDEX.md`

## Deviations from Plan

### Auto-fixed Issues

None — plan executed as written.

### Plan 02 notes

The `r121_pinned` variable in R/177 is left as an empty string (`""`). The operator must either:
- Set `R177_R121_RDS` environment variable to the Phase 176-validated RDS path, or
- Update `r121_pinned` in the script before the HiPerGator run.

This is intentional: the Phase 176 validated run path is not yet known at plan-write time.

The `definitional_reason` column in the D-04 cross-tab is blank — it is for the Plan 02 memo author to fill after running the script.

## Known Stubs

None — no hardcoded empty values or placeholder text in outputs. All counts are computed from real data (or suppressed via `suppress_small_vec`). The `definitional_reason` column in `C_d04_crosstab` is intentionally blank — it is a structured field for memo authorship, not a data stub.

## Self-Check: PASSED

- `R/177_temporal_match_sizing.R` created: confirmed (640 lines, all greps pass)
- `R/39_run_all_investigations.R` updated: R/177 present (grep count = 1)
- `R/SCRIPT_INDEX.md` updated: R/177 row present (grep count = 1)
- Commits `031a0f0` and `f314ef7` exist in `git log --oneline -5`
