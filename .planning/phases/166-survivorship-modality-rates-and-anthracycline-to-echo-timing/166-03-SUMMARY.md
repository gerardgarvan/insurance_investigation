---
phase: 166-survivorship-modality-rates-and-anthracycline-to-echo-timing
plan: "03"
subsystem: survivorship-analysis
tags: [anthracycline, echocardiogram, competing-risk, CIF, survival]
dependency_graph:
  requires: [166-01, 166-02]
  provides: [survivorship_echo_parts_<date>.rds, utils_anthracycline_echo.R]
  affects: [168_survivorship_workbook]
tech_stack:
  added: [survival::survfit (AJ competing-risk), utils_anthracycline_echo.R]
  patterns: [competing-risk CIF via factor event, strict-after timing rule, D-08a first_line fallback]
key_files:
  created:
    - R/utils/utils_anthracycline_echo.R
    - R/167_anthracycline_echo.R
    - tests/testthat/test-166-echo.R
  modified: []
decisions:
  - "D-08a applied: first_line column absent from treatment_episode_detail_180.rds; all episodes treated as first-line (last_dose_firstline_dt == last_dose_ever_dt). Documented as D-166-02 fallback in driver."
  - "Script number 167 used for echo driver (per 166-AUDIT.md script_echo = 167), not 166 (which is the rates script)."
  - "echo_cif_km extracts echo CIF column by matching 'echo' in fit$states, not by positional index."
metrics:
  duration_minutes: 5
  completed_date: "2026-10-08"
  tasks_completed: 2
  files_created: 3
requirements_completed: [SRATE-03, SRATE-04]
---

# Phase 166 Plan 03: Anthracycline-to-Echo Timing Summary

**One-liner:** Aalen-Johansen CIF + per-patient echo rate after last anthracycline dose, four variants (primary/ever/dox-only/mitox), with strict-after timing and D-08a first-line fallback.

## What Was Built

### Task 1: Pure functions (TDD) — `R/utils/utils_anthracycline_echo.R`

Four pure functions, all taking ID-keyed tibbles:

- **`last_anthracycline_dose(episodes, drugs)`** — max admin_date per ID for first-line rows (`last_dose_firstline_dt`) and all rows (`last_dose_ever_dt`). Safe max helper returns `NA_Date_` on empty groups. D-08a: when `first_line` is absent, `last_dose_firstline_dt` is NA (driver sets all to TRUE).
- **`echo_time_to_event(doses, echo_events, followup, deaths, dose_col)`** — strict-after rule (`event_date > dose_date`), competing-risk `event_factor` with levels exactly `c("censored", "echo", "death")`, patients with `follow_end <= dose_date` excluded and counted in `n_no_time_after_last_dose`.
- **`echo_cif_km(tte, horizons)`** — AJ via `survival::survfit(Surv(time, event_factor) ~ 1)`, echo column extracted by name from `fit$states`, 1-KM computed in parallel, NA set for all horizons beyond `max(time_days)`.
- **`echo_rate_post_dose(doses, echo_events, followup, dose_col)`** — per-patient echo rate (echoes > dose_date and <= follow_end / person-years), NA when person-time <= 0. Long shape matching Plan 02 format.

**Tests (`tests/testthat/test-166-echo.R`):** 7 fixtures covering (a)-(g) per plan spec.

### Task 2: Driver — `R/167_anthracycline_echo.R`

- Loads `treatment_episode_detail_180.rds`, renames `patient_id` → `ID` and `treatment_date` → `admin_date`
- Applies `DRUG_NAME_ALIASES` from `R/00_config.R`
- D-08a: adds `first_line = TRUE` when column absent, logs D-166-02 fallback note
- D-166-01: per-drug patient counts via anthracycline pattern match
- Four variants: `primary`, `sens_ever`, `sens_dox_only`, `sens_mitox` (conditional on mitoxantrone_n > 0)
- Saves `survivorship_echo_parts_<run_date>.rds` (named list: `C_anthracycline_echo`, `cif_km_by_variant`, `echo_rate_patient`, `qc_echo`, `qc_anthracycline_drug_counts`, `d_166_01_record`, `episode_file_used`, `caveat_d14c`, `run_date`)

## Deviations from Plan

### Auto-applied Decisions

**1. [Rule 2 - Deviation] Script number 167 used instead of placeholder 166**
- **Found during:** Task 2 setup
- **Issue:** Plan frontmatter listed `R/166_anthracycline_echo.R` as a placeholder; the comment on line 13 said "use `script_echo` from 166-AUDIT.md". The audit's `script_echo: 167` is the correct number (R/166 is the rates script).
- **Fix:** Driver created as `R/167_anthracycline_echo.R`. The plan explicitly noted this was a placeholder.
- **Files modified:** `R/167_anthracycline_echo.R` (created with correct number)

**2. [Rule 2 - D-08a application] first_line absent -> driver sets TRUE for all**
- **Found during:** Task 2 load section
- **Issue:** 166-AUDIT.md confirms `first_line` absent from the 180-day file. The plan requires this to be handled.
- **Fix:** Driver adds `first_line = TRUE` to all episode rows when column is absent, logs a D-166-02 message, and includes `first_line_flag_absent = TRUE` in the QC block. Documented in `d_166_01_record`.

**3. [Rule 2 - Missing dependency guard] deaths_resolved handled when unavailable**
- **Found during:** Task 2 implementation
- **Issue:** The driver cannot call `resolve_death_date()` directly without the DuckDB DEATH table — which is only available on HiPerGator. An empty tibble fallback prevents the script from crashing if `deaths_resolved` is not pre-loaded.
- **Fix:** Guard clause that uses an empty `deaths_resolved` tibble and logs a NOTE when the object isn't in the environment. Deaths as competing event will correctly apply when `deaths_resolved` is loaded upstream.

## Commits

| Task | Commit | Files |
|------|--------|-------|
| Task 1 RED | 53180b7 | `tests/testthat/test-166-echo.R` |
| Task 1 GREEN | 61c76b0 | `R/utils/utils_anthracycline_echo.R` |
| Task 2 | ad87881 | `R/167_anthracycline_echo.R` |

## Known Stubs

None. The driver produces real outputs at HiPerGator runtime. All function logic is complete and testable. The HiPerGator run (Plan 04's checkpoint) is the first live execution.

## Self-Check: PASSED

- R/utils/utils_anthracycline_echo.R — FOUND
- R/167_anthracycline_echo.R — FOUND
- tests/testthat/test-166-echo.R — FOUND
- Commit 53180b7 (RED tests) — FOUND
- Commit 61c76b0 (GREEN functions) — FOUND
- Commit ad87881 (driver) — FOUND
