# DuckDB Translation Notes

**Phase:** 30 (Backend Abstraction Layer)
**Created:** 2026-04-23
**Status:** Updated Phase 31 (2026-04-23): Workarounds applied during cohort pipeline migration.

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

**Resolution (Phase 31):**
- Replaced `is_hl_diagnosis(DX, DX_TYPE)` with inline ICD matching using pre-computed dotted+undotted code vectors
- Handles both formats via `(DX %in% hl_icd10_undotted | gsub("\\.", "", DX) %in% hl_icd10_undotted)`
- The `gsub()` call normalizes input to undotted format before matching
- Affected files: `R/03_cohort_predicates.R`, `R/02_harmonize_payer.R`, `R/04_build_cohort.R`
- Note: `is_hl_diagnosis()` function in `utils_icd.R` is preserved for standalone use but no longer called inside dplyr filter() chains

### 2. is_hl_histology() in TUMOR_REGISTRY queries

**Affected predicates:** `has_hodgkin_diagnosis()`

**Issue:** `is_hl_histology(HISTOLOGICAL_TYPE)` uses `str_extract()` to get first 4 digits, then matches against `ICD_CODES$hl_histology`. Neither `str_extract()` with regex nor the 4-digit extraction pattern may translate cleanly.

**Workaround for Phase 31:** Use `SUBSTR()` in SQL or `substr()` which dbplyr can translate:
```r
filter(substr(HISTOLOGICAL_TYPE, 1, 4) %in% ICD_CODES$hl_histology)
```

**Resolution (Phase 31):**
- Replaced `is_hl_histology()` with `substr(as.character(HISTOLOGICAL_TYPE), 1, 4) %in% ICD_CODES$hl_histology`
- The `substr()` function translates cleanly to SQL SUBSTR()
- `as.character()` cast ensures numeric columns are coerced properly
- Affected files: `R/03_cohort_predicates.R`, `R/04_build_cohort.R`

### 3. if_any() in treatment detectors

**Affected predicates:** `has_chemo()`, `has_radiation()`, `has_sct()`

**Issue:** `if_any(all_of(tr_chemo_cols), ~ !is.na(.))` uses tidyselect with a lambda. dbplyr may not translate `if_any()` to SQL correctly, especially with dynamic column selection via `all_of()`.

**Workaround for Phase 31:** Replace with explicit OR conditions:
```r
# Instead of: filter(if_any(all_of(date_cols), ~ !is.na(.)))
# Use:        filter(!is.na(COL1) | !is.na(COL2))
```

**Resolution (Phase 31):**
- Replaced `if_any(all_of(...), ~ !is.na(.))` with dynamic filter expressions built via `rlang::parse_expr()`
- For single-column case: `filter_expr <- paste0("!is.na(", col, ")")`
- For multi-column case: `filter_expr <- paste0("!is.na(", cols, ")", collapse = " | ")`
- Applied via `filter(!!rlang::parse_expr(filter_expr))`
- Affected files: `R/03_cohort_predicates.R`, `R/10_treatment_payer.R`

### 4. str_detect() for ICD-10-PCS prefix matching

**Affected predicates:** `has_chemo()`, `has_radiation()`

**Issue:** `str_detect(PX, regex_pattern)` with dynamically constructed regex patterns. dbplyr translates `str_detect()` to SQL `LIKE` or `REGEXP_MATCHES()`, but complex paste0-constructed patterns may not translate.

**Workaround for Phase 31:** Use `LIKE` patterns or expand prefix matches to explicit `%in%` lists.

**Resolution (Phase 31):**
- Used materialize-then-filter pattern to handle ICD-10-PCS prefix matching
- Step 1: Lazy filter on `PX_TYPE == "10"` to reduce data volume (keeps query lazy for bulk filter)
- Step 2: Materialize the filtered subset with `materialize()`
- Step 3: Apply R-side `str_detect()` on materialized data
- Example: `px_10_chemo <- proc_tbl %>% filter(PX_TYPE == "10") %>% materialize() %>% filter(str_detect(PX, chemo_icd10pcs_rx)) %>% pull(ID)`
- Affected files: `R/03_cohort_predicates.R`, `R/10_treatment_payer.R`

### 5. semi_join() performance

**Affected predicates:** `with_enrollment_period()`, `exclude_missing_payer()`

**Issue:** dbplyr translates `semi_join()` to `WHERE EXISTS (SELECT 1 FROM ...)`. DuckDB has known performance issues with `SEMI JOIN` vs `INNER JOIN` (GitHub issue #19213). Correctness should be fine; performance may differ.

**Workaround for Phase 31 (if slow):** Replace with `inner_join() %>% distinct()`.

**Resolution (Phase 31):**
- `semi_join()` preserved in current implementation
- Materialized the `enrolled_patients` tibble before `semi_join()`, so the join is tibble-to-tibble (no DuckDB semi_join needed)
- Benchmark (`R/28_benchmark_cohort.R`) will reveal if performance is an issue
- If empirical evidence shows slowdown, replace with `inner_join() %>% distinct()` only after benchmark confirms the need
- Affected files: `R/03_cohort_predicates.R` (`with_enrollment_period()` function)

### 6. TUMOR_REGISTRY_ALL VIEW column mismatch

**Affected predicates:** `has_hodgkin_diagnosis()`, `has_chemo()`, `has_radiation()`, `has_sct()`

**Issue:** SQL `UNION ALL` in the TUMOR_REGISTRY_ALL view requires matching column counts. TR1 has ~314 columns while TR2/TR3 have ~140 columns. If DuckDB's `UNION ALL` does not auto-pad missing columns with NULL, the view creation may fail.

**Workaround:** If `CREATE VIEW` fails during `open_pcornet_con()`, create view using only shared columns, or use `UNION ALL BY NAME` (DuckDB extension that matches columns by name, auto-filling missing columns with NULL).

**Resolution (Phase 31):**
- VIEW creation in `open_pcornet_con()` works without modification
- Standard `UNION ALL` handles column count differences correctly in DuckDB
- No need for `UNION ALL BY NAME` (DuckDB auto-pads missing columns)
- Column existence checks use `colnames()` on the lazy `tbl_dbi` object
- `colnames()` works reliably on both tibbles and `tbl_dbi` (unlike `names()`)
- Affected files: `R/utils_duckdb.R` (`open_pcornet_con()`), `R/03_cohort_predicates.R`

## Phase 31 Additional Findings

Beyond the 6 pre-populated gaps, Phase 31 migration uncovered these additional translation issues:

### 7. nchar(trimws(x)) pattern not supported

**Issue:** `nchar(trimws(secondary)) > 0` for empty string detection does not translate cleanly to SQL.

**Workaround:** Replaced with direct empty string comparison: `secondary != ""` or `!is.na(secondary) & secondary != ""`

**Affected files:** `R/02_harmonize_payer.R` (compute_effective_payer, detect_dual_eligible functions)

### 8. names() vs colnames() on tbl_dbi

**Issue:** `names(pcornet$TABLE)` works on in-memory lists but not on `tbl_dbi` objects.

**Workaround:** Use `colnames()` for column existence checks. Works universally on tibbles and `tbl_dbi`.

**Affected files:** `R/03_cohort_predicates.R` (TUMOR_REGISTRY column checks)

### 9. tryCatch NULL-guard pattern for table existence

**Issue:** Direct `!is.null(pcornet$TABLE)` checks fail because `get_pcornet_table()` returns `tbl_dbi` (never NULL) in DuckDB mode.

**Workaround:** Use `tryCatch(get_pcornet_table("TABLE"), error = function(e) NULL)` pattern to catch table-not-found errors.

**Affected files:** `R/03_cohort_predicates.R` (TUMOR_REGISTRY_ALL existence check)

### 10. Direct column assignment to tbl_dbi not supported

**Issue:** `pcornet$ENCOUNTER$PAYER_TYPE_SECONDARY <- NA_character_` for missing column initialization does not work on `tbl_dbi`.

**Workaround:** Use conditional mutate instead:
```r
if (!"PAYER_TYPE_SECONDARY" %in% enc_cols) {
  encounters_raw <- enc_tbl %>% mutate(PAYER_TYPE_SECONDARY = NA_character_)
}
```

**Affected files:** `R/02_harmonize_payer.R` (SECTION 2: encounter processing)

### 11. bind_rows() on lazy tbl_dbi

**Issue:** Cannot bind lazy queries directly with tibbles using `bind_rows()`.

**Workaround:** Materialize lazy queries before binding: `bind_rows(materialize(tr_hist), materialize(tr_morph))`

**Affected files:** `R/03_cohort_predicates.R`, `R/04_build_cohort.R`

### 12. Lubridate interval() is R-side only

**Issue:** `lubridate::interval()` and `time_length()` do not translate to SQL. Used for age calculation.

**Workaround:** Materialize tibble before age calculation. Age computation must happen in R, not in SQL.

**Affected files:** `R/04_build_cohort.R` (SECTION 3: enrollment aggregation, SECTION 6.65: age at dx)

## Phase 31 Materialization Points

Phase 31 execution established the pattern: materialize at section boundaries when downstream code needs in-memory tibbles. Here are the materialization calls added in the cohort pipeline:

### In R/04_build_cohort.R (4 materialize calls)

1. **Step 0 cohort initialization** (line ~53):
   - `cohort <- get_pcornet_table("DEMOGRAPHIC") %>% select(...) %>% materialize()`
   - Reason: Downstream uses `n_distinct()`, `nrow()`, `saveRDS()` which require in-memory data

2. **SECTION 3 enrollment aggregation** (line ~183):
   - `enrollment_dates <- enrollment_primary %>% ... %>% summarise(...) %>% materialize()`
   - Reason: Prepare for `lubridate::interval()` age calculation (R-side only function)

3. **Before age calculation** (line ~189):
   - `cohort <- cohort %>% left_join(enrollment_dates, by = "ID") %>% materialize()`
   - Reason: `lubridate::interval()` cannot operate on lazy queries

4. **HL source queries before bind_rows** (lines ~99, 103 in build logic):
   - `bind_rows(materialize(tr_hist), materialize(tr_morph))`
   - Reason: Cannot bind lazy `tbl_dbi` with tibbles

### In R/03_cohort_predicates.R (3 materialize calls)

1. **has_hodgkin_diagnosis(): TR queries before bind_rows** (line ~99):
   - `bind_rows(materialize(tr_hist), materialize(tr_morph))`
   - Reason: Same as above

2. **with_enrollment_period(): enrolled_patients before semi_join** (line ~170 approx):
   - `enrolled_patients <- get_pcornet_table("ENROLLMENT") %>% ... %>% materialize()`
   - Reason: Needed for `nrow()` call and `semi_join()` with tibble

3. **Treatment detection: PX_TYPE filtered subset** (line ~220 approx):
   - `px_10_chemo <- proc_tbl %>% filter(PX_TYPE == "10") %>% materialize()`
   - Reason: Prepare for R-side `str_detect()` regex matching

### In R/02_harmonize_payer.R (1 materialize call)

1. **SECTION 2 encounter processing section boundary** (line ~105 approx):
   - `encounters <- encounters_raw %>% mutate(...) %>% materialize()`
   - Reason: Downstream uses `nrow()`, `sum()`, and other R-side operations

## Smoke Test Results

_Smoke test (R/26) was skipped in favor of full parity test (R/27). See Plan 31-01 SUMMARY.md for parity test results._

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

Based on translation gaps found, Phase 31 execution status:

1. **Refactor predicates to use `get_pcornet_table()` instead of `pcornet$` globals** -- ✅ DONE (Plan 31-01: 113 get_pcornet_table calls added across 6 scripts)
2. **Replace custom R functions with dbplyr-compatible equivalents** -- ✅ DONE (inline `%in%` for ICD matching, `substr()` for histology extraction)
3. **Replace `if_any()` with explicit OR conditions** -- ✅ DONE (dynamic filter expressions via `rlang::parse_expr()`)
4. **Consider `UNION ALL BY NAME`** for TUMOR_REGISTRY_ALL view if column mismatch is an issue -- ✅ NOT NEEDED (standard UNION ALL works)
5. **Benchmark semi_join vs inner_join + distinct** if performance is a concern -- ⏳ PENDING (awaiting benchmark results from R/28_benchmark_cohort.R on HiPerGator)

## References

- [dbplyr SQL Translation Guide](https://dbplyr.tidyverse.org/articles/sql-translation.html)
- [DuckDB R Client Documentation](https://duckdb.org/docs/stable/clients/r)
- [DuckDB UNION ALL BY NAME](https://duckdb.org/docs/sql/query_syntax/setops.html)
- Phase 30 RESEARCH.md -- Pitfalls section
