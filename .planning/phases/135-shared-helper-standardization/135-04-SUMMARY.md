---
phase: 135-shared-helper-standardization
plan: "04"
subsystem: R-pipeline-grain-labels
tags: [PATTERN-H, rename, grain, encounter_count, episode_count, n_total_encounters, n_total_dates]
dependency_graph:
  requires: []
  provides: [PATTERN-H]
  affects: [R/56, R/57, R/62, R/67]
tech_stack:
  added: []
  patterns: [named-predicate, grain-labeled columns]
key_files:
  modified:
    - R/56_new_tables_from_groupings.R
    - R/57_explore_dx_deduplication.R
    - R/62_tiered_date_level.R
    - R/67_multi_source_overlap_detection.R
decisions:
  - "R/56 Table 1 has no encounter_count — it is instance-level (no aggregation); only Table 2 needed renaming"
  - "R/62 has no subtitle_text chart element (file is 338 lines, not 381+); header and message were the only two grain description locations"
  - "R/67 same_week message loop already omits n_total_dates from its glue string — only same_date loop referenced it; both select() calls updated"
metrics:
  duration: "~8 minutes"
  completed: "2026-07-25"
  tasks: 2
  files_modified: 4
---

# Phase 135 Plan 04: Grain-Label Fixes (PATTERN-H) Summary

Renamed grain-mislabeled columns in R/56, R/57, R/62, and R/67 to make metric semantics transparent.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Rename encounter_count to episode_count in R/56 and R/57 | 3f3ed99 | R/56_new_tables_from_groupings.R, R/57_explore_dx_deduplication.R |
| 2 | Clarify R/62 grain comment and rename R/67 n_total_encounters | 8b0bf25 | R/62_tiered_date_level.R, R/67_multi_source_overlap_detection.R |

## What Was Done

**Task 1 — R/56 and R/57:**
- R/56 Table 2 `summarise(encounter_count = n())` renamed to `episode_count = n()`; `arrange(desc(...))` updated to match
- R/56 header comments D-05 and D-14 updated from `encounter_count` to `episode_count`
- R/57 both summarise calls (`table1_before` and `table1_after`) renamed to `episode_count = n()`
- R/56 Table 1 confirmed to have no `encounter_count` (it is instance-level with no aggregation — no change needed there)
- R/88 smoke test already asserts R/57 must NOT contain `encounter_count`, so the rename makes R/57 compliant

**Task 2 — R/62 and R/67:**
- R/62 file header comment updated: `date_tier_detail.csv` grain now reads "patient x treatment_type x episode x date; multiple rows per patient when treatment types or episodes overlap"
- R/62 message line updated to reflect correct grain
- R/62 has no subtitle_text chart element (file is 338 lines total, shorter than plan estimate of 381); only two grain description locations existed
- R/67 `n_total_encounters` renamed to `n_total_dates` in: `same_date_combo_freq` summarise, `same_week_combo_freq` summarise, message glue string, and both `select()` calls for CSV3 output
- PATTERN-H explanatory comment added above `same_week_combo_freq` definition documenting intentional double-counting

## Deviations from Plan

### Minor Scope Adjustments

**1. [Rule 1 - Bug/Scope] R/56 Table 1 has no encounter_count**
- Found during: Task 1 audit
- Issue: Plan says to "find Table 1's encounter_count = n()". Table 1 in R/56 is instance-level (no aggregation); it uses `select()` only. No rename was needed there.
- Fix: Skipped Table 1 rename (nothing to rename). Only D-05 and D-14 header comments were updated.
- Files modified: R/56_new_tables_from_groupings.R (comments only for Table 1 section)

**2. [Rule 1 - Scope] R/62 has no subtitle_text element**
- Found during: Task 2
- Issue: Plan describes a `subtitle_text = "Grain: encounter..."` around line 381. The file has only 338 lines and no such chart subtitle string.
- Fix: Updated the two grain description locations that do exist (file header line 15 and message line 327). No subtitle_text change made (element absent).

## Known Stubs

None — all changes are rename/comment only; no data wiring involved.

## Self-Check: PASSED

- R/56: no `encounter_count = n()` definitions remain; `episode_count` present — confirmed
- R/57: no `encounter_count = n()` definitions remain; `episode_count` present — confirmed
- R/62: "patient x treatment_type x episode x date" present in file — confirmed
- R/67: no `n_total_encounters =` definitions remain; `n_total_dates` present — confirmed
- Commits 3f3ed99 and 8b0bf25 verified in git log
