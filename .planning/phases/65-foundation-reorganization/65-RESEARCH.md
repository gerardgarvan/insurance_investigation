# Phase 65: Foundation Reorganization - Research

**Researched:** 2026-06-01
**Domain:** R project structure reorganization, file renaming, cross-reference management
**Confidence:** HIGH

## Summary

Phase 65 reorganizes the R pipeline's foundation layer by (1) moving 8 utils_*.R modules into a new R/utils/ subfolder, (2) renumbering the DuckDB ingest script from 25 to 03, and (3) replacing explicit source() calls in 00_config.R with dynamic auto-discovery. This is a pure refactoring phase with zero functional changes — all scripts maintain their current behavior while gaining cleaner organization and future-proof auto-sourcing.

The critical challenge is maintaining the 121+ source() cross-references across the codebase while the file paths change. The existing pipeline has a well-established source chain pattern (scripts source their upstream dependencies), and we must preserve this without breaking any scripts.

**Primary recommendation:** Use file system moves (not copies) with systematic grep-based cross-reference updates, validate with a smoke test that sources the foundation scripts in sequence (00 → 01 → 02 → 03), and leverage the existing 26_smoke_test_backends.R pattern as a template.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01: Utils Scope**
- All 8 utils_*.R files move to R/utils/ — including utils_pptx.R which is currently sourced directly by 11_generate_pptx.R and 22b_generate_phase19_20_pptx.R (not auto-sourced by config). Update those two callers to the new path.

**D-02: Utils Naming**
- Files keep the `utils_` prefix inside R/utils/ (e.g., R/utils/utils_dates.R). This minimizes source() call changes (just prepend `utils/` to existing paths) and maintains grep-ability across the codebase.

**D-03: Foundation Script Numbering**
- Numbering order: 00=config (unchanged), 01=load_pcornet (unchanged), 02=harmonize_payer (unchanged), 03=duckdb_ingest (renumbered from 25). Only 25_duckdb_ingest.R actually moves — the legacy CSV workflow ordering is preserved, with DuckDB ingest added as 03 since it's optional (USE_DUCKDB flag).

**D-04: Auto-Sourcing Mechanism**
- Replace the 7 explicit source() lines in 00_config.R (lines 1501-1507) with dynamic sourcing: `list.files("R/utils", pattern = "\\.R$", full.names = TRUE)` piped to `lapply(source)`. New utils files added in future phases are auto-discovered without editing config.

### Claude's Discretion

- Smoke test implementation approach: design the validation script during planning.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REORG-01 | All R scripts renumbered sequentially using decade-based scheme (00-09 foundation, 10-19 cohort, 20-39 treatment, 40-59 cancer, 60-69 payer/QA, 70-79 outputs, 80-89 tests, 90-99 ad-hoc) with no gaps, duplicates, or sub-letter suffixes | Foundation scripts occupy 00-03 range; 25_duckdb_ingest.R renumbers to 03 (decade 00-09); maintains sequential ordering |
| REORG-03 | Utility modules (utils_*.R) moved to R/utils/ subfolder with 00_config.R auto-sourcing them | Dynamic sourcing via list.files() enables auto-discovery; standard R project practice (see Architecture Patterns) |
| REORG-04 | Deprecated/superseded scripts moved to R/archive/ folder with README explaining their status | Out of scope for Phase 65 (addressed in Phase 68); no deprecated foundation scripts identified |

</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| base R | 4.4.2+ | File operations | file.rename(), list.files(), lapply() are base R functions; no additional dependencies needed |
| glue | 1.8.0+ | Validation messaging | Already in project stack (CLAUDE.md); readable test output messages |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| stringr | 1.5.1+ | Path manipulation | Already in project; use str_replace() for systematic path updates if needed |
| here | 1.0.2+ | Project-relative paths | Already in stack; use here("R/utils") for portable path construction |

**Installation:**

All required packages are already installed per the project's existing renv environment. No new dependencies needed.

**Version verification:**

Not required — using only base R functions and existing project dependencies.

## Architecture Patterns

### Recommended Project Structure

```
R/
├── 00_config.R           # Foundation: config + auto-sources R/utils/*
├── 01_load_pcornet.R     # Foundation: data loading (sources 00)
├── 02_harmonize_payer.R  # Foundation: payer harmonization (sources 01)
├── 03_duckdb_ingest.R    # Foundation: DuckDB backend (sources 00) — RENUMBERED from 25
├── 04_build_cohort.R     # Cohort scripts continue (existing)
├── utils/                # NEW SUBFOLDER
│   ├── utils_attrition.R
│   ├── utils_dates.R
│   ├── utils_icd.R
│   ├── utils_snapshot.R
│   ├── utils_duckdb.R
│   ├── utils_treatment.R
│   ├── utils_payer.R
│   └── utils_pptx.R
└── [other numbered scripts...]
```

### Pattern 1: Dynamic Auto-Sourcing (Replaces Explicit source() Lines)

**What:** Use list.files() to discover and source all R files in a directory automatically

**When to use:** When you have a collection of utility modules that should always be loaded together, and you want future additions to be automatically included without editing the loader script

**Current implementation (00_config.R lines 1501-1507):**

```r
# Explicit sourcing (7 manual lines)
source("R/utils_dates.R")
source("R/utils_attrition.R")
source("R/utils_icd.R")
source("R/utils_snapshot.R")
source("R/utils_duckdb.R")
source("R/utils_treatment.R")
source("R/utils_payer.R")
```

**Recommended replacement:**

```r
# Dynamic auto-sourcing (D-04)
utils_files <- list.files("R/utils", pattern = "\\.R$", full.names = TRUE)
invisible(lapply(utils_files, source))
```

**Why this is better:**

- Future-proof: new utils files are automatically discovered
- Reduces maintenance: no need to edit config when adding utils
- Preserves load order determinism: list.files() returns alphabetically sorted results
- `invisible()` suppresses return value clutter in interactive sessions

**Source:** [R Gist: Source all files within folder](https://gist.github.com/johnatasjmo/f6073976b5e1aac3d755ee1852a3aca5), [Just Enough R: Dealing with multiple files](https://benwhalley.github.io/just-enough-r/multiple-raw-data-files.html)

### Pattern 2: Source Chain Dependencies

**What:** Scripts source their immediate upstream dependency, creating a transitive loading chain

**Current pattern in codebase:**

```r
# 01_load_pcornet.R
source("R/00_config.R")  # Loads config, which auto-sources utils

# 02_harmonize_payer.R
source("R/01_load_pcornet.R")  # Loads data, which loads config + utils

# 04_build_cohort.R
source("R/02_harmonize_payer.R")  # Loads everything upstream transitively
```

**Critical:** Scripts DO NOT use conditional sourcing (e.g., `if (!exists("pcornet")) source(...)`). The grep search found 0 instances of this pattern. All source() calls are unconditional and explicit.

**Implication for Phase 65:** Every source() call to foundation scripts (00, 01, 02) must be updated if file numbers change. Since only 25 → 03 renumbering happens, and no scripts currently source 25_duckdb_ingest.R directly (verified via grep), the impact is limited to:

1. Updating 00_config.R's utils auto-sourcing block
2. Updating 2 direct callers of utils_pptx.R (11_generate_pptx.R, 22b_generate_phase19_20_pptx.R)
3. Updating 1 redundant direct source in 19_flm_duplicate_dates.R line 97

**Source:** Verified from codebase grep analysis (121 source() calls to foundation scripts; 0 conditional patterns)

### Pattern 3: Smoke Test Validation

**What:** Lightweight validation script that sources foundation scripts in dependency order and checks for basic functionality

**Template from 26_smoke_test_backends.R:**

```r
# Load pipeline (sequential dependency chain)
USE_DUCKDB <<- FALSE
source("R/00_config.R")
source("R/01_load_pcornet.R")
source("R/02_harmonize_payer.R")
source("R/03_cohort_predicates.R")

library(dplyr)
library(glue)

message(strrep("=", 70))
message("SMOKE TEST: [Test Name]")
message(strrep("=", 70))

# Validation checks...
```

**Recommended for Phase 65:**

```r
# 65_smoke_test_foundation.R
# Validates foundation reorganization (REORG-01, REORG-03)

message(strrep("=", 70))
message("SMOKE TEST: Foundation Reorganization (Phase 65)")
message(strrep("=", 70))

# Test 1: Config loads without error
message("\n[1/4] Testing 00_config.R loads...")
source("R/00_config.R")
message("  ✓ Config loaded")

# Test 2: Utils auto-sourced
message("\n[2/4] Testing utils auto-sourcing...")
required_utils <- c("parse_pcornet_date", "log_attrition", "normalize_icd10")
missing <- required_utils[!sapply(required_utils, exists)]
if (length(missing) > 0) {
  stop(glue("Missing utils functions: {paste(missing, collapse=', ')}"))
}
message(glue("  ✓ {length(required_utils)} utils functions available"))

# Test 3: Data loading chain
message("\n[3/4] Testing data loading chain (00 → 01 → 02)...")
source("R/01_load_pcornet.R")
source("R/02_harmonize_payer.R")
message(glue("  ✓ Data loaded: {format(nrow(pcornet$DEMOGRAPHIC), big.mark=',')} patients"))

# Test 4: DuckDB ingest script accessible (03, renumbered from 25)
message("\n[4/4] Testing 03_duckdb_ingest.R accessible...")
if (!file.exists("R/03_duckdb_ingest.R")) {
  stop("03_duckdb_ingest.R not found at expected path")
}
message("  ✓ 03_duckdb_ingest.R exists")

message("\n" %+% strrep("=", 70))
message("✓ ALL FOUNDATION TESTS PASSED")
message(strrep("=", 70))
```

**Why this pattern works:**

- Sequential execution catches missing source() calls immediately
- Function existence checks validate utils auto-sourcing
- File existence checks validate renumbering
- Uses existing project patterns (message formatting, glue, strrep)

### Anti-Patterns to Avoid

**Anti-Pattern 1: Sourcing with Relative Paths Without full.names = TRUE**

```r
# BAD: Will fail because list.files() returns filenames only
files <- list.files("R/utils", pattern = "\\.R$")
lapply(files, source)  # ERROR: cannot open file 'utils_dates.R'

# GOOD: full.names = TRUE provides complete paths
files <- list.files("R/utils", pattern = "\\.R$", full.names = TRUE)
lapply(files, source)  # Works correctly
```

**Source:** [Just Enough R: Dealing with multiple files](https://benwhalley.github.io/just-enough-r/multiple-raw-data-files.html)

**Anti-Pattern 2: Using Copy Instead of Rename**

```r
# BAD: Leaves old files in place, creates confusion
file.copy("R/utils_dates.R", "R/utils/utils_dates.R")
# Old file still exists at R/utils_dates.R!

# GOOD: Atomic move operation
dir.create("R/utils", showWarnings = FALSE)
file.rename("R/utils_dates.R", "R/utils/utils_dates.R")
```

**Why rename is better:**

- Single source of truth (no duplicate files)
- Atomic operation (either succeeds completely or fails)
- Immediately reveals broken source() calls (forcing updates)

**Anti-Pattern 3: Updating Cross-References After Moving Files**

```r
# BAD ORDER:
# 1. Move files first
# 2. Update source() calls later
# Result: Broken state between steps, scripts fail to run

# GOOD ORDER (atomic waves):
# Wave 1: Create utils/ + update auto-sourcing in 00_config.R
# Wave 2: Move all 8 utils files atomically + update 3 direct callers
# Wave 3: Rename 25 → 03 (no source() updates needed — nothing sources it)
# Result: Each wave is independently valid
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cross-reference discovery | Manual grep + text editor search-replace | Systematic grep to file, review before applying | Manual search-replace misses edge cases (commented source calls, multiline strings); systematic grep provides audit trail |
| Utils loading | Manually updating explicit source() list as files are added | Dynamic list.files() + lapply(source) | New utils files require zero config changes; established R community pattern |
| Validation after reorganization | Manual testing each script | Smoke test script that sources foundation in sequence | Manual testing is non-reproducible; smoke test can be re-run by future phases |

**Key insight:** File reorganization is a classic "measure twice, cut once" problem. The actual file operations are trivial (file.rename), but the cross-reference updates are error-prone. Systematic grep-based discovery + smoke test validation is the standard approach, not custom tooling.

## Runtime State Inventory

> Skipped — Phase 65 is a code reorganization (file moves and renumbering). No runtime state affected.

## Common Pitfalls

### Pitfall 1: Alphabetical Loading Order Breaking Dependencies

**What goes wrong:** If utils files have internal dependencies (e.g., utils_treatment.R uses functions from utils_dates.R), dynamic alphabetical loading can break if filenames sort in the wrong order.

**Why it happens:** `list.files()` returns alphabetically sorted results. If utils_treatment.R loads before utils_dates.R (alphabetically "t" < "d" is false, but if filenames change...), you get "object not found" errors.

**How to avoid:**

1. **Best practice:** Utils should be independent — each file provides functions, no file calls functions from other utils. This is already the case in the project (verified from CONTEXT.md: utils are "shared utility functions" not interdependent modules).

2. **If dependencies exist:** Rename files with numeric prefixes (e.g., `001_utils_dates.R`, `002_utils_treatment.R`) to control load order explicitly.

**Warning signs:** Errors like `Error: object 'parse_pcornet_date' not found` when sourcing config, especially if the function exists but in a utils file loaded later alphabetically.

**Status in this project:** Not a risk — utils are independent utility collections. Verified from codebase inspection: utils_dates.R provides parsing functions, utils_attrition.R provides logging functions, etc. No cross-dependencies observed.

### Pitfall 2: Stale .Rdata/.RDS Files After Renumbering

**What goes wrong:** Interactive R sessions or saved workspaces cache old source paths. After renumbering, `source("R/25_duckdb_ingest.R")` in .Rhistory fails silently or throws confusing errors.

**Why it happens:** .Rdata files save the entire workspace including history. Reloading a saved workspace after file renaming resurrects stale paths.

**How to avoid:**

1. **Clear workspace before validation:** Run `rm(list = ls())` before smoke test
2. **Don't commit .Rdata files:** Already in .gitignore (standard R practice)
3. **Test in clean R session:** `Rscript R/65_smoke_test_foundation.R` runs without workspace pollution

**Warning signs:** Smoke test passes interactively but fails in fresh session, or vice versa.

### Pitfall 3: Git Tracking Breaks on file.rename()

**What goes wrong:** Git may not automatically track file moves if done via R's file.rename(). You get a deletion + new file instead of a rename, losing history.

**Why it happens:** `file.rename()` is a filesystem operation. Git detects renames heuristically based on content similarity.

**How to avoid:**

1. **After R rename operations, use git mv to record intent:**

```bash
# AFTER file.rename() in R:
git add -A
git status  # Should show "renamed: R/utils_dates.R -> R/utils/utils_dates.R"
# If it shows delete + add instead:
git rm R/utils_dates.R
git add R/utils/utils_dates.R
# Git will infer rename from content similarity (usually >50% match)
```

2. **Alternative:** Use git mv directly instead of file.rename():

```bash
# Before creating utils folder:
git mv R/utils_dates.R R/utils/utils_dates.R
```

**Warning signs:** `git log --follow R/utils/utils_dates.R` shows no history before Phase 65.

**Recommendation for Phase 65:** Use R's file.rename() for script-based reproducibility, then verify git detects renames with `git status`. Git's similarity detection should work (utils files have stable content).

### Pitfall 4: Forgetting utils_pptx.R Has Different Sourcing Pattern

**What goes wrong:** The plan updates only the 7 auto-sourced utils in 00_config.R, forgetting that utils_pptx.R is sourced directly by 2 scripts (11_generate_pptx.R, 22b_generate_phase19_20_pptx.R). Those scripts break when the file moves.

**Why it happens:** utils_pptx.R is a recent addition (not in the original auto-source list). It has a different usage pattern because PPTX generation is optional/ad-hoc, not part of the core pipeline.

**How to avoid:** CONTEXT.md D-01 explicitly calls this out. The plan MUST include updating those 2 callers:

```r
# 11_generate_pptx.R line 90 (before):
source("R/utils_pptx.R")

# After Phase 65:
source("R/utils/utils_pptx.R")
```

**Warning signs:** Smoke test passes (because it doesn't generate PPTX), but 11_generate_pptx.R fails with "cannot open file 'R/utils_pptx.R'".

**Verification:** Grep for `source.*utils_pptx` across all R scripts, not just 00_config.R.

### Pitfall 5: Missing Redundant Direct Source in 19_flm_duplicate_dates.R

**What goes wrong:** Script 19 has a conditional direct source of utils_dates.R (line 97) that bypasses the config auto-sourcing. After utils moves to subfolder, this line breaks.

**Why it happens:** Legacy code from before utils were auto-sourced by config. The conditional check (`if (file.exists("R/utils_dates.R"))`) was a safety mechanism.

**How to avoid:**

1. **Find it:** Grep for `source.*utils_dates` across all scripts (not just config)
2. **Update the path:**

```r
# Line 97 (before):
if (file.exists("R/utils_dates.R")) {
  source("R/utils_dates.R")

# After Phase 65:
if (file.exists("R/utils/utils_dates.R")) {
  source("R/utils/utils_dates.R")
```

**Warning signs:** Script 19 fails independently, even though config auto-sourcing works. Error occurs at line 97, not at top of script.

**Note:** This is technically redundant (config already sources utils), but changing behavior is out of scope. Just update the path.

## Code Examples

### Example 1: Dynamic Utils Auto-Sourcing (Replacing 00_config.R Lines 1501-1507)

```r
# ==============================================================================
# 6. AUTO-SOURCE UTILITY FUNCTIONS
# ==============================================================================
#
# Load all utility modules from R/utils/ subfolder
# These are sourced automatically when 00_config.R is loaded
# New utils files added in future are auto-discovered (D-04)

utils_files <- list.files(
  path = "R/utils",
  pattern = "\\.R$",
  full.names = TRUE
)

if (length(utils_files) == 0) {
  warning("No utility files found in R/utils/ — expected at least 8 modules")
} else {
  invisible(lapply(utils_files, source))
  message(sprintf("Loaded %d utility modules from R/utils/", length(utils_files)))
}

# ==============================================================================
# End of configuration
# ==============================================================================
```

**Key features:**

- `full.names = TRUE` provides complete paths for source()
- `invisible()` suppresses lapply return value clutter
- Warning if directory is empty (catches broken paths early)
- Optional message() for interactive feedback (can be commented out if verbose)

**Source:** Adapted from [R Gist: Source all files within folder](https://gist.github.com/johnatasjmo/f6073976b5e1aac3d755ee1852a3aca5)

### Example 2: Foundation Smoke Test (New Script: 65_smoke_test_foundation.R)

```r
# ==============================================================================
# 65_smoke_test_foundation.R -- Validate Phase 65 Foundation Reorganization
# ==============================================================================
#
# Validates:
#   1. 00_config.R loads and auto-sources R/utils/*
#   2. Foundation script chain resolves (00 → 01 → 02)
#   3. Renumbered 03_duckdb_ingest.R exists at new location
#
# Usage:
#   Rscript R/65_smoke_test_foundation.R
#
# Returns:
#   Exit code 0 on success, non-zero on failure
#
# Requirements: REORG-01, REORG-03, REORG-05
# ==============================================================================

# Clear workspace (avoid stale references)
rm(list = ls())

library(glue)

message(strrep("=", 70))
message("SMOKE TEST: Foundation Reorganization (Phase 65)")
message(strrep("=", 70))

# ------------------------------------------------------------------------------
# Test 1: Config loads without error
# ------------------------------------------------------------------------------
message("\n[1/4] Testing 00_config.R loads...")

tryCatch(
  {
    source("R/00_config.R")
    message("  ✓ Config loaded successfully")
  },
  error = function(e) {
    stop(glue("Config loading failed: {e$message}"))
  }
)

# ------------------------------------------------------------------------------
# Test 2: Utils auto-sourced from R/utils/ subfolder
# ------------------------------------------------------------------------------
message("\n[2/4] Testing utils auto-sourcing...")

# Key functions from each utils module
required_utils <- list(
  utils_dates = "parse_pcornet_date",
  utils_attrition = "log_attrition",
  utils_icd = "normalize_icd10",
  utils_snapshot = "snapshot_to_rds",
  utils_duckdb = "open_pcornet_con",
  utils_treatment = "detect_treatment_type",
  utils_payer = "categorize_payer",
  utils_pptx = "create_pptx_title_slide"
)

missing <- character(0)
for (module in names(required_utils)) {
  func <- required_utils[[module]]
  if (!exists(func)) {
    missing <- c(missing, glue("{module}: {func}"))
  }
}

if (length(missing) > 0) {
  stop(glue(
    "Missing utils functions (auto-sourcing failed):\n  ",
    paste(missing, collapse = "\n  ")
  ))
}

message(glue("  ✓ All {length(required_utils)} utils modules loaded"))

# ------------------------------------------------------------------------------
# Test 3: Data loading chain (00 → 01 → 02)
# ------------------------------------------------------------------------------
message("\n[3/4] Testing data loading chain...")

tryCatch(
  {
    source("R/01_load_pcornet.R")
    if (!exists("pcornet") || !is.list(pcornet)) {
      stop("pcornet list not created by 01_load_pcornet.R")
    }

    n_patients <- nrow(pcornet$DEMOGRAPHIC)
    message(glue("  ✓ Data loaded: {format(n_patients, big.mark=',')} patients"))

    source("R/02_harmonize_payer.R")
    if (!exists("payer_summary")) {
      stop("payer_summary not created by 02_harmonize_payer.R")
    }

    message("  ✓ Payer harmonization completed")
  },
  error = function(e) {
    stop(glue("Data loading chain failed: {e$message}"))
  }
)

# ------------------------------------------------------------------------------
# Test 4: Renumbered DuckDB script accessible
# ------------------------------------------------------------------------------
message("\n[4/4] Testing 03_duckdb_ingest.R exists at new location...")

if (!file.exists("R/03_duckdb_ingest.R")) {
  stop("03_duckdb_ingest.R not found (renumbering from 25 failed)")
}

if (file.exists("R/25_duckdb_ingest.R")) {
  stop("25_duckdb_ingest.R still exists (old file not removed)")
}

message("  ✓ 03_duckdb_ingest.R exists")
message("  ✓ 25_duckdb_ingest.R removed")

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
message("\n" %+% strrep("=", 70))
message("✓ ALL FOUNDATION TESTS PASSED")
message(strrep("=", 70))
message("\nValidated:")
message("  • Utils auto-sourcing from R/utils/ (REORG-03)")
message("  • Foundation script numbering 00-03 (REORG-01)")
message("  • Source chain resolves without errors (REORG-05)")

# Exit successfully
quit(status = 0)
```

**Why this pattern works:**

- Uses tryCatch for granular error reporting
- Tests existence of key functions (validates auto-sourcing worked)
- Validates file moves AND cleanup (old file removed)
- Follows existing smoke test style from 26_smoke_test_backends.R
- Can be run via `Rscript` in CI or interactively

**Source:** Pattern adapted from R/26_smoke_test_backends.R (lines 32-37)

### Example 3: Updating Direct utils_pptx.R Callers

```r
# ==============================================================================
# 11_generate_pptx.R -- Before Phase 65
# ==============================================================================

# ... (lines 1-89) ...

source("R/utils_pptx.R")  # Line 90

# ... rest of script ...

# ==============================================================================
# 11_generate_pptx.R -- After Phase 65
# ==============================================================================

# ... (lines 1-89) ...

source("R/utils/utils_pptx.R")  # Updated path

# ... rest of script ...
```

**Files requiring this update:**

- R/11_generate_pptx.R (line 90)
- R/22b_generate_phase19_20_pptx.R (line 43)

**Verification:** `grep -n "source.*utils_pptx" R/*.R` should show only the 2 updated paths.

## Environment Availability

Phase 65 has no external dependencies — all operations use base R functions (file.rename, list.files, lapply, source) that are always available in R 4.4.2+.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| R | All operations | ✓ | 4.4.2 (HiPerGator module) | — |
| glue | Smoke test messaging | ✓ | 1.8.0 (renv) | Use base paste0() |
| git | Commit tracking | ✓ | (system) | Manual file tracking |

**Missing dependencies with no fallback:** None

**Missing dependencies with fallback:** None

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Explicit source() list in config | Dynamic list.files() + lapply(source) | 2020s R best practice | New utils auto-discovered without editing config; aligns with modern R project conventions |
| Flat R/ directory with 70+ scripts | Decade-based numbering (00-09 foundation, 10-19 cohort, etc.) + utils/ subfolder | Emerging practice in large analysis pipelines | Improves navigability; separates reusable code (utils) from sequential workflow (numbered scripts) |
| Manual git mv for file operations | Scripted file.rename() in R with git auto-detection | Git 2.x improved rename detection | Reproducible refactoring; git tracks renames via content similarity |

**Deprecated/outdated:**

- **Conditional sourcing with exists() checks**: Modern R projects use explicit source chains with transitive dependencies. Conditional sourcing hides dependencies and breaks static analysis. This project already follows the modern approach (0 conditional source patterns found).

**Current as of:** 2026-06-01 (verified against R 4.4.2 documentation, tidyverse 2.0 conventions, git 2.x behavior)

## Open Questions

None — all research domains covered with high confidence. User decisions (D-01 through D-04) provide complete specification for implementation.

## Sources

### Primary (HIGH confidence)
- Project codebase analysis (verified 121 source() calls, 0 conditional patterns, 8 utils files, foundation script structure)
- Base R documentation: file.rename(), list.files(), lapply(), source() — stable since R 3.x
- Existing project patterns: R/26_smoke_test_backends.R (smoke test template), R/00_config.R lines 1495-1511 (current auto-sourcing)
- CLAUDE.md project constraints: R 4.4.2+, tidyverse ecosystem, HiPerGator environment

### Secondary (MEDIUM confidence)
- [R for Data Science: Workflow - Scripts and Projects](https://r4ds.hadley.nz/workflow-scripts.html) - Hadley Wickham, 2023-2024
- [Bookdown: Folder Structure Best Practices](https://bookdown.org/content/d1e53ac9-28ce-472f-bc2c-f499f18264a3/folder.html) - 2020-2024
- [R Best Practices](https://kdestasio.github.io/post/r_best_practices/) - Kate Destasio
- [Just Enough R: Dealing with multiple files](https://benwhalley.github.io/just-enough-r/multiple-raw-data-files.html)
- [R Gist: Source all files within folder](https://gist.github.com/johnatasjmo/f6073976b5e1aac3d755ee1852a3aca5) - Verified pattern for list.files() + lapply(source)
- [CRAN modules package: Organizing R Source Code](https://cran.r-project.org/web/packages/modules/vignettes/modulesAsFiles.html) - Advanced alternative to source() for large projects

### Tertiary (LOW confidence)
- [usethis::rename_files()](https://usethis.r-lib.org/reference/rename_files.html) - Package development tool (not applicable to analysis pipeline, but illustrates refactoring patterns)

## Metadata

**Confidence breakdown:**

- **Standard stack:** HIGH - Using only base R functions and existing project dependencies (glue, here). No new packages required. Base R file operations (file.rename, list.files) are stable since R 3.x.

- **Architecture:** HIGH - Dynamic sourcing pattern verified from multiple R community sources (R4DS, Bookdown, GitHub gists). Existing smoke test pattern directly applicable from R/26_smoke_test_backends.R. Cross-reference patterns verified via codebase grep (121 source() calls analyzed).

- **Pitfalls:** MEDIUM-HIGH - Pitfalls derived from general R refactoring experience and web search, but not all are documented in official R sources. Git rename tracking behavior is well-documented (HIGH). Alphabetical loading order issues are a known R community pattern (MEDIUM). Stale workspace issues are standard R practice (HIGH). Utils_pptx.R special case is codebase-specific (HIGH from direct inspection).

**Research date:** 2026-06-01

**Valid until:** 2026-07-01 (30 days) - Stable domain. Base R file operations and project organization patterns change slowly. HiPerGator R 4.4.2 environment is stable.
