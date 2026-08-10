---
phase: 139-zip-stability-imputation-occurrence-counts
plan: 04
subsystem: data
tags: [r, dplyr, openxlsx2, testthat, zip-normalization, address-history, encounter-classification, xlsx-assembly]

# Dependency graph
requires:
  - phase: 139-01
    provides: addr_coal column contract, coalesce_zip5(), gap_days_summary, SECTION 1B pattern
  - phase: 139-02
    provides: build_validation_cases()/aggregate_validation_curve(), validation_curve table
  - phase: 139-03
    provides: classify_encounter_zip(), encounter_zip, scenario_assigned, COHORT_IDS, scenario_counts_*/unordered_* tibbles
provides:
  - compute_c02(cohort_ids, addr_coal) as a pure, testable function in SECTION 1B (139-05-PATCH FIX-03b)
  - waterfall_encounter / waterfall_patient (C-01, cumulative stepwise completeness tables)
  - QC sheet tibble (qc_tbl) consolidating every drop/exclusion count logged across Plans 01-04
  - KEY sheet tibble (key_tbl) with FIX-01/FIX-04d/tolerance/coalescing narrative
  - Full 8-sheet styled xlsx (output/zip_stability_counts_YYYYMMDD.xlsx) via wb_workbook()
  - R/115 registered in R/39's investigation_scripts vector (final entry)
  - R/88 Section 15ad (14 structural checks, SMOKE-139-01 footer)
  - R/SCRIPT_INDEX.md row + updated script counts (16 post-renumber, 102 total)
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "compute_c02() left-joins the study cohort onto addr_coal's per-patient zip5-ever summary, coalesce(FALSE) so absence from addr_coal counts toward the numerator rather than being invisible to group_by()"
    - "Cumulative stepwise waterfall built from an already-ordered, mutually-exclusive factor column (scenario_assigned) via count() + arrange() + cumsum() -- no separate 'total' row needed since the bottom row sums to the full universe by construction"
    - "Patient-level waterfall bucket = furthest-resolved scenario per patient (group_by(ID) + slice_min on a numeric priority rank matching factor level order), distinct from Part B's patient-presence reporting which allows multi-scenario membership"
    - "xlsx failure flagging goes on the deliverable itself (UF_ORANGE-filled QC cell), not just console output, since the xlsx is what gets forwarded to the team"
    - "add_styled_sheet()/color constants copied locally (not sourced) per this project's established convention; UF_BLUE/UF_ORANGE are phase-local brand colors, deliberately distinct from utils_pptx.R's own UF_BLUE"

key-files:
  created: []
  modified:
    - R/115_zip_stability_counts.R
    - tests/testthat/test-115-validation-curve.R
    - R/39_run_all_investigations.R
    - R/88_smoke_test_comprehensive.R
    - R/SCRIPT_INDEX.md
  created-new:
    - .planning/phases/139-zip-stability-imputation-occurrence-counts/deferred-items.md

key-decisions:
  - "compute_c02() computed over COHORT_IDS (139-03's study cohort), not addr_coal's own patient set -- a cohort patient entirely absent from addr_coal counts toward n_patients_no_zip5_ever (139-05-PATCH FIX-03b)"
  - "Pre-filter comparison (FIX-03c) reuses coalesce_zip5() against addr_raw directly -- no second coalescing implementation exists anywhere in the codebase (verified by R/88's single-implementation checks)"
  - "C-02 tolerance (+/-5) documented in the KEY sheet as covering cohort-definition drift only, not denominator or methodological uncertainty (FIX-03d), since the denominator is now cohort-scoped and correct"
  - "A C-02 reconciliation failure produces both a loud console message AND a UF_ORANGE-filled QC-sheet cell -- the xlsx itself carries the warning, since that is what gets forwarded to Erin/Amy, not just build-time console output"
  - "KEY sheet locks in FIX-01's A-06 framing (address-history-anchored, not a 'target encounter' reinterpretation) and FIX-04d's ordered-vs-unordered S3 distinction verbatim from Plans 02/03's SUMMARY text"
  - "A_stability_patient sheet reports bucketed patient-level distributions (0/1/2-5/6+ transition buckets), not raw per-patient ID rows -- HIPAA-safe, consistent with R/106's own patient-level sheet convention"
  - "A_stability_summary's extra_tbl combines the fixed-bucket histogram and gap_days_deciles into one Type/Label/Value table (rather than dropping deciles in favor of the histogram alone), satisfying A-05's explicit median/IQR/deciles requirement"
  - "R/115 registered in R/39's investigation_scripts vector only, NOT expected_xlsx -- matches R/106's own established precedent for scripts with a date-stamped output filename"
  - "Two pre-existing R/88 failures (source_coverage_analysis.csv, MED_ADMIN fixture) are unrelated to Phase 139, confirmed via an additive-only diff to R/88, and logged to deferred-items.md rather than fixed (scope boundary)"

requirements-completed: [C-01, C-02]

# Metrics
duration: 35min
completed: 2026-08-05
---

# Phase 139 Plan 04: Part C Completeness Waterfall, C-02 Reconciliation, Full 8-Sheet XLSX Assembly Summary

**Cohort-scoped C-02 reconciliation (`compute_c02()`) with an unmissable console+xlsx failure flag, a stepwise C-01 completeness waterfall, and the full 8-sheet UF-branded `zip_stability_counts_YYYYMMDD.xlsx` deliverable, wired into R/39/R/88/SCRIPT_INDEX.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-08-05 (continuing from 139-03)
- **Completed:** 2026-08-05
- **Tasks:** 2 completed (both auto, both tdd="true")
- **Files modified:** 5 (4 existing files extended, 1 new deferred-items.md log)

## Accomplishments

- `compute_c02(cohort_ids, addr_coal)` added to `R/115_zip_stability_counts.R` SECTION 1B: left-joins the study cohort (`COHORT_IDS`) onto `addr_coal`'s per-patient "any usable ZIP5" summary, `coalesce(FALSE)` so a cohort patient with zero rows in `addr_coal` counts toward `n_patients_no_zip5_ever` rather than being invisible to `group_by()` (139-05-PATCH FIX-03b, the defect the patch exists to fix)
- SECTION 12 (Part C) added: `waterfall_encounter`/`waterfall_patient` cumulative stepwise completeness tables built directly from Part B's ordered `scenario_assigned` factor; C-02 reconciliation against a cohort-scoped ~26-patient expectation (`C02_EXPECTED`, `C02_TOLERANCE = 5`) with a loud, impossible-to-miss console failure message if it does not reconcile; FIX-03c pre-filter comparison via `coalesce_zip5(addr_raw)` (no second coalescing implementation)
- `tests/testthat/test-115-validation-curve.R` gained its 6th and final fixture: a cohort patient absent from a synthetic `addr_coal` counts toward `n_patients_no_zip5_ever` -- the exact assertion that catches the pre-patch "invisible to `group_by()`" defect. 21 tests total across the file, 0 failures
- SECTION 13 (QC sheet data) and SECTION 14 (KEY sheet data) added: QC consolidates every drop/exclusion count logged across Plans 01-04 (unparseable dates, out-of-range dates, sentinel-nulled counts, open-ended count, `n_excluded_no_prior`, cohort N, C-02 figures incl. pre-filter, PASS/FAIL flag, block-group-crosswalk availability); KEY documents FIX-01's A-06 framing, FIX-04d's ordered-vs-unordered-S3 distinction, the C-02 tolerance's narrowed claim, and the single-implementation `coalesce_zip5()` note, all in measured/neutral language
- SECTION 15 (xlsx assembly) added: `add_styled_sheet()`/UF_BLUE (`#0021A5`)/UF_ORANGE (`#FA4616`) copied locally (not sourced); full 8-sheet `wb_workbook()` assembled in order (KEY, A_stability_patient, A_stability_summary, A_validation_curve, B_scenario_counts, B_direction_split, C_completeness, QC); `A_stability_summary` carries Plan 01's `gap_days_summary` through in full (median/p25/p75/min/max + `gap_days_deciles` + histogram, combined into one Type/Label/Value extra table); QC sheet's C-02 row gets a UF_ORANGE fill + bold white font if `c02_reconciled` is `FALSE`, so the failure is visible in the deliverable itself, not just the console
- `R/39_run_all_investigations.R`: `R/115_zip_stability_counts.R` registered as the final `investigation_scripts` entry (comment mirrors R/106/R/114 style); NOT added to `expected_xlsx` (date-stamped filename, follows R/106's own non-inclusion precedent)
- `R/88_smoke_test_comprehensive.R`: Section 15ad added (14 structural checks: file-existence gates, single-implementation checks for `is_sentinel_zip5()`/`coalesce_zip5()`, `get_zip9_at_date()` unchanged-existence check, Part B/C content markers, `>=6` `test_that()` count, R/39 registration) + `SMOKE-139-01` footer line
- `R/SCRIPT_INDEX.md`: R/115 row added to the Post-Renumber Investigations table; Script Count summary updated (15->16 post-renumber, 101->102 total)

## Task Commits

Each task was committed atomically:

1. **Task 1: Part C completeness waterfall + compute_c02() + C-02 fixture + pre-filter comparison** - `ced5720` (feat, tdd)
2. **Task 2: QC sheet data, full 8-sheet xlsx assembly, R/39/R/88/SCRIPT_INDEX registration** - `a5e4fcf` (feat, tdd)

**Plan metadata:** (this commit, following SUMMARY.md creation)

## Files Created/Modified

- `R/115_zip_stability_counts.R` - SECTION 1B gained `compute_c02()`; new SECTION 12 (Part C waterfall + C-02 reconciliation + pre-filter comparison), SECTION 13 (QC sheet data), SECTION 14 (KEY sheet data), SECTION 15 (full 8-sheet styled xlsx assembly, `wb_save(wb, OUTPUT_XLSX)`)
- `tests/testthat/test-115-validation-curve.R` - Appended the 6th and final `test_that()` block (`compute_c02()` cohort-absent-patient fixture)
- `R/39_run_all_investigations.R` - `R/115_zip_stability_counts.R` added as `investigation_scripts`' final entry
- `R/88_smoke_test_comprehensive.R` - Section 15ad added (14 checks) + `SMOKE-139-01` summary line
- `R/SCRIPT_INDEX.md` - R/115 row added; Post-Renumber Investigations count 15->16, Total 101->102
- `.planning/phases/139-zip-stability-imputation-occurrence-counts/deferred-items.md` - New file logging 2 pre-existing, out-of-scope R/88 failures unrelated to Phase 139

## Decisions Made

See `key-decisions` in frontmatter above for the full list. Most consequential: `compute_c02()`'s cohort-scoped (not addr_coal-own-patient-set) design, which is the exact fix 139-05-PATCH FIX-03 exists to make; and the decision to flag a C-02 reconciliation failure directly on the xlsx (UF_ORANGE cell), not just in console output, since the xlsx is the artifact that actually ships to the team.

## Deviations from Plan

None of the code deviated from the plan text -- all 139-05-PATCH.md amendments referenced by this plan (FIX-03b, FIX-03c, FIX-03d, FIX-04d, FIX-01, FIX-05) were already incorporated into the plan text itself and implemented exactly as specified.

One process-level note, not a code deviation: `Rscript R/88_smoke_test_comprehensive.R` exits with status 1 overall (2/728 checks failed), not 0. Both failures are pre-existing and unrelated to Phase 139:
1. `source_coverage_analysis.csv` existence check (an older phase's output file, not touched by this plan)
2. `get_chemo_hits('MED_ADMIN')` local-fixture check (Phase 122)

Confirmed unrelated via `git diff --stat R/88_smoke_test_comprehensive.R` for this session, which shows only additive changes (74 insertions, 0 deletions) -- no pre-existing check logic was touched. Section 15ad itself (this plan's own structural checks) shows **14 PASS, 0 FAIL**, satisfying this plan's literal success criterion ("Section 15ad showing 0 FAIL"). Logged to `deferred-items.md` per the scope-boundary rule (only auto-fix issues directly caused by the current task's changes) rather than fixed.

## Issues Encountered

`Rscript` is not on PATH in this Windows shell; resolved by invoking the full path to `Rscript.exe` (`C:/Program Files/R/R-4.4.1/bin/Rscript.exe`), consistent with 139-01/02/03's same environment note. Multi-line `Rscript -e "..."` invocations via the Bash tool segfaulted on one occasion (same Windows Git Bash quoting/heredoc interaction noted in 139-03's SUMMARY, not an R code issue); resolved by writing verification scripts to `.R` files in the session scratchpad and invoking `Rscript <file>` instead. No source files were affected by this workaround.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 139 is now fully executed across all 4 plans (01: foundation/A-01..A-05, 02: A-06 validation curve, 03: Part B S1-S4 classification, 04: Part C waterfall + C-02 + full xlsx assembly + registration)
- `R/115_zip_stability_counts.R` parses cleanly end-to-end and is registered in `R/39`'s pipeline runner and `R/88`'s smoke test (Section 15ad, `SMOKE-139-01`) and `R/SCRIPT_INDEX.md`
- `tests/testthat/test-115-validation-curve.R` contains all 6 planned fixtures (stable patient, mover, +4-only mover, single-record patient, open-ended interval, C-02 cohort-absent-patient), 21 tests total, 0 failures
- Runtime verification -- actually running `Rscript R/115_zip_stability_counts.R` against real `LDS_ADDRESS_HISTORY`/`ENCOUNTER` data on HiPerGator, producing the real `output/zip_stability_counts_YYYYMMDD.xlsx`, and reviewing the real C-02 reconciliation result -- remains an open item requiring HiPerGator access, exactly as this plan's own `<verification>` section scoped it ("Runtime verification ... out of scope for this planning session but required before the deliverable ships"). This is the phase's definition-of-done gate, not a blocker to Phase 139's own planning/execution completion.
- Per this session's instructions, Phase 139 should now be ready for goal verification (`/gsd:verify-phase` or equivalent)

---
*Phase: 139-zip-stability-imputation-occurrence-counts*
*Completed: 2026-08-05*

## Self-Check: PASSED

- FOUND: R/115_zip_stability_counts.R
- FOUND: tests/testthat/test-115-validation-curve.R
- FOUND: R/39_run_all_investigations.R
- FOUND: R/88_smoke_test_comprehensive.R
- FOUND: R/SCRIPT_INDEX.md
- FOUND: .planning/phases/139-zip-stability-imputation-occurrence-counts/deferred-items.md
- FOUND: .planning/phases/139-zip-stability-imputation-occurrence-counts/139-04-SUMMARY.md
- FOUND commit: ced5720
- FOUND commit: a5e4fcf
