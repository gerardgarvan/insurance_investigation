---
phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook
plan: 03
subsystem: data-pipeline
tags: [r, data-quality-gate, date-parsing, testthat, hipergator, qc]

# Dependency graph
requires:
  - phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook
    plan: 01
    provides: compute_c02() present-vs-absent breakdown (n_present_no_usable_zip5, n_cohort_absent_from_addr) that this plan's Task 2 QC row and Task 3 real-run confirmation both depend on
  - phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook
    plan: 09
    provides: rewired c02_reconciled gate (c02a_monotone && c02b_partition) that this plan's Task 3 HiPerGator run confirmed PASS on real data
provides:
  - "classify_unparseable_dates_vec()/classify_unparseable_dates() (SECTION 1B): failure-mode classifier for the 4,912 unparseable period_start_dt raw strings"
  - "unparseable_date_examples (QC sheet extra_tbl): top-20 raw values per category, confirmed on real data to contain exactly one populated category (blank_or_null)"
  - "n_patients_lost_to_filters_c02 (P-02c): explicit named 280-patient filter-loss QC row"
  - "REAL HiPerGator confirmation (2026-08-08) that 140-01/140-09's diagnostic additions and gate rewiring behave as designed against actual LDS_ADDRESS_HISTORY/PCORnet data -- the Wave 2.5 gate (140-08-PATCH FIX-14) is now passed"
  - "P-02b resolved: the entire 4,912-record unparseable-date residual is genuinely blank/NULL/empty source data (100% blank_or_null), not a parse_pcornet_date() gap -- no parser extension needed"
affects: [140-04-PLAN, 140-05-PLAN, 140-06-PLAN, 140-07-PLAN]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Capture-before-filter: raw values that will be dropped by a filter are captured and classified in the same pipeline pass, immediately before the filter executes, so the classification breakdown never requires a second query/run"
    - "Blocking checkpoint before structural-change waves: a purely-diagnostic wave (140-01/140-09/140-03) is confirmed against real data via an explicit checkpoint before assignment-logic-changing waves (140-04+) are allowed to build on its assumed output"

key-files:
  created:
    - .planning/phases/140-.../140-03-SUMMARY.md
  modified: []  # R/115_zip_stability_counts.R and tests/testthat/test-115-c02.R were already committed (d76a485, fef75e8, and 140-09's 9123628) prior to this close-out session; no code changes made here

key-decisions:
  - "P-02b (parser-extension decision): resolved as 'the residual is genuinely unparseable' -- the real HiPerGator run's classification breakdown shows all 4,912 unparseable period_start_dt records fall into the single blank_or_null category (0 in numeric_looking_but_invalid, text_looking_but_invalid, or other_unrecognized). No extension to parse_pcornet_date() is warranted; the residual is genuinely blank/NULL/empty source data."
  - "Task 3 (Wave 2.5 blocking checkpoint, 140-08-PATCH FIX-14) resolved 2026-08-08: real HiPerGator run confirms all assumed figures (656 vs 9 for C-02 present-vs-absent; 92.9% coverage; 4,912 unparseable dates; 280-patient filter loss; 385/665 pre/post-filter) with zero material divergence. testthat::test_dir('tests/testthat') -- the first-ever real execution of every fixture from Plans 140-01/140-09/140-03 -- passes 35/35 (0 fail, 0 warn, 0 skip). Wave 3 (140-04) is unblocked."

patterns-established:
  - "A striking numeric coincidence (n_present_no_usable_zip5_precoalesce == 26, matching the retired historical C02_EXPECTED constant) is recorded as a non-gating provenance clue rather than silently discarded, even though it does not affect the (already-passing) gate"

requirements-met: [P-02a, P-02b, P-02c]
requirements-deferred: []
requirements-withdrawn: []

# Metrics
duration: multi-session (code executed 2026-08-06/07; HiPerGator confirmation and close-out 2026-08-08)
completed: 2026-08-08
---

# Phase 140 Plan 03: Unparseable-Date Classification + P-02c Filter-Loss Row + Wave 2.5 HiPerGator Confirmation Summary

**All 4,912 unparseable `period_start_dt` records are classified by the script itself and confirmed on real data to be 100% blank/NULL/empty (zero recoverable via parser extension); the 280-patient filter-loss gap is an explicit named QC row; and a real HiPerGator run of this phase's diagnostic layer (140-01 + 140-09 + 140-03) confirms every assumed figure with zero divergence, passing the Wave 2.5 blocking gate and unblocking Wave 3 (140-04).**

## Performance

- **Duration:** Multi-session. Tasks 1-2 implemented and committed 2026-08-06/07 (`d76a485`, `fef75e8`); Task 3's real HiPerGator run and this close-out performed 2026-08-08.
- **Tasks:** 3 (2 auto, 1 checkpoint:human-action) -- all 3 resolved.
- **Files modified (code):** 2 (`R/115_zip_stability_counts.R`, `tests/testthat/test-115-c02.R`) -- both already committed prior to this close-out (see Task Commits below; no new code changes in this session).

## Accomplishments

- **Task 1** (`d76a485`): `classify_unparseable_dates_vec()`/`classify_unparseable_dates()` added to SECTION 1B -- a vectorised failure-mode classifier (`blank_or_null` / `numeric_looking_but_invalid` / `text_looking_but_invalid` / `other_unrecognized`) plus a thin counting wrapper, with testthat fixtures appended to `tests/testthat/test-115-c02.R`.
- **Task 2** (`fef75e8`): SECTION 3 wired to capture raw `ADDRESS_PERIOD_START` strings that fail `parse_pcornet_date()` before the drop-filter, computing `unparseable_date_breakdown` (console) and `unparseable_date_examples` (top-20 raw values per category, QC-sheet `extra_tbl`); SECTION 12/13 add the explicit named `n_patients_lost_to_filters_c02` (P-02c, 280-patient filter-loss) row; SECTION 15's QC sheet carries `unparseable_date_examples`.
- **Task 3** (checkpoint:human-action, resolved 2026-08-08): the user ran `Rscript R/115_zip_stability_counts.R` on HiPerGator against real `LDS_ADDRESS_HISTORY`/PCORnet data, with the working tree's full diagnostic layer applied -- 140-01's `compute_c02()` breakdown, 140-09's rewired `c02_reconciled` gate (`c02a_monotone && c02b_partition`, committed separately as `9123628`), and this plan's Tasks 1-2. Real results:
  - **C-02a (monotonicity):** pre-coalesce 26, post-coalesce 9 -- PASS (recovered 17 patients).
  - **C-02b (partition identity):** independent count 9 vs `compute_c02()`'s 9 -- PASS.
  - **`c02_reconciled`:** PASS (first time this gate has read PASS in this phase).
  - **Coverage (D-5, reported only):** 92.9% of cohort has any address row.
  - **Unparseable-date breakdown:** all 4,912 unparseable `period_start_dt` records are `blank_or_null` -- zero in `numeric_looking_but_invalid`, `text_looking_but_invalid`, or `other_unrecognized`. This conclusively resolves **P-02b**: the residual is genuinely unparseable (blank/NULL/empty source data), not a `parse_pcornet_date()` gap.
  - **P-02c:** 280 cohort patients lose every usable-ZIP5 address row to the study-period/unparseable-date filters (665 post-filter minus 385 pre-filter) -- confirmed exactly as assumed.
  - **`testthat::test_dir('tests/testthat')`:** `FAIL 0 | WARN 0 | SKIP 0 | PASS 35` (127.0s) -- the first-ever real execution of every fixture added across Plans 140-01/140-09/140-03; all pass.
  - **Notable non-blocking finding:** the pre-coalesce baseline (`n_present_no_usable_zip5_precoalesce`) computed to exactly 26 -- the same value as the retired historical `C02_EXPECTED` constant. This supports 140-CONTEXT.md's working hypothesis that the team's original "26" was computed over the pre-coalesce population, not the post-coalesce cohort. Not gate-relevant (`C02_EXPECTED` is retired from the gate per 140-09-PATCH FIX-17) but recorded here as a provenance clue worth surfacing to Erin/Amy.
  - Every figure reported was consistent with 140-CONTEXT.md's assumed figures (656 vs 9; 92.9%; 4,912; 280; 385/665) -- **no material divergence**.

## Task Commits

Code was executed and committed across two sessions:

1. **Task 1: classify_unparseable_dates_vec()/classify_unparseable_dates()** - `d76a485` (feat)
2. **Task 2: Wire classification into SECTION 3 + top-20 examples table + 280-patient QC row** - `fef75e8` (feat)
3. **Task 3: Real HiPerGator confirmation** - no code commit (diagnostic run only); the C-02 gate code it confirmed was committed separately by Plan 140-09 as `9123628` (`feat(140-09): retire unverifiable C-02 control total, gate on coalescing invariants`)

**Plan metadata:** this commit (`docs(140-03): complete plan`)

## Files Created/Modified

- `.planning/phases/140-.../140-03-SUMMARY.md` - this file (new)
- `R/115_zip_stability_counts.R` / `tests/testthat/test-115-c02.R` - no changes this session; both confirmed clean/committed (`d76a485`, `fef75e8`, `9123628`) via `git status`/`git log` before close-out

## Decisions Made

- **P-02b (parser-extension decision):** resolved "genuinely unparseable" -- the real breakdown shows 100% of the 4,912 unparseable records are `blank_or_null`. No extension to `parse_pcornet_date()` is warranted.
- **Task 3 / Wave 2.5 gate (140-08-PATCH FIX-14):** resolved -- real HiPerGator run confirms all assumed figures with zero material divergence; `testthat::test_dir()` passes 35/35. Wave 3 (140-04) is unblocked.

## Deviations from Plan

None - plan executed exactly as written. (140-09's insertion as Wave 2a ahead of this plan's Task 3, and the FIX-21 `test_dir()` amendment to Task 3's `<how-to-verify>`, were both handled by the prior `140-09-PATCH.md` application, not by this plan's own execution.)

## Issues Encountered

None. This close-out session made no code changes -- it verified (via `git log`/`git status`/`grep`) that the code confirmed by the real HiPerGator run was already committed, then recorded the run's results.

## User Setup Required

None - no external service configuration required. The real HiPerGator run itself was the required manual/environment-specific step, and it is now complete.

## Next Phase Readiness

- Wave 2.5's blocking gate (140-08-PATCH FIX-14) is passed. Wave 3 (140-04, S1-fold-in / backward-only waterfall design) may now proceed -- it is no longer building on unconfirmed assumptions about the ZIP5-coalescing pipeline or the C-02 gate.
- `c02_reconciled` is PASS on real data for the first time in this phase -- the phase's own release gate ("Nothing ships before `c02_reconciled = TRUE`," 140-CONTEXT.md Section 10) is achieved.
- P-02b is fully closed: no parser-extension follow-up work is needed.
- The `n_present_no_usable_zip5_precoalesce == 26` coincidence should be flagged to Erin/Amy as a provenance clue for the historical control total, independent of Wave 3's own work.
- Note for future close-out: several 140-09-PATCH-related doc files (`140-01-SUMMARY.md`, `140-02-PLAN.md`, `140-02-SUMMARY.md`, `140-03-PLAN.md`, `140-CONTEXT.md`, `data/reference/README.md`, plus new `140-09-PLAN.md`) remain uncommitted in the working tree as of this close-out -- out of scope for this plan (140-03) to commit; they belong to 140-09's own doc-patch unit.

---
*Phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook*
*Completed: 2026-08-08*

## Self-Check: PASSED

- FOUND: 140-03-SUMMARY.md (this file)
- FOUND: commit `d76a485` (Task 1)
- FOUND: commit `fef75e8` (Task 2)
- FOUND: commit `9123628` (140-09's C-02 gate rewiring, confirmed by this plan's Task 3 HiPerGator run)
