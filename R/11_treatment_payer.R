# ==============================================================================
# 11_treatment_payer.R
# ==============================================================================
#
# Purpose:
#   Treatment-anchored payer mode: assigns primary payer within +/-30 day window
#   around first treatment date. Mirrors PAYER_CATEGORY_AT_FIRST_DX pattern from
#   02_harmonize_payer.R but anchors on treatment rather than diagnosis.
#
# Inputs:
#   - hl_cohort environment from 14_build_cohort (contains payer_summary, encounters)
#   - PCORnet tables via get_pcornet_table(): PROCEDURES, PRESCRIBING, DIAGNOSIS,
#     ENCOUNTER, DISPENSING, MED_ADMIN, TUMOR_REGISTRY_ALL
#   - TREATMENT_CODES and CONFIG from 00_config.R
#
# Outputs:
#   - treatment_payer tibble added to environment: ID, FIRST_*_DATE, PAYER_AT_*
#     for each treatment type (chemo, radiation, SCT)
#
# Dependencies:
#   - Sourced by 14_build_cohort.R
#   - Requires payer_summary and hl_cohort in environment
#   - Uses encounters tibble (from 02_harmonize_payer.R)
#
# Requirements: Implements Phase 8 treatment-anchored payer mode
#
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP ----
# ==============================================================================

library(dplyr)
library(stringr)
library(glue)
library(purrr) # For compact() in multi-source date combination

# nrow_or_0() now provided by R/utils_treatment.R (auto-sourced via R/00_config.R)

# ==============================================================================
# SECTION 2: PAYER MODE CALCULATION WITHIN TEMPORAL WINDOW ----
# ==============================================================================
#
# WHY +/-30 day window: Clinically relevant window for capturing payer information
# at time of treatment. Treatment dates often fall between insurance billing cycles;
# a 30-day window before and after the procedure date captures the most likely
# active payer. Mirrors the diagnosis window pattern from 02_harmonize_payer.R.
#
# WHY modal payer (most frequent): When multiple payers exist in the window,
# select the one with the most encounters. This represents the patient's dominant
# insurance coverage during the treatment episode.

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
    # WHY arrange with desc(n) then payer_category: When ties occur (two payers
    # with same encounter count), alphabetical order provides deterministic tie-breaking.
    # The Amy Crisp hierarchy (Medicaid > Medicare > Private) is enforced at the
    # same-day level in 60_tiered_same_day_payer.R; this is encounter-count mode.
    arrange(ID, desc(n), payer_category) %>%
    group_by(ID) %>%
    slice(1) %>%
    ungroup() %>%
    select(ID, !!payer_col_name := payer_category)

  result
}

# ==============================================================================
# SECTION 3: CHEMOTHERAPY PAYER AT FIRST TREATMENT ----
# ==============================================================================

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
  # SAFE-02: Validate required tables exist
  procedures_tbl <- tryCatch(get_pcornet_table("PROCEDURES"), error = function(e) NULL)
  if (!is.null(procedures_tbl)) {
    # Materialize for assertion check
    procedures_check <- procedures_tbl %>% head(1) %>% materialize()
    assert_df_valid(
      procedures_check,
      "PROCEDURES",
      required_cols = c("ID", "PX", "PX_TYPE", "PX_DATE"),
      script_name = "R/11"
    )
    rm(procedures_check)
  }

  # Build chemo ICD-10-PCS prefix regex once (config defines these as prefixes, not exact codes)
  chemo_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$chemo_icd10pcs_prefixes, collapse = "|"), ")")

  # Extract chemo dates from PROCEDURES (CPT/HCPCS, ICD-9-CM, ICD-10-PCS, revenue) - consolidated query
  px_dates <- NULL
  if (!is.null(get_pcornet_table("PROCEDURES"))) {
    px_dates <- get_pcornet_table("PROCEDURES") %>%
      filter(
        (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) |
          (PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9) |
          (PX_TYPE == "10" & str_detect(PX, chemo_icd10pcs_rx)) |
          (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$chemo_revenue)
      ) %>%
      filter(!is.na(PX_DATE)) %>%
      group_by(ID) %>%
      summarise(px_date = min(PX_DATE, na.rm = TRUE), .groups = "drop") %>%
      collect()
  }

  # Extract chemo dates from PRESCRIBING (RXNORM_CUI-filtered chemo drugs)
  # Previous version used ANY prescription date, inflating FIRST_CHEMO_DATE counts.
  # Now filters to TREATMENT_CODES$chemo_rxnorm before extracting dates.
  rx_dates <- NULL
  if (!is.null(get_pcornet_table("PRESCRIBING"))) {
    rx_dates <- get_pcornet_table("PRESCRIBING") %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      filter(!is.na(RX_ORDER_DATE) | !is.na(RX_START_DATE)) %>%
      mutate(rx_date_raw = coalesce(RX_ORDER_DATE, RX_START_DATE)) %>%
      filter(!is.na(rx_date_raw)) %>%
      group_by(ID) %>%
      summarise(rx_date = min(rx_date_raw, na.rm = TRUE), .groups = "drop") %>%
      collect()
  }

  # --- Phase 9: Expanded date extraction sources ---

  # DIAGNOSIS DX_DATE: Z51.11/Z51.12 (ICD-10), V58.11/V58.12 (ICD-9) per D-09
  dx_dates <- NULL
  if (!is.null(get_pcornet_table("DIAGNOSIS"))) {
    dx_dates <- get_pcornet_table("DIAGNOSIS") %>%
      filter(
        (DX_TYPE == "10" & DX %in% TREATMENT_CODES$chemo_dx_icd10) |
          (DX_TYPE == "09" & DX %in% TREATMENT_CODES$chemo_dx_icd9)
      ) %>%
      filter(!is.na(DX_DATE)) %>%
      group_by(ID) %>%
      summarise(dx_date = min(DX_DATE, na.rm = TRUE), .groups = "drop") %>%
      collect()
  }

  # ENCOUNTER ADMIT_DATE: DRGs 837-839, 846-848 per D-10
  drg_dates <- NULL
  if (!is.null(get_pcornet_table("ENCOUNTER"))) {
    drg_dates <- get_pcornet_table("ENCOUNTER") %>%
      filter(DRG %in% TREATMENT_CODES$chemo_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      group_by(ID) %>%
      summarise(drg_date = min(ADMIT_DATE, na.rm = TRUE), .groups = "drop") %>%
      collect()
  }

  # DISPENSING DISPENSE_DATE: RXNORM_CUI matching per D-12
  disp_dates <- NULL
  if (!is.null(get_pcornet_table("DISPENSING")) && "RXNORM_CUI" %in% colnames(get_pcornet_table("DISPENSING"))) {
    disp_dates <- get_pcornet_table("DISPENSING") %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      filter(!is.na(DISPENSE_DATE)) %>%
      group_by(ID) %>%
      summarise(disp_date = min(DISPENSE_DATE, na.rm = TRUE), .groups = "drop") %>%
      collect()
  }

  # MED_ADMIN MEDADMIN_START_DATE: RXNORM_CUI matching per D-12
  ma_dates <- NULL
  if (!is.null(get_pcornet_table("MED_ADMIN")) && "RXNORM_CUI" %in% colnames(get_pcornet_table("MED_ADMIN"))) {
    ma_dates <- get_pcornet_table("MED_ADMIN") %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      filter(!is.na(MEDADMIN_START_DATE)) %>%
      group_by(ID) %>%
      summarise(ma_date = min(MEDADMIN_START_DATE, na.rm = TRUE), .groups = "drop") %>%
      collect()
  }

  # TUMOR_REGISTRY: chemo dates (CHEMO_START_DATE_SUMMARY, DT_CHEMO)
  tr_dates <- NULL
  if (!is.null(get_pcornet_table("TUMOR_REGISTRY_ALL"))) {
    tr_chemo_cols <- intersect(
      c("CHEMO_START_DATE_SUMMARY", "DT_CHEMO"),
      colnames(get_pcornet_table("TUMOR_REGISTRY_ALL"))
    )
    if (length(tr_chemo_cols) > 0) {
      tr_data <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
        select(ID, all_of(tr_chemo_cols)) %>%
        filter(if_any(all_of(tr_chemo_cols), ~ !is.na(.))) %>%
        collect()
      if (nrow(tr_data) > 0) {
        if (length(tr_chemo_cols) == 1) {
          tr_data$tr_date <- tr_data[[tr_chemo_cols[1]]]
        } else {
          tr_data$tr_date <- do.call(pmin, c(tr_data[tr_chemo_cols], na.rm = TRUE))
        }
        tr_dates <- tr_data %>%
          filter(!is.na(tr_date)) %>%
          group_by(ID) %>%
          summarise(tr_date = min_or_na(tr_date), .groups = "drop")
      }
    }
  }

  # Combine ALL date sources into single first-date-per-patient
  all_date_sources <- list(
    px_dates = px_dates, rx_dates = rx_dates, dx_dates = dx_dates,
    drg_dates = drg_dates, disp_dates = disp_dates, ma_dates = ma_dates,
    tr_dates = tr_dates
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
      df %>%
        rename(src_date = !!date_col[1]) %>%
        select(ID, src_date)
    })
  )

  first_dates <- stacked %>%
    group_by(ID) %>%
    summarise(FIRST_CHEMO_DATE = min_or_na(src_date), .groups = "drop") %>%
    filter(!is.na(FIRST_CHEMO_DATE))

  # Log source-level date counts
  message(glue("  Chemo date sources: PX={nrow_or_0(px_dates)}, RX={nrow_or_0(rx_dates)}, DX={nrow_or_0(dx_dates)}, DRG={nrow_or_0(drg_dates)}, DISP={nrow_or_0(disp_dates)}, MA={nrow_or_0(ma_dates)}, TR={nrow_or_0(tr_dates)}"))
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

# ==============================================================================
# SECTION 4: RADIATION THERAPY PAYER AT FIRST TREATMENT ----
# ==============================================================================

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
  # Build radiation ICD-10-PCS prefix regex once (config defines these as prefixes, not exact codes)
  rad_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$radiation_icd10pcs_prefixes, collapse = "|"), ")")

  # Extract radiation dates from PROCEDURES (CPT, ICD-9-CM, ICD-10-PCS, revenue) - consolidated query
  px_dates <- NULL
  if (!is.null(get_pcornet_table("PROCEDURES"))) {
    px_dates <- get_pcornet_table("PROCEDURES") %>%
      filter(
        (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$radiation_cpt) |
          (PX_TYPE == "09" & PX %in% TREATMENT_CODES$radiation_icd9) |
          (PX_TYPE == "10" & str_detect(PX, rad_icd10pcs_rx)) |
          (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$radiation_revenue)
      ) %>%
      filter(!is.na(PX_DATE)) %>%
      group_by(ID) %>%
      summarise(px_date = min(PX_DATE, na.rm = TRUE), .groups = "drop") %>%
      collect()
  }

  # --- Phase 9: Expanded date extraction sources ---

  # DIAGNOSIS DX_DATE: Z51.0 (ICD-10), V58.0 (ICD-9) per D-09
  dx_dates <- NULL
  if (!is.null(get_pcornet_table("DIAGNOSIS"))) {
    dx_dates <- get_pcornet_table("DIAGNOSIS") %>%
      filter(
        (DX_TYPE == "10" & DX %in% TREATMENT_CODES$radiation_dx_icd10) |
          (DX_TYPE == "09" & DX %in% TREATMENT_CODES$radiation_dx_icd9)
      ) %>%
      filter(!is.na(DX_DATE)) %>%
      group_by(ID) %>%
      summarise(dx_date = min(DX_DATE, na.rm = TRUE), .groups = "drop") %>%
      collect()
  }

  # ENCOUNTER ADMIT_DATE: DRG 849 per D-10
  drg_dates <- NULL
  if (!is.null(get_pcornet_table("ENCOUNTER"))) {
    drg_dates <- get_pcornet_table("ENCOUNTER") %>%
      filter(DRG %in% TREATMENT_CODES$radiation_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      group_by(ID) %>%
      summarise(drg_date = min(ADMIT_DATE, na.rm = TRUE), .groups = "drop") %>%
      collect()
  }

  # TUMOR_REGISTRY: radiation dates (RAD_START_DATE_SUMMARY, DT_RAD)
  tr_dates <- NULL
  if (!is.null(get_pcornet_table("TUMOR_REGISTRY_ALL"))) {
    tr_rad_cols <- intersect(
      c("RAD_START_DATE_SUMMARY", "DT_RAD"),
      colnames(get_pcornet_table("TUMOR_REGISTRY_ALL"))
    )
    if (length(tr_rad_cols) > 0) {
      tr_data <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
        select(ID, all_of(tr_rad_cols)) %>%
        filter(if_any(all_of(tr_rad_cols), ~ !is.na(.))) %>%
        collect()
      if (nrow(tr_data) > 0) {
        if (length(tr_rad_cols) == 1) {
          tr_data$tr_date <- tr_data[[tr_rad_cols[1]]]
        } else {
          tr_data$tr_date <- do.call(pmin, c(tr_data[tr_rad_cols], na.rm = TRUE))
        }
        tr_dates <- tr_data %>%
          filter(!is.na(tr_date)) %>%
          group_by(ID) %>%
          summarise(tr_date = min_or_na(tr_date), .groups = "drop")
      }
    }
  }

  # Combine ALL date sources
  all_date_sources <- list(
    px_dates = px_dates, dx_dates = dx_dates,
    drg_dates = drg_dates, tr_dates = tr_dates
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
      df %>%
        rename(src_date = !!date_col[1]) %>%
        select(ID, src_date)
    })
  )

  first_dates <- stacked %>%
    group_by(ID) %>%
    summarise(FIRST_RADIATION_DATE = min_or_na(src_date), .groups = "drop") %>%
    filter(!is.na(FIRST_RADIATION_DATE))

  message(glue("  Radiation date sources: PX={nrow_or_0(px_dates)}, DX={nrow_or_0(dx_dates)}, DRG={nrow_or_0(drg_dates)}, TR={nrow_or_0(tr_dates)}"))
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

# ==============================================================================
# SECTION 5: STEM CELL TRANSPLANT PAYER AT FIRST TREATMENT ----
# ==============================================================================

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
  if (!is.null(get_pcornet_table("PROCEDURES"))) {
    px_dates <- get_pcornet_table("PROCEDURES") %>%
      filter(
        (PX_TYPE == "CH" & PX %in% c(TREATMENT_CODES$sct_cpt, TREATMENT_CODES$sct_hcpcs)) |
          (PX_TYPE == "09" & PX %in% TREATMENT_CODES$sct_icd9) |
          (PX_TYPE == "10" & PX %in% TREATMENT_CODES$sct_icd10pcs) |
          (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$sct_revenue)
      ) %>%
      filter(!is.na(PX_DATE)) %>%
      group_by(ID) %>%
      summarise(px_date = min(PX_DATE, na.rm = TRUE), .groups = "drop") %>%
      collect()
  }

  # --- Phase 9: Expanded date extraction sources ---

  # DIAGNOSIS DX_DATE: Z94.84/T86.5/T86.09/Z48.290/T86.0 (ICD-10 only) per D-09
  dx_dates <- NULL
  if (!is.null(get_pcornet_table("DIAGNOSIS"))) {
    dx_dates <- get_pcornet_table("DIAGNOSIS") %>%
      filter(DX_TYPE == "10" & DX %in% TREATMENT_CODES$sct_dx_icd10) %>%
      filter(!is.na(DX_DATE)) %>%
      group_by(ID) %>%
      summarise(dx_date = min(DX_DATE, na.rm = TRUE), .groups = "drop") %>%
      collect()
  }

  # ENCOUNTER ADMIT_DATE: DRGs 014, 016, 017 per D-10
  drg_dates <- NULL
  if (!is.null(get_pcornet_table("ENCOUNTER"))) {
    drg_dates <- get_pcornet_table("ENCOUNTER") %>%
      filter(DRG %in% TREATMENT_CODES$sct_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      group_by(ID) %>%
      summarise(drg_date = min(ADMIT_DATE, na.rm = TRUE), .groups = "drop") %>%
      collect()
  }

  # TUMOR_REGISTRY: SCT dates (DT_HTE, DT_SCT, SCT_DATE, BMT_DATE, etc.)
  tr_dates <- NULL
  if (!is.null(get_pcornet_table("TUMOR_REGISTRY_ALL"))) {
    tr_sct_cols <- intersect(
      c(
        "DT_HTE", "DT_SCT", "SCT_DATE", "BMT_DATE",
        "TRANSPLANT_DATE", "HCT_DATE", "DT_TRANSPLANT"
      ),
      colnames(get_pcornet_table("TUMOR_REGISTRY_ALL"))
    )
    if (length(tr_sct_cols) > 0) {
      tr_data <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
        select(ID, all_of(tr_sct_cols)) %>%
        filter(if_any(all_of(tr_sct_cols), ~ !is.na(.))) %>%
        collect()
      if (nrow(tr_data) > 0) {
        if (length(tr_sct_cols) == 1) {
          tr_data$tr_date <- tr_data[[tr_sct_cols[1]]]
        } else {
          tr_data$tr_date <- do.call(pmin, c(tr_data[tr_sct_cols], na.rm = TRUE))
        }
        tr_dates <- tr_data %>%
          filter(!is.na(tr_date)) %>%
          group_by(ID) %>%
          summarise(tr_date = min_or_na(tr_date), .groups = "drop")
      }
    }
  }

  # Combine ALL date sources
  all_date_sources <- list(
    px_dates = px_dates, dx_dates = dx_dates,
    drg_dates = drg_dates, tr_dates = tr_dates
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
      df %>%
        rename(src_date = !!date_col[1]) %>%
        select(ID, src_date)
    })
  )

  first_dates <- stacked %>%
    group_by(ID) %>%
    summarise(FIRST_SCT_DATE = min_or_na(src_date), .groups = "drop") %>%
    filter(!is.na(FIRST_SCT_DATE))

  message(glue("  SCT date sources: PX={nrow_or_0(px_dates)}, DX={nrow_or_0(dx_dates)}, DRG={nrow_or_0(drg_dates)}, TR={nrow_or_0(tr_dates)}"))
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

# ==============================================================================
# SECTION 6: LAST TREATMENT DATE COMPUTATION ----
# ==============================================================================

#' Compute last treatment date across all treatment types per patient
#'
#' Scans PROCEDURES, PRESCRIBING, DIAGNOSIS, ENCOUNTER, DISPENSING, MED_ADMIN,
#' and TUMOR_REGISTRY_ALL for the latest treatment date (max across chemo,
#' radiation, SCT) per patient. Filters 1900 sentinel dates.
#' Used by 04_build_cohort.R for HAS_POST_TX_ENCOUNTERS.
#'
#' @return Tibble with columns: ID, LAST_ANY_TX_DATE
compute_last_any_treatment_date <- function() {
  # Helper: extract max treatment dates for one type from all available sources
  last_dates_for_type <- function(treatment_type) {
    sources <- list()

    # Build prefix regexes once for this call
    chemo_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$chemo_icd10pcs_prefixes, collapse = "|"), ")")
    rad_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$radiation_icd10pcs_prefixes, collapse = "|"), ")")

    if (treatment_type == "chemo") {
      if (!is.null(get_pcornet_table("PROCEDURES"))) {
        sources$px <- get_pcornet_table("PROCEDURES") %>%
          filter(
            (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) |
              (PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9) |
              (PX_TYPE == "10" & str_detect(PX, chemo_icd10pcs_rx)) |
              (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$chemo_revenue)
          ) %>%
          filter(!is.na(PX_DATE)) %>%
          group_by(ID) %>%
          summarise(tx_date = max(PX_DATE, na.rm = TRUE), .groups = "drop") %>%
          collect()
      }
      if (!is.null(get_pcornet_table("PRESCRIBING"))) {
        sources$rx <- get_pcornet_table("PRESCRIBING") %>%
          filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
          mutate(d = coalesce(RX_ORDER_DATE, RX_START_DATE)) %>%
          filter(!is.na(d)) %>%
          group_by(ID) %>%
          summarise(tx_date = max(d, na.rm = TRUE), .groups = "drop") %>%
          collect()
      }
      if (!is.null(get_pcornet_table("DIAGNOSIS"))) {
        sources$dx <- get_pcornet_table("DIAGNOSIS") %>%
          filter(
            (DX_TYPE == "10" & DX %in% TREATMENT_CODES$chemo_dx_icd10) |
              (DX_TYPE == "09" & DX %in% TREATMENT_CODES$chemo_dx_icd9)
          ) %>%
          filter(!is.na(DX_DATE)) %>%
          group_by(ID) %>%
          summarise(tx_date = max(DX_DATE, na.rm = TRUE), .groups = "drop") %>%
          collect()
      }
      if (!is.null(get_pcornet_table("ENCOUNTER"))) {
        sources$drg <- get_pcornet_table("ENCOUNTER") %>%
          filter(DRG %in% TREATMENT_CODES$chemo_drg) %>%
          filter(!is.na(ADMIT_DATE)) %>%
          group_by(ID) %>%
          summarise(tx_date = max(ADMIT_DATE, na.rm = TRUE), .groups = "drop") %>%
          collect()
      }
      if (!is.null(get_pcornet_table("DISPENSING")) && "RXNORM_CUI" %in% colnames(get_pcornet_table("DISPENSING"))) {
        sources$disp <- get_pcornet_table("DISPENSING") %>%
          filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
          filter(!is.na(DISPENSE_DATE)) %>%
          group_by(ID) %>%
          summarise(tx_date = max(DISPENSE_DATE, na.rm = TRUE), .groups = "drop") %>%
          collect()
      }
      if (!is.null(get_pcornet_table("MED_ADMIN")) && "RXNORM_CUI" %in% colnames(get_pcornet_table("MED_ADMIN"))) {
        sources$ma <- get_pcornet_table("MED_ADMIN") %>%
          filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
          filter(!is.na(MEDADMIN_START_DATE)) %>%
          group_by(ID) %>%
          summarise(tx_date = max(MEDADMIN_START_DATE, na.rm = TRUE), .groups = "drop") %>%
          collect()
      }
      # TUMOR_REGISTRY: chemo dates (CHEMO_START_DATE_SUMMARY, DT_CHEMO)
      if (!is.null(get_pcornet_table("TUMOR_REGISTRY_ALL"))) {
        tr_chemo_cols <- intersect(
          c("CHEMO_START_DATE_SUMMARY", "DT_CHEMO"),
          colnames(get_pcornet_table("TUMOR_REGISTRY_ALL"))
        )
        if (length(tr_chemo_cols) > 0) {
          tr_data <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
            select(ID, all_of(tr_chemo_cols)) %>%
            filter(if_any(all_of(tr_chemo_cols), ~ !is.na(.))) %>%
            collect()
          if (nrow(tr_data) > 0) {
            if (length(tr_chemo_cols) == 1) {
              tr_data$tx_date <- tr_data[[tr_chemo_cols[1]]]
            } else {
              tr_data$tx_date <- do.call(pmax, c(tr_data[tr_chemo_cols], na.rm = TRUE))
            }
            sources$tr <- tr_data %>%
              filter(!is.na(tx_date)) %>%
              group_by(ID) %>%
              summarise(tx_date = max(tx_date, na.rm = TRUE), .groups = "drop")
          }
        }
      }
    } else if (treatment_type == "radiation") {
      if (!is.null(get_pcornet_table("PROCEDURES"))) {
        sources$px <- get_pcornet_table("PROCEDURES") %>%
          filter(
            (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$radiation_cpt) |
              (PX_TYPE == "09" & PX %in% TREATMENT_CODES$radiation_icd9) |
              (PX_TYPE == "10" & str_detect(PX, rad_icd10pcs_rx)) |
              (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$radiation_revenue)
          ) %>%
          filter(!is.na(PX_DATE)) %>%
          group_by(ID) %>%
          summarise(tx_date = max(PX_DATE, na.rm = TRUE), .groups = "drop") %>%
          collect()
      }
      if (!is.null(get_pcornet_table("DIAGNOSIS"))) {
        sources$dx <- get_pcornet_table("DIAGNOSIS") %>%
          filter(
            (DX_TYPE == "10" & DX %in% TREATMENT_CODES$radiation_dx_icd10) |
              (DX_TYPE == "09" & DX %in% TREATMENT_CODES$radiation_dx_icd9)
          ) %>%
          filter(!is.na(DX_DATE)) %>%
          group_by(ID) %>%
          summarise(tx_date = max(DX_DATE, na.rm = TRUE), .groups = "drop") %>%
          collect()
      }
      if (!is.null(get_pcornet_table("ENCOUNTER"))) {
        sources$drg <- get_pcornet_table("ENCOUNTER") %>%
          filter(DRG %in% TREATMENT_CODES$radiation_drg) %>%
          filter(!is.na(ADMIT_DATE)) %>%
          group_by(ID) %>%
          summarise(tx_date = max(ADMIT_DATE, na.rm = TRUE), .groups = "drop") %>%
          collect()
      }
      # TUMOR_REGISTRY: radiation dates (RAD_START_DATE_SUMMARY, DT_RAD)
      if (!is.null(get_pcornet_table("TUMOR_REGISTRY_ALL"))) {
        tr_rad_cols <- intersect(
          c("RAD_START_DATE_SUMMARY", "DT_RAD"),
          colnames(get_pcornet_table("TUMOR_REGISTRY_ALL"))
        )
        if (length(tr_rad_cols) > 0) {
          tr_data <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
            select(ID, all_of(tr_rad_cols)) %>%
            filter(if_any(all_of(tr_rad_cols), ~ !is.na(.))) %>%
            collect()
          if (nrow(tr_data) > 0) {
            if (length(tr_rad_cols) == 1) {
              tr_data$tx_date <- tr_data[[tr_rad_cols[1]]]
            } else {
              tr_data$tx_date <- do.call(pmax, c(tr_data[tr_rad_cols], na.rm = TRUE))
            }
            sources$tr <- tr_data %>%
              filter(!is.na(tx_date)) %>%
              group_by(ID) %>%
              summarise(tx_date = max(tx_date, na.rm = TRUE), .groups = "drop")
          }
        }
      }
    } else if (treatment_type == "sct") {
      if (!is.null(get_pcornet_table("PROCEDURES"))) {
        sources$px <- get_pcornet_table("PROCEDURES") %>%
          filter(
            (PX_TYPE == "CH" & PX %in% c(TREATMENT_CODES$sct_cpt, TREATMENT_CODES$sct_hcpcs)) |
              (PX_TYPE == "09" & PX %in% TREATMENT_CODES$sct_icd9) |
              (PX_TYPE == "10" & PX %in% TREATMENT_CODES$sct_icd10pcs) |
              (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$sct_revenue)
          ) %>%
          filter(!is.na(PX_DATE)) %>%
          group_by(ID) %>%
          summarise(tx_date = max(PX_DATE, na.rm = TRUE), .groups = "drop") %>%
          collect()
      }
      if (!is.null(get_pcornet_table("DIAGNOSIS"))) {
        sources$dx <- get_pcornet_table("DIAGNOSIS") %>%
          filter(DX_TYPE == "10" & DX %in% TREATMENT_CODES$sct_dx_icd10) %>%
          filter(!is.na(DX_DATE)) %>%
          group_by(ID) %>%
          summarise(tx_date = max(DX_DATE, na.rm = TRUE), .groups = "drop") %>%
          collect()
      }
      if (!is.null(get_pcornet_table("ENCOUNTER"))) {
        sources$drg <- get_pcornet_table("ENCOUNTER") %>%
          filter(DRG %in% TREATMENT_CODES$sct_drg) %>%
          filter(!is.na(ADMIT_DATE)) %>%
          group_by(ID) %>%
          summarise(tx_date = max(ADMIT_DATE, na.rm = TRUE), .groups = "drop") %>%
          collect()
      }
      # TUMOR_REGISTRY: SCT dates (DT_HTE, DT_SCT, SCT_DATE, BMT_DATE, etc.)
      if (!is.null(get_pcornet_table("TUMOR_REGISTRY_ALL"))) {
        tr_sct_cols <- intersect(
          c(
            "DT_HTE", "DT_SCT", "SCT_DATE", "BMT_DATE",
            "TRANSPLANT_DATE", "HCT_DATE", "DT_TRANSPLANT"
          ),
          colnames(get_pcornet_table("TUMOR_REGISTRY_ALL"))
        )
        if (length(tr_sct_cols) > 0) {
          tr_data <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
            select(ID, all_of(tr_sct_cols)) %>%
            filter(if_any(all_of(tr_sct_cols), ~ !is.na(.))) %>%
            collect()
          if (nrow(tr_data) > 0) {
            if (length(tr_sct_cols) == 1) {
              tr_data$tx_date <- tr_data[[tr_sct_cols[1]]]
            } else {
              tr_data$tx_date <- do.call(pmax, c(tr_data[tr_sct_cols], na.rm = TRUE))
            }
            sources$tr <- tr_data %>%
              filter(!is.na(tx_date)) %>%
              group_by(ID) %>%
              summarise(tx_date = max(tx_date, na.rm = TRUE), .groups = "drop")
          }
        }
      }
    }

    non_null <- compact(sources)
    if (length(non_null) == 0) {
      return(tibble(ID = character(0), tx_date = as.Date(character(0))))
    }

    bind_rows(non_null) %>%
      group_by(ID) %>%
      summarise(tx_date = max_or_na(tx_date), .groups = "drop") %>%
      filter(!is.na(tx_date))
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
    summarise(LAST_ANY_TX_DATE = max_or_na(tx_date), .groups = "drop") %>%
    filter(!is.na(LAST_ANY_TX_DATE))

  message(glue("  LAST_ANY_TX_DATE: {nrow(result)} patients with treatment"))
  result
}

# ==============================================================================
# End of 10_treatment_payer.R
# ==============================================================================
