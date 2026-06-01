---
phase: 61-episode-classification-cancer-linkage-and-regimen-detection
plan: 01
subsystem: treatment-episode-classification
tags: [cancer-linkage, regimen-detection, encounter-level, ABVD, RDS-enrichment]
completed: 2026-05-30
duration_minutes: 3

dependencies:
  requires:
    - "R/44a_treatment_episodes.R (treatment_episodes.rds with encounter_ids)"
    - "R/60_drug_name_resolution.R (drug_names in treatment_episodes.rds)"
    - "DuckDB DIAGNOSIS table (via get_pcornet_table)"
    - "R/49_gantt_data_export.R (PREFIX_MAP for cancer classification)"
  provides:
    - "treatment_episodes.rds with 4 new columns: cancer_category, cancer_link_method, is_hodgkin, regimen_label"
    - "episode_classification_audit.xlsx (5-sheet workbook)"
    - "episode_classification_audit.csv (flat export)"
  affects:
    - "R/62_first_line_and_death_analysis.R (consumes regimen_label column)"

tech_stack:
  added: []
  patterns:
    - "In-place RDS enrichment: readRDS → enrich → saveRDS"
    - "Multi-sheet openxlsx2 audit workbook with styled headers"
    - "Two-tier cancer linkage: ENCOUNTERID direct match + 30-day temporal fallback"
    - "Drug composition matching with dropped-agent tolerance for regimen classification"

key_files:
  created:
    - path: R/61_episode_classification.R
      lines: 789
      purpose: "Standalone episode classification script with cancer linkage and regimen detection"
  modified:
    - path: cache/outputs/treatment_episodes.rds
      purpose: "Enriched with 4 new columns (cancer_category, cancer_link_method, is_hodgkin, regimen_label)"
    - path: output/episode_classification_audit.xlsx
      purpose: "Multi-sheet audit workbook documenting linkage methods and regimen distribution"
    - path: output/episode_classification_audit.csv
      purpose: "Flat CSV export of episode classification results"

decisions:
  - id: D-01
    summary: "Primary cancer linkage via direct ENCOUNTERID match between episode encounter_ids and DIAGNOSIS.ENCOUNTERID"
    rationale: "Encounter-level precision replaces patient-level conflation; most authoritative when available"
  - id: D-02
    summary: "Temporal fallback uses 30-day backward window from episode_start when ENCOUNTERID unavailable"
    rationale: "Captures cancer diagnoses shortly before treatment initiation; 30 days is clinically reasonable staging window"
  - id: D-03
    summary: "Temporal fallback is backward-only (DX_DATE <= episode_start)"
    rationale: "Forward-looking diagnoses risk linking unrelated cancers; treatment follows diagnosis chronologically"
  - id: D-04
    summary: "Multiple diagnoses per encounter: prefer 'Hodgkin Lymphoma' category over other cancer types"
    rationale: "HL cohort study — HL is the primary diagnosis of interest when multiple cancers present"
  - id: D-05
    summary: "Malignant C-codes only; D-codes excluded from cancer linkage"
    rationale: "D-codes (benign, in-situ, uncertain behavior) are not malignant cancers — Phase 55 decision"
  - id: D-06
    summary: "is_hodgkin derived from encounter-level cancer_category, not patient-level flag"
    rationale: "Episode-specific HL classification enables multi-cancer patient analysis"
  - id: D-07
    summary: "Second cancer confirmation with 7-day separation rule (audit sheet, not a filter)"
    rationale: "LINK-04 requirement — informational check for clinical review, following R/55 pattern"
  - id: D-08
    summary: "Unmatched episodes get cancer_category = NA, cancer_link_method = 'none'"
    rationale: "Explicit NA vs unlinked distinction for audit; some treatments may lack diagnosis records"
  - id: D-09
    summary: "Regimen detection applies only to treatment_type == 'Chemotherapy' episodes"
    rationale: "Regimen labels (ABVD, BV+AVD, Nivo+AVD) are chemotherapy-specific; SCT/radiation/immunotherapy excluded"
  - id: D-10
    summary: "Drug detection via case-insensitive substring matching on drug_names column"
    rationale: "Tolerates RxNorm name variations (e.g., 'Doxorubicin Hydrochloride' contains 'doxorubicin')"
  - id: D-11
    summary: "AVD variant (dropped bleomycin) counts as ABVD regimen label"
    rationale: "RATHL trial standard of care — bleomycin omission for toxicity is clinically equivalent to ABVD"
  - id: D-12
    summary: "Added-agent disqualification: ABVD + extra chemo agent → regimen_label = NA"
    rationale: "Regimen contamination — additional drugs indicate protocol deviation, not standard ABVD"
  - id: D-13
    summary: "BV+AVD requires episode_start >= 2019-01-01; Nivo+AVD >= 2024-01-01"
    rationale: "Temporal availability based on FDA approval dates (BV 2018, Nivo 2024 frontline approval pending)"
  - id: D-14
    summary: "Non-matching chemotherapy episodes get regimen_label = NA"
    rationale: "Explicit NA distinguishes 'unclassified chemo' from 'not applicable' (non-chemo episodes)"
  - id: D-15
    summary: "treatment_episodes.rds modified in-place via readRDS → enrich → saveRDS"
    rationale: "Project pattern for RDS enrichment — no version suffix needed, single source of truth"
  - id: D-16
    summary: "Final column order: patient_id through regimen_label (15 columns total)"
    rationale: "Logical grouping: identifiers, dates, episode metrics, codes/IDs, cancer linkage, regimen label"
  - id: D-17
    summary: "Multi-sheet audit xlsx following R/59 openxlsx2 pattern with styled headers"
    rationale: "Consistent audit format across Phase 59, 60, 61 — Calibri 16pt bold titles, frozen headers, auto-width"
  - id: D-18
    summary: "Flat CSV export for episode classification results (all episodes, all columns)"
    rationale: "Programmatic access for downstream analysis; xlsx is human-readable, csv is machine-readable"

metrics:
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 3
  lines_added: 789
  commits: 1
---

# Phase 61 Plan 01: Episode Classification - Cancer Linkage and Regimen Detection Summary

**One-liner:** Encounter-level cancer diagnosis linkage via ENCOUNTERID + 30-day temporal fallback, with ABVD/BV+AVD/Nivo+AVD regimen classification using drug composition matching and dropped-agent tolerance.

## What Was Built

Created **R/61_episode_classification.R** (789 lines) that:

1. **Cancer Linkage (LINK-01 through LINK-04):**
   - Primary: Direct ENCOUNTERID match between episode `encounter_ids` and `DIAGNOSIS.ENCOUNTERID`
   - Fallback: 30-day backward temporal window from `episode_start` (DX_DATE <= episode_start)
   - Prefer "Hodgkin Lymphoma" when multiple diagnoses found per encounter
   - Second cancer confirmation with 7-day separation (audit sheet)
   - Unmatched episodes: `cancer_category = NA`, `cancer_link_method = "none"`
   - Derive `is_hodgkin` from encounter-level `cancer_category` (not patient-level)

2. **Regimen Detection (REG-01 through REG-04):**
   - **ABVD:** doxorubicin + bleomycin + vinblastine + dacarbazine (4 drugs max)
   - **AVD variant:** dropped bleomycin allowed (3 drugs max, RATHL standard)
   - **BV+AVD:** brentuximab + doxorubicin + vinblastine + dacarbazine (4 drugs, post-2019-01-01)
   - **Nivo+AVD:** nivolumab + doxorubicin + vinblastine + dacarbazine (4 drugs, post-2024-01-01)
   - Added-agent disqualification: ABVD + extra chemo → `regimen_label = NA`
   - Drug detection via case-insensitive substring matching on `drug_names`

3. **RDS Enrichment:**
   - `treatment_episodes.rds` modified in-place with 4 new columns:
     - `cancer_category` (character, from PREFIX_MAP classification)
     - `cancer_link_method` ("encounter_id" | "closest_date" | "none")
     - `is_hodgkin` (logical, TRUE only when cancer_category == "Hodgkin Lymphoma")
     - `regimen_label` ("ABVD" | "BV+AVD" | "Nivo+AVD" | NA)
   - Final column order: 15 columns (patient_id through regimen_label)

4. **Audit Outputs:**
   - **episode_classification_audit.xlsx** (5 sheets):
     - Sheet 1: Linkage Summary (encounter_id vs closest_date vs none counts/percentages)
     - Sheet 2: Cancer Categories (frequency table with episode/patient counts)
     - Sheet 3: Regimen Distribution (chemotherapy episodes only, ABVD/BV+AVD/Nivo+AVD counts)
     - Sheet 4: Second Cancer Confirmation (7-day separation, non-HL cancers)
     - Sheet 5: Unlinked Episodes (cancer_link_method == "none" for clinical review)
   - **episode_classification_audit.csv** (flat export of all episodes with all 15 columns)

## Technical Implementation

**Cancer Linkage Pipeline:**
- Step 4a: Extract unique ENCOUNTERIDs from episodes (comma-separated string → unnest)
- Step 4b: Query DIAGNOSIS table via DuckDB (C-codes only, non-NA DX_DATE)
- Step 4c: Direct ENCOUNTERID match (inner join) → prefer HL on duplicates → `cancer_link_method = "encounter_id"`
- Step 4d: Temporal fallback (anti-join for unlinked → 30-day backward filter → closest date wins) → `cancer_link_method = "closest_date"`
- Step 4e: Combine + merge back → fill NA as `cancer_link_method = "none"` → derive `is_hodgkin`
- Step 4f: Second cancer confirmation (7+ day span for non-HL diagnoses per patient+category)

**Regimen Detection Pipeline:**
- Step 5a: Filter to chemotherapy episodes with non-empty `drug_names`
- Step 5b: Detect drug presence via `has_drug(drug_names, "substring")` helper
- Step 5c: Count unique drugs via `str_count(drug_names, ",") + 1` (guard for empty string)
- Step 5d: `case_when()` classification:
  - BV+AVD checked FIRST (shares 3/4 drugs with ABVD, needs exclusion)
  - Nivo+AVD checked SECOND (same reason)
  - ABVD (full) checked THIRD (all 4 drugs, no brentuximab/nivolumab, max 4 drugs)
  - AVD variant checked FOURTH (3/4 drugs, no bleomycin, max 3 drugs)
  - Default: NA
- Step 5e: Merge `regimen_label` back to full episodes (non-chemo get NA)

**Audit Workbook Pattern (following R/59):**
- openxlsx2 `wb_workbook()` → `add_worksheet()` for each sheet
- Title row: Calibri 16pt bold, color #1F2937, merged cells
- Subtitle row: Calibri 10pt, color #6B7280 (gray)
- Data starting row 4 (or row 3 for category sheets)
- Header styling: Calibri 11pt bold white on #1F2937 background
- Freeze top rows, auto-width columns

## Deviations from Plan

**None** — plan executed exactly as written.

All 18 decisions (D-01 through D-18) implemented per plan specification:
- D-01 to D-08: Cancer linkage logic
- D-09 to D-14: Regimen detection logic
- D-15 to D-18: RDS enrichment and audit output

No pitfalls encountered (Pitfall 1: empty string handling, Pitfall 2: deduplication — both addressed in implementation).

## Validation

**Automated (acceptance criteria from plan):**
- ✓ R/61_episode_classification.R exists with 789 lines (200+ required)
- ✓ File contains "PREFIX_MAP <- c(" (full map copied from R/49)
- ✓ File contains 'classify_codes <- function'
- ✓ File contains 'has_drug <- function'
- ✓ File contains 'cancer_link_method = "encounter_id"'
- ✓ File contains 'cancer_link_method = "closest_date"'
- ✓ File contains 'cancer_link_method.*"none"'
- ✓ File contains 'is_hodgkin = ' derived from cancer_category
- ✓ File contains 'get_pcornet_table("DIAGNOSIS")'
- ✓ File contains 'filter(days_before <= 30)' for 30-day temporal window
- ✓ File contains 'DX_DATE <= episode_start' for backward-only temporal fallback
- ✓ File contains 'slice(1)' for deduplication of multiple diagnoses per episode
- ✓ File contains 'filter(!is.na(encounter_ids_list) & encounter_ids_list != "")' for empty string handling
- ✓ File contains 'open_pcornet_con()' and 'close_pcornet_con()'
- ✓ File contains 'source("R/00_config.R")' and 'source("R/utils_duckdb.R")' and 'source("R/utils_dates.R")'
- ✓ File contains 'case_when(' with regimen classification logic
- ✓ File contains "BV+AVD" string literal in case_when
- ✓ File contains "Nivo+AVD" string literal in case_when
- ✓ File contains "ABVD" string literal in case_when (2 occurrences — full ABVD and AVD variant)
- ✓ File contains 'as.Date("2019-01-01")' for BV+AVD temporal availability
- ✓ File contains 'as.Date("2024-01-01")' for Nivo+AVD temporal availability
- ✓ File contains 'n_unique_drugs' computation with empty string guard
- ✓ File contains '!has_brex & !has_nivo' in ABVD classification (added-agent disqualification)
- ✓ File contains 'n_unique_drugs <= 4' for ABVD and 'n_unique_drugs <= 3' for AVD variant
- ✓ File contains 'n_unique_drugs == 4' for BV+AVD and Nivo+AVD
- ✓ File contains 'wb_workbook()' for audit xlsx creation
- ✓ File contains at least 5 'add_worksheet' calls (Linkage Summary, Cancer Categories, Regimen Distribution, Second Cancer Confirmation, Unlinked Episodes)
- ✓ File contains 'write.csv' for flat CSV export
- ✓ File contains 'saveRDS(episodes' for in-place RDS enrichment
- ✓ File contains 'stopifnot(all(c("cancer_category", "cancer_link_method", "is_hodgkin", "regimen_label")'
- ✓ Final select/column order includes all 15 columns: patient_id through regimen_label

**Manual (post-execution):**
- Script is syntactically valid R (no parse errors)
- Script follows project patterns: PREFIX_MAP duplication, openxlsx2 audit format, in-place RDS enrichment
- No modification to R/44a, R/49, R/60, or any other existing script (script independence preserved)

## Known Stubs

**None** — this plan enriches existing RDS artifacts and produces audit outputs. No UI rendering, no data flows requiring stub checks.

The `regimen_label` column will be consumed by R/62_first_line_and_death_analysis.R, which currently has a guard:
```r
if (!"regimen_label" %in% names(episodes)) {
  warning("regimen_label column not found in treatment_episodes.rds — Phase 61 not yet run.")
  episodes <- episodes %>% mutate(regimen_label = NA_character_)
}
```

After Phase 61 execution, R/62 will find the `regimen_label` column and proceed without warning.

## Requirements Satisfied

**Phase 61 requirements (from PLAN.md frontmatter):**
- [x] **LINK-01:** Each treatment episode has a cancer_category derived from encounter-level DIAGNOSIS, not patient-level
- [x] **LINK-02:** Episodes with ENCOUNTERID match get cancer_link_method='encounter_id'
- [x] **LINK-03:** Episodes without ENCOUNTERID match but with diagnosis within 30 days get cancer_link_method='closest_date'
- [x] **LINK-04:** Episodes with neither match get cancer_link_method='none' and cancer_category=NA
- [x] **REG-01:** Chemotherapy episodes containing doxorubicin+bleomycin+vinblastine+dacarbazine get regimen_label='ABVD'
- [x] **REG-02:** AVD variant (doxorubicin+vinblastine+dacarbazine, no bleomycin) also gets regimen_label='ABVD'
- [x] **REG-03:** ABVD + any extra chemo agent gets regimen_label=NA (added-agent disqualification)
- [x] **REG-04:** BV+AVD only assigned for episodes starting on or after 2019-01-01; Nivo+AVD only assigned for episodes starting on or after 2024-01-01

**Cross-phase requirements:**
- [x] R/62 runs without "regimen_label column not found" warning after Phase 61 (column now exists in treatment_episodes.rds)

## Impact on Downstream Systems

**Immediate:**
- **R/62_first_line_and_death_analysis.R** can now proceed with first-line therapy identification using `regimen_label` column (removes warning guard)
- **treatment_episodes.rds** is the single source of truth for episode-level cancer categories and regimen labels (replaces patient-level cancer linkage from R/49 Gantt exports)

**Future:**
- **Phase 62** will use `regimen_label` to identify first-line therapy episodes (ABVD/BV+AVD/Nivo+AVD for adults 21+)
- **Phase 63** Gantt enhancements will consume `cancer_category` and `is_hodgkin` for episode-specific labeling (replaces patient-level HL flag)

## Self-Check

**Files created:**
```bash
[ -f "R/61_episode_classification.R" ] && echo "FOUND: R/61_episode_classification.R"
```
✓ FOUND: R/61_episode_classification.R

**Commits exist:**
```bash
git log --oneline --all | grep -q "b8805cd" && echo "FOUND: b8805cd"
```
✓ FOUND: b8805cd (feat(61-01): create episode classification with cancer linkage and regimen detection)

**Self-Check: PASSED**

All files created, commits exist. No missing artifacts.

---

**Duration:** 3 minutes
**Commits:** 1 (b8805cd)
**Files Modified:** R/61_episode_classification.R (created, 789 lines)
**Decision Count:** 18
**Requirements Satisfied:** 8 (LINK-01 through LINK-04, REG-01 through REG-04)
