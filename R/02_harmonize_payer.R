# ==============================================================================
# 02_harmonize_payer.R -- AMC 8-category payer harmonization from raw PAYER_TYPE codes
# ==============================================================================
#
# Purpose:
#   Harmonizes raw PAYER_TYPE_PRIMARY and PAYER_TYPE_SECONDARY codes from ENROLLMENT
#   table into standardized AMC 8 categories (Medicaid, Medicare, Private, Other govt,
#   Other, Self-pay, Uninsured, Missing). Produces patient-level payer summary with
#   mode payer category, dual-eligible flags, and enrollment completeness metrics.
#   The payer_summary tibble is the foundation for all downstream payer analyses.
#
# Inputs:
#   - pcornet$ENROLLMENT: PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY, ENR_START_DATE, ENR_END_DATE, SOURCE, ID
#   - pcornet$DIAGNOSIS: DX, DX_DATE, ID (for first HL diagnosis date calculation)
#   - PAYER_MAPPING$categories, AMC_PAYER_LOOKUP (from R/00_config.R)
#
# Outputs:
#   - payer_summary: Tibble with patient-level payer mode, dual-eligible flag, enrollment metrics
#   - output/tables/payer_summary.csv: Patient-level payer summary CSV export
#   - Console output: Enrollment completeness by partner, payer distribution table, validation summary
#
# Dependencies:
#   - source("R/01_load_pcornet.R"): Loads pcornet$ENROLLMENT, pcornet$DIAGNOSIS
#   - utils/utils_payer.R: is_missing_payer() (auto-sourced by 00_config)
#   - dplyr, lubridate, stringr, glue (tidyverse ecosystem)
#
# Requirements: PAYR-01 (harmonize payer), PAYR-02 (dual-eligible), PAYR-03 (enrollment completeness)
#
# ==============================================================================

source("R/01_load_pcornet.R") # Loads data and config (auto-sources utils)

library(dplyr)
library(stringr)
library(lubridate)
library(glue)
library(readr)

message("\n", strrep("=", 60))
message("Payer Harmonization Pipeline")
message(strrep("=", 60))

# ==============================================================================
# SECTION 0: INPUT VALIDATION ----
# ==============================================================================

# SAFE-02: Validate critical input tables exist and have required columns
# Guard: ENCOUNTER table is required for payer harmonization (checked later in script)
# Validate ENROLLMENT immediately since it's the primary data source

# Validate ENCOUNTER table has payer columns (PAYER_TYPE_PRIMARY lives in ENCOUNTER, not ENROLLMENT)
encounter_check_tbl <- tryCatch(get_pcornet_table("ENCOUNTER"), error = function(e) NULL)
if (!is.null(encounter_check_tbl)) {
  encounter_check <- encounter_check_tbl %>% materialize()
  assert_df_valid(
    encounter_check,
    "ENCOUNTER",
    required_cols = c("ID", "PAYER_TYPE_PRIMARY", "ADMIT_DATE"),
    script_name = "R/02"
  )
  assert_col_types(
    encounter_check,
    type_spec = list(ID = "character", PAYER_TYPE_PRIMARY = "character"),
    script_name = "R/02"
  )
  rm(encounter_check, encounter_check_tbl)
}

# ==============================================================================
# SECTION 1: NAMED PAYER FUNCTIONS ----
# ==============================================================================

#' Compute effective payer per encounter
#'
#' Returns primary if valid, else secondary if valid, else NA.
#' Sentinel values (NI, UN, OT) trigger fallback to secondary.
#'
#' @param primary Character vector of PAYER_TYPE_PRIMARY values
#' @param secondary Character vector of PAYER_TYPE_SECONDARY values
#' @return Character vector of effective payer codes
#'
compute_effective_payer <- function(primary, secondary) {
  sentinel_values <- PAYER_MAPPING$sentinel_values # c("NI", "UN", "OT")

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

#' Detect dual-eligible encounters (informational flag only)
#'
#' Returns 1 if encounter is dual-eligible, 0 otherwise.
#' NOTE: This flag is informational only under the AMC 8-category system.
#' It does NOT override the payer category (code 14 maps to Medicaid directly).
#'
#' @param primary Character vector of PAYER_TYPE_PRIMARY values
#' @param secondary Character vector of PAYER_TYPE_SECONDARY values
#' @return Integer vector (0 or 1) indicating dual-eligible status
#'
detect_dual_eligible <- function(primary, secondary) {
  dual_codes <- PAYER_MAPPING$dual_eligible_codes # c("14", "141", "142")

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

#' Map effective payer to AMC 8-category system
#'
#' Uses AMC_PAYER_LOOKUP direct code-to-category table (from
#' payer_primary_codes_frequency_AMC.xlsx). Falls back to prefix-based rules
#' for codes not in the lookup. NA effective payer maps to "Missing".
#'
#' @param effective_payer Character vector of effective payer codes
#' @return Character vector of payer categories (8 levels)
#'
map_payer_category <- function(effective_payer) {
  # Direct lookup from AMC table
  looked_up <- AMC_PAYER_LOOKUP[effective_payer]

  # Prefix-based fallback for codes not in AMC_PAYER_LOOKUP
  prefix_category <- case_when(
    str_starts(effective_payer, "1") ~ "Medicare",
    str_starts(effective_payer, "2") ~ "Medicaid",
    str_starts(effective_payer, "5") | str_starts(effective_payer, "6") ~ "Private",
    str_starts(effective_payer, "3") | str_starts(effective_payer, "4") ~ "Other govt",
    str_starts(effective_payer, "7") ~ "Private",
    str_starts(effective_payer, "8") ~ "Uninsured",
    str_starts(effective_payer, "9") ~ "Other",
    TRUE ~ "Other"
  )

  # Use lookup result if found, else prefix fallback, else Missing for NA
  result <- if_else(!is.na(looked_up), looked_up, prefix_category)
  result <- if_else(is.na(effective_payer), "Missing", result)
  result
}

# ==============================================================================
# SECTION 2: ENCOUNTER-LEVEL PROCESSING ----
# ==============================================================================
# WHY encounter-level first: Each enrollment record represents a time window with
# a payer assignment. Processing at encounter level captures payer changes over time,
# then patient-level summary aggregates to mode payer (most common category per patient).

# Guard: ENCOUNTER table is required for payer harmonization
enc_tbl <- tryCatch(get_pcornet_table("ENCOUNTER"), error = function(e) NULL)
if (is.null(enc_tbl)) {
  stop("[Harmonize] ENCOUNTER table is NULL. ENCOUNTER table is required for payer harmonization. Ensure ENCOUNTER.csv is present.")
}

# Check if PAYER_TYPE_SECONDARY column exists (Pitfall 3)
enc_cols <- colnames(enc_tbl)
if (!"PAYER_TYPE_SECONDARY" %in% enc_cols) {
  message("WARNING: PAYER_TYPE_SECONDARY not found in ENCOUNTER table. Setting all dual_eligible = 0")
  # For DuckDB mode, add column via mutate (cannot assign directly to tbl_dbi)
  encounters_raw <- enc_tbl %>%
    mutate(PAYER_TYPE_SECONDARY = NA_character_)
} else {
  encounters_raw <- enc_tbl
}

# Process all encounters
# Materialize BEFORE custom R functions — DuckDB can't translate these to SQL
encounters <- encounters_raw %>%
  materialize() %>%
  mutate(
    effective_payer = compute_effective_payer(PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY),
    dual_eligible_encounter = detect_dual_eligible(PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY),
    payer_category = map_payer_category(effective_payer)
  )

# Safety net: re-check 1900 sentinels on derived dates where _VALID flags may not propagate
# Filter 1900 sentinel dates from encounters (SAS/Excel epoch sentinels)
n_sentinel_enc <- sum(year(encounters$ADMIT_DATE) == 1900L, na.rm = TRUE)
if (n_sentinel_enc > 0) {
  message(glue("  Filtering {n_sentinel_enc} encounters with 1900 sentinel ADMIT_DATE"))
  encounters <- encounters %>%
    filter(is.na(ADMIT_DATE) | year(ADMIT_DATE) != 1900L)
}

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
# SECTION 3: FIRST HL DIAGNOSIS DATE ----
# ==============================================================================
# WHY first HL diagnosis date: Used for temporal payer analysis (payer at diagnosis,
# payer changes post-diagnosis). Calculated here to avoid recomputing in every downstream script.

# Get earliest HL diagnosis from DIAGNOSIS table
# Translation gap workaround: replace is_hl_diagnosis() with inline %in% matching
hl_icd10_codes <- unique(c(ICD_CODES$hl_icd10, gsub("\\.", "", ICD_CODES$hl_icd10)))
hl_icd9_codes  <- unique(c(ICD_CODES$hl_icd9,  gsub("\\.", "", ICD_CODES$hl_icd9)))

dx_dates <- get_pcornet_table("DIAGNOSIS") %>%
  filter(
    (DX_TYPE == "10" & DX %in% hl_icd10_codes) |
      (DX_TYPE == "09" & DX %in% hl_icd9_codes)
  ) %>%
  group_by(ID) %>%
  summarise(first_dx_date_diagnosis = min_or_na(DX_DATE), .groups = "drop") %>%
  collect()

# Get earliest from TUMOR_REGISTRY_ALL (consolidated in 01_load_pcornet.R)
tr_tbl <- tryCatch(get_pcornet_table("TUMOR_REGISTRY_ALL"), error = function(e) NULL)
if (!is.null(tr_tbl) &&
  "DATE_OF_DIAGNOSIS" %in% colnames(tr_tbl)) {
  tr_dates <- tr_tbl %>%
    filter(!is.na(DATE_OF_DIAGNOSIS)) %>%
    group_by(ID) %>%
    summarise(first_dx_date_tr = min_or_na(DATE_OF_DIAGNOSIS), .groups = "drop") %>%
    collect()
} else {
  tr_dates <- data.frame(ID = character(), first_dx_date_tr = as.Date(character()), stringsAsFactors = FALSE)
}

# Combine: prefer tumor registry date; fall back to diagnosis table if no TR data
first_dx <- dx_dates %>%
  full_join(tr_dates, by = "ID") %>%
  mutate(first_hl_dx_date = if_else(!is.na(first_dx_date_tr),
    first_dx_date_tr,
    first_dx_date_diagnosis
  )) %>%
  select(ID, first_hl_dx_date) %>%
  collect()

# Nullify 1900 sentinel dates at the source (SAS/Excel epoch sentinels)
# These are missing dates, not real diagnoses -- must be NA before any downstream use
n_sentinel_first_dx <- sum(year(first_dx$first_hl_dx_date) == 1900L, na.rm = TRUE)
if (n_sentinel_first_dx > 0) {
  message(glue("  Nullifying {n_sentinel_first_dx} sentinel first-diagnosis dates (year 1900)"))
  first_dx <- first_dx %>%
    mutate(first_hl_dx_date = if_else(year(first_hl_dx_date) == 1900L, as.Date(NA), first_hl_dx_date))
}

message(glue("\nFirst HL diagnosis:"))
message(glue("  Patients with HL diagnosis found: {format(nrow(first_dx), big.mark=',')}"))

# ==============================================================================
# SECTION 4: PATIENT-LEVEL SUMMARY ----
# ==============================================================================
# WHY mode payer: Patients can have multiple enrollment periods with different
# payers. Mode (most frequent category) provides a single patient-level payer
# assignment for stratified analyses while preserving encounter-level variation
# in the enrollment table.

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
dx_window <- CONFIG$analysis$dx_window_days # 30

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
patient_source <- get_pcornet_table("DEMOGRAPHIC") %>%
  select(ID, SOURCE) %>%
  distinct() %>%
  collect()

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

# SAFE-02: Validate payer_summary output
assert_df_valid(
  payer_summary,
  "payer_summary",
  required_cols = c("ID", "PAYER_CATEGORY_PRIMARY"),
  script_name = "R/02"
)
assert_col_types(
  payer_summary,
  type_spec = list(ID = "character"),
  script_name = "R/02"
)

message(glue("\nPatient-level summary:"))
message(glue("  Total patients in payer_summary: {format(nrow(payer_summary), big.mark=',')}"))

# ==============================================================================
# SECTION 5: ENROLLMENT COMPLETENESS REPORT ----
# ==============================================================================
# Requirement PAYR-03: Per-partner enrollment completeness metrics

# 5a. Total patients per partner
patients_per_partner <- get_pcornet_table("DEMOGRAPHIC") %>%
  group_by(SOURCE) %>%
  summarise(n_patients = n_distinct(ID), .groups = "drop") %>%
  collect()

# 5b. Patients with enrollment per partner
patients_with_enrollment <- get_pcornet_table("ENROLLMENT") %>%
  group_by(SOURCE) %>%
  summarise(n_with_enrollment = n_distinct(ID), .groups = "drop") %>%
  collect()

# 5c. Mean covered days per partner
covered_days <- get_pcornet_table("ENROLLMENT") %>%
  filter(!is.na(ENR_START_DATE) & !is.na(ENR_END_DATE)) %>%
  mutate(period_days = as.numeric(ENR_END_DATE - ENR_START_DATE)) %>%
  group_by(SOURCE, ID) %>%
  summarise(total_covered_days = sum(period_days, na.rm = TRUE), .groups = "drop") %>%
  group_by(SOURCE) %>%
  summarise(mean_covered_days = mean(total_covered_days, na.rm = TRUE), .groups = "drop") %>%
  collect()

# 5d. Gap detection (gap = >30 days between consecutive enrollment periods)
enrollment_gaps <- get_pcornet_table("ENROLLMENT") %>%
  filter(!is.na(ENR_START_DATE) & !is.na(ENR_END_DATE)) %>%
  collect() %>%
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
# SECTION 6: VALIDATION SUMMARY ----
# ==============================================================================

message("\n=== Payer Harmonization Validation (AMC 8-category) ===")
message(glue("Total patients: {nrow(payer_summary)}"))

category_counts <- payer_summary %>%
  count(PAYER_CATEGORY_PRIMARY, name = "n") %>%
  arrange(desc(n))

for (i in seq_len(nrow(category_counts))) {
  message(glue("  {category_counts$PAYER_CATEGORY_PRIMARY[i]}: {category_counts$n[i]}"))
}

n_dual <- sum(payer_summary$DUAL_ELIGIBLE == 1, na.rm = TRUE)
message(glue("\nDual-eligible patients (informational flag): {n_dual}"))
message("NOTE: Dual-eligible is an informational flag only; category is determined by AMC lookup")

# ==============================================================================
# SECTION 7: CSV OUTPUT ----
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
