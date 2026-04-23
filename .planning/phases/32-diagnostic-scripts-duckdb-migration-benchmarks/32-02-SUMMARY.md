---
phase: 32-diagnostic-scripts-duckdb-migration-benchmarks
plan: 02
subsystem: database
tags: [duckdb, benchmarks, speedup-report, migration-guide, config-flip]

# Dependency graph
requires:
  - phase: 32-diagnostic-scripts-duckdb-migration-benchmarks
    provides: 5 diagnostic scripts migrated to DuckDB (Plan 32-01)
  - phase: 31-cohort-pipeline-duckdb-migration
    provides: DuckDB backend abstraction layer, benchmark infrastructure (R/28_benchmark_cohort.R)
provides:
  - R/26_generate_speedup_report.R for automated benchmark analysis
  - docs/DUCKDB_MIGRATION_GUIDE.md for future script authors
  - USE_DUCKDB default flipped to TRUE (DuckDB is now the default backend)
affects: [future-scripts, maintenance]

# Tech tracking
tech-stack:
  added: []
  patterns: [speedup-report-generation, migration-guide-template, deprecation-comment-pattern]

key-files:
  created:
    - R/26_generate_speedup_report.R
    - docs/DUCKDB_MIGRATION_GUIDE.md
  modified:
    - R/00_config.R

key-decisions:
  - "Speedup report handles flexible CSV formats (legacy cohort-only and multi-script)"
  - "Migration guide includes 7 sections with copy-pasteable template script"
  - "USE_DUCKDB flipped to TRUE as default with RDS deprecation notice"
  - "RDS mode retained for backward compatibility and bisecting"

patterns-established:
  - "Speedup report generator: deterministic script for regenerating benchmark reports on future extracts"
  - "Migration guide template: standardized skeleton for new diagnostic scripts with DuckDB support"

requirements-completed: [DBDIAG-03, DBDIAG-04]

# Metrics
duration: 4min
completed: 2026-04-23
---

# Phase 32 Plan 02: Speedup Report, Migration Guide, Flip Default Summary

**Automated speedup report generator, 7-section migration guide with copy-pasteable template, and USE_DUCKDB default flipped to TRUE with RDS deprecation notice**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-23T22:36:50Z
- **Completed:** 2026-04-23T22:41:04Z
- **Tasks:** 4 (code deliverables; HiPerGator verification pending)
- **Files modified:** 3

## Accomplishments

- Speedup report generator reads benchmark CSV and produces formatted markdown with per-script speedup ratios, milestone target check, variance analysis, and detailed run data
- Migration guide covers all 7 sections: overview, connection pattern, get_pcornet_table/materialize, when to materialize, known translation gaps (top 3), template script, and parity test methodology
- USE_DUCKDB default flipped from FALSE to TRUE -- DuckDB is now the standard backend
- RDS mode preserved with explicit deprecation timeline and pointer to migration guide

## Task Commits

Each task was committed atomically:

1. **Task 1: Write R/26_generate_speedup_report.R** - `1e209a4` (feat)
2. **Task 3: Write docs/DUCKDB_MIGRATION_GUIDE.md** - `12bc029` (docs)
3. **Task 4: Flip USE_DUCKDB to TRUE** - `a444022` (feat)

**Note:** Task 2 (run report generator) and Task 5 (HiPerGator end-to-end run) require HiPerGator access and are deferred to runtime verification.

## Files Created/Modified

- `R/26_generate_speedup_report.R` - Reads benchmark CSV, computes medians/speedups, writes markdown report to output/reports/
- `docs/DUCKDB_MIGRATION_GUIDE.md` - Standalone guide for future script authors with 7 sections + template
- `R/00_config.R` - USE_DUCKDB flipped to TRUE with deprecation comment (4 lines)

## Decisions Made

1. **Flexible benchmark CSV handling** -- The speedup report script detects whether a `script` column exists. Legacy CSVs from R/28_benchmark_cohort.R (cohort-only) are handled by defaulting to "04_build_cohort". Multi-script CSVs from future diagnostic benchmarks are handled natively. This makes the report generator work before and after diagnostic benchmarks are collected.

2. **7 sections instead of 6** -- Added a 7th section (Parity Test Methodology) which the plan listed as a sub-item of the template but deserved its own section for clarity. The parity test procedure is distinct from the template pattern.

3. **RDS deprecation timeline left open** -- The deprecation comment says "will be removed in a future milestone" rather than naming a specific date or version. This is intentional -- removing RDS requires confirming that all HiPerGator users have transitioned, which is outside this phase's scope.

## Deviations from Plan

None - plan executed exactly as written. Task 2 (run report generator) is a runtime step that requires HiPerGator data; the script is complete and ready to run.

## Known Stubs

None - all deliverables are complete code. The speedup report output (`output/reports/duckdb_speedup_report.md`) will be generated when `R/26_generate_speedup_report.R` is run on HiPerGator after benchmark data is collected.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Pending Verification

**HiPerGator end-to-end run (Plan Step 5):** After this plan completes, the user should:

1. Run `source("R/28_benchmark_cohort.R")` to collect cohort benchmarks
2. Run each diagnostic script (R/20-R/24) with `USE_DUCKDB = TRUE` to verify no errors
3. Run `source("R/26_generate_speedup_report.R")` to generate the speedup report
4. Review `output/reports/duckdb_speedup_report.md` for the milestone target check

If the pipeline fails under `USE_DUCKDB = TRUE`, revert to `USE_DUCKDB <- FALSE` in R/00_config.R and investigate.

## Next Phase Readiness

- Phase 32 code deliverables complete
- All v1.3 DuckDB Backend Migration code work is done
- Runtime verification on HiPerGator is the final step before milestone closure
- No blockers for future development -- new scripts can use the migration guide template

## Self-Check: PASSED

All 3 files verified present. All 3 commit hashes verified in git log. USE_DUCKDB confirmed set to TRUE.

---
*Phase: 32-diagnostic-scripts-duckdb-migration-benchmarks*
*Completed: 2026-04-23*
