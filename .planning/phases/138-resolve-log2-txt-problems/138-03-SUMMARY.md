---
phase: 138
plan: "03"
subsystem: death-validation
tags: [bug-fix, duckdb, column-rename, r53]
dependency_graph:
  requires: []
  provides: [validated_death_dates.rds (refreshed)]
  affects: [R/29, R/59, R/51]
tech_stack:
  added: []
  patterns: [dplyr select without rename when column already has target name]
key_files:
  modified: [R/53_death_date_validation.R]
  created: []
decisions:
  - "select(ID = PATID, ...) -> select(ID, ...) because R/01 renames PATID to ID at load time; the rename attempt in R/53 was the entire bug"
metrics:
  duration: "5m"
  completed: "2026-07-26"
  tasks_completed: 1
  files_modified: 1
---

# Phase 138 Plan 03: Fix R/53 PATID Column Bug Summary

**One-liner:** Removed erroneous `ID = PATID` rename in R/53's DEMOGRAPHIC select — DuckDB tables use `ID` (renamed at load time in R/01), so `PATID` never existed in the table.

## What Was Done

`R/53_death_date_validation.R` line 209 attempted `select(ID = PATID, BIRTH_DATE)`, which tries to find a column named `PATID` and rename it to `ID`. Because `R/01_load_pcornet.R` already renames the column to `ID` at load time, `PATID` does not exist in the DuckDB DEMOGRAPHIC table. The select call fails with a column-not-found error, preventing `validated_death_dates.rds` from being written.

Fix: changed to `select(ID, BIRTH_DATE)` — no rename needed, the column is already named `ID`.

## Tasks

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Fix DEMOGRAPHIC select in R/53 | 38f89b8 | R/53_death_date_validation.R |

## Verification

- `= PATID` grep in R/53: zero matches (confirmed)
- `select(ID, BIRTH_DATE)` at line 209: confirmed present

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Self-Check: PASSED

- R/53_death_date_validation.R modified: confirmed
- Commit 38f89b8: confirmed
