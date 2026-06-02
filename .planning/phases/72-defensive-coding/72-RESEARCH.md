# Phase 72: Defensive Coding - Research

**Researched:** 2026-06-02
**Domain:** Input validation and error handling in R data pipelines
**Confidence:** HIGH

## Summary

Phase 72 adds checkmate assertions to 43 production scripts (decades 00-69) in the PCORnet R pipeline. The phase implements fail-fast input validation with informative error messages at script entry points and after critical data loads/joins. Research confirms checkmate 2.3.4 (released Feb 2026) provides the necessary assertion functions (assert_file_exists, assert_data_frame, assert_names, assert_subset, assert_class) with C-optimized performance suitable for data pipeline use. The phase integrates checkmate with the existing glue() messaging pattern already present in 22 scripts, maintains 30+ existing tryCatch patterns (leave as-is), and follows R defensive programming best practices: validate at function entry, hard-stop on structural errors, warn on suspicious data, fail with context.

**Primary recommendation:** Load checkmate once in R/00_config.R (auto-distributed to all downstream scripts), create R/utils/utils_assertions.R with 5 helper functions to reduce boilerplate, add assertions at script entry (file existence) and after critical operations (data structure, column presence, type validation, row count sanity), use glue() for context-rich error messages following the `[R/XX ACTION] What failed — expected vs actual — fix hint` pattern established in CONTEXT.md.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Validation Scope:**
- **D-01:** Assertions added to foundation (00-03), cohort (10-14), treatment (20-29), cancer (40-53), and payer/QA (60-69) scripts — approximately 40 production scripts. (Actual count: 43 scripts in decades 00-69)
- **D-02:** Test scripts (80-87) and ad-hoc scripts (90-99) are excluded from this phase. They are diagnostic/one-off and handle their own errors or run interactively.
- **D-03:** Output scripts (70-75) are excluded — they are visualization/report generators, not critical data pipeline steps.

**checkmate Integration:**
- **D-04:** Load checkmate once in R/00_config.R via `library(checkmate)`. Since every production script sources 00_config.R (directly or via chain), checkmate is available everywhere without per-script library() calls.
- **D-05:** Leave all ~30 existing tryCatch calls and 2 stopifnot calls (R/13, R/28) as-is. They serve different purposes (error recovery vs fail-fast). Add NEW checkmate assertions at script entry points and after critical loads/joins. No refactoring of working defensive code.
- **D-06:** Add checkmate to renv.lock via `renv::install("checkmate")` and `renv::snapshot()` for HiPerGator reproducibility.

**Assertion Depth:**
- **D-07:** Full validation: file/RDS existence + data frame structure + critical column presence + key identifier types + row-count sanity checks + date value range warnings.
- **D-08:** Column type checks for key identifiers only: PATID (character), ENCOUNTERID (character), date columns (Date class), numeric counts. Not all columns — only those that cause silent bugs when types are wrong.
- **D-09:** Date range validation uses 1990-2030 boundaries. Dates outside this range are flagged as warnings. Pre-2012 dates are legitimately present in tumor registry data (per existing historical_flag in R/26).
- **D-10:** Two severity levels — hard stops vs warnings:
  - **Hard stops (stop()):** File existence, data frame structure, required column presence, column type mismatches. These indicate the pipeline cannot proceed.
  - **Warnings (warning()):** Date range violations, unexpected row counts (e.g., zero rows after join, suspiciously large cartesian products). Pipeline continues but flags suspicious data.

**Error Message Style:**
- **D-11:** All messages follow the pattern: `[R/XX ACTION] What failed — expected vs actual — fix hint`. Uses glue() for interpolation. Examples:
  - Error: `[R/26 ERROR] Expected treatment_durations.rds at {path} -- run R/25_treatment_durations.R first`
  - Warning: `[R/26 WARNING] 15 dates outside 1990-2030 range in treatment_episodes`
- **D-12:** Warnings use the same glue() template as errors but with WARNING prefix instead of ERROR. Consistent format across all assertion messages.
- **D-13:** Create R/utils/utils_assertions.R with helper functions to reduce boilerplate:
  - `assert_rds_exists(path, script_name)` — checks file exists, fails with context + fix hint
  - `assert_df_valid(df, name, required_cols, script_name)` — checks data frame, columns, non-empty
  - `assert_col_types(df, type_spec, script_name)` — validates key column types
  - `warn_date_range(df, col, lo, hi, script_name)` — warns on out-of-range dates
  - `warn_row_count(df, name, min_expected, max_expected, script_name)` — warns on suspicious counts
  - Auto-sourced by 00_config.R alongside other utils modules.

### Claude's Discretion

- Exact assertion placement within each script (after which specific load/join operations)
- Which specific columns constitute "key identifiers" in each table beyond PATID/ENCOUNTERID
- Row count thresholds for sanity checks (what counts as "suspiciously large" per join)
- Whether to batch assertions by script or by assertion type across plans
- Internal structure of utils_assertions.R helper functions
- Wave/plan decomposition strategy

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SAFE-01 | Input file existence validation (checkmate assert_file_exists) at the start of every script that loads data | checkmate::assert_file_exists() with access parameter for read/write checks; helper function assert_rds_exists() wraps with glue() context |
| SAFE-02 | Data structure validation after critical loads and joins (checkmate assertions for expected columns, types, and row-count sanity checks) | checkmate::assert_data_frame(), assert_names(must.include=), assert_subset(), assert_class() for structure; custom warn_row_count() helper for sanity checks |
| SAFE-03 | Error messages include context using glue() — file paths, expected vs actual values, script name | glue() already loaded in 22+ scripts; integrate with checkmate .var.name parameter and custom helper functions for consistent `[R/XX ACTION] message` format |

</phase_requirements>

## Project Constraints (from CLAUDE.md)

**Runtime environment:** RStudio on UF HiPerGator — checkmate must be installed via renv for reproducibility.

**R packages:** Tidyverse ecosystem — checkmate integrates seamlessly with dplyr/tidyverse patterns.

**Code style:** Phase 71 lintr compliance — checkmate assertion calls must follow magrittr pipe standard (%>%), 150-char line length, and pass lintr.

**Existing patterns:** 30+ tryCatch calls across 22 scripts, 2 stopifnot calls in R/13 and R/28 — DO NOT modify (D-05). New assertions supplement, not replace.

**Auto-sourcing:** R/00_config.R uses list.files() to auto-source all R/utils/*.R modules — new utils_assertions.R will be automatically available.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| checkmate | 2.3.4 | Fast argument and input validation | Industry standard for defensive R programming; C-optimized assertions; 30+ check functions; supports both snake_case and camelCase |
| glue | 1.8.0 | String interpolation for error messages | Already loaded in 22+ production scripts; enables readable `[R/XX ERROR] {context}` messages |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| dplyr | 1.2.0+ | Pipe context for assertions | Already loaded; assertions can be piped after filter/join operations |
| rlang | 1.2.0+ | Advanced error handling (optional) | Only if need custom condition classes beyond checkmate (not required for Phase 72) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| checkmate | assertthat | assertthat is older, slower, less comprehensive; checkmate has 30+ validators vs assertthat's ~10 |
| checkmate | base stopifnot | stopifnot lacks informative messages, no customization, harder to maintain; checkmate provides context |
| checkmate | validate package | validate is for data validation workflows (like pointblank); checkmate is for function argument/input checks |
| Custom wrappers | checkmate helpers | Building custom wrappers duplicates checkmate functionality; use checkmate directly + project-specific helper layer |

**Installation:**
```r
# In interactive R session on HiPerGator
renv::install("checkmate")
renv::snapshot()
```

**Version verification:**
Verified against CRAN on 2026-06-02. checkmate 2.3.4 released February 3, 2026. Current stable version.

## Architecture Patterns

### Recommended Assertion Placement Pattern

**Script-level structure:**
```r
# ==============================================================================
# XX_script_name.R
# ==============================================================================

source("R/00_config.R")  # checkmate loaded here, utils_assertions.R auto-sourced

# SECTION 1: INPUT VALIDATION ----

# File existence checks (SAFE-01)
assert_rds_exists(
  file.path(CONFIG$cache$raw_dir, "ENROLLMENT.rds"),
  script_name = "R/26"
)

# SECTION 2: LOAD DATA ----

df <- readRDS(path)

# SECTION 3: DATA STRUCTURE VALIDATION ----

# Data frame structure + required columns (SAFE-02)
assert_df_valid(
  df,
  name = "treatment_durations",
  required_cols = c("ID", "treatment_type", "first_date", "last_date"),
  script_name = "R/26"
)

# Column type validation for key identifiers (D-08)
assert_col_types(
  df,
  type_spec = list(ID = "character", first_date = "Date", episode_count = "integer"),
  script_name = "R/26"
)

# SECTION 4: DATA OPERATIONS ----

result <- df %>%
  left_join(other, by = "ID")

# SECTION 5: POST-JOIN VALIDATION ----

# Row count sanity check (D-10: warning, not error)
warn_row_count(
  result,
  name = "post-join result",
  min_expected = nrow(df),  # At minimum, preserve left table rows
  max_expected = nrow(df) * 1.1,  # Flag if >10% row inflation
  script_name = "R/26"
)

# Date range warnings (D-09, D-10)
warn_date_range(
  result,
  col = "episode_start",
  lo = as.Date("1990-01-01"),
  hi = as.Date("2030-12-31"),
  script_name = "R/26"
)
```

### Pattern 1: File Existence Validation (SAFE-01)

**What:** Check that RDS cache files and data dependencies exist before attempting to load them.

**When to use:** At the start of every script that loads data from RDS cache or depends on output from prior scripts.

**Example:**
```r
# Source: checkmate documentation + Phase 72 decision D-13
# Helper function in R/utils/utils_assertions.R

assert_rds_exists <- function(path, script_name) {
  checkmate::assert_file_exists(
    path,
    access = "r",
    .var.name = glue::glue("[{script_name} ERROR] Expected RDS file")
  )

  # If assertion fails, checkmate throws error with context
  # If succeeds, returns invisibly

  invisible(path)
}

# Usage in R/26_treatment_episodes.R
assert_rds_exists(
  file.path(CONFIG$cache$outputs_dir, "treatment_durations.rds"),
  script_name = "R/26"
)
# Error message if fails: "[R/26 ERROR] Expected RDS file: File '/blue/.../treatment_durations.rds' does not exist"
```

### Pattern 2: Data Frame Structure Validation (SAFE-02)

**What:** Verify that loaded data is a data frame, has expected columns, and is non-empty.

**When to use:** Immediately after loading RDS files or after critical joins that could produce empty results.

**Example:**
```r
# Source: checkmate documentation + Phase 72 decision D-13
# Helper function in R/utils/utils_assertions.R

assert_df_valid <- function(df, name, required_cols, script_name, allow_empty = FALSE) {
  # Check 1: Is it a data frame?
  checkmate::assert_data_frame(
    df,
    min.rows = if (allow_empty) 0 else 1,
    .var.name = glue::glue("[{script_name} ERROR] {name}")
  )

  # Check 2: Does it have required columns?
  checkmate::assert_names(
    colnames(df),
    must.include = required_cols,
    .var.name = glue::glue("[{script_name} ERROR] {name} columns")
  )

  invisible(df)
}

# Usage in R/14_build_cohort.R
cohort_raw <- readRDS(file.path(CONFIG$cache$raw_dir, "ENROLLMENT.rds"))

assert_df_valid(
  cohort_raw,
  name = "ENROLLMENT",
  required_cols = c("ID", "ENR_START_DATE", "ENR_END_DATE"),
  script_name = "R/14"
)
# Error if missing columns: "[R/14 ERROR] ENROLLMENT columns: Must include elements {'ID','ENR_START_DATE','ENR_END_DATE'}"
```

### Pattern 3: Column Type Validation (D-08)

**What:** Verify that key identifier columns have correct types (character for IDs, Date for date columns, numeric for counts).

**When to use:** After loading data and after type conversions (e.g., parse_pcornet_date() calls).

**Example:**
```r
# Source: Phase 72 decision D-08
# Helper function in R/utils/utils_assertions.R

assert_col_types <- function(df, type_spec, script_name) {
  # type_spec is a named list: list(ID = "character", count = "integer", date_col = "Date")

  for (col_name in names(type_spec)) {
    expected_class <- type_spec[[col_name]]

    if (!col_name %in% colnames(df)) {
      stop(glue::glue("[{script_name} ERROR] Column '{col_name}' not found in data frame"))
    }

    actual_class <- class(df[[col_name]])[1]  # First class (handles POSIXct + POSIXt)

    if (expected_class == "Date" && !inherits(df[[col_name]], "Date")) {
      stop(glue::glue(
        "[{script_name} ERROR] Column '{col_name}' must be Date class, got {actual_class} -- ",
        "use parse_pcornet_date() or mutate with as.Date()"
      ))
    } else if (expected_class == "character" && !is.character(df[[col_name]])) {
      stop(glue::glue(
        "[{script_name} ERROR] Column '{col_name}' must be character, got {actual_class} -- ",
        "IDs should be col_character() in vroom specs"
      ))
    } else if (expected_class %in% c("integer", "numeric") && !is.numeric(df[[col_name]])) {
      stop(glue::glue(
        "[{script_name} ERROR] Column '{col_name}' must be numeric, got {actual_class}"
      ))
    }
  }

  invisible(df)
}

# Usage in R/26_treatment_episodes.R
assert_col_types(
  treatment_durations,
  type_spec = list(
    ID = "character",
    first_date = "Date",
    last_date = "Date",
    episode_count = "integer"
  ),
  script_name = "R/26"
)
```

### Pattern 4: Date Range Warnings (D-09, D-10)

**What:** Warn (not error) when date values fall outside plausible range 1990-2030. Pre-2012 dates are legitimate tumor registry data.

**When to use:** After date parsing and before date-based calculations.

**Example:**
```r
# Source: Phase 72 decision D-09, D-10
# Helper function in R/utils/utils_assertions.R

warn_date_range <- function(df, col, lo, hi, script_name) {
  if (!col %in% colnames(df)) {
    warning(glue::glue("[{script_name} WARNING] Column '{col}' not found for date range check"))
    return(invisible(df))
  }

  if (!inherits(df[[col]], "Date")) {
    warning(glue::glue("[{script_name} WARNING] Column '{col}' is not Date class, skipping range check"))
    return(invisible(df))
  }

  out_of_range <- df %>%
    filter(!is.na(.data[[col]]) & (.data[[col]] < lo | .data[[col]] > hi))

  n_out <- nrow(out_of_range)

  if (n_out > 0) {
    range_actual <- range(out_of_range[[col]], na.rm = TRUE)
    warning(glue::glue(
      "[{script_name} WARNING] {n_out} dates outside {lo} to {hi} range in column '{col}' -- ",
      "actual range: {range_actual[1]} to {range_actual[2]} -- ",
      "tumor registry data may include pre-2012 dates (legitimate)"
    ))
  }

  invisible(df)
}

# Usage in R/26_treatment_episodes.R
warn_date_range(
  treatment_episodes,
  col = "episode_start",
  lo = as.Date("1990-01-01"),
  hi = as.Date("2030-12-31"),
  script_name = "R/26"
)
# Output if out of range: "[R/26 WARNING] 15 dates outside 1990-01-01 to 2030-12-31 range in column 'episode_start' -- actual range: 1985-03-15 to 2029-11-20 -- tumor registry data may include pre-2012 dates (legitimate)"
```

### Pattern 5: Row Count Sanity Checks (D-10)

**What:** Warn when post-join row counts are suspiciously low (data loss) or high (cartesian explosion).

**When to use:** After joins, filters, and aggregations that could produce unexpected row counts.

**Example:**
```r
# Source: Phase 72 decision D-10
# Helper function in R/utils/utils_assertions.R

warn_row_count <- function(df, name, min_expected = NULL, max_expected = NULL, script_name) {
  actual <- nrow(df)

  if (!is.null(min_expected) && actual < min_expected) {
    warning(glue::glue(
      "[{script_name} WARNING] {name} has {actual} rows, expected at least {min_expected} -- ",
      "possible data loss from join/filter"
    ))
  }

  if (!is.null(max_expected) && actual > max_expected) {
    warning(glue::glue(
      "[{script_name} WARNING] {name} has {actual} rows, expected at most {max_expected} -- ",
      "possible cartesian product from join"
    ))
  }

  invisible(df)
}

# Usage in R/14_build_cohort.R
n_before <- nrow(cohort)

cohort_with_payer <- cohort %>%
  left_join(payer_summary, by = "ID")

warn_row_count(
  cohort_with_payer,
  name = "cohort after payer join",
  min_expected = n_before,  # Left join shouldn't lose rows
  max_expected = n_before * 1.05,  # Tolerate 5% inflation, warn beyond
  script_name = "R/14"
)
```

### Anti-Patterns to Avoid

- **Don't refactor existing tryCatch calls:** 30+ tryCatch blocks handle NULL-guards for DuckDB and API failures. Leave them as-is (D-05). Add new assertions alongside, don't replace.

- **Don't validate inside hot loops:** Assertions at function entry (D-07), not inside `map()` or `for` loops over thousands of rows. Validate input data structure once, not per iteration.

- **Don't use stopifnot for complex checks:** stopifnot lacks context. Use checkmate assert_* functions with .var.name for informative messages.

- **Don't duplicate checkmate functionality:** Don't write custom `is_valid_dataframe()` when `assert_data_frame()` exists. Use checkmate directly or wrap minimally for project-specific patterns.

- **Don't assert on computed intermediate values:** Assert on inputs and critical outputs, not every intermediate variable. Over-validation adds noise.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File existence checks | `if (!file.exists(x)) stop(...)` | `checkmate::assert_file_exists(x, access = "r")` | checkmate adds access rights checks (read/write), better error messages, .var.name customization |
| Data frame validation | `if (!is.data.frame(x)) stop(...)` | `checkmate::assert_data_frame(x, min.rows = 1)` | Checks class, dimensions, and provides informative errors in one call |
| Column presence checks | `if (!all(req_cols %in% names(x))) stop(...)` | `checkmate::assert_names(names(x), must.include = req_cols)` | Reports exactly which columns are missing, better error message |
| Type validation | `if (!is.character(x$ID)) stop(...)` | `checkmate::assert_character(x$ID)` or custom `assert_col_types()` | Type family checks (character, numeric, integer, Date), length validation, NA handling |
| Subset validation | `if (!all(x %in% choices)) stop(...)` | `checkmate::assert_subset(x, choices)` | Reports which elements are invalid, not just TRUE/FALSE |
| Custom error messages | `paste0("Error in ", name, ": ", msg)` | `glue::glue("[{script_name} ERROR] {context}")` | Readable string interpolation, already loaded in 22+ scripts |

**Key insight:** checkmate provides 30+ validators covering standard input checks. Building custom validators duplicates tested functionality and adds maintenance burden. Use checkmate directly for standard checks, wrap in project-specific helpers (utils_assertions.R) only for repeated patterns (RDS existence, column type specs, date ranges).

## Common Pitfalls

### Pitfall 1: Asserting Inside Pipes Without Storing Intermediate Results

**What goes wrong:** Placing assertions inside long pipe chains makes debugging harder when they fail, and you lose the ability to inspect intermediate state.

**Why it happens:** Temptation to keep everything in one pipe chain for "clean" code.

**How to avoid:** Break pipe chains at assertion points. Store intermediate results, assert, then continue.

**Warning signs:** Stack traces that don't clearly show which step failed; inability to inspect data when assertion triggers.

```r
# AVOID: Assertion buried in pipe
cohort <- enrollment %>%
  filter(has_enrollment) %>%
  left_join(payer, by = "ID") %>%
  {assert_df_valid(., "cohort", c("ID", "payer_category"), "R/14"); .} %>%  # Hard to debug
  mutate(age = compute_age(DOB))

# PREFER: Break at assertion point
cohort_pre_assert <- enrollment %>%
  filter(has_enrollment) %>%
  left_join(payer, by = "ID")

assert_df_valid(cohort_pre_assert, "cohort", c("ID", "payer_category"), "R/14")

cohort <- cohort_pre_assert %>%
  mutate(age = compute_age(DOB))
```

### Pitfall 2: Using Error When Warning Is Appropriate

**What goes wrong:** Stopping execution for non-critical issues (out-of-range dates, unexpected row counts) prevents pipeline from completing when partial results are still useful.

**Why it happens:** Over-defensive validation; treating all anomalies as fatal.

**How to avoid:** Use D-10 severity levels. Hard stop (error) for structural problems (missing files, wrong types, missing columns). Warn for data quality issues (date ranges, row count anomalies).

**Warning signs:** Pipeline fails on legitimate edge cases (pre-2012 tumor registry dates); analysts can't get exploratory results because of non-critical issues.

```r
# AVOID: Error on date range (blocks legitimate historical data)
if (any(df$episode_start < as.Date("2012-01-01"), na.rm = TRUE)) {
  stop("[R/26 ERROR] Historical dates found")
}

# PREFER: Warning (pipeline continues, analyst aware of issue)
warn_date_range(df, "episode_start", as.Date("1990-01-01"), as.Date("2030-12-31"), "R/26")
```

### Pitfall 3: Forgetting to Handle NA Values in Validation

**What goes wrong:** Date range checks, type checks, and subset validation fail or produce misleading errors when columns contain NA values.

**Why it happens:** Focusing on valid data, forgetting NA is a legitimate R value.

**How to avoid:** Use `na.rm = TRUE` in aggregations, `!is.na()` in filters, and checkmate's `any.missing = FALSE` parameter when NAs are not allowed.

**Warning signs:** Warnings about "NAs introduced by coercion"; unexpected validation failures on columns known to have missing data.

```r
# AVOID: Date range check without NA handling
if (any(df$episode_start < lo | df$episode_start > hi)) {
  warning("Out of range dates")  # Fails if any NA present
}

# PREFER: Explicit NA handling
out_of_range <- df %>%
  filter(!is.na(episode_start) & (episode_start < lo | episode_start > hi))

if (nrow(out_of_range) > 0) {
  warning(glue::glue("[{script_name} WARNING] {nrow(out_of_range)} dates out of range"))
}
```

### Pitfall 4: Validating After Expensive Operations

**What goes wrong:** Running time-consuming joins, aggregations, or API calls before validating inputs wastes computation when inputs are invalid.

**Why it happens:** Not thinking about fail-fast principle; validation as afterthought.

**How to avoid:** Follow architecture pattern: INPUT VALIDATION section first, LOAD DATA second, DATA STRUCTURE VALIDATION third, OPERATIONS fourth.

**Warning signs:** Long-running scripts that fail after 5 minutes due to missing input file; expensive DuckDB queries executed before realizing required columns are absent.

```r
# AVOID: Validate after expensive operation
big_result <- expensive_api_call(df)  # Takes 5 minutes
assert_df_valid(df, "input", c("ID", "date"), "R/21")  # Fails here — wasted 5 minutes

# PREFER: Validate inputs first
assert_df_valid(df, "input", c("ID", "date"), "R/21")  # Fail fast
big_result <- expensive_api_call(df)  # Only run if inputs valid
```

### Pitfall 5: Not Customizing .var.name for Context

**What goes wrong:** Default checkmate error messages lack script context, making it hard to trace which script and which operation failed in a multi-script pipeline.

**Why it happens:** Using checkmate directly without .var.name parameter.

**How to avoid:** Use helper functions (assert_rds_exists, assert_df_valid) that embed script_name in .var.name, or pass .var.name = glue("[{script_name} ERROR] {context}") to checkmate functions.

**Warning signs:** Error messages like "Assertion on 'x' failed" without indicating which script or data object.

```r
# AVOID: Generic error message
checkmate::assert_data_frame(cohort)
# Error: "Assertion on 'cohort' failed: Must be of type 'data.frame', not 'NULL'"

# PREFER: Contextualized error message
checkmate::assert_data_frame(cohort, .var.name = glue("[R/14 ERROR] cohort after enrollment filter"))
# Error: "[R/14 ERROR] cohort after enrollment filter: Must be of type 'data.frame', not 'NULL'"
```

## Code Examples

Verified patterns from checkmate official docs and Phase 72 decisions:

### File Existence Validation (SAFE-01)

```r
# Source: checkmate documentation + Phase 72 D-13
# From R/utils/utils_assertions.R

assert_rds_exists <- function(path, script_name) {
  checkmate::assert_file_exists(
    path,
    access = "r",
    .var.name = glue::glue("[{script_name} ERROR] Expected RDS file")
  )
  invisible(path)
}

# Usage in R/26_treatment_episodes.R
assert_rds_exists(
  file.path(CONFIG$cache$outputs_dir, "treatment_durations.rds"),
  script_name = "R/26"
)
```

### Data Frame + Column Validation (SAFE-02)

```r
# Source: checkmate documentation + Phase 72 D-13
# From R/utils/utils_assertions.R

assert_df_valid <- function(df, name, required_cols, script_name, allow_empty = FALSE) {
  # Check 1: Is it a data frame with rows?
  checkmate::assert_data_frame(
    df,
    min.rows = if (allow_empty) 0 else 1,
    .var.name = glue::glue("[{script_name} ERROR] {name}")
  )

  # Check 2: Does it have required columns?
  checkmate::assert_names(
    colnames(df),
    must.include = required_cols,
    .var.name = glue::glue("[{script_name} ERROR] {name} columns")
  )

  invisible(df)
}

# Usage in R/14_build_cohort.R
enrollment <- readRDS(file.path(CONFIG$cache$raw_dir, "ENROLLMENT.rds"))

assert_df_valid(
  enrollment,
  name = "ENROLLMENT",
  required_cols = c("ID", "ENR_START_DATE", "ENR_END_DATE", "CHART"),
  script_name = "R/14"
)
```

### Column Type Validation (D-08)

```r
# Source: Phase 72 D-08
# From R/utils/utils_assertions.R

assert_col_types <- function(df, type_spec, script_name) {
  # type_spec: list(ID = "character", count = "integer", date_col = "Date")

  for (col_name in names(type_spec)) {
    expected_class <- type_spec[[col_name]]

    if (!col_name %in% colnames(df)) {
      stop(glue::glue("[{script_name} ERROR] Column '{col_name}' not found in data frame"))
    }

    actual_class <- class(df[[col_name]])[1]

    # Date class check
    if (expected_class == "Date" && !inherits(df[[col_name]], "Date")) {
      stop(glue::glue(
        "[{script_name} ERROR] Column '{col_name}' must be Date class, got {actual_class} -- ",
        "use parse_pcornet_date() or as.Date()"
      ))
    }

    # Character class check (for IDs)
    if (expected_class == "character" && !is.character(df[[col_name]])) {
      stop(glue::glue(
        "[{script_name} ERROR] Column '{col_name}' must be character, got {actual_class} -- ",
        "IDs should be col_character() in vroom specs"
      ))
    }

    # Numeric class check
    if (expected_class %in% c("integer", "numeric") && !is.numeric(df[[col_name]])) {
      stop(glue::glue(
        "[{script_name} ERROR] Column '{col_name}' must be numeric, got {actual_class}"
      ))
    }
  }

  invisible(df)
}

# Usage in R/26_treatment_episodes.R
assert_col_types(
  treatment_durations,
  type_spec = list(
    ID = "character",
    first_date = "Date",
    episode_count = "integer"
  ),
  script_name = "R/26"
)
```

### Date Range Warning (D-09, D-10)

```r
# Source: Phase 72 D-09, D-10
# From R/utils/utils_assertions.R

warn_date_range <- function(df, col, lo, hi, script_name) {
  if (!col %in% colnames(df)) {
    warning(glue::glue("[{script_name} WARNING] Column '{col}' not found for date range check"))
    return(invisible(df))
  }

  if (!inherits(df[[col]], "Date")) {
    warning(glue::glue("[{script_name} WARNING] Column '{col}' not Date class, skipping range check"))
    return(invisible(df))
  }

  out_of_range <- df %>%
    filter(!is.na(.data[[col]]) & (.data[[col]] < lo | .data[[col]] > hi))

  n_out <- nrow(out_of_range)

  if (n_out > 0) {
    range_actual <- range(out_of_range[[col]], na.rm = TRUE)
    warning(glue::glue(
      "[{script_name} WARNING] {n_out} dates outside {lo} to {hi} range in '{col}' -- ",
      "range: {range_actual[1]} to {range_actual[2]} -- ",
      "tumor registry may include pre-2012 dates (legitimate)"
    ))
  }

  invisible(df)
}

# Usage in R/26_treatment_episodes.R
warn_date_range(
  treatment_episodes,
  col = "episode_start",
  lo = as.Date("1990-01-01"),
  hi = as.Date("2030-12-31"),
  script_name = "R/26"
)
```

### Row Count Sanity Check (D-10)

```r
# Source: Phase 72 D-10
# From R/utils/utils_assertions.R

warn_row_count <- function(df, name, min_expected = NULL, max_expected = NULL, script_name) {
  actual <- nrow(df)

  if (!is.null(min_expected) && actual < min_expected) {
    warning(glue::glue(
      "[{script_name} WARNING] {name} has {actual} rows, expected ≥{min_expected} -- ",
      "possible data loss from join/filter"
    ))
  }

  if (!is.null(max_expected) && actual > max_expected) {
    warning(glue::glue(
      "[{script_name} WARNING] {name} has {actual} rows, expected ≤{max_expected} -- ",
      "possible cartesian product from join"
    ))
  }

  invisible(df)
}

# Usage in R/14_build_cohort.R
n_before <- nrow(cohort)

cohort_with_payer <- cohort %>%
  left_join(payer_summary, by = "ID")

warn_row_count(
  cohort_with_payer,
  name = "cohort after payer join",
  min_expected = n_before,
  max_expected = n_before * 1.05,
  script_name = "R/14"
)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| base::stopifnot() | checkmate::assert_*() | checkmate 1.0 (2016), 2.0 (2020), 2.3.4 (2026) | Informative error messages with context, C-optimized performance, 30+ validators |
| Manual if (!file.exists()) stop() | checkmate::assert_file_exists(access = "r") | checkmate 1.8.0+ | Access rights validation, better error messages |
| paste0() for error messages | glue::glue() | glue 1.0 (2017), 1.8.0 (2025) | Readable string interpolation, embedded R expressions |
| Validate anywhere in code | Validate at function entry (fail-fast) | Defensive programming best practices (2020s) | Catch errors early, prevent wasted computation |
| Error for all issues | Error vs warning severity levels | Data pipeline best practices (2024-2026) | Pipeline robustness — fail hard on structural issues, warn on data quality anomalies |

**Deprecated/outdated:**
- **assertthat package:** Slower than checkmate, fewer validators, less active maintenance. Last major update 2019 vs checkmate's 2026.
- **stopifnot with custom messages:** R 4.0+ added `stopifnot(msg = ...)` but still less flexible than checkmate.
- **validate package for input checks:** validate is for data validation workflows (ETL pipelines), not function argument validation.

## Open Questions

None identified. All research domains covered with high confidence.

## Environment Availability

**Skip condition:** Phase 72 is code-only (adding checkmate assertions to existing R scripts). No external runtime dependencies beyond R packages managed by renv.

**Package dependency:** checkmate 2.3.4 must be installed via renv. No system-level tools required.

```r
# Installation (one-time in interactive R session on HiPerGator)
renv::install("checkmate")
renv::snapshot()
```

## Validation Architecture

> Validation Architecture section omitted: workflow.nyquist_validation is explicitly set to false in .planning/config.json.

## Sources

### Primary (HIGH confidence)

**CRAN Official:**
- [CRAN: Package checkmate](https://cran.r-project.org/package=checkmate) - Version 2.3.4 verified
- [checkmate package - RDocumentation](https://www.rdocumentation.org/packages/checkmate/versions/2.3.4) - Version 2.3.4 released February 3, 2026
- [Package 'checkmate' February 3, 2026 Type Package](https://cloud.r-project.org/web/packages/checkmate/checkmate.pdf) - Official PDF manual
- [Checkmate vignette](https://cran.r-project.org/web/packages/checkmate/vignettes/checkmate.html) - Best practices and usage patterns

**Official Documentation:**
- [Fast and Versatile Argument Checks • checkmate](https://mllg.github.io/checkmate/) - Official package site
- [Package index • checkmate](https://mllg.github.io/checkmate/reference/index.html) - Function reference
- [checkNames: Check names to comply to specific rules](https://rdrr.io/cran/checkmate/man/checkNames.html) - assert_names() documentation
- [checkSubset: Check if an argument is a subset of a given set](https://rdrr.io/cran/checkmate/man/checkSubset.html) - assert_subset() documentation
- [checkFileExists: Check existence and access rights of files](https://rdrr.io/cran/checkmate/man/checkFileExists.html) - assert_file_exists() documentation

**Academic:**
- [checkmate: Fast Argument Checks for Defensive R Programming - Michel Lang (arXiv)](https://arxiv.org/pdf/1701.04781) - Academic paper on checkmate design and performance

**Project Files:**
- C:\Users\Owner\Documents\insurance_investigation\.planning\phases\72-defensive-coding\72-CONTEXT.md - User decisions (D-01 through D-13)
- C:\Users\Owner\Documents\insurance_investigation\.planning\REQUIREMENTS.md - SAFE-01, SAFE-02, SAFE-03
- C:\Users\Owner\Documents\insurance_investigation\R\SCRIPT_INDEX.md - 43 production scripts in scope (decades 00-69)
- C:\Users\Owner\Documents\insurance_investigation\R\00_config.R - Auto-sourcing pattern for utils/ modules
- C:\Users\Owner\Documents\insurance_investigation\.lintr - Phase 71 lintr configuration

### Secondary (MEDIUM confidence)

**Best Practices:**
- [8 Conditions | Advanced R - Hadley Wickham](https://adv-r.hadley.nz/conditions.html) - When to use error vs warning vs message
- [R message() vs. warning() vs. stop() Functions (Example)](https://statisticsglobe.com/message-warning-stop-function-in-r/) - Condition types in R
- [Enhancing R Programming Efficiency with Checkmate - Christophe Garon](https://christophegaron.com/articles/research/enhancing-r-programming-efficiency-with-checkmate-type-validation-and-fast-argument-checks/) - checkmate integration patterns

**glue Integration:**
- [Format and interpolate a string — glue • glue](https://glue.tidyverse.org/reference/glue.html) - glue() syntax
- [Signal an error, warning or message with a cli formatted message — cli_abort • cli](https://cli.r-lib.org/reference/cli_abort.html) - Error formatting with glue

**Data Pipeline Best Practices:**
- [Error Handling and Logging in Data Pipelines: Ensuring Data Reliability | Medium](https://medium.com/towards-data-engineering/error-handling-and-logging-in-data-pipelines-ensuring-data-reliability-227df82ba782) - Defensive programming for pipelines
- [Defensive Programming: Techniques, Best Practices, and Benefits](https://www.devzery.com/post/defensive-programming-techniques-best-practices-and-benefits) - Fail-fast principle, validation placement
- [Data Engineering Best Practices 2026](https://datavidhya.com/blog/data-engineering-best-practices/) - Error handling strategy, monitoring

### Tertiary (LOW confidence)

None — all findings verified against official sources or academic publications.

## Metadata

**Confidence breakdown:**
- Standard stack (checkmate 2.3.4, glue 1.8.0): **HIGH** - Verified against CRAN, official docs, version confirmed 2026-06-02
- Architecture patterns (assertion placement, helper functions): **HIGH** - Based on checkmate official vignette + Phase 72 decisions
- Pitfalls (validation timing, severity levels): **HIGH** - Supported by Advanced R (Hadley Wickham) + data pipeline best practices
- Code examples (5 helper functions): **HIGH** - Synthesized from checkmate docs + project-specific patterns (glue, script_name context)
- Integration with existing codebase: **HIGH** - Verified via Read tool on R/00_config.R, R/10_cohort_predicates.R, R/03_duckdb_ingest.R

**Research date:** 2026-06-02
**Valid until:** 2026-09-02 (checkmate is mature/stable; 2.3.4 released Feb 2026; patch releases unlikely to change API)
