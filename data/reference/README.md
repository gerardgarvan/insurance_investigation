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

### Also consumed by R/116 for ADI (Phase 145)

R/116_encounter_ses_index.R SECTION 6 (lines 214-248) probes this SAME file
(`data/reference/neighborhood_atlas_block_group_crosswalk.csv`) to supply its
encounter-level `adi_natrank` column, joined on **ZIP9** (not ZIP5). R/116 accepts the
ZIP9 key as the first present of `ZIP9`, `zip9`, `ADDRESS_ZIP9`, `zip9_norm`, `GEOID9`,
`ZIP_PLUS4`, and the rank as the first present of `adi_natrank`, `ADI_NATRANK`, `natrank`.
Because Tier 3 centroid ZIP9 resolution is inert (144-CONTEXT.md D-01) AND this crosswalk
is not staged (P-03a pending), `adi_natrank` is entirely NA on current runs. Acquisition
status is the same as the Phase 140 block-group tier above -- not staged as of 2026-08-17.

## SDI -- Social Deprivation Index (Robert Graham Center) (Phase 145)

**Expected path:** `data/reference/zip5_sdi_reference.csv`

**Purpose:** Supplies R/116 SECTION 6/7's `sdi_score` column (encounter-level SES),
joined on ZIP5.

**Source:** Robert Graham Center Social Deprivation Index
(https://www.graham-center.org/maps-data-tools/social-deprivation-index.html).
Portal download -- not obtainable via CLI/API.

**Expected columns:**
- Join key: `ZIP5` (character, 5-digit; normalized via `normalize_zip5_raw()`)
- Value: `SDI_score` (numeric, 0-100)

**R/116 probe gate:** SECTION 6 (lines 187-212) checks `has_sdi` (file.exists on
`SDI_PATH`) and then requires BOTH columns `ZIP5` and `SDI_score` to be present. If the
file is absent OR either column is missing, `sdi_lookup` is empty and `sdi_score` is
`NA_real_` for all encounter rows (a console message names the available columns). If the
staged file uses different column names, update the `select(ZIP5, sdi_score = SDI_score)`
in R/116 SECTION 6 rather than renaming the source file.

**Status as of 2026-08-17:** Not staged. `sdi_score` is NA across all rows.

## SVI -- CDC/ATSDR Social Vulnerability Index 2020 (Phase 145)

**Expected path:** `data/reference/svi_2020_us_by_zcta.csv`

**Purpose:** Supplies R/116 SECTION 6/7's `svi_score` column, joined on ZIP5 (ZCTA is an
approximation of ZIP5 and differs in edge cases).

**Source:** CDC/ATSDR SVI 2020, ZCTA-level file, downloaded from the CDC GRASP portal
(https://www.atsdr.cdc.gov/placeandhealth/svi/). Portal download -- not obtainable via CLI/API.

**Expected columns:**
- Join key: `ZCTA` (character, 5-digit; carried in R/116 as `ZIP5 = ZCTA`)
- Value: `RPL_THEMES` (numeric, composite overall SVI percentile, 0-1). CDC encodes
  missing as `-999`; R/116 maps any value `< 0` to `NA_real_`.

**R/116 probe gate:** SECTION 6 (lines 250-278) checks `has_svi` and then requires BOTH
columns `ZCTA` and `RPL_THEMES`. If absent OR either column missing, `svi_lookup` is empty
and `svi_score` is `NA_real_` for all rows. If the staged file uses different column names,
update the `select(ZIP5 = ZCTA, svi_score = RPL_THEMES)` in R/116 SECTION 6.

**Status as of 2026-08-17:** Not staged. `svi_score` is NA across all rows.

## ZIP5-modal imputation tier -- why it can report zero rows (Phase 145)

The `zip5_modal` tier in `approximate_zip9()` (R/utils/utils_address.R) only fires for
encounters that satisfy ALL of the following:
1. ZIP9 is NA (no direct match),
2. match_type is in {interval, most_recent_before} (a covering address record exists), AND
3. ZIP5 is NOT NA (the covering record carries a usable 5-digit ZIP).

In the Hodgkin Lymphoma cohort run of 2026-08-17 (Phase 145-02), `zip5_modal` reported
**zero rows**. The D-02 decision tree applied to the pre-approximation diagnostic table
produced the following three cells:

| Cell | Condition | Count |
|------|-----------|-------|
| (i)  | match_type == "none", ZIP9 NA | 93,029 |
| (ii) | match_type in {interval, most_recent_before}, ZIP9 NA, ZIP5 NA | 157,472 |
| (iii)| match_type in {interval, most_recent_before}, ZIP9 NA, ZIP5 present | 0 |

Cell (iii) = 0 confirms **no code bug**. Cell (ii) = 157,472 > 0 means the early-exit at
`n_to_approx == 0` does NOT fire — the modal lookup IS built — but every approximable row
has ZIP5 = NA (sentinel-nulled by `normalize_zip5()`/`is_sentinel_zip5()`). The modal join
table therefore has no ZIP5 keys to match on, and `zip5_modal` fires zero rows by design.

This is **Branch C (data-driven, no ZIP5 to impute from)**. No code change is required.
The console note emitted by `approximate_zip9()` (Phase 145) will read:
"157472 approximable row(s) found but all have ZIP5 = NA (sentinel-nulled);
zip5_modal tier will report zero rows -- expected, not a defect (Branch C)."

Final zip9_source breakdown for all 1,950,696 encounters (2026-08-17 run):
- zip9_observed: 1,516,469 (77.7%) -- ADI ceiling; see ADI section above
- no_zip5:         275,528 (14.1%)
- none:            158,699  (8.1%)
