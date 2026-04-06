# ==============================================================================
# 10_treatment_payer.R -- Treatment-anchored payer mode computation
# ==============================================================================
#
# For each of three treatment types (chemo, radiation, stem cell transplant),
# computes the payer mode within a +/-30 day window around the first treatment
# procedure date. Mirrors the PAYER_CATEGORY_AT_FIRST_DX pattern from
# 02_harmonize_payer.R Section 4c but anchors on treatment dates.
#
# Phase 9 expansion: Extracts dates from DIAGNOSIS (Z/V codes), ENCOUNTER (DRG),
# DISPENSING (RXNORM), MED_ADMIN (RXNORM), and PROCEDURES revenue codes in
# addition to existing PROCEDURES CPT/ICD and PRESCRIBING sources.
#
# Per D-01: Anchors on PX_DATE from PROCEDURES table (not TUMOR_REGISTRY)
# Per D-02: Includes PX_TYPE "CH" (CPT/HCPCS), "09" (ICD-9-CM), "10" (ICD-10-PCS)
# Per D-03: Chemo also uses RX_ORDER_DATE from PRESCRIBING for RXNORM matches
# Per D-05: Uses FIRST treatment date per patient per treatment type
# Per D-07: Uses CONFIG$analysis$treatment_window_days (= 30) for +/-30 day window
# Per D-09: DIAGNOSIS DX_DATE for Z51.*/V58.*/Z94.*/T86.* treatment codes
# Per D-10: ENCOUNTER ADMIT_DATE for MS-DRG 837-839, 846-849, 014-017
# Per D-11: Sets payer to NA when no encounters in window (left_join)
# Per D-11 (new): PROCEDURES PX_TYPE="RE" revenue code detection
# Per D-12: Logs match counts per treatment type; DISPENSING/MED_ADMIN RXNORM_CUI
#
# Dependencies:
#   - pcornet$PROCEDURES (via 01_load_pcornet.R) -- PX, PX_TYPE, PX_DATE, ID
#   - pcornet$PRESCRIBING (via 01_load_pcornet.R) -- RXNORM_CUI, RX_ORDER_DATE, ID
#   - encounters (via 02_harmonize_payer.R) -- ID, ADMIT_DATE, effective_payer, payer_category
#   - TREATMENT_CODES (via 00_config.R) -- all code lists
#   - CONFIG$analysis$treatment_window_days (via 00_config.R)
#   - PAYER_MAPPING$sentinel_values (via 00_config.R)
#
# Usage:
#   source("R/10_treatment_payer.R")  # After 02_harmonize_payer.R has run
#   chemo_result <- compute_payer_at_chemo()
#   rad_result <- compute_payer_at_radiation()
#   sct_result <- compute_payer_at_sct()
#
# ==============================================================================

library(dplyr)
library(stringr)
library(glue)
library(purrr)  # For compact() in multi-source date combination

# Helper: return nrow or 0 for NULL tibbles (for logging)
nrow_or_0 <- function(df) if (is.null(df)) 0L else nrow(df)

#' Compute payer mode within a temporal window around anchor dates
#'
#' Generic function that joins encounters to patient anchor dates,
#' filters to +/- window_days, and returns the mode payer_category.
#' Reuses the exact pattern from 02_harmonize_payer.R Section 4c.
#'
#' @param first_dates Tibble with columns: ID, anchor_date (Date)
#' @param window_days Integer, +/- days around anchor (default: CONFIG$analysis$treatment_window_days)
#' @param payer_col_name Character, name for output payer column
#' @return Tibble with columns: ID, {payer_col_name}
compute_payer_mode_in_window <- function(first_dates, window_days = CONFIG$analysis$treatment_window_days, payer_col_name = "PAYER_MODE") {
  # Detect the date column (the non-ID column) and rename to anchor_date
  date_col <- setdiff(names(first_dates), "ID")
  first_dates <- first_dates %>% rename(anchor_date = !!date_col[1])

  result <- encounters %>%
    filter(!is.na(effective_payer) &
           nchar(trimws(effective_payer)) > 0 &
           !effective_payer %in% PAYER_MAPPING$sentinel_values) %>%
    inner_join(first_dates, by = "ID") %>%
    mutate(days_from_treatment = as.numeric(ADMIT_DATE - anchor_date)) %>%
    filter(!is.na(days_from_treatment) & abs(days_from_treatment) <= window_days) %>%
    group_by(ID, payer_category) %>%
    summarise(n = n(), .groups = "drop") %>%
    arrange(ID, desc(n), payer_category) %>%
    group_by(ID) %>%
    slice(1) %>%
    ungroup() %>%
    select(ID, !!payer_col_name := payer_category)

  result
}

#' Compute payer mode at first chemotherapy procedure
#'
#' Extracts first chemo procedure dates from 6 source queries:
#'   - PROCEDURES CPT/HCPCS, ICD-9-CM, ICD-10-PCS, revenue (0331/0332/0335)
#'   - PRESCRIBING RXNORM
#'   - DIAGNOSIS Z51.11/Z51.12 (ICD-10), V58.11/V58.12 (ICD-9)
#'   - ENCOUNTER DRGs 837-839, 846-848
#'   - DISPENSING RXNORM_CUI
#'   - MED_ADMIN RXNORM_CUI
#'
#' Takes minimum date per patient across all sources, then computes payer mode
#' within +/-30 day window.
#'
#' @return Tibble with columns: ID, FIRST_CHEMO_DATE, PAYER_AT_CHEMO
compute_payer_at_chemo <- function() {
  # Extract chemo dates from PROCEDURES (CPT/HCPCS, ICD-9-CM, ICD-10-PCS, revenue) - consolidated query
  px_dates <- NULL
  if (!is.null(pcornet$PROCEDURES)) {
    px_dates <- pcornet$PROCEDURES %>%
      filter(
        (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) |
        (PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9) |
        (PX_TYPE == "10" & PX %in% TREATMENT_CODES$chemo_icd10pcs_prefixes) |
        (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$chemo_revenue)
      ) %>%
      filter(!is.na(PX_DATE)) %>%
      group_by(ID) %>%
      summarise(px_date = min(PX_DATE, na.rm = TRUE), .groups = "drop")
  }

  # Extract chemo dates from PRESCRIBING (RXNORM_CUI-filtered chemo drugs)
  # Previous version used ANY prescription date, inflating FIRST_CHEMO_DATE counts.
  # Now filters to TREATMENT_CODES$chemo_rxnorm before extracting dates.
  rx_dates <- NULL
  if (!is.null(pcornet$PRESCRIBING)) {
    rx_dates <- pcornet$PRESCRIBING %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      filter(!is.na(RX_ORDER_DATE) | !is.na(RX_START_DATE)) %>%
      mutate(rx_date_raw = coalesce(RX_ORDER_DATE, RX_START_DATE)) %>%
      filter(!is.na(rx_date_raw)) %>%
      group_by(ID) %>%
      summarise(rx_date = min(rx_date_raw, na.rm = TRUE), .groups = "drop")
  }

  # --- Phase 9: Expanded date extraction sources ---

  # DIAGNOSIS DX_DATE: Z51.11/Z51.12 (ICD-10), V58.11/V58.12 (ICD-9) per D-09
  dx_dates <- NULL
  if (!is.null(pcornet$DIAGNOSIS)) {
    dx_dates <- pcornet$DIAGNOSIS %>%
      filter(
        (DX_TYPE == "10" & DX %in% TREATMENT_CODES$chemo_dx_icd10) |
        (DX_TYPE == "09" & DX %in% TREATMENT_CODES$chemo_dx_icd9)
      ) %>%
      filter(!is.na(DX_DATE)) %>%
      group_by(ID) %>%
      summarise(dx_date = min(DX_DATE, na.rm = TRUE), .groups = "drop")
  }

  # ENCOUNTER ADMIT_DATE: DRGs 837-839, 846-848 per D-10
  drg_dates <- NULL
  if (!is.null(pcornet$ENCOUNTER)) {
    drg_dates <- pcornet$ENCOUNTER %>%
      filter(DRG %in% TREATMENT_CODES$chemo_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      group_by(ID) %>%
      summarise(drg_date = min(ADMIT_DATE, na.rm = TRUE), .groups = "drop")
  }

  # DISPENSING DISPENSE_DATE: RXNORM_CUI matching per D-12
  disp_dates <- NULL
  if (!is.null(pcornet$DISPENSING) && "RXNORM_CUI" %in% names(pcornet$DISPENSING)) {
    disp_dates <- pcornet$DISPENSING %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      filter(!is.na(DISPENSE_DATE)) %>%
      group_by(ID) %>%
      summarise(disp_date = min(DISPENSE_DATE, na.rm = TRUE), .groups = "drop")
  }

  # MED_ADMIN MEDADMIN_START_DATE: RXNORM_CUI matching per D-12
  ma_dates <- NULL
  if (!is.null(pcornet$MED_ADMIN) && "RXNORM_CUI" %in% names(pcornet$MED_ADMIN)) {
    ma_dates <- pcornet$MED_ADMIN %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      filter(!is.na(MEDADMIN_START_DATE)) %>%
      group_by(ID) %>%
      summarise(ma_date = min(MEDADMIN_START_DATE, na.rm = TRUE), .groups = "drop")
  }

  # Combine ALL date sources into single first-date-per-patient
  all_date_sources <- list(
    px_dates = px_dates, rx_dates = rx_dates, dx_dates = dx_dates,
    drg_dates = drg_dates, disp_dates = disp_dates, ma_dates = ma_dates
  )

  # Filter out NULLs and rename date columns to generic "src_date"
  non_null_sources <- compact(all_date_sources)

  if (length(non_null_sources) == 0) {
    message(glue("  Patients with chemo dates: 0"))
    message(glue("PAYER_AT_CHEMO: 0 matched, 0 no encounters in window (NA)"))
    return(tibble(ID = character(0), FIRST_CHEMO_DATE = as.Date(character(0)), PAYER_AT_CHEMO = character(0)))
  }

  # Stack all sources with generic date column, then take min per patient
  stacked <- bind_rows(
    lapply(non_null_sources, function(df) {
      date_col <- setdiff(names(df), "ID")
      df %>% rename(src_date = !!date_col[1]) %>% select(ID, src_date)
    })
  )

  first_dates <- stacked %>%
    group_by(ID) %>%
    summarise(FIRST_CHEMO_DATE = min(src_date, na.rm = TRUE), .groups = "drop") %>%
    filter(!is.infinite(FIRST_CHEMO_DATE))

  # Log source-level date counts
  message(glue("  Chemo date sources: PX={nrow_or_0(px_dates)}, RX={nrow_or_0(rx_dates)}, DX={nrow_or_0(dx_dates)}, DRG={nrow_or_0(drg_dates)}, DISP={nrow_or_0(disp_dates)}, MA={nrow_or_0(ma_dates)}"))
  message(glue("  Patients with chemo dates: {nrow(first_dates)}"))

  # Compute payer mode in window
  payer_result <- compute_payer_mode_in_window(first_dates, payer_col_name = "PAYER_AT_CHEMO")

  # Join back to get all patients with treatment dates, NA for no match
  result <- first_dates %>%
    left_join(payer_result, by = "ID")

  # Log match counts
  n_with_treatment <- nrow(result)
  n_matched <- sum(!is.na(result$PAYER_AT_CHEMO))
  n_no_match <- n_with_treatment - n_matched
  message(glue("PAYER_AT_CHEMO: {n_matched} matched, {n_no_match} no encounters in window (NA)"))

  result
}

#' Compute payer mode at first radiation therapy procedure
#'
#' Extracts first radiation dates from 3 source queries:
#'   - PROCEDURES CPT, ICD-9-CM, ICD-10-PCS, revenue (0330/0333)
#'   - DIAGNOSIS Z51.0 (ICD-10), V58.0 (ICD-9)
#'   - ENCOUNTER DRG 849
#'
#' Takes minimum date per patient across all sources, then computes payer mode
#' within +/-30 day window.
#'
#' @return Tibble with columns: ID, FIRST_RADIATION_DATE, PAYER_AT_RADIATION
compute_payer_at_radiation <- function() {
  # Extract radiation dates from PROCEDURES (CPT, ICD-9-CM, ICD-10-PCS, revenue) - consolidated query
  px_dates <- NULL
  if (!is.null(pcornet$PROCEDURES)) {
    px_dates <- pcornet$PROCEDURES %>%
      filter(
        (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$radiation_cpt) |
        (PX_TYPE == "09" & PX %in% TREATMENT_CODES$radiation_icd9) |
        (PX_TYPE == "10" & (
          str_starts(PX, "D70") |
          str_starts(PX, "D71") |
          str_starts(PX, "D72") |
          str_starts(PX, "D7Y")
        )) |
        (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$radiation_revenue)
      ) %>%
      filter(!is.na(PX_DATE)) %>%
      group_by(ID) %>%
      summarise(px_date = min(PX_DATE, na.rm = TRUE), .groups = "drop")
  }

  # --- Phase 9: Expanded date extraction sources ---

  # DIAGNOSIS DX_DATE: Z51.0 (ICD-10), V58.0 (ICD-9) per D-09
  dx_dates <- NULL
  if (!is.null(pcornet$DIAGNOSIS)) {
    dx_dates <- pcornet$DIAGNOSIS %>%
      filter(
        (DX_TYPE == "10" & DX %in% TREATMENT_CODES$radiation_dx_icd10) |
        (DX_TYPE == "09" & DX %in% TREATMENT_CODES$radiation_dx_icd9)
      ) %>%
      filter(!is.na(DX_DATE)) %>%
      group_by(ID) %>%
      summarise(dx_date = min(DX_DATE, na.rm = TRUE), .groups = "drop")
  }

  # ENCOUNTER ADMIT_DATE: DRG 849 per D-10
  drg_dates <- NULL
  if (!is.null(pcornet$ENCOUNTER)) {
    drg_dates <- pcornet$ENCOUNTER %>%
      filter(DRG %in% TREATMENT_CODES$radiation_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      group_by(ID) %>%
      summarise(drg_date = min(ADMIT_DATE, na.rm = TRUE), .groups = "drop")
  }

  # Combine ALL date sources
  all_date_sources <- list(
    px_dates = px_dates, dx_dates = dx_dates,
    drg_dates = drg_dates
  )

  non_null_sources <- compact(all_date_sources)

  if (length(non_null_sources) == 0) {
    message(glue("  Patients with radiation dates: 0"))
    message(glue("PAYER_AT_RADIATION: 0 matched, 0 no encounters in window (NA)"))
    return(tibble(ID = character(0), FIRST_RADIATION_DATE = as.Date(character(0)), PAYER_AT_RADIATION = character(0)))
  }

  stacked <- bind_rows(
    lapply(non_null_sources, function(df) {
      date_col <- setdiff(names(df), "ID")
      df %>% rename(src_date = !!date_col[1]) %>% select(ID, src_date)
    })
  )

  first_dates <- stacked %>%
    group_by(ID) %>%
    summarise(FIRST_RADIATION_DATE = min(src_date, na.rm = TRUE), .groups = "drop") %>%
    filter(!is.infinite(FIRST_RADIATION_DATE))

  message(glue("  Radiation date sources: PX={nrow_or_0(px_dates)}, DX={nrow_or_0(dx_dates)}, DRG={nrow_or_0(drg_dates)}"))
  message(glue("  Patients with radiation dates: {nrow(first_dates)}"))

  if (nrow(first_dates) == 0) {
    message(glue("PAYER_AT_RADIATION: 0 matched, 0 no encounters in window (NA)"))
    return(tibble(ID = character(0), FIRST_RADIATION_DATE = as.Date(character(0)), PAYER_AT_RADIATION = character(0)))
  }

  # Compute payer mode in window
  payer_result <- compute_payer_mode_in_window(first_dates, payer_col_name = "PAYER_AT_RADIATION")

  # Join back to get all patients with treatment dates, NA for no match
  result <- first_dates %>%
    left_join(payer_result, by = "ID")

  # Log match counts
  n_with_treatment <- nrow(result)
  n_matched <- sum(!is.na(result$PAYER_AT_RADIATION))
  n_no_match <- n_with_treatment - n_matched
  message(glue("PAYER_AT_RADIATION: {n_matched} matched, {n_no_match} no encounters in window (NA)"))

  result
}

#' Compute payer mode at first stem cell transplant procedure
#'
#' Extracts first SCT dates from 3 source queries:
#'   - PROCEDURES CPT/HCPCS (incl. S2140/S2142/S2150), ICD-9-CM, ICD-10-PCS, revenue (0362/0815)
#'   - DIAGNOSIS Z94.84/T86.5/T86.09/Z48.290/T86.0 (ICD-10 only)
#'   - ENCOUNTER DRGs 014, 016, 017
#'
#' Takes minimum date per patient across all sources, then computes payer mode
#' within +/-30 day window.
#'
#' @return Tibble with columns: ID, FIRST_SCT_DATE, PAYER_AT_SCT
compute_payer_at_sct <- function() {
  # Extract SCT dates from PROCEDURES (CPT/HCPCS, ICD-9-CM, ICD-10-PCS, revenue)
  px_dates <- NULL
  if (!is.null(pcornet$PROCEDURES)) {
    px_dates <- pcornet$PROCEDURES %>%
      filter(
        (PX_TYPE == "CH" & PX %in% c(TREATMENT_CODES$sct_cpt, TREATMENT_CODES$sct_hcpcs)) |
        (PX_TYPE == "09" & PX %in% TREATMENT_CODES$sct_icd9) |
        (PX_TYPE == "10" & PX %in% TREATMENT_CODES$sct_icd10pcs) |
        (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$sct_revenue)
      ) %>%
      filter(!is.na(PX_DATE)) %>%
      group_by(ID) %>%
      summarise(px_date = min(PX_DATE, na.rm = TRUE), .groups = "drop")
  }

  # --- Phase 9: Expanded date extraction sources ---

  # DIAGNOSIS DX_DATE: Z94.84/T86.5/T86.09/Z48.290/T86.0 (ICD-10 only) per D-09
  dx_dates <- NULL
  if (!is.null(pcornet$DIAGNOSIS)) {
    dx_dates <- pcornet$DIAGNOSIS %>%
      filter(DX_TYPE == "10" & DX %in% TREATMENT_CODES$sct_dx_icd10) %>%
      filter(!is.na(DX_DATE)) %>%
      group_by(ID) %>%
      summarise(dx_date = min(DX_DATE, na.rm = TRUE), .groups = "drop")
  }

  # ENCOUNTER ADMIT_DATE: DRGs 014, 016, 017 per D-10
  drg_dates <- NULL
  if (!is.null(pcornet$ENCOUNTER)) {
    drg_dates <- pcornet$ENCOUNTER %>%
      filter(DRG %in% TREATMENT_CODES$sct_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      group_by(ID) %>%
      summarise(drg_date = min(ADMIT_DATE, na.rm = TRUE), .groups = "drop")
  }

  # Combine ALL date sources
  all_date_sources <- list(
    px_dates = px_dates, dx_dates = dx_dates,
    drg_dates = drg_dates
  )

  non_null_sources <- compact(all_date_sources)

  if (length(non_null_sources) == 0) {
    message(glue("  Patients with SCT dates: 0"))
    message(glue("PAYER_AT_SCT: 0 matched, 0 no encounters in window (NA)"))
    return(tibble(ID = character(0), FIRST_SCT_DATE = as.Date(character(0)), PAYER_AT_SCT = character(0)))
  }

  stacked <- bind_rows(
    lapply(non_null_sources, function(df) {
      date_col <- setdiff(names(df), "ID")
      df %>% rename(src_date = !!date_col[1]) %>% select(ID, src_date)
    })
  )

  first_dates <- stacked %>%
    group_by(ID) %>%
    summarise(FIRST_SCT_DATE = min(src_date, na.rm = TRUE), .groups = "drop") %>%
    filter(!is.infinite(FIRST_SCT_DATE))

  message(glue("  SCT date sources: PX={nrow_or_0(px_dates)}, DX={nrow_or_0(dx_dates)}, DRG={nrow_or_0(drg_dates)}"))
  message(glue("  Patients with SCT dates: {nrow(first_dates)}"))

  if (nrow(first_dates) == 0) {
    message(glue("PAYER_AT_SCT: 0 matched, 0 no encounters in window (NA)"))
    return(tibble(ID = character(0), FIRST_SCT_DATE = as.Date(character(0)), PAYER_AT_SCT = character(0)))
  }

  # Compute payer mode in window
  payer_result <- compute_payer_mode_in_window(first_dates, payer_col_name = "PAYER_AT_SCT")

  # Join back to get all patients with treatment dates, NA for no match
  result <- first_dates %>%
    left_join(payer_result, by = "ID")

  # Log match counts
  n_with_treatment <- nrow(result)
  n_matched <- sum(!is.na(result$PAYER_AT_SCT))
  n_no_match <- n_with_treatment - n_matched
  message(glue("PAYER_AT_SCT: {n_matched} matched, {n_no_match} no encounters in window (NA)"))

  result
}

#' Compute last treatment date across all treatment types per patient
#'
#' Scans PROCEDURES, PRESCRIBING, DIAGNOSIS, ENCOUNTER, DISPENSING, and MED_ADMIN
#' for the latest treatment date (max across chemo, radiation, SCT) per patient.
#' Filters 1900 sentinel dates. Used by 04_build_cohort.R for HAS_POST_TX_ENCOUNTERS.
#'
#' @return Tibble with columns: ID, LAST_ANY_TX_DATE
compute_last_any_treatment_date <- function() {

  # Helper: extract max treatment dates for one type from all available sources
  last_dates_for_type <- function(treatment_type) {
    sources <- list()

    if (treatment_type == "chemo") {
      if (!is.null(pcornet$PROCEDURES)) {
        sources$px <- pcornet$PROCEDURES %>%
          filter(
            (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) |
            (PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9) |
            (PX_TYPE == "10" & PX %in% TREATMENT_CODES$chemo_icd10pcs_prefixes) |
            (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$chemo_revenue)
          ) %>% filter(!is.na(PX_DATE)) %>%
          group_by(ID) %>% summarise(tx_date = max(PX_DATE, na.rm = TRUE), .groups = "drop")
      }
      if (!is.null(pcornet$PRESCRIBING)) {
        sources$rx <- pcornet$PRESCRIBING %>%
          filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
          mutate(d = coalesce(RX_ORDER_DATE, RX_START_DATE)) %>%
          filter(!is.na(d)) %>%
          group_by(ID) %>% summarise(tx_date = max(d, na.rm = TRUE), .groups = "drop")
      }
      if (!is.null(pcornet$DIAGNOSIS)) {
        sources$dx <- pcornet$DIAGNOSIS %>%
          filter(
            (DX_TYPE == "10" & DX %in% TREATMENT_CODES$chemo_dx_icd10) |
            (DX_TYPE == "09" & DX %in% TREATMENT_CODES$chemo_dx_icd9)
          ) %>% filter(!is.na(DX_DATE)) %>%
          group_by(ID) %>% summarise(tx_date = max(DX_DATE, na.rm = TRUE), .groups = "drop")
      }
      if (!is.null(pcornet$ENCOUNTER)) {
        sources$drg <- pcornet$ENCOUNTER %>%
          filter(DRG %in% TREATMENT_CODES$chemo_drg) %>% filter(!is.na(ADMIT_DATE)) %>%
          group_by(ID) %>% summarise(tx_date = max(ADMIT_DATE, na.rm = TRUE), .groups = "drop")
      }
      if (!is.null(pcornet$DISPENSING) && "RXNORM_CUI" %in% names(pcornet$DISPENSING)) {
        sources$disp <- pcornet$DISPENSING %>%
          filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>% filter(!is.na(DISPENSE_DATE)) %>%
          group_by(ID) %>% summarise(tx_date = max(DISPENSE_DATE, na.rm = TRUE), .groups = "drop")
      }
      if (!is.null(pcornet$MED_ADMIN) && "RXNORM_CUI" %in% names(pcornet$MED_ADMIN)) {
        sources$ma <- pcornet$MED_ADMIN %>%
          filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>% filter(!is.na(MEDADMIN_START_DATE)) %>%
          group_by(ID) %>% summarise(tx_date = max(MEDADMIN_START_DATE, na.rm = TRUE), .groups = "drop")
      }

    } else if (treatment_type == "radiation") {
      if (!is.null(pcornet$PROCEDURES)) {
        sources$px <- pcornet$PROCEDURES %>%
          filter(
            (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$radiation_cpt) |
            (PX_TYPE == "09" & PX %in% TREATMENT_CODES$radiation_icd9) |
            (PX_TYPE == "10" & (
              str_starts(PX, "D70") | str_starts(PX, "D71") |
              str_starts(PX, "D72") | str_starts(PX, "D7Y")
            )) |
            (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$radiation_revenue)
          ) %>% filter(!is.na(PX_DATE)) %>%
          group_by(ID) %>% summarise(tx_date = max(PX_DATE, na.rm = TRUE), .groups = "drop")
      }
      if (!is.null(pcornet$DIAGNOSIS)) {
        sources$dx <- pcornet$DIAGNOSIS %>%
          filter(
            (DX_TYPE == "10" & DX %in% TREATMENT_CODES$radiation_dx_icd10) |
            (DX_TYPE == "09" & DX %in% TREATMENT_CODES$radiation_dx_icd9)
          ) %>% filter(!is.na(DX_DATE)) %>%
          group_by(ID) %>% summarise(tx_date = max(DX_DATE, na.rm = TRUE), .groups = "drop")
      }
      if (!is.null(pcornet$ENCOUNTER)) {
        sources$drg <- pcornet$ENCOUNTER %>%
          filter(DRG %in% TREATMENT_CODES$radiation_drg) %>% filter(!is.na(ADMIT_DATE)) %>%
          group_by(ID) %>% summarise(tx_date = max(ADMIT_DATE, na.rm = TRUE), .groups = "drop")
      }

    } else if (treatment_type == "sct") {
      if (!is.null(pcornet$PROCEDURES)) {
        sources$px <- pcornet$PROCEDURES %>%
          filter(
            (PX_TYPE == "CH" & PX %in% c(TREATMENT_CODES$sct_cpt, TREATMENT_CODES$sct_hcpcs)) |
            (PX_TYPE == "09" & PX %in% TREATMENT_CODES$sct_icd9) |
            (PX_TYPE == "10" & PX %in% TREATMENT_CODES$sct_icd10pcs) |
            (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$sct_revenue)
          ) %>% filter(!is.na(PX_DATE)) %>%
          group_by(ID) %>% summarise(tx_date = max(PX_DATE, na.rm = TRUE), .groups = "drop")
      }
      if (!is.null(pcornet$DIAGNOSIS)) {
        sources$dx <- pcornet$DIAGNOSIS %>%
          filter(DX_TYPE == "10" & DX %in% TREATMENT_CODES$sct_dx_icd10) %>%
          filter(!is.na(DX_DATE)) %>%
          group_by(ID) %>% summarise(tx_date = max(DX_DATE, na.rm = TRUE), .groups = "drop")
      }
      if (!is.null(pcornet$ENCOUNTER)) {
        sources$drg <- pcornet$ENCOUNTER %>%
          filter(DRG %in% TREATMENT_CODES$sct_drg) %>% filter(!is.na(ADMIT_DATE)) %>%
          group_by(ID) %>% summarise(tx_date = max(ADMIT_DATE, na.rm = TRUE), .groups = "drop")
      }
    }

    non_null <- compact(sources)
    if (length(non_null) == 0) return(tibble(ID = character(0), tx_date = as.Date(character(0))))

    bind_rows(non_null) %>%
      group_by(ID) %>%
      summarise(tx_date = max(tx_date, na.rm = TRUE), .groups = "drop") %>%
      filter(!is.infinite(tx_date))
  }

  # Combine all treatment types, take overall max per patient
  all_dates <- bind_rows(
    last_dates_for_type("chemo"),
    last_dates_for_type("radiation"),
    last_dates_for_type("sct")
  )

  if (nrow(all_dates) == 0) {
    message("  LAST_ANY_TX_DATE: 0 patients (no treatment evidence found)")
    return(tibble(ID = character(0), LAST_ANY_TX_DATE = as.Date(character(0))))
  }

  result <- all_dates %>%
    filter(tx_date > as.Date("1900-12-31")) %>%
    group_by(ID) %>%
    summarise(LAST_ANY_TX_DATE = max(tx_date, na.rm = TRUE), .groups = "drop") %>%
    filter(!is.infinite(LAST_ANY_TX_DATE))

  message(glue("  LAST_ANY_TX_DATE: {nrow(result)} patients with treatment"))
  result
}

# ==============================================================================
# End of 10_treatment_payer.R
# ==============================================================================
