# Phase 27: Cross-Table Data Quality Assessment - Context

**Gathered:** 2026-04-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Run a comprehensive QA pass across ALL loaded PCORnet CDM tables (not just ENCOUNTER, which Phase 25-26 already investigated and found no actionable duplicates). For each table, assess multi-source overlap, field completeness, value validity against PCORnet CDM value sets, and exact row duplicates. Produce per-table CSV reports and a full console summary identifying data that isn't analytically useful.

</domain>

<decisions>
## Implementation Decisions

### Definition of 'not useful'
- **D-01:** Phase 25-26 confirmed no encounter duplicates worth removing. This phase extends QA to ALL other PCORnet CDM tables to find data quality issues there.
- **D-02:** "Not useful" encompasses: multi-source overlap records, fields that are mostly empty/sentinel-coded, values outside valid PCORnet CDM value sets, and exact row duplicates.

### QA dimensions (all four applied per table where applicable)
- **D-03:** Multi-source overlap detection — same-ID, same-date records from different SOURCE values. Apply Phase 25-26 approach to each table with a date field.
- **D-04:** Field completeness — percentage of non-NA values per column, flagging columns that are mostly empty or all-sentinel.
- **D-05:** Value validity — check values against known PCORnet CDM value sets (e.g., ENC_TYPE should be AV/IP/ED/etc., DX_TYPE should be 09/10/SM, etc.).
- **D-06:** Exact row duplicates — identical rows (all fields match) that may be data loading artifacts.
- **D-07:** Skip multi-source overlap detection for tables without a natural date field (DEMOGRAPHIC, PROVIDER). These tables get completeness + validity + exact-duplicate checks only.

### Scope
- **D-08:** All records in each table as loaded by R/01_load_pcornet.R — not filtered to HL cohort patients. Data issues affect the whole dataset.
- **D-09:** All 13 loaded PCORnet CDM tables: ENROLLMENT, DIAGNOSIS, PROCEDURES, PRESCRIBING, ENCOUNTER, DEMOGRAPHIC, TUMOR_REGISTRY (3 subtables), DISPENSING, MED_ADMIN, LAB_RESULT_CM, PROVIDER.

### Output
- **D-10:** Per-table CSV reports in output/tables/ — one CSV per table with QA findings across all four dimensions.
- **D-11:** Full console summary per table with key findings, flagged issues, and overall QA scorecard — same message()/glue() pattern as Phase 25-26 scripts.
- **D-12:** Standalone script R/24_cross_table_qa.R following established investigation script pattern.

### Claude's Discretion
- Researcher should investigate additional QA dimensions beyond the four specified (the user requested "research into other areas to explore")
- CSV naming convention and column structure per table
- How to define PCORnet CDM valid value sets per column (reference PCORnet CDM v7.0 spec or derive from data)
- How to handle TUMOR_REGISTRY which is loaded as 3 subtables — QA each separately or combined
- Console summary formatting and aggregation approach

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Prior investigation scripts (pattern reference)
- `R/22_multi_source_overlap_detection.R` — Phase 25: multi-source overlap detection pattern to adapt per table
- `R/23_overlap_classification.R` — Phase 26: field comparison and classification pattern
- `R/20_all_source_missingness.R` — Phase 21: missingness profiling pattern across sites
- `R/21_all_site_duplicate_dates.R` — Phase 22: per-site duplicate detection pattern

### Data loading and config
- `R/01_load_pcornet.R` — Defines all 13 loaded tables with column type specs
- `R/00_config.R` — CONFIG object, output_dir, payer sentinel definitions
- `R/17_value_audit.R` — Phase 13: value audit approach (frequency tables per column per table)

### Prior QA findings
- `R/18_uf_insurance_missingness.R` — Phase 19: UFH payer missingness patterns
- `R/19_flm_duplicate_dates.R` — Phase 20: FLM duplicate date patterns

### Requirements
- `.planning/REQUIREMENTS.md` — No specific REQ-IDs mapped to Phase 27 yet (TBD)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `hipaa_suppress()` and `suppress_counts()` from R/22_multi_source_overlap_detection.R — HIPAA suppression on count columns
- `is_missing_payer()` from R/21_all_site_duplicate_dates.R — payer sentinel normalization
- `R/17_value_audit.R` — Phase 13 already produced per-column frequency tables; this phase goes deeper with QA dimensions beyond just value enumeration
- Column type specs in R/01_load_pcornet.R — defines which columns exist per table

### Established Patterns
- Standalone diagnostic scripts: source 00_config.R, conditionally source 01_load_pcornet.R
- Console output: message() + glue() with section headers (strrep('=', 70))
- CSV output: readr::write_csv() to output/tables/
- HIPAA suppression on CSV count columns only; console retains raw values

### Integration Points
- Reads all tables from pcornet list object (loaded by R/01_load_pcornet.R)
- Outputs go to output/tables/ for potential future PPTX visualization
- Phase 13's value_audit CSVs in output/value_audit/ could serve as reference data

</code_context>

<specifics>
## Specific Ideas

- User confirmed encounter data has no duplicates (Phase 25-26 finding) — skip ENCOUNTER overlap re-analysis
- User wants the researcher to investigate additional QA areas beyond the four core dimensions specified
- Per-table CSV pattern is preferred over a single consolidated report

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 27-logical-next-step-to-identify-data-that-isn-t-useful*
*Context gathered: 2026-04-22*
