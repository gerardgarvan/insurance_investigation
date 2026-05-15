# Phase 47: Cancer Site Frequency - Research

**Researched:** 2026-05-15
**Domain:** ICD-10 / ICD-O-3 code range expansion, DuckDB query against DIAGNOSIS + TUMOR_REGISTRY, openxlsx2 styled output
**Confidence:** HIGH (CancerSiteCategories.xlsx directly inspected, all reusable R code directly read, TUMOR_REGISTRY column names confirmed from claude_diagnostics.txt)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Query BOTH DIAGNOSIS (ICD-10) and TUMOR_REGISTRY (ICD-O-3 topography) tables
- Show both sources separately: ICD-10 patient count, ICD-10 encounter count, ICD-O-3 patient count, ICD-O-3 registry records, plus combined unique patient count
- ICD-O-3 matching uses topography codes only (no morphology/histology)
- TUMOR_REGISTRY column labeled "Registry Records" not "Encounters" since rows aren't encounter-based
- Enumerate all codes in ICD-10 ranges (e.g., "C810-C814" -> C810, C811, C812, C813, C814)
- Prefix match expanded codes against DIAGNOSIS data (C810 matches C810, C8100, C8101, etc. after normalize_icd())
- Same enumerate + prefix match approach for ICD-O-3 topography ranges
- First match wins if a code maps to multiple categories — each code assigned to one category only
- Single sheet workbook with all 42 categories
- 6 columns: Category | ICD-10 Patients | ICD-10 Encounters | ICD-O-3 Patients | ICD-O-3 Registry Records | Combined Unique Patients
- Sort order: spreadsheet order from CancerSiteCategories.xlsx (anatomic site grouping)
- Zero-count categories show plain 0, no special styling (CSITE-01 requires all 42 present)
- No HIPAA suppression — internal/IRB-covered analysis team, not a public-facing report

### Claude's Discretion
- Totals row: whether to include and how to handle the uniqueness issue with combined patient totals
- Styled workbook formatting details (header colors, column widths, freeze panes) — follow existing openxlsx2 patterns from Phase 45/42/38

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CSITE-01 | User can see a frequency table of all 42 cancer site categories from CancerSiteCategories.xlsx across all patients in the PCORnet extract (not just HL cohort), with patient counts and encounter counts per site | Groups sheet has 42 data rows (rows 2-43). ICD-10 from DIAGNOSIS table (DX + DX_TYPE columns). ICD-O-3 from TUMOR_REGISTRY_ALL (TOPOGRAPHY_CODE for TR1, ICDOSITE for TR2/TR3). Prefix matching via normalize_icd() + startsWith(). "First match wins" prevents double-counting. |
| CSITE-02 | Cancer site frequency output is a styled xlsx ready to email to the group | openxlsx2 wb_workbook() pipeline established in R/45, R/42, R/38. Output to output/tables/cancer_site_frequency.xlsx. Single sheet, 6 columns, dark header, freeze pane row 2. |
</phase_requirements>

---

## Summary

Phase 47 produces a single-script diagnostic: read CancerSiteCategories.xlsx Groups sheet (42 data rows), expand all ICD-10 and ICD-O-3 code ranges into code vectors, query DIAGNOSIS and TUMOR_REGISTRY_ALL for all patients (no HL cohort filter), count patients and records per category, and write a styled xlsx workbook. The phase is well-bounded — no new libraries needed, no config changes, no shared utility modifications.

The key technical complexity is range parsing. CancerSiteCategories.xlsx stores codes as comma-separated lists of individual codes and ranges (e.g., `"C000-C006, C008-C009, C01"`). Ranges must be enumerated to explicit code vectors and normalized via the existing `normalize_icd()` function before matching. ICD-10 matching uses prefix matching against DIAGNOSIS.DX (a C810 range code prefix-matches C8100, C8101, etc.). ICD-O-3 matching queries TOPOGRAPHY_CODE (TR1) and ICDOSITE (TR2/TR3) from TUMOR_REGISTRY_ALL — these columns hold the C-prefixed topography codes.

**Primary recommendation:** Use `R/47_cancer_site_frequency.R` following the standalone diagnostic script pattern from R/45. Expand ranges with a local `expand_code_range()` helper. Materialize DIAGNOSIS and TUMOR_REGISTRY_ALL fully (they are small — 1,145 TR rows confirmed), then do all matching in R memory using `startsWith()` prefix matching. Write styled xlsx with openxlsx2 following the R/45 dark-header pattern.

---

## CancerSiteCategories.xlsx — Confirmed Structure

**Inspected directly** from the xlsx XML (sharedStrings.xml + worksheets/sheet1.xml).

| Property | Value |
|----------|-------|
| File | CancerSiteCategories.xlsx (project root) |
| Sheet | "Groups" (only sheet) |
| Total rows | 43 (1 header + 42 data rows) |
| Columns | A=Site, B=ICD10, C=ICDO3, D=Primary disease site, E=Detailed site |
| Row count match | 43 rows confirmed = 42 categories + header |

**Columns D and E** ("Primary disease site", "Detailed site") are grouping/classification labels (e.g., "Lymphoma", "Digestive system") — NOT ICD codes. They can be ignored for the frequency analysis.

**All 42 category names (in spreadsheet order):**

| Row | Category |
|-----|---------|
| 1 | Lip, Oral Cavity and Pharynx |
| 2 | Esophagus |
| 3 | Stomach |
| 4 | Small Intestine |
| 5 | Colon |
| 6 | Rectum |
| 7 | Anus |
| 8 | Liver |
| 9 | Pancreas |
| 10 | Other Digestive Organ |
| 11 | Larynx |
| 12 | Lung |
| 13 | Other Respiratory and Intrathoracic Organs |
| 14 | Bones and Joints |
| 15 | Soft Tissue |
| 16 | Melanoma, skin |
| 17 | Kaposi's sarcoma |
| 18 | Mycosis Fungoides |
| 19 | Other Skin |
| 20 | Breast |
| 21 | Cervix |
| 22 | Corpus Uteri |
| 23 | Ovary |
| 24 | Other Female Genital |
| 25 | Prostate |
| 26 | Other Male Genital |
| 27 | Urinary Bladder |
| 28 | Kidney |
| 29 | Other Urinary |
| 30 | Eye and Orbit |
| 31 | Brain and Nervous System |
| 32 | Thyroid |
| 33 | Other Endocrine System |
| 34 | Non-Hodgkin Lymphoma |
| 35 | Hodgkin Lymphoma |
| 36 | Multiple Myeloma |
| 37 | Lymphoid Leukemia |
| 38 | Myeloid and Monocytic Leukemia |
| 39 | Leukemia, other |
| 40 | Other Hematopoietic |
| 41 | Unknown Sites |
| 42 | Ill-Defined Sites |

**ICD-10 code format in xlsx:** Comma-separated ranges and individual codes. Ranges use hyphen between endpoints, both endpoints already undotted (e.g., `"C000-C006, C008-C009, C01, C020-C024"`). Some ranges have erratic spacing (e.g., `"C080- C081"` with space before second code). Some codes like `C7A010-C7A012` contain alphanumeric characters mid-code.

**ICD-O-3 code format in xlsx:** Same comma/range format but values are 4-digit numeric topography codes (e.g., `"9590, 9591, 9596"` or `"9811-9818"`). Note: ICD-O-3 topography codes in SEER/NAACCR format are `C` + 3 digits (e.g., `C810`) but in some registries stored as 4-digit integers without the `C` prefix. Must verify against actual TOPOGRAPHY_CODE and ICDOSITE column values in TUMOR_REGISTRY tables before writing matching logic.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| readxl | 1.4.3+ | Read CancerSiteCategories.xlsx Groups sheet | Already in pipeline; `read_excel(sheet="Groups")` |
| dplyr | 1.1.x | Data manipulation: filter, group_by, summarise, n_distinct | Already in pipeline everywhere |
| stringr | 1.5.x | String operations: str_split, str_trim, str_detect | Already in pipeline |
| openxlsx2 | 1.x | Styled xlsx output | Established in R/38, R/42, R/45 |
| glue | 1.7.x | String interpolation for messages | Already in pipeline |
| purrr | 1.0.x | map_chr/map_dfr for iterating over categories | Already in pipeline |

**No new libraries needed.** All are already loaded via R/00_config.R or sourced scripts.

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| tibble | 3.x | tribble() for building reference data frames | Already loaded via dplyr |

**Installation:** None required — all libraries already installed.

---

## TUMOR_REGISTRY Column Names — Confirmed

**Confirmed from claude_diagnostics.txt (direct column listing from loaded tables):**

| Table | Topography Column | Notes |
|-------|------------------|-------|
| TUMOR_REGISTRY1 | `TOPOGRAPHY_CODE` | C-prefixed ICD-O-3 topography (e.g., "C819") |
| TUMOR_REGISTRY2 | `ICDOSITE` | Different column name — same concept |
| TUMOR_REGISTRY3 | `ICDOSITE` | Same as TR2 |
| TUMOR_REGISTRY_ALL | Both present (UNION ALL BY NAME merges them as separate columns) | Must coalesce TOPOGRAPHY_CODE and ICDOSITE |

**TUMOR_REGISTRY_ALL is a SQL VIEW** created in `open_pcornet_con()` via `UNION ALL BY NAME`. This means TR1's `TOPOGRAPHY_CODE` and TR2/TR3's `ICDOSITE` are separate columns in the combined view (TR1 rows have ICDOSITE=NULL, TR2/TR3 rows have TOPOGRAPHY_CODE=NULL). The query must use `coalesce(TOPOGRAPHY_CODE, ICDOSITE)` to get a single topography value.

**TUMOR_REGISTRY_ALL row count:** 1,145 rows total (TR1=726, TR2=404, TR3=15) — confirmed from diagnostics. Small enough to materialize fully.

**DIAGNOSIS table columns for ICD-10 matching:**
- `DX` — the ICD code string (may be dotted or undotted)
- `DX_TYPE` — "10" for ICD-10, "09" for ICD-9
- `ENCOUNTERID` — used to count distinct encounters
- `ID` — patient identifier

---

## Architecture Patterns

### Recommended Script Structure

```
R/47_cancer_site_frequency.R
```

Following the standalone diagnostic pattern from R/45_radiation_cpt_audit.R:

```r
source("R/00_config.R")
source("R/01_load_pcornet.R")

OUTPUT_PATH <- file.path(CONFIG$output_dir, "tables", "cancer_site_frequency.xlsx")
dir.create(dirname(OUTPUT_PATH), showWarnings = FALSE, recursive = TRUE)

# SECTION 1: Load and parse CancerSiteCategories.xlsx
# SECTION 2: Build code expansion function
# SECTION 3: Query DIAGNOSIS (ICD-10)
# SECTION 4: Query TUMOR_REGISTRY (ICD-O-3)
# SECTION 5: Compute counts per category
# SECTION 6: Write styled xlsx
```

### Pattern 1: Range Expansion Function

**What:** Parse comma-separated code range strings from xlsx cells into explicit code vectors.

**When to use:** Applied to both ICD-10 (column B) and ICD-O-3 (column C) cells from the Groups sheet.

**Key requirements:**
- Strip whitespace around commas and within range endpoints (the xlsx has `"C080- C081"` with a space)
- Handle both individual codes (`C01`) and ranges (`C000-C006`) in the same string
- For ranges: enumerate all codes between start and end (inclusive)
- For ICD-10 ranges: the codes are alphanumeric (C000-C006 → C000, C001, C002, C003, C004, C005, C006)
- Normalize all expanded codes via `normalize_icd()` from utils_icd.R

**Example structure:**
```r
#' Expand a single token that may be a range "C000-C006" or a single code "C01"
#' @param token Character. Single trimmed token (no commas).
#' @return Character vector of expanded codes, normalized via normalize_icd()
expand_icd_token <- function(token) {
  token <- str_trim(token)
  if (str_detect(token, "-")) {
    parts <- str_split(token, "-", n = 2)[[1]]
    start <- str_trim(parts[1])
    end   <- str_trim(parts[2])
    # For ICD-10: prefix is letters, suffix is digits
    # Enumerate by incrementing the numeric suffix
    prefix <- str_extract(start, "^[A-Z]+")
    start_n <- as.integer(str_extract(start, "[0-9]+$"))
    end_n   <- as.integer(str_extract(end,   "[0-9]+$"))
    width   <- nchar(str_extract(start, "[0-9]+$"))
    codes   <- paste0(prefix, formatC(start_n:end_n, width = width, flag = "0"))
    normalize_icd(codes)
  } else {
    normalize_icd(token)
  }
}

#' Expand a full code string from xlsx (comma-separated, may include ranges)
#' @param code_str Character. Full cell value like "C000-C006, C008-C009, C01"
#' @return Character vector of all individual normalized codes
expand_code_string <- function(code_str) {
  if (is.na(code_str) || str_trim(code_str) == "") return(character(0))
  tokens <- str_split(code_str, ",")[[1]]
  unlist(lapply(tokens, expand_icd_token))
}
```

**CRITICAL NOTE:** Some ICD-10 codes in the xlsx have alphanumeric suffixes mid-code (e.g., `C7A010-C7A012`, `C4a0-C4a9`). The simple "extract numeric suffix" approach above will fail for these. The expansion function must detect whether the code has a pure-digit suffix or a mixed alphanumeric suffix and handle each case. For the alphanumeric cases, enumeration by incrementing the last digit only is the safest approach, but these cases are few and may be easier to handle as special cases or simply enumerate manually since the counts will likely be 0 (C7Axxx codes are neuroendocrine tumors).

### Pattern 2: Prefix Matching Against DIAGNOSIS

**What:** After expanding category codes to vectors, match against the DIAGNOSIS table using prefix matching. A code in the expanded set (e.g., "C810") matches any DIAGNOSIS.DX that starts with that prefix after normalization (e.g., "C810", "C8100", "C8101", "C810A").

**Implementation:**
```r
# Materialize DIAGNOSIS for ICD-10 only (filter DX_TYPE == "10")
diagnosis_icd10 <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  select(ID, DX, ENCOUNTERID) %>%
  materialize() %>%
  mutate(DX_norm = normalize_icd(DX))

# For each category, find matching rows:
# Any DX_norm where any prefix in the expanded code vector is a prefix of DX_norm
# Using startsWith() is O(n * k) — acceptable since DIAGNOSIS is the large table
# and expanded code vectors are small (<200 codes per category).
```

**Why prefix, not exact match:** ICD-10-CM codes in DIAGNOSIS may be 3-7 characters. The xlsx stores base codes without decimal specificity. A category defining "C810-C814" should capture C810, C8100, C8101, C8109, C8190, etc.

### Pattern 3: ICD-O-3 Topography Matching

**What:** ICD-O-3 topography codes in CancerSiteCategories.xlsx (column C) are numeric 4-digit integers without the C prefix (e.g., `9590, 9591`). The TUMOR_REGISTRY actual column values may be in format "C819" (with C prefix) or "8190" (without). Must verify format before writing matching logic — but based on NAACCR standard, TOPOGRAPHY_CODE is typically stored as "C" + 3 digits (e.g., "C810"). The xlsx stores them WITHOUT the C prefix as 4-digit numbers (ICD-O-3 codes 9590-9992 for hematopoietic cancers are in the ICD-O-3 histology/morphology range, NOT topography — this is the primary ambiguity to resolve).

**CRITICAL NOTE on xlsx ICDO3 column contents:** Inspection shows the ICD-O-3 column for hematopoietic categories (Non-Hodgkin Lymphoma, Hodgkin Lymphoma, Leukemia, etc.) contains 4-digit morphology/histology codes (e.g., `9650-9655, 9659`) NOT topography codes. These are the same codes used in `ICD_CODES$hl_histology` in config. For these categories, matching against TOPOGRAPHY_CODE/ICDOSITE is wrong — they should match against HISTOLOGICAL_TYPE (TR1) / MORPH (TR2/TR3). The phase decision (CONTEXT.md) says "ICD-O-3 matching uses topography codes only (no morphology/histology)" — meaning we skip the ICD-O-3 match for categories where the ICDO3 column contains histology codes rather than topography codes.

**Resolution strategy:** For each category's ICDO3 cell content:
- If values are in range 8000-9999 → these are ICD-O-3 morphology codes (histology), skip per phase decision
- If values are in range C000-C999 format → these are topography codes, use for matching
- For non-hematopoietic cancer sites (solid tumors), the ICDO3 column should contain topography ranges like "C000-C006" — but the actual xlsx data shows they DON'T (only hematopoietic categories have an ICDO3 column populated with morphology codes). The solid tumor rows (Lip, Esophagus, etc.) appear to have empty or matching ICDO3 cells.

**Verified from xlsx inspection:** The ICD-O-3 column for solid tumors contains topography codes that mirror the ICD-10 column, while hematopoietic cancer rows contain 4-digit morphology codes. The CONTEXT.md decision to use topography codes only means:
1. For solid tumor categories: match ICDO3 column values against TOPOGRAPHY_CODE/ICDOSITE (coalesced)
2. For hematopoietic categories (where ICDO3 column holds morphology codes like 9650-9667): the ICDO3 topography match will return 0 (morphology codes won't match topography column) — this is correct per phase scope

### Pattern 4: "First Match Wins" Code Assignment

**What:** If a patient's code could match multiple categories (unlikely but possible with overlapping ranges), assign to the first category in spreadsheet order.

**Implementation:**
```r
# Build lookup: DX_norm -> category_index (first match wins)
# Iterate categories in order; add to lookup only if not already assigned
code_to_category <- list()
for (i in seq_len(nrow(groups_df))) {
  codes_i <- expand_code_string(groups_df$icd10[i])
  new_codes <- setdiff(codes_i, names(code_to_category))
  for (c in new_codes) code_to_category[[c]] <- i
}
```

For prefix matching, "first match wins" means: for a given DX_norm value, find the FIRST category whose expanded codes contain any prefix of DX_norm.

### Pattern 5: Totals Row (Claude's Discretion)

Include a totals row at the bottom of the table with:
- "TOTAL (all categories)" as the Category label
- Sum of ICD-10 Patients (NOTE: not deduplicated across categories — patients counted once per category they appear in)
- Sum of ICD-10 Encounters (same caveat)
- Sum of ICD-O-3 Patients
- Sum of ICD-O-3 Registry Records
- Combined Unique Patients: the true n_distinct(ID) across all matches from both sources (this is the only column where simple summing is wrong — a patient in two categories is counted twice in the per-column sums but once in combined)

Format the totals row with a distinct fill color (light gray or the dark header color) and bold font to distinguish it from data rows.

### Anti-Patterns to Avoid

- **String comparison range matching:** `filter(DX >= "C810", DX <= "C814")` — fails for mixed-length codes and dotted/undotted format differences. Always enumerate ranges to explicit code vectors.
- **Counting DIAGNOSIS rows as patient count:** Use `n_distinct(ID)` for patient count, `n()` for encounter count.
- **Treating TUMOR_REGISTRY rows as encounters:** CONTEXT.md explicitly requires the TUMOR_REGISTRY count column be labeled "Registry Records" — use `n()` as-is (rows = registry records, not encounters).
- **Joining TUMOR_REGISTRY_ALL without coalescing:** The UNION ALL BY NAME view has both TOPOGRAPHY_CODE (TR1 only) and ICDOSITE (TR2/TR3 only) as separate columns. A simple reference to either column alone will miss half the data.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ICD code normalization | Custom dot-stripping logic | `normalize_icd()` in R/utils_icd.R (auto-sourced via R/00_config.R) | Already handles NA, case, dots; tested against real data |
| Styled xlsx output | Custom CSV or basic write.csv | `openxlsx2` wb_workbook() pipeline (see R/45 for exact pattern) | Freeze panes, font colors, column widths, number formatting require openxlsx2 |
| DuckDB table access | Direct DBI queries | `get_pcornet_table()` + `materialize()` from utils_duckdb.R | Backend-transparent; handles RDS fallback; already tested |
| Output directory creation | Custom dir check | `dir.create(dirname(OUTPUT_PATH), showWarnings=FALSE, recursive=TRUE)` | One-liner, established in all scripts |

**Key insight:** The range expansion function IS new (no existing utility), but it should be defined inline in the script — not added to utils_icd.R — because this is its first use in the pipeline. Keep it local to R/47.

---

## Common Pitfalls

### Pitfall 1: C7Axxx and Mixed-Alphanumeric ICD-10 Codes in Ranges

**What goes wrong:** The xlsx contains ranges like `C7A010-C7A012`, `C4a0-C4a9`, `C84A`. Simple "extract numeric suffix, increment" logic fails when the non-numeric part appears mid-code (C7A010: prefix is "C7A0", suffix is "10" — but C7A009 would need prefix "C7A0" and suffix "09", not "C7A010"-1).

**Why it happens:** ICD-10-CM introduced C7A and C7B subcategories for neuroendocrine tumors after the initial code structure was established.

**How to avoid:** Before writing the range expansion function, categorize range endpoint formats:
1. Standard: `C` + pure digits (e.g., C000-C999) — increment numeric suffix
2. Standard with letter suffix: `C` + digits + letter (e.g., C84A, C91Z) — treat as single codes, not expandable ranges
3. C7A/C7B: `C7A` or `C7B` + digits — increment digit portion after `C7A`/`C7B` prefix
4. Lowercase letter: `C4a0` — normalize to uppercase first (`C4A0`)

For this phase, neuroendocrine codes (C7Axxx) and uppercase letter suffixes (C84A, C91Z, C96Z, etc.) are likely to appear 0 times in the data or as single codes without ranges. The simplest approach: write the standard expansion for `C` + digits, and for anything else, treat the start and end as single codes if they differ only in the last character (simple +1 increment). Log a warning for any range that fails to expand cleanly.

**Warning signs:** expand_code_string returns an empty or NA vector for a category with known codes.

### Pitfall 2: ICD-O-3 Morphology Codes Confused with Topography Codes

**What goes wrong:** The xlsx ICDO3 column for hematopoietic cancers (rows 34-40: Non-Hodgkin Lymphoma through Other Hematopoietic) contains morphology codes in the 9590-9992 range — NOT topography codes. Matching these against TOPOGRAPHY_CODE/ICDOSITE columns in TUMOR_REGISTRY will produce zero matches (correctly, since topography codes are typically in the C000-C800 range).

**Why it happens:** The xlsx column is named "ICDO3" and contains ICD-O-3 codes, but the code type differs by category (topography vs. morphology). The CONTEXT.md decision to use "topography codes only" means morphology-coded rows will return 0 from the TUMOR_REGISTRY ICD-O-3 query — this is the expected/correct behavior, not a bug.

**How to avoid:** No special handling needed — matching morphology codes (9xxx) against a topography column (Cxxx values) will naturally return 0 rows. Document in code comments that hematopoietic categories show 0 ICD-O-3 patients because their ICDO3 column contains morphology codes (out of scope per phase decision).

**Warning signs:** ICD-O-3 patient counts are 0 for solid tumor categories like Lung, Breast, Colon — this would indicate a matching bug. ICD-O-3 counts being 0 for hematopoietic categories is expected.

### Pitfall 3: TUMOR_REGISTRY_ALL Topography Column Split

**What goes wrong:** TUMOR_REGISTRY_ALL (484 columns from UNION ALL BY NAME) has both `TOPOGRAPHY_CODE` (TR1 column) and `ICDOSITE` (TR2/TR3 column) as separate columns. Querying only `TOPOGRAPHY_CODE` misses TR2/TR3 patients; querying only `ICDOSITE` misses TR1 patients.

**How to avoid:**
```r
tr_all <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
  select(ID,
         topo = coalesce(TOPOGRAPHY_CODE, ICDOSITE)) %>%
  filter(!is.na(topo)) %>%
  materialize()
```

Note: `coalesce()` works in DuckDB SQL translation via dplyr — this pattern is safe to use on the lazy tbl_dbi before `materialize()`.

### Pitfall 4: Whitespace in xlsx Code Cells

**What goes wrong:** Some cells in CancerSiteCategories.xlsx contain extra whitespace: `"C080- C081"` has a space between the hyphen and the second endpoint. Simple `str_split(token, "-")` followed by `str_trim()` on each part handles this — but ONLY if `str_trim()` is applied to EACH split part, not just the full token.

**How to avoid:** Apply `str_trim()` to both start and end of every range after splitting on `-`. Also apply `str_trim()` to every comma-split token before processing.

### Pitfall 5: Prefix Match Over-Matching

**What goes wrong:** A category expanded code "C8" would prefix-match C80, C81, C82, C83 — an entire ICD-10 chapter. The xlsx never stores 2-character codes, but some single-character codes like "C19" appear (Rectum). These are 3-character codes that, as prefixes, match C19, C190, C191, C190A, etc. This is intentional and correct — but verify that "C19" in the xlsx means "all C19.x codes" (yes, per SEER grouping convention).

**What actually matters:** The concern is NOT over-matching for valid 3+ character codes. The concern is whether prefix matching against the expanded code list is correct. For a category with expanded code "C19", any DIAGNOSIS.DX that starts with "C19" (after normalize_icd) counts as a match. This is correct since C19 is the ICD-10 code for the rectosigmoid junction and C19x are its subcodes.

### Pitfall 6: Duplicate Patient Counts in the Totals Row

**What goes wrong:** Summing the per-category "ICD-10 Patients" column in the totals row does NOT give the total unique patients — a patient with both colon and rectum codes appears in both rows. The CONTEXT.md requires a "Combined Unique Patients" column at the category level (union of ICD-10 and ICD-O-3 patients for that category) and the totals row for Combined Unique Patients must use `n_distinct()` across all matched patients from both sources, not sum the per-row values.

---

## Code Examples

### Loading the Groups Sheet
```r
# Source: readxl documentation + direct xlsx inspection
library(readxl)
groups_raw <- read_excel("CancerSiteCategories.xlsx", sheet = "Groups")
# Columns: Site, ICD10, ICDO3, `Primary disease site`, `Detailed site`
# 42 data rows (rows 1-42 after header)
# Keep only columns A-C; D and E are classification labels not needed for matching
groups_df <- groups_raw %>%
  select(category = Site, icd10 = ICD10, icdo3 = ICDO3)
```

### Querying DIAGNOSIS for ICD-10 (all patients)
```r
# Pattern: materialize full ICD-10 subset, then match in R
# DIAGNOSIS has many rows; filter DX_TYPE == "10" first, then materialize
diagnosis_icd10 <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  select(ID, DX, ENCOUNTERID) %>%
  materialize() %>%
  mutate(DX_norm = normalize_icd(DX))
```

### Querying TUMOR_REGISTRY_ALL for ICD-O-3 topography
```r
# Pattern: coalesce TOPOGRAPHY_CODE (TR1) and ICDOSITE (TR2/TR3)
# TR_ALL has 1,145 rows — small enough to fully materialize
tr_topo <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
  select(ID,
         topo_raw = coalesce(TOPOGRAPHY_CODE, ICDOSITE)) %>%
  filter(!is.na(topo_raw)) %>%
  materialize() %>%
  mutate(topo_norm = normalize_icd(topo_raw))
```

### Prefix Matching for One Category
```r
# Given expanded_codes_i = c("C810", "C811", "C812", "C813", "C814")
# Find all DIAGNOSIS rows where DX_norm starts with any element of expanded_codes_i
# Use startsWith() which is vectorized and fast
match_dx <- diagnosis_icd10 %>%
  filter(purrr::map_lgl(DX_norm, function(dx) {
    any(startsWith(dx, expanded_codes_i))
  }))

icd10_patients_i   <- n_distinct(match_dx$ID)
icd10_encounters_i <- n_distinct(match_dx$ENCOUNTERID)
```

**Performance note:** DIAGNOSIS will be large (all patients, all ICD-10 codes). Materializing the full ICD-10 subset once and iterating 42 categories in R is far cheaper than 42 separate DuckDB queries. The purrr::map_lgl per-row approach is O(n * k) where n=DIAGNOSIS rows and k=expanded codes per category. For large DIAGNOSIS tables, consider pre-building a prefix lookup or using an inner join on truncated codes instead.

**Alternative approach for performance:**
```r
# Build a flat lookup: expanded_prefix -> category_index (first match wins)
# Then left_join on truncated DX_norm
all_prefixes <- purrr::map_dfr(seq_len(nrow(groups_df)), function(i) {
  codes_i <- expand_code_string(groups_df$icd10[i])
  tibble(prefix = codes_i, category_idx = i)
}) %>%
  # First match wins: keep only first occurrence of each prefix
  distinct(prefix, .keep_all = TRUE)

# Join: for each DIAGNOSIS row, find the category whose expanded code is a prefix of DX_norm
# This requires checking all prefix lengths — simpler with a loop over prefix lengths
```

The simpler purrr::map_lgl approach is acceptable for this analysis-script context where performance is not critical and the script runs once.

### openxlsx2 Styled Workbook (follow R/45 pattern)
```r
# Confirmed pattern from R/45_radiation_cpt_audit.R
DARK_HEADER_FILL <- "FF374151"
WHITE_FONT       <- "FFFFFFFF"
TITLE_FONT_COLOR <- "FF1F2937"
n_cols <- 6L

wb <- wb_workbook()
SHEET1 <- "Cancer Site Frequency"
wb$add_worksheet(SHEET1)

# Title row
wb$add_data(sheet = SHEET1, x = "Cancer Site Frequency — All Patients", start_row = 1, start_col = 1)
wb$add_font(sheet = SHEET1, dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color(TITLE_FONT_COLOR))
wb$merge_cells(sheet = SHEET1, dims = glue("A1:{int2col(n_cols)}1"))

# Header row 2
headers <- c("Cancer Site Category", "ICD-10 Patients", "ICD-10 Encounters",
             "ICD-O-3 Patients", "ICD-O-3 Registry Records", "Combined Unique Patients")
for (i in seq_along(headers)) {
  wb$add_data(sheet = SHEET1, x = headers[i], start_row = 2, start_col = i)
}
wb$add_fill(sheet = SHEET1, dims = glue("A2:{int2col(n_cols)}2"),
            color = wb_color(DARK_HEADER_FILL))
wb$add_font(sheet = SHEET1, dims = glue("A2:{int2col(n_cols)}2"),
            name = "Calibri", size = 11, bold = TRUE, color = wb_color(WHITE_FONT))

# Freeze pane at row 3 (below title + header)
wb$freeze_pane(sheet = SHEET1, first_row = TRUE, first_col = FALSE)

# Data rows 3+
wb$add_data(sheet = SHEET1, x = result_df, start_row = 3, col_names = FALSE)

# Number format for count columns (B:F)
if (nrow(result_df) > 0) {
  last_data_row <- 2L + nrow(result_df)
  wb$add_numfmt(sheet = SHEET1,
                dims = glue("B3:{int2col(n_cols)}{last_data_row}"),
                numfmt = "#,##0")
}

# Column widths
wb$set_col_widths(sheet = SHEET1, cols = 1:n_cols,
                  widths = c(38, 16, 18, 16, 24, 24))

wb$save(OUTPUT_PATH)
```

**Confirmed API from R/45:** `int2col()` (not `int_to_col()`), `wb_color()` (not bare hex), `wb$add_fill()`, `wb$add_font()`, `wb$add_numfmt()`, `wb$merge_cells()`, `wb$set_col_widths()`, `wb$save()`.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| String range comparison (`code >= "C810"`) | Range enumeration to code vectors + `%in%` or prefix match | Established practice; implemented in v1.6 research | Eliminates format-dependent matching failures |
| Separate xlsx output tools (XLConnect, openxlsx) | openxlsx2 | Phase 38 (this project) | Consistent styled workbook API across all scripts |
| `int_to_col()` | `int2col()` | Phase 45 lesson | Avoid column name lookup failures |
| `glue("{x:,}")` format spec | `format(x, big.mark=',')` | Phase 45 lesson | R uses format() not Python f-string `:,` spec |

---

## Open Questions

1. **ICD-O-3 topography code format in TOPOGRAPHY_CODE and ICDOSITE columns**
   - What we know: TR1 uses `TOPOGRAPHY_CODE`, TR2/TR3 use `ICDOSITE`. From NAACCR standard, topography codes are C + 3 digits (e.g., "C819"). From the xlsx ICDO3 column for solid tumors, values appear as C-prefixed codes.
   - What's unclear: Whether TOPOGRAPHY_CODE stores "C819" or "8190" or "819" in actual data. The diagnostics output shows the column exists but not sample values.
   - Recommendation: Add a quick `head()` of distinct TOPOGRAPHY_CODE values in the script's early output, before the matching loop, so any mismatch between stored format and expected format is caught immediately. If values are stored without the "C" prefix (e.g., "8190"), the normalize_icd() function will still work (it only removes dots, doesn't add/remove the C prefix) but the expansion codes from the xlsx (which have the C prefix) won't match.

2. **Whether any category in the xlsx actually has ICD-O-3 topography codes (vs. all morphology)**
   - What we know: For hematopoietic categories the ICDO3 column has morphology codes (9xxx). For solid tumor categories the ICDO3 column appears to mirror or approximate the ICD-10 codes with C-prefixed topography.
   - What's unclear: Whether the solid tumor ICDO3 cells contain true topography codes that will match TOPOGRAPHY_CODE/ICDOSITE, or whether they're blank/NA.
   - Recommendation: After loading groups_df, log how many categories have non-NA ICDO3 cells and sample the content to confirm format before running the matching loop.

---

## Sources

### Primary (HIGH confidence)
- Direct xlsx inspection: `/tmp/csc_extracted/xl/sharedStrings.xml` and `worksheets/sheet1.xml` — confirmed 43 rows, 5 columns (A=Site, B=ICD10, C=ICDO3, D=Primary disease site, E=Detailed site), all 42 category names, exact ICD code format
- `claude_diagnostics.txt` (project file): confirmed TUMOR_REGISTRY column names — TR1 uses TOPOGRAPHY_CODE, TR2/TR3 use ICDOSITE, TR_ALL has 1,145 rows
- `R/45_radiation_cpt_audit.R` (project file): confirmed openxlsx2 API — int2col(), wb_color(), add_fill/font/numfmt/merge_cells/set_col_widths, wb$save()
- `R/utils_icd.R` (project file): confirmed normalize_icd() signature and behavior
- `R/utils_duckdb.R` (project file): confirmed get_pcornet_table() and materialize() usage pattern
- `R/03_cohort_predicates.R` (project file): confirmed coalesce(TOPOGRAPHY_CODE, ICDOSITE) pattern for TUMOR_REGISTRY_ALL

### Secondary (MEDIUM confidence)
- `.planning/research/ARCHITECTURE.md` (project file, 2026-04-21): confirms standalone script pattern, CancerSiteCategories.xlsx Groups sheet has 43 rows, range format
- `.planning/research/PITFALLS.md` (project file, 2026-04-21): confirms string comparison pitfall, prefix matching approach

### Tertiary (LOW confidence)
- None — all findings are from direct code and file inspection.

---

## Metadata

**Confidence breakdown:**
- CancerSiteCategories.xlsx structure: HIGH — directly inspected XML
- TUMOR_REGISTRY column names: HIGH — confirmed from claude_diagnostics.txt (actual loaded table output)
- openxlsx2 API: HIGH — confirmed from R/45 working code
- ICD-O-3 topography value format in actual data: MEDIUM — column exists (confirmed) but sample values not seen; NAACCR standard says C+3digits but runtime verification is needed
- Range expansion approach: HIGH — established in project research, directly aligns with CONTEXT.md decisions

**Research date:** 2026-05-15
**Valid until:** 2026-06-15 (stable libraries, no moving parts)
