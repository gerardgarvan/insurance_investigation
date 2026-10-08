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
  modified:
    - .planning/phases/166-survivorship-modality-rates-and-anthracycline-to-echo-timing/166-AUDIT.md
decisions:
  - "script_rates=166, script_echo=167, script_workbook=168 (next free numbers after R/165)"
  - "echo_modality_name: Echocardiogram (from R/147 KEY sheet)"
  - "person_years_uses_phase161_compute_followup: yes (confirmed from R/147 line 265 and header audit note)"
  - "dated_events_source: option_a — rebuild via utils_surveillance.R function chain (no new RDS save in R/147 required)"
  - "n_dates_col: n_dates_post_primary; anchor_rule: strictly after anchor (ANCHOR_DAY_IS_POST=FALSE); followup_clip: yes; date_dedup: distinct ID x modality x event_date"
  - "survival_installed: yes (version 3.8.9 on HiPerGator) — no renv::install needed"
  - "episode_180_file: treatment_episode_detail_180.rds; patient_id column (not ID) — rename on load"
  - "first_line_flag_populated: no — D-08a fallback; all episodes in 180-day file treated equivalently"
  - "dated_events_reconciliation_sample: 1363/1363 matching (PASS) — option_a confirmed correct"
metrics:
  duration_minutes: 40
  tasks_completed: 3
  tasks_total: 3
  files_created: 2
  files_modified: 1
  completed_date: "2026-10-08"
requirements_met: [SRATE-01]
---

# Phase 166 Plan 01: Audit Summary

**One-liner:** Code audit + HiPerGator data check confirms script numbers 166/167/168, reconciliation contract (option_a function chain, PASS on 1363/1363 sample), D-08a fallback (no first_line column), patient_id rename required, and survival 3.8.9 available — Plans 02-04 have all confirmed inputs.

## Tasks Completed

| Task | Name | Commit | Files |
|---|---|---|---|
| 1 | Code audit → draft 166-AUDIT.md + data check snippet | 00cb181 | 166-AUDIT.md, scratch/166_data_check.R |
| 2 | Run data check on HiPerGator | (human action) | logs/166_data_check.log |
| 3 | Fill audit from HiPerGator output | 02fa25e | 166-AUDIT.md |

## Decisions Made

### Script numbers
Scripts 166, 167, 168 are the next free numbers after R/165. Letter-suffixed names (e.g. 166b) are not introduced; only `R/122a` exists in the repo.

### Follow-up definition confirmed
`R/147` line 265 calls `compute_followup(denominator, activity, death_resolved, EXTRACT_CUTOFF)` using the Phase 161 three-argument signature. No D-05 discrepancy flag needed.

### Dated-events source: option_a (CONFIRMED)
`events_win` is produced entirely by pure functions in `utils_surveillance.R`. The 200-patient sample reconciliation passed: 1363/1363 ID x modality combinations matched exactly. No RDS save in R/147 required; no R/147 re-run required.

### Reconciliation contract
- `n_dates_col`: `n_dates_post_primary`
- `codeset_variant`: primary tier only (`tier == "primary"`)
- `anchor_rule`: event_date > hl_anchor_date (`ANCHOR_DAY_IS_POST = FALSE`)
- `followup_clip`: yes — events after `follow_end` excluded
- `date_dedup`: distinct ID x modality x event_date

### Episode file and D-08a fallback
- File: `treatment_episode_detail_180.rds` (nrow 259,199)
- ID column is `patient_id` — Plans 02/03 must `rename(ID = patient_id)` on load
- `first_line` column absent → D-08a triggered: all 180-day episodes treated equivalently
- No 90-day file found; 180-day is the only available episode source

### survival package
Available on HiPerGator (version 3.8.9). No installation step needed before Plan 03.

## Deviations from Plan

### Auto-noted discovery (not a code fix)
The episode file uses `patient_id` instead of `ID`. This is a data-discovery finding (not a code bug in an existing script) recorded in 166-AUDIT.md as a required rename in Plans 02/03. No deviation from the plan's task scope; the audit's purpose is exactly to surface this type of finding.

## Known Stubs

None. All PENDING-HPG items in 166-AUDIT.md are resolved. `grep -c "PENDING-HPG" 166-AUDIT.md` = 0.

## Self-Check: PASSED

- `.planning/phases/166-.../166-AUDIT.md`: FOUND (commits 00cb181, 02fa25e)
- `scratch/166_data_check.R`: FOUND (commit 00cb181)
- `grep -c "PENDING-HPG" 166-AUDIT.md` = 0 (Task 3 done criterion: MET)
- `grep -nE "saveRDS|write_csv|write\.csv|openxlsx|saveWorkbook" scratch/166_data_check.R` = 0
- All 9 audit sections present: script numbers, modality set, existing rate columns, follow-up definition, reconciliation contract, dated-events source, treatment episode readiness, survival package, build-vs-reuse list
