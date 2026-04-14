# Phase 23: Make Visual Presentation of Tables from Last 2 Pages - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-04-14
**Phase:** 23-make-visual-presentation-of-tables-from-last-2-pages
**Areas discussed:** Table selection, Visualization type

---

## Table Selection

### Which CSVs become slides?

| Option | Description | Selected |
|--------|-------------|----------|
| Cross-site summaries only | Just the 2 high-level cross-site comparison tables | |
| Summaries + key breakdowns | Cross-site summaries plus 2-3 most informative breakdowns | |
| All tables | Convert all 11 CSVs to slides | ✓ |

**User's choice:** All tables
**Notes:** All 11 CSVs from Phase 21 (6) and Phase 22 (5) become PPTX slides.

### Wide table handling

| Option | Description | Selected |
|--------|-------------|----------|
| Smaller font, one slide | Keep each CSV as a single slide even if font gets small | |
| Split across slides | Break wide/tall tables into multiple slides (e.g., 7 sites per slide) | ✓ |
| You decide | Claude picks the best approach per table based on dimensions | |

**User's choice:** Split across slides
**Notes:** Tables too wide or tall for a single slide should be split (e.g., 7 sites per slide).

### Detail-level data handling

| Option | Description | Selected |
|--------|-------------|----------|
| Summarize | Aggregate detail-level data into presentation-friendly summaries | ✓ |
| Full data | Include all rows, split across as many slides as needed | |
| Skip detail, keep agg | Only include aggregate/summary CSVs, skip row-level detail files | |

**User's choice:** Summarize
**Notes:** Patient-level and date-level detail CSVs should be summarized to presentation-friendly aggregates.

---

## Visualization Type

### Tables vs charts

| Option | Description | Selected |
|--------|-------------|----------|
| Tables + bar charts (Recommended) | Key metrics as bar charts by site, plus full data tables | ✓ |
| Tables only | All CSVs as formatted tables only | |
| Tables + heatmaps | Heatmaps for crosstab data plus tables for summaries | |

**User's choice:** Tables + bar charts
**Notes:** Both formatted table slides and bar chart visualizations for key metrics.

### Which metrics get bar charts?

| Option | Description | Selected |
|--------|-------------|----------|
| Primary missingness % by site | Bar chart of pct_primary_missing from cross-site summary | ✓ |
| Duplicate date rate by site | Bar chart of pct_duplicate_rate from duplication cross-site summary | ✓ |
| Missingness by enc type | Grouped bar chart showing missingness rates by encounter type across sites | ✓ |
| You decide | Claude picks which data dimensions get charts vs tables | |

**User's choice:** All three bar chart options selected (multiSelect)
**Notes:** Three distinct bar chart slides for the key comparative metrics.

---

## Claude's Discretion

- Slide ordering and section grouping
- Bar chart styling (color palette, axis labels, sort order)
- Footnote text
- HIPAA suppression for site-level breakdowns
- Number formatting
- How to summarize detail-level CSVs
- Font sizes for tables

## Deferred Ideas

None -- discussion stayed within phase scope.
