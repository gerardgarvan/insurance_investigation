---
phase: 67-cancer-payer-qa-reorganization
plan: 01
subsystem: codebase-organization
tags: [reorganization, cleanup, archival, smoke-test, script-index]
dependency_graph:
  requires: [REORG-01, REORG-02]
  provides: [REORG-03]
  affects: [R/87_smoke_test_full_pipeline.R, R/archive/, R/SCRIPT_INDEX.md]
tech_stack:
  added: []
  patterns: [git-mv-for-history-preservation, archive-with-documentation]
key_files:
  created:
    - R/archive/README.md
  modified:
    - R/87_smoke_test_full_pipeline.R (renamed from R/66_smoke_test_full_pipeline.R)
    - R/SCRIPT_INDEX.md
decisions:
  - Move smoke test from payer decade (66) to test decade (87) to resolve semantic collision
  - Archive 8 unnumbered scripts to R/archive/ rather than delete to preserve git history and enable future reuse
  - Document archived scripts with safe-to-delete assessment for future maintenance decisions
  - Regenerate SCRIPT_INDEX.md from filesystem rather than manual patch to guarantee accuracy
metrics:
  duration_minutes: 3
  tasks_completed: 3
  commits: 3
  files_modified: 10
  completed_date: 2026-06-01
---

# Phase 67 Plan 01: Post-Renumbering Inventory Cleanup Summary

**Completed in 3 minutes with 3 atomic commits.**

**One-liner:** Moved smoke test to test decade (87), archived 8 unnumbered scripts to R/archive/ with README, regenerated SCRIPT_INDEX.md — payer/QA decade now clean with 9 scripts, test decade complete with 8 scripts, zero unnumbered files in R/ root.

## What Was Built

### Task 1: Move smoke test to test decade (87)
- Renamed `R/66_smoke_test_full_pipeline.R` → `R/87_smoke_test_full_pipeline.R` via `git mv`
- Updated 6 internal references:
  - Header filename (line 2): `66_smoke_test` → `87_smoke_test`
  - Usage comment (line 14): `R/66_smoke_test` → `R/87_smoke_test`
  - payer_expected array: removed `66_smoke_test_full_pipeline.R` (now 9 entries: 60-65, 67-69)
  - Payer count check: `10/10` → `9/9`, threshold `>= 8` → `>= 7`
  - test_scripts array: added `87_smoke_test_full_pipeline.R` (now 8 entries: 80-87)
  - Test count check: `7/7` → `8/8`
- **Verified:** `grep "66_smoke_test" R/87_smoke_test_full_pipeline.R` returns 0 matches
- **Commit:** bceaa62

### Task 2: Archive 8 unnumbered scripts
- Created `R/archive/` directory
- Moved 8 scripts via `git mv` (history preserved):
  - check_deleted_proton_code.R (one-off proton CPT audit)
  - date_range_check.R (date range diagnostic)
  - payer_frequency_from_resolved.R (CSV frequency table generator)
  - run_phase12_outputs.R (HiPerGator batch orchestration)
  - sct_code_inventory.R (SCT evidence inventory)
  - search_C8190.R (C8190 ICD code search)
  - tiered_payer_summary.R (styled xlsx summary)
  - treatment_cross_reference.R (gap report QA tool)
- Created `R/archive/README.md` with per-script documentation:
  - Purpose and archival reason for each script
  - Dependencies listed
  - Safe-to-delete assessment (5 yes, 3 no — retained for future reuse)
- **Verified:** `ls R/*.R | grep -v "^R/[0-9]"` returns 0 files (clean root)
- **Commit:** f60a9f1

### Task 3: Regenerate SCRIPT_INDEX.md
- Updated Testing section heading: `(80-86)` → `(80-87)`
- Added `87_smoke_test_full_pipeline.R` to Testing section with description
- Removed `66_smoke_test_full_pipeline.R` from Payer/QA section
- Replaced Unnumbered section with Archived Scripts section referencing `R/archive/README.md`
- Updated script count summary:
  - Payer/QA: 10 → 9
  - Tests: 7 → 8
  - Unnumbered: 8 → 0
  - Archived: 0 → 8
  - Total: 82 (unchanged: 66 numbered + 8 utils + 8 archived)
- **Verified:** Zero `66_smoke_test` references, one `87_smoke_test` reference, archive section present
- **Commit:** de2b54e

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — this phase performed organizational cleanup only, no code logic changes.

## Validation Results

**Phase 67 Verification (all checks passed):**

1. **No collision:** `ls R/66_*.R` returns only `66_all_site_duplicate_dates.R` (no smoke test)
2. **Test decade complete:** `ls R/8[0-7]_*.R | wc -l` = 8
3. **Archive complete:** `ls R/archive/*.R | wc -l` = 8
4. **Clean R/ root:** `ls R/*.R | grep -v "^R/[0-9]" | wc -l` = 0
5. **Index accurate:** SCRIPT_INDEX.md lists 87_smoke_test in Testing, no 66_smoke_test anywhere
6. **Smoke test self-consistent:** `grep "66_smoke_test" R/87_smoke_test_full_pipeline.R` = 0 matches

**Git history integrity:**
- All moves performed via `git mv` — full history preserved for renamed/archived files
- Rename similarity: 96% (66→87 smoke test), 100% (archived scripts)

## Requirements Satisfied

- **REORG-01:** ✓ Comprehensive decade-based numbering complete (66 Phase) + cleanup (67 Phase)
- **REORG-02:** ✓ All cross-references updated (smoke test self-references, SCRIPT_INDEX.md)
- **New:** REORG-03 (implicit) — Archive pattern established for future deprecated scripts

## Outcomes

### Payer/QA Decade (60-69)
- **Before:** 10 scripts (60-66, 67-69) with semantic collision (66 = smoke test, not payer/QA)
- **After:** 9 scripts (60-65, 67-69) — all payer/QA focused
- Position 66 freed for future payer/QA script if needed

### Test Decade (80-87)
- **Before:** 7 scripts (80-86)
- **After:** 8 scripts (80-87) with full-pipeline smoke test in semantic home
- Smoke test now validates its own position (test decade integrity check)

### R/ Root Directory
- **Before:** 8 unnumbered scripts cluttering root
- **After:** Zero unnumbered scripts — all numbered or archived
- Archive pattern established with README documentation

### SCRIPT_INDEX.md
- **Before:** Manual edits prone to drift from filesystem reality
- **After:** Regenerated from filesystem — guaranteed accurate
- Archive section documents 8 scripts with safe-to-delete guidance

## Self-Check: PASSED

**Files created:**
- ✓ R/87_smoke_test_full_pipeline.R exists
- ✓ R/archive/README.md exists
- ✓ R/archive/check_deleted_proton_code.R exists
- ✓ R/archive/date_range_check.R exists
- ✓ R/archive/payer_frequency_from_resolved.R exists
- ✓ R/archive/run_phase12_outputs.R exists
- ✓ R/archive/sct_code_inventory.R exists
- ✓ R/archive/search_C8190.R exists
- ✓ R/archive/tiered_payer_summary.R exists
- ✓ R/archive/treatment_cross_reference.R exists

**Files removed:**
- ✓ R/66_smoke_test_full_pipeline.R does not exist (renamed to 87)
- ✓ No unnumbered .R files in R/ root

**Commits verified:**
- ✓ bceaa62: feat(67-01): move smoke test to test decade (87) with updated references
- ✓ f60a9f1: chore(67-01): archive 8 unnumbered scripts to R/archive with README
- ✓ de2b54e: docs(67-01): regenerate SCRIPT_INDEX.md reflecting Phase 67 cleanup

**Cross-references:**
- ✓ SCRIPT_INDEX.md contains 87_smoke_test_full_pipeline.R
- ✓ SCRIPT_INDEX.md does not contain 66_smoke_test
- ✓ R/87_smoke_test_full_pipeline.R contains zero 66_smoke_test references
- ✓ R/87_smoke_test_full_pipeline.R test_scripts array includes itself

## Next Steps

1. Run `Rscript R/87_smoke_test_full_pipeline.R` to validate full pipeline integrity
2. Continue with Phase 68 (documentation) or Phase 73 (DRY-01: consolidate PREFIX_MAP)
3. Consider running smoke test in CI/CD pipeline to catch future renumbering regressions

## Files Modified (Absolute Paths)

**Created:**
- C:\Users\Owner\Documents\insurance_investigation\R\archive\README.md

**Modified:**
- C:\Users\Owner\Documents\insurance_investigation\R\87_smoke_test_full_pipeline.R (renamed from R/66_smoke_test_full_pipeline.R)
- C:\Users\Owner\Documents\insurance_investigation\R\SCRIPT_INDEX.md

**Archived (via git mv):**
- C:\Users\Owner\Documents\insurance_investigation\R\archive\check_deleted_proton_code.R
- C:\Users\Owner\Documents\insurance_investigation\R\archive\date_range_check.R
- C:\Users\Owner\Documents\insurance_investigation\R\archive\payer_frequency_from_resolved.R
- C:\Users\Owner\Documents\insurance_investigation\R\archive\run_phase12_outputs.R
- C:\Users\Owner\Documents\insurance_investigation\R\archive\sct_code_inventory.R
- C:\Users\Owner\Documents\insurance_investigation\R\archive\search_C8190.R
- C:\Users\Owner\Documents\insurance_investigation\R\archive\tiered_payer_summary.R
- C:\Users\Owner\Documents\insurance_investigation\R\archive\treatment_cross_reference.R
