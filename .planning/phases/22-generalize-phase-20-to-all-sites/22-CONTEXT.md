# Phase 22: Generalize Phase 20 to All Sites - Context

**Gathered:** 2026-04-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Extend Phase 20's FLM-specific duplicate date investigation to ALL partner sites (AMS, UMI, FLM, VRT, UFH) in the OneFlorida+ dataset. Produce a standalone diagnostic R script that performs the same duplicate date detection, multi-source identification, and payer completeness comparison as Phase 20 but for all sites using DEMOGRAPHIC.SOURCE as the site grouping dimension, with per-site recommendations and a cross-site summary CSV.

</domain>

<decisions>
## Implementation Decisions

### Investigation Scope
- **D-01:** Analyze ALL patients per site from DEMOGRAPHIC (not just HL cohort). Same approach as Phase 20 D-06 — this is a data quality investigation, not a cohort analysis
- **D-02:** Patients assigned to sites via DEMOGRAPHIC.SOURCE (patient's home site). Then examine ENCOUNTER.SOURCE within each patient's encounters to detect cross-site encounters. Direct extension of Phase 20 pattern
- **D-03:** Same duplicate definitions as Phase 20: same-date by ID+date only (D-01), exact row duplicates (D-02), check ADMIT_DATE primary + DISCHARGE_DATE secondary (D-03)
- **D-04:** Same missingness definition as Phase 19/20: NA, empty string, NI, UN, OT, 99, 9999

### Output Structure
- **D-05:** Same 3+1 CSVs as Phase 20 but with a SITE/SOURCE column, plus a cross-site summary CSV (5 files total)
  - `all_site_patient_duplicate_summary.csv` (patient-level with SITE column)
  - `all_site_date_level_duplicate_detail.csv` (date-level with sources and payer data, SITE column)
  - `all_site_duplicate_aggregate_summary.csv` (per-site aggregate rates)
  - `all_site_source_payer_completeness.csv` (per-site source completeness)
  - `all_site_cross_site_summary.csv` (one row per site for head-to-head comparison)
- **D-06:** CSV file naming uses `all_site_` prefix, consistent with Phase 21's `all_source_` prefix pattern
- **D-07:** CSV output to `output/tables/` — consistent with existing pipeline pattern

### Recommendation Logic
- **D-08:** Per-site source-preference recommendations — for each DEMOGRAPHIC.SOURCE site, identify which ENCOUNTER.SOURCE provides the best payer data when multi-source duplicates exist
- **D-09:** Each site gets its own recommendation based on its own multi-source encounter payer completeness rates

### Script Design
- **D-10:** New standalone script `R/21_all_site_duplicate_dates.R`. Phase 20's `R/19_flm_duplicate_dates.R` stays unchanged
- **D-11:** Sources its own dependencies (same pattern as Phase 20: `source("R/00_config.R")` then conditional `source("R/01_load_pcornet.R")`)
- **D-12:** Use `group_by(SITE)` or iterate per site to extend Phase 20's single-site logic to all sites

### Claude's Discretion
- Exact CSV column structures and any additional columns beyond Phase 20's set
- Console logging format and how to present per-site summaries compactly
- Whether to iterate per site (for-loop like Phase 20's structure) or use group_by throughout (Phase 21's pattern)
- How to handle sites with zero duplicate dates or zero multi-source encounters
- Cross-site summary CSV column selection and sort order
- Script section numbering and organization

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 20 reference implementation
- `R/19_flm_duplicate_dates.R` — Phase 20 FLM-specific script to generalize. Contains the 8 sections: FLM patient identification (S1), encounter filtering (S2), same-date duplicate detection (S3), exact row duplicates (S4), multi-source identification (S5), payer completeness comparison (S6), CSV outputs (S7), console summary (S8)
- `.planning/phases/20-check-duplicate-dates-of-flm-subjects/20-CONTEXT.md` — Phase 20 decisions D-01 through D-18, especially duplicate definitions and payer completeness approach

### Phase 21 generalization pattern
- `R/20_all_source_missingness.R` — Phase 21 script showing the successful "generalize to all sites" pattern (group_by(SOURCE), cross-site summary CSV, `all_source_` prefix)
- `.planning/phases/21-generalize-phase-19-to-all-sources/21-CONTEXT.md` — Phase 21 decisions, especially D-01 (combined CSVs), D-02 (cross-site summary), D-07 (group_by pattern)

### Data loading and payer handling
- `R/01_load_pcornet.R` — PCORnet table loading including ENCOUNTER and DEMOGRAPHIC tables
- `R/00_config.R` — PAYER_MAPPING with sentinel_values, unavailable_codes; SOURCE column note at line 107

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/19_flm_duplicate_dates.R`: Direct template — generalize by replacing `filter(SOURCE == "FLM")` with a per-site loop or group_by pattern for each section
- `is_missing_payer()` function in Phase 20 script: Reuse directly for payer completeness comparison
- `R/20_all_source_missingness.R`: Shows the successful generalization pattern from Phase 19 to all sites

### Established Patterns
- Patient ID column is `ID` (not PATID)
- DEMOGRAPHIC.SOURCE identifies patient's home site (UFH, AMS, UMI, FLM, VRT)
- ENCOUNTER.SOURCE identifies where the encounter was recorded — may differ from DEMOGRAPHIC.SOURCE
- Standalone diagnostic scripts: `source("R/01_load_pcornet.R")`, `message()` + `glue()` logging, `write_csv()` to `output/tables/`
- `janitor::get_dupes()` used for exact row duplicate detection
- Date parsing: try ISO format first, fall back to `parse_pcornet_date()` if needed

### Integration Points
- Input: `pcornet$ENCOUNTER` (all 19 columns, especially ADMIT_DATE, DISCHARGE_DATE, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY, SOURCE, ID)
- Input: `pcornet$DEMOGRAPHIC` (ID, SOURCE) — iterate per unique SOURCE value
- Output: CSV files to `output/tables/` with `all_site_` prefix

</code_context>

<specifics>
## Specific Ideas

- Structure mirrors Phase 20's 8-section layout, but wraps the per-site logic to run for each DEMOGRAPHIC.SOURCE value
- Cross-site summary CSV enables quick identification of which sites have the worst duplication problems and which ENCOUNTER.SOURCE provides best payer data per site
- Console output should print a compact per-site summary table for quick HiPerGator review (like Phase 21's console output pattern)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 22-generalize-phase-20-to-all-sites*
*Context gathered: 2026-04-14*
