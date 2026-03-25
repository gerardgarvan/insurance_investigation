---
phase: 06-use-debug-output-to-rectify-issues
plan: 02
subsystem: data-loading
tags: [date-parsing, col-types, numeric-validation, payer-mapping, pcornet-cdm, data-quality]

# Dependency graph
requires:
  - phase: 06-01
    provides: "HL_SOURCE tracking and Neither exclusion in cohort predicates"
  - phase: 05-02
    provides: "07_diagnostics.R script producing diagnostic CSVs"
provides:
  - "_VALID validation columns for age, tumor size, and date fields in load_pcornet_table()"
  - "Diagnostic validation comments confirming date parser, regex, and col_types are correct"
  - "R vs Python payer mapping comparison documentation in 00_config.R"
  - "Known missing value and encoding documentation in TABLE_SPECS"
affects: [06-03, pipeline-rebuild, data-quality-summary]

# Tech tracking
tech-stack:
  added: [dplyr (added to 01_load_pcornet.R imports)]
  patterns: ["_VALID suffix columns for range validation (preserve raw, flag outliers)", "Diagnostic validation comments documenting audit results in-code"]

key-files:
  created: []
  modified:
    - "R/utils_dates.R"
    - "R/01_load_pcornet.R"
    - "R/00_config.R"

key-decisions:
  - "All TR coded columns stay character despite tr_type_audit flagging them as numeric -- preserves ICD-O-3 morphology codes and NAACCR staging semantics"
  - "No new date format handlers needed -- diagnostics confirmed existing 4 formats are sufficient for this cohort extract"
  - "No date regex expansion needed -- all date columns already matched by current pattern"
  - "_VALID columns added as non-destructive flags (raw values preserved) for downstream filtering decisions"
  - "Date validation uses 5-year future tolerance window to catch extreme sentinels while allowing reasonable future dates"

patterns-established:
  - "_VALID suffix pattern: range validation columns that preserve raw data and flag outliers for downstream filtering"
  - "Diagnostic validation comments: documenting audit results directly in code with Phase/Plan provenance"

requirements-completed: [RECT-03, RECT-04]

# Metrics
duration: 4min
completed: 2026-03-25
---

# Phase 6 Plan 02: Data-Driven Fixes from Diagnostic Output Summary

**Validation columns (_VALID) for age/tumor-size/date ranges, diagnostic audit comments confirming parser/regex/col-types correctness, and R vs Python payer distribution documentation**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-25T18:37:36Z
- **Completed:** 2026-03-25T18:41:09Z
- **Tasks:** 2 (1 checkpoint + 1 auto)
- **Files modified:** 3

## Accomplishments
- Added _VALID validation columns for AGE_AT_DIAGNOSIS, DXAGE, TUMOR_SIZE_SUMMARY/CLINICAL/PATHOLOGIC, and all parsed date columns -- flags sentinels (200, 999, negatives) and implausible dates (pre-1900, extreme future)
- Documented diagnostic validation results directly in code: date parser confirmed sufficient (4 formats), date regex confirmed complete (all columns matched), TR coded columns confirmed correct as character type
- Added R vs Python payer mapping comparison comment block with R pipeline percentages (Medicaid 43.66%, Private 28.58%, Dual 11.01%, Medicare 8.91%, etc.)
- Documented known missing value patterns (ENCOUNTER.DISCHARGE_DATE 70.87%, PRESCRIBING.RX_DAYS_SUPPLY 92.89%, TR1 all date columns 100% NA)
- Documented encoding finding (TR1.HISTOLOGICAL_TYPE_DESCRIPTION: 8 non-ASCII chars, cosmetic only)

## Task Commits

Each task was committed atomically:

1. **Task 1: User shares diagnostic output from HiPerGator** - checkpoint (no commit -- user-provided data)
2. **Task 2: Apply all data-driven fixes to pipeline scripts** - `e7a680a` (feat)

**Plan metadata:** (pending -- final commit below)

## Files Created/Modified
- `R/utils_dates.R` - Added diagnostic validation comment confirming 4 date formats are sufficient
- `R/01_load_pcornet.R` - Added _VALID validation columns for ages, tumor sizes, and dates; diagnostic comments for regex, col_types, missing values, and encoding; added library(dplyr)
- `R/00_config.R` - Added R vs Python payer mapping comparison comment block with percentages and HL identification context

## Decisions Made
- **TR coded columns stay character:** tr_type_audit.csv flagged many columns as "Consider col_double()" but these are ICD-O-3 morphology codes, NAACCR staging codes, and site codes. Changing to numeric would lose leading zeros (e.g., "0200" -> 200) and misrepresent categorical semantics.
- **No new date format handlers:** date_parsing_failures.csv confirmed all NA values are genuine missing data, not parse failures. The existing 4-format chain handles all date formats in this cohort extract.
- **No date regex expansion:** date_column_regex_audit.csv showed all date columns matched (regex_match = TRUE for every column).
- **5-year future tolerance for date validation:** Allows reasonable future dates (e.g., projected enrollment ends) while catching extreme sentinels like 2173-09-27 (279 future enrollment dates).
- **Non-destructive validation pattern:** _VALID columns flag outliers without modifying raw values, preserving data for downstream analysis decisions.

## Deviations from Plan

None -- plan executed as written. The diagnostic findings drove specific implementation choices:
- Batches 1-3 resulted in documentation-only changes (diagnostics confirmed existing code is correct)
- Batch 4 (validation columns) was the primary code addition
- Batch 5 (payer docs) applied as specified
- Batch 6 (missing values) resulted in inline documentation

## Issues Encountered
None

## Known Stubs
None -- all changes are complete implementations, not placeholders.

## User Setup Required
None -- no external service configuration required.

## Next Phase Readiness
- All data-driven fixes from diagnostic output are applied
- _VALID columns ready for use by downstream pipeline scripts (filtering, data quality reporting)
- Ready for Plan 03: diagnostics update, data quality summary script, and full pipeline rebuild
- Python pipeline payer percentages marked TBD -- user can fill in when available

## Self-Check: PASSED

All files verified present. Commit e7a680a confirmed in git log.

---
*Phase: 06-use-debug-output-to-rectify-issues*
*Completed: 2026-03-25*
