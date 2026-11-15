---
status: partial
phase: 203-no-treatment-patient-characterization
source: [203-VERIFICATION.md]
started: 2026-11-14
updated: 2026-11-14
---

## Current Test

[awaiting human testing]

## Tests

### 1. HiPerGator schema probe — confirm column names
expected: Run `probe_inputs("203", ...)` from `.planning/schemas/203_schema_PENDING.md` on HiPerGator; update `WINDOW_START_COL` and `TR_TX_COLS` constants in `R/203_no_treatment_characterization.R` to confirmed names; script runs without stop() errors
result: passed — probe run 2026-11-14; schema in .planning/schemas/203_schema_inputs_20261114.md; R/203 updated in quick 261114-r5e

### 2. Full pipeline run and workbook QC
expected: Script produces workbook with no-treatment count ≈ 3,246 and treated count ≈ 4,450; six sheets in order KEY / A_profile / B_reasons_waterfall / C_by_source / D_candidate_rules / QC; all counts < 11 show "<11"; UF colours present; internal RDS written to output/internal/
result: [pending]

## Summary

total: 2
passed: 1
issues: 0
pending: 1
skipped: 0
blocked: 0

## Gaps
