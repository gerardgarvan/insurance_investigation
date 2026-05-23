# Phase 57: Gantt Enhancements - Context

**Gathered:** 2026-05-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Enrich the Gantt chart CSV exports (`gantt_episodes.csv` and `gantt_detail.csv`) with cancer category labels derived from cancer_summary.csv, an is_hodgkin binary flag, and death dates sourced from the DEATH table as pseudo-treatment endpoint rows. Also requires adding the DEATH table to the full pipeline infrastructure (config, load spec, DuckDB ingest).

</domain>

<decisions>
## Implementation Decisions

### Cancer Category Assignment
- **D-01:** Cancer categories are assigned at the patient level from `cancer_summary.csv` (R/55 output). Group by patient ID to get all distinct cancer categories per patient, then join onto treatment episode rows. No re-querying of DIAGNOSIS/DuckDB needed.
- **D-02:** Comma-separated list format for the `cancer_category` column when a patient has multiple cancer types (e.g., "Hodgkin Lymphoma,Breast"). Matches the existing `triggering_codes` pattern in Gantt data.
- **D-03:** `is_hodgkin` column is TRUE when "Hodgkin Lymphoma" appears anywhere in the comma-separated `cancer_category` value.

### Death Date Integration
- **D-04:** Death dates come from a separate `DEATH_Mailhot_V1.csv` table with columns: ID, DEATH_DATE, DEATH_DATE_IMPUTE, DEATH_SOURCE, DEATH_MATCH_CONFIDENCE, SOURCE.
- **D-05:** Full pipeline integration for the DEATH table: add to `PCORNET_TABLES` in R/00_config.R, define `DEATH_SPEC` in R/01_load_pcornet.R, ingest into DuckDB via R/25_duckdb_ingest.R, query via `get_pcornet_table("DEATH")`.
- **D-06:** Death rows are single-point pseudo-treatment rows: `treatment_type = "Death"`, `episode_start = death_date`, `episode_stop = death_date`, `episode_length_days = 0`, `episode_number = 1`. Other fields (triggering_codes, triggering_code_descriptions) are empty strings.
- **D-07:** Death rows appear in BOTH `gantt_episodes.csv` and `gantt_detail.csv` with the same structure.
- **D-08:** Death dates undergo 1900 sentinel date nullification (same pattern as diagnosis dates). Patients with NULL death dates after sentinel filtering are excluded (no Death row).

### Claude's Discretion
- Column ordering for new columns (cancer_category, is_hodgkin) in the CSVs
- Whether cancer_category list is alphabetically sorted or ordered by code frequency
- Script numbering for the new R/57 script
- Whether DEATH table re-ingest requires a separate step or is part of R/57's setup instructions
- Cancer category for the Death pseudo-treatment row (patient's cancer categories, or NA/empty)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Gantt Export (Primary Modification Target)
- `R/49_gantt_data_export.R` — Current Gantt export script. Loads treatment_episodes.rds + treatment_episode_detail.rds + code_descriptions.rds, writes gantt_episodes.csv and gantt_detail.csv. Phase 57 modifies this script to add cancer_category, is_hodgkin, and death rows.

### Cancer Category Source
- `R/55_cancer_summary_refined.R` lines 69-336 — PREFIX_MAP definition and classify_codes() function. D-codes excluded from output. Phase 57 uses cancer_summary.csv (R/55 output) rather than re-classifying.
- `output/tables/cancer_summary.csv` — Patient-code level data with ID, cancer_code, cancer_category columns. Phase 57 groups by ID to get per-patient cancer categories.

### Confirmed HL Cohort
- `R/55_cancer_summary_refined.R` lines 459-464 — Creates confirmed_hl_cohort.rds (ID, first_hl_dx_date, first_hl_dx_source). Phase 57 consumes this for patient identification.

### Pipeline Infrastructure (for DEATH table)
- `R/00_config.R` lines 108-123 — PCORNET_TABLES vector. Phase 57 adds "DEATH" here.
- `R/01_load_pcornet.R` lines 170-185 — DEMOGRAPHIC_SPEC pattern. Phase 57 adds DEATH_SPEC following this pattern.
- `R/25_duckdb_ingest.R` — DuckDB ingest script. After config changes, user re-runs to add DEATH table.

### Treatment Episode Data
- `R/44a_treatment_episodes.R` — Defines episode extraction and RDS output structure (treatment_episodes.rds, treatment_episode_detail.rds)

### Requirements
- `.planning/REQUIREMENTS.md` — GANTT-01 (cancer category), GANTT-02 (is_hodgkin), GANTT-03 (death dates)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `cancer_summary.csv` (output/tables/): Patient-code level data with ID + cancer_category. Group by ID for per-patient category assignment.
- `confirmed_hl_cohort.rds`: Bridge artifact from Phase 55 — can cross-reference patient IDs.
- `code_descriptions.rds`: Existing lookup pattern for enriching Gantt data. Phase 57 follows same enrichment approach.
- `treatment_episodes.rds` / `treatment_episode_detail.rds`: Input RDS artifacts for Gantt export.

### Established Patterns
- Script independence: Each script copies needed data rather than importing (PREFIX_MAP duplication accepted)
- 1900 sentinel date nullification: Applied in R/02, R/04, R/55. Apply to DEATH_DATE.
- DuckDB-first: All table queries go through `get_pcornet_table()` after DuckDB ingest.
- Column enrichment pattern in R/49: `mutate()` + `sapply()` for lookup-based enrichment.

### Integration Points
- **Input:** `cancer_summary.csv` (patient cancer categories), `DEATH` table via DuckDB (death dates), existing Gantt RDS artifacts
- **Modified:** `R/49_gantt_data_export.R` — adds cancer_category, is_hodgkin columns + death pseudo-treatment rows
- **Modified:** `R/00_config.R` — adds DEATH to PCORNET_TABLES
- **Modified:** `R/01_load_pcornet.R` — adds DEATH_SPEC
- **Output:** Updated `gantt_episodes.csv` and `gantt_detail.csv` with new columns and death rows

</code_context>

<specifics>
## Specific Ideas

- DEATH table columns from user: ID, DEATH_DATE, DEATH_DATE_IMPUTE, DEATH_SOURCE, DEATH_MATCH_CONFIDENCE, SOURCE
- File naming follows existing pattern: `DEATH_Mailhot_V1.csv`
- Cancer category comma-separated format mirrors triggering_codes pattern already established in Phase 48/49

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 57-gantt-enhancements*
*Context gathered: 2026-05-22*
