# Phase 31: Cohort Pipeline DuckDB Migration - Context

**Gathered:** 2026-04-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Migrate the cohort build pipeline (`04_build_cohort.R` and its dependency chain: `03_cohort_predicates.R`, `02_harmonize_payer.R`, `10_treatment_payer.R`, `13_surveillance.R`, `14_survivorship_encounters.R`) to work under the DuckDB backend using the Phase 30 abstraction layer. Verify full parity against RDS output and benchmark DuckDB vs RDS performance.

</domain>

<decisions>
## Implementation Decisions

### Refactoring Strategy
- **D-01:** In-place modification of existing scripts. Replace `pcornet$TABLE` references with `get_pcornet_table("TABLE")` calls. Single code path works for both backends because `get_pcornet_table()` returns tibbles when `USE_DUCKDB=FALSE` and lazy `tbl_dbi` objects when `USE_DUCKDB=TRUE`.
- **D-02:** No conditional `if(USE_DUCKDB)` blocks. The dispatcher handles backend differences transparently. Only exception: where dbplyr translation gaps require different syntax (use dbplyr-compatible operations that also work on tibbles).

### Treatment Predicate Approach
- **D-03:** Treatment predicates (`has_chemo()`, `has_radiation()`, `has_sct()`) use materialize-per-source-then-combine pattern. Each source query (TR, PX, RX, DX, DRG, DISP, MA, REV) uses `get_pcornet_table()` lazily, then `collect()`s/`pull()`s IDs, combines with `c()` as today. Preserves per-source count logging.

### Lazy Evaluation Depth
- **D-04:** Materialize at section boundaries. Each major section in `04_build_cohort.R` (cohort selection, enrollment aggregation, payer join, treatment flags, surveillance, survivorship) gets inputs lazy via `get_pcornet_table()`, but materializes before the next section joins. Approximately 5-6 materialize points throughout the pipeline.
- **D-05:** Natural materialization boundaries are forced by R-specific functions that dbplyr cannot translate (e.g., `lubridate::interval()`, `lubridate::year()` for sentinel checks, `time_length()`). Claude has discretion to determine exact placement based on what dbplyr can and cannot translate.

### dbplyr Translation Gap Handling
- **D-06:** Apply workarounds documented in `docs/DUCKDB_TRANSLATION_NOTES.md`:
  - Replace `is_hl_diagnosis(DX, DX_TYPE)` with inline `%in%` matching (handle dot normalization)
  - Replace `is_hl_histology()` with `substr()` which dbplyr can translate
  - Replace `if_any(all_of(...))` with explicit OR conditions
  - Replace `str_detect()` with regex patterns with `%in%` lists or `LIKE` patterns
  - Use `UNION ALL BY NAME` for TUMOR_REGISTRY_ALL view if column mismatch issues arise

### Parity Testing
- **D-07:** Fresh RDS rebuild in same session as baseline. Run pipeline once with `USE_DUCKDB=FALSE` then again with `USE_DUCKDB=TRUE` in the same R session. Compares apples-to-apples with same data, same code version.
- **D-08:** Coerce known type differences before `waldo::compare()`. DuckDB may return `double` where RDS has `integer`, or `POSIXct` where RDS has `Date`. Coerce DuckDB output to match RDS types before comparison. Document all coercions applied.
- **D-09:** Parity checks per DBCOH-02: row count equality, PATID set equality, and full structural equality on both final cohort and attrition log.

### Benchmark Approach
- **D-10:** Time cohort build only (`04_build_cohort.R` execution), not full pipeline from config loading. Assumes data is already loaded/connected. Isolates DuckDB query speedup from CSV/RDS loading.
- **D-11:** Standalone benchmark wrapper script (e.g., `R/27_benchmark_cohort.R`) that sources the pipeline under each backend, records timings, writes `output/logs/duckdb_benchmark.csv`. Keeps benchmark logic separate from production code. Establishes reusable pattern for Phase 32.
- **D-12:** 3 runs per backend with median comparison, per DBCOH-03.

### Claude's Discretion
- Exact materialize point placement within sections (wherever dbplyr translation forces it)
- Whether `semi_join()` needs replacement with `inner_join() %>% distinct()` (benchmark if slow)
- ICD dot normalization approach (R-side `str_remove_all` vs DuckDB `REPLACE()` — either is fine as long as it works on both backends)
- Benchmark CSV column layout and summary format

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### DuckDB Migration
- `docs/DUCKDB_TRANSLATION_NOTES.md` -- 6 known translation gaps with workarounds for Phase 31 refactoring
- `R/utils_duckdb.R` -- Backend abstraction layer (get_pcornet_table, open/close_pcornet_con, materialize)

### Cohort Pipeline (migration targets)
- `R/04_build_cohort.R` -- Main cohort build script (~565 lines, 10 sections, ~40+ pcornet$ references)
- `R/03_cohort_predicates.R` -- Named filter predicates and treatment flag functions (~540 lines, custom R functions needing SQL translation)
- `R/02_harmonize_payer.R` -- Payer harmonization (sourced by 04_build_cohort.R)
- `R/10_treatment_payer.R` -- Treatment-anchored payer computation (sourced inline by 04_build_cohort.R)
- `R/13_surveillance.R` -- Surveillance modality detection (sourced inline by 04_build_cohort.R)
- `R/14_survivorship_encounters.R` -- Survivorship encounter classification (sourced inline by 04_build_cohort.R)

### Infrastructure
- `R/00_config.R` -- USE_DUCKDB flag, DUCKDB_PATH, EXTRACT_DATE constants
- `R/utils_icd.R` -- is_hl_diagnosis(), is_hl_histology(), normalize_icd() (functions needing inline replacement for dbplyr)

### Parity Baselines
- Phase 16 snapshot directory: `/blue/erin.mobley-hl.bcu/clean/rds/cohort/` -- cohort_final.rds, attrition_log.rds (reference only; fresh rebuild used as actual baseline per D-07)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `get_pcornet_table(name, con)` -- Phase 30 dispatcher, returns tibble or tbl_dbi based on USE_DUCKDB flag
- `materialize()` -- Phase 30 helper, collect() for lazy queries, no-op for tibbles
- `open_pcornet_con()` / `close_pcornet_con()` -- Phase 30 DuckDB connection management with TUMOR_REGISTRY_ALL view creation
- `verify_duckdb_roundtrip()` -- Phase 29 dimension/column verification (used during ingest, reusable for validation)
- `waldo::compare()` -- External package for structural comparison (specified in DBCOH-02)

### Established Patterns
- `pcornet$TABLE` global list access -- the pattern being replaced with `get_pcornet_table("TABLE")`
- Named predicate convention (`has_*`, `with_*`, `exclude_*`) -- preserve function signatures, change internals
- Per-source ID accumulation in treatment predictors -- preserve pattern, materialize each source query
- RDS snapshot pattern (`saveRDS()` at each filter step) -- continue saving snapshots under DuckDB path

### Integration Points
- `USE_DUCKDB` flag in `00_config.R` -- the master switch
- `pcornet_con` global variable -- DuckDB connection opened by `open_pcornet_con()`
- TUMOR_REGISTRY_ALL SQL VIEW -- created by `open_pcornet_con()`, replaces `pcornet$TUMOR_REGISTRY_ALL`
- `output/logs/duckdb_benchmark.csv` -- new output for benchmark results

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- open to standard approaches within the decisions captured above.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope.

</deferred>

---

*Phase: 31-cohort-pipeline-duckdb-migration*
*Context gathered: 2026-04-23*
