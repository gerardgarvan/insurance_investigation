# Phase 63: Enhanced Gantt Export - Context

**Gathered:** 2026-05-31
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce Gantt v2 CSV files (gantt_episodes_v2.csv, gantt_detail_v2.csv) integrating all v1.8 enhancements (encounter-level cancer categories, HL flags, specific drug names, regimen labels, first-line flags) while preserving existing v1 output files unchanged for backward compatibility.

</domain>

<decisions>
## Implementation Decisions

### v2 Column Schema
- **D-01:** v2 is a superset of v1 — all 14 existing v1 columns plus 3 new columns: cancer_link_method, regimen_label, is_first_line
- **D-02:** cancer_category column keeps the same name in v2 but uses encounter-level data from treatment_episodes.rds (Phase 61) instead of patient-level derivation from cancer_summary.csv (Phase 57 pattern in R/49)
- **D-03:** is_hodgkin in v2 is derived from the encounter-level cancer_category (already in treatment_episodes.rds), not from patient-level cancer_summary.csv

### Script Architecture
- **D-04:** New standalone R/63_gantt_v2_export.R script — does NOT modify R/49
- **D-05:** R/63 reads enriched treatment_episodes.rds directly (cancer_category, cancer_link_method, is_hodgkin, regimen_label, is_first_line are pre-computed by Phases 61-62)
- **D-06:** R/63 is simpler than R/49 because it does NOT re-derive cancer categories from cancer_summary.csv or PREFIX_MAP — the RDS already has encounter-level values
- **D-07:** Accept code duplication for Death/HL Diagnosis row construction (~200 lines shared with R/49). Scripts remain self-contained per project pattern (same pattern as PREFIX_MAP duplication across R/47, R/49, R/53, R/55, R/61)

### Schema Documentation
- **D-08:** v2 schema documented in R/63's header comment block — column name, type, source, and description. Same pattern as R/49's header comments listing expected columns. No extra output artifact needed.

### Death/HL Diagnosis Rows
- **D-09:** v2 includes Death and HL Diagnosis pseudo-treatment rows (same as v1)
- **D-10:** New v2 columns on pseudo-treatment rows: cancer_link_method="none", regimen_label=NA, is_first_line=FALSE. Ensures v2 is a complete superset of v1.

### Claude's Discretion
- Column ordering within v2 CSVs (likely: v1 columns in original order, then cancer_link_method, regimen_label, is_first_line appended)
- Whether to include a summary message at end of R/63 showing v1 vs v2 column comparison
- How to handle edge cases where treatment_episodes.rds is missing Phase 61/62 columns (guard clauses similar to R/62's pattern)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Gantt Export
- `R/49_gantt_data_export.R` — v1 Gantt export (816 lines). v2 must produce compatible superset. Death/HL Diagnosis row construction pattern lives here (Sections 4B, 4C).
- `R/44a_treatment_episodes.R` — Produces treatment_episodes.rds and treatment_episode_detail.rds (primary inputs for v2)

### Phase 61-62 Enrichments
- `R/61_episode_classification.R` — Adds cancer_category, cancer_link_method, is_hodgkin, regimen_label to treatment_episodes.rds
- `R/62_first_line_and_death_analysis.R` — Adds is_first_line to treatment_episodes.rds; death analysis tables

### Supporting Artifacts
- `R/55_cancer_summary_refined.R` — Produces confirmed_hl_cohort.rds (used for HL Diagnosis rows)
- `R/59_death_date_validation.R` — Produces validated_death_dates.rds (used for Death rows)
- `R/48b_build_code_descriptions.R` — Produces code_descriptions.rds (triggering code lookup)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `treatment_episodes.rds` — Already enriched with all v2 columns (Phase 60: encounter_ids, drug_names; Phase 61: cancer_category, cancer_link_method, is_hodgkin, regimen_label; Phase 62: is_first_line)
- `treatment_episode_detail.rds` — Already enriched with ENCOUNTERID, drug_name (Phase 60)
- `validated_death_dates.rds` — Pre-validated death dates with impossible deaths excluded (Phase 59)
- `confirmed_hl_cohort.rds` — HL diagnosis dates for pseudo-treatment rows (Phase 55)
- `code_descriptions.rds` — Triggering code → description lookup (Phase 48b)

### Established Patterns
- Self-contained scripts with header comment documenting decision traceability (D-XX format)
- Column validation via setdiff() before binding rows (R/49 Sections 4B/4C)
- Guard clauses for missing columns with warning + default values (R/62 lines 79-85)
- DuckDB connection lifecycle: open_pcornet_con() → get_pcornet_table() → close_pcornet_con()
- Death row construction: validated_death_dates.rds → filter(!is.na(DEATH_DATE)) → build pseudo-rows with treatment_type="Death"
- HL Diagnosis row construction: confirmed_hl_cohort.rds → build pseudo-rows with treatment_type="HL Diagnosis"

### Integration Points
- Output directory: CONFIG$output_dir (same as v1)
- v2 file names: gantt_episodes_v2.csv, gantt_detail_v2.csv (alongside existing gantt_episodes.csv, gantt_detail.csv)
- R/49 remains UNCHANGED — v1 backward compatibility guaranteed by not touching the file

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. Key simplification: since treatment_episodes.rds already has all enrichment columns, R/63 avoids the complex cancer_summary.csv → PREFIX_MAP derivation that R/49 does. The main complexity is Death/HL Diagnosis row construction (duplicated from R/49).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 63-enhanced-gantt-export*
*Context gathered: 2026-05-31*
