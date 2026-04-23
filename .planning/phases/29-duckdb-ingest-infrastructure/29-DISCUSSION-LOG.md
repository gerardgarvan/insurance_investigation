# Phase 29: DuckDB Ingest Infrastructure - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-23
**Phase:** 29-duckdb-ingest-infrastructure
**Areas discussed:** DuckDB file location, Re-run behavior, Error handling, EXTRACT_DATE config

---

## DuckDB File Location

| Option | Description | Selected |
|--------|-------------|----------|
| Alongside RDS cache | `/blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb` — new subdirectory under existing `/blue/clean/` tree. Keeps all derived data together, already gitignored. | ✓ |
| Same dir as RDS raw | `/blue/erin.mobley-hl.bcu/clean/rds/raw/pcornet.duckdb` — right next to .rds files. Simpler path but mixes formats. | |
| Project-relative | `output/duckdb/pcornet.duckdb` — under repo's output/ directory. Closer to scripts but needs separate gitignore. | |

**User's choice:** Alongside RDS cache (Recommended)
**Notes:** None — straightforward choice aligning with existing storage patterns.

---

## Re-Run Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Always rebuild | Every run produces fresh DuckDB from current RDS files. Simpler, guarantees consistency. ~20 min on HiPerGator. | ✓ |
| Cache-check like RDS | Skip rebuild if .duckdb is newer than all 13 .rds files. Saves time but adds complexity. | |
| Manual flag | FORCE_REBUILD_DUCKDB in config (default FALSE). Normal runs skip if file exists. | |

**User's choice:** Always rebuild (Recommended)
**Notes:** Since ingest is a one-time operation per extract (not part of every pipeline run), rebuild cost is acceptable.

---

## Error Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Abort entire build | Any table failure stops the build, .tmp not swapped. Atomic guarantee: canonical DuckDB is always complete or absent. | ✓ |
| Skip and continue | Failed table logged, build continues. Partial DuckDB possible but downstream scripts would break. | |
| Retry once, then abort | Try failed table once more, then abort if still fails. | |

**User's choice:** Abort entire build (Recommended)
**Notes:** Maintains atomic guarantee. Pre-written plan's tryCatch for indexes is separate — indexes can fail without aborting.

---

## EXTRACT_DATE Config

| Option | Description | Selected |
|--------|-------------|----------|
| Hardcoded in config | `EXTRACT_DATE = "2025-09-15"` in CONFIG in 00_config.R. User updates manually per new extract. | ✓ |
| Derived from CSV path | Parse date from CONFIG$data_dir path string. Automatic but fragile. | |
| Current date | Use Sys.Date(). Simple but doesn't tie log to specific data extract. | |

**User's choice:** Hardcoded in config (Recommended)
**Notes:** Matches known `Mailhot_V1_20250915` extract naming.

---

## Claude's Discretion

- Column type handling for dbWriteTable() edge cases
- Memory management approach (sequential with gc() vs parallel)
- Ingest log CSV column set beyond required (table_name, row_count, duration_sec)

## Deferred Ideas

None — discussion stayed within phase scope.
