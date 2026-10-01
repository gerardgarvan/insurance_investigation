---
phase: 161
plan: "03"
subsystem: death-date-resolution
tags: [death, person-time, survival, plausibility, grace-period, utils]
dependency_graph:
  requires: [161-02]
  provides: [utils_activity, utils_death, death_sensitivity_driver]
  affects: [R/147, person-time calculations, time-to-event analyses]
tech_stack:
  added: []
  patterns: [dplyr-throughout, duckdb-register-on-exit, purrr-map-dfr]
key_files:
  created:
    - R/utils/utils_activity.R
    - R/utils/utils_death.R
    - R/161_death_sensitivity.R
  modified: []
decisions:
  - D1 (grace = 30 days) implemented as default; sensitivity table at 0/30/60/90/365 documents choice
  - D2 (implausible -> NA) implemented; death_date_resolved is never the last-contact date
  - D3 (source priority N>S>D>L>T, then earliest) implemented via arrange+distinct
  - D4 (shared utils) satisfied; both files auto-sourced by R/00_config.R list.files()
metrics:
  duration: ~20 min
  completed: "2026-10-01"
  tasks: 3
  files: 3
---

# Phase 161 Plan 03: Shared Activity and Death-Date Resolution Utilities Summary

Implemented `get_last_activity()`, `resolve_death_date()`, `death_sensitivity_table()`, and the `R/161_death_sensitivity.R` driver — the shared utilities that every person-time and time-to-event calculation must use (D4).

## What Was Built

### `R/utils/utils_activity.R`

Exports `ACTIVITY_SOURCES` (named list of nine PCORnet CDM tables and their date columns) and `get_last_activity(con, ids, cutoff)`.

**Function signature:**
```r
get_last_activity(con, ids, cutoff)
# Returns tibble: ID, last_enc_any, last_activity_any, last_activity_src, last_observed
```

- Registers the cohort ID frame as a DuckDB virtual table (`duckdb_register`) with `on.exit` cleanup.
- Queries ENCOUNTER for the latest discharge-or-admit date (greatest of the two, capped at cutoff).
- Queries all nine ACTIVITY_SOURCES tables that exist in the database, unions the per-table maximums, picks the overall latest per patient.
- Returns `last_observed = pmax(last_enc_any, last_activity_any, na.rm = TRUE)`, which is the canonical follow-up end date for all scripts (before applying death date).

### `R/utils/utils_death.R`

Exports `DEATH_SOURCE_PRIORITY`, `resolve_death_date()`, and `death_sensitivity_table()`.

**Function signature:**
```r
resolve_death_date(death_tbl, activity_tbl, grace_days = 30L,
                   source_priority = DEATH_SOURCE_PRIORITY)
# Returns tibble: one row per cohort ID
```

**Output columns:**

| Column | Description |
|---|---|
| `death_date_raw` | Earliest recorded DEATH_DATE; NA if no record |
| `n_death_dates` | Distinct recorded death dates |
| `death_date_resolved` | Credible death date; NA if D2 applies |
| `death_source_resolved` | DEATH_SOURCE of chosen date; NA if D2 applies |
| `death_flag` | See below |
| `post_death_activity_days` | Days from `death_date_raw` to `last_observed` (0 if none) |

**`death_flag` values (five, exhaustive):**

| Value | Meaning |
|---|---|
| `plausible` | Single death date; activity within grace window |
| `implausible_post_activity` | Single death date; activity > grace_days after it (D2: `death_date_resolved = NA`) |
| `conflicting_resolved` | Multiple dates; at least one consistent with activity; D3 applied |
| `conflicting_unresolved` | Multiple dates; none consistent with activity (D2: `death_date_resolved = NA`) |
| `no_death_record` | Patient has no row in DEATH table |

**D2 guarantee:** `death_date_resolved` is `NA` for every `implausible_post_activity`, `conflicting_unresolved`, and `no_death_record` patient — never the last-contact date.

**`death_sensitivity_table(death_tbl, activity_tbl, grace_values = c(0L, 30L, 60L, 90L, 365L))`** iterates `resolve_death_date()` at each threshold and returns a tibble with one row per grace value and seven count columns.

### `R/161_death_sensitivity.R`

Driver script that:
1. Opens DuckDB read-only.
2. Builds the HL cohort via `get_hl_any_dx_ids()` (same denominator as R/147).
3. Computes `get_last_activity()` with `CUTOFF_DATE`.
4. Fetches DEATH rows for cohort patients via DuckDB virtual table join.
5. Runs `death_sensitivity_table()` and writes `output/161_death_sensitivity.csv`.
6. Prints reproduction check: `sum(post_death_activity_days > 30)` must equal 261; warns if not.
7. Writes `output/161_death_flags_n30.csv` (aggregate flag counts at N = 30).

### Wiring into `R/00_config.R`

No manual `source()` lines were needed. The existing `list.files(here::here("R/utils"), pattern = "\\.R$")` loop at the end of `R/00_config.R` automatically picks up both new files. Both utilities are available in every script that sources `R/00_config.R`.

## Deviations from Plan

None — plan executed exactly as written. The `R/00_config.R` auto-source mechanism already covered step 3 of the plan (explicit `source()` calls); no file modification was required.

## Known Stubs

None. The driver reads live DuckDB tables; no hardcoded or mocked data flows to output.

## Self-Check: PASSED

- `R/utils/utils_activity.R` — created
- `R/utils/utils_death.R` — created
- `R/161_death_sensitivity.R` — created
- Commit `40ad195` contains all three files
