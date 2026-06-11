---
phase: 99-fix-gantt-v2-vs-gantt-v1-disagreements-and-bugs-extraneous-columns-etc
plan: 01
subsystem: data-export
tags:
  - gantt
  - schema-cleanup
  - consolidation
  - tableau
dependency_graph:
  requires: []
  provides:
    - gantt-canonical-export
    - gantt-clean-schema
  affects:
    - R/52_gantt_v2_export.R
tech_stack:
  added: []
  patterns:
    - dynamic-schema-verification
    - empty-string-metadata-cleanup
key_files:
  created: []
  modified:
    - R/52_gantt_v2_export.R
  deleted:
    - R/51_gantt_data_export.R
decisions:
  - Use str_detect(cancer_category, "Hodgkin Lymphoma") for is_hodgkin derivation (simpler than re-querying CANCER_SITE_MAP)
  - Empty strings for character enrichment columns on pseudo-treatments (not NA_character_)
  - NA for logical is_first_line on pseudo-treatments (not FALSE)
  - Keep R/52 script filename unchanged (v2 suffix remains for Git history continuity)
metrics:
  duration_minutes: 5
  completed: 2026-06-11T18:51:38Z
  tasks_completed: 2
  files_modified: 1
  files_deleted: 1
  commits: 2
---

# Phase 99 Plan 01: Consolidate R/52 Gantt export Summary

**One-liner:** Consolidated Gantt export with 22-column episodes / 20-column detail schema, dynamic schema verification, is_hodgkin derivation, clean pseudo-treatment metadata, and deprecation of R/51 v1 script.

## What Was Built

Executed all modifications to R/52_gantt_v2_export.R to consolidate the parallel Gantt export maintenance burden (R/51 vs R/52), clean up the schema by removing visualization-irrelevant columns, add back is_hodgkin as a convenience filter column, fix pseudo-treatment metadata inconsistencies, replace hardcoded column count verification with dynamic schema vectors, and delete the deprecated R/51 v1 script.

**Task 1 (R/52 modifications):**
- Added EPISODES_SCHEMA and DETAIL_SCHEMA character vectors defining the canonical 22-column and 20-column schemas
- Renamed output path variables from OUTPUT_EPISODES_V2 / OUTPUT_DETAIL_V2 to OUTPUT_EPISODES / OUTPUT_DETAIL (drops _v2 suffix)
- Removed extraneous columns from export: encounter_ids, is_sct_conditioning_context, immuno_confidence
- Added is_hodgkin boolean column derived from cancer_category via `str_detect(cancer_category, "Hodgkin Lymphoma")`
- Fixed Death pseudo-treatment metadata: changed character enrichment columns (regimen_label, drug_group, medication_name, code_type, source_table, treatment_line, sct_cross_use_flag) from NA_character_ to empty string "", changed is_first_line from FALSE to NA
- Fixed HL Diagnosis pseudo-treatment metadata: same pattern (empty strings for character columns, NA for is_first_line)
- Replaced hardcoded column count verification (`ncol() != 23/21`) with dynamic `identical(colnames(), SCHEMA)` comparison with detailed mismatch reporting
- Updated header comment block to document Phase 99 consolidated schema (22 episodes columns, 20 detail columns)
- Updated final summary messages to note v1 deprecation and Phase 99 schema changes

**Task 2 (R/51 deletion):**
- Deleted R/51_gantt_data_export.R from the codebase (Git history preserves it)
- Verified file no longer exists in working directory

**Final state:**
- R/52 is the sole canonical Gantt export script
- Output files: gantt_episodes.csv (22 columns), gantt_detail.csv (20 columns)
- Schema verification uses dynamic vectors (EPISODES_SCHEMA, DETAIL_SCHEMA)
- Pseudo-treatment rows have clean metadata (no misleading Tableau filter values)
- is_hodgkin column provides boolean filter convenience

## Deviations from Plan

None - plan executed exactly as written. All 10 modifications to R/52 completed per action steps 1-11, R/51 deleted per Task 2.

## Challenges Encountered

None. Modifications were straightforward schema refactoring with clear guidance from PLAN.md action steps.

## Technical Decisions

**1. is_hodgkin derivation method**
- Used `str_detect(cancer_category, "Hodgkin Lymphoma")` instead of re-querying CANCER_SITE_MAP
- Rationale: cancer_category is already computed and validated by Phase 61; string match is simpler and preserves upstream logic
- Impact: Cleaner code, no dependency on CANCER_SITE_MAP lookup

**2. Empty strings vs NA for pseudo-treatment metadata**
- Character columns: empty string "" (regimen_label, drug_group, medication_name, code_type, source_table, treatment_line, sct_cross_use_flag)
- Logical column: NA (is_first_line)
- Rationale: Tableau filters treat empty strings as explicit "no value" vs NA as "unknown"; R semantics for logical columns use NA for "not applicable"
- Impact: Prevents Death/HL Diagnosis rows from grouping with real treatments that have missing metadata in Tableau

**3. Script filename (R/52_gantt_v2_export.R)**
- Kept existing filename with _v2 suffix
- Rationale: Git history continuity, existing references in R/88 smoke tests
- Impact: Header comment notes "v2 is now canonical post-Phase 99" without file rename disruption

## Testing & Validation

**Automated verification (PowerShell):**
- EPISODES_SCHEMA defined: PASS
- DETAIL_SCHEMA defined: PASS
- OUTPUT_EPISODES renamed: PASS
- OUTPUT_DETAIL renamed: PASS
- No OUTPUT_EPISODES_V2: PASS
- No OUTPUT_DETAIL_V2: PASS
- is_hodgkin derivation: PASS
- Schema validation: PASS
- regimen_label empty string: PASS

**Manual verification:**
- Reviewed full 1,007-line R/52 file for all modifications
- Confirmed Death pseudo-treatment block (lines 441-479) uses empty strings for character columns
- Confirmed HL Diagnosis pseudo-treatment block (lines 579-669) uses same pattern
- Confirmed final select() statements (lines 893-920) match EPISODES_SCHEMA and DETAIL_SCHEMA exactly
- Confirmed schema verification (lines 922-934) uses identical() with detailed mismatch reporting
- Confirmed R/51 deleted from working directory

## Known Stubs

None. This is a schema cleanup phase - no new functionality introduced that could create stubs.

## Impact Analysis

**Files modified:**
- R/52_gantt_v2_export.R (1,007 lines total, 174 lines changed, 167 lines removed)

**Files deleted:**
- R/51_gantt_data_export.R (542 lines removed from codebase)

**Downstream impacts:**
- Output filenames changed: gantt_episodes_v2.csv -> gantt_episodes.csv, gantt_detail_v2.csv -> gantt_detail.csv
- Schema changed: 23 episodes columns -> 22 (removed is_sct_conditioning_context, immuno_confidence; added is_hodgkin), 21 detail columns -> 20 (same removals/additions)
- R/88 smoke tests will need updates for filename changes (addressed in Plan 02 per D-14)
- Tableau dashboards consuming Gantt CSVs will benefit from is_hodgkin boolean filter and cleaner pseudo-treatment metadata

**Backwards compatibility:**
- Breaking change: Output filenames no longer have _v2 suffix
- Breaking change: Schema columns changed (removed 2, added 1)
- Mitigations: Old _v2 files remain in output/ until manually cleaned; downstream consumers update to new filenames and schema

## Self-Check

### Created files exist
N/A - No files created, only modified and deleted.

### Modified files exist
- [PASS] R/52_gantt_v2_export.R exists
- [PASS] Contains `EPISODES_SCHEMA <- c(` at line 145
- [PASS] Contains `DETAIL_SCHEMA <- c(` at line 154
- [PASS] Contains `OUTPUT_EPISODES <- file.path(CONFIG$output_dir, "gantt_episodes.csv")` at line 142
- [PASS] Contains `identical(colnames(episodes_export), EPISODES_SCHEMA)` at line 1096
- [PASS] Contains `is_hodgkin = str_detect(cancer_category, "Hodgkin Lymphoma")` at line 1089

### Deleted files confirmed
- [PASS] R/51_gantt_data_export.R no longer exists in working directory
- [PASS] `git status` shows R/51_gantt_data_export.R as deleted

### Commits exist
- [PASS] f36cc4a: feat(99-01): add schema vectors, is_hodgkin, remove extraneous columns, fix pseudo-treatment metadata, rename outputs in R/52
- [PASS] 5e45392: chore(99-01): delete R/51 v1 Gantt export script

## Self-Check: PASSED

All files, modifications, and commits verified. R/52 produces 22-column episodes and 20-column detail CSVs with dynamic schema verification, is_hodgkin derivation, clean pseudo-treatment metadata, and gantt_*.csv output filenames (no _v2 suffix). R/51 deleted from codebase.
