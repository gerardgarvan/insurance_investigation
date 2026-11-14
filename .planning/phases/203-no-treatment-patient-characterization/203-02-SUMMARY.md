---
phase: 203-no-treatment-patient-characterization
plan: "02"
subsystem: no-treatment-characterization
tags: [characterization, NOTX-01, NOTX-02, NOTX-03, NOTX-04, duckdb, registry-join]
dependency_graph:
  requires: [confirmed_hl_cohort.rds, R/169 single_source_care RDS, R/193 TR flags RDS, DuckDB ENCOUNTER]
  provides: [NOTX-01..NOTX-04 computation blocks in R/203, char_pt RDS, per-group summaries]
  affects: [plan 203-03 workbook sheets A_profile, B_reasons_waterfall, C_by_source]
tech_stack:
  added: [tidyr]
  patterns: [named-constant guards with stop() printing available columns, dplyr inequality join, single-shared-DuckDB-connection, suppress-after-arithmetic (counts raw)]
key_files:
  created: []
  modified:
    - R/203_no_treatment_characterization.R
decisions: []
metrics:
  duration_minutes: 20
  completed_date: "2026-11-14"
  tasks_completed: 2
  tasks_total: 2
  files_created: 0
  files_modified: 1
---

# Phase 203 Plan 02: NOTX-01..NOTX-04 Characterization Blocks Summary

NOTX-01 through NOTX-04 characterization computed for both no_treatment and treated
groups (NOTX-06) using candidate column names guarded by stop() calls that print
available columns on HiPerGator if names differ from probe expectations.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | NOTX-01 window truncation + NOTX-02 peri-dx encounter counts | 8f8317e | R/203_no_treatment_characterization.R |
| 2 | NOTX-03 demographic/care characterization + NOTX-04 registry join | 8f8317e | R/203_no_treatment_characterization.R |

## Deviations from Plan

**1. [Rule 3 - Blocking] Tasks 1 and 2 committed together.**
Schema probe still PENDING at execution time — both tasks written in one editing
pass because char_pt (defined in Task 1) is immediately extended in Task 2;
splitting commits across a file that cannot be run locally would not add value.
Single commit 8f8317e covers both tasks' code.

**2. [Rule 2 - Missing functionality] Added `tidyr` to library() calls.**
`tidyr::pivot_longer` required for the TR_TX_COLS flag loop in NOTX-04; not
in the original scaffold's library list. Added during Task 2 implementation.

## Schema Status

203_schema_PENDING.md remains the only schema file. All column references use
candidate names from the probe placeholder with named constants and stop() guards:

| Constant | Candidate name | Guard |
|----------|---------------|-------|
| WINDOW_START_COL | `enr_start_date` | stop() prints available columns |
| NLPHL_COL | `is_nlphl` | stop() prints available columns |
| AGE_DX_COL | `age_at_dx` | stop() prints available columns |
| PAYER_CAT_COL | `payer_cat` | stop() prints available columns |
| FAR_COL | `far_from_care_100mi` | stop() prints available columns |
| SOURCE_COL | `SOURCE` | stop() prints available columns |
| TR_TX_COLS | `rx_summ_treatment_status`, `rx_summ_systemic_surg_seq` | stop() prints available columns |

Before running R/203 on HiPerGator: run the probe_inputs() call in
203_schema_PENDING.md, paste the resulting 203_schema_<date>.md, and update
the candidate constants above to match confirmed names.

## Known Stubs

TR_TX_COLS candidate names (`rx_summ_treatment_status`, `rx_summ_systemic_surg_seq`)
are unconfirmed — real column names depend on the HiPerGator probe. The stop()
guard will halt the script and print available names if they differ. Plan 203-02
cannot be considered fully wired until the probe runs and constants are updated.

## Self-Check: PASSED

- R/203_no_treatment_characterization.R — found and updated (commit 8f8317e)
- Commit 8f8317e present in git log
- tools/rcheck.sh parse R/203_no_treatment_characterization.R — exits 0
- grep PERI_DX_WINDOW_DAYS <- 90L — 1 match
- grep window_truncated — 4 matches
- grep open_pcornet_con() — 2 matches (open + guard)
- grep close_pcornet_con() — 1 match
- grep DBI::dbDisconnect — 0 matches
- grep WINDOW_START_COL — 7 matches (constant + stop() guard + uses)
- grep registry_says_tx_pipeline_missed — 3 matches
- grep registry_tx_given — 6 matches
- grep age_group_dx — 5 matches
- grep hl_subtype — 4 matches
- grep single_source_care — 6 matches (join + summary)
- grep TR_TX_COLS — 9 matches (definition + stop() guard + uses)
