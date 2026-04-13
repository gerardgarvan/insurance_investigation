---
phase: 21-generalize-phase-19-to-all-sources
plan: 01
subsystem: data-analysis
tags: [pcornet, payer, missingness, cross-site, diagnostic, dplyr]

requires:
  - phase: 19-investigate-insurance-missingness-source-uf-specifically
    provides: UFH-specific payer missingness diagnostic pattern (R/18_uf_insurance_missingness.R)
provides:
  - R/20_all_source_missingness.R -- all-source payer missingness diagnostic script
  - 6 CSV files in output/tables/ with all_source_ prefix for cross-site comparison
affects: []

tech-stack:
  added: []
  patterns: [select(-SOURCE) before DEMOGRAPHIC join to avoid PCORnet CDM column collision]

key-files:
  created:
    - R/20_all_source_missingness.R
  modified: []

key-decisions:
  - "select(-SOURCE) needed on ENCOUNTER/encounters before joining DEMOGRAPHIC — both PCORnet tables have SOURCE column causing .x/.y collision"
  - "HL cohort patients only (not all patients) per D-05 — uses source('R/04_build_cohort.R') for hl_cohort"
  - "Cross-site summary has numeric columns only — no severity flags or interpretation per D-03"
  - "ALL aggregate row uses SOURCE = 'ALL' for totals across all sites"

patterns-established:
  - "PCORnet CDM join pattern: always select(-SOURCE) from ENCOUNTER before joining DEMOGRAPHIC to get partner site SOURCE"

requirements-completed: [ALLMISS-01, ALLMISS-02, ALLMISS-03, ALLMISS-04, ALLMISS-05]

duration: ~15min
completed: 2026-04-13
---

# Phase 21: Generalize Phase 19 to All Sources — Plan 01 Summary

**All-source payer missingness diagnostic with 6 cross-site CSV breakdowns and console summary for 5 OneFlorida+ partner sites**

## Performance

- **Duration:** ~15 min
- **Completed:** 2026-04-13
- **Tasks:** 2 (1 auto + 1 human-verify)
- **Files created:** 1

## Accomplishments
- Created R/20_all_source_missingness.R (504 lines, 9 sections) extending Phase 19's UFH-specific pattern to all 5 sites
- Produces 6 CSV files with SOURCE grouping: raw value distribution, year breakdown, encounter type, year x type crosstab, raw vs harmonized, cross-site summary
- Cross-site summary provides one row per site + ALL aggregate for head-to-head comparison
- Console output shows per-site PRIMARY missingness rates with >50% highlighting
- User verified script runs correctly on HiPerGator with all 5 sites visible

## Task Commits

1. **Task 1: Create R/20_all_source_missingness.R** - `880e373` (feat)
2. **Task 2: User verification on HiPerGator** - approved
3. **Bug fix: SOURCE column collision** - `15a2f29` (fix)

## Files Created/Modified
- `R/20_all_source_missingness.R` - Standalone all-source payer missingness diagnostic (504 lines)

## Decisions Made
- Both ENCOUNTER and DEMOGRAPHIC have SOURCE column in PCORnet CDM; must select(-SOURCE) from ENCOUNTER before joining DEMOGRAPHIC to avoid .x/.y collision
- HL cohort scoping via source("R/04_build_cohort.R") per discussion decision D-05

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] ENCOUNTER SOURCE column collision with DEMOGRAPHIC SOURCE**
- **Found during:** User testing on HiPerGator (Task 2)
- **Issue:** Both pcornet$ENCOUNTER and pcornet$DEMOGRAPHIC have a SOURCE column. left_join created SOURCE.x/SOURCE.y, so group_by(SOURCE) failed
- **Fix:** Added select(-SOURCE) before inner_join/left_join in Section 2 and Section 7
- **Files modified:** R/20_all_source_missingness.R
- **Verification:** User confirmed script runs successfully after fix
- **Committed in:** 15a2f29

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Fix was necessary for script to run. Pattern documented for future scripts.

## Issues Encountered
- SOURCE column name collision between ENCOUNTER and DEMOGRAPHIC tables — resolved by dropping ENCOUNTER's SOURCE before joining

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Cross-site missingness data available for analysis
- Pattern established for any future multi-site diagnostic scripts

---
*Phase: 21-generalize-phase-19-to-all-sources*
*Completed: 2026-04-13*
