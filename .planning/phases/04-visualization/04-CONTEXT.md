# Phase 4: Visualization - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce attrition waterfall chart and payer-stratified Sankey/alluvial diagram from the HL cohort data. Save as PNG files to output/figures/. HIPAA small-cell suppression is deferred for v1 (exploratory outputs on HIPAA-compliant HiPerGator environment). No statistical analysis or interactive dashboards.

</domain>

<decisions>
## Implementation Decisions

### Waterfall chart design
- **D-01:** Vertical bars decreasing left-to-right, one bar per filter step from attrition_log
- **D-02:** Each bar annotated with N patients remaining AND % excluded from previous step (e.g., "N=4,200 (-12.3%)")
- **D-03:** Single color for all bars (e.g., steel blue) -- bar height tells the attrition story, no color gradient needed
- **D-04:** Total cohort attrition only, not faceted by payer. Payer stratification is the Sankey's job

### Sankey flow axes
- **D-05:** Two axes: Payer category (axis 1) -> Treatment type (axis 2). Shows how patients flow from insurance type to treatment received
- **D-06:** Treatment categories are mutually exclusive combinations: "Chemo only", "Radiation only", "Chemo + Radiation", "SCT" (with any combo), "No treatment evidence". Rare combinations (<=10 patients) merged into "Multiple treatments" for readability
- **D-07:** Flows colored by payer category throughout the diagram (matches VIZ-02 "stratified by payer")
- **D-08:** Small payer categories collapsed into "Other" for the visualization to prevent thin illegible flows. Keep individual counts in data
- **D-09:** Stratum labels show category name + N patients (e.g., "Medicare (N=1,200)"). Flows themselves are unlabeled -- width tells the story
- **D-10:** Rare treatment combos simplified: if a treatment combination has <=10 patients, merge into broader category. Handles both readability and HIPAA concerns naturally

### HIPAA suppression
- **D-11:** Skipped for v1. Data stays on HiPerGator's HIPAA-compliant environment and outputs are exploratory. VIZ-03 requirement deferred to v2 if outputs need to be shared externally

### Output aesthetics
- **D-12:** ggplot2 theme_minimal() for both charts
- **D-13:** Colorblind-safe qualitative palette (viridis discrete or RColorBrewer "Set2") for payer categories
- **D-14:** PNG output: 10x7 inches, 300 DPI
- **D-15:** Display in RStudio viewer (interactive exploration) AND save PNG to output/figures/

### Claude's Discretion
- Exact bar color choice (within steel blue family)
- Specific colorblind-safe palette selection (viridis vs Set2 vs similar)
- ggalluvial geom configuration details (lode ordering, curve type)
- Treatment combination grouping threshold tuning if 10-patient cutoff needs adjustment
- Font sizes and spacing for chart readability
- Axis label formatting and rotation

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Upstream data (Phase 3 outputs consumed by visualization)
- `R/04_build_cohort.R` -- Produces `hl_cohort` tibble (patient-level with PAYER_CATEGORY_PRIMARY, HAD_CHEMO, HAD_RADIATION, HAD_SCT) and `attrition_log` data frame (step, n_before, n_after, n_excluded, pct_excluded)
- `R/utils_attrition.R` -- Attrition log structure: init_attrition_log(), log_attrition() producing columns step, n_before, n_after, n_excluded, pct_excluded

### Config and utilities
- `R/00_config.R` -- PAYER_MAPPING$categories (9-category list), CONFIG$output_dir, auto-sources utilities
- `R/02_harmonize_payer.R` -- payer_summary tibble with PAYER_CATEGORY_PRIMARY per patient

### Stack decisions
- `.planning/research/STACK.md` -- ggalluvial 0.12.5 for Sankey, scales for formatting, ggplot2 4.0.1+, forcats for factor reordering

### Architecture
- `.planning/phases/01-foundation-data-loading/01-CONTEXT.md` -- D-23: Script naming (05_visualize_waterfall.R, 06_visualize_sankey.R), D-26: output/figures/ directory exists
- `.planning/phases/03-cohort-building/03-CONTEXT.md` -- D-09: hl_cohort column structure, D-02: treatment flags are identification only

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `attrition_log` data frame: Already has step, n_before, n_after, n_excluded, pct_excluded columns -- maps directly to waterfall chart axes
- `hl_cohort` tibble: Has PAYER_CATEGORY_PRIMARY, HAD_CHEMO, HAD_RADIATION, HAD_SCT -- maps directly to Sankey axes
- `output/figures/` directory: Already created with .gitkeep
- `PAYER_MAPPING$categories`: 9-category list in config for consistent ordering

### Established Patterns
- Scripts source their dependencies: 05/06 would source 04_build_cohort.R which loads everything upstream
- Console logging via message() + glue()
- CSV output pattern via readr::write_csv() (for any tabular output alongside figures)
- Named list storage: pcornet$TABLE_NAME, CONFIG$output_dir

### Integration Points
- Input: attrition_log data frame (from 04_build_cohort.R) -> waterfall chart
- Input: hl_cohort tibble (from 04_build_cohort.R) -> Sankey diagram
- Output: output/figures/waterfall_attrition.png (VIZ-01)
- Output: output/figures/sankey_patient_flow.png (VIZ-02)
- RStudio viewer: Both plots displayed interactively before saving

</code_context>

<specifics>
## Specific Ideas

- Waterfall chart should be straightforward: attrition_log maps directly to ggplot2 geom_col() with step on x-axis and n_after on y-axis
- Sankey uses ggalluvial: geom_alluvium() for flows + geom_stratum() for category boxes, with PAYER_CATEGORY as fill aesthetic
- Treatment combination column needs to be derived from HAD_CHEMO + HAD_RADIATION + HAD_SCT flags using case_when()
- forcats::fct_reorder() to order payer categories by frequency (largest first) in Sankey
- Collapsing rare categories helps with both visual clarity and incidental HIPAA compliance

</specifics>

<deferred>
## Deferred Ideas

- VIZ-03 HIPAA small-cell suppression -- deferred to v2 if outputs need external sharing
- Faceted waterfall by payer category -- could add as supplementary figure in v2
- Interactive Sankey (plotly/networkD3) -- v1 uses static ggalluvial
- Treatment timing analysis visualization (time-to-treatment by payer) -- separate analysis phase

</deferred>

---

*Phase: 04-visualization*
*Context gathered: 2026-03-25*
