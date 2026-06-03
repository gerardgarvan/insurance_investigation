# Phase 81: Filter Unknown, Add Category Column, Map Unmapped Sub-Categories - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-03
**Phase:** 81-filter-unknown-from-cancer-codes-in-treatment-summary-add-category-column-to-sub-category-summary-map-unmapped-sub-categories
**Areas discussed:** Unknown filtering, Category column design, Unmapped sub-category resolution

---

## Unknown Filtering

### Q1: How should episodes with no cancer diagnosis codes be handled?

| Option | Description | Selected |
|--------|-------------|----------|
| Filter out entirely | Remove rows with 'Unknown' cancer_codes from both Table 1 and Table 2. Simplest — these episodes had no cancer ICD codes on their encounters. | ✓ |
| Filter from Table 1 only | Remove 'Unknown' from sub-category summary but keep in encounter summary. Table 2 would still show all treatment combinations including those without cancer codes. | |
| You decide | Claude picks the approach that best fits the data quality goals. | |

**User's choice:** Filter out entirely
**Notes:** None

### Q2: Should the log/console output report how many rows were removed due to missing cancer codes?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, log the count | Add a message like 'Filtered N rows with no cancer codes from Table 1/Table 2' — follows existing R/56 logging patterns. | |
| No, just filter silently | Remove them without special logging — the existing NOTE about episodes without cancer codes in Section 4 already covers this. | ✓ |
| You decide | Claude picks based on existing logging patterns in R/56. | |

**User's choice:** No, just filter silently
**Notes:** Existing Section 4 NOTE already reports count of episodes without cancer codes.

---

## Category Column Design

### Q1: Where should the category column appear in Table 1?

| Option | Description | Selected |
|--------|-------------|----------|
| First column (Recommended) | category \| sub_category \| cancer_codes \| encounter_count — natural grouping, reads left-to-right from broad to specific. | ✓ |
| After sub_category | sub_category \| category \| cancer_codes \| encounter_count — keeps current first column unchanged. | |
| You decide | Claude picks the column order. | |

**User's choice:** First column (Recommended)
**Notes:** None

### Q2: How should the category value be derived?

| Option | Description | Selected |
|--------|-------------|----------|
| From treatment_type | Use the episode's treatment_type field directly (Chemotherapy, Radiation, SCT, Immunotherapy) — already present on each episode row, no parsing needed. | ✓ |
| Parse from sub_category name | Extract from the sub_category label itself (e.g., 'Chemo HCPCS...' -> Chemotherapy). More fragile if naming changes. | |
| You decide | Claude picks the most robust approach. | |

**User's choice:** From treatment_type
**Notes:** None

### Q3: Should the table be sorted by category first, then sub-category?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, sort by category then by encounter count within | category (alphabetical or custom order) -> sub_category (by descending encounter_count). Groups related rows together. | ✓ |
| Keep current sort | Currently sorted by sub_category alphabetical, then by descending encounter_count. Adding category column but not changing sort. | |
| You decide | Claude picks the sort order. | |

**User's choice:** Yes, sort by category then by encounter count within
**Notes:** None

---

## Unmapped Sub-Category Resolution

### Q1: Which tiers of unmapped sub-categories should be resolved?

| Option | Description | Selected |
|--------|-------------|----------|
| Both code-type and truly unmapped | Resolve all non-xlsx sub-categories. Code-type fallbacks like 'Chemo HCPCS (no xlsx mapping)' get proper medication names, and truly unmapped codes get investigated and assigned. | ✓ |
| Truly unmapped only | Only fix Tier 3 codes ('Chemotherapy (unmapped)', etc.). The code-type labels like 'Chemo RxNorm' are informative enough as-is. | |
| You decide | Claude assesses which unmapped codes are worth resolving based on volume. | |

**User's choice:** Both code-type and truly unmapped
**Notes:** None

### Q2: How should unmapped codes be resolved?

| Option | Description | Selected |
|--------|-------------|----------|
| Add mappings to R/00_config.R | Create a new CODE_SUBCATEGORY_MAP in config that maps treatment codes to sub-category names. Follows the centralized config pattern (like DRUG_GROUPINGS, CANCER_SITE_MAP). R/56 falls back to this map for codes not in the xlsx. | ✓ |
| Add mappings to the xlsx file | Update all_codes_resolved_next_tables_v2.1.xlsx with the missing code-to-subcategory mappings. Keeps the xlsx as the single source of truth. | |
| Investigate codes at runtime | Look up unknown codes against DRUG_GROUPINGS or TREATMENT_CODES to derive a label dynamically. No static mapping file needed, but more complex logic. | |

**User's choice:** Add mappings to R/00_config.R
**Notes:** Follows existing centralized config pattern (DRUG_GROUPINGS, CANCER_SITE_MAP, AMC_PAYER_LOOKUP).

### Q3: For the new CODE_SUBCATEGORY_MAP, should we map every individual code to a readable sub-category name, or group by code type?

| Option | Description | Selected |
|--------|-------------|----------|
| Readable names where possible | Map each code to a specific medication/procedure name (e.g., HCPCS J9035 -> 'Bevacizumab'). Fall back to code-type group only for codes where a specific name can't be determined. | ✓ |
| Group by code type | Map to categories like 'HCPCS Chemo Agent', 'RxNorm Chemo Agent', 'ICD-9 Radiation Procedure'. Less specific but consistent and maintainable. | |
| You decide | Claude investigates the actual codes and picks the most useful labeling approach. | |

**User's choice:** Readable names where possible
**Notes:** None

---

## Claude's Discretion

- Category sort order (alphabetical vs logical treatment ordering)
- Method for investigating unmapped codes to find readable names
- Whether to add summary count of resolved vs remaining unmapped

## Deferred Ideas

None — discussion stayed within phase scope.
