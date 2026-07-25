---
status: complete
phase: 121-investigate-how-often-the-9-digit-zip-code-changes-at-the-individual-level-to-inform-the-decision-on-handling-zip-code-data-for-socioeconomic-indices
source: [121-VERIFICATION.md, 121-01-SUMMARY.md]
started: 2026-07-20
updated: 2026-07-20
---

## Current Test

[testing complete]

## Tests

### 1. R/106 runs to completion on HiPerGator
expected: `Rscript R/106_zip_change_frequency.R` loads the LDS_ADDRESS_HISTORY CSV, prints headline console stats (n_patients_total, pct_ever_changed_zip9, pct_ever_changed_zip5, pct_zip9_change_only, median_distinct_zip9, n_with_na_zip9, pct_disagree), and writes a 5-sheet styled xlsx (output/zip_change_frequency.xlsx). If LDS_ADDRESS_HISTORY_Mailhot_V1.csv is absent at the probed path, it exits gracefully via quit(status=0) with a clear diagnostic message (no crash).
result: pass

### 2. R/88 Section 15s Check 14 flips from SKIPPED to PASS
expected: After R/106 produces output/zip_change_frequency.xlsx on HiPerGator, running `Rscript R/88_smoke_test_comprehensive.R` shows Section 15s Check 14 (IS_LOCAL-gated runtime check) as PASS rather than SKIPPED; all other Section 15s structural checks (1-13) still PASS.
result: pass

### 3. LDS_ADDRESS_HISTORY filename + runtime unknowns confirmed
expected: Confirm the actual extract filename matches `LDS_ADDRESS_HISTORY_Mailhot_V1.csv` at CONFIG$data_dir (update the ADDR_FILENAME constant in R/106 if it differs). Also confirm the console log reports on the remaining runtime unknowns — ADDRESS_ZIP5 fill rate vs ADDRESS_ZIP9 (derive-from-ZIP9 fallback if blank), ADDRESS_PREFERRED fill rate (recency-only fallback if <5% populated), and cohort breadth (total LDS_ADDRESS_HISTORY patients vs HL-cohort overlap).
result: pass

## Summary

total: 3
passed: 3
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps
