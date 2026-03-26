# Phase 9: Expand Treatment Detection Using Docx-Specified Tables and Researched Codes - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Expand treatment detection for the existing 3 treatment types (chemotherapy, radiation, SCT) to cover all data sources specified in `TreatmentVariables_2024.07.17.docx`. This includes adding new PCORnet tables (DISPENSING, MED_ADMIN), querying new columns in already-loaded tables (DIAGNOSIS treatment codes, ENCOUNTER DRG codes, PROCEDURES revenue codes), and researching clinically appropriate code sets where the docx references unavailable xlsx files. The expanded detection feeds into both HAD_* flags (03_cohort_predicates.R) and treatment-anchored payer computation (10_treatment_payer.R). No new treatment types (surgery, ancillary therapy) or treatment intensity variables are added in this phase.

</domain>

<decisions>
## Implementation Decisions

### Treatment Type Scope
- **D-01:** Keep the same 3 treatment types: chemotherapy, radiation, SCT. Do NOT add surgery, ancillary therapy, or treatment intensity in this phase.
- **D-02:** Expand all 3 types to include every data source the docx specifies (PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, DIAGNOSIS, ENCOUNTER).
- **D-03:** Expanded detection feeds BOTH the HAD_* flags (has_chemo, has_radiation, has_sct in 03_cohort_predicates.R) AND the treatment-anchored payer computation (compute_payer_at_* in 10_treatment_payer.R). More anchor date sources = better payer match coverage.

### Code Ranges and Research
- **D-04:** Do NOT blindly use the full CPT ranges from the docx (96401-96549 for chemo, 70010-79999 for radiation). The radiation range especially is too broad (includes diagnostic radiology). Have the researcher identify clinically appropriate subsets for Hodgkin Lymphoma.
- **D-05:** DRG codes explicitly listed in the docx text can be used as-is: chemo DRGs 837-839, 846-848; radiation DRG 849; SCT DRGs 014-017.
- **D-06:** For the 125 ICD-10-PCS chemo codes (docx references unavailable "PCS Codes Cancer Tx.xlsx"), have the researcher identify the appropriate ICD-10-PCS codes for cancer chemotherapy administration.
- **D-07:** ICD-9 procedure codes from docx text: add V58.11, V58.12, 99.28 to chemo (99.25 already present); add V58.0 to radiation.

### Data Source Expansion
- **D-08:** Load DISPENSING and MED_ADMIN as new PCORnet CDM tables in 01_load_pcornet.R with full col_types specifications (matching existing table pattern).
- **D-09:** Add DIAGNOSIS-based treatment evidence: Z51.11/Z51.12 (ICD-10) and V58.11/V58.12 (ICD-9) for chemo; Z51.0 (ICD-10) and V58.0 (ICD-9) for radiation; Z94.81/T86.5/T86.09/Z48.290/T86.0 (ICD-10) for SCT.
- **D-10:** Add ENCOUNTER DRG-based treatment evidence: DRGs 837-839, 846-848 for chemo; DRG 849 for radiation; DRGs 014-017 for SCT.
- **D-11:** Add PROCEDURES PX_TYPE="RE" (revenue code) detection: 0335/0332/0331 for chemo; 0330/0333 for radiation; 0362/0815 for SCT.
- **D-12:** For DISPENSING and MED_ADMIN, match on RXNORM_CUI only (no NDC matching). This avoids the need for a SEER*Rx NDC-to-category mapping file. Use the same RXNORM CUI list already in TREATMENT_CODES$chemo_rxnorm.

### Output Structure
- **D-13:** Update existing functions in-place: modify has_chemo(), has_radiation(), has_sct() in 03_cohort_predicates.R and compute_payer_at_chemo/radiation/sct() in 10_treatment_payer.R. No new wrapper functions or toggle flags.
- **D-14:** Log aggregate source contribution counts per treatment type: e.g., "Chemo detected: 450 via PROCEDURES, 23 via DIAGNOSIS, 8 via DRG, 5 via DISPENSING". No per-patient source tracking columns.
- **D-15:** New tables (DISPENSING, MED_ADMIN) get full col_types specifications in 01_load_pcornet.R, researcher identifies key columns from PCORnet CDM spec.

### Claude's Discretion
- Exact col_types for DISPENSING and MED_ADMIN tables (researcher determines from PCORnet CDM v7.0 spec)
- Internal refactoring of has_*() and compute_payer_at_*() functions to accommodate new sources cleanly
- How to handle date columns in DISPENSING (DISPENSE_DATE) and MED_ADMIN (MEDADMIN_START_DATE) for treatment date anchoring
- Whether to add the new code lists as new vectors in TREATMENT_CODES or extend existing vectors
- Order of source checking within each treatment type function

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Treatment variable specification
- `TreatmentVariables_2024.07.17.docx` -- Defines all treatment detection sources by PCORnet table, code type, and specific codes. This is the authoritative reference for what sources to cover. Cannot be read directly (binary); text extraction available in 09-CONTEXT.md domain section.

### Existing treatment code configuration
- `R/00_config.R` -- TREATMENT_CODES list (current chemo_hcpcs, chemo_rxnorm, radiation_cpt, sct_cpt, plus ICD procedure code lists from Phase 8). New code lists from expanded detection go here.
- `R/00_config.R` -- CONFIG$analysis$treatment_window_days = 30 (reused for expanded payer anchoring)

### Treatment detection functions
- `R/03_cohort_predicates.R` Section 2 -- has_chemo(), has_radiation(), has_sct() functions. These are the functions to expand with new sources.
- `R/10_treatment_payer.R` -- compute_payer_at_chemo/radiation/sct() and compute_payer_mode_in_window(). These extract FIRST_*_DATE and compute PAYER_AT_*. Expand date extraction sources.

### Data loading
- `R/01_load_pcornet.R` -- PCORnet table loading with col_types. Add DISPENSING and MED_ADMIN here.

### Pipeline integration
- `R/04_build_cohort.R` Section 6 -- Treatment flags join. Section 6.5 -- Treatment-anchored payer. No structural changes needed (same columns, just broader detection).

### PCORnet CDM specification
- PCORnet CDM v7.0 specification (external) -- Column definitions for DISPENSING (DISPENSINGID, PRESCRIBINGID, DISPENSE_DATE, NDC, DISPENSE_SUP, DISPENSE_AMT, RAW_NDC) and MED_ADMIN (MEDADMINID, MEDADMIN_TYPE, MEDADMIN_CODE, MEDADMIN_START_DATE, MEDADMIN_STOP_DATE, RXNORM_CUI)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `compute_payer_mode_in_window()` in 10_treatment_payer.R: Generic function that joins encounters to anchor dates, filters to +/- window. Already works with any tibble(ID, date_column). New date sources just produce more anchor dates.
- `TREATMENT_CODES` in 00_config.R: Named list structure for code lists. New codes (DRG, revenue, diagnosis, ICD-10-PCS) follow same pattern.
- `encounters` tibble from 02_harmonize_payer.R: Already has payer_category per encounter with ADMIT_DATE. Unchanged for this phase.

### Established Patterns
- Treatment flag functions return tibble(ID, HAD_*) with integer 0/1 flags, combining multiple sources via union of patient IDs
- Treatment payer functions extract first dates from PROCEDURES/PRESCRIBING, then call compute_payer_mode_in_window()
- PX_TYPE matching: "CH" for CPT/HCPCS, "09" for ICD-9-CM, "10" for ICD-10-PCS. Adding "RE" for revenue codes.
- ICD-10-PCS prefix matching uses str_starts() for variable-length codes
- Null-safe table access: `if (!is.null(pcornet$TABLE)) { ... }` pattern for tables that may not exist
- Source logging via message(glue("...")) with formatted counts

### Integration Points
- 01_load_pcornet.R: Add DISPENSING and MED_ADMIN to PCORNET_TABLES vector and col_types_* specifications
- 00_config.R TREATMENT_CODES: Add new code vectors (chemo_drg, radiation_drg, sct_drg, chemo_revenue, radiation_revenue, sct_revenue, chemo_dx_icd10, chemo_dx_icd9, radiation_dx_icd10, radiation_dx_icd9, sct_dx_icd10, expanded ICD-10-PCS codes)
- 03_cohort_predicates.R: Expand has_chemo/radiation/sct() to query DISPENSING, MED_ADMIN, DIAGNOSIS, ENCOUNTER
- 10_treatment_payer.R: Expand compute_payer_at_*() date extraction to include new sources

</code_context>

<specifics>
## Specific Ideas

- The docx text is the authoritative source for which tables and code types to query per treatment category. The exact code values come from research (ICD-10-PCS) or the docx text itself (DRG numbers, revenue codes, diagnosis codes).
- DISPENSING and MED_ADMIN matching uses RXNORM CUI only, NOT NDC codes, to avoid need for SEER*Rx mapping.
- Researcher should identify clinically appropriate CPT/HCPCS subsets rather than using the full docx ranges (70010-79999 for radiation is too broad).
- DRG codes from docx text can be hardcoded directly since they're explicitly enumerated with descriptions.

</specifics>

<deferred>
## Deferred Ideas

- **Surgery treatment type** (HAD_SURGERY, FIRST_SURGERY_DATE, PAYER_AT_SURGERY) -- requires ComprehensiveSurgeryCodes.xlsx, its own phase
- **Ancillary therapy** (HAD_ANCILLARY) -- requires SEER*Rx NDC category mapping, future phase
- **Treatment Intensity variable** -- derived ordinal (None/Surgery only/.../SCT), depends on surgery being implemented first
- **NDC-based detection** in DISPENSING/MED_ADMIN -- deferred pending SEER*Rx mapping file availability
- **Multimodal treatment flag** -- combination variable from the docx, future phase

</deferred>

---

*Phase: 09-expand-treatment-detection-using-docx-specified-tables-and-researched-codes*
*Context gathered: 2026-03-26*
