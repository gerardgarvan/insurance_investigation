# Phase 6: Make Dataset That Produces cancer_summary_template.xlsx - Context

**Gathered:** 2026-05-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Create R/53_cancer_summary.R that produces a patient-code level dataset from the DIAGNOSIS table, outputting cancer_summary.xlsx and cancer_summary.csv to output/tables/. Each row represents one patient + one cancer code, with date-based confirmation metrics (2+ distinct dates, 7-day gap). All neoplasm codes (C00-D49) included. All patients in DIAGNOSIS included (not just HL cohort).

</domain>

<decisions>
## Implementation Decisions

### Data Content
- **D-01:** Output is patient-code level: one row per patient per unique cancer code they have in DIAGNOSIS
- **D-02:** Columns: `ID`, `cancer_code`, `description`, `two_or_more_unique_dates`, `two_or_more_unique_dates_gt_7`, `unique_dates_total`, `unique_dates_with_sep_gt_7`
- **D-03:** `two_or_more_unique_dates` = 1 if patient has 2+ distinct non-NA DX_DATEs for this code, else 0 (integer 1/0 flags, not TRUE/FALSE)
- **D-04:** `two_or_more_unique_dates_gt_7` = 1 if patient has 2+ distinct DX_DATEs where max(date) - min(date) >= 7 days for this code, else 0
- **D-05:** `unique_dates_total` = count of distinct non-NA DX_DATEs for this patient-code combo
- **D-06:** `unique_dates_with_sep_gt_7` = count of distinct dates that are >7 days from at least one other date for this patient-code (Claude's discretion on interpretation — clinically, this is the number of dates that contribute to "spread" evidence)
- **D-07:** Patient-code combos where all DX_DATEs are NA get 0 for all confirmation columns — code presence is still recorded
- **D-08:** Code scope: all neoplasm codes with C or D prefix (C00-D49), same as R/47
- **D-09:** Data source: DIAGNOSIS table only (DX_TYPE == "10" for ICD-10), no TUMOR_REGISTRY
- **D-10:** `description` column: include both cancer site category name (from PREFIX_MAP) and code-level description where available (Claude's discretion on best source and format)

### Template Approach
- **D-11:** Generate xlsx from scratch in R code using openxlsx2 (not reading the template file). Template serves as specification, not input.
- **D-12:** Single flat sheet with all patient-code rows
- **D-13:** Output both xlsx and CSV formats

### Patient Scope
- **D-14:** All patients in DIAGNOSIS with neoplasm codes (not restricted to HL cohort)

### Output
- **D-15:** Output directory: output/tables/
- **D-16:** Filenames: cancer_summary.xlsx and cancer_summary.csv

### Script
- **D-17:** Script: R/53_cancer_summary.R
- **D-18:** Minimal xlsx styling (headers and data, no dark header fill or special formatting — primarily a data export)

### Claude's Discretion
- `unique_dates_with_sep_gt_7` interpretation: Claude picks the most clinically useful counting method for dates >7 days apart
- Description source: Claude picks best combination of PREFIX_MAP category names and code-level descriptions from available sources (Phase 39-41 RDS, config comments, etc.)
- Performance safeguards: Claude assesses data volume during research and adds row count warnings or memory management if needed

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Cancer Site Classification
- `R/47_cancer_site_frequency.R` — Defines PREFIX_MAP and CATEGORY_ORDER for cancer site classification; classify_codes() function
- `R/50_cancer_site_confirmation.R` — 2-date confirmation logic at exact code and category level
- `R/51_cancer_site_confirmation_7day.R` — 7-day gap confirmation logic (clone of R/50)

### Code Descriptions
- `R/52_all_codes_resolved.R` — Multi-source description cascade pattern (Phase 39-41 RDS, hardcoded, config comments)
- `R/00_config.R` — TREATMENT_CODES vectors with inline comments as description source

### Data Access
- `R/01_load_pcornet.R` — get_pcornet_table() for DuckDB access
- `R/00_config.R` — CONFIG$output_dir and USE_DUCKDB flag

### Styling Patterns
- `R/47_cancer_site_frequency.R` — openxlsx2 styling pattern (for reference, though D-18 says minimal styling)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PREFIX_MAP` in R/47: Maps 3-char ICD-10 prefixes to cancer site categories — reuse for `description` column
- `classify_codes()` in R/47: Classifies ICD-10 codes by prefix — reuse directly
- `CATEGORY_ORDER` in R/47: Display ordering for categories
- Multi-source description cascade in R/52: Pattern for looking up code descriptions from RDS artifacts, hardcoded tables, and config comments
- `get_pcornet_table("DIAGNOSIS")` via DuckDB: Standard data access pattern

### Established Patterns
- DIAGNOSIS filtering: `filter(DX_TYPE == "10")` for ICD-10 only, `select(ID, DX, DX_DATE)`
- Code normalization: `toupper(str_remove_all(DX, "\\."))` — uppercase, no dots
- Neoplasm filter: `filter(str_detect(DX_norm, "^[CD]"))`
- Date confirmation: `group_by(ID, DX_norm) %>% filter(n_distinct(DX_DATE) >= 2)` pattern from R/50
- 7-day gap: `max(DX_DATE) - min(DX_DATE) >= 7` pattern from R/51

### Integration Points
- Outputs to `output/tables/` directory (same as R/47, R/50, R/51)
- Sources R/00_config.R and R/01_load_pcornet.R like all data scripts
- Closes DuckDB connection via `close_pcornet_con()` at end

</code_context>

<specifics>
## Specific Ideas

- The existing `cancer_summary_template.xlsx` at repo root is a blank formatted template — the script replaces it with generated data
- Column names must match exactly: `ID`, `cancer_code`, `description`, `two_or_more_unique_dates`, `two_or_more_unique_dates_gt_7`, `unique_dates_total`, `unique_dates_with_sep_gt_7`
- Boolean columns use integer 1/0 encoding (not TRUE/FALSE) for easy summing in downstream analysis

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 06-make-dataset-that-produces-cancer-summary-template-xlsx*
*Context gathered: 2026-05-21*
