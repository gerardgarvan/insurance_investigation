---
phase: 134
plan: "01"
subsystem: ingest
tags: [duckdb, ingest, integrity, INGEST-01]
dependency_graph:
  requires: []
  provides: [hardened-R03-ingest]
  affects: [R/03_duckdb_ingest.R]
tech_stack:
  added: []
  patterns: [stop-on-missing-rds, setdiff-assertion-before-atomic-swap, real-count-summary]
key_files:
  modified: [R/03_duckdb_ingest.R]
decisions:
  - "stop() instead of next for missing RDS -- error propagates to outer tryCatch, triggers .tmp cleanup, no silent partial ingest"
  - "setdiff assertion placed after round-trip verification and before TRUE signal -- catches set mismatches before atomic swap"
  - "n_passed derived from tables_ingested length (actual) not TABLES_TO_INGEST length (expected) -- honest count"
metrics:
  duration: "< 5 minutes"
  completed: "2026-07-25"
  tasks: 3
  files: 1
requirements: [INGEST-01]
---

# Phase 134 Plan 01: R/03 Ingest Integrity Summary

**One-liner:** Hardened DuckDB ingest to abort loudly on missing RDS, assert exact table-set match before atomic swap, and report real pass counts instead of hardcoded ratio.

## What Was Done

Three honesty gaps in `R/03_duckdb_ingest.R` were fixed per INGEST-01:

1. **Missing RDS: skip to stop.** The `if (!file.exists(rds_path)) { next }` pattern was replaced with `stop(glue("RDS file not found for table {tbl_name}: {rds_path}"))`. Because this executes inside the outer `tryCatch` body, the error handler now fires: it disconnects from DuckDB, removes the `.tmp` file, and re-raises. A missing table can never silently produce a partial database.

2. **setdiff assertion before atomic swap.** After round-trip verification completes (and before `TRUE # signal success`), two `setdiff` calls check `missing_from_ingest` and `extra_in_ingest`. If either is non-empty, `stop()` aborts -- the `.tmp` is cleaned up and the canonical database is never promoted.

3. **Real summary counts.** The Section 9 summary line previously printed `{length(TABLES_TO_INGEST)}/{length(TABLES_TO_INGEST)}` -- always a perfect ratio regardless of what actually ran. It now derives `n_passed` from `length(tables_ingested)` (populated only for tables that wrote successfully and passed round-trip verification).

## Deviations from Plan

None -- plan executed exactly as written.

## Self-Check: PASSED

- grep -n 'SKIPPED: {tbl_name}' R/03_duckdb_ingest.R returns nothing (only "INGEST SKIPPED" variants remain for encoding-retry/inner-tryCatch warnings, unrelated to the missing-RDS path)
- grep -n 'setdiff(TABLES_TO_INGEST' R/03_duckdb_ingest.R returns line 321
- grep -n '}/{length(TABLES_TO_INGEST)}' R/03_duckdb_ingest.R returns only line 141 (progress counter [N/total]), not the summary line
- grep -n 'RDS file not found' R/03_duckdb_ingest.R returns line 138
- grep -n 'Verification:' R/03_duckdb_ingest.R returns line 390 with {n_passed}/{n_expected}
- Commit 172ffd3 exists
