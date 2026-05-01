# Phase 38: Chemo Treatment Inventory by Source Table - Context

**Gathered:** 2026-05-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Create an aggregate inventory of all treatment-related records in the PCORnet CDM data, broken down by source table (PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, DIAGNOSIS, ENCOUNTER, TUMOR_REGISTRY). Covers 4 treatment types: chemotherapy, radiation, stem cell transplant (SCT), and immunotherapy (CAR T-cell). Queries all patients in the raw data (not restricted to HL cohort). Outputs a styled xlsx workbook with one sheet per treatment type, matching the formatting pattern established in csv_to_xlsx.py.

</domain>

<decisions>
## Implementation Decisions

### Treatment Type Scope
- **D-01:** Cover all 4 treatment types: chemotherapy, radiation, SCT, and immunotherapy (CAR T-cell). Use existing TREATMENT_CODES lists in 00_config.R (chemo_*, radiation_*, sct_*, cart_icd10pcs_prefixes).
- **D-02:** Each treatment type gets its own sheet in the output xlsx.

### Output Granularity
- **D-03:** Aggregate summary only -- code frequencies and counts per source table per treatment type. No patient-level detail (no patient IDs in output).

### Cohort Scope
- **D-04:** Query all patients in the raw PCORnet extract, regardless of cohort status. Script sources 00_config.R + 01_load_pcornet.R but does NOT run the cohort pipeline.

### Output Format
- **D-05:** Produce a styled xlsx workbook matching csv_to_xlsx.py visual patterns: title/subtitle row, "By Source Table" summary section with treatment-type colored pills, "Detailed Codes" section with code, source table, count, and % of total columns, frozen panes, header fills.
- **D-06:** No HIPAA small-cell suppression -- show exact counts. This is an internal exploratory tool.
- **D-07:** Show raw code values only (no human-readable descriptions). Keeps output simple.

### Code Discovery
- **D-08:** Include unknown treatment codes not in our TREATMENT_CODES lists. Use broad CPT/HCPCS range heuristics to identify potentially missed codes within treatment code families (e.g., 96xxx for chemo admin, 77xxx for radiation, 38xxx for transplant, J-codes for chemo drugs). Flag these as "Unmatched" in a separate section per sheet.

### Script & Packaging
- **D-09:** Script named R/38_treatment_inventory.R following existing numbering convention.
- **D-10:** Sources only R/00_config.R and R/01_load_pcornet.R -- lightweight dependency chain since it doesn't need the cohort pipeline.

### Claude's Discretion
- xlsx package selection (openxlsx2 recommended for full styling support without Java dependency)
- Treatment-type color scheme for xlsx pills (analogous to CATEGORY_COLORS in csv_to_xlsx.py but for treatment types instead of payer categories)
- Exact CPT/HCPCS range boundaries for the "unknown code discovery" heuristic
- Internal function organization within R/38_treatment_inventory.R
- How to handle TUMOR_REGISTRY date columns (DT_CHEMO, DT_RAD, DT_HTE) as treatment evidence vs. the coded records in other tables

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Treatment code configuration
- `R/00_config.R` -- TREATMENT_CODES list (all chemo, radiation, SCT, immunotherapy code vectors), SURVEILLANCE_CODES, LAB_CODES. Section 5.5-5.6.

### Existing treatment detection patterns
- `R/03_cohort_predicates.R` Section 2 -- has_chemo(), has_radiation(), has_sct() functions showing how each table is queried for treatment evidence
- `R/10_treatment_payer.R` -- compute_payer_at_chemo/radiation/sct() showing date extraction from multiple sources

### Data loading
- `R/01_load_pcornet.R` -- PCORnet table loading with col_types. All 13 tables including DISPENSING, MED_ADMIN.

### xlsx styling reference
- `csv_to_xlsx.py` -- Python xlsx formatter with styled sheets, category-colored pills, header fills, frozen panes. Visual pattern to replicate in R.

### Prior phase context
- `.planning/phases/08-*/08-CONTEXT.md` -- Treatment-anchored payer decisions (D-01 through D-12)
- `.planning/phases/09-*/09-CONTEXT.md` -- Expanded treatment detection decisions (D-01 through D-15), code sources per table

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TREATMENT_CODES` in R/00_config.R: Complete named list of all treatment code vectors across all code systems (HCPCS, RXNORM, ICD-9, ICD-10-PCS, DRG, revenue codes). Phase 38 queries the actual data for each.
- `get_pcornet_table()` in R/utils_duckdb.R: Backend-transparent table access (DuckDB mode). Already used by all diagnostic scripts.
- `has_chemo()`, `has_radiation()`, `has_sct()` in R/03_cohort_predicates.R: Show the exact query patterns for each table. Can serve as templates for the inventory queries.
- `csv_to_xlsx.py` styling functions: `write_sheet()`, `category_style()`, color constants. Pattern to replicate in R.

### Established Patterns
- PX_TYPE matching: "CH" for CPT/HCPCS, "09" for ICD-9-CM, "10" for ICD-10-PCS, "RE" for revenue codes
- ICD-10-PCS prefix matching uses `str_starts()` for variable-length codes
- RXNORM matching in DISPENSING/MED_ADMIN uses RXNORM_CUI column
- DRG matching in ENCOUNTER uses DRG column
- Diagnosis matching uses DX + DX_TYPE columns
- Null-safe table access: `tryCatch(get_pcornet_table("TABLE"), error = function(e) NULL)`

### Integration Points
- R/00_config.R: Source for all treatment code lists
- R/01_load_pcornet.R: Table loading (must be sourced before inventory queries)
- output/ directory: Destination for xlsx output file

</code_context>

<specifics>
## Specific Ideas

- Match csv_to_xlsx.py visual style: title/subtitle, "By Source Table" summary with colored pills, "Detailed Codes" grid with code/source/count/percentage, frozen panes
- Each of the 4 treatment type sheets should show which PCORnet tables contributed records and what specific codes were found
- "Unmatched" section on each sheet reveals treatment-adjacent codes in the data that aren't in our TREATMENT_CODES lists, using broad CPT range heuristics
- Script runs independently of cohort pipeline -- quick to execute for ad-hoc exploration

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 38-chemo-treatment-inventory-by-source-table*
*Context gathered: 2026-05-01*
