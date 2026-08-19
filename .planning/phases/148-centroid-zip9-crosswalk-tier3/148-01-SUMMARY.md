---
phase: 148-centroid-zip9-crosswalk-tier3
plan: 01
subsystem: address-imputation
tags: [zip9, adi, centroid, route-b, neighborhood-atlas, decisions]
requires: [147-DISCOVERY.md]
provides: [148-DISCOVERY.md, R/118_build_centroid_crosswalk.R]
affects: [R/116_build_ses_variables.R, R/utils/utils_address.R]
tech-stack:
  added: []
  patterns: [vroom-cols-default-c, here-paths, stopifnot-gates, named-constants]
key-files:
  created:
    - .planning/phases/148-centroid-zip9-crosswalk-tier3/148-DISCOVERY.md
    - R/118_build_centroid_crosswalk.R
  modified: []
decisions:
  - "D-01 BUILD: zip5_no_zip9 = 59,818 is material; phase proceeds"
  - "D-02 Route B: ZIP5-level ADI summary via grouping neighborhood_atlas_zip9_adi.csv"
  - "D-03 not applicable: Route A sub-routes (USPS API, commercial, D-03c) all ruled out"
  - "D-05 answered: Neighborhood Atlas ZIP9-keyed file staged (37M rows, ADI_NATRANK)"
  - "zip9_source for Route B cannot be zip5_centroid — no ZIP9 imputed; tracked as Wave 3"
metrics:
  duration: 15 min
  completed: 2026-08-19
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 0
---

# Phase 148 Plan 01: Gate Decisions and Build Script Summary

**One-liner:** Gate confirmed (59,818 encounters), Route B chosen (ZIP5-level ADI median from Neighborhood Atlas ZIP9 file via grouping), and build script R/118 written with five blocking validation gates.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Write 148-DISCOVERY.md — gate, D-05, D-02, D-03 decisions | 5ff83a0 | .planning/phases/148-centroid-zip9-crosswalk-tier3/148-DISCOVERY.md |
| 2 | Write R/118_build_centroid_crosswalk.R — ZIP5 ADI summary builder | 3184378 | R/118_build_centroid_crosswalk.R |

## What Was Built

**148-DISCOVERY.md** records all open decisions from 148-CONTEXT.md:

- **§0 (D-01 gate):** `zip5_no_zip9 = 59,818` from 147-DISCOVERY.md §4 post-147-redo column.
  Decision is BUILD. Reasoning: (a) the earlier "0 encounters" was a coalesce-arm artefact
  (commit `2e79285` corrected it); (b) 59,818 are genuinely unresolvable at Tiers 1–2 because
  no ZIP9 ever existed for those patients; (c) the build requires only a grouping operation on
  an already-staged 478 MB file.

- **§1 (D-05):** Neighborhood Atlas does publish a ZIP+4-keyed file. It is already staged at
  `data/reference/neighborhood_atlas_zip9_adi.csv` (37,029,488 rows; columns ZIP9 + ADI_NATRANK;
  gitignored; needs scp to HiPerGator before Wave 2).

- **§2 (D-02):** Route B — ZIP5-level ADI summary — chosen over Route A (centroid crosswalk).
  Route B groups the staged file by `substr(ZIP9, 1, 5)` and computes median/p25/p75 of
  ADI_NATRANK. No coordinates, no geocoding, no additional licence, more defensible methods text.

- **§3 (D-03):** Not applicable. Route A's three sub-routes (USPS API, commercial file, D-03c)
  are all ruled out. R/118 is repurposed to build `zip5_adi_summary.csv` via Route B.

- **§4 (zip9_source):** Route B does not impute a ZIP9 — it fills ADI coverage only.
  The `zip9_source` value `"zip5_representative"` must be added to `.classify_zip9_source()`
  in `R/utils/utils_address.R` (tracked as Wave 3 change in 148-03-PLAN.md). The 0000 guard
  in `approximate_zip9()` is not touched.

- **§5 (D-04 placeholders):** Three reporting figures — (a) ZIP5s resolved, (b) of the
  zip5_no_zip9 ZIP5s how many the summary covers, (c) encounters gaining ADI — deferred to
  Wave 2/3 HiPerGator runs.

**R/118_build_centroid_crosswalk.R** is a HiPerGator-ready build script:

- Reads `data/reference/neighborhood_atlas_zip9_adi.csv` via vroom with `cols(.default = "c")`
- Filters to 9-digit numeric ZIP9s; derives ZIP5 = `substr(ZIP9, 1, 5)`
- Converts ADI_NATRANK to numeric; maps suppression codes (GQ/GQ-PH/PH/QDI) to `NA_real_`
- Groups by ZIP5; computes `adi_natrank_median`, `adi_natrank_p25`, `adi_natrank_p75`,
  `n_zip9_in_zip5`, `n_zip9_with_adi`; adds metadata columns (vintage/method/source)
- Five blocking `stopifnot()` gates: 5-char ZIP5, digits-only, no-0000, unique, n>0
- Writes `data/reference/zip5_adi_summary.csv` via `readr::write_csv`
- No `setwd()`, no `read.csv()`, no `data.table`; `here::here()` for all paths

## Deviations from Plan

**1. [Rule 3 - Adaptation] Rscript parse-only unavailable in Windows environment**

The plan's automated verify step calls `Rscript --vanilla --parse-only R/118_build_centroid_crosswalk.R`. Rscript is not available on this Windows machine (confirmed in STATE.md Known Blockers and re-confirmed during execution). Verification was satisfied by:
- Manual inspection of script structure (all five stopifnot gates present, no setwd/read.csv/data.table, here() paths, correct method string)
- grep-based pattern checks confirming ADI_SUPPRESSION_CODES, stopifnot, zip5_adi_summary_route_b all present
- True R-parse deferred to HiPerGator (Wave 2 prerequisite anyway, since the 478 MB input file must be scp'd there first)

This matches the established deviation pattern from Phases 139–147 for this project.

## Known Stubs

**§5 placeholders in 148-DISCOVERY.md:** D-04 figures (a), (b), (c) are `[TBD after Wave 2/3]`.
These are intentional placeholders — the data they require can only be produced by running
`R/118_build_centroid_crosswalk.R` on HiPerGator (Wave 2) and then re-running R/116 (Wave 3).
The placeholders do not prevent this plan's goal (decisions recorded, build script ready).
Wave 2 plan (148-02-PLAN.md) will fill them.

## Self-Check: PASSED

- FOUND: .planning/phases/148-centroid-zip9-crosswalk-tier3/148-DISCOVERY.md
- FOUND: R/118_build_centroid_crosswalk.R
- FOUND: commit 5ff83a0 (docs(148-01): 148-DISCOVERY.md)
- FOUND: commit 3184378 (feat(148-01): R/118_build_centroid_crosswalk.R)
