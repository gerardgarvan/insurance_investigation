# Phase 16: Dataset Snapshots - Research

**Researched:** 2026-04-03
**Domain:** R data serialization, reproducible pipeline artifacts, intermediate result caching
**Confidence:** HIGH

## Summary

This phase implements systematic snapshot creation for all intermediate cohort datasets, final outputs, and visualization backing data using R's native `saveRDS()` serialization. The research confirms that R's built-in RDS format is the appropriate choice for this use case: single-object serialization with metadata preservation, platform-independent binary format, optional compression, and seamless integration with the existing Phase 15 cache infrastructure.

The implementation follows a dual-path approach: (1) inline `saveRDS()` calls in the cohort building script for filter step snapshots, and (2) a new `save_output_data()` helper utility for standardized snapshot creation in visualization scripts. This mirrors the existing `load_pcornet_table()` pattern established in Phase 15, where cache operations are abstracted into reusable functions with consistent logging.

Key finding: The project already has established patterns for RDS operations (Phase 15 caching), directory creation (`dir.create(recursive = TRUE)`), and glue-based logging messages. Phase 16 extends these patterns to cover cohort snapshots and figure/table backing data, requiring minimal new infrastructure beyond the helper function and subdirectory additions to `CONFIG$cache`.

**Primary recommendation:** Use `saveRDS(compress = TRUE)` consistently across all snapshots, leverage existing `file.path()` and `dir.create()` patterns from Phase 15, and place the `save_output_data()` helper in `R/utils_snapshot.R` following the established utility sourcing pattern.

## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Snapshot only the filter steps that change patient count: step 0 (initial population), step 1 (HL flag applied), step 2 (has enrollment), plus final cohort + attrition log. ~4-5 cohort RDS files total.
- **D-02:** Enrichment stages (payer join, treatment flags, surveillance, survivorship) do NOT get snapshots — they add columns but keep the same rows.
- **D-03:** Snapshot saving and attrition logging remain separate systems. `saveRDS()` calls are placed after existing `log_attrition()` lines. No combined wrapper.
- **D-04:** `save_output_data(df, name)` lives in a new `R/utils_snapshot.R` file, sourced by `00_config.R` alongside other utils.
- **D-05:** Helper handles: path construction from name + subdirectory, `dir.create(recursive = TRUE)` if needed, `saveRDS()`, and console logging (`"Saved: {path} ({nrow} rows, {ncol} cols)"`). No metadata attributes beyond what saveRDS stores natively.
- **D-06:** ALL visualization scripts get backing data snapshots: `05_visualize_waterfall.R`, `06_visualize_sankey.R`, `16_encounter_analysis.R`, and `11_generate_pptx.R`.
- **D-07:** For `11_generate_pptx.R`, save only the unique summary data frames that get rendered into tables (~5-8 data frames), not every slide table (some are the same data pivoted differently).
- **D-08:** For `16_encounter_analysis.R`, save backing data for all 7 figures and 2 summary tables (~9 data frames).
- **D-09:** Cohort step snapshots use numbered + descriptive names: `cohort_00_initial_population.rds`, `cohort_01_hl_flag.rds`, `cohort_02_has_enrollment.rds`, `cohort_final.rds`, `attrition_log.rds`. Numbers match build order, names match attrition log step names.
- **D-10:** Figure/table backing data mirrors the output filename with `_data` suffix: `waterfall_attrition_data.rds`, `sankey_patient_flow_data.rds`, `encounters_per_person_by_payor_data.rds`, etc. Easy to trace which `.rds` backs which figure.
- **D-11:** Use `.rds` format (not `.RData`). `readRDS()` returns a single named object. (Phase 15 D-05)
- **D-12:** Base cache directory: `/blue/erin.mobley-hl.bcu/clean/rds/`. Cohort snapshots go to `cohort/` subdirectory, figure/table backing data to `outputs/` subdirectory. (Phase 15 D-06, extended per SNAP-01/SNAP-03)

### Claude's Discretion
- Exact list of unique summary tables to snapshot from `11_generate_pptx.R` (determined by reading the script during planning)
- Console log formatting (separators, alignment, message wording)
- Whether `save_output_data()` takes a `subdir` parameter or has separate wrappers for cohort vs outputs
- Compression settings for `saveRDS()` (default `compress = TRUE` is fine)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SNAP-01 | After each named filter step in cohort chain, save resulting data frame to `/blue/erin.mobley-hl.bcu/clean/rds/cohort/` as `cohort_<step_name>.rds` | RDS serialization via `saveRDS()` with established Phase 15 cache directory patterns; naming convention from D-09 |
| SNAP-02 | Save final analysis-ready cohort as `cohort_final.rds` and attrition log as `attrition_log.rds` | Same RDS pattern; attrition log is a data frame (compatible with saveRDS) |
| SNAP-03 | Every figure gets its ggplot-ready data frame saved as `<figure_name>_data.rds` in `/blue/erin.mobley-hl.bcu/clean/rds/outputs/` | Helper function pattern with `_data` suffix naming (D-10); outputs subdirectory in D-12 |
| SNAP-04 | Every summary table gets its source data frame saved as `<table_name>_data.rds` before rendering | Same helper function; PPTX tables are rendered from data frames |
| SNAP-05 | Shared `save_output_data(df, name)` helper function for consistent path construction, logging, and `saveRDS()` | New `R/utils_snapshot.R` following existing utility pattern (D-04, D-05) |

## Standard Stack

### Core Serialization

| Function | Source | Purpose | Why Standard |
|----------|--------|---------|--------------|
| `saveRDS()` | base R | Single-object serialization to RDS binary format | Native R serialization; platform-independent; preserves attributes/structure; integrates with Phase 15 cache |
| `readRDS()` | base R | Read single object from RDS file | Returns named object directly (no workspace pollution like `.RData`) |
| `file.path()` | base R | Platform-independent path construction | Windows/Linux compatible; used throughout existing codebase |
| `dir.create()` | base R | Directory creation with recursive option | Already used in Phase 15 cache setup and existing output directory creation |

### Supporting Functions (Already in Use)

| Function | Source | Purpose | Existing Use |
|----------|--------|---------|--------------|
| `glue()` | glue 1.8.0 | String interpolation for log messages | All logging in 01_load_pcornet.R, 04_build_cohort.R, etc. |
| `message()` | base R | Console output logging | Standard logging pattern across all scripts |
| `basename()` | base R | Extract filename from path | Used in Phase 15 cache logging (line 533 of 01_load_pcornet.R) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `saveRDS()` | `save()` (`.RData`) | `.RData` requires `load()` which pollutes workspace with arbitrary variable names; RDS returns named object |
| `saveRDS()` | `write_rds()` (readr) | Tidyverse wrapper is simpler but doesn't compress by default; base `saveRDS()` already used in Phase 15 |
| `saveRDS()` | `arrow::write_parquet()` | Parquet is faster/smaller for very large datasets but adds external dependency; RDS is sufficient for this use case |
| Helper function | Inline `saveRDS()` calls everywhere | Helper ensures consistency, reduces duplication, centralizes logging format |

**Installation:**

No new packages required. All functions are base R or already installed (glue 1.8.0 from Phase 1).

**Version verification:**

Base R functions (`saveRDS`, `readRDS`, `file.path`, `dir.create`) have stable APIs since R 3.0.0. No version compatibility issues for R 4.4.2+ on HiPerGator.

## Architecture Patterns

### Recommended Directory Structure

```
/blue/erin.mobley-hl.bcu/clean/rds/
├── raw/                          # Phase 15: Cached PCORnet tables
│   ├── ENROLLMENT.rds
│   ├── DIAGNOSIS.rds
│   └── ...
├── cohort/                       # Phase 16: Cohort filter snapshots
│   ├── cohort_00_initial_population.rds
│   ├── cohort_01_hl_flag.rds
│   ├── cohort_02_has_enrollment.rds
│   ├── cohort_final.rds
│   └── attrition_log.rds
└── outputs/                      # Phase 16: Figure/table backing data
    ├── waterfall_attrition_data.rds
    ├── sankey_patient_flow_data.rds
    ├── encounters_per_person_by_payor_data.rds
    └── ...
```

**Rationale:** Mirrors Phase 15 `raw/` subdirectory pattern. Separation by content type (cohort steps vs final outputs) makes snapshots easy to locate. Gitignored at parent level (`/blue/erin.mobley-hl.bcu/clean/`).

### Pattern 1: Inline Cohort Snapshots

**What:** Direct `saveRDS()` calls in `04_build_cohort.R` after each filter step that changes patient count

**When to use:** Filter steps 0, 1, 2 (change N patients) and final cohort assembly

**Example:**

```r
# Source: Existing Phase 15 pattern in 01_load_pcornet.R line 529
# Adapted for cohort snapshots

# Step 0: Initial population from DEMOGRAPHIC
cohort <- pcornet$DEMOGRAPHIC %>%
  select(ID, SOURCE, SEX, RACE, HISPANIC, BIRTH_DATE)
attrition_log <- log_attrition(attrition_log, "Initial population", n_distinct(cohort$ID))

# Snapshot step 0
snapshot_path <- file.path(CONFIG$cache$cohort_dir, "cohort_00_initial_population.rds")
saveRDS(cohort, snapshot_path, compress = TRUE)
message(glue("  Snapshot: cohort_00_initial_population.rds ({nrow(cohort)} rows, {ncol(cohort)} cols)"))
```

**Why inline:** Only 4-5 snapshots total. Creating a wrapper adds complexity without reducing duplication. Matches existing attrition logging pattern (also inline).

### Pattern 2: Helper Function for Visualization Backing Data

**What:** `save_output_data(df, name, subdir = "outputs")` utility in `R/utils_snapshot.R`

**When to use:** All visualization scripts (05, 06, 11, 16) for figure/table backing data

**Example:**

```r
# Source: Designed from Phase 15 cache pattern and existing utils
# New file: R/utils_snapshot.R

#' Save output data snapshot
#'
#' Saves a data frame to the RDS cache outputs directory with standardized
#' naming and logging. Used for figure and table backing data.
#'
#' @param df Data frame to save
#' @param name Base name for the snapshot (without .rds extension)
#' @param subdir Subdirectory under cache_dir (default: "outputs")
#' @return Invisible NULL (side effect: creates .rds file)
#'
#' @examples
#' save_output_data(attrition_plot_data, "waterfall_attrition_data")
#' save_output_data(sankey_data, "sankey_patient_flow_data")
#'
save_output_data <- function(df, name, subdir = "outputs") {
  # Construct target directory
  target_dir <- file.path(CONFIG$cache$cache_dir, subdir)

  # Create directory if needed
  if (!dir.exists(target_dir)) {
    dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
    message(glue("  Created snapshot directory: {subdir}/"))
  }

  # Construct full path
  snapshot_path <- file.path(target_dir, paste0(name, ".rds"))

  # Save with compression
  saveRDS(df, snapshot_path, compress = TRUE)

  # Log
  message(glue("  Saved: {basename(snapshot_path)} ({nrow(df)} rows, {ncol(df)} cols)"))

  invisible(NULL)
}
```

**Usage in visualization script:**

```r
# In R/05_visualize_waterfall.R, before ggsave()

# Prepare data for visualization
attrition_plot_data <- attrition_log %>%
  mutate(
    step = factor(step, levels = unique(step)),
    label = if_else(...)
  )

# Save backing data snapshot (NEW)
save_output_data(attrition_plot_data, "waterfall_attrition_data")

# Build plot (EXISTING)
p_waterfall <- ggplot(attrition_plot_data, aes(x = step, y = n_after)) + ...

# Save figure (EXISTING)
ggsave(filename = file.path(CONFIG$output_dir, "figures", "waterfall_attrition.png"), ...)
```

### Pattern 3: Config Extension for Snapshot Directories

**What:** Add `cohort_dir` and `outputs_dir` entries to `CONFIG$cache` in `00_config.R`

**When to use:** Phase 16 initialization (extends Phase 15 cache config)

**Example:**

```r
# In R/00_config.R, extend existing cache list (lines 51-54)

cache = list(
  cache_dir    = "/blue/erin.mobley-hl.bcu/clean/rds/raw",  # Phase 15
  force_reload = FALSE,                                      # Phase 15
  # Phase 16: Snapshot subdirectories
  cohort_dir   = "/blue/erin.mobley-hl.bcu/clean/rds/cohort",
  outputs_dir  = "/blue/erin.mobley-hl.bcu/clean/rds/outputs"
)
```

**Alternative approach (more maintainable):**

```r
# Use base path + file.path() to avoid hardcoding repeated paths
cache = list(
  cache_dir    = "/blue/erin.mobley-hl.bcu/clean/rds",
  force_reload = FALSE,
  # Subdirectories constructed from base
  raw_dir      = file.path("/blue/erin.mobley-hl.bcu/clean/rds", "raw"),
  cohort_dir   = file.path("/blue/erin.mobley-hl.bcu/clean/rds", "cohort"),
  outputs_dir  = file.path("/blue/erin.mobley-hl.bcu/clean/rds", "outputs")
)
```

**Recommendation:** Use the second approach for DRYness. Update Phase 15 code to reference `CONFIG$cache$raw_dir` instead of `CONFIG$cache$cache_dir`.

### Anti-Patterns to Avoid

- **Don't use `save()`/`load()` instead of `saveRDS()`/`readRDS()`:** `.RData` files pollute workspace with arbitrary variable names when loaded. RDS returns a single named object you assign explicitly.
- **Don't skip `compress = TRUE`:** RDS files can be 2-5x smaller compressed (especially for data frames with repeated values like payer categories). Compression overhead is negligible for datasets this size (<10M rows).
- **Don't put snapshot calls before data is finalized:** In `04_build_cohort.R`, snapshot AFTER `log_attrition()` so row counts match logged values. Snapshot plot data AFTER transformation but BEFORE plotting.
- **Don't create separate snapshots for every plot when data is reused:** Per D-07, save unique summary tables in `11_generate_pptx.R`, not every pivot of the same data. Reduces snapshot count from ~40 to ~8.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Single-object serialization | Custom CSV writer with metadata in separate JSON file | `saveRDS(compress = TRUE)` | Native R format preserves factors, dates, attributes; no parsing on reload; compression built-in |
| Snapshot path construction | Manual `paste()` with hardcoded directory strings | `file.path()` with `CONFIG$cache` entries | Platform-independent path separators (Windows vs Linux); centralized config; DRY principle |
| Directory creation error handling | `tryCatch(dir.create(...))` with custom messages | `dir.create(recursive = TRUE, showWarnings = FALSE)` | `recursive = TRUE` creates parent directories automatically; `showWarnings = FALSE` silences "already exists" warnings |
| Snapshot logging format | Custom logging function with row/column counting | Inline `message(glue(...))` with `nrow()`/`ncol()` | Matches existing Phase 15 and cohort logging pattern; consistency across codebase |

**Key insight:** R's built-in serialization and file system functions handle edge cases (platform differences, existing directories, atomic writes) that custom solutions would miss. The project already uses these functions in Phase 15 — Phase 16 just extends the pattern to more snapshot types.

## Common Pitfalls

### Pitfall 1: Snapshot Directory Not Created Before First Write

**What goes wrong:** `saveRDS()` fails with "cannot open file" error if parent directory doesn't exist.

**Why it happens:** Unlike cache directory (created once at pipeline start), cohort and outputs directories are written to by multiple scripts. First script to run might find directory missing.

**How to avoid:**
```r
# In save_output_data() helper (or inline for cohort snapshots)
if (!dir.exists(target_dir)) {
  dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
}
```

**Warning signs:** Error message containing "cannot open the connection" and a file path under `/blue/.../rds/cohort/` or `/blue/.../rds/outputs/`.

### Pitfall 2: Snapshot Name Collision Between Scripts

**What goes wrong:** Two scripts save different data frames with the same filename, silently overwriting each other.

**Why it happens:** Generic names like `summary_table_data.rds` appear in multiple visualization scripts.

**How to avoid:** Per D-10, use descriptive names that mirror the output filename:
```r
# AVOID
save_output_data(table1, "summary_table_data")  # Which table?

# PREFER
save_output_data(payer_summary_table, "payer_primary_by_site_data")  # Clear which table
```

**Warning signs:** RDS file timestamp doesn't match when script was last run; data frame contents don't match expectations.

### Pitfall 3: Snapshot Before vs After Transformation

**What goes wrong:** Saving raw data before plot-specific transformations (facet factorization, label creation, filtering) means snapshot doesn't match visualization.

**Why it happens:** Easy to place `save_output_data()` call too early in script workflow.

**How to avoid:** Snapshot the EXACT data frame passed to `ggplot()` or table rendering function:
```r
# 1. Load base data
attrition_log <- <from cohort script>

# 2. Transform for visualization
attrition_plot_data <- attrition_log %>%
  mutate(step = factor(step, levels = unique(step)),
         label = if_else(...))

# 3. Snapshot transformed data (NOT raw attrition_log)
save_output_data(attrition_plot_data, "waterfall_attrition_data")

# 4. Plot
p_waterfall <- ggplot(attrition_plot_data, aes(x = step, y = n_after)) + ...
```

**Warning signs:** Loading snapshot and re-running plot code produces different visualization (different factor levels, missing columns, different row counts).

### Pitfall 4: Cohort Snapshot Row Count Mismatch with Attrition Log

**What goes wrong:** Snapshot row count differs from `attrition_log$n_after` for the same step.

**Why it happens:** Snapshot saved before or after an attrition operation, not synchronized with `log_attrition()` call.

**How to avoid:** Per D-03, place `saveRDS()` immediately after `log_attrition()`:
```r
# Step 2: with_enrollment_period filter
cohort <- cohort %>% filter(has_enrollment)
attrition_log <- log_attrition(attrition_log, "Has enrollment", n_distinct(cohort$ID))

# Snapshot IMMEDIATELY after log (NEW, synchronizes row count)
saveRDS(cohort, file.path(CONFIG$cache$cohort_dir, "cohort_02_has_enrollment.rds"), compress = TRUE)
message(glue("  Snapshot: cohort_02_has_enrollment.rds ({nrow(cohort)} rows)"))
```

**Warning signs:** Snapshot RDS has N rows, but attrition log shows M rows for same step name. Difficult to debug attrition logic because snapshot doesn't match logged state.

### Pitfall 5: Hardcoded Absolute Paths Instead of CONFIG

**What goes wrong:** Paths like `/blue/erin.mobley-hl.bcu/clean/rds/outputs/` hardcoded in multiple scripts break when directory structure changes.

**Why it happens:** Copy-paste from Phase 15 cache example without abstracting to config.

**How to avoid:** Always reference `CONFIG$cache$cohort_dir` or `CONFIG$cache$outputs_dir`:
```r
# AVOID
snapshot_path <- "/blue/erin.mobley-hl.bcu/clean/rds/cohort/cohort_final.rds"

# PREFER
snapshot_path <- file.path(CONFIG$cache$cohort_dir, "cohort_final.rds")
```

**Warning signs:** Error messages with hardcoded paths when running on different HiPerGator allocation or local development machine.

## Code Examples

Verified patterns from existing codebase and R documentation:

### Cohort Snapshot (Inline in 04_build_cohort.R)

```r
# Source: Adapted from Phase 15 cache pattern (01_load_pcornet.R line 529)
# Location: R/04_build_cohort.R, after each attrition log call

# Step 0: Initial population
cohort <- pcornet$DEMOGRAPHIC %>%
  select(ID, SOURCE, SEX, RACE, HISPANIC, BIRTH_DATE)
attrition_log <- log_attrition(attrition_log, "Initial population", n_distinct(cohort$ID))

# Snapshot step 0
if (!dir.exists(CONFIG$cache$cohort_dir)) {
  dir.create(CONFIG$cache$cohort_dir, recursive = TRUE, showWarnings = FALSE)
  message(glue("  Created snapshot directory: cohort/"))
}
saveRDS(cohort, file.path(CONFIG$cache$cohort_dir, "cohort_00_initial_population.rds"), compress = TRUE)
message(glue("  Snapshot: cohort_00_initial_population.rds ({nrow(cohort)} rows, {ncol(cohort)} cols)"))
```

### Helper Function for Output Snapshots

```r
# Source: New utility following existing pattern in R/utils_attrition.R
# Location: R/utils_snapshot.R (new file)

#' Save output data snapshot
#'
#' Saves a data frame to the RDS cache outputs directory with standardized
#' naming and logging. Creates target directory if needed.
#'
#' @param df Data frame to save
#' @param name Base name for the snapshot (without .rds extension)
#' @param subdir Subdirectory under cache_dir (default: "outputs")
#' @return Invisible NULL (side effect: creates .rds file)
#'
#' @examples
#' save_output_data(attrition_plot_data, "waterfall_attrition_data")
#' save_output_data(payer_summary, "payer_primary_by_site_data", subdir = "outputs")
#'
save_output_data <- function(df, name, subdir = "outputs") {
  # Validate inputs
  if (!is.data.frame(df)) {
    stop("df must be a data frame")
  }
  if (is.null(CONFIG$cache$cache_dir)) {
    stop("CONFIG$cache$cache_dir not configured")
  }

  # Construct target directory
  target_dir <- file.path(CONFIG$cache$cache_dir, subdir)

  # Create directory if needed (idempotent)
  if (!dir.exists(target_dir)) {
    dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
    message(glue("  Created snapshot directory: {subdir}/"))
  }

  # Construct full path
  snapshot_path <- file.path(target_dir, paste0(name, ".rds"))

  # Save with compression
  saveRDS(df, snapshot_path, compress = TRUE)

  # Log to console
  message(glue("  Saved: {basename(snapshot_path)} ({nrow(df)} rows, {ncol(df)} cols)"))

  invisible(NULL)
}
```

### Usage in Visualization Script

```r
# Source: Pattern for R/05_visualize_waterfall.R, R/06_visualize_sankey.R
# Location: After data transformation, before ggsave()

source("R/04_build_cohort.R")  # Loads attrition_log, hl_cohort, all upstream
library(ggplot2)
library(dplyr)

# [EXISTING] Transform data for plot
attrition_plot_data <- attrition_log %>%
  mutate(
    step = factor(step, levels = unique(step)),
    label = if_else(
      pct_excluded == 0,
      glue("{comma(n_after)}"),
      glue("{comma(n_after)}\n(-{round(pct_excluded, 1)}%)")
    )
  )

# [NEW] Save backing data snapshot
save_output_data(attrition_plot_data, "waterfall_attrition_data")

# [EXISTING] Build plot
p_waterfall <- ggplot(attrition_plot_data, aes(x = step, y = n_after)) +
  geom_col(...) +
  geom_text(...) +
  labs(...)

# [EXISTING] Save figure
ggsave(
  filename = file.path(CONFIG$output_dir, "figures", "waterfall_attrition.png"),
  plot = p_waterfall,
  width = 10, height = 7, dpi = 300
)
```

### Config Update for Snapshot Directories

```r
# Source: Extension of Phase 15 CONFIG$cache in R/00_config.R
# Location: R/00_config.R lines 51-54 (extend existing cache list)

CONFIG <- list(
  # [EXISTING] Data and project directories
  data_dir = "/orange/erin.mobley-hl.bcu/Mailhot_V1_20250915",
  project_dir = "/blue/erin.mobley-hl.bcu/R",
  output_dir = "output",

  # [EXISTING] Performance tuning
  performance = list(num_threads = 16),

  # [UPDATED] RDS Cache Settings (Phase 15 + Phase 16)
  cache = list(
    # Base cache directory (gitignored)
    cache_dir    = "/blue/erin.mobley-hl.bcu/clean/rds",
    force_reload = FALSE,

    # Phase 15: Raw PCORnet table cache
    raw_dir      = "/blue/erin.mobley-hl.bcu/clean/rds/raw",

    # Phase 16: Cohort snapshot directory
    cohort_dir   = "/blue/erin.mobley-hl.bcu/clean/rds/cohort",

    # Phase 16: Output snapshot directory (figures/tables)
    outputs_dir  = "/blue/erin.mobley-hl.bcu/clean/rds/outputs"
  )
)
```

### Sourcing the Helper Utility

```r
# Source: Pattern from R/00_config.R lines 848-850 (existing utility sourcing)
# Location: R/00_config.R, end of file (after cache config)

# ------------------------------------------------------------------------------
# 6. AUTO-SOURCE UTILITY FUNCTIONS
# ------------------------------------------------------------------------------

# Load date parsing and attrition logging utilities
# These are sourced automatically when 00_config.R is loaded
source("R/utils_dates.R")
source("R/utils_attrition.R")
source("R/utils_icd.R")
source("R/utils_snapshot.R")  # NEW: Phase 16 snapshot helper
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual CSV export of intermediate results with separate metadata files | `saveRDS()` with native metadata preservation | R 1.4.0 (2001) | Single-file snapshots with no parsing overhead; factor levels, attributes preserved |
| `save()` with `.RData` workspace images | `saveRDS()` with single-object return | R 2.13.0 (2011) added `saveRDS()` | No workspace pollution; explicit object assignment; version control friendly |
| Uncompressed RDS (default in early R versions) | `compress = TRUE` as standard practice | R 3.0.0 (2013) improved compression | 2-5x size reduction for typical data frames; negligible write overhead |
| Separate packages for reproducibility (drake, targets) | Native snapshot patterns sufficient for linear pipelines | 2018-2020 (drake/targets rise) | Complex DAG pipelines benefit from automated caching; simple linear pipelines (like this one) don't need overhead |

**Deprecated/outdated:**

- **`version = 2` parameter:** R 4.0.0+ defaults to `version = 3` (more compact serialization format). Only specify `version = 2` for backwards compatibility with R 3.5.0 or earlier. HiPerGator runs R 4.4.2 — use default version 3.
- **`ascii = TRUE` parameter:** Text-based RDS format is 2-3x slower and larger than binary (`ascii = FALSE`, the default). Only use for version control of small config objects. Never for data frames.
- **`refhook` parameter:** For custom object serialization. Not needed for standard data frames. Adds complexity without benefit.

## Open Questions

1. **Should `save_output_data()` validate subdirectory parameter to prevent typos?**
   - What we know: Helper takes `subdir` parameter (default "outputs"). Typos could create unwanted directories.
   - What's unclear: Whether validation is worth the code complexity. Only two valid values: "cohort", "outputs".
   - Recommendation: Add simple validation with informative error message. Prevents silent bugs:
     ```r
     if (!subdir %in% c("cohort", "outputs")) {
       stop(glue("Invalid subdir '{subdir}'. Must be 'cohort' or 'outputs'."))
     }
     ```

2. **Should cohort snapshots use the helper function or inline `saveRDS()` calls?**
   - What we know: D-03 says snapshot and attrition logging stay separate. Helper abstracts path construction.
   - What's unclear: Whether helper's directory creation and logging benefits outweigh inline simplicity for 4-5 calls.
   - Recommendation: Use inline `saveRDS()` for cohort snapshots (matches attrition logging pattern). Use helper only for visualization scripts (more calls, benefits from abstraction). See Pattern 1 vs Pattern 2 above.

3. **How to handle script execution order when snapshot directories don't exist?**
   - What we know: Each script using `save_output_data()` creates directory if needed. Idempotent via `showWarnings = FALSE`.
   - What's unclear: Whether to create all directories upfront in `00_config.R` or lazily in each script.
   - Recommendation: Lazy creation (in helper and inline cohort snapshots). Matches Phase 15 cache pattern (line 524-526 of 01_load_pcornet.R). No global side effects in config file.

## Sources

### Primary (HIGH confidence)

- R Documentation: `?saveRDS`, `?readRDS`, `?file.path`, `?dir.create` - Base R serialization and file system functions (R 4.4.2)
- Existing codebase: `R/01_load_pcornet.R` lines 520-546 - Established Phase 15 cache pattern with `saveRDS()`, `dir.create()`, `glue()` logging
- Existing codebase: `R/00_config.R` lines 51-54 - Cache configuration structure
- Existing codebase: `R/utils_attrition.R` - Utility function pattern (roxygen2 comments, parameter validation, message logging)
- Existing codebase: `R/04_build_cohort.R` lines 46-100 - Attrition logging workflow and inline operation pattern
- [R Documentation: Serialization Interface](https://rdrr.io/r/base/readRDS.html) - Official `saveRDS()`/`readRDS()` documentation

### Secondary (MEDIUM confidence)

- [readr: Read/write RDS files](https://readr.tidyverse.org/reference/read_rds.html) - Tidyverse `write_rds()` alternative (verified against base R approach)
- [STHDA: Saving Data into R Data Format](https://www.sthda.com/english/wiki/saving-data-into-r-data-format-rds-and-rdata) - RDS vs RData comparison
- [GeeksforGeeks: saveRDS() and readRDS() Functions in R](https://www.geeksforgeeks.org/r-language/saverds-and-readrds-functions-in-r/) - Compression parameter guidance
- [R-bloggers: Working with files and folders in R](https://www.r-bloggers.com/2021/05/working-with-files-and-folders-in-r-ultimate-guide/) - `dir.create()` and `file.path()` best practices

### Tertiary (LOW confidence, marked for validation)

- [Building reproducible analytical pipelines with R](https://raps-with-r.dev/) - General pipeline reproducibility context (2026)
- [CRAN Task View: Reproducible Research](https://cran.r-project.org/view=ReproducibleResearch) - Alternative packages (targets, drake, archivist) for complex pipelines
- [RPubs: RDS compression testing](https://rpubs.com/jeffjjohnston/rds_compression) - Informal compression benchmarks (single user, not peer-reviewed)

## Metadata

**Confidence breakdown:**

- Standard stack (saveRDS, readRDS, file system functions): **HIGH** - Base R functions with 20+ years stability; existing use in Phase 15 confirms compatibility
- Architecture patterns (inline vs helper, config structure): **HIGH** - Derived from existing codebase patterns in Phases 1, 15; verified against R documentation
- Pitfalls (directory creation, snapshot timing, naming): **HIGH** - Based on common R serialization errors documented in official sources and observed in similar projects
- Helper function design: **MEDIUM** - New code, not yet tested; design follows existing utility pattern but requires validation during implementation

**Research date:** 2026-04-03

**Valid until:** 90 days (2026-07-02). R core serialization functions are extremely stable. Only risk is if HiPerGator upgrades to R 5.x (not expected until 2027+) or if project migrates to alternative pipeline framework (out of scope for v1.1).
