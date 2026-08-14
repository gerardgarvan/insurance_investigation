---
phase: quick
plan: 260814-gwb
subsystem: planning-docs
tags: [phase-142, drug-dedup, 180-day-episodes, patch-application]
dependency_graph:
  requires: [142-PATCH.md]
  provides: [CONTEXT.md-updated, 142-01-PLAN.md-updated, 142-02-PLAN.md-updated, 142-DISCOVERY.md-created]
  affects: [phase-142-execution]
tech_stack:
  added: []
  patterns: [patch-application, planning-doc-update]
key_files:
  created:
    - .planning/phases/142-180-day-treatment-episodes-drug-name-deduplication/142-DISCOVERY.md
  modified:
    - .planning/phases/142-180-day-treatment-episodes-drug-name-deduplication/CONTEXT.md
    - .planning/phases/142-180-day-treatment-episodes-drug-name-deduplication/142-01-PLAN.md
    - .planning/phases/142-180-day-treatment-episodes-drug-name-deduplication/142-02-PLAN.md
decisions:
  - "Applied all P0/P1/P2 corrections from 142-PATCH.md to planning files before Phase 142 executes"
  - "Created 142-DISCOVERY.md as a self-contained pre-flight checklist independent of the patch"
metrics:
  duration: ~15 min
  completed: 2026-08-14
---

# Quick Task 260814-gwb: Apply 142-PATCH.md Corrections to Phase 142 Planning Files

Applied all P0 (blocking), P1 (should fix), and P2 (minor) corrections from 142-PATCH.md to the three Phase 142 planning files and created 142-DISCOVERY.md as a standalone pre-flight discovery template.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Update CONTEXT.md | c5593cf | CONTEXT.md |
| 2 | Update 142-01-PLAN.md | 511d668 | 142-01-PLAN.md |
| 3 | Update 142-02-PLAN.md + create 142-DISCOVERY.md | 2a66ce2 | 142-02-PLAN.md, 142-DISCOVERY.md |

## Changes Applied

### CONTEXT.md (Task 1)

- **Removed** the contradictory "No changes to the 90-day pipeline or existing output files" Out of Scope line (P0-03 fix — the DRUG_NAME_ALIASES fix necessarily affects both windows)
- **Added D-05**: drug-name fix applies to both windows; archive prior 90-day outputs as `*_pre142.csv` before regeneration so the change is reversible and auditable
- **Amended D-01**: added §0c verification requirement and the two-interpretation discriminating test (2 episodes = window-from-start; 1 episode = gap-between-dates)

### 142-01-PLAN.md (Task 2)

- **Frontmatter `files_modified`**: added conditional note that R/26 may also need updating depending on §0b grep result (P0-02)
- **Task 0 prepended**: new `checkpoint:human-action` task requiring §0a/§0b/§0c discovery on HiPerGator before any code edits
- **Step 2 replaced**: speculative dacarbazine/bleomycin/vincristine list replaced with enumerate-then-group approach using the real `det$drug_name` values (P1-01); liposomal forms explicitly excluded
- **Direction comment added**: DRUG_NAME_ALIASES block comment now states that canonical value is always MEDICATION_LOOKUP's authority, explaining why doxorubicin (base→salt) and vinblastine (salt→base) go opposite directions (P1-02)
- **P0-01 assertion added** to Task 1 verify block: checks that alias keys match observed `drug_name` strings, not assumed RxNorm strings
- **P1-03 CSV token check added** to Task 1 done block: verifies exactly one vinblastine-matching token in both gantt CSVs

### 142-02-PLAN.md (Task 3)

- **P0-03 before/after check**: Task 1 done block now requires archiving prior 90-day CSV and verifying content changed (2→1 vinblastine tokens), replacing the row-count-only "unchanged" check
- **P1-05 fan-out assertion**: Task 1 action block now captures `n_before_join` before the left-join and asserts `nrow(detail_df_180) == n_before_join` (the `annotate_detail_with_episodes()` call now assigned to named intermediate `annotated_180`)
- **P1-04 invariants added** to Task 1 verify block: patient count held constant, median episode length non-decreasing, `sprintf` summary output added; duplicate bare `stopifnot` replaced by combined block
- **P1-03 CSV token check added** to Task 2 done block: vinblastine token count check for `gantt_episodes_180.csv`
- **P2-02 schema identity check**: hardcoded `ncol(ep) == 20` / `ncol(det) == 14` replaced with `identical(names(ref_ep), names(new_ep))` comparison against the actual 90-day files
- **P2-01 numbering note added** to Task 2 done block: confirms whether `R/142_gantt_180_export.R` should be renumbered as `R/53_gantt_180_export.R` for R/39 registration

### 142-DISCOVERY.md (Task 3, new file)

Self-contained pre-flight checklist with:
- §0a: exact `drug_name` strings in `treatment_episode_detail.rds` (alias key derivation)
- §0b: `canonicalize_drug_name` call-site grep (determines if R/26 needs a fix)
- §0c: episode rule discrimination test (confirms which interpretation `calculate_episodes_detailed()` implements)
- Sign-off checklist with fill-in slots for alias key, §0b result, §0c result, and go/no-go decision

## Deviations from Plan

None — plan executed exactly as written.

## Verification

All checks pass:
- `grep -c "D-05" CONTEXT.md` → 1
- `grep -c "No changes to the 90-day" CONTEXT.md` → 0
- `grep -ic "Task 0" 142-01-PLAN.md` → 1
- `grep -ic "enumerate" 142-01-PLAN.md` → 1
- `grep -c "unmapped" 142-01-PLAN.md` → 3
- `grep -c "n_before_join" 142-02-PLAN.md` → 2
- `grep -c "identical(names" 142-02-PLAN.md` → 2
- `grep -c "§0a" 142-DISCOVERY.md` → 2
- `grep -c "§0b" 142-DISCOVERY.md` → 2
- `grep -c "§0c" 142-DISCOVERY.md` → 2

## Self-Check: PASSED

All four files exist and all patch corrections are reflected. 142-DISCOVERY.md is self-contained (no reference to 142-PATCH.md required to understand and execute it). No contradictions remain between the planning files and the patch.
