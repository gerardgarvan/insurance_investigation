---
phase: 06-use-debug-output-to-rectify-issues
plan: 03
subsystem: diagnostics
tags: [diagnostics, data-quality, pipeline-rebuild, pcornet-cdm, validation, end-to-end]

# Dependency graph
requires:
  - phase: 06-01
    provides: "HL_SOURCE tracking and Neither exclusion in cohort predicates"
  - phase: 06-02
    provides: "_VALID validation columns, diagnostic audit comments, payer documentation"
provides:
  - "Updated 07_diagnostics.R reflecting Plan 01/02 pipeline changes"
  - "New 08_data_quality_summary.R generating data_quality_summary.csv with 13 issue categories"
  - "Full end-to-end pipeline verified on HiPerGator"
  - "D-16 clean enough criterion met: all issues resolved or explained"
affects: [pipeline-complete, data-quality-reporting]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Data quality resolution tracker: tribble-based summary with before/after counts and status classification"
    - "_VALID column exclusion in diagnostic discrepancy checks"

key-files:
  created:
    - "R/08_data_quality_summary.R"
  modified:
    - "R/07_diagnostics.R"

key-decisions:
  - "Section 3 excludes _VALID columns from discrepancy check to avoid false positives from validation columns added in Plan 02"
  - "data_quality_summary.csv uses 3 status levels: fixed (resolved by code change), accepted (cosmetic or optional-field issue), documented (flagged by _VALID column for downstream filtering)"
  - "13 issue categories cover all 6 diagnostic sections from the original 07_diagnostics.R output"

patterns-established:
  - "Numbered script convention: 08_data_quality_summary.R follows pipeline numbering"
  - "Before/after count tracking: hardcoded baseline from diagnostic output, computed current from live data"

requirements-completed: [RECT-05]

# Metrics
duration: ~35min (including HiPerGator verification by user)
completed: 2026-03-25
---

# Phase 6 Plan 03: Diagnostics Update & Data Quality Summary

**Updated 07_diagnostics.R for Plan 01/02 changes, created 08_data_quality_summary.R with 13-category resolution tracker, full pipeline verified end-to-end on HiPerGator**

## Performance

- **Duration:** ~35 min (including HiPerGator verification)
- **Started:** 2026-03-25T18:42:00Z
- **Completed:** 2026-03-25T19:17:00Z
- **Tasks:** 2 (1 auto + 1 checkpoint:human-verify)
- **Files modified:** 2

## Accomplishments
- Updated R/07_diagnostics.R Section 3 to exclude _VALID validation columns from column discrepancy checks (prevents false positives)
- Updated R/07_diagnostics.R Section 4 to check for excluded_no_hl_evidence.csv file written by Plan 01's has_hodgkin_diagnosis() changes
- Updated R/07_diagnostics.R Section 6 to summarize _VALID column results and write validation_column_summary.csv
- Created R/08_data_quality_summary.R with 13 diagnostic finding categories, before/after counts, and status classification (fixed/accepted/documented)
- Full pipeline (00_config through 06_sankey) verified running end-to-end on HiPerGator by user
- D-16 "clean enough" criterion met: all diagnostic issues are resolved or explained with no unexplained anomalies

## Task Commits

Each task was committed atomically:

1. **Task 1: Update 07_diagnostics.R and create 08_data_quality_summary.R** - `c9d57a7` (feat)
2. **Task 2: Full pipeline rebuild and final diagnostic verification on HiPerGator** - VERIFIED by user (checkpoint, no commit)

## Files Created/Modified
- `R/07_diagnostics.R` - Section 3: exclude _VALID columns from discrepancy check; Section 4: check excluded_no_hl_evidence.csv; Section 6: _VALID column summary + validation_column_summary.csv output
- `R/08_data_quality_summary.R` - New script sourcing 01_load_pcornet.R, computing post-fix counts for date parsing, age sentinels, future/pre-1900 dates, encoding, and HL identification; builds tribble with 13 rows; writes to output/diagnostics/data_quality_summary.csv

## Decisions Made
- **_VALID column exclusion from discrepancy checks:** These columns are added programmatically by load_pcornet_table() and are not in the PCORnet CDM spec. Excluding them from Section 3's "extra columns" check avoids noisy false positives.
- **13-category resolution format:** Covers all findings from the 6 diagnostic sections with granular categories (e.g., separate rows for AGE_AT_DIAGNOSIS=200, DXAGE negative, DXAGE=200, DXAGE=999) rather than collapsing into generic "age issues."
- **Status classification:** "fixed" for issues resolved by code changes (date parsing, Neither exclusion), "accepted" for cosmetic/optional-field issues (encoding, high missing values), "documented" for issues flagged by _VALID columns for downstream filtering decisions.

## Deviations from Plan

None -- plan executed as written. Task 1 implemented the diagnostic updates and summary script, Task 2 was verified by user on HiPerGator.

## Issues Encountered
None

## Known Stubs
None -- all data flows are wired. The 08_data_quality_summary.R script computes current counts from live data and writes the summary CSV.

## User Setup Required
None -- no external service configuration required.

## Phase 6 Completion

This is the final plan in Phase 6. All remediation objectives are met:
- **RECT-01 (Plan 01):** HL_SOURCE tracking in cohort output
- **RECT-02 (Plan 01):** Neither patient exclusion with audit CSV
- **RECT-03 (Plan 02):** Date parser, regex, col_types, and validation fixes applied
- **RECT-04 (Plan 02):** R vs Python payer mapping documented
- **RECT-05 (Plan 03):** Full pipeline rebuild verified, data_quality_summary.csv confirms all issues resolved or explained

The R pipeline is now complete from data loading through visualization with all data quality issues addressed.

## Self-Check: PASSED

- FOUND: R/07_diagnostics.R
- FOUND: R/08_data_quality_summary.R
- FOUND: commit c9d57a7

---
*Phase: 06-use-debug-output-to-rectify-issues*
*Completed: 2026-03-25*
