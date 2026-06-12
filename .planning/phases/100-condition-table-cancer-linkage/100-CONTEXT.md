# Phase 100: CONDITION Table Cancer Linkage - Context

**Gathered:** 2026-06-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Investigate the CONDITION table's potential to reduce the ~30% unlinked episode rate in cancer linkage. Produce an investigation report showing which currently-unlinked episodes WOULD gain cancer linkage from CONDITION data. **Does NOT modify treatment_episodes.rds or any existing outputs.** This is a read-only analysis that informs a future decision on whether to integrate CONDITION data into the production cascade.

</domain>

<decisions>
## Implementation Decisions

### Code Filtering
- **D-01:** Include only ICD-10 (CONDITION_TYPE = "10") and ICD-9 (CONDITION_TYPE = "09") codes from CONDITION table. SNOMED CT and ICD-11 are excluded since classify_codes() only handles ICD-10/ICD-9.
- **D-02:** No filtering on CONDITION_STATUS or CONDITION_SOURCE. Include all CONDITION rows regardless of status/source to maximize linkage coverage as a Tier 3 last-resort approach.

### Matching Approach
- **D-03:** Mirror the existing DIAGNOSIS cascade within CONDITION: (1) ENCOUNTERID match first, (2) temporal fallback using ONSET_DATE within 30 days before episode_start. This produces two new link method labels: `condition_encounter` and `condition_date`.
- **D-04:** Use ONSET_DATE (not REPORT_DATE) for temporal fallback — clinically analogous to DX_DATE used in DIAGNOSIS temporal matching.
- **D-05:** Only episodes currently with `cancer_link_method == "none"` are candidates for CONDITION matching. Episodes already linked via DIAGNOSIS tiers are not re-evaluated.

### Non-Destructive Constraint (Critical)
- **D-06:** This phase is **investigation only**. CONDITION linkage results are reported but NOT merged into treatment_episodes.rds. The existing R/28 script, all RDS files, all xlsx/csv outputs remain completely untouched.
- **D-07:** New standalone script (NOT a modification to R/28). Reads treatment_episodes.rds and CONDITION table, produces an investigation report showing what COULD be linked.
- **D-08:** No existing datasets, reports, or outputs are affected by this phase.

### Improvement Report
- **D-09:** Report lives as a new sheet ("Linkage Improvement") in the existing episode_classification_audit.xlsx workbook. Additive — no existing sheets are modified.
- **D-10:** Report contains aggregate before/after counts plus breakdown by treatment type (Chemo, RT, SCT, Immuno, Proton) showing which treatment types would benefit most from CONDITION linkage.

### Claude's Discretion
- Script numbering (e.g., R/29 or next available number in the decade)
- Console logging verbosity during analysis
- Whether to include a "would-be cancer categories" distribution in the report
- Smoke test additions for the new script

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Cancer Linkage Logic
- `R/28_episode_classification.R` — Current 2-tier cancer linkage cascade (ENCOUNTERID direct → 30-day temporal fallback). Sections 4a-4f are the linkage logic. New script should mirror this approach.
- `R/utils/utils_cancer.R` — classify_codes() 4-tier cascade and is_cancer_code() detection. Used to classify CONDITION codes into cancer categories.

### CONDITION Table Schema
- `R/01_load_pcornet.R` lines 86-106 — CONDITION_SPEC column definitions (CONDITIONID, ID, ENCOUNTERID, CONDITION, CONDITION_TYPE, CONDITION_SOURCE, CONDITION_STATUS, ONSET_DATE, REPORT_DATE, RESOLVE_DATE)

### Data Access
- `R/00_config.R` — CANCER_SITE_MAP, ICD9_CANCER_SITE_MAP, CONFIG paths
- `R/utils/utils_duckdb.R` — get_pcornet_table() for DuckDB queries, open/close_pcornet_con()

### Requirements
- `.planning/REQUIREMENTS.md` — COND-01, COND-02, COND-03 requirement definitions

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `classify_codes()` (utils_cancer.R): Handles ICD-10 + ICD-9 prefix matching — reuse directly for CONDITION codes
- `is_cancer_code()` (utils_cancer.R): Quick filter for cancer codes before classification
- `get_pcornet_table("CONDITION")`: DuckDB access already configured with ENCOUNTERID index
- `parse_pcornet_date()` (utils_dates.R): Multi-format date parsing for ONSET_DATE
- `assert_rds_exists()`, `assert_df_valid()`: Input validation helpers from R/00_config.R

### Established Patterns
- Episode enrichment in R/28 uses: load data → filter C-codes → ENCOUNTERID match → temporal fallback → combine → summarize
- Audit xlsx follows pattern: title row → subtitle → data table with styled headers → freeze panes → autofit (openxlsx2)
- Console logging uses glue() messages at each step

### Integration Points
- Reads: `cache/outputs/treatment_episodes.rds` (for unlinked episodes list)
- Reads: DuckDB CONDITION table (via get_pcornet_table)
- Writes: New sheet in `output/episode_classification_audit.xlsx`
- Does NOT write to any existing RDS files

</code_context>

<specifics>
## Specific Ideas

- User explicitly wants to see what CONDITION linkage COULD do before deciding whether to integrate it into production — "we don't know what we will do with CONDITION table"
- The report should make it easy to evaluate whether the improvement justifies integration
- Future decision (not this phase): if results are compelling, a follow-up phase could merge CONDITION data into the actual cascade in R/28

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 100-condition-table-cancer-linkage*
*Context gathered: 2026-06-12*
