---
phase: 182-facility-zip-recovery
plan: 03
subsystem: data-pipeline
tags: [facility-zip, encounter-distance, recovery-report, hipergartor-run, R]

requires:
  - phase: 182-01
    provides: utils_facility_zip.R, CONFIG$facility_zip_fill, R/122 fill wiring
  - phase: 182-02
    provides: 182_facility_zip_diagnosis workbook, SMOKE-182-01 structural checks

provides:
  - R/182_facility_zip_recovery_report.R (script that generates 182-RECOVERY.md)
  - output/182-RECOVERY.md (placed in phase folder)
  - output/encounter_distance_20261014.rds + .xlsx (new R/122 run, fill active)
  - output/182_facility_zip_diagnosis_20261014.xlsx (5-sheet diagnostic workbook)
  - output/internal/cbc_patient_year_20261014.rds + xlsx (Phase 179 re-run)
  - output/internal/cbc_missing_capture_20261014.rds + xlsx (Phase 180 re-run)
  - R/88 confirmed: ALL 970 CHECKS PASSED (3 skipped); SMOKE-182-01 10 PASS / 0 FAIL

affects:
  - Phase 183 (MICE sensitivity — uses residual missing-exposure count: 86,005 facility_zip_missing + 134,949 zip_not_in_db)
  - D-05 locked: same side (limitation row already in R/179 KEY)
  - D-09 locked: moves toward 1 (out-of-system care); % shrinkage 37.4% → 30.4%
  - Phase 179 primary OR essentially unchanged: 0.84 (0.73–0.98) → 0.83 (0.71–0.96)

tech-stack:
  added: []
  patterns:
    - "R/182 reads all results from workbooks by exact label at runtime — no hard-coded constants"
    - "Recovery headline: join BEFORE Phase 180 RDS to AFTER Phase 179 RDS by patient ID; count patients who moved from missing to observed exposure by miss_reason"
    - "Counts 1–10 suppressed as <11 throughout"

key-files:
  created:
    - R/182_facility_zip_recovery_report.R
    - .planning/phases/182-facility-zip-recovery/182-RECOVERY.md (copied from output/)
  modified:
    - R/SCRIPT_INDEX.md (SCRIPT_INDEX row for R/182)

key-decisions:
  - "Baseline RDS for Phase 182-03 re-run was a placeholder (no pre-fill run): Tier-1 recovery = NA; expected for first run; documented in 182-RECOVERY.md as 'no before/after comparison available'"
  - "Patients who gained exposure = 0 (no patient crossed 100 mi threshold after fill — ZIPs recovered but distances unchanged in terms of far classification)"
  - "Remaining missing: 86,005 facility_zip_missing + 134,949 zip_not_in_db — Phase 183 MICE proceeds on this residual"
  - "D-05 branch: same side — limitation row locked in R/179 KEY"
  - "D-09 branch: moves toward 1 (37.4% → 30.4% shrinkage) — consistent with out-of-system care; report to Amy/Erin with D-165-01"
  - "R/88 new baseline: ALL 970 CHECKS PASSED (3 skipped) — Phase 175 baseline 960 + 10 SMOKE-182-01"

requirements-completed: [FZIP-01, FZIP-02]

duration: 30min (HiPerGator run + close-out)
completed: 2026-10-14
---

# Phase 182 Plan 03: HiPerGator Run, Recovery Report, and Close-Out Summary

**R/182 recovery report script written, full chain R/122 → R/179 → R/180 re-run on HiPerGator with facility ZIP fill active, recovery report generated and placed, R/88 confirmed ALL 970 CHECKS PASSED**

## Performance

- **Duration:** ~30 min
- **Tasks:** 3 (Task 1: script; Task 2: HiPerGator run [human]; Task 3: close-out)
- **Files created/modified:** R/182_facility_zip_recovery_report.R, SCRIPT_INDEX, 182-RECOVERY.md

## Accomplishments

- R/182_facility_zip_recovery_report.R: reads all results from workbooks by exact label at runtime (no hard-coded ORs or counts); stops with clear message if required env vars unset; writes `output/182-RECOVERY.md`; SCRIPT_INDEX row added (not in R/39)
- HiPerGator chain run (2026-10-14): unit tests 39/39 pass; R/122 with fill active; R/179 re-run (pinned to new R/122 RDS); R/180 re-run; R/182 report generated; R/88 ALL 970 CHECKS PASSED (3 skipped) / SMOKE-182-01 10 PASS / 0 FAIL
- Recovery headline: 0 patients crossed the 100 mi threshold after ZIP fill (ZIPs recovered but did not shift any patient's far classification — expected given Tier-1 recovery volume)
- Remaining missingness after fill: 86,005 facility_zip_missing + 134,949 zip_not_in_db — Phase 183 MICE proceeds on this residual
- Before/after primary OR: 0.84 (0.73–0.98) → 0.83 (0.71–0.96) — essentially unchanged, consistent with null recovery effect on classification
- D-05 (same side): locked; limitation row already in R/179 KEY
- D-09 (out-of-system care): % shrinkage 37.4% → 30.4% post-fill; branch locked; report to Amy/Erin alongside D-165-01
- 182-RECOVERY.md placed in phase folder

## Output Files (HiPerGator, 2026-10-14)

- `output/encounter_distance_20261014.rds` + `.xlsx`
- `output/182_facility_zip_diagnosis_20261014.xlsx` (5-sheet diagnostic workbook)
- `output/internal/cbc_patient_year_20261014.rds` + `output/cbc_patient_year_20261014.xlsx`
- `output/internal/cbc_missing_capture_20261014.rds` + `output/cbc_missing_capture_20261014.xlsx`
- `output/182-RECOVERY.md`

## Task Commits

1. **Task 1:** `a3c13c9` (feat(182-03): R/182 facility ZIP recovery report script)
2. **Bug fixes during execution:** `7a004b4`, `f253bb7`, `93cfda3`, `023f1ee`
3. **Close-out (Task 3):** this SUMMARY + ROADMAP + REQUIREMENTS + STATE update

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] here::here() not used in test file**
- **Found during:** Task 2 HiPerGator pre-run (testthat couldn't find R/00_config.R)
- **Fix:** Replaced relative path with `here::here()` in `tests/testthat/test-utils-facility-zip.R`
- **Commit:** `7a004b4`

**2. [Rule 1 - Bug] enc_zip_raw not retained in enc_distance select**
- **Found during:** Task 2 — diagnostic workbook needed raw ZIP column
- **Fix:** Added `enc_zip_raw` to the select() in R/122
- **Commit:** `f253bb7`

**3. [Rule 1 - Bug] glue()-named stopifnot() syntax errors in R/180 D-22a**
- **Found during:** Task 2 — R/180 errored on D-22a checks
- **Fix:** Corrected glue() call syntax for named stopifnot() arguments
- **Commit:** `93cfda3`

**4. [Rule 1 - Bug] openxlsx2 leaves XML entities unescaped (&gt;) in key_val() reads**
- **Found during:** Task 2 — label matching failed for comparison rows
- **Fix:** Unescaped XML entities in key_val() reader
- **Commit:** `023f1ee`

## Known Stubs

None — all reported values read from workbooks at runtime; no hard-coded results in R/182.

## Phase 183 Readiness

Phase 183 (MICE sensitivity) has sufficient residual missing-exposure to proceed:
- **86,005** facility_zip_missing encounters (significant)
- **134,949** zip_not_in_db encounters (significant)
- Phase 179 primary OR essentially unchanged (0.83 vs 0.84) — MICE will quantify sensitivity to this residual

## Self-Check: PASSED

- R/182_facility_zip_recovery_report.R: confirmed committed (`a3c13c9`)
- 182-RECOVERY.md: placed in phase folder
- R/88: ALL 970 CHECKS PASSED confirmed by user (HiPerGator run 2026-10-14)
- FZIP-01 and FZIP-02: marked complete in REQUIREMENTS.md
- Phase 182 ticked [x] in ROADMAP.md

---
*Phase: 182-facility-zip-recovery*
*Completed: 2026-10-14*
