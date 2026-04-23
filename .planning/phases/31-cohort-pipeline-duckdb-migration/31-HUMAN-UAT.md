---
status: partial
phase: 31-cohort-pipeline-duckdb-migration
source: [31-VERIFICATION.md]
started: 2026-04-23T18:35:00Z
updated: 2026-04-23T18:35:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Execute RDS vs DuckDB Parity Test on HiPerGator
expected: Run `source("R/27_parity_test_cohort.R")` — all 3 parity levels pass (row count, PATID set equality, structural equality via waldo::compare). Console shows "ALL CHECKS PASSED".
result: [pending]

### 2. Execute Benchmark Timing Comparison on HiPerGator
expected: Run `source("R/28_benchmark_cohort.R")` — CSV written to output/logs/duckdb_benchmark.csv with 6 rows (3 RDS + 3 DuckDB runs), median comparison and speedup ratio logged to console.
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
