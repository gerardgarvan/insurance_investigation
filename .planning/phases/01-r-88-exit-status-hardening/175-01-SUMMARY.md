---
phase: 175
plan: "01"
subsystem: smoke-test
tags: [exit-status, skip-tracking, hardening, R88]
dependency-graph:
  requires: []
  provides: [skip_check, skipped-counter, R88_FORCE_FAIL-sentinel, three-way-exit-guard]
  affects: [R/88_smoke_test_comprehensive.R]
tech-stack:
  added: []
  patterns: [skip_check helper, three-way exit guard pattern]
key-files:
  created: []
  modified:
    - R/88_smoke_test_comprehensive.R
decisions:
  - "Fake-assertions inside file.exists() if-blocks (R/37, R/38) converted to real file.exists() conditions rather than skip_check, since the guard already confirms the file exists and the condition is testable"
  - "p163_skip_note unified with global skipped counter via skipped <<- skipped + 1L addition"
  - "quit(status=0) grep showing 2 hits is a false positive: both hits are check() label strings validating R/106's own source code, not actual quit() calls in R/88"
metrics:
  duration: "~15 min"
  completed: "2026-10-12"
  tasks: 2
  files: 1
---

# Phase 175 Plan 01: R/88 Exit-Status Hardening (Tasks 1-2) Summary

Audit and edit R/88_smoke_test_comprehensive.R to add a skip counter, skip_check() helper, R88_FORCE_FAIL sentinel, and three-way exit guard. Converts 13 runtime-skip fake-TRUEs and 2 fake-assertions to correct patterns.

## Task 1 — Audit Results

### Grep output: hard-coded TRUE hits

```
Line 111:   check("00_config.R loads without error", TRUE)
Line 2350:  check("output has non-zero TRUE or FALSE -- SKIPPED (local / no output) (Phase 119)", TRUE)
Line 2622:  check("R/106 output xlsx present -- SKIPPED (local / no output) (Phase 121)", TRUE)
Line 2763:  check("get_chemo_hits runtime check -- SKIPPED (helpers not loaded in this scope) (Phase 122)", TRUE)
Line 2766:  check("get_chemo_hits runtime check -- SKIPPED (error loading fixtures) (Phase 122)", TRUE)
Line 2770:  check("get_chemo_hits runtime check -- SKIPPED (HiPerGator runtime, not IS_LOCAL) (Phase 122)", TRUE)
Line 2854:  check("R/109 runtime (Rscript parse + DuckDB diff + xlsx) -- SKIPPED (HiPerGator runtime) (Phase 123)", TRUE)
Line 2857:  check("R/109 runtime check -- SKIPPED (HiPerGator runtime, not IS_LOCAL) (Phase 123)", TRUE)
Line 2938:  check("R/39 not found -- R/110 not-wired check SKIPPED (Phase 124)", TRUE)
Line 2944:  check("R/110 runtime (xlsx generation + sheet row counts) -- SKIPPED (HiPerGator runtime) (Phase 124)", TRUE)
Line 2947:  check("R/110 runtime check -- SKIPPED (HiPerGator runtime, not IS_LOCAL) (Phase 124)", TRUE)
Line 3034:  check("R/111 .rds runtime column/non-empty check -- SKIPPED (local / no output) (Phase 130)", TRUE)
Line 3045:  check("R/112 xlsx 4-sheet runtime check -- SKIPPED (local / no output) (Phase 130)", TRUE)
Line 3057:  check("R/111 real-data DoI category counts -- SKIPPED (local / no output; logged on HiPerGator) (Phase 130)", TRUE)
Line 4336:  check("R/37 Rmd file exists", TRUE)       [inside file.exists() if block]
Line 4398:  check("R/38 script exists", TRUE)          [inside file.exists() if block]
```

### Classification table

| Line | Label (abbreviated) | Classification | Action |
|------|---------------------|---------------|--------|
| 111 | `00_config.R loads without error` | **legit** — tryCatch success branch | Leave unchanged |
| 2350 | Phase 119 output check SKIPPED | **runtime-skip** | -> skip_check() |
| 2622 | Phase 121 xlsx SKIPPED | **runtime-skip** | -> skip_check() |
| 2763 | Phase 122 get_chemo_hits helpers not loaded | **runtime-skip** | -> skip_check() |
| 2766 | Phase 122 get_chemo_hits error loading fixtures | **runtime-skip** | -> skip_check() |
| 2770 | Phase 122 get_chemo_hits HiPerGator runtime | **runtime-skip** | -> skip_check() |
| 2854 | Phase 123 runtime IS_LOCAL branch | **runtime-skip** | -> skip_check() |
| 2857 | Phase 123 runtime not-IS_LOCAL branch | **runtime-skip** | -> skip_check() |
| 2938 | Phase 124 R/39 not found | **runtime-skip** | -> skip_check() |
| 2944 | Phase 124 runtime IS_LOCAL branch | **runtime-skip** | -> skip_check() |
| 2947 | Phase 124 runtime not-IS_LOCAL branch | **runtime-skip** | -> skip_check() |
| 3034 | Phase 130 R/111 .rds no output | **runtime-skip** | -> skip_check() |
| 3045 | Phase 130 R/112 xlsx no output | **runtime-skip** | -> skip_check() |
| 3057 | Phase 130 DoI category counts no output | **runtime-skip** | -> skip_check() |
| 4336 | R/37 Rmd file exists (inside if block) | **fake-assertion** | -> file.exists() |
| 4398 | R/38 script exists (inside if block) | **fake-assertion** | -> file.exists() |

**Total runtime-skips converted:** 13  
**Total fake-assertions fixed:** 2  
**Legit TRUE left unchanged:** 1

### p163_skip_note count

`grep -c "p163_skip_note" R/88_smoke_test_comprehensive.R` = **7** (1 definition + 6 call sites)

### Callers of R/88

Only referenced in `.planning/` PLAN.md files (83-02, 87-03 phase plans) and `.planning/` SUMMARY.md files. No code in `R/`, `tests/`, or `scripts/` calls or sources R/88.

## Task 2 — Edits Made

### A — skipped counter + skip_check() function

Added `skipped <- 0L` alongside `passed` and `failed`. Added `skip_check()` function after the closing `}` of `check()`:

```r
skip_check <- function(label, reason = "") {
  msg <- if (nzchar(reason)) paste0("  SKIP: ", label, " (", reason, ")") else paste0("  SKIP: ", label)
  message(msg)
  skipped <<- skipped + 1L
}
```

### B — p163_skip_note unified with global skipped

Added `skipped <<- skipped + 1L` inside `p163_skip_note` so Section 15as skips roll up into the global footer count.

### C — Runtime-skips converted (13 calls)

All 13 `check("... SKIPPED ...", TRUE)` calls replaced with `skip_check(label, reason)`. Labels trimmed of "-- SKIPPED (reason)" suffix; reason moved to second argument.

### D — Fake-assertions fixed (2 calls)

- `check("R/37 Rmd file exists", TRUE)` -> `check("R/37 Rmd file exists", file.exists("R/37_gap_resolution_report.Rmd"))`
- `check("R/38 script exists", TRUE)` -> `check("R/38 script exists", file.exists("R/38_delivery_manifest.R"))`

### E — R88_FORCE_FAIL sentinel

Added before Section 2 (after function definitions, after the header messages):

```r
# Failure-path sentinel: fires only when the env var is set (Phase 175)
if (identical(Sys.getenv("R88_FORCE_FAIL"), "1")) {
  check("Forced failure sentinel (env var set)", FALSE)
}
```

### F — Footer updated (Section 16)

```r
total <- passed + failed   # skips are not checks
if (failed == 0) {
  message(glue("ALL {total} CHECKS PASSED  ({skipped} skipped)"))
} else {
  message(glue("FAILED: {failed}/{total} checks failed  ({skipped} skipped)"))
}
```

### G — Three-way exit guard (replaces single-branch guard)

```r
if (failed > 0) {
  if (identical(Sys.getenv("TESTTHAT"), "true")) {
    # testthat: no-op; the harness reads FAIL lines
  } else if (interactive()) {
    stop(paste0("R/88: ", failed, " check(s) FAILED"))
  } else {
    quit(status = 1)
  }
}
```

## Grep Verification Results

```
skip_check <- function (expect 1):      1  PASS
^skipped <- 0L (expect 1):             1  PASS
R88_FORCE_FAIL (expect 1):             1  PASS
Forced failure sentinel (expect 1):    1  PASS
stop(paste0("R/88: " (expect 1):       1  PASS
quit(status = 1) (expect 1):           1  PASS
quit(status = 0) (expect 0):           2  NOTE (false positive -- see below)
{skipped} skipped) (expect 2):         2  PASS
check(".*SKIPPED.*", TRUE) (expect 0): 0  PASS

Remaining ,TRUE) hits (legit only):
  Line 123: check("00_config.R loads without error", TRUE)   <- tryCatch success branch
```

**Note on quit(status = 0) count:** The grep matched 2 lines, but both are check() label strings that validate R/106's own source code contains `quit(status = 0)`. Neither is an actual `quit()` call in R/88. There is one actual `quit(status = 1)` call in the new exit guard and zero `quit(status = 0)` calls.

## Deviations from Plan

None. Plan executed exactly as specified. The `p163_skip_note` unification (Plan item B) and R/37/R/38 fake-assertion fixes (Plan item C) were both completed as specified.

## Stopped Before

Task 3 (checkpoint:human-verify) — HiPerGator run and exit-code verification. Not attempted.

## Self-Check: PASSED

- [x] R/88_smoke_test_comprehensive.R modified with all 6 plan edits
- [x] Commit 34c799e exists
- [x] All 9 grep verifications match expected values (quit(status=0) false positive documented)
