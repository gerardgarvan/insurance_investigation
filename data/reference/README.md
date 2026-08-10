# data/reference/ -- Reference Data Files

This directory holds static reference datasets consumed by the R pipeline
(distinct from PCORNET_TABLES clinical data). Existing files:

- `RUCA-codes-2020-zipcode.xlsx` -- used by R/100
- `all_codes_resolved_next_tables_v2.1.xlsx`
- `ndc_rxnorm_crosswalk.rds`

## Neighborhood Atlas ZIP9-to-Block-Group Crosswalk (Phase 140, P-03a)

**Expected path:** `data/reference/neighborhood_atlas_block_group_crosswalk.csv`

**Purpose:** Enables R/115_zip_stability_counts.R's A-06 block-group accuracy tier
(SECTION 8), currently gracefully degraded to `NA_real_` / "not available" because this
file does not exist in this repo. No further code changes are required to activate the
tier -- R/115 auto-probes for this exact path, joins automatically, and (per this plan)
gates on match-rate coverage once the file is present.

**Source:** University of Wisconsin Neighborhood Atlas (https://www.neighborhoodatlas.medicine.wisc.edu/).
Requires portal access/download -- not obtainable via CLI or API. If the team has an
existing internal source for this crosswalk, use that instead of a fresh Neighborhood
Atlas download.

**Vintage (140-08-PATCH FIX-11; corrected 2026-08-06 by 140-09-PATCH FIX-22):**
Neighborhood Atlas publishes ZIP+4-to-block-group files by release year (known releases
include 2015, 2019, 2020, 2021). LDS_ADDRESS_HISTORY's study period is 2012-01-01 to
2025-03-31 (per ZIP_STUDY_PERIOD_MIN/MAX) -- a 13-year span. **A single crosswalk
vintage cannot match a 13-year study period; no such vintage exists.** Do not describe
any single release as "matched to the study period." Choose explicitly between:

- **Single vintage (simpler).** Use the 2021 Neighborhood Atlas release only, and
  document that ZIP+4-to-block-group assignments drift over a 13-year window, so a
  share of A-06's block-group misses will be crosswalk-vintage error rather than
  carry-forward error. State this as a known limitation of the block-group tier, both
  here and on the A-06 sheet -- not as a settled match.
- **Two vintages (defensible).** Stage both 2015 and 2021, run A-06's block-group tier
  against each, and report the spread. If the two agree, vintage drift is not material
  for this deliverable and the limitation above can be dropped. If they diverge, that
  divergence *is* the measurement error and belongs in the methods, not in a caveat.

Either is acceptable; PENDING TEAM CONFIRMATION which one (same pending-confirmation
posture as the 90% match-rate threshold below -- do not treat either as final without
Erin/Amy sign-off). Whichever release year(s) are actually obtained, record them in this
README (below) and note them in the KEY sheet -- the block-group tier's accuracy figures
are conditional on that choice and must not be reported as vintage-neutral. If multiple
vintages end up staged side-by-side, R/115 SECTION 8 must be extended to select
explicitly (by filename convention or a config constant) or to run both and report the
spread per the two-vintage option above -- it does not do either today because only one
vintage is expected to be staged at a time.

**Expected columns** (R/115 SECTION 8 probes for the first match in each list; if the
staged file uses different names, add them to R/115's `candidate_cols`/`candidate_bg_cols`
vectors -- do not rename the source file's columns):
- ZIP9 key: one of `ZIP9`, `zip9`, `ADDRESS_ZIP9`, `zip9_norm`, `GEOID9`, `ZIP_PLUS4`
- Block-group key: one of `block_group_id`, `block_group`, `BLOCK_GROUP`, `GEOID_BG`, `bg_id`

**Match-rate coverage gate (140-08-PATCH FIX-12):** File existence alone is not
sufficient for P-03a's acceptance. R/115 SECTION 8 also computes
`n_zip9_matched_to_block_group / n_zip9_distinct_observed` (the fraction of DISTINCT
ZIP9s actually observed in `addr_coal` that the crosswalk covers) and gates on a minimum
threshold, default 90% -- PENDING TEAM CONFIRMATION. Below that threshold,
`block_group_tier_status` reads `"found but coverage insufficient"` rather than
publishing `pct_block_group_match` figures computed on a non-random subset of the data.
P-03a's acceptance is therefore `has_block_group_crosswalk = TRUE` **and** match rate
above threshold, not file existence alone.

**Status as of 2026-08-06:** Not staged. R/115's block-group tier reads
`block_group_tier_status <- "not available (crosswalk file not found)"` and
`pct_block_group_match` is `NA_real_` across all gap bins on the last real run.
