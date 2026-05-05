---
phase: 43-establish-treatment-lengths-for-sct-chemo-and-radiation
plan: 01
subsystem: analysis
tags: [treatment-duration, episodes, openxlsx2, ggplot2, tumor-registry, episode-splitting]

# Dependency graph
requires:
  - phase: 00-config
    provides: "TREATMENT_CODES vectors (chemo, radiation, SCT, immunotherapy codes)"
  - phase: 01-load-pcornet
    provides: "get_pcornet_table() backend dispatcher"
  - phase: 42-treatment-codes-resolved-xlsx-all-types
    provides: "TREATMENT_TYPE_COLORS styling and openxlsx2 workbook patterns"
provides:
  - "R/43_treatment_durations.R - multi-source treatment duration extraction and analysis"
  - "R/43_test_durations.R - verification script with clinical plausibility checks"
  - "treatment_durations.rds - per-patient per-type duration artifact (ID, treatment_type, first/last dates, span, distinct dates, episodes)"
  - "treatment_durations.xlsx - styled report with Summary + 4 per-type detail sheets"
  - "treatment_duration_distributions.png - boxplot of duration distributions by type"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: ["multi-source date extraction with dedup", "episode splitting at 90-day gap threshold", "per-patient duration metrics"]

key-files:
  created: ["R/43_treatment_durations.R", "R/43_test_durations.R"]
  modified: []

key-decisions:
  - "90-day gap threshold for episode splitting (D-05)"
  - "All chemo codes pooled together — no regimen distinction between ABVD/BV+AVD/salvage (D-13)"
  - "Immunotherapy limited to CAR-T ICD-10-PCS codes + DRG 018 — no RXNORM/DX sources"
  - "Pre-2000 dates retained — real tumor registry historical data, not sentinels (15th-of-month pattern confirms TR origin)"
  - "Single-date patients preserved with span=0, count=1, episodes=1 (D-03)"

patterns-established:
  - "Multi-source date extraction: query 7 PCORnet tables per type, stack, dedup with distinct(ID, treatment_date)"
  - "Episode splitting: lag() + cumsum(new_episode) pattern for gap-based episode detection"
  - "Verification script pattern: structural checks, data quality flags, clinical plausibility thresholds, cross-type overlap"

requirements-completed: [PHASE-43-GOAL]

# Metrics
duration: N/A
completed: 2026-05-05
---

# Phase 43 Plan 01: Treatment Duration Analysis Summary

**Per-patient treatment duration metrics for 4 types (Chemo/Radiation/SCT/Immunotherapy) from 7 PCORnet tables with 90-day episode splitting, styled xlsx, and distribution visualization**

## Performance

- **Duration:** Across multiple sessions
- **Completed:** 2026-05-05
- **Tasks:** 2 (1 auto, 1 human-verify)
- **Files created:** 2

## Accomplishments

- Extracted ALL treatment dates from 7 PCORnet tables for 4 treatment types (4,494 chemo, 1,292 radiation, 993 SCT, 170 immunotherapy patients)
- Per-patient duration metrics: first-to-last span, distinct date count, episode count with 90-day gap threshold
- Styled xlsx report with Summary sheet + 4 per-type detail sheets using TREATMENT_TYPE_COLORS
- Verification script with 6-area validation (structure, per-type stats, data quality, clinical plausibility, cross-type overlap, output files)

## Task Commits

1. **Task 1: Create R/43_treatment_durations.R** — `86f4a8b` (feat)
2. **Verification script** — `03bff05` (feat)
3. **Pre-2000 date deep dive** — `b34da6f` (feat)
4. **Task 2: Human verification on HiPerGator** — confirmed by user

## Files Created/Modified

- `R/43_treatment_durations.R` — 764-line treatment duration extraction, computation, xlsx report, and boxplot PNG
- `R/43_test_durations.R` — Verification script with structural checks, clinical plausibility flags, pre-2000 date deep dive, and cross-type overlap analysis

## Verification Results

- **6,949 rows** across 4,941 unique patients
- **Chemo:** median span 147 days, IQR [48, 394], median 9 distinct dates — consistent with ABVD ~6 cycles
- **Radiation:** median span 29 days, IQR [12, 48], median 8 distinct dates — matches 3-4 weeks of daily fractions
- **SCT:** median span 209 days, IQR [6, 896], median 4 distinct dates — elevated due to DX codes capturing post-transplant follow-up
- **Immunotherapy:** median span 0, 76.5% single-date — expected given limited code capture (CAR-T PCS + DRG 018 only)
- **Pre-2000 dates (70 rows):** Real tumor registry data (15th-of-month pattern), not sentinels. 17 bridge patients inflate max spans but medians unaffected.
- **Cross-type overlap:** 1,693 multi-type patients; top combos: Chemo+Radiation (771), Chemo+SCT (546), Chemo+Radiation+SCT (223)
- All data quality checks passed (no negatives, no date flips, no duplicates)

## Decisions Made

- Pre-2000 dates kept as-is — confirmed as real historical tumor registry abstractions, impact on medians negligible
- SCT duration metric captures post-transplant follow-up via DX codes (Z94.84, T86.5), not just transplant event — documented as known limitation
- Immunotherapy capture limited to 2 sources (PCS + DRG) since no dedicated RXNORM/DX vectors exist in TREATMENT_CODES

## Deviations from Plan

None — plan executed as written. Verification script added beyond plan scope for clinical validation.

## Issues Encountered

None — script ran to completion on HiPerGator, all outputs generated successfully.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Treatment duration RDS artifact available for downstream payer-stratified analysis
- SCT duration interpretation should account for DX-code-driven inflation in any reports
- Phases 38 (Chemo Inventory by Source) and 42 (Treatment Codes Resolved All Types) remain planned but unexecuted

---
*Phase: 43-establish-treatment-lengths-for-sct-chemo-and-radiation*
*Completed: 2026-05-05*
