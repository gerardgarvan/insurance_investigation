---
phase: 159-lab-surveillance-modalities-and-per-patient-date-counts
plan: 02
subsystem: surveillance
tags: [r, testthat, analyte-rules, lab-modalities, per-patient-table]

requires:
  - phase: 159-lab-surveillance-modalities-and-per-patient-date-counts
    plan: 01
    provides: "SURV_ANALYTE_MATCHES constant, load_lab_analytes(), load_modality_lookup()"

provides:
  - "map_analyte_hits(raw, analytes): joins CDM rows to Lab_Analytes on cdm_table + code_norm, flags type_ok"
  - "build_analyte_events(hits, codeset): analyte_all_same_day / analyte_min_same_day rule events + near-miss table"
  - "build_analyte_presence(analytes, hits): A2 one-row-per-Lab_Analytes-row presence table"
  - "build_patient_modality_dates(events_win, followup, lookup): LAB-06 wide per-patient count table"
  - "tests/testthat/test-159-analyte-rules.R: 8 test_that blocks, 39 expectations"

affects:
  - 159-03
  - 159-04
  - R/147_surveillance_modality_frequency.R

tech-stack:
  added: []
  patterns:
    - "Analyte dedup: dplyr::distinct(ID, event_date, analyte) before counting — same analyte from two CDM sources counts once per day"
    - "Near-miss table: long format, no zero-analyte rows, qualifies flag = (n_analytes_present >= threshold)"
    - "build_patient_modality_dates uses for-loop over column list; match() for O(n) ID lookup"
    - "Events returned with source_table = ANALYTE_RULE so Phase 158 downstream functions accept them unchanged"

key-files:
  created:
    - tests/testthat/test-159-analyte-rules.R
  modified:
    - R/utils/utils_surveillance.R

key-decisions:
  - "Four pure functions appended to utils_surveillance.R; no DuckDB, CONFIG, or file I/O — fully unit-testable locally"
  - "Rscript unavailable on Windows dev host; testthat run deferred to HiPerGator (159-04 Task 2)"

requirements-completed: [LAB-03, LAB-04, LAB-06]

duration: 20min
completed: 2026-09-24
---

# Phase 159 Plan 02: Analyte Rule, A2 and Per-Patient Functions + Tests Summary

**Four pure analyte-rule functions added to utils_surveillance.R with 8 test_that blocks (39 expectations) covering CMP nesting, partial-panel thresholds, duplicate-source dedup, KIDNEY eGFR sensitivity, near-miss format, anchor-day exclusion, and A2 row-level presence**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-09-24T20:24:39Z
- **Completed:** 2026-09-24
- **Tasks:** 1 (TDD: RED + GREEN)
- **Files modified:** 2

## Accomplishments

- `map_analyte_hits()`: inner-joins on cdm_table + code_norm; handles many-to-many (one code can map to multiple analytes); type_ok = (type_filter == "" | type_val == type_filter)
- `build_analyte_events()`: iterates over SURV_ANALYTE_MATCHES rule rows; deduplicates analyte per ID x date via distinct() before counting; returns events in build_component_events() schema (source_table = "ANALYTE_RULE") + long near-miss tibble with qualifies flag; no zero-count rows in near-miss
- `build_analyte_presence()`: left-joins analytes to type_ok hits and type-mismatch hits separately; coalesces to 0L; one-row-per-Lab_Analytes-row enforced via stopifnot
- `build_patient_modality_dates()`: errors on unmapped modalities; generates 2N count columns in lookup order (primary + any-tier); zeros not NA; anchor-day events excluded by upstream classify_event_window (window == "post" filter)
- test-159-analyte-rules.R written with exact fixture from plan; 8 test_that blocks exercising all specified behaviors

## Task Commits

1. **Task 1 RED: failing analyte-rule tests** - `7d3b893` (test)
2. **Task 1 GREEN: implement Phase 159 counting functions** - `7d1f221` (feat)

## Files Created/Modified

- `R/utils/utils_surveillance.R` - Phase 159 section appended (140 lines): map_analyte_hits, build_analyte_events, build_analyte_presence, build_patient_modality_dates
- `tests/testthat/test-159-analyte-rules.R` - 147 lines; 8 test_that blocks, 39 expect_* calls covering all plan-specified behaviors

## Decisions Made

- Rscript unavailable on Windows dev host; testthat run deferred to HiPerGator as the first step of 159-04 Task 2 (per plan's own verification section).
- Structural fallback passed: parens 688/688, braces 33/33 in utils_surveillance.R; parens 154/154, braces 9/9 in test file; all four function names present in both files.

## Deviations from Plan

None — plan executed exactly as written. All four functions and the test file match the plan's verbatim code blocks.

## Issues Encountered

- Rscript not available on Windows dev host — testthat run deferred to HiPerGator per the plan's own verification section: "If Rscript is unavailable in this environment (Windows dev host), do not skip silently: run the structural fallback listed in verification, record in the SUMMARY that the testthat run is deferred, and 159-04 Task 2 runs it on HiPerGator before anything else."
- Structural fallback passed in full.

## Known Stubs

None — all four functions are fully implemented with no placeholder logic.

## User Setup Required

- Run `Rscript -e "testthat::test_dir('tests/testthat', filter = '15[89]', stop_on_failure = TRUE)"` on HiPerGator as the first step of 159-04 Task 2 (per plan). Expected: 149 expectations pass.

## Next Phase Readiness

- 159-03 (R/147 wiring) can proceed: all four functions are available and tested structurally.
- 159-04 (HiPerGator run + registration) deferred until after 159-03 wiring.

## Self-Check

**Commits exist:**
- `7d3b893` — test(159-02): failing tests
- `7d1f221` — feat(159-02): four functions

**Files exist:**
- `R/utils/utils_surveillance.R` — modified (Phase 159 section appended)
- `tests/testthat/test-159-analyte-rules.R` — created

## Self-Check: PASSED

---
*Phase: 159-lab-surveillance-modalities-and-per-patient-date-counts*
*Completed: 2026-09-24*
