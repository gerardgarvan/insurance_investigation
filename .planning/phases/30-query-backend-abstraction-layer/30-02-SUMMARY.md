---
phase: 30-query-backend-abstraction-layer
plan: 02
subsystem: data-access-layer
tags: [duckdb, backend-testing, smoke-test, translation-gaps, phase-30]
dependencies:
  requires: [30-01]  # Backend abstraction layer from Plan 01
  provides: [smoke_test_script, translation_gap_documentation]
  affects: [31-01, 31-02]  # Phase 31 cohort migration will use smoke test results
tech_stack:
  added: []
  patterns: [test-driven-validation, parity-testing, error-capture]
key_files:
  created:
    - R/26_smoke_test_backends.R
    - docs/DUCKDB_TRANSLATION_NOTES.md
  modified: []
decisions:
  - Smoke test swaps pcornet$ entries with tbl_dbi objects (predicates access globals)
  - tryCatch wraps predicate calls to capture translation errors gracefully
  - Sample size 100 patients with seed=20260423 for reproducibility
  - Translation notes pre-populated from code analysis (6 known gaps)
  - Smoke test does NOT modify predicates (Phase 31's job)
metrics:
  duration_seconds: 142
  tasks_completed: 2
  commits: 2
  files_created: 2
  tests_added: 0
completed: 2026-04-23
requirements: [DBAPI-04]
---

# Phase 30 Plan 02: Backend Parity Smoke Test — SUMMARY

**One-liner:** Standalone smoke test script validating 6 named predicates on RDS and DuckDB backends with 100-patient sample, plus pre-populated translation gap documentation for Phase 31 refactoring

## What Was Built

### 1. Smoke Test Script (R/26_smoke_test_backends.R)

A complete standalone script that tests all 6 named predicates from 03_cohort_predicates.R on both RDS and DuckDB backends, comparing PATID set equality for each.

**Script structure:**

1. **Sample creation (D-07):** Randomly selects 100 patients from DEMOGRAPHIC using seed=20260423 for reproducibility
2. **RDS baseline:** Runs all 6 predicates on in-memory tibbles, collects PATID sets
3. **DuckDB testing:** Opens connection, swaps pcornet$ entries with tbl_dbi objects, runs predicates with tryCatch
4. **Comparison:** Uses setequal() for pass/fail per predicate, setdiff() for detailed mismatch reporting
5. **Cleanup:** Restores original pcornet$ list, closes DuckDB connection
6. **Summary:** Reports N/6 passed, lists translation errors if any

**Predicates tested (D-06):**

- `has_hodgkin_diagnosis()` — Filter predicate using is_hl_diagnosis() and is_hl_histology()
- `with_enrollment_period()` — Filter predicate using semi_join on ENROLLMENT
- `exclude_missing_payer()` — Filter predicate using semi_join on payer_summary
- `has_chemo()` — Treatment detector querying 7 sources with if_any()
- `has_radiation()` — Treatment detector querying 4 sources with if_any()
- `has_sct()` — Treatment detector querying 4 sources with if_any()

**Key design decisions:**

- **Global pcornet$ swap:** Predicates access `pcornet$TABLE_NAME` directly (not via get_pcornet_table()). Smoke test temporarily replaces pcornet$ entries with tbl_dbi objects to test parity without modifying predicates.
- **tryCatch wrapper:** Custom `run_predicate_safe()` function captures translation errors gracefully, logs error messages, and returns empty character vector on failure.
- **Treatment detectors test full table:** has_chemo(), has_radiation(), has_sct() take no arguments and return all patients with treatment evidence (not filtered to 100-patient sample).
- **payer_summary available:** 02_harmonize_payer.R is sourced, so payer_summary tibble exists for exclude_missing_payer().

### 2. Translation Gap Documentation (docs/DUCKDB_TRANSLATION_NOTES.md)

Pre-populated documentation of 6 known dbplyr translation gaps identified from code analysis.

**Gaps documented:**

1. **Custom R functions in filter():** is_hl_diagnosis() and is_hl_histology() cannot translate to SQL
2. **is_hl_histology() str_extract():** First 4-digit extraction may not translate cleanly
3. **if_any() with tidyselect:** Dynamic column selection via all_of() may fail in SQL translation
4. **str_detect() with complex regex:** Dynamically constructed patterns may not map to SQL LIKE/REGEXP
5. **semi_join() performance:** DuckDB SEMI JOIN may be slower than INNER JOIN + distinct()
6. **TUMOR_REGISTRY_ALL VIEW column mismatch:** TR1 has ~314 columns, TR2/TR3 have ~140 columns (UNION ALL may require column count match or UNION ALL BY NAME)

**Structure:**

- Overview section categorizes gaps (Translation Errors, Result Differences, Performance Concerns)
- Per-gap sections include: affected predicates, issue description, Phase 31 workaround
- Placeholder table for HiPerGator smoke test results (to be filled in after running script)
- Phase 31 refactoring recommendations (5 items)
- References to dbplyr and DuckDB documentation

## Deviations from Plan

None — plan executed exactly as written.

## Key Decisions

### 1. Smoke test swaps pcornet$ entries (not predicates)

**Context:** Predicates in 03_cohort_predicates.R access `pcornet$TABLE_NAME` directly as globals. They do NOT call get_pcornet_table().

**Decision:** Smoke test temporarily replaces pcornet$ list entries with tbl_dbi objects from DuckDB, runs predicates, then restores original tibbles.

**Rationale:** Phase 30's goal is to test data equivalence, not refactor predicates. Phase 31 will migrate predicates to use get_pcornet_table(). This approach validates that DuckDB ingestion is correct without changing existing predicate code.

### 2. tryCatch wraps all predicate calls

**Context:** Custom R functions (is_hl_diagnosis, is_hl_histology, if_any) may not translate to SQL.

**Decision:** Wrap each predicate call in `run_predicate_safe()` which uses tryCatch to capture errors, log messages, and return empty character vector on failure.

**Rationale:** Allows smoke test to complete even if some predicates fail. Translation errors are logged for documentation in DUCKDB_TRANSLATION_NOTES.md. Phase 31 can address gaps systematically.

### 3. Sample size 100 patients with seed=20260423

**Context:** Plan specified 100-patient sample (D-07) for smoke test.

**Decision:** Use set.seed(20260423) and slice_sample(n = 100) on DEMOGRAPHIC$ID.

**Rationale:** Reproducibility. Same seed will select same 100 patients across multiple runs. Date-based seed (April 23, 2026) documents when test was created.

### 4. Translation notes pre-populated from code analysis

**Context:** Plan specified pre-populating known gaps before running smoke test on HiPerGator.

**Decision:** Document 6 gaps identified from reading 03_cohort_predicates.R and utils_icd.R source code. Include placeholder table for actual test results.

**Rationale:** Provides Phase 31 with immediate visibility into expected issues. Smoke test will confirm or refine these predictions. Pre-population saves round-trip time (no need to run test before knowing what to expect).

### 5. Treatment detectors test full table (not 100-patient sample)

**Context:** has_chemo(), has_radiation(), has_sct() take no arguments and return all patients with treatment evidence.

**Decision:** Smoke test calls these predicates without filtering to 100-patient sample. They query the full pcornet tables.

**Rationale:** Predicates have no `patient_df` argument to filter on. Testing them on full table validates translation of treatment detection logic across all patients, not just sample. More comprehensive test.

## Implementation Notes

### Smoke Test Console Output

Script produces structured console output with:
- Sample info (size, seed, first 5 IDs)
- Phase 1 header (RDS baseline) with per-predicate patient counts
- Phase 2 header (DuckDB testing) with translation error messages if any
- Results section with per-predicate PASS/FAIL, counts, and setdiff details on failures
- Summary section with N/6 passed, N errors, and action message

Example output format:
```
==================================================
SMOKE TEST: Backend Parity (RDS vs DuckDB)
==================================================

Sample: 100 patients (seed=20260423)
Sample IDs (first 5): 1234, 5678, 9012, 3456, 7890

--------------------------------------------------
Phase 1: Running predicates on RDS backend...
--------------------------------------------------

RDS baseline counts:
  has_hodgkin_diagnosis: 42 patients
  with_enrollment_period: 95 patients
  exclude_missing_payer: 87 patients
  has_chemo: 123 patients
  has_radiation: 89 patients
  has_sct: 12 patients

--------------------------------------------------
Phase 2: Running predicates on DuckDB backend...
--------------------------------------------------

[DuckDB messages...]

==================================================
RESULTS: PATID Set Equality
==================================================

  [PASS] has_hodgkin_diagnosis
    RDS: 42 patients, DuckDB: 42 patients

  [FAIL] has_chemo
    RDS: 123 patients, DuckDB: 115 patients
    In RDS only (8): 1234, 5678, ...

==================================================
SUMMARY: 5/6 predicates passed PATID set equality
         1 translation errors encountered

Translation gaps found:
  - has_chemo: dbplyr cannot translate if_any(...)

Action: Document gaps in docs/DUCKDB_TRANSLATION_NOTES.md
Phase 31 may need to refactor predicates for full SQL translation.
==================================================

[Smoke test complete]
```

### Translation Notes Structure

File organized in sections:
1. Frontmatter (phase, created date, status)
2. Overview (3 gap categories)
3. Known Translation Gaps (6 subsections with workarounds)
4. Smoke Test Results (placeholder tables — to be filled in after HiPerGator run)
5. Phase 31 Refactoring Recommendations (5 items)
6. References (3 links to dbplyr/DuckDB docs)

Each gap subsection includes:
- Affected predicates
- Issue description (what fails, why)
- Workaround code example for Phase 31

### Error Handling

**Smoke test:**
- Stops if DuckDB file not found (duckdb_path does not exist)
- Warns if table not found in DuckDB (keeps RDS tibble)
- tryCatch logs error messages and continues to next predicate
- Restores pcornet$ list even if DuckDB testing fails mid-run

**Translation notes:**
- Placeholder tables for results (prevents stale data if script not run)
- Clear status marker at top ("Pre-populated from code analysis. Update after running...")

## Testing Strategy (Deferred to HiPerGator)

This plan creates the smoke test script and documentation. Actual testing will occur on HiPerGator in Phase 30 or early Phase 31:

1. Run `source("R/26_smoke_test_backends.R")` interactively in RStudio on HiPerGator
2. Copy console output to docs/DUCKDB_TRANSLATION_NOTES.md "Smoke Test Results" section
3. Update predicate results table with actual counts and pass/fail status
4. Document any translation errors encountered
5. Note performance observations (if any queries are significantly slower)
6. Use results to prioritize Phase 31 refactoring work

## Known Stubs

None. Both artifacts are fully implemented:
- Smoke test script has complete logic for all 6 predicates with comparison and error handling
- Translation notes document all 6 gaps with workarounds and references

## Completion Checklist

- [x] Task 1 executed: R/26_smoke_test_backends.R created (4dcee53)
- [x] Task 2 executed: docs/DUCKDB_TRANSLATION_NOTES.md created (4de7619)
- [x] Both tasks committed individually
- [x] No deviations from plan
- [x] SUMMARY.md created
- [x] Self-check performed (see below)

## Self-Check: PASSED

All claimed artifacts verified to exist:

**R/26_smoke_test_backends.R:**
- File exists ✓
- Contains all 6 predicate names (31 references total) ✓
- Uses set.seed(20260423) and sample size 100 ✓
- Sources 00_config.R, 01_load_pcornet.R, 02_harmonize_payer.R, 03_cohort_predicates.R ✓
- Calls open_pcornet_con() and close_pcornet_con() ✓
- Swaps pcornet$ entries with tbl_dbi objects ✓
- Uses run_predicate_safe() with tryCatch ✓
- Uses setequal() for comparison ✓
- Prints per-predicate PASS/FAIL ✓
- Prints summary with N/6 passed ✓
- Restores pcornet_rds_backup ✓

**docs/DUCKDB_TRANSLATION_NOTES.md:**
- File exists ✓
- Contains "Translation" keyword (5 occurrences) ✓
- Documents 6 known gaps ✓
- Mentions is_hl_diagnosis(), is_hl_histology(), if_any(), str_detect(), semi_join() ✓
- Includes TUMOR_REGISTRY_ALL UNION ALL column mismatch concern ✓
- Has placeholder table for smoke test results ✓
- Has "Phase 31 Refactoring Recommendations" section ✓
- Has References section with dbplyr and DuckDB links ✓

**Commits:**
- 4dcee53 (Task 1: smoke test script) ✓
- 4de7619 (Task 2: translation notes) ✓

All commits exist:
```bash
$ git log --oneline -2
4de7619 docs(30-02): add DuckDB translation notes with known gaps
4dcee53 feat(30-02): add smoke test script for backend parity testing
```

All claimed files exist:
```bash
$ ls -1 R/26_smoke_test_backends.R docs/DUCKDB_TRANSLATION_NOTES.md
R/26_smoke_test_backends.R
docs/DUCKDB_TRANSLATION_NOTES.md
```
