---
phase: 119-fix-death-cause-nhl-flag
plan: 04
subsystem: pipeline-registration
tags: [pcornet, death_cause, smoke-test, r39, script-index, registration, phase-119]

# Dependency graph
requires:
  - phase: 119-fix-death-cause-nhl-flag
    plan: 01
    provides: R/103_death_cause_diagnostic.R (the read-only diagnostic being registered)
  - phase: 119-fix-death-cause-nhl-flag
    plan: 02
    provides: DEATH_CAUSE wired into PCORNET_TABLES / R/01 spec / R/88 table-count 16 (asserted structurally by Section 15p)
  - phase: 119-fix-death-cause-nhl-flag
    plan: 03
    provides: R/102 reading DEATH_CAUSE table + D-05 proxy backstop (the fix Section 15p validates)
provides:
  - R/103 registered in R/39 investigation_scripts (before R/102, diagnostic-before-fix), R/102 retained
  - R/88 Section 15p (14 structural checks + gated HiPerGator runtime check) guarding the Phase 119 fix against regression
  - R/SCRIPT_INDEX.md documenting R/103 + the R/102 Phase 119 source change; post-renumber (100+) count 3 -> 4
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Phase-registration triad (R/39 runner + R/88 smoke-test section + SCRIPT_INDEX row) mirroring the 116/117/118 precedent"
    - "Section 15p mirrors 15o: file.exists guard + else-branch registering SKIPPED dependent checks 2:14 for an honest total"
    - "Negative structural assertion (!grepl old DEATH-column pattern) pairs with positive (DEATH_CAUSE table) to prove a source switch"
    - "Self-read of R/88 to assert its own table-count constant (length(tables_found) == 16) without re-hardcoding it"
    - "IS_LOCAL-gated runtime check (non-zero TRUE/FALSE in output CSV) stays green on Windows, only fires on HiPerGator"

key-files:
  created: []
  modified:
    - R/39_run_all_investigations.R
    - R/88_smoke_test_comprehensive.R
    - R/SCRIPT_INDEX.md

key-decisions:
  - "R/103 placed BEFORE R/102 in investigation_scripts (diagnostic before the fix it informs); R/102 kept as the final comma-less vector entry so the vector still parses"
  - "Section suffix 15p continues the 15m (116) -> 15n (117) -> 15o (118) -> 15p (119) sequence"
  - "Section 15p guard requires BOTH R/102 AND R/103 to exist before running checks 2:14 (both are Phase 119 artifacts); else-branch registers SKIPPED FALSE for an honest total, mirroring 15o"
  - "Check 5 negative assertion targets the exact old pattern 'DEATH_CAUSE = all_of(death_cause_col)' (the Phase 118 DEATH-column read) so a regression to the empty column would flip it FALSE"
  - "Check 13 self-reads R/88 rather than duplicating the table-count literal, so the count-16 assertion has a single source of truth (the IS_LOCAL DuckDB section from Plan 02)"
  - "R/102 phase column in SCRIPT_INDEX updated to '118, 119' (per plan option) for provenance clarity; R/103 row added as phase 119"

requirements-completed: [NHLFIX-05, SMOKE-119-01]

# Metrics
duration: 2min
completed: 2026-07-10
---

# Phase 119 Plan 04: Register the Death-Cause Fix (R/39 + R/88 + SCRIPT_INDEX) Summary

**Made the Phase 119 fix discoverable, runnable via the pipeline runner, and regression-guarded: R/103 registered in R/39 (before R/102, which is retained), a new R/88 Section 15p (14 structural checks + one gated HiPerGator runtime check) validating the DEATH_CAUSE-table source switch / three-state preservation / table loading / count 16 / R/103 existence, and R/SCRIPT_INDEX.md documenting R/103 and the R/102 source change with the post-renumber count bumped 3 -> 4.**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-07-10
- **Completed:** 2026-07-10
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- Registered `R/103_death_cause_diagnostic.R` in R/39's `investigation_scripts` vector, placed immediately before `R/102_death_cause_nhl_flag.R` (diagnostic-before-fix ordering); R/102 retained as the final comma-less entry and annotated with the Phase 119 DEATH_CAUSE-table fix note.
- Added R/88 **Section 15p** (mirroring Section 15o): a `[Phase 119]` banner, a top-level `file.exists("R/103...")` check plus a combined `R/102 && R/103` guard, 13 further structural `check()` calls, and an else-branch registering checks 2:14 as SKIPPED FALSE for an honest total.
- Section 15p asserts the source switch both ways — positive `get_pcornet_table("DEATH_CAUSE")` in R/102, negative `!grepl('DEATH_CAUSE = all_of(death_cause_col)')` — plus underlying-cause preference (`DEATH_CAUSE_TYPE`/`"U"`), `left_join`, three-state classify (`classify_codes` + `Non-Hodgkin Lymphoma` + `cause_of_death_is_nhl` + `case_when`), the unchanged output contract (`death_cause_nhl_flag.csv` + `row.names = FALSE` + `na = ""` + `PATID`), the labeled `USED_PROXY_BACKSTOP` / `D-05`, `DEATH_CAUSE` in PCORNET_TABLES (reads R/00_config), `DEATH_CAUSE_SPEC` in TABLE_SPECS (reads R/01), the self-read `length(tables_found) == 16`, and R/103 existence.
- Added a gated, HiPerGator-only runtime check (Check 14): if `!IS_LOCAL` and the output CSV exists, assert non-zero TRUE/FALSE counts; otherwise register a SKIPPED-TRUE so local Windows runs stay green.
- Added Phase 119 summary lines (`NHLFIX-03`, `NHLFIX-04`, `SMOKE-119-01`) directly after the Phase 118 block.
- Updated R/SCRIPT_INDEX.md: new R/103 row (phase 119, read-only inventory), R/102 row annotated with the Phase 119 source correction and phase column `118, 119`, and the post-renumber investigations (100+) summary bumped `3 -> 4`.

## Task Commits

1. **Task 1: Register R/103 in R/39 investigation_scripts** - `d72a151` (chore)
2. **Task 2: Add R/88 Section 15p Phase 119 structural validation** - `b1d7025` (test)
3. **Task 3: Update R/SCRIPT_INDEX.md (R/103 row, R/102 note, count 3 -> 4)** - `db817e8` (docs)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP) committed separately.

## Files Created/Modified
- `R/39_run_all_investigations.R` - R/103 added to investigation_scripts before R/102 (diagnostic-before-fix); R/102 retained + Phase 119 annotation.
- `R/88_smoke_test_comprehensive.R` - Section 15p added (14 Phase 119 checks: 1 top-level R/103-exists + 13 guarded, with an else-branch SKIPPED loop); 3 Phase 119 summary lines (NHLFIX-03/04, SMOKE-119-01).
- `R/SCRIPT_INDEX.md` - R/103 row added; R/102 row annotated with Phase 119 fix + phase `118, 119`; post-renumber (100+) count `3 -> 4`.

## Decisions Made
- R/103 placed before R/102 in the runner (diagnostic before the fix it informs); R/102 kept as the terminal comma-less vector entry so the vector parses.
- Section suffix 15p continues the 15m/15n/15o sequence for phases 116/117/118.
- Section 15p guard requires both R/102 and R/103 to exist (both Phase 119 artifacts) before running dependent checks; else-branch registers SKIPPED FALSE for an honest total.
- Check 13 self-reads R/88 for `length(tables_found) == 16` rather than duplicating the literal — single source of truth is the IS_LOCAL DuckDB section wired in Plan 02.
- R/102 SCRIPT_INDEX phase column set to `118, 119` (plan-provided option) for provenance clarity.

## Deviations from Plan
None - plan executed exactly as written. (Check-14 runtime comparison written as `== "TRUE" | == TRUE` to be robust to whether `read.csv` parses the flag column as character or logical — a defensive detail within the plan's intent, not a behavioral deviation.)

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

**HiPerGator runtime gate (USER ACTION):** These three edits are structurally verified locally (grep) but the full pipeline run is HiPerGator-only. After Plan 02's DuckDB rebuild (`source("R/01_load_pcornet.R")` with force_reload, then `source("R/03_duckdb_ingest.R")`), on HiPerGator the user runs the investigation pipeline (or R/103 + R/102 directly):
```
Rscript R/39_run_all_investigations.R
Rscript R/88_smoke_test_comprehensive.R
```
Section 15p's gated Check 14 then confirms `output/death_cause_nhl_flag.csv` has non-zero TRUE/FALSE (no longer 100% blank). Locally that check is SKIPPED-green.

## Next Phase Readiness
- Phase 119 is now fully registered: R/103 in the runner, the fix guarded by R/88 Section 15p, and both documented in SCRIPT_INDEX. This is the final plan (4 of 4) of Phase 119.
- No blockers.

## Self-Check: PASSED
- FOUND: R/39_run_all_investigations.R "R/103_death_cause_diagnostic.R" (registered before R/102, which is retained)
- FOUND: R/88_smoke_test_comprehensive.R "SECTION 15p" (line 2206), "[Phase 119]" (line 2216), negative check `!grepl('DEATH_CAUSE = all_of` (line 2248)
- FOUND: R/88 summary lines NHLFIX-03 (line 3895), SMOKE-119-01 (line 3897)
- FOUND: R/SCRIPT_INDEX.md "R/103_death_cause_diagnostic.R" row + post-renumber count "4 ("
- FOUND: commit d72a151
- FOUND: commit b1d7025
- FOUND: commit db817e8

---
*Phase: 119-fix-death-cause-nhl-flag*
*Completed: 2026-07-10*
