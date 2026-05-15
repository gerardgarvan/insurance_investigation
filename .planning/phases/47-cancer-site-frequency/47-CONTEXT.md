# Phase 47: Cancer Site Frequency - Context

**Gathered:** 2026-05-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Frequency table of all 42 cancer site categories from CancerSiteCategories.xlsx across the full PCORnet extract (not just HL cohort), with patient counts and encounter/record counts from both DIAGNOSIS (ICD-10) and TUMOR_REGISTRY (ICD-O-3 topography). Output is a styled xlsx file ready to email to collaborators.

</domain>

<decisions>
## Implementation Decisions

### ICD code matching scope
- Query BOTH DIAGNOSIS (ICD-10) and TUMOR_REGISTRY (ICD-O-3 topography) tables
- Show both sources separately: ICD-10 patient count, ICD-10 encounter count, ICD-O-3 patient count, ICD-O-3 registry records, plus combined unique patient count
- ICD-O-3 matching uses topography codes only (no morphology/histology)
- TUMOR_REGISTRY column labeled "Registry Records" not "Encounters" since rows aren't encounter-based

### Range expansion logic
- Enumerate all codes in ICD-10 ranges (e.g., "C810-C814" -> C810, C811, C812, C813, C814)
- Prefix match expanded codes against DIAGNOSIS data (C810 matches C810, C8100, C8101, etc. after normalize_icd())
- Same enumerate + prefix match approach for ICD-O-3 topography ranges
- First match wins if a code maps to multiple categories — each code assigned to one category only

### Output layout & columns
- Single sheet workbook with all 42 categories
- 6 columns: Category | ICD-10 Patients | ICD-10 Encounters | ICD-O-3 Patients | ICD-O-3 Registry Records | Combined Unique Patients
- Sort order: spreadsheet order from CancerSiteCategories.xlsx (anatomic site grouping)
- Zero-count categories show plain 0, no special styling (CSITE-01 requires all 42 present)

### HIPAA suppression
- No suppression — show exact counts for all cell sizes
- Internal/IRB-covered analysis team, not a public-facing report

### Claude's Discretion
- Totals row: whether to include and how to handle the uniqueness issue with combined patient totals
- Styled workbook formatting details (header colors, column widths, freeze panes) — follow existing openxlsx2 patterns from Phase 45/42/38

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `normalize_icd()` in R/utils_icd.R: removes dots for consistent matching — use for both ICD-10 and ICD-O-3 codes
- openxlsx2 styled workbook pattern: R/45_radiation_cpt_audit.R, R/42_treatment_codes_resolved.R, R/38_treatment_inventory.R all produce styled xlsx
- `get_pcornet_table()` in R/01_load_pcornet.R: DuckDB lazy queries for DIAGNOSIS and TUMOR_REGISTRY tables
- `get_hl_patient_ids()` in R/utils_treatment.R: not needed here (querying all patients) but available if HL-subset view wanted later

### Established Patterns
- Standalone diagnostic script pattern: source config, open DuckDB, do work, write output to output/tables/
- openxlsx2: wb_workbook() -> wb_add_worksheet() -> wb_add_data() -> wb_add_cell_style() pipeline
- `int2col()` for column references (not int_to_col — Phase 45 lesson)
- `format(x, big.mark=',')` for number formatting (not glue `:,` spec — Phase 45 lesson)

### Integration Points
- Input: CancerSiteCategories.xlsx "Groups" sheet (readxl::read_excel)
- Output: output/tables/cancer_site_frequency.xlsx
- DuckDB tables: DIAGNOSIS (DX, DX_TYPE columns), TUMOR_REGISTRY (topography columns)
- R/00_config.R sourced for CONFIG paths and shared utilities

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches matching existing pipeline style.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 47-cancer-site-frequency*
*Context gathered: 2026-05-15*
