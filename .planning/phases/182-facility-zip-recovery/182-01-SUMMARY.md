---
phase: 182-facility-zip-recovery
plan: 01
subsystem: data-pipeline
tags: [facility-zip, encounter-distance, R, dplyr, testthat]

requires:
  - phase: 152-encounter-distance
    provides: R/122_encounter_distance.R skeleton, enc_for_dist frame
  - phase: 153-zip-calendar
    provides: compute_encounter_distance(), normalize_zip5_raw()

provides:
  - R/utils/utils_facility_zip.R (FACILITYID_PLACEHOLDERS, facility_key_ok, build_facility_zip_lookup, apply_facility_zip_fill)
  - CONFIG$facility_zip_fill toggle in R/00_config.R
  - R/122 wired with fill step; enc_distance carries facility_zip_source

affects:
  - 182-02 (diagnostic workbook reads fill counts from enc_distance)
  - 182-03 (HiPerGator run confirms fill numbers)

tech-stack:
  added: []
  patterns:
    - "Facility ZIP fill: build lookup from supporting encounters, apply in one left_join; na_matches='never' prevents NA key collisions"
    - "Tier 1 fill rule: exactly one distinct ZIP5 with >= 3 supporting encounters"
    - "facility_zip_source column: observed/filled_tier1/not_filled/not_filled_no_key"
    - "CONFIG toggle pattern: CONFIG$facility_zip_fill = TRUE; FALSE reproduces pre-182 output"

key-files:
  created:
    - R/utils/utils_facility_zip.R
    - tests/testthat/test-utils-facility-zip.R
  modified:
    - R/00_config.R
    - R/122_encounter_distance.R

key-decisions:
  - "D-01: Fill key = SOURCE + FACILITYID; na_matches='never' prevents cross-partner and NA collisions"
  - "D-02: Tier 1 = exactly one distinct ZIP5 with >= 3 supporting encounters; any disagreement = no fill"
  - "D-05: facility_zip_source has 4 values (observed/filled_tier1/not_filled/not_filled_no_key); not_filled_no_key refines not_filled for NA/blank/placeholder IDs"
  - "D-08: CONFIG$facility_zip_fill toggle (default TRUE); FALSE = exact pre-182 R/122 output"
  - "enc_for_dist carries zip5_facility (filled) and facility_zip_source; joined back by ENCOUNTERID after dist_result join"

patterns-established:
  - "utils_facility_zip.R: no library() calls, no I/O, dplyr only — sourced by R/122 after R/00_config.R"
  - "FACILITYID_PLACEHOLDERS constant: c('', '0', 'NI', 'UN', 'UNK', 'UNKNOWN', 'OT', 'NA')"

requirements-completed: [FZIP-01, FZIP-02]

duration: 35min
completed: 2026-10-14
---

# Phase 182 Plan 01: Facility ZIP Fill Helper Summary

**Tier 1 facility ZIP fill utility (SOURCE+FACILITYID key, >=3 supporting encounters, exactly 1 distinct ZIP) wired into R/122 behind CONFIG$facility_zip_fill toggle; enc_distance carries facility_zip_source provenance column**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-10-14T00:00:00Z
- **Completed:** 2026-10-14
- **Tasks:** 3 + pre-flight (Task 0)
- **Files modified:** 4

## Pre-Flight Findings (Task 0)

- **Section 3 select line:** `dplyr::select(ID, ENCOUNTERID, ADMIT_DATE, ENC_TYPE, enc_zip_raw = FACILITY_LOCATION)` — FACILITYID and SOURCE added per D-06.
- **Section 4 fill insertion point:** Between `enc_for_dist <- encounters_raw %>% dplyr::mutate(zip5_facility = normalize_zip5_raw(enc_zip_raw))` (L259) and `dist_result <- compute_encounter_distance(enc_for_dist, cal)` (L263). Fill step goes there.
- **enc_distance frame:** zip5_facility enters at L537 (enc_distance select). After the fill, facility_zip_source is also carried in via ENCOUNTERID join then included in the enc_distance select.
- **FACILITYID placeholder list:** `FACILITYID_PLACEHOLDERS <- c("", "0", "NI", "UN", "UNK", "UNKNOWN", "OT", "NA")` — 8 codes. HiPerGator pre-flight run (182-03 checkpoint) will reveal whether the real extract has additional placeholder values.

## Accomplishments

- Created `R/utils/utils_facility_zip.R` with `FACILITYID_PLACEHOLDERS`, `facility_key_ok()`, `build_facility_zip_lookup()`, `apply_facility_zip_fill()` — pure dplyr helpers, no I/O, no library() calls
- Created `tests/testthat/test-utils-facility-zip.R` with 10 test_that blocks (tests run on HiPerGator in 182-03)
- Added `CONFIG$facility_zip_fill <- TRUE` to `R/00_config.R` (FALSE = pre-182 repro)
- Wired fill step into R/122: source utils_facility_zip.R in Section 1; add FACILITYID/SOURCE to Section 3 select; insert `build_facility_zip_lookup` + `apply_facility_zip_fill` + message in Section 4; join filled zip5_facility and facility_zip_source onto encounters; add facility_zip_source to enc_distance select

## Task Commits

1. **Test (TDD RED): add failing tests** - `5f869a6` (test)
2. **Task 1: utils_facility_zip.R** - `73b5c3f` (feat)
3. **Task 3: CONFIG toggle + R/122 wiring** - `4a58b24` (feat)

## Files Created/Modified

- `R/utils/utils_facility_zip.R` — facility ZIP fill helpers (pure functions, dplyr only)
- `tests/testthat/test-utils-facility-zip.R` — 10 unit test blocks
- `R/00_config.R` — added CONFIG$facility_zip_fill toggle (line ~263)
- `R/122_encounter_distance.R` — sourced utils_facility_zip.R; added FACILITYID/SOURCE to pull; inserted fill step with message; joined facility_zip_source; added to enc_distance select

## Decisions Made

- Task 2 (unit tests) written as TDD RED step before Task 1 implementation per plan's `tdd="true"` — tests committed at 5f869a6, impl at 73b5c3f
- `facility_zip_source` carried in enc_distance RDS (not workbook only) — enables downstream scripts (R/179, R/180) to see provenance without re-running R/122

## Deviations from Plan

None — plan executed exactly as written. Task 0 (pre-flight read-only) findings recorded above.

## Issues Encountered

None

## Next Phase Readiness

- R/122 wiring is complete; 182-02 can now add the Section 12b diagnostic workbook using fill counts from enc_distance and fac_lookup
- Unit tests written but NOT yet run — HiPerGator run in 182-03 is the test gate
- enc_distance RDS will carry `facility_zip_source` on next R/122 run

---
*Phase: 182-facility-zip-recovery*
*Completed: 2026-10-14*
