---
phase: 82-non-informative-subcategories-explore-this-and-see-if-unhelpful-codes-are-in-the-same-encounter-as-a-helpful-code-and-from-there-just-count-the-helpful-code
plan: 01
subsystem: treatment_code_deduplication
tags:
  - exploration
  - data_quality
  - encounter_analysis
  - code_classification
dependency_graph:
  requires:
    - "Phase 81: CODE_SUBCATEGORY_MAP, category column, NA filtering"
    - "R/56: Drug grouping summary tables"
    - "R/28: treatment_episodes.rds with encounter_ids"
  provides:
    - "R/57: Encounter-level dx co-occurrence analysis script"
    - "Validation data for R/56 deduplication integration"
  affects:
    - "R/56: Production deduplication logic (Plan 02)"
    - "Table 1 (Sub-Category Summary) row counts"
tech_stack:
  added: []
  patterns:
    - "Encounter-level join propagation via episode_row"
    - "Pattern matching (str_detect) for code classification robustness"
    - "Flag-based preservation (dx_only) rather than exclusion"
key_files:
  created:
    - path: "R/57_explore_dx_deduplication.R"
      lines: 541
      purpose: "Standalone exploration script for encounter-level dx code co-occurrence analysis"
  modified: []
decisions:
  - id: "D-01"
    summary: "Non-informative codes = sub_category matching 'Encounter Dx' pattern"
  - id: "D-03"
    summary: "Co-occurrence check within same encounter_id (not entire episode)"
  - id: "D-05"
    summary: "Orphan dx-only encounters flagged (dx_only=TRUE), not excluded"
  - id: "D-10"
    summary: "Pattern matching (str_detect) rather than hardcoded lists for robustness"
metrics:
  duration_seconds: 179
  completed_date: "2026-06-03"
  tasks_completed: 1
  files_created: 1
  commits: 1
---

# Phase 82 Plan 01: Encounter-level Dx Code Co-Occurrence Analysis - Summary

**One-liner:** Standalone R/57 exploration script validates encounter-level deduplication logic for non-informative "Encounter Dx" codes via pattern matching and dx_only flagging.

## What Was Built

Created `R/57_explore_dx_deduplication.R` (541 lines) — a standalone exploration script that replicates R/56's data loading and sub-category classification, then adds encounter-level co-occurrence analysis to identify non-informative encounter diagnosis codes and check whether helpful/specific treatment codes exist in the same encounter.

**Key capabilities:**
1. **Data loading replication:** Loads treatment_episodes.rds, DuckDB DIAGNOSIS, and xlsx reference mappings using identical logic to R/56
2. **3-tier sub-category classification:** Applies same cascade as R/56 (xlsx → CODE_SUBCATEGORY_MAP → code-type fallback)
3. **Encounter-level granularity:** Joins episode_codes to episode_encounters via episode_row to get per-encounter treatment code rows
4. **Non-informative code detection:** Uses `str_detect(sub_category, "Encounter Dx")` pattern matching (not hardcoded lists) for robustness against upstream changes
5. **Co-occurrence check:** For each encounter, checks if ANY helpful (non-dx) code exists via `group_by(ENCOUNTERID) %>% summarise(has_helpful = any(!is_non_informative))`
6. **Orphan preservation:** Flags dx-only encounters with `dx_only=TRUE` rather than excluding them (per D-05), preserving data completeness
7. **Diagnostic output:** Console logs show partner rate (% dx codes with helpful partner), orphan counts, and Table 1 before/after deduplication impact

**Validation approach:**
- Exploration-first pattern: understand the data before modifying production R/56 code
- Quantifies deduplication impact on Table 1 row counts
- Identifies top 10 most common orphan sub-categories
- Per-category breakdown shows impact across Chemotherapy, Immunotherapy, Radiation, SCT

## Deviations from Plan

None - plan executed exactly as written.

**Auto-fixed issues:** None.

**Architectural decisions:** None required.

**Authentication gates:** None.

## Verification Results

All acceptance criteria met:

✅ R/57_explore_dx_deduplication.R exists with 541 lines (>= 150 required)
✅ Contains `str_detect(sub_category, "Encounter Dx")` pattern matching (2 occurrences)
✅ Contains `source("R/00_config.R")` for config loading
✅ Contains `source("R/utils/utils_assertions.R")` and `source("R/utils/utils_duckdb.R")`
✅ Contains `readRDS` for treatment_episodes.rds loading
✅ Contains 4 join operations (inner_join/left_join) for encounter-level propagation
✅ Contains 3 `group_by(ENCOUNTERID)` for per-encounter helpful code check
✅ Contains 14 occurrences of `dx_only` flag column
✅ Contains 7 occurrences of `has_helpful` column for co-occurrence detection
✅ Contains 8 occurrences of `table1_before`/`table1_after` for impact comparison
✅ Contains 10 SECTION headers matching `^# SECTION.*----` pattern
✅ Contains documentation header with Purpose, Inputs, Outputs, Dependencies, Requirements, Decision Traceability
✅ Contains 4 checkmate assertion calls (assert_rds_exists, assert_df_valid, assert_file_exists, warn_row_count)
✅ Does NOT contain hardcoded sub-category names (uses pattern matching)

**Script structure:**
- Section 1: Setup and configuration (logging, libraries, paths)
- Section 2: Load and validate input data (treatment_episodes.rds with checkmate assertions)
- Section 3: Build sub-category mappings from reference xlsx (chemo/rad/sct maps)
- Section 4: Prepare encounter-level data (episode_encounters split, DuckDB DIAGNOSIS cancer codes)
- Section 5: Build episode_codes with sub-category classification (3-tier cascade)
- Section 6: Encounter-level co-occurrence analysis (join to encounters, flag non-informative, check has_helpful, flag dx_only)
- Section 7: Diagnostic output (partner rate, orphan counts, Table 1 before/after impact)
- Section 8: Per-category breakdown (Chemotherapy/Immunotherapy/Radiation/SCT deduplication impact)
- Section 9: Orphan encounter detail (top 10 most common dx_only sub-categories)
- Section 10: Console summary

## Known Stubs

None. R/57 is an exploration script that produces console diagnostic output, not production data artifacts. All data flows are wired.

## Technical Notes

**Pattern matching robustness (D-10):**
The script uses `str_detect(sub_category, "Encounter Dx")` throughout, making it robust to:
- New treatment types added upstream (new dx code patterns)
- DRUG_GROUPINGS updates (new codes in config)
- CODE_SUBCATEGORY_MAP additions (new Tier 2 mappings)

This approach avoids brittle hardcoded lists like `c("Chemo Encounter Dx Code", "Radiation Encounter Dx Code", ...)` which would break if new sub-category names emerge.

**Encounter-level join propagation:**
The key technical pattern:
1. `episode_dx` has `episode_row` (1 per episode)
2. `episode_codes` inherits `episode_row` via unnest
3. `episode_encounters` has `episode_row + ENCOUNTERID` (many per episode)
4. Join gives encounter-level granularity: every code in an episode appears in every encounter of that episode

This enables the per-encounter helpful code check: `group_by(ENCOUNTERID) %>% summarise(has_helpful = any(!is_non_informative))`.

**dx_only flag semantics (D-05, D-06):**
- `dx_only = TRUE` means: this code instance is non-informative AND has no helpful partner in ANY of its encounters
- Preserved in output (not filtered) so downstream consumers can choose to include/exclude
- Provides flexibility: exploratory analyses may want to see dx-only encounters, production summaries may exclude them

**v2.0 code quality compliance (D-12):**
- styler-compatible formatting (tidyverse style)
- lintr-ready (no linting violations expected)
- checkmate assertions: 4 calls (assert_rds_exists, assert_df_valid, assert_file_exists, warn_row_count)
- Documentation header: 7 sections (Purpose, Inputs, Outputs, Dependencies, Requirements, Decision Traceability)
- Section structure: 10 sections with `# SECTION N: NAME ----` headers
- Console diagnostics: All output uses `message()` + `glue()` for interpolation

## Next Steps

**Plan 02: Integrate deduplication logic into R/56**
- Add encounter-level join to R/56 Section 5 (before Table 1 aggregation)
- Apply `str_detect(sub_category, "Encounter Dx")` pattern matching
- Add `has_helpful` per-encounter check
- Add `dx_only` flag column to Table 1
- Filter out non-informative codes with helpful partners
- Preserve orphan dx-only codes with flag
- Update smoke test (R/88) to validate deduplication

**Validation criteria for Plan 02:**
- Table 1 row count reduction matches R/57 diagnostic output
- dx_only flag appears in Table 1 output
- No hardcoded sub-category lists (pattern matching only)
- Smoke test validates presence of dx_only flag and absence of deduplicated codes

## Commits

- `34e75f1`: feat(82-01): create R/57 encounter-level dx code co-occurrence exploration script

## Self-Check

**Verification:**
```bash
# File exists
ls -lh R/57_explore_dx_deduplication.R
-rw-r--r-- 1 Owner None 26K Jun  3 19:42 R/57_explore_dx_deduplication.R

# Commit exists
git log --oneline | grep 34e75f1
34e75f1 feat(82-01): create R/57 encounter-level dx code co-occurrence exploration script

# Line count
wc -l R/57_explore_dx_deduplication.R
541 R/57_explore_dx_deduplication.R
```

**Result:** ✅ PASSED

All files created, commit exists, line count verified.
