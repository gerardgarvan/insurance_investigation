---
phase: 06-use-debug-output-to-rectify-issues
plan: 01
subsystem: cohort-building
tags: [dplyr, cohort-filtering, hl-diagnosis, data-quality, csv-output]

# Dependency graph
requires:
  - phase: 05-fix-parsing
    provides: "has_hodgkin_diagnosis() with DIAGNOSIS + TUMOR_REGISTRY sources"
  - phase: 03-cohort-building
    provides: "Named predicate pattern, attrition logging, build pipeline"
provides:
  - "HL_SOURCE column tracking how each patient was identified (DIAGNOSIS only, TR only, Both)"
  - "Neither patient exclusion with audit CSV (excluded_no_hl_evidence.csv)"
  - "Updated hl_cohort.csv with 19 columns including HL_SOURCE"
affects: [06-02, 06-03, visualization, downstream-stratification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Source mapping via left_join + case_when for provenance tracking"
    - "Excluded patient audit CSV pattern for data quality investigation"

key-files:
  created: []
  modified:
    - "R/03_cohort_predicates.R"
    - "R/04_build_cohort.R"

key-decisions:
  - "HL_SOURCE computed via left_join mapping against dx_hl_patients and tr_all, not via the old union + semi_join"
  - "Neither patients excluded from return value but preserved in excluded_no_hl_evidence.csv for audit"

patterns-established:
  - "Source provenance tracking: inner_join with source map instead of semi_join for filtered predicates"
  - "Exclusion audit CSV: excluded patients written to separate file with EXCLUSION_REASON column"

requirements-completed: [RECT-01, RECT-02]

# Metrics
duration: 2min
completed: 2026-03-25
---

# Phase 6 Plan 01: HL Source Tracking Summary

**HL_SOURCE column added to cohort pipeline tracking DIAGNOSIS-only, TR-only, and Both identification; Neither patients excluded and written to audit CSV**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-25T18:02:54Z
- **Completed:** 2026-03-25T18:04:55Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- has_hodgkin_diagnosis() now returns tibble with HL_SOURCE column showing "DIAGNOSIS only", "TR only", or "Both" per patient
- Patients with HL_SOURCE = "Neither" (no evidence in any source) are excluded from the cohort and written to output/cohort/excluded_no_hl_evidence.csv with ID, SOURCE, HL_SOURCE, and EXCLUSION_REASON columns
- hl_cohort.csv output now includes 19 columns (added HL_SOURCE after SOURCE)
- Console logging shows source breakdown counts during predicate execution

## Task Commits

Each task was committed atomically:

1. **Task 1: Update has_hodgkin_diagnosis() with HL_SOURCE tracking and Neither exclusion** - `2a60d1e` (feat)
2. **Task 2: Add HL_SOURCE to cohort output and update attrition label** - `44ad049` (feat)

## Files Created/Modified
- `R/03_cohort_predicates.R` - Updated has_hodgkin_diagnosis() to build HL_SOURCE mapping via left_join + case_when, exclude Neither patients, write excluded CSV, and return tibble with HL_SOURCE column
- `R/04_build_cohort.R` - Added HL_SOURCE to final select() block (19 columns), updated attrition label to "Has HL diagnosis (ICD or histology, excludes Neither)"

## Decisions Made
None - followed plan as specified

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Known Stubs
None - all data flows are wired. HL_SOURCE column flows from has_hodgkin_diagnosis() through the pipeline to the final CSV output.

## Next Phase Readiness
- HL_SOURCE column is available for downstream stratification in visualization scripts
- excluded_no_hl_evidence.csv will be generated on next pipeline run for data quality review
- Plans 06-02 and 06-03 can proceed with the updated cohort structure

## Self-Check: PASSED

- FOUND: R/03_cohort_predicates.R
- FOUND: R/04_build_cohort.R
- FOUND: 06-01-SUMMARY.md
- FOUND: commit 2a60d1e
- FOUND: commit 44ad049

---
*Phase: 06-use-debug-output-to-rectify-issues*
*Completed: 2026-03-25*
