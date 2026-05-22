# Phase 55: Cancer Summary Refinement Foundation - Context

**Gathered:** 2026-05-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Remove benign D-codes from cancer summary outputs, filter to a validated HL cohort (2+ C81 diagnosis codes at least 7 days apart), compute first HL diagnosis date as the minimum across DIAGNOSIS and TUMOR_REGISTRY sources, and regenerate cancer_summary.csv, cancer_summary.xlsx, and cancer_summary_table.xlsx. Column F (Hodgkin Lymphoma %) must reach 100% after cohort confirmation.

</domain>

<decisions>
## Implementation Decisions

### Script Structure
- **D-01:** Create a single new self-contained R/55 script (R/55_cancer_summary_refined.R) that handles everything: load R/53 CSV, remove D-codes, confirm cohort, compute first_hl_dx_date, aggregate to category+code sheets, write styled xlsx. R/53 and R/54 are preserved as baseline.
- **D-02:** R/55 produces both the patient-code level output (cancer_summary.csv/.xlsx) and the summary table output (cancer_summary_table.xlsx) internally. No need to re-run R/54.

### First HL Diagnosis Date
- **D-03:** first_hl_dx_date is computed as min(earliest DIAGNOSIS C81 date, earliest TUMOR_REGISTRY DATE_OF_DIAGNOSIS) per patient. True minimum across both sources, not TR-preferred fallback.
- **D-04:** first_hl_dx_date uses ANY C81 date regardless of whether the code meets the confirmation threshold. The cohort confirmation step already filters patients; the date itself should be the true earliest evidence.
- **D-05:** Add first_hl_dx_source column to the output with values: 'DIAGNOSIS', 'TUMOR_REGISTRY', or 'Both' (indicating which source provided the minimum date). Satisfies success criterion #5.

### Cohort Confirmation
- **D-06:** R/55 queries DIAGNOSIS directly for C81 codes, groups by patient, applies 7-day gap confirmation (max date - min date >= 7 days). Self-contained, no dependency on R/04 cohort.
- **D-07:** Confirmation uses any C81.xx sub-code — different subtypes (e.g., C81.10 and C81.90) count toward the 2+ code threshold. Clinically standard.
- **D-08:** Confirmation uses DIAGNOSIS table C81 codes only (DX_DATE). TUMOR_REGISTRY contributes to first_hl_dx_date but not to the confirmation threshold.

### Output File Handling
- **D-09:** R/55 overwrites the original output files: cancer_summary.csv, cancer_summary.xlsx, and cancer_summary_table.xlsx. R/53/R/54 can regenerate baseline anytime if needed.
- **D-10:** R/55 saves confirmed_hl_cohort.rds with columns: ID, first_hl_dx_date, first_hl_dx_source. Phase 56 (temporal filtering) and Phase 57 (Gantt enhancement) consume this artifact.

### Claude's Discretion
- Styling of the xlsx outputs (reuse R/54's dark header pattern)
- Console logging verbosity and attrition step messaging
- 1900 sentinel date handling (follow existing pattern from R/02)
- PREFIX_MAP: copy from R/53 for script independence (existing pattern) or import — Claude's call

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Cancer Summary Baseline
- `R/53_cancer_summary.R` — Patient-code level cancer summary with PREFIX_MAP, classify_codes(), description cascade. Phase 55 loads its CSV output.
- `R/54_cancer_summary_table.R` — Category + code level aggregation with styled two-sheet xlsx. Phase 55 replicates this output format.

### Cohort & HL Diagnosis
- `R/02_harmonize_payer.R` lines 185-226 — Current first_hl_dx_date computation (TR-preferred, not minimum). Phase 55 replaces this logic with true minimum.
- `R/00_config.R` lines 136-220 — HL_CODES list (150 ICD codes including C81.xx). Phase 55 uses C81 prefix matching.
- `R/03_cohort_predicates.R` lines 45-142 — has_hl_diagnosis() predicate using DIAGNOSIS + TUMOR_REGISTRY. Reference for TR table access patterns.

### Confirmation Pattern
- `R/51_cancer_site_confirmation_7day.R` — 7-day gap confirmation pattern at code level. Phase 55 applies similar logic at C81 prefix level for cohort confirmation.

### Requirements
- `.planning/REQUIREMENTS.md` — CREF-01 (D-code removal), CREF-02 (cohort confirmation), CREF-03 (first HL dx date)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PREFIX_MAP` (R/53, R/54, R/47): Named vector mapping 3-character ICD-10 prefixes to cancer site categories. Includes D-codes that Phase 55 will filter out.
- `classify_codes()` (R/53): Takes normalized codes, returns category names. Reusable as-is.
- Description cascade (R/53 Section 4): Multi-source lookup (RDS artifacts > hardcoded > config comments). Can be reused for code-level descriptions.
- Styled xlsx pattern (R/54): Dark header, freeze pane, number formatting, totals row. Reuse for output consistency.
- `get_pcornet_table()` / `TUMOR_REGISTRY_ALL` (R/01): DuckDB accessor for DIAGNOSIS and TUMOR_REGISTRY tables.

### Established Patterns
- Script independence: Each script copies PREFIX_MAP rather than importing from a shared module (noted as sync risk but accepted for v1.7)
- 1900 sentinel date nullification: Applied in R/02 and R/04. Must apply in R/55's first_hl_dx_date computation.
- DuckDB as default backend: All DIAGNOSIS queries use `get_pcornet_table("DIAGNOSIS") %>% filter() %>% collect()`

### Integration Points
- **Input:** `output/tables/cancer_summary.csv` (R/53 output)
- **Output:** Overwrites `output/tables/cancer_summary.csv`, `cancer_summary.xlsx`, `cancer_summary_table.xlsx`
- **New artifact:** `confirmed_hl_cohort.rds` saved to CONFIG$output_dir — consumed by Phase 56 and Phase 57
- **DuckDB connection:** `source("R/01_load_pcornet.R")` + `close_pcornet_con()` at end

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 55-cancer-summary-refinement-foundation*
*Context gathered: 2026-05-22*
