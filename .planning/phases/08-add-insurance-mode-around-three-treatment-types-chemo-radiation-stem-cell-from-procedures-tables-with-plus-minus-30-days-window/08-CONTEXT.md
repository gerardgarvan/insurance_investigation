# Phase 8: Insurance Mode Around Treatment Types - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

For each of three treatment types (chemotherapy, radiation, stem cell transplant), compute the patient's insurance payer mode within a ±30 day window around the first treatment procedure date. Adds PAYER_AT_CHEMO, PAYER_AT_RADIATION, PAYER_AT_SCT columns (plus first treatment dates) to the existing hl_cohort output.

</domain>

<decisions>
## Implementation Decisions

### Treatment Date Source
- **D-01:** Anchor the ±30 day window on PX_DATE from the PROCEDURES table (not TUMOR_REGISTRY dates)
- **D-02:** Include ALL procedure code types: PX_TYPE == "CH" (HCPCS/CPT) AND PX_TYPE == "09" (ICD-9 procedure) AND PX_TYPE == "10" (ICD-10-PCS)
- **D-03:** For chemotherapy specifically, also anchor on RX_ORDER_DATE from PRESCRIBING table when RXNORM_CUI matches chemo codes — more anchor points for chemo
- **D-04:** Will need to add ICD-9-CM and ICD-10-PCS procedure code lists for chemo, radiation, and SCT to 00_config.R TREATMENT_CODES

### Window Anchor Point
- **D-05:** Use the FIRST treatment procedure date per patient per treatment type as the window anchor (mirrors PAYER_CATEGORY_AT_FIRST_DX pattern)
- **D-06:** Capture first treatment dates as output columns: FIRST_CHEMO_DATE, FIRST_RADIATION_DATE, FIRST_SCT_DATE
- **D-07:** Payer mode computed from encounters within ±30 days of that first date, using CONFIG$analysis$treatment_window_days (already defined as 30)

### Output Structure
- **D-08:** Add new columns directly to hl_cohort in 04_build_cohort.R: PAYER_AT_CHEMO, PAYER_AT_RADIATION, PAYER_AT_SCT, FIRST_CHEMO_DATE, FIRST_RADIATION_DATE, FIRST_SCT_DATE
- **D-09:** Create new standalone script (e.g., 10_treatment_payer.R) with functions, sourced by 04_build_cohort.R
- **D-10:** Column naming follows existing pattern: PAYER_AT_CHEMO / PAYER_AT_RADIATION / PAYER_AT_SCT (consistent with PAYER_CATEGORY_AT_FIRST_DX)

### No-Match Handling
- **D-11:** When a patient has treatment evidence but no encounters with valid payer within ±30 days, set payer column to NA (honest about missing data)
- **D-12:** Log match counts per treatment type: "PAYER_AT_CHEMO: N matched, M no encounters in window (NA)" — consistent with existing pipeline logging style

### Claude's Discretion
- ICD-9-CM and ICD-10-PCS procedure code selection for chemo, radiation, and SCT
- Internal function structure within 10_treatment_payer.R
- Exact placement of the source() call and column joins in 04_build_cohort.R
- Whether to reuse existing `encounters` object from 02_harmonize_payer.R or re-query

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing pipeline code
- `R/00_config.R` — TREATMENT_CODES list (chemo_hcpcs, chemo_rxnorm, radiation_cpt, sct_cpt), CONFIG$analysis$treatment_window_days = 30
- `R/02_harmonize_payer.R` §4c — PAYER_CATEGORY_AT_FIRST_DX computation pattern (mode within ±30 days of first HL DX using encounters table)
- `R/03_cohort_predicates.R` §2 — has_chemo(), has_radiation(), has_sct() functions showing current treatment identification logic
- `R/04_build_cohort.R` §6 — Treatment flags join pattern, §7 final cohort column assembly

### PCORnet CDM
- `R/01_load_pcornet.R` — PROCEDURES table loading with col_types (PX, PX_TYPE, PX_DATE columns)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `compute_effective_payer()` in 02_harmonize_payer.R: Already computes effective payer per encounter with sentinel value handling
- `map_payer_category()` in 02_harmonize_payer.R: Maps effective payer to 9-category system with dual-eligible override
- `encounters` tibble in 02_harmonize_payer.R: Already has payer_category computed per encounter with ADMIT_DATE
- PAYER_CATEGORY_AT_FIRST_DX computation in 02_harmonize_payer.R §4c: Direct template for the ±30 day mode calculation — same pattern, different anchor date
- TREATMENT_CODES in 00_config.R: Existing HCPCS/CPT/RXNORM code lists (need ICD procedure codes added)

### Established Patterns
- Mode calculation: group_by(ID, payer_category) %>% summarise(n = n()) %>% arrange(desc(n)) %>% slice(1) — used in both PAYER_CATEGORY_PRIMARY and PAYER_CATEGORY_AT_FIRST_DX
- Treatment flag functions return tibble(ID, HAD_*) with integer 0/1 flags
- Pipeline logging: message(glue("...")) with formatted counts and percentages
- Named predicate convention: has_*, with_*, exclude_* functions

### Integration Points
- 04_build_cohort.R Section 6 (Treatment Flags) — new script would be sourced here
- 04_build_cohort.R Section 7 (Final Cohort Assembly) — new columns added to select()
- 00_config.R TREATMENT_CODES — ICD procedure codes added here
- encounters tibble from 02_harmonize_payer.R — available in R environment at cohort build time

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. The implementation should mirror the existing PAYER_CATEGORY_AT_FIRST_DX pattern as closely as possible, applied three times (once per treatment type) with procedure-date anchors instead of diagnosis-date anchors.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 08-add-insurance-mode-around-three-treatment-types-chemo-radiation-stem-cell-from-procedures-tables-with-plus-minus-30-days-window*
*Context gathered: 2026-03-25*
