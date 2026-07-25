---
phase: 135-shared-helper-standardization
plan: "03"
subsystem: cohort-validation
tags: [pattern-g, na-safety, death-validation, enrollment, treatment-flags]
dependency_graph:
  requires: []
  provides:
    - R/53 death-before-birth impossible-record guard (SECTION 4C)
    - R/14 enrollment aggregation NA-safe (min_or_na / max_or_na)
    - R/31 episode summarise NA-safe (min_or_na / max_or_na)
    - R/93 no-treatment filter NA-correct (coalesce pattern)
  affects:
    - output/death_date_validation.xlsx (Flagged Patients sheet gains Death before birth rows)
    - output/no_treatment_medicaid_patients.csv (now includes NA-flagged patients)
tech_stack:
  added: []
  patterns:
    - min_or_na / max_or_na for grouped summarise aggregation
    - coalesce(HAD_*, 0L) == 0L pattern for NA-safe treatment flag filters
key_files:
  created: []
  modified:
    - R/53_death_date_validation.R
    - R/14_build_cohort.R
    - R/31_pre_diagnosis_treatments.R
    - R/93_no_treatment_medicaid.R
decisions:
  - "DEMOGRAPHIC PATID column used as ID in SECTION 4C join — consistent with rest of R/53"
  - "R/93 near-miss tx_medicaid filter uses coalesce(HAD_*, 0L)==1L conservatively (NA treated as not-treated, not as treated)"
metrics:
  duration_minutes: 10
  completed_date: "2026-07-25"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 4
---

# Phase 135 Plan 03: PATTERN-G Guards (Death-Before-Birth, NA-Safe Min/Max, NA-Safe Treatment Flags) Summary

**One-liner:** Added death-before-birth guard (SECTION 4C) to R/53, replaced bare min/max with min_or_na/max_or_na in R/14 and R/31, and applied coalesce(HAD_*, 0L) NA-safety to all three R/93 treatment filters.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add death-before-birth check to R/53 | 678abd7 | R/53_death_date_validation.R |
| 2 | Apply min_or_na/max_or_na in R/14, R/31; fix NA-drop in R/93 | 2803b38 | R/14_build_cohort.R, R/31_pre_diagnosis_treatments.R, R/93_no_treatment_medicaid.R |

## What Was Done

### Task 1 — R/53 SECTION 4C: Death Before Birth

Inserted a new `SECTION 4C` block between the existing Section 4B (death-before-HL-diagnosis) and Section 5 (post-death clinical activity). The block:

1. Loads DEMOGRAPHIC table via `get_pcornet_table("DEMOGRAPHIC")` and parses `BIRTH_DATE`.
2. Joins to `valid_deaths` and computes `age_at_death_days = difftime(DEATH_DATE, BIRTH_DATE, units = "days")`.
3. Flags `death_before_birth = !is.na(BIRTH_DATE) & !is.na(DEATH_DATE) & age_at_death_days < 0`.
4. If any impossible records are found: builds `impossible_birth` tibble, removes those patients from `valid_deaths` via `anti_join`, and logs counts.
5. Before writing the Flagged Patients sheet: `if (exists("impossible_birth") && nrow(impossible_birth) > 0)` appends those rows with `flag_type = "Death before birth"`.

### Task 2 — R/14, R/31, R/93

**R/14 (lines 269-270):** Replaced `min(ENR_START_DATE, na.rm = TRUE)` / `max(ENR_END_DATE, na.rm = TRUE)` with `min_or_na(ENR_START_DATE)` / `max_or_na(ENR_END_DATE)`. When all enrollment records for a patient are NA-dated, bare min/max returns `Inf`; `min_or_na` returns `NA` correctly.

**R/31 (grouped summarise + total row):** Replaced bare `min(days_before_dx)` / `max(days_before_dx)` with `min_or_na` / `max_or_na` in both the `group_by` summarise block and the scalar `total_row` tibble.

**R/93 (three filter sites):**
- `no_tx_medicaid`: replaced `HAD_CHEMO == 0` etc. with `coalesce(HAD_CHEMO, 0L) == 0L` — NA treatment flags now correctly include patients in the no-treatment population.
- `all_no_tx`: same coalesce pattern applied.
- `tx_medicaid` (Medicaid WITH treatment comparison): replaced `HAD_CHEMO == 1` etc. with `coalesce(HAD_CHEMO, 0L) == 1L` — NA remains conservatively excluded from "treated".

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Self-Check: PASSED

- R/53: SECTION 4C present, `death_before_birth` pattern present, `impossible_birth` flagged-patients append present — FOUND
- R/14: `min_or_na(ENR_START_DATE)` at line 269, `max_or_na(ENR_END_DATE)` at line 270 — FOUND
- R/31: `min_or_na(days_before_dx)` and `max_or_na` in grouped summarise and total row — FOUND
- R/93: `coalesce(HAD_CHEMO, 0L)` in no_tx_medicaid, all_no_tx, tx_medicaid — FOUND
- Commits 678abd7 and 2803b38 exist — VERIFIED
