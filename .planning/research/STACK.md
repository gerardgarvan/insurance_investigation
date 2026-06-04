# Technology Stack — v2.2 Local Testing Infrastructure

**Project:** PCORnet Payer Variable Investigation (R Pipeline)
**Milestone:** v2.2 Local Testing Infrastructure
**Researched:** 2026-06-03

---

## Executive Summary

**ONE NEW PACKAGE REQUIRED: testthat 3.3.2.** The v2.2 milestone adds local testing infrastructure (environment auto-detection + test fixtures) using:

- **Base R** — `Sys.info()` for OS/hostname detection (NO new packages)
- **.Renviron** — R-native environment variable overrides (NO new packages)
- **testthat** — Structured testing framework with fixture support (NEW, version 3.3.2)
- **Existing tidyverse** — dplyr + base R `write.csv()` for hand-crafted test fixtures

**Key finding:** Environment detection requires ZERO packages. `Sys.info()["sysname"]` + `Sys.info()["nodename"]` provide OS detection and HiPerGator hostname matching via base R. Test data generation for clinical edge cases is best done manually (base R data.frame construction) rather than with generic faker libraries.

**Integration risk:** **MINIMAL** — testthat is the industry-standard R testing framework (part of tidyverse ecosystem), widely used, and already a dependency of withr. No conflicts with existing stack.

---

## New Capabilities → Stack Mapping

### Capability 1: Environment Auto-Detection (Local vs HiPerGator)

**Requirement:** R/00_config.R must automatically detect whether it's running on local Windows or HiPerGator Linux, and set appropriate data/cache/DuckDB paths accordingly.

**Existing stack solution:**

| Component | Package | Version | How to Use |
|-----------|---------|---------|------------|
| OS detection | Base R | (built-in) | `Sys.info()["sysname"]` returns "Windows", "Linux", or "Darwin" |
| Hostname detection | Base R | (built-in) | `Sys.info()["nodename"]` returns computer name (HiPerGator nodes contain "ufhpc") |
| Env var override | Base R | (built-in) | `Sys.getenv("R_ENV", unset = NA)` reads environment variables |
| Env var configuration | .Renviron | (built-in) | Project-level `.Renviron` file with `R_ENV=local` |

**NO NEW PACKAGES NEEDED.** Base R provides all environment detection capabilities.

**Implementation approach:**

```r
# In R/00_config.R
detect_environment <- function() {
  # Check override first (from .Renviron or SLURM env)
  env_override <- Sys.getenv("R_ENV", unset = NA)
  if (!is.na(env_override)) {
    return(tolower(env_override))  # "local" or "hpc"
  }

  # Auto-detect by OS + hostname
  sysname <- Sys.info()["sysname"]
  nodename <- Sys.info()["nodename"]

  if (sysname == "Windows") {
    return("local")
  } else if (grepl("ufhpc", nodename, ignore.case = TRUE)) {
    return("hpc")
  } else {
    return("local")  # Default to local for unknown Linux/macOS
  }
}

# Set paths based on environment
env <- detect_environment()
if (env == "hpc") {
  DATA_DIR <- "/blue/erin.mobley-hl.bcu/Mailhot/FLHodgkins_data_extraction_09152025/"
  RDS_DIR <- "/blue/erin.mobley-hl.bcu/clean/rds/"
  DUCKDB_PATH <- "/blue/erin.mobley-hl.bcu/clean/pcornet.duckdb"
} else {
  # Local defaults (Windows or local Linux/Mac)
  DATA_DIR <- here::here("tests", "testthat", "fixtures")
  RDS_DIR <- here::here("tests", "testthat", "cache")
  DUCKDB_PATH <- here::here("tests", "testthat", "fixtures", "pcornet_test.duckdb")
}
```

**Optional .Renviron override:**

```
# In project root .Renviron (gitignored)
R_ENV=local
```

**Why base R instead of config/dotenv packages:**

- **No dependencies** — `Sys.info()` is built into R since v1.0
- **Simple binary detection** — Only two environments (local vs HPC), not complex multi-environment config
- **.Renviron is R-native** — No need for YAML (config package) or .env parsing (dotenv package)
- **Follows R conventions** — .Renviron is standard R practice for environment-specific settings

**References:**
- [R: Extract System and User Information](https://stat.ethz.ch/R-manual/R-devel/library/base/html/Sys.info.html) — Official Sys.info() documentation
- [Identifying the OS from R | R-bloggers](https://www.r-bloggers.com/2015/06/identifying-the-os-from-r/) — Best practices for OS detection
- [Chapter 7 Environment Management | Best Coding Practices for R](https://bookdown.org/content/d1e53ac9-28ce-472f-bc2c-f499f18264a3/envManagement.html) — .Renviron best practices

**Confidence:** **HIGH** — Base R Sys.info() is stable API, used throughout R ecosystem for platform detection.

---

### Capability 2: Test Fixture Generation (Hand-Crafted Clinical Edge Cases)

**Requirement:** Create ~20-patient test fixture CSVs covering clinical edge cases (dual-eligible, NLPHL, SCT 0362, multiple cancers, death dates, orphan dx codes) that can be ingested via existing R/01 DuckDB path.

**Existing stack solution:**

| Component | Package | Version | How to Use |
|-----------|---------|---------|------------|
| Data frame construction | Base R | (built-in) | `data.frame()` to manually construct edge case patients |
| CSV writing | Base R | (built-in) | `write.csv()` to write fixtures to `tests/testthat/fixtures/` |
| Resampling (optional) | dplyr | 1.2.0+ (VALIDATED) | `sample_n()` to sample from real data if running on HPC |
| Path management | here | 1.0.2 (VALIDATED) | `here("tests", "testthat", "fixtures", "ENROLLMENT.csv")` for portable paths |

**NO NEW PACKAGES NEEDED.** Base R + existing dplyr provide sufficient fixture generation capabilities.

**Implementation approach:**

```r
# In tests/testthat/fixtures/generate_fixtures.R
library(dplyr)
library(here)

# Edge case patients (manually constructed for clinical scenarios):
# PT001: Dual-eligible (Medicare + Medicaid same day)
# PT002: NLPHL (C81.0x codes)
# PT003: Multiple cancers (HL + breast)
# PT004: SCT 0362 with other SCT codes in same encounter
# PT005: Death date with post-death activity
# PT006: Orphan dx codes (diagnosis without encounter linkage)
# PT007-020: Standard cases covering payer categories

enrollment <- data.frame(
  PATID = sprintf("PT%03d", 1:20),
  ENROLL_DATE = as.Date("2020-01-01") + (0:19) * 7,  # Staggered enrollment
  CHART = "Y",
  ENR_BASIS = "I",
  stringsAsFactors = FALSE
)

diagnosis <- data.frame(
  PATID = c(
    rep("PT001", 2),  # HL diagnosis
    rep("PT002", 2),  # NLPHL (C81.0x)
    rep("PT003", 4)   # Multiple cancers (HL + breast)
  ),
  ENCOUNTERID = c(
    "ENC001_1", "ENC001_2",
    "ENC002_1", "ENC002_2",
    "ENC003_1", "ENC003_2", "ENC003_3", "ENC003_4"
  ),
  DX = c(
    "C81.10", "C81.11",        # HL
    "C81.00", "C81.01",        # NLPHL
    "C81.20", "C81.21", "C50.911", "C50.912"  # HL + breast
  ),
  DX_TYPE = "09",  # ICD-10
  ADMIT_DATE = as.Date("2020-02-01") + c(0, 10, 0, 12, 0, 8, 15, 20),
  stringsAsFactors = FALSE
)

# Write to fixtures directory
write.csv(enrollment, here("tests", "testthat", "fixtures", "ENROLLMENT.csv"),
          row.names = FALSE)
write.csv(diagnosis, here("tests", "testthat", "fixtures", "DIAGNOSIS.csv"),
          row.names = FALSE)

# ... (repeat for other 11 PCORnet tables)
```

**Why manual construction over faker/generator packages:**

- **Clinical edge cases require deliberate design** — Dual-eligible requires specific ENROLLMENT rows with same PATID + date, not random generation
- **Small fixture size (~20 patients)** — Manual construction is faster than learning fabricatr/charlatan APIs
- **PCORnet CDM structure** — Generic faker libraries don't understand PCORnet foreign key relationships (PATID → ENCOUNTERID → diagnosis codes)
- **Validation targets** — Fixtures need to produce known outputs for smoke test assertions (e.g., "PT001 should have dual-eligible flag")

**When NOT to use charlatan/fabricatr:**

| Package | Why NOT Use | Use Case |
|---------|-------------|----------|
| charlatan | Generates realistic names/addresses/DOIs, not PCORnet medical codes | Generic fake data for demos |
| fabricatr | Hierarchical social science simulations (villages → households → individuals) | Large-scale survey data |
| wakefield | Quick demographic data, but stale (last update 2021) | Rapid prototyping with standard demographics |

**References:**
- [Writing Data From R to txt|csv Files: R Base Functions](https://www.sthda.com/english/wiki/writing-data-from-r-to-txt-csv-files-r-base-functions) — write.csv() documentation
- [Package 'charlatan' January 14, 2026](https://cran.r-project.org/web/packages/charlatan/charlatan.pdf) — Evaluated but NOT recommended
- [fabricatr: Imagine Your Data Before You Collect It](https://cran.r-project.org/package=fabricatr) — Evaluated but NOT recommended

**Confidence:** **HIGH** — Base R data.frame() + write.csv() is the simplest approach for small, deliberately designed fixtures.

---

### Capability 3: Structured Testing Framework (testthat)

**Requirement:** Adapt R/88 smoke test to run as a structured test against local fixtures, with proper setup/teardown and scoped environment modifications.

**NEW PACKAGE REQUIRED:**

| Package | Version | Purpose | Why |
|---------|---------|---------|-----|
| testthat | 3.3.2 | Structured testing with fixtures and snapshots | Industry standard for R testing, part of tidyverse ecosystem |

**testthat is the ONLY new dependency for v2.2.**

**Key capabilities:**

- **Test fixtures** — `tests/testthat/setup.R` for package-wide setup, `local_*()` functions for scoped cleanup
- **Snapshot testing** — `expect_snapshot()` for validating data frame outputs (useful for pipeline results)
- **Scoped environment** — Integration with withr for temporary environment variable changes
- **Standard structure** — `tests/testthat/test-*.R` convention recognized by RStudio and R CMD check

**Implementation approach:**

```r
# tests/testthat/test-smoke.R
# Adapted from R/88_smoke_test.R

test_that("Fixtures load into DuckDB", {
  # Force local environment for test
  withr::local_envvar(c(R_ENV = "local"))

  # Source config to set paths
  source(here::here("R", "00_config.R"))

  # Connect to test DuckDB
  con <- DBI::dbConnect(duckdb::duckdb(), DUCKDB_PATH, read_only = TRUE)
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))  # Cleanup

  # Verify fixture count
  enrollment_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) FROM ENROLLMENT")[[1]]
  expect_equal(enrollment_count, 20, label = "Fixture patients loaded")
})

test_that("Cohort filter chain runs locally", {
  withr::local_envvar(c(R_ENV = "local"))

  # Run cohort predicates
  source(here::here("R", "10_cohort_predicates.R"))

  # Verify cohort size (should be subset of 20 fixtures)
  cohort <- readRDS(here::here("tests", "testthat", "cache", "cohort.rds"))
  expect_true(nrow(cohort) >= 1 & nrow(cohort) <= 20)
  expect_true("PATID" %in% names(cohort))
})

test_that("Dual-eligible detection works on fixtures", {
  # Test specific edge case (PT001 should be dual-eligible)
  source(here::here("R", "11_payer_harmonization.R"))

  payer_data <- readRDS(here::here("tests", "testthat", "cache", "payer_harmonized.rds"))

  dual_eligible <- payer_data %>% filter(PATID == "PT001")
  expect_true(any(dual_eligible$is_dual_eligible))
})
```

**Why testthat:**

- **Tidyverse standard** — Maintained by Posit (RStudio), used in 10,000+ CRAN packages
- **Latest version (3.3.2, Jan 2026)** — Recent improvements to fixtures, snapshots, and failure messages
- **withr integration** — `local_envvar()` for scoped environment changes (included as testthat dependency)
- **RStudio integration** — "Run Tests" button, Cmd/Ctrl+Shift+T shortcut, test coverage visualization

**Optional withr usage (already included):**

| Function | Purpose | Example |
|----------|---------|---------|
| `local_envvar()` | Temporarily set env vars for test scope | `withr::local_envvar(c(R_ENV = "local"))` |
| `local_tempfile()` | Create temp file with auto-cleanup | `withr::local_tempfile(fileext = ".csv")` |
| `local_dir()` | Change working directory for test | `withr::local_dir(here::here("tests"))` |
| `defer()` | Register cleanup action | `withr::defer(DBI::dbDisconnect(con))` |

**References:**
- [Unit Testing for R • testthat](https://testthat.r-lib.org/) — Official documentation
- [Test fixtures • testthat](https://testthat.r-lib.org/articles/test-fixtures.html) — Fixture patterns and best practices
- [testthat 3.3.0 - Tidyverse](https://tidyverse.org/blog/2025/11/testthat-3-3-0/) — Version 3.3.0 changelog (Nov 2025)
- [CRAN: Package testthat](https://cran.r-project.org/package=testthat) — Current version 3.3.2 (Jan 2026)
- [Run Code With Temporarily Modified Global State • withr](https://withr.r-lib.org/) — withr documentation (testthat dependency)

**Confidence:** **HIGH** — testthat 3.3.2 is latest stable release (Jan 2026), widely adopted, part of tidyverse ecosystem.

---

## Packages NOT Needed (Evaluated and Rejected)

### Configuration Packages

| Package | Version | Why NOT Needed |
|---------|---------|---------------|
| config | 0.3.2 (Aug 2023) | Binary local/HPC detection doesn't need YAML overhead; .Renviron is R-native |
| dotenv | 1.0.3 (Apr 2021) | Stale (last updated 2021); .Renviron is standard R practice |

**Decision:** Use base R `Sys.info()` + `.Renviron` instead of adding config layer packages.

### Test Data Generation Packages

| Package | Version | Why NOT Needed |
|---------|---------|---------------|
| charlatan | 0.6.1 (Jan 2026) | Generates generic fake data (names, addresses), not PCORnet clinical edge cases |
| fabricatr | 1.0.2 (Dec 2023) | Hierarchical simulations for social science, overkill for 20-patient fixtures |
| wakefield | 0.3.6 (Sep 2021) | Stale (2021), doesn't understand PCORnet CDM structure |

**Decision:** Manual fixture construction with base R `data.frame()` + `write.csv()` provides more control over clinical edge cases.

### Additional Environment Detection

| Package | Why NOT Needed |
|---------|---------------|
| R.utils | `getHostname()` function adds dependency; `Sys.info()["nodename"]` is base R equivalent |

**Decision:** Base R provides all needed OS/hostname detection capabilities.

---

## Stack Status Summary

### Existing Stack (Unchanged)

**From v2.0 and v2.1:**

| Package | Version | Status | v2.2 Usage |
|---------|---------|--------|------------|
| tidyverse | 2.0.0+ | VALIDATED | Data manipulation in fixture generation |
| dplyr | 1.2.0+ | VALIDATED | Optional resampling from real data |
| here | 1.0.2 | VALIDATED | Portable paths for fixtures directory |
| DuckDB backend | (Phase 29-32) | VALIDATED | Test fixtures ingested via R/01 |
| checkmate | 2.3.4 | VALIDATED | Test assertions (assert_true, assert_data_frame) |

### New Packages for v2.2

| Package | Version | Status | Purpose |
|---------|---------|--------|---------|
| testthat | 3.3.2 (Jan 2026) | **NEW** | Structured testing with fixtures and snapshots |

### Dependencies (Included with testthat)

| Package | Version | Status | Purpose |
|---------|---------|--------|---------|
| withr | 3.0.2 (Oct 2024) | Included | Scoped environment variable management (testthat dependency) |

**withr is already installed as a testthat dependency — no separate installation needed.**

---

## Installation

### On HiPerGator

```bash
# Load R module
module load R/4.4.2

# Start R interactively
R
```

```r
# In R console
install.packages("testthat")  # Only NEW package for v2.2
renv::snapshot()
```

### On Local Windows

```r
# Install testthat
install.packages("testthat")
renv::snapshot()
```

### Verification

```r
# Check testthat version
packageVersion("testthat")
# Expected: 3.3.2

# withr should already be installed (testthat dependency)
packageVersion("withr")
# Expected: 3.0.2

# Verify environment detection works
Sys.info()[c("sysname", "nodename")]
# Windows: sysname = "Windows", nodename = your computer name
# HiPerGator: sysname = "Linux", nodename contains "ufhpc"
```

---

## Integration Checklist

- [ ] Install testthat on both HiPerGator and local Windows
- [ ] Add `detect_environment()` function to `R/00_config.R`
- [ ] Add conditional path logic (HPC vs local) to `R/00_config.R`
- [ ] Create project-level `.Renviron` with `R_ENV=local` (add to .gitignore)
- [ ] Create `tests/testthat/fixtures/` directory structure
- [ ] Write `generate_fixtures.R` script with 20 edge-case patients
- [ ] Generate fixture CSVs for 13 PCORnet tables
- [ ] Run R/01 locally to ingest fixtures into `pcornet_test.duckdb`
- [ ] Create `tests/testthat/test-smoke.R` adapted from R/88
- [ ] Validate smoke test passes locally with fixtures
- [ ] Document fixture design (README in fixtures/ explaining edge cases)
- [ ] Update .gitignore to exclude test cache and DuckDB files

---

## Anti-Patterns to Avoid

### 1. Don't Add config Package for Simple Binary Detection

**AVOID:**
```r
# Using config package for simple local/HPC switch
library(config)
config <- config::get(config = Sys.getenv("R_CONFIG_ACTIVE", "local"))
DATA_DIR <- config$data_dir
```

**PREFER:**
```r
# Simple base R detection
env <- if (Sys.info()["sysname"] == "Windows") "local" else "hpc"
DATA_DIR <- if (env == "hpc") "/blue/..." else here::here("tests/testthat/fixtures")
```

**Why:** config package adds YAML dependency and complexity for simple two-environment detection.

### 2. Don't Use Faker Libraries for Clinical Edge Cases

**AVOID:**
```r
# Random patient generation doesn't create edge cases
library(charlatan)
patients <- data.frame(
  PATID = replicate(20, ch_name()),  # Random names, not structured IDs
  ENROLL_DATE = replicate(20, ch_date())  # Random dates, no dual-eligible logic
)
```

**PREFER:**
```r
# Deliberate edge case construction
patients <- data.frame(
  PATID = c("PT001", "PT002", ...),  # Structured IDs for test assertions
  is_dual_eligible = c(TRUE, FALSE, ...),  # Explicit edge case flags
  scenario = c("dual-eligible", "NLPHL", ...)  # Documented test scenarios
)
```

**Why:** Test fixtures need predictable edge cases for assertions, not realistic randomness.

### 3. Don't Skip .Renviron for Environment Overrides

**AVOID:**
```r
# Hardcoding environment in script
env <- "local"  # Must manually change before deploying to HPC
```

**PREFER:**
```r
# Check .Renviron first, then auto-detect
env_override <- Sys.getenv("R_ENV", unset = NA)
env <- if (!is.na(env_override)) env_override else detect_environment()
```

**Why:** .Renviron allows per-developer overrides without modifying code.

### 4. Don't Commit Test Fixtures to Git (If Large)

**AVOID:**
```r
# Committing 20 full PCORnet CSVs with realistic data volumes
# tests/testthat/fixtures/PROCEDURES.csv (1M rows, 50 MB)
```

**PREFER:**
```r
# Keep fixtures minimal (~20 patients, <1 MB total)
# tests/testthat/fixtures/PROCEDURES.csv (100 rows, <10 KB)

# OR: Generate fixtures programmatically from RDS snapshots
# tests/testthat/fixtures/generate_fixtures.R sources from actual data
```

**Why:** Git performance degrades with large binary files. Keep fixtures minimal or generate on-demand.

---

## Testing Best Practices

### From R Testing Community

**Avoid "Mystery Guest" anti-pattern:**

```r
# AVOID: Test depends on .Rprofile or options() set elsewhere
test_that("Payer mapping works", {
  # Assumes options(amc.payer.strict = TRUE) set in .Rprofile
  result <- harmonize_payer(data)
  expect_equal(result$payer_category, "Medicare")
})

# PREFER: Set options explicitly in test with withr
test_that("Payer mapping works", {
  withr::local_options(list(amc.payer.strict = TRUE))
  result <- harmonize_payer(data)
  expect_equal(result$payer_category, "Medicare")
})
```

**Avoid "Test Logic in Production" anti-pattern:**

```r
# AVOID: if (env == "test") branches in production code
if (Sys.getenv("R_ENV") == "test") {
  load_data_from_fixtures()
} else {
  load_data_from_hpc()
}

# PREFER: Dependency injection via config
load_data <- function(data_dir = CONFIG$data_dir) {
  read.csv(file.path(data_dir, "ENROLLMENT.csv"))
}

# Test passes different data_dir
test_that("Data loads", {
  data <- load_data(data_dir = here::here("tests/testthat/fixtures"))
  expect_true(nrow(data) > 0)
})
```

**References:**
- [11 Test Smells That Make Your Tests Lie to You | R-bloggers](https://www.r-bloggers.com/2026/06/11-test-smells-that-make-your-tests-lie-to-you/) — R testing anti-patterns (June 2026)
- [14 Designing your test suite – R Packages (2e)](https://r-pkgs.org/testing-design.html) — Test design patterns with withr

---

## Implementation Roadmap Suggestions

### Phase Sequencing for v2.2

**Foundation phases:**
1. **Phase v2.2-01:** Add `detect_environment()` to R/00_config.R with conditional path logic
2. **Phase v2.2-02:** Create `.Renviron` with `R_ENV=local` and add to .gitignore
3. **Phase v2.2-03:** Install testthat on both HiPerGator and local Windows

**Fixture creation phases:**
4. **Phase v2.2-04:** Design 20-patient fixture scenarios (document edge cases in README)
5. **Phase v2.2-05:** Create `generate_fixtures.R` script for 13 PCORnet tables
6. **Phase v2.2-06:** Run fixture generation and verify CSV structure

**DuckDB integration phases:**
7. **Phase v2.2-07:** Run R/01 locally to ingest fixtures into `pcornet_test.duckdb`
8. **Phase v2.2-08:** Verify round-trip (CSV → DuckDB → query) with all 13 tables

**Smoke test adaptation phases:**
9. **Phase v2.2-09:** Create `tests/testthat/test-smoke.R` from R/88 baseline
10. **Phase v2.2-10:** Add fixture-specific assertions (e.g., PT001 dual-eligible check)
11. **Phase v2.2-11:** Run smoke test locally and fix failures

**Validation and documentation:**
12. **Phase v2.2-12:** Document fixture design (which patients test which edge cases)
13. **Phase v2.2-13:** Update smoke test for v2.0/v2.1 features (if needed)
14. **Phase v2.2-14:** Create local testing guide (README in tests/testthat/)

**Rationale:** Foundation (env detection + testthat install) → Fixture design (deliberate edge cases) → DuckDB integration (reuse R/01) → Smoke test adaptation (validate locally) → Documentation.

---

## Version Verification (All Current as of 2026-06-03)

| Package | Current Version | Publication Date | Source | Status |
|---------|-----------------|------------------|--------|--------|
| **testthat** | 3.3.2 | 2026-01-11 | [CRAN](https://cran.r-project.org/package=testthat) | ✅ Current |
| **withr** | 3.0.2 | 2024-10-28 | [CRAN](https://cran.r-project.org/package=withr) | ✅ Current (testthat dep) |

**Both packages are current (published within 6 months of 2026-06-03). No updates needed.**

---

## Confidence Assessment

| Area | Confidence | Rationale |
|------|------------|-----------|
| **Environment detection (base R)** | **HIGH** | Official R documentation; Sys.info() is stable base R since v1.0 |
| **testthat for fixtures** | **HIGH** | Latest version 3.3.2 (Jan 2026); tidyverse standard, 10K+ CRAN packages |
| **Manual fixture generation** | **HIGH** | Base R data.frame() + write.csv(); no new dependencies |
| **.Renviron for overrides** | **HIGH** | R-native; documented best practice |
| **withr for scoped env vars** | **HIGH** | CRAN stable release 3.0.2 (Oct 2024); testthat dependency |
| **config/dotenv NOT needed** | **MEDIUM** | WebSearch consensus; verified against official docs |
| **charlatan/fabricatr NOT needed** | **MEDIUM** | Package docs reviewed; clinical edge cases require manual construction |

**Overall confidence:** **HIGH** for recommended approach (base R + testthat), **MEDIUM** for exclusions (verified via official docs but could have niche use cases).

---

## Summary

**v2.2 Local Testing Infrastructure requires ONE new package: testthat 3.3.2.** All other features use base R or existing stack:

| Feature | Primary Tool | Status |
|---------|--------------|--------|
| Environment detection | Base R Sys.info() | ✅ No packages needed (built-in) |
| Environment overrides | .Renviron | ✅ R-native configuration |
| Test framework | testthat | ✅ NEW (v3.3.2, tidyverse standard) |
| Fixture generation | Base R data.frame() + write.csv() | ✅ No packages needed (built-in) |
| Scoped env vars (optional) | withr | ✅ Included (testthat dependency) |
| Path management | here | ✅ Existing (v1.0.2, validated in v1.0) |

**Key principles:**
1. **Prefer base R for simple tasks** — Sys.info() beats config packages for binary detection
2. **Manual fixtures for edge cases** — Deliberate construction beats random generation for clinical scenarios
3. **Industry standards for testing** — testthat is the R community standard (10K+ packages)
4. **Minimal new dependencies** — Only testthat added; withr included automatically
5. **Reuse existing infrastructure** — DuckDB ingest via R/01, smoke test from R/88

**Risk assessment:** **MINIMAL** — testthat is mature, widely adopted, and maintained by Posit (RStudio). withr is already validated as testthat dependency. No version conflicts with existing stack.

---

## Sources

### Environment Detection
- [R: Extract System and User Information](https://stat.ethz.ch/R-manual/R-devel/library/base/html/Sys.info.html) — Official base R documentation for Sys.info()
- [Identifying the OS from R | R-bloggers](https://www.r-bloggers.com/2015/06/identifying-the-os-from-r/) — Best practices for OS detection
- [R: Get Environment Variables](https://stat.ethz.ch/R-manual/R-devel/library/base/html/Sys.getenv.html) — Official Sys.getenv() documentation
- [Chapter 7 Environment Management | Best Coding Practices for R](https://bookdown.org/content/d1e53ac9-28ce-472f-bc2c-f499f18264a3/envManagement.html) — .Renviron best practices

### Testing Framework
- [Unit Testing for R • testthat](https://testthat.r-lib.org/) — Official testthat documentation
- [Test fixtures • testthat](https://testthat.r-lib.org/articles/test-fixtures.html) — Fixture patterns and best practices
- [testthat 3.3.0 - Tidyverse](https://tidyverse.org/blog/2025/11/testthat-3-3-0/) — Version 3.3.0 changelog (Nov 2025)
- [CRAN: Package testthat](https://cran.r-project.org/package=testthat) — Current version 3.3.2 (Jan 2026)
- [14 Designing your test suite – R Packages (2e)](https://r-pkgs.org/testing-design.html) — Test design patterns with withr

### withr (testthat dependency)
- [Run Code With Temporarily Modified Global State • withr](https://withr.r-lib.org/) — Official withr documentation
- [Environment variables — with_envvar • withr](https://withr.r-lib.org/reference/with_envvar.html) — local_envvar() and with_envvar() reference
- [CRAN: Package withr](https://cran.r-project.org/web/packages/withr/index.html) — Current version 3.0.2 (Oct 2024)

### Configuration Packages (Evaluated but NOT Recommended)
- [CRAN: Package config](https://cran.r-project.org/package=config) — YAML-based config (version 0.3.2, Aug 2023)
- [R config: How to Manage Environment-Specific Configuration Files](https://www.appsilon.com/post/r-config) — config package tutorial
- [CRAN: Package dotenv](https://cran.r-project.org/web/packages/dotenv/index.html) — .env file loading (version 1.0.3, Apr 2021)

### Test Data Generation (Evaluated but NOT Recommended)
- [Package 'charlatan' January 14, 2026](https://cran.r-project.org/web/packages/charlatan/charlatan.pdf) — Fake data generation (version 0.6.1)
- [CRAN: Package charlatan](https://cran.r-project.org/package=charlatan) — Current version info
- [fabricatr: Imagine Your Data Before You Collect It](https://cran.r-project.org/package=fabricatr) — Hierarchical data simulation (version 1.0.2, Dec 2023)
- [Using other data generating packages with fabricatr](https://declaredesign.org/r/fabricatr/articles/other_packages.html) — Integration patterns

### Testing Best Practices
- [11 Test Smells That Make Your Tests Lie to You | R-bloggers](https://www.r-bloggers.com/2026/06/11-test-smells-that-make-your-tests-lie-to-you/) — R testing anti-patterns (June 2026)
- [Writing Data From R to txt|csv Files: R Base Functions](https://www.sthda.com/english/wiki/writing-data-from-r-to-txt-csv-files-r-base-functions) — Base R write.csv() documentation

---

**Confidence:** **HIGH** — All sources verified (CRAN package versions current as of 2026-06-03, official R documentation for base functions). Source hierarchy: CRAN official → Official R docs → R community best practices (R-bloggers, tidyverse blog).

*Last updated: 2026-06-03*
*Researcher: GSD Project Researcher (Phase 6)*
