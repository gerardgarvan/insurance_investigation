---
phase: 22-generalize-phase-20-to-all-sites
plan: 01
subsystem: data-quality
tags: [duplicate-dates, multi-source, payer-completeness, pcornet, encounter-analysis]

requires:
  - phase: 20-check-duplicate-dates-flm
    provides: FLM-specific duplicate date investigation pattern (R/19_flm_duplicate_dates.R)
  - phase: 21-generalize-phase-19-to-all-sources
    provides: All-source generalization pattern (R/20_all_source_missingness.R) and SOURCE column collision handling
provides:
  - All-site duplicate date investigation script (R/21_all_site_duplicate_dates.R)
  - Per-site duplicate date statistics across all 5 OneFlorida+ partner sites
  - Per-site source-preference recommendations based on payer completeness
  - Cross-site summary CSV for head-to-head comparison of duplication rates
affects: []

tech-stack:
  added: []
  patterns: [site-grouped-analysis, encounter-source-separation, cross-site-summary-with-ALL-row]

key-files:
  created:
    - R/21_all_site_duplicate_dates.R
  modified: []

key-decisions:
  - "DEMOGRAPHIC.SOURCE renamed to SITE, ENCOUNTER.SOURCE renamed to ENCOUNTER_SOURCE to avoid column collision"
  - "Per-site source recommendations generated from payer completeness rates of multi-source encounters"
  - "Cross-site summary includes ALL aggregate row sorted by descending duplicate rate"

patterns-established:
  - "Site-grouped duplicate analysis: DEMOGRAPHIC.SOURCE as primary dimension, ENCOUNTER.SOURCE as secondary"
  - "Cross-site summary CSV with one-row-per-site + ALL aggregate row pattern"

requirements-completed: [ALLDUP-01, ALLDUP-02, ALLDUP-03, ALLDUP-04, ALLDUP-05]

duration: ~15min
completed: 2026-04-14
---

# Phase 22: Generalize Phase 20 to All Sites Summary

**All-site duplicate date investigation across 5 OneFlorida+ partner sites with per-site source recommendations and cross-site comparison**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-04-14
- **Completed:** 2026-04-14
- **Tasks:** 2 (1 auto + 1 human-verify)
- **Files created:** 1

## Accomplishments
- Created R/21_all_site_duplicate_dates.R (705 lines, 8 sections) extending FLM-specific duplicate date investigation to all 5 partner sites
- Same-date duplicate detection per SITE using ADMIT_DATE and DISCHARGE_DATE
- Exact row and near-exact duplicate detection per SITE via get_dupes()
- Multi-source date identification per SITE (encounters from different ENCOUNTER.SOURCE values)
- Payer completeness comparison per ENCOUNTER_SOURCE for multi-source encounters at each site
- Per-site source-preference recommendations based on payer completeness rates
- 5 CSV files output to output/tables/ with all_site_ prefix
- Cross-site summary CSV with one row per site + ALL aggregate row for head-to-head comparison
- User verified correct execution on HiPerGator

## Task Commits

1. **Task 1: Create R/21_all_site_duplicate_dates.R** - `b51f93a` (feat)
2. **Task 2: Verify script on HiPerGator** - human-verify checkpoint (approved)

## Files Created/Modified
- `R/21_all_site_duplicate_dates.R` - All-site duplicate date investigation script (705 lines, 8 sections)

## Decisions Made
- DEMOGRAPHIC.SOURCE renamed to SITE, ENCOUNTER.SOURCE renamed to ENCOUNTER_SOURCE to prevent .x/.y column collision
- Per-site source recommendations derived from payer completeness rates among multi-source encounters
- Cross-site summary includes ALL aggregate row, sorted by descending duplicate rate with ALL last

## Deviations from Plan
None - plan executed as specified.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All-site duplicate date analysis complete
- Cross-site comparison data available for further investigation
- Pattern established for site-grouped analysis with ENCOUNTER_SOURCE separation

---
*Phase: 22-generalize-phase-20-to-all-sites*
*Completed: 2026-04-14*
