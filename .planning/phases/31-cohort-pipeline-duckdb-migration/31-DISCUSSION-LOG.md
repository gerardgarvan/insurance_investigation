# Phase 31: Cohort Pipeline DuckDB Migration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-04-23
**Phase:** 31-cohort-pipeline-duckdb-migration
**Areas discussed:** Refactoring strategy, Lazy evaluation depth, Parity testing baseline, Benchmark scope

---

## Refactoring Strategy

### Q1: How should we refactor for DuckDB compatibility?

| Option | Description | Selected |
|--------|-------------|----------|
| In-place modification | Modify 03_cohort_predicates.R and 04_build_cohort.R to use get_pcornet_table() and dbplyr-compatible operations. Single code path works for both backends via the dispatcher. RDS backend still works because get_pcornet_table() returns tibbles when USE_DUCKDB=FALSE. | ✓ |
| Conditional code paths | Keep existing pcornet$ code intact, add if(USE_DUCKDB){...} blocks with DuckDB-specific logic. More code duplication but zero risk of breaking RDS path. | |
| You decide | Let Claude choose the approach based on what works best technically. | |

**User's choice:** In-place modification (Recommended)
**Notes:** None

### Q2: Treatment predicate approach

| Option | Description | Selected |
|--------|-------------|----------|
| Materialize per-source then combine | Each source query uses get_pcornet_table() lazily, then collect()s IDs, combines with c() as today. Simple, preserves logging, minimal refactoring. | ✓ |
| SQL UNION approach | Build a single DuckDB query with UNION ALL across sources, execute once. More SQL-native but loses per-source count logging and requires heavier rewrite. | |
| You decide | Let Claude choose based on tradeoffs. | |

**User's choice:** Materialize per-source then combine (Recommended)
**Notes:** None

---

## Lazy Evaluation Depth

### Q1: How far should lazy evaluation extend before materializing?

| Option | Description | Selected |
|--------|-------------|----------|
| Materialize at section boundaries | Each major section gets inputs lazy via get_pcornet_table(), but materializes before the next section joins. ~5-6 materialize points. Safe, debuggable, still captures DuckDB speedup on heavy filter/join/group_by operations. | ✓ |
| Single late materialize | Keep everything lazy as long as possible, materialize only at final assembly. Maximum DuckDB benefit but lubridate::interval(), year(), etc. will force early materialization anyway. | |
| You decide | Let Claude figure out the natural materialization boundaries. | |

**User's choice:** Materialize at section boundaries (Recommended)
**Notes:** None

---

## Parity Testing Baseline

### Q1: What should DuckDB output be compared against?

| Option | Description | Selected |
|--------|-------------|----------|
| Fresh RDS rebuild in same session | Run pipeline once with USE_DUCKDB=FALSE then again with TRUE in same R session. Apples-to-apples with same data, same code version. | ✓ |
| Existing Phase 16 snapshots | Compare against .rds files already on disk from Phase 16 runs. Faster but snapshots may not reflect code changes made in Phases 17-30. | |
| You decide | Let Claude choose the baseline approach. | |

**User's choice:** Fresh RDS rebuild in same session (Recommended)
**Notes:** None

### Q2: Type difference handling in waldo::compare()

| Option | Description | Selected |
|--------|-------------|----------|
| Coerce known type diffs | DuckDB may return double where RDS has integer, or POSIXct where RDS has Date. Coerce DuckDB output to match RDS types before comparison. Document coercions applied. | ✓ |
| Strict comparison | No coercion. Any type mismatch is flagged as a parity failure. More rigorous but may produce false positives on DuckDB type promotions. | |

**User's choice:** Coerce known type diffs (Recommended)
**Notes:** None

---

## Benchmark Scope

### Q1: What should the benchmark timer measure?

| Option | Description | Selected |
|--------|-------------|----------|
| Cohort build only | Time just 04_build_cohort.R execution. Isolates DuckDB query speedup from CSV/RDS loading. | ✓ |
| Full pipeline end-to-end | Time from source('R/00_config.R') through cohort output. Gives total wall-clock but mixes DuckDB gains with RDS cache hits. | |
| You decide | Let Claude determine the most meaningful measurement boundary. | |

**User's choice:** Cohort build only (Recommended)
**Notes:** None

### Q2: Benchmark script location

| Option | Description | Selected |
|--------|-------------|----------|
| Standalone wrapper script | New R/27_benchmark_cohort.R that sources pipeline under each backend, records timings, writes CSV. Reusable pattern for Phase 32. | ✓ |
| Embedded in 04_build_cohort.R | Add timing instrumentation directly to cohort build script. Simpler but mixes concerns. | |

**User's choice:** Standalone wrapper script (Recommended)
**Notes:** None

---

## Claude's Discretion

- Exact materialize point placement within sections
- Whether semi_join() needs replacement with inner_join() %>% distinct()
- ICD dot normalization approach (R-side vs DuckDB REPLACE())
- Benchmark CSV column layout

## Deferred Ideas

None -- discussion stayed within phase scope.
