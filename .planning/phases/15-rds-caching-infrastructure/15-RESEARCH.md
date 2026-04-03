# Phase 15: RDS Caching Infrastructure - Research

**Researched:** 2026-04-03
**Domain:** R data serialization, file-based caching, modification time comparison
**Confidence:** HIGH

## Summary

RDS caching for PCORnet CSV tables is a well-established R pattern with proven time savings. The core approach: serialize loaded data frames with `saveRDS()`, compare source CSV vs RDS modification times with `file.mtime()`, and load from cache with `readRDS()` if RDS is newer. Attributes attached to data frames (like CSV parse time) are preserved through serialization, enabling time-savings calculations. Performance benchmarks show RDS reads are 10-20x faster than CSV parsing, with vroom CSV parsing taking 10-30 seconds for multi-GB files vs 1-3 seconds for RDS loads.

**Primary recommendation:** Extend `load_pcornet_table()` with cache-check logic before vroom call, store CSV parse time as `attr(df, "csv_parse_seconds")`, and log `[CACHE HIT]` vs `[CSV PARSE]` with time comparisons using `system.time()` or `tictoc::tic()/toc()`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01: Store original CSV parse time as an attr() on the RDS object**
- Store as `attr(df, "csv_parse_seconds")`
- `readRDS()` preserves attributes, so on cache hit retrieve this value and log: `"ENROLLMENT: 0.4s (cache) vs 18.7s (CSV) -- saved 18.3s"`
- Zero extra metadata files

**D-02: Use file modification time (file.mtime()) comparison only**
- RDS newer than source CSV = cache hit
- No schema hashing or code version tracking
- If pipeline code changes (new validation columns, new date parsing logic), user sets `FORCE_RELOAD <- TRUE` once to rebuild all caches
- This is an exploratory pipeline — the user knows when code changes

**D-03: Cache TUMOR_REGISTRY_ALL (combined TR1+TR2+TR3 table)**
- Cache as separate RDS file alongside individual TR table caches
- Keeps consistency — all loaded tables have corresponding RDS files

**D-04: Skip post-load diagnostic logging on cache hits**
- Post-load diagnostics (PROVIDER specialty sample, LAB_RESULT_CM null rate) are informational and useful on first load to verify data
- Noisy on repeat runs; cache hit means data is already trusted
- Log only `[CACHE HIT]` per table

**D-05: Use .rds format (not .RData)**
- `readRDS()` returns a single named object directly into assignment — no namespace side-effects
- (Decided during v1.1 roadmapping)

**D-06: Cache directory is /blue/erin.mobley-hl.bcu/clean/rds/raw/**
- Large binary files stay on blue storage, outside the repo root, gitignored
- (Decided during v1.1 roadmapping)

### Claude's Discretion

- Cache directory creation logic (auto-create with `dir.create(recursive = TRUE)` if missing, or error)
- Console log formatting details (colors, separators, alignment)
- Whether to store additional metadata in RDS attributes beyond parse time (e.g., row count, load timestamp)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CACHE-01 | After each raw PCORnet table is loaded and validated, serialize it to `.rds` in `/blue/erin.mobley-hl.bcu/clean/rds/raw/` with consistent naming (e.g., `ENROLLMENT.rds`, `DIAGNOSIS.rds`) | `saveRDS()` serialization with compression; naming pattern matches `PCORNET_TABLES` vector |
| CACHE-02 | At pipeline startup, check if `.rds` exists and is newer than source CSV — load from `.rds` via `readRDS()` if so, log `[CACHE HIT]` vs `[CSV PARSE]` per table | `file.exists()` + `file.mtime()` comparison pattern; `readRDS()` for deserialization |
| CACHE-03 | `FORCE_RELOAD` flag in `00_config.R` (default `FALSE`) bypasses cache and re-parses all CSVs when set to `TRUE` | Boolean flag in `CONFIG` list; conditional logic wraps cache check |
| CACHE-04 | Log wall-clock time saved per table when loading from cache vs CSV | `system.time()` or `tictoc::tic()/toc()` for timing; `attr(df, "csv_parse_seconds")` for original parse time |
| GIT-01 | Add `/blue/erin.mobley-hl.bcu/clean/` to `.gitignore` | Append line to existing `.gitignore` file |
| GIT-02 | Add comment in `00_config.R` next to `CACHE_DIR` noting it is gitignored and must not be a repo-internal path | Inline comment in R config file |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| base R | 4.4.2+ | saveRDS/readRDS, file.mtime, file.exists | Built-in serialization; zero dependencies; preserves attributes and metadata automatically |
| glue | 1.8.0+ | String formatting for console logs | Already in project stack (STACK.md); consistent with existing `message(glue(...))` pattern in `load_pcornet_table()` |
| vroom | 1.7.0+ | CSV loading (existing) | Already in project; used in existing `load_pcornet_table()` function |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| tictoc | 1.2.1+ | Timing measurement (optional) | Alternative to `system.time()` for cleaner timing logs; already popular in R data pipelines |
| fs | 1.7.0+ | Cross-platform file operations (optional) | Modern alternative to base `file.exists()`, `dir.create()`; not required for this phase |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| saveRDS() | arrow::write_parquet() | Parquet is 5-10x smaller and faster, but adds dependency not in current stack; RDS is sufficient for v1 |
| file.mtime() | tools::md5sum() for content hashing | Content hash is more rigorous (detects actual changes vs timestamp), but slower and unnecessary for exploratory pipeline where user controls FORCE_RELOAD |
| system.time() | tictoc::tic()/toc() | tictoc is more readable for nested timings, but system.time() is built-in; both work |

**Installation:**
Already installed via Phase 1. No new packages required for core functionality.

**Version verification:**
```bash
# In R console (already available on HiPerGator via renv.lock)
packageVersion("glue")   # 1.8.0
packageVersion("vroom")  # 1.7.0
```

Optional (if timing with tictoc instead of system.time()):
```r
install.packages("tictoc")  # Version 1.2.1 (Dec 2025 release)
```

## Architecture Patterns

### Recommended Cache Directory Structure
```
/blue/erin.mobley-hl.bcu/clean/
└── rds/
    ├── raw/                       # Phase 15: raw table caches
    │   ├── ENROLLMENT.rds
    │   ├── DIAGNOSIS.rds
    │   ├── PROCEDURES.rds
    │   ├── PRESCRIBING.rds
    │   ├── ENCOUNTER.rds
    │   ├── DEMOGRAPHIC.rds
    │   ├── TUMOR_REGISTRY1.rds
    │   ├── TUMOR_REGISTRY2.rds
    │   ├── TUMOR_REGISTRY3.rds
    │   ├── TUMOR_REGISTRY_ALL.rds  # Combined TR table
    │   ├── DISPENSING.rds
    │   ├── MED_ADMIN.rds
    │   ├── LAB_RESULT_CM.rds
    │   └── PROVIDER.rds
    ├── cohort/                    # Phase 16: cohort snapshots (out of scope)
    └── outputs/                   # Phase 16: figure/table backing data (out of scope)
```

### Pattern 1: Cache-Check Logic in load_pcornet_table()
**What:** Check for cached RDS before loading CSV; use `file.mtime()` to compare timestamps
**When to use:** Every table load unless `FORCE_RELOAD = TRUE`
**Example:**
```r
# Pseudocode structure (not final implementation)
load_pcornet_table <- function(table_name, file_path, col_spec, cache_dir = NULL, force_reload = FALSE) {
  # 1. Build cache path
  cache_path <- file.path(cache_dir, paste0(table_name, ".rds"))

  # 2. Cache check (if caching enabled and not force reload)
  if (!is.null(cache_dir) && !force_reload && file.exists(cache_path)) {
    csv_mtime <- file.mtime(file_path)
    rds_mtime <- file.mtime(cache_path)

    if (rds_mtime > csv_mtime) {
      # CACHE HIT: load from RDS
      start_time <- Sys.time()
      df <- readRDS(cache_path)
      load_seconds <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

      original_parse_seconds <- attr(df, "csv_parse_seconds")
      time_saved <- original_parse_seconds - load_seconds

      message(glue("[CACHE HIT] {table_name}: {round(load_seconds, 1)}s (cache) vs {round(original_parse_seconds, 1)}s (CSV) — saved {round(time_saved, 1)}s"))
      return(df)
    }
  }

  # 3. CSV PARSE: load from source (existing vroom logic)
  start_time <- Sys.time()
  df <- vroom(file_path, col_types = col_spec, ...)  # existing code
  # ... existing date parsing, validation logic ...
  parse_seconds <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  # 4. Cache write (if caching enabled)
  if (!is.null(cache_dir)) {
    attr(df, "csv_parse_seconds") <- parse_seconds
    saveRDS(df, cache_path, compress = TRUE)
    message(glue("[CSV PARSE] {table_name}: {round(parse_seconds, 1)}s — cached to {basename(cache_path)}"))
  } else {
    message(glue("Loaded {table_name}: {format(nrow(df), big.mark=',')} rows, {ncol(df)} columns"))
  }

  return(df)
}
```

### Pattern 2: CONFIG List Extension for Cache Settings
**What:** Add cache directory path and force reload flag to `CONFIG` list in `00_config.R`
**When to use:** Once during Phase 15 implementation
**Example:**
```r
CONFIG <- list(
  # ... existing entries ...

  # RDS cache settings (Phase 15)
  # IMPORTANT: cache_dir is GITIGNORED — must not be a repo-internal path
  # See .gitignore: /blue/erin.mobley-hl.bcu/clean/ is excluded
  cache = list(
    cache_dir = "/blue/erin.mobley-hl.bcu/clean/rds/raw",
    force_reload = FALSE   # Set to TRUE to bypass cache and re-parse all CSVs
  )
)
```

### Pattern 3: Cache Directory Auto-Creation
**What:** Create cache directory if it doesn't exist before first write
**When to use:** Once before first `saveRDS()` call
**Example:**
```r
# Before first cache write
if (!is.null(CONFIG$cache$cache_dir) && !dir.exists(CONFIG$cache$cache_dir)) {
  dir.create(CONFIG$cache$cache_dir, recursive = TRUE, showWarnings = FALSE)
  message(glue("Created cache directory: {CONFIG$cache$cache_dir}"))
}
```

### Pattern 4: TUMOR_REGISTRY_ALL Caching
**What:** Cache the combined TUMOR_REGISTRY_ALL table after `bind_rows(TR1, TR2, TR3)`
**When to use:** After combining individual TR tables in main loading block
**Example:**
```r
# After existing TUMOR_REGISTRY_ALL binding logic (lines 517-531 in 01_load_pcornet.R)
if (!is.null(CONFIG$cache$cache_dir) && !CONFIG$cache$force_reload) {
  tr_all_cache_path <- file.path(CONFIG$cache$cache_dir, "TUMOR_REGISTRY_ALL.rds")

  # Store metadata and cache
  attr(pcornet$TUMOR_REGISTRY_ALL, "csv_parse_seconds") <-
    sum(c(attr(pcornet$TUMOR_REGISTRY1, "csv_parse_seconds"),
          attr(pcornet$TUMOR_REGISTRY2, "csv_parse_seconds"),
          attr(pcornet$TUMOR_REGISTRY3, "csv_parse_seconds")), na.rm = TRUE)

  saveRDS(pcornet$TUMOR_REGISTRY_ALL, tr_all_cache_path, compress = TRUE)
  message(glue("Cached TUMOR_REGISTRY_ALL to {basename(tr_all_cache_path)}"))
}
```

### Anti-Patterns to Avoid

- **Caching before validation:** Don't cache before date parsing and numeric validation. Cached data must be analysis-ready.
- **Relative cache paths:** Don't use `file.path("cache", ...)`. HiPerGator SLURM jobs change working directory; use absolute paths.
- **RData instead of RDS:** `save()` and `load()` pollute namespace; `saveRDS()` and `readRDS()` are explicit.
- **Manual timestamp checking:** Don't build custom timestamp comparison logic. `file.mtime()` returns POSIXct objects that compare directly with `>` operator.
- **Caching NULL returns:** If `load_pcornet_table()` returns NULL (file not found), don't cache it.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File modification time comparison | Custom stat() wrapper, manual timestamp parsing | `file.mtime()` (base R) | Returns POSIXct object; handles all OS differences; compares directly with `>` |
| Timing measurements | Manual `Sys.time()` subtraction with timezone edge cases | `system.time()` or `tictoc::tic()/toc()` | system.time() handles CPU vs elapsed time; tictoc handles nested timings |
| Cache directory creation | Nested `if (!dir.exists()) dir.create()` loops | `dir.create(recursive = TRUE)` | Handles all parent directories in one call (Unix `mkdir -p` equivalent) |
| Attribute preservation | Separate metadata CSV or JSON sidecar files | `attr(df, "key") <- value` with saveRDS/readRDS | Attributes serialize automatically with object; zero extra files |

**Key insight:** R's serialization preserves attributes and metadata automatically. No need for external metadata tracking. CSV parse time, load timestamp, row counts, etc. can all be stored as attributes and retrieved after `readRDS()` with zero manual bookkeeping.

## Common Pitfalls

### Pitfall 1: Forgetting to Create Cache Directory
**What goes wrong:** `saveRDS()` fails with "cannot open the connection" error if parent directory doesn't exist.
**Why it happens:** R doesn't auto-create parent directories for file writes (unlike `dir.create(recursive = TRUE)`).
**How to avoid:** Create cache directory with `dir.create(cache_dir, recursive = TRUE)` before first write. Use `showWarnings = FALSE` to suppress "already exists" warnings on subsequent runs.
**Warning signs:** Error message containing "cannot open the connection" or "No such file or directory" when calling `saveRDS()`.

### Pitfall 2: Caching Before Validation/Transformation
**What goes wrong:** Cache contains raw vroom output before date parsing and numeric validation. Cache hits skip validation steps, producing inconsistent data.
**Why it happens:** Natural temptation to cache immediately after `vroom()` to avoid re-parsing.
**How to avoid:** Cache AFTER all transformations (date parsing, validation flag columns, diagnostic logging). The cached object should be identical to what the pipeline uses downstream.
**Warning signs:** Missing `_VALID` columns on cache hits; dates still character type on cache hits; validation logging appears on CSV parse but not on cache hits.

### Pitfall 3: Comparing Timestamps with == Instead of >
**What goes wrong:** Cache never hits because exact timestamp match is nearly impossible; or cache hits when CSV is newer (data staleness).
**Why it happens:** Misunderstanding of cache invalidation logic — need "RDS newer than CSV" not "RDS same age as CSV".
**How to avoid:** Use `rds_mtime > csv_mtime` for cache validation. If RDS modification time is strictly greater, cache is valid.
**Warning signs:** Cache never hits (always re-parsing CSV) despite RDS files existing; or cache hits when CSV was updated (stale data).

### Pitfall 4: Not Handling Missing CSV Gracefully
**What goes wrong:** `file.mtime()` errors on non-existent CSV files; pipeline crashes instead of logging warning and skipping table.
**Why it happens:** Cache check happens before the existing `file.exists(file_path)` guard in `load_pcornet_table()`.
**How to avoid:** Check CSV existence BEFORE cache check. If CSV doesn't exist, return NULL (existing pattern).
**Warning signs:** Error message "cannot open file '..._Mailhot_V1.csv'" instead of existing graceful "WARNING: TABLE_NAME not found. Skipping."

### Pitfall 5: Forgetting to Update .gitignore
**What goes wrong:** Large RDS files (100MB-2GB each, 13+ files) get staged for git commit. Git becomes unusable due to file size.
**Why it happens:** .gitignore exclusion not added before first RDS write.
**How to avoid:** Add `/blue/erin.mobley-hl.bcu/clean/` to `.gitignore` BEFORE running pipeline with caching enabled (GIT-01). Document in CONFIG comment (GIT-02).
**Warning signs:** `git status` shows `.rds` files in "untracked files" list; git operations become slow.

### Pitfall 6: FORCE_RELOAD Not Bypassing Cache Completely
**What goes wrong:** Setting `FORCE_RELOAD <- TRUE` rebuilds some caches but not TUMOR_REGISTRY_ALL or skips cache writes.
**Why it happens:** Inconsistent force_reload checks across different code sections (main loading block vs TR_ALL binding logic).
**How to avoid:** Pass `force_reload` parameter from CONFIG to all cache-related logic. Both cache reads AND cache writes should check `force_reload`.
**Warning signs:** After `FORCE_RELOAD <- TRUE`, some tables still show `[CACHE HIT]`; or caches rebuild but new RDS files not written.

## Code Examples

Verified patterns from R documentation and community best practices:

### Example 1: Basic saveRDS/readRDS with Attributes
```r
# Source: R base documentation (readRDS help)
# https://stat.ethz.ch/R-manual/R-devel/library/base/html/readRDS.html

# Save with attributes
df <- data.frame(x = 1:5, y = letters[1:5])
attr(df, "creation_time") <- Sys.time()
attr(df, "csv_parse_seconds") <- 12.3
saveRDS(df, "example.rds", compress = TRUE)

# Load and verify attributes preserved
df2 <- readRDS("example.rds")
attr(df2, "csv_parse_seconds")  # Returns: 12.3
identical(df, df2)  # Returns: TRUE
```

### Example 2: File Modification Time Comparison
```r
# Source: R Markdown Cookbook - 14.9 A more transparent caching mechanism
# https://bookdown.org/yihui/rmarkdown-cookbook/cache-rds.html

csv_file <- "data.csv"
rds_file <- "data.rds"

# Check if cache is valid (RDS newer than CSV)
cache_valid <- file.exists(rds_file) &&
               file.exists(csv_file) &&
               file.mtime(rds_file) > file.mtime(csv_file)

if (cache_valid) {
  data <- readRDS(rds_file)
} else {
  data <- read.csv(csv_file)
  saveRDS(data, rds_file)
}
```

### Example 3: Timing with system.time()
```r
# Source: Multiple R timing guides
# https://www.alexejgossmann.com/benchmarking_r/

# Approach 1: system.time() wrapper
time_result <- system.time({
  df <- vroom("large_file.csv", col_types = cols(...))
})
parse_seconds <- time_result["elapsed"]

# Approach 2: Manual Sys.time() diff (more flexible for logging)
start <- Sys.time()
df <- vroom("large_file.csv", col_types = cols(...))
parse_seconds <- as.numeric(difftime(Sys.time(), start, units = "secs"))
```

### Example 4: dir.create with recursive = TRUE
```r
# Source: R base documentation (files2 help)
# https://stat.ethz.ch/R-manual/R-devel/library/base/html/files2.html

cache_dir <- "/blue/erin.mobley-hl.bcu/clean/rds/raw"

# Safe directory creation (like mkdir -p)
if (!dir.exists(cache_dir)) {
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
}

# recursive = TRUE creates all parent directories
# showWarnings = FALSE suppresses "already exists" warnings
```

### Example 5: Conditional Cache Logic Pattern
```r
# Source: Common R data pipeline pattern
# Adapted from rOpenSci pkgreport cache.R
# https://rdrr.io/github/ropenscilabs/pkgreport/src/R/cache.R

load_with_cache <- function(csv_path, rds_path, force_reload = FALSE) {
  # Guard: CSV must exist
  if (!file.exists(csv_path)) {
    warning(glue("CSV not found: {csv_path}"))
    return(NULL)
  }

  # Cache check
  use_cache <- !force_reload &&
               file.exists(rds_path) &&
               file.mtime(rds_path) > file.mtime(csv_path)

  if (use_cache) {
    message("[CACHE HIT] Loading from RDS")
    return(readRDS(rds_path))
  }

  # CSV parse
  message("[CSV PARSE] Loading from source")
  df <- read.csv(csv_path)  # Replace with vroom
  saveRDS(df, rds_path, compress = TRUE)
  return(df)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `save()` and `load()` with .RData | `saveRDS()` and `readRDS()` with .rds | R 2.13+ (2011) | RDS returns explicit object without namespace pollution; better for pipelines |
| Manual timestamp string parsing | `file.mtime()` returning POSIXct | R 2.13+ (2011) | Direct comparison with `>` operator; no string parsing edge cases |
| `compress = "gzip"` (default) | `compress = "xz"` option | R 2.10+ (2009) | xz gives 20-30% smaller files but 2-3x slower compression; gzip default is best balance |
| No built-in timing | `system.time()` built-in | R base (always available) | Zero dependencies for basic timing; tictoc (2014) adds nested timing |

**Deprecated/outdated:**
- `.RData` format for caching: Use `.rds` instead. `save()`/`load()` namespace side-effects cause hard-to-debug issues in pipelines.
- `tools::md5sum()` for cache invalidation: Overkill for exploratory pipelines. `file.mtime()` is faster and sufficient when user controls `FORCE_RELOAD`.
- `data.table::fwrite()` + `fread()` for caching: Faster than RDS for very large files (10GB+), but PCORnet tables are 100MB-2GB range where RDS is adequate.

## Open Questions

1. **Should we cache TUMOR_REGISTRY_ALL before or after it's added to pcornet list?**
   - What we know: TR_ALL is created by `bind_rows(TR1, TR2, TR3)` after individual tables load (lines 517-531)
   - What's unclear: Whether to cache immediately after binding, or integrate caching into the TR_ALL creation logic
   - Recommendation: Cache immediately after `pcornet$TUMOR_REGISTRY_ALL <- bind_rows(...)` assignment. It's a derived table, so cache separately from raw TR1/TR2/TR3 caches.

2. **Should cache directory creation fail silently or error loudly if parent directory (/blue/erin.mobley-hl.bcu/) doesn't exist?**
   - What we know: `dir.create(recursive = TRUE)` creates all parents; but if `/blue/erin.mobley-hl.bcu/` doesn't exist, it indicates wrong HiPerGator environment
   - What's unclear: Whether to auto-create all the way to `/blue/` (risky) or require `/blue/erin.mobley-hl.bcu/` to exist
   - Recommendation: Let `dir.create()` attempt creation; if it fails (permissions issue, wrong filesystem), the error message will be informative. Don't add extra validation.

3. **Should we store additional metadata attributes (load timestamp, vroom version, row count)?**
   - What we know: D-01 specifies `csv_parse_seconds` only; additional metadata is "Claude's discretion"
   - What's unclear: Whether row count, column count, load timestamp would be useful for debugging or cache invalidation
   - Recommendation: Start with `csv_parse_seconds` only (D-01). Can add more attributes in Phase 16 if needed for cohort snapshots.

## Sources

### Primary (HIGH confidence)
- [R base documentation: readRDS/saveRDS](https://stat.ethz.ch/R-manual/R-devel/library/base/html/readRDS.html) - Official R manual on serialization
- [R base documentation: file.mtime()](https://stat.ethz.ch/R-manual/R-devel/library/base/html/files2.html) - Official R manual on file operations
- [R Markdown Cookbook: Cache time-consuming code chunks](https://bookdown.org/yihui/rmarkdown-cookbook/cache.html) - Yihui Xie (RMarkdown author) on `file.mtime()` caching pattern
- [R Markdown Cookbook: Transparent caching with readRDS](https://bookdown.org/yihui/rmarkdown-cookbook/cache-rds.html) - Canonical RDS caching pattern
- [saveRDS() and readRDS() in R: Practical Guide 2026](https://thelinuxcode.com/saverds-and-readrds-in-r-a-practical-modern-guide-for-reliable-object-storage/) - Modern guide confirming attributes preservation

### Secondary (MEDIUM confidence)
- [5 ways to measure running time of R code](https://www.r-bloggers.com/2017/05/5-ways-to-measure-running-time-of-r-code/) - system.time() vs tictoc vs microbenchmark comparison
- [Comparing performances of CSV to RDS, Parquet, and Feather](https://www.r-bloggers.com/2022/05/comparing-performances-of-csv-to-rds-parquet-and-feather-file-formats-in-r/) - RDS 10x faster than CSV read; benchmarks for this use case
- [Timing in R: Best Practices for Accurate Measurements](https://supergloo.com/r-programming/timing-in-r/) - Comprehensive timing guide (2026)
- [Introduction to glue](https://cran.r-project.org/web/packages/glue/vignettes/glue.html) - Official glue package documentation for message formatting

### Tertiary (LOW confidence)
- [Speeding up Reading and Writing in R](https://www.danielecook.com/speeding-up-reading-and-writing-in-r/) - Older benchmarks (2017), but vroom vs RDS patterns still relevant
- [rOpenSci pkgreport cache.R](https://rdrr.io/github/ropenscilabs/pkgreport/src/R/cache.R) - Real-world cache pattern example (community code, not official docs)

## Metadata

**Confidence breakdown:**
- Standard stack (saveRDS/readRDS, file.mtime): HIGH - Base R functions, official documentation, mature and stable
- Architecture patterns (cache-check logic, CONFIG extension): HIGH - Direct adaptation of existing `load_pcornet_table()` patterns from codebase
- Pitfalls (caching before validation, timestamp comparison): HIGH - Verified from R Markdown Cookbook (Yihui Xie, authoritative source)
- Performance claims (10x faster RDS vs CSV): MEDIUM - Based on community benchmarks, not official vroom benchmarks; actual speedup depends on file size and disk I/O

**Research date:** 2026-04-03
**Valid until:** 2026-05-03 (30 days - stable R base functions, low churn in serialization APIs)
