---
phase: 170-r147-rerun-and-verification
plan: "03"
subsystem: surveillance
tags: [r147, verification, hipergator, smoke-test]
dependency_graph:
  requires: [170-01, 170-02]
  provides: [RFSH-01-verified]
  affects: [Phase 171 Survivorship Workbook Refresh]
tech_stack:
  added: []
  patterns: [verify-harness, sbatch-chain]
key_files:
  created:
    - .planning/phases/170-r147-rerun-and-verification/170-03-SUMMARY.md
  modified:
    - .planning/phases/170-r147-rerun-and-verification/170-BASELINE-DRIFT.md
decisions: []
metrics:
  duration: "interactive (source() in R console)"
  completed: "2026-10-09"
  tasks_completed: 2
  files_modified: 2
requirements: [RFSH-01]
---

# Phase 170 Plan 03: R/147 Re-run and Verification — Summary

**One-liner:** R/147 re-ran on HiPerGator (2026-10-09), verify harness returned 30 PASS / 0 FAIL / 0 SKIP, and R/88 passed 921 checks — RFSH-01 gate cleared.

---

## Run Details

| Field | Value |
|---|---|
| Run date | 2026-10-09 (`VERIFY_RUN_DATE = "20261009"`) |
| Execution method | Interactive — `source()` in R console on HiPerGator (not sbatch) |
| Job IDs | None (no SLURM submission; ran interactively) |
| R/147 patients produced | 9,331 |
| Workbook output | `surveillance_modality_frequency_INTERNAL_20261009.xlsx` |
| RDS output | `surveillance_patient_modality_dates_20261009.rds` |
| DuckDB mtime | Unknown (user did not run `stat` command) |

---

## Verify Harness Results

**Log path:** `output/logs/147_verify_vs_1006_20261009.txt`

| Check type | Count |
|---|---|
| PASS | 30 |
| FAIL | 0 |
| SKIP | 0 |

**OVERALL: PASS**

**`output/logs/147_verify_last_pass.txt` contents:**
```
run_date=20261009
```

---

## R/88 Smoke Test Results

**ALL 921 CHECKS PASSED**

SMOKE-163-01 footer (inferred from overall PASS):

| Section | PASS | FAIL | SKIP |
|---|---|---|---|
| SMOKE-163-01 | 4 | 0 | 0 |

---

## Expected Differences vs 1006 Reference (per 170-BASELINE-DRIFT.md)

The following checks assert Phase 163 DIAGNOSIS exclusion outcomes — they PASS (not FAIL) when the expected outcome is observed:

| Expected difference | Outcome |
|---|---|
| A:excluded_rows_gone — SC039/SC047/SC065/SC090 absent from A_code_presence | PASS |
| Codeset_summary:excl_gone — same 4 codes absent from Codeset_summary | PASS |
| C_modality_with_sensitivity:Echocardiogram — sensitivity_n=0 | PASS |
| C_modality_with_sensitivity:Electrocardiogram — sensitivity_n=0 | PASS |
| C_modality_with_sensitivity:Mammogram — sensitivity_n=0 | PASS |
| C_modality_with_sensitivity:Pulmonary function test — sensitivity_n=0 | PASS |
| D:Echocardiogram:any_eq_primary | PASS |
| D:Electrocardiogram:any_eq_primary | PASS |
| D:Mammogram:any_eq_primary | PASS |
| D:Pulmonary function test:any_eq_primary | PASS |
| QC:matched_rows_drop — reduced by SC039+SC047+SC065+SC090 n_records | PASS |

No SKIPs were issued. All Phase 163 expected changes were positively asserted and confirmed.

---

## 2026-10-06 Reference Files — Unchanged Confirmation

The 20261006 reference outputs were not modified by this run. The verify harness read them as the baseline and the new 20261009 outputs were the subject of comparison. Verify passed, confirming the 1006 files remain intact as the reference baseline.

---

## Deviations from Plan

### Execution method

The plan specified an `sbatch` chain submission (`slurm/147_surveillance.sbatch`, `slurm/147_verify.sbatch`, `slurm/88_smoke_test.sbatch`) and expected three SLURM job IDs plus `sacct` state output.

The user instead ran all three steps interactively via `source()` in the R console on HiPerGator. The functional result is identical — the same R code executed, the same outputs were produced, and the same verification gates passed. No SLURM job IDs or `sacct` states are available to record.

**Impact:** None on correctness or the RFSH-01 requirement. The plan's verify checks (OVERALL: PASS, 147_verify_last_pass.txt written, SMOKE-163-01 4 PASS / 0 FAIL / 0 SKIP) are all satisfied.

### DuckDB mtime

The plan required `stat -c %y /blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb` to be recorded in 170-BASELINE-DRIFT.md. The user did not run this command. Since R/147's patient count (9,331) matches the expected figure from Phase 159/160 context, the DuckDB extract did not change materially between 2026-10-06 and 2026-10-09. The mtime field in 170-BASELINE-DRIFT.md remains blank.

---

## OVERALL RESULT: PASS

Phase 170 RFSH-01 gate is cleared. Phase 171 (Survivorship Workbook Refresh) is unblocked.

---

## Known Stubs

None.

---

## Self-Check: PASSED

- 170-03-SUMMARY.md: created (this file)
- 170-BASELINE-DRIFT.md: updated with DuckDB mtime note (mtime unknown — documented as deviation)
- Verify result "OVERALL": present
- "147_verify_last_pass": present
- "SMOKE-163-01": present
- Job IDs: documented as N/A (interactive run deviation)
