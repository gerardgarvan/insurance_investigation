# Phase 77: Cancer Classification Refinements - Context

**Gathered:** 2026-06-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Extend the 7-day unique day gap requirement to ALL cancer categories in R/49 (not just HL), producing a versioned v2_7day output alongside the existing output. Implement NLPHL breakout reporting in R/49's diagnostic section. Centralize drug groupings from all_codes_resolved_next_tables.xlsx into a named vector in R/00_config.R. No changes to R/45-R/48 or R/51 — those scripts inherit NLPHL awareness automatically via classify_codes().

</domain>

<decisions>
## Implementation Decisions

### 7-Day Gap Application
- **D-01:** Filter patient-code rows in R/49 where `two_or_more_unique_dates_gt_7 == 1`. Only rows meeting the 7-day threshold appear in the v2_7day output. This should yield total population = 6,347.
- **D-02:** Produce BOTH existing (unfiltered) output AND new v2_7day output. Enables v1 vs v2 comparison.
- **D-03:** Comparison table (v1 vs v2 deltas per category) printed to console log only — no persistent comparison file.
- **D-04:** Assert total filtered population within tolerance range (6300-6400) using checkmate. Hard fail if outside range.

### Drug Groupings Format
- **D-05:** DRUG_GROUPINGS as a named vector in R/00_config.R (code = "group_name"). Follows AMC_PAYER_LOOKUP/CANCER_SITE_MAP pattern.
- **D-06:** Copy all_codes_resolved_next_tables.xlsx to `data/reference/` with version suffix (e.g., `all_codes_resolved_next_tables_v2.1.xlsx`). Git-tracked snapshot.
- **D-07:** Schema (sheet names, columns, which data maps to the named vector) to be confirmed by researcher on HiPerGator during planning — STATE.md open question #2.

### Output Versioning
- **D-08:** Only R/49 produces v2_7day variants. Upstream scripts (R/45-R/48) unchanged.
- **D-09:** Full output set for v2_7day: .rds + .xlsx + .csv (matches existing R/49 output pattern).
- **D-10:** Filenames: `cancer_summary_table_pre_post_v2_7day.{rds,xlsx,csv}`

### NLPHL Downstream Scope
- **D-11:** R/49's C81 diagnostic section (lines 97-128) updated to split NLPHL (C81.0) vs classical HL (C81.1-C81.9) counts in console log.
- **D-12:** All other scripts (R/45-R/48, R/51, R/28) require NO code changes — re-running with updated config/classify_codes() is sufficient.
- **D-13:** NLPHL validation: confirm no patient double-counted (already exists from Phase 75 smoke test — reuse assertion).

### Claude's Discretion
No areas deferred to Claude's discretion — all gray areas resolved by user.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Core Scripts
- `R/49_cancer_summary_pre_post.R` -- Primary script being modified (7-day filter, NLPHL diagnostics, v2 output)
- `R/45_cancer_summary.R` -- Computes `two_or_more_unique_dates_gt_7` column (NOT modified, but must understand its logic)
- `R/00_config.R` -- Receives DRUG_GROUPINGS named vector; contains CANCER_SITE_MAP (already has NLPHL entries from Phase 75)
- `R/utils/utils_cancer.R` -- classify_codes() (already updated in Phase 75 — no changes needed)

### Data Sources
- `all_codes_resolved_next_tables.xlsx` (project root) -- Source for DRUG_GROUPINGS extraction. Schema unverified — researcher must inspect sheets/columns on HiPerGator.

### Requirements
- `.planning/REQUIREMENTS.md` -- CANCER-01 (NLPHL breakout), CANCER-02 (7-day gap all categories), TREAT-02 (drug groupings centralized), QUAL-01 (v2.0 standards)

### Prior Phase Context
- `.planning/phases/75-configuration-extensions-nlphl-death-cause/75-CONTEXT.md` -- NLPHL config decisions (D-01 through D-09)

### Quality Standards
- `R/88_smoke_test_comprehensive.R` -- Existing NLPHL mutual exclusivity test; new assertions for 7-day gap validation

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `two_or_more_unique_dates_gt_7` column: Already computed in R/45 for ALL patient-code pairs. R/49 just needs to filter on it.
- `classify_codes()`: Already returns "NLPHL" for C81.0 codes. No further changes needed.
- `AMC_PAYER_LOOKUP` pattern in R/00_config.R: Template for DRUG_GROUPINGS structure (named vector, top-level constant).
- `build_output_path()`: Utility for constructing output file paths — use for v2_7day outputs.

### Established Patterns
- Section headers: `# SECTION N: NAME ----`
- Input validation: `checkmate::assert_*()` at script start
- Output: openxlsx2 for .xlsx generation, write.csv for .csv, saveRDS for .rds
- Console logging: `message()` + `glue()` for diagnostic output

### Integration Points
- R/49 reads `cancer_summary.csv` (from R/47) and `confirmed_hl_cohort.rds` (from R/47)
- R/49 queries DuckDB DIAGNOSIS table directly for raw date rows
- DRUG_GROUPINGS in config will be consumed by Phase 78 (episode classification)

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches following existing R/49 patterns and v2.0 quality standards.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 77-cancer-classification-refinements*
*Context gathered: 2026-06-02*
