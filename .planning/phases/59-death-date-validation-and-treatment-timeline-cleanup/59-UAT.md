---
status: testing
phase: 59-death-date-validation-and-treatment-timeline-cleanup
source: 59-01-SUMMARY.md, 59-02-SUMMARY.md
started: 2026-05-28T22:00:00Z
updated: 2026-05-28T22:05:00Z
---

## Current Test

number: 3
name: Death Date Validation XLSX Report
expected: |
  Opening `output/death_date_validation.xlsx` shows 3 sheets:
  Sheet 1 "Validation Summary" with 11 summary statistics and dark header styling,
  Sheet 2 "Flagged Patients" listing impossible deaths and patients with post-death activity,
  Sheet 3 "Death Only Patients" with full clinical timeline and care_gap_category populated for every row.
awaiting: user response

## Tests

### 1. Death Date Validation Script Structure
expected: R/59_death_date_validation.R exists (~470 lines) and contains all expected validation sections: DuckDB death data loading with 1900 sentinel filtering, impossible death detection (death before earliest treatment), post-death activity flagging across ENCOUNTER/DIAGNOSIS/treatment tables, death-only patient investigation with 6-category care_gap_category classification, three-sheet openxlsx2 output, and RDS/CSV output generation.
result: pass

### 2. Validation Script Execution
expected: Running `source("R/59_death_date_validation.R")` on HiPerGator prints console messages showing: patients with valid death dates count, patients with treatment records count, impossible death dates count, valid death dates retained count, post-death activity counts by table (ENCOUNTER, DIAGNOSIS, treatment), and death-only patients count with care gap category breakdown. Three output files are generated without errors.
result: issue
reported: "Investigating death-only patients --- Patients with death dates but no treatment records: 594. Error in eval(ei, envir) : Confirmed HL cohort RDS not found: /blue/erin.mobley-hl.bcu/clean/rds/outputs/confirmed_hl_cohort.rds"
severity: blocker

### 3. Death Date Validation XLSX Report
expected: Opening `output/death_date_validation.xlsx` shows 3 sheets: Sheet 1 "Validation Summary" with 11 summary statistics and dark header styling, Sheet 2 "Flagged Patients" listing impossible deaths and patients with post-death activity, Sheet 3 "Death Only Patients" with full clinical timeline and care_gap_category populated for every row.
result: [pending]

### 4. Validated Death Dates RDS Schema
expected: Loading `validated_death_dates.rds` in R returns a data frame with exactly 5 columns: ID, DEATH_DATE, DEATH_SOURCE, death_valid, post_death_activity. Rows with death_valid=TRUE represent deaths that passed temporal consistency checks.
result: [pending]

### 5. Gantt Export Integrates Validated Deaths
expected: Running `source("R/49_gantt_data_export.R")` after R/59 shows console message about loaded validated death dates with impossible deaths excluded. In gantt_episodes.csv, `treatment_type = "Death"` row count matches valid death count (impossible deaths excluded).
result: [pending]

### 6. HL Diagnosis Rows in Gantt CSVs
expected: gantt_episodes.csv and gantt_detail.csv contain rows with `treatment_type = "HL Diagnosis"`, `episode_length_days = 0`, and they appear chronologically before treatment rows for the same patient. HL Diagnosis rows have `is_hodgkin = TRUE` and non-empty cancer_category.
result: [pending]

### 7. Gantt Export Backward Compatibility
expected: Running R/49 WITHOUT validated_death_dates.rds present shows fallback message "validated_death_dates.rds not found... Falling back to raw DEATH table" and proceeds normally with all death dates included (no impossible death exclusion). HL Diagnosis rows are still added independently.
result: [pending]

## Summary

total: 7
passed: 1
issues: 1
pending: 5
skipped: 0
blocked: 0

## Gaps

- truth: "R/59 script completes execution without errors, producing all three output files"
  status: failed
  reason: "User reported: Error in eval(ei, envir) : Confirmed HL cohort RDS not found: /blue/erin.mobley-hl.bcu/clean/rds/outputs/confirmed_hl_cohort.rds"
  severity: blocker
  test: 2
  root_cause: "Path mismatch: R/55 saves confirmed_hl_cohort.rds to CONFIG$output_dir (output/) but R/59 line 32 loads from CONFIG$cache$outputs_dir (/blue/.../rds/outputs). R/56 and R/58 correctly use CONFIG$output_dir. R/49 line 78 has the same bug."
  artifacts:
    - path: "R/59_death_date_validation.R"
      line: 32
      issue: "COHORT_RDS uses CONFIG$cache$outputs_dir instead of CONFIG$output_dir"
    - path: "R/49_gantt_data_export.R"
      line: 78
      issue: "COHORT_RDS uses CONFIG$cache$outputs_dir instead of CONFIG$output_dir"
  missing:
    - "Change R/59 line 32: CONFIG$cache$outputs_dir -> CONFIG$output_dir"
    - "Change R/49 line 78: CONFIG$cache$outputs_dir -> CONFIG$output_dir"
  debug_session: ""
