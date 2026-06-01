# =============================================================================
# Phase 24: Treatment Codes Resolved XLSX (All Types)
# =============================================================================
# Creates per-treatment-type resolved xlsx files (Radiation, SCT, Immunotherapy,
# Supportive Care) from combined_unmatched_report.xlsx, mirroring the
# chemotherapy_codes_resolved.xlsx format. Also verifies chemotherapy_codes_resolved.xlsx
# accuracy against the combined report.
#
# Input:  output/combined_unmatched_report.xlsx  (Phase 41 output)
#         chemotherapy_codes_resolved.xlsx       (verification target)
# Output: radiation_codes_resolved.xlsx
#         sct_codes_resolved.xlsx
#         immunotherapy_codes_resolved.xlsx
#         supportive_care_codes_resolved.xlsx
# =============================================================================

# --- SECTION 1: SETUP AND CONFIGURATION ---

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(openxlsx2)
})

source("R/00_config.R")

# Paths to source files
COMBINED_REPORT <- file.path(CONFIG$output_dir, "combined_unmatched_report.xlsx")
CHEMO_RESOLVED  <- "chemotherapy_codes_resolved.xlsx"

# Categories to produce resolved files for (non-chemo)
RESOLVE_CATEGORIES <- list(
  list(category = "Radiation",       sheet = "Radiation",       output = "radiation_codes_resolved.xlsx"),
  list(category = "SCT",             sheet = "SCT",             output = "sct_codes_resolved.xlsx"),
  list(category = "Immunotherapy",   sheet = "Immunotherapy",   output = "immunotherapy_codes_resolved.xlsx"),
  list(category = "Supportive Care", sheet = "Supportive Care", output = "supportive_care_codes_resolved.xlsx")
)

# TREATMENT_TYPE_COLORS: defined in R/00_config.R
# Color scheme per treatment type


# --- SECTION 2: write_resolved_xlsx() FUNCTION ---

write_resolved_xlsx <- function(df, category, output_path) {
  #' Write a resolved treatment codes xlsx file for a single category.
  #'
  #' Creates a 2-sheet workbook:
  #'   Sheet 1: "{Category} Codes" -- title row, headers, styled data
  #'   Sheet 2: "Notes" -- provenance documentation
  #'

  #' @param df Data frame from combined report (columns: code, description,
  #'   code_type, source_table, records, patients)
  #' @param category Character string: treatment category name
  #' @param output_path Character string: output xlsx file path

  n_codes <- nrow(df)
  sheet_name <- paste(category, "Codes")

  fill_color <- TREATMENT_TYPE_COLORS[[category]]$fill
  font_color <- TREATMENT_TYPE_COLORS[[category]]$font

  wb <- wb_workbook()
  wb$add_worksheet(sheet_name)

  # Row 1: Title with code count
  wb$add_data(sheet = sheet_name,
              x = glue("{category} Codes ({n_codes} codes)"),
              start_row = 1, start_col = 1)
  wb$add_font(sheet = sheet_name, dims = "A1",
              name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
  wb$merge_cells(sheet = sheet_name, dims = "A1:F1")

  # Row 2: Column headers
  headers <- c("Code", "Meaning", "Code Type", "Source Table", "Records", "Patients")
  for (i in seq_along(headers)) {
    wb$add_data(sheet = sheet_name, x = headers[i],
                start_row = 2, start_col = i)
  }
  wb$add_fill(sheet = sheet_name, dims = "A2:F2", color = wb_color("FF374151"))
  wb$add_font(sheet = sheet_name, dims = "A2:F2",
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

  # Row 3+: Bulk data write
  write_df <- data.frame(
    Code         = df$code,
    Meaning      = ifelse(is.na(df$description), "", df$description),
    Code_Type    = df$code_type,
    Source_Table = df$source_table,
    Records      = df$records,
    Patients     = df$patients,
    stringsAsFactors = FALSE
  )
  wb$add_data(sheet = sheet_name, x = write_df, start_row = 3, col_names = FALSE)

  # Styling: Code column (A3:A{last_row}) -- category fill + bold font
  last_row <- 2 + n_codes
  code_dims <- glue("A3:A{last_row}")
  wb$add_fill(sheet = sheet_name, dims = code_dims, color = wb_color(fill_color))
  wb$add_font(sheet = sheet_name, dims = code_dims,
              name = "Calibri", size = 10, bold = TRUE, color = wb_color(font_color))

  # Number formatting: columns E-F (Records, Patients)
  num_dims <- glue("E3:F{last_row}")
  wb$add_numfmt(sheet = sheet_name, dims = num_dims, numfmt = "#,##0")

  # Column widths
  wb$set_col_widths(sheet = sheet_name, cols = 1:6, widths = c(15, 45, 12, 15, 10, 10))

  # Notes sheet
  wb$add_worksheet("Notes")
  notes_lines <- c(
    glue("Data Source: combined_unmatched_report.xlsx (Phase 41)"),
    glue("Descriptions: NLM/RxNorm API lookups via Phase 39-40"),
    glue("Generated: {Sys.Date()}"),
    glue("Classification: {category} codes")
  )
  for (i in seq_along(notes_lines)) {
    wb$add_data(sheet = "Notes", x = as.character(notes_lines[i]),
                start_row = i, start_col = 1)
  }

  # Save workbook
  wb$save(output_path)
  message(glue("  Wrote {output_path} ({n_codes} codes)"))
}


# --- SECTION 3: verify_chemotherapy() FUNCTION ---

verify_chemotherapy <- function() {
  #' Verify chemotherapy_codes_resolved.xlsx against combined report.
  #'
  #' Performs three checks per D-07/D-08/D-09:
  #'   1. Row count match (203 expected)
  #'   2. Code set match (setdiff in both directions)
  #'   3. Records/Patients count comparison
  #'
  #' @return List with pass (logical), n_source, n_resolved, mismatches (df or NULL)

  all_pass <- TRUE

  # Read Chemotherapy sheet from combined report (headers at row 4)
  chemo_source <- read_xlsx(COMBINED_REPORT, sheet = "Chemotherapy", start_row = 4)
  names(chemo_source) <- tolower(gsub(" ", "_", names(chemo_source)))
  message(glue("  Source (combined report): {nrow(chemo_source)} chemotherapy codes"))

  # Read chemotherapy resolved file -- detect sheet name dynamically

  chemo_wb <- wb_load(CHEMO_RESOLVED)
  available_sheets <- chemo_wb$sheet_names
  message(glue("  Resolved file sheets: {paste(available_sheets, collapse = ', ')}"))

  # Use first non-"Notes" sheet as data sheet
  data_sheet <- available_sheets[available_sheets != "Notes"][1]
  message(glue("  Reading data sheet: '{data_sheet}'"))

  # Title row is row 1, headers at row 2, data starts row 3
  # Use start_row = 2 to skip title and read headers from row 2
  chemo_resolved <- wb_to_df(chemo_wb, sheet = data_sheet, start_row = 2, col_names = TRUE)
  message(glue("  Resolved file: {nrow(chemo_resolved)} chemotherapy codes"))

  # Check 1: Row count match (D-07)
  message("\n  Check 1: Row count match")
  if (nrow(chemo_source) == nrow(chemo_resolved)) {
    message(glue("  PASS: Both have {nrow(chemo_source)} codes"))
  } else {
    message(glue("  FAIL: Source has {nrow(chemo_source)}, resolved has {nrow(chemo_resolved)}"))
    all_pass <- FALSE
  }

  # Check 2: Code set match (D-07)
  message("\n  Check 2: Code set match")
  source_codes <- sort(as.character(chemo_source$code))

  # Detect code column name in resolved file (may be "Code" or lowercase)
  resolved_col_names <- tolower(names(chemo_resolved))
  code_col_idx <- which(resolved_col_names == "code")[1]
  if (is.na(code_col_idx)) {
    message("  FAIL: Cannot find 'Code' column in resolved file")
    message(glue("  Available columns: {paste(names(chemo_resolved), collapse = ', ')}"))
    all_pass <- FALSE
    return(list(pass = FALSE, n_source = nrow(chemo_source),
                n_resolved = nrow(chemo_resolved), mismatches = NULL))
  }
  resolved_codes <- sort(as.character(chemo_resolved[[code_col_idx]]))

  missing_in_resolved <- setdiff(source_codes, resolved_codes)
  extra_in_resolved <- setdiff(resolved_codes, source_codes)

  if (length(missing_in_resolved) > 0) {
    message(glue("  FAIL: {length(missing_in_resolved)} codes in source but not in resolved"))
    message(glue("  Missing: {paste(head(missing_in_resolved, 10), collapse = ', ')}"))
    all_pass <- FALSE
  }
  if (length(extra_in_resolved) > 0) {
    message(glue("  FAIL: {length(extra_in_resolved)} codes in resolved but not in source"))
    message(glue("  Extra: {paste(head(extra_in_resolved, 10), collapse = ', ')}"))
    all_pass <- FALSE
  }
  if (length(missing_in_resolved) == 0 && length(extra_in_resolved) == 0) {
    message("  PASS: Code sets match exactly")
  }

  # Check 3: Records/Patients count comparison (D-08)
  message("\n  Check 3: Records/Patients count comparison")

  # Map resolved column names to expected names (handle case differences)
  resolved_names <- names(chemo_resolved)
  records_col <- which(tolower(resolved_names) == "records")[1]
  patients_col <- which(tolower(resolved_names) == "patients")[1]

  mismatches_df <- NULL

  if (is.na(records_col) || is.na(patients_col)) {
    message("  WARN: Cannot find Records/Patients columns in resolved file")
    message(glue("  Available columns: {paste(resolved_names, collapse = ', ')}"))
    # Still try to continue -- not a hard failure for overall verification
  } else {
    # Build comparison data frame
    source_compare <- chemo_source %>%
      select(code, n_records_source = records, n_patients_source = patients)

    resolved_compare <- data.frame(
      code = as.character(chemo_resolved[[code_col_idx]]),
      n_records_resolved = as.numeric(chemo_resolved[[records_col]]),
      n_patients_resolved = as.numeric(chemo_resolved[[patients_col]]),
      stringsAsFactors = FALSE
    )

    verification <- source_compare %>%
      inner_join(resolved_compare, by = "code") %>%
      mutate(
        records_match = n_records_source == n_records_resolved,
        patients_match = n_patients_source == n_patients_resolved
      )

    mismatches_df <- verification %>%
      filter(!records_match | !patients_match)

    if (nrow(mismatches_df) > 0) {
      message(glue("  FAIL: {nrow(mismatches_df)} codes have count mismatches"))
      message("  First 10 mismatches:")
      print(head(mismatches_df, 10))
      all_pass <- FALSE
    } else {
      message("  PASS: All Records/Patients counts match")
    }
  }

  return(list(
    pass = all_pass,
    n_source = nrow(chemo_source),
    n_resolved = nrow(chemo_resolved),
    mismatches = mismatches_df
  ))
}


# --- SECTION 4: MAIN EXECUTION ---

message("=== Phase 42: Treatment Codes Resolved XLSX (All Types) ===\n")

# Step 0: Verify source file exists
stopifnot(file.exists(COMBINED_REPORT))

# Discover available sheets in combined report
combined_wb <- wb_load(COMBINED_REPORT)
available_sheets <- combined_wb$sheet_names
message(glue("Combined report sheets: {paste(available_sheets, collapse = ', ')}\n"))

# Step 1: Generate resolved xlsx for each non-chemo category
message("Step 1: Generating per-type resolved xlsx files...\n")
for (item in RESOLVE_CATEGORIES) {
  # Check if sheet exists in combined report
  if (!(item$sheet %in% available_sheets)) {
    message(glue("  WARNING: Sheet '{item$sheet}' not found in combined report, skipping {item$category}"))
    message("")
    next
  }

  message(glue("  Reading {item$sheet} sheet from combined report..."))
  # Headers at row 4, data from row 5 (rows 1-3 are title/subtitle/blank)
  df <- read_xlsx(COMBINED_REPORT, sheet = item$sheet, start_row = 4)
  # Normalize column names: "Code Type" -> "code_type", "Records" -> "records", etc.
  names(df) <- tolower(gsub(" ", "_", names(df)))
  message(glue("  Found {nrow(df)} {item$category} codes"))

  if (nrow(df) == 0) {
    message(glue("  WARNING: No codes found for {item$category}, skipping"))
    message("")
    next
  }

  # Sort by patients descending (most clinically relevant first)
  df <- df %>% arrange(desc(patients))

  write_resolved_xlsx(df, item$category, item$output)
  message("")
}

# Step 2: Verify chemotherapy file
message("Step 2: Verifying chemotherapy_codes_resolved.xlsx...\n")
if (file.exists(CHEMO_RESOLVED)) {
  result <- verify_chemotherapy()
  if (result$pass) {
    message("\nChemotherapy verification: ALL CHECKS PASSED")
  } else {
    message("\nChemotherapy verification: ISSUES FOUND (see above)")
  }
} else {
  message(glue("  WARNING: {CHEMO_RESOLVED} not found, skipping verification"))
}

message("\n=== Phase 42 Complete ===")
