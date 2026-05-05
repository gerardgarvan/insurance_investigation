# Phase 43: Establish Treatment Lengths for SCT, Chemo, and Radiation - Context

**Gathered:** 2026-05-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Determine treatment duration windows for chemotherapy, radiation, SCT, and immunotherapy using procedure/dispensing/prescribing timestamps from PCORnet CDM tables. Calculate per-patient first-to-last date spans, count distinct treatment dates, and detect separate treatment episodes using gap-based splitting.

</domain>

<decisions>
## Implementation Decisions

### Duration Measurement
- **D-01:** Measure treatment length as first-to-last date span (calendar days between earliest and latest treatment date per patient per type)
- **D-02:** Also report count of distinct treatment dates per patient per type (measures intensity alongside duration)
- **D-03:** Single-date patients included as span=0, count=1 — no special flag needed

### Episode Detection
- **D-04:** Calculate BOTH overall first-to-last span AND detect separate treatment episodes within each type
- **D-05:** 90-day gap threshold defines a new episode (gap of 90+ days between consecutive dates = new course)
- **D-06:** Episode output detail level — Claude's Discretion (choose what fits existing pipeline patterns)

### Output Deliverables
- **D-07:** Per-patient summary tibble saved as RDS artifact (one row per patient per treatment type with first date, last date, span, distinct date count, episode count)
- **D-08:** Styled xlsx report using openxlsx2 (following Phase 41/42 patterns)
- **D-09:** Distribution visualization — histogram or boxplot of treatment durations by type, PNG output
- **D-10:** Console summary statistics during execution (median, IQR, range per type, like existing tidylog-style logging)
- **D-11:** xlsx sheet organization — Claude's Discretion (pick multi-sheet or summary based on data volume)

### Treatment Type Scope
- **D-12:** Cover four treatment types: Chemotherapy, Radiation, SCT, Immunotherapy
- **D-13:** All chemotherapy codes treated as one type — no regimen distinction (ABVD/BV+AVD/salvage all pooled)

### Claude's Discretion
- Episode output granularity (episode summary per patient vs just counts)
- xlsx sheet structure (multi-sheet per type + summary vs single summary)
- Visualization style (histogram vs boxplot vs both)
- Whether to reuse compute functions from R/10_treatment_payer.R or write new extraction logic

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Treatment Code Detection
- `R/00_config.R` lines 412-650+ — TREATMENT_CODES list with all code vectors by type (chemo, radiation, SCT, immunotherapy)
- `R/10_treatment_payer.R` — Treatment date extraction pattern from 7 source tables (PROCEDURES, PRESCRIBING, DIAGNOSIS, ENCOUNTER, DISPENSING, MED_ADMIN, TUMOR_REGISTRY)

### Output Patterns
- `R/41_combine_reports.R` — openxlsx2 workbook creation with styled headers, color-coded rows
- `R/42_treatment_codes_resolved.R` — Per-type xlsx output pattern

### Data Infrastructure
- `R/01_load_pcornet.R` — DuckDB backend with `get_pcornet_table()` dispatcher
- `R/00_config.R` lines 29-75 — CONFIG paths (output_dir, cache dirs)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/10_treatment_payer.R`: Already extracts first treatment dates from 7 source tables per type — can extend to extract ALL dates (remove `min()` aggregation)
- `compute_payer_mode_in_window()`: Window-based join pattern reusable for episode detection
- `TREATMENT_CODES` in config: Complete code lists already defined for all 4 types
- `get_pcornet_table()`: Backend-transparent table access (DuckDB default)
- openxlsx2 styling patterns from R/41_combine_reports.R (TREATMENT_TYPE_COLORS, header styling)

### Established Patterns
- Multi-source date extraction: Query each source independently, stack, then aggregate per patient
- `compact()` + `bind_rows()` for combining nullable source results
- Console logging with `glue()` for counts at each step
- RDS artifacts saved to CONFIG$cache dirs
- PNG output to CONFIG$output_dir

### Integration Points
- Reads from: PROCEDURES, PRESCRIBING, DIAGNOSIS, ENCOUNTER, DISPENSING, MED_ADMIN, TUMOR_REGISTRY via get_pcornet_table()
- Depends on: `source("R/00_config.R")` for TREATMENT_CODES and CONFIG
- Outputs to: CONFIG$output_dir (xlsx, PNG), CONFIG$cache$outputs_dir (RDS)

</code_context>

<specifics>
## Specific Ideas

- Extend the multi-source date extraction pattern from R/10_treatment_payer.R but collect ALL dates instead of just min()
- 90-day gap threshold aligns with HL treatment patterns (ABVD cycles are ~28 days, so 90 days is ~3 missed cycles)
- SCT typically has very few dates (often 1) — expect short spans and mostly 1 episode

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 43-establish-treatment-lengths-for-sct-chemo-and-radiation*
*Context gathered: 2026-05-05*
