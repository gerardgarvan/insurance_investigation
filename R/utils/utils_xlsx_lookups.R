# ==============================================================================
# utils_xlsx_lookups.R -- Reference XLSX Lookup Table Extraction
# ==============================================================================
# Purpose:     Parse all_codes_resolved2.xlsx (8 sheets) and extract per-code
#              metadata for treatment episode enrichment (Phase 91).
#
# Exports:     load_xlsx_lookups(xlsx_path) -> list of 5 named vectors
#
# Columns extracted:
#   medications   - Column 3 (Medication name, human-readable)
#   code_types    - Column 4 (RXNORM, CPT/HCPCS, ICD-10-CM, etc.)
#   source_tables - Column 5 (PRESCRIBING, PROCEDURES, DIAGNOSIS)
#   line_labels   - Column 8 (F/S/E/N, Chemotherapy only per D-01)
#   cross_use_flags - Column 9 (SCT conditioning/immunotherapy cross-use)
#
# Dependencies: openxlsx2 (wb_load, wb_to_df), checkmate, stringr, glue
#
# Requirements: GANTT-01 through GANTT-05
# ==============================================================================

library(openxlsx2)
library(checkmate)
library(stringr)
library(glue)


#' Normalize F/S/E/N treatment line labels to single uppercase letters
#'
#' Implements D-02: F, S, E, N only. Blank/NA/N/A/mixed-case -> NA_character_
#'
#' @param label Character. Raw label from xlsx
#' @return Character. "F", "S", "E", "N", or NA_character_
normalize_fsen <- function(label) {
  if (is.na(label) || label == "") return(NA_character_)
  cleaned <- str_to_upper(str_trim(label))
  # Extract first character for "First line" -> "F" etc.
  first_char <- str_sub(cleaned, 1, 1)
  if (first_char %in% c("F", "S", "E", "N")) return(first_char)
  # Explicit NA patterns
  if (cleaned %in% c("NA", "N/A", "NONE", "")) return(NA_character_)
  # Log unexpected value and return NA
  message(glue("  WARNING: Unexpected F/S/E/N value: '{label}' -- treating as NA"))
  return(NA_character_)
}


#' Load all treatment code metadata from all_codes_resolved2.xlsx
#'
#' Parses 4 treatment sheets (Chemotherapy, Radiation, SCT, Immunotherapy) and
#' returns 5 named character vectors for metadata enrichment. Keys are treatment
#' codes; values are metadata fields. All vectors have identical keys (all codes
#' from all sheets). Pre-join validation prevents duplicate codes across sheets.
#'
#' @param xlsx_path Character. Path to all_codes_resolved2.xlsx (default: project root)
#' @return List with 5 elements: medications, code_types, source_tables,
#'         line_labels, cross_use_flags (each a named character vector)
load_xlsx_lookups <- function(xlsx_path = "all_codes_resolved2.xlsx") {
  # Step 1: Validate input
  assert_file_exists(xlsx_path, .var.name = "[utils_xlsx_lookups ERROR] Reference XLSX")

  # Step 2: Load workbook once
  ref_wb <- wb_load(xlsx_path)

  # Step 3: Parse Chemotherapy sheet (has all 9 columns)
  message("  Loading Chemotherapy sheet...")
  chemo_sheet <- wb_to_df(ref_wb, sheet = "Chemotherapy", start_row = 2)
  chemo_codes <- as.character(chemo_sheet[[1]])
  chemo_codes <- chemo_codes[!is.na(chemo_codes) & chemo_codes != ""]

  chemo_medications <- setNames(as.character(chemo_sheet[[3]]), chemo_codes)
  chemo_code_types <- setNames(as.character(chemo_sheet[[4]]), chemo_codes)
  chemo_source_tables <- setNames(as.character(chemo_sheet[[5]]), chemo_codes)

  # Step 4: Normalize F/S/E/N labels from column 8 (D-02)
  raw_line_labels <- as.character(chemo_sheet[[8]])
  chemo_line_labels <- setNames(
    sapply(raw_line_labels, normalize_fsen, USE.NAMES = FALSE),
    chemo_codes
  )

  # Step 5: Normalize cross-use flags from column 9 (D-08 Claude's Discretion)
  # First inspect unique values
  raw_cross_use <- as.character(chemo_sheet[[9]])
  unique_cross_values <- unique(raw_cross_use[!is.na(raw_cross_use) & raw_cross_use != ""])
  message(glue("  Cross-use flag unique values in Chemotherapy: {paste(unique_cross_values, collapse = ', ')}"))

  # Normalize: pass through non-empty values, NA for empty/NA
  chemo_cross_use <- setNames(
    sapply(raw_cross_use, function(val) {
      if (is.na(val) || val == "") NA_character_ else str_trim(val)
    }, USE.NAMES = FALSE),
    chemo_codes
  )

  # Step 3b: Parse Radiation sheet
  message("  Loading Radiation sheet...")
  rad_sheet <- wb_to_df(ref_wb, sheet = "Radiation", start_row = 2)
  message(glue("    Radiation sheet has {ncol(rad_sheet)} columns"))
  rad_codes <- as.character(rad_sheet[[1]])
  rad_codes <- rad_codes[!is.na(rad_codes) & rad_codes != ""]

  # Check if column 3 exists and contains medication-like data
  if (ncol(rad_sheet) >= 3 && !all(is.na(rad_sheet[[3]]))) {
    rad_medications <- setNames(as.character(rad_sheet[[3]]), rad_codes)
  } else {
    rad_medications <- setNames(rep(NA_character_, length(rad_codes)), rad_codes)
  }

  # Extract code_type and source_table if they exist
  if (ncol(rad_sheet) >= 4) {
    rad_code_types <- setNames(as.character(rad_sheet[[4]]), rad_codes)
  } else {
    rad_code_types <- setNames(rep(NA_character_, length(rad_codes)), rad_codes)
  }

  if (ncol(rad_sheet) >= 5) {
    rad_source_tables <- setNames(as.character(rad_sheet[[5]]), rad_codes)
  } else {
    rad_source_tables <- setNames(rep(NA_character_, length(rad_codes)), rad_codes)
  }

  # Radiation has no F/S/E/N or cross-use (per D-01)
  rad_line_labels <- setNames(rep(NA_character_, length(rad_codes)), rad_codes)
  rad_cross_use <- setNames(rep(NA_character_, length(rad_codes)), rad_codes)

  # Step 3c: Parse SCT sheet
  message("  Loading SCT sheet...")
  sct_sheet <- wb_to_df(ref_wb, sheet = "SCT", start_row = 2)
  message(glue("    SCT sheet has {ncol(sct_sheet)} columns"))
  sct_codes <- as.character(sct_sheet[[1]])
  sct_codes <- sct_codes[!is.na(sct_codes) & sct_codes != ""]

  # Check if column 3 exists
  if (ncol(sct_sheet) >= 3 && !all(is.na(sct_sheet[[3]]))) {
    sct_medications <- setNames(as.character(sct_sheet[[3]]), sct_codes)
  } else {
    sct_medications <- setNames(rep(NA_character_, length(sct_codes)), sct_codes)
  }

  if (ncol(sct_sheet) >= 4) {
    sct_code_types <- setNames(as.character(sct_sheet[[4]]), sct_codes)
  } else {
    sct_code_types <- setNames(rep(NA_character_, length(sct_codes)), sct_codes)
  }

  if (ncol(sct_sheet) >= 5) {
    sct_source_tables <- setNames(as.character(sct_sheet[[5]]), sct_codes)
  } else {
    sct_source_tables <- setNames(rep(NA_character_, length(sct_codes)), sct_codes)
  }

  # No F/S/E/N or cross-use (per D-01)
  sct_line_labels <- setNames(rep(NA_character_, length(sct_codes)), sct_codes)
  sct_cross_use <- setNames(rep(NA_character_, length(sct_codes)), sct_codes)

  # Step 3d: Parse Immunotherapy sheet
  message("  Loading Immunotherapy sheet...")
  immuno_sheet <- wb_to_df(ref_wb, sheet = "Immunotherapy", start_row = 2)
  message(glue("    Immunotherapy sheet has {ncol(immuno_sheet)} columns"))
  immuno_codes <- as.character(immuno_sheet[[1]])
  immuno_codes <- immuno_codes[!is.na(immuno_codes) & immuno_codes != ""]

  # Check if column 3 exists
  if (ncol(immuno_sheet) >= 3 && !all(is.na(immuno_sheet[[3]]))) {
    immuno_medications <- setNames(as.character(immuno_sheet[[3]]), immuno_codes)
  } else {
    immuno_medications <- setNames(rep(NA_character_, length(immuno_codes)), immuno_codes)
  }

  if (ncol(immuno_sheet) >= 4) {
    immuno_code_types <- setNames(as.character(immuno_sheet[[4]]), immuno_codes)
  } else {
    immuno_code_types <- setNames(rep(NA_character_, length(immuno_codes)), immuno_codes)
  }

  if (ncol(immuno_sheet) >= 5) {
    immuno_source_tables <- setNames(as.character(immuno_sheet[[5]]), immuno_codes)
  } else {
    immuno_source_tables <- setNames(rep(NA_character_, length(immuno_codes)), immuno_codes)
  }

  # No F/S/E/N or cross-use (per D-01)
  immuno_line_labels <- setNames(rep(NA_character_, length(immuno_codes)), immuno_codes)
  immuno_cross_use <- setNames(rep(NA_character_, length(immuno_codes)), immuno_codes)

  # Step 6: Combine all lookups into a single list
  all_lookups <- list(
    medications = c(chemo_medications, rad_medications, sct_medications, immuno_medications),
    code_types = c(chemo_code_types, rad_code_types, sct_code_types, immuno_code_types),
    source_tables = c(chemo_source_tables, rad_source_tables, sct_source_tables, immuno_source_tables),
    line_labels = c(chemo_line_labels, rad_line_labels, sct_line_labels, immuno_line_labels),
    cross_use_flags = c(chemo_cross_use, rad_cross_use, sct_cross_use, immuno_cross_use)
  )

  # Step 7: Pre-join validation — detect duplicate codes (Pitfall 1 prevention)
  all_codes <- names(all_lookups$medications)
  dup_codes <- all_codes[duplicated(all_codes)]
  if (length(dup_codes) > 0) {
    stop(glue("[utils_xlsx_lookups ERROR] Duplicate codes found across xlsx sheets: {paste(unique(dup_codes), collapse = ', ')}. Deduplicate before proceeding."))
  }

  # Step 8: Log summary
  message(glue("  xlsx lookups loaded: {length(all_lookups$medications)} total codes"))
  message(glue("    Chemotherapy: {length(chemo_codes)} codes"))
  message(glue("    Radiation: {length(rad_codes)} codes"))
  message(glue("    SCT: {length(sct_codes)} codes"))
  message(glue("    Immunotherapy: {length(immuno_codes)} codes"))
  message(glue("    With F/S/E/N labels: {sum(!is.na(all_lookups$line_labels))}"))
  message(glue("    With cross-use flags: {sum(!is.na(all_lookups$cross_use_flags) & all_lookups$cross_use_flags != '')}"))

  # Step 9: Return the list
  return(all_lookups)
}
