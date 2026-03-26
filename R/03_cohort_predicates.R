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
library(readr)
library(stringr)

# ==============================================================================
# SECTION 1: FILTER PREDICATES (tibble-in, tibble-out)
# ==============================================================================

#' Filter to patients with Hodgkin Lymphoma diagnosis (DIAGNOSIS or TUMOR_REGISTRY)
#'
#' Returns only patients who have at least one HL diagnosis code in the
#' DIAGNOSIS table (ICD-9 201.xx or ICD-10 C81.xx) OR at least one HL
#' histology code in TUMOR_REGISTRY tables (ICD-O-3 9650-9667).
#'
#' Per D-06: Single source of truth for HL identification.
#' Per D-07: Checks TR1 (HISTOLOGICAL_TYPE), TR2/TR3 (MORPH).
#'
#' @param patient_df Tibble with at least an ID column
#' @return Filtered tibble containing only patients with HL diagnosis
#'
has_hodgkin_diagnosis <- function(patient_df) {

  # Source 1: DIAGNOSIS table (ICD-9/10)
  dx_hl_patients <- pcornet$DIAGNOSIS %>%
    filter(is_hl_diagnosis(DX, DX_TYPE)) %>%
    distinct(ID)

  # Source 2: TUMOR_REGISTRY1 (verbose NAACCR column: HISTOLOGICAL_TYPE)
  tr1_hl_patients <- if (!is.null(pcornet$TUMOR_REGISTRY1) &&
                         "HISTOLOGICAL_TYPE" %in% names(pcornet$TUMOR_REGISTRY1)) {
    pcornet$TUMOR_REGISTRY1 %>%
      filter(is_hl_histology(HISTOLOGICAL_TYPE)) %>%
      distinct(ID)
  } else {
    tibble(ID = character())
  }

  # Source 3: TUMOR_REGISTRY2 (compact column: MORPH)
  tr2_hl_patients <- if (!is.null(pcornet$TUMOR_REGISTRY2) &&
                         "MORPH" %in% names(pcornet$TUMOR_REGISTRY2)) {
    pcornet$TUMOR_REGISTRY2 %>%
      filter(is_hl_histology(MORPH)) %>%
      distinct(ID)
  } else {
    tibble(ID = character())
  }

  # Source 4: TUMOR_REGISTRY3 (compact column: MORPH)
  tr3_hl_patients <- if (!is.null(pcornet$TUMOR_REGISTRY3) &&
                         "MORPH" %in% names(pcornet$TUMOR_REGISTRY3)) {
    pcornet$TUMOR_REGISTRY3 %>%
      filter(is_hl_histology(MORPH)) %>%
      distinct(ID)
  } else {
    tibble(ID = character())
  }

  # Union all TR sources
  tr_all <- bind_rows(tr1_hl_patients, tr2_hl_patients, tr3_hl_patients) %>%
    distinct(ID)

  # Build HL source mapping for ALL patients in patient_df (D-20)
  hl_source_map <- patient_df %>%
    select(ID) %>%
    distinct() %>%
    left_join(
      dx_hl_patients %>% mutate(has_dx = TRUE) %>% distinct(ID, has_dx),
      by = "ID"
    ) %>%
    left_join(
      tr_all %>% mutate(has_tr = TRUE) %>% distinct(ID, has_tr),
      by = "ID"
    ) %>%
    mutate(
      has_dx = coalesce(has_dx, FALSE),
      has_tr = coalesce(has_tr, FALSE),
      HL_SOURCE = case_when(
        has_dx & has_tr ~ "Both",
        has_dx & !has_tr ~ "DIAGNOSIS only",
        !has_dx & has_tr ~ "TR only",
        TRUE ~ "Neither"
      )
    ) %>%
    select(ID, HL_SOURCE)

  # Log HL source breakdown (D-20)
  message(glue("[Predicate] has_hodgkin_diagnosis source breakdown:"))
  source_counts <- hl_source_map %>% count(HL_SOURCE)
  for (i in seq_len(nrow(source_counts))) {
    message(glue("  {source_counts$HL_SOURCE[i]}: {source_counts$n[i]}"))
  }

  # Write excluded "Neither" patients to CSV (D-02)
  excluded <- patient_df %>%
    inner_join(
      hl_source_map %>% filter(HL_SOURCE == "Neither"),
      by = "ID"
    ) %>%
    mutate(
      EXCLUSION_REASON = "No HL evidence in DIAGNOSIS or TUMOR_REGISTRY tables"
    )

  if (nrow(excluded) > 0) {
    excl_dir <- file.path(CONFIG$output_dir, "cohort")
    dir.create(excl_dir, showWarnings = FALSE, recursive = TRUE)
    write_csv(excluded, file.path(excl_dir, "excluded_no_hl_evidence.csv"))
    message(glue("  Wrote {nrow(excluded)} excluded patients to excluded_no_hl_evidence.csv"))
  } else {
    message("  No 'Neither' patients found (all have HL evidence)")
  }

  # Return patients WITH HL evidence, including HL_SOURCE column (D-02, D-20)
  patient_df %>%
    inner_join(
      hl_source_map %>% filter(HL_SOURCE != "Neither"),
      by = "ID"
    )
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
#'   - PROCEDURES: PX_TYPE == "RE" and PX in TREATMENT_CODES$chemo_revenue (Phase 9)
#'   - PRESCRIBING: RXNORM_CUI in TREATMENT_CODES$chemo_rxnorm
#'   - DISPENSING: RXNORM_CUI in TREATMENT_CODES$chemo_rxnorm (Phase 9)
#'   - MED_ADMIN: RXNORM_CUI in TREATMENT_CODES$chemo_rxnorm (Phase 9)
#'   - DIAGNOSIS: Z51.11/Z51.12 (ICD-10), V58.11/V58.12 (ICD-9) (Phase 9)
#'   - ENCOUNTER: DRG in TREATMENT_CODES$chemo_drg (Phase 9)
#'
#' @return Tibble with columns: ID, HAD_CHEMO (integer 1 for all rows)
#'
has_chemo <- function() {
  chemo_ids <- character(0)

  # Initialize source counters for aggregate logging (D-14)
  n_tr <- 0L
  n_px <- 0L
  n_rx <- 0L
  n_dx <- 0L
  n_drg <- 0L
  n_disp <- 0L
  n_ma <- 0L
  n_rev <- 0L

  # TUMOR_REGISTRY1: CHEMO_START_DATE_SUMMARY (different column name from TR2/TR3)
  tr1_chemo <- character(0)
  if (!is.null(pcornet$TUMOR_REGISTRY1) &&
      "CHEMO_START_DATE_SUMMARY" %in% names(pcornet$TUMOR_REGISTRY1)) {
    tr1_chemo <- pcornet$TUMOR_REGISTRY1 %>%
      filter(!is.na(CHEMO_START_DATE_SUMMARY)) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, tr1_chemo)
  }

  # TUMOR_REGISTRY2: DT_CHEMO
  tr2_chemo <- character(0)
  if (!is.null(pcornet$TUMOR_REGISTRY2) &&
      "DT_CHEMO" %in% names(pcornet$TUMOR_REGISTRY2)) {
    tr2_chemo <- pcornet$TUMOR_REGISTRY2 %>%
      filter(!is.na(DT_CHEMO)) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, tr2_chemo)
  }

  # TUMOR_REGISTRY3: DT_CHEMO
  tr3_chemo <- character(0)
  if (!is.null(pcornet$TUMOR_REGISTRY3) &&
      "DT_CHEMO" %in% names(pcornet$TUMOR_REGISTRY3)) {
    tr3_chemo <- pcornet$TUMOR_REGISTRY3 %>%
      filter(!is.na(DT_CHEMO)) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, tr3_chemo)
  }

  # Aggregate TR source count
  n_tr <- length(unique(c(tr1_chemo, tr2_chemo, tr3_chemo)))

  # PROCEDURES: chemo CPT/HCPCS, ICD-9-CM, ICD-10-PCS codes
  px_chemo <- character(0)
  if (!is.null(pcornet$PROCEDURES)) {
    px_chemo <- pcornet$PROCEDURES %>%
      filter(
        (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) |
        (PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9) |
        (PX_TYPE == "10" & PX %in% TREATMENT_CODES$chemo_icd10pcs_prefixes)
      ) %>%
      distinct(ID) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, px_chemo)
  }
  n_px <- length(px_chemo)

  # PRESCRIBING: any prescription record (matches Python pipeline's broad definition)
  # Python counts any patient with RX_ORDER_DATE or RX_START_DATE as chemo evidence
  rx_chemo <- character(0)
  if (!is.null(pcornet$PRESCRIBING)) {
    rx_chemo <- pcornet$PRESCRIBING %>%
      filter(!is.na(RX_ORDER_DATE) | !is.na(RX_START_DATE)) %>%
      distinct(ID) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, rx_chemo)
  }
  n_rx <- length(rx_chemo)

  # --- Phase 9: Expanded treatment detection sources ---

  # DIAGNOSIS: Z51.11/Z51.12 (ICD-10), V58.11/V58.12 (ICD-9) per D-09
  if (!is.null(pcornet$DIAGNOSIS)) {
    dx_chemo <- pcornet$DIAGNOSIS %>%
      filter(
        (DX_TYPE == "10" & DX %in% TREATMENT_CODES$chemo_dx_icd10) |
        (DX_TYPE == "09" & DX %in% TREATMENT_CODES$chemo_dx_icd9)
      ) %>%
      distinct(ID) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, dx_chemo)
    n_dx <- length(dx_chemo)
  }

  # ENCOUNTER: DRGs 837-839, 846-848 per D-10
  if (!is.null(pcornet$ENCOUNTER)) {
    drg_chemo <- pcornet$ENCOUNTER %>%
      filter(DRG %in% TREATMENT_CODES$chemo_drg) %>%
      distinct(ID) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, drg_chemo)
    n_drg <- length(drg_chemo)
  }

  # DISPENSING: RXNORM_CUI matching per D-12 (same CUIs as PRESCRIBING)
  if (!is.null(pcornet$DISPENSING)) {
    disp_chemo <- pcornet$DISPENSING %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      distinct(ID) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, disp_chemo)
    n_disp <- length(disp_chemo)
  }

  # MED_ADMIN: RXNORM_CUI matching per D-12 (same CUIs as PRESCRIBING)
  if (!is.null(pcornet$MED_ADMIN)) {
    ma_chemo <- pcornet$MED_ADMIN %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      distinct(ID) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, ma_chemo)
    n_ma <- length(ma_chemo)
  }

  # PROCEDURES revenue codes: 0331/0332/0335 per D-11 (PX_TYPE = "RE")
  if (!is.null(pcornet$PROCEDURES)) {
    rev_chemo <- pcornet$PROCEDURES %>%
      filter(PX_TYPE == "RE" & PX %in% TREATMENT_CODES$chemo_revenue) %>%
      distinct(ID) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, rev_chemo)
    n_rev <- length(rev_chemo)
  }

  result <- tibble(ID = unique(chemo_ids), HAD_CHEMO = 1L)
  message(glue("[Treatment] has_chemo: {nrow(result)} patients total"))
  message(glue("  Sources: TR={n_tr}, PX={n_px}, RX={n_rx}, DX={n_dx}, DRG={n_drg}, DISP={n_disp}, MA={n_ma}, REV={n_rev}"))
  result
}

#' Identify patients with radiation therapy evidence
#'
#' Combines evidence from:
#'   - TUMOR_REGISTRY1: RAD_START_DATE_SUMMARY (non-NA)
#'   - TUMOR_REGISTRY2/3: DT_RAD (non-NA)
#'   - PROCEDURES: PX_TYPE == "CH" and PX in TREATMENT_CODES$radiation_cpt
#'   - PROCEDURES: PX_TYPE == "RE" and PX in TREATMENT_CODES$radiation_revenue (Phase 9)
#'   - DIAGNOSIS: Z51.0 (ICD-10), V58.0 (ICD-9) (Phase 9)
#'   - ENCOUNTER: DRG in TREATMENT_CODES$radiation_drg (Phase 9)
#'
#' Note: Radiation does NOT use DISPENSING or MED_ADMIN (radiation is a procedure,
#' not a drug dispensation). No RXNORM_CUI matching for radiation.
#'
#' @return Tibble with columns: ID, HAD_RADIATION (integer 1 for all rows)
#'
has_radiation <- function() {
  rad_ids <- character(0)

  # Initialize source counters for aggregate logging (D-14)
  n_tr <- 0L
  n_px <- 0L
  n_dx <- 0L
  n_drg <- 0L
  n_rev <- 0L

  # TUMOR_REGISTRY1: RAD_START_DATE_SUMMARY (Python pipeline checks this)
  tr1_rad <- character(0)
  if (!is.null(pcornet$TUMOR_REGISTRY1) &&
      "RAD_START_DATE_SUMMARY" %in% names(pcornet$TUMOR_REGISTRY1)) {
    tr1_rad <- pcornet$TUMOR_REGISTRY1 %>%
      filter(!is.na(RAD_START_DATE_SUMMARY)) %>%
      pull(ID)
    rad_ids <- c(rad_ids, tr1_rad)
  }

  # TUMOR_REGISTRY2: DT_RAD
  tr2_rad <- character(0)
  if (!is.null(pcornet$TUMOR_REGISTRY2) &&
      "DT_RAD" %in% names(pcornet$TUMOR_REGISTRY2)) {
    tr2_rad <- pcornet$TUMOR_REGISTRY2 %>%
      filter(!is.na(DT_RAD)) %>%
      pull(ID)
    rad_ids <- c(rad_ids, tr2_rad)
  }

  # TUMOR_REGISTRY3: DT_RAD
  tr3_rad <- character(0)
  if (!is.null(pcornet$TUMOR_REGISTRY3) &&
      "DT_RAD" %in% names(pcornet$TUMOR_REGISTRY3)) {
    tr3_rad <- pcornet$TUMOR_REGISTRY3 %>%
      filter(!is.na(DT_RAD)) %>%
      pull(ID)
    rad_ids <- c(rad_ids, tr3_rad)
  }

  # Aggregate TR source count
  n_tr <- length(unique(c(tr1_rad, tr2_rad, tr3_rad)))

  # PROCEDURES: radiation CPT, ICD-9-CM, ICD-10-PCS codes
  px_rad <- character(0)
  if (!is.null(pcornet$PROCEDURES)) {
    px_rad <- pcornet$PROCEDURES %>%
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
      distinct(ID) %>%
      pull(ID)
    rad_ids <- c(rad_ids, px_rad)
  }
  n_px <- length(px_rad)

  # --- Phase 9: Expanded treatment detection sources ---

  # DIAGNOSIS: Z51.0 (ICD-10), V58.0 (ICD-9) per D-09
  if (!is.null(pcornet$DIAGNOSIS)) {
    dx_rad <- pcornet$DIAGNOSIS %>%
      filter(
        (DX_TYPE == "10" & DX %in% TREATMENT_CODES$radiation_dx_icd10) |
        (DX_TYPE == "09" & DX %in% TREATMENT_CODES$radiation_dx_icd9)
      ) %>%
      distinct(ID) %>%
      pull(ID)
    rad_ids <- c(rad_ids, dx_rad)
    n_dx <- length(dx_rad)
  }

  # ENCOUNTER: DRG 849 per D-10
  if (!is.null(pcornet$ENCOUNTER)) {
    drg_rad <- pcornet$ENCOUNTER %>%
      filter(DRG %in% TREATMENT_CODES$radiation_drg) %>%
      distinct(ID) %>%
      pull(ID)
    rad_ids <- c(rad_ids, drg_rad)
    n_drg <- length(drg_rad)
  }

  # PROCEDURES revenue codes: 0330/0333 per D-11 (PX_TYPE = "RE")
  if (!is.null(pcornet$PROCEDURES)) {
    rev_rad <- pcornet$PROCEDURES %>%
      filter(PX_TYPE == "RE" & PX %in% TREATMENT_CODES$radiation_revenue) %>%
      distinct(ID) %>%
      pull(ID)
    rad_ids <- c(rad_ids, rev_rad)
    n_rev <- length(rev_rad)
  }

  result <- tibble(ID = unique(rad_ids), HAD_RADIATION = 1L)
  message(glue("[Treatment] has_radiation: {nrow(result)} patients total"))
  message(glue("  Sources: TR={n_tr}, PX={n_px}, DX={n_dx}, DRG={n_drg}, REV={n_rev}"))
  result
}

#' Identify patients with stem cell transplant evidence
#'
#' Combines evidence from:
#'   - TUMOR_REGISTRY1: HEMATOLOGIC_TRANSPLANT_AND_ENDOC (non-NA, non-empty, non-"00")
#'   - TUMOR_REGISTRY2/3: DT_HTE (non-NA) + Python pipeline SCT date columns
#'   - PROCEDURES: PX_TYPE == "CH" and PX in TREATMENT_CODES$sct_cpt
#'   - PROCEDURES: PX_TYPE == "RE" and PX in TREATMENT_CODES$sct_revenue (Phase 9)
#'   - DIAGNOSIS: Z94.84/T86.5/T86.09/Z48.290/T86.0 (ICD-10 only) (Phase 9)
#'   - ENCOUNTER: DRG in TREATMENT_CODES$sct_drg (Phase 9)
#'
#' Note: DT_HTE may include endocrine therapy, not just SCT. However, for HL,
#' endocrine therapy is not standard, so DT_HTE evidence in an HL cohort is a
#' reasonable SCT signal.
#'
#' Note: SCT does NOT use DISPENSING or MED_ADMIN (transplant is a procedure,
#' not a drug dispensation). No RXNORM_CUI matching for SCT.
#'
#' Per D-07: Single flag covering both autologous and allogeneic transplant.
#'
#' @return Tibble with columns: ID, HAD_SCT (integer 1 for all rows)
#'
has_sct <- function() {
  sct_ids <- character(0)

  # Initialize source counters for aggregate logging (D-14)
  n_tr <- 0L
  n_px <- 0L
  n_dx <- 0L
  n_drg <- 0L
  n_rev <- 0L

  # TUMOR_REGISTRY1: HEMATOLOGIC_TRANSPLANT_AND_ENDOC (code field, not date)
  tr1_sct <- character(0)
  if (!is.null(pcornet$TUMOR_REGISTRY1) &&
      "HEMATOLOGIC_TRANSPLANT_AND_ENDOC" %in% names(pcornet$TUMOR_REGISTRY1)) {
    tr1_sct <- pcornet$TUMOR_REGISTRY1 %>%
      filter(!is.na(HEMATOLOGIC_TRANSPLANT_AND_ENDOC) &
             HEMATOLOGIC_TRANSPLANT_AND_ENDOC != "" &
             HEMATOLOGIC_TRANSPLANT_AND_ENDOC != "00") %>%
      pull(ID)
    sct_ids <- c(sct_ids, tr1_sct)
  }

  # TUMOR_REGISTRY2/3: DT_HTE + Python pipeline SCT date columns
  # Python checks: DT_SCT, SCT_DATE, BMT_DATE, TRANSPLANT_DATE, HCT_DATE, DT_TRANSPLANT
  tr_sct_from_loop <- character(0)
  sct_date_cols <- c("DT_HTE", "DT_SCT", "SCT_DATE", "BMT_DATE",
                     "TRANSPLANT_DATE", "HCT_DATE", "DT_TRANSPLANT")
  for (tr_name in c("TUMOR_REGISTRY2", "TUMOR_REGISTRY3")) {
    tr_df <- pcornet[[tr_name]]
    if (!is.null(tr_df)) {
      present_cols <- intersect(sct_date_cols, names(tr_df))
      if (length(present_cols) > 0) {
        tr_sct <- tr_df %>%
          filter(if_any(all_of(present_cols), ~ !is.na(.))) %>%
          pull(ID)
        sct_ids <- c(sct_ids, tr_sct)
        tr_sct_from_loop <- c(tr_sct_from_loop, tr_sct)
      }
    }
  }

  # Aggregate TR source count
  n_tr <- length(unique(c(tr1_sct, tr_sct_from_loop)))

  # PROCEDURES: SCT CPT, ICD-9-CM, ICD-10-PCS codes
  px_sct <- character(0)
  if (!is.null(pcornet$PROCEDURES)) {
    px_sct <- pcornet$PROCEDURES %>%
      filter(
        (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$sct_cpt) |
        (PX_TYPE == "09" & PX %in% TREATMENT_CODES$sct_icd9) |
        (PX_TYPE == "10" & PX %in% TREATMENT_CODES$sct_icd10pcs)
      ) %>%
      distinct(ID) %>%
      pull(ID)
    sct_ids <- c(sct_ids, px_sct)
  }
  n_px <- length(px_sct)

  # --- Phase 9: Expanded treatment detection sources ---

  # DIAGNOSIS: Z94.84/T86.5/T86.09/Z48.290/T86.0 (ICD-10 only, no ICD-9 SCT dx codes) per D-09
  if (!is.null(pcornet$DIAGNOSIS)) {
    dx_sct <- pcornet$DIAGNOSIS %>%
      filter(DX_TYPE == "10" & DX %in% TREATMENT_CODES$sct_dx_icd10) %>%
      distinct(ID) %>%
      pull(ID)
    sct_ids <- c(sct_ids, dx_sct)
    n_dx <- length(dx_sct)
  }

  # ENCOUNTER: DRGs 014, 016, 017 per D-10
  if (!is.null(pcornet$ENCOUNTER)) {
    drg_sct <- pcornet$ENCOUNTER %>%
      filter(DRG %in% TREATMENT_CODES$sct_drg) %>%
      distinct(ID) %>%
      pull(ID)
    sct_ids <- c(sct_ids, drg_sct)
    n_drg <- length(drg_sct)
  }

  # PROCEDURES revenue codes: 0362/0815 per D-11 (PX_TYPE = "RE")
  if (!is.null(pcornet$PROCEDURES)) {
    rev_sct <- pcornet$PROCEDURES %>%
      filter(PX_TYPE == "RE" & PX %in% TREATMENT_CODES$sct_revenue) %>%
      distinct(ID) %>%
      pull(ID)
    sct_ids <- c(sct_ids, rev_sct)
    n_rev <- length(rev_sct)
  }

  result <- tibble(ID = unique(sct_ids), HAD_SCT = 1L)
  message(glue("[Treatment] has_sct: {nrow(result)} patients total"))
  message(glue("  Sources: TR={n_tr}, PX={n_px}, DX={n_dx}, DRG={n_drg}, REV={n_rev}"))
  result
}

# ==============================================================================
# End of 03_cohort_predicates.R
# ==============================================================================
