# Phase 2: Payer Harmonization - Context

**Gathered:** 2026-03-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement 9-category payer mapping with encounter-level dual-eligible detection, matching the Python pipeline's logic exactly. Produce a patient-level payer summary and per-partner enrollment completeness report. Cohort filtering and visualization are separate phases.

</domain>

<decisions>
## Implementation Decisions

### Dual-eligible detection
- **D-01:** Encounter-level dual-eligible detection matching Python pipeline exactly (not temporal enrollment overlap). PAYR-02 requirement wording to be updated from "temporal overlap" to "encounter-level"
- **D-02:** Effective payer per encounter = primary if valid, else secondary if valid, else null. Sentinels: null, empty, NI, UN, OT
- **D-03:** 99/9999 are NOT sentinel values — they map to "Unavailable" category (matching Python default, no configurable toggle)
- **D-04:** When PAYER_TYPE_SECONDARY is missing, dual_eligible = 0 (matches Python — cannot compute cross-payer check without secondary)
- **D-05:** Dual-eligible overrides payer category to "Dual eligible" — no separate raw category column preserved

### Payer variable scope (core set for v1)
- **D-06:** Compute core set: PAYER_CATEGORY_PRIMARY (most frequent), PAYER_CATEGORY_AT_FIRST_DX (mode within +/-30 days of first HL DX), DUAL_ELIGIBLE, PAYER_TRANSITION, N_ENCOUNTERS, N_ENCOUNTERS_WITH_PAYER
- **D-07:** Treatment flags (HAD_CHEMO, HAD_RADIATION, HAD_SCT) deferred to Phase 3 cohort building
- **D-08:** +/-30 day window for PAYER_CATEGORY_AT_FIRST_DX uses CONFIG$analysis$dx_window_days (already set to 30 in 00_config.R)
- **D-09:** Tie-breaking for mode: sort by count descending, take first (matches Python)
- **D-10:** First HL diagnosis date = earliest of DX_DATE (DIAGNOSIS table) and DATE_OF_DIAGNOSIS (TUMOR_REGISTRY tables). Both sources used
- **D-11:** ICD code matching uses config list (ICD_CODES$hl_icd10 + hl_icd9) with dot-removal normalization on both sides
- **D-12:** ICD normalization goes in shared R/utils_icd.R (normalize_icd(), is_hl_diagnosis()) — auto-sourced via 00_config.R, reusable by Phase 3

### Harmonization function design
- **D-13:** Named reusable functions: map_payer_category(), compute_effective_payer(), detect_dual_eligible(). Defined in 02_harmonize_payer.R. Readable and consistent with project's named-function style

### Completeness report (PAYR-03)
- **D-14:** Console summary table printed via message() + glue. Columns: partner, n_patients, n_with_enrollment, pct_enrolled, mean_covered_days, n_with_gaps
- **D-15:** Enrollment gap = break >30 days between consecutive enrollment periods for same patient at same partner
- **D-16:** Duration = total covered days (sum of actual enrollment period durations, excluding gaps)
- **D-17:** Report also includes payer category distribution per partner (counts per category per site)

### Output structure
- **D-18:** Primary output = patient-level summary tibble (payer_summary): one row per patient with ID, SOURCE, PAYER_CATEGORY_PRIMARY, PAYER_CATEGORY_AT_FIRST_DX, DUAL_ELIGIBLE, PAYER_TRANSITION, N_ENCOUNTERS, N_ENCOUNTERS_WITH_PAYER
- **D-19:** Save to both environment (payer_summary object) and CSV (output/tables/payer_summary.csv) for manual inspection and Python comparison
- **D-20:** Print validation summary after harmonization: total patients, per-category counts, dual-eligible rate, flag if dual-eligible rate outside 10-20% of Medicare+Medicaid combined
- **D-21:** Script sources 01_load_pcornet.R (self-contained — running 02_harmonize_payer.R loads data automatically)

### Claude's Discretion
- Internal structure of map_payer_category() and compute_effective_payer() functions
- Console formatting for completeness report and validation summary
- Exact dplyr pipeline structure within named functions
- How to handle edge cases in gap detection (missing ENR_END_DATE, etc.)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Payer mapping logic (PRIMARY reference)
- `C:\cygwin64\home\Owner\Data loading and cleaing\docs\PAYER_VARIABLES_AND_CATEGORIES.md` -- Exact 9-category mapping, effective payer logic, dual-eligible definition (encounter-level), sentinel handling, tie-breaking rules. THE authoritative reference for all payer harmonization logic

### Data schema
- `csv_columns.txt` -- Column listing for PCORnet CDM CSV files. Key tables: ENCOUNTER (PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY), ENROLLMENT (ENR_START_DATE, ENR_END_DATE), DIAGNOSIS (DX, DX_DATE, DX_TYPE)

### Existing config and code
- `R/00_config.R` -- PAYER_MAPPING list (prefix rules, sentinel values, dual-eligible codes, categories), ICD_CODES list (149 HL codes), CONFIG$analysis$dx_window_days
- `R/01_load_pcornet.R` -- Data loading (pcornet$ENROLLMENT, pcornet$ENCOUNTER, pcornet$DIAGNOSIS, pcornet$TUMOR_REGISTRY1/2/3)
- `R/utils_dates.R` -- parse_pcornet_date() for date column parsing
- `R/utils_attrition.R` -- Attrition logging pattern (reuse for reporting)

### Architecture patterns
- `.planning/research/ARCHITECTURE.md` -- Numbered script pattern, named function style
- `.planning/phases/01-foundation-data-loading/01-CONTEXT.md` -- Phase 1 decisions (D-04 payer mapping in config, D-11 column names as-is, D-15 SOURCE column, D-23 script naming)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/00_config.R`: PAYER_MAPPING list with all prefix rules, sentinel values, dual-eligible codes, and 9 category names already defined
- `R/00_config.R`: ICD_CODES list with all 149 HL diagnosis codes (77 ICD-10 + 72 ICD-9) in dotted format
- `R/00_config.R`: CONFIG$analysis$dx_window_days = 30 for diagnosis window
- `R/utils_attrition.R`: log_attrition() pattern for console reporting
- `R/utils_dates.R`: parse_pcornet_date() for date parsing

### Established Patterns
- Named list storage: pcornet$TABLE_NAME for loaded data (from 01_load_pcornet.R)
- Patient ID column is `ID` (not PATID) across all tables
- SOURCE column = partner/site identifier (AMS, UMI, FLM, VRT)
- Scripts source their dependencies: 02 sources 01 which sources 00_config
- Console logging via message() + glue()
- readr for CSV I/O

### Integration Points
- Input: pcornet$ENCOUNTER (PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY, ADMIT_DATE, ENCOUNTERID, ID)
- Input: pcornet$ENROLLMENT (ID, SOURCE, ENR_START_DATE, ENR_END_DATE)
- Input: pcornet$DIAGNOSIS (ID, DX, DX_DATE, DX_TYPE)
- Input: pcornet$TUMOR_REGISTRY1/2/3 (ID, DATE_OF_DIAGNOSIS)
- Output: payer_summary tibble consumed by Phase 3 (cohort building) and Phase 4 (visualization)
- Output: output/tables/payer_summary.csv for manual validation against Python pipeline
- New utility: R/utils_icd.R auto-sourced via 00_config.R

</code_context>

<specifics>
## Specific Ideas

- Match Python pipeline logic exactly for comparability — this is a parallel exploration tool, not a different approach
- First HL diagnosis date should use both DIAGNOSIS and TUMOR_REGISTRY tables (earliest date wins)
- ICD normalization utility (utils_icd.R) should be built here to be reused by Phase 3 cohort predicates
- Validation summary should flag concerning rates automatically so the user sees issues immediately

</specifics>

<deferred>
## Deferred Ideas

- Treatment-specific payer variables (AT_FIRST_CHEMO, AT_LAST_CHEMO, AT_FIRST_RADIATION, etc.) -- could add after v1 core
- Temporal enrollment overlap as supplemental dual-eligible analysis -- alternative approach, not needed for Python match
- Configurable 99/9999 sentinel toggle -- Python has it but defaults to False, not needed for v1
- Full diagnostic enrollment report with histograms and heatmaps -- v2 enhancement

</deferred>

---

*Phase: 02-payer-harmonization*
*Context gathered: 2026-03-24*
