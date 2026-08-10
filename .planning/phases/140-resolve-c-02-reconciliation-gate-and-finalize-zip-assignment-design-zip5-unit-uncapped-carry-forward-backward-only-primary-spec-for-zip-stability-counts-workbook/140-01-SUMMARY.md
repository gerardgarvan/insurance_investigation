---
phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook
plan: 01
subsystem: data-pipeline
tags: [r, data-quality-gate, zip5, reconciliation, testthat]

# Dependency graph
requires:
  - phase: 139-zip-stability-imputation-occurrence-counts
    provides: compute_c02() (SECTION 1B), C02_EXPECTED/C02_TOLERANCE reconciliation gate (SECTION 12), QC/KEY sheets (SECTION 13/14) -- all from 139-04
provides:
  - "compute_c02() exposes n_present_no_usable_zip5 directly (cohort patients present in addr_coal with no usable ZIP5), reproducing the 656-vs-9 breakdown from the script itself, not just planning documents"
  - "D-1 recorded as a distinct, explicit, user-directed resolution (not either of the plan's anticipated option-a/option-b team-confirmation branches): the C-02 reconciliation comparison basis is corrected to use n_present_no_usable_zip5 instead of n_patients_no_zip5_ever, while C02_EXPECTED (26L) and C02_TOLERANCE (5L) remain unchanged"
  - "tests/testthat/test-115-c02.R (new file, per 140-08-PATCH FIX-16) carrying the C-02 fixtures moved out of test-115-validation-curve.R plus the new 4-patient present-vs-absent breakdown fixture"
affects: [140-03-PLAN, 140-04-PLAN]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Comparison-basis correction distinct from control-total re-derivation: when a gate's 'expected' constant cannot be safely re-derived, correct which computed quantity is compared against it instead of touching the constant -- documented as its own decision type, not silently folded into either of a pre-planned binary's branches"

key-files:
  created:
    - tests/testthat/test-115-c02.R
  modified:
    - R/115_zip_stability_counts.R

key-decisions:
  - "D-1 (as actually resolved, 2026-08-06, user-directed -- NOT an Erin/Amy team confirmation of the original 26's denominator, and NOT either of the plan's anticipated option-a/option-b branches): C02_EXPECTED (26L) and C02_TOLERANCE (5L) remain unchanged; the reconciliation comparison itself is corrected to compare n_present_no_usable_zip5 (9) against C02_EXPECTED instead of n_patients_no_zip5_ever (665), because only the former is a population a genuine ZIP5-coalescing defect could actually produce. The gate is expected to continue reading FAIL (9 vs [21,31]) for this legitimate, documented, non-circular reason. The original 26's provenance/denominator remains an unconfirmed OPEN ITEM; the workbook's shippability stays explicitly blocked on C-02 pending team follow-up."

patterns-established:
  - "C-02 fixtures live in tests/testthat/test-115-c02.R (sibling to test-115-validation-curve.R), per 140-08-PATCH FIX-16, so a single shared test file does not keep absorbing every Phase 140 plan's fixtures"

requirements-met: [D-1]              # 140-09-PATCH FIX-19: a decision was recorded, which was D-1's acceptance
requirements-deferred: []
requirements-withdrawn:              # 140-09-PATCH FIX-19: acceptance criteria (written denominator statement /
                                      # c02_reconciled = PASS / an escalation trigger) were never met -- P-01a/b/c
                                      # are superseded by 140-09-PATCH FIX-18's invariant-based redesign, not completed
  - id: P-01a
    superseded-by: "140-09-PATCH FIX-18 (P-01d): provenance unrecoverable, retired as a gate input"
  - id: P-01b
    superseded-by: "140-09-PATCH FIX-18 (P-01d): C02_EXPECTED/C02_TOLERANCE retired from the gate expression"
  - id: P-01c
    superseded-by: "140-09-PATCH FIX-18 (P-01d): the escalation trigger no longer exists"

# Metrics
duration: Task 1 ~15min (prior session) + this session (Task 3 implementation + close-out) ~30min
completed: 2026-08-06
---

# Phase 140 Plan 01: C-02 Present-vs-Absent Breakdown + D-1 Comparison-Basis Correction Summary

> **Amended 2026-08-06 by 140-09-PATCH FIX-19:** This summary's frontmatter originally
> listed `P-01a, P-01b, P-01c, D-1` under `requirements-completed`. That overstated
> completion -- this plan's own prose says P-01a's denominator was "recorded as an
> unconfirmed open item" (not a written statement of the denominator, P-01a's actual
> acceptance criterion), and `c02_reconciled` reads FAIL, not PASS (P-01b's criterion).
> P-01a/b/c are now `requirements-withdrawn` (superseded by 140-09-PATCH FIX-18's
> invariant-based C-02 redesign, not completed); only `D-1` (a decision was recorded,
> which was its acceptance) remains `requirements-met`. See frontmatter.

**compute_c02() now exposes n_present_no_usable_zip5 (the only population a genuine ZIP5-coalescing defect could produce); the C-02 reconciliation gate's comparison basis is corrected to use it instead of the conflated n_patients_no_zip5_ever, per an explicit user-directed D-1 decision that deviates from the plan's anticipated team-confirmation branches -- C02_EXPECTED/C02_TOLERANCE stay unchanged and the gate remains a documented, open FAIL.**

## Performance

- **Duration:** Task 1 executed and committed in a prior session (~15 min); this session implements Task 3 per the user's actual D-1 resolution and closes out the plan (~30 min).
- **Started:** 2026-08-06 (prior session, Task 1) / resumed 2026-08-06T~19:00Z (this session)
- **Completed:** 2026-08-06T19:16:08-04:00
- **Tasks:** 3 (Task 1 auto/TDD, Task 2 checkpoint:decision, Task 3 auto) -- all 3 resolved
- **Files modified:** 2 (R/115_zip_stability_counts.R, tests/testthat/test-115-c02.R) -- test file from Task 1 only; Task 3 touched only R/115_zip_stability_counts.R

## Accomplishments

- Task 1 (already committed `6862a64`, verified intact this session): `compute_c02()`'s returned list gains `n_present_no_usable_zip5`, computed arithmetically from the two values it already returns (no second `group_by()`/`summarise()`). SECTION 12 console output and SECTION 13 `qc_tbl` both surface it as an adjacent named row/breakdown message. `tests/testthat/test-115-c02.R` created per 140-08-PATCH FIX-16 (moved the existing FIX-03 fixture out of `test-115-validation-curve.R`, extended with a 4-patient present-vs-absent fixture).
- Task 2 (D-1 checkpoint, resolved by the user this session): the team's answer did **not** match either of the plan's anticipated branches (option-a: confirmed narrower historical denominator with a re-derived `C02_EXPECTED`; option-b: cannot confirm, leave everything unchanged and add an unresolved-status note). Instead, the user made an explicit, informed, in-session decision: the reconciliation gate's *comparison basis* itself was wrong, independent of whether the historical "26" can ever be confirmed -- `n_patients_no_zip5_ever` (665) conflates a coverage question (656 patients with zero `addr_coal` rows) with the only population a coalescing defect could actually produce (9 patients present in `addr_coal` with no usable ZIP5). See "Deviations from Plan" below for why this required deviating from the plan's Task 3 text.
- Task 3 (implemented this session per the D-1 resolution, **not** the plan's original option-a/option-b text): `c02_reconciled` now compares `n_present_no_usable_zip5` against `C02_EXPECTED`, in place of `n_patients_no_zip5_ever`. `C02_EXPECTED` (26L) and `C02_TOLERANCE` (5L) are byte-for-byte unchanged -- confirmed via `grep`. SECTION 12 console messages (both the failure and would-be-OK branches), the SECTION 13 `qc_tbl` row labels, and two new SECTION 14 KEY-sheet fields, plus the QC-sheet subtitle, all state: (a) the corrected comparison basis; (b) that this is a user-directed decision recorded 2026-08-06, not an Erin/Amy team confirmation of the original 26's denominator; (c) the gate is expected to continue reading FAIL (9 vs. 26±5 = [21,31]) for a legitimate, non-circular reason; (d) the workbook's shippability stays explicitly blocked on C-02 pending further team follow-up on the original 26's provenance.

## Task Commits

Each task was committed atomically:

1. **Task 1: Expose the present-vs-absent C-02 breakdown (n_present_no_usable_zip5)** - `6862a64` (test, prior session; landed alongside 140-02's concurrent Wave-1 commit due to a `git add -p` race, content verified present and correct)
2. **Task 2: D-1 checkpoint** - No code commit; resolved via decision recording only (see below). Outcome: a distinct, user-directed comparison-basis correction -- neither option-a nor option-b as originally anticipated.
3. **Task 3: Apply the D-1 resolution to C02_EXPECTED and the KEY sheet** - `b6f1e74` (fix) -- applied the actual D-1 resolution (comparison-basis correction), which deviates from the plan's original option-a/option-b Task 3 text.

**Plan metadata:** this SUMMARY.md + STATE.md/ROADMAP.md updates (docs commit, see below)

_Note: Task 2 has no `<files>` tag -- it is a decision-recording task by design, resolved entirely through documentation (this SUMMARY.md, STATE.md), not code._

## Files Created/Modified

- `tests/testthat/test-115-c02.R` - (Task 1) New file per 140-08-PATCH FIX-16; carries the C-02 `compute_c02()` fixtures moved from `test-115-validation-curve.R`, extended with the 4-patient present-vs-absent breakdown fixture. Unchanged by Task 3 (Task 3's edits are all in SECTION 12+, after the probe gate, which `sys.source()` never reaches).
- `R/115_zip_stability_counts.R` - (Task 1) `compute_c02()` (SECTION 1B) gains `n_present_no_usable_zip5`; SECTION 12 console message and SECTION 13 `qc_tbl` row added. (Task 3, this session) SECTION 12's `c02_reconciled` now compares `n_present_no_usable_zip5` (not `n_patients_no_zip5_ever`) against `C02_EXPECTED`; console failure/OK messages, the pre-filter-comparison message, SECTION 13 `qc_tbl` Metric labels, two new SECTION 14 `key_tbl` fields ("C-02 reconciliation comparison basis" and "C-02 status, OPEN ITEM"), and the QC-sheet subtitle all updated to document the corrected basis and its user-directed, still-unresolved, still-blocking status.

## Decisions Made

- **D-1, as actually resolved (2026-08-06, user-directed):** See `key-decisions` in frontmatter. In short: `C02_EXPECTED`/`C02_TOLERANCE` stay at 26L/5L; the reconciliation *comparison basis* is corrected from `n_patients_no_zip5_ever` (665, conflated) to `n_present_no_usable_zip5` (9, the only population a genuine coalescing defect could produce). This is a comparison-basis correction, not a re-derivation of the historical control total -- the gate is expected to continue reading FAIL, and this is by design, not a bug to chase.
- **Why this deviates from the plan's Task 2/3 design, not just "which option was picked":** the plan's Task 2 `<options>` block presented a strict binary -- either the team confirms a narrower historical denominator (option-a, re-derive `C02_EXPECTED`) or cannot confirm it (option-b, leave everything as-is with an unresolved note). Both branches treated `n_patients_no_zip5_ever` as the correct thing to compare against `C02_EXPECTED`, disagreeing only about what `C02_EXPECTED` itself should be. The user's actual resolution instead identified that the *comparison basis* was the flawed element regardless of `C02_EXPECTED`'s correctness -- comparing a metric that conflates a coverage question with a coalescing-defect question was never going to produce a meaningful reconciliation, no matter what `C02_EXPECTED` is set to. This is a third, distinct resolution type: neither "confirmed, re-derive the constant" nor "unconfirmed, leave everything untouched," but "the comparison itself needed correcting, independent of the constant's own unconfirmed provenance." Task 3 was executed to implement this actual resolution rather than shoehorning it into either pre-planned branch.

## Deviations from Plan

### Task 3 executed per the D-1 resolution, not the plan's original option-a/option-b text

- **Found during:** Task 2 (D-1 checkpoint resolution) / Task 3 (implementation)
- **Nature of deviation:** The plan's Task 3 `<action>` block only anticipated two branches (option-a: re-derive `C02_EXPECTED` with a cited source; option-b: leave `C02_EXPECTED`/`C02_TOLERANCE` unchanged and add an unresolved-status KEY-sheet note). The user's actual decision was a third, distinct resolution -- correct the comparison basis (`n_present_no_usable_zip5` instead of `n_patients_no_zip5_ever`) while leaving `C02_EXPECTED`/`C02_TOLERANCE` unchanged, per explicit instructions supplied for this session.
- **Why this is not Rule 4 (architectural change requiring a stop):** this is a same-shape correction to an existing single-line boolean comparison (`c02_reconciled <- abs(X - C02_EXPECTED) <= C02_TOLERANCE`), changing which already-computed variable `X` refers to. No new data structures, tables, services, or schema changes were introduced. It is squarely within Task 3's original scope (`c02_reconciled`/`C02_EXPECTED`/KEY-sheet text), just applying a resolution the plan's binary didn't anticipate. The user (project owner) supplied this resolution directly and explicitly for this session, functioning as the checkpoint's resume-signal answer -- this is the same mechanism the plan's own `<resume-signal>` uses to hand a decision to Task 3, just with content outside the pre-enumerated option list.
- **Fix:** Implemented per the `<d1_resolution>` instructions verbatim: changed the comparison basis (SECTION 12), updated console messages (failure branch, OK branch, pre-filter-comparison message), updated `qc_tbl` labels (SECTION 13) to state the corrected basis without breaking the `match("c02_reconciled", qc_tbl$Metric)` exact-match lookup used later for QC-sheet UF_ORANGE highlighting (label for that one row deliberately left unchanged), added two new KEY-sheet fields (SECTION 14) documenting the corrected basis and the OPEN ITEM status, and updated the QC-sheet subtitle (SECTION 15).
- **Files modified:** `R/115_zip_stability_counts.R`
- **Verification:** Structural brace/paren/bracket balance check (Node script) confirms the file's syntax is balanced (Rscript unavailable in this Windows environment, a pre-existing documented limitation -- R-parse verification deferred to HiPerGator, matching how 140-02's Task 1 handled the same constraint). `grep` confirms `C02_TOLERANCE <- 5L` and `C02_EXPECTED <- 26L` unchanged. `tests/testthat/test-115-c02.R` is unaffected by Task 3's edits since all of Task 3's changes are in SECTION 12+ (after the `sys.source()` probe gate) -- the test file only exercises `compute_c02()` (SECTION 1B), which Task 3 did not touch.
- **Committed in:** `b6f1e74`

### Bug caught and fixed during Task 3 implementation ([Rule 1 - Bug])

- **Found during:** Task 3, while updating `qc_tbl` Metric labels for readability
- **Issue:** An initial draft of the label edits changed the `"c02_reconciled"` Metric string to a longer, more descriptive label. This would have silently broken `c02_row_idx <- match("c02_reconciled", qc_tbl$Metric)` (SECTION 15, used to locate and UF_ORANGE-highlight the QC-sheet row when the gate fails) -- `match()` would return `NA`, and the subsequent `glue("A{NA}:B{NA}")` dims string would produce an invalid Excel range, breaking the xlsx-writing step for exactly the failure case the highlighting exists to flag.
- **Fix:** Reverted that one label back to the exact string `"c02_reconciled"`, keeping all explanatory context in the surrounding console messages, KEY-sheet fields, and QC-sheet subtitle instead (which have no exact-match dependents).
- **Files modified:** `R/115_zip_stability_counts.R` (same file, caught and fixed before commit -- not a separate commit)
- **Verification:** `grep` confirms `match("c02_reconciled", qc_tbl$Metric)` is the only exact-match lookup against `qc_tbl$Metric` in the file, and the label it targets is unchanged.
- **Committed in:** `b6f1e74` (part of the Task 3 commit; caught before commit, not a follow-up fix)

---

**Total deviations:** 1 plan-scope deviation (Task 3's actual implementation vs. the plan's anticipated option-a/option-b branches, per explicit user instruction) + 1 auto-fixed bug (Rule 1, caught pre-commit).
**Impact on plan:** The plan-scope deviation is a direct implementation of the user's own explicit, in-session decision -- not a unilateral choice made without user input. The auto-fix was necessary for correctness (a broken exact-match lookup would have corrupted the xlsx-writing step) and caught before it ever reached a commit. No scope creep; both stayed within Task 3's original file/section boundaries.

## Issues Encountered

- Rscript is not available in this Windows planning environment (confirmed via `where`/`which`, consistent with the project's previously documented HiPerGator-only R runtime). Used a Node.js brace/paren/bracket balance-check script as a structural proxy for `Rscript -e "invisible(parse(...))"`, and deferred true R-parse verification to a future HiPerGator run -- matching the precedent set by 140-02's Task 1 for the same environment constraint.

## User Setup Required

None required by this plan directly. Follow-up (not blocking, tracked as an open item on the KEY/QC sheets): the original "26" figure's exact denominator population has still not been confirmed by the team (Erin/Amy) as of this session's close-out. When/if that provenance is eventually confirmed, a future plan can re-derive `C02_EXPECTED` with a documented basis; until then, the workbook's shippability to Erin/Amy stays explicitly blocked on C-02.

## Next Phase Readiness

- Both of Task 1's `must_haves` (the present-vs-absent breakdown exposed by the script itself, not just asserted in planning docs; the D-1 decision recorded explicitly rather than silently assumed) are satisfied.
- `C02_TOLERANCE` was never widened to absorb the gap, in either the plan's anticipated branches or the actual resolution -- preserved across this plan's entire execution, consistent with 139-05-PATCH FIX-03d and 140-CONTEXT.md's explicit constraint.
- The C-02 gate is now comparing against a metric (`n_present_no_usable_zip5`) that is analogous to what a genuine coalescing defect would produce, rather than a conflated metric -- but it still reads FAIL, and the workbook remains explicitly blocked from shipping to Erin/Amy on this basis, per the KEY/QC sheet language added this session. This is the correct, documented state, not an unresolved bug in this plan's own scope.
- 140-02 (Wave 1, the other in-flight plan) completed its own D-2/human-action checkpoints in this same session (see `140-02-SUMMARY.md`) -- both Wave 1 plans are now fully resolved.
- 140-03 and 140-04 (later plans referencing this plan's `provides`) can proceed; 140-04's C-01/C-02 waterfall design should reference `n_present_no_usable_zip5` as the reconciliation basis, per the pattern established here, if it touches the same gate.

---
*Phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook*
*Completed: 2026-08-06*

## Self-Check: PASSED

- FOUND: 140-01-SUMMARY.md (this file)
- FOUND: commit 6862a64 (Task 1)
- FOUND: commit b6f1e74 (Task 3)
- FOUND: tests/testthat/test-115-c02.R
- FOUND: `n_present_no_usable_zip5` present in R/115_zip_stability_counts.R
- FOUND: `C02_TOLERANCE <- 5L` unchanged
- FOUND: `C02_EXPECTED <- 26L` unchanged
