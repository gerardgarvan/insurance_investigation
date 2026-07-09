---
phase: 118-create-csv-that-outputs-patid-and-a-column-where-cause-of-death-is-non-hodgkins-lymphoma-true-or-cause-of-death-is-non-hodgkins-lymphoma-false
plan: "01"
subsystem: death-cause-investigation
tags: [death, nhl, cause-of-death, csv-export, three-state-flag, classify-codes]

dependency_graph:
  requires:
    - R/00_config.R (CONFIG$output_dir, auto-sources utils)
    - R/utils/utils_duckdb.R (get_pcornet_table, open_pcornet_con)
    - R/utils/utils_dates.R (parse_pcornet_date)
    - R/utils/utils_cancer.R (classify_codes)
    - DuckDB DEATH table
  provides:
    - R/102_death_cause_nhl_flag.R
    - output/death_cause_nhl_flag.csv (PATID, cause_of_death_is_nhl)
  affects:
    - R/39_run_all_investigations.R (investigation_scripts vector)
    - R/88_smoke_test_comprehensive.R (Section 15o, 14 checks)
    - R/SCRIPT_INDEX.md (Post-Renumber Investigations table)

tech_stack:
  added: []
  patterns:
    - Three-state logical flag (TRUE/FALSE/NA) via case_when + classify_codes()
    - write.csv(na="") for blank-cell NA rendering
    - DEATH_CAUSE / DEATH_CAUSE_CODE field-availability guard (D-78-01)
    - 1900 date sentinel coercion to NA via lubridate year()
    - Self-bootstrap DuckDB (USE_DUCKDB + guarded open_pcornet_con)

key_files:
  created:
    - path: R/102_death_cause_nhl_flag.R
      description: Standalone script -- DEATH table -> deceased set -> NHL three-state flag -> CSV
      lines: 226
  modified:
    - path: R/39_run_all_investigations.R
      description: R/102 added to investigation_scripts vector (after R/101)
    - path: R/88_smoke_test_comprehensive.R
      description: Section 15o added (14 checks + NHLDEATH-01/02/03 + SMOKE-118-01 summary)
    - path: R/SCRIPT_INDEX.md
      description: R/102 row added to Post-Renumber Investigations (100+) table

decisions:
  - "Three-state flag (TRUE/FALSE/NA) preserved -- missing DEATH_CAUSE is NA, not FALSE, to avoid misrepresenting uncoded deaths (D-04)"
  - "classify_codes() reused for NHL determination -- no hand-rolled ICD list (D-07)"
  - "Only deceased patients included (valid DEATH_DATE) -- alive patients excluded entirely (D-02)"
  - "DEATH_CAUSE field-availability guard degrades gracefully to all-NA when field absent (D-78-01)"
  - "Section 15o used for Phase 118 smoke test (continuing 15n -> 15o sequence)"

metrics:
  duration_minutes: 5
  completed_date: "2026-07-09"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 3
---

# Phase 118 Plan 01: Cause-of-Death NHL Flag CSV Summary

**One-liner:** Three-state cause_of_death_is_nhl CSV (TRUE/FALSE/blank) via classify_codes("Non-Hodgkin Lymphoma") on DEATH table, one row per deceased patient with valid DEATH_DATE.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | Create R/102_death_cause_nhl_flag.R | 2cac8c0 | R/102_death_cause_nhl_flag.R (created, 226 lines) |
| 2 | Register R/102 in R/39, add R/88 Section 15o, update SCRIPT_INDEX | a8e7406 | R/39_run_all_investigations.R, R/88_smoke_test_comprehensive.R, R/SCRIPT_INDEX.md |

## What Was Built

### R/102_death_cause_nhl_flag.R

A new standalone "100+" investigation script (226 lines) following the R/101 pattern. The script:

1. Self-bootstraps the DuckDB connection (`USE_DUCKDB <- TRUE; if (!exists("pcornet_con"))`)
2. Loads the DEATH table via `get_pcornet_table("DEATH") %>% collect()`
3. Applies the DEATH_CAUSE / DEATH_CAUSE_CODE field-availability guard (D-78-01) — degrades gracefully to all-NA if neither field exists
4. Parses `DEATH_DATE` via `parse_pcornet_date()`, coerces year-1900 sentinel to NA, drops NA dates
5. Aggregates to one death record per patient (`group_by(ID)`, `min(DEATH_DATE)`, `first(DEATH_CAUSE)`)
6. Computes the three-state flag via `classify_codes()`:
   - `TRUE` — DEATH_CAUSE classifies as "Non-Hodgkin Lymphoma"
   - `FALSE` — DEATH_CAUSE is a different, coded cause
   - `NA` — DEATH_CAUSE is missing/empty (blank cell in CSV)
7. Writes `output/death_cause_nhl_flag.csv` with `write.csv(row.names = FALSE, na = "")` — NA renders as blank cells

**Output columns:** `PATID` (renamed from DEATH table's `ID`), `cause_of_death_is_nhl`

### Registration and Smoke Testing

- **R/39:** R/102 appended after R/101 in the `investigation_scripts` vector
- **R/88 Section 15o:** 14 structural checks covering all NHLDEATH requirements; SKIPPED fallback for missing-script case; NHLDEATH-01/02/03 + SMOKE-118-01 summary messages added to requirements-echo block
- **R/SCRIPT_INDEX.md:** Row added to Post-Renumber Investigations (100+) table

## Verification Results

All 8 structural verification checks pass (Windows-local, no data):

1. DEATH table read (`get_pcornet_table("DEATH")`) — PASS
2. NHL determination (`classify_codes(` + `"Non-Hodgkin Lymphoma"`) — PASS
3. Three-state flag (`case_when`) — PASS
4. Blank-cell NA convention (`row.names = FALSE`, `na = ""`) — PASS
5. No visualization libs (no ggplot2/geom_/ggsave) — PASS
6. R/39 registered (`102_death_cause_nhl_flag`) — PASS
7. R/88 smoke-tested (`SECTION 15o`) — PASS
8. SCRIPT_INDEX indexed (`R/102_death_cause_nhl_flag.R`) — PASS

**Runtime verification (HiPerGator-only):** Sourcing R/102 against the real PCORnet DuckDB will write `output/death_cause_nhl_flag.csv` with columns `PATID` and `cause_of_death_is_nhl`; NA rows render as blank cells; TRUE/FALSE print literally; row count equals number of deceased patients with valid DEATH_DATE. This executor runs Windows-local without the data; structural verification is consistent with Phase 116/117 precedent.

## Deviations from Plan

None — plan executed exactly as written.

## Requirements Satisfied

- **NHLDEATH-01:** R/102 derives deceased set from DEATH table (parse_pcornet_date, 1900 sentinel, filter NA dates, group_by(ID) per-patient aggregation)
- **NHLDEATH-02:** `cause_of_death_is_nhl` three-state flag via `classify_codes() == "Non-Hodgkin Lymphoma"` (TRUE / FALSE / NA); NA renders as blank cell
- **NHLDEATH-03:** R/102 writes `output/death_cause_nhl_flag.csv` (PATID + flag, `row.names=FALSE, na=""`)
- **SMOKE-118-01:** R/88 Section 15o validates Phase 118 structural integrity (14 checks)

## Self-Check: PASSED

Files verified:
- `R/102_death_cause_nhl_flag.R` — FOUND (226 lines, 7 SECTION markers)
- `R/39_run_all_investigations.R` contains `102_death_cause_nhl_flag` — FOUND
- `R/88_smoke_test_comprehensive.R` contains `SECTION 15o` and `SMOKE-118-01` — FOUND
- `R/SCRIPT_INDEX.md` contains `R/102_death_cause_nhl_flag.R` — FOUND

Commits verified:
- `2cac8c0` — FOUND (feat: R/102 creation)
- `a8e7406` — FOUND (feat: R/39, R/88, SCRIPT_INDEX updates)
