# ==============================================================================
# 25_treatment_durations.R -- Treatment Duration Analysis
# ==============================================================================
# Purpose:     Extract treatment dates from 7 PCORnet tables, calculate per-patient
#              duration metrics (span, date count, episodes) with 90-day gap threshold.
#
# Inputs:      PCORnet CDM tables (7 tables via extract_all_dates: PROCEDURES,
#              PRESCRIBING, MED_ADMIN, DIAGNOSIS, ENCOUNTER, DISPENSING, TUMOR_REGISTRY)
#
# Outputs:     cache/outputs/treatment_durations.rds, output/treatment_durations.xlsx,
#              output/treatment_duration_distributions.png
#
# Dependencies: R/00_config.R, R/01_load_pcornet.R
#
# Requirements: Phase 43 treatment duration (D-05 90-day window from episode start)
#
# WHY 90-day gap threshold: Clinical standard for oncology treatment cycles. Gaps >90
# days between treatment dates indicate separate episodes (relapse, new line of therapy)
# vs continuation of same regimen. Window-based splitting (90 days from episode start)
# prevents episodes >threshold.
#
# WHY all 7 PCORnet tables: Treatment evidence distributed across multiple tables
# (see R/20 for table-specific rationale). Comprehensive search maximizes detection.
#
# Decision traceability:
#   D-01: first-to-last span as overall_span_days
#   D-02: distinct_treatment_dates count for intensity metric
#   D-03: single-date patients produce span=0, count=1, episodes=1
#   D-04: compute BOTH overall span AND episode-level breakdown
#   D-05: 90-day window from episode start for episode splitting
#   D-07: RDS artifact with per-patient summary
#   D-08: styled xlsx report using openxlsx2
#   D-09: distribution visualization PNG
#   D-10: log summary stats (median, IQR, range) per type to console
#   D-11: multi-sheet organization (Summary + per-type detail sheets)
#   D-12: cover all four treatment types
#   D-13: all chemo codes pooled together (no regimen distinction)
# =============================================================================


# SECTION 1: SETUP AND CONFIGURATION ----

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(purrr)
  library(ggplot2)
  library(scales)
  library(openxlsx2)
  library(tidyr)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")

# SECTION 1b: INPUT VALIDATION ----
# SAFE-02: Validate critical PCORnet tables for treatment date extraction
assert_df_valid(
  pcornet$PROCEDURES, "PROCEDURES",
  required_cols = c("ID", "PX", "PX_TYPE", "PX_DATE"),
  script_name = "R/25"
)
assert_col_types(
  pcornet$PROCEDURES,
  type_spec = list(ID = "character"),
  script_name = "R/25"
)

# GAP_THRESHOLD: defined in R/00_config.R
# TREATMENT_TYPES: defined in R/00_config.R

# Output paths
# Per D-08: styled xlsx output
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "treatment_durations.xlsx")
# Per D-09: distribution visualization
OUTPUT_PNG <- file.path(CONFIG$output_dir, "treatment_duration_distributions.png")
# Per D-07: RDS artifact for downstream use
OUTPUT_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_durations.rds")

# TREATMENT_TYPE_COLORS: defined in R/00_config.R
# nrow_or_0(): provided by R/utils_treatment.R


# SECTION 2: MULTI-SOURCE DATE EXTRACTION FUNCTIONS ----

#' Extract all treatment dates for a given type from 7 PCORnet tables
#'
#' Returns a tibble with columns `ID` and `treatment_date` containing ALL
#' distinct treatment dates (not min/max). Each source is queried separately,
#' then stacked and deduplicated.
#'
#' @param type Character. One of "Chemotherapy", "Radiation", "Proton Therapy", "SCT", "Immunotherapy"
#' @return Tibble with columns: ID (character), treatment_date (Date)
extract_all_dates <- function(type) {
  message(glue("\n--- Extracting {type} dates ---"))

  if (type == "Chemotherapy") {
    return(extract_chemo_dates())
  } else if (type == "Radiation") {
    return(extract_radiation_dates())
  } else if (type == "Proton Therapy") {
    return(extract_proton_dates())
  } else if (type == "SCT") {
    return(extract_sct_dates())
  } else if (type == "Immunotherapy") {
    return(extract_immunotherapy_dates())
  } else {
    stop(glue("Unknown treatment type: {type}"))
  }
}

#' Extract all chemotherapy dates from 7 sources
#' Per D-13: all chemo codes pooled together -- no regimen distinction
extract_chemo_dates <- function() {
  # Build chemo ICD-10-PCS prefix regex
  chemo_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$chemo_icd10pcs_prefixes, collapse = "|"), ")")

  # 1. PROCEDURES: CPT/HCPCS, ICD-9-CM, ICD-10-PCS, revenue
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
      select(ID, treatment_date = PX_DATE, ENCOUNTERID) %>%
      collect()
  }

  # 2. PRESCRIBING: RXNORM_CUI matching
  rx_dates <- NULL
  if (!is.null(get_pcornet_table("PRESCRIBING")) &&
    "RXNORM_CUI" %in% colnames(get_pcornet_table("PRESCRIBING"))) {
    rx_dates <- get_pcornet_table("PRESCRIBING") %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      mutate(treatment_date = coalesce(RX_ORDER_DATE, RX_START_DATE)) %>%
      filter(!is.na(treatment_date)) %>%
      select(ID, treatment_date, ENCOUNTERID) %>%
      collect()
  }

  # 3. DIAGNOSIS: Z51.11/Z51.12 (ICD-10), V58.11/V58.12 (ICD-9)
  dx_dates <- NULL
  if (!is.null(get_pcornet_table("DIAGNOSIS"))) {
    dx_dates <- get_pcornet_table("DIAGNOSIS") %>%
      filter(
        (DX_TYPE == "10" & DX %in% TREATMENT_CODES$chemo_dx_icd10) |
          (DX_TYPE == "09" & DX %in% TREATMENT_CODES$chemo_dx_icd9)
      ) %>%
      filter(!is.na(DX_DATE)) %>%
      select(ID, treatment_date = DX_DATE, ENCOUNTERID) %>%
      collect()
  }

  # 4. ENCOUNTER: chemo DRGs
  drg_dates <- NULL
  if (!is.null(get_pcornet_table("ENCOUNTER"))) {
    drg_dates <- get_pcornet_table("ENCOUNTER") %>%
      filter(DRG %in% TREATMENT_CODES$chemo_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      select(ID, treatment_date = ADMIT_DATE, ENCOUNTERID) %>%
      collect()
  }

  # 5. DISPENSING: RXNORM_CUI matching
  disp_dates <- NULL
  if (!is.null(get_pcornet_table("DISPENSING")) &&
    "RXNORM_CUI" %in% colnames(get_pcornet_table("DISPENSING"))) {
    disp_dates <- get_pcornet_table("DISPENSING") %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      filter(!is.na(DISPENSE_DATE)) %>%
      select(ID, treatment_date = DISPENSE_DATE, ENCOUNTERID) %>%
      collect()
  }

  # 6. MED_ADMIN: RXNORM_CUI matching
  ma_dates <- NULL
  if (!is.null(get_pcornet_table("MED_ADMIN")) &&
    "RXNORM_CUI" %in% colnames(get_pcornet_table("MED_ADMIN"))) {
    ma_dates <- get_pcornet_table("MED_ADMIN") %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      filter(!is.na(MEDADMIN_START_DATE)) %>%
      select(ID, treatment_date = MEDADMIN_START_DATE, ENCOUNTERID) %>%
      collect()
  }

  # 7. TUMOR_REGISTRY_ALL: CHEMO_START_DATE_SUMMARY, DT_CHEMO
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
        # Pivot each date column to long format (treat as separate observations)
        tr_dates <- tr_data %>%
          pivot_longer(
            cols = all_of(tr_chemo_cols),
            names_to = "date_source",
            values_to = "treatment_date"
          ) %>%
          filter(!is.na(treatment_date)) %>%
          mutate(
            treatment_date = as.Date(treatment_date),
            ENCOUNTERID = NA_character_
          ) %>%
          select(ID, treatment_date, ENCOUNTERID)
      }
    }
  }

  # Stack all sources, deduplicate, log
  stack_and_dedup(
    sources = list(
      PX = px_dates, RX = rx_dates, DX = dx_dates,
      DRG = drg_dates, DISP = disp_dates, MA = ma_dates, TR = tr_dates
    ),
    type_name = "Chemotherapy"
  )
}

#' Extract all radiation dates from 4 sources
extract_radiation_dates <- function() {
  # Build radiation ICD-10-PCS prefix regex
  rad_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$radiation_icd10pcs_prefixes, collapse = "|"), ")")

  # 1. PROCEDURES: CPT, ICD-9-CM, ICD-10-PCS, revenue
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
      select(ID, treatment_date = PX_DATE, ENCOUNTERID) %>%
      collect()
  }

  # 2. DIAGNOSIS: Z51.0 (ICD-10), V58.0 (ICD-9)
  dx_dates <- NULL
  if (!is.null(get_pcornet_table("DIAGNOSIS"))) {
    dx_dates <- get_pcornet_table("DIAGNOSIS") %>%
      filter(
        (DX_TYPE == "10" & DX %in% TREATMENT_CODES$radiation_dx_icd10) |
          (DX_TYPE == "09" & DX %in% TREATMENT_CODES$radiation_dx_icd9)
      ) %>%
      filter(!is.na(DX_DATE)) %>%
      select(ID, treatment_date = DX_DATE, ENCOUNTERID) %>%
      collect()
  }

  # 3. ENCOUNTER: DRG 849
  drg_dates <- NULL
  if (!is.null(get_pcornet_table("ENCOUNTER"))) {
    drg_dates <- get_pcornet_table("ENCOUNTER") %>%
      filter(DRG %in% TREATMENT_CODES$radiation_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      select(ID, treatment_date = ADMIT_DATE, ENCOUNTERID) %>%
      collect()
  }

  # 4. TUMOR_REGISTRY_ALL: RAD_START_DATE_SUMMARY, DT_RAD
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
          pivot_longer(
            cols = all_of(tr_rad_cols),
            names_to = "date_source",
            values_to = "treatment_date"
          ) %>%
          filter(!is.na(treatment_date)) %>%
          mutate(
            treatment_date = as.Date(treatment_date),
            ENCOUNTERID = NA_character_
          ) %>%
          select(ID, treatment_date, ENCOUNTERID)
      }
    }
  }

  stack_and_dedup(
    sources = list(PX = px_dates, DX = dx_dates, DRG = drg_dates, TR = tr_dates),
    type_name = "Radiation"
  )
}

#' Extract all proton therapy dates from 1 source
#' Simpler than radiation -- only PROCEDURES CPT codes (no DX, DRG, TR, Revenue)
#' Uses default 90-day gap threshold (same as radiation); validate with clinical SME
extract_proton_dates <- function() {
  # 1. PROCEDURES: CPT codes only
  px_dates <- NULL
  if (!is.null(get_pcornet_table("PROCEDURES"))) {
    px_dates <- get_pcornet_table("PROCEDURES") %>%
      filter(PX_TYPE == "CH" & PX %in% TREATMENT_CODES$proton_cpt) %>%
      filter(!is.na(PX_DATE)) %>%
      select(ID, treatment_date = PX_DATE, ENCOUNTERID) %>%
      collect()
  }

  stack_and_dedup(
    sources = list(PX = px_dates),
    type_name = "Proton Therapy"
  )
}

#' Extract all SCT dates from 3 sources
extract_sct_dates <- function() {
  # 1. PROCEDURES: CPT/HCPCS, ICD-9-CM, ICD-10-PCS (exact match), revenue
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
      select(ID, treatment_date = PX_DATE, ENCOUNTERID) %>%
      collect()
  }

  # 2. ENCOUNTER: DRGs 014, 016, 017
  drg_dates <- NULL
  if (!is.null(get_pcornet_table("ENCOUNTER"))) {
    drg_dates <- get_pcornet_table("ENCOUNTER") %>%
      filter(DRG %in% TREATMENT_CODES$sct_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      select(ID, treatment_date = ADMIT_DATE, ENCOUNTERID) %>%
      collect()
  }

  # 3. TUMOR_REGISTRY_ALL: SCT-related date columns
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
        collect() %>%
        filter(if_any(all_of(tr_sct_cols), ~ !is.na(.)))
      if (nrow(tr_data) > 0) {
        tr_dates <- tr_data %>%
          pivot_longer(
            cols = all_of(tr_sct_cols),
            names_to = "date_source",
            values_to = "treatment_date"
          ) %>%
          filter(!is.na(treatment_date)) %>%
          mutate(
            treatment_date = as.Date(treatment_date),
            ENCOUNTERID = NA_character_
          ) %>%
          select(ID, treatment_date, ENCOUNTERID)
      }
    }
  }

  stack_and_dedup(
    sources = list(PX = px_dates, DRG = drg_dates, TR = tr_dates),
    type_name = "SCT"
  )
}

#' Extract all immunotherapy dates from 2 sources (PROCEDURES + ENCOUNTER)
#' No PRESCRIBING/DISPENSING/MED_ADMIN/DIAGNOSIS/TUMOR_REGISTRY sources for
#' immunotherapy -- the DX codes Z51.12/V58.12 are too generic (cover both
#' chemo and immunotherapy encounters, already captured under chemo per D-13).
extract_immunotherapy_dates <- function() {
  # Build CAR T-cell ICD-10-PCS prefix regex
  cart_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$cart_icd10pcs_prefixes, collapse = "|"), ")")

  # 1. PROCEDURES: ICD-10-PCS CAR T-cell codes (prefix match)
  px_dates <- NULL
  if (!is.null(get_pcornet_table("PROCEDURES"))) {
    px_dates <- get_pcornet_table("PROCEDURES") %>%
      filter(PX_TYPE == "10" & str_detect(PX, cart_icd10pcs_rx)) %>%
      filter(!is.na(PX_DATE)) %>%
      select(ID, treatment_date = PX_DATE, ENCOUNTERID) %>%
      collect()
  }

  # 2. ENCOUNTER: DRG 018 (Chimeric Antigen Receptor T-cell Immunotherapy)
  # DRG 018 from CMS MS-DRG classification, now in TREATMENT_CODES$immunotherapy_drg
  drg_dates <- NULL
  if (!is.null(get_pcornet_table("ENCOUNTER"))) {
    drg_dates <- get_pcornet_table("ENCOUNTER") %>%
      filter(DRG %in% TREATMENT_CODES$immunotherapy_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      select(ID, treatment_date = ADMIT_DATE, ENCOUNTERID) %>%
      collect()
  }

  stack_and_dedup(
    sources = list(PX = px_dates, DRG = drg_dates),
    type_name = "Immunotherapy"
  )
}

#' Stack all date sources, deduplicate same-day records, and log counts
#'
#' CRITICAL per Pitfall 2: distinct(ID, treatment_date) removes same-day
#' records across sources (e.g., a procedure AND a diagnosis on the same day
#' should count as one treatment date, not two).
#'
#' Phase 60: accepts 3-column input (ID, treatment_date, ENCOUNTERID) but
#' returns 2-column output (ID, treatment_date) for R/43a compatibility.
#' ENCOUNTERID is extracted for consistency with R/44a but not needed in
#' R/43a's patient-level duration summary.
#'
#' @param sources Named list of tibbles (each with ID + treatment_date + ENCOUNTERID), NULLs allowed
#' @param type_name Character. Treatment type name for logging
#' @return Tibble with columns: ID (character), treatment_date (Date)
stack_and_dedup <- function(sources, type_name) {
  # Log source-level counts
  source_counts <- sapply(names(sources), function(nm) nrow_or_0(sources[[nm]]))
  count_str <- paste(paste0(names(source_counts), "=", source_counts), collapse = ", ")
  message(glue("  {type_name} date sources: {count_str}"))

  # Filter out NULLs
  non_null <- compact(sources)

  if (length(non_null) == 0) {
    message(glue("  {type_name}: 0 patients, 0 distinct patient-dates"))
    return(tibble(ID = character(0), treatment_date = as.Date(character(0))))
  }

  # Stack all sources
  stacked <- bind_rows(non_null)

  # Ensure treatment_date is Date class (DuckDB returns Date already,
  # but TUMOR_REGISTRY fields may be character or POSIXct)
  stacked <- stacked %>%
    mutate(treatment_date = as.Date(treatment_date))

  # Remove NA dates
  stacked <- stacked %>%
    filter(!is.na(treatment_date))

  n_before <- nrow(stacked)

  # CRITICAL: deduplicate same-day records across sources
  # Drop ENCOUNTERID after stacking -- not needed for R/43a's patient-level output
  result <- stacked %>%
    distinct(ID, treatment_date) %>%
    arrange(ID, treatment_date)

  n_after <- nrow(result)
  n_patients <- n_distinct(result$ID)

  message(glue("  {type_name}: {n_patients} patients, {n_after} distinct patient-dates (deduped from {n_before} raw rows)"))

  result
}


# --- SECTION 3: DURATION AND EPISODE CALCULATION ---

#' Assign episode IDs using a window-based approach
#'
#' A new episode starts whenever a treatment date falls >= gap_threshold days
#' from the current episode's start date (not from the previous date).
#' This ensures no episode spans more than gap_threshold days from its first date.
#'
#' @param dates Date vector, must be sorted ascending
#' @param gap_threshold Numeric. Max days from episode start before a new episode begins
#' @return Integer vector of episode IDs (1-based)
assign_episode_ids <- function(dates, gap_threshold) {
  n <- length(dates)
  if (n == 0) {
    return(integer(0))
  }

  episode_ids <- integer(n)
  episode_ids[1] <- 1L
  current_episode <- 1L
  episode_start <- dates[1]

  for (i in seq_along(dates)[-1]) {
    if (as.numeric(dates[i] - episode_start) >= gap_threshold) {
      current_episode <- current_episode + 1L
      episode_start <- dates[i]
    }
    episode_ids[i] <- current_episode
  }

  episode_ids
}

#' Calculate per-patient treatment durations and episode counts
#'
#' Per D-01: first-to-last span as overall_span_days
#' Per D-02: distinct_treatment_dates count for intensity metric
#' Per D-03: single-date patients produce span=0, count=1, episodes=1
#' Per D-04: compute BOTH overall span AND episode-level breakdown
#' Per D-05: 90-day window from episode start for episode splitting
#'
#' @param dates_df Tibble with columns ID and treatment_date
#' @param gap_threshold Integer. Max days from episode start to define cycle boundary
#' @return Tibble with one row per patient: ID, first_treatment_date, last_treatment_date,
#'   overall_span_days, distinct_treatment_dates, episode_count
calculate_durations_and_episodes <- function(dates_df, gap_threshold = GAP_THRESHOLD) {
  if (nrow(dates_df) == 0) {
    return(tibble(
      ID = character(0),
      first_treatment_date = as.Date(character(0)),
      last_treatment_date = as.Date(character(0)),
      overall_span_days = numeric(0),
      distinct_treatment_dates = integer(0),
      episode_count = integer(0)
    ))
  }

  dates_df %>%
    group_by(ID) %>%
    arrange(treatment_date, .by_group = TRUE) %>%
    mutate(
      # Per D-05: window-based episode splitting (date - episode_start >= threshold)
      episode_id = assign_episode_ids(treatment_date, gap_threshold)
    ) %>%
    # Per-episode summary first (per D-04: detect separate episodes)
    group_by(ID, episode_id) %>%
    summarise(
      episode_first_date = min(treatment_date),
      episode_last_date = max(treatment_date),
      episode_span_days = as.numeric(max(treatment_date) - min(treatment_date)),
      episode_distinct_dates = n(),
      .groups = "drop_last"
    ) %>%
    # Per D-07: per-patient summary output shape (one row per patient per type)
    summarise(
      first_treatment_date = min(episode_first_date), # Per D-01: first date
      last_treatment_date = max(episode_last_date), # Per D-01: last date
      overall_span_days = as.numeric(max(episode_last_date) - min(episode_first_date)),
      distinct_treatment_dates = sum(episode_distinct_dates), # Per D-02: count
      episode_count = n(), # Per D-04: episodes
      .groups = "drop"
    )
}


# --- SECTION 4: MAIN EXECUTION LOOP + CONSOLE STATS + RDS SAVE ---

#' Log summary statistics for a treatment type's durations
#' Per D-10: median, IQR, range per type to console
log_duration_stats <- function(durations_df, type_name) {
  if (nrow(durations_df) == 0) {
    message(glue("\n  {type_name} Summary: 0 patients (no data)"))
    return(invisible(NULL))
  }

  stats <- durations_df %>%
    summarise(
      n = n(),
      median_span = median(overall_span_days, na.rm = TRUE),
      q1_span = quantile(overall_span_days, 0.25, na.rm = TRUE),
      q3_span = quantile(overall_span_days, 0.75, na.rm = TRUE),
      min_span = min(overall_span_days, na.rm = TRUE),
      max_span = max(overall_span_days, na.rm = TRUE),
      median_dates = median(distinct_treatment_dates, na.rm = TRUE),
      median_episodes = median(episode_count, na.rm = TRUE)
    )

  message(glue("\n  {type_name} Summary:"))
  message(glue("    Patients: {stats$n}"))
  message(glue("    Span (days): median={stats$median_span}, IQR=[{stats$q1_span}, {stats$q3_span}], range=[{stats$min_span}, {stats$max_span}]"))
  message(glue("    Distinct dates: median={stats$median_dates}"))
  message(glue("    Episodes: median={stats$median_episodes}"))

  invisible(stats)
}


# --- SECTION 2a: ENCOUNTERID POPULATION RATE INSPECTION (Phase 60, D-05) ---

message("\n=== ENCOUNTERID Population Rate Inspection ===")

# Tables to inspect: PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, ENCOUNTER, DIAGNOSIS
inspect_tables <- c("PROCEDURES", "PRESCRIBING", "DISPENSING", "MED_ADMIN", "ENCOUNTER", "DIAGNOSIS")

encounterid_profile <- map_dfr(inspect_tables, function(tbl_name) {
  tbl <- get_pcornet_table(tbl_name)
  if (is.null(tbl)) {
    return(tibble(
      table = tbl_name,
      total_rows = 0L,
      encounterid_populated = 0L,
      population_rate = 0.0
    ))
  }

  # Guard: some tables (e.g., DISPENSING) lack ENCOUNTERID

  if (!"ENCOUNTERID" %in% colnames(tbl)) {
    stats <- tbl %>%
      summarise(total_rows = n()) %>%
      collect()
    return(tibble(
      table = tbl_name,
      total_rows = as.integer(stats$total_rows),
      encounterid_populated = NA_integer_,
      population_rate = NA_real_
    ))
  }

  stats <- tbl %>%
    summarise(
      total_rows = n(),
      encounterid_populated = sum(!is.na(ENCOUNTERID), na.rm = TRUE)
    ) %>%
    collect()

  tibble(
    table = tbl_name,
    total_rows = as.integer(stats$total_rows),
    encounterid_populated = as.integer(stats$encounterid_populated),
    population_rate = round(100 * stats$encounterid_populated / stats$total_rows, 1)
  )
})

# Log to console
message("\nENCOUNTERID Population Rates by Table:")
for (i in seq_len(nrow(encounterid_profile))) {
  row <- encounterid_profile[i, ]
  message(glue("  {row$table}: {row$encounterid_populated}/{row$total_rows} ({row$population_rate}%)"))
}

# Save for Plan 03 xlsx
encounterid_profile_path <- file.path(CONFIG$cache$outputs_dir, "encounterid_profile.rds")
saveRDS(encounterid_profile, encounterid_profile_path)
message(glue("\nSaved: {encounterid_profile_path}"))


# --- SECTION 2b: SCT SOURCE AUDIT (Phase 60, D-13, D-14, TREAT-01) ---

message("\n=== SCT Source Audit: Pre/Post DX Code Removal ===")

# Define temporary audit function (NO DX codes) inline
extract_sct_dates_no_dx <- function() {
  # 1. PROCEDURES: CPT/HCPCS, ICD-9-CM, ICD-10-PCS (exact match), revenue
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
      select(ID, treatment_date = PX_DATE) %>%
      collect()
  }

  # 2. ENCOUNTER: DRGs 014, 016, 017
  drg_dates <- NULL
  if (!is.null(get_pcornet_table("ENCOUNTER"))) {
    drg_dates <- get_pcornet_table("ENCOUNTER") %>%
      filter(DRG %in% TREATMENT_CODES$sct_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      select(ID, treatment_date = ADMIT_DATE) %>%
      collect()
  }

  # 3. TUMOR_REGISTRY_ALL: SCT-related date columns
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
        collect() %>%
        filter(if_any(all_of(tr_sct_cols), ~ !is.na(.)))
      if (nrow(tr_data) > 0) {
        tr_dates <- tr_data %>%
          pivot_longer(
            cols = all_of(tr_sct_cols),
            names_to = "date_source",
            values_to = "treatment_date"
          ) %>%
          filter(!is.na(treatment_date)) %>%
          mutate(treatment_date = as.Date(treatment_date)) %>%
          select(ID, treatment_date)
      }
    }
  }

  stack_and_dedup(
    sources = list(PX = px_dates, DRG = drg_dates, TR = tr_dates),
    type_name = "SCT (no DX)"
  )
}

# Run audit: WITH DX codes (current extract_sct_dates)
sct_with_dx <- extract_sct_dates()

# Run audit: WITHOUT DX codes (temporary function)
sct_without_dx <- extract_sct_dates_no_dx()

# Compute delta
patients_with_dx <- n_distinct(sct_with_dx$ID)
patients_without_dx <- n_distinct(sct_without_dx$ID)
patients_lost <- setdiff(unique(sct_with_dx$ID), unique(sct_without_dx$ID))
n_lost <- length(patients_lost)
retention_rate <- if (patients_with_dx > 0) round(100 * patients_without_dx / patients_with_dx, 1) else 0

sct_audit_result <- tibble(
  metric = c(
    "Patients with SCT (WITH DX codes)",
    "Patients with SCT (WITHOUT DX codes)",
    "Patients lost (DX-only detection)",
    "Retention rate"
  ),
  value = c(
    as.character(patients_with_dx),
    as.character(patients_without_dx),
    as.character(n_lost),
    paste0(retention_rate, "%")
  )
)

# Log to console
message("\nSCT Source Audit Results:")
for (i in seq_len(nrow(sct_audit_result))) {
  row <- sct_audit_result[i, ]
  message(glue("  {row$metric}: {row$value}"))
}

# Save for Plan 03 xlsx
sct_audit_result_path <- file.path(CONFIG$cache$outputs_dir, "sct_audit_result.rds")
saveRDS(sct_audit_result, sct_audit_result_path)
message(glue("\nSaved: {sct_audit_result_path}"))


message("\n=== Phase 43: Treatment Duration Analysis ===\n")

# Per D-12: loop over all four treatment types
results_list <- list()

for (type in TREATMENT_TYPES) {
  # Extract all dates
  dates_df <- extract_all_dates(type)

  # Calculate durations and episodes
  durations_df <- calculate_durations_and_episodes(dates_df)

  # Add treatment type column
  durations_df <- durations_df %>%
    mutate(treatment_type = type)

  # Log summary stats
  log_duration_stats(durations_df, type)

  results_list[[type]] <- durations_df
}

# Per D-07: combine into single artifact with treatment_type column
# Column order: ID, treatment_type, first_treatment_date, last_treatment_date,
#   overall_span_days, distinct_treatment_dates, episode_count
all_durations <- bind_rows(results_list) %>%
  select(
    ID, treatment_type, first_treatment_date, last_treatment_date,
    overall_span_days, distinct_treatment_dates, episode_count
  )

# SAFE-02: Validate treatment_durations output
assert_df_valid(
  all_durations, "treatment_durations",
  required_cols = c("ID", "treatment_type", "first_treatment_date", "last_treatment_date"),
  script_name = "R/25"
)
warn_date_range(all_durations, "first_treatment_date",
                as.Date("1990-01-01"), as.Date("2030-12-31"),
                script_name = "R/25")

# Save RDS artifact
saveRDS(all_durations, OUTPUT_RDS)
message(glue("\nRDS saved: {OUTPUT_RDS} ({nrow(all_durations)} rows)"))


# --- SECTION 4b: PER-TYPE CSV OUTPUT ---

message("\n--- Writing per-type CSV files ---")

for (type in TREATMENT_TYPES) {
  type_data <- results_list[[type]]

  # Build clean filename: lowercase, underscored
  csv_name <- paste0(tolower(gsub(" ", "_", type)), "_durations.csv")
  csv_path <- file.path(CONFIG$output_dir, csv_name)

  # Clean column names: snake_case, no spaces or parens
  write_df <- type_data %>%
    rename(patient_id = ID) %>%
    select(
      patient_id, first_treatment_date, last_treatment_date,
      overall_span_days, distinct_treatment_dates, episode_count
    )

  write.csv(write_df, csv_path, row.names = FALSE)
  message(glue("  Wrote {csv_path} ({nrow(write_df)} rows)"))
}


# --- SECTION 5: STYLED XLSX REPORT ---

# Per D-08: styled xlsx report using openxlsx2
# Per D-11: multi-sheet organization (Summary + per-type detail sheets)

message("\n--- Writing styled xlsx report ---")

wb <- wb_workbook()

# --- Sheet 1: Summary ---
wb$add_worksheet("Summary")

# Row 1: Title
wb$add_data(
  sheet = "Summary", x = "Treatment Duration Analysis",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Summary", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Summary", dims = "A1:F1")

# Row 2: Subtitle with date
wb$add_data(
  sheet = "Summary",
  x = as.character(glue("Generated: {Sys.Date()} | Gap threshold: {GAP_THRESHOLD} days")),
  start_row = 2, start_col = 1
)
wb$add_font(
  sheet = "Summary", dims = "A2",
  name = "Calibri", size = 10, color = wb_color("FF6B7280")
)
wb$merge_cells(sheet = "Summary", dims = "A2:F2")

# Row 4: Headers
summary_headers <- c(
  "Treatment Type", "Patients", "Median Span (days)",
  "IQR", "Median Distinct Dates", "Median Episodes"
)
for (i in seq_along(summary_headers)) {
  wb$add_data(
    sheet = "Summary", x = summary_headers[i],
    start_row = 4, start_col = i
  )
}
wb$add_fill(sheet = "Summary", dims = "A4:F4", color = wb_color("FF374151"))
wb$add_font(
  sheet = "Summary", dims = "A4:F4",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)

# Row 5+: One row per treatment type
for (i in seq_along(TREATMENT_TYPES)) {
  type <- TREATMENT_TYPES[i]
  row_num <- 4 + i
  type_data <- results_list[[type]]

  if (nrow(type_data) == 0) {
    wb$add_data(sheet = "Summary", x = type, start_row = row_num, start_col = 1)
    wb$add_data(sheet = "Summary", x = 0L, start_row = row_num, start_col = 2)
    wb$add_data(sheet = "Summary", x = "N/A", start_row = row_num, start_col = 3)
    wb$add_data(sheet = "Summary", x = "N/A", start_row = row_num, start_col = 4)
    wb$add_data(sheet = "Summary", x = "N/A", start_row = row_num, start_col = 5)
    wb$add_data(sheet = "Summary", x = "N/A", start_row = row_num, start_col = 6)
    next
  }

  stats <- type_data %>%
    summarise(
      n = n(),
      median_span = median(overall_span_days, na.rm = TRUE),
      q1 = quantile(overall_span_days, 0.25, na.rm = TRUE),
      q3 = quantile(overall_span_days, 0.75, na.rm = TRUE),
      median_dates = median(distinct_treatment_dates, na.rm = TRUE),
      median_episodes = median(episode_count, na.rm = TRUE)
    )

  iqr_str <- glue("[{stats$q1}, {stats$q3}]")

  wb$add_data(sheet = "Summary", x = type, start_row = row_num, start_col = 1)
  wb$add_data(sheet = "Summary", x = as.integer(stats$n), start_row = row_num, start_col = 2)
  wb$add_data(sheet = "Summary", x = stats$median_span, start_row = row_num, start_col = 3)
  wb$add_data(sheet = "Summary", x = as.character(iqr_str), start_row = row_num, start_col = 4)
  wb$add_data(sheet = "Summary", x = stats$median_dates, start_row = row_num, start_col = 5)
  wb$add_data(sheet = "Summary", x = stats$median_episodes, start_row = row_num, start_col = 6)

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

# Number formatting on summary
summary_last_row <- 4 + length(TREATMENT_TYPES)
wb$add_numfmt(sheet = "Summary", dims = glue("B5:B{summary_last_row}"), numfmt = "#,##0")
wb$add_numfmt(sheet = "Summary", dims = glue("C5:C{summary_last_row}"), numfmt = "#,##0")
wb$add_numfmt(sheet = "Summary", dims = glue("E5:E{summary_last_row}"), numfmt = "#,##0")

# Summary column widths
wb$set_col_widths(sheet = "Summary", cols = 1:6, widths = c(20, 12, 20, 18, 22, 18))

# --- Sheets 2-5: Per-type detail sheets ---
for (type in TREATMENT_TYPES) {
  type_data <- results_list[[type]]
  sheet_name <- paste(type, "Durations")
  n_patients <- nrow(type_data)

  message(glue("  Writing {sheet_name} ({n_patients} patients)..."))

  wb$add_worksheet(sheet_name)

  fill_color <- TREATMENT_TYPE_COLORS[[type]]$fill
  font_color <- TREATMENT_TYPE_COLORS[[type]]$font

  # Row 1: Title
  title_text <- glue("{type} Treatment Durations ({n_patients} patients)")
  wb$add_data(
    sheet = sheet_name, x = as.character(title_text),
    start_row = 1, start_col = 1
  )
  wb$add_font(
    sheet = sheet_name, dims = "A1",
    name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
  )
  wb$merge_cells(sheet = sheet_name, dims = "A1:F1")

  # Row 2: Headers
  detail_headers <- c(
    "Patient ID", "First Date", "Last Date",
    "Span (days)", "Distinct Dates", "Episodes"
  )
  for (j in seq_along(detail_headers)) {
    wb$add_data(
      sheet = sheet_name, x = detail_headers[j],
      start_row = 2, start_col = j
    )
  }
  # Header styling: TREATMENT_TYPE_COLORS fill + font
  wb$add_fill(sheet = sheet_name, dims = "A2:F2", color = wb_color(fill_color))
  wb$add_font(
    sheet = sheet_name, dims = "A2:F2",
    name = "Calibri", size = 11, bold = TRUE, color = wb_color(font_color)
  )

  # Row 3+: Data (bulk write)
  if (n_patients > 0) {
    write_df <- data.frame(
      Patient_ID = type_data$ID,
      First_Date = as.character(type_data$first_treatment_date),
      Last_Date = as.character(type_data$last_treatment_date),
      Span_Days = type_data$overall_span_days,
      Distinct_Dates = type_data$distinct_treatment_dates,
      Episodes = type_data$episode_count,
      stringsAsFactors = FALSE
    )
    wb$add_data(sheet = sheet_name, x = write_df, start_row = 3, col_names = FALSE)

    # Number formatting on Span/Distinct Dates/Episodes columns (D, E, F)
    last_row <- 2 + n_patients
    wb$add_numfmt(sheet = sheet_name, dims = glue("D3:F{last_row}"), numfmt = "#,##0")
  }

  # Column widths
  wb$set_col_widths(sheet = sheet_name, cols = 1:6, widths = c(20, 15, 15, 15, 15, 12))
}

# Save workbook
wb$save(OUTPUT_XLSX)
message(glue("  Saved: {OUTPUT_XLSX}"))


# --- SECTION 6: DISTRIBUTION VISUALIZATION ---

# Per D-09: distribution visualization -- PNG output showing treatment duration spread by type

message("\n--- Creating distribution visualization ---")

if (nrow(all_durations) > 0) {
  # Single boxplot with jittered points (cleanest for comparing types)
  p <- ggplot(
    all_durations,
    aes(x = treatment_type, y = overall_span_days, fill = treatment_type)
  ) +
    geom_boxplot(outlier.alpha = 0.3) +
    geom_jitter(width = 0.2, alpha = 0.1, size = 0.5) +
    labs(
      title = "Treatment Duration Distribution by Type",
      subtitle = glue("N = {nrow(all_durations)} patients across {length(unique(all_durations$treatment_type))} treatment types | 90-day episode gap threshold"),
      x = "Treatment Type",
      y = "Duration (days, first to last treatment date)"
    ) +
    scale_fill_manual(values = c(
      "Chemotherapy" = "#DCEEFB",
      "Radiation" = "#DDF4E1",
      "SCT" = "#FFF4D6",
      "Immunotherapy" = "#E8DCF4"
    )) +
    theme_minimal(base_size = 12) +
    theme(legend.position = "none")

  ggsave(OUTPUT_PNG, plot = p, width = 10, height = 6, dpi = 300)
  message(glue("  Saved: {OUTPUT_PNG}"))
} else {
  message("  WARNING: No treatment durations to plot -- skipping PNG output")
}


# --- Final Summary ---

message(glue("\n=== Phase 43 Complete ==="))
message(glue("Outputs:"))
message(glue("  RDS:  {OUTPUT_RDS}"))
message(glue("  CSVs: {CONFIG$output_dir}/{{chemotherapy,radiation,sct,immunotherapy}}_durations.csv"))
message(glue("  XLSX: {OUTPUT_XLSX}"))
message(glue("  PNG:  {OUTPUT_PNG}"))
message(glue("Total patients: {nrow(all_durations)} across {length(unique(all_durations$treatment_type))} treatment types"))
