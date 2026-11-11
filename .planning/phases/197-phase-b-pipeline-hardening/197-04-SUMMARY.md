---
phase: 197
plan: "04"
name: overwrite-protection-versioned-output
status: complete
completed: 2026-11-11
duration_min: 45
tasks_completed: 6
files_created: 0
files_modified: 18
commit: 5293a04
tags: [refactor, io, versioning, hardening, overwrite-protection]
key_decisions:
  - "D-197-04a: versioned_output_path() appends date as suffix (stem_YYYYMMDD.ext); R/188's original date-prefix convention (YYYYMMDD_188_...xlsx) changed to suffix for consistency"
  - "D-197-04b: RUN_DATE env-var override added to all scripts with format(Sys.Date()) at top-level; allows cross-script date coordination"
  - "D-197-04c: R/107, R/109, R/110, R/46, R/47, R/48 have fixed (undated) output filenames — versioned_output_path() not applicable; confirmed not at same-date overwrite risk"
  - "D-197-04d: overwrite=TRUE changed to overwrite=FALSE in all openxlsx::saveWorkbook calls that now use versioned paths — versioned_output_path() guarantees a new path on rerun"
  - "D-197-04e: Pre-existing paren-balance deltas in R/122 (p=-17), R/168 (p=3), R/179 (p=3), R/181 (p=7), R/184 (p=2) confirmed pre-existing via git stash baseline check"
---

# Phase 197 Plan 04: Overwrite Protection (versioned_output_path) — Summary

**One-liner:** `versioned_output_path()` helper auto-increments `_v2/_v3` on same-day rerun; applied to all dated output paths across 17 scripts, controlled by `VERSIONED_OUTPUT` env var.

## Objective

61 same-date overwrite sites identified in audit. This plan adds `versioned_output_path()` to `R/utils/utils_io.R` and applies it to all dated output paths.

## Tasks Completed

| Task | Description | Outcome |
|------|-------------|---------|
| 0 | Context probe: existing pattern in R/165, R/46-48 | Done — R/165 uses `RUN_DATE` glue; R/46-48 use `build_output_path()` with undated filenames |
| 1 | Add `versioned_output_path()` to `R/utils/utils_io.R` | Done — `VERSIONED_OUTPUT` env var; `_v2`/`_v3` on same-day rerun |
| 2 | Apply to delivered-output writers | Done — R/165, R/183; R/107/109/110/46/47/48 have undated paths (N/A) |
| 3 | Apply to remaining audit-listed scripts | Done — R/116, R/122, R/147, R/166–169, R/179–184, R/186–189 |
| 4 | Reader sort correctness | Confirmed — no bare `list.files()` readers for newly-versioned outputs; all use `resolve_input()` from plan 197-03 |
| 5 | Parse checks (brace + paren balance) | All new edits balance to 0; pre-existing deltas in 5 scripts confirmed pre-existing |
| 6 | Commit | 5293a04 |

## Helper: versioned_output_path()

**File:** `R/utils/utils_io.R` (auto-sourced by `R/00_config.R`)

Behaviour:
1. Build `dir/stem_run_date.ext`.
2. If that path does not exist, return it immediately.
3. If `VERSIONED_OUTPUT=FALSE`, call `stop()` (explicit opt-out).
4. Otherwise (default), increment `_v2`, `_v3`, ... until a free path is found and return it.

## Scripts Updated

| Script | Dated outputs versioned | RUN_DATE env-var added |
|--------|------------------------|------------------------|
| R/utils/utils_io.R | — (helper added) | — |
| R/116_encounter_ses_index.R | encounter_ses_index .rds/.xlsx | Yes |
| R/122_encounter_distance.R | encounter_distance .rds/.xlsx, distance_patient .rds, 182_facility_zip_diagnosis .xlsx | Yes |
| R/147_surveillance_modality_frequency.R | surveillance_modality_frequency _INTERNAL/.xlsx, surveillance_modality_patient .rds, surveillance_patient_modality_dates .rds/.csv | Yes (Sys.getenv) |
| R/165_distance_cbc_association.R | distance_cbc_association .xlsx | Yes |
| R/166_survivorship_modality_rates.R | survivorship_dated_events .rds, survivorship_modality_rates_parts .rds | Yes |
| R/167_anthracycline_echo.R | survivorship_echo_parts .rds | Yes |
| R/168_survivorship_workbook.R | survivorship_modality_rates_long .rds, _patient .rds/.csv, survivorship_modality_rates .xlsx | Yes |
| R/169_single_source_care.R | single_source_care .csv/.rds/_parts .rds, .xlsx | Yes |
| R/179_cbc_patient_year.R | cbc_patient_year internal .rds, .xlsx | Yes |
| R/180_cbc_missing_capture.R | cbc_missing_capture .xlsx, internal .rds | Yes |
| R/181_cbc_prior_year.R | cbc_prior_year .xlsx, _memo .md | Yes |
| R/183_mice_sensitivity_distance.R | mice_input_patient .rds, mice_mids .rds, mice_trace .png, mice_density .png, mice_sensitivity_distance .xlsx, 183-MEMO .md | Yes |
| R/184_modality_rate_model.R | modality_long internal .rds, modality_rate_model .xlsx, 184-MEMO .md | Yes |
| R/186_survivorship_rate_granularity.R | survivorship_rate_granularity .xlsx | Yes (central run_date) |
| R/187_anthracycline_exposure.R | anthracycline_exposure_patient internal .rds, _summary .xlsx | Yes |
| R/188_echo_rate_since_anthracycline.R | echo_enc_anthracycline .rds, echo_rate_anthracycline_patient .rds, 188_echo_rate_anthracycline .xlsx | Yes (central run_date) |
| R/189_nhl_explainer.R | 189-NHL-EXPLAINER .md | Yes |

## Scripts Confirmed N/A (undated fixed-name outputs)

R/107, R/109, R/110 — fixed output filenames, no date suffix, no same-date overwrite risk.
R/46, R/47, R/48 — use `build_output_path()` with undated filenames (e.g., `cancer_summary_table.xlsx`).

## Deviations from Plan

**1. [Rule 1 - Convention] R/188 filename convention changed from date-prefix to date-suffix**
- Found during: Task 3
- Issue: Original `{YYYYMMDD}_188_echo_rate_anthracycline.xlsx` has date as prefix; `versioned_output_path()` builds `stem_YYYYMMDD.ext` (suffix). Making the stem include the date would double-embed it.
- Fix: Changed stem to `188_echo_rate_anthracycline`, producing `188_echo_rate_anthracycline_YYYYMMDD.xlsx`. Consistent with all other pipeline outputs.
- Files modified: R/188_echo_rate_since_anthracycline.R
- Commit: 5293a04

## Self-Check

- `R/utils/utils_io.R` exists and contains `versioned_output_path`: FOUND
- Commit 5293a04 exists: FOUND
- Brace/paren balance on new edits: all 0 (pre-existing deltas confirmed unchanged)

## Self-Check: PASSED
