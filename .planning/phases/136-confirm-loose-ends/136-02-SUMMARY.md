---
phase: 136-confirm-loose-ends
plan: "02"
subsystem: config / loader
tags: [date-validation, config, requirements, confirm-02]
dependency_graph:
  requires: [136-01]
  provides: []
  affects: [R/00_config.R, R/01_load_pcornet.R, .planning/REQUIREMENTS.md]
tech_stack:
  added: []
  patterns: [investigative grep before config change, Branch B documentation pattern]
key_files:
  created: []
  modified:
    - R/00_config.R
    - R/01_load_pcornet.R
    - .planning/REQUIREMENTS.md
decisions:
  - "Branch B applied: _VALID flags are informational only (message() counts), never used as filter predicates — no Apr-Sep 2025 records were being dropped"
  - "date_range_max left at 2025-03-31 (unchanged) per D-06; comment updated to reflect true intent (sentinel-date guard, not extract cutoff enforcement)"
metrics:
  duration: "~10 minutes"
  completed: "2026-07-25"
  tasks: 2
  files: 3
---

# Phase 136 Plan 02: Investigate date_range_max and Resolve CONFIRM Entries Summary

`_VALID` flags confirmed informational-only across all R/ scripts; no Apr–Sep 2025 records dropped by the `date_range_max = 2025-03-31` bound. Config value left unchanged with updated comment; explanatory comment added to R/01 validation block; CONFIRM-01 and CONFIRM-02 both resolved in REQUIREMENTS.md.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Investigate _VALID flag usage; update config comment | d848323 | R/00_config.R, R/01_load_pcornet.R |
| 2 | Add R/01 explanatory comment; resolve CONFIRM entries | d067a0f | .planning/REQUIREMENTS.md |

## Investigation Result: Branch B

**Question:** Does `CONFIG$analysis$date_range_max = as.Date("2025-03-31")` cause valid Apr–Sep 2025 encounter or death records to be silently dropped?

**Answer: No. Branch B applies.**

### Evidence

Grep of all `_VALID` column references across `R/` (excluding R/01 itself):

| File | Usage | Data loss? |
|------|-------|-----------|
| R/02_harmonize_payer.R | Comment only ("where _VALID flags may not propagate") | No |
| R/14_build_cohort.R | Comment only (same safety-net pattern) | No |
| R/63_value_audit.R | Comment only ("Logical (_VALID flags): converted to character frequency table") | No |
| R/90_diagnostics.R | Excludes `_VALID` columns from column loops; summarizes counts via `str_detect("_VALID$")` — reporting only | No |
| R/91_data_quality_summary.R | Reads `_VALID` column values for summary table; excludes them from date-column lists | No |
| R/99_claude_diagnostics.R | `if (grepl("_VALID$", col)) next` — skips the flag columns during iteration | No |

No script outside R/01 uses `_VALID == FALSE` as a filter predicate, in a `filter()`, `subset()`, `[...]`, or `case_when()` that drops rows. The `_VALID` columns are produced by R/01's validation loop solely for the `message()` count log:

```r
n_invalid <- sum(!df[[valid_col_name]], na.rm = TRUE)
if (n_invalid > 0) {
  message(glue("  Validation: {n_invalid} invalid {dcol} values flagged ..."))
}
```

Downstream scripts apply their own independent sentinel-date guards (e.g., `year(ADMIT_DATE) == 1900` in R/02 and R/14) that do not rely on the `_VALID` flag.

### Branch Applied: D-06 (leave value unchanged, update comment)

**R/00_config.R** — comment updated from:
```
# Upper bound is end of data collection period
```
to:
```
# Upper bound catches future-year sentinel dates only; does not filter records
# (validation flag is informational). Data-source cutoff enforced by the extract.
```

**R/01_load_pcornet.R** — added 5-line explanatory comment block before the date validation loop clarifying intent of both bounds and citing CONFIRM-02.

## REQUIREMENTS.md Updates

Both CONFIRM entries updated to `[x]` with one-line finding notes:

- **CONFIRM-01** (already `[x]` from plan 01): finding note added — `clean_multi_value()`/`union_field()` in R/utils/utils_format.R; `suppress_small()` inline in R/106.
- **CONFIRM-02**: changed from `[ ]` to `[x]`; Branch B finding note appended.
- Tracking table: `CONFIRM-02 | Phase 136 | Pending` → `Complete`.

## Deviations from Plan

None — plan executed exactly as written. Branch B was determined by evidence (grep results); all actions matched the Branch B path specified in the plan.

## Known Stubs

None.

## Self-Check: PASSED

- `grep "date_range_max" R/00_config.R` → unchanged value `as.Date("2025-03-31")` with new comment: CONFIRMED
- `grep "CONFIRM-02" R/01_load_pcornet.R` → present: CONFIRMED
- `grep "data-source cutoff" R/01_load_pcornet.R` → present: CONFIRMED
- `grep "\[x\].*CONFIRM-01" .planning/REQUIREMENTS.md` → present: CONFIRMED
- `grep "\[x\].*CONFIRM-02" .planning/REQUIREMENTS.md` → present: CONFIRMED
- `grep "CONFIRM-02.*Complete" .planning/REQUIREMENTS.md` → present: CONFIRMED
- Commits d848323 and d067a0f exist: CONFIRMED
