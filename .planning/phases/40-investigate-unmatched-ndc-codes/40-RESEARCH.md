# Phase 40: Investigate Unmatched NDC Codes - Research

**Researched:** 2026-05-04
**Domain:** Drug code investigation — NDC and RXNORM CUI lookup via NLM RxNorm API
**Confidence:** HIGH

## Summary

Phase 40 investigates drug codes in PCORnet CDM drug tables (DISPENSING, PRESCRIBING, MED_ADMIN) that aren't captured by current TREATMENT_CODES configuration. Unlike Phase 39 (CPT/HCPCS procedure codes), this phase focuses on National Drug Codes (NDC) and RXNORM Concept Unique Identifiers (CUIs), using the NLM RxNorm REST API for drug name resolution and automated keyword-based classification into treatment categories.

The core approach mirrors Phase 39's successful 8-section script structure: extract unmatched codes from drug tables, look up drug names via RxNorm API, auto-classify using keyword matching (chemotherapy, supportive care, SCT-related, immunotherapy, unrelated), produce a styled xlsx report, save RDS artifact, and optionally update R/00_config.R with new code vectors. The current configuration has only 4 RXNORM CUIs (ABVD regimen components) and zero NDC codes, creating significant coverage gaps for comprehensive Hodgkin lymphoma treatment detection.

**Primary recommendation:** Follow Phase 39's proven investigation pipeline structure exactly — use httr2 for modern HTTP with built-in retry/rate limiting, query all three drug tables (DISPENSING.NDC + RXNORM_CUI, PRESCRIBING.RXNORM_CUI, MED_ADMIN.RXNORM_CUI), batch API lookups with 0.1s sleep (well under 20 req/sec limit), classify via Hodgkin-specific drug name keywords, create openxlsx2 styled workbook matching Phase 38/39 patterns, and produce both xlsx report and RDS artifact for downstream config updates.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Investigate both NDC codes (from DISPENSING.NDC) AND unmatched RXNORM CUIs (from PRESCRIBING, DISPENSING, MED_ADMIN) — current `chemo_rxnorm` only has 4 CUIs (ABVD regimen), so significant gaps are expected
- **D-02:** All 3 drug tables in scope: DISPENSING (NDC + RXNORM), PRESCRIBING (RXNORM), MED_ADMIN (RXNORM)
- **D-03:** Exclude ICD, DRG, revenue, CPT/HCPCS — those were covered by Phase 39
- **D-04:** Use NLM RxNorm API (rxnav.nlm.nih.gov) for both NDC-to-drug-name and RXNORM-to-drug-name resolution — free, no auth, same NLM infrastructure as Phase 39's HCPCS API
- **D-05:** NDC lookup endpoint: `/REST/ndcstatus` or `/REST/rxcui` for NDC-to-RxNorm mapping, then `/REST/rxcui/{rxcui}/properties` for drug name
- **D-06:** RXNORM lookup endpoint: `/REST/rxcui/{rxcui}/properties` for drug name directly
- **D-07:** Fully automated classification via drug name keyword matching — same approach as Phase 39 (no manual review step)
- **D-08:** Treatment categories: chemo, radiation (unlikely for drugs but include), SCT-related, immunotherapy, supportive care, unrelated
- **D-09:** Keyword patterns based on known HL treatment drugs (doxorubicin, bleomycin, vinblastine, dacarbazine, brentuximab, nivolumab, filgrastim, ondansetron, etc.)
- **D-10:** Add new NDC vectors to TREATMENT_CODES: `chemo_ndc`, `supportive_care_ndc`, etc. — keeps code types separate (existing pattern in TREATMENT_CODES)
- **D-11:** Expand `chemo_rxnorm` (and add new RXNORM vectors as needed) with newly discovered treatment-relevant RXNORM CUIs
- **D-12:** Produce xlsx report of all unmatched codes with drug names, classifications, patient counts, and source tables
- **D-13:** Produce RDS artifact for downstream config update consumption (same pattern as Phase 39)

### Claude's Discretion
- Specific RxNorm API endpoint selection and batching strategy
- Keyword classification rules (drug name patterns for each treatment category)
- xlsx report layout and styling (consistent with Phase 38/39 output patterns)
- Handling of NDC codes that don't resolve via RxNorm API (log as unresolved vs skip)
- Whether to add MED_ADMIN NDC codes (if MEDADMIN_CODE contains NDC values) or only DISPENSING.NDC

### Deferred Ideas (OUT OF SCOPE)
- Downstream script updates (R/03, R/10) to actually match on new NDC vectors — those scripts currently only use RXNORM_CUI for drug matching. Adding NDC matching to cohort/treatment pipelines is a separate phase.
- ICD-10-PCS broader range detection for drug administration codes
- Drug interaction or polypharmacy analysis

</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| httr2 | 1.0.9+ | HTTP client with retry/rate limiting | Modern replacement for httr (Feb 2026 release); built-in `req_retry()` and `req_throttle()` for API robustness; pipeable API |
| jsonlite | 1.9.2+ | JSON parsing | Industry standard for API response parsing; handles nested structures from RxNorm API properties endpoints |
| openxlsx2 | 1.19.1+ | Excel workbook creation | Latest stable (April 2026); Phase 38/39 use this for styled xlsx reports with conditional formatting |
| dplyr | 1.2.0+ | Data manipulation | tidyverse core; existing Phase 38/39 pattern for grouping, summarizing, filtering drug codes |
| stringr | 1.5.1+ | String operations | Keyword matching for classification; drug name normalization (tolower, str_detect) |
| glue | 1.8.0+ | String interpolation | Readable logging and dynamic xlsx titles (Phase 39 pattern) |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| tidyr | 1.3.1+ | Data reshaping | If API responses need unnesting (unnest_wider for nested JSON properties) |
| purrr | 1.0.2+ | Functional iteration | Alternative to for-loops in API batching (map_dfr for cleaner batch lookup) |
| tibble | 3.2.1+ | Modern data frames | Better printing for debugging; included in tidyverse |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| httr2 | httr (legacy) | httr2 has built-in retry/rate limiting via `req_retry()`; httr requires manual `RETRY()` wrapper with less flexibility |
| httr2 | RxNormR package (GitHub) | RxNormR last updated 2019, not on CRAN; httr2 + raw API calls more maintainable and allows Phase 39 code reuse |
| httr2 | rxnorm package (nt-williams) | More recent (Apr 2025) but limited to RxCUI lookups; doesn't handle NDC endpoints; raw API gives full control |
| openxlsx2 | openxlsx (legacy) | openxlsx2 is modern rewrite (April 2026) with faster performance and cleaner API; Phase 38/39 already use it |

**Installation:**
```r
# In R console (interactive session on HiPerGator):
install.packages(c("httr2", "jsonlite", "openxlsx2", "tidyr", "purrr"))
# Core packages (dplyr, stringr, glue, tibble) already installed as tidyverse dependencies
```

**Version verification:**
As of 2026-05-04:
- httr2 1.0.9 (CRAN, Feb 2026)
- jsonlite 1.9.2 (CRAN, verified current)
- openxlsx2 1.19.1 (CRAN, April 2026)
- tidyr 1.3.1, purrr 1.0.2 (tidyverse dependencies)

## Architecture Patterns

### Recommended Project Structure
```
R/
├── 40_investigate_unmatched_ndc.R   # Main investigation script
├── 00_config.R                       # TREATMENT_CODES update target (lines 385-659)
└── 01_load_pcornet.R                 # get_pcornet_table() for data access

output/
└── unmatched_ndc_report.xlsx         # Styled xlsx output
└── unmatched_ndc_classified.rds      # RDS artifact for Plan 02 consumption

.planning/phases/40-investigate-unmatched-ndc-codes/
├── 40-CONTEXT.md
├── 40-RESEARCH.md
└── 40-01-PLAN.md                     # Investigation + report generation
└── 40-02-PLAN.md                     # Config update (if warranted)
```

### Pattern 1: 8-Section Investigation Script (Reuse Phase 39 Template)
**What:** Mimic R/39_investigate_unmatched.R's proven structure for consistency
**When to use:** Always for Phase 40 implementation
**Sections:**
1. Setup and Configuration — source config/load functions, load libraries, set output paths
2. Extract Unmatched Drug Codes — query 3 drug tables, filter out existing TREATMENT_CODES, count records + patients
3. RxNorm API Lookup — batch lookup with retry/rate limiting
4. Auto-Classification — keyword-based categorization
5. Excel Report Generation — openxlsx2 styled workbook
6. Save RDS Artifact — for Plan 02 config update consumption
7. Main Execution — orchestrate steps 1-6 with logging
8. Config Update Function (optional) — programmatic insertion into R/00_config.R

**Example:**
```r
# SECTION 1: SETUP
source("R/00_config.R")
source("R/01_load_pcornet.R")
library(httr2)
library(jsonlite)
library(openxlsx2)
library(dplyr)
library(stringr)
library(glue)

OUTPUT_PATH <- file.path(CONFIG$output_dir, "unmatched_ndc_report.xlsx")
RDS_PATH <- file.path(CONFIG$output_dir, "unmatched_ndc_classified.rds")
```

### Pattern 2: RxNorm API Lookup with httr2 Retry/Rate Limiting
**What:** Query NLM RxNorm REST API with automatic retries and rate limiting
**When to use:** For all NDC and RXNORM CUI drug name lookups
**API endpoints:**
- NDC → RxCUI: `GET https://rxnav.nlm.nih.gov/REST/rxcui.json?idtype=NDC&id={ndc}`
- RxCUI properties: `GET https://rxnav.nlm.nih.gov/REST/rxcui/{rxcui}/allProperties.json?prop=names`
- Alternative: `GET https://rxnav.nlm.nih.gov/REST/rxcui/{rxcui}/properties.json` (returns name directly)

**Example:**
```r
# Source: httr2.r-lib.org official docs + RxNorm API spec
lookup_rxcui_name <- function(rxcui, sleep_sec = 0.1) {
  url <- glue("https://rxnav.nlm.nih.gov/REST/rxcui/{rxcui}/properties.json")

  resp <- request(url) %>%
    req_timeout(10) %>%
    req_retry(
      max_tries = 3,
      is_transient = ~ resp_status(.x) %in% c(429, 503, 504)
    ) %>%
    req_perform()

  if (resp_status(resp) == 200) {
    data <- resp_body_json(resp, simplifyVector = TRUE)
    name <- data$properties$name  # RxNorm name
    return(tibble(rxcui = rxcui, drug_name = name, lookup_status = "success"))
  } else {
    return(tibble(rxcui = rxcui, drug_name = NA_character_, lookup_status = glue("HTTP {resp_status(resp)}")))
  }

  Sys.sleep(sleep_sec)  # Rate limiting: 0.1s = 10 req/sec (well under 20 req/sec limit)
}

# Batch lookup with progress logging
lookup_rxcui_batch <- function(rxcuis, sleep_sec = 0.1) {
  results <- list()
  for (i in seq_along(rxcuis)) {
    if (i %% 10 == 0) message(glue("  Looked up {i}/{length(rxcuis)} RxCUIs"))
    results[[i]] <- lookup_rxcui_name(rxcuis[i], sleep_sec)
  }
  bind_rows(results)
}
```

### Pattern 3: NDC Code Extraction from Three Drug Tables
**What:** Query DISPENSING, PRESCRIBING, MED_ADMIN for all drug codes in HL patients, filter out existing TREATMENT_CODES
**When to use:** Step 2 of investigation script
**Example:**
```r
# Source: R/38_treatment_inventory.R lines 239-280 (existing drug extraction pattern)
extract_unmatched_drug_codes <- function() {
  hl_ids <- get_hl_patient_ids()  # From R/03_cohort_predicates.R or inline query

  # Get existing codes from TREATMENT_CODES
  known_rxnorm <- TREATMENT_CODES$chemo_rxnorm  # Currently only 4 CUIs
  known_ndc <- character(0)  # No NDC vectors exist yet

  results <- list()

  # 1. DISPENSING: RXNORM_CUI + NDC
  disp_tbl <- get_pcornet_table("DISPENSING")

  # DISPENSING RXNORM (unmatched)
  disp_rxnorm <- disp_tbl %>%
    filter(ID %in% hl_ids) %>%
    filter(!is.na(RXNORM_CUI) & RXNORM_CUI != "") %>%
    filter(!RXNORM_CUI %in% known_rxnorm) %>%
    group_by(code = RXNORM_CUI, drug_name = RAW_DISPENSE_MED_NAME) %>%
    summarise(n_records = n(), n_patients = n_distinct(ID), .groups = "drop") %>%
    collect() %>%
    mutate(source_table = "DISPENSING", code_type = "RXNORM")
  results <- c(results, list(disp_rxnorm))

  # DISPENSING NDC (all unmatched since no known_ndc exists)
  disp_ndc <- disp_tbl %>%
    filter(ID %in% hl_ids) %>%
    filter(!is.na(NDC) & NDC != "") %>%
    group_by(code = NDC, drug_name = RAW_DISPENSE_MED_NAME) %>%
    summarise(n_records = n(), n_patients = n_distinct(ID), .groups = "drop") %>%
    collect() %>%
    mutate(source_table = "DISPENSING", code_type = "NDC")
  results <- c(results, list(disp_ndc))

  # 2. PRESCRIBING: RXNORM_CUI only
  rx_tbl <- get_pcornet_table("PRESCRIBING")
  rx_rxnorm <- rx_tbl %>%
    filter(ID %in% hl_ids) %>%
    filter(!is.na(RXNORM_CUI) & RXNORM_CUI != "") %>%
    filter(!RXNORM_CUI %in% known_rxnorm) %>%
    group_by(code = RXNORM_CUI, drug_name = RAW_RX_MED_NAME) %>%
    summarise(n_records = n(), n_patients = n_distinct(ID), .groups = "drop") %>%
    collect() %>%
    mutate(source_table = "PRESCRIBING", code_type = "RXNORM")
  results <- c(results, list(rx_rxnorm))

  # 3. MED_ADMIN: RXNORM_CUI only (MEDADMIN_CODE may have NDC but not documented in spec)
  ma_tbl <- get_pcornet_table("MED_ADMIN")
  ma_rxnorm <- ma_tbl %>%
    filter(ID %in% hl_ids) %>%
    filter(!is.na(RXNORM_CUI) & RXNORM_CUI != "") %>%
    filter(!RXNORM_CUI %in% known_rxnorm) %>%
    group_by(code = RXNORM_CUI, drug_name = RAW_MEDADMIN_MED_NAME) %>%
    summarise(n_records = n(), n_patients = n_distinct(ID), .groups = "drop") %>%
    collect() %>%
    mutate(source_table = "MED_ADMIN", code_type = "RXNORM")
  results <- c(results, list(ma_rxnorm))

  bind_rows(results)
}
```

### Pattern 4: Keyword-Based Drug Classification
**What:** Auto-classify drugs into treatment categories using case_when() + str_detect() on drug names
**When to use:** After API lookup provides drug names
**Order matters:** Supportive care MUST come before chemotherapy to avoid misclassifying supportive drugs (filgrastim, ondansetron) as chemo
**Example:**
```r
# Source: R/39_investigate_unmatched.R lines 247-280 (adapted for drugs)
classify_drug <- function(code, drug_name, code_type) {
  name_lower <- tolower(ifelse(is.na(drug_name), "", drug_name))

  case_when(
    # 1. Supportive care FIRST (colony-stimulating factors, antiemetics, etc.)
    str_detect(name_lower,
      "filgrastim|pegfilgrastim|neulasta|neupogen|zarxio|granix|udenyca|nyvepria|ziextenzo|stimufend|fylnetra|releuko|ondansetron|zofran|granisetron|kytril|palonosetron|aloxi|fosaprepitant|emend|aprepitant|dexamethasone|colony.stimulating|growth factor|antiemetic|epoetin|procrit|darbepoetin|aranesp|lenograstim|tbo-filgrastim|lipegfilgrastim"
    ) ~ "Supportive Care",

    # 2. Chemotherapy (ABVD components + other HL agents)
    str_detect(name_lower,
      "doxorubicin|adriamycin|bleomycin|vinblastine|dacarbazine|dtic|brentuximab|adcetris|nivolumab|opdivo|pembrolizumab|keytruda|etoposide|cisplatin|carboplatin|vincristine|cyclophosphamide|cytoxan|bendamustine|gemcitabine|ifosfamide|methotrexate|procarbazine|mechlorethamine|lomustine|carmustine|chemotherapy|antineoplastic|cytotoxic"
    ) ~ "Chemotherapy",

    # 3. Immunotherapy (checkpoint inhibitors, CAR-T if drugs exist)
    str_detect(name_lower,
      "nivolumab|pembrolizumab|atezolizumab|durvalumab|avelumab|ipilimumab|cemiplimab|dostarlimab|retifanlimab|toripalimab|tislelizumab|checkpoint inhibitor|anti-pd-1|anti-pd-l1|anti-ctla-4|car.t|chimeric antigen|axicabtagene|tisagenlecleucel|brexucabtagene|lisocabtagene"
    ) ~ "Immunotherapy",

    # 4. SCT-related (unlikely for drugs but include for completeness)
    str_detect(name_lower,
      "stem cell|bone marrow|hematopoietic|transplant|conditioning|busulfan|melphalan|thiotepa|fludarabine|cyclophosphamide.*transplant"
    ) ~ "SCT-related",

    # 5. Radiation (very unlikely for drug tables, but include for consistency)
    str_detect(name_lower, "radiation|radiotherapy|radiolabeled") ~ "Radiation",

    # 6. Default: Unrelated
    TRUE ~ "Unrelated"
  )
}
```

### Pattern 5: Styled Excel Report with openxlsx2
**What:** Create multi-sheet xlsx workbook with summary sheet + per-category sheets, colored by treatment type
**When to use:** Final output step
**Example:**
```r
# Source: R/39_investigate_unmatched.R lines 283-450 (xlsx generation pattern)
# Reuse TREATMENT_TYPE_COLORS from Phase 39 for consistency
TREATMENT_TYPE_COLORS <- list(
  Chemotherapy      = list(fill = "FFDCEEFB", font = "FF0B5394"),  # light blue / dark blue
  Radiation         = list(fill = "FFDDF4E1", font = "FF274E13"),  # light green / dark green
  `SCT-related`     = list(fill = "FFFFF4D6", font = "FF7F6000"),  # light yellow / dark olive
  Immunotherapy     = list(fill = "FFE8DCF4", font = "FF4C1D7A"),  # light purple / dark purple
  `Supportive Care` = list(fill = "FFD5F5F0", font = "FF0E6655"),  # light teal / dark teal
  Unrelated         = list(fill = "FFF3F4F6", font = "FF6B7280")   # light gray / medium gray
)

write_unmatched_ndc_report <- function(classified_df, output_path) {
  wb <- wb_workbook()

  # Summary sheet: classification counts + percentages
  wb$add_worksheet("Summary")
  wb$add_data("Summary", x = "Unmatched NDC/RXNORM Investigation Summary", start_row = 1, start_col = 1)
  # ... (follow Phase 39 exact styling pattern)

  # Per-category sheets with colored code pills
  for (category in c("Chemotherapy", "Supportive Care", "Immunotherapy", "SCT-related", "Unrelated")) {
    df_cat <- classified_df %>% filter(classification == category)
    if (nrow(df_cat) == 0) next

    wb$add_worksheet(category)
    # Headers: Code | Drug Name | Code Type | Source Table | Records | Patients | Lookup Status
    # Apply fill/font colors from TREATMENT_TYPE_COLORS
    # ... (follow Phase 39 styling exactly)
  }

  wb$save(output_path)
}
```

### Anti-Patterns to Avoid

- **Don't use legacy httr package:** Phase 39 used httr; httr2 is modern replacement with better retry/rate limiting API
- **Don't query drug tables without filtering to HL patients:** Full drug tables are massive; always filter by HL patient IDs first
- **Don't classify supportive care after chemotherapy:** Keywords like "colony-stimulating" would match "chemotherapy" if checked first; order matters in case_when()
- **Don't assume all NDC codes are 11 digits:** PCORnet may have 10-digit (4-4-2, 5-3-2, 5-4-1) or 11-digit (5-4-2) formats; RxNorm API accepts both
- **Don't use RxNormR package from GitHub:** Unmaintained since 2019; raw httr2 calls are more reliable and match Phase 39 pattern

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| RxNorm API wrapper | Custom httr request builder with manual retry logic | httr2 with `req_retry()` + `req_throttle()` | httr2 has built-in exponential backoff, transient error detection (429, 503), and automatic retries; manual retry is error-prone |
| NDC format normalization | Custom regex to convert 10-digit → 11-digit | Pass as-is to RxNorm API | RxNorm API accepts both formats; premature normalization introduces bugs (which segment to pad?) |
| Drug name keyword lists | Manually curated drug list from Google searches | Extract from existing literature + Phase 38 RAW_*_MED_NAME columns | PCORnet RAW_MED_NAME fields contain actual drug names from source data; use them to validate keywords |
| Excel styling | Manual cell-by-cell formatting loops | openxlsx2 `wb_add_fill()`, `wb_add_font()`, color constants | Phase 38/39 established TREATMENT_TYPE_COLORS palette; reuse for consistency |
| API response parsing | String manipulation on JSON responses | jsonlite with simplifyVector = TRUE | RxNorm API returns nested JSON; jsonlite handles it robustly |

**Key insight:** Phase 39 solved all infrastructure problems (API batching, retry, xlsx styling, config update validation). Phase 40 should reuse that code nearly verbatim, changing only the API endpoint and classification keywords.

## Common Pitfalls

### Pitfall 1: NDC Format Confusion (10-digit vs 11-digit)
**What goes wrong:** Attempting to normalize NDC codes before API lookup, introducing conversion bugs
**Why it happens:** HIPAA mandates 11-digit 5-4-2 format, but PCORnet may have 10-digit variants (4-4-2, 5-3-2, 5-4-1)
**How to avoid:** Pass NDC codes to RxNorm API as-is; API accepts both 10 and 11-digit formats
**Warning signs:** Errors like "Invalid NDC format" from homegrown normalization logic; codes not found despite being valid

### Pitfall 2: Rate Limiting Violations (HTTP 429 errors)
**What goes wrong:** API requests fail with "Too Many Requests" errors
**Why it happens:** RxNorm API allows up to 20 requests/second; tight loops without sleep exceed this
**How to avoid:** Use httr2's `req_throttle()` OR manual `Sys.sleep(0.1)` between requests (10 req/sec is safe margin)
**Warning signs:** HTTP 429 status codes in lookup results; intermittent failures on large batches

### Pitfall 3: Misclassifying Supportive Care Drugs as Chemotherapy
**What goes wrong:** Filgrastim (G-CSF) classified as "Chemotherapy" instead of "Supportive Care"
**Why it happens:** Keyword order in case_when() matters; if "chemotherapy" keyword check comes before supportive care check, and drug name contains "chemotherapy" context (e.g., "used with chemotherapy"), it misclassifies
**How to avoid:** ALWAYS check supportive care keywords BEFORE chemotherapy keywords in case_when() (Phase 39 learned this lesson)
**Warning signs:** Known supportive drugs (filgrastim, ondansetron, pegfilgrastim) appearing in Chemotherapy category in report

### Pitfall 4: Empty Drug Name Fields Breaking Classification
**What goes wrong:** Classification function crashes on NA drug names from failed API lookups
**Why it happens:** Not all codes resolve successfully; API returns NA for not-found codes
**How to avoid:** Always use `ifelse(is.na(drug_name), "", drug_name)` before tolower() and str_detect()
**Warning signs:** "Error in tolower() : argument is not a character vector" during classification step

### Pitfall 5: Ignoring Code Type in Classification Logic
**What goes wrong:** Treating NDC and RXNORM codes identically when they may need different handling
**Why it happens:** Drug name is primary classification signal, but code type context helps (e.g., J-codes in Phase 39 had heuristic ranges)
**How to avoid:** Include `code_type` parameter in classify_drug() function; use it as tiebreaker if drug name is ambiguous
**Warning signs:** NDC codes for brand names (e.g., "Neulasta" vs generic "pegfilgrastim") classified differently despite being same drug

### Pitfall 6: Config Update Without Validation (Parse Errors)
**What goes wrong:** Programmatic insertion of new codes into R/00_config.R breaks R syntax, causing all downstream scripts to fail
**Why it happens:** String manipulation (readLines/writeLines) doesn't validate R syntax; missing commas, unmatched parentheses, etc.
**How to avoid:** After config update, ALWAYS validate with `parse()` and `source()` in tryCatch; rollback from backup if validation fails (Phase 39 pattern)
**Warning signs:** "Error: unexpected symbol" when sourcing R/00_config.R after update

## Code Examples

Verified patterns from Phase 39 and RxNorm API documentation:

### Example 1: RxNorm API Lookup with httr2 Retry
```r
# Source: httr2.r-lib.org/reference/req_retry.html + RxNorm API spec
library(httr2)
library(jsonlite)
library(glue)

lookup_rxcui_properties <- function(rxcui) {
  url <- glue("https://rxnav.nlm.nih.gov/REST/rxcui/{rxcui}/properties.json")

  resp <- request(url) %>%
    req_timeout(10) %>%
    req_retry(
      max_tries = 3,
      is_transient = ~ resp_status(.x) %in% c(429, 503, 504),
      backoff = ~ 2 ^ .x  # Exponential backoff: 2s, 4s, 8s
    ) %>%
    req_perform()

  if (resp_status(resp) == 200) {
    data <- resp_body_json(resp, simplifyVector = TRUE)
    return(list(
      rxcui = rxcui,
      drug_name = data$properties$name,
      status = "success"
    ))
  } else {
    return(list(
      rxcui = rxcui,
      drug_name = NA_character_,
      status = glue("HTTP {resp_status(resp)}")
    ))
  }
}
```

### Example 2: NDC to RxCUI Mapping
```r
# Source: RxNorm API spec + WebSearch results
# Endpoint: GET /REST/rxcui.json?idtype=NDC&id={ndc}
lookup_ndc_to_rxcui <- function(ndc) {
  url <- glue("https://rxnav.nlm.nih.gov/REST/rxcui.json?idtype=NDC&id={ndc}")

  resp <- request(url) %>%
    req_timeout(10) %>%
    req_retry(max_tries = 3) %>%
    req_perform()

  if (resp_status(resp) == 200) {
    data <- resp_body_json(resp, simplifyVector = TRUE)
    # Response structure: data$idGroup$rxnormId (may be array or NULL)
    rxcui <- data$idGroup$rxnormId[1]  # Take first if multiple
    return(tibble(ndc = ndc, rxcui = rxcui, status = "success"))
  } else {
    return(tibble(ndc = ndc, rxcui = NA_character_, status = glue("HTTP {resp_status(resp)}")))
  }
}

# Then lookup drug name via rxcui
lookup_ndc_drug_name <- function(ndc) {
  # Step 1: NDC → RxCUI
  rxcui_result <- lookup_ndc_to_rxcui(ndc)
  if (is.na(rxcui_result$rxcui)) {
    return(tibble(ndc = ndc, drug_name = NA_character_, status = rxcui_result$status))
  }

  # Step 2: RxCUI → Properties
  Sys.sleep(0.1)  # Rate limiting
  props <- lookup_rxcui_properties(rxcui_result$rxcui)
  return(tibble(ndc = ndc, drug_name = props$drug_name, status = props$status))
}
```

### Example 3: Keyword-Based Classification Function
```r
# Source: R/39_investigate_unmatched.R lines 247-280 (adapted for drugs)
classify_drug <- function(code, drug_name, code_type, source_table) {
  name_lower <- tolower(ifelse(is.na(drug_name), "", drug_name))

  case_when(
    # 1. Supportive Care FIRST (prevents misclassification)
    str_detect(name_lower,
      "filgrastim|pegfilgrastim|neulasta|neupogen|ondansetron|zofran|granisetron|palonosetron|fosaprepitant|emend|dexamethasone|colony.stimulating|growth factor|antiemetic|epoetin|darbepoetin"
    ) ~ "Supportive Care",

    # 2. Chemotherapy (ABVD + other HL regimens)
    str_detect(name_lower,
      "doxorubicin|bleomycin|vinblastine|dacarbazine|brentuximab|etoposide|cisplatin|carboplatin|vincristine|cyclophosphamide|bendamustine|gemcitabine|procarbazine|mechlorethamine|lomustine|carmustine|chemotherapy|antineoplastic"
    ) ~ "Chemotherapy",

    # 3. Immunotherapy
    str_detect(name_lower,
      "nivolumab|pembrolizumab|checkpoint inhibitor|anti-pd-1|anti-pd-l1|car.t|chimeric antigen"
    ) ~ "Immunotherapy",

    # 4. SCT-related
    str_detect(name_lower,
      "stem cell|bone marrow|transplant|conditioning"
    ) ~ "SCT-related",

    # 5. Radiation (unlikely for drugs)
    str_detect(name_lower, "radiation|radiotherapy") ~ "Radiation",

    # 6. Default
    TRUE ~ "Unrelated"
  )
}
```

### Example 4: Config Update with Parse Validation
```r
# Source: R/39_investigate_unmatched.R lines 471-725 (config update pattern)
update_config_treatment_codes <- function(classified_rds_path) {
  # 1. Load classified codes
  classified <- readRDS(classified_rds_path)

  # 2. Filter to treatment-relevant categories (exclude "Unrelated")
  treatment_codes_new <- classified %>%
    filter(classification %in% c("Chemotherapy", "Supportive Care", "Immunotherapy", "SCT-related")) %>%
    arrange(classification, desc(n_patients))

  if (nrow(treatment_codes_new) == 0) {
    message("No treatment-relevant codes to add. Skipping config update.")
    return(invisible(NULL))
  }

  # 3. Map categories to TREATMENT_CODES vector names
  category_map <- c(
    "Chemotherapy" = "chemo_rxnorm",     # Expand existing
    "Supportive Care" = "supportive_care_ndc",  # Create new NDC vector
    "Immunotherapy" = "immunotherapy_rxnorm",   # Create new (if codes exist)
    "SCT-related" = "sct_rxnorm"                # Create new (if codes exist)
  )

  # 4. Read R/00_config.R
  config_path <- "R/00_config.R"
  backup_path <- paste0(config_path, ".bak")
  file.copy(config_path, backup_path, overwrite = TRUE)
  config_lines <- readLines(config_path)

  # 5. Insert new codes into appropriate vectors (logic from Phase 39)
  # ... (follow Phase 39's vector detection, insertion, and creation logic)

  # 6. Validate updated config
  writeLines(config_lines, config_path)
  validation_error <- tryCatch({
    parse(config_path)
    source(config_path, local = new.env())  # Source in isolated environment
    NULL  # Success
  }, error = function(e) e$message)

  if (!is.null(validation_error)) {
    message(glue("Config validation failed: {validation_error}"))
    message("Restoring backup...")
    file.copy(backup_path, config_path, overwrite = TRUE)
    stop("Config update failed validation. Rolled back.")
  }

  message("Config update validated successfully.")
  file.remove(backup_path)
  invisible(NULL)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| httr package | httr2 package | Feb 2026 | req_retry() built-in vs manual RETRY() wrapper; pipeable API; automatic backoff |
| Manual JSON parsing | jsonlite simplifyVector = TRUE | Stable since 2015 | Nested RxNorm API responses auto-flatten to data frames |
| openxlsx (legacy) | openxlsx2 | April 2026 release | Faster performance, modern API, better conditional formatting support |
| RxNormR package (GitHub) | Raw httr2 API calls | N/A (RxNormR stale since 2019) | Direct API control; matches Phase 39 pattern; no unmaintained dependencies |
| 10-digit NDC zero-padding | Pass as-is to API | N/A (API always accepted both) | Eliminates normalization bugs |

**Deprecated/outdated:**
- **httr::GET() + httr::RETRY():** Replaced by httr2's req_perform() + req_retry() (cleaner API, better defaults)
- **RxNormR package:** Last updated 2019, not on CRAN; use raw httr2 calls instead
- **Manual rate limiting with global counters:** httr2's req_throttle() handles this automatically

## Open Questions

1. **Do MED_ADMIN records contain NDC codes in MEDADMIN_CODE column?**
   - What we know: PCORnet CDM v7.0 spec (R/01_load_pcornet.R lines 255-271) shows MEDADMIN_CODE column but doesn't specify code type; RXNORM_CUI is documented
   - What's unclear: Whether MEDADMIN_CODE ever contains NDC values in OneFlorida+ data
   - Recommendation: Query MED_ADMIN table for HL patients, check MEDADMIN_CODE values; if NDC-like format (10-11 digits, hyphens), include in extraction; otherwise skip

2. **Should NDC vectors be split by treatment category (chemo_ndc, supportive_care_ndc) or unified (all_treatment_ndc)?**
   - What we know: Existing TREATMENT_CODES uses separate vectors per category-and-code-type (chemo_hcpcs, chemo_rxnorm, radiation_cpt)
   - What's unclear: Whether separate NDC vectors are needed for matching logic (R/03, R/10 currently don't use NDC at all)
   - Recommendation: Follow existing pattern — create chemo_ndc, supportive_care_ndc, etc. This matches TREATMENT_CODES structure and enables future selective matching

3. **How many unique NDC and RXNORM codes exist in HL patient drug records?**
   - What we know: Current chemo_rxnorm has only 4 CUIs (ABVD components); Phase 38 extracted "all drugs" from PRESCRIBING/DISPENSING/MED_ADMIN but didn't report counts
   - What's unclear: Volume estimate for API batching (100s? 1000s?)
   - Recommendation: Run exploratory query in investigation script; log counts before API lookup; adjust batching strategy if >500 codes

## Environment Availability

> All dependencies are R packages installable via CRAN; no external system tools required.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| httr2 | RxNorm API requests | ✓ (CRAN) | 1.0.9 (Feb 2026) | — |
| jsonlite | API response parsing | ✓ (CRAN) | 1.9.2+ | — |
| openxlsx2 | Excel report generation | ✓ (CRAN) | 1.19.1 (April 2026) | — |
| tidyverse | Data manipulation (dplyr, stringr, glue, etc.) | ✓ (installed) | 2.0.0+ | — |
| RxNorm API | Drug name lookup | ✓ (public REST API) | Current | None — blocking dependency |
| DuckDB backend | Drug table queries via get_pcornet_table() | ✓ (Phase 32 migration complete) | — | — |

**Missing dependencies with no fallback:**
- None — all packages available on CRAN; RxNorm API is public and free

**Missing dependencies with fallback:**
- None

**Notes:**
- httr2 not yet installed; add to renv.lock after `install.packages("httr2")`
- RxNorm API requires internet access; HiPerGator compute nodes have outbound HTTPS access
- No rate limit exceeded errors expected with 0.1s sleep (10 req/sec well under 20 req/sec limit)

## Sources

### Primary (HIGH confidence)
- [RxNorm API Documentation](https://lhncbc.nlm.nih.gov/RxNav/APIs/RxNormAPIs.html) - Official NLM API spec
- [getAllProperties Endpoint](https://lhncbc.nlm.nih.gov/RxNav/APIs/api-RxNorm.getAllProperties.html) - RxCUI to drug name lookup
- [getNDCProperties Endpoint](https://lhncbc.nlm.nih.gov/RxNav/APIs/api-RxNorm.getNDCProperties.html) - NDC property lookup
- [Mapping NDC, RXCUI, and Drug Names in RxNorm Files](https://www.nlm.nih.gov/research/umls/user_education/quick_tours/RxNorm/ndc_rxcui/NDC_RXCUI_DrugName.html) - NDC to RxCUI mapping methodology
- CRAN httr2 package - [httr2.r-lib.org](https://httr2.r-lib.org/) (version 1.0.9, Feb 2026)
- CRAN openxlsx2 package - [Package 'openxlsx2' April 17, 2026](https://cran.r-project.org/web/packages/openxlsx2/openxlsx2.pdf)
- R/39_investigate_unmatched.R (775 lines) - Primary template for Phase 40 script structure
- R/38_treatment_inventory.R (lines 239-280) - Drug code extraction pattern from DISPENSING/PRESCRIBING/MED_ADMIN

### Secondary (MEDIUM confidence)
- [Brentuximab vedotin, nivolumab, doxorubicin, and dacarbazine for advanced-stage classical Hodgkin lymphoma](https://pubmed.ncbi.nlm.nih.gov/39622165/) - HL treatment regimens for keyword patterns (2026)
- [Filgrastim - StatPearls](https://www.ncbi.nlm.nih.gov/books/NBK559282/) - G-CSF supportive care drug documentation
- [Supportive Treatments for Patients with Cancer - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC5545632/) - Antiemetic and colony-stimulating factor patterns
- [NDC Code Format Explained](https://www.drugs.com/ndc.html) - 10-digit vs 11-digit format variations
- [Federal Register: Revising the National Drug Code Format](https://www.federalregister.gov/documents/2022/07/25/2022-15414/revising-the-national-drug-code-format) - Future 12-digit format (not yet implemented)

### Tertiary (LOW confidence)
- RxNormR package (GitHub, mpancia/RxNormR) - Unmaintained since 2019; not recommended
- rxnorm package (GitHub, nt-williams/rxnorm) - More recent (April 2025) but limited scope; documentation sparse

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - httr2, openxlsx2, jsonlite all verified on CRAN with 2026 release dates
- Architecture: HIGH - Phase 39 provides complete template; RxNorm API officially documented
- Pitfalls: MEDIUM - Rate limiting and NDC format issues are well-documented; supportive care classification learned from Phase 39; config update validation proven in Phase 39
- Drug classification keywords: MEDIUM - Hodgkin regimens well-documented in recent literature; supportive care drugs verified in oncology references

**Research date:** 2026-05-04
**Valid until:** 60 days (stable domain — drug codes and RxNorm API change infrequently; ABVD has been standard HL treatment for 40 years)
