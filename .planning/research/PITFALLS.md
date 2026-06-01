# Domain Pitfalls — v2.0 Codebase Cleanup & Documentation

**Domain:** R code reorganization, documentation, and quality tooling
**Researched:** 2026-06-01
**Confidence:** HIGH (synthesis of R community best practices + common refactoring mistakes)

---

## Critical Pitfalls

### Pitfall v2.0-1: Broken source() References After Renumbering

**What goes wrong:**
Renumber R/35_payer_frequency.R → R/47_payer_frequency.R but forget to update `source("R/35_payer_frequency.R")` calls in downstream scripts. Pipeline fails 20 minutes into execution with "cannot open file 'R/35_payer_frequency.R': No such file or directory."

**Why it happens:**
Search-and-replace misses comments, string literals in glue(), or source() calls with variable paths. Grepping for "35" finds too many false positives (dates, row counts, column indices). Developer updates obvious source() calls manually but misses edge cases.

**Consequences:**
- Pipeline breaks in middle of execution (wasted compute time)
- Error message cryptic if source() is inside conditional (only fails some runs)
- Git bisect difficult (renaming commit + reference update commit might be separate)

**Prevention:**
1. **Comprehensive grep before renaming:**
   ```r
   # Find all source() calls
   system('grep -rn "source\\\(" R/')

   # Find all old numbers in comments
   system('grep -rn "R/[0-9]\\{2\\}" R/')
   ```

2. **Update references BEFORE renaming files** (so broken paths fail immediately)

3. **Smoke test after renumbering:**
   ```r
   # tests/testthat/test_renumbering.R
   test_that("All source() calls reference existing files", {
     r_files <- dir_ls(here("R"), glob = "*.R")

     for (script in r_files) {
       content <- read_file(script)
       source_calls <- str_match_all(content, 'source\\("([^"]+)"\\)')[[1]][,2]

       for (sourced_file in source_calls) {
         expect_true(
           file_exists(here(sourced_file)),
           info = glue("{basename(script)} sources non-existent {sourced_file}")
         )
       }
     }
   })
   ```

4. **Create renaming manifest FIRST:**
   ```r
   renaming_plan <- tribble(
     ~old_number, ~new_number, ~script_purpose,
     0,  1,  "config.R",
     35, 47, "payer_code_frequency_av_th.R"
   )

   # Validate no duplicates
   stopifnot(!any(duplicated(renaming_plan$new_number)))
   ```

**Warning signs:**
- Renaming took 20 min but no test errors (didn't verify cross-references)
- Only tested first 3 scripts, assumed rest work (sequential dependencies hide failures)
- Git diff shows file renames but no source() updates

---

### Pitfall v2.0-2: Over-Aggressive lintr Violations Breaking Build

**What goes wrong:**
Run lintr with tidyverse defaults, get 500+ violations. Try to fix all at once. Accidentally change `PATID` → `patid` (lintr flags ALLCAPS). Now column references break: `df$PATID` no longer works because PCORnet uses ALLCAPS column names.

**Why it happens:**
lintr doesn't know about PCORnet CDM naming conventions (ALLCAPS table/column names). Default object_name_linter flags ALLCAPS as violation. Developer batch-renames without understanding that data frame columns ≠ R variables.

**Consequences:**
- 50+ scripts break with "object 'PATID' not found"
- Silently creates new column `patid` instead of using existing `PATID`
- dplyr joins fail (key column mismatch)

**Prevention:**
1. **Configure .lintr to disable object_name_linter:**
   ```
   linters: linters_with_defaults(
       object_name_linter = NULL,  # PCORnet uses ALLCAPS, not snake_case
       line_length_linter(120)      # Data pipelines need wider lines
     )
   exclusions: list("renv/", "output/", ".planning/")
   ```

2. **Fix violations incrementally:**
   - Run lintr, prioritize HIGH severity (commented code, T/F vs TRUE/FALSE)
   - Defer LOW severity (line length, spacing) to final polishing pass
   - Never batch-rename without manual review

3. **Test after each lintr fix:**
   ```r
   # After fixing violations in R/05_cohort_filter.R
   source(here("R", "05_cohort_filter.R"))
   # Verify outputs unchanged
   ```

4. **Use styler BEFORE lintr** (auto-fixes mechanical issues, reduces violations)

**Warning signs:**
- lintr reports 500+ violations (too many to fix at once)
- Batch find-replace on variable names (high risk)
- No incremental testing (fix → test → fix → test)

---

### Pitfall v2.0-3: checkmate Assertions Inside Hot Loops

**What goes wrong:**
Add `checkmate::assert_character(ID)` inside `map()` call. Pipeline that took 5 min now takes 45 min. Validation overhead 9x the actual work.

**Why it happens:**
Defensive programming enthusiasm. "Validate everything" applied literally. checkmate is fast (C implementation) but not zero-cost. Validating 100,000 rows × 5 columns = 500,000 function calls.

**Consequences:**
- Pipeline runtime increases 5-10x
- HiPerGator job times out (was 30 min, now 4 hours)
- No actual bugs caught (data already validated at load)

**Prevention:**
1. **Validate ONCE at entry, not inside iterations:**
   ```r
   # BAD: Validate inside map (100,000 calls)
   treatment_episodes <- prescriptions %>%
     group_by(ID) %>%
     summarize(
       episodes = map(PRESCRIBING_DATE, function(date) {
         assert_date(date)  # DON'T DO THIS
         # ... processing
       })
     )

   # GOOD: Validate once before loop
   assert_date(prescriptions$PRESCRIBING_DATE, any.missing = FALSE)

   treatment_episodes <- prescriptions %>%
     group_by(ID) %>%
     summarize(
       episodes = map(PRESCRIBING_DATE, function(date) {
         # ... processing (already validated)
       })
     )
   ```

2. **Validate at function entry, not every call:**
   ```r
   calculate_age <- function(birth_date, index_date) {
     # Validate ONCE per function call, not per vector element
     assert_date(birth_date, any.missing = FALSE)
     assert_date(index_date, any.missing = FALSE)

     floor(as.numeric(index_date - birth_date) / 365.25)
   }
   ```

3. **Use conditional validation for debugging:**
   ```r
   VALIDATE_INPUTS <- Sys.getenv("VALIDATE_INPUTS") == "TRUE"

   if (VALIDATE_INPUTS) {
     assert_data_frame(df, min.rows = 1000)
   }
   ```

**Warning signs:**
- Pipeline runtime increased 5x after adding assertions
- Profiling shows checkmate functions at top (not data operations)
- Assertions inside group_by/summarize/map

---

### Pitfall v2.0-4: styler Reformats Data Files

**What goes wrong:**
Run `styler::style_dir(".")` intending to format R/ scripts. styler also processes .Rmd files, data CSVs, and anything with R-like syntax. Corrupts output/gantt_episodes.csv by "fixing" spacing.

**Why it happens:**
`style_dir(".")` recurses into ALL subdirectories. CSV files with header rows look like R variable names to styler if file encoding is ambiguous.

**Consequences:**
- Output CSVs corrupted (commas removed, spacing changed)
- Gantt chart tool can't parse corrupted CSV
- Git diff shows 10,000+ lines changed in output/ (noise)

**Prevention:**
1. **Style ONLY R/ directory:**
   ```r
   styler::style_dir(here("R"))
   styler::style_dir(here("tests", "testthat"))
   ```

2. **Use .stylerignore (if available):**
   ```
   output/
   cache/
   renv/
   .planning/
   ```

3. **Preview before applying:**
   ```r
   # Dry run
   styler::style_dir(here("R"), dry = "on")
   # Review proposed changes, then apply
   styler::style_dir(here("R"))
   ```

**Warning signs:**
- styler processing 1000+ files (should be ~80 R scripts)
- Git diff shows changes in output/ or cache/
- CSV files show spacing changes

---

### Pitfall v2.0-5: Smoke Tests with Hardcoded Paths

**What goes wrong:**
Write smoke test: `expect_true(file.exists("C:/Users/Owner/insurance_investigation/cache/cohort.rds"))`. Works on local machine. Fails on HiPerGator: "No such file or directory."

**Why it happens:**
Hardcoded absolute paths. Windows path separator backslashes vs Linux forward slashes. Test written on one machine, run on another.

**Consequences:**
- Tests pass locally, fail in CI or HiPerGator
- False confidence (tests green but wrong)
- Manual path editing needed for every environment

**Prevention:**
1. **Use here() for project-relative paths:**
   ```r
   # BAD: Absolute path
   expect_true(file.exists("C:/Users/Owner/insurance_investigation/cache/cohort.rds"))

   # GOOD: Project-relative with here()
   expect_true(file_exists(here("cache", "cohort.rds")))
   ```

2. **Use fs::file_exists() (not base R):**
   ```r
   library(fs)
   library(here)

   expect_true(file_exists(here("cache", "cohort.rds")))
   ```

3. **Test on both platforms before committing:**
   - Local Windows: RStudio
   - HiPerGator: `sbatch smoke_test.sh`

**Warning signs:**
- Paths with `C:/` or `D:/` (Windows-specific)
- Backslashes in paths (`"cache\\cohort.rds"`)
- Tests pass in RStudio, fail in SLURM jobs

---

### Pitfall v2.0-6: Duplicate Constants Diverge After Consolidation

**What goes wrong:**
Consolidate PREFIX_MAP to R/00_config.R. Update 2 of 3 scripts to use centralized version. Third script still has old copy. Now same patient has different payer categories depending on which script runs first.

**Why it happens:**
Incomplete consolidation. Grep found 2 copies, missed third (inside function definition or conditional). Legacy code path still uses old lookup.

**Consequences:**
- Results vary by execution path (non-deterministic)
- Payer categories don't match between reports
- Debugging difficult (same code, different config)

**Prevention:**
1. **Grep exhaustively BEFORE consolidation:**
   ```r
   # Find ALL instances of constant
   system('grep -rn "PREFIX_MAP" R/')

   # Find definitions (assignments)
   system('grep -rn "PREFIX_MAP <-\\|PREFIX_MAP =" R/')
   ```

2. **Remove old copies in SAME commit as consolidation:**
   ```r
   # In consolidation commit:
   # 1. Add to R/00_config.R
   # 2. Delete from R/35, R/44a, R/52 (all instances)
   # 3. Update all references to source config
   ```

3. **Validate with smoke test:**
   ```r
   test_that("PREFIX_MAP defined only in config", {
     r_files <- setdiff(
       dir_ls(here("R"), glob = "*.R"),
       here("R", "00_config.R")
     )

     for (script in r_files) {
       content <- read_file(script)
       expect_false(
         str_detect(content, "PREFIX_MAP <-|PREFIX_MAP ="),
         info = glue("{basename(script)} redefines PREFIX_MAP")
       )
     }
   })
   ```

**Warning signs:**
- Consolidation commit only modifies R/00_config.R (didn't delete old copies)
- Grep shows multiple definitions after consolidation
- Results change when scripts run in different order

---

## Moderate Pitfalls

### Pitfall v2.0-7: Renumbering Without Execution Order Analysis

**What goes wrong:**
Renumber alphabetically (01_config, 02_data_load, ...) without considering dependencies. R/05_filter_cohort.R runs before R/03_load_cohort.R (alphabet order). Breaks because cohort.rds doesn't exist yet.

**Prevention:**
- Manually map execution order FIRST (dependency graph)
- Number by logical flow, not alphabetical
- Use gaps (01, 05, 10, 15) to allow insertions

### Pitfall v2.0-8: Section Headers Break RStudio Outline

**What goes wrong:**
Add section headers: `# Section Name` (no trailing dashes). RStudio outline doesn't show them. Navigation still broken.

**Prevention:**
Use RStudio format: `# Section Name ----` (4+ trailing dashes)

### Pitfall v2.0-9: roxygen2 Package Build for Non-Package

**What goes wrong:**
Add roxygen2 comments `#' @param`, then run `devtools::document()`. Creates man/ directory, NAMESPACE file. Git complains about untracked files. Package structure unnecessary for scripts.

**Prevention:**
- Use roxygen2 SYNTAX (`#'`) for readability
- DON'T run `roxygen2::roxygenise()` or `devtools::document()`
- This is a pipeline, not a package

### Pitfall v2.0-10: Over-Commenting Trivial Code

**What goes wrong:**
Add comments to every line: `# Load libraries`, `# Create vector`, `# Sum values`. 500-line script becomes 1000 lines, harder to read.

**Prevention:**
- Comment WHY, not WHAT
- Section headers + function-level roxygen2 comments sufficient
- Only explain non-obvious clinical/statistical logic

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Broken source() calls | LOW | Grep for old numbers, update references, run smoke test |
| lintr renamed ALLCAPS columns | MEDIUM | Revert changes, configure .lintr to exclude object_name_linter, re-run lintr |
| checkmate in hot loops | LOW | Move assertions outside loop, re-run with timing |
| styler corrupted CSVs | LOW | Revert output/ changes, re-run styler on R/ only |
| Hardcoded paths in tests | LOW | Replace with here(), verify on both platforms |
| Duplicate constants diverged | MEDIUM | Grep for all copies, delete old ones, validate with smoke test |

---

## Anti-Patterns Summary

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Renumber without updating references | Fast file operation | Broken pipeline in production | Never — always update references |
| Accept all lintr defaults | Quick setup | False positives on PCORnet ALLCAPS | Never — configure .lintr first |
| Validate inside loops | Feels thorough | 10x slowdown | Never — validate once at entry |
| style_dir(".") on project root | One command | Corrupts data files | Never — style R/ only |
| Hardcode absolute paths | Works locally | Fails on HiPerGator | Never — use here() |
| Partial constant consolidation | Quick partial fix | Non-deterministic results | Never — all or nothing |

---

## Sources

- [R Packages: Testing](https://r-pkgs.org/testing-basics.html) — testthat best practices
- [lintr documentation](https://lintr.r-lib.org/) — Configuration and false positives
- [styler documentation](https://styler.r-lib.org/) — Scope control
- [checkmate vignette](https://mllg.github.io/checkmate/) — Performance considerations
- [here package](https://here.r-lib.org/) — Project-relative paths

**Confidence:** **HIGH** — All pitfalls documented from common R refactoring mistakes and tool documentation.
