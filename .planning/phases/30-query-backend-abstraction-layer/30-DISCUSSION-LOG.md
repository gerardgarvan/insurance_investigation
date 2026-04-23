# Phase 30: Query Backend Abstraction Layer - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-04-23
**Phase:** 30-query-backend-abstraction-layer
**Areas discussed:** RDS mode behavior, TUMOR_REGISTRY_ALL, Connection lifecycle, Smoke test scope

---

## RDS Mode Behavior

### Question 1: Data source in RDS mode

| Option | Description | Selected |
|--------|-------------|----------|
| Return from pcornet$ list (Recommended) | Return the already-loaded in-memory tibble from pcornet$TABLE_NAME. Zero overhead since 01_load_pcornet.R already loaded everything at pipeline start. | ✓ |
| Read fresh from RDS cache | Call readRDS() from CONFIG$cache$raw_dir each time. Consistent with DuckDB path but slower and redundant. | |
| You decide | Claude picks the best approach based on codebase patterns | |

**User's choice:** Return from pcornet$ list (Recommended)
**Notes:** None

### Question 2: Global vs parameter access

| Option | Description | Selected |
|--------|-------------|----------|
| Access pcornet$ as global (Recommended) | Matches how predicates already work. No signature changes needed. get_pcornet_table('DIAGNOSIS') just returns pcornet[['DIAGNOSIS']]. | ✓ |
| Pass pcornet list as parameter | Cleaner function design but more verbose. Callers need to pass the pcornet list every time. | |
| You decide | Claude picks based on existing patterns | |

**User's choice:** Access pcornet$ as global (Recommended)
**Notes:** None

---

## TUMOR_REGISTRY_ALL

### Question 1: DuckDB handling of derived table

| Option | Description | Selected |
|--------|-------------|----------|
| Create DuckDB VIEW (Recommended) | Add CREATE VIEW during connection setup. Predicates can query it like any other table. Lazy evaluation with no extra storage. | ✓ |
| Materialize on request | Run UNION ALL query when requested, return as lazy tbl. No persistent view. | |
| Skip -- handle in predicates | Don't support in DuckDB mode. Modify predicates in Phase 31 to query TR1/TR2/TR3 separately. | |
| You decide | Claude picks the cleanest approach | |

**User's choice:** Create DuckDB VIEW (Recommended)
**Notes:** None

---

## Connection Lifecycle

### Question 1: Connection management pattern

| Option | Description | Selected |
|--------|-------------|----------|
| One connection per pipeline run (Recommended) | open_pcornet_con() at pipeline start, close_pcornet_con() at end. All scripts share one read-only connection stored as global. | ✓ |
| Per-script open/close | Each script opens/closes its own connection. More isolated but more boilerplate. | |
| Hybrid -- global + standalone support | Default to global, but open_pcornet_con() works standalone too. | |
| You decide | Claude picks based on pipeline structure | |

**User's choice:** One connection per pipeline run (Recommended)
**Notes:** None

### Question 2: Where to open the connection

| Option | Description | Selected |
|--------|-------------|----------|
| In 01_load_pcornet.R (Recommended) | After loading tables, if USE_DUCKDB is TRUE, open connection and create TUMOR_REGISTRY_ALL view. Natural fit -- data access setup in one place. | ✓ |
| Separate setup function | A new init_backend() function that scripts call explicitly. Keeps 01_load_pcornet.R unchanged. | |
| You decide | Claude picks the least-disruptive approach | |

**User's choice:** In 01_load_pcornet.R (Recommended)
**Notes:** None

---

## Smoke Test Scope

### Question 1: Which predicates to test

| Option | Description | Selected |
|--------|-------------|----------|
| All 6 functions (Recommended) | 3 filter predicates + 3 treatment detectors. Full coverage of everything in 03_cohort_predicates.R. | ✓ |
| 3 filter predicates only | Just the core cohort filters. Treatment detectors deferred to Phase 31. | |
| You decide | Claude picks based on complexity and risk | |

**User's choice:** All 6 functions (Recommended)
**Notes:** None

### Question 2: Sample selection method

| Option | Description | Selected |
|--------|-------------|----------|
| Random sample from DEMOGRAPHIC (Recommended) | 100 random PATIDs with set.seed() for reproducibility. Run each predicate on subset under both backends, compare PATID sets. | ✓ |
| First 100 by ID sort order | Deterministic without set.seed(). May not represent data diversity. | |
| You decide | Claude picks the most practical approach | |

**User's choice:** Random sample from DEMOGRAPHIC (Recommended)
**Notes:** None

---

## Claude's Discretion

- materialize() helper implementation details
- USE_DUCKDB flag placement and default value
- docs/DUCKDB_TRANSLATION_NOTES.md structure
- Smoke test script location (standalone vs function)

## Deferred Ideas

None -- discussion stayed within phase scope.
