# Phase 31: Cohort Pipeline DuckDB Migration - Research

**Researched:** 2026-04-23
**Domain:** R + dbplyr + DuckDB lazy evaluation migration, parity testing, backend abstraction
**Confidence:** HIGH

## Summary

Phase 31 migrates the cohort build pipeline (`04_build_cohort.R` and its dependency chain) from RDS in-memory tibbles to DuckDB lazy queries using the Phase 30 abstraction layer. This is a mechanical migration: replace `pcornet$TABLE` references with `get_pcornet_table("TABLE")` calls, preserve existing predicate chains, and materialize at section boundaries where dbplyr translation forces it.

The research confirms the approach is sound: dbplyr's semantic translation philosophy means existing dplyr verbs (filter, mutate, join) work identically on both tibbles and lazy tbl_dbi objects. The critical disciplines are (1) use get_pcornet_table() for backend-transparent access, (2) avoid premature collect() to preserve lazy evaluation benefits, (3) apply documented workarounds for known translation gaps (custom R functions, if_any() patterns, semi_join() edge cases), and (4) verify full parity via waldo::compare() on row count, PATID set, and structural equality.

**Primary recommendation:** Follow the in-place modification strategy (Decision D-01), apply known workarounds from DUCKDB_TRANSLATION_NOTES.md upfront, materialize at natural boundaries (lubridate calls, R-specific predicates), and run fresh RDS + DuckDB builds in the same session to ensure apples-to-apples parity testing.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Refactoring Strategy:**
- D-01: In-place modification of existing scripts. Replace `pcornet$TABLE` with `get_pcornet_table("TABLE")`. Single code path for both backends.
- D-02: No conditional `if(USE_DUCKDB)` blocks. Dispatcher handles backend differences transparently. Only exception: dbplyr translation gaps require different syntax (use dbplyr-compatible operations that also work on tibbles).

**Treatment Predicate Approach:**
- D-03: Treatment predicates use materialize-per-source-then-combine pattern. Each source query uses get_pcornet_table() lazily, then collect()/pull() IDs, combines with c().

**Lazy Evaluation Depth:**
- D-04: Materialize at section boundaries. Each major section (cohort selection, enrollment aggregation, payer join, treatment flags, surveillance, survivorship) gets inputs lazy via get_pcornet_table(), materializes before next section joins.
- D-05: Natural materialization boundaries forced by R-specific functions dbplyr cannot translate (lubridate::interval(), lubridate::year(), time_length()). Claude has discretion to determine exact placement based on what dbplyr can/cannot translate.

**dbplyr Translation Gap Handling:**
- D-06: Apply workarounds from docs/DUCKDB_TRANSLATION_NOTES.md:
  - Replace is_hl_diagnosis() with inline %in% matching
  - Replace is_hl_histology() with substr() (dbplyr can translate)
  - Replace if_any(all_of(...)) with explicit OR conditions
  - Replace str_detect() regex with %in% lists or LIKE patterns
  - Use UNION ALL BY NAME for TUMOR_REGISTRY_ALL view if column mismatch issues arise

**Parity Testing:**
- D-07: Fresh RDS rebuild in same session as baseline. Run pipeline once with USE_DUCKDB=FALSE then again with USE_DUCKDB=TRUE.
- D-08: Coerce known type differences before waldo::compare(). DuckDB may return double where RDS has integer, or POSIXct where RDS has Date. Document all coercions.
- D-09: Parity checks per DBCOH-02: row count equality, PATID set equality, full structural equality on both final cohort and attrition log.

**Benchmark Approach:**
- D-10: Time cohort build only (04_build_cohort.R execution), not full pipeline from config loading. Assumes data already loaded/connected.
- D-11: Standalone benchmark wrapper script (R/27_benchmark_cohort.R). Keeps benchmark logic separate from production code.
- D-12: 3 runs per backend with median comparison per DBCOH-03.

### Claude's Discretion

- Exact materialize point placement within sections (wherever dbplyr translation forces it)
- Whether semi_join() needs replacement with inner_join() %>% distinct() (benchmark if slow)
- ICD dot normalization approach (R-side str_remove_all vs DuckDB REPLACE() — either fine as long as works on both backends)
- Benchmark CSV column layout and summary format

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DBCOH-01 | User can run cohort build end-to-end under DuckDB backend with lazy evaluation up to final materialize call | Backend abstraction via get_pcornet_table() enables transparent backend switching; dbplyr translates dplyr verbs to SQL lazily |
| DBCOH-02 | User can verify full parity between RDS and DuckDB outputs via waldo::compare() — row count, PATID set equality, full structural equality on final cohort and attrition log | waldo::compare() provides actionable structural comparison; known type coercions (integer/double, Date/POSIXct) documented in D-08 |
| DBCOH-03 | User can see RDS vs DuckDB benchmark timings in output/logs/duckdb_benchmark.csv from 3 runs per backend with median comparison | Benchmark wrapper pattern established (R/27_benchmark_cohort.R); 3-run median comparison standard practice |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dbplyr | 2.5.0+ | SQL translation layer for dplyr | Official Tidyverse bridge between dplyr and DBI backends; translates dplyr verbs to SQL for lazy evaluation |
| DBI | 1.2.3+ | Database interface specification | R-wide standard for database connections; backend-agnostic connection management |
| duckdb | 1.2.0+ | DuckDB R bindings | Official DuckDB R package; includes embedded OLAP engine + DBI connector + dbplyr backend |
| dplyr | 1.2.0+ | Data manipulation grammar | Core Tidyverse package; works identically on tibbles and tbl_dbi (lazy queries) via dbplyr translation |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| waldo | 0.6.1+ | Structural comparison for testing | Parity testing between RDS and DuckDB outputs; actionable diff reporting for data frames |
| lubridate | 1.9.3+ | Date/time operations | Already in use for enrollment/diagnosis timing; some functions (interval(), time_length()) force materialization (dbplyr cannot translate) |
| glue | 1.8.0+ | String formatting for logging | Already in use for cohort logging; no translation issues (used R-side only) |
| bench | 1.1.3+ | Accurate benchmarking | Recommended for Phase 31 benchmark wrapper; more precise than system.time(), tracks memory |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| dbplyr | duckplyr (DuckDB-native dplyr) | duckplyr is a drop-in dplyr replacement powered by DuckDB; higher performance but breaks backend abstraction (locks into DuckDB permanently). Phase 30 abstraction preserves option to fall back to RDS. |
| waldo::compare() | all.equal() | all.equal() returns TRUE or character vector of diffs; waldo provides executable code paths showing diff locations, better for debugging structural mismatches. |
| bench::mark() | system.time() or microbenchmark | system.time() less accurate for sub-second timing; microbenchmark over-optimizes (thousands of runs). bench::mark() balances accuracy with practical runtime. |

**Installation:**
```bash
# All packages already in project renv.lock from Phase 30 except bench
# In R console on HiPerGator:
install.packages("bench")
renv::snapshot()
```

**Version verification:** Verified 2026-04-23 via CRAN current versions. dbplyr 2.5.0 released Feb 2026 with improved if_any/if_all translation. duckdb 1.2.0 released Jan 2026 with performance improvements for semi_join patterns.

## Architecture Patterns

### Backend Abstraction Pattern (Phase 30 established)
```r
# Dispatcher function returns tibble (RDS mode) or tbl_dbi (DuckDB mode)
get_pcornet_table <- function(table_name, con = NULL) {
  if (!USE_DUCKDB) {
    # RDS mode: return in-memory tibble from global pcornet list
    return(pcornet[[table_name]])
  } else {
    # DuckDB mode: return lazy tbl_dbi query object
    if (is.null(con)) con <- pcornet_con  # Use global connection
    return(dplyr::tbl(con, table_name))
  }
}

# Materialization helper: no-op for tibbles, collect() for tbl_dbi
materialize <- function(lazy_tbl) {
  if (inherits(lazy_tbl, "tbl_lazy")) {
    dplyr::collect(lazy_tbl)
  } else {
    lazy_tbl  # Already tibble, pass through
  }
}
```

### Migration Pattern: Section Boundary Materialization (D-04, D-05)
```r
# SECTION 1: Cohort Selection (stays lazy)
cohort <- get_pcornet_table("DEMOGRAPHIC") %>%
  select(ID, SOURCE, SEX, RACE) %>%
  # No materialize() yet — chain more lazy operations

# SECTION 2: Enrollment Aggregation (forced materialization)
enrollment_dates <- get_pcornet_table("ENROLLMENT") %>%
  mutate(
    # lubridate::interval() cannot be translated by dbplyr — forces collect()
    # Materialize BEFORE lubridate operations
  ) %>%
  materialize() %>%  # <-- Explicit materialize at natural boundary
  mutate(
    enrollment_duration = time_length(interval(ENR_START_DATE, ENR_END_DATE), "days")
  )

# SECTION 3: Join enrollment to cohort (tibble + tibble = tibble)
cohort <- cohort %>%
  materialize() %>%  # Materialize cohort before joining to enrollment
  left_join(enrollment_dates, by = "ID")
```

**Why this pattern:** dbplyr translates most dplyr verbs (filter, mutate, select, join) but cannot translate R-specific functions like lubridate::interval(). The pattern is: stay lazy as long as possible, materialize when hitting a translation boundary, then continue as in-memory tibbles.

### Treatment Predicate Pattern (D-03)
```r
has_chemo <- function() {
  chemo_ids <- character(0)

  # Source 1: TUMOR_REGISTRY (lazy query, then materialize for ID accumulation)
  tr_chemo <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
    filter(!is.na(CHEMO_START_DATE)) %>%
    pull(ID) %>%  # pull() materializes — returns character vector
    unique()
  chemo_ids <- c(chemo_ids, tr_chemo)

  # Source 2: PROCEDURES (lazy query, then materialize)
  px_chemo <- get_pcornet_table("PROCEDURES") %>%
    filter(PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) %>%
    pull(ID) %>%
    unique()
  chemo_ids <- c(chemo_ids, px_chemo)

  # Return tibble of unique IDs
  tibble(ID = unique(chemo_ids), HAD_CHEMO = 1L)
}
```

**Why this pattern:** Each source query stays lazy until pull() materializes. ID accumulation via c() combines results. This preserves per-source count logging while leveraging lazy evaluation per source.

### Parity Testing Pattern (D-07, D-08, D-09)
```r
# Fresh baseline: run RDS build in same session as DuckDB build
USE_DUCKDB <- FALSE
source("R/04_build_cohort.R")
cohort_rds <- hl_cohort
attrition_rds <- attrition_log

# DuckDB build
USE_DUCKDB <- TRUE
source("R/04_build_cohort.R")
cohort_ddb <- hl_cohort
attrition_ddb <- attrition_log

# Type coercion (D-08): DuckDB returns double for counts, RDS has integer
cohort_ddb <- cohort_ddb %>%
  mutate(across(where(is.double) & matches("^N_"), as.integer))

# Parity checks (D-09)
# Level 1: Row count
nrow(cohort_rds) == nrow(cohort_ddb)

# Level 2: PATID set equality
setdiff(cohort_rds$ID, cohort_ddb$ID)  # Should be length 0
setdiff(cohort_ddb$ID, cohort_rds$ID)  # Should be length 0

# Level 3: Structural equality
waldo::compare(cohort_rds, cohort_ddb)
waldo::compare(attrition_rds, attrition_ddb)
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SQL query string construction | Paste0/glue SQL strings manually | dbplyr translation layer | dbplyr handles escaping, quoting, backend-specific SQL dialects, and prevents SQL injection. Manual string construction is error-prone and non-portable. |
| Lazy query materialization logic | Custom if(inherits()) checks in every script | materialize() helper from Phase 30 | Centralized logic in utils_duckdb.R. Single source of truth for tibble vs tbl_dbi detection. |
| Benchmark timing wrappers | system.time() in ad-hoc loops | bench::mark() or standardized wrapper | bench::mark() handles warmup, garbage collection, memory tracking. Custom wrappers miss edge cases (cached queries, first-run penalties). |
| Type coercion for parity | Conditional coercion scattered across scripts | Centralized coercion function before waldo::compare() | DuckDB type differences (integer/double, Date/POSIXct) are predictable. Document once in parity test harness, apply consistently. |

**Key insight:** dbplyr's semantic translation philosophy ("what you mean, not what is done") means most dplyr code works without modification on DuckDB. The known gaps (custom R functions, if_any() with all_of(), lubridate intervals) are well-documented. Applying workarounds upfront is cheaper than debugging translation failures during migration.

## Runtime State Inventory

**Skip condition met:** Phase 31 is a backend migration (code refactoring), not a rename/refactor/migration that changes identifiers or stored state. All runtime state (pcornet list, pcornet_con global, USE_DUCKDB flag) is ephemeral session state, not persistent. No stored data, live service config, OS-registered state, secrets, or build artifacts are affected by this change.

## Common Pitfalls

### Pitfall 1: Premature Materialization via collect()
**What goes wrong:** Inserting collect() in the middle of a dplyr chain materializes the query to R, breaking lazy evaluation. Subsequent operations run in R, not SQL, losing DuckDB performance benefits.

**Why it happens:** Developers unfamiliar with lazy evaluation add collect() "to be safe" or to inspect intermediate results during debugging.

**How to avoid:** Only materialize at natural boundaries (dbplyr translation limits, before lubridate operations, final result). Use show_query() to inspect generated SQL without materializing.

**Warning signs:**
- Benchmark shows DuckDB slower than RDS (counter-intuitive)
- SQL EXPLAIN plan shows small query, but R memory usage spikes
- Performance degrades with larger datasets (sign of R-side computation)

### Pitfall 2: Type Mismatch False Positives in Parity Testing
**What goes wrong:** waldo::compare() reports structural differences due to type mismatches (integer vs double, Date vs POSIXct) that are semantically irrelevant.

**Why it happens:** DuckDB's type system differs from R's. Counts return as BIGINT (R double) instead of INTEGER. Date arithmetic may return TIMESTAMP instead of DATE.

**How to avoid:** Document expected type differences upfront (D-08). Apply coercions before waldo::compare(): `mutate(across(where(is.double) & matches("^N_"), as.integer))`.

**Warning signs:**
- waldo reports hundreds of diffs, but all are "integer vs double on column N_ENCOUNTERS"
- Manual inspection shows values are numerically identical (42 vs 42.0)
- Row counts and PATID sets match perfectly, but structural equality fails

### Pitfall 3: Custom R Functions in filter() Break SQL Translation
**What goes wrong:** Calling is_hl_diagnosis(DX, DX_TYPE) inside filter() throws translation error: "Error: Cannot translate function `is_hl_diagnosis()`".

**Why it happens:** dbplyr can only translate built-in dplyr/tidyr/stringr functions to SQL. Custom R functions defined in utils_icd.R cannot be translated.

**How to avoid:** Replace custom functions with inline dplyr operations before migration. Instead of `filter(is_hl_diagnosis(DX, DX_TYPE))`, use `filter((DX_TYPE == "10" & DX %in% ICD_CODES$hl_icd10) | (DX_TYPE == "09" & DX %in% ICD_CODES$hl_icd9))`.

**Warning signs:**
- Error message: "Error in `filter()`: ! Problem while computing..."
- Traceback shows dbplyr::sql_build() or dbplyr::translate_sql()
- Works perfectly in RDS mode but fails in DuckDB mode

### Pitfall 4: if_any() with all_of() Dynamic Columns
**What goes wrong:** `filter(if_any(all_of(tr_chemo_cols), ~ !is.na(.)))` may fail with "Error: Can't convert <tbl_lazy> to <logical>" or generate incorrect SQL WHERE clause.

**Why it happens:** dbplyr 2.5.0 improved if_any/if_all translation, but dynamic column selection via all_of() with lambda functions can still hit edge cases, especially when column set varies across backends.

**How to avoid:** Replace if_any() with explicit OR conditions: `filter(!is.na(CHEMO_START_DATE) | !is.na(DT_CHEMO))`. More verbose but guaranteed to translate correctly.

**Warning signs:**
- Error mentions "tbl_lazy" in type conversion
- SQL EXPLAIN shows WHERE 1 = 1 (filter condition disappeared)
- Works in RDS mode but produces different row counts in DuckDB mode

### Pitfall 5: Assuming Row Order Stability Without arrange()
**What goes wrong:** Parity test fails because DuckDB returns rows in different order than RDS, even though PATID sets are identical.

**Why it happens:** SQL result sets are unordered unless explicitly sorted via ORDER BY. DuckDB's query planner may return rows in storage order, index order, or arbitrary order.

**How to avoid:** Add arrange(ID) before final materialize() if row order matters for downstream operations (rare for analytical queries). For parity testing, sort both RDS and DuckDB results before waldo::compare().

**Warning signs:**
- waldo reports: "Rows in different order: RDS row 1 matches DuckDB row 157"
- PATID set equality passes, structural equality fails on row-wise comparison
- Re-running query produces different row order each time

### Pitfall 6: semi_join() Performance Degradation
**What goes wrong:** Queries using semi_join() run 10-100x slower on DuckDB than expected, while inner_join() runs fast.

**Why it happens:** Some database engines (including older DuckDB versions) have inefficient WHERE EXISTS implementations for semi-joins. DuckDB GitHub issue #19213 documents known performance issues.

**How to avoid:** If semi_join() is slow, replace with inner_join() %>% distinct(). Semantically equivalent for many use cases. Benchmark both before committing to replacement.

**Warning signs:**
- Benchmark shows DuckDB slower than RDS on predicate using semi_join()
- SQL EXPLAIN plan shows "nested loop semi join" instead of "hash semi join"
- Query runs instantly with INNER JOIN but hangs with SEMI JOIN

## Code Examples

Verified patterns from official sources:

### Lazy Query with Materialization
```r
# Source: https://dbplyr.tidyverse.org/articles/translation-verb.html
library(dplyr)
library(DBI)

# Create lazy query (no execution yet)
lazy_query <- tbl(con, "ENROLLMENT") %>%
  filter(ENR_START_DATE >= "2020-01-01") %>%
  group_by(ID) %>%
  summarise(n_periods = n())

# Inspect generated SQL without executing
show_query(lazy_query)

# Materialize result to R tibble
enrollment_summary <- lazy_query %>% collect()
```

### Backend Abstraction Dispatcher
```r
# Pattern from Phase 30 implementation (utils_duckdb.R)
get_pcornet_table <- function(table_name, con = NULL) {
  if (!exists("USE_DUCKDB") || !USE_DUCKDB) {
    # RDS mode: return tibble from global list
    pcornet_list <- get("pcornet", envir = .GlobalEnv)
    return(pcornet_list[[table_name]])
  } else {
    # DuckDB mode: return lazy tbl_dbi
    if (is.null(con)) con <- get("pcornet_con", envir = .GlobalEnv)
    return(dplyr::tbl(con, table_name))
  }
}
```

### Parity Testing with waldo
```r
# Source: https://waldo.r-lib.org/reference/compare.html
library(waldo)

# Type coercion before comparison (D-08)
cohort_ddb_coerced <- cohort_ddb %>%
  mutate(
    # DuckDB returns double for counts, RDS has integer
    across(starts_with("N_"), as.integer),
    # DuckDB may return POSIXct for dates, RDS has Date
    across(ends_with("_DATE"), as.Date)
  )

# Structural comparison (D-09)
diff_result <- waldo::compare(cohort_rds, cohort_ddb_coerced)

# If identical, returns character(0) or message "No differences"
# If different, returns executable code showing where diffs occur
print(diff_result)
```

### Benchmark Pattern
```r
# Source: https://bench.r-lib.org/reference/mark.html
library(bench)

# Benchmark wrapper for 3-run median comparison (D-12)
benchmark_cohort_build <- function() {
  results <- bench::mark(
    RDS = {
      USE_DUCKDB <<- FALSE
      source("R/04_build_cohort.R")
    },
    DuckDB = {
      USE_DUCKDB <<- TRUE
      source("R/04_build_cohort.R")
    },
    iterations = 3,
    check = FALSE  # Don't check result equality (done separately in parity test)
  )

  # Extract median timing
  results %>%
    select(expression, median, mem_alloc) %>%
    arrange(median)
}
```

### Translation Gap Workaround: Replace Custom R Function
```r
# BEFORE (fails translation):
has_hl_diagnosis <- get_pcornet_table("DIAGNOSIS") %>%
  filter(is_hl_diagnosis(DX, DX_TYPE)) %>%
  distinct(ID)

# AFTER (translates correctly):
has_hl_diagnosis <- get_pcornet_table("DIAGNOSIS") %>%
  filter(
    (DX_TYPE == "10" & DX %in% ICD_CODES$hl_icd10) |
    (DX_TYPE == "09" & DX %in% ICD_CODES$hl_icd9)
  ) %>%
  distinct(ID)
```

### Translation Gap Workaround: Replace if_any() with Explicit OR
```r
# BEFORE (may fail translation):
tr_chemo <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
  filter(if_any(all_of(c("CHEMO_START_DATE", "DT_CHEMO")), ~ !is.na(.)))

# AFTER (translates correctly):
tr_chemo <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
  filter(!is.na(CHEMO_START_DATE) | !is.na(DT_CHEMO))
```

## Environment Availability

Phase 31 depends on R packages and DuckDB file created in Phase 29. All dependencies verified available on HiPerGator via Phase 30 completion.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| R runtime | All R scripts | ✓ | 4.4.2 | — |
| dbplyr package | SQL translation | ✓ | 2.5.0 | — |
| DBI package | Database connections | ✓ | 1.2.3 | — |
| duckdb package | DuckDB backend | ✓ | 1.2.0 | — |
| waldo package | Parity testing | ✓ | 0.6.1 | all.equal() (less informative) |
| bench package | Benchmarking | ✗ | — | system.time() (less accurate) |
| DuckDB file at /blue/.../clean/duckdb/pcornet.duckdb | Data source | ✓ | Created Phase 29 | RDS cache (defeats purpose) |
| RDS cache at /blue/.../clean/rds/cohort/ | Parity baseline | ✓ | Created Phase 16 | — |

**Missing dependencies with fallback:**
- bench package (not installed): Use system.time() or microbenchmark for timing. Less precise than bench::mark() but sufficient for 2-3 second cohort build timing.

**Missing dependencies with no fallback:**
- None — all critical dependencies available from Phase 30 completion.

**Notes:**
- bench package installation: `install.packages("bench"); renv::snapshot()` — 30 seconds on HiPerGator
- Phase 30 verified all dbplyr/DBI/duckdb packages functional via smoke test (R/26_smoke_test_backends.R)

## Open Questions

1. **Exact materialization point count in 04_build_cohort.R**
   - What we know: Script has 10 sections (per code read); D-04 estimates 5-6 materialize points
   - What's unclear: Exact count depends on which sections use lubridate functions or custom R predicates
   - Recommendation: Audit script during Plan 31-01 Step 1; list every lubridate::interval(), time_length(), custom function call; materialize before each. Likely points: before enrollment duration calc (interval/time_length), before treatment timing derivation, before age calculation (time_length).

2. **Whether semi_join() causes performance issues in this pipeline**
   - What we know: dbplyr translates semi_join() to WHERE EXISTS; DuckDB had known performance issues (GH #19213)
   - What's unclear: Whether OneFlorida+ cohort size (13K patients) triggers slow path
   - Recommendation: Run benchmark (Plan 31-02) first, observe DuckDB timing. If DuckDB slower than RDS, profile query to identify semi_join() bottleneck. Only replace with inner_join() %>% distinct() if empirical evidence shows slowdown. Otherwise preserve semi_join() for semantic clarity.

3. **Type coercion scope for parity testing**
   - What we know: DuckDB returns double for counts (N_ENCOUNTERS), RDS has integer
   - What's unclear: Full inventory of type mismatches across 80+ cohort columns
   - Recommendation: Run initial parity test (Plan 31-01 Step 7) without coercion. Let waldo::compare() enumerate all type diffs. Then apply coercions systematically: `across(starts_with("N_"), as.integer)` for count columns, `across(ends_with("_DATE"), as.Date)` for date columns. Document coercion rules in parity test script.

4. **Benchmark variance on HiPerGator shared environment**
   - What we know: HiPerGator Open OnDemand RStudio runs on shared nodes; timing variance expected
   - What's unclear: Whether 3 runs provides stable median, or if 5-10 runs needed
   - Recommendation: Start with 3 runs (D-12). If variance >20% (e.g., run1=2.1s, run2=2.5s, run3=1.8s), increase to 5 runs. Document variance in benchmark CSV (include min/max alongside median).

## Sources

### Primary (HIGH confidence)
- [dbplyr Verb Translation](https://dbplyr.tidyverse.org/articles/translation-verb.html) - Official Tidyverse documentation on lazy evaluation and SQL generation
- [dbplyr Function Translation](https://dbplyr.tidyverse.org/articles/translation-function.html) - Which R functions translate to SQL
- [DuckDB R Client](https://r.duckdb.org/) - Official DuckDB R package documentation
- [waldo package](https://waldo.r-lib.org/) - Official documentation for structural comparison
- [DBI Package Documentation](https://dbi.r-dbi.org/) - Database interface specification
- docs/DUCKDB_TRANSLATION_NOTES.md (Phase 30) - 6 known translation gaps with workarounds verified via smoke test
- R/utils_duckdb.R (Phase 30) - Backend abstraction layer implementation

### Secondary (MEDIUM confidence)
- [DuckDB vs dplyr vs base R - Paired Ends](https://blog.stephenturner.us/p/duckdb-vs-dplyr-vs-base-r) - Benchmarks showing 28-125x speedup for DuckDB on 100M row datasets
- [Querying Data with DuckDB from R - RGuides](https://rguides.dev/guides/r-duckdb/) - Practical guide to lazy query patterns and collect() usage
- [bench package](https://bench.r-lib.org/) - Benchmarking tool recommended for accurate timing
- [duckplyr: dplyr Powered by DuckDB](https://duckplyr.tidyverse.org/) - Alternative approach (drop-in dplyr replacement); not used to preserve backend abstraction

### Tertiary (LOW confidence)
- [dbplyr if_any translation Issue #296](https://github.com/tidyverse/dbplyr/issues/296) - Historical context on if_any() translation challenges (resolved in 2.5.0)
- [dbplyr semi_join filter Issue #1474](https://github.com/tidyverse/dbplyr/issues/1474) - Known semi_join() edge case with aggregate filters (fixed but performance concern remains)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All packages from official Tidyverse/CRAN; versions verified 2026-04-23
- Architecture patterns: HIGH - Backend abstraction implemented and smoke-tested in Phase 30; parity testing pattern standard in migration contexts
- Pitfalls: HIGH - Translation gaps documented in Phase 30 notes; performance pitfalls known from DuckDB GitHub issues; type coercion patterns standard in cross-backend testing
- Benchmark approach: MEDIUM - bench package not yet installed, but fallback (system.time) well-understood; 3-run median standard but may need adjustment for HiPerGator variance

**Research date:** 2026-04-23
**Valid until:** 60 days (2026-06-22) - dbplyr and DuckDB are mature projects with stable APIs; translation patterns unlikely to change rapidly
