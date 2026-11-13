---
phase: quick
plan: 261113-hap
subsystem: test-suite
tags: [test-fix, canonicalize, source-local, codeset-summary]
key-files:
  modified:
    - tests/testthat/test-160-diagnostic-and-eligibility.R
    - R/00_config.R
    - tests/testthat/test-169-single-source-care.R
    - tests/testthat/test_autoimmune_flags.R
decisions: []
metrics:
  completed: 2026-11-13
  tasks: 3
  files: 4
---

# Quick Task 261113-hap Summary

Three independent test failures fixed; test suite restored to green.

## Fixes

**Fix A — test-160 codeset summary (test-160-diagnostic-and-eligibility.R)**

- Added `code_system = ""` to the `rule()` helper and to the inline `cs2` tibble so the fixture satisfies `build_codeset_summary()`'s `group_by(code_system)`.
- Corrected the test assertions: `build_codeset_summary()` returns a flat tibble (not a list with `$by_modality`/`$by_analyte` slots); switched to `dplyr::filter(sm2, row_type == "code/analyte")`.
- Added `as.integer()` casts for `n_codes`/`n_codes_present` comparisons because the flat tibble stores counts as character.

**Fix B — canonicalize_drug_name named-vector leak (R/00_config.R, line 3017)**

Changed:
```r
out <- ifelse(!is.na(hit), unname(hit), x)
```
to:
```r
out <- unname(ifelse(!is.na(hit), unname(hit), x))
```
`ifelse()` inherits names from `!is.na(hit)` (a named logical); the outer `unname()` strips them. Test 164 skips locally because `R/00_config.R` cannot be sourced without HiPerGator data — verify on HiPerGator.

**Fix C — local=FALSE in two source() calls**

Changed `local = new.env(parent = globalenv())` to `local = FALSE` in `test-169-single-source-care.R` (line 13) and `test_autoimmune_flags.R` (line 12). Top-level assignments from the sourced file now land in `globalenv()` and are visible to test code.

## Results

| Filter | Outcome |
|--------|---------|
| `tools/rcheck.sh test 160` | 0 failures, 3 skips (writexl not installed — expected) |
| `tools/rcheck.sh test 164` | skip (env-only: R/00_config.R needs HiPerGator data) — verify on HiPerGator |
| `tools/rcheck.sh test 169` | 0 failures |
| `tools/rcheck.sh test autoimmune` | 0 failures |

## Deviations from Plan

**Fix A required two additional sub-fixes beyond adding `code_system`:**

1. The test accessed `sm2$by_modality` and `sm2$by_analyte` which don't exist — `build_codeset_summary()` returns a flat tibble. Fixed by filtering on `row_type` instead.
2. `n_codes`/`n_codes_present` are stored as character in the flat tibble. Fixed by wrapping comparisons in `as.integer()`.

No tests were weakened or deleted. The assertions check the same logic, just via the actual return structure.

## Commit

`aee6c84` — fix(261113-hap): restore green test suite — three independent failures
