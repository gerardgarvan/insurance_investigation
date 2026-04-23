# Phase 30: Query Backend Abstraction Layer - Research

**Researched:** 2026-04-23
**Domain:** R database abstraction with dbplyr + DuckDB backend
**Confidence:** MEDIUM

## Summary

Phase 30 creates a dual-backend dispatcher allowing transparent switching between in-memory tibbles (RDS) and lazy DuckDB queries via a `USE_DUCKDB` flag. The core technical challenge is ensuring that dplyr pipelines written for tibbles work identically when querying DuckDB tables through dbplyr's SQL translation layer.

**Primary recommendation:** Use dbplyr 2.5.2+ with duckdb 1.5.1+ for mature lazy evaluation support. Return `tbl_dbi` objects from DuckDB backend (not raw tibbles) to preserve lazy evaluation semantics. Create a `TUMOR_REGISTRY_ALL` SQL VIEW during connection setup to match the existing `bind_rows()` pattern without storage overhead.

**Key insight:** dbplyr automatically handles most dplyr operations (filter, select, mutate, joins) via SQL translation, but some functions (custom predicates, complex case_when) may require local fallback. The smoke test will surface translation gaps early so workarounds can be documented before full migration.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**RDS Mode Behavior:**
- **D-01:** When `USE_DUCKDB = FALSE`, `get_pcornet_table()` returns the already-loaded in-memory tibble from the global `pcornet$TABLE_NAME` list. Zero overhead since `01_load_pcornet.R` already loaded everything at pipeline start.
- **D-02:** `get_pcornet_table()` accesses the `pcornet$` list as a global variable (not passed as a parameter). Matches how predicates already reference `pcornet$DIAGNOSIS` directly. No signature changes needed anywhere.

**TUMOR_REGISTRY_ALL Handling:**
- **D-03:** In DuckDB mode, create a `TUMOR_REGISTRY_ALL` SQL VIEW during connection setup: `CREATE VIEW TUMOR_REGISTRY_ALL AS SELECT * FROM TUMOR_REGISTRY1 UNION ALL SELECT * FROM TUMOR_REGISTRY2 UNION ALL SELECT * FROM TUMOR_REGISTRY3`. Lazy evaluation with no extra storage. Predicates can query it like any other table.

**Connection Lifecycle:**
- **D-04:** One DuckDB connection per pipeline run. `open_pcornet_con()` opens a read-only connection and stores it as a global (e.g., `pcornet_con`). `close_pcornet_con()` closes it at the end.
- **D-05:** The connection is opened in `01_load_pcornet.R` alongside the `pcornet$` loading. If `USE_DUCKDB = TRUE`, the DuckDB connection opens and the `TUMOR_REGISTRY_ALL` view is created in the same startup step. All data access setup happens in one place.

**Smoke Test:**
- **D-06:** Smoke test covers all 6 functions from `03_cohort_predicates.R`: 3 filter predicates (`has_hodgkin_diagnosis`, `with_enrollment_period`, `exclude_missing_payer`) + 3 treatment detectors (`has_chemo`, `has_radiation`, `has_sct`).
- **D-07:** 100-patient sample selected as random PATIDs from DEMOGRAPHIC table using `set.seed()` for reproducibility. Each predicate runs on both backends and resulting PATID sets are compared for equality.

### Claude's Discretion

- `materialize()` helper implementation details (whether it calls `collect()` or `as_tibble()` internally)
- `USE_DUCKDB` flag placement and default value in `00_config.R`
- Exact structure of `docs/DUCKDB_TRANSLATION_NOTES.md`
- Whether the smoke test script is standalone or a function in utils_duckdb.R

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DBAPI-01 | User can call `get_pcornet_table(name, con)` to get a pipeable dplyr-compatible object from either RDS or DuckDB backend transparently | dbplyr `tbl()` returns `tbl_dbi` objects with full dplyr compatibility; dispatcher pattern maps to standard R S3 method dispatch |
| DBAPI-02 | User can toggle `USE_DUCKDB` flag in `00_config.R` to switch all scripts between RDS and DuckDB without changing downstream code | Global flag pattern is standard R practice; conditional logic in `get_pcornet_table()` preserves identical downstream interfaces |
| DBAPI-03 | User can manage DuckDB connections via `open_pcornet_con()` / `close_pcornet_con()` with read-only enforcement, and convert lazy queries to tibbles via `materialize()` | DBI `dbConnect()` accepts `read_only = TRUE` parameter; `collect()` / `as_tibble()` materialize lazy queries |
| DBAPI-04 | User can see all named predicates passing a smoke test on both backends (100-patient sample, PATID set equality), with translation gaps documented in `docs/DUCKDB_TRANSLATION_NOTES.md` | Smoke testing pattern validates critical paths with small sample; `setequal()` / `waldo::compare()` verify PATID set equality; dbplyr function translation docs list known gaps |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dbplyr | 2.5.2 | dplyr backend for databases | Latest CRAN release (2026-02-13); mature SQL translation layer for dplyr verbs; DuckDB-specific backend optimizations |
| duckdb (R) | 1.5.1 | DBI driver for DuckDB | Latest CRAN release (2026-03-26); includes DuckDB v1.5.1 engine; official R interface with full DBI compliance |
| DBI | 1.3.0+ | Database interface specification | Standard database abstraction layer; required by dbplyr; defines `dbConnect()`, `dbGetQuery()`, etc. |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| glue | 1.8.0 | String formatting for SQL | Already in project stack; use for `CREATE VIEW` statements and error messages |
| waldo | 0.6.1+ | Deep comparison for testing | Optional for smoke test; `waldo::compare()` provides detailed diff output for debugging parity issues |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| dbplyr | duckplyr | duckplyr is a drop-in dplyr replacement with automatic DuckDB acceleration, but requires converting all tibbles to `duckplyr_df` objects. Phase 30's dispatcher pattern allows surgical backend switching without rewriting existing code. |
| `collect()` | `as_tibble()` | Both materialize lazy queries. `collect()` is dbplyr-native (recommended in dbplyr docs), `as_tibble()` works but may cause confusion about intent. Use `collect()` for clarity. |
| `tbl()` | `tbl_file()` | `tbl_file()` reads Parquet/CSV directly without ingest, but requires changing data layer (out of scope for Phase 30). `tbl()` works with existing DuckDB file. |

**Installation:**

```r
install.packages(c("dbplyr", "duckdb", "DBI", "waldo"))
```

**Version verification:**

```r
packageVersion("dbplyr")  # Expected: 2.5.2
packageVersion("duckdb")  # Expected: 1.5.1
packageVersion("DBI")     # Expected: 1.3.0+
```

All versions verified against CRAN as of 2026-04-23.

## Architecture Patterns

### Recommended Project Structure

```
R/
├── utils_duckdb.R          # Backend abstraction helpers (Phase 29 foundation + Phase 30 additions)
├── 00_config.R             # USE_DUCKDB flag, duckdb_path config
├── 01_load_pcornet.R       # Connection setup location (per D-05)
└── 03_cohort_predicates.R  # Smoke test target (predicates must work on both backends)

docs/
└── DUCKDB_TRANSLATION_NOTES.md  # Translation gaps found during smoke test
```

### Pattern 1: Backend Dispatcher (S3 Method Dispatch)

**What:** A generic function that returns different object types based on `USE_DUCKDB` flag.

**When to use:** When you need a single interface that delegates to different implementations at runtime.

**Example:**

```r
# Source: Backend dispatcher pattern (standard R S3 dispatch)
# In utils_duckdb.R

get_pcornet_table <- function(table_name, con = NULL) {
  if (!exists("USE_DUCKDB", envir = .GlobalEnv) || !USE_DUCKDB) {
    # RDS mode: return tibble from global pcornet list (D-01, D-02)
    if (!exists("pcornet", envir = .GlobalEnv)) {
      stop(glue("pcornet list not found. Run source('R/01_load_pcornet.R') first."))
    }
    pcornet <- get("pcornet", envir = .GlobalEnv)
    if (!table_name %in% names(pcornet)) {
      stop(glue("Table {table_name} not found in pcornet list."))
    }
    return(pcornet[[table_name]])
  } else {
    # DuckDB mode: return tbl_dbi lazy query object
    if (is.null(con)) {
      if (!exists("pcornet_con", envir = .GlobalEnv)) {
        stop("DuckDB connection not found. Run open_pcornet_con() first.")
      }
      con <- get("pcornet_con", envir = .GlobalEnv)
    }
    return(dplyr::tbl(con, table_name))
  }
}
```

**Why this works:**
- RDS mode returns a tibble (S3 class `tbl_df`)
- DuckDB mode returns a `tbl_dbi` object (S3 class `tbl_lazy`)
- Both support identical dplyr verbs via method dispatch
- Downstream code sees no difference

### Pattern 2: Connection Management with Read-Only Enforcement

**What:** Centralized connection lifecycle with automatic read-only enforcement.

**When to use:** Multi-process environments where concurrent read-only access is required.

**Example:**

```r
# Source: DBI connection pattern with read_only parameter
# In utils_duckdb.R

open_pcornet_con <- function(db_path = CONFIG$cache$duckdb_path, read_only = TRUE) {
  if (exists("pcornet_con", envir = .GlobalEnv)) {
    warning("DuckDB connection already open. Closing and reopening.")
    close_pcornet_con()
  }

  con <- DBI::dbConnect(
    duckdb::duckdb(),
    dbdir = db_path,
    read_only = read_only
  )

  # Create TUMOR_REGISTRY_ALL view (D-03)
  # Use IF NOT EXISTS to avoid errors on reconnection
  DBI::dbExecute(con, "
    CREATE VIEW IF NOT EXISTS TUMOR_REGISTRY_ALL AS
    SELECT * FROM TUMOR_REGISTRY1
    UNION ALL
    SELECT * FROM TUMOR_REGISTRY2
    UNION ALL
    SELECT * FROM TUMOR_REGISTRY3
  ")

  assign("pcornet_con", con, envir = .GlobalEnv)
  message(glue("DuckDB connection opened (read_only={read_only}): {db_path}"))
  invisible(con)
}

close_pcornet_con <- function() {
  if (!exists("pcornet_con", envir = .GlobalEnv)) {
    warning("No DuckDB connection to close.")
    return(invisible(NULL))
  }

  con <- get("pcornet_con", envir = .GlobalEnv)
  DBI::dbDisconnect(con, shutdown = TRUE)
  rm(pcornet_con, envir = .GlobalEnv)
  message("DuckDB connection closed.")
  invisible(NULL)
}
```

**Why read_only = TRUE:**
- Prevents accidental writes during analysis
- Allows multiple R processes to query the same DuckDB file concurrently
- Standard practice for read-only workflows

### Pattern 3: Lazy Query Materialization

**What:** Convert lazy DuckDB queries to in-memory tibbles on demand.

**When to use:** When you need to force query execution (e.g., for plotting, summary stats, writing CSVs).

**Example:**

```r
# Source: dbplyr collect() / dplyr::as_tibble() pattern
# In utils_duckdb.R

materialize <- function(lazy_tbl) {
  # dplyr::collect() is the dbplyr-native way to materialize lazy queries
  # It calls DBI::dbFetch() internally and returns a tibble
  dplyr::collect(lazy_tbl)
}
```

**Alternative implementation (as_tibble):**

```r
materialize <- function(lazy_tbl) {
  # as_tibble() also works but is less explicit about intent
  # collect() is preferred in dbplyr documentation
  dplyr::as_tibble(lazy_tbl)
}
```

**Recommendation:** Use `collect()` for clarity. It's the standard dbplyr function for this purpose.

### Pattern 4: Smoke Test with PATID Set Equality

**What:** Run predicates on small sample and compare PATID sets from both backends.

**When to use:** Validate that SQL translation produces identical results to in-memory operations.

**Example:**

```r
# Source: Smoke testing pattern for backend parity
# Could be standalone script or function in utils_duckdb.R

smoke_test_predicates <- function(sample_size = 100, seed = 20260423) {
  set.seed(seed)

  # Sample 100 random patients from DEMOGRAPHIC
  sample_ids <- pcornet$DEMOGRAPHIC %>%
    distinct(ID) %>%
    slice_sample(n = sample_size) %>%
    pull(ID)

  # Create sample data frame
  sample_df <- tibble(ID = sample_ids)

  # Test has_hodgkin_diagnosis()
  rds_hl <- sample_df %>% has_hodgkin_diagnosis() %>% pull(ID)

  # Switch to DuckDB mode
  USE_DUCKDB <<- TRUE
  open_pcornet_con()
  ddb_hl <- sample_df %>% has_hodgkin_diagnosis() %>% pull(ID)
  close_pcornet_con()
  USE_DUCKDB <<- FALSE

  # Compare PATID sets
  if (setequal(rds_hl, ddb_hl)) {
    message("✓ has_hodgkin_diagnosis: PATID sets match")
  } else {
    message("✗ has_hodgkin_diagnosis: PATID sets differ")
    # Use waldo for detailed comparison
    waldo::compare(sort(rds_hl), sort(ddb_hl))
  }
}
```

**Key insight:** Use `setequal()` for simple pass/fail, `waldo::compare()` for debugging.

### Anti-Patterns to Avoid

- **Mixing backends within a pipeline:** Don't toggle `USE_DUCKDB` mid-pipeline. Set it once at the start and stick to it. Switching mid-pipeline breaks lazy evaluation chains.

- **Calling materialize() too early:** Don't call `materialize()` / `collect()` on DuckDB queries until you need the full result. Lazy evaluation allows DuckDB to optimize the entire query plan. Premature materialization defeats the purpose of using DuckDB.

- **Assuming all dplyr works in DuckDB:** Some custom functions and complex `case_when()` statements may not translate to SQL. Always run the smoke test first to identify gaps. Document workarounds in DUCKDB_TRANSLATION_NOTES.md.

- **Forgetting to close connections:** DuckDB connections lock the file. Always call `close_pcornet_con()` at the end of scripts or in an `on.exit()` handler to avoid file access issues.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SQL translation layer | Custom SQL builder, manual `sprintf()` queries | dbplyr | dbplyr handles 95%+ of dplyr operations automatically. Custom SQL builders are bug-prone and don't benefit from dbplyr's query optimization. DuckDB backend is already tuned. |
| Connection pooling | Custom connection cache, manual reconnect logic | DBI standard connection (single connection per run) | Phase 30 is read-only, single-process. Connection pooling adds complexity without benefit. One connection opened at startup, closed at end. |
| Lazy query inspection | Parsing SQL strings manually | `dplyr::show_query()`, `dplyr::explain()` | dbplyr provides `show_query()` to inspect generated SQL, `explain()` to see DuckDB's query plan. Don't reverse-engineer SQL by hand. |
| Deep comparison for testing | Manual `all.equal()` loops, custom diff logic | `waldo::compare()` | waldo provides structured diff output for tibbles/data frames. Handles edge cases (NA, floating point, factors) automatically. |

**Key insight:** dbplyr is production-grade SQL translation. Trust it first, only write raw SQL (via `DBI::dbGetQuery()` or `dplyr::sql()`) if translation fails.

## Common Pitfalls

### Pitfall 1: Forgetting that tbl_dbi is Lazy

**What goes wrong:** Calling `nrow()` or printing a `tbl_dbi` object to check "if it worked" triggers a full table scan. On large tables this is slow and defeats the purpose of DuckDB.

**Why it happens:** Tibbles (`tbl_df`) are in-memory, so `nrow()` is instant. `tbl_dbi` objects are lazy queries, so `nrow()` requires running `COUNT(*)` against the database.

**How to avoid:** Don't call `nrow()`, `print()`, or `View()` on intermediate `tbl_dbi` objects during pipeline development. Use `dplyr::show_query()` to inspect the SQL instead. Only materialize (`collect()`) when you need the final result.

**Warning signs:**
- Pipeline feels slow despite "using DuckDB"
- You see SQL queries in console output every time you inspect an object
- Phase 31 benchmarks show no speedup vs RDS

### Pitfall 2: Custom Functions Don't Translate to SQL

**What goes wrong:** Predicates like `has_hodgkin_diagnosis()` call `is_hl_diagnosis()` (a custom function from `utils_icd.R`). dbplyr can't translate custom R functions to SQL, so the entire operation falls back to local execution.

**Why it happens:** dbplyr only knows how to translate built-in R functions (e.g., `mean()`, `sum()`, `str_detect()`). Custom functions are opaque to the SQL translator.

**How to avoid:**
1. **Refactor custom functions into dplyr-compatible operations.** Example: Replace `is_hl_diagnosis(DX, DX_TYPE)` with inline `filter(DX %in% ICD_CODES$hl_icd10 & DX_TYPE == "10")`.
2. **If refactoring is impractical, document the fallback.** The smoke test will reveal if fallback causes correctness issues. If PATID sets match, fallback is acceptable (just slower).
3. **For Phase 31 full migration, consider rewriting predicates as SQL functions** registered with `dplyr::sql_translate_env()`.

**Warning signs:**
- Smoke test PATID sets differ between backends
- `dplyr::show_query()` shows incomplete SQL (missing WHERE clauses)
- No performance improvement in Phase 31 benchmarks

### Pitfall 3: semi_join() / anti_join() May Not Optimize Well

**What goes wrong:** dbplyr translates `semi_join()` to a `WHERE EXISTS` subquery or `IN` clause, which can be slower than the in-memory hash join used by dplyr. There are known DuckDB issues where `SEMI JOIN` is 2200x slower than `INNER JOIN` for certain query patterns.

**Why it happens:** DuckDB's query optimizer may not recognize optimization opportunities in the generated SQL. dbplyr's translation is correct but not always optimal.

**How to avoid:**
1. **For Phase 30, document if semi_join behaves differently.** The smoke test will reveal correctness issues (PATID set mismatch).
2. **For Phase 31, consider refactoring to `inner_join() %>% distinct(ID)`** if semi_join is slow. This gives the optimizer more freedom.
3. **Check DuckDB GitHub for updates.** Semi-join performance has been a known issue; later DuckDB versions may fix it.

**Warning signs:**
- Smoke test passes but DuckDB query is unexpectedly slow
- `EXPLAIN` shows full table scans instead of index usage
- Phase 31 benchmark shows regression vs RDS

### Pitfall 4: TUMOR_REGISTRY_ALL View Requires All TR Tables

**What goes wrong:** If `TUMOR_REGISTRY2` or `TUMOR_REGISTRY3` are missing from the DuckDB file, the `CREATE VIEW` statement fails and connection setup crashes.

**Why it happens:** The view definition (D-03) assumes all three tables exist. If the ingest script skipped empty tables, the view fails.

**How to avoid:** Phase 29 ingests all 13 tables unconditionally, even if empty (verified in Phase 29 CONTEXT). No special handling needed. Document this dependency in DUCKDB_TRANSLATION_NOTES.md.

**Warning signs:**
- `open_pcornet_con()` fails with "table not found" error
- DuckDB file was created by custom script, not Phase 29 ingest
- Partial ingest (e.g., testing with subset of tables)

## Code Examples

Verified patterns from existing code and dbplyr/DuckDB documentation:

### Example 1: Basic Table Access

```r
# Source: Pattern from 03_cohort_predicates.R (has_hodgkin_diagnosis)
# Backend-agnostic table access

# Current (RDS-only):
dx_hl_patients <- pcornet$DIAGNOSIS %>%
  filter(is_hl_diagnosis(DX, DX_TYPE)) %>%
  distinct(ID)

# Phase 30 (dual-backend):
dx_hl_patients <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX %in% ICD_CODES$hl_icd10 & DX_TYPE == "10") %>%  # Refactored for SQL translation
  distinct(ID) %>%
  collect()  # Materialize when needed
```

### Example 2: Connection Lifecycle in 01_load_pcornet.R

```r
# Source: Phase 30 integration point (per D-05)
# Add after existing pcornet list loading

# Existing code loads pcornet$ENROLLMENT, pcornet$DIAGNOSIS, etc.
# ...

# Phase 30: DuckDB connection setup
if (exists("USE_DUCKDB") && USE_DUCKDB) {
  open_pcornet_con()
  message("DuckDB mode enabled. Tables accessed via get_pcornet_table().")
} else {
  message("RDS mode enabled. Tables accessed via pcornet$TABLE_NAME.")
}
```

### Example 3: Smoke Test Script Structure

```r
# Source: Smoke testing pattern combining set equality + detailed diff
# Standalone script: tests/smoke_test_backend_parity.R

library(dplyr)
library(glue)
source("R/00_config.R")
source("R/01_load_pcornet.R")
source("R/utils_duckdb.R")
source("R/03_cohort_predicates.R")

# Test configuration
SAMPLE_SIZE <- 100
SEED <- 20260423

set.seed(SEED)
sample_ids <- pcornet$DEMOGRAPHIC %>%
  distinct(ID) %>%
  slice_sample(n = SAMPLE_SIZE) %>%
  pull(ID)

sample_df <- tibble(ID = sample_ids)

# Predicate list (D-06)
predicates <- list(
  has_hodgkin_diagnosis = has_hodgkin_diagnosis,
  with_enrollment_period = with_enrollment_period,
  exclude_missing_payer = function(df) exclude_missing_payer(df, payer_summary),
  has_chemo = has_chemo,
  has_radiation = has_radiation,
  has_sct = has_sct
)

results <- list()

for (pred_name in names(predicates)) {
  message(glue("\n=== Testing {pred_name} ==="))

  # RDS mode
  USE_DUCKDB <<- FALSE
  rds_ids <- predicates[[pred_name]](sample_df) %>% pull(ID)

  # DuckDB mode
  USE_DUCKDB <<- TRUE
  open_pcornet_con()
  ddb_ids <- predicates[[pred_name]](sample_df) %>% collect() %>% pull(ID)
  close_pcornet_con()
  USE_DUCKDB <<- FALSE

  # Compare
  match <- setequal(rds_ids, ddb_ids)
  results[[pred_name]] <- match

  if (match) {
    message(glue("✓ {pred_name}: {length(rds_ids)} PATIDs match"))
  } else {
    message(glue("✗ {pred_name}: RDS={length(rds_ids)}, DuckDB={length(ddb_ids)}"))
    print(waldo::compare(sort(rds_ids), sort(ddb_ids)))
  }
}

# Summary
n_pass <- sum(unlist(results))
n_total <- length(results)
message(glue("\n=== Smoke Test Summary: {n_pass}/{n_total} predicates passed ==="))
if (n_pass < n_total) {
  message("Review DUCKDB_TRANSLATION_NOTES.md for documented gaps and workarounds.")
}
```

### Example 4: Inspecting Generated SQL

```r
# Source: dbplyr show_query() documentation
# Debugging translation issues

library(dplyr)
source("R/utils_duckdb.R")

USE_DUCKDB <- TRUE
open_pcornet_con()

# Build query without executing
query <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10", DX %in% c("C81.10", "C81.20")) %>%
  distinct(ID)

# Show generated SQL
query %>% show_query()
# Output:
# <SQL>
# SELECT DISTINCT "ID"
# FROM "DIAGNOSIS"
# WHERE ("DX_TYPE" = '10') AND ("DX" IN ('C81.10', 'C81.20'))

# Show DuckDB query plan
query %>% explain()

close_pcornet_con()
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| dplyr only (in-memory) | dbplyr + DuckDB backend | dbplyr 2.0+ (2021), matured in 2.5.x (2025-2026) | Lazy evaluation allows querying datasets larger than RAM; DuckDB engine provides 10-100x speedup for aggregations |
| Manual SQL string building | dbplyr SQL translation | Standard since dplyr 0.5 (2016) | 95% of dplyr operations auto-translate; eliminates SQL injection risks and syntax errors |
| `as_tibble()` for materialization | `collect()` | dbplyr best practice (documented 2020+) | `collect()` is explicit about intent; works identically across all dbplyr backends (DuckDB, PostgreSQL, etc.) |
| RStudio RMarkdown for database queries | Posit Workbench + DuckDB | Posit rebranding (2022), DuckDB R package stable (2023+) | DuckDB embeds in R process (no server setup); production-ready since v1.0 (2024-06) |

**Deprecated/outdated:**
- **src_dbi() and src_tbls():** Deprecated in dbplyr 2.0 (replaced by `tbl()` and `dbplyr::in_schema()`). Use `tbl()` directly.
- **`sql_render()` and `build_sql()`:** Internal dbplyr functions. Use `show_query()` for debugging, not internal APIs.
- **DuckDB <1.0 (pre-2024):** Early versions had stability issues and incomplete SQL support. Use 1.5.1+ for production.

## Open Questions

1. **Do custom predicate functions require refactoring for SQL translation, or is local fallback acceptable?**
   - What we know: dbplyr can't translate `is_hl_diagnosis()`. Fallback executes the filter in R after fetching data.
   - What's unclear: Does fallback break correctness (smoke test will reveal), and is performance acceptable (Phase 31 benchmarks will reveal)?
   - Recommendation: Run smoke test first. If PATID sets match, document fallback as "acceptable for Phase 30, optimize in Phase 31 if needed." If sets differ, refactor is mandatory.

2. **Should materialize() wrap collect() or as_tibble()?**
   - What we know: Both work. `collect()` is dbplyr-native, `as_tibble()` is more generic.
   - What's unclear: User preference for readability vs. technical precision.
   - Recommendation: Use `collect()` per dbplyr documentation. Less ambiguous than `as_tibble()`.

3. **Does TUMOR_REGISTRY_ALL view need column alignment across TR1/TR2/TR3?**
   - What we know: SQL `UNION ALL` requires identical column sets. TR1/TR2/TR3 have different schemas (TR1: 314 cols, TR2/TR3: 140 cols).
   - What's unclear: Does the view definition need `SELECT` to harmonize columns, or does DuckDB auto-pad?
   - Recommendation: Test during Plan 01 implementation. If `UNION ALL` fails, use `SELECT col1, col2, ... FROM TR1 UNION ALL SELECT col1, col2, ... FROM TR2` with explicit column lists.

## Environment Availability

> Phase 30 has no external dependencies beyond R packages. R itself is expected to be available on HiPerGator via `module load R/4.4.2` (per CLAUDE.md stack guidance).

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| R | Phase execution | ✗ (Windows local env) | — | Must run on HiPerGator (Linux) |
| dbplyr | Backend abstraction | ✗ | — | Install via `install.packages("dbplyr")` |
| duckdb (R package) | DBI driver | ✗ | — | Install via `install.packages("duckdb")` |
| DBI | Database interface | ✗ | — | Auto-installed with dbplyr |
| waldo | Smoke test comparison | ✗ | — | Optional; fallback to manual `setdiff()` |

**Missing dependencies with no fallback:**
- R packages (dbplyr, duckdb, DBI) — must install before execution

**Missing dependencies with fallback:**
- waldo — smoke test can use `setequal()` + manual `setdiff()` for debugging

**Note:** Environment check skipped on local Windows machine. Phase 30 will execute on HiPerGator where R 4.4.2 is available. Package installation is part of Plan 01 setup.

## Sources

### Primary (HIGH confidence)
- [CRAN dbplyr 2.5.2](https://cran.r-project.org/web/packages/dbplyr/dbplyr.pdf) - Official package documentation (2026-02-13 release)
- [CRAN duckdb 1.5.1](https://cran.r-project.org/web/packages/duckdb/duckdb.pdf) - Official R package (2026-03-26 release)
- [DuckDB R Client Documentation](https://duckdb.org/docs/stable/clients/r) - Read-only connection setup, DBI parameters
- [dbplyr SQL Translation Guide](https://dbplyr.tidyverse.org/articles/sql-translation.html) - Function translation limitations

### Secondary (MEDIUM confidence)
- [dbplyr Backend Documentation](https://dbplyr.tidyverse.org/articles/dbplyr.html) - `tbl_dbi` and lazy evaluation patterns
- [DuckDB SQL Backend for dbplyr](https://r.duckdb.org/reference/backend-duckdb.html) - DuckDB-specific optimizations
- [Chapter 9: Lazy Evaluation and Lazy Queries](https://smithjd.github.io/sql-pet/chapter-lazy-evaluation-queries.html) - Best practices for lazy queries
- [duckplyr Memory Protection](https://duckplyr.tidyverse.org/articles/prudence.html) - Materialization strategies

### Tertiary (LOW confidence, flagged for validation)
- [DuckDB SEMI JOIN Issue #19213](https://github.com/duckdb/duckdb/issues/19213) - Performance concern (unverified if fixed in 1.5.1)
- [DuckDB read_only flag Issue #1088](https://github.com/duckdb/duckdb-r/issues/1088) - Historical bug (may be fixed)

## Metadata

**Confidence breakdown:**
- Standard stack: MEDIUM - Package versions verified via CRAN, but features not tested in project context yet
- Architecture: MEDIUM - Patterns verified via dbplyr/DuckDB docs, but custom predicate translation unknown until smoke test
- Pitfalls: MEDIUM - Documented in dbplyr/DuckDB issues and Stack Overflow, but project-specific impacts TBD

**Research date:** 2026-04-23
**Valid until:** 2026-05-23 (30 days; dbplyr/duckdb are stable, but DuckDB releases frequently)
