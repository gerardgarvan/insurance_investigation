# Phase 101: Broadened Drug Grouping Output - Context

**Gathered:** 2026-06-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Expand R/57 drug grouping instances output to include ALL treatment encounters (not just cancer-linked) with a new cancer_linked TRUE/FALSE flag column. Preserve the existing cancer-linked-only output as a separate file. Add a linked-vs-unlinked cross-tab summary sheet.

R/56 (episode-level summaries) is NOT in scope — stays cancer-linked-only.

</domain>

<decisions>
## Implementation Decisions

### Scope of Broadening
- **D-01:** R/57 only. R/56 episode-level summaries stay unchanged (cancer-linked-only).
- **D-02:** Only the `filter(!is.na(cancer_category_names))` filter is removed for the broadened output. The existing reference code filter (valid_reference_codes OR Immunotherapy) stays in place.

### cancer_linked Flag
- **D-03:** cancer_linked derived from encounter-level DX presence — the existing R/57 logic that joins DuckDB DIAGNOSIS data per encounter and checks for cancer codes. TRUE when encounter has cancer diagnosis codes, FALSE otherwise.
- **D-04:** Self-contained within R/57, no dependency change on R/28's cancer_category column.

### Cross-Tab Summary
- **D-05:** Simple 3-column table: treatment_type | linked_count | unlinked_count. One row per treatment type (Chemo, RT, SCT, Immuno, Proton).
- **D-06:** Cross-tab lives as 3rd sheet in the broadened xlsx (named "Linked vs Unlinked Summary" or similar within 31-char Excel limit).

### Output File Strategy
- **D-07:** Broadened output becomes the primary file: `drug_grouping_instances.xlsx` (backward compat) and `encounter_level_drug_grouping_instances.xlsx` (grain-labeled).
- **D-08:** Cancer-linked-only output preserved with `_linked_only` suffix: `drug_grouping_instances_linked_only.xlsx` (backward compat) and `encounter_level_drug_grouping_instances_linked_only.xlsx` (grain-labeled).
- **D-09:** Broadened file has 3 sheets (Sub-Category Detail, Treatment Detail, Linked vs Unlinked Summary). Linked-only file keeps exact current 2-sheet structure.

### Claude's Discretion
- Sheet naming within 31-char Excel limit
- Column ordering for cancer_linked flag (last column or positioned contextually)
- Smoke test (R/88) validation section additions for broadened output

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Drug Grouping Scripts
- `R/57_drug_grouping_instances.R` — Primary script to modify. Currently filters to cancer-linked-only at lines 375 and 399.
- `R/56_new_tables_from_groupings.R` — Episode-level companion. NOT in scope but read for pattern consistency.

### Episode Classification
- `R/28_episode_classification.R` — Upstream cancer linkage (ENCOUNTERID + 30-day temporal fallback). NOT modified, but understanding cancer_category derivation is needed for context.

### Configuration
- `R/00_config.R` — DRUG_GROUPINGS, CODE_SUBCATEGORY_MAP, CANCER_SITE_MAP, ICD9_CANCER_SITE_MAP, TREATMENT_CODES
- `R/utils/utils_cancer.R` — is_cancer_code() shared utility used by R/57 for DX filtering

### Validation
- `R/88_smoke_test_comprehensive.R` — Needs new validation section for broadened output structure

### Requirements
- `.planning/REQUIREMENTS.md` — DRUG-01, DRUG-02, DRUG-03

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/57_drug_grouping_instances.R` Section 4: Already joins DuckDB DIAGNOSIS per encounter and derives cancer_category_names. The cancer_linked flag can be derived from existing `cancer_codes` column (non-NA = linked).
- `is_cancer_code()` from `R/utils/utils_cancer.R`: Shared utility for cancer DX detection, already used in R/57.
- `get_lookup_dt()` / `ensure_dt()` / `to_tibble_safe()`: data.table bridge utilities already integrated in R/57 Sections 5-6.

### Established Patterns
- Dual-output pattern (Phase 89): grain-labeled filename + backward compat filename. R/57 already uses this pattern.
- Multi-sheet xlsx via openxlsx2: R/57 Section 7 already creates workbook with multiple sheets.
- Reference code filtering: Lines 280-284 filter to valid_reference_codes OR Immunotherapy. This filter stays for both broadened and linked-only outputs.

### Integration Points
- `treatment_episode_detail.rds` (from R/26): Input data. Contains all treatment encounters — the broadening is about removing the downstream cancer filter, not changing the input.
- `R/88_smoke_test_comprehensive.R`: Needs new validation section checking broadened output has more rows than linked-only, cancer_linked column exists, and cross-tab sheet present.

</code_context>

<specifics>
## Specific Ideas

- Row structure of broadened output must be identical to existing output plus the cancer_linked column (per success criteria #4).
- The linked-only preserved file must produce identical content to what R/57 currently produces (no regressions).
- Treatment types in cross-tab: Chemotherapy, Radiation, SCT, Immunotherapy, Proton Therapy (5 rows).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 101-broadened-drug-grouping-output*
*Context gathered: 2026-06-12*
