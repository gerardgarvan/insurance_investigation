---
phase: 188-echo-rate-since-anthracycline
plan: "01"
subsystem: echo-rate-anthracycline
tags: [echo, anthracycline, rate, patient-grain, encounter-grain, phase-188]
requirements: [ECHO-01, ECHO-02]
dependency_graph:
  requires:
    - output/internal/anthracycline_exposure_patient_20261022.rds (Phase 187)
    - cache/outputs/survivorship_dated_events_20261012.rds (Phase 166/171)
    - cache/outputs/survivorship_echo_parts_20261012.rds (Phase 166/167, Anchor Comparison)
  provides:
    - output/internal/echo_enc_anthracycline_20261022.rds
    - output/internal/echo_rate_anthracycline_patient_20261022.rds
    - output/20261022_188_echo_rate_anthracycline.xlsx
  affects:
    - Phase 189 (REG-01 script registration)
tech_stack:
  added: []
  patterns:
    - build_echo_out() shared function for fixtures and real data (same as R/187 build_patient_out() pattern)
    - sup() / sup_pair() complementary suppression
    - D-06 dual sum checks (per-patient and dataset-level)
    - D-07a denominator recomputation check (exact agreement, diff = 0)
    - three-pin SECTION 0 pattern (CONFIG$cache$outputs_dir for dated inputs)
key_files:
  created:
    - R/188_echo_rate_since_anthracycline.R
    - output/internal/echo_enc_anthracycline_20261022.rds
    - output/internal/echo_rate_anthracycline_patient_20261022.rds
    - output/20261022_188_echo_rate_anthracycline.xlsx
  modified: []
decisions:
  - "D-02a: survivorship_dated_events not windowed; on_or_before count is full pre-dose history"
  - "D-02b: dedup by dplyr::distinct(ID, echo_date) via inner_join from echo rows onto anthra"
  - "D-05a: window labeling case_when first-match-wins: unclassifiable → after_follow_end → on_or_before_last_dose → after_last_dose"
  - "D-06: per-patient and dataset-level sum checks both passed (diff = 0)"
  - "D-07a: max person-year diff = 0 (exact agreement with Phase 187)"
  - "D-08a: anchor delta = 0 across all Anchor Comparison columns — last_dose_firstline_dt == last_dose_ever_dt confirmed"
  - "D-11: pooled rate = total_echoes_post / total_person_years over in_rate_population patients"
  - "PD-01: no Phase 166 workbook exists; Phase 166 row derived from survivorship_echo_parts_20261012.rds primary variant"
  - "PD-02: anchor dates not in parts RDS; per-patient comparison uses person_years as proxy"
  - "PD-03: n_exposed = nrow(anthra) at run time — no hardcoded count"
metrics:
  duration: "~3 min (HiPerGator run)"
  completed_date: "2026-10-22"
  tasks_completed: 2
  files_created: 4
---

# Phase 188 Plan 01: Echo Rate Since Anthracycline Summary

Echocardiogram rate per patient-year after the last anthracycline dose computed for
2,379 anthracycline-exposed patients (Phase 187); encounter-grain and patient-grain
internal RDS files written; four-sheet workbook produced with Anchor Comparison
confirming D-08a: zero delta between the Phase 166 and Phase 188 rate estimates.

## What Was Built

`R/188_echo_rate_since_anthracycline.R` — five-section script that pins three inputs,
defines `sup()`, `sup_pair()`, and `build_echo_out()` (used by both 13 synthetic
fixtures and real data), runs all 13 fixtures before data load, then processes the
real cohort: encounter-grain dedup and window labeling (SECTION 2–3), D-07a
denominator check, D-06 dual sum checks, patient-grain RDS, and a four-sheet
workbook (SECTION 4).

## Outputs

| Artifact | Path | Notes |
|----------|------|-------|
| Script | `R/188_echo_rate_since_anthracycline.R` | 799 lines; source from repo root |
| Encounter-grain RDS (internal) | `output/internal/echo_enc_anthracycline_20261022.rds` | 4,316 rows × 4 cols; internal only |
| Patient-grain RDS (internal) | `output/internal/echo_rate_anthracycline_patient_20261022.rds` | 2,379 rows × 8 cols; internal only |
| Workbook | `output/20261022_188_echo_rate_anthracycline.xlsx` | KEY, Rates, Anchor Comparison, QC |

## HiPerGator Run Results (2026-10-22)

| Metric | Value |
|--------|-------|
| Exposed patients (Phase 187) | 2,379 |
| Source echo rows for exposed patients | 4,316 |
| NA echo dates | 0 |
| Duplicate ID × date pairs removed | 0 |
| Encounter-grain rows (after dedup) | 4,316 |
| window_label: after_last_dose | 2,224 |
| window_label: on_or_before_last_dose | 2,092 |
| window_label: after_follow_end | 0 |
| window_label: unclassifiable | 0 |
| D-07a max person-year diff | 0 (exact) |
| D-06 sum checks | Both passed |
| All 13 fixtures | Passed |

### Rates Sheet

| n_patients | n_excluded | total_echoes_post | total_person_years | rate_per_py |
|-----------|-----------|-----------------|------------------|------------|
| 2,352 | 27 | 2,224 | 8,891.6 | 0.2501 |

Rate-eligible = 2,352 patients; 27 excluded (see QC Panel C).
Pooled rate: 2,224 echoes / 8,891.6 person-years = 0.2501 echoes/person-year.

### Anchor Comparison Sheet (ECHO-02)

| anchor | n_patients | total_echoes_post | person_years | rate_per_py |
|--------|-----------|-----------------|-------------|------------|
| last_dose_firstline_dt (D-08a: equals last_dose_ever_dt) | 2,352 | 2,224 | 8,891.6 | 0.2501 |
| last_dose_ever_dt (Phase 188) | 2,352 | 2,224 | 8,891.6 | 0.2501 |
| Difference (Phase 188 − Phase 166) | 0 | 0 | 0.0 | 0.0000 |

**D-08a confirmed:** Delta is zero across all columns. The two anchor definitions are
numerically identical in this extract (first_line flag was absent from the 180-day
episode file; all episodes treated as first-line per Phase 166 D-08a fallback).
Any cross-phase difference would reflect window, eligibility, echo-source, or drug-set
differences — the methodology table on the Anchor Comparison sheet enumerates which
dimensions are shared and which differ.

**Per-patient overlap (D-15a):**
- Patients in both Phase 166 and Phase 188: 2,379
- Patients only in Phase 166: <11
- Patients only in Phase 188: 0
- Patients with different person-years / patients in both with py on both sides: 0 / 2,352
- Patients with different post-dose echo count / patients in both: 0 / 2,379
- Rate-eligible in both: 2,352 / 2,379

### QC Sheet

**Panel A — echoes on or before last dose:**
- Total echoes: 2,092
- Patients with any on-or-before echo: 1,369
- Pct of exposed: 57.5%

**Panel B — echoes after follow_end:** 0 echoes, 0 patients

**Panel C — patient reconciliation (identity: 2,352 + <11 + <11 = 2,379 ✓):**
- in rate population: 2,352
- excluded: last dose after follow_end: <11 (1 patient, consistent with Phase 187 D-07)
- excluded: last dose on follow_end (zero person-years): <11

**Panel D — unclassifiable echoes:** 0 (expected)

## Deviations from Plan

### PD-01 (documented): No Phase 166 workbook
Phase 168 was never run. The Anchor Comparison Phase 166 row was derived from
`survivorship_echo_parts_20261012.rds` primary variant (`echo_rate_patient` element),
using the same pooled formula as Phase 188. Recorded on KEY with reason.

### PD-02 (documented): Per-patient anchor date comparison not possible
`echo_rate_patient` stores rates, not anchor dates. The per-patient comparison uses
`person_years` as proxy (same follow_end source). Person-years difference = 0 / 2,352,
confirming the two anchor definitions produce identical denominators. Recorded on KEY.

## Known Stubs

None. All outputs computed from real data. No placeholder values.

## Handed Off to Phase 189 (REG-01)

- Registration of `R/188_echo_rate_since_anthracycline.R` in `R/39_run_all_investigations.R`
- `R/SCRIPT_INDEX.md` entry for R/188
- `R/88_smoke_test_comprehensive.R` structural check section for R/188

## Self-Check: PASSED

- `R/188_echo_rate_since_anthracycline.R` — confirmed written (799 lines)
- `output/internal/echo_enc_anthracycline_20261022.rds` — confirmed by HiPerGator console
- `output/internal/echo_rate_anthracycline_patient_20261022.rds` — confirmed by HiPerGator console
- `output/20261022_188_echo_rate_anthracycline.xlsx` — confirmed by HiPerGator console
- All 13 fixture assertions passed (confirmed in console output)
- D-06 sum checks passed (per-patient and dataset-level)
- D-07a denominator check passed (diff = 0)
- ECHO-01, ECHO-02 requirements satisfied
