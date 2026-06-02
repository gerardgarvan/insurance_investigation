---
status: testing
phase: 57-gantt-enhancements
source: 57-01-PLAN.md (no SUMMARY.md found; tests derived from plan acceptance criteria and implementation)
started: 2026-05-25T12:00:00Z
updated: 2026-05-25T12:00:00Z
---

## Current Test

number: 1
name: DEATH table registered in PCORNET_TABLES
expected: |
  Open R/00_config.R. The PCORNET_TABLES vector should contain "DEATH" as the last entry (15 entries total). The "PROVIDER" line should have a trailing comma since it's no longer the last element.
awaiting: user response

## Tests

### 1. DEATH table registered in PCORNET_TABLES
expected: R/00_config.R PCORNET_TABLES vector contains "DEATH" as the 15th entry, with a comment "Phase 57: death dates for Gantt chart endpoint". "PROVIDER" line has a trailing comma.
result: [pending]

### 2. DEATH_SPEC column specification
expected: R/01_load_pcornet.R contains DEATH_SPEC with exactly 6 col_character() columns: ID, DEATH_DATE, DEATH_DATE_IMPUTE, DEATH_SOURCE, DEATH_MATCH_CONFIDENCE, SOURCE. Comment block mentions "Phase 57" and "DEATH_Mailhot_V1.csv".
result: [pending]

### 3. DEATH wired into TABLE_SPECS dispatch
expected: R/01_load_pcornet.R TABLE_SPECS list contains `DEATH = DEATH_SPEC` so the loading pipeline uses the correct column spec when ingesting the DEATH table.
result: [pending]

### 4. Cancer category enrichment in gantt_episodes.csv
expected: After running R/49_gantt_data_export.R, gantt_episodes.csv has a `cancer_category` column with comma-separated cancer site category names (e.g., "Hodgkin Lymphoma" or "Hodgkin Lymphoma,Non-Hodgkin Lymphoma"). Patients not in cancer_summary get an empty string.
result: [pending]

### 5. is_hodgkin flag in gantt_episodes.csv
expected: gantt_episodes.csv has an `is_hodgkin` column with TRUE/FALSE values. TRUE when "Hodgkin Lymphoma" appears anywhere in cancer_category, FALSE otherwise.
result: [pending]

### 6. Death pseudo-treatment rows in gantt_episodes.csv
expected: gantt_episodes.csv contains rows with `treatment_type = "Death"`. These rows have episode_length_days=0, empty triggering_codes, and a valid death date (not 1900) as episode_start and episode_stop.
result: [pending]

### 7. Cancer category and is_hodgkin in gantt_detail.csv
expected: gantt_detail.csv also has `cancer_category` and `is_hodgkin` columns, matching the same logic as episodes (comma-separated categories, is_hodgkin TRUE for Hodgkin patients).
result: [pending]

### 8. Death pseudo-treatment rows in gantt_detail.csv
expected: gantt_detail.csv contains rows with `treatment_type = "Death"`. These have a valid treatment_date (the death date), empty triggering_code, and empty triggering_code_description.
result: [pending]

### 9. 1900 sentinel date exclusion
expected: No death rows in either CSV have dates from the year 1900. The script nullifies 1900 sentinel dates and filters them out before building death pseudo-treatment rows.
result: [pending]

### 10. Console output shows enrichment stats
expected: Running R/49_gantt_data_export.R prints stats including: cancer categories aggregated for N patients, Hodgkin Lymphoma patient count, patients with valid death dates count, death episode/detail rows added count.
result: [pending]

## Summary

total: 10
passed: 0
issues: 0
pending: 10
skipped: 0
blocked: 0

## Gaps

[none yet]
