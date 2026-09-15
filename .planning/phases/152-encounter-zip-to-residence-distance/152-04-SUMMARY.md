---
phase: 152-encounter-zip-to-residence-distance
plan: "04"
subsystem: utils_address
tags: [duckdb, oom-fix, zip9, centroid, get_zip_centroid]
dependency_graph:
  requires: ["152-03"]
  provides: ["get_zip_centroid() ZIP9 DuckDB path"]
  affects: ["R/122_encounter_zip_to_residence_distance.R"]
tech_stack:
  added: []
  patterns: ["DuckDB read_csv filtered join (pushdown WHERE to CSV scanner)"]
key_files:
  modified:
    - R/utils/utils_address.R
decisions:
  - "DuckDB in-memory connection opened/queried/disconnected per call — no persistent connection"
  - "glue::glue() used (not glue_sql()) with manual gsub SQL-escaping since read_csv() is a DuckDB table function, not a parameterized query"
metrics:
  duration: "5 min"
  completed: "2026-09-15"
  tasks_completed: 1
  tasks_total: 1
  files_modified: 1
requirements_completed:
  - DIST-HELPERS
---

# Phase 152 Plan 04: Replace vroom full-load with DuckDB filtered read in get_zip_centroid() Summary

Replaced the memoized `vroom::vroom(bg_path)` full crosswalk load in `get_zip_centroid()`'s ZIP9 branch with a DuckDB `read_csv` filtered query that scans only the requested ZIP9 rows — eliminating the OOM risk from loading the 68M-row / ~3.5 GB crosswalk CSV into R memory on HiPerGator.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Replace vroom full-load with DuckDB filtered read | 4d67cba | R/utils/utils_address.R |

## What Was Built

The memoized vroom block (lines 856-906 pre-edit) in `get_zip_centroid()`'s `level == "zip9"` branch was removed and replaced with a DuckDB in-memory connection that issues a single `SELECT ... FROM read_csv(...) WHERE ZIP9 = '<zip_str>' LIMIT 1` query. The CSV file is never loaded whole — DuckDB's CSV scanner processes only the matching rows via pushdown filter.

Key implementation details:
- `duckdb::dbConnect(duckdb::duckdb(), dbdir = ":memory:")` opened per call
- `on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)` ensures cleanup even on error, matching R/122a's own pattern
- `safe_zip` and `bg_path_sql` are SQL-escaped via `gsub("'", "''", ...)` since `read_csv()` is a DuckDB table function (not a parameterized query)
- Error handler returns `NULL`, which the immediately-following `if (is.null(hit_bg))` catches and returns the `zip9_bg_absent` tibble
- `hit_bg` is now a `data.frame` (from `dbGetQuery`); downstream `if (nrow(hit_bg) > 0L)` and `hit_bg$INTPTLAT`/`hit_bg$INTPTLON` work identically for data.frame and tibble — no downstream changes needed
- The file-absent guard (lines 849-854) and hit/fallback branch (lines 908+) are untouched

## Verification

```
grep -c "vroom::vroom(bg_path" R/utils/utils_address.R  # => 0  PASS
grep -c "duckdb::dbConnect" R/utils/utils_address.R     # => 1  PASS
grep -c "zip9_bg_absent" R/utils/utils_address.R        # => 3  (2 in code + 1 in roxygen) PASS
grep -c "read_csv" R/utils/utils_address.R              # => 1  PASS
```

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- File exists: R/utils/utils_address.R ✓
- Commit exists: 4d67cba ✓
- `vroom::vroom(bg_path` count = 0 ✓
- `duckdb::dbConnect` count = 1 ✓
- `zip9_bg_absent` present in file-absent guard and DuckDB error handler ✓
- `read_csv` present ✓
- `on.exit` call present (1 real occurrence in code) ✓
- Lines 908+ (hit/fallback branch: `if (nrow(hit_bg) > 0L)`) untouched ✓
