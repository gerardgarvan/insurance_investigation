---
phase: 163
plan: "01"
subsystem: surveillance-modality-frequency
tags: [R/147, codeset, diagnosis-exclusion, codeset-summary, per-modality-blocks]
dependency-graph:
  requires: [R/147_surveillance_modality_frequency.R, R/utils/utils_surveillance.R]
  provides: [163-D-01-exclusion, 163-D-02-codeset-summary, 163-D-03-excluded-rows-removed]
  affects: [surveillance_modality_frequency_INTERNAL_*.xlsx, surveillance_modality_frequency_*.xlsx]
tech-stack:
  added: []
  patterns: [per-modality-stacked-blocks, cdm-table-exclusion-constant]
key-files:
  created: [R/147_verify_vs_1006.R]
  modified: [R/147_surveillance_modality_frequency.R, R/utils/utils_surveillance.R]
decisions:
  - D-01: EXCLUDED_CDM_TABLES constant; split codeset after load; remove DIAGNOSIS collector; stopifnot assertion before matching
  - D-02: Per-modality stacked blocks in Codeset_summary (14 blocks); analytes from each modality's own rule rows
  - D-03: Excluded rows removed from A_code_presence; listed by ID only in KEY and QC
metrics:
  duration: ~30min
  completed: "2026-10-06"
  tasks: 4
  files: 3
---

# Phase 163 Plan 01: R/147 changes — DIAGNOSIS exclusion and per-modality Codeset_summary

Drop 4 DIAGNOSIS-table sensitivity-tier Z-code rows from surveillance-event collection; rebuild Codeset_summary as per-modality stacked blocks.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| T1 | Exclude DIAGNOSIS surveillance rows (D-01) | 0a4f56e | R/147 |
| T2 | Downstream sheets zero-fill (no code change needed) | 0a4f56e | R/147 |
| T3 | Codeset_summary per-modality blocks (D-02) | 4f4c3b9 | R/utils/utils_surveillance.R |
| T4 | KEY/QC updates + verification script | 62fd52e | R/147, R/147_verify_vs_1006.R |

## What Changed

**R/147 (T1, T2, T4):**
- Added `EXCLUDED_CDM_TABLES <- c("DIAGNOSIS")` constant in the run-constants block.
- After `load_surveillance_codeset()`: split into `codeset_full`, `codeset_excluded`, `codeset`; log excluded row IDs to console.
- SECTION 5: removed the DIAGNOSIS surveillance collector (pull + tibble + message block) entirely; replaced with a comment explaining the exclusion.
- SECTION 7: added `stopifnot(!any(codeset$cdm_table %in% EXCLUDED_CDM_TABLES))` before `match_coded_events()`; removed `dx_events_in` from `bind_rows`.
- QC: replaced `"DIAGNOSIS rows collected"` row with `"Codeset rows excluded (DIAGNOSIS)"` = 4, note lists IDs.
- KEY: updated Codeset line to show loaded/excluded/used counts; updated Tiers line; added `"Diagnosis codes (163 D-01)"` line; replaced Codeset_summary Phase 160 line with D-02 per-modality description.
- Updated `codeset_summary` call (comment updated to 163 D-02).
- `write_workbook`: Codeset_summary is now a flat tibble (not a list); bold header rows applied via `hdr_mod` style; removed the old `by_analyte` second `writeData` block.

**R/utils/utils_surveillance.R (T3):**
- Rewrote `build_codeset_summary()` to return a single flat tibble with `row_type` column.
- Per-modality blocks: header row + codes table (tier/match/code_system/n_codes/n_codes_present/codes/threshold) + optional analyte table (for modalities with `SURV_ANALYTE_MATCHES` rule rows).
- Analytes per modality come from that modality's own rule rows via `surv_components()`, not the full Lab_Analytes list.
- `row_type` values: `"header"`, `"code"`, `"analyte_header"`, `"analyte"`, `"separator"`.

**R/147_verify_vs_1006.R (T4):**
- New comparison script: reads latest INTERNAL output + reference 1006 workbook, checks B/A/D/E sheets for identity, checks C primary_* columns, checks sensitivity/any for Echo/ECG/Mammogram/PFT, checks QC row replacement, checks KEY 163 D-01 note, checks Codeset_summary for 14 modality blocks and absence of Z-codes.

## Expected Behavior After Run

- B_modality_primary: unchanged
- C primary_* columns: unchanged for all modalities
- C sensitivity_*/any_* for Echo, ECG, Mammogram, PFT: sensitivity = 0 patients/0 dates; any = primary
- A_code_presence: 163 rows (4 excluded rows absent)
- QC "A_code_presence rows minus codeset rows": 0 (compared against 163-row kept codeset)
- Codeset_summary: 14 modality blocks, no Z-codes, analyte sub-tables under BMP/CMP/LIPID/LFT/KIDNEY
- Denominator N / confirmed-cohort N / person-years: 9,331 / 9,282 / 40,298.9 — unchanged

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — all data wiring is from the live run.

## Self-Check

Files exist:
- [x] `R/147_surveillance_modality_frequency.R` — modified
- [x] `R/utils/utils_surveillance.R` — modified
- [x] `R/147_verify_vs_1006.R` — created

Commits exist:
- [x] 0a4f56e — T1
- [x] 4f4c3b9 — T3
- [x] 62fd52e — T4

## Self-Check: PASSED
