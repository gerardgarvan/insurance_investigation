# Phase 146 Discovery — SES Reference File Verification

**Produced by:** 146-01-PLAN.md Task 1 and Task 2
**Date:** 2026-08-17
**Status:** COMPLETE (Tasks 1-2). Findings from 146-RESEARCH.md (researched 2026-08-17)
synthesized with R/116 SECTION 6 code inspection. Live web fetches were not available
from this Windows planning box; all publisher findings come from 146-RESEARCH.md (MEDIUM
confidence) and R/116 code inspection (HIGH confidence). Open items are flagged explicitly.

---

## PART A — Per-Index Source Verification Table

### INDEX 1: SDI — Social Deprivation Index (Robert Graham Center)

**date accessed: 2026-08-17** (via 146-RESEARCH.md, sourced from graham-center.org portal)
**URL:** https://www.graham-center.org/maps-data-tools/social-deprivation-index.html

| Property | Finding |
|----------|---------|
| Publisher | Robert Graham Center (AAFP) |
| Native geography | ZCTA (also county and PCSA — but NOT ZIP5 natively) |
| Release format | CSV portal download (manual click; no CLI/API) |
| Registration required | No registration indicated on the portal page |
| Vintages available | 7 documented releases: 2012, 2015, 2016, 2017, 2018, 2019 (2015–2019 ACS 5-year is the latest confirmed vintage) |
| 2020 vintage | Mentioned in FAQ/marketing copy but NOT confirmed as a distinct separate downloadable release beyond the 7 documented. **OPEN ITEM — confirm which is most recent on the download page.** |
| ZIP5-level release | NO. Published at ZCTA. Most ZIP5 codes have a same-numbered ZCTA, but PO-box-only and single-building ZIPs have none (see D-01 below). |
| Exact column names in download | UNKNOWN from public page metadata. **OPEN ITEM — must be confirmed on download.** Known from academic use to include a ZCTA identifier and an SDI score column. |
| R/116 expected columns | `ZIP5` (character, 5-digit) and `SDI_score` (numeric, 0-100) — verified from R/116 SECTION 6 line 210 |
| Column match verdict | **CANNOT CONFIRM pre-download.** If the file uses `ZCTA5` or `SDI` or other names, update `select(ZIP5, sdi_score = SDI_score)` in R/116 SECTION 6 — do NOT rename the source file. |
| Terms of use | NOT specified on the portal page. **OPEN ITEM — redistribution allowed? May the file live in this repo?** Contact: policy@aafp.org. Label: "unclear — confirm with policy@aafp.org" |
| Attribution required in outputs | Unknown until terms are confirmed. Assume yes pending confirmation. |
| Missing-value encoding | Not documented publicly. **OPEN ITEM — must check on download.** |
| R/116 SECTION 6 probe | `has_sdi` checks `file.exists(SDI_PATH)`, then requires BOTH `ZIP5` AND `SDI_score`. Missing file or missing column → `sdi_lookup` empty, `sdi_score = NA` for all rows. |

**D-01 note (label matters):** Wherever `sdi_score` appears in output sheets, method documentation, or README, state that it is a **ZCTA-level value attached through the ZIP5**. It is NOT a ZIP5-level measure. Required wording: "ZCTA-level SDI score, joined via ZIP5 (ZCTA ≈ ZIP5; PO-box-only and single-building ZIPs have no ZCTA and will not match)."

---

### INDEX 2: SVI — Social Vulnerability Index (CDC/ATSDR)

**date accessed: 2026-08-17** (via 146-RESEARCH.md, sourced from svi.cdc.gov portal)
**URL:** https://svi.cdc.gov/dataDownloads/data-download.html

| Property | Finding |
|----------|---------|
| Publisher | CDC/ATSDR GRASP |
| Native geography | Census tract AND county. ZCTA is available for **2022 only** — NOT for 2020. |
| Release format | CSV and ESRI Geodatabase |
| Registration required | No |
| Vintages available | 2020 (tract + county only); 2022 (tract + county + ZCTA) |
| ZIP5-level release | NO. No ZCTA-level file exists for 2020. |
| **ZCTA 2020 locked fact** | **CDC does NOT publish SVI at ZCTA for 2020.** The file `svi_2020_us_by_zcta.csv` named in Phase 145 D-03 does not exist as a published product. It must be derived. This is a locked fact (CONTEXT.md §3b). |
| Exact column names (2020 tract file) | `FIPS` (11-digit census tract GEOID, character) for geography; `RPL_THEMES` (composite overall SVI percentile, 0–1; −999 for suppressed) for composite score; theme columns `RPL_THEME1` through `RPL_THEME4` |
| R/116 expected columns | `ZCTA` (character, 5-digit) and `RPL_THEMES` — from R/116 SECTION 6 line 274 `select(ZIP5 = ZCTA, svi_score = RPL_THEMES)` |
| Column match verdict for derived file | **Columns must match R/116 as-is.** The derived file must carry `ZCTA` (character, 5-digit) and `RPL_THEMES` (numeric). If different names are used, update R/116 SECTION 6's `select()` — do not rename the source file. |
| Terms of use (CDC/ATSDR) | CDC data is US government public domain. No registration, no redistribution restriction. The **derived file** `svi_2020_zcta_derived.csv` may be committed to this repo freely. |
| Attribution in outputs | CDC/ATSDR SVI 2020 source should be credited in methods. |
| Missing-value encoding | −999 for suppressed tracts (insufficient population). **R/116 already guards:** `svi_score = if_else(svi_score < 0, NA_real_, svi_score)`. The SVI build script must apply the same guard before writing the derived CSV. |
| R/116 SECTION 6 probe | `has_svi` checks `file.exists(SVI_PATH)`. SVI_PATH = `data/reference/svi_2020_us_by_zcta.csv` (Phase 145 name — must be updated to `svi_2020_zcta_derived.csv` in R/116 SECTION 2 and README after 146-02). |

**D-02 decision required (gating 146-02):** Three options — see CONTEXT.md §3b. Recommend **D-02a-i** (findSVI CRAN package, computes SVI at ZCTA from 2020 ACS). Requires Census API key. Build script is `R/117_build_svi_zcta.R` (next free script number — confirmed: no `R/117*` exists; see Task 2 note). If D-02a-i, derived file carries `vintage`, `method`, `source` and NO `svi_areal_coverage` column (no aggregation step). If D-02a-ii (areal mean), it additionally carries `svi_areal_coverage` and `SVI_COVERAGE_FLOOR`. **D-02 is recorded as OPEN — to be decided in 146-02.**

---

### INDEX 3: ADI — Area Deprivation Index (Neighborhood Atlas, UW-Madison)

**date accessed: 2026-08-17** (via 146-RESEARCH.md, sourced from neighborhoodatlas.medicine.wisc.edu)
**URL:** https://www.neighborhoodatlas.medicine.wisc.edu/

| Property | Finding |
|----------|---------|
| Publisher | University of Wisconsin Neighborhood Atlas |
| Native geography | Census block group |
| Release format | CSV (inferred from prior phase documentation and portal) |
| Registration required | YES — must create a login; terms of use must be acknowledged before download |
| Who must register | A named person on the team (Erin, Amy, or Gerard). **OPEN ITEM — who registers?** Record name and date in this file once completed. |
| Vintages available | 2015, 2020, 2021, 2022 |
| ZIP5-level release | NO. Block group only. The site warns against linking ADI to ZIP5/ZCTA/tract. |
| ZIP9-level release | See D-05 below — the critical open question. |
| ADI column name | `ADI_NATRANK` (national percentile rank, integer 1–100) — confirmed from R/116 SECTION 6 candidate list |
| ZIP9 column name | One of `ZIP9`, `zip9`, `ADDRESS_ZIP9`, `zip9_norm`, `GEOID9`, `ZIP_PLUS4` — R/116 auto-detects first match |
| Column match verdict | R/116 probes auto-detect — columns match R/116 as-is if the download uses any of the candidate names |
| Terms of use | Registration-gated data — redistribution is **likely restricted**. **OPEN ITEM — confirm terms before committing the file.** If redistribution is prohibited, add to `.gitignore` and document transfer path: `scp` to `/blue/erin.mobley-hl.bcu/insurance_investigation/data/reference/`. |
| Attribution in outputs | Likely required. Confirm on terms page after registration. |
| Missing-value encoding | Unknown — must check on download. |
| R/116 SECTION 6 probe | `has_adi` checks `file.exists(ADI_PATH)`. ADI_PATH = `data/reference/neighborhood_atlas_block_group_crosswalk.csv`. Auto-detects ZIP9 key + rank column from candidate lists. Missing file → `adi_natrank = NA` for all rows. |

**D-05 (CRITICAL — answers before 146-02 registration task runs):**

*Question:* Does the Neighborhood Atlas download package include a **ZIP+4-keyed file**, or **block group only**?

*Finding from 146-RESEARCH.md:* "The Neighborhood Atlas publishes ADI at census block group, not at ZIP+4 directly. The block-group file is joined via ZIP9 because ZIP9 maps to a block group. The `data/reference/README.md` describes this correctly."

*CONTEXT.md note:* The Atlas's warning names ZIP5/ZCTA/tract linkage specifically. ZIP+4 → block group is a different claim: a ZIP+4 delivery segment usually sits inside one block group, so the warning does not automatically rule it out.

*Resolution:* **block group only.** The Neighborhood Atlas does NOT publish a separate ZIP+4-keyed file. The file IS joinable on ZIP9 (ZIP+4 = 9-digit ZIP) because a ZIP+4 delivery segment typically maps to a single block group, which is why `data/reference/README.md` describes joining on ZIP9. The "block group file" IS the crosswalk — it contains block group FIPS codes and the ADI scores, and is joined to encounter ZIP9 values. **ADI IS achievable this phase** if the download file contains a ZIP9 (9-digit) or ZIP_PLUS4 column alongside the block group FIPS and ADI score.

*However, this must be verified from the actual portal download page by the registering team member.* The 146-02 registration task must confirm that the downloaded file contains one of the candidate ZIP9 column names (`ZIP9`, `zip9`, `ADDRESS_ZIP9`, `zip9_norm`, `GEOID9`, `ZIP_PLUS4`) so R/116's probe gate can detect and join it.

*If the portal confirms block group only (no ZIP+4 column):* ADI cannot be joined on ZIP9 without a ZIP9→block-group crosswalk for which no source has been identified. ADI would then stay at 0% regardless of who registers, and staging it would not be achievable this phase. The 146-02 registration task must include a verification step.

**ADI ceiling (stated before the file arrives, per CONTEXT.md §2 D-03):**
Even once staged, ADI coverage is bounded by the share of encounters with `zip9_source == "zip9_observed"`:
**1,516,469 / 1,950,696 = 77.7%** (from 2026-08-17 corrected run, Phase 145). A join rate of ≤ 77.7% is not a failure; it is the ceiling. The earlier figure of 68.6% (Phase 145 pre-correction) was computed against the 13.3%-inflated denominator and must not be reused.

---

## PART B — Network Availability Finding

**Compute node network — PENDING HiPerGator run**

The safe assumption, per 146-RESEARCH.md and HPC community convention, is that **compute nodes are network-isolated** and **login nodes have outbound HTTPS**.

Verification command (CONTEXT.md §2 verbatim):
```bash
curl -sS -m 10 -o /dev/null -w "%{http_code}\n" https://www.graham-center.org/ || echo "NO NETWORK"
```

Run this from an interactive SLURM session on a compute node. Result: **PENDING HiPerGator run** (this Windows box cannot run this command against HiPerGator compute nodes).

**Practical rule (in effect now, regardless of the PENDING result):** All three reference files are one-time portal downloads. They must be downloaded on a login node (module load R/4.4.2 + curl or browser) or on the Windows workstation, then transferred to HiPerGator via `scp` or direct git commit. **No SLURM download scripts.** This is the safe default regardless of whether compute nodes have outbound network.

---

## PART C — Coverage Expectations Table (for summary workbook §4)

| Index | Geography | Best achievable coverage | Limited by |
|-------|-----------|--------------------------|-----------|
| RUCA | ZIP5 | 77.7% (achieved) | ZIP availability |
| SDI | ZCTA via ZIP5 | ≤ 77.7%, minus ZIP5s with no ZCTA | ZIP availability, then ZCTA match |
| SVI | ZCTA via ZIP5, derived | ≤ 77.7%, minus ZCTA match | Same as above, plus derivation |
| ADI | ZIP9 | ≤ 77.7% | ZIP9 availability only |

22.3% of encounters (434,227) can receive no index at any geography:
- 14.1% (275,528) — matched address record whose ZIP is sentinel-nulled
- 8.1% (158,699) — no address record covering the encounter date

This is a data ceiling, not a reference-file problem. No reference file changes it.

---

## PART D — Script Number Confirmation

**SVI build script number: `R/117_build_svi_zcta.R`**

Script numbers in this repo are sequential in `R/`, not phase numbers:
- `R/115_zip_stability_counts.R` — Phase 139
- `R/116_encounter_ses_index.R` — Phase 144

Confirmed no `R/117*` exists:
```bash
ls R/117* 2>/dev/null || echo "no R/117* found"
```
Result: **no R/117* found** (verified below in Task 2 verification section).

Do NOT use `R/147` — it is not the next free number, will collide when the repo reaches 147, and wrongly implies this is a Phase 147 artifact.

---

## PART E — Consolidated Open Items

| Item | Index | Status | Action Required |
|------|-------|--------|-----------------|
| SDI exact column names | SDI | OPEN — confirm on download | Inspect CSV before staging; update R/116 SECTION 6 `select()` if they differ |
| SDI 2020 vs 2019 vintage | SDI | OPEN | Navigate portal download page; use whichever is most recent confirmed download |
| SDI missing-value encoding | SDI | OPEN | Inspect on download |
| SDI redistribution terms | SDI | OPEN — unclear | Confirm with policy@aafp.org before committing |
| SVI D-02 option decision | SVI | **RESOLVED — D-02a-i (findSVI)** | Decided in 146-02. See PART H below. |
| Census API key availability | SVI | **PENDING REGISTRATION** | Team member registering at api.census.gov (free). Status = pending; must be confirmed on HiPerGator before 146-04 build script runs. |
| ADI D-05 portal verification | ADI | OPEN — gating 146-02 | Registering team member must confirm ZIP+4/ZIP9 column presence in downloaded file |
| ADI who registers | ADI | OPEN | Confirm with Erin/Amy; record name + date here once done |
| ADI redistribution terms | ADI | OPEN | Confirm on terms page after registration; if restricted, add to `.gitignore` and document scp transfer path |
| ADI missing-value encoding | ADI | OPEN | Check on download |
| HiPerGator compute node network | Network | PENDING HiPerGator run | Run curl test from interactive SLURM session; practical rule already set |

---

## PART F — Sentinel-ZIP Frequency Finding (D-04 lever)

**PENDING HiPerGator run** — This box has no PCORnet CSV.

The following R query must be run on HiPerGator against `LDS_ADDRESS_HISTORY_Mailhot_V1.csv` to determine whether the 157,472 sentinel-ZIP rows are dominated by one or two systematic placeholder values (making it a single-fix lever worth raising with the data provider):

```r
addr <- readr::read_csv(file.path(CONFIG$data_dir, "LDS_ADDRESS_HISTORY_Mailhot_V1.csv"),
                        show_col_types = FALSE)
ZIP_COL <- "ADDRESS_ZIP9"
addr %>%
  dplyr::filter(is.na(normalize_zip5(.data[[ZIP_COL]])), !is.na(.data[[ZIP_COL]])) %>%
  dplyr::count(.data[[ZIP_COL]], sort = TRUE) %>%
  head(20) %>%
  print()
```

**Frequency table: PENDING HiPerGator run** (no fabricated counts)

**Decision rule (to apply once counts are available):**
- If one or two placeholder values dominate the 157,472 sentinel rows → **systematic single-source placeholder**. Worth raising with the data provider (Erin/Amy → OneFlorida+). This would raise the ZIP availability ceiling for every index at once — higher-leverage than any single reference file acquisition.
- If counts are scattered across many distinct values → not a single-fix lever. The 22.3% no-index floor holds.

**Context:** CONTEXT.md §0 confirms the 157,472 figure. The 2026-08-17 corrected run shows:
- `no_zip5` (sentinel-nulled): 275,528 (14.1%)
- `none` (no address record): 158,699 (8.1%)
- **Total with no usable ZIP: 434,227 (22.3%)**

The 157,472 figure in CONTEXT.md §4 is an earlier count; the corrected `no_zip5` is 275,528. Both the §4 query and the corrected figure are noted here for completeness.

---

## PART G — Normalizer Disagreement Finding (§5 five-row inconsistency)

**Source:** R/utils/utils_address.R (read for this task)

**Finding:**

The Phase 145 pre-approximation table has five rows at `match_type = "interval"`, `zip9_na = FALSE`, `zip5_na = TRUE` — a valid ZIP9 with no ZIP5. CONTEXT.md §5 explains: since ZIP5 is the first five digits of ZIP9, this should be impossible unless `normalize_zip5()` rejects a sentinel prefix that `normalize_zip9()` accepts.

**Code inspection of R/utils/utils_address.R:**

`normalize_zip9()` (line 41):
```r
normalize_zip9 <- function(zip) {
  z <- str_remove_all(str_trim(zip), "-")
  z <- if_else(str_detect(z, "^[0-9]{8,9}$"), str_pad(z, 9, pad = "0"), NA_character_)
  if_else(str_detect(z, "^[0-9]{9}$"), z, NA_character_)
}
```
→ Accepts any 8-or-9-digit numeric string, left-pads to 9 digits. A string like `"000001234"` (which is a 9-digit number starting with `00000`) IS accepted: `str_detect("000001234", "^[0-9]{8,9}$")` = TRUE → returns `"000001234"`.

`normalize_zip5()` (line 47):
```r
normalize_zip5 <- function(zip9_clean) {
  str_sub(zip9_clean, 1, 5)
}
```
→ Extracts characters 1-5 from the (already validated) zip9_clean. For `"000001234"`, this returns `"00000"`.

`is_sentinel_zip5()` — **CRITICAL FINDING: defined TWICE in utils_address.R** (lines 52-54 and 77-79):

First definition (lines 52-54):
```r
is_sentinel_zip5 <- function(zip5) {
  !is.na(zip5) & str_detect(zip5, "^(\\d)\\1{4}$")
}
```
→ Returns `FALSE` for `NA` input (explicit `!is.na(zip5)` guard).

Second definition (lines 77-79) — **OVERWRITES the first**:
```r
is_sentinel_zip5 <- function(zip5) {
  str_detect(zip5, "^(\\d)\\1{4}$")
}
```
→ `str_detect(NA, ...)` returns `NA` (not `FALSE` and not `TRUE`). The `!is.na()` guard is absent. This second definition is what R actually uses (function redefinition). For `NA` input, it returns `NA` rather than `FALSE`.

**Mechanism producing the five rows:**

In `get_zip9_at_date()` (line 162), the ZIP5 sentinel filter is:
```r
zip5_norm = if_else(is_sentinel_zip5(zip5_norm), NA_character_, zip5_norm)
```
For a ZIP9 like `"000001234"`: `normalize_zip9("000001234")` = `"000001234"` (accepted). `normalize_zip5("000001234")` = `"00000"`. Then `is_sentinel_zip5("00000")` → `str_detect("00000", "^(\\d)\\1{4}$")` = `TRUE` → `zip5_norm` is set to `NA_character_`. ZIP9 is non-NA, ZIP5 is NA. This is exactly the five-row inconsistency.

**Is the fix trivial?** Yes. The sentinel filter on ZIP5 is correct behavior — `"00000"` IS a sentinel and should be NA. But `normalize_zip9()` still accepts a ZIP9 that encodes a sentinel ZIP5 prefix. The inconsistency is by design in the current code, but it creates a small apparent contradiction.

**Proposed one-line fix (NOT applied here — application belongs to a later staging plan or /gsd:quick):**

Option A — Reject ZIP9s whose ZIP5 prefix is sentinel in `normalize_zip9()`:
```r
normalize_zip9 <- function(zip) {
  z <- str_remove_all(str_trim(zip), "-")
  z <- if_else(str_detect(z, "^[0-9]{8,9}$"), str_pad(z, 9, pad = "0"), NA_character_)
  z <- if_else(str_detect(z, "^[0-9]{9}$"), z, NA_character_)
  # Reject ZIP9s with sentinel ZIP5 prefix (00000, 11111, ..., 99999)
  if_else(!is.na(z) & str_detect(str_sub(z, 1, 5), "^(\\d)\\1{4}$"), NA_character_, z)
}
```

Option B — Deduplicate `is_sentinel_zip5()` to remove the second definition (lines 77-79) that drops the `!is.na()` guard. The first definition (lines 52-54) is more correct.

**Verdict:** Fix is trivial (one-line change or removing duplicate). Five rows out of 1.95M changes nothing downstream. Do not apply in this plan; log as a follow-up item for a `/gsd:quick` or the next staging plan.

**`git diff --stat R/utils/utils_address.R`:** No changes — utils_address.R is untouched by this plan (confirmed intent; verification in Task 2 automated check).

---

## PART H — Decisions Recorded in 146-02

### D-02 — How SVI is produced (resolved 2026-08-17)

**Decision: D-02a-i (findSVI)**

**Rationale:** CDC publishes no 2020 ZCTA-level SVI file. The `findSVI` CRAN package computes SVI at ZCTA directly from 2020 ACS variables using the CDC SVI methodology. This removes the entire tract-to-ZCTA aggregation step and its associated error surface (spatial join, partial coverage, coverage floor rules). It is a peer-reviewed CRAN package with a documented method.

Options D-02a-ii (areal mean), D-02b (county-level), and D-02c (drop) were all considered and not selected:
- D-02a-ii was the fallback in case no Census API key was obtainable; a key will be registered at api.census.gov (free), so the fallback is not needed.
- D-02b was rejected as too coarse (county spans very different neighborhoods; same column would hold different-geography values).
- D-02c was rejected as unnecessarily pessimistic given findSVI is available.

**Output contract for D-02a-i:**

| Column | Value |
|--------|-------|
| `ZCTA` | character, 5-digit ZCTA code |
| `RPL_THEMES` | numeric, 0–1 composite SVI percentile (percentile-ranked against ZCTAs) |
| `vintage` | "2020" |
| `method` | "findSVI CRAN package v{version}, geography=zcta, year=2020; percentile-ranked against ZCTAs, NOT comparable to CDC tract SVI" |
| `source` | "ACS 2020 5-year estimates via Census API; findSVI package" |
| `svi_areal_coverage` | **NOT PRESENT** — findSVI does no tract-to-ZCTA aggregation; this column has nothing to measure and must not be added |

**ZCTA-vs-tract ranking caveat (must appear in `method` column and in `data/reference/README.md`):**
findSVI values are percentile-ranked against the national ZCTA universe. CDC's published 2020 SVI values are percentile-ranked against the national census tract universe. Same ACS variables, same CDC methodology, different reference population. A findSVI ZCTA percentile of 0.75 means "more deprived than 75% of US ZCTAs" — not "more deprived than 75% of US tracts." These are not comparable and must not be described as equivalent.

**Census API key status:** Pending registration at api.census.gov (free registration). Must be confirmed present on HiPerGator before the `R/117_build_svi_zcta.R` build script runs in Wave 3/146-04.

**Derived file path:** `data/reference/svi_2020_zcta_derived.csv`
**Build script:** `R/117_build_svi_zcta.R` (next free number — confirmed no R/117* exists)
**Phase 145 README entry:** Must be rewritten in 146-04 to describe a derived file (not a download), with `vintage`, `method`, and `source` columns documented.

---

### ADI Registration Status and Per-Index Commit Verdicts (resolved 2026-08-17)

**ADI registration:** COMPLETED — registered by Gerard, 2026-08-17. Files downloaded: block group file (`US_2024_block_group_adi_v_4_0_1.csv`) AND 23 state-level 9-digit ZIP files (`{STATE}_2024_ADI_9Digit_Zip_v4_0_1.csv`).

**D-05 REVISED FINAL ANSWER (2026-08-17): ZIP9-keyed files exist — ADI IS achievable.**

The initial download was the block group file only (no ZIP9). However, the portal also provides per-state 9-digit ZIP files with column `BENE_ZIP_CD` (= ZIP9). All 23 available state files were downloaded and collated into a single reference file.

**Collated reference file:** `data/reference/neighborhood_atlas_zip9_adi.csv`
- Columns: `ZIP9` (renamed from `BENE_ZIP_CD`), `ADI_NATRANK` (median across block groups per ZIP9; suppression codes → NA)
- Rows: 37,029,488 unique ZIP9 codes; 7,591,693 suppressed/NA
- States: AK, AL, AZ, CA, CO, CT, DC, DE, FL, GA, ID, KY, MI, MN, MT, NJ, NY, OH, PA, RI, VA, WA, WI (23 states)
- Vintage: 2024 (v4.0.1)
- File size: 478MB — **too large for git; added to `.gitignore`**
- Transfer to HiPerGator: `scp data/reference/neighborhood_atlas_zip9_adi.csv {user}@hpg.rc.ufl.edu:/blue/erin.mobley-hl.bcu/insurance_investigation/data/reference/`
- R/116 auto-detects `ZIP9` column (in candidate list) and `ADI_NATRANK` (in candidate list) — no R/116 column-name change needed

**Per-index commit-to-repo verdicts (updated 2026-08-17):**

| Index | File | May commit to repo? | Notes |
|-------|------|--------------------|-----------------------|
| SDI | `data/reference/zip5_sdi_reference.csv` | YES | Confirmed by user. |
| SVI | `data/reference/svi_2020_zcta_derived.csv` | YES — CDC data is US government public domain | N/A |
| ADI | `data/reference/neighborhood_atlas_zip9_adi.csv` | NO — 478MB, gitignored | Transfer via scp; see path above |

**Census API key status:** OBTAINED — registered by Gerard at api.census.gov, 2026-08-17. Must be added to `~/.Renviron` on HiPerGator as `CENSUS_API_KEY=<key>` before `R/117_build_svi_zcta.R` runs (Wave 4 / plan 146-04).

---

## PART I-SVI — SVI Build Script (146-04)

**Script:** `R/117_build_svi_zcta.R`
**Committed:** YES — committed in 146-04 wave.
**Method:** D-02a-i (findSVI CRAN package, `find_svi(year=2020, geography="zcta")`).
**Census API key:** Obtained (api.census.gov), must be present in `~/.Renviron` on HiPerGator as `CENSUS_API_KEY=<key>` before the script runs.

**Output file:** `data/reference/svi_2020_zcta_derived.csv`
**Output status: PENDING HiPerGator run.** This Windows development box cannot execute the findSVI API call. The script must be run on a HiPerGator login node:
```bash
# On HiPerGator login node, after module load R/4.4.2 and renv::restore():
Rscript R/117_build_svi_zcta.R
```
The derived CSV will be committed after the HiPerGator run (Wave 6 / plan 146-06 or equivalent).

**Output columns (once produced):**
| Column | Description |
|--------|-------------|
| `ZCTA` | character, 5-digit, zero-padded |
| `RPL_THEMES` | numeric, 0–1 composite SVI percentile (or NA for suppressed rows) |
| `vintage` | "2020" |
| `method` | findSVI version, geography=zcta, ZCTA-vs-tract ranking caveat |
| `source` | ACS 2020 5-year estimates via Census API; findSVI package |

**No `svi_areal_coverage` column** — findSVI does no tract-to-ZCTA aggregation; this column has nothing to measure and is not present.

**ADI staging:** NOT applicable this phase. D-05 confirmed block group only — no ZIP9 column in the downloaded file. No ADI staging script written. R/116 probe gate continues to degrade ADI to NA for all rows (no code change needed).

---

## PART I — SDI Staging Results (146-03)

### D-01 Label (mandatory wherever sdi_score appears in outputs)

**sdi_score is a ZCTA-level SDI value attached through ZIP5 (ZCTA is approximate; PO-box-only and single-building ZIPs have no ZCTA and do not match) — it is NOT a ZIP5-level measure.**

### SDI File Staged (2026-08-17)

- **File:** `data/reference/zip5_sdi_reference.csv`
- **Columns:** `ZIP5` (character, 5-digit zero-padded), `SDI_score` (numeric)
- **Rows:** 32,989 distinct ZCTAs
- **Source raw file:** `asset_rgc_sdi_2015_through_2019_zcta.csv` (2015–2019 ACS 5-year, Robert Graham Center)
- **Raw key column:** `ZCTA5_FIPS` → renamed `ZIP5`; zero-padded to 5 characters
- **Commit status:** Committed to repo (user-approved 2026-08-17)
- **R/116 SECTION 6 contract:** `select(ZIP5, sdi_score = SDI_score)` — exact column match, no R/116 change required
- **Staging script:** `R/146_stage_sdi_reference.R`

### ZIP5-with-no-ZCTA Haircut Quantification

**Script:** `R/diagnostics/146_sdi_coverage_quantifier.R`

**Result: PENDING HiPerGator run** — this Windows box has no encounter RDS.

The quantification script computes BOTH:
- **(a) Distinct codes:** unique non-NA cohort ZIP5s matched/unmatched against `zip5_sdi_reference.csv`. This is the count of ZIP5 CODES lacking a ZCTA counterpart.
- **(b) Encounter-weighted coverage:** `sum(!is.na(enc$ZIP5) & enc$ZIP5 %in% sdi$ZIP5) / nrow(enc)`. This is the coverage figure the deliverable reports. (a) alone is misleading since a rare ZIP5 code and a high-volume one weigh the same.

The unmatched count from (a)/(b) is the **second haircut** below the 77.7% ceiling (first haircut = no usable ZIP5 at all). Label for the coverage sheet (146-05): **"ZIP5s with no corresponding ZCTA"**.

No fabricated counts. Run `R/diagnostics/146_sdi_coverage_quantifier.R` on HiPerGator after the 146-06 job produces `output/encounter_ses_index_<date>.rds`.
