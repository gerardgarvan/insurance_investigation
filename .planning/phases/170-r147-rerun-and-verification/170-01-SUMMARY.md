---
phase: 170-r147-rerun-and-verification
plan: 01
subsystem: verification-harness
tags: [surveillance, verify, slurm, phase-163]
dependency_graph:
  requires: [163-01, 162-01]
  provides: [170-01-verify-harness]
  affects: [171-survivorship-refresh, 172-phase-164-closeout]
tech_stack:
  added: []
  patterns: [run_check/tryCatch pattern, sink-first OVERALL pattern, VERIFY_RUN_DATE env var]
key_files:
  created:
    - .planning/phases/170-r147-rerun-and-verification/170-BASELINE-DRIFT.md
    - slurm/147_surveillance.sbatch
    - slurm/147_verify.sbatch
  modified:
    - R/147_verify_vs_1006.R
decisions:
  - EXPECTED_DIFFS = character(0) — all Phase 163 outcomes are positively asserted; no checks skip
  - Sink opens before any check; inputs-missing records FAIL, never stop()
  - Column names discovered from readRDS() at runtime; missing columns FAIL explicitly
metrics:
  duration_minutes: 25
  tasks_completed: 3
  files_changed: 4
  completed_date: "2026-10-09"
requirements_met: [RFSH-01]
---

# Phase 170 Plan 01: Verify Harness and sbatch Wrappers Summary

**One-liner:** Fail-safe PASS/FAIL verify harness (R/147_verify_vs_1006.R) comparing INTERNAL-to-INTERNAL outputs with Phase 163 exclusion accounting, plus two SLURM sbatch wrappers.

## What Was Built

### Task 0 — Baseline Drift (170-BASELINE-DRIFT.md)

Recorded that no R/147 input files changed since 2026-10-06. The R/00_config.R commits since 1006 (Phases 165/168) added unrelated CONFIG keys and do not affect surveillance outputs. Phase 163 DIAGNOSIS exclusion is the only change affecting R/147's output — it is the expected, intended change. DuckDB mtime fill-in slot provided for HiPerGator pre-flight.

**expected_differences = character(0)** — all Phase 163 outcomes are positively asserted by specific check names, none need to be skipped.

### Task 1 — R/147_verify_vs_1006.R (full rewrite)

The old script used a `which.max(file.mtime())` glob to find the newest INTERNAL workbook, compared against a release workbook (wrong reference), used `stop()` on missing files, and had no sink/log. The new harness:

- `VERIFY_RUN_DATE` env var drives all paths and log filename; no globs
- Compares INTERNAL-to-INTERNAL (`surveillance_modality_frequency_INTERNAL_20261006.xlsx` vs `..._<run_date>.xlsx`)
- Sink opens at line 53, before any check — OVERALL always written
- Missing input files → `FAIL` result entries, never `stop()`
- All checks via `run_check()` / `tryCatch()` — errors become FAIL, not crashes
- 10 check groups (E1–E10), ~25 individual check entries

**Check inventory:**
| Check | What it verifies |
|-------|-----------------|
| KEY:denominator_N | "Denominator N" == ref (expect 9,331) |
| KEY:confirmed_cohort_N | "Confirmed-cohort N" == ref (expect 9,282) |
| QC:total_person_years | "Total person-years" == ref (expect 40,298.9) |
| B_modality_primary:identical | B sheet byte-identical |
| A2_analyte_presence:identical | A2 sheet byte-identical |
| A3_missing_analyte:identical | A3 sheet byte-identical (was missing before) |
| A_code_presence:ref_minus_excl_eq_new | ref minus 4 excluded rows == new |
| A:excluded_rows_gone | SC039/047/065/090 absent from new, present in ref |
| Codeset_summary:excl_gone | excluded IDs absent; 14 modality blocks |
| Codeset_summary:no_z_codes | no Z-code pattern in any cell |
| C:primary_all_14 | C primary_* columns identical for all 14 modalities |
| C:changed_mod:{4 mods} | sensitivity_n=0; any_n == primary_n |
| D:primary_all_14_eq_ref | D primary rows identical to ref |
| D:changed_mod:{4 mods}:any_eq_primary | D any row == primary row for changed mods |
| D:unaffected_any_eq_ref | D any rows identical to ref for 10 unaffected mods |
| QC:matched_rows_drop | drop = sum(ref A n_records for excluded IDs) |
| QC:excluded_row_present | "Codeset rows excluded (DIAGNOSIS)" present |
| QC:old_diag_row_absent | "DIAGNOSIS rows collected" absent |
| KEY:163_D01_note | "163 D-01" note present in KEY |
| residue:diagnosis_text | no disallowed "diagnosis" occurrences in sheets |
| RDS:same_ids | identical patient ID sets |
| RDS:primary_cols | primary columns equal to ref (all.equal) |
| RDS:changed_any_eq_primary | changed mod _any == primary in new RDS |
| RDS:unaffected_any_eq_ref | unaffected _any == ref |

On OVERALL: PASS only, writes `output/logs/147_verify_last_pass.txt` with run_date, log, rds, workbook paths.

### Task 2 — sbatch Wrappers

**147_surveillance.sbatch:** 4 CPUs, 32gb, 4h; `set -e`; `module load R/4.5`; logs to `logs/147_surveillance_${VERIFY_RUN_DATE}.log`.

**147_verify.sbatch:** 2 CPUs, 16gb, 1h; no `set -e`; captures `rc=$?`; `echo "verify exit: $rc"`; `exit $rc`. Both include VERIFY_RUN_DATE handling and midnight-crossing caveat.

## Deviations from Plan

None — plan executed exactly as written. The `%||%` helper was defined inline (not in plan) as a minor convenience for NULL-guarding `read_sheet()` returns; this is an additive implementation detail, not a deviation from any plan requirement.

## Self-Check

- [x] 170-BASELINE-DRIFT.md exists with `expected_differences:` section
- [x] R/147_verify_vs_1006.R: `VERIFY_RUN_DATE`, `EXCLUDED_IDS`, `A:excluded_rows_gone`, `RDS:changed_any_eq_primary`, `RDS:unaffected_any_eq_ref`, `147_verify_last_pass.txt`, `n_skip` all present
- [x] Sink at line 53, before first run_check at line 101
- [x] No `which.max(file.mtime`, no `rds_dir`, no plain `surveillance_modality_frequency_20261006.xlsx`
- [x] slurm/147_surveillance.sbatch: `module load R/4.5` present, `set -e` present
- [x] slurm/147_verify.sbatch: `module load R/4.5` present, `exit $rc` as last meaningful line, no `set -e`

## Self-Check: PASSED
