# Phase 28: Per-Patient Source Detection by Date - Context

**Gathered:** 2026-04-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Redo the Phase 25-26 multi-source overlap approach using a simpler per-date source enumeration strategy. Instead of pairwise encounter comparisons, for each patient on each date, detect which ENCOUNTER.SOURCE values are present and how many encounters each source contributes. Output patient-date detail (all dates including single-source), source combination frequency summaries, and per-source aggregate counts. Same-date grouping only (no same-week window).

</domain>

<decisions>
## Implementation Decisions

### Output Granularity
- **D-01:** Patient-date detail CSV with one row per (patient, date) showing n_sources, source_combo, n_encounters. Include ALL dates (1+ sources), not just multi-source dates -- full picture with ability to filter downstream.
- **D-02:** Also produce aggregate summary CSVs: source combination frequencies and per-source summary counts. Mirrors Phase 25 output structure but based on source-per-date grouping instead of pairwise detection.

### Fields Captured
- **D-03:** Source detection only -- each patient-date gets n_sources, source_combo (alphabetical), n_encounters per source. No field comparison (ENC_TYPE, payer, provider) -- that was Phase 26's pairwise concern and is being replaced by this simpler approach.

### Temporal Scope
- **D-04:** Same-date grouping only (patient + ADMIT_DATE). No same-week or rolling window detection. Directly answers "which sources were on each date" without the complexity of near-miss overlap detection.

### Performance
- **D-05:** Use data.table for data manipulation instead of dplyr. Speed is the priority for this script. This overrides the project-wide "prefer dplyr for readability" convention specifically for this Phase 28 script.

### Claude's Discretion
- Script naming and numbering (follow existing convention: R/24_*.R or next available number)
- Console output formatting (follow existing Phase 25/26 banner and summary patterns)
- HIPAA suppression approach (carry forward Phase 25 pattern: suppress CSV count columns 1-10 as "<11")
- Whether to include an n_encounters_per_source breakdown column or just total n_encounters

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 25-26 Scripts (being replaced/simplified)
- `R/22_multi_source_overlap_detection.R` -- Phase 25 pairwise same-date and same-week overlap detection. This script's approach is being simplified by Phase 28.
- `R/23_overlap_classification.R` -- Phase 26 field-by-field classification. Phase 28 replaces this with source enumeration only.

### Pipeline Infrastructure
- `R/00_config.R` -- CONFIG object, output_dir, library loading
- `R/01_load_pcornet.R` -- pcornet table loading (ENCOUNTER, DEMOGRAPHIC)
- `R/utils_dates.R` -- parse_pcornet_date() fallback for ADMIT_DATE parsing

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/22_multi_source_overlap_detection.R`: ADMIT_DATE parsing logic (lines 86-108), HIPAA suppression helpers (lines 47-60), encounter loading pattern (lines 73-114)
- `R/00_config.R`: CONFIG$output_dir for CSV output path
- `R/01_load_pcornet.R`: pcornet$ENCOUNTER table loading

### Established Patterns
- Standalone diagnostic scripts source R/00_config.R and conditionally source R/01_load_pcornet.R
- Console output uses glue() message() with section banners, summary blocks
- CSV outputs go to output/tables/ with descriptive filenames
- HIPAA suppression replaces count values 1-10 with "<11" in CSV only

### Integration Points
- Reads from pcornet$ENCOUNTER (ID, ENCOUNTERID, ADMIT_DATE, SOURCE)
- Writes CSVs to output/tables/
- No downstream script consumes this output (standalone investigation)

</code_context>

<specifics>
## Specific Ideas

- User explicitly requested data.table for speed: "use whatever data manipulation is fastest you don't need to use dplyr you can use data.table"
- The fundamental shift: Phase 25 did pairwise source comparisons (A+B, A+C) with self-joins; Phase 28 simply groups by (patient, date) and lists all sources present -- no joins needed

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 28-per-patient-source-detection-by-date*
*Context gathered: 2026-04-23*
