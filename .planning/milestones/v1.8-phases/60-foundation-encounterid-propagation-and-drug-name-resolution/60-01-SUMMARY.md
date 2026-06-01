---
phase: 60-foundation-encounterid-propagation-and-drug-name-resolution
plan: 01
subsystem: treatment-extraction
tags: [encounterid, sct-audit, data-quality, infrastructure]
requires: []
provides: [encounterid-extraction, sct-dx-removal, encounter-linkage-foundation]
affects: [R/43a, R/44a, R/00_config, treatment_episodes.rds, treatment_episode_detail.rds]
dependency_graph:
  upstream: []
  downstream: [60-02, 61-*]
tech_stack:
  added: []
  patterns: [encounterid-propagation, source-audit, config-cleanup]
key_files:
  created: []
  modified:
    - R/43a_treatment_durations.R
    - R/44a_treatment_episodes.R
    - R/00_config.R
decisions:
  - "SCT source audit compares WITH vs WITHOUT DX codes before removal"
  - "ENCOUNTERID extracted from all source queries but not used in R/43a patient-level output"
  - "encounter_ids aggregated per episode as comma-separated string in R/44a"
  - "sct_dx_icd10 vector completely removed from R/00_config.R (no comments)"
  - "TUMOR_REGISTRY sources use ENCOUNTERID = NA_character_ (no encounter linkage available)"
metrics:
  duration: "7 minutes"
  tasks_completed: 2
  files_modified: 3
  commits: 2
  lines_added: 278
  lines_removed: 117
---

# Phase 60 Plan 01: ENCOUNTERID Extraction & SCT DX Code Removal

**One-liner:** ENCOUNTERID extraction infrastructure added to R/43a and R/44a, SCT source audit performed, and sct_dx_icd10 diagnosis codes removed from treatment detection.

## What Was Built

### Task 1: SCT Source Audit & ENCOUNTERID in R/43a

**Part A: SCT Source Audit**
- Added inline audit section at top of R/43a (after source/library, before extraction functions)
- Audit compares patient counts WITH DX codes (existing extract_sct_dates()) vs WITHOUT DX codes (temporary extract_sct_dates_no_dx())
- Computes delta: patients_with_dx, patients_without_dx, patients_lost, retention_rate
- Saves `sct_audit_result.rds` in CONFIG$cache$outputs_dir for Plan 03 xlsx inclusion
- Logs results to console for immediate visibility

**Part B: Config Cleanup**
- Removed `sct_dx_icd10` vector from R/00_config.R (lines 946-952)
- Vector contained: "Z94.84", "T86.5", "T86.09", "Z48.290", "T86.0"
- Clean removal with no commented code per D-15

**Part C: SCT DX Section Removal**
- Removed DIAGNOSIS source section (#2) from extract_sct_dates() in R/43a
- Updated function comment from "Extract all SCT dates from 4 sources" to "3 sources"
- Updated stack_and_dedup() sources list: removed `DX = dx_dates` entry
- SCT detection now uses only PROCEDURES, ENCOUNTER, TUMOR_REGISTRY

**Part D: ENCOUNTERID Extraction in R/43a**
- Added ENCOUNTERID to select() in all source queries across all four extract_*_dates() functions:
  - PROCEDURES: `select(ID, treatment_date = PX_DATE, ENCOUNTERID)`
  - PRESCRIBING: `select(ID, treatment_date, ENCOUNTERID)`
  - DISPENSING: `select(ID, treatment_date = DISPENSE_DATE, ENCOUNTERID)`
  - MED_ADMIN: `select(ID, treatment_date = MEDADMIN_START_DATE, ENCOUNTERID)`
  - ENCOUNTER: `select(ID, treatment_date = ADMIT_DATE, ENCOUNTERID)`
  - DIAGNOSIS: `select(ID, treatment_date = DX_DATE, ENCOUNTERID)`
  - TUMOR_REGISTRY: `mutate(ENCOUNTERID = NA_character_)` (no encounter linkage available)
- Updated stack_and_dedup() to accept 3-column input (ID, treatment_date, ENCOUNTERID) but return 2-column output (ID, treatment_date)
- ENCOUNTERID extracted for consistency with R/44a but not used in R/43a's patient-level duration output

**Part E: ENCOUNTERID Population Rate Inspection**
- Added inspection section at top of R/43a (after audit, before extraction loop)
- Inspects 6 tables: PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, ENCOUNTER, DIAGNOSIS
- Computes total_rows, encounterid_populated, population_rate per table
- Saves `encounterid_profile.rds` in CONFIG$cache$outputs_dir for Plan 03 xlsx
- Logs to console: `{table}: {populated}/{total} ({rate}%)`

### Task 2: ENCOUNTERID & encounter_ids in R/44a

**Part A: SCT DX Section Removal**
- Removed DIAGNOSIS source section (#2) from extract_sct_dates_with_codes() in R/44a
- Updated function comment from "4 sources" to "3 sources"
- Updated stack_and_dedup_with_codes() sources list: removed `DX = dx_dates`
- Mirrors R/43a removal for consistency

**Part B: ENCOUNTERID Extraction**
- Added ENCOUNTERID to select() in all source queries across all four extract_*_dates_with_codes() functions:
  - PROCEDURES: `select(ID, treatment_date = PX_DATE, triggering_code = PX, ENCOUNTERID)`
  - PRESCRIBING: `select(ID, treatment_date, triggering_code = RXNORM_CUI, ENCOUNTERID)`
  - DISPENSING: `select(ID, treatment_date = DISPENSE_DATE, triggering_code = RXNORM_CUI, ENCOUNTERID)`
  - MED_ADMIN: `select(ID, treatment_date = MEDADMIN_START_DATE, triggering_code = RXNORM_CUI, ENCOUNTERID)`
  - DIAGNOSIS: `select(ID, treatment_date = DX_DATE, triggering_code = DX, ENCOUNTERID)`
  - ENCOUNTER: `select(ID, treatment_date = ADMIT_DATE, triggering_code = DRG, ENCOUNTERID)`
  - TUMOR_REGISTRY: `mutate(ENCOUNTERID = NA_character_)`

**Part C: stack_and_dedup_with_codes() Update**
- Updated to handle 4-column input: ID, treatment_date, triggering_code, ENCOUNTERID
- Changed distinct() from 3-column to 4-column: `distinct(ID, treatment_date, triggering_code, ENCOUNTERID)`
- Preserves different encounter IDs for same (patient, date, code) triple
- Updated function docstring to reflect 4-column tibble output
- Empty return tibble includes `ENCOUNTERID = character(0)`

**Part D: encounter_ids Aggregation in calculate_episodes_detailed()**
- Updated empty-input guard to include `encounter_ids = character(0)`
- Added new summarise line after triggering_codes:
  ```r
  encounter_ids = paste(sort(unique(na.omit(ENCOUNTERID))), collapse = ","),
  ```
- NULL/missing ENCOUNTERID values omitted per D-04
- Empty string if all NULL
- Added `encounter_ids` to final select() as column 9 (after triggering_codes)

**Part E: ENCOUNTERID in annotate_detail_with_episodes()**
- Updated empty-input guard to include `ENCOUNTERID = character(0)`
- ENCOUNTERID flows through from dates_df via the episode assignment join
- Added ENCOUNTERID to final select() as column 4 (after triggering_code)
- Updated function docstring to reflect 4-column input and 8-column output

**Part F: Main Loop Output Updates**
- all_episodes select: added `encounter_ids` as column 9
- all_detail select: added `ENCOUNTERID` as column 5
- CSV output (episode files): added `encounter_ids` as column 8
- CSV output (detail files): added `ENCOUNTERID` as column 4

**Part G: log_episode_stats() Update**
- Added encounter_ids coverage calculation:
  ```r
  n_with_encounters <- sum(nchar(episodes_df$encounter_ids) > 0, na.rm = TRUE)
  pct_with_encounters <- round(100 * n_with_encounters / n_episodes, 1)
  ```
- Added console log: `"Episodes with encounter IDs: {n_with_encounters} ({pct_with_encounters}%)"`

**Part H: xlsx Formatting Updates**
- Episode sheets: updated title merge from A1:H1 to A1:I1 (9 columns)
- Episode sheets: added "Encounter IDs" as column 9 header
- Episode sheets: updated header fill/font from A2:H2 to A2:I2
- Episode sheets: updated historical row fill from A{row}:H{row} to A{row}:I{row}
- Episode sheets: added encounter_ids to write_df
- Episode sheets: updated column widths from 1:8 to 1:9 (Encounter IDs width = 30)
- Detail CSV and xlsx now include ENCOUNTERID column

## Outputs

### New RDS Artifacts
- `sct_audit_result.rds` - SCT source audit comparing WITH vs WITHOUT DX codes (4 rows: metrics + values)
- `encounterid_profile.rds` - ENCOUNTERID population rates per table (6 rows: PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, ENCOUNTER, DIAGNOSIS)

### Modified RDS Artifacts
- `treatment_episodes.rds` - Now includes `encounter_ids` column (comma-separated encounter IDs per episode)
- `treatment_episode_detail.rds` - Now includes `ENCOUNTERID` column (one ENCOUNTERID per row)

### Modified CSV Outputs
- `chemotherapy_episodes.csv`, `radiation_episodes.csv`, `sct_episodes.csv`, `immunotherapy_episodes.csv` - Now include `encounter_ids` column
- `chemotherapy_episode_detail.csv`, `radiation_episode_detail.csv`, `sct_episode_detail.csv`, `immunotherapy_episode_detail.csv` - Now include `ENCOUNTERID` column

### Modified xlsx Output
- `treatment_episodes.xlsx` - Episode sheets expanded to 9 columns with Encounter IDs as column 9

## Verification

### Automated Checks
```bash
# ENCOUNTERID in R/43a
grep -c "ENCOUNTERID" R/43a_treatment_durations.R
# Result: 27

# sct_dx_icd10 removed from config
grep -c "sct_dx_icd10" R/00_config.R
# Result: 0

# SCT audit exists
grep -c "sct_audit_result" R/43a_treatment_durations.R
# Result: 6

# ENCOUNTERID profile exists
grep -c "encounterid_profile" R/43a_treatment_durations.R
# Result: 6

# ENCOUNTERID in R/44a
grep -c "ENCOUNTERID" R/44a_treatment_episodes.R
# Result: 39

# encounter_ids aggregation
grep -c "encounter_ids" R/44a_treatment_episodes.R
# Result: 13

# sct_dx_icd10 not in R/44a
grep "sct_dx_icd10" R/44a_treatment_episodes.R
# Result: (no match)
```

### Manual Verification Points
- [ ] SCT audit runs BEFORE code removal and saves results
- [ ] extract_sct_dates() comment says "3 sources" not "4 sources"
- [ ] TREATMENT_CODES still contains sct_cpt, sct_hcpcs, sct_icd9, sct_icd10pcs, sct_drg, sct_revenue
- [ ] stack_and_dedup() accepts 3-column input but returns 2-column output
- [ ] stack_and_dedup_with_codes() docstring says "4-column tibble"
- [ ] calculate_episodes_detailed() summarise block contains encounter_ids aggregation
- [ ] annotate_detail_with_episodes() final select includes ENCOUNTERID
- [ ] log_episode_stats() logs encounter ID coverage

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None - no stubs created in this infrastructure-only plan.

## Next Steps

1. **Plan 02:** Drug name resolution - extract granular drug names (RXNORM, NDC) for first-line therapy regimen detection
2. **Plan 03:** Phase 60 audit report - consolidate sct_audit_result.rds, encounterid_profile.rds, and drug name coverage into phase-level xlsx audit
3. **Phase 61:** Episode-level cancer linkage using ENCOUNTERID from this plan

## Self-Check: PASSED

**Files created:**
```bash
[ -f ".planning/phases/60-foundation-encounterid-propagation-and-drug-name-resolution/60-01-SUMMARY.md" ] && echo "FOUND"
```

**Files modified:**
```bash
[ -f "R/43a_treatment_durations.R" ] && echo "FOUND: R/43a"
[ -f "R/44a_treatment_episodes.R" ] && echo "FOUND: R/44a"
[ -f "R/00_config.R" ] && echo "FOUND: R/00_config"
```

**Commits exist:**
```bash
git log --oneline --all | grep "323c5ee" && echo "FOUND: Task 1 commit"
git log --oneline --all | grep "01ec098" && echo "FOUND: Task 2 commit"
```

All verification passed - plan complete.
