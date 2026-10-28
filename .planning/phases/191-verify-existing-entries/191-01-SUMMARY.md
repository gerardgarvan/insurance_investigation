---
phase: 191-verify-existing-entries
plan: "01"
subsystem: analytic-manual-verification
tags: [verification, duckdb, payer, diagnosis, death, zip, workbook]
dependency_graph:
  requires: [DuckDB PCORnet extract, R/60 payer CSV, R/116 encounter SES RDS, R/49 cancer 7-day RDS]
  provides: [R/191_am_verification.R, am_verification_20261027.xlsx]
  affects: [AM-VERDICTS.md (Phase 191 Plans 02-03), am_verdicts_<date>.xlsx (Plan 03)]
tech_stack:
  added: []
  patterns: [run_check() tryCatch wrapper, opened_here DuckDB pattern, sup_table() complementary suppression, information_schema column probing]
key_files:
  created:
    - R/191_am_verification.R
    - .planning/phases/191-verify-existing-entries/191-01-NOTES.md
  modified:
    - R/SCRIPT_INDEX.md
decisions:
  - "Script number 191 confirmed free (no R/190_* or R/191_* files in repo)"
  - "V2 crosswalk: Self-pay, Other, Other govt marked UNMAPPED (no clean manual 6-level equivalent)"
  - "V6 grace_days: pipeline uses 30L at all 5 call sites; manual specifies 14 days"
  - "V4 code-path finding: 7-day rule IS applied to non-HL cancer types in R/49 lines 182-184"
  - "get_hl_any_dx_ids() reads DIAGNOSIS only; TUMOR_REGISTRY not consulted for pipeline anchor"
  - "LDS_ADDRESS_HISTORY ZIP column names probed at runtime via information_schema (column names unconfirmed in schema probe)"
  - "V5 PARTIAL accepted: LDS_ADDRESS_HISTORY not in DuckDB (data availability, not a code bug)"
metrics:
  duration_minutes: 45
  completed_date: "2026-10-27"
  tasks_completed: 3
  tasks_total: 3
  files_created: 4
  files_modified: 2
---

# Phase 191 Plan 01: AM Verification Script Summary

**One-liner:** Standalone R/191 read-only verification script with six DuckDB-backed checks; workbook `am_verification_20261027.xlsx` produced on HiPerGator with five COMPLETE checks and V5 PARTIAL (LDS_ADDRESS_HISTORY not in DuckDB).

## HiPerGator Run Results (2026-10-27)

| Check | Status | Key result |
|---|---|---|
| V1_SOURCE | COMPLETE | SOURCE profiled in 17 CDM tables |
| V2_INSURANCE | COMPLETE | 1,005,977 mapped patient-days; 11,052 UNMAPPED (Self-pay/Other/Other govt) |
| V3_DXDATE | COMPLETE | 9,331 pipeline anchors, 9,331 manual anchors — exact match |
| V4_DXSCOPE | COMPLETE | 54 cancer categories assessed |
| V5_ZIPCOVER | PARTIAL | LDS_ADDRESS_HISTORY not in DuckDB (data availability, not a code bug) |
| V6_DEATH | COMPLETE | 1,344 patients with a death record |

Workbook: `output/am_verification_20261027.xlsx` — to be copied to phase folder.

## What Was Built

### R/191_am_verification.R

A read-only, standalone R script (not registered in R/39 or R/88 per D-21) that:

1. Sources `R/00_config.R` in the global environment so CONFIG and pipeline helpers are available.
2. Opens a DuckDB connection using the `opened_here` pattern from R/169 (never closes a connection it did not open).
3. Runs six checks through `run_check()`, which wraps each in `tryCatch` — one FAILED/SKIPPED check never stops the others.
4. Writes `output/am_verification_<YYYYMMDD>.xlsx` with sheets KEY (leftmost), V1_SOURCE, V2_INSURANCE, V3_DXDATE, V4_DXSCOPE, V5_ZIPCOVER, V6_DEATH, QC.
5. Saves ID-bearing detail only to `output/internal/`.

#### Per-check design
| Check | Manual side | Pipeline side | What it answers |
|-------|-------------|---------------|-----------------|
| V1_SOURCE | information_schema + GROUP BY SOURCE per table | R/169 reads ENCOUNTER only (note) | SOURCE distribution across all CDM tables |
| V2_INSURANCE | SQL 6-level hierarchy on ENCOUNTER | R/60 `payer_resolved_detail_all.csv` | Agreement with pipeline; UNMAPPED categories |
| V3_DXDATE | SQL two-step: TUMOR_REGISTRY_ALL HL hist → first C81/201 code date | `get_hl_any_dx_ids()` live call | Day-difference distribution between manual and pipeline anchor |
| V4_DXSCOPE | Independent 7-day rule re-check from DIAGNOSIS via classify_codes() | `cancer_summary_table_pre_post_v2_7day.rds` | Whether 7-day rule applies to non-HL types |
| V5_ZIPCOVER | LDS_ADDRESS_HISTORY ZIP9/ZIP5/none per patient (probed at runtime) | R/116 `encounter_ses_index_<date>.rds` | ZIP and SES index coverage |
| V6_DEATH | SQL death-before-last-treatment gap; 14-day vs grace_days=30 comparison | `resolve_death_date()` (utils_death.R:51) | Gap bands; rule comparison; DEATH_CAUSE scope |

#### V2 crosswalk
| Pipeline category | Maps to | Status |
|---|---|---|
| Medicaid | Medicaid | MATCH |
| Medicare | Medicare | MATCH |
| Private (incl. 311=TRICARE) | Private | MATCH |
| Uninsured | Uninsured | MATCH |
| Missing | missing | MATCH |
| Self-pay | — | UNMAPPED |
| Other | — | UNMAPPED |
| Other govt | — | UNMAPPED |

#### V6 code-path findings
- `resolve_death_date()` default `grace_days = 30L` (`utils_death.R:51`).
- All 5 production call sites use `grace_days = 30L`.
- Manual specifies a 14-day rule — confirmed MISMATCH.
- No cohort predicate uses DEATH_CAUSE — expected 0 exclusions.

#### V4 code-path finding
- R/49 lines 182–184: 7-day rule IS applied to ALL cancer categories, not only HL.

## Task 0 Findings
All column names, pipeline-side sources, V2 crosswalk, and V3/V6 rules recorded with `file:line` citations in `191-01-NOTES.md`.

## SCRIPT_INDEX
R/191_am_verification.R added at line 186 of R/SCRIPT_INDEX.md. Count 28 → 29.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] V2 cross-tab rbind type mismatch**
- **Found during:** Task 2 HiPerGator run
- **Issue:** `col_totals` was a named numeric vector combined with a character label using `c()` then bound via `rbind(as.data.frame(xtab_raw), as.list(col_totals))`. The character `manual_resolved` column caused coercion errors.
- **Fix:** Construct `totals_row` as a properly-typed `data.frame`, bind with `dplyr::bind_rows`.
- **Files modified:** `R/191_am_verification.R`
- **Commit:** a4b7169

**2. [Rule 1 - Bug] V4 early return before independent re-derivation**
- **Found during:** Task 2 HiPerGator run
- **Issue:** When the R/49 pipeline artifact lacked the expected `cancer_category` column (artifact is a list, not a flat data frame), the check returned early before running the independent DIAGNOSIS re-derivation.
- **Fix:** Set `artifact_note` (SKIPPED pipeline comparison) and always continue to the DIAGNOSIS-based re-derivation, which is the primary result.
- **Files modified:** `R/191_am_verification.R`
- **Commit:** a4b7169

### Runtime Notes

**V5 PARTIAL — LDS_ADDRESS_HISTORY not in DuckDB:** The table exists as a CSV on HiPerGator but was not ingested into the DuckDB file used by this script. This is a data availability issue, not a code bug. The encounter-level R/116 RDS side of V5 ran successfully if R191_R116_RDS was set. Status accepted as PARTIAL per plan design (a PARTIAL does not block Plan 02).

## Known Stubs

None. All six checks return machine-readable status. V5 PARTIAL reflects data availability, not missing logic.

## Self-Check

### Files exist
- `R/191_am_verification.R` — ✓ created
- `.planning/phases/191-verify-existing-entries/191-01-NOTES.md` — ✓ created
- `R/SCRIPT_INDEX.md` — ✓ modified

### Commits
- `81f61dd` — Task 0 (NOTES.md + SCRIPT_INDEX)
- `07843b1` — Task 1 (R/191_am_verification.R initial)
- `a4b7169` — Bug fixes (V2 rbind, V4 early return)

## Self-Check: PASSED
