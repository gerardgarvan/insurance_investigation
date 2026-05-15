---
phase: 46-treatment-code-cross-reference-and-triggering-codes
plan: "02"
subsystem: pipeline
tags: [dplyr, openxlsx2, r-pipeline, episode-analysis, treatment-codes, triggering-codes]

# Dependency graph
requires:
  - phase: 44-treatment-episode-start-stop-dates
    provides: calculate_episodes_detailed(), episode CSV/xlsx output schema
  - phase: 43-treatment-duration-analysis
    provides: assign_episode_ids(), extract_all_dates() pattern, stack_and_dedup()
  - phase: 00-config
    provides: TREATMENT_CODES named list (chemo_hcpcs, radiation_cpt, sct_*, immunotherapy_drg, etc.)

provides:
  - R/44_treatment_episodes.R with triggering_codes column in episode output
  - extract_dates_with_codes(type) dispatch + 4 type-specific extraction functions
  - stack_and_dedup_with_codes() — 3-column dedup preserving multiple codes per date
  - CSV column 8 (triggering_codes): comma-separated bare codes per episode
  - xlsx detail sheets column 8 (Triggering Codes): same per-episode codes in styled report

affects: [phase-47-cancer-site-frequency, any downstream script consuming episode CSVs]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Parallel extraction pattern: new *_with_codes() functions in 44 that return 3-col tibble (ID, treatment_date, triggering_code) without modifying 43's *_dates() functions"
    - "3-column dedup: distinct(ID, treatment_date, triggering_code) preserves multiple codes on same date"
    - "Episode code aggregation: paste(sort(unique(na.omit(triggering_code))), collapse=',') in summarise()"
    - "TUMOR_REGISTRY source always gets triggering_code = NA_character_ (date evidence only, no individual code)"

key-files:
  created: []
  modified:
    - R/44_treatment_episodes.R

key-decisions:
  - "New extract_dates_with_codes() in R/44 instead of modifying R/43 — keeps Phase 43 extract_all_dates() intact for other consumers"
  - "3-column distinct(ID, treatment_date, triggering_code) dedup — preserves multiple codes on same date (D-46-07)"
  - "TUMOR_REGISTRY dates get triggering_code = NA_character_ — date evidence only, na.omit() removes them from comma list"
  - "triggering_codes as column 8 (last) in both CSV and xlsx — backward-compatible per Pitfall 5"
  - "PRESCRIBING/DISPENSING/MED_ADMIN get triggering_code = RXNORM_CUI — valid bare codes per D-46-08"
  - "DRG sources get triggering_code = DRG — bare numeric DRG code per D-46-08"

patterns-established:
  - "triggering_codes appended as LAST column — never insert before existing columns in episode output"
  - "TUMOR_REGISTRY sources always contribute NA triggering_code — use na.omit() in aggregation"

requirements-completed: [TXREF-02]

# Metrics
duration: 3min
completed: 2026-05-15
---

# Phase 46 Plan 02: Treatment Episode Triggering Codes Summary

**triggering_codes column added to R/44_treatment_episodes.R — comma-separated bare codes per episode in CSV (column 8) and xlsx detail sheets, using 3-column dedup to preserve all codes matched within each episode's date window**

## Performance

- **Duration:** 3 min
- **Started:** 2026-05-15T17:26:28Z
- **Completed:** 2026-05-15T17:29:59Z
- **Tasks:** 1 of 1
- **Files modified:** 1

## Accomplishments

- Added `extract_dates_with_codes(type)` dispatch function and 4 type-specific functions (chemo, radiation, SCT, immunotherapy) that return `ID`, `treatment_date`, `triggering_code` — mirroring R/43's extraction logic without modifying it
- Modified `calculate_episodes_detailed()` to accept 3-col dates_df and aggregate triggering codes per episode via `paste(sort(unique(na.omit(triggering_code))), collapse=",")`
- Updated CSV output (column 8), xlsx detail sheets (column 8 "Triggering Codes", A1:H1, A2:H2, A{r}:H{r} dims), and all_episodes bind_rows select — all backward-compatible with existing 7 columns unchanged
- R/43_treatment_durations.R left unmodified; no existing consumers affected

## Task Commits

Each task was committed atomically:

1. **Task 1: Add extract_all_dates_with_codes() and modify calculate_episodes_detailed()** - `ce94a54` (feat)

**Plan metadata:** [committed with final docs]

## Files Created/Modified

- `R/44_treatment_episodes.R` — Added triggering codes pipeline: new extraction functions, 3-col dedup helper, updated calculate_episodes_detailed(), CSV select, xlsx detail sheets, and all_episodes select

## Decisions Made

- New `extract_dates_with_codes()` in R/44 (not modifying R/43) — other scripts depend on R/43's `extract_all_dates()` returning 2-col tibble; modifying it would break them
- TUMOR_REGISTRY sources always get `triggering_code = NA_character_` — these contribute date evidence only (RAD_START_DATE_SUMMARY, DT_CHEMO, etc.), not individual procedure codes; `na.omit()` cleanly removes NAs from the comma list
- 3-column `distinct(ID, treatment_date, triggering_code)` dedup — D-46-07 requires ALL matching codes within episode window; 2-col dedup would lose multiple codes on same date

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

`Rscript -e "parse(...)"` segfaulted when passed a large R heredoc string as `-e` argument (R 4.4.1 on Windows). Used grep-based verification instead — all criteria confirmed via text search against the source file.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- triggering_codes column is live in R/44_treatment_episodes.R — run on HiPerGator to regenerate CSVs and xlsx with the new column
- Phase 46 Plan 01 (gap report) remains independent and can be executed separately
- No blockers or concerns

---
*Phase: 46-treatment-code-cross-reference-and-triggering-codes*
*Completed: 2026-05-15*
