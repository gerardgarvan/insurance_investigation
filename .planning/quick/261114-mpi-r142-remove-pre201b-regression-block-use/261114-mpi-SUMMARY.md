---
phase: quick-261114-mpi
plan: 01
subsystem: R/142
tags: [regression-block, gantt-180, cleanup]
dependency_graph:
  requires: []
  provides: [R/142 runs without PRE201B error]
  affects: [gantt_episodes_180.csv export]
tech_stack:
  added: []
  patterns: []
key_files:
  modified:
    - R/142_gantt_180_export.R
decisions: []
metrics:
  duration: "< 5 min"
  completed: "2026-11-14"
  tasks_completed: 1
  files_modified: 1
---

# Quick Task 261114-mpi: Remove PRE201B Regression Blocks from R/142

**One-liner:** Deleted both `RUN_PRE201B_REGRESSION`-gated blocks from R/142 (save + check) that permanently failed because the output file already has 32 columns, not 30.

## What Changed

Removed two `if (Sys.getenv("RUN_PRE201B_REGRESSION") == "TRUE") { ... }` blocks from `R/142_gantt_180_export.R`:

- **Block 1** (lines 1322–1337): saved a PRE201B baseline copy and ran `stopifnot(ncol == 30L)` — always failed because the current output file has 32 columns.
- **Block 2** (lines 1343–1362): read the baseline and ran a row-identity regression check — depended on block 1.

Untouched: `RUN_PRE201_REGRESSION` (26-col baseline, lines intact), `RUN_PRE199_REGRESSION`, all other blocks.

## Verification

- `grep -n "RUN_PRE201B_REGRESSION" R/142_gantt_180_export.R` → no output (0 matches)
- `grep -c "RUN_PRE201_REGRESSION" R/142_gantt_180_export.R` → 2 (PRE201 block intact)
- `tools/rcheck.sh parse R/142_gantt_180_export.R` → exit 0, 1 file parsed, 0 failed

## Commits

| Hash | Message |
|------|---------|
| 0468c5e | fix(quick-261114-mpi): remove both RUN_PRE201B_REGRESSION blocks from R/142 |

## Deviations from Plan

None — plan executed exactly as written.
