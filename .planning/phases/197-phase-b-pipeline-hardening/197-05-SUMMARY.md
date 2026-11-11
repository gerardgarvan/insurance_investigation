---
phase: 197
plan: "05"
name: rxnorm-cache-single-owner
status: complete
completed: 2026-11-11
duration_min: 15
tasks_completed: 6
tasks_total: 6
files_modified: 3
commit: 52a7190

subsystem: pipeline-hardening
tags: [cache, idempotency, rxnorm, ownership]

dependency_graph:
  requires: [R/105 runs before R/131 on cold cache]
  provides: [D-197-05 single cache-owner contract]
  affects: [R/105_normalize_supportive_care_meaning.R, R/131_update_xlsx_med_admin_and_normalized_name.R]

tech_stack:
  patterns: [sole-writer cache contract, in-memory resolve pass-through, staleness logging]

key_files:
  modified:
    - R/105_normalize_supportive_care_meaning.R
    - R/131_update_xlsx_med_admin_and_normalized_name.R
    - R/SCRIPT_INDEX.md

key_decisions:
  - "D-197-05: R/105 is sole writer of rxnorm_ingredient_cache.csv; R/131 resolves CUIs in-memory and appends to xlsx only"
---

# Phase 197 Plan 05: rxnorm Cache Single Owner Summary

One-liner: R/105 designated sole writer of rxnorm_ingredient_cache.csv; R/131 converted to read-only cache consumer with idempotency guard fixed and staleness logging added.

## Changes Made

### R/105 — staleness message added

After reading the existing cache, a `cache_mtime` message now reports the file's last-modified timestamp:

```r
cache_mtime <- format(file.mtime(CACHE_CSV), "%Y-%m-%d %H:%M")
message("[R/105] rxnorm cache last updated: ", cache_mtime)
```

No other logic changed. R/105 already wrote the cache on new CUIs; it remains the sole writer.

### R/131 — three write_csv calls removed

| Site | Line (pre-patch) | Action |
|------|-----------------|--------|
| Checkpoint flush inside `resolve_tab_normalized_name` loop | ~442 | Removed `write_csv`; replaced with no-op comment |
| Final flush per tab inside the same function | ~447 | Removed; message updated to note in-memory only |
| Final cache save after all tabs | ~513 | Removed `write_csv`; message notes R/105 persists |

The `resolve_tab_normalized_name` function still builds `cache_df` in memory and returns it — this supports normalized_name resolution within the run without touching the file.

### R/131 — read-only comment and staleness message

At the cache-load block (Section 6), added:

```r
# rxnorm_ingredient_cache.csv is managed by R/105 (sole writer).
# R/131 reads it here and appends MED_ADMIN-exclusive CUIs to the xlsx only.
```

Staleness message on successful load:
```r
message("[R/131] rxnorm cache last updated: ", cache_mtime)
```

### R/131 — idempotency guard fix

The `chemo_existing` pull previously used `chemo_df` read at script start (line 84). On re-runs where Section 4 has already appended rows to `wb` in memory, that snapshot would be stale. Fix: re-read Chemotherapy from `wb` immediately before the anti_join:

```r
chemo_df_current <- wb_to_df(wb, sheet = "Chemotherapy", start_row = 2)
chemo_existing <- chemo_df_current %>%
  dplyr::filter(`Code Type` == "RXNORM") %>%
  dplyr::pull(Code)
```

### SCRIPT_INDEX

- R/105 entry: added "**Sole writer of `data/reference/rxnorm_ingredient_cache.csv`** (D-197-05)".
- R/131 entry: new row documenting read-only cache dependency, idempotency fix, and R/105 prerequisite.

## Deviations from Plan

None — plan executed exactly as written. Task 5 (parse checks) used the project's Node brace-balance script per CLAUDE.md (no Rscript locally); both scripts balanced 80/80 and 107/107 respectively.

## Self-Check: PASSED

- `R/105_normalize_supportive_care_meaning.R` exists and brace-balanced.
- `R/131_update_xlsx_med_admin_and_normalized_name.R` exists and brace-balanced.
- Commit 52a7190 confirmed in git log.
- Zero `write_csv.*CACHE_PATH` calls remain in R/131 (verified by grep).
