# Phase 29: DuckDB Ingest Infrastructure - Context

**Gathered:** 2026-04-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Ingest all 13 PCORnet tables from the existing RDS cache into a single indexed DuckDB file with atomic write and round-trip verification. This phase creates the DuckDB file and validates its contents — it does NOT change how any existing scripts access data (that's Phase 30).

</domain>

<decisions>
## Implementation Decisions

### DuckDB File Location
- **D-01:** DuckDB file lives at `/blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb` — a new `duckdb/` subdirectory under the existing `/blue/clean/` tree. This keeps all derived data together and is already gitignored via the existing `/blue/erin.mobley-hl.bcu/clean/` exclusion.

### Re-Run Behavior
- **D-02:** Always rebuild from scratch. Every run of `R/25_duckdb_ingest.R` produces a fresh DuckDB from current RDS files. No cache-check or timestamp comparison. The ingest is a one-time operation per extract (not part of the regular pipeline run), so the ~20 minute cost is acceptable.

### Error Handling
- **D-03:** Abort entire build on any table failure. If one table fails to ingest (type conversion, disk error, etc.), the `.tmp` file is NOT swapped to the canonical path. The user sees the error, fixes the issue, and re-runs. This maintains the atomic guarantee: the canonical DuckDB file is always either complete (all 13 tables) or absent.
- **D-04:** Index creation uses `tryCatch()` per index (from pre-written plan 29-02). A failed index does not abort the build — it logs a warning. An unindexed table is still queryable, just slower.

### EXTRACT_DATE Configuration
- **D-05:** `EXTRACT_DATE = "2025-09-15"` hardcoded in `CONFIG` in `R/00_config.R`. Matches the known `Mailhot_V1_20250915` extract. User updates it manually when a new extract arrives. Used for ingest log filename: `output/logs/duckdb_ingest_2025-09-15.csv`.

### Claude's Discretion
- Column type handling: If `dbWriteTable()` rejects a column type (e.g., POSIXct vs Date), Claude can add explicit casts in a helper before the write.
- Memory management: Sequential table ingestion with `gc()` between tables (per pre-written plan approach). Claude can adjust if HiPerGator memory allows parallel writes.
- Ingest log CSV columns: Claude decides the exact column set (table_name, row_count, duration_sec are required; additional columns like col_count or file_size at discretion).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### RDS Cache Infrastructure (source data for ingest)
- `R/00_config.R` -- CONFIG$cache settings (cache_dir, raw_dir, force_reload), PCORNET_TABLES list (13 tables)
- `R/01_load_pcornet.R` -- `load_pcornet_table()` function with RDS cache read/write logic, TUMOR_REGISTRY_ALL binding

### Pre-Written Plan Stubs
- `29-01-PLAN.md` (repo root) -- Ingest script core: atomic write, sequential loop, config additions (DBING-01, DBING-02)
- `29-02-PLAN.md` (repo root) -- Index creation and round-trip verification helper (DBING-03)

### Requirements
- `.planning/REQUIREMENTS.md` section "v1.3 Requirements > DuckDB Ingest (Phase 29)" -- DBING-01, DBING-02, DBING-03

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/00_config.R` CONFIG$cache structure: pattern for adding `duckdb_dir` and `duckdb_path` alongside existing cache settings
- `R/01_load_pcornet.R` `load_pcornet_table()`: reads from `CONFIG$cache$raw_dir` — the ingest script can use the same path to locate RDS files
- `R/utils_snapshot.R` `save_output_data()`: pattern for consistent path construction and logging — ingest log CSV can follow similar approach
- `PCORNET_TABLES` vector in `00_config.R`: authoritative list of 13 tables to ingest

### Established Patterns
- Cache directory structure: `/blue/erin.mobley-hl.bcu/clean/rds/{raw,cohort,outputs}/` — DuckDB adds `../duckdb/`
- Gitignore already covers `/blue/erin.mobley-hl.bcu/clean/` — DuckDB subdirectory inherits this
- Console logging with `glue()` + `message()` for progress reporting (seen throughout pipeline)
- `TUMOR_REGISTRY_ALL` is a derived table (bind of TR1+TR2+TR3) cached as its own RDS — must decide whether to ingest it as a 14th table or only ingest the 3 individual TR tables

### Integration Points
- `R/00_config.R`: Add `EXTRACT_DATE`, `CONFIG$cache$duckdb_dir`, `CONFIG$cache$duckdb_path` constants
- `R/25_duckdb_ingest.R`: New standalone script (follows numbering convention: R/24 exists for per-patient source detection)
- `R/utils_duckdb.R`: New utility file for `verify_duckdb_roundtrip()` — minimal stub in Phase 29, fleshed out in Phase 30
- `output/logs/`: Existing directory for ingest log CSV output

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. The pre-written plan stubs provide the architectural sketch; planning should refine them with the decisions captured above.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 29-duckdb-ingest-infrastructure*
*Context gathered: 2026-04-23*
