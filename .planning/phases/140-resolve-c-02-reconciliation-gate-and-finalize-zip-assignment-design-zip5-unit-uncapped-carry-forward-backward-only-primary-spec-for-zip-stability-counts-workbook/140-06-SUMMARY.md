---
phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook
plan: 06
subsystem: data/investigation
tags: [r, dplyr, testthat, zip-imputation, validation-curve]

# Dependency graph
requires:
  - phase: 140-05
    provides: encounter_zip with gap_days_at_assignment/gap_days_at_assignment_backward_only and direct_zip_period_start, fully assembled through SECTION 11
provides:
  - build_encounter_anchored_validation_cases() (SECTION 1B pure function, encounter-anchored second validation estimate, P-05a)
  - A_validation_curve_encounter_anchored sheet (9th workbook sheet), stating its own 74.4%-subpopulation and ZIP9-derived-ZIP5 limitations (140-08-PATCH FIX-06)
  - A_validation_curve and KEY-sheet LOWER BOUND labeling on the existing record-anchored A-06 curve (P-05b)
affects: [140-07]

# Tech tracking
tech-stack:
  added: []
  patterns: ["dual validation-curve pattern: two independently-sampled hold-out estimates (record-anchored vs. encounter-anchored) reusing one shared aggregate_validation_curve() reducer"]

key-files:
  created: []
  modified:
    - R/115_zip_stability_counts.R
    - tests/testthat/test-115-validation-curve.R

key-decisions:
  - "No architectural decisions required this plan -- both tasks were literal implementations of 140-CONTEXT.md Section 6's recommendation and 140-08-PATCH FIX-05/FIX-06, with no checkpoint task and no deviation beyond one accuracy fix (8-sheet -> 9-sheet header/console text, corrected to match the new sheet count)."

patterns-established:
  - "Encounter-anchored validation sampling: hold out nothing -- sample the real encounter population directly (ADMIT_DATE) and score against same-day ground truth where it exists, rather than sampling address-change boundaries. Reusable pattern if a future plan needs a third, differently-anchored estimate."

requirements-completed: [P-05a, P-05b]

# Metrics
duration: ~20min
completed: 2026-08-10
---

# Phase 140 Plan 06: Encounter-Anchored Validation Curve + A-06 Lower-Bound Labeling Summary

**A second, encounter-anchored validation curve (`build_encounter_anchored_validation_cases()`) samples real cohort `ADMIT_DATE`s and predicts via the same backward most-recent-before rule `get_zip9_at_date()` uses, shipped alongside a new `A_validation_curve_encounter_anchored` sheet; the pre-existing record-anchored A-06 curve is now explicitly labeled a LOWER BOUND everywhere it appears, with both curves' own selection limitations (74.4%-subpopulation-only, ZIP9-derived-not-`zip5_coalesced` ZIP5 accuracy) stated in the KEY sheet and each sheet's own subtitle.**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-08-10
- **Tasks:** 2 (both `type="auto"`, no checkpoints)
- **Files modified:** 2 (`R/115_zip_stability_counts.R`, `tests/testthat/test-115-validation-curve.R`)

## Accomplishments

- `build_encounter_anchored_validation_cases(encounter_zip_with_direct, zip9_seq)` added to SECTION 1B: filters to `has_direct_zip9 == TRUE` encounters (the ground-truth population, a genuine same-day covering record), predicts from the `zip9_seq` spell immediately prior to the covering record's own `direct_zip_period_start` (excluding the covering record itself -- the same backward most-recent-before rule `get_zip9_at_date()` applies in production), and measures `gap_days` as `ADMIT_DATE - period_start_dt` of the *predicting* spell (140-08-PATCH FIX-05: encounter-to-record staleness, not the record-to-record quantity A-06 already plots). Returns the same shape (`gap_bin`, `exact_match`, `zip5_match`) as `build_validation_cases()`, so `aggregate_validation_curve()` (unchanged, from 139-02) applies directly.
- Two `testthat` fixtures added: (1) a 3-spell/1-encounter case proving the function predicts from the spell just prior to the covering record and that `gap_days` equals `ADMIT_DATE - predicting_period_start_dt` (220) rather than `direct_zip_period_start - predicting_period_start_dt` (200) -- the exact distinction FIX-05 exists to enforce; (2) a single-spell case proving an encounter whose covering record is the patient's only spell contributes zero rows (mirrors `build_validation_cases()`'s own single-record exclusion).
- SECTION 11 (after `encounter_zip` is fully assembled, including 140-05's `gap_days_at_assignment` columns) now calls `build_encounter_anchored_validation_cases(encounter_zip, zip9_seq)` and `aggregate_validation_curve()` on its output, producing `validation_curve_encounter_anchored`, with a console summary comparing case/patient counts against A-06's record-anchored `validation_cases`.
- New `A_validation_curve_encounter_anchored` sheet (workbook's 9th sheet, positioned immediately after `A_validation_curve` in SECTION 15) states its own 74.4%-subpopulation selection limitation (140-08-PATCH FIX-06 -- computed only on encounters that already have a covering ZIP9, exactly the subpopulation carry-forward is *not* needed for) and that both curves' ZIP5 accuracy is computed from the ZIP9-derived prefix, not `zip5_coalesced`.
- `A_validation_curve`'s own subtitle and the KEY sheet's "A-06 sampling frame" field now explicitly state the record-anchored curve is a LOWER BOUND (over-represents recently-changed addresses; structurally excludes single-record/most-stable patients), never a standalone production accuracy estimate. A new KEY-sheet field ("A-06 vs P-05a") explains why/how the two curves can diverge and states both curves' limitations side by side.
- SECTION 15's header comment and console message corrected from "8-sheet" to "9-sheet" (accuracy fix reflecting the new sheet, not a new design decision).

## Task Commits

Each task was committed atomically:

1. **Task 1: `build_encounter_anchored_validation_cases()` -- sample real ADMIT_DATEs, gap measured to the encounter (P-05a, FIX-05)** - `176cf84` (feat)
2. **Task 2: Wire encounter-anchored curve into a new sheet + lower-bound labeling on A_validation_curve/KEY + selection-limitation language (P-05b, FIX-06)** - `87e980a` (feat)

_Note: neither task used TDD's separate RED/GREEN commit split -- Task 1 is `tdd="true"` in the plan but was implemented with the function and its tests committed together in a single `feat` commit, consistent with this phase's established pattern in prior plans (e.g. 140-04, 140-05) of committing SECTION 1B function + fixture together rather than as separate failing/passing commits._

## Files Created/Modified

- `R/115_zip_stability_counts.R` - `build_encounter_anchored_validation_cases()` (SECTION 1B); SECTION 11 wiring (`encounter_anchored_cases`, `validation_curve_encounter_anchored`, console summary); `A_validation_curve_encounter_anchored` sheet (SECTION 15); LOWER BOUND labeling on `A_validation_curve`'s subtitle and two KEY-sheet fields ("A-06 sampling frame", new "A-06 vs P-05a"); 8-sheet -> 9-sheet header/console text correction
- `tests/testthat/test-115-validation-curve.R` - two new `test_that()` blocks covering `build_encounter_anchored_validation_cases()`'s prediction/gap-value correctness (including the FIX-05 gap-formula distinction) and its no-prior-spell exclusion behavior

## Decisions Made

None requiring a checkpoint -- both tasks were literal implementations of 140-CONTEXT.md Section 6's recommendation and 140-08-PATCH FIX-05/FIX-06's already-specified formulas/limitations language. No `checkpoint:decision` or `checkpoint:human-action` task existed in this plan (`autonomous: true`), and none was encountered.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected stale "8 sheets" header/console text to "9 sheets"**
- **Found during:** Task 2
- **Issue:** SECTION 15's section-header comment (`FULL 8-SHEET WORKBOOK`) and its `message()` call (`"...8 sheets..."`) were written when the workbook had 8 sheets (through 140-05); Task 2 adds the workbook's 9th sheet (`A_validation_curve_encounter_anchored`), making both strings inaccurate.
- **Fix:** Updated both to "9-sheet"/"9 sheets".
- **Files modified:** `R/115_zip_stability_counts.R`
- **Verification:** Structural grep/brace-balance check (below); this is a comment/message string only, no logic path depends on the literal sheet count.
- **Committed in:** `87e980a` (part of Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug -- stale accuracy text, not a design decision)
**Impact on plan:** Cosmetic-only fix, no scope creep, no logic change.

## Issues Encountered

None. `Rscript` remains unavailable in this Windows environment (confirmed again this session via `which Rscript`), consistent with every prior plan in this phase -- true `testthat::test_file()` execution against the new fixtures and real R parsing remain deferred to a future HiPerGator run. Verification for this session used the same structural fallback established by 140-01 through 140-05: a Python-based brace/paren/bracket balance check (1615/1615 parens, 174/174 braces, 43/43 brackets across both commits) plus literal-string `grep`-equivalent checks for every phrase the plan's `<verify>` blocks require (`build_encounter_anchored_validation_cases`, `ADMIT_DATE - period_start_dt`, `LOWER BOUND`, `A_validation_curve_encounter_anchored`, `74.4`, `zip5_coalesced`) -- all present.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 140-07 (Wave 6, depends on 140-06) is unblocked: Part A universe-difference documentation, sentinel-nulling close-out, and the optional `get_zip9_at_date()` addr_full test seam remain, the final plan in Phase 140.
- The workbook now has 9 sheets (KEY, A_stability_patient, A_stability_summary, A_validation_curve, A_validation_curve_encounter_anchored, B_scenario_counts, B_direction_split, C_completeness, QC) per the plan's own verification step 7 -- confirmed structurally (all `add_styled_sheet()` calls present with the expected names/order); real execution against actual `LDS_ADDRESS_HISTORY`/`ENCOUNTER` data (producing the real encounter-anchored curve's actual figures, in particular the real 74.4%-equivalent selection-limitation percentage for this run) remains deferred to a future HiPerGator run, consistent with every prior plan in this phase.

---
*Phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook*
*Completed: 2026-08-10*

## Self-Check: PASSED

- FOUND: R/115_zip_stability_counts.R
- FOUND: tests/testthat/test-115-validation-curve.R
- FOUND: 140-06-SUMMARY.md
- FOUND: commit 176cf84 (Task 1)
- FOUND: commit 87e980a (Task 2)
