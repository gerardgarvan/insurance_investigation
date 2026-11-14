---
phase: quick
plan: 261113-t4d
subsystem: R/142
tags: [bug-fix, cross-tab, regimen_label]
key_files:
  modified: [R/142_gantt_180_export.R]
decisions: []
metrics:
  duration: "< 5 min"
  completed: "2026-11-13"
  tasks: 1
  files: 1
---

# Quick Task 261113-t4d: Fix R/142 Section 4C4 ABVD Cross-Tab Crash

**One-liner:** Extended regimen_label recode in ct_abvd to catch empty-string (from Section 4D NA-to-blank conversion), preventing un-indexable "" column name in table().

## What Changed

**R/142_gantt_180_export.R line 953** — `ct_abvd` table() call recode:

Before:
```r
regimen_label = ifelse(is.na(chemo_ep$regimen_label), "(NA)", chemo_ep$regimen_label)
```

After:
```r
regimen_label = ifelse(is.na(chemo_ep$regimen_label) | chemo_ep$regimen_label == "", "(none)", chemo_ep$regimen_label)
```

## Root Cause

Section 4D converts NA character values to `""` before Section 4C4 executes. The old recode only caught `is.na()`, leaving `""` values unchanged. `table()` then created a column named `""`, which `ct_abvd[r, ""]` cannot index, producing "subscript out of bounds".

## Verification

- `tools/rcheck.sh parse R/142_gantt_180_export.R` exits 0
- Section 4C5 confirmed unaffected (data-frame loop, no `[r, cc]` indexing)

## Commit

`a691134` — fix(261113-t4d): extend regimen_label recode to catch empty-string in ct_abvd

## Deviations

None — plan executed exactly as written.
