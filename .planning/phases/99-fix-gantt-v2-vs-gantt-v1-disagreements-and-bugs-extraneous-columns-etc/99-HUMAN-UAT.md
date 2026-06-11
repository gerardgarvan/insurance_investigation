---
status: partial
phase: 99-fix-gantt-v2-vs-gantt-v1-disagreements-and-bugs-extraneous-columns-etc
source: [99-VERIFICATION.md]
started: 2026-06-11T19:15:00Z
updated: 2026-06-11T19:15:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Run R/52_gantt_v2_export.R to regenerate CSV outputs
expected: gantt_episodes.csv with 22 columns and gantt_detail.csv with 20 columns matching EPISODES_SCHEMA and DETAIL_SCHEMA
result: [pending]

### 2. Verify pseudo-treatment metadata in regenerated CSVs
expected: Death and HL Diagnosis rows have empty strings for regimen_label, drug_group, etc., and NA for is_first_line
result: [pending]

### 3. Verify is_hodgkin derivation correctness in outputs
expected: All rows with cancer_category containing 'Hodgkin Lymphoma' have is_hodgkin=TRUE, others have FALSE
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
