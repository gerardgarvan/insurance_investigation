# Domain Pitfalls: Adding data.table to Existing Tidyverse R Pipeline

**Domain:** PCORnet R pipeline performance optimization with data.table
**Researched:** 2026-06-10

## Critical Pitfalls

Mistakes that cause incorrect results, data corruption, or major architectural issues.

### Pitfall 1: Reference Semantics Silent Mutation

**What goes wrong:** Functions that use `:=` to modify a data.table parameter silently mutate the original object in the caller's scope. Named vector lookups converted to data.table joins can unexpectedly modify lookup tables if you use `:=` instead of creating new columns.

**Example scenario:**
```r
# BEFORE: Named vector lookup (safe, copy-on-modify)
cohort$payer_category <- AMC_PAYER_LOOKUP[cohort$RAW_PAYER_TYPE]

# AFTER: data.table join attempt (DANGER if using :=)
payer_dt <- as.data.table(AMC_PAYER_LOOKUP)
setkey(payer_dt, raw_code)
cohort_dt <- as.data.table(cohort)
cohort_dt[payer_dt, payer_category := i.category]  # Modifies cohort_dt in place!

# If cohort was originally a tibble passed to a function, the caller's
# tibble is now unexpectedly a data.table with new columns
```

**Why it happens:** data.table uses reference semantics for the `:=` operator. Modifications propagate to all R variables pointing to the same object in memory. The tidyverse ecosystem assumes copy-on-modify semantics — functions don't mutate inputs.

**Consequences:**
- Smoke test (R/88) may pass locally but fail on HiPerGator if objects are reused across scripts
- Lookup tables (AMC_PAYER_LOOKUP, CODE_SUBCATEGORY_MAP) could gain extra columns
- Pipeline outputs differ between runs if intermediate objects persist in .GlobalEnv
- RDS cache invalidation logic breaks if objects mutate after mtime comparison

**Prevention:**
1. **Defensive copying at function boundaries**: Use `copy()` at the start of any function that receives a data.table and uses `:=`
   ```r
   optimize_payer_join <- function(cohort) {
     dt <- copy(cohort)  # Deep copy to avoid mutating caller's data
     # Safe to use := now
     dt[, new_col := transformation]
     return(dt)
   }
   ```

2. **Prefer returning new objects over in-place modification**: Follow tidyverse convention of `result <- function(input)` rather than modifying inputs
   ```r
   # SAFE: Return new object
   cohort_enriched <- add_payer_categories(cohort)

   # UNSAFE: Mutation hidden in function
   add_payer_categories(cohort)  # cohort now modified
   ```

3. **Never pass original config objects to data.table operations**: Convert to data.table inside optimization functions, not at config load time
   ```r
   # BAD: Config object becomes mutable data.table
   AMC_PAYER_LOOKUP_DT <- as.data.table(AMC_PAYER_LOOKUP)

   # GOOD: Convert fresh copy in each function
   payer_join <- function(cohort) {
     lookup_dt <- as.data.table(AMC_PAYER_LOOKUP, keep.rownames = "raw_code")
     # ...
   }
   ```

**Detection:**
- Before-and-after testing: `waldo::compare(input_original, input_after_function)` should show no differences if function shouldn't mutate
- Check object addresses: `data.table::address(x)` before and after — identical addresses with different content = mutation occurred
- Smoke test validation: Add Section 36 to R/88 checking `length(names(AMC_PAYER_LOOKUP))` hasn't increased

### Pitfall 2: Factor vs Character Join Mismatches

**What goes wrong:** data.table joins between factor columns (from PCORnet CSVs with vroom type inference) and character lookup keys produce `NA` matches or silent type coercion with incorrect mappings.

**Example scenario:**
```r
# PCORnet ENROLLMENT table loaded by vroom
enrollment <- vroom("ENROLLMENT.csv")  # RAW_PAYER_TYPE becomes factor

# AMC_PAYER_LOOKUP is a named character vector
payer_dt <- data.table(
  raw_code = names(AMC_PAYER_LOOKUP),    # character
  category = unname(AMC_PAYER_LOOKUP)    # character
)

# Join between factor (enrollment) and character (payer_dt)
setDT(enrollment)
enrollment[payer_dt, on = .(RAW_PAYER_TYPE = raw_code), payer_category := i.category]
# Result: Rows with factor levels missing from character keys get NA
```

**Why it happens:**
- vroom automatically converts low-cardinality character columns to factors (performance optimization)
- data.table versions prior to 1.18.2 had bugs sorting factor-to-character joins when factor levels aren't `sort()`-ed
- Version 1.18.4 (May 2026) fixed UTF-8 factor matching, but coercion behavior still differs from dplyr's character-only approach

**Consequences:**
- **Data loss**: Payer categories become `NA` for valid codes not in factor levels
- **Silent failures**: join succeeds but produces wrong results (e.g., mapping to incorrect category if factor integer codes align accidentally)
- **Inconsistent results across environments**: Local Windows (different locale) vs HiPerGator Linux may sort factor levels differently

**Prevention:**
1. **Explicit character coercion before joins**:
   ```r
   enrollment[, RAW_PAYER_TYPE := as.character(RAW_PAYER_TYPE)]
   ```

2. **Specify vroom column types to prevent factor inference**:
   ```r
   # In utils_duckdb.R get_pcornet_table() for non-DuckDB path
   vroom::vroom(
     path,
     col_types = cols(
       RAW_PAYER_TYPE = col_character(),
       RAW_PAYER_SOURCE = col_character(),
       .default = col_guess()
     )
   )
   ```

3. **Use data.table's type-safe join syntax**:
   ```r
   # Ensure both sides are character before join
   payer_dt[, raw_code := as.character(raw_code)]
   enrollment[payer_dt, on = .(RAW_PAYER_TYPE = raw_code), nomatch = NA]
   ```

4. **Validate join coverage post-optimization**:
   ```r
   # Add to smoke test or within optimization function
   missing_payers <- enrollment[is.na(payer_category), unique(RAW_PAYER_TYPE)]
   if (length(missing_payers) > 0) {
     warning("Unmapped payer codes: ", paste(missing_payers, collapse = ", "))
   }
   ```

**Detection:**
- Compare `sum(is.na(payer_category))` before and after optimization
- Check factor levels: `levels(enrollment$RAW_PAYER_TYPE)` vs `unique(names(AMC_PAYER_LOOKUP))`
- Smoke test Section: Validate no new NAs introduced in key payer/treatment columns
- Run on both Windows and Linux to catch locale-dependent sorting issues

### Pitfall 3: Downstream Tool Incompatibility (openxlsx2, ggplot2)

**What goes wrong:** Functions expecting tibbles or data.frames fail with data.tables, or produce degraded output with missing attributes (e.g., grouped tibble metadata, column labels).

**Example scenario:**
```r
# Optimized treatment episodes with data.table
episodes_dt <- data.table(...)  # Fast aggregation
episodes_dt[, treatment_line := classify_line(...)]

# openxlsx2 export (expects tibble or data.frame)
wb <- wb_workbook()
wb$add_worksheet("Episodes")
wb$add_data("Episodes", episodes_dt)
# Result: May work but lose tibble print formatting, grouped metadata
# write.xlsx() wrapper may call methods expecting data.frame attributes

# ggplot2 with data.table (usually works but edge cases exist)
ggplot(episodes_dt, aes(x = start_date, y = PATID)) + geom_point()
# Result: Works in most cases
# BUT: If episodes_dt has keys set, some geoms may sort unexpectedly
# AND: facet_wrap() may not recognize grouped_dt() metadata
```

**Why it happens:**
- data.table inherits from data.frame but has additional attributes (keys, indices, `.internal.selfref`)
- openxlsx2's `write_xlsx()` accepts "everything that can be converted into a data frame with `as.data.frame()`" but may not preserve data.table's reference semantics intent
- ggplot2 primarily uses data.frame methods; data.table's key-based ordering can interfere with geom expectations
- The pipeline's grain-labeled outputs (Phase 89) rely on `as_tibble()` for consistent sheet naming

**Consequences:**
- **Incorrect grain labels**: Phase 89's `wb$add_worksheet("episode_grain_...")` may fail if data.table print methods override expected behavior
- **Lost metadata**: Grouped tibbles (e.g., `group_by(PATID)`) lose grouping when converted to data.table, breaking downstream summarise() calls
- **Subtle visual bugs**: ggalluvial flows may render in unexpected order if data.table keys override factor levels
- **Test fixture failures**: Local testing with synthetic data (Phase 84) may pass, but HiPerGator production outputs differ

**Prevention:**
1. **Explicit conversion at I/O boundaries**:
   ```r
   # Before openxlsx2 export
   episodes_for_export <- as_tibble(episodes_dt)
   wb$add_data("Episodes", episodes_for_export)

   # Before ggplot2 (usually not needed, but defensive)
   ggplot(as.data.frame(episodes_dt), aes(...))
   ```

2. **Preserve conversion checkpoints in optimization workflow**:
   ```r
   # Pattern: Optimize with data.table, convert before return
   optimize_treatment_summary <- function(episodes_tbl) {
     dt <- as.data.table(episodes_tbl)
     # ... fast data.table operations ...
     result_dt[, summary_col := compute(...)]

     # Convert back to tibble before returning
     as_tibble(result_dt)
   }
   ```

3. **Test both tibble and data.table outputs**:
   ```r
   # In smoke test R/88 Section 36: Data.table Optimization Parity
   check("Treatment episodes tibble-compatible", inherits(episodes, "tbl_df"))
   check("No unexpected keys set", is.null(attr(episodes, "sorted")))
   ```

4. **Document conversion points in migration plan**:
   ```markdown
   Phase X script optimization map:
   - R/60: Optimize drug grouping (data.table internally, return tibble)
   - R/28: Optimize episode assembly (data.table internally, return tibble)
   - R/11: Keep as tibble (already fast, openxlsx2 dependency)
   ```

**Detection:**
- Run full pipeline end-to-end and compare `output/*.xlsx` file sizes and sheet counts
- Check for new warnings like `"Coercing data.table to data.frame"` in logs
- Validate ggplot2 outputs visually: save PNGs before/after optimization and diff
- Smoke test: `waldo::compare()` on critical output structures (columns, row counts, data types)

## Moderate Pitfalls

### Pitfall 4: NSE Variable Name Collisions in Programmatic Code

**What goes wrong:** data.table's non-standard evaluation (NSE) treats bare names inside `DT[...]` as column references, conflicting with programmatic column name construction via variables.

**Example scenario:**
```r
# Dynamic column creation in utils functions
add_category_column <- function(dt, lookup_map, key_col, output_col) {
  # FAILS: output_col is interpreted as literal column name "output_col"
  dt[, output_col := lookup_map[get(key_col)]]

  # CORRECT: Use parentheses for variable evaluation
  dt[, (output_col) := lookup_map[get(key_col)]]
}

# Multiple column operations with character vectors
treatment_cols <- c("chemo_flag", "radiation_flag", "sct_flag")
# FAILS: Tries to find column named "treatment_cols"
episodes_dt[, treatment_cols := lapply(.SD, as.integer), .SDcols = treatment_cols]

# CORRECT: Wrap in parentheses
episodes_dt[, (treatment_cols) := lapply(.SD, as.integer), .SDcols = treatment_cols]
```

**Why it happens:** data.table's NSE design optimizes for interactive use ("inside `DT[...]`, column names are variables") but requires special syntax for programmatic access. The pipeline's named predicate functions (`has_*`, `with_*`) and DRY utility functions (Phase 73) use programmatic column references.

**Prevention:**
- Use `(variable_name)` on LHS of `:=` for programmatic column names
- Use `get("col_name")` or `.SD` for RHS column references
- Test utility functions with multiple column name variations
- Document NSE requirements in function headers

**Detection:**
- Error messages: `"object 'col_var' not found"` or `"column 'col_var' not found"`
- Unit tests for utility functions with various column name inputs
- Code review: grep for `:=` without parentheses in functions with parameters

### Pitfall 5: DuckDB collect() Interactions with data.table

**What goes wrong:** Mixing DuckDB's lazy evaluation (collect()) with data.table's reference semantics creates inconsistent behavior depending on backend (USE_DUCKDB flag).

**Example scenario:**
```r
# R/28 treatment episode assembly (Phase 31 DuckDB migration)
if (USE_DUCKDB) {
  # DuckDB path: Returns tibble after collect()
  encounters <- get_pcornet_table("ENCOUNTER")  # lazy tbl_duckdb
  episodes <- encounters %>%
    filter(condition) %>%
    collect()  # Now a tibble
} else {
  # RDS path: Returns data.frame
  encounters <- readRDS("ENCOUNTER.rds")
}

# Later optimization converts to data.table
setDT(episodes)  # Works if tibble, works if data.frame
episodes[, new_col := compute()]  # Mutates in place

# PROBLEM: If USE_DUCKDB=TRUE, episodes is a local tibble (mutation OK)
#          If USE_DUCKDB=FALSE and encounters cached in .GlobalEnv, mutation propagates!
```

**Why it happens:**
- DuckDB `collect()` always returns a new tibble (no reference to source)
- RDS backend may reuse cached data.frames across scripts if not carefully scoped
- Backend abstraction (get_pcornet_table dispatcher, Phase 30) hides this difference
- Optimization changes copy behavior depending on backend

**Prevention:**
1. **Explicit copy in backend abstraction**:
   ```r
   # In utils_duckdb.R get_pcornet_table()
   if (USE_DUCKDB) {
     dplyr::collect(tbl(db_connection, table_name))
   } else {
     data.table::copy(readRDS(rds_path))  # Ensure fresh copy
   }
   ```

2. **Document mutation assumptions in optimization**:
   ```r
   # Function header comment
   # MUTATES: Input `cohort` is modified in place (data.table reference semantics)
   # REQUIRES: Caller must pass copy() if original should be preserved
   ```

3. **Parity testing between backends**:
   ```r
   # Smoke test Section 37: Backend Parity
   # Run same script with USE_DUCKDB=TRUE vs FALSE, compare outputs
   ```

**Detection:**
- Run pipeline with `USE_DUCKDB=TRUE` vs `FALSE`, diff outputs
- Check object addresses with `data.table::address()` before and after optimization
- Validate RDS cache doesn't contain mutated objects (reload from disk, compare to memory version)

### Pitfall 6: Group-by Memory Explosion with Unoptimized Aggregations

**What goes wrong:** Converting tidyverse `group_by() %>% summarise()` to data.table `[, by = ]` naively can trigger Cartesian products or n² memory allocation if join conditions are missed.

**Example scenario:**
```r
# BEFORE: dplyr same-day payer resolution (R/36)
same_day_encounters %>%
  group_by(PATID, ADMIT_DATE) %>%
  summarise(
    payer_modes = paste(unique(payer_category), collapse = ", "),
    .groups = "drop"
  )

# AFTER: data.table (NAIVE, DANGEROUS)
same_day_dt[, .(payer_modes = paste(unique(payer_category), collapse = ", ")),
            by = .(PATID, ADMIT_DATE)]
# Looks equivalent BUT...

# If same_day_dt has millions of rows and ADMIT_DATE isn't keyed/indexed,
# data.table may build full Cartesian product internally before grouping
```

**Why it happens:**
- data.table's `by` without keys/indices scans full table
- Pipeline's ENCOUNTER table on HiPerGator has 5M+ rows (per PROJECT.md context: "large PCORnet datasets")
- Phase 35's same-day payer resolution iterates over duplicate PATID+ADMIT_DATE combinations
- Missing secondary indices cause vector scans instead of binary search

**Prevention:**
1. **Set keys before group-by operations**:
   ```r
   setkey(same_day_dt, PATID, ADMIT_DATE)
   same_day_dt[, .(payer_modes = paste(unique(payer_category), collapse = ", ")),
               by = .(PATID, ADMIT_DATE)]
   ```

2. **Use secondary indices for multi-column groups**:
   ```r
   setindex(same_day_dt, PATID, ADMIT_DATE)
   # Subsequent grouping operations use index automatically
   ```

3. **Benchmark before production deployment**:
   ```r
   # Test on subset
   microbenchmark::microbenchmark(
     dplyr_version = old_summarise_logic(test_data),
     dt_version = new_dt_logic(test_data),
     times = 10
   )
   ```

**Detection:**
- Monitor memory usage with `bench::mark(memory = TRUE)`
- Log execution time for group-by operations (utils_attrition.R already logs timing)
- Compare row counts: output rows should ≤ input rows (Cartesian product produces more)

## Minor Pitfalls

### Pitfall 7: renv Snapshot with data.table Development Version

**What goes wrong:** data.table's development version (1.18.99 from GitLab) may be in renv.lock if installed during development, breaking `renv::restore()` on HiPerGator.

**Prevention:** Pin to CRAN version 1.18.4 (May 2026 stable release) in renv.lock before milestone deployment.

**Detection:** Check `renv.lock` for data.table version ≥ 1.19 or non-CRAN source before deployment.

### Pitfall 8: Named Vector Row Order Differs from Join Order

**What goes wrong:** Named vector lookups preserve input row order; data.table joins may reorder rows if keys are set.

**Prevention:** Use `setorder()` after joins to restore original PATID order for output consistency.

**Detection:** Compare `head(output$PATID, 100)` before and after optimization.

### Pitfall 9: Lost Tidylog Automatic Logging

**What goes wrong:** tidylog (Phase 15) wraps dplyr verbs to log row counts. data.table operations bypass this, losing automatic attrition logging.

**Prevention:**
- Keep utils_attrition.R manual logging for data.table operations
- Wrap data.table operations in `log_attrition_step()` calls

**Detection:** Check output logs for missing attrition step counts after optimization.

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Named vector → join migration | Pitfall 1 (reference semantics), Pitfall 2 (factor/character) | Use `copy()`, coerce to character, validate join coverage |
| Hot-path script optimization (R/60, R/28, R/36) | Pitfall 6 (group-by memory), Pitfall 5 (DuckDB interaction) | Set keys/indices, test both backends, benchmark subsets |
| Lookup table joins (AMC_PAYER_LOOKUP, CODE_SUBCATEGORY_MAP) | Pitfall 1 (mutation), Pitfall 8 (row reordering) | Never convert config to data.table globally, use `setorder()` post-join |
| Output generation (openxlsx2, ggplot2) | Pitfall 3 (downstream compatibility) | Convert to tibble before `wb$add_data()`, test visual outputs |
| Utility function refactoring (utils_payer.R, utils_treatment.R) | Pitfall 4 (NSE collisions) | Use `(var)` for programmatic `:=`, test with multiple column names |
| Smoke test validation (R/88 expansion) | All pitfalls need detection | Add Section 36-37 for optimization parity and backend consistency |

## Sources

**HIGH Confidence:**
- [data.table Reference Semantics (CRAN Vignette)](https://cran.r-project.org/web/packages/data.table/vignettes/datatable-reference-semantics.html) — Official documentation on copy() usage and mutation behavior
- [data.table Joins (CRAN Vignette)](https://cran.r-project.org/web/packages/data.table/vignettes/datatable-joins.html) — Official guide to key-based joins, NA handling, Cartesian product warnings
- [data.table NEWS.md](https://github.com/Rdatatable/data.table/blob/master/NEWS.md) — Version 1.18.2-1.18.4 bug fixes for factor joins and UTF-8 matching
- [data.table Package Documentation (CRAN, May 2026)](https://cran.r-project.org/web/packages/data.table/data.table.pdf) — Version 1.18.4 official reference
- [openxlsx2 Package Documentation (May 2026)](https://cran.r-project.org/web/packages/openxlsx2/openxlsx2.pdf) — Compatibility with data.frame variants

**MEDIUM Confidence:**
- [dtplyr: Data Table Backend for dplyr](https://dtplyr.tidyverse.org/) — Lazy evaluation patterns for mixing dplyr and data.table
- [Column Assignment and Reference Semantics (rdatatable-community)](https://rdatatable-community.github.io/The-Raft/posts/2024-02-18-dt_particularities-toby_hocking/) — Common gotchas from data.table maintainers
- [Data science: data.table and tidyverse (Hause Tutorials)](https://hausetutorials.netlify.app/0002_tidyverse_datatable) — Anti-patterns when mixing approaches
- [Waldo Package](https://waldo.r-lib.org/) — Testing verification for comparing pre/post optimization results
- [renv on HPC (NYU HPC Guide)](https://sites.google.com/nyu.edu/nyu-hpc/hpc-systems/greene/software/r-packages-with-renv) — Package management best practices

**Project-Specific Context (LOCAL):**
- `.planning/PROJECT.md` — Pipeline structure, backend abstraction, DuckDB integration, output requirements
- `R/00_config.R` — Named vector lookups (AMC_PAYER_LOOKUP, CODE_SUBCATEGORY_MAP, TREATMENT_CODES)
- `R/88_smoke_test_comprehensive.R` — Existing validation patterns to extend for optimization parity
