# Phase 26: Overlap Classification and Recommendations - Context

**Gathered:** 2026-04-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Classify each multi-source encounter group (same-date and same-week) as Identical, Partial, or Distinct via field-by-field comparison. Produce CSV outputs with per-pair classification detail, per-site aggregate overlap profiles, a console summary, and per-site actionable recommendations on whether to deduplicate or retain encounters (with preferred source suggestion).

</domain>

<decisions>
## Implementation Decisions

### Missing field treatment
- **D-01:** Both NA = match. If both encounters in a pair have NA/missing for the same field, treat as agreement (shared absence = consistency).
- **D-02:** One NA, one present = mismatch. If one encounter has a value and the other has NA, treat as disagreement.
- **D-03:** Normalize payer sentinels before comparison. Convert all payer missing sentinels (NI, UN, OT, 99, 9999, empty string) to NA before comparing PAYER_TYPE_PRIMARY and PAYER_TYPE_SECONDARY. Consistent with Phase 19 `is_missing_payer()` definition.

### Classification thresholds
- **D-04:** 5 fields compared for same-date pairs: ENC_TYPE, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY, PROVIDERID, DISCHARGE_DATE.
- **D-05:** Identical = all compared fields match (5/5 for same-date, 4/4 for same-week). Partial = 1 to N-1 fields match. Distinct = 0 fields match.
- **D-06:** Include raw match count alongside label: e.g., "Partial (3/5)" so analyst can drill into granularity of partial matches.

### Recommendation logic
- **D-07:** Per-site recommendation thresholds based on % Identical among same-date multi-source groups:
  - >=70% Identical: "Safe to deduplicate by keeping preferred source"
  - 30-69% Identical: "Mixed overlap — review partial matches before deduplication"
  - <30% Identical: "Encounters are largely distinct — retain all"
- **D-08:** Include preferred source suggestion for deduplication. For sites where deduplication is recommended, suggest which ENCOUNTER.SOURCE to keep based on payer completeness comparison (derived from the field comparison data within this phase).

### Same-week comparison
- **D-09:** Exclude DISCHARGE_DATE from same-week field comparison. Compare only 4 fields: ENC_TYPE, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY, PROVIDERID. Different admit dates likely mean different discharge dates — including it adds noise.
- **D-10:** Use same Identical/Partial/Distinct labels for same-week, with a `basis` column noting "same_date (5 fields)" vs "same_week (4 fields)" so the denominator difference is transparent.

### Claude's Discretion
- Exact join strategy for reading Phase 25 CSVs and joining back to ENCOUNTER table for field extraction
- Console summary formatting and verbosity
- CSV column naming and ordering
- How to compute preferred source from field comparison data (e.g., which source has more non-NA payer values across overlapping encounters)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 25 detection output (input to this phase)
- `R/22_multi_source_overlap_detection.R` — Phase 25 script producing the 4 input CSVs
- `output/tables/multi_source_same_date_detail.csv` — Same-date detail: ID, ADMIT_DATE, n_sources, n_encounters, source_combo, sources_list
- `output/tables/multi_source_same_week_detail.csv` — Same-week detail: ID, admit_date_1, source_1, admit_date_2, source_2, day_gap, source_combo
- `output/tables/multi_source_per_source_summary.csv` — Per-source aggregate counts

### Prior phase patterns
- `R/21_all_site_duplicate_dates.R` — Phase 22 pattern for `is_missing_payer()` helper and per-site source recommendations
- `R/00_config.R` — CONFIG object, output_dir, payer sentinel definitions
- `R/01_load_pcornet.R` — Table loading infrastructure

### Requirements
- `.planning/REQUIREMENTS.md` — OVRLP-01 through OVRLP-04, OUTPT-01 through OUTPT-03

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/22_multi_source_overlap_detection.R`: Standalone script pattern (source config, conditional load, HIPAA helpers, section-based structure with console output)
- `hipaa_suppress()` and `suppress_counts()` functions in Phase 25 script — reusable or copy-paste
- `is_missing_payer()` in `R/21_all_site_duplicate_dates.R` — payer sentinel normalization logic

### Established Patterns
- Standalone diagnostic scripts: source `00_config.R`, conditionally source `01_load_pcornet.R`
- Console output: `message()` + `glue()` with section headers (`strrep('=', 70)`)
- CSV output: `readr::write_csv()` to `output/tables/`
- HIPAA suppression on CSV count columns only; console retains raw values

### Integration Points
- Reads Phase 25 CSVs (same-date detail, same-week detail) as input
- Joins back to raw `pcornet$ENCOUNTER` to extract the 5 comparison fields per encounter
- Output CSVs could feed a future PPTX phase for visualization

</code_context>

<specifics>
## Specific Ideas

- User wants preferred source included in deduplication recommendations — not just "deduplicate" but "deduplicate, keeping source X"
- Match count granularity ("Partial (3/5)") requested for analytical flexibility
- Payer sentinel normalization before comparison aligns with Phase 19 definition — maintain consistency

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 26-overlap-classification-and-recommendations*
*Context gathered: 2026-04-22*
