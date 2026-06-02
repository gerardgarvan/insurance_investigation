# Phase 74: Smoke Testing & Reference Manual - Research

**Researched:** 2026-06-02
**Domain:** R testing infrastructure, dependency analysis, cross-platform validation
**Confidence:** HIGH

## Summary

Phase 74 delivers two critical maintainability artifacts: (1) a comprehensive standalone smoke test that validates pipeline structural integrity (sequential numbering, source() resolution, RDS dependency chains, config constants, utility modules, DRY consolidation), and (2) an auto-generated reference manual with full dependency matrix and onboarding instructions.

The research confirms that the existing manual `check()` pattern from R/86 and R/87 is the correct approach for this project — avoiding testthat's package scaffolding overhead while maintaining SLURM-compatible exit codes. The pipeline's structured 5-field headers (added in Phase 69) provide machine-parseable input for automated reference manual generation. Cross-platform testing is achievable through runtime auto-detection of data availability, allowing structural checks to pass on Windows while full validation runs on HiPerGator.

**Primary recommendation:** Consolidate or extend R/86 + R/87 into a comprehensive smoke test covering all structural invariants (no broken source() calls, no duplicate constants, utils completeness, DRY compliance), use regex parsing to extract structured headers for dependency matrix generation, and gate data-dependent checks behind `dir.exists(CONFIG$data_dir)` auto-detection for cross-platform compatibility.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Enhanced standalone test scripts using the existing manual `check()` pattern from R/86 and R/87. No testthat framework, no DESCRIPTION file, no package scaffolding. Works directly with `Rscript` on both platforms.
- **D-02:** R/80 (backend parity test) is left as a separate data-dependent test, outside the scope of the structural smoke test suite.
- **D-04:** Structure-only testing — verify file existence, sequential numbering, source() resolution, RDS dependency chains, config constants. No script execution that requires data.
- **D-06:** Auto-detect platform using `.Platform$OS.type` or `Sys.info()`. Check if `CONFIG$data_dir` exists to determine data availability. No explicit flags needed.
- **D-07:** Data-dependent checks gated behind `DATA_AVAILABLE` flag set by auto-detection. Structural checks run on both Windows and HiPerGator. Tests pass on Windows with fewer checks (structural only).
- **D-08:** Reference manual lives at `docs/REFERENCE_MANUAL.md`, alongside existing docs (DUCKDB_MIGRATION_GUIDE.md, DUCKDB_TRANSLATION_NOTES.md).
- **D-09:** Full dependency matrix — every script gets a row: Script | Purpose | source() Dependencies | RDS Inputs | RDS/CSV Outputs | Config Constants Used. Covers all 67 numbered scripts + 10 utils.
- **D-10:** Includes full onboarding section: HiPerGator setup, renv restore, module loading, run-order walkthrough, output file locations. Targeted at new team members.
- **D-11:** Auto-generated from script headers. Phase 69 added structured 5-field header blocks (Purpose, Inputs, Outputs, Dependencies, Requirements) to all scripts. A utility script or inline R code parses these headers to build the dependency matrix automatically.

### Claude's Discretion
- Internal structure of the comprehensive smoke test (check grouping, output format, exit codes)
- Which R/86/R/87 checks to consolidate vs keep separate
- Exact set of additional structural checks beyond existing coverage
- Reference manual generator implementation (standalone script vs inline in smoke test vs separate utility)
- Prose sections of reference manual (architecture overview, config documentation, error message patterns)
- Wave/plan decomposition strategy

### Deferred Ideas (OUT OF SCOPE)
- None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REORG-05 | Smoke test validates no broken cross-references after each renumbering phase (RDS artifacts unchanged, source() calls resolve) | Existing R/86 and R/87 demonstrate file existence and source() parsing patterns; extend with RDS dependency chain validation |
| SAFE-06 | Comprehensive smoke test suite (testthat) verifying pipeline integrity — sequential numbering, source() resolution, RDS dependency checks, critical script execution without error | Manual check() pattern is superior to testthat for standalone scripts; consolidate/extend R/86 + R/87 with DRY compliance checks, config constant validation, utils completeness |
| DOC-04 | Full reference manual created with dependency matrix (Script -> Inputs/Outputs/Dependencies table for all scripts) and run-order guide | Script headers (Phase 69) are regex-parseable; extract Purpose/Inputs/Outputs/Dependencies fields to generate dependency matrix automatically |
</phase_requirements>

## Standard Stack

### Core Testing Infrastructure
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| base R | 4.4.2+ | check() function pattern | Manual check(description, condition) pattern from R/86/R/87 is lightweight, SLURM-compatible, requires no package scaffolding |
| glue | 1.8.0+ | Error messages | Already project standard; readable interpolation for pass/fail output |

### Supporting Libraries
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| stringr | 1.5.1+ | Regex parsing | Extract source() calls, parse header fields for reference manual generation |
| dplyr | 1.2.0+ | Data wrangling | Build dependency matrix tables from parsed header metadata |
| fs | 1.6.5+ (optional) | Cross-platform paths | Optional enhancement for path handling; base R file.exists() sufficient for current needs |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Manual check() pattern | testthat | testthat is designed for package testing; requires DESCRIPTION file and tests/testthat/ structure. Adds overhead for standalone scripts. Community consensus: testthat poorly suited for non-package projects. Manual pattern is simpler and works with `Rscript` directly. |
| Regex parsing headers | Static analysis packages (renv::dependencies, depcheck) | renv::dependencies() finds library() calls and package::function references, but does NOT parse script headers or RDS inputs/outputs. Custom regex parsing needed for full dependency matrix. |
| Base R path handling | fs package | fs provides cross-platform normalization and vectorized operations, but adds dependency. Base R file.exists(), dir.exists(), file.path() work reliably on Windows + Linux when paths use forward slashes or normalizePath(). |

**Installation:**
```bash
# All dependencies already installed (project uses tidyverse)
# No additional packages needed
```

## Architecture Patterns

### Recommended Test Structure
```
R/
├── 86_smoke_test_foundation.R     # Existing foundation checks (utils/, 00-03 chain)
├── 87_smoke_test_full_pipeline.R  # Existing reorganization checks (decades, source() refs)
└── 88_smoke_test_comprehensive.R  # NEW: Consolidates + extends R/86 + R/87
    OR: Merge checks into single enhanced R/87 (fewer files to maintain)

docs/
└── REFERENCE_MANUAL.md             # Auto-generated dependency matrix + onboarding
```

### Pattern 1: Manual check() Pattern (from R/86)
**What:** Lightweight pass/fail validation without testthat framework
**When to use:** Standalone smoke tests for script pipelines, SLURM job validation
**Example:**
```r
# Source: R/86_smoke_test_foundation.R (existing code)
library(glue)

passed <- 0L
failed <- 0L

check <- function(description, condition) {
  if (condition) {
    message(glue("  PASS: {description}"))
    passed <<- passed + 1L
  } else {
    message(glue("  FAIL: {description}"))
    failed <<- failed + 1L
  }
}

# Use pattern:
check("R/00_config.R exists", file.exists("R/00_config.R"))
check(
  glue("R/utils/ contains 10 files (found {length(utils_files)})"),
  length(utils_files) == 10
)

# Exit with non-zero status for SLURM compatibility
if (failed > 0) {
  quit(status = 1)
}
```

### Pattern 2: Source Call Extraction (from R/87)
**What:** Parse R scripts to extract source("R/XX_name.R") references
**When to use:** Validate that all source() calls resolve to existing files
**Example:**
```r
# Source: R/87_smoke_test_full_pipeline.R (existing code)
r_files_full <- list.files("R", pattern = "\\.R$", full.names = TRUE)
broken_refs <- character(0)

for (f in r_files_full) {
  lines <- readLines(f, warn = FALSE)
  # Extract source("R/...") patterns (ignore commented lines)
  source_lines <- grep('^[^#]*source\\("R/', lines, value = TRUE)

  for (line in source_lines) {
    matches <- regmatches(line, gregexpr('source\\("R/[^"]+\\.R"\\)', line))
    for (match_list in matches) {
      for (m in match_list) {
        path <- sub('source\\("', "", m)
        path <- sub('"\\)', "", path)
        if (!file.exists(path)) {
          broken_refs <- c(broken_refs, glue("{basename(f)}: {path}"))
        }
      }
    }
  }
}

check(
  glue("No broken source() calls (found: {paste(broken_refs, collapse=', ') %||% 'none'})"),
  length(broken_refs) == 0
)
```

### Pattern 3: Cross-Platform Data Availability Detection
**What:** Auto-detect whether HiPerGator data paths exist for gating data-dependent checks
**When to use:** Tests that must pass on Windows (local development) and HiPerGator (production)
**Example:**
```r
# Auto-detect data availability (no manual flags)
source("R/00_config.R")  # Loads CONFIG$data_dir

DATA_AVAILABLE <- dir.exists(CONFIG$data_dir)
PLATFORM <- .Platform$OS.type  # "windows" or "unix"

message(glue("Platform: {PLATFORM}"))
message(glue("Data available: {DATA_AVAILABLE}"))

# Structural checks (run on both platforms)
check("R/00_config.R exists", file.exists("R/00_config.R"))
check("No broken source() references", length(broken_refs) == 0)

# Data-dependent checks (HiPerGator only)
if (DATA_AVAILABLE) {
  message("\n[Data-dependent checks]")
  check("ENROLLMENT.csv readable", file.exists(file.path(CONFIG$data_dir, "ENROLLMENT.csv")))
  check("RDS cache directory exists", dir.exists(CONFIG$cache$raw_dir))
} else {
  message("\n[Skipping data-dependent checks - data not available on this platform]")
}
```

### Pattern 4: Header Parsing for Reference Manual Generation
**What:** Extract structured 5-field headers (Purpose, Inputs, Outputs, Dependencies, Requirements) from all scripts
**When to use:** Auto-generate dependency matrix documentation
**Example:**
```r
# Parse all R scripts for structured headers
library(stringr)
library(dplyr)

parse_script_header <- function(filepath) {
  lines <- readLines(filepath, warn = FALSE)

  # Extract 5-field header block (lines starting with "# Purpose:", etc.)
  purpose_match <- str_match(lines, "^# Purpose:\\s*(.*)$")
  purpose <- purpose_match[!is.na(purpose_match[,2]), 2][1]  # First match

  inputs_match <- str_match(lines, "^# Inputs:\\s*(.*)$")
  inputs <- inputs_match[!is.na(inputs_match[,2]), 2][1]

  outputs_match <- str_match(lines, "^# Outputs:\\s*(.*)$")
  outputs <- outputs_match[!is.na(outputs_match[,2]), 2][1]

  deps_match <- str_match(lines, "^# Dependencies:\\s*(.*)$")
  dependencies <- deps_match[!is.na(deps_match[,2]), 2][1]

  reqs_match <- str_match(lines, "^# Requirements:\\s*(.*)$")
  requirements <- reqs_match[!is.na(reqs_match[,2]), 2][1]

  tibble(
    script = basename(filepath),
    purpose = purpose %||% "Not documented",
    inputs = inputs %||% "Not documented",
    outputs = outputs %||% "Not documented",
    dependencies = dependencies %||% "Not documented",
    requirements = requirements %||% "Not documented"
  )
}

# Parse all numbered scripts
r_scripts <- list.files("R", pattern = "^[0-9]+.*\\.R$", full.names = TRUE)
dependency_matrix <- map_df(r_scripts, parse_script_header)

# Output as markdown table
cat("| Script | Purpose | Dependencies | Inputs | Outputs |\n")
cat("|--------|---------|--------------|--------|----------|\n")
for (i in 1:nrow(dependency_matrix)) {
  cat(glue("| {dependency_matrix$script[i]} | {dependency_matrix$purpose[i]} | {dependency_matrix$dependencies[i]} | {dependency_matrix$inputs[i]} | {dependency_matrix$outputs[i]} |\n"))
}
```

### Anti-Patterns to Avoid

- **Don't use testthat for standalone scripts:** testthat is designed for package development. It expects DESCRIPTION file, tests/testthat/ directory structure, and devtools::load_all() workflow. For standalone R scripts, the manual check() pattern is simpler and more maintainable.
- **Don't hardcode Windows paths:** Use forward slashes or normalizePath() for cross-platform compatibility. `file.path()` handles platform differences automatically.
- **Don't assume data availability:** Gate data-dependent checks behind `dir.exists(CONFIG$data_dir)` so tests pass on local Windows machines without HiPerGator mount.
- **Don't manually write dependency matrices:** Phase 69 added structured headers to all scripts. Parse these programmatically instead of maintaining a manual table that will drift out of sync.
- **Don't install packages inside smoke tests:** Tests should assume the environment is already configured (renv::restore() completed). Check for library availability with `requireNamespace("package", quietly = TRUE)`, but don't call `install.packages()`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| R package dependency analysis | Custom AST parser | renv::dependencies() | renv uses static analysis to find library(), require(), package::function() calls. Well-tested across CRAN packages. |
| Cross-platform path handling | String manipulation | file.path(), normalizePath() | Base R functions handle Windows backslashes vs Linux forward slashes. fs package is overkill for this project's needs. |
| Test framework from scratch | Custom test harness | Manual check() pattern (already in R/86) | Existing pattern is 50 lines, works with Rscript, SLURM-compatible, no dependencies. testthat adds complexity without value for this use case. |
| Markdown table generation | String concatenation | glue() or knitr::kable() | glue() for simple cases; knitr::kable() for complex formatting. Both handle escaping and alignment. |

**Key insight:** R testing ecosystem is package-centric. For standalone script pipelines, lightweight manual patterns (check(), readLines() + regex, file.exists()) are more maintainable than forcing package tooling onto non-package structures.

## Runtime State Inventory

Phase 74 is a documentation and testing phase — no rename/refactor/migration work. This section is omitted.

## Common Pitfalls

### Pitfall 1: testthat in Non-Package Projects
**What goes wrong:** Attempting to use testthat for standalone R scripts leads to DESCRIPTION file creation, tests/testthat/ scaffolding, and package development overhead. Tests fail with cryptic errors about missing packages or context.
**Why it happens:** testthat is designed for package development workflow (devtools::load_all(), usethis::use_testthat()). Documentation assumes package structure.
**How to avoid:** Use manual check() pattern from R/86/R/87. One function, works with Rscript, SLURM-compatible exit codes, no scaffolding.
**Warning signs:** Creating DESCRIPTION file for a script pipeline, seeing "Error: Could not find package root" from testthat, needing devtools::load_all() to run tests.

### Pitfall 2: Case-Sensitive File Paths
**What goes wrong:** Tests pass on Windows (case-insensitive) but fail on Linux (case-sensitive). `source("R/Utils/utils_payer.R")` works locally but fails on HiPerGator if actual directory is `R/utils/`.
**Why it happens:** Windows file system ignores case; Linux does not. `File.txt` and `file.txt` are the same on Windows, different on Linux.
**How to avoid:** Verify exact case matches using `list.files()` and case-sensitive regex patterns. Test on HiPerGator before finalizing.
**Warning signs:** Tests pass on Windows but fail in SLURM jobs with "cannot open file 'R/Utils/...': No such file or directory."

### Pitfall 3: Hardcoded Absolute Paths
**What goes wrong:** Tests hardcode `/blue/erin.mobley-hl.bcu/...` paths that exist on HiPerGator but fail on Windows. Cross-platform testing becomes impossible.
**Why it happens:** CONFIG$data_dir is HiPerGator-specific. Tests that assume data exists fail on local machines.
**How to avoid:** Gate data-dependent checks behind `dir.exists(CONFIG$data_dir)`. Structural checks (file existence, source() resolution) work on both platforms. Data checks run only where data is available.
**Warning signs:** All tests fail on Windows with "directory does not exist" errors, even though script structure is valid.

### Pitfall 4: Parsing Multi-Line Header Fields
**What goes wrong:** Header fields span multiple lines (e.g., "# Inputs:\n#   - ENROLLMENT.csv\n#   - DIAGNOSIS.csv"). Simple regex extracts only first line, losing detail.
**Why it happens:** Phase 69 headers use continuation lines (comment prefix + indentation) for readability.
**How to avoid:** Parse header blocks by finding field start (e.g., "# Inputs:") and collecting subsequent comment lines until next field or section boundary. Alternatively, extract only first line for summary and link to source file for full detail.
**Warning signs:** Dependency matrix shows truncated inputs like "- ENROLLMENT.csv" instead of full list.

### Pitfall 5: Stale smoke Test Decade Counts
**What goes wrong:** Smoke test expects 8 utils files (from Phase 65), but utils_assertions.R (Phase 72) and utils_cancer.R (Phase 73) were added. Test fails with "expected 8, found 10."
**Why it happens:** Tests hardcode expected counts that become outdated as the codebase evolves.
**How to avoid:** Either (1) update expected counts each phase, or (2) validate structure (all files match pattern) without hardcoding totals. Prefer structural checks: "no utils_*.R files in R/ root" over "exactly 10 utils in R/utils/."
**Warning signs:** Test failures after phases that added utils modules, even though structure is valid.

## Code Examples

Verified patterns from existing codebase:

### Check for No Duplicate Constants (DRY Validation)
```r
# Validate Phase 73 DRY consolidation: PREFIX_MAP, TIER_MAPPING moved to config
message("\n[DRY Consolidation Validation]")

# These constants should ONLY exist in R/00_config.R
cancer_scripts <- c(
  "R/28_episode_classification.R", "R/40_cancer_site_frequency.R",
  "R/43_cancer_site_confirmation.R", "R/44_cancer_site_confirmation_7day.R",
  "R/45_cancer_summary.R", "R/46_cancer_summary_table.R",
  "R/47_cancer_summary_refined.R", "R/48_cancer_summary_post_hl.R",
  "R/49_cancer_summary_pre_post.R", "R/51_gantt_data_export.R",
  "R/52_gantt_v2_export.R"
)

duplicate_prefix_map <- character(0)
for (script in cancer_scripts) {
  if (!file.exists(script)) next
  lines <- readLines(script, warn = FALSE)
  # Look for PREFIX_MAP definition (not CANCER_SITE_MAP reference)
  if (any(grepl("^PREFIX_MAP\\s*<-", lines))) {
    duplicate_prefix_map <- c(duplicate_prefix_map, basename(script))
  }
}

check(
  glue("No duplicate PREFIX_MAP definitions (found in: {paste(duplicate_prefix_map, collapse=', ') %||% 'none'})"),
  length(duplicate_prefix_map) == 0
)

# Validate TIER_MAPPING consolidated
payer_scripts <- c("R/60_tiered_same_day_payer.R", "R/61_tiered_encounter_level.R", "R/62_tiered_date_level.R")
duplicate_tier_mapping <- character(0)
for (script in payer_scripts) {
  if (!file.exists(script)) next
  lines <- readLines(script, warn = FALSE)
  if (any(grepl("^TIER_MAPPING\\s*<-", lines))) {
    duplicate_tier_mapping <- c(duplicate_tier_mapping, basename(script))
  }
}

check(
  glue("No duplicate TIER_MAPPING definitions (found in: {paste(duplicate_tier_mapping, collapse=', ') %||% 'none'})"),
  length(duplicate_tier_mapping) == 0
)
```

### RDS Dependency Chain Validation
```r
# Validate RDS dependency chains: ensure upstream outputs exist before downstream scripts load them
message("\n[RDS Dependency Chains]")

# Example: R/26_treatment_episodes.R depends on R/25_treatment_durations.R output
source("R/00_config.R")  # Loads CONFIG paths

check(
  "R/25_treatment_durations.R creates treatment_durations.rds",
  file.exists(file.path(CONFIG$cache$cohort_dir, "treatment_durations.rds"))
)

check(
  "R/26_treatment_episodes.R depends on treatment_durations.rds",
  file.exists("R/26_treatment_episodes.R") &&
  any(grepl("treatment_durations.rds", readLines("R/26_treatment_episodes.R", warn = FALSE)))
)

# Validate cohort chain: 14_build_cohort.R -> outputs/hl_cohort.rds -> 70/71 visualizations
check(
  "14_build_cohort.R creates hl_cohort.rds",
  file.exists(file.path(CONFIG$cache$outputs_dir, "hl_cohort.rds")) ||
  file.exists("output/hl_cohort.rds")
)

check(
  "70_visualize_waterfall.R depends on hl_cohort.rds",
  file.exists("R/70_visualize_waterfall.R") &&
  any(grepl("hl_cohort.rds", readLines("R/70_visualize_waterfall.R", warn = FALSE)))
)
```

### Utils Module Completeness Check
```r
# Validate all 10 utils modules are present and auto-sourced
message("\n[Utils Module Completeness]")

expected_utils <- c(
  "utils_assertions.R", "utils_attrition.R", "utils_cancer.R",
  "utils_dates.R", "utils_duckdb.R", "utils_icd.R",
  "utils_payer.R", "utils_pptx.R", "utils_snapshot.R",
  "utils_treatment.R"
)

utils_files <- list.files("R/utils", pattern = "\\.R$")
missing_utils <- setdiff(expected_utils, utils_files)

check(
  glue("All 10 utils modules present (missing: {paste(missing_utils, collapse=', ') %||% 'none'})"),
  length(missing_utils) == 0
)

# Validate no stale utils remain in R/ root (should all be in R/utils/)
stale_utils <- list.files("R", pattern = "^utils_.*\\.R$")
check(
  glue("No utils_*.R in R/ root (found: {paste(stale_utils, collapse=', ') %||% 'none'})"),
  length(stale_utils) == 0
)

# Validate key functions exist after 00_config.R auto-sources utils
source("R/00_config.R")

key_functions <- list(
  utils_assertions = "assert_rds_exists",
  utils_cancer     = "classify_codes",
  utils_payer      = "classify_payer_tier",
  utils_snapshot   = "build_output_path"
)

for (module in names(key_functions)) {
  func_name <- key_functions[[module]]
  check(glue("{module}: {func_name}() exists"), exists(func_name))
}
```

### Config Constants Validation
```r
# Validate all expected config constants exist in R/00_config.R
message("\n[Config Constants Validation]")

source("R/00_config.R")

expected_constants <- c(
  "CONFIG", "EXTRACT_DATE", "PCORNET_TABLES", "PCORNET_PATHS",
  "ICD_CODES", "PAYER_MAPPING", "AMC_PAYER_LOOKUP",
  "TREATMENT_CODES", "ANALYSIS_PARAMS",
  "CANCER_SITE_MAP",  # Added Phase 73
  "TIER_MAPPING"       # Added Phase 73
)

for (const_name in expected_constants) {
  check(glue("{const_name} defined in config"), exists(const_name))
}

# Validate structure of key constants
check(
  "CANCER_SITE_MAP is named character vector",
  is.character(CANCER_SITE_MAP) && !is.null(names(CANCER_SITE_MAP))
)

check(
  glue("CANCER_SITE_MAP has 324 entries (found {length(CANCER_SITE_MAP)})"),
  length(CANCER_SITE_MAP) == 324
)

check(
  "TIER_MAPPING is character vector",
  is.character(TIER_MAPPING)
)

check(
  glue("TIER_MAPPING has 8 entries (found {length(TIER_MAPPING)})"),
  length(TIER_MAPPING) == 8
)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| testthat for all R testing | Manual check() pattern for standalone scripts | 2024-2025 (community consensus) | testthat Issue #1490 (2023) and Posit Community discussions show poor fit for non-package projects. Manual patterns are simpler, SLURM-compatible, no scaffolding. |
| Manual dependency documentation | Parse structured headers (Phase 69) | Phase 69 (2026-06-01) | All 67 numbered scripts + 10 utils have 5-field headers (Purpose/Inputs/Outputs/Dependencies/Requirements). Machine-parseable for auto-generated documentation. |
| Hardcoded test expectations | Auto-detection via dir.exists() | Phase 74 | Cross-platform testing: structural checks pass on Windows, data checks gated behind HiPerGator data availability. |

**Deprecated/outdated:**
- **testthat for standalone scripts:** Community consensus (GitHub Issue #1490, Posit forums) is that testthat is poorly suited for non-package R projects. Manual patterns preferred.
- **8 utils modules:** R/86 and R/87 expect 8 utils, but utils_assertions.R (Phase 72) and utils_cancer.R (Phase 73) increased count to 10. Tests must update expected counts.
- **PREFIX_MAP in individual scripts:** Phase 73 consolidated to CANCER_SITE_MAP in R/00_config.R. Smoke tests should validate no duplicates remain.

## Open Questions

1. **R/86 vs R/87 vs new R/88 consolidation strategy**
   - What we know: R/86 validates foundation (utils/, 00-03 chain). R/87 validates full reorganization (decades, source() refs). Some checks overlap (utils count, foundation scripts).
   - What's unclear: Best consolidation strategy — merge all checks into enhanced R/87, create new R/88 that supersedes both, or keep separate with R/88 as comprehensive superset?
   - Recommendation: Start with consolidation analysis in Wave 0 (count overlapping checks, estimate merge effort). If >50% overlap, merge into enhanced R/87. If <30% overlap, create new R/88. Document decision in plan.

2. **Multi-line header field parsing strategy**
   - What we know: Phase 69 headers use continuation lines for readability (e.g., "# Inputs:\n#   - ENROLLMENT.csv\n#   - DIAGNOSIS.csv"). Simple regex extracts only first line.
   - What's unclear: Best extraction strategy — parse full multi-line blocks, extract first line only and link to source, or flatten to single line?
   - Recommendation: Extract first line for summary table, add "View source" links to full script. Avoids complex multi-line parsing while preserving detail access.

3. **Config constant usage detection**
   - What we know: D-09 requires "Config Constants Used" column in dependency matrix. Need to detect which scripts use CANCER_SITE_MAP, TIER_MAPPING, ICD_CODES, etc.
   - What's unclear: Detection method — grep for constant names in script body, or infer from source chain (all scripts via 00_config have access to all constants)?
   - Recommendation: Grep for actual usage (e.g., `grepl("CANCER_SITE_MAP", script_body)`). More accurate than assuming access = usage. Helps identify which scripts are affected by config changes.

## Environment Availability

Phase 74 smoke tests and reference manual generation are code/structure-only operations with no external dependencies beyond the existing R environment (base R, tidyverse already installed via renv). This section is omitted.

## Validation Architecture

> Validation architecture section omitted per workflow.nyquist_validation: false in .planning/config.json.

## Sources

### Primary (HIGH confidence)
- Existing codebase:
  - `R/86_smoke_test_foundation.R` - Manual check() pattern, utils validation, foundation chain checks
  - `R/87_smoke_test_full_pipeline.R` - Decade validation, source() parsing, dependency chain checks
  - `R/SCRIPT_INDEX.md` - Canonical script inventory with 67 numbered + 10 utils + 8 archived
  - All 67 numbered scripts have Phase 69 structured headers (Purpose, Inputs, Outputs, Dependencies, Requirements)
- R official documentation:
  - [.Platform documentation](https://stat.ethz.ch/R-manual/R-devel/library/base/html/Platform.html) - Platform detection via .Platform$OS.type
  - [file.path() documentation](https://stat.ethz.ch/R-manual/R-devel/library/base/html/file.path.html) - Cross-platform path construction

### Secondary (MEDIUM confidence)
- [testthat Issue #1490: Support for testing non-package R project structures](https://github.com/r-lib/testthat/issues/1490) - Community consensus that testthat is poorly suited for standalone scripts
- [Posit Community: Testing R scripts/code outside of package development](https://forum.posit.co/t/testing-r-scripts-code-outside-of-package-development/10086) - Manual approaches for non-package testing
- [renv::dependencies() documentation](https://rstudio.github.io/renv/reference/dependencies.html) - Static analysis for library() and package::function() calls
- [fs package documentation](https://fs.r-lib.org/) - Cross-platform file system operations (optional enhancement)
- [Cross Platform Development - Mastering Software Development in R](https://bookdown.org/rdpeng/RProgDA/cross-platform-development.html) - Best practices for Windows/Linux compatibility
- [SLURM Job Exit Codes](https://slurm.schedmd.com/job_exit_code.html) - Non-zero exit codes trigger job failure

### Tertiary (LOW confidence)
- [Unit testing with file paths across Windows and Linux](https://medium.com/@jonathantwite/unit-testing-with-file-paths-across-windows-and-linux-32dc49460aa7) - Case-sensitivity pitfalls (general guidance, not R-specific)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Existing codebase demonstrates manual check() pattern works for this project; testthat community consensus documented in GitHub issues and forums
- Architecture: HIGH - R/86 and R/87 provide proven patterns; Phase 69 structured headers are parseable with base R regex
- Pitfalls: HIGH - Case-sensitivity and testthat issues verified across official R docs, community forums, and existing codebase experience
- Cross-platform testing: HIGH - .Platform$OS.type and dir.exists() are base R, documented in official manuals, proven in HPC contexts

**Research date:** 2026-06-02
**Valid until:** ~60 days (testing patterns stable; R 4.4.2 is current stable release through 2026-08)
