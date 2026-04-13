# Phase 21: Generalize Phase 19 to All Sources - Context

**Gathered:** 2026-04-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Extend the Phase 19 UF-specific payer missingness investigation to ALL partner sites (AMS, UMI, FLM, VRT, UFH) in the OneFlorida+ HL cohort. Produce a standalone diagnostic R script that performs the same 5 missingness breakdowns as Phase 19 but grouped by SOURCE, with a cross-site summary CSV for head-to-head comparison. Output is CSV files to `output/tables/`.

</domain>

<decisions>
## Implementation Decisions

### Cross-site Comparison
- **D-01:** Single combined CSVs with a SOURCE column — all sites in the same file per breakdown type (not separate per-site CSVs)
- **D-02:** Include an additional cross-site summary CSV with one row per site showing overall missingness rates, enabling head-to-head comparison at a glance
- **D-03:** Numbers only in the summary — no severity flags or interpretation columns. Let the user interpret the rates

### Analysis Scope
- **D-04:** Same 5 breakdowns as Phase 19: raw value distribution, by year, by encounter type, year×type crosstab, raw vs harmonized — just add SOURCE as a grouping dimension
- **D-05:** HL cohort patients only (same population as Phase 19). Do not analyze all patients per site

### Script Design
- **D-06:** New standalone script (next available number, e.g., `R/20_all_source_missingness.R`). Phase 19's `R/18_uf_insurance_missingness.R` stays unchanged
- **D-07:** Single grouped pass using `dplyr::group_by(SOURCE)` for all breakdowns — no site-by-site loop. Natural tidyverse pattern
- **D-08:** Reuse Phase 19 missingness definition: NA, empty string, NI, UN, OT, 99, 9999 (from PAYER_MAPPING$sentinel_values + PAYER_MAPPING$unavailable_codes)

### Output Structure
- **D-09:** CSV file naming uses `all_source_` prefix, mirroring Phase 19's `uf_` prefix: `all_source_payer_raw_value_distribution.csv`, `all_source_payer_missingness_by_year.csv`, etc.
- **D-10:** Console output: per-site summary of overall missingness rates plus a final cross-site comparison. Enough to review in HiPerGator terminal without opening CSVs
- **D-11:** CSV output to `output/tables/` — consistent with existing pipeline pattern

### Claude's Discretion
- Exact script number (next available after existing scripts)
- Cross-site summary CSV column structure and exact columns
- Console output formatting and which per-site stats to highlight
- How to handle sites with very few encounters (if any)
- Whether to include an "ALL" aggregate row in each breakdown CSV

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 19 reference implementation
- `R/18_uf_insurance_missingness.R` — Phase 19 UF-specific script to generalize. Contains the 5 breakdown patterns (Sections 3-7), missingness flag logic (Section 2), and console summary format (Section 8)
- `.planning/phases/19-investigate-insurance-missingness-source-uf-specifically/19-CONTEXT.md` — Phase 19 decisions D-01 through D-14, especially missingness definition (D-01 to D-04)

### Payer handling and data loading
- `R/02_harmonize_payer.R` — Payer harmonization logic, `encounters` tibble with `payer_category`, enrollment completeness per partner (Section 5)
- `R/00_config.R` — PAYER_MAPPING with sentinel_values, unavailable_codes; SOURCE column note at line 107 (AMS, UMI, FLM, VRT)
- `R/01_load_pcornet.R` — PCORnet table loading including ENCOUNTER and DEMOGRAPHIC tables

### Display layer
- `R/11_generate_pptx.R` — rename_payer() function (line 86-91) maps Unknown/Unavailable/Other/NA to "Missing"

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/18_uf_insurance_missingness.R`: Direct template — generalize by replacing `filter(SOURCE == "UFH")` with `group_by(SOURCE)` in each section
- `PAYER_MAPPING$sentinel_values` + `PAYER_MAPPING$unavailable_codes`: Missingness indicator lists from `00_config.R`
- `encounters` tibble from `02_harmonize_payer.R`: Provides harmonized `payer_category` column for raw-vs-harmonized comparison

### Established Patterns
- Patient ID column is `ID` (not PATID)
- SOURCE column from DEMOGRAPHIC table identifies partner site (UFH, AMS, UMI, FLM, VRT)
- Standalone diagnostic scripts: `source("R/02_harmonize_payer.R")`, `message()` + `glue()` logging, `write_csv()` to `output/tables/`
- NA ENC_TYPE preserved as visible "<NA>" category (Phase 19 pattern)
- 1900 sentinel dates filtered from temporal analyses

### Integration Points
- Input: `pcornet$ENCOUNTER` (PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY, ADMIT_DATE, ENC_TYPE, ID)
- Input: `pcornet$DEMOGRAPHIC` (ID, SOURCE) — no site filter, use all sites
- Input: `encounters` tibble (with payer_category for raw-vs-harmonized)
- Output: CSV files to `output/tables/` with `all_source_` prefix

</code_context>

<specifics>
## Specific Ideas

- Structure is essentially Phase 19's script with `filter(SOURCE == "UFH")` replaced by `group_by(SOURCE)` throughout
- Cross-site summary CSV should enable quick identification of which sites have the best/worst payer data completeness
- Console output should print a compact table-like summary showing each site's overall PRIMARY missingness rate for quick HiPerGator review

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 21-generalize-phase-19-to-all-sources*
*Context gathered: 2026-04-13*
