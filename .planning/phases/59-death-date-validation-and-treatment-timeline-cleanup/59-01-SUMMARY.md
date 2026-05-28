---
phase: 59-death-date-validation-and-treatment-timeline-cleanup
plan: 01
subsystem: clinical-data-validation
tags:
  - death-dates
  - temporal-validation
  - data-quality
  - treatment-timeline
dependency_graph:
  requires:
    - treatment_episodes.rds (Phase 44)
    - confirmed_hl_cohort.rds (Phase 55)
    - DuckDB DEATH table (Phase 29)
    - DuckDB ENCOUNTER table (Phase 29)
    - DuckDB DIAGNOSIS table (Phase 29)
    - DuckDB DEMOGRAPHIC table (Phase 29)
    - DuckDB ENROLLMENT table (Phase 29)
  provides:
    - validated_death_dates.rds
    - death_date_validation.xlsx
    - death_date_validation.csv
  affects:
    - R/49_gantt_data_export.R (future modification to consume validated_death_dates.rds)
tech_stack:
  added: []
  patterns:
    - DuckDB multi-table temporal validation via dplyr filtering joins (anti_join, inner_join)
    - Post-death activity detection across ENCOUNTER/DIAGNOSIS/treatment tables
    - Death-only patient investigation with full clinical timeline
    - openxlsx2 three-sheet styled validation report
    - care_gap_category classification via case_when() logic
key_files:
  created:
    - R/59_death_date_validation.R
    - output/death_date_validation.xlsx (generated on execution)
    - output/death_date_validation.csv (generated on execution)
    - validated_death_dates.rds (generated on execution)
  modified: []
decisions:
  - decision: Use anti_join to remove impossible deaths from valid pool
    rationale: Idiomatic dplyr pattern for "not in" filtering, handles NA edge cases automatically
    impact: Clean separation of impossible vs valid deaths for downstream consumption
  - decision: Flag post-death activity without auto-excluding
    rationale: Per D-03, post-death activity needs manual review (may be delayed reporting, not data errors)
    impact: Validation report surfaces potential data quality issues for researcher review
  - decision: Investigate death-only patients with full clinical timeline
    rationale: Per D-05/D-06, need to answer "Are they real HL patients?" and "Why no treatments?"
    impact: Care gap classification reveals VRT-only sources, unconfirmed HL, died before diagnosis, etc.
  - decision: Three-sheet xlsx report structure
    rationale: Per D-10, separate sheets for summary stats, flagged patient detail, and death-only investigation
    impact: Clean separation of validation findings by audience (summary for QA, detail for manual review, death-only for cohort validity)
metrics:
  duration_minutes: 3
  tasks_completed: 1
  files_created: 1
  lines_of_code: 470
  completed_date: 2026-05-28
---

# Phase 59 Plan 01: Death Date Validation Script Creation Summary

**One-liner:** Death date validation script with temporal consistency checks, post-death activity flagging, death-only patient investigation, and three-sheet xlsx validation report.

## What Was Built

Created R/59_death_date_validation.R, a comprehensive death date validation script that:

1. **Validates death dates against treatment timelines** (per D-01, D-02)
   - Loads death data from DuckDB with 1900 sentinel filtering
   - Computes earliest treatment date per patient across all treatment types
   - Identifies impossible deaths (death BEFORE earliest treatment) via `filter(DEATH_DATE < earliest_treatment_date)`
   - Removes impossible deaths from valid pool using `anti_join()`

2. **Flags post-death clinical activity** (per D-03)
   - Checks ENCOUNTER table for post-death admissions
   - Checks DIAGNOSIS table for post-death diagnoses
   - Checks treatment episodes for post-death treatments
   - Combines flags into binary `post_death_activity` indicator without auto-excluding (manual review required)

3. **Investigates death-only patients** (per D-05, D-06)
   - Identifies patients with death dates but no treatment records
   - Checks HL confirmation status (2+ codes, 7-day threshold from Phase 55)
   - Loads demographics (age at death, sex, race)
   - Loads enrollment (coverage periods)
   - Counts encounters and diagnoses (total + HL-specific C81 codes)
   - Classifies care gaps into 6 categories:
     - No HL diagnosis codes in data
     - Has HL codes but not confirmed (< 2 codes or < 7 days)
     - Confirmed HL but died before first HL diagnosis date
     - Confirmed HL, no encounter records
     - Confirmed HL with encounters but no treatment records
     - Other / Unknown

4. **Produces multi-format outputs** (per D-10, D-12)
   - **validated_death_dates.rds**: Artifact for downstream R/49 consumption (ID, DEATH_DATE, DEATH_SOURCE, death_valid, post_death_activity)
   - **death_date_validation.xlsx**: Three-sheet styled report
     - Sheet 1: Validation Summary (11 summary statistics with dark header styling)
     - Sheet 2: Flagged Patients (impossible deaths + post-death activity detail)
     - Sheet 3: Death Only Patients (full clinical timeline with care gap classification)
   - **death_date_validation.csv**: Flat export of all validated death records

**Population:** ALL patients with death dates, regardless of HL confirmation status (per D-11).

**Key validation logic:**
- Impossible death detection: `death_data %>% inner_join(earliest_treatment) %>% filter(DEATH_DATE < earliest_treatment_date)`
- Post-death activity detection: `inner_join(valid_deaths) %>% filter(ADMIT_DATE > DEATH_DATE)` (repeated for ENCOUNTER, DIAGNOSIS, treatment tables)
- Death-only identification: `death_data %>% anti_join(treatment_episodes)`

## Deviations from Plan

None - plan executed exactly as written. All decision points (D-01 through D-12) followed precisely.

## Verification Status

**Automated checks passed:**
- File exists: R/59_death_date_validation.R ✓
- Line count: 470 lines (min_lines: 250) ✓
- Contains `get_pcornet_table("DEATH")` ✓
- Contains `get_pcornet_table("ENCOUNTER")` (2 calls) ✓
- Contains `get_pcornet_table("DIAGNOSIS")` (2 calls) ✓
- Contains `get_pcornet_table("DEMOGRAPHIC")` ✓
- Contains `get_pcornet_table("ENROLLMENT")` ✓
- Contains `readRDS` calls (2 for treatment_episodes.rds, confirmed_hl_cohort.rds) ✓
- Contains `anti_join(impossible_deaths)` for removing impossible deaths ✓
- Contains `filter(DEATH_DATE < earliest_treatment_date)` for impossible death detection ✓
- Contains `filter(ADMIT_DATE > DEATH_DATE)` for post-death encounter detection ✓
- Contains `filter(DX_DATE > DEATH_DATE)` for post-death diagnosis detection ✓
- Contains `anti_join(treatment_episodes)` for identifying death-only patients ✓
- Contains `care_gap_category = case_when(` for classifying death-only patients ✓
- Contains `if_else(year(DEATH_DATE) == 1900L` for sentinel date filtering ✓
- Contains `saveRDS(` to write validated_death_dates.rds ✓
- Contains `wb_save(` to write xlsx output ✓
- Contains `write.csv(` to write CSV output ✓
- Contains three `add_worksheet` calls for three-sheet xlsx ✓
- Contains "Validation Summary" for Sheet 1 ✓
- Contains "Flagged Patients" for Sheet 2 ✓
- Contains "Death Only Patients" for Sheet 3 ✓

**Manual execution required:** Script runs on HiPerGator with access to DuckDB and RDS cache. Output files (xlsx, csv, rds) will be generated when executed on the server.

## Implementation Notes

### Reused Patterns
1. **Death data loading** (R/49 lines 394-424): Exact replication of DuckDB query, parse_pcornet_date(), 1900 sentinel filtering, and deduplication via `min(DEATH_DATE)`
2. **Pseudo-treatment row structure** (R/49 lines 532-572): Used as reference for understanding treatment episode schema (not modified in this plan - deferred to Plan 02)
3. **openxlsx2 styling** (R/44a): Dark header fill (FF374151), white font (FFFFFFFF), Calibri font, freeze panes, number formatting

### Technical Decisions
- **No type filtering for earliest treatment:** Uses `min(episode_start)` across ALL treatment types (Chemotherapy, Radiation, SCT, Immunotherapy) per RESEARCH anti-pattern 2
- **Binary post-death activity flag:** Flagged patients appear in Sheet 2 for manual review; no automatic exclusion per D-03
- **Care gap classification:** Six categories based on HL confirmation, diagnosis timing, encounter presence, and treatment absence
- **RDS schema:** Minimal schema (5 columns) per Claude's discretion: ID, DEATH_DATE, DEATH_SOURCE, death_valid, post_death_activity

### Known Limitations
1. **No conflicting death date detection:** Takes `min(DEATH_DATE)` when multiple sources disagree (established Phase 57 pattern). Conflict detection deferred to v2 per RESEARCH Open Question 3.
2. **No post-death activity severity categorization:** Binary flag only (ANY post-death activity). Severity by time interval (1-7 days vs >30 days) deferred to v2 per RESEARCH Open Question 2.
3. **HL Diagnosis rows not added:** Plan 01 focuses on validation only. HL Diagnosis pseudo-treatment rows deferred to Plan 02 (R/49 modification).

## Testing & Validation

**On HiPerGator:**
```r
source("R/59_death_date_validation.R")
```

**Expected outputs:**
1. Console messages showing:
   - Patients with valid death dates count
   - Patients with treatment records count
   - Impossible death dates count
   - Valid death dates retained count
   - Post-death activity counts by table (ENCOUNTER, DIAGNOSIS, treatment)
   - Death-only patients count with care gap category breakdown
2. Three output files created:
   - `output/death_date_validation.xlsx` (3 sheets)
   - `output/death_date_validation.csv`
   - `/blue/erin.mobley-hl.bcu/clean/rds/outputs/validated_death_dates.rds`

**Verification:**
- Check Sheet 1 summary statistics match console output counts
- Check Sheet 2 flagged patients list is non-empty if impossible deaths exist
- Check Sheet 3 death-only patients have care_gap_category populated for all rows
- Verify RDS contains expected columns: ID, DEATH_DATE, DEATH_SOURCE, death_valid, post_death_activity

## Next Steps

1. **Execute on HiPerGator** to generate validation outputs
2. **Review Sheet 2** (Flagged Patients) for impossible death date cases and post-death activity patterns
3. **Review Sheet 3** (Death Only Patients) to understand care gap distribution
4. **Plan 02**: Modify R/49_gantt_data_export.R to:
   - Consume validated_death_dates.rds (remove impossible deaths before Gantt export)
   - Add HL Diagnosis pseudo-treatment rows (per D-07, D-08, D-09)
   - Regenerate gantt_episodes.csv and gantt_detail.csv with cleaned death data

## Files Modified

### Created
- `R/59_death_date_validation.R` (470 lines) - Death date validation, post-death activity flagging, death-only investigation, multi-output generation

### Outputs (Generated on Execution)
- `output/death_date_validation.xlsx` - Three-sheet validation report
- `output/death_date_validation.csv` - Flat export of validated death records
- `/blue/erin.mobley-hl.bcu/clean/rds/outputs/validated_death_dates.rds` - Artifact for downstream R/49 consumption

## Commit

- **Hash:** 0b57877
- **Message:** feat(59-01): create death date validation script with multi-output generation
- **Files:** R/59_death_date_validation.R

---

*Plan completed: 2026-05-28*
*Duration: 3 minutes*
*Status: Ready for HiPerGator execution*
