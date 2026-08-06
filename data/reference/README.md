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

**Vintage (140-08-PATCH FIX-11):** Neighborhood Atlas publishes ZIP+4-to-block-group
files by release year (known releases include 2015, 2019, 2020, 2021). Applying an
off-vintage crosswalk to LDS_ADDRESS_HISTORY records (study period 2012-01-01 to
2025-03-31, per ZIP_STUDY_PERIOD_MIN/MAX) risks the block-group tier attributing
boundary-redefinition noise to carry-forward error, or vice versa. Required vintage for
this deliverable: the most recent Neighborhood Atlas release available at acquisition
time (as of this document, that is the 2021 release) -- recommended as the default
choice, PENDING TEAM CONFIRMATION (same pending-confirmation posture as the 90% match-rate
threshold below; do not treat either as final without Erin/Amy sign-off). Whichever
release year is actually obtained, record it in this README (below) and note it in the
KEY sheet -- the block-group tier's accuracy figures are conditional on that choice and
must not be reported as vintage-neutral. If multiple vintages end up staged
side-by-side, R/115 SECTION 8 must be extended to select one explicitly (by filename
convention or a config constant) rather than globbing for "a" crosswalk file -- it does
not do this today because only one vintage is expected to be staged at a time.

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
