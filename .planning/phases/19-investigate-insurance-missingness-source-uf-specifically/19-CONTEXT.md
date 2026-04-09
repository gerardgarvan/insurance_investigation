# Phase 19: Investigate Insurance Missingness Source UF Specifically - Context

**Gathered:** 2026-04-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Investigate why insurance/payer data is missing for patients from the UF (UFH) partner site in the OneFlorida+ HL cohort. Produce a standalone diagnostic R script that examines raw ENCOUNTER PAYER_TYPE fields and derived payer_summary values for UFH patients, breaking down missingness by year, encounter type, and other dimensions the researcher identifies. Output is CSV files to `output/tables/`. The primary hypothesis is a data submission gap from UF.

</domain>

<decisions>
## Implementation Decisions

### Missingness Definition
- **D-01:** "Missing" insurance = PAYER_TYPE_PRIMARY or PAYER_TYPE_SECONDARY is any of: NA, empty string, NI, UN, OT, 99, or 9999
- **D-02:** Track missingness on BOTH PRIMARY and SECONDARY fields (not just PRIMARY)
- **D-03:** Sentinel codes (NI, UN, OT) count as missing — they provide no usable insurance information
- **D-04:** 99/9999 ("Unavailable") counts as missing — consistent with Phase 11 collapsing it into "Missing" for display

### Investigation Scope
- **D-05:** UF-only deep dive — do not compare to other sites. Focus exclusively on characterizing UFH patients' payer data patterns
- **D-06:** Examine all UF patients in the HL cohort (not just those with missing payer). Compare missing vs valid payer patients to find patterns
- **D-07:** Break down missingness by year, encounter type, and any other dimensions the researcher discovers as worthwhile
- **D-08:** Investigate at both levels: raw ENCOUNTER PAYER_TYPE fields AND derived PAYER_CATEGORY_PRIMARY after harmonization — shows where the gap originates

### Output & Deliverables
- **D-09:** Produce a standalone diagnostic R script (e.g., `R/18_uf_insurance_missingness.R` or next available number). Sources its own dependencies. Not part of the main pipeline sequence
- **D-10:** CSV output files go to `output/tables/` — consistent with existing pipeline outputs
- **D-11:** Script produces CSV files with missingness breakdowns, run on HiPerGator

### Root Cause Hypotheses
- **D-12:** Primary hypothesis: data submission gap from UF — the site may not submit payer data in certain encounter types or time periods
- **D-13:** No specific observation driving this investigation yet — this is the first UF-specific look at payer missingness
- **D-14:** Script should be exploratory — test the data submission gap hypothesis but surface whatever patterns exist

### Claude's Discretion
- Exact CSV file names and column structures
- Which additional breakdown dimensions to include beyond year and encounter type
- Console logging format and verbosity
- Script number (next available after existing scripts)
- How to identify UFH patients (SOURCE == "UFH" from DEMOGRAPHIC table, matching existing pattern)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Payer handling logic
- `R/02_harmonize_payer.R` — Payer harmonization including compute_effective_payer(), sentinel handling, and enrollment completeness report. Sections 1-7 cover all payer processing. Key: Section 2 (encounter-level processing) and Section 5 (enrollment completeness by partner)
- `R/00_config.R` — PAYER_MAPPING list with sentinel_values, unavailable_codes, unknown_codes. SOURCE column comment at line 107

### Cohort and data loading
- `R/04_build_cohort.R` — Cohort build pipeline. Line 210: WARNING for missing PAYER_CATEGORY_PRIMARY after join
- `R/01_load_pcornet.R` — PCORnet table loading including ENCOUNTER (contains PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY)

### Display layer (for understanding "Missing" consolidation)
- `R/11_generate_pptx.R` — rename_payer() function at line 86-91 maps Unknown/Unavailable/Other/NA to "Missing". PAYER_ORDER at line 82

### Prior phase context
- `.planning/phases/02-payer-harmonization/02-CONTEXT.md` — Phase 2 decisions on payer harmonization, sentinel handling, completeness report
- `.planning/phases/11-pptx-clarity-and-missing-data-consolidation/11-CONTEXT.md` — Phase 11 decisions on Missing category consolidation

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/02_harmonize_payer.R` Section 5: Enrollment completeness report already computes per-partner stats (n_patients, n_with_enrollment, pct_enrolled, mean_covered_days, n_with_gaps). Can be adapted for UF-specific analysis
- `R/02_harmonize_payer.R` Section 5f: Payer category distribution per partner already logged. Can serve as baseline for comparing against more granular missingness analysis
- `compute_effective_payer()` function: Handles PRIMARY/SECONDARY fallback logic. Useful for understanding when both fields are missing
- `PAYER_MAPPING$sentinel_values` in config: c("NI", "UN", "OT") — reuse for missingness classification

### Established Patterns
- Patient ID column is `ID` (not PATID)
- SOURCE column from DEMOGRAPHIC table identifies partner site (UFH for UF)
- Standalone diagnostic scripts source their dependencies: `source("R/01_load_pcornet.R")`
- Console logging via `message()` + `glue()`
- CSV output via `readr::write_csv()` to `output/tables/`

### Integration Points
- Input: `pcornet$ENCOUNTER` (PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY, ADMIT_DATE, ENC_TYPE, ENCOUNTERID, ID)
- Input: `pcornet$DEMOGRAPHIC` (ID, SOURCE) — filter for SOURCE == "UFH"
- Input: `payer_summary` tibble from 02_harmonize_payer.R (PAYER_CATEGORY_PRIMARY, N_ENCOUNTERS, N_ENCOUNTERS_WITH_PAYER)
- Output: CSV files to `output/tables/` with UF-specific missingness breakdowns

</code_context>

<specifics>
## Specific Ideas

- Start by profiling raw PAYER_TYPE_PRIMARY and PAYER_TYPE_SECONDARY value distributions for UFH encounters specifically
- Cross-tabulate missing payer by encounter year (from ADMIT_DATE) to see if missingness is concentrated in certain time periods
- Cross-tabulate by ENC_TYPE (IP, AV, ED, etc.) to see if certain encounter types systematically lack payer data
- Compare the raw field missingness rate to the derived PAYER_CATEGORY_PRIMARY="Unknown"/"Unavailable" rate after harmonization
- Log key summary stats to console for quick HiPerGator review, with detailed breakdowns in CSV files

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 19-investigate-insurance-missingness-source-uf-specifically*
*Context gathered: 2026-04-09*
