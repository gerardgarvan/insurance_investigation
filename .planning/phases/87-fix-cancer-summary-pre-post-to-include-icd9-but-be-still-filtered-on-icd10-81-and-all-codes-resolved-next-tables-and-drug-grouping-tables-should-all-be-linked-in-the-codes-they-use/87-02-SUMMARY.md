---
phase: 87-fix-cancer-summary-pre-post-to-include-icd9
plan: 02
subsystem: diagnostics
tags: [icd-9, icd-10, cancer-codes, hl-cohort, coding-system-agnostic]

# Dependency graph
requires:
  - phase: 87-01
    provides: is_cancer_code() and classify_codes() with ICD-9 support in R/utils/utils_cancer.R
provides:
  - Cancer summary pipeline (R/45, R/47, R/48, R/49) expanded to ICD-9 + ICD-10
  - HL cohort confirmation with C81 + 201.x codes
  - Cross-system category aggregation via classify_codes()
  - Code-level summaries with separate ICD-9 and ICD-10 entries
affects: [cancer-summary, hl-cohort, pre-post-analysis, treatment-episodes]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Map-based cancer code detection (is_cancer_code) over DX_TYPE filtering"
    - "4-tier classification cascade (ICD-10 4-char > ICD-10 3-char > ICD-9 4-char > ICD-9 3-char)"
    - "Defense-in-depth filtering (is_cancer_code + D-code + 210-239 removal)"

key-files:
  created: []
  modified:
    - R/45_cancer_summary.R
    - R/47_cancer_summary_refined.R
    - R/48_cancer_summary_post_hl.R
    - R/49_cancer_summary_pre_post.R

key-decisions:
  - "Removed all DX_TYPE==10 hard-filters in favor of is_cancer_code() map-based detection"
  - "Expanded HL cohort confirmation from C81-only to C81+201.x (cross-system 7-day gap allowed)"
  - "Added ICD-9 benign/uncertain exclusion (210-239) alongside D-code filtering for defense-in-depth"
  - "Widened R/49 V2 assertion upper bound from 6500 to 7500 to accommodate ICD-9 cohort expansion"

patterns-established:
  - "Cancer summary pipeline loading: select(ID, DX, DX_TYPE, DX_DATE) → collect() → is_cancer_code() → D-code+210-239 filter"
  - "HL diagnostic queries: filter(^C81 | ^201) for cross-system HL detection"
  - "Code-level NA handling: if_else(^C81 | ^201, NA_integer_, ...) for anchor code exclusion"

requirements-completed:
  - ICD-01
  - ICD-02
  - ICD-09
  - ICD-10
  - ICD-11
  - ICD-12

# Metrics
duration: 5min
completed: 2026-06-04
---

# Phase 87 Plan 02: Cancer Summary ICD-9 Expansion Summary

**Cancer summary pipeline (R/45-49) expanded to include ICD-9 codes, HL cohort confirmation broadened to C81+201.x, and cross-system aggregation via classify_codes()**

## Performance

- **Duration:** 5 min
- **Started:** 2026-06-04T04:27:06Z
- **Completed:** 2026-06-04T04:32:09Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Removed all DX_TYPE=="10" hard-filters from 4 cancer summary scripts
- Expanded HL cohort confirmation to include ICD-9 201.x codes alongside ICD-10 C81
- Added defense-in-depth filtering: is_cancer_code() + D-code removal + ICD-9 210-239 exclusion
- Updated R/49 NLPHL split to detect ICD-9 201.4x alongside ICD-10 C81.0x
- Widened R/49 V2 assertion bounds to accommodate ICD-9 cohort expansion (6500 → 7500)

## Task Commits

Each task was committed atomically:

1. **Task 1: Update R/45 and R/47 -- remove DX_TYPE filter, expand cohort confirmation** - `e113f83` (feat)
   - R/45: Load all diagnosis codes, filter via is_cancer_code()
   - R/47: Expand cohort confirmation to C81 + 201.x, add 210-239 exclusion, update record counts query

2. **Task 2: Update R/48 and R/49 -- remove DX_TYPE filters, expand HL anchor exclusion** - `2f9f678` (feat)
   - R/48: Load all cancer codes with is_cancer_code()
   - R/49: Expand HL diagnostic section to C81 + 201.x, remove 3 DX_TYPE filters, extend anchor exclusion, update NLPHL split, widen V2 assertion, update record counts

## Files Created/Modified
- `R/45_cancer_summary.R` - Loads all diagnosis codes (ICD-9 + ICD-10), filters via is_cancer_code(), sources utils_cancer.R
- `R/47_cancer_summary_refined.R` - Expands HL cohort confirmation to C81 + 201.x, adds 210-239 exclusion, updates record counts query
- `R/48_cancer_summary_post_hl.R` - Loads all cancer codes, applies 210-239 exclusion, sources utils_cancer.R
- `R/49_cancer_summary_pre_post.R` - Expands HL diagnostics to C81 + 201.x, updates NLPHL split (C81.0x + 201.4x), extends anchor exclusion, widens V2 assertion (6300-7500)

## Decisions Made

**1. Removed DX_TYPE filters in favor of is_cancer_code():**
- **Rationale:** Map-based detection ensures gap-free coverage. Every code detected as cancer can be classified by classify_codes(). Range-based detection (140-239) would include benign codes (210-239) that classify_codes() cannot classify, creating "detected but unclassified" records.

**2. Expanded HL cohort confirmation to C81 + 201.x:**
- **Rationale:** Per D-09/D-10, HL cohort must include ICD-9-diagnosed patients (pre-Oct 2015). Cross-system 7-day gap allowed because both coding systems represent the same disease.

**3. Defense-in-depth filtering (is_cancer_code + D-code + 210-239):**
- **Rationale:** is_cancer_code() already excludes 210-239 malignant-only map), but explicit D-code and 210-239 filters prevent data leaks if upstream detection changes.

**4. Widened R/49 V2 assertion to 7500:**
- **Rationale:** ICD-9 201.x expansion may increase cohort by 5-15% (OneFlorida+ 2011-2025 date range includes ICD-9 era). Upper bound widened conservatively; assertion will catch unexpected cohort size changes.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Cancer summary pipeline is now coding-system agnostic
- HL cohort confirmation includes ICD-9 201.x patients
- Ready for downstream table creation (drug grouping, all_codes_resolved_next_tables)
- Self-check pending: Scripts will be run on HiPerGator to validate ICD-9 code inclusion and cohort size

## Known Stubs

None - no hardcoded empty values or placeholder text introduced

## Self-Check

Will be performed after first HiPerGator run (local testing infrastructure not yet complete).

---
*Phase: 87-fix-cancer-summary-pre-post-to-include-icd9*
*Completed: 2026-06-04*
