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
  - "Sensitivity (CDM-cutoff window) yielded no eligible patients under anchor <= CDM_CUTOFF − 730 restriction"
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

2. **Sensitivity (calendar window):** No patients were eligible for the fixed `(CDM_CUTOFF − 365, CDM_CUTOFF]` window under the anchor ≤ CDM_CUTOFF − 730 restriction; reported as N/A in the workbook.

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
| Sensitivity (CDM-cutoff window) | 0 eligible | N/A | N/A | N/A | N/A |

Missing exposure: 847 patients excluded. Patients who died earlier: 851.

## Memo Location

`.planning/phases/181-cbc-prior-year-vs-distance/181-MEMO.md`

Ready to send to Amy/Erin.

## Open Items

- **D-15:** Which analysis is primary — Phase 165 (encounter-level) or Phase 179/181 (patient-year)?
- **D-165-01:** Primary method for Phase 165 (provisionally patient-level Fisher; pending Amy/Erin).
- **Prior-year definition:** Confirm `max(year_index)` working definition with Erin/Ray.

## Deviations from Plan

**1. [Rule 1 - Bug] Sensitivity window yielded no eligible patients**
- **Found during:** Task 1 (design) / confirmed in Task 3 (HiPerGator run)
- **Issue:** Under the restriction anchor ≤ CDM_CUTOFF − 730 (ensuring the window is year 2 or later), no patients qualified for the fixed calendar window sensitivity analysis. The DuckDB query ran without error; the result was N = 0 eligible patients.
- **Fix:** Script reports the sensitivity as N/A in KEY, A_2x2, and QC sheets with an explanatory note. Memo documents this as "sensitivity not available."
- **Files modified:** R/181_cbc_prior_year.R (defensive handling already in place at write time)
- **Commit:** a852c03

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
