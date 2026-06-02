---
phase: 73-dry-consolidation
plan: 02
subsystem: codebase-quality
tags: [DRY, refactoring, consolidation]
dependency_graph:
  requires: [73-01]
  provides: [cancer-classification-centralized]
  affects: [cancer-scripts, treatment-scripts, gantt-export]
tech_stack:
  added: []
  patterns: [centralized-constants, utility-functions]
key_files:
  created: []
  modified:
    - R/28_episode_classification.R
    - R/40_cancer_site_frequency.R
    - R/43_cancer_site_confirmation.R
    - R/44_cancer_site_confirmation_7day.R
    - R/45_cancer_summary.R
    - R/46_cancer_summary_table.R
    - R/47_cancer_summary_refined.R
    - R/48_cancer_summary_post_hl.R
    - R/49_cancer_summary_pre_post.R
    - R/51_gantt_data_export.R
decisions:
  - id: D-01
    summary: Remove all local PREFIX_MAP definitions, use centralized CANCER_SITE_MAP
    rationale: Single source of truth for cancer site classification
  - id: D-02
    summary: Remove all local classify_codes() definitions, use utils_cancer.R version
    rationale: Single implementation eliminates synchronization burden
  - id: D-03
    summary: Update message() calls to reference CANCER_SITE_MAP instead of PREFIX_MAP
    rationale: Match new constant name for consistency
metrics:
  duration_seconds: 529
  completed_at: "2026-06-02T17:55:43Z"
  tasks_completed: 2
  files_modified: 10
  lines_removed: 2930
  commits: 1
---

# Phase 73 Plan 02: Remove duplicated PREFIX_MAP and classify_codes Summary

**One-liner:** Eliminated ~2,930 lines of duplicated cancer classification code from 10 scripts using centralized CANCER_SITE_MAP + classify_codes()

## Objective

Remove PREFIX_MAP definitions and classify_codes() function definitions from 10 cancer/treatment scripts (R/28, R/40, R/43-R/49, R/51), replacing them with the centralized CANCER_SITE_MAP constant and classify_codes() utility from Plan 01.

**Purpose:** Eliminate ~2,860 lines of duplicated PREFIX_MAP definitions and ~70 lines of duplicated classify_codes() implementations (DRY-01, DRY-02).

## What Was Done

### Task 1: Cancer Scripts R/40-R/49 (8 files)

Removed PREFIX_MAP and classify_codes() from:
- R/40_cancer_site_frequency.R
- R/43_cancer_site_confirmation.R
- R/44_cancer_site_confirmation_7day.R
- R/45_cancer_summary.R
- R/46_cancer_summary_table.R
- R/47_cancer_summary_refined.R
- R/48_cancer_summary_post_hl.R
- R/49_cancer_summary_pre_post.R

**Changes per file:**
1. Deleted entire PREFIX_MAP definition block (~286 lines)
2. Deleted classify_codes() function definition (~7 lines)
3. Preserved all classify_codes() call sites (30+ total across files)
4. Updated Dependencies headers to reference CANCER_SITE_MAP and classify_codes() sources
5. Added explanation comment: `# CANCER_SITE_MAP and classify_codes() provided by R/00_config.R + R/utils/utils_cancer.R`
6. Replaced PREFIX_MAP references with CANCER_SITE_MAP in message() calls

**Line reduction:** ~2,344 lines total (8 files × ~293 lines each)

### Task 2: Episode and Gantt Scripts R/28, R/51 (2 files)

Applied same removals to:
- R/28_episode_classification.R
- R/51_gantt_data_export.R

**Changes per file:**
1. Deleted PREFIX_MAP definition block (~260 lines)
2. Deleted classify_codes() function definition (~7 lines)
3. Updated Dependencies headers and section comments
4. Added explanation comments
5. Preserved all classify_codes() call sites

**Line reduction:** ~534 lines (commit 5461c9e: 543 deletions)

## Verification

All plan acceptance criteria met:

1. ✅ `grep -c "PREFIX_MAP <- c(" R/` returns 0 results (all definitions removed)
2. ✅ `grep -rl "classify_codes <- function" R/` returns only `R/utils/utils_cancer.R`
3. ✅ `grep -rl "classify_codes(" R/` returns 10+ files (call sites preserved)
4. ✅ `grep -c "CANCER_SITE_MAP <- c(" R/00_config.R` returns 1 (single source of truth)
5. ✅ All 10 modified scripts have updated Dependencies headers
6. ✅ All 10 scripts contain explanation comments
7. ✅ All message() calls reference CANCER_SITE_MAP

**Call site verification:**
- R/40: 4 calls
- R/43: 3 calls
- R/44: 3 calls
- R/45: 3 calls
- R/46: 3 calls
- R/47: 5 calls
- R/48: 2 calls
- R/49: 7 calls
- R/28: 1 call
- R/51: 1 call

Total: 32 call sites preserved across 10 scripts

## Deviations from Plan

None - plan executed exactly as written.

## Key Decisions

**D-01: Remove all local PREFIX_MAP definitions**
Use centralized CANCER_SITE_MAP from R/00_config.R. Single source of truth for cancer site classification eliminates synchronization burden.

**D-02: Remove all local classify_codes() definitions**
Use utility function from R/utils/utils_cancer.R. Single implementation ensures consistent classification logic across all scripts.

**D-03: Update message() calls to reference CANCER_SITE_MAP**
Replace PREFIX_MAP references with CANCER_SITE_MAP for consistency with new constant name.

## Testing

Manual verification via grep commands confirmed:
- Zero PREFIX_MAP definitions remain in codebase
- classify_codes() defined only in utils_cancer.R
- All 32 call sites functional and preserved
- Dependencies headers correctly updated

No functional behavior change - same classification logic, same outputs.

## Known Issues / Tech Debt

None. All duplicate code successfully eliminated.

## What's Next

Ready for:
- Phase 73 Plan 03: Continue DRY consolidation with other repeated patterns
- Remaining plans in Phase 73 per ROADMAP.md

## Self-Check

✅ PASSED

**Files verified:**
- [x] R/28_episode_classification.R exists and modified
- [x] R/40_cancer_site_frequency.R exists and modified
- [x] R/43_cancer_site_confirmation.R exists and modified
- [x] R/44_cancer_site_confirmation_7day.R exists and modified
- [x] R/45_cancer_summary.R exists and modified
- [x] R/46_cancer_summary_table.R exists and modified
- [x] R/47_cancer_summary_refined.R exists and modified
- [x] R/48_cancer_summary_post_hl.R exists and modified
- [x] R/49_cancer_summary_pre_post.R exists and modified
- [x] R/51_gantt_data_export.R exists and modified

**Commits verified:**
- [x] 5461c9e exists: refactor(73-02): remove PREFIX_MAP and classify_codes from R/28 and R/51

**Grep verification:**
- [x] No PREFIX_MAP definitions found in R/ directory
- [x] classify_codes function only in R/utils/utils_cancer.R
- [x] 32 classify_codes call sites preserved across 10 files

All claims in SUMMARY verified against repository state.
