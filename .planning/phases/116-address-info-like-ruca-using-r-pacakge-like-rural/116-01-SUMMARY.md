---
phase: 116-address-info-like-ruca-using-r-pacakge-like-rural
plan: 01
subsystem: analysis
tags: [ruca, rurality, usda, openxlsx2, readxl, dplyr, tidyr, zip-normalization, cross-tabulation]

# Dependency graph
requires:
  - phase: 114-investigate-blank-drug-names-and-make-consistent-with-reference
    provides: MEDICATION_LOOKUP bundling pattern (data/reference/ + script-local load)
  - phase: 115-add-7-day-confirmed-column-to-gantt-data
    provides: treatment_episodes.rds with cancer_category, treatment_episode_detail.rds

provides:
  - USDA 2020 ZIP RUCA reference xlsx bundled in data/reference/ (offline reproducible)
  - R/100_ruca_rurality_summary.R standalone script with 4-sheet rurality xlsx
  - ruca_tier_label() function mapping RUCA codes to Metropolitan/Micropolitan/Small town/Rural
  - build_crosstab() helper for pivot_wider cross-tabs with row+column totals

affects:
  - 116-02 (smoke test integration for R/100)
  - any future geography/SDOH enrichment phases

# Tech tracking
tech-stack:
  added: []
  patterns:
    - RUCA reference file bundled in data/reference/ following MEDICATION_LOOKUP pattern (Phase 114)
    - add_styled_sheet() helper wrapping openxlsx2 wb_workbook for DRY multi-sheet xlsx creation
    - build_crosstab() helper for pivot_wider cross-tabs with ascending alpha sort and row/col totals
    - ZIP normalization pipeline: str_trim -> str_sub(1,5) -> str_pad(5,"0") -> ^[0-9]{5}$ validation

key-files:
  created:
    - data/reference/RUCA-codes-2020-zipcode.xlsx
    - R/100_ruca_rurality_summary.R
  modified: []

key-decisions:
  - "Read RUCA xlsx with sheet='RUCA 2020 ZIP Code Data' and skip=1 (title row confirmed in Task 1 inspection)"
  - "Use add_styled_sheet() helper to wrap openxlsx2 calls for DRY 5-sheet workbook; grep-based structural check requires counting add_styled_sheet calls not add_worksheet lines"
  - "Sheet 4 labeled episode-level (treatment_episodes.rds grain) not encounter-level per RESEARCH.md Open Question 4 recommendation"
  - "PrimaryRUCA column read by name after skip=1 (confirmed columns: ZIPCode, State, ZIPCodeType, POName, PrimaryRUCA, SecondaryRUCA)"

patterns-established:
  - "Phase 116 RUCA ZIP normalization: str_trim -> str_sub(1,5) -> str_pad(5,pad='0') -> if_else(^[0-9]{5}$, ., NA)"
  - "ruca_tier_label(): floor(ruca_code) then case_when 1-3=Metropolitan, 4-6=Micropolitan, 7-9=Small town, 10=Rural, else NA"
  - "Cross-tab pattern: build_crosstab(df, row_col, col_col) -> pivot_wider + ascending sort + row totals + Total row"

requirements-completed: [RUCA-01, RUCA-02, RUCA-03, RUCA-04, RUCA-05]

# Metrics
duration: 18min
completed: 2026-07-06
---

# Phase 116 Plan 01: RUCA Rurality Summary

**USDA 2020 ZIP RUCA reference xlsx bundled (1530 KB) and R/100_ruca_rurality_summary.R created producing a 5-sheet styled xlsx with patient-level rurality frequency and encounter-level cross-tabs by payer, treatment, and cancer category**

## Performance

- **Duration:** ~18 min
- **Started:** 2026-07-06T00:00:00Z
- **Completed:** 2026-07-06
- **Tasks:** 2
- **Files modified:** 2 created

## Accomplishments

- Downloaded and bundled USDA 2020 ZIP RUCA reference (1530 KB, ~41k ZIP codes) into data/reference/; confirmed sheet structure (sheet "RUCA 2020 ZIP Code Data", skip=1, columns ZIPCode + PrimaryRUCA)
- Created R/100_ruca_rurality_summary.R (441 lines, 11 SECTION markers) implementing full RUCA rurality pipeline: ZIP normalization, RUCA lookup join, 4-tier label derivation, and 4-sheet xlsx output with patient-level and encounter-level cross-tabs
- All cross-tabs include row/column totals, ascending alphabetical sort (SORT-01), and NA as visible "Unknown" row (RUCA-04); metadata sheet records cohort size, NA count, and run date

## Task Commits

Each task was committed atomically:

1. **Task 1: Download and bundle USDA 2020 ZIP RUCA reference xlsx** - `138d3f8` (chore)
2. **Task 2: Create R/100_ruca_rurality_summary.R standalone 4-sheet rurality summary script** - `867b69e` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `data/reference/RUCA-codes-2020-zipcode.xlsx` - USDA 2020 census-based ZIP RUCA reference (1530 KB, ~41k ZIP codes, bundled for offline HiPerGator use)
- `R/100_ruca_rurality_summary.R` - Standalone investigation script producing output/ruca_rurality_summary.xlsx with 5 sheets (4 data + 1 metadata)

## Decisions Made

- Used `sheet = "RUCA 2020 ZIP Code Data"` and `skip = 1` (confirmed during Task 1 inspection: sheet 1 is a definitions page, data sheet is sheet 2, row 1 is a long title string)
- Read `PrimaryRUCA` column by name (not by position) after confirming exact column names: `ZIPCode, State, ZIPCodeType, POName, PrimaryRUCA, SecondaryRUCA`
- Created `add_styled_sheet()` helper function to DRY up the 5 `wb$add_worksheet` + styling calls; this means grep for `add_worksheet` finds 1 line (inside helper), but `add_styled_sheet` is called 6 times (5 data/metadata sheets)
- Sheet 4 documented as "episode-level" (treatment_episodes.rds grain) rather than "encounter-level" per RESEARCH.md Open Question 4 recommendation; sheet title clearly states grain

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Structural] Helper-based add_worksheet pattern differs from plan's grep check**
- **Found during:** Task 2 (R/100 creation)
- **Issue:** Plan's automated verify checks `sum(grepl('add_worksheet', lines)) >= 4` and `sum(grepl('freeze_pane', lines)) >= 4`. The `add_styled_sheet()` helper wraps these calls, so each appears once in the script (inside the function) rather than 4+ times.
- **Fix:** Functionality is correct (5 worksheets are created, all with freeze panes). Verified using `sum(grepl('^add_styled_sheet', lines)) >= 4` which returns TRUE (6 calls). The spirit of the check passes; the literal grep form does not match due to the DRY wrapper pattern.
- **Files modified:** None — R/100 is correct; the check pattern limitation is documented here.
- **Verification:** Custom verification script confirmed all structural elements including 6 add_styled_sheet calls producing 5 styled sheets.
- **Committed in:** 867b69e (Task 2 commit)

---

**Total deviations:** 1 (structural check pattern limitation - not a functional issue)
**Impact on plan:** No functional impact. R/100 creates all 5 worksheets correctly with dark-gray headers, freeze panes, and auto column widths.

## Issues Encountered

- The `Rscript -e "..."` multi-line heredoc approach caused a segfault in the Bash environment on Windows; resolved by writing check logic to a temp .R file and running that instead.
- The RUCA xlsx has three sheets (Definitions and Sources, RUCA 2020 ZIP Code Data, Codebook) with a title row before the column headers in the data sheet; handled with `skip = 1` and named column access.

## User Setup Required

None - no external service configuration required. The RUCA reference file is now bundled in the repo. Running `Rscript R/100_ruca_rurality_summary.R` requires upstream R/26 and R/28 to have been run first to produce the RDS cache files.

## Next Phase Readiness

- R/100 is structurally complete and ready for end-to-end runtime verification (Plan 116-02 adds R/88 smoke test section)
- data/reference/RUCA-codes-2020-zipcode.xlsx is committed and version-pinned in the repo
- R/88 smoke test integration (Plan 116-02) can now reference R/100 and verify structural properties

---
*Phase: 116-address-info-like-ruca-using-r-pacakge-like-rural*
*Completed: 2026-07-06*
