---
status: partial
phase: 121-investigate-how-often-the-9-digit-zip-code-changes-at-the-individual-level-to-inform-the-decision-on-handling-zip-code-data-for-socioeconomic-indices
source: [121-VERIFICATION.md]
started: 2026-07-13
updated: 2026-07-13
---

## Current Test

[awaiting human testing]

## Tests

### 1. R/106 runs to completion on HiPerGator
expected: `Rscript R/106_zip_change_frequency.R` loads the LDS_ADDRESS_HISTORY CSV, prints headline console stats (total patients, % ever-changed at ZIP9 and ZIP5, median distinct ZIPs, NA counts), and writes a 5-sheet styled xlsx (zip_change_frequency.xlsx) to the output dir. If the address table is absent, it exits gracefully via quit(status=0) with a clear message (no crash).
result: [pending]

### 2. R/88 Section 15s Check 14 flips from SKIPPED to PASS
expected: After R/106 produces the output xlsx on HiPerGator, running `Rscript R/88_smoke_test_comprehensive.R` shows Section 15s Check 14 (IS_LOCAL-gated runtime check) as PASS rather than SKIPPED; all other Section 15s structural checks PASS.
result: [pending]

### 3. LDS_ADDRESS_HISTORY filename + field fill rates confirmed
expected: Confirm the actual extract filename matches `LDS_ADDRESS_HISTORY_Mailhot_V1.csv` (add a PCORNET_PATHS-style override in R/106 if it differs). Also confirm the console log reports on the 4 runtime unknowns: ADDRESS_ZIP5 fill rate (derive-from-ZIP9 fallback if blank), ADDRESS_PREFERRED fill rate (recency fallback if <5% populated), and cohort breadth (all address-history patients vs HL-cohort overlap footnote).
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
