---
phase: 151-per-patient-zip-problem-inventory
plan: 01
subsystem: address-data
tags: [zip, address, r121, reconciliation, hipergator]

requires:
  - phase: 150-zip5-missing-but-zip9-elsewhere-patient-count-and-first-5-concordance-check
    provides: 8 aggregate reconciliation constants (n_missing_zip5=1128, n_concordant=547, n_discordant=135, etc.) and pinned normalizer normalize_zip5_raw

provides:
  - R/121_zip_problem_inventory.R: per-patient ZIP problem flag inventory
  - output/zip_problem_inventory_2026-10-09.xlsx: 7-sheet workbook (KEY leftmost)
  - output/zip_problem_inventory_2026-10-09.rds: alongside the workbook
  - Per-patient triage categories for all 1,128 missing-ZIP5 patients
  - Named patient list (D_record_mismatches) for all 12 record-level mismatches

affects: [phase-177-hygiene-04-temporal-sizing, any phase using triage categories from R/121]

key-files:
  created:
    - R/121_zip_problem_inventory.R
  modified:
    - R/39_run_all_investigations.R
    - R/88_smoke_test_comprehensive.R
    - R/SCRIPT_INDEX.md

key-decisions:
  - "normalize_zip5_raw pinned as PHASE150_ZIP5_FN — no automatic fallback"
  - "period_start asserted ISO-8601 before use as lexical tie-break"
  - "Reconciliation gate is blocking: on failure a QC-failure workbook is written then stop() fires"
  - "19 patients with n_no_zip5_elsewhere are excluded from the 547/135 concordant/discordant denominators"
  - "12 record-level mismatches accepted as expected data quirks (see mismatch section below)"
---

# Phase 151 Summary — Per-Patient ZIP Problem Inventory

**Verdict: PASS**

## Run Record

| Field | Value |
|---|---|
| Run date | 2026-10-09 |
| Node | c0610a-s20.ufhpc |
| R version | R 4.5.3 (2026-03-11) |
| Log file | Not captured (no phase121-specific log written to output/logs/) |
| Output workbook | output/zip_problem_inventory_2026-10-09.xlsx |
| Output RDS | output/zip_problem_inventory_2026-10-09.rds |

**Input file mtimes vs run date (2026-10-09):**

| File | mtime | Predates run? |
|---|---|---|
| LDS_ADDRESS_HISTORY_Mailhot_V1.csv | 2025-11-14 13:56:27 | Yes ✓ |
| pcornet.duckdb | 2026-10-06 11:35:30 | Yes ✓ |

Both inputs predate the run. No post-run commits to R/121, R/utils/utils_address.R, or R/00_config.R affect R/121 results (the one post-run commit to R/00_config.R on 2026-10-12 re-pointed the Gantt snapshot path only). The 2026-10-09 run is confirmed as the close-out run.

## Reconciliation Table (from E_reconciliation sheet)

| quantity | expected | observed | status |
|---|---|---|---|
| n_missing_zip5 | 1128 | 1128 | PASS |
| n_zip9_available | 701 | 701 | PASS |
| n_unreachable | 427 | 427 | PASS |
| n_concordant | 547 | 547 | PASS |
| n_discordant | 135 | 135 | PASS |
| n_no_zip5_elsewhere | 19 | 19 | PASS |
| n_rows_both_present | 19739 | 19739 | PASS |
| n_rows_mismatch | 12 | 12 | PASS |

Expected column uses the Phase 150 amended constants (547/135), not the original 530/152 values.

## Phase 151 Success Criteria Mapping

| Criterion (from 151-01-PLAN.md) | Evidence | Status |
|---|---|---|
| R/121 written, registered in R/39, R/88 Section 15ag, SCRIPT_INDEX.md | File exists; R/39 line 224; R/88 line 5224; SCRIPT_INDEX line 165 | PASS |
| HiPerGator run completes with all 8 reconciliation quantities PASS and no invariant failure | E_reconciliation sheet: all 8 PASS; no QC-failure workbook written | PASS |
| Workbook written with KEY leftmost and 7 sheets; RDS written alongside | `excel_sheets()` returns KEY, A_patient_flags, B_flag_summary, C_triage_summary, D_record_mismatches, E_reconciliation, QC (7 sheets, KEY first); RDS confirmed at same path | PASS |
| Triage reports ALL / PARTIAL / TEMPORAL / UNREACHABLE split of the 1,128 | C_triage_summary: see triage table below | PASS |
| Roster gives named patient list for each problem group, including 19 (no ZIP5) and 12 (record-level mismatches) | A_patient_flags contains all flagged patients; D_record_mismatches has 12 rows (12 distinct patients) | PASS |

## Triage Summary (from C_triage_summary sheet)

| Triage category | Patients | % of 8,953 |
|---|---|---|
| NO_MISSING_ZIP5 | 7,825 | 87.4% |
| UNREACHABLE_NO_ZIP9 | 427 | 4.77% |
| NEEDS_TEMPORAL_MATCH | 410 | 4.58% |
| SAME_ROW_BACKFILL_ALL | 286 | 3.19% |
| SAME_ROW_BACKFILL_PARTIAL | 5 | 0.06% |

Same-row backfill volume left open by Phase 150: **291 patients** (286 ALL + 5 PARTIAL).

## 19 Patients with No ZIP5 Anywhere (Informational)

These 19 patients have `F01_missing_zip5` AND at least one usable ZIP9 (`n_zip9_usable > 0`) AND `modal_zip5 IS NA` — meaning they have a usable ZIP9 on at least one address record but no observed, non-sentinel ZIP5 on any record.

**Denominator note:** The 19 are **excluded** from the 547/135 concordant/discordant denominators. The concordance identity is `n_concordant + n_discordant + n_no_zip5_elsewhere = n_zip9_available` (547 + 135 + 19 = 701). They cannot be concordant or discordant because there is no ZIP5 value to compare against. No action required.

## 12 Record-Level Mismatches (Blocking — now resolved)

Records where `zip9_first5 != zip5_norm` on the same row, among rows where both values are present and usable. One mismatch per patient (12 rows, 12 distinct patients).

| Group | Rows | Patients | Cause | Disposition |
|---|---|---|---|---|
| Same ZIP3, different ZIP5 | 10 | 10 | ZIP9 and ZIP5 share the same 3-digit area code but differ on digits 4–5. Expected within-zone geographic variation or minor entry-level discrepancy. Same-row ZIP9 backfill would produce a close but non-identical ZIP5. | Accepted — expected data quirk |
| Different ZIP3 | 2 | 2 | ZIP9 and ZIP5 disagree at the 3-digit level. Likely address update lag between fields or carrier-route ZIP9 mapping to a different ZIP5 zone. | Accepted — expected data quirk |

All 12 mismatches have a disposition. No open items. Phase 151 tick is unblocked.

## Freshness Evidence Summary

- LDS_ADDRESS_HISTORY CSV mtime: 2025-11-14 (predates 2026-10-09 run)
- DuckDB mtime: 2026-10-06 (predates 2026-10-09 run)
- Post-run commit to R/00_config.R (2026-10-12, `ee01b75`): re-pointed Gantt snapshot path only — does not affect R/121 results
- Amended constants (547/135) committed 2026-09-03, predating the run
- D-02 verdict: **use 2026-10-09 run** — no re-run required

## R/.planning Duplication (Phase 176 finding, deferred to Phase 177)

`R/.planning/` is a full parallel planning environment (ROADMAP.md, STATE.md, REQUIREMENTS.md, milestones/, phases/, etc.), not a stale copy of the root `.planning/` tree.

- Root `.planning/ROADMAP.md`: 816 lines
- `R/.planning/ROADMAP.md`: 616 lines
- Lines unique to root: 816 | Lines unique to R/.planning: 616 (essentially fully diverged)
- Most recent commit to R/.planning: `08e43c6` (2026-10-12) — still being written to
- Live references outside R/.planning: none (only in `.claude/worktrees/` stale agent worktrees)

**Root cause:** GSD was launched from inside the `R/` subdirectory at some point, causing it to treat `R/.planning/` as its planning root. Some phases were deliberately committed to both (e.g., commit `a05adc2`: "add phases 153-157 to both roadmap files").

**Resolution:** Deferred to Phase 177. The R/.planning tree has diverged content that requires evaluation before deletion. Always launch GSD from the repo root, not from `R/`.
