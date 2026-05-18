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
#     Long format: one row per category per source (ICD-10 / ICD-O-3)
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

# Print column names for diagnostics -- the previous version used positional
# selection (columns 1,2,3) which failed when columns were in a different order.
cn <- names(groups_raw)
message(glue("  Groups sheet has {length(cn)} columns: {paste(cn, collapse = ' | ')}"))

# Identify columns by header name (case-insensitive)
cn_lower <- tolower(cn)

# Site column: named exactly "site" (not "primary disease site" or "detailed site")
site_idx <- which(cn_lower == "site")
if (length(site_idx) == 0) {
  # Fallback: column containing "site" but not "primary"/"detailed"/"disease"
  site_idx <- which(str_detect(cn_lower, "site") &
                    !str_detect(cn_lower, "primary|detailed|disease"))
}

# ICD-10 column: contains "icd" and "10" but not "o" between them
icd10_idx <- which(str_detect(cn_lower, "icd") &
                   str_detect(cn_lower, "10") &
                   !str_detect(cn_lower, "icdo|icd.?o"))
if (length(icd10_idx) == 0) {
  icd10_idx <- which(str_detect(cn_lower, "icd10|icd.10"))
}

# ICD-O-3 column: contains "icdo" or "icd-o" or similar
icdo3_idx <- which(str_detect(cn_lower, "icdo|icd.?o"))

message(glue("  Detected column indices: site={paste(site_idx, collapse=',')} icd10={paste(icd10_idx, collapse=',')} icdo3={paste(icdo3_idx, collapse=',')}"))

# If detection fails, dump rows for manual inspection and stop
if (length(site_idx) != 1 || length(icd10_idx) != 1 || length(icdo3_idx) != 1) {
  message("  Column detection failed. Dumping first 3 rows for inspection:")
  for (r in seq_len(min(3, nrow(groups_raw)))) {
    vals <- paste(sapply(seq_along(cn), function(c) {
      glue("[{c}] {cn[c]}='{groups_raw[[c]][r]}'")
    }), collapse = " | ")
    message(glue("    Row {r}: {vals}"))
  }
  stop("Cannot identify Site, ICD10, and ICDO3 columns. Check column names above.")
}

groups_df <- tibble(
  category = groups_raw[[site_idx]],
  icd10    = as.character(groups_raw[[icd10_idx]]),
  icdo3    = as.character(groups_raw[[icdo3_idx]])
)

# Verify 42 categories
stopifnot("Expected 42 categories in CancerSiteCategories.xlsx Groups sheet" = nrow(groups_df) == 42)
message(glue("Loaded {nrow(groups_df)} categories (expected 42) -- OK"))

# Check for NA categories (merged cell issue in xlsx)
n_na_cats <- sum(is.na(groups_df$category))
if (n_na_cats > 0) {
  message(glue("  WARNING: {n_na_cats} categories have NA names (merged cells in xlsx?)"))
}

n_icd10_nonna <- sum(!is.na(groups_df$icd10))
n_icdo3_nonna <- sum(!is.na(groups_df$icdo3))
message(glue("  Categories with non-NA ICD-10 codes: {n_icd10_nonna}"))
message(glue("  Categories with non-NA ICD-O-3 codes: {n_icdo3_nonna}"))

# Show first rows to verify column mapping is correct
message("  First 5 rows of groups_df:")
for (r in seq_len(min(5, nrow(groups_df)))) {
  icd10_preview <- substr(as.character(groups_df$icd10[r]), 1, 50)
  icdo3_preview <- substr(as.character(groups_df$icdo3[r]), 1, 50)
  message(glue("    [{r}] category='{groups_df$category[r]}' | icd10='{icd10_preview}' | icdo3='{icdo3_preview}'"))
}

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
  prefix_start <- str_extract(start, "^.*?(?=\\d+$)")
  suffix_start <- str_extract(start, "\\d+$")
  prefix_end   <- str_extract(end,   "^.*?(?=\\d+$)")
  suffix_end   <- str_extract(end,   "\\d+$")

  # If we can't extract numeric suffixes or prefixes differ, warn and return endpoints
  if (is.na(suffix_start) || is.na(suffix_end) || is.na(prefix_start) || is.na(prefix_end)) {
    warning(glue("expand_icd_token: cannot parse range '{token}' -- returning endpoints only"))
    return(normalize_icd(c(start, end)))
  }

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
# Skip categories where all expanded codes are in morphology range (8000-9999 pure digits)
icdo3_prefix_to_cat <- list()
skipped_morph_cats <- integer(0)

for (i in seq_len(nrow(groups_df))) {
  codes_i <- expand_code_string(groups_df$icdo3[i])

  if (length(codes_i) == 0) next

  is_pure_numeric <- !str_detect(codes_i, "^[A-Z]")
  numeric_vals <- suppressWarnings(as.integer(codes_i))
  is_morphology <- is_pure_numeric & !is.na(numeric_vals) & numeric_vals >= 8000

  if (all(is_morphology)) {
    skipped_morph_cats <- c(skipped_morph_cats, i)
    next
  }

  new_codes <- setdiff(codes_i, names(icdo3_prefix_to_cat))
  for (c in new_codes) icdo3_prefix_to_cat[[c]] <- i
}

message(glue("Built ICD-10 prefix lookup: {length(icd10_prefix_to_cat)} unique prefixes"))
message(glue("Built ICD-O-3 prefix lookup: {length(icdo3_prefix_to_cat)} unique prefixes (skipped {length(skipped_morph_cats)} morphology-only categories)"))

message(glue("  ICD-10 prefixes (first 10): {paste(head(names(icd10_prefix_to_cat), 10), collapse = ', ')}"))
message(glue("  ICD-O-3 prefixes (first 10): {paste(head(names(icdo3_prefix_to_cat), 10), collapse = ', ')}"))

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
message(glue("  DX_norm sample (first 10 unique): {paste(head(unique(diagnosis_icd10$DX_norm), 10), collapse = ', ')}"))

# --- ICD-O-3 from TUMOR_REGISTRY_ALL ---

message("Loading TUMOR_REGISTRY_ALL table (topography codes, all patients)...")

tr_all_lazy <- get_pcornet_table("TUMOR_REGISTRY_ALL")
tr_cols <- colnames(tr_all_lazy)
site_candidates <- intersect(c("SITE_CODE", "SITE", "PRIMARY_SITE"), tr_cols)
message(glue("  Topography column candidates found: {paste(site_candidates, collapse = ', ')}"))

if (length(site_candidates) == 0) {
  warning("No topography/site column found in TUMOR_REGISTRY_ALL -- ICD-O-3 counts will be 0")
  tr_topo <- tibble(ID = character(), topo_raw = character(), topo_norm = character())
} else {
  coalesce_expr <- rlang::parse_expr(paste0("coalesce(", paste(site_candidates, collapse = ", "), ")"))
  tr_topo <- tr_all_lazy %>%
    mutate(topo_raw = !!coalesce_expr) %>%
    select(ID, topo_raw) %>%
    filter(!is.na(topo_raw)) %>%
    materialize() %>%
    mutate(topo_norm = normalize_icd(topo_raw))
}

message(glue("Loaded {format(nrow(tr_topo), big.mark = ',')} TUMOR_REGISTRY rows with topography codes"))
message(glue("  Topography sample (first 10 unique): {paste(head(unique(tr_topo$topo_norm), 10), collapse = ', ')}"))

# --- Matching per category ---

message("Computing per-category counts (42 categories x ICD-10 and ICD-O-3)...")

icd10_codes_by_cat <- lapply(seq_len(nrow(groups_df)), function(i) {
  expand_code_string(groups_df$icd10[i])
})
icdo3_codes_by_cat <- lapply(seq_len(nrow(groups_df)), function(i) {
  expand_code_string(groups_df$icdo3[i])
})

# Collectors for overall totals (true n_distinct)
all_matched_ids_icd10 <- character(0)
all_matched_ids_icdo3 <- character(0)

# Per-category result vectors
cat_icd10_patients   <- integer(42)
cat_icd10_records    <- integer(42)
cat_icdo3_patients   <- integer(42)
cat_icdo3_records    <- integer(42)

for (i in seq_len(nrow(groups_df))) {

  # ICD-10 matching
  icd10_codes_i <- icd10_codes_by_cat[[i]]

  if (i <= 3) {
    message(glue("  cat[{i}] '{groups_df$category[i]}': icd10_codes={paste(head(icd10_codes_i, 5), collapse=',')} icdo3_codes={paste(head(icdo3_codes_by_cat[[i]], 5), collapse=',')}"))
  }

  if (length(icd10_codes_i) > 0) {
    dx_matches <- diagnosis_icd10 %>%
      filter(map_lgl(DX_norm, function(dx) any(startsWith(dx, icd10_codes_i))))
    cat_icd10_patients[i] <- n_distinct(dx_matches$ID)
    cat_icd10_records[i]  <- nrow(dx_matches)
    all_matched_ids_icd10 <- c(all_matched_ids_icd10, dx_matches$ID)
  }

  # ICD-O-3 matching (topography only, skip morphology codes)
  icdo3_codes_i <- icdo3_codes_by_cat[[i]]

  if (length(icdo3_codes_i) > 0) {
    is_pure_numeric <- !str_detect(icdo3_codes_i, "^[A-Z]")
    numeric_vals <- suppressWarnings(as.integer(icdo3_codes_i))
    is_morphology <- is_pure_numeric & !is.na(numeric_vals) & numeric_vals >= 8000
    if (all(is_morphology)) {
      icdo3_codes_i <- character(0)
    }
  }

  if (length(icdo3_codes_i) > 0) {
    tr_matches <- tr_topo %>%
      filter(map_lgl(topo_norm, function(t) any(startsWith(t, icdo3_codes_i))))
    cat_icdo3_patients[i] <- n_distinct(tr_matches$ID)
    cat_icdo3_records[i]  <- nrow(tr_matches)
    all_matched_ids_icdo3 <- c(all_matched_ids_icdo3, tr_matches$ID)
  }

  if (i %% 10 == 0) message(glue("  Processed {i}/42 categories..."))
}

message("All 42 categories processed.")

# ==============================================================================
# Build long-format result: one row per category per source
# ==============================================================================

result_long <- bind_rows(
  tibble(
    category = groups_df$category,
    source   = "ICD-10",
    patients = cat_icd10_patients,
    records  = cat_icd10_records
  ),
  tibble(
    category = groups_df$category,
    source   = "ICD-O-3",
    patients = cat_icdo3_patients,
    records  = cat_icdo3_records
  )
)

# Sort: keep categories in spreadsheet order, ICD-10 before ICD-O-3 within each
cat_order <- seq_len(nrow(groups_df))
result_long <- result_long %>%
  mutate(cat_idx = rep(cat_order, 2)) %>%
  arrange(cat_idx, source) %>%
  select(-cat_idx)

# Totals rows
total_icd10_patients <- n_distinct(all_matched_ids_icd10)
total_icdo3_patients <- n_distinct(all_matched_ids_icdo3)

totals_long <- tibble(
  category = c("TOTAL", "TOTAL"),
  source   = c("ICD-10", "ICD-O-3"),
  patients = c(total_icd10_patients, total_icdo3_patients),
  records  = c(sum(cat_icd10_records), sum(cat_icdo3_records))
)

message("")
message("=== COUNT SUMMARY ===")
message(glue("ICD-10: {format(total_icd10_patients, big.mark=',')} unique patients, {format(sum(cat_icd10_records), big.mark=',')} records"))
message(glue("ICD-O-3: {format(total_icdo3_patients, big.mark=',')} unique patients, {format(sum(cat_icdo3_records), big.mark=',')} records"))

# Spot-check: Hodgkin Lymphoma
hl_rows <- result_long %>% filter(category == "Hodgkin Lymphoma")
if (nrow(hl_rows) > 0) {
  for (r in seq_len(nrow(hl_rows))) {
    message(glue("  Hodgkin Lymphoma ({hl_rows$source[r]}): {format(hl_rows$patients[r], big.mark=',')} patients, {format(hl_rows$records[r], big.mark=',')} records"))
  }
}

# ==============================================================================
# SECTION 6: WRITE STYLED XLSX (long format)
# ==============================================================================

message("")
message(glue("Writing styled xlsx to {OUTPUT_PATH}..."))

DARK_HEADER_FILL <- "FF374151"
WHITE_FONT       <- "FFFFFFFF"
TITLE_FONT_COLOR <- "FF1F2937"
TOTALS_FILL      <- "FFE5E7EB"

n_cols <- 4L
n_data_rows <- nrow(result_long)  # 84 rows (42 categories x 2 sources)

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
headers <- c("Cancer Site Category", "Source", "Patients", "Records")

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
# Freeze pane at row 3
# ---------------------------------------------------------------------------
wb$freeze_pane(sheet = SHEET1, first_active_row = 3, first_active_col = 1)

# ---------------------------------------------------------------------------
# Data rows (84 rows: 42 categories x 2 sources)
# ---------------------------------------------------------------------------
data_start_row <- 3
data_end_row   <- data_start_row + n_data_rows - 1

write_data <- result_long %>% as.data.frame()
wb$add_data(sheet = SHEET1, x = write_data, start_row = data_start_row, col_names = FALSE)

# Number format for count columns C:D
wb$add_numfmt(sheet = SHEET1,
              dims  = glue("C{data_start_row}:{int2col(n_cols)}{data_end_row}"),
              numfmt = "#,##0")

# ---------------------------------------------------------------------------
# Totals rows (2 rows: ICD-10 total + ICD-O-3 total)
# ---------------------------------------------------------------------------
totals_start_row <- data_end_row + 1
totals_end_row   <- totals_start_row + nrow(totals_long) - 1

totals_data <- totals_long %>% as.data.frame()
wb$add_data(sheet = SHEET1, x = totals_data, start_row = totals_start_row, col_names = FALSE)

wb$add_fill(sheet = SHEET1,
            dims  = glue("A{totals_start_row}:{int2col(n_cols)}{totals_end_row}"),
            color = wb_color(TOTALS_FILL))
wb$add_font(sheet = SHEET1,
            dims  = glue("A{totals_start_row}:{int2col(n_cols)}{totals_end_row}"),
            name  = "Calibri", size = 11, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$add_numfmt(sheet = SHEET1,
              dims  = glue("C{totals_start_row}:{int2col(n_cols)}{totals_end_row}"),
              numfmt = "#,##0")

# ---------------------------------------------------------------------------
# Column widths
# ---------------------------------------------------------------------------
wb$set_col_widths(sheet = SHEET1,
                  cols   = 1:n_cols,
                  widths = c(40, 12, 14, 14))

# ---------------------------------------------------------------------------
# Save workbook
# ---------------------------------------------------------------------------
wb$save(OUTPUT_PATH)
message(glue("Wrote {OUTPUT_PATH}"))
message(glue("  Sheet '{SHEET1}': {n_data_rows} data rows + {nrow(totals_long)} total rows"))
message(glue("  Columns: {paste(headers, collapse = ' | ')}"))

message("")
message("=== Phase 47 Cancer Site Frequency Complete ===")
