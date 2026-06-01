# Phase 64: Clean up Gantt 2 output for coherent chart generation - Context

**Gathered:** 2026-06-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Clean up the Gantt v2 CSV output files (gantt_episodes_v2.csv, gantt_detail_v2.csv) so they are directly usable in Tableau for coherent Gantt chart creation. This includes trimming unnecessary columns, fixing data quality issues (NAs, empty descriptions, comma-in-cell conflicts), simplifying drug names, deduplicating multi-value fields, and labeling missing data consistently.

</domain>

<decisions>
## Implementation Decisions

### Target Platform
- **D-01:** Output is consumed by Tableau. Data must be clean enough for direct import without manual preprocessing.

### Column Selection (Episodes)
- **D-02:** Trim episodes to essential columns only. Keep: patient_id, treatment_type, episode_number, episode_start, episode_stop, episode_length_days, distinct_dates_in_episode, historical_flag, triggering_codes, drug_names, triggering_code_descriptions, cancer_category, regimen_label, is_first_line. Drop: encounter_ids, is_hodgkin, cancer_link_method.
- **D-03:** Keep historical_flag in the trimmed output so Tableau users can filter historical episodes.

### Column Selection (Detail)
- **D-04:** Trim detail to essential columns. Keep: patient_id, treatment_type, treatment_date, triggering_code, drug_name, episode_number, episode_start, episode_stop, historical_flag, triggering_code_description, cancer_category, regimen_label, is_first_line. Drop: ENCOUNTERID, is_hodgkin, cancer_link_method.

### Column Naming
- **D-05:** Keep snake_case column names (no renaming to Title Case).

### Separator Character
- **D-06:** Use semicolons (`;`) instead of commas as the separator within multi-value cells (triggering_codes, drug_names, triggering_code_descriptions). This prevents CSV parsing conflicts since commas are also the field delimiter.

### Description Cleanup
- **D-07:** Deduplicate descriptions within each cell and drop blank entries. For example, `",,Encounter for antineoplastic chemotherapy"` becomes `"Encounter for antineoplastic chemotherapy"`. Multiple identical descriptions are collapsed to one.
- **D-08:** Apply same dedup + blank-drop to triggering_codes and drug_names fields.

### Drug Name Simplification
- **D-09:** Simplify drug names from full RxNorm descriptions (e.g., `"25 ML doxorubicin hydrochloride 2 MG/ML Injection"`) to just the generic drug name (e.g., `"doxorubicin"`). Remove dosage, formulation, volume, and brand info. Deduplicate per episode.

### Null/NA Handling
- **D-10:** Convert R's text `"NA"` to true empty cells in the CSV output (Tableau reads these as null). Do not leave literal "NA" strings.

### Pseudo-Treatment Rows
- **D-11:** Keep Death and HL Diagnosis pseudo-treatment rows. Set their triggering_code_descriptions to the treatment_type value itself (e.g., "Death", "HL Diagnosis") so Tableau tooltips are not blank.

### Missing Cancer Category
- **D-12:** Set empty/blank cancer_category values to "Unlinked" instead of empty string. This provides an honest label for Tableau filtering and coloring.

### Output Structure
- **D-13:** Clean both gantt_episodes_v2.csv and gantt_detail_v2.csv with the same quality fixes. Output overwrites the existing v2 files (or writes to new filenames — Claude's discretion).

### Claude's Discretion
- Output file naming (overwrite v2 files vs new names like gantt_episodes_v2_clean.csv)
- Sort order of output rows
- How to extract generic drug names from RxNorm strings (regex pattern design)
- Whether to also clean triggering_codes field values (dedup/drop blanks)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Gantt Export Script
- `R/63_gantt_v2_export.R` — Current v2 export script (Phase 63). This is the file to modify or extend for cleanup logic.

### Input Artifacts
- `output/gantt_episodes_v2.csv` — Current v2 episodes output (17 columns, ~23K rows). Source of truth for what needs cleaning.
- `output/gantt_detail_v2.csv` — Current v2 detail output (16 columns, ~221K rows).

### Code Description Lookup
- `R/48b_build_code_descriptions.R` — Produces code_descriptions.rds. Understanding why some codes have empty descriptions helps inform D-07.

### Drug Name Source
- `cache/outputs/treatment_episode_detail.rds` — Contains raw drug_name values from RxNorm resolution (Phase 60).

### Prior Gantt Phase Context
- `.planning/milestones/v1.8-phases/63-enhanced-gantt-export/63-CONTEXT.md` — Phase 63 decisions about v2 schema and structure.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/63_gantt_v2_export.R` — Contains `map_codes_to_descriptions()` helper (line 164) and `lookup_description()` (line 157). These can be extended with dedup/blank-drop logic.
- `code_descriptions.rds` — Named character vector mapping codes to descriptions. Some codes (DRG codes like 0333, 0335, J-codes like J9185, J9263) have no entries, causing blank descriptions.

### Established Patterns
- sapply-based lookup enrichment (R/63 line 187)
- Guard clauses for missing columns with defaults (R/63 lines 122-141)
- Column verification via setdiff() before bind_rows (R/63 lines 284-294)

### Integration Points
- Cleanup logic should be added to R/63_gantt_v2_export.R between Section 4 (column selection) and Section 5 (CSV write)
- No upstream artifacts need modification — this is a presentation-layer cleanup only

</code_context>

<specifics>
## Specific Ideas

- User noted triggering_code_descriptions are "kind of hard to read" — this drove D-07 and D-08
- Drug names like "25 ML doxorubicin hydrochloride 2 MG/ML Injection [Vincasar]" need regex extraction of the base drug name
- Semicolon separator chosen specifically because Tableau's SPLIT() function handles it well
- "Unlinked" label for missing cancer categories enables meaningful Tableau color coding

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 64-clean-up-gantt-2-output-for-coherent-chart-generation*
*Context gathered: 2026-06-01*
