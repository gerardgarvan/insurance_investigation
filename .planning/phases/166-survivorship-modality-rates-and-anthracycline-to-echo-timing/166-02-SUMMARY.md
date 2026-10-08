---
phase: 166-survivorship-modality-rates-and-anthracycline-to-echo-timing
plan: "02"
subsystem: surveillance-rates
tags: [rates, person-years, modality, survivorship, TDD]
one_liner: "Per-patient modality rates (n_dates_post_primary / person_years) via pure functions and option-a dated-event chain, with Y1/Y2/Y3-5/5+ interval breakdown and interval reconciliation QC"
dependency_graph:
  requires:
    - "166-01 (audit confirming n_dates_col, function chain, script numbers)"
    - "R/147 output: surveillance_modality_patient_<date>.rds"
  provides:
    - "R/utils/utils_surveillance_rates.R (5 pure functions)"
    - "R/166_survivorship_modality_rates.R (driver)"
    - "survivorship_modality_rates_parts_<date>.rds"
    - "survivorship_dated_events_<date>.rds (reused by Plan 03)"
  affects:
    - "166-03 (echo timing block reads survivorship_dated_events_<date>.rds)"
    - "166-04 (workbook reads survivorship_modality_rates_parts_<date>.rds)"
tech_stack:
  added: []
  patterns:
    - "TDD RED → GREEN for pure utility functions"
    - "option-a dated-event rebuild: same function chain as R/147 SECTION 7"
    - "half-open interval boundaries via cut(..., right=TRUE)"
    - "QC as message + named list element, not hard stop"
key_files:
  created:
    - R/utils/utils_surveillance_rates.R
    - R/166_survivorship_modality_rates.R
    - tests/testthat/test-166-rates.R
  modified: []
decisions:
  - "Task 0 skipped: dated_events_source = option_a (confirmed by 166-AUDIT.md); no additive saveRDS needed in R/147"
  - "Driver file is R/166 (not R/165 as PLAN.md placeholder stated); audit script_rates = 166"
  - "n_dates_col = n_dates_post_primary (confirmed from audit)"
  - "Option-a function chain mirrors R/147 SECTION 7 exactly: match_coded_events + build_component_events + build_analyte_events + classify_event_window"
  - "Interval reconciliation is QC (message + named list), never a hard stop; Plan 04 surfaces it"
metrics:
  duration_minutes: 25
  completed_date: "2026-10-08"
  tasks_completed: 3
  tasks_planned: 3
  files_created: 3
  files_modified: 0
key_decisions:
  - "n_dates_col confirmed as n_dates_post_primary from 166-AUDIT.md"
  - "Script number 166 (not 165 placeholder) for the rates driver"
  - "Task 0 skipped per option_a audit result"
requirements_met:
  - SRATE-02
---

# Phase 166 Plan 02: Survivorship Modality Rate Tables Summary

Per-patient modality rates (n_dates_post_primary / person_years) via pure functions and option-a dated-event chain, with Y1/Y2/Y3-5/5+ interval breakdown and interval reconciliation QC.

## What Was Built

### Task 0 (skipped)
The audit confirmed `dated_events_source = option_a`. No additive saveRDS was needed in R/147. Task 0 was skipped per plan instructions.

### Task 1 — Pure functions in R/utils/utils_surveillance_rates.R (TDD)

RED commit `599da00`: 6-fixture testthat file covering:
- (a) rate formula: 6/2.0 → 3.0
- (b) zero-event patient retained with rate = 0
- (c) py=0 or NA → NA rate
- (d) half-open boundary: day 365 → Y1, day 366 → Y2
- (e) reconciliation: followed 1000 days, events at 100/400/800; interval py sum = 1000/365.25, dates sum = 3, Y3-5 py = 270/365.25
- (f) anchor-day and post-follow_end events excluded by build_dated_post_events()

GREEN commit `a92b81a`: Five pure functions implemented (dplyr/tidyr only, no data.table, no setwd):

- **`build_dated_post_events(events_win, followup)`** — option-a filter: `filter(type_ok, tier == "primary", window == "post") |> distinct(ID, modality, event_date)`. Reproduces n_dates_post_primary exactly.
- **`compute_modality_rates(patient_modality, n_dates_col)`** — long table ID × modality, rate = n/py; NA when py is 0 or NA; all rows kept (zero-event patients rate = 0).
- **`rates_wide(long)`** — pivot_wider to `<modality>_rate_per_py` columns, one row per ID.
- **`split_followup_intervals(followup, events_dated, breaks)`** — Y1/Y2/Y3-5/5+ breakdown with half-open boundaries; every ID × modality × interval the patient reaches is included; person-time = overlap of (0, followed_days] with interval / 365.25.
- **`rates_summary(long)`** — per modality: n_patients, n_zero_event, mean/median/q25/q75 of rate_per_py (NA excluded), pooled_rate = sum(n_dates_post[py>0]) / sum(py[py>0]).

All roxygen headers document the NA rule (D-04), half-open boundary rule, and reconciliation invariant (D-03b).

### Task 2 — Driver R/166_survivorship_modality_rates.R

Commit `1399587`. Sections:

1. Loads most recent `surveillance_modality_patient_*.rds` (stops with clear message if absent).
2. Builds `followup` via `distinct(patient_modality, ID, hl_anchor_date, follow_end, person_years)`; asserts no duplicated IDs.
3. `long_rates = compute_modality_rates(patient_modality, n_dates_col = "n_dates_post_primary")`; unique ID × modality asserted.
4. `wide_rates = rates_wide(long_rates)`; unique ID asserted. `A_rates_summary = rates_summary(long_rates)`.
5. Option-a function chain: opens DuckDB, pulls PROCEDURES + LAB_RESULT_CM for all denominator IDs, runs `match_coded_events → build_component_events → build_analyte_events → classify_event_window`, then `build_dated_post_events()`. Saves `survivorship_dated_events_<date>.rds`.
6. `B_rates_by_fu_year = split_followup_intervals(followup, events_dated)`.
7. Interval reconciliation QC: per ID × modality, compares summed interval py to person_years (tol 1e-6) and summed dates to n_dates_post. Reports via `message()`; failing rows kept in `qc_interval_fail` (first 50). Not a hard stop.
8. `n_zero_py_patients` computed.
9. Named list saved to `survivorship_modality_rates_parts_<date>.rds`.

## Deviations from Plan

### Auto-resolved

**1. [Rule 1 - Correction] Driver script number: R/166, not R/165**
- **Found during:** Task 2
- **Issue:** PLAN.md frontmatter uses `R/165_survivorship_modality_rates.R` as a placeholder; the audit recorded `script_rates: 166`.
- **Fix:** Driver written as `R/166_survivorship_modality_rates.R` per 166-AUDIT.md.
- **Files modified:** R/166_survivorship_modality_rates.R (created at correct path)

None other — plan executed per audit spec.

## Known Stubs

None. All outputs are structurally complete; actual values compute at HiPerGator runtime (Plan 04's run checkpoint).

## Self-Check: PASSED

Files confirmed present:
- `R/utils/utils_surveillance_rates.R` — FOUND
- `R/166_survivorship_modality_rates.R` — FOUND
- `tests/testthat/test-166-rates.R` — FOUND

Commits confirmed:
- `599da00` (RED test file) — FOUND
- `a92b81a` (GREEN pure functions) — FOUND
- `1399587` (driver) — FOUND

Grep checks:
- All 5 function names present in utils_surveillance_rates.R
- 0 data.table/setwd in utils_surveillance_rates.R
- All required greps present in R/166 driver
- 0 data.table/setwd in R/166 driver
