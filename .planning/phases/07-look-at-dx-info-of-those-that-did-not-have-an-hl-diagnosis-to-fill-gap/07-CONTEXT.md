# Phase 7: Dx Info of Non-HL Patients to Fill Gap - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Investigate the DIAGNOSIS, ENROLLMENT, and TUMOR_REGISTRY table content for the 19 patients excluded as "Neither" (no HL evidence in DIAGNOSIS or TUMOR_REGISTRY) to understand what diagnoses they DO have, characterize the data gap by site, and determine if the HL identification gap can be closed. Produces a standalone gap analysis script with focused CSV outputs. If findings reveal clear-cut recoverable HL patients, update the pipeline and rebuild; otherwise report only.

</domain>

<decisions>
## Implementation Decisions

### Diagnosis exploration scope
- **D-01:** Pull ALL diagnosis codes for the 19 Neither patients from the DIAGNOSIS table (full clinical history dump) PLUS a focused summary of lymphoma/cancer-related codes (C81-C96 ICD-10, 200-208 ICD-9)
- **D-02:** Also check ENROLLMENT and TUMOR_REGISTRY tables for these patients — enrollment spans, site info, and any TR records that weren't caught by the histology filter
- **D-03:** Stratify all exploration by site (AMS/UMI/FLM/VRT) to identify whether the gap clusters at specific partners (e.g., claims-only sites like FLM)

### Gap-filling strategy
- **D-04:** Claude reviews the actual codes found and recommends whether expansion of HL identification is justified based on clinical coding conventions (Claude's discretion)
- **D-05:** Patients with zero DIAGNOSIS records: flag as data quality issue AND cross-reference with ENROLLMENT to characterize the gap (have enrollment but no dx = coding gap; no enrollment either = phantom record)

### Output and reporting
- **D-06:** New standalone script `09_dx_gap_analysis.R` — separate from 07_diagnostics.R since this is a focused investigation, not a general diagnostic
- **D-07:** Produce multiple focused CSVs in output/diagnostics/:
  - `neither_all_diagnoses.csv` — all DX codes for the 19 patients
  - `neither_lymphoma_codes.csv` — cancer/lymphoma-related subset (C81-C96, 200-208)
  - `neither_patient_summary.csv` — one row per patient with site, dx count, enrollment info, TR data presence, and gap classification
- **D-08:** Console summary via message() in addition to CSVs

### Pipeline impact
- **D-09:** Conditional rebuild — if findings are clear-cut (e.g., missed ICD codes that should be in the HL code list), update 00_config.R / 03_cohort_predicates.R and rebuild the cohort in this phase. If ambiguous (requires clinical judgment), report findings only and defer pipeline changes
- **D-10:** Script depends on having run the full pipeline first (reads `excluded_no_hl_evidence.csv` from output/cohort/) — no code duplication of HL_SOURCE logic

### Claude's Discretion
- Whether any discovered codes justify expanding HL identification (D-04)
- Gap classification categories for neither_patient_summary.csv
- Exact lymphoma/cancer ICD code ranges to include in the focused filter
- Console summary format and level of detail
- Whether a pipeline rebuild is warranted based on findings

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Pipeline code (input and potential fix targets)
- `R/00_config.R` — ICD_CODES list (hl_icd10, hl_icd9, hl_histology). Fix target if new codes discovered.
- `R/03_cohort_predicates.R` — has_hodgkin_diagnosis() with HL_SOURCE tracking. Fix target if identification logic changes.
- `R/04_build_cohort.R` — Cohort assembly pipeline that writes excluded_no_hl_evidence.csv. Input dependency.
- `R/07_diagnostics.R` — Section 4 (HL Identification Source Comparison) for reference on existing Venn breakdown logic.
- `R/utils_icd.R` — is_hl_diagnosis(), is_hl_histology(), normalize_icd(). Potential fix targets.

### Data outputs (inputs to this phase)
- `output/cohort/excluded_no_hl_evidence.csv` — The 19 Neither patients. Primary input for gap analysis.
- `output/diagnostics/hl_identification_venn.csv` — Existing HL source breakdown by site.
- `output/diagnostics/hl_identification_detail.csv` — Per-patient HL source detail.

### Prior phase context
- `.planning/phases/05-fix-parsing-of-dates-and-other-possible-parsing-errors-and-investigate-why-not-everyone-has-an-hl-diagnosis/05-CONTEXT.md` — D-04 through D-09: HL diagnosis gap investigation decisions
- `.planning/phases/06-use-debug-output-to-rectify-issues/06-CONTEXT.md` — D-02: Neither exclusion logic, D-20: HL_SOURCE tracking

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `is_hl_diagnosis()` in utils_icd.R: ICD-9/10 matching with normalization. Can be used as a reference for building lymphoma-adjacent code checks.
- `is_hl_histology()` in utils_icd.R: ICD-O-3 histology matching (9650-9667). Reference for TR table exploration.
- `excluded_no_hl_evidence.csv`: Already contains the 19 patients with ID, SOURCE, and EXCLUSION_REASON columns.
- Section 4 of 07_diagnostics.R: HL Venn breakdown logic showing how dx_patients and tr_patients are identified.

### Established Patterns
- Named list storage: pcornet$TABLE_NAME for loaded data
- Console logging via message() + glue()
- CSV output via readr::write_csv() to output/diagnostics/
- Numbered script pattern: 09_dx_gap_analysis.R follows 08_data_quality_summary.R
- Script sources upstream: `source("R/01_load_pcornet.R")` for data access

### Integration Points
- Input: `output/cohort/excluded_no_hl_evidence.csv` (requires full pipeline to have been run)
- Input: pcornet$DIAGNOSIS, pcornet$ENROLLMENT, pcornet$TUMOR_REGISTRY1/2/3 tables
- Output: `output/diagnostics/neither_all_diagnoses.csv`, `neither_lymphoma_codes.csv`, `neither_patient_summary.csv`
- Potential fix targets: R/00_config.R (ICD_CODES), R/03_cohort_predicates.R (has_hodgkin_diagnosis)

</code_context>

<specifics>
## Specific Ideas

- The Mailhot extract (2025-09-15) should be all HL patients — 19 "Neither" patients out of the total population is a small but meaningful data quality gap worth understanding
- Claims-only sites (FLM) may have different dx coverage patterns than EHR-based sites (AMS, UMI)
- VRT is death-only — patients from VRT may have no DIAGNOSIS records at all
- The 00_config.R notes show "19 'Neither' patients excluded by Plan 01's HL_SOURCE tracking" and "Most patients are 'DIAGNOSIS only' (no TR data for most sources)"

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 07-look-at-dx-info-of-those-that-did-not-have-an-hl-diagnosis-to-fill-gap*
*Context gathered: 2026-03-25*
