# Phase 105: Code & Overlap Verification - Context

**Gathered:** 2026-06-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Verify three code classification concerns (Ethna immunotherapy, organ transplant code 0362, SCT diagnosis codes above line 22) and produce a focused HL+NHL dual-code validation report for the ~4,000/8,000 dual-code patients. Four investigation requirements (CODE-01, CODE-02, CODE-03, OVERLAP-01) organized into two standalone scripts producing two xlsx reports. **Report-only — no modifications to existing scripts, config, or outputs.**

</domain>

<decisions>
## Implementation Decisions

### Script Organization
- **D-01:** Two scripts total: one combined code verification script (CODE-01 + CODE-02 + CODE-03) and one separate HL+NHL overlap validation script (OVERLAP-01).
- **D-02:** Combined code verification script produces a single xlsx with tabs per investigation plus a summary tab with recommendations. Each CODE section is a self-contained analysis block within the script.
- **D-03:** Script numbering follows next available numbers in the investigation script decade (R/33, R/34 or similar — Claude's discretion on exact numbers).

### Code Verification Investigations (CODE-01/02/03)
- **D-04:** CODE-01 (Ethna/etanercept): Query PRESCRIBING for etanercept RxNorm codes (1653225, 809158, 809159, 214555). Cross-reference against DRUG_GROUPINGS immunotherapy codes. Report finding: etanercept is a TNF-alpha inhibitor (immunosuppressant), NOT anticancer immunotherapy. Already correctly excluded from DRUG_GROUPINGS — data quality issue in raw data, not a mapping error.
- **D-05:** CODE-02 (Organ transplant code 0362): Query PROCEDURES for revenue code 0362. Cross-reference patients against SCT-indicating diagnosis codes (Z94.84) and procedure codes (38240-38243, 30233/30243 series) to assess what fraction are SCT vs solid organ transplant.
- **D-06:** CODE-03 (SCT codes above line 22): Query DIAGNOSIS for Z94.84 (SCT status), T86.5 (SCT complications), T86.09 (BMT complications). Cross-reference against procedure-based SCT evidence. Report how many patients have diagnosis-only vs. diagnosis+procedure evidence.

### HL+NHL Overlap Validation (OVERLAP-01)
- **D-07:** Extends R/78's 3-way Venn analysis with patient-level temporal detail. For each dual-code patient: first HL dx date, first NHL dx date, days between, same-day flag, encounter count per type.
- **D-08:** Summary pattern analysis: categorize dual-code patients by temporal relationship (same-day, <30 days apart, 30-180 days, >180 days). This directly addresses the meeting note concern about whether dual diagnoses are real.
- **D-09:** Output as hl_nhl_overlap_validation.xlsx with three tabs: Summary (counts and pattern breakdown), Patient Detail (per-patient temporal data), Pattern Analysis (grouped statistics).

### Action Outcomes
- **D-10:** Report-only — no modifications to R/00_config.R, DRUG_GROUPINGS, or any existing scripts. Recommendations are captured in xlsx summary tabs and console output. Config changes, if needed, would be a separate follow-up phase.
- **D-11:** Raw counts without HIPAA suppression — manual suppression before sharing (v3.1/v3.2 convention).

### Output Structure
- **D-12:** Two xlsx output files: `code_verification.xlsx` (3 investigation tabs + Summary/Recommendations tab) and `hl_nhl_overlap_validation.xlsx` (Summary + Patient Detail + Pattern Analysis tabs).

### Claude's Discretion
- Exact script numbers (next available in investigation decade)
- Console logging structure and verbosity
- Tab ordering and column layout within xlsx files
- Whether to include percentage columns alongside raw counts in summaries
- R/88 smoke test section structure and check count for both new scripts
- Specific temporal buckets for overlap pattern analysis (exact day thresholds)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Code Classification Sources
- `all_codes_resolved_next_tables.xlsx` — Primary code reference. Line 11 = revenue code 0362 (organ transplant). Lines 3-22 = SCT status/complication codes (Z94.84, T86.5, T86.09, HEMATOLOGIC_TRANSPLANT_AND_ENDOC). Line 22+ = active SCT procedure codes.
- `R/00_config.R` — DRUG_GROUPINGS (lines 1599-1635 SCT codes, lines 3031-3073 immunotherapy codes), QUESTIONABLE_IMMUNO_CODES (lines 1876-1890), TREATMENT_CODES, ICD_CODES, CANCER_SITE_MAP
- `R/utils/utils_xlsx_lookups.R` — Code metadata loader from all_codes_resolved2.xlsx (Phase 91)

### HL+NHL Overlap Analysis
- `R/78_venn_lymphoma_3way.R` — Existing 3-way Venn (NLPHL vs Classical HL vs NHL) with patient-level flags. Template for OVERLAP-01 extension.
- `R/77_venn_hl_nlphl.R` — 2-way Venn (NLPHL vs Classical HL). Shows existing overlap analysis pattern.
- `R/utils/utils_cancer.R` — is_cancer_code(), classify_codes() 4-tier cascade for ICD code classification

### Investigation Script Patterns
- `R/31_pre_diagnosis_treatments.R` — Phase 104 TIMING-01 script. Template for investigation script structure (setup, validation, DuckDB query, analysis, xlsx output).
- `R/32_secondary_malignancy_table.R` — Phase 104 TIMING-02 script. Shows 7-day gap criterion pattern and multi-sheet xlsx output.

### Data Access & Utilities
- `R/utils/utils_duckdb.R` — get_pcornet_table() for DuckDB queries
- `R/utils/utils_dates.R` — parse_pcornet_date() for date parsing

### Meeting Notes Context
- `pecan_lymphoma_meeting_notes_combined.md` — G4 (HL+NHL overlap ~4,000/8,000), G8 (Ethna immunotherapy), G10 (organ transplant code line 11), G11 (SCT codes above line 22)

### Requirements
- `.planning/REQUIREMENTS.md` — CODE-01, CODE-02, CODE-03, OVERLAP-01 specifications

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `get_pcornet_table("PRESCRIBING")` / `get_pcornet_table("PROCEDURES")` / `get_pcornet_table("DIAGNOSIS")`: DuckDB queries for raw PCORnet table access
- `confirmed_hl_cohort.rds` (from R/47): ID, first_hl_dx_date, first_hl_dx_source — denominator/anchor for overlap analysis
- `R/78 venn_lymphoma_3way.R` patient classification logic: C82-C86 (ICD-10 NHL), 200/202 (ICD-9 NHL), C81 (HL) code detection — reuse for OVERLAP-01
- `openxlsx2` workbook pattern: wb_workbook() -> add_worksheet() -> add_data() -> styled headers -> save(). Established across R/29, R/30, R/31, R/32, R/53, R/57-R/59
- `assert_rds_exists()`, `assert_df_valid()`: Standard input validation from R/00_config.R

### Established Patterns
- Investigation script pattern: Section-based structure with console logging, loads existing RDS/DuckDB artifacts, self-contained analysis, produces styled xlsx output, no upstream modification
- Styled xlsx: dark header row (FF374151), white bold text, freeze panes, autofit column widths
- Console logging with glue: section headers ("=== SECTION N: ... ==="), row counts, summary statistics at each step

### Integration Points
- Reads: DuckDB tables (PRESCRIBING, PROCEDURES, DIAGNOSIS) via get_pcornet_table()
- Reads: `output/confirmed_hl_cohort.rds` (from R/47 via R/20) — for overlap analysis denominator
- Reads: `all_codes_resolved_next_tables.xlsx` — for code reference context (line numbers, recommendations)
- Writes: `output/code_verification.xlsx` (new file)
- Writes: `output/hl_nhl_overlap_validation.xlsx` (new file)
- Does NOT modify any existing scripts, RDS files, or xlsx files

</code_context>

<specifics>
## Specific Ideas

- Meeting note G4 flags Erin's skepticism about the ~4,000/8,000 dual-code rate — the overlap investigation should directly test whether same-day coding is the primary driver
- "Ethna" is likely a phonetic variant of "Enbrel" (etanercept brand name) from meeting notes — the investigation confirms the drug identity and validates it's correctly excluded
- Revenue code 0362 covers both solid organ and SCT — the key question is what fraction of the 192 records (90 patients) have corroborating SCT procedure evidence
- Z94.84 (SCT status) and T86.x (SCT complications) are diagnosis codes that inflate SCT patient counts if treated as treatment events — investigation confirms they are NOT in DRUG_GROUPINGS

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 105-code-overlap-verification*
*Context gathered: 2026-06-15*
