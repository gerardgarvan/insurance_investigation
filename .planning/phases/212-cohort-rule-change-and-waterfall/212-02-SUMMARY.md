# 212-02 SUMMARY — COMPLETE

- Added `R/utils/utils_cohort_rule.R`: `hl_confirmed_two_encounters()`, `apply_cohort_rule_v315()`, `cohort_waterfall_by_site()`, `fallback_summary_by_site()`. Uses existing `fmt_sup()`.
- Rule A implements user decisions D-212-05 (missing ENCOUNTERID = own encounter keyed by DX_DATE, else ADMIT_DATE) and D-212-05b (`require_diff_dates`).
- Added `DISTINCT_ENC_REQUIRE_DIFF_DATES` to `R/00_config.R` (default TRUE, env override).
- Added `tests/testthat/test-212-cohort-rule.R` (synthetic IDs; 8 tests).
- Verify: `tools/rcheck.sh parse` exit 0 on all changed files; `tools/rcheck.sh test 212`: 0 failures.

## Deviations
- Fallback summary helper `fallback_summary_by_site()` added (not in plan) for the by-site fallback report.
- Plan's `n_na_enc_only` attribute replaced by `fallback_rows` / `fallback_only_ids` / `n_rows_no_key`.

## Assumptions (headless run)
- Equivalence used: >= 2 distinct encounter keys AND >= 2 distinct dates implies two encounters on different dates.
