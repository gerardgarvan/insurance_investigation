# Phase 89: Clear Up Episode vs Encounter Distinction - Context

**Gathered:** 2026-06-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Clarify the episode-level vs encounter-level distinction in the drug grouping Excel outputs (R/56 and R/57). Rename output files and sheet names so each file self-documents which grain of data it contains. Both old and new filenames produced for backward compatibility.

</domain>

<decisions>
## Implementation Decisions

### Output Naming
- **D-01:** R/56 output renamed from `drug_grouping_tables.xlsx` to `episode_level_drug_grouping_tables.xlsx`
- **D-02:** R/57 output renamed from `drug_grouping_instances.xlsx` to `encounter_level_drug_grouping_instances.xlsx`
- **D-03:** Both scripts also produce the original filenames (backward compatibility) — both old and new names written in the same run

### Column/Sheet Labeling
- **D-04:** R/56 sheet names updated to include "Episode-Level" prefix (e.g., "Episode-Level Sub-Category Summary", "Episode-Level Encounter Treatment Summary")
- **D-05:** R/57 sheet names updated to include "Encounter-Level" prefix (e.g., "Encounter-Level Sub-Category Detail", "Encounter-Level Treatment Detail")

### Script Scope
- **D-06:** Modify R/56 and R/57 in-place — no new wrapper script, no config changes

### Claude's Discretion
- Whether to use `wb$save()` twice (one per filename) or `file.copy()` for the duplicate filename
- Log message wording for the dual-output step

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Drug Grouping Scripts
- `R/56_new_tables_from_groupings.R` — Episode-level drug grouping tables (source of drug_grouping_tables.xlsx)
- `R/57_drug_grouping_instances.R` — Encounter-level drug grouping instances (source of drug_grouping_instances.xlsx)

### Data Sources
- `R/26_treatment_episodes.R` — Creates both treatment_episodes.rds (episode grain) and treatment_episode_detail.rds (encounter grain)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Both R/56 and R/57 already use `openxlsx2` with `wb_workbook()` / `wb$add_worksheet()` / `wb$save()` pattern
- Output paths already use `file.path(CONFIG$output_dir, ...)` pattern

### Established Patterns
- R/56 Section 7 (line 571-586): Creates workbook, adds 2 sheets, saves to OUTPUT_XLSX
- R/57 Section 7 (line 403-417): Same pattern — creates workbook, adds 2 sheets, saves to OUTPUT_XLSX
- Both scripts have a console summary section that logs the output path

### Integration Points
- OUTPUT_XLSX variable defined near top of each script (R/56 line 81, R/57 line 59)
- Sheet names defined inline in `wb$add_worksheet()` calls
- Log messages reference the output path via glue()

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches for the dual-save and sheet renaming.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 89-clear-up-episode-vs-encounter-distinction-for-r-56-export-both-versions-as-labeled-excel-files*
*Context gathered: 2026-06-05*
