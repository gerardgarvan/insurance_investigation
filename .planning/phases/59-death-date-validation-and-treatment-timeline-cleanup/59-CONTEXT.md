# Phase 59: Death Date Validation & Treatment Timeline Cleanup - Context

**Gathered:** 2026-05-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Validate death dates against treatment timelines to identify and exclude impossible pre-treatment deaths, flag patients with post-death clinical activity, investigate patients who have death dates but no treatment records (full clinical timeline with HL validity and care gap analysis), add first HL diagnosis date as a pseudo-treatment row in Gantt CSVs, and produce validated death date artifacts for downstream use.

</domain>

<decisions>
## Implementation Decisions

### Death Date Validation Rules
- **D-01:** A death date is "impossible" when it occurs before the patient's EARLIEST treatment date across all treatment types (chemotherapy, radiation, SCT, immunotherapy). Patients cannot die before starting treatment and still have treatment records after.
- **D-02:** Impossible death dates are REMOVED from the Gantt CSVs entirely — the death pseudo-treatment row is dropped. The patient retains their treatment rows but has no death endpoint.
- **D-03:** Post-death clinical activity is FLAGGED but not auto-excluded. Check ENCOUNTER, DIAGNOSIS, and treatment tables for any records occurring after the death date. Surface these patients in the report for manual review.
- **D-04:** 1900 sentinel date filtering remains in place (established pattern from Phase 57).

### Death-Only Patient Investigation
- **D-05:** Patients with death dates but no treatment records receive a full clinical timeline investigation: all available data including demographics, diagnoses, encounters, and enrollment.
- **D-06:** Two clinical questions to answer: (1) Are these patients real HL patients — do they meet the 2+ codes / 7-day confirmation threshold? (2) Why do they have no treatment records — did they die before treatment, are they from death-only sources (VRT), or are there gaps in care?

### HL Diagnosis as Treatment Row
- **D-07:** Add `first_hl_dx_date` as a pseudo-treatment row in both `gantt_episodes.csv` and `gantt_detail.csv`, using `treatment_type = "HL Diagnosis"`. Single-point event, same structure as Death rows (episode_length_days = 0, episode_number = 1).
- **D-08:** HL Diagnosis rows appear for ALL patients with any HL diagnosis code, not only the confirmed 7-day cohort. Uses the earliest HL date from DIAGNOSIS and/or TUMOR_REGISTRY.
- **D-09:** The HL Diagnosis row provides a timeline reference point so the Gantt chart shows when HL was first diagnosed relative to treatments and death.

### Output Format
- **D-10:** Both styled xlsx AND CSV output. Multi-sheet xlsx: Sheet 1 = validation summary (counts of impossible dates, post-death activity flags), Sheet 2 = patient-level detail of flagged patients, Sheet 3 = death-only patient investigation with full clinical timeline.
- **D-11:** Population is ALL patients with death dates, regardless of HL confirmation status. Broadest view of data quality.
- **D-12:** Save `validated_death_dates.rds` artifact containing cleaned death dates (impossible dates removed, post-death activity flags included) for downstream scripts to consume.

### Claude's Discretion
- Script numbering (R/59_*.R or similar)
- Column ordering in xlsx sheets
- Whether to modify R/49_gantt_data_export.R in place (adding HL Diagnosis rows and death validation) or create a separate validation script that R/49 consumes
- Summary statistics to include in the validation overview sheet
- Exact schema of validated_death_dates.rds (minimum: ID, DEATH_DATE, death_valid flag, post_death_activity flag)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Death Data Infrastructure (Phase 57)
- `R/49_gantt_data_export.R` lines 394-424 — Current death data loading, parsing, sentinel filtering, deduplication
- `R/49_gantt_data_export.R` lines 518-611 — Death pseudo-treatment row construction and Gantt CSV appending
- `R/01_load_pcornet.R` lines 188-201 — DEATH_SPEC column specification (6 columns)

### Treatment Episode Data
- `R/44a_treatment_episodes.R` — Episode extraction, start/stop dates, 90-day gap detection. Source of treatment_episodes.rds and treatment_episode_detail.rds
- `R/43a_treatment_durations.R` — Treatment type definitions (Chemotherapy, Radiation, SCT, Immunotherapy) and date extraction functions

### HL Cohort and Diagnosis
- `R/55_cancer_summary_refined.R` lines 459-464 — confirmed_hl_cohort.rds creation (ID, first_hl_dx_date, first_hl_dx_source)
- `output/tables/cancer_summary.csv` — Patient-code level cancer data with cancer_category

### Date Handling
- `R/utils_dates.R` lines 33-124 — parse_pcornet_date() multi-format parser
- Sentinel date pattern: `if_else(year(date) == 1900L, as.Date(NA), date)` — used across R/02, R/04, R/49, R/55

### User Notes
- `notes5282026.txt` — Original problem description: death before treatment, death-only patients
- `example_of_patient_with_impossible_death_date.PNG` — Screenshot of impossible death date in data

### DuckDB Backend
- `R/utils_duckdb.R` lines 162-203 — get_pcornet_table() dispatcher for DEATH, ENCOUNTER, DIAGNOSIS queries

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `parse_pcornet_date()` (R/utils_dates.R): Multi-format date parser already handles DEATH_DATE format
- `get_pcornet_table()` (R/utils_duckdb.R): DuckDB-first table access for DEATH, ENCOUNTER, DIAGNOSIS
- `confirmed_hl_cohort.rds`: Contains first_hl_dx_date per confirmed patient — reusable for HL Diagnosis rows
- Death pseudo-treatment row pattern (R/49 lines 532-572): Established pattern to follow for HL Diagnosis rows
- 1900 sentinel filtering pattern: Reuse `if_else(year(date) == 1900L, as.Date(NA), date)`

### Established Patterns
- Pseudo-treatment row structure: treatment_type label, episode_start = episode_stop = event_date, episode_length_days = 0, episode_number = 1, empty triggering_codes
- DuckDB-first queries via open_pcornet_con() / get_pcornet_table() / close_pcornet_con()
- Styled xlsx output with openxlsx2 (headers, column widths, freezePane)
- RDS artifacts saved to blue storage path for downstream consumption

### Integration Points
- **Input:** DEATH table (DuckDB), treatment_episodes.rds, treatment_episode_detail.rds, confirmed_hl_cohort.rds, ENCOUNTER table, DIAGNOSIS table
- **Modified:** R/49_gantt_data_export.R — add death date validation (remove impossible dates before Gantt export) + add HL Diagnosis pseudo-treatment rows
- **New output:** death_date_validation.xlsx, death_date_validation.csv, validated_death_dates.rds
- **Modified output:** gantt_episodes.csv, gantt_detail.csv (impossible death rows removed, HL Diagnosis rows added)

</code_context>

<specifics>
## Specific Ideas

- The screenshot (example_of_patient_with_impossible_death_date.PNG) shows a patient where a death date appears chronologically impossible relative to chemotherapy/radiation records
- User specifically wants to understand "what other information is about patients that only have a death date and no treatments" — full characterization, not just counts
- The HL Diagnosis row concept mirrors the Death row pattern from Phase 57 — a clinical milestone shown as a pseudo-treatment for Gantt visualization

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 59-death-date-validation-and-treatment-timeline-cleanup*
*Context gathered: 2026-05-28*
