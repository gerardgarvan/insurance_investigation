# Phase 110: Redo Cancer Summary Table V2 7-Day (Confirmed HL Only) - Context

**Gathered:** 2026-06-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Tighten the existing cancer_summary_table_pre_post_v2_7day.xlsx with two restrictions: (1) restrict the entire table population to patients whose **HL diagnosis specifically** meets the 7-day gap criterion (not just any cancer code), and (2) restrict the Pre-HL, Post-HL, and Both columns (K-L-M) to only count secondary malignancies that themselves meet the 7-day confirmation criterion. Modify R/49 in-place; replace the existing v2_7day output (no new file).

</domain>

<decisions>
## Implementation Decisions

### Output Strategy
- **D-01:** Replace the existing `cancer_summary_table_pre_post_v2_7day.xlsx` with the new restricted version. The current v2 output becomes obsolete since the new version applies strictly tighter filters. The v1 (unfiltered) output remains as the baseline comparison.
- **D-02:** Same applies to companion files: `.csv` and `.rds` for v2 are overwritten with the tighter-filtered data.

### Script Approach
- **D-03:** Modify R/49 in-place. The existing V2 code path (Section 8b) already has the dual-output structure. Tighten the V2 population filter and secondary malignancy filter within the existing section. No new script created.

### Population Filter
- **D-04:** V2 table population restricted to patients whose **HL codes (C81 + ICD-9 201.x) specifically** meet the 7-day gap criterion (2+ unique HL diagnosis dates spanning 7+ calendar days). R/49 already computes this subset at lines 125-131 (`n_hl_7day`). Expand that computation to produce an ID vector for filtering.
- **D-05:** This replaces the current V2 filter which includes patients with 7-day confirmation for ANY cancer code (`two_or_more_unique_dates_gt_7 == 1` on any patient-code pair).

### Pre/Post/Both Columns (K-L-M)
- **D-06:** Columns K (Pre-HL), L (Post-HL), and M (Both) all require the secondary malignancy to be 7-day confirmed. A patient counts in K/L/M for a given category/code only if that secondary malignancy itself meets the 7-day gap criterion.
- **D-07:** All three temporal columns use the same rule — consistent filtering across K-L-M.

### Sheet Scope
- **D-08:** Both Sheet 1 (Category Summary) and Sheet 2 (Code Summary) apply the same tighter filtering. The workbook is internally consistent — no sheet uses a broader population than the other.

### Claude's Discretion
- Assertion bound adjustments for the tighter population (currently 6300-7500 for any-code v2; confirmed-HL-only will be smaller)
- Footnote text updates to clearly describe the new filtering criteria
- Title text update in xlsx to reflect confirmed HL population
- Console logging structure for the tighter filter diagnostics
- V1-vs-V2 comparison table adjustments (if needed)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Primary Script
- `R/49_cancer_summary_pre_post.R` — Script being modified. Section 8b (V2 tables) is the target. Lines 125-131 compute 7-day confirmed HL subset. Lines 518-534 compute V2 pre/post/both filtering.

### Cancer Summary Pipeline
- `R/45_cancer_summary.R` — Computes `two_or_more_unique_dates_gt_7` column per patient-code pair. Upstream of R/49.
- `R/47_cancer_summary_refined.R` — Produces `confirmed_hl_cohort.rds` (ID, first_hl_dx_date, first_hl_dx_source). Population anchor.

### Cancer Code Classification
- `R/utils/utils_cancer.R` — `classify_codes()` 4-tier cascade, `is_cancer_code()` detection
- `R/00_config.R` — CANCER_SITE_MAP (309 ICD-10 prefixes), ICD9_CANCER_SITE_MAP

### Prior Phase Context
- `.planning/phases/77-cancer-classification-refinements/77-CONTEXT.md` — Original V2 7-day filtering decisions (D-01 through D-10)
- `.planning/phases/104-treatment-timing-investigations/104-CONTEXT.md` — Dual 7-day confirmation concept (D-05, D-06)

### Quality
- `R/88_smoke_test_comprehensive.R` — V2 population assertion (Section referencing R/49 output)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `n_hl_7day` computation (R/49 lines 125-131): Already computes the 7-day confirmed HL patient count. Needs to be expanded to produce an ID vector (not just a count) for use as the V2 population filter.
- `v2_valid_pairs` pattern (R/49 lines 518-521): Semi-join pattern for filtering pre/post to confirmed patient-code pairs. Reuse this pattern with the tighter population.
- `compute_code_baseline()` and `compute_category_summary()` DRY helper functions (R/49 lines 299-339): Already parameterized with a label argument. Can pass the tighter-filtered dataset directly.

### Established Patterns
- V2 section (8b) mirrors V1 section (6-8) with filtered data passed through the same helpers
- Pre/post/both computed via semi_join on valid patient-code pairs
- HL anchor codes (C81 + 201.x) get NA in K-L-M columns

### Integration Points
- Reads: `output/confirmed_hl_cohort.rds` (R/47) — population anchor
- Reads: `output/tables/cancer_summary.csv` (R/45 via R/47) — baseline metrics with `two_or_more_unique_dates_gt_7` column
- Reads: DuckDB DIAGNOSIS table — raw diagnosis rows for pre/post computation
- Overwrites: `output/tables/cancer_summary_table_pre_post_v2_7day.{xlsx,csv,rds}` — tighter-filtered V2 output

</code_context>

<specifics>
## Specific Ideas

- The population change is conceptually: from "any patient with any 7-day confirmed cancer" to "only patients with 7-day confirmed HL specifically"
- The K-L-M change ensures secondary malignancies in temporal columns are also individually confirmed, preventing unconfirmed single-code appearances from inflating pre/post counts
- The V2 population will be smaller than current (~6,300-7,500 shrinks to the HL-specific 7-day subset). Assertion bounds need updating.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 110-redo-cancer-summary-table-pre-post-v2-7day-xlsx-but-have-it-so-only-confirmed-7-day-gap-hl-pts-are-in-it-and-rows-k-through-l-only-have-confirmed-7-day-gap-respective-malignancies*
*Context gathered: 2026-06-18*
