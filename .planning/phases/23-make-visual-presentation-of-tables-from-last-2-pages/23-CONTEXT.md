# Phase 23: Make Visual Presentation of Tables from Last 2 Pages - Context

**Gathered:** 2026-04-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Convert the CSV table outputs from Phase 21 (all-source payer missingness, 6 CSVs) and Phase 22 (all-site duplicate dates, 5 CSVs) into PPTX slides appended to the existing `insurance_tables_YYYY-MM-DD.pptx` presentation. Includes both formatted data tables and bar chart visualizations for key metrics.

</domain>

<decisions>
## Implementation Decisions

### Table Selection
- **D-01:** All 11 CSV outputs from Phase 21 and Phase 22 become PPTX slides
- **D-02:** Wide/tall tables that don't fit on a single slide should be split across multiple slides (e.g., 7 sites per slide)
- **D-03:** Detail-level CSVs (all_site_patient_duplicate_summary.csv, all_site_date_level_duplicate_detail.csv) should be summarized into presentation-friendly aggregates rather than showing raw row-level data

### Visualization Type
- **D-04:** Presentation includes both formatted tables AND bar charts for key metrics
- **D-05:** Three bar chart slides required:
  - Primary payer missingness % by site (from all_source_cross_site_summary.csv)
  - Duplicate date rate % by site (from all_site_cross_site_summary.csv)
  - Grouped bar chart of missingness by encounter type across sites (from all_source_payer_missingness_by_enc_type.csv)
- **D-06:** All CSVs also get corresponding formatted table slides

### Claude's Discretion
- Slide ordering and section grouping (missingness section vs duplication section)
- Bar chart styling (color palette, axis labels, sort order)
- Footnote text explaining metrics and definitions
- HIPAA small-cell suppression decisions for site-level breakdowns
- Number formatting (percentages, comma separators)
- How to summarize the detail-level CSVs (top N rows, grouped stats, or key metrics only)
- Font size for table slides

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### PPTX generation patterns
- `R/11_generate_pptx.R` -- Existing 38-slide PPTX generator with `add_table_slide()`, `add_image_slide()`, `add_footnote()`, `build_payer_table()` helpers
- `R/16_encounter_analysis.R` -- Encounter analysis PNG generation patterns (bar charts, histograms)

### Phase 21 source data and script
- `R/20_all_source_missingness.R` -- All-source payer missingness diagnostic script (6 CSV outputs)
- `output/tables/all_source_cross_site_summary.csv` -- Cross-site missingness comparison (14 sites + ALL row)
- `output/tables/all_source_payer_raw_value_distribution.csv` -- Raw PAYER_TYPE value counts by source
- `output/tables/all_source_payer_missingness_by_year.csv` -- Temporal missingness breakdown by source
- `output/tables/all_source_payer_missingness_by_enc_type.csv` -- Encounter type missingness by source
- `output/tables/all_source_payer_missingness_year_x_enc_type.csv` -- Year x encounter type crosstab by source
- `output/tables/all_source_payer_raw_vs_harmonized.csv` -- Raw vs harmonized missingness comparison

### Phase 22 source data and script
- `R/21_all_site_duplicate_dates.R` -- All-site duplicate date investigation script (5 CSV outputs)
- `output/tables/all_site_cross_site_summary.csv` -- Cross-site duplication comparison (14 sites + ALL row)
- `output/tables/all_site_patient_duplicate_summary.csv` -- Patient-level duplicate summary (needs summarization)
- `output/tables/all_site_date_level_duplicate_detail.csv` -- Date-level detail (needs summarization)
- `output/tables/all_site_duplicate_aggregate_summary.csv` -- Per-site aggregate metrics (long format)
- `output/tables/all_site_source_payer_completeness.csv` -- Source payer completeness for multi-source dates

### Configuration
- `R/00_config.R` -- Project configuration, HIPAA suppression utilities, payer mapping

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `add_table_slide(pptx, title, subtitle, tbl_data)` -- Core table slide builder in 11_generate_pptx.R (line 722)
- `add_image_slide(pptx, title, subtitle, img_path)` -- Image embedding helper in 11_generate_pptx.R (line 760)
- `add_footnote(pptx, text)` -- Footnote helper in 11_generate_pptx.R (line 790)
- `build_payer_table()` and variants -- Table formatting with HIPAA suppression patterns
- `save_output_data()` -- Snapshot helper from utils_snapshot.R for backing data
- `rename_payer()` -- Payer label standardization

### Established Patterns
- PPTX slides use `officer` package with "Blank" layout
- Tables use `flextable` for formatting
- Bar charts saved as PNG then embedded via `add_image_slide()`
- Consistent slide structure: title, subtitle, table/image, footnote
- ggplot2 for all chart generation with colorblind-safe palettes

### Integration Points
- New slides append after existing Slide 38 (Section 5 ends at line 1983)
- PPTX file save at Section 6 (line 1989) -- new slides must be added before this
- Chart PNGs go to `output/figures/` directory
- The script reads CSVs from `output/tables/` which already exist from Phase 21/22

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- open to standard approaches matching existing PPTX style.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope.

</deferred>

---

*Phase: 23-make-visual-presentation-of-tables-from-last-2-pages*
*Context gathered: 2026-04-14*
