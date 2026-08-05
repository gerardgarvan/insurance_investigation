---
phase: 139-zip-stability-imputation-occurrence-counts
plan: 02
subsystem: data
tags: [r, dplyr, testthat, zip-normalization, address-history, validation]

# Dependency graph
requires:
  - phase: 139-01
    provides: addr_coal column contract (period_start_dt, period_end_dt, period_end_open, period_end_eff, zip9_norm, zip5_coalesced), coalesce_zip5(), SECTION 1B testable-function prelude pattern
provides:
  - build_validation_cases(addr_coal) and aggregate_validation_curve(cases) as pure, testable functions in SECTION 1B (139-05-PATCH FIX-01, framing F1 -- record-anchored, not spell-anchored)
  - tests/testthat/test-115-validation-curve.R with 4 passing behavioral fixtures (stable/mover/+4-only/single-record patient), including the stable-patient assertion that pct_exact_zip9_match == 100 -- the assertion that catches the pre-patch silent-zero defect
  - validation_curve tibble wired into Section 8/9 (gap-bin x accuracy-tier), with pct_unchanged/n_same_day console reporting and a Neighborhood Atlas block-group crosswalk probe that degrades gracefully (documented NA) when absent
affects: [139-03-encounter-zip-classification, 139-04-xlsx-assembly-and-c02]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Record-anchored hold-out validation (F1): hold out one addr_coal RECORD (not a zip9_seq spell) and predict it from the most recent PRIOR record with a non-NA ZIP9 -- operating on the pre-spell-collapse universe is what allows unchanged-address cases (and therefore nonzero exact-match accuracy) to survive into the test population"
    - "withr::with_dir(here::here(), ...) wrapping source()/sys.source() in testthat files, since testthat::test_file() runs with cwd set to tests/testthat, not the project root"
    - "Gap-bin scheme separates '0 (same-day)' from '0-30' so same-day version-correction records don't inflate the shortest elapsed-time bin's accuracy"
    - "Graceful-degradation probe pattern for optional enrichment files: file.exists() check, explicit console message either way, NA_real_-filled column (not omitted column, not error) when absent"

key-files:
  created:
    - tests/testthat/test-115-validation-curve.R
  modified:
    - R/115_zip_stability_counts.R

key-decisions:
  - "F1 framing (139-05-PATCH FIX-01): build_validation_cases() operates on addr_coal directly, never on zip9_seq -- zip9_seq's spell-collapsing (139-01 Task 3) removes exactly the unchanged-address records the hold-out test needs to measure carry-forward's real accuracy"
  - "Stable-patient test asserts pct_exact_zip9_match == 100 as a computed-value check (not a structural grep for a column name) -- this is the specific assertion that would have failed under the pre-patch spell-based design (which read 0.0 in every bin by construction)"
  - "gap_bin scheme: '0 (same-day)' split out from '0-30' so version-correction pairs (gap_days == 0) don't get folded into and inflate the shortest elapsed-time bin"
  - "n_excluded_no_prior (single-record patients with no prior to predict from) is counted and logged via message(), never silently dropped"
  - "Block-group tier is attempted only if data/reference/neighborhood_atlas_block_group_crosswalk.csv is found (it is not, in this repo); absence degrades to a documented NA_real_ column with an explicit console message, not an error and not silent omission"
  - "KEY-sheet language locked for Plan 04: A-06 is computed on address-history records (addr_coal) using each record's period_start_dt as the lookup date -- Pitfall 1 governs universe consistency across sheets, not A-06's sampling frame, and is not invoked to reinterpret A-06's own 'target encounter' phrase"
  - "Real HiPerGator validation of the validation_curve table's actual computed values (as opposed to the synthetic-fixture testthat checks) is deferred to a future run, exactly as the plan's own <how-to-verify> step 3 anticipated ('out of scope for this planning session') -- user explicitly deferred this at the Task 3 checkpoint"

requirements-completed: [A-06]

# Metrics
duration: 15min
completed: 2026-08-05
---

# Phase 139 Plan 02: Carry-Forward Validation Curve (A-06) Summary

**Record-anchored (not spell-anchored) hold-out validation curve for ZIP9 carry-forward, with a synthetic-fixture testthat suite that specifically proves the FIX-01 defect (silent 0.0% exact-match reading) can no longer occur.**

## Performance

- **Duration:** 15 min (Tasks 1-2 execution + checkpoint close-out)
- **Started:** 2026-08-05 (continuing from 139-01)
- **Completed:** 2026-08-05
- **Tasks:** 3 completed (2 auto tasks + 1 checkpoint)
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments
- `build_validation_cases()` and `aggregate_validation_curve()` added to `R/115_zip_stability_counts.R` SECTION 1B as pure, testable functions implementing 139-05-PATCH FIX-01's F1 framing: hold out one `addr_coal` address RECORD, predict it from the most recent prior record with a non-NA ZIP9, and measure exact-ZIP9 / same-ZIP5 match rate binned by elapsed gap days
- `tests/testthat/test-115-validation-curve.R` created with 4 passing behavioral fixtures (stable patient, mover, +4-only mover, single-record patient) -- 0 failures across 13 expectations, confirmed twice (once during initial task execution, once independently during this checkpoint close-out)
- The stable-patient fixture specifically asserts `pct_exact_zip9_match == 100` -- a real computed-value assertion, not a structural grep -- which is the exact check that would have failed (reading 0) under the pre-patch spell-based design
- SECTION 8/9 wired: `validation_cases <- build_validation_cases(addr_coal)` called against the real script-level `addr_coal`, `n_excluded_no_prior` logged, `pct_unchanged`/`n_same_day` reported, Neighborhood Atlas block-group crosswalk probed (not found in this repo -- degrades to documented NA, no error)
- Task 3 human-verify checkpoint closed: automated proxy confirmed 0 failures / 13 expectations across all 4 `test_that()` blocks, and the stable-patient assertion was independently confirmed to be a real nonzero-value check rather than a weakened structural check

## Task Commits

Each task was committed atomically:

1. **Task 1: Record-anchored A-06 hold-out (F1) -- test fixtures + build_validation_cases()/aggregate_validation_curve()** - `6afe2b0` (feat, tdd)
2. **Task 2: Wire A-06 into Section 8/9 -- block-group probe, pct_unchanged/n_same_day reporting, console summary** - `a235cbb` (feat)
3. **Task 3: HUMAN-VERIFY checkpoint** - approved by user ("defer testing"); no code changes, closed via this SUMMARY/STATE/ROADMAP commit

**Plan metadata:** (this commit, following SUMMARY.md creation)

## Files Created/Modified
- `R/115_zip_stability_counts.R` - SECTION 1B gained `build_validation_cases()`/`aggregate_validation_curve()`; SECTION 8 gained the real-data call, `n_excluded_no_prior`/`pct_unchanged`/`n_same_day` reporting, and the block-group crosswalk probe; SECTION 9 gained the `validation_curve` aggregation and console summary table. No xlsx write (deferred to Plan 04).
- `tests/testthat/test-115-validation-curve.R` - New file: 4 `test_that()` blocks (stable/mover/+4-only/single-record) sourcing `R/115_zip_stability_counts.R`'s SECTION 1B via `sys.source()` into a fresh environment, tolerating the probe gate's `stop()`/`quit()` once source execution reaches it.

## Decisions Made
See `key-decisions` in frontmatter above for the full list. Most consequential: the F1 record-anchored framing itself (the entire point of 139-05-PATCH FIX-01), and the decision to defer real HiPerGator validation of the curve's actual computed output (as opposed to the synthetic-fixture tests, which are fully verified) to a future run.

## Deviations from Plan

None - plan executed exactly as written. Both auto tasks (Task 1, Task 2) were completed in a prior execution session and committed at `6afe2b0` and `a235cbb`. This close-out session ran no new code changes -- it verified the existing test suite still passes, confirmed the stable-patient assertion is a real computed-value check, and closed the Task 3 checkpoint per the user's response.

## Issues Encountered

None. Re-running the test suite during this close-out session (`Rscript -e "library(testthat); test_file(...)"` via the full path to `Rscript.exe`, since `Rscript` is not on PATH in this Windows shell) reproduced the same result as the original task execution: 0 failures across 13 expectations in 4 `test_that()` blocks.

## User Setup Required

None - no external service configuration required.

## Checkpoint Resolution

**Task 3 (checkpoint:human-verify)** — Resume signal was "defer testing." This is interpreted, per the checkpoint's own scoping, as: approve the automated-verification portion of the checkpoint (steps 1-2 of `<how-to-verify>` -- test suite passes with 0 failures, stable-patient assertion confirmed to be a real nonzero-value check) and explicitly defer step 3 (reviewing the real `validation_curve` table's Overall row on an actual HiPerGator run) to a future session. The plan's own `<how-to-verify>` text already anticipated this: step 3 is prefixed "Once this script is run on HiPerGator (out of scope for this planning session)." No further action is required to close this checkpoint; the deferred item is a future runtime-verification task, not an open plan task.

## Next Phase Readiness
- `build_validation_cases()`/`aggregate_validation_curve()` and the F1 record-anchored framing are established in SECTION 1B and fully unit-tested; Plan 03 (encounter ZIP classification) and Plan 04 (xlsx assembly) can build on `addr_coal` and the SECTION 1B pattern without re-deriving either
- `tests/testthat/test-115-validation-curve.R` is designed to grow across Plans 03/04 (each appends its own `test_that()` block once its supporting function exists) -- current file reflects only the 139-02 fixtures
- KEY-sheet language for A-06 is locked (see key-decisions) for Plan 04's KEY-sheet authoring to reuse verbatim
- Real HiPerGator verification of the validation_curve table's actual computed values (not just the synthetic-fixture tests) remains an open item for whenever HiPerGator access is available -- tracked as a deferred item, not a blocker to Plans 03/04, which do not depend on A-06's real-data output
- No xlsx write yet by design -- deferred to Plan 04 once all sheets' data exists

---
*Phase: 139-zip-stability-imputation-occurrence-counts*
*Completed: 2026-08-05*

## Self-Check: PASSED

- FOUND: R/115_zip_stability_counts.R
- FOUND: tests/testthat/test-115-validation-curve.R
- FOUND commit: 6afe2b0
- FOUND commit: a235cbb
- Re-verified: testthat 0 failures across 13 expectations (4 test_that blocks)
