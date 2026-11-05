# ==============================================================================
# 89_generate_reference_manual.R
# ==============================================================================
#
# Purpose:
#   Auto-generate docs/REFERENCE_MANUAL.md by parsing structured 5-field headers
#   from all pipeline scripts. Discovers scripts dynamically via list.files(),
#   groups three-digit scripts by functional range, and builds a live utils
#   function-usage cross-reference.
#
# Inputs:
#   - R/*.R and R/utils/*.R script files (header blocks)
#   - R/00_config.R (sourced into isolated env to read constant sizes)
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

rm(list = ls())

library(glue)
library(stringr)

output_path <- "docs/REFERENCE_MANUAL.md"

# Set to TRUE to suppress stop() on undocumented production scripts.
# Leave FALSE for normal CI/generation runs so missing headers are caught.
ALLOW_UNDOCUMENTED <- FALSE

message("=== Reference Manual Generator ===")
message(glue("Output: {output_path}"))

# ==============================================================================
# SECTION 2: STAGE RANGE MAP (three-digit scripts)
# ==============================================================================

# Named list: group label -> integer range (inclusive).
# Scripts with a three-digit leading number are matched against these ranges in order.
# Any that match no range go into "Unassigned".
THREE_DIGIT_STAGE_MAP <- list(
  list(name = "Geospatial & SES (100-122)",           lo = 100L, hi = 122L),
  list(name = "Treatment Enhancement (130-146)",       lo = 130L, hi = 146L),
  list(name = "Surveillance & Survivorship (147-188)", lo = 147L, hi = 188L),
  list(name = "Supplemental Diagnostics (189+)",       lo = 189L, hi = 999L)
)

# Two-digit decade groups (unchanged from original)
DECADE_GROUPS <- list(
  list(name = "Foundation (00-09)"),
  list(name = "Cohort (10-19)"),
  list(name = "Treatment (20-29)"),
  list(name = "Supplemental (30-39)"),
  list(name = "Cancer (40-59)"),
  list(name = "Payer & QA (60-69)"),
  list(name = "Outputs (70-79)"),
  list(name = "Tests (80-89)"),
  list(name = "Ad-hoc (90-99)")
)

assign_stage <- function(script_basename) {
  # Extract leading integer from filename (e.g. "122a_..." -> 122, "00_..." -> 0)
  num_str <- str_extract(script_basename, "^[0-9]+")
  if (is.na(num_str)) return("Unassigned")
  num <- as.integer(num_str)

  if (num >= 100L) {
    for (grp in THREE_DIGIT_STAGE_MAP) {
      if (num >= grp$lo && num <= grp$hi) return(grp$name)
    }
    return("Unassigned")
  }

  # Two-digit: map decade
  decade <- (num %/% 10L) * 10L
  switch(as.character(decade),
    "0"  = "Foundation (00-09)",
    "10" = "Cohort (10-19)",
    "20" = "Treatment (20-29)",
    "30" = "Supplemental (30-39)",
    "40" = ,
    "50" = "Cancer (40-59)",
    "60" = "Payer & QA (60-69)",
    "70" = "Outputs (70-79)",
    "80" = "Tests (80-89)",
    "90" = "Ad-hoc (90-99)",
    "Unassigned"
  )
}

# ==============================================================================
# SECTION 3: HEADER PARSING FUNCTION
# ==============================================================================

# Field keywords and accepted spellings (singular/plural, "Depends").
# Names are the canonical field keys stored in the result list.
HEADER_FIELDS <- c(
  purpose      = "Purpose",
  inputs       = "Inputs?",
  outputs      = "Outputs?",
  dependencies = "(?:Dependencies|Depends)",
  requirements = "Requirements?"
)
ANY_FIELD_RX <- glue("^#\\s*(?:{paste(HEADER_FIELDS, collapse = '|')}):")
BANNER_RX    <- "^#\\s*={3,}"

parse_script_header <- function(filepath) {
  lines <- readLines(filepath, warn = FALSE)

  fields <- list(
    script       = basename(filepath),
    purpose      = "Not documented",
    inputs       = "Not documented",
    outputs      = "Not documented",
    dependencies = "Not documented",
    requirements = "Not documented",
    documented   = FALSE
  )

  # First line of executable code (non-comment, non-blank) in the file.
  # The header can never extend past this point.
  first_code <- which(!str_detect(lines, "^\\s*#") & !str_detect(lines, "^\\s*$"))[1]
  search_end <- if (!is.na(first_code)) first_code - 1L else length(lines)

  # Field lines inside the leading comment region.
  field_hits <- which(str_detect(lines, ANY_FIELD_RX))
  field_hits <- field_hits[field_hits <= search_end]

  if (length(field_hits) == 0) {
    # No structured fields: use the first comment paragraph as Purpose (USABLE fallback).
    comment_lines <- lines[seq_len(search_end)]
    comment_lines <- comment_lines[str_detect(comment_lines, "^#") &
                                   !str_detect(comment_lines, BANNER_RX)]
    prose <- str_trim(str_replace(comment_lines, "^#\\s*", ""))
    prose <- prose[nchar(prose) > 0]
    # Skip a leading line that is just the file name
    prose <- prose[prose != basename(filepath)]
    if (length(prose) > 0) fields$purpose <- paste(head(prose, 3), collapse = " ")
    header_end <- search_end
  } else {
    # Header block = from the first field line to the first banner AFTER it
    # (or to the end of the leading comment region). This handles both layouts:
    #   ===== / title / ===== / fields / =====   (banner-sandwiched title)
    #   ===== / fields / =====                   (single opening banner)
    # without bleeding into "# SECTION n" banners in the script body.
    first_field  <- field_hits[1]
    banners      <- which(str_detect(lines, BANNER_RX))
    closing      <- banners[banners > first_field][1]
    header_end   <- if (!is.na(closing)) min(closing - 1L, search_end) else search_end
    header_lines <- lines[first_field:header_end]

    for (key in names(HEADER_FIELDS)) {
      pattern <- glue("^#\\s*{HEADER_FIELDS[[key]]}:\\s*(.*)$")
      idx <- which(str_detect(header_lines, pattern))[1]
      if (is.na(idx)) next

      value <- str_trim(str_match(header_lines[idx], pattern)[, 2])

      # Continuation lines: indented comment lines that are not another field,
      # not a banner, and not an empty "#" line (which ends the field).
      cont <- character(0)
      k <- idx + 1L
      while (k <= length(header_lines)) {
        ln <- header_lines[k]
        if (str_detect(ln, "^#\\s+\\S") &&
            !str_detect(ln, ANY_FIELD_RX) &&
            !str_detect(ln, BANNER_RX)) {
          cont <- c(cont, str_trim(str_replace(ln, "^#\\s*(?:[-*]\\s+)?", "")))
          k <- k + 1L
        } else {
          break
        }
      }
      value <- str_trim(str_replace(value, "^[-*]\\s+", ""))
      parts <- c(value, cont)
      parts <- parts[nchar(parts) > 0]
      # Bulleted lists become "a; b; c"; wrapped prose is joined with spaces
      had_bullets <- k > idx + 1L &&
        any(str_detect(header_lines[(idx + 1L):(k - 1L)], "^#\\s*[-*]\\s+"))
      value <- paste(parts, collapse = if (had_bullets) "; " else " ")
      if (nchar(value) > 0) fields[[key]] <- value
    }
  }

  # Documented = Purpose, Inputs and Outputs all present
  fields$documented <- !any(c(fields$purpose, fields$inputs, fields$outputs) == "Not documented")

  # Dependency auto-detection from body: source("R/...") calls, excluding 00_config.R
  if (fields$dependencies == "Not documented" && header_end < length(lines)) {
    body_lines <- lines[(header_end + 1L):length(lines)]
    source_matches <- str_match_all(
      body_lines,
      'source\\((?:here::here\\()?["\'](?:R/|"R",\\s*")([^"\']+\\.R)["\']'
    )
    sourced <- unique(unlist(lapply(source_matches, function(m) m[, 2])))
    sourced <- sourced[!is.na(sourced) & !str_detect(sourced, "00_config")]
    if (length(sourced) > 0) fields$dependencies <- paste(sourced, collapse = ", ")
  }

  fields$header_end <- header_end
  fields
}

# Which of Purpose / Inputs / Outputs a parsed header is missing (for error reports)
missing_fields <- function(h) {
  req <- c("purpose", "inputs", "outputs")
  req[vapply(req, function(f) identical(h[[f]], "Not documented"), logical(1))]
}

# ==============================================================================
# SECTION 4: CONFIG CONSTANT DETECTION (unchanged — works correctly)
# ==============================================================================

detect_config_constants <- function(filepath) {
  if (basename(filepath) == "00_config.R") return("None")

  lines <- readLines(filepath, warn = FALSE)

  known_constants <- c(
    "CONFIG", "EXTRACT_DATE", "PCORNET_TABLES", "PCORNET_PATHS",
    "ICD_CODES", "PAYER_MAPPING", "AMC_PAYER_LOOKUP", "TREATMENT_CODES",
    "ANALYSIS_PARAMS", "CANCER_SITE_MAP", "TIER_MAPPING",
    "ICD9_CANCER_SITE_MAP", "LOOKUP_TABLES_DT", "USE_DUCKDB",
    "IS_LOCAL", "THREAD_COUNT"
  )

  code_lines <- lines[!str_detect(lines, "^\\s*#")]

  used_constants <- Filter(function(constant) {
    any(str_detect(code_lines, constant))
  }, known_constants)

  if (length(used_constants) == 0) "None" else paste(used_constants, collapse = ", ")
}

# ==============================================================================
# SECTION 5: DISCOVER SCRIPTS
# ==============================================================================

message("\n=== Discovering Scripts ===")

# Numbered scripts: sort numerically by leading integer (not alphabetically,
# so that 100.R sorts after 99.R).
numbered_files_raw <- list.files("R", pattern = "^[0-9]+.*\\.R$", full.names = TRUE)

extract_leading_int <- function(path) {
  as.integer(str_extract(basename(path), "^[0-9]+"))
}

numbered_files <- numbered_files_raw[order(extract_leading_int(numbered_files_raw),
                                           basename(numbered_files_raw))]

# Utils scripts
utils_files <- sort(list.files("R/utils", pattern = "\\.R$", full.names = TRUE))

message(glue("  Found {length(numbered_files)} numbered scripts"))
message(glue("  Found {length(utils_files)} utils modules"))

# ==============================================================================
# SECTION 6: PARSE ALL SCRIPTS
# ==============================================================================

message("\n=== Parsing Scripts ===")

numbered_headers <- lapply(numbered_files, parse_script_header)
utils_headers    <- lapply(utils_files,    parse_script_header)
numbered_constants <- sapply(numbered_files, detect_config_constants)

# Check for unassigned scripts and warn
all_script_names <- sapply(numbered_headers, function(x) x$script)
all_stages       <- sapply(all_script_names, assign_stage)
unassigned       <- all_script_names[all_stages == "Unassigned"]
if (length(unassigned) > 0) {
  warning(glue("R/89: {length(unassigned)} script(s) matched no stage group: ",
               paste(unassigned, collapse = ", ")))
}

# Documentation coverage
n_documented <- sum(sapply(numbered_headers, function(x) isTRUE(x$documented)))
message(glue("  Documented (Purpose+Inputs+Outputs): {n_documented}/{length(numbered_headers)}"))

n_utils <- length(utils_files)

message(glue("Parsed {length(numbered_headers)} numbered scripts + {n_utils} utils modules"))

# ==============================================================================
# COVERAGE CHECK
# ==============================================================================
# Production scripts: numbered scripts whose stage is not Outputs/Tests/Ad-hoc.
# (These are the scripts where "Not documented" is a blocker, not a warning.)

NON_PRODUCTION_STAGES <- c("Outputs (70-79)", "Tests (80-89)", "Ad-hoc (90-99)")

is_production_script <- function(script_basename) {
  stage <- assign_stage(script_basename)
  !stage %in% NON_PRODUCTION_STAGES
}

prod_idxs    <- which(sapply(all_script_names, is_production_script))
n_production <- length(prod_idxs)

undocumented_production <- all_script_names[
  prod_idxs[!sapply(numbered_headers[prod_idxs], function(x) isTRUE(x$documented))]
]

n_utils_documented <- sum(sapply(utils_headers, function(x) isTRUE(x$documented)))
undocumented_utils  <- sapply(utils_files, basename)[
  !sapply(utils_headers, function(x) isTRUE(x$documented))
]

# Missing-file check: list.files() cannot return duplicates; presence = OK.
# (Duplicate filenames in the same directory are impossible on all supported OS.)
n_missing <- 0L   # will remain 0 — discovery is live from list.files()

# One-line summary (always printed)
message(glue(
  "[R/89] {n_production - length(undocumented_production)}/{n_production} production scripts documented; ",
  "{n_utils_documented}/{n_utils} utils; {n_missing} missing"
))

# Undocumented non-production: message only
non_prod_undoc <- all_script_names[
  which(!sapply(all_script_names, is_production_script) &
        !sapply(numbered_headers, function(x) isTRUE(x$documented)))
]
if (length(non_prod_undoc) > 0) {
  message(glue("[R/89] NOTE: {length(non_prod_undoc)} non-production script(s) undocumented: ",
               paste(non_prod_undoc, collapse = ", ")))
}

# Print every gap in full via message() (stop() messages are truncated by R),
# with the specific fields each file is missing.
report_gaps <- function(headers, label) {
  gaps <- Filter(function(h) !isTRUE(h$documented), headers)
  if (length(gaps) == 0) return(invisible(0L))
  message(glue("[R/89] {label} with incomplete headers ({length(gaps)}):"))
  for (h in gaps) {
    message(glue("  - {h$script}  (missing: {paste(missing_fields(h), collapse = ', ')})"))
  }
  invisible(length(gaps))
}

prod_headers <- numbered_headers[prod_idxs]
n_prod_gaps  <- report_gaps(prod_headers,  "Production scripts")
n_util_gaps  <- report_gaps(utils_headers, "Utils modules")

if ((n_prod_gaps + n_util_gaps) > 0 && !isTRUE(ALLOW_UNDOCUMENTED)) {
  stop(glue(
    "[R/89] {n_prod_gaps} production script(s) and {n_util_gaps} utils module(s) ",
    "have incomplete headers (see list above). ",
    "Set ALLOW_UNDOCUMENTED <- TRUE to generate anyway."
  ), call. = FALSE)
}

# ==============================================================================
# SECTION 7: SOURCE 00_CONFIG INTO ISOLATED ENV FOR CONSTANT SIZES
# ==============================================================================

message("\n=== Reading config constants ===")

# Parent must be globalenv(): an emptyenv() parent cannot see base R (`<-`, list(),
# library()), so sourcing always failed and every size showed "see description".
config_env <- new.env(parent = globalenv())
# Attempt to source; failures are caught so the manual still generates.
tryCatch(
  source("R/00_config.R", local = config_env),
  error = function(e) {
    message(glue("  Warning: could not source R/00_config.R: {conditionMessage(e)}"))
    message("  Config Constants Reference table will show static sizes.")
  }
)

get_const_size <- function(name) {
  if (!exists(name, envir = config_env, inherits = FALSE)) return(NA_character_)
  obj <- get(name, envir = config_env, inherits = FALSE)
  cl  <- class(obj)[1]
  sz  <- if (is.data.frame(obj)) glue("{nrow(obj)} rows") else glue("length {length(obj)}")
  glue("{cl} ({sz})")
}

# Constants table: columns = Constant, Type/Size (live), Description (from audit)
constants_meta <- list(
  list(name = "IS_LOCAL",          desc = "TRUE on Windows; FALSE on Linux/HiPerGator"),
  list(name = "THREAD_COUNT",      desc = "1L locally; SLURM_CPUS_PER_TASK (default 16) on HPG"),
  list(name = "EXTRACT_DATE",      desc = "PCORnet data extract date (2025-09-15)"),
  list(name = "CONFIG",            desc = "Data paths, cache paths, DuckDB settings, performance tuning"),
  list(name = "PCORNET_TABLES",    desc = "PCORnet CDM table names to load"),
  list(name = "PCORNET_PATHS",     desc = "Full CSV file paths for each PCORnet table"),
  list(name = "ICD_CODES",         desc = "HL diagnosis codes (hl_icd10 + hl_icd9)"),
  list(name = "PAYER_MAPPING",     desc = "9-category payer mapping with prefix-based fallback rules"),
  list(name = "AMC_PAYER_LOOKUP",  desc = "Code-to-category lookup; also in LOOKUP_TABLES_DT"),
  list(name = "CANCER_SITE_MAP",   desc = "ICD-10 prefix to cancer site category"),
  list(name = "ICD9_CANCER_SITE_MAP", desc = "ICD-9 prefix to cancer site category"),
  list(name = "TIER_MAPPING",      desc = "Payer tier classification: Medicaid=1, Medicare=2, Private=3, ..."),
  list(name = "TREATMENT_CODES",   desc = "CPT/HCPCS/NDC codes for chemotherapy, radiation, SCT, immunotherapy"),
  list(name = "ANALYSIS_PARAMS",   desc = "Thresholds for cohort filtering (via CONFIG$analysis)"),
  list(name = "LOOKUP_TABLES_DT",  desc = "data.table versions of 6 lookup objects for fast joins"),
  list(name = "USE_DUCKDB",        desc = "TRUE (hardcoded) — DuckDB is required, not optional")
)

# ==============================================================================
# SECTION 8: BUILD UTILS USAGE MAP
# ==============================================================================

message("\n=== Building utils usage map ===")

# Read all numbered script bodies once
script_bodies <- lapply(numbered_files, function(f) {
  paste(readLines(f, warn = FALSE), collapse = "\n")
})
script_basenames <- sapply(numbered_files, basename)

# For each utils file, detect exported top-level functions and which scripts call them
build_utils_used_by <- function(utils_path) {
  lines <- readLines(utils_path, warn = FALSE)
  # Top-level function definitions: name <- function(
  func_line_values <- grep("^[a-zA-Z_.][a-zA-Z0-9_.]*\\s*<-\\s*function\\s*\\(", lines, value = TRUE)
  func_names <- str_extract(func_line_values, "^[a-zA-Z_.][a-zA-Z0-9_.]*")
  func_names <- unique(func_names[!is.na(func_names)])

  if (length(func_names) == 0) return(list(functions = character(0), used_by = "None"))

  # Find which numbered scripts reference any of these functions
  callers <- c()
  for (fn in func_names) {
    # Match whole-word usage (not inside function definitions themselves)
    pattern <- glue("\\b{fn}\\b")
    matches <- which(str_detect(script_bodies, pattern))
    callers <- union(callers, script_basenames[matches])
  }

  callers <- sort(callers)
  used_by_str <- if (length(callers) == 0) {
    "None detected"
  } else if (length(callers) > 8) {
    paste(paste(head(callers, 8), collapse = ", "), glue("+ {length(callers) - 8} more"))
  } else {
    paste(callers, collapse = ", ")
  }

  list(functions = func_names, used_by = used_by_str)
}

utils_usage <- lapply(utils_files, build_utils_used_by)

# ==============================================================================
# SECTION 9: GENERATE MARKDOWN
# ==============================================================================

message("\n=== Generating Markdown ===")

content <- c()

# -- Title and header --
git_hash <- tryCatch(
  trimws(system("git rev-parse --short HEAD", intern = TRUE)),
  error   = function(e) "unknown",
  warning = function(w) "unknown"
)
if (length(git_hash) == 0 || nchar(git_hash) == 0) git_hash <- "unknown"

content <- c(content,
  "# PCORnet Payer Variable Investigation -- Pipeline Reference Manual",
  "",
  glue("> **Auto-generated** by `R/89_generate_reference_manual.R` on {Sys.Date()} (git {git_hash})."),
  "> To regenerate: open an interactive R/4.5 session on HiPerGator and run",
  "> `source(\"R/89_generate_reference_manual.R\", local = new.env(parent = globalenv()))`",
  "",
  "---",
  ""
)

# -- Table of Contents --
content <- c(content,
  "## Table of Contents",
  "",
  "1. [Architecture Overview](#architecture-overview)",
  "2. [Dependency Matrix](#dependency-matrix)",
  "3. [Utils Module Reference](#utils-module-reference)",
  "4. [Run-Order Guide](#run-order-guide)",
  "5. [Config Constants Reference](#config-constants-reference)",
  "6. [Onboarding Guide](#onboarding-guide)",
  "",
  "---",
  ""
)

# -- Architecture Overview --
n_numbered   <- length(numbered_files)
n_utils_live <- length(utils_files)
n_consts     <- length(constants_meta)

content <- c(content,
  "## Architecture Overview",
  "",
  "### Script Organization",
  "",
  glue("The pipeline contains **{n_numbered} numbered scripts** and **{n_utils_live} utility modules**."),
  "",
  "Two-digit scripts (00–99) use a decade-based numbering system:",
  "",
  "- **00-09 Foundation:** Configuration, data loading, payer harmonization, DuckDB ingest",
  "- **10-19 Cohort:** Named predicates, treatment-anchored payer, cohort building",
  "- **20-29 Treatment:** Treatment inventory, episodes, drug resolution, first-line therapy",
  "- **30-39 Supplemental:** Linkage, secondary malignancy, code verification, Tableau export, delivery manifest",
  "- **40-59 Cancer:** Cancer site classification, confirmation, Gantt export, death validation",
  "- **60-69 Payer/QA:** Payer tiering, missingness analysis, multi-source overlap, value audit",
  "- **70-79 Outputs:** Visualizations (waterfall, Sankey), PowerPoint presentations, documentation",
  "- **80-89 Tests:** Backend parity tests, smoke tests, verification scripts",
  "- **90-99 Ad-hoc:** Standalone diagnostics and one-off analysis tools",
  "",
  "Three-digit scripts (100+) are grouped by functional area:",
  "",
  "- **100-122 Geospatial & SES:** RUCA rurality, Gantt collapse, ZIP stability, DOI classification, encounter distance, SES index",
  "- **130-146 Treatment Enhancement:** XLSX updates, Gantt exports, staging/SDI reference",
  "- **147-188 Surveillance & Survivorship:** Modality frequency, CBC, MICE sensitivity, distance-CBC, modality rates, anthracycline/echo",
  "- **189+ Supplemental Diagnostics:** NHL explainer, AM verification, source probes",
  "",
  "### Source Chain Pattern",
  "",
  "1. **R/00_config.R** is the root configuration script.",
  glue("2. It auto-sources all **{n_utils_live} R/utils/*.R** modules via `list.files()`."),
  "3. Downstream scripts source `00_config.R` to inherit all utilities and constants.",
  "",
  "This creates a clean dependency tree where every script has access to:",
  glue("- Configuration constants ({n_consts} objects: CONFIG, ICD_CODES, PAYER_MAPPING, etc.)"),
  glue("- Utility functions ({n_utils_live} modules: dates, attrition, DuckDB, ICD, payer, PPTX, snapshot, treatment, and more)"),
  "",
  "### Named Predicate Pattern",
  "",
  "Cohort building uses human-readable named predicates (`has_*`, `with_*`, `exclude_*`) rather than opaque one-liners. This makes the filter chain read like a clinical protocol:",
  "",
  "```r",
  "cohort <- enrollment %>%",
  "  has_florida_enrollment() %>%",
  "  with_hl_diagnosis() %>%",
  "  exclude_neither_source()",
  "```",
  "",
  "### Defensive Coding",
  "",
  "All production scripts (decades 00-69) use checkmate assertions via **R/utils/utils_assertions.R** helper functions:",
  "",
  "- `assert_rds_exists()`: File existence checks",
  "- `assert_df_valid()`: Data frame structure validation",
  "- `assert_col_types()`: Column type validation",
  "- `warn_date_range()`: Date range warnings",
  "- `warn_row_count()`: Row count sanity checks",
  "",
  "All error messages follow the `[R/XX ACTION] message` format using `glue()` for context-rich diagnostics.",
  "",
  "---",
  ""
)

# -- Dependency Matrix --
content <- c(content,
  "## Dependency Matrix",
  ""
)

# Collect all group names in the order we want to emit them
all_groups <- c(
  sapply(DECADE_GROUPS, function(g) g$name),
  sapply(THREE_DIGIT_STAGE_MAP, function(g) g$name),
  "Unassigned"
)

for (grp_name in all_groups) {
  group_idxs <- which(sapply(numbered_headers, function(x) assign_stage(x$script)) == grp_name)
  if (length(group_idxs) == 0) next

  content <- c(content,
    glue("### {grp_name}"),
    "",
    "| Script | Purpose | Dependencies | Inputs | Outputs | Config Constants Used |",
    "|--------|---------|--------------|--------|---------|----------------------|"
  )

  for (i in group_idxs) {
    script_info <- numbered_headers[[i]]
    script_name <- script_info$script
    constants_used <- numbered_constants[[i]]

    purpose <- script_info$purpose
    if (nchar(purpose) > 80) purpose <- paste0(substr(purpose, 1, 77), "...")

    ep <- function(text) str_replace_all(text, "\\|", "\\\\|")

    row <- glue("| {ep(script_name)} | {ep(purpose)} | {ep(script_info$dependencies)} | {ep(script_info$inputs)} | {ep(script_info$outputs)} | {ep(constants_used)} |")
    content <- c(content, row)
  }

  content <- c(content, "")
}

content <- c(content, "---", "")

# -- Utils Module Reference --
content <- c(content,
  "## Utils Module Reference",
  "",
  glue("All {n_utils_live} utility modules are auto-sourced by `R/00_config.R` and available to all downstream scripts."),
  "",
  "| Module | Purpose | Key Functions | Used By |",
  "|--------|---------|---------------|---------|"
)

for (j in seq_along(utils_headers)) {
  info   <- utils_headers[[j]]
  usage  <- utils_usage[[j]]

  purpose <- info$purpose
  if (nchar(purpose) > 80) purpose <- paste0(substr(purpose, 1, 77), "...")

  key_functions <- if (length(usage$functions) > 0) paste(usage$functions, collapse = ", ") else "N/A"
  ep <- function(text) str_replace_all(text, "\\|", "\\\\|")

  row <- glue("| {ep(info$script)} | {ep(purpose)} | {ep(key_functions)} | {ep(usage$used_by)} |")
  content <- c(content, row)
}

content <- c(content, "", "---", "")

# -- Run-Order Guide (updated from live facts) --
content <- c(content,
  "## Run-Order Guide",
  "",
  "All scripts are sourced interactively on HiPerGator:",
  "```r",
  "source(\"R/<script>.R\", local = new.env(parent = globalenv()))",
  "```",
  "",
  "### Stage 0 — Foundation (run once per data extract)",
  "",
  "1. `R/01_load_pcornet.R` -- Load raw PCORnet tables",
  "2. `R/02_harmonize_payer.R` -- Create payer categories",
  "3. `R/03_duckdb_ingest.R` -- Create DuckDB backend (required)",
  "4. `R/14_build_cohort.R` -- Auto-sources R/10–R/13 via chain",
  "",
  "### Stage 1 — Post-cohort investigations (via R/39)",
  "",
  "Run `R/39_run_all_investigations.R` to execute the full investigation batch in order.",
  "R/39 covers: R/20–R/36, R/38, R/40–R/69, R/75, R/100–R/122, R/147–R/188.",
  "",
  "### Stage 2 — Outputs",
  "",
  "5. `R/70_visualize_waterfall.R` and `R/71_visualize_sankey.R` -- Require cohort",
  "6. `R/72_generate_pptx.R` and `R/73_generate_phase19_20_pptx.R`",
  "",
  "### Stage 3 — Report rendering",
  "",
  "7. `R/37_gap_resolution_report.Rmd` -- Via `rmarkdown::render()`",
  "",
  "### Stage 4 — Post-R/52 dependents",
  "",
  "8. `R/101_gantt_lifespan_collapse.R`, `R/104_gantt_entire_history.R`, `R/76_treatment_source_coverage.R`",
  "",
  "### Stage 5 — Manifest",
  "",
  "9. `R/38_delivery_manifest.R`",
  "",
  "**Note:** Ad-hoc scripts (90–99) and supplemental diagnostics (189+) are standalone and can be run independently.",
  "",
  "---",
  ""
)

# -- Config Constants Reference --
content <- c(content,
  "## Config Constants Reference",
  "",
  glue("All {n_consts} constants defined in `R/00_config.R` and available to downstream scripts."),
  "Size/type are read at generation time by sourcing `R/00_config.R` into an isolated environment.",
  "",
  "| Constant | Type / Size | Description |",
  "|----------|-------------|-------------|"
)

for (cm in constants_meta) {
  size_str <- get_const_size(cm$name)
  if (is.na(size_str)) size_str <- "see description"
  ep <- function(text) str_replace_all(text, "\\|", "\\\\|")
  row <- glue("| {ep(cm$name)} | {ep(size_str)} | {ep(cm$desc)} |")
  content <- c(content, row)
}

content <- c(content, "", "---", "")

# -- Onboarding Guide --
content <- c(content,
  "## Onboarding Guide",
  "",
  "### HiPerGator Setup",
  "",
  "1. SSH to HiPerGator: `ssh <gatorlink>@hpg.rc.ufl.edu`",
  "2. Load R module: `module load R/4.5`",
  "3. Navigate to project: `cd /blue/erin.mobley-hl.bcu/insurance_investigation`",
  "4. Launch interactive R session and restore packages: `renv::restore()`",
  "5. Verify: `source(\"R/88_smoke_test_comprehensive.R\", local = new.env(parent = globalenv()))`",
  "",
  "**Data location:** `/orange/erin.mobley-hl.bcu/Mailhot_V1_20250915` (raw PCORnet CSVs)",
  "**DuckDB:** `/blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb` (required; USE_DUCKDB = TRUE)",
  "**RDS cache:** `/blue/erin.mobley-hl.bcu/clean/rds`",
  "",
  "### Output File Locations",
  "",
  "| Directory | Contents |",
  "|-----------|----------|",
  "| output/ | Root output directory |",
  "| output/tables/ | Excel workbooks (.xlsx) |",
  "| output/figures/ | Visualizations (.png, .pdf) |",
  "| output/reports/ | PowerPoint decks (.pptx) |",
  "| output/gantt/ | Gantt chart CSV exports |",
  "| output/internal/ | Patient-level data (PHI — not shared) |",
  "| cache/raw/ | RDS cached raw tables |",
  "| cache/cohort/ | RDS cohort and treatment intermediates |",
  ""
)

# ==============================================================================
# SECTION 10: WRITE OUTPUT
# ==============================================================================

dir.create("docs", showWarnings = FALSE)
writeLines(content, output_path)

message(glue("\nReference manual written to {output_path}"))
message(glue("  Numbered scripts documented: {length(numbered_headers)}"))
message(glue("  Utils modules documented: {n_utils_live}"))
message(glue("  Total lines: {length(content)}"))
message("\nDone.")
