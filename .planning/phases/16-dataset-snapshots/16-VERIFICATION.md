---
phase: 16-dataset-snapshots
verified: 2026-04-03T18:15:00Z
status: passed
score: 5/5 must-haves verified
re_verification: false
---

# Phase 16: Dataset Snapshots Verification Report

**Phase Goal:** User can save cohort snapshots at every filter step, final outputs, and figure/table backing datasets as RDS files for reproducibility and debugging

**Verified:** 2026-04-03T18:15:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth                                                                                      | Status     | Evidence                                                                                                  |
| --- | ------------------------------------------------------------------------------------------ | ---------- | --------------------------------------------------------------------------------------------------------- |
| 1   | User can call save_output_data(df, name) from any script to save an RDS snapshot          | ✓ VERIFIED | R/utils_snapshot.R exists with function signature, sourced in 00_config.R line 863                        |
| 2   | User can see RDS snapshot after each filter step that changes patient count in cohort/    | ✓ VERIFIED | R/04_build_cohort.R lines 59, 116, 124 save cohort_00, cohort_01, cohort_02.rds                          |
| 3   | User can see cohort_final.rds and attrition_log.rds in cohort/                            | ✓ VERIFIED | R/04_build_cohort.R lines 420, 503 save cohort_final.rds, attrition_log.rds                              |
| 4   | User can see figure-backing data frames saved as RDS before each plot is rendered         | ✓ VERIFIED | 10 save_output_data calls in R/05, R/06, R/16 scripts before ggplot() calls                              |
| 5   | User can see table-backing data frames saved as RDS before each PPTX table is built       | ✓ VERIFIED | 6 save_output_data calls in R/11_generate_pptx.R before add_table_slide() calls                          |

**Score:** 5/5 truths verified (100%)

### Required Artifacts

| Artifact                              | Expected                                                                         | Status     | Details                                                                                             |
| ------------------------------------- | -------------------------------------------------------------------------------- | ---------- | --------------------------------------------------------------------------------------------------- |
| R/utils_snapshot.R                    | save_output_data() helper function                                              | ✓ VERIFIED | 56 lines, contains function def, validation, saveRDS with compress=TRUE, logging                    |
| R/00_config.R cache section           | CONFIG$cache with cache_dir, raw_dir, cohort_dir, outputs_dir entries           | ✓ VERIFIED | Lines 51-66 contain all 4 paths, GITIGNORED comment present                                         |
| R/00_config.R sourcing                | source("R/utils_snapshot.R")                                                     | ✓ VERIFIED | Line 863 sources utils_snapshot.R with Phase 16 comment                                             |
| R/01_load_pcornet.R cache reference   | Uses CONFIG$cache$raw_dir (not cache_dir)                                       | ✓ VERIFIED | Line 561: cache_dir <- CONFIG$cache$raw_dir                                                         |
| R/04_build_cohort.R snapshots         | 5 inline saveRDS() calls (3 filter steps + final + attrition)                   | ✓ VERIFIED | Lines 59, 116, 124, 420, 503 all use file.path(CONFIG$cache$cohort_dir, ...) with compress=TRUE    |
| R/05_visualize_waterfall.R snapshot   | save_output_data() call for waterfall backing data                              | ✓ VERIFIED | Line 39: save_output_data(attrition_plot_data, "waterfall_attrition_data"), before ggplot line 48  |
| R/06_visualize_sankey.R snapshot      | save_output_data() call for sankey backing data                                 | ✓ VERIFIED | Line 151: save_output_data(sankey_data, "sankey_patient_flow_data"), before ggplot line 159        |
| R/16_encounter_analysis.R snapshots   | 8 save_output_data() calls for figure/table backing data                        | ✓ VERIFIED | Lines 61, 113, 140, 204, 223, 314, 356, 378 — all placed before ggplot()/write_csv() calls         |
| R/11_generate_pptx.R snapshots        | 6 save_output_data() calls for unique summary tables                            | ✓ VERIFIED | Lines 410, 1019, 1072, 1162, 1236, 1371 — all placed before add_table_slide() calls                |

**All 9 artifact groups verified** — existence confirmed, substantive content validated, wiring to rendering calls verified.

### Key Link Verification

| From                           | To                             | Via                                                   | Status   | Details                                                                           |
| ------------------------------ | ------------------------------ | ----------------------------------------------------- | -------- | --------------------------------------------------------------------------------- |
| R/utils_snapshot.R             | R/00_config.R                  | CONFIG$cache$cache_dir reference in save_output_data  | ✓ WIRED  | Lines 29, 30, 37 in utils_snapshot.R reference CONFIG$cache$cache_dir            |
| R/00_config.R                  | R/utils_snapshot.R             | source() at end of config                             | ✓ WIRED  | Line 863 sources utils_snapshot.R                                                |
| R/04_build_cohort.R            | CONFIG$cache$cohort_dir        | file.path() for snapshot paths                       | ✓ WIRED  | All 5 saveRDS calls use CONFIG$cache$cohort_dir                                  |
| R/05_visualize_waterfall.R     | R/utils_snapshot.R             | save_output_data() function call                     | ✓ WIRED  | Line 39 calls save_output_data                                                   |
| R/06_visualize_sankey.R        | R/utils_snapshot.R             | save_output_data() function call                     | ✓ WIRED  | Line 151 calls save_output_data                                                  |
| R/16_encounter_analysis.R      | outputs subdirectory           | save_output_data() writes to outputs/                | ✓ WIRED  | 8 calls to save_output_data with default subdir="outputs"                        |
| R/11_generate_pptx.R           | outputs subdirectory           | save_output_data() writes to outputs/                | ✓ WIRED  | 6 calls to save_output_data with default subdir="outputs"                        |

**All 7 key links verified** — function calls present, CONFIG references confirmed, paths wired correctly.

### Requirements Coverage

| Requirement | Source Plan | Description                                                             | Status       | Evidence                                                                       |
| ----------- | ----------- | ----------------------------------------------------------------------- | ------------ | ------------------------------------------------------------------------------ |
| SNAP-01     | 16-01       | Save resulting data frame after each named filter step                 | ✓ SATISFIED  | 3 cohort snapshots in 04_build_cohort.R (steps 0, 1, 2)                       |
| SNAP-02     | 16-01       | Save final cohort as cohort_final.rds and attrition_log.rds            | ✓ SATISFIED  | Lines 420, 503 in 04_build_cohort.R                                           |
| SNAP-03     | 16-02       | Every figure gets its ggplot-ready data frame saved                    | ✓ SATISFIED  | 10 figure snapshots across R/05, R/06, R/16 before plot rendering             |
| SNAP-04     | 16-02       | Every summary table gets its source data frame saved                   | ✓ SATISFIED  | 6 table snapshots in R/11_generate_pptx.R + 1 in R/16 before table building   |
| SNAP-05     | 16-01       | Shared save_output_data(df, name) helper function                      | ✓ SATISFIED  | R/utils_snapshot.R with validation, path construction, logging                |

**All 5 requirements satisfied** — no orphaned requirements in REQUIREMENTS.md for Phase 16.

### Anti-Patterns Found

| File                        | Line | Pattern | Severity | Impact                                                    |
| --------------------------- | ---- | ------- | -------- | --------------------------------------------------------- |
| R/utils_snapshot.R          | 54   | invisible(NULL) return | ℹ️ Info   | Intentional design — side-effect function, not a stub    |

**No blocker or warning anti-patterns detected.** The `invisible(NULL)` return is standard R practice for side-effect functions like saveRDS wrappers.

### Human Verification Required

None. All verification can be performed programmatically by checking file existence, grep patterns, and commit hashes. The snapshot functionality itself (whether RDS files are actually written when scripts run) would require executing R code, which is out of scope for static verification.

The phase deliverables are infrastructure (helper function + inline saveRDS calls). Actual RDS file generation happens at runtime on HiPerGator, not during verification.

---

## Verification Summary

**Status: PASSED** — All must-haves verified, all requirements satisfied, no blocking issues found.

### What Was Verified

1. **save_output_data() helper function exists and is wired**
   - Function signature matches plan spec: `save_output_data <- function(df, name, subdir = "outputs")`
   - Validates inputs: data.frame check, CONFIG$cache$cache_dir existence, subdir whitelist
   - Creates directories idempotently with dir.create()
   - Saves with compression: `saveRDS(df, snapshot_path, compress = TRUE)`
   - Logs to console with glue: `Snapshot: {name}.rds ({nrow} rows, {ncol} cols)`
   - Sourced in 00_config.R line 863

2. **CONFIG cache structure extended**
   - Base cache_dir: `/blue/erin.mobley-hl.bcu/clean/rds` (changed from .../rds/raw)
   - raw_dir: `/blue/erin.mobley-hl.bcu/clean/rds/raw` (Phase 15 table cache)
   - cohort_dir: `/blue/erin.mobley-hl.bcu/clean/rds/cohort` (Phase 16 filter snapshots)
   - outputs_dir: `/blue/erin.mobley-hl.bcu/clean/rds/outputs` (Phase 16 viz backing data)
   - GITIGNORED comments present
   - Phase 15 cache logic updated: 01_load_pcornet.R uses raw_dir instead of cache_dir

3. **Cohort filter step snapshots in 04_build_cohort.R**
   - cohort_00_initial_population.rds (line 59, after step 0 attrition log)
   - cohort_01_hl_flag.rds (line 116, after step 1 attrition log)
   - cohort_02_has_enrollment.rds (line 124, after step 2 attrition log)
   - cohort_final.rds (line 420, after final cohort assembly)
   - attrition_log.rds (line 503, after attrition log print)
   - dir.create() guard at step 0 only (idempotent)
   - No snapshots in enrichment stages (Sections 3-6.8) per design decision D-02

4. **Figure backing data snapshots (10 total)**
   - R/05_visualize_waterfall.R: waterfall_attrition_data (1 snapshot, line 39)
   - R/06_visualize_sankey.R: sankey_patient_flow_data (1 snapshot, line 151)
   - R/16_encounter_analysis.R: 8 snapshots (lines 61, 113, 140, 204, 223, 314, 356, 378)
     - encounters_per_person_by_payor_data
     - post_tx_encounters_by_dx_year_data
     - total_encounters_by_dx_year_data (same enc_by_year data frame, different name per D-10)
     - encounter_summary_by_payor_age_data (CSV table backing)
     - post_tx_by_age_group_data
     - unique_dates_per_person_by_payor_data
     - post_tx_unique_dates_by_dx_year_data
     - total_unique_dates_by_dx_year_data (same enc_ud_by_year data frame, different name per D-10)

5. **Table backing data snapshots (6 total in R/11_generate_pptx.R)**
   - pptx_cohort_full_data (line 410, master source for pivoted tables tbl2-tbl13)
   - last_tx_equals_last_encounter_data (line 1019, tbl14)
   - missing_post_tx_payer_breakdown_data (line 1072, tbl15)
   - insurance_after_last_tx_retention_data (line 1162, tbl16)
   - encounter_summary_stats_by_payer_data (line 1236, summary stats table)
   - unique_dates_summary_stats_by_payer_data (line 1371, unique dates stats table)

6. **All snapshots placed correctly**
   - Before ggplot() calls for figures
   - Before add_table_slide() calls for PPTX tables
   - Before write_csv() for CSV tables
   - After data transformation completes
   - Naming follows _data suffix convention (D-10 traceability)

7. **Commits verified**
   - d4fc273: feat(16-01): create snapshot utility and extend CONFIG cache
   - b550ba9: feat(16-01): add cohort filter step snapshots to build pipeline
   - 4babd66: feat(16-dataset-snapshots): add backing data snapshots to waterfall and sankey scripts
   - 4220b35: feat(16-dataset-snapshots): add backing data snapshots to encounter analysis and PPTX scripts

### Goal Achievement Confirmed

The phase goal is **ACHIEVED**:

✓ User can save cohort snapshots at every filter step (3 snapshots in 04_build_cohort.R)
✓ User can save final outputs (cohort_final.rds + attrition_log.rds)
✓ User can save figure/table backing datasets as RDS files (16 snapshots across 4 viz scripts)
✓ All snapshots use consistent path construction via CONFIG$cache subdirectories
✓ save_output_data() helper provides reusable infrastructure for future scripts

All truths are verifiable in the codebase, all artifacts exist with substantive implementation, all key links are wired, and all 5 requirements are satisfied with concrete evidence.

**Ready to proceed to Phase 17.**

---

_Verified: 2026-04-03T18:15:00Z_
_Verifier: Claude (gsd-verifier)_
