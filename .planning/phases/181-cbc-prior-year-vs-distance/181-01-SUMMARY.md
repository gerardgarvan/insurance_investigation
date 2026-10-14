---
phase: 181-cbc-prior-year-vs-distance
plan: 01
subsystem: distance-cbc
tags: [prior-year, 2x2, chi-squared, fisher, or, memo, cbcp-01, cbcp-02]
dependency_graph:
  requires: [179-02, 180-01]
  provides: [CBCP-prior-year-2x2, CBCP-team-memo]
  affects: []
tech_stack:
  added: []
  patterns: [chi-squared-fisher-branch, openxlsx-uf-colors, readxl-label-lookup, glue-memo-generation]
key_files:
  created:
    - R/181_cbc_prior_year.R
    - .planning/phases/181-cbc-prior-year-vs-distance/181-MEMO.md
    - .planning/phases/181-cbc-prior-year-vs-distance/181-01-SUMMARY.md
  modified:
    - R/39_run_all_investigations.R
    - R/SCRIPT_INDEX.md
    - .planning/phases/181-cbc-prior-year-vs-distance/181-CONTEXT.md
decisions:
  - "Prior year = max(year_index) per patient (working definition; label as such in KEY and memo — confirm with Erin/Ray)"
  - "Primary test: Pearson chi-squared (min expected cell = 148.6 > 5); no Fisher fallback needed"
  - "Sensitivity (CDM-cutoff window): bug fixed post-execution — year_start <= CDM_CUTOFF-730 replaced with year_index >= 2; corrected result: N=6468, OR=0.850 (0.687-1.052), p=0.136"
  - "Memo generated at runtime from Phase 179/180 workbook labels — no hard-coded result values"
  - "CONTEXT fixes: D-165-01 wording updated to 'pending Amy/Erin (provisionally patient-level Fisher)'; section count corrected from Five to Six"
metrics:
  duration: ~45 minutes (Tasks 0-2 local write + Task 3 HiPerGator run + Task 4 close-out)
  completed: 2026-10-14
  tasks: 5
  files: 6
requirements:
  - CBCP-01
  - CBCP-02
---

# Phase 181 Plan 01: Prior-Year CBC × Distance 2×2 and Team Memo — Summary

**One-liner:** Patient-level 2×2 of CBC in prior year (max year_index) × far from care: OR 0.833 (0.682–1.016), p = 0.071; memo generated from Phase 179/180 workbook values and placed in the phase folder.

## What Was Built

`R/181_cbc_prior_year.R` — a read-only companion to Phase 179/180 that produces:

1. **Prior-year 2×2 (CBCP-01):** Each patient's `max(year_index)` row defines their "prior year." Primary analytic set: year_index ≥ 2 (survivorship cohort), N = 7,075 patients. Pearson chi-squared used throughout (min expected cell = 148.6 > 5). OR 0.833 (95% CI 0.682–1.016), p = 0.071. Secondary (all years): OR 0.871 (0.73–1.04), p = 0.126.

2. **Sensitivity (calendar window):** Fixed `(2024-09-15, 2025-09-15]` window, year_index ≥ 2. N = 6,468. OR 0.850 (95% CI 0.687–1.052), p = 0.136, Pearson chi-squared. (Original run had a bug — year_start ≤ CDM_CUTOFF − 730 instead of year_index ≥ 2 — yielding 0 eligible patients; corrected and re-run same date.)

3. **Workbook** `output/cbc_prior_year_20261014.xlsx`: sheets KEY, A_2x2, B_rates, C_year_distribution, QC. Suppression rule (counts 1–10 → `<11`) applied consistently; no suppressed cells in the primary block.

4. **Team memo (CBCP-02):** Six-section markdown memo generated at runtime from Phase 179/180 workbook key labels (no hard-coded numbers). Includes: working-definition caveat; 851 patients who died earlier contribute their last full year before death; out-of-system language; single-source group labeling from Phase 180 MISS-04; D-15 and D-165-01 as open decisions. Placed in `.planning/phases/181-cbc-prior-year-vs-distance/181-MEMO.md`.

## Inputs

| Input | File | Pinned |
|-------|------|--------|
| Phase 179 RDS | cbc_patient_year_20261013.rds | YES (date-locked default) |
| Phase 180 workbook | cbc_missing_capture_20261013.xlsx | YES (date-locked default) |
| Phase 179 workbook | cbc_patient_year_20261013.xlsx | YES (for Phase 165 side-by-side) |
| DuckDB LAB_RESULT_CM | sensitivity window only | from HiPerGator |

## Prior-Year Distribution

Distribution of max year_index (patients whose "prior year" is year 1, 2, 3, …) available in the C_year_distribution sheet of the workbook.

## Results

| Analysis | N | OR | 95% CI | p | Test |
|----------|---|----|--------|---|------|
| Primary (year_index ≥ 2) | 7,075 | 0.833 | 0.682–1.016 | 0.071 | Pearson chi-squared |
| Secondary (all years) | see workbook | 0.871 | 0.73–1.04 | 0.126 | Pearson chi-squared |
| Sensitivity (CDM-cutoff window, year_index ≥ 2) | 6,468 | 0.850 | 0.687–1.052 | 0.136 | Pearson chi-squared |

Missing exposure: 847 patients excluded. Patients who died earlier: 851.

## Memo Location

`.planning/phases/181-cbc-prior-year-vs-distance/181-MEMO.md`

Ready to send to Amy/Erin.

## Open Items

- **D-15:** Which analysis is primary — Phase 165 (encounter-level) or Phase 179/181 (patient-year)?
- **D-165-01:** Primary method for Phase 165 (provisionally patient-level Fisher; pending Amy/Erin).
- **Prior-year definition:** Confirm `max(year_index)` working definition with Erin/Ray.

## Deviations from Plan

**1. [Bug] Sensitivity filter too restrictive — zero eligible patients**
- **Found during:** Post-run review (Task 3 HiPerGator output)
- **Issue:** Filter used `year_start <= CDM_CUTOFF − 730` on the *prior-year* row. For year_index = 2, year_start = anchor + 365, so the condition required anchor ≤ CDM_CUTOFF − 1095 (3 years before cutoff) instead of the intended 2 years. Result: 0 eligible patients.
- **Fix:** Replaced with `year_index >= 2L`, which directly encodes the survivorship requirement. Re-run same date yielded N = 6,468 eligible patients.
- **Files modified:** R/181_cbc_prior_year.R
- **Commit:** aa9dc77

## Known Stubs

None — all analytic sets, 2×2 tables, and memo sections produced from real run data.

## Self-Check: PASSED

- R/181_cbc_prior_year.R exists (created, 772 lines)
- R/39_run_all_investigations.R contains exactly 1 reference to R/181_cbc_prior_year.R
- R/SCRIPT_INDEX.md contains exactly 1 reference to R/181_cbc_prior_year.R
- 181-MEMO.md exists in phase folder
- HiPerGator run confirmed: workbook cbc_prior_year_20261014.xlsx and memo written successfully
- CBCP-01: prior-year 2×2 with correct test choice, OR/CI, suppression — confirmed
- CBCP-02: memo generated from computed + workbook-read values, reviewed, placed in phase folder — confirmed
