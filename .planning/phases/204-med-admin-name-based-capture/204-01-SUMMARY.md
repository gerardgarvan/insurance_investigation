---
phase: 204-med-admin-name-based-capture
plan: "01"
subsystem: treatment-capture
tags: [med-admin, name-capture, chemo-detection, utils-treatment, R26]
dependency_graph:
  requires: []
  provides:
    - get_chemo_hits() name-based capture tier (MED_ADMIN_NAME source tag)
    - R/26 pre-capture snapshot (treatment_episodes_pre_p204.rds)
    - Before/after count report for Rituximab / Brentuximab Vedotin / Methotrexate
  affects:
    - R/26_treatment_episodes.R (ma_dates now includes name-matched rows)
    - Downstream: R/28, R/29, R/52, R/142 (all consume stage1 RDS)
tech_stack:
  added: []
  patterns:
    - canonicalize_drug_name() / DRUG_NAME_ALIASES as sole name-matching path
    - MCAP-05 safety gate pattern (halt on unexpected alias-resolved canonical)
    - Anti-join de-duplication against existing code-based capture
key_files:
  created: []
  modified:
    - R/utils/utils_treatment.R
    - R/26_treatment_episodes.R
decisions:
  - "DRUG_NAME_ALIASES values (not keys) define the known canonical set for MCAP-05"
  - "Anti-join on (ID, treatment_date) excludes rows already captured by RX/ND paths"
  - "Pre-capture snapshot is idempotent: skips if output/internal/treatment_episodes_pre_p204.rds already exists"
metrics:
  duration_minutes: 10
  completed_date: "2026-11-14"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 2
---

# Phase 204 Plan 01: Name-Based MED_ADMIN Capture Summary

One-liner: Added `return_name_capture = TRUE` tier to `get_chemo_hits("MED_ADMIN", ...)` using `canonicalize_drug_name()` on `RAW_MEDADMIN_MED_NAME`; wired into R/26 with pre-capture snapshot and before/after count report.

## Tasks Completed

| # | Name | Commit | Files |
|---|------|--------|-------|
| 1 | Extend get_chemo_hits() with name-based capture tier | 8086179 | R/utils/utils_treatment.R |
| 2 | Wire name-based capture in R/26 and save pre-capture snapshot | 1839db5 | R/26_treatment_episodes.R |

## What Was Built

**Task 1 — `R/utils/utils_treatment.R`:**

- Added `return_name_capture = FALSE` parameter after `return_source` in `get_chemo_hits()` signature. Existing callers (R/10, R/11, R/25, R/76, R/20, R/109) pass neither argument and are unaffected.
- Inside the `MED_ADMIN` branch, after `result <- bind_rows(rx_hits, nd_hits)`, a new sub-block:
  - Collects non-RX/ND rows with a non-blank `RAW_MEDADMIN_MED_NAME`
  - Canonicalizes via `canonicalize_drug_name(toupper(trimws(raw_name)))`
  - MCAP-05 safety gate: `stop()` if any alias-resolved canonical is not in `unique(unname(DRUG_NAME_ALIASES))`
  - Keeps only rows whose canonical IS in the known set
  - Sets `triggering_code = paste0("NAME:", canonical)`, `source = "MED_ADMIN_NAME"`
  - Anti-joins against existing result on `(ID, treatment_date)` — only new observations added
- `keep_cols` guard updated: `raw_med_name` is included when `return_raw_name || return_name_capture` is TRUE (name_hits always carries `raw_med_name`; prior rx/nd rows already have `raw_med_name` from their existing path).

**Task 2 — `R/26_treatment_episodes.R`:**

- Pre-capture snapshot block (Edit A): before `ma_dates` call, saves `output/internal/treatment_episodes_pre_p204.rds` from the existing `OUTPUT_RDS` if snapshot does not yet exist. Idempotent — logs "already exists" on subsequent runs. If no prior stage1 RDS exists, logs "new from this run".
- `ma_dates` call (Edit B): added `return_source = TRUE, return_name_capture = TRUE` (MCAP-01).
- Before/after count report (Edit C): after the `raw_name_lookup` block, filters `ma_dates` for `source == "MED_ADMIN_NAME"` rows; groups by canonical drug; prints records/patients with `<11` suppression; explicitly reports 0 for Rituximab, Brentuximab Vedotin, Methotrexate when not present (MCAP-02).

## Verification

- `tools/rcheck.sh parse R/utils/utils_treatment.R R/26_treatment_episodes.R` — both exit 0
- Acceptance grep checks all pass: `return_name_capture` (5 lines), `MED_ADMIN_NAME` (2 lines), `paste0("NAME:"` (1 line), `MCAP-05` (3 lines), `pre_p204` (2 lines), `MCAP-01` (2 lines), `MCAP-02` (1 line)

## Deviations from Plan

None — plan executed exactly as written.

## HiPerGator Run Steps (Plan 02 prerequisite)

Gerard should run R/26 on HiPerGator to generate `treatment_episodes_pre_p204.rds` and see the Phase 204 name-capture count report. Paste back the `[R/26] Phase 204` console lines.

```r
module load R/4.5
R --no-save
source("R/26_treatment_episodes.R", local = new.env(parent = globalenv()))
```

Paste back: all lines starting with `[R/26] Phase 204`.

## Known Stubs

None. No hardcoded placeholders — all logic is wired to live data paths.

## Self-Check: PASSED

- `R/utils/utils_treatment.R` — file exists, modified, committed 8086179
- `R/26_treatment_episodes.R` — file exists, modified, committed 1839db5
- Both commits present in `git log --oneline -5`
