# ==============================================================================
# utils_xlsx_lookups.R -- Treatment Code Metadata from Config
# ==============================================================================
# Purpose:     Build per-code metadata for treatment episode enrichment (Phase 91)
#              from R/00_config.R data structures instead of an external XLSX file.
#
# Exports:     load_xlsx_lookups() -> list of 5 named vectors
#
# Vectors returned:
#   medications   - Human-readable drug/procedure name (from CODE_SUBCATEGORY_MAP)
#   code_types    - Code system (CPT/HCPCS, RXNORM, ICD-10-PCS, etc.)
#   source_tables - PCORnet table origin (PROCEDURES, PRESCRIBING, DIAGNOSIS, ENCOUNTER)
#   line_labels   - F/S/E/N treatment line (all NA -- not derivable from config)
#   cross_use_flags - Immunotherapy cross-use annotations (from QUESTIONABLE_IMMUNO_CODES)
#
# Dependencies: stringr, glue, R/00_config.R (TREATMENT_CODES, CODE_SUBCATEGORY_MAP,
#               DRUG_GROUPINGS, QUESTIONABLE_IMMUNO_CODES)
#
# Requirements: GANTT-01 through GANTT-05
# ==============================================================================

library(stringr)
library(glue)


#' Build treatment code metadata lookups from config data
#'
#' Constructs 5 named character vectors from TREATMENT_CODES, CODE_SUBCATEGORY_MAP,
#' DRUG_GROUPINGS, and QUESTIONABLE_IMMUNO_CODES (all defined in R/00_config.R).
#' Replaces the previous XLSX-based implementation. The function signature accepts
#' an optional xlsx_path for backward compatibility but ignores it.
#'
#' @param xlsx_path Character. Ignored (kept for backward compatibility).
#' @return List with 5 elements: medications, code_types, source_tables,
#'         line_labels, cross_use_flags (each a named character vector)
load_xlsx_lookups <- function(xlsx_path = NULL) {

  message("  Building treatment code lookups from config data...")

  # --- Step 1: Collect all treatment codes from TREATMENT_CODES ---
  # Map each sublist name to its code_type and source_table based on naming convention

  # Define code_type mapping by sublist name suffix/pattern
  code_type_map <- list(
    chemo_hcpcs         = "CPT/HCPCS",
    chemo_rxnorm        = "RXNORM",
    radiation_cpt       = "CPT/HCPCS",
    proton_cpt          = "CPT/HCPCS",
    sct_cpt             = "CPT/HCPCS",
    sct_hcpcs           = "CPT/HCPCS",
    chemo_icd9          = "ICD-9-CM",
    chemo_icd10pcs_prefixes = "ICD-10-PCS",
    radiation_icd9      = "ICD-9-CM",
    radiation_icd10pcs_prefixes = "ICD-10-PCS",
    sct_icd9            = "ICD-9-CM",
    sct_icd10pcs        = "ICD-10-PCS",
    cart_icd10pcs_prefixes = "ICD-10-PCS",
    chemo_dx_icd10      = "ICD-10-CM",
    chemo_dx_icd9       = "ICD-9-CM",
    immunotherapy_dx_icd10 = "ICD-10-CM",
    immunotherapy_dx_icd9  = "ICD-9-CM",
    radiation_dx_icd10  = "ICD-10-CM",
    radiation_dx_icd9   = "ICD-9-CM",
    chemo_drg           = "DRG",
    radiation_drg       = "DRG",
    sct_drg             = "DRG",
    immunotherapy_drg   = "DRG",
    supportive_care_rxnorm = "RXNORM",
    immunotherapy_hcpcs = "CPT/HCPCS",
    immunotherapy_rxnorm = "RXNORM",
    sct_rxnorm          = "RXNORM",
    chemo_revenue       = "Revenue",
    radiation_revenue   = "Revenue",
    sct_revenue         = "Revenue"
  )

  # Define source_table mapping by sublist name suffix/pattern
  source_table_map <- list(
    chemo_hcpcs         = "PROCEDURES",
    chemo_rxnorm        = "PRESCRIBING",
    radiation_cpt       = "PROCEDURES",
    proton_cpt          = "PROCEDURES",
    sct_cpt             = "PROCEDURES",
    sct_hcpcs           = "PROCEDURES",
    chemo_icd9          = "PROCEDURES",
    chemo_icd10pcs_prefixes = "PROCEDURES",
    radiation_icd9      = "PROCEDURES",
    radiation_icd10pcs_prefixes = "PROCEDURES",
    sct_icd9            = "PROCEDURES",
    sct_icd10pcs        = "PROCEDURES",
    cart_icd10pcs_prefixes = "PROCEDURES",
    chemo_dx_icd10      = "DIAGNOSIS",
    chemo_dx_icd9       = "DIAGNOSIS",
    immunotherapy_dx_icd10 = "DIAGNOSIS",
    immunotherapy_dx_icd9  = "DIAGNOSIS",
    radiation_dx_icd10  = "DIAGNOSIS",
    radiation_dx_icd9   = "DIAGNOSIS",
    chemo_drg           = "ENCOUNTER",
    radiation_drg       = "ENCOUNTER",
    sct_drg             = "ENCOUNTER",
    immunotherapy_drg   = "ENCOUNTER",
    supportive_care_rxnorm = "PRESCRIBING",
    immunotherapy_hcpcs = "PROCEDURES",
    immunotherapy_rxnorm = "PRESCRIBING",
    sct_rxnorm          = "PRESCRIBING",
    chemo_revenue       = "PROCEDURES",
    radiation_revenue   = "PROCEDURES",
    sct_revenue         = "PROCEDURES"
  )

  # --- Step 2: Build code_types and source_tables vectors ---
  all_code_types <- character(0)
  all_source_tables <- character(0)

  for (sublist_name in names(TREATMENT_CODES)) {
    codes <- TREATMENT_CODES[[sublist_name]]
    n <- length(codes)

    ct <- code_type_map[[sublist_name]]
    st <- source_table_map[[sublist_name]]

    if (is.null(ct)) ct <- NA_character_
    if (is.null(st)) st <- NA_character_

    new_ct <- setNames(rep(ct, n), codes)
    new_st <- setNames(rep(st, n), codes)

    # Only add codes not already present (first occurrence wins)
    new_codes <- setdiff(names(new_ct), names(all_code_types))
    if (length(new_codes) > 0) {
      all_code_types <- c(all_code_types, new_ct[new_codes])
      all_source_tables <- c(all_source_tables, new_st[new_codes])
    }
  }

  all_codes <- names(all_code_types)

  # --- Step 3: Build medications vector ---
  # Primary source: CODE_SUBCATEGORY_MAP (has human-readable names)
  # Fallback: DRUG_GROUPINGS category label (e.g., "Chemotherapy agent")
  all_medications <- setNames(rep(NA_character_, length(all_codes)), all_codes)

  for (code in all_codes) {
    if (code %in% names(CODE_SUBCATEGORY_MAP)) {
      all_medications[code] <- CODE_SUBCATEGORY_MAP[code]
    } else if (code %in% names(DRUG_GROUPINGS)) {
      all_medications[code] <- paste0(DRUG_GROUPINGS[code], " agent")
    }
  }

  # --- Step 4: Build line_labels vector (all NA -- not derivable from config) ---
  all_line_labels <- setNames(rep(NA_character_, length(all_codes)), all_codes)

  # --- Step 5: Build cross_use_flags vector from QUESTIONABLE_IMMUNO_CODES ---
  all_cross_use <- setNames(rep(NA_character_, length(all_codes)), all_codes)
  for (code in names(QUESTIONABLE_IMMUNO_CODES)) {
    if (code %in% all_codes) {
      all_cross_use[code] <- QUESTIONABLE_IMMUNO_CODES[code]
    }
  }

  # --- Step 6: Assemble return list ---
  all_lookups <- list(
    medications     = all_medications,
    code_types      = all_code_types,
    source_tables   = all_source_tables,
    line_labels     = all_line_labels,
    cross_use_flags = all_cross_use
  )

  # --- Step 7: Validate no duplicate codes ---
  dup_codes <- all_codes[duplicated(all_codes)]
  if (length(dup_codes) > 0) {
    stop(glue("[utils_xlsx_lookups ERROR] Duplicate codes found: {paste(unique(dup_codes), collapse = ', ')}. Deduplicate before proceeding."))
  }

  # --- Step 8: Log summary ---
  n_total <- length(all_codes)
  n_with_med <- sum(!is.na(all_medications) & all_medications != "")
  n_with_cross <- sum(!is.na(all_cross_use) & all_cross_use != "")

  message(glue("  Config-based lookups built: {n_total} total codes"))
  message(glue("    With medication names: {n_with_med}"))
  message(glue("    With code_type: {sum(!is.na(all_code_types))}"))
  message(glue("    With source_table: {sum(!is.na(all_source_tables))}"))
  message(glue("    With F/S/E/N labels: {sum(!is.na(all_line_labels))}"))
  message(glue("    With cross-use flags: {n_with_cross}"))

  return(all_lookups)
}
