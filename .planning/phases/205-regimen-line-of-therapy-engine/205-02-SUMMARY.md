---
phase: 205-regimen-line-of-therapy-engine
plan: "02"
subsystem: regimen-classification
tags: [regimen, lot, wiring, R28, R142, R205, smoke-test]
dependency_graph:
  requires: [205-01]
  provides: [regimen_label in stage2 RDS, line_of_therapy in stage2 RDS, lot_summary_p205]
  affects: [R/28_episode_classification.R, R/142_gantt_180_export.R, R/205_lot_output.R, R/88_smoke_test_comprehensive.R]
tech_stack:
  added: [R/205_lot_output.R]
  patterns: [assign_regimen-wiring, column-rename-shim, smoke-test-pattern]
key_files:
  created:
    - R/205_lot_output.R
  modified:
    - R/28_episode_classification.R
    - R/142_gantt_180_export.R
    - R/88_smoke_test_comprehensive.R
decisions:
  - "assign_regimen() output joined to episodes by patient_id (not ID) — column rename shim applied before assign_lot() call and restored after"
  - "Phase 201b relabel block removed from R/142; abvd_class now sourced directly from regimen_label column in stage2 RDS"
  - "R/205 calls assign_lot() independently — stage2 already has line_of_therapy from R/28 but R/205 recomputes for standalone summary"
  - "SMOKE-205-01 [g] check for REGL-06-decisions.md will FAIL until Plan 03 creates the file — expected and noted"
metrics:
  duration_minutes: 15
  completed_date: "2026-11-14"
  tasks_completed: 3
  tasks_total: 4
  files_created: 1
  files_modified: 3
---

# Phase 205 Plan 02: Regimen + LOT Engine Wiring Summary

**One-liner:** assign_regimen() and assign_lot() wired into R/28 replacing the case_when + jcode fallback block; Phase 201b relabel block removed from R/142; R/205_lot_output.R writes per-patient LOT summary; R/88 SMOKE-205-01 regression section appended.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Replace regimen detection in R/28 with assign_regimen() + assign_lot() | 5435667 | R/28_episode_classification.R |
| 2 | Remove Phase 201b relabel from R/142; create R/205_lot_output.R | fbf8f3b | R/142_gantt_180_export.R, R/205_lot_output.R |
| 3 | Add SMOKE-205-01 section to R/88 | 53d8a2f | R/88_smoke_test_comprehensive.R |
| 4 | HiPerGator pipeline run verification | — | checkpoint:human-verify (pending) |

## What Was Built

**R/28_episode_classification.R** — Steps 5d/5e/5f/5g replaced:
- Added `source(here::here("R", "utils", "utils_regimen.R"), local = TRUE)` in header
- Built `date_level_drugs` from `episode_detail` (one row per drug-date; `drug_name` -> `canonical_drug`)
- Called `assign_regimen(date_level_df, REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS)` and joined result to `episodes` by `patient_id` + `episode_number`
- Called `assign_lot()` with column rename shim (`patient_id` -> `ID`, `episode_start` -> `start_date`, `episode_stop` -> `end_date`), then restored names
- `episodes` now contains `regimen_label` (character) and `line_of_therapy` (integer)

**R/142_gantt_180_export.R** — Phase 201b relabel block removed:
- SECTION 4C4 simplified: `abvd_class <- episodes_export$regimen_label` with chemotherapy filter
- Removed: classify_abvd_episode() call, immuno_admin/chemo_span/conc/bv_span steps, abvd_class_pre, n_relabel_* variables, is_chemo vector
- D-08 QC block cleaned: removed pre-relabel rows and 201b relabel count messages; abvd_class distribution reporting preserved

**R/205_lot_output.R** — new standalone LOT summary script (four sections):
- Section 0: Pins (four env vars), KEY tibble, fail-fast file checks
- Section 1: sources R/00_config.R and utils_regimen.R; loads stage2 RDS
- Section 2: calls assign_lot() with column rename shim; prints LOT distribution
- Section 3: dplyr::summarise() per patient — ID, line_1_regimen, line_1_start, n_lines, regimen_per_line; writes RDS + CSV (REGL-07)
- Section 4: Gantt column regression guard against 32 expected columns (REGL-08)

**R/88_smoke_test_comprehensive.R** — SECTION 15bg appended:
- 22 SMOKE-205-01 labeled checks across [a]–[h3]
- File-existence, function-definition, config-constant, jcode_regimen removal, Phase 201b removal checks run locally
- LOT output and reconciliation CSV checks wrapped in file.exists() with SKIP fallback for local runs

## Verification

```
tools/rcheck.sh parse R/28_episode_classification.R R/142_gantt_180_export.R R/205_lot_output.R R/88_smoke_test_comprehensive.R
# -> 4 files parsed, 0 failed
```

HiPerGator verification: checkpoint:human-verify pending (see plan task 4).

## Deviations from Plan

**1. [Rule 1 - Bug] Column name mismatch — patient_id vs ID in assign_regimen/assign_lot**
- **Found during:** Task 1
- **Issue:** `assign_regimen()` returns `ID` and `episode_number`; `episodes` in R/28 uses `patient_id`. `assign_lot()` requires `ID`, `start_date`, `end_date` but `episodes` uses `patient_id`, `episode_start`, `episode_stop`. Plan code assumed these matched.
- **Fix:** Joined `regimen_assignments` back using `dplyr::rename(patient_id = ID)`. Added column rename shim before `assign_lot()` call and restored names after. Same shim applied in R/205_lot_output.R.
- **Files modified:** R/28_episode_classification.R, R/205_lot_output.R

**2. [Rule 1 - Bug] date_level_drugs source — `ma_dates` does not exist in R/28**
- **Found during:** Task 1
- **Issue:** Plan code referenced `ma_dates %>% filter(!is.na(canonical_drug))` but no such variable exists in R/28. The date-level frame is `episode_detail` with column `drug_name` (not `canonical_drug`), `episode_start` (not `start_date`).
- **Fix:** Built `date_level_drugs` from `episode_detail` using correct column names, renaming `drug_name` -> `canonical_drug` and `episode_start` -> `start_date` in the select.
- **Files modified:** R/28_episode_classification.R

**3. [Rule 1 - Adaptation] QC block in R/142 referenced removed variables**
- **Found during:** Task 2
- **Issue:** The D-08 QC block used `abvd_class_pre`, `is_chemo`, `n_relabel_bv`, `n_relabel_nivo`, `n_relabel_plus`, `n_bv_span_not_admin` — all defined in the removed Phase 201b block. R/142 would not parse if left as-is.
- **Fix:** Removed the pre-relabel and relabel-count subsections from the QC block; kept per-class and per-patient counts (which only reference the final `abvd_class` vector).
- **Files modified:** R/142_gantt_180_export.R

## Known Stubs

None. `regimen_label` is wired from `assign_regimen()` through `episode_detail`. `line_of_therapy` is computed by `assign_lot()`. The LOT summary script (R/205) is complete; output depends on a HiPerGator run.

## Open Items Carried Forward

- REGL-06: SME confirmation of LOT_GAP_DAYS (90d default) still pending.
- Plan 03: Reconciliation CSV (regimen_reconciliation_p205.csv) and REGL-06-decisions.md — SMOKE-205-01 [g] and [h] will SKIP until Plan 03 completes.
- HiPerGator verification: Run R/26 -> R/28 -> R/142 -> R/205 -> R/88 and paste back five message blocks (see plan task 4 checkpoint).

## Self-Check: PASSED

Files confirmed present:
- R/28_episode_classification.R — FOUND (modified)
- R/142_gantt_180_export.R — FOUND (modified)
- R/205_lot_output.R — FOUND (created)
- R/88_smoke_test_comprehensive.R — FOUND (modified)

Commits confirmed:
- 5435667 (Task 1 — R/28)
- fbf8f3b (Task 2 — R/142 + R/205)
- 53d8a2f (Task 3 — R/88)

## Run 5 close-out (2026-11-14)

- HiPerGator run 5 (commit 466b0f9): R/28, R/142, R/205 completed; QC all pass. Candidate NOT shipped; see `205-VERIFICATION.md`, `205-TEAM-SUMMARY.md`, `REGL-06-decisions.md`.
