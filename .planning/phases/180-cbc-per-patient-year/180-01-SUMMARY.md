---
phase: 180-cbc-missing-capture
plan: 01
subsystem: distance-cbc
tags: [missing-exposure, bounding, capture-check, gee, patient-year]
dependency_graph:
  requires: [179-02]
  provides: [MISS-01-reason-table, MISS-02-03-bounded-ORs, MISS-04-capture-ORs]
  affects: [179-KEY-limitation-row]
tech_stack:
  added: []
  patterns: [geepack-gee-logistic, duckdb-push-down, openxlsx-uf-colors, inequality-join-flags]
key_files:
  created:
    - R/180_cbc_missing_capture.R
    - .planning/phases/180-cbc-per-patient-year/180-01-SUMMARY.md
  modified:
    - R/179_cbc_patient_year.R  # D-05 limitation row added to key_df
    - R/39_run_all_investigations.R
    - R/SCRIPT_INDEX.md
decisions:
  - "D-05 branch: same side — both bounded ORs (far=1: 0.776; far=0: 0.872) below 1, same as primary 0.845; limitation row added to R/179 KEY builder"
  - "D-09 branch (primary): moves toward 1 — any_lab_year restriction OR 0.90 (37.4% log-OR shrinkage >= 25% threshold); consistent with out-of-system care; report only to Amy/Erin with D-165-01"
  - "Lab-source caveat: external origin of lab results could not be determined from available source fields"
metrics:
  duration: ~30 minutes (Tasks 1-5 local write + Task 6 HiPerGator run)
  completed: 2026-10-13
  tasks: 6
  files: 4
---

# Phase 180 Plan 01: Missing-Exposure Bounding and CBC Capture Check — Summary

**One-liner:** GEE bounding confirms Phase 179 OR is robust to missing-exposure assignment (D-05: same side); capture restriction moves OR toward 1 by 37% (D-09: consistent with out-of-system care).

## What Was Built

`R/180_cbc_missing_capture.R` — a read-only companion to Phase 179 that runs three checks:

1. **MISS-01**: Every patient with missing exposure is assigned exactly one of six reason groups (asserted by `stopifnot`). The largest groups are reason (b) — facility ZIP missing or not in database (581 patients, 2,421 patient-years) and reason (a) — all patient ZIP missing (164 patients, 1,260 py). Reason (c) — no post-anchor encounter in ENCOUNTER — has <11 patients (suppressed), which is the group most directly relevant to capture.

2. **MISS-02/03**: Primary GEE refit with missing patients assigned far=1 (OR 0.776, 0.693–0.867) and far=0 (OR 0.872, 0.751–1.012). Both bounded ORs remain below 1, same side as the Phase 179 primary estimate (OR 0.845). D-05 branch: **same side** — limitation row added to R/179 KEY builder.

3. **MISS-04**: Per-patient-year `any_lab_year` (non-CBC/hematology lab in the year, from DuckDB push-down excluding 15 LOINCs) and `any_enc_year` (any ENCOUNTER row in the year) flags built via dplyr inequality joins. D-08 primary restriction (within `any_lab_year == 1`) gives OR 0.90 (0.741–1.092), a 37.4% shrinkage in the log-OR relative to Phase 179 (OR 0.845). D-09 locked rule: **moves toward 1 — consistent with out-of-system care (non-capture)**. Report only; goes to Amy/Erin with D-165-01.

## Inputs

| Input | File | Pinned |
|-------|------|--------|
| Phase 179 RDS | cbc_patient_year_20261013.rds | YES (date-locked default) |
| enc_distance | encounter_distance_*.rds (most recent) | NO (noted in KEY) |
| single_source_care | single_source_care_*.rds (most recent) | NO (noted in KEY) |
| Triage | triage column in Phase 179 RDS | from R/179 run |

## Reproduction Check

Phase 179 primary OR reproduced before any check: **PASSED** — OR 0.84 (0.73–0.98), confirming the pinned RDS and GEE specification are identical.

## MISS-01 Reason Groups (all years)

| Reason | Patients | Patient-years | CBC rate |
|--------|----------|---------------|----------|
| (c) no post-anchor encounter | <11 | — | — |
| (f) post-anchor enc but not in enc_distance | 46 | 306 | 10.8% |
| (e) computed status but no distance | 0 | 0 | — |
| (a) all patient_zip_missing | 164 | 1,260 | 14.1% |
| (b) all facility_zip_missing / zip_not_in_db | 581 | 2,421 | 21.9% |
| (d) mixed (a)+(b) | 54 | 234 | 29.9% |
| Observed exposure | 7,785 | 54,3xx | ~24% |

## MISS-02/03 Bounding (years 2+)

| Analysis | OR | CI |
|----------|----|----|
| Phase 179 primary (ref) | 0.845 | 0.727–0.981 |
| MISS-02: missing -> far=1 | 0.776 | 0.693–0.867 |
| MISS-03: missing -> far=0 | 0.872 | 0.751–1.012 |

D-05 branch: **same side** — limitation row written to `R/179_cbc_patient_year.R` KEY builder.

## MISS-04 Capture Models (years 2+, observed exposure)

| Analysis | OR | CI | % change | D-09 label |
|----------|----|----|----------|------------|
| Phase 179 primary (ref) | 0.845 | 0.727–0.981 | — | reference |
| D-08 primary: within any_lab_year=1 | 0.90 | 0.741–1.092 | 37.4% | moves toward 1: consistent with out-of-system care |
| D-08 secondary: within any_enc_year=1 | 1.047 | 0.897–1.222 | — | — |
| D-08 single_source_care_post=1 | 0.754 | 0.614–0.927 | — | — |
| D-08 single_source_care_post=0 | 1.068 | 0.862–1.323 | — | — |

D-09 branch (primary): **moves toward 1 — consistent with out-of-system care (non-capture)**. Report only; goes to Amy/Erin with D-165-01.

## Lab-Source Caveat

Source field value counts reported in MISS-04 sheet. External origin of lab results could not be determined from available fields — absence of an "external" category in these fields is not evidence of absence of outside results.

## D-05 Action Applied

Limitation row added to `R/179_cbc_patient_year.R` `key_df` (Field: "Missing-exposure limitation (Phase 180, D-05)"). The row records the three ORs, both bounded CIs, the D-05 branch, and a pointer to `cbc_missing_capture_20261013.xlsx`. This row will appear in the KEY sheet on the next R/179 run.

## Outputs

- `output/cbc_missing_capture_20261013.xlsx` — KEY | MISS-01 | MISS-02-03 | MISS-04
- `output/internal/cbc_missing_capture_20261013.rds` — 58,595 rows; Phase 179 columns + any_lab_year, any_enc_year, miss_reason

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — all four MISS sections run and produce real numbers from the HiPerGator DuckDB and Phase 179 RDS.

## Self-Check: PASSED

- R/180_cbc_missing_capture.R exists and contains all required patterns (verified pre-commit)
- R/39_run_all_investigations.R contains one reference to R/180_cbc_missing_capture.R
- R/SCRIPT_INDEX.md contains one reference to R/180_cbc_missing_capture.R
- R/179_cbc_patient_year.R contains the D-05 limitation row (key_df Field: "Missing-exposure limitation (Phase 180, D-05)")
- HiPerGator run confirmed: reproduction check PASSED, workbook and RDS written
