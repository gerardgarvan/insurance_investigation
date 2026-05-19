# Phase 1: Combine Treatment Episode and Detail for Gantt Chart — Context

**Gathered:** 2026-05-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Combine existing treatment episode data (episode-level start/stop) with treatment episode detail data (per-date granularity) into a Gantt-chart-ready dataset. This is a **data preparation** phase — no visualization code. The output CSVs will be consumed by a third party for plotting.

</domain>

<decisions>
## Implementation Decisions

### Data Structure
- **D-01:** Two-table output: (1) episode-level "bars" table with patient_id, treatment_type, episode_number, episode_start, episode_stop, episode_length_days, distinct_dates_in_episode, historical_flag, triggering_codes; (2) detail-level "ticks" table with patient_id, treatment_type, treatment_date, triggering_code, episode_number, episode_start, episode_stop, historical_flag
- **D-02:** One row per code in the detail table — if a patient has 3 treatment codes on one date, that's 3 rows. Preserves full granularity for the consumer.
- **D-03:** Separate rows by treatment type — concurrent treatments (e.g., chemo overlapping radiation) appear as separate rows. No overlap flag needed; the plotter handles overlap visually.

### Scope
- **D-04:** All HL patients with at least one treatment episode are included — full cohort, no filtering. Third party handles any subsetting.
- **D-05:** No payer tier data included in this phase. May be added in a future phase.

### Output Format
- **D-06:** CSV output only — two files: `gantt_episodes.csv` (bars) and `gantt_detail.csv` (ticks). Universal format for any plotting tool.

### Data Sources
- **D-07:** Load from existing RDS artifacts: `cache/outputs/treatment_episodes.rds` (episode-level) and `cache/outputs/treatment_episode_detail.rds` (detail-level). No re-extraction from raw PCORnet tables.

### Claude's Discretion
- Column ordering within the CSVs
- Whether to add any derived columns useful for Gantt plotting (e.g., patient row index, episode label)
- Script naming convention (following existing R/NN_*.R pattern)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Treatment Episode Data
- `R/44_treatment_episodes.R` — Defines episode extraction and RDS output structure
- `R/43_treatment_durations.R` — Defines date extraction functions and assign_episode_ids() logic

### Configuration
- `R/00_config.R` — TREATMENT_TYPES, TREATMENT_TYPE_COLORS, GAP_THRESHOLD constants (lines ~1454-1469)

### Shared Utilities
- `R/utils_treatment.R` — safe_table, get_hl_patient_ids, empty_result, nrow_or_0 helpers

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `treatment_episodes.rds` — Episode-level data (patient_id, treatment_type, episode_number, episode_start, episode_stop, episode_length_days, distinct_dates_in_episode, historical_flag, triggering_codes)
- `treatment_episode_detail.rds` — Detail-level data (patient_id, treatment_type, treatment_date, triggering_code, episode_number, episode_start, episode_stop, historical_flag)
- `TREATMENT_TYPE_COLORS` in config — Hex colors per type (strip FF prefix for ggplot2 if ever needed)

### Established Patterns
- RDS-to-output pipeline: load RDS artifact, transform, write CSV (used throughout R/43-R/46)
- Script numbering: R/NN_descriptive_name.R
- Output directory: output/ for final CSV/xlsx files

### Integration Points
- Input: `cache/outputs/treatment_episodes.rds` and `cache/outputs/treatment_episode_detail.rds`
- Output: `output/gantt_episodes.csv` and `output/gantt_detail.csv`
- No downstream R scripts depend on this output (consumed by third party)

</code_context>

<specifics>
## Specific Ideas

- The two RDS files already contain the data needed — this phase is primarily a load-and-write operation with minimal transformation
- The detail table's one-row-per-code granularity matches the existing `treatment_episode_detail.rds` structure (D-46-07 requirement preserved)

</specifics>

<deferred>
## Deferred Ideas

- Payer tier integration — joining Phase 46 date-level payer data onto the Gantt detail table (user noted "might be implemented in future")
- Actual Gantt chart visualization code (ggplot2, plotly, etc.) — third party handles plotting

</deferred>

---

*Phase: 01-combine-treatment-episode-and-treatment-episode-detail-to-make-gantt-chart-of-each-patient-treatment*
*Context gathered: 2026-05-19*
