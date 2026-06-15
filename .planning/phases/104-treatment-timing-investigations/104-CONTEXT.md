# Phase 104: Treatment Timing Investigations - Context

**Gathered:** 2026-06-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Flag and quantify all treatment episodes occurring before a patient's first confirmed HL diagnosis date, and produce a secondary malignancy table with 7-day gap criterion and population-based rate columns. Two standalone investigation scripts producing xlsx outputs. **Does NOT modify any existing scripts or outputs.**

</domain>

<decisions>
## Implementation Decisions

### Pre-Diagnosis Treatment Output (TIMING-01)
- **D-01:** Output as xlsx with two sheets: Sheet 1 = summary counts by treatment type (e.g., "42 chemo episodes before HL dx"), Sheet 2 = patient-level detail rows for clinical plausibility review.
- **D-02:** Include ALL 5 treatment types: Chemotherapy, Radiation, SCT, Immunotherapy, Proton Therapy. No focus/weighting on any single type.
- **D-03:** Detail rows include full code context: ID, treatment_type, episode_start, episode_stop, first_hl_dx_date, days_before_dx, triggering_codes, drug_names. Enables clinical review without cross-referencing R/26 output.

### Secondary Malignancy Table (TIMING-02)
- **D-04:** Separate standalone output file (`secondary_malignancy_table.xlsx`), NOT an enhancement of R/49's existing output. R/49 output remains unchanged.
- **D-05:** Population restricted to confirmed HL patients (7-day gap HL diagnosis confirmation from R/47's confirmed_hl_cohort.rds).
- **D-06:** Secondary malignancies also require 7-day confirmation — each non-HL cancer code needs 2+ diagnosis dates with 7+ day separation to count as a confirmed secondary malignancy.
- **D-07:** Pre/post HL split: secondary cancer diagnosed before vs after first HL dx date. Population-based percentage columns use confirmed HL cohort size as denominator.

### Script Structure
- **D-08:** Two separate standalone scripts: one for pre-diagnosis treatment flagging (TIMING-01), one for secondary malignancy table (TIMING-02). Different data flows, different outputs. Follows investigation script pattern from v3.1.
- **D-09:** Raw counts without HIPAA suppression — manual suppression before sharing (v3.1 convention).

### Claude's Discretion
- Script numbering (next available numbers in appropriate decade)
- Console logging structure and verbosity
- Summary sheet layout details (column ordering, row labels, formatting)
- Whether to include additional context in summary (e.g., percentage of total episodes that are pre-dx)
- R/88 smoke test section structure and check count for both new scripts

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Treatment Episodes Infrastructure
- `R/26_treatment_episodes.R` — Produces treatment_episodes.rds and treatment_episode_detail.rds with episode_start, episode_stop, treatment_type, triggering_codes, drug_names, encounter_ids. Source of pre-dx episode data.
- `R/25_treatment_episode_ids.R` — assign_episode_ids() function for 90-day gap windowing. Called by R/26.

### HL Diagnosis Date
- `R/47_cancer_summary_refined.R` — Produces confirmed_hl_cohort.rds with ID, first_hl_dx_date, first_hl_dx_source. Anchor point for pre/post temporal analysis.

### 7-Day Gap Criterion
- `R/45_cancer_summary.R` lines 266-302 — 7-day gap detection logic: `max(unique_dates) - min(unique_dates) >= 7`. Core pattern for secondary malignancy confirmation.
- `R/49_cancer_summary_pre_post.R` — Pre/post HL partitioning with 7-day gap filtering. Existing logic to adapt for secondary malignancy table.

### Cancer Code Classification
- `R/utils/utils_cancer.R` — classify_codes() 4-tier cascade and is_cancer_code() detection. Used to classify secondary malignancy codes into cancer site categories.
- `R/00_config.R` — CANCER_SITE_MAP (309 ICD-10 prefixes), ICD9_CANCER_SITE_MAP, TREATMENT_TYPES, ICD_CODES

### Data Access
- `R/utils/utils_duckdb.R` — get_pcornet_table() for DuckDB queries
- `R/utils/utils_dates.R` — parse_pcornet_date() for date parsing

### Meeting Notes Context
- `pecan_lymphoma_meeting_notes_combined.md` — G5 (radiation before HL dx), secondary malignancy table definition (columns K-N, population E/E3)

### Requirements
- `.planning/REQUIREMENTS.md` — TIMING-01, TIMING-02

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `treatment_episodes.rds`: Contains episode_start, episode_stop, treatment_type, triggering_codes, drug_names, encounter_ids per episode per patient. Direct input for TIMING-01.
- `confirmed_hl_cohort.rds`: Contains ID, first_hl_dx_date, first_hl_dx_source. Denominator for both investigations.
- `classify_codes()` (utils_cancer.R): Maps ICD-10/ICD-9 codes to cancer site categories. Reuse for secondary malignancy classification.
- `is_cancer_code()` (utils_cancer.R): Quick filter for cancer codes before classification.
- `openxlsx2` workbook pattern: wb_workbook() -> add_worksheet() -> add_data() -> styled headers -> save(). Established in R/29, R/30, R/53, R/57, R/58, R/59.
- `assert_rds_exists()`, `assert_df_valid()`: Standard input validation from R/00_config.R.

### Established Patterns
- Investigation script pattern (R/30, R/58, R/59): loads existing artifacts, self-contained analysis, produces xlsx output, no upstream modification.
- Console logging with glue: section headers, row counts, summary statistics at each step.
- Styled xlsx: dark header row (FF374151), white bold text, freeze panes, autofit column widths.
- Pre/post temporal split: R/49 lines 127-160 filter by DX_DATE < first_hl_dx_date vs >= first_hl_dx_date.

### Integration Points
- Reads: `cache/outputs/treatment_episodes.rds` (from R/26) — for TIMING-01
- Reads: `output/confirmed_hl_cohort.rds` (from R/47 via R/20) — for both investigations
- Reads: DuckDB DIAGNOSIS table (for TIMING-02 secondary malignancy queries)
- Writes: `output/pre_diagnosis_treatments.xlsx` (new file) — TIMING-01
- Writes: `output/secondary_malignancy_table.xlsx` (new file) — TIMING-02
- Does NOT modify R/26, R/47, R/49, or any existing RDS/xlsx files

</code_context>

<specifics>
## Specific Ideas

- Meeting note G5 specifically flags "Radiation occurring BEFORE HL diagnosis — review these cases" — while all 5 treatment types are included, radiation may dominate the pre-dx findings
- Secondary malignancy table must enforce dual 7-day confirmation: confirmed HL diagnosis AND confirmed secondary malignancy (each independently meeting the 7-day gap criterion)
- Percentage columns denominated on confirmed HL cohort population, not on subset with secondary malignancies

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 104-treatment-timing-investigations*
*Context gathered: 2026-06-15*
