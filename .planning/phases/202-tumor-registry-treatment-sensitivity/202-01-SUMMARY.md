---
phase: 202
plan: 01
subsystem: tumor-registry-sensitivity
tags: [scaffold, pin, IS_LOCAL, join-logic, PENDING-PROBE]
dependency_graph:
  requires: [R/00_config.R, R/utils/utils_duckdb.R, R/193 output RDS, gantt_episodes_180 CSV]
  provides: [R/202_tr_sensitivity.R Sections 1-4]
  affects: [202-02 (comparison logic), 202-03 (workbook output)]
tech_stack:
  added: []
  patterns: [env-var pin, IS_LOCAL guard, fmt_sup suppression, open/close_pcornet_con pair]
key_files:
  created: [R/202_tr_sensitivity.R]
  modified: []
decisions:
  - "TR_IMMUNO_COLS left as character(0) pending HiPerGator schema probe (Task 0)"
  - "TR_SCT_DATE_COLS lists 7 candidate names; intersect() makes it safe before probe"
  - "gantt_pts uses slice(1L) after group_by(patient_id) — tr_hl_dx/tr_nhl_dx are patient-constant per R/88 Phase 201"
metrics:
  duration: "15 min"
  completed: "2026-11-14"
  tasks_completed: 3
  files_created: 1
---

# Phase 202 Plan 01: Schema probe + R/202 scaffold with join logic Summary

R/202_tr_sensitivity.R created with IS_LOCAL guard, four pinned env vars, PENDING-PROBE TR column constants, small-cell suppression helpers, and Section 1–4 join logic building the sensitivity denominator (~600 TR-HL patients in gantt) and footnote population (121 TR-HL patients not in gantt).

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 0 | PENDING HIPERGATOR — schema probe steps documented in PLAN.md; cannot run locally | — |
| 1 | Created R/202_tr_sensitivity.R scaffold (banner, packages, IS_LOCAL guard, pins, constants) | 90214df |
| 2 | Appended Sections 1-4 (load gantt, load TR flags, load TR treatment cols, build populations) | 90214df |

## Deviations from Plan

None — plan executed exactly as written. Task 0 is documented as PENDING HIPERGATOR in the plan itself; it is not a deviation.

## Known Stubs

- `TR_IMMUNO_COLS <- character(0)` — immunotherapy column name unknown until HiPerGator probe runs. Downstream comparison logic (Plan 202-02) must check `length(tr_immuno_present) > 0` before attempting immunotherapy sensitivity calculation.
- `TR_SCT_DATE_COLS` lists 7 candidate names; actual names confirmed only after probe. The `intersect()` call in Section 3 makes this safe — no columns will be selected until at least one candidate name matches.
- Default `tr_flags_path` contains literal `<DATED>` placeholder — user must set `R202_TR_FLAGS` env var before running on HiPerGator (script stops with a clear message if the file is missing).

## Self-Check: PASSED

- R/202_tr_sensitivity.R: FOUND
- Commit 90214df: FOUND
