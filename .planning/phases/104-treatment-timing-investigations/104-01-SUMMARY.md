---
phase: 104-treatment-timing-investigations
plan: 01
subsystem: investigation-scripts
tags: [treatment-timing, secondary-malignancy, 7-day-gap, xlsx-output]
dependency_graph:
  requires:
    - R/26 (treatment_episodes.rds)
    - R/47 (confirmed_hl_cohort.rds)
    - DuckDB DIAGNOSIS table
  provides:
    - R/31 (pre-diagnosis treatment investigation)
    - R/32 (secondary malignancy table investigation)
  affects:
    - R/88 (smoke test updated with Phase 104 validation)
tech_stack:
  added: []
  patterns:
    - Investigation script pattern (7 sections)
    - Two-sheet styled xlsx output (summary + detail)
    - 7-day gap criterion for secondary malignancies
    - Pre/post HL temporal split with population-based percentages
key_files:
  created:
    - R/31_pre_diagnosis_treatments.R
    - R/32_secondary_malignancy_table.R
  modified:
    - R/88_smoke_test_comprehensive.R
decisions:
  - context: "Pre-diagnosis treatment output format (D-01)"
    chosen: "Two-sheet xlsx: summary counts by treatment type + patient-level detail rows"
    reasoning: "Meeting-presentable format with full clinical review context (triggering codes, drug names)"
  - context: "Secondary malignancy 7-day confirmation (D-06)"
    chosen: "Apply 7-day gap criterion to BOTH HL diagnosis AND secondary malignancies"
    reasoning: "Consistent confirmation standard across all cancer diagnoses"
  - context: "Secondary malignancy percentage denominator (D-07, Pitfall 3)"
    chosen: "Total confirmed HL cohort as denominator for all percentages"
    reasoning: "Population-based rates per meeting notes requirement (columns K-N based on population E/E3)"
metrics:
  tasks_completed: 3
  tasks_total: 3
  duration_minutes: 6
  files_created: 2
  files_modified: 1
  lines_added: 868
  commits: 3
  completed_date: "2026-06-15"
---

# Phase 104 Plan 01: Treatment Timing Investigations Summary

**One-liner:** Created two standalone investigation scripts answering G5 (radiation before HL dx) and secondary malignancy table requirements using established 7-section pattern with styled xlsx outputs.

## What Was Built

Two investigation scripts for Phase 104 (TIMING-01, TIMING-02):

1. **R/31_pre_diagnosis_treatments.R** -- Flags and quantifies all treatment episodes occurring before a patient's first confirmed HL diagnosis date across all 5 treatment types (Chemotherapy, Radiation, SCT, Immunotherapy, Proton Therapy). Produces meeting-ready two-sheet xlsx with summary counts and patient-level detail including full code context.

2. **R/32_secondary_malignancy_table.R** -- Produces secondary malignancy table for confirmed HL patients using dual 7-day gap confirmation (HL + secondary cancers), classifies into cancer site categories, splits pre/post HL with population-based percentages. Produces meeting-ready two-sheet xlsx.

3. **R/88 smoke test validation** -- Added Section 31D (13 checks for R/31) and Section 31E (15 checks for R/32) to comprehensive smoke test, updated all section counters from /35 to /37, added TIMING-01 and TIMING-02 requirement labels to summary.

## Technical Approach

### R/31 Pre-Diagnosis Treatment Flagging (TIMING-01)

**Data flow:**
1. Load `treatment_episodes.rds` (11 columns from R/26)
2. Load `confirmed_hl_cohort.rds` (3 columns from R/47)
3. Inner join on `patient_id = ID` (treatment_episodes uses "patient_id", cohort uses "ID")
4. Filter sentinel dates: `year(first_hl_dx_date) > 1900`
5. Filter pre-diagnosis: `episode_start < first_hl_dx_date`
6. Compute `days_before_dx = as.numeric(first_hl_dx_date - episode_start)`
7. Aggregate by treatment_type for summary sheet
8. Build patient-level detail with full code context (triggering_codes, drug_names)

**Output:** Two-sheet xlsx with styled headers (FF374151 dark gray, FFFFFFFF white bold text):
- Sheet 1 "Summary": Episodes, patients, median/min/max days before dx by treatment type
- Sheet 2 "Detail": Patient-level rows with ID, treatment_type, episode dates, first_hl_dx_date, days_before_dx, triggering_codes, drug_names

### R/32 Secondary Malignancy Table (TIMING-02)

**Data flow:**
1. Load `confirmed_hl_cohort.rds` for denominator (total_cohort = nrow(cohort))
2. Query DuckDB DIAGNOSIS table for all diagnosis codes
3. Filter to cancer codes via `is_cancer_code(DX)`
4. CRITICAL: Exclude BOTH ICD-10 C81 AND ICD-9 201 HL codes (`!str_detect(DX_norm, "^C81|^201")`)
5. Filter to confirmed HL cohort via inner join
6. Apply 7-day gap criterion per patient-code (copy R/45 lines 266-302 logic):
   - 2+ unique non-NA dates AND `max(dates) - min(dates) >= 7`
7. Classify confirmed secondary cancers into site categories via `classify_codes()`
8. Join to cohort for first_hl_dx_date, filter sentinel dates
9. Split pre/post HL: `earliest_dx < first_hl_dx_date` vs `>= first_hl_dx_date`
10. Aggregate by category and timing with `n_patients / total_cohort` percentages

**Output:** Two-sheet xlsx with styled headers:
- Sheet 1 "Summary": Cancer category, timing (Pre-HL/Post-HL), patient counts, % of total cohort
- Sheet 2 "Detail": Patient-level rows with ID, DX code, category, timing, earliest dx date, first HL dx date, unique dx dates

**Note:** Patients can appear in both Pre-HL and Post-HL rows (split is per diagnosis, not per patient per Pitfall 4).

### R/88 Smoke Test Updates

**Section 31D (R/31 validation):**
- 13 structural checks validating join keys, pre-diagnosis filter, sentinel date guard, days_before_dx computation, styled xlsx output, no saveRDS (investigation script pattern)

**Section 31E (R/32 validation):**
- 15 structural checks validating dual ICD filtering (C81 + 201), 7-day gap criterion, classify_codes usage, pre/post split, total_cohort denominator, styled xlsx output, no saveRDS

**Counter updates:** All section counters incremented from /35 to /37 throughout R/88.

**Summary labels added:** TIMING-01 and TIMING-02 requirement labels added to SECTION 16 validated requirements list.

## Deviations from Plan

None -- plan executed exactly as written. All 3 tasks completed without deviation.

## Files Created

### R/31_pre_diagnosis_treatments.R (316 lines)
- Purpose: Pre-diagnosis treatment flagging investigation (TIMING-01)
- Input: treatment_episodes.rds, confirmed_hl_cohort.rds
- Output: output/pre_diagnosis_treatments.xlsx (two-sheet styled xlsx)
- Pattern: 7-section investigation script (no saveRDS per D-08)
- Features: Sentinel date guard, join key validation, days_before_dx computation, full code context in detail sheet

### R/32_secondary_malignancy_table.R (406 lines)
- Purpose: Secondary malignancy table with 7-day gap criterion (TIMING-02)
- Input: confirmed_hl_cohort.rds, DuckDB DIAGNOSIS table
- Output: output/secondary_malignancy_table.xlsx (two-sheet styled xlsx)
- Pattern: 7-section investigation script (no saveRDS per D-04)
- Features: Dual ICD filtering (C81 + 201), 7-day gap confirmation, classify_codes classification, pre/post HL split, population-based percentages

## Files Modified

### R/88_smoke_test_comprehensive.R (+146 lines, -2 lines)
- Added Section 31D at line 2321 (R/31 validation with 13 checks)
- Added Section 31E at line 2387 (R/32 validation with 15 checks)
- Updated Section 32 counter from [34/35] to [36/37] at line 2469
- Updated Section 33 counter from [35/35] to [37/37] at line 2550
- Added TIMING-01 and TIMING-02 labels to SECTION 16 summary at line 2732

## Key Decisions Made

1. **Script numbering:** R/31 and R/32 selected as next available numbers in 30s decade (investigation scripts decade).

2. **7-day gap logic reuse:** Copied R/45 lines 266-302 verbatim for secondary malignancy confirmation rather than refactoring into shared utility. Rationale: 37 lines of inline summarise() code, would require modifying 12+ existing scripts to create reusable function for 2 new scripts.

3. **Detail sheet column selection (R/31):** Included triggering_codes AND drug_names (not just one) to enable full clinical review without cross-referencing R/26 output. Aligns with D-03 "full code context" requirement.

4. **Summary sheet layout (R/32):** Added "Any Secondary Cancer" total rows for Pre-HL, Post-HL, and Any Timing to clarify that individual category rows are NOT mutually exclusive (Pitfall 4 documentation).

5. **R/88 section placement:** Inserted new Phase 104 sections between Section 31C (Phase 103) and Section 32 (DuckDB validation) to maintain chronological phase ordering in smoke test.

## Verification

All tasks completed per acceptance criteria:

### Task 1 Verification (R/31)
- ✓ R/31 exists with 7 SECTION markers
- ✓ Contains `source("R/00_config.R")` and `source("R/utils/utils_assertions.R")`
- ✓ Contains `readRDS` calls for both treatment_episodes.rds and confirmed_hl_cohort.rds
- ✓ Contains `inner_join` with `by = c("patient_id" = "ID")` (correct join key)
- ✓ Contains `episode_start < first_hl_dx_date` filter
- ✓ Contains `year(first_hl_dx_date) > 1900` sentinel date guard
- ✓ Contains `days_before_dx = as.numeric(first_hl_dx_date - episode_start)` computation
- ✓ Contains `wb_workbook()` with two worksheets: "Summary" and "Detail"
- ✓ Contains FF374151 header fill and FFFFFFFF bold text styling
- ✓ Contains `assert_rds_exists` for input validation
- ✓ Does NOT contain `saveRDS` (investigation script per D-08)
- ✓ Does NOT contain `hipaa_suppress` or `<11` (raw counts per D-09)
- ✓ Detail sheet includes all required columns per D-03
- ✓ Output path is file.path(CONFIG$output_dir, "pre_diagnosis_treatments.xlsx")

### Task 2 Verification (R/32)
- ✓ R/32 exists with 7 SECTION markers
- ✓ Contains `source("R/00_config.R")`, `source("R/utils/utils_cancer.R")`, `source("R/utils/utils_duckdb.R")`
- ✓ Contains `get_pcornet_table("DIAGNOSIS")` for DuckDB query
- ✓ Contains `is_cancer_code(DX)` for cancer code filtering
- ✓ Contains `!str_detect(DX_norm, "^C81|^201")` excluding BOTH ICD-10 and ICD-9 HL codes
- ✓ Contains 7-day gap criterion logic with `max(ud) - min(ud) >= 7` pattern
- ✓ Contains `classify_codes` call for cancer site classification
- ✓ Contains pre/post HL temporal split using `earliest_dx < first_hl_dx_date` vs `>= first_hl_dx_date`
- ✓ Contains `total_cohort <- nrow(cohort)` and uses total_cohort as denominator
- ✓ Contains `wb_workbook()` with two worksheets: "Summary" and "Detail"
- ✓ Contains FF374151 header fill and FFFFFFFF bold text styling
- ✓ Contains note about patients appearing in both Pre-HL and Post-HL rows
- ✓ Does NOT contain `saveRDS` (investigation script per D-04)
- ✓ Does NOT contain `hipaa_suppress` or `<11` (raw counts per D-09)
- ✓ Output path is file.path(CONFIG$output_dir, "secondary_malignancy_table.xlsx")

### Task 3 Verification (R/88)
- ✓ R/88 contains `SECTION 31D: PHASE 104 R/31 -- PRE-DIAGNOSIS TREATMENT FLAGGING (TIMING-01)`
- ✓ R/88 contains `SECTION 31E: PHASE 104 R/32 -- SECONDARY MALIGNANCY TABLE (TIMING-02)`
- ✓ R/88 contains `R/31_pre_diagnosis_treatments` in validation code
- ✓ R/88 contains `R/32_secondary_malignancy_table` in validation code
- ✓ R/88 section counters updated: [34/37] for Section 31D, [35/37] for Section 31E
- ✓ R/88 former [34/35] DuckDB section is now [36/37]
- ✓ R/88 former [35/35] fixture section is now [37/37]
- ✓ R/88 SECTION 16 summary contains `TIMING-01` and `TIMING-02` labels
- ✓ R/88 Section 31D has 13 check() calls for R/31 structural validation
- ✓ R/88 Section 31E has 15 check() calls for R/32 structural validation

## Known Issues / Limitations

None identified. Both scripts follow established investigation script pattern with full defensive coding (assert_rds_exists, assert_df_valid, sentinel date guards).

## Known Stubs

None -- both scripts are complete investigations producing final xlsx outputs. No placeholder data or temporary implementations.

## Dependencies

### Upstream (Required Before Running)
- **R/26** must have run to produce `treatment_episodes.rds` (for R/31)
- **R/47** must have run to produce `confirmed_hl_cohort.rds` (for both R/31 and R/32)
- **DuckDB ingest** (R/29) must have run to populate DIAGNOSIS table (for R/32)

### Downstream (Depends on This Phase)
- None -- investigation scripts are terminal outputs consumed by team for meeting presentations

## Testing Notes

Structural validation via R/88 smoke test. Actual execution testing requires production data on HiPerGator:
- R/31 execution will produce pre_diagnosis_treatments.xlsx in output/ directory
- R/32 execution will produce secondary_malignancy_table.xlsx in output/ directory
- Both scripts log counts and summaries to console for verification

## Self-Check

### Files Created
- [x] R/31_pre_diagnosis_treatments.R exists (316 lines)
- [x] R/32_secondary_malignancy_table.R exists (406 lines)

### Commits Made
- [x] 77c602b exists (R/31 creation)
- [x] 9af4a6c exists (R/32 creation)
- [x] e842525 exists (R/88 smoke test updates)

### Structural Validation
- [x] R/31 has 7 SECTION markers (grep confirms)
- [x] R/32 has 7 SECTION markers (grep confirms)
- [x] R/88 has Section 31D with [34/37] counter
- [x] R/88 has Section 31E with [35/37] counter
- [x] R/88 has Section 32 with [36/37] counter (updated from [34/35])
- [x] R/88 has Section 33 with [37/37] counter (updated from [35/35])
- [x] R/88 SECTION 16 includes TIMING-01 and TIMING-02 labels

**Self-Check: PASSED** -- All files created, commits exist, structural validation complete.

---

**Phase:** 104-treatment-timing-investigations
**Plan:** 01
**Completed:** 2026-06-15
**Duration:** 6 minutes
**Requirements:** TIMING-01, TIMING-02
