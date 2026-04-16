# Phase 25: Close Gaps Between Code and OneFLQuestions/QuantAnalysisMtgNotes - Context

**Gathered:** 2026-04-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Close analytical gaps between the existing R pipeline and action items/questions from two meeting documents: OneFLQuestions.docx (undated) and QuantAnalysisMtgNotes_ZoomAI.docx (meetings on 03/24/2026 and 04/07/2026). Prioritize lowest-hanging fruit first.

The 8 concrete gaps identified are:
1. Break out "Missing" post-treatment insurance into "no payer info" vs "no encounters"
2. QA comparison of DX_DATE from DIAGNOSIS table vs TUMOR_REGISTRY
3. Implement tumor registry DX_DATE as primary for sites that have TR data
4. FLM claims vs site-EHR encounter overlap analysis
5. Medicaid patients without treatment: DX date vs enrollment window check
6. Orlando Health impossible enrollment dates (279 records)
7. Sensitivity analysis: exclude FLM claims comparison
8. Source precedence documentation

</domain>

<decisions>
## Implementation Decisions

### Missing Insurance Breakdown
- **D-01:** 3-way split for all "Missing" payer categories: (A) "No Post-Treatment Encounters" (patient has zero encounters after last treatment date), (B) "Payer Data Missing" (patient has encounters but all have NA/NI/OT payer data), (C) existing valid payer categories unchanged.
- **D-02:** Apply the 3-way split to ALL treatment-anchored payer columns: POST_TREATMENT_PAYER, POST_CHEMO_PAYER, POST_RAD_PAYER, POST_SCT_PAYER, PAYER_AT_CHEMO, PAYER_AT_RADIATION, PAYER_AT_SCT.
- **D-03:** Add new columns to cohort CSV output AND update PPTX tables to reflect the breakdown.

### DX Date QA & Sourcing
- **D-04:** Produce a QA comparison CSV: per-patient DX_DATE from DIAGNOSIS table vs DX_DATE from TUMOR_REGISTRY, showing concordance, discrepancies, and days difference.
- **D-05:** Implement tumor registry DX_DATE as primary for sites that have TR data (LNK, ORL, UFH), DIAGNOSIS table DX_DATE as fallback.
- **D-06:** Add three columns to cohort output: DX_DATE_TR (from tumor registry), DX_DATE_DIAG (from diagnosis table), DX_DATE_SOURCE (flag: "TR", "DIAG", or "BOTH" when concordant). FIRST_DX_DATE uses TR when available, DIAG as fallback.

### FLM Claims vs EHR Overlap
- **D-07:** New standalone diagnostic script for FLM/site encounter overlap. For patients with BOTH FLM claims AND site-specific EHR encounters, compare payer completeness, encounter volume, and date coverage side-by-side. Output CSV + console summary.

### Medicaid QA
- **D-08:** Separate standalone diagnostic CSV: for Medicaid-payer patients with HAD_CHEMO/RADIATION/SCT = FALSE, classify whether FIRST_DX_DATE falls before, during, or after their ENROLLMENT start/end dates.

### Orlando Health Impossible Dates
- **D-09:** Add enrollment date validation: dates > today + 1 year flagged as ENR_DATE_VALID = FALSE. Log count, write flagged records to diagnostic CSV, set impossible dates to NA in the pipeline. Follows existing _VALID suffix pattern from Phase 6.

### Sensitivity Analysis
- **D-10:** Exclude-FLM-claims comparison: run key payer summary tables with (a) all data and (b) FLM-claims encounters excluded. Output side-by-side CSVs showing how payer distributions shift. Addresses 04/07 meeting suggestion from Myra.

### Source Precedence
- **D-11:** Document existing primary site strategy (inner_join on SOURCE from DEMOGRAPHIC) and the source precedence decision in code comments and diagnostic output.

### Claude's Discretion
- Script numbering and naming for new diagnostic scripts
- Internal implementation details for the 3-way payer split logic
- Column ordering in new CSV outputs
- Whether to combine smaller analyses into fewer scripts or keep each standalone

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Meeting Documents (Gap Source)
- `OneFLQuestions.docx` -- Questions for OneFL+ team about data quality, source precedence, missing payer handling, ORL dates, FLM overlap, sensitivity analysis
- `QuantAnalysisMtgNotes_ZoomAI.docx` -- Two meetings: 03/24/2026 (insurance table review, DX date sourcing, Missing breakdown) and 04/07/2026 (UF missingness, Medicaid QA, sensitivity analysis)

### Core Pipeline Scripts (Modification Targets)
- `R/04_build_cohort.R` -- Cohort building pipeline; will need DX_DATE sourcing changes (D-05, D-06) and enrollment date validation (D-09)
- `R/10_treatment_payer.R` -- Treatment-anchored payer computation; compute_payer_mode_in_window() needs 3-way split logic (D-01, D-02)
- `R/11_generate_pptx.R` -- PPTX generation; rename_payer() and post-treatment table logic need updating for 3-way split (D-03)
- `R/02_harmonize_payer.R` -- Payer harmonization; reference for encounter-level payer data structure
- `R/00_config.R` -- Configuration; ICD_CODES lists, site mappings, treatment window settings

### Pattern References (Existing Diagnostic Scripts)
- `R/18_uf_insurance_missingness.R` -- Phase 19 standalone diagnostic pattern
- `R/19_flm_duplicate_dates.R` -- Phase 20 standalone diagnostic pattern
- `R/20_all_source_missingness.R` -- Phase 21 all-source grouped analysis pattern
- `R/21_all_site_duplicate_dates.R` -- Phase 22 all-site grouped analysis pattern

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `rename_payer()` in R/11_generate_pptx.R: Currently maps Other/Unavailable/Unknown/NA to "Missing". Will need modification for 3-way split.
- `compute_payer_mode_in_window()` in R/10_treatment_payer.R: Returns NA when no encounters in window. Logic here distinguishes "no encounters" from "encounters with missing payer".
- `_VALID` suffix pattern from Phase 6: Used for age, tumor size, date range validation. Reuse for enrollment date validation (D-09).
- `save_output_data()` helper in R/utils_snapshot.R: Consistent RDS snapshot writing.
- `PAYER_MAPPING$sentinel_values` in R/00_config.R: NA, empty, NI, UN, OT, 99, 9999 -- the missingness definition.
- Standalone diagnostic script pattern: Phases 19-22 all follow source() -> load data -> analyze -> write CSVs to output/tables/ -> console summary.

### Established Patterns
- Post-treatment columns use asymmetric case_when: preserves NA as NA (not mapped to "Missing") so "No Payer Assigned" / "N/A" row logic works in PPTX.
- TUMOR_REGISTRY_ALL pre-built in 01_load_pcornet.R (bind_rows of TR1/2/3).
- Cohort build follows filter chain: DEMOGRAPHIC -> HL identification -> enrollment -> payer -> treatment flags -> derived columns.
- FIRST_DX_DATE currently derived from DIAGNOSIS table only (first HL diagnosis encounter date).

### Integration Points
- FIRST_DX_DATE change (D-05/D-06) cascades to: AGE_AT_DX, DAYS_DX_TO_CHEMO, DAYS_DX_TO_RADIATION, DAYS_DX_TO_SCT, and all post-diagnosis surveillance/survivorship columns.
- PPTX table updates (D-03) cascade to: all 3 treatment-specific post-treatment tables + the combined post-treatment table.
- Enrollment date validation (D-09) could affect enrollment-based filtering in cohort build.

</code_context>

<specifics>
## Specific Ideas

- The 03/24 meeting noted 53% of chemo patients have missing post-treatment insurance -- the 3-way split should make this more actionable
- Sites with tumor registry data are specifically: LNK, ORL, UFH (from 00_config.R comment line 257)
- Orlando Health has exactly 277 records at 2173-09-27 and 2 at 2078-12-31 (from OneFLQuestions.docx)
- The 04/07 meeting explicitly suggested "running analyses that exclude Medicaid claims to focus on EHR data alone" (Myra's suggestion)
- "Lowest hanging fruit first" ordering: enrollment date flags and source documentation are simplest, followed by diagnostic scripts, then the cohort-modifying changes (DX date, payer split)

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 25-close-gaps*
*Context gathered: 2026-04-15*
