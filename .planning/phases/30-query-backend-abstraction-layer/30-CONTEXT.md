# Phase 30: Query Backend Abstraction Layer - Context

**Gathered:** 2026-04-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Create a dual-backend dispatcher so existing R scripts can transparently query PCORnet tables from either RDS (in-memory tibbles) or DuckDB (lazy SQL queries) via a single `get_pcornet_table()` function, controlled by a `USE_DUCKDB` flag. Includes connection management helpers, a `materialize()` convenience function, a smoke test of all named predicates on both backends, and documentation of any dbplyr translation gaps.

</domain>

<decisions>
## Implementation Decisions

### RDS Mode Behavior
- **D-01:** When `USE_DUCKDB = FALSE`, `get_pcornet_table()` returns the already-loaded in-memory tibble from the global `pcornet$TABLE_NAME` list. Zero overhead since `01_load_pcornet.R` already loaded everything at pipeline start.
- **D-02:** `get_pcornet_table()` accesses the `pcornet$` list as a global variable (not passed as a parameter). Matches how predicates already reference `pcornet$DIAGNOSIS` directly. No signature changes needed anywhere.

### TUMOR_REGISTRY_ALL Handling
- **D-03:** In DuckDB mode, create a `TUMOR_REGISTRY_ALL` SQL VIEW during connection setup: `CREATE VIEW TUMOR_REGISTRY_ALL AS SELECT * FROM TUMOR_REGISTRY1 UNION ALL SELECT * FROM TUMOR_REGISTRY2 UNION ALL SELECT * FROM TUMOR_REGISTRY3`. Lazy evaluation with no extra storage. Predicates can query it like any other table.

### Connection Lifecycle
- **D-04:** One DuckDB connection per pipeline run. `open_pcornet_con()` opens a read-only connection and stores it as a global (e.g., `pcornet_con`). `close_pcornet_con()` closes it at the end.
- **D-05:** The connection is opened in `01_load_pcornet.R` alongside the `pcornet$` loading. If `USE_DUCKDB = TRUE`, the DuckDB connection opens and the `TUMOR_REGISTRY_ALL` view is created in the same startup step. All data access setup happens in one place.

### Smoke Test
- **D-06:** Smoke test covers all 6 functions from `03_cohort_predicates.R`: 3 filter predicates (`has_hodgkin_diagnosis`, `with_enrollment_period`, `exclude_missing_payer`) + 3 treatment detectors (`has_chemo`, `has_radiation`, `has_sct`).
- **D-07:** 100-patient sample selected as random PATIDs from DEMOGRAPHIC table using `set.seed()` for reproducibility. Each predicate runs on both backends and resulting PATID sets are compared for equality.

### Claude's Discretion
- `materialize()` helper implementation details (whether it calls `collect()` or `as_tibble()` internally)
- `USE_DUCKDB` flag placement and default value in `00_config.R`
- Exact structure of `docs/DUCKDB_TRANSLATION_NOTES.md`
- Whether the smoke test script is standalone or a function in utils_duckdb.R

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Abstraction Foundation
- `R/utils_duckdb.R` -- Phase 29 foundation file with `verify_duckdb_roundtrip()` and Phase 30 placeholder comment. All new functions go here.
- `R/00_config.R` -- `CONFIG$cache$duckdb_path` already configured (line 73). `USE_DUCKDB` flag will be added here.
- `R/01_load_pcornet.R` -- Loads 13 tables into `pcornet$TABLE_NAME` list. DuckDB connection setup will be added here.

### Predicate Functions to Smoke Test
- `R/03_cohort_predicates.R` -- All 6 named predicates (`has_hodgkin_diagnosis`, `with_enrollment_period`, `exclude_missing_payer`, `has_chemo`, `has_radiation`, `has_sct`). These reference `pcornet$TABLE_NAME` globals.

### DuckDB Infrastructure
- `R/25_duckdb_ingest.R` -- Ingest script showing table list, ENCOUNTERID tables, and DuckDB path constants. References `PCORNET_TABLES` and `TABLES_WITH_ENCOUNTERID`.

### Phase 29 Plans (Architecture Decisions)
- `.planning/phases/29-duckdb-ingest-infrastructure/29-01-PLAN.md` -- EXTRACT_DATE constant, DuckDB path, TUMOR_REGISTRY_ALL exclusion
- `.planning/phases/29-duckdb-ingest-infrastructure/29-02-PLAN.md` -- PATID column is `ID` (not PATID), 6 tables with ENCOUNTERID indexes

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/utils_duckdb.R` -- Already structured as the extensible foundation file for Phase 30. Contains `verify_duckdb_roundtrip()` and library imports for DBI and glue.
- `CONFIG$cache$duckdb_path` -- DuckDB file path already defined in `00_config.R` line 73.
- `PCORNET_TABLES` -- Vector of 13 table names already defined in `00_config.R`, used by ingest script.

### Established Patterns
- **Global named list pattern**: All table data accessed via `pcornet$TABLE_NAME` (e.g., `pcornet$DIAGNOSIS`). The RDS backend dispatcher must return from this list.
- **dplyr pipeline pattern**: Predicates use `filter()`, `distinct()`, `semi_join()`, `inner_join()` on tibbles. DuckDB backend must return `tbl()` objects compatible with the same verbs via dbplyr.
- **Source chain**: Scripts source upstream files (`source("R/00_config.R")` -> auto-sources utils). DuckDB connection setup fits naturally in `01_load_pcornet.R`.

### Integration Points
- `01_load_pcornet.R` -- Where `USE_DUCKDB` check and `open_pcornet_con()` call will be added (after table loading section).
- `03_cohort_predicates.R` -- Smoke test target. Predicates reference `pcornet$TUMOR_REGISTRY_ALL` which must work under both backends.
- `00_config.R` -- Where `USE_DUCKDB` flag will be defined.

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- open to standard approaches for the abstraction layer implementation.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope.

</deferred>

---

*Phase: 30-query-backend-abstraction-layer*
*Context gathered: 2026-04-23*
