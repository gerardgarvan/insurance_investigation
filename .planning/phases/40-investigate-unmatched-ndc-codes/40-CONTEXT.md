# Phase 40: Investigate Unmatched NDC Codes - Context

**Gathered:** 2026-05-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Investigate NDC codes and RXNORM CUIs in HL patient drug data (DISPENSING, PRESCRIBING, MED_ADMIN) that aren't captured by the current `TREATMENT_CODES` lists in `R/00_config.R`. Look up drug names via the RxNorm API, auto-classify each unmatched code into treatment categories using keyword matching, produce an xlsx report, and update `TREATMENT_CODES` with confirmed codes (new NDC vectors + expanded RXNORM).

</domain>

<decisions>
## Implementation Decisions

### Code Systems Scope
- **D-01:** Investigate both NDC codes (from DISPENSING.NDC) AND unmatched RXNORM CUIs (from PRESCRIBING, DISPENSING, MED_ADMIN) — current `chemo_rxnorm` only has 4 CUIs (ABVD regimen), so significant gaps are expected
- **D-02:** All 3 drug tables in scope: DISPENSING (NDC + RXNORM), PRESCRIBING (RXNORM), MED_ADMIN (RXNORM)
- **D-03:** Exclude ICD, DRG, revenue, CPT/HCPCS — those were covered by Phase 39

### Code Lookup Method
- **D-04:** Use NLM RxNorm API (rxnav.nlm.nih.gov) for both NDC-to-drug-name and RXNORM-to-drug-name resolution — free, no auth, same NLM infrastructure as Phase 39's HCPCS API
- **D-05:** NDC lookup endpoint: `/REST/ndcstatus` or `/REST/rxcui` for NDC-to-RxNorm mapping, then `/REST/rxcui/{rxcui}/properties` for drug name
- **D-06:** RXNORM lookup endpoint: `/REST/rxcui/{rxcui}/properties` for drug name directly

### Classification Strategy
- **D-07:** Fully automated classification via drug name keyword matching — same approach as Phase 39 (no manual review step)
- **D-08:** Treatment categories: chemo, radiation (unlikely for drugs but include), SCT-related, immunotherapy, supportive care, unrelated
- **D-09:** Keyword patterns based on known HL treatment drugs (doxorubicin, bleomycin, vinblastine, dacarbazine, brentuximab, nivolumab, filgrastim, ondansetron, etc.)

### Config Integration
- **D-10:** Add new NDC vectors to TREATMENT_CODES: `chemo_ndc`, `supportive_care_ndc`, etc. — keeps code types separate (existing pattern in TREATMENT_CODES)
- **D-11:** Expand `chemo_rxnorm` (and add new RXNORM vectors as needed) with newly discovered treatment-relevant RXNORM CUIs
- **D-12:** Produce xlsx report of all unmatched codes with drug names, classifications, patient counts, and source tables
- **D-13:** Produce RDS artifact for downstream config update consumption (same pattern as Phase 39)

### Claude's Discretion
- Specific RxNorm API endpoint selection and batching strategy
- Keyword classification rules (drug name patterns for each treatment category)
- xlsx report layout and styling (consistent with Phase 38/39 output patterns)
- Handling of NDC codes that don't resolve via RxNorm API (log as unresolved vs skip)
- Whether to add MED_ADMIN NDC codes (if MEDADMIN_CODE contains NDC values) or only DISPENSING.NDC

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Treatment Code Configuration
- `R/00_config.R` (lines 385-659) — Current `TREATMENT_CODES` lists including `chemo_rxnorm` (4 CUIs only), all NDC-relevant sections
- `R/00_config.R` (lines 97-120) — `REQUIRED_TABLES` list showing DISPENSING, MED_ADMIN, PRESCRIBING

### Phase 39 Implementation (Template)
- `R/39_investigate_unmatched.R` — Phase 39 investigation script (775 lines) — **primary template** for Phase 40's script structure (API lookup, classification, xlsx report, config update)
- `.planning/phases/39-investigate-unmatched-codes/39-CONTEXT.md` — Phase 39 decisions (Phase 40 mirrors the same approach for a different code system)

### Phase 38 Drug Data Extraction
- `R/38_treatment_inventory.R` (lines 239-278) — Existing NDC and RXNORM extraction from DISPENSING and MED_ADMIN tables — shows exactly how drug data is queried

### Data Loading Specs
- `R/01_load_pcornet.R` (lines 233-250) — DISPENSING_SPEC showing NDC, RAW_NDC, RXNORM_CUI columns
- `R/01_load_pcornet.R` (lines 255-270) — MED_ADMIN_SPEC showing MEDADMIN_CODE, RXNORM_CUI columns

### External API
- RxNorm API documentation: rxnav.nlm.nih.gov (NDC status, RxCUI properties endpoints)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/39_investigate_unmatched.R` — Full investigation pipeline template: API batching, classification, xlsx generation, config update function. Phase 40 can follow this same 8-section structure
- `R/38_treatment_inventory.R` `collect_all_drug_codes()` (lines 200-280) — Already extracts NDC + RXNORM from DISPENSING, PRESCRIBING, MED_ADMIN with patient counts
- `openxlsx2` styled workbook pattern from Phase 38/39 — reuse styling, sheet structure
- `TREATMENT_TYPE_COLORS` from R/39 — reuse color scheme for treatment categories

### Established Patterns
- TREATMENT_CODES uses named vectors grouped by code type: `chemo_hcpcs`, `chemo_rxnorm`, `radiation_cpt`, etc. — new NDC vectors follow this pattern (`chemo_ndc`, `supportive_care_ndc`)
- DuckDB backend via `get_pcornet_table()` for data access
- Config update via `readLines()`/`writeLines()` programmatic insertion (Phase 39's `update_config_treatment_codes()`)
- API batching with rate limiting and error handling (Phase 39's `lookup_hcpcs_batch()`)

### Integration Points
- `R/00_config.R` `TREATMENT_CODES` — primary update target for new NDC vectors and expanded RXNORM CUIs
- `R/03_cohort_predicates.R` — currently matches on RXNORM_CUI; would need updates to also match on NDC if NDC vectors are added
- `R/10_treatment_payer.R` — currently matches DISPENSING on RXNORM_CUI only; would need NDC matching logic if NDC vectors are added
- `output/` directory — xlsx report output location

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. Follow Phase 39 script structure closely as the template.

</specifics>

<deferred>
## Deferred Ideas

- Downstream script updates (R/03, R/10) to actually match on new NDC vectors — those scripts currently only use RXNORM_CUI for drug matching. Adding NDC matching to cohort/treatment pipelines is a separate phase.
- ICD-10-PCS broader range detection for drug administration codes
- Drug interaction or polypharmacy analysis

None of these were discussed as in-scope — all explicitly deferred.

</deferred>

---

*Phase: 40-investigate-unmatched-ndc-codes*
*Context gathered: 2026-05-04*
