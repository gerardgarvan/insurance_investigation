# Phase 78: Episode Enhancement & Death Integration - Context

**Gathered:** 2026-06-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Add triggering code descriptions and drug group labels to treatment episodes in R/28, create a standalone death cause quality profiling script, and integrate cause of death into Gantt v2 output (R/52) with missingness awareness. No changes to cancer linkage logic (Phase 61) or upstream treatment episode construction.

</domain>

<decisions>
## Implementation Decisions

### Death Quality Profiling
- **D-01:** New standalone script (R/XX_death_cause_quality.R) for cause of death quality reporting. Follows established analysis script pattern (R/35, R/40).
- **D-02:** Stratifications: overall completeness + by AMC payer category + by partner site (AMS, UMI, FLM, VRT, UFH).
- **D-03:** Output format: console diagnostics (glue messages with counts/percentages) + multi-sheet xlsx for persistent review.
- **D-04:** Claude's Discretion on whether death quality report gates R/52's cause_of_death integration (hard gate at 40% vs soft warning). Choose based on what the quality data shows.

### Triggering Code Description Mapping
- **D-05:** `triggering_code_description` column in R/28 populated from `code_descriptions.rds` (human-readable drug/procedure names like "Doxorubicin HCl"). NOT from DRUG_GROUPINGS.
- **D-06:** Separate `drug_group` column in R/28 populated from DRUG_GROUPINGS (category labels: "Chemotherapy", "Radiation", "SCT", "Immunotherapy", "Supportive Care").
- **D-07:** Both columns use semicolon-separated values matching triggering_codes order. E.g., codes="J9000;J9040" -> descriptions="Doxorubicin;Bleomycin" -> groups="Chemotherapy;Chemotherapy".
- **D-08:** Unmapped codes get NA in both description and group columns per-code position.

### Cause of Death Integration
- **D-09:** `cause_of_death` column appended as last column in gantt_episodes_v2.csv (14 -> 15 columns) and gantt_detail_v2.csv (13 -> 14 columns). Non-breaking change.
- **D-10:** Missing/unmapped ICD-10 codes -> "Unknown or Unspecified" (matches DEATH_CAUSE_MAP Phase 75 D-05). Treatment rows (non-death) -> NA.
- **D-11:** >40% missingness flagged via console warning in R/52 + documented in quality report xlsx. No footnote embedded in CSV.
- **D-12:** Both gantt_episodes_v2.csv and gantt_detail_v2.csv get the cause_of_death column.

### Episode-Level Scope
- **D-13:** "Populated for all episodes" means adding the two new columns (triggering_code_description, drug_group) to R/28 output. No changes to linkage logic. Unlinked episodes keep NA.
- **D-14:** drug_group column propagates to Gantt v2 export (R/52). Gantt episodes CSV grows from 15 to 16 columns (cause_of_death + drug_group).

### Claude's Discretion
- D-04: Hard gate vs soft warning for >40% cause of death missingness
- Script number assignment for the new death cause quality script (must fit decade-based numbering)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Episode Classification
- `R/28_episode_classification.R` -- Primary target for triggering_code_description and drug_group columns. Currently 15 columns in treatment_episodes.rds.
- `R/00_config.R` -- DRUG_GROUPINGS named vector (454 codes, 5 categories, Section 5e from Phase 77). Also DEATH_CAUSE_MAP (ICD-10 3-char prefix mapping, Phase 75).

### Gantt Export
- `R/52_gantt_v2_export.R` -- Target for cause_of_death and drug_group columns. Currently 14 episode columns, 13 detail columns. Already reads validated_death_dates.rds.

### Data Sources
- `cache/outputs/code_descriptions.rds` -- Code-to-human-readable-name lookup. Source for triggering_code_description values.
- `cache/outputs/validated_death_dates.rds` -- Pre-validated death dates (Phase 59). Source for death row construction in R/52.

### Prior Phase Context
- `.planning/phases/75-configuration-extensions-nlphl-death-cause/75-CONTEXT.md` -- DEATH_CAUSE_MAP decisions (D-04 through D-07)
- `.planning/phases/77-cancer-classification-refinements/77-CONTEXT.md` -- DRUG_GROUPINGS decisions (D-05 through D-07)

### Quality Standards
- `R/88_smoke_test_comprehensive.R` -- Existing smoke test. New sections needed for death quality and R/28 column validation.

### Requirements
- `.planning/REQUIREMENTS.md` -- CANCER-03 (per-episode description), DEATH-01 (quality profiling), DEATH-02 (death in outputs), QUAL-01 (v2.0 standards)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `code_descriptions.rds`: Existing code-to-name lookup used by R/52 for triggering_code_descriptions. Reuse for R/28.
- `DRUG_GROUPINGS` (R/00_config.R): 454-entry named vector mapping treatment codes to 5 categories. New in Phase 77.
- `DEATH_CAUSE_MAP` (R/00_config.R): ICD-10 3-char prefix -> cause of death group. New in Phase 75.
- `validated_death_dates.rds`: Pre-validated death dates with impossible-death exclusions. Already loaded by R/52.
- `build_output_path()`: Output path construction utility.
- `assert_df_valid()`, `assert_rds_exists()`: Defensive validation helpers from Phase 72.

### Established Patterns
- Multi-sheet xlsx via openxlsx2 (R/28, R/35 pattern)
- Semicolon-separated multi-value fields in Gantt CSVs (Phase 64 cleanup convention)
- Console diagnostics via message() + glue() at each processing step
- Guard clauses for missing columns (R/52 lines 152-159: graceful fallback when Phase 61 not yet run)
- Section headers: `# SECTION N: NAME ----`

### Integration Points
- R/28 modifies treatment_episodes.rds in-place (readRDS -> enrich -> saveRDS)
- R/52 reads treatment_episodes.rds — new columns from R/28 flow through automatically
- Death quality script reads DuckDB DEATH table + validated_death_dates.rds
- Smoke test (R/88) needs new sections for death quality + R/28 column validation

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches following existing patterns.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 78-episode-enhancement-death-integration*
*Context gathered: 2026-06-03*
