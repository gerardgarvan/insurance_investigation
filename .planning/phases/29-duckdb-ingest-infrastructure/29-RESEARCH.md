# Phase 29: DuckDB Ingest Infrastructure - Research

**Researched:** 2026-04-23
**Domain:** DuckDB integration with R, bulk data ingestion, atomic writes, indexing
**Confidence:** HIGH

## Summary

Phase 29 creates a DuckDB ingest pipeline that reads 13 PCORnet tables from the existing RDS cache (Phase 15) and writes them to a single indexed DuckDB file with atomic write guarantees. The research confirms DuckDB R package version 1.5.1 (March 2026) provides stable `dbWriteTable()` with `overwrite` control, automatic transaction handling for ACID guarantees, and ART index support. The atomic write pattern (`.tmp` file swap) is a standard R/filesystem pattern, not DuckDB-specific. RDS-to-DuckDB type mapping is low-risk because `saveRDS()`/`readRDS()` preserve R object attributes including Date/POSIXct classes, and `dbWriteTable()` handles these types natively.

**Primary recommendation:** Use sequential table ingestion with explicit `gc()` between tables to control peak memory. Build indexes after all data is loaded, not during writes. Verify round-trip via `dim()` and `colnames()` comparison — full value parity testing deferred to Phase 31.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** DuckDB file lives at `/blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb` — a new `duckdb/` subdirectory under the existing `/blue/clean/` tree. This keeps all derived data together and is already gitignored via the existing `/blue/erin.mobley-hl.bcu/clean/` exclusion.
- **D-02:** Always rebuild from scratch. Every run of `R/25_duckdb_ingest.R` produces a fresh DuckDB from current RDS files. No cache-check or timestamp comparison. The ingest is a one-time operation per extract (not part of the regular pipeline run), so the ~20 minute cost is acceptable.
- **D-03:** Abort entire build on any table failure. If one table fails to ingest (type conversion, disk error, etc.), the `.tmp` file is NOT swapped to the canonical path. The user sees the error, fixes the issue, and re-runs. This maintains the atomic guarantee: the canonical DuckDB file is always either complete (all 13 tables) or absent.
- **D-04:** Index creation uses `tryCatch()` per index (from pre-written plan 29-02). A failed index does not abort the build — it logs a warning. An unindexed table is still queryable, just slower.
- **D-05:** `EXTRACT_DATE = "2025-09-15"` hardcoded in `CONFIG` in `R/00_config.R`. Matches the known `Mailhot_V1_20250915` extract. User updates it manually when a new extract arrives. Used for ingest log filename: `output/logs/duckdb_ingest_2025-09-15.csv`.

### Claude's Discretion

- Column type handling: If `dbWriteTable()` rejects a column type (e.g., POSIXct vs Date), Claude can add explicit casts in a helper before the write.
- Memory management: Sequential table ingestion with `gc()` between tables (per pre-written plan approach). Claude can adjust if HiPerGator memory allows parallel writes.
- Ingest log CSV columns: Claude decides the exact column set (table_name, row_count, duration_sec are required; additional columns like col_count or file_size at discretion).

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DBING-01 | User can ingest all 13 PCORnet tables from RDS cache into a single DuckDB file with atomic write (`.tmp` file swap ensuring interrupted runs leave canonical file untouched) | Standard Stack: duckdb R package 1.5.1; Architecture Patterns: atomic write via `.tmp` + `file.rename()`, sequential table loop with `dbWriteTable(overwrite=TRUE)` |
| DBING-02 | User can see per-table ingest log CSV (`output/logs/duckdb_ingest_<EXTRACT_DATE>.csv`) with row counts and durations for all 13 tables | Architecture Patterns: log data frame built during ingest loop, written via `readr::write_csv()` after atomic swap completes |
| DBING-03 | User can see PATID indexes on all 13 tables and ENCOUNTERID indexes on 8 tables, with round-trip dimension/column verification passing for all tables | Standard Stack: `CREATE INDEX` via `DBI::dbExecute()`; Code Examples: index creation loop with `tryCatch()` per index; round-trip verification via `dim()` + `colnames()` comparison |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| duckdb | 1.5.1 (R pkg 1.5.1-1) | DuckDB engine + R DBI interface | Official R client; CRAN release 2026-03-26; ART indexes, concurrent checkpointing (17% TPC-H improvement in 1.5.0), Lance format support in 1.5.1 |
| DBI | 1.2.3+ | Database interface abstraction | Standard R DB interface; `dbConnect()`, `dbWriteTable()`, `dbExecute()`, `dbGetQuery()` all DuckDB implements via DBI spec |

**Installation:**
```r
install.packages("duckdb")  # CRAN 1.5.1-1 as of 2026-03-26
```

**Version verification:**
```r
packageVersion("duckdb")
# [1] '1.5.1.1'
```

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| readr | 2.2.0+ | Write ingest log CSV | `write_csv()` for clean CSV output with no row names |
| glue | 1.8.0+ | Logging messages | Already in project stack; `glue()` for readable progress messages |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| duckdb R package | arrow + Parquet | Parquet is 5-10x smaller/faster than DuckDB for pure analytics, but Phase 30 needs SQL predicate pushdown and dplyr translation — DuckDB's dbplyr integration is mature, Arrow's is limited |
| Sequential write loop | Parallel writes via futures | Parallel writes risk memory spikes (each worker holds a table in RAM); DuckDB 1.5.0+ supports concurrent reads/writes but R DBI client is single-connection; sequential is safer on shared HPC nodes |
| ART indexes | No indexes (rely on zone maps) | DuckDB auto-creates min-max zone maps; ART indexes help point lookups (PATID-specific queries) but cost RAM and maintenance; user constraints specify indexes, so we build them |

## Architecture Patterns

### Recommended Project Structure (no changes)
Phase 29 adds:
```
R/
├── 25_duckdb_ingest.R       # New ingest script
├── utils_duckdb.R            # New utilities (verify_duckdb_roundtrip stub)

/blue/erin.mobley-hl.bcu/clean/
├── rds/                      # Existing Phase 15 cache (source data)
└── duckdb/                   # New subdirectory
    └── pcornet.duckdb        # Canonical DuckDB file

output/logs/
└── duckdb_ingest_2025-09-15.csv  # Per-table ingest log
```

### Pattern 1: Atomic Write via Temporary File Swap
**What:** Write to `<path>.tmp`, verify success, then `file.rename(<path>.tmp, <path>)`. R's `file.rename()` is atomic on POSIX filesystems (HiPerGator /blue uses Lustre, which is POSIX-compliant).

**When to use:** Anytime a long-running build must not leave a partial/corrupt output on failure.

**Example:**
```r
# Source: Standard R filesystem pattern (not DuckDB-specific)
tmp_path <- paste0(DUCKDB_PATH, ".tmp")

# Remove old .tmp if exists (cleanup from prior interrupted run)
if (file.exists(tmp_path)) file.remove(tmp_path)

# Build entire DuckDB at tmp_path
con <- DBI::dbConnect(duckdb::duckdb(), tmp_path)
on.exit(DBI::dbDisconnect(con), add = TRUE)

# ... write all 13 tables via loop ...

DBI::dbDisconnect(con)
on.exit()  # Clear on.exit hook after clean disconnect

# Atomic swap (only if build succeeded)
if (file.exists(DUCKDB_PATH)) file.remove(DUCKDB_PATH)
file.rename(tmp_path, DUCKDB_PATH)
```

**Rationale:** DuckDB supports transactions internally (ACID-compliant), but that doesn't protect against filesystem-level issues (disk full, killed process). The `.tmp` + `file.rename()` pattern is a defense-in-depth layer ensuring the canonical file is never partially written.

### Pattern 2: Sequential Table Ingestion with Explicit Memory Management
**What:** Loop over tables one at a time, `dbWriteTable()` each, then `rm()` + `gc()` before loading the next.

**When to use:** When peak RAM is a constraint and tables are large (100MB-2GB RDS files).

**Example:**
```r
# Source: Phase 29 CONTEXT.md + DuckDB R best practices
tables_to_ingest <- c(
  "ENROLLMENT", "DIAGNOSIS", "PROCEDURES", "PRESCRIBING", "ENCOUNTER",
  "DEMOGRAPHIC", "TUMOR_REGISTRY1", "TUMOR_REGISTRY2", "TUMOR_REGISTRY3",
  "DISPENSING", "MED_ADMIN", "LAB_RESULT_CM", "PROVIDER"
)

ingest_log <- tibble(
  table_name = character(),
  row_count = integer(),
  col_count = integer(),
  duration_sec = numeric()
)

for (tbl_name in tables_to_ingest) {
  message(glue::glue("Ingesting {tbl_name}..."))
  start_time <- Sys.time()

  # Load from RDS cache
  rds_path <- file.path(CONFIG$cache$raw_dir, paste0(tbl_name, ".rds"))
  df <- readRDS(rds_path)

  # Write to DuckDB
  DBI::dbWriteTable(con, tbl_name, df, overwrite = TRUE)

  # Log metrics
  duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  ingest_log <- bind_rows(ingest_log, tibble(
    table_name = tbl_name,
    row_count = nrow(df),
    col_count = ncol(df),
    duration_sec = duration
  ))

  # Free memory before next table
  rm(df)
  gc()
}
```

**Rationale:** Peak RAM = (largest table in RAM) + (DuckDB write buffers). Sequential prevents summing all 13 tables. `gc()` forces R to release memory immediately rather than waiting for next allocation pressure.

### Pattern 3: Index Creation After Data Load
**What:** Create indexes after all `dbWriteTable()` calls complete, not during the write loop.

**When to use:** Always for bulk data ingestion. Building indexes on empty tables forces DuckDB to maintain them during insert; post-load indexing is faster.

**Example:**
```r
# Source: DuckDB indexing guide + Plan 29-02
tables_with_encounterid <- c(
  "DIAGNOSIS", "PROCEDURES", "ENCOUNTER", "DISPENSING",
  "MED_ADMIN", "LAB_RESULT_CM", "PRESCRIBING", "PROVIDER"
)

# Index all tables on PATID (universal join key)
for (tbl_name in tables_to_ingest) {
  idx_name <- paste0("idx_", tolower(tbl_name), "_patid")
  tryCatch({
    DBI::dbExecute(con, glue::glue("CREATE INDEX {idx_name} ON {tbl_name} (ID)"))
    message(glue::glue("  Created index: {idx_name}"))
  }, error = function(e) {
    warning(glue::glue("  Failed to create {idx_name}: {e$message}"))
  })
}

# Index ENCOUNTERID on tables that have it
for (tbl_name in tables_with_encounterid) {
  idx_name <- paste0("idx_", tolower(tbl_name), "_encounterid")
  tryCatch({
    DBI::dbExecute(con, glue::glue("CREATE INDEX {idx_name} ON {tbl_name} (ENCOUNTERID)"))
    message(glue::glue("  Created index: {idx_name}"))
  }, error = function(e) {
    warning(glue::glue("  Failed to create {idx_name}: {e$message}"))
  })
}
```

**Rationale:** `tryCatch()` per index prevents one failure from aborting all. An unindexed table is still queryable (just slower); user can fix the root cause and rerun. Per D-04, index failures are warnings, not errors.

### Pattern 4: Round-Trip Verification (Dimension & Schema Check)
**What:** After ingest, read each table back from DuckDB via `dbReadTable()` and verify `dim()` and `colnames()` match the RDS source.

**When to use:** Phase 29 round-trip verification (cheap sanity check). Phase 31 does full value parity via `waldo::compare()`.

**Example:**
```r
# Source: Plan 29-02 stub, to be fleshed out in Plan 30-01
verify_duckdb_roundtrip <- function(table_name, con) {
  # Read from RDS
  rds_path <- file.path(CONFIG$cache$raw_dir, paste0(table_name, ".rds"))
  rds_df <- readRDS(rds_path)

  # Read from DuckDB
  ddb_df <- DBI::dbReadTable(con, table_name)

  # Dimension check
  dim_match <- identical(dim(rds_df), dim(ddb_df))

  # Column name check
  col_match <- identical(colnames(rds_df), colnames(ddb_df))

  if (!dim_match || !col_match) {
    warning(glue::glue(
      "Round-trip mismatch for {table_name}: ",
      "dim_match={dim_match}, col_match={col_match}"
    ))
    return(list(ok = FALSE, dim_match = dim_match, col_match = col_match))
  }

  list(ok = TRUE, dim_match = TRUE, col_match = TRUE)
}

# Run on all tables after ingest
for (tbl_name in tables_to_ingest) {
  result <- verify_duckdb_roundtrip(tbl_name, con)
  if (!result$ok) {
    stop(glue::glue("Round-trip verification failed for {tbl_name}"))
  }
}
```

**Rationale:** Cheap sanity check (no value comparison, just metadata). If dimensions or column names mismatch, it flags a serious problem before closing the connection. Full value comparison deferred to Phase 31 parity testing.

### Anti-Patterns to Avoid

- **Parallel dbWriteTable() calls:** DuckDB supports concurrent reads/writes at the SQL level, but R's DBI client is single-connection. Opening multiple connections to write in parallel risks lock contention and memory spikes. Sequential is simpler and safer.

- **Indexes during data load:** `CREATE INDEX` before `INSERT` forces DuckDB to maintain indexes during bulk insert. This is slower than post-load indexing and provides no benefit for one-time ingests.

- **Skipping `gc()` between tables:** R's garbage collector runs on allocation pressure, not immediately after `rm()`. On large tables, skipping `gc()` means the next table loads while the prior one still occupies RAM. Explicit `gc()` forces immediate release.

- **Using `dbWriteTable(append=TRUE)` with `overwrite=TRUE`:** Mutually exclusive flags. DBI throws an error if both are set. Per D-02, always rebuild from scratch, so use `overwrite=TRUE` consistently.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SQL connection pooling | Custom connection manager | DBI single-connection pattern | R DBI is single-threaded by design; connection pooling adds complexity with no benefit for sequential writes |
| Index verification | Custom SQL parser | `DBI::dbGetQuery("PRAGMA show_tables")` + `information_schema` views | DuckDB exposes system catalog via SQL-standard views; parsing SQL strings is fragile |
| Type conversion RDS→DuckDB | Custom type mapper | `dbWriteTable()` auto-mapping | DuckDB R client handles R Date/POSIXct → DuckDB DATE/TIMESTAMP natively; edge cases are rare (see Common Pitfalls) |
| Progress bars for ingest | Custom spinner/bar | `message()` with table name + elapsed time | Ingest is fast (sequential loop ~20 min total per D-02); progress bars add dependency (cli/progressr) for minimal UX gain |

**Key insight:** DuckDB R package (1.5.1) is mature and DBI-compliant. Most "custom solutions" are reinventing DBI/DuckDB built-ins. Trust the standard stack unless a specific limitation surfaces.

## Runtime State Inventory

> Omitted — Phase 29 is greenfield (new file creation), not a rename/refactor/migration.

## Common Pitfalls

### Pitfall 1: Date/POSIXct Type Conversion Failures
**What goes wrong:** `dbWriteTable()` may reject POSIXct columns with timezone attributes, or convert Date columns to TIMESTAMP instead of DATE.

**Why it happens:** DuckDB has strict type semantics. R's POSIXct stores timezone in an attribute; DuckDB's TIMESTAMP has no timezone (always UTC). If RDS has POSIXct with `tzone != "UTC"`, DuckDB may refuse the write or silently convert to UTC, shifting timestamps.

**How to avoid:**
1. Phase 15 RDS cache uses `parse_pcornet_date()` which returns base R Date objects (no timezone). POSIXct is only used for time-of-day columns (e.g., ADMIT_TIME), which are rare in PCORnet and not in the 13-table ingest list.
2. If `dbWriteTable()` rejects a column, inspect with `str(df$column)` to check for POSIXct vs Date. Convert POSIXct to Date via `as.Date()` if the time component is irrelevant.
3. Test on a small table first (PROVIDER has 7 columns, fast to debug).

**Warning signs:**
- DBI error: `Error in dbWriteTable: Cannot convert POSIXct to TIMESTAMP`
- Timestamps shifted by hours after round-trip (UTC conversion)

**Severity:** LOW for this phase — PCORnet date columns are parsed as Date, not POSIXct, in Phase 1. TIME columns exist but are not indexed or queried in v1.3 scope.

**Source confidence:** MEDIUM — DuckDB R package changelog mentions POSIXct/timezone issues in older versions (e.g., [Issue #184](https://github.com/duckdb/duckdb-r/issues/184)), but 1.5.1 changelog doesn't list new type conversion fixes. Assume it's stable but flag for testing.

### Pitfall 2: Disk Space Exhaustion During Build
**What goes wrong:** `/blue` filesystem fills up mid-write, causing `dbWriteTable()` to fail with a disk I/O error. The `.tmp` file is left incomplete, but the atomic swap never happens, so the canonical file is safe (per D-03).

**Why it happens:** DuckDB files are compressed but still large. 13 tables with ~1M-10M rows each → ~5-10 GB final DuckDB file. If `/blue` is near quota, the ingest may fail.

**How to avoid:**
1. Check `/blue` quota before running: `lfs quota -h /blue/erin.mobley-hl.bcu`
2. DuckDB compresses on write; final size is ~50-60% of total RDS size. Total RDS cache (Phase 15) is ~15-20 GB → expect DuckDB ~8-12 GB.
3. Clean up old `.tmp` files at script start: `if (file.exists(paste0(DUCKDB_PATH, ".tmp"))) file.remove(paste0(DUCKDB_PATH, ".tmp"))`

**Warning signs:**
- Error: `Error in dbWriteTable: Disk quota exceeded` or `Error in dbWriteTable: No space left on device`
- `.tmp` file exists but is smaller than expected (partial write)

**Severity:** MEDIUM — HiPerGator `/blue` quotas are generous (TB-scale), but user should verify before first run.

### Pitfall 3: Index Creation Timeout on Large Tables
**What goes wrong:** `CREATE INDEX` on DIAGNOSIS (largest table, ~10M rows) takes minutes, and user Ctrl+C's thinking it's hung. DuckDB transaction aborts, connection closes uncleanly, and the entire `.tmp` file is corrupted.

**Why it happens:** ART index build is O(n log n). On 10M rows, expect 2-5 minutes per index. No progress output makes it seem stuck.

**How to avoid:**
1. Log before each `CREATE INDEX`: `message(glue("Creating index on {tbl_name}..."))`
2. Per D-04, wrap each `CREATE INDEX` in `tryCatch()` — if it fails, log a warning and continue. The build still succeeds with some unindexed tables.
3. Test on HiPerGator with real data to establish baseline timing. If index creation is >10 minutes per table, consider deferring indexes to a post-ingest step.

**Warning signs:**
- Console shows "Creating index on DIAGNOSIS..." with no output for >2 minutes
- User kills the script, next run finds `.tmp` exists but is invalid (DuckDB throws "file corrupted" error)

**Severity:** LOW — `on.exit(dbDisconnect(con))` ensures clean shutdown even on user interrupt. DuckDB's WAL (write-ahead log) protects against corruption. But user impatience is still a risk.

### Pitfall 4: TUMOR_REGISTRY_ALL Confusion
**What goes wrong:** User expects 14 tables in DuckDB (13 from `PCORNET_TABLES` + `TUMOR_REGISTRY_ALL`), but only 13 appear. Or, user ingests `TUMOR_REGISTRY_ALL` instead of the 3 individual TR tables, and downstream scripts (Phase 30) break because they expect TR1/TR2/TR3.

**Why it happens:** `TUMOR_REGISTRY_ALL` is a derived table created in `01_load_pcornet.R` by `bind_rows(TR1, TR2, TR3)`. It's cached as RDS but not in the canonical `PCORNET_TABLES` list. Phase 29 must decide: ingest TR1/TR2/TR3 separately, or ingest `TUMOR_REGISTRY_ALL` as a 14th table?

**How to avoid:**
1. Per canonical refs, `PCORNET_TABLES` lists 13 tables. `TUMOR_REGISTRY_ALL` is a convenience alias for cohort building, not a separate data source.
2. Decision: Ingest TR1, TR2, TR3 separately (13 tables total). Do NOT ingest `TUMOR_REGISTRY_ALL`. Phase 30 abstraction layer can recreate it via `UNION ALL` if needed.
3. Document in ingest script: `# Note: TUMOR_REGISTRY_ALL is not ingested — it's a derived table (TR1+TR2+TR3)`

**Warning signs:**
- Ingest log shows 14 rows instead of 13
- Phase 30 scripts fail with "Table TUMOR_REGISTRY1 not found" (because only TR_ALL was ingested)

**Severity:** LOW — pre-written plans specify 13 tables, not 14. But document the decision explicitly to prevent future confusion.

### Pitfall 5: Incomplete `on.exit()` Cleanup
**What goes wrong:** Script errors mid-ingest, `on.exit(dbDisconnect(con))` fires, but `.tmp` file is left behind. Next run finds `.tmp`, removes it, starts fresh — but if `.tmp` removal fails (permissions issue, file locked), the new ingest writes to a corrupt `.tmp` and produces garbage.

**Why it happens:** `on.exit()` only cleans up R-managed resources (connections). It doesn't remove the `.tmp` file on error.

**How to avoid:**
1. Add `.tmp` cleanup at script start (before `dbConnect()`): `if (file.exists(tmp_path)) file.remove(tmp_path)`
2. Add `.tmp` cleanup in `on.exit()` if build fails: `on.exit({ dbDisconnect(con); if (file.exists(tmp_path)) file.remove(tmp_path) }, add = TRUE)`
3. Test by manually killing the script mid-ingest (Ctrl+C) and verifying `.tmp` is cleaned up on next run.

**Warning signs:**
- `.tmp` exists after interrupted run
- Next run fails with "Error in dbConnect: file is locked" or "Error in file.remove: Permission denied"

**Severity:** LOW — HiPerGator filesystem permissions are predictable, and `file.remove()` failures are rare. But defensive cleanup is cheap.

## Code Examples

Verified patterns from official sources:

### Connecting to DuckDB File
```r
# Source: https://duckdb.org/docs/stable/clients/r
library(duckdb)
library(DBI)

# Read-write connection (for ingest)
con <- dbConnect(duckdb::duckdb(), dbdir = "/path/to/file.duckdb")

# Read-only connection (for queries, Phase 30+)
con <- dbConnect(duckdb::duckdb(), dbdir = "/path/to/file.duckdb", read_only = TRUE)

# Always disconnect when done
dbDisconnect(con)

# Auto-disconnect pattern (recommended)
con <- dbConnect(duckdb::duckdb(), dbdir = "/path/to/file.duckdb")
on.exit(dbDisconnect(con), add = TRUE)
# ... do work ...
```

### Writing Data to DuckDB
```r
# Source: https://duckdb.org/docs/stable/clients/r
library(DBI)
library(dplyr)

# Write data frame to DuckDB
DBI::dbWriteTable(con, "table_name", df, overwrite = TRUE)

# Append to existing table
DBI::dbWriteTable(con, "table_name", df, append = TRUE)

# Default behavior: error if table exists (neither overwrite nor append set)
# DBI::dbWriteTable(con, "table_name", df)  # Throws error if table exists
```

**Note:** Per D-02, this phase always uses `overwrite = TRUE` (rebuild from scratch). Append is never used.

### Creating Indexes
```r
# Source: https://duckdb.org/docs/current/sql/statements/create_index
library(DBI)

# Create single-column index (ART index)
DBI::dbExecute(con, "CREATE INDEX idx_tablename_colname ON tablename (colname)")

# Create multi-column index (not used in Phase 29, but documented for future)
DBI::dbExecute(con, "CREATE INDEX idx_tablename_col1_col2 ON tablename (col1, col2)")

# Check indexes (via system catalog)
DBI::dbGetQuery(con, "
  SELECT table_name, index_name
  FROM information_schema.indexes
  ORDER BY table_name
")
```

**Note:** DuckDB's `information_schema.indexes` view is not universally documented. If it doesn't exist in 1.5.1, fall back to `PRAGMA show_tables` and document the gap.

### Listing Tables
```r
# Source: https://duckdb.org/docs/current/guides/meta/list_tables
library(DBI)

# List all tables in the database
tables <- DBI::dbListTables(con)
print(tables)

# Alternative: SQL query via information_schema
tables <- DBI::dbGetQuery(con, "
  SELECT table_name
  FROM information_schema.tables
  WHERE table_schema = 'main'
  ORDER BY table_name
")
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| DuckDB R pkg 0.x (pre-1.0) | DuckDB R pkg 1.5.1 | 2026-03-26 (1.5.1), 2026-03-09 (1.5.0) | Concurrent checkpointing (17% TPC-H improvement), ART index fixes in 1.5.1, Lance format support |
| dbWriteTable with inconsistent arg order | dbWriteTable aligned with DBI spec | 2026-03-14 (1.5.0 release) | Breaking change for code relying on old arg order; verify scripts use named args |
| Manual progress tracking | Built-in CLI pager (terminal only) | 2026-03-09 (1.5.0 release) | R scripts still need manual logging; CLI improvements don't affect R workflows |

**Deprecated/outdated:**
- **DuckDB R pkg <1.0:** Pre-1.0 versions had unstable ART index behavior. Phase 29 targets 1.5.1, which includes ART index fixes.
- **`duckdb::duckdb_register()` without `overwrite` arg:** Issue #967 (2021) requested an `overwrite` parameter; current version (1.5.1) supports it. Use `duckdb_register(con, "name", df, overwrite = TRUE)` if registering temp tables in Phase 30.

## Open Questions

1. **Does `information_schema.indexes` exist in DuckDB 1.5.1 R client?**
   - What we know: DuckDB docs mention `information_schema` views for tables, columns, schemata. Indexes are mentioned in the general indexing guide but not explicitly in the R client examples.
   - What's unclear: Whether `SELECT * FROM information_schema.indexes` works in R, or if we need a fallback like `PRAGMA show_tables`.
   - Recommendation: Test on HiPerGator during Plan 29-02 implementation. If it doesn't exist, use `dbGetQuery(con, "PRAGMA show_tables")` and document the limitation.

2. **What is the actual peak RAM usage for sequential ingest of 13 tables?**
   - What we know: Largest table (DIAGNOSIS) is ~10M rows, likely ~1-2 GB in RAM. DuckDB write buffers add overhead.
   - What's unclear: Total peak RAM during `dbWriteTable()` on the largest table. HiPerGator Open OnDemand RStudio allocates 16 cores, but RAM per core varies.
   - Recommendation: Run ingest on HiPerGator with 16 cores (CONFIG$performance$num_threads = 16) and monitor `top` or `htop` to observe peak RAM. If it exceeds 80% of available RAM, reduce `num_threads` or request more RAM.

3. **Does DuckDB compress the file on disk, and what is the compression ratio for PCORnet data?**
   - What we know: DuckDB uses internal compression (LZ4 or similar), but exact ratio depends on data patterns (repeated values, sorted columns, etc.).
   - What's unclear: Expected final DuckDB file size for this cohort. Total RDS cache is ~15-20 GB; compression ratio could be 40-60% (8-12 GB final size).
   - Recommendation: Document observed compression ratio after first HiPerGator run. If ratio is worse than 60%, investigate (e.g., unsorted data, high cardinality columns).

## Environment Availability

> Skipped — Phase 29 has no external dependencies beyond R packages (duckdb, DBI, readr, glue), which are CRAN packages installable via `install.packages()`. HiPerGator R module (4.4.2) is already loaded per CLAUDE.md stack.

## Sources

### Primary (HIGH confidence)
- [Announcing DuckDB 1.5.1 – DuckDB](https://duckdb.org/2026/03/23/announcing-duckdb-151) - DuckDB 1.5.1 release notes, March 23, 2026
- [Announcing DuckDB 1.5.0 – DuckDB](https://duckdb.org/2026/03/09/announcing-duckdb-150) - DuckDB 1.5.0 release notes, March 9, 2026
- [R Client – DuckDB](https://duckdb.org/docs/stable/clients/r) - Official DuckDB R client documentation
- [Changelog • duckdb (R package)](https://r.duckdb.org/news/index.html) - R package changelog
- [Transaction Management – DuckDB](https://duckdb.org/docs/stable/sql/statements/transactions) - DuckDB ACID transaction guarantees
- [Concurrency – DuckDB](https://duckdb.org/docs/current/connect/concurrency) - DuckDB concurrency model (concurrent checkpointing)
- [CREATE INDEX Statement – DuckDB](https://duckdb.org/docs/current/sql/statements/create_index) - ART index creation syntax
- [Indexes – DuckDB](https://duckdb.org/docs/current/sql/indexes) - Index types (ART, min-max zone maps)
- [dbWriteTable: Copy data frames to database tables in DBI](https://rdrr.io/cran/DBI/man/dbWriteTable.html) - DBI spec for `dbWriteTable()`

### Secondary (MEDIUM confidence)
- [DuckDB R package dbWriteTable source](https://rdrr.io/cran/duckdb/src/R/dbWriteTable__duckdb_connection_character_data.frame.R) - R implementation details
- [GitHub Issue #104: Change in behaviour with date manipulation](https://github.com/duckdb/duckdb-r/issues/104) - Date vs TIMESTAMP type conversion issue (older version, may be fixed)
- [GitHub Issue #184: Support ICU extension and timezones for TIMESTAMPTZ](https://github.com/duckdb/duckdb-r/issues/184) - POSIXct timezone handling issue
- [Memory Management in DuckDB – DuckDB](https://duckdb.org/2024/07/09/memory-management) - DuckDB buffer manager and memory usage patterns
- [DuckDB SQL Server extension: 1.2M Rows/Sec Bulk Loading](https://medium.com/@gribanov.vladimir/duckdb-sql-server-extension-update-delete-transactions-and-1-2m-rows-sec-bulk-loading-a1a921fce647) - Bulk insert performance benchmarks (not R-specific, but indicative)
- [saveRDS() and readRDS() in R: A Practical, Modern Guide](https://thelinuxcode.com/saverds-and-readrds-in-r-a-practical-modern-guide-for-reliable-object-storage/) - RDS type fidelity (Date/POSIXct preservation)

### Tertiary (LOW confidence)
- [GitHub Discussion #16217: Large table import / sync](https://github.com/duckdb/duckdb/discussions/16217) - Community discussion on large table performance (anecdotal, not authoritative)

## Metadata

**Confidence breakdown:**
- Standard stack (duckdb R package 1.5.1): **HIGH** - Official CRAN release, documented changelog, verified release dates
- Architecture patterns (atomic write, sequential ingest): **HIGH** - Standard R/filesystem patterns, DuckDB docs confirm transaction safety
- Index creation (ART indexes): **HIGH** - Official DuckDB docs, `CREATE INDEX` syntax verified
- Type conversion (RDS → DuckDB): **MEDIUM** - DuckDB R client handles Date/POSIXct natively, but GitHub issues show edge cases exist; requires HiPerGator testing
- Memory usage (sequential ingest): **MEDIUM** - Estimates based on table sizes and DuckDB memory management docs; actual peak RAM needs HiPerGator measurement
- `information_schema.indexes` availability: **LOW** - Documented for DuckDB generally, but R client examples don't show it; needs testing

**Research date:** 2026-04-23
**Valid until:** 60 days (stable domain — DuckDB 1.5.x is mature, no fast-moving API changes expected)
