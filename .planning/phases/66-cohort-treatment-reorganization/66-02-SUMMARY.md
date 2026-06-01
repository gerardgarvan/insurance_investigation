---
phase: 66-cohort-treatment-reorganization
plan: 02
subsystem: pipeline-organization
tags:
  - renumbering
  - cancer-decade
  - payer-decade
  - cross-references
dependency_graph:
  requires:
    - "66-01"
  provides:
    - cancer-decade-40-53
    - payer-decade-60-69
  affects:
    - R/22b_generate_phase19_20_pptx.R
tech_stack:
  added: []
  patterns:
    - decade-based-numbering
    - sequential-script-organization
key_files:
  created: []
  modified:
    - R/40_cancer_site_frequency.R
    - R/41_extract_all_codes.R
    - R/42_build_code_descriptions.R
    - R/43_cancer_site_confirmation.R
    - R/44_cancer_site_confirmation_7day.R
    - R/45_cancer_summary.R
    - R/46_cancer_summary_table.R
    - R/47_cancer_summary_refined.R
    - R/48_cancer_summary_post_hl.R
    - R/49_cancer_summary_pre_post.R
    - R/50_all_codes_resolved.R
    - R/51_gantt_data_export.R
    - R/52_gantt_v2_export.R
    - R/53_death_date_validation.R
    - R/60_tiered_same_day_payer.R
    - R/61_tiered_encounter_level.R
    - R/62_tiered_date_level.R
    - R/63_value_audit.R
    - R/64_all_source_missingness.R
    - R/65_uf_insurance_missingness.R
    - R/66_all_site_duplicate_dates.R
    - R/67_multi_source_overlap_detection.R
    - R/68_overlap_classification.R
    - R/69_per_patient_source_detection.R
    - R/86_smoke_test_foundation.R
    - R/22b_generate_phase19_20_pptx.R
decisions:
  - id: D-07
    what: Eliminate all a/b suffixes from cancer and payer scripts
    why: Clean sequential numbering within decades
    outcome: 48a->41, 48b->42, 45a->61, 46a->62, 22a->67 (no suffixes)
  - id: D-08
    what: Gantt export scripts stay in cancer decade
    why: Gantt data derives from treatment episodes and cancer linkage
    outcome: 49->51, 63->52 (both in 40-53 range)
  - id: SMOKE-MOVE
    what: Move 65_smoke_test_foundation to 86
    why: Freed slot 65 for payer script, aligns smoke test with test decade (80-89)
    outcome: 65->86, zero collision on payer renumber
metrics:
  duration_seconds: 310
  tasks_completed: 2
  files_renamed: 25
  cross_references_updated: 2
  stale_references: 0
---

# Phase 66 Plan 02: Cancer and Payer/QA Decades

**Renumbered 14 cancer analysis scripts to 40-53, 10 payer/QA scripts to 60-69, eliminated a/b suffixes, updated all cross-references.**

## What Was Done

Completed REORG-01 and REORG-02 requirements for cancer (40-53) and payer/QA (60-69) decades.

### Task 1: Cancer Analysis Scripts → 40-53

Renamed 14 cancer analysis scripts from scattered positions (47-59, 63) to sequential 40-53 range:

**Mapping:**
- 47_cancer_site_frequency → 40_cancer_site_frequency
- 48a_extract_all_codes → 41_extract_all_codes (suffix dropped)
- 48b_build_code_descriptions → 42_build_code_descriptions (suffix dropped)
- 50_cancer_site_confirmation → 43_cancer_site_confirmation
- 51_cancer_site_confirmation_7day → 44_cancer_site_confirmation_7day
- 53_cancer_summary → 45_cancer_summary
- 54_cancer_summary_table → 46_cancer_summary_table
- 55_cancer_summary_refined → 47_cancer_summary_refined
- 56_cancer_summary_post_hl → 48_cancer_summary_post_hl
- 58_cancer_summary_pre_post → 49_cancer_summary_pre_post
- 52_all_codes_resolved → 50_all_codes_resolved
- 49_gantt_data_export → 51_gantt_data_export (per D-08)
- 63_gantt_v2_export → 52_gantt_v2_export (per D-08)
- 59_death_date_validation → 53_death_date_validation

**Header updates:** All 14 scripts updated with new phase numbers and usage comments.

**Collision avoidance:** Renamed high-numbered scripts first (55-59, 63) to vacate slots before renaming lower-numbered scripts (47-54) that needed those vacated slots.

**Gantt decision (D-08):** Gantt export scripts stayed in cancer decade because they produce treatment episode visualizations with cancer category linkage — logically part of cancer analysis, not standalone outputs.

### Task 2: Payer/QA Scripts → 60-69

Renamed 10 payer/QA scripts from scattered positions (17-24, 36, 45a, 46a) to sequential 60-69 range:

**Pre-rename:** Moved 65_smoke_test_foundation → 86_smoke_test_foundation to free slot 65 for payer script.

**Mapping:**
- 36_tiered_same_day_payer → 60_tiered_same_day_payer
- 45a_tiered_encounter_level → 61_tiered_encounter_level (suffix dropped)
- 46a_tiered_date_level → 62_tiered_date_level (suffix dropped)
- 17_value_audit → 63_value_audit
- 20_all_source_missingness → 64_all_source_missingness
- 18_uf_insurance_missingness → 65_uf_insurance_missingness
- 21_all_site_duplicate_dates → 66_all_site_duplicate_dates
- 22a_multi_source_overlap_detection → 67_multi_source_overlap_detection (suffix dropped)
- 23_overlap_classification → 68_overlap_classification
- 24_per_patient_source_detection → 69_per_patient_source_detection

**Header updates:** All 10 scripts updated with new phase numbers and usage comments.

**Cross-reference updates:**
- R/22b_generate_phase19_20_pptx.R line 157: `source("R/18_uf_insurance_missingness.R")` → `source("R/65_uf_insurance_missingness.R")`
- R/22b line 163 error hint: same update

**a/b suffix elimination (D-07):** All cancer and payer scripts now have clean sequential numbering. Remaining a/b files (22b, 43b-46b) are test/ad-hoc/outputs scripts that move to their final decades in Plan 03.

## Deviations from Plan

None — plan executed exactly as written.

## Verification

**File counts:**
- Cancer decade (40-53): 14 files ✓
- Payer/QA decade (60-69): 10 files ✓

**Old files removed:**
- R/47_cancer_site_frequency.R (now 40) ✓
- R/49_gantt_data_export.R (now 51) ✓
- R/63_gantt_v2_export.R (now 52) ✓
- R/36_tiered_same_day_payer.R (now 60) ✓
- R/17_value_audit.R (now 63) ✓
- R/45a_tiered_encounter_level.R (now 61) ✓
- R/65_smoke_test_foundation.R (now 86) ✓

**Stale references:** 0 (grep verified)

**Remaining a/b suffixes:** Only 22b, 43b, 44b, 45b, 46b (expected, move in Plan 03)

## Known Stubs

None — this plan only renames files and updates headers/cross-references, no code logic changes.

## Output Artifacts

No new output artifacts — renaming operation only.

## Dependencies for Next Plan

Plan 66-03 can proceed. All cancer and payer scripts now at final positions with clean sequential numbering.

## Self-Check

**Files exist:**
```bash
FOUND: R/40_cancer_site_frequency.R
FOUND: R/45_cancer_summary.R
FOUND: R/51_gantt_data_export.R
FOUND: R/52_gantt_v2_export.R
FOUND: R/53_death_date_validation.R
FOUND: R/60_tiered_same_day_payer.R
FOUND: R/61_tiered_encounter_level.R
FOUND: R/65_uf_insurance_missingness.R
FOUND: R/69_per_patient_source_detection.R
FOUND: R/86_smoke_test_foundation.R
```

**Commits exist:**
```bash
FOUND: db8da00 (Task 1: cancer scripts 40-53)
FOUND: 7bbac60 (Task 2: payer scripts 60-69)
```

## Self-Check: PASSED

All files created, all commits exist, zero stale references verified.
