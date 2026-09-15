---
status: partial
phase: 152-encounter-zip-to-residence-distance
source: [152-VERIFICATION.md]
started: 2026-09-15T00:00:00Z
updated: 2026-09-15T00:00:00Z
---

## Current Test

[awaiting human testing on HiPerGator]

## Tests

### 1. Crosswalk build — sbatch 122a_build_zip9_centroid_crosswalk.sbatch
expected: data/reference/zip9_bg_centroid_crosswalk.csv produced with expected schema and coordinate ranges
result: [pending]

### 2. R/122 end-to-end run on HiPerGator cohort (N=9,282)
expected: Workbook produced with all five sheets; QC waterfall reconciles to DuckDB ENCOUNTER row count
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
