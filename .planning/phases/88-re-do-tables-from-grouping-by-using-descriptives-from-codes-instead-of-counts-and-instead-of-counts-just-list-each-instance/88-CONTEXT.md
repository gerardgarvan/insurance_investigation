# Phase 88: Re-do Tables with Descriptives Instead of Counts - Context

**Gathered:** 2026-06-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Restructure R/56 drug grouping summary tables into a new instance-level output file. Replace aggregated counts with individual patient-episode rows, use resolved sub-category names (drug names, procedure types) as primary descriptors instead of raw codes, and show cancer site category names instead of raw ICD codes. Produces a new xlsx file with 2 sheets, leaving the existing drug_grouping_tables.xlsx unchanged.

</domain>

<decisions>
## Implementation Decisions

### Which Tables Change
- **D-01:** Both Table 1 (Sub-Category Summary) and Table 2 (Encounter Treatment Summary) are restructured into the new instance-level design.
- **D-02:** The existing drug_grouping_tables.xlsx remains unchanged — a new separate xlsx file is created.

### Descriptive Columns
- **D-03:** Use resolved sub-category names as the primary descriptor column (e.g., "Doxorubicin" instead of "J9000", "IMRT" instead of CPT code). These come from the existing 3-tier sub-category resolution: xlsx mappings → CODE_SUBCATEGORY_MAP → fallback labels.
- **D-04:** Cancer codes column replaced with cancer site category names from CANCER_SITE_MAP (ICD-10) and ICD9_CANCER_SITE_MAP (ICD-9), sorted in descending order. E.g., "Hodgkin Lymphoma;Lymph Node Neoplasm" instead of "C81.10;C77.9".

### Instance-Level Detail
- **D-05:** One row per patient + treatment type + episode. Each episode is a distinct row — if a patient has 2 separate chemotherapy courses, they appear as 2 rows.
- **D-06:** Each row includes: PATID, episode_start, episode_stop, episode_number, treatment category (Chemotherapy/Radiation/SCT/Immunotherapy), sub-category name(s), and cancer site category names.

### Output Format
- **D-07:** New xlsx file (separate from drug_grouping_tables.xlsx) — preserves the old file unchanged.
- **D-08:** Two sheets maintained — Table 1 (sub-category detail) and Table 2 (encounter treatment detail) remain as separate sheets with the new row grain.

### Claude's Discretion
- New xlsx file name (e.g., `drug_grouping_instances.xlsx` or similar descriptive name)
- Column ordering within each sheet beyond the specified columns
- How to handle episodes with multiple sub-categories (semicolon-separated list vs one column per sub-category)
- Sort order of rows within sheets (by PATID, by treatment category, by date, etc.)
- Whether to create a new script (e.g., R/57) or add to R/56 as additional output
- How to map semicolon-separated cancer codes to their category names (per-code lookup before joining)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Primary Script
- `R/56_new_tables_from_groupings.R` — Current drug grouping tables producer; source of data pipeline and sub-category resolution logic

### Configuration & Lookups
- `R/00_config.R` — DRUG_GROUPINGS (454-entry named vector), CODE_SUBCATEGORY_MAP (326-entry code-to-name mappings), CANCER_SITE_MAP (ICD-10), ICD9_CANCER_SITE_MAP (ICD-9)
- `R/utils/utils_cancer.R` — is_cancer_code(), classify_codes() shared utilities
- `data/reference/all_codes_resolved_next_tables_v2.1.xlsx` — Reference xlsx with sub-category mappings (Chemo col C, Radiation col G, SCT col G)

### Data Sources
- `cache/outputs/treatment_episodes.rds` — Input data from R/28 with PATID, treatment_type, episode_number, episode_start, episode_stop, triggering_codes, encounter_ids, cancer_category columns

### Prior Phase Context
- `.planning/phases/79-code-investigations-new-tables/79-CONTEXT.md` — R/56 creation decisions, Table 1/Table 2 original design
- `.planning/phases/81-filter-unknown-from-cancer-codes-in-treatment-summary-add-category-column-to-sub-category-summary-map-unmapped-sub-categories/81-CONTEXT.md` — Table 1 column structure, NA filtering, CODE_SUBCATEGORY_MAP
- `.planning/phases/82-non-informative-subcategories-explore-this-and-see-if-unhelpful-codes-are-in-the-same-encounter-as-a-helpful-code-and-from-there-just-count-the-helpful-code/82-CONTEXT.md` — Encounter-level dx code deduplication
- `.planning/phases/87-fix-cancer-summary-pre-post-to-include-icd9-but-be-still-filtered-on-icd10-81-and-all-codes-resolved-next-tables-and-drug-grouping-tables-should-all-be-linked-in-the-codes-they-use/87-CONTEXT.md` — Unified ICD-9/ICD-10 cancer code handling

### Quality
- `R/88_smoke_test_comprehensive.R` — Smoke test to be updated for new output file

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `treatment_episodes.rds` columns: PATID, treatment_type, episode_number, episode_start, episode_stop, triggering_codes, encounter_ids, cancer_category, drug_names — all the per-episode data needed
- Sub-category resolution logic in R/56 Section 5: 3-tier lookup (xlsx → CODE_SUBCATEGORY_MAP → fallback) — can be reused or refactored
- `CANCER_SITE_MAP` and `ICD9_CANCER_SITE_MAP` in R/00_config.R — for cancer code → category name translation
- `classify_codes()` in R/utils/utils_cancer.R — can classify individual ICD codes to site categories
- openxlsx2 multi-sheet xlsx output pattern — established in R/50, R/56

### Established Patterns
- Centralized config maps in R/00_config.R as named vectors
- Section headers: `# SECTION N: NAME ----`
- Defensive assertions: `checkmate::assert_*()` at script start
- Documentation headers with Purpose, Inputs, Outputs, Dependencies, Requirements

### Integration Points
- R/56 Section 4: encounter_ids split and cancer code aggregation per encounter — foundation for cancer code → category name translation
- R/56 Section 5: triggering_codes split and sub-category resolution — foundation for sub-category name columns
- treatment_episodes.rds already has episode-level grain with all required identifying columns

</code_context>

<specifics>
## Specific Ideas

- Cancer site categories should be sorted in descending order within each cell (user specified "descending order" for category names)
- The new tables are explicitly about seeing individual instances rather than aggregated patterns — the audience wants to trace specific patient episodes with readable labels

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 88-re-do-tables-from-grouping-by-using-descriptives-from-codes-instead-of-counts-and-instead-of-counts-just-list-each-instance*
*Context gathered: 2026-06-04*
