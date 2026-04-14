---
phase: 20-check-duplicate-dates-of-flm-subjects
plan: 01
subsystem: data-quality,diagnostics
tags: [flm, duplicate-dates, encounter-deduplication, payer-completeness, multi-source, data-investigation]
completed: 2026-04-09

dependency_graph:
  requires:
    - phase: 19-investigate-insurance-missingness
      provides: Missingness definition (NA, empty, NI, UN, OT, 99, 9999)
  provides:
    - R/19_flm_duplicate_dates.R (standalone FLM duplicate date diagnostic)
    - Same-date and exact duplicate detection methodology
    - Multi-source date identification
    - Payer completeness comparison across sources
    - Source-preference recommendation logic
    - 3 CSV outputs (patient-level, date-level, aggregate)
  affects:
    - Phase 22 (generalized this investigation to all 5 partner sites)

tech_stack:
  added: []
  patterns:
    - Same-date duplicate detection via group_by(PATID, ADMIT_DATE) + n() > 1
    - Exact row duplicate detection via janitor::get_dupes()
    - Multi-source date identification (encounters from different SOURCE on same date)
    - Payer completeness comparison using Phase 19 missing_indicators definition

key_files:
  created:
    - R/19_flm_duplicate_dates.R
  modified: []

decisions: []

requirements-completed: [FLMDUP-01, FLMDUP-02, FLMDUP-03, FLMDUP-04]

metrics:
  tasks_completed: 1
  tasks_total: 1
  commits: 1
  files_modified: 1
---

# Phase 20 Plan 01: FLM Duplicate Date Investigation Summary

**Created FLM duplicate date diagnostic script (507 lines) investigating same-date encounter collisions and exact row duplicates with multi-source identification, payer completeness comparison across data sources, and source-preference recommendation**

## Performance

- **Duration:** Committed 2026-04-09
- **Commit:** 6e2e756
- **Tasks:** 1/1 complete
- **Files created:** 1 (R/19_flm_duplicate_dates.R, 507 lines)

## What Was Built

Created `R/19_flm_duplicate_dates.R` as a standalone diagnostic script investigating duplicate encounter dates for FLM-sourced patients. The script has 8 sections:

1. **Patient identification** -- Identifies FLM patients via DEMOGRAPHIC.SOURCE
2. **Encounter filtering** -- Filters ENCOUNTER table to FLM patient encounters
3. **Same-date duplicate detection** -- Groups by PATID + ADMIT_DATE, flags dates with >1 encounter
4. **Exact row duplicate detection** -- Uses janitor::get_dupes() to find fully identical rows
5. **Multi-source date identification** -- Detects encounters from different SOURCE values on the same date
6. **Payer completeness comparison** -- Compares payer data availability across sources for duplicate encounters
7. **CSV outputs** -- Three diagnostic CSVs to output/tables/
8. **Console summary** -- Aggregated statistics and source-preference recommendation

Uses Phase 19's missingness definition (NA, empty, NI, UN, OT, 99, 9999) for consistent payer completeness assessment.

## Accomplishments

- Quantified same-date duplicate encounter rates for all FLM patients
- Separated exact row duplicates from same-date collisions (different encounter types/sources on same date)
- Identified multi-source date patterns revealing data integration issues
- Compared payer completeness across sources to inform deduplication strategy
- Generated source-preference recommendation based on payer data quality
- Findings generalized to all 5 sites by Phase 22

## Task Commits

1. **Task 1: Create FLM duplicate date diagnostic** -- `6e2e756` (feat)
   - R/19_flm_duplicate_dates.R created (507 lines, 8 sections)
   - Same-date and exact duplicate detection
   - Multi-source identification and payer completeness comparison
   - 3 CSV outputs and console summary

## Files Created/Modified

- `R/19_flm_duplicate_dates.R` -- Standalone FLM duplicate date diagnostic script (507 lines) with 8 analytical sections

### Output files (generated on HiPerGator)

- `output/tables/flm_patient_duplicate_summary.csv` -- Patient-level summary with encounter counts, duplicate dates, multi-source dates, payer completeness per source
- `output/tables/flm_date_level_duplicate_detail.csv` -- Date-level detail showing all encounters on duplicate dates
- `output/tables/flm_aggregate_duplicate_stats.csv` -- Aggregate statistics and source comparison

## Decisions Made

None -- followed plan as specified.

## Deviations from Plan

None -- plan executed exactly as written.

## Known Stubs

None. Script is a complete diagnostic tool with all analytical sections and CSV outputs.

## Impact & Next Steps

**Immediate impact:** Quantified FLM encounter date duplication patterns and identified source-level data quality differences.

**Downstream consumption:** Phase 22 ("Generalize Phase 20 to All Sites") extended this investigation to all 5 partner sites (AMS, UMI, FLM, VRT, UFH) with cross-site comparison and per-site source recommendations.

## Self-Check: PASSED

- R/19_flm_duplicate_dates.R: FOUND (507 lines)
- Commit 6e2e756: FOUND

---
*Phase: 20-check-duplicate-dates-of-flm-subjects*
*Completed: 2026-04-09*
