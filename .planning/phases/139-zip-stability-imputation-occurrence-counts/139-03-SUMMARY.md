---
phase: 139-zip-stability-imputation-occurrence-counts
plan: 03
subsystem: data
tags: [r, dplyr, testthat, zip-normalization, address-history, pcornet, encounter-classification]

# Dependency graph
requires:
  - phase: 139-01
    provides: addr_coal column contract (period_start_dt, period_end_dt, period_end_open, period_end_eff, zip9_norm, zip5_coalesced), zip9_seq/zip5_seq spell sequences, SECTION 1B testable-function prelude pattern
  - phase: 139-02
    provides: SECTION 1B pattern precedent (build_validation_cases()/aggregate_validation_curve()), tests/testthat/test-115-validation-curve.R growing-file pattern
provides:
  - classify_encounter_zip(encounters, addr_coal) as a pure, testable function in SECTION 1B (139-05-PATCH FIX-02/FIX-04c/FIX-04e)
  - encounter_zip tibble (cohort-restricted, per-encounter ZIP-availability classification) wired into SECTION 10
  - scenario_assigned ordered S1-S4 classification + unordered eligible-for counts (s1_backward/forward/either, s2_backward/forward/either, s3_eligible) wired into SECTION 11
  - COHORT_IDS (get_hl_patient_ids()) established as Part B/C's population, reusable by Plan 04
affects: [139-04-xlsx-assembly-and-c02]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Interval matching against period_end_eff (sentineled), never period_end_dt (NA-preserving) -- ADMIT_DATE < NA evaluates to NA and filter() silently drops the row, misclassifying every encounter covered by an open-ended (current) address record"
    - "semi_join pre-filter against the cohort-restricted encounters before a many-to-many interval join, applied unconditionally (not gated on a profiling flag)"
    - "Ordered-vs-unordered dual reporting: a case_when() cascade (first-match-wins) assignment column reported alongside independent per-scenario eligibility flags, so overlap hidden by the ordered rule remains visible"
    - "Forward-lookup implemented as new local script code (join zip9_seq/zip5_seq by direction relative to ADMIT_DATE) rather than extending get_zip9_at_date(), which is explicitly Out of Scope for modification and only looks backward"

key-files:
  created: []
  modified:
    - R/115_zip_stability_counts.R
    - tests/testthat/test-115-validation-curve.R

key-decisions:
  - "classify_encounter_zip() replicates get_zip9_at_date()'s own tie-break priority (non-NA zip9_norm preferred, then most-recent period_start_dt) locally rather than calling get_zip9_at_date(), because Part B needs the coalesced ZIP5 visible alongside ZIP9 for S1/S3 classification, which get_zip9_at_date()'s derived-only ZIP5 output would mask"
  - "has_neither is split into has_no_record (no covering address record exists at all) and has_record_but_empty (a covering record exists with both ZIP9 and ZIP5 NA) -- these are different data conditions, and S2's own definition presumes a record exists (139-05-PATCH FIX-04e)"
  - "S2 eligibility (backward/forward/either) is computed against zip5_seq, not zip9_seq, because S2 covers both the take-ZIP9-from-another-encounter path and the ZIP5-centroid path; any backward zip5_seq spell satisfies at least the centroid path. resolution_path (take_zip9 vs centroid_only) is computed from the nearest backward spell for reporting transparency only -- it does not gate eligibility"
  - "S3 eligibility is defined as the complement of S1-eligible-backward within the has_direct_zip5_only set (by construction, mutually exclusive) and stays backward-only, matching S3's own definition ('does not match the PRIOR ZIP9's ZIP5')"
  - "The ordered scenario_assigned column (S1 then S2 then S3) and the unordered per-scenario eligibility flags are BOTH computed and printed -- an encounter eligible only via S1-forward is assigned S1 by the ordered rule while remaining S3-eligible under the unordered definition (139-05-PATCH FIX-04d); a console NOTE makes this explicit so the ordered S3 count is never misread as the complete S3-eligible population"
  - "S3 is reported strictly as an occurrence count with an explicit 'S3 resolution still pending as of 08/04 notes' message -- no resolution path (backward-carry vs. drop vs. something else) is presented as decided (B-01)"
  - "S4 (complete-case comparator) is the complement of has_direct_zip9, reported separately from the ordered S1/S2/S3 assignment, not folded into it"
  - "Every count (ordered and unordered) is reported at both encounter level (denominator: n_encounters_total) and patient level (denominator: n_patients_with_encounters, patient-level rows report PRESENCE across scenarios, not a forced single category per patient) -- denominators are named directly in accompanying console messages, not left implicit (B-02)"

requirements-completed: [B-01, B-02, B-03, B-04]

# Metrics
duration: 20min
completed: 2026-08-05
---

# Phase 139 Plan 03: Encounter ZIP Classification + S1-S4 Occurrence Counts Summary

**Cohort-restricted per-encounter ZIP classification (period_end_eff-based interval match) feeding an ordered S1-then-S2-then-S3 imputation-scenario assignment plus unordered eligible-for counts with backward/forward/either direction splits, all reported at encounter and patient level.**

## Performance

- **Duration:** 20 min
- **Started:** 2026-08-05 (continuing from 139-02)
- **Completed:** 2026-08-05
- **Tasks:** 2 completed (both auto)
- **Files modified:** 2 (both existing files extended, none created)

## Accomplishments
- `classify_encounter_zip(encounters, addr_coal)` added to `R/115_zip_stability_counts.R` SECTION 1B: locally replicates `get_zip9_at_date()`'s own interval tie-break logic (non-NA ZIP9 preferred, then most-recent `period_start_dt`) against `period_end_eff` (sentineled), not `period_end_dt` (NA-preserving) -- the 139-05-PATCH FIX-02 fix that prevents every encounter covered by a patient's current (open-ended) address from misclassifying as `has_neither`
- `semi_join` pre-filter against the cohort-restricted `encounters` is applied unconditionally before the many-to-many interval join (139-05-PATCH FIX-04c)
- `has_neither` split into `has_no_record` (no covering record at all) and `has_record_but_empty` (a covering record exists with both ZIP9 and ZIP5 NA), both reported with `has_neither` kept as their union (139-05-PATCH FIX-04e)
- SECTION 10 added: cohort restriction via `get_hl_patient_ids()` (139-05-PATCH FIX-03a, reusing the established R/106/R/107/R/109/R/111 pattern verbatim), cohort-restricted `ENCOUNTER` pull via `get_pcornet_table`, and the real-data call to `classify_encounter_zip()` producing `encounter_zip`, with cohort N and encounter-level headline counts logged
- SECTION 11 added: S1/S2 eligibility (backward/forward/either) computed against `zip9_seq`/`zip5_seq` respectively (forward lookup implemented as new local join logic, since `get_zip9_at_date()` only looks backward and is Out of Scope for modification); S3 eligibility (backward-only, complement of S1-backward); `scenario_assigned` ordered S1-then-S2-then-S3 assignment; S4 reported separately as the complete-case comparator
- Both ordered-assignment and unordered-eligible-for count tables built at encounter AND patient level with denominators named in accompanying console messages; the 139-05-PATCH FIX-04d ordered-vs-unordered-S3 distinction is called out via an explicit console `NOTE`; S3's own headline is flagged "S3 resolution still pending as of 08/04 notes"
- `tests/testthat/test-115-validation-curve.R` gained the open-ended-interval fixture (139-05-PATCH FIX-05/FIX-02): an encounter covered by a `period_end_dt = NA` record classifies `has_direct_zip9 == TRUE`, not `has_neither` -- 18 total tests across the file, 0 failures

## Task Commits

Each task was committed atomically:

1. **Task 1: Cohort-restricted ENCOUNTER pull + classify_encounter_zip() (period_end_eff, semi_join default, has_no_record/has_record_but_empty split)** - `0d2ad64` (feat, tdd)
2. **Task 2: S1-S4 ordered and unordered scenario assignment with direction split** - `c740566` (feat, tdd)

**Plan metadata:** (this commit, following SUMMARY.md creation)

## Files Created/Modified
- `R/115_zip_stability_counts.R` - SECTION 1B gained `classify_encounter_zip()`; new SECTION 10 (Part B cohort restriction + ENCOUNTER pull + real-data classification call) and SECTION 11 (S1-S4 eligibility, ordered/unordered scenario counts, console reporting) appended. No xlsx write (deferred to Plan 04).
- `tests/testthat/test-115-validation-curve.R` - Appended one new `test_that()` block (open-ended-interval fixture) exercising `.test_env$classify_encounter_zip()`, captured by the file's existing `sys.source()` pattern since `classify_encounter_zip()` is defined in SECTION 1B before the probe gate.

## Decisions Made
See `key-decisions` in frontmatter above for the full list. Most consequential: replicating (not calling) `get_zip9_at_date()`'s interval tie-break logic to keep the coalesced ZIP5 visible for S1/S3 classification, and the explicit dual reporting (ordered `scenario_assigned` vs. unordered per-scenario eligibility flags) that 139-05-PATCH FIX-04d requires so the ordered "S3" column is never mistaken for the complete S3-eligible population.

## Deviations from Plan

None - plan executed exactly as written. All 139-05-PATCH.md amendments referenced by this plan (FIX-02, FIX-03a, FIX-04c, FIX-04d, FIX-04e) were already incorporated into the plan text itself and implemented as specified. Task 2's `tdd="true"` frontmatter tag did not require new test additions -- Task 2's own `<files>` list and `<action>`/`<verify>` blocks specify only `R/115_zip_stability_counts.R` changes with structural (grep-based) verification, no new `test_that()` block; this was followed literally rather than forcing an unrequested test addition.

## Issues Encountered

`Rscript` is not on PATH in this Windows shell; resolved by invoking the full path to `Rscript.exe` (`C:/Program Files/R/R-4.4.1/bin/Rscript.exe`), consistent with 139-01/139-02's same environment note. A multi-line `Rscript -e "..."` invocation via the Bash tool segfaulted (likely a Windows Git Bash quoting/heredoc interaction, not an R code issue); resolved by writing the verification script to a `.R` file in the session scratchpad and invoking `Rscript <file>` instead. No source files were affected.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `encounter_zip` (cohort-restricted, per-encounter ZIP-availability + scenario eligibility/assignment) is fully computed at the script level and ready for Plan 04 to pull directly into the `B_scenario_counts` xlsx sheet without re-deriving any of it
- `scenario_counts_encounter`, `scenario_counts_patient`, `unordered_encounter`, `unordered_patient` tibbles are assembled and named for direct reuse by Plan 04's sheet-writing code
- `COHORT_IDS` (via `get_hl_patient_ids()`) is established as Part B/C's population -- Plan 04's C-02 reconciliation against the notes' 26-patient control total is comparable against this same cohort definition
- The 139-05-PATCH FIX-04d ordered-vs-unordered-S3 language is locked in the console `NOTE` text for Plan 04's KEY sheet to reuse verbatim
- No xlsx write yet by design -- deferred to Plan 04 once all sheets' data exists
- Runtime verification against real `LDS_ADDRESS_HISTORY`/`ENCOUNTER` data (as opposed to parse-level and synthetic-fixture testthat checks) requires HiPerGator, consistent with 139-01/139-02's stated scope

---
*Phase: 139-zip-stability-imputation-occurrence-counts*
*Completed: 2026-08-05*

## Self-Check: PASSED

- FOUND: R/115_zip_stability_counts.R
- FOUND: tests/testthat/test-115-validation-curve.R
- FOUND commit: 0d2ad64
- FOUND commit: c740566
- Re-verified: testthat 0 failures across 18 tests (5 test_that blocks)
