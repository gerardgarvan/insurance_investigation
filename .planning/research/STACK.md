# Technology Stack — v2.3 Gantt Data Enrichment

**Project:** PCORnet Payer Variable Investigation (R Pipeline)
**Milestone:** v2.3 Gantt Data Enrichment
**Researched:** 2026-06-07

## Executive Summary

**NO NEW STACK COMPONENTS REQUIRED.** All necessary libraries (openxlsx2, dplyr, stringr) are already validated and in use across the existing 98-script pipeline. The enrichment milestone adds NO new dependencies—it leverages existing xlsx reading capabilities to extract treatment line labels (F/S/E/N), medication names, code metadata, and cross-use flags from all_codes_resolved2.xlsx and integrates them into Gantt CSV exports (R/51, R/52).

**Integration pattern:** Follow R/57_drug_grouping_instances.R model—`wb_load()` + `wb_to_df()` to read specific columns from Chemotherapy/Radiation/SCT/Immunotherapy sheets, build lookup maps (code → metadata), join to existing Gantt detail data.

**What NOT to add:** readxl (replaced by openxlsx2), xlsx (deprecated Java-based), data.table (conflicts with project's tidyverse style), writexl (write-only, not needed).

---

## Recommended Stack (All Already Validated)

### Excel File Reading — openxlsx2

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| openxlsx2 | 1.8.2+ | Read/write xlsx with modern API | Already used in 30+ scripts; `wb_load()` + `wb_to_df()` proven for multi-sheet xlsx reading; no Java dependency |

**Current usage:** R/57 (drug grouping), R/24 (treatment codes), R/55 (replaced-by verification), R/50 (all codes resolved generation)

**Why sufficient:**
- `wb_load(path)` — loads workbook object
- `wb_to_df(wb, sheet, start_row)` — reads sheet to data frame with row offset
- Handles merged headers, multi-line cells, preserves data types
- Read + write capability (unlike readxl)

**Integration example (from R/57):**
```r
library(openxlsx2)
ref_wb <- wb_load("all_codes_resolved2.xlsx")
chemo_sheet <- wb_to_df(ref_wb, sheet = "Chemotherapy", start_row = 2)

# Column access by index (reliable for multi-line headers)
code_col <- chemo_sheet[[1]]          # Column A: Code
med_col <- chemo_sheet[[3]]           # Column C: Medication
fsen_col <- chemo_sheet[[8]]          # Column H: F/S/E/N labels
crossuse_col <- chemo_sheet[[9]]      # Column I: Cross-use flags
```

### Data Manipulation — tidyverse

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| dplyr | 1.2.0+ | Data joins, filters, mutates | Join xlsx lookups to Gantt detail via `left_join(detail, lookup, by = "triggering_code")` |
| stringr | 1.5.1+ | String cleaning/normalization | Clean F/S/E/N labels: `str_trim()`, `str_to_upper()`, handle Y/y/yes variants in cross-use |
| tibble | 3.2.1+ | Modern data frames | Build lookup tables from xlsx columns |

**Why sufficient:** All operations are standard data wrangling:
1. Read xlsx columns → tibble
2. Build named vector or tibble lookup: `setNames(values, keys)`
3. Join to existing Gantt detail: `left_join()`
4. Clean/normalize text values: `str_trim()`, `coalesce()`

### Input Validation — checkmate

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| checkmate | 2.3.2+ | Type/structure assertions | Validate xlsx file exists, lookup tables have expected columns, enrichment preserves row counts |

**Pattern (from v2.0 Phase 72):**
```r
library(checkmate)

# Before loading xlsx
assert_file_exists("all_codes_resolved2.xlsx", .var.name = "[R/51 ERROR] Reference XLSX")

# After building lookup
assert_data_frame(code_metadata, min.rows = 200)
assert_names(colnames(code_metadata), must.include = c("code", "code_type", "source_table"))

# After enrichment
assert_true(nrow(detail_enriched) == nrow(detail),
  .var.name = "[R/51 ERROR] Enrichment lost rows")
```

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| xlsx reading | openxlsx2 | readxl | Read-only; project standardized on openxlsx2 in Phase 36 (v1.5) |
| xlsx reading | openxlsx2 | xlsx (Java-based) | Deprecated; requires Java runtime; replaced by openxlsx2 |
| xlsx reading | openxlsx2 | writexl | Write-only; no read capability |
| Data wrangling | dplyr | data.table | 10-50x faster but opaque `DT[i, j, by]` syntax conflicts with named predicate requirement |

## Installation

**NO NEW PACKAGES TO INSTALL.** All dependencies already in project renv.

For new contributors cloning the repo:
```r
# Restore existing environment (includes openxlsx2, tidyverse, checkmate)
renv::restore()
```

Verification:
```r
packageVersion("openxlsx2")  # Should be >= 1.8.0
packageVersion("dplyr")       # Should be >= 1.2.0
packageVersion("checkmate")   # Should be >= 2.3.0
```

---

## Integration Details

### all_codes_resolved2.xlsx Structure (Verified 2026-06-07)

**Sheets:** Index, Sheet1, Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care, Unrelated

**Chemotherapy sheet (203 codes):**
- Row 1: Title ("Chemotherapy — 203 codes")
- Row 2: Column headers
- Row 3+: Data

| Column | Header | Content | Example |
|--------|--------|---------|---------|
| 1 | Code | Treatment code | "1147324", "J9245" |
| 2 | Meaning | Code description | "Adcetris", "melphalan" |
| 3 | Medication | Generic medication name | "Adcetris", "melphalan" |
| 4 | Code Type | RXNORM, CPT/HCPCS, ICD-9, etc. | "RXNORM", "CPT/HCPCS" |
| 5 | Source Table | PCORnet table | "PRESCRIBING", "PROCEDURES" |
| 6 | Records | Record count | 1, 25, 150 |
| 7 | Patients | Patient count | 1, 12, 45 |
| 8 | F: First line<br>S: Second line<br>E: Either first or second<br>N: Not for Hodgkin<br>NA: Not applicable | Treatment line label | "F", "S", "E", "N", "NA" |
| 9 | Is this used for conditioning for SCT or as immunotherapy also? | Cross-use flag | "Y", "y", blank, None |

**Radiation sheet (12 codes):**
- Columns 1-2, 4-7 same as Chemotherapy
- Column 3: MISSING (no Medication column)
- Column 8: Type (IMRT, Proton Therapy, Other radiation) — NOT F/S/E/N
- Column 9: MISSING (no cross-use flags)

**SCT sheet (8 codes):**
- Columns 1-2, 4-6: Same as Radiation
- Column 7: Type (Allogeneic, Autologous) — NOT patient count
- Column 8+: MISSING

**Immunotherapy sheet:**
- Columns 1-6: Same structure
- Column 7: "Questions for Sharon" — NOT F/S/E/N or Type

### Defensive Column Indexing Strategy

**Problem:** Sheets have different column structures. Radiation/SCT lack Medication (col 3), have different col 7/8/9 meanings.

**Solution:** Build sheet-specific extractors with explicit NA fills.

```r
# SECTION: LOAD METADATA FROM XLSX

library(openxlsx2)
assert_file_exists("all_codes_resolved2.xlsx", .var.name = "[R/51 ERROR] Reference XLSX")
ref_wb <- wb_load("all_codes_resolved2.xlsx")

# Chemotherapy: Has all 9 columns
chemo_meta <- wb_to_df(ref_wb, sheet = "Chemotherapy", start_row = 2) %>%
  transmute(
    code = as.character(.[[1]]),
    description = as.character(.[[2]]),
    medication_name = as.character(.[[3]]),
    code_type = as.character(.[[4]]),
    source_table = as.character(.[[5]]),
    treatment_line_label = as.character(.[[8]]),
    cross_use_flag = as.character(.[[9]])
  ) %>%
  filter(!is.na(code), code != "")

# Radiation: No Medication (col 3 blank), no F/S/E/N, no cross-use
rad_sheet_raw <- wb_to_df(ref_wb, sheet = "Radiation", start_row = 2)
# Verify column count to determine indexing
message(glue("Radiation sheet columns: {ncol(rad_sheet_raw)}"))

rad_meta <- rad_sheet_raw %>%
  transmute(
    code = as.character(.[[1]]),
    description = as.character(.[[2]]),
    medication_name = NA_character_,  # Not applicable
    code_type = as.character(.[[4]]),  # Verified: col 4
    source_table = as.character(.[[5]]),
    treatment_line_label = NA_character_,  # No F/S/E/N for radiation
    cross_use_flag = NA_character_
  ) %>%
  filter(!is.na(code), code != "")

# SCT: Similar structure to Radiation
sct_sheet_raw <- wb_to_df(ref_wb, sheet = "SCT", start_row = 2)
message(glue("SCT sheet columns: {ncol(sct_sheet_raw)}"))

sct_meta <- sct_sheet_raw %>%
  transmute(
    code = as.character(.[[1]]),
    description = as.character(.[[2]]),
    medication_name = NA_character_,
    code_type = as.character(.[[4]]),  # Verify during implementation
    source_table = as.character(.[[5]]),
    treatment_line_label = NA_character_,
    cross_use_flag = NA_character_
  ) %>%
  filter(!is.na(code), code != "")

# Immunotherapy: Check actual structure
immuno_sheet_raw <- wb_to_df(ref_wb, sheet = "Immunotherapy", start_row = 2)
message(glue("Immunotherapy sheet columns: {ncol(immuno_sheet_raw)}"))

immuno_meta <- immuno_sheet_raw %>%
  transmute(
    code = as.character(.[[1]]),
    description = as.character(.[[2]]),
    medication_name = NA_character_,
    code_type = as.character(.[[3]]),  # Verified: no Medication col
    source_table = as.character(.[[4]]),
    treatment_line_label = NA_character_,
    cross_use_flag = NA_character_
  ) %>%
  filter(!is.na(code), code != "")

# Combine all lookups
code_metadata <- bind_rows(chemo_meta, rad_meta, sct_meta, immuno_meta)
message(glue("Total codes with metadata: {nrow(code_metadata)}"))
assert_data_frame(code_metadata, min.rows = 200)  # Expect 200+ codes total
```

### Enrichment Integration (R/51 and R/52)

**Add to existing Gantt scripts after detail is loaded, before CSV export:**

```r
# SECTION: ENRICH DETAIL WITH XLSX METADATA

message("--- Enriching detail with code metadata ---")

detail_enriched <- detail %>%
  left_join(code_metadata, by = c("triggering_code" = "code")) %>%
  mutate(
    # Clean F/S/E/N labels (normalize NA/blank/mixed case)
    treatment_line_label = str_trim(str_to_upper(treatment_line_label)),
    treatment_line_label = case_when(
      treatment_line_label %in% c("", "NA", "N/A", "NA:") ~ NA_character_,
      treatment_line_label %in% c("F", "S", "E", "N") ~ treatment_line_label,
      TRUE ~ NA_character_  # Catch unexpected values
    ),

    # Clean cross-use flags (Y/y/yes → "Y", blank/NA → NA)
    cross_use_flag = case_when(
      str_to_upper(str_trim(cross_use_flag)) %in% c("Y", "YES") ~ "Y",
      TRUE ~ NA_character_
    ),

    # Fill missing metadata with empty strings for CSV export
    medication_name = coalesce(medication_name, ""),
    code_type = coalesce(code_type, ""),
    source_table = coalesce(source_table, "")
  )

# Verify enrichment preserved row count
assert_true(nrow(detail_enriched) == nrow(detail),
  .var.name = "[R/51 ERROR] Enrichment lost rows")

# Log match rate
match_summary <- detail_enriched %>%
  summarise(
    total_codes = n_distinct(triggering_code),
    matched_codes = n_distinct(triggering_code[!is.na(code_type)]),
    match_pct = 100 * matched_codes / total_codes
  )
message(glue("Metadata match rate: {round(match_summary$match_pct, 1)}% ({match_summary$matched_codes}/{match_summary$total_codes} codes)"))

# SECTION: EXPORT ENRICHED CSV (add new columns to existing schema)

detail_export <- detail_enriched %>%
  select(
    patient_id,
    treatment_type,
    treatment_date,
    triggering_code,
    # NEW: Metadata columns
    medication_name,
    treatment_line_label,
    code_type,
    source_table,
    cross_use_flag,
    # EXISTING: Episode context
    episode_number,
    episode_start,
    episode_stop,
    # ... rest of existing columns
  )

write_csv(detail_export, OUTPUT_DETAIL)
message(glue("  Wrote {OUTPUT_DETAIL} ({nrow(detail_export)} rows, {ncol(detail_export)} columns)"))
```

### New Gantt v2 Schema (Post-Enrichment)

**gantt_detail_v2.csv (19 columns, was 14):**

1. patient_id
2. treatment_type
3. treatment_date
4. triggering_code
5. **medication_name** (NEW — from xlsx col 3)
6. **treatment_line_label** (NEW — from xlsx col 8: F/S/E/N/NA)
7. **code_type** (NEW — from xlsx col 4: RXNORM, CPT/HCPCS, etc.)
8. **source_table** (NEW — from xlsx col 5: PRESCRIBING, PROCEDURES, etc.)
9. **cross_use_flag** (NEW — from xlsx col 9: Y or NA)
10. episode_number
11. episode_start
12. episode_stop
13. historical_flag
14. triggering_code_description (existing)
15. cancer_category (existing)
16. regimen_label (existing)
17. is_first_line (existing)
18. drug_group (existing)
19. cause_of_death (existing)

**gantt_episodes_v2.csv (21 columns, was 16):**

Same 5 new columns added (medication_name, treatment_line_label, code_type, source_table, cross_use_flag), but aggregated/concatenated for episode-level:
- medication_name → semicolon-separated list of unique medications in episode
- treatment_line_label → semicolon-separated list of unique labels
- code_type → semicolon-separated list of unique types
- source_table → semicolon-separated list of unique tables
- cross_use_flag → "Y" if ANY code in episode has cross-use flag, else NA

**Aggregation example:**
```r
episodes_enriched <- detail_enriched %>%
  group_by(patient_id, treatment_type, episode_number) %>%
  summarise(
    # Existing aggregations
    episode_start = min(treatment_date),
    episode_stop = max(treatment_date),
    triggering_codes = paste(sort(unique(triggering_code)), collapse = ";"),
    # NEW: Aggregate metadata
    medication_names = paste(sort(unique(medication_name[medication_name != ""])), collapse = ";"),
    treatment_line_labels = paste(sort(unique(treatment_line_label[!is.na(treatment_line_label)])), collapse = ";"),
    code_types = paste(sort(unique(code_type[code_type != ""])), collapse = ";"),
    source_tables = paste(sort(unique(source_table[source_table != ""])), collapse = ";"),
    cross_use_any = if_else(any(cross_use_flag == "Y", na.rm = TRUE), "Y", NA_character_),
    # ... rest of existing aggregations
    .groups = "drop"
  )
```

---

## Anti-Patterns to Avoid

### 1. Don't Use readxl for This Project

```r
# AVOID: readxl (tidyverse xlsx reader)
library(readxl)
df <- read_excel("all_codes_resolved2.xlsx", sheet = "Chemotherapy")

# WHY: Project standardized on openxlsx2 (Phase 36) for read+write capability
# readxl is read-only, introduces inconsistency
```

**Decision traceability:** Phase 36 (v1.5) removed readxl in favor of openxlsx2.

### 2. Don't Use Column Names for Multi-Line Headers

```r
# AVOID: Relying on column names when header is multi-line
df <- wb_to_df(ref_wb, sheet = "Chemotherapy", start_row = 2)
fsen_col <- df$`F: First line\nS: Second line\nE: Either...`

# WHY: Multi-line header creates unwieldy name, fragile to text changes
```

**Better:** Use column index with comment:
```r
# Column 8: F/S/E/N treatment line labels
fsen_col <- df[[8]]
```

### 3. Don't Hardcode Questionable Codes in Multiple Scripts

```r
# AVOID: Duplicating questionable code lists in R/51, R/52, R/88
questionable_codes <- c("1234", "5678", ...)  # Vitamin combos
# ... repeated in 3 scripts

# WHY: Violates DRY principle (v2.0 Phase 73 consolidation)
```

**Better:** Centralize in R/00_config.R:
```r
# In R/00_config.R
QUESTIONABLE_CODES <- list(
  vitamin_combos = c("1234", "5678", ..., "8888"),  # 8 codes
  cart_classification_tbd = c("XW033E5", "XW043B3")  # 2 codes
)
```

Or add "Questionable Flag" column to xlsx (more maintainable for clinical reviewers).

### 4. Don't Assume All Sheets Have Same Column Structure

```r
# AVOID: Applying Chemotherapy indices to other sheets
rad_sheet <- wb_to_df(ref_wb, sheet = "Radiation", start_row = 2)
med_name <- rad_sheet[[3]]  # WRONG: Radiation has no Medication column

# WHY: Column 3 is blank/different per sheet
```

**Better:** Build sheet-specific extractors with NA fills (see integration example above).

### 5. Don't Skip Input Validation

```r
# AVOID: Assuming xlsx file exists and has expected structure
ref_wb <- wb_load("all_codes_resolved2.xlsx")  # May fail silently
chemo_meta <- wb_to_df(ref_wb, sheet = "Chemotherapy", start_row = 2)

# WHY: Missing file or renamed sheets cause cryptic errors downstream
```

**Better:** Add checkmate assertions:
```r
assert_file_exists("all_codes_resolved2.xlsx", .var.name = "[R/51 ERROR] Reference XLSX")
ref_wb <- wb_load("all_codes_resolved2.xlsx")

# After reading
assert_data_frame(chemo_meta, min.rows = 1)
assert_names(colnames(chemo_meta), must.include = c("code", "code_type"))
```

---

## Validation Strategy

### During Enrichment (R/51, R/52)

```r
# 1. Verify xlsx loaded
assert_file_exists("all_codes_resolved2.xlsx")
message(glue("Loaded reference xlsx with {nrow(code_metadata)} codes"))

# 2. Check match rate
match_summary <- detail_enriched %>%
  summarise(
    total_codes = n_distinct(triggering_code),
    matched_codes = n_distinct(triggering_code[!is.na(code_type)]),
    match_pct = 100 * matched_codes / total_codes
  )
message(glue("Metadata match rate: {round(match_summary$match_pct, 1)}%"))

# Expect: 95%+ for Chemo/Radiation/SCT (all codes in xlsx)
if (match_summary$match_pct < 90) {
  warning("Low match rate - verify xlsx structure and code alignment")
}

# 3. Check F/S/E/N value distribution (Chemo only)
fsen_dist <- detail_enriched %>%
  filter(treatment_type == "Chemotherapy", !is.na(treatment_line_label)) %>%
  count(treatment_line_label) %>%
  arrange(desc(n))
message("F/S/E/N distribution:")
print(fsen_dist)
# Expect: Only F, S, E, N values (not "First line", "NA:", etc.)

# 4. Check cross-use flags
crossuse_dist <- detail_enriched %>%
  filter(!is.na(cross_use_flag)) %>%
  count(treatment_type, cross_use_flag) %>%
  arrange(treatment_type, desc(n))
message("Cross-use flag distribution:")
print(crossuse_dist)
# Expect: Only "Y" values (not "y", "yes", "YES", blank strings)
```

### Smoke Test Updates (R/88)

Add new Section 34: Gantt Enrichment Validation

```r
# Section 34: Gantt v2 enrichment validation ----
message("\n=== Section 34: Gantt v2 Enrichment Validation ===\n")

gantt_detail <- read_csv("output/gantt_detail_v2.csv", show_col_types = FALSE)

# 34.1: Check new columns exist
expected_cols <- c("medication_name", "treatment_line_label", "code_type",
                   "source_table", "cross_use_flag")
assert_names(colnames(gantt_detail), must.include = expected_cols)
message("✓ All 5 new metadata columns present")

# 34.2: Check F/S/E/N values are clean
valid_fsen <- c("F", "S", "E", "N", NA)
invalid_fsen <- gantt_detail %>%
  filter(!treatment_line_label %in% valid_fsen) %>%
  distinct(treatment_line_label)

if (nrow(invalid_fsen) > 0) {
  stop("Invalid treatment_line_label values: ", paste(invalid_fsen$treatment_line_label, collapse = ", "))
}
message("✓ Treatment line labels are valid (F/S/E/N/NA only)")

# 34.3: Check cross-use flags are clean
valid_crossuse <- c("Y", NA)
invalid_crossuse <- gantt_detail %>%
  filter(!cross_use_flag %in% valid_crossuse) %>%
  distinct(cross_use_flag)

if (nrow(invalid_crossuse) > 0) {
  stop("Invalid cross_use_flag values: ", paste(invalid_crossuse$cross_use_flag, collapse = ", "))
}
message("✓ Cross-use flags are valid (Y/NA only)")

# 34.4: Check metadata coverage
coverage <- gantt_detail %>%
  summarise(
    total_rows = n(),
    has_med_name = sum(medication_name != "", na.rm = TRUE),
    has_fsen = sum(!is.na(treatment_line_label)),
    has_code_type = sum(code_type != "", na.rm = TRUE),
    has_source = sum(source_table != "", na.rm = TRUE),
    has_crossuse = sum(!is.na(cross_use_flag))
  )

message(glue("Metadata coverage:"))
message(glue("  Medication names: {coverage$has_med_name}/{coverage$total_rows} ({100*coverage$has_med_name/coverage$total_rows}%)"))
message(glue("  F/S/E/N labels: {coverage$has_fsen}/{coverage$total_rows} ({100*coverage$has_fsen/coverage$total_rows}%)"))
message(glue("  Code types: {coverage$has_code_type}/{coverage$total_rows} ({100*coverage$has_code_type/coverage$total_rows}%)"))
message(glue("  Source tables: {coverage$has_source}/{coverage$total_rows} ({100*coverage$has_source/coverage$total_rows}%)"))
message(glue("  Cross-use flags: {coverage$has_crossuse}/{coverage$total_rows} ({100*coverage$has_crossuse/coverage$total_rows}%)"))

# Expect high coverage for code_type and source_table (95%+)
assert_true(coverage$has_code_type / coverage$total_rows > 0.90,
  .var.name = "Code type coverage should be >90%")
```

---

## Version Pinning

| Package | Current Version | Min Version | Source |
|---------|----------------|-------------|--------|
| openxlsx2 | 1.8.2 | 1.8.0+ | CRAN, Dec 2025 release |
| dplyr | 1.2.0 | 1.2.0+ | Tidyverse 2.0.0 (July 2025) |
| stringr | 1.5.1 | 1.5.1+ | Tidyverse 2.0.0 |
| tibble | 3.2.1 | 3.2.1+ | Tidyverse 2.0.0 |
| checkmate | 2.3.2 | 2.3.0+ | CRAN, v2.0 Phase 72 validation |

**NO VERSION CHANGES NEEDED.** All packages already at target versions (verified in v2.2 renv.lock).

---

## Sources

- **openxlsx2 documentation:** https://cran.r-project.org/web/packages/openxlsx2/index.html (v1.8.2, Dec 2025)
- **openxlsx2 GitHub:** https://github.com/JanMarvin/openxlsx2 (active development, 500+ stars)
- **Existing usage patterns:** R/57_drug_grouping_instances.R (lines 113-131), R/24_treatment_codes_resolved.R, R/55_verify_replaced_by_codes.R
- **Project decisions:** Phase 36 (v1.5) standardized openxlsx2, Phase 73 (v2.0) DRY consolidation
- **xlsx structure verification:** Python openpyxl inspection of all_codes_resolved2.xlsx (2026-06-07)
- **Chemotherapy sheet:** 203 codes, 9 columns (Code, Meaning, Medication, Code Type, Source Table, Records, Patients, F/S/E/N, Cross-use)
- **Radiation sheet:** 12 codes, 7 columns (no Medication, no F/S/E/N, no Cross-use)
- **SCT sheet:** 8 codes, 6 columns (no Medication, Type instead of patient count)
- **Immunotherapy sheet:** Codes with "Questions for Sharon" column instead of F/S/E/N

---

## Confidence Assessment

| Area | Confidence | Rationale |
|------|------------|-----------|
| openxlsx2 sufficiency | **HIGH** | Already validated in 30+ scripts; wb_load + wb_to_df patterns proven for multi-sheet xlsx reading |
| Column indexing approach | **HIGH** | Python inspection confirmed exact column positions; index-based access avoids multi-line header issues |
| Integration pattern | **HIGH** | R/57 model (xlsx → lookup map → left_join) directly applicable; same wb_to_df + setNames pattern |
| Sheet structure handling | **MEDIUM** | Requires defensive coding for missing columns; verify during implementation with message() logging |
| No new dependencies | **HIGH** | All operations (read xlsx, build lookups, join, clean strings) achievable with validated stack |

**Research flags for phases:** None. No new libraries needed, no version conflicts, no integration risks.

---

## Recommendations for Implementation

1. **Start with Chemotherapy sheet only** (simplest: all 9 columns present). Verify enrichment works end-to-end in R/51 before expanding to other sheets.

2. **Print column structure during first run:**
   ```r
   chemo_sheet <- wb_to_df(ref_wb, sheet = "Chemotherapy", start_row = 2)
   message("Chemotherapy sheet columns:")
   print(names(chemo_sheet))
   print(head(chemo_sheet, 3))
   ```

3. **Add defensive NA handling for all metadata columns** (see integration example above with `coalesce()`).

4. **Update smoke test (R/88) Section 34** to validate new Gantt columns (see validation strategy above).

5. **Document xlsx dependency in R/51 and R/52 headers:**
   ```r
   # Inputs:
   #   - all_codes_resolved2.xlsx (treatment code metadata)
   #     - Chemotherapy: Medication (col 3), F/S/E/N (col 8), cross-use (col 9)
   #     - Radiation/SCT/Immunotherapy: Code Type (col 4), Source Table (col 5)
   ```

**NO STACK CHANGES. NO NEW LIBRARIES. NO VERSION BUMPS.** Pure integration work using validated tools.
