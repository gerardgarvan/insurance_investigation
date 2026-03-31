# Phase 11: PPTX Clarity & Missing Data Consolidation - Context

**Gathered:** 2026-03-31
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase makes every PPTX slide unambiguous. The primary change is collapsing multiple vague payer categories into a single "Missing" label, plus incorporating the encounter analysis visualizations and cohort enhancements (age groups, DX year, column totals, post-treatment encounter flag) that were already coded in the current session.

</domain>

<decisions>
## Implementation Decisions

### Missing Data Consolidation (LOCKED)
- Unknown, Unavailable, Other, and "No Information" payer categories MUST all be collapsed into a single label: **"Missing"**
- This applies to ALL payer columns throughout the PPTX (PAYER_CATEGORY_PRIMARY, PAYER_CATEGORY_AT_FIRST_DX, PAYER_AT_CHEMO, PAYER_AT_RADIATION, PAYER_AT_SCT, POST_TREATMENT_PAYER, etc.)
- The 9-category payer system becomes a 6-category system for PPTX display: Medicare, Medicaid, Dual eligible, Private, Other government, No payment/Self-pay, Missing
- The underlying data in hl_cohort.csv retains the original 9 categories; collapsing is display-only in the PPTX

### Unambiguous Labels (LOCKED)
- Every slide title, subtitle, column header, and row label must be clear and self-explanatory
- No vague terminology like "N/A" without context -- use descriptive labels

### Column Totals (LOCKED -- already implemented)
- Every table in the PPTX must have a Total row at the bottom
- Total row styled with blue background and white bold text (matching header)
- Already implemented in current session via style_table() and build_payer_table() changes

### Encounter Analysis Slides (LOCKED -- already implemented)
- Histogram of encounters per person by payor category
- Post-treatment encounters per person by year of diagnosis
- Total encounters per person by year of diagnosis
- Post-treatment encounter breakdown by age group (Yes/No)

### Age Groups (LOCKED -- already implemented)
- Four groups: 0-17, 18-39, 40-64, 65+
- Based on age at diagnosis (age_at_dx)
- Already added to cohort in 04_build_cohort.R

### DX Date Priority (LOCKED -- already implemented)
- Tumor registry DATE_OF_DIAGNOSIS is primary source
- Diagnosis table DX_DATE used only if no tumor registry data available
- Already changed in 02_harmonize_payer.R

### Claude's Discretion
- How to handle the 16_encounter_analysis.R figures in PPTX (embed as images or recreate with flextable)
- Whether to add new slides for encounter analysis or replace existing ones
- Exact wording of clarified slide titles/subtitles

</decisions>

<specifics>
## Specific Ideas

- PAYER_ORDER in 11_generate_pptx.R needs to change from 9 categories to 6+Missing
- rename_payer() function needs to map Unknown/Unavailable/Other -> "Missing"
- The "N/A (No Follow-up)" label on post-treatment slides should remain as-is (it's a valid category, not missing data)
- Consider whether "No payment / Self-pay" should keep its current name or be shortened

</specifics>

<deferred>
## Deferred Ideas

None -- user requirements are fully specified for this phase.

</deferred>

---

*Phase: 11-pptx-clarity-and-missing-data-consolidation*
*Context gathered: 2026-03-31 via direct user input*
