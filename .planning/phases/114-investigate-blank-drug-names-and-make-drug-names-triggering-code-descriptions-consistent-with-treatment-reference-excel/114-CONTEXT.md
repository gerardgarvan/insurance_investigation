# Phase 114: Investigate blank drug names and make drug_names/triggering_code_descriptions consistent with treatment reference excel - Context

**Gathered:** 2026-06-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Data quality remediation of blank drug names in treatment episodes and alignment of drug_names/triggering_code_descriptions with the canonical treatment reference excel. Modifies pipeline scripts to use the reference excel Medication column as the authoritative drug name source, filling blanks where triggering codes can be mapped. Produces a separate before/after audit xlsx documenting all changes.

</domain>

<decisions>
## Implementation Decisions

### Blank Drug Names
- **D-01:** Investigate AND fill blank drug_names where possible — not report-only. Episodes with blank drug_names that have triggering_codes should be resolved.
- **D-02:** Use the **Medication** column from `all_codes_resolved_next_tables_v2.1.xlsx` as the fill source. Do NOT include route, dosage, or full description — just the medication name.
- **D-03:** Map triggering_codes to the reference excel to fill blanks. This is the primary fill mechanism (most blanks likely have J-codes or billing codes).

### Consistency Target
- **D-04:** Treatment reference excel (`all_codes_resolved_next_tables_v2.1.xlsx`) is the authoritative source for drug names and code descriptions. Pipeline values that disagree are bugs to fix.
- **D-05:** triggering_code_descriptions should match the treatment reference excel. Discrepancies = pipeline fixes, not reference corrections.

### Normalization
- **D-06:** Claude's discretion on normalization level (exact character match vs cleaned/title-cased form). Choose what makes sense given the data.

### Output Structure
- **D-07:** Before/after audit xlsx with two sheets: Sheet 1 = summary of blanks filled and discrepancies fixed with counts. Sheet 2 = per-code detail showing old vs new drug_name/description values.
- **D-08:** Audit xlsx produced by a **separate standalone investigation script** (not built into modified pipeline scripts). Follows the R/59, R/51 standalone pattern.

### Pipeline Modification
- **D-09:** Modify upstream pipeline scripts (R/27, R/42, R/26, R/28 as needed) so drug_names and triggering_code_descriptions use the treatment reference excel as source of truth. Changes propagate through all downstream outputs.

### Claude's Discretion
- Which specific pipeline scripts need modification (R/27 drug name resolution, R/42 code descriptions, R/26 episode builder, R/28 episode classification — determine based on where inconsistencies originate)
- Styled xlsx headers following existing meeting-presentable pattern (dark gray FF374151, white bold text, freeze panes)
- New script number assignment for the audit script
- R/88 smoke test section additions
- Whether to add the audit script to R/39 pipeline runner

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Treatment Reference Excel
- `data/reference/all_codes_resolved_next_tables_v2.1.xlsx` — Canonical source for drug names (Medication column), treatment code mappings, and code descriptions. 454 codes across 5 categories.

### Drug Name Resolution Pipeline
- `R/27_drug_name_resolution.R` — Resolves drug names via RxNorm API; produces `drug_name_lookup.rds`. Primary source of current drug_names.
- `R/26_treatment_episodes.R` — Aggregates drug_names per episode (lines 706-719); blank episodes get empty string.
- `R/28_episode_classification.R` — Uses drug_names for regimen detection (lines 294-306); J-code fallback for episodes without drug names (lines 365-382).

### Code Description Infrastructure
- `R/42_build_code_descriptions.R` — Builds `code_descriptions.rds` used for triggering_code_description in episode classification.
- `R/00_config.R` (lines 1371-1901) — Contains DRUG_GROUPINGS named vector (454 codes → categories) extracted from reference excel.

### Downstream Consumers
- `R/57_drug_grouping_instances.R` — Drug grouping instances output; uses drug names and reference excel.
- `R/36_tableau_ready_tables.R` — TABLE-2 chemo drugs by class; reads reference excel for medication names.
- `R/58_co_administration_analysis.R` — Co-administration analysis; uses drug names.
- `R/52_gantt_v2_export.R` — Gantt export; includes drug_names and triggering_code_description columns.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/27_drug_name_resolution.R`: RxNorm API lookup infrastructure with caching (`drug_name_lookup.rds`)
- `R/42_build_code_descriptions.R`: Code description builder producing `code_descriptions.rds`
- `R/00_config.R DRUG_GROUPINGS`: 454-code named vector mapping treatment codes to categories
- `R/36_tableau_ready_tables.R` already reads the reference excel for medication names (line 70) — this pattern can be reused
- openxlsx2 styled xlsx pattern from R/59, R/51 for audit output

### Established Patterns
- Drug name resolution: RxNorm API via R/27 → `drug_name_lookup.rds` → R/26 aggregates per episode
- Episode drug_names: aggregated from detail-level drug_name via `paste(sort(unique(drug_name)), collapse = ",")`
- J-code fallback: R/28 already detects regimens from triggering_codes when drug_names are blank (42% of chemo episodes)
- Reference excel reading: `openxlsx2::read_xlsx(REFERENCE_XLSX, sheet = ...)` pattern used in R/36, R/56, R/57, R/58

### Integration Points
- `drug_name_lookup.rds` (R/27 output → R/26 input): drug name resolution cache
- `code_descriptions.rds` (R/42 output → R/28 input): code description lookup for triggering_code_description
- `treatment_episodes.rds` (R/26 output → many consumers): carries drug_names column
- `all_codes_resolved_next_tables_v2.1.xlsx` (reference data → R/36, R/56, R/57, R/58): medication name lookup

</code_context>

<specifics>
## Specific Ideas

- User specifically said to use the **Medication column** from the reference excel, not route/dosage/full description
- This is a data quality remediation, not just an investigation — the goal is to actually fix the blanks and inconsistencies in the pipeline
- The J-code fallback in R/28 (lines 365-382) already handles ~42% of chemo episodes without drug_names — this phase may expand that approach

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 114-investigate-blank-drug-names-and-make-drug-names-triggering-code-descriptions-consistent-with-treatment-reference-excel*
*Context gathered: 2026-06-24*
