# Phase 42: Treatment Codes Resolved XLSX (All Types) - Research

**Researched:** 2026-05-05
**Domain:** R xlsx manipulation, data verification, treatment code classification
**Confidence:** HIGH

## Summary

Phase 42 extends the chemotherapy_codes_resolved.xlsx pattern to radiation, SCT, immunotherapy, and supportive care treatment types. The task involves reading classified codes from combined_unmatched_report.xlsx, extracting per-category subsets, and writing individual xlsx files with consistent structure. Additionally, the phase requires verification that chemotherapy_codes_resolved.xlsx matches the source data.

This is a straightforward data extraction and transformation task using established patterns from Phase 41 (R/41_combine_reports.R). The core technical challenge is reading multi-sheet xlsx workbooks, filtering by classification, and writing styled xlsx output — all capabilities proven in the existing codebase.

**Primary recommendation:** Use openxlsx2 wb_load() to read combined_unmatched_report.xlsx, filter by classification, and apply the existing write pattern from Phase 41 with per-category color schemes. Verification is a simple row count and column match between chemotherapy sheet and resolved file.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** One xlsx file per treatment type, mirroring chemotherapy_codes_resolved.xlsx format exactly (data sheet + Notes sheet)
- **D-02:** Files to produce: `radiation_codes_resolved.xlsx`, `sct_codes_resolved.xlsx`, `immunotherapy_codes_resolved.xlsx`, `supportive_care_codes_resolved.xlsx`
- **D-03:** Each file's data sheet has columns: Code, Meaning, Code Type, Source Table, Records, Patients
- **D-04:** Each file has a "Notes" sheet documenting source provenance
- **D-05:** Use API descriptions from combined_unmatched_report.xlsx as-is, renamed to "Meaning" column for consistency with chemotherapy file format
- **D-06:** No manual curation step required — API descriptions are sufficient
- **D-07:** Cross-check that the 203 codes in chemotherapy_codes_resolved.xlsx match the 203 codes in the Chemotherapy sheet of combined_unmatched_report.xlsx
- **D-08:** Flag any mismatches in Records/Patients counts between the two files
- **D-09:** Output verification results (pass/fail + any discrepancies) to console and optionally a verification summary
- **D-10:** Include Supportive Care (171 codes) as its own resolved xlsx file alongside active treatment types

### Claude's Discretion
- Styling/formatting of xlsx files (color scheme, fonts, column widths)
- Whether to produce a single R script or one per type
- Verification output format (console message vs separate report file)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope

</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| openxlsx2 | 1.26 (2026-04-17) | xlsx reading and writing | Modern rewrite of openxlsx; used in Phase 41 (41_combine_reports.R); `wb_load()` for reading, `wb_workbook()` for writing |
| dplyr | 1.2.0+ | Data transformation | Project standard (tidyverse ecosystem); filtering, selecting, arranging operations |
| glue | 1.8.0 | String interpolation | Project standard; logging and message formatting |
| stringr | 1.5.1+ | String operations (optional) | Project standard; may be needed for column name operations |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| readr | 2.2.0+ | CSV fallback (optional) | If RDS artifacts are missing and need to parse CSV exports |
| tibble | 3.2.1+ | Modern data frames | Included in tidyverse; better printing for verification output |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| openxlsx2 | openxlsx (original) | openxlsx2 is project standard (used in Phase 41); no reason to switch |
| openxlsx2 | writexl + readxl | writexl lacks styling capabilities needed to match chemotherapy_codes_resolved.xlsx format; readxl is read-only |
| wb_load() | read_xlsx() | read_xlsx() is simpler but returns only data frames; wb_load() needed to inspect sheet names and structure |

**Installation:**
```bash
# In R console (already in project renv)
# openxlsx2, dplyr, glue should already be available from Phase 41
library(openxlsx2)
library(dplyr)
library(glue)
```

**Version verification:**
```bash
# In R console
packageVersion("openxlsx2")  # Should be >= 1.26
```

## Architecture Patterns

### Recommended Project Structure
```
R/
├── 42_treatment_codes_resolved.R   # Main script (create per-type xlsx files + verification)
└── 00_config.R                     # Shared configuration (already exists)

output/
├── combined_unmatched_report.xlsx  # Source (Phase 41)
├── chemotherapy_codes_resolved.xlsx # Template/verification target
├── radiation_codes_resolved.xlsx    # NEW
├── sct_codes_resolved.xlsx          # NEW
├── immunotherapy_codes_resolved.xlsx # NEW
└── supportive_care_codes_resolved.xlsx # NEW
```

### Pattern 1: Read Multi-Sheet XLSX Workbook
**What:** Load xlsx file and extract sheet names and data from specific sheets
**When to use:** Need to read from combined_unmatched_report.xlsx per-category sheets
**Example:**
```r
# Source: openxlsx2 official docs (https://janmarvin.github.io/openxlsx2/reference/wb_load.html)
library(openxlsx2)
library(dplyr)

# Load entire workbook to inspect sheet names
wb <- wb_load("combined_unmatched_report.xlsx")
sheet_names <- wb$sheet_names
message(glue("Found {length(sheet_names)} sheets: {paste(sheet_names, collapse = ', ')}"))

# Read specific sheet as data frame
radiation_df <- wb_to_df(wb, sheet = "Radiation")
# OR simpler direct read
radiation_df <- read_xlsx("combined_unmatched_report.xlsx", sheet = "Radiation")

# Expected structure from Phase 41:
# Columns: code, description, code_type, source_table, n_records, n_patients, classification, heuristic_type, lookup_status
```

### Pattern 2: Write Styled XLSX with Multiple Sheets
**What:** Create workbook with data sheet + notes sheet, apply color scheme and formatting
**When to use:** Creating per-type resolved xlsx files matching chemotherapy_codes_resolved.xlsx format
**Example:**
```r
# Source: R/41_combine_reports.R (project codebase)
library(openxlsx2)
library(glue)

# Color scheme from Phase 41
TREATMENT_TYPE_COLORS <- list(
  Radiation = list(fill = "FFDDF4E1", font = "FF274E13"),   # light green / dark green
  SCT = list(fill = "FFFFF4D6", font = "FF7F6000"),         # light yellow / dark olive
  Immunotherapy = list(fill = "FFE8DCF4", font = "FF4C1D7A"), # light purple / dark purple
  `Supportive Care` = list(fill = "FFD5F5F0", font = "FF0E6655") # light teal / dark teal
)

# Create workbook
wb <- wb_workbook()

# Add data sheet
sheet_name <- "Radiation Codes"
wb$add_worksheet(sheet_name)

# Title row (with code count)
n_codes <- nrow(radiation_df)
wb$add_data(sheet = sheet_name,
            x = glue("Radiation Codes ({n_codes} codes)"),
            start_row = 1, start_col = 1)
wb$add_font(sheet = sheet_name, dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = sheet_name, dims = "A1:F1")

# Headers row 2
headers <- c("Code", "Meaning", "Code Type", "Source Table", "Records", "Patients")
for (i in seq_along(headers)) {
  wb$add_data(sheet = sheet_name, x = headers[i],
              start_row = 2, start_col = i)
}
wb$add_fill(sheet = sheet_name, dims = "A2:F2", color = wb_color("FF374151"))
wb$add_font(sheet = sheet_name, dims = "A2:F2",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Data rows (bulk write)
write_df <- data.frame(
  Code = radiation_df$code,
  Meaning = ifelse(is.na(radiation_df$description), "", radiation_df$description),
  Code_Type = radiation_df$code_type,
  Source_Table = radiation_df$source_table,
  Records = radiation_df$n_records,
  Patients = radiation_df$n_patients,
  stringsAsFactors = FALSE
)
wb$add_data(sheet = sheet_name, x = write_df, start_row = 3, col_names = FALSE)

# Styling (range-based, not per-cell)
last_row <- 2 + nrow(radiation_df)
code_dims <- glue("A3:A{last_row}")
fill_color <- TREATMENT_TYPE_COLORS$Radiation$fill
font_color <- TREATMENT_TYPE_COLORS$Radiation$font

wb$add_fill(sheet = sheet_name, dims = code_dims, color = wb_color(fill_color))
wb$add_font(sheet = sheet_name, dims = code_dims,
            name = "Calibri", size = 10, bold = TRUE, color = wb_color(font_color))

# Number formatting
num_dims <- glue("E3:F{last_row}")
wb$add_numfmt(sheet = sheet_name, dims = num_dims, numfmt = "#,##0")

# Column widths
wb$set_col_widths(sheet = sheet_name, cols = 1:6, widths = c(15, 45, 12, 15, 10, 10))

# Add Notes sheet
wb$add_worksheet("Notes")
notes_text <- paste0(
  "Data Source: combined_unmatched_report.xlsx (Phase 41)\n",
  "Descriptions: NLM/RxNorm API lookups\n",
  "Generated: ", Sys.Date(), "\n",
  "Classification: Radiation therapy codes"
)
wb$add_data(sheet = "Notes", x = notes_text, start_row = 1, start_col = 1)

# Save
wb$save("radiation_codes_resolved.xlsx")
```

### Pattern 3: Data Verification Between XLSX Sources
**What:** Compare row counts and column values between two xlsx files
**When to use:** Verifying chemotherapy_codes_resolved.xlsx matches combined_unmatched_report.xlsx Chemotherapy sheet
**Example:**
```r
# Source: research synthesis (common verification pattern)
library(openxlsx2)
library(dplyr)
library(glue)

# Read chemotherapy sheet from combined report
chemo_source <- read_xlsx("combined_unmatched_report.xlsx", sheet = "Chemotherapy")

# Read chemotherapy resolved file (sheet name unknown, read first sheet or detect)
chemo_resolved_wb <- wb_load("chemotherapy_codes_resolved.xlsx")
sheet_name <- chemo_resolved_wb$sheet_names[1]  # Likely "Chemotherapy Codes" or similar
chemo_resolved <- wb_to_df(chemo_resolved_wb, sheet = sheet_name)

# Verification: row counts
message("=== Chemotherapy Verification ===")
message(glue("Source (combined): {nrow(chemo_source)} codes"))
message(glue("Resolved file:     {nrow(chemo_resolved)} codes"))

if (nrow(chemo_source) != nrow(chemo_resolved)) {
  message("❌ FAIL: Row count mismatch")
} else {
  message("✅ PASS: Row count matches")
}

# Verification: code set match
source_codes <- sort(chemo_source$code)
resolved_codes <- sort(chemo_resolved$Code)  # Note: column name may differ (case)

missing_in_resolved <- setdiff(source_codes, resolved_codes)
extra_in_resolved <- setdiff(resolved_codes, source_codes)

if (length(missing_in_resolved) > 0) {
  message(glue("❌ FAIL: {length(missing_in_resolved)} codes in source but not in resolved"))
  message("Missing codes: ", paste(head(missing_in_resolved, 10), collapse = ", "))
}

if (length(extra_in_resolved) > 0) {
  message(glue("❌ FAIL: {length(extra_in_resolved)} codes in resolved but not in source"))
  message("Extra codes: ", paste(head(extra_in_resolved, 10), collapse = ", "))
}

if (length(missing_in_resolved) == 0 && length(extra_in_resolved) == 0) {
  message("✅ PASS: Code sets match exactly")
}

# Verification: Records/Patients counts (join on code)
verification_df <- chemo_source %>%
  select(code, n_records_source = n_records, n_patients_source = n_patients) %>%
  full_join(
    chemo_resolved %>%
      select(Code, n_records_resolved = Records, n_patients_resolved = Patients),
    by = c("code" = "Code")
  ) %>%
  mutate(
    records_match = n_records_source == n_records_resolved,
    patients_match = n_patients_source == n_patients_resolved
  )

mismatches <- verification_df %>%
  filter(!records_match | !patients_match)

if (nrow(mismatches) > 0) {
  message(glue("❌ FAIL: {nrow(mismatches)} codes have count mismatches"))
  print(head(mismatches, 10))
} else {
  message("✅ PASS: All Records/Patients counts match")
}
```

### Anti-Patterns to Avoid
- **Cell-by-cell xlsx writes:** Phase 41 shows bulk data write with `wb$add_data(x = data.frame)` is 10-100x faster than per-cell writes
- **Hardcoded sheet names without validation:** Use `wb$sheet_names` to discover sheet names programmatically
- **Ignoring column name case mismatches:** combined_unmatched_report.xlsx uses lowercase (`code`, `description`), resolved files use title case (`Code`, `Meaning`) — explicitly map column names
- **Missing Notes sheet:** D-04 requires Notes sheet; don't skip it

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Reading multi-sheet xlsx | CSV exports + manual splits | `openxlsx2::wb_load()` + `wb_to_df()` | Native xlsx reading preserves sheet structure; CSV export loses multi-sheet organization and requires manual reconstruction |
| xlsx styling | Base R write.csv + manual Excel formatting | `openxlsx2` wb_add_fill/font/numfmt | Phase 41 pattern handles styled output programmatically; manual Excel formatting breaks reproducibility and automation |
| Verification logic | Manual Excel comparison | R script comparing data frames | Automated verification enables regression testing; manual comparison error-prone for 203 codes |

**Key insight:** openxlsx2 provides complete read/write/style capabilities. Don't fall back to CSV intermediate formats or manual Excel steps.

## Common Pitfalls

### Pitfall 1: Column Name Case Mismatches
**What goes wrong:** combined_unmatched_report.xlsx uses lowercase column names (`code`, `description`, `n_records`, `n_patients`), but resolved xlsx format requires title case (`Code`, `Meaning`, `Records`, `Patients`)
**Why it happens:** Phase 41 writes combined report with tidyverse conventions (lowercase snake_case), but resolved files match a different style (title case)
**How to avoid:** Explicitly rename columns when creating write_df data frame:
```r
write_df <- data.frame(
  Code = source_df$code,           # lowercase -> title case
  Meaning = source_df$description, # explicit rename
  Code_Type = source_df$code_type,
  Source_Table = source_df$source_table,
  Records = source_df$n_records,   # lowercase -> title case
  Patients = source_df$n_patients, # lowercase -> title case
  stringsAsFactors = FALSE
)
```
**Warning signs:** Verification failures due to "column not found" errors, or xlsx files with lowercase headers that don't match template

### Pitfall 2: Sheet Name Detection Assumption
**What goes wrong:** Assuming chemotherapy_codes_resolved.xlsx has a sheet named "Chemotherapy" when it might be "Chemotherapy Codes" or "Data"
**Why it happens:** File created manually or by earlier script without documentation
**How to avoid:** Always use `wb_load()` and inspect `$sheet_names` before reading:
```r
wb <- wb_load("chemotherapy_codes_resolved.xlsx")
message(glue("Sheets found: {paste(wb$sheet_names, collapse = ', ')}"))
data_sheet <- wb$sheet_names[1]  # First non-Notes sheet
chemo_resolved <- wb_to_df(wb, sheet = data_sheet)
```
**Warning signs:** "sheet not found" errors during verification

### Pitfall 3: Missing Title Row with Code Count
**What goes wrong:** D-03 shows columns in row 2 but doesn't explicitly mention title row with count in row 1 — might accidentally omit it
**Why it happens:** Requirement says "columns: Code, Meaning, ..." but doesn't diagram full file structure
**How to avoid:** Study Phase 41 pattern which has title row (row 1), headers (row 4), data starting row 5. Resolved files likely similar: title row 1, headers row 2, data row 3+. Verify against chemotherapy_codes_resolved.xlsx structure.
**Warning signs:** Resolved files missing descriptive title, or verification fails because row numbers don't align

### Pitfall 4: Wrong Color Scheme Application
**What goes wrong:** Applying Chemotherapy colors (blue) to Radiation file
**Why it happens:** Copy-paste from Phase 41 chemotherapy block without updating TREATMENT_TYPE_COLORS lookup
**How to avoid:** Extract color scheme as data structure keyed by category:
```r
category <- "Radiation"  # or "SCT", "Immunotherapy", "Supportive Care"
fill_color <- TREATMENT_TYPE_COLORS[[category]]$fill
font_color <- TREATMENT_TYPE_COLORS[[category]]$font
```
**Warning signs:** Visual inspection shows wrong color in xlsx output

### Pitfall 5: Verification False Positives from Skip Rows
**What goes wrong:** Reading chemotherapy_codes_resolved.xlsx without accounting for title/header rows reads garbage from row 1
**Why it happens:** read_xlsx() defaults to detecting headers, but styled xlsx files with titles break auto-detection
**How to avoid:** Specify skip parameter or use wb_to_df with startRow:
```r
# If title in row 1, headers in row 2, data starts row 3
chemo_resolved <- read_xlsx("chemotherapy_codes_resolved.xlsx",
                             sheet = 1,
                             skip = 1)  # Skip title row, read headers from row 2
# OR
chemo_resolved <- wb_to_df(wb, sheet = 1, start_row = 2, col_names = TRUE)
```
**Warning signs:** First row of data frame has title text instead of code values

## Code Examples

Verified patterns from official sources:

### Reading Combined Report Sheet
```r
# Source: openxlsx2 documentation + project Phase 41 structure
library(openxlsx2)
library(dplyr)

# Read specific treatment type sheet
radiation_raw <- read_xlsx("combined_unmatched_report.xlsx", sheet = "Radiation")

# Expected columns from Phase 41 (lines 65-81 of 41_combine_reports.R):
# code, code_type, source_table, description, n_records, n_patients,
# classification, heuristic_type, lookup_status

# Filter if needed (should already be filtered by sheet)
stopifnot(all(radiation_raw$classification == "Radiation"))

# Sort by patient count descending (common pattern)
radiation_sorted <- radiation_raw %>%
  arrange(desc(n_patients))
```

### Writing Per-Type Resolved XLSX
```r
# Source: Synthesis of R/41_combine_reports.R pattern adapted for resolved format
library(openxlsx2)
library(glue)

write_resolved_xlsx <- function(df, category, output_path) {
  # Color scheme
  TREATMENT_TYPE_COLORS <- list(
    Chemotherapy = list(fill = "FFDCEEFB", font = "FF0B5394"),
    Radiation = list(fill = "FFDDF4E1", font = "FF274E13"),
    SCT = list(fill = "FFFFF4D6", font = "FF7F6000"),
    Immunotherapy = list(fill = "FFE8DCF4", font = "FF4C1D7A"),
    `Supportive Care` = list(fill = "FFD5F5F0", font = "FF0E6655")
  )

  fill_color <- TREATMENT_TYPE_COLORS[[category]]$fill
  font_color <- TREATMENT_TYPE_COLORS[[category]]$font
  sheet_name <- paste(category, "Codes")

  wb <- wb_workbook()
  wb$add_worksheet(sheet_name)

  # Row 1: Title with count
  n_codes <- nrow(df)
  wb$add_data(sheet = sheet_name,
              x = glue("{category} Codes ({n_codes} codes)"),
              start_row = 1, start_col = 1)
  wb$add_font(sheet = sheet_name, dims = "A1",
              name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
  wb$merge_cells(sheet = sheet_name, dims = "A1:F1")

  # Row 2: Headers
  headers <- c("Code", "Meaning", "Code Type", "Source Table", "Records", "Patients")
  for (i in seq_along(headers)) {
    wb$add_data(sheet = sheet_name, x = headers[i], start_row = 2, start_col = i)
  }
  wb$add_fill(sheet = sheet_name, dims = "A2:F2", color = wb_color("FF374151"))
  wb$add_font(sheet = sheet_name, dims = "A2:F2",
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

  # Row 3+: Data
  write_df <- data.frame(
    Code = df$code,
    Meaning = ifelse(is.na(df$description), "", df$description),
    Code_Type = df$code_type,
    Source_Table = df$source_table,
    Records = df$n_records,
    Patients = df$n_patients,
    stringsAsFactors = FALSE
  )
  wb$add_data(sheet = sheet_name, x = write_df, start_row = 3, col_names = FALSE)

  # Styling
  last_row <- 2 + nrow(df)
  code_dims <- glue("A3:A{last_row}")
  wb$add_fill(sheet = sheet_name, dims = code_dims, color = wb_color(fill_color))
  wb$add_font(sheet = sheet_name, dims = code_dims,
              name = "Calibri", size = 10, bold = TRUE, color = wb_color(font_color))

  num_dims <- glue("E3:F{last_row}")
  wb$add_numfmt(sheet = sheet_name, dims = num_dims, numfmt = "#,##0")

  wb$set_col_widths(sheet = sheet_name, cols = 1:6, widths = c(15, 45, 12, 15, 10, 10))

  # Notes sheet
  wb$add_worksheet("Notes")
  notes_text <- paste0(
    "Data Source: combined_unmatched_report.xlsx (Phase 41)\n",
    "Descriptions: NLM/RxNorm API lookups via Phase 39-40\n",
    "Generated: ", Sys.Date(), "\n",
    "Classification: ", category, " codes"
  )
  wb$add_data(sheet = "Notes", x = notes_text, start_row = 1, start_col = 1)

  wb$save(output_path)
  message(glue("Wrote {output_path} ({n_codes} codes)"))
}

# Usage
radiation_df <- read_xlsx("combined_unmatched_report.xlsx", sheet = "Radiation")
write_resolved_xlsx(radiation_df, "Radiation", "radiation_codes_resolved.xlsx")
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| openxlsx (original) | openxlsx2 | 2024+ (openxlsx2 1.0 released 2023, matured by 2024) | openxlsx2 is a modern rewrite with cleaner API; project adopted in Phase 41 |
| Cell-by-cell xlsx writes | Bulk data frame writes + range styling | Phase 41 (2026-05) | 10-100x performance improvement; 41_combine_reports.R uses bulk pattern |
| Manual Excel formatting | Programmatic openxlsx2 styling | Phase 41 | Reproducibility; automated styling via code |

**Deprecated/outdated:**
- openxlsx (original): Still maintained but openxlsx2 is the modern choice for new projects
- xlsx package (Java-based): Deprecated, heavy dependency on rJava

## Open Questions

1. **What is the exact structure of chemotherapy_codes_resolved.xlsx?**
   - What we know: Has "Code, Meaning, Code Type, Source Table, Records, Patients" columns (D-03), has Notes sheet (D-04)
   - What's unclear: Sheet names, title row format, header row position, data start row
   - Recommendation: Use wb_load() to inspect structure before verification; assume same pattern as Phase 41 (title row 1, headers row 4, data row 5+) but verify

2. **Should verification output go to console only or to a file?**
   - What we know: D-09 says "console and optionally a verification summary" — console mandatory, file optional
   - What's unclear: User preference for file output
   - Recommendation: Always output to console; optionally write verification_summary.txt if any failures detected (discretion per CONTEXT.md)

3. **Are there any missing treatment categories in combined_unmatched_report.xlsx?**
   - What we know: Phase 41 creates sheets for Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care, Unrelated (lines 39-40 of 41_combine_reports.R)
   - What's unclear: Whether all categories have >0 codes (Phase 41 skips empty categories at line 284)
   - Recommendation: Check sheet existence before reading; skip gracefully if category has 0 codes (with warning message)

## Environment Availability

> Phase 42 depends on R packages and existing xlsx files but no external tools/services beyond R itself.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| R | All operations | ✓ (project standard) | 4.4.2+ | — |
| openxlsx2 | xlsx read/write | ✓ (Phase 41 renv) | 1.26 | — |
| dplyr | Data transformation | ✓ (project standard) | 1.2.0+ | — |
| glue | String interpolation | ✓ (project standard) | 1.8.0 | — |
| combined_unmatched_report.xlsx | Source data | ✓ (Phase 41 output) | N/A | Re-run R/41_combine_reports.R |
| chemotherapy_codes_resolved.xlsx | Verification target | ✓ (project root) | N/A | Manual creation if missing (blocks verification, not creation of other types) |

**Missing dependencies with no fallback:**
None — all required packages are project standard and should be in renv.

**Missing dependencies with fallback:**
- If combined_unmatched_report.xlsx is missing: Re-run R/41_combine_reports.R (requires RDS artifacts from Phase 39-40)
- If chemotherapy_codes_resolved.xlsx is missing: Verification cannot complete, but creation of other type files can still proceed

## Sources

### Primary (HIGH confidence)
- [openxlsx2 CRAN page](https://cran.r-project.org/web/packages/openxlsx2/index.html) - version 1.26, published 2026-04-17
- [openxlsx2 official documentation](https://janmarvin.github.io/openxlsx2/) - read/write/edit xlsx files
- [openxlsx2 wb_load reference](https://janmarvin.github.io/openxlsx2/reference/wb_load.html) - loading existing xlsx files
- R/41_combine_reports.R (project codebase) - Phase 41 implementation showing openxlsx2 patterns, color schemes, styling
- R/00_config.R lines 412-600 (project codebase) - TREATMENT_CODES list with category vectors

### Secondary (MEDIUM confidence)
- Phase 42 CONTEXT.md (project planning) - user decisions and locked requirements
- Phase 41 STATE.md context - SCT classification remapping, cross-source RDS harmonization pattern

### Tertiary (LOW confidence)
None

## Metadata

**Confidence breakdown:**
- Standard stack (openxlsx2, dplyr, glue): HIGH - All used in Phase 41, versions verified from CRAN
- Architecture patterns (read multi-sheet, write styled xlsx): HIGH - Direct implementation examples from Phase 41 codebase
- Verification pattern: MEDIUM - Synthesized from standard R data frame comparison, not project-specific precedent
- File structure assumptions (chemotherapy_codes_resolved.xlsx): LOW - Inferred from requirements, not verified by reading actual file (binary xlsx cannot be read in text mode)

**Research date:** 2026-05-05
**Valid until:** 2026-06-05 (30 days — openxlsx2 is stable, R ecosystem slow-moving)
