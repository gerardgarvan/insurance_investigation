# Quick Task 260709-jhw — R/27 self-bootstrap DuckDB connection — PLAN

**Mode:** quick (orchestrator-implemented; trivial 1-hunk edit)

## Problem
R/27 asserts `pcornet_con` exists in SECTION 0 (line ~46) but only opens it later
(line ~319). Running R/27 standalone in a fresh session → `Error: object 'pcornet_con'
not found`. Sibling DuckDB scripts (R/28-R/36) self-bootstrap at the top with
`USE_DUCKDB <- TRUE; open_pcornet_con()`.

## Task
Insert, after the two `source()` lines and before the SECTION 0 assert in
`R/27_drug_name_resolution.R`:
```r
USE_DUCKDB <- TRUE
if (!exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}
```
- Conditional open (guarded by `exists`) so a pipeline-established connection is reused,
  and a standalone session opens its own. `open_pcornet_con()` is idempotent regardless.
- Leave the existing `open_pcornet_con()` at ~line 319 as-is (harmless; matches R/28's
  double-open pattern).

## Constraints
- Modify ONLY R/27_drug_name_resolution.R. No data-logic changes. Run-order/consistency fix.
- No R/88 check (not a data-logic change).
- Structural verification only (Windows-local): grep bootstrap appears before SECTION 0 assert; parse if Rscript available.

## Acceptance
- `USE_DUCKDB <- TRUE` and `open_pcornet_con()` appear before `# SECTION 0: INPUT VALIDATION`.
- File parses.
