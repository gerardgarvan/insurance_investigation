---
phase: 106-tableau-ready-data-tables
plan: 01
subsystem: investigation-scripts
tags: [tableau, xlsx, cancer-codes, chemotherapy, drug-grouping]
dependency_graph:
  requires: [treatment_episode_detail.rds, DuckDB DIAGNOSIS, all_codes_resolved_next_tables_v2.1.xlsx]
  provides: [tableau_table1_encounter_cancer_codes.xlsx, tableau_table2_chemo_drugs_by_class.xlsx]
  affects: [R/88_smoke_test_comprehensive.R]
tech_stack:
  added: []
  patterns: [openxlsx2 single-sheet workbook, comma-separated cancer code aggregation, 3-tier medication name cascade]
key_files:
  created:
    - R/36_tableau_ready_tables.R
  modified:
    - R/88_smoke_test_comprehensive.R
decisions:
  - "Comma separator for cancer codes (meeting notes line 75, not semicolons like R/57)"
  - "Separate xlsx files per table (not combined workbook) for clearer Tableau import purpose"
  - "One row per encounter+medication in TABLE-2 (no aggregation) for Tableau pivot flexibility"
metrics:
  duration: "5 minutes"
  completed: "2026-06-15"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 1
---

# Phase 106 Plan 01: Tableau-Ready Data Tables Summary

R/36 script producing two Tableau-ready xlsx files: TABLE-1 maps treatment encounters to comma-separated cancer diagnosis codes with category names; TABLE-2 lists chemotherapy drugs by class with 3-tier medication name resolution from reference xlsx, CODE_SUBCATEGORY_MAP, and fallback labels.

## What Was Done

### Task 1: Create R/36_tableau_ready_tables.R (372 lines)
**Commit:** `5131724`

Created `R/36_tableau_ready_tables.R` with 7 sections following the R/57 encounter-level extraction pattern:

1. **Setup**: Libraries (dplyr, tidyr, glue, stringr, openxlsx2, checkmate), sources R/00_config.R and 3 utility modules, defines paths for inputs and outputs, console logging handler
2. **Load Input Data**: Reads `treatment_episode_detail.rds` with assert_rds_exists/assert_df_valid validation
3. **Extract Cancer Codes**: DuckDB DIAGNOSIS query via get_pcornet_table(), is_cancer_code() filter, comma-separated aggregation per encounter (D-02), 4-tier cancer category mapping
4. **TABLE-1**: Distinct rows per encounter with PATID, ENCOUNTERID, treatment_date, treatment_type, cancer_codes, cancer_category_names (D-01, D-03)
5. **TABLE-2**: Chemotherapy-only filter (D-05), reference xlsx medication name loading, 3-tier medication_name resolution via case_when (D-04), one row per encounter+medication combination (D-06)
6. **Write XLSX**: Separate workbooks via wb_workbook() with col_names=TRUE, saved to distinct filenames
7. **Summary**: Row count logging, sanity check (TABLE-2 < TABLE-1)

### Task 2: Add Phase 106 validation to R/88 smoke test
**Commit:** `5743894`

Added SECTION 31H to R/88_smoke_test_comprehensive.R with 17 structural checks:
- 4 source dependency checks (R/00_config.R, utils_duckdb, utils_assertions, utils_cancer)
- 3 data loading checks (treatment_episode_detail.rds, get_pcornet_table DIAGNOSIS, is_cancer_code)
- 2 TABLE-1 checks (comma separator, output filename)
- 3 TABLE-2 checks (Chemotherapy filter, medication_name, reference xlsx, output filename)
- 4 output format checks (wb_workbook, col_names=TRUE, no saveRDS, 7+ SECTION markers)

Updated counter denominators from /39 to /41 across affected sections. Added TABLE-01 and TABLE-02 to requirements summary.

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Comma separator for cancer_codes | Meeting notes line 75 explicitly requests comma-separated; Tableau Split function defaults to comma delimiter |
| Separate xlsx files (not combined workbook) | Clearer purpose per file; Tableau connects to one table per data source |
| One row per encounter+medication in TABLE-2 | Preserves granularity for Amy's Tableau pivot/filter on individual drugs |
| 3-tier medication name cascade | Matches R/57 pattern: xlsx reference > CODE_SUBCATEGORY_MAP > fallback label |

## Deviations from Plan

None -- plan executed exactly as written.

## Commits

| # | Hash | Message | Files |
|---|------|---------|-------|
| 1 | `5131724` | feat(106-01): create R/36 Tableau-ready tables | R/36_tableau_ready_tables.R |
| 2 | `5743894` | feat(106-01): add Phase 106 validation to R/88 | R/88_smoke_test_comprehensive.R |

## Known Stubs

None. Both TABLE-1 and TABLE-2 generation logic is complete with data sources fully wired. The xlsx output files are only produced at runtime (on HiPerGator or with local fixtures + DuckDB).

## Self-Check: PASSED

All files found, all commits verified.
