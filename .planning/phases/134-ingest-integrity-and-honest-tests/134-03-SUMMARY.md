---
phase: 134
plan: "03"
subsystem: benchmark-and-smoke-test
tags: [honesty, benchmark, smoke-test, pattern-e]
dependency_graph:
  requires: [134-01, 134-02]
  provides: [honest-benchmark-coverage, honest-skip-accounting, honest-cause-of-death-check]
  affects: [R/82_benchmark_cohort.R, R/88_smoke_test_comprehensive.R]
tech_stack:
  added: []
  patterns: [skip-helper-pattern, schema-block-grep-pattern]
key_files:
  created: []
  modified:
    - R/82_benchmark_cohort.R
    - R/88_smoke_test_comprehensive.R
decisions:
  - "SCRIPTS_TO_BENCHMARK set to R/20-R/24 (DBDIAG-01 diagnostic set) — not R/14 which benchmarks cohort build, not diagnostic throughput"
  - "cause_of_death check is a regression guard (fails when column IS present in EPISODES_SCHEMA) rather than an absence guard — more useful behavior per polarity note in plan"
  - "skip() helper routes all skip paths through one counter so the summary line is always accurate"
metrics:
  duration_seconds: 182
  completed_date: "2026-07-25"
  tasks_completed: 3
  files_modified: 2
---

# Phase 134 Plan 03: R/82 all-5-scripts benchmark + R/88 skip/pass separation + cause_of_death inversion Summary

**One-liner:** Expanded R/82 benchmark from 1 to 5 diagnostic scripts, added a `skipped` counter and `skip()` helper to R/88 so skips are visible in the summary, and inverted the `cause_of_death` schema check from a presence test to a regression guard.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Expand R/82 to benchmark all 5 diagnostic scripts | ad12667 | R/82_benchmark_cohort.R |
| 2+3 | Add skip counter + fix inverted cause_of_death check in R/88 | 1c9ea43 | R/88_smoke_test_comprehensive.R |

## Changes Made

### R/82_benchmark_cohort.R

- Replaced `time_cohort_build(backend, run_number)` (hardcoded to `R/14_build_cohort.R`) with `time_script(script_path, backend, run_number)` (generic, accepts any script path)
- Added `SCRIPTS_TO_BENCHMARK` vector with the 5 DBDIAG-01 diagnostic scripts: R/20, R/21, R/22, R/23, R/24
- Replaced two sequential `for (i in seq_len(n_runs))` loops (one per backend) with a `for (script_path in SCRIPTS_TO_BENCHMARK)` outer loop containing both backend loops
- Benchmark results tibble gains a `script` column (basename) so R/83 can group by script correctly
- Removed now-unused scalar extractions (`rds_median`, `ddb_median`, `speedup`, `rds_summary`, `ddb_summary`, `min_rds`, `max_rds`, `sd_rds`, `min_ddb`, `max_ddb`, `sd_ddb`) — these were per-backend aggregates that only made sense for a single script
- Console summary now prints a per-script loop showing RDS/DuckDB median + range + speedup ratio for each of the 5 scripts

### R/88_smoke_test_comprehensive.R (Steps 2 and 3)

**Step 2 — skip counter and helper:**
- Added `skipped <- 0L` counter alongside `passed` and `failed` at top of Section 1
- Added `skip(reason)` helper: prints `"  SKIP: {reason}"` via glue and increments `skipped <<-`
- Replaced all 8 bare `message("  SKIP: ...")` calls with `skip(...)` calls
- Replaced all 4 `message(glue("  SKIP: Could not read..."))` error-handler calls with `skip(glue(...))`
- Updated Section 16 summary: both branches now print `({skipped} skipped)` after the pass/fail count

**Step 3 — cause_of_death inversion fix:**
- Old Check 7: `any(grepl("cause_of_death", r52_lines))` — PASSED whenever `cause_of_death` appeared anywhere in the file (including comments), gave a false green
- New Check 7: Locates the `EPISODES_SCHEMA <- c(...)` vector block in R/52, extracts the block using paren-depth counting, then asserts `!any(grepl("cause_of_death", schema_block_r52))` — FAILS if the column is re-added to the schema (regression guard)
- If `EPISODES_SCHEMA` is not found, a forced `FALSE` check fires to surface the structural problem

## Deviations from Plan

None — plan executed exactly as written. The polarity note in the plan (regression guard vs. absence guard) was followed explicitly.

## Verification Results

```
R/82: SCRIPTS_TO_BENCHMARK present with 5 entries — PASS
R/82: time_script present, time_cohort_build absent — PASS
R/88: skipped <- 0L defined at line 50 — PASS
R/88: skip <- function defined at line 62 — PASS
R/88: no remaining bare "  SKIP:" message calls (1 match = inside skip() helper) — PASS
R/88: summary includes skipped) on lines 4646, 4648 — PASS
R/88: schema_block_r52 grep variable present at lines 1232, 1235 — PASS
```

## Self-Check: PASSED

- R/82_benchmark_cohort.R: modified (worktree) — FOUND
- R/88_smoke_test_comprehensive.R: modified (worktree) — FOUND
- Commit ad12667: FOUND
- Commit 1c9ea43: FOUND
