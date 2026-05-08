# Phase 44: Treatment Episode Start/Stop Dates - Context

**Gathered:** 2026-05-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce per-patient, per-episode start and stop dates for each 90-day treatment period with episode length. Special handling for isolated historical treatment dates (tumor registry records from 1970s-2000s) that fall outside the 2012-2025 data window. This is a NEW detail-level output alongside Phase 43's existing per-patient summary — Phase 43 outputs are not modified.

</domain>

<decisions>
## Implementation Decisions

### Historical Date Handling
- **D-01:** Include historical episodes in the same output but flag them with a boolean `historical_flag` column
- **D-02:** Historical cutoff = before 2012 (matches OneFlorida+ data extraction period start)
- **D-03:** An episode is flagged historical when ALL its dates fall before 2012-01-01
- **D-04:** Historical episodes get start=stop=that date, length=0 for single-date records (consistent with Phase 43 D-03)

### Output Structure
- **D-05:** New per-episode output alongside Phase 43's per-patient summary — Phase 43 stays unchanged
- **D-06:** New R script `R/44_treatment_episodes.R` (separate from R/43)
- **D-07:** Output deliverables: RDS artifact + styled xlsx + per-type CSVs (following Phase 43 patterns)

### Episode Columns
- **D-08:** Per-episode row columns: `patient_id`, `treatment_type`, `episode_number`, `episode_start`, `episode_stop`, `episode_length_days`, `distinct_dates_in_episode`, `historical_flag`
- **D-09:** One row per patient per treatment type per episode

### Carried Forward from Phase 43
- **D-10:** 90-day gap threshold for episode splitting (Phase 43 D-05)
- **D-11:** All chemo codes pooled, no regimen distinction (Phase 43 D-13)
- **D-12:** Four treatment types: Chemotherapy, Radiation, SCT, Immunotherapy (Phase 43 D-12)
- **D-13:** Pre-2000 dates are real tumor registry data, not sentinels (STATE.md key decision)

### Claude's Discretion
- How to share date extraction logic with R/43 (source R/43 functions, refactor to shared helper, or duplicate)
- xlsx sheet organization (summary + per-type, or flat)
- Whether to include a summary statistics console output like Phase 43's D-10

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 43 Implementation (Direct Predecessor)
- `R/43_treatment_durations.R` — Contains `extract_all_dates()` and `calculate_durations_and_episodes()` functions. The per-episode intermediate data (lines 486-492) is exactly what Phase 44 needs to output instead of collapsing.
- `R/43_test_durations.R` — Validation checks pattern for treatment duration data

### Treatment Code Detection
- `R/00_config.R` lines 412-650+ — TREATMENT_CODES list with all code vectors by type
- `R/10_treatment_payer.R` — Original treatment date extraction pattern from 7 source tables

### Output Patterns
- `R/41_combine_reports.R` — openxlsx2 workbook styling patterns (TREATMENT_TYPE_COLORS)
- `R/42_treatment_codes_resolved.R` — Per-type xlsx output pattern with write_resolved_xlsx()

### Data Infrastructure
- `R/01_load_pcornet.R` — DuckDB backend with `get_pcornet_table()` dispatcher
- `R/00_config.R` lines 29-75 — CONFIG paths (output_dir, cache dirs)

### Phase 43 Context
- `.planning/phases/43-establish-treatment-lengths-for-sct-chemo-and-radiation/43-CONTEXT.md` — Prior decisions D-01 through D-13

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/43_treatment_durations.R` `extract_all_dates(type)`: Already extracts ALL treatment dates from 7 sources per type — directly reusable
- `R/43_treatment_durations.R` `calculate_durations_and_episodes()` lines 476-492: Already computes per-episode `episode_first_date`, `episode_last_date`, `episode_span_days`, `episode_distinct_dates` — this intermediate result IS the Phase 44 output shape (before the final collapse to per-patient summary)
- `TREATMENT_TYPE_COLORS` in R/43: Color scheme for xlsx styling, reusable
- `GAP_THRESHOLD <- 90` in R/43: Episode splitting threshold

### Established Patterns
- Multi-source date extraction: Query each source independently, stack, then aggregate
- `compact()` + `bind_rows()` for combining nullable source results
- Console logging with `glue()` for counts at each step
- RDS artifacts saved to CONFIG$cache$outputs_dir
- PNG output to CONFIG$output_dir
- Per-type CSV output to CONFIG$output_dir with snake_case column names

### Integration Points
- Reads from: Same 7 PCORnet tables as Phase 43 via `get_pcornet_table()`
- Depends on: `source("R/00_config.R")` for TREATMENT_CODES and CONFIG
- Can source or call Phase 43's extraction functions to avoid duplication
- Outputs to: CONFIG$output_dir (xlsx, CSV), CONFIG$cache$outputs_dir (RDS)

</code_context>

<specifics>
## Specific Ideas

- The key code change vs Phase 43: stop at the per-episode `summarise()` (lines 486-492) instead of collapsing to per-patient summary — then add `historical_flag` and `episode_number`
- Tumor registry dates from 1970s/1980s/1990s/early 2000s should be easy to identify — they'll be isolated single-date episodes with large gaps from the 2012+ treatment data
- Historical flag should be usable as a simple filter: `filter(!historical_flag)` to get only modern episodes

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 44-treatment-episode-start-stop-dates*
*Context gathered: 2026-05-07*
