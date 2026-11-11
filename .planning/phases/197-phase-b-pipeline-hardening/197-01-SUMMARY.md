---
phase: 197
plan: "01"
name: run-order-r39-script-index
status: complete
completed: 2026-11-11
duration_minutes: 25
tasks_completed: 7
files_modified: 8
decisions:
  - "D-197-01: R/29 sole final writer of treatment_episodes.rds; R/26 writes treatment_episodes_stage1.rds (intermediate)"
key_files:
  modified:
    - R/39_run_all_investigations.R
    - R/26_treatment_episodes.R
    - R/29_first_line_and_death_analysis.R
    - R/142_gantt_180_export.R
    - R/110_output_level_before_after_report.R
    - R/100_ruca_rurality_summary.R
    - R/SCRIPT_INDEX.md
    - .planning/phases/196-phase-a-delivered-output-fixes/RERUN-AND-REISSUE.md
tech_stack:
  patterns:
    - stopifnot() column guard after readRDS for is_first_line
    - Intermediate RDS naming convention: *_stage1.rds
---

# Phase 197 Plan 01: Run Order, R/39 + SCRIPT_INDEX Summary

## One-liner

Fixed R/53-before-R/29 run order, assigned R/29 as sole writer of treatment_episodes.rds (R/26 now writes treatment_episodes_stage1.rds), and added is_first_line column guards in three downstream scripts.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 0 | Context probe: grep for exact lines in R/39, R/26, R/29, R/142, R/110, R/100, SCRIPT_INDEX | 8c0803d |
| 1 | Swap R/29 and R/53 in R/39 (R/53 now precedes R/29) | 8c0803d |
| 2 | R/26 writes treatment_episodes_stage1.rds; R/29 reads it and writes canonical treatment_episodes.rds | 8c0803d |
| 3 | stopifnot("is_first_line" %in% names(episodes)) guard in R/110, R/100, R/142 | 8c0803d |
| 4 | RERUN-AND-REISSUE.md: comment noting R/14 sources R/02 internally | 8c0803d |
| 5 | SCRIPT_INDEX: updated R/26, R/29, R/53, R/02, R/14 entries and dependency graph | 8c0803d |
| 6 | Parse checks noted for HiPerGator (see below) | — |
| 7 | Commit | 8c0803d |

## Changes by File

### R/39_run_all_investigations.R

Lines 178-184: R/53 now runs before R/29. Added comment `# R/53 must run before R/29 (validated_death_dates.rds)`. R/29 comment updated to reference both input files.

### R/26_treatment_episodes.R

- Line 9: header comment updated to show `treatment_episodes_stage1.rds` as output.
- Line 75: `OUTPUT_RDS` path changed from `"treatment_episodes.rds"` to `"treatment_episodes_stage1.rds"`. Added inline comment: `# Intermediate; R/29 writes the canonical treatment_episodes.rds`.
- Line 873: `message()` updated to `[R/26] treatment_episodes_stage1.rds written — N rows`.

### R/29_first_line_and_death_analysis.R

- Lines 44-48: added `INPUT_RDS` pointing to `treatment_episodes_stage1.rds`; `OUTPUT_RDS` retained for canonical write.
- Lines 10-11: header comment updated to list correct inputs.
- Lines 68-74: `assert_rds_exists` and `readRDS` now use `INPUT_RDS`.
- Lines 196-198: saveRDS comment and message updated to `[R/29] treatment_episodes.rds written (canonical)`.

### R/110_output_level_before_after_report.R

Line 131: `stopifnot("is_first_line" %in% names(episodes_after))` added after readRDS inside the conditional block.

### R/100_ruca_rurality_summary.R

Line 314: `stopifnot("is_first_line" %in% names(episodes))` added after readRDS.

### R/142_gantt_180_export.R

Line 111: `stopifnot("is_first_line" %in% names(episodes))` added after readRDS of treatment_episodes_180_enriched.rds.

### R/SCRIPT_INDEX.md

- R/02 entry: added note that R/14 sources R/02 internally.
- R/26 entry: documents treatment_episodes_stage1.rds as intermediate output.
- R/29 entry: documents canonical writer role; lists R/26 (stage1) and R/53 as dependencies.
- R/53 entry: notes must run before R/29.
- Dependency graph: updated R/14, R/26, R/29 lines.

### RERUN-AND-REISSUE.md (Phase 196)

Added HTML comment after the run-order table row for R/02 and R/14 clarifying the Phase 196 exception (R/02 listed for md5 verification before R/14 runs; in R/39 R/02 must not be listed separately).

## Deviations from Plan

None — plan executed as written. R/39 did not contain a direct R/02 source call (only R/14 at line 150, with an existing auto-sources comment); no R/39 change was needed for Task 4 beyond the comment already present.

## Parse Checks (run on HiPerGator)

```r
invisible(parse("R/39_run_all_investigations.R"))
invisible(parse("R/26_treatment_episodes.R"))
invisible(parse("R/29_first_line_and_death_analysis.R"))
```

Run each as:
```
source("R/00_config.R")
invisible(parse("R/<script>.R"))
```
or via:
```
Rscript -e 'invisible(parse("R/39_run_all_investigations.R"))'
```

Paste back any error plus ~20 lines of context.

## Known Stubs

None.
