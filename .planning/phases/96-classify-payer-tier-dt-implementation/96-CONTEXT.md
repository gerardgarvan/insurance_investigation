# Phase 96: classify_payer_tier_dt() Implementation - Context

**Gathered:** 2026-06-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Create a data.table variant of `classify_payer_tier()` — the most-called payer utility function — and validate it produces identical output to the existing dplyr version. The function uses keyed joins against LOOKUP_TABLES_DT and fcase() logic internally but returns results compatible with the existing pipeline. Callers (R/60, R/61, R/62) remain on the dplyr version until their own migration phases (97-98).

</domain>

<decisions>
## Implementation Decisions

### Function Placement
- **D-01:** Place `classify_payer_tier_dt()` in `R/utils/utils_payer.R` alongside the existing `classify_payer_tier()`. Both versions of the same function in one file for easy side-by-side comparison. Callers already source this file via R/00_config.R auto-sourcing.

### Caller Migration Timing
- **D-02:** Defer caller migration to their own phases. Phase 96 only creates and validates the function. R/60 switches in Phase 97, R/61/R/62 switch in Phase 98. No existing script behavior changes in Phase 96.

### Parity Validation Approach
- **D-03:** Create a standalone validation script `R/96_validate_payer_dt.R` (following the Phase 95 pattern of R/95_validate_dt_infrastructure.R). Runs both classify_payer_tier() and classify_payer_tier_dt() on ENCOUNTER data, compares all output columns row-by-row, logs pass/fail. Can run on HiPerGator production data.

### Return Type
- **D-04:** Claude's Discretion — choose return type (tibble vs data.table) based on how the function will actually be used in R/60, R/61, R/62 downstream. Success criteria says "tibble with payer_category column" which leans toward tibble return, but Claude may choose data.table if it makes the Phase 97-98 migration cleaner.

### Claude's Discretion
- Return type decision (D-04): tibble vs data.table based on actual caller patterns
- Internal implementation details: fcase() vs fifelse(), join syntax, copy() placement
- API signature: whether to match classify_payer_tier(df, include_dual, flm_override) exactly or adjust parameter names
- Validation script structure and specific checks within R/96

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` -- PAYER-01 (function using keyed joins and fcase()) and PAYER-02 (output parity validation on fixture data)
- `.planning/ROADMAP.md` -- Phase 96 success criteria (4 testable assertions)

### Existing Implementation (dplyr version to replicate)
- `R/utils/utils_payer.R` -- classify_payer_tier() function (lines 93-177), CODE_TO_TIER() function (lines 45-58), is_missing_payer() function (lines 32-36)
- `R/00_config.R` -- PAYER_MAPPING list (sentinel_values, dual_eligible_codes, prefix_fallback, categories), AMC_PAYER_LOOKUP named vector, TIER_MAPPING named list

### Phase 95 Infrastructure (consumed by this phase)
- `R/utils/utils_dt.R` -- ensure_dt(), to_tibble_safe(), get_lookup_dt() conversion helpers
- `R/00_config.R` (lines 3430-3532) -- LOOKUP_TABLES_DT with keyed AMC_PAYER_LOOKUP and TIER_MAPPING data.tables
- `.planning/phases/95-infrastructure-setup/95-CONTEXT.md` -- D-01 through D-05 decisions that constrain this phase

### Callers (reference only, not modified in this phase)
- `R/60_tiered_same_day_payer.R` (line 90) -- classify_payer_tier(include_dual=TRUE, flm_override=FALSE)
- `R/61_tiered_encounter_level.R` (line 79) -- classify_payer_tier(include_dual=TRUE, flm_override=TRUE)
- `R/62_tiered_date_level.R` (line 122) -- classify_payer_tier(include_dual=FALSE, flm_override=TRUE)

### Validation Pattern
- `R/95_validate_dt_infrastructure.R` -- Phase 95 validation script pattern to follow for R/96

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ensure_dt()` in utils_dt.R: Convert input tibble to data.table at function entry with defensive guards
- `to_tibble_safe()` in utils_dt.R: Convert data.table result back to tibble at function exit
- `get_lookup_dt("AMC_PAYER_LOOKUP")`: Retrieve keyed payer lookup table for joins
- `get_lookup_dt("TIER_MAPPING")`: Retrieve keyed tier mapping table for joins
- `PAYER_MAPPING$sentinel_values`: c("NI", "UN", "OT") — used for effective_payer resolution
- `PAYER_MAPPING$dual_eligible_codes`: c("14", "141", "142") — used for dual_eligible flag
- `PAYER_MAPPING$prefix_fallback`: Named list mapping first digit to payer category

### Established Patterns
- classify_payer_tier() uses dplyr case_when() for effective_payer resolution (primary → secondary → NA cascade)
- AMC_PAYER_LOOKUP used as named vector lookup: `AMC_PAYER_LOOKUP[effective_payer]`
- TIER_MAPPING used as named list: `TIER_MAPPING[tier]` for rank assignment
- CODE_TO_TIER() function wraps case_when() for category → tier mapping (1:1 mapping, same strings)
- Special codes 93/14 override tier to "Medicaid" regardless of lookup result
- FLM source override: conditionally set tier to "Medicaid" when SOURCE == "FLM"
- Phase 95 validation pattern: numbered checks with pass/fail messaging and stopifnot() assertions

### Integration Points
- classify_payer_tier_dt() will be consumed by Phase 97 (R/60 migration) and Phase 98 (R/61, R/62 migration)
- R/88 smoke test already checks classify_payer_tier exists (line 155) — may need updating for _dt variant
- LOOKUP_TABLES_DT$AMC_PAYER_LOOKUP keyed on `code` column — join on effective_payer
- LOOKUP_TABLES_DT$TIER_MAPPING keyed on `payer_category` column — join on payer_category

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard data.table optimization approaches for the function internals.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 96-classify-payer-tier-dt-implementation*
*Context gathered: 2026-06-10*
