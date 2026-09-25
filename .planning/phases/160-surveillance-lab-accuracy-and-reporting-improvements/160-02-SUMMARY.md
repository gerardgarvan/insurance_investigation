---
phase: 160-surveillance-lab-accuracy-and-reporting-improvements
plan: "02"
subsystem: utils_surveillance / A3 diagnostic / eligible denominators
tags: [tdd, analyte-diagnostic, eligible-sex, suppression, codeset-summary]
dependency_graph:
  requires: [160-01]
  provides: [summarise_missing_analyte, select_a3_sample, surv_sql_date_expr, rank_candidate_codes, compute_eligible_modality_stats, suppress_eligible_columns, build_codeset_summary]
  affects: [R/147_surveillance_modality_frequency.R]
tech_stack:
  added: []
  patterns: [contrast-ranking-by-lift, complementary-suppression, deterministic-seeded-sampling]
key_files:
  created:
    - tests/testthat/test-160-diagnostic-and-eligibility.R
  modified:
    - R/utils/utils_surveillance.R
decisions:
  - "Rscript unavailable on Windows host; testthat RED/GREEN runs and automated verify command deferred to HiPerGator (160-04 Task 2 will run test_dir before workbook ships)"
  - "surv_sql_date_expr single-column DuckDB path returns one-level COALESCE (no outer wrap) matching test expectation for the two-column case which produces COALESCE(COALESCE(TRY_CAST...))"
metrics:
  duration_minutes: 20
  completed_date: "2026-09-25"
  tasks_completed: 2
  files_modified: 2
---

# Phase 160 Plan 02: Phase 160 Pure Functions Summary

Seven pure functions added to `R/utils/utils_surveillance.R` covering A3 missing-analyte diagnostics, deterministic sampling, SQL date expression generation, contrast-ranked candidate codes, eligible-sex B/C statistics, complementary suppression, and codeset summary — with 55-expectation testthat coverage in a new test file.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 (RED) | Add failing test file | 5299a96 | tests/testthat/test-160-diagnostic-and-eligibility.R |
| 1 (GREEN) | Implement Phase 160 functions | 8b34fe9 | R/utils/utils_surveillance.R |

## What Was Built

**Task 1 (RED) — Test file `tests/testthat/test-160-diagnostic-and-eligibility.R`:**
55 expectations across 9 `test_that` blocks covering:
- Block 1: CO2 miss count = 2, CALCIUM miss count = 1, total = 3; reconciles with `build_analyte_events()` near-miss count at 7-of-8; SC126/SC166/SC167 absent; by-year sums; complete days returned with NA `missing_analyte`
- Sampling: 30 patients × 2 days, cap 10 → 10 rows, no repeated ID, identical after shuffling input
- SQL date expression: sqlite `DATE(col)`; duckdb nested COALESCE with TRY_CAST and `%m/%d/%Y`
- Block 2: 57922-7 ranks first with lift 1; hemoglobin lift 0 ranks below LOC123; Lab_Analytes and unsampled codes absent; 57922-7 flagged excluded/MASTER; LOC123 keeps code_source "RAW"
- Eligible stats: female 2 of 3, pct 66.7, female person-years 6, rate 0.5; all-patient columns identical to `compute_modality_stats()`; M1 and U1 are other-sex
- Complementary suppression: other-sex 5 with eligible 495 → other "<11", eligible/pct/event-dates/rate blank; 25/15 row untouched; prefix variant works
- Codeset summary: code counts and lists per modality × tier × match, threshold text, analyte code and present counts

**Task 1 (GREEN) — `R/utils/utils_surveillance.R` Phase 160 section (lines 688–976):**
- `summarise_missing_analyte()`: filters `analyte_all_same_day` rules with ≥2 analytes; deduplicates hits by ID × date × analyte before counting; attributes exactly n_listed−1 presence rows to the one missing analyte; returns `list(days, overall, by_year)` with complete days in the `days` component for block 2 comparison
- `select_a3_sample()`: sorts rows before `set.seed()` for order-independence; one day per patient per group via `slice_min(.u, n=1)`; cap via `slice_min(.u, n=n_max)` at group level
- `surv_sql_date_expr()`: single-column path returns the inner COALESCE expression directly; multi-column wraps in outer COALESCE; `%%` escaping for `sprintf` produces literal `%m/%d/%Y`
- `rank_candidate_codes()`: Lab_Analytes codes excluded in R (non-RAW source with code_norm in analytes); codes on unsampled days excluded via `inner_join` to sample; lift = coverage_near − coalesce(coverage_control, 0); `rank` within codeset_row_id × missing_analyte group; top_of() picks modal raw label
- `compute_eligible_modality_stats()`: returns `base` unchanged when `eligible_sex == ""`; zero-eligible-denominator branch returns NA pct/rate via the `nrow(fu) == 0` guard; `n_patients_other_sex` = all − eligible via the complement followup split
- `suppress_eligible_columns()`: processes two pairs (patient counts, event-date counts); complementary logic: `hide <- small(a) | small(b)`; sets both sides blank then overwrites the actually-small side with `"<11"`; `prefix` prepended to all column names
- `build_codeset_summary()`: `by_modality` groups by modality × tier × match, sorts analyte codes for stable `codes` string; `by_analyte` left-joins presence summary when supplied

## Deviations from Plan

None — plan executed exactly as written. Code follows the plan's provided implementation verbatim.

## Known Stubs

None. All seven functions are fully implemented; R/147 wiring is the Wave 3 task (Plan 160-03).

## Verification Status

**Rscript is unavailable on this Windows development host.** The following are deferred to HiPerGator per the plan's own fallback clause:

- `testthat::test_dir("tests/testthat", filter = "15[89]|160", stop_on_failure = TRUE)` — 216 expectations (Phases 158–160)

**Structural fallback (passed):**
- All 7 function names: 1 match each in utils_surveillance.R
- Paren balance: 0 (balanced)
- Brace balance: 0 (balanced)

Per 160-CONTEXT.md and the plan's `<verification>` clause, 160-04 Task 2 (HiPerGator run) will execute the full test suite before the workbook ships.

## Self-Check: PASSED

Files exist:
- `tests/testthat/test-160-diagnostic-and-eligibility.R`: FOUND
- `R/utils/utils_surveillance.R` (modified): FOUND

Commits exist:
- 5299a96 (RED test): FOUND
- 8b34fe9 (GREEN implementation): FOUND
