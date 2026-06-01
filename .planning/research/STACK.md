# Technology Stack — v2.0 Codebase Cleanup & Documentation

**Project:** PCORnet Payer Variable Investigation (R Pipeline)
**Milestone:** v2.0 Codebase Cleanup & Documentation
**Researched:** 2026-06-01

## Executive Summary

**FOCUSED ADDITIONS for documentation, linting, and defensive coding.** The v2.0 milestone requires stack additions for:

1. **Code documentation** — roxygen2-style comments for functions (NOT full package documentation)
2. **Style checking & fixing** — lintr for detection, styler for auto-formatting
3. **Defensive coding** — checkmate for input validation with minimal overhead
4. **Smoke testing** — testthat for pipeline integrity verification
5. **File operations** — fs for safe file renaming during reorganization
6. **Enhanced logging** — logger for structured logging (optional upgrade from glue)

**All packages are CRAN-stable, mature (5-10+ years), and widely adopted.** Zero bleeding-edge dependencies. Integration risk is minimal — these are standard R development tools.

**Key principle:** Add capabilities for code quality WITHOUT changing pipeline logic or dependencies. Documentation and testing infrastructure should be transparent to existing data processing code.

---

## New Capability Requirements → Stack Mapping

### Capability 1: Script Documentation with Section Headers

**Requirement:** Add section header comments and key-logic comments to every R script for maintainability

**Stack solution:**
| Component | Package | Version | Purpose |
|-----------|---------|---------|---------|
| Inline documentation | Base R comments | — | Section headers via `# ===== SECTION NAME =====` |
| Function documentation | roxygen2-style comments | — | Optional #' comments for complex functions |
| Documentation linting | lintr | 3.3.0-1 | Detect missing/malformed comments via custom linters |

**Implementation approach:**
```r
# ============================================================================
# SECTION 1: DATA LOADING
# ============================================================================
# Purpose: Load PCORnet tables from DuckDB backend
# Inputs: None (uses global USE_DUCKDB flag from R/00_config.R)
# Outputs: enrollment_tbl, diagnosis_tbl, procedures_tbl
# Dependencies: R/00_config.R must be sourced first

enrollment_tbl <- get_pcornet_table("ENROLLMENT")
diagnosis_tbl <- get_pcornet_table("DIAGNOSIS")


# ============================================================================
# SECTION 2: COHORT FILTERING
# ============================================================================
# Purpose: Apply named predicate filter chain for HL cohort
# Key decision: Inner join on SOURCE to keep only primary site enrollment

#' Check for Hodgkin Lymphoma diagnosis codes
#'
#' @param diagnosis_df Data frame with DX column (ICD-9/10 codes)
#' @return Logical vector indicating HL diagnosis presence
#' @details Matches 149 ICD codes from HL_ICD_CODES list (C81.* family)
has_hl_diagnosis <- function(diagnosis_df) {
  diagnosis_df %>%
    filter(str_remove_all(DX, "\\.") %in% HL_ICD_CODES) %>%
    pull(ID) %>%
    unique()
}

cohort <- enrollment_tbl %>%
  filter(ID %in% has_hl_diagnosis(diagnosis_tbl))
```

**Why this approach:**
- **Base R comments for sections:** No package overhead, IDE-friendly, universal standard
- **roxygen2-style for complex logic:** Familiar to R developers, works without building package docs
- **lintr validation:** Can create custom linters to enforce section header presence

**When NOT to use full roxygen2 package documentation:**
- This is a **pipeline project, not an R package** — no NAMESPACE, no man/ directory
- Full roxygen2::roxygenize() workflow is overkill for standalone scripts
- roxygen2-style **comments** are fine (readable, self-documenting), full roxygen2 **build process** is not needed

**References:**
- [Tidyverse Style Guide: Comments](https://style.tidyverse.org/syntax.html#comments) — Section headers and inline documentation
- [roxygen2 syntax reference](https://roxygen2.r-lib.org/articles/rd.html) — roxygen2-style comment format (use syntax, skip build)

**Confidence:** **HIGH** — Comments are base R, no package dependency. roxygen2-style syntax is well-documented standard.

---

### Capability 2: Automated Style Checking (Detection)

**Requirement:** Lint all R scripts to detect style violations, inconsistent naming, and code smells

**Stack solution:**
| Component | Package | Version | Publication Date |
|-----------|---------|---------|------------------|
| R code linter | lintr | 3.3.0-1 | 2025-11-27 |
| Style guide | tidyverse | (built into lintr) | — |

**Implementation approach:**
```r
# Install lintr (one-time, add to renv)
install.packages("lintr")

# Configure project-level linting rules
# Create .lintr file in project root:
linters: linters_with_defaults(
    line_length_linter(120),  # Allow 120 chars (not 80) for data pipelines
    object_name_linter = NULL,  # Disable — PCORnet uses ALLCAPS column names
    commented_code_linter(),  # Flag commented-out code blocks
    T_and_F_symbol_linter()  # Flag T/F instead of TRUE/FALSE
  )
exclusions: list(
    "renv/",  # Exclude renv library
    "output/",  # Exclude output directory
    ".planning/"  # Exclude planning artifacts
  )

# Lint entire R/ directory
lintr::lint_dir("R/")

# Lint single file during development
lintr::lint("R/01_data_loading.R")

# Run in CI/GitHub Actions (future)
# lintr::lint_package() for package-structured projects
```

**Default checks (tidyverse style guide):**
- Line length (default 80 chars, configurable to 120)
- Object naming (snake_case for variables, PascalCase for S3/R6 classes)
- Spacing around operators (`x <- 1` not `x<-1`)
- Indentation (2 spaces, not tabs)
- Trailing whitespace detection
- Commented-out code detection
- T/F vs TRUE/FALSE usage

**Custom linters for this project:**
```r
# Example: Enforce section headers in scripts
section_header_linter <- function() {
  Linter(function(source_expression) {
    # Check for at least one section header (# ===...)
    # Return lint if missing
  })
}
```

**Why lintr:**
- **Non-invasive** — detection only, doesn't modify code (unlike styler)
- **Tidyverse default** — matches project's existing style (dplyr, ggplot2)
- **Customizable** — can disable object_name_linter for ALLCAPS PCORnet columns
- **IDE integration** — works with RStudio, VS Code, Emacs, Vim

**Why NOT base R's code analyzer:**
- Base R has `codetools::checkUsage()` for unused variables, but no style checking
- lintr is the standard for style enforcement in tidyverse ecosystem

**References:**
- [lintr documentation](https://lintr.r-lib.org/) — Full linter reference
- [CRAN lintr](https://cran.r-project.org/package=lintr) — v3.3.0-1 (Nov 2025)
- [Using lintr vignette](https://cran.r-project.org/web/packages/lintr/vignettes/lintr.html) — Configuration and usage
- [lintr GitHub](https://github.com/r-lib/lintr) — Custom linter examples

**Confidence:** **HIGH** — lintr is mature (10+ years), widely adopted (tidyverse standard), actively maintained.

---

### Capability 3: Automated Style Fixing (Correction)

**Requirement:** Auto-format R scripts to tidyverse style, especially after renumbering

**Stack solution:**
| Component | Package | Version | Publication Date |
|-----------|---------|---------|------------------|
| Auto-formatter | styler | 1.11.0 | 2025-10-13 |
| Style guide | tidyverse | (built into styler) | — |

**Implementation approach:**
```r
# Install styler (one-time, add to renv)
install.packages("styler")

# Format entire R/ directory (after renumbering)
styler::style_dir("R/")

# Format single file
styler::style_file("R/01_data_loading.R")

# RStudio Addin: select code → Addins → "Style selection"
# Keyboard shortcut: Ctrl+Shift+A (configurable)

# Preview changes without modifying files (dry run)
styler::style_dir("R/", dry = "on")
```

**What styler fixes:**
- Spacing around operators (`x<-1` → `x <- 1`)
- Indentation (tabs → 2 spaces)
- Line breaks (long function calls → multi-line with proper indentation)
- Brace placement (`if (x) {` not `if (x){`)
- Trailing commas in function arguments
- `=` → `<-` for assignment (configurable)

**styler + lintr workflow:**
1. **styler** first: Auto-fix what can be fixed automatically
2. **lintr** second: Detect remaining issues (commented code, long functions, etc.)
3. Manual fix: Address lintr warnings that styler can't auto-fix

**Why styler:**
- **Saves time** — no manual formatting after bulk renumbering
- **Consistency** — entire codebase styled identically
- **Non-destructive** — can preview with `dry = "on"` before applying
- **Tidyverse aligned** — matches existing pipeline style

**Customization example:**
```r
# Use custom style guide (if needed)
my_style <- function() {
  transformers <- tidyverse_style(indent_by = 4)  # 4 spaces instead of 2
  transformers
}

styler::style_dir("R/", transformers = my_style())
```

**When NOT to use styler:**
- **Don't run on output CSVs/Excel files** — only R code
- **Don't style renv/ directory** — package library is managed by renv
- **Caution with data.table syntax** — styler may break `DT[i, j, by]` formatting (not an issue for this tidyverse project)

**References:**
- [styler documentation](https://styler.r-lib.org/) — Full API reference
- [CRAN styler](https://cran.r-project.org/package=styler) — v1.11.0 (Oct 2025)
- [Tidyverse style guide](https://style.tidyverse.org/) — Rules that styler enforces
- [styler RStudio Addin](https://styler.r-lib.org/) — Interactive styling

**Confidence:** **HIGH** — styler is mature (7+ years), widely used in tidyverse ecosystem, non-invasive (can preview).

---

### Capability 4: Defensive Coding with Input Validation

**Requirement:** Add input validation to functions — check required files exist, types are correct, row counts are reasonable

**Stack solution:**
| Component | Package | Version | Publication Date |
|-----------|---------|---------|------------------|
| Input validation | checkmate | 2.3.4 | 2026-02-03 |
| Assertions | checkmate | (same) | (same) |

**Implementation approach:**
```r
# Install checkmate (one-time, add to renv)
install.packages("checkmate")

library(checkmate)

# Example 1: Validate function inputs
load_cohort_data <- function(rds_path, expected_min_rows = 1000) {
  # Check file exists
  assert_file_exists(rds_path, access = "r", extension = "rds")

  # Load data
  cohort <- readRDS(rds_path)

  # Check data structure
  assert_data_frame(cohort, min.rows = expected_min_rows)
  assert_names(colnames(cohort), must.include = c("ID", "ENROLL_DATE", "SOURCE"))

  # Check data types
  assert_character(cohort$ID, min.chars = 1, any.missing = FALSE)
  assert_date(cohort$ENROLL_DATE, any.missing = FALSE)

  cohort
}

# Example 2: Validate data pipeline assumptions
validate_payer_mapping <- function(payer_df) {
  # Check required columns exist
  assert_names(colnames(payer_df),
               must.include = c("RAW_PAYER_TYPE_PRIMARY", "amc_payer_category"))

  # Check valid payer categories (from R/00_config.R AMC_PAYER_LOOKUP)
  valid_categories <- c("Medicaid", "Medicare", "Private", "Dual-eligible",
                        "Self-pay", "Other govt", "Other/unknown", "Missing")
  assert_subset(payer_df$amc_payer_category, valid_categories)

  # Check no negative tier ranks
  if ("tier_rank" %in% colnames(payer_df)) {
    assert_integerish(payer_df$tier_rank, lower = 1, upper = 8)
  }

  invisible(payer_df)  # Return invisibly for piping
}

# Example 3: Lightweight checks with qassert (faster for simple types)
process_treatment_codes <- function(code_vector) {
  qassert(code_vector, "s+")  # Non-empty character vector
  # ... processing logic
}

# Example 4: Conditional validation (development vs production)
if (Sys.getenv("VALIDATE_INPUTS") == "TRUE") {
  validate_payer_mapping(payer_resolved)
}
```

**checkmate function families:**
| Function Pattern | Purpose | Example |
|------------------|---------|---------|
| `assert_*()` | Stop with error if check fails | `assert_file_exists("data.rds")` |
| `check_*()` | Return error message or TRUE | `check_data_frame(df, min.rows = 100)` |
| `test_*()` | Return TRUE/FALSE silently | `test_directory_exists("output/")` |
| `expect_*()` | testthat integration | `expect_file_exists("cohort.rds")` |
| `qassert()` | DSL for fast type checks | `qassert(x, "n+")` # numeric, non-empty |

**Why checkmate over base R stopifnot():**
- **Better error messages:** "Variable 'x': Must be of type 'character', not 'integer'" vs base R's cryptic messages
- **Performance:** C implementation — 2-5x faster than base R checks
- **Comprehensive:** 100+ assertion functions (file existence, data frame structure, date validity, etc.)
- **testthat integration:** `expect_*()` functions extend testthat for unit tests

**Why checkmate over assertthat:**
- **5x faster** — checkmate is C-optimized, assertthat is pure R
- **More comprehensive** — checkmate has 100+ checks, assertthat has ~20
- **Better for data validation** — checkmate has data frame/column-specific assertions

**When to use checkmate:**
- **Function entry points:** Validate inputs to any function called by multiple scripts
- **Data quality gates:** After loading RDS files, check expected structure
- **Pipeline assumptions:** Validate payer mappings, ICD code formats, date ranges

**When NOT to overuse:**
- **Hot loops:** Don't validate inside `map()` or `for` loops — validate once before loop
- **Intermediate pipeline steps:** tidylog already logs row counts — don't duplicate
- **User-facing scripts:** This is a research pipeline, not production software — validate critical paths only

**References:**
- [checkmate documentation](https://mllg.github.io/checkmate/) — Full function reference
- [CRAN checkmate](https://cran.r-project.org/package=checkmate) — v2.3.4 (Feb 2026)
- [R Journal article](https://journal.r-project.org/articles/RJ-2017-028/) — Performance benchmarks and design rationale
- [checkmate vignette](https://cran.r-project.org/web/packages/checkmate/vignettes/checkmate.html) — Usage patterns

**Confidence:** **HIGH** — checkmate is mature (9+ years), peer-reviewed (R Journal), widely adopted for defensive R programming.

---

### Capability 5: Smoke Testing for Pipeline Integrity

**Requirement:** Create smoke test script to verify pipeline integrity after renumbering (scripts run, produce expected outputs)

**Stack solution:**
| Component | Package | Version | Publication Date |
|-----------|---------|---------|------------------|
| Test framework | testthat | 3.3.2 | 2026-01-11 |
| File operations | fs | 2.1.0 | 2026-04-18 |

**Implementation approach:**
```r
# Install testthat + fs (one-time, add to renv)
install.packages(c("testthat", "fs"))

# Create tests/testthat/ directory structure
fs::dir_create("tests/testthat")

# tests/testthat.R (test runner)
library(testthat)
test_dir("tests/testthat")

# tests/testthat/test_pipeline_integrity.R (smoke tests)
library(testthat)
library(fs)

test_that("All R scripts are numbered sequentially", {
  r_files <- dir_ls("R/", glob = "*.R")
  script_numbers <- str_extract(r_files, "\\d{2}")

  # Check no gaps in numbering
  expected_sequence <- sprintf("%02d", seq_along(script_numbers))
  expect_equal(sort(script_numbers), expected_sequence)
})

test_that("Required RDS artifacts exist before downstream scripts", {
  # Script 05 requires cohort.rds from script 04
  if (file_exists("R/05_something.R")) {
    expect_true(file_exists("cache/cohort.rds"),
                info = "R/05 depends on cohort.rds from R/04")
  }
})

test_that("All source() calls reference valid file paths", {
  # Parse all R scripts, extract source() calls, verify paths exist
  r_files <- dir_ls("R/", glob = "*.R")

  for (script in r_files) {
    source_calls <- str_extract_all(read_file(script), 'source\\("([^"]+)"\\)')
    # Verify each sourced file exists
    # (Implementation details...)
  }
})

test_that("Config file has all required constants", {
  source("R/00_config.R")

  expect_true(exists("AMC_PAYER_LOOKUP"), info = "AMC_PAYER_LOOKUP missing from config")
  expect_true(exists("HL_ICD_CODES"), info = "HL_ICD_CODES missing from config")
  expect_true(exists("USE_DUCKDB"), info = "USE_DUCKDB flag missing from config")
})

test_that("Critical pipeline scripts run without error (smoke test)", {
  # Test key scripts in isolation (not full pipeline)
  expect_no_error(source("R/00_config.R"))

  # For data-loading scripts, use skip_if_not() to run only on HiPerGator
  skip_if_not(file_exists("/blue/erin.mobley-hl.bcu/clean/rds/"),
              message = "Skipping data load tests (not on HiPerGator)")

  expect_no_error(source("R/01_data_loading.R"))
})

test_that("Output directory structure exists", {
  expect_true(dir_exists("output/"))
  expect_true(dir_exists("cache/"))
  expect_true(dir_exists(".planning/"))
})
```

**Why testthat:**
- **Standard R testing framework** — used by 10,000+ CRAN packages
- **Readable syntax** — `expect_*()` functions read like assertions
- **IDE integration** — RStudio "Run Tests" button, Ctrl+Shift+T shortcut
- **Flexible scoping** — can test individual functions OR smoke-test entire scripts

**Why fs for file operations:**
- **Cross-platform** — works on Windows (HiPerGator local dev) and Linux (HiPerGator HPC)
- **Consistent API** — `dir_ls()`, `file_exists()`, `path_abs()` replace base R's inconsistent file functions
- **Better error messages** — fs functions fail loudly instead of returning error codes
- **UTF-8 safe** — handles non-ASCII filenames correctly (base R struggles on Windows)

**Smoke test vs unit test distinction:**
- **Smoke test:** Does the pipeline run end-to-end without crashing? (integration test)
- **Unit test:** Does `has_hl_diagnosis()` correctly filter 149 ICD codes? (function-level test)

**For this milestone, prioritize smoke tests:**
- ✅ Scripts numbered sequentially with no gaps
- ✅ `source()` calls reference existing files
- ✅ Required RDS artifacts exist before downstream consumers
- ✅ Config file has all expected constants
- ✅ Critical scripts run without error
- ⚠️ Unit tests for individual functions (nice-to-have, defer to future milestone)

**When to run smoke tests:**
- **After renumbering all scripts** — verify no broken `source()` references
- **After consolidating lookup tables** — verify all scripts find constants in R/00_config.R
- **Before milestone completion** — ensure pipeline integrity

**References:**
- [testthat documentation](https://testthat.r-lib.org/) — Full API reference
- [CRAN testthat](https://cran.r-project.org/package=testthat) — v3.3.2 (Jan 2026)
- [R Packages (2e) Testing Basics](https://r-pkgs.org/testing-basics.html) — testthat usage guide
- [fs documentation](https://fs.r-lib.org/) — Cross-platform file operations
- [CRAN fs](https://cran.r-project.org/package=fs) — v2.1.0 (Apr 2026)

**Confidence:** **HIGH** — testthat is industry standard (14+ years), fs is mature and widely adopted (tidyverse ecosystem).

---

### Capability 6: Safe File Renaming During Reorganization

**Requirement:** Renumber ~80 R scripts from arbitrary names (e.g., R/35_payer_code_frequency_av_th.R) to sequential numbering (e.g., R/47_payer_code_frequency_av_th.R)

**Stack solution:**
| Component | Package | Version | Publication Date |
|-----------|---------|---------|------------------|
| File operations | fs | 2.1.0 | 2026-04-18 |
| Path manipulation | fs | (same) | (same) |

**Implementation approach:**
```r
library(fs)
library(dplyr)
library(stringr)

# Step 1: Inventory current scripts
scripts <- dir_ls("R/", glob = "*.R") %>%
  tibble(old_path = .) %>%
  mutate(
    old_name = path_file(old_path),
    old_number = str_extract(old_name, "^\\d{2}") %>% as.integer(),
    script_purpose = str_remove(old_name, "^\\d{2}_")
  )

# Step 2: Define new execution order (manual mapping)
execution_order <- tribble(
  ~old_number, ~new_number, ~script_purpose,
  0,  1,  "config.R",
  1,  2,  "data_loading.R",
  2,  3,  "payer_harmonization.R",
  # ... (manual specification of logical order)
  35, 47, "payer_code_frequency_av_th.R",
  36, 48, "tiered_same_day_payer.R"
)

# Step 3: Generate new file paths
renaming_plan <- scripts %>%
  left_join(execution_order, by = c("old_number", "script_purpose")) %>%
  mutate(
    new_name = sprintf("%02d_%s", new_number, script_purpose),
    new_path = path("R", new_name)
  )

# Step 4: Validate no conflicts (two scripts mapping to same new number)
stopifnot(!any(duplicated(renaming_plan$new_number)))

# Step 5: Preview renaming plan
renaming_plan %>%
  select(old_name, new_name) %>%
  print(n = Inf)

# Step 6: Execute renaming (CAUTION: review preview first!)
# fs::file_move() fails if destination exists (safety check)
for (i in seq_len(nrow(renaming_plan))) {
  file_move(renaming_plan$old_path[i], renaming_plan$new_path[i])
  cat(sprintf("Renamed: %s -> %s\n",
              renaming_plan$old_name[i],
              renaming_plan$new_name[i]))
}

# Step 7: Update source() calls in all scripts
update_source_calls <- function(script_path, renaming_plan) {
  content <- read_file(script_path)

  for (i in seq_len(nrow(renaming_plan))) {
    old_pattern <- sprintf('source\\("R/%s"\\)', renaming_plan$old_name[i])
    new_replacement <- sprintf('source("R/%s")', renaming_plan$new_name[i])
    content <- str_replace_all(content, fixed(old_pattern), new_replacement)
  }

  write_file(content, script_path)
}

# Apply to all R scripts
walk(dir_ls("R/", glob = "*.R"), update_source_calls, renaming_plan = renaming_plan)
```

**Why fs over base R file.rename():**
- **Fails loudly** — `file_move()` errors if destination exists (prevents accidental overwrites)
- **Cross-platform** — works identically on Windows and Linux
- **Atomic operations** — `file_move()` is atomic (no partial state if interrupted)
- **Better error messages** — "Cannot move 'old.R' to 'new.R': file exists" vs base R's error code

**Safety measures:**
1. **Preview plan first** — print renaming table, verify manually
2. **Check for duplicates** — ensure no two scripts map to same new number
3. **Backup first** — `git commit` before renaming (can revert if needed)
4. **Dry run option** — can add `dry = TRUE` parameter to preview without executing

**Git integration:**
```r
# After renaming, Git tracks as move (preserves history)
# git add -A
# git commit -m "Renumber scripts 01-80 in logical execution order"
```

**References:**
- [fs::file_move documentation](https://fs.r-lib.org/reference/file_move.html) — Atomic file renaming
- [fs package overview](https://fs.r-lib.org/) — Cross-platform file operations
- [CRAN fs](https://cran.r-project.org/package=fs) — v2.1.0 (Apr 2026)

**Confidence:** **HIGH** — fs is production-ready (tidyverse ecosystem), widely used, safer than base R file operations.

---

### Capability 7: Enhanced Logging (Optional Upgrade)

**Requirement:** Structured logging for debugging, better than `glue()` + `cat()` for complex pipelines

**Stack solution (OPTIONAL):**
| Component | Package | Version | Publication Date | Status |
|-----------|---------|---------|------------------|--------|
| Structured logging | logger | 0.4.2 | 2026-05-10 | OPTIONAL |
| Current approach | glue + cat | (base R) | — | VALIDATED |

**Implementation approach (if adopted):**
```r
# Install logger (OPTIONAL, only if glue/cat becomes insufficient)
install.packages("logger")

library(logger)

# Configure logging
log_threshold(INFO)  # Log INFO and above (DEBUG, INFO, WARN, ERROR, FATAL)
log_appender(appender_tee("logs/pipeline.log"))  # Write to file + console

# Replace glue/cat with structured logging
# OLD approach (current):
cat(glue("Loaded {nrow(cohort)} patients from {rds_path}\n"))

# NEW approach (logger):
log_info("Loaded {nrow(cohort)} patients from {rds_path}")
log_warn("Missing death dates for {n_missing} patients")
log_error("DuckDB connection failed: {err$message}")

# Conditional logging by namespace (per-script logging)
log_info("Starting payer harmonization", namespace = "payer")
log_info("Cohort filtering complete", namespace = "cohort")

# Can filter logs by namespace in output
log_threshold(WARN, namespace = "payer")  # Only warnings from payer scripts
```

**Why logger over current glue/cat approach:**
- **Severity levels** — can filter DEBUG vs INFO vs WARN vs ERROR
- **Namespaces** — can log per-script and filter outputs selectively
- **Structured output** — JSON logging for machine-readable logs (future CI integration)
- **Appenders** — log to file + console simultaneously

**Why logger over futile.logger or lgr:**
- **Simpler API** — `log_info()` vs futile.logger's `flog.info()`
- **Modern conventions** — snake_case function names, tidy-friendly
- **Lighter weight** — fewer dependencies than lgr (lgr is R6-heavy)

**When NOT to adopt logger:**
- **Current glue/cat works fine** — don't fix what isn't broken
- **Small pipeline** — logger shines in large multi-developer projects, less critical for solo research pipeline
- **No CI/CD** — structured logging benefits CI systems that parse JSON logs

**Recommendation:** **DEFER to future milestone.** Current `glue()` + `cat()` + `tidylog` provides sufficient logging. Adopt `logger` only if:
1. Need to filter logs by severity (e.g., suppress DEBUG in production runs)
2. Multiple developers need per-script log namespaces
3. CI/CD integration requires machine-readable logs

**If adopted, integrate with tidylog:**
```r
# tidylog prints to stderr by default
# logger can capture tidylog output and route to file
```

**References:**
- [logger documentation](https://daroczig.github.io/logger/) — Full API reference
- [CRAN logger](https://cran.r-project.org/package=logger) — v0.4.2 (May 2026)
- [Introduction to logger](https://cran.r-project.org/web/packages/logger/vignettes/Intro.html) — Usage patterns
- [Logging from R Packages](https://daroczig.github.io/logger/articles/r_packages.html) — Namespace best practices

**Confidence:** **MEDIUM** — logger is mature and well-documented, but **not critical for v2.0**. Mark as OPTIONAL.

---

## Recommended Stack Additions for v2.0

### Required (Add to renv)

| Package | Version | Purpose | Why |
|---------|---------|---------|-----|
| **lintr** | 3.3.0-1 | Style checking | Detect violations without modifying code; tidyverse default linters |
| **styler** | 1.11.0 | Auto-formatting | Fix spacing, indentation, line breaks after bulk renumbering |
| **checkmate** | 2.3.4 | Input validation | Defensive coding for file existence, data structure checks; C-optimized performance |
| **testthat** | 3.3.2 | Smoke testing | Verify pipeline integrity after renumbering (sequential numbering, source() calls, RDS dependencies) |
| **fs** | 2.1.0 | File operations | Safe cross-platform file renaming; atomic operations prevent partial state |

### Optional (Defer or Evaluate During Implementation)

| Package | Version | Purpose | When to Adopt |
|---------|---------|---------|---------------|
| **logger** | 0.4.2 | Structured logging | If glue/cat becomes insufficient; useful for severity filtering and multi-developer namespaces |

### Not Needed (Use Base R or Existing Stack)

| Capability | Solution | Why No Package Needed |
|------------|----------|----------------------|
| Section headers | Base R comments `# =====` | No package overhead, IDE-friendly, universal |
| Function comments | roxygen2-style `#'` syntax | Use syntax without building package docs; readable without roxygen2::roxygenize() |
| Reference manual | RMarkdown or Quarto | Already validated in v1.0 for PPTX generation; can reuse for documentation |

---

## Installation

### On HiPerGator (HPC Environment)

```bash
# Load R module (version 4.4.2+)
module load R/4.4.2

# Start R interactively
R
```

```r
# In R console:
# Install new packages for v2.0
install.packages(c("lintr", "styler", "checkmate", "testthat", "fs"))

# Optional (defer unless needed):
# install.packages("logger")

# Update renv snapshot
renv::snapshot()

# Exit R
q()
```

### Local Development (Optional)

```r
# Clone project and restore environment
renv::restore()

# Verify new packages installed
library(lintr)
library(styler)
library(checkmate)
library(testthat)
library(fs)
```

---

## Integration with Existing Stack

### 1. lintr + tidylog (No Conflict)

**Current:** tidylog automatically logs dplyr operations (row counts, joins)

**New:** lintr checks code style statically (before execution)

**Integration:** Independent tools, no conflict. tidylog runs during execution, lintr runs during development.

### 2. styler + RStudio (IDE Integration)

**RStudio Addin:** After installing styler, RStudio adds "Style selection" and "Style active file" to Addins menu

**Keyboard shortcut:** Assign Ctrl+Shift+A to "Style selection" for quick formatting

**Auto-format on save:** Can configure `.Rprofile` to run styler on save (optional, may be intrusive)

### 3. checkmate + testthat (Built-in Integration)

**testthat extensions:** checkmate provides `expect_*()` functions that extend testthat

```r
# In tests/testthat/test_cohort.R
library(testthat)
library(checkmate)

test_that("Cohort RDS has valid structure", {
  cohort <- readRDS("cache/cohort.rds")

  # checkmate's expect_* functions integrate with testthat
  expect_data_frame(cohort, min.rows = 1000)
  expect_names(colnames(cohort), must.include = c("ID", "ENROLL_DATE"))
})
```

### 4. fs + here (Path Management)

**Current:** `here()` provides project-relative paths (`here("R", "01_config.R")`)

**New:** fs provides cross-platform file operations (`file_move()`, `dir_ls()`)

**Integration:** Complementary. Use `here()` for path construction, fs for file operations.

```r
library(here)
library(fs)

# Combine here + fs
scripts <- dir_ls(here("R"), glob = "*.R")
file_move(here("R", "old.R"), here("R", "new.R"))
```

### 5. logger + tidylog (Optional Future Integration)

**If logger is adopted**, can route tidylog output through logger appenders:

```r
# tidylog writes to stderr by default
# logger can capture and route to file + console
log_appender(appender_tee("logs/tidylog_output.log"))
```

**Recommendation:** Defer until need is validated. Current tidylog → console output is sufficient.

---

## Anti-Patterns to Avoid

### 1. Don't Build Full roxygen2 Package Documentation

**AVOID:**
```r
# OVERKILL for standalone pipeline
roxygen2::roxygenise()  # Generates man/ directory, NAMESPACE file
devtools::document()    # Runs roxygenise + package checks
```

**PREFER:**
```r
# Use roxygen2 SYNTAX for comments (readable, self-documenting)
#' Check for HL diagnosis codes
#'
#' @param diagnosis_df Data frame with DX column
#' @return Logical vector
has_hl_diagnosis <- function(diagnosis_df) { ... }

# But DON'T run roxygen2 build process (this is not a package)
```

**Why:** This is a **pipeline project**, not an R package. No NAMESPACE, no man/ directory, no CRAN submission. roxygen2-style comments are fine for readability, but full package build is overkill.

### 2. Don't Overuse checkmate in Hot Loops

**AVOID:**
```r
# Validating inside map() is SLOW (repeated checks)
treatment_episodes <- prescriptions %>%
  group_by(ID) %>%
  summarize(
    episodes = map(PRESCRIBING_DATE, function(date) {
      assert_date(date)  # DON'T validate inside map()
      # ... processing
    })
  )
```

**PREFER:**
```r
# Validate ONCE before loop
assert_date(prescriptions$PRESCRIBING_DATE, any.missing = FALSE)

treatment_episodes <- prescriptions %>%
  group_by(ID) %>%
  summarize(
    episodes = map(PRESCRIBING_DATE, function(date) {
      # ... processing (validation already done)
    })
  )
```

**Why:** checkmate is fast (C implementation), but repeated validation adds unnecessary overhead. Validate at function entry or before loops, not inside iterations.

### 3. Don't Style Output Data Files

**AVOID:**
```r
# styler will corrupt CSV/Excel files if run on output/
styler::style_dir(".")  # DON'T style entire project root
```

**PREFER:**
```r
# Style only R code directories
styler::style_dir("R/")
styler::style_dir("tests/testthat/")

# Exclude output/ and renv/ in .stylerignore (if exists)
```

**Why:** styler is designed for R code, not data files. Running on CSVs/Excel/RDS will corrupt them.

### 4. Don't Create Unit Tests for Every Function (Prioritize Smoke Tests)

**AVOID (for v2.0):**
```r
# Testing every helper function is OVERKILL for research pipeline
test_that("str_remove_icd_dot removes periods from ICD codes", {
  expect_equal(str_remove_icd_dot("C81.00"), "C8100")
  expect_equal(str_remove_icd_dot("Z85.71"), "Z8571")
  # ... 50 more test cases
})
```

**PREFER (for v2.0):**
```r
# Smoke tests: Does the pipeline run end-to-end?
test_that("Cohort pipeline scripts run without error", {
  skip_if_not(file_exists("cache/enrollment.rds"))

  expect_no_error(source("R/01_config.R"))
  expect_no_error(source("R/02_data_loading.R"))
  expect_no_error(source("R/03_cohort_filtering.R"))
})

# Unit tests can be added incrementally in future milestones
```

**Why:** This is a **research pipeline**, not production software. Smoke tests ensure scripts run and produce outputs. Unit tests for helper functions are nice-to-have, but lower priority than pipeline integrity checks.

### 5. Don't Use fs::file_delete() Without Caution

**AVOID:**
```r
# DON'T delete files without confirmation
fs::file_delete(dir_ls("output/", glob = "*.csv"))  # DANGEROUS
```

**PREFER:**
```r
# Preview files first
files_to_delete <- dir_ls("output/", glob = "old_*.csv")
print(files_to_delete)

# Manual confirmation or interactive prompt
if (readline("Delete these files? (y/n): ") == "y") {
  file_delete(files_to_delete)
}
```

**Why:** fs::file_delete() is permanent (no trash/recycle bin). Always preview and confirm before bulk deletes.

---

## Version Verification (All Current as of 2026-06-01)

| Package | Minimum | Latest Stable | Publication Date | Status | Source |
|---------|---------|---------------|------------------|--------|--------|
| **lintr** | 3.3.0 | 3.3.0-1 | 2025-11-27 | Current | [CRAN](https://cran.r-project.org/package=lintr) |
| **styler** | 1.10.0 | 1.11.0 | 2025-10-13 | Current | [CRAN](https://cran.r-project.org/package=styler) |
| **checkmate** | 2.3.0 | 2.3.4 | 2026-02-03 | Current | [CRAN](https://cran.r-project.org/package=checkmate) |
| **testthat** | 3.3.0 | 3.3.2 | 2026-01-11 | Current | [CRAN](https://cran.r-project.org/package=testthat) |
| **fs** | 2.0.0 | 2.1.0 | 2026-04-18 | Current | [CRAN](https://cran.r-project.org/package=fs) |
| **logger** | 0.4.0 | 0.4.2 | 2026-05-10 | Current (OPTIONAL) | [CRAN](https://cran.r-project.org/package=logger) |

**All packages are current (published within 1-8 months of 2026-06-01). No deprecated versions.**

---

## Implementation Roadmap Suggestions

### Phase Sequencing

**Reorganization phases (file operations):**
1. **Phase REORG-01:** Inventory current scripts, define execution order, generate renaming plan (manual)
2. **Phase REORG-02:** Execute renaming with fs::file_move(), update source() calls

**Documentation phases (add comments):**
3. **Phase DOC-01:** Add section headers to all scripts (template: `# ===== SECTION NAME =====`)
4. **Phase DOC-02:** Add function-level comments for complex logic (roxygen2-style `#'`)
5. **Phase DOC-03:** Create reference manual (script order, purpose, parameters, outputs)

**Code quality phases (linting, validation, testing):**
6. **Phase SAFE-01:** Run styler on all R/ scripts (auto-format after renumbering)
7. **Phase SAFE-02:** Run lintr, fix style violations flagged by linters
8. **Phase SAFE-03:** Add checkmate assertions to critical functions (file loading, payer mapping)
9. **Phase SAFE-04:** Create smoke test suite with testthat (sequential numbering, source() calls, RDS dependencies)

**Consolidation phases (DRY):**
10. **Phase DRY-01:** Consolidate lookup tables to R/00_config.R (PREFIX_MAP, code mappings)
11. **Phase DRY-02:** Extract repeated patterns into shared utility functions

**Rationale:** Renumber FIRST (file operations), then document (add comments), then quality checks (lint/test), then consolidate (DRY). Each phase builds on previous.

### Testing Strategy

**After each phase:**
- **REORG-02:** Run smoke tests to verify all source() calls resolve
- **DOC-01/02:** Run lintr to check comment formatting
- **SAFE-01/02:** Visual review of styler changes (preview with dry = "on")
- **SAFE-03:** Run testthat suite to verify assertions don't break valid inputs
- **DRY-01:** Run smoke tests to verify config consolidation didn't break scripts

**Final integration test:** Run entire pipeline end-to-end on HiPerGator with DuckDB backend.

---

## What NOT to Add (Over-Engineering Warnings)

### Rejected: Full Package Structure (pkgdown, usethis)

**Considered:** Convert pipeline to full R package with pkgdown website, devtools workflow

**Why NOT:**
- **Overkill** — This is a **research pipeline**, not a package for distribution
- **CRAN constraints** — Package structure imposes constraints (no output/ directory, strict NAMESPACE, examples in every function)
- **Maintenance burden** — pkgdown website, NEWS.md, CRAN checks add overhead without benefit
- **Current structure works** — Standalone scripts with renv dependency management is sufficient

**What to use instead:** Keep current structure (R/ scripts + renv), add documentation via comments + reference manual.

### Rejected: Continuous Integration (GitHub Actions)

**Considered:** GitHub Actions to run lintr + testthat on every commit

**Why NOT:**
- **Data dependency** — Pipeline requires PCORnet CSVs on HiPerGator (not accessible from GitHub Actions)
- **HPC environment** — Tests need DuckDB, renv, HiPerGator module system (hard to replicate in CI)
- **Solo project** — CI benefits multi-developer teams with frequent merges; less critical for solo research

**When to reconsider:** If project becomes multi-developer or if smoke tests can run without data dependencies.

### Rejected: covr (Code Coverage)

**Considered:** Track test coverage percentage with covr package

**Why NOT:**
- **Smoke tests, not unit tests** — Coverage metrics are meaningful for unit tests, not end-to-end smoke tests
- **Research pipeline** — Coverage targets (80%+) are for production software; overkill for exploratory analysis

**What to use instead:** Focus on **critical path coverage** (do smoke tests verify all numbered scripts run?) rather than line-by-line coverage percentage.

### Rejected: profvis (Performance Profiling)

**Considered:** Profile code execution to find bottlenecks

**Why NOT:**
- **DuckDB already optimized** — Query performance is handled by DuckDB engine (Phase 29-32)
- **No performance complaints** — Pipeline completes in acceptable time on HiPerGator
- **Premature optimization** — v2.0 is about maintainability, not performance

**When to reconsider:** If specific scripts become slow enough to block development.

### Rejected: renv::snapshot() Automation

**Considered:** Automatically snapshot renv on every package install

**Why NOT:**
- **Manual control** — Explicit renv::snapshot() ensures intentional dependency changes
- **Reduces noise** — Prevents accidental snapshots during experimentation

**What to use instead:** Run renv::snapshot() manually after confirming new packages work correctly.

---

## Summary

**Focused stack additions for v2.0:**

| Tool | Purpose | Critical? | Adoption Phase |
|------|---------|-----------|----------------|
| **lintr** | Style checking | ✅ Required | SAFE-02 |
| **styler** | Auto-formatting | ✅ Required | SAFE-01 |
| **checkmate** | Input validation | ✅ Required | SAFE-03 |
| **testthat** | Smoke testing | ✅ Required | SAFE-04 |
| **fs** | File renaming | ✅ Required | REORG-02 |
| **logger** | Structured logging | ⚠️ Optional | Defer |

**Key principles:**
1. **Use base R where sufficient** — Section headers via `# =====`, function comments via `#'` (no roxygen2 build)
2. **Prioritize smoke tests over unit tests** — Verify pipeline runs, defer exhaustive function testing
3. **Integrate with existing stack** — checkmate extends testthat, fs complements here, lintr/styler work with tidyverse
4. **Don't over-engineer** — No package structure, no CI/CD, no coverage metrics (research pipeline, not production software)

**Risk assessment:** **LOW**
- All packages are mature (5-14 years old), CRAN-stable, widely adopted
- No bleeding-edge dependencies, no GitHub-only packages
- Integration points are well-documented (checkmate + testthat, fs + here)
- Tools are **additive** (don't change pipeline logic, only infrastructure)

**Next steps:**
1. Install 5 required packages (lintr, styler, checkmate, testthat, fs)
2. Run renv::snapshot() to lock versions
3. Start with REORG-01 (inventory scripts, plan renumbering)
4. Apply tools incrementally across 11 phases (REORG → DOC → SAFE → DRY)

---

## Sources

### Official Documentation
- [lintr documentation](https://lintr.r-lib.org/) — Full linter reference and configuration
- [styler documentation](https://styler.r-lib.org/) — Auto-formatting API and RStudio integration
- [checkmate documentation](https://mllg.github.io/checkmate/) — Input validation functions
- [testthat documentation](https://testthat.r-lib.org/) — Testing framework reference
- [fs documentation](https://fs.r-lib.org/) — Cross-platform file operations
- [logger documentation](https://daroczig.github.io/logger/) — Structured logging API

### CRAN Package Pages
- [CRAN lintr](https://cran.r-project.org/package=lintr) — v3.3.0-1 (Nov 2025)
- [CRAN styler](https://cran.r-project.org/package=styler) — v1.11.0 (Oct 2025)
- [CRAN checkmate](https://cran.r-project.org/package=checkmate) — v2.3.4 (Feb 2026)
- [CRAN testthat](https://cran.r-project.org/package=testthat) — v3.3.2 (Jan 2026)
- [CRAN fs](https://cran.r-project.org/package=fs) — v2.1.0 (Apr 2026)
- [CRAN logger](https://cran.r-project.org/package=logger) — v0.4.2 (May 2026)
- [CRAN roxygen2](https://cran.r-project.org/package=roxygen2) — v8.0.0 (May 2026)

### Tutorials & Guides
- [Tidyverse Style Guide](https://style.tidyverse.org/) — Conventions enforced by lintr/styler
- [R Packages (2e) Testing Basics](https://r-pkgs.org/testing-basics.html) — testthat usage patterns
- [Using lintr vignette](https://cran.r-project.org/web/packages/lintr/vignettes/lintr.html) — Configuration and customization
- [checkmate vignette](https://cran.r-project.org/web/packages/checkmate/vignettes/checkmate.html) — Defensive programming patterns
- [Introduction to logger](https://cran.r-project.org/web/packages/logger/vignettes/Intro.html) — Structured logging setup

### Academic Sources
- [R Journal: checkmate](https://journal.r-project.org/articles/RJ-2017-028/) — Peer-reviewed performance benchmarks and design rationale
- [arXiv: checkmate](https://arxiv.org/abs/1701.04781) — Fast argument checks for defensive R programming

### Community Resources
- [R for Data Science](https://r4ds.had.co.nz/) — Tidyverse workflow best practices
- [RStudio Community: lintr + styler](https://community.rstudio.com/) — User discussions and troubleshooting
- [GitHub: lintr](https://github.com/r-lib/lintr) — Custom linter examples and issue tracker
- [GitHub: styler](https://github.com/r-lib/styler) — Customization examples

---

## Confidence Assessment

| Area | Confidence | Rationale |
|------|------------|-----------|
| **lintr** | **HIGH** | Industry standard for R style checking (10+ years), tidyverse default, actively maintained |
| **styler** | **HIGH** | Mature auto-formatter (7+ years), RStudio integration, non-invasive (preview mode) |
| **checkmate** | **HIGH** | Peer-reviewed (R Journal), C-optimized, 100+ assertion functions, testthat integration |
| **testthat** | **HIGH** | Most popular R testing framework (14+ years), 10,000+ CRAN packages use it |
| **fs** | **HIGH** | Tidyverse ecosystem package, cross-platform, safer than base R file operations |
| **logger** | **MEDIUM** | Mature package, but OPTIONAL for v2.0 — current glue/cat/tidylog sufficient |
| **roxygen2 syntax** | **HIGH** | Standard comment format, use syntax without build process (not building package) |
| **Integration risk** | **LOW** | All tools are additive (don't change pipeline logic), widely compatible |

**Overall confidence:** **HIGH** — All required packages (5) are CRAN-stable, mature, and widely adopted in R ecosystem. Optional package (logger) is well-documented but deferred. No bleeding-edge or GitHub-only dependencies. Integration points are clear and well-tested by community.

**Source hierarchy followed:** CRAN official pages (versions) → Official documentation (usage) → Peer-reviewed articles (checkmate) → Community resources (examples). All version numbers verified against CRAN as of 2026-06-01.

**Gaps:** None identified. All capabilities (documentation, linting, validation, testing, file operations) have clear solutions with mature packages.
