# ==============================================================================
# 38_treatment_inventory.R -- Treatment Inventory by Source Table
# ==============================================================================
#
# Queries all 7 PCORnet CDM tables for 4 treatment types (chemotherapy,
# radiation, SCT, immunotherapy), aggregates code frequencies by source table,
# detects unknown treatment-adjacent codes via CPT/HCPCS range heuristics, and
# outputs a styled xlsx workbook with one sheet per treatment type matching
# the csv_to_xlsx.py visual pattern.
#
# Purpose: Internal exploratory inventory of all treatment-related records
# across PCORnet tables, revealing which codes appear, in which tables, and
# at what frequency -- including potentially missed codes not in the curated
# TREATMENT_CODES lists.
#
# Output: output/treatment_inventory.xlsx (workbook with 4 styled sheets)
#
# Usage:
#   Rscript R/38_treatment_inventory.R
#
# Dependencies:
#   - R/00_config.R (TREATMENT_CODES list)
#   - R/01_load_pcornet.R (PCORnet table loading)
#   - openxlsx2, dplyr, stringr, glue, tidyr
#
# Phase 38 -- chemo-treatment-inventory-by-source-table
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP AND CONFIGURATION
# ==============================================================================

source("R/00_config.R")
source("R/01_load_pcornet.R")

library(openxlsx2)
library(dplyr)
library(stringr)
library(glue)
library(tidyr)

OUTPUT_PATH <- file.path(CONFIG$output_dir, "treatment_inventory.xlsx")

# ==============================================================================
# SECTION 2: TREATMENT TYPE CONFIGURATION
# ==============================================================================

# Treatment type colors for xlsx pills (8-char hex with FF alpha prefix)
# Analogous to CATEGORY_COLORS in csv_to_xlsx.py but for treatment types
TREATMENT_TYPE_COLORS <- list(
  Chemotherapy  = list(fill = "FFDCEEFB", font = "FF0B5394"),   # light blue / dark blue
  Radiation     = list(fill = "FFDDF4E1", font = "FF274E13"),   # light green / dark green
  SCT           = list(fill = "FFFFF4D6", font = "FF7F6000"),   # light yellow / dark olive
  Immunotherapy = list(fill = "FFE8DCF4", font = "FF4C1D7A")    # light purple / dark purple
)

# CPT/HCPCS range heuristics for unknown code detection (D-08)
# Targeted ranges to catch treatment-adjacent codes NOT in TREATMENT_CODES.
# Intentionally narrow to avoid false positives from unrelated procedures.
CPT_HCPCS_RANGES <- list(
  Chemotherapy = list(
    j9_codes = "^J9[0-9]{3}$"            # J9000-J9999 injectable chemo drugs
  ),
  Radiation = list(
    delivery = "^774[0-9]{2}$"            # 77400-77499 radiation treatment delivery
  ),
  SCT = list(
    transplant = "^382[3-4][0-9]$"        # 38230-38249 HPC/bone marrow transplant
  ),
  Immunotherapy = list(
    car_t_admin = "^XW0[34]3[A-Z][0-9]$"  # CAR T-cell administration ICD-10-PCS pattern
  )
)

TREATMENT_SHEET_ORDER <- c("Chemotherapy", "Radiation", "SCT", "Immunotherapy")

# ==============================================================================
# SECTION 3: SAFE TABLE ACCESS HELPER
# ==============================================================================

#' Safely access a PCORnet table with null-guard
#'
#' Wraps get_pcornet_table() in tryCatch to handle missing tables gracefully.
#' Returns NULL (not an error) when a table doesn't exist in the current
#' data extract.
#'
#' @param name Character. PCORnet table name (e.g., "PROCEDURES", "DISPENSING")
#' @return A dplyr-compatible object (tibble or tbl_dbi), or NULL if not found
safe_table <- function(name) {
  tryCatch(
    get_pcornet_table(name),
    error = function(e) {
      message(glue("Table {name} not found; skipping"))
      NULL
    }
  )
}

#' Create empty result tibble for missing tables
empty_result <- function() {
  tibble(code = character(), code_type = character(), source_table = character(), n = integer())
}

# ==============================================================================
# SECTION 4: CODE EXTRACTION FUNCTIONS -- one per treatment type
# ==============================================================================

# ------------------------------------------------------------------------------
# extract_chemo_codes()
# ------------------------------------------------------------------------------
#' Extract chemotherapy code frequencies from all relevant PCORnet tables
#'
#' Queries: PROCEDURES (CPT/HCPCS, ICD-9, ICD-10-PCS, Revenue),
#'          PRESCRIBING, DISPENSING, MED_ADMIN (RXNORM),
#'          DIAGNOSIS (ICD-10-CM, ICD-9-CM Z/V codes),
#'          ENCOUNTER (DRG), TUMOR_REGISTRY (date evidence)
#'
#' @return Tibble with columns: code, code_type, source_table, n, treatment_type
extract_chemo_codes <- function() {
  message("  Extracting chemotherapy codes...")
  results <- list()


  # --- PROCEDURES ---
  proc_tbl <- safe_table("PROCEDURES")
  if (!is.null(proc_tbl)) {
    # CPT/HCPCS exact match
    px_ch <- tryCatch({
      proc_tbl %>%
        filter(PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) %>%
        mutate(code_type = PX_TYPE) %>%
        group_by(code = PX, code_type) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "PROCEDURES")
    }, error = function(e) empty_result())
    results <- c(results, list(px_ch))

    # ICD-9 exact match
    px_09 <- tryCatch({
      proc_tbl %>%
        filter(PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9) %>%
        mutate(code_type = PX_TYPE) %>%
        group_by(code = PX, code_type) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "PROCEDURES")
    }, error = function(e) empty_result())
    results <- c(results, list(px_09))

    # ICD-10-PCS PREFIX match (str_detect, NOT %in%)
    chemo_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$chemo_icd10pcs_prefixes, collapse = "|"), ")")
    px_10 <- tryCatch({
      proc_tbl %>%
        filter(PX_TYPE == "10") %>%
        materialize() %>%
        filter(str_detect(PX, chemo_icd10pcs_rx)) %>%
        mutate(code_type = "10") %>%
        group_by(code = PX, code_type) %>%
        summarise(n = n(), .groups = "drop") %>%
        mutate(source_table = "PROCEDURES")
    }, error = function(e) empty_result())
    results <- c(results, list(px_10))

    # Revenue codes exact match
    px_re <- tryCatch({
      proc_tbl %>%
        filter(PX_TYPE == "RE" & PX %in% TREATMENT_CODES$chemo_revenue) %>%
        mutate(code_type = PX_TYPE) %>%
        group_by(code = PX, code_type) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "PROCEDURES")
    }, error = function(e) empty_result())
    results <- c(results, list(px_re))
  }

  # --- PRESCRIBING ---
  rx_tbl <- safe_table("PRESCRIBING")
  if (!is.null(rx_tbl)) {
    rx_codes <- tryCatch({
      rx_tbl %>%
        filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
        group_by(code = RXNORM_CUI) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "PRESCRIBING", code_type = "RXNORM")
    }, error = function(e) empty_result())
    results <- c(results, list(rx_codes))
  }

  # --- DISPENSING ---
  disp_tbl <- safe_table("DISPENSING")
  if (!is.null(disp_tbl)) {
    disp_codes <- tryCatch({
      disp_tbl %>%
        filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
        group_by(code = RXNORM_CUI) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "DISPENSING", code_type = "RXNORM")
    }, error = function(e) empty_result())
    results <- c(results, list(disp_codes))
  }

  # --- MED_ADMIN ---
  ma_tbl <- safe_table("MED_ADMIN")
  if (!is.null(ma_tbl)) {
    ma_codes <- tryCatch({
      ma_tbl %>%
        filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
        group_by(code = RXNORM_CUI) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "MED_ADMIN", code_type = "RXNORM")
    }, error = function(e) empty_result())
    results <- c(results, list(ma_codes))
  }

  # --- DIAGNOSIS ---
  dx_tbl <- safe_table("DIAGNOSIS")
  if (!is.null(dx_tbl)) {
    dx_codes <- tryCatch({
      dx_tbl %>%
        filter(
          (DX_TYPE == "10" & DX %in% TREATMENT_CODES$chemo_dx_icd10) |
          (DX_TYPE == "09" & DX %in% TREATMENT_CODES$chemo_dx_icd9)
        ) %>%
        mutate(code_type = DX_TYPE) %>%
        group_by(code = DX, code_type) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "DIAGNOSIS")
    }, error = function(e) empty_result())
    results <- c(results, list(dx_codes))
  }

  # --- ENCOUNTER (DRG) ---
  enc_tbl <- safe_table("ENCOUNTER")
  if (!is.null(enc_tbl)) {
    enc_codes <- tryCatch({
      enc_tbl %>%
        filter(DRG %in% TREATMENT_CODES$chemo_drg) %>%
        group_by(code = DRG) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "ENCOUNTER", code_type = "DRG")
    }, error = function(e) empty_result())
    results <- c(results, list(enc_codes))
  }

  # --- TUMOR_REGISTRY (date evidence only, NOT codes) ---
  tr_tbl <- safe_table("TUMOR_REGISTRY_ALL")
  if (!is.null(tr_tbl)) {
    tr_codes <- tryCatch({
      # Check which chemo date columns exist
      tr_cols <- colnames(tr_tbl)
      has_dt_chemo <- "DT_CHEMO" %in% tr_cols
      has_chemo_summary <- "CHEMO_START_DATE_SUMMARY" %in% tr_cols

      if (has_dt_chemo && has_chemo_summary) {
        tr_count <- tr_tbl %>%
          filter(!is.na(DT_CHEMO) | !is.na(CHEMO_START_DATE_SUMMARY)) %>%
          summarise(n = n()) %>%
          collect()
      } else if (has_dt_chemo) {
        tr_count <- tr_tbl %>%
          filter(!is.na(DT_CHEMO)) %>%
          summarise(n = n()) %>%
          collect()
      } else if (has_chemo_summary) {
        tr_count <- tr_tbl %>%
          filter(!is.na(CHEMO_START_DATE_SUMMARY)) %>%
          summarise(n = n()) %>%
          collect()
      } else {
        tr_count <- tibble(n = 0L)
      }

      if (tr_count$n[1] > 0) {
        tibble(
          code = "DATE_EVIDENCE",
          code_type = "DATE",
          source_table = "TUMOR_REGISTRY",
          n = as.integer(tr_count$n[1])
        )
      } else {
        empty_result()
      }
    }, error = function(e) empty_result())
    results <- c(results, list(tr_codes))
  }

  bind_rows(results) %>%
    mutate(treatment_type = "Chemotherapy")
}

# ------------------------------------------------------------------------------
# extract_radiation_codes()
# ------------------------------------------------------------------------------
#' Extract radiation therapy code frequencies from relevant PCORnet tables
#'
#' Queries: PROCEDURES (CPT, ICD-9, ICD-10-PCS prefixes, Revenue),
#'          DIAGNOSIS (ICD-10-CM, ICD-9-CM), ENCOUNTER (DRG),
#'          TUMOR_REGISTRY (date evidence)
#'
#' @return Tibble with columns: code, code_type, source_table, n, treatment_type
extract_radiation_codes <- function() {
  message("  Extracting radiation codes...")
  results <- list()

  # --- PROCEDURES ---
  proc_tbl <- safe_table("PROCEDURES")
  if (!is.null(proc_tbl)) {
    # CPT exact match
    px_cpt <- tryCatch({
      proc_tbl %>%
        filter(PX_TYPE == "CH" & PX %in% TREATMENT_CODES$radiation_cpt) %>%
        mutate(code_type = PX_TYPE) %>%
        group_by(code = PX, code_type) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "PROCEDURES")
    }, error = function(e) empty_result())
    results <- c(results, list(px_cpt))

    # ICD-9 exact match
    px_09 <- tryCatch({
      proc_tbl %>%
        filter(PX_TYPE == "09" & PX %in% TREATMENT_CODES$radiation_icd9) %>%
        mutate(code_type = PX_TYPE) %>%
        group_by(code = PX, code_type) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "PROCEDURES")
    }, error = function(e) empty_result())
    results <- c(results, list(px_09))

    # ICD-10-PCS PREFIX match (str_detect for prefix matching)
    radiation_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$radiation_icd10pcs_prefixes, collapse = "|"), ")")
    px_10 <- tryCatch({
      proc_tbl %>%
        filter(PX_TYPE == "10") %>%
        materialize() %>%
        filter(str_detect(PX, radiation_icd10pcs_rx)) %>%
        mutate(code_type = "10") %>%
        group_by(code = PX, code_type) %>%
        summarise(n = n(), .groups = "drop") %>%
        mutate(source_table = "PROCEDURES")
    }, error = function(e) empty_result())
    results <- c(results, list(px_10))

    # Revenue codes exact match
    px_re <- tryCatch({
      proc_tbl %>%
        filter(PX_TYPE == "RE" & PX %in% TREATMENT_CODES$radiation_revenue) %>%
        mutate(code_type = PX_TYPE) %>%
        group_by(code = PX, code_type) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "PROCEDURES")
    }, error = function(e) empty_result())
    results <- c(results, list(px_re))
  }

  # --- DIAGNOSIS ---
  dx_tbl <- safe_table("DIAGNOSIS")
  if (!is.null(dx_tbl)) {
    dx_codes <- tryCatch({
      dx_tbl %>%
        filter(
          (DX_TYPE == "10" & DX %in% TREATMENT_CODES$radiation_dx_icd10) |
          (DX_TYPE == "09" & DX %in% TREATMENT_CODES$radiation_dx_icd9)
        ) %>%
        mutate(code_type = DX_TYPE) %>%
        group_by(code = DX, code_type) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "DIAGNOSIS")
    }, error = function(e) empty_result())
    results <- c(results, list(dx_codes))
  }

  # --- ENCOUNTER (DRG) ---
  enc_tbl <- safe_table("ENCOUNTER")
  if (!is.null(enc_tbl)) {
    enc_codes <- tryCatch({
      enc_tbl %>%
        filter(DRG %in% TREATMENT_CODES$radiation_drg) %>%
        group_by(code = DRG) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "ENCOUNTER", code_type = "DRG")
    }, error = function(e) empty_result())
    results <- c(results, list(enc_codes))
  }

  # --- TUMOR_REGISTRY (date evidence only) ---
  tr_tbl <- safe_table("TUMOR_REGISTRY_ALL")
  if (!is.null(tr_tbl)) {
    tr_codes <- tryCatch({
      tr_cols <- colnames(tr_tbl)
      if ("DT_RAD" %in% tr_cols) {
        tr_count <- tr_tbl %>%
          filter(!is.na(DT_RAD)) %>%
          summarise(n = n()) %>%
          collect()
        if (tr_count$n[1] > 0) {
          tibble(
            code = "DATE_EVIDENCE",
            code_type = "DATE",
            source_table = "TUMOR_REGISTRY",
            n = as.integer(tr_count$n[1])
          )
        } else {
          empty_result()
        }
      } else {
        empty_result()
      }
    }, error = function(e) empty_result())
    results <- c(results, list(tr_codes))
  }

  bind_rows(results) %>%
    mutate(treatment_type = "Radiation")
}

# ------------------------------------------------------------------------------
# extract_sct_codes()
# ------------------------------------------------------------------------------
#' Extract stem cell transplant code frequencies from relevant PCORnet tables
#'
#' Queries: PROCEDURES (CPT, HCPCS, ICD-9, ICD-10-PCS EXACT match, Revenue),
#'          DIAGNOSIS (ICD-10-CM), ENCOUNTER (DRG),
#'          TUMOR_REGISTRY (date evidence)
#'
#' NOTE: sct_icd10pcs stores full 7-char codes, use %in% NOT str_detect
#'
#' @return Tibble with columns: code, code_type, source_table, n, treatment_type
extract_sct_codes <- function() {
  message("  Extracting SCT codes...")
  results <- list()

  # --- PROCEDURES ---
  proc_tbl <- safe_table("PROCEDURES")
  if (!is.null(proc_tbl)) {
    # CPT exact match
    px_cpt <- tryCatch({
      proc_tbl %>%
        filter(PX_TYPE == "CH" & PX %in% TREATMENT_CODES$sct_cpt) %>%
        mutate(code_type = PX_TYPE) %>%
        group_by(code = PX, code_type) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "PROCEDURES")
    }, error = function(e) empty_result())
    results <- c(results, list(px_cpt))

    # HCPCS exact match
    px_hcpcs <- tryCatch({
      proc_tbl %>%
        filter(PX_TYPE == "CH" & PX %in% TREATMENT_CODES$sct_hcpcs) %>%
        mutate(code_type = PX_TYPE) %>%
        group_by(code = PX, code_type) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "PROCEDURES")
    }, error = function(e) empty_result())
    results <- c(results, list(px_hcpcs))

    # ICD-9 exact match
    px_09 <- tryCatch({
      proc_tbl %>%
        filter(PX_TYPE == "09" & PX %in% TREATMENT_CODES$sct_icd9) %>%
        mutate(code_type = PX_TYPE) %>%
        group_by(code = PX, code_type) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "PROCEDURES")
    }, error = function(e) empty_result())
    results <- c(results, list(px_09))

    # ICD-10-PCS EXACT match (%in%, NOT str_detect -- full 7-char codes)
    px_10 <- tryCatch({
      proc_tbl %>%
        filter(PX_TYPE == "10" & PX %in% TREATMENT_CODES$sct_icd10pcs) %>%
        mutate(code_type = PX_TYPE) %>%
        group_by(code = PX, code_type) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "PROCEDURES")
    }, error = function(e) empty_result())
    results <- c(results, list(px_10))

    # Revenue codes exact match
    px_re <- tryCatch({
      proc_tbl %>%
        filter(PX_TYPE == "RE" & PX %in% TREATMENT_CODES$sct_revenue) %>%
        mutate(code_type = PX_TYPE) %>%
        group_by(code = PX, code_type) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "PROCEDURES")
    }, error = function(e) empty_result())
    results <- c(results, list(px_re))
  }

  # --- DIAGNOSIS ---
  dx_tbl <- safe_table("DIAGNOSIS")
  if (!is.null(dx_tbl)) {
    dx_codes <- tryCatch({
      dx_tbl %>%
        filter(DX_TYPE == "10" & DX %in% TREATMENT_CODES$sct_dx_icd10) %>%
        mutate(code_type = DX_TYPE) %>%
        group_by(code = DX, code_type) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "DIAGNOSIS")
    }, error = function(e) empty_result())
    results <- c(results, list(dx_codes))
  }

  # --- ENCOUNTER (DRG) ---
  enc_tbl <- safe_table("ENCOUNTER")
  if (!is.null(enc_tbl)) {
    enc_codes <- tryCatch({
      enc_tbl %>%
        filter(DRG %in% TREATMENT_CODES$sct_drg) %>%
        group_by(code = DRG) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "ENCOUNTER", code_type = "DRG")
    }, error = function(e) empty_result())
    results <- c(results, list(enc_codes))
  }

  # --- TUMOR_REGISTRY (date evidence only) ---
  tr_tbl <- safe_table("TUMOR_REGISTRY_ALL")
  if (!is.null(tr_tbl)) {
    tr_codes <- tryCatch({
      tr_cols <- colnames(tr_tbl)
      if ("DT_HTE" %in% tr_cols) {
        tr_count <- tr_tbl %>%
          filter(!is.na(DT_HTE)) %>%
          summarise(n = n()) %>%
          collect()
        if (tr_count$n[1] > 0) {
          tibble(
            code = "DATE_EVIDENCE",
            code_type = "DATE",
            source_table = "TUMOR_REGISTRY",
            n = as.integer(tr_count$n[1])
          )
        } else {
          empty_result()
        }
      } else {
        empty_result()
      }
    }, error = function(e) empty_result())
    results <- c(results, list(tr_codes))
  }

  bind_rows(results) %>%
    mutate(treatment_type = "SCT")
}

# ------------------------------------------------------------------------------
# extract_immunotherapy_codes()
# ------------------------------------------------------------------------------
#' Extract immunotherapy (CAR T-cell) code frequencies from relevant tables
#'
#' Queries: PROCEDURES (ICD-10-PCS prefixes for CAR T-cell),
#'          ENCOUNTER (DRG 018)
#' No PRESCRIBING/DISPENSING/MED_ADMIN/DIAGNOSIS (no immunotherapy RXNORM/DX
#' codes in TREATMENT_CODES). No TUMOR_REGISTRY immunotherapy date column.
#'
#' @return Tibble with columns: code, code_type, source_table, n, treatment_type
extract_immunotherapy_codes <- function() {
  message("  Extracting immunotherapy codes...")
  results <- list()

  # --- PROCEDURES: ICD-10-PCS prefix match for CAR T-cell ---
  proc_tbl <- safe_table("PROCEDURES")
  if (!is.null(proc_tbl)) {
    cart_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$cart_icd10pcs_prefixes, collapse = "|"), ")")
    px_10 <- tryCatch({
      proc_tbl %>%
        filter(PX_TYPE == "10") %>%
        materialize() %>%
        filter(str_detect(PX, cart_icd10pcs_rx)) %>%
        mutate(code_type = "10") %>%
        group_by(code = PX, code_type) %>%
        summarise(n = n(), .groups = "drop") %>%
        mutate(source_table = "PROCEDURES")
    }, error = function(e) empty_result())
    results <- c(results, list(px_10))
  }

  # --- ENCOUNTER (DRG 018 = BMT with CAR T-cell) ---
  enc_tbl <- safe_table("ENCOUNTER")
  if (!is.null(enc_tbl)) {
    enc_codes <- tryCatch({
      enc_tbl %>%
        filter(DRG %in% c("018")) %>%
        group_by(code = DRG) %>%
        summarise(n = n(), .groups = "drop") %>%
        collect() %>%
        mutate(source_table = "ENCOUNTER", code_type = "DRG")
    }, error = function(e) empty_result())
    results <- c(results, list(enc_codes))
  }

  bind_rows(results) %>%
    mutate(treatment_type = "Immunotherapy")
}

# ==============================================================================
# SECTION 5: UNKNOWN CODE DETECTION
# ==============================================================================

#' Detect unknown treatment-adjacent codes not in TREATMENT_CODES lists
#'
#' Uses CPT/HCPCS range heuristics (CPT_HCPCS_RANGES) to find codes in
#' PROCEDURES that match broad treatment code families but are NOT in our
#' curated TREATMENT_CODES lists. Flags these as "Unmatched" for review.
#'
#' @param treatment_type Character. One of TREATMENT_SHEET_ORDER values.
#' @return Tibble with columns: code, code_type, source_table, n, treatment_type
detect_unknown_codes <- function(treatment_type) {
  range_patterns <- CPT_HCPCS_RANGES[[treatment_type]]
  if (is.null(range_patterns)) {
    return(tibble(code = character(), code_type = character(),
                  source_table = character(), n = integer(),
                  treatment_type = character()))
  }

  combined_regex <- paste(unlist(range_patterns), collapse = "|")

  # Build list of ALL known codes for this treatment type and determine PX_TYPE
  code_info <- switch(treatment_type,
    "Chemotherapy" = list(
      codes = c(TREATMENT_CODES$chemo_hcpcs, TREATMENT_CODES$chemo_icd9,
                TREATMENT_CODES$chemo_revenue),
      px_type = "CH"
    ),
    "Radiation" = list(
      codes = c(TREATMENT_CODES$radiation_cpt, TREATMENT_CODES$radiation_icd9,
                TREATMENT_CODES$radiation_revenue),
      px_type = "CH"
    ),
    "SCT" = list(
      codes = c(TREATMENT_CODES$sct_cpt, TREATMENT_CODES$sct_hcpcs,
                TREATMENT_CODES$sct_icd9, TREATMENT_CODES$sct_revenue),
      px_type = "CH"
    ),
    "Immunotherapy" = list(
      codes = unlist(TREATMENT_CODES$cart_icd10pcs_prefixes),
      px_type = "10"  # CAR T uses ICD-10-PCS, not CPT/HCPCS
    )
  )

  known_codes <- code_info$codes
  px_type_filter <- code_info$px_type

  proc_tbl <- safe_table("PROCEDURES")
  if (is.null(proc_tbl)) {
    return(tibble(code = character(), code_type = character(),
                  source_table = character(), n = integer(),
                  treatment_type = character()))
  }

  tryCatch({
    proc_tbl %>%
      filter(PX_TYPE == px_type_filter) %>%
      materialize() %>%
      filter(str_detect(PX, combined_regex)) %>%
      filter(!PX %in% known_codes) %>%
      group_by(code = PX) %>%
      summarise(n = n(), .groups = "drop") %>%
      mutate(
        source_table = "PROCEDURES (unmatched)",
        code_type = px_type_filter,
        treatment_type = treatment_type
      )
  }, error = function(e) {
    message(glue("  Warning: Unknown code detection failed for {treatment_type}: {e$message}"))
    tibble(code = character(), code_type = character(),
           source_table = character(), n = integer(),
           treatment_type = character())
  })
}

# ==============================================================================
# SECTION 6: XLSX WRITING FUNCTIONS
# ==============================================================================

#' Write a styled treatment type sheet to the workbook
#'
#' Creates a sheet matching csv_to_xlsx.py visual patterns: title/subtitle,
#' "By Source Table" summary section with colored pills, "Detailed Codes"
#' section, optional "Unmatched Codes" section, frozen panes, header fills.
#'
#' @param wb openxlsx2 workbook object
#' @param sheet_name Character. Sheet name (treatment type)
#' @param df_summary Tibble. By-source-table summary (source_table, code_type, n, pct)
#' @param df_codes Tibble. Detailed code rows (code, code_type, source_table, n)
#' @param df_unmatched Tibble. Unmatched codes (code, code_type, source_table, n)
#' @param treatment_type Character. Treatment type name for styling
write_treatment_sheet <- function(wb, sheet_name, df_summary, df_codes, df_unmatched, treatment_type) {
  wb$add_worksheet(sheet_name)

  fill_color <- TREATMENT_TYPE_COLORS[[treatment_type]]$fill
  font_color <- TREATMENT_TYPE_COLORS[[treatment_type]]$font

  # --- Row 1: Title ---
  wb$add_data(sheet = sheet_name, x = "Treatment Inventory by Source Table",
              start_row = 1, start_col = 1)
  wb$add_font(sheet = sheet_name, dims = "A1",
              name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
  wb$merge_cells(sheet = sheet_name, dims = "A1:E1")

  # --- Row 2: Subtitle ---
  subtitle <- glue("Counts and percentages of {treatment_type} codes by PCORnet table.")
  wb$add_data(sheet = sheet_name, x = as.character(subtitle),
              start_row = 2, start_col = 1)
  wb$add_font(sheet = sheet_name, dims = "A2",
              name = "Calibri", size = 10, color = wb_color("FF6B7280"))
  wb$merge_cells(sheet = sheet_name, dims = "A2:E2")

  # --- Row 3: blank ---

  # --- Row 4: Section header "By Source Table" ---
  wb$add_data(sheet = sheet_name, x = "By Source Table",
              start_row = 4, start_col = 1)
  wb$add_font(sheet = sheet_name, dims = "A4",
              name = "Calibri", size = 12, bold = TRUE, color = wb_color("FF1F2937"))

  # --- Row 5: Summary column headers ---
  summary_headers <- c("Source Table", "Code Type", "Count", "% of Total")
  for (i in seq_along(summary_headers)) {
    wb$add_data(sheet = sheet_name, x = summary_headers[i],
                start_row = 5, start_col = i)
  }
  wb$add_fill(sheet = sheet_name, dims = "A5:D5", color = wb_color("FF374151"))
  wb$add_font(sheet = sheet_name, dims = "A5:D5",
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

  # --- Rows 6+: Summary data ---
  current_row <- 6
  if (nrow(df_summary) > 0) {
    for (r in seq_len(nrow(df_summary))) {
      row_num <- current_row + r - 1
      wb$add_data(sheet = sheet_name, x = df_summary$source_table[r],
                  start_row = row_num, start_col = 1)
      wb$add_data(sheet = sheet_name, x = df_summary$code_type[r],
                  start_row = row_num, start_col = 2)
      wb$add_data(sheet = sheet_name, x = df_summary$n[r],
                  start_row = row_num, start_col = 3)
      wb$add_data(sheet = sheet_name, x = df_summary$pct[r],
                  start_row = row_num, start_col = 4)

      # Source Table column gets treatment-type colored pill
      dims_a <- glue("A{row_num}")
      wb$add_fill(sheet = sheet_name, dims = dims_a, color = wb_color(fill_color))
      wb$add_font(sheet = sheet_name, dims = dims_a,
                  name = "Calibri", size = 11, bold = TRUE, color = wb_color(font_color))

      # Count format
      dims_c <- glue("C{row_num}")
      wb$add_numfmt(sheet = sheet_name, dims = dims_c, numfmt = "#,##0")

      # Percentage format
      dims_d <- glue("D{row_num}")
      wb$add_numfmt(sheet = sheet_name, dims = dims_d, numfmt = "0.00%")
    }
    current_row <- current_row + nrow(df_summary)
  }

  # --- Summary total row ---
  total_n <- sum(df_summary$n, na.rm = TRUE)
  wb$add_data(sheet = sheet_name, x = "Total",
              start_row = current_row, start_col = 1)
  wb$add_data(sheet = sheet_name, x = total_n,
              start_row = current_row, start_col = 3)
  wb$add_data(sheet = sheet_name, x = 1.0,
              start_row = current_row, start_col = 4)

  total_dims <- glue("A{current_row}:D{current_row}")
  wb$add_fill(sheet = sheet_name, dims = total_dims, color = wb_color("FF374151"))
  wb$add_font(sheet = sheet_name, dims = total_dims,
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
  wb$add_numfmt(sheet = sheet_name, dims = glue("C{current_row}"), numfmt = "#,##0")
  wb$add_numfmt(sheet = sheet_name, dims = glue("D{current_row}"), numfmt = "0.00%")

  current_row <- current_row + 1  # blank row
  current_row <- current_row + 1

  # --- Section header "Detailed Codes" ---
  wb$add_data(sheet = sheet_name, x = "Detailed Codes",
              start_row = current_row, start_col = 1)
  wb$add_font(sheet = sheet_name, dims = glue("A{current_row}"),
              name = "Calibri", size = 12, bold = TRUE, color = wb_color("FF1F2937"))
  current_row <- current_row + 1

  # --- Detail header row ---
  detail_header_row <- current_row
  detail_headers <- c("Code", "Code Type", "Source Table", "Count", "% of Total")
  for (i in seq_along(detail_headers)) {
    wb$add_data(sheet = sheet_name, x = detail_headers[i],
                start_row = detail_header_row, start_col = i)
  }
  detail_header_dims <- glue("A{detail_header_row}:E{detail_header_row}")
  wb$add_fill(sheet = sheet_name, dims = detail_header_dims, color = wb_color("FF374151"))
  wb$add_font(sheet = sheet_name, dims = detail_header_dims,
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
  current_row <- current_row + 1

  # --- Detail data rows ---
  detail_total <- sum(df_codes$n, na.rm = TRUE)
  if (nrow(df_codes) > 0) {
    for (r in seq_len(nrow(df_codes))) {
      row_num <- current_row + r - 1
      wb$add_data(sheet = sheet_name, x = df_codes$code[r],
                  start_row = row_num, start_col = 1)
      wb$add_data(sheet = sheet_name, x = df_codes$code_type[r],
                  start_row = row_num, start_col = 2)
      wb$add_data(sheet = sheet_name, x = df_codes$source_table[r],
                  start_row = row_num, start_col = 3)
      wb$add_data(sheet = sheet_name, x = df_codes$n[r],
                  start_row = row_num, start_col = 4)
      pct_val <- if (detail_total > 0) df_codes$n[r] / detail_total else 0
      wb$add_data(sheet = sheet_name, x = pct_val,
                  start_row = row_num, start_col = 5)

      # Code column: Calibri 10pt bold dark gray (CODE_FONT from csv_to_xlsx.py)
      wb$add_font(sheet = sheet_name, dims = glue("A{row_num}"),
                  name = "Calibri", size = 10, bold = TRUE, color = wb_color("FF374151"))
      # Body font for other columns
      wb$add_font(sheet = sheet_name, dims = glue("B{row_num}:C{row_num}"),
                  name = "Calibri", size = 10, color = wb_color("FF111827"))

      wb$add_numfmt(sheet = sheet_name, dims = glue("D{row_num}"), numfmt = "#,##0")
      wb$add_numfmt(sheet = sheet_name, dims = glue("E{row_num}"), numfmt = "0.00%")
    }
    current_row <- current_row + nrow(df_codes)
  }

  # --- Unmatched codes section (if any) ---
  if (nrow(df_unmatched) > 0) {
    current_row <- current_row + 1  # blank row

    # Section header: "Unmatched Codes (Heuristic Detection)"
    wb$add_data(sheet = sheet_name, x = "Unmatched Codes (Heuristic Detection)",
                start_row = current_row, start_col = 1)
    wb$add_font(sheet = sheet_name, dims = glue("A{current_row}"),
                name = "Calibri", size = 12, bold = TRUE, color = wb_color("FF1F2937"))
    current_row <- current_row + 1

    # Unmatched header row
    for (i in seq_along(detail_headers)) {
      wb$add_data(sheet = sheet_name, x = detail_headers[i],
                  start_row = current_row, start_col = i)
    }
    unmatched_header_dims <- glue("A{current_row}:E{current_row}")
    wb$add_fill(sheet = sheet_name, dims = unmatched_header_dims, color = wb_color("FF374151"))
    wb$add_font(sheet = sheet_name, dims = unmatched_header_dims,
                name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
    current_row <- current_row + 1

    # Unmatched data rows
    unmatched_total <- sum(df_unmatched$n, na.rm = TRUE)
    for (r in seq_len(nrow(df_unmatched))) {
      row_num <- current_row + r - 1
      wb$add_data(sheet = sheet_name, x = df_unmatched$code[r],
                  start_row = row_num, start_col = 1)
      wb$add_data(sheet = sheet_name, x = df_unmatched$code_type[r],
                  start_row = row_num, start_col = 2)
      wb$add_data(sheet = sheet_name, x = df_unmatched$source_table[r],
                  start_row = row_num, start_col = 3)
      wb$add_data(sheet = sheet_name, x = df_unmatched$n[r],
                  start_row = row_num, start_col = 4)
      pct_val <- if (unmatched_total > 0) df_unmatched$n[r] / unmatched_total else 0
      wb$add_data(sheet = sheet_name, x = pct_val,
                  start_row = row_num, start_col = 5)

      wb$add_font(sheet = sheet_name, dims = glue("A{row_num}"),
                  name = "Calibri", size = 10, bold = TRUE, color = wb_color("FF374151"))
      wb$add_font(sheet = sheet_name, dims = glue("B{row_num}:C{row_num}"),
                  name = "Calibri", size = 10, color = wb_color("FF111827"))
      wb$add_numfmt(sheet = sheet_name, dims = glue("D{row_num}"), numfmt = "#,##0")
      wb$add_numfmt(sheet = sheet_name, dims = glue("E{row_num}"), numfmt = "0.00%")
    }
    current_row <- current_row + nrow(df_unmatched)
  }

  # --- Final total row (TOTAL_FILL) ---
  grand_total <- sum(df_codes$n, na.rm = TRUE) + sum(df_unmatched$n, na.rm = TRUE)
  wb$add_data(sheet = sheet_name, x = "TOTAL",
              start_row = current_row, start_col = 1)
  wb$add_data(sheet = sheet_name, x = grand_total,
              start_row = current_row, start_col = 4)
  wb$add_data(sheet = sheet_name, x = 1.0,
              start_row = current_row, start_col = 5)

  for (col in 1:5) {
    dims <- glue("{LETTERS[col]}{current_row}")
    wb$add_fill(sheet = sheet_name, dims = dims, color = wb_color("FF1F2937"))
    wb$add_font(sheet = sheet_name, dims = dims,
                name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
  }
  wb$add_numfmt(sheet = sheet_name, dims = glue("D{current_row}"), numfmt = "#,##0")
  wb$add_numfmt(sheet = sheet_name, dims = glue("E{current_row}"), numfmt = "0.00%")

  # --- Freeze pane at first detail data row ---
  freeze_row <- detail_header_row + 1
  wb$freeze_pane(sheet = sheet_name, first_active_row = freeze_row)

  # --- Column widths ---
  wb$set_col_widths(sheet = sheet_name, cols = 1:5, widths = c(16, 14, 20, 14, 14))

  invisible(wb)
}

# ==============================================================================
# SECTION 7: MAIN EXECUTION
# ==============================================================================

message("=== Treatment Inventory by Source Table ===")
message("")

# --- Extract codes from all 4 treatment types ---
message("Extracting treatment codes from PCORnet tables...")
all_codes <- bind_rows(
  extract_chemo_codes(),
  extract_radiation_codes(),
  extract_sct_codes(),
  extract_immunotherapy_codes()
)

# --- Detect unknown codes via CPT/HCPCS heuristics ---
message("")
message("Detecting unknown codes via CPT/HCPCS range heuristics...")
all_unmatched <- bind_rows(lapply(TREATMENT_SHEET_ORDER, detect_unknown_codes))

# --- Log summary to console ---
message("")
message("--- Summary ---")
for (type in TREATMENT_SHEET_ORDER) {
  type_data <- filter(all_codes, treatment_type == type)
  n_records <- sum(type_data$n, na.rm = TRUE)
  n_sources <- n_distinct(type_data$source_table)
  message(glue("  {type}: {format(n_records, big.mark = ',')} records from {n_sources} source tables"))
}
message("")

type_unmatched_counts <- all_unmatched %>%
  group_by(treatment_type) %>%
  summarise(n_codes = n(), n_records = sum(n), .groups = "drop")
if (nrow(type_unmatched_counts) > 0) {
  message("--- Unmatched Codes ---")
  for (r in seq_len(nrow(type_unmatched_counts))) {
    message(glue("  {type_unmatched_counts$treatment_type[r]}: {type_unmatched_counts$n_codes[r]} unique codes ({format(type_unmatched_counts$n_records[r], big.mark = ',')} records)"))
  }
  message("")
}

# --- Create workbook ---
message("Writing xlsx workbook...")
wb <- wb_workbook()

for (type in TREATMENT_SHEET_ORDER) {
  type_codes <- filter(all_codes, treatment_type == type)
  type_unmatched <- filter(all_unmatched, treatment_type == type)

  # Build summary: group by source_table and code_type
  type_summary <- type_codes %>%
    group_by(source_table, code_type) %>%
    summarise(n = sum(n), .groups = "drop") %>%
    mutate(pct = n / sum(n)) %>%
    arrange(desc(n))

  # Build detail: arrange by source_table descending count
  type_detail <- type_codes %>%
    arrange(source_table, desc(n))

  write_treatment_sheet(wb, type, type_summary, type_detail, type_unmatched, type)
}

# --- Save workbook ---
dir.create(CONFIG$output_dir, showWarnings = FALSE, recursive = TRUE)
wb$save(OUTPUT_PATH)
message(glue("Wrote {OUTPUT_PATH}"))
message("")

# --- Final summary ---
message("=== Treatment Inventory Complete ===")
for (type in TREATMENT_SHEET_ORDER) {
  type_data <- filter(all_codes, treatment_type == type)
  n_records <- sum(type_data$n, na.rm = TRUE)
  n_sources <- n_distinct(type_data$source_table)
  message(glue("  {type}: {format(n_records, big.mark = ',')} records from {n_sources} source tables"))
}
message("")
message(glue("Output: {OUTPUT_PATH}"))
