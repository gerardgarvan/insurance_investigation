# Phase 36: All-Encounter Payer Frequency & Same-Day Categorization (AMC 8-Category) - Context

**Gathered:** 2026-04-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Refactor R/36_tiered_same_day_payer.R (Phase 35's script) to use the centralized AMC 8-category payer coding from R/00_config.R instead of PayerVariable.xlsx. Remove PayerVariable.xlsx dependency, remove duplicated local mapping functions, and use AMC_PAYER_LOOKUP + prefix fallback for all category assignments. Same 12 CSV outputs with updated AMC categories. R/35 (Phase 34 baseline) stays untouched.

</domain>

<decisions>
## Implementation Decisions

### Script Strategy
- **D-01:** Update R/36_tiered_same_day_payer.R in-place. No new script file. R/36 already has dual-scope coverage (all encounters + AV+TH) with frequency tables and same-day resolution.
- **D-02:** R/35_payer_code_frequency_av_th.R (Phase 34) remains as a historical baseline using PayerVariable.xlsx. It is NOT modified by this phase.

### AMC Category Mapping
- **D-03:** Use AMC_PAYER_LOOKUP from R/00_config.R as the sole category mapping source. Remove PayerVariable.xlsx loading (readxl dependency no longer needed in R/36).
- **D-04:** Keep prefix-based fallback from PAYER_MAPPING$prefix_fallback in config.R for codes not found in AMC_PAYER_LOOKUP. Every code gets a category.
- **D-05:** Frequency table output columns: code, amc_category, n, pct. No description column (AMC_PAYER_LOOKUP has no descriptions). Category summary aggregates by the 8 AMC categories: Medicaid, Medicare, Private, Other govt, Other, Self-pay, Uninsured, Missing.

### Refactoring
- **D-06:** Remove local function copies (map_payer_category_local, compute_effective_payer_local, detect_dual_eligible_local). Use centralized logic from config.R — AMC_PAYER_LOOKUP is already loaded via source("R/00_config.R").
- **D-07:** Remove Section 1 (Load PayerVariable.xlsx) entirely. Remove PAYER_XLSX_PATH constant. Remove readxl from library() calls.
- **D-08:** The CODE_TO_TIER function mapping AMC categories to resolution tiers stays — it's specific to the same-day resolution logic and maps from AMC 8 categories to the 7 resolution tiers (Other govt collapses to Other).

### Output Deliverables
- **D-09:** Same 12 CSV filenames, same structure, content updated with AMC categories instead of PayerVariable.xlsx categories. Existing output files get overwritten on next HiPerGator run.
- **D-10:** Resolution CSVs already use AMC categories (via CODE_TO_TIER) — those need minimal or no changes. Frequency table CSVs are the primary update target.

### Claude's Discretion
- How to handle the left_join-based frequency table logic when switching from PayerVariable.xlsx lookup to AMC_PAYER_LOOKUP vector
- Whether to use map_payer_category() from R/02_harmonize_payer.R or inline AMC_PAYER_LOOKUP lookups
- Console summary format adjustments (if any) for the new column layout
- Whether compute_effective_payer and detect_dual_eligible should be sourced from R/02_harmonize_payer.R or remain inline (simplified)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### AMC 8-Category Mapping (Primary Reference)
- `R/00_config.R` lines 239-362 — AMC_PAYER_LOOKUP named vector (code→category), PAYER_MAPPING$prefix_fallback, PAYER_MAPPING$categories (8 standard categories), PAYER_MAPPING$sentinel_values
- `payer_primary_codes_frequency_AMC.xlsx` — Source spreadsheet for AMC_PAYER_LOOKUP with "New Category" overrides

### Script Being Modified
- `R/36_tiered_same_day_payer.R` — Phase 35 dual-scope script: frequency tables + same-day resolution, 486 lines. This is the file being refactored.

### Existing Payer Logic
- `R/02_harmonize_payer.R` — map_payer_category(), compute_effective_payer(), detect_dual_eligible() functions. Reference for centralized payer logic that R/36 local copies were based on.

### Infrastructure
- `R/utils_duckdb.R` — get_pcornet_table(), open_pcornet_con(), materialize() helpers

### Amy Crisp Framework
- `payer_framework.txt` — Same-day resolution hierarchy specification (Medicaid > Medicare > Private > Other > Self-pay > Uninsured > Missing). Still applies — resolution logic unchanged.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AMC_PAYER_LOOKUP` in R/00_config.R — Named character vector mapping ~35 raw payer codes to 8 AMC categories
- `PAYER_MAPPING$prefix_fallback` in R/00_config.R — Named list mapping first-digit prefixes to categories for unmapped codes
- `PAYER_MAPPING$sentinel_values` in R/00_config.R — c("NI", "UN", "OT") sentinel codes
- `map_payer_category()` in R/02_harmonize_payer.R — Centralized AMC mapping function using AMC_PAYER_LOOKUP + prefix fallback
- `compute_effective_payer()` in R/02_harmonize_payer.R — Primary-if-valid-else-secondary logic
- `detect_dual_eligible()` in R/02_harmonize_payer.R — Dual-eligible detection via codes 14/141/142 and cross-prefix

### Established Patterns
- R/36 currently loads PayerVariable.xlsx in Section 1 and uses left_join for cross-reference — this entire section gets removed
- Frequency table logic in build_frequency_tables() uses left_join(payer_lookup, by = "code") — needs to switch to AMC_PAYER_LOOKUP vector lookup
- Resolution logic in resolve_same_day_payer() already uses tier mapping from AMC categories — minimal changes needed

### Integration Points
- R/00_config.R already exports AMC_PAYER_LOOKUP and PAYER_MAPPING globally when sourced
- R/02_harmonize_payer.R functions are available if sourced — decision: source R/02 or keep simplified inline versions

</code_context>

<specifics>
## Specific Ideas

- User explicitly wants to "replace everything that used the old code, just use AMC code" — clean AMC-native approach throughout
- No PayerVariable.xlsx dependency at all in the updated R/36
- Same output filenames, same CSV count (12), just updated category values
- Prefix fallback retained so every code maps to a category

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 36-all-encounter-payer-frequency-and-same-day-categorization-with-amc-8-category-coding*
*Context gathered: 2026-04-30*
