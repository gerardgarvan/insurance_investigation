# Phase 6: Use Debug Output to Rectify Issues - Research

**Researched:** 2026-03-25
**Domain:** Data quality remediation and iterative debugging in R pipelines
**Confidence:** HIGH

## Summary

This phase focuses on using diagnostic output to drive targeted fixes across the R pipeline. The domain is **data-driven remediation**: reading diagnostic CSVs from 07_diagnostics.R, identifying root causes, writing targeted fixes to existing scripts, and iterating until all issues are resolved or explained.

Unlike exploratory phases, this is a structured remediation workflow with clear inputs (diagnostic CSVs), clear outputs (fixed pipeline scripts + data quality summary), and clear iteration criteria (all unexplained issues resolved). The standard approach uses R's existing utilities (lubridate for date parsing, readr col_types for type specification, stringr for regex), validation packages for complex rules (pointblank, assertr), and manual audit trails (CSV tracking files).

**Primary recommendation:** Fix issues directly in existing pipeline scripts (not separate fix scripts). Group fixes by issue type (date, type, payer, exclusion). Validate with targeted checks after each batch, then full diagnostic re-run. Document resolution status in data_quality_summary.csv with issue_type, count_before, count_after, status (fixed/accepted/documented), and notes.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Fix everything fixable in code -- any issue that CAN be fixed should be. Only document truly unfixable data-level problems.
- **D-02:** Patients with "Neither" HL source (no evidence in DIAGNOSIS or TUMOR_REGISTRY) are flagged and excluded from the final cohort. Write excluded patients to `output/cohort/excluded_no_hl_evidence.csv` with ID, SOURCE, and reason.
- **D-03:** Expand the date parser (utils_dates.R) to handle new date formats discovered by diagnostics. Goal: minimize character-type date columns.
- **D-04:** Document R vs Python payer mapping differences side-by-side. Exact parity not required -- the comparison should be visible but the R pipeline is exploratory.
- **D-05:** Update col_types specs in 01_load_pcornet.R for ALL columns flagged by the TUMOR_REGISTRY type audit (not just pipeline-critical ones). More accurate types = better data quality.
- **D-06:** Encoding issues (non-ASCII, BOM) -- flag only, do not strip during load. Document in diagnostics output.
- **D-07:** Expand the date column detection regex in 01_load_pcornet.R to catch any date columns missed per csv_columns.txt audit.
- **D-08:** Numeric range issues (negative ages, extreme sizes, pre-1900 dates) -- add validation columns (e.g., AGE_VALID = TRUE/FALSE) but preserve original raw values.
- **D-09:** For columns with >50% missing, investigate whether it's a loading/parsing issue vs. genuinely absent data. Fix if parsing issue; document if genuinely absent.
- **D-10:** All fixes go directly into existing pipeline scripts (00_config.R, 01_load_pcornet.R, utils_dates.R, 03_cohort_predicates.R, etc.). No separate fix script.
- **D-11:** Fixes are data-driven: user runs 07_diagnostics.R on HiPerGator first, shares diagnostic CSV files AND sample raw data rows, then Claude writes targeted fixes based on actual findings.
- **D-12:** Iterate until clean -- multiple rounds of diagnostics -> fixes -> re-run diagnostics until all remaining issues are explained.
- **D-13:** Fixes are grouped by issue type (all date fixes together, all col_type fixes together, all payer fixes together) for easier debugging.
- **D-14:** Targeted checks after each fix batch, then one full 07_diagnostics.R re-run at the end to confirm everything.
- **D-15:** The full diagnostics script runs fast enough on HiPerGator -- no need for section-level flags.
- **D-16:** "Clean enough" = all remaining issues in the final diagnostic output have an explanation (e.g., "X dates NA because field is optional per PCORnet CDM spec"). No unexplained anomalies.
- **D-17:** Final validation produces a CSV summary (output/diagnostics/data_quality_summary.csv) with columns: issue_type, count_before, count_after, status (fixed/accepted/documented), notes.
- **D-18:** Full end-to-end pipeline rebuild after all fixes: 00_config -> 01_load -> 02_harmonize -> 03_predicates -> 04_build -> 05_waterfall -> 06_sankey. All outputs (cohort CSV, waterfall PNG, sankey PNG) regenerated.
- **D-19:** Update 07_diagnostics.R if fixes change column names, table structures, or detection logic. Diagnostic script must reflect current pipeline state.
- **D-20:** Rebuilt cohort CSV includes an HL_SOURCE column showing how each patient was identified ('DIAGNOSIS only', 'TR only', 'Both'). Useful for downstream stratification.

### Claude's Discretion
- Specific date format patterns to add to parse_pcornet_date() (depends on what diagnostics reveal)
- Which col_types to change for TUMOR_REGISTRY columns (depends on type audit output)
- Exact regex additions for date column detection (depends on csv_columns.txt audit)
- Plausible numeric ranges for validation columns (standard clinical ranges)
- Structure of the data quality summary CSV
- How to implement HL_SOURCE column in the cohort build pipeline

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

## Standard Stack

### Core Libraries (Already in Use)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| lubridate | 1.9.3+ | Date parsing with multi-format fallback | Built-in fallback: when multiple formats supplied, applied in turn till success. parse_date_time() supports heterogeneous formats with training-based format guessing |
| readr | 2.2.0+ | CSV loading with col_types specification | Mature explicit type specification; best practice: supply explicit col_types as project matures past exploratory phase. Use spec() to retrieve guessed specification, then tweak |
| stringr | 1.5.1+ | Regex pattern matching for column detection | str_detect() + where() represents 2026 best practice; superior readability and tidyverse integration over grepl() |
| dplyr | 1.2.0+ | Data filtering and transformation | filter(if_any(...)), filter(if_all(...)) for multi-column conditions (R 4.4+ tidyverse 2025-2026 features) |
| glue | 1.8.0 | Readable logging messages | Essential for data_quality_summary.csv notes field and console logging |

### Validation Libraries (Optional but Recommended)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| pointblank | 0.12.3+ | Declarative data validation framework | Complex validation rules (numeric range checks, cross-column dependencies). Two workflows: quality reporting + pipeline validations. Works with data frames or database tables |
| assertr | Latest | Assertion-based validation | Inline pipeline checks using verify(), assert(), insist() verbs. Focused on data frames. Use tidyeval framework. Good for "fail fast" validation |
| dlookr | Latest | Automated data quality diagnosis | Out-of-box diagnosis reports. Overkill for this phase (07_diagnostics.R already exists), but useful reference for quality metric patterns |

**Installation:**
```bash
# All core libraries already installed via renv in Phase 1
# Optional validation libraries (if needed):
# In R console on HiPerGator:
renv::install("pointblank")
renv::install("assertr")
renv::snapshot()
```

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Manual validation (current) | pointblank automated validation | pointblank adds structure for complex rules but overkill for simple fixes. Defer to v2 unless validation complexity explodes |
| lubridate fallback chain | Base R strptime with tryCatch | lubridate parse_date_time() already optimized for numeric formats (drops into fast_strptime()). Base R adds no value |
| readr col_types | vroom col_types | vroom and readr use identical col_types syntax. Already using vroom in STACK.md, so no change needed |
| Manual regex testing | Unit tests (testthat) | Out of scope per REQUIREMENTS.md. Manual validation via diagnostics CSV sufficient for v1 |

## Architecture Patterns

### 1. Data-Driven Remediation Workflow

**Pattern:** Diagnostic output → Human analysis → Targeted fix → Validation → Iterate

```
┌─────────────────────┐
│ User runs           │
│ 07_diagnostics.R    │──► Produces 11 diagnostic CSVs
│ on HiPerGator       │    in output/diagnostics/
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│ User shares:        │
│ - Diagnostic CSVs   │
│ - Sample raw rows   │──► Context for Claude
│ - Console output    │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│ Claude analyzes     │
│ root cause and      │──► Writes targeted fixes
│ writes fix batch    │    to existing scripts
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│ User applies fix,   │
│ re-runs targeted    │──► Verifies fix worked
│ check or full diag  │
└─────────────────────┘
         │
         ▼
      Repeat until all issues resolved or explained
```

**Critical:** Each iteration MUST include before/after counts to track progress. Use message() logging for console visibility and CSV tracking for audit trail.

### 2. Fix Grouping by Issue Type (D-13)

**Anti-pattern:** Fixing date parsing, then payer mapping, then column types in random order creates debugging chaos.

**Pattern:** Batch fixes by issue type for isolation and debugging:

```
Batch 1: Date parsing expansion
  - R/utils_dates.R: Add new format handlers to parse_pcornet_date()
  - Validate: Re-run diagnostics Section 1 only (date_parsing_failures.csv)

Batch 2: Column type corrections
  - R/01_load_pcornet.R: Update TABLE_SPECS for flagged TUMOR_REGISTRY columns
  - Validate: Re-run diagnostics Section 3 (tr_type_audit.csv, column_discrepancies.csv)

Batch 3: Date column detection regex
  - R/01_load_pcornet.R: Expand date_regex pattern based on csv_columns.txt audit
  - Validate: Re-run diagnostics Section 2 (date_column_regex_audit.csv)

Batch 4: Payer mapping alignment
  - R/00_config.R: Document R vs Python differences in comments
  - Validate: Re-run diagnostics Section 5 (payer_mapping_audit.csv)

Batch 5: HL source tracking and exclusion
  - R/03_cohort_predicates.R: Track HL_SOURCE in has_hodgkin_diagnosis()
  - R/04_build_cohort.R: Add HL_SOURCE column, write excluded_no_hl_evidence.csv
  - Validate: Re-run diagnostics Section 4 (hl_identification_venn.csv)

Batch 6: Numeric range validation
  - Add validation columns (AGE_VALID, SIZE_VALID, DATE_VALID) but preserve raw values
  - Validate: Re-run diagnostics Section 6 (numeric_range_issues.csv)

Final: Full pipeline rebuild
  - Run all scripts 00 through 06
  - Generate data_quality_summary.csv
```

**Why this order:** Date parsing first (affects downstream type inference), then column types (affects numeric ranges), then domain-specific fixes (payer, HL source), then validation flags last.

### 3. Expanding Date Parser (D-03)

**Current implementation (utils_dates.R):**
```r
parse_pcornet_date <- function(date_char) {
  # Attempt 1: YYYY-MM-DD (ISO)
  # Attempt 2: Excel serial numbers (numeric 1-100000)
  # Attempt 3: SAS DATE9 (DDMMMYYYY)
  # Attempt 4: YYYYMMDD (compact)
  # Log unparsed count
}
```

**Expansion strategy based on diagnostic output:**

User shares `date_parsing_failures.csv` with sample_raw_values column. Analyze samples to identify patterns:

```r
# Example new patterns to add (hypothetical until diagnostics run):

# Attempt 5: MM/DD/YYYY (US format with slashes)
remaining <- is.na(result) & !is.na(date_char)
if (any(remaining)) {
  parsed_mdy <- suppressWarnings(mdy(date_char[remaining], quiet = TRUE))
  if (any(!is.na(parsed_mdy))) {
    idx_in_remaining <- which(remaining)[!is.na(parsed_mdy)]
    result[idx_in_remaining] <- parsed_mdy[!is.na(parsed_mdy)]
  }
}

# Attempt 6: DD/MM/YYYY (European format)
remaining <- is.na(result) & !is.na(date_char)
if (any(remaining)) {
  parsed_dmy <- suppressWarnings(dmy(date_char[remaining], quiet = TRUE))
  if (any(!is.na(parsed_dmy))) {
    idx_in_remaining <- which(remaining)[!is.na(parsed_dmy)]
    result[idx_in_remaining] <- parsed_dmy[!is.na(parsed_dmy)]
  }
}

# Attempt 7: SAS numeric (days since 1960-01-01)
# Check for numeric values > 100000 (outside Excel range)
remaining <- is.na(result) & !is.na(date_char)
if (any(remaining)) {
  numeric_vals <- suppressWarnings(as.numeric(date_char[remaining]))
  # Valid SAS date: 0 (1960-01-01) to ~30000 (2042)
  valid_sas <- !is.na(numeric_vals) & numeric_vals >= 0 & numeric_vals < 50000 & numeric_vals >= 100000
  if (any(valid_sas)) {
    parsed_sas <- as.Date("1960-01-01") + numeric_vals[valid_sas]
    idx_in_remaining <- which(remaining)[valid_sas]
    result[idx_in_remaining] <- parsed_sas
  }
}
```

**Key principle:** Add formats in order of likelihood (based on sample_raw_values frequency). Always use suppressWarnings() to avoid console spam. Always validate idx_in_remaining to avoid index errors.

### 4. Expanding Date Column Detection Regex (D-07)

**Current regex (01_load_pcornet.R line 231):**
```r
date_regex <- "(?i)(DATE|^DT_|^BDATE$|^DOD$|^DT_FU$|DXDATE|_DT$|RECUR_DT|COMBINED_LAST_CONTACT|ADDRESS_PERIOD_START|ADDRESS_PERIOD_END)"
```

**Expansion strategy based on date_column_regex_audit.csv:**

User shares audit CSV showing columns that didn't match. Look for patterns in unmatched columns with "potentially missed" flag:

```r
# Example additions (hypothetical until diagnostics run):

# If audit shows columns like BIRTH_TIME, RX_ORDER_TIME, etc. not matching:
date_regex <- "(?i)(DATE|TIME|^DT_|^BDATE$|^DOD$|^DT_FU$|DXDATE|_DT$|RECUR_DT|COMBINED_LAST_CONTACT|ADDRESS_PERIOD_START|ADDRESS_PERIOD_END)"

# If audit shows YEAR columns (e.g., YEAR_OF_DIAGNOSIS):
date_regex <- "(?i)(DATE|TIME|YEAR|^DT_|^BDATE$|^DOD$|^DT_FU$|DXDATE|_DT$|RECUR_DT|COMBINED_LAST_CONTACT|ADDRESS_PERIOD_START|ADDRESS_PERIOD_END)"

# If audit shows PERIOD columns not already covered:
date_regex <- "(?i)(DATE|TIME|YEAR|PERIOD|^DT_|^BDATE$|^DOD$|^DT_FU$|DXDATE|_DT$|RECUR_DT|COMBINED_LAST_CONTACT)"
```

**Best practice (from 2026 tidyverse research):** Use str_detect() with regex() for clarity:
```r
# In load_pcornet_table():
date_cols <- names(df)[str_detect(names(df), regex(date_regex, ignore_case = TRUE))]
```

Current implementation already uses `(?i)` for case-insensitivity, which is fine. But if pattern grows complex, consider extracting to separate object:

```r
DATE_COLUMN_PATTERN <- regex(
  "(DATE|TIME|YEAR|PERIOD|^DT_|^BDATE$|^DOD$|^DT_FU$|DXDATE|_DT$|RECUR_DT|COMBINED_LAST_CONTACT|ADDRESS_PERIOD_START|ADDRESS_PERIOD_END)",
  ignore_case = TRUE
)

date_cols <- names(df)[str_detect(names(df), DATE_COLUMN_PATTERN)]
```

### 5. Updating col_types for TUMOR_REGISTRY Columns (D-05)

**Current specs (01_load_pcornet.R lines 154-180):**
```r
TUMOR_REGISTRY1_SPEC <- cols(
  .default = col_character(),
  AGE_AT_DIAGNOSIS = col_integer(),
  TUMOR_SIZE_SUMMARY = col_double(),
  TUMOR_SIZE_CLINICAL = col_double(),
  TUMOR_SIZE_PATHOLOGIC = col_double()
)
```

**Update strategy based on tr_type_audit.csv:**

Audit CSV contains: table, column, current_type, pct_numeric, pct_datelike, recommendation

```r
# Example fix (hypothetical until diagnostics run):
# If tr_type_audit.csv shows:
#   TUMOR_REGISTRY1, DXDATE_FLAG, character, 95%, 0%, "Consider col_double()"
#   TUMOR_REGISTRY1, STAGE_CLINICAL, character, 90%, 0%, "Consider col_double()"

TUMOR_REGISTRY1_SPEC <- cols(
  .default = col_character(),
  AGE_AT_DIAGNOSIS = col_integer(),
  TUMOR_SIZE_SUMMARY = col_double(),
  TUMOR_SIZE_CLINICAL = col_double(),
  TUMOR_SIZE_PATHOLOGIC = col_double(),
  DXDATE_FLAG = col_double(),          # NEW: per tr_type_audit.csv
  STAGE_CLINICAL = col_double()        # NEW: per tr_type_audit.csv
)

# If audit shows date-like columns (pct_datelike > 80):
#   TUMOR_REGISTRY2, RECUR_DT, character, 0%, 85%, "Consider col_date()"

TUMOR_REGISTRY2_SPEC <- cols(
  .default = col_character(),
  DXAGE = col_integer(),
  RECUR_DT = col_character()  # Keep as character for parse_pcornet_date()
)
# Note: Date columns ALWAYS stay col_character() in spec, parsed by parse_pcornet_date() in load_pcornet_table()
```

**Critical rule:** Never use col_date() in specs. Always use col_character() for date columns and let parse_pcornet_date() handle multi-format fallback. This is because readr's col_date() only accepts a single format, which fails on PCORnet's heterogeneous exports.

### 6. Adding Numeric Range Validation Columns (D-08)

**Pattern:** Add _VALID suffix columns, preserve raw values

```r
# In load_pcornet_table() AFTER all parsing:

# Age validation (TUMOR_REGISTRY1: AGE_AT_DIAGNOSIS)
if (table_name == "TUMOR_REGISTRY1" && "AGE_AT_DIAGNOSIS" %in% names(df)) {
  df <- df %>%
    mutate(
      AGE_AT_DIAGNOSIS_VALID = case_when(
        is.na(AGE_AT_DIAGNOSIS) ~ NA,
        AGE_AT_DIAGNOSIS < 0 ~ FALSE,
        AGE_AT_DIAGNOSIS > 120 ~ FALSE,
        TRUE ~ TRUE
      )
    )
}

# Age validation (TUMOR_REGISTRY2/3: DXAGE)
if (table_name %in% c("TUMOR_REGISTRY2", "TUMOR_REGISTRY3") && "DXAGE" %in% names(df)) {
  df <- df %>%
    mutate(
      DXAGE_VALID = case_when(
        is.na(DXAGE) ~ NA,
        DXAGE < 0 ~ FALSE,
        DXAGE > 120 ~ FALSE,
        TRUE ~ TRUE
      )
    )
}

# Tumor size validation (TUMOR_REGISTRY1)
if (table_name == "TUMOR_REGISTRY1") {
  for (size_col in c("TUMOR_SIZE_SUMMARY", "TUMOR_SIZE_CLINICAL", "TUMOR_SIZE_PATHOLOGIC")) {
    if (size_col %in% names(df)) {
      valid_col <- paste0(size_col, "_VALID")
      df <- df %>%
        mutate(
          !!valid_col := case_when(
            is.na(.data[[size_col]]) ~ NA,
            .data[[size_col]] < 0 ~ FALSE,
            .data[[size_col]] > 999 ~ FALSE,  # 999mm = 99.9cm, plausible upper bound
            TRUE ~ TRUE
          )
        )
    }
  }
}

# Date range validation (ALL date columns)
for (col in date_cols) {
  if (inherits(df[[col]], "Date")) {
    valid_col <- paste0(col, "_VALID")
    df <- df %>%
      mutate(
        !!valid_col := case_when(
          is.na(.data[[col]]) ~ NA,
          .data[[col]] < as.Date("1900-01-01") ~ FALSE,
          .data[[col]] > Sys.Date() ~ FALSE,
          TRUE ~ TRUE
        )
      )
  }
}
```

**Rationale:** _VALID columns enable downstream filtering (`filter(AGE_AT_DIAGNOSIS_VALID)`) without losing the raw data for auditing. Analysts can choose to exclude invalid values or investigate why they're invalid.

### 7. HL Source Tracking and Exclusion (D-02, D-20)

**Current implementation:** has_hodgkin_diagnosis() in 03_cohort_predicates.R returns union of DIAGNOSIS and TUMOR_REGISTRY sources, but doesn't track WHICH source identified each patient.

**Updated pattern:**

```r
# In 03_cohort_predicates.R:

has_hodgkin_diagnosis <- function(patient_df) {
  # (existing DIAGNOSIS and TR source extraction code)

  # NEW: Create full mapping with source tracking
  hl_source_map <- pcornet$DEMOGRAPHIC %>%
    select(ID) %>%
    left_join(
      dx_hl_patients %>% mutate(has_dx = TRUE),
      by = "ID"
    ) %>%
    left_join(
      tr_all %>% mutate(has_tr = TRUE),
      by = "ID"
    ) %>%
    mutate(
      has_dx = coalesce(has_dx, FALSE),
      has_tr = coalesce(has_tr, FALSE),
      HL_SOURCE = case_when(
        has_dx & has_tr ~ "Both",
        has_dx & !has_tr ~ "DIAGNOSIS only",
        !has_dx & has_tr ~ "TR only",
        TRUE ~ "Neither"
      )
    )

  message(glue("[Predicate] has_hodgkin_diagnosis breakdown:"))
  message(glue("  Both sources: {sum(hl_source_map$HL_SOURCE == 'Both')}"))
  message(glue("  DIAGNOSIS only: {sum(hl_source_map$HL_SOURCE == 'DIAGNOSIS only')}"))
  message(glue("  TR only: {sum(hl_source_map$HL_SOURCE == 'TR only')}"))
  message(glue("  Neither (excluded): {sum(hl_source_map$HL_SOURCE == 'Neither')}"))

  # Filter to patients with HL evidence (exclude "Neither")
  patient_df_with_source <- patient_df %>%
    inner_join(
      hl_source_map %>% filter(HL_SOURCE != "Neither") %>% select(ID, HL_SOURCE),
      by = "ID"
    )

  # Write excluded patients to CSV (D-02)
  excluded <- patient_df %>%
    inner_join(
      hl_source_map %>% filter(HL_SOURCE == "Neither") %>% select(ID, HL_SOURCE),
      by = "ID"
    ) %>%
    mutate(
      EXCLUSION_REASON = "No HL evidence in DIAGNOSIS or TUMOR_REGISTRY tables"
    )

  if (nrow(excluded) > 0) {
    write_csv(
      excluded,
      file.path(CONFIG$output_dir, "cohort", "excluded_no_hl_evidence.csv")
    )
    message(glue("  Wrote {nrow(excluded)} excluded patients to excluded_no_hl_evidence.csv"))
  }

  return(patient_df_with_source)
}
```

**In 04_build_cohort.R:** HL_SOURCE column now flows through the pipeline automatically because has_hodgkin_diagnosis() adds it to the tibble.

### 8. Data Quality Summary CSV (D-17)

**Structure:**
```r
# At end of remediation, generate summary:
data_quality_summary <- tribble(
  ~issue_type,                     ~count_before, ~count_after, ~status,      ~notes,
  "Date parsing failures",         45,            3,            "fixed",      "Added MM/DD/YYYY and DD/MM/YYYY formats to parse_pcornet_date()",
  "Date parsing failures",         3,             3,            "accepted",   "Remaining 3 are genuinely blank fields per PCORnet spec",
  "Character date columns",        12,            2,            "fixed",      "Expanded date_regex to include TIME and YEAR patterns",
  "TR column type mismatches",     8,             0,            "fixed",      "Updated TUMOR_REGISTRY1_SPEC with col_double() for numeric columns",
  "Encoding issues (non-ASCII)",   5,             5,            "documented", "Non-ASCII in FACILITY_LOCATION names - preserved per D-06",
  "Negative ages",                 2,             2,            "documented", "AGE_AT_DIAGNOSIS_VALID=FALSE flags these; raw values preserved",
  "Future dates",                  1,             1,            "documented", "DISCHARGE_DATE_VALID=FALSE; likely data entry error",
  "Missing payer (>50%)",          1,             1,            "accepted",   "PAYER_TYPE_SECONDARY missing in 65% of encounters - optional field",
  "HL identification: Neither",    23,            0,            "fixed",      "23 patients excluded to excluded_no_hl_evidence.csv per D-02",
  "Dual-eligible rate",            NA,            NA,           "documented", "R pipeline: 14.2%, Python pipeline: 15.1%. Within expected 10-20% range (D-04)"
)

write_csv(
  data_quality_summary,
  file.path(CONFIG$output_dir, "diagnostics", "data_quality_summary.csv")
)
```

**Statuses:**
- **fixed:** Issue resolved by code change, count reduced to 0 or acceptable level
- **accepted:** Issue is expected (optional field, known data limitation), no fix needed
- **documented:** Issue flagged with validation column or note, raw data preserved

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Multi-format date parsing | Custom regex + as.Date() for each format | lubridate::parse_date_time() with multiple orders | Handles format guessing with training subset, optimized fast_strptime() for numeric formats, built-in fallback chain |
| Data validation rules | Custom if/else chains with stop() | pointblank validation agents or assertr verify() | Declarative validation with automatic reporting, works with data frames and databases, generates validation reports |
| Column type inference | Manual type checking with class() loops | readr::spec() to extract guessed types, then refine | Mature type guessing algorithm, easy copy-paste-tweak workflow from guessed spec to explicit spec |
| Regex pattern testing | Trial-and-error in console | stringr::str_detect() with regex() wrapper for explicit options | Clear intent (ignore_case, multiline, etc.), integrates with tidyverse, modern 2026 best practice |
| Audit trail tracking | Manual CSV writing in each script | Centralized data_quality_summary.csv with status tracking | Single source of truth for remediation history, enables before/after comparison, supports compliance audits |

**Key insight:** R ecosystem already solved these problems. The remediation workflow should USE existing utilities (lubridate, readr, stringr), not rebuild them. Only custom code needed: domain-specific validation rules (HL source tracking, payer mapping audit) and pipeline-specific fixes (updating col_types based on actual data).

## Common Pitfalls

### Pitfall 1: Fixing Issues Without Understanding Root Cause
**What goes wrong:** Adding a date format to parse_pcornet_date() without checking sample_raw_values leads to incorrect parsing or missed formats.
**Why it happens:** Assuming based on column name rather than inspecting actual data.
**How to avoid:** ALWAYS request sample_raw_values from date_parsing_failures.csv. Analyze patterns before writing regex. Test on samples before deploying.
**Warning signs:** unparsed_count stays high after fix, or new NA values appear in previously-parsed columns.

### Pitfall 2: Using col_date() in readr col_types Specs
**What goes wrong:** readr's col_date() requires a single format string. PCORnet sites export dates in multiple formats, causing parse failures.
**Why it happens:** Misunderstanding readr's type specification vs. lubridate's multi-format parsing.
**How to avoid:** ALWAYS use col_character() for date columns in TABLE_SPECS. Let parse_pcornet_date() handle multi-format fallback in load_pcornet_table().
**Warning signs:** Sudden spike in parse problems after updating col_types, or entire date columns becoming NA.

### Pitfall 3: Stripping or Coercing Invalid Values
**What goes wrong:** Replacing negative ages with NA or clamping extreme values to valid ranges loses data and hides quality issues.
**Why it happens:** Desire to "clean" data for analysis, but loses audit trail.
**How to avoid:** Per D-08: add _VALID columns, preserve raw values. Analysts can filter on _VALID=TRUE if needed, but raw data remains for investigation.
**Warning signs:** Data quality summary shows "fixed" issues but no record of what the invalid values were, making it impossible to identify systematic problems.

### Pitfall 4: Expanding Regex Too Broadly
**What goes wrong:** Adding "TIME" to date_regex catches TIME_TO_EVENT (numeric duration) and tries to parse as date, creating spurious failures.
**Why it happens:** Overgeneralizing from a few missed columns without checking all matches.
**How to avoid:** After expanding regex, re-run date_column_regex_audit.csv and review ALL new matches, not just the ones you intended to catch. Use anchors (^, $) and negative lookahead if needed.
**Warning signs:** New columns appear in date_parsing_failures.csv that are clearly not dates (e.g., TIME_ZONE, EVENT_TIMING).

### Pitfall 5: Mixing Fix Batches
**What goes wrong:** Changing date parser, col_types, and payer mapping in a single commit makes it impossible to isolate which fix caused new issues.
**Why it happens:** Impatience to "fix everything at once."
**How to avoid:** Per D-13: group fixes by issue type. Validate each batch separately. Only combine in final full rebuild.
**Warning signs:** After a multi-fix commit, diagnostics show new failures, but can't determine which fix introduced them.

### Pitfall 6: Forgetting to Update 07_diagnostics.R
**What goes wrong:** After adding HL_SOURCE column to cohort, diagnostics script fails because it expects old schema.
**Why it happens:** Diagnostics script is treated as "read-only" rather than part of the pipeline.
**How to avoid:** Per D-19: review 07_diagnostics.R after structural changes (new columns, renamed tables). Update accordingly.
**Warning signs:** Diagnostics script throws "column not found" errors, or produces incorrect summaries after pipeline changes.

### Pitfall 7: Accepting High Missing Rates Without Investigation
**What goes wrong:** Assuming >50% missing is "just how the data is" when it's actually a parsing or column mismatch issue.
**Why it happens:** Fatigue from debugging, assuming PCORnet data is inherently messy.
**How to avoid:** Per D-09: for every column with >50% missing, check (1) is column optional per CDM spec? (2) is data genuinely absent or is loader failing silently? (3) do other sites have data for this column?
**Warning signs:** Column that should have high completion (e.g., ID, SOURCE) shows 50%+ missing; column has data in Python pipeline but missing in R pipeline.

## Code Examples

Verified patterns from project codebase and official documentation:

### 1. Expanding parse_pcornet_date() with New Format
```r
# Source: R/utils_dates.R (existing pattern)
# Adding MM/DD/YYYY format (hypothetical example)

parse_pcornet_date <- function(date_char) {
  # ... (existing attempts 1-4)

  # NEW Attempt 5: MM/DD/YYYY (US format with slashes)
  remaining <- is.na(result) & !is.na(date_char)
  if (any(remaining)) {
    parsed_mdy <- suppressWarnings(mdy(date_char[remaining], quiet = TRUE))
    if (any(!is.na(parsed_mdy))) {
      idx_in_remaining <- which(remaining)[!is.na(parsed_mdy)]
      result[idx_in_remaining] <- parsed_mdy[!is.na(parsed_mdy)]
    }
  }

  # ... (unparsed logging)
  return(result)
}
```

### 2. Updating TUMOR_REGISTRY col_types Based on Audit
```r
# Source: R/01_load_pcornet.R (existing pattern)
# Example: Adding numeric columns flagged by tr_type_audit.csv

TUMOR_REGISTRY1_SPEC <- cols(
  .default = col_character(),
  # Existing numeric columns
  AGE_AT_DIAGNOSIS = col_integer(),
  TUMOR_SIZE_SUMMARY = col_double(),
  TUMOR_SIZE_CLINICAL = col_double(),
  TUMOR_SIZE_PATHOLOGIC = col_double(),
  # NEW: Based on tr_type_audit.csv showing >80% numeric
  LYMPH_NODES_POSITIVE = col_integer(),     # pct_numeric = 92%
  GRADE_CLINICAL = col_integer(),           # pct_numeric = 88%
  CS_TUMOR_SIZE = col_double()              # pct_numeric = 95%
)
```

### 3. Expanding Date Column Detection Regex
```r
# Source: R/01_load_pcornet.R line 231 (existing pattern)
# Example: Adding TIME and YEAR patterns based on audit

# BEFORE:
date_regex <- "(?i)(DATE|^DT_|^BDATE$|^DOD$|^DT_FU$|DXDATE|_DT$|RECUR_DT|COMBINED_LAST_CONTACT|ADDRESS_PERIOD_START|ADDRESS_PERIOD_END)"

# AFTER (based on date_column_regex_audit.csv showing missed TIME/YEAR columns):
date_regex <- "(?i)(DATE|TIME|YEAR|^DT_|^BDATE$|^DOD$|^DT_FU$|DXDATE|_DT$|RECUR_DT|COMBINED_LAST_CONTACT|ADDRESS_PERIOD_START|ADDRESS_PERIOD_END)"

# In load_pcornet_table():
date_cols <- names(df)[str_detect(names(df), date_regex)]
for (col in date_cols) {
  if (is.character(df[[col]])) {
    df[[col]] <- parse_pcornet_date(df[[col]])
  }
}
```

### 4. Adding Numeric Range Validation Columns
```r
# Source: D-08 requirement + R/01_load_pcornet.R pattern
# Example: Age validation for TUMOR_REGISTRY1

# In load_pcornet_table() AFTER all parsing:
if (table_name == "TUMOR_REGISTRY1" && "AGE_AT_DIAGNOSIS" %in% names(df)) {
  df <- df %>%
    mutate(
      AGE_AT_DIAGNOSIS_VALID = case_when(
        is.na(AGE_AT_DIAGNOSIS) ~ NA,           # NA stays NA
        AGE_AT_DIAGNOSIS < 0 ~ FALSE,           # Negative = invalid
        AGE_AT_DIAGNOSIS > 120 ~ FALSE,         # >120 = invalid
        TRUE ~ TRUE                              # Otherwise valid
      )
    )

  # Log validation results
  n_invalid <- sum(!df$AGE_AT_DIAGNOSIS_VALID, na.rm = TRUE)
  if (n_invalid > 0) {
    message(glue("  Added AGE_AT_DIAGNOSIS_VALID: {n_invalid} invalid ages flagged"))
  }
}
```

### 5. Tracking HL Source and Writing Exclusion CSV
```r
# Source: R/03_cohort_predicates.R (existing has_hodgkin_diagnosis pattern)
# Updated to track source and write exclusions

has_hodgkin_diagnosis <- function(patient_df) {
  # (existing DIAGNOSIS and TR patient extraction)

  # NEW: Full source mapping
  hl_source_map <- pcornet$DEMOGRAPHIC %>%
    select(ID, SOURCE) %>%
    left_join(dx_hl_patients %>% mutate(has_dx = TRUE), by = "ID") %>%
    left_join(tr_all %>% mutate(has_tr = TRUE), by = "ID") %>%
    mutate(
      has_dx = coalesce(has_dx, FALSE),
      has_tr = coalesce(has_tr, FALSE),
      HL_SOURCE = case_when(
        has_dx & has_tr ~ "Both",
        has_dx & !has_tr ~ "DIAGNOSIS only",
        !has_dx & has_tr ~ "TR only",
        TRUE ~ "Neither"
      )
    )

  # Log breakdown
  message(glue("[Predicate] HL source breakdown:"))
  source_counts <- hl_source_map %>% count(HL_SOURCE)
  for (i in 1:nrow(source_counts)) {
    message(glue("  {source_counts$HL_SOURCE[i]}: {source_counts$n[i]}"))
  }

  # Write excluded patients (D-02)
  excluded <- hl_source_map %>%
    filter(HL_SOURCE == "Neither") %>%
    mutate(EXCLUSION_REASON = "No HL evidence in DIAGNOSIS or TUMOR_REGISTRY")

  if (nrow(excluded) > 0) {
    dir.create(file.path(CONFIG$output_dir, "cohort"), showWarnings = FALSE, recursive = TRUE)
    write_csv(excluded, file.path(CONFIG$output_dir, "cohort", "excluded_no_hl_evidence.csv"))
    message(glue("  Wrote {nrow(excluded)} excluded patients to excluded_no_hl_evidence.csv"))
  }

  # Return patients WITH HL evidence, including HL_SOURCE column
  patient_df %>%
    inner_join(
      hl_source_map %>% filter(HL_SOURCE != "Neither") %>% select(ID, HL_SOURCE),
      by = "ID"
    )
}
```

### 6. Generating Data Quality Summary CSV
```r
# Source: D-17 requirement
# Example: Final validation summary after all fixes

library(tibble)
library(readr)
library(glue)

# Collect before/after counts from diagnostic CSVs and fix logs
data_quality_summary <- tribble(
  ~issue_type,                     ~count_before, ~count_after, ~status,      ~notes,
  "Date parsing failures",         45,            3,            "fixed",      "Added MM/DD/YYYY and DD/MM/YYYY to parse_pcornet_date()",
  "Date parsing failures",         3,             3,            "accepted",   "Remaining 3 are blank ENR_END_DATE (ongoing enrollment per CDM spec)",
  "Character date columns",        12,            2,            "fixed",      "Expanded date_regex to include TIME and YEAR patterns",
  "Character date columns",        2,             2,            "accepted",   "TIME_TO_EVENT and YEAR_OF_BIRTH are intentionally numeric, not dates",
  "TR column type mismatches",     8,             0,            "fixed",      "Updated TUMOR_REGISTRY1_SPEC: LYMPH_NODES_POSITIVE, GRADE_CLINICAL, CS_TUMOR_SIZE to col_integer()",
  "Encoding issues (non-ASCII)",   5,             5,            "documented", "Non-ASCII in FACILITY_LOCATION names (e.g., 'José Martí Clinic') - preserved per D-06",
  "BOM in first row",              1,             1,            "documented", "BOM in DEMOGRAPHIC.csv SOURCE column - flagged in encoding_issues.csv, no strip per D-06",
  "Negative ages",                 2,             2,            "documented", "AGE_AT_DIAGNOSIS_VALID=FALSE for 2 patients; raw -1 values preserved",
  "Extreme ages (>120)",           1,             1,            "documented", "AGE_AT_DIAGNOSIS=999 likely missing data code; flagged with _VALID=FALSE",
  "Future dates",                  1,             1,            "documented", "DISCHARGE_DATE=2027-05-01 flagged with _VALID=FALSE; likely data entry error",
  "Pre-1900 dates",                0,             0,            "accepted",   "No pre-1900 dates found after parsing fixes",
  "Missing payer (>50%)",          2,             1,            "fixed",      "PAYER_TYPE_SECONDARY missing 65% - expected for single-payer encounters",
  "Missing payer (>50%)",          1,             1,            "accepted",   "PAYER_TYPE_PRIMARY missing 12% - matches Python pipeline (11.8%)",
  "HL identification: Neither",    23,            0,            "fixed",      "23 patients excluded to excluded_no_hl_evidence.csv per D-02",
  "HL identification: Both",       NA,            156,          "documented", "156 patients identified by BOTH DIAGNOSIS and TUMOR_REGISTRY (D-20)",
  "HL identification: DX only",    NA,            89,           "documented", "89 patients identified by DIAGNOSIS only (D-20)",
  "HL identification: TR only",    NA,            67,           "documented", "67 patients identified by TUMOR_REGISTRY only (D-20)",
  "Dual-eligible rate",            NA,            14.2,         "documented", "R pipeline: 14.2%, Python pipeline: 15.1%. Within 10-20% expected range (D-04)",
  "Unmapped payer codes",          3,             3,            "accepted",   "Codes 'NI', 'OT', 'UN' already map to correct categories per PAYER_MAPPING"
)

write_csv(
  data_quality_summary,
  file.path(CONFIG$output_dir, "diagnostics", "data_quality_summary.csv")
)

message(glue("\nData quality summary:"))
message(glue("  Total issues tracked: {nrow(data_quality_summary)}"))
message(glue("  Fixed: {sum(data_quality_summary$status == 'fixed')}"))
message(glue("  Accepted: {sum(data_quality_summary$status == 'accepted')}"))
message(glue("  Documented: {sum(data_quality_summary$status == 'documented')}"))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual date format detection with base R strptime | lubridate parse_date_time() with multi-format fallback and training | lubridate 1.7.0+ (2017) | Automatic format guessing, fast_strptime() optimization for numeric formats, handles heterogeneous date formats in single column |
| readr type guessing with no explicit specs | Explicit col_types specs matured from exploration (spec() workflow) | readr 2.0+ best practice (2021) | Prevents type inference drift, faster loading (skips guessing), explicit documentation of expected types |
| Manual validation with if/else + stop() | Declarative validation frameworks (pointblank 0.12.3, assertr) | pointblank released 2020, matured 2025 | Validation as code (version controlled), automatic reporting, works with databases, separation of validation logic from analysis |
| grepl() with ignore.case = TRUE | str_detect() with regex() wrapper (tidyverse 2025-2026) | tidyverse 2.0+ / R 4.4+ | Clearer intent, better tidyverse integration, filter(if_any(...)) for multi-column conditions |
| Single-pass debugging (fix all issues, hope for best) | Iterative data-driven debugging (diagnostics → fix → validate → repeat) | Industry best practice (healthcare/clinical data 2020s) | Prevents fix cascades, isolates root causes, maintains audit trail |

**Deprecated/outdated:**
- **Base R strptime() for multi-format parsing:** lubridate parse_date_time() handles this better with training-based format selection
- **Implicit type guessing in production pipelines:** readr 2.0+ best practice is explicit col_types for mature projects
- **grepl() for tidyverse workflows:** str_detect() is the modern standard (2026), especially with regex() wrapper for clarity

## Open Questions

1. **What date formats will diagnostics reveal?**
   - What we know: Current parse_pcornet_date() handles ISO, Excel serial, SAS DATE9, and YYYYMMDD compact
   - What's unclear: Actual formats in Mailhot HL extract CSVs on HiPerGator
   - Recommendation: Wait for date_parsing_failures.csv with sample_raw_values. Add formats based on actual data, not speculation

2. **Which TUMOR_REGISTRY columns need type changes?**
   - What we know: Current specs have AGE_AT_DIAGNOSIS (integer), TUMOR_SIZE_* (double), everything else character
   - What's unclear: Which character columns are actually numeric/date and should be retyped
   - Recommendation: Wait for tr_type_audit.csv showing pct_numeric and pct_datelike. Update specs based on >80% threshold

3. **How many patients have "Neither" HL source?**
   - What we know: This is a pre-filtered HL cohort, so "Neither" should be rare or zero
   - What's unclear: Actual count and whether it indicates data quality issue vs. extract scope mismatch
   - Recommendation: Wait for hl_identification_venn.csv. If count >0, investigate why (missing TR columns? ICD code list incomplete?)

4. **Do R and Python payer mappings diverge significantly?**
   - What we know: Both use 9-category scheme, dual-eligible detection via temporal overlap
   - What's unclear: Actual category distributions, dual-eligible rates, unmapped code counts
   - Recommendation: Wait for payer_mapping_audit.csv. Document differences in comments (D-04), investigate large divergences (>5% difference in major categories)

5. **Are >50% missing columns parsing failures or genuinely sparse?**
   - What we know: PCORnet CDM has many optional fields (e.g., PAYER_TYPE_SECONDARY, SEXUAL_ORIENTATION)
   - What's unclear: Which high-missing columns are expected vs. loader issues
   - Recommendation: Wait for missing_values_audit.csv. Cross-reference against PCORnet CDM v7.0 spec for required vs. optional. Compare against Python pipeline if available

6. **Should pointblank validation be added now or deferred to v2?**
   - What we know: Manual validation via 07_diagnostics.R works, pointblank offers declarative framework
   - What's unclear: Whether validation complexity justifies adding new dependency
   - Recommendation: Defer to v2 unless diagnostic fixes reveal need for complex cross-column validation rules. Current _VALID column approach sufficient for v1

## Sources

### Primary (HIGH confidence)
- [lubridate parse_date_time() documentation](https://lubridate.tidyverse.org/reference/parse_date_time.html) - multi-format fallback, training-based format selection
- [lubridate package PDF February 2026](https://cran.r-project.org/web/packages/lubridate/lubridate.pdf) - current version features
- [readr column type specification](https://readr.tidyverse.org/articles/column-types.html) - col_types best practices, spec() workflow
- [readr introduction](https://cran.r-project.org/web/packages/readr/vignettes/readr.html) - explicit types for mature projects
- [stringr regular expressions with tidyverse 2026](https://copyprogramming.com/howto/r-select-rows-containing-only-string-in-r) - str_detect() best practices, if_any()/if_all() patterns
- [PCORnet Common Data Model v7.0 specification](https://pcornet.org/wp-content/uploads/2025/05/PCORnet_Common_Data_Model_v70_2025_05_01.pdf) - official CDM structure, required vs optional fields
- Project codebase: R/utils_dates.R, R/01_load_pcornet.R, R/07_diagnostics.R - existing implementation patterns

### Secondary (MEDIUM confidence)
- [pointblank GitHub](https://github.com/rstudio/pointblank) - data validation framework features
- [assertr vignette](https://cran.r-project.org/web/packages/assertr/vignettes/assertr.html) - assertion-based validation patterns
- [Data validation in R using tidyverse](https://codepointtech.com/validate-your-data-like-a-pro-with-rs-tidyverse/) - validation best practices
- [PCORnet CDM data quality validation guidance](https://pcornet.org/wp-content/uploads/2024/12/CDM-Data-Quality-Validation.pdf) - official DQ validation recommendations
- [Tailoring rule-based DQ assessment to PCORnet CDM](https://pmc.ncbi.nlm.nih.gov/articles/PMC10148276/) - clinical data quality patterns
- [R packages for data quality assessments (systematic review)](https://www.mdpi.com/2076-3417/12/9/4238) - dlookr, pointblank, validate comparison

### Tertiary (LOW confidence)
- [dlookr diagnosis vignette](https://cran.r-project.org/web/packages/dlookr/vignettes/diagonosis.html) - automated diagnosis patterns (reference only, 07_diagnostics.R already exists)
- [January 2026 new CRAN packages](https://www.r-bloggers.com/2026/02/january-2026-top-40-new-cran-packages/) - autoFlagR for EHR data quality (new package, not yet mature)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - lubridate, readr, stringr, dplyr are mature tidyverse core packages with stable APIs and extensive documentation
- Architecture patterns: HIGH - data-driven remediation workflow is industry standard for clinical data; existing codebase provides clear patterns
- Pitfalls: HIGH - based on common R debugging issues (col_date vs col_character, regex overreach) and project-specific constraints (D-08 preserve raw values)
- Code examples: HIGH - all examples derived from existing codebase patterns (utils_dates.R, 01_load_pcornet.R, 03_cohort_predicates.R) or official documentation

**Research date:** 2026-03-25
**Valid until:** ~60 days (stable domain: R package APIs change slowly, PCORnet CDM v7.0 is current through 2026, remediation patterns are timeless)

**Key research gaps addressed:**
- Confirmed lubridate parse_date_time() fallback behavior (applies formats in sequence till success, training-based guessing)
- Confirmed readr col_types best practice (explicit specs for mature projects, spec() workflow to extract guesses)
- Confirmed stringr/tidyverse 2026 patterns (str_detect() + if_any()/if_all() for modern R 4.4+)
- Confirmed PCORnet data quality common issues (laboratory/medication errors, date parsing variability, encoding issues)
- Identified pointblank/assertr as optional validation frameworks (defer to v2 unless complexity increases)

**Critical for planning:**
- All fixes data-driven (wait for actual diagnostics before writing code)
- Fix batches must be isolated (date → type → domain-specific → validation)
- Validation columns (_VALID suffix) preserve raw values (D-08)
- HL_SOURCE tracking requires updating has_hodgkin_diagnosis() to return source-annotated tibble
- data_quality_summary.csv is the formal resolution record (status: fixed/accepted/documented)
