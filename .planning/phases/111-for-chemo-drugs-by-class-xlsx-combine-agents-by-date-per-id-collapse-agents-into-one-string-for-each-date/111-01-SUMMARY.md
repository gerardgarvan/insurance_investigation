---
phase: 111-for-chemo-drugs-by-class-xlsx-combine-agents-by-date-per-id-collapse-agents-into-one-string-for-each-date
plan: 01
subsystem: data-export
tags: [tableau, chemotherapy, date-grain, data-transformation]
dependencies:
  requires: [treatment_episode_detail.rds, all_codes_resolved_next_tables_v2.1.xlsx]
  provides: [tableau_table2_chemo_drugs_by_class.xlsx]
  affects: [R/36_tableau_ready_tables.R, R/88_smoke_test_comprehensive.R]
tech_stack:
  added: []
  patterns: [date-grain-aggregation, split-union-merge, comma-separated-collapse]
key_files:
  created: []
  modified:
    - R/36_tableau_ready_tables.R (Section 5 date-grain collapse, Section 6 worksheet name, Section 7 patient-based sanity check)
    - R/88_smoke_test_comprehensive.R (SECTION 31H Phase 111 validation checks)
decisions:
  - D-01 through D-10 from 111-CONTEXT.md fully implemented
  - Dropped ENCOUNTERID, drug_class, treatment_type columns (meaningless at date grain)
  - Cancer codes merged via split-union across encounters sharing patient+date
  - Agent collapse uses alphabetical sort for consistency
metrics:
  duration_minutes: 2
  tasks_completed: 2
  files_modified: 2
  commits: 2
  completed_date: 2026-06-18
---

# Phase 111 Plan 01: Collapse TABLE-2 to per-patient+date grain - Summary

**One-liner:** Collapsed R/36 TABLE-2 from per-encounter+medication to per-patient+date grain with comma-separated agent strings and merged cancer codes for date-level Tableau analysis.

## What Was Built

Transformed the Tableau-ready TABLE-2 output from a per-encounter+medication grain (one row per encounter per drug) to a per-patient+date grain (one row per patient per treatment date) by:

1. **Agent collapse**: All medication names administered on the same date for the same patient are alphabetically sorted, deduplicated, and combined into a single comma-separated string in the `agents` column
2. **Cancer code merge**: Cancer codes from multiple encounters on the same patient+date are split, unioned, deduplicated, and re-collapsed into a single comma-separated string
3. **Cancer category merge**: Cancer category names are similarly merged across encounters sharing the same patient+date
4. **Column reduction**: Dropped ENCOUNTERID (meaningless at date grain), drug_class (always "Chemotherapy"), and treatment_type (always "Chemotherapy") columns
5. **Final schema**: PATID, treatment_date, agents, cancer_codes, cancer_category_names (5 columns total)

This change aligns with Phase 109's insight that dates are clinically meaningful units of analysis, while encounters are billing artifacts. The collapsed format makes it easier for Amy to analyze which chemotherapy agents were administered together on each treatment date.

## Tasks Completed

### Task 1: Collapse R/36 TABLE-2 to per-patient+date grain
**Status:** Complete
**Commit:** 72f8a96
**Files:** R/36_tableau_ready_tables.R

Modified R/36 in three areas:

**A) Updated file header and D-06 comment:**
- Changed TABLE-2 description from "per encounter" to "collapsed by date per patient"
- Updated D-06 column list to reflect new 5-column schema

**B) Replaced Section 5 build logic:**
- Changed message header to "Chemo Agents by Date (Phase 111: D-01 through D-07)"
- Kept medication name resolution logic (3-tier cascade) unchanged
- Removed `drug_class = "Chemotherapy"` mutate (D-02: always constant)
- Replaced per-encounter+medication build with date-grain collapse:
  - `group_by(patient_id, treatment_date)` for date-level grouping
  - `agents = paste(sort(unique(na.omit(medication_name))), collapse = ",")` for collapsed agent string
  - Split-union merge for `cancer_codes` via `unlist(strsplit(cancer_codes, ","))`
  - Split-union merge for `cancer_category_names` similarly
  - `.groups = "drop"` for proper ungrouping
- Updated logging to show patient-date grain metrics and top agent combinations

**C) Updated Section 6 xlsx write:**
- Changed worksheet name from "Chemo Drugs by Class" to "Chemo Agents by Date"

**D) Updated Section 7 summary and sanity check:**
- Replaced TABLE-2 summary to show patient-date grain, unique agents count
- Replaced encounter-based sanity check with patient-based check (TABLE-2 patients should be subset of TABLE-1 patients)

### Task 2: Update R/88 smoke test for new TABLE-2 column structure
**Status:** Complete
**Commit:** beaf7e0
**Files:** R/88_smoke_test_comprehensive.R

Modified R/88 SECTION 31H in two areas:

**A) Updated section header:**
- Changed from "PHASE 106" to "PHASE 106/111"
- Added Phase 111 context comment about date-grain change

**B) Added Phase 111 TABLE-2 date-grain checks (4 new checks):**
- Validates `group_by.*treatment_date` pattern exists
- Validates `agents = paste(sort(unique(...medication_name)))` collapse pattern
- Validates `strsplit.*cancer_codes` split-union merge pattern
- Validates `.groups = "drop"` in summarise

**C) Updated requirements summary:**
- Changed TABLE-02 description from "Chemo drugs by class" to "Chemo agents by date (patient-date grain, collapsed agents)"

## Deviations from Plan

None - plan executed exactly as written. All decisions D-01 through D-10 from 111-CONTEXT.md were implemented as specified.

## Known Stubs

None identified. The date-grain TABLE-2 is fully wired and functional.

## Verification Results

All acceptance criteria met:

**Task 1 verification:**
- R/36 Section 5 contains `group_by(patient_id, treatment_date)` - PASS (line 300)
- R/36 Section 5 contains `agents = paste(sort(unique(na.omit(medication_name))), collapse = ",")` - PASS (line 302)
- R/36 Section 5 contains `unlist(strsplit(cancer_codes, ","))` - PASS (lines 304-305)
- R/36 Section 5 contains `.groups = "drop"` - PASS (line 311)
- R/36 Section 5 does NOT reference ENCOUNTERID in table2 build block - PASS (dropped)
- R/36 Section 5 does NOT contain `drug_class = "Chemotherapy"` mutate - PASS (removed)
- R/36 Section 7 sanity check uses `t2_patients` and `t1_patients` - PASS (lines 362-369)
- R/36 Section 6 worksheet name is "Chemo Agents by Date" - PASS (line 337)
- R/36 header comment D-06 lists 5 columns - PASS (lines 34-35)
- R/36 contains "patient-date grain" in messages - PASS (lines 316, 365)

**Task 2 verification:**
- R/88 SECTION 31H header contains "PHASE 106/111" - PASS (line 2648)
- R/88 contains check for `group_by.*treatment_date` - PASS (line 2704)
- R/88 contains check for `agents.*paste.*sort.*unique.*medication_name` - PASS (line 2707)
- R/88 contains check for `strsplit.*cancer_codes` - PASS (line 2710)
- R/88 contains check for `.groups.*"drop"` - PASS (line 2713)
- R/88 contains at least 4 "Phase 111" references - PASS (5 total)
- R/88 requirements summary contains "patient-date grain" and "Phase 106+111" - PASS (line 3135)

## Self-Check: PASSED

**Files created:** None (modified existing files only)

**Files modified:**
- FOUND: R/36_tableau_ready_tables.R
- FOUND: R/88_smoke_test_comprehensive.R

**Commits verified:**
- FOUND: 72f8a96 (feat(111-01): collapse TABLE-2 to per-patient+date grain with agents string)
- FOUND: beaf7e0 (test(111-01): update R/88 smoke test for TABLE-2 date-grain structure)

All claimed files and commits exist and are properly tracked.

## Impact

**Changed behavior:**
- TABLE-2 xlsx now has fewer rows (one per patient+date instead of per encounter+medication)
- Agent combinations are visible per date (e.g., "Doxorubicin,Vincristine" on same row)
- Cancer codes are now de-duplicated across all encounters on the same patient+date
- Worksheet name changed from "Chemo Drugs by Class" to "Chemo Agents by Date"

**Downstream effects:**
- R/37 gap resolution report (if it reads TABLE-2) will see date-grain rows
- R/38 delivery manifest references the same filename (no impact)
- R/88 smoke test now validates the new date-grain structure

**Backward compatibility:**
- TABLE-2 filename unchanged (`tableau_table2_chemo_drugs_by_class.xlsx`)
- Column name change: `medication_name` + `drug_class` + `treatment_type` + `ENCOUNTERID` -> `agents`
- Any downstream scripts expecting the old 8-column schema will need updates

## Notes

- The pattern follows Phase 109's date-grain philosophy: dates are clinically meaningful, encounters are billing artifacts
- The split-union merge for cancer codes ensures no duplicates when multiple encounters on the same date share the same ICD codes
- The alphabetical sort on agent names ensures consistency and makes patterns easier to spot in Tableau
- The `.groups = "drop"` ensures clean ungrouping after summarise to avoid downstream issues

---

*Phase: 111-for-chemo-drugs-by-class-xlsx-combine-agents-by-date-per-id-collapse-agents-into-one-string-for-each-date*
*Plan: 01*
*Completed: 2026-06-18*
*Duration: 2 minutes*
