---
phase: 144
plan: "02"
subsystem: ses-linkage
tags: [ses, sdi, adi, svi, ruca, encounter, zip9, duckdb, investigation]
dependency_graph:
  requires: [144-01]
  provides: [R/116_encounter_ses_index.R, encounter_ses_index_YYYYMMDD.rds, encounter_ses_index_summary_YYYYMMDD.xlsx]
  affects: []
tech_stack:
  added: []
  patterns: [probe-first-gated reference loads, approximate_zip9 chain, openxlsx2 workbook assembly, DuckDB ENCOUNTER pull scoped to address extract]
key_files:
  created:
    - R/116_encounter_ses_index.R
  modified: []
decisions:
  - "Encounter pull scoped to LDS_ADDRESS_HISTORY patients (address-coverage filter, not HL-cohort filter per D-07)"
  - "Tier 3 centroid fallback is inert as of this plan (no crosswalk); ADI will be fully null per P1-07"
  - "All four reference file loads are probe-first gated; missing files produce NA columns, not errors"
metrics:
  duration_minutes: 15
  completed_date: "2026-08-16"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 0
requirements_met: [SES-01, SES-02, SES-03, SES-04]
---

# Phase 144 Plan 02: R/116 Encounter-Level SES Index Linkage Summary

## One-liner

Standalone investigation script linking encounter-level ZIP9/ZIP5 (via `get_zip9_at_date() |> approximate_zip9()`) to SDI, ADI, SVI, and RUCA scores from probe-first-gated reference files, producing a dated RDS cache and 3-sheet summary xlsx.

## What Was Built

`R/116_encounter_ses_index.R` — a read-only investigation script (346 lines) that:

1. Probes four reference files (RUCA always expected; SDI/ADI/SVI probe-first gated)
2. Pulls ENCOUNTER rows from DuckDB scoped to patients present in LDS_ADDRESS_HISTORY
3. Resolves ZIP9/ZIP5 per encounter via `get_zip9_at_date() |> approximate_zip9()` (includes Phase 144 Tier 3 centroid fallback, currently inert)
4. Joins RUCA (ZIP5), SDI (ZIP5), SVI (ZIP5), and ADI (ZIP9) scores with `na_matches = "never"`
5. Saves `output/encounter_ses_index_YYYYMMDD.rds` (one row per PATID/ENCOUNTERID/ADMIT_DATE)
6. Saves `output/encounter_ses_index_summary_YYYYMMDD.xlsx` with 3 sheets: ZIP Source Breakdown, Index Coverage, RUCA Distribution

## Output Grain

One row per `(PATID, ENCOUNTERID, ADMIT_DATE)` with columns:
`PATID, ENCOUNTERID, ADMIT_DATE, ZIP9, ZIP5, match_type, zip9_source, sdi_score, adi_natrank, svi_score, ruca_code, ruca_category`

## Commits

| Task | Description | Commit |
|------|-------------|--------|
| 1+2  | Write complete R/116 script (all 10 sections) | e7b160e |

## Deviations from Plan

None — plan executed exactly as written. Tasks 1 and 2 were committed together since they constitute a single file created in one pass; the plan did not specify separate commits per task (both were `type="auto"` with no checkpoint between them).

## Known Stubs

None. All four SES index columns (sdi_score, adi_natrank, svi_score, ruca_code) will be NA at runtime for reference files not yet staged — this is the honest, documented state per the probe-first gating design, not a stub. ADI will be fully null because (a) the Neighborhood Atlas crosswalk is pending P-03a acquisition and (b) the Tier 3 centroid crosswalk is absent (see P1-07 note in script SECTION 7).

## Self-Check: PASSED

- R/116_encounter_ses_index.R: FOUND (commit e7b160e)
- get_zip9_at_date / approximate_zip9 chain: CONFIRMED (lines 126-129)
- All 4 probe gates (has_ruca/has_sdi/has_adi/has_svi): CONFIRMED
- Output RDS path naming: CONFIRMED (`encounter_ses_index_{RUN_DATE}.rds`)
- Output XLSX path naming: CONFIRMED (`encounter_ses_index_summary_{RUN_DATE}.xlsx`)
- RUCA joined via ZIP5: CONFIRMED (line 271)
- ADI joined via ZIP9: CONFIRMED (line 277)
- No get_hl_patient_ids() call: CONFIRMED (grep count = 0)
