---
phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook
plan: 04
subsystem: data-pipeline
tags: [r, zip-imputation, scenario-assignment, waterfall, dplyr, testthat]

# Dependency graph
requires:
  - phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook
    plan: 01
    provides: n_present_no_usable_zip5 comparison-basis fix (superseded by 140-09, unrelated to this plan's own logic but shares SECTION 12/13 file region)
  - phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook
    plan: 02
    provides: "D-2 = option-a (ZIP5 as primary analysis unit) -- the logical precondition this plan's S1-fold-in design (P-06b) requires per 140-08-PATCH FIX-03"
  - phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook
    plan: 03
    provides: Wave 2.5 blocking HiPerGator confirmation gate PASSED, unblocking Wave 3 (this plan)
provides:
  - "assign_scenarios(encounter_zip_flagged, backward_only) (SECTION 1B): S1-collapsed, dual-mode ordered scenario assignment -- S1 folded into S3 universally (P-06b)"
  - "scenario_assigned (forward-inclusive, 4 levels) and scenario_assigned_backward_only (new) columns on encounter_zip, assigned via direct $ assignment (140-08-PATCH FIX-09)"
  - "Independently-computed backward-only ordered waterfall (waterfall_encounter_backward/waterfall_patient_backward) joined as parallel n_backward_only/cumulative_n_backward_only/cumulative_pct_backward_only columns on C_completeness (P-06a)"
  - "Coverage-neutrality assertion (stopifnot) proving the S1 fold-in only relabels buckets, never changes total resolved coverage (140-08-PATCH FIX-04)"
  - "KEY sheet / B_scenario_counts / C_completeness text documenting the INVERTED (not eliminated) ordered-vs-unordered S3 discrepancy"
  - "D-4 decision resolved and recorded on the KEY sheet: backward-only stays PRIMARY, forward-inclusive stays SENSITIVITY-only; P-06d explicitly out of scope, not triggered"
affects: [140-05-PLAN, 140-06-PLAN, 140-07-PLAN]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dual-mode pure function (assign_scenarios(backward_only = FALSE/TRUE)) computing two independent ordered classifications from one set of eligibility flags, rather than deriving one waterfall from the other by arithmetic -- preserves each waterfall's own PASS/FAIL and cumulative-percentage integrity"
    - "Direct $ assignment instead of mutate()-internal self-reference when a function call inside a pipeline would otherwise need to reference the outer (pre-assignment) frame (140-08-PATCH FIX-09)"
    - "Recorded team decisions (D-2, D-4, D-5) get their own KEY sheet field with the resolution date and rejected-alternative rationale, not just a footnote buried in a subtitle"

key-files:
  created:
    - tests/testthat/test-115-scenarios.R
  modified:
    - R/115_zip_stability_counts.R

key-decisions:
  - "D-4 (P-06c) resolved 2026-08-08 as option-a: backward-only stays the PRIMARY specification reported to Erin/Amy (already_has_zip9 + S2-backward + S3); forward-inclusive remains a SENSITIVITY-only comparison. Matches 140-CONTEXT.md Section 7's own recommendation. Option-b (forward-inclusive as primary) was rejected -- it would trigger P-06d, an out-of-scope extension to the shared production utility R/utils/utils_address.R, which is explicitly NOT built by this plan regardless of the answer."
  - "P-06d (utils_address.R forward-lookup variant) is explicitly out of scope / not triggered / not built -- utils_address.R stays byte-for-byte untouched by this plan."

patterns-established:
  - "A dangling cross-sheet reference (C_completeness's subtitle pointed to 'the KEY sheet for the D-4 primary-spec decision' before that field existed) is treated as a Rule-2 missing-critical-functionality gap and filled in in the same task that resolves the referenced decision, not left dangling until a hypothetical future plan"

requirements-met: [P-06a, P-06b, P-06c, D-4]
requirements-deferred: [P-06d]
requirements-withdrawn: []

# Metrics
duration: multi-session (Tasks 1-2 executed 2026-08-08; Task 3 D-4 checkpoint resolved and closed out 2026-08-08)
completed: 2026-08-08
---

# Phase 140 Plan 04: S1-Fold-In Dual-Mode Scenario Assignment + Backward-Only Waterfall + D-4 Primary-Spec Decision Summary

**`assign_scenarios()` collapses S1 into S3 universally and computes two independently-derived ordered waterfalls (forward-inclusive and backward-only) as parallel columns on C_completeness; the team's D-4 decision (option-a, recorded 2026-08-08) keeps backward-only as the PRIMARY specification reported to Erin/Amy, with forward-inclusive staying a sensitivity-only comparison and P-06d's production-utility extension explicitly out of scope.**

## Performance

- **Duration:** Multi-session. Tasks 1-2 implemented and committed 2026-08-08 (`45aef76`, `8bf3a87`); Task 3's D-4 checkpoint returned to the user blocking, then resolved and closed out later the same day (`8e980e8`).
- **Tasks:** 3 (2 auto, 1 checkpoint:decision) -- all 3 resolved.
- **Files modified:** 2 (`R/115_zip_stability_counts.R`, `tests/testthat/test-115-scenarios.R`).

## Accomplishments

- **Task 1** (`45aef76`): `assign_scenarios(encounter_zip_flagged, backward_only)` added to SECTION 1B, confirmed applicable because D-2 (140-02) resolved option-a (ZIP5 as analysis unit). S1 is folded into S3 universally -- the S3 test is `has_direct_zip5_only` in both modes; the S2 test varies by mode (`s2_either` for forward-inclusive, `s2_backward` for backward-only). SECTION 11's old 5-level inline `case_when` was replaced with two independent `assign_scenarios()` calls via direct `$` assignment (140-08-PATCH FIX-09, avoiding an outer-frame self-reference inside `mutate()`), producing `scenario_assigned` (forward-inclusive, now 4 levels: `already_has_zip9`, `S2`, `S3`, `unresolvable`) and `scenario_assigned_backward_only` (new). `tests/testthat/test-115-scenarios.R` created (new file per 140-08-PATCH FIX-16) with a 4-case fixture proving the S1-forward-only case resolves to `"S3"` in both modes (proving the fold-in is universal) and a forward-only-S2 case resolves to `"S2"` under forward-inclusive but `"unresolvable"` under backward-only.
- **Task 2** (`8bf3a87`): `scenario_priority` collapsed to the 4-level scheme; `waterfall_encounter`/`waterfall_patient` recomputed against the collapsed `scenario_assigned`. An INDEPENDENTLY-computed backward-only waterfall (`waterfall_encounter_backward`/`waterfall_patient_backward`, its own `count()`/`arrange()`/`cumsum()` call against `scenario_assigned_backward_only` -- never derived from the forward-inclusive table by subtraction) is joined on as parallel `n_backward_only`/`cumulative_n_backward_only`/`cumulative_pct_backward_only` columns. A console block reproduces 140-CONTEXT.md Section 7's headline comparison with an explicit "never sum B_direction_split rows" caveat. A coverage-neutrality `stopifnot()` (140-08-PATCH FIX-04) proves the S1 fold-in only relabels buckets, never changes total resolved coverage. The KEY sheet's "Ordered vs unordered S3" field, `B_scenario_counts`' subtitle, and `C_completeness`'s title/subtitle were all updated to state the ordered-vs-unordered S3 discrepancy has INVERTED (ordered S3 now EXCEEDS unordered "S3-eligible" by exactly the S1-backward count), not eliminated.
- **Task 3** (D-4 checkpoint:decision, resolved 2026-08-08): the team selected **option-a** -- keep backward-only as the PRIMARY specification, forward-inclusive as SENSITIVITY-only, matching 140-CONTEXT.md's own recommendation. Tasks 1-2 already implement this framing (`C_completeness`'s subtitle, written during Task 2, already labels the two column sets "SENSITIVITY spec" / "PRIMARY spec" respectively), so no code changes to the waterfall logic were required. One documentation gap was found and fixed during close-out: `C_completeness`'s subtitle references "See KEY sheet for the D-4 primary-spec decision," but no such KEY sheet field existed yet (Task 2 only added the inverted-discrepancy field, not a D-4 field, since D-4 was unresolved at that time). A new KEY sheet row, "Primary vs sensitivity spec (D-4, resolved 2026-08-08)," was added, stating the resolution, the rationale (matches 140-CONTEXT.md Section 7), and explicitly noting option-b was rejected and P-06d is not triggered. **P-06d (extending `R/utils/utils_address.R` with a forward-lookup variant) was NOT built** -- it is out of this plan's scope regardless of the D-4 answer, and this decision (option-a) does not trigger it either. `utils_address.R` remains byte-for-byte untouched by this plan.

## Task Commits

Each task was committed atomically:

1. **Task 1: assign_scenarios() -- S1-collapsed, dual-mode ordered assignment (P-06b)** - `45aef76` (feat)
2. **Task 2: Backward-only waterfall parallel columns + inverted-discrepancy KEY text (P-06a, FIX-04)** - `8bf3a87` (feat)
3. **Task 3: D-4 decision recorded on KEY sheet (option-a)** - `8e980e8` (docs)

**Plan metadata:** this commit (`docs(140-04): complete plan`)

_Progress notes from the mid-session checkpoint were recorded separately in `4a8b5b8` (STATE.md only, before Task 3 resolved)._

## Files Created/Modified

- `R/115_zip_stability_counts.R` - `assign_scenarios()` (SECTION 1B), SECTION 11 rewired onto direct `$` assignment producing both `scenario_assigned`/`scenario_assigned_backward_only`, SECTION 12 backward-only waterfall + coverage-neutrality assertion, SECTION 14 KEY sheet (inverted-S3-discrepancy field + new D-4 field), SECTION 15 `B_scenario_counts`/`C_completeness` subtitles
- `tests/testthat/test-115-scenarios.R` - new file (140-08-PATCH FIX-16); 4-case fixture for `assign_scenarios()` covering both modes

## Decisions Made

- **D-4 (P-06c):** resolved option-a -- backward-only stays PRIMARY, forward-inclusive stays sensitivity-only. No further code changes needed beyond the KEY sheet documentation gap fixed in Task 3's close-out. See "Key Decisions" in frontmatter for full rationale.
- **P-06d scope:** explicitly NOT built. `R/utils/utils_address.R` is out of scope for this phase and remains untouched.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added missing D-4 KEY sheet field**
- **Found during:** Task 3 close-out
- **Issue:** `C_completeness`'s subtitle (written during Task 2) says "See KEY sheet for the D-4 primary-spec decision," but Task 2's KEY sheet edits only covered the inverted ordered-vs-unordered S3 discrepancy field -- no D-4 field existed. Since D-4 was unresolved at Task 2's time of writing, this was an expected, not a defect, gap at that point, but leaving it unresolved after D-4 was actually decided would ship a workbook with a dangling cross-sheet reference to Erin/Amy.
- **Fix:** Added a new KEY sheet row, "Primary vs sensitivity spec (D-4, resolved 2026-08-08)," documenting the option-a resolution, its rationale, and the explicit rejection of option-b/non-triggering of P-06d.
- **Files modified:** `R/115_zip_stability_counts.R`
- **Verification:** Confirmed `key_tbl`'s `Field`/`Value` vectors both have 16 entries (aligned 1:1); brace/paren/bracket balance check (Python `str.count()`) passed on the full file after the edit (1425/1425 parens, 164/164 braces, 42/42 brackets). True R-parse deferred to a future HiPerGator run (Rscript unavailable in this Windows environment, consistent with every prior plan in this phase).
- **Committed in:** `8e980e8`

---

**Total deviations:** 1 auto-fixed (1 missing critical)
**Impact on plan:** Necessary to avoid shipping a workbook with a dangling internal cross-reference. No scope creep -- purely documentation, no logic change.

## Issues Encountered

None beyond the KEY sheet gap documented above.

## User Setup Required

None - no external service configuration required. Rscript remains unavailable in this Windows planning environment; true R-parse and `testthat::test_dir()` execution of `test-115-scenarios.R` against real data are deferred to a future HiPerGator run, consistent with every prior plan in Phase 140 (see 140-03-SUMMARY.md's Wave 2.5 confirmation for the pattern this plan follows).

## Next Phase Readiness

- Wave 3 (140-04) is fully complete. Plans 140-05/06/07 (downstream, not yet started) may now proceed.
- The backward-only PRIMARY / forward-inclusive SENSITIVITY framing is now locked in as the deliverable's reported specification -- any future plan touching C_completeness or the KEY sheet should preserve this framing unless a new team decision explicitly reopens D-4.
- `assign_scenarios()` (SECTION 1B) is the single reversible site if D-2 or D-4 are ever reconsidered -- no other code depends on the old 5-level inline `case_when`.
- P-06d remains an explicitly-scoped-out follow-up: if a future team decision reopens D-4 toward option-b, P-06d (extending `R/utils/utils_address.R`) requires its own planning session, not a quick patch to this plan.
- True R-parse and real-data execution of this plan's `assign_scenarios()`/backward-only-waterfall logic (and `test-115-scenarios.R`) remain deferred to a future HiPerGator run, same as every other plan in this phase to date.

---
*Phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook*
*Completed: 2026-08-08*

## Self-Check: PASSED

- FOUND: `140-04-SUMMARY.md` (this file)
- FOUND: `tests/testthat/test-115-scenarios.R`
- FOUND: commit `45aef76` (Task 1)
- FOUND: commit `8bf3a87` (Task 2)
- FOUND: commit `4a8b5b8` (mid-session STATE.md progress note)
- FOUND: commit `8e980e8` (Task 3 KEY sheet D-4 decision)
