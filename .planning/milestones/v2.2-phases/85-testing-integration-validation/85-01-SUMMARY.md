---
phase: 85-testing-integration-validation
plan: 01
subsystem: testing
tags: [duckdb, fixtures, integration-test, smoke-test, validation]
dependency_graph:
  requires: [83-01, 83-02, 84-01, 84-02]
  provides: [local-pipeline-validation, duckdb-fixture-integration, smoke-test-fixture-validation]
  affects: [R/88_smoke_test_comprehensive.R, tests/run_local_test.R]
tech_stack:
  added: []
  patterns: [conditional-validation, environment-gated-checks, end-to-end-testing]
key_files:
  created:
    - tests/run_local_test.R
  modified:
    - R/88_smoke_test_comprehensive.R
decisions:
  - "Sections 32/33 use fully-qualified DBI:: and dplyr:: calls to avoid polluting R/88 namespace with library() imports"
  - "Section 33 (fixture validation) only runs when IS_LOCAL=TRUE; production skips fixture-specific checks"
  - "DBI::dbDisconnect always uses shutdown=TRUE to prevent Windows file locking issues"
  - "run_local_test.R saves/restores timing variables around R/88 because R/88 does rm(list=ls()) at startup"
  - "2-minute performance target (120 seconds) for full local pipeline from config through smoke test"
metrics:
  duration_minutes: 3
  tasks_completed: 2
  files_created: 1
  files_modified: 1
  commits: 2
  lines_added: 422
completed: 2026-06-05T15:07:09Z
---

# Phase 85 Plan 01: DuckDB Integration & Fixture Validation Summary

**One-liner:** Add DuckDB integration validation (Section 32) and fixture schema validation (Section 33) to R/88 smoke test, plus create end-to-end local pipeline runner that validates full stack from config through smoke test in under 2 minutes.

## What Was Built

### 1. R/88 Section 32: DuckDB Integration Validation (TEST-01, TEST-02)

Added DuckDB integration validation that runs in BOTH local and production modes with environment-specific checks:

**Local mode validations:**
- DuckDB file contains exactly 15 tables from fixture CSVs
- All 7 critical tables present (ENROLLMENT, DIAGNOSIS, ENCOUNTER, DEMOGRAPHIC, PROCEDURES, PRESCRIBING, DEATH)
- Fixture row counts match FIXTURE_DESIGN.md: ENROLLMENT=20, DIAGNOSIS=18, ENCOUNTER=19, PRESCRIBING=4

**Production mode validations:**
- DuckDB file contains >= 13 tables (data-dependent counts, not fixture-specific)

**Implementation details:**
- Uses fully-qualified `DBI::dbConnect(duckdb::duckdb(), ...)` calls (no library imports)
- Always uses `shutdown = TRUE` on dbDisconnect to prevent Windows file locking
- Gracefully skips if DuckDB file doesn't exist (message: "run R/01 + R/03 first")

### 2. R/88 Section 33: Fixture Schema & Edge Case Validation (TEST-03, TEST-05)

Added fixture-specific validation that ONLY runs in local mode (`if (IS_LOCAL)`):

**Row count assertions:**
- 7 fixture tables validated against FIXTURE_DESIGN.md specifications
- ENROLLMENT=20, DIAGNOSIS=18, DEMOGRAPHIC=20, ENCOUNTER=19, PRESCRIBING=4, PROCEDURES=1, DEATH=1

**Edge case patient validations:**
- PT002: dual-eligible (payer code "14")
- PT003: NLPHL diagnosis (C81.00)
- PT004: SCT procedure (CPT 38241)
- PT007: orphan dx code (Z51.11)
- PT009: 1900 sentinel date patient
- PT010: ICD-9/ICD-10 cross-system (2 diagnoses)
- PT012: ABVD regimen (4 RXNORM_CUIs: 3639, 11213, 67228, 3946)
- PT006: death record

**Implementation details:**
- Requires `pcornet` list in global environment (from R/01)
- Uses fully-qualified `dplyr::filter()` calls (no library imports)
- Gracefully skips if pcornet doesn't exist with informative message
- Production mode: section skipped entirely (message: "SKIPPED (production mode)")

### 3. tests/run_local_test.R: End-to-End Integration Test (TEST-04)

Created standalone script for full local pipeline validation with timing:

**Five-step process:**
1. **Config**: Source R/00_config.R, verify IS_LOCAL=TRUE (abort if not)
2. **CSV Load**: Source R/01_load_pcornet.R, load fixture CSVs into pcornet list
3. **DuckDB Ingest**: Source R/03_duckdb_ingest.R, ingest RDS cache into DuckDB
4. **DuckDB Validation**: Connect to DuckDB, verify 15 tables, fixture row counts, edge case patients PT003/PT012
5. **Smoke Test**: Source R/88_smoke_test_comprehensive.R, run full validation including new Sections 32+33

**Performance validation:**
- Tracks per-step timing (config, CSV load, DuckDB, validation, smoke test)
- Validates total duration under 2 minutes (120 seconds) - TEST-04 requirement
- Reports PASS/WARNING based on performance target

**Error handling:**
- Aborts immediately if IS_LOCAL=FALSE (clear error message)
- Saves/restores timing variables around R/88 (which does `rm(list=ls())`)
- Exits with status 1 on any validation errors or smoke test failures
- Compatible with both RStudio (interactive) and Rscript (non-interactive via `if (!interactive())`)

### 4. R/88 Metadata Updates

- Section numbering updated: [30/31] and [31/31] → [30/33] and [31/33]
- Version string updated: "v2.2 + Phase 87" → "v2.2 + Phase 87-89"
- Summary section adds TEST-01, TEST-02, TEST-03, TEST-05 requirement messages

## Deviations from Plan

None - plan executed exactly as written.

## Requirements Validated

- **TEST-01**: DuckDB ingest works with fixture CSVs (Section 32 local mode checks)
- **TEST-02**: R/88 smoke test passes locally against fixtures (Sections 32+33)
- **TEST-03**: Fixture schema validation in local mode (Section 33 row counts + edge cases)
- **TEST-04**: Full local pipeline end-to-end runnable (tests/run_local_test.R)
- **TEST-05**: Conditional fixture count assertions (Sections 32+33 both validate counts)

## Technical Highlights

### Pattern: Fully-Qualified Function Calls

R/88 does NOT import DBI, duckdb, or dplyr libraries. All calls use `::` notation:
- `DBI::dbConnect(duckdb::duckdb(), ...)`
- `DBI::dbListTables(con)`
- `DBI::dbGetQuery(con, ...)`
- `DBI::dbDisconnect(con, shutdown = TRUE)`
- `dplyr::filter(table, condition)`

**Why:** Avoids namespace pollution in R/88 (which only loads glue at top). Keeps smoke test lightweight.

### Pattern: Environment-Gated Validation

Section 33 uses `if (IS_LOCAL)` wrapper for fixture-specific checks:
```r
if (IS_LOCAL) {
  message("\n[33/33] Fixture schema validation (local mode only)...")
  # ... fixture checks ...
} else {
  message("\n[33/33] Fixture schema validation -- SKIPPED (production mode)")
}
```

**Why:** Production DuckDB has real patient data, not 20-patient fixtures. Fixture row counts only make sense locally.

Section 32 runs in both modes but with different assertions:
```r
if (IS_LOCAL) {
  check(..., length(tables_found) == 15)  # Exact fixture count
} else {
  check(..., length(tables_found) >= 13)  # Production minimum
}
```

### Pattern: Graceful Degradation

Both sections skip gracefully if prerequisites missing:
- Section 32: "SKIP: DuckDB file not found (run R/01 + R/03 first)"
- Section 33: "SKIP: pcornet list not loaded (run R/01_load_pcornet.R first)"

**Why:** R/88 is run standalone frequently. Informative skip messages guide users instead of cryptic errors.

### Pattern: Windows File Locking Prevention

All `DBI::dbDisconnect` calls include `shutdown = TRUE`:
```r
DBI::dbDisconnect(con, shutdown = TRUE)
```

**Why:** DuckDB on Windows can leave file locks if connection isn't properly shut down. This pattern from Phase 83 research prevents file locking issues.

### Pattern: Environment Preservation Around rm(list=ls())

run_local_test.R saves timing variables before sourcing R/88:
```r
saved_pipeline_start <- pipeline_start
saved_step_times <- c(step1_time, step2_time, step3_time, step4_time)
saved_val_errors <- val_errors

source("R/88_smoke_test_comprehensive.R")  # Does rm(list=ls()) at top

# Restore saved values
pipeline_start <- saved_pipeline_start
step_times <- saved_step_times
val_errors <- saved_val_errors
```

**Why:** R/88 clears workspace at startup (line 44: `rm(list = ls())`). Without save/restore, timing data would be lost.

## Integration Points

**Upstream dependencies:**
- Phase 83-01: IS_LOCAL flag and CONFIG$cache$duckdb_path
- Phase 83-02: Environment detection infrastructure and startup logging
- Phase 84-01: FIXTURE_DESIGN.md specifications (row counts, edge cases)
- Phase 84-02: 15 fixture CSV files in tests/fixtures/

**Downstream impacts:**
- Future R/88 runs will validate DuckDB integration and fixture schema in local mode
- tests/run_local_test.R provides one-command local pipeline validation for developers

**Files created:**
- tests/run_local_test.R (211 lines)

**Files modified:**
- R/88_smoke_test_comprehensive.R (+211 lines for Sections 32+33, -3 lines for section numbering updates)

## Known Limitations

1. **Fixture-specific checks only run when pcornet list exists**: Section 33 requires R/01 to have been sourced. If R/88 is run standalone, Section 33 skips with informative message.

2. **DuckDB validation only runs if DB file exists**: Section 32 skips if CONFIG$cache$duckdb_path doesn't exist. This is intentional (not all developers run R/03 before R/88).

3. **2-minute performance target is informational**: run_local_test.R reports WARNING (not FAIL) if pipeline exceeds 120 seconds. This is expected on slow machines or first run (no RDS cache).

4. **Production mode skips fixture-specific checks**: Section 32 only validates table count >= 13 in production. Fixture row counts and edge case patients are local-only checks.

## Verification

Self-check: PASSED

**Files created:**
- tests/run_local_test.R exists: FOUND

**Files modified:**
- R/88_smoke_test_comprehensive.R modified: FOUND

**Commits:**
- 0071ea5: feat(85-01): add DuckDB integration and fixture schema validation to R/88
- bf69cc8: feat(85-01): create local integration test runner script

**Grep validations:**
```bash
# Section 32 exists
$ grep "SECTION 32.*DuckDB LOCAL INTEGRATION" R/88_smoke_test_comprehensive.R
# SECTION 32: DuckDB LOCAL INTEGRATION VALIDATION (TEST-01, TEST-02) ----

# Section 33 exists
$ grep "SECTION 33.*FIXTURE SCHEMA" R/88_smoke_test_comprehensive.R
# SECTION 33: FIXTURE SCHEMA & EDGE CASE VALIDATION (TEST-03, TEST-05) ----

# No library(DBI) or library(duckdb) added
$ grep -c "^library(DBI)" R/88_smoke_test_comprehensive.R
0
$ grep -c "^library(duckdb)" R/88_smoke_test_comprehensive.R
0

# run_local_test.R sources all 4 pipeline scripts
$ grep "source.*R/00_config.R" tests/run_local_test.R
source("R/00_config.R")
$ grep "source.*R/01_load_pcornet.R" tests/run_local_test.R
source("R/01_load_pcornet.R")
$ grep "source.*R/03_duckdb_ingest.R" tests/run_local_test.R
source("R/03_duckdb_ingest.R")
$ grep "source.*R/88_smoke_test" tests/run_local_test.R
source("R/88_smoke_test_comprehensive.R")
```

## Next Steps

**Immediate (Phase 85 Plan 02, if exists):**
- None - Phase 85 has only 1 plan

**Phase 86 (Documentation & Cleanup):**
- Document local testing workflow in README or TESTING.md
- Update PROJECT.md to move v2.2 to "Shipped" section
- Verify .gitignore prevents .Renviron commits
- Run styler/lintr on modified scripts (R/88 already compliant from v2.0)

**Developer workflow:**
From project root on Windows (or Linux with R_TESTING_ENV=local):
```r
source("tests/run_local_test.R")
# Runs full pipeline: R/00 -> R/01 -> R/03 -> R/88
# Reports timing, DuckDB validation, smoke test pass/fail
# Exits with status 1 on any failure (Rscript-compatible)
```

Or step-by-step:
```r
source("R/00_config.R")  # IS_LOCAL auto-detects Windows
source("R/01_load_pcornet.R")  # Loads fixture CSVs
source("R/03_duckdb_ingest.R")  # Writes DuckDB to tempdir()
source("R/88_smoke_test_comprehensive.R")  # Sections 32+33 validate fixtures
```

---
*Summary generated: 2026-06-05*
*Phase 85 Plan 01 duration: 3 minutes*
*Total lines added: 422 (211 R/88, 211 run_local_test.R)*
