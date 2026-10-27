---
phase: 187-anthracycline-exposure-variables
plan: "01"
subsystem: anthracycline-exposure
tags: [anthracycline, exposure, patient-grain, phase-187]
requirements: [ANTH-01, ANTH-02, ANTH-03]
dependency_graph:
  requires:
    - cache/outputs/treatment_episode_detail_180.rds (Phase 124)
    - output/internal/survivorship_modality_rates_parts_20261012.rds (Phase 171)
    - R/utils/utils_anthracycline_echo.R::last_anthracycline_dose()
  provides:
    - output/internal/anthracycline_exposure_patient_20261022.rds
    - output/anthracycline_exposure_summary_20261022.xlsx
    - .planning/schemas/187out_schema_20261022.md
  affects:
    - Phase 188 (R188_ANTH_RDS pin default)
tech_stack:
  added: []
  patterns:
    - pin() pattern with dated default and pinned TRUE/FALSE on KEY
    - build_patient_out() shared function for fixtures and real data
    - sup() / sup_pair() complementary suppression for aggregate workbook
key_files:
  created:
    - R/187_anthracycline_exposure.R
    - output/internal/anthracycline_exposure_patient_20261022.rds
    - output/anthracycline_exposure_summary_20261022.xlsx
    - .planning/schemas/187out_schema_20261022.md
  modified: []
decisions:
  - "Follow-up source: survivorship_modality_rates_parts_20261012.rds$followup (R/166/171 origin; R/184 does not pin this file)"
  - "D-07 flag count: 1 patient whose last dose is after follow_end; years_since set to NA and counted on KEY"
  - "D-04a dropped: 61 episode IDs not in follow-up table; dropped and counted on KEY"
metrics:
  duration: "~15 min (HiPerGator run)"
  completed_date: "2026-10-22"
  tasks_completed: 3
  files_created: 4
---

# Phase 187 Plan 01: Anthracycline Exposure Variables Summary

Patient-grain anthracycline exposure variables (any_anthracycline, last_anthracycline_date, years_since_last_anthracycline, any_chemo, follow_end, drugs_received) computed for all 8,925 cohort patients from the 180-day treatment episode detail; output RDS and aggregate summary workbook written and probed.

## What Was Built

`R/187_anthracycline_exposure.R` — four-section script that pins two inputs, renames episode columns to match the `last_anthracycline_dose()` helper contract, runs five synthetic fixture assertions, computes patient-grain exposure flags and time variables via `build_patient_out()`, and writes a patient-grain internal RDS plus an aggregate summary workbook with complementary suppression.

## Outputs

| Artifact | Path | Notes |
|----------|------|-------|
| Patient-grain RDS (internal) | `output/internal/anthracycline_exposure_patient_20261022.rds` | 8,925 rows × 7 cols; internal only |
| Aggregate summary XLSX | `output/anthracycline_exposure_summary_20261022.xlsx` | KEY leftmost; UF colours; no patient IDs |
| Output schema probe | `.planning/schemas/187out_schema_20261022.md` | Copied from HiPerGator unedited |
| Script | `R/187_anthracycline_exposure.R` | Source from repo root |

## HiPerGator Run Results (2026-10-22)

Run date: `20261022`

| Metric | Value |
|--------|-------|
| Total cohort patients (followup rows) | 8,925 |
| any_anthracycline TRUE | 2,379 |
| any_anthracycline FALSE | 6,546 |
| any_chemo TRUE | 4,477 |
| any_chemo FALSE | 4,448 |
| D-07 flagged (last dose after follow_end) | 1 |
| D-04a dropped (episode IDs not in cohort) | 61 |
| follow_end NA in follow-up table | 0 |
| Fixture assertions | All 5 passed |

Counts 1–10 are suppressed to `"<11"` in the workbook. Complementary suppression applied to any_chemo and any_anthracycline TRUE/FALSE pairs. All four ANTHRACYCLINE_DRUGS listed in COUNTS_BY_DRUG; only Doxorubicin present (confirmed by probe: Doxorubicin=2,370; smaller combinations suppressed per HIPAA).

Probe columns confirmed (from `187out_schema_20261022.md`):
`ID`, `any_chemo`, `any_anthracycline`, `last_anthracycline_date`, `years_since_last_anthracycline`, `follow_end`, `drugs_received` — 7 columns, 8,925 rows, no patient ID values in probe.

`years_since_last_anthracycline` NA count = 6,547 (6,546 unexposed + 1 D-07 flagged patient) — correct per D-07 design.

## Phase 188 Interface

**Pin default path for R188_ANTH_RDS:**
`output/internal/anthracycline_exposure_patient_20261022.rds`
(exact path confirmed on HiPerGator 2026-10-22 — Phase 188 uses this as its pinned default)

**Output schema probe:**
`.planning/schemas/187out_schema_20261022.md`
(Phase 188 must read only column names that appear in this probe)

**Column contract (from probe):**
`ID`, `any_chemo`, `any_anthracycline`, `last_anthracycline_date`,
`years_since_last_anthracycline`, `follow_end`, `drugs_received`

**Note on `drugs_received`:** character column with sorted drug names joined by `"; "`. Probe shows 4 levels including small combinations (suppressed). Phase 188 should treat as a plain string; no list-column unpacking needed.

## Handed Off to Phase 189 (REG-01)

- Registration of `R/187_anthracycline_exposure.R` in `R/39_run_all_investigations.R`
- `R/SCRIPT_INDEX.md` entry for R/187
- `R/88_smoke_test_comprehensive.R` structural check section for R/187 (file existence + column names)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] pin() helper not available in script scope**
- **Found during:** Task 1 (HiPerGator run)
- **Issue:** `pin()` is defined in `R/utils/` and auto-sourced by `R/00_config.R`, but the coordinator reports it was missing from the script's executed scope. An inline fix was applied.
- **Fix:** Inline pin() definition or sourcing correction committed as 63f52f9.
- **Files modified:** R/187_anthracycline_exposure.R

**2. [Rule 3 - Blocking] R187_RATES_PARTS_RDS default path used wrong directory**
- **Found during:** Task 1 (HiPerGator run)
- **Issue:** The plan specified `file.path(CONFIG$output_dir, "internal", ...)` but the parts file lives in `CONFIG$cache$outputs_dir` (the `clean/rds/outputs/` blue storage path), not in `output/internal/`.
- **Fix:** Path corrected to `CONFIG$cache$outputs_dir`. R187_RATES_PARTS_RDS was set as an env var (`pinned=TRUE`) for the run. Corrected script committed as 6a69420.
- **Files modified:** R/187_anthracycline_exposure.R
- **Phase 188 note:** Use `CONFIG$cache$outputs_dir` (not `CONFIG$output_dir/internal`) when pinning `survivorship_modality_rates_parts_*.rds`.

**3. [Documented deviation] D-04a: 61 episode IDs not in follow-up table**
- **Found during:** Task 1 (HiPerGator run)
- **Issue:** 61 patient IDs appear in the episode detail but not in the follow-up table. These are dropped per D-04a design.
- **Fix:** Not a bug — design-specified behavior. Counted and recorded on KEY.

**4. [Documented deviation] D-07: 1 patient with last dose after follow_end**
- **Found during:** Task 1 (HiPerGator run)
- **Issue:** 1 patient has `last_anthracycline_date > follow_end`. Per D-07, `years_since_last_anthracycline` is set to NA for this patient.
- **Fix:** Not a bug — design-specified behavior. Counted and recorded on KEY.

**5. [Documented] Follow-up source differs from plan's framing**
- R/184 does not pin `survivorship_modality_rates_parts_*.rds`. The plan said "copy the dated literal from R/184's follow-up pin," but R/184 reads follow_end from the patient-year RDS (R/179), not from the parts file. R/187 correctly uses `rates_parts$followup` from the R/166 output (same source as R/167), with default date `20261012` from Phase 171 SURV_RUN_DATE. This is recorded in the script header comment and on the KEY sheet.

## Known Stubs

None. All output columns are computed from real data and written to the dated RDS. No placeholder values in the patient-grain output.

## Self-Check: PASSED

- `R/187_anthracycline_exposure.R` — confirmed written (437+ lines)
- `output/internal/anthracycline_exposure_patient_20261022.rds` — confirmed by HiPerGator console output
- `output/anthracycline_exposure_summary_20261022.xlsx` — confirmed by HiPerGator console output
- `.planning/schemas/187out_schema_20261022.md` — confirmed copied to Windows repo
- `187-01-SUMMARY.md` — this file
- All five fixture assertions passed (confirmed in console output)
- ANTH-01, ANTH-02, ANTH-03 requirements satisfied
