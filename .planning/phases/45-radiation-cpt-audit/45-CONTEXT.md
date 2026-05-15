# Phase 45: Radiation CPT Audit - Context

**Gathered:** 2026-05-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Classify CPT 70010-79999 sub-ranges with AMA citations, query all patients' PROCEDURES data for codes in that range, add proton therapy codes 77520-77525 to config, fix Phase 39 "no description" comments, and auto-add any confirmed treatment codes found in data. Output is a styled xlsx for sharing with collaborators that explains why the pipeline uses a narrow radiation code set rather than the full range from TreatmentVariables.

</domain>

<decisions>
## Implementation Decisions

### Classification granularity (D-01 to D-03)
- D-01: Claude's discretion on sub-range grouping level — pick what best supports the argument for excluding imaging codes
- D-02: Citations use AMA CPT chapter structure (publicly known range boundaries). No need for published literature references.
- D-03: Classification table includes a brief rationale column explaining WHY each sub-range is imaging vs treatment (not just the AMA label)

### Output format & audience (D-04 to D-07)
- D-04: Primary audience is collaborators (Amy Crisp / team) — output must be self-explanatory
- D-05: Styled xlsx following Phase 42 openxlsx2 pattern. Two sheets: classification table + codes found in data.
- D-06: This is NOT about flagging false positives in existing detection. The current config does NOT use imaging codes. The purpose is to explain to collaborators WHY the pipeline uses a narrow set of treatment codes rather than the full 70010-79999 range from TreatmentVariables.
- D-07: Include an explicit recommendation section: "TreatmentVariables specifies 70010-79999; only 77261-77799 are radiation treatment per AMA CPT. Recommend using narrow treatment-only range."

### Config update scope (D-08 to D-11)
- D-08: Add proton therapy codes 77520-77525 to TREATMENT_CODES$radiation_cpt with proper descriptions and citation comments
- D-09: Fix all Phase 39 "no description" comments on existing radiation_cpt codes (77404, 77408, 77413, 77414, 77416, 77417, 77418, 77421, 77431, 77432, 77435, 77470) with actual AMA/NLM descriptions
- D-10: Auto-add any confirmed radiation treatment codes found in data but not in config (following Phase 39 pattern)
- D-11: Add a comment block above radiation_cpt explaining AMA chapter structure and why the full 70010-79999 range isn't used

### Data query scope (D-12 to D-15)
- D-12: Query ALL patients in the PCORnet extract (not just HL cohort) for broader view
- D-13: Include ALL PX_TYPEs, not just PX_TYPE='CH' — cast a wider net for unexpected mappings
- D-14: Per-code detail: patient count + encounter count (consistent with Phase 42 resolved xlsx)
- D-15: No HIPAA suppression on counts — raw numbers are fine for this audit output

### Claude's Discretion
- Exact sub-range grouping level within the classification table
- Sheet styling details and column ordering within the xlsx
- Console output format and summary statistics
- NLM API vs hardcoded descriptions for code lookups

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- R/00_config.R lines 639-657: Current `radiation_cpt` vector with 17 codes (no proton, 12 with "Phase 39: no description")
- R/42_treatment_codes_resolved.R: `write_resolved_xlsx()` reusable function for styled 2-sheet xlsx
- R/39_investigate_unmatched.R: NLM HCPCS API lookup pattern for code descriptions
- R/38_treatment_inventory.R: Pattern for querying PROCEDURES by PX_TYPE and matching against TREATMENT_CODES

### Established Patterns
- Phase 42 xlsx pattern: openxlsx2 with header styling, auto-width, data sheet + notes sheet
- Phase 39 config update pattern: programmatic modification of TREATMENT_CODES vectors with parse/source validation
- `get_pcornet_table("PROCEDURES") %>% materialize()` for DuckDB-backed data access

### Integration Points
- R/00_config.R `TREATMENT_CODES$radiation_cpt` — direct modification target
- All scripts using `radiation_cpt` (R/03, R/10, R/11, R/16, R/38, R/39, R/43) — gain proton codes automatically after config update
- output/tables/ — xlsx output destination

</code_context>

<specifics>
## Specific Ideas

- The key purpose is explaining to collaborators why the pipeline doesn't use the full 70010-79999 range from TreatmentVariables — it's a justification document as much as an audit
- User suspects many 70010-79999 codes are imaging, not treatment — the audit confirms this systematically
- Proton therapy codes 77520-77525 are specifically called out in meeting notes as needing verification

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 45-radiation-cpt-audit*
*Context gathered: 2026-05-15*
