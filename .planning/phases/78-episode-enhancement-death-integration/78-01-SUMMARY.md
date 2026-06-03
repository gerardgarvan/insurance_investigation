---
phase: 78-episode-enhancement-death-integration
plan: 01
subsystem: analysis-scripts, treatment-episodes
tags: [death-cause, quality-profiling, code-enrichment, drug-grouping]
requirements: [DEATH-01, CANCER-03, QUAL-01]
dependency_graph:
  requires: [Phase-75-DEATH_CAUSE_MAP, Phase-77-DRUG_GROUPINGS, Phase-48b-code_descriptions]
  provides: [death_cause_quality.xlsx, death_cause_quality_result.rds, treatment_episodes_17_columns]
  affects: [R/52_gantt_v2_export, Plan-78-02-gantt-export]
tech_stack:
  added: []
  patterns: [openxlsx2-multi-sheet, comma-separated-mapping, quality-gate-artifact]
key_files:
  created:
    - R/35_death_cause_quality.R
  modified:
    - R/28_episode_classification.R
decisions:
  - id: D-78-01
    summary: "DEATH_CAUSE field availability guard with death_cause_available flag"
    rationale: "PCORnet DEATH table schema varies; graceful degradation prevents pipeline failure"
  - id: D-78-05
    summary: "triggering_code_description from code_descriptions.rds (Phase 48b)"
    rationale: "Reuse existing code->description lookup built for Gantt exports"
  - id: D-78-06
    summary: "drug_group from DRUG_GROUPINGS named vector (Phase 77)"
    rationale: "Centralized groupings in R/00_config.R avoid runtime xlsx dependency"
  - id: D-78-07
    summary: "Comma-separated parallel mapping for multi-value fields"
    rationale: "triggering_codes at R/28 uses commas (pre-Phase 64 semicolon cleanup)"
  - id: D-78-08
    summary: "Unmapped codes get NA per-code position in both new columns"
    rationale: "Parallel structure preserves 1:1 code-to-metadata correspondence"
metrics:
  duration_minutes: 3
  tasks_completed: 2
  files_created: 1
  files_modified: 1
  commits: 2
  lines_added: 470
---

# Phase 78 Plan 01: Episode Enhancement & Death Integration - Foundation

**One-liner:** Death cause quality profiling with multi-sheet xlsx + treatment episodes enriched with triggering code descriptions and drug group categories

## What Was Built

### R/35_death_cause_quality.R (New)
Standalone death cause data quality profiling script producing console diagnostics and multi-sheet Excel workbook.

**Key features:**
- DEATH_CAUSE field availability guard (handles missing field gracefully)
- Overall completeness: n_deaths, n_with_cause, pct_complete, missingness_rate
- Stratification by AMC payer category (extracted from treatment_episodes.rds)
- Stratification by partner site (3-char ID prefix: AMS, UMI, FLM, VRT, UFH)
- ICD-10 prefix mapping via DEATH_CAUSE_MAP (100+ categories)
- Cause category distribution for coded deaths
- Missingness threshold checks (D-04 soft warning approach):
  - ≤40%: "Proceed with integration"
  - 40-60%: "Document limitations"
  - >60%: "SKIP integration"
- Multi-sheet xlsx output (5 sheets: Overall Completeness, By Payer Category, By Partner Site, Cause Category Distribution, Recommendations)
- Quality decision artifact: `death_cause_quality_result.rds` for Plan 02 consumption

**Pattern:** Follows R/35 Phase 34 analysis script pattern (section structure, openxlsx2 styling)

**Outputs:**
- `output/death_cause_quality.xlsx` (5-sheet workbook)
- `cache/outputs/death_cause_quality_result.rds` (quality gate artifact)

### R/28_episode_classification.R (Modified)
Added two new columns to treatment_episodes.rds via new SECTION 5B.

**New columns (15→17 total):**
1. **triggering_code_description**: Comma-separated human-readable code descriptions
   - Source: `code_descriptions.rds` (Phase 48b)
   - Mapping: 1:1 parallel to `triggering_codes` field
   - Unmapped codes: NA per-code position (D-78-08)

2. **drug_group**: Comma-separated category labels
   - Source: `DRUG_GROUPINGS` named vector (Phase 77, R/00_config.R)
   - Categories: Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care
   - Mapping: 1:1 parallel to `triggering_codes` field
   - Unmapped codes: NA per-code position (D-78-08)

**Helper functions:**
- `lookup_description(code)`: Single code → description (from code_descriptions.rds)
- `lookup_drug_group(code)`: Single code → drug group (from DRUG_GROUPINGS)
- `map_codes_to_descriptions(codes_str)`: Comma-separated codes → comma-separated descriptions
- `map_codes_to_drug_groups(codes_str)`: Comma-separated codes → comma-separated groups

**Critical detail:** triggering_codes uses commas at R/28 stage (pre-Phase 64 semicolon cleanup for Gantt exports). Helpers use comma split.

**Outputs:**
- `cache/outputs/treatment_episodes.rds` (now 17 columns, was 15)

## Deviations from Plan

None. Plan executed exactly as written.

## Files Created
- `R/35_death_cause_quality.R` (390 lines, 8 SECTION headers)

## Files Modified
- `R/28_episode_classification.R` (+80 lines: new SECTION 5B + updated header/select/stopifnot)

## Testing & Verification

### Automated Checks
```bash
# R/35 line count
wc -l R/35_death_cause_quality.R
# Output: 390 R/35_death_cause_quality.R

# R/35 section count
grep -c "SECTION" R/35_death_cause_quality.R
# Output: 8

# R/35 key patterns
grep -c "library(openxlsx2)" R/35_death_cause_quality.R  # 1
grep -c "DEATH_CAUSE_MAP" R/35_death_cause_quality.R      # 5
grep -c "death_cause_available" R/35_death_cause_quality.R # 11

# R/28 new columns
grep -c "triggering_code_description" R/28_episode_classification.R  # 8
grep -c "drug_group" R/28_episode_classification.R                   # 12
grep -c "DRUG_GROUPINGS" R/28_episode_classification.R               # 5
grep -c "SECTION 5B" R/28_episode_classification.R                   # 1
```

### Manual Verification
✓ R/35 has DEATH_CAUSE field availability guard (`if (!"DEATH_CAUSE" %in% names(death_raw))`)
✓ R/35 has 5-sheet xlsx workbook creation
✓ R/35 saves quality decision artifact (death_cause_quality_result.rds)
✓ R/28 new columns in final select() (17 total)
✓ R/28 stopifnot includes new columns
✓ R/28 helper functions use comma separator (triggering_codes format at R/28 stage)
✓ R/28 header updated with Phase 78 decision traceability

## Known Stubs

None. All functionality is fully implemented.

## Requirements Satisfied

- **DEATH-01**: Death cause quality profiling with payer/site stratification → R/35_death_cause_quality.R
- **CANCER-03**: Per-episode code descriptions and drug groups → R/28 new columns (triggering_code_description, drug_group)
- **QUAL-01**: Quality gates before data integration → death_cause_quality_result.rds artifact

## Integration Points

### For Plan 78-02 (Gantt Export Enhancement)
- **Input:** `cache/outputs/death_cause_quality_result.rds`
  - Read `missingness_rate` and `recommendation` to decide whether to add cause_of_death column to Gantt exports
- **Input:** `cache/outputs/treatment_episodes.rds` (now 17 columns)
  - New columns `triggering_code_description` and `drug_group` ready for Gantt export inclusion

### Downstream Impact
- **R/52_gantt_v2_export.R**: Will consume new columns in Plan 78-02
- **output/gantt_episodes_v2.csv**: Schema will grow from 14 to 16 columns (add triggering_code_description, drug_group)

## Commits

1. **1345a7d** - `feat(78-01): create death cause quality profiling script`
   - R/35_death_cause_quality.R (390 lines)
   - Multi-sheet xlsx + quality decision artifact

2. **9c5ab58** - `feat(78-01): add triggering_code_description and drug_group to R/28`
   - R/28_episode_classification.R (+80 lines)
   - New SECTION 5B with 4 helper functions
   - 15→17 column expansion

## Self-Check: PASSED

### Files Created
✓ `R/35_death_cause_quality.R` exists (390 lines)

### Files Modified
✓ `R/28_episode_classification.R` modified (+80 lines, SECTION 5B added)

### Commits Verified
```bash
git log --oneline | grep -E "(1345a7d|9c5ab58)"
```
✓ 1345a7d feat(78-01): create death cause quality profiling script
✓ 9c5ab58 feat(78-01): add triggering_code_description and drug_group to R/28

## Notes

### DEATH_CAUSE Field Availability
R/35 gracefully handles missing DEATH_CAUSE field via `death_cause_available` flag. If field is absent:
- Sets `missingness_rate = 100%`
- Sets `recommendation = "SKIP cause of death integration"`
- Saves empty RDS artifact with availability flag
- Plan 78-02 can check flag and skip cause_of_death column integration

### Triggering Codes Separator
Critical discovery: `triggering_codes` uses **commas** at R/28 stage (R/26 line 412: `collapse = ","`). Phase 64 converts to semicolons during Gantt export cleanup. R/28 SECTION 5B correctly uses comma split for code_descriptions and drug_group mapping.

### Parallel Mapping Behavior
Unmapped codes get `NA` per D-78-08, preserving parallel structure:
- Input: `"J9000,UNKNOWN_CODE,J9040"`
- triggering_code_description: `"Doxorubicin HCl,NA,Bleomycin sulfate"`
- drug_group: `"Chemotherapy,NA,Chemotherapy"`

This maintains 1:1 correspondence for downstream processing.

---

**Duration:** 3 minutes
**Status:** Complete — all tasks executed, committed, verified
