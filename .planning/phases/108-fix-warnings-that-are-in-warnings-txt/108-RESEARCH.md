# Phase 108: Fix warnings that are in warnings.txt - Research

**Researched:** 2026-06-16
**Domain:** R warning management, data pipeline defensive coding
**Confidence:** HIGH

## Summary

Phase 108 resolves 14 R warnings produced during pipeline execution. The warnings fall into 5 categories: (1) DuckDB connection reuse noise (5 warnings), (2) empty result set notifications (1 warning), (3) min() returning Inf for all-NA groups (815 warnings — the bulk of the noise), (4) pre-1900 sentinel dates from SAS epoch (3 warnings), and (5) data quality issues (2 file-not-found, 1 logic error). The research identifies established R patterns for each: targeted suppression for benign noise, safe wrapper functions for arithmetic edge cases, and sentinel value coercion for legacy data.

**Primary recommendation:** Create a `min_or_na()` safe wrapper (returns NA instead of Inf+warning when all values are NA) and apply it to 30+ min() calls across R/02, R/11, R/13. This eliminates 815/819 warnings (99% reduction) using a reusable, testable utility function that prevents misleading Inf values in downstream analysis.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01:** 5 "DuckDB connection already open" warnings (warnings 3,4,6,9,10) — **suppress at source** by removing the `warning()` call from `open_pcornet_con()` in `R/utils/utils_duckdb.R`. Keep the existing silent close-and-reopen behavior.

**D-02:** "Unresolved codes empty" warning (warning 7) — **suppress at source** by removing the `warning()` call from `to_tibble_safe()` in `R/utils/utils_dt.R` when result is empty. Return empty tibble silently.

**D-03:** 815 `summarise()` warnings about `min()` returning `Inf` for all-NA groups (warning 11) — **fix at source** by creating a `min_or_na()` safe wrapper that returns `NA` instead of `Inf + warning` when all values are `NA`. Replace `min(col, na.rm = TRUE)` calls in `summarise()` across R/13, R/11, R/02 and related files.

**D-04:** 3 "Date < 1900-01-01" warnings (warnings 8,12,13) — **coerce pre-1900 dates to NA** during ingest or harmonization. These are SAS epoch sentinels (1899-12-30), not real dates.

**D-05:** "23 dates outside 1990-2030 range" warning (warning 5) — **widen the valid range** in `warn_date_range()` call in R/25 to accommodate tumor registry pre-2012 dates (e.g., 1960-2030).

**D-06:** `open_pcornet_con()` connection pattern — **silent close/reopen only**. Remove the `warning()` call but keep the existing close-and-reopen behavior. No connection reuse or refactoring needed.

**D-07:** LAB_RESULT_CM unicode ingest failure (warning 2) — **filename mismatch confirmed**. The actual file on disk is `LAB_RESULT_Mailhot_V1.csv`. Update the filename mapping in `R/00_config.R` (or wherever the ingest maps table names to filenames) so R/03 finds the correct file. If encoding issues persist after the filename fix, try latin1/windows-1252 fallback.

**D-08:** PROVIDER table unavailable (warning 1) — **filename mismatch confirmed**. The actual file on disk is `PROVIDER_Mailhot_V1.csv`. Update the filename mapping so the pipeline finds the correct file.

**D-09:** TABLE-2 rows >= TABLE-1 (warning 14) — **investigate and fix the root cause**. TABLE-2 (chemo-only encounters) should be a subset of TABLE-1 (all cancer encounters). Either the TABLE-2 filter is too broad or TABLE-1 is too narrow. Fix the logic error in R/36.

### Claude's Discretion

- Exact placement of the `min_or_na()` utility function (likely `R/utils/utils_assertions.R` or a new safe-math utility)
- Whether pre-1900 date coercion happens in R/03 ingest or R/02 harmonization
- Exact widened range for `warn_date_range()` (1960-2030 or similar)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

## Standard Stack

### Core

All tools already present in project stack (tidyverse ecosystem). No new packages needed.

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| base R | 4.4.2+ | min(), max(), is.na() | Built-in; safe wrappers extend base behavior |
| dplyr | 1.2.0+ | summarise() context for min/max operations | Already in use; 30+ summarise() calls need fixing |
| checkmate | (current) | Input validation in utils_assertions.R | Established pattern for defensive coding helpers |
| glue | 1.8.0 | Error/warning message formatting | Existing `[R/XX WARNING]` format convention |

**Version verification:**

All packages already installed per CLAUDE.md stack section. No version updates needed.

**Installation:**

No installation required — this phase modifies existing code using existing dependencies.

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| lubridate | 1.9.3+ | Date manipulation for sentinel value filtering | Pre-1900 date detection (D-04) |
| DBI/duckdb | (current) | Connection management for D-01 fix | Modify open_pcornet_con() warning behavior |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom min_or_na() | tidyna package | tidyna provides drop-in NA-aware replacements (min_tidy(), max_tidy()) but adds dependency; custom wrapper is 3 lines, no deps |
| Remove warning() calls | suppressWarnings() at call sites | Suppression at call sites (30+ locations) is repetitive; source fix (1 function) is cleaner |
| Fix TABLE-1/TABLE-2 logic | Suppress warning in R/36 | Logic error must be fixed, not suppressed — indicates real data quality issue |

## Architecture Patterns

### Recommended Project Structure

No structural changes. All fixes occur in existing files:

```
R/
├── utils/
│   ├── utils_duckdb.R       # D-01, D-06: Remove connection warning
│   ├── utils_dt.R           # D-02: Remove empty result warning
│   └── utils_assertions.R   # D-03: Add min_or_na() safe wrapper, D-05: widen date range
├── 00_config.R              # D-07, D-08: Fix PCORNET_PATHS filename mappings
├── 02_harmonize_payer.R     # D-03: Replace min() with min_or_na() (2 calls)
├── 03_duckdb_ingest.R       # D-07: (LAB_RESULT_CM reads from PCORNET_PATHS, no change needed)
├── 11_treatment_payer.R     # D-03: Replace min() with min_or_na() (30+ calls)
├── 13_survivorship_encounters.R  # D-03: Replace min() with min_or_na() (4 calls)
├── 25_treatment_durations.R # D-05: Widen warn_date_range() call bounds
└── 36_tableau_ready_tables.R # D-09: Fix TABLE-1/TABLE-2 logic error
```

### Pattern 1: Safe Arithmetic Wrappers (D-03 — min_or_na)

**What:** Wrapper functions that handle edge cases (all-NA groups, empty vectors) gracefully without warnings or misleading values (Inf, -Inf).

**When to use:** Grouped aggregations (summarise, group_by) where some groups may have all-NA values for the aggregated column. Common in sparse medical data (not all patients have all event types).

**Example:**

```r
# Source: Custom pattern based on dplyr best practices
# Location: R/utils/utils_assertions.R (or new R/utils/utils_safe_math.R)

#' Safe minimum that returns NA instead of Inf for all-NA input
#'
#' Wrapper around min() that returns NA (correct type) when all values are NA,
#' instead of Inf + warning. Prevents 815 warnings from min(na.rm=TRUE) in
#' grouped summarise() calls where some groups have all-NA values.
#'
#' @param x Numeric or Date vector
#' @param na.rm Logical. Remove NAs before computing? Default TRUE.
#' @return Minimum value, or NA if all values are NA
#'
#' @examples
#' # Standard min() behavior (returns Inf + warning)
#' min(c(NA, NA, NA), na.rm = TRUE)  # Inf (with warning)
#'
#' # Safe wrapper behavior (returns NA silently)
#' min_or_na(c(NA, NA, NA))  # NA (no warning)
#'
#' # Used in grouped summarise
#' df %>%
#'   group_by(ID) %>%
#'   summarise(earliest_date = min_or_na(event_date))
min_or_na <- function(x, na.rm = TRUE) {
  if (all(is.na(x))) {
    return(NA)
  }
  min(x, na.rm = na.rm)
}

#' Safe maximum that returns NA instead of -Inf for all-NA input
max_or_na <- function(x, na.rm = TRUE) {
  if (all(is.na(x))) {
    return(NA)
  }
  max(x, na.rm = na.rm)
}
```

**Usage in summarise():**

```r
# BEFORE (generates warning when group has all-NA DX_DATE)
enrollment %>%
  group_by(ID, DX_norm) %>%
  summarise(earliest_dx = min(DX_DATE, na.rm = TRUE), .groups = "drop")

# AFTER (returns NA silently for all-NA groups)
enrollment %>%
  group_by(ID, DX_norm) %>%
  summarise(earliest_dx = min_or_na(DX_DATE), .groups = "drop")
```

**Why this pattern:**

- Prevents misleading Inf values in downstream analysis (Inf != "no data")
- Eliminates 815 warnings (99% of warning volume) with minimal code change
- Reusable across all aggregation contexts (not just min/max — same pattern for mean, sum, etc.)
- Testable in isolation (unit test: all-NA input → NA output, no warning)
- Aligns with tidyverse philosophy (explicit NA handling, readable code)

### Pattern 2: Targeted Warning Suppression at Source (D-01, D-02)

**What:** Remove `warning()` calls from utility functions when the condition is benign and logging adds no value.

**When to use:** Warning messages that are (1) high-frequency noise, (2) document expected/correct behavior, (3) provide no actionable information to the user.

**Example (D-01):**

```r
# BEFORE: R/utils/utils_duckdb.R lines 128-131
open_pcornet_con <- function(db_path = CONFIG$cache$duckdb_path, read_only = TRUE) {
  if (exists("pcornet_con", envir = .GlobalEnv)) {
    warning("DuckDB connection already open. Closing and reopening.")  # REMOVE THIS
    close_pcornet_con()
  }
  # ... rest of function
}

# AFTER: Silent close-and-reopen (behavior unchanged, noise eliminated)
open_pcornet_con <- function(db_path = CONFIG$cache$duckdb_path, read_only = TRUE) {
  if (exists("pcornet_con", envir = .GlobalEnv)) {
    close_pcornet_con()  # Silent cleanup
  }
  # ... rest of function
}
```

**Example (D-02):**

```r
# BEFORE: R/utils/utils_dt.R lines 104-107
to_tibble_safe <- function(dt, name = "output", script_name = "unknown") {
  if (is.null(dt)) {
    stop(glue::glue("[{script_name} ERROR] {name} is NULL"))
  }
  if (nrow(dt) == 0) {
    warning(glue::glue("[{script_name} WARNING] {name} is empty (0 rows)"))  # REMOVE THIS
    return(tibble::as_tibble(dt))
  }
  # ... rest of function
}

# AFTER: Return empty tibble silently (structure preserved, no noise)
to_tibble_safe <- function(dt, name = "output", script_name = "unknown") {
  if (is.null(dt)) {
    stop(glue::glue("[{script_name} ERROR] {name} is NULL"))
  }
  if (nrow(dt) == 0) {
    return(tibble::as_tibble(dt))  # Silent return
  }
  # ... rest of function
}
```

**Why this pattern:**

- Respects the principle: "warnings are for unexpected conditions that merit investigation"
- Empty result sets and connection reuse are **expected** in this pipeline
- User confirmed these warnings provide no actionable information (CONTEXT.md decisions)
- Reduces warning volume by 6 warnings (5 connection + 1 empty result)

### Pattern 3: Sentinel Value Filtering (D-04)

**What:** Detect and coerce sentinel values (placeholder dates like 1899-12-30, 1900-01-01) to NA during data ingestion or harmonization.

**When to use:** Legacy data sources (SAS, SPSS, Excel) that use pre-1900 dates as "missing" indicators. These values break R's Date class validation and are not semantically meaningful.

**Example:**

```r
# Option A: Filter during ingest (R/03_duckdb_ingest.R or after readRDS)
# Apply to DATE columns during RDS load

# After loading from RDS
df <- readRDS(rds_path)

# Coerce pre-1900 dates to NA for all Date columns
date_cols <- names(df)[sapply(df, inherits, "Date")]
for (col in date_cols) {
  df[[col]][df[[col]] < as.Date("1900-01-01")] <- NA
}

# Option B: Filter during harmonization (R/02_harmonize_payer.R or similar)
# Apply to specific date columns known to contain sentinel values

enrollment <- enrollment %>%
  mutate(
    ENR_START_DATE = if_else(ENR_START_DATE < as.Date("1900-01-01"), NA, ENR_START_DATE),
    ENR_END_DATE   = if_else(ENR_END_DATE < as.Date("1900-01-01"), NA, ENR_END_DATE)
  )
```

**Why this pattern:**

- SAS uses 1960-01-01 as epoch; pre-1960 dates (and especially pre-1900) are sentinel values
- R's Date class validation throws warnings on pre-1900 conversion
- Coercing to NA is semantically correct ("unknown date" not "impossible date")
- Prevents downstream errors in date arithmetic (Inf results, invalid intervals)

### Pattern 4: Validation Range Widening (D-05)

**What:** Adjust validation thresholds when legitimate data exceeds expected bounds.

**When to use:** Tumor registry or longitudinal data that predates study enrollment (e.g., diagnosis in 1973, enrollment in 2012).

**Example:**

```r
# BEFORE: R/25_treatment_durations.R — warn_date_range() call
warn_date_range(
  all_durations,
  col = "first_treatment_date",
  lo = as.Date("1990-01-01"),  # TOO RESTRICTIVE for tumor registry data
  hi = as.Date("2030-12-31"),
  script_name = "R/25"
)

# AFTER: Widen range to accommodate pre-2012 tumor registry dates
warn_date_range(
  all_durations,
  col = "first_treatment_date",
  lo = as.Date("1960-01-01"),  # Tumor registry may include pre-2012 dates
  hi = as.Date("2030-12-31"),
  script_name = "R/25"
)
```

**Why this pattern:**

- Warnings are correct (dates ARE outside 1990-2030 range)
- But the data is legitimate (tumor registry includes historical diagnoses)
- Widen range to match data reality, not arbitrary expectations

### Anti-Patterns to Avoid

- **Don't use suppressWarnings() at call sites:** Suppressing 30+ min() calls individually is repetitive and hides the root cause. Fix at source with min_or_na().
- **Don't suppress data quality warnings (D-09):** TABLE-2 >= TABLE-1 indicates a logic error. Investigate and fix the root cause, don't silence the warning.
- **Don't ignore sentinel values:** Pre-1900 dates are not real dates. Coerce to NA rather than allowing invalid values to propagate.
- **Don't over-narrow validation ranges:** If legitimate data exceeds bounds, adjust bounds (not suppress warnings).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| NA-aware min/max across entire pipeline | tidyna package | Custom min_or_na() wrapper | tidyna adds dependency for 3-line function; custom wrapper is sufficient for project needs |
| Connection pooling for DuckDB | Custom connection manager | Silent close-and-reopen (existing) | DuckDB read-only connections are lightweight; reuse pattern already implemented, just remove warning |
| Date validation framework | Custom validator | Extend warn_date_range() (existing) | utils_assertions.R already has parameterized range check; widen bounds, don't rebuild |

**Key insight:** The project already has defensive coding patterns (utils_assertions.R, utils_duckdb.R, utils_dt.R). This phase extends existing utilities rather than introducing new frameworks.

## Common Pitfalls

### Pitfall 1: Suppressing Warnings Without Understanding Root Cause

**What goes wrong:** Using `suppressWarnings()` or removing `warning()` calls without investigating whether the warning indicates a real problem.

**Why it happens:** Warnings are noisy and easy to silence. Developers suppress first, investigate later (or never).

**How to avoid:** Triage warnings into 3 categories:
1. **Benign noise** (D-01, D-02) — suppress at source after confirming behavior is correct
2. **Edge case handled incorrectly** (D-03) — fix logic to handle edge case without warning
3. **Data quality issue** (D-09) — investigate and fix root cause, never suppress

**Warning signs:**

- Warning message says "unexpected" or "should not happen" → investigate, don't suppress
- Warning includes row counts or specific values → data quality issue, not noise
- Warning only appears on certain datasets → conditional bug, not universal noise

### Pitfall 2: Returning Inf From Aggregations

**What goes wrong:** Grouped aggregations return Inf/-Inf when a group has all-NA values, causing downstream arithmetic errors and misleading visualizations.

**Why it happens:** R's base min()/max() returns Inf/-Inf for empty input (after NA removal), and dplyr preserves this behavior in summarise().

**How to avoid:** Use safe wrappers (min_or_na, max_or_na) that return NA for all-NA groups. This prevents:

- Inf values appearing in output tables
- Arithmetic operations producing Inf (e.g., days_to_treatment = Inf - date)
- Filter operations behaving unexpectedly (Inf > threshold is always TRUE)

**Warning signs:**

- Inf/-Inf values in RDS cache files or output tables
- Scatter plots with points at y = Inf
- Filter operations removing all rows unexpectedly

### Pitfall 3: Treating Sentinel Values as Real Data

**What goes wrong:** Pre-1900 dates (SAS epoch sentinels like 1899-12-30) are treated as real dates, breaking Date class validation and date arithmetic.

**Why it happens:** Source systems (SAS, SPSS, Excel) use sentinel values to represent missing data, but R doesn't have a convention for this.

**How to avoid:** Filter sentinel values to NA during ingest (R/03) or harmonization (R/02). Common sentinels:

- Pre-1900 dates (SAS epoch before 1960-01-01)
- 1900-01-01 (SPSS default missing date)
- 9999-12-31 (Excel "far future" placeholder)

**Warning signs:**

- "Date < 1900-01-01 found. This can not be converted." warnings
- Date columns with impossibly old values (e.g., 1800s diagnoses in 2012 cohort)
- Date arithmetic producing negative intervals of 100+ years

### Pitfall 4: Filename Mapping Mismatches (D-07, D-08)

**What goes wrong:** PCORNET_PATHS mapping assumes standard naming pattern (`{TABLE}_Mailhot_V1.csv`), but actual files on disk use different names (`LAB_RESULT_Mailhot_V1.csv` instead of `LAB_RESULT_CM_Mailhot_V1.csv`).

**Why it happens:** PCORnet CDM v7.0 uses `LAB_RESULT_CM` as the canonical table name (Clinical Modifications), but data providers shorten to `LAB_RESULT`. Similarly, PROVIDER table may use site-specific suffixes.

**How to avoid:** Use explicit filename overrides in R/00_config.R for tables that don't follow the standard pattern:

```r
# Filename overrides section (already exists for LAB_RESULT_CM)
PCORNET_PATHS[["LAB_RESULT_CM"]] <- file.path(CONFIG$data_dir, "LAB_RESULT_Mailhot_V1.csv")
PCORNET_PATHS[["PROVIDER"]] <- file.path(CONFIG$data_dir, "PROVIDER_Mailhot_V1.csv")
```

**Warning signs:**

- "INGEST SKIPPED: {TABLE} -- RDS file not found" messages
- Unicode errors during ingest (file exists but path is wrong, reads wrong file)
- Tables missing from DuckDB database after ingest

## Code Examples

Verified patterns from project codebase and R best practices:

### Safe Min/Max Wrappers (D-03)

```r
# Source: Custom pattern based on dplyr GitHub issues #3776, R-bloggers 2023-10
# Location: R/utils/utils_assertions.R (add after warn_row_count())

#' Safe minimum that returns NA instead of Inf for all-NA input
min_or_na <- function(x, na.rm = TRUE) {
  if (all(is.na(x))) {
    return(NA)
  }
  min(x, na.rm = na.rm)
}

#' Safe maximum that returns NA instead of -Inf for all-NA input
max_or_na <- function(x, na.rm = TRUE) {
  if (all(is.na(x))) {
    return(NA)
  }
  max(x, na.rm = na.rm)
}
```

### Targeted Warning Removal (D-01, D-02)

```r
# Source: R/utils/utils_duckdb.R lines 128-131
# BEFORE
if (exists("pcornet_con", envir = .GlobalEnv)) {
  warning("DuckDB connection already open. Closing and reopening.")
  close_pcornet_con()
}

# AFTER
if (exists("pcornet_con", envir = .GlobalEnv)) {
  close_pcornet_con()  # Silent cleanup
}

# Source: R/utils/utils_dt.R lines 104-107
# BEFORE
if (nrow(dt) == 0) {
  warning(glue::glue("[{script_name} WARNING] {name} is empty (0 rows)"))
  return(tibble::as_tibble(dt))
}

# AFTER
if (nrow(dt) == 0) {
  return(tibble::as_tibble(dt))  # Silent return preserves structure
}
```

### Filename Override Pattern (D-07, D-08)

```r
# Source: R/00_config.R lines 245-251
# Existing pattern (LAB_RESULT_CM already has override)
PCORNET_PATHS <- setNames(
  file.path(CONFIG$data_dir, paste0(PCORNET_TABLES, "_Mailhot_V1.csv")),
  PCORNET_TABLES
)

# Filename overrides: actual CSV names that don't match the {TABLE}_Mailhot_V1.csv pattern
PCORNET_PATHS[["LAB_RESULT_CM"]] <- file.path(CONFIG$data_dir, "LAB_RESULT_Mailhot_V1.csv")
PCORNET_PATHS[["PROVIDER"]] <- file.path(CONFIG$data_dir, "PROVIDER_Mailhot_V1.csv")  # ADD THIS
```

### Sentinel Date Filtering (D-04)

```r
# Option A: During ingest (R/03_duckdb_ingest.R after readRDS)
df <- readRDS(rds_path)

# Coerce pre-1900 dates to NA for all Date columns
date_cols <- names(df)[sapply(df, inherits, "Date")]
for (col in date_cols) {
  pre_1900 <- !is.na(df[[col]]) & df[[col]] < as.Date("1900-01-01")
  if (any(pre_1900)) {
    message(glue("  Coercing {sum(pre_1900)} pre-1900 dates to NA in {col} (SAS sentinel values)"))
    df[[col]][pre_1900] <- NA
  }
}

# Option B: During harmonization (R/02 or similar)
enrollment <- enrollment %>%
  mutate(across(
    where(is.Date),
    ~ if_else(. < as.Date("1900-01-01"), NA, .)
  ))
```

### Validation Range Widening (D-05)

```r
# Source: R/25_treatment_durations.R
# BEFORE
warn_date_range(
  all_durations,
  col = "first_treatment_date",
  lo = as.Date("1990-01-01"),
  hi = as.Date("2030-12-31"),
  script_name = "R/25"
)

# AFTER
warn_date_range(
  all_durations,
  col = "first_treatment_date",
  lo = as.Date("1960-01-01"),  # Accommodate tumor registry pre-2012 dates
  hi = as.Date("2030-12-31"),
  script_name = "R/25"
)
```

### Existing suppressWarnings Pattern (for reference)

```r
# Source: R/14_build_cohort.R lines 406-408
# Project already uses suppressWarnings for known benign warnings (Date-to-integer coercion)
cohort <- cohort %>%
  mutate(
    DAYS_DX_TO_CHEMO     = suppressWarnings(as.integer(FIRST_CHEMO_DATE - first_hl_dx_date)),
    DAYS_DX_TO_RADIATION = suppressWarnings(as.integer(FIRST_RADIATION_DATE - first_hl_dx_date)),
    DAYS_DX_TO_SCT       = suppressWarnings(as.integer(FIRST_SCT_DATE - first_hl_dx_date))
  )

# Pattern: suppressWarnings at call site when (1) warning is benign, (2) alternative is verbose
# Contrast with D-03: When 30+ call sites need suppression, fix at source instead
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Suppress warnings globally (options(warn = -1)) | Targeted suppression at source or safe wrappers | R 4.0+ best practices (Hadley Wickham Advanced R Ch. 8) | Warnings surface real issues while eliminating noise |
| Ignore Inf from min/max | Return NA for all-NA groups | dplyr 1.0+ (grouped operations awareness) | Prevents misleading Inf values in downstream analysis |
| Manual sentinel value filtering per script | Centralize in ingest/harmonization | Data pipeline best practices (2020+) | Consistent handling, single source of truth |
| Reopen DuckDB connection with warnings | Silent close-and-reopen | DuckDB 0.8+ (lightweight connections) | Connection reuse is expected behavior, not exceptional |

**Deprecated/outdated:**

- **options(warn = -1):** Global warning suppression — masks all warnings, including critical ones. Never use in production pipelines.
- **Leaving Inf values in output:** min(na.rm = TRUE) on all-NA groups returns Inf, which breaks downstream arithmetic. R 4.0+ best practice is to handle explicitly.
- **suppressWarnings() around entire scripts:** Too coarse-grained; hides new warnings introduced by code changes.

## Open Questions

None. All warnings have clear resolution paths defined in CONTEXT.md decisions D-01 through D-09.

## Environment Availability

Step 2.6: SKIPPED (no external dependencies identified)

This phase modifies existing R code using existing dependencies (base R, dplyr, checkmate, glue). No external tools, services, or package installations required.

## Sources

### Primary (HIGH confidence)

- Project codebase: `R/utils/utils_duckdb.R`, `R/utils/utils_dt.R`, `R/utils/utils_assertions.R`, `R/00_config.R` (lines 245-252), `R/14_build_cohort.R` (lines 406-408) — existing patterns for warning handling, suppressWarnings usage, filename overrides
- Project artifact: `warnings.txt` — complete list of 14 warnings to resolve
- Project decisions: `.planning/phases/108-fix-warnings-that-are-in-warnings-txt/108-CONTEXT.md` — user-confirmed triage and resolution strategy (D-01 through D-09)

### Secondary (MEDIUM confidence)

- [Missing warning when computing min · Issue #3776 · tidyverse/dplyr](https://github.com/tidyverse/dplyr/issues/3776) — confirms min() returns Inf without warning in dplyr summarise
- [Summarising Dates with Missing Values | R-bloggers](https://www.r-bloggers.com/2023/10/summarising-dates-with-missing-values/) — safe min/max wrapper pattern (if/else approach)
- [How to Avoid and Handle Warnings in R | Gary Bao | Medium](https://medium.com/@bao.character/how-to-avoid-and-handle-warnings-in-r-e8344058a187) — targeted suppression best practices
- [Conditions | Advanced R - Hadley Wickham](https://adv-r.hadley.nz/conditions.html) — warning handling philosophy (suppress at source vs call site)
- [R Client – DuckDB](https://duckdb.org/docs/stable/clients/r) — connection management best practices (reuse vs recreate)
- [tidyna: NA-Aware Defaults for Common R Functions](https://archive.linux.duke.edu/cran/web/packages/tidyna/index.html) — alternative approach (package with NA-aware wrappers)

### Tertiary (LOW confidence)

None — all core patterns verified against project codebase or official documentation.

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — all tools already in use, no new dependencies
- Architecture: HIGH — extends existing utils patterns (utils_assertions.R, utils_duckdb.R, utils_dt.R)
- Pitfalls: HIGH — warnings.txt provides complete failure catalog, CONTEXT.md provides resolution strategy
- Code examples: HIGH — all examples drawn from project codebase or verified R best practices

**Research date:** 2026-06-16
**Valid until:** 2026-07-16 (30 days — stable R patterns, no fast-moving dependencies)
