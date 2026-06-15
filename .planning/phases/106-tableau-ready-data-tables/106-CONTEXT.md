# Phase 106: Tableau-Ready Data Tables - Context

**Gathered:** 2026-06-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce two xlsx tables (TABLE-1 and TABLE-2) that Amy can import directly into Tableau for interactive exploration of cancer diagnosis codes and chemotherapy drug classifications per treatment encounter. These are self-contained Tableau-ready exports derived from existing pipeline data — no new clinical logic, no new linkage algorithms.

</domain>

<decisions>
## Implementation Decisions

### TABLE-1: Encounter Cancer Diagnosis Codes
- **D-01:** TABLE-1 covers treatment encounters only — use encounter IDs from `treatment_episode_detail.rds` (same source as R/57). Does NOT include non-treatment encounters.
- **D-02:** One row per encounter with comma-separated cancer diagnosis codes (meeting notes specify "comma-separated").
- **D-03:** Include columns: PATID, ENCOUNTERID, treatment_date, treatment_type, cancer_codes (comma-separated DX codes), cancer_category_names (human-readable category names).

### TABLE-2: Chemo Drugs by Class with Cancer Codes
- **D-04:** TABLE-2 provides individual medication names (e.g., "Doxorubicin") plus drug class/category (e.g., "Chemotherapy", with sub-category from reference xlsx).
- **D-05:** Chemo-only filter — TABLE-2 includes only chemotherapy encounters (treatment_type == "Chemotherapy"), per meeting notes "chemotherapy drugs by class/category."
- **D-06:** Include columns: PATID, ENCOUNTERID, treatment_date, treatment_type, medication_name (individual drug), drug_class/sub_category, cancer_codes, cancer_category_names.

### Both Tables
- **D-07:** Tables include treatment context columns (PATID, ENCOUNTERID, treatment_date, treatment_type, cancer codes, category names) so Amy can build most Tableau views without external joins.
- **D-08:** Output as xlsx using openxlsx2 (established pattern from R/57, R/59, etc.).
- **D-09:** Raw counts without HIPAA suppression (internal investigation files — manual suppression before sharing, per v3.1 decision).

### Claude's Discretion
- Script number assignment (next available in the R/ directory sequence)
- Whether to create one new script or two (TABLE-1 and TABLE-2 may share enough setup to be in one script)
- Exact column ordering within each table
- Whether to reuse R/57's cancer code extraction logic via shared helper or inline it
- Sheet naming within xlsx workbooks

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Meeting Notes (TABLE-1/TABLE-2 requirements source)
- `pecan_lymphoma_meeting_notes_combined.md` — Lines 75-76: Gerard action items defining TABLE-1 and TABLE-2 specs; Line 90: Amy's Tableau visualization requirements

### Existing Implementation (data extraction patterns)
- `R/57_drug_grouping_instances.R` — Already extracts encounter-level cancer codes from DuckDB DIAGNOSIS and maps to category names; TABLE-1/TABLE-2 share this data pipeline
- `R/28_episode_classification.R` — Episode-level cancer linkage and regimen detection; produces treatment_episodes.rds consumed downstream
- `R/00_config.R` — CANCER_SITE_MAP, ICD9_CANCER_SITE_MAP, DRUG_GROUPINGS, CODE_SUBCATEGORY_MAP lookup tables
- `R/utils/utils_cancer.R` — is_cancer_code() and classify_codes() shared cancer code utilities
- `R/utils/utils_xlsx_lookups.R` — Reference xlsx loading (all_codes_resolved2.xlsx medication mappings)

### Requirements
- `.planning/REQUIREMENTS.md` — TABLE-01 and TABLE-02 requirement definitions (lines 27-28)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **R/57 cancer code extraction pattern**: `encounter_dx` intermediate already maps ENCOUNTERID -> semicolon-separated cancer codes via DuckDB DIAGNOSIS table query + is_cancer_code() filter. Can be adapted (change separator to comma).
- **R/57 sub-category resolution**: 3-tier cascade (xlsx reference -> CODE_SUBCATEGORY_MAP -> code-type fallback) resolves triggering_code to human-readable medication names.
- **openxlsx2 workbook pattern**: wb_workbook() -> add_worksheet() -> add_data() -> save() pattern used consistently in R/57, R/59, R/31, R/32, R/33, R/34.
- **utils_cancer.R**: is_cancer_code() handles both ICD-9 and ICD-10 cancer codes with map-based detection.
- **utils_xlsx_lookups.R**: load_xlsx_lookups() returns chemo/radiation/SCT medication name mappings from reference xlsx.

### Established Patterns
- **Input validation**: checkmate assert_file_exists + custom assert_rds_exists/assert_df_valid from utils_assertions.R
- **DuckDB access**: open_pcornet_con() + get_pcornet_table("DIAGNOSIS") via utils_duckdb.R
- **Logging**: Console message logging with file output (.log file pattern from R/57)
- **data.table keyed joins**: get_lookup_dt("DRUG_GROUPINGS") pattern for fast code resolution (R/57 Section 5)

### Integration Points
- **Input**: `cache/outputs/treatment_episode_detail.rds` (from R/26, encounter-level grain)
- **Input**: DuckDB DIAGNOSIS table (cancer codes per encounter)
- **Input**: `data/reference/all_codes_resolved_next_tables_v2.1.xlsx` (medication name mappings)
- **Output**: `output/` directory for new xlsx files
- **Smoke test**: R/88_smoke_test_comprehensive.R will need new validation sections

</code_context>

<specifics>
## Specific Ideas

- Meeting notes explicitly request "comma-separated" format for TABLE-1 cancer codes
- Amy uses these for Tableau — tables need to open cleanly in both Excel and Tableau
- R/57 uses semicolons as separators; TABLE-1 should use commas per meeting notes

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 106-tableau-ready-data-tables*
*Context gathered: 2026-06-15*
