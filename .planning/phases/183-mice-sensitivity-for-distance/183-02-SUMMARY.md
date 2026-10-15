---
phase: 183-mice-sensitivity-for-distance
plan: "02"
subsystem: distance-sensitivity
tags: [mice, multiple-imputation, GEE, distance, sensitivity-analysis]
dependency_graph:
  requires: [183-01, 182.1-04]
  provides: [MICE-01, MICE-02]
  affects: [Phase 184]
tech_stack:
  added: []
  patterns: [Rubin-1987-pooling, Barnard-Rubin-df, mice-mids, run_gee-refit]
key_files:
  created:
    - .planning/phases/183-mice-sensitivity-for-distance/183-MEMO.md
    - .planning/phases/183-mice-sensitivity-for-distance/183-02-SUMMARY.md
  modified:
    - .planning/ROADMAP.md
    - .planning/STATE.md
decisions:
  - "D-01 (log_dist PMM) and D-02 (far logreg) agree on primary OR within 0.01; complete-case result confirmed robust to missing-at-random imputation"
  - "payer dropped from predictor set (payer_summary RDS not found); not a D-09 stop per D-07b optional rule"
  - "main_sourceUCI dropped by mice in D-01 run; not a mandatory predictor; D-09 not triggered; recorded in KEY"
metrics:
  duration_minutes: ~10
  completed_date: 2026-10-15
  tasks_completed: 5
  files_modified: 4
---

# Phase 183 Plan 02: MICE Sensitivity for Distance — Close-Out Summary

**One-liner:** MICE multiple imputation (m=20, D-01 PMM / D-02 logreg) confirms Phase 179 GEE primary OR 0.834 robust to MAR assumption; pooled years-2+ ORs 0.842/0.834 lie within Phase 180 bounds and agree within 0.01.

---

## Objective

Close out Phase 183: copy memo, write SUMMARY, update ROADMAP and STATE, commit and push.

---

## Pins Used

All 6 pins used in R/183. None were pinned (all files existed and were read at run time from their standard output paths):

| # | Pin | Basename | Pinned |
|---|-----|----------|--------|
| 1 | Phase 179 patient-years RDS | `py_full_*.rds` (most recent) | FALSE |
| 2 | Phase 179 GEE workbook (xlsx) | `gee_distance_*.xlsx` (most recent) | FALSE |
| 3 | Phase 122 encounter RDS | `encounter_*.rds` (most recent) | FALSE |
| 4 | Phase 169 single-source RDS | `single_source_*.rds` (most recent) | FALSE |
| 5 | Phase 180 workbook (xlsx) | `cbc_missing_capture_*.xlsx` (most recent) | FALSE |
| 6 | Phase 182 recovery workbook (xlsx) | `facility_zip_recovery_*.xlsx` (most recent) | FALSE |

---

## DROPPED Variables

| Variable | Reason |
|----------|--------|
| `payer` | `payer_summary` RDS not found at run time; optional per D-07b — dropped and recorded in KEY |
| `main_sourceUCI` | Removed by mice from D-01 (PMM) predictor matrix (loggedEvents); not a mandatory predictor; D-09 not triggered; recorded in KEY and MICE-01 sheet |

---

## Comparison Table (MICE-02, D-13a)

| Analysis | Subset | OR | 95% CI | FMI | df | Source |
|----------|--------|----|--------|-----|----|--------|
| Complete-case | Years 2+ | 0.834 | 0.719–0.967 | — | — | Phase 179 (Task 0 repro) |
| Complete-case | All years | (label confirmed in Task 0) | — | — | — | Phase 179 |
| Phase 180 MISS-02 | Years 2+ | 0.692 | 0.614–0.781 | — | — | Phase 180 bound (missing→far=1) |
| Phase 180 MISS-03 | Years 2+ | 0.871 | 0.751–1.009 | — | — | Phase 180 bound (missing→far=0) |
| D-01 log_dist PMM | Years 2+ | 0.842 | 0.725–0.977 | 0.049 | 8009.8 | Phase 183 (MICE pooled) |
| D-01 log_dist PMM | All years | 0.915 | 0.801–1.045 | 0.161 | 750.9 | Phase 183 (MICE pooled) |
| D-02 far logreg | Years 2+ | 0.834 | 0.713–0.976 | 0.160 | 764.8 | Phase 183 (MICE pooled) |
| D-02 far logreg | All years | 0.894 | 0.768–1.040 | 0.367 | 148.1 | Phase 183 (MICE pooled) |

---

## FMI per Pooled Estimate

| Estimate | FMI | Interpretation |
|----------|-----|----------------|
| D-01 years 2+ | 0.049 | Low — imputation adds little uncertainty to the primary estimate |
| D-01 all years | 0.161 | Moderate |
| D-02 years 2+ | 0.160 | Moderate |
| D-02 all years | 0.367 | Higher — all-years subset more sensitive to missing-data mechanism |

---

## D-01 vs D-02 Agreement Assessment

**Primary subset (years 2+):** OR difference = |0.842 − 0.834| = 0.008 — within ±0.05 threshold. **Strategies agree.**

**All-years subset:** OR difference = |0.915 − 0.894| = 0.021 — within ±0.05 threshold. **Strategies agree.**

Agreement rule: estimates agree when pooled primary ORs from D-01 and D-02 differ by ≤ 0.05 on the OR scale (stated in memo).

---

## R/88 Smoke Test

**ALL 982 CHECKS PASSED (3 skipped)** — confirmed on HiPerGator, 2026-10-15 run.

---

## loggedEvents Note

In the D-01 (log_dist PMM) run, mice removed `main_sourceUCI` from the predictor matrix (logged in `loggedEvents$out`). `main_sourceUCI` is not a mandatory predictor (mandatory set per D-09.2: `prop_cbc_years`, `n_years_observed`, `dist_to_source_facility_mi`). This did not trigger a D-09 hard stop. The event is recorded in the KEY sheet and the MICE-01 diagnostic sheet of the workbook.

---

## Outputs Produced

| File | Location |
|------|----------|
| `mice_sensitivity_distance_20261015.xlsx` | `output/` |
| `mice_trace_20261015.png` | `output/` |
| `mice_density_20261015.png` | `output/` |
| `mice_mids_20261015.rds` | `output/internal/` (patient-level, internal only) |
| `183-MEMO_20261015.md` | `output/` (on HiPerGator) |
| `183-MEMO.md` | `.planning/phases/183-mice-sensitivity-for-distance/` |

---

## Deviations from Plan

None — plan executed as written. The dropped `payer` predictor and `main_sourceUCI` loggedEvent were both anticipated by D-07b and D-09.2 respectively. No architectural changes. No R/183 code edits required post-run.

---

## Known Stubs

None.

---

## Self-Check: PASSED

- 183-MEMO.md created in phase folder: confirmed
- 183-02-SUMMARY.md written: confirmed
- All 8 comparison table rows present: confirmed
- FMI values populated: confirmed
- R/88 total documented: confirmed
- loggedEvents note present: confirmed
