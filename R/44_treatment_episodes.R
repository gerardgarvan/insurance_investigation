# =============================================================================
# Phase 44: Treatment Episode Start/Stop Dates
# =============================================================================
# Extracts per-patient, per-episode treatment start and stop dates with episode
# length and historical date flagging. This is a NEW detail-level output
# alongside Phase 43's existing per-patient summary.
#
# Decision traceability:
#   D-01: historical episodes included with historical_flag boolean column
#   D-02: historical cutoff = before 2012-01-01
#   D-03: episode flagged historical when ALL dates < 2012-01-01 (using episode_stop)
#   D-04: single-date historical episodes get start=stop, length=0
#   D-05: new script alongside Phase 43 (Phase 43 unchanged)
#   D-06: new file R/44_treatment_episodes.R
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
# Outputs:
#   - RDS artifact: one row per patient per treatment type per episode
#   - Styled xlsx: Summary sheet + per-type detail sheets + Historical Summary
#   - Per-type CSVs: chemotherapy_episodes.csv, radiation_episodes.csv,
#                    sct_episodes.csv, immunotherapy_episodes.csv
# =============================================================================


# --- SECTION 1: SETUP AND CONFIGURATION ---

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(purrr)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")

# Reuse Phase 43's assign_episode_ids() and stack_and_dedup() functions
source("R/43_treatment_durations.R")

# Output paths
OUTPUT_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
OUTPUT_DETAIL_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds")
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "treatment_episodes.xlsx")

# Per D-02: historical cutoff date (matches OneFlorida+ data extraction period start)
HISTORICAL_CUTOFF <- as.Date("2012-01-01")


# --- SECTION 2: EXTRACTION FUNCTIONS WITH TRIGGERING CODES ---

# These functions mirror the logic in R/43_treatment_durations.R but return
# a 3-column tibble: ID, treatment_date, triggering_code.
# Per D-46-08: bare codes only (PX column for PROCEDURES, DX for DIAGNOSIS, etc.)
# TUMOR_REGISTRY dates are date evidence only — triggering_code = NA_character_
# R/43_treatment_durations.R is NOT modified; these are new functions in R/44.

#' Stack sources with triggering_code, dedup on (ID, treatment_date, triggering_code)
#'
#' Per D-46-07: distinct(ID, treatment_date, triggering_code) — 3-column dedup —
#' preserves multiple codes on the same date while removing exact duplicates.
#'
#' @param sources Named list of tibbles with columns ID, treatment_date, triggering_code
#' @param type_name Character. Treatment type name for logging
#' @return Tibble with columns: ID, treatment_date, triggering_code
stack_and_dedup_with_codes <- function(sources, type_name) {
  non_null <- compact(sources)

  if (length(non_null) == 0) {
    return(tibble(
      ID = character(0),
      treatment_date = as.Date(character(0)),
      triggering_code = character(0)
    ))
  }

  stacked <- bind_rows(non_null) %>%
    mutate(treatment_date = as.Date(treatment_date)) %>%
    filter(!is.na(treatment_date))

  # 3-column distinct: preserves multiple codes on same date (D-46-07)
  result <- stacked %>%
    distinct(ID, treatment_date, triggering_code) %>%
    arrange(ID, treatment_date)

  message(glue("  {type_name} with codes: {n_distinct(result$ID)} patients, {nrow(result)} distinct (ID, date, code) rows"))
  result
}

#' Extract all chemotherapy dates with triggering codes
#' Mirrors extract_chemo_dates() from R/43_treatment_durations.R but adds triggering_code
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
      select(ID, treatment_date = PX_DATE, triggering_code = PX) %>%
      collect()
  }

  # 2. PRESCRIBING: RXNORM_CUI — bare RxNorm CUI is a valid code per D-46-08
  rx_dates <- NULL
  if (!is.null(get_pcornet_table("PRESCRIBING"))) {
    rx_dates <- get_pcornet_table("PRESCRIBING") %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      mutate(treatment_date = coalesce(RX_ORDER_DATE, RX_START_DATE)) %>%
      filter(!is.na(treatment_date)) %>%
      select(ID, treatment_date, triggering_code = RXNORM_CUI) %>%
      collect()
  }

  # 3. DIAGNOSIS: Z51.11/Z51.12 (ICD-10), V58.11/V58.12 (ICD-9) — bare DX code
  dx_dates <- NULL
  if (!is.null(get_pcornet_table("DIAGNOSIS"))) {
    dx_dates <- get_pcornet_table("DIAGNOSIS") %>%
      filter(
        (DX_TYPE == "10" & DX %in% TREATMENT_CODES$chemo_dx_icd10) |
        (DX_TYPE == "09" & DX %in% TREATMENT_CODES$chemo_dx_icd9)
      ) %>%
      filter(!is.na(DX_DATE)) %>%
      select(ID, treatment_date = DX_DATE, triggering_code = DX) %>%
      collect()
  }

  # 4. ENCOUNTER: chemo DRGs — bare DRG numeric code
  drg_dates <- NULL
  if (!is.null(get_pcornet_table("ENCOUNTER"))) {
    drg_dates <- get_pcornet_table("ENCOUNTER") %>%
      filter(DRG %in% TREATMENT_CODES$chemo_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      select(ID, treatment_date = ADMIT_DATE, triggering_code = DRG) %>%
      collect()
  }

  # 5. DISPENSING: RXNORM_CUI — bare RxNorm CUI
  disp_dates <- NULL
  if (!is.null(get_pcornet_table("DISPENSING")) &&
      "RXNORM_CUI" %in% colnames(get_pcornet_table("DISPENSING"))) {
    disp_dates <- get_pcornet_table("DISPENSING") %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      filter(!is.na(DISPENSE_DATE)) %>%
      select(ID, treatment_date = DISPENSE_DATE, triggering_code = RXNORM_CUI) %>%
      collect()
  }

  # 6. MED_ADMIN: RXNORM_CUI — bare RxNorm CUI
  ma_dates <- NULL
  if (!is.null(get_pcornet_table("MED_ADMIN")) &&
      "RXNORM_CUI" %in% colnames(get_pcornet_table("MED_ADMIN"))) {
    ma_dates <- get_pcornet_table("MED_ADMIN") %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      filter(!is.na(MEDADMIN_START_DATE)) %>%
      select(ID, treatment_date = MEDADMIN_START_DATE, triggering_code = RXNORM_CUI) %>%
      collect()
  }

  # 7. TUMOR_REGISTRY_ALL: date evidence only — no individual code (triggering_code = NA)
  tr_dates <- NULL
  if (!is.null(get_pcornet_table("TUMOR_REGISTRY_ALL"))) {
    tr_chemo_cols <- intersect(
      c("CHEMO_START_DATE_SUMMARY", "DT_CHEMO"),
      colnames(get_pcornet_table("TUMOR_REGISTRY_ALL"))
    )
    if (length(tr_chemo_cols) > 0) {
      tr_data <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
        select(ID, all_of(tr_chemo_cols)) %>%
        collect() %>%
        filter(if_any(all_of(tr_chemo_cols), ~ !is.na(.)))
      if (nrow(tr_data) > 0) {
        tr_dates <- tr_data %>%
          tidyr::pivot_longer(
            cols = all_of(tr_chemo_cols),
            names_to = "date_source",
            values_to = "treatment_date"
          ) %>%
          filter(!is.na(treatment_date)) %>%
          mutate(
            treatment_date = as.Date(treatment_date),
            triggering_code = NA_character_
          ) %>%
          select(ID, treatment_date, triggering_code)
      }
    }
  }

  stack_and_dedup_with_codes(
    sources = list(
      PX = px_dates, RX = rx_dates, DX = dx_dates,
      DRG = drg_dates, DISP = disp_dates, MA = ma_dates, TR = tr_dates
    ),
    type_name = "Chemotherapy"
  )
}

#' Extract all radiation dates with triggering codes
#' Mirrors extract_radiation_dates() from R/43_treatment_durations.R but adds triggering_code
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
      select(ID, treatment_date = PX_DATE, triggering_code = PX) %>%
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
      select(ID, treatment_date = DX_DATE, triggering_code = DX) %>%
      collect()
  }

  # 3. ENCOUNTER: DRG 849 — bare DRG code
  drg_dates <- NULL
  if (!is.null(get_pcornet_table("ENCOUNTER"))) {
    drg_dates <- get_pcornet_table("ENCOUNTER") %>%
      filter(DRG %in% TREATMENT_CODES$radiation_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      select(ID, treatment_date = ADMIT_DATE, triggering_code = DRG) %>%
      collect()
  }

  # 4. TUMOR_REGISTRY_ALL: date evidence only — no individual code
  tr_dates <- NULL
  if (!is.null(get_pcornet_table("TUMOR_REGISTRY_ALL"))) {
    tr_rad_cols <- intersect(
      c("RAD_START_DATE_SUMMARY", "DT_RAD"),
      colnames(get_pcornet_table("TUMOR_REGISTRY_ALL"))
    )
    if (length(tr_rad_cols) > 0) {
      tr_data <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
        select(ID, all_of(tr_rad_cols)) %>%
        collect() %>%
        filter(if_any(all_of(tr_rad_cols), ~ !is.na(.)))
      if (nrow(tr_data) > 0) {
        tr_dates <- tr_data %>%
          tidyr::pivot_longer(
            cols = all_of(tr_rad_cols),
            names_to = "date_source",
            values_to = "treatment_date"
          ) %>%
          filter(!is.na(treatment_date)) %>%
          mutate(
            treatment_date = as.Date(treatment_date),
            triggering_code = NA_character_
          ) %>%
          select(ID, treatment_date, triggering_code)
      }
    }
  }

  stack_and_dedup_with_codes(
    sources = list(PX = px_dates, DX = dx_dates, DRG = drg_dates, TR = tr_dates),
    type_name = "Radiation"
  )
}

#' Extract all SCT dates with triggering codes
#' Mirrors extract_sct_dates() from R/43_treatment_durations.R but adds triggering_code
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
      select(ID, treatment_date = PX_DATE, triggering_code = PX) %>%
      collect()
  }

  # 2. DIAGNOSIS: Z94.84/T86.5/T86.09/Z48.290/T86.0 (ICD-10 only) — bare DX code
  dx_dates <- NULL
  if (!is.null(get_pcornet_table("DIAGNOSIS"))) {
    dx_dates <- get_pcornet_table("DIAGNOSIS") %>%
      filter(DX_TYPE == "10" & DX %in% TREATMENT_CODES$sct_dx_icd10) %>%
      filter(!is.na(DX_DATE)) %>%
      select(ID, treatment_date = DX_DATE, triggering_code = DX) %>%
      collect()
  }

  # 3. ENCOUNTER: DRGs 014, 016, 017 — bare DRG code
  drg_dates <- NULL
  if (!is.null(get_pcornet_table("ENCOUNTER"))) {
    drg_dates <- get_pcornet_table("ENCOUNTER") %>%
      filter(DRG %in% TREATMENT_CODES$sct_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      select(ID, treatment_date = ADMIT_DATE, triggering_code = DRG) %>%
      collect()
  }

  # 4. TUMOR_REGISTRY_ALL: SCT-related date columns — date evidence only
  tr_dates <- NULL
  if (!is.null(get_pcornet_table("TUMOR_REGISTRY_ALL"))) {
    tr_sct_cols <- intersect(
      c("DT_HTE", "DT_SCT", "SCT_DATE", "BMT_DATE",
        "TRANSPLANT_DATE", "HCT_DATE", "DT_TRANSPLANT"),
      colnames(get_pcornet_table("TUMOR_REGISTRY_ALL"))
    )
    if (length(tr_sct_cols) > 0) {
      tr_data <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
        select(ID, all_of(tr_sct_cols)) %>%
        collect() %>%
        filter(if_any(all_of(tr_sct_cols), ~ !is.na(.)))
      if (nrow(tr_data) > 0) {
        tr_dates <- tr_data %>%
          tidyr::pivot_longer(
            cols = all_of(tr_sct_cols),
            names_to = "date_source",
            values_to = "treatment_date"
          ) %>%
          filter(!is.na(treatment_date)) %>%
          mutate(
            treatment_date = as.Date(treatment_date),
            triggering_code = NA_character_
          ) %>%
          select(ID, treatment_date, triggering_code)
      }
    }
  }

  stack_and_dedup_with_codes(
    sources = list(PX = px_dates, DX = dx_dates, DRG = drg_dates, TR = tr_dates),
    type_name = "SCT"
  )
}

#' Extract all immunotherapy dates with triggering codes
#' Mirrors extract_immunotherapy_dates() from R/43_treatment_durations.R but adds triggering_code
extract_immunotherapy_dates_with_codes <- function() {
  cart_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$cart_icd10pcs_prefixes, collapse = "|"), ")")

  # 1. PROCEDURES: ICD-10-PCS CAR T-cell codes (prefix match) — bare code = PX
  px_dates <- NULL
  if (!is.null(get_pcornet_table("PROCEDURES"))) {
    px_dates <- get_pcornet_table("PROCEDURES") %>%
      filter(PX_TYPE == "10" & str_detect(PX, cart_icd10pcs_rx)) %>%
      filter(!is.na(PX_DATE)) %>%
      select(ID, treatment_date = PX_DATE, triggering_code = PX) %>%
      collect()
  }

  # 2. ENCOUNTER: DRG 018 — bare DRG code
  drg_dates <- NULL
  if (!is.null(get_pcornet_table("ENCOUNTER"))) {
    drg_dates <- get_pcornet_table("ENCOUNTER") %>%
      filter(DRG %in% TREATMENT_CODES$immunotherapy_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      select(ID, treatment_date = ADMIT_DATE, triggering_code = DRG) %>%
      collect()
  }

  stack_and_dedup_with_codes(
    sources = list(PX = px_dates, DRG = drg_dates),
    type_name = "Immunotherapy"
  )
}

#' Dispatch to the appropriate type-specific extraction function with triggering codes
#' @param type Character. One of "Chemotherapy", "Radiation", "SCT", "Immunotherapy"
#' @return Tibble with columns: ID, treatment_date, triggering_code
extract_dates_with_codes <- function(type) {
  message(glue("\n--- Extracting {type} dates (with triggering codes) ---"))

  if (type == "Chemotherapy") {
    return(extract_chemo_dates_with_codes())
  } else if (type == "Radiation") {
    return(extract_radiation_dates_with_codes())
  } else if (type == "SCT") {
    return(extract_sct_dates_with_codes())
  } else if (type == "Immunotherapy") {
    return(extract_immunotherapy_dates_with_codes())
  } else {
    stop(glue("Unknown treatment type: {type}"))
  }
}


# --- SECTION 3: EPISODE CALCULATION FUNCTION ---

# assign_episode_ids() is defined in R/43_treatment_durations.R (sourced above)

#' Calculate detailed episode-level data with triggering codes
#'
#' Adapted from Phase 44 original calculate_episodes_detailed() — now accepts
#' dates_df with 3 columns (ID, treatment_date, triggering_code) and aggregates
#' triggering codes per episode via paste(sort(unique(na.omit(...))), collapse=",").
#'
#' Per D-46-07: ALL matching codes within the episode date window are included.
#' Per D-46-08: bare codes only (no type prefix).
#' Per D-46-05: triggering_codes is the LAST column (column 8) in output.
#'
#' @param dates_df Tibble with columns ID, treatment_date, and triggering_code
#' @param gap_threshold Integer. Max days from episode start to define cycle boundary
#' @return Tibble with one row per patient per episode: patient_id, episode_number,
#'   episode_start, episode_stop, episode_length_days, distinct_dates_in_episode,
#'   historical_flag, triggering_codes
calculate_episodes_detailed <- function(dates_df, gap_threshold = GAP_THRESHOLD) {
  # Empty input guard — must include triggering_codes = character(0) per D-46-05
  if (nrow(dates_df) == 0) {
    return(tibble(
      patient_id = character(0),
      episode_number = integer(0),
      episode_start = as.Date(character(0)),
      episode_stop = as.Date(character(0)),
      episode_length_days = numeric(0),
      distinct_dates_in_episode = integer(0),
      historical_flag = logical(0),
      triggering_codes = character(0)
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
    # Final select — triggering_codes LAST (column 8) per D-46-05 / Pitfall 5
    select(
      patient_id = ID,
      episode_number,
      episode_start,
      episode_stop,
      episode_length_days,
      distinct_dates_in_episode,
      historical_flag,
      triggering_codes
    )
}


#' Annotate raw date+code rows with episode context
#'
#' Takes the raw 3-column data (before episode collapsing) and the episode-level
#' output, assigns episode IDs to each raw row, then joins episode context.
#' Returns one row per unique (patient, date, code) — the detail-level output.
#'
#' @param dates_df Tibble with columns: ID, treatment_date, triggering_code
#' @param episodes_df Tibble from calculate_episodes_detailed() with episode-level data
#' @param gap_threshold Integer. Max days from episode start (must match episodes_df)
#' @return Tibble with columns: patient_id, treatment_date, triggering_code,
#'   episode_number, episode_start, episode_stop, historical_flag
annotate_detail_with_episodes <- function(dates_df, episodes_df, gap_threshold = GAP_THRESHOLD) {
  if (nrow(dates_df) == 0 || nrow(episodes_df) == 0) {
    return(tibble(
      patient_id = character(0),
      treatment_date = as.Date(character(0)),
      triggering_code = character(0),
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

  message(glue("\n  {type_name} Summary:"))
  message(glue("    Patients: {n_patients}"))
  message(glue("    Episodes: {n_episodes} ({n_historical} historical, {pct_historical}%)"))
  message(glue("    Episode length (days): median={median_length}"))
  message(glue("    Dates per episode: median={median_dates}"))
  message(glue("    Episodes with triggering codes: {n_with_codes} ({pct_with_codes}%)"))

  invisible(NULL)
}


# --- SECTION 5: MAIN EXECUTION LOOP ---

message("=== Phase 44: Treatment Episode Start/Stop Dates ===\n")

episodes_list <- list()
detail_list <- list()

for (type in TREATMENT_TYPES) {
  # Use new extract_dates_with_codes() instead of extract_all_dates()
  # Returns 3 columns: ID, treatment_date, triggering_code
  dates_df <- extract_dates_with_codes(type)

  # Calculate per-episode detail (now includes triggering_codes aggregation)
  episodes_df <- calculate_episodes_detailed(dates_df)

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

# Combine all types into single dataset — triggering_codes flows through bind_rows automatically
all_episodes <- bind_rows(episodes_list) %>%
  select(patient_id, treatment_type, episode_number, episode_start, episode_stop,
         episode_length_days, distinct_dates_in_episode, historical_flag, triggering_codes)

# Save RDS artifact
saveRDS(all_episodes, OUTPUT_RDS)
message(glue("\nRDS saved: {OUTPUT_RDS} ({nrow(all_episodes)} rows)"))

# Combine detail-level data and save
all_detail <- bind_rows(detail_list) %>%
  select(patient_id, treatment_type, treatment_date, triggering_code,
         episode_number, episode_start, episode_stop, historical_flag)
saveRDS(all_detail, OUTPUT_DETAIL_RDS)
message(glue("Detail RDS saved: {OUTPUT_DETAIL_RDS} ({nrow(all_detail)} rows)"))


# --- SECTION 6: PER-TYPE CSV OUTPUT ---

message("\n--- Writing per-type CSV files ---")

for (type in TREATMENT_TYPES) {
  type_data <- episodes_list[[type]]
  csv_name <- paste0(tolower(gsub(" ", "_", type)), "_episodes.csv")
  csv_path <- file.path(CONFIG$output_dir, csv_name)

  # D-46-05: triggering_codes as column 8 (last column)
  write_df <- type_data %>%
    select(patient_id, episode_number, episode_start, episode_stop,
           episode_length_days, distinct_dates_in_episode, historical_flag,
           triggering_codes)

  write.csv(write_df, csv_path, row.names = FALSE)
  message(glue("  Wrote {csv_path} ({nrow(write_df)} episodes)"))
}


# --- SECTION 6b: PER-TYPE DETAIL CSV OUTPUT ---

message("\n--- Writing per-type detail CSV files ---")

for (type in TREATMENT_TYPES) {
  type_detail <- detail_list[[type]]
  csv_name <- paste0(tolower(gsub(" ", "_", type)), "_episode_detail.csv")
  csv_path <- file.path(CONFIG$output_dir, csv_name)

  write_df <- type_detail %>%
    select(patient_id, treatment_date, triggering_code,
           episode_number, episode_start, episode_stop, historical_flag) %>%
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
wb$add_data(sheet = "Summary", x = "Treatment Episodes by Type",
            start_row = 1, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Summary", dims = "A1:H1")

# Row 2: Subtitle
subtitle <- as.character(glue("Generated: {Sys.Date()} | Gap threshold: {GAP_THRESHOLD} days | Historical cutoff: 2012-01-01"))
wb$add_data(sheet = "Summary", x = subtitle, start_row = 2, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A2",
            name = "Calibri", size = 10, color = wb_color("FF6B7280"))
wb$merge_cells(sheet = "Summary", dims = "A2:H2")

# Row 4: Headers with dark fill and white font
headers <- c("Treatment Type", "Patients", "Episodes", "Historical Episodes",
             "% Historical", "Median Length (days)", "Median Dates/Episode", "Max Episodes")
for (i in seq_along(headers)) {
  wb$add_data(sheet = "Summary", x = headers[i], start_row = 4, start_col = i)
}
wb$add_fill(sheet = "Summary", dims = "A4:H4", color = wb_color("FF374151"))
wb$add_font(sheet = "Summary", dims = "A4:H4",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

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
    wb$add_data(sheet = "Summary", x = as.integer(n_distinct(type_data$patient_id)),
                start_row = row_num, start_col = 2)
    wb$add_data(sheet = "Summary", x = as.integer(nrow(type_data)),
                start_row = row_num, start_col = 3)
    wb$add_data(sheet = "Summary", x = as.integer(sum(type_data$historical_flag)),
                start_row = row_num, start_col = 4)
    wb$add_data(sheet = "Summary", x = round(100 * mean(type_data$historical_flag), 1),
                start_row = row_num, start_col = 5)
    wb$add_data(sheet = "Summary", x = median(type_data$episode_length_days),
                start_row = row_num, start_col = 6)
    wb$add_data(sheet = "Summary", x = median(type_data$distinct_dates_in_episode),
                start_row = row_num, start_col = 7)
    wb$add_data(sheet = "Summary", x = as.integer(max(type_data$episode_number)),
                start_row = row_num, start_col = 8)
  }

  # Apply type-specific fill color to the type name cell
  type_dims <- glue("A{row_num}")
  wb$add_fill(sheet = "Summary", dims = type_dims,
              color = wb_color(TREATMENT_TYPE_COLORS[[type]]$fill))
  wb$add_font(sheet = "Summary", dims = type_dims,
              name = "Calibri", size = 11, bold = TRUE,
              color = wb_color(TREATMENT_TYPE_COLORS[[type]]$font))
}

# Number formatting
wb$add_numfmt(sheet = "Summary", dims = "B5:D8", numfmt = "#,##0")
wb$add_numfmt(sheet = "Summary", dims = "E5:E8", numfmt = "#,##0.0")
wb$add_numfmt(sheet = "Summary", dims = "F5:H8", numfmt = "#,##0")

# Column widths
wb$set_col_widths(sheet = "Summary", cols = 1:8, widths = c(20, 12, 12, 18, 14, 22, 20, 16))


# ---------- SHEETS 2-5: PER-TYPE DETAIL SHEETS ----------
for (type in TREATMENT_TYPES) {
  type_data <- episodes_list[[type]]
  sheet_name <- as.character(glue("{type} Episodes"))
  wb$add_worksheet(sheet_name)

  n_episodes <- nrow(type_data)
  n_patients <- if (n_episodes > 0) n_distinct(type_data$patient_id) else 0

  # Row 1: Title — updated to span 8 columns (A1:H1)
  title_text <- as.character(glue("{type} Treatment Episodes ({n_episodes} episodes, {n_patients} patients)"))
  wb$add_data(sheet = sheet_name, x = title_text, start_row = 1, start_col = 1)
  wb$add_font(sheet = sheet_name, dims = "A1",
              name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
  wb$merge_cells(sheet = sheet_name, dims = "A1:H1")

  # Row 2: Headers — column 8 = "Triggering Codes" (D-46-09)
  detail_headers <- c("Patient ID", "Episode #", "Start Date", "Stop Date",
                      "Length (days)", "Distinct Dates", "Historical", "Triggering Codes")
  for (j in seq_along(detail_headers)) {
    wb$add_data(sheet = sheet_name, x = detail_headers[j], start_row = 2, start_col = j)
  }

  colors <- TREATMENT_TYPE_COLORS[[type]]
  # Updated dims from A2:G2 to A2:H2 for 8 columns
  wb$add_fill(sheet = sheet_name, dims = "A2:H2", color = wb_color(colors$fill))
  wb$add_font(sheet = sheet_name, dims = "A2:H2",
              name = "Calibri", size = 11, bold = TRUE, color = wb_color(colors$font))

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
      stringsAsFactors = FALSE
    )

    wb$add_data(sheet = sheet_name, x = write_df, start_row = 3, col_names = FALSE)

    # Apply gray fill to historical rows — updated dims from A{row}:G{row} to A{row}:H{row}
    historical_rows <- which(type_data$historical_flag)
    if (length(historical_rows) > 0) {
      for (row_idx in historical_rows) {
        row_num <- 2 + row_idx  # +2 because data starts at row 3
        wb$add_fill(sheet = sheet_name, dims = glue("A{row_num}:H{row_num}"),
                    color = wb_color("FFE5E5E5"))
      }
    }

    # Number formatting for numeric columns (E and F only; H is text)
    last_row <- 2 + n_episodes
    wb$add_numfmt(sheet = sheet_name, dims = glue("E3:F{last_row}"), numfmt = "#,##0")
  }

  # Column widths — column 8 (Triggering Codes) gets width 30 for code strings
  wb$set_col_widths(sheet = sheet_name, cols = 1:8, widths = c(20, 12, 15, 15, 15, 15, 12, 30))
}


# ---------- SHEET 6: HISTORICAL SUMMARY ----------
wb$add_worksheet("Historical Summary")

# Row 1: Title
wb$add_data(sheet = "Historical Summary", x = "Historical Episodes (pre-2012)",
            start_row = 1, start_col = 1)
wb$add_font(sheet = "Historical Summary", dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Historical Summary", dims = "A1:E1")

historical_episodes <- all_episodes %>% filter(historical_flag)

if (nrow(historical_episodes) == 0) {
  wb$add_data(sheet = "Historical Summary", x = "No historical episodes found",
              start_row = 3, start_col = 1)
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
  wb$add_font(sheet = "Historical Summary", dims = "A5:E5",
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

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
  wb$add_data(sheet = "Historical Summary", x = "Decade Distribution:",
              start_row = 10, start_col = 1)

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
  wb$add_font(sheet = "Historical Summary", dims = "A12:B12",
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

  decade_out <- decade_dist %>% select(decade_label, n_episodes)
  wb$add_data(sheet = "Historical Summary", x = decade_out, start_row = 13, col_names = FALSE)
}

wb$set_col_widths(sheet = "Historical Summary", cols = 1:5, widths = c(20, 12, 12, 15, 15))


# ---------- SHEETS 7-10: PER-TYPE DETAIL SHEETS (one row per date+code) ----------
for (type in TREATMENT_TYPES) {
  type_detail <- detail_list[[type]]
  sheet_name <- as.character(glue("{type} Detail"))
  wb$add_worksheet(sheet_name)

  n_rows <- nrow(type_detail)
  n_patients <- if (n_rows > 0) n_distinct(type_detail$patient_id) else 0

  # Row 1: Title
  title_text <- as.character(glue("{type} Episode Detail ({n_rows} rows, {n_patients} patients)"))
  wb$add_data(sheet = sheet_name, x = title_text, start_row = 1, start_col = 1)
  wb$add_font(sheet = sheet_name, dims = "A1",
              name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
  wb$merge_cells(sheet = sheet_name, dims = "A1:G1")

  # Row 2: Headers
  detail_headers <- c("Patient ID", "Treatment Date", "Triggering Code",
                       "Episode #", "Episode Start", "Episode Stop", "Historical")
  for (j in seq_along(detail_headers)) {
    wb$add_data(sheet = sheet_name, x = detail_headers[j], start_row = 2, start_col = j)
  }

  colors <- TREATMENT_TYPE_COLORS[[type]]
  wb$add_fill(sheet = sheet_name, dims = "A2:G2", color = wb_color(colors$fill))
  wb$add_font(sheet = sheet_name, dims = "A2:G2",
              name = "Calibri", size = 11, bold = TRUE, color = wb_color(colors$font))

  # Data rows (row 3+)
  if (n_rows > 0) {
    write_df <- data.frame(
      Patient_ID = type_detail$patient_id,
      Treatment_Date = as.character(type_detail$treatment_date),
      Triggering_Code = type_detail$triggering_code,
      Episode_Num = type_detail$episode_number,
      Episode_Start = as.character(type_detail$episode_start),
      Episode_Stop = as.character(type_detail$episode_stop),
      Historical = type_detail$historical_flag,
      stringsAsFactors = FALSE
    )

    wb$add_data(sheet = sheet_name, x = write_df, start_row = 3, col_names = FALSE)

    # Gray fill for historical rows
    historical_rows <- which(type_detail$historical_flag)
    if (length(historical_rows) > 0) {
      for (row_idx in historical_rows) {
        row_num <- 2 + row_idx
        wb$add_fill(sheet = sheet_name, dims = glue("A{row_num}:G{row_num}"),
                    color = wb_color("FFE5E5E5"))
      }
    }
  }

  # Column widths
  wb$set_col_widths(sheet = sheet_name, cols = 1:7, widths = c(20, 15, 20, 12, 15, 15, 12))
}


# Save workbook
wb$save(OUTPUT_XLSX)
message(glue("XLSX saved: {OUTPUT_XLSX}"))


# --- SECTION 8: FINAL SUMMARY ---

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
