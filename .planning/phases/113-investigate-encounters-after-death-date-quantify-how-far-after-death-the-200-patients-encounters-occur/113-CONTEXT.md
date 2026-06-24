# Phase 113: Investigate encounters after death date - Context

**Gathered:** 2026-06-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Drill-down investigation of the ~200 patients already flagged with post-death clinical activity. Quantify how far after the recorded death date each encounter/diagnosis/treatment occurs. Produce a meeting-ready xlsx with summary distribution and per-encounter detail.

</domain>

<decisions>
## Implementation Decisions

### Output Structure
- **D-01:** Two-sheet xlsx output. Sheet 1: per-patient summary (one row per patient with count of post-death events, min/max/median gap in days, bucket assignment). Sheet 2: per-encounter detail (every individual post-death event with exact date and gap from death date in raw days).
- **D-02:** Investigation script pattern (standalone, reads existing artifacts, no upstream modification) -- consistent with R/59, R/58, R/30.

### Time Bucketing
- **D-03:** Gap distribution presented using clinically meaningful bucketed ranges: 0-30 days, 31-90 days, 91-365 days, >1 year. Summary sheet shows patient count per bucket.
- **D-04:** Detail sheet includes raw days_after_death column (exact days) alongside the bucket label so users can re-bucket in Excel if needed.

### Clinical Scope
- **D-05:** All three clinical activity types included: ENCOUNTER admits, DIAGNOSIS records, and treatment episodes. Mirrors the scope R/53 already checks.
- **D-06:** Each post-death event row should identify its source table (ENCOUNTER, DIAGNOSIS, TREATMENT) so the user can filter by activity type.

### Claude's Discretion
- Styled xlsx headers following existing meeting-presentable pattern (dark gray FF374151, white bold text, freeze panes)
- Whether to add a third summary sheet with bucket distribution cross-tabbed by activity type
- R/88 smoke test section additions

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Death Date Infrastructure
- `R/53_death_date_validation.R` -- Produces `validated_death_dates.rds` with post_death_activity flag, post_death_encounters/diagnoses/treatments counts, latest_post_death_encounter dates. Primary upstream data source.
- `R/59_death_date_summary.R` -- Phase 103 cross-tab summary. Pattern reference for standalone investigation script with styled xlsx.
- `R/29_first_line_and_death_analysis.R` -- Original death date analysis with DEATH-01/02/03 metrics.

### Data Sources
- `cache/outputs/validated_death_dates.rds` -- Pre-validated death dates with post_death_activity boolean
- DuckDB ENCOUNTER table (ADMIT_DATE for post-death encounter detection)
- DuckDB DIAGNOSIS table (DX_DATE for post-death diagnosis detection)
- `cache/outputs/treatment_episodes.rds` -- Treatment episodes (episode_start for post-death treatment detection)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/53 Section 5` already computes post-death encounters, diagnoses, and treatments with patient-level counts and latest dates -- this logic can be reused/extended
- `validated_death_dates.rds` already has post_death_activity boolean, post_death_encounters count, and latest_post_death_encounter date per patient
- `R/utils/utils_duckdb.R` (get_pcornet_table, open/close_pcornet_con) for DuckDB access
- `R/utils/utils_dates.R` (parse_pcornet_date) for date parsing
- `R/utils/utils_assertions.R` (assert_rds_exists, assert_df_valid) for input validation
- openxlsx2 styled xlsx pattern from R/59 (dark gray headers, freeze panes, number formatting)

### Established Patterns
- Investigation scripts are standalone (source R/00_config.R, read cached RDS/DuckDB, write xlsx to output/)
- R/53 already identifies the patient population; this phase drills into the detail
- Meeting-presentable xlsx styling: Calibri, dark gray headers FF374151, white bold text, freeze panes, #,##0 number format

### Integration Points
- Reads from: `validated_death_dates.rds` (R/53 output), DuckDB ENCOUNTER/DIAGNOSIS tables, `treatment_episodes.rds`
- Writes to: `output/post_death_encounter_investigation.xlsx` (new file)
- R/88 smoke test: new section validating script output structure
- R/39 pipeline runner: add new script to investigation block

</code_context>

<specifics>
## Specific Ideas

- User noted "200 something patients" -- the exact count comes from R/53/R/59 post_death_activity flag
- Primary question is "how far after the death the encounter" -- the gap in days/time is the core deliverable
- This is a data quality investigation, not a clinical analysis -- the goal is to understand whether post-death records are data artifacts (e.g., claims lag) or truly anomalous

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 113-investigate-encounters-after-death-date-quantify-how-far-after-death-the-200-patients-encounters-occur*
*Context gathered: 2026-06-24*
