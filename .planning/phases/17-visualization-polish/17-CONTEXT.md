# Phase 17: Visualization Polish - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Filter 1900 sentinel dates from all PPTX content (tables and graphs), add a new post-treatment encounter summary table slide (unique encounter dates per person by payer, counted after last treatment), and add stacked encounter histograms showing pre/post-treatment breakdown by payer. Also verify and close gaps for PPTX2-04 (overflow bin) and PPTX2-07 (label clipping).

</domain>

<decisions>
## Implementation Decisions

### 1900 Sentinel Date Filtering (VIZP-01)
- **D-01:** Filter 1900 dates at the PPTX display layer only — in `11_generate_pptx.R` and `16_encounter_analysis.R`. Do NOT modify raw cohort data in `04_build_cohort.R` (except the existing `first_hl_dx_date` nullification which stays). This keeps raw data intact for audit purposes.
- **D-02:** Apply 1900 filtering to any date column that appears in PPTX tables or is used to derive values shown in PPTX graphs (treatment dates, enrollment dates, encounter dates).

### Post-Treatment Encounter Summary (VIZP-02)
- **D-03:** New PPTX slide with summary table: unique encounter dates per person by payer category, counted only after `max(LAST_CHEMO_DATE, LAST_RADIATION_DATE, LAST_SCT_DATE)` — the last treatment date across all treatment types.
- **D-04:** Patients with no treatment (all three LAST_*_DATE are NA) are excluded from this slide — they have no "post-treatment" period.
- **D-05:** This is a distinct metric from the existing `N_UNIQUE_DATES_POST_TX` in Section 6 of `16_encounter_analysis.R`, which uses post-diagnosis as anchor. The new metric uses post-last-treatment as anchor.

### Stacked Encounter Histogram (VIZP-03)
- **D-06:** Add a NEW stacked histogram — do not replace the existing encounter histogram (Section 1 of `16_encounter_analysis.R`).
- **D-07:** Each bar shows a patient's total encounters split into pre-treatment (top) and post-treatment (bottom, colored distinctly). "Post-treatment" = encounters after `max(LAST_CHEMO_DATE, LAST_RADIATION_DATE, LAST_SCT_DATE)`.
- **D-08:** Faceted by payer category (6 + Missing, matching existing consolidation pattern).
- **D-09:** Use raw encounter counts (N_ENCOUNTERS), not unique dates, to match the existing histogram metric.
- **D-10:** Patients with no treatment are excluded from the stacked histogram (no way to split pre/post).

### Gap Closure (PPTX2-04, PPTX2-07)
- **D-11:** PPTX2-04 (encounter histogram with 6+Missing payer and >500 overflow bin with per-facet annotation) — code already exists in `16_encounter_analysis.R` lines 39-83. Verify correctness, do not rewrite.
- **D-12:** PPTX2-07 (age group bar chart labels not clipped) — code already exists with `coord_cartesian(clip = "off", ylim = c(0, max_y_p4 * 1.2))` at line 231. Verify correctness, do not rewrite.

### Claude's Discretion
- Exact color palette for pre/post-treatment stacking (should be visually distinct and consistent with existing viridis/manual palettes)
- Binwidth and x-axis cap for the new stacked histogram
- Whether to add a summary statistics companion slide for the stacked histogram (like Slide 18 for the existing histogram)
- Exact wording of footnotes and subtitles for new slides

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` — VIZP-01, VIZP-02, VIZP-03 definitions; PPTX2-04 and PPTX2-07 gap closure specs

### Existing Implementation
- `R/16_encounter_analysis.R` — Current encounter analysis script (6 sections, produces PNGs). Stacked histogram and new metrics go here.
- `R/11_generate_pptx.R` — PPTX generation (25 slides). New slides and 1900 filtering go here. Contains `rename_payer()`, `PAYER_ORDER`, `add_table_slide()`, `add_image_slide()`, `add_footnote()` helpers.
- `R/04_build_cohort.R` §4 (lines 176-183) — Existing 1900 sentinel nullification for `first_hl_dx_date`
- `R/00_config.R` — TREATMENT_CODES config, PAYER_MAPPING, analysis window settings

### Prior Phase Patterns
- `.planning/ROADMAP.md` §Phase 12 — Phase 12 established overflow bin, label clipping, and DX_YEAR filtering patterns

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `rename_payer()` in `11_generate_pptx.R` — consolidates Other/Unavailable/Unknown → Missing
- `PAYER_ORDER` vector — standard 7-level factor ordering used across all PPTX content
- `add_table_slide()` / `add_image_slide()` / `add_footnote()` — PPTX slide builder helpers
- `save_output_data()` from `utils_snapshot.R` — RDS snapshot helper for figure/table backing data
- `compute_last_dates()` in `11_generate_pptx.R` — already computes LAST_CHEMO/RADIATION/SCT dates
- `all_last_dates` tibble in `11_generate_pptx.R` — already computes `LAST_ANY_TREATMENT_DATE` per patient

### Established Patterns
- Encounter histograms: `geom_histogram()` + `facet_wrap(~ PAYER_CATEGORY_PRIMARY, scales = "free_y")` + overflow annotation
- DX year bar charts: `geom_col()` + `geom_text()` labels + `coord_cartesian(clip = "off")` + expanded y-axis
- Payer consolidation: `case_when()` collapsing Other/Unavailable/Unknown to Missing, then `factor()` with PAYER_ORDER levels
- HIPAA suppression: `format_count_pct()` for count display

### Integration Points
- New slides insert after existing Slide 25 (or between existing slides as appropriate)
- New PNGs saved to `output/figures/` and embedded via `add_image_slide()`
- New table backing data saved via `save_output_data()` per SNAP-03/SNAP-04

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches using established codebase patterns.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 17-visualization-polish*
*Context gathered: 2026-04-03*
