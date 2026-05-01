# Phase 38: Chemo Treatment Inventory by Source Table - Research

**Researched:** 2026-05-01
**Domain:** R xlsx output generation, PCORnet CDM table querying, treatment code aggregation
**Confidence:** HIGH

## Summary

Phase 38 creates an aggregate inventory of all treatment-related records across PCORnet CDM tables, producing a styled xlsx workbook similar to the existing csv_to_xlsx.py pattern. The phase covers 4 treatment types (chemotherapy, radiation, SCT, immunotherapy) queried from all patients in the raw data (not restricted to HL cohort), with output broken down by source table (PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, DIAGNOSIS, ENCOUNTER, TUMOR_REGISTRY).

Research focused on R xlsx generation packages with full styling support (matching Python's openpyxl patterns), PCORnet CDM table structures, and code aggregation strategies. All treatment code lists already exist in R/00_config.R TREATMENT_CODES (Phase 9 expansion). The script will be lightweight — sources only 00_config.R + 01_load_pcornet.R, bypassing the cohort pipeline for fast execution.

**Primary recommendation:** Use openxlsx2 (v1.24+) for xlsx generation due to complete styling API without Java dependency, matching csv_to_xlsx.py visual patterns (title/subtitle, colored pills, frozen panes, header fills). Aggregate counts via group_by(code, source_table, treatment_type) with bind_rows() across all source queries.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Treatment Type Scope (D-01, D-02):**
- Cover all 4 treatment types: chemotherapy, radiation, SCT, and immunotherapy (CAR T-cell)
- Use existing TREATMENT_CODES lists in 00_config.R (chemo_*, radiation_*, sct_*, cart_icd10pcs_prefixes)
- Each treatment type gets its own sheet in the output xlsx

**Output Granularity (D-03):**
- Aggregate summary only — code frequencies and counts per source table per treatment type
- No patient-level detail (no patient IDs in output)

**Cohort Scope (D-04):**
- Query all patients in the raw PCORnet extract, regardless of cohort status
- Script sources 00_config.R + 01_load_pcornet.R but does NOT run the cohort pipeline

**Output Format (D-05, D-06, D-07):**
- Produce a styled xlsx workbook matching csv_to_xlsx.py visual patterns: title/subtitle row, "By Source Table" summary section with treatment-type colored pills, "Detailed Codes" section with code/source table/count/% columns, frozen panes, header fills
- No HIPAA small-cell suppression — show exact counts (internal exploratory tool)
- Show raw code values only (no human-readable descriptions)

**Code Discovery (D-08):**
- Include unknown treatment codes not in our TREATMENT_CODES lists
- Use broad CPT/HCPCS range heuristics to identify potentially missed codes within treatment code families (e.g., 96xxx for chemo admin, 77xxx for radiation, 38xxx for transplant, J-codes for chemo drugs)
- Flag these as "Unmatched" in a separate section per sheet

**Script & Packaging (D-09, D-10):**
- Script named R/38_treatment_inventory.R following existing numbering convention
- Sources only R/00_config.R and R/01_load_pcornet.R — lightweight dependency chain

### Claude's Discretion

- xlsx package selection (openxlsx2 recommended for full styling support without Java dependency)
- Treatment-type color scheme for xlsx pills (analogous to CATEGORY_COLORS in csv_to_xlsx.py but for treatment types instead of payer categories)
- Exact CPT/HCPCS range boundaries for the "unknown code discovery" heuristic
- Internal function organization within R/38_treatment_inventory.R
- How to handle TUMOR_REGISTRY date columns (DT_CHEMO, DT_RAD, DT_HTE) as treatment evidence vs. the coded records in other tables

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| openxlsx2 | 1.24+ | xlsx file creation with full styling | Modern rewrite of openxlsx; complete styling API (cell fills, fonts, borders, frozen panes) without Java dependency; active development (CRAN Apr 2026) |
| dplyr | 1.2.0+ | Data aggregation and transformation | Already in project stack; group_by + summarise for code frequency aggregation |
| stringr | 1.5.1+ | String matching for code detection | Already in project stack; str_starts() for ICD-10-PCS prefix matching, str_detect() for CPT/HCPCS range heuristics |
| glue | 1.8.0 | String formatting for logging | Already in project stack; readable console messages during execution |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| tidyr | 1.3.0+ | Reshaping for "By Source Table" summary | pivot_wider() if summary section needs tabular layout (1 row per treatment type, columns for each source table count) |
| forcats | 1.0.0+ | Treatment type ordering | fct_relevel() to control sheet order (chemo, radiation, SCT, immunotherapy) and color mapping |
| purrr | 1.0.2+ | Iteration over treatment types | map() if writing all 4 sheets in a loop rather than manually |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| openxlsx2 | writexl | Faster (2x performance) but NO styling support — cannot replicate csv_to_xlsx.py visual patterns (no cell fills, no colored pills, no frozen panes) |
| openxlsx2 | openxlsx (original) | Same styling features but deprecated (no longer under active development per CRAN); openxlsx2 is the modern successor |
| openxlsx2 | xlsx | Requires Java runtime (rJava dependency) — adds complexity on HiPerGator; slower than openxlsx2 |

**Installation:**
```bash
# In R console (interactive HiPerGator session)
install.packages("openxlsx2")
renv::snapshot()  # Update renv.lock
```

**Version verification:**
openxlsx2 1.24 published to CRAN 2026-04-17 (verified via CRAN package page 2026-05-01). This is the latest stable release with full styling API.

## Architecture Patterns

### Recommended Script Structure
```
R/38_treatment_inventory.R
├── Section 1: Setup & Configuration
│   ├── source("R/00_config.R")
│   ├── source("R/01_load_pcornet.R")
│   └── library(openxlsx2, dplyr, stringr, glue)
├── Section 2: Treatment Type Configuration
│   ├── TREATMENT_TYPE_COLORS (4 colors for pills)
│   └── CPT_HCPCS_RANGES (heuristic boundaries for unknown codes)
├── Section 3: Code Extraction Functions (1 per treatment type)
│   ├── extract_chemo_codes()
│   ├── extract_radiation_codes()
│   ├── extract_sct_codes()
│   └── extract_immunotherapy_codes()
├── Section 4: Aggregation & Enrichment
│   ├── aggregate_by_source_table() -- group_by(code, source_table)
│   └── detect_unknown_codes() -- apply CPT/HCPCS heuristics
├── Section 5: xlsx Writing Functions
│   ├── write_treatment_sheet() -- generic sheet writer
│   └── apply_treatment_styles() -- cell fills, fonts, frozen panes
├── Section 6: Main Execution
│   ├── Call all 4 extract functions
│   ├── Write 4 sheets to workbook
│   └── Save to output/treatment_inventory.xlsx
└── Section 7: Logging & Summary
    └── Console summary of counts per treatment type
```

### Pattern 1: Multi-Table Code Extraction (Chemo Example)

**What:** Query 7 PCORnet tables for chemo evidence codes, bind results, aggregate by source table.

**When to use:** Each treatment type needs to query multiple tables with different code columns (PX, RXNORM_CUI, DX, DRG).

**Example:**
```r
# Source: R/03_cohort_predicates.R Section 2 (has_chemo pattern), R/10_treatment_payer.R lines 96-99
extract_chemo_codes <- function() {
  # 1. PROCEDURES: CPT/HCPCS, ICD-9-CM, ICD-10-PCS, revenue
  px_chemo <- get_pcornet_table("PROCEDURES") %>%
    filter(
      (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) |
      (PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9) |
      (PX_TYPE == "10" & str_starts(PX, paste0(TREATMENT_CODES$chemo_icd10pcs_prefixes, collapse = "|"))) |
      (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$chemo_revenue)
    ) %>%
    select(code = PX, code_type = PX_TYPE) %>%
    mutate(source_table = "PROCEDURES")

  # 2. PRESCRIBING: RXNORM
  rx_chemo <- get_pcornet_table("PRESCRIBING") %>%
    filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
    select(code = RXNORM_CUI) %>%
    mutate(source_table = "PRESCRIBING", code_type = "RXNORM")

  # 3. DISPENSING: RXNORM (Phase 9 expansion)
  disp_chemo <- get_pcornet_table("DISPENSING") %>%
    filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
    select(code = RXNORM_CUI) %>%
    mutate(source_table = "DISPENSING", code_type = "RXNORM")

  # 4. MED_ADMIN: RXNORM (Phase 9 expansion)
  medadm_chemo <- get_pcornet_table("MED_ADMIN") %>%
    filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
    select(code = RXNORM_CUI) %>%
    mutate(source_table = "MED_ADMIN", code_type = "RXNORM")

  # 5. DIAGNOSIS: ICD-10-CM Z/V codes (Phase 9 expansion)
  dx_chemo <- get_pcornet_table("DIAGNOSIS") %>%
    filter(
      (DX_TYPE == "10" & DX %in% TREATMENT_CODES$chemo_dx_icd10) |
      (DX_TYPE == "09" & DX %in% TREATMENT_CODES$chemo_dx_icd9)
    ) %>%
    select(code = DX, code_type = DX_TYPE) %>%
    mutate(source_table = "DIAGNOSIS")

  # 6. ENCOUNTER: MS-DRG codes (Phase 9 expansion)
  enc_chemo <- get_pcornet_table("ENCOUNTER") %>%
    filter(DRG %in% TREATMENT_CODES$chemo_drg) %>%
    select(code = DRG) %>%
    mutate(source_table = "ENCOUNTER", code_type = "DRG")

  # 7. TUMOR_REGISTRY: Date columns as evidence (NOT coded records)
  # Decision: Count presence of non-NA dates, NOT individual code values
  # TUMOR_REGISTRY_ALL combines TR1 (CHEMO_START_DATE_SUMMARY), TR2/TR3 (DT_CHEMO)
  tr_chemo <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
    filter(!is.na(DT_CHEMO) | !is.na(CHEMO_START_DATE_SUMMARY)) %>%
    summarise(n = n()) %>%
    mutate(code = "DATE_EVIDENCE", source_table = "TUMOR_REGISTRY", code_type = "DATE")

  # Bind all sources and aggregate
  bind_rows(px_chemo, rx_chemo, disp_chemo, medadm_chemo, dx_chemo, enc_chemo, tr_chemo) %>%
    group_by(code, source_table, code_type) %>%
    summarise(n = n(), .groups = "drop") %>%
    mutate(treatment_type = "Chemotherapy")
}
```

### Pattern 2: Unknown Code Detection (CPT/HCPCS Heuristics)

**What:** Use broad code range patterns to find treatment-adjacent codes NOT in TREATMENT_CODES lists.

**When to use:** Per D-08, flag potentially missed codes for manual review.

**Example:**
```r
# CPT/HCPCS range heuristics (derived from CMS code families)
CPT_HCPCS_RANGES <- list(
  chemo = list(
    j_codes = "^J9[0-9]{3}$",         # J9000-J9999 (injectable chemo drugs)
    admin_codes = "^96[4-5][0-9]{2}$" # 96400-96599 (chemo administration)
  ),
  radiation = list(
    planning = "^770[0-9]{2}$",       # 77000-77099 (planning, not treatment)
    delivery = "^774[0-9]{2}$"        # 77400-77499 (treatment delivery)
  ),
  sct = list(
    transplant = "^382[0-9]{2}$"      # 38200-38299 (HPC procedures)
  )
)

detect_unknown_codes <- function(treatment_type, known_codes) {
  # Extract PROCEDURES CPT/HCPCS codes matching range but NOT in known list
  range_patterns <- CPT_HCPCS_RANGES[[treatment_type]]

  get_pcornet_table("PROCEDURES") %>%
    filter(PX_TYPE == "CH") %>%
    filter(str_detect(PX, paste(range_patterns, collapse = "|"))) %>%
    filter(!PX %in% known_codes) %>%
    select(code = PX) %>%
    group_by(code) %>%
    summarise(n = n()) %>%
    mutate(source_table = "PROCEDURES (unmatched)", code_type = "CH")
}
```

### Pattern 3: xlsx Sheet Writing with Styling (openxlsx2)

**What:** Create styled sheet matching csv_to_xlsx.py patterns — title/subtitle, colored pills, frozen panes.

**When to use:** Writing each of the 4 treatment type sheets.

**Example:**
```r
# Source: csv_to_xlsx.py lines 32-51 (CATEGORY_COLORS), lines 78-180 (write_sheet)
library(openxlsx2)

# Treatment type color scheme (analogous to CATEGORY_COLORS)
TREATMENT_TYPE_COLORS <- list(
  Chemotherapy = list(fill = "FFDCEEFB", font = "FF0B5394"),  # light blue / dark blue
  Radiation = list(fill = "FFDDF4E1", font = "FF274E13"),     # light green / dark green
  SCT = list(fill = "FFFFF4D6", font = "FF7F6000"),           # light yellow / dark olive
  Immunotherapy = list(fill = "FFE8DCF4", font = "FF4C1D7A")  # light purple / dark purple
)

write_treatment_sheet <- function(wb, sheet_name, df_codes, df_summary, treatment_type) {
  # Add worksheet
  wb$add_worksheet(sheet_name)

  # Title block (rows 1-2)
  wb$add_data(sheet = sheet_name, x = "Treatment Inventory by Source Table", startRow = 1, startCol = 1)
  wb$add_font(sheet = sheet_name, dims = "A1", name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
  wb$merge_cells(sheet = sheet_name, rows = 1, cols = 1:5)

  subtitle <- glue("Counts and percentages of {treatment_type} codes by PCORnet table.")
  wb$add_data(sheet = sheet_name, x = subtitle, startRow = 2, startCol = 1)
  wb$add_font(sheet = sheet_name, dims = "A2", name = "Calibri", size = 10, color = wb_color("FF6B7280"))
  wb$merge_cells(sheet = sheet_name, rows = 2, cols = 1:5)

  # "By Source Table" section (row 4+)
  wb$add_data(sheet = sheet_name, x = "By Source Table", startRow = 4, startCol = 1)
  wb$add_font(sheet = sheet_name, dims = "A4", name = "Calibri", size = 12, bold = TRUE)

  # Summary table header (row 5)
  wb$add_data(sheet = sheet_name, x = data.frame(
    Source = "Source Table",
    Count = "Count",
    Percent = "% of Total"
  ), startRow = 5, startCol = 1, colNames = FALSE)
  wb$add_fill(sheet = sheet_name, dims = "A5:C5", color = wb_color("FF374151"))
  wb$add_font(sheet = sheet_name, dims = "A5:C5", name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

  # Summary data (rows 6+)
  wb$add_data(sheet = sheet_name, x = df_summary, startRow = 6, startCol = 1, colNames = FALSE)

  # Apply treatment type pill color to source table column
  fill_color <- TREATMENT_TYPE_COLORS[[treatment_type]]$fill
  font_color <- TREATMENT_TYPE_COLORS[[treatment_type]]$font
  summary_rows <- 6:(6 + nrow(df_summary) - 1)
  wb$add_fill(sheet = sheet_name, dims = glue("A{summary_rows[1]}:A{summary_rows[length(summary_rows)]}"),
              color = wb_color(fill_color))
  wb$add_font(sheet = sheet_name, dims = glue("A{summary_rows[1]}:A{summary_rows[length(summary_rows)]}"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color(font_color))

  # "Detailed Codes" section (after summary + blank row)
  detail_start_row <- 6 + nrow(df_summary) + 2
  wb$add_data(sheet = sheet_name, x = "Detailed Codes", startRow = detail_start_row - 1, startCol = 1)
  wb$add_font(sheet = sheet_name, dims = glue("A{detail_start_row - 1}"), name = "Calibri", size = 12, bold = TRUE)

  # Detailed table
  wb$add_data_table(sheet = sheet_name, x = df_codes, startRow = detail_start_row, startCol = 1,
                    tableStyle = "TableStyleMedium2", withFilter = FALSE)

  # Freeze panes (freeze at first detail row)
  wb$freeze_pane(sheet = sheet_name, firstRow = detail_start_row + 1)

  # Column widths (match csv_to_xlsx.py)
  wb$set_col_widths(sheet = sheet_name, cols = 1:5, widths = c(12, 60, 16, 14, 14))
}
```

### Anti-Patterns to Avoid

**1. Don't Query Every Patient's Records Separately**
- AVOID: Loop over patient IDs and query each table individually (1000s of queries)
- PREFER: Single table scan with %in% filter on code lists, then aggregate

**2. Don't Materialize DuckDB Tables Before Filtering**
- AVOID: `materialize(get_pcornet_table("PROCEDURES"))` then filter (loads millions of rows into memory)
- PREFER: Filter in SQL via lazy query: `get_pcornet_table("PROCEDURES") %>% filter(...) %>% group_by(...) %>% summarise(...)`

**3. Don't Use Base R xlsx Writing**
- AVOID: `write.xlsx()` from xlsx package (requires Java, slow)
- PREFER: openxlsx2 (no Java dependency, modern API)

**4. Don't Hardcode Treatment Type Count Assumptions**
- AVOID: `df_summary[1:7, ]` assuming 7 source tables always present
- PREFER: Dynamic row counting based on actual data: `nrow(df_summary)`

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| xlsx cell styling | Manual XML manipulation of .xlsx structure | openxlsx2 wb_add_fill(), wb_add_font(), wb_freeze_pane() | Excel Open XML spec is 5,000+ pages; openxlsx2 abstracts cell styles, conditional formatting, merged cells correctly |
| Code range pattern matching | Manual substring checks for CPT ranges | stringr str_detect() with regex ranges | Edge cases: 5-digit vs 4-digit codes, leading zeros, alphanumeric HCPCS (G codes, J codes) |
| Multi-source date extraction | Separate TUMOR_REGISTRY query per date column | TUMOR_REGISTRY_ALL table (Phase 14 optimization) | Combines TR1/TR2/TR3 with column alignment; single query instead of 3 |
| DuckDB lazy query materialization | Manual collect() calls before aggregation | dplyr group_by() %>% summarise() pushes aggregation to SQL | DuckDB executes aggregation in C++ (10-50x faster than R); only summary rows returned |

**Key insight:** PCORnet tables have 100k-10M+ rows. Premature materialization (collect/materialize) before filtering/aggregating causes memory exhaustion. DuckDB lazy queries push filtering and aggregation to SQL layer, returning only summary results to R. openxlsx2 handles xlsx complexity (shared strings, styles, relationships) that would require 1000+ lines of manual XML code.

## Common Pitfalls

### Pitfall 1: ICD-10-PCS Prefix Matching vs Exact Matching

**What goes wrong:** ICD-10-PCS codes in TREATMENT_CODES are stored as prefixes (e.g., "3E03305") but PROCEDURES.PX contains full 7-character codes (e.g., "3E03305Z"). Exact %in% matching returns zero results.

**Why it happens:** ICD-10-PCS codes have 7 characters; TREATMENT_CODES stores common prefixes to cover qualifier variations (character 7 varies by approach/device). Config comment says "prefix-matched via str_starts()" but implementer may use %in% by habit.

**How to avoid:** Use str_starts() for ICD-10-PCS, %in% for CPT/HCPCS/ICD-9/DRG.
```r
# WRONG: PX %in% TREATMENT_CODES$chemo_icd10pcs_prefixes (0 matches)
# RIGHT:
filter(PX_TYPE == "10" & str_starts(PX, paste0("^(", paste(TREATMENT_CODES$chemo_icd10pcs_prefixes, collapse = "|"), ")")))
```

**Warning signs:** Zero chemo/radiation records from PROCEDURES with PX_TYPE = "10" despite known data presence.

### Pitfall 2: TUMOR_REGISTRY Date Evidence Double-Counting

**What goes wrong:** Treating TUMOR_REGISTRY date columns (DT_CHEMO, DT_RAD, DT_HTE) as coded records creates misleading "code frequency" counts. These are not codes — they're date-of-treatment markers.

**Why it happens:** TUMOR_REGISTRY contains treatment dates (DT_CHEMO = 2019-05-15) but NO treatment codes. Other tables (PROCEDURES, DISPENSING) contain codes. Mixing "N patients with chemo date" with "N J9000 codes found" in the same table is category error.

**How to avoid:** TUMOR_REGISTRY contribution should be a single summary row: "DATE_EVIDENCE" with count = N patients having non-NA date. Do NOT attempt to extract individual code values from TUMOR_REGISTRY — they don't exist.
```r
# WRONG: Extracting DT_CHEMO values as if they were codes
# RIGHT:
tr_chemo <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
  filter(!is.na(DT_CHEMO) | !is.na(CHEMO_START_DATE_SUMMARY)) %>%
  summarise(n = n()) %>%
  mutate(code = "DATE_EVIDENCE", source_table = "TUMOR_REGISTRY", code_type = "DATE")
```

**Warning signs:** TUMOR_REGISTRY row in output has dates (2019-05-15) in the "Code" column instead of "DATE_EVIDENCE".

### Pitfall 3: Ignoring Missing Tables in Partial Extracts

**What goes wrong:** Script crashes with "table not found" error when DISPENSING or MED_ADMIN are missing from a test extract.

**Why it happens:** Phase 9 added DISPENSING/MED_ADMIN to the full extract, but older test extracts or site-specific pulls may only include core tables. get_pcornet_table() in DuckDB mode returns an error if table doesn't exist (unlike RDS mode where pcornet$DISPENSING would be NULL).

**How to avoid:** Wrap optional table queries in tryCatch() and bind empty tibble on error.
```r
disp_chemo <- tryCatch({
  get_pcornet_table("DISPENSING") %>%
    filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
    select(code = RXNORM_CUI) %>%
    mutate(source_table = "DISPENSING", code_type = "RXNORM")
}, error = function(e) {
  message("DISPENSING table not found; skipping")
  tibble(code = character(), source_table = character(), code_type = character())
})
```

**Warning signs:** Script runs successfully in full data environment but crashes in test environments with fewer tables.

### Pitfall 4: Color Hex Format Mismatch in openxlsx2

**What goes wrong:** Cell fill colors don't apply; cells remain white despite wb_add_fill() calls.

**Why it happens:** openxlsx2 wb_color() expects 8-character hex with alpha channel ("FFFFFFFF" = opaque white), but csv_to_xlsx.py uses 6-character hex ("FFFFFF"). Direct copy-paste of Python color codes fails silently.

**How to avoid:** Prepend "FF" (opaque alpha) to all 6-character hex colors from csv_to_xlsx.py.
```r
# WRONG: wb_color("DCEEFB") -- 6-char hex, invalid
# RIGHT: wb_color("FFDCEEFB") -- 8-char with alpha channel
TREATMENT_TYPE_COLORS <- list(
  Chemotherapy = list(fill = "FFDCEEFB", font = "FF0B5394")  # FF prefix = opaque
)
```

**Warning signs:** Workbook opens but all cells have white background despite styling code running without errors.

## Code Examples

Verified patterns from project codebase:

### Multi-Table Treatment Detection (Source: R/03_cohort_predicates.R lines 150-200)
```r
# Pattern: Query 7 tables for chemo evidence, use has_dx/has_tr flags
has_chemo <- function(patient_df) {
  # PROCEDURES: CPT/HCPCS + ICD-9 + ICD-10-PCS + revenue
  px_chemo_patients <- get_pcornet_table("PROCEDURES") %>%
    filter(
      (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) |
      (PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9) |
      (PX_TYPE == "10" & str_starts(PX, paste0("^(", paste(TREATMENT_CODES$chemo_icd10pcs_prefixes, collapse = "|"), ")"))) |
      (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$chemo_revenue)
    ) %>%
    distinct(ID)

  # PRESCRIBING: RXNORM
  rx_chemo_patients <- get_pcornet_table("PRESCRIBING") %>%
    filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
    distinct(ID)

  # ... [DISPENSING, MED_ADMIN, DIAGNOSIS, ENCOUNTER queries] ...

  # Combine sources with semi_join
  patient_df %>% semi_join(
    bind_rows(px_chemo_patients, rx_chemo_patients, ...), by = "ID"
  )
}
```

### DuckDB Backend-Transparent Table Access (Source: R/utils_duckdb.R lines 45-65)
```r
# Pattern: Works in both RDS and DuckDB mode
get_pcornet_table <- function(table_name) {
  if (USE_DUCKDB) {
    # Return lazy tbl_dbi query (not materialized)
    tbl(pcornet_con, table_name)
  } else {
    # Return in-memory tibble from RDS cache
    pcornet[[table_name]]
  }
}

# Usage in aggregation (DuckDB executes SQL aggregation, returns summary only)
code_counts <- get_pcornet_table("PROCEDURES") %>%
  filter(PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) %>%
  group_by(PX) %>%
  summarise(n = n())  # Only summary rows materialized to R
```

### openxlsx2 Styling Pattern (Adapted from csv_to_xlsx.py)
```r
# Pattern: Title block + colored category pills + frozen panes
library(openxlsx2)

wb <- wb_workbook()
wb$add_worksheet("Chemotherapy")

# Title (row 1)
wb$add_data(sheet = "Chemotherapy", x = "Treatment Inventory by Source Table",
            startRow = 1, startCol = 1)
wb$add_font(sheet = "Chemotherapy", dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Chemotherapy", rows = 1, cols = 1:5)

# Subtitle (row 2)
wb$add_data(sheet = "Chemotherapy", x = "Chemotherapy codes by PCORnet table.",
            startRow = 2, startCol = 1)
wb$add_font(sheet = "Chemotherapy", dims = "A2",
            name = "Calibri", size = 10, color = wb_color("FF6B7280"))

# Data table with header fill (row 5+)
wb$add_data(sheet = "Chemotherapy", x = summary_df, startRow = 5, startCol = 1)
wb$add_fill(sheet = "Chemotherapy", dims = "A5:C5", color = wb_color("FF374151"))
wb$add_font(sheet = "Chemotherapy", dims = "A5:C5",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Colored pill for treatment type (rows 6+)
wb$add_fill(sheet = "Chemotherapy", dims = "A6:A12", color = wb_color("FFDCEEFB"))
wb$add_font(sheet = "Chemotherapy", dims = "A6:A12",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FF0B5394"))

# Freeze panes (freeze at detail table header)
wb$freeze_pane(sheet = "Chemotherapy", firstRow = 14)

# Column widths
wb$set_col_widths(sheet = "Chemotherapy", cols = 1:5, widths = c(12, 60, 16, 14, 14))

# Save
wb$save("output/treatment_inventory.xlsx")
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| writexl for all xlsx output | openxlsx2 for styled output, writexl for data-only | openxlsx2 1.0 release (Oct 2023) | writexl 2x faster but NO styling; openxlsx2 matches Python openpyxl feature parity |
| openxlsx (original) | openxlsx2 | Apr 2024 deprecation notice | openxlsx maintenance-only; openxlsx2 is active successor with modern API |
| Manual column type guessing | Explicit col_types in vroom/readr | Project standard (Phase 1) | PCORnet ID columns (PATID, ENCOUNTERID) can have leading zeros; character type prevents truncation |
| Separate TR1/TR2/TR3 queries | TUMOR_REGISTRY_ALL combined table | Phase 14 optimization | 1 query instead of 3; column alignment across TR variants |

**Deprecated/outdated:**
- openxlsx (original): Maintenance-only as of Apr 2024; openxlsx2 is the successor
- xlsx package: Requires rJava (Java runtime dependency); slow performance; use openxlsx2 instead
- write.xlsx() from openxlsx: Use wb_workbook() piped API in openxlsx2 for cleaner code

## Open Questions

1. **Should unmatched codes be on separate sheets or inline sections?**
   - What we know: D-08 says flag as "Unmatched" in a separate section per sheet
   - What's unclear: "Section" could mean (a) rows at bottom of detailed table, or (b) separate "Unmatched" sub-table between summary and detailed
   - Recommendation: Inline at bottom of detailed table with "source_table = PROCEDURES (unmatched)" to keep all codes on one sheet; easier filtering

2. **How to handle TUMOR_REGISTRY date columns for radiation?**
   - What we know: TR1 has no DT_RAD column (only CHEMO_START_DATE_SUMMARY); TR2/TR3 have DT_RAD
   - What's unclear: Should radiation inventory skip TR1 entirely, or query TUMOR_REGISTRY_ALL and filter for non-NA DT_RAD only?
   - Recommendation: Query TUMOR_REGISTRY_ALL, filter for non-NA DT_RAD; omit TR1 contribution if column doesn't exist (no false negatives)

3. **Should percentage column be % of total across all treatment types, or % within treatment type?**
   - What we know: csv_to_xlsx.py uses "% of Total" within each sheet (denominator = sum of codes on that sheet)
   - What's unclear: D-03 says "counts per source table per treatment type" but doesn't specify denominator for %
   - Recommendation: % within treatment type (matches csv_to_xlsx.py pattern); cross-treatment comparisons not meaningful (different code systems)

## Environment Availability

> Phase 38 has external dependencies (R packages, xlsx writing libraries)

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| openxlsx2 | xlsx styling/writing | Unknown (not in CLAUDE.md stack) | 1.24 (CRAN 2026-04-17) | Install via renv::install("openxlsx2") |
| R 4.4.2+ | Script execution | ✓ (HiPerGator module) | 4.4.2 | — |
| dplyr, stringr, glue | Data manipulation | ✓ (project stack) | Per renv.lock | — |
| DuckDB backend | Table access | ✓ (USE_DUCKDB = TRUE default) | Per Phase 32 | RDS mode fallback (slower) |

**Missing dependencies with no fallback:**
- None (openxlsx2 installable via CRAN)

**Missing dependencies with fallback:**
- openxlsx2 → Could use writexl (no styling) or openxlsx (deprecated) if install fails; would lose D-05 styling requirement

## Validation Architecture

> Skipped: .planning/config.json does not exist; assuming validation enabled by default.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | None detected (R project; no testthat/RUnit config found) |
| Config file | None — validation deferred to manual execution |
| Quick run command | `Rscript R/38_treatment_inventory.R` |
| Full suite command | Manual inspection of output/treatment_inventory.xlsx |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| N/A | No mapped requirements | manual | Manual: Open xlsx, verify 4 sheets, check styling | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** Manual: `Rscript R/38_treatment_inventory.R && open output/treatment_inventory.xlsx`
- **Per wave merge:** Same (manual inspection)
- **Phase gate:** Manual verification of styling, counts, and unmatched section before `/gsd:verify-work`

### Wave 0 Gaps
- No automated tests (R project convention: scripts are self-validating via console output)
- Manual verification required: xlsx structure, styling correctness, count accuracy

*(R pipeline convention: Validation via manual inspection and reproducible execution, not unit tests)*

## Sources

### Primary (HIGH confidence)
- [openxlsx2 CRAN package page](https://cran.r-project.org/web/packages/openxlsx2/index.html) - Version 1.24, published 2026-04-17
- [openxlsx2 styling manual](https://cran.r-project.org/web/packages/openxlsx2/vignettes/openxlsx2_style_manual.html) - Cell fills, fonts, frozen panes API
- [openxlsx2 reference manual](https://cran.r-project.org/web/packages/openxlsx2/openxlsx2.pdf) - Complete function reference
- R/00_config.R (project codebase) - TREATMENT_CODES lists, all 4 treatment types
- R/03_cohort_predicates.R (project codebase) - has_chemo/radiation/sct patterns for multi-table queries
- R/10_treatment_payer.R (project codebase) - Treatment date extraction from 7 tables
- csv_to_xlsx.py (project codebase) - Visual styling patterns (title/subtitle, colored pills, frozen panes)

### Secondary (MEDIUM confidence)
- [R xlsx packages comparison (R-bloggers)](https://www.r-bloggers.com/2023/05/comparing-r-packages-for-writing-excel-files-an-analysis-of-writexl-openxlsx-and-xlsx-in-r/) - Performance benchmarks (writexl 2x faster, but no styling)
- [PCORnet CDM v7.0 specification](https://pcornet.org/wp-content/uploads/2025/05/PCORnet_Common_Data_Model_v70_2025_05_01.pdf) - Table schemas (PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, TUMOR_REGISTRY)
- [openxlsx deprecation notice (CRAN)](https://cran.r-project.org/package=openxlsx) - Maintenance-only status, openxlsx2 is successor

### Tertiary (LOW confidence)
- [GPC Tumor Table Transformation guide](https://pcornet.org/news/resources-gpc-tumor-table-transformation-and-linkage/) - TUMOR_REGISTRY structure (DT_CHEMO, DT_RAD, DT_HTE columns mentioned but not detailed schema)

## Metadata

**Confidence breakdown:**
- Standard stack (openxlsx2): **HIGH** - Official CRAN release 2026-04-17, complete styling API verified in reference manual
- Architecture (multi-table aggregation): **HIGH** - Existing patterns in R/03_cohort_predicates.R and R/10_treatment_payer.R directly applicable
- Pitfalls (ICD-10-PCS prefix matching): **HIGH** - Documented in R/00_config.R comments, verified in existing code
- TUMOR_REGISTRY date columns: **MEDIUM** - Column names verified in project code, but exact schema (TR1 vs TR2/TR3 differences) inferred from code comments

**Research date:** 2026-05-01
**Valid until:** ~60 days (stable R packages; openxlsx2 API unlikely to change before Phase 38 execution)
