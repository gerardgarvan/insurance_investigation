# Phase 25: Multi-Source Overlap Detection - Context

**Gathered:** 2026-04-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Detect same-date and same-week multi-source encounter pairs across all 5 sites, with per-source counts and source combination frequencies. This phase identifies overlaps; Phase 26 classifies them (Identical/Partial/Distinct) and produces recommendations.

</domain>

<decisions>
## Implementation Decisions

### Population scope
- Analyze ALL patients in ENCOUNTER table, not just HL cohort
- Do NOT use DEMOGRAPHIC.SOURCE for site assignment — use ENCOUNTER.SOURCE only
- Global detection first, then per-ENCOUNTER.SOURCE breakdowns
- "Per-site" in requirements = per ENCOUNTER.SOURCE value
- Fresh load from raw ENCOUNTER table (standalone script, no dependency on Phase 22 having run)

### Near-duplicate window
- Rolling ±7 calendar days on ADMIT_DATE (not calendar week)
- Pairwise matching only — no transitive chaining
- ADMIT_DATE only (not DISCHARGE_DATE)
- Same-date pairs excluded from near-duplicate results (captured separately by same-date detection)

### Source combination reporting
- Sorted concatenated string format: e.g., "AMS+FLM+UFH"
- Separate frequency tables for same-date combos vs same-week combos
- Console output includes top 10 source combinations ranked by frequency (for both categories)
- Report both patient-date pair counts AND total encounter row counts per combination

### CSV output structure
- 4 CSV files in output/tables/ with `multi_source_` prefix
- multi_source_same_date_detail.csv — one row per patient-date (ID, ADMIT_DATE, n_sources, n_encounters, source_combo, sources_list)
- multi_source_same_week_detail.csv — one row per patient-date pair (near-duplicates only, excluding same-date)
- multi_source_combo_frequencies.csv — source combination frequencies, separate sections for same-date and same-week
- multi_source_per_source_summary.csv — per ENCOUNTER.SOURCE aggregate with counts + rates (total_encounters, n_multi_source_dates, n_patients_affected, pct_encounters_overlapping)

### Claude's Discretion
- Exact self-join or window approach for ±7 day pairwise detection
- Console summary formatting and verbosity beyond top 10 combos
- Date parsing fallback strategy (standard vs parse_pcornet_date)
- HIPAA suppression of small counts in CSV output

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/21_all_site_duplicate_dates.R`: Same encounter loading pattern (source config, load pcornet, parse dates), same-date duplicate detection logic, `is_missing_payer()` helper
- `R/00_config.R` + `R/01_load_pcornet.R`: Standard config/loading infrastructure
- `R/utils_dates.R`: `parse_pcornet_date()` fallback for non-standard date formats

### Established Patterns
- Standalone diagnostic scripts source `00_config.R` and conditionally source `01_load_pcornet.R`
- Console output uses `message()` + `glue()` with section headers (`strrep('=', 70)`)
- CSV output via `readr::write_csv()` to `output/tables/`
- Phase 22 renames ENCOUNTER.SOURCE to ENCOUNTER_SOURCE to avoid column collision — Phase 25 can skip this since it doesn't join DEMOGRAPHIC

### Integration Points
- Output CSVs feed directly into Phase 26 (`R/23_overlap_classification.R`) for field-by-field comparison
- Same-date detail CSV must contain enough info for Phase 26 to join back to ENCOUNTER for field comparison

</code_context>

<specifics>
## Specific Ideas

- User explicitly chose NOT to use DEMOGRAPHIC.SOURCE for site assignment ("just in case" — avoids assumptions about patient-site mapping)
- Phase 26 downstream will need to join back to raw ENCOUNTER rows for field comparison, so patient-date detail must preserve ID + ADMIT_DATE as join keys

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 25-multi-source-overlap-detection*
*Context gathered: 2026-04-21*
