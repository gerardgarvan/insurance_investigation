# Phase 91: Reference Data Loader & Metadata Enrichment - Context

**Gathered:** 2026-06-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Build R/utils/utils_xlsx_lookups.R to parse all_codes_resolved2.xlsx (8 sheets) and extract per-code metadata (medication names, code types, source tables, F/S/E/N treatment line labels, cross-use flags). Enrich R/28 episode classification with 5 new columns via left_join. Export unresolved TBD codes separately for clinical SME review. Output: treatment_episodes.rds with medication_name, code_type, source_table, treatment_line, and sct_cross_use_flag columns.

</domain>

<decisions>
## Implementation Decisions

### F/S/E/N Label Handling
- **D-01:** Non-chemotherapy codes (Radiation, SCT, Immunotherapy, Supportive Care) get NA for treatment_line. F/S/E/N labels only exist in the Chemotherapy sheet (column 8). Other sheets lack this column entirely.
- **D-02:** Normalize F/S/E/N to single uppercase letters: F, S, E, N. Blank/N/A/missing/mixed-case variants all normalize to NA.
- **D-03:** Treatment line aggregates to a single best value per episode using priority: F > S > E > N. If any code in the episode has "F", the episode gets "F". This matches the existing is_first_line episode-level concept.

### Multi-Code Episode Display
- **D-04:** medication_name, code_type, and source_table use parallel semicolon-separated lists matching the existing triggering_codes pattern from Phase 64. Positional correspondence maintained (code N in triggering_codes maps to value N in each metadata column).
- **D-05:** treatment_line is the exception — it aggregates to a single value per episode (D-03), NOT a parallel list, because treatment line is an episode-level concept.

### TBD Code Handling
- **D-06:** TBD codes (8 vitamin combos, 2 CAR-T with unresolved classification) remain in treatment_episodes.rds with marker values: treatment_line = "TBD", sct_cross_use_flag = "TBD". No data loss — analysts can filter TBD if needed.
- **D-07:** Separate xlsx export for SME review containing: code, current category, medication name, patient/record counts from DuckDB, and a "Classification Question" column describing what needs resolving. Matches project's existing xlsx export pattern.

### Cross-Use Flag Values
- **D-08:** Claude's Discretion — inspect actual column 9 values in all_codes_resolved2.xlsx during implementation and decide normalization strategy (pass-through vs. enum mapping) based on what's found.
- **D-09:** Episode-level aggregation uses any-positive flag logic: if ANY code in the episode has a cross-use flag, the episode gets that flag. Most specific flag wins (mirrors the F>S>E>N aggregation pattern).

### Claude's Discretion
- Cross-use flag normalization strategy (D-08) — determined after xlsx inspection
- Exact column indices for sheets with fewer than 9 columns (Radiation has 7, SCT has 6)
- Pre-join deduplication logic (detect and resolve duplicate codes in xlsx before joining)
- TBD xlsx export filename and location (follow existing output patterns)
- Whether to version-stamp the xlsx reference file in data/reference/

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### XLSX Reference Data
- `all_codes_resolved2.xlsx` — Canonical source for treatment code metadata (8 sheets: Index, Sheet1, Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care, Unrelated). Chemotherapy has 9 columns; other sheets have fewer.

### Episode Classification (Primary Modification Target)
- `R/28_episode_classification.R` — Episode enrichment with cancer linkage, regimen detection, code descriptions, drug groups. Phase 91 adds 5 new columns here via left_join.

### Existing Code Patterns
- `R/50_all_codes_resolved.R` — `code_type_map` tribble (lines 57-81) defines code→metadata mapping structure. Reference for how the project maps code types and source tables.
- `R/52_gantt_v2_export.R` — Current 16-column episodes schema (lines 38-54). Phase 92 will extend this to 21 columns using Phase 91's enriched RDS.
- `R/00_config.R` — DRUG_GROUPINGS named vector, TREATMENT_CODES lists. Central config.

### Research Documents
- `.planning/research/ARCHITECTURE.md` — Integration architecture for xlsx loading and enrichment pipeline
- `.planning/research/PITFALLS.md` — Many-to-many join explosion prevention, TBD code propagation risks
- `.planning/research/SUMMARY.md` — Research synthesis with integration patterns and column derivation logic
- `.planning/research/STACK.md` — xlsx structure verification (column counts per sheet), openxlsx2 usage patterns

### Requirements
- `.planning/REQUIREMENTS.md` — GANTT-01 through GANTT-05 (medication_name, code_type, source_table, treatment_line, cross_use_flag)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `openxlsx2` library: Already in use across R/50, R/57, R/24 for xlsx read/write. `wb_load()` + `wb_to_df()` pattern established.
- `code_type_map` tribble in R/50 (lines 57-81): Maps vector names to code_type and source_table metadata. Can inform the lookup structure.
- `lookup_drug_group()` function in R/28 (line 456): Existing pattern for named vector lookup across comma-separated code lists using `sapply()`.
- `check()` function in R/88: Existing smoke test assertion helper.
- `safe_table()` in R/utils/utils_treatment.R: Graceful null handling for DuckDB table access.
- `assert_file_exists()` from checkmate: Standard input validation pattern.

### Established Patterns
- Named vector lookups (DRUG_GROUPINGS, CANCER_SITE_MAP) for code → metadata mapping
- Semicolon delimiters for multi-value fields in Gantt output (Phase 64)
- left_join with NA preservation for enrichment (R/28, R/52)
- Utility module pattern: `R/utils/utils_*.R` files sourced as needed (10 existing utils files)
- Dual file save for backward compatibility (Phase 89)

### Integration Points
- R/28 is the enrichment point — sources utils, loads xlsx, derives columns, saves to treatment_episodes.rds
- treatment_episodes.rds flows downstream to R/51 (v1 export) and R/52 (v2 export)
- R/88 smoke test needs new section for the 5 new columns
- xlsx file path configured via CONFIG$output_dir or project root

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches following existing patterns.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 91-reference-data-loader-metadata-enrichment*
*Context gathered: 2026-06-08*
