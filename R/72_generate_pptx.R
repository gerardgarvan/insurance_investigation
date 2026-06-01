# ==============================================================================
# 72_generate_pptx.R -- Generate insurance tables PowerPoint
# ==============================================================================
#
# Produces insurance_tables_YYYY-MM-DD.pptx matching the Python pipeline's
# 15-slide output, computed entirely from R pipeline data.
#
# Slides:
#   1. Definitions & Glossary
#   2. Insurance Coverage Overview (Primary + First Dx, all patients)
#   3. Post-Treatment Insurance (all patients)
#   4. Chemotherapy Insurance (Primary + First + Last Chemo)
#   5. Chemotherapy Post-Treatment Insurance
#   6. Radiation Insurance (Primary + First + Last Radiation)
#   7. Radiation Post-Treatment Insurance
#   8. SCT Insurance (Primary + First + Last SCT)
#   9. SCT Post-Treatment Insurance
#  10. Diagnosis - Insurance by Enrollment Coverage
#  11. Chemotherapy - Insurance by Enrollment Coverage
#  12. Radiation - Insurance by Enrollment Coverage
#  13. SCT - Insurance by Enrollment Coverage
#  14. Last Treatment = Last Encounter
#  15. Missing Post-Treatment Payer - Encounter Breakdown
#  16. Insurance After Last Treatment - Dataset Retention (still in dataset vs missing)
#  17. Encounters per Person by Payer Category (histogram)
#  18. Summary Statistics: Encounters per Payer Category (table)
#  19. Mean Post-Treatment Encounters by Year of Diagnosis
#  20. Mean Total Encounters by Year of Diagnosis
#  21. Post-Treatment Encounter Presence by Age Group
#  22. Unique Encounter Dates per Person by Payer Category (histogram)
#  23. Summary Statistics: Unique Dates per Payer Category (table)
#  24. Mean Post-Treatment Unique Dates by Year of Diagnosis
#  25. Mean Total Unique Dates by Year of Diagnosis
#  26. Unique Encounter Dates per Person by Payer (Post-Last Treatment) [VIZP-02]
#  27. Stacked Encounters Pre/Post-Treatment by Payer [VIZP-03]
#  28. Summary Statistics: Pre/Post-Treatment Encounters by Payer [VIZP-03]
#  29. Stacked Unique Dates Pre/Post-Treatment by Payer
#  30. Summary Statistics: Pre/Post-Treatment Unique Dates by Payer
#  --- Treated Only / Unique Dates Section (versions of 17-30) ---
#  31. Unique Encounter Dates per Person by Payer (Treated Only) [histogram]
#  32. Summary Statistics: Unique Dates per Payer (Treated Only) [table]
#  33. Median Post-Treatment Unique Dates by Year of Diagnosis (Treated Only)
#  34. Median Total Unique Dates by Year of Diagnosis (Treated Only)
#  35. Post-Treatment Encounter Presence by Age Group (Treated Only)
#  36. Unique Encounter Dates Post-Last Treatment (Treated Only) [table]
#  37. Stacked Unique Dates Pre/Post-Treatment by Payer (Treated Only)
#  38. Summary Statistics: Pre/Post Unique Dates by Payer (Treated Only) [table]
#  --- Phase 21: Payer Missingness Slides (Section 8) ---
#  39. Payer Missingness: Cross-Site Comparison [grouped bar chart]
#  40. Primary Payer Missingness by Site [bar chart]
#  41. Raw PAYER_TYPE_PRIMARY: Top 5 Values per Site [faceted bar chart]
#  42. Payer Missingness by Encounter Type and Site [heatmap]
#  43. Primary Payer Missingness by Encounter Type (All Sites) [bar chart]
#  44. Raw vs Harmonized Payer Missingness by Site [dumbbell chart]
#  45. Highest Missingness: Year x Enc Type Combinations [table]
#  46. Payer Missingness by Year (Recent 5 Years per Site) [line chart]
#  --- Phase 22: Duplicate Date Slides (Section 9) ---
#  47. Duplicate Dates: Cross-Site Comparison [bar chart]
#  48. Duplicate Rate vs Cohort Size [scatter plot]
#  49. Key Duplication Metrics by Partner Site [grouped bar chart]
#  50. Source Payer Completeness for Multi-Source Dates [heatmap]
#  51. Patient Duplicate Summary by Site [grouped bar chart]
#  52. Multi-Source Dates: Payer Missingness by Source [heatmap]
#
# Dependencies:
#   - 14_build_cohort.R must be sourced first (produces hl_cohort, pcornet,
#     encounters, payer_summary in the global environment)
#   - 75_encounter_analysis.R is sourced automatically to regenerate PNG figures
#     in output/figures/ (slides 17-20, 22-25 will be skipped if PNGs are absent)
#   - Packages: officer, flextable, dplyr, glue, lubridate, purrr, scales
#
# Usage:
#   source("R/14_build_cohort.R")  # Build cohort first
#   source("R/72_generate_pptx.R") # Generate PPTX
#
# ==============================================================================

library(officer)
library(flextable)
library(dplyr)
library(glue)
library(lubridate)
library(purrr)
library(scales)
library(stringr)
library(readr)
library(tidyr)

# Load shared pptx styling utilities
source("R/utils/utils_pptx.R")

message("\n", strrep("=", 60))
message("Generating Insurance Tables PowerPoint")
message(strrep("=", 60))

# ==============================================================================
# SECTION 1: CONFIGURATION
# ==============================================================================

# Payer category display order (AMC 8-category; Other/Other govt collapse to Missing for display)
PAYER_ORDER <- c(
  "Medicare", "Medicaid", "Private",
  "Self-pay", "Uninsured", "Missing"
)

# Map AMC category names to PPTX display names
# Collapses Other, Other govt, and NA into "Missing"
rename_payer <- function(x) {
  case_when(
    x %in% c("Other", "Other govt") ~ "Missing",
    is.na(x)                         ~ "Missing",
    TRUE ~ x
  )
}

format_count_pct <- function(n, total) {
  pct <- round(100 * n / total, 1)
  count_str <- format(n, big.mark = ",")
  pct_str <- paste0(pct, "%")
  paste0(count_str, " (", pct_str, ")")
}

# Treatment window (days)
WINDOW_DAYS <- CONFIG$analysis$treatment_window_days  # 30

# PPTX color constants provided by R/utils_pptx.R

# ==============================================================================
# SECTION 2: COMPUTE ADDITIONAL DATA (last treatment, post-treatment, enrollment)
# ==============================================================================

message("\n--- Computing additional payer data for PPTX ---")

# ---- 2a. Last treatment dates (max across all sources, mirrors 10_treatment_payer.R) ----

compute_last_dates <- function(treatment_type) {
  # Reuses the same source-extraction logic as 10_treatment_payer.R
  # but takes max() instead of min()

  # Build prefix regexes once (config defines these as prefixes, not exact codes)
  chemo_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$chemo_icd10pcs_prefixes, collapse = "|"), ")")
  rad_icd10pcs_rx <- paste0("^(", paste(TREATMENT_CODES$radiation_icd10pcs_prefixes, collapse = "|"), ")")

  if (treatment_type == "chemo") {
    sources <- list()
    if (!is.null(pcornet$PROCEDURES)) {
      sources$px <- pcornet$PROCEDURES %>%
        filter(
          (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) |
          (PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9) |
          (PX_TYPE == "10" & str_detect(PX, chemo_icd10pcs_rx))
        ) %>% filter(!is.na(PX_DATE)) %>%
        group_by(ID) %>% summarise(d = max(PX_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$PRESCRIBING)) {
      sources$rx <- pcornet$PRESCRIBING %>%
        filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
        filter(!is.na(RX_ORDER_DATE) | !is.na(RX_START_DATE)) %>%
        mutate(d = coalesce(RX_ORDER_DATE, RX_START_DATE)) %>%
        filter(!is.na(d)) %>%
        group_by(ID) %>% summarise(d = max(d, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$DIAGNOSIS)) {
      sources$dx <- pcornet$DIAGNOSIS %>%
        filter(
          (DX_TYPE == "10" & DX %in% TREATMENT_CODES$chemo_dx_icd10) |
          (DX_TYPE == "09" & DX %in% TREATMENT_CODES$chemo_dx_icd9)
        ) %>% filter(!is.na(DX_DATE)) %>%
        group_by(ID) %>% summarise(d = max(DX_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$ENCOUNTER)) {
      sources$drg <- pcornet$ENCOUNTER %>%
        filter(DRG %in% TREATMENT_CODES$chemo_drg) %>%
        filter(!is.na(ADMIT_DATE)) %>%
        group_by(ID) %>% summarise(d = max(ADMIT_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$DISPENSING) && "RXNORM_CUI" %in% names(pcornet$DISPENSING)) {
      sources$disp <- pcornet$DISPENSING %>%
        filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
        filter(!is.na(DISPENSE_DATE)) %>%
        group_by(ID) %>% summarise(d = max(DISPENSE_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$MED_ADMIN) && "RXNORM_CUI" %in% names(pcornet$MED_ADMIN)) {
      sources$ma <- pcornet$MED_ADMIN %>%
        filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
        filter(!is.na(MEDADMIN_START_DATE)) %>%
        group_by(ID) %>% summarise(d = max(MEDADMIN_START_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$PROCEDURES)) {
      sources$rev <- pcornet$PROCEDURES %>%
        filter(PX_TYPE == "RE" & PX %in% TREATMENT_CODES$chemo_revenue) %>%
        filter(!is.na(PX_DATE)) %>%
        group_by(ID) %>% summarise(d = max(PX_DATE, na.rm = TRUE), .groups = "drop")
    }
    # TUMOR_REGISTRY: chemo dates (CHEMO_START_DATE_SUMMARY, DT_CHEMO)
    if (!is.null(pcornet$TUMOR_REGISTRY_ALL)) {
      tr_chemo_cols <- intersect(
        c("CHEMO_START_DATE_SUMMARY", "DT_CHEMO"),
        names(pcornet$TUMOR_REGISTRY_ALL)
      )
      if (length(tr_chemo_cols) > 0) {
        tr_data <- pcornet$TUMOR_REGISTRY_ALL %>%
          select(ID, all_of(tr_chemo_cols)) %>%
          filter(if_any(all_of(tr_chemo_cols), ~ !is.na(.)))
        if (nrow(tr_data) > 0) {
          if (length(tr_chemo_cols) == 1) {
            tr_data$d <- tr_data[[tr_chemo_cols[1]]]
          } else {
            tr_data$d <- do.call(pmax, c(tr_data[tr_chemo_cols], na.rm = TRUE))
          }
          sources$tr <- tr_data %>%
            filter(!is.na(d)) %>%
            group_by(ID) %>%
            summarise(d = max(d, na.rm = TRUE), .groups = "drop")
        }
      }
    }

  } else if (treatment_type == "radiation") {
    sources <- list()
    if (!is.null(pcornet$PROCEDURES)) {
      sources$px <- pcornet$PROCEDURES %>%
        filter(
          (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$radiation_cpt) |
          (PX_TYPE == "09" & PX %in% TREATMENT_CODES$radiation_icd9) |
          (PX_TYPE == "10" & str_detect(PX, rad_icd10pcs_rx))
        ) %>% filter(!is.na(PX_DATE)) %>%
        group_by(ID) %>% summarise(d = max(PX_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$DIAGNOSIS)) {
      sources$dx <- pcornet$DIAGNOSIS %>%
        filter(
          (DX_TYPE == "10" & DX %in% TREATMENT_CODES$radiation_dx_icd10) |
          (DX_TYPE == "09" & DX %in% TREATMENT_CODES$radiation_dx_icd9)
        ) %>% filter(!is.na(DX_DATE)) %>%
        group_by(ID) %>% summarise(d = max(DX_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$ENCOUNTER)) {
      sources$drg <- pcornet$ENCOUNTER %>%
        filter(DRG %in% TREATMENT_CODES$radiation_drg) %>%
        filter(!is.na(ADMIT_DATE)) %>%
        group_by(ID) %>% summarise(d = max(ADMIT_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$PROCEDURES)) {
      sources$rev <- pcornet$PROCEDURES %>%
        filter(PX_TYPE == "RE" & PX %in% TREATMENT_CODES$radiation_revenue) %>%
        filter(!is.na(PX_DATE)) %>%
        group_by(ID) %>% summarise(d = max(PX_DATE, na.rm = TRUE), .groups = "drop")
    }
    # TUMOR_REGISTRY: radiation dates (RAD_START_DATE_SUMMARY, DT_RAD)
    if (!is.null(pcornet$TUMOR_REGISTRY_ALL)) {
      tr_rad_cols <- intersect(
        c("RAD_START_DATE_SUMMARY", "DT_RAD"),
        names(pcornet$TUMOR_REGISTRY_ALL)
      )
      if (length(tr_rad_cols) > 0) {
        tr_data <- pcornet$TUMOR_REGISTRY_ALL %>%
          select(ID, all_of(tr_rad_cols)) %>%
          filter(if_any(all_of(tr_rad_cols), ~ !is.na(.)))
        if (nrow(tr_data) > 0) {
          if (length(tr_rad_cols) == 1) {
            tr_data$d <- tr_data[[tr_rad_cols[1]]]
          } else {
            tr_data$d <- do.call(pmax, c(tr_data[tr_rad_cols], na.rm = TRUE))
          }
          sources$tr <- tr_data %>%
            filter(!is.na(d)) %>%
            group_by(ID) %>%
            summarise(d = max(d, na.rm = TRUE), .groups = "drop")
        }
      }
    }

  } else if (treatment_type == "sct") {
    sources <- list()
    if (!is.null(pcornet$PROCEDURES)) {
      sources$px <- pcornet$PROCEDURES %>%
        filter(
          (PX_TYPE == "CH" & PX %in% c(TREATMENT_CODES$sct_cpt, TREATMENT_CODES$sct_hcpcs)) |
          (PX_TYPE == "09" & PX %in% TREATMENT_CODES$sct_icd9) |
          (PX_TYPE == "10" & PX %in% TREATMENT_CODES$sct_icd10pcs)
        ) %>% filter(!is.na(PX_DATE)) %>%
        group_by(ID) %>% summarise(d = max(PX_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$DIAGNOSIS)) {
      sources$dx <- pcornet$DIAGNOSIS %>%
        filter(DX_TYPE == "10" & DX %in% TREATMENT_CODES$sct_dx_icd10) %>%
        filter(!is.na(DX_DATE)) %>%
        group_by(ID) %>% summarise(d = max(DX_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$ENCOUNTER)) {
      sources$drg <- pcornet$ENCOUNTER %>%
        filter(DRG %in% TREATMENT_CODES$sct_drg) %>%
        filter(!is.na(ADMIT_DATE)) %>%
        group_by(ID) %>% summarise(d = max(ADMIT_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$PROCEDURES)) {
      sources$rev <- pcornet$PROCEDURES %>%
        filter(PX_TYPE == "RE" & PX %in% TREATMENT_CODES$sct_revenue) %>%
        filter(!is.na(PX_DATE)) %>%
        group_by(ID) %>% summarise(d = max(PX_DATE, na.rm = TRUE), .groups = "drop")
    }
    # TUMOR_REGISTRY: SCT dates (DT_HTE, DT_SCT, SCT_DATE, BMT_DATE, etc.)
    if (!is.null(pcornet$TUMOR_REGISTRY_ALL)) {
      tr_sct_cols <- intersect(
        c("DT_HTE", "DT_SCT", "SCT_DATE", "BMT_DATE",
          "TRANSPLANT_DATE", "HCT_DATE", "DT_TRANSPLANT"),
        names(pcornet$TUMOR_REGISTRY_ALL)
      )
      if (length(tr_sct_cols) > 0) {
        tr_data <- pcornet$TUMOR_REGISTRY_ALL %>%
          select(ID, all_of(tr_sct_cols)) %>%
          filter(if_any(all_of(tr_sct_cols), ~ !is.na(.)))
        if (nrow(tr_data) > 0) {
          if (length(tr_sct_cols) == 1) {
            tr_data$d <- tr_data[[tr_sct_cols[1]]]
          } else {
            tr_data$d <- do.call(pmax, c(tr_data[tr_sct_cols], na.rm = TRUE))
          }
          sources$tr <- tr_data %>%
            filter(!is.na(d)) %>%
            group_by(ID) %>%
            summarise(d = max(d, na.rm = TRUE), .groups = "drop")
        }
      }
    }
  }

  non_null <- compact(sources)
  if (length(non_null) == 0) return(tibble(ID = character(0), last_date = as.Date(character(0))))

  bind_rows(non_null) %>%
    group_by(ID) %>%
    summarise(last_date = max(d, na.rm = TRUE), .groups = "drop") %>%
    filter(!is.infinite(last_date))
}

# Compute last treatment dates
last_chemo_dates <- compute_last_dates("chemo") %>% rename(LAST_CHEMO_DATE = last_date)
last_rad_dates <- compute_last_dates("radiation") %>% rename(LAST_RADIATION_DATE = last_date)
last_sct_dates <- compute_last_dates("sct") %>% rename(LAST_SCT_DATE = last_date)

message(glue("  Last chemo dates: {nrow(last_chemo_dates)} patients"))
message(glue("  Last radiation dates: {nrow(last_rad_dates)} patients"))
message(glue("  Last SCT dates: {nrow(last_sct_dates)} patients"))

# Filter 1900 sentinel dates from computed last treatment dates (per VIZP-01)
n_sentinel_last_chemo <- sum(year(last_chemo_dates$LAST_CHEMO_DATE) == 1900L, na.rm = TRUE)
n_sentinel_last_rad <- sum(year(last_rad_dates$LAST_RADIATION_DATE) == 1900L, na.rm = TRUE)
n_sentinel_last_sct <- sum(year(last_sct_dates$LAST_SCT_DATE) == 1900L, na.rm = TRUE)
n_sentinel_total <- n_sentinel_last_chemo + n_sentinel_last_rad + n_sentinel_last_sct

if (n_sentinel_total > 0) {
  message(glue("  VIZP-01: Filtering {n_sentinel_total} sentinel dates (year 1900) from last treatment dates"))
  last_chemo_dates <- last_chemo_dates %>%
    filter(is.na(LAST_CHEMO_DATE) | year(LAST_CHEMO_DATE) != 1900L)
  last_rad_dates <- last_rad_dates %>%
    filter(is.na(LAST_RADIATION_DATE) | year(LAST_RADIATION_DATE) != 1900L)
  last_sct_dates <- last_sct_dates %>%
    filter(is.na(LAST_SCT_DATE) | year(LAST_SCT_DATE) != 1900L)
}

# ---- 2b. Payer at LAST treatment (mode in ±30 day window around last date) ----

compute_payer_at_last <- function(last_dates, payer_col_name) {
  if (nrow(last_dates) == 0) {
    return(tibble(ID = character(0), !!payer_col_name := character(0)))
  }
  compute_payer_mode_in_window(last_dates, payer_col_name = payer_col_name)
}

payer_at_last_chemo <- last_chemo_dates %>%
  compute_payer_at_last("PAYER_AT_LAST_CHEMO")
payer_at_last_rad <- last_rad_dates %>%
  compute_payer_at_last("PAYER_AT_LAST_RADIATION")
payer_at_last_sct <- last_sct_dates %>%
  compute_payer_at_last("PAYER_AT_LAST_SCT")

message(glue("  Payer at last chemo: {sum(!is.na(payer_at_last_chemo$PAYER_AT_LAST_CHEMO))} matched"))
message(glue("  Payer at last radiation: {sum(!is.na(payer_at_last_rad$PAYER_AT_LAST_RADIATION))} matched"))
message(glue("  Payer at last SCT: {sum(!is.na(payer_at_last_sct$PAYER_AT_LAST_SCT))} matched"))

# ---- 2c. Post-treatment payer (most prevalent after ANY last treatment) ----

# For each patient, find the latest treatment date across all types
# Then find the mode payer from encounters AFTER that date

all_last_dates <- hl_cohort %>%
  select(ID) %>%
  left_join(last_chemo_dates, by = "ID") %>%
  left_join(last_rad_dates, by = "ID") %>%
  left_join(last_sct_dates, by = "ID") %>%
  rowwise() %>%
  mutate(
    LAST_ANY_TREATMENT_DATE = {
      dates <- c(LAST_CHEMO_DATE, LAST_RADIATION_DATE, LAST_SCT_DATE)
      dates <- dates[!is.na(dates)]
      if (length(dates) == 0) NA_Date_ else max(dates)
    }
  ) %>%
  ungroup() %>%
  select(ID, LAST_ANY_TREATMENT_DATE)

# Last encounter date per patient (reused in Slide 14)
last_encounter_per_patient <- encounters %>%
  filter(!is.na(ADMIT_DATE)) %>%
  group_by(ID) %>%
  summarise(LAST_ENCOUNTER_DATE = max(ADMIT_DATE, na.rm = TRUE), .groups = "drop")

# Helper: compute post-treatment payer (mode of payer after last treatment date)
# Patients with no encounters after last treatment date get N/A (no follow-up)
compute_post_tx_payer <- function(patient_dates, date_col, payer_col_name) {
  # Identify patients with no follow-up (no encounters after last treatment date)
  no_followup_ids <- patient_dates %>%
    filter(!is.na(!!sym(date_col))) %>%
    inner_join(last_encounter_per_patient, by = "ID") %>%
    filter(LAST_ENCOUNTER_DATE <= !!sym(date_col)) %>%
    pull(ID)

  result <- patient_dates %>%
    filter(!is.na(!!sym(date_col))) %>%
    filter(!ID %in% no_followup_ids) %>%
    inner_join(
      encounters %>%
        filter(!is.na(effective_payer) &
               nchar(trimws(effective_payer)) > 0 &
               !effective_payer %in% PAYER_MAPPING$sentinel_values),
      by = "ID"
    ) %>%
    filter(ADMIT_DATE > !!sym(date_col)) %>%
    group_by(ID, payer_category) %>%
    summarise(n = n(), .groups = "drop") %>%
    arrange(ID, desc(n), payer_category) %>%
    group_by(ID) %>%
    slice(1) %>%
    ungroup() %>%
    select(ID, !!payer_col_name := payer_category)

  message(glue("  {payer_col_name}: {nrow(result)} with follow-up, {length(no_followup_ids)} N/A (no follow-up)"))
  result
}

# Post-treatment payer: anytime after last treatment of ANY type
post_treatment_payer <- compute_post_tx_payer(
  all_last_dates, "LAST_ANY_TREATMENT_DATE", "POST_TREATMENT_PAYER"
)

# Post-treatment payer per treatment type
post_chemo_payer <- compute_post_tx_payer(
  last_chemo_dates %>% rename(LAST_DATE = LAST_CHEMO_DATE),
  "LAST_DATE", "POST_CHEMO_PAYER"
)
post_rad_payer <- compute_post_tx_payer(
  last_rad_dates %>% rename(LAST_DATE = LAST_RADIATION_DATE),
  "LAST_DATE", "POST_RAD_PAYER"
)
post_sct_payer <- compute_post_tx_payer(
  last_sct_dates %>% rename(LAST_DATE = LAST_SCT_DATE),
  "LAST_DATE", "POST_SCT_PAYER"
)

# ---- 2d. Enrollment coverage analysis ----

# Check if enrollment covers ±30 day window around a given date
# Returns TRUE if any enrollment span covers [date - 30, date + 30]
enrollment_primary <- pcornet$ENROLLMENT %>%
  inner_join(
    pcornet$DEMOGRAPHIC %>% select(ID, SOURCE),
    by = c("ID", "SOURCE")
  )

check_enr_covers_window <- function(patient_dates, date_col) {
  patient_dates %>%
    rename(anchor_date = !!date_col) %>%
    filter(!is.na(anchor_date)) %>%
    left_join(
      enrollment_primary %>% select(ID, ENR_START_DATE, ENR_END_DATE),
      by = "ID",
      relationship = "many-to-many"
    ) %>%
    mutate(
      window_start = anchor_date - days(WINDOW_DAYS),
      window_end = anchor_date + days(WINDOW_DAYS),
      enr_covers = ENR_START_DATE <= window_start & ENR_END_DATE >= window_end
    ) %>%
    group_by(ID) %>%
    summarise(enr_covers_window = any(enr_covers, na.rm = TRUE), .groups = "drop")
}

# ---- 2e. Join all additional data to cohort ----

cohort_full <- hl_cohort %>%
  left_join(last_chemo_dates, by = "ID") %>%
  left_join(last_rad_dates, by = "ID") %>%
  left_join(last_sct_dates, by = "ID") %>%
  left_join(payer_at_last_chemo, by = "ID") %>%
  left_join(payer_at_last_rad, by = "ID") %>%
  left_join(payer_at_last_sct, by = "ID") %>%
  left_join(all_last_dates, by = "ID") %>%
  left_join(post_treatment_payer, by = "ID") %>%
  left_join(post_chemo_payer, by = "ID") %>%
  left_join(post_rad_payer, by = "ID") %>%
  left_join(post_sct_payer, by = "ID")

# Filter 1900 sentinel dates from FIRST treatment dates shown in PPTX (per VIZP-01)
# Note: first_hl_dx_date is already nullified in 14_build_cohort.R and should NOT be touched here
cohort_full <- cohort_full %>%
  mutate(
    across(
      c(FIRST_CHEMO_DATE, FIRST_RADIATION_DATE, FIRST_SCT_DATE),
      ~ if_else(year(.x) == 1900L, as.Date(NA), .x)
    )
  )

# Rename payer categories to match Python PPTX display names
# POST_TREATMENT_PAYER excluded: NA must stay NA for the N/A row (no follow-up)
cohort_full <- cohort_full %>%
  mutate(
    across(
      c(PAYER_CATEGORY_PRIMARY, PAYER_CATEGORY_AT_FIRST_DX,
        PAYER_AT_CHEMO, PAYER_AT_RADIATION, PAYER_AT_SCT,
        PAYER_AT_LAST_CHEMO, PAYER_AT_LAST_RADIATION, PAYER_AT_LAST_SCT),
      rename_payer
    ),
    across(
      c(POST_TREATMENT_PAYER, POST_CHEMO_PAYER, POST_RAD_PAYER, POST_SCT_PAYER),
      ~ case_when(
          .x %in% c("Other", "Other govt") ~ "Missing",
          TRUE ~ .x  # preserves NA as NA, preserves all other values
        )
    )
  )

message(glue("\n  Full cohort assembled: {nrow(cohort_full)} patients, {ncol(cohort_full)} columns"))

# Snapshot: PPTX master source data (per SNAP-04)
save_output_data(cohort_full, "pptx_cohort_full_data")

# ==============================================================================
# SECTION 3: TABLE BUILDING FUNCTIONS
# ==============================================================================

# Build a payer distribution table for one or more columns
build_payer_table <- function(data, col_specs, total_n = NULL) {
  # col_specs: named list of list(col = "column_name", label = "Display Label")
  if (is.null(total_n)) total_n <- nrow(data)

  rows <- lapply(PAYER_ORDER, function(cat) {
    row <- list(`Payer Category` = cat)
    for (spec in col_specs) {
      vals <- data[[spec$col]]
      n <- sum(vals == cat, na.rm = TRUE)
      row[[spec$label]] <- format_count_pct(n, total_n)
    }
    as_tibble(row)
  })
  tbl <- bind_rows(rows)

  # Add totals row
  total_row <- list(`Payer Category` = "Total")
  for (spec in col_specs) {
    n_total <- sum(!is.na(data[[spec$col]]))
    total_row[[spec$label]] <- format_count_pct(n_total, total_n)
  }
  bind_rows(tbl, as_tibble(total_row))
}

# Build a payer table with an extra "N/A" row for patients without data
build_payer_table_with_na <- function(data, col_specs, na_label = "N/A (No Treatment)", total_n = NULL) {
  if (is.null(total_n)) total_n <- nrow(data)

  tbl <- build_payer_table(data, col_specs, total_n)

  # Add N/A row
  na_row <- list(`Payer Category` = na_label)
  for (spec in col_specs) {
    n_na <- sum(is.na(data[[spec$col]]))
    na_row[[spec$label]] <- format_count_pct(n_na, total_n)
  }
  # Replace Total row to include N/A patients (so percentages sum to 100%)
  n_rows <- nrow(tbl)
  total_row <- list(`Payer Category` = "Total")
  for (spec in col_specs) {
    total_row[[spec$label]] <- format_count_pct(total_n, total_n)
  }

  bind_rows(tbl[1:(n_rows - 1), ], as_tibble(na_row), as_tibble(total_row))
}

# Build enrollment coverage split table
build_enr_coverage_table <- function(data, payer_col, enr_covers_col, total_n = NULL) {
  if (is.null(total_n)) total_n <- nrow(data)

  covers_data <- data %>% filter(!!sym(enr_covers_col) == TRUE)
  gap_data <- data %>% filter(!!sym(enr_covers_col) == FALSE)
  n_covers <- nrow(covers_data)
  n_gap <- nrow(gap_data)

  rows <- lapply(PAYER_ORDER, function(cat) {
    n_c <- sum(covers_data[[payer_col]] == cat, na.rm = TRUE)
    n_g <- sum(gap_data[[payer_col]] == cat, na.rm = TRUE)
    tibble(
      `Payer Category` = cat,
      `ENR Covers Window` = format_count_pct(n_c, n_covers),
      `ENR Does Not Cover` = format_count_pct(n_g, n_gap)
    )
  })
  tbl <- bind_rows(rows)

  # Add No Payer Assigned row for patients without the payer assignment
  n_na_c <- sum(is.na(covers_data[[payer_col]]))
  n_na_g <- sum(is.na(gap_data[[payer_col]]))
  tbl <- bind_rows(tbl, tibble(
    `Payer Category` = "No Payer Assigned",
    `ENR Covers Window` = format_count_pct(n_na_c, n_covers),
    `ENR Does Not Cover` = format_count_pct(n_na_g, n_gap)
  ))

  # Add totals row
  bind_rows(tbl, tibble(
    `Payer Category` = "Total",
    `ENR Covers Window` = format_count_pct(n_covers, n_covers),
    `ENR Does Not Cover` = format_count_pct(n_gap, n_gap)
  ))
}

# Build treatment enrollment coverage table (first + last, covers + gap)
build_treatment_enr_table <- function(data, first_payer_col, last_payer_col,
                                       first_enr_col, last_enr_col,
                                       first_label, last_label) {
  fc <- data %>% filter(!!sym(first_enr_col) == TRUE)
  fg <- data %>% filter(!!sym(first_enr_col) == FALSE)
  lc <- data %>% filter(!!sym(last_enr_col) == TRUE)
  lg <- data %>% filter(!!sym(last_enr_col) == FALSE)

  rows <- lapply(PAYER_ORDER, function(cat) {
    tibble(
      `Payer Category` = cat,
      !!paste0("First ", first_label, " ENR Covers") :=
        format_count_pct(sum(fc[[first_payer_col]] == cat, na.rm = TRUE), nrow(fc)),
      !!paste0("First ", first_label, " ENR Gap") :=
        format_count_pct(sum(fg[[first_payer_col]] == cat, na.rm = TRUE), nrow(fg)),
      !!paste0("Last ", last_label, " ENR Covers") :=
        format_count_pct(sum(lc[[last_payer_col]] == cat, na.rm = TRUE), nrow(lc)),
      !!paste0("Last ", last_label, " ENR Gap") :=
        format_count_pct(sum(lg[[last_payer_col]] == cat, na.rm = TRUE), nrow(lg))
    )
  })
  tbl <- bind_rows(rows)

  # No Payer Assigned row
  tbl <- bind_rows(tbl, tibble(
    `Payer Category` = "No Payer Assigned",
    !!paste0("First ", first_label, " ENR Covers") :=
      format_count_pct(sum(is.na(fc[[first_payer_col]])), nrow(fc)),
    !!paste0("First ", first_label, " ENR Gap") :=
      format_count_pct(sum(is.na(fg[[first_payer_col]])), nrow(fg)),
    !!paste0("Last ", last_label, " ENR Covers") :=
      format_count_pct(sum(is.na(lc[[last_payer_col]])), nrow(lc)),
    !!paste0("Last ", last_label, " ENR Gap") :=
      format_count_pct(sum(is.na(lg[[last_payer_col]])), nrow(lg))
  ))

  # Totals row
  bind_rows(tbl, tibble(
    `Payer Category` = "Total",
    !!paste0("First ", first_label, " ENR Covers") :=
      format_count_pct(nrow(fc), nrow(fc)),
    !!paste0("First ", first_label, " ENR Gap") :=
      format_count_pct(nrow(fg), nrow(fg)),
    !!paste0("Last ", last_label, " ENR Covers") :=
      format_count_pct(nrow(lc), nrow(lc)),
    !!paste0("Last ", last_label, " ENR Gap") :=
      format_count_pct(nrow(lg), nrow(lg))
  ))
}

# ==============================================================================
# SECTION 4: FLEXTABLE STYLING
# ==============================================================================

# style_table() provided by R/utils_pptx.R

# ==============================================================================
# SECTION 5: BUILD PPTX SLIDES
# ==============================================================================

message("\n--- Building PowerPoint slides ---")

pptx <- read_pptx()

# Set 16:9 widescreen slide dimensions (matching Python pipeline: 10" x 5.625")
tryCatch({
  pres_node <- pptx$doc_obj$get()
  sld_sz <- xml2::xml_find_first(pres_node, "//p:sldSz", xml2::xml_ns(pres_node))
  xml2::xml_attr(sld_sz, "cx") <- "9144000"   # 10 inches * 914400 EMU/inch
  xml2::xml_attr(sld_sz, "cy") <- "5143500"    # 5.625 inches * 914400 EMU/inch
  message("  Set slide dimensions to 16:9 widescreen (10\" x 5.625\")")
}, error = function(e) {
  message(glue("  Note: Using default slide dimensions ({e$message})"))
})

# Helper to add a slide with title, subtitle, and table
add_table_slide <- function(pptx, title, subtitle, tbl_data) {
  # Find Total row index (if any) for bold styling
  total_row_idx <- which(tbl_data[[1]] == "Total")
  ft <- flextable(tbl_data) %>% style_table(total_row = total_row_idx)

  # Set column widths (Payer Category = 2.2", rest evenly distributed)
  n_cols <- ncol(tbl_data)
  if (n_cols > 1) {
    payer_width <- 2.2
    data_col_width <- (9.0 - payer_width) / (n_cols - 1)
    ft <- ft %>%
      width(j = 1, width = payer_width) %>%
      width(j = 2:n_cols, width = data_col_width)
  }

  pptx <- pptx %>%
    add_slide(layout = "Blank") %>%
    ph_with(
      value = fpar(ftext(title, prop = fp_text(font.size = 26, bold = TRUE,
                                                font.family = "Calibri",
                                                color = UF_BLUE))),
      location = ph_location(left = 0.5, top = 0.2, width = 9, height = 0.6)
    ) %>%
    ph_with(
      value = fpar(ftext(subtitle, prop = fp_text(font.size = 14, italic = TRUE,
                                                   font.family = "Calibri",
                                                   color = DARK_TEXT))),
      location = ph_location(left = 0.5, top = 0.85, width = 9, height = 0.4)
    ) %>%
    ph_with(
      value = ft,
      location = ph_location(left = 0.5, top = 1.4, width = 9, height = 5.0)
    )

  pptx
}

# Helper to add a slide with title, subtitle, and a centered PNG figure
add_image_slide <- function(pptx, title, subtitle, img_path,
                             img_width = 8.5, img_height = 5.0) {
  if (!file.exists(img_path)) {
    message(glue("  SKIPPED: {title} -- {img_path} not found. Run 16_encounter_analysis.R first."))
    return(pptx)
  }
  pptx %>%
    add_slide(layout = "Blank") %>%
    ph_with(
      value = fpar(ftext(title, prop = fp_text(font.size = 26, bold = TRUE,
                                               font.family = "Calibri", color = UF_BLUE))),
      location = ph_location(left = 0.5, top = 0.2, width = 9, height = 0.6)
    ) %>%
    ph_with(
      value = fpar(ftext(subtitle, prop = fp_text(font.size = 14, italic = TRUE,
                                                  font.family = "Calibri", color = DARK_TEXT))),
      location = ph_location(left = 0.5, top = 0.85, width = 9, height = 0.4)
    ) %>%
    ph_with(
      value = external_img(img_path, width = img_width, height = img_height),
      location = ph_location(left = (10 - img_width) / 2, top = 1.4,
                              width = img_width, height = img_height)
    )
}

# Footnote text formatting (10pt italic gray at bottom of slide)
footnote_prop <- fp_text(font.size = 10, italic = TRUE, font.family = "Calibri", color = "#666666")
footnote_location <- ph_location(left = 0.5, top = 6.9, width = 9, height = 0.5)

# Helper to add a footnote to the current (last-added) slide
add_footnote <- function(pptx, text) {
  pptx %>%
    ph_with(
      value = fpar(ftext(text, prop = footnote_prop)),
      location = footnote_location
    )
}

# ---- Counts for title slide ----
N_TOTAL <- nrow(cohort_full)
N_CHEMO <- sum(cohort_full$HAD_CHEMO == 1)
N_RAD <- sum(cohort_full$HAD_RADIATION == 1)
N_SCT <- sum(cohort_full$HAD_SCT == 1)

# ---- Slide 1: Definitions & Glossary ----
message("  Slide 1: Definitions & Glossary")

pptx <- pptx %>%
  add_slide(layout = "Blank") %>%
  ph_with(
    value = fpar(ftext("Definitions and Glossary",
                       prop = fp_text(font.size = 28, bold = TRUE,
                                      font.family = "Calibri", color = UF_BLUE))),
    location = ph_location(left = 0.5, top = 0.2, width = 9, height = 0.6)
  ) %>%
  ph_with(
    value = block_list(
      fpar(ftext("Primary Insurance: ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("Most prevalent payer across all encounters for the patient.", prop = fp_text(font.size = 14, font.family = "Calibri"))),
      fpar(ftext("First Diagnosis: ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("Payer mode within \u00b130 days of first HL diagnosis date.", prop = fp_text(font.size = 14, font.family = "Calibri"))),
      fpar(ftext("First Chemo / Radiation / SCT: ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("Payer mode within \u00b130 day window of first treatment date for that treatment type.", prop = fp_text(font.size = 14, font.family = "Calibri"))),
      fpar(ftext("Last Chemo / Radiation / SCT: ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("Payer mode within \u00b130 day window of last treatment date for that treatment type.", prop = fp_text(font.size = 14, font.family = "Calibri"))),
      fpar(ftext("Post-Treatment Insurance: ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("Mode of payer from encounters after last treatment date of that type.", prop = fp_text(font.size = 14, font.family = "Calibri"))),
      fpar(ftext(" ", prop = fp_text(font.size = 10))),
      fpar(ftext("Missing: ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("Consolidation of Other and Other govt payer categories.", prop = fp_text(font.size = 14, font.family = "Calibri"))),
      fpar(ftext("No Payer Assigned: ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("No encounter with valid payer data found in the \u00b130 day window around the relevant date.", prop = fp_text(font.size = 14, font.family = "Calibri"))),
      fpar(ftext("N/A (No Follow-up): ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("No encounters after the patient's last treatment date in the dataset.", prop = fp_text(font.size = 14, font.family = "Calibri"))),
      fpar(ftext("N/A (No Treatment): ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("Patient had no recorded treatment of that type.", prop = fp_text(font.size = 14, font.family = "Calibri"))),
      fpar(ftext(" ", prop = fp_text(font.size = 10))),
      fpar(ftext("ENR Covers Window: ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("Patient has enrollment records spanning the full \u00b130 day window around the event date.", prop = fp_text(font.size = 14, font.family = "Calibri"))),
      fpar(ftext("ENR Does Not Cover: ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("Patient's enrollment records do not fully cover the \u00b130 day window.", prop = fp_text(font.size = 14, font.family = "Calibri")))
    ),
    location = ph_location(left = 0.5, top = 1.1, width = 9, height = 5.5)
  ) %>%
  ph_with(
    value = fpar(ftext(glue("Hodgkin Lymphoma Cohort -- N = {format(N_TOTAL, big.mark = ',')} | Chemo: {format(N_CHEMO, big.mark = ',')} | Radiation: {format(N_RAD, big.mark = ',')} | SCT: {format(N_SCT, big.mark = ',')}"),
                       prop = fp_text(font.size = 11, italic = TRUE,
                                      font.family = "Calibri", color = "#666666"))),
    location = ph_location(left = 0.5, top = 6.9, width = 9, height = 0.5)
  )

# ---- Slide 2: Insurance Coverage Overview ----
message("  Slide 2: Insurance Coverage Overview")
tbl2 <- build_payer_table(cohort_full, list(
  list(col = "PAYER_CATEGORY_PRIMARY", label = "Primary Insurance"),
  list(col = "PAYER_CATEGORY_AT_FIRST_DX", label = "First Diagnosis")
))
pptx <- add_table_slide(pptx,
  "Insurance Coverage Overview",
  glue("All enrolled patients \u2014 N = {format(N_TOTAL, big.mark = ',')}"),
  tbl2) %>%
  add_footnote("Primary Insurance = most prevalent payer across all encounters. First Diagnosis = payer mode within \u00b130 days of first HL diagnosis date.")

# ---- Slide 3: Post-Treatment Insurance (all patients) ----
message("  Slide 3: Post-Treatment Insurance")
tbl3_base <- build_payer_table(cohort_full, list(
  list(col = "POST_TREATMENT_PAYER", label = "Post-Treatment Insurance")
), total_n = N_TOTAL)
# Split N/A into two sub-rows: no treatment evidence vs no encounters after treatment
n_no_treatment <- sum(is.na(cohort_full$LAST_ANY_TREATMENT_DATE))
n_no_post_enc  <- sum(!is.na(cohort_full$LAST_ANY_TREATMENT_DATE) & is.na(cohort_full$POST_TREATMENT_PAYER))
message(glue("    N/A breakdown: {n_no_treatment} no treatment evidence, {n_no_post_enc} no encounters after last treatment"))
na_row1 <- tibble(`Payer Category` = "N/A: No evidence of treatment",
                   `Post-Treatment Insurance` = format_count_pct(n_no_treatment, N_TOTAL))
na_row2 <- tibble(`Payer Category` = "N/A: No encounters after last treatment",
                   `Post-Treatment Insurance` = format_count_pct(n_no_post_enc, N_TOTAL))
total_row3 <- tibble(`Payer Category` = "Total",
                      `Post-Treatment Insurance` = format_count_pct(N_TOTAL, N_TOTAL))
tbl3 <- bind_rows(tbl3_base[1:(nrow(tbl3_base) - 1), ], na_row1, na_row2, total_row3)
pptx <- add_table_slide(pptx,
  "Post-Treatment Insurance \u2014 All Patients",
  glue("Most prevalent payer after last treatment \u2014 N = {format(N_TOTAL, big.mark = ',')}"),
  tbl3) %>%
  add_footnote("Post-Treatment Insurance = mode of payer from encounters after last treatment of any type. N/A rows: 'No evidence of treatment' = no chemo/radiation/SCT found; 'No encounters after last treatment' = treatment found but no subsequent encounters.")

# ---- Slide 4: Chemotherapy Insurance ----
message("  Slide 4: Chemotherapy Insurance")
chemo_patients <- cohort_full %>% filter(HAD_CHEMO == 1)
tbl4 <- build_payer_table(chemo_patients, list(
  list(col = "PAYER_CATEGORY_PRIMARY", label = "Primary Insurance"),
  list(col = "PAYER_AT_CHEMO", label = "First Chemo"),
  list(col = "PAYER_AT_LAST_CHEMO", label = "Last Chemo")
))
pptx <- add_table_slide(pptx,
  "Chemotherapy Insurance",
  glue("Insurance at primary, first, and last chemotherapy \u2014 N = {format(N_CHEMO, big.mark = ',')}"),
  tbl4) %>%
  add_footnote("Primary Insurance = most prevalent payer across all encounters. First/Last Chemo = payer mode within \u00b130 days of first/last chemotherapy date.")

# ---- Slide 5: Chemotherapy Post-Treatment Insurance ----
message("  Slide 5: Chemo Post-Treatment Insurance")
tbl5 <- build_payer_table_with_na(chemo_patients, list(
  list(col = "POST_CHEMO_PAYER", label = "Post-Treatment Insurance")
), na_label = "N/A (No Follow-up)")
pptx <- add_table_slide(pptx,
  "Chemotherapy Post-Treatment Insurance",
  glue("Most prevalent payer after last chemotherapy \u2014 N = {format(N_CHEMO, big.mark = ',')}"),
  tbl5) %>%
  add_footnote("Post-Treatment Insurance = mode of payer from encounters after last chemotherapy date. N/A (No Follow-up) = no encounters after last chemotherapy date.")

# ---- Slide 6: Radiation Insurance ----
message("  Slide 6: Radiation Insurance")
rad_patients <- cohort_full %>% filter(HAD_RADIATION == 1)
tbl6 <- build_payer_table(rad_patients, list(
  list(col = "PAYER_CATEGORY_PRIMARY", label = "Primary Insurance"),
  list(col = "PAYER_AT_RADIATION", label = "First Radiation"),
  list(col = "PAYER_AT_LAST_RADIATION", label = "Last Radiation")
))
pptx <- add_table_slide(pptx,
  "Radiation Insurance",
  glue("Insurance at primary, first, and last radiation \u2014 N = {format(N_RAD, big.mark = ',')}"),
  tbl6) %>%
  add_footnote("Primary Insurance = most prevalent payer across all encounters. First/Last Radiation = payer mode within \u00b130 days of first/last radiation date.")

# ---- Slide 7: Radiation Post-Treatment Insurance ----
message("  Slide 7: Radiation Post-Treatment Insurance")
tbl7 <- build_payer_table_with_na(rad_patients, list(
  list(col = "POST_RAD_PAYER", label = "Post-Treatment Insurance")
), na_label = "N/A (No Follow-up)")
pptx <- add_table_slide(pptx,
  "Radiation Post-Treatment Insurance",
  glue("Most prevalent payer after last radiation \u2014 N = {format(N_RAD, big.mark = ',')}"),
  tbl7) %>%
  add_footnote("Post-Treatment Insurance = mode of payer from encounters after last radiation date. N/A (No Follow-up) = no encounters after last radiation date.")

# ---- Slide 8: SCT Insurance ----
message("  Slide 8: SCT Insurance")
sct_patients <- cohort_full %>% filter(HAD_SCT == 1)
tbl8 <- build_payer_table(sct_patients, list(
  list(col = "PAYER_CATEGORY_PRIMARY", label = "Primary Insurance"),
  list(col = "PAYER_AT_SCT", label = "First SCT"),
  list(col = "PAYER_AT_LAST_SCT", label = "Last SCT")
))
pptx <- add_table_slide(pptx,
  "Stem Cell Transplant Insurance",
  glue("Insurance at primary, first, and last SCT \u2014 N = {format(N_SCT, big.mark = ',')}"),
  tbl8) %>%
  add_footnote("Primary Insurance = most prevalent payer across all encounters. First/Last SCT = payer mode within \u00b130 days of first/last stem cell transplant date.")

# ---- Slide 9: SCT Post-Treatment Insurance ----
message("  Slide 9: SCT Post-Treatment Insurance")
tbl9 <- build_payer_table_with_na(sct_patients, list(
  list(col = "POST_SCT_PAYER", label = "Post-Treatment Insurance")
), na_label = "N/A (No Follow-up)")
pptx <- add_table_slide(pptx,
  "SCT Post-Treatment Insurance",
  glue("Most prevalent payer after last SCT \u2014 N = {format(N_SCT, big.mark = ',')}"),
  tbl9) %>%
  add_footnote("Post-Treatment Insurance = mode of payer from encounters after last SCT date. N/A (No Follow-up) = no encounters after last SCT date.")

# ---- Slide 10: Diagnosis - Enrollment Coverage ----
message("  Slide 10: Diagnosis Enrollment Coverage")
dx_enr <- check_enr_covers_window(
  cohort_full %>% select(ID, first_hl_dx_date) %>% filter(!is.na(first_hl_dx_date)),
  "first_hl_dx_date"
)
cohort_dx_enr <- cohort_full %>%
  left_join(dx_enr %>% rename(dx_enr_covers = enr_covers_window), by = "ID") %>%
  mutate(dx_enr_covers = coalesce(dx_enr_covers, FALSE))

tbl10 <- build_enr_coverage_table(cohort_dx_enr, "PAYER_CATEGORY_AT_FIRST_DX", "dx_enr_covers")
pptx <- add_table_slide(pptx,
  "Diagnosis \u2014 Insurance by Enrollment Coverage",
  glue("Payer at first HL diagnosis: patients with vs without enrollment covering \u00b130 day window"),
  tbl10) %>%
  add_footnote("ENR Covers Window = enrollment records span the full \u00b130 day window around first HL diagnosis. ENR Does Not Cover = enrollment gap in that window.")

# ---- Slide 11: Chemo - Enrollment Coverage ----
message("  Slide 11: Chemo Enrollment Coverage")
chemo_first_enr <- check_enr_covers_window(
  chemo_patients %>% select(ID, FIRST_CHEMO_DATE) %>% filter(!is.na(FIRST_CHEMO_DATE)),
  "FIRST_CHEMO_DATE"
) %>% rename(chemo_first_enr = enr_covers_window)

chemo_last_enr <- check_enr_covers_window(
  chemo_patients %>%
    select(ID, LAST_CHEMO_DATE) %>%
    filter(!is.na(LAST_CHEMO_DATE)),
  "LAST_CHEMO_DATE"
) %>% rename(chemo_last_enr = enr_covers_window)

chemo_enr <- chemo_patients %>%
  left_join(chemo_first_enr, by = "ID") %>%
  left_join(chemo_last_enr, by = "ID") %>%
  mutate(
    chemo_first_enr = coalesce(chemo_first_enr, FALSE),
    chemo_last_enr = coalesce(chemo_last_enr, FALSE)
  )

tbl11 <- build_treatment_enr_table(
  chemo_enr, "PAYER_AT_CHEMO", "PAYER_AT_LAST_CHEMO",
  "chemo_first_enr", "chemo_last_enr", "Chemo", "Chemo"
)
pptx <- add_table_slide(pptx,
  "Chemotherapy \u2014 Insurance by Enrollment Coverage",
  glue("Payer at first/last chemo: patients with vs without enrollment covering \u00b130 day window"),
  tbl11) %>%
  add_footnote("ENR Covers = enrollment records span the full \u00b130 day window around first/last chemotherapy. ENR Gap = enrollment gap in that window.")

# ---- Slide 12: Radiation - Enrollment Coverage ----
message("  Slide 12: Radiation Enrollment Coverage")
rad_first_enr <- check_enr_covers_window(
  rad_patients %>% select(ID, FIRST_RADIATION_DATE) %>% filter(!is.na(FIRST_RADIATION_DATE)),
  "FIRST_RADIATION_DATE"
) %>% rename(rad_first_enr = enr_covers_window)

rad_last_enr <- check_enr_covers_window(
  rad_patients %>%
    select(ID, LAST_RADIATION_DATE) %>%
    filter(!is.na(LAST_RADIATION_DATE)),
  "LAST_RADIATION_DATE"
) %>% rename(rad_last_enr = enr_covers_window)

rad_enr <- rad_patients %>%
  left_join(rad_first_enr, by = "ID") %>%
  left_join(rad_last_enr, by = "ID") %>%
  mutate(
    rad_first_enr = coalesce(rad_first_enr, FALSE),
    rad_last_enr = coalesce(rad_last_enr, FALSE)
  )

tbl12 <- build_treatment_enr_table(
  rad_enr, "PAYER_AT_RADIATION", "PAYER_AT_LAST_RADIATION",
  "rad_first_enr", "rad_last_enr", "Radiation", "Radiation"
)
pptx <- add_table_slide(pptx,
  "Radiation \u2014 Insurance by Enrollment Coverage",
  glue("Payer at first/last radiation: patients with vs without enrollment covering \u00b130 day window"),
  tbl12) %>%
  add_footnote("ENR Covers = enrollment records span the full \u00b130 day window around first/last radiation. ENR Gap = enrollment gap in that window.")

# ---- Slide 13: SCT - Enrollment Coverage ----
message("  Slide 13: SCT Enrollment Coverage")
sct_first_enr <- check_enr_covers_window(
  sct_patients %>% select(ID, FIRST_SCT_DATE) %>% filter(!is.na(FIRST_SCT_DATE)),
  "FIRST_SCT_DATE"
) %>% rename(sct_first_enr = enr_covers_window)

sct_last_enr <- check_enr_covers_window(
  sct_patients %>%
    select(ID, LAST_SCT_DATE) %>%
    filter(!is.na(LAST_SCT_DATE)),
  "LAST_SCT_DATE"
) %>% rename(sct_last_enr = enr_covers_window)

sct_enr <- sct_patients %>%
  left_join(sct_first_enr, by = "ID") %>%
  left_join(sct_last_enr, by = "ID") %>%
  mutate(
    sct_first_enr = coalesce(sct_first_enr, FALSE),
    sct_last_enr = coalesce(sct_last_enr, FALSE)
  )

tbl13 <- build_treatment_enr_table(
  sct_enr, "PAYER_AT_SCT", "PAYER_AT_LAST_SCT",
  "sct_first_enr", "sct_last_enr", "SCT", "SCT"
)
pptx <- add_table_slide(pptx,
  "SCT \u2014 Insurance by Enrollment Coverage",
  glue("Payer at first/last SCT: patients with vs without enrollment covering \u00b130 day window"),
  tbl13) %>%
  add_footnote("ENR Covers = enrollment records span the full \u00b130 day window around first/last SCT. ENR Gap = enrollment gap in that window.")

# ---- Slide 14: Last Treatment = Last Encounter ----
message("  Slide 14: Last Treatment = Last Encounter")

# Reuse last_encounter_per_patient computed in section 2c
last_tx_vs_enc <- cohort_full %>%
  filter(!is.na(LAST_ANY_TREATMENT_DATE)) %>%
  inner_join(last_encounter_per_patient, by = "ID") %>%
  mutate(
    days_last_enc_after_last_tx = as.numeric(LAST_ENCOUNTER_DATE - LAST_ANY_TREATMENT_DATE),
    last_tx_is_last_enc = LAST_ENCOUNTER_DATE == LAST_ANY_TREATMENT_DATE
  )

# Also compute per treatment type (LAST_*_DATE columns already in cohort_full)
last_tx_vs_enc <- last_tx_vs_enc %>%
  mutate(
    chemo_is_last_enc = if_else(
      !is.na(LAST_CHEMO_DATE),
      LAST_ENCOUNTER_DATE == LAST_CHEMO_DATE,
      NA
    ),
    rad_is_last_enc = if_else(
      !is.na(LAST_RADIATION_DATE),
      LAST_ENCOUNTER_DATE == LAST_RADIATION_DATE,
      NA
    ),
    sct_is_last_enc = if_else(
      !is.na(LAST_SCT_DATE),
      LAST_ENCOUNTER_DATE == LAST_SCT_DATE,
      NA
    )
  )

# Build summary table
n_any_tx <- nrow(last_tx_vs_enc)
n_any_match <- sum(last_tx_vs_enc$last_tx_is_last_enc, na.rm = TRUE)

n_chemo_tx <- sum(!is.na(last_tx_vs_enc$LAST_CHEMO_DATE))
n_chemo_match <- sum(last_tx_vs_enc$chemo_is_last_enc, na.rm = TRUE)

n_rad_tx <- sum(!is.na(last_tx_vs_enc$LAST_RADIATION_DATE))
n_rad_match <- sum(last_tx_vs_enc$rad_is_last_enc, na.rm = TRUE)

n_sct_tx <- sum(!is.na(last_tx_vs_enc$LAST_SCT_DATE))
n_sct_match <- sum(last_tx_vs_enc$sct_is_last_enc, na.rm = TRUE)

tbl14 <- tibble(
  `Treatment Type` = c("Any Treatment", "Chemotherapy", "Radiation", "Stem Cell Transplant"),
  `N With Treatment` = c(
    format(n_any_tx, big.mark = ","),
    format(n_chemo_tx, big.mark = ","),
    format(n_rad_tx, big.mark = ","),
    format(n_sct_tx, big.mark = ",")
  ),
  `Last Tx = Last Encounter` = c(
    format_count_pct(n_any_match, n_any_tx),
    format_count_pct(n_chemo_match, n_chemo_tx),
    format_count_pct(n_rad_match, n_rad_tx),
    format_count_pct(n_sct_match, n_sct_tx)
  ),
  `Had Follow-up Encounters` = c(
    format_count_pct(n_any_tx - n_any_match, n_any_tx),
    format_count_pct(n_chemo_tx - n_chemo_match, n_chemo_tx),
    format_count_pct(n_rad_tx - n_rad_match, n_rad_tx),
    format_count_pct(n_sct_tx - n_sct_match, n_sct_tx)
  )
)

# Snapshot: table backing data (per SNAP-04)
save_output_data(tbl14, "last_tx_equals_last_encounter_data")

pptx <- add_table_slide(pptx,
  "Last Treatment = Last Encounter",
  glue("Patients whose last treatment date equals their last encounter date (no follow-up)"),
  tbl14) %>%
  add_footnote("Last Tx = Last Encounter: patient's last treatment date is the same as their last encounter date in the dataset.")

# ---- Slide 15: Missing Post-Treatment Payer - Encounter Breakdown ----
message("  Slide 15: Missing Post-Treatment Encounter Breakdown")

# Patients with Missing or NA post-treatment payer: how many encounters after last treatment?
unknown_post <- cohort_full %>%
  filter(!is.na(LAST_ANY_TREATMENT_DATE)) %>%
  filter(is.na(POST_TREATMENT_PAYER) | POST_TREATMENT_PAYER == "Missing")

# Count encounters after last treatment for each patient
post_tx_encounter_counts <- unknown_post %>%
  select(ID, LAST_ANY_TREATMENT_DATE) %>%
  left_join(
    encounters %>% select(ID, ADMIT_DATE),
    by = "ID",
    relationship = "many-to-many"
  ) %>%
  filter(ADMIT_DATE > LAST_ANY_TREATMENT_DATE) %>%
  group_by(ID) %>%
  summarise(n_post_encounters = n(), .groups = "drop")

# Join back and fill 0 for patients with no post-treatment encounters
unknown_post_counts <- unknown_post %>%
  select(ID) %>%
  left_join(post_tx_encounter_counts, by = "ID") %>%
  mutate(n_post_encounters = coalesce(n_post_encounters, 0L))

# Bin into categories
n_unknown <- nrow(unknown_post_counts)
tbl15 <- unknown_post_counts %>%
  mutate(
    bin = case_when(
      n_post_encounters == 0 ~ "0",
      n_post_encounters <= 5 ~ "1-5",
      n_post_encounters <= 10 ~ "6-10",
      n_post_encounters <= 20 ~ "11-20",
      TRUE ~ "21+"
    ),
    bin = factor(bin, levels = c("0", "1-5", "6-10", "11-20", "21+"))
  ) %>%
  count(bin, name = "n") %>%
  mutate(`N Patients` = format_count_pct(n, n_unknown)) %>%
  select(`Number of Encounters` = bin, `N Patients`) %>%
  bind_rows(tibble(`Number of Encounters` = "Total", `N Patients` = format_count_pct(n_unknown, n_unknown)))

# Snapshot: table backing data (per SNAP-04)
save_output_data(tbl15, "missing_post_tx_payer_breakdown_data")

pptx <- add_table_slide(pptx,
  "Missing Post-Treatment Payer \u2014 Encounter Breakdown",
  glue("Patients with Missing post-treatment payer: how many encounters exist after last treatment?"),
  tbl15) %>%
  add_footnote("Shows how many post-treatment encounters exist for patients whose post-treatment payer is Missing or unassigned.")

# ---- Slide 16: Insurance After Last Treatment & Dataset Retention ----
message("  Slide 16: Post-Last-Treatment Insurance & Retention")

# Compute payer at last treatment of any type (mode in ±30 day window)
payer_at_last_any <- all_last_dates %>%
  filter(!is.na(LAST_ANY_TREATMENT_DATE)) %>%
  compute_payer_mode_in_window(payer_col_name = "PAYER_AT_LAST_TX")

# Determine which treated patients have ANY encounter after their last treatment
treated_ids <- cohort_full %>%
  filter(!is.na(LAST_ANY_TREATMENT_DATE)) %>%
  select(ID, LAST_ANY_TREATMENT_DATE)

patients_with_post_enc <- treated_ids %>%
  inner_join(
    encounters %>% select(ID, ADMIT_DATE),
    by = "ID",
    relationship = "many-to-many"
  ) %>%
  filter(ADMIT_DATE > LAST_ANY_TREATMENT_DATE) %>%
  distinct(ID) %>%
  mutate(has_post_encounter = TRUE)

# Build retention dataset
tx_retention <- treated_ids %>%
  left_join(patients_with_post_enc, by = "ID") %>%
  mutate(has_post_encounter = coalesce(has_post_encounter, FALSE)) %>%
  left_join(post_treatment_payer, by = "ID") %>%
  left_join(payer_at_last_any, by = "ID") %>%
  mutate(
    # POST_TREATMENT_PAYER: preserve NA so the "No Payer Assigned" row logic works
    POST_TREATMENT_PAYER = case_when(
      POST_TREATMENT_PAYER %in% c("Other", "Other govt") ~ "Missing",
      TRUE ~ POST_TREATMENT_PAYER
    ),
    PAYER_AT_LAST_TX = rename_payer(PAYER_AT_LAST_TX)
  )

n_treated <- nrow(tx_retention)
n_still_in <- sum(tx_retention$has_post_encounter)
n_missing <- n_treated - n_still_in

still_data <- tx_retention %>% filter(has_post_encounter)
missing_data <- tx_retention %>% filter(!has_post_encounter)

message(glue("  Treated: {n_treated} | Still in dataset: {n_still_in} | Missing: {n_missing}"))

# Build payer breakdown: still in dataset (post-tx payer) vs missing (last known payer)
still_col <- glue("Still in Dataset (N={format(n_still_in, big.mark=',')})")
missing_col <- glue("No Longer in Dataset (N={format(n_missing, big.mark=',')})")

rows16 <- lapply(PAYER_ORDER, function(cat) {
  n_s <- sum(still_data$POST_TREATMENT_PAYER == cat, na.rm = TRUE)
  n_m <- sum(missing_data$PAYER_AT_LAST_TX == cat, na.rm = TRUE)
  tibble(
    `Payer Category` = cat,
    !!still_col := if (n_still_in > 0) format_count_pct(n_s, n_still_in) else "0 (0.0%)",
    !!missing_col := if (n_missing > 0) format_count_pct(n_m, n_missing) else "0 (0.0%)"
  )
})
tbl16 <- bind_rows(rows16)

# Add No Payer Assigned row (no payer matched in window)
n_na_s <- sum(is.na(still_data$POST_TREATMENT_PAYER))
n_na_m <- sum(is.na(missing_data$PAYER_AT_LAST_TX))
tbl16 <- bind_rows(tbl16, tibble(
  `Payer Category` = "No Payer Assigned",
  !!still_col := if (n_still_in > 0) format_count_pct(n_na_s, n_still_in) else "0 (0.0%)",
  !!missing_col := if (n_missing > 0) format_count_pct(n_na_m, n_missing) else "0 (0.0%)"
))

# Add totals row for treated patients
tbl16 <- bind_rows(tbl16, tibble(
  `Payer Category` = "Total",
  !!still_col := if (n_still_in > 0) format_count_pct(n_still_in, n_still_in) else "0 (0.0%)",
  !!missing_col := if (n_missing > 0) format_count_pct(n_missing, n_missing) else "0 (0.0%)"
))

pct_still <- if (n_treated > 0) round(100 * n_still_in / n_treated, 1) else 0
pct_missing <- if (n_treated > 0) round(100 * n_missing / n_treated, 1) else 0

# Snapshot: table backing data (per SNAP-04)
save_output_data(tbl16, "insurance_after_last_tx_retention_data")

pptx <- add_table_slide(pptx,
  "Insurance After Last Treatment \u2014 Dataset Retention",
  glue("{format(n_treated, big.mark=',')} treated patients: {format(n_still_in, big.mark=',')} ({pct_still}%) still in dataset, {format(n_missing, big.mark=',')} ({pct_missing}%) no longer in dataset"),
  tbl16) %>%
  add_footnote("Still in Dataset = patient has encounters after last treatment. No Longer in Dataset = last treatment date was the last encounter date. Payer shown is post-treatment (still) or at last treatment (no longer).")

# ==============================================================================
# SECTION 5b: ENCOUNTER ANALYSIS SLIDES (from 16_encounter_analysis.R figures)
# ==============================================================================

# Regenerate encounter analysis PNGs to ensure they reflect current cohort data.
# Without this, stale PNGs from a previous run get embedded in the pptx.
message("\n--- Regenerating encounter analysis figures ---")
source("R/75_encounter_analysis.R")

message("\n--- Encounter Analysis Slides ---")

# ---- Slide 17: Encounter histogram by payor ----
message("  Slide 17: Encounters per Person by Payer Category")
enc_hist_path <- "output/figures/encounters_per_person_by_payor.png"
pptx <- add_image_slide(pptx,
  "Encounters per Person by Payer Category",
  glue("Distribution of total encounter counts by primary payer -- N = {format(N_TOTAL, big.mark=',')}"),
  enc_hist_path
)
if (file.exists(enc_hist_path)) {
  pptx <- add_footnote(pptx, "Primary Insurance = most prevalent payer across all encounters. Payer categories consolidated to 6 + Missing.")
}

# ---- Slide 18 (new): Summary Statistics -- Encounters per Person by Payer ----
message("  Slide 18: Summary Statistics -- Encounters per Payer")

summary_stats <- cohort_full %>%
  filter(!is.na(N_ENCOUNTERS)) %>%
  mutate(PAYER_DISPLAY = rename_payer(PAYER_CATEGORY_PRIMARY)) %>%
  filter(!is.na(PAYER_DISPLAY)) %>%
  group_by(PAYER_DISPLAY) %>%
  summarise(
    N = n(),
    Mean = round(mean(N_ENCOUNTERS, na.rm = TRUE), 1),
    Median = round(median(N_ENCOUNTERS, na.rm = TRUE), 1),
    Min = min(N_ENCOUNTERS, na.rm = TRUE),
    Q1 = round(quantile(N_ENCOUNTERS, 0.25, na.rm = TRUE), 1),
    Q3 = round(quantile(N_ENCOUNTERS, 0.75, na.rm = TRUE), 1),
    Max = max(N_ENCOUNTERS, na.rm = TRUE),
    `500+` = sum(N_ENCOUNTERS > 500, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  rename(`Payer Category` = PAYER_DISPLAY)

# Add totals row
summary_totals <- cohort_full %>%
  filter(!is.na(N_ENCOUNTERS), !is.na(PAYER_CATEGORY_PRIMARY)) %>%
  summarise(
    `Payer Category` = "Total",
    N = n(),
    Mean = round(mean(N_ENCOUNTERS, na.rm = TRUE), 1),
    Median = round(median(N_ENCOUNTERS, na.rm = TRUE), 1),
    Min = min(N_ENCOUNTERS, na.rm = TRUE),
    Q1 = round(quantile(N_ENCOUNTERS, 0.25, na.rm = TRUE), 1),
    Q3 = round(quantile(N_ENCOUNTERS, 0.75, na.rm = TRUE), 1),
    Max = max(N_ENCOUNTERS, na.rm = TRUE),
    `500+` = sum(N_ENCOUNTERS > 500, na.rm = TRUE)
  )

summary_stats <- bind_rows(summary_stats, summary_totals)

# Format N with commas for display
summary_stats <- summary_stats %>%
  mutate(N = format(N, big.mark = ","))

# Snapshot: table backing data (per SNAP-04)
save_output_data(summary_stats, "encounter_summary_stats_by_payer_data")

pptx <- add_table_slide(pptx,
  "Summary Statistics: Encounters per Person by Payer Category",
  glue("Distribution of total encounter counts by primary insurance category -- N = {format(N_TOTAL, big.mark = ',')}"),
  summary_stats) %>%
  add_footnote("Primary Insurance = most prevalent payer across all encounters. 500+ = patients with more than 500 total encounters.")

# Count patients with missing DX_YEAR (includes nullified 1900 sentinels) for footnote
# VIZP-01: DX_YEAR filtering already handled correctly via is.na() since DX_YEAR derives from
# the already-nullified first_hl_dx_date (nullified in 14_build_cohort.R lines 176-183)
n_missing_dx_year <- sum(is.na(cohort_full$DX_YEAR))
masked_footnote <- if (n_missing_dx_year > 0) {
  glue("{n_missing_dx_year} patients with missing diagnosis date excluded from this analysis.")
} else {
  ""
}

# ---- Slide 19: Post-treatment encounters by DX year ----
message("  Slide 19: Post-Treatment Encounters by DX Year")
post_tx_dx_path <- "output/figures/post_tx_encounters_by_dx_year.png"
pptx <- add_image_slide(pptx,
  "Mean Post-Treatment Encounters by Year of Diagnosis",
  "Non-acute care encounters per person after last treatment, stratified by HL diagnosis year",
  post_tx_dx_path
)
if (file.exists(post_tx_dx_path) && nchar(masked_footnote) > 0) {
  pptx <- add_footnote(pptx, masked_footnote)
}

# ---- Slide 20: Total encounters by DX year ----
message("  Slide 20: Total Encounters by DX Year")
total_enc_dx_path <- "output/figures/total_encounters_by_dx_year.png"
pptx <- add_image_slide(pptx,
  "Mean Total Encounters by Year of Diagnosis",
  "All encounters per person across the full observation window, stratified by HL diagnosis year",
  total_enc_dx_path
)
if (file.exists(total_enc_dx_path) && nchar(masked_footnote) > 0) {
  pptx <- add_footnote(pptx, masked_footnote)
}

# ---- Slide 21: Post-treatment encounters by age group ----
message("  Slide 21: Post-Treatment Encounters by Age Group")
age_group_path <- "output/figures/post_tx_by_age_group.png"
pptx <- add_image_slide(pptx,
  "Post-Treatment Encounter Presence by Age Group at Diagnosis",
  "Among treated patients: proportion with any encounter after last treatment, by age group (0-17, 18-39, 40-64, 65+)",
  age_group_path
)
if (file.exists(age_group_path)) {
  pptx <- add_footnote(pptx, "Age group determined at date of first HL diagnosis. Post-treatment = any encounter after last treatment of any type.")
}

# ==============================================================================
# SECTION 5c: UNIQUE DATES SLIDES (distinct encounter dates per patient)
# ==============================================================================

message("\n--- Unique Dates Slides ---")

# Compute unique encounter dates per patient from the encounters table
unique_dates_total <- encounters %>%
  filter(!is.na(ADMIT_DATE)) %>%
  group_by(ID) %>%
  summarise(N_UNIQUE_DATES = n_distinct(ADMIT_DATE), .groups = "drop")

# Compute unique post-treatment dates (AV+TH post-diagnosis, mirrors Level 1)
first_dx_map <- cohort_full %>%
  select(ID, first_hl_dx_date) %>%
  filter(!is.na(first_hl_dx_date))

unique_dates_post_tx <- pcornet$ENCOUNTER %>%
  filter(ENC_TYPE %in% c("AV", "TH")) %>%
  inner_join(first_dx_map, by = "ID") %>%
  filter(!is.na(ADMIT_DATE), ADMIT_DATE > first_hl_dx_date) %>%
  group_by(ID) %>%
  summarise(N_UNIQUE_DATES_POST_TX = n_distinct(ADMIT_DATE), .groups = "drop")

cohort_ud <- cohort_full %>%
  left_join(unique_dates_total, by = "ID") %>%
  left_join(unique_dates_post_tx, by = "ID") %>%
  mutate(
    N_UNIQUE_DATES = coalesce(N_UNIQUE_DATES, 0L),
    N_UNIQUE_DATES_POST_TX = coalesce(N_UNIQUE_DATES_POST_TX, 0L)
  )

# ---- Slide 22: Unique dates histogram by payor ----
message("  Slide 22: Unique Dates per Person by Payer Category")
ud_hist_path <- "output/figures/unique_dates_per_person_by_payor.png"
pptx <- add_image_slide(pptx,
  "Unique Encounter Dates per Person by Payer Category",
  glue("Distribution of distinct encounter dates by primary payer -- N = {format(N_TOTAL, big.mark=',')}"),
  ud_hist_path
)
if (file.exists(ud_hist_path)) {
  pptx <- add_footnote(pptx, "Unique dates = distinct ADMIT_DATEs per patient. Multiple encounters on the same day count as one date.")
}

# ---- Slide 23: Summary Statistics -- Unique Dates per Person by Payer ----
message("  Slide 23: Summary Statistics -- Unique Dates per Payer")

ud_summary_stats <- cohort_ud %>%
  filter(!is.na(N_UNIQUE_DATES)) %>%
  mutate(PAYER_DISPLAY = rename_payer(PAYER_CATEGORY_PRIMARY)) %>%
  filter(!is.na(PAYER_DISPLAY)) %>%
  group_by(PAYER_DISPLAY) %>%
  summarise(
    N = n(),
    Mean = round(mean(N_UNIQUE_DATES, na.rm = TRUE), 1),
    Median = round(median(N_UNIQUE_DATES, na.rm = TRUE), 1),
    Min = min(N_UNIQUE_DATES, na.rm = TRUE),
    Q1 = round(quantile(N_UNIQUE_DATES, 0.25, na.rm = TRUE), 1),
    Q3 = round(quantile(N_UNIQUE_DATES, 0.75, na.rm = TRUE), 1),
    Max = max(N_UNIQUE_DATES, na.rm = TRUE),
    `300+` = sum(N_UNIQUE_DATES > 300, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  rename(`Payer Category` = PAYER_DISPLAY)

ud_summary_totals <- cohort_ud %>%
  filter(!is.na(N_UNIQUE_DATES), !is.na(PAYER_CATEGORY_PRIMARY)) %>%
  summarise(
    `Payer Category` = "Total",
    N = n(),
    Mean = round(mean(N_UNIQUE_DATES, na.rm = TRUE), 1),
    Median = round(median(N_UNIQUE_DATES, na.rm = TRUE), 1),
    Min = min(N_UNIQUE_DATES, na.rm = TRUE),
    Q1 = round(quantile(N_UNIQUE_DATES, 0.25, na.rm = TRUE), 1),
    Q3 = round(quantile(N_UNIQUE_DATES, 0.75, na.rm = TRUE), 1),
    Max = max(N_UNIQUE_DATES, na.rm = TRUE),
    `300+` = sum(N_UNIQUE_DATES > 300, na.rm = TRUE)
  )

ud_summary_stats <- bind_rows(ud_summary_stats, ud_summary_totals) %>%
  mutate(N = format(N, big.mark = ","))

# Snapshot: table backing data (per SNAP-04)
save_output_data(ud_summary_stats, "unique_dates_summary_stats_by_payer_data")

pptx <- add_table_slide(pptx,
  "Summary Statistics: Unique Dates per Person by Payer Category",
  glue("Distribution of distinct encounter dates by primary insurance category -- N = {format(N_TOTAL, big.mark = ',')}"),
  ud_summary_stats) %>%
  add_footnote("Unique dates = distinct ADMIT_DATEs per patient. 300+ = patients with more than 300 unique encounter dates.")

# ---- Slide 24: Post-treatment unique dates by DX year ----
message("  Slide 24: Post-Treatment Unique Dates by DX Year")
post_tx_ud_path <- "output/figures/post_tx_unique_dates_by_dx_year.png"
pptx <- add_image_slide(pptx,
  "Mean Post-Treatment Unique Dates by Year of Diagnosis",
  "Distinct encounter dates per person after last treatment, stratified by HL diagnosis year",
  post_tx_ud_path
)
if (file.exists(post_tx_ud_path) && nchar(masked_footnote) > 0) {
  pptx <- add_footnote(pptx, masked_footnote)
}

# ---- Slide 25: Total unique dates by DX year ----
message("  Slide 25: Total Unique Dates by DX Year")
total_ud_dx_path <- "output/figures/total_unique_dates_by_dx_year.png"
pptx <- add_image_slide(pptx,
  "Mean Total Unique Dates by Year of Diagnosis",
  "Distinct encounter dates per person across the full observation window, stratified by HL diagnosis year",
  total_ud_dx_path
)
if (file.exists(total_ud_dx_path) && nchar(masked_footnote) > 0) {
  pptx <- add_footnote(pptx, masked_footnote)
}

# ---- Slide 26: Unique Encounter Dates per Person by Payer (Post-Last Treatment) ----
message("  Slide 26: Post-Last-Treatment Unique Encounter Dates by Payer")

# Per D-05: This uses LAST_ANY_TREATMENT_DATE as anchor (post-LAST-treatment),
# NOT first_hl_dx_date (post-diagnosis) which Section 6 of 16_encounter_analysis.R uses.

# Step 1: Compute per-patient unique post-last-treatment encounter dates
post_last_tx_dates <- encounters %>%
  inner_join(all_last_dates, by = "ID") %>%
  filter(
    !is.na(LAST_ANY_TREATMENT_DATE),       # Only patients with treatment (per D-04)
    !is.na(ADMIT_DATE),
    ADMIT_DATE > LAST_ANY_TREATMENT_DATE    # Post-last-treatment encounters only (1900 sentinels filtered at source in 02_harmonize_payer.R)
  ) %>%
  group_by(ID) %>%
  summarise(N_UNIQUE_DATES_POST_LAST_TX = n_distinct(ADMIT_DATE), .groups = "drop")

# Step 2: Join to treated patients with payer, fill 0 for those with no post-tx encounters
# Only include patients who HAVE treatment (per D-04)
treated_cohort_ids <- cohort_full %>%
  filter(!is.na(LAST_ANY_TREATMENT_DATE)) %>%
  select(ID, PAYER_CATEGORY_PRIMARY)

post_last_tx_summary <- treated_cohort_ids %>%
  left_join(post_last_tx_dates, by = "ID") %>%
  mutate(
    N_UNIQUE_DATES_POST_LAST_TX = coalesce(N_UNIQUE_DATES_POST_LAST_TX, 0L),
    PAYER_DISPLAY = rename_payer(PAYER_CATEGORY_PRIMARY)
  ) %>%
  filter(!is.na(PAYER_DISPLAY)) %>%
  group_by(PAYER_DISPLAY) %>%
  summarise(
    N = n(),
    Mean = round(mean(N_UNIQUE_DATES_POST_LAST_TX, na.rm = TRUE), 1),
    Median = median(N_UNIQUE_DATES_POST_LAST_TX, na.rm = TRUE),
    Min = min(N_UNIQUE_DATES_POST_LAST_TX, na.rm = TRUE),
    Max = max(N_UNIQUE_DATES_POST_LAST_TX, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  rename(`Payer Category` = PAYER_DISPLAY)

# Add totals row
post_last_tx_totals <- treated_cohort_ids %>%
  left_join(post_last_tx_dates, by = "ID") %>%
  mutate(N_UNIQUE_DATES_POST_LAST_TX = coalesce(N_UNIQUE_DATES_POST_LAST_TX, 0L)) %>%
  summarise(
    `Payer Category` = "Total",
    N = n(),
    Mean = round(mean(N_UNIQUE_DATES_POST_LAST_TX, na.rm = TRUE), 1),
    Median = median(N_UNIQUE_DATES_POST_LAST_TX, na.rm = TRUE),
    Min = min(N_UNIQUE_DATES_POST_LAST_TX, na.rm = TRUE),
    Max = max(N_UNIQUE_DATES_POST_LAST_TX, na.rm = TRUE)
  )

post_last_tx_summary <- bind_rows(post_last_tx_summary, post_last_tx_totals) %>%
  mutate(N = format(N, big.mark = ","))

n_treated_for_slide <- nrow(treated_cohort_ids)

# Snapshot: table backing data (per SNAP-04)
save_output_data(post_last_tx_summary, "post_last_tx_unique_dates_summary_data")

pptx <- add_table_slide(pptx,
  "Unique Encounter Dates per Person (Post-Last Treatment)",
  glue("Distinct encounter dates after last treatment (any type) -- Treated patients only, N = {format(n_treated_for_slide, big.mark = ',')}"),
  post_last_tx_summary) %>%
  add_footnote("Post-Last Treatment = encounters after max(LAST_CHEMO_DATE, LAST_RADIATION_DATE, LAST_SCT_DATE). Patients with no treatment excluded. Unique dates = distinct ADMIT_DATEs per patient.")

# ---- Slide 27: Stacked Encounter Histogram (Pre/Post-Treatment) ----
message("  Slide 27: Stacked Encounters Pre/Post-Treatment by Payer")
stacked_hist_path <- "output/figures/encounters_stacked_pre_post_by_payor.png"
pptx <- add_image_slide(pptx,
  "Encounters per Person by Payor (Pre/Post-Treatment Split)",
  glue("Total encounters split by pre/post-treatment period -- Treated patients only"),
  stacked_hist_path,
  img_width = 9, img_height = 5.5
)
if (file.exists(stacked_hist_path)) {
  pptx <- add_footnote(pptx, "Post-treatment = encounters after max(last chemo, last radiation, last SCT date). Patients with no treatment excluded. Blue = post-treatment, orange = pre-treatment.")
}

# ---- Slide 28: Summary Statistics -- Pre/Post Encounters by Payer ----
message("  Slide 28: Summary Statistics -- Pre/Post Encounters by Payer")

# Compute pre/post encounter stats per payer for treated patients
# One row per payer (no doubling) with Pre/Post columns side by side
stacked_long <- cohort_full %>%
  filter(!is.na(LAST_ANY_TREATMENT_DATE)) %>%
  select(ID, PAYER_CATEGORY_PRIMARY, LAST_ANY_TREATMENT_DATE) %>%
  inner_join(
    encounters %>% filter(!is.na(ADMIT_DATE)) %>%
      mutate(ADMIT_DATE_CLEAN = ADMIT_DATE) %>%
      select(ID, ADMIT_DATE_CLEAN),
    by = "ID",
    relationship = "many-to-many"
  ) %>%
  mutate(
    PERIOD = if_else(ADMIT_DATE_CLEAN > LAST_ANY_TREATMENT_DATE, "Post-treatment", "Pre-treatment"),
    PAYER_DISPLAY = rename_payer(PAYER_CATEGORY_PRIMARY)
  ) %>%
  filter(!is.na(PAYER_DISPLAY)) %>%
  count(ID, PERIOD, PAYER_DISPLAY, name = "n_enc") %>%
  tidyr::complete(tidyr::nesting(ID, PAYER_DISPLAY), PERIOD, fill = list(n_enc = 0)) %>%
  group_by(PAYER_DISPLAY, PERIOD) %>%
  summarise(
    N = n_distinct(ID),
    Mean = round(mean(n_enc, na.rm = TRUE), 1),
    Median = round(median(n_enc, na.rm = TRUE), 1),
    .groups = "drop"
  )

stacked_stats <- stacked_long %>%
  tidyr::pivot_wider(
    id_cols = PAYER_DISPLAY,
    names_from = PERIOD,
    values_from = c(N, Mean, Median),
    names_glue = "{PERIOD} {.value}"
  ) %>%
  rename(`Payer Category` = PAYER_DISPLAY) %>%
  select(`Payer Category`,
         `Pre-treatment N`, `Pre-treatment Mean`, `Pre-treatment Median`,
         `Post-treatment N`, `Post-treatment Mean`, `Post-treatment Median`) %>%
  arrange(`Payer Category`) %>%
  mutate(
    `Pre-treatment N` = format(`Pre-treatment N`, big.mark = ","),
    `Post-treatment N` = format(`Post-treatment N`, big.mark = ",")
  )

# Snapshot: table backing data (per SNAP-04)
save_output_data(stacked_stats, "stacked_encounter_stats_by_payer_period_data")

pptx <- add_table_slide(pptx,
  "Summary Statistics: Pre/Post-Treatment Encounters by Payer",
  glue("Encounter count statistics by primary payer and treatment period -- Treated patients only"),
  stacked_stats) %>%
  add_footnote("Post-treatment = encounters after last treatment date. Pre-treatment = encounters on or before last treatment date.")

# ---- Slide 29: Stacked Unique Dates Histogram (Pre/Post-Treatment) ----
message("  Slide 29: Stacked Unique Dates Pre/Post-Treatment by Payer")
stacked_ud_hist_path <- "output/figures/unique_dates_stacked_pre_post_by_payor.png"
pptx <- add_image_slide(pptx,
  "Unique Encounter Dates per Person by Payor (Pre/Post-Treatment Split)",
  glue("Distinct encounter dates split by pre/post-treatment period -- Treated patients only"),
  stacked_ud_hist_path,
  img_width = 9, img_height = 5.5
)
if (file.exists(stacked_ud_hist_path)) {
  pptx <- add_footnote(pptx, "Post-treatment = encounters after max(last chemo, last radiation, last SCT date). Patients with no treatment excluded. Unique dates = distinct ADMIT_DATEs. Blue = post-treatment, orange = pre-treatment.")
}

# ---- Slide 30: Summary Statistics -- Pre/Post Unique Dates by Payer ----
message("  Slide 30: Summary Statistics -- Pre/Post Unique Dates by Payer")

stacked_ud_long <- cohort_full %>%
  filter(!is.na(LAST_ANY_TREATMENT_DATE)) %>%
  select(ID, PAYER_CATEGORY_PRIMARY, LAST_ANY_TREATMENT_DATE) %>%
  inner_join(
    encounters %>% filter(!is.na(ADMIT_DATE)) %>%
      mutate(ADMIT_DATE_CLEAN = ADMIT_DATE) %>%
      select(ID, ADMIT_DATE_CLEAN),
    by = "ID",
    relationship = "many-to-many"
  ) %>%
  mutate(
    PERIOD = if_else(ADMIT_DATE_CLEAN > LAST_ANY_TREATMENT_DATE, "Post-treatment", "Pre-treatment"),
    PAYER_DISPLAY = rename_payer(PAYER_CATEGORY_PRIMARY)
  ) %>%
  filter(!is.na(PAYER_DISPLAY)) %>%
  group_by(ID, PERIOD, PAYER_DISPLAY) %>%
  summarise(n_unique_dates = n_distinct(ADMIT_DATE_CLEAN), .groups = "drop") %>%
  tidyr::complete(tidyr::nesting(ID, PAYER_DISPLAY), PERIOD, fill = list(n_unique_dates = 0)) %>%
  group_by(PAYER_DISPLAY, PERIOD) %>%
  summarise(
    N = n_distinct(ID),
    Mean = round(mean(n_unique_dates, na.rm = TRUE), 1),
    Median = round(median(n_unique_dates, na.rm = TRUE), 1),
    .groups = "drop"
  )

stacked_ud_stats <- stacked_ud_long %>%
  tidyr::pivot_wider(
    id_cols = PAYER_DISPLAY,
    names_from = PERIOD,
    values_from = c(N, Mean, Median),
    names_glue = "{PERIOD} {.value}"
  ) %>%
  rename(`Payer Category` = PAYER_DISPLAY) %>%
  select(`Payer Category`,
         `Pre-treatment N`, `Pre-treatment Mean`, `Pre-treatment Median`,
         `Post-treatment N`, `Post-treatment Mean`, `Post-treatment Median`) %>%
  arrange(`Payer Category`) %>%
  mutate(
    `Pre-treatment N` = format(`Pre-treatment N`, big.mark = ","),
    `Post-treatment N` = format(`Post-treatment N`, big.mark = ",")
  )

# Snapshot: table backing data (per SNAP-04)
save_output_data(stacked_ud_stats, "stacked_unique_dates_stats_by_payer_period_data")

pptx <- add_table_slide(pptx,
  "Summary Statistics: Pre/Post-Treatment Unique Dates by Payer",
  glue("Unique encounter date statistics by primary payer and treatment period -- Treated patients only"),
  stacked_ud_stats) %>%
  add_footnote("Post-treatment = unique dates after last treatment date. Pre-treatment = unique dates on or before last treatment date. Unique dates = distinct ADMIT_DATEs per patient (multiple encounters on same day count as one).")

# ==============================================================================
# SECTION 5d: TREATED PATIENTS ONLY -- UNIQUE DATES ANALYSIS
# ==============================================================================
# Versions of slides 17-30 filtered to treated patients only, using unique
# encounter dates throughout. By-year charts use median instead of mean.
# De-duplicated: raw-encounter slides and unique-date slides collapse to the
# same output when everything uses unique dates, giving 8 slides (31-38).

message("\n--- Treated Patients Only: Unique Dates Slides ---")

# Count treated patients for subtitles
N_TREATED <- sum(!is.na(cohort_full$LAST_ANY_TREATMENT_DATE))

# Filter cohort_ud (from Section 5c) to treated patients only
treated_ids_for_ud <- cohort_full %>%
  filter(!is.na(LAST_ANY_TREATMENT_DATE)) %>%
  pull(ID)

cohort_ud_treated <- cohort_ud %>%
  filter(ID %in% treated_ids_for_ud)

# Compute post-last-treatment unique dates (all encounter types)
post_last_tx_ud_treated <- encounters %>%
  inner_join(
    cohort_full %>%
      filter(!is.na(LAST_ANY_TREATMENT_DATE)) %>%
      select(ID, LAST_ANY_TREATMENT_DATE),
    by = "ID"
  ) %>%
  filter(!is.na(ADMIT_DATE), ADMIT_DATE > LAST_ANY_TREATMENT_DATE) %>%
  group_by(ID) %>%
  summarise(N_UNIQUE_DATES_POST_LAST_TX = n_distinct(ADMIT_DATE), .groups = "drop")

cohort_ud_treated <- cohort_ud_treated %>%
  left_join(post_last_tx_ud_treated, by = "ID") %>%
  mutate(N_UNIQUE_DATES_POST_LAST_TX = coalesce(N_UNIQUE_DATES_POST_LAST_TX, 0L))

# ---- Slide 31: Unique Dates Histogram by Payer (Treated Only) ----
# Versions of slides 17 & 22 — treated patients only, unique encounter dates
message("  Slide 31: Unique Dates per Person by Payer (Treated Only)")
ud_hist_treated_path <- "output/figures/unique_dates_per_person_by_payor_treated.png"
pptx <- add_image_slide(pptx,
  "Unique Encounter Dates per Person by Payer (Treated Only)",
  glue("Distribution of distinct encounter dates by primary payer -- Treated patients only, N = {format(N_TREATED, big.mark=',')}"),
  ud_hist_treated_path
)
if (file.exists(ud_hist_treated_path)) {
  pptx <- add_footnote(pptx, "Treated Only = patients with chemo, radiation, or SCT records. Unique dates = distinct ADMIT_DATEs per patient.")
}

# ---- Slide 32: Summary Statistics — Unique Dates by Payer (Treated Only) ----
# Versions of slides 18 & 23 — treated patients only, unique encounter dates
message("  Slide 32: Summary Statistics -- Unique Dates by Payer (Treated Only)")

ud_summary_treated <- cohort_ud_treated %>%
  filter(!is.na(N_UNIQUE_DATES)) %>%
  mutate(PAYER_DISPLAY = rename_payer(PAYER_CATEGORY_PRIMARY)) %>%
  filter(!is.na(PAYER_DISPLAY)) %>%
  group_by(PAYER_DISPLAY) %>%
  summarise(
    N = n(),
    Mean = round(mean(N_UNIQUE_DATES, na.rm = TRUE), 1),
    Median = round(median(N_UNIQUE_DATES, na.rm = TRUE), 1),
    Min = min(N_UNIQUE_DATES, na.rm = TRUE),
    Q1 = round(quantile(N_UNIQUE_DATES, 0.25, na.rm = TRUE), 1),
    Q3 = round(quantile(N_UNIQUE_DATES, 0.75, na.rm = TRUE), 1),
    Max = max(N_UNIQUE_DATES, na.rm = TRUE),
    `300+` = sum(N_UNIQUE_DATES > 300, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  rename(`Payer Category` = PAYER_DISPLAY)

ud_summary_treated_totals <- cohort_ud_treated %>%
  filter(!is.na(N_UNIQUE_DATES), !is.na(PAYER_CATEGORY_PRIMARY)) %>%
  summarise(
    `Payer Category` = "Total",
    N = n(),
    Mean = round(mean(N_UNIQUE_DATES, na.rm = TRUE), 1),
    Median = round(median(N_UNIQUE_DATES, na.rm = TRUE), 1),
    Min = min(N_UNIQUE_DATES, na.rm = TRUE),
    Q1 = round(quantile(N_UNIQUE_DATES, 0.25, na.rm = TRUE), 1),
    Q3 = round(quantile(N_UNIQUE_DATES, 0.75, na.rm = TRUE), 1),
    Max = max(N_UNIQUE_DATES, na.rm = TRUE),
    `300+` = sum(N_UNIQUE_DATES > 300, na.rm = TRUE)
  )

ud_summary_treated <- bind_rows(ud_summary_treated, ud_summary_treated_totals) %>%
  mutate(N = format(N, big.mark = ","))

save_output_data(ud_summary_treated, "unique_dates_summary_stats_by_payer_treated_data")

pptx <- add_table_slide(pptx,
  "Summary Statistics: Unique Dates per Person by Payer (Treated Only)",
  glue("Distribution of distinct encounter dates by primary insurance -- Treated patients only, N = {format(N_TREATED, big.mark = ',')}"),
  ud_summary_treated) %>%
  add_footnote("Treated Only = patients with chemo, radiation, or SCT records. Unique dates = distinct ADMIT_DATEs per patient. 300+ = patients with more than 300 unique encounter dates.")

# Count treated patients with missing DX_YEAR for footnotes
n_missing_dx_year_treated <- sum(is.na(cohort_ud_treated$DX_YEAR))
masked_footnote_treated <- if (n_missing_dx_year_treated > 0) {
  glue("{n_missing_dx_year_treated} treated patients with missing diagnosis date excluded from this analysis.")
} else {
  ""
}

# ---- Slide 33: Median Post-Treatment Unique Dates by DX Year (Treated Only) ----
# Versions of slides 19 & 24 — treated only, unique dates, median
message("  Slide 33: Median Post-Treatment Unique Dates by DX Year (Treated Only)")
post_tx_ud_treated_path <- "output/figures/post_tx_unique_dates_by_dx_year_treated_median.png"
pptx <- add_image_slide(pptx,
  "Median Post-Treatment Unique Dates by Year of Diagnosis (Treated Only)",
  "Distinct encounter dates per person after last treatment, stratified by HL diagnosis year (treated patients only)",
  post_tx_ud_treated_path
)
if (file.exists(post_tx_ud_treated_path) && nchar(masked_footnote_treated) > 0) {
  pptx <- add_footnote(pptx, masked_footnote_treated)
}

# ---- Slide 34: Median Total Unique Dates by DX Year (Treated Only) ----
# Versions of slides 20 & 25 — treated only, unique dates, median
message("  Slide 34: Median Total Unique Dates by DX Year (Treated Only)")
total_ud_treated_path <- "output/figures/total_unique_dates_by_dx_year_treated_median.png"
pptx <- add_image_slide(pptx,
  "Median Total Unique Dates by Year of Diagnosis (Treated Only)",
  "Distinct encounter dates per person across the full observation window, stratified by HL diagnosis year (treated patients only)",
  total_ud_treated_path
)
if (file.exists(total_ud_treated_path) && nchar(masked_footnote_treated) > 0) {
  pptx <- add_footnote(pptx, masked_footnote_treated)
}

# ---- Slide 35: Post-Treatment Encounter Presence by Age Group (Treated Only) ----
# Version of slide 21 — already treated only; binary presence unchanged by unique dates
message("  Slide 35: Post-Treatment Encounter Presence by Age Group (Treated Only)")
pptx <- add_image_slide(pptx,
  "Post-Treatment Encounter Presence by Age Group (Treated Only)",
  "Among treated patients: proportion with any encounter after last treatment, by age group (0-17, 18-39, 40-64, 65+)",
  age_group_path
)
if (file.exists(age_group_path)) {
  pptx <- add_footnote(pptx, "Same as Slide 21. Binary presence/absence is unchanged by unique dates filter. Age group at date of first HL diagnosis.")
}

# ---- Slide 36: Unique Dates Post-Last-Treatment by Payer (Treated Only) ----
# Version of slide 26 — already treated + unique dates
message("  Slide 36: Unique Dates Post-Last-Treatment by Payer (Treated Only)")

# Recompute for treated-only section (same logic as slide 26)
post_last_tx_summary_treated <- cohort_ud_treated %>%
  mutate(PAYER_DISPLAY = rename_payer(PAYER_CATEGORY_PRIMARY)) %>%
  filter(!is.na(PAYER_DISPLAY)) %>%
  group_by(PAYER_DISPLAY) %>%
  summarise(
    N = n(),
    Mean = round(mean(N_UNIQUE_DATES_POST_LAST_TX, na.rm = TRUE), 1),
    Median = median(N_UNIQUE_DATES_POST_LAST_TX, na.rm = TRUE),
    Min = min(N_UNIQUE_DATES_POST_LAST_TX, na.rm = TRUE),
    Max = max(N_UNIQUE_DATES_POST_LAST_TX, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  rename(`Payer Category` = PAYER_DISPLAY)

post_last_tx_totals_treated <- cohort_ud_treated %>%
  mutate(PAYER_DISPLAY = rename_payer(PAYER_CATEGORY_PRIMARY)) %>%
  filter(!is.na(PAYER_DISPLAY)) %>%
  summarise(
    `Payer Category` = "Total",
    N = n(),
    Mean = round(mean(N_UNIQUE_DATES_POST_LAST_TX, na.rm = TRUE), 1),
    Median = median(N_UNIQUE_DATES_POST_LAST_TX, na.rm = TRUE),
    Min = min(N_UNIQUE_DATES_POST_LAST_TX, na.rm = TRUE),
    Max = max(N_UNIQUE_DATES_POST_LAST_TX, na.rm = TRUE)
  )

post_last_tx_summary_treated <- bind_rows(post_last_tx_summary_treated, post_last_tx_totals_treated) %>%
  mutate(N = format(N, big.mark = ","))

save_output_data(post_last_tx_summary_treated, "post_last_tx_unique_dates_summary_treated_data")

pptx <- add_table_slide(pptx,
  "Unique Encounter Dates per Person — Post-Last Treatment (Treated Only)",
  glue("Distinct encounter dates after last treatment (any type) -- Treated patients only, N = {format(N_TREATED, big.mark = ',')}"),
  post_last_tx_summary_treated) %>%
  add_footnote("Post-Last Treatment = encounters after max(LAST_CHEMO_DATE, LAST_RADIATION_DATE, LAST_SCT_DATE). Unique dates = distinct ADMIT_DATEs per patient.")

# ---- Slide 37: Stacked Unique Dates Pre/Post-Treatment by Payer (Treated Only) ----
# Versions of slides 27 & 29 — already treated + unique dates in slide 29
message("  Slide 37: Stacked Unique Dates Pre/Post-Treatment by Payer (Treated Only)")
pptx <- add_image_slide(pptx,
  "Unique Encounter Dates per Person by Payor — Pre/Post-Treatment (Treated Only)",
  glue("Distinct encounter dates split by pre/post-treatment period -- Treated patients only"),
  stacked_ud_hist_path,
  img_width = 9, img_height = 5.5
)
if (file.exists(stacked_ud_hist_path)) {
  pptx <- add_footnote(pptx, "Same as Slide 29. Already filtered to treated patients with unique dates. Blue = post-treatment, orange = pre-treatment.")
}

# ---- Slide 38: Summary Stats Pre/Post Unique Dates by Payer (Treated Only) ----
# Versions of slides 28 & 30 — unique dates version is slide 30 (already treated)
message("  Slide 38: Summary Statistics -- Pre/Post Unique Dates by Payer (Treated Only)")

# Recompute for treated-only section (same logic as slide 30)
stacked_ud_long_treated <- cohort_full %>%
  filter(!is.na(LAST_ANY_TREATMENT_DATE)) %>%
  select(ID, PAYER_CATEGORY_PRIMARY, LAST_ANY_TREATMENT_DATE) %>%
  inner_join(
    encounters %>% filter(!is.na(ADMIT_DATE)) %>%
      select(ID, ADMIT_DATE),
    by = "ID",
    relationship = "many-to-many"
  ) %>%
  mutate(
    PERIOD = if_else(ADMIT_DATE > LAST_ANY_TREATMENT_DATE, "Post-treatment", "Pre-treatment"),
    PAYER_DISPLAY = rename_payer(PAYER_CATEGORY_PRIMARY)
  ) %>%
  filter(!is.na(PAYER_DISPLAY)) %>%
  group_by(ID, PERIOD, PAYER_DISPLAY) %>%
  summarise(n_unique_dates = n_distinct(ADMIT_DATE), .groups = "drop") %>%
  tidyr::complete(tidyr::nesting(ID, PAYER_DISPLAY), PERIOD, fill = list(n_unique_dates = 0)) %>%
  group_by(PAYER_DISPLAY, PERIOD) %>%
  summarise(
    N = n_distinct(ID),
    Mean = round(mean(n_unique_dates, na.rm = TRUE), 1),
    Median = round(median(n_unique_dates, na.rm = TRUE), 1),
    .groups = "drop"
  )

stacked_ud_stats_treated <- stacked_ud_long_treated %>%
  tidyr::pivot_wider(
    id_cols = PAYER_DISPLAY,
    names_from = PERIOD,
    values_from = c(N, Mean, Median),
    names_glue = "{PERIOD} {.value}"
  ) %>%
  rename(`Payer Category` = PAYER_DISPLAY) %>%
  select(`Payer Category`,
         `Pre-treatment N`, `Pre-treatment Mean`, `Pre-treatment Median`,
         `Post-treatment N`, `Post-treatment Mean`, `Post-treatment Median`) %>%
  arrange(`Payer Category`) %>%
  mutate(
    `Pre-treatment N` = format(`Pre-treatment N`, big.mark = ","),
    `Post-treatment N` = format(`Post-treatment N`, big.mark = ",")
  )

save_output_data(stacked_ud_stats_treated, "stacked_unique_dates_stats_treated_data")

pptx <- add_table_slide(pptx,
  "Summary Statistics: Pre/Post-Treatment Unique Dates by Payer (Treated Only)",
  glue("Unique encounter date statistics by primary payer and treatment period -- Treated patients only, N = {format(N_TREATED, big.mark = ',')}"),
  stacked_ud_stats_treated) %>%
  add_footnote("Post-treatment = unique dates after last treatment date. Pre-treatment = unique dates on or before last treatment date. Unique dates = distinct ADMIT_DATEs per patient.")

# ==============================================================================
# SECTION 7: PHASE 21/22 BAR CHART PNG GENERATION
# ==============================================================================

message("\n--- Generating Phase 21/22 bar chart PNGs ---")

# Ensure output/figures/ exists
dir.create("output/figures", showWarnings = FALSE, recursive = TRUE)

# ---- Chart 1: Primary payer missingness % by site (D-05) ----
p21_cross_site <- read_csv("output/tables/all_source_cross_site_summary.csv",
                            show_col_types = FALSE)

chart1_data <- p21_cross_site %>%
  filter(SOURCE != "ALL") %>%
  arrange(desc(pct_primary_missing)) %>%
  mutate(SOURCE = factor(SOURCE, levels = SOURCE))

p1 <- ggplot(chart1_data, aes(x = SOURCE, y = pct_primary_missing)) +
  geom_col(fill = UF_BLUE) +
  coord_flip() +
  scale_y_continuous(labels = scales::percent_format(scale = 1),
                     limits = c(0, NA),
                     expand = expansion(mult = c(0, 0.05))) +
  geom_text(aes(label = paste0(pct_primary_missing, "%")),
            hjust = -0.1, size = 3.5, color = DARK_TEXT) +
  labs(
    title = "Primary Payer Missingness by Partner Site",
    x = "Partner Site",
    y = "% Encounters Missing Primary Payer"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", color = UF_BLUE),
    panel.grid.major.y = element_blank()
  )

ggsave("output/figures/phase21_missingness_by_site.png", p1,
       width = 10, height = 6, dpi = 300)
message("  Saved: output/figures/phase21_missingness_by_site.png")

# ---- Chart 2: Duplicate date rate % by site (D-05) ----
p22_cross_site <- read_csv("output/tables/all_site_cross_site_summary.csv",
                            show_col_types = FALSE)

chart2_data <- p22_cross_site %>%
  filter(SITE != "ALL") %>%
  arrange(desc(pct_duplicate_rate)) %>%
  mutate(SITE = factor(SITE, levels = SITE))

p2 <- ggplot(chart2_data, aes(x = SITE, y = pct_duplicate_rate)) +
  geom_col(fill = UF_ORANGE) +
  coord_flip() +
  scale_y_continuous(labels = scales::percent_format(scale = 1),
                     limits = c(0, NA),
                     expand = expansion(mult = c(0, 0.05))) +
  geom_text(aes(label = paste0(pct_duplicate_rate, "%")),
            hjust = -0.1, size = 3.5, color = DARK_TEXT) +
  labs(
    title = "Duplicate Date Rate by Partner Site",
    x = "Partner Site",
    y = "% Patient-Dates with Duplicate Encounters"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", color = UF_BLUE),
    panel.grid.major.y = element_blank()
  )

ggsave("output/figures/phase22_duplication_by_site.png", p2,
       width = 10, height = 6, dpi = 300)
message("  Saved: output/figures/phase22_duplication_by_site.png")

# ---- Chart 3: Simplified aggregate missingness by encounter type (Slide 44) ----
p21_by_enc_type <- read_csv("output/tables/all_source_payer_missingness_by_enc_type.csv",
                             show_col_types = FALSE)

chart3_data <- p21_by_enc_type %>%
  filter(SOURCE != "ALL") %>%
  group_by(ENC_TYPE_LABEL) %>%
  summarise(
    n_encounters = sum(n_encounters),
    n_primary_missing = sum(n_primary_missing),
    .groups = "drop"
  ) %>%
  mutate(pct_missing = round(100 * n_primary_missing / n_encounters, 1)) %>%
  arrange(desc(pct_missing)) %>%
  mutate(ENC_TYPE_LABEL = factor(ENC_TYPE_LABEL, levels = ENC_TYPE_LABEL))

p3 <- ggplot(chart3_data, aes(x = ENC_TYPE_LABEL, y = pct_missing)) +
  geom_col(fill = UF_BLUE, width = 0.7) +
  coord_flip() +
  scale_y_continuous(labels = scales::percent_format(scale = 1),
                     limits = c(0, NA),
                     expand = expansion(mult = c(0, 0.05))) +
  geom_text(aes(label = paste0(pct_missing, "%")),
            hjust = -0.1, size = 3.5, color = DARK_TEXT) +
  labs(
    title = "Primary Payer Missingness by Encounter Type (All Sites)",
    x = "Encounter Type",
    y = "% Encounters Missing Primary Payer"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", color = UF_BLUE),
    panel.grid.major.y = element_blank()
  )

ggsave("output/figures/phase21_missingness_by_enc_type.png", p3,
       width = 10, height = 6, dpi = 300)
message("  Saved: output/figures/phase21_missingness_by_enc_type.png")

# ---- Chart 4: Cross-Site Payer Missingness grouped bar (Slide 39) ----
chart4_data <- p21_cross_site %>%
  filter(SOURCE != "ALL") %>%
  select(SOURCE, pct_primary_missing, pct_secondary_missing, pct_both_missing) %>%
  pivot_longer(
    cols = starts_with("pct_"),
    names_to = "field",
    values_to = "pct"
  ) %>%
  mutate(
    field = case_when(
      field == "pct_primary_missing" ~ "Primary",
      field == "pct_secondary_missing" ~ "Secondary",
      field == "pct_both_missing" ~ "Both"
    ),
    field = factor(field, levels = c("Primary", "Secondary", "Both")),
    SOURCE = factor(SOURCE, levels = rev(
      (p21_cross_site %>% filter(SOURCE != "ALL") %>% arrange(pct_primary_missing))$SOURCE
    ))
  )

p4 <- ggplot(chart4_data, aes(x = SOURCE, y = pct, fill = field)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  coord_flip() +
  scale_fill_manual(values = c("Primary" = UF_BLUE, "Secondary" = UF_ORANGE, "Both" = "#666666")) +
  scale_y_continuous(labels = scales::percent_format(scale = 1),
                     limits = c(0, NA),
                     expand = expansion(mult = c(0, 0.08))) +
  geom_text(aes(label = paste0(pct, "%")),
            position = position_dodge(width = 0.8),
            hjust = -0.1, size = 2.8, color = DARK_TEXT) +
  labs(
    title = "Payer Missingness by Partner Site",
    subtitle = "Primary, Secondary, and Both fields missing",
    x = "Partner Site",
    y = "% Encounters Missing",
    fill = "Payer Field"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", color = UF_BLUE),
    panel.grid.major.y = element_blank(),
    legend.position = "bottom"
  )

ggsave("output/figures/phase21_cross_site_missingness.png", p4,
       width = 10, height = 7, dpi = 300)
message("  Saved: output/figures/phase21_cross_site_missingness.png")

# ---- Chart 5: Raw PAYER_TYPE_PRIMARY top values faceted bar (Slide 41) ----
p21_raw_values <- read_csv("output/tables/all_source_payer_raw_value_distribution.csv",
                            show_col_types = FALSE)

chart5_data <- p21_raw_values %>%
  filter(field == "PRIMARY") %>%
  group_by(SOURCE) %>%
  slice_max(n, n = 5, with_ties = FALSE) %>%
  ungroup() %>%
  mutate(
    value = if_else(is.na(value) | value == "", "<NA>", as.character(value)),
    value_id = paste0(value, "___", SOURCE),
    value_id = reorder(value_id, pct)
  )

p5 <- ggplot(chart5_data, aes(x = value_id, y = pct)) +
  geom_col(fill = UF_BLUE, width = 0.7) +
  coord_flip() +
  facet_wrap(~ SOURCE, scales = "free_y", ncol = 3) +
  scale_x_discrete(labels = function(x) gsub("___.*$", "", x)) +
  scale_y_continuous(labels = scales::percent_format(scale = 1),
                     expand = expansion(mult = c(0, 0.12))) +
  geom_text(aes(label = paste0(pct, "%")),
            hjust = -0.1, size = 2.5, color = DARK_TEXT) +
  labs(
    title = "Raw PAYER_TYPE_PRIMARY: Top 5 Values per Site",
    x = NULL,
    y = "% of Encounters"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", color = UF_BLUE),
    strip.text = element_text(face = "bold"),
    panel.grid.major.y = element_blank()
  )

ggsave("output/figures/phase21_raw_payer_values.png", p5,
       width = 12, height = 8, dpi = 300)
message("  Saved: output/figures/phase21_raw_payer_values.png")

# ---- Chart 6: Enc Type x Site heatmap (Slides 42-43 collapsed) ----
chart6_data <- p21_by_enc_type %>%
  filter(SOURCE != "ALL") %>%
  select(SOURCE, ENC_TYPE_LABEL, pct_primary_missing)

p6 <- ggplot(chart6_data, aes(x = SOURCE, y = ENC_TYPE_LABEL, fill = pct_primary_missing)) +
  geom_tile(color = "white", linewidth = 0.5) +
  geom_text(aes(label = paste0(pct_primary_missing, "%")), size = 3, color = DARK_TEXT) +
  scale_fill_gradient(low = "#FFFFFF", high = UF_ORANGE,
                      labels = scales::percent_format(scale = 1),
                      name = "% Primary\nMissing") +
  labs(
    title = "Primary Payer Missingness by Encounter Type and Site",
    x = "Partner Site",
    y = "Encounter Type"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", color = UF_BLUE),
    axis.text.x = element_text(angle = 45, hjust = 1),
    panel.grid = element_blank()
  )

ggsave("output/figures/phase21_enc_type_heatmap.png", p6,
       width = 11, height = 7, dpi = 300)
message("  Saved: output/figures/phase21_enc_type_heatmap.png")

# ---- Chart 7: Raw vs Harmonized dumbbell chart (Slide 45) ----
p21_raw_harm <- read_csv("output/tables/all_source_payer_raw_vs_harmonized.csv",
                          show_col_types = FALSE)

chart7_data <- p21_raw_harm %>%
  filter(year == "OVERALL") %>%
  select(SOURCE, pct_raw_primary, pct_harmonized) %>%
  mutate(
    delta = round(pct_harmonized - pct_raw_primary, 1),
    SOURCE = reorder(SOURCE, pct_raw_primary)
  )

p7 <- ggplot(chart7_data) +
  geom_segment(aes(x = SOURCE, xend = SOURCE,
                   y = pct_raw_primary, yend = pct_harmonized),
               color = "#999999", linewidth = 1.2) +
  geom_point(aes(x = SOURCE, y = pct_raw_primary, color = "Raw"), size = 4) +
  geom_point(aes(x = SOURCE, y = pct_harmonized, color = "Harmonized"), size = 4) +
  geom_text(aes(x = SOURCE, y = (pct_raw_primary + pct_harmonized) / 2,
                label = paste0(ifelse(delta >= 0, "+", ""), delta, " pp")),
            hjust = -0.3, size = 3, color = DARK_TEXT) +
  coord_flip() +
  scale_color_manual(values = c("Raw" = UF_BLUE, "Harmonized" = UF_ORANGE),
                     name = "Missingness Type") +
  scale_y_continuous(labels = scales::percent_format(scale = 1)) +
  labs(
    title = "Raw vs Harmonized Payer Missingness by Site",
    x = "Partner Site",
    y = "% Missing"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", color = UF_BLUE),
    panel.grid.major.y = element_blank(),
    legend.position = "bottom"
  )

ggsave("output/figures/phase21_raw_vs_harmonized.png", p7,
       width = 10, height = 6, dpi = 300)
message("  Saved: output/figures/phase21_raw_vs_harmonized.png")

# ---- Chart 8: Temporal missingness faceted line chart (Slide 47) ----
p21_by_year <- read_csv("output/tables/all_source_payer_missingness_by_year.csv",
                         show_col_types = FALSE)

chart8_data <- p21_by_year %>%
  group_by(SOURCE) %>%
  slice_max(admit_year, n = 5, with_ties = FALSE) %>%
  ungroup()

p8 <- ggplot(chart8_data, aes(x = admit_year, y = pct_primary_missing)) +
  geom_line(color = UF_BLUE, linewidth = 1) +
  geom_point(color = UF_BLUE, size = 2.5) +
  geom_text(aes(label = paste0(pct_primary_missing, "%")),
            vjust = -0.8, size = 2.5, color = DARK_TEXT) +
  facet_wrap(~ SOURCE, ncol = 3, scales = "free_x") +
  scale_y_continuous(labels = scales::percent_format(scale = 1),
                     limits = c(0, NA)) +
  labs(
    title = "Primary Payer Missingness by Year (Recent 5 Years)",
    x = "Admission Year",
    y = "% Primary Missing"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", color = UF_BLUE),
    strip.text = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  )

ggsave("output/figures/phase21_temporal_missingness.png", p8,
       width = 12, height = 7, dpi = 300)
message("  Saved: output/figures/phase21_temporal_missingness.png")

# ---- Chart 9: Cross-site duplicate rate bar chart colored by rec source (Slide 48) ----
chart9_data <- p22_cross_site %>%
  filter(SITE != "ALL") %>%
  arrange(desc(pct_duplicate_rate)) %>%
  mutate(
    SITE = factor(SITE, levels = rev(SITE)),
    rec_source = if_else(is.na(recommended_source), "N/A", recommended_source)
  )

p9 <- ggplot(chart9_data, aes(x = SITE, y = pct_duplicate_rate, fill = rec_source)) +
  geom_col(width = 0.7) +
  coord_flip() +
  scale_fill_brewer(palette = "Set2", name = "Recommended\nSource") +
  scale_y_continuous(labels = scales::percent_format(scale = 1),
                     limits = c(0, NA),
                     expand = expansion(mult = c(0, 0.08))) +
  geom_text(aes(label = paste0(pct_duplicate_rate, "%")),
            hjust = -0.1, size = 3.5, color = DARK_TEXT) +
  labs(
    title = "Duplicate Date Rate by Partner Site",
    subtitle = "Color = recommended ENCOUNTER_SOURCE for payer data",
    x = "Partner Site",
    y = "% Patient-Dates with Duplicates"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", color = UF_BLUE),
    panel.grid.major.y = element_blank(),
    legend.position = "bottom"
  )

ggsave("output/figures/phase22_cross_site_duplicates.png", p9,
       width = 10, height = 7, dpi = 300)
message("  Saved: output/figures/phase22_cross_site_duplicates.png")

# ---- Chart 10: Dup rate scatter plot (Slide 49) ----
chart10_data <- p22_cross_site %>%
  filter(SITE != "ALL")

p10 <- ggplot(chart10_data, aes(x = n_patients, y = pct_duplicate_rate)) +
  geom_point(aes(size = n_encounters), color = UF_BLUE, alpha = 0.7) +
  geom_text(aes(label = SITE), vjust = -1, size = 3.5, color = DARK_TEXT) +
  scale_x_continuous(labels = scales::comma) +
  scale_y_continuous(labels = scales::percent_format(scale = 1)) +
  scale_size_continuous(labels = scales::comma, name = "Total\nEncounters",
                        range = c(3, 12)) +
  labs(
    title = "Duplicate Rate vs Cohort Size by Site",
    x = "Number of Patients",
    y = "% Patient-Dates with Duplicates"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", color = UF_BLUE),
    legend.position = "right"
  )

ggsave("output/figures/phase22_dup_rate_scatter.png", p10,
       width = 10, height = 7, dpi = 300)
message("  Saved: output/figures/phase22_dup_rate_scatter.png")

# ---- Chart 11: Per-site key rate metrics grouped bar (Slide 50) ----
chart11_data <- p22_cross_site %>%
  filter(SITE != "ALL") %>%
  mutate(pct_near_exact = round(100 * n_near_exact_dupes / n_unique_dates, 1)) %>%
  select(SITE, pct_duplicate_rate, pct_multi_source_of_dupes, pct_near_exact) %>%
  pivot_longer(
    cols = c(pct_duplicate_rate, pct_multi_source_of_dupes, pct_near_exact),
    names_to = "metric",
    values_to = "pct"
  ) %>%
  mutate(
    metric = case_when(
      metric == "pct_duplicate_rate" ~ "Duplicate Rate",
      metric == "pct_multi_source_of_dupes" ~ "Multi-Source %",
      metric == "pct_near_exact" ~ "Near-Exact Dup %"
    ),
    metric = factor(metric, levels = c("Duplicate Rate", "Multi-Source %", "Near-Exact Dup %")),
    SITE = factor(SITE, levels = rev(sort(unique(SITE))))
  )

p11 <- ggplot(chart11_data, aes(x = SITE, y = pct, fill = metric)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  coord_flip() +
  scale_fill_manual(values = c("Duplicate Rate" = UF_BLUE,
                                "Multi-Source %" = UF_ORANGE,
                                "Near-Exact Dup %" = "#666666"),
                    name = "Metric") +
  scale_y_continuous(labels = scales::percent_format(scale = 1),
                     expand = expansion(mult = c(0, 0.08))) +
  geom_text(aes(label = paste0(pct, "%")),
            position = position_dodge(width = 0.8),
            hjust = -0.1, size = 2.8, color = DARK_TEXT) +
  labs(
    title = "Key Duplication Metrics by Partner Site",
    x = "Partner Site",
    y = "Percentage"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", color = UF_BLUE),
    panel.grid.major.y = element_blank(),
    legend.position = "bottom"
  )

ggsave("output/figures/phase22_per_site_metrics.png", p11,
       width = 10, height = 7, dpi = 300)
message("  Saved: output/figures/phase22_per_site_metrics.png")

# ---- Chart 12: Source payer completeness heatmap (Slide 54) ----
p22_source_comp <- read_csv("output/tables/all_site_source_payer_completeness.csv",
                             show_col_types = FALSE)

if (nrow(p22_source_comp) > 0) {
  p12 <- ggplot(p22_source_comp, aes(x = ENCOUNTER_SOURCE, y = SITE,
                                      fill = pct_primary_present)) +
    geom_tile(color = "white", linewidth = 0.5) +
    geom_text(aes(label = paste0(pct_primary_present, "%")), size = 3, color = DARK_TEXT) +
    scale_fill_gradient(low = UF_ORANGE, high = "#4CAF50",
                        labels = scales::percent_format(scale = 1),
                        name = "% Primary\nPresent") +
    labs(
      title = "Source Payer Completeness for Multi-Source Dates",
      x = "ENCOUNTER_SOURCE",
      y = "Partner Site"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", color = UF_BLUE),
      panel.grid = element_blank(),
      axis.text.x = element_text(angle = 45, hjust = 1)
    )

  ggsave("output/figures/phase22_source_completeness_heatmap.png", p12,
         width = 12, height = 7, dpi = 300)
  message("  Saved: output/figures/phase22_source_completeness_heatmap.png")
}

# ---- Chart 13: Patient duplicate summary grouped bar (Slide 55) ----
p22_patient_summary <- read_csv("output/tables/all_site_patient_duplicate_summary.csv",
                                 show_col_types = FALSE)

chart13_data <- p22_patient_summary %>%
  group_by(SITE) %>%
  summarise(
    n_patients = n(),
    pct_with_dupes = round(100 * sum(n_duplicate_dates > 0) / n(), 1),
    pct_with_multi_source = round(100 * sum(n_multi_source_dates > 0) / n(), 1),
    .groups = "drop"
  ) %>%
  pivot_longer(
    cols = c(pct_with_dupes, pct_with_multi_source),
    names_to = "metric",
    values_to = "pct"
  ) %>%
  mutate(
    metric = case_when(
      metric == "pct_with_dupes" ~ "% With Duplicates",
      metric == "pct_with_multi_source" ~ "% Multi-Source Dates"
    ),
    metric = factor(metric, levels = c("% With Duplicates", "% Multi-Source Dates")),
    SITE = factor(SITE, levels = rev(sort(unique(SITE))))
  )

p13 <- ggplot(chart13_data, aes(x = SITE, y = pct, fill = metric)) +
  geom_col(position = position_dodge(width = 0.7), width = 0.6) +
  coord_flip() +
  scale_fill_manual(values = c("% With Duplicates" = UF_BLUE,
                                "% Multi-Source Dates" = UF_ORANGE),
                    name = "Metric") +
  scale_y_continuous(labels = scales::percent_format(scale = 1),
                     expand = expansion(mult = c(0, 0.08))) +
  geom_text(aes(label = paste0(pct, "%")),
            position = position_dodge(width = 0.7),
            hjust = -0.1, size = 3, color = DARK_TEXT) +
  labs(
    title = "Patient Duplicate Summary by Site",
    x = "Partner Site",
    y = "% of Patients"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", color = UF_BLUE),
    panel.grid.major.y = element_blank(),
    legend.position = "bottom"
  )

ggsave("output/figures/phase22_patient_dup_summary.png", p13,
       width = 10, height = 6, dpi = 300)
message("  Saved: output/figures/phase22_patient_dup_summary.png")

# ---- Chart 14: Date-level duplicate detail heatmap (Slide 56) ----
p22_date_detail <- read_csv("output/tables/all_site_date_level_duplicate_detail.csv",
                             show_col_types = FALSE)

if (nrow(p22_date_detail) > 0) {
  chart14_data <- p22_date_detail %>%
    group_by(SITE, ENCOUNTER_SOURCE) %>%
    summarise(
      n_encounters = n(),
      pct_primary_missing = round(100 * sum(primary_missing, na.rm = TRUE) / n(), 1),
      .groups = "drop"
    )

  p14 <- ggplot(chart14_data, aes(x = ENCOUNTER_SOURCE, y = SITE,
                                    fill = pct_primary_missing)) +
    geom_tile(color = "white", linewidth = 0.5) +
    geom_text(aes(label = paste0(pct_primary_missing, "%")), size = 3, color = DARK_TEXT) +
    scale_fill_gradient(low = "#FFFFFF", high = UF_ORANGE,
                        labels = scales::percent_format(scale = 1),
                        name = "% Primary\nMissing") +
    labs(
      title = "Multi-Source Dates: Payer Missingness by Source",
      x = "ENCOUNTER_SOURCE",
      y = "Partner Site"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", color = UF_BLUE),
      panel.grid = element_blank(),
      axis.text.x = element_text(angle = 45, hjust = 1)
    )

  ggsave("output/figures/phase22_date_detail_heatmap.png", p14,
         width = 12, height = 7, dpi = 300)
  message("  Saved: output/figures/phase22_date_detail_heatmap.png")
}

# ==============================================================================
# SECTION 8: PHASE 21 MISSINGNESS SLIDES (D-01, D-04, D-06)
# ==============================================================================

message("\n--- Adding Phase 21 Missingness Slides ---")


# ---- Slide 39: Cross-Site Payer Missingness Summary (grouped bar chart) ----
message("  Slide 39: Cross-Site Payer Missingness Summary (chart)")

pptx <- add_image_slide(pptx,
  "Payer Missingness: Cross-Site Comparison",
  "Primary, secondary, and both payer fields missing by partner site (HL cohort encounters)",
  "output/figures/phase21_cross_site_missingness.png",
  img_width = 9, img_height = 5.5) %>%
  add_footnote("Missing = NA, empty, NI, UN, OT, 99, 9999. Sorted by primary missingness rate.")

# ---- Slide 40: Bar chart -- Primary Missingness by Site (D-05) ----
message("  Slide 40: Primary Payer Missingness by Site (bar chart)")

pptx <- add_image_slide(pptx,
  "Primary Payer Missingness by Partner Site",
  "Percentage of HL cohort encounters with missing primary payer data, sorted descending",
  "output/figures/phase21_missingness_by_site.png",
  img_width = 9, img_height = 5.0) %>%
  add_footnote("Missing = NA, empty, NI, UN, OT, 99, 9999. Excludes ALL aggregate row.")

# ---- Slide 41: Raw Value Distribution -- faceted bar chart ----
message("  Slide 41: Raw Payer Value Distribution (chart)")

pptx <- add_image_slide(pptx,
  "Raw PAYER_TYPE_PRIMARY: Top 5 Values per Site",
  "Most frequent raw primary payer values in HL cohort encounters, by partner site",
  "output/figures/phase21_raw_payer_values.png",
  img_width = 9.5, img_height = 5.5) %>%
  add_footnote("Shows top 5 values per site. Full distribution in all_source_payer_raw_value_distribution.csv.")

# ---- Slide 42: Missingness by Encounter Type heatmap (replaces 2 table slides) ----
message("  Slide 42: Missingness by Encounter Type (heatmap)")

pptx <- add_image_slide(pptx,
  "Primary Payer Missingness by Encounter Type and Site",
  "Heatmap of % primary payer missing across encounter types and partner sites",
  "output/figures/phase21_enc_type_heatmap.png",
  img_width = 9.5, img_height = 5.5) %>%
  add_footnote("ENC_TYPE codes: AV=Ambulatory, IP=Inpatient, ED=Emergency, EI=ED-to-Inpatient, IS=Non-acute Institutional, OS=Observation, TH=Telehealth, OT=Other.")

# ---- Slide 43: Aggregate missingness by encounter type (simplified bar chart) ----
message("  Slide 43: Missingness by Encounter Type (aggregate bar chart)")

pptx <- add_image_slide(pptx,
  "Primary Payer Missingness by Encounter Type (All Sites)",
  "Aggregate primary payer missingness across all partner sites, sorted descending",
  "output/figures/phase21_missingness_by_enc_type.png",
  img_width = 9, img_height = 5.0) %>%
  add_footnote("Aggregated across all sites. Bars show % of encounters with missing primary payer data.")

# ---- Slide 44: Raw vs Harmonized Comparison (dumbbell chart) ----
message("  Slide 44: Raw vs Harmonized Missingness Comparison (chart)")

pptx <- add_image_slide(pptx,
  "Raw vs Harmonized Payer Missingness by Site",
  "Comparison of raw field missingness vs harmonized category missingness (OVERALL)",
  "output/figures/phase21_raw_vs_harmonized.png",
  img_width = 9, img_height = 5.0) %>%
  add_footnote("Raw = PAYER_TYPE_PRIMARY is NA/empty/sentinel. Harmonized = payer_category is NA/Missing. Delta in percentage points shown between dots.")

# ---- Slide 45: Year x Enc Type -- summary only (all_source_payer_missingness_year_x_enc_type.csv is 1015 rows) ----
message("  Slide 45: Year x Enc Type Missingness (top combinations)")

p21_year_enc <- read_csv("output/tables/all_source_payer_missingness_year_x_enc_type.csv",
                          show_col_types = FALSE)

# Show top 20 combinations by primary missingness % (min 50 encounters)
year_enc_top20 <- p21_year_enc %>%
  filter(n_encounters >= 50) %>%
  arrange(desc(pct_primary_missing)) %>%
  head(20) %>%
  mutate(
    pct_primary_missing = paste0(pct_primary_missing, "%"),
    n_encounters = format(n_encounters, big.mark = ","),
    n_primary_missing = format(n_primary_missing, big.mark = ",")
  ) %>%
  select(
    `Site` = SOURCE,
    `Year` = admit_year,
    `Enc Type` = ENC_TYPE_LABEL,
    `Encounters` = n_encounters,
    `Primary Missing` = n_primary_missing,
    `% Missing` = pct_primary_missing
  )

pptx <- add_table_slide(pptx,
  "Highest Missingness: Year x Encounter Type Combinations",
  "Top 20 site-year-encounter type combinations by primary payer missingness (min 50 encounters)",
  year_enc_top20) %>%
  add_footnote("Full crosstab (1,015 rows) in all_source_payer_missingness_year_x_enc_type.csv. Filtered to combinations with >= 50 encounters.")

# ---- Slide 46: Temporal Missingness by Year (faceted line chart) ----
message("  Slide 46: Temporal Missingness by Year (chart)")

pptx <- add_image_slide(pptx,
  "Payer Missingness by Year (Recent 5 Years per Site)",
  "Primary payer missingness trend by admission year, most recent 5 years per partner site",
  "output/figures/phase21_temporal_missingness.png",
  img_width = 9.5, img_height = 5.5) %>%
  add_footnote("Full temporal breakdown in all_source_payer_missingness_by_year.csv. 1900 sentinel dates excluded.")

# ==============================================================================
# SECTION 9: PHASE 22 DUPLICATION SLIDES (D-01, D-03, D-04, D-06)
# ==============================================================================

message("\n--- Adding Phase 22 Duplication Slides ---")

# ---- Slide: Cross-Site Duplicate Date Summary (bar chart) ----
message("  Adding slide: Cross-Site Duplicate Date Summary (chart)")

pptx <- add_image_slide(pptx,
  "Duplicate Dates: Cross-Site Comparison",
  "Same-date duplicate encounter rate by partner site, colored by recommended ENCOUNTER_SOURCE",
  "output/figures/phase22_cross_site_duplicates.png",
  img_width = 9, img_height = 5.5) %>%
  add_footnote("Duplicate = >1 encounter on same ADMIT_DATE for same patient. Color = ENCOUNTER.SOURCE with highest primary payer completeness.")

# ---- Slide: Duplicate Rate Scatter Plot ----
message("  Adding slide: Duplicate Rate vs Cohort Size (scatter plot)")

pptx <- add_image_slide(pptx,
  "Duplicate Rate vs Cohort Size by Site",
  "Relationship between number of patients and duplicate date rate; point size = total encounters",
  "output/figures/phase22_dup_rate_scatter.png",
  img_width = 9, img_height = 5.5) %>%
  add_footnote("Each point = one partner site. Size proportional to total encounter count. Excludes ALL aggregate row.")

# ---- Slide: Per-Site Key Duplication Metrics (grouped bar chart) ----
message("  Adding slide: Per-Site Key Duplication Metrics (chart)")

pptx <- add_image_slide(pptx,
  "Key Duplication Metrics by Partner Site",
  "Duplicate rate, multi-source %, and near-exact duplicate rate per site",
  "output/figures/phase22_per_site_metrics.png",
  img_width = 9, img_height = 5.5) %>%
  add_footnote("Duplicate Rate = % patient-dates with >1 encounter. Multi-Source = % of duplicates from different ENCOUNTER.SOURCE. Near-Exact = normalized near-exact dup rate.")

# ---- Slide: Source Payer Completeness (heatmap) ----
message("  Adding slide: Source Payer Completeness (heatmap)")

if (file.exists("output/figures/phase22_source_completeness_heatmap.png")) {
  pptx <- add_image_slide(pptx,
    "Source Payer Completeness for Multi-Source Dates",
    "Primary payer completeness by ENCOUNTER_SOURCE and partner site for multi-source duplicate dates",
    "output/figures/phase22_source_completeness_heatmap.png",
    img_width = 9.5, img_height = 5.5) %>%
    add_footnote("Shows only encounters on dates where >1 ENCOUNTER.SOURCE contributed. Higher % (green) = more payer data available from that source.")
} else {
  message("  SKIPPED: Source payer completeness -- no multi-source encounters found.")
}

# ---- Slide: Patient Duplicate Summary (grouped bar chart) ----
message("  Adding slide: Patient Duplicate Summary (chart)")

pptx <- add_image_slide(pptx,
  "Patient Duplicate Summary by Site",
  "Percentage of patients with duplicate dates and multi-source dates, by partner site",
  "output/figures/phase22_patient_dup_summary.png",
  img_width = 9, img_height = 5.0) %>%
  add_footnote("Duplicates = patient has >1 encounter on same date. Multi-Source = encounters from different ENCOUNTER.SOURCE values. Full detail in all_site_patient_duplicate_summary.csv.")

# ---- Slide: Date-Level Detail -- payer missingness heatmap ----
message("  Adding slide: Date-Level Duplicate Detail (heatmap)")

if (file.exists("output/figures/phase22_date_detail_heatmap.png")) {
  pptx <- add_image_slide(pptx,
    "Multi-Source Dates: Payer Missingness by Source",
    "Primary payer missingness by ENCOUNTER_SOURCE and partner site for multi-source duplicate dates",
    "output/figures/phase22_date_detail_heatmap.png",
    img_width = 9.5, img_height = 5.5) %>%
    add_footnote("Shows encounters on multi-source dates. Higher % (darker) = more missing payer data from that source. Full detail in all_site_date_level_duplicate_detail.csv.")
} else {
  message("  SKIPPED: Date-level detail -- no multi-source encounters found.")
}

# ==============================================================================
# SECTION 10: SAVE PPTX
# ==============================================================================

output_filename <- glue("insurance_tables_{Sys.Date()}.pptx")
output_path <- file.path(output_filename)
print(pptx, target = output_path)

message(glue("\n  PowerPoint saved to: {output_path}"))
n_slides <- length(pptx)
message(glue("  Slides: {n_slides} (38 original + {n_slides - 38} Phase 21/22 chart slides)"))
message(glue("  Cohort: {format(N_TOTAL, big.mark = ',')} patients ({format(N_TREATED, big.mark = ',')} treated)"))
message(glue("  Date: {Sys.Date()}"))

message("\n", strrep("=", 60))
message("PowerPoint generation complete")
message(strrep("=", 60))

# ==============================================================================
# End of 72_generate_pptx.R
# ==============================================================================
