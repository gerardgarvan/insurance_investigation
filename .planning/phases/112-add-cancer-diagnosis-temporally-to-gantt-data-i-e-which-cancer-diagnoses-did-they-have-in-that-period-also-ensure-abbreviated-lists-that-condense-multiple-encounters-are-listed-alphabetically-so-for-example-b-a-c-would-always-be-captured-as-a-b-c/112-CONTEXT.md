# Phase 112: Add Cancer Diagnosis Temporally to Gantt Data + Alphabetical List Ordering - Context

**Gathered:** 2026-06-22
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase enriches Gantt episode data with temporal cancer diagnosis information (all cancer diagnoses occurring during each episode's buffered date range) and enforces alphabetical ascending sort on ALL multi-value fields across the Gantt export pipeline and TABLE-2.

</domain>

<decisions>
## Implementation Decisions

### Diagnosis Date Range
- **D-01:** Capture all cancer diagnoses where DX_DATE falls within a 30-day buffer on both sides of the episode span: `(episode_start - 30 days)` through `(episode_stop + 30 days)`
- **D-02:** This extends beyond the existing R/28 linkage (which uses 30-day backward only for single-category matching) to provide a full temporal picture of what was being diagnosed around each treatment episode

### New Columns Design
- **D-03:** Add TWO new columns to Gantt export: one for comma-separated ICD codes (e.g., "C81.00,C81.10,C85.90") and one for comma-separated category names (e.g., "Hodgkin Lymphoma,Non-Hodgkin Lymphoma")
- **D-04:** Deduplicate values within each column (unique codes, unique categories per episode)
- **D-05:** Keep existing single-value `cancer_category` column alongside new temporal columns — do not replace it. Downstream consumers of the existing field are not disrupted.

### Alphabetical Sort Audit
- **D-06:** Audit ALL multi-value fields across the entire Gantt export pipeline (triggering_codes, drug_names, encounter_ids, and any other comma/semicolon-separated fields) and enforce alphabetical ascending sort
- **D-07:** This includes both the new temporal diagnosis columns and all pre-existing multi-value fields in R/26, R/52, and related scripts

### Sort Direction
- **D-08:** All multi-value fields sort ascending (A-Z) everywhere — no exceptions. The user's example ("b,a,c" becomes "a,b,c") is the universal rule.
- **D-09:** Fix TABLE-2 (R/36) `cancer_category_names` field which currently uses `sort(..., decreasing = TRUE)` — change to ascending to match the universal rule

### Claude's Discretion
- Column naming for the two new temporal diagnosis fields (suggested: `episode_dx_codes` and `episode_dx_categories` or similar descriptive names)
- Where in the pipeline the temporal diagnosis query is best placed (R/28 enrichment vs R/52 export-time query)
- Whether to add the new columns to both `gantt_episodes.csv` and `gantt_detail.csv` or episodes only

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Gantt Export Pipeline
- `R/52_gantt_v2_export.R` — Main Gantt export script; Phase 64 cleanup logic; current column structure
- `R/28_episode_classification.R` — Cancer linkage cascade (encounter ID + 30-day temporal + CONDITION); Section 4

### Episode Structure
- `R/25_treatment_durations.R` — Episode splitting (90-day gap threshold); `assign_episode_ids()` function
- `R/26_treatment_episodes.R` — Episode aggregation; `calculate_episodes_detailed()` with triggering_codes/drug_names sorting

### Cancer Code Mapping
- `R/00_config.R` — CANCER_SITE_MAP and ICD9_CANCER_SITE_MAP lookup tables
- `R/utils/utils_cancer.R` — `classify_codes()` function for ICD code to category name mapping

### Existing Sort Pattern (Phase 111 precedent)
- `R/36_tableau_ready_tables.R` — Lines 296-309: TABLE-2 date-grain collapse with `sort(unique(...))` pattern; descending sort on cancer_category_names that needs fixing per D-09

### Smoke Test
- `R/88_smoke_test.R` — Structural validation; will need updates for new columns

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `sort(unique(na.omit(...)))` pattern: Well-established in R/26 and R/36 for collapsing multi-value fields
- `CANCER_SITE_MAP` / `ICD9_CANCER_SITE_MAP` in R/00_config.R: Ready-to-use ICD code to category name mapping
- `classify_codes()` in R/utils/utils_cancer.R: Existing function for mapping DX codes to cancer categories
- `clean_multi_value()` helper in R/52: Phase 64 dedup/cleanup function (does NOT currently re-sort)

### Established Patterns
- Multi-value field aggregation: `paste(sort(unique(na.omit(field))), collapse = ",")` (R/26, R/36)
- Gantt separator convention: semicolons in R/52 Phase 64 cleanup; commas in R/36 TABLE-2
- DuckDB DIAGNOSIS table queries: Already used in R/28 for cancer linkage

### Integration Points
- R/52 gantt_v2_export.R: Where new columns would be added to the Gantt CSV output
- R/28 episode_classification.R: Where temporal diagnosis enrichment could be performed (alongside existing linkage)
- R/36 tableau_ready_tables.R: Where TABLE-2 descending sort fix applies
- R/88 smoke_test.R: Structural assertions need updating for new Gantt columns

</code_context>

<specifics>
## Specific Ideas

- User explicitly gave the example "b,a,c" should always be "a,b,c" — ascending alphabetical is the universal rule, no exceptions
- The intent is to see "which cancer diagnoses did they have in that period" — this is about clinical context enrichment, not replacing the existing linkage mechanism

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 112-add-cancer-diagnosis-temporally-to-gantt-data*
*Context gathered: 2026-06-22*
