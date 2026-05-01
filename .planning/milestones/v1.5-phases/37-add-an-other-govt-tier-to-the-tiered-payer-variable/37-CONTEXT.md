# Phase 37: Add an Other Govt Tier to the Tiered Payer Variable - Context

**Gathered:** 2026-05-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Add "Other govt" as a distinct tier in the same-day payer resolution hierarchy in R/36_tiered_same_day_payer.R. Currently, the CODE_TO_TIER function collapses "Other govt" into "Other" (line 92). This phase promotes "Other govt" to its own resolution tier with its own priority level, expanding the hierarchy from 7 tiers to 8. The AMC 8-category system in R/00_config.R already defines "Other govt" as a standard category — this phase aligns the resolution logic to preserve that distinction.

</domain>

<decisions>
## Implementation Decisions

### Tier Priority Position
- **D-01:** The 8-tier resolution hierarchy is: Medicaid > Medicare > Private > **Other Govt** > Other > Self-pay > Uninsured > Missing. Other Govt slots between Private and Other.
- **D-02:** This matches the intuition that government programs (VA, state/federal agencies, corrections) rank below private insurance but above generic "Other" — the most conservative insertion point.

### Output Impact
- **D-03:** Transparent update — same 12 CSV filenames, same column structure. "Other govt" appears as its own resolved_payer value and its own row in category summary CSVs. No new output files.
- **D-04:** Before-vs-after comparison CSVs will naturally show "Other govt" as a distinct category in both columns.

### Scope of Change
- **D-05:** Full update within R/36_tiered_same_day_payer.R only. Update CODE_TO_TIER function, TIER_PRIORITY ordering vector, console summaries, and any hardcoded tier lists. Self-contained to one script.
- **D-06:** No changes to R/00_config.R, R/02_harmonize_payer.R, or any other script. AMC_PAYER_LOOKUP already maps codes to "Other govt" correctly — the only issue was the resolution step collapsing it.
- **D-07:** R/35 (Phase 34 baseline) remains untouched.

### Claude's Discretion
- Console summary formatting for the additional tier row
- Whether TIER_PRIORITY should be a named vector or character vector (as long as the ordering is correct)
- Any minor formatting adjustments to accommodate the wider tier set

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Script Being Modified
- `R/36_tiered_same_day_payer.R` — Phase 35/36 dual-scope script with CODE_TO_TIER function (line 87), TIER_PRIORITY vector, frequency tables, and same-day resolution logic. This is the only file being changed.

### AMC 8-Category Mapping
- `R/00_config.R` lines 239-362 — AMC_PAYER_LOOKUP (code→category) and PAYER_MAPPING (prefix_fallback, categories list). "Other govt" is already one of the 8 standard categories. Read-only reference — not modified.

### Amy Crisp Framework
- `payer_framework.txt` — Original same-day resolution hierarchy specification. The original 7-tier hierarchy did not list "Other govt" separately — this phase extends it per AMC alignment.

### Phase 36 Context (Predecessor)
- `.planning/phases/36-all-encounter-payer-frequency-and-same-day-categorization-with-amc-8-category-coding/36-CONTEXT.md` — Documents the AMC refactoring decisions (D-08 specifically notes CODE_TO_TIER collapses "Other govt" to "Other").

</canonical_refs>

<code_context>
## Existing Code Insights

### Key Change Target
- `CODE_TO_TIER` function (R/36 line 87-97): Currently has `payer_category == "Other govt" ~ "Other"` — change to `payer_category == "Other govt" ~ "Other govt"`
- `TIER_PRIORITY` vector: Currently 7 elements — add "Other govt" between "Private" and "Other"

### Established Patterns
- AMC_PAYER_LOOKUP already assigns codes 382, 349, 3, 32126, 32121, 32, 44 to "Other govt"
- Prefix fallback: prefix "3" and "4" → "Other govt" (already correct in config.R and in R/36's inline mapping)
- The frequency table functions already use AMC categories including "Other govt" — they don't need changes since they report categories, not tiers

### Integration Points
- The resolution logic calls CODE_TO_TIER to convert AMC categories to tiers — this is the single bottleneck where "Other govt" gets collapsed
- Console summaries likely reference tier names — need to accommodate the 8th tier

</code_context>

<specifics>
## Specific Ideas

No specific requirements — the change is mechanically straightforward: stop collapsing "Other govt" into "Other" and give it its own priority slot between Private and Other.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 37-add-an-other-govt-tier-to-the-tiered-payer-variable*
*Context gathered: 2026-05-01*
