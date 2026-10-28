---
phase: 191-verify-existing-entries
plan: "01"
subsystem: analytic-manual-verification
tags: [verification, duckdb, payer, diagnosis, death, zip, workbook]
dependency_graph:
  requires: [DuckDB PCORnet extract, R/60 payer CSV, R/116 encounter SES RDS, R/49 cancer 7-day RDS]
  provides: [R/191_am_verification.R, am_verification_<YYYYMMDD>.xlsx]
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
metrics:
  duration_estimate: "< 30 min (Tasks 0-1 local; Task 2 HiPerGator)"
  completed_date: "2026-10-27"
  tasks_completed: 2
  tasks_total: 3
  files_created: 3
  files_modified: 1
---

# Phase 191 Plan 01: AM Verification Script Summary

**One-liner:** Standalone R/191 verification script with six DuckDB-backed checks (V1–V6) and complementary-suppression workbook; stopped at HiPerGator checkpoint.

## Status

Tasks 0 and 1 complete (local). Task 2 (HiPerGator run) is a blocking human-verify checkpoint — see Checkpoint section below.

## What Was Built

### R/191_am_verification.R

A read-only, standalone R script (not registered in R/39 or R/88 per D-21) that:

1. Sources `R/00_config.R` in the global environment so CONFIG and pipeline helpers are available.
2. Opens a DuckDB connection using the `opened_here` pattern from R/169 (never closes a connection it did not open).
3. Runs six checks through `run_check()`, which wraps each in `tryCatch` — one FAILED/SKIPPED check never stops the others.
4. Writes `output/am_verification_<YYYYMMDD>.xlsx` with sheets KEY (leftmost), V1_SOURCE, V2_INSURANCE, V3_DXDATE, V4_DXSCOPE, V5_ZIPCOVER, V6_DEATH, QC.
5. Saves ID-bearing detail only to `output/internal/`.

#### Column constants
All CDM column names are held as named constants (`COL_*`) with `file:line` comments from existing pipeline code. No column name is guessed.

#### Per-check design
| Check | Manual side | Pipeline side | What it answers |
|-------|-------------|---------------|-----------------|
| V1_SOURCE | information_schema + GROUP BY SOURCE per table | R/169 reads ENCOUNTER only (note) | SOURCE distribution across all CDM tables |
| V2_INSURANCE | SQL 6-level hierarchy on ENCOUNTER (Medicaid→Medicare→Private→Uninsured→Self-pay→missing) | R/60 `payer_resolved_detail_all.csv` | Agreement with pipeline; UNMAPPED categories |
| V3_DXDATE | SQL two-step: TUMOR_REGISTRY_ALL HL hist → first C81/201 code date | `get_hl_any_dx_ids()` live call | Day-difference distribution between manual and pipeline anchor |
| V4_DXSCOPE | Independent 7-day rule re-check from DIAGNOSIS via classify_codes() | `cancer_summary_table_pre_post_v2_7day.rds` from R/49 | Whether 7-day rule applies to non-HL types |
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
| Self-pay | — | UNMAPPED (pipeline separates; manual merges with Uninsured) |
| Other | — | UNMAPPED (no equivalent in manual 6-level) |
| Other govt | — | UNMAPPED (no equivalent in manual 6-level) |

#### V6 code-path findings
- `resolve_death_date()` default `grace_days = 30L` (`utils_death.R:51`).
- All 5 production call sites use `grace_days = 30L`: R/142:340, R/147:263, R/52:514, R/161:90, R/166:172.
- Manual specifies a 14-day rule. This is a known discrepancy (L6 lead, likely MISMATCH verdict).
- No cohort inclusion/exclusion predicate in R/10_cohort_predicates.R uses DEATH_CAUSE. R/102 and R/103 are diagnostic-only. Expected DEATH_CAUSE exclusion count = 0.

#### V4 code-path finding
- `R/49_cancer_summary_pre_post.R` lines 182–184: `filter(two_or_more_unique_dates_gt_7 == 1)` is applied to ALL cancer categories, not only HL.
- This answers L4: the 7-day rule IS applied to non-HL types in the pipeline.

## Task 0 Findings (191-01-NOTES.md)
All column names, pipeline-side sources, V2 crosswalk, and V3/V6 rules are recorded with `file:line` citations in `.planning/phases/191-verify-existing-entries/191-01-NOTES.md`. Unconfirmed items: LDS_ADDRESS_HISTORY ZIP column names (probed at runtime) and DEATH_CAUSE cause-code column (probed via information_schema).

## SCRIPT_INDEX
R/191_am_verification.R added at line 186 of R/SCRIPT_INDEX.md. Count 28 → 29 post-renumber investigations.

## Deviations from Plan

None. Plan executed exactly as written for Tasks 0 and 1.

## Checkpoint (Task 2 — Blocking)

Task 2 is a `checkpoint:human-verify` requiring a HiPerGator run. See return message below.

## Self-Check

### Files exist
- `R/191_am_verification.R` — created in this plan
- `.planning/phases/191-verify-existing-entries/191-01-NOTES.md` — created in this plan
- `R/SCRIPT_INDEX.md` — modified in this plan

### Commits exist
- `81f61dd` — Task 0 (NOTES.md + SCRIPT_INDEX entry)
- `07843b1` — Task 1 (R/191_am_verification.R)

## Self-Check: PASSED
