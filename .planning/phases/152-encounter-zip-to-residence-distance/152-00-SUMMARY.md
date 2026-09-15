---
phase: 152-encounter-zip-to-residence-distance
plan: "00"
subsystem: zip-centroid-crosswalk
tags: [zip9, centroid, crosswalk, neighborhood-atlas, slurm, hipergator]
dependency_graph:
  requires: []
  provides:
    - R/122a_build_zip9_centroid_crosswalk.R
    - slurm/122a_build_zip9_centroid_crosswalk.sbatch
    - CONFIG$atlas_zip4_dir
    - CONFIG$zip9_bg_centroid_path
  affects:
    - R/122 (get_zip_centroid reads the crosswalk)
    - 152-01-PLAN.md (Plan 01 probe gate 2 checks crosswalk existence)
tech_stack:
  added: [vroom, dplyr, stringr, glue, foreign (TIGER fallback)]
  patterns:
    - col_select for memory-bounded reads of large Atlas CSVs
    - ZIP4_COL / FIPS_COL named placeholder constants for unconfirmed column names
    - Dual centroid-source probe (NHGIS -> TIGER/Line -> actionable stop)
    - BUILDLOG sibling file with per-state counts
key_files:
  created:
    - R/122a_build_zip9_centroid_crosswalk.R
    - slurm/122a_build_zip9_centroid_crosswalk.sbatch
  modified:
    - R/00_config.R (atlas_zip4_dir + zip9_bg_centroid_path added)
decisions:
  - "CONFIG$atlas_zip4_dir path is a placeholder (/blue/erin.mobley.precision/ADI_zip4_files); must be confirmed on HiPerGator before sbatch submission"
  - "ZIP4_COL and FIPS_COL are named placeholder constants in R/122a; must be replaced with confirmed column names from a real Atlas file header"
  - "Centroid source discovery order: NHGIS table first, TIGER/Line DBF second; script stops with Census download URLs if neither is staged"
metrics:
  duration: "~15 min"
  completed: "2026-09-15"
  tasks_completed: 2
  tasks_total: 3
  files_modified: 3
---

# Phase 152 Plan 00: ZIP9 Centroid Crosswalk Builder Summary

**One-liner:** Builder script and sbatch wrapper for ZIP9 -> block-group centroid crosswalk from Neighborhood Atlas ZIP+4 files, with placeholder column names requiring Task 1 head inspection on HiPerGator before job submission.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add CONFIG$atlas_zip4_dir (Windows portion) | 8e4446f | R/00_config.R |
| 2 | Write R/122a builder + sbatch wrapper | 721c7cd | R/122a_build_zip9_centroid_crosswalk.R, slurm/122a_build_zip9_centroid_crosswalk.sbatch |

## Task 3 (Checkpoint): Run and Validate on HiPerGator

**Status:** AWAITING HUMAN ACTION — blocking checkpoint, plan `autonomous: false`.

### Before Submitting the SLURM Job (Complete Task 1 on HiPerGator)

Task 1's head inspection could not run on the Windows planning machine. Before submitting the sbatch job, do the following on HiPerGator:

1. Locate the Atlas ZIP+4 directory:
   ```bash
   ls /blue/erin.mobley.precision/
   ```
   Find the directory containing the 51 per-state CSV files.

2. Inspect a file header (pick a small state like Delaware or Vermont):
   ```bash
   head -2 /blue/erin.mobley.precision/<atlas_dir>/<state_file>.csv
   ```
   Record:
   - The exact column name holding the ZIP+4 identifier (replace `ZIP4_COL` in `R/122a`)
   - The exact column name holding the block-group FIPS (replace `FIPS_COL` in `R/122a`)
   - Whether FIPS values are 12 digits (block-group) or 15 digits (block — script truncates automatically)

3. Update `R/00_config.R`: replace the placeholder path in `atlas_zip4_dir` with the confirmed directory path.

4. Update `R/122a_build_zip9_centroid_crosswalk.R`: replace the `ZIP4_COL` and `FIPS_COL` constants (lines ~60-62) with the confirmed column names.

5. Confirm a centroid source is staged (NHGIS block-group CSV or TIGER/Line 2020 DBFs); the script searches these candidate directories automatically:
   - `/blue/erin.mobley.precision/`
   - `/blue/erin.mobley-hl.bcu/reference/`
   - `/blue/erin.mobley-hl.bcu/clean/reference/`

### Submitting and Validating

```bash
sbatch slurm/122a_build_zip9_centroid_crosswalk.sbatch
```

After completion, validate:

```bash
head -3 data/reference/zip9_bg_centroid_crosswalk.csv
# header: ZIP9,GEOID,INTPTLAT,INTPTLON
# ZIP9 = 9 digits, GEOID = 12 digits, INTPTLON < 0
```

In R:
```r
library(vroom)
cw <- vroom("data/reference/zip9_bg_centroid_crosswalk.csv",
            col_types = cols(ZIP9 = col_character(), GEOID = col_character(),
                             INTPTLAT = col_double(), INTPTLON = col_double()))
stopifnot(all(nchar(cw$ZIP9) == 9))
stopifnot(all(nchar(cw$GEOID) == 12))
stopifnot(!any(duplicated(cw$ZIP9)))
stopifnot(all(cw$INTPTLAT >= 17 & cw$INTPTLAT <= 72))
stopifnot(all(cw$INTPTLON >= -180 & cw$INTPTLON <= -64))
```

Spot-check 3 Gainesville (326xx-xxxx) ZIP9s — centroids should be within ~30 km of (29.65, -82.32).

Review the build log: `data/reference/zip9_bg_centroid_crosswalk_BUILDLOG_<date>.txt`
- 50-51 state files present
- WV listed as missing (expected for 2024 Atlas)
- n_unmatched GEOIDs < 1% of rows (if larger, Atlas and centroid source are different vintages — swap the centroid file)

### Resume Signal

Reply "approved" (crosswalk validates) or describe any issues (column format mismatch, vintage mismatch, memory failure) so the continuation agent can correct and re-run.

## Deviations from Plan

### Windows-constrained Task 1

**Rule 2 — Missing confirmation deferred:** Task 1 requires running `ls` and `head -2` on HiPerGator to confirm the Atlas column names. This cannot run on the Windows planning machine. Mitigation applied:

- Added `CONFIG$atlas_zip4_dir` to `R/00_config.R` with a placeholder path and explicit "UNCONFIRMED" comment.
- Named the placeholder constants `ZIP4_COL` and `FIPS_COL` in `R/122a` as the only place these strings appear, so a single find-replace updates the script once names are confirmed.
- Documented the `head -2` command in the SLURM wrapper's pre-submission checklist and in this SUMMARY.

**Impact:** The sbatch job cannot be submitted until Task 1 head inspection is completed on HiPerGator (5 min of manual work).

## Known Stubs

- `ZIP4_COL <- "ZIP9"` (R/122a line ~60): placeholder — not confirmed from real file header.
- `FIPS_COL <- "FIPS"` (R/122a line ~62): placeholder — not confirmed from real file header.
- `atlas_zip4_dir = "/blue/erin.mobley.precision/ADI_zip4_files"` (R/00_config.R): placeholder path — not confirmed on HiPerGator.

None of these stubs prevent plan completion; they gate the SLURM job submission (Task 3).

## Self-Check: PASSED

- [x] R/122a_build_zip9_centroid_crosswalk.R exists
- [x] slurm/122a_build_zip9_centroid_crosswalk.sbatch exists
- [x] R/00_config.R modified (atlas_zip4_dir + zip9_bg_centroid_path)
- [x] Commits 8e4446f and 721c7cd exist in git log
- [x] grep col_select / substr(.*1,12) / vroom_write / BUILDLOG all match
- [x] Script contains no network download calls inside SLURM
