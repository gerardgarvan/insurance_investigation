# Phase 103: Death Date Cross-Tab Summary - Context

**Gathered:** 2026-06-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce a clean, meeting-ready death date cross-tab summary table answering three team questions: (i) how many patients have a death date, (ii) of those how many have death as their last encounter, (iii) how many have encounters after their death date. Output as a standalone xlsx file (death_date_summary.xlsx) with HIPAA-aware formatting. New standalone R/59 script — does NOT modify R/29 or any existing outputs.

</domain>

<decisions>
## Implementation Decisions

### Script Approach
- **D-01:** New standalone script: R/59_death_date_summary.R. Self-contained investigation pattern (like R/30, R/58). Reads existing artifacts, produces its own output. Clean separation from first-line therapy logic in R/29.
- **D-02:** Reads validated_death_dates.rds (from R/53 Phase 59) and queries DuckDB ENCOUNTER table for last-encounter and post-death timing. Also reads confirmed_hl_cohort.rds for cohort denominator.

### Table Layout
- **D-03:** Cascading summary structure: rows flow top-to-bottom from total cohort -> patients with death date -> death is last encounter -> encounters after death. Each row shows count and percentage of cohort.
- **D-04:** First row = total confirmed HL cohort patients (from confirmed_hl_cohort.rds) as denominator. Makes percentages meaningful (e.g., "42 of 500 (8.4%) have a death date").
- **D-05:** Success criteria #2 requires counts match existing Phase 62 data (R/29 death analysis). Script should log comparison against R/29 metrics for verification.

### HIPAA Suppression
- **D-06:** Raw counts in xlsx output — NO automatic <11 suppression applied. HIPAA suppression applied manually before sharing/presenting. This allows internal review with exact numbers.

### Output
- **D-07:** Single xlsx file: death_date_summary.xlsx in output/ directory. Meeting-presentable formatting (styled headers, labeled rows, clear percentages).
- **D-08:** Success criteria #3 requires no additional formatting needed for team meeting presentation — styled xlsx with clear labels, readable column widths.

### Claude's Discretion
- Column ordering and exact row labels in the summary table
- Whether to include additional context rows (e.g., "patients with death date but no treatment records" from R/53)
- Console logging structure and verification messages
- R/88 smoke test validation section structure and check count
- Whether to add a second sheet with post-death encounter detail by ENC_TYPE (already computed in R/29)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Death Date Infrastructure
- `R/53_death_date_validation.R` — Produces validated_death_dates.rds with death_valid and post_death_activity flags. Sections 2-5 show death date loading, impossible death detection, and post-death activity flagging.
- `R/29_first_line_and_death_analysis.R` — Section 4 computes the same three metrics (n_with_death, n_death_is_last, n_post_death). Phase 103 counts MUST match these for verification (success criteria #2).

### Cohort Denominator
- `R/55_cancer_summary_refined.R` — Creates confirmed_hl_cohort.rds (ID, first_hl_dx_date, first_hl_dx_source). Used for total cohort denominator.

### Data Access
- `R/00_config.R` — CONFIG paths for output_dir, cache dirs
- `R/utils/utils_duckdb.R` — get_pcornet_table() for ENCOUNTER queries, open/close_pcornet_con()
- `R/utils/utils_dates.R` — parse_pcornet_date() for ADMIT_DATE parsing

### Validation
- `R/88_smoke_test_comprehensive.R` — Needs new validation section for R/59 structural checks

### Requirements
- `.planning/REQUIREMENTS.md` — DEATH-01

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `validated_death_dates.rds`: Contains ID, DEATH_DATE, DEATH_SOURCE, death_valid, post_death_activity. Already has the death-date-present and post-death-activity answers.
- `confirmed_hl_cohort.rds`: Contains cohort patient list for denominator.
- `R/29 Section 4` pattern: Last encounter date computation via DuckDB ENCOUNTER max(ADMIT_DATE) grouped by ID. Can reuse exact approach.
- `openxlsx2` workbook pattern: wb_workbook() -> add_worksheet() -> add_data() -> styled headers -> save(). Established in R/29, R/30, R/53, R/57, R/58.
- `assert_rds_exists()`, `assert_df_valid()`: Standard input validation from R/00_config.R.

### Established Patterns
- Investigation script pattern (R/30, R/58): loads data, self-contained analysis, produces xlsx output, no upstream modification.
- Console logging with glue: section headers, row counts, summary statistics at each step.
- Styled xlsx: dark header row (FF374151), white bold text, freeze panes, autofit column widths.

### Integration Points
- Reads: `cache/outputs/validated_death_dates.rds` (from R/53)
- Reads: `output/confirmed_hl_cohort.rds` (from R/55 via R/20)
- Reads: DuckDB ENCOUNTER table (for last encounter date comparison)
- Writes: `output/death_date_summary.xlsx` (new file, does not overwrite any existing output)
- Does NOT modify R/29, R/53, or any existing RDS/xlsx files

</code_context>

<specifics>
## Specific Ideas

- Success criteria #2 specifically calls out "verify counts match existing death date data quality analysis from Phase 62" — R/59 should log the three counts and compare against R/29's computation for parity.
- Success criteria #3 requires table be presentable "without additional formatting" — invest in clean xlsx styling (readable labels, proper column widths, number formatting with commas).
- The cascading structure should make it immediately obvious how the numbers nest: total cohort > has death date > death is last > post-death activity.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope.

</deferred>

---

*Phase: 103-death-date-cross-tab-summary*
*Context gathered: 2026-06-12*
