# Phase 106: Tableau-Ready Data Tables - Research

**Researched:** 2026-06-15
**Domain:** R data extraction, Excel formatting, Tableau data requirements
**Confidence:** HIGH

## Summary

Phase 106 produces two self-contained xlsx tables for Amy to import into Tableau for interactive exploration of cancer diagnosis codes and chemotherapy drug classifications per treatment encounter. This is a data reshaping and formatting task, not a new clinical analysis — the phase adapts existing R/57 encounter-level extraction patterns to create Tableau-optimized outputs with comma-separated cancer codes and drug-by-class mappings.

**Critical foundation:** R/57 already extracts encounter-level cancer codes from DuckDB DIAGNOSIS and maps medication codes to human-readable names via reference xlsx lookups. Phase 106 reuses this proven pipeline, changing only the separator format (semicolons → commas per meeting notes) and adding drug class groupings for TABLE-2.

**Primary recommendation:** Create a single new R script (next available number: R/100 or above based on Phase 105 completion) that produces both tables in one execution, following the established R/57 multi-sheet xlsx pattern with openxlsx2.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**TABLE-1: Encounter Cancer Diagnosis Codes**
- **D-01:** TABLE-1 covers treatment encounters only — use encounter IDs from `treatment_episode_detail.rds` (same source as R/57). Does NOT include non-treatment encounters.
- **D-02:** One row per encounter with comma-separated cancer diagnosis codes (meeting notes specify "comma-separated").
- **D-03:** Include columns: PATID, ENCOUNTERID, treatment_date, treatment_type, cancer_codes (comma-separated DX codes), cancer_category_names (human-readable category names).

**TABLE-2: Chemo Drugs by Class with Cancer Codes**
- **D-04:** TABLE-2 provides individual medication names (e.g., "Doxorubicin") plus drug class/category (e.g., "Chemotherapy", with sub-category from reference xlsx).
- **D-05:** Chemo-only filter — TABLE-2 includes only chemotherapy encounters (treatment_type == "Chemotherapy"), per meeting notes "chemotherapy drugs by class/category."
- **D-06:** Include columns: PATID, ENCOUNTERID, treatment_date, treatment_type, medication_name (individual drug), drug_class/sub_category, cancer_codes, cancer_category_names.

**Both Tables**
- **D-07:** Tables include treatment context columns (PATID, ENCOUNTERID, treatment_date, treatment_type, cancer codes, category names) so Amy can build most Tableau views without external joins.
- **D-08:** Output as xlsx using openxlsx2 (established pattern from R/57, R/59, etc.).
- **D-09:** Raw counts without HIPAA suppression (internal investigation files — manual suppression before sharing, per v3.1 decision).

### Claude's Discretion

- Script number assignment (next available in the R/ directory sequence)
- Whether to create one new script or two (TABLE-1 and TABLE-2 may share enough setup to be in one script)
- Exact column ordering within each table
- Whether to reuse R/57's cancer code extraction logic via shared helper or inline it
- Sheet naming within xlsx workbooks

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TABLE-01 | User can open xlsx with TABLE 1: each encounter ID mapped to all associated cancer diagnosis codes (comma-separated), suitable for Tableau import | Standard Stack: openxlsx2 for xlsx output; Architecture Patterns: R/57 encounter-level cancer code extraction; Code Examples: DuckDB DIAGNOSIS query + is_cancer_code() filter |
| TABLE-02 | User can open xlsx with TABLE 2: chemotherapy drugs by class/category with associated cancer codes per encounter, suitable for Tableau import | Standard Stack: openxlsx2 for xlsx output; Architecture Patterns: R/57 sub-category resolution (3-tier cascade); Code Examples: Reference xlsx medication name mappings + CODE_SUBCATEGORY_MAP lookups |

</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| openxlsx2 | 1.27 (May 2026) | xlsx file creation | Project standard (R/57, R/59, R/31-R/34); modern OOXML API with full styling support; no Java dependency |
| dplyr | 1.2.0+ | Data transformation | Project standard (tidyverse ecosystem); established in R/57 for encounter aggregation |
| glue | 1.8.0+ | String formatting | Project standard for readable logging |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| stringr | 1.5.1+ | String operations | ICD code normalization (is_cancer_code), separator replacement (semicolon → comma) |
| tidyr | 1.3.0+ | Data reshaping | If pivot operations needed for drug class grouping |
| checkmate | 2.3.0+ | Input validation | Assert file existence, validate data structures (project pattern from utils_assertions.R) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| openxlsx2 | writexl | writexl is simpler but lacks multi-sheet workbook customization used in R/57 pattern |
| openxlsx2 | openxlsx (v1) | openxlsx2 is the maintained successor; v1 is deprecated |
| Single script | Two scripts (one per table) | Two scripts = more code duplication; single script shares setup (DuckDB connection, reference xlsx loading) |

**Installation:**
```bash
# On HiPerGator (already installed via renv from previous phases)
module load R/4.4.2
R
# In R console:
renv::restore()  # Restores openxlsx2, dplyr, glue, stringr, tidyr, checkmate
```

**Version verification:** openxlsx2 1.27 verified from CRAN (2026-05-25 release). All supporting libraries already pinned in project renv.lock from R/57 implementation.

## Architecture Patterns

### Recommended Project Structure
```
R/
├── 100_tableau_ready_tables.R        # New script (or next available number)
├── 00_config.R                       # TREATMENT_CODES, CODE_SUBCATEGORY_MAP, CANCER_SITE_MAP
├── utils/
│   ├── utils_cancer.R                # is_cancer_code(), classify_codes() [reuse]
│   ├── utils_duckdb.R                # open_pcornet_con(), get_pcornet_table() [reuse]
│   └── utils_assertions.R            # assert_rds_exists, assert_df_valid [reuse]

output/
├── tableau_table1_encounter_cancer_codes.xlsx      # TABLE-1 output
└── tableau_table2_chemo_drugs_by_class.xlsx        # TABLE-2 output
```

### Pattern 1: Encounter-Level Cancer Code Extraction (from R/57 Section 4)
**What:** Query DuckDB DIAGNOSIS table for all diagnosis codes associated with treatment encounters, filter to cancer codes only using `is_cancer_code()`, aggregate by encounter ID with separator-delimited concatenation.

**When to use:** Any time you need "all cancer codes found during an encounter" — R/57, R/28, and now TABLE-1.

**Example:**
```r
# Source: R/57_drug_grouping_instances.R lines 184-204
# Adapted for TABLE-1: change separator from semicolon to comma

USE_DUCKDB <- TRUE
open_pcornet_con()

# Get all diagnosis codes for encounters in treatment detail
dx_data <- get_pcornet_table("DIAGNOSIS") %>%
  filter(ENCOUNTERID %in% !!all_encounter_ids) %>%
  select(ENCOUNTERID, DX, DX_TYPE) %>%
  collect()

# Filter to cancer/neoplasm codes only
dx_cancer <- dx_data %>%
  filter(is_cancer_code(DX))

# Aggregate cancer codes per encounter (COMMA-separated per D-02)
encounter_dx <- dx_cancer %>%
  group_by(ENCOUNTERID) %>%
  summarise(
    cancer_codes = paste(sort(unique(DX)), collapse = ","),  # Changed from ";" to ","
    .groups = "drop"
  )
```

### Pattern 2: Medication Code-to-Name Resolution (from R/57 Section 3)
**What:** Map treatment codes (HCPCS, RxNorm, ICD-10-PCS, etc.) to human-readable medication/procedure names using 3-tier cascade: (1) reference xlsx lookups, (2) CODE_SUBCATEGORY_MAP supplement, (3) code-type fallback labels.

**When to use:** Any table that needs human-readable drug names instead of raw codes — R/56, R/57, and now TABLE-2.

**Example:**
```r
# Source: R/57_drug_grouping_instances.R lines 128-166 (xlsx loading)
# Source: R/57_drug_grouping_instances.R lines 343-391 (3-tier resolution)

# Load reference xlsx medication mappings
assert_file_exists(REFERENCE_XLSX, .var.name = "[R/57 ERROR] Reference XLSX")
ref_wb <- wb_load(REFERENCE_XLSX)

# Chemo: code -> medication name (column C)
chemo_sheet <- wb_to_df(ref_wb, sheet = "Chemotherapy", start_row = 2)
chemo_map <- setNames(as.character(chemo_sheet[[3]]), as.character(chemo_sheet[[1]]))
chemo_map <- chemo_map[!is.na(names(chemo_map)) & !is.na(chemo_map)]

# Apply 3-tier sub-category resolution
detail_codes <- detail_codes %>%
  mutate(
    sub_category = case_when(
      # Tier 1: xlsx reference sub-categories (most authoritative)
      triggering_code %in% names(code_to_subcategory) ~ code_to_subcategory[triggering_code],

      # Tier 2: CODE_SUBCATEGORY_MAP supplement
      !is.na(subcat_map) ~ subcat_map,

      # Tier 3: Code-type fallback labels
      category == "Chemotherapy" & triggering_code %in% chemo_hcpcs_codes ~ "Chemo HCPCS (no xlsx mapping)",
      category == "Chemotherapy" & triggering_code %in% chemo_rxnorm_codes ~ "Chemo RxNorm",
      # ... (full cascade in R/57 lines 343-391)
      TRUE ~ category
    )
  )
```

### Pattern 3: Multi-Sheet Workbook Output (from R/57 Section 7)
**What:** Create workbook with `wb_workbook()`, add multiple worksheets with `add_worksheet()`, write data to each sheet with `add_data()`, save with `save()` method.

**When to use:** Any output requiring multiple related tables in one file — R/57 (3 sheets), R/56 (5 sheets), and potentially TABLE-1/TABLE-2 if combined.

**Example:**
```r
# Source: R/57_drug_grouping_instances.R lines 488-506

wb <- wb_workbook()

# Sheet 1: TABLE-1
wb$add_worksheet("Encounter Cancer Codes")
wb$add_data("Encounter Cancer Codes", table1, start_row = 1, col_names = TRUE)

# Sheet 2: TABLE-2 (if combined into one xlsx)
wb$add_worksheet("Chemo Drugs by Class")
wb$add_data("Chemo Drugs by Class", table2, start_row = 1, col_names = TRUE)

wb$save(file.path(CONFIG$output_dir, "tableau_tables.xlsx"))
```

### Pattern 4: Cancer Code-to-Category Mapping (from R/57 Section 4)
**What:** Map ICD-10/ICD-9 cancer codes to human-readable category names (e.g., "C81.90" → "Hodgkin Lymphoma (non-NLPHL)", "C50.1" → "Breast") using classify_codes() from utils_cancer.R with 4-tier cascade.

**When to use:** Whenever cancer_codes needs companion cancer_category_names column for Tableau filtering/grouping.

**Example:**
```r
# Source: R/57_drug_grouping_instances.R lines 219-248

map_cancer_codes_to_categories <- function(cancer_codes_str) {
  if (is.na(cancer_codes_str) || cancer_codes_str == "") return(NA_character_)

  codes <- str_split(cancer_codes_str, ",")[[1]]  # Split on comma (TABLE-1 format)

  # 4-tier cascade: ICD-10 4-char -> ICD-10 3-char -> ICD-9 4-char -> ICD-9 3-char
  categories <- sapply(codes, function(code) {
    code_clean <- str_remove(code, "\\.")  # Normalize: remove dots
    prefix_4 <- substr(code_clean, 1, 4)
    prefix_3 <- substr(code_clean, 1, 3)

    if (prefix_4 %in% names(CANCER_SITE_MAP)) {
      CANCER_SITE_MAP[[prefix_4]]
    } else if (prefix_3 %in% names(CANCER_SITE_MAP)) {
      CANCER_SITE_MAP[[prefix_3]]
    } else if (prefix_4 %in% names(ICD9_CANCER_SITE_MAP)) {
      ICD9_CANCER_SITE_MAP[[prefix_4]]
    } else if (prefix_3 %in% names(ICD9_CANCER_SITE_MAP)) {
      ICD9_CANCER_SITE_MAP[[prefix_3]]
    } else {
      NA_character_
    }
  }, USE.NAMES = FALSE)

  # Remove NAs, keep unique, sort descending, collapse with commas
  categories <- categories[!is.na(categories)]
  if (length(categories) == 0) return(NA_character_)

  paste(sort(unique(categories), decreasing = TRUE), collapse = ",")
}

# Apply to unique cancer_codes strings
unique_cancer_codes <- unique(detail_dx$cancer_codes[!is.na(detail_dx$cancer_codes)])
cancer_category_lookup <- setNames(
  sapply(unique_cancer_codes, map_cancer_codes_to_categories, USE.NAMES = FALSE),
  unique_cancer_codes
)

detail_dx <- detail_dx %>%
  mutate(cancer_category_names = cancer_category_lookup[cancer_codes])
```

### Anti-Patterns to Avoid

- **Don't use semicolons as separator in TABLE-1/TABLE-2 cancer_codes:** Meeting notes explicitly request "comma-separated" format. R/57 uses semicolons for internal processing; TABLE-1/TABLE-2 must use commas for Tableau compatibility.
- **Don't create separate DuckDB connections for each table:** Reuse `open_pcornet_con()` once per script; DuckDB connection is singleton via utils_duckdb.R.
- **Don't include non-chemo encounters in TABLE-2:** D-05 specifies chemo-only filter. Verify with `filter(treatment_type == "Chemotherapy")` before aggregation.
- **Don't skip column header row:** Tableau requires `col_names = TRUE` in `add_data()` for automatic field detection.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cancer code detection | Custom ICD range regex | is_cancer_code() from utils_cancer.R | Handles both ICD-10 and ICD-9 with gap-free coverage; tested across 10+ scripts |
| Cancer code classification | Manual CANCER_SITE_MAP lookups | classify_codes() from utils_cancer.R | 4-tier cascade (ICD-10 4-char → 3-char → ICD-9 4-char → 3-char) prevents misclassification |
| DuckDB table access | Direct DBI::dbGetQuery() | get_pcornet_table() from utils_duckdb.R | Handles connection singleton, lazy evaluation, error handling |
| Input validation | Manual file.exists() checks | assert_rds_exists(), assert_df_valid() from utils_assertions.R | Standardized error messages with script name context |
| Medication name resolution | Parse reference xlsx manually | R/57 Section 3 pattern (chemo_map, rad_map, sct_map) | Already handles missing values, normalizes codes, deduplicates |

**Key insight:** R/57 already solves 90% of TABLE-1/TABLE-2 requirements. Don't reimplement — adapt separator format and add drug class grouping.

## Common Pitfalls

### Pitfall 1: Separator Format Inconsistency
**What goes wrong:** Using semicolons (R/57 internal format) instead of commas (meeting notes requirement) causes Tableau's built-in Split function to fail — users must write custom calculated fields.

**Why it happens:** R/57 uses `paste(..., collapse = ";")` consistently for encounter-level aggregation. Copy-pasting this pattern without reading meeting notes perpetuates semicolons.

**How to avoid:** Global find-replace in new script: `collapse = ";"` → `collapse = ","`. Verify in TABLE-1 and TABLE-2 column definitions. Meeting notes line 75 explicitly states "comma-separated."

**Warning signs:** During manual xlsx inspection, cancer_codes cells show semicolons between ICD codes.

### Pitfall 2: Including All Treatment Types in TABLE-2
**What goes wrong:** TABLE-2 includes Radiation, SCT, Immunotherapy encounters because script filters on `treatment_type %in% c("Chemotherapy", ...)` instead of exact match. Amy requested "chemotherapy drugs by class/category" — other treatment types are out of scope.

**Why it happens:** R/57 produces encounter-level tables for ALL treatment types. Copying R/57's filter logic without adding chemo-specific constraint includes unwanted rows.

**How to avoid:** Add explicit filter before TABLE-2 aggregation: `filter(treatment_type == "Chemotherapy")`. Verify row count matches chemo-only subset of treatment_episode_detail.rds.

**Warning signs:** TABLE-2 row count equals TABLE-1 row count (should be subset). TABLE-2 includes medication_name values like "IMRT" or "Allogeneic SCT" (radiation/SCT categories).

### Pitfall 3: Missing Column Headers in Tableau Import
**What goes wrong:** Tableau interprets first data row as values instead of field names, causing "Field1", "Field2" column names and mangled first-row data.

**Why it happens:** openxlsx2 `add_data()` defaults to `col_names = FALSE` (R convention: data.frame colnames are metadata, not data). Tableau expects Excel convention where row 1 = headers.

**How to avoid:** Always specify `col_names = TRUE` in `add_data()` calls. R/57 uses this pattern (lines 492, 496, 500, 512, 516).

**Warning signs:** Manual xlsx inspection shows data starting at row 1 with no header row. Tableau preview shows "Field1", "Field2", etc.

### Pitfall 4: Blank Rows Breaking Tableau Auto-Detection
**What goes wrong:** If data frame has NA-only rows or if `add_data()` includes blank spacer rows, Tableau's Data Interpreter fails to detect table boundaries correctly.

**Why it happens:** Defensive coding adds spacer rows "for readability" in Excel. Tableau best practices explicitly state "no blank rows in your data."

**How to avoid:** Filter out NA rows before `add_data()`: `filter(!is.na(ENCOUNTERID))`. Do NOT add manual spacer rows for "visual separation" — Tableau is not Excel.

**Warning signs:** Tableau import wizard shows "multiple tables detected" when only one table exists. Data Interpreter auto-cleans blank rows (symptom of poor source data).

### Pitfall 5: Overwriting Existing R/57 Output Files
**What goes wrong:** New script writes to `drug_grouping_instances.xlsx` (R/57's output file), clobbering existing broadened encounter-level tables.

**Why it happens:** Copy-pasting R/57 file paths without renaming for Tableau-specific purpose.

**How to avoid:** Use distinct output filenames: `tableau_table1_encounter_cancer_codes.xlsx`, `tableau_table2_chemo_drugs_by_class.xlsx`. Verify R/57 outputs remain unchanged after execution.

**Warning signs:** R/88 smoke test failures after running new script (file checksum mismatch).

## Code Examples

Verified patterns from R/57 and project utilities:

### Example 1: Load Treatment Episode Detail (Input)
```r
# Source: R/57_drug_grouping_instances.R lines 74-125

DETAIL_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds")

assert_rds_exists(DETAIL_RDS, script_name = "R/100")
detail <- readRDS(DETAIL_RDS)

assert_df_valid(
  detail,
  name = "treatment_episode_detail",
  required_cols = c("patient_id", "treatment_type", "treatment_date",
                    "triggering_code", "ENCOUNTERID", "episode_number"),
  script_name = "R/100"
)

message(glue("  Loaded {nrow(detail)} detail rows (one per date+code+encounter)"))
message(glue("  Unique encounters: {n_distinct(detail$ENCOUNTERID[!is.na(detail$ENCOUNTERID)])}"))
```

### Example 2: Extract and Aggregate Cancer Codes per Encounter (TABLE-1 Core)
```r
# Source: Adapted from R/57_drug_grouping_instances.R lines 168-206
# CHANGED: semicolon → comma separator per D-02

USE_DUCKDB <- TRUE
open_pcornet_con()

# Get unique encounter IDs from treatment detail
all_encounter_ids <- unique(detail$ENCOUNTERID[!is.na(detail$ENCOUNTERID) & detail$ENCOUNTERID != ""])

# Query DIAGNOSIS table for cancer codes
dx_data <- get_pcornet_table("DIAGNOSIS") %>%
  filter(ENCOUNTERID %in% !!all_encounter_ids) %>%
  select(ENCOUNTERID, DX, DX_TYPE) %>%
  collect()

dx_cancer <- dx_data %>%
  filter(is_cancer_code(DX))

# Aggregate with COMMA separator (D-02)
encounter_dx <- dx_cancer %>%
  group_by(ENCOUNTERID) %>%
  summarise(
    cancer_codes = paste(sort(unique(DX)), collapse = ","),  # COMMA not semicolon
    .groups = "drop"
  )

# Join cancer codes to detail
detail_dx <- detail %>%
  left_join(encounter_dx, by = "ENCOUNTERID")
```

### Example 3: Map Cancer Codes to Category Names
```r
# Source: Adapted from R/57_drug_grouping_instances.R lines 219-248
# CHANGED: split on comma instead of semicolon

map_cancer_codes_to_categories <- function(cancer_codes_str) {
  if (is.na(cancer_codes_str) || cancer_codes_str == "") return(NA_character_)

  codes <- str_split(cancer_codes_str, ",")[[1]]

  categories <- sapply(codes, function(code) {
    code_clean <- str_remove(code, "\\.")
    prefix_4 <- substr(code_clean, 1, 4)
    prefix_3 <- substr(code_clean, 1, 3)

    if (prefix_4 %in% names(CANCER_SITE_MAP)) {
      CANCER_SITE_MAP[[prefix_4]]
    } else if (prefix_3 %in% names(CANCER_SITE_MAP)) {
      CANCER_SITE_MAP[[prefix_3]]
    } else if (prefix_4 %in% names(ICD9_CANCER_SITE_MAP)) {
      ICD9_CANCER_SITE_MAP[[prefix_4]]
    } else if (prefix_3 %in% names(ICD9_CANCER_SITE_MAP)) {
      ICD9_CANCER_SITE_MAP[[prefix_3]]
    } else {
      NA_character_
    }
  }, USE.NAMES = FALSE)

  categories <- categories[!is.na(categories)]
  if (length(categories) == 0) return(NA_character_)

  paste(sort(unique(categories), decreasing = TRUE), collapse = ",")
}

# Apply to unique codes
unique_cancer_codes <- unique(detail_dx$cancer_codes[!is.na(detail_dx$cancer_codes)])
cancer_category_lookup <- setNames(
  sapply(unique_cancer_codes, map_cancer_codes_to_categories, USE.NAMES = FALSE),
  unique_cancer_codes
)

detail_dx <- detail_dx %>%
  mutate(cancer_category_names = cancer_category_lookup[cancer_codes])
```

### Example 4: Build TABLE-1 (Encounter Cancer Codes)
```r
# Source: New for Phase 106, pattern from R/57 Section 5-6
# Implements D-01, D-02, D-03

table1 <- detail_dx %>%
  # One row per encounter (treatment grain, per D-01)
  select(patient_id, ENCOUNTERID, treatment_date, treatment_type,
         cancer_codes, cancer_category_names) %>%
  distinct() %>%
  rename(PATID = patient_id) %>%
  arrange(PATID, treatment_date, treatment_type)

message(glue("  TABLE-1 rows: {nrow(table1)}"))
message(glue("  TABLE-1 unique encounters: {n_distinct(table1$ENCOUNTERID)}"))
```

### Example 5: Build TABLE-2 (Chemo Drugs by Class)
```r
# Source: New for Phase 106, adapted from R/57 Section 3 + Section 5
# Implements D-04, D-05, D-06

# Load reference xlsx for medication name mappings
REFERENCE_XLSX <- "data/reference/all_codes_resolved_next_tables_v2.1.xlsx"
assert_file_exists(REFERENCE_XLSX, .var.name = "[R/100 ERROR] Reference XLSX")
ref_wb <- wb_load(REFERENCE_XLSX)

chemo_sheet <- wb_to_df(ref_wb, sheet = "Chemotherapy", start_row = 2)
chemo_map <- setNames(as.character(chemo_sheet[[3]]), as.character(chemo_sheet[[1]]))
chemo_map <- chemo_map[!is.na(names(chemo_map)) & !is.na(chemo_map)]

# Filter to chemo encounters only (D-05)
chemo_detail <- detail_dx %>%
  filter(treatment_type == "Chemotherapy", !is.na(triggering_code), triggering_code != "")

# Resolve medication names (3-tier cascade)
chemo_detail <- chemo_detail %>%
  mutate(
    medication_name = case_when(
      triggering_code %in% names(chemo_map) ~ chemo_map[triggering_code],
      triggering_code %in% names(CODE_SUBCATEGORY_MAP) ~ CODE_SUBCATEGORY_MAP[triggering_code],
      TRUE ~ paste0("Chemo code ", triggering_code)  # Fallback
    )
  )

# Aggregate to encounter level (one row per encounter, D-06)
table2 <- chemo_detail %>%
  group_by(patient_id, ENCOUNTERID, treatment_date, treatment_type,
           cancer_codes, cancer_category_names) %>%
  summarise(
    medication_name = paste(sort(unique(medication_name)), collapse = ";"),  # Multiple drugs per encounter
    drug_class = "Chemotherapy",  # All are chemo per D-05 filter
    .groups = "drop"
  ) %>%
  rename(PATID = patient_id) %>%
  arrange(PATID, treatment_date)

message(glue("  TABLE-2 rows: {nrow(table2)}"))
message(glue("  TABLE-2 unique encounters: {n_distinct(table2$ENCOUNTERID)}"))
```

### Example 6: Write Multi-Sheet Workbook (or Separate Files)
```r
# Source: R/57_drug_grouping_instances.R lines 488-506
# Option A: Separate files (clearer purpose)

wb1 <- wb_workbook()
wb1$add_worksheet("Encounter Cancer Codes")
wb1$add_data("Encounter Cancer Codes", table1, start_row = 1, col_names = TRUE)
wb1$save(file.path(CONFIG$output_dir, "tableau_table1_encounter_cancer_codes.xlsx"))
message(glue("Saved TABLE-1: tableau_table1_encounter_cancer_codes.xlsx"))

wb2 <- wb_workbook()
wb2$add_worksheet("Chemo Drugs by Class")
wb2$add_data("Chemo Drugs by Class", table2, start_row = 1, col_names = TRUE)
wb2$save(file.path(CONFIG$output_dir, "tableau_table2_chemo_drugs_by_class.xlsx"))
message(glue("Saved TABLE-2: tableau_table2_chemo_drugs_by_class.xlsx"))

# Option B: Combined workbook (2 sheets, simpler for user to find)

wb <- wb_workbook()

wb$add_worksheet("TABLE-1: Encounter Cancer Codes")
wb$add_data("TABLE-1: Encounter Cancer Codes", table1, start_row = 1, col_names = TRUE)

wb$add_worksheet("TABLE-2: Chemo Drugs by Class")
wb$add_data("TABLE-2: Chemo Drugs by Class", table2, start_row = 1, col_names = TRUE)

wb$save(file.path(CONFIG$output_dir, "tableau_ready_tables.xlsx"))
message(glue("Saved combined TABLE-1 + TABLE-2: tableau_ready_tables.xlsx"))
```

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| R | All code | ✓ | 4.4.2 | — |
| openxlsx2 | xlsx output | ✓ | 1.27 (renv) | — |
| dplyr | Data transformation | ✓ | 1.2.0+ (renv) | — |
| stringr | String operations | ✓ | 1.5.1+ (renv) | — |
| glue | Logging | ✓ | 1.8.0+ (renv) | — |
| DuckDB DIAGNOSIS table | Cancer code extraction | ✓ | Via utils_duckdb.R | — |
| treatment_episode_detail.rds | Input data | ✓ | Produced by R/26 | — |
| all_codes_resolved_next_tables_v2.1.xlsx | Medication mappings | ✓ | data/reference/ | — |

**Missing dependencies with no fallback:**
- None identified

**Missing dependencies with fallback:**
- None identified

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| openxlsx (v1) | openxlsx2 | 2023 | v2 is actively maintained; v1 deprecated; new projects should use v2 |
| Manual xlsx formatting | Tableau Data Interpreter | 2020+ | Tableau auto-cleans minor formatting issues; focus on data structure (no blank rows) over styling |
| Semicolon separators in R | Comma separators for Tableau | Project-specific | Meeting notes explicitly request commas; Tableau's Split function defaults to comma delimiter |

**Deprecated/outdated:**
- openxlsx (v1): Last update 2021, recommend openxlsx2 for new code
- R data.table for Excel writing: Requires intermediate CSV step; openxlsx2 is native xlsx

## Open Questions

None identified. All requirements clarified in 106-CONTEXT.md and meeting notes.

## Project Constraints (from CLAUDE.md)

**Runtime environment:** RStudio on UF HiPerGator — scripts must work in that environment

**R packages:** tidyverse ecosystem (dplyr, ggplot2, stringr, lubridate), openxlsx2 for xlsx output

**Data access:** Raw CSVs on HiPerGator filesystem (via DuckDB) — paths configured in R/00_config.R

**Code style:** Named predicate functions (`has_*`, `with_*`, `exclude_*`) not applicable here (no cohort filtering); follow established R/57 pattern for encounter-level aggregation

## Sources

### Primary (HIGH confidence)
- R/57_drug_grouping_instances.R (project code) - Encounter-level cancer code extraction, medication name resolution, openxlsx2 multi-sheet pattern
- R/utils/utils_cancer.R (project code) - is_cancer_code(), classify_codes() utilities
- pecan_lymphoma_meeting_notes_combined.md lines 75-76 (project docs) - TABLE-1/TABLE-2 requirements, comma-separated format
- .planning/phases/106-tableau-ready-data-tables/106-CONTEXT.md - User decisions from /gsd:discuss-phase
- [openxlsx2 CRAN Package](https://cran.r-project.org/package=openxlsx2) - Version 1.27 (2026-05-25)
- [openxlsx2 Official Documentation](https://janmarvin.github.io/openxlsx2/) - wb_workbook(), add_data() API
- [The openxlsx2 book](https://janmarvin.github.io/ox2-book/) - Comprehensive guide
- [Tableau Excel Data Source](https://help.tableau.com/current/pro/desktop/en-us/examples_excel.htm) - Excel format requirements
- [Tableau Data Tips](https://help.tableau.com/current/pro/desktop/en-us/data_tips.htm) - No blank rows, row-oriented tables

### Secondary (MEDIUM confidence)
- [Tableau Split Function](https://help.tableau.com/current/pro/desktop/en-us/split.htm) - Comma delimiter default
- [Split & Pivot Comma-Separated Values - Flerlage Twins](https://www.flerlagetwins.com/2020/05/split-and-pivot.html) - Tableau workflow for comma-separated fields

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All libraries already in project renv.lock from R/57
- Architecture: HIGH - R/57 provides 90% of needed patterns (encounter aggregation, cancer code extraction, xlsx output)
- Pitfalls: HIGH - Separator format mismatch is the primary risk; other pitfalls derived from Tableau official docs
- Tableau requirements: MEDIUM - Official Tableau docs verified (no blank rows, col_names = TRUE), but Tableau version-specific behavior not tested

**Research date:** 2026-06-15
**Valid until:** 90 days (stable domain — R package ecosystem, Tableau data import best practices)
