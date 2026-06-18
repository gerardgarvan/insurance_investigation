# Phase 111: Collapse chemo agents by date per patient in TABLE-2 - Context

**Gathered:** 2026-06-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Modify R/36 TABLE-2 output (`tableau_table2_chemo_drugs_by_class.xlsx`) to collapse from per-encounter+medication grain to per-patient+date grain, combining all chemo agent names on each date into a single comma-separated string. TABLE-1 is untouched. No new scripts, no new output files.

</domain>

<decisions>
## Implementation Decisions

### Output Columns
- **D-01:** Drop ENCOUNTERID column entirely. Date grain makes encounter IDs meaningless — consistent with Phase 109's date-grain philosophy.
- **D-02:** Drop drug_class and treatment_type columns. Both are always "Chemotherapy" after the chemo-only filter — no information content.
- **D-03:** Merge and deduplicate cancer_codes across all encounters on the same patient+date. Union all cancer codes from all encounters that day into one comma-separated string.
- **D-04:** Merge and deduplicate cancer_category_names across all encounters on the same patient+date, matching the cancer_codes merge.
- **D-05:** Final columns: PATID, treatment_date, agents (collapsed medication names), cancer_codes (merged+deduped), cancer_category_names (merged+deduped).

### Agent String Format
- **D-06:** Combined agent string uses medication names only (e.g., "Doxorubicin, Vincristine, Bleomycin"), no triggering codes in the string. Comma-separated, sorted alphabetically.
- **D-07:** Deduplicate agents within each date — each unique medication name appears once per patient+date, even if it appeared in multiple encounters.

### Scope of Change
- **D-08:** Modify R/36 Section 5 in-place. Change the TABLE-2 build logic to collapse by (PATID, treatment_date) instead of keeping per-encounter+medication rows.
- **D-09:** Replace existing output file — same filename (`tableau_table2_chemo_drugs_by_class.xlsx`), date-collapsed version supersedes the per-encounter version.
- **D-10:** TABLE-1 (encounter cancer codes) is completely untouched.

### Claude's Discretion
- Column name for the collapsed agents string (e.g., "agents", "medication_names", "chemo_agents")
- Whether to update R/88 smoke test assertions for the new column structure
- Exact sort order for cancer_codes and cancer_category_names within the merged strings
- Log message updates to reflect the new grain and row counts

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Primary Script to Modify
- `R/36_tableau_ready_tables.R` — Section 5 (BUILD TABLE-2) is the main modification target. Sections 1-4 and Section 6 (xlsx write) need minor adjustments for new column structure.

### Phase 106 Context (Original TABLE-2 Decisions)
- `.planning/phases/106-tableau-ready-data-tables/106-CONTEXT.md` — Original TABLE-2 implementation decisions. D-04 (medication names), D-05 (chemo-only filter), D-06 (columns) are being modified by this phase.

### Phase 109 Context (Date-Grain Precedent)
- `.planning/phases/109-fix-co-administration-analysis-remove-icd9-codes-that-blur-single-agent-detection-and-switch-grouping-from-encounter-to-date/109-CONTEXT.md` — Established date-grain as the meaningful clinical unit over encounter-grain. D-03 defines the date-level grouping pattern.

### Code & Drug Mappings
- `R/00_config.R` — CONFIG paths, CODE_SUBCATEGORY_MAP for drug name resolution
- `data/reference/all_codes_resolved_next_tables_v2.1.xlsx` — Chemotherapy sheet column C for medication name mappings

### Validation
- `R/88_smoke_test_comprehensive.R` — Existing R/36 validation section may need updating for new column structure

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **R/36 Section 5**: Current TABLE-2 build logic already resolves medication names via 3-tier cascade (xlsx -> CODE_SUBCATEGORY_MAP -> fallback). The name resolution stays; only the aggregation changes.
- **R/36 Section 3**: Cancer code extraction per encounter is reusable — just needs a second pass to merge codes across encounters sharing the same date.
- **openxlsx2 workbook pattern**: Already in R/36 Section 6 — just update the data being written.

### Established Patterns
- `group_by() %>% summarise(paste(sort(unique(x)), collapse = ","))` — Used in R/36 Section 3 for cancer code aggregation. Same pattern applies to agent name collapsing.
- Date-grain grouping established in Phase 109's R/58 modification.

### Integration Points
- **Input**: Same as current R/36 — `treatment_episode_detail.rds` + DuckDB DIAGNOSIS table + reference xlsx
- **Output**: Same filename `output/tableau_table2_chemo_drugs_by_class.xlsx` — in-place replacement
- **Downstream consumers**: R/37 (gap resolution report) reads this xlsx; R/38 (delivery manifest) references it; R/88 validates it

</code_context>

<specifics>
## Specific Ideas

- The user wants to see which agents were administered together on each date, collapsed into one string per row — this is about making the Tableau-ready table more useful for Amy's date-level analysis.
- Pattern mirrors Phase 109's insight: dates are clinically meaningful, encounters are billing artifacts.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 111-for-chemo-drugs-by-class-xlsx-combine-agents-by-date-per-id-collapse-agents-into-one-string-for-each-date*
*Context gathered: 2026-06-18*
