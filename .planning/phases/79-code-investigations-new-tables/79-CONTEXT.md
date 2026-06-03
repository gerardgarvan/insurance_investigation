# Phase 79: Code Investigations & New Tables - Context

**Gathered:** 2026-06-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Investigate SCT code 0362 data quality across 90 patients, verify replaced-by code mappings from all_codes_resolved_next_tables.xlsx with pairwise and chain analysis, and generate two new drug grouping summary tables (treatment-type-level and drug-level). Three new scripts numbered R/54-R/56 in the cancer/codes decade. No changes to upstream treatment pipeline or cancer classification logic.

</domain>

<decisions>
## Implementation Decisions

### Script Numbering
- **D-01:** New scripts in the 54-56 range within the cancer/codes decade (40-59), NOT the roadmap's originally suggested R/92, R/93, R/76 (all taken).
- **D-02:** R/54_investigate_sct_0362.R — SCT code 0362 investigation
- **D-03:** R/55_verify_replaced_by_codes.R — replaced-by code verification
- **D-04:** R/56_new_tables_from_groupings.R — two new drug grouping summary tables

### SCT 0362 Investigation (R/54)
- **D-05:** Full encounter profile — pull complete encounter details (all procedures, diagnoses, prescriptions) for encounters with revenue code 0362.
- **D-06:** Output: multi-sheet xlsx. Sheet 1: patient summary (PATID, encounter count, other SCT codes found). Sheet 2: encounter-level detail (all procedures, diagnoses for 0362 encounters). Sheet 3: summary statistics.
- **D-07:** Automated recommendation based on overlap rate with standard SCT codes (38204-38241, 0815): >80% overlap = "confirmed SCT", <30% = "likely coding artifact", 30-80% = "manual review needed".

### Replaced-by Verification (R/55)
- **D-08:** Replaced-by mappings are in all_codes_resolved_next_tables.xlsx (column/sheet in the xlsx).
- **D-09:** Primary verification: pairwise check — for each old->new pair, verify old code IS in our code lists, new code IS also in our code lists, and both map to the same treatment category. Flag mismatches and missing codes with PASS/FAIL status.
- **D-10:** Secondary verification: chain detection — detect replacement chains >3 steps and any cycles. Uses igraph for DAG checking (new lightweight dependency, noted in STATE.md open question #6).
- **D-11:** Output: xlsx verification report. Sheet 1: all replaced-by pairs with PASS/FAIL/MISSING status. Sheet 2: chain analysis (chains >3 steps, any cycles). Sheet 3: summary statistics. Plus console diagnostics.

### New Drug Grouping Tables (R/56)
- **D-12:** Single xlsx output with 2 sheets matching all_codes_resolved_next_tables.xlsx Sheet1 templates.
- **D-13:** Table 1 (Sheet 1): treatment-type-level summary. Rows = treatment types (Chemo, Radiation, SCT, Immunotherapy). Columns: treatment type | cancer code(s) for the encounter (raw ICD codes) | count of encounters. One row per unique treatment-type + cancer-code-set combination.
- **D-14:** Table 2 (Sheet 2): drug-level summary. Rows = individual treatment codes (CPT/HCPCS/NDC). Columns: treatment code | cancer code(s) for the encounter (raw ICD codes) | count of encounters. One row per unique treatment-code + cancer-code-set combination.
- **D-15:** Cancer codes = raw ICD diagnosis codes linked to the encounter (not cancer_category labels). Multi-code encounters show semicolon-separated code sets.
- **D-16:** Data source: treatment_episodes.rds (from R/28) joined with encounter-level cancer linkage data. Uses DRUG_GROUPINGS for treatment type classification and triggering_codes for cancer code extraction.

### Quality Process
- **D-17:** During execution, take explicit validation passes through all new scripts to verify: (a) column names referenced actually exist in source data, (b) joins use correct keys and produce expected row counts, (c) source() calls reference correct script paths, (d) functions called are defined and accessible. Fix any issues found before committing.

### Claude's Discretion
- igraph installation approach (install.packages vs renv::install) — follow existing renv pattern
- Script header comment depth — follow v2.0 standard patterns from R/35 or R/50

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Data Sources
- `data/reference/all_codes_resolved_next_tables_v2.1.xlsx` -- Source of replaced-by mappings and template for new tables. Must inspect sheet structure and column names.
- `all_codes_resolved_next_tables.xlsx` (project root) -- Original xlsx, may differ from versioned copy.

### Treatment Pipeline (read-only, provides input data)
- `R/28_episode_classification.R` -- Produces treatment_episodes.rds with triggering_codes, cancer_category, drug_group, triggering_code_description columns. Primary data source for R/56.
- `R/00_config.R` -- DRUG_GROUPINGS (Section 5e, 454 codes), TREATMENT_CODES (SCT revenue codes including 0362 at line 2444), CANCER_SITE_MAP.

### Existing Code Resolution Scripts (pattern reference)
- `R/50_all_codes_resolved.R` -- Existing code resolution xlsx generator. Pattern for openxlsx2 multi-sheet output.
- `R/42_build_code_descriptions.R` -- Code description lookup builder. May be needed for human-readable labels in R/56.

### Investigation Script Patterns
- `R/35_death_cause_quality.R` -- Recent investigation script with multi-sheet xlsx output. Good template for R/54 structure.
- `R/76_treatment_source_coverage.R` -- Coverage analysis script. Pattern for encounter-level profiling.

### Quality Standards
- `R/88_smoke_test_comprehensive.R` -- Smoke test. Phase 80 will add assertions for R/54-R/56 outputs.

### Requirements
- `.planning/REQUIREMENTS.md` -- CODE-01 (replaced-by verification), CODE-02 (SCT 0362), TREAT-03 (new tables), QUAL-01 (v2.0 standards)

### Prior Phase Context
- `.planning/phases/77-cancer-classification-refinements/77-CONTEXT.md` -- DRUG_GROUPINGS decisions (D-05 through D-07)
- `.planning/phases/78-episode-enhancement-death-integration/78-CONTEXT.md` -- Episode enrichment with triggering_code_description and drug_group (D-05 through D-08)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `DRUG_GROUPINGS` (R/00_config.R:1153): 454-entry named vector mapping treatment codes to 5 categories. Source for R/56 treatment type classification.
- `TREATMENT_CODES` (R/00_config.R): Contains sct_revenue = c("0362", "0815"). Source for R/54 code list.
- `treatment_episodes.rds`: Output from R/28 with columns including triggering_codes, cancer_category, drug_group, triggering_code_description. Primary input for R/56.
- `code_descriptions.rds`: Code-to-human-readable-name lookup. Can provide labels for R/56 drug-level table.
- `build_output_path()`: Output path construction utility.
- `assert_df_valid()`, `assert_rds_exists()`: Defensive validation helpers.
- openxlsx2 multi-sheet pattern from R/50, R/35: Established xlsx generation approach.

### Established Patterns
- Section headers: `# SECTION N: NAME ----`
- Input validation: `checkmate::assert_*()` at script start
- Multi-sheet xlsx: openxlsx2 `wb_add_worksheet()` + `wb_add_data()` pattern
- Console diagnostics: `message()` + `glue()` for step-by-step logging
- Documentation headers with Purpose, Inputs, Outputs, Dependencies, Requirements

### Integration Points
- R/54 reads DuckDB PROCEDURES table (for encounter-level detail) + treatment_episodes.rds (for patient identification)
- R/55 reads all_codes_resolved_next_tables.xlsx directly + cross-references against TREATMENT_CODES/DRUG_GROUPINGS in R/00_config.R
- R/56 reads treatment_episodes.rds + DRUG_GROUPINGS + encounter-level cancer linkage data
- Phase 80 smoke test (R/88) will validate outputs from all three scripts

</code_context>

<specifics>
## Specific Ideas

- User requests explicit validation passes during implementation: verify all column references, join keys, source() paths, and function availability before committing code.
- SCT code 0362 investigation motivated by question: "do the 90 patients have other SCT codes during those encounters?" — standard CPT SCT codes are 38204-38241.
- Replaced-by code verification should flag when old and new codes map to different treatment categories (category mismatch = FAIL).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 79-code-investigations-new-tables*
*Context gathered: 2026-06-03*
