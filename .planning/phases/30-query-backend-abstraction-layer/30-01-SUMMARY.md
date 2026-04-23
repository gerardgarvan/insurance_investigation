---
phase: 30-query-backend-abstraction-layer
plan: 01
subsystem: data-access-layer
tags: [duckdb, backend-abstraction, dual-mode, phase-30]
dependencies:
  requires: [29-02]  # DuckDB indexes from Phase 29
  provides: [get_pcornet_table, open_pcornet_con, close_pcornet_con, materialize]
  affects: [31-01, 31-02, 32-01, 32-02]  # All Phase 31-32 migrations depend on this layer
tech_stack:
  added: []
  patterns: [dispatcher-pattern, global-connection-singleton, lazy-evaluation-wrapper]
key_files:
  created: []
  modified:
    - R/00_config.R
    - R/utils_duckdb.R
    - R/01_load_pcornet.R
decisions:
  - USE_DUCKDB defaults to FALSE (RDS mode) for backward compatibility
  - pcornet_con stored as global singleton (not passed through call chains)
  - materialize() is pass-through no-op for tibbles (not just tbl_lazy)
  - TUMOR_REGISTRY_ALL created as SQL VIEW in DuckDB (not ingested as table)
  - DuckDB connection opened in 01_load_pcornet.R regardless of pcornet cache hit
metrics:
  duration_seconds: 141
  tasks_completed: 3
  commits: 3
  files_modified: 3
  tests_added: 0
completed: 2026-04-23
requirements: [DBAPI-01, DBAPI-02, DBAPI-03]
---

# Phase 30 Plan 01: Backend Abstraction Layer — SUMMARY

**One-liner:** Dual-backend dispatcher with USE_DUCKDB flag enabling transparent switching between RDS tibbles and DuckDB lazy queries via get_pcornet_table()

## What Was Built

Added a complete backend abstraction layer to R/utils_duckdb.R that allows downstream scripts to call `get_pcornet_table("DIAGNOSIS")` and receive a dplyr-pipeable object from either RDS or DuckDB backend, controlled by a single `USE_DUCKDB` flag in 00_config.R.

### Core Functions

1. **get_pcornet_table(table_name, con = NULL)** — Dispatcher function
   - RDS mode (USE_DUCKDB = FALSE): returns in-memory tibble from global `pcornet$TABLE_NAME`
   - DuckDB mode (USE_DUCKDB = TRUE): returns tbl_dbi lazy query object via `dplyr::tbl()`
   - No signature changes needed in downstream code (both return dplyr-compatible objects)

2. **open_pcornet_con(db_path, read_only = TRUE)** — Connection manager
   - Opens read-only DBI connection to DuckDB file
   - Creates TUMOR_REGISTRY_ALL SQL view (UNION ALL of TR1 + TR2 + TR3)
   - Stores connection as global `pcornet_con` (singleton pattern)
   - Warns and reopens if connection already exists

3. **close_pcornet_con()** — Connection cleanup
   - Disconnects and removes global `pcornet_con`
   - Calls `shutdown = TRUE` for clean DuckDB release

4. **materialize(lazy_tbl)** — Lazy query execution
   - Wraps `dplyr::collect()` for consistent API
   - Pass-through no-op for tibbles/data.frames (not just tbl_lazy)
   - Executes lazy DuckDB queries and returns in-memory tibbles

### Configuration

- **USE_DUCKDB flag** added to R/00_config.R (line 87)
  - Defaults to FALSE (RDS mode) for backward compatibility
  - Detailed comment block explains FALSE = RDS mode, TRUE = DuckDB mode
  - Placed after CONFIG$cache block, before PCORNET_TABLES section

- **Auto-source utils_duckdb.R** added to R/00_config.R (line 894)
  - Ensures all 4 backend functions available to downstream scripts
  - Placed after existing utils (dates, attrition, icd, snapshot)

### Pipeline Integration

- **DuckDB auto-setup** added to R/01_load_pcornet.R (lines 688-718)
  - Runs AFTER pcornet loading block (outside if/else guard)
  - Checks USE_DUCKDB flag, verifies DuckDB file exists
  - Graceful fallback to RDS mode with warning if file missing
  - Calls `open_pcornet_con()` which creates TUMOR_REGISTRY_ALL view
  - Logs backend mode (RDS vs DuckDB) for user visibility

## Deviations from Plan

None — plan executed exactly as written.

## Key Decisions

### 1. USE_DUCKDB defaults to FALSE (RDS mode)

**Context:** Plan specified default FALSE for backward compatibility.

**Decision:** Set USE_DUCKDB <- FALSE in 00_config.R. All existing pipeline behavior preserved. Phase 31 will migrate cohort scripts, Phase 32 will flip default to TRUE.

**Rationale:** Ensures no breaking changes. Users opt-in to DuckDB mode explicitly.

### 2. pcornet_con as global singleton

**Context:** Plan specified global environment storage (D-04).

**Decision:** Store connection as `pcornet_con` in .GlobalEnv via `assign()`. get_pcornet_table() accesses via `get("pcornet_con", envir = .GlobalEnv)`.

**Rationale:** Avoids threading connection object through every function call. Matches existing pattern of global `pcornet` list. Simplifies migration in Phase 31.

### 3. materialize() is pass-through for tibbles

**Context:** Plan specified wrapper around dplyr::collect() for consistent API.

**Decision:** Check `inherits(lazy_tbl, "tbl_lazy")`. If TRUE, call `dplyr::collect()`. If FALSE, return object unchanged (no-op).

**Rationale:** Allows downstream code to call `materialize()` unconditionally in both RDS and DuckDB modes. In RDS mode, tibbles pass through unchanged. In DuckDB mode, lazy queries execute.

### 4. TUMOR_REGISTRY_ALL as SQL VIEW (not ingested table)

**Context:** Plan specified CREATE VIEW in open_pcornet_con() (D-03).

**Decision:** Use `CREATE VIEW IF NOT EXISTS TUMOR_REGISTRY_ALL AS SELECT * FROM TR1 UNION ALL ...` in open_pcornet_con(). No separate ingest step.

**Rationale:** View is derived data (bind_rows equivalent in SQL). Saves disk space and ingest time. IF NOT EXISTS prevents errors on reconnection. Matches Phase 29 decision to exclude TUMOR_REGISTRY_ALL from ingest.

### 5. DuckDB setup runs regardless of pcornet cache hit

**Context:** Plan specified placement OUTSIDE pcornet loading guard (D-05).

**Decision:** Place DuckDB connection block after line 685 (after the pcornet loading if/else closes), before "End of script" comment.

**Rationale:** Ensures connection opens even when pcornet list loads from cache (not freshly parsed). DuckDB backend needs connection regardless of RDS cache state.

## Implementation Notes

### Library Imports

Added to R/utils_duckdb.R (lines 14-15):
- `library(duckdb)` — for duckdb::duckdb() driver
- `library(dplyr)` — for dplyr::tbl() and dplyr::collect()

Existing imports preserved:
- `library(DBI)` — for dbConnect, dbExecute, dbDisconnect
- `library(glue)` — for logging messages

### Roxygen Documentation

All 4 new functions include roxygen-style documentation:
- `@param` tags for all parameters with type and description
- `@return` tags describing return value and type
- Plain-language descriptions of RDS vs DuckDB behavior
- References to plan decision IDs (D-01, D-02, D-03, D-04, D-05) in comments

### Error Handling

**get_pcornet_table():**
- RDS mode: Stops with helpful message if `pcornet` list not found or table missing
- DuckDB mode: Stops with helpful message if `pcornet_con` not found

**open_pcornet_con():**
- Warns and closes existing connection if already open (prevents resource leaks)
- Stores connection in global environment with `assign()`
- Returns connection invisibly (allows chaining but doesn't clutter console)

**close_pcornet_con():**
- Warns if no connection exists (no-op, returns invisibly)
- Removes `pcornet_con` from global environment after disconnect

**01_load_pcornet.R:**
- Checks if DuckDB file exists before opening connection
- Falls back to RDS mode with warning if file missing (sets `USE_DUCKDB <<- FALSE`)
- Logs which backend mode is active (RDS vs DuckDB)

## Testing Strategy (Deferred to Phase 31)

This plan builds the abstraction layer. Testing will occur in Phase 31 during cohort migration:
1. Parity testing: Compare RDS vs DuckDB outputs for each filter step
2. Snapshot comparisons: Verify DuckDB results match Phase 16 RDS snapshots
3. Lazy evaluation testing: Confirm tbl_dbi objects are lazy (no premature materialization)
4. TUMOR_REGISTRY_ALL view testing: Verify view combines TR1/TR2/TR3 correctly

## Known Stubs

None. All 4 functions are fully implemented with complete logic paths.

## Completion Checklist

- [x] All 3 tasks executed
- [x] Each task committed individually (21384a1, 911856a, ef98192)
- [x] No deviations from plan
- [x] SUMMARY.md created
- [x] Self-check performed (see below)

## Self-Check: PASSED

All claimed artifacts verified to exist:

**R/00_config.R:**
- `USE_DUCKDB <- FALSE` exists at line 87 ✓
- `source("R/utils_duckdb.R")` exists at line 894 ✓
- Comment block explains RDS vs DuckDB modes ✓

**R/utils_duckdb.R:**
- `library(duckdb)` and `library(dplyr)` imports exist (lines 14-15) ✓
- `open_pcornet_con <- function(...)` exists at line 112 ✓
- `close_pcornet_con <- function()` exists at line 148 ✓
- `get_pcornet_table <- function(...)` exists at line 177 ✓
- `materialize <- function(...)` exists at line 212 ✓
- `CREATE VIEW IF NOT EXISTS TUMOR_REGISTRY_ALL` exists (line 127) ✓
- `assign("pcornet_con", con, envir = .GlobalEnv)` exists (line 135) ✓
- `read_only = read_only` in dbConnect call (line 121) ✓
- Existing `verify_duckdb_roundtrip()` preserved ✓

**R/01_load_pcornet.R:**
- `if (exists("USE_DUCKDB") && USE_DUCKDB)` block exists at line 699 ✓
- `open_pcornet_con(db_path = duckdb_path, read_only = TRUE)` call exists (line 709) ✓
- Fallback logic with warning if DuckDB file missing (lines 702-707) ✓
- `[DuckDB] Backend enabled` message exists (lines 710-714) ✓
- `[RDS] Backend active` message exists (line 717) ✓
- DuckDB block placed OUTSIDE pcornet loading guard (after line 685) ✓

**Commits:**
- 21384a1 (Task 1: USE_DUCKDB flag and utils_duckdb.R sourcing) ✓
- 911856a (Task 2: backend abstraction functions) ✓
- ef98192 (Task 3: DuckDB connection setup) ✓

All claimed files exist:
```bash
$ ls -1 R/00_config.R R/utils_duckdb.R R/01_load_pcornet.R
R/00_config.R
R/01_load_pcornet.R
R/utils_duckdb.R
```

All commits exist:
```bash
$ git log --oneline --all | grep -E "21384a1|911856a|ef98192"
ef98192 feat(30-01): add DuckDB connection setup to 01_load_pcornet.R
911856a feat(30-01): add backend abstraction functions to utils_duckdb.R
21384a1 feat(30-01): add USE_DUCKDB flag and source utils_duckdb.R
```
