---
phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook
verified: 2026-08-10T16:44:32Z
status: human_needed
score: 5/5 must-haves verified (all automated checks pass; real-data execution of Waves 3-6 still required)
human_verification:
  - test: "Run `Rscript R/115_zip_stability_counts.R` on HiPerGator against real LDS_ADDRESS_HISTORY/ENCOUNTER data with the FULL amended script (140-01 through 140-07 layered together, i.e. everything built after the 2026-08-08 confirmation run)."
    expected: "c02_reconciled remains TRUE (c02a_monotone && c02b_partition); the backward-only vs forward-inclusive waterfalls, gap_days_at_assignment/gap_days_at_assignment_backward_only, the encounter-anchored validation curve, and the n_cohort_in_addr/n_cohort_not_in_addr universe cross-check all execute without error and produce numbers consistent with the planning-time estimates cited in 140-CONTEXT.md (e.g. ~86% backward-only coverage, 96.9% forward-inclusive, median gap 547 days)."
    why_human: "Rscript is unavailable in this Windows planning environment. Every plan in this phase (140-04 through 140-07) substituted a structural brace/paren/bracket balance check for real execution. Only the diagnostic layer (140-01 + 140-09 + 140-03) has ever actually run against real data (HiPerGator, 2026-08-08, testthat 35/35 PASS) -- that run happened BEFORE Waves 3-6 (S1-fold-in/backward-only waterfall, gap-days covariates, encounter-anchored validation curve, universe cross-check, get_zip9_at_date() test seam) were built. No plan in this phase claims otherwise; 140-07-SUMMARY.md and STATE.md both explicitly flag this as the required next step before the workbook ships to Erin/Amy."
  - test: "Run `Rscript -e \"library(testthat); test_dir('tests/testthat')\"` on HiPerGator against the current working tree (4 test files: test-115-c02.R, test-115-scenarios.R, test-115-validation-curve.R, test-utils-address.R)."
    expected: "All fixtures pass, including the 140-04 assign_scenarios() 4-case fixture, the 140-05 compute_gap_days_at_assignment() 6-case (a)-(f) fixture, the 140-06 encounter-anchored validation fixtures, and the 140-07 addr_full injection-seam fixtures -- none of which have ever been executed against a real R runtime."
    why_human: "Same environment constraint as above. These fixtures were only ever structurally balance-checked in this Windows environment."
  - test: "Re-issue output/zip_stability_counts_YYYYMMDD.xlsx from the confirmed-passing real run and confirm Erin/Amy can open all 9 sheets (KEY, A_stability_patient, A_stability_summary, A_validation_curve, A_validation_curve_encounter_anchored, B_scenario_counts, B_direction_split, C_completeness, QC) without Excel range/highlighting errors."
    expected: "Workbook opens cleanly; SECTION 15's match(\"c02_reconciled\", qc_tbl$Metric) highlighting logic (relied on by every plan in this phase to preserve byte-for-byte) does not throw an invalid-range error."
    why_human: "No workbook has been generated yet in this environment (output/ directory contains no zip_stability_counts file) -- xlsx generation requires the real HiPerGator run above to complete first."
---

# Phase 140: Resolve C-02 Reconciliation Gate and Finalize ZIP Assignment Design Verification Report

**Phase Goal:** Phase 139's `zip_stability_counts_20260806.xlsx` is unblocked for release: the C-02 reconciliation gate failure (computed 665 vs. expected 26) is resolved via an explicit, recorded team decision rather than a silently-widened tolerance; the coverage gaps behind it are classified and reported; ZIP5-vs-ZIP9 as the analysis unit, uncapped carry-forward with a gap-days covariate, and backward-only-primary/forward-inclusive-sensitivity scenario reporting are all implemented and confirmed by explicit team decisions (D-1..D-4) rather than silently assumed.

**Verified:** 2026-08-10T16:44:32Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Note on 140-CONTEXT.md sourcing

Two stray, untracked files exist at the repository root (`140-CONTEXT.md`, `140-09-PATCH.md`) that are NOT the operative phase documents — the root-level `140-CONTEXT.md` is a stale pre-planning snapshot (`# Phase 140: ZIP Stability & Imputation Occurrence Counts — Context`, "Status: Ready for planning"), superseded before implementation began. The authoritative, current `140-CONTEXT.md` lives in the phase directory (`# Phase 139 — ZIP Assignment Plan`, amended 2026-08-06 by 140-09-PATCH FIX-17/18) and is what this verification used throughout. Flagged under Anti-Patterns below as a repo-hygiene item, not a goal failure — the phase-directory copy is correct and is the one every plan/SUMMARY actually references.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | The 665-vs-26 C-02 gap is broken down by the script itself, and the gate is resolved via an explicit recorded decision (D-1) rather than silently widening tolerance or leaving it unresolved | VERIFIED | `compute_c02()` exposes `n_present_no_usable_zip5` (9) vs `n_cohort_absent_from_addr` (656); D-1 resolved 2026-08-06 (comparison-basis correction), then superseded 2026-08-06/07 by 140-09-PATCH FIX-17/18's invariant-based redesign. `c02_reconciled <- c02a_monotone && c02b_partition` (R/115_zip_stability_counts.R:1599) has a reachable TRUE state and read TRUE on the 2026-08-08 real HiPerGator run. `C02_EXPECTED <- 26L`/`C02_TOLERANCE <- 5L` (lines 1543-1544) remain defined, retained on KEY sheet for provenance, never widened, never present in the gate expression. |
| 2 | Unparseable-date failure modes and the 280-patient filter-loss gap are classified/reported by the script (P-02a/b/c) | VERIFIED | `classify_unparseable_dates_vec()`/`classify_unparseable_dates()` present; real HiPerGator run (2026-08-08, 140-03) confirms 100% of the 4,912 unparseable records are `blank_or_null` — P-02b resolved "genuinely unparseable." `n_patients_lost_to_filters_c02` (P-02c, 280-patient row) present and confirmed on real data. |
| 3 | Block-group crosswalk staging contract is fully documented (no code changes needed to activate); ZIP5-as-analysis-unit (D-2) is an explicit recorded decision | VERIFIED | `data/reference/README.md` documents path/columns/vintage/90% threshold (corrected 2026-08-06 by FIX-22 to state the single-vs-two-vintage tradeoff honestly, no longer claiming a nonexistent "matched to study period" vintage). D-2 resolved option-a (2026-08-06), reflected in R/115 KEY sheet field "Analysis unit (D-2, recorded 2026-08-06)" (line 1791) and in `assign_scenarios()`'s ZIP5-based S3 test. Crosswalk acquisition itself explicitly deferred (not available), consistent with Phase 139's shipped graceful-degradation behavior, not a regression. |
| 4 | S1 is folded into S3 in the ordered scenario assignment; a backward-only ordered waterfall is computed independently (not derived by summing B_direction_split rows); whether forward lookup becomes primary (D-4) is an explicit recorded decision | VERIFIED | `assign_scenarios(encounter_zip_flagged, backward_only)` (line 253) folds S1 into S3 universally in both modes (confirmed via 4-case testthat fixture). `waterfall_encounter_backward`/`waterfall_patient_backward` (lines 1446-1484) each run their own independent `count()`/`arrange()`/`cumsum()` against `scenario_assigned_backward_only`, never derived by arithmetic from the forward-inclusive table. D-4 resolved option-a (2026-08-08, backward-only PRIMARY / forward-inclusive SENSITIVITY-only), recorded on KEY sheet (line 1787). P-06d (utils_address.R forward variant) explicitly not triggered/not built, consistent with option-a. |
| 5 | `gap_days_at_assignment` exists as a signed per-encounter covariate (uncapped, D-3 recorded); a second encounter-anchored validation curve exists alongside A-06, explicitly labeled a lower bound; Part A's universe difference from Part B/C is documented and self-checking | VERIFIED | `compute_gap_days_at_assignment()` (line 283) produces `gap_days_at_assignment` (signed) and `gap_days_at_assignment_backward_only` (never-negative, `stopifnot`-enforced, line 1271); no cap/discard-rule/`within_cap` logic exists anywhere in the file (grep-confirmed clean). D-3 resolved option-a (2026-08-10), recorded on KEY sheet (line 1785). `build_encounter_anchored_validation_cases()` (line 166) implemented and wired to a 9th sheet `A_validation_curve_encounter_anchored`; `A_validation_curve`'s subtitle and KEY sheet explicitly state "LOWER BOUND" (lines 1820-1830). Universe cross-check (`n_cohort_in_addr`/`n_cohort_not_in_addr`, `stopifnot`) lives in SECTION 12 immediately after `compute_c02()` (lines 1521-1523); universe notes present on all 4 Part A sheet subtitles. |

**Score:** 5/5 truths verified at the code level. All are gated on a follow-up HiPerGator run for real-data confirmation of Waves 3-6 (see Human Verification below) — this does not fail any truth, since no plan claimed real-data execution for that code.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/115_zip_stability_counts.R` | C-02 invariant gate, unparseable-date classifier, dual-mode scenario assignment, gap-day covariates, encounter-anchored validation curve, universe cross-check | VERIFIED | 2,272 lines. All claimed functions/variables present and correctly wired (see truths 1-5 above). |
| `R/utils/utils_address.R` | `get_zip9_at_date(ids, dates, addr_full = NULL)` test-injection seam; `normalize_*()`/`is_sentinel_zip5()` byte-for-byte unchanged | VERIFIED | 191 lines. `addr_full = NULL` parameter present (line 93); default path (addr_full = NULL) unchanged per SUMMARY's `git diff` claim (not independently re-verified beyond confirming the signature and injection branch exist and the four normalize/sentinel functions are untouched by grep for stray edits). |
| `tests/testthat/test-115-c02.R` | `compute_c02_baseline()` recovery + synthetic-violation fixtures | VERIFIED | Both fixtures present (lines 142-201), including the violation fixture that proves `c02a_monotone` can read FALSE. |
| `tests/testthat/test-115-scenarios.R` | `assign_scenarios()` 4-case fixture; `compute_gap_days_at_assignment()` 6-case (a)-(f) fixture | VERIFIED | Both present, each case's expected value asserted individually. |
| `tests/testthat/test-115-validation-curve.R` | `build_encounter_anchored_validation_cases()` fixtures (prediction/gap-formula, single-spell exclusion) | VERIFIED | Both present (lines 200-249). |
| `tests/testthat/test-utils-address.R` | `addr_full` injection-seam fixtures (3 match-type outcomes; default-arg contract) | VERIFIED | New file, both fixtures present. |
| `data/reference/README.md` | Crosswalk staging contract (path/columns/vintage/threshold), corrected vintage claim (FIX-22) | VERIFIED | Present and honest about the single-vs-two-vintage tradeoff post-correction. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `compute_c02_baseline(COHORT_IDS, addr_raw)` | `c02a_monotone` / `n_zip5_recovered_by_coalesce` | Pre-coalesce raw-ZIP5-only count, differenced against `compute_c02()`'s post-coalesce figure | WIRED | `n_present_no_usable_zip5_precoalesce <- compute_c02_baseline(...)` (line 1577); `c02a_monotone <- n_present_no_usable_zip5 <= n_present_no_usable_zip5_precoalesce` (line 1579). Confirmed on real data: pre-coalesce 26, post-coalesce 9, PASS. |
| C-02b independent term | `compute_c02()`'s subtraction-derived figure | `filter()`/`nrow()` over `c02_tbl`, not the subtraction itself | WIRED | Lines 1587-1591 compute independently; confirmed non-circular per 140-01-SUMMARY/140-09-SUMMARY design intent. |
| `assign_scenarios(backward_only = TRUE)` | `waterfall_encounter_backward`/`waterfall_patient_backward` | Independent `count()`/`arrange()`/`cumsum()` on `scenario_assigned_backward_only` | WIRED | Lines 1446-1484; never derived by subtracting `B_direction_split` rows (explicit console caveat present per 140-04-SUMMARY). |
| `compute_gap_days_at_assignment()` | `encounter_zip$gap_days_at_assignment*` | Direct `$` assignment after `scenario_assigned`/`scenario_assigned_backward_only` are joined | WIRED | Confirmed via SECTION 11 call site and the `stopifnot()` never-negative assertion on the backward-only column. |
| `build_encounter_anchored_validation_cases()` | `A_validation_curve_encounter_anchored` sheet | `aggregate_validation_curve()` (reused, unchanged from 139-02) then `add_styled_sheet()` | WIRED | Function defined (line 166), called in SECTION 11, sheet added in SECTION 15 (lines 2166+). |
| `n_cohort_in_addr`/`n_cohort_not_in_addr` | `c02_result$n_cohort_absent_from_addr` | `stopifnot()` identity check | WIRED | Line 1523; catches a mismatch in SECTION 12 (before workbook assembly), per P-07a's design intent. |
| `get_zip9_at_date(addr_full = ...)` | test-injection seam | Character-coercion branch skipping the CONFIG$data_dir file load | WIRED | Signature confirmed at utils_address.R:93; exercised by `test-utils-address.R`'s 3-outcome fixture with no file I/O. |

### Requirements Coverage

REQUIREMENTS.md has no Phase 140 section — this is a documented gap consistent with Phase 139's own precedent (standalone remediation/investigation deliverable, no milestone requirement IDs mapped). Per phase instructions, 140-CONTEXT.md's own task/decision IDs (P-01a..P-07c, D-1..D-5) serve as the acceptance criteria instead. All are addressed:

| ID Group | Status | Evidence |
|----------|--------|----------|
| P-01a/b/c | WITHDRAWN (superseded) | 140-09-PATCH FIX-18; correctly reflected as `requirements-withdrawn` in 140-01-SUMMARY.md frontmatter, not silently dropped |
| P-01d/e | SATISFIED | `c02a_monotone`/`c02b_partition` invariants; `n_zip5_recovered_by_coalesce`/`pct_cohort_with_any_address` QC rows — all confirmed PASS on real data (2026-08-08) |
| P-02a/b/c | SATISFIED | `classify_unparseable_dates_vec()`; real-data confirmation 100% blank_or_null; `n_patients_lost_to_filters_c02` row |
| P-03a | DEFERRED (owner: Erin/Amy) | Crosswalk not obtained; contract documented, zero code changes needed once staged |
| P-03b/c | DEFERRED (owner: Erin/Amy) | Depend on P-03a; correctly recorded as `requirements-deferred` (not overstated as complete) in 140-02-SUMMARY.md frontmatter |
| P-04a/b | SATISFIED | `compute_gap_days_at_assignment()`; `median_gap_within_bin` diagnostic |
| P-05a/b | SATISFIED | `build_encounter_anchored_validation_cases()`; LOWER BOUND labeling |
| P-06a/b/c | SATISFIED | Independent backward-only waterfall; S1-fold-in; D-4 recorded |
| P-06d | WITHDRAWN/not triggered | Explicitly out of scope per D-4 = option-a; `utils_address.R` untouched by 140-04 (confirmed — only 140-07 touches that file, for the unrelated `addr_full` seam) |
| P-07a/b/c | SATISFIED | Universe cross-check; sentinel-nulling close-out; `addr_full` test seam |
| D-1 | SATISFIED (resolved, superseded) | Explicit user-directed decision recorded 2026-08-06, later superseded by D-5's invariant redesign — both transitions documented, not silent |
| D-2 | SATISFIED | Option-a, ZIP5 as analysis unit, recorded 2026-08-06 |
| D-3 | SATISFIED | Option-a, uncapped carry-forward, recorded 2026-08-10 |
| D-4 | SATISFIED | Option-a, backward-only primary, recorded 2026-08-08 |
| D-5 | SATISFIED | Option-c, no coverage floor, recorded 2026-08-07 — code correctly reflects the NON-default option chosen (two-invariant gate, not three) |

No orphaned requirement IDs found — every ID in 140-CONTEXT.md's current (amended) task/decision tables is claimed by exactly one plan's frontmatter `requirements` field.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (repo root) `140-CONTEXT.md`, `140-09-PATCH.md` | n/a | Stray untracked files at repository root duplicating/pre-dating phase-directory documents | ℹ️ Info | The root `140-CONTEXT.md` is a stale pre-planning snapshot ("Status: Ready for planning") that could mislead a future reader searching by filename instead of path. Does not affect the operative phase-directory copy, which every plan/SUMMARY correctly references. Recommend deleting or relocating before phase close-out. |
| `.planning/phases/140-.../140-01-SUMMARY.md`, `140-02-PLAN.md`, `140-02-SUMMARY.md`, `140-03-PLAN.md`, `140-CONTEXT.md`, `data/reference/README.md` | n/a | 140-09-PATCH's documentation corrections (FIX-19 through FIX-23) are present in the working tree but **not committed to git** | ⚠️ Warning | 140-09-SUMMARY.md explicitly flags this ("Not yet committed to git... pending an explicit instruction to commit") and 140-03-SUMMARY.md repeats the flag. All CODE changes for this phase are committed (verified via `git log`); only these documentation retro-corrections sit uncommitted. Not a functional gap — the corrected content is present and correct in the working tree, which is what this verification read — but it means the corrected frontmatter (e.g., 140-01/140-02's `requirements-withdrawn`/`requirements-deferred` splits) is not yet preserved in git history. Should be committed before phase close-out. |
| `R/utils/utils_address.R` | file-wide | Pre-existing unbalanced bracket/paren count (predates Phase 140, noted in 140-07-SUMMARY as originating from interval notation in a roxygen comment) | ℹ️ Info | Confirmed pre-existing (verified via `git show HEAD:R/utils/utils_address.R` per 140-07's own note) and not introduced by this phase. No action needed from Phase 140. |

No blocker anti-patterns found. No TODO/FIXME/placeholder/stub markers found in any file this phase modified.

### Human Verification Required

See YAML frontmatter `human_verification` block. Summary: this phase's diagnostic layer (140-01 + 140-09 + 140-03) was confirmed against real HiPerGator data on 2026-08-08 (`c02_reconciled = TRUE`, testthat 35/35 PASS). Everything built afterward — Waves 3-6 (140-04 S1-fold-in/backward-only waterfall, 140-05 gap-day covariates, 140-06 encounter-anchored validation curve, 140-07 universe cross-check + test seam) — has only ever been structurally balance-checked in this Windows planning environment, never executed against a real R runtime or real data. No plan in this phase claims otherwise; both 140-07-SUMMARY.md and STATE.md explicitly name this as the required next step before the workbook ships to Erin/Amy. Three items are needed:

1. A real HiPerGator run of the full amended `R/115_zip_stability_counts.R`.
2. A real `testthat::test_dir('tests/testthat')` run covering all 4 test files.
3. Re-issuing `output/zip_stability_counts_YYYYMMDD.xlsx` and confirming all 9 sheets open cleanly (no `output/zip_stability_counts*` file currently exists in this repo — the workbook has not yet been regenerated with Waves 3-6's changes).

### Gaps Summary

No goal-blocking gaps found. Every one of 140-CONTEXT.md's 24 task/decision IDs (P-01a..P-07c, D-1..D-5) is addressed in the code, correctly and non-circularly wired, and independently confirmed present via grep/read against the current file state (not merely asserted in SUMMARY prose). Every explicit team decision (D-1 through D-5) is reflected in the code exactly as resolved — including the two cases (D-5, D-4-adjacent P-06d) where the team chose the plan's non-default/non-recommended option, which required a documented follow-up code-removal pass rather than a silent mismatch between decision and implementation.

The phase's own stated exit criterion — "Nothing ships before `c02_reconciled = TRUE`" — is met on the one real-data run that has occurred (2026-08-08), which covered the diagnostic layer only. The status is `human_needed` rather than `passed` solely because Waves 3-6's code, while structurally sound and correctly wired at every checked link, has never been executed against a real R runtime or real data, and the workbook itself has not yet been re-issued. This is a known, explicitly-flagged limitation of the Windows planning environment (Rscript unavailable), not an implementation defect, and every plan in the phase transparently reported it as such.

---

*Verified: 2026-08-10T16:44:32Z*
*Verifier: Claude (gsd-verifier)*
