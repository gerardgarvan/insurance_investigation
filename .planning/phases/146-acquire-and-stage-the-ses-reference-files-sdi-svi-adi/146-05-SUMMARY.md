---
phase: 146-acquire-and-stage-the-ses-reference-files-sdi-svi-adi
plan: "05"
subsystem: ses-reference-files
tags: [svi, sdi, adi, r116, coverage-ceilings, readme, wiring]
dependency_graph:
  requires: ["146-03", "146-04"]
  provides: ["R/116 reads staged SVI/SDI/ADI files", "Coverage Ceilings workbook sheet", "Corrected README"]
  affects: ["R/116_encounter_ses_index.R", "data/reference/README.md"]
tech_stack:
  added: []
  patterns: ["probe-first gated reference paths", "Coverage Ceilings workbook sheet"]
key_files:
  created: []
  modified:
    - R/116_encounter_ses_index.R
    - data/reference/README.md
decisions:
  - "SVI_PATH updated to svi_2020_zcta_derived.csv (D-02a-i; findSVI)"
  - "ADI_PATH updated to neighborhood_atlas_zip9_adi.csv (D-05; ZIP9 23-state collation)"
  - "SDI columns unchanged: ZIP5/SDI_score exact match, no R/116 select() change needed"
  - "Coverage Ceilings sheet added to workbook (§4 expectations table)"
  - "77.7% ceiling replaces 68.6% everywhere; 68.6% confirmed absent"
metrics:
  duration_minutes: 25
  completed_date: "2026-08-17"
  tasks_completed: 2
  tasks_total: 2
  files_created: 0
  files_modified: 2
---

# Phase 146 Plan 05: Wire R/116 and README to Staged Files — Summary

**One-liner:** R/116 now reads `svi_2020_zcta_derived.csv` (findSVI D-02a-i) and `neighborhood_atlas_zip9_adi.csv` (D-05 ZIP9 collation); a "Coverage Ceilings" §4 sheet is added; README rewrites SVI as derived, SDI with D-01 ZCTA label, and ADI with 77.7% ceiling — replacing the old 68.6% figure and the phantom svi_2020_us_by_zcta.csv portal-download description.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Point R/116 at staged files; add Coverage Ceilings sheet | 43f5a9c | R/116_encounter_ses_index.R |
| 2 | Rewrite README SVI/SDI/ADI sections; correct 77.7% ceiling | 759254f | data/reference/README.md |

## What Was Built

**Task 1 — R/116 wired to staged files:**

- `SVI_PATH` changed from `svi_2020_us_by_zcta.csv` to `svi_2020_zcta_derived.csv` (SECTION 2)
- `ADI_PATH` changed from `neighborhood_atlas_block_group_crosswalk.csv` to `neighborhood_atlas_zip9_adi.csv` (SECTION 2)
- SDI: no `select()` change -- staged file columns `ZIP5`/`SDI_score` match R/116's existing select exactly
- SVI: no `select()` change -- derived file columns `ZCTA`/`RPL_THEMES` match R/116's existing `select(ZIP5 = ZCTA, svi_score = RPL_THEMES)` exactly
- ADI: no `select()` change -- `ZIP9` and `ADI_NATRANK` are both in candidate lists; R/116 auto-detects
- Section comments updated to reflect derived/ZIP9-keyed nature of each file
- Added `coverage_ceilings` tibble (§4 table) and "Coverage Ceilings" worksheet to SECTION 9 workbook:
  - Rows: RUCA (ZIP5, 77.7% achieved), SDI (ZCTA via ZIP5 D-01, <=77.7% minus ZIP5-with-no-ZCTA haircut), SVI (ZCTA via ZIP5 derived D-02a-i, <=77.7% minus ZCTA match), ADI (ZIP9 D-05, <=77.7%)
  - Note row: 22.3% (434,227) encounters receive no index: 14.1% sentinel-ZIP (275,528) + 8.1% no-address-record (158,699)
  - Note row: SVI ZCTA-vs-tract ranking caveat
- `many-to-one` relationship (line comment + `relationship =` argument) preserved: grep count = 2 (correct)
- Both fan-out `stopifnot()` guards preserved (lines 163, 316)
- 68.6%: `grep -c 68.6 R/116_encounter_ses_index.R` == 0

**Task 2 — README rewritten:**

- ADI section (new): describes `neighborhood_atlas_zip9_adi.csv` as STAGED (local, gitignored 478MB); D-05 answer (ZIP9-keyed files exist, 23 states); scp transfer path; `ZIP9`/`ADI_NATRANK` columns; 77.7% ceiling with corrected 2026-08-17 figures; block-group crosswalk note moved to sub-note
- SDI section: status updated to STAGED (32,989 rows, committed); D-01 label added (ZCTA-level value not ZIP5-level measure; required wording provided); ZIP5-with-no-ZCTA haircut noted as PENDING HiPerGator run; Coverage Ceilings sheet cross-referenced
- SVI section: completely rewritten as derived file (D-02a-i findSVI); removed all references to non-existent `svi_2020_us_by_zcta.csv` portal download; ZCTA-vs-tract ranking caveat prominent; D-02a-i output contract documented (columns, no svi_areal_coverage); status PENDING HiPerGator run
- `grep -c "68.6" data/reference/README.md` == 0
- `grep -E "77.7|svi_2020_zcta_derived|ZCTA-level"` matches

## Deviations from Plan

None -- plan executed exactly as written.

The D-05 revised answer (ZIP9-keyed files exist) was already recorded in DISCOVERY.md PART H before this plan ran, so the ADI section describes the staged file directly rather than "block group only cannot be joined on ZIP9." The plan's interface note anticipated this path.

## Known Stubs

One intentional pending value: ZIP5-with-no-ZCTA unmatched count in the Coverage Ceilings sheet reads "PENDING HiPerGator run" -- this is not a stub but an honest status. The count will be computed by `R/diagnostics/146_sdi_coverage_quantifier.R` once the HiPerGator job runs.

## Self-Check: PASSED

- Commit 43f5a9c: present (`git log --oneline | grep 43f5a9c`)
- Commit 759254f: present (`git log --oneline | grep 759254f`)
- `grep "svi_2020_zcta_derived" R/116_encounter_ses_index.R` -- FOUND (path constant + comment)
- `grep "Coverage Ceilings" R/116_encounter_ses_index.R` -- FOUND (wb_add_worksheet + wb_add_data)
- `grep -c "68.6" R/116_encounter_ses_index.R` -- 0
- `grep -c "68.6" data/reference/README.md` -- 0
- `grep "svi_2020_zcta_derived" data/reference/README.md` -- FOUND
- `grep "ZCTA-level" data/reference/README.md` -- FOUND
- `grep "77.7" data/reference/README.md` -- FOUND
- No setwd/read.csv/data.table/absolute paths introduced: static check confirmed
