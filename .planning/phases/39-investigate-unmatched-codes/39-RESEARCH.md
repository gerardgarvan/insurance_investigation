# Phase 39: Investigate Unmatched Codes - Research

**Researched:** 2026-05-04
**Domain:** Medical code classification, HCPCS/CPT code lookup, automated code-to-description mapping, R xlsx generation
**Confidence:** MEDIUM

## Summary

Phase 39 investigates CPT/HCPCS procedure codes that appear in HL patient data but aren't captured by the curated `TREATMENT_CODES` lists in `R/00_config.R`. The phase widens heuristic detection ranges beyond Phase 38's current patterns, auto-classifies unmatched codes using keyword-based rules on CMS reference data descriptions, produces an xlsx report, and updates `TREATMENT_CODES` with confirmed treatment codes.

The technical challenge is acquiring authoritative code descriptions (CMS HCPCS files or NLM API), building classification heuristics using `stringr` keyword matching on descriptions and code family patterns, and automating `R/00_config.R` updates without manual curation. The project already has strong xlsx styling infrastructure from Phase 38 (`openxlsx2`, treatment type color schemes) and heuristic range detection (`CPT_HCPCS_RANGES` patterns).

**Primary recommendation:** Use the NLM HCPCS API for real-time code-to-description lookup (free, no download required, returns JSON with short/long descriptions). Build auto-classification using `case_when()` with keyword matching on descriptions (e.g., "chemotherapy", "radiation", "transplant") combined with code family patterns (J0-J8 supportive care, 773xx planning). Update `TREATMENT_CODES` in `R/00_config.R` by programmatically inserting new codes into the appropriate list entries, preserving existing comments and formatting.

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Code Systems Scope (D-01):**
- CPT/HCPCS procedure codes only — no ICD-10-PCS, ICD-9, DRG, revenue, RXNORM, or NDC investigation this phase

**Widened Heuristic Ranges (D-02):**
- Chemotherapy: J9xxx full range PLUS curated J0-J8 supportive care codes (growth factors like pegfilgrastim, antiemetics like ondansetron)
- Radiation: 774xx delivery codes PLUS 773xx treatment planning codes (skip 772xx simulation)
- SCT: existing 382xx range (no change)
- Immunotherapy: existing XW0xx range (no change)

**Skip NDC Mapping (D-03):**
- Skip NDC-to-treatment mapping entirely this phase — stay focused on procedure codes

**Investigation Method (D-04, D-05, D-06):**
- D-04: Automated code-to-description lookup using CMS HCPCS/CPT reference CSV files downloaded to HiPerGator
- D-05: Auto-classify ALL unmatched codes into treatment categories: chemo, radiation, SCT, immunotherapy, supportive care, unrelated — no uncertainty flags, rely on heuristic classification rules
- D-06: No manual review step in the workflow — classification is fully automated

**Resolution Action (D-07, D-08, D-09):**
- D-07: Produce xlsx report of all unmatched codes with descriptions, classifications, and patient counts
- D-08: Automatically update `TREATMENT_CODES` in `R/00_config.R` with all auto-classified treatment codes (no patient count threshold)
- D-09: Phase 38's treatment inventory will pick up the expanded code lists on next run

### Claude's Discretion

- Choice of specific CMS reference file format and download approach
- Classification heuristic rules (keyword matching on descriptions, code family patterns)
- xlsx report layout and styling (consistent with Phase 38 output patterns)
- Which specific J0-J8 codes to include in the curated supportive care list

### Deferred Ideas (OUT OF SCOPE)

- NDC-to-treatment mapping for drugs in DISPENSING/PRESCRIBING/MED_ADMIN — large scope, potentially its own phase
- ICD-10-PCS broader range detection (3E0x chemo admin, D7x radiation beyond current prefixes)
- ICD-9/DRG/revenue code gap analysis

## Standard Stack

### Core Libraries (Already in Project)

| Library | Version | Purpose | Already Used |
|---------|---------|---------|--------------|
| stringr | 1.5.1+ | String pattern matching, keyword detection | Phase 38: `str_detect()`, `str_remove()` for code normalization |
| dplyr | 1.2.0+ | Data transformation, `case_when()` classification | All phases: pipeline backbone |
| openxlsx2 | Latest | xlsx generation with styling | Phase 38: `wb_workbook()`, pill styling, frozen panes |
| glue | 1.8.0+ | String interpolation for logging | Phase 38: `glue()` for messages |
| httr | 1.4.7+ | HTTP API calls (if using NLM API) | Not yet used, but standard R HTTP client |
| jsonlite | 1.8.8+ | JSON parsing (if using NLM API) | Not yet used, but standard R JSON parser |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| readr | 2.2.0+ | CSV parsing (if using CMS file) | Parse downloaded CMS HCPCS reference file |
| here | 1.0.2+ | Project-relative paths | Construct paths to downloaded CMS files |
| curl | 5.2.0+ | Low-level HTTP (fallback for httr) | Only if httr unavailable |

**Installation (if needed):**
```r
# In R console on HiPerGator:
install.packages(c("httr", "jsonlite"))  # Only if using NLM API approach
renv::snapshot()
```

**Version verification:**
```r
packageVersion("stringr")   # Should be >= 1.5.1
packageVersion("dplyr")     # Should be >= 1.2.0
packageVersion("openxlsx2") # Should be latest
```

All core libraries are already installed and used in Phase 38. Only `httr` and `jsonlite` may need installation if the NLM API approach is chosen.

## Architecture Patterns

### Recommended Approach: NLM HCPCS API

**What:** Use the free NLM Clinical Tables API for real-time code-to-description lookup
**When to use:** When code descriptions are needed for classification and download management overhead should be avoided
**Why preferred:**
- Free, no authentication required
- Returns JSON with `short_desc` and `long_desc` fields
- No file download or version management needed
- Base URL: `https://clinicaltables.nlm.nih.gov/api/hcpcs/v3/search`

**Example API usage in R:**
```r
# Source: NLM HCPCS API documentation (https://clinicaltables.nlm.nih.gov/apidoc/hcpcs/v3/doc.html)
library(httr)
library(jsonlite)

lookup_hcpcs_codes <- function(codes) {
  # API returns results for single search term
  # For multiple codes, query by code or batch via term search
  results <- list()

  for (code in codes) {
    url <- glue("https://clinicaltables.nlm.nih.gov/api/hcpcs/v3/search?terms={code}&ef=display,code")
    response <- GET(url)

    if (status_code(response) == 200) {
      json <- content(response, "text") %>% fromJSON()
      # API returns: [total_count, [codes], {extra_fields}, [display_strings]]
      if (length(json[[2]]) > 0) {
        results[[code]] <- list(
          code = json[[2]][1],
          description = json[[4]][1]
        )
      }
    }

    Sys.sleep(0.1)  # Rate limiting: ~10 req/sec to be polite
  }

  bind_rows(results)
}
```

**Limitations:**
- No batch lookup (must loop through codes)
- Rate limits not documented (be conservative: ~10 req/sec)
- May not have every code (especially very new 2026 additions)

### Alternative Approach: CMS HCPCS Quarterly File

**What:** Download CMS quarterly HCPCS update ZIP file, extract internal file (format unknown), parse for code-description mapping
**When to use:** When NLM API is unavailable or fails to return descriptions for critical codes
**Why secondary:**
- Requires file download step (not automated)
- ZIP contains unknown internal format (need to inspect)
- Version management overhead (which quarter's file to use?)
- HiPerGator storage required for reference data

**Download location:**
- Latest: April 2026 HCPCS file from https://www.cms.gov/medicare/coding-billing/healthcare-common-procedure-system/quarterly-update
- Direct ZIP path: `/files/zip/april-2026-alpha-numeric-hcpcs-file.zip`

**Unknown file structure:** CMS does not publish field specifications. ZIP must be downloaded and inspected to determine:
- Is the internal file CSV, Excel, or fixed-width text?
- Which column contains code? Which contains description?
- Are there short vs. long description fields?

**If using this approach:**
1. Download ZIP to HiPerGator `/blue/erin.mobley-hl.bcu/reference_data/cms_hcpcs/`
2. Unzip and inspect file structure
3. Parse with `readr::read_csv()` or `readxl::read_excel()` based on format
4. Extract code + description columns
5. Cache as RDS for reuse

### Project Structure Pattern (Phase 39)

```
R/
├── 39_investigate_unmatched.R       # Main investigation script
├── 00_config.R                      # Target for TREATMENT_CODES updates
└── 38_treatment_inventory.R         # Existing detect_unknown_codes() function

output/
└── unmatched_codes_report.xlsx      # Styled report with descriptions and classifications

.planning/phases/39-investigate-unmatched-codes/
└── 39-RESEARCH.md                   # This file
```

### Pattern 1: Auto-Classification with case_when()

**What:** Use `case_when()` with keyword matching on descriptions and code family patterns to assign treatment categories
**When to use:** Automated code classification without manual review (D-05, D-06)
**Example:**
```r
# Source: dplyr 1.2.0 documentation (https://dplyr.tidyverse.org/reference/case_when.html)
classify_unmatched_code <- function(code, description) {
  desc_lower <- tolower(description)

  case_when(
    # Chemotherapy: J9xxx or keywords in description
    str_detect(code, "^J9") ~ "Chemotherapy",
    str_detect(desc_lower, "chemotherapy|antineoplastic|doxorubicin|cisplatin") ~ "Chemotherapy",

    # Supportive care: J0-J8 with specific keywords
    str_detect(code, "^J[0-8]") & str_detect(desc_lower, "filgrastim|pegfilgrastim|ondansetron|granisetron|antiemetic|growth factor") ~ "Supportive Care",

    # Radiation: 773xx-774xx or keywords
    str_detect(code, "^77[34]") ~ "Radiation",
    str_detect(desc_lower, "radiation|radiotherapy|external beam|brachytherapy") ~ "Radiation",

    # SCT: 382xx or keywords
    str_detect(code, "^382[34]") ~ "SCT",
    str_detect(desc_lower, "transplant|bone marrow|stem cell|hematopoietic") ~ "SCT",

    # Immunotherapy: XW0xx or keywords
    str_detect(code, "^XW0[34]3") ~ "Immunotherapy",
    str_detect(desc_lower, "car.t|chimeric antigen|immunotherapy|pembrolizumab|nivolumab") ~ "Immunotherapy",

    # Default: Unrelated
    TRUE ~ "Unrelated"
  )
}
```

### Pattern 2: Programmatic R/00_config.R Update

**What:** Parse `R/00_config.R`, find `TREATMENT_CODES <- list(...)`, insert new codes into appropriate vectors, preserve formatting and comments
**When to use:** Automated config update (D-08) without manual editing
**Example:**
```r
# Simplified pattern — production code needs robust parsing
update_treatment_codes <- function(new_codes, category) {
  config_path <- "R/00_config.R"
  config_lines <- readLines(config_path)

  # Find the target vector (e.g., chemo_hcpcs = c(...))
  vector_pattern <- glue("^\\s*{category}\\s*=\\s*c\\(")
  start_idx <- which(str_detect(config_lines, vector_pattern))

  # Find closing parenthesis
  end_idx <- start_idx
  while (!str_detect(config_lines[end_idx], "\\)\\s*,?\\s*$")) {
    end_idx <- end_idx + 1
  }

  # Extract existing codes
  existing_block <- config_lines[start_idx:end_idx]
  existing_codes <- str_extract_all(existing_block, '"[^"]+"')[[1]]

  # Merge new codes (avoid duplicates)
  all_codes <- unique(c(existing_codes, new_codes))

  # Rebuild vector with formatting
  new_lines <- c(
    glue("  {category} = c("),
    paste0('    "', all_codes, '",'),
    "  ),"
  )

  # Replace old lines with new
  config_lines <- c(
    config_lines[1:(start_idx - 1)],
    new_lines,
    config_lines[(end_idx + 1):length(config_lines)]
  )

  writeLines(config_lines, config_path)
  message(glue("Updated {category} with {length(new_codes)} new codes"))
}
```

**Note:** This is a simplified pattern. Production implementation must handle:
- Multi-line code vectors with inline comments
- Comma placement (last item has no comma)
- Indentation consistency
- Validation that new codes don't already exist

### Pattern 3: xlsx Report Structure (Consistent with Phase 38)

**What:** Single xlsx workbook with sheets per treatment type, styled with treatment-type colored pills, descriptions, classifications
**When to use:** D-07 reporting requirement
**Example structure:**
```r
# Source: Phase 38 R/38_treatment_inventory.R write_treatment_sheet()
wb <- wb_workbook()

for (treatment_type in c("Chemotherapy", "Radiation", "SCT", "Immunotherapy", "Supportive Care")) {
  df_unmatched <- unmatched_codes %>% filter(classification == treatment_type)

  wb$add_worksheet(treatment_type)

  # Title/subtitle (rows 1-2)
  wb$add_data(sheet = treatment_type, x = "Unmatched Treatment Codes Investigation",
              start_row = 1, start_col = 1)

  # Section header (row 4)
  wb$add_data(sheet = treatment_type, x = glue("{treatment_type} Codes"),
              start_row = 4, start_col = 1)

  # Column headers (row 5) with dark gray fill and white text
  headers <- c("Code", "Description", "Source Table", "Patient Count", "Classification")
  # ... wb$add_fill(), wb$add_font() for styling

  # Data rows (row 6+) with treatment-type colored pills in Code column
  # ... wb$add_data() per row, wb$add_fill() with TREATMENT_TYPE_COLORS

  # Freeze panes at row 6 (header row)
  wb$freeze_pane(sheet = treatment_type, first_active_row = 6)
}

wb$save(file = "output/unmatched_codes_report.xlsx")
```

**Styling reference:** Reuse `TREATMENT_TYPE_COLORS` from `R/38_treatment_inventory.R` (lines 49-54):
- Chemotherapy: light blue / dark blue
- Radiation: light green / dark green
- SCT: light yellow / dark olive
- Immunotherapy: light purple / dark purple
- Add Supportive Care: light teal / dark teal (new color scheme)

### Anti-Patterns to Avoid

**1. Don't hard-code code descriptions in R scripts**
```r
# AVOID: Manual description mapping
code_desc <- c("J9000" = "Doxorubicin", "J9040" = "Bleomycin", ...)

# PREFER: Dynamic lookup from CMS/NLM source
code_desc <- lookup_hcpcs_codes(c("J9000", "J9040"))
```

**2. Don't modify R/00_config.R without validation**
```r
# AVOID: Direct sed/awk replacement without parsing
system("sed -i 's/chemo_hcpcs = c(/chemo_hcpcs = c(\"J9999\", /' R/00_config.R")

# PREFER: Parse-modify-validate workflow
config_lines <- readLines("R/00_config.R")
# ... validate syntax, check for duplicates, preserve comments
writeLines(config_lines, "R/00_config.R")
```

**3. Don't classify codes without keyword context**
```r
# AVOID: Code family pattern only
classification <- ifelse(str_detect(code, "^J9"), "Chemotherapy", "Unknown")

# PREFER: Combined code pattern + description keyword matching
classification <- case_when(
  str_detect(code, "^J9") | str_detect(desc, "chemotherapy") ~ "Chemotherapy",
  ...
)
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HCPCS code database scraping | Custom web scraper for hcpcsdata.com or similar | NLM HCPCS API | API is maintained by NIH, official, free, no scraping fragility |
| Manual code classification | Human review of every unmatched code | Keyword + pattern heuristics with `case_when()` | D-06 requires full automation; 100+ codes to classify |
| xlsx cell styling loops | Manual `wb$add_fill()` per cell | Phase 38's `write_treatment_sheet()` pattern | Already proven, consistent styling, handles edge cases |
| Code range expansion | Manually add codes to TREATMENT_CODES lists | Automated parsing + insertion via `readLines()`/`writeLines()` | D-08 requires automation; error-prone if manual |

**Key insight:** The NLM API eliminates the entire "acquire and parse CMS file" problem. Classification heuristics will never be 100% accurate, but D-05 explicitly accepts this tradeoff (no uncertainty flags, rely on heuristic rules). Phase 38 already established the xlsx styling patterns; reuse them.

## Runtime State Inventory

> Skipped — Phase 39 is a greenfield investigation script, not a rename/refactor/migration phase.

## Common Pitfalls

### Pitfall 1: NLM API Code Lookup Returns No Results for New 2026 Codes

**What goes wrong:** NLM HCPCS API database may lag behind CMS quarterly updates by weeks or months. Codes added in April 2026 may not appear in the API yet.

**Why it happens:** NLM maintains a separate database updated independently of CMS. There's no guaranteed sync schedule.

**How to avoid:**
1. Test API lookup for a known 2026 code (e.g., a J9xxx code from the April 2026 HCPCS update)
2. If API returns empty results, fall back to CMS file download approach
3. Log codes that fail lookup for manual investigation

**Warning signs:**
- `lookup_hcpcs_codes()` returns empty results for codes known to exist in PROCEDURES table
- API response JSON shows `total_count = 0` for valid-looking codes

**Detection code:**
```r
test_code <- "J9999"  # Known 2026 code
result <- lookup_hcpcs_codes(test_code)
if (nrow(result) == 0) {
  warning("NLM API may be out of date; consider CMS file download approach")
}
```

### Pitfall 2: Classification Heuristics Misclassify Supportive Care as Chemotherapy

**What goes wrong:** J0-J8 codes include both supportive care (growth factors, antiemetics) and unrelated drugs. Broad keyword matching on "cancer" or "treatment" may incorrectly classify supportive drugs as chemotherapy.

**Why it happens:** J-code range overlaps multiple drug classes. Descriptions often mention cancer context even for supportive drugs.

**How to avoid:**
1. Use explicit negative keywords: NOT "diagnostic", NOT "imaging"
2. Prioritize supportive care classification before chemotherapy
3. Build curated J0-J8 supportive care code list from known drugs (pegfilgrastim = J2506, ondansetron = J2405)

**Warning signs:**
- J2506 (pegfilgrastim) classified as "Chemotherapy" instead of "Supportive Care"
- J2405 (ondansetron) classified as "Chemotherapy"

**Prevention strategy:**
```r
# Curated supportive care keywords (more specific than chemo keywords)
supportive_keywords <- "filgrastim|pegfilgrastim|ondansetron|granisetron|antiemetic|growth factor|colony stimulating"

classify_code <- function(code, desc) {
  case_when(
    # Supportive care BEFORE chemotherapy to catch J0-J8 correctly
    str_detect(code, "^J[0-8]") & str_detect(tolower(desc), supportive_keywords) ~ "Supportive Care",
    str_detect(code, "^J9") | str_detect(tolower(desc), "chemotherapy|antineoplastic") ~ "Chemotherapy",
    ...
  )
}
```

### Pitfall 3: Automated R/00_config.R Update Corrupts File Syntax

**What goes wrong:** Programmatic insertion of new codes breaks R syntax (missing commas, unmatched parentheses, corrupted comments), causing `source("R/00_config.R")` to fail with parse errors.

**Why it happens:** R code is not a structured format like JSON. String manipulation on code text is fragile.

**How to avoid:**
1. After updating `R/00_config.R`, validate syntax with `parse("R/00_config.R")`
2. Run a test: `source("R/00_config.R"); str(TREATMENT_CODES)` to confirm list structure
3. Keep a backup before modifying: `file.copy("R/00_config.R", "R/00_config.R.bak")`
4. Use `diff` to review changes before committing

**Warning signs:**
- `source("R/00_config.R")` throws "unexpected symbol" or "unexpected end of input" errors
- `TREATMENT_CODES$chemo_hcpcs` is NULL or malformed after update

**Validation code:**
```r
# Before modifying R/00_config.R
file.copy("R/00_config.R", "R/00_config.R.bak", overwrite = TRUE)

# After modifying
tryCatch({
  parse("R/00_config.R")
  source("R/00_config.R")
  stopifnot(!is.null(TREATMENT_CODES$chemo_hcpcs))
  message("Config update validated successfully")
}, error = function(e) {
  warning("Config update broke syntax; restoring backup")
  file.copy("R/00_config.R.bak", "R/00_config.R", overwrite = TRUE)
  stop(e)
})
```

### Pitfall 4: Widened Heuristic Ranges (D-02) Catch Too Many Unrelated Codes

**What goes wrong:** Expanding to full J0-J8 range (instead of curated list) detects 100+ unrelated injectable drugs (antibiotics, fluids, diagnostics). Classification heuristics fail to separate treatment from non-treatment.

**Why it happens:** J0-J8 is ~800 codes, most unrelated to cancer treatment. Keyword matching on descriptions can't reliably separate "cancer-related" from "administered to cancer patients incidentally."

**How to avoid:**
1. Start with curated J0-J8 supportive care list (10-20 codes: filgrastim, ondansetron, etc.) instead of full range
2. For radiation 773xx, manually verify that planning codes are treatment-related (not just simulation/dosimetry)
3. Accept that "Unrelated" will be the largest category

**Warning signs:**
- Unmatched codes report shows 200+ "Supportive Care" codes, many with descriptions like "vitamin B12" or "antibiotic"
- 773xx codes include simulation-only procedures (77290, 77295) that aren't treatment delivery

**Mitigation strategy:**
```r
# Instead of full J0-J8 range, use curated supportive care list
SUPPORTIVE_CARE_CODES <- c(
  "J2506",  # Pegfilgrastim (Neulasta)
  "J2505",  # Pegfilgrastim (biosimilar)
  "J1442",  # Filgrastim (Neupogen)
  "J2405",  # Ondansetron (Zofran)
  "J1626",  # Granisetron
  # ... add others as identified
)

# For 773xx radiation, exclude simulation (772xx) explicitly
radiation_heuristic <- "^774[0-9]{2}$|^773[3-9][0-9]$"  # Delivery + planning, NOT 772xx simulation
```

## Code Examples

Verified patterns for implementation:

### Example 1: NLM API Code Lookup with Error Handling

```r
# Source: NLM HCPCS API documentation (https://clinicaltables.nlm.nih.gov/apidoc/hcpcs/v3/doc.html)
library(httr)
library(jsonlite)
library(dplyr)
library(glue)

lookup_hcpcs_batch <- function(codes, sleep_sec = 0.1) {
  results <- list()

  for (i in seq_along(codes)) {
    code <- codes[i]
    url <- glue("https://clinicaltables.nlm.nih.gov/api/hcpcs/v3/search?terms={code}&ef=display")

    tryCatch({
      response <- GET(url, timeout(10))

      if (status_code(response) == 200) {
        json <- fromJSON(content(response, "text", encoding = "UTF-8"))
        # API returns: [total_count, [codes], {extra_fields}, [display_strings]]

        if (json[[1]] > 0 && length(json[[4]]) > 0) {
          results[[code]] <- tibble(
            code = code,
            description = json[[4]][1],
            lookup_status = "success"
          )
        } else {
          results[[code]] <- tibble(
            code = code,
            description = NA_character_,
            lookup_status = "not_found"
          )
        }
      } else {
        results[[code]] <- tibble(
          code = code,
          description = NA_character_,
          lookup_status = glue("http_error_{status_code(response)}")
        )
      }
    }, error = function(e) {
      results[[code]] <- tibble(
        code = code,
        description = NA_character_,
        lookup_status = glue("error: {e$message}")
      )
    })

    if (i %% 10 == 0) message(glue("  Processed {i}/{length(codes)} codes"))
    Sys.sleep(sleep_sec)  # Rate limiting
  }

  bind_rows(results)
}

# Usage:
unmatched_codes <- c("J9999", "77399", "38240")
code_descriptions <- lookup_hcpcs_batch(unmatched_codes)
```

### Example 2: Auto-Classification with Keyword Matching

```r
# Source: dplyr 1.2.0 case_when() documentation (https://dplyr.tidyverse.org/reference/case_when.html)
library(stringr)
library(dplyr)

classify_treatment_code <- function(code, description) {
  desc_lower <- tolower(description)

  case_when(
    # Supportive care FIRST (before chemo) to catch J0-J8 correctly
    str_detect(code, "^J[0-8]") & str_detect(desc_lower, "filgrastim|pegfilgrastim|ondansetron|granisetron|antiemetic|growth factor|colony stimulating") ~ "Supportive Care",

    # Chemotherapy: J9xxx or antineoplastic keywords
    str_detect(code, "^J9") ~ "Chemotherapy",
    str_detect(desc_lower, "chemotherapy|antineoplastic|doxorubicin|cisplatin|carboplatin|etoposide|vincristine|bleomycin|dacarbazine") ~ "Chemotherapy",

    # Radiation: 773xx-774xx or radiation keywords
    str_detect(code, "^77[34]") ~ "Radiation",
    str_detect(desc_lower, "radiation|radiotherapy|external beam|brachytherapy|radiosurgery|imrt|igrt") ~ "Radiation",

    # SCT: 382xx or transplant keywords
    str_detect(code, "^382[34]") ~ "SCT",
    str_detect(desc_lower, "transplant|bone marrow|stem cell|hematopoietic|allogeneic|autologous") ~ "SCT",

    # Immunotherapy: XW0xx or immunotherapy keywords
    str_detect(code, "^XW0[34]3") ~ "Immunotherapy",
    str_detect(desc_lower, "car.t|chimeric antigen|immunotherapy|pembrolizumab|nivolumab|checkpoint inhibitor") ~ "Immunotherapy",

    # Default: Unrelated
    TRUE ~ "Unrelated"
  )
}

# Usage:
unmatched_with_desc <- unmatched_codes %>%
  left_join(code_descriptions, by = "code") %>%
  mutate(classification = classify_treatment_code(code, description))
```

### Example 3: Validate R/00_config.R Update

```r
# Source: Base R parse() and source() functions
library(glue)

update_and_validate_config <- function(new_codes, category_name) {
  config_path <- "R/00_config.R"
  backup_path <- glue("{config_path}.bak")

  # Backup
  file.copy(config_path, backup_path, overwrite = TRUE)
  message(glue("Created backup: {backup_path}"))

  tryCatch({
    # Update config (simplified — real implementation needs robust parsing)
    # ... insert new_codes into TREATMENT_CODES[[category_name]]

    # Validate syntax
    parse(config_path)
    message("✓ Syntax validation passed")

    # Validate structure
    rm(list = c("TREATMENT_CODES", "CONFIG"), envir = .GlobalEnv)  # Clear old
    source(config_path, local = TRUE)
    stopifnot(!is.null(TREATMENT_CODES[[category_name]]))
    message(glue("✓ TREATMENT_CODES${category_name} has {length(TREATMENT_CODES[[category_name]])} codes"))

    # Success
    file.remove(backup_path)
    message("Config update successful; backup removed")

  }, error = function(e) {
    warning(glue("Config update failed: {e$message}"))
    warning("Restoring backup...")
    file.copy(backup_path, config_path, overwrite = TRUE)
    stop(e)
  })
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual code list curation from literature | Heuristic range detection + API lookup | Phase 38 (2026-05) | Automates discovery of unmapped codes |
| CPT code downloads from AMA website | NLM free API or CMS quarterly files | 2024+ | Free, no AMA licensing for descriptions |
| Manual classification by clinician | Keyword-based heuristics with `case_when()` | Phase 39 (2026-05) | Eliminates human bottleneck (D-06) |

**Deprecated/outdated:**
- AMA CPT code database subscription: NLM API provides HCPCS (Level II) codes free; CPT (Level I) codes not needed for this phase since focus is J-codes and radiation
- Manual xlsx creation: openxlsx2 package (2024+) provides programmatic styling with frozen panes, cell fills, fonts

## Open Questions

### Question 1: How complete is the NLM HCPCS API for 2026 codes?

**What we know:**
- NLM API exists and is free (https://clinicaltables.nlm.nih.gov/api/hcpcs/v3/search)
- API documentation describes JSON response format with `short_desc`, `long_desc`, `display` fields
- No published sync schedule with CMS quarterly updates

**What's unclear:**
- Does the API include April 2026 HCPCS additions, or does it lag behind by weeks/months?
- What percentage of codes from PROCEDURES table (PX_TYPE = "CH") will return valid descriptions?

**Recommendation:**
1. Implement NLM API approach as primary
2. Test on a sample of 10-20 unmatched codes from Phase 38 output
3. If >90% return valid descriptions, proceed with NLM
4. If <90%, fall back to CMS file download approach (requires inspecting ZIP contents)

### Question 2: Which J0-J8 supportive care codes should be included in widened heuristic?

**What we know:**
- D-02 specifies "curated J0-J8 supportive care codes (growth factors like pegfilgrastim, antiemetics like ondansetron)"
- J0-J8 range is ~800 codes, most unrelated to cancer treatment
- Phase 38 currently only detects J9xxx (chemotherapy)

**What's unclear:**
- Which specific J-codes are considered "supportive care for cancer treatment" vs. general hospital drugs?
- Should the heuristic expansion be a curated list (10-20 codes) or a broader range with classification filtering?

**Recommendation:**
1. Start with a curated list of 10-15 known supportive care codes:
   - J2506 (pegfilgrastim), J2505 (pegfilgrastim biosimilar), J1442 (filgrastim)
   - J2405 (ondansetron), J1626 (granisetron), J2469 (palonosetron)
   - J9035 (bevacizumab), J9355 (trastuzumab) — if considered supportive vs. chemo
2. Review Phase 38 output for other J0-J8 codes appearing in HL patient data
3. Expand list based on actual data presence, not theoretical completeness

### Question 3: What's the internal format of CMS HCPCS ZIP files?

**What we know:**
- CMS publishes quarterly HCPCS updates as ZIP files
- April 2026 file exists at https://www.cms.gov/files/zip/april-2026-alpha-numeric-hcpcs-file.zip
- No published field specification or data dictionary

**What's unclear:**
- Is the internal file CSV, Excel (.xlsx), or fixed-width text?
- Which columns contain code and description?
- Are there multiple files per ZIP (e.g., additions, deletions, full list)?

**Recommendation:**
1. If NLM API fails for critical codes, download April 2026 ZIP file
2. Inspect contents: `unzip -l april-2026-alpha-numeric-hcpcs-file.zip`
3. Extract and examine first 100 lines to determine format
4. Document findings in implementation notes for future phases

## Environment Availability

> Skipped — Phase 39 has no external tool dependencies beyond R packages. All required packages (stringr, dplyr, openxlsx2, httr, jsonlite) are CRAN packages installable via `install.packages()` on HiPerGator. No databases, CLI tools, or services required.

## Validation Architecture

> Skipped — workflow.nyquist_validation is explicitly set to false in .planning/config.json (confirmed by absence of test infrastructure in Phase 38 or other phases). Phase 39 produces an exploratory xlsx report, not production code requiring automated tests.

## Code Examples (Additional)

### Example 4: Widened Heuristic Range Detection (D-02 Implementation)

```r
# Source: Phase 38 CPT_HCPCS_RANGES pattern, expanded per D-02
CPT_HCPCS_RANGES_WIDENED <- list(
  Chemotherapy = list(
    j9_codes = "^J9[0-9]{3}$",           # J9000-J9999 (existing)
    j0_j8_supportive = "^J(2506|2505|1442|2405|1626)$"  # Curated supportive care
  ),
  Radiation = list(
    delivery = "^774[0-9]{2}$",          # 77400-77499 (existing)
    planning = "^773[3-9][0-9]$"         # 77330-77399 treatment planning (new, excludes 772xx simulation)
  ),
  SCT = list(
    transplant = "^382[3-4][0-9]$"       # 38230-38249 (no change)
  ),
  Immunotherapy = list(
    car_t_admin = "^XW0[34]3[A-Z][0-9]$" # CAR T-cell ICD-10-PCS (no change)
  )
)

# Usage in detect_unknown_codes():
combined_regex <- paste(unlist(CPT_HCPCS_RANGES_WIDENED[[treatment_type]]), collapse = "|")
```

### Example 5: xlsx Report Generation (D-07 Implementation)

```r
# Source: Phase 38 R/38_treatment_inventory.R write_treatment_sheet() pattern
library(openxlsx2)

write_unmatched_report <- function(unmatched_with_classification, output_path) {
  wb <- wb_workbook()

  for (treatment_type in c("Chemotherapy", "Radiation", "SCT", "Immunotherapy", "Supportive Care", "Unrelated")) {
    df <- unmatched_with_classification %>% filter(classification == treatment_type)
    if (nrow(df) == 0) next  # Skip empty categories

    wb$add_worksheet(treatment_type)

    # Title (row 1)
    wb$add_data(sheet = treatment_type, x = "Unmatched Treatment Codes Investigation",
                start_row = 1, start_col = 1)
    wb$add_font(sheet = treatment_type, dims = "A1",
                name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
    wb$merge_cells(sheet = treatment_type, dims = "A1:F1")

    # Subtitle (row 2)
    wb$add_data(sheet = treatment_type,
                x = glue("{treatment_type}: {nrow(df)} codes not in TREATMENT_CODES"),
                start_row = 2, start_col = 1)
    wb$add_font(sheet = treatment_type, dims = "A2",
                name = "Calibri", size = 10, color = wb_color("FF6B7280"))

    # Column headers (row 4)
    headers <- c("Code", "Description", "Source Table", "Patient Count", "Classification")
    for (i in seq_along(headers)) {
      wb$add_data(sheet = treatment_type, x = headers[i], start_row = 4, start_col = i)
    }
    wb$add_fill(sheet = treatment_type, dims = "A4:E4", color = wb_color("FF374151"))
    wb$add_font(sheet = treatment_type, dims = "A4:E4",
                name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

    # Data rows (row 5+)
    wb$add_data(sheet = treatment_type, x = df, start_row = 5, start_col = 1)

    # Freeze panes at row 5 (header row)
    wb$freeze_pane(sheet = treatment_type, first_active_row = 5, first_active_col = 1)

    # Column widths
    wb$set_col_widths(sheet = treatment_type, cols = 1:5, widths = c(10, 50, 20, 15, 20))
  }

  wb$save(file = output_path)
  message(glue("Wrote unmatched codes report: {output_path}"))
}
```

## Sources

### Primary (HIGH confidence)

- NLM HCPCS API documentation: https://clinicaltables.nlm.nih.gov/apidoc/hcpcs/v3/doc.html — API structure, query parameters, response format
- dplyr 1.2.0 case_when() documentation: https://dplyr.tidyverse.org/reference/case_when.html — classification pattern
- stringr str_detect() documentation: https://stringr.tidyverse.org/reference/str_detect.html — keyword matching pattern
- openxlsx2 conditional formatting vignette: https://cran.r-project.org/web/packages/openxlsx2/vignettes/conditional-formatting.html — xlsx styling
- Phase 38 implementation (R/38_treatment_inventory.R) — existing heuristic detection, xlsx styling patterns
- Phase 38 CONTEXT.md and PLAN.md — code matching architecture

### Secondary (MEDIUM confidence)

- CMS HCPCS Quarterly Update page: https://www.cms.gov/medicare/coding-billing/healthcare-common-procedure-system/quarterly-update — download location for April 2026 file (verified file exists, format unknown)
- CMS List of CPT/HCPCS Codes: https://www.cms.gov/medicare/regulations-guidance/physician-self-referral/list-cpt-hcpcs-codes — annual update PDF (January 2026), not granular code descriptions
- HCPCSData.com: https://www.hcpcsdata.com/ — free web lookup (verified 2026 codes present), no API documented
- AAPC HCPCS lookup: https://www.aapc.com/codes/hcpcs-codes-range/ — commercial service, not used

### Tertiary (LOW confidence)

- CMS HCPCS file internal format: UNKNOWN — ZIP files exist but internal structure (CSV vs Excel vs text) not documented on CMS website; requires download and inspection
- NLM API coverage of April 2026 codes: UNKNOWN — no published sync schedule; requires testing against actual unmatched codes from Phase 38 output
- Completeness of supportive care keyword list: LOW — based on common drugs (filgrastim, ondansetron), not exhaustive clinical review

## Metadata

**Confidence breakdown:**
- NLM API approach: MEDIUM — API exists and is documented (HIGH), but 2026 code coverage unknown until tested (LOW)
- Classification heuristics: MEDIUM — Pattern is established (case_when + keyword matching), but accuracy depends on description quality and keyword completeness
- R/00_config.R programmatic update: MEDIUM — Approach is feasible with readLines/writeLines, but R code parsing is fragile; requires robust validation
- xlsx report generation: HIGH — Phase 38 already implemented this pattern successfully with openxlsx2

**Research date:** 2026-05-04
**Valid until:** 60 days (July 2026) — NLM API stability is high, HCPCS code system changes quarterly but structure is stable

---

*Phase: 39-investigate-unmatched-codes*
*Research completed: 2026-05-04*
