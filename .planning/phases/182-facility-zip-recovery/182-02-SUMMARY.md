---
phase: 182-facility-zip-recovery
plan: 02
subsystem: data-pipeline
tags: [facility-zip, encounter-distance, diagnostic-workbook, smoke-test, R, openxlsx2]

requires:
  - phase: 182-01
    provides: utils_facility_zip.R, CONFIG$facility_zip_fill, R/122 wiring with facility_zip_source

provides:
  - R/122 Section 12b: 182_facility_zip_diagnosis_YYYYMMDD.xlsx (5 sheets)
  - R/180 D-22a: data-driven reproduction check (reads Phase 179 xlsx by RDS date)
  - R/88 SMOKE-182-01 section (10 checks)
  - SCRIPT_INDEX row for utils/utils_facility_zip.R

affects:
  - 182-03 (HiPerGator run consumes diagnostic workbook; R/88 smoke confirms structure)

tech-stack:
  added: []
  patterns:
    - "Diagnostic workbook: 5 sheets KEY/A/B/C/QC; baseline via env R122_BASELINE_RDS; sup11() suppression"
    - "Data-driven repro check: derive xlsx date from RDS name; read Model_Results by exact label"
    - "SMOKE section: local p182_chk() wrapper updating both local and global counters"

key-files:
  created: []
  modified:
    - R/122_encounter_distance.R
    - R/180_cbc_missing_capture.R
    - R/39_run_all_investigations.R
    - R/SCRIPT_INDEX.md
    - R/88_smoke_test_comprehensive.R

key-decisions:
  - "D-22a: R/180 repro check reads expected OR/CI from Phase 179 workbook matching pinned RDS date; P179_PRIMARY_LABEL = 'Primary: years 2+'"
  - "Baseline RDS for Section 12b: env R122_BASELINE_RDS; absent = workbook written with 'baseline not available' note (no hypothetical fill)"
  - "R/88 new baseline: ~970 CHECKS PASSED (960 + 10 new SMOKE-182-01 checks)"

requirements-completed: [FZIP-01]

duration: 25min
completed: 2026-10-14
---

# Phase 182 Plan 02: Diagnostic Workbook and Smoke Test Summary

**Phase 182 diagnostic workbook (5 sheets, baseline-aware), R/180 data-driven reproduction check (reads xlsx not hard-coded constants), and SMOKE-182-01 structural section (10 checks) added to R/88**

## Performance

- **Duration:** ~25 min
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- R/122 Section 12b: `182_facility_zip_diagnosis_YYYYMMDD.xlsx` with 5 sheets (KEY/A_status_summary/B_facility_table/C_zip_not_in_db/QC). Before/after comparison via `R122_BASELINE_RDS` env; gracefully degrades if absent. sup11() suppression applied to all counts 1-10. Hard QC stopifnot: no computed→other transition, filled_tier1 enc count == sum of missing enc for filled keys.
- R/122 KEY: 5 rows added for Phase 182 fill counts (toggle, filled_tier1 enc, ambiguous keys, no_donor keys, no-key enc)
- R/180 D-22a: removed hardcoded `0.84`/`0.73`/`0.98` constants; now reads `Model_Results` sheet from the Phase 179 xlsx whose date matches the pinned RDS (`cbc_patient_year_YYYYMMDD.xlsx`); uses `P179_PRIMARY_LABEL = "Primary: years 2+"`; stops with clear message if workbook or row missing
- R/39: updated R/122 inline comment to mention diagnosis workbook
- SCRIPT_INDEX: row for `utils/utils_facility_zip.R`
- R/88 Section 15at: SMOKE-182-01 with 10 structural checks using check()/skip_check() conventions

## Task Commits

1. **Task 1-3 combined:** `292c2d1` (feat)

## Files Created/Modified

- `R/122_encounter_distance.R` — Section 12b diagnostic workbook + KEY rows (Phase 182)
- `R/180_cbc_missing_capture.R` — D-22a data-driven repro check; no more hard-coded 0.84/0.73/0.98
- `R/39_run_all_investigations.R` — R/122 comment updated
- `R/SCRIPT_INDEX.md` — utils_facility_zip.R row added
- `R/88_smoke_test_comprehensive.R` — Section 15at SMOKE-182-01 (10 checks)

## Decisions Made

- R/88 new total check baseline: ~970 CHECKS PASSED (Phase 175 baseline 960 + 10 new SMOKE-182-01 checks); downstream phases should cite "PASS == total, FAIL == 0" not a fixed number
- openxlsx::read.xlsx used for R/180 D-22a (R/180 already uses openxlsx, not openxlsx2)

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None

## Next Phase Readiness

- All code written; Phase 182-03 requires HiPerGator run (interactive R, compute node)
- R/182_facility_zip_recovery_report.R still needs to be written (Plan 03 Task 1)
- Unit tests for utils_facility_zip.R will run in the 182-03 HiPerGator session

---
*Phase: 182-facility-zip-recovery*
*Completed: 2026-10-14*
