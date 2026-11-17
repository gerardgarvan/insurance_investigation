---
phase: 211-abvd-impact-table
plan: 01
subsystem: testing
tags: [r, abvd, avd, small-cell-suppression, testthat]
requires:
  - phase: 210
    provides: abvd_episode / avd_episode / ever_* flags in the 34-col episode schema
provides:
  - Pure helpers for ABVD/AVD old-vs-new impact tables (R/utils/utils_abvd_impact.R)
affects: [211-02, 211-03, 211-04]
tech-stack:
  added: []
  patterns: [aggregate-only helpers, "<11" suppression with total hiding]
key-files:
  created:
    - R/utils/utils_abvd_impact.R
    - tests/testthat/test-211-abvd-impact.R
key-decisions:
  - "Suppression helper named suppress_impact_table, not suppress_table"
metrics:
  completed: 2026-11-17
---

# Phase 211 Plan 01: ABVD impact helpers Summary

Aggregate-only helpers (fmt_sup, episode_crosstab, episode_transitions, patient_flag_compare, drug_set_patterns, beacopp_extra_components, ever_cross, suppress_impact_table) with fixture tests; no I/O, no patient-level output.

## Task Commits
- Tasks 0-2 (one commit): 5599055

## Verification
- `tools/rcheck.sh parse` on both files: 0 failed.
- `tools/rcheck.sh test 211`: 0 failed, 0 errors.

## Deviations from Plan

**1. [Rule 3 - Blocking] Renamed suppress_table to suppress_impact_table**
- R/utils/utils_surveillance.R:646 already defines `suppress_table(df, rules, threshold)`. It is auto-sourced after utils_abvd_impact.R and overrides it, so the plan's name failed the test (unused argument `total_col`).
- Later plans (02-04) must call `suppress_impact_table`.

## Assumptions (headless run)
- Task 0: column names taken from the plan; no probe file lists them (header check is plan 04 step 1).
- `episode_crosstab` / `episode_transitions` / `patient_flag_compare` assume old and new tables are row-aligned (same episode order, same nrow) and stop on a row-count mismatch. Plan 04 must confirm alignment or join first.
- Old ever_abvd is derived as any() of old abvd_episode per patient, since the old CSV has no per-patient flag guaranteed.
- `beacopp_extra_components` default component list (doxorubicin, bleomycin, etoposide, cyclophosphamide, vincristine, procarbazine, prednisone) is a named constant `BEACOPP_COMPONENTS_DEFAULT`; callers may pass REGIMEN_DICT components instead.
- `suppress_impact_table(total_col=)` hides the total row-wise when any component in that row is 1-10. Column totals are not handled.
- `fmt_sup` here is vectorised; several numbered scripts define their own scalar `fmt_sup` locally, which overrides it inside those scripts.

## Known Stubs
None.

## Self-Check: PASSED
