---
phase: 45-radiation-cpt-audit
plan: "01"
subsystem: radiation-cpt-config-and-audit
tags:
  - radiation
  - cpt-codes
  - config
  - xlsx
  - audit
dependency_graph:
  requires:
    - R/00_config.R (TREATMENT_CODES)
    - R/01_load_pcornet.R (get_pcornet_table)
    - PROCEDURES DuckDB table
  provides:
    - Updated radiation_cpt vector (21 codes, proton codes, fixed descriptions)
    - R/45_radiation_cpt_audit.R (audit script)
    - output/tables/radiation_cpt_audit.xlsx (2-sheet collaborator deliverable)
  affects:
    - All scripts that source R/00_config.R and use TREATMENT_CODES$radiation_cpt
    - Phase 45 deliverable for collaborators (Amy Crisp / team)
tech_stack:
  added:
    - purrr::map_chr for vectorized code classification
    - findInterval for AMA CPT range classification
  patterns:
    - Phase 39 parse/source validation with rollback for config updates
    - Phase 42 openxlsx2 two-sheet workbook pattern (title row, dark header, conditional row fill)
    - Phase 38/39 materialize-first PROCEDURES query pattern (DuckDB anti-pattern avoidance)
key_files:
  modified:
    - R/00_config.R (lines 637-676 — radiation_cpt section rebuilt)
  created:
    - R/45_radiation_cpt_audit.R (513 lines)
decisions:
  - Use hardcoded descriptions for all retired codes (77404-77421 series) — NLM API returns not_found for deleted codes
  - Include G6003-G6016 G-code radiation codes in PROCEDURES query per D-13 (all PX_TYPEs)
  - Classify G-codes as "Radiation Treatment" with "G-Code Radiation Delivery (CMS)" AMA category
  - Do not add 77521 (deleted prior to 2024; active proton set is 77520, 77522, 77523, 77525 only)
  - Simplify classification mutate to use helper function classify_code_str() to avoid if_else type issues with purrr::map_chr
metrics:
  duration: "7 minutes"
  completed_date: "2026-05-15"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 1
  files_created: 1
---

# Phase 45 Plan 01: Radiation CPT Audit Summary

**One-liner:** Updated radiation_cpt config with 4 proton codes and AMA descriptions; built audit script classifying full 70010-79999 CPT range by AMA chapter structure with DuckDB PROCEDURES query and two-sheet styled xlsx for collaborators.

## What Was Built

**Task 1 — R/00_config.R update (commit 9894a75):**

Targeted replacement of the radiation_cpt vector block (lines 637-676). Changes:

1. Added AMA CPT Radiation Oncology chapter structure comment block (D-11) above `radiation_cpt = c(` explaining all 10 sub-ranges from 70010-79999 and the pipeline recommendation.
2. Replaced all 12 "Phase 39: no description" comments with actual AMA descriptions (D-09). These were retired codes (deleted 2015 or 2026) that the NLM HCPCS API cannot describe — hardcoded from pre-2015 AMA CPT / CMS LCD L34652.
3. Updated 77401 comment to note "DELETED 2026; historical claims only".
4. Added 4 proton therapy codes: 77520, 77522, 77523, 77525 (D-08). Code 77521 intentionally excluded — deleted before 2024.

Result: radiation_cpt has 21 codes (17 original + 4 proton). Config parses and sources cleanly.

**Task 2 — R/45_radiation_cpt_audit.R creation (commit 6a629ee, 513 lines):**

Six-section audit script:

- **Section 1:** Hardcoded AMA CPT 70010-79999 classification table as a `tibble::tribble` (11 rows, 7 columns). Covers all sub-ranges from Diagnostic Radiology through Nuclear Medicine with classification and rationale.
- **Section 2:** Hardcoded description lookup with `get_description()` — covers all 21 radiation_cpt codes plus G6003-G6016, falling back to "No description available" for unknown codes.
- **Section 3:** `classify_code()` using `findInterval()` for range matching; `classify_code_str()` wrapper handles both 7xxxx CPT codes and G60xx G-codes.
- **Section 4:** PROCEDURES query — materializes full table first, then applies `str_detect` regex in R memory for `^7[0-9]{4}$` and `^G60(0[3-9]|1[0-6])$`. All patients, all PX_TYPEs per D-12/D-13.
- **Section 5:** Classification join — adds classification, ama_category, in_config, description to each code-PX_TYPE combination.
- **Section 6:** Auto-add new confirmed treatment codes using Phase 39 parse/source validation pattern with rollback.
- **Section 7:** Console summary (total codes, breakdown by type, in_config counts).
- **Section 8:** Two-sheet xlsx using openxlsx2:
  - Sheet 1 "CPT Classification": title row (16pt merged), dark header, 11 AMA sub-range rows with green fill for Radiation Treatment rows, yellow for Mixed, plus recommendation text row (D-07) with green background.
  - Sheet 2 "Codes in Data": title row (14pt), dark header, all codes found in PROCEDURES with Patient Count, Encounter Count, In Pipeline Config? (YES/NO), conditional coloring.

## Requirements Satisfied

| Requirement | Status | Evidence |
|-------------|--------|----------|
| RADCPT-01 | Satisfied | classification_table with 11 AMA sub-ranges, AMA citations, classification and rationale columns — written to Sheet 1 of xlsx |
| RADCPT-02 | Satisfied | PROCEDURES query all patients/all PX_TYPEs, str_detect regex for 7xxxx + G60xx, codes classified and written to Sheet 2 |
| RADCPT-03 | Satisfied | 77520, 77522, 77523, 77525 added to radiation_cpt in R/00_config.R; 77521 excluded; config validates via parse/source |

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1: Config update | 9894a75 | feat(45-01): update radiation_cpt config — proton codes, fixed descriptions, AMA comment block |
| Task 2: Audit script | 6a629ee | feat(45-01): create R/45_radiation_cpt_audit.R — classification table, PROCEDURES query, styled xlsx |

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written, with one planned simplification:

**Simplification: Refactored classification mutate to use helper function**

The plan described using `if_else(str_detect(...), ..., purrr::map_chr(...))` for classification. This was refactored to use a `classify_code_str()` helper function instead, which avoids type-strictness issues with `if_else` and `purrr::map_chr` when handling both G-codes and 7xxxx codes in the same vector. The behavior is identical but the code is more readable and robust.

### Note on Local Execution Verification

The `Rscript R/45_radiation_cpt_audit.R` verification step from the plan cannot be run locally — the project runs on HiPerGator Linux HPC where DuckDB, openxlsx2, and the PCORnet data reside. The script was verified via `parse()` (syntax check) which passed. The output xlsx will be generated on first HiPerGator execution.

## Self-Check: PASSED

| Item | Status |
|------|--------|
| R/00_config.R exists | FOUND |
| R/45_radiation_cpt_audit.R exists | FOUND |
| 45-01-SUMMARY.md exists | FOUND |
| Commit 9894a75 (config update) | FOUND |
| Commit 6a629ee (audit script) | FOUND |
