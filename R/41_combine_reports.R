# =============================================================================
# Phase 41: Combine Unmatched Code Reports
# =============================================================================
# Merges Phase 39 (CPT/HCPCS) and Phase 40 (NDC/RXNORM) unmatched code
# investigation RDS artifacts into a single consolidated xlsx report with
# unified classification, cross-source summary statistics, and per-category
# detail sheets.
#
# Input:  output/unmatched_codes_classified.rds   (Phase 39)
#         output/unmatched_ndc_classified.rds     (Phase 40)
# Output: output/combined_unmatched_report.xlsx
# =============================================================================

# --- SECTION 1: SETUP AND CONFIGURATION ---

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(openxlsx2)
  library(stringr)
})

source("R/00_config.R")

OUTPUT_PATH <- file.path(CONFIG$output_dir, "combined_unmatched_report.xlsx")
HCPCS_RDS  <- file.path(CONFIG$output_dir, "unmatched_codes_classified.rds")
NDC_RDS    <- file.path(CONFIG$output_dir, "unmatched_ndc_classified.rds")

# TREATMENT_TYPE_COLORS: defined in R/00_config.R
# Unified color scheme uses "SCT" (not "SCT-related")

category_order <- c("Chemotherapy", "Radiation", "SCT", "Immunotherapy",
                    "Supportive Care", "Unrelated")


# --- SECTION 2: LOAD AND HARMONIZE RDS ARTIFACTS ---

load_and_harmonize <- function() {
  # Guard: check both RDS files exist

if (!file.exists(HCPCS_RDS)) {
    stop(glue("Phase 39 RDS not found: {HCPCS_RDS}\n",
              "Run R/39_investigate_unmatched.R first to generate it."))
  }
  if (!file.exists(NDC_RDS)) {
    stop(glue("Phase 40 RDS not found: {NDC_RDS}\n",
              "Run R/40_investigate_unmatched_ndc.R first to generate it."))
  }

  # Load RDS artifacts
  hcpcs_classified <- readRDS(HCPCS_RDS)
  ndc_classified   <- readRDS(NDC_RDS)

  message(glue("  Loaded Phase 39 (CPT/HCPCS): {nrow(hcpcs_classified)} codes"))
  message(glue("  Loaded Phase 40 (NDC/RXNORM): {nrow(ndc_classified)} codes"))

  # Harmonize Phase 39 to unified schema
  hcpcs_harmonized <- hcpcs_classified %>%
    mutate(
      code_type = "CPT/HCPCS",
      source_table = "PROCEDURES"
    ) %>%
    select(code, code_type, source_table, description, n_records, n_patients,
           classification, heuristic_type, lookup_status)

  # Harmonize Phase 40 to unified schema
  # Note: "SCT-related" -> "SCT" remap no longer needed (fixed in script 40)
  # Defensive fallback retained in case old RDS artifacts are reused:
  ndc_harmonized <- ndc_classified %>%
    mutate(
      description = drug_name,
      heuristic_type = NA_character_,
      classification = if_else(classification == "SCT-related", "SCT", classification)
    ) %>%
    select(code, code_type, source_table, description, n_records, n_patients,
           classification, heuristic_type, lookup_status)

  # Combine
  all_codes <- bind_rows(hcpcs_harmonized, ndc_harmonized)

  # Log summary
  message(glue("\n  Combined total: {nrow(all_codes)} codes"))
  message("  By code type:")
  code_type_counts <- all_codes %>% count(code_type)
  for (i in seq_len(nrow(code_type_counts))) {
    message(glue("    {code_type_counts$code_type[i]}: {code_type_counts$n[i]}"))
  }
  message("  By classification:")
  class_counts <- all_codes %>%
    count(classification) %>%
    arrange(match(classification, category_order))
  for (i in seq_len(nrow(class_counts))) {
    message(glue("    {class_counts$classification[i]}: {class_counts$n[i]}"))
  }

  return(all_codes)
}


# --- SECTION 3: WRITE COMBINED XLSX REPORT ---

write_combined_report <- function(df, output_path) {
  message("\n  Writing combined xlsx report...")

  wb <- wb_workbook()

  # --- SUMMARY SHEET ---
  message("  Writing Summary sheet...")
  wb$add_worksheet("Summary")

  # Row 1: Title
  wb$add_data(sheet = "Summary", x = "Combined Unmatched Code Investigation",
              start_row = 1, start_col = 1)
  wb$add_font(sheet = "Summary", dims = "A1",
              name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
  wb$merge_cells(sheet = "Summary", dims = "A1:D1")

  # Row 2: Subtitle
  wb$add_data(sheet = "Summary",
              x = "Phase 39 (CPT/HCPCS) + Phase 40 (NDC/RXNORM) — consolidated view",
              start_row = 2, start_col = 1)
  wb$add_font(sheet = "Summary", dims = "A2",
              name = "Calibri", size = 10, color = wb_color("FF6B7280"))
  wb$merge_cells(sheet = "Summary", dims = "A2:D2")

  # Row 3: Date
  wb$add_data(sheet = "Summary", x = as.character(Sys.Date()),
              start_row = 3, start_col = 1)
  wb$add_font(sheet = "Summary", dims = "A3",
              name = "Calibri", size = 10, color = wb_color("FF6B7280"))

  # Row 5: "By Classification" section header
  wb$add_data(sheet = "Summary", x = "By Classification:",
              start_row = 5, start_col = 1)
  wb$add_font(sheet = "Summary", dims = "A5",
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FF1F2937"))

  # Row 6: Headers
  headers <- c("Classification", "Codes", "Records", "Patients")
  for (i in seq_along(headers)) {
    wb$add_data(sheet = "Summary", x = headers[i],
                start_row = 6, start_col = i)
  }
  wb$add_fill(sheet = "Summary", dims = "A6:D6", color = wb_color("FF374151"))
  wb$add_font(sheet = "Summary", dims = "A6:D6",
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

  # Classification summary data
  summary_df <- df %>%
    group_by(classification) %>%
    summarise(
      n_codes = n_distinct(code),
      n_records = sum(n_records),
      n_patients = sum(n_patients),
      .groups = "drop"
    ) %>%
    arrange(match(classification, category_order))

  for (i in seq_len(nrow(summary_df))) {
    row_num <- 6 + i
    wb$add_data(sheet = "Summary", x = summary_df$classification[i],
                start_row = row_num, start_col = 1)
    wb$add_data(sheet = "Summary", x = summary_df$n_codes[i],
                start_row = row_num, start_col = 2)
    wb$add_data(sheet = "Summary", x = summary_df$n_records[i],
                start_row = row_num, start_col = 3)
    wb$add_data(sheet = "Summary", x = summary_df$n_patients[i],
                start_row = row_num, start_col = 4)
    wb$add_numfmt(sheet = "Summary", dims = glue("B{row_num}:D{row_num}"), numfmt = "#,##0")
  }

  # Total row
  total_row <- 6 + nrow(summary_df) + 1
  wb$add_data(sheet = "Summary", x = "Total",
              start_row = total_row, start_col = 1)
  wb$add_data(sheet = "Summary", x = sum(summary_df$n_codes),
              start_row = total_row, start_col = 2)
  wb$add_data(sheet = "Summary", x = sum(summary_df$n_records),
              start_row = total_row, start_col = 3)
  wb$add_data(sheet = "Summary", x = sum(summary_df$n_patients),
              start_row = total_row, start_col = 4)
  wb$add_fill(sheet = "Summary", dims = glue("A{total_row}:D{total_row}"),
              color = wb_color("FF374151"))
  wb$add_font(sheet = "Summary", dims = glue("A{total_row}:D{total_row}"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
  wb$add_numfmt(sheet = "Summary", dims = glue("B{total_row}:D{total_row}"), numfmt = "#,##0")

  # "By Code Type" section
  code_type_row <- total_row + 2
  wb$add_data(sheet = "Summary", x = "By Code Type:",
              start_row = code_type_row, start_col = 1)
  wb$add_font(sheet = "Summary", dims = glue("A{code_type_row}"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FF1F2937"))

  # Code type headers
  ct_header_row <- code_type_row + 1
  ct_headers <- c("Code Type", "Codes", "Records", "Patients")
  for (i in seq_along(ct_headers)) {
    wb$add_data(sheet = "Summary", x = ct_headers[i],
                start_row = ct_header_row, start_col = i)
  }
  wb$add_fill(sheet = "Summary", dims = glue("A{ct_header_row}:D{ct_header_row}"),
              color = wb_color("FF374151"))
  wb$add_font(sheet = "Summary", dims = glue("A{ct_header_row}:D{ct_header_row}"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

  code_type_summary <- df %>%
    group_by(code_type) %>%
    summarise(
      n_codes = n_distinct(code),
      n_records = sum(n_records),
      n_patients = sum(n_patients),
      .groups = "drop"
    )

  for (i in seq_len(nrow(code_type_summary))) {
    row_num <- ct_header_row + i
    wb$add_data(sheet = "Summary", x = code_type_summary$code_type[i],
                start_row = row_num, start_col = 1)
    wb$add_data(sheet = "Summary", x = code_type_summary$n_codes[i],
                start_row = row_num, start_col = 2)
    wb$add_data(sheet = "Summary", x = code_type_summary$n_records[i],
                start_row = row_num, start_col = 3)
    wb$add_data(sheet = "Summary", x = code_type_summary$n_patients[i],
                start_row = row_num, start_col = 4)
    wb$add_numfmt(sheet = "Summary", dims = glue("B{row_num}:D{row_num}"), numfmt = "#,##0")
  }

  # "By Source Table" section
  source_row <- ct_header_row + nrow(code_type_summary) + 2
  wb$add_data(sheet = "Summary", x = "By Source Table:",
              start_row = source_row, start_col = 1)
  wb$add_font(sheet = "Summary", dims = glue("A{source_row}"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FF1F2937"))

  # Source table headers
  st_header_row <- source_row + 1
  st_headers <- c("Source Table", "Codes", "Records", "Patients")
  for (i in seq_along(st_headers)) {
    wb$add_data(sheet = "Summary", x = st_headers[i],
                start_row = st_header_row, start_col = i)
  }
  wb$add_fill(sheet = "Summary", dims = glue("A{st_header_row}:D{st_header_row}"),
              color = wb_color("FF374151"))
  wb$add_font(sheet = "Summary", dims = glue("A{st_header_row}:D{st_header_row}"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

  source_summary <- df %>%
    group_by(source_table) %>%
    summarise(
      n_codes = n_distinct(code),
      n_records = sum(n_records),
      n_patients = sum(n_patients),
      .groups = "drop"
    )

  for (i in seq_len(nrow(source_summary))) {
    row_num <- st_header_row + i
    wb$add_data(sheet = "Summary", x = source_summary$source_table[i],
                start_row = row_num, start_col = 1)
    wb$add_data(sheet = "Summary", x = source_summary$n_codes[i],
                start_row = row_num, start_col = 2)
    wb$add_data(sheet = "Summary", x = source_summary$n_records[i],
                start_row = row_num, start_col = 3)
    wb$add_data(sheet = "Summary", x = source_summary$n_patients[i],
                start_row = row_num, start_col = 4)
    wb$add_numfmt(sheet = "Summary", dims = glue("B{row_num}:D{row_num}"), numfmt = "#,##0")
  }

  # Summary column widths
  wb$set_col_widths(sheet = "Summary", cols = 1:4, widths = c(22, 12, 12, 12))

  # --- PER-CATEGORY SHEETS ---
  for (category in category_order) {
    df_cat <- df %>%
      filter(classification == category) %>%
      arrange(desc(n_patients))

    if (nrow(df_cat) == 0) {
      next  # Skip empty categories
    }

    n_types <- n_distinct(df_cat$code_type)
    message(glue("  Writing {category} sheet ({nrow(df_cat)} codes)..."))

    sheet_name <- category
    wb$add_worksheet(sheet_name)

    fill_color <- TREATMENT_TYPE_COLORS[[category]]$fill
    font_color <- TREATMENT_TYPE_COLORS[[category]]$font

    # Row 1: Title
    wb$add_data(sheet = sheet_name, x = "Combined Unmatched Code Investigation",
                start_row = 1, start_col = 1)
    wb$add_font(sheet = sheet_name, dims = "A1",
                name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
    wb$merge_cells(sheet = sheet_name, dims = "A1:G1")

    # Row 2: Subtitle
    subtitle <- glue("{category}: {nrow(df_cat)} codes from {n_types} code types")
    wb$add_data(sheet = sheet_name, x = as.character(subtitle),
                start_row = 2, start_col = 1)
    wb$add_font(sheet = sheet_name, dims = "A2",
                name = "Calibri", size = 10, color = wb_color("FF6B7280"))
    wb$merge_cells(sheet = sheet_name, dims = "A2:G2")

    # Row 3: blank

    # Row 4: Column headers
    headers <- c("Code", "Description", "Code Type", "Source Table",
                 "Records", "Patients", "Lookup Status")
    for (i in seq_along(headers)) {
      wb$add_data(sheet = sheet_name, x = headers[i],
                  start_row = 4, start_col = i)
    }
    wb$add_fill(sheet = sheet_name, dims = "A4:G4", color = wb_color("FF374151"))
    wb$add_font(sheet = sheet_name, dims = "A4:G4",
                name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

    # Bulk data write (not cell-by-cell)
    write_df <- data.frame(
      Code = df_cat$code,
      Description = ifelse(is.na(df_cat$description), "", df_cat$description),
      Code_Type = df_cat$code_type,
      Source_Table = df_cat$source_table,
      Records = df_cat$n_records,
      Patients = df_cat$n_patients,
      Lookup_Status = df_cat$lookup_status,
      stringsAsFactors = FALSE
    )
    wb$add_data(sheet = sheet_name, x = write_df, start_row = 5, col_names = FALSE)

    # Range-based styling (O(categories) not O(n*cols))
    last_row <- 4 + nrow(df_cat)
    code_dims <- glue("A5:A{last_row}")
    text_dims <- glue("B5:G{last_row}")
    num_dims  <- glue("E5:F{last_row}")

    # Code column: colored pill
    wb$add_fill(sheet = sheet_name, dims = code_dims, color = wb_color(fill_color))
    wb$add_font(sheet = sheet_name, dims = code_dims,
                name = "Calibri", size = 10, bold = TRUE, color = wb_color(font_color))

    # Text columns: standard font
    wb$add_font(sheet = sheet_name, dims = text_dims,
                name = "Calibri", size = 10, color = wb_color("FF111827"))

    # Numeric columns: comma formatting
    wb$add_numfmt(sheet = sheet_name, dims = num_dims, numfmt = "#,##0")

    # Freeze panes at row 5 (first data row)
    wb$freeze_pane(sheet = sheet_name, first_active_row = 5)

    # Column widths
    wb$set_col_widths(sheet = sheet_name, cols = 1:7,
                      widths = c(15, 45, 12, 15, 10, 10, 15))
  }

  # Save workbook
  wb$save(output_path)
  message(glue("\n  Saved report: {output_path}"))
}


# --- SECTION 4: MAIN EXECUTION ---

message("=== Phase 41: Combine Unmatched Code Reports ===\n")

message("Step 1: Loading and harmonizing RDS artifacts...")
all_codes <- load_and_harmonize()

message("\nStep 2: Writing combined xlsx report...")
write_combined_report(all_codes, OUTPUT_PATH)

message("\n=== Phase 41 Complete ===")
message(glue("Output: {OUTPUT_PATH}"))
