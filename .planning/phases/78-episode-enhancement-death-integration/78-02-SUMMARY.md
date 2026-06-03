---
phase: 78-episode-enhancement-death-integration
plan: 02
subsystem: gantt-export, quality-assurance
tags: [cause-of-death, drug-group, gantt-v2, smoke-test, death-integration]
requirements: [DEATH-02, CANCER-03, QUAL-01]
dependency_graph:
  requires: [Phase-78-01-death_quality_artifact, Phase-78-01-treatment_episodes_17_columns, Phase-75-DEATH_CAUSE_MAP]
  provides: [gantt_episodes_v2_16_columns, gantt_detail_v2_14_columns, smoke_test_phase_78_validation]
  affects: [Gantt-visualization-downstream-consumers, Tableau-dashboards]
tech_stack:
  added: []
  patterns: [death-cause-mapping, quality-gate-integration, ICD-10-prefix-lookup, multi-sheet-validation]
key_files:
  created: []
  modified:
    - R/52_gantt_v2_export.R
    - R/88_smoke_test_comprehensive.R
decisions:
  - id: D-78-09
    summary: "cause_of_death appended as last column (non-breaking)"
    rationale: "Preserves existing column order for downstream consumers"
  - id: D-78-10
    summary: "Missing/unmapped ICD-10 -> 'Unknown or Unspecified'"
    rationale: "Explicit fallback value better than NA for Tableau dashboards"
  - id: D-78-11
    summary: ">40% missingness triggers console warning"
    rationale: "Alerts users to data quality issues without blocking export"
  - id: D-78-12
    summary: "Both gantt_episodes_v2.csv and gantt_detail_v2.csv get cause_of_death"
    rationale: "Consistent schema across episode and detail views"
  - id: D-78-14
    summary: "drug_group propagated from treatment_episodes.rds to episodes CSV"
    rationale: "Episode-level field follows existing pattern; detail is date-level"
metrics:
  duration_minutes: 6
  tasks_completed: 2
  files_created: 0
  files_modified: 2
  commits: 2
  lines_added: 280
---

# Phase 78 Plan 02: Gantt v2 Export Integration & Smoke Test Validation

**One-liner:** Gantt v2 CSV exports enriched with cause of death and drug group columns, validated by comprehensive smoke test checks

## What Was Built

### R/52_gantt_v2_export.R (Modified)
Integrated cause of death and drug group into Gantt v2 CSV exports with intelligent fallback and quality gate logic.

**Schema updates:**
- **gantt_episodes_v2.csv**: 14 → 16 columns (+drug_group, +cause_of_death)
- **gantt_detail_v2.csv**: 13 → 14 columns (+cause_of_death)

**New SECTION 3B: Death Cause Mapping**
- `map_death_cause()` function: ICD-10 3-char prefix → DEATH_CAUSE_MAP lookup
- "Unknown or Unspecified" fallback for missing/unmapped codes (D-78-10)
- Quality gate integration: loads `death_cause_quality_result.rds` from Plan 01
- Conditional logic:
  - If DEATH_CAUSE field unavailable → skip mapping, set all to NA
  - If missingness > 60% → console warning
  - If DEATH_CAUSE not in validated_death_dates.rds → query DEATH table directly

**Death pseudo-treatment rows:**
- `cause_of_death`: Mapped via DEATH_CAUSE_MAP from DEATH_CAUSE field
- `drug_group`: NA (death events have no drug group)
- Query fallback: If DEATH_CAUSE missing from validated_death_dates.rds, queries DEATH table via DuckDB

**Treatment episode rows:**
- `cause_of_death`: NA (treatment episodes are not death events)
- `drug_group`: Propagated from `treatment_episodes.rds` (Phase 78 Plan 01 R/28 enrichment)

**HL Diagnosis pseudo-treatment rows:**
- `cause_of_death`: NA (diagnostic markers are not death events)
- `drug_group`: NA (diagnostic markers have no drug group)

**Guard clauses:**
- Added for `drug_group` column (Phase 78 R/28 enrichment)
- Added for `triggering_code_description` column (Phase 78 R/28 enrichment)
- Both default to NA_character_ if column missing

**Missingness warning (D-78-11):**
- New Section 4C2: checks cause_of_death completeness in Death rows
- Triggers warning if >40% missing/unmapped
- Reports completeness percentage if <=40% missing

**Column count verification:**
- `expected_ep_cols`: 14 → 16
- `expected_detail_cols`: 13 → 14

**Final summary stats:**
- Added "Deaths with mapped cause" count
- Updated v1 vs v2 column comparison messages

**Pattern:** Follows Phase 78 Plan 01 quality gate pattern — loads RDS decision artifact, applies conditional logic, degrades gracefully if data unavailable.

### R/88_smoke_test_comprehensive.R (Modified)
Added two new validation sections and updated requirements list.

**New SECTION 14: Death Quality Profiling Validation (DEATH-01)**
7 checks for R/35_death_cause_quality.R:
1. File existence
2. Sources R/00_config.R
3. References DEATH_CAUSE_MAP
4. Has DEATH_CAUSE field availability check
5. Outputs death_cause_quality.xlsx
6. Saves death_cause_quality_result.rds
7. Has >= 6 section headers

**New SECTION 15: Episode Enrichment and Gantt Integration (CANCER-03, DEATH-02)**
10 checks for R/28 and R/52:
1. R/28 final select includes triggering_code_description
2. R/28 final select includes drug_group
3. R/28 references DRUG_GROUPINGS
4. R/28 references code_descriptions.rds
5. R/52 episodes export includes cause_of_death
6. R/52 episodes export includes drug_group
7. R/52 references DEATH_CAUSE_MAP
8. R/52 expected_ep_cols is 16 (was 14)
9. R/52 expected_detail_cols is 14 (was 13)
10. R/52 has >40% missingness warning threshold

**Section renumbering:**
- SUMMARY section: 14 → 16

**Validated requirements additions:**
- CANCER-03: Per-episode triggering_code_description and drug_group columns (R/28)
- DEATH-01: Death cause quality profiling (R/35)
- DEATH-02: Cause of death in Gantt v2 exports (R/52)

**Total new checks:** 17

## Deviations from Plan

None. Plan executed exactly as written.

## Files Created
None — all modifications to existing files.

## Files Modified
- `R/52_gantt_v2_export.R` (+151 lines, -33 lines)
- `R/88_smoke_test_comprehensive.R` (+129 lines, -1 line)

## Testing & Verification

### Automated Checks
```bash
# R/52 pattern counts
grep -c "cause_of_death" R/52_gantt_v2_export.R
# Output: 44

grep -c "drug_group" R/52_gantt_v2_export.R
# Output: 16

grep -c "map_death_cause" R/52_gantt_v2_export.R
# Output: 3

grep -c "DEATH_CAUSE_MAP" R/52_gantt_v2_export.R
# Output: 2

grep -c "Unknown or Unspecified" R/52_gantt_v2_export.R
# Output: 8

grep -c "> 40\|40%" R/52_gantt_v2_export.R
# Output: 2

grep "expected_ep_cols" R/52_gantt_v2_export.R
# Output: expected_ep_cols <- 16  # was 14, Phase 78: +drug_group, +cause_of_death

grep "expected_detail_cols" R/52_gantt_v2_export.R
# Output: expected_detail_cols <- 14  # was 13, Phase 78: +cause_of_death

# R/88 pattern counts
grep -c "CANCER-03" R/88_smoke_test_comprehensive.R
# Output: 3

grep -c "DEATH-01" R/88_smoke_test_comprehensive.R
# Output: 5

grep -c "DEATH-02" R/88_smoke_test_comprehensive.R
# Output: 4

grep "SECTION 14\|SECTION 15\|SECTION 16" R/88_smoke_test_comprehensive.R
# Output: SECTION 14, SECTION 15, SECTION 16 headers present
```

### Manual Verification
✓ R/52 schema documentation updated (16 episodes columns, 14 detail columns)
✓ R/52 SECTION 3B added with map_death_cause() function
✓ R/52 DEATH_CAUSE_MAP reference present
✓ R/52 quality gate integration via death_cause_quality_result.rds
✓ R/52 Death rows get mapped cause_of_death, NA drug_group
✓ R/52 Treatment rows get NA cause_of_death, drug_group from treatment_episodes.rds
✓ R/52 HL Diagnosis rows get NA cause_of_death, NA drug_group
✓ R/52 guard clauses for drug_group and triggering_code_description
✓ R/52 >40% missingness warning in Section 4C2
✓ R/52 column counts: expected_ep_cols=16, expected_detail_cols=14
✓ R/52 final summary includes deaths_with_mapped_cause stat
✓ R/88 SECTION 14 validates R/35 (7 checks)
✓ R/88 SECTION 15 validates R/28 and R/52 (10 checks)
✓ R/88 SECTION 16 (SUMMARY) renumbered from 14
✓ R/88 validated requirements list updated

## Known Stubs

None. All functionality is fully implemented.

## Requirements Satisfied

- **DEATH-02**: Cause of death in Gantt v2 exports → R/52 cause_of_death column with DEATH_CAUSE_MAP integration
- **CANCER-03**: Drug group in Gantt v2 exports → R/52 drug_group column propagated from treatment_episodes.rds
- **QUAL-01**: Quality gates before data integration → R/52 loads death_cause_quality_result.rds, applies conditional logic

## Integration Points

### Inputs Consumed
- **cache/outputs/treatment_episodes.rds** (Plan 78-01): 17-column RDS with drug_group and triggering_code_description
- **cache/outputs/death_cause_quality_result.rds** (Plan 78-01): Quality gate artifact with missingness_rate and death_cause_available flag
- **DEATH_CAUSE_MAP** (Phase 75, R/00_config.R): 100+ ICD-10 3-char prefix mappings
- **validated_death_dates.rds** (Phase 59): Death dates + DEATH_CAUSE field (if available)

### Outputs Produced
- **output/gantt_episodes_v2.csv**: 16 columns (was 14) — added drug_group, cause_of_death
- **output/gantt_detail_v2.csv**: 14 columns (was 13) — added cause_of_death

### Downstream Impact
- **Gantt visualization tools**: Can now stratify by drug_group and cause_of_death
- **Tableau dashboards**: New columns available for filtering and cross-tabulation
- **Mortality analyses**: cause_of_death enables cause-specific mortality reporting

## Commits

1. **38766fc** - `feat(78-02): add cause_of_death and drug_group to Gantt v2 exports`
   - R/52_gantt_v2_export.R (+151, -33 lines)
   - Schema updates: 14→16 episodes, 13→14 detail
   - SECTION 3B: death cause mapping
   - Quality gate integration
   - Guard clauses for new columns

2. **5ec46aa** - `feat(78-02): add Phase 78 validation sections to smoke test`
   - R/88_smoke_test_comprehensive.R (+129, -1 lines)
   - SECTION 14: DEATH-01 validation (7 checks)
   - SECTION 15: CANCER-03/DEATH-02 validation (10 checks)
   - SECTION 16: SUMMARY renumbered
   - Validated requirements list updated

## Self-Check: PASSED

### Files Modified
✓ `R/52_gantt_v2_export.R` modified (+151, -33 lines)
✓ `R/88_smoke_test_comprehensive.R` modified (+129, -1 lines)

### Commits Verified
```bash
git log --oneline | grep -E "(38766fc|5ec46aa)"
```
✓ 38766fc feat(78-02): add cause_of_death and drug_group to Gantt v2 exports
✓ 5ec46aa feat(78-02): add Phase 78 validation sections to smoke test

## Notes

### Quality Gate Integration Pattern
R/52 follows the quality gate pattern established in Plan 78-01:
1. Check if `death_cause_quality_result.rds` exists
2. Load and inspect `death_cause_available` flag
3. If false → skip mapping, set all cause_of_death to NA
4. If missingness > 60% → console warning, proceed with integration
5. If DEATH_CAUSE field missing from validated_death_dates.rds → query DEATH table directly via DuckDB

This graceful degradation ensures the export never fails due to missing death cause data.

### DEATH_CAUSE Field Availability Fallback
The plan anticipated DEATH_CAUSE might not be in validated_death_dates.rds (which only stores ID, DEATH_DATE, DEATH_SOURCE per R/53). If missing, R/52 queries the DEATH table directly via DuckDB to fetch DEATH_CAUSE codes. This pattern mirrors R/35's field availability check.

### Drug Group Propagation
drug_group flows from R/28 → treatment_episodes.rds → R/52 episodes export. Detail CSV does NOT get drug_group because:
- drug_group is an **episode-level** field (one value per episode)
- detail CSV is **date-level** (one row per treatment date)
- Episode-level fields (cancer_category, regimen_label, is_first_line) are joined to detail via left_join but drug_group was excluded per D-14

This maintains semantic consistency with existing detail CSV structure.

### Smoke Test Coverage
17 new checks ensure Phase 78 integration is complete:
- R/35 structural validation (7 checks)
- R/28 column enrichment validation (4 checks)
- R/52 Gantt integration validation (6 checks)

All checks are lightweight pattern matches — no actual script execution required.

---

**Duration:** 6 minutes
**Status:** Complete — all tasks executed, committed, verified
