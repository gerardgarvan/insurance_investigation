# Phase 56: Temporal Filtering - Context

**Gathered:** 2026-05-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce a post-HL cancer summary variant — cancer diagnoses occurring after each patient's first HL diagnosis date — alongside the existing baseline outputs. The post-HL variant is clearly labeled as EXPLORATORY (potential immortal time bias). A side-by-side comparison sheet shows denominator differences between baseline and post-HL filtered results.

</domain>

<decisions>
## Implementation Decisions

### Script Architecture
- **D-01:** Create a new standalone R/56_cancer_summary_post_hl.R script. R/55 baseline outputs are not modified. R/56 reads confirmed_hl_cohort.rds (from Phase 55) and cancer_summary.csv to produce _post_hl suffixed outputs.
- **D-02:** R/56 follows the same single-script consolidation pattern as R/55 — produces both patient-code level outputs (csv, xlsx) and summary table (xlsx) internally.

### Comparison Output
- **D-03:** The side-by-side comparison is presented as a third sheet ("Comparison") in cancer_summary_table_post_hl.xlsx. Shows baseline vs post-HL counts per cancer category: total patients, total codes, and delta. Keeps everything in one workbook.

### EXPLORATORY Labeling
- **D-04:** Each sheet name in the post-HL xlsx outputs includes an "[EXPLORATORY]" prefix (e.g., "EXPLORATORY - Category Summary").
- **D-05:** A footnote row at the bottom of each data sheet reads: "Note: Post-HL filter introduces potential immortal time bias. Use for exploratory comparison only."

### Edge Case Handling
- **D-06:** Patients with NA first_hl_dx_date are excluded from the post-HL variant entirely. They remain in baseline only. The comparison sheet reports the exclusion count.

### Claude's Discretion
- Same-day cancer diagnoses (DX_DATE == first_hl_dx_date): Claude decides whether to use strict > or >= based on clinical standard for temporal comparisons
- Console logging verbosity and attrition step messaging
- Styling of post-HL xlsx outputs (reuse R/55's dark header pattern for consistency)
- PREFIX_MAP handling (copy from R/55 for script independence, or load from cancer_summary.csv which already has categories)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 55 Foundation (Direct Upstream)
- `R/55_cancer_summary_refined.R` — Produces baseline cancer_summary.csv, cancer_summary.xlsx, cancer_summary_table.xlsx, and confirmed_hl_cohort.rds. Phase 56 reads these outputs.
- `.planning/phases/55-cancer-summary-refinement-foundation/55-01-SUMMARY.md` — Documents confirmed_hl_cohort.rds schema (ID, first_hl_dx_date, first_hl_dx_source) and all output file locations.

### Existing Patterns
- `R/55_cancer_summary_refined.R` lines 550-673 — Two-sheet styled xlsx pattern (Category Summary + Code Summary) with dark headers, freeze panes, number formatting, totals row. Phase 56 replicates this pattern plus adds Comparison sheet.
- `R/55_cancer_summary_refined.R` lines 435-464 — confirmed_hl_cohort.rds creation with first_hl_dx_date and first_hl_dx_source columns. Phase 56 consumes this artifact.

### Requirements
- `.planning/REQUIREMENTS.md` — CREF-04 (cancer summary in two versions: all cancers and post-HL cancers for comparison)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `confirmed_hl_cohort.rds`: Bridge artifact from Phase 55 with ID, first_hl_dx_date, first_hl_dx_source. Phase 56's primary input for temporal filtering.
- `cancer_summary.csv`: Patient-code level data with columns including ID, cancer_code, DX_DATE, cancer_category. Phase 56 joins this with confirmed_hl_cohort on ID, then filters DX_DATE > first_hl_dx_date.
- R/55's styled xlsx pattern: Dark header, freeze pane, number formatting, totals row. Reuse for output consistency in post-HL variant.
- R/55's category aggregation logic (Sections 9-12): Category-level and code-level summary with patient counts, code counts, rates. Reuse for post-HL aggregation.

### Established Patterns
- Script independence: Each script copies dependencies rather than importing from a shared module (PREFIX_MAP duplication accepted for v1.7)
- 1900 sentinel date nullification: Already handled in R/55's confirmed_hl_cohort.rds (sentinel dates nullified before saving)
- DuckDB as default backend: R/56 may not need DuckDB if it can work entirely from R/55's outputs (cancer_summary.csv + confirmed_hl_cohort.rds)
- Output file naming: _post_hl suffix for temporal variant (cancer_summary_post_hl.csv, cancer_summary_post_hl.xlsx, cancer_summary_table_post_hl.xlsx)

### Integration Points
- **Input:** `output/tables/cancer_summary.csv` (R/55 output, baseline)
- **Input:** `output/confirmed_hl_cohort.rds` (R/55 output, patient dates)
- **Output:** `output/tables/cancer_summary_post_hl.csv` (new, temporal-filtered patient-code level)
- **Output:** `output/tables/cancer_summary_post_hl.xlsx` (new, single flat sheet)
- **Output:** `output/tables/cancer_summary_table_post_hl.xlsx` (new, three-sheet workbook: EXPLORATORY Category Summary, EXPLORATORY Code Summary, Comparison)

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

*Phase: 56-temporal-filtering*
*Context gathered: 2026-05-22*
