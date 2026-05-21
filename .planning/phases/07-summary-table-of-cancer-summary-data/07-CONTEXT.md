# Phase 7: Summary Table of Cancer Summary Data - Context

**Gathered:** 2026-05-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Create a summary/aggregate table from the Phase 6 cancer_summary patient-code level dataset (R/53_cancer_summary.R output). Produces a two-sheet xlsx with category-level and code-level summaries including patient counts, confirmation rates, date distribution stats, and record counts. Output to output/tables/cancer_summary_table.xlsx.

</domain>

<decisions>
## Implementation Decisions

### Aggregation Level
- **D-01:** Two-sheet xlsx: one sheet aggregated by cancer site category (from PREFIX_MAP), one sheet aggregated by exact ICD-10 code
- **D-02:** Category-level sheet: one row per cancer site category (~54 categories)
- **D-03:** Code-level sheet: one row per unique ICD-10 code — include ALL codes, no minimum patient count threshold

### Summary Metrics
- **D-04:** Patient counts: total_patients per category/code (the base metric)
- **D-05:** Confirmation rates: confirmed_patients (2+ dates), confirmed_7day (7-day gap), and percentage rates for both — show both absolute counts AND percentages
- **D-06:** Date distribution stats: mean and median of unique_dates_total and unique_dates_with_sep_gt_7 per category/code
- **D-07:** Record counts: total DIAGNOSIS rows per category/code (not just unique dates — shows encounter volume)

### Output Format
- **D-08:** Styled xlsx with dark fill + white font headers, freeze panes, auto column widths, number formatting — matches R/47 and R/50 patterns
- **D-09:** xlsx only, no CSV output
- **D-10:** Filename: cancer_summary_table.xlsx in output/tables/
- **D-11:** Output directory: output/tables/ (same as Phase 6)

### Scope
- **D-12:** All patients in DIAGNOSIS with neoplasm codes (not restricted to HL cohort) — consistent with Phase 6
- **D-13:** All neoplasm codes included (C and D prefixes, C00-D49) — matches Phase 6 scope
- **D-14:** Rows sorted by patient count descending (most common cancer sites/codes at top)

### Script
- **D-15:** New R script (Claude's discretion on number, likely R/54_cancer_summary_table.R)

### Claude's Discretion
- Script number assignment
- Exact column header names (should be human-readable)
- Whether to include a totals row at the bottom of each sheet
- Percentage number formatting (e.g., 1 decimal place)
- Whether date distribution stats use mean, median, or both

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Source Data
- `R/53_cancer_summary.R` — Phase 6 script that produces the patient-code level cancer_summary dataset; defines column structure (ID, cancer_code, description, confirmation flags, date counts)
- `output/tables/cancer_summary.xlsx` — The source data file to summarize (patient-code level)
- `output/tables/cancer_summary.csv` — CSV version of same data

### Cancer Site Classification
- `R/47_cancer_site_frequency.R` — Defines PREFIX_MAP and CATEGORY_ORDER; classify_codes() function; openxlsx2 styled output pattern
- `R/50_cancer_site_confirmation.R` — Category-level confirmation pattern (similar summary structure)

### Styling Patterns
- `R/47_cancer_site_frequency.R` — openxlsx2 dark header styling pattern to replicate
- `R/52_all_codes_resolved.R` — Multi-sheet xlsx pattern with consistent styling

### Data Access
- `R/01_load_pcornet.R` — get_pcornet_table() for DuckDB access (needed for record counts from DIAGNOSIS)
- `R/00_config.R` — CONFIG$output_dir and USE_DUCKDB flag

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PREFIX_MAP` in R/47 and R/53: Maps 3-char ICD-10 prefixes to cancer site categories — reuse for category grouping
- `classify_codes()` in R/47 and R/53: Classifies ICD-10 codes by prefix
- openxlsx2 styling pattern in R/47: Dark header fill, white font, freeze panes, auto widths — replicate for this output
- `cancer_summary.csv` / `.xlsx` from Phase 6: Already has per-patient confirmation metrics — can read this directly or recompute from DIAGNOSIS

### Established Patterns
- Two-sheet xlsx pattern: R/50 and R/51 each produce two-sheet workbooks (exact code + prefix level)
- Record count queries: R/52 queries DuckDB for patient_count and record_count per code
- Styled header pattern: `wb_add_fill()` + `wb_add_font()` for dark headers in R/47

### Integration Points
- Reads output from R/53_cancer_summary.R (or recomputes from DIAGNOSIS)
- Outputs to output/tables/ directory
- Sources R/00_config.R and R/01_load_pcornet.R

</code_context>

<specifics>
## Specific Ideas

- The summary table should be a standalone companion to cancer_summary.xlsx — someone can open it to get the high-level picture without needing the patient-level detail
- Category sheet is the primary view; code sheet provides drill-down detail
- Sorting by patient count makes the most clinically relevant categories immediately visible

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 07-summary-table-of-cancer-summary-data*
*Context gathered: 2026-05-21*
