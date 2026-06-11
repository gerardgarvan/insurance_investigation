# Phase 99: Fix gantt_v2 vs gantt_v1 disagreements and bugs, extraneous columns - Context

**Gathered:** 2026-06-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Consolidate two parallel Gantt export scripts (R/51 v1 and R/52 v2) into a single canonical export. Delete v1, clean up v2's schema (add is_hodgkin, remove immunotherapy columns, rename output files), fix pseudo-treatment metadata inconsistencies, replace hardcoded column count verification with dynamic schema, and update all downstream references.

</domain>

<decisions>
## Implementation Decisions

### V1 Disposition
- **D-01:** Deprecate v1 entirely. Delete R/51_gantt_data_export.R from the codebase. R/52 becomes the single canonical Gantt export script. Git history preserves R/51 if ever needed.

### Column Reconciliation
- **D-02:** Keep semicolons for multi-value field separators (triggering_codes, drug_names, triggering_code_descriptions). Phase 64 standard — avoids CSV parsing ambiguity.
- **D-03:** Keep v2 cleanup behavior: empty strings instead of NA, "Unlinked" for blank cancer_category. Better for Tableau filters.
- **D-04:** Keep simplified drug names (Phase 64 BRAND_TO_GENERIC mapping). Full RxNorm descriptions available in treatment_episodes.rds for analysis.
- **D-05:** Rename output files from gantt_episodes_v2.csv / gantt_detail_v2.csv to gantt_episodes.csv / gantt_detail.csv. Drop the _v2 suffix since v2 is now canonical.

### Extraneous Columns
- **D-06:** Leave out encounter_ids (episodes) and ENCOUNTERID (detail) columns. Too noisy for Tableau visualization; available in treatment_episodes.rds.
- **D-07:** Add is_hodgkin back as a convenience boolean column derived from cancer_category. Easier to filter on TRUE/FALSE than matching a string.
- **D-08:** Keep clinical context columns: regimen_label, is_first_line.
- **D-09:** Keep death/drug info columns: drug_group, cause_of_death.
- **D-10:** Keep source metadata columns: medication_name, code_type, source_table, treatment_line, sct_cross_use_flag.
- **D-11:** Remove immunotherapy context columns from Gantt export: is_sct_conditioning_context, immuno_confidence. These are specialized analysis flags, not visualization-relevant.

### Bug Fixes
- **D-12:** Clean up pseudo-treatment row metadata. For Death and HL Diagnosis rows, set enrichment columns (regimen_label, is_first_line, drug_group, treatment_line, sct_cross_use_flag, etc.) to empty string rather than NA or FALSE. Prevents misleading Tableau filter results.
- **D-13:** Replace hardcoded column count verification (currently expects 23 episodes, 21 detail) with dynamic verification from a schema definition vector at top of script. Column names defined once, verification checks against that definition.
- **D-14:** Update all downstream references from gantt_*_v2 patterns to gantt_* across the codebase (R/88 smoke tests, any other scripts referencing v2 filenames).
- **D-15:** Create R/99 validation script following established pattern (R/95, R/96) that verifies: column names match schema, row counts preserved, separator consistency, NA handling, is_hodgkin derivation correctness.

### Claude's Discretion
- Column ordering in the final schema (logical grouping preferred)
- R/99 validation script check count and granularity
- How is_hodgkin is derived (cancer_category string match or lookup)
- Whether R/52 gets renamed to just R/52_gantt_export.R (drop _v2 from script name too)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Gantt Export Scripts
- `R/51_gantt_data_export.R` -- V1 generator (543 lines) -- TO BE DELETED. Read to understand what v1 provided that v2 must cover.
- `R/52_gantt_v2_export.R` -- V2 generator (1,007 lines) -- PRIMARY target for modification. Contains Phase 64 cleanup, Phase 78 death cause mapping, Phase 92/93 metadata columns.

### Validation & Smoke Tests
- `R/88_smoke_test_validation.R` -- Smoke test script with gantt-related sections. Must be updated for filename changes (gantt_*_v2 -> gantt_*).

### Data Sources
- `R/00_config.R` -- LOOKUP_TABLES including CANCER_SITE_MAP (for is_hodgkin derivation), BRAND_TO_GENERIC (for drug name simplification)

### Prior Phase Patterns
- `R/95_validate_dt_infrastructure.R` -- Validation script pattern (45+ checks) to follow for R/99
- `R/96_validate_payer_dt.R` -- Validation script pattern (41 checks) to follow for R/99

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phase 64 cleanup logic in R/52 (multi-value dedup, drug simplification, NA handling) -- already implemented, just needs column trimming
- Validation script pattern from R/95 and R/96 -- numbered check sections with pass/fail reporting
- CANCER_SITE_MAP in R/00_config.R -- can derive is_hodgkin from cancer_category matching

### Established Patterns
- Column count verification at end of R/52 (lines ~925-933) -- will be replaced with dynamic schema vector
- Pseudo-treatment row injection (Death, HL Diagnosis) in R/52 -- needs metadata cleanup per D-12
- Output path pattern: `output/gantt_*.csv` using here() or configured paths

### Integration Points
- R/88 smoke tests reference gantt_*_v2.csv filenames -- must be updated per D-14
- Output directory: `output/` contains both v1 and v2 files -- v1 files should be cleaned up
- treatment_episodes.rds -- primary data source for R/52, contains all enrichment columns from Phases 60-93

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- open to standard approaches. Key constraint is that the final schema should be clean for Tableau consumption with logical column grouping.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope.

</deferred>

---

*Phase: 99-fix-gantt-v2-vs-gantt-v1-disagreements-and-bugs-extraneous-columns-etc*
*Context gathered: 2026-06-11*
