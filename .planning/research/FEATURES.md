# Feature Landscape: data.table Performance Optimization

**Domain:** R pipeline performance optimization for PCORnet CDM data (millions of encounter rows)
**Researched:** 2026-06-10
**Context:** Existing dplyr pipeline with ~77 numbered scripts, DuckDB backend, named vector lookups, case_when chains, group_by aggregations

## Table Stakes

Features users expect from data.table migration. Missing = optimization feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Keyed joins for lookup tables | Standard data.table optimization replacing named vector lookups (`AMC_PAYER_LOOKUP[code]`) | **Medium** | Requires converting named vectors to data.tables, setting keys via `setkey()`, switching from `lookup[key]` to `lookup_dt[dt, on="key"]` pattern. ~6 lookups: AMC_PAYER_LOOKUP, DRUG_GROUPINGS, CODE_SUBCATEGORY_MAP, TREATMENT_CODES, CANCER_SITE_MAP, TIER_MAPPING |
| In-place column updates with `:=` | Core data.table feature — eliminates copy-on-modify overhead | **Low** | Direct replacement for `mutate()`. Example: `DT[, new_col := value]` instead of `DT %>% mutate(new_col = value)`. Zero copies vs shallow copy overhead |
| `by=` aggregation replacing `group_by() %>% summarise()` | 3-10x faster on 1M+ rows via radix sort | **High** | R/60_tiered_same_day_payer.R is hot path (same-day resolution with multi-tier grouping). 368 lines, group_by ID+date then summarise with 10+ columns. Complexity: multiple grouping keys, complex conditional logic in summarise |
| `fcase()` replacing `case_when()` | Fast conditional logic (~2-4x speedup) | **Medium** | 30+ case_when calls across codebase (R/02, R/60 frequency tables, payer tier classification). fcase syntax differs: no `~`, all conditions must be logical. R/02 has 3 nested case_when in payer functions |
| `set*()` functions for metadata ops | Avoid copies when renaming/reordering columns | **Low** | `setnames()`, `setcolorder()`, `setattr()` replace rename/select operations. Minimal syntax change, large memory savings on wide tables |
| Preserve output correctness | Migration is speed-only; results must match dplyr exactly | **High** | Requires parity testing (compare pre vs post optimization outputs). Smoke test (R/88) has 35 validation sections — must all pass. Floating-point tolerance needed for aggregations |

## Differentiators

Features that set optimization apart. Not expected, but valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| `dtplyr` hybrid mode (dplyr syntax → data.table backend) | Zero-rewrite migration path: wrap existing dplyr chains in `lazy_dt()`, get 3-4x speedup | **Low** | `lazy_dt(df) %>% filter(...) %>% group_by(...) %>% as_tibble()` translates dplyr to data.table automatically. Slightly slower than native data.table but 4x faster than dplyr. Best for low-risk first pass on R/60, R/02, R/28 |
| Secondary indices (`setindex()`) | Multi-column query optimization without reordering data in RAM | **Medium** | Alternative to `setkey()` when you need fast lookups on multiple column combinations (e.g., PATID + ENCOUNTERID). 4x memory cost per index (stores row order), but no data reordering penalty |
| Rolling joins for temporal lookups | Match encounters to nearest payer enrollment period without exact date match | **High** | `roll=TRUE` or `roll="nearest"` in joins. Clinically relevant: payer at treatment date ±30 days (R/11_treatment_payer.R). Avoids manual window logic, but complex syntax and edge case handling |
| Parallel aggregation with `parallel` package | Multi-core group_by via `mclapply()` wrapping data.table ops | **High** | Splits data.table by groups, processes in parallel, combines. HiPerGator has 16 cores (SLURM allocation). Overhead from data splitting/combining — only worth it for >10M rows with heavy computation per group |
| Reference semantics for nested function calls | Functions modify data.tables in-place without `copy()` — caller sees changes | **Low** (awareness), **High** (debugging) | data.table default behavior. Must use `copy(DT)` at function entry to prevent side effects. Opposite of R/dplyr norms. Easy performance win but breaks functional programming expectations |
| `foverlaps()` for interval joins | Fast overlap detection (e.g., diagnosis date within treatment episode date range) | **Medium** | Specialized join for interval data. Relevant for R/26_treatment_episodes.R (linking diagnoses to episodes). More efficient than `filter(date >= start & date <= end)` |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Complete dplyr removal | Pipeline uses named predicates (`has_*`, `with_*`, `exclude_*`) for readability — data.table's `[i, j, by]` syntax conflicts with this core value | Hybrid approach: keep dplyr for predicate chains (R/10_cohort_predicates.R, R/14_build_cohort.R), migrate only hot paths (R/60, R/28, R/02 payer functions) to data.table |
| Global `.datatable.aware=TRUE` without scoping | data.table modifies by reference globally — breaks encapsulation in utility functions | Use `copy()` explicitly in utils/*.R functions; document reference semantics in function headers |
| Native data.table in all 77 scripts | Over-optimization. 90% of scripts process <100k rows where dplyr/data.table speed is negligible | Profile first: target ENCOUNTER-heavy scripts (R/60 = 368 lines of same-day grouping, R/02 payer harmonization, R/28 episode classification). Leave diagnostic scripts (R/30-40s) in dplyr |
| `setDT()` in-place conversion of existing tibbles | Converts data.frame/tibble to data.table **by reference** — breaks downstream code expecting tibble semantics (e.g., `[[` extraction, print methods) | Use `as.data.table()` to create copy, or scope setDT to isolated functions with clear boundaries |
| Replacing DuckDB backend with data.table-only | DuckDB provides disk-backed lazy queries for 13 PCORnet tables (some 1-5GB CSVs). data.table is in-memory only — RAM constraints on HiPerGator | Keep DuckDB for data loading (`get_pcornet_table()`), materialize to data.table only for hot-path operations (same-day resolution, payer tier classification) |
| Factor-level encoding for payer categories | data.table's factor optimization (integer storage) saves memory but adds conversion overhead for 8-category payer system with frequent joins | Keep character vectors for payer_category. Factors only help with 100+ levels; 8 levels = negligible memory savings, added complexity for joins |

## Feature Dependencies

```
Keyed joins → setkey() (must run before join)
fcase() → all conditions vectorized (no ifelse nesting allowed)
by= aggregation → := for in-place column creation (otherwise returns subset)
dtplyr hybrid → lazy_dt() wrapper → as_tibble() finalization (must bookend chain)
Rolling joins → keyed table + date column sorted (key must include date)
Reference semantics → copy() at function boundaries (prevents caller mutation)
```

## MVP Recommendation

Prioritize (highest impact, lowest risk):

1. **dtplyr hybrid on R/60** — Lowest-friction win. 3-4x speedup on 368-line same-day payer resolution with zero syntax changes beyond `lazy_dt()` wrapper. Validates data.table benefits before deeper refactoring.

2. **Keyed join conversion (AMC_PAYER_LOOKUP, TIER_MAPPING)** — R/02 and R/60 have heaviest lookup usage. Named vector lookup (`AMC_PAYER_LOOKUP[code]`) → keyed join (`amc_dt[dt, on="code"]`). Medium complexity, high frequency (called per encounter row).

3. **fcase() in payer tier classification** — R/02 `map_payer_category()`, `compute_effective_payer()`, `detect_dual_eligible()` functions have nested case_when. Direct fcase replacement (2-4x speedup), minimal syntax change.

4. **Reference semantics audit** — Review utils/utils_payer.R, utils/utils_treatment.R for functions that would benefit from `copy()` isolation. Document in function headers. Prevents silent bugs from caller mutation.

Defer:

- **by= aggregation in R/60** → High complexity (multi-column summarise with 10+ computed fields). Start with dtplyr, migrate to native data.table only if profiling shows it's still a bottleneck.

- **Rolling joins for treatment payer** → R/11 has ±30 day window logic via filter. Rolling joins are cleaner but require significant testing for edge cases (no enrollment periods, overlapping periods). Not a proven bottleneck yet.

- **Parallel aggregation** → Overhead from data splitting only pays off at >10M rows. Current ENCOUNTER table (OneFlorida HL cohort) likely <5M rows. Premature optimization.

## Migration Strategy

### Phase 1: Baseline + dtplyr (Low Risk)
- Run smoke test (R/88) to capture pre-optimization outputs
- Wrap R/60 main pipeline in `lazy_dt()` → dplyr chains → `as_tibble()`
- Verify output parity, measure speedup
- Document dtplyr pattern in CONVENTIONS.md

### Phase 2: Targeted data.table Conversion (Medium Risk)
- Convert 6 named vector lookups (AMC_PAYER_LOOKUP, DRUG_GROUPINGS, etc.) to keyed data.tables in R/00_config.R
- Update R/02 payer functions: case_when → fcase, named vector → keyed join
- Update R/60 frequency table builders: case_when → fcase
- Smoke test Section 15 (payer) + Section 20 (tier resolution) for parity

### Phase 3: Hot-Path group_by Optimization (High Risk)
- Profile R/60 same-day resolution (`resolve_same_day_payer()` function)
- If still slow after dtplyr, convert `group_by() %>% summarise()` → `DT[, .(col1 = expr1, col2 = expr2), by=.(ID, date)]`
- Handle complex conditional logic in `j` (likely need helper columns via chained `[` operations)
- Full regression test (all 35 smoke test sections)

### Phase 4: Ecosystem Integration (Stabilization)
- Document reference semantics in utils/*.R function headers
- Add `copy()` isolation where needed
- Update ARCHITECTURE.md with data.table patterns
- Benchmark report (before/after timings for R/02, R/60, R/28)

## Performance Targets

| Operation | Baseline (dplyr) | dtplyr (Phase 1) | data.table (Phase 2-3) | Data Size |
|-----------|------------------|------------------|------------------------|-----------|
| R/60 same-day resolution | ~2-5 min (estimate) | ~30-75 sec (4x faster) | ~15-30 sec (10x faster) | ~3M encounters |
| R/02 payer harmonization | ~30-60 sec (estimate) | ~10-20 sec (3x faster) | ~5-10 sec (6x faster) | ~3M encounters |
| Named vector lookup (per 1M rows) | ~500ms (match) | ~200ms (dtplyr) | ~50ms (keyed join) | 1M lookups |
| case_when (per 1M rows) | ~300ms | ~150ms (dtplyr) | ~75ms (fcase) | 1M evaluations |

**Benchmark methodology:** HiPerGator production data (Mailhot HL cohort extract 2025-09-15), 16-core SLURM allocation, USE_DUCKDB=TRUE, materialize() before data.table operations.

## Complexity vs Impact Matrix

| Complexity | High Impact | Medium Impact | Low Impact |
|------------|-------------|---------------|------------|
| **Low** | dtplyr hybrid (Phase 1), := in-place updates | setnames/setcolorder, Reference semantics docs | Factor encoding (anti-feature) |
| **Medium** | Keyed joins (6 lookups), fcase (30+ calls) | Secondary indices, foverlaps | Rolling joins (uncertain value) |
| **High** | by= aggregation (R/60) | Preserve output correctness (testing), Parallel aggregation | Complete dplyr removal (anti-feature) |

**Recommendation:** Start top-left (dtplyr + keyed joins + fcase), then decide on by= aggregation based on Phase 1 profiling results.

## Codebase-Specific Considerations

### Named Vector Lookups (6 conversions needed)

**Current pattern (R/00_config.R):**
```r
AMC_PAYER_LOOKUP <- c("1" = "Medicare", "2" = "Medicaid", ...)  # Named vector
looked_up <- AMC_PAYER_LOOKUP[effective_payer]  # Vector indexing
```

**data.table pattern:**
```r
AMC_PAYER_LOOKUP <- data.table(code = c("1", "2", ...), category = c("Medicare", "Medicaid", ...))
setkey(AMC_PAYER_LOOKUP, code)
looked_up <- AMC_PAYER_LOOKUP[data.table(code = effective_payer), category, on="code"]
```

**Affected lookups (from R/00_config.R):**
1. AMC_PAYER_LOOKUP (8 categories, ~50 codes) → R/02, R/60 frequency tables
2. DRUG_GROUPINGS (treatment type mapping) → R/28 episode classification
3. CODE_SUBCATEGORY_MAP (sub-category names) → R/57 drug grouping tables
4. TREATMENT_CODES (CPT/HCPCS/NDC lists) → R/20 treatment inventory
5. CANCER_SITE_MAP (ICD → cancer category) → R/50 cancer summary
6. TIER_MAPPING (payer tier hierarchy 1-8) → R/60 same-day resolution

### case_when Hotspots (3 functions in R/02)

**compute_effective_payer():** 3 conditions (primary_valid, secondary_valid, fallback to NA)
**detect_dual_eligible():** 4 conditions (secondary_missing, has_dual_code, cross_payer, default 0)
**map_payer_category():** 10 conditions (lookup hit, 9 prefix rules)

**Plus:** R/60 frequency tables have 2x case_when chains for PRIMARY/SECONDARY code bucketing (<NA>, <EMPTY>, actual codes) with 9-way payer category mapping.

**fcase migration gotcha:** case_when allows `TRUE ~ default`, fcase requires explicit `rep(TRUE, length(x)), default`. All conditions must be same length (vectorized).

### group_by Hotspots

**R/60 resolve_same_day_payer():**
- `group_by(ID, admit_date_parsed)`
- `summarise()` with 10+ columns: n_encounters, n_distinct_tiers, has_flm, has_special_code, paste(collapse="+"), case_when for resolved_payer, resolved_tier, dual_eligible, payer_category
- Complex conditional logic in summarise (FLM override > special code override > tier hierarchy)
- **Migration challenge:** data.table's `by=` doesn't directly support complex case_when in `j`. Likely need multi-step approach: compute intermediate columns, then final resolution.

**R/02 payer summary (patient-level mode):**
- Simpler group_by(ID) → mode(payer_category)
- Lower priority (single grouping key, simple aggregation)

## Verification Requirements

### Output Parity Tests (from smoke test R/88)
- Section 15: Payer harmonization (8 categories, dual-eligible counts)
- Section 15f: Same-day payer resolution (tier hierarchy, FLM override, special code handling)
- Section 20: Treatment episode payer assignment
- All 35 sections must pass (no new failures)

### Numeric Tolerance
- **Counts:** Exact match (integer equality)
- **Percentages:** ±0.01% tolerance (floating-point rounding in aggregations)
- **Dates:** Exact match (lubridate vs data.table date handling)

### Performance Benchmarks
- R/60 end-to-end runtime (message timestamps)
- R/02 payer harmonization runtime
- Peak memory usage (via `pryr::mem_used()` or SLURM sacct)
- DuckDB → data.table materialization overhead (monitor `materialize()` calls)

## Open Questions

1. **DuckDB integration:** Can data.table operate directly on `tbl_dbi` lazy queries, or must we always `materialize()` first? (Answer: must materialize — data.table is in-memory only)

2. **Named predicate compatibility:** Do `has_*()`, `with_*()`, `exclude_*()` functions in R/10 need data.table awareness, or can they stay dplyr-only? (Recommendation: keep dplyr — predicates are low-volume, readability-critical)

3. **dtplyr coverage:** Which dplyr verbs translate poorly to data.table via dtplyr? (Known: `case_when` translates but stays slow; `fcase` not auto-translated)

4. **Fixture compatibility:** Do hand-crafted test fixtures (20 patients, tests/fixtures/) work with data.table, or do we need data.table-specific test data? (Answer: CSVs are backend-agnostic — no changes needed)

5. **Rolling join value:** Is R/11 treatment payer (±30 day window) a proven bottleneck worth rolling join complexity? (Needs profiling data)

## Sources

### Official Documentation (HIGH confidence)
- [data.table Reference Semantics Vignette](https://cran.r-project.org/web/packages/data.table/vignettes/datatable-reference-semantics.html) — `:=` operator, set* functions, copy() usage
- [data.table Keys and Fast Subset Vignette](https://cran.r-project.org/web/packages/data.table/vignettes/datatable-keys-fast-subset.html) — setkey(), binary search joins
- [data.table Joins Vignette](https://cran.r-project.org/web/packages/data.table/vignettes/datatable-joins.html) — Keyed joins, on= syntax, rolling joins
- [CRAN data.table 1.18.4 (May 2026)](https://cran.r-project.org/web/packages/data.table/data.table.pdf) — Latest version documentation
- [dtplyr Package (Feb 2026)](https://cran.r-project.org/web/packages/dtplyr/dtplyr.pdf) — dplyr → data.table translation layer

### Benchmarks and Comparisons (MEDIUM-HIGH confidence)
- [data.table vs dplyr Performance Benchmark](https://r-statistics.co/data-table-vs-dplyr.html) — 1M row benchmark: data.table 0.041s vs dplyr 0.115s for group-by-summarise (3x speedup)
- [MetricGate: data.table vs dplyr](https://metricgate.com/blogs/data-table-vs-dplyr-r-performance/) — 3-10x faster on 1M+ rows, half the memory usage
- [TysonBarrett.com: Speed of Joins](https://tysonbarrett.com/jekyll/update/2019/10/11/speed_of_joins/) — data.table join performance analysis
- [The MockUp: Joins vs case_when](https://themockup.blog/posts/2021-02-13-joins-vs-casewhen-speed-and-memory-tradeoffs/) — fcase vs case_when performance comparison (2-4x speedup)

### Best Practices and Patterns (MEDIUM confidence)
- [Towards Data Science: data.table speed with dplyr syntax](https://towardsdatascience.com/data-table-speed-with-dplyr-syntax-yes-we-can-51ef9aaed585/) — dtplyr hybrid approach overview
- [GeeksforGeeks: Rolling Joins in data.table](https://www.geeksforgeeks.org/r-language/rolling-joins-datatable-in-r/) — Rolling join patterns for time series
- [R-bloggers: Understanding data.table Rolling Joins](https://www.r-bloggers.com/2016/06/understanding-data-table-rolling-joins/) — Medical encounter use cases for temporal joins
- [GormAnalysis: data.table Rolling Joins](https://www.gormanalysis.com/blog/r-data-table-rolling-joins/) — Practical examples with direction control

### Ecosystem Context (MEDIUM confidence)
- [rdrr.io: fcase](https://rdrr.io/cran/data.table/man/fcase.html) — Fast CASE WHEN, supports bit64/nanotime, comparable to dplyr::case_when
- [Martin Chan: Comparing dplyr and data.table](https://martinctc.github.io/blog/comparing-common-operations-in-dplyr-and-data.table/) — Common operation syntax comparison

### Project-Specific (HIGH confidence)
- C:\Users\Owner\Documents\insurance_investigation\.planning\PROJECT.md — Current pipeline state (94 phases, 99 R scripts, DuckDB backend)
- C:\Users\Owner\Documents\insurance_investigation\R\00_config.R — 6 named vector lookups identified
- C:\Users\Owner\Documents\insurance_investigation\R\02_harmonize_payer.R — 3 case_when functions, AMC_PAYER_LOOKUP usage
- C:\Users\Owner\Documents\insurance_investigation\R\60_tiered_same_day_payer.R — 368 lines, group_by same-day resolution hot path

## Confidence Assessment

| Area | Level | Reason |
|------|-------|--------|
| Keyed joins | HIGH | Official vignettes + benchmarks show 10-50x speedup over vector scan; pattern well-documented |
| fcase replacement | HIGH | Official docs confirm 2-4x speedup over case_when; syntax differences documented; no SQL translation caveat noted |
| by= aggregation | MEDIUM-HIGH | Benchmarks show 3-10x speedup on 1M+ rows; complexity of R/60's 10-column summarise with nested conditionals is project-specific risk |
| dtplyr hybrid | HIGH | Official package (tidyverse-maintained), 4x speedup documented, minimal syntax changes required |
| Reference semantics | HIGH | Core data.table feature, extensively documented; risk is cultural (breaking functional programming norms), not technical |
| Rolling joins | MEDIUM | Feature well-documented, but value for R/11 treatment payer is unproven (no profiling data showing it's a bottleneck) |
| Output parity | MEDIUM | Smoke test infrastructure exists (R/88, 35 sections); floating-point tolerance and edge case handling needs careful testing |
| Performance targets | LOW-MEDIUM | Estimates based on published benchmarks (1M row operations); actual HiPerGator timings on 3M encounter OneFlorida data not yet measured |

**Overall confidence:** MEDIUM-HIGH. Core optimizations (keyed joins, fcase, :=, dtplyr) are well-documented with proven benchmarks. Complexity risk is in R/60's multi-column group_by (requires careful migration testing) and maintaining named predicate readability (hybrid approach mitigates this). Performance targets are directionally correct but need empirical validation on production data.
