---
phase: 44-treatment-episode-start-stop-dates
plan: 01
subsystem: analysis
tags: [treatment-episodes, per-episode-dates, historical-flagging, openxlsx2, episode-splitting]

# Dependency graph
requires:
  - phase: 00-config
    provides: "TREATMENT_CODES vectors, CONFIG paths, TREATMENT_TYPE_COLORS"
  - phase: 01-load-pcornet
    provides: "get_pcornet_table() backend dispatcher"
  - phase: 43-establish-treatment-lengths-for-sct-chemo-and-radiation
    provides: "extract_all_dates(), stack_and_dedup(), GAP_THRESHOLD, TREATMENT_TYPES"
provides:
  - "R/44_treatment_episodes.R - per-episode treatment start/stop date extraction"
  - "R/44_test_episodes.R - verification script with Phase 43 cross-reference"
  - "treatment_episodes.rds - per-patient per-type per-episode artifact (patient_id, treatment_type, episode_number, episode_start, episode_stop, episode_length_days, distinct_dates_in_episode, historical_flag)"
  - "treatment_episodes.xlsx - styled report with Summary + 4 per-type detail sheets + Historical Summary"
  - "4 per-type CSVs (chemotherapy_episodes.csv, radiation_episodes.csv, sct_episodes.csv, immunotherapy_episodes.csv)"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: ["per-episode detail output (one row per patient per type per episode)", "historical date flagging with 2012 cutoff", "episode-level xlsx with gray-fill historical rows"]

key-files:
  created: ["R/44_treatment_episodes.R", "R/44_test_episodes.R"]
  modified: []

key-decisions:
  - "Historical cutoff at 2012-01-01 — episodes with ALL dates before this are flagged (D-02, D-03)"
  - "Single-date historical episodes get start=stop, length=0 (D-04)"
  - "90-day window from episode start, not gap between consecutive dates (D-10, fixed post-plan)"
  - "One row per patient per treatment type per episode — not collapsed to patient-level (D-09)"
  - "Phase 43 outputs unchanged — Phase 44 is additive alongside, not replacing (D-05)"

patterns-established:
  - "Episode-level detail output pattern: expand Phase 43's per-patient summary to per-episode rows"
  - "Historical flagging: episode_stop < cutoff date identifies pre-modern-data episodes"
  - "Gray-fill xlsx styling for historical rows"

requirements-completed: [PHASE-44-GOAL]

# Metrics
duration: N/A
completed: 2026-05-11
---

# Phase 44 Plan 01: Treatment Episode Start/Stop Dates Summary

**Per-episode treatment start/stop dates with episode length and historical flagging for 4 treatment types**

## Performance

- **Completed:** 2026-05-11
- **Tasks:** 3 (2 auto, 1 human-verify)
- **Files created:** 2

## Accomplishments

- Per-episode detail output: one row per patient per treatment type per episode with start/stop dates, length, distinct date count, and historical flag
- Historical flagging for episodes where all dates precede 2012-01-01 (tumor registry data from 1970s-2000s)
- Styled xlsx with Summary sheet, 4 per-type detail sheets (historical rows gray-filled), and Historical Summary sheet
- 4 per-type CSV exports for downstream analysis
- Verification script validates schema, data quality, episode numbering contiguity, historical flag consistency, and cross-references Phase 43 episode counts

## Task Commits

1. **Task 1: Create R/44_treatment_episodes.R** — `d33232d` (feat)
2. **Task 2: Create R/44_test_episodes.R** — `f99e114` (feat)
3. **Post-plan fix: 90-day window from episode start** — `74a1c13` (fix)
4. **Post-plan fix: openxlsx2 API deprecation updates** — `57c6212` (fix)
5. **Task 3: UAT on HiPerGator** — 8/8 passed, `61ed1b9`

## Files Created/Modified

- `R/44_treatment_episodes.R` — Per-episode treatment date extraction with historical flagging, styled xlsx, per-type CSVs, and RDS output
- `R/44_test_episodes.R` — Verification script with structural checks, data quality validation, historical flag consistency, and Phase 43 cross-reference

## Verification Results

- UAT: 8/8 tests passed, 0 issues
- Main script runs end-to-end producing all output artifacts
- Verification script passes all checks including Phase 43 episode count cross-reference
- RDS artifact has correct 8-column schema
- Styled xlsx has 6 sheets (Summary + 4 per-type + Historical Summary)
- 4 per-type CSVs produced with correct schema
- Historical flagging correct — pre-2012 episodes identified
- Phase 43 outputs unchanged

## Decisions Made

- D-10 corrected post-plan: 90-day window measured from episode start rather than gap between consecutive dates
- openxlsx2 API calls updated to current non-deprecated patterns

## Deviations from Plan

- Episode splitting logic corrected (90-day window from episode start instead of gap between dates) — fix applied to both Phase 43 and 44
- openxlsx2 API calls updated for deprecation warnings

## Issues Encountered

None — all issues resolved before UAT.

## User Setup Required

None.

## Next Phase Readiness

- treatment_episodes.rds available for Phase 46 (date-level payer tier expansion)
- Episode-level detail enables per-episode payer assignment and longitudinal analysis

---
*Phase: 44-treatment-episode-start-stop-dates*
*Completed: 2026-05-11*
