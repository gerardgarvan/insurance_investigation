# Project Research Summary

**Project:** PCORnet Payer Variable Investigation (R Pipeline) - data.table Performance Optimization
**Domain:** R pipeline optimization for healthcare data analysis (PCORnet CDM, millions of encounter rows)
**Researched:** 2026-06-10
**Confidence:** HIGH

## Executive Summary

This research evaluates adding data.table to an existing 77-script R pipeline built on tidyverse/DuckDB to optimize performance on multi-million row PCORnet datasets. The pipeline currently uses named vector lookups for payer/treatment code mapping and dplyr group_by/summarise for same-day encounter resolution, both of which become bottlenecks at scale (5M+ encounter rows on HiPerGator). data.table offers 3-10x speedups on grouped operations and 10-50x faster keyed joins versus named vector indexing.

The recommended approach is selective migration: convert lookup tables to keyed data.tables, optimize hot-path scripts (R/60 same-day payer resolution, R/28 episode classification, R/02 payer harmonization), and preserve dplyr syntax in cohort filters where readability is critical. This hybrid strategy maintains the pipeline's "named predicate" architecture (has_*, with_*, exclude_* functions) while gaining performance where it matters. The migration can proceed incrementally with full backward compatibility.

Key risks center on data.table's reference semantics (functions modify inputs in-place, breaking tidyverse copy-on-modify assumptions) and type coercion issues (factor vs character joins). These are mitigated through defensive copy() usage at function boundaries, explicit character coercion before joins, and comprehensive output parity testing against existing smoke test infrastructure (R/88, 35 validation sections).

## Key Findings

### Recommended Stack

data.table 1.18.4+ is the only new dependency needed for v3.0 performance optimization. The existing stack (tidyverse, DuckDB, ggplot2, vroom, checkmate, renv) is validated and documented in CLAUDE.md; this research focuses solely on data.table integration.

**Core technology:**
- **data.table 1.18.4+**: Fast joins (keyed binary search), in-place aggregations (radix sort-based group-by), and zero-copy updates (`:=` operator). Crossover at ~100K-1M rows; below that, dplyr performance is comparable, above it the gap grows exponentially. On 1M-row dataset: data.table group-by-summarise 0.041s vs dplyr 0.115s (2.8x faster); keyed joins 10-50x faster than named vector lookups.

**Optional (deferred to Phase 2):**
- **dtplyr 1.3.3**: Gradual migration path allowing dplyr syntax with data.table backend. Achieves 3-4x speedup with zero rewrite overhead. Useful if migration resistance emerges, but hot-path scripts should use native data.table for maximum performance.

**Explicitly rejected:**
- **collapse 2.1.7**: Advanced statistical computing package offering 10x faster aggregations than data.table on complex weighted/categorical operations. Unnecessary complexity; data.table covers all project use cases (straightforward payer frequency counts, treatment summaries, episode groupings). Would introduce third syntax paradigm (dplyr, data.table, collapse) violating simplicity.

### Expected Features

Research focused on optimization features, not product features. Key capabilities needed from data.table:

**Must have (table stakes):**
- Keyed joins replacing named vector lookups (AMC_PAYER_LOOKUP, DRUG_GROUPINGS, CODE_SUBCATEGORY_MAP, CANCER_SITE_MAP, TIER_MAPPING, TREATMENT_CODES) — 6 lookup tables totaling ~1,140 entries
- In-place column updates with `:=` eliminating copy-on-modify overhead
- `by=` aggregation replacing group_by/summarise for 3-10x speedup on R/60 same-day resolution (2M+ encounters grouped by PATID+ADMIT_DATE)
- fcase() replacing case_when() for 2-4x speedup on multi-condition logic (30+ case_when calls across R/02 payer functions, R/60 frequency tables)
- Preserve output correctness — migration is speed-only, results must match dplyr exactly (smoke test R/88 with 35 sections must all pass)

**Should have (differentiators):**
- dtplyr hybrid mode for zero-rewrite migration path on low-risk scripts
- Secondary indices (setindex()) for multi-column query optimization without data reordering
- Rolling joins for temporal lookups (payer at treatment date ±30 days in R/11) — cleaner than manual window logic but high complexity
- Reference semantics for nested function calls — performance win but breaks functional programming expectations (requires copy() discipline)

**Anti-features (explicitly avoid):**
- Complete dplyr removal — conflicts with "named predicate" readability requirement (has_*, with_*, exclude_* cohort filters)
- Global .datatable.aware=TRUE without scoping — breaks encapsulation in utility functions
- Native data.table in all 77 scripts — over-optimization (90% process <100K rows)
- Replacing DuckDB backend — data.table is in-memory only, DuckDB provides disk-backed lazy queries for 1-5GB CSVs
- Factor-level encoding for payer categories — 8-category system sees negligible memory savings, added join complexity

### Architecture Approach

Integration pattern: **convert at boundaries, preserve internals**. Do NOT rewrite entire pipeline in data.table syntax — preserve dplyr/tibble for cohort filters, low-frequency scripts, and utility functions without table operations.

**Major components:**

1. **Lookup tables (R/00_config.R)** — Convert 6 named character vectors to keyed data.tables stored in LOOKUP_TABLES_DT list. Backward compatible: named vectors remain unchanged, scripts migrate individually.

2. **utils_dt.R (new utility module)** — Centralize data.table conversion helpers: ensure_dt() for lazy conversion, to_tibble_safe() for back-conversion, get_lookup_dt() for lookup table access. Sourced only by scripts needing data.table operations (isolates from utils_payer.R which is sourced by 20+ scripts).

3. **classify_payer_tier_dt() (new function variant)** — data.table version of classify_payer_tier() in utils_payer.R using keyed joins, fcase() logic, and optional tibble return for downstream compatibility. Allows phased migration: existing classify_payer_tier() unchanged, call sites update individually.

4. **Hot-path script optimization** — R/60 same-day resolution (368 lines, group_by ID+date with 10+ summarise columns), R/28 episode classification (DRUG_GROUPINGS/CODE_SUBCATEGORY_MAP lookups), R/02 payer harmonization (3 nested case_when functions). Convert group_by/summarise to DT[, .(col = expr), by = .(key)], replace named vector lookups with keyed joins.

**Data flow changes:**
- **Before:** DuckDB → materialize() → tibble → classify_payer_tier() [named vector lookup] → tibble → group_by/summarise → tibble → write_csv()
- **After:** DuckDB → materialize() → tibble → setDT() → data.table → classify_payer_tier_dt() [keyed join] → DT[, by=] → setDF() → tibble → write_csv()

**Key change:** Single conversion at start (tibble → data.table), single conversion at end (data.table → tibble). Minimizes boundary crossings, preserves downstream compatibility with openxlsx2/ggplot2.

### Critical Pitfalls

1. **Reference semantics silent mutation** — Functions using `:=` modify inputs in-place, breaking tidyverse copy-on-modify assumptions. Smoke test may pass locally but fail on HiPerGator if objects reused across scripts. Lookup tables (AMC_PAYER_LOOKUP) could gain extra columns. **Prevention:** Defensive copy() at function boundaries, never pass original config objects to data.table operations, document reference semantics in function headers. **Detection:** waldo::compare() pre/post function calls, check data.table::address() for identical addresses with different content.

2. **Factor vs character join mismatches** — data.table joins between factor columns (PCORnet CSVs with vroom type inference) and character lookup keys produce NA matches or silent type coercion. Payer categories become NA for valid codes not in factor levels. **Prevention:** Explicit as.character() before joins, specify vroom col_types to prevent factor inference, use nomatch=NA for explicit NA handling, validate join coverage post-optimization. **Detection:** Compare sum(is.na(payer_category)) before/after, check levels(enrollment$RAW_PAYER_TYPE) vs unique(names(AMC_PAYER_LOOKUP)), run on both Windows and Linux.

3. **Downstream tool incompatibility** — openxlsx2 and ggplot2 expect tibbles/data.frames; data.table's additional attributes (keys, indices, .internal.selfref) may break grain labels (Phase 89), lose grouped tibble metadata, or cause unexpected sort order in ggalluvial flows. **Prevention:** Explicit as_tibble() before wb$add_data(), preserve conversion checkpoints in optimization workflow (optimize with data.table, return tibble), test both tibble and data.table outputs. **Detection:** Compare output/*.xlsx file sizes/sheet counts, check for "Coercing data.table to data.frame" warnings, waldo::compare() on critical output structures.

4. **DuckDB collect() interactions** — Mixing DuckDB's lazy evaluation (collect() returns new tibble) with data.table's reference semantics creates inconsistent behavior depending on USE_DUCKDB flag. RDS backend may reuse cached data.frames across scripts. **Prevention:** Explicit copy() in get_pcornet_table() backend abstraction, document mutation assumptions, parity testing between backends. **Detection:** Run with USE_DUCKDB=TRUE vs FALSE and diff outputs.

5. **Group-by memory explosion** — Converting group_by/summarise to data.table [, by=] naively can trigger Cartesian products if keys/indices are missing. ENCOUNTER table (5M+ rows) with group_by(PATID, ADMIT_DATE) may scan full table instead of binary search. **Prevention:** setkey() or setindex() before group-by operations, benchmark before production deployment, monitor memory usage with bench::mark(). **Detection:** Compare row counts (output rows should ≤ input rows), log execution time.

## Implications for Roadmap

Based on research, suggested 4-phase structure:

### Phase 95: Infrastructure Setup (Low Risk)

**Rationale:** Add data.table infrastructure without changing behavior. Ensures backward compatibility before any optimization. Validates lookup table conversion approach.

**Delivers:**
- data.table 1.18.4+ in renv.lock
- R/utils/utils_dt.R with conversion helpers (ensure_dt, to_tibble_safe, get_lookup_dt)
- LOOKUP_TABLES_DT list in R/00_config.R (6 keyed lookup tables)
- Zero behavior changes (all existing scripts run unchanged)

**Addresses:** Stack integration (data.table + existing tidyverse/DuckDB/checkmate)

**Avoids:** Pitfall 1 (reference semantics) via conditional creation (if data.table installed), preserving named vectors for backward compatibility

**Research flags:** NO RESEARCH NEEDED — standard renv package installation, additive changes only

### Phase 96: classify_payer_tier_dt() Implementation (Medium Risk)

**Rationale:** Create data.table variant of most-called utility function with correctness validation before touching hot-path scripts. Validates keyed join pattern, fcase() replacement, and conversion workflow.

**Delivers:**
- classify_payer_tier_dt() in R/utils/utils_payer.R (alongside existing dplyr version)
- Unit test comparing both versions on synthetic data (1000-row fixture)
- Smoke test section validating output parity
- Documentation of reference semantics in function header

**Uses:** LOOKUP_TABLES_DT keyed joins, fcase() for conditional logic, := for in-place mutation, optional tibble return

**Implements:** Component 3 from Architecture (payer classification utility)

**Avoids:** Pitfall 2 (factor/character joins) via explicit as.character() coercion, Pitfall 1 via copy() at function entry

**Research flags:** NO RESEARCH NEEDED — function logic mirrors existing classify_payer_tier(), data.table syntax well-documented

### Phase 97: R/60 Hot-Path Migration (Medium-High Risk)

**Rationale:** Highest-impact optimization (368-line same-day payer resolution with group_by ID+date on 2M+ encounters). Expected 5-20x speedup. Complex multi-column summarise requires careful migration testing.

**Delivers:**
- R/60_tiered_same_day_payer.R migrated to data.table group-by syntax
- CSV output parity validation (diff pre/post optimization)
- Runtime benchmark log (before/after timings)
- Updated smoke test Section 15f for same-day payer resolution

**Addresses:** Must-have "by= aggregation" feature, hot-path script optimization from architecture Component 4

**Uses:** setkey(enc_dt, PATID, ADMIT_DATE), DT[, .(n_encounters = .N, ...), by = .(PATID, ADMIT_DATE)], setDF() for tibble return

**Avoids:** Pitfall 5 (DuckDB collect() interactions) via single conversion at start, Pitfall 5 (group-by memory explosion) via setkey() before aggregation, Pitfall 3 (downstream incompatibility) via as_tibble() before CSV export

**Research flags:** POSSIBLE PHASE RESEARCH — if complex conditional logic in summarise doesn't translate cleanly to data.table [, j, by] syntax. May need multi-step approach (compute intermediate columns, then final resolution). Monitor during implementation; trigger /gsd:research-phase if migration stalls.

### Phase 98: R/28 + Remaining Lookup Optimization (Low-Medium Risk)

**Rationale:** Replace named vector lookups in R/28 episode classification (DRUG_GROUPINGS, CODE_SUBCATEGORY_MAP) and other scripts with keyed joins. Lower complexity than R/60, isolated lookups.

**Delivers:**
- R/28_episode_classification.R with DRUG_GROUPINGS[code] → keyed join
- Remaining lookup-heavy scripts (R/02 payer harmonization if profiling shows bottleneck, R/11 treatment payer)
- Validation of treatment_episodes.rds structure unchanged (22 columns, same order)
- Smoke test Section 15 (payer) + Section 20 (episodes) validation

**Addresses:** Must-have "keyed joins for lookup tables" feature (6 lookup tables totaling ~1,140 entries)

**Uses:** DT[LOOKUP_TABLES_DT$DRUG_GROUPINGS, on = .(code), drug_group := i.treatment_type]

**Avoids:** Pitfall 1 (reference semantics) via fresh lookup copies in functions, Pitfall 8 (row reordering) via setorder() post-join if needed

**Research flags:** NO RESEARCH NEEDED — keyed join pattern validated in Phase 96, straightforward replacement

### Phase Ordering Rationale

- **Infrastructure first (Phase 95):** Validates data.table installation, lookup table conversion, backward compatibility before any behavior changes. Low risk, enables subsequent phases.

- **Utility function next (Phase 96):** classify_payer_tier_dt() is called from 10+ scripts including R/60. Must be validated before hot-path migration. Medium risk due to complex logic (dual-eligible detection, tier hierarchy), but existing function unchanged as fallback.

- **Hot-path before bulk (Phase 97):** R/60 is highest-impact optimization (same-day resolution on 2M+ encounters). Validates complex group-by migration pattern. If this succeeds, remaining scripts (R/28, R/02) follow same pattern. Medium-high risk due to 10+ column summarise with nested conditionals, but smoke test infrastructure (Section 15f) provides validation.

- **Bulk migration last (Phase 98):** Straightforward lookup replacements after pattern proven in Phase 96-97. Low-medium risk, isolated changes.

**Dependency chain:** Phase 95 (LOOKUP_TABLES_DT) → Phase 96 (classify_payer_tier_dt uses lookup tables) → Phase 97 (R/60 uses classify_payer_tier_dt) → Phase 98 (applies patterns from 96-97 to remaining scripts)

**Pitfall avoidance:**
- Phases 95-96 establish correct conversion workflow (copy() discipline, character coercion) before touching production hot paths
- Phase 97 validates complex aggregation migration before bulk rollout
- Incremental approach allows rollback at any phase without losing prior gains

**Research flags:**
- **Need deeper research:** Phase 97 only, if conditional logic in group_by/summarise doesn't translate to data.table syntax
- **Standard patterns:** Phases 95, 96, 98 — well-documented data.table installation, keyed joins, utility function patterns

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Official CRAN page verified (data.table 1.18.4, May 2026), extensive benchmarks (3-10x speedup on 1M+ rows), integration with tidyverse/DuckDB/checkmate documented |
| Features | MEDIUM-HIGH | Core optimizations (keyed joins, fcase, :=, by= aggregation) well-documented with proven benchmarks. Complexity risk in R/60's multi-column group_by requires careful migration testing. Performance targets directionally correct but need empirical validation on production HiPerGator data (3M encounters) |
| Architecture | HIGH | Boundary-conversion pattern (convert once at start/end) is established best practice. Hybrid approach (data.table hot paths, dplyr cohort filters) validated by existing pipeline structure. Component boundaries clear (lookup tables, utility functions, hot-path scripts) |
| Pitfalls | HIGH | Reference semantics, factor/character joins, downstream tool compatibility extensively documented in official vignettes and community resources. Prevention strategies proven (copy() discipline, explicit coercion, parity testing) |

**Overall confidence:** HIGH

Core recommendations (data.table 1.18.4 for keyed joins + group-by optimization, hybrid integration preserving dplyr readability, 4-phase migration) are well-supported by official documentation and independent benchmarks. Primary uncertainty is in Phase 97 (R/60 complex aggregation) where project-specific conditional logic may require multi-step data.table translation.

### Gaps to Address

**Gap 1: R/60 conditional logic complexity**
- **What's unknown:** Whether R/60's 10+ column summarise with nested case_when (FLM override > special code override > tier hierarchy) translates cleanly to data.table [, j, by] syntax
- **How to handle:** Start Phase 97 with dtplyr hybrid (lazy_dt() wrapper) for quick validation. If profiling shows it's still slow, convert to native data.table with multi-step approach (compute intermediate columns via chained [ operations, then final resolution)
- **Trigger:** If Phase 97 migration stalls >4 hours, run /gsd:research-phase "R/60 complex aggregation data.table translation patterns"

**Gap 2: HiPerGator-specific performance validation**
- **What's unknown:** Actual speedup on production HiPerGator data (3M encounters from OneFlorida HL cohort) vs benchmarks (1M row synthetic data)
- **How to handle:** Log execution times in script headers pre/post migration. Use system.time() for one-off comparisons. Validate crossover thresholds (100K-1M rows) match published benchmarks
- **Not blocking:** Benchmarks from multiple independent sources agree; production validation confirms gains but doesn't affect migration approach

**Gap 3: openxlsx2 + data.table edge cases**
- **What's unknown:** Whether openxlsx2's write_xlsx() wrapper methods handle data.table's additional attributes (keys, indices, .internal.selfref) gracefully for grain-labeled outputs (Phase 89)
- **How to handle:** Explicit as_tibble() before wb$add_data() (defensive approach). Test visual outputs during Phase 97 (save PNGs before/after, diff). If issues emerge, add to_tibble_safe() wrapper checking for/removing data.table attributes
- **Low risk:** openxlsx2 documentation states "accepts everything convertible to data.frame"; data.table inherits from data.frame

## Sources

### Primary (HIGH confidence)

**Official Documentation:**
- [data.table CRAN page](https://cran.r-project.org/web/packages/data.table/data.table.pdf) — Version 1.18.4, May 2026; keyed joins, reference semantics, fcase/fifelse, GForce optimization
- [data.table Reference Semantics Vignette](https://cran.r-project.org/web/packages/data.table/vignettes/datatable-reference-semantics.html) — `:=` operator, copy() usage, set* functions
- [data.table Keys and Fast Subset Vignette](https://cran.r-project.org/web/packages/data.table/vignettes/datatable-keys-fast-subset.html) — setkey(), binary search joins
- [data.table Joins Vignette](https://cran.r-project.org/web/packages/data.table/vignettes/datatable-joins.html) — Keyed joins, on= syntax, rolling joins, NA handling
- [dtplyr CRAN page](https://cran.r-project.org/web/packages/dtplyr/dtplyr.pdf) — Version 1.3.3, Feb 2026; dplyr to data.table translation layer
- [collapse CRAN page](https://cran.r-project.org/package=collapse) — Version 2.1.7, May 2026; advanced statistical computing (evaluated, rejected as unnecessary)
- [checkmate data.table support](https://mllg.github.io/checkmate/reference/checkDataTable.html) — assert_data_table() validation

**Performance Benchmarks:**
- [data.table vs dplyr benchmark (MetricGate)](https://metricgate.com/blogs/data-table-vs-dplyr-r-performance/) — 3-10x faster on grouped ops >1M rows
- [data.table vs dplyr (R-statistics.co)](https://r-statistics.co/data-table-vs-dplyr.html) — 1M row benchmark: 0.041s vs 0.115s (2.8x speedup)
- [data.table benchmarking guide](https://rdatatable.gitlab.io/data.table/articles/datatable-benchmarking.html) — Official performance testing methodology
- [Fast data lookups in R (R-bloggers)](https://www.r-bloggers.com/2017/03/fast-data-lookups-in-r-dplyr-vs-data-table/) — 25x improvement with keyed joins

### Secondary (MEDIUM confidence)

**Best Practices and Patterns:**
- [data.table Do's and Don'ts (GitHub Wiki)](https://github.com/Rdatatable/data.table/wiki/Do's-and-Don'ts) — Best practices, common pitfalls
- [Towards Data Science: data.table speed with dplyr syntax](https://towardsdatascience.com/data-table-speed-with-dplyr-syntax-yes-we-can-51ef9aaed585/) — dtplyr hybrid approach overview
- [Martin Chan: Comparing dplyr and data.table](https://martinctc.github.io/blog/comparing-common-operations-in-dplyr-and-data.table/) — Common operation syntax comparison
- [Column Assignment and Reference Semantics (rdatatable-community)](https://rdatatable-community.github.io/The-Raft/posts/2024-02-18-dt_particularities-toby_hocking/) — Common gotchas from data.table maintainers
- [Waldo Package](https://waldo.r-lib.org/) — Testing verification for pre/post optimization parity

**HPC and Environment:**
- [HiPerGator R Guide](https://wiki.weecology.org/docs/computers-and-programming/hipergator-reference/) — HPC R package installation
- [renv on HPC (Darya Vanichkina)](https://www.daryavanichkina.com/posts/210728_renvhpc.html) — renv installation patterns for HPC
- [renv for HPC reproducibility](https://bioinformatics.ccr.cancer.gov/docs/reproducible-r-on-biowulf/L3_PackageManagement/) — Package management best practices

**Integration Context:**
- [DuckDB and R integration (bwlewis)](https://bwlewis.github.io/duckdb_and_r/) — DuckDB + data.table workflow
- [InfoWorld: Quick lookup tables with named vectors](https://www.infoworld.com/article/2257959/do-more-with-r-quick-lookup-tables-using-named-vectors.html) — Named vector replacement rationale
- [openxlsx2 Package Documentation (May 2026)](https://cran.r-project.org/web/packages/openxlsx2/openxlsx2.pdf) — Compatibility with data.frame variants

### Project-Specific (LOCAL, HIGH confidence)

- C:\Users\Owner\Documents\insurance_investigation\.planning\PROJECT.md — Pipeline structure (77 scripts), DuckDB backend, output requirements
- C:\Users\Owner\Documents\insurance_investigation\R\00_config.R — 6 named vector lookups identified (3,443 lines total)
- C:\Users\Owner\Documents\insurance_investigation\R\02_harmonize_payer.R — 3 case_when functions, AMC_PAYER_LOOKUP usage
- C:\Users\Owner\Documents\insurance_investigation\R\60_tiered_same_day_payer.R — 368 lines, group_by same-day resolution hot path
- C:\Users\Owner\Documents\insurance_investigation\R\88_smoke_test_comprehensive.R — 35 validation sections to extend for optimization parity

---
*Research completed: 2026-06-10*
*Ready for roadmap: yes*
