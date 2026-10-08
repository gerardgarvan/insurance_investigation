---
phase: 167-single-health-system-care-flag
plan: "01"
subsystem: investigation-scripts
tags: [duckdb, encounter, single-source-care, flags, tdd]
dependency_graph:
  requires:
    - utils_treatment.R::get_hl_any_dx_ids
    - utils_duckdb.R::open_pcornet_con / close_pcornet_con
    - R/00_config.R::CONFIG$analysis date range + CONFIG$output_dir
  provides:
    - build_single_source_result() pure helper (testable without DuckDB)
    - output/internal/single_source_care_<date>.csv
    - output/internal/single_source_care_<date>.rds
    - output/internal/single_source_care_parts_<date>.rds  (consumed by Plan 02)
  affects:
    - Plan 02 (workbook assembly): reads parts RDS
    - Phase 165 sensitivity model: joins on ID from CSV
tech_stack:
  added: []
  patterns:
    - duckdb_register + SQL JOIN (not IN-list) for cohort filter
    - NULLIF(UPPER(TRIM(SOURCE)), '') SOURCE normalisation in DuckDB SQL
    - opened_here pattern for safe DuckDB connection lifecycle
    - single_source_care_post flag computed before coalescing post counts
key_files:
  created:
    - tests/testthat/test-169-single-source-care.R
    - R/169_single_source_care.R
  modified: []
decisions:
  - "Used get_hl_any_dx_ids() from utils_treatment.R as anchor source (D-167-04); confirmed same function R/147 uses"
  - "NULLIF(UPPER(TRIM(SOURCE)),'') in DuckDB normalises blanks; COUNT(DISTINCT src) ignores NULLs so blanks never inflate n_sources"
  - "Post-anchor flag case_when precedes coalesce of n_sources_post to ensure zero-post-encounter patients get NA not 0"
  - "any_blank_source coalesced to FALSE (not NA) for patients absent from whole_raw (no encounters)"
  - "Parts RDS bundles result + source_counts + n_na_admit for Plan 02 workbook without re-querying DuckDB"
metrics:
  duration_seconds: 134
  completed_date: "2026-10-08"
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 0
---

# Phase 167 Plan 01: Single-Source Care Flag (SECTIONS 1B-3) Summary

**One-liner:** Patient-level `single_source_care` + `single_source_care_post` flags via DuckDB ENCOUNTER.SOURCE aggregation with NULLIF/UPPER/TRIM normalisation, opened_here connection lifecycle, and parts RDS for Plan 02 workbook.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 0 | Unit tests for build_single_source_result() | b795e1f | tests/testthat/test-169-single-source-care.R |
| 1 | R/169 SECTIONS 1B-3 implementation | 3d6ee3e | R/169_single_source_care.R |

## Verification Results

**Task 0 greps passed:**
- `grep -c "test_that"` = 6 (>= 6 required)
- All required strings present: `single_source_care_post`, `any_blank_source`, `primary_source`, `NA_integer_`

**Task 1 greps passed:**
- `build_single_source_result <- function` present
- `get_hl_any_dx_ids()` present (x2: anchor call + verified in comment)
- `duckdb_register` present (x2: cohort_ids + hl_anchors)
- `duckdb_unregister` present (x2: both tables unregistered in cleanup)
- `UPPER(TRIM(` present (x4: both SQL queries)
- `NULLIF(` present (x4: normalisation in all CTEs)
- `opened_here` present (x5: pattern fully implemented)
- `internal` present (x6: all output paths under output/internal/)
- No functional `quit()` call — only appears in comment documenting its absence
- No `openxlsx` — workbook deferred to Plan 02
- No `CASE WHEN n_sources = 1 THEN 1 ELSE 0` — correct case_when with NA branch used
- `single_source_care_post = dplyr::case_when` at line 71, before `n_sources_post = dplyr::coalesce` at line 80

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None — R/169 is complete for its scope (SECTIONS 1B-3). SECTIONS 4-5 (workbook) are explicitly deferred to Plan 02. The parts RDS is the intentional handoff mechanism.

## Self-Check: PASSED

Files created:
- FOUND: tests/testthat/test-169-single-source-care.R
- FOUND: R/169_single_source_care.R

Commits verified:
- b795e1f — test(167-01): add failing tests for build_single_source_result()
- 3d6ee3e — feat(167-01): implement R/169 SECTIONS 1B-3 single_source_care flags
