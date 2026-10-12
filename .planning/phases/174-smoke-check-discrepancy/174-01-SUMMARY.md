---
phase: 174-smoke-check-discrepancy
plan: 01
status: complete
started: 2026-10-12
completed: 2026-10-12
key-files:
  created:
    - R/88_smoke_test_comprehensive.R
    - .planning/phases/174-smoke-check-discrepancy/174-01-SUMMARY.md
---

## Objective

Make R/88's final summary trustworthy: PASS == total with FAIL == 0 on HiPerGator, where every check is counted once and failures are counted as failures.

## Root Cause (from Task 0 HiPerGator evidence)

**920 vs 921 discrepancy:** The "ALL 920 CHECKS PASSED" footer computes `total = passed + failed`. With `failed == 0`, `total == passed`. The "921" figure came from a local run (IS_LOCAL = TRUE), which executes 4 ENV-04 checks vs production's 3 — a difference of exactly 1. No FAIL lines existed in the before-run.

**Counter bugs confirmed by reading R/88:**

| Section | Checker fn | `passed` bug | `failed` bug | Checks affected |
|---------|-----------|--------------|--------------|-----------------|
| 135 | `.p135_check` | Never updated | Never updated | 28 |
| 137 | `check_137` | Never updated | Never updated | 14 |
| 138 | `check_138` | Always incremented (pass or fail) | Correct | 12 |
| 139 | `check_139` | Always incremented (pass or fail) | Correct | 14 |
| 144 | `check_144` | Always incremented (pass or fail) | Correct | 22 |

## Counter Fixes Applied

**Sections 135 and 137** — added `passed <<- passed + 1L` in pass branch, `failed <<- failed + 1L` in fail branch. 28 + 14 = 42 checks now visible to global total.

**Sections 138, 139, 144** — moved `passed <<- passed + 1L` from unconditional position into the pass branch only. Failures now correctly increment `failed` only.

**Generic `check()`** — already correct; left unchanged.

## cache_dir Check Added

Field name confirmed: `CONFIG$cache$cache_dir` = `"/blue/erin.mobley-hl.bcu/clean/rds"`.

Added to production branch (after thread count check):
```r
check(
  "Production mode: cache_dir in /blue/",
  !is.null(CONFIG$cache$cache_dir) && grepl("^/blue/", CONFIG$cache$cache_dir)
)
```

## Totals — Before vs After

| | Before (Task 0) | After (Task 3) |
|--|--|--|
| Footer | ALL 920 CHECKS PASSED | ALL 963 CHECKS PASSED |
| FAIL lines | character(0) | character(0) |
| Production mode: lines | 3 | 4 (cache_dir added) |

**Arithmetic:** 920 + 28 (§135) + 14 (§137) + 1 (cache_dir) = **963** ✓ (predicted in Task 1, confirmed by HiPerGator run)

## FAILs

None. All 963 checks passed on HiPerGator (2026-10-12).

## Note

The R/88 baseline is now **963**, not 921 or 920. Downstream phases and SUMMARYs should cite "PASS == total, FAIL == 0" rather than a fixed number, since the total will change as new checks are added.
