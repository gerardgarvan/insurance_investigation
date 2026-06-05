# Phase 88: Re-do Tables with Descriptives Instead of Counts - Research

**Researched:** 2026-06-04
**Domain:** R data transformation, xlsx multi-sheet output, semi-colon delimited aggregation
**Confidence:** HIGH

## Summary

Phase 88 restructures R/56's existing aggregated drug grouping summary tables into a new instance-level output file that shows individual patient-episode rows with human-readable descriptive labels instead of raw codes and aggregated counts. The transformation changes the data grain from "aggregated summary by treatment sub-category" to "one row per patient + treatment type + episode", using resolved sub-category names (drug names, procedure types) and cancer site category names (not raw ICD codes) as primary descriptors.

All required technical infrastructure already exists: `treatment_episodes.rds` contains per-episode data with all identifying columns, R/56's 3-tier sub-category resolution logic (xlsx → CODE_SUBCATEGORY_MAP → fallback) is reusable, CANCER_SITE_MAP and ICD9_CANCER_SITE_MAP provide ICD-to-category translation, and openxlsx2 multi-sheet xlsx output is established. The implementation is a data reshaping exercise, not a new feature build.

**Primary recommendation:** Create new script R/57 that reads `treatment_episodes.rds`, applies existing resolution logic with minimal refactoring, and outputs a new xlsx file. Leave R/56 and `drug_grouping_tables.xlsx` unchanged.

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Which Tables Change:**
- Both Table 1 (Sub-Category Summary) and Table 2 (Encounter Treatment Summary) are restructured into the new instance-level design (D-01)
- The existing drug_grouping_tables.xlsx remains unchanged — a new separate xlsx file is created (D-02)

**Descriptive Columns:**
- Use resolved sub-category names as the primary descriptor column (e.g., "Doxorubicin" instead of "J9000", "IMRT" instead of CPT code). These come from the existing 3-tier sub-category resolution: xlsx mappings → CODE_SUBCATEGORY_MAP → fallback labels (D-03)
- Cancer codes column replaced with cancer site category names from CANCER_SITE_MAP (ICD-10) and ICD9_CANCER_SITE_MAP (ICD-9), sorted in descending order. E.g., "Hodgkin Lymphoma;Lymph Node Neoplasm" instead of "C81.10;C77.9" (D-04)

**Instance-Level Detail:**
- One row per patient + treatment type + episode. Each episode is a distinct row — if a patient has 2 separate chemotherapy courses, they appear as 2 rows (D-05)
- Each row includes: PATID, episode_start, episode_stop, episode_number, treatment category (Chemotherapy/Radiation/SCT/Immunotherapy), sub-category name(s), and cancer site category names (D-06)

**Output Format:**
- New xlsx file (separate from drug_grouping_tables.xlsx) — preserves the old file unchanged (D-07)
- Two sheets maintained — Table 1 (sub-category detail) and Table 2 (encounter treatment detail) remain as separate sheets with the new row grain (D-08)

### Claude's Discretion

- New xlsx file name (e.g., `drug_grouping_instances.xlsx` or similar descriptive name)
- Column ordering within each sheet beyond the specified columns
- How to handle episodes with multiple sub-categories (semicolon-separated list vs one column per sub-category)
- Sort order of rows within sheets (by PATID, by treatment category, by date, etc.)
- Whether to create a new script (e.g., R/57) or add to R/56 as additional output
- How to map semicolon-separated cancer codes to their category names (per-code lookup before joining)

### Deferred Ideas

None — discussion stayed within phase scope.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Established in project; tidyverse standard for readable pipelines |
| tidyr | 1.3.1+ | Data reshaping | Needed for unnest() of semicolon-separated codes; tidyverse ecosystem |
| stringr | 1.5.1+ | String manipulation | Already used for str_split() on triggering_codes and cancer_codes |
| openxlsx2 | 1.4+ | Multi-sheet xlsx output | Established in R/50, R/56 for 2-sheet workbooks; modern successor to openxlsx |
| glue | 1.8.0 | String formatting | Already used for logging messages in all R/ scripts |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| checkmate | 2.3.2+ | Input validation | Already required by R/00_config.R; assert_rds_exists(), assert_df_valid() |

**Installation:**
All packages already installed — no new dependencies required. All are loaded via `source("R/00_config.R")` auto-sourcing pattern.

**Version verification:**
Versions verified from CLAUDE.md STACK.md section. All packages already in project renv.lock (Phase 15 renv adoption).

## Architecture Patterns

### Recommended Project Structure
This phase follows the established R/ script pattern from R/56:

```
R/
├── 57_drug_grouping_instances.R   # New script (Claude's discretion on number)
├── 56_new_tables_from_groupings.R # Unchanged existing script
└── 00_config.R                     # CANCER_SITE_MAP, CODE_SUBCATEGORY_MAP, DRUG_GROUPINGS

cache/outputs/
└── treatment_episodes.rds          # Input data (from R/28)

data/reference/
└── all_codes_resolved_next_tables_v2.1.xlsx  # Sub-category mappings

output/
├── drug_grouping_tables.xlsx       # Existing file (unchanged)
└── drug_grouping_instances.xlsx    # New instance-level file (name negotiable)
```

### Pattern 1: Per-Episode Data Grain
**What:** Output one row per treatment episode (not aggregated by sub-category)
**When to use:** User explicitly requested "list each instance" instead of counts
**Example:**
```r
# R/56 current (aggregated):
# sub_category | treatment_code | cancer_codes | encounter_count
# Doxorubicin  | J9000          | C81.10;C77.9 | 42

# Phase 88 new (instance-level):
# PATID | episode_start | episode_stop | episode_number | treatment_category | sub_category | cancer_category_names
# 12345 | 2018-03-15    | 2018-09-10   | 1              | Chemotherapy       | Doxorubicin  | Hodgkin Lymphoma;Lymph Node Neoplasm
# 12345 | 2019-02-01    | 2019-02-15   | 2              | Chemotherapy       | Doxorubicin  | Hodgkin Lymphoma
# 67890 | 2020-06-10    | 2020-12-05   | 1              | Chemotherapy       | Doxorubicin  | Hodgkin Lymphoma
```

### Pattern 2: Reuse Sub-Category Resolution Logic from R/56
**What:** R/56 Section 5 has 3-tier lookup: xlsx mappings → CODE_SUBCATEGORY_MAP → code-type fallback
**When to use:** Need to map treatment codes (J9000, CPT codes, ICD-10-PCS) to human-readable names
**Example:**
```r
# Source: R/56_new_tables_from_groupings.R lines 322-369
sub_category = case_when(
  # Tier 1: xlsx reference sub-categories (most authoritative)
  treatment_code %in% names(code_to_subcategory) ~ code_to_subcategory[treatment_code],

  # Tier 2: CODE_SUBCATEGORY_MAP supplement
  treatment_code %in% names(CODE_SUBCATEGORY_MAP) ~ CODE_SUBCATEGORY_MAP[treatment_code],

  # Tier 3: Code-type fallback labels
  category == "Chemotherapy" & treatment_code %in% chemo_hcpcs_codes ~ "Chemo HCPCS (no xlsx mapping)",
  # ... additional fallback rules
  TRUE ~ category
)
```

### Pattern 3: ICD Code to Category Name Translation
**What:** Map semicolon-separated ICD codes (C81.10;C77.9) to category names (Hodgkin Lymphoma;Lymph Node Neoplasm)
**When to use:** Converting raw cancer_codes from treatment_episodes.rds to readable category names (D-04)
**Example:**
```r
# Split semicolon-separated codes, map each to category, sort descending, rejoin
map_cancer_codes_to_categories <- function(cancer_codes) {
  if (is.na(cancer_codes) || cancer_codes == "") return(NA_character_)

  codes <- str_split(cancer_codes, ";")[[1]]

  # Map each code using classify_codes() or direct CANCER_SITE_MAP lookup
  categories <- sapply(codes, function(code) {
    # Try 4-char prefix first (ICD-10), then 3-char, then ICD-9 map
    prefix_4 <- substr(code, 1, 4)
    prefix_3 <- substr(code, 1, 3)

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

  # Remove NAs, sort descending, collapse with semicolons
  categories <- categories[!is.na(categories)]
  if (length(categories) == 0) return(NA_character_)

  paste(sort(unique(categories), decreasing = TRUE), collapse = ";")
}

# Apply to data
episodes %>%
  mutate(cancer_category_names = sapply(cancer_codes, map_cancer_codes_to_categories))
```

**Note:** The classify_codes() utility in R/utils/utils_cancer.R implements the same 4-tier cascade (C810 → C81 → ICD9 201.4 → ICD9 201) and could be reused, but returns a single category (first match), not all categories for a semicolon-separated list. Direct map lookup in the mapping function is cleaner for this use case.

### Pattern 4: Multi-Sheet xlsx Output with openxlsx2
**What:** Create 2-sheet workbook: Table 1 (sub-category detail) + Table 2 (encounter treatment detail)
**When to use:** User explicitly requested 2 sheets maintained (D-08)
**Example:**
```r
# Source: R/56 Section 7 lines 571-589
wb <- wb_workbook()

# Sheet 1: Sub-Category Summary (instance-level)
wb$add_worksheet("Treatment Sub-Category Summary")
wb$add_data("Treatment Sub-Category Summary", table1, start_row = 1, col_names = TRUE)

# Sheet 2: Encounter Treatment Summary (instance-level)
wb$add_worksheet("Encounter Treatment Summary")
wb$add_data("Encounter Treatment Summary", table2, start_row = 1, col_names = TRUE)

wb$save(OUTPUT_XLSX)
message(glue("Saved: {OUTPUT_XLSX}"))
```

### Anti-Patterns to Avoid
- **Don't modify R/56 or drug_grouping_tables.xlsx:** User explicitly wants existing file unchanged (D-02, D-07). Create new script and new output file.
- **Don't aggregate by treatment category:** User wants to see individual episodes (D-05). No `group_by()` + `summarise()` on the final output.
- **Don't leave raw ICD codes in output:** User wants category names (D-04), not C81.10;C77.9.
- **Don't use encounter_count column:** Output grain is per-episode, so there's no count to display (each row IS one instance).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ICD code prefix matching | Custom string parsing | CANCER_SITE_MAP + ICD9_CANCER_SITE_MAP direct lookup | Maps already exist with 4-char and 3-char prefixes (200+ ICD-10, 70+ ICD-9); hand-rolling will miss edge cases like C810 vs C81 priority |
| Sub-category resolution | New code-to-name mapping | Reuse R/56 Section 5 logic + xlsx sheet loading | 3-tier lookup already handles 326 CODE_SUBCATEGORY_MAP entries + xlsx mappings + fallback labels; duplicating will diverge |
| Multi-sheet xlsx output | Manual file writing | openxlsx2 wb_workbook() pattern from R/56 | Established 2-sheet pattern (lines 571-589); reinventing will break consistency |
| Semicolon-separated list handling | Manual str_split() loops | sapply() with helper functions | Already used in R/56 for cancer_codes aggregation (line 205-219) and R/28 for triggering_codes mapping (lines 462-484); pattern is proven |

**Key insight:** R/56 already implements 90% of the required logic (sub-category resolution, cancer code aggregation, xlsx output). The only new challenge is mapping semicolon-separated ICD codes to category names — everything else is refactoring existing code to change the data grain from aggregated to per-episode.

## Runtime State Inventory

Not applicable — this is a greenfield data transformation phase with no rename/refactor/migration component.

## Common Pitfalls

### Pitfall 1: Semicolon-Separated Codes Lose Individual Mappings
**What goes wrong:** Treating "C81.10;C77.9" as a single string key instead of splitting into individual codes before mapping
**Why it happens:** CANCER_SITE_MAP uses 3-4 character prefixes, not full dotted codes. "C81.10;C77.9" as a key will never match "C81" in the map.
**How to avoid:** Always split on semicolon FIRST, map each code individually, then rejoin the category names
**Warning signs:** Output shows NA for cancer_category_names even though cancer_codes is non-NA; categories are inconsistent with input codes
**Example:**
```r
# WRONG: tries to look up the full concatenated string
CANCER_SITE_MAP["C81.10;C77.9"]  # Returns NA

# CORRECT: split, map each, rejoin
codes <- c("C81.10", "C77.9")
categories <- sapply(codes, function(c) CANCER_SITE_MAP[substr(c, 1, 3)])
paste(categories, collapse = ";")  # "Hodgkin Lymphoma (non-NLPHL);Lymph Node Neoplasm"
```

### Pitfall 2: Using classify_codes() for Multi-Code Strings
**What goes wrong:** classify_codes() in R/utils/utils_cancer.R is vectorized but returns ONE category per code (first match in 4-tier cascade). It doesn't handle semicolon-separated lists.
**Why it happens:** Function signature is `classify_codes(icd_codes)` where `icd_codes` is a character vector of individual codes, not a vector of semicolon-delimited strings.
**How to avoid:** Split semicolon-separated strings into individual codes BEFORE calling classify_codes(), or write a wrapper that does split → classify → rejoin
**Warning signs:** Error "argument is of length zero" or unexpected NA results when passing "C81.10;C77.9"
**Example:**
```r
# WRONG:
classify_codes("C81.10;C77.9")  # Tries to match the whole string, fails

# CORRECT:
codes <- str_split("C81.10;C77.9", ";")[[1]]
categories <- classify_codes(codes)
paste(unique(categories), collapse = ";")
```

### Pitfall 3: Forgetting ICD-9 Code Handling
**What goes wrong:** Only checking CANCER_SITE_MAP (ICD-10) and missing ICD-9 codes (201.x, 140-209 range)
**Why it happens:** R/56 current implementation uses is_cancer_code() which checks both maps, but a naive rewrite might forget ICD9_CANCER_SITE_MAP
**How to avoid:** Use classify_codes() or replicate its 4-tier logic (C810 4-char → C81 3-char → ICD9 4-char → ICD9 3-char)
**Warning signs:** Patients with ICD-9 codes (pre-2015 diagnoses) have NA cancer_category_names; Phase 87 smoke test fails (Section 30 checks ICD-9 mapping)
**Example:**
```r
# WRONG: Only checks ICD-10
prefix_3 <- substr(code, 1, 3)
category <- CANCER_SITE_MAP[[prefix_3]]  # Misses 201.x ICD-9 HL codes

# CORRECT: Check both maps
if (prefix_3 %in% names(CANCER_SITE_MAP)) {
  category <- CANCER_SITE_MAP[[prefix_3]]
} else if (prefix_3 %in% names(ICD9_CANCER_SITE_MAP)) {
  category <- ICD9_CANCER_SITE_MAP[[prefix_3]]
}
```

### Pitfall 4: Descending Sort on Category Names, Not Codes
**What goes wrong:** User specified "sorted in descending order" for cancer category names (D-04). Sorting the raw ICD codes before mapping will give wrong results because codes sort differently than category names.
**Why it happens:** Temptation to sort codes (C81.10, C77.9) before mapping, but "C81" < "C77" alphabetically while "Hodgkin Lymphoma (non-NLPHL)" > "Lymph Node Neoplasm" alphabetically descending
**How to avoid:** Map codes to categories FIRST, then sort the category names in descending order, then collapse
**Warning signs:** Category name order doesn't match descending alphabetical sort
**Example:**
```r
# WRONG: sorts codes before mapping
codes <- sort(str_split("C81.10;C77.9", ";")[[1]], decreasing = TRUE)  # "C81.10", "C77.9"
# Maps to: "Hodgkin Lymphoma (non-NLPHL);Lymph Node Neoplasm" (wrong order)

# CORRECT: map first, then sort categories
codes <- str_split("C81.10;C77.9", ";")[[1]]
categories <- sapply(codes, map_to_category)
paste(sort(unique(categories), decreasing = TRUE), collapse = ";")
# "Lymph Node Neoplasm;Hodgkin Lymphoma (non-NLPHL)" (descending alpha)
```

### Pitfall 5: Multiple Sub-Categories Per Episode
**What goes wrong:** An episode has triggering_codes = "J9000,J9042,J9360" (3 distinct chemo drugs). Unclear if output should have 1 row with semicolon-separated sub_category or 3 rows (one per drug).
**Why it happens:** User decision D-05 says "one row per patient + treatment type + episode" but doesn't specify grain within an episode when multiple distinct codes exist
**How to avoid:** Treat this as Claude's discretion per CONTEXT.md. Options: (1) semicolon-separated sub-category column (matches R/56 Table 2 pattern), (2) one row per code (explode triggering_codes first, like R/56 Table 1 pre-aggregation), or (3) "Mixed regimen" label when >1 sub-category
**Warning signs:** Episode with 3 drugs appears 3 times with same episode_number (unexpected row grain), or sub_category column has long semicolon lists that are hard to read
**Recommendation:** **Option 1 (semicolon-separated)** matches existing R/56 Table 2 pattern and user's request for "list each instance" at episode grain (not code grain). If user wants code-level grain, they'll request a change.

## Code Examples

Verified patterns from existing R/56 and established utilities:

### Common Operation 1: Load treatment_episodes.rds and Extract Required Columns
```r
# Source: R/56 lines 108-119 + R/28 lines 498-509
source("R/00_config.R")  # Auto-sources utils, loads CANCER_SITE_MAP, CODE_SUBCATEGORY_MAP, DRUG_GROUPINGS
source("R/utils/utils_assertions.R")

EPISODES_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
assert_rds_exists(EPISODES_RDS, script_name = "R/57")

episodes <- readRDS(EPISODES_RDS)
message(glue("Loaded {nrow(episodes)} treatment episodes"))

# Required columns from treatment_episodes.rds (per R/28 final select):
# patient_id, treatment_type, episode_number, episode_start, episode_stop,
# triggering_codes, encounter_ids, cancer_category (computed from cancer_codes at R/56 Section 4)
```

### Common Operation 2: Build Sub-Category Mappings from Reference xlsx
```r
# Source: R/56 Section 3 lines 122-160
library(openxlsx2)

REFERENCE_XLSX <- "data/reference/all_codes_resolved_next_tables_v2.1.xlsx"
assert_file_exists(REFERENCE_XLSX, .var.name = "[R/57 ERROR] Reference XLSX")
ref_wb <- wb_load(REFERENCE_XLSX)

# Chemo: code -> medication name (column C)
chemo_sheet <- wb_to_df(ref_wb, sheet = "Chemotherapy", start_row = 2)
chemo_map <- setNames(as.character(chemo_sheet[[3]]), as.character(chemo_sheet[[1]]))
chemo_map <- chemo_map[!is.na(names(chemo_map)) & !is.na(chemo_map)]

# Radiation: code -> type (column G)
rad_sheet <- wb_to_df(ref_wb, sheet = "Radiation", start_row = 2)
rad_map <- setNames(as.character(rad_sheet[[7]]), as.character(rad_sheet[[1]]))
rad_map <- rad_map[!is.na(names(rad_map)) & !is.na(rad_map)]

# SCT: code -> type (column G)
sct_sheet <- wb_to_df(ref_wb, sheet = "SCT", start_row = 2)
sct_map <- setNames(as.character(sct_sheet[[7]]), as.character(sct_sheet[[1]]))
sct_map <- sct_map[!is.na(names(sct_map)) & !is.na(sct_map)]

# Combined lookup
code_to_subcategory <- c(chemo_map, rad_map, sct_map)
message(glue("Total codes with sub-categories: {length(code_to_subcategory)}"))
```

### Common Operation 3: Map Semicolon-Separated Cancer Codes to Category Names
```r
# Source: Adapted from R/56 Section 4 lines 169-219 + R/utils/utils_cancer.R classify_codes() logic
map_cancer_codes_to_categories <- function(cancer_codes) {
  if (is.na(cancer_codes) || cancer_codes == "") return(NA_character_)

  codes <- str_split(cancer_codes, ";")[[1]]

  categories <- sapply(codes, function(code) {
    # 4-tier cascade: C810 (4-char) → C81 (3-char) → 2014 (ICD-9 4-char) → 201 (ICD-9 3-char)
    prefix_4 <- substr(code, 1, 4)
    prefix_3 <- substr(code, 1, 3)

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

  # Remove NAs, keep unique, sort descending (per D-04), rejoin
  categories <- categories[!is.na(categories)]
  if (length(categories) == 0) return(NA_character_)

  paste(sort(unique(categories), decreasing = TRUE), collapse = ";")
}

# Apply to all episodes
episodes <- episodes %>%
  mutate(cancer_category_names = sapply(cancer_codes, map_cancer_codes_to_categories, USE.NAMES = FALSE))
```

### Common Operation 4: Build Instance-Level Table 1 (Sub-Category Detail)
```r
# Source: R/56 Section 5 lines 245-528 (refactored to per-episode grain)
# Split triggering_codes and map to sub-categories (reuse R/56 3-tier logic)
episode_codes <- episodes %>%
  mutate(code_list = str_split(triggering_codes, ",\\s*")) %>%
  unnest(code_list) %>%
  filter(!is.na(code_list), code_list != "") %>%
  rename(treatment_code = code_list) %>%
  mutate(category = ifelse(
    treatment_code %in% names(DRUG_GROUPINGS),
    DRUG_GROUPINGS[treatment_code],
    treatment_type
  ))

# 3-tier sub-category resolution (same as R/56 lines 322-369)
episode_codes <- episode_codes %>%
  mutate(
    sub_category = case_when(
      treatment_code %in% names(code_to_subcategory) ~ code_to_subcategory[treatment_code],
      treatment_code %in% names(CODE_SUBCATEGORY_MAP) ~ CODE_SUBCATEGORY_MAP[treatment_code],
      category == "Immunotherapy" ~ "Immunotherapy",  # Simplified; full R/56 has detailed fallback
      TRUE ~ paste0(category, " (unmapped)")
    )
  )

# Aggregate back to episode level with semicolon-separated sub_category
table1 <- episode_codes %>%
  group_by(patient_id, episode_number, episode_start, episode_stop, treatment_type, category, cancer_category_names) %>%
  summarise(
    sub_category = paste(sort(unique(sub_category)), collapse = ";"),
    .groups = "drop"
  ) %>%
  filter(!is.na(cancer_category_names)) %>%  # Exclude episodes without cancer diagnosis
  select(patient_id, episode_start, episode_stop, episode_number, category, sub_category, cancer_category_names)

message(glue("Table 1: {nrow(table1)} episode rows"))
```

### Common Operation 5: Build Instance-Level Table 2 (Encounter Treatment Detail)
```r
# Source: R/56 Section 6 lines 531-569 (simplified to per-episode grain)
# Table 2 shows all treatments per episode (not aggregated by treatment set)
table2 <- episodes %>%
  filter(!is.na(cancer_category_names), !is.na(triggering_codes)) %>%
  mutate(all_treatments = triggering_codes) %>%  # Rename for clarity
  select(patient_id, episode_start, episode_stop, episode_number, treatment_type, all_treatments, cancer_category_names)

message(glue("Table 2: {nrow(table2)} episode rows"))
```

### Common Operation 6: Write Multi-Sheet xlsx Output
```r
# Source: R/56 Section 7 lines 571-589
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "drug_grouping_instances.xlsx")

wb <- wb_workbook()

wb$add_worksheet("Treatment Sub-Category Summary")
wb$add_data("Treatment Sub-Category Summary", table1, start_row = 1, col_names = TRUE)

wb$add_worksheet("Encounter Treatment Summary")
wb$add_data("Encounter Treatment Summary", table2, start_row = 1, col_names = TRUE)

wb$save(OUTPUT_XLSX)
message(glue("Saved: {OUTPUT_XLSX}"))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Aggregated counts by sub-category | Instance-level per-episode rows | Phase 88 | Exploratory analysis shifts from "how many times did X occur" to "which patients got X and when" — enables patient-level traceability |
| Raw ICD codes in output (C81.10;C77.9) | Cancer site category names (Hodgkin Lymphoma;Lymph Node Neoplasm) | Phase 88 | Human-readable outputs reduce need for codebook lookups |
| Treatment codes as identifiers (J9000) | Sub-category names as primary descriptors (Doxorubicin) | Phase 88 | Non-technical stakeholders can interpret outputs without medical coding knowledge |

**Deprecated/outdated:**
- None — this is a net-new output format, not a replacement

## Open Questions

1. **Multiple sub-categories per episode: semicolon-separated or explode to multiple rows?**
   - What we know: D-05 says "one row per patient + treatment type + episode" (episode grain), but some episodes have 3+ distinct drugs
   - What's unclear: User preference for readability vs granularity
   - Recommendation: Default to semicolon-separated (matches R/56 Table 2 pattern, preserves episode grain). If user wants code-level grain, they'll request it in verification.

2. **Should cancer_category_names include duplicates from multiple ICD codes mapping to the same category?**
   - What we know: D-04 says "sorted in descending order" but doesn't specify whether to deduplicate
   - What's unclear: If C81.10 and C81.20 both map to "Hodgkin Lymphoma (non-NLPHL)", should output be "Hodgkin Lymphoma (non-NLPHL);Hodgkin Lymphoma (non-NLPHL)" or just "Hodgkin Lymphoma (non-NLPHL)"?
   - Recommendation: **Deduplicate** with `unique()` before collapsing — showing the same category twice adds no information and clutters output. Code example already includes `unique()` in operation 3.

3. **New xlsx filename preference?**
   - What we know: Claude's discretion per CONTEXT.md
   - What's unclear: User's naming convention preference
   - Recommendation: `drug_grouping_instances.xlsx` (parallel to `drug_grouping_tables.xlsx`, clearly distinguishes instance-level from aggregated)

## Environment Availability

Phase 88 is a pure R data transformation with no external tool dependencies beyond the existing project stack. All required components are already available:

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| R | All R/ scripts | ✓ | 4.4.2 (HiPerGator module) | — |
| dplyr | Data transformation | ✓ | 1.2.0+ (tidyverse) | — |
| tidyr | unnest() for code splitting | ✓ | 1.3.1+ (tidyverse) | — |
| stringr | String manipulation | ✓ | 1.5.1+ (tidyverse) | — |
| openxlsx2 | Multi-sheet xlsx output | ✓ | 1.4+ (installed Phase 50) | — |
| glue | Logging | ✓ | 1.8.0 | — |
| checkmate | Input validation | ✓ | 2.3.2+ (loaded in 00_config.R) | — |
| treatment_episodes.rds | Input data | ✓ | Output from R/28 | — |
| CANCER_SITE_MAP | ICD-10 mapping | ✓ | R/00_config.R (200+ entries) | — |
| ICD9_CANCER_SITE_MAP | ICD-9 mapping | ✓ | R/00_config.R (70+ entries, Phase 87) | — |
| CODE_SUBCATEGORY_MAP | Treatment code mapping | ✓ | R/00_config.R (326+ entries, Phase 81) | — |
| DRUG_GROUPINGS | Treatment category | ✓ | R/00_config.R (454+ entries, Phase 77) | — |
| all_codes_resolved_next_tables_v2.1.xlsx | Sub-category xlsx mappings | ✓ | data/reference/ (Phase 81) | — |

**Missing dependencies with no fallback:**
- None

**Missing dependencies with fallback:**
- None

## Validation Architecture

> Skipped — workflow.nyquist_validation is explicitly set to false in .planning/config.json

## Sources

### Primary (HIGH confidence)
- R/56_new_tables_from_groupings.R (lines 1-620) — current drug grouping summary tables implementation; source of sub-category resolution logic, cancer code aggregation, xlsx output pattern
- R/28_episode_classification.R (lines 498-509) — treatment_episodes.rds column structure and content
- R/00_config.R (lines 537-834, 1882-2200) — CANCER_SITE_MAP, ICD9_CANCER_SITE_MAP, CODE_SUBCATEGORY_MAP, DRUG_GROUPINGS structure and coverage
- R/utils/utils_cancer.R (classify_codes() function) — 4-tier ICD prefix matching logic (C810 → C81 → ICD9 4-char → ICD9 3-char)
- .planning/phases/88-re-do-tables-from-grouping-by-using-descriptives-from-codes-instead-of-counts-and-instead-of-counts-just-list-each-instance/88-CONTEXT.md — user decisions and constraints
- CLAUDE.md STACK.md section (lines 1-200) — tidyverse version verification, package standards

### Secondary (MEDIUM confidence)
- R/88_smoke_test_comprehensive.R (lines 982-1034) — R/56 validation checks confirming 2-sheet structure, CODE_SUBCATEGORY_MAP integration, 3-tier lookup pattern

### Tertiary (LOW confidence)
- None — all research verified against project code or official documentation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all packages already installed and verified in project renv.lock
- Architecture: HIGH - R/56 existing code provides 90% of required logic; only new operation is cancer code-to-category mapping
- Pitfalls: HIGH - identified from R/56 code review (semicolon handling, ICD-9 map checking, sort order) and R/utils/utils_cancer.R function behavior

**Research date:** 2026-06-04
**Valid until:** 60 days (2026-08-03) — stable domain; project stack frozen at tidyverse 2.0.0, openxlsx2 1.4+, no upstream API changes expected
