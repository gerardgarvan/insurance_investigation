---
phase: 161
plan: "05"
subsystem: surveillance
tags: [follow-up, death-resolution, sensitivity-analysis, activity]
dependency_graph:
  requires: [161-03, 161-04]
  provides: [147-followup-161-pattern, 147-flag-summary, 147-sensitivity-exclusion]
  affects: [R/147_surveillance_modality_frequency.R, R/utils/utils_surveillance.R]
tech_stack:
  added: [readr]
  patterns: [get_last_activity, resolve_death_date, compute_followup-new-signature]
key_files:
  modified:
    - R/147_surveillance_modality_frequency.R
    - R/utils/utils_surveillance.R
decisions:
  - "Collect DEATH_SOURCE alongside DEATH_DATE so resolve_death_date() can apply source-priority D3"
  - "Sensitivity exclusion defined as death_flag in {implausible_post_activity, conflicting_unresolved}; main analysis retains all patients"
  - "classify_event_window D5 rule consolidated to explicit event_date <= hl_anchor_date comment"
metrics:
  duration: ~20min
  completed: "2026-10-01"
  tasks: 7
  files: 2
---

# Phase 161 Plan 05: R/147 — shared utils, flag reporting, sensitivity exclusion

Updated R/147 to call `get_last_activity()`, `resolve_death_date()`, and `compute_followup()` with the new 161-04 signature; added flag summary output, D2 confirmation logging, sensitivity exclusion analysis, and fixed QC table to report `zero` and `negative` fu_status separately.

## What Was Done

### Task 1 — Source new utils at top of R/147
Added `if (!exists(...))` guards for `utils_activity.R` and `utils_death.R` alongside the existing guards, and added `library(readr)` for CSV output.

### Task 2 — Replace follow-up block (Section 6)
Replaced the old manual `enc_raw` -> `last_enc` -> `death` -> `compute_followup(legacy)` pattern with:
```r
activity       <- get_last_activity(con, denominator, EXTRACT_CUTOFF)
# DEATH_DATE + DEATH_SOURCE pulled via semi_join on hl_ids_tbl
death_resolved <- resolve_death_date(death_rows, activity, grace_days = 30L)
followup       <- compute_followup(denominator, activity, death_resolved, EXTRACT_CUTOFF)
```
No legacy shim is triggered; no deprecation warning emitted.

### Task 3 — Flag summary block
Immediately after `compute_followup()`:
- `count(followup, death_flag, fu_status, fu_reason)` written to console and `output/161_flag_summary.csv`
- D2 guard: logs count of patients with `NA death_date_resolved` and count with implausible/conflicting_unresolved flags

### Task 4 — Main analysis retains all patients (D2 confirmed)
No downstream filter on `death_flag` or `death_date_resolved` drops any patient. The follow-up logic in `compute_followup()` already censors NA-death patients at `obs_end`.

### Task 5 — Sensitivity exclusion analysis
After writing the main workbooks:
```r
followup_sensitivity <- filter(followup, !death_flag %in% c("implausible_post_activity", "conflicting_unresolved"))
```
Re-runs `compute_modality_stats()` on the restricted cohort and writes:
- `output/147_surveillance_sensitivity_excl_no_credible_death.csv` with columns: modality, n_patients_main, n_patients_sens, delta_n_patients, events_per_py_main, events_per_py_sens, delta_total_event_dates, person_years_main, person_years_sens, n_cohort_main, n_cohort_sens
- Console table of rate differences (rate_diff, pct_change_n)

### Task 6 — Anchor-day rule (D5) in classify_event_window
Consolidated the two-condition pattern in `utils_surveillance.R` to a single named case with an explicit D5 comment:
```r
event_date <= hl_anchor_date & !anchor_day_is_post ~ "pre",   # D5: anchor-day is pre
event_date <  hl_anchor_date ~ "pre",                          # anchor_day_is_post=TRUE path
```
Semantics unchanged; comment makes the decision visible.

### Task 7 — QC table: zero and negative reported separately
Replaced `"Follow-up ok"` / `"zero_or_negative"` / `"no_followup_date"` rows with:
- `"Follow-up positive"` — `sum(fu_status == "positive")`
- `"Follow-up zero (0 person-years; same-day last contact)"` — `sum(fu_status == "zero")`
- `"Follow-up negative (should be 0 after D6)"` — `sum(fu_status == "negative")`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing functionality] DEATH_SOURCE collection**
- **Found during:** Task 2
- **Issue:** The old block only selected `ID, DEATH_DATE` from the DEATH table, dropping `DEATH_SOURCE`. `resolve_death_date()` requires DEATH_SOURCE for D3 source-priority logic.
- **Fix:** Changed `select(ID, DEATH_DATE)` to `select(any_of(c("ID", "DEATH_DATE", "DEATH_SOURCE")))` with a fallback to `NA_character_` if the column is absent.
- **Files modified:** R/147_surveillance_modality_frequency.R
- **Commit:** b1e9a77

**2. [Rule 1 - Bug] classify_event_window D5 case order**
- **Found during:** Task 6
- **Issue:** The consolidated `event_date <= hl_anchor_date` must come before the `event_date < hl_anchor_date` case so that anchor-day events are caught by the first branch when `anchor_day_is_post = FALSE`. The second branch (`< hl_anchor_date`) handles the `anchor_day_is_post = TRUE` path correctly because `==` events fall through to the post/after_followup cases.
- **Fix:** Ordered cases correctly with explicit comments.
- **Files modified:** R/utils/utils_surveillance.R
- **Commit:** b1e9a77

## Acceptance Criteria Check

- [x] R/147 calls `get_last_activity()`, `resolve_death_date()`, `compute_followup()` with new args; no raw admit-only last-encounter logic remains
- [x] `output/161_flag_summary.csv` written every run
- [x] Main analysis retains all denominator patients; D2 guard logged
- [x] Sensitivity output `147_surveillance_sensitivity_excl_no_credible_death.csv` written; console diff printed
- [x] Anchor-day events classified as "pre" via D5 rule in `classify_event_window`
- [x] `zero` and `negative` reported as separate QC rows
- [x] No deprecation warning from `compute_followup()` (new-signature call, no legacy detection triggered)

## Known Stubs

None. All data paths are wired to real CDM tables via DuckDB.

## Self-Check: PASSED

- `R/147_surveillance_modality_frequency.R` — modified and committed (b1e9a77)
- `R/utils/utils_surveillance.R` — modified and committed (b1e9a77)
- Commit b1e9a77 verified in git log
