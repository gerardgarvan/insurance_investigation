---
phase: 65-foundation-reorganization
plan: 01
subsystem: foundation
tags: [refactor, organization, utils, renumbering]
dependency_graph:
  requires: []
  provides:
    - R/utils/ subfolder structure
    - Dynamic utils auto-sourcing
    - Foundation script 03_duckdb_ingest
  affects:
    - All scripts that source utils files (16 scripts)
    - R/00_config.R auto-sourcing logic
tech_stack:
  added: []
  patterns:
    - Dynamic file discovery via list.files()
    - Git mv for preserving file history
key_files:
  created:
    - R/utils/ (directory)
  modified:
    - R/00_config.R
    - R/03_duckdb_ingest.R (renamed from 25)
    - R/11_generate_pptx.R
    - R/19_flm_duplicate_dates.R
    - R/21_all_site_duplicate_dates.R
    - R/22a_multi_source_overlap_detection.R
    - R/22b_generate_phase19_20_pptx.R
    - R/24_per_patient_source_detection.R
    - R/27_parity_test_cohort.R
    - R/28_benchmark_cohort.R
    - R/33_multi_source_overlap_av_th.R
    - R/49_gantt_data_export.R
    - R/59_death_date_validation.R
    - R/60_drug_name_resolution.R
    - R/61_episode_classification.R
    - R/62_first_line_and_death_analysis.R
    - R/63_gantt_v2_export.R
  moved:
    - R/utils_attrition.R → R/utils/utils_attrition.R
    - R/utils_dates.R → R/utils/utils_dates.R
    - R/utils_duckdb.R → R/utils/utils_duckdb.R
    - R/utils_icd.R → R/utils/utils_icd.R
    - R/utils_payer.R → R/utils/utils_payer.R
    - R/utils_pptx.R → R/utils/utils_pptx.R
    - R/utils_snapshot.R → R/utils/utils_snapshot.R
    - R/utils_treatment.R → R/utils/utils_treatment.R
    - R/25_duckdb_ingest.R → R/03_duckdb_ingest.R
decisions: []
metrics:
  duration_minutes: 5
  tasks_completed: 2
  files_modified: 17
  files_moved: 9
  source_calls_updated: 19
  completed_date: "2026-06-01"
---

# Phase 65 Plan 01: Foundation Reorganization Summary

**One-liner:** Created R/utils/ subfolder with 8 utility modules, implemented dynamic auto-sourcing via list.files(), renumbered 25_duckdb_ingest.R to 03, and updated all 19 source() cross-references across 16 scripts.

## What Was Done

### Task 1: Create R/utils/ and Move 8 Utils Files

Created `R/utils/` subfolder and moved all 8 utility modules using `git mv` to preserve file history:
- utils_attrition.R (attrition logging)
- utils_dates.R (date parsing)
- utils_duckdb.R (DuckDB backend abstraction)
- utils_icd.R (ICD code normalization)
- utils_payer.R (payer helpers)
- utils_pptx.R (PPTX generation)
- utils_snapshot.R (snapshot helper)
- utils_treatment.R (treatment helpers)

Replaced explicit source() calls in `R/00_config.R` with dynamic auto-sourcing:

```r
utils_files <- list.files(
  path = "R/utils",
  pattern = "\\.R$",
  full.names = TRUE
)

if (length(utils_files) == 0) {
  warning("No utility files found in R/utils/ -- expected at least 8 modules")
} else {
  invisible(lapply(utils_files, source))
  message(sprintf("Loaded %d utility modules from R/utils/", length(utils_files)))
}
```

**Critical parameter:** `full.names = TRUE` ensures `list.files()` returns full paths for `source()` to resolve correctly.

**Benefit:** New utils files added in future phases are auto-discovered without manual edits to `00_config.R`.

### Task 2: Update Source() References and Renumber 25 to 03

Updated 19 direct source() calls across 16 scripts to point to `R/utils/` paths:

**utils_pptx.R callers (2):**
- R/11_generate_pptx.R
- R/22b_generate_phase19_20_pptx.R

**utils_dates.R callers (10):**
- R/19_flm_duplicate_dates.R (conditional source with file.exists check)
- R/21_all_site_duplicate_dates.R (conditional source with file.exists check)
- R/22a_multi_source_overlap_detection.R (conditional source + comment update)
- R/24_per_patient_source_detection.R (conditional source + comment update)
- R/33_multi_source_overlap_av_th.R (conditional source + comment update)
- R/49_gantt_data_export.R
- R/59_death_date_validation.R
- R/61_episode_classification.R
- R/62_first_line_and_death_analysis.R
- R/63_gantt_v2_export.R

**utils_duckdb.R callers (7):**
- R/03_duckdb_ingest.R (formerly R/25_duckdb_ingest.R)
- R/27_parity_test_cohort.R
- R/28_benchmark_cohort.R
- R/49_gantt_data_export.R
- R/59_death_date_validation.R
- R/60_drug_name_resolution.R
- R/61_episode_classification.R
- R/62_first_line_and_death_analysis.R
- R/63_gantt_v2_export.R

**Renumbered 25_duckdb_ingest.R to 03_duckdb_ingest.R:**
- Moved file using `git mv` to preserve history
- Updated header comment (line 2): `# 03_duckdb_ingest.R`
- Updated self-reference comment (line 10): `source("R/03_duckdb_ingest.R")`

**Foundation scripts now numbered 00-03:**
- R/00_config.R (configuration + dynamic utils loading)
- R/01_load_pcornet.R (PCORnet table loading)
- R/02_harmonize_payer.R (payer harmonization)
- R/03_duckdb_ingest.R (DuckDB ingest)

## Deviations from Plan

None — plan executed exactly as written.

## Key Decisions

No new decisions required. Implementation followed design decisions from 65-RESEARCH.md (D-02: keep utils_ prefix, D-03: renumber 25→03, D-04: dynamic auto-sourcing).

## Verification Results

All verification checks passed:

1. ✅ 8 utils files exist in R/utils/
2. ✅ 0 utils files remain in R/ root
3. ✅ 0 old-style source() paths (`source("R/utils_`)`) remain
4. ✅ 1 list.files() call in R/00_config.R (dynamic sourcing active)
5. ✅ R/03_duckdb_ingest.R exists
6. ✅ R/25_duckdb_ingest.R removed
7. ✅ All 4 foundation scripts exist (00, 01, 02, 03)
8. ✅ 19 updated source() calls verified across 16 scripts

## Testing Notes

No runtime testing performed (file organization refactor only). Scripts will be tested during Phase 70 smoke testing (SAFE-03).

## Impact Assessment

**Files changed:** 17 scripts + 9 file moves = 26 total changes
**Scope:** Foundation scripts and utilities (no analysis logic modified)
**Risk:** Low — all changes are path updates with git history preserved

**Backward compatibility:** None required (internal refactor only, no API changes)

## Known Issues

None.

## Known Stubs

None — this is a pure refactoring plan with no new functionality.

## Next Steps

Continue to Phase 65 Plan 02:
- Renumber cohort-building scripts to decade 10-19
- Update cross-references to moved scripts
- Document the 10-19 decade purpose (cohort construction)

## Self-Check

**Verify created files exist:**
```bash
$ ls R/utils/utils_*.R
R/utils/utils_attrition.R
R/utils/utils_dates.R
R/utils/utils_duckdb.R
R/utils/utils_icd.R
R/utils/utils_payer.R
R/utils/utils_pptx.R
R/utils/utils_snapshot.R
R/utils/utils_treatment.R
```

**Verify commits exist:**
```bash
$ git log --oneline -2
8f60b4d refactor(65-01): update all source() references to R/utils/ and renumber 25 to 03
0a312b3 refactor(65-01): create R/utils/ and move 8 utils modules with dynamic auto-sourcing
```

**Verify 03 exists and 25 removed:**
```bash
$ test -f R/03_duckdb_ingest.R && echo "PASS" || echo "FAIL"
PASS
$ test ! -f R/25_duckdb_ingest.R && echo "PASS" || echo "FAIL"
PASS
```

**Verify no old-style paths remain:**
```bash
$ grep -rn 'source("R/utils_' R/*.R | wc -l
0
```

## Self-Check: PASSED

All created files exist, commits are recorded, and verification checks confirm the reorganization is complete.
