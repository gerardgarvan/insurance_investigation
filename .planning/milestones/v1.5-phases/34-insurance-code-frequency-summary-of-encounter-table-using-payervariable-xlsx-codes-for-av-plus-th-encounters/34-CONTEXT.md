# Phase 34: Insurance Code Frequency Summary — Context

**Gathered:** 2026-04-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce a frequency summary of raw PAYER_TYPE_PRIMARY and PAYER_TYPE_SECONDARY codes in the ENCOUNTER table (AV+TH encounters only), cross-referenced against the PayerVariable.xlsx lookup table to show each code's description (column B) and mapped category (column C). Outputs: per-field code-level detail CSVs and a category-level aggregate summary CSV, plus console summary.

</domain>

<decisions>
## Implementation Decisions

### Output Content
- **D-01:** Cover BOTH PAYER_TYPE_PRIMARY and PAYER_TYPE_SECONDARY as separate frequency tables (one CSV per field).
- **D-02:** Each row contains: raw code value | PayerVariable.xlsx description (col B: "What old value means") | PayerVariable.xlsx mapped category (col C: "New Value") | encounter count | percentage of total.
- **D-03:** Codes found in the ENCOUNTER data but NOT in PayerVariable.xlsx are flagged as "NOT IN XLSX" in description and category columns.

### Mapping Approach
- **D-04:** Use the explicit PayerVariable.xlsx mappings as the reference — both the detailed col B descriptions and the col C higher-level categories. This is NOT a comparison against the R pipeline's PAYER_MAPPING; it's the xlsx's own mapping applied to the data.
- **D-05:** No R pipeline PAYER_MAPPING comparison column. The xlsx mappings stand on their own.

### Grouping & Aggregation
- **D-06:** Overall frequencies only — all AV+TH encounters combined (no per-site or per-year breakdown).
- **D-07:** Add a category-level summary CSV aggregating counts by the xlsx column C category (Medicare, Medicaid, Other govt, Private, Uninsured, Other, Impute). Quick big-picture view.

### Script Structure
- **D-08:** Read PayerVariable.xlsx dynamically at runtime using `readxl::read_excel()`. No hardcoded lookup table.
- **D-09:** Reference PayerVariable.xlsx from repo root as-is. Add a config constant like `PAYER_XLSX_PATH` at the top of the script.
- **D-10:** Standalone diagnostic script following Phase 33 pattern: `source("R/00_config.R")`, DuckDB mode with `get_pcornet_table("ENCOUNTER")`, materialize-early, AV+TH filter.

### Claude's Discretion
- Script numbering (likely R/35_*.R or similar)
- Console summary format and detail level
- CSV file naming convention (with `_av_th` suffix to match Phase 33 pattern)
- Whether to include a "total" row in the CSV or just in console output
- Sort order of codes in output (by frequency descending, or by code value)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### PayerVariable Reference
- `PayerVariable.xlsx` (Sheet2) — 166-row lookup table with 3 columns: "Value In Data" (raw code), "What old value means" (description), "New Value" (mapped category: Medicare, Medicaid, Other govt, Private, Uninsured, Other, Impute)

### AV+TH Pattern
- `R/33_multi_source_overlap_av_th.R` — Phase 33 AV+TH filtering pattern, DuckDB materialize-early approach, standalone script structure
- `R/34_overlap_classification_av_th.R` — Additional Phase 33 AV+TH script

### Infrastructure
- `R/00_config.R` — USE_DUCKDB flag, PAYER_MAPPING definition (for context, not used in this phase's mapping), output_dir
- `R/utils_duckdb.R` — `get_pcornet_table()`, `open_pcornet_con()`, `materialize()` helpers
- `R/02_harmonize_payer.R` — Existing payer harmonization logic (context only — this phase uses xlsx mapping, not R pipeline mapping)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `get_pcornet_table("ENCOUNTER")` — DuckDB backend-transparent access to ENCOUNTER table
- `materialize()` — Collect lazy DuckDB query to tibble
- `open_pcornet_con()` / `close_pcornet_con()` — DuckDB connection management
- Phase 33 scripts as structural template (R/33, R/34) for standalone AV+TH diagnostic scripts

### Established Patterns
- AV+TH filter: `filter(ENC_TYPE %in% c("AV", "TH"))` applied after materialize
- Materialize-early: `get_pcornet_table("ENCOUNTER") %>% materialize()` then in-memory operations
- Standalone script structure: `source("R/00_config.R")`, conditional `source("R/01_load_pcornet.R")`, DuckDB connection management
- CSV output to `output/tables/` with `readr::write_csv()`

### Integration Points
- `readxl::read_excel()` — new dependency for this script (available on CRAN, likely already on HiPerGator)
- ENCOUNTER table columns: ID, ENCOUNTERID, ADMIT_DATE, SOURCE, ENC_TYPE, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY

</code_context>

<specifics>
## Specific Ideas

- User explicitly wants both column B (detailed descriptions like "Medicare HMO") and column C (mapped categories like "Medicare") from the xlsx visible in the output
- Single CSV per payer field with all columns — not split across multiple files for code vs category level
- Category-level summary is a separate additional CSV, not a replacement for the detail

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 34-insurance-code-frequency-summary-of-encounter-table-using-payervariable-xlsx-codes-for-av-plus-th-encounters*
*Context gathered: 2026-04-26*
