# ==============================================================================
# 13_surveillance.R
# Surveillance Modality Detection -- Phase 10
#
# Purpose:
#   Implements D-01 through D-04 from Phase 10 CONTEXT.md.
#   Detects post-diagnosis surveillance events for 9 modalities (procedure-based
#   from PROCEDURES table) and 10 lab types (LOINC-based from LAB_RESULT_CM).
#
#   All detection is restricted to events AFTER the patient's first HL diagnosis
#   date (D-03). Missing tables (LAB_RESULT_CM, PROCEDURES) are handled gracefully
#   with zero-valued flags (D-04).
#
# Output columns per modality/lab (D-04):
#   HAD_{NAME}          -- integer 0/1 flag
#   FIRST_{NAME}_DATE   -- date of first post-diagnosis event
#   N_{NAME}            -- count of post-diagnosis events
#
# Modalities (9, procedure-based):
#   MAMMOGRAM, BREAST_MRI, ECHO, STRESS_TEST, ECG, MUGA, PFT
#   + combined TSH (procedure + lab) and CBC (procedure + lab)
#
# Labs (8 LOINC-only):
#   CRP, ALT, AST, ALP, GGT, BILIRUBIN, PLATELETS, FOBT
#   + TSH_LAB and CBC_LAB (also used in combined TSH/CBC above)
#
# Entry point:
#   assemble_surveillance_flags(post_dx_date_map)
#   post_dx_date_map <- cohort %>% select(ID, first_hl_dx_date)
#
# Dependencies:
#   - pcornet environment (list with $PROCEDURES and $LAB_RESULT_CM)
#   - SURVEILLANCE_CODES from 00_config.R
#   - LAB_CODES from 00_config.R
#   - dplyr (loaded via source chain)
#   - glue (loaded via source chain)
# ==============================================================================

library(dplyr)
library(glue)

# ==============================================================================
# SECTION 1: Generic procedure-based modality detection helper
# ==============================================================================

#' Detect a surveillance modality from the PROCEDURES table
#'
#' @param post_dx_date_map tibble(ID, first_hl_dx_date) -- cohort patients with
#'   their first HL diagnosis date. Drives both cohort restriction and post-dx
#'   date filtering.
#' @param modality_name Character scalar. Used for column naming (uppercased).
#'   e.g. "MAMMOGRAM" produces HAD_MAMMOGRAM, FIRST_MAMMOGRAM_DATE, N_MAMMOGRAM.
#' @param code_vectors Named list. Each name is a code type ("cpt", "hcpcs",
#'   "icd10pcs", "icd9") and each value is a character vector of codes to match.
#'   Mapped to PCORnet PX_TYPE: cpt/hcpcs -> "CH", icd10pcs -> "10", icd9 -> "09".
#'
#' @return tibble with columns ID, HAD_{modality_name}, FIRST_{modality_name}_DATE,
#'   N_{modality_name}. One row per patient in post_dx_date_map. Patients with
#'   no matching post-dx procedures receive 0 / NA / 0.
detect_procedure_modality <- function(post_dx_date_map, modality_name, code_vectors) {
  had_col   <- paste0("HAD_", modality_name)
  date_col  <- paste0("FIRST_", modality_name, "_DATE")
  count_col <- paste0("N_", modality_name)

  # Default all-zero result (graceful handling for missing PROCEDURES table)
  result <- post_dx_date_map %>%
    select(ID) %>%
    mutate(
      !!had_col   := 0L,
      !!date_col  := as.Date(NA),
      !!count_col := 0L
    )

  if (is.null(pcornet$PROCEDURES)) {
    message(glue("[Surveillance] PROCEDURES not loaded -- skipping {modality_name}"))
    return(result)
  }

  # Map code type names to PCORnet PX_TYPE values
  type_map <- c(cpt = "CH", hcpcs = "CH", icd10pcs = "10", icd9 = "09", re = "RE")

  # Collect all matching procedure rows across code types
  px_hits <- NULL
  for (code_type in names(code_vectors)) {
    px_type <- type_map[[code_type]]
    if (is.null(px_type)) next
    codes <- code_vectors[[code_type]]
    if (length(codes) == 0) next
    hits <- pcornet$PROCEDURES %>%
      filter(PX_TYPE == px_type, PX %in% codes)
    px_hits <- bind_rows(px_hits, hits)
  }

  if (is.null(px_hits) || nrow(px_hits) == 0) {
    message(glue("[Surveillance] {modality_name}: 0 procedure hits in PROCEDURES"))
    return(result)
  }

  # Restrict to cohort patients and post-diagnosis events only (D-03)
  px_summary <- px_hits %>%
    inner_join(post_dx_date_map, by = "ID") %>%
    filter(!is.na(PX_DATE), PX_DATE > first_hl_dx_date) %>%
    group_by(ID) %>%
    summarise(
      !!date_col  := min(PX_DATE, na.rm = TRUE),
      !!count_col := n(),
      .groups = "drop"
    )

  result <- post_dx_date_map %>%
    select(ID) %>%
    left_join(px_summary, by = "ID") %>%
    mutate(
      !!had_col   := as.integer(!is.na(!!sym(date_col))),
      !!count_col := coalesce(!!sym(count_col), 0L)
    )

  n_had <- sum(result[[had_col]], na.rm = TRUE)
  message(glue("[Surveillance] {modality_name}: {n_had} patients with post-dx procedure evidence"))
  result
}

# ==============================================================================
# SECTION 2: Generic lab-based modality detection helper
# ==============================================================================

#' Detect a surveillance lab type from the LAB_RESULT_CM table
#'
#' @param post_dx_date_map tibble(ID, first_hl_dx_date) -- cohort patients with
#'   their first HL diagnosis date.
#' @param lab_name Character scalar. Used for column naming (uppercased).
#'   e.g. "CRP" produces HAD_CRP, FIRST_CRP_DATE, N_CRP.
#' @param loinc_codes Character vector of LOINC codes to match against LAB_LOINC.
#'
#' @return tibble with columns ID, HAD_{lab_name}, FIRST_{lab_name}_DATE,
#'   N_{lab_name}. One row per patient in post_dx_date_map. Patients with
#'   no matching post-dx labs receive 0 / NA / 0.
detect_lab_modality <- function(post_dx_date_map, lab_name, loinc_codes) {
  had_col   <- paste0("HAD_", lab_name)
  date_col  <- paste0("FIRST_", lab_name, "_DATE")
  count_col <- paste0("N_", lab_name)

  # Default all-zero result (graceful handling for missing LAB_RESULT_CM table)
  result <- post_dx_date_map %>%
    select(ID) %>%
    mutate(
      !!had_col   := 0L,
      !!date_col  := as.Date(NA),
      !!count_col := 0L
    )

  if (is.null(pcornet$LAB_RESULT_CM)) {
    message(glue("[Surveillance] LAB_RESULT_CM not loaded -- skipping {lab_name}"))
    return(result)
  }

  if (length(loinc_codes) == 0) {
    message(glue("[Surveillance] {lab_name}: no LOINC codes provided"))
    return(result)
  }

  # Best available date: SPECIMEN_DATE preferred, fall back to LAB_ORDER_DATE
  lab_hits <- pcornet$LAB_RESULT_CM %>%
    filter(LAB_LOINC %in% loinc_codes) %>%
    inner_join(post_dx_date_map, by = "ID") %>%
    mutate(lab_date = coalesce(SPECIMEN_DATE, LAB_ORDER_DATE)) %>%
    filter(!is.na(lab_date), lab_date > first_hl_dx_date) %>%
    group_by(ID) %>%
    summarise(
      !!date_col  := min(lab_date, na.rm = TRUE),
      !!count_col := n(),
      .groups = "drop"
    )

  result <- post_dx_date_map %>%
    select(ID) %>%
    left_join(lab_hits, by = "ID") %>%
    mutate(
      !!had_col   := as.integer(!is.na(!!sym(date_col))),
      !!count_col := coalesce(!!sym(count_col), 0L)
    )

  n_had <- sum(result[[had_col]], na.rm = TRUE)
  message(glue("[Surveillance] {lab_name}: {n_had} patients with post-dx lab results"))
  result
}

# ==============================================================================
# SECTION 3: Procedure-based wrapper functions (7 modalities -- no LOINC overlap)
# ==============================================================================

#' Mammogram detection (CPT + ICD-10-PCS)
detect_mammogram <- function(post_dx_date_map) {
  codes <- list()
  if (length(SURVEILLANCE_CODES$mammogram_cpt) > 0)     codes$cpt     <- SURVEILLANCE_CODES$mammogram_cpt
  if (length(SURVEILLANCE_CODES$mammogram_icd10pcs) > 0) codes$icd10pcs <- SURVEILLANCE_CODES$mammogram_icd10pcs
  detect_procedure_modality(post_dx_date_map, "MAMMOGRAM", codes)
}

#' Breast MRI detection (CPT + HCPCS + ICD-10-PCS)
detect_breast_mri <- function(post_dx_date_map) {
  codes <- list()
  if (length(SURVEILLANCE_CODES$breast_mri_cpt) > 0)     codes$cpt     <- SURVEILLANCE_CODES$breast_mri_cpt
  if (length(SURVEILLANCE_CODES$breast_mri_hcpcs) > 0)   codes$hcpcs   <- SURVEILLANCE_CODES$breast_mri_hcpcs
  if (length(SURVEILLANCE_CODES$breast_mri_icd10pcs) > 0) codes$icd10pcs <- SURVEILLANCE_CODES$breast_mri_icd10pcs
  detect_procedure_modality(post_dx_date_map, "BREAST_MRI", codes)
}

#' Echocardiogram detection (CPT + ICD-10-PCS)
#' Note: echo_icd10_dx is a diagnosis screening Z-code, not a procedure code --
#' it cannot be matched via PROCEDURES PX_TYPE and is omitted here.
detect_echo <- function(post_dx_date_map) {
  codes <- list()
  if (length(SURVEILLANCE_CODES$echo_cpt) > 0)     codes$cpt     <- SURVEILLANCE_CODES$echo_cpt
  if (length(SURVEILLANCE_CODES$echo_icd10pcs) > 0) codes$icd10pcs <- SURVEILLANCE_CODES$echo_icd10pcs
  detect_procedure_modality(post_dx_date_map, "ECHO", codes)
}

#' Stress test detection (CPT -- nuclear cardiology SPECT)
detect_stress_test <- function(post_dx_date_map) {
  codes <- list()
  if (length(SURVEILLANCE_CODES$stress_test_cpt) > 0) codes$cpt <- SURVEILLANCE_CODES$stress_test_cpt
  detect_procedure_modality(post_dx_date_map, "STRESS_TEST", codes)
}

#' Electrocardiogram detection (CPT)
#' Note: ecg_icd10_dx is a diagnosis screening Z-code, not a procedure code --
#' omitted from procedure matching.
detect_ecg <- function(post_dx_date_map) {
  codes <- list()
  if (length(SURVEILLANCE_CODES$ecg_cpt) > 0) codes$cpt <- SURVEILLANCE_CODES$ecg_cpt
  detect_procedure_modality(post_dx_date_map, "ECG", codes)
}

#' MUGA scan detection (CPT + ICD-10-PCS)
detect_muga <- function(post_dx_date_map) {
  codes <- list()
  if (length(SURVEILLANCE_CODES$muga_cpt) > 0)     codes$cpt     <- SURVEILLANCE_CODES$muga_cpt
  if (length(SURVEILLANCE_CODES$muga_icd10pcs) > 0) codes$icd10pcs <- SURVEILLANCE_CODES$muga_icd10pcs
  detect_procedure_modality(post_dx_date_map, "MUGA", codes)
}

#' Pulmonary function test detection (CPT)
#' Note: pft_icd10_dx is a diagnosis screening Z-code, not a procedure code --
#' omitted from procedure matching.
detect_pft <- function(post_dx_date_map) {
  codes <- list()
  if (length(SURVEILLANCE_CODES$pft_cpt) > 0) codes$cpt <- SURVEILLANCE_CODES$pft_cpt
  detect_procedure_modality(post_dx_date_map, "PFT", codes)
}

# ==============================================================================
# SECTION 4: TSH and CBC -- separate procedure and lab sub-functions, then
#            combined functions that merge both sources
# ==============================================================================

#' TSH procedure sub-function (CPT + HCPCS)
detect_tsh_procedure <- function(post_dx_date_map) {
  codes <- list()
  if (length(SURVEILLANCE_CODES$tsh_cpt) > 0)   codes$cpt   <- SURVEILLANCE_CODES$tsh_cpt
  if (length(SURVEILLANCE_CODES$tsh_hcpcs) > 0) codes$hcpcs <- SURVEILLANCE_CODES$tsh_hcpcs
  detect_procedure_modality(post_dx_date_map, "TSH", codes)
}

#' TSH lab sub-function (LOINC -- LAB_RESULT_CM)
detect_tsh_lab <- function(post_dx_date_map) {
  loinc <- c(
    SURVEILLANCE_CODES$tsh_loinc,
    LAB_CODES$tsh_loinc
  ) %>% unique()
  detect_lab_modality(post_dx_date_map, "TSH", loinc)
}

#' Combined TSH detection (procedure OR lab)
#' Patients who had TSH via either PROCEDURES (CPT/HCPCS) or LAB_RESULT_CM (LOINC)
#' are counted. Date is the earliest event across both sources. Count is summed.
detect_tsh <- function(post_dx_date_map) {
  px_result  <- detect_tsh_procedure(post_dx_date_map)
  lab_result <- detect_tsh_lab(post_dx_date_map)

  combined <- post_dx_date_map %>%
    select(ID) %>%
    left_join(
      px_result  %>% select(ID,
                            HAD_TSH_PX    = HAD_TSH,
                            FIRST_TSH_PX_DATE  = FIRST_TSH_DATE,
                            N_TSH_PX      = N_TSH),
      by = "ID"
    ) %>%
    left_join(
      lab_result %>% select(ID,
                            HAD_TSH_LAB   = HAD_TSH,
                            FIRST_TSH_LAB_DATE = FIRST_TSH_DATE,
                            N_TSH_LAB     = N_TSH),
      by = "ID"
    ) %>%
    mutate(
      HAD_TSH        = as.integer(
        coalesce(HAD_TSH_PX, 0L) == 1L | coalesce(HAD_TSH_LAB, 0L) == 1L
      ),
      FIRST_TSH_DATE = pmin(FIRST_TSH_PX_DATE, FIRST_TSH_LAB_DATE, na.rm = TRUE),
      N_TSH          = coalesce(N_TSH_PX, 0L) + coalesce(N_TSH_LAB, 0L)
    ) %>%
    select(ID, HAD_TSH, FIRST_TSH_DATE, N_TSH)

  n_had <- sum(combined$HAD_TSH, na.rm = TRUE)
  message(glue("[Surveillance] TSH (combined): {n_had} patients with post-dx TSH evidence"))
  combined
}

#' CBC procedure sub-function (CPT + HCPCS)
detect_cbc_procedure <- function(post_dx_date_map) {
  codes <- list()
  if (length(SURVEILLANCE_CODES$cbc_cpt) > 0)   codes$cpt   <- SURVEILLANCE_CODES$cbc_cpt
  if (length(SURVEILLANCE_CODES$cbc_hcpcs) > 0) codes$hcpcs <- SURVEILLANCE_CODES$cbc_hcpcs
  detect_procedure_modality(post_dx_date_map, "CBC", codes)
}

#' CBC lab sub-function (LOINC -- LAB_RESULT_CM)
detect_cbc_lab <- function(post_dx_date_map) {
  loinc <- c(
    SURVEILLANCE_CODES$cbc_loinc,
    LAB_CODES$cbc_loinc
  ) %>% unique()
  detect_lab_modality(post_dx_date_map, "CBC", loinc)
}

#' Combined CBC detection (procedure OR lab)
#' Same merge logic as detect_tsh().
detect_cbc <- function(post_dx_date_map) {
  px_result  <- detect_cbc_procedure(post_dx_date_map)
  lab_result <- detect_cbc_lab(post_dx_date_map)

  combined <- post_dx_date_map %>%
    select(ID) %>%
    left_join(
      px_result  %>% select(ID,
                            HAD_CBC_PX    = HAD_CBC,
                            FIRST_CBC_PX_DATE  = FIRST_CBC_DATE,
                            N_CBC_PX      = N_CBC),
      by = "ID"
    ) %>%
    left_join(
      lab_result %>% select(ID,
                            HAD_CBC_LAB   = HAD_CBC,
                            FIRST_CBC_LAB_DATE = FIRST_CBC_DATE,
                            N_CBC_LAB     = N_CBC),
      by = "ID"
    ) %>%
    mutate(
      HAD_CBC        = as.integer(
        coalesce(HAD_CBC_PX, 0L) == 1L | coalesce(HAD_CBC_LAB, 0L) == 1L
      ),
      FIRST_CBC_DATE = pmin(FIRST_CBC_PX_DATE, FIRST_CBC_LAB_DATE, na.rm = TRUE),
      N_CBC          = coalesce(N_CBC_PX, 0L) + coalesce(N_CBC_LAB, 0L)
    ) %>%
    select(ID, HAD_CBC, FIRST_CBC_DATE, N_CBC)

  n_had <- sum(combined$HAD_CBC, na.rm = TRUE)
  message(glue("[Surveillance] CBC (combined): {n_had} patients with post-dx CBC evidence"))
  combined
}

# ==============================================================================
# SECTION 5: Lab-only wrapper functions (no procedure-based counterpart)
# ==============================================================================

#' C-reactive protein (LOINC)
detect_crp <- function(post_dx_date_map) {
  detect_lab_modality(post_dx_date_map, "CRP", LAB_CODES$crp_loinc)
}

#' Alanine aminotransferase -- ALT (LOINC)
detect_alt <- function(post_dx_date_map) {
  detect_lab_modality(post_dx_date_map, "ALT", LAB_CODES$alt_loinc)
}

#' Aspartate aminotransferase -- AST (LOINC)
detect_ast <- function(post_dx_date_map) {
  detect_lab_modality(post_dx_date_map, "AST", LAB_CODES$ast_loinc)
}

#' Alkaline phosphatase -- ALP (LOINC)
detect_alp <- function(post_dx_date_map) {
  detect_lab_modality(post_dx_date_map, "ALP", LAB_CODES$alp_loinc)
}

#' Gamma-glutamyl transferase -- GGT (LOINC)
detect_ggt <- function(post_dx_date_map) {
  detect_lab_modality(post_dx_date_map, "GGT", LAB_CODES$ggt_loinc)
}

#' Bilirubin (LOINC -- total + fractions)
detect_bilirubin <- function(post_dx_date_map) {
  detect_lab_modality(post_dx_date_map, "BILIRUBIN", LAB_CODES$bilirubin_loinc)
}

#' Platelets (LOINC -- includes APRI index and PDF derived values)
detect_platelets <- function(post_dx_date_map) {
  detect_lab_modality(post_dx_date_map, "PLATELETS", LAB_CODES$platelets_loinc)
}

#' Fecal occult blood test -- FOBT (LOINC)
detect_fobt <- function(post_dx_date_map) {
  detect_lab_modality(post_dx_date_map, "FOBT", LAB_CODES$fobt_loinc)
}

# ==============================================================================
# SECTION 6: Assembly function -- combine all modalities into one wide tibble
# ==============================================================================

#' Assemble all surveillance flags into a single wide tibble
#'
#' Calls all detect_*() functions and left-joins their output into a single
#' wide tibble. One row per patient in post_dx_date_map.
#'
#' Columns produced (3 per modality/lab, 51 total + ID):
#'   Procedure-based (7): MAMMOGRAM, BREAST_MRI, ECHO, STRESS_TEST, ECG, MUGA, PFT
#'   Combined (2):        TSH, CBC
#'   Lab-only (8):        CRP, ALT, AST, ALP, GGT, BILIRUBIN, PLATELETS, FOBT
#'
#' @param post_dx_date_map tibble(ID, first_hl_dx_date). Typically constructed as:
#'   post_dx_date_map <- cohort %>% select(ID, first_hl_dx_date)
#'
#' @return Wide tibble (nrow = nrow(post_dx_date_map)) with all HAD_*/FIRST_*_DATE/N_*
#'   columns. Safe to left_join onto hl_cohort by ID.
assemble_surveillance_flags <- function(post_dx_date_map) {
  message("\n--- Surveillance Modality Detection ---")

  result <- post_dx_date_map %>% select(ID)

  # 7 procedure-only modalities
  result <- result %>%
    left_join(detect_mammogram(post_dx_date_map),   by = "ID") %>%
    left_join(detect_breast_mri(post_dx_date_map),  by = "ID") %>%
    left_join(detect_echo(post_dx_date_map),         by = "ID") %>%
    left_join(detect_stress_test(post_dx_date_map), by = "ID") %>%
    left_join(detect_ecg(post_dx_date_map),          by = "ID") %>%
    left_join(detect_muga(post_dx_date_map),         by = "ID") %>%
    left_join(detect_pft(post_dx_date_map),          by = "ID")

  # 2 combined (procedure + lab) modalities
  result <- result %>%
    left_join(detect_tsh(post_dx_date_map), by = "ID") %>%
    left_join(detect_cbc(post_dx_date_map), by = "ID")

  # 8 lab-only modalities
  result <- result %>%
    left_join(detect_crp(post_dx_date_map),       by = "ID") %>%
    left_join(detect_alt(post_dx_date_map),       by = "ID") %>%
    left_join(detect_ast(post_dx_date_map),       by = "ID") %>%
    left_join(detect_alp(post_dx_date_map),       by = "ID") %>%
    left_join(detect_ggt(post_dx_date_map),       by = "ID") %>%
    left_join(detect_bilirubin(post_dx_date_map), by = "ID") %>%
    left_join(detect_platelets(post_dx_date_map), by = "ID") %>%
    left_join(detect_fobt(post_dx_date_map),      by = "ID")

  n_cols <- ncol(result) - 1L  # exclude ID
  message(glue(
    "[Surveillance] assemble_surveillance_flags: {n_cols} surveillance columns",
    " for {nrow(result)} patients"
  ))
  result
}

# ==============================================================================
# End of 13_surveillance.R
# ==============================================================================
