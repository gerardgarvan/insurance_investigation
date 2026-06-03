# Phase 81: Filter Unknown from cancer_codes, add category column, map unmapped sub-categories - Context

**Gathered:** 2026-06-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Refine R/56 (`R/56_new_tables_from_groupings.R`) drug grouping summary table outputs: remove rows without cancer diagnosis codes, add a parent treatment category column to Table 1, and resolve all unmapped sub-category labels to readable names via a new centralized config map.

</domain>

<decisions>
## Implementation Decisions

### Unknown Cancer Codes Filtering
- **D-01:** Filter out rows with no cancer diagnosis codes (`cancer_codes` is NA) from both Table 1 (Sub-Category Summary) and Table 2 (Encounter Treatment Summary) entirely. Do not replace NA with "Unknown" — exclude these rows from the output.
- **D-02:** Filter silently — no additional log message for the filtering. The existing Section 4 NOTE about episodes without cancer codes already reports the count.

### Category Column Design
- **D-03:** Add a `category` column as the **first column** in Table 1. Final column order: `category | sub_category | cancer_codes | encounter_count`.
- **D-04:** Derive `category` value from the episode's `treatment_type` field directly (Chemotherapy, Radiation, SCT, Immunotherapy). No parsing from sub_category labels.
- **D-05:** Sort Table 1 by `category` first (alphabetical or custom order), then by descending `encounter_count` within each category. This groups related sub-categories together.

### Unmapped Sub-Category Resolution
- **D-06:** Resolve ALL non-xlsx sub-categories — both code-type fallbacks (Tier 2: "Chemo HCPCS (no xlsx mapping)", "Chemo RxNorm", etc.) and truly unmapped codes (Tier 3: "Chemotherapy (unmapped)", "Radiation (unmapped)", "SCT (unmapped)").
- **D-07:** Create a new `CODE_SUBCATEGORY_MAP` named vector in `R/00_config.R` that maps treatment codes to sub-category names. Follows the centralized config pattern established by `DRUG_GROUPINGS`, `CANCER_SITE_MAP`, and `AMC_PAYER_LOOKUP`.
- **D-08:** Map to readable medication/procedure names where possible (e.g., HCPCS J9035 -> "Bevacizumab"). Fall back to code-type group labels only for codes where a specific name cannot be determined.
- **D-09:** R/56 lookup order: (1) reference xlsx sub-category mappings, (2) `CODE_SUBCATEGORY_MAP` from config, (3) final fallback label only if code is in neither.

### Claude's Discretion
- Category sort order within Table 1 (alphabetical vs custom logical ordering like Chemo > Radiation > SCT > Immunotherapy)
- How to investigate and identify readable names for currently unmapped codes (DRUG_GROUPINGS cross-reference, HCPCS/CPT code descriptions, etc.)
- Whether to add a summary count of resolved vs remaining unmapped codes to the console log

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Primary Script
- `R/56_new_tables_from_groupings.R` -- The script being modified; produces drug_grouping_tables.xlsx

### Configuration
- `R/00_config.R` -- Where CODE_SUBCATEGORY_MAP will be added; contains DRUG_GROUPINGS, CANCER_SITE_MAP, TREATMENT_CODES patterns
- `data/reference/all_codes_resolved_next_tables_v2.1.xlsx` -- Reference xlsx with existing sub-category mappings (Chemo col C, Radiation col G, SCT col G)

### Utilities
- `R/utils/utils_assertions.R` -- assert_rds_exists, assert_df_valid, warn_row_count
- `R/utils/utils_duckdb.R` -- open_pcornet_con, get_pcornet_table

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `DRUG_GROUPINGS` in R/00_config.R: Named vector mapping treatment codes to drug group names — same pattern for CODE_SUBCATEGORY_MAP
- `CANCER_SITE_MAP` in R/00_config.R: Named vector mapping ICD code prefixes to cancer categories — established pattern for code-to-label lookups
- `TREATMENT_CODES` in R/00_config.R: Lists of codes by treatment type and code system — can cross-reference to identify which codes need sub-category mappings
- `code_to_subcategory` in R/56 (line 135): Combined lookup vector built from xlsx sheets — integration point for CODE_SUBCATEGORY_MAP fallback

### Established Patterns
- Centralized config constants: All lookup maps live in R/00_config.R as named vectors
- Three-tier sub-category assignment in R/56 Section 5: xlsx lookup -> code-type fallback -> truly unmapped
- `case_when()` cascade for sub-category assignment (lines 279-319): Will need modification to use CODE_SUBCATEGORY_MAP

### Integration Points
- R/56 Section 5 (lines 277-319): `case_when()` block where sub-category assignment happens — CODE_SUBCATEGORY_MAP lookup inserted here
- R/56 Section 5 (lines 341-346): Table 1 aggregation — add `category` column from `treatment_type`, reorder columns, change sort
- R/56 Section 6 (lines 369-376): Table 2 aggregation — filter out NA cancer_codes instead of replacing with "Unknown"

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches for code name resolution and config map structure.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 81-filter-unknown-from-cancer-codes-in-treatment-summary-add-category-column-to-sub-category-summary-map-unmapped-sub-categories*
*Context gathered: 2026-06-03*
