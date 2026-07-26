---
status: awaiting_human_verify
trigger: "R/14_build_cohort.R fails on HiPerGator with Catalog Error: Scalar Function with name min_or_na does not exist"
created: 2026-07-25T00:00:00Z
updated: 2026-07-25T00:00:00Z
---

## Current Focus

hypothesis: min_or_na() and is_cancer_code() are pure R functions that cannot be translated to SQL by dbplyr. In R/14, enrollment_primary is a lazy tbl_dbi that flows directly into summarise(min_or_na(...)) without a collect() call first — DuckDB tries to execute min_or_na as a SQL scalar UDF and fails. Same issue in R/46 with is_cancer_code() on a lazy DuckDB pipeline.
test: Confirmed by tracing the data flow: enrollment_primary is built from get_pcornet_table("ENROLLMENT") inner_join(...) with no collect() before summarise(min_or_na(...)) at line 268. R/13 and R/11 always collect() before calling min_or_na() on their data.
expecting: Fix = insert collect() before the summarise() in R/14, and in R/46 replace the lazy-path is_cancer_code() call with a collect()-first approach.
next_action: Apply fix to R/14 (collect before summarise) and R/46 (collect before is_cancer_code filter)

## Symptoms

expected: R/14_build_cohort.R completes enrollment aggregation successfully using min_or_na DuckDB UDF
actual: DuckDB throws "Catalog Error: Scalar Function with name min_or_na does not exist! Did you mean min?" at enrollment aggregation step
errors: |
  --- Enrollment Aggregation ---
  ** R/14_build_cohort.R -- FAILED: Failed to collect lazy table.
  Caused by error in `dbSendQuery()`:
  ! Catalog Error: Scalar Function with name min_or_na does not exist!
  Did you mean "min"?
  LINE 7:     min_or_na(ENR_START_DATE) AS enr_start_date,
reproduction: source("R/39_run_all_investigations.R") or source("R/14_build_cohort.R") on HiPerGator
started: 2026-07-25 during first full pipeline run on HiPerGator via R/39

## Eliminated

- hypothesis: min_or_na is not defined/sourced at all
  evidence: It IS defined in R/utils/utils_assertions.R lines 264-267. The function loads fine. The error is at SQL execution time, not at R definition time.
  timestamp: 2026-07-25

- hypothesis: DuckDB UDF registration gap (min_or_na was supposed to be registered with duckdb_register_function or similar)
  evidence: utils_duckdb.R has no UDF registration calls at all. No script uses duckdb_register_function(). The design was always pure-R functions, not DuckDB UDFs. The problem is calling them on lazy tbl_dbi objects.
  timestamp: 2026-07-25

## Evidence

- timestamp: 2026-07-25
  checked: R/utils/utils_duckdb.R — full file
  found: open_pcornet_con() opens the connection and creates TUMOR_REGISTRY_ALL view. Zero UDF registration of any kind. No duckdb_register_function() calls anywhere in the codebase.
  implication: min_or_na and is_cancer_code were never intended to be SQL UDFs. They must be called on in-memory (collected) data only.

- timestamp: 2026-07-25
  checked: R/14_build_cohort.R lines 252-276 (enrollment aggregation section)
  found: enrollment_primary is a tbl_dbi (lazy DuckDB query built from get_pcornet_table("ENROLLMENT") %>% inner_join(...)). It flows directly into group_by() %>% summarise(min_or_na(ENR_START_DATE), ...) at lines 267-271 with NO collect() before the summarise. The collect() appears AFTER at line 276 via materialize(). DuckDB tries to translate min_or_na to SQL, fails.
  implication: Need collect() before the summarise, not after.

- timestamp: 2026-07-25
  checked: R/11_treatment_payer.R lines 209-222 (TUMOR_REGISTRY chemo dates using min_or_na)
  found: collect() at line 212 before tr_dates assignment. min_or_na at line 222 runs on in-memory tibble. Works correctly.
  implication: This is the correct pattern. R/14 was written inconsistently.

- timestamp: 2026-07-25
  checked: R/13_survivorship_encounters.R lines 96-105 (enc_av_th -> level1_per_patient)
  found: collect() at line 96 before level1_per_patient assignment. min_or_na at line 102 runs on in-memory tibble. Pattern is correct.
  implication: R/14 is the outlier — all other scripts collect() before using min_or_na().

- timestamp: 2026-07-25
  checked: R/46_cancer_summary_table.R lines 96-102
  found: get_pcornet_table("DIAGNOSIS") %>% filter(...) %>% mutate(DX_norm=...) %>% filter(is_cancer_code(DX_norm)) — is_cancer_code() is called on a lazy tbl_dbi before collect(). is_cancer_code() is a pure R function that checks CANCER_SITE_MAP lookups — dbplyr cannot translate it to SQL.
  implication: Need collect() after the mutate(DX_norm=...) step and before is_cancer_code() filter, or use SQL-compatible filtering (DX_norm patterns that DuckDB can execute natively).

## Resolution

root_cause: |
  Two scripts call pure-R helper functions within lazy DuckDB tbl_dbi pipelines, causing dbplyr to try translating them to SQL scalar functions which do not exist in DuckDB:

  1. R/14 line 268-270: enrollment_primary (tbl_dbi) -> group_by() -> summarise(min_or_na(...), max_or_na(...)) without collect() first. Fix: insert collect() after the mutate() (line 265-266) and before group_by/summarise.

  2. R/46 line 99: lazy DIAGNOSIS tbl_dbi pipeline uses filter(is_cancer_code(DX_norm)) before collect(). Fix: insert collect() after mutate(DX_norm=...) and before filter(is_cancer_code(...)).

fix: |
  R/14: Insert collect() after the mutate(ENR_START_DATE/ENR_END_DATE sentinel cleanup) and before group_by/summarise. Replace min_or_na/max_or_na in the summarise with min/max (na.rm=TRUE) since after collect() all-NA groups are handled by base R's warnings — OR keep min_or_na which also works fine on in-memory tibbles. The materialize() at line 276 becomes redundant but harmless.

  R/46: Insert collect() after mutate(DX_norm=...) and before filter(is_cancer_code(DX_norm)). This materializes only the two needed columns (DX_TYPE, DX_norm) before R-side filtering.

verification: pending
files_changed: [R/14_build_cohort.R, R/46_cancer_summary_table.R]
