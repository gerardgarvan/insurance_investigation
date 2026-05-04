# Phase 39: Investigate Unmatched Codes - Context

**Gathered:** 2026-05-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Investigate CPT/HCPCS codes that appear in HL patient data but aren't in the curated `TREATMENT_CODES` lists in `R/00_config.R`. Widen heuristic detection ranges beyond Phase 38's current patterns, auto-classify each unmatched code using CMS reference data, produce an xlsx report, and update `TREATMENT_CODES` with confirmed treatment codes.

</domain>

<decisions>
## Implementation Decisions

### Code Systems Scope
- **D-01:** CPT/HCPCS procedure codes only — no ICD-10-PCS, ICD-9, DRG, revenue, RXNORM, or NDC investigation this phase
- **D-02:** Widen heuristic ranges beyond Phase 38's current patterns:
  - Chemotherapy: J9xxx full range PLUS curated J0-J8 supportive care codes (growth factors like pegfilgrastim, antiemetics like ondansetron)
  - Radiation: 774xx delivery codes PLUS 773xx treatment planning codes (skip 772xx simulation)
  - SCT: existing 382xx range (no change)
  - Immunotherapy: existing XW0xx range (no change)
- **D-03:** Skip NDC-to-treatment mapping entirely this phase — stay focused on procedure codes

### Investigation Method
- **D-04:** Automated code-to-description lookup using CMS HCPCS/CPT reference CSV files downloaded to HiPerGator
- **D-05:** Auto-classify ALL unmatched codes into treatment categories: chemo, radiation, SCT, immunotherapy, supportive care, unrelated — no uncertainty flags, rely on heuristic classification rules
- **D-06:** No manual review step in the workflow — classification is fully automated

### Resolution Action
- **D-07:** Produce xlsx report of all unmatched codes with descriptions, classifications, and patient counts
- **D-08:** Automatically update `TREATMENT_CODES` in `R/00_config.R` with all auto-classified treatment codes (no patient count threshold)
- **D-09:** Phase 38's treatment inventory will pick up the expanded code lists on next run

### Claude's Discretion
- Choice of specific CMS reference file format and download approach
- Classification heuristic rules (keyword matching on descriptions, code family patterns)
- xlsx report layout and styling (consistent with Phase 38 output patterns)
- Which specific J0-J8 codes to include in the curated supportive care list

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Treatment Code Configuration
- `R/00_config.R` (lines 412-659) — Current `TREATMENT_CODES` lists and `CPT_HCPCS_RANGES` heuristic patterns

### Phase 38 Implementation
- `R/38_treatment_inventory.R` — Treatment inventory script with `detect_unknown_codes()` function (lines 686-749), heuristic range definitions (lines 57-73), xlsx output generation
- `.planning/phases/38-chemo-treatment-inventory-by-source-table/38-01-PLAN.md` — Phase 38 plan with code matching architecture

### External References
- CMS HCPCS quarterly update files — source for code descriptions (download during implementation)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `detect_unknown_codes(treatment_type)` in `R/38_treatment_inventory.R` (lines 686-749) — existing heuristic detection function, can be extended or used as pattern
- `CPT_HCPCS_RANGES` in `R/38_treatment_inventory.R` (lines 57-73) — current heuristic range definitions to widen
- `TREATMENT_CODES` in `R/00_config.R` (lines 412-659) — target for updates with newly classified codes
- xlsx output pattern from Phase 38 — styled workbook generation with openxlsx2

### Established Patterns
- Code matching uses two patterns: exact match (`%in%`) for full codes, prefix match (`str_detect`) for ICD-10-PCS prefixes — same distinction applies here
- DuckDB backend via `get_pcornet_table()` for data access
- Treatment types organized as named lists in `TREATMENT_CODES` (chemo_hcpcs, radiation_cpt, sct_cpt, etc.)

### Integration Points
- `R/00_config.R` `TREATMENT_CODES` — primary update target; all downstream scripts (R/03, R/09, R/38) read from this
- `R/38_treatment_inventory.R` `CPT_HCPCS_RANGES` — widened ranges should be updated here too
- `output/` directory — xlsx report output location

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

- NDC-to-treatment mapping for drugs in DISPENSING/PRESCRIBING/MED_ADMIN — large scope, potentially its own phase
- ICD-10-PCS broader range detection (3E0x chemo admin, D7x radiation beyond current prefixes)
- ICD-9/DRG/revenue code gap analysis

None of these were discussed as in-scope — all explicitly deferred.

</deferred>

---

*Phase: 39-investigate-unmatched-codes*
*Context gathered: 2026-05-04*
