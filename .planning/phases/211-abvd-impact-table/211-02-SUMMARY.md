---
phase: 211-abvd-impact-table
plan: 02
subsystem: reporting
tags: [r, abvd, avd, openxlsx]
requires:
  - phase: 211-01
    provides: helpers in R/utils/utils_abvd_impact.R
provides:
  - R/211_abvd_impact_table.R (KEY + six sheets not dependent on R/209)
affects: [211-03, 211-04]
key-files:
  created:
    - R/211_abvd_impact_table.R
metrics:
  completed: 2026-11-17
---

# Phase 211 Plan 02: ABVD impact workbook script Summary

R/211_abvd_impact_table.R reads the pinned old and new episode CSVs, guards row alignment, and writes `output/211_abvd_impact_<RUN_DATE>.xlsx` with sheets KEY, episode_by_class, episode_transitions, patient_flags, abvd_plus_no_bleo, abvd_plus_beacopp_comp, ever_abvd_x_avd. Aggregate counts only, 1-10 shown as "<11".

**Real run: PENDING HIPERGATOR (plan 04).** Only parse and fixture tests were run locally.

## Task Commits
- Tasks 0-1: 47d0f62

## Verification
- `tools/rcheck.sh parse R/211_abvd_impact_table.R`: 0 failed.
- `tools/rcheck.sh test 211`: 0 failed, 0 errors.

## Deviations from Plan
- None in scope. Calls `suppress_impact_table` (not `suppress_table`) per 211-01 SUMMARY.

## Assumptions (headless run)
- Task 0: column names from plan 01 constants (`ABVD_IMPACT_COLS`); no probe file lists them. Script stops printing available names if a column is missing (check in plan 04 step 1).
- BEACOPP components = union of `REGIMEN_DICT$BEACOPP$drugs` and `$optional` (R/00_config.R:4552); the four ABVD drugs do not count as extra.
- `abvd_plus_no_bleo` = new `abvd_class == "ABVD_PLUS"` and new `avd_episode` TRUE; the class label "ABVD_PLUS" is taken from CONTEXT, unverified against the real CSV.
- Flags parsed with `toupper(trimws(x)) == "TRUE"`; NA treated as FALSE in patient-level any().
- Alignment guard compares `patient_id`, `treatment_type`, `drug_names` with NA-safe equality; stops if any mismatch.
- Complementary (derived-cell) suppression is not applied beyond per-cell "<11"; totals row row in pattern sheets is suppressed independently.
- Console prints only suppressed counts and checkpoints.
- Reconciliation sheet (R/209) is absent; KEY row says pending plan 03.

## Known Stubs
None (reconciliation deferred to plan 03 by design).

## Self-Check: PASSED
