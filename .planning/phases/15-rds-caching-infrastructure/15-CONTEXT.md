# Phase 15: RDS Caching Infrastructure - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Add persistent RDS cache for all PCORnet CDM tables so that `load_pcornet_table()` loads from serialized `.rds` files instead of re-parsing CSVs on every run. Includes cache-check logic, `FORCE_RELOAD` override, and wall-clock time-savings logging.

This phase modifies `R/01_load_pcornet.R` (the loader function and main loading block) and `R/00_config.R` (new config entries). It does NOT add cohort snapshots or output-backing data (that's Phase 16).

</domain>

<decisions>
## Implementation Decisions

### Time Savings Tracking
- **D-01:** Store original CSV parse time as an `attr()` on the RDS object (e.g., `attr(df, "csv_parse_seconds")`). `readRDS()` preserves attributes, so on cache hit the loader retrieves this value and logs: `"ENROLLMENT: 0.4s (cache) vs 18.7s (CSV) -- saved 18.3s"`. Zero extra metadata files.

### Cache Invalidation
- **D-02:** Use file modification time (`file.mtime()`) comparison only: RDS newer than source CSV = cache hit. No schema hashing or code version tracking. If pipeline code changes (new validation columns, new date parsing logic), the user sets `FORCE_RELOAD <- TRUE` in `00_config.R` once to rebuild all caches. This is an exploratory pipeline — the user knows when code changes.

### Cache Scope
- **D-03:** Cache `TUMOR_REGISTRY_ALL` (the combined TR1+TR2+TR3 table) as its own separate RDS file alongside the individual TR table caches. Keeps consistency — all loaded tables have corresponding RDS files.
- **D-04:** Skip post-load diagnostic logging (PROVIDER specialty sample, LAB_RESULT_CM null rate) on cache hits. These diagnostics are informational and useful on first load to verify data, but noisy on repeat runs. Cache hit means data is already trusted. Log only `[CACHE HIT]` per table.

### Prior Decisions (carried forward)
- **D-05:** Use `.rds` format (not `.RData`). `readRDS()` returns a single named object directly into assignment — no namespace side-effects. (Decided during v1.1 roadmapping.)
- **D-06:** Cache directory is `/blue/erin.mobley-hl.bcu/clean/rds/raw/`. Large binary files stay on blue storage, outside the repo root, gitignored. (Decided during v1.1 roadmapping.)

### Claude's Discretion
- Cache directory creation logic (auto-create with `dir.create(recursive = TRUE)` if missing, or error)
- Console log formatting details (colors, separators, alignment)
- Whether to store additional metadata in RDS attributes beyond parse time (e.g., row count, load timestamp)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Pipeline Code
- `R/01_load_pcornet.R` -- Contains `load_pcornet_table()` (lines 359-478) and main loading block (lines 484-557). This is the primary file to modify.
- `R/00_config.R` -- CONFIG list (line 25+), PCORNET_PATHS (line 74+). Add CACHE_DIR and FORCE_RELOAD here.

### Requirements
- `.planning/REQUIREMENTS.md` -- CACHE-01 through CACHE-04 (RDS caching), GIT-01/GIT-02 (gitignore)

### Roadmap
- `.planning/ROADMAP.md` -- Phase 15 success criteria (lines 242-258)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `load_pcornet_table(table_name, file_path, col_spec)` — Central loader function. Returns tibble or NULL. Already handles file existence, vroom CSV loading, date parsing, numeric validation, and summary logging. Extend this to add cache-check and cache-write logic.
- `TABLE_SPECS` lookup (line 325) — Maps table names to col_specs. All 13 tables defined.
- `PCORNET_PATHS` (line 74 in config) — Named character vector of CSV file paths. Cache paths will parallel these.
- Main loading block uses `imap(PCORNET_PATHS, ...)` pattern — the cache logic integrates naturally into this iterator.

### Established Patterns
- `CONFIG$` nested list pattern for configuration (e.g., `CONFIG$performance$num_threads`). CACHE_DIR and FORCE_RELOAD should follow this pattern.
- `message(glue(...))` for all console output. Time-savings logging should use the same pattern.
- Guard pattern at line 484: `if (exists("pcornet", envir = .GlobalEnv))` skips reload. Cache is a separate concern (persistent disk cache vs in-memory session cache).
- `TUMOR_REGISTRY_ALL` binding pattern (lines 517-531) — bind_rows after loading individual tables. Phase 15 adds a cached version of this combined table.

### Integration Points
- `.gitignore` — Add `/blue/erin.mobley-hl.bcu/clean/` exclusion (GIT-01)
- `00_config.R` — Add `CONFIG$cache_dir` and `CONFIG$force_reload` entries with documentation comment (GIT-02)
- `01_load_pcornet.R` — Modify `load_pcornet_table()` and the `imap()` loading block

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- open to standard approaches for the caching implementation.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope.

</deferred>

---

*Phase: 15-rds-caching-infrastructure*
*Context gathered: 2026-04-03*
