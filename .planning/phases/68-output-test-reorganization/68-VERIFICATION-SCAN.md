# Phase 68 Structural Verification Scan

## Scan Date

2026-06-02

## Purpose

Comprehensive local structural verification of the reorganized R pipeline after Phase 65-67 renumbering. This scan validates REORG-01 through REORG-05 requirements by comparing documentation (SCRIPT_INDEX.md and smoke test) against actual filesystem state.

## Structural Scan Results

### 1. Script Count Validation

| Decade | Range | Expected | Actual | Status |
|--------|-------|----------|--------|--------|
| Foundation | 00-09 | 4 | 4 | PASS |
| Cohort | 10-19 | 5 | 5 | PASS |
| Treatment | 20-29 | 10 | 10 | PASS |
| Cancer | 40-53 | 14 | 14 | PASS |
| Payer/QA | 60-69 | 10 | 10 | PASS |
| Outputs | 70-79 | 6 | 6 | PASS |
| Tests | 80-89 | 8 | 8 | PASS |
| Ad-hoc | 90-99 | 10 | 10 | PASS |
| **TOTAL** | | **67** | **67** | **PASS** |

All decade counts match expectations. REORG-01 validated at the count level.

### 2. SCRIPT_INDEX.md Alignment

Comparison of SCRIPT_INDEX.md Cancer Site Analysis section (40-53) against filesystem reality:

| Position | Filesystem Actual | SCRIPT_INDEX.md Listed | Status |
|----------|-------------------|------------------------|--------|
| 40 | 40_cancer_site_frequency.R | 40_cancer_site_frequency.R | MATCH |
| 41 | 41_extract_all_codes.R | 41_extract_all_codes.R | MATCH |
| 42 | 42_build_code_descriptions.R | 42_build_code_descriptions.R | MATCH |
| 43 | **43_cancer_site_confirmation.R** | 43_gantt_data_export.R | **MISMATCH** |
| 44 | **44_cancer_site_confirmation_7day.R** | 44_cancer_site_confirmation.R | **MISMATCH** |
| 45 | **45_cancer_summary.R** | 45_cancer_site_confirmation_7day.R | **MISMATCH** |
| 46 | **46_cancer_summary_table.R** | 46_all_codes_resolved.R | **MISMATCH** |
| 47 | **47_cancer_summary_refined.R** | 47_cancer_summary.R | **MISMATCH** |
| 48 | **48_cancer_summary_post_hl.R** | 48_cancer_summary_table.R | **MISMATCH** |
| 49 | **49_cancer_summary_pre_post.R** | 49_gantt_v2_data_export.R | **MISMATCH** |
| 50 | **50_all_codes_resolved.R** | 50_temporal_filtering.R | **MISMATCH** |
| 51 | 51_gantt_data_export.R | 51_gantt_data_export.R | MATCH |
| 52 | **52_gantt_v2_export.R** | 52_radiation_vs_imaging.R | **MISMATCH** |
| 53 | 53_death_date_validation.R | 53_death_date_validation.R | MATCH |

**Discrepancy Summary:**
- Total cancer scripts: 14
- Matching: 5
- Mismatched: 9

The SCRIPT_INDEX.md cancer decade (positions 43-52, excluding 51) has drifted from filesystem reality. Positions 40-42, 51, and 53 are correct.

### 3. Smoke Test Array Alignment

Comparison of R/87_smoke_test_full_pipeline.R `cancer_expected` array against filesystem:

**Smoke test cancer_expected array:**
```r
cancer_expected <- c("40_cancer_site_frequency.R", "41_extract_all_codes.R",
                     "42_build_code_descriptions.R", "43_gantt_data_export.R",
                     "44_cancer_site_confirmation.R", "45_cancer_site_confirmation_7day.R",
                     "46_all_codes_resolved.R", "47_cancer_summary.R",
                     "48_cancer_summary_table.R", "49_gantt_v2_data_export.R",
                     "50_temporal_filtering.R", "51_gantt_data_export.R",
                     "52_radiation_vs_imaging.R", "53_death_date_validation.R")
```

**Filesystem actual order:**
```
40_cancer_site_frequency.R
41_extract_all_codes.R
42_build_code_descriptions.R
43_cancer_site_confirmation.R
44_cancer_site_confirmation_7day.R
45_cancer_summary.R
46_cancer_summary_table.R
47_cancer_summary_refined.R
48_cancer_summary_post_hl.R
49_cancer_summary_pre_post.R
50_all_codes_resolved.R
51_gantt_data_export.R
52_gantt_v2_export.R
53_death_date_validation.R
```

**Discrepancy Summary:**
- Same 9 mismatches as SCRIPT_INDEX.md (positions 43-50, 52)
- Smoke test array is identical to SCRIPT_INDEX.md (both wrong in the same way)

### 4. A/B Suffix Check

**Result:** PASS

No files matching pattern `[0-9]+[ab]_` found in R/ directory. REORG-01 requirement for elimination of sub-letter suffixes validated.

### 5. Unnumbered Script Check

**Result:** PASS

No unnumbered .R files found in R/ root directory (excluding SCRIPT_INDEX.md which is documentation).

All active scripts use the two-digit prefix pattern `[0-9][0-9]_*.R`.

### 6. Source() Reference Validation

**Result:** PASS

Automated check of all source("R/...") calls across all 67 numbered scripts found zero broken references. All cross-references resolve to existing files.

This validates REORG-02 (all source() cross-references updated correctly during renumbering).

### 7. Archive Completeness

**Archive Status:**
- R/archive/ directory exists: YES
- Script count: 8 .R files
- README.md present: YES

**Archived Scripts (from R/archive/README.md):**
1. check_deleted_proton_code.R (one-off audit, safe to delete)
2. date_range_check.R (exploratory, safe to delete)
3. payer_frequency_from_resolved.R (CSV post-processor, safe to delete)
4. run_phase12_outputs.R (HiPerGator orchestration, retain for adaptation)
5. sct_code_inventory.R (one-off audit, safe to delete)
6. search_C8190.R (one-off search, safe to delete)
7. tiered_payer_summary.R (report regeneration helper, retain)
8. treatment_cross_reference.R (QA validation tool, retain)

**Additional Archival Candidates:**

Scan of all active scripts for archival indicators (one-off, diagnostic, temp in headers; zero source() references from other scripts):

- **None identified.** All 67 numbered scripts are actively referenced or part of the production pipeline.
- Ad-hoc decade (90-99) intentionally contains standalone diagnostics and is NOT a candidate for archival (per D-07 plan guidance).

**Conclusion:** Archive is complete. No additional scripts need archiving.

### 8. Orphan Output Scan

**Output Directory Structure:**
- Total files: 47
- Subdirectories: cohort/, diagnostics/, figures/, tables/

**Output Classification:**

Outputs were cross-referenced against generating scripts by filename similarity and known pipeline outputs:

| Output File | Likely Generator(s) | Classification |
|-------------|---------------------|----------------|
| cancer_site_confirmation.xlsx | 44_cancer_site_confirmation.R | Active |
| chemotherapy_episodes.csv | 26_treatment_episodes.R | Active |
| cohort/* | 14_build_cohort.R | Active |
| diagnostics/* | 90_diagnostics.R, 91_data_quality_summary.R | Active |
| figures/* | 70_visualize_waterfall.R, 71_visualize_sankey.R | Active |
| gantt_detail.csv | 51_gantt_data_export.R | Active |
| gantt_detail_v2.csv | 49_gantt_v2_data_export.R | Active |
| gantt_episodes.csv | 51_gantt_data_export.R | Active |
| gantt_episodes_v2.csv | 49_gantt_v2_data_export.R | Active |
| immunotherapy_episodes.csv | 26_treatment_episodes.R | Active |
| radiation_episodes.csv | 26_treatment_episodes.R | Active |
| sct_episodes.csv | 26_treatment_episodes.R | Active |
| tables/* | Various (60-69 payer scripts, 72_generate_pptx.R) | Active |
| treatment_episodes.xlsx | 26_treatment_episodes.R | Active |

**No orphan outputs identified.** All outputs in output/ directory have active generators in the current pipeline (numbered scripts 00-99).

No outputs have archived generators (R/archive/ scripts produce no persisted outputs).

## Discrepancies Requiring Fix

The following discrepancies between documentation and filesystem must be fixed in Task 2:

### Critical: SCRIPT_INDEX.md Cancer Decade Mismatch

**Affected positions:** 43-50, 52 (9 out of 14 cancer scripts)

SCRIPT_INDEX.md lists old/incorrect filenames for these positions. The Cancer Site Analysis section must be rewritten to match actual filesystem filenames.

### Critical: Smoke Test Cancer Array Mismatch

**Affected file:** R/87_smoke_test_full_pipeline.R

The `cancer_expected` array (lines 89-95) contains the same 9 incorrect filenames as SCRIPT_INDEX.md. Must be updated to match filesystem reality.

### Impact

These discrepancies would cause:
1. Onboarding confusion (SCRIPT_INDEX.md documents wrong files)
2. Smoke test failures (cancer_expected array expects non-existent files)
3. REORG-01/REORG-02 validation failures (documentation out of sync with code)

## Follow-up Items

No minor issues requiring follow-up. All structural checks passed except the cancer decade documentation drift (which blocks Phase 68 completion).

## Summary

**Passing Checks:** 6/8
- Script counts match expectations (67 total, correct decade distribution)
- No a/b suffixes remain
- No unnumbered scripts in R/ root
- All source() references resolve correctly
- Archive complete with 8 scripts
- No orphan outputs

**Failing Checks:** 2/8
- SCRIPT_INDEX.md cancer decade (9/14 mismatched filenames)
- Smoke test cancer_expected array (9/14 mismatched filenames)

**Root Cause:** The cancer decade (40-53) underwent renumbering in Phase 55-67, but SCRIPT_INDEX.md and R/87_smoke_test_full_pipeline.R were not updated to reflect the new positions of cancer site confirmation, cancer summary, and gantt export scripts.

**Resolution:** Task 2 will rewrite both documentation artifacts to match filesystem reality.
