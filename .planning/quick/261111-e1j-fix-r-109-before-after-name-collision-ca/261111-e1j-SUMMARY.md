---
phase: quick-261111-e1j
plan: 01
completed: 2026-11-11
commit: eb9dfc3
files_modified:
  - R/109_med_admin_dispensing_fix_impact_audit.R
---

# Quick Task 261111-e1j: Fix R/109 before/after Name Collision

## Root Cause Confirmed

In R/109 Section 6 (D-03), `before` and `after` were simultaneously used as source data frame names (assigned at lines 208, 218) and as column names inside the same `tibble()` call (lines 242–245). R evaluated `before = c(n_distinct(before$ID), ...)` first, binding `before` to a numeric vector within the nascent tibble. When it then evaluated `after = c(n_distinct(after$ID), ...)`, `after` resolved to that just-created column, so `after$ID` failed with "$ operator is invalid for atomic vectors".

## All Renamed Occurrences

| File | Line (before edit) | Old | New |
|------|--------------------|-----|-----|
| R/109 | 208 | `before <- hits_rx_coh %>% distinct(...)` | `chemo_before <- hits_rx_coh %>% distinct(...)` |
| R/109 | 218 | `after <- after_labeled %>% distinct(...)` | `chemo_after <- after_labeled %>% distinct(...)` |
| R/109 | 220 | `n_distinct(before$ID)`, `nrow(before)` in message() | `n_distinct(chemo_before$ID)`, `nrow(chemo_before)` |
| R/109 | 221 | `n_distinct(after$ID)`, `nrow(after)` in message() | `n_distinct(chemo_after$ID)`, `nrow(chemo_after)` |
| R/109 | 242 | `n_distinct(before$ID)`, `nrow(before)` in tibble() | replaced by pre-computed `n_pat_before`, `n_pair_before` |
| R/109 | 243–245 | `n_distinct(after$ID)`, `nrow(after)` in tibble() | replaced by pre-computed `n_pat_after`, `n_pair_after` |

Pre-computed scalars added before the `tibble()` call:

```r
n_pat_before  <- n_distinct(chemo_before$ID)
n_pair_before <- nrow(chemo_before)
n_pat_after   <- n_distinct(chemo_after$ID)
n_pair_after  <- nrow(chemo_after)
```

Output column names (`before`, `after`, `delta`) in `df_before_after_summary_raw` and workbook sheets are unchanged.

## grep Results for R/107 and R/110

- R/107: no `before$` or `after$` patterns found — clean, no edits needed.
- R/110: no `before$` or `after$` patterns found — clean, no edits needed.

## Static Check Results

Post-edit grep of R/109 for `before$|after$`:

- Line 220: `chemo_before$ID`, `nrow(chemo_before)` — correct (message call, not tibble column).
- Line 221: `chemo_after$ID`, `nrow(chemo_after)` — correct (message call, not tibble column).
- Line 240: `chemo_before$ID` inside `n_distinct()` scalar assignment — correct.
- Line 242: `chemo_after$ID` inside `n_distinct()` scalar assignment — correct.

No bare `before$ID` or `after$ID` referencing the D-03 data frames remain.

Brace-balance script: not found at R/tools/check_syntax* — skipped gracefully.

Previous fix commit 6637ec4 (261111-cxn, small-cell suppression at display) confirmed present in git log.

## SLURM Check

`$SLURM_JOB_ID` is empty (Windows local environment). No R scripts run. Parse-check only.

## Deviations

None — plan executed exactly as written.

## Commit

`eb9dfc3` — fix(109): rename before/after data frames to chemo_before/chemo_after; pre-compute scalars to avoid tibble column name collision in Section 6 D-03
