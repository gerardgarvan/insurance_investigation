---
phase: 134
plan: "02"
subsystem: test-honesty
tags: [parity-test, fixture, baseline, PATTERN-E]
dependency_graph:
  requires: []
  provides: [honest-r81-parity-test, honest-r96-flm-fixture, honest-r98-baseline]
  affects: [R/81_parity_test_cohort.R, R/96_validate_payer_dt.R, R/98_validate_r28_migration.R]
tech_stack:
  added: []
  patterns: [snapshot-baseline, fixture-driven-testing, paired-before-after-assertions]
key_files:
  created: []
  modified:
    - R/81_parity_test_cohort.R
    - R/96_validate_payer_dt.R
    - R/98_validate_r28_migration.R
decisions:
  - "D-12: First R/98 comparison is trivially empty by design; drift detectable from Phase-134 snapshot forward"
  - "R/96 FLM override keyed on SOURCE == 'FLM', not payer code -- row 19 changed to Private ('511') so override is distinguishable from a no-op"
metrics:
  duration_minutes: 15
  completed: "2026-07-25"
  tasks_completed: 3
  files_modified: 3
---

# Phase 134 Plan 02: R/81 coerce_types removal + R/96 FLM fixture + R/98 independent baseline Summary

Removed type coercion masking from the parity test, fixed the FLM-override fixture so the override path is provably exercised, and replaced the circular self-comparison in the R/28 migration validator with an honest Phase-134 snapshot approach.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Remove coerce_types() and call sites from R/81 | 0cb3c21 | R/81_parity_test_cohort.R |
| 2 | Replace FLM fixture row 19 with non-Medicaid starting state | 0cb3c21 | R/96_validate_payer_dt.R |
| 3 | Replace circular baseline branch in R/98 with snapshot approach | 0cb3c21 | R/98_validate_r28_migration.R |

## What Changed

### R/81_parity_test_cohort.R

Removed the entire `coerce_types()` function (lines 96-125) and its two call sites:
- `cohort_ddb_coerced <- coerce_types(cohort_ddb, cohort_rds)`
- `attrition_ddb_coerced <- coerce_types(attrition_ddb, attrition_rds)`

Also removed the `message("\n--- Type coercion (D-08) ---")` header and the `# TYPE COERCION (D-08)` section comment block.

Downstream sort variables updated to use raw DuckDB output directly (`cohort_ddb` and `attrition_ddb` instead of the coerced variants). `waldo::compare()` at Level 3 now operates on uncoerced types, so genuine type divergence introduced by DuckDB's type inference will surface rather than being silently masked.

### R/96_validate_payer_dt.R

Row 19 `PAYER_TYPE_PRIMARY` changed from `"219"` (Medicaid) to `"511"` (Private). Row 19 `PAYER_TYPE_SECONDARY` changed from `"11"` (Medicare) to `NA_character_` (no secondary needed). Comment updated to explain the FLM override test intent.

Section 4 assertions replaced: the two original checks (both confirming `tier="Medicaid"` with the override active) were replaced with a paired before/after proof:
- `result_dt$tier[19] == "Private"` — without override, row 19 classifies as Private
- `result_dt_flm$tier[19] == "Medicaid"` — with override, row 19 reclassifies to Medicaid

The `result_dt` object (from Section 3's `flm_override=FALSE` run) is already in scope so no re-computation is needed.

### R/98_validate_r28_migration.R

Added a `# BASELINE CAVEAT (Phase 134, D-12)` block immediately after the script header, documenting the known first-run trivial-empty-comparison tradeoff.

Replaced the Section 3 baseline branch with a Phase-134 snapshot approach:
- Message clearly names this as a one-time snapshot (not a silent self-comparison)
- References the caveat at top of file
- Logs a `git add ... && git commit` instruction so the executor commits the baseline immediately after generation
- Uses `glue()` for path interpolation in messages

## Deviations from Plan

None — plan executed exactly as written.

## Verification Results

```
# R/81: coerce_types definition and call sites gone
grep -n "coerce_types\|D-08" R/81_parity_test_cohort.R
# (no output -- PASS)

# R/96: row 19 primary is now "511" (Private)
grep -n '"511".*Row 19\|Row 19.*511' R/96_validate_payer_dt.R
# 93: "511" # Row 19: FLM source with Private payer -- FLM override should reclassify to Medicaid -- PASS

# R/96: both override-proof assertions present
grep -n "tier.*Private.*WITHOUT override\|tier.*Medicaid.*WITH override" R/96_validate_payer_dt.R
# 190: check("FLM row (row 19) has tier='Private' WITHOUT override ...
# 192: check("FLM row (row 19) has tier='Medicaid' WITH override ...  -- PASS (2 matches)

# R/98: caveat comment present
grep -n "BASELINE CAVEAT" R/98_validate_r28_migration.R
# 24: # BASELINE CAVEAT (Phase 134, D-12) -- PASS

# R/98: Phase-134 snapshot message
grep -n "Phase-134 snapshot" R/98_validate_r28_migration.R
# 84: "Generating one from CURRENT output as a Phase-134 snapshot ... -- PASS

# R/98: commit instruction present
grep -n "Commit it now" R/98_validate_r28_migration.R
# 88: message(glue("Baseline saved. Commit it now: ... -- PASS
```

## Known Stubs

None.

## Self-Check: PASSED

- R/81_parity_test_cohort.R: modified, coerce_types removed
- R/96_validate_payer_dt.R: modified, row 19 changed and assertions updated
- R/98_validate_r28_migration.R: modified, caveat added, baseline branch replaced
- Commit 0cb3c21: confirmed in git log
