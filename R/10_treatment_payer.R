# ==============================================================================
# 10_treatment_payer.R -- Treatment-anchored payer mode computation
# ==============================================================================
#
# For each of three treatment types (chemo, radiation, stem cell transplant),
# computes the payer mode within a +/-30 day window around the first treatment
# procedure date. Mirrors the PAYER_CATEGORY_AT_FIRST_DX pattern from
# 02_harmonize_payer.R Section 4c but anchors on treatment dates.
#
# Per D-01: Anchors on PX_DATE from PROCEDURES table (not TUMOR_REGISTRY)
# Per D-02: Includes PX_TYPE "CH" (CPT/HCPCS), "09" (ICD-9-CM), "10" (ICD-10-PCS)
# Per D-03: Chemo also uses RX_ORDER_DATE from PRESCRIBING for RXNORM matches
# Per D-05: Uses FIRST treatment date per patient per treatment type
# Per D-07: Uses CONFIG$analysis$treatment_window_days (= 30) for +/-30 day window
# Per D-11: Sets payer to NA when no encounters in window (left_join)
# Per D-12: Logs match counts per treatment type
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
#' Extracts first chemo procedure dates from PROCEDURES (CPT/HCPCS, ICD-9-CM, ICD-10-PCS)
#' and PRESCRIBING (RXNORM), then computes payer mode within +/-30 day window.
#'
#' Per D-03: Chemo uses BOTH PROCEDURES and PRESCRIBING sources.
#'
#' @return Tibble with columns: ID, FIRST_CHEMO_DATE, PAYER_AT_CHEMO
compute_payer_at_chemo <- function() {
  # Extract chemo dates from PROCEDURES
  px_dates <- NULL
  if (!is.null(pcornet$PROCEDURES)) {
    px_dates <- pcornet$PROCEDURES %>%
      filter(
        (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) |
        (PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9) |
        (PX_TYPE == "10" & PX %in% TREATMENT_CODES$chemo_icd10pcs_prefixes)
      ) %>%
      filter(!is.na(PX_DATE)) %>%
      group_by(ID) %>%
      summarise(px_date = min(PX_DATE, na.rm = TRUE), .groups = "drop")
  }

  # Extract chemo dates from PRESCRIBING
  rx_dates <- NULL
  if (!is.null(pcornet$PRESCRIBING)) {
    rx_dates <- pcornet$PRESCRIBING %>%
      filter(!is.na(RXNORM_CUI) & RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      filter(!is.na(RX_ORDER_DATE)) %>%
      group_by(ID) %>%
      summarise(rx_date = min(RX_ORDER_DATE, na.rm = TRUE), .groups = "drop")
  }

  # Combine PROCEDURES and PRESCRIBING dates
  if (!is.null(px_dates) && !is.null(rx_dates)) {
    first_dates <- full_join(px_dates, rx_dates, by = "ID") %>%
      rowwise() %>%
      mutate(FIRST_CHEMO_DATE = min(c(px_date, rx_date), na.rm = TRUE)) %>%
      ungroup() %>%
      select(ID, FIRST_CHEMO_DATE)
  } else if (!is.null(px_dates)) {
    first_dates <- px_dates %>%
      rename(FIRST_CHEMO_DATE = px_date)
  } else if (!is.null(rx_dates)) {
    first_dates <- rx_dates %>%
      rename(FIRST_CHEMO_DATE = rx_date)
  } else {
    # No chemo dates found
    message(glue("  Patients with chemo procedure dates: 0"))
    message(glue("PAYER_AT_CHEMO: 0 matched, 0 no encounters in window (NA)"))
    return(tibble(ID = character(0), FIRST_CHEMO_DATE = as.Date(character(0)), PAYER_AT_CHEMO = character(0)))
  }

  # Filter out infinite dates (from empty groups)
  first_dates <- first_dates %>%
    filter(!is.infinite(FIRST_CHEMO_DATE))

  message(glue("  Patients with chemo procedure dates: {nrow(first_dates)}"))

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
#' Extracts first radiation dates from PROCEDURES (CPT, ICD-9-CM, ICD-10-PCS),
#' then computes payer mode within +/-30 day window.
#'
#' Per D-02: Uses all three PX_TYPE values.
#' ICD-10-PCS radiation codes use prefix matching (D7x).
#'
#' @return Tibble with columns: ID, FIRST_RADIATION_DATE, PAYER_AT_RADIATION
compute_payer_at_radiation <- function() {
  if (is.null(pcornet$PROCEDURES)) {
    message(glue("  Patients with radiation procedure dates: 0"))
    message(glue("PAYER_AT_RADIATION: 0 matched, 0 no encounters in window (NA)"))
    return(tibble(ID = character(0), FIRST_RADIATION_DATE = as.Date(character(0)), PAYER_AT_RADIATION = character(0)))
  }

  # Extract radiation dates from PROCEDURES (all three PX_TYPE values)
  first_dates <- pcornet$PROCEDURES %>%
    filter(
      (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$radiation_cpt) |
      (PX_TYPE == "09" & PX %in% TREATMENT_CODES$radiation_icd9) |
      (PX_TYPE == "10" & (
        str_starts(PX, "D70") |
        str_starts(PX, "D71") |
        str_starts(PX, "D72") |
        str_starts(PX, "D7Y")
      ))
    ) %>%
    filter(!is.na(PX_DATE)) %>%
    group_by(ID) %>%
    summarise(FIRST_RADIATION_DATE = min(PX_DATE, na.rm = TRUE), .groups = "drop") %>%
    filter(!is.infinite(FIRST_RADIATION_DATE))

  message(glue("  Patients with radiation procedure dates: {nrow(first_dates)}"))

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
#' Extracts first SCT dates from PROCEDURES (CPT, ICD-9-CM, ICD-10-PCS),
#' then computes payer mode within +/-30 day window.
#'
#' Per D-02: Uses all three PX_TYPE values.
#'
#' @return Tibble with columns: ID, FIRST_SCT_DATE, PAYER_AT_SCT
compute_payer_at_sct <- function() {
  if (is.null(pcornet$PROCEDURES)) {
    message(glue("  Patients with SCT procedure dates: 0"))
    message(glue("PAYER_AT_SCT: 0 matched, 0 no encounters in window (NA)"))
    return(tibble(ID = character(0), FIRST_SCT_DATE = as.Date(character(0)), PAYER_AT_SCT = character(0)))
  }

  # Extract SCT dates from PROCEDURES (all three PX_TYPE values)
  first_dates <- pcornet$PROCEDURES %>%
    filter(
      (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$sct_cpt) |
      (PX_TYPE == "09" & PX %in% TREATMENT_CODES$sct_icd9) |
      (PX_TYPE == "10" & PX %in% TREATMENT_CODES$sct_icd10pcs)
    ) %>%
    filter(!is.na(PX_DATE)) %>%
    group_by(ID) %>%
    summarise(FIRST_SCT_DATE = min(PX_DATE, na.rm = TRUE), .groups = "drop") %>%
    filter(!is.infinite(FIRST_SCT_DATE))

  message(glue("  Patients with SCT procedure dates: {nrow(first_dates)}"))

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

# ==============================================================================
# End of 10_treatment_payer.R
# ==============================================================================
