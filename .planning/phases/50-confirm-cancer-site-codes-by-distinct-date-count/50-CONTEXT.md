# Phase 3: Confirm Cancer Site Codes by Distinct Date Count - Context

**Gathered:** 2026-05-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Validate cancer site diagnosis codes from the DIAGNOSIS table by requiring at least 2 distinct dates per code per patient before counting the code as "confirmed." Produces a styled xlsx comparing total vs confirmed patient counts at two matching levels (exact code and 3-char prefix). This is a new analysis script — R/47 stays as the unfiltered frequency baseline.

</domain>

<decisions>
## Implementation Decisions

### Code Matching Level
- **D-01:** Run confirmation at TWO levels: (1) exact ICD-10 code (e.g., C81.10 must appear on 2+ distinct dates), and (2) 3-character prefix (e.g., any C81.* code on 2+ distinct dates confirms C81). Both levels are computed and reported.
- **D-02:** Output is one xlsx workbook with two sheets — Sheet 1 for exact code confirmation, Sheet 2 for prefix-level confirmation. Easy side-by-side comparison.

### Data Sources
- **D-03:** DIAGNOSIS table only. Use DX_DATE as the date for distinct-date counting. TUMOR_REGISTRY entries are already registrar-confirmed and do not need date-based validation.
- **D-04:** Only ICD-10 codes (DX_TYPE == "10") — consistent with R/47's DIAGNOSIS query.

### Output Format
- **D-05:** Per cancer site category: total_patients, confirmed_patients, unconfirmed_patients, confirmation_rate. Shows the impact of the confirmation filter at a glance.
- **D-06:** Only show populated categories (those with at least one patient). No zero-count rows.
- **D-07:** Styled xlsx output following established openxlsx2 patterns from prior phases.

### Script Structure
- **D-08:** New script (R/50_*.R or next available number). R/47 stays as the unfiltered baseline. New script reuses R/47's PREFIX_MAP and classify_codes() logic but adds the confirmation filter.

### Claude's Discretion
- Exact script numbering (next available R/NN_*.R)
- Whether to source PREFIX_MAP from R/47 directly or duplicate/extract to a shared location
- Column ordering and xlsx styling details
- Whether to include a summary row at the bottom of each sheet

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Cancer Site Classification (Primary Reference)
- `R/47_cancer_site_frequency.R` lines 39-309 — PREFIX_MAP: 53 cancer site categories mapped from ICD-10-CM 3-char prefixes
- `R/47_cancer_site_frequency.R` lines 375-382 — `classify_codes()` function for 3-char prefix matching
- `R/47_cancer_site_frequency.R` lines 388-419 — DIAGNOSIS table query pattern (DX_TYPE == "10", select ID/DX, normalize, classify)

### ICD Code Utilities
- `R/utils_icd.R` lines 36-44 — `normalize_icd()` removes dots and uppercases codes
- `R/00_config.R` lines 135-236 — ICD_CODES lists (HL-specific, but shows ICD code structure)

### DuckDB Access
- `R/utils_duckdb.R` lines 100-138 — `open_pcornet_con()` and `get_pcornet_table()` patterns

### Styled XLSX Output Pattern
- `R/47_cancer_site_frequency.R` lines 597-694 — openxlsx2 styled xlsx output pattern to follow

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PREFIX_MAP` in R/47 (lines 39-309): 53-category mapping from ICD-10-CM 3-char prefix to cancer site name
- `classify_codes()` in R/47 (lines 375-382): Takes normalized codes, returns category names via prefix matching
- `CATEGORY_ORDER` in R/47 (lines 312-367): Display ordering for categories
- `normalize_icd()` in R/utils_icd.R: Standard code normalization (remove dots, uppercase)
- `get_pcornet_table()` in R/utils_duckdb.R: Backend-transparent table accessor

### Established Patterns
- DIAGNOSIS query: `get_pcornet_table("DIAGNOSIS") %>% filter(DX_TYPE == "10") %>% select(ID, DX, DX_DATE) %>% collect()`
- Group-by summarise for patient/record counts: `group_by(category) %>% summarise(patients = n_distinct(ID))`
- openxlsx2 styled xlsx with `wb_add_data_table()`, header styling, auto column widths

### Integration Points
- Input: DIAGNOSIS table via DuckDB (same source as R/47)
- Output: New xlsx in `CONFIG$output_dir` or output/tables/
- No modification to R/47 or other existing scripts

</code_context>

<specifics>
## Specific Ideas

- The distinct-date confirmation is a standard epidemiological approach — a single diagnosis may be a rule-out, while 2+ dates suggests a real diagnosis
- R/47's existing DIAGNOSIS query needs DX_DATE added to the select() for this phase
- Phase 4 will add a 7-day separation requirement on top of this same logic, so the script structure should accommodate that easily (the date-distinct logic is the base, 7-day gap is a stricter filter)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-confirm-cancer-site-codes-by-distinct-date-count*
*Context gathered: 2026-05-19*
