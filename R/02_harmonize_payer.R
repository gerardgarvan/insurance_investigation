# ==============================================================================
# 02_harmonize_payer.R -- Payer harmonization pipeline
# ==============================================================================
#
# Implements 9-category payer mapping with encounter-level dual-eligible detection
# matching the Python pipeline's logic exactly. Produces patient-level payer summary
# and per-partner enrollment completeness report.
#
# Requirements: PAYR-01, PAYR-02, PAYR-03
#
# Usage:
#   source("R/02_harmonize_payer.R")
#   # Produces: payer_summary tibble (patient-level)
#   # Prints: enrollment completeness by partner, payer distribution, validation summary
#   # Saves: output/tables/payer_summary.csv
#
# ==============================================================================

source("R/01_load_pcornet.R")  # Loads data and config (auto-sources utils)

library(dplyr)
library(stringr)
library(lubridate)
library(glue)
library(readr)

message("\n", strrep("=", 60))
message("Payer Harmonization Pipeline")
message(strrep("=", 60))

# ==============================================================================
# SECTION 1: NAMED PAYER FUNCTIONS
# ==============================================================================

#' Compute effective payer per encounter
#'
#' Returns primary if valid, else secondary if valid, else NA.
#' Sentinel values (NI, UN, OT) trigger fallback to secondary.
#' 99/9999 are NOT sentinel — they are valid and map to "Unavailable".
#'
#' @param primary Character vector of PAYER_TYPE_PRIMARY values
#' @param secondary Character vector of PAYER_TYPE_SECONDARY values
#' @return Character vector of effective payer codes
#'
compute_effective_payer <- function(primary, secondary) {
  sentinel_values <- PAYER_MAPPING$sentinel_values  # c("NI", "UN", "OT")

  # Primary is valid if non-NA, non-empty, and not sentinel
  primary_valid <- !is.na(primary) &
                   nchar(trimws(primary)) > 0 &
                   !primary %in% sentinel_values

  # Secondary is valid if non-NA, non-empty, and not sentinel
  secondary_valid <- !is.na(secondary) &
                     nchar(trimws(secondary)) > 0 &
                     !secondary %in% sentinel_values

  # Return primary if valid, else secondary if valid, else NA
  case_when(
    primary_valid ~ primary,
    secondary_valid ~ secondary,
    TRUE ~ NA_character_
  )
}

#' Detect dual-eligible encounters
#'
#' Returns 1 if encounter is dual-eligible, 0 otherwise.
#' Dual-eligible = (Medicare primary + Medicaid secondary) OR
#'                 (Medicaid primary + Medicare secondary) OR
#'                 (primary or secondary in {14, 141, 142})
#'
#' When secondary is missing/empty, returns 0 (cannot compute cross-payer check).
#'
#' @param primary Character vector of PAYER_TYPE_PRIMARY values
#' @param secondary Character vector of PAYER_TYPE_SECONDARY values
#' @return Integer vector (0 or 1) indicating dual-eligible status
#'
detect_dual_eligible <- function(primary, secondary) {
  dual_codes <- PAYER_MAPPING$dual_eligible_codes  # c("14", "141", "142")

  # Check if secondary is missing/empty
  secondary_missing <- is.na(secondary) | nchar(trimws(secondary)) == 0

  # Check if primary or secondary is in dual codes
  has_dual_code <- primary %in% dual_codes | secondary %in% dual_codes

  # Check cross-payer: Medicare+Medicaid or Medicaid+Medicare
  cross_payer <- (str_starts(primary, "1") & str_starts(secondary, "2")) |
                 (str_starts(primary, "2") & str_starts(secondary, "1"))

  # Return 0 if secondary missing, else check dual conditions
  case_when(
    secondary_missing ~ 0L,
    has_dual_code ~ 1L,
    cross_payer ~ 1L,
    TRUE ~ 0L
  )
}

#' Map effective payer to 9-category system
#'
#' Applies exact-match overrides first (99/9999 -> Unavailable, NI/UN/OT/UNKNOWN -> Unknown),
#' then prefix rules (1->Medicare, 2->Medicaid, etc.), then dual-eligible override.
#'
#' @param effective_payer Character vector of effective payer codes
#' @param dual_eligible_encounter Integer vector (0/1) indicating dual-eligible encounters
#' @return Character vector of payer categories (9 levels)
#'
map_payer_category <- function(effective_payer, dual_eligible_encounter) {

  # First compute raw category from effective_payer
  # CRITICAL: exact-match overrides BEFORE prefix rules
  payer_category_raw <- case_when(
    # Exact-match overrides
    effective_payer %in% PAYER_MAPPING$unavailable_codes ~ "Unavailable",  # 99, 9999
    effective_payer %in% PAYER_MAPPING$unknown_codes | is.na(effective_payer) ~ "Unknown",  # NI, UN, OT, UNKNOWN, NA

    # Prefix rules
    str_starts(effective_payer, "1") ~ "Medicare",
    str_starts(effective_payer, "2") ~ "Medicaid",
    str_starts(effective_payer, "5") | str_starts(effective_payer, "6") ~ "Private",
    str_starts(effective_payer, "3") | str_starts(effective_payer, "4") ~ "Other government",
    str_starts(effective_payer, "8") ~ "No payment / Self-pay",
    str_starts(effective_payer, "7") | str_starts(effective_payer, "9") ~ "Other",

    # Default
    TRUE ~ "Other"
  )

  # Then apply dual-eligible override
  if_else(dual_eligible_encounter == 1L, "Dual eligible", payer_category_raw)
}

# ==============================================================================
# SECTION 2: ENCOUNTER-LEVEL PROCESSING
# ==============================================================================

# Check if PAYER_TYPE_SECONDARY column exists (Pitfall 3)
if (!"PAYER_TYPE_SECONDARY" %in% names(pcornet$ENCOUNTER)) {
  message("WARNING: PAYER_TYPE_SECONDARY not found in ENCOUNTER table. Setting all dual_eligible = 0")
  pcornet$ENCOUNTER$PAYER_TYPE_SECONDARY <- NA_character_
}

# Process all encounters
encounters <- pcornet$ENCOUNTER %>%
  mutate(
    effective_payer = compute_effective_payer(PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY),
    dual_eligible_encounter = detect_dual_eligible(PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY),
    payer_category = map_payer_category(effective_payer, dual_eligible_encounter)
  )

# Log encounter processing stats
n_total_encounters <- nrow(encounters)
n_with_valid_payer <- sum(!is.na(encounters$effective_payer) &
                          nchar(trimws(encounters$effective_payer)) > 0 &
                          !encounters$effective_payer %in% PAYER_MAPPING$sentinel_values)
n_dual_eligible_enc <- sum(encounters$dual_eligible_encounter == 1, na.rm = TRUE)

message(glue("\nEncounter processing:"))
message(glue("  Total encounters: {format(n_total_encounters, big.mark=',')}"))
message(glue("  Encounters with valid effective payer: {format(n_with_valid_payer, big.mark=',')} ({round(100*n_with_valid_payer/n_total_encounters, 1)}%)"))
message(glue("  Dual-eligible encounters: {format(n_dual_eligible_enc, big.mark=',')} ({round(100*n_dual_eligible_enc/n_total_encounters, 1)}%)"))

# ==============================================================================
# SECTION 3: FIRST HL DIAGNOSIS DATE
# ==============================================================================

# Get earliest HL diagnosis from DIAGNOSIS table
dx_dates <- pcornet$DIAGNOSIS %>%
  filter(is_hl_diagnosis(DX, DX_TYPE)) %>%
  group_by(ID) %>%
  summarise(first_dx_date_diagnosis = if (all(is.na(DX_DATE))) NA_real_ else min(DX_DATE, na.rm = TRUE), .groups = "drop")

# Get earliest from TUMOR_REGISTRY tables
tr_tables <- list()
if (!is.null(pcornet$TUMOR_REGISTRY1) &&
    "DATE_OF_DIAGNOSIS" %in% names(pcornet$TUMOR_REGISTRY1)) {
  tr_tables <- c(tr_tables, list(pcornet$TUMOR_REGISTRY1 %>% select(ID, DATE_OF_DIAGNOSIS)))
}
if (!is.null(pcornet$TUMOR_REGISTRY2) &&
    "DXDATE" %in% names(pcornet$TUMOR_REGISTRY2)) {
  tr_tables <- c(tr_tables, list(pcornet$TUMOR_REGISTRY2 %>% select(ID, DATE_OF_DIAGNOSIS = DXDATE)))
}
if (!is.null(pcornet$TUMOR_REGISTRY3) &&
    "DXDATE" %in% names(pcornet$TUMOR_REGISTRY3)) {
  tr_tables <- c(tr_tables, list(pcornet$TUMOR_REGISTRY3 %>% select(ID, DATE_OF_DIAGNOSIS = DXDATE)))
}

if (length(tr_tables) > 0) {
  tr_dates <- bind_rows(tr_tables) %>%
    filter(!is.na(DATE_OF_DIAGNOSIS)) %>%
    group_by(ID) %>%
    summarise(first_dx_date_tr = min(DATE_OF_DIAGNOSIS, na.rm = TRUE), .groups = "drop")
} else {
  tr_dates <- data.frame(ID = character(), first_dx_date_tr = as.Date(character()), stringsAsFactors = FALSE)
}

# Combine: prefer tumor registry date; fall back to diagnosis table if no TR data
first_dx <- dx_dates %>%
  full_join(tr_dates, by = "ID") %>%
  mutate(first_hl_dx_date = if_else(!is.na(first_dx_date_tr),
                                     first_dx_date_tr,
                                     first_dx_date_diagnosis)) %>%
  select(ID, first_hl_dx_date)

message(glue("\nFirst HL diagnosis:"))
message(glue("  Patients with HL diagnosis found: {format(nrow(first_dx), big.mark=',')}"))

# ==============================================================================
# SECTION 4: PATIENT-LEVEL SUMMARY
# ==============================================================================

# 4a. N_ENCOUNTERS and N_ENCOUNTERS_WITH_PAYER per patient
encounter_counts <- encounters %>%
  group_by(ID) %>%
  summarise(
    N_ENCOUNTERS = n(),
    N_ENCOUNTERS_WITH_PAYER = sum(!is.na(effective_payer) &
                                   nchar(trimws(effective_payer)) > 0 &
                                   !effective_payer %in% PAYER_MAPPING$sentinel_values),
    .groups = "drop"
  )

# 4b. PAYER_CATEGORY_PRIMARY -- mode of payer_category across ALL valid encounters
payer_primary <- encounters %>%
  filter(!is.na(effective_payer) &
         nchar(trimws(effective_payer)) > 0 &
         !effective_payer %in% PAYER_MAPPING$sentinel_values) %>%
  group_by(ID, payer_category) %>%
  summarise(n = n(), .groups = "drop") %>%
  arrange(ID, desc(n), payer_category) %>%
  group_by(ID) %>%
  slice(1) %>%
  ungroup() %>%
  select(ID, PAYER_CATEGORY_PRIMARY = payer_category)

# 4c. PAYER_CATEGORY_AT_FIRST_DX -- mode within +/-30 days of first HL DX
dx_window <- CONFIG$analysis$dx_window_days  # 30

payer_at_dx <- encounters %>%
  filter(!is.na(effective_payer) &
         nchar(trimws(effective_payer)) > 0 &
         !effective_payer %in% PAYER_MAPPING$sentinel_values) %>%
  inner_join(first_dx, by = "ID") %>%
  mutate(days_from_dx = as.numeric(ADMIT_DATE - first_hl_dx_date)) %>%
  filter(!is.na(days_from_dx) & abs(days_from_dx) <= dx_window) %>%
  group_by(ID, payer_category) %>%
  summarise(n = n(), .groups = "drop") %>%
  arrange(ID, desc(n), payer_category) %>%
  group_by(ID) %>%
  slice(1) %>%
  ungroup() %>%
  select(ID, PAYER_CATEGORY_AT_FIRST_DX = payer_category)

# 4d. DUAL_ELIGIBLE -- patient-level rollup (1 if any encounter dual-eligible)
patient_dual <- encounters %>%
  group_by(ID) %>%
  summarise(DUAL_ELIGIBLE = as.integer(max(dual_eligible_encounter, na.rm = TRUE) == 1), .groups = "drop")

# 4e. PAYER_TRANSITION -- 1 if >1 distinct payer category across valid encounters
payer_transition <- encounters %>%
  filter(!is.na(effective_payer) &
         nchar(trimws(effective_payer)) > 0 &
         !effective_payer %in% PAYER_MAPPING$sentinel_values) %>%
  group_by(ID) %>%
  summarise(n_distinct_categories = n_distinct(payer_category), .groups = "drop") %>%
  mutate(PAYER_TRANSITION = as.integer(n_distinct_categories > 1)) %>%
  select(ID, PAYER_TRANSITION)

# 4f. Get SOURCE from DEMOGRAPHIC (one row per patient)
patient_source <- pcornet$DEMOGRAPHIC %>%
  select(ID, SOURCE) %>%
  distinct()

# 4g. Assemble payer_summary
payer_summary <- patient_source %>%
  left_join(encounter_counts, by = "ID") %>%
  left_join(payer_primary, by = "ID") %>%
  left_join(payer_at_dx, by = "ID") %>%
  left_join(patient_dual, by = "ID") %>%
  left_join(payer_transition, by = "ID") %>%
  mutate(
    N_ENCOUNTERS = coalesce(N_ENCOUNTERS, 0L),
    N_ENCOUNTERS_WITH_PAYER = coalesce(N_ENCOUNTERS_WITH_PAYER, 0L),
    DUAL_ELIGIBLE = coalesce(DUAL_ELIGIBLE, 0L),
    PAYER_TRANSITION = coalesce(PAYER_TRANSITION, 0L)
  )

message(glue("\nPatient-level summary:"))
message(glue("  Total patients in payer_summary: {format(nrow(payer_summary), big.mark=',')}"))

# ==============================================================================
# SECTION 5: ENROLLMENT COMPLETENESS REPORT (PAYR-03)
# ==============================================================================

# 5a. Total patients per partner
patients_per_partner <- pcornet$DEMOGRAPHIC %>%
  group_by(SOURCE) %>%
  summarise(n_patients = n_distinct(ID), .groups = "drop")

# 5b. Patients with enrollment per partner
patients_with_enrollment <- pcornet$ENROLLMENT %>%
  group_by(SOURCE) %>%
  summarise(n_with_enrollment = n_distinct(ID), .groups = "drop")

# 5c. Mean covered days per partner
covered_days <- pcornet$ENROLLMENT %>%
  filter(!is.na(ENR_START_DATE) & !is.na(ENR_END_DATE)) %>%
  mutate(period_days = as.numeric(ENR_END_DATE - ENR_START_DATE)) %>%
  group_by(SOURCE, ID) %>%
  summarise(total_covered_days = sum(period_days, na.rm = TRUE), .groups = "drop") %>%
  group_by(SOURCE) %>%
  summarise(mean_covered_days = mean(total_covered_days, na.rm = TRUE), .groups = "drop")

# 5d. Gap detection (gap = >30 days between consecutive enrollment periods)
enrollment_gaps <- pcornet$ENROLLMENT %>%
  filter(!is.na(ENR_START_DATE) & !is.na(ENR_END_DATE)) %>%
  arrange(ID, SOURCE, ENR_START_DATE) %>%
  group_by(ID, SOURCE) %>%
  mutate(
    prev_end_date = lag(ENR_END_DATE),
    gap_days = as.numeric(ENR_START_DATE - prev_end_date)
  ) %>%
  ungroup() %>%
  filter(!is.na(gap_days) & gap_days > 30)

n_with_gaps_per_partner <- enrollment_gaps %>%
  group_by(SOURCE) %>%
  summarise(n_with_gaps = n_distinct(ID), .groups = "drop")

# 5e. Assemble and print completeness report
completeness_report <- patients_per_partner %>%
  left_join(patients_with_enrollment, by = "SOURCE") %>%
  left_join(covered_days, by = "SOURCE") %>%
  left_join(n_with_gaps_per_partner, by = "SOURCE") %>%
  mutate(
    n_with_enrollment = coalesce(n_with_enrollment, 0L),
    pct_enrolled = round(100 * n_with_enrollment / n_patients, 1),
    mean_covered_days = coalesce(mean_covered_days, 0),
    n_with_gaps = coalesce(n_with_gaps, 0L)
  )

message("\n=== Enrollment Completeness by Partner ===")
for (i in seq_len(nrow(completeness_report))) {
  r <- completeness_report[i, ]
  message(glue("{r$SOURCE}: {r$n_with_enrollment}/{r$n_patients} ({r$pct_enrolled}%) enrolled, mean {round(r$mean_covered_days)} covered days, {r$n_with_gaps} with gaps"))
}

# 5f. Payer category distribution per partner
payer_by_partner <- payer_summary %>%
  filter(!is.na(PAYER_CATEGORY_PRIMARY)) %>%
  group_by(SOURCE, PAYER_CATEGORY_PRIMARY) %>%
  summarise(n = n(), .groups = "drop") %>%
  arrange(SOURCE, desc(n))

message("\n=== Payer Category Distribution by Partner ===")
for (src in unique(payer_by_partner$SOURCE)) {
  message(glue("\n{src}:"))
  subset <- payer_by_partner %>% filter(SOURCE == src)
  for (j in seq_len(nrow(subset))) {
    message(glue("  {subset$PAYER_CATEGORY_PRIMARY[j]}: {subset$n[j]}"))
  }
}

# ==============================================================================
# SECTION 6: VALIDATION SUMMARY
# ==============================================================================

message("\n=== Payer Harmonization Validation ===")
message(glue("Total patients: {nrow(payer_summary)}"))

category_counts <- payer_summary %>%
  count(PAYER_CATEGORY_PRIMARY, name = "n") %>%
  arrange(desc(n))

for (i in seq_len(nrow(category_counts))) {
  message(glue("  {category_counts$PAYER_CATEGORY_PRIMARY[i]}: {category_counts$n[i]}"))
}

n_dual <- sum(payer_summary$DUAL_ELIGIBLE == 1, na.rm = TRUE)
n_medicare <- sum(payer_summary$PAYER_CATEGORY_PRIMARY == "Medicare", na.rm = TRUE)
n_medicaid <- sum(payer_summary$PAYER_CATEGORY_PRIMARY == "Medicaid", na.rm = TRUE)
medicare_medicaid_total <- n_medicare + n_medicaid

message(glue("\nDual-eligible patients: {n_dual}"))
if (medicare_medicaid_total > 0) {
  dual_pct <- round(100 * n_dual / medicare_medicaid_total, 1)
  message(glue("Dual-eligible rate (% of Medicare+Medicaid): {dual_pct}%"))
  if (dual_pct < 10 | dual_pct > 20) {
    message(glue("WARNING: Dual-eligible rate ({dual_pct}%) outside expected 10-20% range"))
  } else {
    message(glue("Dual-eligible rate within expected 10-20% range"))
  }
} else {
  message("WARNING: No Medicare or Medicaid patients found -- cannot compute dual-eligible rate")
}

# ==============================================================================
# SECTION 7: CSV OUTPUT
# ==============================================================================

output_path <- file.path(CONFIG$output_dir, "tables", "payer_summary.csv")

# Create output directory if it doesn't exist
dir.create(file.path(CONFIG$output_dir, "tables"), showWarnings = FALSE, recursive = TRUE)

write_csv(payer_summary, output_path)
message(glue("\nPayer summary saved to: {output_path}"))
message(glue("Columns: {paste(names(payer_summary), collapse = ', ')}"))

message("\n", strrep("=", 60))
message("Payer harmonization complete")
message(strrep("=", 60))

# ==============================================================================
# End of script
# ==============================================================================
