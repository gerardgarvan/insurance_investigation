# ==============================================================================
# utils/utils_treatment.R -- Shared treatment analysis helpers
# ==============================================================================
#
# Purpose:
#   Shared treatment analysis helpers. Provides safe_table(), get_hl_patient_ids(),
#   and empty_result() for treatment pipeline scripts. safe_table() wraps
#   get_pcornet_table() with null-guard for missing tables (returns NULL instead
#   of error). get_hl_patient_ids() queries DIAGNOSIS for HL cohort. empty_result()
#   returns zero-row tibble matching code inventory schema for graceful handling
#   of missing data sources.
#
# Inputs:
#   - None (utility function library, not a standalone script)
#
# Outputs:
#   - None (defines functions loaded into calling scripts' environment)
#
# Dependencies:
#   - dplyr: Data manipulation for HL patient ID query
#   - tibble: empty_result() tibble creation
#   - glue: String formatting for messages
#
# Requirements: N/A (utility module)
#
# ==============================================================================

#' Safely access a PCORnet table with null-guard
#'
#' Wraps get_pcornet_table() in tryCatch to handle missing tables gracefully.
#' Returns NULL (not an error) when a table doesn't exist.
#'
#' @param name Character. PCORnet table name (e.g., "PROCEDURES", "DISPENSING")
#' @return A dplyr-compatible object (tibble or tbl_dbi), or NULL if not found
safe_table <- function(name) {
  tryCatch(
    get_pcornet_table(name),
    error = function(e) {
      message(glue::glue("  Table {name} not found; skipping"))
      NULL
    }
  )
}

#' Create empty result tibble for missing tables
#'
#' Returns a zero-row tibble matching the standard code inventory schema.
#' @return Tibble with columns: code, code_type, source_table, n, drug_name
empty_result <- function() {
  tibble::tibble(
    code = character(), code_type = character(), source_table = character(),
    n = integer(), drug_name = character()
  )
}

#' Get patient IDs with a Hodgkin Lymphoma diagnosis
#'
#' Queries DIAGNOSIS table for any patient with an HL ICD-10 or ICD-9 code.
#' Used to pull ALL drugs for HL patients (not just curated TREATMENT_CODES).
#'
#' @return Character vector of unique patient IDs
get_hl_patient_ids <- function() {
  dx_tbl <- safe_table("DIAGNOSIS")
  if (is.null(dx_tbl)) {
    message("  Warning: DIAGNOSIS table not found, cannot identify HL patients")
    return(character(0))
  }

  tryCatch(
    {
      hl_ids <- dx_tbl %>%
        dplyr::filter(
          (DX_TYPE == "10" & DX %in% ICD_CODES$hl_icd10) |
            (DX_TYPE == "09" & DX %in% ICD_CODES$hl_icd9)
        ) %>%
        dplyr::select(ID) %>%
        dplyr::distinct() %>%
        dplyr::collect() %>%
        dplyr::pull(ID)
      message(glue::glue("  Found {format(length(hl_ids), big.mark = ',')} patients with HL diagnosis"))
      hl_ids
    },
    error = function(e) {
      message(glue::glue("  Warning: HL patient lookup failed: {e$message}"))
      character(0)
    }
  )
}

#' Helper: return nrow or 0 for NULL tibbles (for logging)
#' @param df A data frame or NULL
#' @return Integer row count (0 if NULL)
nrow_or_0 <- function(df) if (is.null(df)) 0L else nrow(df)

#' Verify output file exists and log size
#'
#' Checks if a file exists and prints formatted size message.
#' Used for post-run verification of RDS/XLSX outputs.
#'
#' @param path Character. File path to check
#' @param label Character. Human-readable label for the file
check_file <- function(path, label) {
  if (file.exists(path)) {
    sz <- file.size(path)
    message(glue("  OK: {label} ({round(sz/1024, 1)} KB)"))
  } else {
    message(glue("  MISSING: {label}"))
  }
}

# ==============================================================================
# D-12 revised Phase 122: MED_ADMIN / DISPENSING chemo detection helpers
# ==============================================================================

#' Normalize an NDC code to 11-digit no-hyphen format
#'
#' Strips hyphens and left-pads with zeros to produce the standard 11-digit
#' NDC string required for RxNav API lookups and crosswalk key matching.
#' Vectorized — safe to apply to a column.
#'
#' @param ndc Character vector of NDC codes (hyphenated or plain)
#' @return Character vector of 11-digit no-hyphen NDC strings
normalize_ndc <- function(ndc) {
  stringr::str_remove_all(ndc, "-") |>
    stringr::str_pad(width = 11, side = "left", pad = "0")
}

#' Load NDC->RxNorm crosswalk from data/reference/ndc_rxnorm_crosswalk.rds
#'
#' Returns named character vector (NDC -> RxCUI) or empty vector with message.
#' Named vector allows O(1) lookup: rxcui <- crosswalk[ndc_value].
#' If the file is absent (crosswalk not yet built on HiPerGator), degrades
#' gracefully — never crashes. Callers must handle character(0) return.
#'
#' @return Named character vector (NDC -> RxCUI) or character(0)
load_ndc_crosswalk <- function() {
  path <- here::here("data", "reference", "ndc_rxnorm_crosswalk.rds")
  if (!file.exists(path)) {
    message("  NDC->RxNorm crosswalk not found at ", path,
            " — NDC-coded rows will NOT contribute to chemo detection.")
    message("  Run R/108_build_ndc_rxnorm_crosswalk.R on HiPerGator to build it.")
    return(character(0))
  }
  cw <- readRDS(path)
  message(glue::glue("  NDC crosswalk loaded: {length(cw)} NDC->RxCUI mappings"))
  cw
}

#' Extract chemo-matching rows from a single PCORnet medication table
#'
#' Returns a tibble of (ID, treatment_date, triggering_code) for chemo hits,
#' or NULL with a message if the table or required columns are absent.
#'
#' ENCOUNTERID intentionally omitted; callers add it if the source has it.
#' (DISPENSING may lack ENCOUNTERID in this extract; omitting keeps the
#' helper contract consistent across all three tables.)
#'
#' @param table_name  "PRESCRIBING", "DISPENSING", or "MED_ADMIN"
#' @param chemo_rxnorm  Character vector of RxNorm CUIs (TREATMENT_CODES$chemo_rxnorm)
#' @param ndc_crosswalk Named character vector: NDC -> RxCUI, or NULL to skip NDC path
#'   (load via load_ndc_crosswalk(); NULL/character(0) both degrade gracefully)
#' @return Tibble(ID, treatment_date, triggering_code) with distinct rows, or NULL
get_chemo_hits <- function(table_name, chemo_rxnorm, ndc_crosswalk = NULL) {
  tbl <- safe_table(table_name)
  if (is.null(tbl)) {
    message(glue::glue("  [{table_name}] table not found — skipping chemo detection"))
    return(NULL)
  }

  if (table_name == "PRESCRIBING") {
    if (!"RXNORM_CUI" %in% colnames(tbl)) {
      message(glue::glue("  [PRESCRIBING] RXNORM_CUI absent — unexpected; skipping"))
      return(NULL)
    }
    tbl %>%
      dplyr::filter(RXNORM_CUI %in% chemo_rxnorm) %>%
      dplyr::mutate(treatment_date = dplyr::coalesce(RX_ORDER_DATE, RX_START_DATE)) %>%
      dplyr::filter(!is.na(treatment_date)) %>%
      dplyr::select(ID, treatment_date, triggering_code = RXNORM_CUI) %>%
      dplyr::collect() %>%
      dplyr::distinct(ID, treatment_date, triggering_code)

  } else if (table_name == "DISPENSING") {
    if (!"NDC" %in% colnames(tbl)) {
      message(glue::glue("  [DISPENSING] NDC column absent — skipping"))
      return(NULL)
    }
    if (is.null(ndc_crosswalk) || length(ndc_crosswalk) == 0) {
      message("  [DISPENSING] no NDC crosswalk loaded — skipping chemo match")
      return(NULL)
    }
    rows <- tbl %>%
      dplyr::filter(!is.na(NDC), !is.na(DISPENSE_DATE)) %>%
      dplyr::select(ID, treatment_date = DISPENSE_DATE, NDC) %>%
      dplyr::collect()
    rows %>%
      dplyr::mutate(rxcui = ndc_crosswalk[normalize_ndc(NDC)]) %>%
      dplyr::filter(!is.na(rxcui), rxcui %in% chemo_rxnorm) %>%
      dplyr::select(ID, treatment_date, triggering_code = rxcui) %>%
      dplyr::distinct(ID, treatment_date, triggering_code)

  } else if (table_name == "MED_ADMIN") {
    required <- c("MEDADMIN_TYPE", "MEDADMIN_CODE", "MEDADMIN_START_DATE")
    missing_cols <- required[!required %in% colnames(tbl)]
    if (length(missing_cols) > 0) {
      message(glue::glue(
        "  [MED_ADMIN] missing columns: {paste(missing_cols, collapse = ', ')} — skipping"
      ))
      return(NULL)
    }
    # RX-typed rows: MEDADMIN_CODE holds RxNorm CUI directly
    rx_hits <- tbl %>%
      dplyr::filter(
        MEDADMIN_TYPE == "RX",
        MEDADMIN_CODE %in% chemo_rxnorm,
        !is.na(MEDADMIN_START_DATE)
      ) %>%
      dplyr::select(ID, treatment_date = MEDADMIN_START_DATE,
                    triggering_code = MEDADMIN_CODE) %>%
      dplyr::collect() %>%
      dplyr::distinct(ID, treatment_date, triggering_code)
    # ND-typed rows: MEDADMIN_CODE holds NDC — needs crosswalk
    nd_hits <- NULL
    if (!is.null(ndc_crosswalk) && length(ndc_crosswalk) > 0) {
      nd_rows <- tbl %>%
        dplyr::filter(
          MEDADMIN_TYPE == "ND",
          !is.na(MEDADMIN_CODE),
          !is.na(MEDADMIN_START_DATE)
        ) %>%
        dplyr::select(ID, treatment_date = MEDADMIN_START_DATE,
                      NDC = MEDADMIN_CODE) %>%
        dplyr::collect()
      nd_hits <- nd_rows %>%
        dplyr::mutate(rxcui = ndc_crosswalk[normalize_ndc(NDC)]) %>%
        dplyr::filter(!is.na(rxcui), rxcui %in% chemo_rxnorm) %>%
        dplyr::select(ID, treatment_date, triggering_code = rxcui) %>%
        dplyr::distinct(ID, treatment_date, triggering_code)
    }
    dplyr::bind_rows(rx_hits, nd_hits)

  } else {
    message(glue::glue("  [{table_name}] unrecognised table for get_chemo_hits() — skipping"))
    NULL
  }
}
