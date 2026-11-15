---
status: complete
phase: 202-tumor-registry-treatment-sensitivity
source: [202-VERIFICATION.md]
started: 2026-11-14T00:00:00Z
updated: 2026-11-14T00:00:00Z
---

## Current Test

[all tests complete]

## Tests

### 1. HiPerGator schema probe (TRVAL-01)
expected: Run Task 0 probe from 202-01-PLAN.md on HiPerGator; write `.planning/schemas/202_schema_tr_treatment_cols_YYYYMMDD.md`; update PENDING-PROBE constants in R/202_tr_sensitivity.R (especially TR_IMMUNO_COLS).
result: done 2026-11-14 — probe saved at .planning/schemas/202_schema_tr_treatment_cols_20261114.md; constants applied in quick 261114-qj1

### 2. Full R/202 execution on HiPerGator (TRVAL-02 through TRVAL-06)
expected: Denominator ≈600, footnote 121; xlsx written with sheets KEY, A_sensitivity, B_date_diff, C_by_source, D_by_year, E_coverage_window, PPV_reverse, QC.
result: done 2026-11-14 on HiPerGator. Denominator 600, footnote 121. Chemo sensitivity 46.5% overall (TR n 518, within 90d 241), 80.3% within EHR coverage window (294 patients). Radiation: 84/115 in-window TR records with no pipeline record. Earlier run also gave radiation PPV 36.7%, immunotherapy PPV 6.8% (13/192). Fixes/extensions in quick 261114-qv3.

### 3. R/88 SECTION 15be workbook checks (TRVAL-07)
expected: Set R202_SENSITIVITY_XLSX to the written xlsx path; rerun R/88 SECTION 15be; workbook checks PASS (KEY leftmost, all 8 sheets present, at least one '<11' in A_sensitivity).
result: done 2026-11-14 — TR-VAL-202 12/12 PASS.

## Summary

total: 3
passed: 3
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

Close-out 2026-11-14 (quick 261114-s48): all 3 items done; full results in 202-VERIFICATION.md "Close-out" and 202-03-SUMMARY.md.
