---
phase: 203-no-treatment-patient-characterization
plan: "01"
subsystem: no-treatment-characterization
tags: [scaffold, cohort-split, schema-probe, pinned-inputs]
dependency_graph:
  requires: [confirmed_hl_cohort.rds, R/169 output, R/193 output, gantt_episodes_180.csv]
  provides: [R/203_no_treatment_characterization.R scaffold, 203_schema_PENDING.md]
  affects: [plan 203-02 join code]
tech_stack:
  added: []
  patterns: [IS_LOCAL guard, Sys.getenv pinned inputs, TX_COUNT_COL named constant, pin_info list]
key_files:
  created:
    - R/203_no_treatment_characterization.R
    - .planning/schemas/203_schema_PENDING.md
  modified:
    - R/SCRIPT_INDEX.md
decisions: []
metrics:
  duration_minutes: 15
  completed_date: "2026-11-14"
  tasks_completed: 3
  tasks_total: 3
  files_created: 2
  files_modified: 1
---

# Phase 203 Plan 01: No-Treatment Scaffold and Schema Probe Summary

Established the Phase 203 input contract: R/203 scaffold parses clean on the
local machine, pins all four inputs via R203_* env vars with stop() guards,
defines TX_COUNT_COL as a named constant (confirmed by HiPerGator probe before
Plan 203-02 uses it), and splits confirmed_hl_cohort.rds into no_tx/treated
with a membership-preserving stopifnot. Schema probe placeholder (PENDING
HiPerGator) blocks any join code until column names are confirmed.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 0 | Schema probe placeholder | ce40049 | .planning/schemas/203_schema_PENDING.md |
| 1 | R/203 scaffold with pinned inputs and cohort split | 29fc141 | R/203_no_treatment_characterization.R |
| 2 | Register R/203 in SCRIPT_INDEX.md | e5b4597 | R/SCRIPT_INDEX.md |

## Deviations from Plan

None — plan executed exactly as written.

The IS_LOCAL guard was implemented using the existing `R203_RUN_LOCAL` bool
(checking file.exists on the COHORT_RDS path) rather than the global `IS_LOCAL`
from 00_config.R, because sourcing 00_config.R first would already emit
IS_LOCAL before the guard. The approach follows the same pattern as R/202
(which uses IS_LOCAL from config), but Phase 203 defines its own local-check
var to avoid ordering issues. This is equivalent and consistent with CLAUDE.md
pinning conventions.

## Known Stubs

None. No join code, no table output, and no data reads in this scaffold plan.
All NOTX tables and the probe result are deferred to Plan 203-02.

## Self-Check: PASSED

- R/203_no_treatment_characterization.R — found (created this plan)
- .planning/schemas/203_schema_PENDING.md — found (created this plan)
- R/SCRIPT_INDEX.md row for R/203 — confirmed by grep
- Commits ce40049, 29fc141, e5b4597 — all present in git log
