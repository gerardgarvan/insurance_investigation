# ==============================================================================
# 20_treatment_inventory.R -- Treatment Inventory by Source Table
# ==============================================================================
# Purpose:     Treatment inventory by source table: counts code frequencies
#              across 7 PCORnet tables for Chemotherapy, Radiation, SCT, and
#              Immunotherapy. Detects unknown treatment-adjacent codes via
#              CPT/HCPCS range heuristics.
#
# Inputs:      PCORnet CDM tables (PROCEDURES, PRESCRIBING, MED_ADMIN, DIAGNOSIS,
#              LAB_RESULT_CM, CONDITION, OBS_CLIN via get_pcornet_table),
#              TREATMENT_CODES from R/00_config.R
#
# Outputs:     output/treatment_inventory.xlsx (workbook with 4 styled sheets)
#
# Dependencies: R/00_config.R, R/01_load_pcornet.R
#
# Requirements: Phase 20 exploratory inventory (D-08 heuristic detection)
# ==============================================================================

# SECTION 1: SETUP AND CONFIGURATION ----

source("R/00_config.R")
source("R/01_load_pcornet.R")

library(openxlsx2)
library(dplyr)
library(stringr)
library(glue)
library(tidyr)

OUTPUT_PATH <- file.path(CONFIG$output_dir, "treatment_inventory.xlsx")

# WHY 7 PCORnet tables: Treatment evidence is scattered across multiple tables.
# PROCEDURES captures procedure codes (CPT/HCPCS/ICD-10-PCS). PRESCRIBING,
# DISPENSING, MED_ADMIN capture drug records (RXNORM/NDC). DIAGNOSIS captures
# Z/V codes for chemotherapy encounters. ENCOUNTER captures DRG codes.
# TUMOR_REGISTRY captures date-only evidence (no codes). Searching all 7 sources
# maximizes treatment detection sensitivity.

# SECTION 2: TREATMENT TYPE CONFIGURATION ----

# Treatment type colors and constants: see R/00_config.R
# TREATMENT_TYPE_COLORS, TREATMENT_TYPES provided via config

# WHY CPT/HCPCS range heuristics: Detects codes matching treatment code families
# (J9000-J9999 chemo, 77400-77499 radiation delivery, etc.) but NOT in curated
# TREATMENT_CODES lists. Identifies potentially missed codes for manual review and
# config update. Range-based detection reduces manual exploration burden.
# Phase 39: Widened ranges to include J0-J8 supportive care and 773xx radiation planning.
CPT_HCPCS_RANGES <- list(
  Chemotherapy = list(
    j9_codes = "^J9[0-9]{3}$", # J9000-J9999 injectable chemo drugs
    j0_j8_drugs = "^J[0-8][0-9]{3}$" # J0000-J8999 for supportive care detection (Phase 39)
  ),
  Radiation = list(
    delivery = "^774[0-9]{2}$", # 77400-77499 radiation treatment delivery
    planning = "^773[0-9]{2}$" # 77300-77399 treatment planning (Phase 39)
  ),
  SCT = list(
    transplant = "^382[3-4][0-9]$" # 38230-38249 HPC/bone marrow transplant
  ),
  Immunotherapy = list(
    car_t_admin = "^XW0[34]3[A-Z][0-9]$" # CAR T-cell administration ICD-10-PCS pattern
  )
)

# Treatment sheet order uses centralized TREATMENT_TYPES from config
TREATMENT_SHEET_ORDER <- TREATMENT_TYPES

# SECTION 3: SAFE TABLE ACCESS AND HELPER FUNCTIONS ----

# safe_table(), empty_result(), get_hl_patient_ids() now provided by
# R/utils_treatment.R (auto-sourced via R/00_config.R)

# SECTION 4: CODE EXTRACTION FUNCTIONS ----

# ------------------------------------------------------------------------------
# extract_chemo_codes()
# ------------------------------------------------------------------------------
#' Extract chemotherapy code frequencies + all drugs for HL patients
#'
#' Queries: PROCEDURES (CPT/HCPCS, ICD-9, ICD-10-PCS, Revenue) for chemo codes,
#'          PRESCRIBING, DISPENSING, MED_ADMIN for ALL drugs prescribed to HL patients
#'            (not limited to curated TREATMENT_CODES -- shows full drug landscape),
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
    px_ch <- tryCatch(
      {
        proc_tbl %>%
          filter(PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) %>%
          mutate(code_type = PX_TYPE) %>%
          group_by(code = PX, code_type) %>%
          summarise(n = n(), .groups = "drop") %>%
          collect() %>%
          mutate(source_table = "PROCEDURES", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(px_ch))

    # ICD-9 exact match
    px_09 <- tryCatch(
      {
        proc_tbl %>%
          filter(PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9) %>%
          mutate(code_type = PX_TYPE) %>%
          group_by(code = PX, code_type) %>%
          summarise(n = n(), .groups = "drop") %>%
          collect() %>%
          mutate(source_table = "PROCEDURES", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(px_09))

    # ICD-10-PCS PREFIX match (str_detect, NOT %in%)
    chemo_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$chemo_icd10pcs_prefixes, collapse = "|"), ")")
    px_10 <- tryCatch(
      {
        proc_tbl %>%
          filter(PX_TYPE == "10") %>%
          materialize() %>%
          filter(str_detect(PX, chemo_icd10pcs_rx)) %>%
          mutate(code_type = "10") %>%
          group_by(code = PX, code_type) %>%
          summarise(n = n(), .groups = "drop") %>%
          mutate(source_table = "PROCEDURES", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(px_10))

    # Revenue codes exact match
    px_re <- tryCatch(
      {
        proc_tbl %>%
          filter(PX_TYPE == "RE" & PX %in% TREATMENT_CODES$chemo_revenue) %>%
          mutate(code_type = PX_TYPE) %>%
          group_by(code = PX, code_type) %>%
          summarise(n = n(), .groups = "drop") %>%
          collect() %>%
          mutate(source_table = "PROCEDURES", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(px_re))
  }

  # --- ALL DRUGS FOR HL PATIENTS ---
  # Instead of filtering to curated chemo_rxnorm list, pull ALL drugs
  # prescribed/dispensed/administered to patients with an HL diagnosis.
  # This reveals the full drug landscape, not just known ABVD codes.
  hl_ids <- get_hl_patient_ids()

  if (length(hl_ids) > 0) {
    # --- PRESCRIBING (all drugs for HL patients) ---
    rx_tbl <- safe_table("PRESCRIBING")
    if (!is.null(rx_tbl)) {
      rx_codes <- tryCatch(
        {
          rx_tbl %>%
            filter(ID %in% hl_ids) %>%
            filter(!is.na(RXNORM_CUI) & RXNORM_CUI != "") %>%
            group_by(code = RXNORM_CUI, drug_name = RAW_RX_MED_NAME) %>%
            summarise(n = n(), .groups = "drop") %>%
            collect() %>%
            mutate(source_table = "PRESCRIBING", code_type = "RXNORM")
        },
        error = function(e) empty_result()
      )
      results <- c(results, list(rx_codes))
    }

    # --- DISPENSING (all drugs for HL patients) ---
    disp_tbl <- safe_table("DISPENSING")
    if (!is.null(disp_tbl)) {
      # RXNORM records with drug name
      disp_rxnorm <- tryCatch(
        {
          disp_tbl %>%
            filter(ID %in% hl_ids) %>%
            filter(!is.na(RXNORM_CUI) & RXNORM_CUI != "") %>%
            group_by(code = RXNORM_CUI, drug_name = RAW_DISPENSE_MED_NAME) %>%
            summarise(n = n(), .groups = "drop") %>%
            collect() %>%
            mutate(source_table = "DISPENSING", code_type = "RXNORM")
        },
        error = function(e) empty_result()
      )
      results <- c(results, list(disp_rxnorm))

      # NDC codes with drug name
      disp_ndc <- tryCatch(
        {
          disp_tbl %>%
            filter(ID %in% hl_ids) %>%
            filter(!is.na(NDC) & NDC != "") %>%
            group_by(code = NDC, drug_name = RAW_DISPENSE_MED_NAME) %>%
            summarise(n = n(), .groups = "drop") %>%
            collect() %>%
            mutate(source_table = "DISPENSING", code_type = "NDC")
        },
        error = function(e) empty_result()
      )
      results <- c(results, list(disp_ndc))
    }

    # --- MED_ADMIN (all drugs for HL patients) ---
    ma_tbl <- safe_table("MED_ADMIN")
    if (!is.null(ma_tbl)) {
      ma_codes <- tryCatch(
        {
          ma_tbl %>%
            filter(ID %in% hl_ids) %>%
            filter(!is.na(RXNORM_CUI) & RXNORM_CUI != "") %>%
            group_by(code = RXNORM_CUI, drug_name = RAW_MEDADMIN_MED_NAME) %>%
            summarise(n = n(), .groups = "drop") %>%
            collect() %>%
            mutate(source_table = "MED_ADMIN", code_type = "RXNORM")
        },
        error = function(e) empty_result()
      )
      results <- c(results, list(ma_codes))
    }
  }

  # --- DIAGNOSIS ---
  dx_tbl <- safe_table("DIAGNOSIS")
  if (!is.null(dx_tbl)) {
    dx_codes <- tryCatch(
      {
        dx_tbl %>%
          filter(
            (DX_TYPE == "10" & DX %in% TREATMENT_CODES$chemo_dx_icd10) |
              (DX_TYPE == "09" & DX %in% TREATMENT_CODES$chemo_dx_icd9)
          ) %>%
          mutate(code_type = DX_TYPE) %>%
          group_by(code = DX, code_type) %>%
          summarise(n = n(), .groups = "drop") %>%
          collect() %>%
          mutate(source_table = "DIAGNOSIS", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(dx_codes))
  }

  # --- ENCOUNTER (DRG) ---
  enc_tbl <- safe_table("ENCOUNTER")
  if (!is.null(enc_tbl)) {
    enc_codes <- tryCatch(
      {
        enc_tbl %>%
          filter(DRG %in% TREATMENT_CODES$chemo_drg) %>%
          group_by(code = DRG) %>%
          summarise(n = n(), .groups = "drop") %>%
          collect() %>%
          mutate(source_table = "ENCOUNTER", code_type = "DRG", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(enc_codes))
  }

  # --- TUMOR_REGISTRY (date evidence only, NOT codes) ---
  tr_tbl <- safe_table("TUMOR_REGISTRY_ALL")
  if (!is.null(tr_tbl)) {
    tr_codes <- tryCatch(
      {
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
            n = as.integer(tr_count$n[1]),
            drug_name = NA_character_
          )
        } else {
          empty_result()
        }
      },
      error = function(e) empty_result()
    )
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
#' @return Tibble with columns: code, code_type, source_table, n, drug_name, treatment_type
extract_radiation_codes <- function() {
  message("  Extracting radiation codes...")
  results <- list()

  # --- PROCEDURES ---
  proc_tbl <- safe_table("PROCEDURES")
  if (!is.null(proc_tbl)) {
    px_cpt <- tryCatch(
      {
        proc_tbl %>%
          filter(PX_TYPE == "CH" & PX %in% TREATMENT_CODES$radiation_cpt) %>%
          mutate(code_type = PX_TYPE) %>%
          group_by(code = PX, code_type) %>%
          summarise(n = n(), .groups = "drop") %>%
          collect() %>%
          mutate(source_table = "PROCEDURES", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(px_cpt))

    px_09 <- tryCatch(
      {
        proc_tbl %>%
          filter(PX_TYPE == "09" & PX %in% TREATMENT_CODES$radiation_icd9) %>%
          mutate(code_type = PX_TYPE) %>%
          group_by(code = PX, code_type) %>%
          summarise(n = n(), .groups = "drop") %>%
          collect() %>%
          mutate(source_table = "PROCEDURES", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(px_09))

    radiation_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$radiation_icd10pcs_prefixes, collapse = "|"), ")")
    px_10 <- tryCatch(
      {
        proc_tbl %>%
          filter(PX_TYPE == "10") %>%
          materialize() %>%
          filter(str_detect(PX, radiation_icd10pcs_rx)) %>%
          mutate(code_type = "10") %>%
          group_by(code = PX, code_type) %>%
          summarise(n = n(), .groups = "drop") %>%
          mutate(source_table = "PROCEDURES", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(px_10))

    px_re <- tryCatch(
      {
        proc_tbl %>%
          filter(PX_TYPE == "RE" & PX %in% TREATMENT_CODES$radiation_revenue) %>%
          mutate(code_type = PX_TYPE) %>%
          group_by(code = PX, code_type) %>%
          summarise(n = n(), .groups = "drop") %>%
          collect() %>%
          mutate(source_table = "PROCEDURES", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(px_re))
  }

  # --- DIAGNOSIS ---
  dx_tbl <- safe_table("DIAGNOSIS")
  if (!is.null(dx_tbl)) {
    dx_codes <- tryCatch(
      {
        dx_tbl %>%
          filter(
            (DX_TYPE == "10" & DX %in% TREATMENT_CODES$radiation_dx_icd10) |
              (DX_TYPE == "09" & DX %in% TREATMENT_CODES$radiation_dx_icd9)
          ) %>%
          mutate(code_type = DX_TYPE) %>%
          group_by(code = DX, code_type) %>%
          summarise(n = n(), .groups = "drop") %>%
          collect() %>%
          mutate(source_table = "DIAGNOSIS", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(dx_codes))
  }

  # --- ENCOUNTER (DRG) ---
  enc_tbl <- safe_table("ENCOUNTER")
  if (!is.null(enc_tbl)) {
    enc_codes <- tryCatch(
      {
        enc_tbl %>%
          filter(DRG %in% TREATMENT_CODES$radiation_drg) %>%
          group_by(code = DRG) %>%
          summarise(n = n(), .groups = "drop") %>%
          collect() %>%
          mutate(source_table = "ENCOUNTER", code_type = "DRG", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(enc_codes))
  }

  # --- TUMOR_REGISTRY (date evidence only) ---
  tr_tbl <- safe_table("TUMOR_REGISTRY_ALL")
  if (!is.null(tr_tbl)) {
    tr_codes <- tryCatch(
      {
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
              n = as.integer(tr_count$n[1]),
              drug_name = NA_character_
            )
          } else {
            empty_result()
          }
        } else {
          empty_result()
        }
      },
      error = function(e) empty_result()
    )
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
#' @return Tibble with columns: code, code_type, source_table, n, drug_name, treatment_type
extract_sct_codes <- function() {
  message("  Extracting SCT codes...")
  results <- list()

  # --- PROCEDURES ---
  proc_tbl <- safe_table("PROCEDURES")
  if (!is.null(proc_tbl)) {
    px_cpt <- tryCatch(
      {
        proc_tbl %>%
          filter(PX_TYPE == "CH" & PX %in% TREATMENT_CODES$sct_cpt) %>%
          mutate(code_type = PX_TYPE) %>%
          group_by(code = PX, code_type) %>%
          summarise(n = n(), .groups = "drop") %>%
          collect() %>%
          mutate(source_table = "PROCEDURES", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(px_cpt))

    px_hcpcs <- tryCatch(
      {
        proc_tbl %>%
          filter(PX_TYPE == "CH" & PX %in% TREATMENT_CODES$sct_hcpcs) %>%
          mutate(code_type = PX_TYPE) %>%
          group_by(code = PX, code_type) %>%
          summarise(n = n(), .groups = "drop") %>%
          collect() %>%
          mutate(source_table = "PROCEDURES", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(px_hcpcs))

    px_09 <- tryCatch(
      {
        proc_tbl %>%
          filter(PX_TYPE == "09" & PX %in% TREATMENT_CODES$sct_icd9) %>%
          mutate(code_type = PX_TYPE) %>%
          group_by(code = PX, code_type) %>%
          summarise(n = n(), .groups = "drop") %>%
          collect() %>%
          mutate(source_table = "PROCEDURES", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(px_09))

    px_10 <- tryCatch(
      {
        proc_tbl %>%
          filter(PX_TYPE == "10" & PX %in% TREATMENT_CODES$sct_icd10pcs) %>%
          mutate(code_type = PX_TYPE) %>%
          group_by(code = PX, code_type) %>%
          summarise(n = n(), .groups = "drop") %>%
          collect() %>%
          mutate(source_table = "PROCEDURES", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(px_10))

    px_re <- tryCatch(
      {
        proc_tbl %>%
          filter(PX_TYPE == "RE" & PX %in% TREATMENT_CODES$sct_revenue) %>%
          mutate(code_type = PX_TYPE) %>%
          group_by(code = PX, code_type) %>%
          summarise(n = n(), .groups = "drop") %>%
          collect() %>%
          mutate(source_table = "PROCEDURES", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(px_re))
  }

  # --- DIAGNOSIS ---
  dx_tbl <- safe_table("DIAGNOSIS")
  if (!is.null(dx_tbl)) {
    dx_codes <- tryCatch(
      {
        dx_tbl %>%
          filter(DX_TYPE == "10" & DX %in% TREATMENT_CODES$sct_dx_icd10) %>%
          mutate(code_type = DX_TYPE) %>%
          group_by(code = DX, code_type) %>%
          summarise(n = n(), .groups = "drop") %>%
          collect() %>%
          mutate(source_table = "DIAGNOSIS", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(dx_codes))
  }

  # --- ENCOUNTER (DRG) ---
  enc_tbl <- safe_table("ENCOUNTER")
  if (!is.null(enc_tbl)) {
    enc_codes <- tryCatch(
      {
        enc_tbl %>%
          filter(DRG %in% TREATMENT_CODES$sct_drg) %>%
          group_by(code = DRG) %>%
          summarise(n = n(), .groups = "drop") %>%
          collect() %>%
          mutate(source_table = "ENCOUNTER", code_type = "DRG", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(enc_codes))
  }

  # --- TUMOR_REGISTRY (date evidence only) ---
  tr_tbl <- safe_table("TUMOR_REGISTRY_ALL")
  if (!is.null(tr_tbl)) {
    tr_codes <- tryCatch(
      {
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
              n = as.integer(tr_count$n[1]),
              drug_name = NA_character_
            )
          } else {
            empty_result()
          }
        } else {
          empty_result()
        }
      },
      error = function(e) empty_result()
    )
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
#' @return Tibble with columns: code, code_type, source_table, n, drug_name, treatment_type
extract_immunotherapy_codes <- function() {
  message("  Extracting immunotherapy codes...")
  results <- list()

  # --- PROCEDURES: ICD-10-PCS prefix match for CAR T-cell ---
  proc_tbl <- safe_table("PROCEDURES")
  if (!is.null(proc_tbl)) {
    cart_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$cart_icd10pcs_prefixes, collapse = "|"), ")")
    px_10 <- tryCatch(
      {
        proc_tbl %>%
          filter(PX_TYPE == "10") %>%
          materialize() %>%
          filter(str_detect(PX, cart_icd10pcs_rx)) %>%
          mutate(code_type = "10") %>%
          group_by(code = PX, code_type) %>%
          summarise(n = n(), .groups = "drop") %>%
          mutate(source_table = "PROCEDURES", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(px_10))
  }

  # --- ENCOUNTER (DRG 018 = BMT with CAR T-cell) ---
  enc_tbl <- safe_table("ENCOUNTER")
  if (!is.null(enc_tbl)) {
    enc_codes <- tryCatch(
      {
        enc_tbl %>%
          filter(DRG %in% c("018")) %>%
          group_by(code = DRG) %>%
          summarise(n = n(), .groups = "drop") %>%
          collect() %>%
          mutate(source_table = "ENCOUNTER", code_type = "DRG", drug_name = NA_character_)
      },
      error = function(e) empty_result()
    )
    results <- c(results, list(enc_codes))
  }

  bind_rows(results) %>%
    mutate(treatment_type = "Immunotherapy")
}

# SECTION 5: UNKNOWN CODE DETECTION ----

#' Detect unknown treatment-adjacent codes not in TREATMENT_CODES lists
#'
#' Uses CPT/HCPCS range heuristics (CPT_HCPCS_RANGES) to find codes in
#' PROCEDURES that match broad treatment code families but are NOT in our
#' curated TREATMENT_CODES lists. Flags these as "Unmatched" for review.
#'
#' @param treatment_type Character. One of TREATMENT_SHEET_ORDER values.
#' @return Tibble with columns: code, code_type, source_table, n, drug_name, treatment_type
detect_unknown_codes <- function(treatment_type) {
  range_patterns <- CPT_HCPCS_RANGES[[treatment_type]]
  if (is.null(range_patterns)) {
    return(tibble(
      code = character(), code_type = character(),
      source_table = character(), n = integer(),
      drug_name = character(), treatment_type = character()
    ))
  }

  combined_regex <- paste(unlist(range_patterns), collapse = "|")

  # Build list of ALL known codes for this treatment type and determine PX_TYPE
  code_info <- switch(treatment_type,
    "Chemotherapy" = list(
      codes = c(
        TREATMENT_CODES$chemo_hcpcs, TREATMENT_CODES$chemo_icd9,
        TREATMENT_CODES$chemo_revenue,
        if (!is.null(TREATMENT_CODES$supportive_care_hcpcs)) TREATMENT_CODES$supportive_care_hcpcs
      ),
      px_type = "CH"
    ),
    "Radiation" = list(
      codes = c(
        TREATMENT_CODES$radiation_cpt, TREATMENT_CODES$radiation_icd9,
        TREATMENT_CODES$radiation_revenue
      ),
      px_type = "CH"
    ),
    "SCT" = list(
      codes = c(
        TREATMENT_CODES$sct_cpt, TREATMENT_CODES$sct_hcpcs,
        TREATMENT_CODES$sct_icd9, TREATMENT_CODES$sct_revenue
      ),
      px_type = "CH"
    ),
    "Immunotherapy" = list(
      codes = unlist(TREATMENT_CODES$cart_icd10pcs_prefixes),
      px_type = "10" # CAR T uses ICD-10-PCS, not CPT/HCPCS
    )
  )

  known_codes <- code_info$codes
  px_type_filter <- code_info$px_type

  proc_tbl <- safe_table("PROCEDURES")
  if (is.null(proc_tbl)) {
    return(tibble(
      code = character(), code_type = character(),
      source_table = character(), n = integer(),
      drug_name = character(), treatment_type = character()
    ))
  }

  tryCatch(
    {
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
          drug_name = NA_character_,
          treatment_type = treatment_type
        )
    },
    error = function(e) {
      message(glue("  Warning: Unknown code detection failed for {treatment_type}: {e$message}"))
      tibble(
        code = character(), code_type = character(),
        source_table = character(), n = integer(),
        drug_name = character(), treatment_type = character()
      )
    }
  )
}

# SECTION 6: XLSX WRITING FUNCTIONS ----

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
  wb$add_data(
    sheet = sheet_name, x = "Treatment Inventory by Source Table",
    start_row = 1, start_col = 1
  )
  wb$add_font(
    sheet = sheet_name, dims = "A1",
    name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
  )
  wb$merge_cells(sheet = sheet_name, dims = "A1:F1")

  # --- Row 2: Subtitle ---
  subtitle <- if (treatment_type == "Chemotherapy") {
    "All drugs for HL patients (PRESCRIBING/DISPENSING/MED_ADMIN) + chemo procedure codes by PCORnet table."
  } else {
    glue("Counts and percentages of {treatment_type} codes by PCORnet table.")
  }
  wb$add_data(
    sheet = sheet_name, x = as.character(subtitle),
    start_row = 2, start_col = 1
  )
  wb$add_font(
    sheet = sheet_name, dims = "A2",
    name = "Calibri", size = 10, color = wb_color("FF6B7280")
  )
  wb$merge_cells(sheet = sheet_name, dims = "A2:F2")

  # --- Row 3: blank ---

  # --- Row 4: Section header "By Source Table" ---
  wb$add_data(
    sheet = sheet_name, x = "By Source Table",
    start_row = 4, start_col = 1
  )
  wb$add_font(
    sheet = sheet_name, dims = "A4",
    name = "Calibri", size = 12, bold = TRUE, color = wb_color("FF1F2937")
  )

  # --- Row 5: Summary column headers ---
  summary_headers <- c("Source Table", "Code Type", "Count", "% of Total")
  for (i in seq_along(summary_headers)) {
    wb$add_data(
      sheet = sheet_name, x = summary_headers[i],
      start_row = 5, start_col = i
    )
  }
  wb$add_fill(sheet = sheet_name, dims = "A5:D5", color = wb_color("FF374151"))
  wb$add_font(
    sheet = sheet_name, dims = "A5:D5",
    name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
  )

  # --- Rows 6+: Summary data (bulk write) ---
  current_row <- 6
  if (nrow(df_summary) > 0) {
    summary_df <- data.frame(
      Source_Table = df_summary$source_table,
      Code_Type = df_summary$code_type,
      Count = df_summary$n,
      Pct = df_summary$pct,
      stringsAsFactors = FALSE
    )
    wb$add_data(
      sheet = sheet_name, x = summary_df,
      start_row = current_row, col_names = FALSE
    )

    last_summary_row <- current_row + nrow(df_summary) - 1
    # Source Table column: treatment-type colored pills (range-based)
    pill_dims <- glue("A{current_row}:A{last_summary_row}")
    wb$add_fill(sheet = sheet_name, dims = pill_dims, color = wb_color(fill_color))
    wb$add_font(
      sheet = sheet_name, dims = pill_dims,
      name = "Calibri", size = 11, bold = TRUE, color = wb_color(font_color)
    )
    # Number formats (range-based)
    wb$add_numfmt(sheet = sheet_name, dims = glue("C{current_row}:C{last_summary_row}"), numfmt = "#,##0")
    wb$add_numfmt(sheet = sheet_name, dims = glue("D{current_row}:D{last_summary_row}"), numfmt = "0.00%")

    current_row <- current_row + nrow(df_summary)
  }

  # --- Summary total row ---
  total_n <- sum(df_summary$n, na.rm = TRUE)
  wb$add_data(
    sheet = sheet_name, x = "Total",
    start_row = current_row, start_col = 1
  )
  wb$add_data(
    sheet = sheet_name, x = total_n,
    start_row = current_row, start_col = 3
  )
  wb$add_data(
    sheet = sheet_name, x = 1.0,
    start_row = current_row, start_col = 4
  )

  total_dims <- glue("A{current_row}:D{current_row}")
  wb$add_fill(sheet = sheet_name, dims = total_dims, color = wb_color("FF374151"))
  wb$add_font(
    sheet = sheet_name, dims = total_dims,
    name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
  )
  wb$add_numfmt(sheet = sheet_name, dims = glue("C{current_row}"), numfmt = "#,##0")
  wb$add_numfmt(sheet = sheet_name, dims = glue("D{current_row}"), numfmt = "0.00%")

  current_row <- current_row + 1 # blank row
  current_row <- current_row + 1

  # --- Section header "Detailed Codes" ---
  wb$add_data(
    sheet = sheet_name, x = "Detailed Codes",
    start_row = current_row, start_col = 1
  )
  wb$add_font(
    sheet = sheet_name, dims = glue("A{current_row}"),
    name = "Calibri", size = 12, bold = TRUE, color = wb_color("FF1F2937")
  )
  current_row <- current_row + 1

  # --- Detail header row ---
  detail_header_row <- current_row
  detail_headers <- c("Code", "Code Type", "Drug Name", "Source Table", "Count", "% of Total")
  for (i in seq_along(detail_headers)) {
    wb$add_data(
      sheet = sheet_name, x = detail_headers[i],
      start_row = detail_header_row, start_col = i
    )
  }
  detail_header_dims <- glue("A{detail_header_row}:F{detail_header_row}")
  wb$add_fill(sheet = sheet_name, dims = detail_header_dims, color = wb_color("FF374151"))
  wb$add_font(
    sheet = sheet_name, dims = detail_header_dims,
    name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
  )
  current_row <- current_row + 1

  # --- Detail data rows (bulk write for performance) ---
  detail_total <- sum(df_codes$n, na.rm = TRUE)
  if (nrow(df_codes) > 0) {
    detail_df <- data.frame(
      Code = df_codes$code,
      Code_Type = df_codes$code_type,
      Drug_Name = ifelse(is.na(df_codes$drug_name), "", df_codes$drug_name),
      Source_Table = df_codes$source_table,
      Count = df_codes$n,
      Pct = if (detail_total > 0) df_codes$n / detail_total else rep(0, nrow(df_codes)),
      stringsAsFactors = FALSE
    )
    wb$add_data(
      sheet = sheet_name, x = detail_df,
      start_row = current_row, col_names = FALSE
    )

    last_detail_row <- current_row + nrow(df_codes) - 1
    # Range-based formatting (not per-row)
    code_dims <- glue("A{current_row}:A{last_detail_row}")
    wb$add_font(
      sheet = sheet_name, dims = code_dims,
      name = "Calibri", size = 10, bold = TRUE, color = wb_color("FF374151")
    )
    body_dims <- glue("B{current_row}:D{last_detail_row}")
    wb$add_font(
      sheet = sheet_name, dims = body_dims,
      name = "Calibri", size = 10, color = wb_color("FF111827")
    )
    wb$add_numfmt(sheet = sheet_name, dims = glue("E{current_row}:E{last_detail_row}"), numfmt = "#,##0")
    wb$add_numfmt(sheet = sheet_name, dims = glue("F{current_row}:F{last_detail_row}"), numfmt = "0.00%")

    current_row <- current_row + nrow(df_codes)
  }

  # --- Unmatched codes section (if any) ---
  if (nrow(df_unmatched) > 0) {
    current_row <- current_row + 1 # blank row

    # Section header: "Unmatched Codes (Heuristic Detection)"
    wb$add_data(
      sheet = sheet_name, x = "Unmatched Codes (Heuristic Detection)",
      start_row = current_row, start_col = 1
    )
    wb$add_font(
      sheet = sheet_name, dims = glue("A{current_row}"),
      name = "Calibri", size = 12, bold = TRUE, color = wb_color("FF1F2937")
    )
    current_row <- current_row + 1

    # Unmatched header row
    for (i in seq_along(detail_headers)) {
      wb$add_data(
        sheet = sheet_name, x = detail_headers[i],
        start_row = current_row, start_col = i
      )
    }
    unmatched_header_dims <- glue("A{current_row}:F{current_row}")
    wb$add_fill(sheet = sheet_name, dims = unmatched_header_dims, color = wb_color("FF374151"))
    wb$add_font(
      sheet = sheet_name, dims = unmatched_header_dims,
      name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
    )
    current_row <- current_row + 1

    # Unmatched data rows (bulk write)
    unmatched_total <- sum(df_unmatched$n, na.rm = TRUE)
    unmatched_df <- data.frame(
      Code = df_unmatched$code,
      Code_Type = df_unmatched$code_type,
      Drug_Name = ifelse(is.na(df_unmatched$drug_name), "", df_unmatched$drug_name),
      Source_Table = df_unmatched$source_table,
      Count = df_unmatched$n,
      Pct = if (unmatched_total > 0) df_unmatched$n / unmatched_total else rep(0, nrow(df_unmatched)),
      stringsAsFactors = FALSE
    )
    wb$add_data(
      sheet = sheet_name, x = unmatched_df,
      start_row = current_row, col_names = FALSE
    )

    last_unmatched_row <- current_row + nrow(df_unmatched) - 1
    wb$add_font(
      sheet = sheet_name, dims = glue("A{current_row}:A{last_unmatched_row}"),
      name = "Calibri", size = 10, bold = TRUE, color = wb_color("FF374151")
    )
    wb$add_font(
      sheet = sheet_name, dims = glue("B{current_row}:D{last_unmatched_row}"),
      name = "Calibri", size = 10, color = wb_color("FF111827")
    )
    wb$add_numfmt(sheet = sheet_name, dims = glue("E{current_row}:E{last_unmatched_row}"), numfmt = "#,##0")
    wb$add_numfmt(sheet = sheet_name, dims = glue("F{current_row}:F{last_unmatched_row}"), numfmt = "0.00%")
    current_row <- current_row + nrow(df_unmatched)
  }

  # --- Final total row (TOTAL_FILL) ---
  grand_total <- sum(df_codes$n, na.rm = TRUE) + sum(df_unmatched$n, na.rm = TRUE)
  wb$add_data(
    sheet = sheet_name, x = "TOTAL",
    start_row = current_row, start_col = 1
  )
  wb$add_data(
    sheet = sheet_name, x = grand_total,
    start_row = current_row, start_col = 5
  )
  wb$add_data(
    sheet = sheet_name, x = 1.0,
    start_row = current_row, start_col = 6
  )

  total_dims <- glue("A{current_row}:F{current_row}")
  wb$add_fill(sheet = sheet_name, dims = total_dims, color = wb_color("FF1F2937"))
  wb$add_font(
    sheet = sheet_name, dims = total_dims,
    name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
  )
  wb$add_numfmt(sheet = sheet_name, dims = glue("E{current_row}"), numfmt = "#,##0")
  wb$add_numfmt(sheet = sheet_name, dims = glue("F{current_row}"), numfmt = "0.00%")

  # --- Freeze pane at first detail data row ---
  freeze_row <- detail_header_row + 1
  wb$freeze_pane(sheet = sheet_name, first_active_row = freeze_row)

  # --- Column widths ---
  wb$set_col_widths(sheet = sheet_name, cols = 1:6, widths = c(16, 14, 36, 20, 14, 14))

  invisible(wb)
}

# SECTION 7: MAIN EXECUTION ----

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
