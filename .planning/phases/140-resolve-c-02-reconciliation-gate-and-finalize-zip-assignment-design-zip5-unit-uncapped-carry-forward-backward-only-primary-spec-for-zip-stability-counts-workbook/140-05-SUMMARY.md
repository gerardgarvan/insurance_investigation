---
phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook
plan: 05
subsystem: data-pipeline
tags: [r, zip-imputation, gap-days, covariate, dplyr, testthat]

# Dependency graph
requires:
  - phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook
    plan: 04
    provides: "scenario_assigned (forward-inclusive) and scenario_assigned_backward_only (final, collapsed 4-level classifications) -- both gap columns reflect which record 'resolved' an encounter under EACH specification"
provides:
  - "compute_gap_days_at_assignment() (SECTION 1B): two independently-computed signed per-encounter gap covariates -- gap_days_at_assignment (forward-inclusive) and gap_days_at_assignment_backward_only (never-negative, stopifnot-enforced)"
  - "classify_encounter_zip() retains direct_zip_period_start (covering record's period start) through to its return value"
  - "median_gap_within_bin column on validation_curve (P-04b non-monotonicity diagnostic) plus a console NOTE and a new KEY sheet field"
  - "D-3 decision resolved and recorded on the KEY sheet: uncapped carry-forward accepted (option-a), no hard time-window cap built"
affects: [140-06-PLAN, 140-07-PLAN]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Gap-covariate computation factored as a SECTION 1B pure function (compute_gap_days_at_assignment()), mirroring assign_scenarios()'s dual-mode design, so sys.source()-based testthat fixtures (which stop at SECTION 2's probe gate before SECTION 11 executes) can exercise it directly"
    - "Backward-wins-ties tiebreaking on either-direction nearest-match reductions (140-08-PATCH FIX-08): arrange(abs(gap_signed), tie_rank, .by_group = TRUE) with tie_rank favoring gap_signed >= 0"
    - "Recorded team decisions (D-3, following D-2/D-4/D-5) get their own KEY sheet field with the resolution date and rejected-alternative rationale"

key-files:
  created: []
  modified:
    - R/115_zip_stability_counts.R
    - tests/testthat/test-115-scenarios.R

key-decisions:
  - "D-3 (P-04a) resolved 2026-08-10 as option-a: ZIP5 is carried forward WITHOUT a hard time-window cap (no 90/180/365-day discard rule); gap_days_at_assignment / gap_days_at_assignment_backward_only are reported as analytic covariates/sensitivity variables instead. Matches 140-CONTEXT.md Section 5's recommendation. Option-b (impose a cap at a team-specified N days) was NOT selected and requires no follow-up plan since it wasn't chosen."
  - "Task 1's gap-day logic was factored into a new SECTION 1B pure function, compute_gap_days_at_assignment(), rather than left as inline SECTION 11 code as the plan's action text literally showed -- necessary because tests/testthat/test-115-scenarios.R's sys.source()-based harness stops at SECTION 2's probe gate before SECTION 11 ever executes."

patterns-established:
  - "A checkpoint:decision task whose recommended option requires literally zero code changes (because a prior task in the same plan already implements it) still gets its own KEY sheet field recording the decision explicitly -- decisions are never left implicit just because the code already matches the recommended answer."

requirements-met: [P-04a, P-04b, D-3]
requirements-deferred: []
requirements-withdrawn: []

# Metrics
duration: multi-session (Tasks 1-2 executed 2026-08-08; Task 3 D-3 checkpoint resolved and closed out 2026-08-10)
completed: 2026-08-10
---

# Phase 140 Plan 05: Uncapped Carry-Forward Gap-Day Covariates + Non-Monotonicity Diagnostic + D-3 Decision Summary

**Two independently-computed signed gap-day covariates (`gap_days_at_assignment` forward-inclusive, `gap_days_at_assignment_backward_only` never-negative) plus a `median_gap_within_bin` diagnostic replace any hard time-window discard rule; the team's D-3 decision (option-a, recorded 2026-08-10) confirms uncapped carry-forward as the shipped design, requiring zero further code changes since Task 1 already implemented it.**

## Performance

- **Duration:** Multi-session. Tasks 1-2 implemented and committed 2026-08-08 (`98cca02`, `c765eb9`); Task 3's D-3 checkpoint returned to the user blocking, then resolved and closed out 2026-08-10 (`51e2064`).
- **Tasks:** 3 (2 auto/TDD, 1 checkpoint:decision) -- all 3 resolved.
- **Files modified:** 2 (`R/115_zip_stability_counts.R`, `tests/testthat/test-115-scenarios.R`).

## Accomplishments

- **Task 1** (`98cca02`): `compute_gap_days_at_assignment()` added to SECTION 1B, computing TWO independently-derived signed per-encounter covariates rather than one (per 140-08-PATCH FIX-01/FIX-02, since which record "resolved" an encounter differs between the forward-inclusive and backward-only specifications -- 201,118 of 217,570 S2 encounters are forward-only, so a single shared column would leave the backward-only covariate NA for 92% of the largest resolved bucket). `gap_days_at_assignment` (forward-inclusive): `ADMIT_DATE - resolving_period_start_dt` for `already_has_zip9` rows; nearest zip5_seq/zip9_seq spell in EITHER direction (backward wins exact ties, FIX-08) for S2/S3-resolved encounters; NA when unresolvable. `gap_days_at_assignment_backward_only`: same value for `already_has_zip9`; nearest BACKWARD-ONLY spell for S2/S3 resolved-under-backward-only encounters; NA otherwise -- and NEVER negative, enforced via `stopifnot()`. `classify_encounter_zip()` now retains `direct_zip_period_start` (the covering record's period start) through its return value. `tests/testthat/test-115-scenarios.R` extended with a 6-case fixture (a)-(f) covering `already_has_zip9`, S3-backward-resolved, S3-forward-only (negative gap, signaling forward inference), fully unresolvable, the FIX-01 forward-only-S2 case (resolved under forward-inclusive, NA under backward-only), and the FIX-08 exact-tie case (backward wins, not row order).
- **Task 2** (`c765eb9`): `median_gap_within_bin` added to `validation_curve` (P-04b) -- the median `gap_days` computed WITHIN each `gap_bin` (distinct from the bin's own boundary definition), plus an `Overall` row. A console `message()` (NOTE, P-04b) explains the diagnostic exists to determine whether the 366+ bin's higher-than-181-365 ZIP5 accuracy (52.0% -> 56.1% in the planning run) is a composition effect (very-stable long-tenure patients dominating the tail) or a binning artifact -- deferred to a future real HiPerGator run. A new KEY sheet field documents the same.
- **Task 3** (D-3 `checkpoint:decision`, resolved 2026-08-10): the team selected **option-a** -- ZIP5 is carried forward WITHOUT a hard time-window cap, using `gap_days_at_assignment`/`gap_days_at_assignment_backward_only` as analytic covariates/sensitivity variables. This is the design Task 1 already implements exactly (no discard rule, no `within_cap` flag, no filtering of the analytic dataset based on gap-day value anywhere in the script), so **no code logic changes were required**. The only change made in Task 3's close-out was documentation: a new KEY sheet row, "Uncapped carry-forward design (D-3, resolved 2026-08-10)," records the resolution, the rationale (median gap 547 days, p25 184/p75 1,310, only ~22% of gaps under 180 days; ZIP5 accuracy flattens 52-57% past 90 days with no decay cliff justifying a cutoff), and explicitly states option-b (a cap at a team-specified N days) was NOT selected.

## Task Commits

Each task was committed atomically:

1. **Task 1: gap_days_at_assignment (forward-inclusive) + gap_days_at_assignment_backward_only covariates (P-04a, 140-08-PATCH FIX-01/FIX-02/FIX-08)** - `98cca02` (feat)
2. **Task 2: median_gap_within_bin non-monotonicity diagnostic (P-04b)** - `c765eb9` (feat)
3. **Task 3: D-3 decision recorded on KEY sheet (option-a)** - `51e2064` (docs)

**Plan metadata:** this commit (`docs(140-05): complete plan`)

_Progress notes from the mid-session checkpoint were recorded separately in `a6df1e1` (STATE.md only, before Task 3 resolved)._

## Files Created/Modified

- `R/115_zip_stability_counts.R` - `compute_gap_days_at_assignment()` (SECTION 1B), `classify_encounter_zip()`'s `top1` selection extended to retain `direct_zip_period_start`, SECTION 9 `median_gap_within_bin`/console NOTE, SECTION 14 KEY sheet (P-04b diagnostic field + new D-3 field)
- `tests/testthat/test-115-scenarios.R` - extended (not new; created by 140-04 per 140-08-PATCH FIX-16) with a 6-case fixture (a)-(f) for `compute_gap_days_at_assignment()`

## Decisions Made

- **D-3 (P-04a):** resolved option-a -- uncapped carry-forward with gap-days as covariate. No code changes needed beyond the KEY sheet documentation added in Task 3's close-out. See "Key Decisions" in frontmatter for full rationale.
- **Gap-covariate placement:** factored into a new SECTION 1B pure function rather than left inline in SECTION 11, so the required test fixture can actually exercise the real implementation. See "Deviations from Plan" below.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Factored gap-day computation into a SECTION 1B pure function instead of inline SECTION 11 code**
- **Found during:** Task 1
- **Issue:** The plan's `<action>` text showed the gap-day reductions and `case_when()` logic added directly inline in SECTION 11, alongside `s1_matches`/`s2_matches`/`s2_nearest_backward`. `tests/testthat/test-115-scenarios.R`'s `sys.source()`-based harness (established by 140-04 per 140-08-PATCH FIX-16) stops execution at SECTION 2's probe gate before SECTION 11 ever runs -- inline placement would have made the plan's own required 6-case test fixture unable to exercise the real implementation; the tests would only be able to check for the literal presence of column names via `grepl()`, not correctness of the sign convention, the FIX-01 forward-only-S2 case, the FIX-02 never-negative invariant, or the FIX-08 exact-tie tiebreak.
- **Fix:** Factored the full gap-day computation (four nearest-match reductions, the FIX-08 backward-wins-ties tiebreak, and both `case_when()` assignments) into a new pure function, `compute_gap_days_at_assignment()`, added to SECTION 1B alongside `classify_encounter_zip()`/`assign_scenarios()`. SECTION 11 calls this function against the final `encounter_zip` (after `scenario_assigned`/`scenario_assigned_backward_only` are joined on) instead of containing the logic inline. All required behaviors are preserved byte-for-byte in effect: sign convention, FIX-01 forward-only-S2 case, FIX-02 never-negative invariant (`stopifnot()` still present), and FIX-08 exact-tie backward-wins tiebreak.
- **Files modified:** `R/115_zip_stability_counts.R`, `tests/testthat/test-115-scenarios.R`
- **Verification:** `testthat` 6-case fixture (a)-(f) exercises `compute_gap_days_at_assignment()` directly via `sys.source()`; structural brace/paren/bracket balance check passed after every edit (Rscript unavailable in this Windows environment, true R-parse deferred to a future HiPerGator run, consistent with every prior plan in this phase).
- **Committed in:** `98cca02` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking -- test-harness incompatibility with the plan's literal inline placement)
**Impact on plan:** Necessary for the plan's own required test fixture to be meaningful. No scope creep -- same behaviors, same columns, different code location. Documented in STATE.md at the time it was made (mid-session checkpoint note, `a6df1e1`) and carried forward here.

## Issues Encountered

None beyond the SECTION 1B factoring documented above.

## User Setup Required

None - no external service configuration required. Rscript remains unavailable in this Windows planning environment; true R-parse and `testthat::test_dir()` execution of `test-115-scenarios.R`'s gap-covariate fixture against real data are deferred to a future HiPerGator run, consistent with every prior plan in Phase 140.

## Next Phase Readiness

- Wave 4 (140-05) is fully complete. Plans 140-06/07 (downstream, not yet started) may now proceed.
- The uncapped-carry-forward design (D-3, option-a) is now locked in as the deliverable's shipped design -- any future plan touching `encounter_zip`'s gap columns or considering a discard/cap rule should treat D-3 as resolved unless a new team decision explicitly reopens it.
- `compute_gap_days_at_assignment()` (SECTION 1B) is the single reversible site if D-3 is ever reconsidered toward option-b (a capped design) -- that would require a new follow-up plan (a team-specified cap value N, a `within_cap` flag, and discard/filter logic), none of which exist in this plan.
- Both `gap_days_at_assignment` and `gap_days_at_assignment_backward_only` are available on the Part B/C analytic export for downstream sensitivity analyses (filter/stratify by gap value) without any code change.
- `median_gap_within_bin`'s actual composition-vs-artifact finding for the 366+ bin remains an open question pending a future real HiPerGator run, same as every other real-data-dependent diagnostic in this phase to date.
- True R-parse and real-data execution of this plan's `compute_gap_days_at_assignment()`/`median_gap_within_bin` logic (and `test-115-scenarios.R`) remain deferred to a future HiPerGator run, same as every other plan in this phase to date.

---
*Phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook*
*Completed: 2026-08-10*

## Self-Check: PASSED

- FOUND: `140-05-SUMMARY.md` (this file)
- FOUND: commit `98cca02` (Task 1)
- FOUND: commit `c765eb9` (Task 2)
- FOUND: commit `a6df1e1` (mid-session STATE.md progress note)
- FOUND: commit `51e2064` (Task 3 KEY sheet D-3 decision)
