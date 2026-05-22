# Phase 5: all_codes_resolved.xlsx Update - Context

**Gathered:** 2026-05-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Regenerate all_codes_resolved.xlsx and the 5 per-type resolved xlsx files (chemotherapy, radiation, SCT, immunotherapy, supportive care) from the current TREATMENT_CODES in R/00_config.R, with patient/record counts queried from PCORnet data and descriptions sourced from a multi-source cascade. Also curate R/00_config.R inline comments where better descriptions are available.

</domain>

<decisions>
## Implementation Decisions

### Code Source
- **D-01:** Pull code lists directly from R/00_config.R TREATMENT_CODES vectors — this is the current source of truth including Phase 45 proton additions, Phase 46 ICD-10-PCS additions, and all prior expansions
- **D-02:** Do NOT depend on combined_unmatched_report.xlsx (Phase 41 output) — config has diverged since May 5

### Data Counts
- **D-03:** Include patient count and record count per code, queried from PCORnet data via DuckDB on HiPerGator
- **D-04:** Query all relevant tables per code type: CPT/HCPCS codes against PROCEDURES, NDC codes against DISPENSING, RXNORM codes against PRESCRIBING/MED_ADMIN, ICD-10-PCS codes against PROCEDURES
- **D-05:** Script requires HiPerGator execution (not local-only)

### Descriptions
- **D-06:** Multi-source description cascade: (1) Phase 39-41 RDS artifacts (NLM/RxNorm API descriptions), (2) R/45 hardcoded radiation descriptions, (3) R/00_config.R inline comments, (4) "No description available" fallback
- **D-07:** Update R/00_config.R inline comments when a better description exists from the RDS/API sources — makes config self-documenting
- **D-08:** Config comment updates must use parse/source validation with rollback (established pattern from Phase 39)

### Output Structure
- **D-09:** all_codes_resolved.xlsx has one sheet per treatment type: Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care, plus a Summary sheet with totals
- **D-10:** Also regenerate all 5 individual per-type resolved files (chemotherapy_codes_resolved.xlsx, radiation_codes_resolved.xlsx, sct_codes_resolved.xlsx, immunotherapy_codes_resolved.xlsx, supportive_care_codes_resolved.xlsx)
- **D-11:** Per-type sheets and files follow established format: Code, Meaning, Code Type, Source Table, Records, Patients columns with openxlsx2 styling

### Script Approach
- **D-12:** New standalone script R/52_all_codes_resolved.R — R/42 stays as historical record of the original Phase 42 approach
- **D-13:** Script number 52 follows the current sequence (R/51 is cancer site confirmation 7-day)

### Claude's Discretion
- Whether config comment curation is done as an early section of R/52 or as a separate preparatory step — pick the approach that minimizes risk of breaking config
- Exact xlsx styling details (colors, column widths, Summary sheet layout)
- How to map TREATMENT_CODES vector names to code types and source tables for querying
- Console output format and progress messages

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Treatment Code Config
- `R/00_config.R` — TREATMENT_CODES named list (all code vectors by type), TREATMENT_TYPE_COLORS, AMC_PAYER_LOOKUP
- `R/00_config.R` inline comments — Current description annotations on code vectors

### Existing Resolved Scripts and Output
- `R/42_treatment_codes_resolved.R` — write_resolved_xlsx() reusable function, per-type generation pattern, chemotherapy verification logic
- `chemotherapy_codes_resolved.xlsx` — Template format (2 sheets: data + Notes, styled headers)
- `radiation_codes_resolved.xlsx`, `sct_codes_resolved.xlsx`, `immunotherapy_codes_resolved.xlsx`, `supportive_care_codes_resolved.xlsx` — Current per-type files (May 5, now outdated)

### Description Sources (RDS Artifacts)
- `output/unmatched_codes_classified.rds` — Phase 39 HCPCS/CPT API descriptions
- `output/unmatched_ndc_classified.rds` — Phase 40 NDC/RXNORM API descriptions

### Config Update Pattern
- `R/39_investigate_unmatched.R` — Phase 39 programmatic config modification with parse/source validation and rollback

### Data Access
- `R/01_load_pcornet.R` — get_pcornet_table() DuckDB-backed data access
- `R/utils_treatment.R` — Shared treatment helpers (safe_table, get_hl_patient_ids, empty_result, nrow_or_0)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `write_resolved_xlsx()` in R/42: Creates styled 2-sheet workbook (data + Notes) per treatment type — can be reused or adapted
- `TREATMENT_TYPE_COLORS` in R/00_config.R: Per-category color scheme for xlsx styling
- `get_pcornet_table()` in R/01: DuckDB-backed table access for patient/record count queries
- Phase 39-41 RDS artifacts: Pre-computed code descriptions from NLM/RxNorm API lookups

### Established Patterns
- openxlsx2 (not openxlsx) for all xlsx creation
- Dark header fill (FF374151) + white font (FFFFFFFF) for styled headers
- Freeze panes on row 2, auto column widths
- Number formatting with #,##0 for count columns
- parse/source validation with rollback for programmatic config modifications (Phase 39 pattern)
- format(x, big.mark=',') for thousands separators in glue() messages

### Integration Points
- R/00_config.R TREATMENT_CODES — read source for code lists, modification target for comment curation
- PROCEDURES, DISPENSING, PRESCRIBING, MED_ADMIN tables — DuckDB query targets for counts
- Root directory — xlsx output destination (gitignored via /*.xlsx)
- Phase 39-41 RDS artifacts in output/ — description lookup source

</code_context>

<specifics>
## Specific Ideas

- The all_codes_resolved.xlsx is the definitive "what codes does our pipeline detect?" reference — shared with collaborators
- Config has had 4+ commits adding codes since the per-type files were last generated (May 5)
- Phase 45 added 46 radiation codes with hardcoded descriptions
- Phase 46 gap report led to ICD-10-PCS chemo route additions
- The per-type files and all_codes_resolved.xlsx should all reflect the same current state of config

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 05-all-codes-resolved-xlsx-update-because-we-added-more-codes-in-config-etc*
*Context gathered: 2026-05-20*
