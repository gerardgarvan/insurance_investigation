---
phase: 146-acquire-and-stage-the-ses-reference-files-sdi-svi-adi
plan: "04"
subsystem: ses-reference-files
tags: [svi, findsvi, zcta, census-api, derivation]
dependency_graph:
  requires: ["146-02", "146-03"]
  provides: ["R/117_build_svi_zcta.R", "svi_2020_zcta_derived.csv (PENDING HiPerGator run)"]
  affects: ["R/116_encounter_ses_index.R (SECTION 6 SVI probe, path update in 146-05)"]
tech_stack:
  added: ["findSVI (CRAN)", "tidycensus (findSVI dependency)"]
  patterns: ["derivation metadata columns (vintage/method/source)", "Census API key via Sys.getenv", "here() for all paths"]
key_files:
  created: ["R/117_build_svi_zcta.R"]
  modified: [".planning/phases/146-acquire-and-stage-the-ses-reference-files-sdi-svi-adi/146-DISCOVERY.md"]
decisions:
  - "D-02a-i (findSVI) confirmed and implemented; no svi_areal_coverage column (no aggregation)"
  - "ADI staging not written per D-05 (block group only, no ZIP9 column)"
metrics:
  duration_minutes: 15
  completed_date: "2026-08-17"
  tasks_completed: 2
  tasks_total: 3
  files_created: 1
  files_modified: 1
---

# Phase 146 Plan 04: SVI Build Script (findSVI) Summary

**One-liner:** findSVI CRAN script `R/117_build_svi_zcta.R` derives ZCTA-level 2020 SVI from ACS via Census API, outputting `ZCTA`/`RPL_THEMES`/`vintage`/`method`/`source` with -999-to-NA guard; derived CSV is PENDING HiPerGator run.

## Tasks Completed

| Task | Name | Status | Commit |
|------|------|--------|--------|
| 1 | Branch on D-02 decision | Auto-approved (D-02a-i confirmed in DISCOVERY.md) | — |
| 2 | Write R/117_build_svi_zcta.R | COMPLETE | e0afeea |
| 3 | Run on HiPerGator, commit derived CSV | PENDING — checkpoint:human-action | — |

## What Was Built

`R/117_build_svi_zcta.R` (171 lines):

- Calls `findSVI::find_svi(year=2020, geography="zcta", key=Sys.getenv("CENSUS_API_KEY"))`
- Guards: `RPL_THEMES = if_else(RPL_THEMES < 0, NA_real_, RPL_THEMES)` applied before writing
- Adds derivation metadata: `vintage="2020"`, `method` (includes ZCTA-vs-tract ranking caveat: "percentile-ranked against ZCTAs, NOT comparable to CDC tract SVI"), `source` (ACS 2020 5-year via Census API)
- Output columns: `ZCTA`, `RPL_THEMES`, `vintage`, `method`, `source` — exactly what R/116 SECTION 6 expects (joins on `ZIP5 = ZCTA`, reads `svi_score = RPL_THEMES`)
- No `svi_areal_coverage` column — findSVI does no tract-to-ZCTA aggregation
- Uses `here()` for all paths, `Sys.getenv("CENSUS_API_KEY")` for API key (no hard-coding), `write_csv()` not `write.csv()`
- Script number 117 = next sequential free number in R/ (confirmed no R/117* existed)

## Deviations from Plan

None — plan executed exactly as written, given the D-02a-i decision context provided.

The plan's Task 1 (checkpoint:decision) was auto-approved because the decision context explicitly confirmed D-02a-i in the execution prompt and in 146-DISCOVERY.md PART H. Task 3 (checkpoint:human-action) stops here as specified — the derived CSV requires a HiPerGator run with the Census API key.

## ADI Sections — Not Applicable

D-05 confirmed block group only (downloaded file: `US_2024_block_group_adi_v_4_0_1.csv`, columns `GISJOIN`, `FIPS`, `ADI_NATRANK`, `ADI_STATERNK` — no ZIP9 or ZIP_PLUS4 column). No ADI staging script was written. R/116's probe gate continues to degrade `adi_natrank` to NA for all rows (no code change needed).

## Pending (Task 3 — human-action gate)

**To complete this plan:**
1. On HiPerGator login node, confirm `~/.Renviron` contains `CENSUS_API_KEY=<key>`
2. Run: `module load R/4.4.2 && Rscript R/117_build_svi_zcta.R`
3. Confirm `data/reference/svi_2020_zcta_derived.csv` produced with columns `ZCTA`, `RPL_THEMES`, `vintage`, `method`, `source`
4. Verify row count (expect ~33k ZCTAs) and `sum(is.na(RPL_THEMES))` (expect small — findSVI suppression is rare)
5. Commit `data/reference/svi_2020_zcta_derived.csv` (CDC public domain data — committable per 146-DISCOVERY.md PART H)
6. Report: row count, NA count, commit hash

## Self-Check: PASSED

- `R/117_build_svi_zcta.R` exists: FOUND (git show e0afeea confirms)
- Commit e0afeea exists: CONFIRMED (`git rev-parse --short HEAD` = e0afeea)
- Static checks:
  - `grep "RPL_THEMES < 0"` — FOUND (line 74)
  - `grep "vintage"` — FOUND (line 96)
  - `grep "ranked against ZCTA"` — FOUND (method string)
  - `grep -i "setwd\|read\.csv\|data\.table"` — NOT FOUND (correct)
  - Line count: 171 (>= 30 minimum)
- 146-DISCOVERY.md PART I-SVI records script path and PENDING status: CONFIRMED
- No ADI staging script written: CONFIRMED
