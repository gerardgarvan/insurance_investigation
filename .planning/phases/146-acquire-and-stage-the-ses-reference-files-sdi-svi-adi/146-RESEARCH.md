# Phase 146: Acquire and Stage the SES Reference Files (SDI, SVI, ADI) — Research

**Researched:** 2026-08-17
**Domain:** SES reference file acquisition, tract-to-ZCTA spatial aggregation, R data pipeline
**Confidence:** MEDIUM (SDI and SVI portals verified; ADI portal partially verified; HiPerGator network policy not officially documented)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- The corrected 77.7% coverage ceiling applies to every ZIP-keyed index. The 68.6% figure from Phase 145 was computed against the 13.3%-inflated denominator and must not be reused.
- Probe-first gating stays in R/116. A missing file degrades to NA, never crashes.
- Phase 144 D-01 and Branch C (modal tier inert) findings stand: no ZIP9 is ever imputed from ZIP5 modal, and no index can exceed 77.7% coverage.
- CDC does NOT publish SVI at ZCTA for 2020. The file `svi_2020_us_by_zcta.csv` named in Phase 145 D-03 does not exist as a published product — it must be derived.
- A derived file is not an acquisition: it requires a committed build script, recorded method, vintage column, and per-ZCTA coverage share.
- Do not silently substitute county-level SVI for tract-derived ZCTA SVI.
- An areal mean without its coverage share must not be published.

### Claude's Discretion
- Which SVI option to implement (D-02a derive by population-weighted areal mean / D-02b county-level / D-02c drop). Context recommends D-02a.
- Whether to use a single ADI vintage (2021) or two (2015 + 2021).
- Script numbering for the SVI build script (R/NN_build_svi_zcta.R).
- Exact threshold for per-ZCTA SVI coverage floor (0.80 suggested as a named constant).

### Deferred Ideas (OUT OF SCOPE)
- Raising the 77.7% ceiling via upstream data provider queries (mentioned in §4 as a future lever, not a Phase 146 deliverable).
- Any ZIP9 imputation beyond what is already coded.
- Re-running the full pipeline to re-verify fixed outputs outside of R/116-specific validation.
</user_constraints>

---

## Summary

Phase 146 must stage three absent SES reference files for `R/116_encounter_ses_index.R`. Each has a distinct acquisition obstacle:

**SDI (Robert Graham Center):** Published as a free CSV at the ZCTA level with no registration required. The most recent vintage is 2019 (using 2015–2019 ACS). A 2020 vintage has been described in marketing copy but is not confirmed as separately downloadable from the seven documented releases (2012, 2015, 2016, 2017, 2018, 2019). Download is a portal click at graham-center.org — no CLI/API. The file must be renamed/restructured to match R/116's expected columns (`ZIP5`, `SDI_score`). The ZIP5=ZCTA approximation introduces a known small mismatch (PO-box-only ZIPs have no ZCTA); the gap must be quantified.

**SVI (CDC/ATSDR):** Confirmed: CDC does NOT publish SVI at ZCTA for 2020. A ZCTA-level file exists only for 2022. For 2020, only census tract and county files are available. The ZCTA file must be derived by aggregating the 2020 tract-level data to ZCTA using a population-weighted crosswalk. The `findSVI` R package (CRAN) computes SVI at ZCTA level directly from ACS data using the CDC methodology, which is a cleaner alternative to aggregating CDC's pre-computed tract rankings. Either approach requires a committed build script. CDC's tract CSV uses `FIPS` (11-digit GEOID) as the geographic key and `RPL_THEMES` as the composite score; `-999` encodes suppressed values.

**ADI (Neighborhood Atlas, UW-Madison):** Requires portal registration — free but mandatory. The Neighborhood Atlas publishes ADI at census block group, not at ZIP+4 directly. The site explicitly warns against linking ADI to ZIP5/ZCTA/tract as a validated approach. The existing `data/reference/README.md` describes joining on ZIP9 via a file that covers block groups, which the ADI file does contain. Available vintages include 2015, 2020, 2021, and 2022. Registration is a named-person action; it must be attributed in `146-DISCOVERY.md`.

**Network on HiPerGator compute nodes:** Official documentation does not explicitly state whether outbound HTTPS is available from compute nodes. The accepted safe assumption based on community practice at HPC centers is that compute nodes are network-restricted; login nodes have outbound access. The CONTEXT.md rule (§1.6) requires establishing this before designing download steps. The practical implication: all three files should be downloaded on a login node or the Windows workstation and committed to the repo, rather than being fetched inside a SLURM script.

**Primary recommendation:** Stage SDI and ADI via manual portal download on a login node; derive SVI using the `findSVI` CRAN package with a committed R build script (`R/147_build_svi_zcta.R` or similar). Do not attempt automated downloads from compute nodes.

---

## Standard Stack

### Core (already in renv)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| tidyverse (dplyr, readr, stringr) | project-pinned | Data wrangling, CSV loading | Project standard |
| vroom | project-pinned | Fast CSV read for reference files | Already used by R/116 |
| openxlsx2 | project-pinned | XLSX output | Already used by R/116 |
| here | project-pinned | Path management | Project convention |

### New (for SVI build script, if D-02a chosen)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| findSVI | current CRAN | Compute SVI at ZCTA level from ACS | D-02a only |
| tidycensus | current CRAN | Pull ACS data for SVI inputs | D-02a only, if findSVI needs it |
| zctaCrosswalk | current CRAN | ZCTA–state relationship files | D-02a only |

**Note:** `findSVI` retrieves census data and computes SVI from first principles at ZCTA level — it does not aggregate CDC's pre-computed tract scores. This is methodologically cleaner than a manual areal-mean aggregation and avoids the tract→ZCTA spatial join entirely. If the team has a Census API key (required by tidycensus), this is the recommended approach. If no API key is available, the fallback is manual tract-level download + HUD USPS crosswalk aggregation.

**Version verification:** Run `npm view` equivalent before installing:
```r
install.packages(c("findSVI", "tidycensus", "zctaCrosswalk"))
renv::snapshot()
```

---

## Architecture Patterns

### Reference File Staging Convention (established by Phase 140/144/145)
```
data/reference/
├── zip5_sdi_reference.csv          # SDI — portal download, renamed
├── neighborhood_atlas_block_group_crosswalk.csv  # ADI — portal download
├── svi_2020_zcta_derived.csv       # SVI — committed build output
└── README.md                       # Updated to reflect derived vs. downloaded
```

### Pattern 1: Probe-First Gate (already implemented in R/116)
**What:** R/116 SECTION 3 checks file existence before loading. Missing = NA for all rows, no crash.
**When to use:** Always — this is the existing pattern and must not be loosened.
**Key:** The probe gate in R/116 checks for `ZIP5` + `SDI_score` (SDI), `ZCTA` + `RPL_THEMES` (SVI), and one of several ZIP9/ADI column name candidates. Column names in the staged files must match what R/116 probes for, or R/116 SECTION 6 must be updated (not the source file).

### Pattern 2: Derived File Convention (Phase 144/145 precedent)
**What:** A file the project computes rather than downloads carries `vintage`, `method`, and `source` columns.
**When to use:** Any reference file that is not a direct download (SVI ZCTA file, centroid crosswalk).
**Example:**
```r
# In the SVI build script, final output must include:
svi_zcta <- svi_zcta_raw |>
  mutate(
    vintage  = "2020",
    method   = "findSVI::find_svi() via 2020 ACS 5-year at ZCTA level",
    source   = "US Census Bureau ACS 2020 5-year, computed via findSVI R package"
  )
readr::write_csv(svi_zcta, here::here("data/reference/svi_2020_zcta_derived.csv"))
```

### Pattern 3: ZIP5=ZCTA Approximation Labeling (Phase 146 D-01)
**What:** SDI is a ZCTA-level measure attached through the ZIP5 identifier. It is NOT a ZIP5-level measure.
**When to use:** Wherever `sdi_score` appears in output sheets, method documentation, or README.
**Required wording:** "ZCTA-level SDI score, joined via ZIP5 (ZCTA ≈ ZIP5; PO-box-only and single-building ZIPs have no ZCTA and will not match)."

### Anti-Patterns to Avoid
- **Downloading files from a SLURM compute node:** Network access is not guaranteed. Stage files on a login node or Windows workstation.
- **Writing a downloader for `svi_2020_us_by_zcta.csv`:** No such CDC file exists for 2020. Compute it.
- **Substituting county-level SVI:** Different measurements; different grain.
- **Publishing an areal mean without the per-ZCTA coverage share (`svi_areal_coverage`):** A mean over 3 of 40 tracts is not the same quantity as one over 40.
- **Describing `sdi_score` as ZIP5-level:** It is ZCTA-level.
- **Targeting coverage above 77.7%:** The ceiling is set by ZIP availability.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ZCTA-level SVI | Manual tract→ZCTA areal-mean aggregation from scratch | `findSVI::find_svi(year=2020, geography="zcta")` | findSVI implements the full CDC methodology at ZCTA; handles ZCTA-state crosswalk internally; peer-reviewed approach |
| Tract→ZCTA crosswalk weights | Custom spatial join with Census shapefiles | HUD USPS crosswalk (if not using findSVI) or `getACS::make_area_xwalk()` with `POP20` | HUD crosswalk is the standard reference; manual spatial joins require TIGER shapefiles and are error-prone |
| ZIP5 normalization | New code | `normalize_zip5_raw()` in `utils_address.R` | Already in the project, already used by R/116 |

**Key insight:** `findSVI` bypasses the tract→ZCTA aggregation problem entirely by computing SVI from ACS data at the ZCTA level directly — the same variables, the same methodology, but at the desired geography from the start. This is methodologically cleaner than aggregating already-ranked tract scores.

---

## Common Pitfalls

### Pitfall 1: CDC Does Not Publish ZCTA-Level SVI for 2020
**What goes wrong:** A script is written to download `svi_2020_us_by_zcta.csv` — the file does not exist; the download fails silently or raises a 404.
**Why it happens:** The CONTEXT.md README entry (Phase 145) described a portal download, but that file is not published. A ZCTA release exists only for 2022.
**How to avoid:** Use `findSVI` to compute from ACS, OR download the 2020 tract-level CSV and aggregate.
**Warning signs:** Any script with a URL pointing to a ZCTA-level SVI 2020 file.

### Pitfall 2: SDI Column Names May Not Match R/116's Expectations
**What goes wrong:** The downloaded SDI CSV uses different column names (e.g., `ZCTA5`, `sdi`, `SDI_RAW`) and R/116 silently falls back to empty `sdi_lookup`.
**Why it happens:** R/116 SECTION 6 hard-codes `"ZIP5"` and `"SDI_score"` as the expected column names. If the download uses other names, the probe prints a warning but `sdi_score` stays NA for all rows.
**How to avoid:** Inspect the downloaded CSV column names before staging. If they differ, update the `select(ZIP5, sdi_score = SDI_score)` call in R/116 SECTION 6 — do not rename the source file.
**Warning signs:** Console output "SDI: file found but expected columns ZIP5/SDI_score not present."

### Pitfall 3: ADI Joins on ZIP9 Not ZIP5 — Coverage is Bounded at 77.7%
**What goes wrong:** ADI shows, say, 60% coverage and is read as a join failure; team spends time debugging.
**Why it happens:** ADI joins on ZIP9. Only 77.7% of encounters have an observed ZIP9 (`zip9_observed`). A join rate of ≤77.7% is not a failure; it is the ceiling.
**How to avoid:** State the ceiling in `data/reference/README.md` and the coverage sheet BEFORE staging the file, so a 0-to-≤77.7% jump is expected, not alarming.
**Warning signs:** Coverage reported as exactly 77.7% would be suspicious (perfect join); coverage near 70-77% is expected.

### Pitfall 4: SVI `RPL_THEMES` = -999 is Suppressed, Not Zero
**What goes wrong:** `-999` is treated as a very low vulnerability score instead of missing.
**Why it happens:** CDC uses `-999` to suppress tracts with insufficient population. R/116 already guards: `svi_score = if_else(svi_score < 0, NA_real_, svi_score)`. The SVI build script must apply the same guard before writing the derived file, so downstream consumers that skip R/116's guard are protected.
**How to avoid:** In the build script, `mutate(RPL_THEMES = if_else(RPL_THEMES < 0, NA_real_, RPL_THEMES))` before writing.

### Pitfall 5: HiPerGator Compute Nodes May Have No Outbound Network
**What goes wrong:** A SLURM script runs `curl` or `download.file()` to fetch reference files; the job silently fails or hangs.
**Why it happens:** Many HPC clusters block outbound internet from compute nodes for security reasons. HiPerGator's official policy is not published in the docs reviewed, but the convention is to treat compute nodes as network-isolated.
**How to avoid:** Perform all downloads on a login node or Windows workstation. Commit the files to the repo (if terms of use permit). If files cannot be committed, document the transfer path (e.g., `scp` to HiPerGator scratch).

### Pitfall 6: SDI ZCTA ≠ ZIP5 for PO-Box-Only ZIPs
**What goes wrong:** Cohort ZIP5s that are PO-box-only (e.g., 00501 for IRS Holtsville) have no corresponding ZCTA and will not match any SDI row, silently inflating missingness.
**Why it happens:** ZCTAs are built from address-range ZIPs; PO-box-only ZIP codes are not mapped to a ZCTA.
**How to avoid:** After staging, run the quantification query from CONTEXT.md §3a (`sum(zips %in% sdi$ZIP5)` / `sum(!zips %in% sdi$ZIP5)`) and record the unmatched count in the coverage sheet labeled "ZIP5s with no corresponding ZCTA."

### Pitfall 7: ADI's Warning About Non-Block-Group Use
**What goes wrong:** The Neighborhood Atlas site warns that "linking ADI to other geographic units (including 5-digit ZIP codes, ZCTA, census tracts and others) is not a validated approach."
**Why it happens:** ADI is designed for block-group linkage. The Phase 144 design uses ZIP9 (which maps 1:1 to a block group), which is the supported approach. But anyone reading ADI documentation may question it.
**How to avoid:** Document in the README and coverage sheet that R/116 joins on ZIP9 (block-group granularity), not ZIP5 — this is the validated linkage unit.

---

## Discovery Findings by Source

### SDI — Robert Graham Center

| Property | Finding | Confidence |
|----------|---------|------------|
| Publisher | Robert Graham Center (AAFP) | HIGH |
| URL | https://www.graham-center.org/maps-data-tools/social-deprivation-index.html | HIGH |
| Native geography | ZCTA (also county and PCSA) | HIGH |
| Release format | CSV download | HIGH |
| Registration required | Not indicated — no registration requirement described | MEDIUM |
| Latest confirmed vintage | 2019 (2015–2019 ACS 5-year) | MEDIUM |
| 2020 vintage | Described in FAQ copy but not confirmed as a separate portal download distinct from the 7 documented releases | LOW |
| Terms of use | Not specified on the page; contact policy@aafp.org for redistribution clarification | LOW |
| Exact column names | Not published in page metadata; known from academic use to include ZCTA identifier and SDI score columns. Must be confirmed on download | LOW |
| R/116 expected columns | `ZIP5` (character, 5-digit) and `SDI_score` (numeric, 0-100) per R/116 SECTION 6 line 210 | HIGH (from code) |
| Missing-value encoding | Not documented publicly — must check on download | LOW |
| Redistribution in repo | Unknown — must confirm with RGC before committing | LOW |

**Action:** Download from portal (no registration); inspect column names; if columns differ from `ZIP5`/`SDI_score`, update R/116 SECTION 6's `select()` call. Check terms before committing the file.

### SVI — CDC/ATSDR

| Property | Finding | Confidence |
|----------|---------|------------|
| Publisher | CDC/ATSDR GRASP | HIGH |
| URL | https://svi.cdc.gov/dataDownloads/data-download.html | HIGH |
| Native geography | Census tract AND county — confirmed. ZCTA available for 2022 ONLY | HIGH |
| 2020 file geography | Tract and county only. No ZCTA file for 2020 | HIGH |
| Release format | CSV and ESRI Geodatabase | HIGH |
| Registration required | No | HIGH |
| Vintage available | 2020 tract-level confirmed | HIGH |
| Tract key column | `FIPS` (11-digit census tract GEOID, character) | MEDIUM |
| Composite score column | `RPL_THEMES` (0–1 percentile rank; -999 for suppressed) | HIGH |
| Theme columns | `RPL_THEME1` through `RPL_THEME4` | MEDIUM |
| Missing-value encoding | -999 for suppressed tracts. R/116 already guards: `if_else(svi_score < 0, NA_real_, svi_score)` | HIGH |
| ZCTA derivation method | `findSVI::find_svi(year=2020, geography="zcta")` — computes from ACS, not aggregates tract rankings | MEDIUM |
| findSVI CRAN availability | Available; version confirmed on CRAN | HIGH |

**Action (D-02a):** Install `findSVI` via `renv`; write `R/1NN_build_svi_zcta.R` that calls `find_svi(year=2020, geography="zcta", state="FL")` (or US-wide, then filter), writes `data/reference/svi_2020_zcta_derived.csv` with `vintage`, `method`, `source`, and per-ZCTA `svi_areal_coverage` columns; rewrite the SVI section of `data/reference/README.md` to describe a derived file.

**Important:** `findSVI` requires a Census API key (set via `tidycensus::census_api_key()`). If no key is available, fall back to manual CDC tract download + HUD USPS crosswalk aggregation. The Census API key must be available on the machine running the build script.

### ADI — Neighborhood Atlas (UW-Madison)

| Property | Finding | Confidence |
|----------|---------|------------|
| Publisher | University of Wisconsin Neighborhood Atlas | HIGH |
| URL | https://www.neighborhoodatlas.medicine.wisc.edu/ | HIGH |
| Native geography | Census block group | HIGH |
| ZIP+4 / ZIP9 file | Not a separate ZIP+4 file. The block-group file is joined via ZIP9 because ZIP9 maps to a block group. The `data/reference/README.md` describes this correctly | MEDIUM |
| Release format | CSV (inferred from prior phase documentation and portal page) | MEDIUM |
| Registration required | YES — must create a login; terms of use must be acknowledged | HIGH |
| Who must register | A named person on the team (Erin, Amy, or Gerard); must be recorded in `146-DISCOVERY.md` | HIGH |
| Vintages available | 2015, 2020, 2021, 2022 confirmed in search results | MEDIUM |
| Recommended vintage | 2021 (single vintage, simpler) or 2015+2021 (two vintage, defensible) — per README Phase 140 guidance | MEDIUM |
| ADI column name | `ADI_NATRANK` (national rank, integer 1–100) — confirmed by R/116 SECTION 6 candidate list | HIGH (from code) |
| ZIP9 column name | One of: `ZIP9`, `zip9`, `ADDRESS_ZIP9`, `zip9_norm`, `GEOID9`, `ZIP_PLUS4` — R/116 auto-detects first match | HIGH (from code) |
| Redistribution in repo | Likely restricted by terms of use (registration-gated data) — must confirm on terms page before committing | LOW |
| ADI ceiling | 77.7% — the share with `zip9_source == "zip9_observed"`. Even once staged, cannot exceed this | HIGH |
| Non-block-group linking warning | Neighborhood Atlas warns against linking ADI to non-block-group geographies. ZIP9 join is the validated approach (Phase 144 design choice) | HIGH |

**Action:** A team member must register at neighborhoodatlas.medicine.wisc.edu, accept terms, download the file, and record registration date and name in `146-DISCOVERY.md`. If redistribution is prohibited, the file must NOT be committed to git; instead document the transfer path (HiPerGator scratch, `.gitignore` entry).

---

## HiPerGator Network Availability

| Question | Finding | Confidence |
|----------|---------|------------|
| Outbound HTTPS from compute nodes | Official docs do not explicitly state policy. HPC community convention: compute nodes are typically network-isolated | LOW |
| Outbound HTTPS from login nodes | Yes — login nodes have internet access | HIGH |
| Download approach | Stage files on login node or Windows workstation; do not fetch in SLURM scripts | MEDIUM |

**Practical rule for this phase:** All three files are one-time portal downloads. Perform them interactively on a login node (`module load R/4.4.2` + `curl` or browser) or on the Windows workstation, then transfer to HiPerGator via `scp` or direct git commit. No SLURM download scripts.

**Verification command (per CONTEXT.md §2):**
```bash
curl -sS -m 10 -o /dev/null -w "%{http_code}\n" https://www.graham-center.org/ || echo "NO NETWORK"
```
Run this from a compute node inside an interactive SLURM session to confirm policy. Record result in `146-DISCOVERY.md`.

---

## Tract→ZCTA Crosswalk (if D-02a via manual aggregation, not findSVI)

If `findSVI` is not used (e.g., no Census API key), the standard method for aggregating CDC tract SVI to ZCTA is:

1. **Crosswalk source:** HUD USPS ZIP Code Crosswalk (https://www.huduser.gov/portal/datasets/usps_crosswalk.html) — tract-to-ZIP quarterly files. Use a 2020 or 2021 Q4 release to match SVI 2020.
2. **Population weights:** Residential address ratio from the HUD file (`RES_RATIO` column) — multiply tract SVI value by `RES_RATIO`, sum within ZCTA.
3. **Coverage share:** For each ZCTA, record the sum of `RES_RATIO` for contributing tracts as `svi_areal_coverage`. Tracts below a named coverage floor (0.80 suggested) receive `NA` for `svi_score`.
4. **Alternative:** `getACS::make_area_xwalk()` with `weight_col = "POP20"` from the 2020 decennial census block-level population counts. Requires `getACS` CRAN package.

**Standard for this project:** If findSVI works, use it. If not, use HUD USPS crosswalk with `RES_RATIO` weights.

---

## SVI Build Script Requirements (D-02a)

If D-02a is chosen, the build script `R/1NN_build_svi_zcta.R` must:

1. Load `findSVI` (or HUD crosswalk + CDC tract CSV).
2. Compute or derive `RPL_THEMES` at ZCTA level.
3. Apply `if_else(RPL_THEMES < 0, NA_real_, RPL_THEMES)` to handle -999 suppression.
4. Compute `svi_areal_coverage` per ZCTA (share of ZCTA population represented by contributing tracts). Apply `NA` below the named floor constant (suggest `SVI_COVERAGE_FLOOR <- 0.80`).
5. Add `vintage`, `method`, `source` columns.
6. Write to `data/reference/svi_2020_zcta_derived.csv`.
7. The output file must have columns: `ZCTA` (character, 5-digit) and `RPL_THEMES` (numeric) so R/116's existing probe gate (`select(ZIP5 = ZCTA, svi_score = RPL_THEMES)`) works without modification to R/116.

---

## Coverage Expectations Table (for summary workbook §4)

| Index | Geography | Best achievable coverage | Limited by |
|-------|-----------|--------------------------|-----------|
| RUCA | ZIP5 | 77.7% (achieved) | ZIP availability |
| SDI | ZCTA via ZIP5 | ≤ 77.7%, minus ZIP5s with no ZCTA | ZIP availability, then ZCTA match |
| SVI | ZCTA via ZIP5, derived | ≤ 77.7%, minus ZCTA match, minus tracts below coverage floor | Same as above, plus derivation coverage |
| ADI | ZIP9 | ≤ 77.7% | ZIP9 availability only |

22.3% of encounters (434,227) — 14.1% sentinel-ZIP + 8.1% no address record — can receive no index at any geography. This is a data ceiling, not a reference-file problem.

---

## README Updates Required

The `data/reference/README.md` SVI section currently describes a portal download (`svi_2020_us_by_zcta.csv`). After Phase 146:

1. The SVI section must be rewritten to describe a **derived file** (`svi_2020_zcta_derived.csv`) with `vintage`, `method`, `source`, and `svi_areal_coverage` columns.
2. The ADI ceiling must be corrected from 68.6% to **77.7%** everywhere it appears.
3. The SDI section should note that `sdi_score` is a **ZCTA-level value attached through ZIP5**, not a ZIP5-level measure.

---

## Project Constraints (from CLAUDE.md)

- **Environment:** RStudio on HiPerGator — `module load R/4.4.2` in every SLURM script. No downloads inside SLURM.
- **Stack:** tidyverse (dplyr, readr, stringr), vroom for loading, renv for packages. New packages (`findSVI`, `tidycensus`) must be installed interactively and snapshotted via `renv::snapshot()`.
- **Paths:** Use `here()` and `file.path()` — no `setwd()` or absolute paths.
- **Column types:** Specify critical column types (`col_types`) when reading reference CSVs with vroom/readr. ZIP codes and FIPS codes must be read as character.
- **No data.table:** Use dplyr throughout the build script.
- **Named predicates:** The build script need not use `has_*` predicates (it's not a cohort filter), but should use named constants (e.g., `SVI_COVERAGE_FLOOR <- 0.80`) rather than magic numbers.
- **No install inside SLURM:** If the build script needs findSVI, install it interactively first.

---

## Open Questions

1. **SDI exact column names on download**
   - What we know: The portal provides CSVs described as containing ZCTA identifier + SDI raw + SDI score.
   - What's unclear: Whether the column names are exactly `ZIP5` and `SDI_score` or differ (e.g., `ZCTA5`, `SDI`).
   - Recommendation: Download the file and inspect column names before staging. Update R/116 SECTION 6 `select()` if needed.

2. **SDI 2020 vintage availability**
   - What we know: Seven releases exist (2012–2019); a 2020 vintage is mentioned in FAQ copy.
   - What's unclear: Whether 2020 is a distinct download or the 2019 is the current release.
   - Recommendation: Navigate to the portal download page; use whichever is most recent and confirmed downloadable.

3. **SDI and ADI redistribution rights**
   - What we know: Neither publisher explicitly states redistribution terms on the public page.
   - What's unclear: Whether the files may be committed to this repo (even private).
   - Recommendation: Check terms before committing. If restricted, add to `.gitignore`, commit a `data/reference/.gitkeep`, and document the transfer path.

4. **HiPerGator compute node network access**
   - What we know: Official docs don't state policy; HPC convention is compute nodes are isolated.
   - What's unclear: Whether UF HiPerGator specifically blocks outbound HTTPS from compute nodes.
   - Recommendation: Run the curl test from CONTEXT.md §2 on a login node AND a compute node; record both results in `146-DISCOVERY.md`.

5. **Census API key availability**
   - What we know: `findSVI` requires a Census API key via tidycensus.
   - What's unclear: Whether the team has a key registered on HiPerGator.
   - Recommendation: The plan should include a step to confirm key availability before committing to the findSVI path. Fallback: manual CDC tract download + HUD USPS crosswalk aggregation.

6. **ADI who registers**
   - What we know: A named person must register; the registration date must be recorded.
   - What's unclear: Whether Erin or Amy has an existing account.
   - Recommendation: Confirm with team; the plan should flag this as a human-action step with a named owner.

---

## Sources

### Primary (HIGH confidence)
- R/116_encounter_ses_index.R (lines 65-290) — probe gate logic, expected column names, join keys, -999 guard
- data/reference/README.md — staged file contracts, existing acquisition status, ADI ceiling = 77.7%
- 146-CONTEXT.md — locked decisions, rules for the planner, anti-patterns
- https://svi.cdc.gov/dataDownloads/data-download.html — ZCTA available for 2022 only, not 2020; CSV format confirmed

### Secondary (MEDIUM confidence)
- https://www.graham-center.org/maps-data-tools/social-deprivation-index.html — SDI portal, CSV format, no registration, ~7 vintages
- https://www.neighborhoodatlas.medicine.wisc.edu/ — ADI registration required, login mandatory, block-group geography, ZIP+4 not a separate validated product
- https://cran.r-project.org/web/packages/findSVI/vignettes/findSVI.html — findSVI computes ZCTA-level SVI from ACS directly (not by aggregating tract rankings)
- https://www.huduser.gov/portal/datasets/usps_crosswalk.html — HUD USPS tract-to-ZIP crosswalk for fallback aggregation

### Tertiary (LOW confidence)
- WebSearch results on HiPerGator network access — no official documentation found; community convention applied
- WebSearch results on SDI column names — not verified from official source; must be confirmed on download

---

## Metadata

**Confidence breakdown:**
- SDI acquisition: MEDIUM — portal confirmed, column names unverified, terms unclear
- SVI derivation (findSVI): MEDIUM — package confirmed on CRAN, Census API key availability unknown
- ADI acquisition: MEDIUM — registration requirement confirmed, exact column names confirmed from R/116 code
- HiPerGator network: LOW — no official policy found; HPC convention applied
- Coverage ceilings: HIGH — computed from actual run data, documented in README

**Research date:** 2026-08-17
**Valid until:** 2026-09-17 (stable — SDI/SVI/ADI portals change infrequently)
