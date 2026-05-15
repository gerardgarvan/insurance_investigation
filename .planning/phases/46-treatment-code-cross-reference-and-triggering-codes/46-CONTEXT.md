# Phase 46: Treatment Code Cross-Reference & Triggering Codes - Context

**Gathered:** 2026-05-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Two deliverables: (1) a two-way gap report comparing TreatmentVariables docx code lists against current TREATMENT_CODES in R/00_config.R, and (2) a new triggering_codes column in the episode CSV and xlsx output showing which code(s) triggered each treatment episode.

</domain>

<decisions>
## Implementation Decisions

### Gap report scope (D-01 to D-03)
- D-01: Cross-reference all 4 active treatment types: chemotherapy, radiation, SCT, immunotherapy
- D-02: Merge both documents as source — TreatmentVariables_2024.07.17.docx (broad, 6 categories) AND Treatment_Variable_Documentation.docx (implementation-focused, adds Q-codes, ICD-10-PCS patterns, doxorubicin detail)
- D-03: Include external xlsx files in comparison: PCS Codes Cancer Tx.xlsx, ComprehensiveSurgeryCodes.xlsx, MSDRGs.xlsx (all now in project directory)

### Range handling (D-04 to D-05)
- D-04: Compare at range level, not individual code expansion. For each docx range, report: what the docx says, what config covers, and what's intentionally excluded with rationale
- D-05: Range coverage summary format: "Docx says X-Y. Config covers A-B (N codes). Gap: C-D intentionally excluded (reason)." Annotate with Phase 45 rationale where applicable.

### Triggering codes format (D-06 to D-10)
- D-06: Comma-separated `triggering_codes` column in episode CSVs (e.g., "77427,77412,77386"). One row per episode preserved.
- D-07: Include ALL codes that matched TREATMENT_CODES within the episode's date window, not just the first code
- D-08: Bare codes only — no type prefix (PX_TYPE is implied by code format)
- D-09: Triggering codes appear in BOTH CSV and styled xlsx output for consistency
- D-10: Modify existing R/44_treatment_episodes.R to add the triggering_codes column

### Gap report output (D-11 to D-14)
- D-11: Styled xlsx with one sheet per treatment type (Chemo, Radiation, SCT, Immunotherapy) plus a summary sheet
- D-12: Each sheet shows codes in doc but not config AND codes in config but not doc
- D-13: Codes added via Phase 45 audit (42 radiation codes) shown in gap report with annotation "Added via Phase 45 audit — confirmed treatment codes in patient data"
- D-14: Include patient count and encounter count from PROCEDURES data for each gap code (requires DuckDB query on HiPerGator)

### Docx parsing strategy (D-15 to D-17)
- D-15: Hardcode code lists from both docx files into R data structures. The docx content is static (dated 2024.07.17). Most reliable approach.
- D-16: Also hardcode code lists from external xlsx files (PCS Codes Cancer Tx.xlsx, ComprehensiveSurgeryCodes.xlsx, MSDRGs.xlsx) rather than reading at runtime
- D-17: All hardcoded data structures serve as the "reference" side of the two-way comparison

### Claude's Discretion
- Exact R data structure format for hardcoded docx/xlsx code lists (named lists, tribbles, etc.)
- Sheet styling details (colors, column widths, conditional formatting)
- Console output format and progress messages
- How to handle codes that appear in both docs with different categorizations
- Summary sheet content and layout

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- R/44_treatment_episodes.R: Episode generation script — modification target for triggering_codes column
- R/00_config.R: TREATMENT_CODES named list — the "config" side of the comparison
- R/45_radiation_cpt_audit.R: Phase 45 audit pattern — styled xlsx with openxlsx2, PROCEDURES query for counts
- R/42_treatment_codes_resolved.R: `write_resolved_xlsx()` reusable function for styled 2-sheet xlsx
- R/utils_treatment.R: Shared helpers (safe_table, get_hl_patient_ids, empty_result, nrow_or_0)

### Established Patterns
- openxlsx2 styled xlsx: header styling, conditional fills, auto-width, multi-sheet workbooks (Phase 42, 45)
- `get_pcornet_table("PROCEDURES") %>% materialize()` for DuckDB-backed data access
- Episode CSV columns: patient_id, treatment_type, episode_number, episode_start, episode_stop, episode_length_days, distinct_dates_in_episode, historical_flag
- format(x, big.mark=',') for thousands separators in glue() messages (not Python `:,` syntax)
- int2col() for openxlsx2 column references (not int_to_col())

### Integration Points
- R/00_config.R TREATMENT_CODES — read target for config side of comparison
- R/44_treatment_episodes.R — modification target for triggering_codes
- output/ directory — xlsx and CSV output destination
- Both docx files + 3 external xlsx files in project root — reference documents

</code_context>

<specifics>
## Specific Ideas

- The gap report is both an audit tool and a communication artifact for collaborators (Amy Crisp / team)
- Phase 45 established the precedent: audit finds gaps → expand config → re-audit for 100% coverage. Phase 46 may surface similar actionable gaps in other treatment categories.
- Treatment_Variable_Documentation.docx adds Q-codes (Q0083-Q0085) and ICD-10-PCS patterns not in the original TreatmentVariables doc — merging both catches these.
- The triggering_codes column helps answer "which specific codes caused this patient to be flagged for radiation/chemo/etc?" — useful for clinical validation.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 46-treatment-code-cross-reference-and-triggering-codes*
*Context gathered: 2026-05-15*
