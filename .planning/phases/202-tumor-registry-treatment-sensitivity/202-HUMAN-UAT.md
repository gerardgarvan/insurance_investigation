---
status: partial
phase: 202-tumor-registry-treatment-sensitivity
source: [202-VERIFICATION.md]
started: 2026-11-14T00:00:00Z
updated: 2026-11-14T00:00:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. HiPerGator schema probe (TRVAL-01)
expected: Run Task 0 probe from 202-01-PLAN.md on HiPerGator; write `.planning/schemas/202_schema_tr_treatment_cols_YYYYMMDD.md`; update PENDING-PROBE constants in R/202_tr_sensitivity.R (especially TR_IMMUNO_COLS).
result: [pending]

### 2. Full R/202 execution on HiPerGator (TRVAL-02 through TRVAL-06)
expected: Denominator ≈600, footnote 121; xlsx written with sheets KEY, A_sensitivity, B_date_diff, C_by_source, D_by_year, PPV_reverse, QC.
result: [pending]

### 3. R/88 SECTION 15be workbook checks (TRVAL-07)
expected: Set R202_SENSITIVITY_XLSX to the written xlsx path; rerun R/88 SECTION 15be; workbook checks PASS (KEY leftmost, all 7 sheets present, at least one '<11' in A_sensitivity).
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
