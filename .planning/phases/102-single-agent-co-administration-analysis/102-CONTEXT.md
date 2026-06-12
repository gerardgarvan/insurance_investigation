# Phase 102: Single-Agent Co-Administration Analysis - Context

**Gathered:** 2026-06-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Detect fragmented regimen patterns by identifying single-agent chemotherapy encounters and finding all co-administered chemotherapies within a ±30-day window. Produces a detail table (COADMIN-01) and pattern summary table (COADMIN-02) as a new standalone R script (R/58).

NOT in scope: modifying regimen detection in R/28, changing any existing outputs, adding non-chemo treatment types to the co-administration window.

</domain>

<decisions>
## Implementation Decisions

### Single-Agent Definition
- **D-01:** "Single-agent" means one chemotherapy triggering_code per patient-date. Group by (patient_id, treatment_date) — if only 1 chemo code appears on that date, the encounter qualifies.
- **D-02:** Include encounters with no resolved drug_name (drug_name is NA). Use triggering_code as the identifier. Some chemo is billed via J-codes without RxNorm resolution — these should not be excluded.

### Window & Scope
- **D-03:** ±30-day window from treatment_date. For each single-agent chemo encounter, find all OTHER chemo encounters for the same patient within 30 days before or after.
- **D-04:** Chemo-to-chemo only. Only Chemotherapy treatment_type encounters are included in both the single-agent base and the co-administration window. Radiation, SCT, Immunotherapy, Proton Therapy are excluded.
- **D-05:** Exclude encounters already classified as part of a multi-agent regimen (regimen_label = ABVD, BV+AVD, or Nivo+AVD from R/28). Only analyze truly unclassified single-agent encounters — these are the ones that might represent fragmented billing.

### Output Structure
- **D-06:** Two-sheet xlsx output: Sheet 1 = "Co-Administration Detail" (COADMIN-01), Sheet 2 = "Pattern Summary" (COADMIN-02).
- **D-07:** Detail table format: one row per (single-agent encounter, co-administered drug) pair. Multiple rows if multiple co-admin drugs found within ±30 days. Columns include days_apart for temporal analysis.
- **D-08:** Drug identification: show both human-readable sub_category_name AND triggering_code. Sub-category names from R/57's reference xlsx mapping pattern (CODE_SUBCATEGORY_MAP or direct xlsx lookup).

### Script Placement
- **D-09:** New standalone script: R/58_co_administration_analysis.R. Follows R/57 in the drug grouping decade. Reads same treatment_episode_detail.rds input.
- **D-10:** Self-contained investigation script — loads its own data, produces its own output. Does not modify any upstream RDS files or existing outputs.

### Claude's Discretion
- Column ordering in detail and summary tables
- Whether to include cancer_linked flag from Phase 101 in the co-admin detail
- Sub-category name resolution approach (reuse R/57's xlsx lookup pattern vs CODE_SUBCATEGORY_MAP from R/00_config.R)
- Console summary messages and attrition logging
- R/88 smoke test validation section structure and check count

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Drug Grouping Scripts
- `R/57_drug_grouping_instances.R` — Established pattern for reading treatment_episode_detail.rds, building sub-category mappings from reference xlsx, encounter-level analysis with openxlsx2 output
- `R/56_new_tables_from_groupings.R` — Episode-level companion. Not modified but shows episode vs encounter grain patterns.

### Episode Classification & Regimen Detection
- `R/28_episode_classification.R` — Regimen detection (Section 5). Defines regimen_label (ABVD, BV+AVD, Nivo+AVD) and n_unique_drugs. D-05 requires filtering OUT encounters with these regimen labels.

### Configuration & Lookups
- `R/00_config.R` — DRUG_GROUPINGS, CODE_SUBCATEGORY_MAP, TREATMENT_CODES, CONFIG paths
- `R/utils/utils_assertions.R` — assert_rds_exists, assert_df_valid patterns
- `data/reference/all_codes_resolved_next_tables_v2.1.xlsx` — Sub-category mappings (Chemo column C = medication name)

### Data Input
- `cache/outputs/treatment_episode_detail.rds` — Primary input. Grain: (patient_id, treatment_date, triggering_code, ENCOUNTERID). Columns include treatment_type, drug_name, episode_number, episode_start, episode_stop.
- `cache/outputs/treatment_episodes.rds` — Episode-level data with regimen_label from R/28. Needed to filter out regimen-classified encounters (D-05).

### Validation
- `R/88_smoke_test_comprehensive.R` — Needs new validation section for co-administration output structure

### Requirements
- `.planning/REQUIREMENTS.md` — COADMIN-01, COADMIN-02

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/57_drug_grouping_instances.R` Section 3: Sub-category mapping pattern from reference xlsx (chemo_map, radiation_map, sct_map). Can reuse for human-readable drug names in co-admin output.
- `assert_rds_exists()` / `assert_df_valid()`: Standard input validation pattern.
- `openxlsx2` workbook pattern: `wb_workbook()` → `add_worksheet()` → `add_data()` → `save()` — well-established across R/57, R/58 (code_reference), R/28.
- `R/00_config.R` CONFIG paths for output_dir, cache dirs.

### Established Patterns
- Investigation script pattern (R/30 Phase 100): loads data, self-contained analysis, produces xlsx output, no upstream modification.
- Dual-output pattern (R/57 Phase 89): grain-labeled + backward-compat filenames. May apply if needed.
- Console logging with glue: section headers, row counts, summary statistics at each step.

### Integration Points
- `treatment_episode_detail.rds` (from R/26/R/44a/R/60): Primary input, encounter-level grain.
- `treatment_episodes.rds` (from R/28): Episode-level with regimen_label — needed to identify which encounters belong to classified regimens.
- `R/88_smoke_test_comprehensive.R`: New validation section for R/58 structural checks.

</code_context>

<specifics>
## Specific Ideas

- Success criteria #4 specifically calls out "identify fragmented ABVD/BV+AVD patterns via co-administration temporal clustering" — the pattern summary should make it easy to spot known regimen drug combinations appearing as separate single-agent encounters.
- The ±30-day window matches R/28's temporal fallback window, keeping the pipeline internally consistent.
- "Most common pairings ranked by frequency" (success criteria #2) means the Pattern Summary sheet should be sorted descending by pair count.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 102-single-agent-co-administration-analysis*
*Context gathered: 2026-06-12*
