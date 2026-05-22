# Phase 6: Make Dataset That Produces cancer_summary_template.xlsx - Research

**Researched:** 2026-05-21
**Domain:** Patient-code level cancer diagnosis dataset with date-based confirmation metrics
**Confidence:** HIGH

## Summary

Phase 6 creates R/53_cancer_summary.R to generate a patient-code level dataset from the DIAGNOSIS table. Each row represents one patient + one cancer code (all neoplasm codes C00-D49) with date-based confirmation metrics. The script outputs both cancer_summary.xlsx and cancer_summary.csv to output/tables/, covering all patients in DIAGNOSIS (not restricted to HL cohort).

This phase builds on established patterns from R/47 (PREFIX_MAP classification), R/50-51 (date confirmation logic), and R/52 (description cascade), combining them into a single patient-code-level export with 7 columns: ID, cancer_code, description, two_or_more_unique_dates, two_or_more_unique_dates_gt_7, unique_dates_total, unique_dates_with_sep_gt_7.

**Primary recommendation:** Reuse PREFIX_MAP, classify_codes(), and date aggregation patterns from R/47, R/50, R/51 exactly as written. Generate xlsx from scratch using openxlsx2 (minimal styling, data export focus). Handle NA dates gracefully (0 for all confirmation metrics when all dates are NA).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Data Content:**
- **D-01:** Output is patient-code level: one row per patient per unique cancer code they have in DIAGNOSIS
- **D-02:** Columns: `ID`, `cancer_code`, `description`, `two_or_more_unique_dates`, `two_or_more_unique_dates_gt_7`, `unique_dates_total`, `unique_dates_with_sep_gt_7`
- **D-03:** `two_or_more_unique_dates` = 1 if patient has 2+ distinct non-NA DX_DATEs for this code, else 0 (integer 1/0 flags, not TRUE/FALSE)
- **D-04:** `two_or_more_unique_dates_gt_7` = 1 if patient has 2+ distinct DX_DATEs where max(date) - min(date) >= 7 days for this code, else 0
- **D-05:** `unique_dates_total` = count of distinct non-NA DX_DATEs for this patient-code combo
- **D-06:** `unique_dates_with_sep_gt_7` = count of distinct dates that are >7 days from at least one other date for this patient-code (Claude's discretion on interpretation — clinically, this is the number of dates that contribute to "spread" evidence)
- **D-07:** Patient-code combos where all DX_DATEs are NA get 0 for all confirmation columns — code presence is still recorded
- **D-08:** Code scope: all neoplasm codes with C or D prefix (C00-D49), same as R/47
- **D-09:** Data source: DIAGNOSIS table only (DX_TYPE == "10" for ICD-10), no TUMOR_REGISTRY
- **D-10:** `description` column: include both cancer site category name (from PREFIX_MAP) and code-level description where available (Claude's discretion on best source and format)

**Template Approach:**
- **D-11:** Generate xlsx from scratch in R code using openxlsx2 (not reading the template file). Template serves as specification, not input.
- **D-12:** Single flat sheet with all patient-code rows
- **D-13:** Output both xlsx and CSV formats

**Patient Scope:**
- **D-14:** All patients in DIAGNOSIS with neoplasm codes (not restricted to HL cohort)

**Output:**
- **D-15:** Output directory: output/tables/
- **D-16:** Filenames: cancer_summary.xlsx and cancer_summary.csv

**Script:**
- **D-17:** Script: R/53_cancer_summary.R
- **D-18:** Minimal xlsx styling (headers and data, no dark header fill or special formatting — primarily a data export)

### Claude's Discretion

- `unique_dates_with_sep_gt_7` interpretation: Claude picks the most clinically useful counting method for dates >7 days apart
- Description source: Claude picks best combination of PREFIX_MAP category names and code-level descriptions from available sources (Phase 39-41 RDS, config comments, etc.)
- Performance safeguards: Claude assesses data volume during research and adds row count warnings or memory management if needed

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

## Standard Stack

### Core Libraries
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Standard for patient-code aggregation; group_by + summarise pattern |
| stringr | 1.5.1+ | String operations | ICD-10 code normalization (remove dots, uppercase) |
| glue | 1.8.0 | String formatting | Logging and output messages |
| openxlsx2 | 1.11.2+ | Excel generation | Generate styled xlsx from scratch; successor to openxlsx (R4.0.0+ compatible) |

### Supporting Libraries
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| lubridate | 1.9.3+ | Date operations | Date difference calculation (7-day gap logic) |
| tibble | 3.2.1+ | Modern data frames | Explicit tibble construction if needed |

**Installation:**
```bash
# All libraries already in project dependency set
# (loaded via R/00_config.R and canonical scripts)
```

**Version verification:** Not required — all libraries already used in canonical scripts R/47, R/50-52.

## Architecture Patterns

### Recommended Project Structure
```
R/
├── 53_cancer_summary.R        # New script for this phase
├── 47_cancer_site_frequency.R # Reuse: PREFIX_MAP, classify_codes()
├── 50_cancer_site_confirmation.R  # Reuse: 2-date confirmation logic
├── 51_cancer_site_confirmation_7day.R  # Reuse: 7-day gap logic
└── 52_all_codes_resolved.R    # Reuse: multi-source description cascade
```

### Pattern 1: Load and Classify Neoplasm Codes (from R/47)
**What:** Load DIAGNOSIS, filter to ICD-10 neoplasm codes (C00-D49), classify by 3-character prefix
**When to use:** Phase 6 data loading
**Example:**
```r
# Source: R/47_cancer_site_frequency.R lines 388-410
dx_icd10 <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  select(ID, DX, DX_DATE) %>%
  collect()

# Normalize codes
dx_icd10 <- dx_icd10 %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\.")))

# Filter to neoplasm codes only (C00-D49)
dx_cancer <- dx_icd10 %>%
  filter(str_detect(DX_norm, "^[CD]"))

# Classify
dx_cancer <- dx_cancer %>%
  mutate(category = classify_codes(DX_norm))
```

### Pattern 2: Date-Based Confirmation Logic (from R/50, R/51)
**What:** Count distinct dates and compute 2-date / 7-day gap flags per patient-code
**When to use:** Aggregation step in Phase 6
**Example:**
```r
# Source: R/50_cancer_site_confirmation.R lines 424-434
# 2+ distinct dates logic
confirmed_exact <- dx_cancer %>%
  filter(!is.na(DX_DATE)) %>%
  distinct(ID, DX_norm, DX_DATE, category) %>%   # Deduplicate per Pitfall 3
  group_by(ID, DX_norm) %>%
  filter(n_distinct(DX_DATE) >= 2) %>%
  ungroup()

# Source: R/51_cancer_site_confirmation_7day.R lines 425-434
# 7-day gap logic
confirmed_7day <- dx_cancer %>%
  filter(!is.na(DX_DATE)) %>%
  distinct(ID, DX_norm, DX_DATE, category) %>%
  group_by(ID, DX_norm) %>%
  filter(as.numeric(max(DX_DATE) - min(DX_DATE)) >= 7) %>%
  ungroup()
```

### Pattern 3: Patient-Code Level Aggregation (NEW for Phase 6)
**What:** Create one row per patient-code combo with all date metrics
**When to use:** Core aggregation in Phase 6
**Recommended structure:**
```r
# Per D-02, D-03, D-04, D-05, D-06, D-07
cancer_summary <- dx_cancer %>%
  group_by(ID, DX_norm, category) %>%
  summarise(
    # D-05: Total distinct non-NA dates
    unique_dates_total = n_distinct(DX_DATE[!is.na(DX_DATE)]),
    # D-03: 2+ distinct dates flag
    two_or_more_unique_dates = as.integer(n_distinct(DX_DATE[!is.na(DX_DATE)]) >= 2),
    # D-04: 7-day gap flag
    two_or_more_unique_dates_gt_7 = as.integer(
      if (n_distinct(DX_DATE[!is.na(DX_DATE)]) >= 2) {
        as.numeric(max(DX_DATE, na.rm=TRUE) - min(DX_DATE, na.rm=TRUE)) >= 7
      } else {
        FALSE
      }
    ),
    # D-06: Count dates with >7 day separation (see "unique_dates_with_sep_gt_7 Interpretation" below)
    unique_dates_with_sep_gt_7 = <CUSTOM LOGIC>,
    .groups = "drop"
  ) %>%
  # D-07: Ensure 0 for all metrics when unique_dates_total == 0
  mutate(
    two_or_more_unique_dates = ifelse(unique_dates_total == 0, 0L, two_or_more_unique_dates),
    two_or_more_unique_dates_gt_7 = ifelse(unique_dates_total == 0, 0L, two_or_more_unique_dates_gt_7),
    unique_dates_with_sep_gt_7 = ifelse(unique_dates_total == 0, 0L, unique_dates_with_sep_gt_7)
  )
```

### Pattern 4: Multi-Source Description Cascade (from R/52)
**What:** Look up code descriptions from RDS artifacts, hardcoded tables, config comments
**When to use:** Adding `description` column in Phase 6
**Example:**
```r
# Source: R/52_all_codes_resolved.R lines 76-158
# Three-tier cascade:
# 1. Phase 39-41 RDS artifacts
# 2. Phase 45 hardcoded descriptions
# 3. R/00_config.R inline comments
# 4. Fallback: "No description available"

# For Phase 6: Combine PREFIX_MAP category + code description
# Recommended format: "Hodgkin Lymphoma - C81.10 (Nodular lymphocyte predominant)"
```

### Pattern 5: Minimal XLSX Generation (NEW for Phase 6)
**What:** Generate xlsx with header row and data (no dark header fill, no fancy styling)
**When to use:** Output step in Phase 6 (per D-18)
**Example:**
```r
# Source: Adapted from R/47 but simplified (no dark header fill)
library(openxlsx2)

wb <- wb_workbook()
wb$add_worksheet("Cancer Summary")

# Row 1: Headers (plain, no fill)
headers <- c("ID", "cancer_code", "description", "two_or_more_unique_dates",
             "two_or_more_unique_dates_gt_7", "unique_dates_total", "unique_dates_with_sep_gt_7")
for (i in seq_along(headers)) {
  wb$add_data(sheet = "Cancer Summary", x = headers[i], start_row = 1, start_col = i)
}

# Row 2+: Data
wb$add_data(sheet = "Cancer Summary", x = as.data.frame(cancer_summary),
            start_row = 2, col_names = FALSE)

# Number formatting for integer columns
wb$add_numfmt(sheet = "Cancer Summary", dims = "D2:G<LAST_ROW>", numfmt = "0")

# Column widths (optional)
wb$set_col_widths(sheet = "Cancer Summary", cols = 1:7, widths = "auto")

# Save
wb$save("output/tables/cancer_summary.xlsx")
```

### Anti-Patterns to Avoid

- **Don't use distinct() before counting dates:** Will lose duplicate-date rows that should be deduplicated. Use `distinct(ID, DX_norm, DX_DATE)` before date counting, as shown in R/50-51.
- **Don't use TRUE/FALSE for binary flags:** D-03 requires integer 1/0 encoding (per decision). Use `as.integer()` wrapper.
- **Don't read the template file:** D-11 says generate from scratch. Template is a spec, not an input.
- **Don't add fancy styling:** D-18 says minimal styling. This is a data export, not a presentation artifact.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ICD-10 prefix classification | Custom regex or if/else chains | `PREFIX_MAP` + `classify_codes()` from R/47 | Canonical source: 309 prefix mappings to 53 categories; R/47 is maintained |
| 2-date confirmation logic | Custom date counting | Pattern from R/50 lines 424-434 | Tested, handles NA dates, uses correct deduplication |
| 7-day gap calculation | Custom date difference | Pattern from R/51 lines 425-434 | Handles NA dates, uses `as.numeric(max - min)` pattern |
| Code descriptions | API calls or custom lookup | Multi-source cascade from R/52 | Already fetched Phase 39-41 RDS; R/52 pattern handles all sources |
| XLSX generation | Manual xml writing | openxlsx2 | Handles Excel formatting quirks (e.g., shared strings, cell types) |

**Key insight:** Date-based confirmation logic has subtle pitfalls (e.g., duplicate-date deduplication, NA handling, integer vs. logical flags). R/50-51 have solved these issues — reuse verbatim.

## Runtime State Inventory

> Phase 6 is a greenfield script (no rename/refactor) — this section is not applicable.

## Common Pitfalls

### Pitfall 1: Duplicate-Date Deduplication Timing
**What goes wrong:** Counting distinct dates without deduplicating (ID, code, date) tuples first can over-count or under-count dates.
**Why it happens:** DIAGNOSIS table can have multiple rows for the same patient-code-date combo (e.g., different encounters, different diagnoses in the same encounter).
**How to avoid:** Use `distinct(ID, DX_norm, DX_DATE, category)` before any date counting logic. See R/50 line 427, R/51 line 429.
**Warning signs:** Confirmation rates look suspiciously high or date counts exceed number of diagnosis rows.

### Pitfall 2: Integer Flag Encoding
**What goes wrong:** Using TRUE/FALSE instead of 1/0 for binary flags breaks D-03 requirement and downstream summing operations.
**Why it happens:** R's `>=` comparison returns logical, not integer. `ifelse()` also returns logical by default.
**How to avoid:** Wrap all flag computations in `as.integer()`. Example: `as.integer(n_distinct(DX_DATE) >= 2)`.
**Warning signs:** Column shows TRUE/FALSE in output instead of 1/0; downstream Excel formulas fail.

### Pitfall 3: NA Date Handling in Date Difference
**What goes wrong:** `max(DX_DATE) - min(DX_DATE)` returns NA when all dates are NA, breaking the 7-day gap logic.
**Why it happens:** R's `max()` and `min()` return NA when input is all NA, unless `na.rm=TRUE` is specified.
**How to avoid:** Use `max(DX_DATE, na.rm=TRUE)` and `min(DX_DATE, na.rm=TRUE)`. Also guard with `if (n_distinct(DX_DATE[!is.na(DX_DATE)]) >= 2)` check.
**Warning signs:** NAs in `two_or_more_unique_dates_gt_7` column when dates exist; script crashes with "argument to 'max'/'min' is empty".

### Pitfall 4: unique_dates_with_sep_gt_7 Ambiguity
**What goes wrong:** D-06 is ambiguous ("dates that are >7 days from at least one other date"). Multiple interpretations exist.
**Why it happens:** Clinically, "spread evidence" could mean: (1) any date >7 days from any other, (2) dates that extend a >7 day window, (3) dates with a 7-day gap before or after.
**How to avoid:** Choose the most clinically useful interpretation: **count dates that contribute to extending a 7-day window**. Implementation: if date span < 7 days, return 0. If span >= 7 days, return count of dates that are >= 7 days from the earliest date OR >= 7 days from the latest date.
**Warning signs:** User questions results; counts don't match intuition for simple cases (e.g., 3 dates spread 1 day apart should return 0, not 3).

### Pitfall 5: Memory Bloat on Large Data
**What goes wrong:** Loading all DIAGNOSIS rows into memory (millions of rows) before filtering can exhaust RAM.
**Why it happens:** `collect()` materializes DuckDB query into in-memory tibble.
**How to avoid:** Use DuckDB lazy evaluation: filter to neoplasm codes (`DX_TYPE == "10" AND DX LIKE 'C%' OR DX LIKE 'D%'`) in SQL before `collect()`. Or collect only ID, DX, DX_DATE columns (D-09).
**Warning signs:** Script crashes with "cannot allocate vector of size X GB"; extremely slow collect() step.

## Code Examples

Verified patterns from canonical scripts:

### Load and Filter to Neoplasm Codes
```r
# Source: R/47_cancer_site_frequency.R lines 388-406
message("\nLoading DIAGNOSIS table (ICD-10 only, all patients)...")

dx_icd10 <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  select(ID, DX, DX_DATE) %>%
  collect()

message(glue("  Total ICD-10 DIAGNOSIS rows: {format(nrow(dx_icd10), big.mark=',')}"))

# Normalize codes
dx_icd10 <- dx_icd10 %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\.")))

# Filter to neoplasm codes only (C00-D49)
dx_cancer <- dx_icd10 %>%
  filter(str_detect(DX_norm, "^[CD]"))

message(glue("  Neoplasm codes (C/D): {format(nrow(dx_cancer), big.mark=',')} rows"))

# Classify
dx_cancer <- dx_cancer %>%
  mutate(category = classify_codes(DX_norm))
```

### Compute Date Metrics per Patient-Code
```r
# Source: Adapted from R/50-51 patterns
cancer_summary <- dx_cancer %>%
  group_by(ID, DX_norm, category) %>%
  summarise(
    # D-05: Count distinct non-NA dates
    unique_dates_total = n_distinct(DX_DATE[!is.na(DX_DATE)]),

    # D-03: 2+ distinct dates flag (integer 1/0)
    two_or_more_unique_dates = as.integer(n_distinct(DX_DATE[!is.na(DX_DATE)]) >= 2),

    # D-04: 7-day gap flag (integer 1/0)
    two_or_more_unique_dates_gt_7 = as.integer({
      dates <- DX_DATE[!is.na(DX_DATE)]
      if (length(unique(dates)) >= 2) {
        as.numeric(max(dates) - min(dates)) >= 7
      } else {
        FALSE
      }
    }),

    # D-06: Dates with >7 day separation (Claude's discretion: clinically useful counting)
    unique_dates_with_sep_gt_7 = {
      dates <- unique(sort(DX_DATE[!is.na(DX_DATE)]))
      if (length(dates) < 2) {
        0L
      } else {
        span <- as.numeric(max(dates) - min(dates))
        if (span < 7) {
          0L
        } else {
          # Count dates that are >= 7 days from earliest OR >= 7 days from latest
          earliest <- min(dates)
          latest <- max(dates)
          sum(as.numeric(dates - earliest) >= 7 | as.numeric(latest - dates) >= 7)
        }
      }
    },
    .groups = "drop"
  ) %>%
  # D-07: Ensure 0 for all metrics when no dates exist
  mutate(
    two_or_more_unique_dates = ifelse(unique_dates_total == 0, 0L, two_or_more_unique_dates),
    two_or_more_unique_dates_gt_7 = ifelse(unique_dates_total == 0, 0L, two_or_more_unique_dates_gt_7),
    unique_dates_with_sep_gt_7 = ifelse(unique_dates_total == 0, 0L, unique_dates_with_sep_gt_7)
  )
```

### Add Description Column
```r
# Source: Adapted from R/52 multi-source cascade + PREFIX_MAP
# Recommended format: "Category Name - CODE (details if available)"
cancer_summary <- cancer_summary %>%
  mutate(
    # Base description: category from PREFIX_MAP
    description = category,
    # Optionally: load Phase 39-41 RDS for code-level descriptions
    # Then: description = glue("{category} - {DX_norm} ({code_desc})") where code_desc is from RDS
    # For minimal version: category name alone is acceptable per D-10 discretion
  ) %>%
  select(ID, cancer_code = DX_norm, description,
         two_or_more_unique_dates, two_or_more_unique_dates_gt_7,
         unique_dates_total, unique_dates_with_sep_gt_7)
```

### Generate Minimal XLSX
```r
# Source: Adapted from R/47 but simplified (no fancy styling per D-18)
library(openxlsx2)

OUTPUT_PATH <- file.path(CONFIG$output_dir, "tables", "cancer_summary.xlsx")
dir.create(dirname(OUTPUT_PATH), showWarnings = FALSE, recursive = TRUE)

wb <- wb_workbook()
wb$add_worksheet("Cancer Summary")

# Row 1: Headers
headers <- c("ID", "cancer_code", "description", "two_or_more_unique_dates",
             "two_or_more_unique_dates_gt_7", "unique_dates_total", "unique_dates_with_sep_gt_7")
for (i in seq_along(headers)) {
  wb$add_data(sheet = "Cancer Summary", x = headers[i], start_row = 1, start_col = i)
}

# Row 2+: Data
wb$add_data(sheet = "Cancer Summary", x = as.data.frame(cancer_summary),
            start_row = 2, col_names = FALSE)

# Number formatting for integer columns (columns 4-7)
if (nrow(cancer_summary) > 0) {
  last_row <- 1 + nrow(cancer_summary)
  wb$add_numfmt(sheet = "Cancer Summary", dims = glue("D2:G{last_row}"), numfmt = "0")
}

# Column widths (optional, improves readability)
wb$set_col_widths(sheet = "Cancer Summary", cols = 1:7, widths = "auto")

# Save
wb$save(OUTPUT_PATH)
message(glue("Wrote {OUTPUT_PATH} ({nrow(cancer_summary)} rows)"))
```

### CSV Output
```r
# Source: Standard write.csv pattern
CSV_PATH <- file.path(CONFIG$output_dir, "tables", "cancer_summary.csv")
write.csv(cancer_summary, CSV_PATH, row.names = FALSE)
message(glue("Wrote {CSV_PATH}"))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual ICD-10 category mapping | PREFIX_MAP named vector (R/47) | Phase 47 (2026-05) | 53 categories, 309 prefix mappings; centralized maintenance |
| Base xlsx generation (xlsx package) | openxlsx2 | Project start (2026-03) | R4.0.0+ compatible; faster; no Java dependency |
| RDS backend | DuckDB lazy evaluation | Phase 30 (2026-04) | Memory-efficient for large DIAGNOSIS table queries |
| Logical TRUE/FALSE flags | Integer 1/0 encoding | Project convention | Excel-friendly; enables sum() aggregation |

**Deprecated/outdated:**
- xlsx package: No longer maintained; use openxlsx2 for all Excel generation
- In-memory tibble loading for large tables: Use DuckDB lazy evaluation where possible

## Open Questions

None — all ambiguities resolved via CONTEXT.md decisions and canonical script patterns.

## Environment Availability

**Trigger:** No external dependencies beyond project's existing R package ecosystem.

**Conclusion:** All required libraries (dplyr, stringr, glue, openxlsx2) already used in canonical scripts R/47, R/50-52. No new installations or external tools needed.

## Sources

### Primary (HIGH confidence)
- R/47_cancer_site_frequency.R (lines 1-702) - PREFIX_MAP, classify_codes(), neoplasm filtering pattern, openxlsx2 styling
- R/50_cancer_site_confirmation.R (lines 1-658) - 2-date confirmation logic, distinct() deduplication pattern, date aggregation
- R/51_cancer_site_confirmation_7day.R (lines 1-661) - 7-day gap calculation, date span logic
- R/52_all_codes_resolved.R (lines 1-793) - Multi-source description cascade pattern (RDS artifacts, hardcoded, config comments)
- R/00_config.R (lines 1-100) - CONFIG structure, output_dir, USE_DUCKDB flag
- R/01_load_pcornet.R (lines 1-723) - get_pcornet_table() pattern, DuckDB connection management
- 06-CONTEXT.md (Phase 6 user decisions) - All D-01 through D-18 requirements

### Secondary (MEDIUM confidence)
- None required — all patterns verified in canonical code

### Tertiary (LOW confidence)
- None — no external research needed

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All libraries already in use in canonical scripts
- Architecture: HIGH - Patterns directly copied from R/47, R/50-52 (working code)
- Pitfalls: HIGH - Derived from actual code patterns in R/50-51 (distinct() timing, NA handling, integer encoding)
- unique_dates_with_sep_gt_7 interpretation: MEDIUM - User gave Claude discretion; recommended approach is clinically meaningful but not verified

**Research date:** 2026-05-21
**Valid until:** 90 days (2026-08-19) — stable domain, no fast-moving dependencies
