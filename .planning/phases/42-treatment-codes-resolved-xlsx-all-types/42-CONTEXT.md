# Phase 42: Treatment Codes Resolved XLSX (All Types) - Context

**Gathered:** 2026-05-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Create individual resolved xlsx files for each non-chemo treatment type (Radiation, SCT, Immunotherapy, Supportive Care) by extracting classified codes from combined_unmatched_report.xlsx, mirroring the format of chemotherapy_codes_resolved.xlsx. Also cross-check chemotherapy_codes_resolved.xlsx against the combined report to verify code counts match.

</domain>

<decisions>
## Implementation Decisions

### Output Structure
- **D-01:** One xlsx file per treatment type, mirroring chemotherapy_codes_resolved.xlsx format exactly (data sheet + Notes sheet)
- **D-02:** Files to produce: `radiation_codes_resolved.xlsx`, `sct_codes_resolved.xlsx`, `immunotherapy_codes_resolved.xlsx`, `supportive_care_codes_resolved.xlsx`
- **D-03:** Each file's data sheet has columns: Code, Meaning, Code Type, Source Table, Records, Patients
- **D-04:** Each file has a "Notes" sheet documenting source provenance

### Description Curation
- **D-05:** Use API descriptions from combined_unmatched_report.xlsx as-is, renamed to "Meaning" column for consistency with chemotherapy file format
- **D-06:** No manual curation step required — API descriptions are sufficient

### Chemo Verification
- **D-07:** Cross-check that the 203 codes in chemotherapy_codes_resolved.xlsx match the 203 codes in the Chemotherapy sheet of combined_unmatched_report.xlsx
- **D-08:** Flag any mismatches in Records/Patients counts between the two files
- **D-09:** Output verification results (pass/fail + any discrepancies) to console and optionally a verification summary

### Supportive Care
- **D-10:** Include Supportive Care (171 codes) as its own resolved xlsx file alongside active treatment types

### Claude's Discretion
- Styling/formatting of xlsx files (color scheme, fonts, column widths)
- Whether to produce a single R script or one per type
- Verification output format (console message vs separate report file)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Output Files
- `chemotherapy_codes_resolved.xlsx` — Template file to mirror (2 sheets: "Chemotherapy Codes" + "Notes", 203 rows)
- `combined_unmatched_report.xlsx` — Source data (sheets: Summary, Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care, Unrelated)

### Source Scripts
- `R/41_combine_reports.R` — Produces combined_unmatched_report.xlsx; shows openxlsx2 patterns and category color scheme
- `R/00_config.R` lines 412-600+ — TREATMENT_CODES list with all code vectors by type

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/41_combine_reports.R`: openxlsx2 workbook creation pattern with styled headers, color-coded rows, and number formatting
- `TREATMENT_TYPE_COLORS` in 41_combine_reports.R: per-category color scheme (Chemotherapy=blue, Radiation=green, SCT=yellow, Immunotherapy=purple, Supportive Care=teal)
- `unmatched_codes_classified.rds` and `unmatched_ndc_classified.rds`: raw RDS artifacts if needed

### Established Patterns
- openxlsx2 (not openxlsx) for xlsx creation
- RDS artifacts as intermediate data format
- `source("R/00_config.R")` for shared configuration
- Category order: Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care, Unrelated

### Integration Points
- Reads from: `combined_unmatched_report.xlsx` (or the underlying RDS files)
- Writes to: project root (same location as chemotherapy_codes_resolved.xlsx)
- Verification reads: `chemotherapy_codes_resolved.xlsx`

</code_context>

<specifics>
## Specific Ideas

- Mirror chemotherapy_codes_resolved.xlsx structure exactly (title row with count, column headers, data rows)
- Notes sheet should document that descriptions come from NLM/RxNorm API lookups via combined_unmatched_report.xlsx

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 42-treatment-codes-resolved-xlsx-all-types*
*Context gathered: 2026-05-04*
