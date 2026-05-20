# Phase 5: all_codes_resolved.xlsx Update - Research

**Researched:** 2026-05-20
**Domain:** R data wrangling, xlsx generation, multi-source description cascade, programmatic config curation
**Confidence:** HIGH

## Summary

Phase 5 regenerates the all_codes_resolved.xlsx master reference file and 5 per-type resolved xlsx files from the current state of R/00_config.R TREATMENT_CODES (which has diverged from the May 5 combined_unmatched_report.xlsx through Phases 45-46 code additions). The script will query PCORnet data via DuckDB for patient/record counts, build descriptions from a multi-source cascade (Phase 39-41 RDS artifacts, Phase 45 hardcoded radiation descriptions, config inline comments), and optionally curate config comments where better descriptions exist. The project has established patterns for all required operations: openxlsx2 styling (R/42), DuckDB querying (R/01, utils_duckdb.R), parse/source validation with rollback (R/39), and reusable write_resolved_xlsx() function.

**Primary recommendation:** Create R/52_all_codes_resolved.R as a standalone script (leaving R/42 as historical record). Use DuckDB queries to get patient/record counts per code. Build description lookup from Phase 39-41 RDS artifacts (if they exist), Phase 45 hardcoded descriptions, and R/00_config.R inline comments as fallback. Apply parse/source validation when curating config comments. Follow R/42 write_resolved_xlsx() pattern with openxlsx2 styling for all 6 xlsx outputs.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Code Source (D-01, D-02):**
- Pull code lists directly from R/00_config.R TREATMENT_CODES vectors
- This is the current source of truth including Phase 45 proton additions, Phase 46 ICD-10-PCS additions, and all prior expansions
- Do NOT depend on combined_unmatched_report.xlsx (Phase 41 output) — config has diverged since May 5

**Data Counts (D-03, D-04, D-05):**
- Include patient count and record count per code, queried from PCORnet data via DuckDB on HiPerGator
- Query all relevant tables per code type: CPT/HCPCS codes against PROCEDURES, NDC codes against DISPENSING, RXNORM codes against PRESCRIBING/MED_ADMIN, ICD-10-PCS codes against PROCEDURES
- Script requires HiPerGator execution (not local-only)

**Descriptions (D-06, D-07, D-08):**
- Multi-source description cascade: (1) Phase 39-41 RDS artifacts (NLM/RxNorm API descriptions), (2) R/45 hardcoded radiation descriptions, (3) R/00_config.R inline comments, (4) "No description available" fallback
- Update R/00_config.R inline comments when a better description exists from the RDS/API sources — makes config self-documenting
- Config comment updates must use parse/source validation with rollback (established pattern from Phase 39)

**Output Structure (D-09, D-10, D-11):**
- all_codes_resolved.xlsx has one sheet per treatment type: Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care, plus a Summary sheet with totals
- Also regenerate all 5 individual per-type resolved files (chemotherapy_codes_resolved.xlsx, radiation_codes_resolved.xlsx, sct_codes_resolved.xlsx, immunotherapy_codes_resolved.xlsx, supportive_care_codes_resolved.xlsx)
- Per-type sheets and files follow established format: Code, Meaning, Code Type, Source Table, Records, Patients columns with openxlsx2 styling

**Script Approach (D-12, D-13):**
- New standalone script R/52_all_codes_resolved.R — R/42 stays as historical record of the original Phase 42 approach
- Script number 52 follows the current sequence (R/51 is cancer site confirmation 7-day)

### Claude's Discretion

- Whether config comment curation is done as an early section of R/52 or as a separate preparatory step — pick the approach that minimizes risk of breaking config
- Exact xlsx styling details (colors, column widths, Summary sheet layout)
- How to map TREATMENT_CODES vector names to code types and source tables for querying
- Console output format and progress messages

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Tidyverse standard; mature SQL-like syntax; integrates with DuckDB tbl_dbi |
| openxlsx2 | 1.10+ | Excel file creation | Modern rewrite of openxlsx; no Java dependency; R6 API; used in R/42, R/39, R/45 |
| glue | 1.8.0+ | String formatting | Tidyverse adjacent; embedded expression evaluation; used throughout project |
| DBI / duckdb | 1.2.0+ / 1.1.0+ | Database access | Project standard (Phase 30+); backend-agnostic DBI layer over DuckDB analytical database |
| stringr | 1.5.1+ | String operations | Tidyverse standard; consistent API; used for code prefix matching |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| purrr | 1.0.2+ | Functional programming | map_chr() for vectorized classification; rowwise() alternative |
| tibble | 3.2.1+ | Modern data frames | Tidyverse default; better printing than base data.frame |
| lubridate | 1.9.3+ | Date operations | Parse dates if needed (not critical for this phase) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| openxlsx2 | openxlsx (v4.x) | Original openxlsx uses reference classes, requires Java rJava for some features; openxlsx2 is pure R rewrite with R6 API |
| DuckDB | Direct CSV reads | DuckDB provides 10-100x faster aggregation on large PCORnet tables; CSV reads would be slower and memory-intensive |
| dplyr | data.table | data.table is 10-50x faster but opaque syntax conflicts with project's "readable named predicates" requirement |

**Installation:**
```bash
# On HiPerGator (already installed via renv)
module load R/4.4.2
Rscript -e "library(openxlsx2); library(dplyr); library(DBI); library(duckdb)"
```

**Version verification:**
All packages already installed and locked in project's renv.lock (Phase 1 setup). No new dependencies required.

## Architecture Patterns

### Recommended Project Structure
```
R/
├── 00_config.R              # TREATMENT_CODES source of truth
├── 01_load_pcornet.R        # DuckDB backend initialization
├── 39_investigate_unmatched.R  # Config update pattern with validation
├── 42_treatment_codes_resolved.R  # write_resolved_xlsx() reusable function
├── 45_radiation_cpt_audit.R    # hardcoded_descriptions pattern
├── 52_all_codes_resolved.R  # NEW: Phase 5 implementation
├── utils_duckdb.R           # get_pcornet_table(), open_pcornet_con()
└── utils_treatment.R        # safe_table(), nrow_or_0()

output/
├── unmatched_codes_classified.rds  # Phase 39 HCPCS/CPT descriptions (if exists)
└── unmatched_ndc_classified.rds    # Phase 40 NDC/RXNORM descriptions (if exists)

/*.xlsx                       # Root-level xlsx outputs (gitignored)
```

### Pattern 1: Multi-Source Description Cascade
**What:** Build code description lookup by checking multiple sources in priority order, taking first non-NA result
**When to use:** When descriptions come from heterogeneous sources (API lookups, hardcoded tables, config comments)
**Example:**
```r
# Source: Phase 5 design pattern (analogous to R/45 hardcoded + R/39 RDS pattern)

# Step 1: Load Phase 39-41 RDS artifacts (if they exist)
rds_39_path <- file.path(CONFIG$output_dir, "unmatched_codes_classified.rds")
rds_40_path <- file.path(CONFIG$output_dir, "unmatched_ndc_classified.rds")

descriptions_39 <- if (file.exists(rds_39_path)) {
  readRDS(rds_39_path) %>% select(code, description)
} else {
  tibble(code = character(), description = character())
}

descriptions_40 <- if (file.exists(rds_40_path)) {
  readRDS(rds_40_path) %>% select(code, description)
} else {
  tibble(code = character(), description = character())
}

api_descriptions <- bind_rows(descriptions_39, descriptions_40)

# Step 2: Load Phase 45 hardcoded radiation descriptions
hardcoded_descriptions <- tibble::tribble(
  ~code, ~description,
  "77401", "External beam radiation delivery, surface/orthovoltage (DELETED 2026)",
  "77404", "Radiation treatment delivery; single area, 6-10 MeV (DELETED 2015)",
  # ... (copy from R/45_radiation_cpt_audit.R lines 88-115)
)

# Step 3: Extract config inline comments
config_comments <- extract_config_comments("R/00_config.R")

# Step 4: Build cascade lookup function
lookup_description <- function(code) {
  # Priority 1: API descriptions from Phase 39-41 RDS
  api_match <- api_descriptions %>% filter(code == !!code) %>% pull(description)
  if (length(api_match) > 0 && !is.na(api_match[1])) return(api_match[1])

  # Priority 2: Hardcoded descriptions from Phase 45
  hardcoded_match <- hardcoded_descriptions %>% filter(code == !!code) %>% pull(description)
  if (length(hardcoded_match) > 0 && !is.na(hardcoded_match[1])) return(hardcoded_match[1])

  # Priority 3: Config inline comments
  config_match <- config_comments %>% filter(code == !!code) %>% pull(description)
  if (length(config_match) > 0 && !is.na(config_match[1])) return(config_match[1])

  # Priority 4: Fallback
  return("No description available")
}
```

### Pattern 2: DuckDB Patient/Record Count Query
**What:** Query PCORnet tables via DuckDB to count records and distinct patients per code
**When to use:** When aggregating large PCORnet tables (millions of rows) efficiently
**Example:**
```r
# Source: Established pattern from R/38, R/39, R/43 (DuckDB aggregation)

library(DBI)
library(duckdb)
source("R/01_load_pcornet.R")  # Opens pcornet_con via open_pcornet_con()

# Query PROCEDURES for CPT/HCPCS codes
get_cpt_counts <- function(codes) {
  proc_tbl <- get_pcornet_table("PROCEDURES")

  proc_tbl %>%
    filter(PX_TYPE == "CH", PX %in% codes) %>%
    group_by(code = PX) %>%
    summarise(
      records = n(),
      patients = n_distinct(ID),
      .groups = "drop"
    ) %>%
    collect()
}

# Query DISPENSING for NDC codes
get_ndc_counts <- function(codes) {
  disp_tbl <- safe_table("DISPENSING")
  if (is.null(disp_tbl)) return(tibble(code = character(), records = integer(), patients = integer()))

  disp_tbl %>%
    filter(NDC %in% codes) %>%
    group_by(code = NDC) %>%
    summarise(
      records = n(),
      patients = n_distinct(ID),
      .groups = "drop"
    ) %>%
    collect()
}

# Query PRESCRIBING + MED_ADMIN for RXNORM CUIs
get_rxnorm_counts <- function(codes) {
  # Combine PRESCRIBING and MED_ADMIN (Phase 9 pattern)
  presc_counts <- safe_table("PRESCRIBING") %>%
    filter(RXNORM_CUI %in% codes) %>%
    group_by(code = RXNORM_CUI) %>%
    summarise(records_presc = n(), patients_presc = n_distinct(ID), .groups = "drop") %>%
    collect()

  medadm_counts <- safe_table("MED_ADMIN") %>%
    filter(MEDADMIN_CODE %in% codes, MEDADMIN_TYPE == "RX") %>%
    group_by(code = MEDADMIN_CODE) %>%
    summarise(records_medadm = n(), patients_medadm = n_distinct(ID), .groups = "drop") %>%
    collect()

  # Merge and sum
  full_join(presc_counts, medadm_counts, by = "code") %>%
    mutate(
      records = coalesce(records_presc, 0L) + coalesce(records_medadm, 0L),
      patients = coalesce(patients_presc, 0L) + coalesce(patients_medadm, 0L)
    ) %>%
    select(code, records, patients)
}
```

### Pattern 3: Config Parse/Source Validation with Rollback
**What:** Programmatically modify R/00_config.R, validate syntax and runtime loading, rollback on failure
**When to use:** When updating config inline comments or adding codes programmatically
**Example:**
```r
# Source: R/39_investigate_unmatched.R (lines 456-718, SECTION 8)

update_config_comments <- function(code_description_df) {
  config_path <- "R/00_config.R"
  backup_path <- paste0(config_path, ".bak")

  # 1. Create backup
  file.copy(config_path, backup_path, overwrite = TRUE)
  message(glue("Created backup: {backup_path}"))

  # 2. Read config lines
  config_lines <- readLines(config_path)

  # 3. Modify inline comments (find code line, replace comment)
  for (i in seq_len(nrow(code_description_df))) {
    code <- code_description_df$code[i]
    desc <- code_description_df$description[i]

    # Find line with this code
    code_line_idx <- grep(glue('"{code}"'), config_lines, fixed = TRUE)
    if (length(code_line_idx) == 0) next

    # Replace comment portion (everything after #)
    config_lines[code_line_idx[1]] <- sub(
      "#.*$",
      glue("# {desc}"),
      config_lines[code_line_idx[1]]
    )
  }

  # 4. Write updated config
  writeLines(config_lines, config_path)

  # 5. Validate with parse() and source()
  validation_error <- tryCatch({
    parse(config_path)
    env <- new.env()
    source(config_path, local = env)

    if (is.null(env$TREATMENT_CODES)) {
      stop("TREATMENT_CODES is NULL after sourcing")
    }

    NULL  # No error
  }, error = function(e) {
    e$message
  })

  # 6. Rollback on failure
  if (!is.null(validation_error)) {
    message(glue("Validation failed: {validation_error}"))
    message("Restoring backup...")
    file.copy(backup_path, config_path, overwrite = TRUE)
    stop(glue("Config validation failed: {validation_error}"))
  }

  message("Config update validated successfully")
  file.remove(backup_path)
}
```

### Pattern 4: Reusable write_resolved_xlsx() Function
**What:** Create styled 2-sheet workbook (data + Notes) per treatment category with openxlsx2
**When to use:** For all per-type resolved xlsx outputs (5 files) and sheets in all_codes_resolved.xlsx
**Example:**
```r
# Source: R/42_treatment_codes_resolved.R (lines 45-127)
# Reusable as-is; just call with appropriate df, category, output_path

write_resolved_xlsx <- function(df, category, output_path) {
  n_codes <- nrow(df)
  sheet_name <- paste(category, "Codes")

  fill_color <- TREATMENT_TYPE_COLORS[[category]]$fill
  font_color <- TREATMENT_TYPE_COLORS[[category]]$font

  wb <- wb_workbook()
  wb$add_worksheet(sheet_name)

  # Row 1: Title with code count
  wb$add_data(sheet = sheet_name, x = glue("{category} Codes ({n_codes} codes)"),
              start_row = 1, start_col = 1)
  wb$add_font(sheet = sheet_name, dims = "A1",
              name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
  wb$merge_cells(sheet = sheet_name, dims = "A1:F1")

  # Row 2: Column headers
  headers <- c("Code", "Meaning", "Code Type", "Source Table", "Records", "Patients")
  for (i in seq_along(headers)) {
    wb$add_data(sheet = sheet_name, x = headers[i], start_row = 2, start_col = i)
  }
  wb$add_fill(sheet = sheet_name, dims = "A2:F2", color = wb_color("FF374151"))
  wb$add_font(sheet = sheet_name, dims = "A2:F2",
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

  # Row 3+: Bulk data write
  write_df <- data.frame(
    Code = df$code,
    Meaning = ifelse(is.na(df$description), "", df$description),
    Code_Type = df$code_type,
    Source_Table = df$source_table,
    Records = df$records,
    Patients = df$patients,
    stringsAsFactors = FALSE
  )
  wb$add_data(sheet = sheet_name, x = write_df, start_row = 3, col_names = FALSE)

  # Styling: Code column with category color
  last_row <- 2 + n_codes
  code_dims <- glue("A3:A{last_row}")
  wb$add_fill(sheet = sheet_name, dims = code_dims, color = wb_color(fill_color))
  wb$add_font(sheet = sheet_name, dims = code_dims,
              name = "Calibri", size = 10, bold = TRUE, color = wb_color(font_color))

  # Number formatting
  wb$add_numfmt(sheet = sheet_name, dims = glue("E3:F{last_row}"), numfmt = "#,##0")

  # Column widths
  wb$set_col_widths(sheet = sheet_name, cols = 1:6, widths = c(15, 45, 12, 15, 10, 10))

  # Notes sheet
  wb$add_worksheet("Notes")
  notes_lines <- c(
    glue("Data Source: R/00_config.R TREATMENT_CODES (current as of {Sys.Date()})"),
    glue("Descriptions: Multi-source cascade (Phase 39-41 RDS, Phase 45 hardcoded, config comments)"),
    glue("Generated: {Sys.Date()}"),
    glue("Classification: {category} codes")
  )
  for (i in seq_along(notes_lines)) {
    wb$add_data(sheet = "Notes", x = as.character(notes_lines[i]),
                start_row = i, start_col = 1)
  }

  wb$save(output_path)
  message(glue("  Wrote {output_path} ({n_codes} codes)"))
}
```

### Anti-Patterns to Avoid

- **Don't Query RDS Directly:** Use get_pcornet_table() abstraction (supports both DuckDB and RDS backends). Direct pcornet$TABLE access breaks when USE_DUCKDB = TRUE.
- **Don't Modify Config Without Validation:** Always use parse() + source() validation with rollback. Silent syntax errors corrupt the config and break all downstream scripts.
- **Don't Assume RDS Artifacts Exist:** Phase 39-41 RDS files may not exist in all environments (output/ is gitignored). Use file.exists() checks with empty tibble fallbacks.
- **Don't Hardcode Sheet Names with Special Characters:** Excel sheet names have a 31-character limit and disallow `[]:*?/\`. Sanitize category names if needed (though current categories are safe).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Excel file generation | Custom XML writing, write.xlsx() loops | openxlsx2 wb_workbook() R6 API | Edge cases: merged cells, number formatting, color fills, freeze panes. openxlsx2 handles all correctly; custom solutions break on complex styling. |
| DuckDB query aggregation | CSV reading + dplyr in-memory | get_pcornet_table() + lazy queries | PCORnet tables are 100MB-2GB. In-memory dplyr loads all rows; DuckDB pushes aggregation to database engine (10-100x faster, constant memory). |
| Config inline comment parsing | Regex on raw lines | parse() + source() validation | R syntax is complex (escaped quotes, trailing commas, nested structures). Regex misses edge cases; parse() is authoritative. |
| Multi-table RxNorm lookup | Custom API wrappers | Reuse Phase 39-40 RDS artifacts | Phase 40 already paid the 15-minute API cost with retry logic. RDS files are pre-computed; rebuilding wastes time and risks rate limiting. |

**Key insight:** This phase reuses 4 prior phases' work (R/39 validation pattern, R/40 RDS artifacts, R/42 write_resolved_xlsx() function, R/45 hardcoded descriptions). Don't rebuild what already exists.

## Runtime State Inventory

> Section omitted: This is not a rename/refactor/migration phase. It's a code inventory regeneration from current config state.

## Common Pitfalls

### Pitfall 1: Missing RDS Artifacts in Output Directory
**What goes wrong:** Script crashes with "file not found" when trying to load Phase 39-41 RDS artifacts
**Why it happens:** output/ is gitignored; RDS files don't transfer across environments; collaborator runs script without running Phase 39-40 first
**How to avoid:** Use file.exists() checks and provide empty tibble fallbacks
**Warning signs:** Error message "cannot open the connection" or "No such file or directory" when loading RDS
**Prevention code:**
```r
rds_39_path <- file.path(CONFIG$output_dir, "unmatched_codes_classified.rds")
descriptions_39 <- if (file.exists(rds_39_path)) {
  readRDS(rds_39_path)
} else {
  message("  Phase 39 RDS not found; skipping API descriptions")
  tibble(code = character(), description = character())
}
```

### Pitfall 2: Code Type Ambiguity for Multi-Table Codes
**What goes wrong:** RXNORM codes appear in both PRESCRIBING and MED_ADMIN; counts double if queried separately without deduplication
**Why it happens:** Same RxCUI can appear in multiple medication tables; patient receives same drug via prescription and inpatient administration
**How to avoid:** Query both tables, group by patient+code, count distinct patients across tables (not sum of distinct per table)
**Warning signs:** Patient counts exceed total cohort size; same code has 2 rows in output with different "source_table" values
**Prevention code:**
```r
# WRONG: Separate queries with sum of patients (double-counts patients who appear in both)
presc_patients <- presc_tbl %>% filter(...) %>% summarise(n_distinct(ID))
medadm_patients <- medadm_tbl %>% filter(...) %>% summarise(n_distinct(ID))
total_patients <- presc_patients + medadm_patients  # WRONG: double counts

# RIGHT: Combined query with distinct across tables
combined_tbl <- bind_rows(
  presc_tbl %>% filter(...) %>% select(ID, code = RXNORM_CUI),
  medadm_tbl %>% filter(...) %>% select(ID, code = MEDADMIN_CODE)
)
combined_tbl %>%
  group_by(code) %>%
  summarise(patients = n_distinct(ID), records = n())
```

### Pitfall 3: Config Comment Corruption via Naive String Substitution
**What goes wrong:** Regex comment replacement breaks when code appears in multiple contexts (e.g., "J9000" in a comment about a different code's description)
**Why it happens:** grep('"J9000"') matches code definition lines; sub("#.*$", ...) blindly replaces ALL comments on that line, including structural comments
**How to avoid:** Target only lines within TREATMENT_CODES vectors; validate exact code match in quotes; preserve trailing commas
**Warning signs:** Config sourcing fails with "unexpected symbol" or "object not found"; git diff shows unintended comment changes
**Prevention code:**
```r
# Find vector boundaries first
vec_start <- grep("chemo_hcpcs = c\\(", config_lines)
vec_end <- grep("^\\s*\\),?\\s*$", config_lines[vec_start:length(config_lines)])[1] + vec_start - 1

# Only modify lines within this vector
for (line_idx in vec_start:vec_end) {
  if (grepl(glue('"{code}"'), config_lines[line_idx], fixed = TRUE)) {
    # Exact match on quoted code
    config_lines[line_idx] <- sub("#.*$", glue("# {new_desc}"), config_lines[line_idx])
  }
}
```

### Pitfall 4: Excel Sheet Name Collisions in all_codes_resolved.xlsx
**What goes wrong:** Creating "Chemotherapy" sheet twice (once for data, once for notes) causes openxlsx2 error "sheet already exists"
**Why it happens:** Multi-sheet workbook pattern from R/42 uses "{Category} Codes" naming; all_codes_resolved.xlsx consolidates all categories into one workbook
**How to avoid:** Use unique sheet names: "Chemotherapy", "Radiation", etc. (no " Codes" suffix in all_codes_resolved.xlsx); Notes sheet is per-file, not per-sheet
**Warning signs:** Error "sheet 'Chemotherapy' already exists" when calling wb$add_worksheet()
**Prevention code:**
```r
# For per-type single-category files (chemotherapy_codes_resolved.xlsx):
sheet_name <- paste(category, "Codes")  # "Chemotherapy Codes"

# For all_codes_resolved.xlsx multi-category workbook:
sheet_name <- category  # "Chemotherapy" (no " Codes" suffix)
```

## Code Examples

Verified patterns from existing codebase:

### Extracting Config Inline Comments
```r
# Source: New pattern for Phase 5 (analogous to R/39 config reading pattern)

extract_config_comments <- function(config_path) {
  config_lines <- readLines(config_path)

  # Find all lines with quoted codes and inline comments
  code_comment_lines <- config_lines[grepl('"[A-Z0-9]+"\\s*,?\\s*#', config_lines)]

  # Extract code and comment
  tibble(line = code_comment_lines) %>%
    mutate(
      code = str_extract(line, '"([A-Z0-9]+)"', group = 1),
      description = str_trim(str_extract(line, "#\\s*(.*)$", group = 1))
    ) %>%
    filter(!is.na(code), !is.na(description), description != "") %>%
    select(code, description)
}
```

### Mapping TREATMENT_CODES Vector Names to Code Types and Source Tables
```r
# Source: Project pattern from R/38, R/39, R/43 (code type routing)

code_type_map <- tribble(
  ~vector_name,               ~code_type,    ~source_table,        ~query_column,
  "chemo_hcpcs",              "CPT/HCPCS",   "PROCEDURES",         "PX",
  "chemo_rxnorm",             "RXNORM",      "PRESCRIBING|MED_ADMIN", "RXNORM_CUI|MEDADMIN_CODE",
  "chemo_ndc",                "NDC",         "DISPENSING",         "NDC",
  "chemo_icd10pcs_prefixes",  "ICD-10-PCS",  "PROCEDURES",         "PX",
  "radiation_cpt",            "CPT/HCPCS",   "PROCEDURES",         "PX",
  "radiation_icd10pcs",       "ICD-10-PCS",  "PROCEDURES",         "PX",
  "sct_cpt",                  "CPT/HCPCS",   "PROCEDURES",         "PX",
  "sct_hcpcs",                "CPT/HCPCS",   "PROCEDURES",         "PX",
  "sct_icd10pcs",             "ICD-10-PCS",  "PROCEDURES",         "PX",
  "cart_icd10pcs_prefixes",   "ICD-10-PCS",  "PROCEDURES",         "PX",
  "supportive_care_hcpcs",    "CPT/HCPCS",   "PROCEDURES",         "PX",
  "immunotherapy_drg",        "DRG",         "ENCOUNTER",          "DRG"
)

# Map vector name to treatment category
category_map <- c(
  "chemo_hcpcs" = "Chemotherapy",
  "chemo_rxnorm" = "Chemotherapy",
  "chemo_ndc" = "Chemotherapy",
  "chemo_icd10pcs_prefixes" = "Chemotherapy",
  "radiation_cpt" = "Radiation",
  "radiation_icd10pcs" = "Radiation",
  "sct_cpt" = "SCT",
  "sct_hcpcs" = "SCT",
  "sct_icd10pcs" = "SCT",
  "cart_icd10pcs_prefixes" = "Immunotherapy",
  "supportive_care_hcpcs" = "Supportive Care",
  "immunotherapy_drg" = "Immunotherapy"
)
```

### Building Summary Sheet for all_codes_resolved.xlsx
```r
# Source: R/39 Summary sheet pattern (lines 296-351) + R/42 color scheme

build_summary_df <- function(all_codes_df) {
  summary <- all_codes_df %>%
    group_by(category) %>%
    summarise(
      n_codes = n(),
      total_records = sum(records, na.rm = TRUE),
      total_patients = sum(patients, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(match(category, c("Chemotherapy", "Radiation", "SCT", "Immunotherapy", "Supportive Care")))

  # Add totals row
  bind_rows(
    summary,
    tibble(
      category = "Total",
      n_codes = sum(summary$n_codes),
      total_records = sum(summary$total_records),
      total_patients = sum(summary$total_patients)
    )
  )
}

write_summary_sheet <- function(wb, summary_df) {
  wb$add_worksheet("Summary")

  # Title
  wb$add_data(sheet = "Summary", x = "All Treatment Codes - Summary",
              start_row = 1, start_col = 1)
  wb$add_font(sheet = "Summary", dims = "A1",
              name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
  wb$merge_cells(sheet = "Summary", dims = "A1:D1")

  # Headers
  headers <- c("Treatment Type", "Codes", "Records", "Patients")
  for (i in seq_along(headers)) {
    wb$add_data(sheet = "Summary", x = headers[i], start_row = 3, start_col = i)
  }
  wb$add_fill(sheet = "Summary", dims = "A3:D3", color = wb_color("FF374151"))
  wb$add_font(sheet = "Summary", dims = "A3:D3",
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

  # Data rows
  for (r in seq_len(nrow(summary_df))) {
    row_num <- 3 + r
    wb$add_data(sheet = "Summary", x = summary_df$category[r], start_row = row_num, start_col = 1)
    wb$add_data(sheet = "Summary", x = summary_df$n_codes[r], start_row = row_num, start_col = 2)
    wb$add_data(sheet = "Summary", x = summary_df$total_records[r], start_row = row_num, start_col = 3)
    wb$add_data(sheet = "Summary", x = summary_df$total_patients[r], start_row = row_num, start_col = 4)

    # Number formatting
    wb$add_numfmt(sheet = "Summary", dims = glue("B{row_num}:D{row_num}"), numfmt = "#,##0")

    # Totals row styling
    if (summary_df$category[r] == "Total") {
      wb$add_fill(sheet = "Summary", dims = glue("A{row_num}:D{row_num}"),
                  color = wb_color("FF374151"))
      wb$add_font(sheet = "Summary", dims = glue("A{row_num}:D{row_num}"),
                  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
    }
  }

  wb$set_col_widths(sheet = "Summary", cols = 1:4, widths = c(20, 12, 12, 12))
  wb$freeze_pane(sheet = "Summary", first_active_row = 4)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual xlsx generation from combined_unmatched_report.xlsx | Regenerate from R/00_config.R TREATMENT_CODES with DuckDB counts | Phase 5 (this phase) | Config is single source of truth; xlsx is derived artifact that can be regenerated as config evolves |
| Phase 39-40 API lookups at runtime | Load pre-computed RDS artifacts (fallback to config comments) | Phase 39-40 (2026-05) | 100x faster description lookup; no NLM/RxNorm API rate limiting |
| openxlsx (v4.x reference classes) | openxlsx2 (R6 API, pure R) | Phase 42 (2026-05-05) | No Java rJava dependency; faster xlsx writing; modern R6 API |
| In-memory CSV reads | DuckDB lazy queries | Phase 30 (2026-04-23, default Phase 32) | 10-100x faster aggregation; constant memory usage |

**Deprecated/outdated:**
- **combined_unmatched_report.xlsx as source of truth:** Now stale (May 5); config has diverged through Phases 45-46 additions. Use R/00_config.R directly.
- **openxlsx v4.x:** R/42 migrated to openxlsx2; avoid openxlsx (old package) for new code.
- **RDS mode (USE_DUCKDB = FALSE):** Deprecated in Phase 32; retained for backward compatibility but will be removed in future milestone.

## Open Questions

1. **Do Phase 39-41 RDS artifacts exist in the current environment?**
   - What we know: output/ is gitignored; RDS files don't transfer across clones
   - What's unclear: Whether collaborator ran Phase 39-40 on this HiPerGator instance
   - Recommendation: Use file.exists() checks with empty tibble fallbacks; script works with or without RDS files (degrades to config comments only)

2. **Should config comment curation be automatic or manual review?**
   - What we know: Phase 39 auto-updated config with parse/source validation; user decision D-07 says "update config comments when better description exists"
   - What's unclear: Whether "better" requires human judgment (e.g., API description is verbose; config comment is concise and domain-specific)
   - Recommendation: Implement optional `--update-config` flag; default is read-only (no config modification), flag enables auto-curation with validation

3. **How to handle ICD-10-PCS prefix matching in count queries?**
   - What we know: TREATMENT_CODES has both exact codes (sct_icd10pcs) and prefix patterns (chemo_icd10pcs_prefixes like "3E03305")
   - What's unclear: Whether prefixes should use str_detect() or expand to all matching codes in data first
   - Recommendation: Use str_detect() for prefixes (established pattern from R/38); annotate code_type as "ICD-10-PCS (prefix)" vs "ICD-10-PCS (exact)"

## Environment Availability

> Script requires HiPerGator execution (D-05). Local execution will fail without DuckDB database file.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| DuckDB database | Patient/record count queries | ✓ (HiPerGator only) | 1.1.0+ | None — phase blocks without DuckDB |
| R 4.4.2+ | Base runtime | ✓ (HiPerGator) | 4.4.2 | None |
| renv packages | All libraries | ✓ (project renv.lock) | locked versions | None |
| Phase 39-41 RDS artifacts | API descriptions | ✗ (optional) | — | Use config comments + hardcoded descriptions |

**Missing dependencies with no fallback:**
- DuckDB database file (CONFIG$cache$duckdb_path) — script blocks if not found; must run on HiPerGator where database was created via R/25_duckdb_ingest.R

**Missing dependencies with fallback:**
- Phase 39-41 RDS artifacts — graceful degradation to config comments + hardcoded descriptions

## Validation Architecture

> Section omitted: workflow.nyquist_validation is explicitly set to false in .planning/config.json.

## Sources

### Primary (HIGH confidence)
- R/00_config.R lines 412-1507 (TREATMENT_CODES structure, TREATMENT_TYPE_COLORS)
- R/42_treatment_codes_resolved.R (write_resolved_xlsx() function, openxlsx2 patterns)
- R/39_investigate_unmatched.R lines 456-718 (config update with parse/source validation)
- R/45_radiation_cpt_audit.R lines 86-115 (hardcoded_descriptions pattern)
- R/01_load_pcornet.R, R/utils_duckdb.R (get_pcornet_table(), DuckDB backend)
- R/utils_treatment.R (safe_table(), empty_result(), nrow_or_0() helpers)
- .planning/phases/05-.../05-CONTEXT.md (user decisions D-01 through D-13)

### Secondary (MEDIUM confidence)
- Git log commits f4de3c5, 9894a75, 13a9de4, e9ef0ba, b865ba5, 657f171 (Phase 45-46 code additions to config)
- all_codes_resolved.xlsx (May 20 15:30, 507KB) — current output to be replaced

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All packages already in project renv.lock; no version verification needed
- Architecture: HIGH - 4 established patterns from R/39, R/42, R/45, utils_duckdb.R reused directly
- Pitfalls: MEDIUM-HIGH - Code type ambiguity and RDS artifact handling based on project history; config corruption prevention from Phase 39 validation pattern (proven robust)

**Research date:** 2026-05-20
**Valid until:** 60 days (stable R ecosystem; openxlsx2 and DuckDB mature packages)
