---
phase: 59-death-date-validation-and-treatment-timeline-cleanup
plan: 02
subsystem: gantt-visualization
tags:
  - gantt-export
  - validated-death-dates
  - hl-diagnosis-timeline
  - pseudo-treatment-rows
dependency_graph:
  requires:
    - validated_death_dates.rds (Phase 59 Plan 01)
    - confirmed_hl_cohort.rds (Phase 55)
    - treatment_episodes.rds (Phase 44)
    - code_descriptions.rds (Phase 48b)
    - cancer_summary.csv (Phase 55)
  provides:
    - gantt_episodes.csv (with HL Diagnosis rows, validated Death rows)
    - gantt_detail.csv (with HL Diagnosis rows, validated Death rows)
  affects:
    - Gantt chart visualizations (downstream consumer of CSV outputs)
tech_stack:
  added: []
  patterns:
    - Validated death date integration via readRDS with fallback to raw DEATH table
    - HL Diagnosis pseudo-treatment rows using same zero-length event pattern as Death rows
    - Column validation before bind_rows (setdiff pattern matching death row validation)
    - 1900 sentinel date filtering applied to first_hl_dx_date
    - Chronological re-sort after appending pseudo-treatment rows
key_files:
  created: []
  modified:
    - R/49_gantt_data_export.R
decisions:
  - decision: Load validated_death_dates.rds with fallback to raw DEATH table
    rationale: Maintains backward compatibility if validation script hasn't been run yet
    impact: Script works in both pre-validation and post-validation states
  - decision: HL Diagnosis rows for ALL HL patients, not just confirmed 7-day cohort
    rationale: Per D-08, provides timeline reference for all patients with any HL diagnosis
    impact: Broader visualization coverage beyond final cohort
  - decision: Apply 1900 sentinel filtering to first_hl_dx_date
    rationale: Maintains consistency with established date handling pattern across codebase
    impact: Invalid 1900 sentinel dates excluded from HL Diagnosis rows
  - decision: Re-sort episodes/detail after appending HL Diagnosis rows
    rationale: Ensures chronological ordering per patient (HL Diagnosis -> Treatments -> Death)
    impact: Gantt chart displays clinical timeline in correct temporal sequence
metrics:
  duration_minutes: 2
  tasks_completed: 1
  files_modified: 1
  lines_added: 164
  lines_removed: 24
  completed_date: 2026-05-28
---

# Phase 59 Plan 02: Gantt Export Integration Summary

**One-liner:** Gantt CSV export now consumes validated death dates (excluding impossible pre-treatment deaths) and adds HL Diagnosis pseudo-treatment rows as timeline reference points.

## What Was Built

Modified R/49_gantt_data_export.R to integrate validated death dates and add HL Diagnosis pseudo-treatment rows:

1. **Validated death date integration** (per D-01, D-02)
   - Added `VALIDATED_DEATHS_RDS` path constant pointing to validated_death_dates.rds
   - Replaced SECTION 2C (raw DEATH table loading) with validated death date consumption
   - Filters to `death_valid == TRUE` to exclude impossible deaths (death before earliest treatment)
   - Maintains backward compatibility with fallback to raw DEATH table if validated_death_dates.rds missing
   - Logs count of excluded impossible deaths in console output

2. **HL Diagnosis pseudo-treatment rows** (per D-07, D-08, D-09)
   - Added `COHORT_RDS` path constant pointing to confirmed_hl_cohort.rds
   - Created SECTION 2D to load HL cohort with 1900 sentinel filtering on first_hl_dx_date
   - Created SECTION 4C to build and append HL Diagnosis rows to both gantt_episodes.csv and gantt_detail.csv
   - HL Diagnosis rows use same zero-length event structure as Death rows:
     - `treatment_type = "HL Diagnosis"`
     - `episode_start = episode_stop = first_hl_dx_date`
     - `episode_length_days = 0L`
     - `episode_number = 1L`
     - Empty triggering_codes/triggering_code_descriptions
   - Default `cancer_category = "Hodgkin Lymphoma"` for patients missing category
   - Force `is_hodgkin = TRUE` for all HL Diagnosis rows

3. **Column validation and ordering** (per RESEARCH.md Pitfall 4)
   - Added column validation for HL Diagnosis rows using setdiff pattern (matches Death row validation)
   - Re-sorts episodes and detail tables after appending HL Diagnosis rows: `arrange(patient_id, episode_start, treatment_type)`
   - Ensures chronological ordering: HL Diagnosis -> Treatments -> Death

4. **Updated documentation and logging**
   - Added Phase 59 decision references (D-01, D-02, D-07, D-08, D-09) to header comment block
   - Added validated_death_dates.rds and confirmed_hl_cohort.rds to Inputs section
   - Added HL Diagnosis row count to final summary stats (SECTION 6)

## Deviations from Plan

None - plan executed exactly as written. All six CHANGE blocks implemented precisely.

## Verification Status

**Automated checks passed:**
- File modified: R/49_gantt_data_export.R ✓
- Contains `VALIDATED_DEATHS_RDS <- file.path(CONFIG$cache$outputs_dir, "validated_death_dates.rds")` ✓
- Contains `COHORT_RDS <- file.path(CONFIG$cache$outputs_dir, "confirmed_hl_cohort.rds")` ✓
- Contains `readRDS(VALIDATED_DEATHS_RDS)` (line 433) ✓
- Contains `filter(death_valid == TRUE)` (line 436) ✓
- Contains `readRDS(COHORT_RDS)` (line 458) ✓
- Contains `treatment_type = "HL Diagnosis"` (2 occurrences: lines 668, 695) ✓
- Contains `episode_length_days = 0L` in HL Diagnosis row construction (line 672) ✓
- Contains `cancer_category = ifelse(is.na(cancer_category), "Hodgkin Lymphoma"` (2 occurrences: lines 663, 690) ✓
- Contains `is_hodgkin = TRUE` in HL Diagnosis row construction (2 occurrences: lines 664, 691) ✓
- Contains column validation for HL Diagnosis rows (setdiff pattern: line 715) ✓
- Contains fallback to raw DEATH table loading if validated_death_dates.rds does not exist (line 411) ✓
- File header comment block contains "D-01 (Phase 59)" (line 27) ✓
- File header comment block contains "D-07 (Phase 59)" (line 29) ✓
- Contains `if_else(year(first_hl_dx_date) == 1900L` for sentinel filtering on HL dates (line 461) ✓
- SECTION 4C appears AFTER SECTION 4B (death rows at line 558, HL Diagnosis at line 654) ✓

**Search metrics:**
- "validated_death_dates" references: 3 (VALIDATED_DEATHS_RDS definition, file existence check, readRDS call)
- "HL Diagnosis" references: 19 (header comments, logging messages, treatment_type assignments, section headers)
- "confirmed_hl_cohort" references: 3 (COHORT_RDS definition, file existence check, readRDS call)

**Manual execution required:** Script runs on HiPerGator with access to DuckDB and RDS cache. When executed after R/59_death_date_validation.R, it will produce gantt_episodes.csv and gantt_detail.csv with impossible deaths excluded and HL Diagnosis rows added.

## Implementation Notes

### Code Structure Changes

**SECTION 2C (lines 408-445):** Replaced raw DEATH table loading with validated death date consumption. Loads validated_death_dates.rds if available, filters to death_valid=TRUE, and falls back to raw DEATH table (original Phase 57 logic) if RDS missing.

**SECTION 2D (lines 448-464):** New section to load confirmed_hl_cohort.rds with 1900 sentinel filtering applied to first_hl_dx_date.

**SECTION 4C (lines 654-754):** New section to build HL Diagnosis pseudo-treatment rows for both episodes and detail tables, validate column alignment, and append with chronological re-sort.

**SECTION 6 (line 787):** Added HL Diagnosis row count to final summary output.

### Reused Patterns

1. **Death row structure** (R/49 lines 558-653): HL Diagnosis rows replicate the exact same zero-length event pattern (treatment_type label, episode_start=episode_stop, episode_length_days=0, empty triggering codes)
2. **Column validation** (R/49 lines 614-637 for Death rows): HL Diagnosis rows use identical setdiff validation before bind_rows
3. **1900 sentinel filtering** (R/49 line 427 for DEATH_DATE): Applied to first_hl_dx_date in SECTION 2D
4. **Fallback loading pattern** (established Phase 57 pattern): SECTION 2C maintains original DuckDB logic when validated_death_dates.rds unavailable

### Technical Decisions

- **Backward compatibility:** Fallback to raw DEATH table ensures script works even if R/59_death_date_validation.R hasn't been run yet. No hard dependency on Phase 59 Plan 01 completion.
- **HL Diagnosis population:** Uses ALL patients from confirmed_hl_cohort.rds (2+ HL codes, 7-day separation), not restricted to final 7-day threshold cohort. Per D-08, provides broader timeline context.
- **Default cancer category:** HL Diagnosis rows default to "Hodgkin Lymphoma" if cancer_category missing from cancer_summary.csv (per Claude's discretion, consistent with patient's clinical context).
- **Chronological re-sort:** Both episodes_export and detail_export re-sorted after appending HL Diagnosis rows to ensure correct temporal ordering (HL Diagnosis -> Treatments -> Death).

## Testing & Validation

**On HiPerGator (after R/59_death_date_validation.R execution):**

```r
source("R/49_gantt_data_export.R")
```

**Expected console output:**
- "Loaded validated death dates: {N} valid, {M} impossible excluded (per D-02)"
- "Loaded {K} HL patients with valid first diagnosis dates"
- "Added {K} HL Diagnosis episode rows"
- "Added {K} HL Diagnosis detail rows"
- "HL Diagnosis pseudo-treatment rows in episodes: {K}"

**Expected outputs:**
1. `output/gantt_episodes.csv` — Episode bars with HL Diagnosis rows and validated Death rows (impossible deaths excluded)
2. `output/gantt_detail.csv` — Detail ticks with HL Diagnosis rows and validated Death rows (impossible deaths excluded)

**Verification:**
- Check gantt_episodes.csv for `treatment_type = "HL Diagnosis"` rows with episode_length_days=0
- Check gantt_episodes.csv for `treatment_type = "Death"` row count matches valid death count (not total death count)
- Verify no death rows exist for patients flagged with impossible deaths in death_date_validation.xlsx Sheet 2
- Verify HL Diagnosis rows appear chronologically before treatment rows for the same patient

**Backward compatibility test (before R/59_death_date_validation.R execution):**

```r
source("R/49_gantt_data_export.R")
```

**Expected console output:**
- "validated_death_dates.rds not found. Run R/59_death_date_validation.R first. Falling back to raw DEATH table."
- "Patients with valid death dates for Gantt: {N}" (all deaths, no exclusions)
- HL Diagnosis rows still added (independent of death validation)

## Next Steps

1. **Execute R/49_gantt_data_export.R on HiPerGator** after R/59_death_date_validation.R completes
2. **Review gantt_episodes.csv** to verify HL Diagnosis rows appear chronologically
3. **Cross-reference with death_date_validation.xlsx Sheet 2** to confirm impossible death rows excluded
4. **Visualize in Gantt charting tool** to verify timeline reference points display correctly
5. **Future enhancement (v2):** Add HL Diagnosis date to treatment episode filtering logic (exclude treatments before first HL diagnosis per temporal filtering requirements)

## Files Modified

### Modified
- `R/49_gantt_data_export.R` (+164 lines, -24 lines) - Integrate validated death dates, add HL Diagnosis pseudo-treatment rows, maintain backward compatibility

### Outputs (Modified on Execution)
- `output/gantt_episodes.csv` - Episode bars with HL Diagnosis rows and validated Death rows
- `output/gantt_detail.csv` - Detail ticks with HL Diagnosis rows and validated Death rows

## Commit

- **Hash:** 1b91c2a
- **Message:** feat(59-02): integrate validated death dates and add HL Diagnosis pseudo-treatment rows
- **Files:** R/49_gantt_data_export.R

---

*Plan completed: 2026-05-28*
*Duration: 2 minutes*
*Status: Ready for HiPerGator execution*
