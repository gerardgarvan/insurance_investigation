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

## ADI -- Area Deprivation Index ZIP9-Keyed File (Phase 146, D-05)

**Path:** `data/reference/neighborhood_atlas_zip9_adi.csv`
**Status as of 2026-08-17:** STAGED (local). File is 478MB and **gitignored**. Transfer to
HiPerGator via `scp data/reference/neighborhood_atlas_zip9_adi.csv {user}@hpg.rc.ufl.edu:/blue/erin.mobley-hl.bcu/insurance_investigation/data/reference/` before running R/116.

**D-05 answer (2026-08-17):** The Neighborhood Atlas portal provides per-state 9-digit ZIP
files (`{STATE}_2024_ADI_9Digit_Zip_v4_0_1.csv`) with column `BENE_ZIP_CD` (= ZIP9). All 23
available state files were downloaded and collated. The file IS joinable on ZIP9 directly.
States: AK, AL, AZ, CA, CO, CT, DC, DE, FL, GA, ID, KY, MI, MN, MT, NJ, NY, OH, PA, RI, VA, WA, WI (23 states).

**Source:** University of Wisconsin Neighborhood Atlas
(https://www.neighborhoodatlas.medicine.wisc.edu/). Registration required. Registered by
Gerard, 2026-08-17. Redistribution status: terms require confirmation; file gitignored.

**Columns (after collation in Phase 146):**
- Join key: `ZIP9` (renamed from `BENE_ZIP_CD`; character, 9-digit)
- Value: `ADI_NATRANK` (median national percentile rank across block groups per ZIP9; suppression codes → NA)
- Rows: 37,029,488 unique ZIP9 codes; vintage 2024 (v4.0.1)

**R/116 probe gate:** SECTION 6 checks `has_adi` (file.exists on `ADI_PATH`) and auto-detects
the ZIP9 key and rank column from candidate lists. `ZIP9` and `ADI_NATRANK` are both in the
candidate lists -- no R/116 column-name change required.

**ADI ceiling (Phase 145, corrected 2026-08-17):** ADI coverage is bounded by the share of
encounters with `zip9_source == "zip9_observed"`.
In the 2026-08-17 corrected run: 1,516,469 / 1,950,696 = **77.7%**. The remaining 22.3% of
encounters (`no_zip5` + `none`) carry no ZIP9 and cannot receive an ADI score. This is a data
ceiling, not a join failure. The ceiling is reported in the "Index Coverage" and "Coverage
Ceilings" sheets of the summary workbook (Phase 146).

### Also consumed by R/115 for block-group accuracy tier (Phase 140, P-03a)

R/115_zip_stability_counts.R SECTION 8 probes `data/reference/neighborhood_atlas_block_group_crosswalk.csv`
(a DIFFERENT file -- the block-group crosswalk, NOT the ZIP9-keyed ADI file above) for its A-06
block-group accuracy tier. That file is NOT staged as of 2026-08-17 (P-03a still pending).
R/116 no longer uses the block-group crosswalk path -- it uses `neighborhood_atlas_zip9_adi.csv`.

## SDI -- Social Deprivation Index (Robert Graham Center) (Phase 146)

**Path:** `data/reference/zip5_sdi_reference.csv`
**Status as of 2026-08-17:** STAGED. 32,989 rows. Committed to repo (user-approved).
Terms confirmation with policy@aafp.org still pending.

**Purpose:** Supplies R/116 SECTION 6/7's `sdi_score` column (encounter-level SES),
joined on ZIP5.

**D-01 label (mandatory wherever `sdi_score` appears in outputs):**
`sdi_score` is a **ZCTA-level SDI value attached through ZIP5** (ZCTA is approximate; PO-box-only
and single-building ZIPs have no ZCTA and will not match). It is NOT a ZIP5-level measure.
Required wording: "ZCTA-level SDI score, joined via ZIP5 (ZCTA ≈ ZIP5; PO-box-only and
single-building ZIPs have no ZCTA and will not match)."

**Source:** Robert Graham Center Social Deprivation Index, vintage 2015–2019 ACS 5-year
(https://www.graham-center.org/maps-data-tools/social-deprivation-index.html).
Portal download -- not obtainable via CLI/API. Raw file: `asset_rgc_sdi_2015_through_2019_zcta.csv`.
Staged by `R/146_stage_sdi_reference.R` (Phase 146-03).

**Columns:**
- Join key: `ZIP5` (character, 5-digit, zero-padded; renamed from raw `ZCTA5_FIPS`)
- Value: `SDI_score` (numeric, 0-100)

**R/116 probe gate:** SECTION 6 checks `has_sdi` (file.exists on `SDI_PATH`) and then
requires BOTH columns `ZIP5` and `SDI_score` to be present. If the file is absent OR either
column is missing, `sdi_lookup` is empty and `sdi_score` is `NA_real_` for all encounter rows.

**ZIP5-with-no-ZCTA coverage haircut:** Not all ZIP5 codes have a same-numbered ZCTA.
PO-box-only and single-building ZIPs will not match against the SDI reference.
The unmatched count (both distinct-code count and encounter-weighted share) is computed by
`R/diagnostics/146_sdi_coverage_quantifier.R` (Phase 146-03). Result: **PENDING HiPerGator run**.
This is the second haircut below the 77.7% ceiling; see the "Coverage Ceilings" sheet of the
summary workbook for context.

## SVI -- CDC SVI 2020 Derived at ZCTA via findSVI (Phase 146, D-02a-i)

**Path:** `data/reference/svi_2020_zcta_derived.csv`
**Status as of 2026-08-17:** PENDING HiPerGator run of `R/117_build_svi_zcta.R`. The build
script is committed; the derived CSV will be produced when R/117 is run on a HiPerGator login
node with the Census API key configured. Committed to repo once produced (CDC data is US
government public domain -- no redistribution restriction).

**Purpose:** Supplies R/116 SECTION 6/7's `svi_score` column, joined on ZIP5 (ZCTA is an
approximation of ZIP5 and differs in edge cases).

**Why a derived file (D-02a-i):** CDC does NOT publish 2020 SVI at ZCTA geography. The
file `svi_2020_us_by_zcta.csv` (named in earlier planning docs) does not exist as a CDC
published product. The `findSVI` CRAN package computes SVI at ZCTA directly from 2020 ACS
variables using the CDC SVI methodology, removing the tract-to-ZCTA aggregation step. This
is a peer-reviewed CRAN package with a documented method. Build script: `R/117_build_svi_zcta.R`.

**ZCTA-vs-tract ranking caveat (D-02a-i; must appear in all outputs using svi_score):**
`RPL_THEMES` is percentile-ranked against the national ZCTA universe. CDC's published 2020 SVI
values are percentile-ranked against the national census tract universe. Same ACS variables, same
CDC methodology, different reference population. A findSVI ZCTA percentile of 0.75 means "more
deprived than 75% of US ZCTAs" -- not "more deprived than 75% of US tracts." These are not
comparable and must not be described as equivalent.

**Columns (D-02a-i output contract):**
- Join key: `ZCTA` (character, 5-digit, zero-padded; carried in R/116 as `ZIP5 = ZCTA`)
- Value: `RPL_THEMES` (numeric, composite SVI percentile, 0-1; −999 suppressed → NA before writing)
- Metadata: `vintage` ("2020"), `method` (findSVI version + ZCTA-vs-tract caveat), `source`
  (ACS 2020 5-year via Census API)
- **NOT present:** `svi_areal_coverage` -- findSVI does no tract-to-ZCTA aggregation; there
  is no aggregation coverage to measure.

**R/116 probe gate:** SECTION 6 checks `has_svi` and then requires BOTH columns `ZCTA` and
`RPL_THEMES`. If absent OR either column missing, `svi_lookup` is empty and `svi_score` is
`NA_real_` for all rows. The `select(ZIP5 = ZCTA, svi_score = RPL_THEMES)` in R/116 SECTION 6
matches the derived file's column names -- no R/116 change required when the CSV is produced.

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
