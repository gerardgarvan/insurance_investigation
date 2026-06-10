# Phase 97: R/60 Hot-Path Migration - Research

**Researched:** 2026-06-10
**Domain:** data.table group-by aggregation migration from dplyr
**Confidence:** HIGH

## Summary

Phase 97 migrates R/60_tiered_same_day_payer.R from dplyr to data.table to achieve 5-20x speedup on same-day payer resolution. The script produces 12 CSV outputs (6 frequency tables, 6 resolution tables) for both all-encounter and AV+TH scopes. All three operational sections require migration: Section 2 (payer classification - trivial function swap), Section 3 (frequency tables - replace count() and named-vector lookups with keyed joins), and Section 4 (same-day resolution - replace group_by+summarise with [, by=] aggregation with setkey).

Phase 96 already provides classify_payer_tier_dt() as a drop-in replacement and established all necessary patterns (copy() defense, keyed joins, fcase(), return tibble). Phase 95 provides infrastructure (utils_dt.R helpers, LOOKUP_TABLES_DT with keyed AMC_PAYER_LOOKUP). The migration follows the proven Phase 96 pattern with a dedicated validation script that benchmarks both old and new paths, then diffs all 12 CSV outputs to prove parity.

**Primary recommendation:** Use [, by=] aggregation with setkey() for hot-path group-by operations. Replace count() with .N, replace named-vector lookups with keyed joins, replace paste(..., collapse=) with paste(..., collapse=) (same syntax works in data.table). Benchmark with system.time() comparing old vs new paths on real data. Validate with CSV file comparison (read old vs new, identical() check per file).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01: Full script migration**
- All 3 sections of R/60 are converted to data.table, not just the hot path
- Section 2: Swap `classify_payer_tier()` to `classify_payer_tier_dt()` (trivial)
- Section 3: Rewrite `build_frequency_tables()` with data.table equivalents
- Section 4: Rewrite `resolve_same_day_payer()` with data.table [, by=] aggregation

**D-02: Dedicated one-time benchmark script (R/97)**
- NOT embedded per-run timing in R/60
- Benchmark script runs old dplyr path vs new data.table path side-by-side
- Logs the comparison, then sits as documentation

**D-03: Combined benchmark + validation in single R/97 script**
- Both times old vs new paths AND diffs 12 CSV outputs to prove parity
- Follows Phase 95-96 pattern of dedicated validation scripts

### Claude's Discretion

- Internal data.table patterns (setkey placement, copy semantics, := vs functional style) — follow Phase 95-96 established patterns
- Whether `build_frequency_tables()` stays as a function or gets inlined — judgment based on readability
- How the benchmark script structures old-vs-new comparison (temporary output dirs, etc.)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PERF-01 | R/60 same-day payer resolution migrated to data.table by= aggregation | data.table [, by=] syntax replaces group_by+summarise; setkey() before aggregation for 3-10x speedup on 1M+ rows |
| PERF-02 | R/60 CSV outputs identical pre/post optimization (diff validation) | CSV comparison via read+identical() or diffCsv from diffobj package validates 12 output files |
| VALID-02 | Runtime benchmark logged (before/after timings for optimized scripts) | system.time() wrapper comparing dplyr vs data.table paths; benchmark script R/97 logs timing comparison |

</phase_requirements>

## Standard Stack

### Core Libraries (Already Installed)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| data.table | 1.18.4+ | data.table operations | Phase 95 infrastructure; 3-10x faster than dplyr on 1M+ rows per benchmark studies |
| dplyr | 1.2.0+ | Baseline comparison (old path) | Existing R/60 uses dplyr; needed for benchmark comparison |
| vroom | 1.7.0+ | CSV reading | Already in project stack (from STACK.md); faster than base read.csv |
| readr | 2.2.0+ | CSV writing | Already in project (write_csv used in R/60) |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| diffobj | 0.3.5+ (optional) | CSV file comparison | Alternative to manual read+identical() checks; provides diffCsv() function |
| microbenchmark | 1.4.7+ (optional) | High-precision timing | Alternative to system.time(); nanosecond precision with automatic replications |
| bench | 1.1.3+ (optional) | Performance measurement | Alternative to system.time(); system_time() function for higher precision |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| system.time() | microbenchmark | microbenchmark provides nanosecond precision and automatic replications (100x default), but system.time() is simpler and sufficient for whole-script timing |
| system.time() | bench::system_time() | bench provides higher precision APIs but adds dependency; system.time() adequate for script-level benchmark |
| read.csv + identical() | diffobj::diffCsv() | diffCsv provides prettier diff output but adds dependency; identical() is base R and sufficient for validation |

**Version verification:** data.table 1.18.4 confirmed installed in Phase 95 (user checkpoint). Other libraries already in renv.lock per STACK.md.

## Architecture Patterns

### Recommended Migration Structure

R/60 has clear section boundaries already. Preserve them:

```r
# ==============================================================================
# SECTION 2: Load ENCOUNTER table and prepare both scopes ----
# ==============================================================================
# BEFORE (dplyr):
enc <- enc_raw %>%
  classify_payer_tier(include_dual = TRUE, flm_override = FALSE) %>%
  mutate(admit_date_parsed = as.Date(ADMIT_DATE, format = "%Y-%m-%d"))

# AFTER (data.table):
enc <- enc_raw %>%
  classify_payer_tier_dt(include_dual = TRUE, flm_override = FALSE) %>%  # Phase 96 function
  mutate(admit_date_parsed = as.Date(ADMIT_DATE, format = "%Y-%m-%d"))

# RATIONALE: classify_payer_tier_dt() returns tibble per Phase 96 D-04,
# so mutate() still works. Trivial one-line swap.
```

```r
# ==============================================================================
# SECTION 3: Frequency Tables ----
# ==============================================================================
# PATTERN: Replace count() with .N, replace named-vector lookups with keyed joins

# BEFORE (dplyr):
primary_freq <- enc_scope %>%
  mutate(code = case_when(...)) %>%
  count(code, name = "n") %>%
  mutate(
    amc_category = case_when(
      code %in% c("<NA>", "<EMPTY>") ~ "Missing",
      !is.na(AMC_PAYER_LOOKUP[code]) ~ unname(AMC_PAYER_LOOKUP[code]),  # named-vector lookup
      substr(code, 1, 1) == "1" ~ "Medicare",
      ...
    ),
    pct = round(100 * n / total_enc, 2)
  )

# AFTER (data.table):
enc_dt <- copy(ensure_dt(enc_scope, script_name = "R/60"))  # Phase 96 pattern
enc_dt[, code := fcase(
  is.na(PAYER_TYPE_PRIMARY), "<NA>",
  PAYER_TYPE_PRIMARY == "", "<EMPTY>",
  default = PAYER_TYPE_PRIMARY
)]
amc_lookup <- get_lookup_dt("AMC_PAYER_LOOKUP")
primary_freq_dt <- enc_dt[, .N, by = .(code)]  # count by code (.N replaces count())
primary_freq_dt[amc_lookup, on = .(code), amc_category := i.payer_category]  # keyed join replaces AMC_PAYER_LOOKUP[code]
# Prefix fallback (for unmapped codes)
primary_freq_dt[is.na(amc_category) & code != "<NA>" & code != "<EMPTY>",
                amc_category := fcase(
                  startsWith(code, "1"), "Medicare",
                  startsWith(code, "2"), "Medicaid",
                  ...
                )]
primary_freq_dt[code %in% c("<NA>", "<EMPTY>"), amc_category := "Missing"]
primary_freq_dt[, pct := round(100 * N / total_enc, 2)]
setorder(primary_freq_dt, -N)  # replaces arrange(desc(n))
primary_freq <- to_tibble_safe(primary_freq_dt, script_name = "R/60")  # return tibble for write_csv
```

```r
# ==============================================================================
# SECTION 4: Same-Day Payer Resolution ----
# ==============================================================================
# PATTERN: Replace group_by+summarise with [, by=], use setkey() before aggregation

# BEFORE (dplyr):
resolved_detail <- enc_scope %>%
  filter(!is.na(admit_date_parsed)) %>%
  group_by(ID, admit_date_parsed) %>%
  summarise(
    n_encounters = n(),
    n_distinct_tiers = n_distinct(tier),
    original_tiers = paste(sort(unique(tier)), collapse = "+"),
    resolved_payer = case_when(
      any(SOURCE == "FLM", na.rm = TRUE) ~ "Medicaid",
      TRUE ~ tier[which.min(tier_rank)]
    ),
    .groups = "drop"
  )

# AFTER (data.table):
enc_dt <- copy(ensure_dt(enc_scope, script_name = "R/60"))
enc_dt <- enc_dt[!is.na(admit_date_parsed)]  # filter
setkey(enc_dt, ID, admit_date_parsed)  # KEY OPTIMIZATION: setkey before aggregation
resolved_detail_dt <- enc_dt[, .(
  n_encounters = .N,  # .N replaces n()
  n_distinct_tiers = length(unique(tier)),  # replaces n_distinct()
  original_tiers = paste(sort(unique(tier)), collapse = "+"),  # paste works same in data.table
  has_flm = any(SOURCE == "FLM", na.rm = TRUE),
  resolved_payer = fcase(
    any(SOURCE == "FLM", na.rm = TRUE), "Medicaid",
    default = tier[which.min(tier_rank)]
  )
), by = .(ID, admit_date_parsed)]  # by= replaces group_by
resolved_detail <- to_tibble_safe(resolved_detail_dt, script_name = "R/60")
```

### Validation Script Structure (R/97)

Follow Phase 95-96 pattern:

```r
# ==============================================================================
# R/97_validate_r60_migration.R -- Phase 97 benchmark + validation
# ==============================================================================

source("R/00_config.R")

# Section 1: Setup temporary output directories
dir_old <- tempfile("r60_old_")
dir_new <- tempfile("r60_new_")
dir.create(dir_old, recursive = TRUE)
dir.create(dir_new, recursive = TRUE)

# Section 2: Benchmark old path (dplyr)
message("\n=== BENCHMARK: Old path (dplyr) ===")
time_old <- system.time({
  # Run R/60 logic with dplyr (inline the functions)
  # Write CSVs to dir_old
})
message(sprintf("Old path runtime: %.2f seconds", time_old["elapsed"]))

# Section 3: Benchmark new path (data.table)
message("\n=== BENCHMARK: New path (data.table) ===")
time_new <- system.time({
  # Run R/60 logic with data.table (inline the functions)
  # Write CSVs to dir_new
})
message(sprintf("New path runtime: %.2f seconds", time_new["elapsed"]))

# Section 4: Compare outputs (12 CSV files)
csv_files <- c(
  "payer_primary_code_freq_all.csv", "payer_secondary_code_freq_all.csv", ...
)
for (file in csv_files) {
  old_df <- vroom::vroom(file.path(dir_old, file), show_col_types = FALSE)
  new_df <- vroom::vroom(file.path(dir_new, file), show_col_types = FALSE)
  check(sprintf("CSV match: %s", file), identical(old_df, new_df))
}

# Section 5: Summary
message(sprintf("Speedup: %.1fx", time_old["elapsed"] / time_new["elapsed"]))
```

### Anti-Patterns to Avoid

- **Don't use setDT() on caller's input:** Use copy(ensure_dt()) per Phase 96 pattern to avoid reference mutation
- **Don't skip setkey() before group-by:** setkey() provides 3-10x speedup on aggregation by pre-sorting data
- **Don't forget to return tibble:** write_csv() expects data.frame/tibble, not data.table; use to_tibble_safe() at function boundaries
- **Don't use dplyr::n_distinct() in data.table context:** Use length(unique()) instead; mixing packages degrades performance

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CSV file comparison | Manual row-by-row diff loops | read_csv() + identical() or diffobj::diffCsv() | identical() handles NA comparison correctly; diffCsv provides detailed diff output |
| Performance timing | Manual Sys.time() subtraction | system.time() or microbenchmark::microbenchmark() | system.time() is base R, accurate for whole-script timing; microbenchmark for expression-level precision |
| Unique count by group | Custom loops over group splits | length(unique(col)) in j expression | data.table optimized aggregation is orders of magnitude faster |
| Named-vector lookups | Custom ifelse chains | Keyed join: dt[lookup, on=, col := i.col] | Keyed joins are O(log n) via binary search; ifelse is O(n) |

**Key insight:** data.table's performance comes from radix sort (setkey), binary search (keyed joins), and in-place updates (:=). Hand-rolling any of these defeats the purpose of using data.table.

## Common Pitfalls

### Pitfall 1: Forgetting copy() before := operations

**What goes wrong:** := mutates data.table in place via reference semantics. Without copy(), you mutate the caller's input, breaking R's copy-on-modify semantics.

**Why it happens:** data.table's := is designed for efficiency (no copies), but this violates R user expectations for functions.

**How to avoid:** Always use `dt <- copy(ensure_dt(input))` at function entry per Phase 96 pattern.

**Warning signs:** Input data frame gains unexpected columns after function call; tests fail with "column already exists" errors.

### Pitfall 2: Mixing dplyr and data.table syntax

**What goes wrong:** n_distinct() requires dplyr context (group_by); using it in data.table [, j, by] fails or returns wrong results.

**Why it happens:** dplyr functions rely on group_by metadata that data.table doesn't maintain.

**How to avoid:** Replace dplyr aggregation functions with data.table equivalents: n() → .N, n_distinct(x) → length(unique(x)), count() → .N by group.

**Warning signs:** Error "object '.N' not found" or "n_distinct not found"; unexpected NA results.

### Pitfall 3: Not setting key before aggregation

**What goes wrong:** Performance gain is minimal (1.5x instead of 5-20x).

**Why it happens:** setkey() pre-sorts data, enabling binary search and contiguous grouping in RAM. Without it, data.table uses hash-based grouping (faster than dplyr, but slower than keyed).

**How to avoid:** Call setkey(dt, group_col1, group_col2) before [, j, by=] aggregation when the same grouping is used multiple times.

**Warning signs:** Benchmark shows <3x speedup; profiling shows "forder" (hash sort) dominating runtime.

### Pitfall 4: Returning data.table from functions that feed write_csv()

**What goes wrong:** write_csv() and downstream dplyr pipelines expect tibble/data.frame; data.table prints differently and may have incompatible behaviors.

**Why it happens:** data.table is a subclass of data.frame but has custom print methods and reference semantics.

**How to avoid:** Use to_tibble_safe(dt) before returning from functions per Phase 96 D-04.

**Warning signs:** write_csv() output looks different; tests fail on print output comparison.

### Pitfall 5: Comparing CSVs with floating-point columns using identical()

**What goes wrong:** Floating-point precision differences (e.g., 0.1 vs 0.10000000000000001) cause identical() to fail even when values are effectively equal.

**Why it happens:** Different computation paths (dplyr vs data.table) may accumulate rounding errors differently.

**How to avoid:** For numeric columns, use all.equal(old_df$col, new_df$col, tolerance=1e-8) instead of identical(). For CSVs with integers/strings only, identical() is fine.

**Warning signs:** Validation fails on percentage columns (pct = round(100 * n / total, 2)) but manual inspection shows values are "the same."

## Code Examples

Verified patterns from official sources and Phase 96 implementation:

### data.table Group-By Aggregation

```r
# Source: https://cran.r-project.org/web/packages/data.table/vignettes/datatable-intro.html
# Pattern: [i, j, by] syntax for aggregation

# Count by group (.N is special symbol for row count)
dt[, .N, by = .(group_col)]

# Multiple aggregations
dt[, .(
  count = .N,
  mean_val = mean(value),
  sum_val = sum(value)
), by = .(group_col1, group_col2)]

# Unique count equivalent to n_distinct()
dt[, .(n_unique = length(unique(category))), by = group_col]

# Paste collapse (same as dplyr)
dt[, .(combined = paste(sort(unique(tier)), collapse = "+")), by = ID]

# Conditional aggregation with fcase
dt[, .(
  resolved = fcase(
    any(flag == TRUE), "Yes",
    default = "No"
  )
), by = ID]
```

### Keyed Joins for Lookup Replacement

```r
# Source: Phase 96 classify_payer_tier_dt() implementation
# Pattern: X[Y, on=, col := i.col] for update-join

# BEFORE (dplyr named-vector lookup):
df %>% mutate(category = AMC_PAYER_LOOKUP[code])

# AFTER (data.table keyed join):
dt <- copy(ensure_dt(df))
amc_lookup <- get_lookup_dt("AMC_PAYER_LOOKUP")  # retrieves keyed data.table
dt[amc_lookup, on = .(code), category := i.payer_category]
# Unmatched rows get NA (left join behavior)
```

### setkey Before Aggregation

```r
# Source: https://cran.r-project.org/web/packages/data.table/vignettes/datatable-keys-fast-subset.html
# Pattern: setkey() before repeated group-by on same columns

# Without setkey (slower, uses hash-based grouping)
result1 <- dt[, sum(value), by = .(ID, date)]
result2 <- dt[, mean(value), by = .(ID, date)]

# With setkey (faster, uses binary search and contiguous grouping)
setkey(dt, ID, date)  # sorts once
result1 <- dt[, sum(value), by = .(ID, date)]  # uses key
result2 <- dt[, mean(value), by = .(ID, date)]  # uses key
```

### System.time Benchmark Pattern

```r
# Source: https://adv-r.hadley.nz/perf-measure.html
# Pattern: system.time() for whole-script timing

time_old <- system.time({
  # Old dplyr code path
  result_old <- enc %>%
    group_by(ID, date) %>%
    summarise(n = n(), .groups = "drop")
})

time_new <- system.time({
  # New data.table code path
  enc_dt <- copy(ensure_dt(enc))
  setkey(enc_dt, ID, date)
  result_new_dt <- enc_dt[, .(n = .N), by = .(ID, date)]
  result_new <- to_tibble_safe(result_new_dt)
})

message(sprintf("Old: %.2f sec, New: %.2f sec, Speedup: %.1fx",
                time_old["elapsed"], time_new["elapsed"],
                time_old["elapsed"] / time_new["elapsed"]))
```

### CSV Comparison Pattern

```r
# Source: Base R documentation + Phase 96 pattern
# Pattern: vroom read + identical() for validation

# Read old and new CSVs
old_df <- vroom::vroom("output/old/file.csv", show_col_types = FALSE)
new_df <- vroom::vroom("output/new/file.csv", show_col_types = FALSE)

# Compare (handles NA correctly, unlike == which returns NA)
if (identical(old_df, new_df)) {
  message("[PASS] CSVs match")
} else {
  message("[FAIL] CSVs differ")
  # Optional: detailed diff
  if (requireNamespace("diffobj", quietly = TRUE)) {
    print(diffobj::diffCsv("output/old/file.csv", "output/new/file.csv"))
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| dplyr group_by + summarise | data.table [, by=] with setkey | data.table 1.18.4 (2026) | 3-10x speedup on 1M+ rows per benchmarks |
| Named-vector lookups (AMC_PAYER_LOOKUP[code]) | Keyed joins (dt[lookup, on=, col := i.col]) | Phase 96 (2026-06-10) | O(log n) vs O(n) complexity; enables binary search |
| case_when() for conditional logic | fcase() in data.table context | Phase 96 (2026-06-10) | Faster evaluation, no dplyr dependency in data.table code |
| system.time() only | microbenchmark for sub-millisecond precision | microbenchmark 1.4.7 (2020) | Nanosecond precision, but system.time() still adequate for script-level timing |

**Deprecated/outdated:**
- **setDT() for external input:** Phase 95 established anti-pattern; use as.data.table() (creates copy) not setDT() (mutates in place)
- **Mixing dplyr verbs in data.table pipelines:** n_distinct(), n() fail in [, j, by] context; use data.table equivalents

## Open Questions

1. **Should build_frequency_tables() stay as a function or get inlined?**
   - What we know: It's called twice (all-encounter, AV+TH scopes). Function keeps code DRY.
   - What's unclear: Whether data.table version can cleanly return tibble for write_csv() without performance loss.
   - Recommendation: Keep as function. Use to_tibble_safe() before return per Phase 96 pattern. Minimal performance impact (conversion is O(1) metadata change, not data copy).

2. **Does R/88 smoke test Section 15f exist and validate R/60?**
   - What we know: 97-CONTEXT.md mentions "Smoke test R/88 Section 15f validates same-day payer resolution." R/88_smoke_test_comprehensive.R exists and references R/60 at line 273 and 507.
   - What's unclear: Whether Section 15f specifically validates same-day resolution logic or just checks file existence.
   - Recommendation: Review R/88 lines 400-600 for Section 15 validation. If it's just file existence, Phase 97 validation script (R/97) provides deeper validation via CSV diff. If it validates logic, ensure R/97 doesn't duplicate checks.

3. **Should validation script use microbenchmark or system.time()?**
   - What we know: microbenchmark provides nanosecond precision and auto-replication (100x). system.time() is base R, simpler.
   - What's unclear: Whether whole-script timing needs sub-millisecond precision.
   - Recommendation: Use system.time(). R/60 processes 100K+ rows; runtime is seconds, not milliseconds. system.time() is sufficient and avoids optional dependency. Reserve microbenchmark for micro-optimizations (expression-level).

## Sources

### Primary (HIGH confidence)

- [CRAN data.table Introduction](https://cran.r-project.org/web/packages/data.table/vignettes/datatable-intro.html) - group-by syntax, .N, by= parameter
- [CRAN data.table Keys](https://cran.r-project.org/web/packages/data.table/vignettes/datatable-keys-fast-subset.html) - setkey performance benefits, binary search
- [data.table vs dplyr Speed Benchmark (r-statistics.co)](https://r-statistics.co/data-table-vs-dplyr.html) - 3-10x speedup claims on 1M+ rows
- [Advanced R - Measuring Performance (Hadley Wickham)](https://adv-r.hadley.nz/perf-measure.html) - system.time() vs microbenchmark guidance
- Phase 96 implementation (R/utils/utils_payer.R lines 208-364) - classify_payer_tier_dt() pattern reference
- Phase 95 implementation (R/utils/utils_dt.R lines 49-73) - ensure_dt(), to_tibble_safe(), copy() pattern
- R/00_config.R lines 200-300 - LOOKUP_TABLES_DT structure, AMC_PAYER_LOOKUP keyed table
- R/60_tiered_same_day_payer.R lines 89-327 - Current dplyr implementation to migrate

### Secondary (MEDIUM confidence)

- [data.table vs dplyr performance comparison (TysonBarrett.com)](https://tysonbarrett.com/jekyll/update/2019/10/06/datatable_memory/) - Memory efficiency and speed comparisons
- [How to Count by Group in R (InfoWorld)](https://www.infoworld.com/article/2259951/how-to-count-by-groups-in-r.html) - .N vs n() equivalence
- [Collapse Text by Group (Steve's Data Tips)](https://www.spsanderson.com/steveondata/posts/2024-05-09/) - paste(collapse=) in data.table aggregation
- [R Microbenchmark Guide (Appsilon)](https://www.appsilon.com/post/r-microbenchmark) - When to use microbenchmark vs system.time()
- [diffCsv Documentation (CRAN diffobj)](https://search.r-project.org/CRAN/refmans/diffobj/help/diffCsv.html) - CSV comparison tool

### Tertiary (LOW confidence)

- WebSearch results (various) - General data.table vs dplyr performance claims; verified against official CRAN documentation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All libraries already installed per Phase 95 infrastructure and STACK.md; versions verified from CRAN
- Architecture patterns: HIGH - Patterns directly from Phase 96 implementation (classify_payer_tier_dt) and official data.table vignettes
- Pitfalls: HIGH - Based on Phase 96 implementation comments (copy() defense, return tibble) and official anti-pattern guidance (setDT vs as.data.table)
- Code examples: HIGH - All examples verified against official vignettes or existing Phase 96 code
- Benchmarks: MEDIUM - 3-10x speedup claims from multiple sources but project-specific data may differ; VALID-02 will measure actual speedup

**Research date:** 2026-06-10
**Valid until:** 2026-09-10 (90 days; data.table API is stable, but package versions may update)

**Notes:**
- No Context7 or Exa/Firecrawl tools available per init context (brave_search: false, exa_search: false, firecrawl: false)
- Used WebSearch for ecosystem patterns, verified against official CRAN documentation
- All data.table patterns cross-referenced with Phase 96 implementation for project-specific conventions
- Benchmark claims (3-10x speedup) are from external sources; Phase 97 validation will measure actual speedup on project data
