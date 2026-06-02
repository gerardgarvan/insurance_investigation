---
phase: 72-defensive-coding
plan: 04
subsystem: defensive-coding
tags: [assertions, checkmate, validation, cancer-scripts, payer-scripts]
dependency_graph:
  requires:
    - 72-01 (utils_assertions.R with 5 helper functions)
  provides:
    - Input validation for 24 cancer and payer/QA scripts
    - Fail-fast RDS/CSV existence checks
    - Post-load data frame structure validation
  affects:
    - All cancer scripts (R/40-R/53) now validate inputs
    - All payer/QA scripts (R/60-R/69) now validate inputs
tech_stack:
  added: []
  patterns:
    - assert_rds_exists before all readRDS operations
    - assert_df_valid after critical data frame loads
    - checkmate::assert_file_exists for CSV inputs
    - assert_list for pcornet table list validation
key_files:
  created: []
  modified:
    - R/40_cancer_site_frequency.R: DIAGNOSIS table validation
    - R/41_extract_all_codes.R: DIAGNOSIS table validation
    - R/42_build_code_descriptions.R: 2 RDS existence checks
    - R/43_cancer_site_confirmation.R: DIAGNOSIS table validation
    - R/44_cancer_site_confirmation_7day.R: DIAGNOSIS table validation
    - R/45_cancer_summary.R: DIAGNOSIS table validation
    - R/46_cancer_summary_table.R: DIAGNOSIS + CSV validation
    - R/47_cancer_summary_refined.R: DIAGNOSIS + CSV validation
    - R/48_cancer_summary_post_hl.R: DIAGNOSIS + RDS + CSV validation
    - R/49_cancer_summary_pre_post.R: DIAGNOSIS + RDS + CSV validation
    - R/50_all_codes_resolved.R: Comment documenting optional RDS pattern
    - R/51_gantt_data_export.R: 5 RDS + 1 CSV + structure validation
    - R/52_gantt_v2_export.R: 5 RDS + structure validation
    - R/53_death_date_validation.R: 3 RDS + structure + date range warnings
    - R/60_tiered_same_day_payer.R: ENCOUNTER table validation
    - R/61_tiered_encounter_level.R: ENCOUNTER table validation
    - R/62_tiered_date_level.R: RDS + structure validation
    - R/63_value_audit.R: pcornet list validation
    - R/64_all_source_missingness.R: ENROLLMENT table validation
    - R/65_uf_insurance_missingness.R: ENROLLMENT table validation
    - R/66_all_site_duplicate_dates.R: DEMOGRAPHIC + ENCOUNTER validation
    - R/67_multi_source_overlap_detection.R: ENCOUNTER table validation
    - R/68_overlap_classification.R: 2 CSV file validations
    - R/69_per_patient_source_detection.R: ENCOUNTER table validation
decisions:
  - Used assert_rds_exists for all readRDS operations except optional RDS files
  - Used assert_df_valid for pcornet tables and critical RDS-loaded data frames
  - Used checkmate::assert_file_exists for CSV inputs
  - Added warn_date_range to R/53 for treatment episode dates
  - Preserved existing file.exists checks in conditional RDS loads
metrics:
  duration_minutes: 10
  tasks_completed: 2
  files_created: 0
  files_modified: 24
  commits: 2
  completed_at: "2026-06-02T16:54:39Z"
---

# Phase 72 Plan 04: Add Assertions to Cancer and Payer/QA Scripts

**One-liner:** Added checkmate-based input validation to 24 production scripts (R/40-R/53 cancer, R/60-R/69 payer/QA) with fail-fast RDS/CSV existence checks and post-load structure validation.

## What Was Built

### Task 1: Cancer Scripts (R/40-R/53) - 14 Scripts

Added input validation to all 14 cancer analysis scripts following these patterns:

**Pattern A: PCORnet table-dependent scripts (R/40-49)**
- Validated DIAGNOSIS table exists and contains required columns (ID, DX, DX_TYPE, DX_DATE)
- Added validation immediately after source() calls, before any data processing
- Example: R/40, R/41, R/43, R/44, R/45, R/46, R/47, R/48, R/49

**Pattern B: RDS-dependent scripts (R/42, R/50-53)**
- Added assert_rds_exists before each readRDS operation
- R/42: 2 classified code RDS files (HCPCS, NDC)
- R/51: 5 RDS files (episodes, detail, descriptions, deaths, cohort) + 1 CSV
- R/52: 5 RDS files (episodes, detail, descriptions, deaths, cohort)
- R/53: 3 RDS files (episodes, cohort twice) + date range warnings

**Pattern C: CSV-dependent scripts (R/46-49)**
- Added checkmate::assert_file_exists before read.csv operations
- Informative error messages with fix hints (e.g., "run R/47 first")

**Pattern D: Post-load structure validation (R/51-53)**
- Added assert_df_valid after loading episodes and detail data frames
- Validates required columns exist: patient_id, treatment_type, episode_start, episode_stop
- R/53 also includes warn_date_range for episode_start dates (1990-2030 boundaries)

**Pattern E: Optional RDS files (R/45, R/50)**
- Scripts with conditional `if (file.exists())` checks left as-is (design pattern for optional inputs)
- Added comments documenting the optional-file pattern

### Task 2: Payer/QA Scripts (R/60-R/69) - 10 Scripts

Added input validation to all 10 payer and quality assurance scripts:

**Pattern A: ENCOUNTER-dependent scripts (R/60, R/61, R/66, R/67, R/69)**
- Validated ENCOUNTER table after get_pcornet_table() materialization
- Required columns: ID, ENCOUNTERID, ADMIT_DATE, ENC_TYPE, PAYER_TYPE_PRIMARY, SOURCE
- Example: R/60, R/61, R/67, R/69

**Pattern B: ENROLLMENT-dependent scripts (R/64, R/65)**
- Validated ENROLLMENT table after source() chain
- Required columns: ID, PAYER_TYPE_PRIMARY, SOURCE

**Pattern C: RDS-dependent scripts (R/62)**
- assert_rds_exists for treatment_episodes.rds
- assert_df_valid after loading episodes

**Pattern D: pcornet list validation (R/63)**
- checkmate::assert_list for pcornet table list (min.len = 1)

**Pattern E: CSV-dependent scripts (R/68)**
- 2 CSV file validations for overlap classification input files
- Same-date and same-week detail CSVs from R/67

**Pattern F: Multi-table scripts (R/66)**
- Validated both DEMOGRAPHIC and ENCOUNTER tables
- Sequential validation after each get_pcornet_table() call

## Deviations from Plan

None - plan executed exactly as written.

## Blockers Encountered

None.

## Key Decisions

| Decision | Rationale | Impact |
|----------|-----------|--------|
| Preserve conditional file.exists checks | R/45, R/50, R/51, R/52 have optional RDS inputs by design | Left existing patterns unchanged; assertions only for mandatory inputs |
| Add post-load structure validation to Gantt scripts | R/51, R/52 load 5+ RDS files each - a single malformed file wastes minutes | Early structure validation prevents downstream pipeline failures |
| Add date range warnings to R/53 | Treatment episode dates are critical for death date validation | Catches historical dates or sentinel values early |
| Use checkmate::assert_file_exists directly for CSVs | CSV files don't have a helper wrapper in utils_assertions.R | Consistent with project pattern; glue() messages maintain error format |
| Validate ENCOUNTER table after materialization | DuckDB lazy evaluation means validation must happen post-collect() | Ensures validation runs on actual data, not query plan |

## Testing Evidence

**Assertion counts verified:**
```bash
# Cancer scripts: All 14 have at least 1 assertion
$ grep -c "assert_" R/4[0-9]_*.R R/5[0-3]_*.R
R/40_cancer_site_frequency.R:1
R/41_extract_all_codes.R:1
R/42_build_code_descriptions.R:2
R/43_cancer_site_confirmation.R:1
R/44_cancer_site_confirmation_7day.R:1
R/45_cancer_summary.R:1
R/46_cancer_summary_table.R:2
R/47_cancer_summary_refined.R:2
R/48_cancer_summary_post_hl.R:3
R/49_cancer_summary_pre_post.R:3
R/50_all_codes_resolved.R:1
R/51_gantt_data_export.R:8
R/52_gantt_v2_export.R:7
R/53_death_date_validation.R:5

# Payer/QA scripts: All 10 have at least 1 assertion
$ grep -c "assert_" R/6[0-9]_*.R
R/60_tiered_same_day_payer.R:1
R/61_tiered_encounter_level.R:1
R/62_tiered_date_level.R:2
R/63_value_audit.R:1
R/64_all_source_missingness.R:1
R/65_uf_insurance_missingness.R:1
R/66_all_site_duplicate_dates.R:2
R/67_multi_source_overlap_detection.R:1
R/68_overlap_classification.R:2
R/69_per_patient_source_detection.R:1
```

**Specific assertion type verification:**
```bash
# R/51 has 5 assert_rds_exists (episodes, detail, deaths, cohort, descriptions)
$ grep -c "assert_rds_exists" R/51_gantt_data_export.R
5

# R/52 has 5 assert_rds_exists
$ grep -c "assert_rds_exists" R/52_gantt_v2_export.R
5

# R/53 has 3 assert_rds_exists
$ grep -c "assert_rds_exists" R/53_death_date_validation.R
3

# R/42 has 2 assert_rds_exists
$ grep -c "assert_rds_exists" R/42_build_code_descriptions.R
2

# R/40 has DIAGNOSIS validation
$ grep -c "assert_df_valid" R/40_cancer_site_frequency.R
1

# R/46 has CSV check
$ grep -c "assert_file_exists" R/46_cancer_summary_table.R
1

# R/53 has date range warning
$ grep -c "warn_date_range" R/53_death_date_validation.R
1

# R/63 has list validation
$ grep -c "assert_list" R/63_value_audit.R
1

# R/68 has 2 CSV checks
$ grep -c "assert_file_exists" R/68_overlap_classification.R
2
```

**Line length compliance:**
```bash
# No new lines exceed 150 characters
$ git diff HEAD~2 R/40_cancer_site_frequency.R R/46_cancer_summary_table.R \
    R/60_tiered_same_day_payer.R | grep "^+" | awk 'length > 150'
(no output - all lines compliant)
```

**Commits:**
```bash
$ git log --oneline -2
a8a47bc feat(72-04): add assertions to payer/QA scripts (R/60-R/69)
9d0be65 feat(72-04): add assertions to cancer scripts (R/40-R/53)
```

## Known Stubs

None. This plan adds defensive validation only - no data processing or UI rendering.

## Next Steps

**Within Phase 72:**
- Remaining plans will add assertions to treatment (R/20-R/29) scripts
- Treatment scripts have complex RDS dependencies requiring careful validation placement

**Dependencies satisfied:**
- All cancer and payer/QA scripts now fail fast on missing inputs
- Error messages provide clear fix hints (which script to run first)
- Post-load structure validation catches malformed RDS files early

## Self-Check: PASSED

**Modified files exist:**
```bash
$ ls R/40_cancer_site_frequency.R R/51_gantt_data_export.R \
     R/60_tiered_same_day_payer.R R/68_overlap_classification.R
R/40_cancer_site_frequency.R
R/51_gantt_data_export.R
R/60_tiered_same_day_payer.R
R/68_overlap_classification.R
```

**Commits exist:**
```bash
$ git log --oneline --all | grep -E "9d0be65|a8a47bc"
a8a47bc feat(72-04): add assertions to payer/QA scripts (R/60-R/69)
9d0be65 feat(72-04): add assertions to cancer scripts (R/40-R/53)
```

**Assertion functions used:**
```bash
$ grep "assert_rds_exists\|assert_df_valid\|assert_file_exists\|warn_date_range\|assert_list" \
    R/51_gantt_data_export.R | wc -l
8  # Correct count for R/51 (5 RDS + 2 structure + 1 CSV)
```

All checks passed.
