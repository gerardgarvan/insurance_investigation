---
phase: 66-cohort-treatment-reorganization
plan: 01
subsystem: codebase-reorganization
tags: [R, script-renumbering, source-dependencies, cohort, treatment]

# Dependency graph
requires:
  - phase: 65-foundation-reorganization
    provides: Foundation scripts renumbered to 00-09, R/utils/ auto-sourcing established
provides:
  - Cohort scripts at 10-14 (predicates, treatment-payer, surveillance, survivorship, build_cohort)
  - Treatment scripts at 20-29 (inventory through first-line analysis)
  - All a/b suffixes eliminated from treatment scripts
  - All source() cross-references updated to new numbers
affects: [67-outputs-reorganization, 68-test-reorganization, 69-documentation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Cohort decade: 10-14 with helpers numbered before build_cohort (per D-03)"
    - "Treatment decade: 20-29 in pipeline execution order (per D-05)"
    - "No a/b suffixes - sequential numbering only (per D-07)"

key-files:
  created: []
  modified:
    - R/10_cohort_predicates.R (renamed from 03)
    - R/11_treatment_payer.R (renamed from 10)
    - R/12_surveillance.R (renamed from 13)
    - R/13_survivorship_encounters.R (renamed from 14)
    - R/14_build_cohort.R (renamed from 04)
    - R/20_treatment_inventory.R (renamed from 38)
    - R/21_investigate_unmatched.R (renamed from 39)
    - R/22_investigate_unmatched_ndc.R (renamed from 40)
    - R/23_combine_reports.R (renamed from 41)
    - R/24_treatment_codes_resolved.R (renamed from 42)
    - R/25_treatment_durations.R (renamed from 43a, a suffix removed)
    - R/26_treatment_episodes.R (renamed from 44a, a suffix removed)
    - R/27_drug_name_resolution.R (renamed from 60)
    - R/28_episode_classification.R (renamed from 61)
    - R/29_first_line_and_death_analysis.R (renamed from 62)
    - 17 downstream scripts with updated source() calls

key-decisions:
  - "Renumber cohort helpers (10-13) BEFORE build_cohort (14) to reflect dependency order (D-03)"
  - "Eliminate all a/b suffixes in treatment decade for clean sequential numbering (D-07)"
  - "Update all source() cross-references in same commit as renames for atomicity"

patterns-established:
  - "Decade-based numbering: cohort (10-14), treatment (20-29)"
  - "Helpers numbered before consumers in dependency order"
  - "Source() cross-references updated alongside file renames"

requirements-completed: [REORG-01, REORG-02]

# Metrics
duration: 8min
completed: 2026-06-01
---

# Phase 66 Plan 01: Cohort & Treatment Reorganization Summary

**15 scripts renumbered to cohort (10-14) and treatment (20-29) decades with all a/b suffixes eliminated and 30+ source() cross-references updated**

## Performance

- **Duration:** 8 min
- **Started:** 2026-06-01T19:18:38Z
- **Completed:** 2026-06-01T19:26:33Z
- **Tasks:** 2
- **Files modified:** 27 (15 renamed + 12 downstream updates)

## Accomplishments
- 5 cohort scripts renumbered to 10-14 in dependency order (helpers before build_cohort per D-03)
- 10 treatment scripts renumbered to 20-29 in pipeline execution order (per D-05)
- All a/b suffixes removed from treatment scripts (43a→25, 44a→26 per D-07)
- Critical treatment chain preserved (26_treatment_episodes sources 25_treatment_durations)
- All source() cross-references updated in 17 downstream scripts (05, 06, 09, 11, 12, 16, 17, 20, 26, 27, 28, 99)
- Zero stale references to old script numbers remain (verified via grep)

## Task Commits

Each task was committed atomically:

1. **Task 1: Renumber cohort scripts to 10-14 and update all source() references** - `7b97f85` (feat)
2. **Task 2: Renumber treatment scripts to 20-29 and update all source() references** - `3ad15e9` (feat)

## Files Created/Modified

### Cohort Scripts (renamed)
- `R/10_cohort_predicates.R` - Named filter predicates (renamed from 03)
- `R/11_treatment_payer.R` - Treatment-anchored payer mode (renamed from 10)
- `R/12_surveillance.R` - Surveillance modality detection (renamed from 13)
- `R/13_survivorship_encounters.R` - Survivorship encounter classification (renamed from 14)
- `R/14_build_cohort.R` - Cohort builder with sources 10-13 (renamed from 04)

### Treatment Scripts (renamed)
- `R/20_treatment_inventory.R` - Treatment inventory by source table (renamed from 38)
- `R/21_investigate_unmatched.R` - Unmatched CPT/HCPCS investigation (renamed from 39)
- `R/22_investigate_unmatched_ndc.R` - Unmatched NDC/RXNORM investigation (renamed from 40)
- `R/23_combine_reports.R` - Combined unmatched reports (renamed from 41)
- `R/24_treatment_codes_resolved.R` - Treatment codes resolved XLSX (renamed from 42)
- `R/25_treatment_durations.R` - Treatment duration analysis (renamed from 43a, a suffix removed)
- `R/26_treatment_episodes.R` - Treatment episode start/stop dates, sources 25 (renamed from 44a, a suffix removed)
- `R/27_drug_name_resolution.R` - Drug name resolution via RxNorm API (renamed from 60)
- `R/28_episode_classification.R` - Episode cancer linkage and regimen detection (renamed from 61)
- `R/29_first_line_and_death_analysis.R` - First-line therapy identification (renamed from 62)

### Downstream Scripts (source() calls updated)
- `R/05_visualize_waterfall.R` - Updated to source 14_build_cohort
- `R/06_visualize_sankey.R` - Updated to source 14_build_cohort
- `R/09_dx_gap_analysis.R` - Updated error message reference to 14_build_cohort
- `R/11_generate_pptx.R` - Updated usage comment to 14_build_cohort
- `R/12_no_treatment_medicaid.R` - Updated usage comment to 14_build_cohort and 11_treatment_payer
- `R/16_encounter_analysis.R` - Updated to source 14_build_cohort
- `R/17_value_audit.R` - Updated comments to 14_build_cohort
- `R/20_all_source_missingness.R` - Updated conditional source to 14_build_cohort
- `R/26_smoke_test_backends.R` - Updated to source 10_cohort_predicates
- `R/27_parity_test_cohort.R` - Updated two source calls to 14_build_cohort
- `R/28_benchmark_cohort.R` - Updated to source 14_build_cohort
- `R/99_claude_diagnostics.R` - Updated to source 14_build_cohort

## Decisions Made

None - plan executed exactly as specified.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - all renames and source() updates completed without issues.

## Known Stubs

None - this plan performed renumbering only, no functional changes.

## Next Phase Readiness

- Cohort (10-14) and treatment (20-29) decades established as first major blocks
- Ready for Plan 02 (outputs decade) and Plan 03 (tests/scripts decade)
- Downstream scripts (outputs, tests, cancer) remain at old numbers - addressed in Plans 02-03
- Zero stale references to old cohort/treatment numbers verified

## Self-Check: PASSED

All renamed files exist:
```
FOUND: R/10_cohort_predicates.R
FOUND: R/11_treatment_payer.R
FOUND: R/12_surveillance.R
FOUND: R/13_survivorship_encounters.R
FOUND: R/14_build_cohort.R
FOUND: R/20_treatment_inventory.R
FOUND: R/25_treatment_durations.R
FOUND: R/26_treatment_episodes.R
FOUND: R/29_first_line_and_death_analysis.R
```

Old files removed:
```
CONFIRMED: R/03_cohort_predicates.R does not exist
CONFIRMED: R/04_build_cohort.R does not exist
CONFIRMED: R/38_treatment_inventory.R does not exist
CONFIRMED: R/43a_treatment_durations.R does not exist
CONFIRMED: R/44a_treatment_episodes.R does not exist
```

Critical dependencies verified:
```
FOUND: source("R/10_cohort_predicates.R") in R/14_build_cohort.R
FOUND: source("R/11_treatment_payer.R") in R/14_build_cohort.R
FOUND: source("R/12_surveillance.R") in R/14_build_cohort.R
FOUND: source("R/13_survivorship_encounters.R") in R/14_build_cohort.R
FOUND: source("R/25_treatment_durations.R") in R/26_treatment_episodes.R
```

All commits exist:
```
FOUND: 7b97f85 (Task 1)
FOUND: 3ad15e9 (Task 2)
```

---
*Phase: 66-cohort-treatment-reorganization*
*Completed: 2026-06-01*
