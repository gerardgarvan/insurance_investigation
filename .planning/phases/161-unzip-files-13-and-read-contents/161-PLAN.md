# Phase 161 — Plan

Depends on: D1–D5 locked in 161-CONTEXT.md.
Tasks 161-01 and 161-02 can proceed before team sign-off on D1/D2.
161-03 onward implements the agreed rules and requires team sign-off.

## 161-01 Fix ingest typing (R/03)
- In `R/03_duckdb_ingest.R`, type `DEATH_DATE_IMPUTE` as VARCHAR (it is an
  imputation flag, not a date). Audit all columns whose name contains `DATE`
  and confirm only true date fields are cast to DATE.
- Rebuild `/blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb`.
- Acceptance: `DEATH_DATE_IMPUTE` is VARCHAR with non-null B/D/M/N values;
  R/88 asserts the column is populated.

## 161-02 Re-run diagnostic on rebuilt database
- Re-run `R/161_diag_anchor_followup.R` with `print(width = Inf)`; record
  category 2a (imputed death dates) and conflicting-date reconciliation counts
  (`n_conflicting`, `n_death_max_reconciles`). Update 161-CONTEXT.md with the
  numbers so D3 inputs are available for team review.
- Acceptance: updated counts committed to 161-CONTEXT.md.

## 161-03 Shared death-date plausibility utility (FIXED REQUIREMENT — D4)
- Add `resolve_death_date()` to `R/utils/utils_death.R` (new file). Returns
  one row per patient:
  - `death_date_raw` — earliest raw date from DEATH
  - `death_date_resolved` — date after applying plausibility rules
  - `death_flag` — one of: `plausible` / `implausible_post_activity` /
    `conflicting_resolved` / `conflicting_unresolved`
  - `post_death_activity_days` — days of activity beyond recorded death date
- Rules (per D1–D3):
  - Grace period N = 30 days.
  - Conflicting dates: use the *earliest* date consistent with clinical activity
    (consistent = death_date ≥ last_activity_date − N); if `DEATH_SOURCE` is
    populated, use NDI/state > SSA > local/tumor-registry as tiebreaker.
  - Apply D2 if no date is consistent: end follow-up at last observed activity,
    set `death_flag = implausible_post_activity`.
  - Output sensitivity table: patient counts at N = 0, 30, 60, 90, 365 days
    flagged as implausible, so the threshold choice is documented.
- Acceptance: reproduces the 261 implausible cases from the pre-fix diagnostic
  at N = 30; sensitivity table written to output.

## 161-04 Redefine follow-up end (utils_surveillance.R)
- In `compute_followup()`:
  - Replace admit-only `last_enc_date` with
    `obs_end = max(discharge-or-admit, latest CDM activity)`, capped at cutoff.
  - Use `death_date_resolved` from `resolve_death_date()` in `pmin()`.
  - Split `fu_status` into three levels: `positive` / `zero` / `negative`.
    Zero-follow-up patients are reported separately from negative.
  - Carry `death_flag` through to output.
- Acceptance: no retained patient has `follow_end < hl_anchor_date`;
  `fu_status` has three levels in all downstream tables.

## 161-05 R/147 reporting
- Report counts by `death_flag` and `fu_status` in the R/147 output log and
  deliverable notes.
- Apply D2 consistently: flagged patients are included with follow-up ending at
  last observed activity; sensitivity analysis excluding flagged patients is
  written alongside the main output.
- Confirm event-window classification: events on `hl_anchor_date` are "pre"
  (D5); "post" means strictly after `hl_anchor_date`.

## 161-06 Tests and smoke checks
- In `tests/testthat/test-161-death-plausibility.R` (new file), add fixtures for:
  - Death before diagnosis (single and conflicting death dates)
  - Post-death activity within grace period (should remain `plausible`)
  - Post-death activity beyond grace period (should flag `implausible_post_activity`)
  - Inpatient anchor with later discharge date
  - Zero-follow-up patient after fix (≥ 0 days, reported separately)
- R/88: assert `follow_end >= hl_anchor_date` for all retained patients;
  assert `DEATH_DATE_IMPUTE` is VARCHAR and populated.

## 161-07 Audit DEATH usage across all scripts (FIXED REQUIREMENT — D4)
- Search the entire codebase for scripts that read the DEATH table directly
  (e.g., `grep -r "DEATH" R/ --include="*.R"`).
- For each script found: confirm it calls `resolve_death_date()` or explicitly
  documents why it does not (e.g., a script that only counts death records, not
  dates).
- Re-run R/147; compare per-modality counts, person-years, and rates against the
  current deliverable. Summarize differences for the team.

## 161-08 HiPerGator checkpoint
- Re-run the full pipeline on HiPerGator after 161-01 through 161-07.
- Confirm rebuilt DuckDB, updated R/147 output, sensitivity tables, and smoke
  checks all pass.
- Record final `n_implausible` and person-year delta in 161-CONTEXT.md.
