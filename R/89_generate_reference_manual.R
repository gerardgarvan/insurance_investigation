# ==============================================================================
# 89_generate_reference_manual.R
# ==============================================================================
#
# Purpose:
#   Auto-generate docs/REFERENCE_MANUAL.md by parsing structured 5-field headers
#   from all pipeline scripts. Builds dependency matrix and writes onboarding
#   documentation.
#
# Inputs:
#   - R/*.R and R/utils/*.R script files (header blocks)
#
# Outputs:
#   - docs/REFERENCE_MANUAL.md (complete reference manual)
#
# Dependencies:
#   - (standalone generator script), glue, stringr
#
# Requirements:
#   - DOC-04
#
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP
# ==============================================================================

# Clear workspace
rm(list = ls())

# Load libraries
library(glue)
library(stringr)

# Define output path
output_path <- "docs/REFERENCE_MANUAL.md"

message("=== Reference Manual Generator ===")
message(glue("Output: {output_path}"))

# ==============================================================================
# SECTION 2: HEADER PARSING FUNCTION
# ==============================================================================

parse_script_header <- function(filepath) {
  # Read file
  lines <- readLines(filepath, warn = FALSE)

  # Find header block boundaries (between first # == and closing # == or first non-comment)
  header_start <- which(str_detect(lines, "^#\\s*=+"))[1]

  if (is.na(header_start)) {
    # No header found
    return(list(
      script = basename(filepath),
      purpose = "Not documented",
      inputs = "Not documented",
      outputs = "Not documented",
      dependencies = "Not documented",
      requirements = "Not documented"
    ))
  }

  # Find end of header (second === line or first non-comment line after header_start)
  header_end <- which(str_detect(lines, "^#\\s*=+"))[2]
  if (is.na(header_end)) {
    # Find first non-comment line
    non_comment <- which(!str_detect(lines[(header_start + 1):length(lines)], "^#"))[1]
    if (!is.na(non_comment)) {
      header_end <- header_start + non_comment - 1
    } else {
      header_end <- length(lines)
    }
  }

  # Extract header block
  header_lines <- lines[header_start:header_end]

  # Initialize fields
  fields <- list(
    script = basename(filepath),
    purpose = "Not documented",
    inputs = "Not documented",
    outputs = "Not documented",
    dependencies = "Not documented",
    requirements = "Not documented"
  )

  # Field keywords
  field_keywords <- c("Purpose", "Inputs", "Outputs", "Dependencies", "Requirements")

  # Parse each field
  for (field_name in field_keywords) {
    # Find line matching "# Field:"
    pattern <- glue("^#\\s*{field_name}:\\s*(.*)$")
    field_line_idx <- which(str_detect(header_lines, pattern))[1]

    if (!is.na(field_line_idx)) {
      # Extract first-line value
      match <- str_match(header_lines[field_line_idx], pattern)
      field_value <- str_trim(match[, 2])

      # Collect multi-line continuation (subsequent comment lines with leading whitespace)
      continuation_lines <- c()
      next_idx <- field_line_idx + 1

      while (next_idx <= length(header_lines)) {
        # Check if line is a continuation (starts with # followed by whitespace, not a new field)
        if (str_detect(header_lines[next_idx], "^#\\s{2,}") &&
            !str_detect(header_lines[next_idx], "^#\\s*(Purpose|Inputs|Outputs|Dependencies|Requirements):")) {
          # Extract continuation text
          continuation <- str_replace(header_lines[next_idx], "^#\\s*", "")
          continuation_lines <- c(continuation_lines, str_trim(continuation))
          next_idx <- next_idx + 1
        } else {
          break
        }
      }

      # Combine first line + continuations
      if (length(continuation_lines) > 0) {
        field_value <- paste(c(field_value, continuation_lines), collapse = " ")
      }

      # Store in fields list
      fields[[tolower(field_name)]] <- field_value
    }
  }

  return(fields)
}

# ==============================================================================
# SECTION 3: CONFIG CONSTANT DETECTION
# ==============================================================================

detect_config_constants <- function(filepath) {
  # Exclude R/00_config.R itself (it defines constants, doesn't consume them)
  if (basename(filepath) == "00_config.R") {
    return("None")
  }

  # Read file
  lines <- readLines(filepath, warn = FALSE)

  # Known constants
  known_constants <- c(
    "CONFIG", "EXTRACT_DATE", "PCORNET_TABLES", "PCORNET_PATHS",
    "ICD_CODES", "PAYER_MAPPING", "AMC_PAYER_LOOKUP", "TREATMENT_CODES",
    "ANALYSIS_PARAMS", "CANCER_SITE_MAP", "TIER_MAPPING"
  )

  # Filter to non-comment lines
  code_lines <- lines[!str_detect(lines, "^\\s*#")]

  # Detect which constants are used
  used_constants <- c()
  for (constant in known_constants) {
    # Check if constant appears in any code line
    if (any(str_detect(code_lines, constant))) {
      used_constants <- c(used_constants, constant)
    }
  }

  if (length(used_constants) == 0) {
    return("None")
  } else {
    return(paste(used_constants, collapse = ", "))
  }
}

# ==============================================================================
# SECTION 4: PARSE ALL SCRIPTS
# ==============================================================================

message("\n=== Parsing Scripts ===")

# Get numbered scripts (sorted)
numbered_files <- list.files("R", pattern = "^[0-9]+.*\\.R$", full.names = TRUE)
numbered_files <- sort(numbered_files)

# Get utils scripts (sorted)
utils_files <- list.files("R/utils", pattern = "\\.R$", full.names = TRUE)
utils_files <- sort(utils_files)

# Parse headers for numbered scripts
numbered_headers <- lapply(numbered_files, parse_script_header)

# Parse headers for utils scripts
utils_headers <- lapply(utils_files, parse_script_header)

# Detect config constants for numbered scripts
numbered_constants <- sapply(numbered_files, detect_config_constants)

message(glue("Parsed {length(numbered_headers)} numbered scripts + {length(utils_headers)} utils modules"))

# ==============================================================================
# SECTION 5: GENERATE MARKDOWN
# ==============================================================================

message("\n=== Generating Markdown ===")

# Build content as character vector
content <- c()

# 5a. Title and header
content <- c(content, "# PCORnet Payer Variable Investigation -- Pipeline Reference Manual")
content <- c(content, "")
content <- c(content, glue("> **Auto-generated** by `R/89_generate_reference_manual.R` on {Sys.Date()}."))
content <- c(content, "> To regenerate: `Rscript R/89_generate_reference_manual.R`")
content <- c(content, "")
content <- c(content, "---")
content <- c(content, "")

# 5b. Table of Contents
content <- c(content, "## Table of Contents")
content <- c(content, "")
content <- c(content, "1. [Architecture Overview](#architecture-overview)")
content <- c(content, "2. [Dependency Matrix](#dependency-matrix)")
content <- c(content, "3. [Utils Module Reference](#utils-module-reference)")
content <- c(content, "4. [Run-Order Guide](#run-order-guide)")
content <- c(content, "5. [Config Constants Reference](#config-constants-reference)")
content <- c(content, "6. [Onboarding Guide](#onboarding-guide)")
content <- c(content, "")
content <- c(content, "---")
content <- c(content, "")

# 5c. Architecture Overview
content <- c(content, "## Architecture Overview")
content <- c(content, "")
content <- c(content, "### Decade-Based Organization")
content <- c(content, "")
content <- c(content, "The pipeline uses a decade-based numbering system for logical organization:")
content <- c(content, "")
content <- c(content, "- **00-09 Foundation:** Configuration, data loading, payer harmonization, DuckDB ingest")
content <- c(content, "- **10-19 Cohort:** Named predicates, treatment-anchored payer, cohort building")
content <- c(content, "- **20-29 Treatment:** Treatment inventory, episodes, drug resolution, first-line therapy")
content <- c(content, "- **40-59 Cancer:** Cancer site classification, confirmation, Gantt export, death validation")
content <- c(content, "- **60-69 Payer/QA:** Payer tiering, missingness analysis, multi-source overlap, value audit")
content <- c(content, "- **70-79 Outputs:** Visualizations (waterfall, Sankey), PowerPoint presentations, documentation")
content <- c(content, "- **80-89 Tests:** Backend parity tests, smoke tests, verification scripts")
content <- c(content, "- **90-99 Ad-hoc:** Standalone diagnostics and one-off analysis tools")
content <- c(content, "")
content <- c(content, "### Source Chain Pattern")
content <- c(content, "")
content <- c(content, "The pipeline follows a consistent dependency pattern:")
content <- c(content, "")
content <- c(content, "1. **R/00_config.R** is the root configuration script")
content <- c(content, "2. It auto-sources all **R/utils/*.R** modules via `list.files()`")
content <- c(content, "3. Downstream scripts source `00_config.R` to inherit all utilities and constants")
content <- c(content, "")
content <- c(content, "This creates a clean dependency tree where every script has access to:")
content <- c(content, "- Configuration constants (11 objects: CONFIG, ICD_CODES, PAYER_MAPPING, etc.)")
content <- c(content, "- Utility functions (8 modules: dates, attrition, DuckDB, ICD, payer, PPTX, snapshot, treatment)")
content <- c(content, "")
content <- c(content, "### Named Predicate Pattern")
content <- c(content, "")
content <- c(content, "Cohort building uses human-readable named predicates (`has_*`, `with_*`, `exclude_*`) rather than opaque one-liners. This makes the filter chain read like a clinical protocol:")
content <- c(content, "")
content <- c(content, "```r")
content <- c(content, "cohort <- enrollment %>%")
content <- c(content, "  has_florida_enrollment() %>%")
content <- c(content, "  with_hl_diagnosis() %>%")
content <- c(content, "  exclude_neither_source()")
content <- c(content, "```")
content <- c(content, "")
content <- c(content, "### Defensive Coding")
content <- c(content, "")
content <- c(content, "All production scripts (decades 00-69) use checkmate assertions via **R/utils/utils_assertions.R** helper functions:")
content <- c(content, "")
content <- c(content, "- `assert_rds_exists()`: File existence checks")
content <- c(content, "- `assert_df_valid()`: Data frame structure validation")
content <- c(content, "- `assert_col_types()`: Column type validation")
content <- c(content, "- `warn_date_range()`: Date range warnings")
content <- c(content, "- `warn_row_count()`: Row count sanity checks")
content <- c(content, "")
content <- c(content, "All error messages follow the `[R/XX ACTION] message` format using `glue()` for context-rich diagnostics.")
content <- c(content, "")
content <- c(content, "---")
content <- c(content, "")

# 5d. Dependency Matrix (grouped by decade)
content <- c(content, "## Dependency Matrix")
content <- c(content, "")

# Define decade groups
decade_groups <- list(
  list(name = "Foundation (00-09)", pattern = "^0[0-9]_"),
  list(name = "Cohort (10-19)", pattern = "^1[0-9]_"),
  list(name = "Treatment (20-29)", pattern = "^2[0-9]_"),
  list(name = "Cancer (40-59)", pattern = "^[4-5][0-9]_"),
  list(name = "Payer & QA (60-69)", pattern = "^6[0-9]_"),
  list(name = "Outputs (70-79)", pattern = "^7[0-9]_"),
  list(name = "Tests (80-89)", pattern = "^8[0-9]_"),
  list(name = "Ad-hoc (90-99)", pattern = "^9[0-9]_")
)

for (decade in decade_groups) {
  # Filter scripts for this decade
  decade_scripts <- numbered_headers[str_detect(sapply(numbered_headers, function(x) x$script), decade$pattern)]

  if (length(decade_scripts) == 0) next

  content <- c(content, glue("### {decade$name}"))
  content <- c(content, "")
  content <- c(content, "| Script | Purpose | source() Deps | Inputs | Outputs | Config Constants Used |")
  content <- c(content, "|--------|---------|---------------|--------|---------|----------------------|")

  for (i in seq_along(decade_scripts)) {
    script_info <- decade_scripts[[i]]
    script_name <- script_info$script

    # Find matching constant detection
    script_idx <- which(sapply(numbered_headers, function(x) x$script) == script_name)
    constants_used <- numbered_constants[script_idx]

    # Truncate purpose to ~80 chars
    purpose <- script_info$purpose
    if (nchar(purpose) > 80) {
      purpose <- paste0(substr(purpose, 1, 77), "...")
    }

    # Escape pipe characters in fields
    escape_pipes <- function(text) {
      str_replace_all(text, "\\|", "\\\\|")
    }

    row <- glue("| {escape_pipes(script_name)} | {escape_pipes(purpose)} | {escape_pipes(script_info$dependencies)} | {escape_pipes(script_info$inputs)} | {escape_pipes(script_info$outputs)} | {escape_pipes(constants_used)} |")
    content <- c(content, row)
  }

  content <- c(content, "")
}

content <- c(content, "---")
content <- c(content, "")

# 5e. Utils Module Reference
content <- c(content, "## Utils Module Reference")
content <- c(content, "")
content <- c(content, "Utility modules are auto-sourced by `R/00_config.R` and available to all downstream scripts.")
content <- c(content, "")
content <- c(content, "| Module | Purpose | Key Functions | Used By |")
content <- c(content, "|--------|---------|---------------|---------|")

for (utils_info in utils_headers) {
  # Parse function definitions from file
  utils_file <- file.path("R/utils", utils_info$script)
  utils_lines <- readLines(utils_file, warn = FALSE)

  # Find function definitions (pattern: name <- function)
  func_lines <- grep("^[a-z_]+ <- function", utils_lines, value = TRUE)
  func_names <- str_extract(func_lines, "^[a-z_]+")

  if (length(func_names) > 0) {
    key_functions <- paste(func_names, collapse = ", ")
  } else {
    key_functions <- "N/A"
  }

  # Truncate purpose
  purpose <- utils_info$purpose
  if (nchar(purpose) > 80) {
    purpose <- paste0(substr(purpose, 1, 77), "...")
  }

  row <- glue("| {utils_info$script} | {purpose} | {key_functions} | All scripts via 00_config.R auto-sourcing |")
  content <- c(content, row)
}

content <- c(content, "")
content <- c(content, "---")
content <- c(content, "")

# 5f. Run-Order Guide
content <- c(content, "## Run-Order Guide")
content <- c(content, "")
content <- c(content, "### Recommended Run Order")
content <- c(content, "")
content <- c(content, "#### Foundation (run once per data extract)")
content <- c(content, "")
content <- c(content, "1. `R/00_config.R` -- Loaded automatically by all scripts")
content <- c(content, "2. `R/01_load_pcornet.R` -- Load raw PCORnet tables")
content <- c(content, "3. `R/02_harmonize_payer.R` -- Create payer categories")
content <- c(content, "4. `R/03_duckdb_ingest.R` -- Create DuckDB backend (optional)")
content <- c(content, "")
content <- c(content, "#### Cohort Building")
content <- c(content, "")
content <- c(content, "5. `R/14_build_cohort.R` -- Auto-sources R/10-R/13 via source() chain")
content <- c(content, "")
content <- c(content, "#### Treatment Analysis")
content <- c(content, "")
content <- c(content, "6. `R/20_treatment_inventory.R` through `R/29_first_line_and_death_analysis.R` -- Run sequentially; R/26 depends on R/25")
content <- c(content, "")
content <- c(content, "#### Cancer Site Analysis")
content <- c(content, "")
content <- c(content, "7. `R/40_cancer_site_frequency.R` through `R/53_death_date_validation.R` -- Run sequentially")
content <- c(content, "")
content <- c(content, "#### Payer & QA")
content <- c(content, "")
content <- c(content, "8. `R/60_tiered_same_day_payer.R` through `R/69_per_patient_source_detection.R`")
content <- c(content, "")
content <- c(content, "#### Outputs")
content <- c(content, "")
content <- c(content, "9. `R/70_visualize_waterfall.R` and `R/71_visualize_sankey.R` -- Require cohort")
content <- c(content, "10. `R/72_generate_pptx.R` -- Requires R/75 (auto-sources it)")
content <- c(content, "")
content <- c(content, "**Note:** Ad-hoc scripts (90-99) are standalone and can be run independently.")
content <- c(content, "")
content <- c(content, "---")
content <- c(content, "")

# 5g. Config Constants Reference
content <- c(content, "## Config Constants Reference")
content <- c(content, "")
content <- c(content, "All constants defined in `R/00_config.R` and available to downstream scripts:")
content <- c(content, "")
content <- c(content, "| Constant | Type | Size | Description |")
content <- c(content, "|----------|------|------|-------------|")
content <- c(content, "| CONFIG | list | ~15 elements | Data paths, cache paths, DuckDB settings, performance tuning |")
content <- c(content, "| EXTRACT_DATE | Date | 1 value | PCORnet data extract date (2025-09-15) |")
content <- c(content, "| PCORNET_TABLES | character | 14 tables | PCORnet CDM table names to load |")
content <- c(content, "| PCORNET_PATHS | named vector | 14 paths | Full CSV file paths for each table |")
content <- c(content, "| ICD_CODES | list | 150 codes | HL diagnosis codes (77 ICD-10 + 73 ICD-9) |")
content <- c(content, "| PAYER_MAPPING | named vector | ~50 entries | AMC 8-category payer lookup |")
content <- c(content, "| AMC_PAYER_LOOKUP | data.frame | ~50 rows | Detailed payer code-to-category mapping |")
content <- c(content, "| TREATMENT_CODES | list | 4 types | CPT/HCPCS/NDC codes for radiation, SCT, immunotherapy, supportive care |")
content <- c(content, "| ANALYSIS_PARAMS | list | ~10 params | Thresholds for cohort filtering, HL diagnosis matching |")
content <- c(content, "| CANCER_SITE_MAP | named character | 324 entries | ICD-10 prefix to cancer site category mapping |")
content <- c(content, "| TIER_MAPPING | list | 8 entries | Payer tier classification rules (Medicaid > Medicare > Private) |")
content <- c(content, "")
content <- c(content, "---")
content <- c(content, "")

# 5h. Onboarding Guide
content <- c(content, "## Onboarding Guide")
content <- c(content, "")
content <- c(content, "### HiPerGator Setup")
content <- c(content, "")
content <- c(content, "1. SSH to HiPerGator: `ssh <gatorlink>@hpg.rc.ufl.edu`")
content <- c(content, "2. Load R module: `module load R/4.4.2`")
content <- c(content, "3. Navigate to project: `cd /blue/erin.mobley-hl.bcu/R`")
content <- c(content, "4. Restore packages: `Rscript -e 'renv::restore()'`")
content <- c(content, "5. Verify: `Rscript R/88_smoke_test_comprehensive.R`")
content <- c(content, "")
content <- c(content, "**Data location:** `/orange/erin.mobley-hl.bcu/Mailhot_V1_20250915` (raw PCORnet CSVs)")
content <- c(content, "")
content <- c(content, "### Local Development (Windows/RStudio)")
content <- c(content, "")
content <- c(content, "1. Clone the repository")
content <- c(content, "2. Open `insurance_investigation.Rproj` in RStudio")
content <- c(content, "3. Run `renv::restore()` in R console")
content <- c(content, "4. Run smoke test: `source(\"R/88_smoke_test_comprehensive.R\")`")
content <- c(content, "5. Note: Data-dependent scripts require HiPerGator data mount")
content <- c(content, "")
content <- c(content, "### Output File Locations")
content <- c(content, "")
content <- c(content, "| Directory | Contents |")
content <- c(content, "|-----------|----------|")
content <- c(content, "| output/ | Root output directory |")
content <- c(content, "| output/tables/ | Excel workbooks (.xlsx) |")
content <- c(content, "| output/figures/ | Visualizations (.png, .pdf) |")
content <- c(content, "| output/reports/ | PowerPoint decks (.pptx) |")
content <- c(content, "| output/gantt/ | Gantt chart CSV exports |")
content <- c(content, "| cache/raw/ | RDS cached raw tables |")
content <- c(content, "| cache/cohort/ | RDS cohort and treatment intermediates |")
content <- c(content, "")

# ==============================================================================
# SECTION 6: WRITE OUTPUT
# ==============================================================================

# Ensure docs/ directory exists
dir.create("docs", showWarnings = FALSE)

# Write content
writeLines(content, output_path)

# Print summary
message(glue("\nReference manual written to {output_path}"))
message(glue("  Numbered scripts documented: {length(numbered_headers)}"))
message(glue("  Utils modules documented: {length(utils_headers)}"))
message(glue("  Total lines: {length(content)}"))
message("\nDone.")
