# ==============================================================================
# 26_treatment_episodes.R -- Treatment Episode Start/Stop Dates
# ==============================================================================
# Purpose:     Per-episode start/stop dates with episode length, historical date
#              flagging, and triggering codes for each treatment episode.
#
# Inputs:      PCORnet treatment tables + treatment_durations.rds from R/25
#
# Outputs:     cache/outputs/treatment_episodes.rds, output/treatment_episodes.xlsx,
#              per-type CSVs (chemotherapy_episodes.csv, etc.)
#
# Dependencies: R/00_config.R, R/01_load_pcornet.R, R/25_treatment_durations.R
#
# Requirements: Phase 46 episode-level detail with triggering codes
#
# Decision traceability:
#   D-01: historical episodes included with historical_flag boolean column
#   D-02: historical cutoff = before 2012-01-01
#   D-03: episode flagged historical when ALL dates < 2012-01-01 (using episode_stop)
#   D-04: single-date historical episodes get start=stop, length=0
#   D-05: new script alongside Phase 43 (Phase 43 unchanged)
#   D-06: new file R/26_treatment_episodes.R
#   D-07: outputs RDS + styled xlsx + per-type CSVs
#   D-08: columns: patient_id, treatment_type, episode_number, episode_start,
#          episode_stop, episode_length_days, distinct_dates_in_episode, historical_flag
#   D-09: one row per patient per treatment type per episode
#   D-10: 90-day window from episode start (not gap between consecutive dates)
#   D-11: all chemo codes pooled (from Phase 43)
#   D-12: four treatment types (from Phase 43)
#   D-13: pre-2000 dates are real tumor registry data
#
# Phase 46 additions:
#   D-46-06: triggering_codes column (comma-separated bare codes) added as column 8
#   D-46-07: all codes matching TREATMENT_CODES within episode window included
#   D-46-08: bare codes only — no PX_TYPE prefix
#   D-46-09: triggering_codes appears in both CSV and xlsx output
#
# Phase 76 additions:
#   D-76-01: Tumor registry (TR) source removed from chemo, radiation, SCT extraction
#   D-76-02: TR data accuracy 8-32% vs 95-100% claims (SEER literature)
#   D-76-03: Episode count assertion with >20% drop threshold
#   D-76-04: EPISODE_COUNT_BASELINE = NULL until first post-removal run
#   D-76-05: Pre-removal coverage analysis in output/source_coverage_analysis.xlsx
#
# Outputs:
#   - RDS artifact: one row per patient per treatment type per episode
#   - Styled xlsx: Summary sheet + per-type detail sheets + Historical Summary
#   - Per-type CSVs: chemotherapy_episodes.csv, radiation_episodes.csv,
#                    sct_episodes.csv, immunotherapy_episodes.csv
# =============================================================================


# SECTION 1: SETUP AND CONFIGURATION ----

# WHY historical date flagging: Dates before 2012-01-01 may indicate data quality
# issues (backloaded tumor registry data, retrospective coding errors). Historical
# flag enables filtering for contemporary treatment pattern analysis without
# discarding old data entirely.

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(purrr)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")

# Reuse Phase 25's assign_episode_ids() and stack_and_dedup() functions
source("R/25_treatment_durations.R")

# Output paths
OUTPUT_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
OUTPUT_DETAIL_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds")
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "treatment_episodes.xlsx")

# Per D-02: historical cutoff date (matches OneFlorida+ data extraction period start)
HISTORICAL_CUTOFF <- as.Date("2012-01-01")


# SECTION 2: EXTRACTION FUNCTIONS WITH TRIGGERING CODES ---

# These functions mirror the logic in R/43a_treatment_durations.R but return
# a 3-column tibble: ID, treatment_date, triggering_code.
# Per D-46-08: bare codes only (PX column for PROCEDURES, DX for DIAGNOSIS, etc.)
# Phase 76: Tumor registry (TR) sources removed from chemo, radiation, SCT extraction.
# Claims-based sources provide 95-100% accuracy vs TR's 8-32% (SEER literature).
# Pre-removal coverage analysis documented in output/source_coverage_analysis.xlsx.
# R/43a_treatment_durations.R is NOT modified; these are new functions in R/44.

#' Stack sources with triggering_code and ENCOUNTERID, dedup on (ID, treatment_date, triggering_code, ENCOUNTERID)
#'
#' Phase 60: Updated to handle 4-column input (ID, treatment_date, triggering_code, ENCOUNTERID).
#' Per D-46-07: distinct(ID, treatment_date, triggering_code, ENCOUNTERID) — 4-column dedup —
#' preserves multiple codes on the same date and different encounter IDs while removing exact duplicates.
#'
#' @param sources Named list of tibbles with columns ID, treatment_date, triggering_code, ENCOUNTERID
#' @param type_name Character. Treatment type name for logging
#' @return 4-column tibble: ID, treatment_date, triggering_code, ENCOUNTERID
stack_and_dedup_with_codes <- function(sources, type_name) {
  non_null <- compact(sources)

  if (length(non_null) == 0) {
    return(tibble(
      ID = character(0),
      treatment_date = as.Date(character(0)),
      triggering_code = character(0),
      ENCOUNTERID = character(0)
    ))
  }

  stacked <- bind_rows(non_null) %>%
    mutate(treatment_date = as.Date(treatment_date)) %>%
    filter(!is.na(treatment_date))

  # 4-column distinct: preserves multiple codes/encounters on same date (D-46-07 + Phase 60 D-01)
  result <- stacked %>%
    distinct(ID, treatment_date, triggering_code, ENCOUNTERID) %>%
    arrange(ID, treatment_date)

  message(glue("  {type_name} with codes: {n_distinct(result$ID)} patients, {nrow(result)} distinct (ID, date, code, ENCOUNTERID) rows"))
  result
}

#' Extract all chemotherapy dates with triggering codes
#' Mirrors extract_chemo_dates() from R/43a_treatment_durations.R but adds triggering_code
extract_chemo_dates_with_codes <- function() {
  chemo_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$chemo_icd10pcs_prefixes, collapse = "|"), ")")

  # 1. PROCEDURES: CPT/HCPCS, ICD-9-CM, ICD-10-PCS, revenue — bare code = PX
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
      select(ID, treatment_date = PX_DATE, triggering_code = PX, ENCOUNTERID) %>%
      collect()
  }

  # 2. PRESCRIBING: RXNORM_CUI — bare RxNorm CUI is a valid code per D-46-08
  rx_dates <- NULL
  if (!is.null(get_pcornet_table("PRESCRIBING")) &&
    "RXNORM_CUI" %in% colnames(get_pcornet_table("PRESCRIBING"))) {
    rx_dates <- get_pcornet_table("PRESCRIBING") %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      mutate(treatment_date = coalesce(RX_ORDER_DATE, RX_START_DATE)) %>%
      filter(!is.na(treatment_date)) %>%
      select(ID, treatment_date, triggering_code = RXNORM_CUI, ENCOUNTERID) %>%
      collect()
  }

  # 3. DIAGNOSIS: Z51.11 (ICD-10), V58.11 (ICD-9) — bare DX code
  dx_dates <- NULL
  if (!is.null(get_pcornet_table("DIAGNOSIS"))) {
    dx_dates <- get_pcornet_table("DIAGNOSIS") %>%
      filter(
        (DX_TYPE == "10" & DX %in% TREATMENT_CODES$chemo_dx_icd10) |
          (DX_TYPE == "09" & DX %in% TREATMENT_CODES$chemo_dx_icd9)
      ) %>%
      filter(!is.na(DX_DATE)) %>%
      select(ID, treatment_date = DX_DATE, triggering_code = DX, ENCOUNTERID) %>%
      collect()
  }

  # 4. ENCOUNTER: chemo DRGs — bare DRG numeric code
  drg_dates <- NULL
  if (!is.null(get_pcornet_table("ENCOUNTER"))) {
    drg_dates <- get_pcornet_table("ENCOUNTER") %>%
      filter(DRG %in% TREATMENT_CODES$chemo_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      select(ID, treatment_date = ADMIT_DATE, triggering_code = DRG, ENCOUNTERID) %>%
      collect()
  }

  # 5. DISPENSING: RXNORM_CUI — bare RxNorm CUI
  disp_dates <- NULL
  if (!is.null(get_pcornet_table("DISPENSING")) &&
    "RXNORM_CUI" %in% colnames(get_pcornet_table("DISPENSING"))) {
    disp_dates <- get_pcornet_table("DISPENSING") %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      filter(!is.na(DISPENSE_DATE)) %>%
      select(ID, treatment_date = DISPENSE_DATE, triggering_code = RXNORM_CUI, ENCOUNTERID) %>%
      collect()
  }

  # 6. MED_ADMIN: RXNORM_CUI — bare RxNorm CUI
  ma_dates <- NULL
  if (!is.null(get_pcornet_table("MED_ADMIN")) &&
    "RXNORM_CUI" %in% colnames(get_pcornet_table("MED_ADMIN"))) {
    ma_dates <- get_pcornet_table("MED_ADMIN") %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      filter(!is.na(MEDADMIN_START_DATE)) %>%
      select(ID, treatment_date = MEDADMIN_START_DATE, triggering_code = RXNORM_CUI, ENCOUNTERID) %>%
      collect()
  }

  # Phase 76: Tumor registry source removed — claims-based sources only
  # TR data accuracy 8-32% per SEER literature vs 95-100% for EHR claims
  # Coverage analysis documented in output/source_coverage_analysis.xlsx

  stack_and_dedup_with_codes(
    sources = list(
      PX = px_dates, RX = rx_dates, DX = dx_dates,
      DRG = drg_dates, DISP = disp_dates, MA = ma_dates
    ),
    type_name = "Chemotherapy"
  )
}

#' Extract all radiation dates with triggering codes
#' Mirrors extract_radiation_dates() from R/43a_treatment_durations.R but adds triggering_code
extract_radiation_dates_with_codes <- function() {
  rad_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$radiation_icd10pcs_prefixes, collapse = "|"), ")")

  # 1. PROCEDURES: CPT, ICD-9-CM, ICD-10-PCS, revenue — bare code = PX
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
      select(ID, treatment_date = PX_DATE, triggering_code = PX, ENCOUNTERID) %>%
      collect()
  }

  # 2. DIAGNOSIS: Z51.0 (ICD-10), V58.0 (ICD-9) — bare DX code
  dx_dates <- NULL
  if (!is.null(get_pcornet_table("DIAGNOSIS"))) {
    dx_dates <- get_pcornet_table("DIAGNOSIS") %>%
      filter(
        (DX_TYPE == "10" & DX %in% TREATMENT_CODES$radiation_dx_icd10) |
          (DX_TYPE == "09" & DX %in% TREATMENT_CODES$radiation_dx_icd9)
      ) %>%
      filter(!is.na(DX_DATE)) %>%
      select(ID, treatment_date = DX_DATE, triggering_code = DX, ENCOUNTERID) %>%
      collect()
  }

  # 3. ENCOUNTER: DRG 849 — bare DRG code
  drg_dates <- NULL
  if (!is.null(get_pcornet_table("ENCOUNTER"))) {
    drg_dates <- get_pcornet_table("ENCOUNTER") %>%
      filter(DRG %in% TREATMENT_CODES$radiation_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      select(ID, treatment_date = ADMIT_DATE, triggering_code = DRG, ENCOUNTERID) %>%
      collect()
  }

  # Phase 76: Tumor registry source removed — claims-based sources only
  # TR data accuracy 8-32% per SEER literature vs 95-100% for EHR claims
  # Coverage analysis documented in output/source_coverage_analysis.xlsx

  stack_and_dedup_with_codes(
    sources = list(PX = px_dates, DX = dx_dates, DRG = drg_dates),
    type_name = "Radiation"
  )
}

#' Extract proton therapy dates with triggering codes from 1 source (PX)
#' Simpler than radiation -- only PROCEDURES CPT codes (no DX, DRG, TR, Revenue)
#' @return Tibble with columns: ID, treatment_date, triggering_code, ENCOUNTERID
extract_proton_dates_with_codes <- function() {
  # PROCEDURES: CPT codes only
  px_dates <- NULL
  if (!is.null(get_pcornet_table("PROCEDURES"))) {
    px_dates <- get_pcornet_table("PROCEDURES") %>%
      filter(PX_TYPE == "CH" & PX %in% TREATMENT_CODES$proton_cpt) %>%
      filter(!is.na(PX_DATE)) %>%
      select(ID, treatment_date = PX_DATE, triggering_code = PX, ENCOUNTERID) %>%
      collect()
  }

  stack_and_dedup_with_codes(
    sources = list(PX = px_dates),
    type_name = "Proton Therapy"
  )
}

#' Extract all SCT dates with triggering codes from 2 sources (PX, DRG)
#' Mirrors extract_sct_dates() from R/43a_treatment_durations.R but adds triggering_code
extract_sct_dates_with_codes <- function() {
  # 1. PROCEDURES: CPT/HCPCS, ICD-9-CM, ICD-10-PCS (exact match), revenue — bare code = PX
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
      select(ID, treatment_date = PX_DATE, triggering_code = PX, ENCOUNTERID) %>%
      collect()
  }

  # 2. ENCOUNTER: DRGs 014, 016, 017 — bare DRG code
  drg_dates <- NULL
  if (!is.null(get_pcornet_table("ENCOUNTER"))) {
    drg_dates <- get_pcornet_table("ENCOUNTER") %>%
      filter(DRG %in% TREATMENT_CODES$sct_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      select(ID, treatment_date = ADMIT_DATE, triggering_code = DRG, ENCOUNTERID) %>%
      collect()
  }

  # Phase 76: Tumor registry source removed — claims-based sources only
  # TR data accuracy 8-32% per SEER literature vs 95-100% for EHR claims
  # Coverage analysis documented in output/source_coverage_analysis.xlsx

  stack_and_dedup_with_codes(
    sources = list(PX = px_dates, DRG = drg_dates),
    type_name = "SCT"
  )
}

#' Extract all immunotherapy dates with triggering codes
#' Mirrors extract_immunotherapy_dates() from R/43a_treatment_durations.R but adds triggering_code
extract_immunotherapy_dates_with_codes <- function() {
  cart_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$cart_icd10pcs_prefixes, collapse = "|"), ")")

  # 1. PROCEDURES: HCPCS J-codes + ICD-10-PCS CAR T-cell codes — bare code = PX
  px_dates <- NULL
  if (!is.null(get_pcornet_table("PROCEDURES"))) {
    px_dates <- get_pcornet_table("PROCEDURES") %>%
      filter(
        (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$immunotherapy_hcpcs) |
          (PX_TYPE == "10" & str_detect(PX, cart_icd10pcs_rx))
      ) %>%
      filter(!is.na(PX_DATE)) %>%
      select(ID, treatment_date = PX_DATE, triggering_code = PX, ENCOUNTERID) %>%
      collect()
  }

  # 2. ENCOUNTER: DRG 018 — bare DRG code
  drg_dates <- NULL
  if (!is.null(get_pcornet_table("ENCOUNTER"))) {
    drg_dates <- get_pcornet_table("ENCOUNTER") %>%
      filter(DRG %in% TREATMENT_CODES$immunotherapy_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      select(ID, treatment_date = ADMIT_DATE, triggering_code = DRG, ENCOUNTERID) %>%
      collect()
  }

  # 3. PRESCRIBING: RXNORM_CUI — bare RxNorm CUI
  rx_dates <- NULL
  if (!is.null(get_pcornet_table("PRESCRIBING")) &&
    "RXNORM_CUI" %in% colnames(get_pcornet_table("PRESCRIBING"))) {
    rx_dates <- get_pcornet_table("PRESCRIBING") %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$immunotherapy_rxnorm) %>%
      mutate(treatment_date = coalesce(RX_ORDER_DATE, RX_START_DATE)) %>%
      filter(!is.na(treatment_date)) %>%
      select(ID, treatment_date, triggering_code = RXNORM_CUI, ENCOUNTERID) %>%
      collect()
  }

  # 4. DISPENSING: RXNORM_CUI — bare RxNorm CUI
  disp_dates <- NULL
  if (!is.null(get_pcornet_table("DISPENSING")) &&
    "RXNORM_CUI" %in% colnames(get_pcornet_table("DISPENSING"))) {
    disp_dates <- get_pcornet_table("DISPENSING") %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$immunotherapy_rxnorm) %>%
      filter(!is.na(DISPENSE_DATE)) %>%
      select(ID, treatment_date = DISPENSE_DATE, triggering_code = RXNORM_CUI, ENCOUNTERID) %>%
      collect()
  }

  # 5. MED_ADMIN: RXNORM_CUI — bare RxNorm CUI
  ma_dates <- NULL
  if (!is.null(get_pcornet_table("MED_ADMIN")) &&
    "RXNORM_CUI" %in% colnames(get_pcornet_table("MED_ADMIN"))) {
    ma_dates <- get_pcornet_table("MED_ADMIN") %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$immunotherapy_rxnorm) %>%
      filter(!is.na(MEDADMIN_START_DATE)) %>%
      select(ID, treatment_date = MEDADMIN_START_DATE, triggering_code = RXNORM_CUI, ENCOUNTERID) %>%
      collect()
  }

  # 6. DIAGNOSIS: Z51.12 (ICD-10), V58.12 (ICD-9) — bare DX code
  dx_dates <- NULL
  if (!is.null(get_pcornet_table("DIAGNOSIS"))) {
    dx_dates <- get_pcornet_table("DIAGNOSIS") %>%
      filter(
        (DX_TYPE == "10" & DX %in% TREATMENT_CODES$immunotherapy_dx_icd10) |
          (DX_TYPE == "09" & DX %in% TREATMENT_CODES$immunotherapy_dx_icd9)
      ) %>%
      filter(!is.na(DX_DATE)) %>%
      select(ID, treatment_date = DX_DATE, triggering_code = DX, ENCOUNTERID) %>%
      collect()
  }

  stack_and_dedup_with_codes(
    sources = list(PX = px_dates, DRG = drg_dates, RX = rx_dates,
                   DISP = disp_dates, MA = ma_dates, DX = dx_dates),
    type_name = "Immunotherapy"
  )
}

#' Dispatch to the appropriate type-specific extraction function with triggering codes
#' @param type Character. One of "Chemotherapy", "Radiation", "Proton Therapy", "SCT", "Immunotherapy"
#' @return Tibble with columns: ID, treatment_date, triggering_code
extract_dates_with_codes <- function(type) {
  message(glue("\n--- Extracting {type} dates (with triggering codes) ---"))

  if (type == "Chemotherapy") {
    return(extract_chemo_dates_with_codes())
  } else if (type == "Radiation") {
    return(extract_radiation_dates_with_codes())
  } else if (type == "Proton Therapy") {
    return(extract_proton_dates_with_codes())
  } else if (type == "SCT") {
    return(extract_sct_dates_with_codes())
  } else if (type == "Immunotherapy") {
    return(extract_immunotherapy_dates_with_codes())
  } else {
    stop(glue("Unknown treatment type: {type}"))
  }
}


# --- SECTION 3: EPISODE CALCULATION FUNCTION ---

# assign_episode_ids() is defined in R/43a_treatment_durations.R (sourced above)

#' Calculate detailed episode-level data with triggering codes and encounter IDs
#'
#' Phase 60: Updated to accept 4-column input (ID, treatment_date, triggering_code, ENCOUNTERID)
#' and aggregate encounter IDs per episode.
#'
#' Adapted from Phase 44 original calculate_episodes_detailed() — now accepts
#' dates_df with 4 columns and aggregates triggering codes AND encounter IDs per episode
#' via paste(sort(unique(na.omit(...))), collapse=",").
#'
#' Per D-46-07: ALL matching codes within the episode date window are included.
#' Per D-46-08: bare codes only (no type prefix).
#' Per Phase 60 D-03, D-04: encounter_ids aggregated per episode, NULL/missing omitted.
#'
#' @param dates_df Tibble with columns ID, treatment_date, triggering_code, ENCOUNTERID
#' @param gap_threshold Integer. Max days from episode start to define cycle boundary
#' @return Tibble with one row per patient per episode: patient_id, episode_number,
#'   episode_start, episode_stop, episode_length_days, distinct_dates_in_episode,
#'   historical_flag, triggering_codes, encounter_ids
calculate_episodes_detailed <- function(dates_df, gap_threshold = GAP_THRESHOLD) {
  # Empty input guard — must include triggering_codes and encounter_ids per Phase 60
  if (nrow(dates_df) == 0) {
    return(tibble(
      patient_id = character(0),
      episode_number = integer(0),
      episode_start = as.Date(character(0)),
      episode_stop = as.Date(character(0)),
      episode_length_days = numeric(0),
      distinct_dates_in_episode = integer(0),
      historical_flag = logical(0),
      triggering_codes = character(0),
      encounter_ids = character(0)
    ))
  }

  # Core pipeline: window-based episode splitting (date - episode_start >= threshold)
  dates_df %>%
    group_by(ID) %>%
    arrange(treatment_date, .by_group = TRUE) %>%
    mutate(
      episode_id = assign_episode_ids(treatment_date, gap_threshold)
    ) %>%
    # Per-episode summary (THIS is the output level for Phase 44)
    group_by(ID, episode_id) %>%
    summarise(
      episode_start = min(treatment_date),
      episode_stop = max(treatment_date),
      episode_length_days = as.numeric(max(treatment_date) - min(treatment_date)),
      distinct_dates_in_episode = n_distinct(treatment_date),
      # D-46-07: ALL matching codes in episode window; na.omit for TR/DRG/date-only sources
      triggering_codes = paste(sort(unique(na.omit(triggering_code))), collapse = ","),
      # Phase 60 D-03, D-04: aggregate encounter IDs per episode
      encounter_ids = paste(sort(unique(na.omit(ENCOUNTERID))), collapse = ","),
      .groups = "drop"
    ) %>%
    # Add episode_number per patient (per D-08, D-09)
    group_by(ID) %>%
    mutate(episode_number = row_number()) %>%
    ungroup() %>%
    # Add historical_flag per D-02/D-03
    # (using episode_stop < HISTORICAL_CUTOFF because if the LAST date is pre-2012,
    #  ALL dates are pre-2012)
    mutate(historical_flag = episode_stop < HISTORICAL_CUTOFF) %>%
    # Final select — triggering_codes, encounter_ids as last columns per Phase 60
    select(
      patient_id = ID,
      episode_number,
      episode_start,
      episode_stop,
      episode_length_days,
      distinct_dates_in_episode,
      historical_flag,
      triggering_codes,
      encounter_ids
    )
}


#' Annotate raw date+code+ENCOUNTERID rows with episode context
#'
#' Phase 60: Updated to handle 4-column input (ID, treatment_date, triggering_code, ENCOUNTERID).
#'
#' Takes the raw 4-column data (before episode collapsing) and the episode-level
#' output, assigns episode IDs to each raw row, then joins episode context.
#' Returns one row per unique (patient, date, code, ENCOUNTERID) — the detail-level output.
#'
#' @param dates_df Tibble with columns: ID, treatment_date, triggering_code, ENCOUNTERID
#' @param episodes_df Tibble from calculate_episodes_detailed() with episode-level data
#' @param gap_threshold Integer. Max days from episode start (must match episodes_df)
#' @return Tibble with columns: patient_id, treatment_date, triggering_code, ENCOUNTERID,
#'   episode_number, episode_start, episode_stop, historical_flag
annotate_detail_with_episodes <- function(dates_df, episodes_df, gap_threshold = GAP_THRESHOLD) {
  if (nrow(dates_df) == 0 || nrow(episodes_df) == 0) {
    return(tibble(
      patient_id = character(0),
      treatment_date = as.Date(character(0)),
      triggering_code = character(0),
      ENCOUNTERID = character(0),
      episode_number = integer(0),
      episode_start = as.Date(character(0)),
      episode_stop = as.Date(character(0)),
      historical_flag = logical(0)
    ))
  }

  # Assign episode IDs to each raw row (same logic as calculate_episodes_detailed)
  dated_with_episodes <- dates_df %>%
    group_by(ID) %>%
    arrange(treatment_date, .by_group = TRUE) %>%
    mutate(episode_id = assign_episode_ids(treatment_date, gap_threshold)) %>%
    ungroup()

  # Build episode lookup from episodes_df (which has episode_number per patient)
  # episodes_df has one row per (patient_id, episode_number) with episode_start/stop
  # We need to map (ID, episode_id) -> episode context
  # episode_id is sequential per patient, matching episode_number
  episode_lookup <- episodes_df %>%
    select(patient_id, episode_number, episode_start, episode_stop, historical_flag)

  # Join: episode_id in dated_with_episodes corresponds to episode_number in episodes_df
  dated_with_episodes %>%
    left_join(
      episode_lookup,
      by = c("ID" = "patient_id", "episode_id" = "episode_number")
    ) %>%
    select(
      patient_id = ID,
      treatment_date,
      triggering_code,
      ENCOUNTERID,
      episode_number = episode_id,
      episode_start,
      episode_stop,
      historical_flag
    ) %>%
    arrange(patient_id, treatment_date)
}


# --- SECTION 4: CONSOLE SUMMARY FUNCTION ---

#' Log episode statistics for a treatment type
#' @param episodes_df Tibble from calculate_episodes_detailed()
#' @param type_name Character. Treatment type name for logging
log_episode_stats <- function(episodes_df, type_name) {
  if (nrow(episodes_df) == 0) {
    message(glue("\n  {type_name} Summary: 0 episodes (no data)"))
    return(invisible(NULL))
  }

  n_patients <- n_distinct(episodes_df$patient_id)
  n_episodes <- nrow(episodes_df)
  n_historical <- sum(episodes_df$historical_flag)
  pct_historical <- round(100 * mean(episodes_df$historical_flag), 1)
  median_length <- median(episodes_df$episode_length_days)
  median_dates <- median(episodes_df$distinct_dates_in_episode)

  # Count episodes with at least one triggering code
  n_with_codes <- sum(nchar(episodes_df$triggering_codes) > 0)
  pct_with_codes <- round(100 * n_with_codes / n_episodes, 1)

  # Phase 60: Count episodes with at least one encounter ID
  n_with_encounters <- sum(nchar(episodes_df$encounter_ids) > 0, na.rm = TRUE)
  pct_with_encounters <- round(100 * n_with_encounters / n_episodes, 1)

  message(glue("\n  {type_name} Summary:"))
  message(glue("    Patients: {n_patients}"))
  message(glue("    Episodes: {n_episodes} ({n_historical} historical, {pct_historical}%)"))
  message(glue("    Episode length (days): median={median_length}"))
  message(glue("    Dates per episode: median={median_dates}"))
  message(glue("    Episodes with triggering codes: {n_with_codes} ({pct_with_codes}%)"))
  message(glue("    Episodes with encounter IDs: {n_with_encounters} ({pct_with_encounters}%)"))

  invisible(NULL)
}


# --- SECTION 5: MAIN EXECUTION LOOP ---

message("=== Phase 44: Treatment Episode Start/Stop Dates ===\n")

# Phase 76: Episode count baseline for >20% drop detection after TR source removal
# Update these values after first successful post-TR-removal pipeline run.
# Set to NULL to skip assertion (e.g., during initial calibration run).
EPISODE_COUNT_BASELINE <- NULL

episodes_list <- list()
detail_list <- list()

for (type in TREATMENT_TYPES) {
  # Use new extract_dates_with_codes() instead of extract_all_dates()
  # Returns 3 columns: ID, treatment_date, triggering_code
  dates_df <- extract_dates_with_codes(type)

  # Calculate per-episode detail (now includes triggering_codes aggregation)
  episodes_df <- calculate_episodes_detailed(dates_df)

  # Phase 76: Guard against unexpected episode count drop after TR removal
  # Percentage-based threshold (>20%) prevents silent data loss from source changes.
  # Baseline will be populated after first post-TR-removal run.
  # If assertion fires, investigate whether upstream cohort changes or source
  # modifications caused the drop — do NOT simply increase the threshold.
  if (exists("EPISODE_COUNT_BASELINE") && !is.null(EPISODE_COUNT_BASELINE[[type]])) {
    expected <- EPISODE_COUNT_BASELINE[[type]]
    actual <- nrow(episodes_df)
    pct_delta <- abs(actual - expected) / expected * 100
    checkmate::assert_true(
      pct_delta <= 20,
      .var.name = glue(
        "[R/26] {type} episode count delta {round(pct_delta, 1)}% exceeds 20% threshold ",
        "(expected ~{expected}, got {actual})"
      )
    )
  }

  # Add treatment type column
  episodes_df <- episodes_df %>%
    mutate(treatment_type = type)

  # Log summary stats
  log_episode_stats(episodes_df, type)

  episodes_list[[type]] <- episodes_df

  # Build detail-level data: one row per (patient, date, code) with episode context
  detail_df <- annotate_detail_with_episodes(dates_df, episodes_df) %>%
    mutate(treatment_type = type)
  detail_list[[type]] <- detail_df
}

# Combine all types into single dataset — triggering_codes and encounter_ids flow through bind_rows automatically
all_episodes <- bind_rows(episodes_list) %>%
  select(
    patient_id, treatment_type, episode_number, episode_start, episode_stop,
    episode_length_days, distinct_dates_in_episode, historical_flag, triggering_codes, encounter_ids
  )

# Combine detail-level data
all_detail <- bind_rows(detail_list) %>%
  select(
    patient_id, treatment_type, treatment_date, triggering_code, ENCOUNTERID,
    episode_number, episode_start, episode_stop, historical_flag
  )


# --- SECTION 5B: JOIN DRUG NAMES TO EPISODE DETAIL ---

message("\n--- Joining drug names to episode detail ---")
DRUG_LOOKUP_RDS <- file.path(CONFIG$cache$outputs_dir, "drug_name_lookup.rds")

# SAFE-01: File existence validated by existing file.exists() guard
if (file.exists(DRUG_LOOKUP_RDS)) {
  drug_lookup <- readRDS(DRUG_LOOKUP_RDS)
  message(glue("  Loaded {nrow(drug_lookup)} drug name lookups"))
} else {
  warning("drug_name_lookup.rds not found. Run R/60_drug_name_resolution.R first. Drug names will be NA.")
  drug_lookup <- tibble(code = character(0), drug_name = character(0))
}

# Join drug name to detail level (one row per patient/date/code)
# Per D-12: left_join on triggering_code = code
all_detail <- all_detail %>%
  left_join(
    drug_lookup %>% select(code, drug_name),
    by = c("triggering_code" = "code")
  )

n_with_names <- sum(!is.na(all_detail$drug_name))
n_chemo_rows <- sum(all_detail$treatment_type == "Chemotherapy")
message(glue("  Drug names joined: {n_with_names} detail rows have drug names ({n_chemo_rows} chemotherapy rows total)"))

# --- Phase 114: Fill blank drug_names from reference Excel MEDICATION_LOOKUP ---
# Per D-01: Fill blank drug_names where triggering_codes can be mapped to reference Excel.
# Per D-02: Use Medication column from reference Excel (not route/dosage/full description).
# Per D-03: Map triggering_codes to reference Excel to fill blanks.
# CRITICAL: Fill at detail grain BEFORE aggregation (Pitfall 3 avoidance).

n_blank_before <- sum(is.na(all_detail$drug_name) | all_detail$drug_name == "", na.rm = TRUE)

if (length(MEDICATION_LOOKUP) > 0) {
  medication_ref <- tibble(
    triggering_code = names(MEDICATION_LOOKUP),
    ref_medication = unname(MEDICATION_LOOKUP)
  )

  all_detail <- all_detail %>%
    left_join(medication_ref, by = "triggering_code") %>%
    mutate(
      drug_name = dplyr::coalesce(
        if_else(is.na(drug_name) | drug_name == "", NA_character_, drug_name),
        ref_medication
      )
    ) %>%
    select(-ref_medication)

  n_blank_after <- sum(is.na(all_detail$drug_name) | all_detail$drug_name == "", na.rm = TRUE)
  n_filled <- n_blank_before - n_blank_after

  message(glue("  Phase 114 reference fill: {n_filled} blank drug names filled from MEDICATION_LOOKUP"))
  message(glue("  Still blank: {n_blank_after} detail rows (no matching triggering_code in reference)"))
} else {
  message("  Phase 114: MEDICATION_LOOKUP empty, skipping reference fill")
}

# Aggregate drug_names per episode from detail level
# Per D-12: comma-separated unique drug names per episode
drug_names_per_episode <- all_detail %>%
  filter(!is.na(drug_name)) %>%
  group_by(patient_id, treatment_type, episode_number) %>%
  summarise(
    drug_names = paste(sort(unique(drug_name)), collapse = ","),
    .groups = "drop"
  )

# Join to episodes
all_episodes <- all_episodes %>%
  left_join(drug_names_per_episode, by = c("patient_id", "treatment_type", "episode_number")) %>%
  mutate(drug_names = ifelse(is.na(drug_names), "", drug_names))

n_with_drugs <- sum(nchar(all_episodes$drug_names) > 0)
message(glue("  Episodes with drug names: {n_with_drugs} / {nrow(all_episodes)}"))

# Update all_episodes select to include drug_names
all_episodes <- all_episodes %>%
  select(
    patient_id, treatment_type, episode_number, episode_start, episode_stop,
    episode_length_days, distinct_dates_in_episode, historical_flag, triggering_codes,
    encounter_ids, drug_names
  )

# Update all_detail select to include drug_name
all_detail <- all_detail %>%
  select(
    patient_id, treatment_type, treatment_date, triggering_code, ENCOUNTERID, drug_name,
    episode_number, episode_start, episode_stop, historical_flag
  )

# SAFE-02: Validate episode date ranges
warn_date_range(all_detail, "episode_start",
                as.Date("1990-01-01"), as.Date("2030-12-31"),
                script_name = "R/26")
warn_date_range(all_detail, "episode_stop",
                as.Date("1990-01-01"), as.Date("2030-12-31"),
                script_name = "R/26")

# Save RDS artifacts (now with drug name columns)
saveRDS(all_episodes, OUTPUT_RDS)
message(glue("\nRDS saved: {OUTPUT_RDS} ({nrow(all_episodes)} rows)"))

saveRDS(all_detail, OUTPUT_DETAIL_RDS)
message(glue("Detail RDS saved: {OUTPUT_DETAIL_RDS} ({nrow(all_detail)} rows)"))


# --- SECTION 6: PER-TYPE CSV OUTPUT ---

message("\n--- Writing per-type CSV files ---")

for (type in TREATMENT_TYPES) {
  # Get updated data from all_episodes (which now has drug_names)
  type_data <- all_episodes %>% filter(treatment_type == type)
  csv_name <- paste0(tolower(gsub(" ", "_", type)), "_episodes.csv")
  csv_path <- file.path(CONFIG$output_dir, csv_name)

  # Phase 60: encounter_ids as column 9, drug_names as column 10
  write_df <- type_data %>%
    select(
      patient_id, episode_number, episode_start, episode_stop,
      episode_length_days, distinct_dates_in_episode, historical_flag,
      triggering_codes, encounter_ids, drug_names
    )

  write.csv(write_df, csv_path, row.names = FALSE)
  message(glue("  Wrote {csv_path} ({nrow(write_df)} episodes)"))
}


# --- SECTION 6b: PER-TYPE DETAIL CSV OUTPUT ---

message("\n--- Writing per-type detail CSV files ---")

for (type in TREATMENT_TYPES) {
  # Get updated data from all_detail (which now has drug_name)
  type_detail <- all_detail %>% filter(treatment_type == type)
  csv_name <- paste0(tolower(gsub(" ", "_", type)), "_episode_detail.csv")
  csv_path <- file.path(CONFIG$output_dir, csv_name)

  write_df <- type_detail %>%
    select(
      patient_id, treatment_date, triggering_code, ENCOUNTERID, drug_name,
      episode_number, episode_start, episode_stop, historical_flag
    ) %>%
    arrange(patient_id, treatment_date)

  write.csv(write_df, csv_path, row.names = FALSE)
  message(glue("  Wrote {csv_path} ({nrow(write_df)} rows)"))
}


# --- SECTION 7: STYLED XLSX REPORT ---

message("\n--- Creating styled xlsx report ---")

wb <- wb_workbook()

# ---------- SHEET 1: SUMMARY ----------
wb$add_worksheet("Summary")

# Row 1: Title
wb$add_data(
  sheet = "Summary", x = "Treatment Episodes by Type",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Summary", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Summary", dims = "A1:H1")

# Row 2: Subtitle
subtitle <- as.character(glue("Generated: {Sys.Date()} | Gap threshold: {GAP_THRESHOLD} days | Historical cutoff: 2012-01-01"))
wb$add_data(sheet = "Summary", x = subtitle, start_row = 2, start_col = 1)
wb$add_font(
  sheet = "Summary", dims = "A2",
  name = "Calibri", size = 10, color = wb_color("FF6B7280")
)
wb$merge_cells(sheet = "Summary", dims = "A2:H2")

# Row 4: Headers with dark fill and white font
headers <- c(
  "Treatment Type", "Patients", "Episodes", "Historical Episodes",
  "% Historical", "Median Length (days)", "Median Dates/Episode", "Max Episodes"
)
for (i in seq_along(headers)) {
  wb$add_data(sheet = "Summary", x = headers[i], start_row = 4, start_col = i)
}
wb$add_fill(sheet = "Summary", dims = "A4:H4", color = wb_color("FF374151"))
wb$add_font(
  sheet = "Summary", dims = "A4:H4",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)

# Data rows (5-8): one per treatment type
for (i in seq_along(TREATMENT_TYPES)) {
  type <- TREATMENT_TYPES[i]
  type_data <- episodes_list[[type]]
  row_num <- 4 + i

  if (nrow(type_data) == 0) {
    wb$add_data(sheet = "Summary", x = type, start_row = row_num, start_col = 1)
    for (col in 2:8) wb$add_data(sheet = "Summary", x = 0L, start_row = row_num, start_col = col)
  } else {
    wb$add_data(sheet = "Summary", x = type, start_row = row_num, start_col = 1)
    wb$add_data(
      sheet = "Summary", x = as.integer(n_distinct(type_data$patient_id)),
      start_row = row_num, start_col = 2
    )
    wb$add_data(
      sheet = "Summary", x = as.integer(nrow(type_data)),
      start_row = row_num, start_col = 3
    )
    wb$add_data(
      sheet = "Summary", x = as.integer(sum(type_data$historical_flag)),
      start_row = row_num, start_col = 4
    )
    wb$add_data(
      sheet = "Summary", x = round(100 * mean(type_data$historical_flag), 1),
      start_row = row_num, start_col = 5
    )
    wb$add_data(
      sheet = "Summary", x = median(type_data$episode_length_days),
      start_row = row_num, start_col = 6
    )
    wb$add_data(
      sheet = "Summary", x = median(type_data$distinct_dates_in_episode),
      start_row = row_num, start_col = 7
    )
    wb$add_data(
      sheet = "Summary", x = as.integer(max(type_data$episode_number)),
      start_row = row_num, start_col = 8
    )
  }

  # Apply type-specific fill color to the type name cell
  type_dims <- glue("A{row_num}")
  wb$add_fill(
    sheet = "Summary", dims = type_dims,
    color = wb_color(TREATMENT_TYPE_COLORS[[type]]$fill)
  )
  wb$add_font(
    sheet = "Summary", dims = type_dims,
    name = "Calibri", size = 11, bold = TRUE,
    color = wb_color(TREATMENT_TYPE_COLORS[[type]]$font)
  )
}

# Number formatting
wb$add_numfmt(sheet = "Summary", dims = "B5:D8", numfmt = "#,##0")
wb$add_numfmt(sheet = "Summary", dims = "E5:E8", numfmt = "#,##0.0")
wb$add_numfmt(sheet = "Summary", dims = "F5:H8", numfmt = "#,##0")

# Column widths
wb$set_col_widths(sheet = "Summary", cols = 1:8, widths = c(20, 12, 12, 18, 14, 22, 20, 16))


# ---------- SHEETS 2-5: PER-TYPE DETAIL SHEETS ----------
for (type in TREATMENT_TYPES) {
  # Get updated data from all_episodes (which now has drug_names)
  type_data <- all_episodes %>% filter(treatment_type == type)
  sheet_name <- as.character(glue("{type} Episodes"))
  wb$add_worksheet(sheet_name)

  n_episodes <- nrow(type_data)
  n_patients <- if (n_episodes > 0) n_distinct(type_data$patient_id) else 0

  # Row 1: Title — updated to span 10 columns (A1:J1) for Phase 60
  title_text <- as.character(glue("{type} Treatment Episodes ({n_episodes} episodes, {n_patients} patients)"))
  wb$add_data(sheet = sheet_name, x = title_text, start_row = 1, start_col = 1)
  wb$add_font(
    sheet = sheet_name, dims = "A1",
    name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
  )
  wb$merge_cells(sheet = sheet_name, dims = "A1:J1")

  # Row 2: Headers — column 8 = "Triggering Codes", column 9 = "Encounter IDs", column 10 = "Drug Names"
  detail_headers <- c(
    "Patient ID", "Episode #", "Start Date", "Stop Date",
    "Length (days)", "Distinct Dates", "Historical", "Triggering Codes", "Encounter IDs", "Drug Names"
  )
  for (j in seq_along(detail_headers)) {
    wb$add_data(sheet = sheet_name, x = detail_headers[j], start_row = 2, start_col = j)
  }

  colors <- TREATMENT_TYPE_COLORS[[type]]
  # Updated dims from A2:I2 to A2:J2 for 10 columns
  wb$add_fill(sheet = sheet_name, dims = "A2:J2", color = wb_color(colors$fill))
  wb$add_font(
    sheet = sheet_name, dims = "A2:J2",
    name = "Calibri", size = 11, bold = TRUE, color = wb_color(colors$font)
  )

  # Data rows (row 3+)
  if (n_episodes > 0) {
    write_df <- data.frame(
      Patient_ID = type_data$patient_id,
      Episode_Num = type_data$episode_number,
      Start_Date = as.character(type_data$episode_start),
      Stop_Date = as.character(type_data$episode_stop),
      Length_Days = type_data$episode_length_days,
      Distinct_Dates = type_data$distinct_dates_in_episode,
      Historical = type_data$historical_flag,
      Triggering_Codes = type_data$triggering_codes,
      Encounter_IDs = type_data$encounter_ids,
      Drug_Names = type_data$drug_names,
      stringsAsFactors = FALSE
    )

    wb$add_data(sheet = sheet_name, x = write_df, start_row = 3, col_names = FALSE)

    # Apply gray fill to historical rows — updated dims from A{row}:I{row} to A{row}:J{row}
    historical_rows <- which(type_data$historical_flag)
    if (length(historical_rows) > 0) {
      for (row_idx in historical_rows) {
        row_num <- 2 + row_idx # +2 because data starts at row 3
        wb$add_fill(
          sheet = sheet_name, dims = glue("A{row_num}:J{row_num}"),
          color = wb_color("FFE5E5E5")
        )
      }
    }

    # Number formatting for numeric columns (E and F only; H, I, J are text)
    last_row <- 2 + n_episodes
    wb$add_numfmt(sheet = sheet_name, dims = glue("E3:F{last_row}"), numfmt = "#,##0")
  }

  # Column widths — column 8 (Triggering Codes), column 9 (Encounter IDs), column 10 (Drug Names) get width 30
  wb$set_col_widths(sheet = sheet_name, cols = 1:10, widths = c(20, 12, 15, 15, 15, 15, 12, 30, 30, 30))
}


# ---------- SHEET 6: HISTORICAL SUMMARY ----------
wb$add_worksheet("Historical Summary")

# Row 1: Title
wb$add_data(
  sheet = "Historical Summary", x = "Historical Episodes (pre-2012)",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Historical Summary", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Historical Summary", dims = "A1:E1")

historical_episodes <- all_episodes %>% filter(historical_flag)

if (nrow(historical_episodes) == 0) {
  wb$add_data(
    sheet = "Historical Summary", x = "No historical episodes found",
    start_row = 3, start_col = 1
  )
} else {
  # By type
  message_text <- as.character(glue("{nrow(historical_episodes)} historical episodes found"))
  wb$add_data(sheet = "Historical Summary", x = message_text, start_row = 3, start_col = 1)

  # Headers (row 5)
  hist_headers <- c("Treatment Type", "Episodes", "Patients", "Earliest Date", "Latest Date")
  for (i in seq_along(hist_headers)) {
    wb$add_data(sheet = "Historical Summary", x = hist_headers[i], start_row = 5, start_col = i)
  }
  wb$add_fill(sheet = "Historical Summary", dims = "A5:E5", color = wb_color("FF374151"))
  wb$add_font(
    sheet = "Historical Summary", dims = "A5:E5",
    name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
  )

  # By-type summary
  hist_summary <- historical_episodes %>%
    group_by(treatment_type) %>%
    summarise(
      n_episodes = n(),
      n_patients = n_distinct(patient_id),
      earliest = min(episode_start),
      latest = max(episode_stop),
      .groups = "drop"
    ) %>%
    mutate(
      earliest = as.character(earliest),
      latest = as.character(latest)
    )

  wb$add_data(sheet = "Historical Summary", x = hist_summary, start_row = 6, col_names = FALSE)

  # Decade distribution (row 10+)
  wb$add_data(
    sheet = "Historical Summary", x = "Decade Distribution:",
    start_row = 10, start_col = 1
  )

  decade_dist <- historical_episodes %>%
    mutate(decade = 10 * (as.integer(format(episode_start, "%Y")) %/% 10)) %>%
    count(decade, name = "n_episodes") %>%
    arrange(decade) %>%
    mutate(decade_label = paste0(decade, "s"))

  decade_headers <- c("Decade", "Episodes")
  for (i in seq_along(decade_headers)) {
    wb$add_data(sheet = "Historical Summary", x = decade_headers[i], start_row = 12, start_col = i)
  }
  wb$add_fill(sheet = "Historical Summary", dims = "A12:B12", color = wb_color("FF374151"))
  wb$add_font(
    sheet = "Historical Summary", dims = "A12:B12",
    name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
  )

  decade_out <- decade_dist %>% select(decade_label, n_episodes)
  wb$add_data(sheet = "Historical Summary", x = decade_out, start_row = 13, col_names = FALSE)
}

wb$set_col_widths(sheet = "Historical Summary", cols = 1:5, widths = c(20, 12, 12, 15, 15))


# ---------- SHEETS 7-10: PER-TYPE DETAIL SHEETS (one row per date+code) ----------
for (type in TREATMENT_TYPES) {
  # Get updated data from all_detail (which now has drug_name)
  type_detail <- all_detail %>% filter(treatment_type == type)
  sheet_name <- as.character(glue("{type} Detail"))
  wb$add_worksheet(sheet_name)

  n_rows <- nrow(type_detail)
  n_patients <- if (n_rows > 0) n_distinct(type_detail$patient_id) else 0

  # Row 1: Title — updated to span 9 columns (A1:I1) for Phase 60
  title_text <- as.character(glue("{type} Episode Detail ({n_rows} rows, {n_patients} patients)"))
  wb$add_data(sheet = sheet_name, x = title_text, start_row = 1, start_col = 1)
  wb$add_font(
    sheet = sheet_name, dims = "A1",
    name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
  )
  wb$merge_cells(sheet = sheet_name, dims = "A1:I1")

  # Row 2: Headers — add ENCOUNTERID (col 4) and Drug Name (col 5)
  detail_headers <- c(
    "Patient ID", "Treatment Date", "Triggering Code", "ENCOUNTERID", "Drug Name",
    "Episode #", "Episode Start", "Episode Stop", "Historical"
  )
  for (j in seq_along(detail_headers)) {
    wb$add_data(sheet = sheet_name, x = detail_headers[j], start_row = 2, start_col = j)
  }

  colors <- TREATMENT_TYPE_COLORS[[type]]
  wb$add_fill(sheet = sheet_name, dims = "A2:I2", color = wb_color(colors$fill))
  wb$add_font(
    sheet = sheet_name, dims = "A2:I2",
    name = "Calibri", size = 11, bold = TRUE, color = wb_color(colors$font)
  )

  # Data rows (row 3+)
  if (n_rows > 0) {
    write_df <- data.frame(
      Patient_ID = type_detail$patient_id,
      Treatment_Date = as.character(type_detail$treatment_date),
      Triggering_Code = type_detail$triggering_code,
      ENCOUNTERID = type_detail$ENCOUNTERID,
      Drug_Name = type_detail$drug_name,
      Episode_Num = type_detail$episode_number,
      Episode_Start = as.character(type_detail$episode_start),
      Episode_Stop = as.character(type_detail$episode_stop),
      Historical = type_detail$historical_flag,
      stringsAsFactors = FALSE
    )

    wb$add_data(sheet = sheet_name, x = write_df, start_row = 3, col_names = FALSE)

    # Gray fill for historical rows — updated dims from A{row}:G{row} to A{row}:I{row}
    historical_rows <- which(type_detail$historical_flag)
    if (length(historical_rows) > 0) {
      for (row_idx in historical_rows) {
        row_num <- 2 + row_idx
        wb$add_fill(
          sheet = sheet_name, dims = glue("A{row_num}:I{row_num}"),
          color = wb_color("FFE5E5E5")
        )
      }
    }
  }

  # Column widths — ENCOUNTERID (col 4) and Drug Name (col 5) get width 20
  wb$set_col_widths(sheet = sheet_name, cols = 1:9, widths = c(20, 15, 20, 20, 25, 12, 15, 15, 12))
}


# Save workbook
wb$save(OUTPUT_XLSX)
message(glue("XLSX saved: {OUTPUT_XLSX}"))


# --- SECTION 7B: PHASE 60 AUDIT REPORT ---

message("\n--- Creating Phase 60 audit report ---")

AUDIT_XLSX <- file.path(CONFIG$output_dir, "phase_60_audit.xlsx")
wb_audit <- wb_workbook()

# Sheet 1: ENCOUNTERID Population Rates
wb_audit$add_worksheet("ENCOUNTERID Rates")
# Title row
wb_audit$add_data(
  sheet = "ENCOUNTERID Rates", x = "ENCOUNTERID Population Rates by Source Table",
  start_row = 1, start_col = 1
)
wb_audit$add_font(
  sheet = "ENCOUNTERID Rates", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb_audit$merge_cells(sheet = "ENCOUNTERID Rates", dims = "A1:D1")

# Load profile from Plan 01
PROFILE_RDS <- file.path(CONFIG$cache$outputs_dir, "encounterid_profile.rds")
# SAFE-01: File existence validated by existing file.exists() guard
if (file.exists(PROFILE_RDS)) {
  encounterid_profile <- readRDS(PROFILE_RDS)

  # Headers
  profile_headers <- c("Table", "Total Rows", "ENCOUNTERID Populated", "Population Rate (%)")
  for (i in seq_along(profile_headers)) {
    wb_audit$add_data(sheet = "ENCOUNTERID Rates", x = profile_headers[i], start_row = 3, start_col = i)
  }
  wb_audit$add_fill(sheet = "ENCOUNTERID Rates", dims = "A3:D3", color = wb_color("FF374151"))
  wb_audit$add_font(
    sheet = "ENCOUNTERID Rates", dims = "A3:D3",
    name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
  )

  wb_audit$add_data(sheet = "ENCOUNTERID Rates", x = encounterid_profile, start_row = 4, col_names = FALSE)
  wb_audit$add_numfmt(
    sheet = "ENCOUNTERID Rates",
    dims = glue("B4:C{3 + nrow(encounterid_profile)}"), numfmt = "#,##0"
  )
  wb_audit$add_numfmt(
    sheet = "ENCOUNTERID Rates",
    dims = glue("D4:D{3 + nrow(encounterid_profile)}"), numfmt = "#,##0.0"
  )
  wb_audit$set_col_widths(sheet = "ENCOUNTERID Rates", cols = 1:4, widths = c(20, 15, 25, 20))
} else {
  wb_audit$add_data(sheet = "ENCOUNTERID Rates", x = "encounterid_profile.rds not found", start_row = 3, start_col = 1)
}

# Sheet 2: SCT Source Audit
wb_audit$add_worksheet("SCT Source Audit")
wb_audit$add_data(
  sheet = "SCT Source Audit", x = "SCT Detection: Pre/Post ICD DX Code Removal",
  start_row = 1, start_col = 1
)
wb_audit$add_font(
  sheet = "SCT Source Audit", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb_audit$merge_cells(sheet = "SCT Source Audit", dims = "A1:B1")

AUDIT_RDS <- file.path(CONFIG$cache$outputs_dir, "sct_audit_result.rds")
# SAFE-01: File existence validated by existing file.exists() guard
if (file.exists(AUDIT_RDS)) {
  sct_audit <- readRDS(AUDIT_RDS)

  audit_headers <- c("Metric", "Value")
  for (i in seq_along(audit_headers)) {
    wb_audit$add_data(sheet = "SCT Source Audit", x = audit_headers[i], start_row = 3, start_col = i)
  }
  wb_audit$add_fill(sheet = "SCT Source Audit", dims = "A3:B3", color = wb_color("FF374151"))
  wb_audit$add_font(
    sheet = "SCT Source Audit", dims = "A3:B3",
    name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
  )

  wb_audit$add_data(sheet = "SCT Source Audit", x = sct_audit, start_row = 4, col_names = FALSE)
  wb_audit$set_col_widths(sheet = "SCT Source Audit", cols = 1:2, widths = c(45, 20))
} else {
  wb_audit$add_data(sheet = "SCT Source Audit", x = "sct_audit_result.rds not found", start_row = 3, start_col = 1)
}

# Sheet 3: Drug Name Resolution Summary
wb_audit$add_worksheet("Drug Name Resolution")
wb_audit$add_data(
  sheet = "Drug Name Resolution", x = "Drug Name Resolution via RxNorm API",
  start_row = 1, start_col = 1
)
wb_audit$add_font(
  sheet = "Drug Name Resolution", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb_audit$merge_cells(sheet = "Drug Name Resolution", dims = "A1:D1")

if (file.exists(DRUG_LOOKUP_RDS)) {
  # Summary stats
  n_success <- sum(drug_lookup$lookup_status == "success", na.rm = TRUE)
  n_not_found <- sum(grepl("not_found", drug_lookup$lookup_status), na.rm = TRUE)
  n_error <- sum(grepl("error", drug_lookup$lookup_status), na.rm = TRUE)

  drug_summary <- tibble(
    metric = c("Total codes resolved", "Successful lookups", "Not found", "Errors", "Unique drug names"),
    value = c(
      nrow(drug_lookup), n_success, n_not_found, n_error,
      n_distinct(drug_lookup$drug_name[!is.na(drug_lookup$drug_name)])
    )
  )

  summary_headers <- c("Metric", "Value")
  for (i in seq_along(summary_headers)) {
    wb_audit$add_data(sheet = "Drug Name Resolution", x = summary_headers[i], start_row = 3, start_col = i)
  }
  wb_audit$add_fill(sheet = "Drug Name Resolution", dims = "A3:B3", color = wb_color("FF374151"))
  wb_audit$add_font(
    sheet = "Drug Name Resolution", dims = "A3:B3",
    name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
  )
  wb_audit$add_data(sheet = "Drug Name Resolution", x = drug_summary, start_row = 4, col_names = FALSE)

  # Full lookup table below summary
  wb_audit$add_data(
    sheet = "Drug Name Resolution", x = "Full Lookup Table:",
    start_row = 10, start_col = 1
  )
  lookup_headers <- c("Code", "Code Type", "Drug Name", "Status", "Source Tables")
  for (i in seq_along(lookup_headers)) {
    wb_audit$add_data(sheet = "Drug Name Resolution", x = lookup_headers[i], start_row = 11, start_col = i)
  }
  wb_audit$add_fill(sheet = "Drug Name Resolution", dims = "A11:E11", color = wb_color("FF374151"))
  wb_audit$add_font(
    sheet = "Drug Name Resolution", dims = "A11:E11",
    name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
  )
  wb_audit$add_data(sheet = "Drug Name Resolution", x = drug_lookup, start_row = 12, col_names = FALSE)
  wb_audit$set_col_widths(sheet = "Drug Name Resolution", cols = 1:5, widths = c(15, 12, 50, 15, 25))
} else {
  wb_audit$add_data(sheet = "Drug Name Resolution", x = "drug_name_lookup.rds not found", start_row = 3, start_col = 1)
}

wb_audit$save(AUDIT_XLSX)
message(glue("Phase 60 audit saved: {AUDIT_XLSX}"))


# --- SECTION 8: FINAL SUMMARY ---

# ==============================================================================
# SECTION 2: OUTPUT ----
# ==============================================================================

message("\n=== Phase 44 Complete ===")
message(glue("Total episodes: {nrow(all_episodes)}"))
message(glue("Unique patients: {n_distinct(all_episodes$patient_id)}"))
message(glue("Historical episodes: {sum(all_episodes$historical_flag)} ({round(100*mean(all_episodes$historical_flag), 1)}%)"))
message(glue("Total detail rows: {nrow(all_detail)}"))
message(glue("\nOutputs:"))
message(glue("  RDS (episodes):  {OUTPUT_RDS}"))
message(glue("  RDS (detail):    {OUTPUT_DETAIL_RDS}"))
message(glue("  XLSX: {OUTPUT_XLSX}"))
message(glue("  CSVs: {CONFIG$output_dir}/*_episodes.csv"))
message(glue("  CSVs: {CONFIG$output_dir}/*_episode_detail.csv"))
