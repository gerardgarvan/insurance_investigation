# ==============================================================================
# 03_cohort_predicates.R -- Named filter predicates for HL cohort building
# ==============================================================================
#
# Defines tibble-in/tibble-out filter functions following the project's named
# predicate convention (has_*, with_*, exclude_*). Each function:
#   - Accepts a patient-level tibble (one row per patient with at least ID column)
#   - Returns a filtered tibble (same structure, fewer rows)
#   - Uses semi_join/inner_join for set-based filtering (not row-level filter())
#
# Also defines treatment flag identification functions (has_chemo, has_radiation,
# has_sct) that return tibbles of patient IDs with evidence of treatment.
#
# Requirements: CHRT-01 (named predicates), CHRT-02 (attrition visibility via
#   message() logging in each predicate), CHRT-03 (ICD format matching)
#
# Dependencies (loaded via 00_config.R auto-source):
#   - is_hl_diagnosis() from utils_icd.R
#   - normalize_icd() from utils_icd.R
#   - TREATMENT_CODES from 00_config.R
#   - pcornet$* tables from 01_load_pcornet.R
#
# Usage:
#   source("R/02_harmonize_payer.R")  # Loads everything upstream
#   source("R/03_cohort_predicates.R")
#   cohort <- pcornet$DEMOGRAPHIC %>%
#     select(ID, SOURCE) %>%
#     has_hodgkin_diagnosis() %>%
#     with_enrollment_period() %>%
#     exclude_missing_payer(payer_summary)
#
# ==============================================================================

library(dplyr)
library(lubridate)
library(glue)

# ==============================================================================
# SECTION 1: FILTER PREDICATES (tibble-in, tibble-out)
# ==============================================================================

#' Filter to patients with Hodgkin Lymphoma diagnosis
#'
#' Returns only patients who have at least one HL diagnosis code in the
#' DIAGNOSIS table. Uses is_hl_diagnosis() which handles both ICD-9 (201.xx)
#' and ICD-10 (C81.xx) codes in dotted or undotted format.
#'
#' @param patient_df Tibble with at least an ID column
#' @return Filtered tibble containing only patients with HL diagnosis
#'
has_hodgkin_diagnosis <- function(patient_df) {
  hl_patients <- pcornet$DIAGNOSIS %>%
    filter(is_hl_diagnosis(DX, DX_TYPE)) %>%
    distinct(ID)

  message(glue("[Predicate] has_hodgkin_diagnosis: {nrow(hl_patients)} patients with HL diagnosis in DIAGNOSIS table"))

  patient_df %>%
    semi_join(hl_patients, by = "ID")
}

#' Filter to patients with at least one enrollment record
#'
#' Returns only patients who have at least one enrollment record in the
#' ENROLLMENT table. Per D-03: no minimum duration enforced (any enrollment
#' record counts).
#'
#' @param patient_df Tibble with at least an ID column
#' @return Filtered tibble containing only patients with enrollment records
#'
with_enrollment_period <- function(patient_df) {
  enrolled_patients <- pcornet$ENROLLMENT %>%
    distinct(ID)

  message(glue("[Predicate] with_enrollment_period: {nrow(enrolled_patients)} patients with enrollment records"))

  patient_df %>%
    semi_join(enrolled_patients, by = "ID")
}

#' Exclude patients with missing or invalid payer category
#'
#' Returns only patients where PAYER_CATEGORY_PRIMARY is NOT NA, NOT "Unknown",
#' and NOT "Unavailable". Per D-04: only patients with concrete payer categories
#' (Medicare, Medicaid, Dual eligible, Private, Other government, No payment /
#' Self-pay, Other) are retained.
#'
#' @param patient_df Tibble with at least an ID column
#' @param payer_summary Payer summary tibble from 02_harmonize_payer.R
#' @return Filtered tibble containing only patients with valid payer category
#'
exclude_missing_payer <- function(patient_df, payer_summary) {
  valid_payer_patients <- payer_summary %>%
    filter(
      !is.na(PAYER_CATEGORY_PRIMARY) &
      !PAYER_CATEGORY_PRIMARY %in% c("Unknown", "Unavailable")
    ) %>%
    distinct(ID)

  message(glue("[Predicate] exclude_missing_payer: {nrow(valid_payer_patients)} patients with valid payer category"))

  patient_df %>%
    semi_join(valid_payer_patients, by = "ID")
}

# ==============================================================================
# SECTION 2: TREATMENT FLAG FUNCTIONS (returns tibble of IDs with evidence)
# ==============================================================================

#' Identify patients with chemotherapy evidence
#'
#' Combines evidence from:
#'   - TUMOR_REGISTRY1: CHEMO_START_DATE_SUMMARY (non-NA)
#'   - TUMOR_REGISTRY2/3: DT_CHEMO (non-NA)
#'   - PROCEDURES: PX_TYPE == "CH" and PX in TREATMENT_CODES$chemo_hcpcs
#'   - PRESCRIBING: RXNORM_CUI in TREATMENT_CODES$chemo_rxnorm
#'
#' @return Tibble with columns: ID, HAD_CHEMO (integer 1 for all rows)
#'
has_chemo <- function() {
  chemo_ids <- character(0)

  # TUMOR_REGISTRY1: CHEMO_START_DATE_SUMMARY (different column name from TR2/TR3)
  if (!is.null(pcornet$TUMOR_REGISTRY1) &&
      "CHEMO_START_DATE_SUMMARY" %in% names(pcornet$TUMOR_REGISTRY1)) {
    tr1_chemo <- pcornet$TUMOR_REGISTRY1 %>%
      filter(!is.na(CHEMO_START_DATE_SUMMARY)) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, tr1_chemo)
  }

  # TUMOR_REGISTRY2: DT_CHEMO
  if (!is.null(pcornet$TUMOR_REGISTRY2) &&
      "DT_CHEMO" %in% names(pcornet$TUMOR_REGISTRY2)) {
    tr2_chemo <- pcornet$TUMOR_REGISTRY2 %>%
      filter(!is.na(DT_CHEMO)) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, tr2_chemo)
  }

  # TUMOR_REGISTRY3: DT_CHEMO
  if (!is.null(pcornet$TUMOR_REGISTRY3) &&
      "DT_CHEMO" %in% names(pcornet$TUMOR_REGISTRY3)) {
    tr3_chemo <- pcornet$TUMOR_REGISTRY3 %>%
      filter(!is.na(DT_CHEMO)) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, tr3_chemo)
  }

  # PROCEDURES: chemo HCPCS codes
  if (!is.null(pcornet$PROCEDURES)) {
    px_chemo <- pcornet$PROCEDURES %>%
      filter(PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, px_chemo)
  }

  # PRESCRIBING: chemo RXNORM codes
  if (!is.null(pcornet$PRESCRIBING)) {
    rx_chemo <- pcornet$PRESCRIBING %>%
      filter(!is.na(RXNORM_CUI) & RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, rx_chemo)
  }

  result <- tibble(ID = unique(chemo_ids), HAD_CHEMO = 1L)
  message(glue("[Treatment] has_chemo: {nrow(result)} patients with chemotherapy evidence"))
  result
}

#' Identify patients with radiation therapy evidence
#'
#' Combines evidence from:
#'   - TUMOR_REGISTRY2/3: DT_RAD (non-NA)
#'   - PROCEDURES: PX_TYPE == "CH" and PX in TREATMENT_CODES$radiation_cpt
#'
#' Note: TUMOR_REGISTRY1 does NOT have DT_RAD column (has REASON_NO_RADIATION
#' but no date field).
#'
#' @return Tibble with columns: ID, HAD_RADIATION (integer 1 for all rows)
#'
has_radiation <- function() {
  rad_ids <- character(0)

  # TUMOR_REGISTRY2: DT_RAD
  if (!is.null(pcornet$TUMOR_REGISTRY2) &&
      "DT_RAD" %in% names(pcornet$TUMOR_REGISTRY2)) {
    tr2_rad <- pcornet$TUMOR_REGISTRY2 %>%
      filter(!is.na(DT_RAD)) %>%
      pull(ID)
    rad_ids <- c(rad_ids, tr2_rad)
  }

  # TUMOR_REGISTRY3: DT_RAD
  if (!is.null(pcornet$TUMOR_REGISTRY3) &&
      "DT_RAD" %in% names(pcornet$TUMOR_REGISTRY3)) {
    tr3_rad <- pcornet$TUMOR_REGISTRY3 %>%
      filter(!is.na(DT_RAD)) %>%
      pull(ID)
    rad_ids <- c(rad_ids, tr3_rad)
  }

  # PROCEDURES: radiation CPT codes
  if (!is.null(pcornet$PROCEDURES)) {
    px_rad <- pcornet$PROCEDURES %>%
      filter(PX_TYPE == "CH" & PX %in% TREATMENT_CODES$radiation_cpt) %>%
      pull(ID)
    rad_ids <- c(rad_ids, px_rad)
  }

  result <- tibble(ID = unique(rad_ids), HAD_RADIATION = 1L)
  message(glue("[Treatment] has_radiation: {nrow(result)} patients with radiation evidence"))
  result
}

#' Identify patients with stem cell transplant evidence
#'
#' Combines evidence from:
#'   - TUMOR_REGISTRY1: HEMATOLOGIC_TRANSPLANT_AND_ENDOC (non-NA, non-empty, non-"00")
#'   - TUMOR_REGISTRY2/3: DT_HTE (non-NA)
#'   - PROCEDURES: PX_TYPE == "CH" and PX in TREATMENT_CODES$sct_cpt
#'
#' Note: DT_HTE may include endocrine therapy, not just SCT. However, for HL,
#' endocrine therapy is not standard, so DT_HTE evidence in an HL cohort is a
#' reasonable SCT signal.
#'
#' Per D-07: Single flag covering both autologous and allogeneic transplant.
#'
#' @return Tibble with columns: ID, HAD_SCT (integer 1 for all rows)
#'
has_sct <- function() {
  sct_ids <- character(0)

  # TUMOR_REGISTRY1: HEMATOLOGIC_TRANSPLANT_AND_ENDOC (code field, not date)
  if (!is.null(pcornet$TUMOR_REGISTRY1) &&
      "HEMATOLOGIC_TRANSPLANT_AND_ENDOC" %in% names(pcornet$TUMOR_REGISTRY1)) {
    tr1_sct <- pcornet$TUMOR_REGISTRY1 %>%
      filter(!is.na(HEMATOLOGIC_TRANSPLANT_AND_ENDOC) &
             HEMATOLOGIC_TRANSPLANT_AND_ENDOC != "" &
             HEMATOLOGIC_TRANSPLANT_AND_ENDOC != "00") %>%
      pull(ID)
    sct_ids <- c(sct_ids, tr1_sct)
  }

  # TUMOR_REGISTRY2: DT_HTE (hematologic transplant/endocrine date)
  if (!is.null(pcornet$TUMOR_REGISTRY2) &&
      "DT_HTE" %in% names(pcornet$TUMOR_REGISTRY2)) {
    tr2_sct <- pcornet$TUMOR_REGISTRY2 %>%
      filter(!is.na(DT_HTE)) %>%
      pull(ID)
    sct_ids <- c(sct_ids, tr2_sct)
  }

  # TUMOR_REGISTRY3: DT_HTE
  if (!is.null(pcornet$TUMOR_REGISTRY3) &&
      "DT_HTE" %in% names(pcornet$TUMOR_REGISTRY3)) {
    tr3_sct <- pcornet$TUMOR_REGISTRY3 %>%
      filter(!is.na(DT_HTE)) %>%
      pull(ID)
    sct_ids <- c(sct_ids, tr3_sct)
  }

  # PROCEDURES: SCT CPT codes
  if (!is.null(pcornet$PROCEDURES)) {
    px_sct <- pcornet$PROCEDURES %>%
      filter(PX_TYPE == "CH" & PX %in% TREATMENT_CODES$sct_cpt) %>%
      pull(ID)
    sct_ids <- c(sct_ids, px_sct)
  }

  result <- tibble(ID = unique(sct_ids), HAD_SCT = 1L)
  message(glue("[Treatment] has_sct: {nrow(result)} patients with SCT evidence"))
  result
}

# ==============================================================================
# End of 03_cohort_predicates.R
# ==============================================================================
