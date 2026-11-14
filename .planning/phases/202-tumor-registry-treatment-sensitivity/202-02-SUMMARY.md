---
phase: 202
plan: 02
subsystem: tumor-registry-sensitivity
tags: [classify_capture, sensitivity, PPV, xlsx, suppression]
dependency_graph:
  requires: [R/202_tr_sensitivity.R Sections 1-4, gantt_episodes_180, TUMOR_REGISTRY_ALL, confirmed_hl_cohort.rds]
  provides: [R/202_tr_sensitivity.R Sections 5-14, output/202_tr_sensitivity_YYYYMMDD.xlsx]
  affects: [202-03 (HiPerGator run and verification)]
tech_stack:
  added: []
  patterns: [rowwise classify_capture, case_when tier ladder, openxlsx styled workbook, UF colours]
key_files:
  created: []
  modified: [R/202_tr_sensitivity.R]
decisions:
  - "capture_tier 'not_datable' added for SCT patients where TR code confirms treatment but no date available (sentinel 1900-01-01)"
  - "Immunotherapy sheet_A row will show n_denom=0 until PENDING-PROBE fills TR_IMMUNO_COLS — correct behavior"
  - "B_date_diff footnote row uses raw n_footnote (121) with no suppression — it is a population count, not a patient count in the analytic denominator"
metrics:
  duration: "10 min"
  completed: "2026-11-14"
  tasks_completed: 3
  files_created: 0
  files_modified: 1
---

# Phase 202 Plan 02: Capture classification + all output sheets + xlsx Summary

R/202_tr_sensitivity.R extended with classify_capture() function, four sensitivity sheets (A-D), PPV_reverse, QC, and KEY sheets, and styled xlsx output with UF colours.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Sections 5-6: TRTYPES map, tr_first_date(), gantt_first, classify_capture() | 87881bb |
| 2 | Sections 7-10: A_sensitivity, B_date_diff, C_by_source, D_by_year | 87881bb |
| 3 | Sections 11-14: PPV_reverse, QC, KEY, xlsx with UF colours | 87881bb |

## Deviations from Plan

**1. [Rule 2 - Missing field] Added `not_datable` capture tier**
- Found during: Task 1
- Issue: Plan's capture_tier case_when had no branch for SCT patients where the code column confirms treatment but no date exists (sentinel 1900-01-01). Without this, they would fall through to `not_captured`, misclassifying them.
- Fix: Added `not_datable` branch in classify_capture() between the `no_registry` and `exact` checks.
- Files modified: R/202_tr_sensitivity.R
- Commit: 87881bb

**2. [Rule 1 - Bug] Removed stray `tr_code_cols` field in radiation TRTYPES entry**
- Found during: Task 1
- Issue: Plan's TRTYPES code had `tr_code_cols = NULL` (plural) alongside `tr_code_col = NULL` in the radiation list — an inconsistent field name that could cause confusion in tr_first_date(). The function only reads `tr_code_col` (singular).
- Fix: Removed the stray `tr_code_cols` field from the radiation list definition.
- Files modified: R/202_tr_sensitivity.R
- Commit: 87881bb

## Known Stubs

- `TR_IMMUNO_COLS <- character(0)` carries forward from Plan 202-01 — immunotherapy column name unknown until HiPerGator probe. All immunotherapy classify_capture() results will be `no_registry` until resolved.
- `tr_flags_path` default contains `<DATED>` placeholder — user must set `R202_TR_FLAGS` before HiPerGator run.

## Self-Check: PASSED

- R/202_tr_sensitivity.R parse check: PASSED (tools/rcheck.sh parse exits 0)
- Commit 87881bb: FOUND
- classify_capture function: FOUND
- capture_tier values exact/within_30d/within_90d/not_captured/no_registry: FOUND
- sheet_A/B/C/D/PPV/QC/KEY: FOUND
- KEY added first in workbook: FOUND (write_sheet(wb, "KEY", ...) before A_sensitivity)
- uf_blue "#0021A5" and uf_orange "#FA4616": FOUND
- cohort_rds_path (not bare CONFIG call) in Section 10: FOUND
- No IN() patient ID lists: CONFIRMED
- No DBI::dbDisconnect: CONFIRMED
