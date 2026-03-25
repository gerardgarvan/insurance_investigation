# Phase 6: Use Debug Output to Rectify Issues - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Take the diagnostic output from 07_diagnostics.R (6 audit sections, CSV files in output/diagnostics/) and use those findings to fix data quality issues across the pipeline. This includes expanding date parsing, updating column type specs, fixing regex gaps, excluding patients without HL evidence, and rebuilding the full pipeline end-to-end. The phase is data-driven: the user runs diagnostics on HiPerGator first, shares the output, and Claude writes targeted fixes based on actual findings.

</domain>

<decisions>
## Implementation Decisions

### Issue triage
- **D-01:** Fix everything fixable in code -- any issue that CAN be fixed should be. Only document truly unfixable data-level problems.
- **D-02:** Patients with "Neither" HL source (no evidence in DIAGNOSIS or TUMOR_REGISTRY) are flagged and excluded from the final cohort. Write excluded patients to `output/cohort/excluded_no_hl_evidence.csv` with ID, SOURCE, and reason.
- **D-03:** Expand the date parser (utils_dates.R) to handle new date formats discovered by diagnostics. Goal: minimize character-type date columns.
- **D-04:** Document R vs Python payer mapping differences side-by-side. Exact parity not required -- the comparison should be visible but the R pipeline is exploratory.
- **D-05:** Update col_types specs in 01_load_pcornet.R for ALL columns flagged by the TUMOR_REGISTRY type audit (not just pipeline-critical ones). More accurate types = better data quality.
- **D-06:** Encoding issues (non-ASCII, BOM) -- flag only, do not strip during load. Document in diagnostics output.
- **D-07:** Expand the date column detection regex in 01_load_pcornet.R to catch any date columns missed per csv_columns.txt audit.
- **D-08:** Numeric range issues (negative ages, extreme sizes, pre-1900 dates) -- add validation columns (e.g., AGE_VALID = TRUE/FALSE) but preserve original raw values.
- **D-09:** For columns with >50% missing, investigate whether it's a loading/parsing issue vs. genuinely absent data. Fix if parsing issue; document if genuinely absent.

### Fix approach
- **D-10:** All fixes go directly into existing pipeline scripts (00_config.R, 01_load_pcornet.R, utils_dates.R, 03_cohort_predicates.R, etc.). No separate fix script.
- **D-11:** Fixes are data-driven: user runs 07_diagnostics.R on HiPerGator first, shares diagnostic CSV files AND sample raw data rows, then Claude writes targeted fixes based on actual findings.
- **D-12:** Iterate until clean -- multiple rounds of diagnostics -> fixes -> re-run diagnostics until all remaining issues are explained.
- **D-13:** Fixes are grouped by issue type (all date fixes together, all col_type fixes together, all payer fixes together) for easier debugging.

### Validation strategy
- **D-14:** Targeted checks after each fix batch, then one full 07_diagnostics.R re-run at the end to confirm everything.
- **D-15:** The full diagnostics script runs fast enough on HiPerGator -- no need for section-level flags.
- **D-16:** "Clean enough" = all remaining issues in the final diagnostic output have an explanation (e.g., "X dates NA because field is optional per PCORnet CDM spec"). No unexplained anomalies.
- **D-17:** Final validation produces a CSV summary (output/diagnostics/data_quality_summary.csv) with columns: issue_type, count_before, count_after, status (fixed/accepted/documented), notes.

### Cohort rebuild scope
- **D-18:** Full end-to-end pipeline rebuild after all fixes: 00_config -> 01_load -> 02_harmonize -> 03_predicates -> 04_build -> 05_waterfall -> 06_sankey. All outputs (cohort CSV, waterfall PNG, sankey PNG) regenerated.
- **D-19:** Update 07_diagnostics.R if fixes change column names, table structures, or detection logic. Diagnostic script must reflect current pipeline state.
- **D-20:** Rebuilt cohort CSV includes an HL_SOURCE column showing how each patient was identified ('DIAGNOSIS only', 'TR only', 'Both'). Useful for downstream stratification.

### Claude's Discretion
- Specific date format patterns to add to parse_pcornet_date() (depends on what diagnostics reveal)
- Which col_types to change for TUMOR_REGISTRY columns (depends on type audit output)
- Exact regex additions for date column detection (depends on csv_columns.txt audit)
- Plausible numeric ranges for validation columns (standard clinical ranges)
- Structure of the data quality summary CSV
- How to implement HL_SOURCE column in the cohort build pipeline

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Diagnostic script and output
- `R/07_diagnostics.R` -- The diagnostic script that produces all audit output. Must be read to understand what issues are detected and how they're reported.
- `output/diagnostics/` -- Directory containing diagnostic CSVs (date_parsing_failures.csv, date_column_regex_audit.csv, column_discrepancies.csv, missing_values_audit.csv, encoding_issues.csv, tr_type_audit.csv, hl_identification_venn.csv, hl_identification_detail.csv, payer_mapping_audit.csv, payer_raw_codes.csv, numeric_range_issues.csv)

### Pipeline scripts to fix
- `R/utils_dates.R` -- parse_pcornet_date() with 4-format fallback chain. Fix target for date parser expansion.
- `R/01_load_pcornet.R` -- Date column detection regex, col_types specs, load_pcornet_table(). Fix targets for regex and type updates.
- `R/00_config.R` -- ICD_CODES, TREATMENT_CODES, PAYER_MAPPING configuration. Fix target if config-level changes needed.
- `R/03_cohort_predicates.R` -- has_hodgkin_diagnosis() and filter predicates. Fix target for HL_SOURCE tracking and "Neither" exclusion.
- `R/04_build_cohort.R` -- Cohort assembly pipeline. Fix target for HL_SOURCE column addition and exclusion CSV output.

### Visualization scripts (part of full rebuild)
- `R/05_visualize_waterfall.R` -- Attrition waterfall chart. Must work with updated attrition_log after fixes.
- `R/06_visualize_sankey.R` -- Payer-stratified Sankey diagram. Must work with updated hl_cohort after fixes.

### Data reference
- `csv_columns.txt` -- Complete column listing for all 22 PCORnet CDM CSV files. Reference for column detection audit.

### Prior phase context
- `.planning/phases/05-fix-parsing-of-dates-and-other-possible-parsing-errors-and-investigate-why-not-everyone-has-an-hl-diagnosis/05-CONTEXT.md` -- Phase 5 decisions that established the diagnostic framework and HL identification expansion.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `parse_pcornet_date()` in utils_dates.R: 4-format fallback (ISO, Excel serial, SAS DATE9, compact). Will be expanded with additional formats.
- `is_hl_diagnosis()` in utils_icd.R: ICD-9/10 matching with normalization. Already expanded in Phase 5 to include histology.
- `is_hl_histology()` in utils_icd.R: ICD-O-3 histology matching (9650-9667). Added in Phase 5.
- `07_diagnostics.R`: 6-section diagnostic script producing console summaries + CSVs. The primary input for this phase.
- `load_pcornet_table()` in 01_load_pcornet.R: Central load function with date column detection regex and col_types specs.
- `init_attrition_log()` + `log_attrition()`: Existing attrition logging pattern used in cohort build.

### Established Patterns
- Named list storage: pcornet$TABLE_NAME for loaded data
- Console logging via message() + glue()
- CSV output via readr::write_csv() to output/ subdirectories
- Config-centralized code lists (ICD_CODES, TREATMENT_CODES, PAYER_MAPPING)
- Numbered script pattern: 00 through 07
- TABLE_SPECS named list for col_types in 01_load_pcornet.R

### Integration Points
- Input: Diagnostic CSV files from output/diagnostics/ (user shares from HiPerGator)
- Input: Sample raw data rows (user shares for context on specific issues)
- Fixes: Applied to R/utils_dates.R, R/01_load_pcornet.R, R/00_config.R, R/03_cohort_predicates.R, R/04_build_cohort.R, R/07_diagnostics.R
- Output: Updated output/cohort/hl_cohort.csv with HL_SOURCE column
- Output: New output/cohort/excluded_no_hl_evidence.csv
- Output: New output/diagnostics/data_quality_summary.csv
- Output: Regenerated output/figures/waterfall_attrition.png and sankey_patient_flow.png

</code_context>

<specifics>
## Specific Ideas

- The workflow is iterative: user runs diagnostics on HiPerGator, shares CSV files + sample rows with Claude, Claude writes fixes, user applies and re-runs, repeat until all issues are explained.
- Fixes are batched by issue type (date fixes, col_type fixes, payer fixes) for easier debugging.
- "Neither" patients (no HL evidence) should be excluded from the cohort but preserved in a separate audit CSV.
- The rebuilt cohort must include HL_SOURCE so downstream analysis can stratify by identification method.
- The final data_quality_summary.csv serves as the formal resolution record for all diagnostic findings.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 06-use-debug-output-to-rectify-issues*
*Context gathered: 2026-03-25*
