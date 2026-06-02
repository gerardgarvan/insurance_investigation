# ==============================================================================
# 10_cohort_predicates.R
# ==============================================================================
#
# Purpose:
#   Named filter predicates (has_*, with_*, exclude_*) for HL cohort building.
#   Each function accepts a patient-level tibble and returns a filtered subset.
#   Also defines treatment flag identification functions (has_chemo, has_radiation,
#   has_sct) that detect treatment evidence across multiple PCORnet source tables.
#
# Inputs:
#   - PCORnet tables via get_pcornet_table(): DIAGNOSIS, ENROLLMENT, DEMOGRAPHIC,
#     PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, ENCOUNTER, TUMOR_REGISTRY_ALL
#   - ICD_CODES and TREATMENT_CODES from 00_config.R
#
# Outputs:
#   None (defines functions loaded by 14_build_cohort.R)
#
# Dependencies:
#   - 00_config.R (auto-sources utils): provides ICD_CODES, TREATMENT_CODES,
#     get_pcornet_table(), materialize(), is_hl_diagnosis(), normalize_icd()
#   - All predicate functions log attrition via message() (CHRT-02)
#
# Requirements: CHRT-01, CHRT-02, CHRT-03
#
# ==============================================================================

# NOTE: Input validation for cohort data handled in R/14_build_cohort.R
# which sources this file and validates pcornet tables before applying predicates.
# Existing tryCatch patterns (18+) for DuckDB NULL-guards preserved per D-05.

library(dplyr)
library(lubridate)
library(glue)
library(readr)
library(stringr)

# ==============================================================================
# SECTION 1: DIAGNOSIS AND ENROLLMENT PREDICATES ----
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
  # Translation gap workaround: replace is_hl_diagnosis() with inline %in% matching
  # Build both dotted and undotted ICD code lists for robust matching
  #
  # WHY match both dotted and undotted formats: PCORnet data quality varies by site.
  # Some sites store ICD-10 codes as "C81.00" (dotted), others as "C8100" (undotted).
  # Checking both formats ensures we don't miss HL patients due to formatting variance.
  hl_icd10_undotted <- ICD_CODES$hl_icd10
  hl_icd9_undotted <- ICD_CODES$hl_icd9

  dx_hl_patients <- get_pcornet_table("DIAGNOSIS") %>%
    filter(
      (DX_TYPE == "10" & (DX %in% hl_icd10_undotted | gsub("\\.", "", DX) %in% hl_icd10_undotted)) |
        (DX_TYPE == "09" & (DX %in% hl_icd9_undotted | gsub("\\.", "", DX) %in% hl_icd9_undotted))
    ) %>%
    distinct(ID)

  # Source 2: TUMOR_REGISTRY_ALL (Phase 14 optimization: use combined TR table)
  # TR1 uses HISTOLOGICAL_TYPE, TR2/TR3 use MORPH -- check both columns
  # NULL-guard: use tryCatch since get_pcornet_table() returns tbl_dbi (never NULL) in DuckDB mode
  tr_all_tbl <- tryCatch(get_pcornet_table("TUMOR_REGISTRY_ALL"), error = function(e) NULL)

  tr_all <- if (!is.null(tr_all_tbl)) {
    tr_cols <- colnames(tr_all_tbl)

    tr_hist <- if ("HISTOLOGICAL_TYPE" %in% tr_cols) {
      # Translation gap workaround: replace is_hl_histology() with substr()
      tr_all_tbl %>%
        filter(substr(as.character(HISTOLOGICAL_TYPE), 1, 4) %in% ICD_CODES$hl_histology) %>%
        distinct(ID)
    } else {
      tibble(ID = character())
    }

    tr_morph <- if ("MORPH" %in% tr_cols) {
      # Translation gap workaround: replace is_hl_histology() with substr()
      tr_all_tbl %>%
        filter(substr(as.character(MORPH), 1, 4) %in% ICD_CODES$hl_histology) %>%
        distinct(ID)
    } else {
      tibble(ID = character())
    }

    # Materialize before bind_rows (lazy query cannot be bound with tibbles)
    bind_rows(materialize(tr_hist), materialize(tr_morph)) %>% distinct(ID)
  } else {
    tibble(ID = character())
  }

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
  # Materialize enrolled_patients since we need nrow() for message and semi_join needs in-memory data
  enrolled_patients <- get_pcornet_table("ENROLLMENT") %>%
    distinct(ID) %>%
    materialize()

  message(glue("[Predicate] with_enrollment_period: {nrow(enrolled_patients)} patients with enrollment records"))

  patient_df %>%
    semi_join(enrolled_patients, by = "ID")
}

#' Exclude patients with missing or invalid payer category
#'
#' Returns only patients where PAYER_CATEGORY_PRIMARY is NOT NA and NOT "Missing".
#' Under AMC 8-category system, "Missing" consolidates the former "Unknown" and
#' "Unavailable" categories.
#'
#' @param patient_df Tibble with at least an ID column
#' @param payer_summary Payer summary tibble from 02_harmonize_payer.R
#' @return Filtered tibble containing only patients with valid payer category
#'
exclude_missing_payer <- function(patient_df, payer_summary) {
  valid_payer_patients <- payer_summary %>%
    filter(
      !is.na(PAYER_CATEGORY_PRIMARY) &
        !PAYER_CATEGORY_PRIMARY %in% c("Missing")
    ) %>%
    distinct(ID)

  message(glue("[Predicate] exclude_missing_payer: {nrow(valid_payer_patients)} patients with valid payer category"))

  patient_df %>%
    semi_join(valid_payer_patients, by = "ID")
}

# ==============================================================================
# SECTION 2: TREATMENT FLAG FUNCTIONS ----
# ==============================================================================
#
# WHY use semi_join for set-based filtering: semi_join is more efficient than
# filter() for large patient sets. It performs a hash-based membership test
# rather than row-by-row comparisons, and works cleanly with lazy DuckDB queries.

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

  # TUMOR_REGISTRY: chemo dates from combined TR (Phase 14 optimization)
  # TR1 uses CHEMO_START_DATE_SUMMARY, TR2/TR3 use DT_CHEMO
  # NULL-guard: use tryCatch for DuckDB compatibility
  tr_tbl <- tryCatch(get_pcornet_table("TUMOR_REGISTRY_ALL"), error = function(e) NULL)
  if (!is.null(tr_tbl)) {
    tr_chemo_cols <- intersect(
      c("CHEMO_START_DATE_SUMMARY", "DT_CHEMO"),
      colnames(tr_tbl)
    )
    if (length(tr_chemo_cols) > 0) {
      # Translation gap workaround: replace if_any with explicit OR
      if (length(tr_chemo_cols) == 1) {
        filter_expr <- paste0("!is.na(", tr_chemo_cols[1], ")")
      } else {
        filter_expr <- paste0("!is.na(", tr_chemo_cols, ")", collapse = " | ")
      }
      tr_chemo <- tr_tbl %>%
        filter(!!rlang::parse_expr(filter_expr)) %>%
        pull(ID) %>%
        unique()
      chemo_ids <- c(chemo_ids, tr_chemo)
      n_tr <- length(unique(tr_chemo))
    }
  }

  # PROCEDURES: chemo CPT/HCPCS, ICD-9-CM, ICD-10-PCS codes
  # Translation gap workaround for str_detect: two-step (lazy filter, materialize, R-side regex)
  chemo_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$chemo_icd10pcs_prefixes, collapse = "|"), ")")
  px_chemo <- character(0)
  proc_tbl <- tryCatch(get_pcornet_table("PROCEDURES"), error = function(e) NULL)
  if (!is.null(proc_tbl)) {
    # For ICD-10-PCS prefix matching, filter PX_TYPE first (lazy), then materialize for R-side str_detect
    px_10_chemo <- proc_tbl %>%
      filter(PX_TYPE == "10") %>%
      materialize() %>%
      filter(str_detect(PX, chemo_icd10pcs_rx)) %>%
      pull(ID)

    px_other_chemo <- proc_tbl %>%
      filter(
        (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) |
          (PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9)
      ) %>%
      distinct(ID) %>%
      pull(ID)

    px_chemo <- unique(c(px_10_chemo, px_other_chemo))
    chemo_ids <- c(chemo_ids, px_chemo)
  }
  n_px <- length(px_chemo)

  # PRESCRIBING: RXNORM_CUI matching for known chemo drugs (ABVD regimen components)
  rx_chemo <- character(0)
  rx_tbl <- tryCatch(get_pcornet_table("PRESCRIBING"), error = function(e) NULL)
  if (!is.null(rx_tbl)) {
    rx_chemo <- rx_tbl %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      filter(!is.na(RX_ORDER_DATE) | !is.na(RX_START_DATE)) %>%
      distinct(ID) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, rx_chemo)
  }
  n_rx <- length(rx_chemo)

  # --- Phase 9: Expanded treatment detection sources ---

  # DIAGNOSIS: Z51.11/Z51.12 (ICD-10), V58.11/V58.12 (ICD-9) per D-09
  dx_tbl <- tryCatch(get_pcornet_table("DIAGNOSIS"), error = function(e) NULL)
  if (!is.null(dx_tbl)) {
    dx_chemo <- dx_tbl %>%
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
  enc_tbl <- tryCatch(get_pcornet_table("ENCOUNTER"), error = function(e) NULL)
  if (!is.null(enc_tbl)) {
    drg_chemo <- enc_tbl %>%
      filter(DRG %in% TREATMENT_CODES$chemo_drg) %>%
      distinct(ID) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, drg_chemo)
    n_drg <- length(drg_chemo)
  }

  # DISPENSING: RXNORM_CUI matching per D-12 (same CUIs as PRESCRIBING)
  disp_tbl <- tryCatch(get_pcornet_table("DISPENSING"), error = function(e) NULL)
  if (!is.null(disp_tbl) && "RXNORM_CUI" %in% colnames(disp_tbl)) {
    disp_chemo <- disp_tbl %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      distinct(ID) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, disp_chemo)
    n_disp <- length(disp_chemo)
  }

  # MED_ADMIN: RXNORM_CUI matching per D-12 (same CUIs as PRESCRIBING)
  ma_tbl <- tryCatch(get_pcornet_table("MED_ADMIN"), error = function(e) NULL)
  if (!is.null(ma_tbl) && "RXNORM_CUI" %in% colnames(ma_tbl)) {
    ma_chemo <- ma_tbl %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      distinct(ID) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, ma_chemo)
    n_ma <- length(ma_chemo)
  }

  # PROCEDURES revenue codes: 0331/0332/0335 per D-11 (PX_TYPE = "RE")
  # Reuse proc_tbl from above if already fetched
  if (!is.null(proc_tbl)) {
    rev_chemo <- proc_tbl %>%
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

  # TUMOR_REGISTRY: radiation dates from combined TR (Phase 14 optimization)
  # TR1 uses RAD_START_DATE_SUMMARY, TR2/TR3 use DT_RAD
  tr_tbl <- tryCatch(get_pcornet_table("TUMOR_REGISTRY_ALL"), error = function(e) NULL)
  if (!is.null(tr_tbl)) {
    tr_rad_cols <- intersect(
      c("RAD_START_DATE_SUMMARY", "DT_RAD"),
      colnames(tr_tbl)
    )
    if (length(tr_rad_cols) > 0) {
      # Translation gap workaround: replace if_any with explicit OR
      if (length(tr_rad_cols) == 1) {
        filter_expr <- paste0("!is.na(", tr_rad_cols[1], ")")
      } else {
        filter_expr <- paste0("!is.na(", tr_rad_cols, ")", collapse = " | ")
      }
      tr_rad <- tr_tbl %>%
        filter(!!rlang::parse_expr(filter_expr)) %>%
        pull(ID) %>%
        unique()
      rad_ids <- c(rad_ids, tr_rad)
      n_tr <- length(unique(tr_rad))
    }
  }

  # PROCEDURES: radiation CPT, ICD-9-CM, ICD-10-PCS codes
  # Translation gap workaround for str_detect: two-step (lazy filter, materialize, R-side regex)
  rad_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$radiation_icd10pcs_prefixes, collapse = "|"), ")")
  px_rad <- character(0)
  proc_tbl <- tryCatch(get_pcornet_table("PROCEDURES"), error = function(e) NULL)
  if (!is.null(proc_tbl)) {
    px_10_rad <- proc_tbl %>%
      filter(PX_TYPE == "10") %>%
      materialize() %>%
      filter(str_detect(PX, rad_icd10pcs_rx)) %>%
      pull(ID)

    px_other_rad <- proc_tbl %>%
      filter(
        (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$radiation_cpt) |
          (PX_TYPE == "09" & PX %in% TREATMENT_CODES$radiation_icd9)
      ) %>%
      distinct(ID) %>%
      pull(ID)

    px_rad <- unique(c(px_10_rad, px_other_rad))
    rad_ids <- c(rad_ids, px_rad)
  }
  n_px <- length(px_rad)

  # --- Phase 9: Expanded treatment detection sources ---

  # DIAGNOSIS: Z51.0 (ICD-10), V58.0 (ICD-9) per D-09
  dx_tbl <- tryCatch(get_pcornet_table("DIAGNOSIS"), error = function(e) NULL)
  if (!is.null(dx_tbl)) {
    dx_rad <- dx_tbl %>%
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
  enc_tbl <- tryCatch(get_pcornet_table("ENCOUNTER"), error = function(e) NULL)
  if (!is.null(enc_tbl)) {
    drg_rad <- enc_tbl %>%
      filter(DRG %in% TREATMENT_CODES$radiation_drg) %>%
      distinct(ID) %>%
      pull(ID)
    rad_ids <- c(rad_ids, drg_rad)
    n_drg <- length(drg_rad)
  }

  # PROCEDURES revenue codes: 0330/0333 per D-11 (PX_TYPE = "RE")
  if (!is.null(proc_tbl)) {
    rev_rad <- proc_tbl %>%
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

  # TUMOR_REGISTRY: SCT evidence from combined TR (Phase 14 optimization)
  # TR1 uses HEMATOLOGIC_TRANSPLANT_AND_ENDOC (code), TR2/TR3 use date columns
  tr_tbl <- tryCatch(get_pcornet_table("TUMOR_REGISTRY_ALL"), error = function(e) NULL)
  if (!is.null(tr_tbl)) {
    tr_cols <- colnames(tr_tbl)

    # Check for TR1's code-based field
    if ("HEMATOLOGIC_TRANSPLANT_AND_ENDOC" %in% tr_cols) {
      tr1_sct <- tr_tbl %>%
        filter(!is.na(HEMATOLOGIC_TRANSPLANT_AND_ENDOC) &
          HEMATOLOGIC_TRANSPLANT_AND_ENDOC != "" &
          HEMATOLOGIC_TRANSPLANT_AND_ENDOC != "00") %>%
        pull(ID)
      sct_ids <- c(sct_ids, tr1_sct)
    }

    # Check for TR2/TR3 date columns (DT_HTE, DT_SCT, etc.)
    sct_date_cols <- c(
      "DT_HTE", "DT_SCT", "SCT_DATE", "BMT_DATE",
      "TRANSPLANT_DATE", "HCT_DATE", "DT_TRANSPLANT"
    )
    tr_sct_date_cols <- intersect(sct_date_cols, tr_cols)
    if (length(tr_sct_date_cols) > 0) {
      # Translation gap workaround: replace if_any with explicit OR
      if (length(tr_sct_date_cols) == 1) {
        filter_expr <- paste0("!is.na(", tr_sct_date_cols[1], ")")
      } else {
        filter_expr <- paste0("!is.na(", tr_sct_date_cols, ")", collapse = " | ")
      }
      tr_sct_dates <- tr_tbl %>%
        filter(!!rlang::parse_expr(filter_expr)) %>%
        pull(ID)
      sct_ids <- c(sct_ids, tr_sct_dates)
    }

    # Aggregate TR source count (check against materialized TR IDs)
    tr_all_ids <- tr_tbl %>%
      pull(ID) %>%
      unique()
    n_tr <- length(unique(sct_ids[sct_ids %in% tr_all_ids]))
  }

  # PROCEDURES: SCT CPT, ICD-9-CM, ICD-10-PCS codes
  px_sct <- character(0)
  proc_tbl <- tryCatch(get_pcornet_table("PROCEDURES"), error = function(e) NULL)
  if (!is.null(proc_tbl)) {
    px_sct <- proc_tbl %>%
      filter(
        (PX_TYPE == "CH" & PX %in% c(TREATMENT_CODES$sct_cpt, TREATMENT_CODES$sct_hcpcs)) |
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
  dx_tbl <- tryCatch(get_pcornet_table("DIAGNOSIS"), error = function(e) NULL)
  if (!is.null(dx_tbl)) {
    dx_sct <- dx_tbl %>%
      filter(DX_TYPE == "10" & DX %in% TREATMENT_CODES$sct_dx_icd10) %>%
      distinct(ID) %>%
      pull(ID)
    sct_ids <- c(sct_ids, dx_sct)
    n_dx <- length(dx_sct)
  }

  # ENCOUNTER: DRGs 014, 016, 017 per D-10
  enc_tbl <- tryCatch(get_pcornet_table("ENCOUNTER"), error = function(e) NULL)
  if (!is.null(enc_tbl)) {
    drg_sct <- enc_tbl %>%
      filter(DRG %in% TREATMENT_CODES$sct_drg) %>%
      distinct(ID) %>%
      pull(ID)
    sct_ids <- c(sct_ids, drg_sct)
    n_drg <- length(drg_sct)
  }

  # PROCEDURES revenue codes: 0362/0815 per D-11 (PX_TYPE = "RE")
  if (!is.null(proc_tbl)) {
    rev_sct <- proc_tbl %>%
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
