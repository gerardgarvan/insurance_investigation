# Phase 5: Fix Parsing & Investigate HL Diagnosis Gaps - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix date parsing errors and other data quality issues across the pipeline, and investigate why not all patients in the cohort extract have an HL diagnosis in the DIAGNOSIS table. This phase produces a reusable diagnostic script, applies fixes to existing pipeline scripts, and rebuilds the cohort with expanded HL identification (TUMOR_REGISTRY histology codes). No new visualizations or analysis features.

</domain>

<decisions>
## Implementation Decisions

### Date parsing diagnosis
- **D-01:** Audit ALL 9 loaded tables for date parsing issues — ENROLLMENT, DIAGNOSIS, PROCEDURES, PRESCRIBING, ENCOUNTER, DEMOGRAPHIC, TUMOR_REGISTRY1/2/3
- **D-02:** Unparseable dates: keep as NA in pipeline AND write diagnostic CSV (table, column, raw_value, row_count) to output/diagnostics/ for manual inspection
- **D-03:** Audit ALL regex patterns used for column detection (not just date regex) — verify the date column detector regex in 01_load_pcornet.R catches all actual date columns by comparing against csv_columns.txt

### HL diagnosis gap investigation
- **D-04:** Expand HL identification to include TUMOR_REGISTRY histology codes (ICD-O-3 9650-9667) — patients with HL evidence in TR tables should be included in cohort even without DIAGNOSIS table ICD codes
- **D-05:** Add ICD_CODES$hl_histology vector to 00_config.R with ICD-O-3 histology codes for HL (9650-9667). Keeps all HL identification codes centralized
- **D-06:** Update has_hodgkin_diagnosis() predicate to check BOTH DIAGNOSIS (ICD-9/10 codes) AND TUMOR_REGISTRY (histology codes) — single source of truth for HL identification
- **D-07:** Check all 3 TUMOR_REGISTRY tables for histology/morphology fields — TR1, TR2, TR3 may have different column names (HISTOLOGY_ICDO3, HIST3V, MORPH_ICDO3, etc.)
- **D-08:** Produce full Venn-style breakdown: DIAGNOSIS-only, TR-only, both sources, neither. Break down by site (AMS/UMI/FLM/VRT) and by identification method (ICD-9 vs ICD-10 vs histology)
- **D-09:** Verify extract scope — check if ALL patients in DEMOGRAPHIC are supposed to have HL (the Mailhot extract should be pre-filtered). Patients without HL evidence anywhere are a data quality flag

### Fix vs report strategy
- **D-10:** Produce BOTH a reusable diagnostic script (07_diagnostics.R) AND fixes to existing scripts (utils_dates.R, 00_config.R, 03_cohort_predicates.R, 01_load_pcornet.R)
- **D-11:** 07_diagnostics.R is a permanent reusable tool — kept in R/ alongside other scripts, re-runnable whenever data is reloaded or pipeline changes
- **D-12:** Diagnostic output goes to BOTH console (summary via message()) AND detailed CSVs in output/diagnostics/
- **D-13:** Fixes applied directly to existing pipeline scripts — no intermediate "patch later" step
- **D-14:** After fixes, rebuild cohort by re-running the full pipeline (load → harmonize → build) to produce updated hl_cohort.csv with expanded HL identification

### Other parsing errors scope
- **D-15:** Check column type mismatches: verify readr col_types specs match actual CSV data. Flag numeric columns with text values, unexpected NAs from coercion failures
- **D-16:** Check missing/extra columns: compare expected columns (from specs in 01_load_pcornet.R) vs actual columns in each CSV. Flag discrepancies
- **D-17:** Check encoding issues: non-UTF8 characters, BOM markers, embedded newlines in fields
- **D-18:** Numeric range checks: flag obviously wrong values (negative ages, dates before 1900, tumor sizes > 999mm). Report counts and sample values
- **D-19:** Audit TUMOR_REGISTRY column types: check all 314+ TR1 columns and 140+ TR2/TR3 columns. Flag columns that look numeric or date-like but are loaded as character (all currently .default = col_character())

### Payer audit
- **D-20:** Full audit of payer mapping — check if prefix rules are matching correctly, validate dual-eligible detection counts, compare against Python pipeline reference counts

### Claude's Discretion
- Exact implementation of the Venn-style HL breakdown (console table format, CSV structure)
- Which specific TUMOR_REGISTRY columns to scan for histology (explore actual column names in data)
- Plausible numeric ranges for range checks (standard clinical ranges)
- Order and structure of diagnostic script sections
- How to handle the cohort rebuild (single re-source vs separate step)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing pipeline code (files to fix)
- `R/utils_dates.R` -- parse_pcornet_date() with 4-format fallback chain. Fix target for date parsing improvements
- `R/01_load_pcornet.R` -- Date column detection regex, col_types specs, load_pcornet_table(). Fix targets for column detection and type audit
- `R/03_cohort_predicates.R` -- has_hodgkin_diagnosis() predicate. Fix target to include TUMOR_REGISTRY histology
- `R/00_config.R` -- ICD_CODES list (add hl_histology), TREATMENT_CODES, PAYER_MAPPING. Fix target for histology code config
- `R/utils_icd.R` -- normalize_icd(), is_hl_diagnosis(). May need updates if histology matching requires new utility functions
- `R/02_harmonize_payer.R` -- Payer harmonization logic for payer audit comparison
- `R/04_build_cohort.R` -- Full pipeline to re-run after fixes

### Data schema
- `csv_columns.txt` -- Complete column listing for all 22 PCORnet CDM CSV files. Reference for column detection audit and type verification

### Payer mapping reference
- `C:\cygwin64\home\Owner\Data loading and cleaing\docs\PAYER_VARIABLES_AND_CATEGORIES.md` -- Python pipeline payer mapping for validation comparison

### Prior phase context
- `.planning/phases/01-foundation-data-loading/01-CONTEXT.md` -- D-09: date parser design, D-11: column names as-is, D-14: CSV naming pattern
- `.planning/phases/02-payer-harmonization/02-CONTEXT.md` -- Payer mapping logic details for audit comparison
- `.planning/phases/03-cohort-building/03-CONTEXT.md` -- D-01: filter chain order, D-04: payer exclusion rules

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `parse_pcornet_date()` in utils_dates.R: 4-format fallback (ISO, Excel serial, SAS DATE9, compact). Will be enhanced with additional formats if failures found
- `is_hl_diagnosis()` in utils_icd.R: ICD-9/10 matching with normalization. Will be expanded or supplemented for histology matching
- `normalize_icd()` in utils_icd.R: Dot removal for ICD codes. May inspire similar normalizer for histology codes
- `init_attrition_log()` + `log_attrition()`: Existing logging pattern to follow for diagnostic output structure
- `load_pcornet_table()`: Central load function where date column detection regex lives

### Established Patterns
- Named list storage: pcornet$TABLE_NAME for loaded data
- Console logging via message() + glue()
- CSV output via readr::write_csv() to output/ subdirectories
- Config-centralized code lists (ICD_CODES, TREATMENT_CODES, PAYER_MAPPING)
- Numbered script pattern: 07_diagnostics.R follows after 06_visualize_sankey.R

### Integration Points
- Input: All 9 pcornet$* tables (raw loaded data)
- Input: csv_columns.txt (reference for column audit)
- Output: output/diagnostics/ directory with CSV reports
- Fixes: utils_dates.R, 01_load_pcornet.R, 00_config.R, 03_cohort_predicates.R
- Downstream: Rebuilt hl_cohort.csv with expanded HL identification feeds into Phase 4 visualization

</code_context>

<specifics>
## Specific Ideas

- The Mailhot HL cohort extract (2025-09-15) should be all HL patients — anyone without HL evidence in DIAGNOSIS or TUMOR_REGISTRY is a data quality concern to flag prominently
- TUMOR_REGISTRY tables have different schemas (TR1: 314 cols, TR2/TR3: 140 cols each) with potentially different column names for histology (HISTOLOGY_ICDO3 vs HIST3V vs MORPH_ICDO3)
- The date column detection regex `(?i)(DATE|^DT_|^BDATE$|^DOD$|^DT_FU$|DXDATE)` may miss columns — compare against csv_columns.txt to find gaps
- Payer audit should compare R pipeline counts against Python pipeline reference to validate the harmonization is working correctly

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 05-fix-parsing-of-dates-and-other-possible-parsing-errors-and-investigate-why-not-everyone-has-an-hl-diagnosis*
*Context gathered: 2026-03-25*
