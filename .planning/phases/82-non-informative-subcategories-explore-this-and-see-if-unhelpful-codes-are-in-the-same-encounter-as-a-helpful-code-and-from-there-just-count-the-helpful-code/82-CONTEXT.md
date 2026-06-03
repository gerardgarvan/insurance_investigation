# Phase 82: Non-Informative Sub-Categories — Explore and Count Helpful Codes - Context

**Gathered:** 2026-06-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Identify non-informative encounter diagnosis (dx) codes in R/56 drug grouping summary tables, check whether a helpful/specific treatment code exists in the same encounter, and when it does, count only the helpful code. First explore as a standalone investigation script, then integrate the validated logic into R/56. Applies to Table 1 (Sub-Category Summary) only.

</domain>

<decisions>
## Implementation Decisions

### Non-Informative Definition
- **D-01:** Only encounter diagnosis codes are non-informative. These are sub-categories matching "Encounter Dx Code" pattern — e.g., "Chemo Encounter Dx Code", "Radiation Encounter Dx Code", "Immunotherapy Encounter Dx Code". They indicate treatment happened but don't name the specific drug/procedure.
- **D-02:** DRG codes, Revenue codes, procedure codes, HCPCS, CPT, RxNorm, ICD-10-PCS, and all Tier 1/Tier 2 resolved names remain classified as informative (helpful).

### Matching Scope
- **D-03:** Check for helpful code partners within the same `encounter_id`, not across the entire treatment episode. This is the most precise — ensures the specific treatment code was billed alongside the dx code in the same visit.
- **D-04:** R/56 already has encounter-level data from the `encounter_ids` split in Section 4. Use this existing encounter-level granularity for the co-occurrence check.

### Orphan Handling
- **D-05:** When an encounter has ONLY non-informative dx codes (no helpful code partner), keep the rows but add a flag column (`dx_only = TRUE`) so they can be easily filtered later. Do not exclude them from the output entirely.
- **D-06:** This preserves data completeness while making dx-only encounters visually separable and filterable in downstream analysis.

### Output Strategy
- **D-07:** Two-step approach: first create a new exploration script (R/57) that reads R/56's data, performs encounter-level co-occurrence analysis, and produces a refined version of Table 1. Then fold validated logic into R/56.
- **D-08:** Apply deduplication to Table 1 (Sub-Category Summary) only. Table 2 (Encounter Treatment Summary) already shows all treatments per encounter as a set, so non-informative codes are less problematic there.
- **D-09:** The exploration script should produce diagnostic output showing: how many dx codes have helpful partners, how many are orphans (dx-only), and what the count impact is (before vs after deduplication).

### Quality & Robustness
- **D-10:** Code must anticipate upstream changes — handle new treatment types, new code systems, or DRUG_GROUPINGS updates without breaking. Use pattern matching on sub-category labels (e.g., `str_detect(sub_category, "Encounter Dx")`) rather than hardcoded lists.
- **D-11:** Code must anticipate downstream changes — any modifications to drug_grouping_tables.xlsx schema should be backward-compatible or clearly documented. The `dx_only` flag column is additive, not breaking.
- **D-12:** Follow existing v2.0 code quality standards: styler formatting, lintr compliance, checkmate assertions, documentation headers, section structure.

### Claude's Discretion
- Exact script number for exploration script (R/57 suggested but confirm available numbering)
- Whether to add encounter-level co-occurrence stats to the existing R/56 log output or keep them in the exploration script only
- Internal data structure for the co-occurrence check (join-based vs group_by approach)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Primary Script (being modified)
- `R/56_new_tables_from_groupings.R` -- Current drug grouping summary tables; Section 5 (Table 1) is the target for deduplication integration. Contains encounter-level data split in Section 4.

### Configuration
- `R/00_config.R` -- DRUG_GROUPINGS (454-entry named vector), TREATMENT_CODES (code lists by type and code system), CODE_SUBCATEGORY_MAP (treatment code-to-name mappings), CANCER_SITE_MAP
- `data/reference/all_codes_resolved_next_tables_v2.1.xlsx` -- Reference xlsx with sub-category mappings

### Data Sources
- `cache/outputs/treatment_episodes.rds` -- Input data from R/28 with triggering_codes, encounter_ids, treatment_type, cancer_category columns

### Prior Phase Context
- `.planning/phases/81-filter-unknown-from-cancer-codes-in-treatment-summary-add-category-column-to-sub-category-summary-map-unmapped-sub-categories/81-CONTEXT.md` -- Phase 81 decisions on Table 1 column structure, NA filtering, 3-tier sub-category lookup
- `.planning/phases/79-code-investigations-new-tables/79-CONTEXT.md` -- Phase 79 decisions on R/56 creation, table structure, data sources

### Quality Standards
- `R/88_smoke_test_comprehensive.R` -- Smoke test to be updated with Phase 82 validations

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `episode_codes` data frame in R/56 Section 5: Already has per-code rows with `treatment_code`, `sub_category`, `category`, `code_type`, and `cancer_codes`. This is the starting point for co-occurrence analysis.
- `episode_encounters` in R/56 Section 4: Already splits `encounter_ids` into individual rows with `ENCOUNTERID` column. Provides the encounter-level join key.
- `is_cancer_code()` function in R/56: Helper for cancer code detection, reusable in exploration script.
- `code_to_subcategory` combined lookup in R/56 Section 3: Xlsx-sourced mappings for Tier 1 resolution.
- `CODE_SUBCATEGORY_MAP` in R/00_config.R: Tier 2 supplement mappings.

### Established Patterns
- Section headers: `# SECTION N: NAME ----`
- Defensive assertions: `checkmate::assert_*()` at script start
- Multi-sheet xlsx output via openxlsx2
- Console diagnostics with `message()` + `glue()`
- Documentation headers with Purpose, Inputs, Outputs, Dependencies, Requirements
- Sub-category classification via `case_when()` cascade (R/56 lines 291-337)

### Integration Points
- R/56 Section 5 (lines 410-416): Table 1 aggregation — where deduplication logic needs to be inserted (after individual code rows are created but before aggregation)
- R/56 Section 4 (lines 170-175): `episode_encounters` data frame — provides encounter-level granularity for co-occurrence check
- `sub_category` column values: Pattern match on "Encounter Dx" to identify non-informative codes (D-01, D-10)

</code_context>

<specifics>
## Specific Ideas

- User emphasized code should "run well and anticipate downstream and upstream changes" — robustness and defensive coding are priorities.
- Exploration-first approach: understand the data before modifying production code. Diagnostic output should quantify the impact of deduplication.
- The `dx_only` flag provides flexibility — downstream consumers can choose to include or exclude dx-only encounters.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 82-non-informative-subcategories-explore-this-and-see-if-unhelpful-codes-are-in-the-same-encounter-as-a-helpful-code-and-from-there-just-count-the-helpful-code*
*Context gathered: 2026-06-03*
