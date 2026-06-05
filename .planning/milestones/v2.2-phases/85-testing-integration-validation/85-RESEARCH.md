# Phase 85: Testing Integration & Validation - Research

**Researched:** 2026-06-05
**Domain:** R testing infrastructure, DuckDB integration testing, smoke test patterns, environment-conditional validation
**Confidence:** HIGH

## Summary

Phase 85 integrates the test fixtures (Phase 84) with the existing DuckDB ingest pipeline (R/03_duckdb_ingest.R) and smoke test (R/88_smoke_test_comprehensive.R) to validate that the local testing infrastructure works end-to-end. The phase has zero stack additions — all required infrastructure exists. The work is purely integration: ensuring R/03 can ingest fixture CSVs without code changes, extending R/88 with new validation sections (3B: environment detection, 3C: fixture schema), and documenting conditional test execution patterns.

**Primary recommendation:** Leverage existing infrastructure. R/03 already uses CONFIG$cache$raw_dir which points to tempdir() in local mode. R/88 already validates environment detection (Section 15b). The integration tasks are surgical: verify R/03 works with fixtures, add fixture-specific schema validation to R/88 (conditional on IS_LOCAL), and document the 2-minute end-to-end performance target.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TEST-01 | DuckDB ingest (R/03) works with fixture CSVs without code changes | R/03 already sources CONFIG from R/00 which provides IS_LOCAL-conditional paths; vroom reads from CONFIG$data_dir (tests/fixtures/ in local mode); RDS cache writes to tempdir() |
| TEST-02 | R/88 smoke test passes locally against fixtures | R/88 is a structural smoke test (filesystem validation); all checks are data-agnostic except new sections 3B/3C |
| TEST-03 | Smoke test validates environment detection flag and fixture schema | Section 3B (environment) exists (line 1226-1304); Section 3C (fixture schema) needs creation with conditional execution (`if (IS_LOCAL)`) |
| TEST-04 | Full pipeline end-to-end runnable locally | Pipeline is modular (source R/00, R/01, R/03 sequentially); no interdependencies block local execution |
| TEST-05 | Conditional assertions in smoke test (fixture counts vs production counts) | testthat skip_if() pattern: `if (!IS_LOCAL) { check(...) }` for fixture-only validations |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| DuckDB | 1.1.3+ | In-process analytical database | Already in use; R/03_duckdb_ingest.R existing infrastructure |
| vroom | 1.7.0+ | Multi-threaded CSV parsing | Already in use; R/01_load_pcornet.R loads CSVs |
| testthat | 3.3.2+ | R unit testing framework | Already updated (edition 3); smoke test uses check() helper not testthat syntax |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| glue | 1.8.0 | String interpolation for logging | Already in use throughout smoke test |
| checkmate | 2.3.2+ | Defensive assertions | Already in use; utils_assertions.R provides assert_* helpers |
| DBI | 1.2.3+ | Database interface abstraction | Already in use; required by DuckDB R binding |

**Installation:**
```bash
# No new packages required — all dependencies already installed in Phase 83-84
# Verification only:
Rscript -e "library(duckdb); library(vroom); library(glue)"
```

**Version verification:** Phase 84 already verified package availability. No version changes needed.

## Architecture Patterns

### Recommended Test Execution Flow
```
Local testing workflow (Windows or Linux with R_TESTING_ENV=local):
  1. source("R/00_config.R")       # IS_LOCAL = TRUE, paths set to tests/fixtures/
  2. source("R/01_load_pcornet.R") # vroom reads 15 CSVs from tests/fixtures/
  3. source("R/03_duckdb_ingest.R") # Writes to tempdir()/pcornet_test.duckdb
  4. source("R/88_smoke_test_comprehensive.R") # Validates structure + fixture schema

Production workflow (HiPerGator Linux without env var):
  1. source("R/00_config.R")       # IS_LOCAL = FALSE, paths set to /orange/ and /blue/
  2. source("R/01_load_pcornet.R") # vroom reads 15 CSVs from /orange/
  3. source("R/03_duckdb_ingest.R") # Writes to /blue/.../pcornet.duckdb
  4. source("R/88_smoke_test_comprehensive.R") # Validates structure, skips fixture checks
```

### Pattern 1: Environment-Conditional Test Execution
**What:** Smoke test sections that only run in specific environments (local vs production)
**When to use:** Fixture-specific validations that don't apply to production data
**Example:**
```r
# In R/88_smoke_test_comprehensive.R — Section 3C

if (IS_LOCAL) {
  message("\n[3C] Fixture schema validation (local mode only)...")

  # Validate fixture patient count
  check(
    "Fixture ENROLLMENT has 20 patients (PT001-PT020)",
    nrow(pcornet$ENROLLMENT) == 20
  )

  # Validate edge case patients exist
  check(
    "PT003 (NLPHL patient) exists in fixtures",
    "PT003" %in% pcornet$DIAGNOSIS$ID
  )

  # Validate ABVD regimen patient
  check(
    "PT012 has 4 RXNORM_CUIs (ABVD regimen)",
    sum(pcornet$PRESCRIBING$ID == "PT012") == 4
  )
} else {
  message("\n[3C] Fixture schema validation — SKIPPED (production mode)")
}
```

### Pattern 2: DuckDB Connection Validation in Local Mode
**What:** Verify DuckDB file exists in tempdir() with expected table count
**When to use:** After R/03 ingest, before downstream processing
**Example:**
```r
# In R/88 Section 3B (environment detection)

if (IS_LOCAL) {
  # Validate DuckDB file exists in tempdir()
  check(
    "DuckDB file created in tempdir()",
    file.exists(CONFIG$cache$duckdb_path)
  )

  # Validate table count (15 PCORnet tables)
  con <- DBI::dbConnect(duckdb::duckdb(), CONFIG$cache$duckdb_path)
  table_count <- length(DBI::dbListTables(con))
  DBI::dbDisconnect(con, shutdown = TRUE)

  check(
    glue("DuckDB contains 15 tables (found {table_count})"),
    table_count == 15
  )
}
```

### Pattern 3: Performance Benchmarking
**What:** Time full pipeline execution and validate against 2-minute target
**When to use:** End-to-end local testing before HiPerGator deployment
**Example:**
```r
# Manual timing command (not in R/88, developer workflow)

start_time <- Sys.time()
source("R/00_config.R")
source("R/01_load_pcornet.R")
source("R/03_duckdb_ingest.R")
source("R/88_smoke_test_comprehensive.R")
end_time <- Sys.time()

duration <- as.numeric(difftime(end_time, start_time, units = "secs"))
message(glue("Full pipeline: {round(duration, 1)}s"))

if (duration > 120) {
  warning("Pipeline exceeded 2-minute target")
}
```

### Anti-Patterns to Avoid

- **Don't load production data in local mode:** IS_LOCAL flag prevents accidental access to /orange/ paths, but developers should never override CONFIG$data_dir to point to production in .Renviron
- **Don't skip environment checks on HiPerGator:** Section 3B (environment detection) must run in both modes; only Section 3C (fixture schema) is local-only
- **Don't use absolute paths in test assertions:** Use normalizePath() with winslash="/" for cross-platform path comparison (see R/88 line 1254 pattern)

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Test skipping logic | Custom if/else per test | testthat skip_if() + IS_LOCAL flag | testthat provides skip_if(!IS_LOCAL, "Production mode") for conditional execution; already validated pattern |
| DuckDB connection pooling | Custom connection manager | DBI::dbConnect() + explicit dbDisconnect() | DuckDB R binding handles connection lifecycle; custom pooling adds complexity for zero gain in single-session testing |
| Fixture row count validation | Manual nrow() checks per table | Parameterized check() function with table loop | R/88 already uses check() helper; wrap in for loop over PCORNET_TABLES for DRY validation |
| Performance profiling | Custom microbenchmark setup | System.time() or Sys.time() diff | Single-pass end-to-end timing sufficient for 2-minute target; microbenchmark overkill for integration test |

**Key insight:** R/88 already has the check() infrastructure (lines 51-59). Fixture validation is just adding new check() calls inside `if (IS_LOCAL)` blocks. Don't reinvent assertion logic.

## Runtime State Inventory

> Skip: Greenfield phase (integration/validation work, no state to migrate)

## Common Pitfalls

### Pitfall 1: DuckDB File Locking on Windows
**What goes wrong:** R/03 ingest succeeds but subsequent DBI::dbConnect() hangs or errors with "database is locked"
**Why it happens:** Windows file system doesn't always release file handles immediately after DBI::dbDisconnect(); tempdir() may have stale .duckdb.wal (write-ahead log) files
**How to avoid:** Always call `DBI::dbDisconnect(con, shutdown = TRUE)` with explicit shutdown flag; verify in R/03 line 107 pattern
**Warning signs:** Error message "database is locked", inability to delete .duckdb files from tempdir(), R session hang on second source("R/03_duckdb_ingest.R")

### Pitfall 2: Path Separator Mismatches in Smoke Test Assertions
**What goes wrong:** R/88 Section 3B path checks fail on Windows with "path mismatch" despite correct paths
**Why it happens:** CONFIG$cache$duckdb_path uses forward slashes (from file.path()), tempdir() returns backslashes on Windows
**How to avoid:** Use normalizePath(..., winslash = "/") on both sides of path comparison (see R/88 line 1254-1256 existing pattern)
**Warning signs:** check() failures with identical-looking paths that differ only in slash direction

### Pitfall 3: Fixture CSV Column Name Case Sensitivity
**What goes wrong:** vroom fails to load fixture CSVs with "column not found" errors
**Why it happens:** PCORnet CDM uses UPPERCASE column names; fixture generator (tests/generate_fixtures.R) must match exactly
**How to avoid:** Verify fixture CSVs use UPPERCASE column names (ID not id, ADMIT_DATE not admit_date); Phase 84 already documented this in FIXTURE_DESIGN.md
**Warning signs:** vroom error "Unknown columns: 'id'", mismatch between R/01 col_spec and fixture CSV headers

### Pitfall 4: Conditional Check Logic Inverted
**What goes wrong:** Fixture schema checks run in production mode, fail on real data
**Why it happens:** Developer writes `if (!IS_LOCAL)` instead of `if (IS_LOCAL)` for Section 3C
**How to avoid:** Section 3C is **local-only** — use `if (IS_LOCAL) { ... }` pattern; Section 3B is **both modes** — no if wrapper
**Warning signs:** R/88 fails on HiPerGator with "ENROLLMENT has 20 patients" check (production has 100K+ patients)

### Pitfall 5: RDS Cache Stale from Prior Production Run
**What goes wrong:** Local mode loads stale production RDS files instead of fixture CSVs
**Why it happens:** Developer previously ran pipeline in production mode, RDS cache in /blue/ still exists, CONFIG$cache$force_reload = FALSE
**How to avoid:** Local mode uses tempdir() for cache (Phase 83 design); verify CONFIG$cache$raw_dir points to tempdir() subdirectory when IS_LOCAL = TRUE
**Warning signs:** vroom reports "Loading from cache" but fixture patients (PT001-PT020) not found in loaded data

## Code Examples

Verified patterns from existing codebase:

### Smoke Test check() Helper (Existing Infrastructure)
```r
# Source: R/88_smoke_test_comprehensive.R lines 51-59
check <- function(description, condition) {
  if (condition) {
    message(glue("  PASS: {description}"))
    passed <<- passed + 1L
  } else {
    message(glue("  FAIL: {description}"))
    failed <<- failed + 1L
  }
}

# Usage in new Section 3C:
check("Fixture ENROLLMENT has 20 patients", nrow(pcornet$ENROLLMENT) == 20)
```

### Environment-Conditional Path Validation (Existing Pattern)
```r
# Source: R/88_smoke_test_comprehensive.R lines 1246-1267
if (IS_LOCAL) {
  check(
    "Local mode: data_dir points to tests/fixtures",
    grepl("tests.*fixtures", CONFIG$data_dir, ignore.case = TRUE)
  )
  check(
    "Local mode: DuckDB path in tempdir()",
    grepl(normalizePath(tempdir(), winslash = "/", mustWork = FALSE),
          normalizePath(CONFIG$cache$duckdb_path, winslash = "/", mustWork = FALSE),
          fixed = TRUE)
  )
} else {
  check(
    "Production mode: data_dir points to /orange/",
    grepl("^/orange/", CONFIG$data_dir)
  )
}
```

### DuckDB Table Count Verification
```r
# New pattern for Section 3B (DuckDB validation)
# Adapts existing R/03 connection pattern

if (IS_LOCAL && file.exists(CONFIG$cache$duckdb_path)) {
  con <- DBI::dbConnect(duckdb::duckdb(), CONFIG$cache$duckdb_path, read_only = TRUE)

  tables_found <- DBI::dbListTables(con)
  check(
    glue("DuckDB contains 15 tables (found {length(tables_found)})"),
    length(tables_found) == 15
  )

  # Validate specific tables exist
  expected_tables <- c("ENROLLMENT", "DIAGNOSIS", "ENCOUNTER", "DEMOGRAPHIC", "PROCEDURES")
  missing_tables <- setdiff(expected_tables, tables_found)
  check(
    glue("Expected tables present (missing: {paste(missing_tables, collapse=', ') %||% 'none'})"),
    length(missing_tables) == 0
  )

  DBI::dbDisconnect(con, shutdown = TRUE)
}
```

### Fixture Edge Case Patient Validation
```r
# New pattern for Section 3C (Fixture schema validation)
# Uses existing check() helper, pcornet list from R/01

if (IS_LOCAL) {
  message("\n[3C] Fixture schema validation (local mode only)...")

  # Edge case 1: Dual-eligible patient (PT002)
  dual_eligible_records <- pcornet$ENCOUNTER %>%
    filter(ID == "PT002", PAYER_TYPE_PRIMARY == "14")
  check(
    "PT002 (dual-eligible) has payer code 14",
    nrow(dual_eligible_records) > 0
  )

  # Edge case 2: NLPHL patient (PT003)
  nlphl_records <- pcornet$DIAGNOSIS %>%
    filter(ID == "PT003", DX == "C81.00")
  check(
    "PT003 has NLPHL diagnosis (C81.00)",
    nrow(nlphl_records) > 0
  )

  # Edge case 3: SCT patient (PT004)
  sct_records <- pcornet$PROCEDURES %>%
    filter(ID == "PT004", PX == "38241")
  check(
    "PT004 has SCT procedure (CPT 38241)",
    nrow(sct_records) > 0
  )

  # Edge case 4: ABVD regimen patient (PT012)
  abvd_drugs <- pcornet$PRESCRIBING %>%
    filter(ID == "PT012")
  expected_cuis <- c("3639", "11213", "67228", "3946")
  found_cuis <- abvd_drugs$RXNORM_CUI
  check(
    glue("PT012 has ABVD regimen (4 drugs: {paste(found_cuis, collapse=', ')})"),
    all(expected_cuis %in% found_cuis)
  )

  # Edge case 5: Orphan dx patient (PT008)
  orphan_dx_records <- pcornet$DIAGNOSIS %>%
    filter(ID == "PT008", DX == "Z51.11")
  check(
    "PT008 has orphan dx code (Z51.11 without paired procedure)",
    nrow(orphan_dx_records) > 0
  )
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual data mocking per test | Centralized fixture CSVs in tests/fixtures/ | Phase 84 (2026-06-04) | Reproducible, git-tracked test data; eliminates per-test data setup |
| Hardcoded /orange/ and /blue/ paths | IS_LOCAL conditional paths in R/00_config.R | Phase 83 (2026-06-04) | Zero-code-change local testing; production-safe defaults |
| No local testing infrastructure | Environment auto-detection + tempdir() cache | Phase 83 (2026-06-04) | Developers can run pipeline locally without HiPerGator access |

**Deprecated/outdated:**
- None: This is greenfield testing infrastructure (v2.2 milestone)

## Open Questions

1. **Should fixture schema validation (Section 3C) block smoke test exit code?**
   - What we know: R/88 exits with code 1 if any check() fails (line 1537-1539)
   - What's unclear: Whether fixture-specific failures should block local development
   - Recommendation: Yes, fail fast. If fixtures don't match schema, later scripts will error opaquely. Fixture schema validation is a **precondition** for downstream testing.

2. **What is the actual expected performance target for 20-patient fixtures?**
   - What we know: Phase 85 success criteria specify "under 2 minutes" for full local pipeline
   - What's unclear: Is this realistic for DuckDB ingest + smoke test on Windows?
   - Recommendation: 2 minutes is generous. DuckDB benchmarks show 3.84s for analytical queries on larger datasets. 20-patient ingest should be <10s. Document actual timing in Phase 85 summary.

3. **Should R/88 validate fixture data quality (e.g., ICD code validity)?**
   - What we know: Fixtures include edge case ICD codes (C81.00, Z51.11, 201.90)
   - What's unclear: Whether R/88 should validate ICD codes against ICD_CODES config constant
   - Recommendation: No. R/88 is a structural smoke test (files exist, schemas match). Data quality validation is the job of downstream scripts (R/14 cohort predicates, R/45+ cancer summary). Keep R/88 lightweight.

## Environment Availability

> Greenfield phase with no external dependencies beyond Phase 83-84 deliverables. All required R packages already installed.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| DuckDB R binding | R/03 ingest | ✓ | 1.1.3+ | — |
| vroom | R/01 CSV loading | ✓ | 1.7.0+ | readr (slower) |
| DBI | DuckDB connection | ✓ | 1.2.3+ | — |
| glue | R/88 logging | ✓ | 1.8.0 | — |
| checkmate | Defensive assertions | ✓ | 2.3.2+ | — |
| testthat | (not used, but available) | ✓ | 3.3.2 | — |

**Missing dependencies with no fallback:**
- None

**Missing dependencies with fallback:**
- None

## Sources

### Primary (HIGH confidence)
- R/88_smoke_test_comprehensive.R (existing smoke test infrastructure, lines 51-59, 1226-1304)
- R/03_duckdb_ingest.R (existing DuckDB ingest logic, lines 1-200)
- R/00_config.R (environment detection, lines 34-76)
- R/01_load_pcornet.R (vroom CSV loading, column specs)
- tests/fixtures/FIXTURE_DESIGN.md (edge case patient mapping)
- Phase 83 plans (83-01-PLAN.md, 83-02-PLAN.md)
- Phase 84 plans (84-01-PLAN.md, 84-02-PLAN.md)

### Secondary (MEDIUM confidence)
- [testthat skipping functions documentation](https://testthat.r-lib.org/articles/skipping.html) - skip_if() conditional execution patterns
- [DuckDB R package changelog](https://r.duckdb.org/news/index.html) - testthat edition 3 update
- [DuckDB official benchmarks](https://duckdb.org/docs/current/guides/performance/benchmarks) - performance expectations for analytical queries

### Tertiary (LOW confidence)
- [Medium: Unit testing SQL queries with DuckDB](https://medium.com/clarityai-engineering/unit-testing-sql-queries-with-duckdb-23743fd22435) - fixture design patterns (not R-specific)
- [BrowserStack: Smoke Testing Guide 2026](https://www.browserstack.com/guide/smoke-testing) - general smoke test principles (not R-specific)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All packages already installed and verified in Phase 83-84
- Architecture: HIGH - Existing R/88 check() infrastructure well-documented; clear extension points
- Pitfalls: HIGH - DuckDB locking on Windows is well-known; path normalization pattern already in R/88

**Research date:** 2026-06-05
**Valid until:** 2026-07-05 (30 days, stable infrastructure)
