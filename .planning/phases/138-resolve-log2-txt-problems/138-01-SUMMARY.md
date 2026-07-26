---
phase: 138-resolve-log2-txt-problems
plan: 01
subsystem: database
tags: [duckdb, icd-codes, r-pipeline, filter-fix]

requires:
  - phase: 132-crash-fixes
    provides: DuckDB lazy-table pattern established
provides:
  - R/13 DIAGNOSIS filter uses pre-computed IN-lists, no gsub on DuckDB column
affects: [R/70, R/71, R/72 (inherit via R/13 call chain)]

tech-stack:
  added: []
  patterns: ["Pre-compute combined dotted+undotted ICD code vectors before lazy DuckDB filter — matches R/14 pattern"]

key-files:
  created: []
  modified:
    - R/13_survivorship_encounters.R

key-decisions:
  - "Replace hl_icd10_clean/hl_icd9_clean + gsub-in-filter with hl_icd10_combined/hl_icd9_combined pre-computed vectors, matching R/14 lines 140-141 exactly"

patterns-established:
  - "PATTERN-B: never apply R string functions (gsub/sub) inside filter() on a lazy DuckDB table; build the full IN-list in R first"

requirements-completed: [D-01, D-02, D-03]

duration: 5min
completed: 2026-07-26
---

# Phase 138 Plan 01: Fix R/13 DuckDB gsub-in-lazy-filter bug Summary

**Pre-computed hl_icd10_combined/hl_icd9_combined vectors replace gsub-on-DuckDB-column in R/13 DIAGNOSIS filter, fixing the invalid SQL translation crash**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-07-26T18:00:00Z
- **Completed:** 2026-07-26T18:05:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Removed `hl_icd10_clean` and `hl_icd9_clean` variables that were used inside a lazy DuckDB filter (invalid — DuckDB has no gsub function)
- Introduced `hl_icd10_combined` and `hl_icd9_combined` that pre-compute both dotted and undotted code forms in R before the filter
- Filter in `hl_dx_on_encounter` now uses only `DX %in% <vector>` — translates to valid SQL IN clause
- R/70, R/71, R/72 inherit the fix automatically via R/13's call chain

## Task Commits

1. **Fix R/13 gsub-in-lazy-filter bug** - `a814f08` (fix)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `R/13_survivorship_encounters.R` - Lines 116-130 replaced: removed gsub-in-filter, added pre-computed combined ICD vectors

## Decisions Made
- Matched R/14 lines 140-141 pattern exactly (already correct there) — consistent approach across the pipeline

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- 138-02 can proceed; R/13's DIAGNOSIS filter now translates to valid DuckDB SQL
- R/70, R/71, R/72 survivorship cascade should no longer receive the gsub SQL error

---
*Phase: 138-resolve-log2-txt-problems*
*Completed: 2026-07-26*
