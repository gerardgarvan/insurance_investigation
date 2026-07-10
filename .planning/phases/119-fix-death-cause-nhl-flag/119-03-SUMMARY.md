---
phase: 119-fix-death-cause-nhl-flag
plan: 03
subsystem: death-cause-nhl-flag
tags: [pcornet, death_cause, classify_codes, nhl, three-state, proxy-backstop, duckdb]

# Dependency graph
requires:
  - phase: 119-fix-death-cause-nhl-flag
    plan: 01
    provides: R/103 diagnostic (Wave-0 gate) confirming DEATH_CAUSE is the populated cause-of-death source
  - phase: 119-fix-death-cause-nhl-flag
    plan: 02
    provides: DEATH_CAUSE table wired into PCORNET_TABLES / R/01 spec / DuckDB ingest so get_pcornet_table("DEATH_CAUSE") is queryable
provides:
  - R/102 sources cause of death from the DEATH_CAUSE table (underlying-cause preferred) instead of the empty DEATH.DEATH_CAUSE column
  - R/102 documented off-by-default PROXY BACKSTOP (D-05) for the zero-coded-cause case
  - R/35 corrected to read cause codes from the DEATH_CAUSE table (no longer implies DEATH.DEATH_CAUSE)
affects: [119-04-smoke-test]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Deceased-set (DEATH) + cause-codes (DEATH_CAUSE) split: DEATH derives the deceased set, DEATH_CAUSE supplies ICD cause codes joined by ID"
    - "Underlying-cause-preferred one-per-ID selection (type_rank via case_when U/C/other, then first()) shared by R/102 and R/35"
    - "Off-by-default labeled PROXY BACKSTOP gated on n_coded == 0 with a USED_PROXY_BACKSTOP flag"

key-files:
  created: []
  modified:
    - R/102_death_cause_nhl_flag.R
    - R/35_death_cause_quality.R

key-decisions:
  - "Implemented RESEARCH Case A (DEATH_CAUSE table) as the primary path -- RESEARCH + CONTEXT confirmed DEATH_CAUSE exists; Case B (TUMOR_REGISTRY) not needed"
  - "DEATH table reduced to deceased-set derivation only (deceased_set: ID + DEATH_DATE); all cause reads removed from the DEATH frame"
  - "Underlying cause preferred via type_rank (U=1, C=2, other=3) + arrange + first() rather than a hard DEATH_CAUSE_TYPE == 'U' filter (RESEARCH Pitfall 2 -- avoids dropping all rows if provider populated only C/blank)"
  - "classify_codes() reads raw DEATH_CAUSE (the cause value field), not DEATH_CAUSE_CODE (coding-system indicator 09/10/OT/UN), per RESEARCH data model"
  - "R/35 uses Option A (full correction: read DEATH_CAUSE table + left_join) rather than Option B (comment-only) -- death_data keeps the same shape so the 5-sheet xlsx logic is untouched"
  - "Proxy backstop keys DIAGNOSIS on ID (not PATID), matching this extract's convention (RESEARCH Pitfall 4)"

requirements-completed: [NHLFIX-03, NHLFIX-04]

# Metrics
duration: 6min
completed: 2026-07-10
---

# Phase 119 Plan 03: Rewrite R/102 to Read Cause from DEATH_CAUSE Table Summary

**R/102 now sources `cause_of_death_is_nhl` from the newly-loaded DEATH_CAUSE table (underlying-cause preferred) joined onto the DEATH-derived deceased set, preserving the exact three-state PATID + flag output contract, with a labeled off-by-default DIAGNOSIS-history proxy backstop; R/35's identical stale DEATH.DEATH_CAUSE assumption is corrected the same way.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-07-10
- **Completed:** 2026-07-10
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Rewrote `R/102_death_cause_nhl_flag.R` to read cause codes from `get_pcornet_table("DEATH_CAUSE")` (new Section 4b) instead of the empty `DEATH.DEATH_CAUSE` column. The DEATH table is now used ONLY to derive the deceased set (`deceased_set`: ID + earliest valid DEATH_DATE, 1900 sentinel -> NA).
- Underlying cause preferred: `type_rank` (U=1, C=2, other=3) + `arrange(ID, type_rank)` + `first()` per patient, avoiding a hard `== "U"` filter that could drop all rows.
- Kept the three-state `case_when` (TRUE=NHL / FALSE=other coded / NA=uncoded) verbatim, now fed by the joined DEATH_CAUSE column, and preserved the exact output contract (`transmute(PATID, cause_of_death_is_nhl)` + `write.csv(row.names = FALSE, na = "")` to `death_cause_nhl_flag.csv`).
- Added a clearly-labeled PROXY BACKSTOP (Section 5b, CONTEXT D-05): a `USED_PROXY_BACKSTOP` flag + gate on `n_coded == 0` that only fires when the DEATH_CAUSE source yields zero coded causes for the whole deceased set, then flags NHL-in-DIAGNOSIS-history as an explicit proxy. OFF by default.
- Corrected `R/35_death_cause_quality.R` (Option A): reads cause codes from the DEATH_CAUSE table (underlying-cause preferred, mirroring R/102) and left-joins onto the DEATH-derived deceased set, so its completeness / payer / site profiling operates on real DEATH_CAUSE codes. The 5-sheet xlsx structure and `wb_save` target are unchanged.

## Task Commits

1. **Task 1: Rewrite R/102 to read cause from DEATH_CAUSE table (underlying-cause preferred) + proxy backstop** - `61a005e` (feat)
2. **Task 2: Correct R/35's stale DEATH.DEATH_CAUSE assumption** - `b444777` (fix)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP) committed separately.

## Files Created/Modified
- `R/102_death_cause_nhl_flag.R` - Cause of death read from DEATH_CAUSE table (Section 4b), DEATH used only for deceased-set derivation, three-state flag + exact output contract kept, labeled off-by-default proxy backstop (Section 5b), Phase 119 header/summary references.
- `R/35_death_cause_quality.R` - Section 2 corrected to read cause codes from the DEATH_CAUSE table (underlying-cause preferred) joined onto the deceased set; Phase 119 correction comment block; 5-sheet xlsx output unchanged.

## Decisions Made
- Implemented RESEARCH **Case A** (DEATH_CAUSE table) as the primary path -- RESEARCH and CONTEXT confirmed the DEATH_CAUSE table exists, so the TUMOR_REGISTRY fallback (Case B) was not needed.
- `classify_codes()` reads the raw `DEATH_CAUSE` value field (not `DEATH_CAUSE_CODE`, which is the coding-system indicator), per the RESEARCH data model. `classify_codes()` normalizes internally, so no pre-processing.
- R/35 used **Option A** (full correction with join) rather than Option B (comment-only): `death_data` keeps its `(ID, DEATH_DATE, DEATH_SOURCE, DEATH_CAUSE)` shape, so downstream Sections 3-8 (completeness, payer, site, xlsx) are untouched.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected proxy-backstop DIAGNOSIS join key**
- **Found during:** Task 1
- **Issue:** The proxy backstop initially selected `ID = PATID` from the DIAGNOSIS table, but this extract keys DIAGNOSIS on `ID` (not `PATID`) -- confirmed against R/14, R/25, R/26, R/28, R/32-R/45 which all `select(ID, ...)` from DIAGNOSIS. `PATID` does not exist as a column, so the proxy branch would have errored at runtime on HiPerGator if it ever fired.
- **Fix:** Changed the proxy select to `select(ID, DX)` with a clarifying comment.
- **Files modified:** R/102_death_cause_nhl_flag.R
- **Commit:** `61a005e`

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

**HiPerGator runtime gate (USER ACTION):** R/102 is structurally verified locally (grep) but the actual TRUE/FALSE tallies are HiPerGator-only. After Plan 02's DuckDB rebuild (`source("R/01_load_pcornet.R")` with force_reload, then `source("R/03_duckdb_ingest.R")`), on HiPerGator the user runs:
```
Rscript R/102_death_cause_nhl_flag.R
```
and confirms `output/death_cause_nhl_flag.csv` now has non-zero TRUE and/or FALSE counts (not 100% blank). The console line "Cause source: DEATH_CAUSE table (underlying-cause preferred)" confirms the primary path fired (not the proxy).

## Next Phase Readiness
- Plan 04 (R/88 smoke-test Section 15p) can now assert R/102 reads DEATH_CAUSE (positive) and no longer reads cause from DEATH (negative), and reference the DEATH_CAUSE table in PCORNET_TABLES.
- No blockers.

## Self-Check: PASSED
- FOUND: R/102_death_cause_nhl_flag.R (get_pcornet_table("DEATH_CAUSE") line 144, left_join line 168, USED_PROXY_BACKSTOP line 229, transmute PATID line 277, write.csv line 283)
- FOUND: R/35_death_cause_quality.R (Phase 119 correction line 64, get_pcornet_table("DEATH_CAUSE") line 98, 5 add_worksheet + wb_save intact)
- FOUND: commit 61a005e
- FOUND: commit b444777

---
*Phase: 119-fix-death-cause-nhl-flag*
*Completed: 2026-07-10*
