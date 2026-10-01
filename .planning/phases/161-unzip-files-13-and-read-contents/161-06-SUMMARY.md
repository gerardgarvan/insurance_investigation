---
phase: 161
plan: "06"
subsystem: testing
tags: [tests, death-plausibility, compute-followup, smoke-test, D1-D3-D6]
dependency_graph:
  requires: [161-03, 161-04]
  provides: [test-161-death-plausibility, r88-section-15am]
  affects: [R/88_smoke_test_comprehensive.R, tests/testthat/]
tech_stack:
  added: []
  patterns: [testthat fixture testing, synthetic tibble fixtures, grace boundary tests]
key_files:
  created:
    - tests/testthat/test-161-death-plausibility.R
  modified:
    - R/88_smoke_test_comprehensive.R
decisions:
  - "Fixture 7: N outranks L on different dates -> resolved to N's date (2021-03-05), not earliest date -- consistent with D3 priority-first-then-earliest rule"
  - "Fixture 15 (posthumous_dx with obs after anchor): D6 overrides follow_end to anchor => zero, not positive -- because follow_end == anchor after the override"
  - "R/88 assertion B uses synthetic in-memory fixtures rather than live DuckDB, so the smoke test exercises the shared function code paths offline"
  - "DEATH_DATE_IMPUTE live check wrapped in if(exists('con')) so R/88 passes on developer machines without HiPerGator data"
metrics:
  duration: "~20 min"
  completed: "2026-10-01"
  tasks: 2
  files: 2
---

# Phase 161 Plan 06: Death-Plausibility Tests and R/88 Assertions Summary

Pure testthat fixture coverage for `resolve_death_date()` and `compute_followup()`, plus two new structural assertions in `R/88_smoke_test_comprehensive.R` (Section 15am).

## What Was Built

### tests/testthat/test-161-death-plausibility.R (new, 20 tests)

All fixtures are synthetic tibbles -- no DuckDB, no CSVs. Covers:

**resolve_death_date() -- death_flag values:**
- Fixture 1: single death, 1977d activity gap -> `implausible_post_activity`, `post_death_activity_days = 1977`
- Fixture 2: two death dates, both inconsistent -> `conflicting_unresolved`
- Fixture 3: two death dates, one consistent -> `conflicting_resolved`, resolved to the consistent date
- Fixture 4: single death 19d before last activity -> `plausible`
- Fixture 5: single death 75d before last activity -> `implausible_post_activity`

**Grace boundary:**
- Fixture 6a: exactly 30d gap -> `plausible` (boundary inclusive)
- Fixture 6b: 31d gap -> `implausible_post_activity` (just over boundary)

**Source priority D3:**
- Fixture 7: N (rank 1) vs L (rank 4) on different dates -> resolved to N's date
- Fixture 8: same date from L and N -> `plausible`, `death_source_resolved = "N"`
- Fixture 11 (group 11): N beats S on tiebreak

**Edge cases:**
- Fixture 9: no DEATH row -> `no_death_record`, `post_death_activity_days = 0`
- Fixture 10: `last_observed = NA` -> treated as consistent -> `plausible`
- Fixture 11 (exclusion): DEATH row for non-cohort ID absent from output
- One-row-per-cohort-ID assertion
- `post_death_activity_days = 1977` exact value test
- `post_death_activity_days = 0` for no-record patient

**death_sensitivity_table():**
- Returns 5 rows for 5 grace values
- `n_no_credible_death` is weakly decreasing as grace_days increases

**compute_followup() scenarios:**
- Fixture 12: no death, `follow_end = last_enc_any`, `fu_status = "positive"`
- Fixture 13: same-day anchor and last_observed -> `"zero"`, `fu_reason = "same_day_last_contact"`
- Fixture 14: implausible death (`death_resolved = NA`, D2) -> censored at `last_observed`, positive
- Fixture 15: posthumous_dx (death < anchor, D6) -> `follow_end = anchor`, `fu_status = "zero"`, `fu_reason = "posthumous_dx"`
- Fixture 16: `last_observed` after cutoff -> `follow_end = cutoff (2025-12-31)`
- Fixture 17: missing `activity`/`death_resolved` -> `stop()` with `[161-04]` tag
- Fixture 18: legacy `death =` positional argument -> `warning()` with `[161-04]` tag
- No-negative check: all 4 representative fixtures yield `fu_status != "negative"`

### R/88_smoke_test_comprehensive.R (modified, Section 15am added)

New Section 15am immediately before Section 16 (SUMMARY). Contains:

1. `utils_death.R` and `utils_surveillance.R` file existence checks
2. Both files source without error
3. `resolve_death_date()`, `death_sensitivity_table()`, `compute_followup()` all defined
4. `tests/testthat/test-161-death-plausibility.R` exists
5. Live DEATH_DATE_IMPUTE VARCHAR guard (skipped gracefully when no `con` object)
   - Column exists in DEATH table
   - Column type is VARCHAR (not DATE)
   - Non-NULL count > 0 (unless `CONFIG$death_impute_absent_at_source = TRUE`)
   - No non-date column inadvertently typed DATE
6. Synthetic in-memory invariant test:
   - 5-patient cohort spanning all 5 `death_flag` values
   - `resolve_death_date()` + `compute_followup()` called with `grace_days = 30L`
   - Assert `n_neg == 0L` (no negative follow-up)
   - Assert D2 invariant: `implausible_post_activity`, `conflicting_unresolved`, `no_death_record` all have `death_date_resolved = NA`

Also added SMOKE-161-01 bullet to the validated-requirements message block.

## Deviations from Plan

None -- plan executed exactly as written, with one clarification:

The plan specified fixture 15 should yield `fu_status = "zero"` because `follow_end` is overridden to `hl_anchor_date` (D6), and `hl_anchor_date == hl_anchor_date` gives zero days. This is correct and matches the D6 spec.

## Self-Check: PASSED

Files created/modified:
- `tests/testthat/test-161-death-plausibility.R` -- exists (committed at e6a7676)
- `R/88_smoke_test_comprehensive.R` -- Section 15am present (committed at e6a7676)

Commits:
- e6a7676: `feat(161-06): add death-plausibility tests and R/88 assertions`
