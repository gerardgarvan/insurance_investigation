# Phase 115: Add 7-Day Confirmed Column + Age at Episode to Gantt Data - Context

**Gathered:** 2026-06-26
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase adds two new columns to the Gantt episodes CSV:

1. **7-day confirmed categories column** - For each episode, shows which of its `episode_dx_categories` (added in Phase 112) are also 7-day confirmed at the patient level (2+ unique diagnosis dates spanning 7+ days for that category).

2. **Age at episode column** - Patient's age in integer years (floor) at `episode_start`, computed from DEMOGRAPHIC birth date.

Both are additive columns to `gantt_episodes.csv` only (detail CSV unchanged). No existing columns are modified.

</domain>

<decisions>
## Implementation Decisions

### 7-Day Confirmed Column Format
- **D-01:** New column contains a comma-separated list of only the 7-day confirmed categories (subset of `episode_dx_categories`). NOT a boolean flag.
- **D-02:** Example: if `episode_dx_categories` = "Hodgkin Lymphoma,Non-Hodgkin Lymphoma" and only HL is 7-day confirmed for that patient, the new column = "Hodgkin Lymphoma". If both are confirmed, column = "Hodgkin Lymphoma,Non-Hodgkin Lymphoma". If none confirmed, empty string.

### Match Logic
- **D-03:** Confirmation matching operates at the **category level**, not the raw ICD code level. Intersect the episode's `episode_dx_categories` with the patient's set of 7-day confirmed cancer categories.
- **D-04:** Patient's 7-day confirmed categories derived from R/45's `two_or_more_unique_dates_gt_7` flag per patient-code pair, mapped to category names via `classify_codes()`.
- **D-05:** If `episode_dx_categories` is empty (no diagnoses in +/-30 day window), the new column is also empty.

### Age at Episode
- **D-06:** Age represented as integer years (floor of years between birth_date and episode_start).
- **D-07:** Birth date sourced from DEMOGRAPHIC table (BIRTH_DATE column). Patients with missing birth date get NA.

### Output Scope
- **D-08:** Both new columns added to `gantt_episodes.csv` only. `gantt_detail.csv` schema unchanged. Consistent with Phase 112's approach.
- **D-09:** Ascending alphabetical sort on the 7-day confirmed categories list (consistent with Phase 112 universal sort rule).

### Claude's Discretion
- Column naming for both new fields (suggested: `episode_dx_7day_confirmed` and `age_at_episode` or similar descriptive names)
- Where in the pipeline to compute (R/28 enrichment time vs R/52 export time)
- How to source DEMOGRAPHIC birth dates (direct DuckDB query vs cached RDS)
- Gantt episodes schema column count update (currently 24, will become 26)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Gantt Export Pipeline
- `R/52_gantt_v2_export.R` -- Main Gantt export script; current 24-column EPISODES_SCHEMA; where new columns are added
- `R/28_episode_classification.R` -- Episode enrichment; Phase 112 added episode_dx_codes/episode_dx_categories (lines 727-796)

### 7-Day Confirmation Source
- `R/45_cancer_summary.R` -- Computes `two_or_more_unique_dates_gt_7` per patient-code pair (lines 256-304); upstream source for confirmed categories
- `R/49_cancer_summary_pre_post.R` -- Uses HL-specific 7-day confirmation (lines 125-138); pattern reference

### Cancer Code Classification
- `R/utils/utils_cancer.R` -- `classify_codes()` function for ICD code to category name mapping
- `R/00_config.R` -- CANCER_SITE_MAP (309 ICD-10 prefixes), ICD9_CANCER_SITE_MAP

### Episode Structure
- `R/26_treatment_episodes.R` -- Episode aggregation with sort(unique()) pattern for multi-value fields

### Smoke Test
- `R/88_smoke_test_comprehensive.R` -- Structural validation; needs updates for new columns (24 -> 26)

### Prior Phase Context
- `.planning/phases/112-*/112-CONTEXT.md` -- episode_dx_categories design decisions (D-01 through D-09)
- `.planning/phases/110-*/110-CONTEXT.md` -- 7-day gap criterion definition (D-04 through D-07)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `two_or_more_unique_dates_gt_7` column in cancer_summary.csv: Per patient-code pair 7-day confirmation flag. Ready to filter and map to categories.
- `classify_codes()` in R/utils/utils_cancer.R: Maps ICD codes to category names. Already used in R/28 Phase 112 enrichment.
- `sort(unique(na.omit(...)))` pattern: Established in R/26, R/36, R/52 for multi-value field aggregation.
- DuckDB DEMOGRAPHIC table: Already queried elsewhere in pipeline for patient demographics.

### Established Patterns
- Multi-value field aggregation: `paste(sort(unique(na.omit(field))), collapse = ",")` (R/26, R/36)
- Phase 112 enrichment in R/28: DuckDB DIAGNOSIS query + classify_codes() + left_join to episodes
- R/49 lines 125-131: Pattern for extracting patient ID vector from 7-day confirmed subset

### Integration Points
- R/52 EPISODES_SCHEMA: Currently 24 columns, will expand to 26
- R/52 final select() and write: Where new columns appear in output CSV
- R/88 smoke test: Schema count assertion (24 -> 26) and new column structural checks
- R/39 pipeline runner: No changes needed (R/52 already in pipeline)

</code_context>

<specifics>
## Specific Ideas

- The 7-day confirmed column provides a clinical quality signal: episodes whose associated diagnoses are robustly confirmed (multiple dates over 7+ days) vs possibly incidental single-code appearances
- Age at episode enables age-stratified analysis of treatment patterns without requiring a separate demographic join downstream
- Both columns are purely additive -- no existing data or columns are modified

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope (age at episode was folded into this phase)

</deferred>

---

*Phase: 115-add-7-day-confirmed-column-to-gantt-data*
*Context gathered: 2026-06-26*
