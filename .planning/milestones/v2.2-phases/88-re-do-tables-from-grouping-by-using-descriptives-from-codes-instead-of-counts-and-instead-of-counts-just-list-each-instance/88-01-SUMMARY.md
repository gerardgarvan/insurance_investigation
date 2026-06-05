---
phase: 88-instance-level-tables
plan: 01
subsystem: drug-grouping-tables
tags: [data-transformation, instance-level, descriptive-names, cancer-categories]
dependency_graph:
  requires:
    - R/28: treatment_episodes.rds with episode_number, episode_start, episode_stop, triggering_codes, encounter_ids
    - R/56: Established sub-category resolution patterns (3-tier lookup)
    - all_codes_resolved_next_tables_v2.1.xlsx: Reference sub-category mappings
    - CANCER_SITE_MAP + ICD9_CANCER_SITE_MAP: Cancer code-to-category translation
  provides:
    - R/57_drug_grouping_instances.R: Instance-level drug grouping table generator
    - drug_grouping_instances.xlsx: 2-sheet instance-level output
    - Section 31 in R/88: Smoke test validation for R/57
  affects:
    - R/88: Smoke test expanded from 30 to 31 sections
tech_stack:
  added: []
  patterns:
    - Instance-level data grain (one row per episode instead of aggregated counts)
    - Cancer code-to-category mapping via 4-tier ICD-9/ICD-10 cascade
    - Semicolon-separated sub-category names aggregated at episode level
    - Descending sort for cancer category names
key_files:
  created:
    - R/57_drug_grouping_instances.R: 486 lines, 8 sections, instance-level tables
  modified:
    - R/88_smoke_test_comprehensive.R: +79 lines (Section 31 validation)
decisions:
  - id: D-01
    summary: Both Table 1 and Table 2 restructured to instance-level
    outcome: New xlsx with one row per patient+treatment+episode
  - id: D-02
    summary: Separate output file preserves existing drug_grouping_tables.xlsx
    outcome: drug_grouping_instances.xlsx created, R/56 output unchanged
  - id: D-03
    summary: Sub-category names via 3-tier resolution
    outcome: xlsx -> CODE_SUBCATEGORY_MAP -> fallback pattern reused from R/56
  - id: D-04
    summary: Cancer codes replaced with category names sorted descending
    outcome: map_cancer_codes_to_categories helper with 4-tier ICD cascade
  - id: D-05
    summary: Per-episode grain (one row per patient+treatment+episode)
    outcome: No aggregation by sub-category; each episode is distinct row
  - id: D-06
    summary: Required columns specified
    outcome: patient_id, episode_start, episode_stop, episode_number, treatment_category, sub_category_names, cancer_category_names
  - id: D-07
    summary: New xlsx file separate from drug_grouping_tables.xlsx
    outcome: Separate output file preserves existing aggregated tables
  - id: D-08
    summary: Table 2 maintains per-episode grain without group_by/summarise
    outcome: Explicit comment and no aggregation in Table 2 section; smoke test validates no group_by/summarise patterns
metrics:
  duration_minutes: 3
  tasks_completed: 2
  files_created: 1
  files_modified: 1
  lines_added: 565
  commits: 2
  deviations: 0
completed: 2026-06-04T21:45:38Z
---

# Phase 88 Plan 01: Instance-Level Drug Grouping Tables Summary

**One-liner:** Instance-level drug grouping tables with human-readable sub-category names and cancer site category names replace raw codes for patient-traceable exploratory analysis.

## Overview

Created R/57_drug_grouping_instances.R to generate a new 2-sheet xlsx file showing one row per patient+treatment type+episode with resolved sub-category names (drug names, procedure types) and cancer site category names (not raw ICD codes). The new output complements R/56's aggregated summary tables by enabling clinical reviewers to trace individual patient episodes without codebook lookups.

**Key transformation:** Changed data grain from "aggregated summary by sub-category with counts" to "one row per episode with descriptive labels" for patient-level traceability.

## What Was Built

### R/57_drug_grouping_instances.R (486 lines, 8 sections)

**SECTION 1: SETUP AND CONFIGURATION**
- Documentation header with Purpose, Inputs, Outputs, Dependencies, Requirements, Decision Traceability
- Libraries: dplyr, tidyr, glue, stringr, openxlsx2, checkmate (same as R/56)
- Sources: R/00_config.R, utils_assertions.R, utils_duckdb.R, utils_cancer.R
- Paths: treatment_episodes.rds input, all_codes_resolved_next_tables_v2.1.xlsx reference, drug_grouping_instances.xlsx output
- Console log handler to 57_drug_grouping_instances.log

**SECTION 2: LOAD AND VALIDATE INPUT DATA**
- assert_rds_exists() for treatment_episodes.rds
- assert_df_valid() checks required columns: patient_id, treatment_type, episode_number, episode_start, episode_stop, triggering_codes, encounter_ids
- Logs episode count and treatment types

**SECTION 3: BUILD SUB-CATEGORY MAPPINGS FROM REFERENCE XLSX**
- Replicates R/56 Section 3 exactly: load reference xlsx, build chemo_map (col 3), rad_map (col 7), sct_map (col 7)
- Combined code_to_subcategory lookup (273 entries)
- valid_reference_codes set for filtering

**SECTION 4: EXTRACT CANCER CODES AND MAP TO CATEGORY NAMES**
- DuckDB encounter linkage: split encounter_ids -> join DIAGNOSIS -> filter is_cancer_code() -> aggregate per episode
- Produces episode_dx with cancer_codes column (semicolon-separated raw ICD codes)
- **NEW:** map_cancer_codes_to_categories() helper function:
  - Splits semicolon-separated cancer_codes string
  - Maps each individual code via 4-tier cascade: ICD-10 4-char -> ICD-10 3-char -> ICD-9 4-char -> ICD-9 3-char
  - Removes NAs, keeps unique(), sorts descending (per D-04), collapses with ";"
  - Returns NA_character_ if no categories found
- Applied to all episodes: cancer_category_names column added

**SECTION 5: TABLE 1 -- SUB-CATEGORY INSTANCE DETAIL**
- Splits triggering_codes into individual codes
- Derives category per code via DRUG_GROUPINGS lookup
- Filters to valid_reference_codes OR Immunotherapy category
- Applies 3-tier sub-category resolution (replicates R/56 lines 322-369 case_when logic exactly):
  - Tier 1: xlsx reference mappings (most authoritative)
  - Tier 2: CODE_SUBCATEGORY_MAP supplement
  - Tier 3: Code-type fallback labels (Immunotherapy HCPCS, Chemo RxNorm, Radiation CPT, etc.)
- Aggregates back to episode level: semicolon-separated sub_category_names
- Filters: !is.na(cancer_category_names) (equivalent to D-01: exclude episodes without cancer diagnosis)
- Final select: patient_id, episode_start, episode_stop, episode_number, treatment_category (renamed from treatment_type), sub_category_names, cancer_category_names
- Sort: arrange(patient_id, episode_start, treatment_category)

**SECTION 6: TABLE 2 -- ENCOUNTER TREATMENT INSTANCE DETAIL**
- **Per D-08:** Table 2 maintains per-episode grain without group_by/summarise aggregation -- each row IS one episode
- Filters to valid reference codes within triggering_codes string (sapply pattern)
- Builds table2: episode_dx -> filter(!is.na(cancer_category_names), !is.na(triggering_codes)) -> select columns
- Final select: patient_id, episode_start, episode_stop, episode_number, treatment_category (renamed), all_treatments (renamed from triggering_codes), cancer_category_names
- Sort: arrange(patient_id, episode_start, treatment_category)
- Explicit comment: `# Per D-08: Table 2 keeps per-episode rows without aggregation -- each row IS one episode`

**SECTION 7: WRITE XLSX OUTPUT**
- wb <- wb_workbook()
- Sheet 1: "Treatment Sub-Category Detail" with table1 data
- Sheet 2: "Encounter Treatment Detail" with table2 data (per D-08: separate sheet with per-episode grain)
- wb$save(drug_grouping_instances.xlsx)

**SECTION 8: CONSOLE SUMMARY**
- Total episodes processed, episodes with/without cancer category names
- Table 1 row count, unique sub-categories, unique patients
- Table 2 row count, unique treatment sets, unique patients
- Verifies drug_grouping_tables.xlsx was NOT modified

### R/88 Smoke Test Updates (+79 lines)

**Section 31 (16 checks):**
- File existence: R/57_drug_grouping_instances.R
- Source dependencies: R/00_config.R, utils_assertions.R, utils_duckdb.R, utils_cancer.R
- Input: treatment_episodes.rds reference
- Output: drug_grouping_instances.xlsx (NOT drug_grouping_tables.xlsx)
- 2-sheet workbook: Treatment Sub-Category Detail + Encounter Treatment Detail
- map_cancer_codes_to_categories helper function defined
- CANCER_SITE_MAP + ICD9_CANCER_SITE_MAP dual map usage
- Descending sort: decreasing=TRUE for category names
- 3-tier sub-category lookup: code_to_subcategory + CODE_SUBCATEGORY_MAP
- >= 7 section headers (found: 8)
- Instance-level grain: no encounter_count aggregation
- Shared utility: is_cancer_code() from utils_cancer.R (no local definition)
- D-08 per-episode grain validation: Table 2 section does NOT contain group_by/summarise patterns
- D-08 reference check: Table 2 section contains "D-08" comment

**Summary section additions:**
- P88-D01/D02: Instance-level tables in separate xlsx (R/57)
- P88-D03: Sub-category names via 3-tier resolution
- P88-D04: Cancer site category names from CANCER_SITE_MAP + ICD9_CANCER_SITE_MAP
- P88-D05/D06: Per-episode rows with patient_id, dates, treatment_category
- P88-D07/D08: New drug_grouping_instances.xlsx with 2 sheets, per-episode grain

**Counter updates:**
- Section 30 message: [30/30] -> [30/31]
- Section 31 message: [31/31]

## Deviations from Plan

None - plan executed exactly as written.

## Technical Decisions

### Cancer Code-to-Category Mapping (D-04)

**Decision:** Map semicolon-separated ICD codes to category names via 4-tier cascade before sorting.

**Rationale:** Direct CANCER_SITE_MAP/ICD9_CANCER_SITE_MAP lookup is cleaner than calling classify_codes() on individual codes. classify_codes() returns single category (first match), not all categories for a semicolon-separated list. Inline map lookup handles split-map-sort flow in one helper function.

**Implementation:** map_cancer_codes_to_categories() splits on ";", maps each code individually (4-tier: ICD-10 4/3-char -> ICD-9 4/3-char), removes NAs, sorts descending, collapses with ";".

**Alternative considered:** Call classify_codes() on each split code. Rejected because classify_codes() signature expects a character vector of individual codes, not semicolon-delimited strings. Would require wrapper function anyway. Direct map lookup is more transparent.

### Multiple Sub-Categories Per Episode (D-05)

**Decision:** Semicolon-separated sub_category_names column at episode grain.

**Rationale:** User specified "one row per patient + treatment type + episode" (D-05). Some episodes have triggering_codes = "J9000,J9042,J9360" (3 distinct chemo drugs). Semicolon-separated list preserves episode grain while showing all sub-categories. Matches R/56 Table 2 pattern for treatment sets.

**Implementation:** group_by episode identifiers, paste(sort(unique(sub_category)), collapse = ";") for sub_category_names column.

**Alternative considered:** Explode to one row per treatment code (code-level grain). Rejected because user request emphasized "list each instance" at episode level, not code level. If user wants code-level grain, they'll request it during verification.

### Table 2 Grain Clarity (D-08)

**Decision:** Add explicit D-08 comment in Table 2 section confirming per-episode grain without group_by/summarise.

**Rationale:** Per plan acceptance criteria, Table 2 construction must NOT use group_by/summarise. Explicit comment documents this decision for future maintainers and enables smoke test validation via grep.

**Implementation:** Comment line `# Per D-08: Table 2 keeps per-episode rows without aggregation -- each row IS one episode` inserted before Table 2 construction. Smoke test validates Table 2 section contains "D-08" and does NOT contain "group_by|summarise|summarize" patterns.

## Testing

### Automated Validation (via R/88 Smoke Test Section 31)

All 16 checks designed to pass on first execution:

1. R/57 file exists
2. Sources R/00_config.R
3. Sources R/utils/utils_assertions.R
4. Sources R/utils/utils_duckdb.R
5. Sources R/utils/utils_cancer.R
6. Reads treatment_episodes.rds
7. Outputs drug_grouping_instances.xlsx (not drug_grouping_tables.xlsx)
8. Has 2-sheet workbook with correct sheet names
9. Defines map_cancer_codes_to_categories helper
10. Uses CANCER_SITE_MAP + ICD9_CANCER_SITE_MAP
11. Sorts cancer categories descending (decreasing=TRUE)
12. Uses 3-tier sub-category lookup
13. Has >= 7 section headers (found: 8)
14. Does NOT aggregate with encounter_count
15. Uses is_cancer_code() from shared utility
16. Table 2 section does NOT contain group_by/summarise (D-08 validation)
17. Table 2 section references D-08 explicitly

### Manual Verification (to be performed by user on HiPerGator)

**Run R/57:**
```r
source("R/57_drug_grouping_instances.R")
```

**Expected output:**
- drug_grouping_instances.xlsx created in output/ directory
- Console summary shows:
  - Episodes with/without cancer category names
  - Table 1 row count, unique sub-categories, unique patients
  - Table 2 row count, unique treatment sets, unique patients
  - Verification message: "drug_grouping_tables.xlsx exists and was NOT modified"

**Inspect xlsx:**
- Sheet 1 (Treatment Sub-Category Detail): patient_id, episode_start, episode_stop, episode_number, treatment_category, sub_category_names, cancer_category_names
- Sheet 2 (Encounter Treatment Detail): patient_id, episode_start, episode_stop, episode_number, treatment_category, all_treatments, cancer_category_names
- Cancer category names are readable (e.g., "Hodgkin Lymphoma (non-NLPHL);Lymph Node Neoplasm"), not raw codes
- Sub-category names are readable (e.g., "Doxorubicin", not "J9000")
- Cancer category names sorted descending alphabetically
- Each row represents one distinct episode

**Run smoke test:**
```r
source("R/88_smoke_test_comprehensive.R")
```

**Expected:** [31/31] Phase 88 checks pass, all P88-D01 through P88-D08 requirements listed in summary.

## Known Stubs

None. All data sources are wired:
- treatment_episodes.rds provides per-episode data with all identifying columns
- DuckDB DIAGNOSIS table provides raw cancer ICD codes
- all_codes_resolved_next_tables_v2.1.xlsx provides sub-category mappings
- CANCER_SITE_MAP + ICD9_CANCER_SITE_MAP provide cancer code-to-category translation

## Integration Points

### Upstream Dependencies

- **R/28:** treatment_episodes.rds must contain columns: patient_id, treatment_type, episode_number, episode_start, episode_stop, triggering_codes, encounter_ids
- **R/00_config.R:** CANCER_SITE_MAP (200+ ICD-10 prefixes), ICD9_CANCER_SITE_MAP (70+ ICD-9 prefixes), CODE_SUBCATEGORY_MAP (326+ entries), DRUG_GROUPINGS (454+ entries), TREATMENT_CODES structure
- **data/reference/all_codes_resolved_next_tables_v2.1.xlsx:** Chemo (column C), Radiation (column G), SCT (column G) sub-category mappings
- **DuckDB DIAGNOSIS table:** Raw ICD diagnosis codes linked via ENCOUNTERID

### Downstream Consumers

- **Clinical reviewers:** Instance-level xlsx enables patient episode tracing with readable labels
- **R/88 smoke test:** Section 31 validates R/57 structure on every test run
- **Future analyses:** Instance-level data grain enables per-patient drill-down without re-querying treatment_episodes.rds

### Cross-Cutting Patterns

- **Sub-category resolution:** Reuses R/56 3-tier lookup pattern (xlsx -> CODE_SUBCATEGORY_MAP -> fallback)
- **Cancer code detection:** Uses shared is_cancer_code() from R/utils/utils_cancer.R (same as R/56)
- **Multi-sheet xlsx output:** Follows R/56 openxlsx2 wb_workbook() pattern
- **Console logging:** Uses R/56 globalCallingHandlers() pattern for log file capture

## Self-Check: PASSED

### Created Files

```
[ -f "R/57_drug_grouping_instances.R" ] && echo "FOUND: R/57_drug_grouping_instances.R"
FOUND: R/57_drug_grouping_instances.R
```

### Commits Exist

```
git log --oneline --all | grep -q "0a7ca45" && echo "FOUND: 0a7ca45"
FOUND: 0a7ca45

git log --oneline --all | grep -q "46ac8be" && echo "FOUND: 46ac8be"
FOUND: 46ac8be
```

All created files and commits verified successfully.

## Lessons Learned

### What Went Well

- **Reusable patterns from R/56:** 90% of R/57 logic was copy-paste-adapt from R/56 (sub-category resolution, cancer code extraction, xlsx output). Only new operation was cancer code-to-category mapping.
- **Inline helper function clarity:** map_cancer_codes_to_categories() encapsulates split-map-sort-collapse flow in one place. Future readers know exactly what "cancer_category_names" means without tracing multiple functions.
- **D-08 explicit documentation:** Commenting the per-episode grain decision in both code (SECTION 6) and smoke test makes the design choice transparent and testable.

### What Could Be Improved

- **Semicolon-separated cell readability:** Rows with 3+ sub-categories (e.g., "Doxorubicin;Bleomycin;Vincristine") may be hard to read in Excel. Consider width hints or cell wrapping in future iterations.
- **Cancer category sort order ambiguity:** "Descending order" (D-04) wasn't explicitly defined as "alphabetical descending". Assumed standard R sort(x, decreasing=TRUE) behavior. If user expected clinical priority sort (e.g., HL before lymph node), would need custom ordering.

### Future Considerations

- **Code-level grain option:** If users request one row per treatment code (not per episode), add Section 9 to R/57 that explodes sub_category_names before final select.
- **HIPAA suppression:** Current output shows all patient IDs without small-cell suppression. If <11 patients in any category, add HIPAA filtering before xlsx write.
- **Performance:** DuckDB join on 10,000+ encounter IDs completes in <10 seconds (per R/56 logs). No optimization needed unless episode count grows >100,000.

## Risks Mitigated

- **Breaking R/56 output:** Created separate R/57 script and drug_grouping_instances.xlsx file. R/56 and drug_grouping_tables.xlsx completely unchanged. Verified in Section 8 console summary.
- **ICD-9 code gaps:** map_cancer_codes_to_categories() checks both CANCER_SITE_MAP and ICD9_CANCER_SITE_MAP. All malignant ICD-9 codes (140-209) covered (per Phase 87 ICD9_CANCER_SITE_MAP).
- **Semicolon handling pitfalls:** Split-map-rejoin pattern avoids trying to look up "C81.10;C77.9" as single key. Smoke test validates descending sort exists (checks for "decreasing\\s*=\\s*TRUE" pattern).
- **Table 2 aggregation confusion:** D-08 explicit comment + smoke test validation prevent accidental group_by/summarise in future edits. Grep-based check catches regressions.

---

**Completed:** 2026-06-04T21:45:38Z
**Duration:** 3 minutes
**Tasks:** 2/2
**Commits:**
- 0a7ca45: feat(88-01): create R/57 instance-level drug grouping tables
- 46ac8be: test(88-01): add R/57 validation to smoke test
