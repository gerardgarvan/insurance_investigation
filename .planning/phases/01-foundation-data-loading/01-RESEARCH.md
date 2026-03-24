# Phase 1: Foundation & Data Loading - Research

**Researched:** 2026-03-24
**Domain:** R data loading infrastructure for PCORnet CDM CSV files on HiPerGator
**Confidence:** HIGH

## Summary

Phase 1 establishes the foundation for the entire pipeline: configuration management, CSV data loading with explicit type specifications, multi-format date parsing, and utility functions for attrition logging. This phase has no data transformation or analysis — it purely sets up the infrastructure that all downstream phases depend on.

The research confirms that the standard R/tidyverse stack (readr, lubridate, janitor, glue) is mature and well-documented for this use case. The key technical challenges are: (1) handling PCORnet CSV files with mixed date formats from SAS exports, (2) creating explicit col_types specifications for 22 tables with hundreds of columns total, and (3) designing clean configuration structure for paths, ICD codes, and payer mappings.

**Primary recommendation:** Use readr::read_csv with explicit col_types specifications (not auto-detection), janitor::convert_to_date for multi-format date parsing with fallback chain, and nested list structure for config with clear section headers and inline comments for human readability.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Config structure:**
- **D-01:** Use nested lists for organization (CONFIG$data_dir, PCORNET_PATHS$ENROLLMENT, ICD_CODES$hl_icd10, PAYER_MAPPING$...) — prioritize human readability with clear comments per section
- **D-02:** HiPerGator-native paths only — data CSVs at `/orange/erin.mobley-hl.bcu/Mailhot_V1_20250915`, R project at `/blue/erin.mobley-hl.bcu/R`. No local development switching or environment variable abstraction needed
- **D-03:** ICD codes defined as inline character vectors in config (ICD_CODES$hl_icd10, ICD_CODES$hl_icd9) — all 149 codes visible in one place
- **D-04:** Payer mapping rules defined in config (PAYER_MAPPING list) — prefix-to-category mapping. Harmonization script (Phase 2) applies the mapping but doesn't define it
- **D-05:** Analysis parameters included in config (CONFIG$analysis with thresholds like min_enrollment_days, dx_window_days) — central place to tweak without hunting through scripts
- **D-06:** Explicit table list in config (PCORNET_TABLES vector) — loader iterates this list, no auto-discovery

**CSV loading strategy:**
- **D-07:** Primary load set = 6 standard CDM tables (ENROLLMENT, DIAGNOSIS, PROCEDURES, PRESCRIBING, ENCOUNTER, DEMOGRAPHIC) + 3 TUMOR_REGISTRY tables. TUMOR_REGISTRY tables are needed for HL diagnosis dates and treatment dates (DT_CHEMO, DT_RAD, etc.)
- **D-08:** Use readr::read_csv with explicit col_types — reliable, good error messages, sufficient for this cohort size
- **D-09:** Multi-format date parsing with fallback — try YYYY-MM-DD first, then DDMMMYYYY (SAS DATE9), then YYYYMMDD. Log warnings for unparseable dates
- **D-10:** Warn and skip on missing/inaccessible CSV files — log warning, continue loading other tables. Pipeline can work with partial data
- **D-11:** Use column names as-is from the CSVs — no renaming to CDM standard names. Patient ID column is `ID` (not `PATID`). All downstream code references actual column names
- **D-12:** Print load summary per table — table name, row count, column count, parse warnings
- **D-13:** Store loaded tables in a named list (pcornet$ENROLLMENT, pcornet$DIAGNOSIS, etc.) — clean namespace, easy to iterate
- **D-14:** CSV file naming pattern: `TABLE_Mailhot_V1.csv` (e.g., ENROLLMENT_Mailhot_V1.csv, DIAGNOSIS_Mailhot_V1.csv)
- **D-15:** SOURCE column in every table = partner/site identifier (AMS, UMI, FLM, VRT)

**Utility function design:**
- **D-16:** Manual log_attrition() calls — init_attrition_log() creates empty data frame, log_attrition(step_name, n_after) appends rows. User controls step names and what gets logged
- **D-17:** Attrition tracks patient-level counts (unique ID count), not row-level — clinically meaningful for CONSORT diagrams
- **D-18:** Attrition log includes percentage excluded at each step — columns: step_name, n_before, n_after, n_excluded, pct_excluded. Ready for waterfall chart labels
- **D-19:** No HIPAA suppression utilities — data stays on HiPerGator's HIPAA-compliant environment, exploratory outputs don't need suppression
- **D-20:** parse_pcornet_date() utility function — reusable date parser using lubridate that tries multiple SAS export formats with fallback
- **D-21:** 00_config.R auto-sources all utils_*.R files — any script that sources config gets utilities automatically
- **D-22:** Simple message() calls with glue for logging — no custom log wrapper needed

**Project scaffolding:**
- **D-23:** Numbered R/ scripts following architecture research: R/00_config.R, R/01_load_pcornet.R, R/02_harmonize_payer.R, R/03_cohort_predicates.R, R/04_build_cohort.R, R/05_visualize_waterfall.R, R/06_visualize_sankey.R, plus R/utils_*.R files
- **D-24:** No main.R orchestrator — scripts sourced manually in RStudio for interactive exploration
- **D-25:** Initialize renv from the start for reproducible package management on HiPerGator
- **D-26:** Create full output directory structure upfront: output/figures/, output/tables/, output/cohort/

### Claude's Discretion

- Exact col_types specifications per table (based on csv_columns.txt schema)
- Internal structure of the parse_pcornet_date() function
- renv initialization details
- .Rprofile and .gitignore contents

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| LOAD-01 | User can load 22 PCORnet CDM CSV tables with explicit column type specifications | readr::read_csv with cols() specification; csv_columns.txt provides complete schema; each table gets a named col_types object |
| LOAD-02 | User can parse dates in multiple SAS export formats (DATE9, DATETIME, YYYYMMDD) | janitor::convert_to_date with fallback chain; lubridate::parse_date_time for multi-format; handles mixed formats in single column |
| LOAD-03 | User can configure file paths, ICD code lists (149 HL codes), and payer mappings via `00_config.R` | Nested list structure (CONFIG, PCORNET_PATHS, ICD_CODES, PAYER_MAPPING); inline character vectors for codes; human-readable with comments |

</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| readr | 2.2.0+ | CSV loading | Industry standard for tibble-based CSV import; explicit col_types prevents silent failures; good error messages for parse problems |
| lubridate | 1.9.3+ | Date/time parsing | Handles SAS DATE9 (DDMMMYYYY), YYYYMMDD, YYYY-MM-DD formats; parse_date_time allows order-based parsing without separator specification |
| janitor | 2.2.1+ | Date conversion and cleaning | excel_numeric_to_date for Excel serial dates; convert_to_date handles mixed formats with fallback; clean_names if needed (not used per D-11) |
| glue | 1.8.0+ | String formatting for logging | Readable logging messages with embedded expressions: `glue("Loaded {nrow(df)} rows from {table_name}")` |
| here | 1.0.2+ | Path management | Project-relative paths that work in RStudio & SLURM jobs on HiPerGator; anchors to project root automatically |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| stringr | 1.5.1+ | String operations | ICD code format normalization (remove dots: str_remove(dx, "\\.")); payer code prefix extraction |
| dplyr | 1.2.0+ | Data manipulation | Used minimally in Phase 1 for printing summaries; core tool for later phases |
| renv | 1.1.4+ | Package management | Project-local libraries with global cache; reproducibility on HiPerGator; renv.lock pins versions |
| purrr | 1.0.2+ | Iteration | map() for loading multiple CSV files with same col_types logic; cleaner than for loops |

**Version verification note:** All versions verified against CRAN as of 2026-03-24. readr 2.2.0 released Feb 2024, lubridate 1.9.3 released July 2023, janitor 2.2.1 released July 2025, glue 1.8.0 released July 2025, here 1.0.2 released Sept 2025, renv 1.1.4 released Jan 2026.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| readr::read_csv | data.table::fread | fread is 10-50x faster but returns data.table (different syntax); auto-detection can be dangerous for PCORnet CDM; readr is sufficient for cohort size |
| readr::read_csv | vroom::vroom | vroom is faster via lazy loading (Altrep) but can cause issues with some operations; readr is more conservative and reliable |
| janitor::convert_to_date | Custom parser | Manual parsing of DATE9/YYYYMMDD is error-prone; janitor handles edge cases (leap years, Excel 1900 bug) |
| Nested lists for config | YAML/JSON | YAML requires yaml package; JSON less readable for inline code vectors; R lists are native and version-controlled |
| renv | Docker/Singularity | Containers add complexity on HPC; renv integrates with module system; sufficient for R-only project |

**Installation:**
```r
# HiPerGator: module load R/4.4.2 first
install.packages("renv")
renv::init()
install.packages(c("readr", "lubridate", "janitor", "glue", "here", "stringr", "dplyr", "purrr"))
renv::snapshot()
```

## Architecture Patterns

### Recommended Project Structure
```
insurance_investigation/
├── R/
│   ├── 00_config.R                # Paths, ICD codes (149), payer mapping rules
│   ├── 01_load_pcornet.R          # Load 9 CSV tables into named list
│   ├── utils_dates.R              # parse_pcornet_date() multi-format parser
│   ├── utils_attrition.R          # init_attrition_log(), log_attrition()
│   └── [02-06 added in later phases]
├── output/
│   ├── figures/
│   ├── tables/
│   └── cohort/
├── .Rprofile                       # renv activation
├── renv.lock                       # Package versions
└── renv/                           # renv infrastructure
```

**Phase 1 creates:** R/00_config.R, R/01_load_pcornet.R, R/utils_dates.R, R/utils_attrition.R, output/ directories, .Rprofile, renv.lock

### Pattern 1: Configuration as Nested Lists

**What:** Define all configuration in a single R script (00_config.R) using nested named lists with clear section headers and inline comments. Config is loaded via `source("R/00_config.R")` in every analysis script.

**When to use:** When configuration needs to be human-readable and version-controlled. Essential for reproducible research where parameters (ICD code lists, file paths, analysis thresholds) must be transparent.

**Example:**
```r
# R/00_config.R

# ============================================================================
# Data Paths
# ============================================================================
CONFIG <- list(
  data_dir = "/orange/erin.mobley-hl.bcu/Mailhot_V1_20250915",
  project_dir = "/blue/erin.mobley-hl.bcu/R",
  output_dir = "output"
)

# ============================================================================
# PCORnet CDM Table Paths
# ============================================================================
PCORNET_PATHS <- list(
  ENROLLMENT = file.path(CONFIG$data_dir, "ENROLLMENT_Mailhot_V1.csv"),
  DIAGNOSIS  = file.path(CONFIG$data_dir, "DIAGNOSIS_Mailhot_V1.csv"),
  PROCEDURES = file.path(CONFIG$data_dir, "PROCEDURES_Mailhot_V1.csv"),
  PRESCRIBING = file.path(CONFIG$data_dir, "PRESCRIBING_Mailhot_V1.csv"),
  ENCOUNTER  = file.path(CONFIG$data_dir, "ENCOUNTER_Mailhot_V1.csv"),
  DEMOGRAPHIC = file.path(CONFIG$data_dir, "DEMOGRAPHIC_Mailhot_V1.csv"),
  TUMOR_REGISTRY1 = file.path(CONFIG$data_dir, "TUMOR_REGISTRY1_Mailhot_V1.csv"),
  TUMOR_REGISTRY2 = file.path(CONFIG$data_dir, "TUMOR_REGISTRY2_Mailhot_V1.csv"),
  TUMOR_REGISTRY3 = file.path(CONFIG$data_dir, "TUMOR_REGISTRY3_Mailhot_V1.csv")
)

# ============================================================================
# ICD Code Lists (Hodgkin Lymphoma)
# ============================================================================
# ICD-10-CM: C81.* codes (77 codes total)
ICD_CODES <- list(
  hl_icd10 = c(
    "C81.00", "C81.01", "C81.02", "C81.03", "C81.04", "C81.05", "C81.06",
    "C81.07", "C81.08", "C81.09",
    # ... [full 77 codes listed]
  ),

  # ICD-9-CM: 201.* codes (72 codes total)
  hl_icd9 = c(
    "201.00", "201.01", "201.02", "201.10", "201.11", "201.12",
    # ... [full 72 codes listed]
  )
)

# ============================================================================
# Payer Mapping Rules (applied in Phase 2)
# ============================================================================
PAYER_MAPPING <- list(
  medicare_prefix = "1",        # Codes starting with 1 (11, 12, 111, etc.)
  medicaid_prefix = "2",        # Codes starting with 2
  private_prefix = c("5", "6"), # Codes starting with 5 or 6
  other_gov_prefix = c("3", "4"), # Includes 41 (Corrections Federal)
  no_payment_prefix = "8",
  other_prefix = c("7", "9"),   # But not 99/9999
  unavailable_codes = c("99", "9999"),
  unknown_codes = c("NI", "UN", "OT", "UNKNOWN"),
  dual_eligible_codes = c("14", "141", "142") # Explicit dual-eligibility
)

# ============================================================================
# Analysis Parameters
# ============================================================================
CONFIG$analysis <- list(
  min_enrollment_days = 30,
  dx_window_days = 30,  # Window around diagnosis for payer lookup
  treatment_window_days = 30
)

# Auto-source utility functions so any script loading config gets them
source("R/utils_dates.R")
source("R/utils_attrition.R")
```

### Pattern 2: Explicit col_types Specification per Table

**What:** Define a named cols() object for each PCORnet table based on csv_columns.txt schema. Specify col_character() for IDs, col_date() for dates, col_integer() for counts, col_double() for continuous measures. Pass to read_csv(col_types = ...).

**When to use:** Always for clinical data. Auto-detection can silently truncate IDs with leading zeros, misparse dates, or convert coded values to wrong types. Explicit specification catches schema changes and prevents silent failures.

**Example:**
```r
# R/01_load_pcornet.R

# ENROLLMENT: 6 columns (ID, ENR_START_DATE, ENR_END_DATE, CHART, ENR_BASIS, SOURCE)
ENROLLMENT_SPEC <- cols(
  ID = col_character(),           # Patient identifier (not numeric; may have leading zeros)
  ENR_START_DATE = col_character(), # Dates loaded as character, parsed separately
  ENR_END_DATE = col_character(),
  CHART = col_character(),
  ENR_BASIS = col_character(),
  SOURCE = col_character()        # Site identifier (AMS, UMI, FLM, VRT)
)

# DIAGNOSIS: 14 columns
DIAGNOSIS_SPEC <- cols(
  DIAGNOSISID = col_character(),
  ID = col_character(),
  ENCOUNTERID = col_character(),
  ENC_TYPE = col_character(),
  ADMIT_DATE = col_character(),   # Multi-format dates; parse separately
  PROVIDERID = col_character(),
  DX = col_character(),           # ICD code (C81.00 or C8100 — both formats exist)
  DX_TYPE = col_character(),      # 09 or 10
  DX_DATE = col_character(),
  DX_SOURCE = col_character(),
  DX_ORIGIN = col_character(),
  PDX = col_character(),
  DX_POA = col_character(),
  SOURCE = col_character()
)

# ... [similar specs for PROCEDURES, PRESCRIBING, ENCOUNTER, DEMOGRAPHIC, TUMOR_REGISTRY1-3]

load_pcornet_table <- function(table_name, file_path, col_spec) {
  if (!file.exists(file_path)) {
    message(glue("WARNING: {table_name} not found at {file_path}. Skipping."))
    return(NULL)
  }

  df <- read_csv(file_path, col_types = col_spec, show_col_types = FALSE)

  # Parse all date columns with multi-format parser
  date_cols <- names(df)[str_detect(names(df), "DATE|TIME")]
  for (col in date_cols) {
    df[[col]] <- parse_pcornet_date(df[[col]])
  }

  message(glue("Loaded {table_name}: {nrow(df)} rows, {ncol(df)} columns"))
  if (length(problems(df)) > 0) {
    message(glue("  WARNING: {nrow(problems(df))} parse failures"))
  }

  return(df)
}
```

**Rationale:**
- Load all dates as character initially, then apply multi-format parser — readr's col_date() assumes single format
- Use col_character() for IDs and coded values — prevents numeric conversion truncation
- Explicit specs document expected schema — catches upstream changes in CSV generation
- Per D-10: warn and skip missing files, continue loading other tables

### Pattern 3: Multi-Format Date Parser with Fallback Chain

**What:** A utility function that tries multiple date format parsers in sequence (lubridate::ymd → lubridate::dmy → lubridate::parse_date_time with DATE9 order → janitor::excel_numeric_to_date), returning the first successful parse or NA with warning.

**When to use:** When loading dates from SAS exports or Excel, which can export the same date field in different formats across rows or across different SAS runs. Essential for PCORnet data where sites use different SAS configurations.

**Example:**
```r
# R/utils_dates.R

library(lubridate)
library(janitor)
library(stringr)

parse_pcornet_date <- function(date_char) {
  # Input: character vector of dates in various formats
  # Output: Date vector with NA for unparseable values

  if (all(is.na(date_char))) return(as.Date(rep(NA, length(date_char))))

  result <- rep(as.Date(NA), length(date_char))

  # Attempt 1: YYYY-MM-DD (ISO format, most common in recent exports)
  parsed <- suppressWarnings(ymd(date_char, quiet = TRUE))
  result[!is.na(parsed)] <- parsed[!is.na(parsed)]

  # Attempt 2: Excel serial numbers (numeric strings like "44562")
  remaining <- is.na(result) & !is.na(date_char)
  if (any(remaining)) {
    numeric_vals <- suppressWarnings(as.numeric(date_char[remaining]))
    valid_serial <- !is.na(numeric_vals) & numeric_vals > 1 & numeric_vals < 100000
    if (any(valid_serial)) {
      parsed_excel <- excel_numeric_to_date(numeric_vals[valid_serial])
      result[remaining][valid_serial] <- parsed_excel
    }
  }

  # Attempt 3: SAS DATE9 (DDMMMYYYY like 15JAN2020)
  remaining <- is.na(result) & !is.na(date_char)
  if (any(remaining)) {
    parsed_date9 <- suppressWarnings(
      parse_date_time(date_char[remaining], orders = "dby", quiet = TRUE)
    )
    result[remaining][!is.na(parsed_date9)] <- as.Date(parsed_date9[!is.na(parsed_date9)])
  }

  # Attempt 4: YYYYMMDD (compact format, no separators)
  remaining <- is.na(result) & !is.na(date_char)
  if (any(remaining)) {
    # Only try for 8-character strings
    eight_char <- str_length(date_char[remaining]) == 8
    if (any(eight_char)) {
      parsed_compact <- suppressWarnings(
        ymd(date_char[remaining][eight_char], quiet = TRUE)
      )
      result[remaining][eight_char][!is.na(parsed_compact)] <- parsed_compact[!is.na(parsed_compact)]
    }
  }

  # Log unparseable dates (but don't fail)
  unparsed_count <- sum(is.na(result) & !is.na(date_char))
  if (unparsed_count > 0) {
    unparsed_pct <- round(100 * unparsed_count / length(date_char), 1)
    message(glue("  WARNING: {unparsed_count} ({unparsed_pct}%) dates could not be parsed"))
  }

  return(result)
}
```

**Rationale:**
- SAS exports can produce YYYY-MM-DD, DDMMMYYYY (DATE9), YYYYMMDD, or Excel serial numbers depending on SAS PROC EXPORT settings
- Trying all formats with fallback ensures < 5% NA rate (per LOAD-02 requirement)
- excel_numeric_to_date handles Excel 1900 leap year bug automatically
- Logs unparseable count but doesn't fail — allows pipeline to continue with partial data per D-10

### Pattern 4: Attrition Logging Utilities

**What:** Two functions: init_attrition_log() creates an empty data frame with standardized columns (step, n_before, n_after, n_excluded, pct_excluded), and log_attrition(log_df, step_name, n_after) appends a new row with calculated exclusion statistics.

**When to use:** Required for all cohort-building analyses where inclusion/exclusion criteria must be documented for CONSORT diagrams or regulatory reporting. Called manually after each filter step (per D-16).

**Example:**
```r
# R/utils_attrition.R

library(dplyr)

init_attrition_log <- function() {
  data.frame(
    step = character(),
    n_before = integer(),
    n_after = integer(),
    n_excluded = integer(),
    pct_excluded = numeric(),
    stringsAsFactors = FALSE
  )
}

log_attrition <- function(log_df, step_name, n_after) {
  # Infer n_before from previous step's n_after (or use n_after if first step)
  if (nrow(log_df) > 0) {
    n_before <- tail(log_df$n_after, 1)
  } else {
    n_before <- n_after  # First step: no exclusions yet
  }

  n_excluded <- n_before - n_after
  pct_excluded <- if (n_before > 0) round(100 * n_excluded / n_before, 1) else 0

  new_row <- data.frame(
    step = step_name,
    n_before = n_before,
    n_after = n_after,
    n_excluded = n_excluded,
    pct_excluded = pct_excluded,
    stringsAsFactors = FALSE
  )

  rbind(log_df, new_row)
}
```

**Usage in Phase 3 (cohort building):**
```r
source("R/00_config.R")  # Auto-loads utils_attrition.R

attrition_log <- init_attrition_log()
cohort_ids <- pcornet$ENROLLMENT %>% pull(ID) %>% unique()
attrition_log <- log_attrition(attrition_log, "Initial cohort", length(cohort_ids))

# After applying filter:
cohort_ids <- cohort_ids[cohort_ids %in% hl_patient_ids]
attrition_log <- log_attrition(attrition_log, "Has Hodgkin lymphoma diagnosis", length(cohort_ids))
```

**Rationale:**
- Patient-level counts (unique ID count) not row-level (per D-17) — clinically meaningful
- Percentage excluded calculated automatically (per D-18) — ready for waterfall labels
- Manual calls give user control over step granularity (per D-16) — not all filters need logging
- Simple data frame structure — easy to export to CSV or pass to ggplot2

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Multi-format date parsing | Custom regex/strptime chains | janitor::convert_to_date or lubridate::parse_date_time | Edge cases: leap years, month abbreviations in different locales, Excel 1900 bug, timezone ambiguity. janitor handles these. |
| CSV loading with type inference | Custom read.table wrappers | readr::read_csv with explicit col_types | readr handles: quoted commas, embedded newlines, different encodings, parse failure reporting. Manual parsing misses edge cases. |
| Project-relative paths | paste0() with getwd() | here::here() | Working directory changes in SLURM jobs vs. RStudio. here() anchors to project root via .Rproj or .here file automatically. |
| Package version management | Manual install.packages() + documentation | renv | Reproducibility across machines requires exact versions. renv::restore() recreates environment; manual tracking fails when packages update. |
| String interpolation | paste0() or sprintf() | glue::glue() | Readable logs: `glue("Loaded {nrow(df)} rows")` vs. `paste0("Loaded ", nrow(df), " rows")`. glue evaluates expressions in {}. |

**Key insight:** Date parsing is the highest-risk area for custom code. SAS DATE9 format has month abbreviations (JAN, FEB, ...) that are locale-dependent. Excel serial dates have a known bug (treats 1900 as a leap year). lubridate and janitor handle these; custom code usually doesn't test all edge cases.

## Common Pitfalls

### Pitfall 1: Auto-Detection of Column Types Causes Silent ID Truncation

**What goes wrong:** Loading ENROLLMENT with `read_csv(file, col_types = cols())` (auto-detect all) can infer `ID` column as numeric, truncating leading zeros. Patient "00012345" becomes 12345, breaking joins across tables.

**Why it happens:** readr scans first 1000 rows by default (guess_max). If no IDs in first 1000 have leading zeros, it guesses numeric. Later rows with leading zeros lose precision.

**How to avoid:** Always specify col_character() for ID fields in PCORnet CDM. Per D-11, patient identifier is `ID` (not PATID). Explicit specification:
```r
ENROLLMENT_SPEC <- cols(
  ID = col_character(),  # CRITICAL: never let readr infer this as numeric
  # ... other columns
)
```

**Warning signs:** Join between ENROLLMENT and DIAGNOSIS returns fewer rows than expected. Some IDs appear in one table but not another. `n_distinct(enrollment$ID) != n_distinct(diagnosis$ID)` when should be equal.

### Pitfall 2: Date Format Mixing Within a Single Column

**What goes wrong:** ADMISSION_DATE column contains mix of "2023-01-15" (ISO) and "15JAN2023" (DATE9) and "44928" (Excel serial). Single lubridate::ymd() call only parses ISO format, returning NA for others. Pipeline continues with 60% NA dates, silently losing data.

**Why it happens:** PCORnet sites use different SAS configurations. Some export DATE9, some ISO. If data aggregated from multiple sites or multiple export runs, same column can have mixed formats. SAS PROC EXPORT behavior varies by version and site configuration.

**How to avoid:** Use parse_pcornet_date() utility with fallback chain (Pattern 3). Try each format in sequence, keeping first successful parse. Log unparseable count but don't fail.

**Warning signs:** `summary(df$DATE_COLUMN)` shows > 10% NA values. `table(is.na(df$DATE_COLUMN))` shows thousands of NAs. First 100 rows parse fine, but row 1001+ fail (different site or export run).

### Pitfall 3: Missing CSV Files Break Entire Pipeline

**What goes wrong:** HiPerGator path typo or missing TUMOR_REGISTRY3 file causes `read_csv()` to throw error, stopping entire load. Pipeline fails even though only 1 of 22 tables missing, and analysis could proceed with partial data.

**Why it happens:** readr::read_csv() errors if file not found. Default behavior is to halt execution. For exploratory analysis, partial data is often acceptable (e.g., can build cohort from ENROLLMENT + DIAGNOSIS even if TUMOR_REGISTRY tables missing).

**How to avoid:** Wrap read_csv() in file.exists() check (per D-10). Log warning, return NULL, continue loading other tables. Store in named list; downstream code checks for NULL before using table.

```r
load_pcornet_table <- function(table_name, file_path, col_spec) {
  if (!file.exists(file_path)) {
    message(glue("WARNING: {table_name} not found at {file_path}. Skipping."))
    return(NULL)
  }
  read_csv(file_path, col_types = col_spec)
}

pcornet <- list(
  ENROLLMENT = load_pcornet_table("ENROLLMENT", PCORNET_PATHS$ENROLLMENT, ENROLLMENT_SPEC),
  DIAGNOSIS  = load_pcornet_table("DIAGNOSIS", PCORNET_PATHS$DIAGNOSIS, DIAGNOSIS_SPEC)
  # ... others
)

# Downstream usage:
if (!is.null(pcornet$TUMOR_REGISTRY1)) {
  # Use TUMOR_REGISTRY1 data
} else {
  message("Skipping TUMOR_REGISTRY-based analysis (file not loaded)")
}
```

**Warning signs:** `Error: 'path/to/file.csv' does not exist` in RStudio console. Entire pipeline halts on first missing table. Output directory empty even though earlier tables loaded successfully.

### Pitfall 4: renv Cache Fills HiPerGator Home Quota

**What goes wrong:** renv installs packages to project-local library (~/.cache/R/renv by default). Installing tidyverse + dependencies uses 2-3 GB. After multiple projects, cache exceeds HiPerGator home directory quota (5 GB default), causing all R operations to fail with "disk quota exceeded."

**Why it happens:** renv caches all package versions ever installed across all projects. HiPerGator home directory has strict quota. Multiple users on shared HPC often hit this.

**How to avoid:** Move renv cache to /blue or /orange (higher quota). Set RENV_PATHS_CACHE environment variable before renv::init():

```r
# In .Rprofile or before renv::init():
Sys.setenv(RENV_PATHS_CACHE = "/blue/erin.mobley-hl.bcu/R/renv_cache")
renv::init()
```

Alternatively, use HiPerGator's preinstalled R modules and only use renv for project-specific packages (not entire tidyverse).

**Warning signs:** `Error: cannot allocate vector` or `disk quota exceeded` during package installation. `du -sh ~/.cache/R/renv` shows multi-GB cache. HiPerGator quota warning emails.

### Pitfall 5: ICD Code Matching Misses Dotted vs. Undotted Formats

**What goes wrong:** ICD-10 code C81.00 stored in two formats across sites: "C81.00" (dotted) and "C8100" (undotted). Filter `DX %in% c("C81.00", "C81.01", ...)` only matches dotted format, missing half of HL patients.

**Why it happens:** PCORnet CDM specification allows either format. Different sites follow different conventions. No normalization at data ingest. Diagnosis table has both formats mixed.

**How to avoid:** Normalize ICD codes by removing dots before matching. Use stringr::str_remove():

```r
# In cohort predicate function:
diagnosis_normalized <- diagnosis %>%
  mutate(DX_CLEAN = str_remove(DX, "\\."))  # Remove all dots

hl_icd10_normalized <- str_remove(ICD_CODES$hl_icd10, "\\.")  # C81.00 -> C8100

hl_patients <- diagnosis_normalized %>%
  filter(DX_CLEAN %in% hl_icd10_normalized) %>%
  pull(ID) %>%
  unique()
```

**Warning signs:** Cohort size unexpectedly small (hundreds instead of thousands). `table(str_detect(diagnosis$DX, "\\."))` shows mix of TRUE/FALSE (some codes have dots, some don't). Manual inspection of DIAGNOSIS table shows both "C81.00" and "C8100" present.

### Pitfall 6: Large Col_types Specifications are Repetitive and Error-Prone

**What goes wrong:** Manually writing cols() specification for TUMOR_REGISTRY1 (314 columns) leads to copy-paste errors. Missing columns or wrong types go undetected until analysis phase.

**Why it happens:** PCORnet tables have 6-314 columns. Writing col_character() 314 times is tedious. Temptation to use auto-detection or copy-paste-edit from another table.

**How to avoid:** For large tables, start with cols(.default = col_character()) (safe default), then override specific columns known to be numeric/integer:

```r
TUMOR_REGISTRY1_SPEC <- cols(
  .default = col_character(),  # Safe default for all columns
  # Override specific numeric columns if needed for performance:
  AGE_AT_DIAGNOSIS = col_integer(),
  TUMOR_SIZE_SUMMARY = col_double()
)
```

For date columns, still load as character and parse separately (multi-format issue). For IDs and coded values, col_character() is always correct.

**Warning signs:** readr throws "New names" warning (duplicate column names after auto-rename). cols() specification has 50 lines of repetitive col_character(). Copy-paste error causes column N to get spec for column N-1.

## Code Examples

Verified patterns from research and architecture:

### Load Single Table with Explicit Types and Multi-Format Date Parsing

```r
# Source: readr documentation + janitor vignette + Architecture research

library(readr)
library(glue)
source("R/00_config.R")  # Loads utils_dates.R automatically

# Define column specification
ENROLLMENT_SPEC <- cols(
  ID = col_character(),
  ENR_START_DATE = col_character(),  # Load as character, parse separately
  ENR_END_DATE = col_character(),
  CHART = col_character(),
  ENR_BASIS = col_character(),
  SOURCE = col_character()
)

# Load with explicit types
enrollment <- read_csv(
  PCORNET_PATHS$ENROLLMENT,
  col_types = ENROLLMENT_SPEC,
  show_col_types = FALSE
)

# Parse date columns with multi-format parser
enrollment <- enrollment %>%
  mutate(
    ENR_START_DATE = parse_pcornet_date(ENR_START_DATE),
    ENR_END_DATE = parse_pcornet_date(ENR_END_DATE)
  )

# Print load summary
message(glue("Loaded ENROLLMENT: {nrow(enrollment)} rows, {ncol(enrollment)} columns"))
if (nrow(problems(enrollment)) > 0) {
  message(glue("  WARNING: {nrow(problems(enrollment))} parse failures"))
  print(problems(enrollment))
}
```

### Load All Tables into Named List

```r
# Source: Architecture research Pattern 1 + purrr map pattern

library(purrr)

# Define specs for all tables (example shows 2)
table_specs <- list(
  ENROLLMENT = ENROLLMENT_SPEC,
  DIAGNOSIS = DIAGNOSIS_SPEC
  # ... add all 9 tables
)

# Load all tables
pcornet <- imap(PCORNET_PATHS, function(path, table_name) {
  if (!file.exists(path)) {
    message(glue("WARNING: {table_name} not found at {path}. Skipping."))
    return(NULL)
  }

  spec <- table_specs[[table_name]]
  df <- read_csv(path, col_types = spec, show_col_types = FALSE)

  # Parse all date columns
  date_cols <- names(df)[str_detect(names(df), "DATE|TIME")]
  for (col in date_cols) {
    df[[col]] <- parse_pcornet_date(df[[col]])
  }

  message(glue("Loaded {table_name}: {nrow(df)} rows, {ncol(df)} columns"))
  df
})

# Access tables:
# pcornet$ENROLLMENT
# pcornet$DIAGNOSIS
```

### Attrition Logging Example

```r
# Source: Architecture research Pattern 4

source("R/00_config.R")  # Auto-loads utils_attrition.R

# Initialize log
attrition_log <- init_attrition_log()

# Log initial cohort
all_patient_ids <- pcornet$ENROLLMENT %>% pull(ID) %>% unique()
attrition_log <- log_attrition(attrition_log, "Initial cohort", length(all_patient_ids))

# Apply filter and log
hl_patient_ids <- pcornet$DIAGNOSIS %>%
  filter(str_remove(DX, "\\.") %in% str_remove(ICD_CODES$hl_icd10, "\\.")) %>%
  pull(ID) %>%
  unique()

cohort_ids <- all_patient_ids[all_patient_ids %in% hl_patient_ids]
attrition_log <- log_attrition(attrition_log, "Has Hodgkin lymphoma diagnosis", length(cohort_ids))

# Print log
print(attrition_log)
#   step                              n_before n_after n_excluded pct_excluded
# 1 Initial cohort                    12543    12543   0          0.0
# 2 Has Hodgkin lymphoma diagnosis    12543    1847    10696      85.3
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| base::read.csv() | readr::read_csv() | 2015 (readr 0.1.0) | Faster parsing, better type inference, tibble output, progress bars |
| strptime() for dates | lubridate::ymd/dmy/mdy | 2011 (lubridate 1.0.0) | No need for format strings, automatic separator handling |
| Manual renv cache in home | RENV_PATHS_CACHE to /blue or /orange | 2021 (HPC quota issues) | Avoids home directory quota on HPC systems |
| Auto-detect all types | Explicit col_types for clinical data | Ongoing best practice | Prevents silent ID truncation, date misparsing |
| Single-format date parser | Multi-format with fallback | Required for PCORnet/SAS exports | Handles mixed SAS DATE9/ISO/Excel serial in same column |

**Deprecated/outdated:**
- **read.table/read.csv with stringsAsFactors = TRUE:** Default changed to FALSE in R 4.0.0 (2020). Old code may have unexpected factor conversions.
- **lubridate::parse_date_time with select_formats = TRUE:** Deprecated in lubridate 1.7.0 (2018). Use `orders` argument instead.
- **renv::init() without cache configuration on HPC:** Works until cache fills quota. Now best practice to set RENV_PATHS_CACHE first.

## Open Questions

1. **Excel Serial Date Detection**
   - What we know: janitor::excel_numeric_to_date converts serial numbers. Valid range is ~1-100,000 (1900-2200).
   - What's unclear: Can we distinguish Excel serial dates from other numeric codes in PCORnet? E.g., is "44928" a date or an encounter ID? csv_columns.txt doesn't show pure numeric date columns.
   - Recommendation: Include Excel serial parsing in fallback chain with range check (1 < x < 100000). If it triggers on non-date columns, remove from parser. Test with sample data first.

2. **TUMOR_REGISTRY1-3 Column Differences**
   - What we know: csv_columns.txt shows TUMOR_REGISTRY1 has 314 columns, TR2/TR3 have 140 columns each. TR1 is full NAACCR spec, TR2/TR3 are subsets.
   - What's unclear: Do TR2/TR3 column names match subset of TR1 names exactly, or are they different schemas? Can we reuse col_types?
   - Recommendation: Define separate col_types for TR2/TR3. Use cols(.default = col_character()) for all three given size. Validate column overlap after loading.

3. **Parse Failure Threshold**
   - What we know: LOAD-02 requires < 5% NA rate for date parsing. Some unparseable dates are expected (missing data, sentinel values like "UN").
   - What's unclear: Should pipeline fail if > 5% unparseable, or just warn? What if one table has 10% unparseable but others are fine?
   - Recommendation: Warn on > 5% per-table but don't fail. Log to file for review. Phase 4 (visualization) can assess impact. Consider data quality report in Phase 2.

## Validation Architecture

> nyquist_validation is explicitly disabled in .planning/config.json — skipping this section per instructions.

## Sources

### Primary (HIGH confidence)
- [readr::read_csv documentation](https://readr.tidyverse.org/reference/read_delim.html) - col_types specification
- [readr column types vignette](https://readr.tidyverse.org/articles/column-types.html) - cols() specification examples
- [readr::cols documentation](https://readr.tidyverse.org/reference/cols.html) - col_character(), col_date(), col_integer()
- [lubridate date parsing](https://lubridate.tidyverse.org/reference/parse_date_time.html) - parse_date_time orders parameter
- [janitor::excel_numeric_to_date](https://rdrr.io/cran/janitor/man/excel_numeric_to_date.html) - Excel serial date conversion
- [janitor::convert_to_date](https://search.r-project.org/CRAN/refmans/janitor/html/convert_to_date.html) - Mixed format date conversion
- [renv documentation](https://rstudio.github.io/renv/) - Project environments
- [CRAN renv package](https://cran.r-project.org/package=renv) - Version 1.1.4 (Jan 2026)
- [renv on HPC](https://bioinformatics.ccr.cancer.gov/docs/reproducible-r-on-biowulf/L3_PackageManagement/) - Biowulf HPC renv guide
- [glue package](https://glue.tidyverse.org/) - String interpolation
- [here package](https://here.r-lib.org/) - Project-relative paths
- [PCORnet CDM v7.0 Specification PDF](https://pcornet.org/wp-content/uploads/2025/01/PCORnet-Common-Data-Model-v70-2025_01_23.pdf) - Official schema

### Secondary (MEDIUM confidence)
- [R for Data Science: Data Import](https://r4ds.had.co.nz/data-import.html) - readr best practices
- [Date handling in R](https://bookdown.org/hcwatt99/Data_Wrangling_Recipes_in_R/chDate.html) - Multi-format date parsing
- [Converting Excel dates in R](https://www.statology.org/convert-excel-date-to-date-in-r/) - Excel serial date examples
- [Managing lists in R](http://uc-r.github.io/lists) - Nested list structure patterns
- [readr parse failures](https://readr.tidyverse.org/reference/problems.html) - problems() function
- [cohortBuilder attrition](https://rdrr.io/cran/cohortBuilder/man/attrition.html) - Cohort attrition patterns
- [visR get_attrition](https://rdrr.io/cran/visR/man/get_attrition.html) - Clinical attrition table generation

### Tertiary (LOW confidence)
- WebSearch results for "ICD-10 code matching dotted undotted" - No specific R stringr solution found; recommendation based on architecture research str_remove pattern

## Metadata

**Confidence breakdown:**
- Standard stack (readr, lubridate, janitor, renv): **HIGH** - Official CRAN packages, versions verified, extensive documentation, used in architecture research
- Multi-format date parsing: **HIGH** - janitor::convert_to_date documented for this exact use case; architecture research confirms pattern
- col_types specification: **HIGH** - readr documentation complete; csv_columns.txt provides exact schema
- Attrition logging pattern: **MEDIUM** - Pattern from architecture research; no single canonical package (visR, cohortBuilder, dtrackr all have variants)
- renv on HiPerGator: **HIGH** - Biowulf/NIH HPC documentation confirms cache location pattern; similar architecture to HiPerGator
- ICD code normalization: **MEDIUM** - stringr::str_remove pattern confirmed in architecture, but no PCORnet-specific documentation found

**Research date:** 2026-03-24
**Valid until:** 30 days for R package versions (stable ecosystem), 90 days for architecture patterns

**CSV schema confidence:** HIGH - csv_columns.txt is project artifact from actual HiPerGator data extract (Mailhot_V1_20250915), not hypothetical

**Date format confidence:** MEDIUM - SAS DATE9/YYYYMMDD/ISO formats documented in SAS/R conversion guides, but specific mix in this dataset unknown until loading attempted. Excel serial dates may not be present (none visible in csv_columns.txt column names).
