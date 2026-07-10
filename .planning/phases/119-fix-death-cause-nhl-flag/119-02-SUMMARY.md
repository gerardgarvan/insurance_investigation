---
phase: 119-fix-death-cause-nhl-flag
plan: 02
subsystem: data-loading
tags: [pcornet, death_cause, loader, duckdb, table-spec, smoke-test]

# Dependency graph
requires:
  - phase: 119-fix-death-cause-nhl-flag
    plan: 01
    provides: R/103 diagnostic (Wave-0 gate) confirming DEATH_CAUSE is the cause-of-death source to load
provides:
  - DEATH_CAUSE wired into PCORNET_TABLES (count 15 -> 16) with default-pattern path resolution
  - DEATH_CAUSE_SPEC (7 all-character cols) registered in TABLE_SPECS so R/01 loads the table
  - DuckDB auto-ingest of DEATH_CAUSE via TABLES_TO_INGEST <- PCORNET_TABLES (no R/03 edit)
  - R/88 IS_LOCAL fixture table-count assertion bumped 15 -> 16
affects: [119-03-rewrite-r102, 119-04-smoke-test]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "5-touch-point add-a-table recipe: PCORNET_TABLES + PCORNET_PATHS (R/00) + col spec in TABLE_SPECS (R/01) + auto-ingest (R/03) + smoke-test count (R/88)"
    - "R/03 requires zero edits when a non-ENCOUNTERID table is added (TABLES_TO_INGEST <- PCORNET_TABLES auto-includes it)"

key-files:
  created: []
  modified:
    - R/00_config.R
    - R/01_load_pcornet.R
    - R/88_smoke_test_comprehensive.R

key-decisions:
  - "No PCORNET_PATHS override added: DEATH_CAUSE resolves via the default {TABLE}_Mailhot_V1.csv pattern (user-confirmed filename DEATH_CAUSE_Mailhot_V1.csv). A Phase 119 comment flags this as a runtime unknown and points to the LAB_RESULT_CM override pattern if the filename differs on HiPerGator."
  - "R/03_duckdb_ingest.R left UNCHANGED: TABLES_TO_INGEST <- PCORNET_TABLES auto-includes DEATH_CAUSE, and DEATH_CAUSE has no ENCOUNTERID so TABLES_WITH_ENCOUNTERID is unchanged (verified by reading R/03 lines 47-56)."
  - "DEATH_CAUSE_SPEC uses ID (not PATID) as the patient key, matching the rest of this extract and the join key to DEATH (RESEARCH Pitfall 4)."
  - "R/88 note added that the local fixture DuckDB must be rebuilt to include DEATH_CAUSE, else the count check reports 15 (RESEARCH Pitfall 6)."

requirements-completed: [NHLFIX-02]

# Metrics
duration: 2min
completed: 2026-07-10
---

# Phase 119 Plan 02: Load DEATH_CAUSE Table Summary

**Wired the PCORnet CDM DEATH_CAUSE table into the pipeline via the 5-touch-point recipe (config + loader spec + smoke-test count) so cause-of-death codes become queryable through get_pcornet_table("DEATH_CAUSE") after a HiPerGator R/01+R/03 rebuild.**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-07-10
- **Completed:** 2026-07-10
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- Added `"DEATH_CAUSE"` as the final entry of `PCORNET_TABLES` in R/00_config.R (count 15 -> 16), with a comment noting the ID join key to DEATH. The existing `setNames(...)` build resolves its path from the default `{TABLE}_Mailhot_V1.csv` pattern.
- Defined `DEATH_CAUSE_SPEC` (7 all-character columns: ID, DEATH_CAUSE, DEATH_CAUSE_CODE, DEATH_CAUSE_TYPE, DEATH_CAUSE_SOURCE, DEATH_CAUSE_CONFIDENCE, SOURCE) in a new "6c. DEATH_CAUSE" banner section of R/01_load_pcornet.R, and registered `DEATH_CAUSE = DEATH_CAUSE_SPEC` in TABLE_SPECS.
- Bumped the R/88 IS_LOCAL fixture DuckDB table-count assertion from `== 15` to `== 16` and added a Phase 119 note about rebuilding the local fixture; left the production `>= 13` branch unchanged.
- Confirmed R/03_duckdb_ingest.R needs no edit: `TABLES_TO_INGEST <- PCORNET_TABLES` auto-includes DEATH_CAUSE, and DEATH_CAUSE (no ENCOUNTERID) is correctly absent from `TABLES_WITH_ENCOUNTERID`.

## Task Commits

1. **Task 1: Add DEATH_CAUSE to PCORNET_TABLES + path resolution (R/00_config.R)** - `9ea8031` (feat)
2. **Task 2: Define DEATH_CAUSE_SPEC and register in TABLE_SPECS (R/01_load_pcornet.R)** - `9cea83c` (feat)
3. **Task 3: Bump R/88 IS_LOCAL fixture table-count 15 -> 16** - `0f88191` (test)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP) committed separately.

## Files Created/Modified
- `R/00_config.R` - DEATH_CAUSE appended to PCORNET_TABLES (16 tables); Phase 119 runtime-unknown comment near PCORNET_PATHS naming DEATH_CAUSE_Mailhot_V1.csv; load-set count comment updated to 16.
- `R/01_load_pcornet.R` - DEATH_CAUSE_SPEC (7 character cols) added after DEATH_SPEC; DEATH_CAUSE registered in TABLE_SPECS (comma added to the DEATH line).
- `R/88_smoke_test_comprehensive.R` - IS_LOCAL fixture table-count assertion `== 15` -> `== 16` with a Phase 119 rebuild note; production branch untouched.

## Decisions Made
- No PCORNET_PATHS override needed: default `{TABLE}_Mailhot_V1.csv` pattern resolves `DEATH_CAUSE_Mailhot_V1.csv` (user-confirmed filename). A Phase 119 comment flags the runtime unknown and references the LAB_RESULT_CM override pattern as the fix if the name differs on HiPerGator.
- R/03 left unchanged (verified lines 47-56): auto-ingest picks up DEATH_CAUSE; no ENCOUNTERID so no index change.
- DEATH_CAUSE_SPEC keys on ID (not PATID), matching the extract convention and the DEATH join key.

## Deviations from Plan
None - plan executed exactly as written. (The load-set descriptive comment above PCORNET_TABLES read "14 tables" — already stale before this plan; per Task 1's instruction to reflect the new count it was updated to "16 tables" with a DEATH/DEATH_CAUSE line added. Cosmetic, not a behavioral change.)

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

**HiPerGator runtime gate (USER ACTION):** These three edits are structurally verified locally but the actual DEATH_CAUSE load is HiPerGator-only. After this plan lands, on HiPerGator the user must rebuild the DuckDB:
```
# in R, with force_reload to regenerate DEATH_CAUSE.rds, then rebuild DuckDB
source("R/01_load_pcornet.R")   # force_reload=TRUE
source("R/03_duckdb_ingest.R")
```
Then confirm the table loaded:
```
get_pcornet_table("DEATH_CAUSE") %>% collect() %>% nrow()   # expect > 0
```

## Next Phase Readiness
- Plan 03 (R/102 rewrite to read cause codes from DEATH_CAUSE) is unblocked structurally: the table is now wired. Plan 03's source selection remains GATED on the user running R/103 on HiPerGator and reporting DEATH_CAUSE population (per Plan 01).
- Plan 04 (smoke-test Section 15p) can reference the now-present DEATH_CAUSE in PCORNET_TABLES.
- No blockers.

## Self-Check: PASSED
- FOUND: R/00_config.R "DEATH_CAUSE" in PCORNET_TABLES (line 242) + DEATH_CAUSE_Mailhot_V1.csv comment (line 256)
- FOUND: R/01_load_pcornet.R DEATH_CAUSE_SPEC (line 231, 7 cols) + DEATH_CAUSE = DEATH_CAUSE_SPEC in TABLE_SPECS (line 418)
- FOUND: R/88 length(tables_found) == 16 (line 3472); production >= 13 unchanged (line 3513)
- FOUND: commit 9ea8031
- FOUND: commit 9cea83c
- FOUND: commit 0f88191

---
*Phase: 119-fix-death-cause-nhl-flag*
*Completed: 2026-07-10*
