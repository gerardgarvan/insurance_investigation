# ==============================================================================
# Phase 47: Cancer Site Frequency
# ==============================================================================
# Frequency table of all 42 cancer site categories from CancerSiteCategories.xlsx
# across all patients in the PCORnet extract (not just HL cohort).
#
# Inputs:
#   - CancerSiteCategories.xlsx (Groups sheet, 42 categories)
#   - DIAGNOSIS DuckDB table (ICD-10 codes)
#   - TUMOR_REGISTRY_ALL DuckDB table (ICD-O-3 topography codes)
#
# Outputs:
#   - output/tables/cancer_site_frequency.xlsx (styled single-sheet workbook)
#
# Usage:
#   Rscript R/47_cancer_site_frequency.R
#
# Requirements: CSITE-01, CSITE-02
# Phase 47 Plan 01
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(openxlsx2)
  library(readxl)
  library(purrr)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")

OUTPUT_PATH <- file.path(CONFIG$output_dir, "tables", "cancer_site_frequency.xlsx")
dir.create(dirname(OUTPUT_PATH), showWarnings = FALSE, recursive = TRUE)

message("=== Phase 47: Cancer Site Frequency ===")
message(glue("Output: {OUTPUT_PATH}"))

# ==============================================================================
# SECTION 2: LOAD AND PARSE CancerSiteCategories.xlsx
# ==============================================================================

message("Loading CancerSiteCategories.xlsx (Groups sheet)...")

groups_raw <- read_excel("CancerSiteCategories.xlsx", sheet = "Groups")

# Use positional column selection to avoid column name ambiguity
groups_df <- groups_raw %>%
  select(category = 1, icd10 = 2, icdo3 = 3)

# Verify 42 categories
stopifnot("Expected 42 categories in CancerSiteCategories.xlsx Groups sheet" = nrow(groups_df) == 42)
message(glue("Loaded {nrow(groups_df)} categories (expected 42) -- OK"))

n_icd10_nonna <- sum(!is.na(groups_df$icd10))
n_icdo3_nonna <- sum(!is.na(groups_df$icdo3))
message(glue("  Categories with non-NA ICD-10 codes: {n_icd10_nonna}"))
message(glue("  Categories with non-NA ICD-O-3 codes: {n_icdo3_nonna}"))

# ==============================================================================
# SECTION 3: RANGE EXPANSION FUNCTIONS
# ==============================================================================

#' Expand a single token that may be a range (e.g., "C000-C006") or single code (e.g., "C01")
#' @param token Character. Single trimmed token (no commas).
#' @return Character vector of expanded codes, normalized via normalize_icd()
expand_icd_token <- function(token) {
  token <- str_trim(token)

  if (!str_detect(token, "-")) {
    # Single code
    return(normalize_icd(token))
  }

  # Range: split on first "-" only (handles codes like "C7A010-C7A012")
  parts <- str_split(token, "-", n = 2)[[1]]
  start <- str_trim(parts[1])
  end   <- str_trim(parts[2])

  # Extract prefix (everything before the trailing digit sequence) and numeric suffix
  # Strategy: find the longest alphabetic-or-mixed prefix, then trailing digits
  # Pattern: prefix = everything up to (but not including) the trailing digit run
  prefix_start <- str_extract(start, "^.*?(?=\\d+$)")
  suffix_start <- str_extract(start, "\\d+$")
  prefix_end   <- str_extract(end,   "^.*?(?=\\d+$)")
  suffix_end   <- str_extract(end,   "\\d+$")

  # If we can't extract numeric suffixes or prefixes differ, warn and return endpoints
  if (is.na(suffix_start) || is.na(suffix_end) || is.na(prefix_start) || is.na(prefix_end)) {
    warning(glue("expand_icd_token: cannot parse range '{token}' -- returning endpoints only"))
    return(normalize_icd(c(start, end)))
  }

  # Normalize prefix to uppercase for consistent matching
  prefix_start_up <- toupper(prefix_start)
  prefix_end_up   <- toupper(prefix_end)

  if (prefix_start_up != prefix_end_up) {
    warning(glue("expand_icd_token: range endpoints have different prefixes in '{token}' ({prefix_start_up} vs {prefix_end_up}) -- returning endpoints only"))
    return(normalize_icd(c(start, end)))
  }

  start_n <- as.integer(suffix_start)
  end_n   <- as.integer(suffix_end)
  width   <- nchar(suffix_start)  # zero-pad to start suffix width

  if (is.na(start_n) || is.na(end_n)) {
    warning(glue("expand_icd_token: non-numeric suffix in '{token}' -- returning endpoints only"))
    return(normalize_icd(c(start, end)))
  }

  codes <- paste0(prefix_start_up, formatC(start_n:end_n, width = width, flag = "0"))
  normalize_icd(codes)
}

#' Expand a full code string from xlsx (comma-separated, may include ranges)
#' @param code_str Character. Full cell value like "C000-C006, C008-C009, C01"
#' @return Character vector of all individual normalized codes (unique)
expand_code_string <- function(code_str) {
  if (is.na(code_str) || str_trim(code_str) == "") return(character(0))
  tokens <- str_split(code_str, ",")[[1]]
  result <- unlist(lapply(tokens, expand_icd_token))
  unique(result[!is.na(result)])
}

# ==============================================================================
# SECTION 4: BUILD PREFIX LOOKUP (first match wins)
# ==============================================================================

message("Building ICD-10 and ICD-O-3 prefix lookups (first match wins)...")

# Build ICD-10 lookup: expanded code -> category index (first match wins)
icd10_prefix_to_cat <- list()
for (i in seq_len(nrow(groups_df))) {
  codes_i <- expand_code_string(groups_df$icd10[i])
  new_codes <- setdiff(codes_i, names(icd10_prefix_to_cat))
  for (c in new_codes) icd10_prefix_to_cat[[c]] <- i
}

# Build ICD-O-3 lookup: expanded code -> category index (first match wins)
# Per phase decision: SKIP categories where all expanded codes are in morphology range (8000-9999)
# These are topography codes in TOPOGRAPHY_CODE/ICDOSITE, not morphology
icdo3_prefix_to_cat <- list()
skipped_morph_cats <- integer(0)

for (i in seq_len(nrow(groups_df))) {
  codes_i <- expand_code_string(groups_df$icdo3[i])

  if (length(codes_i) == 0) next

  # Check if all codes are in the morphology range (8000-9999, pure digits, no C prefix)
  # Morphology codes are pure 4-digit integers >= 8000
  # Topography codes have a C prefix (e.g., C810) or are C + 3 digits
  # After normalize_icd(), topography codes start with C; morphology codes are pure digits
  is_pure_numeric <- !str_detect(codes_i, "^[A-Z]")
  numeric_vals <- suppressWarnings(as.integer(codes_i))
  is_morphology <- is_pure_numeric & !is.na(numeric_vals) & numeric_vals >= 8000

  if (all(is_morphology)) {
    # All codes in this category's ICDO3 column are morphology codes -- skip per phase decision
    skipped_morph_cats <- c(skipped_morph_cats, i)
    next
  }

  # Add topography codes to lookup (first match wins)
  new_codes <- setdiff(codes_i, names(icdo3_prefix_to_cat))
  for (c in new_codes) icdo3_prefix_to_cat[[c]] <- i
}

message(glue("Built ICD-10 prefix lookup: {length(icd10_prefix_to_cat)} unique prefixes across 42 categories"))
message(glue("Built ICD-O-3 prefix lookup: {length(icdo3_prefix_to_cat)} unique prefixes across {42 - length(skipped_morph_cats)} categories (skipped {length(skipped_morph_cats)} morphology-only categories)"))

# ==============================================================================
# SECTION 5: QUERY DATA AND COUNT
# ==============================================================================

# --- ICD-10 from DIAGNOSIS ---

message("Loading DIAGNOSIS table (ICD-10 only, all patients)...")

diagnosis_icd10 <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  select(ID, DX, ENCOUNTERID) %>%
  materialize() %>%
  mutate(DX_norm = normalize_icd(DX))

message(glue("Loaded {format(nrow(diagnosis_icd10), big.mark = ',')} ICD-10 DIAGNOSIS rows"))

# --- ICD-O-3 from TUMOR_REGISTRY_ALL ---

message("Loading TUMOR_REGISTRY_ALL table (topography codes, all patients)...")

tr_topo <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
  mutate(topo_raw = coalesce(SITE_CODE, SITE)) %>%
  select(ID, topo_raw) %>%
  filter(!is.na(topo_raw)) %>%
  materialize() %>%
  mutate(topo_norm = normalize_icd(topo_raw))

message(glue("Loaded {format(nrow(tr_topo), big.mark = ',')} TUMOR_REGISTRY rows with topography codes"))
message(glue("  Sample topography values (first 10 unique): {paste(head(unique(tr_topo$topo_norm), 10), collapse = ', ')}"))

# --- Matching per category ---

message("Computing per-category counts (42 categories x ICD-10 and ICD-O-3)...")

# Get expanded codes per category (cached to avoid re-expanding in loop)
icd10_codes_by_cat <- lapply(seq_len(nrow(groups_df)), function(i) {
  expand_code_string(groups_df$icd10[i])
})
icdo3_codes_by_cat <- lapply(seq_len(nrow(groups_df)), function(i) {
  expand_code_string(groups_df$icdo3[i])
})

# Collectors for combined unique patient IDs (for overall total)
all_matched_ids_icd10 <- character(0)
all_matched_ids_icdo3 <- character(0)

# Per-category result vectors
cat_icd10_patients   <- integer(42)
cat_icd10_encounters <- integer(42)
cat_icdo3_patients   <- integer(42)
cat_icdo3_records    <- integer(42)
cat_combined_patients <- integer(42)

for (i in seq_len(nrow(groups_df))) {

  # ICD-10 matching
  icd10_codes_i <- icd10_codes_by_cat[[i]]
  if (length(icd10_codes_i) > 0) {
    dx_matches <- diagnosis_icd10 %>%
      filter(map_lgl(DX_norm, function(dx) any(startsWith(dx, icd10_codes_i))))
    cat_icd10_patients[i]   <- n_distinct(dx_matches$ID)
    cat_icd10_encounters[i] <- n_distinct(dx_matches$ENCOUNTERID)
    all_matched_ids_icd10   <- c(all_matched_ids_icd10, dx_matches$ID)
  } else {
    dx_matches <- diagnosis_icd10[0, ]
    cat_icd10_patients[i]   <- 0L
    cat_icd10_encounters[i] <- 0L
  }

  # ICD-O-3 matching (topography only)
  icdo3_codes_i <- icdo3_codes_by_cat[[i]]

  # Check if this category has morphology codes (8000-9999 pure digits) -- skip per phase decision
  if (length(icdo3_codes_i) > 0) {
    is_pure_numeric <- !str_detect(icdo3_codes_i, "^[A-Z]")
    numeric_vals <- suppressWarnings(as.integer(icdo3_codes_i))
    is_morphology <- is_pure_numeric & !is.na(numeric_vals) & numeric_vals >= 8000
    if (all(is_morphology)) {
      icdo3_codes_i <- character(0)  # Skip morphology categories
    }
  }

  if (length(icdo3_codes_i) > 0) {
    tr_matches <- tr_topo %>%
      filter(map_lgl(topo_norm, function(t) any(startsWith(t, icdo3_codes_i))))
    cat_icdo3_patients[i] <- n_distinct(tr_matches$ID)
    cat_icdo3_records[i]  <- nrow(tr_matches)
    all_matched_ids_icdo3 <- c(all_matched_ids_icdo3, tr_matches$ID)
  } else {
    tr_matches <- tr_topo[0, ]
    cat_icdo3_patients[i] <- 0L
    cat_icdo3_records[i]  <- 0L
  }

  # Combined unique patients for this category
  cat_combined_patients[i] <- n_distinct(c(dx_matches$ID, tr_matches$ID))

  if (i %% 10 == 0) message(glue("  Processed {i}/42 categories..."))
}

message("All 42 categories processed.")

# Build result data frame (42 data rows)
result_df <- tibble(
  category          = groups_df$category,
  icd10_patients    = cat_icd10_patients,
  icd10_encounters  = cat_icd10_encounters,
  icdo3_patients    = cat_icdo3_patients,
  icdo3_records     = cat_icdo3_records,
  combined_patients = cat_combined_patients
)

# Totals row: sum per-column numerics; combined_patients = true n_distinct across all sources
total_combined <- n_distinct(c(all_matched_ids_icd10, all_matched_ids_icdo3))

totals_row <- tibble(
  category          = "TOTAL",
  icd10_patients    = sum(result_df$icd10_patients),
  icd10_encounters  = sum(result_df$icd10_encounters),
  icdo3_patients    = sum(result_df$icdo3_patients),
  icdo3_records     = sum(result_df$icdo3_records),
  combined_patients = total_combined
)

message("")
message("=== COUNT SUMMARY ===")
message(glue("Total unique patients across all cancer sites: {format(total_combined, big.mark = ',')}"))
message(glue("  ICD-10 DIAGNOSIS rows used: {format(nrow(diagnosis_icd10), big.mark = ',')}"))
message(glue("  TUMOR_REGISTRY topography rows used: {format(nrow(tr_topo), big.mark = ',')}"))

# Spot-check: Hodgkin Lymphoma (row 35 in spreadsheet order)
hl_row <- result_df %>% filter(category == "Hodgkin Lymphoma")
if (nrow(hl_row) == 1) {
  message(glue("  Hodgkin Lymphoma: ICD-10 patients={format(hl_row$icd10_patients, big.mark=',')}, ICD-O-3 patients={format(hl_row$icdo3_patients, big.mark=',')}"))
}

# ==============================================================================
# SECTION 6: WRITE STYLED XLSX
# ==============================================================================

message("")
message(glue("Writing styled xlsx to {OUTPUT_PATH}..."))

DARK_HEADER_FILL <- "FF374151"
WHITE_FONT       <- "FFFFFFFF"
TITLE_FONT_COLOR <- "FF1F2937"
TOTALS_FILL      <- "FFE5E7EB"  # light gray for totals row

n_cols <- 6L

wb     <- wb_workbook()
SHEET1 <- "Cancer Site Frequency"
wb$add_worksheet(SHEET1)

# ---------------------------------------------------------------------------
# Row 1: Title
# ---------------------------------------------------------------------------
wb$add_data(sheet = SHEET1, x = "Cancer Site Frequency - All Patients",
            start_row = 1, start_col = 1)
wb$add_font(sheet = SHEET1, dims = "A1",
            name = "Calibri", size = 16, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$merge_cells(sheet = SHEET1, dims = glue("A1:{int2col(n_cols)}1"))

# ---------------------------------------------------------------------------
# Row 2: Headers
# ---------------------------------------------------------------------------
headers <- c(
  "Cancer Site Category",
  "ICD-10 Patients",
  "ICD-10 Encounters",
  "ICD-O-3 Patients",
  "ICD-O-3 Registry Records",
  "Combined Unique Patients"
)

for (i in seq_along(headers)) {
  wb$add_data(sheet = SHEET1, x = headers[i], start_row = 2, start_col = i)
}

wb$add_fill(sheet = SHEET1,
            dims  = glue("A2:{int2col(n_cols)}2"),
            color = wb_color(DARK_HEADER_FILL))
wb$add_font(sheet = SHEET1,
            dims  = glue("A2:{int2col(n_cols)}2"),
            name  = "Calibri", size = 11, bold = TRUE,
            color = wb_color(WHITE_FONT))

# ---------------------------------------------------------------------------
# Freeze pane at row 3 (title + header visible when scrolling)
# ---------------------------------------------------------------------------
wb$freeze_pane(sheet = SHEET1, first_active_row = 3, first_active_col = 1)

# ---------------------------------------------------------------------------
# Data rows 3 through 44 (42 category rows)
# ---------------------------------------------------------------------------
write_data <- result_df %>% as.data.frame()
wb$add_data(sheet = SHEET1, x = write_data, start_row = 3, col_names = FALSE)

# Number format #,##0 for count columns B:F (rows 3 to 44)
wb$add_numfmt(sheet = SHEET1,
              dims  = glue("B3:{int2col(n_cols)}44"),
              numfmt = "#,##0")

# ---------------------------------------------------------------------------
# Totals row at row 45
# ---------------------------------------------------------------------------
totals_data <- totals_row %>% as.data.frame()
wb$add_data(sheet = SHEET1, x = totals_data, start_row = 45, col_names = FALSE)

# Style totals row: light gray fill, bold font
wb$add_fill(sheet = SHEET1,
            dims  = glue("A45:{int2col(n_cols)}45"),
            color = wb_color(TOTALS_FILL))
wb$add_font(sheet = SHEET1,
            dims  = glue("A45:{int2col(n_cols)}45"),
            name  = "Calibri", size = 11, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))

# Number format for totals count columns
wb$add_numfmt(sheet = SHEET1,
              dims  = glue("B45:{int2col(n_cols)}45"),
              numfmt = "#,##0")

# ---------------------------------------------------------------------------
# Column widths
# ---------------------------------------------------------------------------
wb$set_col_widths(sheet = SHEET1,
                  cols   = 1:n_cols,
                  widths = c(38, 16, 18, 16, 24, 24))

# ---------------------------------------------------------------------------
# Save workbook
# ---------------------------------------------------------------------------
wb$save(OUTPUT_PATH)
message(glue("Wrote {OUTPUT_PATH}"))
message(glue("  Sheet '{SHEET1}': 42 category rows + TOTAL row (43 data rows)"))
message(glue("  Columns: {paste(headers, collapse = ' | ')}"))

message("")
message("=== Phase 47 Cancer Site Frequency Complete ===")
