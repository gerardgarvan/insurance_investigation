---
status: partial
phase: 33-do-25-and-26-but-only-for-av-th-encounters
source: [33-VERIFICATION.md]
started: 2026-04-24T14:16:00Z
updated: 2026-04-24T14:16:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Run R/33_multi_source_overlap_av_th.R on HiPerGator
expected: 4 CSV files created in output/tables/ with _av_th suffix: multi_source_same_date_detail_av_th.csv, multi_source_same_week_detail_av_th.csv, multi_source_combo_frequencies_av_th.csv, multi_source_per_source_summary_av_th.csv
result: [pending]

### 2. Run R/34_overlap_classification_av_th.R on HiPerGator after R/33
expected: 4 CSV files created in output/tables/ with _av_th suffix: classified_same_date_detail_av_th.csv, classified_same_week_detail_av_th.csv, per_site_overlap_profile_av_th.csv, overlap_source_payer_completeness_av_th.csv
result: [pending]

### 3. Verify console output shows ENC_TYPE distribution with per-site AV/TH counts
expected: Console output includes 'ENC_TYPE distribution after AV+TH filter' section with per-SOURCE breakdown and WARNING messages for sites with zero AV or TH encounters
result: [pending]

### 4. Verify classification output shows Identical/Partial/Distinct recommendations
expected: Console output includes per-source-combo recommendations (e.g., 'Safe to deduplicate' or 'Retain all')
result: [pending]

### 5. Confirm baseline outputs preserved
expected: R/22_multi_source_overlap_detection.R and R/23_overlap_classification.R remain unchanged; baseline CSV files without _av_th suffix are not overwritten
result: [pending]

## Summary

total: 5
passed: 0
issues: 0
pending: 5
skipped: 0
blocked: 0

## Gaps
