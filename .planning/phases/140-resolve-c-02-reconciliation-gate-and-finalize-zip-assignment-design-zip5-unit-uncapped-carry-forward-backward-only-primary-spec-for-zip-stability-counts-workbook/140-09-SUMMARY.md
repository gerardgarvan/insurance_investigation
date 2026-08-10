---
phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook
plan: 09
subsystem: data-pipeline
tags: [r, data-quality-gate, zip5, reconciliation, testthat, patch]

# Dependency graph
requires:
  - phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook
    plan: 01
    provides: compute_c02() (SECTION 1B) with n_present_no_usable_zip5, the C-02 gate's original C02_EXPECTED/C02_TOLERANCE comparison (SECTION 12) that this plan retires from the gate expression
provides:
  - "compute_c02_baseline() (SECTION 1B): pre-coalesce baseline count (raw ADDRESS_ZIP5 only), restricted to cohort patients present in addr_raw"
  - "c02_reconciled rewired onto two internally-checkable invariants (c02a_monotone, c02b_partition) that have a reachable TRUE state -- the retired C02_EXPECTED=26L comparison could never pass"
  - "C02_EXPECTED/C02_TOLERANCE retained (not deleted), reported on the KEY sheet as a superseded historical footnote with provenance marked unknown"
  - "n_zip5_recovered_by_coalesce and pct_cohort_with_any_address reported as named, non-gating QC figures"
  - "D-5 resolved (option-c, 2026-08-07): no coverage floor -- pct_cohort_with_any_address is reported only, not gated; C-02c (coverage-floor invariant) was proposed and not adopted"
affects: [140-03-PLAN, 140-04-PLAN]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Self-checkable invariants over an unverifiable external constant: when a gate's 'expected' value cannot be confirmed, replace the comparison with properties the pipeline itself must satisfy (monotonicity, partition identity) rather than leaving the gate permanently failing or widening tolerance to force a pass"
    - "Decision checkpoints can reject the proposed default: D-5's recommended option (0.90 floor) was not the one chosen -- option-c (no floor) was, and the plan's <resolution> block records the actual code delta, not just the answer"

key-files:
  created: []
  modified:
    - R/115_zip_stability_counts.R
    - tests/testthat/test-115-c02.R

key-decisions:
  - "P-01d/P-01e (140-09-PATCH FIX-17): C02_EXPECTED=26L retired as a gate input (provenance unrecoverable); c02_reconciled now checks properties the pipeline itself must satisfy instead of comparing against it"
  - "D-5 (resolved 2026-08-07, user-directed): option-c -- no coverage floor. pct_cohort_with_any_address (92.9% observed: 8,626 of 9,282) is reported as a QC/KEY-sheet figure but does not gate c02_reconciled. c02_reconciled = c02a_monotone && c02b_partition only (two invariants, not the three originally drafted in 140-09-PLAN.md before this checkpoint resolved)."

patterns-established:
  - "compute_c02_baseline() sits immediately before compute_c02() in SECTION 1B, mirroring the pre-coalesce/post-coalesce pairing the C-02a monotonicity check depends on"

requirements-met: [P-01d, P-01e, D-5]
requirements-deferred: []
requirements-withdrawn: []

# Metrics
duration: single session, 2026-08-06/07
completed: 2026-08-07
---

# Phase 140 Plan 09: C-02 Invariant-Based Gate + D-5 Coverage-Floor Decision Summary

**The unverifiable 26-patient C-02 control total is retired as a gate input. c02_reconciled now checks two properties the ZIP5-coalescing pipeline must satisfy by construction (C-02a monotonicity, C-02b partition identity) instead of comparing against an unconfirmable constant -- giving the gate a reachable PASS state for the first time in this phase. D-5 (whether to also gate on cohort address coverage) was resolved as "no floor -- report only": pct_cohort_with_any_address is a named, non-gating QC figure.**

## Performance

- **Duration:** Single session (2026-08-06 patch application through 2026-08-07 D-5 resolution).
- **Tasks:** 3 (Task 1 auto/TDD, Task 2 auto, Task 3 checkpoint:decision) -- all 3 resolved.
- **Files modified:** 2 (R/115_zip_stability_counts.R, tests/testthat/test-115-c02.R).

## Accomplishments

- **Task 1:** `compute_c02_baseline(cohort_ids, addr_raw)` added to SECTION 1B, immediately before `compute_c02()`. Returns the count of cohort patients present in `addr_raw` with no usable *raw* ZIP5 (via `normalize_zip5_raw()`, called not modified) -- the pre-coalesce counterpart to `compute_c02()`'s post-coalesce `n_present_no_usable_zip5`. Two `test_that()` fixtures appended to `tests/testthat/test-115-c02.R`: a 4-patient recovery case (baseline 2, post-coalesce 1, demonstrating `c02a_monotone` holds) and a synthetic monotonicity **violation** (a buggy "coalesce" step that drops a value, demonstrating `c02a_monotone` can read FALSE) -- an invariant never observed failing is an invariant never tested.
- **Task 2:** SECTION 12 rewired: `c02_reconciled` no longer compares `n_present_no_usable_zip5` against `C02_EXPECTED`. It now computes `c02a_monotone` (post-coalesce <= pre-coalesce baseline -- `coalesce_zip5()` can only add a ZIP5 value, never remove one) and `c02b_partition` (an independently-computed count, via `filter()` + `nrow()` over `c02_tbl`, not the subtraction `compute_c02()` already performs -- so the identity check has teeth). `C02_EXPECTED <- 26L` / `C02_TOLERANCE <- 5L` remain defined (not deleted) but no longer appear in the gate expression. `n_zip5_recovered_by_coalesce` (the coalescing fix's measured yield) is reported as its own figure. The `qc_tbl` `"c02_reconciled"` Metric string is byte-for-byte unchanged (confirmed via `grep` -- SECTION 15's `match("c02_reconciled", qc_tbl$Metric)` UF_ORANGE-highlighting lookup depends on it). SECTION 14 KEY sheet gained a superseded-constant footnote for the historical 26 (provenance marked unknown) and the D-2 sequencing note from 140-09-PATCH FIX-23 (ZIP5 was decided without the block-group evidence, not against it).
- **Task 3 (D-5 checkpoint, resolved 2026-08-07):** The team chose **option-c -- no coverage floor**, not the plan's recommended option-a (accept a 0.90 floor). `c02c_coverage` and `C02_COVERAGE_FLOOR` were removed from the script entirely (not left as dead/FALSE code) once the resolution was known. `pct_cohort_with_any_address` (92.9% observed: 8,626 of 9,282 cohort patients have at least one `addr_coal` row) remains computed and is reported as a named `qc_tbl` row, a KEY-sheet field, and in the QC-sheet subtitle -- explicitly marked "reported only, not gated" in all three places so a reader does not mistake its presence for a gate. `c02_reconciled` is therefore `c02a_monotone && c02b_partition` only.

## Files Created/Modified

- `R/115_zip_stability_counts.R` -- SECTION 1B gains `compute_c02_baseline()`. SECTION 12: `c02_reconciled` rewired onto `c02a_monotone && c02b_partition`; `C02_EXPECTED`/`C02_TOLERANCE` retained but out of the gate; `n_present_no_usable_zip5_precoalesce`, `n_zip5_recovered_by_coalesce`, `pct_cohort_with_any_address` computed and reported; per-invariant console messages added. SECTION 13 `qc_tbl` gains named rows for all of the above; the `"c02_reconciled"` Metric string is unchanged. SECTION 14 KEY sheet's C-02 fields replaced with the superseded-constant footnote + gate-design description + D-2 sequencing note. SECTION 15 QC-sheet subtitle rewritten to describe the two-invariant gate and the non-gating coverage figure.
- `tests/testthat/test-115-c02.R` -- Two new `test_that()` blocks for `compute_c02_baseline()`: a recovery-demonstrating fixture and a synthetic monotonicity-violation fixture.

## Decisions Made

- **P-01d/P-01e (140-09-PATCH FIX-17/FIX-18):** see `key-decisions` in frontmatter.
- **D-5 (resolved 2026-08-07, user-directed):** option-c, "no floor -- report coverage without gating on it." This is the plan's non-default option -- the plan text recommended option-a (accept 0.90). Rationale is the team's own (not restated here beyond the option's own stated tradeoff: coverage becomes purely descriptive rather than a release gate).

## Deviations from Plan

### Task 3 resolved as the plan's non-recommended option, requiring a follow-up code removal pass

- **Found during:** Task 3 (D-5 checkpoint resolution).
- **Nature of deviation:** 140-09-PLAN.md's Task 2 action text and `must_haves` were drafted assuming three invariants (C-02a/b/c) would all ship, since Task 3's decision was expected to confirm a floor value (option-a or option-b), not remove the invariant entirely (option-c). The user selected option-c. This required a second edit pass to `R/115_zip_stability_counts.R` beyond Task 2's original scope: removing `c02c_coverage`/`C02_COVERAGE_FLOOR` from the gate expression, `qc_tbl`, the KEY sheet, and the QC-sheet subtitle (all of which Task 2 had written assuming C-02c would gate), while keeping `pct_cohort_with_any_address` as a reported figure per option-c's own stated pro.
- **Why this is not Rule 4 (architectural change requiring a stop):** Removing one boolean term from an `&&` gate expression and re-labeling the QC/KEY text that described it is a same-shape correction within Task 2/3's own file/section boundaries -- no new data structures or schema changes. The user's own checkpoint answer is the authorization for this change, per the plan's `<resolution>` mechanism (same pattern used by 140-01 D-1 and 140-02 D-2/Task 2).
- **Fix:** Implemented per the D-5 resolution: `c02_reconciled <- c02a_monotone && c02b_partition`; `c02c_coverage`/`C02_COVERAGE_FLOOR` removed (not merely unused); all console messages, `qc_tbl` labels, KEY-sheet paragraphs, and the QC-sheet subtitle updated to describe a two-invariant gate with a reported-only coverage figure. 140-09-PLAN.md itself amended with a top-of-file note and Task 3's own `<resolution>` block documenting the delta from the as-drafted three-invariant design.
- **Files modified:** `R/115_zip_stability_counts.R`, `.planning/phases/.../140-09-PLAN.md`.
- **Verification:** `grep -n "c02c_coverage\|C02_COVERAGE_FLOOR" R/115_zip_stability_counts.R` returns no matches (clean removal, not dead code). `grep -n "^c02_reconciled" R/115_zip_stability_counts.R` confirms the two-term expression. `grep -n "pct_cohort_with_any_address" R/115_zip_stability_counts.R` confirms the figure is still computed and reported in all the same places, now labeled non-gating. Structural brace/paren/bracket balance check (Node script; Rscript unavailable in this Windows environment) passed on both modified files after every edit pass.

---

**Total deviations:** 1 (Task 3 resolving as the plan's non-default option, requiring code the plan had not anticipated needing to remove).
**Impact on plan:** Direct implementation of the user's own explicit checkpoint answer, not a unilateral choice. No scope creep -- confined to the C-02 gate code Task 2 already owned.

## Issues Encountered

- Rscript is not available in this Windows planning environment (consistent with every other Phase 139/140 plan). Used a Node.js brace/paren/bracket balance-check script as a structural proxy for `Rscript -e "invisible(parse(...))"`, run after every edit pass in this session. True R-parse and `testthat::test_dir()` execution (including this plan's two new `compute_c02_baseline()` fixtures) are deferred to the Wave 2.5 HiPerGator run, per 140-09-PATCH FIX-21's new `test_dir()` step added to 140-03 Task 3.

## User Setup Required

None required by this plan directly. **Not yet committed to git** -- this session's edits (140-09-PATCH's documentation fixes across 140-CONTEXT.md/140-01-SUMMARY.md/140-02-SUMMARY.md/140-02-PLAN.md/140-03-PLAN.md/data/reference/README.md, the new 140-09-PLAN.md, and this plan's code changes) are all staged in the working tree, pending an explicit instruction to commit.

## Next Phase Readiness

- `c02_reconciled` now has a reachable `TRUE` state and, on the 08/06 reference figures (9 <= baseline; identity holds), is expected to read `TRUE` on the next real HiPerGator run -- the phase's release gate ("Nothing ships before `c02_reconciled = TRUE`," 140-CONTEXT.md Section 10) is achievable for the first time.
- 140-03 (Wave 2b, depends on both 140-01 and 140-09 per 140-09-PATCH FIX-21) can proceed to its Task 3 HiPerGator checkpoint, which must now confirm this plan's rewired invariants (not the retired C02_EXPECTED comparison) and run `testthat::test_dir('tests/testthat')` for the first time this phase.
- The historical 26-patient control total remains fully documented on the KEY sheet for provenance, explicitly marked as no longer load-bearing -- nothing about the original 08/04 meeting note was deleted, only its role in the gate.

---
*Phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook*
*Completed: 2026-08-07*

## Self-Check: PASSED

- FOUND: 140-09-SUMMARY.md (this file)
- FOUND: `compute_c02_baseline` in R/115_zip_stability_counts.R (SECTION 1B) and tests/testthat/test-115-c02.R
- FOUND: `c02_reconciled <- c02a_monotone && c02b_partition` in R/115_zip_stability_counts.R
- FOUND: `C02_EXPECTED <- 26L` and `C02_TOLERANCE <- 5L` still defined, absent from the gate expression
- FOUND: no `c02c_coverage`/`C02_COVERAGE_FLOOR` references remaining (clean removal per D-5 option-c)
- FOUND: `pct_cohort_with_any_address` computed and reported in qc_tbl, KEY sheet, and QC-sheet subtitle
- FOUND: `"c02_reconciled"` Metric string byte-for-byte unchanged (SECTION 15 `match()` lookup intact)
- CONFIRMED: structural brace/paren/bracket balance check passed on both modified files (Rscript unavailable in this environment)
