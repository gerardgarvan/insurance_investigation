---
phase: 152-encounter-zip-to-residence-distance
plan: "03"
subsystem: investigations
tags: [distance, geospatial, haversine, xlsx, registration]
dependency_graph:
  requires: ["152-02"]
  provides: ["encounter_distance_YYYYMMDD.xlsx", "encounter_distance_YYYYMMDD.rds"]
  affects: ["R/39_run_all_investigations.R", "R/88_smoke_test_comprehensive.R", "R/SCRIPT_INDEX.md"]
tech_stack:
  added: []
  patterns: ["add_styled_sheet copy from R/115", "wb_workbook KEY-leftmost pattern"]
key_files:
  created: []
  modified:
    - R/122_encounter_distance.R
    - R/39_run_all_investigations.R
    - R/88_smoke_test_comprehensive.R
    - R/SCRIPT_INDEX.md
decisions:
  - "RDS output is the full enc_distance tibble (not a list) -- 12 columns, one row per encounter, sufficient for downstream joining without re-running"
  - "zip3_state.csv absent: gracefully emit unmatched ZIP9 as STATE='ALL' row with a QC note row; do not error"
  - "D_flags filters to > 50 km (secondary), add flag_gt200 = distance_km > 200 (primary); both thresholds present in one table"
metrics:
  duration_minutes: 35
  completed_date: "2026-09-15"
  tasks_completed: 2
  tasks_total: 3
  files_modified: 4
---

# Phase 152 Plan 03: SECTION 8-12 + Registration Summary

**One-liner:** SECTION 8-12 appended to R/122 (patient summary, distribution with include.lowest=TRUE, flags, QC waterfall, xlsx+rds assembly), registered in R/39/R/88/SCRIPT_INDEX.md; Task 3 is a blocking HiPerGator checkpoint.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | SECTION 8-11: patient summary, distribution, flags, QC waterfall | b1d5633 | R/122_encounter_distance.R (+420 lines) |
| 2 | SECTION 12: xlsx+rds; R/39, R/88, SCRIPT_INDEX.md registration | c1a6c3b | R/39, R/88, SCRIPT_INDEX.md |
| 3 | HiPerGator end-to-end run | — | BLOCKING CHECKPOINT — awaiting user |

## What Was Built

### SECTION 8 — B_patient_summary
Per-patient summary with exact CONTEXT.md columns: `n_encounters`, `n_with_distance`, `median_km`, `iqr_km`, `max_km`, `pct_gt50km`, `pct_gt200km`. All-NA guards applied (all-NA groups return `NA_real_` rather than `-Inf`/`NaN`). Fallback encounters included per D-02.

### SECTION 9 — C_distribution
Distance binned with `cut(distance_km, breaks = c(0, 5, 25, 50, 200, Inf), labels = c("0-5","5-25","25-50","50-200",">200"), include.lowest = TRUE, right = FALSE)`. `include.lowest = TRUE` is present so zero-distance rows (same ZIP on both sides) fall in the 0-5 bin instead of becoming NA. NA-distance rows appear as an explicit `"NA"` bin. Counts by bin × distance_basis: n_encounters + n_patients.

### SECTION 10 — D_flags
Filtered to `distance_km > 50` (secondary threshold); `flag_gt200 = distance_km > 200` column provides primary threshold. Both D-01 thresholds represented in one table.

### SECTION 11 — QC waterfall
Six-row coverage waterfall from `n_enc_cohort_raw` (raw DuckDB before date filter) through `n_distance_computed`. Reconciliation `stopifnot` confirming `n_admit_date_usable == nrow(enc_distance)`. WV gap NOTE row with verbatim Pitfall 7 text. Fallback sensitivity row (D-02): median/max over res_match_fallback == TRUE encounters. ZIP3 → state lookup via `data/reference/zip3_state.csv` (absent in this repo — graceful fallback to STATE="ALL" row + QC note). `zip9_crosswalk_present` flag row.

### SECTION 12 — xlsx + rds
`add_styled_sheet()` copied verbatim from R/115 (lines 2126-2174). `wb_workbook()` assembles 6 sheets in order: KEY (leftmost, D-02 pattern), A_encounter_distance, B_patient_summary, C_distribution, D_flags, QC. KEY carries D-03 open-question text verbatim. QC sheet uses `extra_tbl` for the unmatched-by-state subtable. RDS saves the full `enc_distance` tibble (12 columns, one row per encounter).

### Registration
- **R/39:** trailing comma added to R/121 line; R/122 entry added on next line.
- **R/88:** Section 15ah with 14 structural grep-based checks, `p152_pass`/`p152_fail` counters, summary `message(glue(...))`.
- **SCRIPT_INDEX.md:** R/122 row appended to Investigations table; post-renumber count 18 → 19; Total 103 → 104.

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written for Tasks 1 and 2.

### Runtime Note

Rscript is NOT available on this Windows machine. All verification was performed via grep-based structural checks. Automated `Rscript -e "..."` acceptance criteria from the plan cannot be executed locally. Runtime verification requires HiPerGator (Task 3 blocking checkpoint).

## Task 3 — Blocking Checkpoint (Awaiting User)

Task 3 is a `checkpoint:human-verify` gate requiring a HiPerGator end-to-end run. It has not been executed. See the checkpoint message below for exact steps.

## Known Stubs

None. All tibbles and sheet names are wired; no hardcoded empty data or placeholder values that would prevent the plan's goal from being achieved (runtime requires HiPerGator data files).

## Self-Check

### Created/Modified Files Exist

- R/122_encounter_distance.R: modified (420 lines added in Tasks 1-2)
- R/39_run_all_investigations.R: modified (R/122 registered)
- R/88_smoke_test_comprehensive.R: modified (Section 15ah added)
- R/SCRIPT_INDEX.md: modified (R/122 row + count bump)

### Commits Exist

- b1d5633: feat(152-03): add SECTION 8-12 to R/122
- c1a6c3b: feat(152-03): register R/122 in R/39, R/88 Section 15ah, SCRIPT_INDEX.md

## Self-Check: PASSED
