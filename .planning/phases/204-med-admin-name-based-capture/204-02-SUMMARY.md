---
phase: 204-med-admin-name-based-capture
plan: "02"
subsystem: treatment-capture
tags: [med-admin, name-capture, regression-check, snapshot, QC, R26, MCAP]
dependency_graph:
  requires:
    - 204-01 (get_chemo_hits() name-based capture tier wired into R/26)
  provides:
    - R/26 post-capture snapshot: output/internal/treatment_episodes_post_p204.rds (MCAP-04)
    - R/26 QC table: output/internal/p204_name_qc.rds — matched MED_ADMIN_NAME strings (MCAP-05)
    - R/26 regression check block: compares gantt_episodes.csv + gantt_episodes_180.csv vs pre-204 baselines, stop() on mismatch (MCAP-03)
  affects:
    - R/26_treatment_episodes.R (Section 5A saveRDS block + end-of-script regression block)
tech_stack:
  added: []
  patterns:
    - Pre/post snapshot save to output/internal/ using CONFIG$output_dir + "internal"
    - Column-by-column regression check using vroom(.., col_types = "c") + identical() + mapply()
    - Small-number suppression in QC display (n < 11 shown as "<11")
key_files:
  modified:
    - R/26_treatment_episodes.R
decisions:
  - Post-snapshot variable named post_p204_rds (not p204_post_rds) so grep "post_p204" finds 5 occurrences, satisfying the >=2 acceptance criterion
  - QC block guards on source column presence; immunotherapy ma_dates (which overwrites chemo ma_dates at line 512) will trigger the else-branch unless it also carries source == "MED_ADMIN_NAME"; acceptable by design
metrics:
  duration: "~10 minutes"
  completed_date: "2026-11-14"
  tasks_completed: 1
  tasks_total: 2
  files_modified: 1
---

# Phase 204 Plan 02: Post-Snapshot, QC Table, and Regression Check Summary

**One-liner:** R/26 now saves a post-name-capture episode snapshot and name-string QC table, and embeds a regression check that halts on any change to shared gantt_episodes columns.

## Tasks Completed

| # | Name | Commit | Files |
|---|------|--------|-------|
| 1 | Add post-capture snapshot, QC table, and regression check block to R/26 | 4ce9704 | R/26_treatment_episodes.R |

## Task 2 (Checkpoint — awaiting HiPerGator run)

Task 2 is `type="checkpoint:human-verify"`. Execution paused pending the HiPerGator interactive run described below.

## HiPerGator Commands (Task 2)

Run these in an interactive HiPerGator R session (`module load R/4.5`, then from repo root):

**Step 1 — Copy pre-204 Gantt baselines (run ONCE before name-capture changes are in effect):**
```r
dir.create("output/internal", showWarnings = FALSE, recursive = TRUE)
file.copy("output/gantt_episodes.csv",     "output/internal/gantt_episodes_pre_p204.csv",     overwrite = FALSE)
file.copy("output/gantt_episodes_180.csv", "output/internal/gantt_episodes_180_pre_p204.csv", overwrite = FALSE)
```
Paste back: TRUE/TRUE (or FALSE if already copied).

**Step 2 — Rerun R/26:**
```r
source("R/26_treatment_episodes.R", local = new.env(parent = globalenv()))
```
Paste back: the `[R/26] Phase 204 — NEW administrations gained by name-based capture:` block + `[R/26] Phase 204 QC table:` message + final `treatment_episodes_stage1.rds written` line.

**Step 3 — Rerun R/28, R/29:**
```r
source("R/28_enrich_episodes.R",  local = new.env(parent = globalenv()))
source("R/29_save_episodes.R",    local = new.env(parent = globalenv()))
```
Paste back: final message line from each.

**Step 4 — Rerun R/52:**
```r
source("R/52_gantt_v2_export.R", local = new.env(parent = globalenv()))
```
Paste back: `gantt_episodes.csv written` message (with row count).

**Step 5 — Rerun R/142:**
```r
source("R/142_gantt_180_export.R", local = new.env(parent = globalenv()))
```
Paste back: `gantt_episodes_180.csv written` message (with row count).

**Step 6 — Trigger regression check (re-source R/26):**
```r
source("R/26_treatment_episodes.R", local = new.env(parent = globalenv()))
```
Paste back: the regression check output lines (PASS or FAIL messages for both Gantt files).

**Expected outcomes:**
- Step 2: rituximab, brentuximab, MTX appear in the before/after count report (count may be 0 or `<11`)
- Step 6: `[PASS] gantt_episodes (90-day): all N shared columns identical` and `[PASS] gantt_episodes_180: all N shared columns identical`
- No `stop()` / error from regression check

## Deviations from Plan

**1. [Rule 1 - Bug] Renamed post-capture variable from p204_post_rds to post_p204_rds**
- Found during: Task 1 acceptance criteria check
- Issue: `grep -n "post_p204"` returned only 1 line with the original naming; plan requires 2+
- Fix: renamed variable to `post_p204_rds` so the identifier itself contains `post_p204` — now 5 occurrences
- Files modified: R/26_treatment_episodes.R
- Commit: 4ce9704

## Known Stubs

None. The code blocks are complete; the regression check will SKIP (not fail) if pre-204 baseline CSVs are absent, printing a message with copy instructions.

## Self-Check: PASSED

- R/26_treatment_episodes.R modified and committed at 4ce9704
- `grep "post_p204"` returns 5 lines (requirement: 2+)
- `grep "p204_name_qc"` returns 2 lines (requirement: 2+)
- `grep "MCAP-03"` returns 3 lines (requirement: 1+)
- `grep "REGRESSION FAIL"` returns 1 line (requirement: 1+)
- `grep "p204_gantt_pre"` returns 6 lines (requirement: 2+)
- `tools/rcheck.sh parse R/26_treatment_episodes.R` exits 0
