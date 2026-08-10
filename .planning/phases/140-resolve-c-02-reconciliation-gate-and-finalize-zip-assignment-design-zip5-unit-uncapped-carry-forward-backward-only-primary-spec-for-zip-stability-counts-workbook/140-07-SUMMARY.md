---
phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook
plan: 07
subsystem: data/investigation
tags: [r, dplyr, testthat, zip-imputation, documentation, test-seam]

# Dependency graph
requires:
  - phase: 140-06
    provides: encounter_zip fully assembled through SECTION 11, A_validation_curve_encounter_anchored sheet, LOWER BOUND labeling on A_validation_curve
provides:
  - Universe cross-check (n_cohort_in_addr/n_cohort_not_in_addr) in SECTION 12, immediately after compute_c02() (140-08-PATCH FIX-07)
  - "Part A vs Part B/C universe overlap (P-07a)" and "Sentinel ZIP nulling -- status (P-07b)" KEY sheet fields
  - Universe note on all 4 Part A sheet subtitles (addr_coal-specific wording on 3, corrected cohort-encounter wording on the 4th)
  - get_zip9_at_date(ids, dates, addr_full = NULL) test-injection seam with documented character/Date column contract (P-07c, 140-08-PATCH FIX-10)
  - tests/testthat/test-utils-address.R (new file, 140-08-PATCH FIX-16)
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: ["optional test-injection-seam parameter (addr_full = NULL) added to a production function without touching its default-path behavior or any downstream logic -- reusable pattern for future utils_*.R functions that load via CONFIG$data_dir"]

key-files:
  created:
    - tests/testthat/test-utils-address.R
  modified:
    - R/115_zip_stability_counts.R
    - R/utils/utils_address.R

key-decisions:
  - "A_validation_curve_encounter_anchored's universe note deviates from the plan's literal wording (which specified the same addr_coal-population sentence for all 4 Part A sheets). That sheet's own pre-existing subtitle already states its population is cohort-restricted ENCOUNTER ADMIT_DATEs (the Part B/C universe, further restricted to has_direct_zip9 == TRUE) -- NOT addr_coal, and the KEY sheet's own pre-existing 'Universe -- Part A sheets' field already excludes it from the addr_coal-universe group. Appending the plan's literal addr_coal sentence would have been a factual error the sheet's own existing text directly contradicts. Applied Rule 1 (auto-fix bug): the sheet still gets an explicit universe note (satisfying the must_haves truth that every Part A sheet states its universe prominently), but the note states the ACTUAL universe (cohort-restricted encounters) instead."

requirements-completed: [P-07a, P-07b, P-07c]

# Metrics
duration: ~25min
completed: 2026-08-10
---

# Phase 140 Plan 07: Universe-Difference Documentation + Sentinel Close-Out + get_zip9_at_date() Test Seam Summary

**Part A's addr_coal-vs-cohort universe gap is now stated on the KEY sheet and every Part A sheet subtitle, backed by a live `n_distinct()`-based cross-check that runs in SECTION 12 (immediately after `compute_c02()`) rather than SECTION 14, so a mismatch fails in seconds; sentinel-ZIP nulling is documented reviewed-and-closed; and `get_zip9_at_date()` gains an additive `addr_full = NULL` test-injection seam with a documented character/Date column contract and a new dedicated test file, all without touching `normalize_zip9()`/`normalize_zip5()`/`normalize_zip5_raw()` or the D-06 no-caching default path.**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-08-10
- **Tasks:** 2 (both `type="auto"`, Task 2 `tdd="true"`; no checkpoints in this plan)
- **Files modified:** 3 (`R/115_zip_stability_counts.R`, `R/utils/utils_address.R`, new `tests/testthat/test-utils-address.R`)

## Accomplishments

- **Task 1 (P-07a, P-07b, 140-08-PATCH FIX-07):**
  - SECTION 12: immediately after the existing `c02_result <- compute_c02(COHORT_IDS, addr_coal)` call, added `n_cohort_in_addr <- n_distinct(intersect(COHORT_IDS, addr_coal$ID))` / `n_cohort_not_in_addr <- n_distinct(COHORT_IDS) - n_cohort_in_addr`, asserted via `stopifnot(n_cohort_not_in_addr == c02_result$n_cohort_absent_from_addr)`. Uses `n_distinct()` on both sides (not `intersect()` + `length()`, which dedupes one side but not the other and false-positives on duplicate cohort IDs). Confirmed structurally between the SECTION 12 (line 1395) and SECTION 14 (line 1759) markers, at line 1523 -- catches a mismatch before workbook assembly, not after.
  - SECTION 14: computed `n_addr_noncohort <- n_patients_total - n_cohort_in_addr` (the one value specific to the KEY sheet's own documentation, not re-derived/re-asserted against `compute_c02()`'s output). Added two new `key_tbl` fields: "Part A vs Part B/C universe overlap (P-07a)" (states the addr_coal-vs-cohort gap with live overlap/non-cohort/absent-from-addr figures) and "Sentinel ZIP nulling (Pitfall 2) -- status" (reviewed-and-closed, citing the existing `n_zip9_sentinel_nulled`/`n_zip5_sentinel_nulled` QC-sheet counts).
  - SECTION 15: appended a universe note to `A_stability_patient`, `A_stability_summary`, and `A_validation_curve`'s subtitles stating their population is `addr_coal`, not the cohort. `A_validation_curve_encounter_anchored`'s subtitle instead states its universe is cohort-restricted encounters (see Deviations below).

- **Task 2 (P-07c, 140-08-PATCH FIX-10, `tdd="true"`):**
  - `get_zip9_at_date()`'s signature changed to `function(ids, dates, addr_full = NULL)`. When `addr_full` is `NULL` (default), the load-on-demand path (CONFIG$data_dir, vroom/read.csv fallback, D-06 no-caching) is byte-for-byte identical to before. When supplied, the file read is skipped entirely and `addr_full` is character-coerced (`as.data.frame(lapply(addr_full, as.character), ...)`) to match the CSV load path's column types, then used as `addr_raw` directly -- everything downstream (ID validation, normalization, interval/fallback matching) is unchanged.
  - The roxygen block gained a `@param addr_full` entry documenting the character/Date column contract (a `POSIXct` column is not guaranteed to survive `as.character()` coercion into a `parse_pcornet_date()`-parseable format) and stating this is a test seam, not a general-purpose data-loader replacement.
  - `normalize_zip9()`/`normalize_zip5()`/`normalize_zip5_raw()`/`is_sentinel_zip5()` confirmed byte-for-byte unchanged via `git diff` (zero touched lines in any of those four function bodies).
  - New `tests/testthat/test-utils-address.R` (140-08-PATCH FIX-16 -- dedicated sibling file, not appended to `test-115-validation-curve.R`). Documents the addr_full column-type contract in its own header comment. Sources via `source("R/00_config.R")`'s standard `R/utils/*.R` auto-load, NOT the `.test_env`/`sys.source()` probe-gate pattern R/115's own test files use (since `get_zip9_at_date()` is a shared production utility, not a SECTION 1B function gated behind R/115's probe). Two `test_that()` blocks: one exercising all three `match_type` outcomes ("interval", "most_recent_before", "none") via a synthetic 2-patient `addr_full` tibble with character-ID/Date-period columns and a third patient with no address record at all, with no `CONFIG$data_dir` access and no file I/O; one confirming the `addr_full = NULL` default exists in `formals()`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Part A universe-difference documentation + sentinel-nulling close-out (P-07a, P-07b, FIX-07)** - `9460498` (feat)
2. **Task 2: get_zip9_at_date() addr_full injection seam + new test file (P-07c, FIX-10)** - `814358f` (feat)

_Note: Task 2 is `tdd="true"` in the plan but, consistent with this phase's established pattern (140-04 through 140-06), was implemented with the function change and its new test file committed together in a single `feat` commit rather than a separate failing/passing RED/GREEN split._

## Files Created/Modified

- `R/115_zip_stability_counts.R` - SECTION 12 universe cross-check (`n_cohort_in_addr`/`n_cohort_not_in_addr`, `stopifnot`); SECTION 14 `n_addr_noncohort` + two new `key_tbl` fields; SECTION 15 universe notes on all 4 Part A sheet subtitles
- `R/utils/utils_address.R` - `get_zip9_at_date(ids, dates, addr_full = NULL)` signature + injection branch; roxygen `@param addr_full` documentation
- `tests/testthat/test-utils-address.R` (new) - two `test_that()` blocks covering the addr_full injection seam's three match-type outcomes and the default-argument contract

## Decisions Made

None requiring a checkpoint -- both tasks were literal implementations of 140-CONTEXT.md Section 8's smaller items and 140-08-PATCH FIX-07/FIX-10/FIX-16's already-specified designs. No `checkpoint:decision` or `checkpoint:human-action` task existed in this plan (`autonomous: true`), and none was encountered.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected A_validation_curve_encounter_anchored's universe note to state its actual population**

- **Found during:** Task 1
- **Issue:** The plan's Task 1 action instructed appending the identical addr_coal-population sentence ("this sheet's population is addr_coal ({n_patients_total} patients), NOT the cohort...") to all 4 Part A sheets, including `A_validation_curve_encounter_anchored`. That sheet's own pre-existing subtitle (written in 140-06) already states its population is cohort-restricted ENCOUNTER `ADMIT_DATE`s (the Part B/C universe, further restricted to `has_direct_zip9 == TRUE`) -- it is built by sampling encounters, not `addr_coal` records. The KEY sheet's own pre-existing "Universe -- Part A sheets" field also already lists only `A_stability_patient`, `A_stability_summary`, `A_validation_curve` -- excluding this sheet. Appending the plan's literal addr_coal sentence to this sheet would have introduced a factual contradiction with text already on the same sheet and on the KEY sheet.
- **Fix:** Appended a universe note stating the sheet's ACTUAL population (cohort-restricted encounters, not addr_coal), explicitly calling out that this differs from the other three Part A sheets -- satisfying the must_haves truth (every Part A sheet states its universe prominently) without asserting something the sheet's own existing subtitle already disproves.
- **Files modified:** `R/115_zip_stability_counts.R`
- **Verification:** Structural review of the existing subtitle text (140-06-authored) confirmed the cohort-encounter population claim before writing the correction; grep confirms the new note text is present.
- **Committed in:** `9460498` (part of Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug -- avoided propagating a plan-instructed but factually incorrect universe claim onto one sheet)
**Impact on plan:** Documentation-accuracy fix only; no logic/computation changes; the must_haves truth (universe difference stated on every Part A sheet) is still satisfied, just with sheet-appropriate wording.

## Issues Encountered

None blocking. `Rscript` remains unavailable in this Windows environment (re-confirmed via `which Rscript` / `Rscript --version`, both failing), consistent with every prior plan in this phase -- true `testthat::test_file()`/`test_dir()` execution and real R parsing remain deferred to a future HiPerGator run. Verification for this session used the same structural fallback established by 140-01 through 140-06: a Python-based brace/paren/bracket balance check on the diff introduced by each edit (both R files' edits are internally balanced; `R/utils/utils_address.R`'s file-wide totals carry a pre-existing 1-parens/1-bracket imbalance that predates this plan's changes -- confirmed via `git show HEAD:R/utils/utils_address.R` before editing, likely from interval notation in a roxygen comment, e.g. `[ADDRESS_PERIOD_START, ADDRESS_PERIOD_END)` -- not introduced by this plan) plus literal `grep` checks for every phrase/pattern this plan's `<verify>` blocks and the plan-level `<verification>` section require: `n_cohort_in_addr`, `n_cohort_not_in_addr`, `Sentinel ZIP nulling`, the SECTION-12-not-SECTION-14 cross-check position, `addr_full = NULL`, `normalize_zip9 <- function` (and the sibling normalize/sentinel functions, confirmed unchanged via `git diff`), plus the amended-verification items carried over from 140-04/140-05 (`gap_days_at_assignment_backward_only` stopifnot, FIX-04 coverage-neutrality stopifnot) -- all present and unchanged from their originating plans.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

This is the final plan (8/8) in Phase 140. All 24 of 140-CONTEXT.md's task/decision IDs (P-01a..P-07c, D-1..D-4, plus D-5 added by 140-09-PATCH) are now addressed across 140-01 through 140-07 -- either implemented, or explicitly recorded as a team decision / deferred follow-up (see each plan's own SUMMARY.md and the "Phase 140 Decisions" section of STATE.md for the full resolution record). Per this session's explicit instructions, phase-level goal verification, marking the phase complete, and advancing to the next phase/milestone are the orchestrator's responsibility, not this plan's -- not attempted here.

The next real step outside this plan's scope is a HiPerGator run of the full amended `R/115_zip_stability_counts.R` against actual `LDS_ADDRESS_HISTORY`/`ENCOUNTER` data, to: confirm `c02_reconciled` (140-01/140-09's resolution) on this session's edits layered on top of the 2026-08-08 confirmed-passing run; review the backward-only/forward-inclusive waterfall split (140-04) and the new Part A universe-overlap figures (this plan) against real `n_cohort_in_addr`/`n_cohort_not_in_addr` numbers; review the encounter-anchored validation curve (140-06); and review the analytic `gap_days_at_assignment` covariate (140-05) -- before the workbook ships to Erin/Amy. `testthat::test_dir('tests/testthat')` should also be run for real at that time, now covering all 4 Phase 140 test files (`test-115-c02.R`, `test-115-scenarios.R`, `test-115-validation-curve.R`, `test-utils-address.R`), per 140-08-PATCH FIX-16's phase-level verification requirement.

---
*Phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook*
*Completed: 2026-08-10*

## Self-Check: PASSED

- FOUND: R/115_zip_stability_counts.R
- FOUND: R/utils/utils_address.R
- FOUND: tests/testthat/test-utils-address.R
- FOUND: 140-07-SUMMARY.md
- FOUND: commit 9460498 (Task 1)
- FOUND: commit 814358f (Task 2)
