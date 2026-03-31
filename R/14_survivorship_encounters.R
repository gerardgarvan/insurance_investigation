# ==============================================================================
# 14_survivorship_encounters.R -- 4-Level Survivorship Encounter Classification
# ==============================================================================
#
# Implements D-05 through D-10 from VariableDetails.xlsx:
# Classifies post-diagnosis encounters into 4 progressively restrictive levels.
#
# HIERARCHY (each level is a strict subset of the previous):
#
#   Level 1: ENC_NONACUTE_CARE
#     AV + TH encounters that occurred AFTER the HL diagnosis date (D-03)
#     "Non-acute care" per PCORnet CDM: Ambulatory Visit + Telehealth
#
#   Level 2: ENC_CANCER_RELATED  (D-07)
#     Level 1 encounters where the SAME encounter also has an HL diagnosis code
#     (C81.xx ICD-10-CM, 201.xx ICD-9-CM) -- NOT all cancer codes
#
#   Level 3: ENC_CANCER_PROVIDER  (D-10)
#     Level 2 encounters where the visit PROVIDER has oncology NUCC taxonomy code
#     PROVIDER_SPECIALTIES$cancer_oncology (Hematology, Hematology/Oncology, etc.)
#     NULL-safe: if pcornet$PROVIDER is NULL, Level 3 and 4 are forced to 0
#
#   Level 4: ENC_SURVIVORSHIP  (D-09)
#     Level 3 encounters where the SAME encounter also has a personal history
#     ICD code (V87.4x/V15.3 ICD-9, Z92.2x/Z92.3 ICD-10) per SURVIVORSHIP_CODES
#
# KEY DECISIONS:
#   D-07: Cancer-related check uses HL-SPECIFIC codes ONLY (C81/201), not all cancer
#   D-09: Personal history codes span ICD-9 and ICD-10; DX_TYPE filter is required
#   D-10: NUCC taxonomy code matching is exact %in% (not regex/prefix)
#   Pitfall 2: PROVIDERID may be NULL on many ENCOUNTER rows -- left_join, not inner_join
#   Pitfall 4: Personal history codes cross ICD eras; DX_TYPE filter is mandatory
#
# INPUT:
#   post_dx_date_map  -- tibble(ID, first_hl_dx_date)  -- one row per cohort patient
#   pcornet$ENCOUNTER -- ENCOUNTERID, ID, ENC_TYPE, ADMIT_DATE, PROVIDERID
#   pcornet$DIAGNOSIS -- ENCOUNTERID, ID, DX, DX_TYPE
#   pcornet$PROVIDER  -- PROVIDERID, PROVIDER_SPECIALTY_PRIM (may be NULL if file missing)
#
# OUTPUT:
#   tibble with columns (3 per level x 4 levels = 12 columns):
#     HAD_ENC_NONACUTE_CARE, N_ENC_NONACUTE_CARE, FIRST_ENC_NONACUTE_CARE_DATE
#     HAD_ENC_CANCER_RELATED, N_ENC_CANCER_RELATED, FIRST_ENC_CANCER_RELATED_DATE
#     HAD_ENC_CANCER_PROVIDER, N_ENC_CANCER_PROVIDER, FIRST_ENC_CANCER_PROVIDER_DATE
#     HAD_ENC_SURVIVORSHIP, N_ENC_SURVIVORSHIP, FIRST_ENC_SURVIVORSHIP_DATE
#
# USAGE (from 04_build_cohort.R):
#   post_dx_date_map <- cohort %>% select(ID, first_hl_dx_date)
#   surv_flags <- classify_survivorship_encounters(post_dx_date_map)
#   cohort <- cohort %>% left_join(surv_flags, by = "ID")
#
# Requirement: SVENC-02, SVENC-03
# Phase: 10, Plan: 03
# ==============================================================================

library(dplyr)
library(glue)

# ==============================================================================
# MAIN CLASSIFICATION FUNCTION
# ==============================================================================

#' Classify post-diagnosis encounters into 4 survivorship encounter levels
#'
#' @param post_dx_date_map tibble with columns ID (character) and
#'   first_hl_dx_date (Date). One row per cohort patient.
#'
#' @return Wide tibble (one row per patient in post_dx_date_map) with 12 columns:
#'   HAD_*/N_*/FIRST_*_DATE for all 4 encounter levels.
#'   Patients with no qualifying encounters at a level receive 0 / NA.
#'
#' @details
#'   Accesses pcornet$ENCOUNTER, pcornet$DIAGNOSIS, pcornet$PROVIDER,
#'   ICD_CODES, SURVIVORSHIP_CODES, and PROVIDER_SPECIALTIES from the
#'   calling environment (loaded by 00_config.R + 01_load_pcornet.R).
#'
#'   NULL-safe for pcornet$PROVIDER: if the PROVIDER table is unavailable,
#'   Level 3 and Level 4 are set to 0 for all patients and a warning is logged.
classify_survivorship_encounters <- function(post_dx_date_map) {

  stopifnot(
    is.data.frame(post_dx_date_map),
    "ID" %in% names(post_dx_date_map),
    "first_hl_dx_date" %in% names(post_dx_date_map)
  )

  n_cohort <- nrow(post_dx_date_map)
  message(glue("[Survivorship] Classifying encounters for {n_cohort} cohort patients"))

  # ----------------------------------------------------------------------------
  # LEVEL 1: Non-acute care encounters (ENC_NONACUTE_CARE)
  # AV (Ambulatory Visit) + TH (Telehealth) post-diagnosis
  # D-03: post-diagnosis = ADMIT_DATE strictly after first_hl_dx_date
  # ----------------------------------------------------------------------------

  enc_av_th <- pcornet$ENCOUNTER %>%
    filter(ENC_TYPE %in% c("AV", "TH")) %>%
    inner_join(post_dx_date_map, by = "ID") %>%
    filter(!is.na(ADMIT_DATE), !is.na(first_hl_dx_date),
           ADMIT_DATE > first_hl_dx_date) %>%
    select(ENCOUNTERID, ID, ADMIT_DATE, PROVIDERID)

  level1_per_patient <- enc_av_th %>%
    group_by(ID) %>%
    summarise(
      N_ENC_NONACUTE_CARE      = n(),
      FIRST_ENC_NONACUTE_CARE_DATE = min(ADMIT_DATE, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(HAD_ENC_NONACUTE_CARE = 1L)

  n1 <- nrow(level1_per_patient)
  message(glue("[Survivorship] Level 1 (Non-acute AV+TH): {n1} patients"))

  # ----------------------------------------------------------------------------
  # LEVEL 2: Cancer-related visits (ENC_CANCER_RELATED)
  # Level 1 encounters that ALSO have an HL diagnosis code on the same encounter
  # D-07: HL codes ONLY -- C81.xx ICD-10, 201.xx ICD-9
  # ----------------------------------------------------------------------------

  hl_dx_on_encounter <- pcornet$DIAGNOSIS %>%
    filter(
      (DX_TYPE == "10" & DX %in% ICD_CODES$hl_icd10) |
      (DX_TYPE == "09" & DX %in% ICD_CODES$hl_icd9)
    ) %>%
    distinct(ENCOUNTERID)

  level2_encounters <- enc_av_th %>%
    semi_join(hl_dx_on_encounter, by = "ENCOUNTERID")

  level2_per_patient <- level2_encounters %>%
    group_by(ID) %>%
    summarise(
      N_ENC_CANCER_RELATED      = n(),
      FIRST_ENC_CANCER_RELATED_DATE = min(ADMIT_DATE, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(HAD_ENC_CANCER_RELATED = 1L)

  n2 <- nrow(level2_per_patient)
  message(glue("[Survivorship] Level 2 (Cancer-related, HL DX on encounter): {n2} patients"))

  # ----------------------------------------------------------------------------
  # LEVEL 3: Cancer provider visits (ENC_CANCER_PROVIDER)
  # Level 2 encounters seen by an oncology provider (D-10: NUCC taxonomy codes)
  # NULL-safe: if PROVIDER table is missing, force Level 3/4 to 0
  # Pitfall 2: PROVIDERID may be NULL in many ENCOUNTER rows -- use left_join
  # ----------------------------------------------------------------------------

  if (is.null(pcornet$PROVIDER)) {
    warning(glue(
      "[Survivorship] pcornet$PROVIDER is NULL. ",
      "Level 3 (ENC_CANCER_PROVIDER) and Level 4 (ENC_SURVIVORSHIP) ",
      "will be set to 0 for all patients. ",
      "Ensure PROVIDER.csv is present if provider-level classification is needed."
    ))

    # Force all Level 3 / Level 4 columns to zero
    level3_per_patient <- tibble(
      ID = character(0),
      N_ENC_CANCER_PROVIDER       = integer(0),
      FIRST_ENC_CANCER_PROVIDER_DATE = as.Date(character(0)),
      HAD_ENC_CANCER_PROVIDER     = integer(0)
    )
    level4_per_patient <- tibble(
      ID = character(0),
      N_ENC_SURVIVORSHIP          = integer(0),
      FIRST_ENC_SURVIVORSHIP_DATE = as.Date(character(0)),
      HAD_ENC_SURVIVORSHIP        = integer(0)
    )
    n3 <- 0L
    n4 <- 0L

  } else {

    # Log encounters where PROVIDERID is NA (transparency for Pitfall 2)
    n_null_providerid <- sum(is.na(level2_encounters$PROVIDERID))
    if (n_null_providerid > 0) {
      message(glue(
        "[Survivorship] Level 3 note: {n_null_providerid} Level 2 encounters ",
        "have NULL PROVIDERID and will not match any provider specialty."
      ))
    }

    # left_join to preserve all Level 2 encounters even when PROVIDERID is NULL
    level3_encounters <- level2_encounters %>%
      left_join(
        pcornet$PROVIDER %>% select(PROVIDERID, PROVIDER_SPECIALTY_PRIM),
        by = "PROVIDERID"
      ) %>%
      filter(PROVIDER_SPECIALTY_PRIM %in% PROVIDER_SPECIALTIES$cancer_oncology)

    level3_per_patient <- level3_encounters %>%
      group_by(ID) %>%
      summarise(
        N_ENC_CANCER_PROVIDER       = n(),
        FIRST_ENC_CANCER_PROVIDER_DATE = min(ADMIT_DATE, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      mutate(HAD_ENC_CANCER_PROVIDER = 1L)

    n3 <- nrow(level3_per_patient)
    message(glue("[Survivorship] Level 3 (Cancer provider, NUCC oncology): {n3} patients"))

    # --------------------------------------------------------------------------
    # LEVEL 4: Survivorship visits (ENC_SURVIVORSHIP)
    # Level 3 encounters that ALSO have a personal history ICD code (D-09)
    # Pitfall 4: Codes span ICD-9 (V87.4x, V15.3) and ICD-10 (Z92.2x, Z92.3)
    #            Must filter by DX_TYPE to avoid cross-era false matches
    # --------------------------------------------------------------------------

    has_personal_hx <- pcornet$DIAGNOSIS %>%
      filter(
        (DX_TYPE == "09" & DX %in% SURVIVORSHIP_CODES$personal_history_icd9) |
        (DX_TYPE == "10" & DX %in% SURVIVORSHIP_CODES$personal_history_icd10)
      ) %>%
      distinct(ENCOUNTERID)

    level4_encounters <- level3_encounters %>%
      semi_join(has_personal_hx, by = "ENCOUNTERID")

    level4_per_patient <- level4_encounters %>%
      group_by(ID) %>%
      summarise(
        N_ENC_SURVIVORSHIP          = n(),
        FIRST_ENC_SURVIVORSHIP_DATE = min(ADMIT_DATE, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      mutate(HAD_ENC_SURVIVORSHIP = 1L)

    n4 <- nrow(level4_per_patient)
    message(glue("[Survivorship] Level 4 (Survivorship, personal history DX): {n4} patients"))
  }

  # ----------------------------------------------------------------------------
  # ASSEMBLY
  # Left join all levels onto the full cohort patient list.
  # Patients with no qualifying encounters at a level receive 0 / NA (via coalesce).
  # ----------------------------------------------------------------------------

  result <- post_dx_date_map %>%
    select(ID) %>%
    # Level 1
    left_join(level1_per_patient, by = "ID") %>%
    mutate(
      HAD_ENC_NONACUTE_CARE        = coalesce(HAD_ENC_NONACUTE_CARE, 0L),
      N_ENC_NONACUTE_CARE          = coalesce(N_ENC_NONACUTE_CARE, 0L)
      # FIRST_ENC_NONACUTE_CARE_DATE stays NA when no encounter
    ) %>%
    # Level 2
    left_join(level2_per_patient, by = "ID") %>%
    mutate(
      HAD_ENC_CANCER_RELATED       = coalesce(HAD_ENC_CANCER_RELATED, 0L),
      N_ENC_CANCER_RELATED         = coalesce(N_ENC_CANCER_RELATED, 0L)
    ) %>%
    # Level 3
    left_join(level3_per_patient, by = "ID") %>%
    mutate(
      HAD_ENC_CANCER_PROVIDER      = coalesce(HAD_ENC_CANCER_PROVIDER, 0L),
      N_ENC_CANCER_PROVIDER        = coalesce(N_ENC_CANCER_PROVIDER, 0L)
    ) %>%
    # Level 4
    left_join(level4_per_patient, by = "ID") %>%
    mutate(
      HAD_ENC_SURVIVORSHIP         = coalesce(HAD_ENC_SURVIVORSHIP, 0L),
      N_ENC_SURVIVORSHIP           = coalesce(N_ENC_SURVIVORSHIP, 0L)
    ) %>%
    # Enforce column order (HAD / N / DATE for each level)
    select(
      ID,
      HAD_ENC_NONACUTE_CARE,      N_ENC_NONACUTE_CARE,      FIRST_ENC_NONACUTE_CARE_DATE,
      HAD_ENC_CANCER_RELATED,     N_ENC_CANCER_RELATED,     FIRST_ENC_CANCER_RELATED_DATE,
      HAD_ENC_CANCER_PROVIDER,    N_ENC_CANCER_PROVIDER,    FIRST_ENC_CANCER_PROVIDER_DATE,
      HAD_ENC_SURVIVORSHIP,       N_ENC_SURVIVORSHIP,       FIRST_ENC_SURVIVORSHIP_DATE
    )

  message(glue(
    "[Survivorship] Classification complete. ",
    "{n_cohort} patients returned with 12 encounter classification columns."
  ))

  return(result)
}

# ==============================================================================
# End of script
# ==============================================================================
