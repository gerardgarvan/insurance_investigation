# Phase 62: First-Line Therapy & Death Analysis - Context

**Gathered:** 2026-05-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Identify first-line chemotherapy therapy for adult HL patients (21+ at treatment date) using a 60-day clean period with no prior chemotherapy, and produce death date analysis summary tables quantifying data quality (patients with death dates, death as last encounter, post-death encounters stratified by ENC_TYPE). Builds on Phase 61's regimen labels and Phase 59's validated death dates.

</domain>

<decisions>
## Implementation Decisions

### First-Line Therapy Eligibility
- **D-01:** First-line flag applies ONLY to chemotherapy episodes that Phase 61 labeled with a regimen name (ABVD, BV+AVD, Nivo+AVD). Unlabeled chemotherapy episodes do not receive a first-line flag.
- **D-02:** Age 21+ is calculated at episode_start date using DEMOGRAPHIC.BIRTH_DATE. Patients under 21 at their chemotherapy episode start are excluded from first-line consideration.
- **D-03:** 60-day clean period = no chemotherapy of any kind in the 60 days before the episode_start date. Only chemotherapy is checked (not radiation, SCT, or immunotherapy). Any prior chemo date within that window disqualifies the episode.
- **D-04:** Only the FIRST qualifying episode per patient gets is_first_line=TRUE. All subsequent chemotherapy episodes for the same patient are is_first_line=FALSE, even if they individually satisfy the 60-day lookback.

### Death Analysis Tables
- **D-05:** Death analysis uses VALIDATED deaths only (death_valid=TRUE from validated_death_dates.rds). Impossible deaths (before earliest treatment) are excluded from all counts.
- **D-06:** "Death is the last encounter" (DEATH-02) is defined by comparing DEATH_DATE to max(ADMIT_DATE) from the ENCOUNTER table. Death is "last" when no ENCOUNTER record exists after the death date.
- **D-07:** Post-death encounter stratification (DEATH-03) is by PCORnet ENC_TYPE (AV, TH, ED, IP, IS, OA, etc.). Shows which encounter settings have records occurring after the death date.
- **D-08:** Phase 62 references Phase 59's post_death_activity flag for the total post-death count. Only queries ENCOUNTER table for the NEW ENC_TYPE stratification detail (avoids re-detecting post-death activity already captured in Phase 59).

### Output Strategy
- **D-09:** is_first_line boolean column added to existing treatment_episodes.rds in-place. Phase 63 picks it up automatically when building Gantt v2 files.
- **D-10:** Death analysis output: styled multi-sheet xlsx (openxlsx2) + flat CSV. Sheet 1 = summary counts (DEATH-01: total with death dates, DEATH-02: death as last encounter, DEATH-03: total with post-death encounters). Sheet 2 = ENC_TYPE stratification detail.
- **D-11:** Single combined script R/62_first_line_and_death_analysis.R handles both first-line flagging and death analysis. Shared data dependencies (treatment_episodes.rds, demographics) justify combining.

### Relationship to Phase 59
- **D-12:** Phase 62 loads validated_death_dates.rds as input — does NOT re-query DEATH table or re-validate. Phase 59 already did the heavy lifting (sentinel filtering, impossible death detection, post-death flagging).
- **D-13:** The 3 death analysis counts (DEATH-01/02/03) are new summary metrics not present in Phase 59's output. Phase 59 produced patient-level detail; Phase 62 produces aggregate counts.

### Claude's Discretion
- Column ordering for is_first_line in treatment_episodes.rds
- xlsx sheet styling (colors, column widths, freeze panes)
- Console logging detail level during analysis
- Whether to also produce a first-line summary table in the xlsx (patient-level first-line detail alongside death analysis)
- How to handle edge case where a patient has no ENCOUNTER records at all (for DEATH-02 comparison)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Treatment Episode Data (Primary Input)
- `R/44a_treatment_episodes.R` — Episode extraction with triggering codes, encounter_ids, drug_names. Contains `calculate_episodes_detailed()` for episode splitting. Produces treatment_episodes.rds and treatment_episode_detail.rds.
- `R/43a_treatment_durations.R` — Treatment type definitions and date extraction functions for Chemotherapy, Radiation, SCT, Immunotherapy.

### Death Date Validation (Phase 59 Input)
- `R/59_death_date_validation.R` — Death date validation logic, produces validated_death_dates.rds with death_valid and post_death_activity flags. Age calculation pattern using DEMOGRAPHIC.BIRTH_DATE.
- `.planning/phases/59-death-date-validation-and-treatment-timeline-cleanup/59-CONTEXT.md` — Phase 59 decisions on death validation rules, impossible death definition, post-death activity flagging.

### Phase 60 Foundation (Recent Modifications)
- `.planning/phases/60-foundation-encounterid-propagation-and-drug-name-resolution/60-CONTEXT.md` — ENCOUNTERID propagation, drug name resolution decisions. treatment_episodes.rds schema now includes encounter_ids and drug_names columns.

### Demographics and HL Cohort
- `R/01_load_pcornet.R` — Column specs for DEMOGRAPHIC table (BIRTH_DATE for age calculation)
- `R/55_cancer_summary_refined.R` lines 459-464 — confirmed_hl_cohort.rds creation (ID, first_hl_dx_date, first_hl_dx_source)

### Configuration
- `R/00_config.R` — TREATMENT_CODES, TREATMENT_TYPES, GAP_THRESHOLD, output paths

### Infrastructure
- `R/utils_duckdb.R` — get_pcornet_table() dispatcher for DEMOGRAPHIC and ENCOUNTER queries
- `R/utils_dates.R` — parse_pcornet_date() for BIRTH_DATE and date comparisons

### Requirements
- `.planning/REQUIREMENTS.md` — FLT-01 (first-line for adults 21+), FLT-02 (60-day clean period), DEATH-01 (death count), DEATH-02 (death as last encounter), DEATH-03 (post-death encounters stratified)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `validated_death_dates.rds` (Phase 59): Pre-validated death dates with death_valid and post_death_activity flags — direct input for death analysis
- `treatment_episodes.rds` (Phase 44a/60): Episode-level data with start/stop dates, drug_names, encounter_ids — input for first-line analysis
- Age calculation pattern (R/59): `as.numeric(difftime(date, BIRTH_DATE, units = "days")) / 365.25` — reuse for 21+ filter
- openxlsx2 styled xlsx pattern (R/59, R/55, R/53): Multi-sheet workbook with color headers, freeze panes, column widths
- DuckDB queries via get_pcornet_table() for DEMOGRAPHIC and ENCOUNTER tables

### Established Patterns
- RDS artifact enrichment: Phase 60 added columns to treatment_episodes.rds in-place (encounter_ids, drug_names) — same pattern for is_first_line
- Console logging with glue() at each step
- RDS saved to CONFIG$cache$outputs_dir, xlsx/csv to output/ directory
- 1900 sentinel date filtering: `if_else(year(date) == 1900L, as.Date(NA), date)`

### Integration Points
- **Input:** treatment_episodes.rds (from R/44a + Phase 60 enrichment + Phase 61 regimen labels), validated_death_dates.rds (from R/59), DEMOGRAPHIC table (DuckDB), ENCOUNTER table (DuckDB)
- **Modified:** treatment_episodes.rds (+ is_first_line column)
- **New:** R/62_first_line_and_death_analysis.R, death_analysis.xlsx, death_analysis.csv
- **Downstream:** Phase 63 reads is_first_line from treatment_episodes.rds for Gantt v2

</code_context>

<specifics>
## Specific Ideas

- The 60-day clean period lookback checks against ALL chemotherapy dates for the patient (from treatment_episode_detail.rds), not just episode start dates — individual chemo dates within a prior episode that fall within 60 days of the new episode start would disqualify
- Phase 61's regimen labels are the gatekeeper: an episode must have a regimen label AND satisfy the 60-day clean period AND be for a 21+ patient to get is_first_line=TRUE
- Death analysis tables are informational/data quality metrics — they quantify how reliable the death date field is in the PCORnet extract, which informs downstream interpretation

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 62-first-line-therapy-and-death-analysis*
*Context gathered: 2026-05-30*
