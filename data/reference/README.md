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

> **[2026-08-17] Superseded by Phase 147 — see 147-DISCOVERY.md.** The 77.7% ceiling was
> computed when `get_zip9_at_date()` ignored `ADDRESS_ZIP5`. After the Phase 147 fix, RUCA
> coverage rises because RUCA joins on ZIP5. Updated figures: see 147-DISCOVERY.md §4.

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

> **[2026-08-17] Superseded by Phase 147 — see 147-DISCOVERY.md.** The zero-row figure was
> an artefact of `ADDRESS_ZIP5` never being read, not a data characteristic. After the Phase 147
> fix, 18,731 records provide a ZIP5 for Tier 2 for the first time; see 147-DISCOVERY.md §4 for
> whether `zip5_modal` fired or those rows landed in `zip5_no_zip9`.
> The "Branch C" console message was emitted because all approx candidates had ZIP5 = NA by
> construction. That console message has been corrected in utils_address.R. Updated figures:
> see 147-DISCOVERY.md §4.

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

Final zip9_source breakdown for all 1,950,696 encounters (2026-08-19 run, post-Phase-148):

| zip9_source | encounters | share |
|---|---|---|
| `zip9_observed` | 1,516,469 | 77.7% |
| `zip5_modal` | 198,768 | 10.2% |
| `zip5_representative` | 47,036 | 2.4% |
| `zip5_no_zip9` | 12,782 | 0.7% |
| `no_zip5` | 16,942 | 0.9% |
| `none` | 158,699 | 8.1% |

---

## ZIP5-Level ADI Summary (Phase 148, D-02 Route B)

**Path:** `data/reference/zip5_adi_summary.csv`
**Status as of 2026-08-19:** STAGED on HiPerGator at
`/blue/erin.mobley-hl.bcu/insurance_investigation/data/reference/zip5_adi_summary.csv`.
File is derived from `neighborhood_atlas_zip9_adi.csv` (gitignored, 478 MB); output file
is also gitignored (derived artefact).
**Builder:** `R/118_build_centroid_crosswalk.R`
**Vintage:** Neighborhood Atlas 2024 v4.0.1

**Columns:**
- `ZIP5` — character(5), zero-padded; primary join key for R/116
- `adi_natrank_median` — median ADI national rank across all ZIP9s within this ZIP5 (na.rm=TRUE)
- `adi_natrank_p25`, `adi_natrank_p75` — IQR; wide IQR indicates intra-ZIP5 heterogeneity
- `n_zip9_in_zip5` — total ZIP9 rows from the Atlas for this ZIP5 (before NA suppression)
- `n_zip9_with_adi` — ZIP9 rows with non-suppressed ADI_NATRANK
- `vintage`, `method`, `source` — provenance

**R/116 integration:**
- Loaded when `file.exists(ADI_SUMMARY_PATH)` — auto-detected; no code change needed to activate
- Joined on `ZIP5` after the modal-tier step; adds `adi_natrank_zip5_median` column to `encounter_ses`
- Rows resolved via this join are classified `zip9_source = "zip5_representative"` — distinct
  from `adi_natrank` (ZIP9-level) and never coalesced with it

**D-04 coverage figures (Phase 148, 2026-08-19 HiPerGator re-run):**
- **(a) ZIP5s in summary:** 20,950
- **(b) Records resolved of 36,953 needing Tier 3:** 30,725 (83.2%) — lead figure
- **(c) Encounters with zip5_representative in final output:** 47,036

**Note on rural degradation:** Route B does not compute `distance_m` — rural heterogeneity
is visible through IQR width (adi_natrank_p75 - adi_natrank_p25) rather than a distance
cutoff. See 148-DISCOVERY.md §5 for details.

**Source:** University of Wisconsin Neighborhood Atlas
(https://www.neighborhoodatlas.medicine.wisc.edu/). Registration required before downloading.

## surveillance_codeset.xlsx
- Used by: load_surveillance_codeset(), load_lab_analytes(), load_modality_lookup() (R/utils/utils_surveillance.R); Phase 158 and Phase 159
- Sheets (Phase 159, in order): KEY (column definitions), Analysis_Codeset (data; 167 rows at 2026-09-24), Lab_Analytes (analyte LOINC/CPT codes; 189 rows, LA001–LA189), Lab_Analytes_Excluded (documentation only; 43 rows; not read by code), Modalities (column prefix lookup; 14 rows)
- Rows: 167 at 2026-09-24 = SC001–SC108 from Phase 158 (unchanged) + SC109–SC167 Phase 159 lab modality rows
- New modalities added (Phase 159): BMP, CMP, LIPID, LFT, KIDNEY
- Key: codeset_row_id (SC001..), unique and never reused; new rows take the next number
- type_filter: bare PX_TYPE/DX_TYPE value (CH, 10, 09); blank for LAB_RESULT_CM; blank for analyte rule rows
- match: exact | prefix | component_all_same_day | analyte_all_same_day | analyte_min_same_day
- tier: primary | sensitivity (tier/modality edits flow to outputs with no code change, L-4)
- submodality: TSH / Free T4 on Thyroid function rows only (D-21); blank for lab modality rows
- plausibility: "verify" on rows still to be confirmed (D-12)
- min_analyte_count: integer as text; set only on analyte_min_same_day rows; blank elsewhere; must be >= 1 and < the number of listed analytes
- Source: desk audit of VariableDetails.xlsx "Surveillance Strategy" sheet (Phase 158) + delivered Phase 159 codeset, 2026-09-24
- **Phase 160 edits (2026-09-25):**
  - Modalities sheet: new `eligible_sex` column (blank / F / M). Set to `F` on Mammogram and Breast MRI; blank for all other modalities. Adds female-denominator view columns for those two modalities; never changes all-patient figures. Read by `load_modality_lookup()` and exposed via `modality_eligible_sex()`.
  - Analysis_Codeset SC132 (CMP sensitivity rule): `min_analyte_count` raised 7 → 11 (11 of 14 analytes required). This is the CMP sensitivity threshold as of Phase 160; it cuts out all 8-of-14 (BMP-equivalent) and 9-of-14 days. A full BMP (8 analytes) can no longer qualify as a CMP. R/88 invariant: threshold > 8.
  - Lab_Analytes: LA190 (2026-3, CO2), LA191 (1752-5, ALBUMIN), and LA192 (45066-8, CREATININE) added from the A3 missing-analyte diagnostic (see review_note column). These are non-standard LOINCs used by one source to report serum CO2, serum albumin, and creatinine. 1756-6 (CSF/serum albumin ratio) was reviewed and deliberately not added.

## Phase 160 output artifacts: A3_missing_analyte, Codeset_summary, eligible_sex columns

### A3_missing_analyte sheet

Produced on every run of R/147 via `summarise_missing_analyte()` + `rank_candidate_codes()`.

**INTERNAL workbook** (stays on HiPerGator — not for external release):
- Block 1: BMP/CMP near-miss days broken out by which analyte is missing (raw LOINC codes and names, unsuppressed patient-date counts)
- Block 1b: year-level breakdown of those near-miss days
- Block 2: top lift candidates for the analyte gap (LOINC/RAW code, `top_raw_name`, `code_source`, `in_excluded` flag for Lab_Analytes_Excluded membership, `lift` rank)

**Release workbook** (shareable):
- Same blocks, but raw-only candidates (code_source == "RAW") are dropped
- Raw code and raw name columns are removed; only LOINC-level codes remain
- Patient-date counts are suppressed to <= 10 threshold (same `suppress_small()` rule as all other release sheets)

### Codeset_summary sheet

Auto-generated each run by `build_codeset_summary()`. **Replaces `code_mapping_summary.xlsx`** (do not maintain that file manually going forward).

Contents:
- Codes per modality x tier x match type, with min_analyte_count thresholds where applicable
- Codes per analyte: how many were actually observed in this data run vs. how many are in Lab_Analytes

The Codeset_summary sheet appears in both INTERNAL and release workbooks; it contains only codeset metadata (no patient counts), so no suppression is applied.

### eligible_sex denominators (Mammogram and Breast MRI)

`modality_eligible_sex()` reads the `eligible_sex` column from the Modalities sheet and returns a named vector (modality -> "" / "F" / "M"). For modalities with a non-blank eligible_sex:

- `compute_eligible_modality_stats()` adds `n_patients_eligible_sex` and `n_dates_eligible_sex` columns alongside the standard all-patient columns. These are the female (or male) denominators: e.g. Mammogram's `n_patients_F` = distinct female patients with >= 1 mammogram.
- `suppress_eligible_columns()` applies **complementary suppression** to the eligible/other-sex column pair: if either the eligible-sex count or the complement (other-sex count = all-patient minus eligible) falls in the 1–10 suppression range, BOTH columns are withheld from the release workbook. This prevents back-calculation of a small cell from a published total.
- The all-patient columns (B sheet primary and C sheet sensitivity) are NEVER changed by this logic. The L-5 guard (`stopifnot("L-5: eligibility must not change the all-patient B columns")`) enforces this invariant.

## lab_code_crosswalk.xlsx
- Path: data/reference/lab_code_crosswalk.xlsx
- Status as of 2026-09-24: NOT YET STAGED (expected; to be placed by user)
- Not read by any code — provenance documentation only
- Purpose: LOINC 2.83 crosswalk (run 2026-09-22) used as the dictionary for Lab_Analytes analyte code selection
- Sheet: MASTER; analytes selected by exact LOINC component match + D-12 specimen allowlist (not by grouping flags — 159 D-21)
- Specimens used: Ser/Plas, Ser, Plas, Ser/Plas/Bld, Bld, BldV (blood); urine only for URINE_PROTEIN and URINE_ALBUMIN_CREATININE_RATIO (KIDNEY sensitivity)
- Exclusion categories recorded in Lab_Analytes_Excluded sheet: test strip/glucometer, challenge "Stdy" timepoints, pCO2, electrophoresis fractions, qualitative results, percentage results, interpretations, calculated blood-gas CO2, calculated triglyceride, timed serum albumin
- Single-analyte CPT codes from the CPT rows are PROCEDURES members (cdm_table = PROCEDURES, type_filter = CH)
