# Phase 24: Make Presentation of Just Phases 19 and 20 - Context

**Gathered:** 2026-04-15  
**Status:** Ready for planning

<domain>
## Phase Boundary

Create a standalone PowerPoint deck containing only the diagnostic outputs from:
- **Phase 19** (UF insurance missingness), and
- **Phase 20** (FLM duplicate encounter dates)

The deck should exclude generalized all-source/all-site outputs from Phases 21/22.
</domain>

<decisions>
## Implementation Decisions

### Deck Scope
- **D-01:** Generate a **standalone** deck (not appended to the existing full presentation)
- **D-02:** Include only Phase 19 and Phase 20 content

### Content Type
- **D-03:** Include **both** formatted tables and chart slides

### Phase 19 Coverage (UF Missingness)
- **D-04:** Include all key outputs:
  - Cross-summary (overall missingness)
  - Missingness by year
  - Missingness by encounter type
  - Missingness year x encounter type
  - Raw vs harmonized missingness
  - Raw payer value distribution

### Phase 20 Coverage (FLM Duplicate Dates)
- **D-05:** Include all key outputs:
  - Overall duplicate-rate summary
  - Patient-level duplicate summary
  - Date-level duplicate detail (summarized for presentation)
  - Source payer completeness comparison
  - Source-preference recommendation

### Presentation Handling
- **D-06:** Split large/wide tables across multiple slides for readability
- **D-07:** Output filename convention: `insurance_tables_phase19_20_YYYY-MM-DD.pptx`

### Claude's Discretion
- Slide ordering across Phase 19 vs Phase 20 sections
- Chart styling choices (palette, orientation, labels)
- Footnote wording and definitions
- Exact summarization method for very large detail tables
- How recommendation logic is rendered (table note vs dedicated summary slide)
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing PPTX Generation
- `R/11_generate_pptx.R` -- current PPTX generation pipeline and helper functions (`add_table_slide()`, `add_image_slide()`, `add_footnote()`)
- `R/16_encounter_analysis.R` -- established chart generation patterns

### Phase 19 Source Script and Outputs
- `R/18_uf_insurance_missingness.R`
- `output/tables/uf_payer_raw_value_distribution.csv`
- `output/tables/uf_payer_missingness_by_year.csv`
- `output/tables/uf_payer_missingness_by_enc_type.csv`
- `output/tables/uf_payer_missingness_year_x_enc_type.csv`
- `output/tables/uf_payer_raw_vs_harmonized.csv`

### Phase 20 Source Script and Outputs
- `R/19_flm_duplicate_dates.R`
- `output/tables/flm_patient_duplicate_summary.csv`
- `output/tables/flm_date_level_duplicate_detail.csv`
- `output/tables/flm_duplicate_aggregate_summary.csv`
- `output/tables/flm_source_payer_completeness.csv`

### Configuration and Styling
- `R/00_config.R` -- project constants/utilities
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `add_table_slide(pptx, title, subtitle, tbl_data)` in `R/11_generate_pptx.R`
- `add_image_slide(pptx, title, subtitle, img_path)` in `R/11_generate_pptx.R`
- `add_footnote(pptx, text)` in `R/11_generate_pptx.R`

### Established Patterns
- PowerPoint built via `officer` + `flextable`
- Charts rendered via `ggplot2` and embedded as images
- Consistent visual style (title/subtitle formatting, table styling, footnotes)
- Missing/diagnostic tables split across slides where needed

### Integration Point
- Extend existing PPTX generation logic with a focused path or dedicated script that reads only UF/FLM outputs and writes the focused filename.
</code_context>

<specifics>
## Specific Ideas

- Keep section structure simple:
  1) Phase 19 section divider + Phase 19 slides
  2) Phase 20 section divider + Phase 20 slides
  3) Brief closing slide with key takeaways/recommendation
- Ensure the recommendation slide explicitly references payer completeness evidence from FLM source comparison.
</specifics>

<deferred>
## Deferred Ideas

None.
</deferred>

---

*Phase: 24-make-presentation-of-just-phases-19-and-20*  
*Context gathered: 2026-04-15*
