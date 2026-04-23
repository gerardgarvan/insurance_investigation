# DuckDB Translation Notes

**Phase:** 30 (Backend Abstraction Layer)
**Created:** 2026-04-23
**Status:** Pre-populated from code analysis. Update after running R/26_smoke_test_backends.R on HiPerGator.

## Overview

This document tracks dbplyr SQL translation gaps found when running the PCORnet pipeline's named predicates on the DuckDB backend. Gaps fall into three categories:

1. **Translation Errors** -- R functions that dbplyr cannot translate to SQL (script errors)
2. **Result Differences** -- Queries that run but produce different PATID sets (semantic differences)
3. **Performance Concerns** -- Queries that work correctly but are significantly slower on DuckDB

## Known Translation Gaps (from code analysis)

### 1. Custom R Functions in filter()

**Affected predicates:** `has_hodgkin_diagnosis()`

**Issue:** The predicate calls `is_hl_diagnosis(DX, DX_TYPE)` inside `filter()`. This is a custom R function defined in `utils_icd.R` that:
- Calls `normalize_icd()` (removes dots from ICD codes via `str_remove_all`)
- Performs vectorized matching against `ICD_CODES$hl_icd10` and `ICD_CODES$hl_icd9`
- Returns a logical vector

dbplyr cannot translate custom R functions to SQL. It may attempt local fallback (fetching data to R, then filtering), which defeats lazy evaluation.

**Workaround for Phase 31:** Refactor to inline dplyr operations:
```r
# Instead of: filter(is_hl_diagnosis(DX, DX_TYPE))
# Use:        filter((DX_TYPE == "10" & DX %in% ICD_CODES$hl_icd10) |
#                    (DX_TYPE == "09" & DX %in% ICD_CODES$hl_icd9))
```
Note: This requires handling dot normalization. DuckDB's `REPLACE()` function can strip dots in SQL: `REPLACE(DX, '.', '')`.

### 2. is_hl_histology() in TUMOR_REGISTRY queries

**Affected predicates:** `has_hodgkin_diagnosis()`

**Issue:** `is_hl_histology(HISTOLOGICAL_TYPE)` uses `str_extract()` to get first 4 digits, then matches against `ICD_CODES$hl_histology`. Neither `str_extract()` with regex nor the 4-digit extraction pattern may translate cleanly.

**Workaround for Phase 31:** Use `SUBSTR()` in SQL or `substr()` which dbplyr can translate:
```r
filter(substr(HISTOLOGICAL_TYPE, 1, 4) %in% ICD_CODES$hl_histology)
```

### 3. if_any() in treatment detectors

**Affected predicates:** `has_chemo()`, `has_radiation()`, `has_sct()`

**Issue:** `if_any(all_of(tr_chemo_cols), ~ !is.na(.))` uses tidyselect with a lambda. dbplyr may not translate `if_any()` to SQL correctly, especially with dynamic column selection via `all_of()`.

**Workaround for Phase 31:** Replace with explicit OR conditions:
```r
# Instead of: filter(if_any(all_of(date_cols), ~ !is.na(.)))
# Use:        filter(!is.na(COL1) | !is.na(COL2))
```

### 4. str_detect() for ICD-10-PCS prefix matching

**Affected predicates:** `has_chemo()`, `has_radiation()`

**Issue:** `str_detect(PX, regex_pattern)` with dynamically constructed regex patterns. dbplyr translates `str_detect()` to SQL `LIKE` or `REGEXP_MATCHES()`, but complex paste0-constructed patterns may not translate.

**Workaround for Phase 31:** Use `LIKE` patterns or expand prefix matches to explicit `%in%` lists.

### 5. semi_join() performance

**Affected predicates:** `with_enrollment_period()`, `exclude_missing_payer()`

**Issue:** dbplyr translates `semi_join()` to `WHERE EXISTS (SELECT 1 FROM ...)`. DuckDB has known performance issues with `SEMI JOIN` vs `INNER JOIN` (GitHub issue #19213). Correctness should be fine; performance may differ.

**Workaround for Phase 31 (if slow):** Replace with `inner_join() %>% distinct()`.

### 6. TUMOR_REGISTRY_ALL VIEW column mismatch

**Affected predicates:** `has_hodgkin_diagnosis()`, `has_chemo()`, `has_radiation()`, `has_sct()`

**Issue:** SQL `UNION ALL` in the TUMOR_REGISTRY_ALL view requires matching column counts. TR1 has ~314 columns while TR2/TR3 have ~140 columns. If DuckDB's `UNION ALL` does not auto-pad missing columns with NULL, the view creation may fail.

**Workaround:** If `CREATE VIEW` fails during `open_pcornet_con()`, create view using only shared columns, or use `UNION ALL BY NAME` (DuckDB extension that matches columns by name, auto-filling missing columns with NULL).

## Smoke Test Results

_Run `source("R/26_smoke_test_backends.R")` on HiPerGator and paste results below._

### Predicate Results

| Predicate | RDS Count | DuckDB Count | PATID Match | Notes |
|-----------|-----------|-------------|-------------|-------|
| has_hodgkin_diagnosis | - | - | - | _pending_ |
| with_enrollment_period | - | - | - | _pending_ |
| exclude_missing_payer | - | - | - | _pending_ |
| has_chemo | - | - | - | _pending_ |
| has_radiation | - | - | - | _pending_ |
| has_sct | - | - | - | _pending_ |

### Translation Errors Encountered

_List any errors from tryCatch during smoke test._

### Performance Observations

_Note any significant timing differences._

## Phase 31 Refactoring Recommendations

Based on translation gaps found, Phase 31 should:

1. **Refactor predicates to use `get_pcornet_table()` instead of `pcornet$` globals** -- enables true lazy evaluation benefit
2. **Replace custom R functions with dbplyr-compatible equivalents** -- inline `%in%` for ICD matching, `substr()` for histology extraction
3. **Replace `if_any()` with explicit OR conditions** -- ensures SQL translation
4. **Consider `UNION ALL BY NAME`** for TUMOR_REGISTRY_ALL view if column mismatch is an issue
5. **Benchmark semi_join vs inner_join + distinct** if performance is a concern

## References

- [dbplyr SQL Translation Guide](https://dbplyr.tidyverse.org/articles/sql-translation.html)
- [DuckDB R Client Documentation](https://duckdb.org/docs/stable/clients/r)
- [DuckDB UNION ALL BY NAME](https://duckdb.org/docs/sql/query_syntax/setops.html)
- Phase 30 RESEARCH.md -- Pitfalls section
