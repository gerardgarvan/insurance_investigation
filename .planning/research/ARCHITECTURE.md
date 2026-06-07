# Architecture Research — Gantt Data Enrichment Integration

**Domain:** R pipeline enhancement — integrating xlsx-sourced lookup tables with existing treatment episode export architecture
**Researched:** 2026-06-07
**Confidence:** HIGH

## Integration Context

**Current architecture:** Decade-based numbered R scripts (R/00_config.R central config, R/28 episode classification, R/51 gantt v1 export, R/52 gantt v2 export). DuckDB backend. Lookup tables centralized in R/00_config.R (TREATMENT_CODES, DRUG_GROUPINGS, CODE_SUBCATEGORY_MAP, AMC_PAYER_LOOKUP). Treatment episode enrichment happens at R/28, export/formatting at R/51-R/52.

**New data source:** `all_codes_resolved2.xlsx` with 8 sheets (Index, Sheet1, Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care, Unrelated). Each treatment sheet has columns: Code, Meaning, Medication, Code Type, Source Table, Records, Patients, F/S/E/N labels (column 8), cross-use flags (column 9).

**Integration challenge:** Where to load xlsx, where to apply lookups, how to propagate new columns through existing v1/v2 export paths without breaking backward compatibility.

---

## Current Data Flow (Pre-Enrichment)

```
R/00_config.R → TREATMENT_CODES (vectors), DRUG_GROUPINGS (named vector)
       ↓
R/28_episode_classification.R
   - Loads treatment_episodes.rds + treatment_episode_detail.rds
   - Links cancer diagnoses (ENCOUNTERID + 30-day temporal fallback)
   - Detects regimens (ABVD, BV+AVD, Nivo+AVD)
   - Adds: cancer_category, regimen_label, is_first_line, drug_group
   - Saves: enriched treatment_episodes.rds
       ↓
R/51_gantt_data_export.R (v1 schema)
   - Reads enriched episodes/detail RDS
   - Joins code_descriptions.rds (Phase 48b: code → description)
   - Joins cancer_categories_per_patient (aggregated from cancer_summary.csv)
   - Appends Death/HL Diagnosis pseudo-treatment rows
   - Writes: gantt_episodes.csv (14 columns), gantt_detail.csv (13 columns)
       ↓
R/52_gantt_v2_export.R (v2 schema)
   - Same pattern as R/51 but with Phase 64 cleanup:
     - Semicolon-separated multi-value fields
     - Simplified drug names (generic only)
     - "Unlinked" cancer_category for blanks
     - Dropped encounter_ids, is_hodgkin, cancer_link_method (internal columns)
   - Writes: gantt_episodes_v2.csv (16 columns), gantt_detail_v2.csv (14 columns)
```

---

## New Components for Gantt Enrichment

### 1. XLSX Lookup Table Loader (NEW)

**Location:** `R/utils/utils_xlsx_lookups.R` (new utility module)

**Rationale:**
- **NOT in R/00_config.R:** Config file already 2000+ lines (55k tokens). Adding xlsx parsing would bloat it further and slow startup.
- **NOT inline in R/51/R/52:** DRY violation — both scripts need the same lookups.
- **Utility module pattern:** Matches existing architecture (10 utils files already). Lazy-load via `source("R/utils/utils_xlsx_lookups.R")` only in scripts that need it.

**Responsibilities:**
- Parse `all_codes_resolved2.xlsx` (read-only mode via `openxlsx2::wb_load()`)
- Combine Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care sheets
- Extract columns: Code, Medication (column 3), Code Type (column 4), Source Table (column 5), F/S/E/N labels (column 8), cross-use flags (column 9)
- Return named list: `list(line_labels = named_vec, medications = named_vec, code_types = named_vec, source_tables = named_vec, cross_use = named_vec)`
- Handle missing values: NA for unmapped codes (join-safe)

**API:**
```r
# Load once per script execution (not cached — lightweight xlsx read)
xlsx_lookups <- load_xlsx_lookups(xlsx_path = "all_codes_resolved2.xlsx")

# Usage in R/28, R/51, R/52:
line_label <- xlsx_lookups$line_labels[code]      # "F", "S", "E", "N", or NA
medication <- xlsx_lookups$medications[code]       # "Doxorubicin", etc.
code_type <- xlsx_lookups$code_types[code]         # "RXNORM", "CPT/HCPCS", etc.
```

**Error handling:**
- `checkmate::assert_file_exists()` for xlsx path (fail-fast if missing)
- Sheet name validation (expect Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care)
- Column existence check (expect 9 columns minimum)

---

### 2. Episode-Level Enrichment (MODIFIED)

**Location:** `R/28_episode_classification.R` (existing script, add new columns)

**Current columns added by R/28 (Phase 61-78):**
- `cancer_category`, `cancer_link_method`, `is_hodgkin`, `regimen_label`, `is_first_line`, `drug_group`, `triggering_code_description`

**New columns to add (v2.3):**
- `line_label` (chr): F/S/E/N/NA per episode (derived from triggering_codes)
- `medication_names` (chr): Comma-separated human-readable names (from xlsx column 3)
- `code_type` (chr): Comma-separated code types (RXNORM, CPT/HCPCS, ICD-10-CM)
- `source_table_source` (chr): Comma-separated source tables (PRESCRIBING, PROCEDURES, DIAGNOSIS)
- `sct_cross_use_flag` (chr): "Conditioning", "Immunotherapy", "Both", or NA (from xlsx column 9)

**Derivation logic:**

1. **Line label (F/S/E/N):** Aggregate from all codes in `triggering_codes` (comma-separated)
   - If any code has "F" → episode gets "F"
   - Else if any "S" → "S"
   - Else if any "E" → "E"
   - Else if all "N" → "N"
   - Else NA (unmapped codes or non-therapy episodes)

2. **Medication names:** Map each code in `triggering_codes` to xlsx Medication (column 3), join with commas

3. **Code type:** Map each code to xlsx Code Type (column 4), deduplicate, join with commas

4. **Source table:** Map each code to xlsx Source Table (column 5), deduplicate, join with commas

5. **SCT cross-use flag:** Episode-level logic:
   - If treatment_type != "SCT" → NA
   - Else aggregate from all codes: if any "Conditioning" + any "Immunotherapy" → "Both", else first non-NA value

**Placement in R/28:**
- After regimen detection (line ~500)
- Before saving enriched treatment_episodes.rds (line ~600)
- Same pattern as existing drug_group + triggering_code_description enrichment (lines 450-490)

**Backward compatibility:**
- R/51 (v1 export) ignores new columns → no schema change
- R/52 (v2 export) can optionally use new columns → schema extension (16 → 21 columns)

---

### 3. False-Positive SCT Code Removal (MODIFIED)

**Location:** `R/00_config.R` — TREATMENT_CODES section (inline comment + code removal)

**Action:** Remove 5 codes from `TREATMENT_CODES$sct_*` vectors based on xlsx classification:
- Status/complication codes (not procedures) identified in xlsx review
- Document removal rationale in inline comments (per existing TREATMENT_CODES pattern)

**Impact:**
- R/20_treatment_inventory.R: Fewer SCT codes detected (expected)
- R/28_episode_classification.R: Episodes using only removed codes no longer classified as SCT
- R/51-R/52: Gantt exports reflect corrected treatment types

**Testing requirement:**
- Before/after code counts in R/88_smoke_test_comprehensive.R Section 15 (treatment code inventory)
- Attrition logging in R/14_build_cohort.R (patients with SCT treatment)

---

### 4. Gantt v2 Export Schema Extension (MODIFIED)

**Location:** `R/52_gantt_v2_export.R` (existing script, add 5 columns)

**Current v2 schema (Phase 78):**
- **Episodes:** 16 columns (patient_id through cause_of_death)
- **Detail:** 14 columns (patient_id through cause_of_death)

**New v2 schema (v2.3):**
- **Episodes:** 21 columns (+5: line_label, medication_names, code_type, source_table_source, sct_cross_use_flag)
- **Detail:** 19 columns (+5: same fields)

**Column ordering (append to end for non-breaking change):**
```
Episodes v2.3 (21 cols):
  1-16: Existing v2 columns (unchanged)
  17. line_label (chr)
  18. medication_names (chr)
  19. code_type (chr)
  20. source_table_source (chr)
  21. sct_cross_use_flag (chr)

Detail v2.3 (19 cols):
  1-14: Existing v2 columns (unchanged)
  15. line_label (chr)
  16. medication_names (chr)
  17. code_type (chr)
  18. source_table_source (chr)
  19. sct_cross_use_flag (chr)
```

**Data flow in R/52:**
1. Load enriched treatment_episodes.rds (already has new columns from R/28)
2. Select new columns in episodes_export build (lines 260-292)
3. Join new columns to detail_export from episodes (lines 299-329)
4. Apply Phase 64 cleanup to new multi-value fields:
   - `clean_multi_value()` for medication_names, code_type, source_table_source (semicolon separator)
   - No cleanup for line_label (single value) or sct_cross_use_flag (categorical)
5. Death/HL Diagnosis pseudo-rows get NA for all new columns (lines 380-603)

**Backward compatibility:**
- R/51 (v1 export) unchanged → gantt_episodes.csv remains 14 columns
- R/52 writes gantt_episodes_v2.csv with 21 columns → downstream tools must handle schema change

---

## Modified Data Flow (Post-Enrichment)

```
R/00_config.R
   - TREATMENT_CODES (5 SCT codes removed, documented)
       ↓
[NEW] R/utils/utils_xlsx_lookups.R
   - load_xlsx_lookups() → named vectors for code → F/S/E/N, medication, etc.
       ↓
R/28_episode_classification.R [MODIFIED]
   - source("R/utils/utils_xlsx_lookups.R")
   - xlsx_lookups <- load_xlsx_lookups("all_codes_resolved2.xlsx")
   - Derive 5 new columns from triggering_codes + xlsx_lookups
   - Save enriched treatment_episodes.rds (+5 columns)
       ↓
R/51_gantt_data_export.R [UNCHANGED]
   - Ignores new columns in treatment_episodes.rds
   - Writes gantt_episodes.csv (14 columns) — v1 schema preserved
       ↓
R/52_gantt_v2_export.R [MODIFIED]
   - source("R/utils/utils_xlsx_lookups.R") (optional, for validation)
   - Select new columns from enriched episodes
   - Join new columns to detail
   - Apply Phase 64 cleanup (semicolon separators)
   - Writes gantt_episodes_v2.csv (21 columns), gantt_detail_v2.csv (19 columns)
```

---

## Integration Points

### 1. R/00_config.R → R/28 → R/51/R/52

**Current integration:** R/28 sources R/00_config.R, adds columns to treatment_episodes.rds, R/51/R/52 consume enriched RDS.

**New integration:** Same pattern, but R/28 additionally sources utils_xlsx_lookups.R. No changes to R/00_config.R sourcing chain.

### 2. xlsx → Named Vectors → Episode Columns

**Pattern:** Same as existing DRUG_GROUPINGS (named vector in R/00_config.R, applied in R/28 via `drug_group <- DRUG_GROUPINGS[code]`).

**New pattern:** Named vectors from xlsx (not hardcoded in config), applied in R/28 via `line_label <- xlsx_lookups$line_labels[code]`.

**Rationale:** xlsx is source of truth (edited by Amy Crisp), not hardcoded R. Config should reference xlsx path, not duplicate 200+ code mappings.

### 3. Comma-Separated Codes → Comma-Separated Enrichments

**Existing pattern (R/28, lines 450-490):**
```r
# triggering_codes: "J9000,J9040,J9360" (comma-separated)
# Map each code to description, rejoin with commas
triggering_code_description <- paste(
  sapply(str_split(triggering_codes, ",")[[1]],
         function(c) code_descriptions[[c]]),
  collapse = ","
)
```

**New pattern (same approach for medication_names, code_type, source_table_source):**
```r
medication_names <- paste(
  sapply(str_split(triggering_codes, ",")[[1]],
         function(c) xlsx_lookups$medications[[c]] %||% NA_character_),
  collapse = ","
)
```

**Phase 64 cleanup (R/52, lines 623-810):** Converts commas → semicolons, deduplicates, drops blanks.

---

## Build Order (Dependency-Aware)

### Phase 1: Utility Module (No Dependencies)
1. Create `R/utils/utils_xlsx_lookups.R`
2. Implement `load_xlsx_lookups(xlsx_path)` function
3. Unit test: Load all_codes_resolved2.xlsx, verify 200+ codes returned
4. Validate column extraction (columns 3, 4, 5, 8, 9)

### Phase 2: Config Cleanup (Depends on xlsx review)
1. Identify 5 false-positive SCT codes from xlsx
2. Remove from `TREATMENT_CODES$sct_*` vectors in R/00_config.R
3. Add inline comments documenting removal rationale
4. Run R/88_smoke_test_comprehensive.R Section 15 (expect lower SCT code counts)

### Phase 3: Episode Enrichment (Depends on Phase 1)
1. Modify R/28_episode_classification.R:
   - Add `source("R/utils/utils_xlsx_lookups.R")` after existing sources
   - Add `xlsx_lookups <- load_xlsx_lookups("all_codes_resolved2.xlsx")` in Section 1
   - Add 5 new column derivations in Section 5 (after regimen detection)
   - Update `select()` call to include new columns before `saveRDS()`
2. Run R/28 on test fixtures (verify 5 new columns appear in treatment_episodes.rds)
3. Update R/88 Section 28 (episode classification validation: expect 5 new columns)

### Phase 4: Gantt v2 Export Extension (Depends on Phase 3)
1. Modify R/52_gantt_v2_export.R:
   - Add new columns to `episodes_export` select (lines 260-292)
   - Add new columns to `detail_export` join + select (lines 299-329)
   - Add `clean_multi_value()` calls for medication_names, code_type, source_table_source (Section 4D)
   - Update Death/HL Diagnosis pseudo-row construction (add NA for 5 new columns)
   - Update column count checks (16 → 21 episodes, 14 → 19 detail)
   - Update header comment schema documentation
2. Run R/52 on test fixtures (verify 21-column CSV output)
3. Update R/88 Section 52 (gantt v2 export validation: expect 21 columns)

### Phase 5: Validation (Depends on Phases 2-4)
1. Run full pipeline on test fixtures (R/01 through R/52)
2. Verify gantt_episodes.csv unchanged (14 columns)
3. Verify gantt_episodes_v2.csv extended (21 columns)
4. Spot-check 10 episodes: line_label matches xlsx F/S/E/N, medication_names populated
5. Verify 5 SCT codes no longer appear in gantt outputs

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Hardcoding xlsx Data in R/00_config.R

**What people do:** Extract xlsx data once, paste 200+ code mappings as named vectors in config.

**Why it's wrong:**
- xlsx is source of truth (Amy Crisp edits it)
- Hardcoding creates divergence (config vs xlsx)
- 200+ line config addition for data that changes

**Do this instead:**
- Load xlsx at runtime in R/28 (once per execution, <1 sec)
- xlsx path in config, data loaded by utility function
- Single source of truth pattern (existing: cancer_summary.csv, code_descriptions.rds)

### Anti-Pattern 2: Separate Enrichment Script (R/28b)

**What people do:** Create R/28b_xlsx_enrichment.R to add new columns, R/28 → R/28b → R/51/R/52 chain.

**Why it's wrong:**
- R/28 already does episode-level enrichment (cancer linkage, regimen detection, drug groups)
- Adds pipeline step, splits related logic
- treatment_episodes.rds written twice (R/28 base, R/28b enriched)

**Do this instead:**
- Add new columns in R/28 alongside existing enrichments (lines 450-600)
- Single episode enrichment script pattern (consolidation, not fragmentation)
- One RDS write per artifact (R/28 writes complete enriched episodes)

### Anti-Pattern 3: Per-Code Column Explosion

**What people do:** Add `code_1_line_label`, `code_2_line_label`, `code_3_line_label` columns (wide format).

**Why it's wrong:**
- Episodes have variable code counts (1-50+ codes per episode)
- Wide format = sparse matrix (mostly NAs)
- Downstream tools (Tableau, ggplot2) prefer long format or aggregated fields

**Do this instead:**
- Comma-separated aggregated fields (existing pattern: triggering_codes, drug_names)
- Episode-level summary (e.g., line_label = first non-NA from all codes)
- Detail-level granularity preserved (detail.csv has per-code rows)

### Anti-Pattern 4: Breaking v1 Export Backward Compatibility

**What people do:** Modify R/51 to output 19-column v1 CSV (add new columns to existing schema).

**Why it's wrong:**
- v1 schema is stable (14 columns since Phase 51)
- Downstream consumers expect 14 columns (Gantt chart tools, Tableau dashboards)
- Breaking change without versioning

**Do this instead:**
- v1 export unchanged (R/51 ignores new columns in RDS)
- New columns only in v2 export (R/52 extends 16 → 21 columns)
- Schema versioning pattern (v1 stable, v2 evolves)

---

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Current (98 scripts, 200 codes) | Utility module + runtime xlsx load is sufficient (<1 sec overhead) |
| 500+ codes, 10+ xlsx sheets | Consider caching xlsx_lookups as .rds (Phase 15 pattern), invalidate on xlsx mtime change |
| 1000+ codes, frequent xlsx updates | Add xlsx → SQL/DuckDB ingest step (R/03 pattern), query via get_pcornet_table() |

**Not needed for v2.3:** Caching or DuckDB ingest. Xlsx load is ~200 codes × 5 columns = 1000 cells, trivial overhead.

---

## Sources

- **Codebase inspection:** R/00_config.R (2000 lines, 55k tokens, lookup table patterns), R/28_episode_classification.R (episode enrichment pattern), R/51-R/52 (export dual-schema pattern), R/utils/*.R (10 utility modules)
- **Data source:** all_codes_resolved2.xlsx (8 sheets, 200+ codes, columns: Code, Meaning, Medication, Code Type, Source Table, F/S/E/N, cross-use flags)
- **Existing patterns:** DRUG_GROUPINGS (R/00_config.R named vector → R/28 application), code_descriptions.rds (R/48b generation → R/51/R/52 lookup), Phase 64 cleanup (semicolon separators, deduplication)
- **Confidence:** HIGH — codebase patterns well-established, xlsx structure verified, integration points explicit

---

*Architecture research for: Gantt data enrichment with xlsx-sourced lookup tables*
*Researched: 2026-06-07*
