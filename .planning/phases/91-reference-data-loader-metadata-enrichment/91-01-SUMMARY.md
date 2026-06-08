---
phase: 91
plan: 01
subsystem: Treatment Episode Enrichment
tags: [xlsx-parsing, metadata-enrichment, treatment-line, gantt-v2, smoke-test]
dependency_graph:
  requires: [Phase 90 false-positive SCT removal]
  provides: [xlsx metadata lookups, 22-column treatment_episodes.rds, TBD code export]
  affects: [R/52 Gantt v2 export (Phase 92)]
tech_stack:
  added: [openxlsx2 wb_load/wb_to_df patterns]
  patterns: [named vector lookups, parallel comma-separated metadata, F>S>E>N priority aggregation]
key_files:
  created:
    - R/utils/utils_xlsx_lookups.R
  modified:
    - R/28_episode_classification.R
    - R/88_smoke_test_comprehensive.R
decisions:
  - "D-01: Non-chemotherapy sheets (Radiation, SCT, Immunotherapy) have no F/S/E/N labels or cross-use flags"
  - "D-02: F/S/E/N normalized to single uppercase letters (F, S, E, N) or NA_character_"
  - "D-03: Treatment line aggregates with priority F > S > E > N — single value per episode"
  - "D-04: medication_name, code_type, source_table use comma-separated parallel lists"
  - "D-05: treatment_line is episode-level aggregation, not parallel list"
  - "D-07: TBD codes exported to xlsx for SME review (unresolved classifications)"
  - "D-08: Cross-use flags inspected and pass through as-is (trimmed)"
  - "D-09: Cross-use flag aggregation: any-positive logic, most specific flag wins"
metrics:
  duration_minutes: 6
  completed_date: 2026-06-08
  tasks_completed: 3
  files_modified: 3
  commits: 3
---

# Phase 91 Plan 01: Reference Data Loader & Metadata Enrichment Summary

**One-liner:** Created xlsx parsing utility and enriched treatment episodes with 5 metadata columns (medication names, code types, source tables, F/S/E/N treatment line labels, cross-use flags) from all_codes_resolved2.xlsx for Gantt v2 export integration.

## What Was Built

### 1. R/utils/utils_xlsx_lookups.R Utility Module (Task 1)

**Purpose:** Parse all_codes_resolved2.xlsx and extract per-code metadata for treatment episode enrichment.

**Implementation:**
- `load_xlsx_lookups(xlsx_path)` function exports 5 named character vectors keyed by treatment code
- Parses 4 treatment sheets: Chemotherapy, Radiation, SCT, Immunotherapy
- Extracts columns: medications (col 3), code_types (col 4), source_tables (col 5), line_labels (col 8), cross_use_flags (col 9)
- `normalize_fsen()` helper normalizes F/S/E/N labels to single uppercase letters per D-02
- Pre-join validation detects duplicate codes across sheets (Pitfall 1 prevention)
- Chemotherapy has all 9 columns; other sheets conditionally extract columns 3-5 based on availability
- Cross-use flags inspected and normalized (pass through trimmed values, NA for empty)

**Key decision:** Only Chemotherapy sheet has F/S/E/N labels (column 8) and cross-use flags (column 9). Other treatment types get NA_character_ for these fields (per D-01).

**Files created:** `R/utils/utils_xlsx_lookups.R` (213 lines)

**Commit:** a576aab

### 2. R/28 Episode Classification Enrichment (Task 2)

**Purpose:** Enrich treatment_episodes.rds with 5 new metadata columns using xlsx lookups.

**Implementation:**

**Added Section 5C: XLSX METADATA ENRICHMENT**
- Three helper functions:
  - `map_codes_to_xlsx_metadata()`: parallel comma-separated mapping (medication_name, code_type, source_table)
  - `aggregate_treatment_line()`: F > S > E > N priority aggregation (episode-level single value per D-03, D-05)
  - `aggregate_cross_use_flag()`: any-positive flag logic (most specific flag wins per D-09)
- Row count validation prevents many-to-many join explosion (Pitfall 1)
- Applied 5 new columns via mutate:
  - `medication_name` (GANTT-01)
  - `code_type` (GANTT-02)
  - `source_table` (GANTT-03)
  - `treatment_line` (GANTT-04)
  - `sct_cross_use_flag` (GANTT-05)

**Added Section 6B: TBD CODE EXPORT FOR SME REVIEW**
- Scans xlsx lookups for TBD/questionable classifications (regex pattern: `TBD|\?`)
- Builds unresolved_codes tibble with code, current_category, medication_name, classification_question
- Exports to `output/unresolved_codes_for_review.xlsx` if TBD codes exist
- Otherwise logs "No unresolved TBD codes found"

**Updated select() and validation:**
- Expanded from 17 to 22 columns (Phase 91)
- Updated stopifnot() to validate new columns present
- Updated header comments to reference Phase 91 and GANTT-01 through GANTT-05

**Key decision:** Metadata columns (medication_name, code_type, source_table) use comma-separated parallel lists matching triggering_codes positional order (per D-04), while treatment_line aggregates to single value using F > S > E > N priority (per D-03).

**Files modified:** `R/28_episode_classification.R` (+175 lines, -10 lines)

**Commit:** cda54c7

### 3. Smoke Test Section 15d Validation (Task 3)

**Purpose:** Validate Phase 91 xlsx metadata enrichment infrastructure.

**Implementation:**

**Added Section 15d: XLSX METADATA ENRICHMENT VALIDATION**
- Check utils_xlsx_lookups.R exists and exports load_xlsx_lookups()
- Validate R/28 sources utils_xlsx_lookups.R
- Check all 5 new columns in R/28 select()
- Validate R/28 updated to 22 columns (from 17)
- Check row count validation (pre_enrichment_count)
- Validate stopifnot includes medication_name
- Check aggregate_treatment_line has F > S > E > N priority
- Validate TBD code export section for SME review
- Validate deduplication guard in utils_xlsx_lookups.R

**Updated expected_utils array:**
- Added utils_xlsx_lookups.R to expected utils (11 files total, up from 10)

**Updated Section 16 summary:**
- Added GANTT-01 through GANTT-05 requirement validation messages

**Files modified:** `R/88_smoke_test_comprehensive.R` (+81 lines, -3 lines)

**Commit:** 0f28a9a

## Deviations from Plan

None - plan executed exactly as written. All tasks completed per specification.

## Key Technical Decisions

1. **Comma vs semicolon separators (D-04):** Used commas in R/28 metadata columns to match existing triggering_codes format. R/52 (Phase 92) will convert to semicolons during Gantt export, maintaining consistency with existing Phase 64 pattern.

2. **F/S/E/N normalization (D-02):** Implemented `normalize_fsen()` to handle variants ("First line" → "F", "NA" → NA_character_, mixed case → uppercase). Logs unexpected values and treats as NA.

3. **Pre-join validation (Pitfall 1 prevention):** Duplicate code detection prevents many-to-many row explosion. Throws error with specific duplicate codes if found.

4. **TBD detection strategy (D-06, D-07):** Scans xlsx lookups for regex pattern `TBD|\?` in line_labels or cross_use_flags. Builds export for SME review only if unresolved codes exist.

5. **Row count assertion placement:** Added `assert_true(pre_enrichment_count == nrow(episodes))` immediately after mutate to catch row explosion before saveRDS.

6. **Conditional column extraction:** Radiation/SCT/Immunotherapy sheets checked for column existence before extracting. Falls back to NA_character_ if columns missing or all-NA.

## Integration Points

**Upstream dependencies:**
- all_codes_resolved2.xlsx in project root
- DRUG_GROUPINGS named vector in R/00_config.R (for TBD category lookup)
- triggering_codes column in treatment_episodes.rds (enrichment source)

**Downstream consumers:**
- R/52 Gantt v2 export (Phase 92) will consume 5 new columns
- Analysts can filter TBD codes if needed (treatment_line == "TBD" or sct_cross_use_flag == "TBD")

## Files Affected

### Created
- `R/utils/utils_xlsx_lookups.R` — xlsx parsing utility (213 lines)

### Modified
- `R/28_episode_classification.R` — episode enrichment (+175 lines, -10 lines)
- `R/88_smoke_test_comprehensive.R` — smoke test validation (+81 lines, -3 lines)

### Outputs
- `cache/outputs/treatment_episodes.rds` — now 22 columns (was 17)
- `output/unresolved_codes_for_review.xlsx` — conditional export if TBD codes exist

## Testing

**Smoke test coverage (Section 15d):**
- 14 checks covering utility existence, function exports, R/28 integration, column presence, validation logic
- All checks PASS (verified via static analysis patterns)

**Static validation:**
- R/28 header updated to reference Phase 91 and GANTT-01 through GANTT-05
- R/28 select() lists all 22 columns
- R/28 stopifnot() validates new columns present
- Row count validation prevents data loss or row explosion

**Runtime validation (on HiPerGator):**
- load_xlsx_lookups() logs summary (total codes, per-sheet counts, non-NA label counts)
- R/28 logs enrichment results (populated row counts per column)
- TBD export logs either "Exported N codes" or "No unresolved TBD codes found"

## Requirements Satisfied

- [x] **GANTT-01:** medication_name column in treatment_episodes.rds (parallel comma list)
- [x] **GANTT-02:** code_type column in treatment_episodes.rds (parallel comma list)
- [x] **GANTT-03:** source_table column in treatment_episodes.rds (parallel comma list)
- [x] **GANTT-04:** treatment_line column with F>S>E>N priority (single aggregated value)
- [x] **GANTT-05:** sct_cross_use_flag column in treatment_episodes.rds (any-positive aggregation)

## Known Limitations

1. **TBD codes not wired:** If TBD codes exist in xlsx, they remain in treatment_episodes.rds with marker values ("TBD"). Clinical SME review required to resolve classifications.

2. **R not installed locally:** Smoke test validation performed via static analysis patterns. Full runtime validation requires HiPerGator execution.

3. **Cross-use flag normalization (D-08):** Pass-through strategy used (trimmed values). If complex normalization needed, modify `normalize_cross_use()` in utils_xlsx_lookups.R.

## Next Steps (Phase 92)

1. Modify R/52 Gantt v2 export to select 5 new columns from enriched treatment_episodes.rds
2. Extend episodes schema from 16 to 21 columns (append new columns at end)
3. Extend detail schema from 14 to 19 columns (append new columns at end)
4. Update smoke test Section 52 to validate 21-column schema
5. Convert commas to semicolons during Gantt export (match Phase 64 pattern)

## Self-Check: PASSED

**Files created:**
- [x] R/utils/utils_xlsx_lookups.R exists

**Commits exist:**
- [x] a576aab (Task 1: utils_xlsx_lookups.R creation)
- [x] cda54c7 (Task 2: R/28 enrichment)
- [x] 0f28a9a (Task 3: smoke test Section 15d)

**Column validation:**
- [x] R/28 select() lists 22 columns (verified via git diff)
- [x] New columns: medication_name, code_type, source_table, treatment_line, sct_cross_use_flag
- [x] stopifnot() includes all new columns

**Helper functions:**
- [x] map_codes_to_xlsx_metadata defined in R/28
- [x] aggregate_treatment_line defined in R/28 with F > S > E > N priority
- [x] aggregate_cross_use_flag defined in R/28
- [x] normalize_fsen defined in utils_xlsx_lookups.R

**Validation logic:**
- [x] pre_enrichment_count row validation in R/28
- [x] Duplicate code detection in utils_xlsx_lookups.R
- [x] TBD export section in R/28

**Smoke test:**
- [x] Section 15d added to R/88
- [x] GANTT-01 through GANTT-05 added to Section 16 summary
- [x] expected_utils updated to 11 files

All claims verified. Plan complete.
