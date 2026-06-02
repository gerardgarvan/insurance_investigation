# HiPerGator Validation Checklist for REORG-05

**Purpose:** Full smoke test validation with PCORnet data (deferred from Phase 68 per D-03)
**Created:** 2026-06-01
**Status:** Pending execution on HiPerGator
**Target Phase for Execution:** Phase 74 (Smoke Testing & Reference Manual)

## Prerequisites

- [ ] SSH to HiPerGator
- [ ] `module load R/4.4.2`
- [ ] Navigate to project directory
- [ ] Verify `renv.lock` in sync: `Rscript -e 'renv::status()'`

## Validation Steps

### 1. Full Smoke Test Execution
- [ ] Run: `Rscript R/87_smoke_test_full_pipeline.R`
- [ ] Expected: All 12 test categories PASS
- [ ] Expected: Zero broken source() references
- [ ] Expected: Zero missing decade files
- [ ] Expected: Cancer decade passes with 14/14 scripts found

### 2. Foundation Smoke Test
- [ ] Run: `Rscript R/86_smoke_test_foundation.R`
- [ ] Expected: All foundation checks PASS (config, utils auto-sourcing, data loading)

### 3. Backend Parity Tests
- [ ] Run: `Rscript R/80_smoke_test_backends.R`
- [ ] Expected: RDS vs DuckDB parity for 6 predicates on 100-patient sample
- [ ] Run: `Rscript R/81_parity_test_cohort.R`
- [ ] Expected: Full cohort build parity (RDS vs DuckDB via waldo::compare)

### 4. RDS Dependency Checks
- [ ] Verify cache/ directory exists and has RDS artifacts
- [ ] Run: `ls cache/*.rds | wc -l` (expect ~25+ artifacts)
- [ ] Spot-check: `Rscript -e 'x <- readRDS("cache/pcornet.rds"); cat(names(x), sep="\n")'`
- [ ] Expected: 13 PCORnet table names listed without error

### 5. Config and Utils Integration
- [ ] Run: `Rscript -e 'source("R/00_config.R"); cat("Utils loaded:", length(ls(pattern="^utils_")), "\n")'`
- [ ] Expected: 8 utils modules auto-sourced successfully
- [ ] Verify: All utility functions available in environment

### 6. Source() Runtime Resolution
- [ ] Run: `Rscript -e 'source("R/14_build_cohort.R")'` (sources 5 dependencies)
- [ ] Expected: No "file not found" errors for source() calls
- [ ] This tests the deepest dependency chain: 00_config -> 01_load -> 02_harmonize -> 10-13 -> 14_build_cohort

## Completion Criteria

- All checkboxes ticked
- Zero test failures across all smoke tests
- Zero broken source() references at runtime
- Update `.planning/phases/68-output-test-reorganization/68-VERIFICATION-SCAN.md` with HiPerGator results
- Mark REORG-05 as fully complete in REQUIREMENTS.md

## Estimated Time

15-20 minutes on HiPerGator with cached data (RDS + DuckDB already built)

## Notes

- Per D-01: Local Windows structural checks (file existence, source() parsing, numbering) already completed in Phase 68 Plan 01
- Per D-03: Phase 68 closes without requiring HiPerGator execution -- this checklist is the deliverable
- Phase 74 (Smoke Testing & Reference Manual) will execute this checklist as part of comprehensive testing
