---
phase: 166-survivorship-modality-rates-and-anthracycline-to-echo-timing
plan: "01"
subsystem: surveillance-rates-audit
tags: [audit, surveillance, modality-rates, anthracycline, echo-timing]
dependency_graph:
  requires: [R/147_surveillance_modality_frequency.R, R/162_export_patient_modality_dates.R, R/utils/utils_surveillance.R]
  provides: [166-AUDIT.md, scratch/166_data_check.R]
  affects: [166-02-PLAN.md, 166-03-PLAN.md, 166-04-PLAN.md]
tech_stack:
  added: []
  patterns: [audit-before-build, read-only-data-check]
key_files:
  created:
    - .planning/phases/166-survivorship-modality-rates-and-anthracycline-to-echo-timing/166-AUDIT.md
    - scratch/166_data_check.R
  modified: []
decisions:
  - "script_rates=166, script_echo=167, script_workbook=168 (next free numbers after R/165)"
  - "echo_modality_name: Echocardiogram (from R/147 KEY sheet)"
  - "person_years_uses_phase161_compute_followup: yes (confirmed from R/147 line 265 and header audit note)"
  - "dated_events_source: option_a — rebuild via utils_surveillance.R function chain (no new RDS save in R/147 required)"
  - "n_dates_col: n_dates_post_primary; anchor_rule: strictly after anchor (ANCHOR_DAY_IS_POST=FALSE); followup_clip: yes; date_dedup: distinct ID x modality x event_date"
  - "renv.lock not present in repo; survival_installed is PENDING-HPG"
metrics:
  duration_minutes: 25
  tasks_completed: 1
  tasks_total: 3
  files_created: 2
  files_modified: 0
  completed_date: "2026-10-08"
requirements_met: [SRATE-01-partial]
---

# Phase 166 Plan 01: Audit Summary

**One-liner:** Code audit of R/147 and utils_surveillance.R confirms script numbers 166/167/168, reconciliation contract (n_dates_post_primary, option-a function chain, Phase 161 follow-up), and PENDING-HPG items for HiPerGator confirmation.

## Tasks Completed

| Task | Name | Commit | Files |
|---|---|---|---|
| 1 | Code audit → draft 166-AUDIT.md + data check snippet | 00cb181 | 166-AUDIT.md, scratch/166_data_check.R |

## Tasks Pending (at checkpoint)

| Task | Name | Status |
|---|---|---|
| 2 | Run data check on HiPerGator | AWAITING human action |
| 3 | Fill audit from HiPerGator output | BLOCKED on Task 2 |

## Decisions Made

### Script numbers
Scripts 166, 167, 168 are the next free numbers after R/165. Letter-suffixed names (e.g. 166b) are not introduced; only `R/122a` exists in the repo.

### Follow-up definition confirmed
`R/147` line 265 calls `compute_followup(denominator, activity, death_resolved, EXTRACT_CUTOFF)` using the Phase 161 three-argument signature. Header comment at line 4 explicitly states `[161-07 audit] Updated in Phase 161-05`. No D-05 discrepancy flag needed.

### Dated-events source: option_a
`events_win` is produced entirely by pure functions in `utils_surveillance.R` (no DuckDB inside those functions). A new script can replicate by calling the same 5-step chain with DuckDB + CONFIG. No RDS save needed in R/147; R/147 re-run not required. This is the preferred option (option_a).

### Reconciliation contract
- `n_dates_col`: `n_dates_post_primary`
- `codeset_variant`: primary tier only (`tier == "primary"`)
- `anchor_rule`: event_date > hl_anchor_date (anchor day is pre; `ANCHOR_DAY_IS_POST = FALSE`)
- `followup_clip`: yes — events after `follow_end` excluded (`window != "after_followup"`)
- `date_dedup`: distinct ID x modality x event_date

## Deviations from Plan

None — plan executed exactly as written for Task 1.

## Known Stubs

None in the code artifacts. 166-AUDIT.md has PENDING-HPG placeholders in sections 7 (treatment episode columns, has_date_level_drug_rows, first_line_flag_populated, anthracyclines_present) and 8 (survival_installed). These are intentional — Task 3 will fill them from the HiPerGator run output.

## Self-Check: PASSED

- `.planning/phases/166-.../166-AUDIT.md`: FOUND
- `scratch/166_data_check.R`: FOUND
- Commit 00cb181: FOUND (git log confirmed)
- `grep -c "PENDING-HPG" 166-AUDIT.md` = 6 (Task 1 done criterion: draft with PENDING-HPG placeholders; Task 3 will reduce this to 0)
- `grep -nE "saveRDS|write_csv|write\.csv|openxlsx" scratch/166_data_check.R` = 0 (no write calls)
