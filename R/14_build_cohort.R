# ==============================================================================
# 14_build_cohort.R
# ==============================================================================
#
# Purpose:
#   Compose named predicates into sequential filter chain, add treatment flags,
#   calculate patient ages, and assemble the final HL cohort. This is the main
#   pipeline entry point that sources all cohort helpers and produces the cohort
#   used by all downstream analysis scripts.
#
# Inputs:
#   - PCORnet CDM tables via 01_load_pcornet.R: DEMOGRAPHIC, DIAGNOSIS, ENROLLMENT,
#     PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, ENCOUNTER, LAB_RESULT_CM,
#     PROVIDER, TUMOR_REGISTRY_ALL
#   - Payer summary via 02_harmonize_payer.R: patient-level AMC 8-category payer
#     assignments with PAYER_CATEGORY_PRIMARY, DUAL_ELIGIBLE flags
#
# Outputs:
#   - hl_cohort (in-memory tibble): Final filtered cohort with treatment flags,
#     demographics, payer info, surveillance modalities, survivorship encounters
#   - attrition_log (in-memory tibble): Step-by-step patient count through filter chain
#   - output/hl_cohort.rds: Cached cohort for downstream scripts
#   - output/cohort/hl_cohort.csv: CSV export for external analysis
#
# Dependencies:
#   - source("R/02_harmonize_payer.R"): Loads full upstream chain (config, data, payer)
#   - source("R/10_cohort_predicates.R"): Named filter functions (has_*, with_*, exclude_*)
#   - source("R/11_treatment_payer.R"): Treatment-anchored payer assignment
#   - source("R/12_surveillance.R"): Surveillance modality detection
#   - source("R/13_survivorship_encounters.R"): Survivorship encounter classification
#
# Requirements: CHRT-01, CHRT-02
#
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP AND DEPENDENCY LOADING ----
# ==============================================================================

source("R/02_harmonize_payer.R") # Loads 01_load_pcornet.R -> 00_config.R -> utils
source("R/10_cohort_predicates.R") # Named predicates + treatment flag functions

library(dplyr)
library(lubridate)
library(glue)
library(readr)

message("\n", strrep("=", 60))
message("HL Cohort Building Pipeline")
message(strrep("=", 60))

# ==============================================================================
# SECTION 2: SEQUENTIAL FILTER CHAIN ----
# ==============================================================================
#
# WHY predicates applied in this order: Enrollment filtering before diagnosis
# reduces join size (smaller patient set to check against DIAGNOSIS table).
# HL verification happens first to tag all patients with HL_SOURCE flag, then
# enrollment filtering removes patients without insurance records. This order
# preserves HL status information for excluded patients (written to CSV) while
# optimizing query performance.
#
# Python's encounter_payer_summary assumes all patients in the extract are HL
# and filters only by enrollment. We match that logic here but add an HL_VERIFIED
# flag so downstream analyses can filter if needed.

# Initialize attrition tracking (CHRT-02)
attrition_log <- init_attrition_log()

# Step 0: Initial population from DEMOGRAPHIC (one row per patient)
# Materialize immediately since we need n_distinct(), nrow(), saveRDS()
cohort <- get_pcornet_table("DEMOGRAPHIC") %>%
  select(ID, SOURCE, SEX, RACE, HISPANIC, BIRTH_DATE) %>%
  materialize()
attrition_log <- log_attrition(attrition_log, "Initial population", n_distinct(cohort$ID))

# Snapshot: Step 0 -- Initial population (per SNAP-01)
if (!dir.exists(CONFIG$cache$cohort_dir)) {
  dir.create(CONFIG$cache$cohort_dir, recursive = TRUE, showWarnings = FALSE)
  message("  Created snapshot directory: cohort/")
}
saveRDS(cohort, file.path(CONFIG$cache$cohort_dir, "cohort_00_initial_population.rds"), compress = TRUE)
message(glue("  Snapshot: cohort_00_initial_population.rds ({nrow(cohort)} rows, {ncol(cohort)} cols)"))

# Step 1: Build HL_SOURCE and HL_VERIFIED flag (but do NOT filter)
# Runs the same HL identification logic to tag patients, then retains all
# Translation gap workaround: inline ICD matching (same pattern as 03_cohort_predicates.R)
hl_icd10_undotted <- ICD_CODES$hl_icd10
hl_icd9_undotted <- ICD_CODES$hl_icd9

dx_hl <- get_pcornet_table("DIAGNOSIS") %>%
  filter(
    (DX_TYPE == "10" & (DX %in% hl_icd10_undotted | gsub("\\.", "", DX) %in% hl_icd10_undotted)) |
      (DX_TYPE == "09" & (DX %in% hl_icd9_undotted | gsub("\\.", "", DX) %in% hl_icd9_undotted))
  ) %>%
  distinct(ID) %>%
  mutate(has_dx = TRUE)

# TUMOR_REGISTRY: same pattern as 03_cohort_predicates.R
tr_all_tbl <- tryCatch(get_pcornet_table("TUMOR_REGISTRY_ALL"), error = function(e) NULL)
tr_all <- if (!is.null(tr_all_tbl)) {
  tr_cols <- colnames(tr_all_tbl)

  tr_hist <- if ("HISTOLOGICAL_TYPE" %in% tr_cols) {
    tr_all_tbl %>%
      filter(substr(as.character(HISTOLOGICAL_TYPE), 1, 4) %in% ICD_CODES$hl_histology) %>%
      distinct(ID)
  } else {
    tibble(ID = character())
  }

  tr_morph <- if ("MORPH" %in% tr_cols) {
    tr_all_tbl %>%
      filter(substr(as.character(MORPH), 1, 4) %in% ICD_CODES$hl_histology) %>%
      distinct(ID)
  } else {
    tibble(ID = character())
  }

  bind_rows(materialize(tr_hist), materialize(tr_morph)) %>% distinct(ID)
} else {
  tibble(ID = character())
}

# Build HL source map
hl_source_map <- cohort %>%
  select(ID) %>%
  distinct() %>%
  left_join(dx_hl, by = "ID") %>%
  left_join(
    tr_all %>% mutate(has_tr = TRUE),
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
    ),
    HL_VERIFIED = as.integer(HL_SOURCE != "Neither")
  ) %>%
  select(ID, HL_SOURCE, HL_VERIFIED)

# Log HL source breakdown
message("[Cohort] HL verification (flag only, no exclusion):")
source_counts <- hl_source_map %>% count(HL_SOURCE)
for (i in seq_len(nrow(source_counts))) {
  message(glue("  {source_counts$HL_SOURCE[i]}: {source_counts$n[i]}"))
}
n_unverified <- sum(hl_source_map$HL_VERIFIED == 0L)
message(glue("  HL_VERIFIED=0 (Neither): {n_unverified} patients retained with flag"))

# Join HL flag to cohort
cohort <- cohort %>%
  left_join(hl_source_map, by = "ID")

attrition_log <- log_attrition(attrition_log, "HL flag applied (all retained)", n_distinct(cohort$ID))

# Snapshot: Step 1 -- HL flag applied (per SNAP-01)
saveRDS(cohort, file.path(CONFIG$cache$cohort_dir, "cohort_01_hl_flag.rds"), compress = TRUE)
message(glue("  Snapshot: cohort_01_hl_flag.rds ({nrow(cohort)} rows, {ncol(cohort)} cols)"))

# Step 2: with_enrollment_period() (matches Python: enrolled patients only)
cohort <- cohort %>% with_enrollment_period()
attrition_log <- log_attrition(attrition_log, "Has enrollment record", n_distinct(cohort$ID))

# Snapshot: Step 2 -- Has enrollment record (per SNAP-01)
saveRDS(cohort, file.path(CONFIG$cache$cohort_dir, "cohort_02_has_enrollment.rds"), compress = TRUE)
message(glue("  Snapshot: cohort_02_has_enrollment.rds ({nrow(cohort)} rows, {ncol(cohort)} cols)"))

# ==============================================================================
# SECTION 3: TREATMENT FLAGS AND AGE CALCULATION ----
# ==============================================================================
#
# WHY treatment flags added after filtering: Computing treatment evidence for
# excluded patients wastes resources. Filter first to the final cohort, then
# add treatment flags only for included patients. This also ensures treatment
# flags align with the cohort that will be used in downstream analyses.
#
# WHY age calculated as current year minus birth year: PCORnet CDM does not
# provide precise date of birth (only birth year) due to HIPAA de-identification.
# Age at diagnosis uses lubridate::interval() for year-difference calculation
# between BIRTH_DATE and first_hl_dx_date, which handles leap years correctly.

message("\n--- Enrollment Aggregation ---")

# Get primary site enrollment only (D-13: primary site strategy)
enrollment_primary <- get_pcornet_table("ENROLLMENT") %>%
  inner_join(
    get_pcornet_table("DEMOGRAPHIC") %>% select(ID, SOURCE),
    by = c("ID", "SOURCE")
  )

# Aggregate enrollment dates per patient
# Safety net: re-check 1900 sentinels on derived dates where _VALID flags may not propagate
# Materialize after summarise since downstream uses interval() (R-side lubridate function)
enrollment_dates <- enrollment_primary %>%
  mutate(
    ENR_START_DATE = if_else(year(ENR_START_DATE) == 1900L, as.Date(NA), ENR_START_DATE),
    ENR_END_DATE   = if_else(year(ENR_END_DATE) == 1900L, as.Date(NA), ENR_END_DATE)
  ) %>%
  group_by(ID) %>%
  summarise(
    enr_start_date = min(ENR_START_DATE, na.rm = TRUE),
    enr_end_date = max(ENR_END_DATE, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    enrollment_duration_days = as.numeric(enr_end_date - enr_start_date)
  ) %>%
  materialize()

# Join enrollment dates and calculate ages (D-10)
# Materialize cohort before age calculation (lubridate::interval is R-side only)
cohort <- cohort %>%
  left_join(enrollment_dates, by = "ID") %>%
  materialize() %>%
  mutate(
    age_at_enr_start = as.integer(
      time_length(interval(BIRTH_DATE, enr_start_date), "years")
    ),
    age_at_enr_end = as.integer(
      time_length(interval(BIRTH_DATE, enr_end_date), "years")
    )
  )

message(glue("  Patients with enrollment dates: {sum(!is.na(cohort$enr_start_date))}"))
message(glue("  Median enrollment duration: {median(cohort$enrollment_duration_days, na.rm = TRUE)} days"))

# ==============================================================================
# SECTION 4: JOIN FIRST HL DIAGNOSIS DATE
# ==============================================================================

message("\n--- First HL Diagnosis Date ---")

cohort <- cohort %>%
  left_join(first_dx, by = "ID")

# Safety net: re-check 1900 sentinels on derived dates where _VALID flags may not propagate
# Nullify 1900 sentinel dates (SAS epoch) -- these are missing, not real diagnoses.
# Must happen HERE so all downstream code (survivorship encounters, payer windows,
# treatment timing, visualizations) automatically excludes these patients.
n_sentinel_dx <- sum(year(cohort$first_hl_dx_date) == 1900L, na.rm = TRUE)
if (n_sentinel_dx > 0) {
  message(glue("  Nullifying {n_sentinel_dx} sentinel diagnosis dates (year 1900)"))
  cohort <- cohort %>%
    mutate(first_hl_dx_date = if_else(year(first_hl_dx_date) == 1900L, as.Date(NA), first_hl_dx_date))
}

message(glue("  Patients with first_hl_dx_date: {sum(!is.na(cohort$first_hl_dx_date))}"))
message(glue("  Patients missing first_hl_dx_date: {sum(is.na(cohort$first_hl_dx_date))}"))

# ==============================================================================
# SECTION 5: JOIN PAYER SUMMARY FIELDS (D-09)
# ==============================================================================

message("\n--- Payer Summary ---")

cohort <- cohort %>%
  left_join(
    payer_summary %>%
      select(
        ID, PAYER_CATEGORY_PRIMARY, PAYER_CATEGORY_AT_FIRST_DX,
        DUAL_ELIGIBLE, PAYER_TRANSITION, N_ENCOUNTERS, N_ENCOUNTERS_WITH_PAYER
      ),
    by = "ID"
  )

n_missing_payer <- sum(is.na(cohort$PAYER_CATEGORY_PRIMARY))
if (n_missing_payer > 0) {
  message(glue("  WARNING: {n_missing_payer} patients missing PAYER_CATEGORY_PRIMARY after join"))
} else {
  message("  All patients have PAYER_CATEGORY_PRIMARY assigned")
}

# ==============================================================================
# SECTION 6: TREATMENT FLAGS (D-02, D-05, D-06)
# ==============================================================================

message("\n--- Treatment Flags ---")

# Get treatment evidence (D-05: multi-source, D-06: integer 0/1)
chemo_flags <- has_chemo()
rad_flags <- has_radiation()
sct_flags <- has_sct()

# Join treatment flags to cohort (D-02: flags only, not exclusion)
cohort <- cohort %>%
  left_join(chemo_flags, by = "ID") %>%
  left_join(rad_flags, by = "ID") %>%
  left_join(sct_flags, by = "ID") %>%
  mutate(
    HAD_CHEMO = coalesce(HAD_CHEMO, 0L),
    HAD_RADIATION = coalesce(HAD_RADIATION, 0L),
    HAD_SCT = coalesce(HAD_SCT, 0L)
  )

message(glue("  HAD_CHEMO = 1: {sum(cohort$HAD_CHEMO == 1)} patients ({round(100 * mean(cohort$HAD_CHEMO), 1)}%)"))
message(glue("  HAD_RADIATION = 1: {sum(cohort$HAD_RADIATION == 1)} patients ({round(100 * mean(cohort$HAD_RADIATION), 1)}%)"))
message(glue("  HAD_SCT = 1: {sum(cohort$HAD_SCT == 1)} patients ({round(100 * mean(cohort$HAD_SCT), 1)}%)"))

# ==============================================================================
# SECTION 6.5: TREATMENT-ANCHORED PAYER MODE (D-08, D-09, D-10)
# ==============================================================================

message("\n--- Treatment-Anchored Payer Mode ---")
source("R/11_treatment_payer.R")

# Compute payer mode at first treatment for each type
chemo_payer <- compute_payer_at_chemo()
rad_payer <- compute_payer_at_radiation()
sct_payer <- compute_payer_at_sct()

# Join to cohort (D-08: add directly to hl_cohort; D-11: NA for no-match via left_join)
cohort <- cohort %>%
  left_join(chemo_payer, by = "ID") %>%
  left_join(rad_payer, by = "ID") %>%
  left_join(sct_payer, by = "ID")

# ==============================================================================
# SECTION 6.6: TIMING DERIVATION (D-12)
# ==============================================================================

message("\n--- Timing Derivation ---")

cohort <- cohort %>%
  mutate(
    DAYS_DX_TO_CHEMO     = suppressWarnings(as.integer(FIRST_CHEMO_DATE - first_hl_dx_date)),
    DAYS_DX_TO_RADIATION = suppressWarnings(as.integer(FIRST_RADIATION_DATE - first_hl_dx_date)),
    DAYS_DX_TO_SCT       = suppressWarnings(as.integer(FIRST_SCT_DATE - first_hl_dx_date))
  )

# Validate treatment timing: log and nullify negative values (treatment before diagnosis is data error)
for (tx_col in c("DAYS_DX_TO_CHEMO", "DAYS_DX_TO_RADIATION", "DAYS_DX_TO_SCT")) {
  vals <- cohort[[tx_col]]
  n_negative <- sum(vals < 0, na.rm = TRUE)
  if (n_negative > 0) {
    message(glue("  WARNING: {n_negative} patients have negative {tx_col} (treatment before diagnosis), min = {min(vals, na.rm = TRUE)} days — setting to NA"))
  }
}

# Set negative timing values to NA (treatment-before-diagnosis indicates data error)
cohort <- cohort %>%
  mutate(
    DAYS_DX_TO_CHEMO     = if_else(DAYS_DX_TO_CHEMO < 0L, NA_integer_, DAYS_DX_TO_CHEMO),
    DAYS_DX_TO_RADIATION = if_else(DAYS_DX_TO_RADIATION < 0L, NA_integer_, DAYS_DX_TO_RADIATION),
    DAYS_DX_TO_SCT       = if_else(DAYS_DX_TO_SCT < 0L, NA_integer_, DAYS_DX_TO_SCT)
  )

message(glue("  DAYS_DX_TO_CHEMO: median {median(cohort$DAYS_DX_TO_CHEMO, na.rm = TRUE)} days (N={sum(!is.na(cohort$DAYS_DX_TO_CHEMO))})"))
message(glue("  DAYS_DX_TO_RADIATION: median {median(cohort$DAYS_DX_TO_RADIATION, na.rm = TRUE)} days (N={sum(!is.na(cohort$DAYS_DX_TO_RADIATION))})"))
message(glue("  DAYS_DX_TO_SCT: median {median(cohort$DAYS_DX_TO_SCT, na.rm = TRUE)} days (N={sum(!is.na(cohort$DAYS_DX_TO_SCT))})"))

# ==============================================================================
# SECTION 6.65: AGE AT DX, AGE GROUP, DX YEAR, POST-TX ENCOUNTER FLAG
# ==============================================================================

message("\n--- Age & DX Year Derivation ---")

cohort <- cohort %>%
  mutate(
    # first_hl_dx_date is already NA for 1900 sentinels (nullified in Section 4)
    age_at_dx_raw = as.integer(time_length(interval(BIRTH_DATE, first_hl_dx_date), "years")),
    # Validate: set impossible ages to NA (negatives = date error, >120 = sentinel/error)
    age_at_dx = if_else(
      !is.na(age_at_dx_raw) & age_at_dx_raw >= 0L & age_at_dx_raw <= 120L,
      age_at_dx_raw,
      NA_integer_
    ),
    # Also validate enrollment ages
    age_at_enr_start = if_else(
      !is.na(age_at_enr_start) & age_at_enr_start >= 0L & age_at_enr_start <= 120L,
      age_at_enr_start,
      NA_integer_
    ),
    age_at_enr_end = if_else(
      !is.na(age_at_enr_end) & age_at_enr_end >= 0L & age_at_enr_end <= 120L,
      age_at_enr_end,
      NA_integer_
    ),
    AGE_GROUP = case_when(
      age_at_dx >= 0 & age_at_dx <= 17 ~ "0-17",
      age_at_dx >= 18 & age_at_dx <= 39 ~ "18-39",
      age_at_dx >= 40 & age_at_dx <= 64 ~ "40-64",
      age_at_dx >= 65 ~ "65+",
      TRUE ~ NA_character_
    ),
    DX_YEAR = year(first_hl_dx_date)
  )

# Log invalid ages that were set to NA
n_invalid_age <- sum(!is.na(cohort$age_at_dx_raw) & is.na(cohort$age_at_dx))
if (n_invalid_age > 0) {
  invalid_range <- cohort %>% filter(!is.na(age_at_dx_raw) & is.na(cohort$age_at_dx))
  message(glue("  WARNING: {n_invalid_age} patients had impossible age_at_dx (outside 0-120) set to NA"))
  message(glue("  Invalid age values: [{min(invalid_range$age_at_dx_raw)}, {max(invalid_range$age_at_dx_raw)}]"))
}

# Drop raw column
cohort <- cohort %>% select(-age_at_dx_raw)

message(glue("  Age at diagnosis: median {median(cohort$age_at_dx, na.rm = TRUE)}, range [{min(cohort$age_at_dx, na.rm = TRUE)}, {max(cohort$age_at_dx, na.rm = TRUE)}]"))
age_grp_dist <- cohort %>%
  filter(!is.na(AGE_GROUP)) %>%
  count(AGE_GROUP)
for (i in seq_len(nrow(age_grp_dist))) {
  message(glue("  {age_grp_dist$AGE_GROUP[i]}: {age_grp_dist$n[i]}"))
}

# ==============================================================================
# SECTION 6.7: SURVEILLANCE MODALITY FLAGS (D-01, D-02, D-03, D-04)
# ==============================================================================

message("\n--- Surveillance Modality Detection ---")
source("R/12_surveillance.R")

post_dx_date_map <- cohort %>% select(ID, first_hl_dx_date)
surveillance_flags <- assemble_surveillance_flags(post_dx_date_map)

cohort <- cohort %>%
  left_join(surveillance_flags, by = "ID")

# ==============================================================================
# SECTION 6.8: SURVIVORSHIP ENCOUNTER CLASSIFICATION (D-05 through D-10)
# ==============================================================================

message("\n--- Survivorship Encounter Classification ---")
source("R/13_survivorship_encounters.R")

survivorship_flags <- classify_survivorship_encounters(post_dx_date_map)

cohort <- cohort %>%
  left_join(survivorship_flags, by = "ID")

# Post-treatment encounter flag: Yes/No based on encounters after last treatment date
# Requires treatment evidence (chemo, radiation, or SCT); NA for untreated patients
message("\n--- Post-Treatment Encounter Flag ---")
last_tx_for_cohort <- compute_last_any_treatment_date()

# Identify patients with any encounter after their last treatment date
post_tx_encounter_ids <- encounters %>%
  inner_join(last_tx_for_cohort, by = "ID") %>%
  filter(!is.na(ADMIT_DATE), ADMIT_DATE > LAST_ANY_TX_DATE) %>%
  distinct(ID) %>%
  pull(ID)

cohort <- cohort %>%
  left_join(last_tx_for_cohort, by = "ID") %>%
  mutate(
    HAS_POST_TX_ENCOUNTERS = case_when(
      is.na(LAST_ANY_TX_DATE) ~ NA_character_, # No treatment = not applicable
      ID %in% post_tx_encounter_ids ~ "Yes", # Has encounters after last tx
      TRUE ~ "No" # Treatment but no post-tx encounters
    )
  )

n_treated <- sum(!is.na(cohort$LAST_ANY_TX_DATE))
message(glue("\n  Post-treatment encounters (among {n_treated} treated): {sum(cohort$HAS_POST_TX_ENCOUNTERS == 'Yes', na.rm = TRUE)} Yes, {sum(cohort$HAS_POST_TX_ENCOUNTERS == 'No', na.rm = TRUE)} No, {sum(is.na(cohort$HAS_POST_TX_ENCOUNTERS))} N/A (untreated)"))

# ==============================================================================
# SECTION 4: COHORT ASSEMBLY AND CACHE ----
# ==============================================================================
#
# WHY attrition log tracks unique patient IDs not row counts: Some predicates
# filter at the patient level (one row per patient), while others work with
# encounter-level data (multiple rows per patient). Tracking n_distinct(ID)
# ensures consistent patient-level attrition reporting regardless of data
# structure at each step.

message("\n--- Final Cohort Assembly ---")

hl_cohort <- cohort %>%
  select(
    ID,
    SOURCE,
    HL_SOURCE,
    HL_VERIFIED,
    SEX,
    RACE,
    HISPANIC,
    age_at_enr_start,
    age_at_enr_end,
    age_at_dx,
    AGE_GROUP,
    first_hl_dx_date,
    DX_YEAR,
    PAYER_CATEGORY_PRIMARY,
    PAYER_CATEGORY_AT_FIRST_DX,
    DUAL_ELIGIBLE,
    PAYER_TRANSITION,
    N_ENCOUNTERS,
    N_ENCOUNTERS_WITH_PAYER,
    HAD_CHEMO,
    HAD_RADIATION,
    HAD_SCT,
    FIRST_CHEMO_DATE,
    FIRST_RADIATION_DATE,
    FIRST_SCT_DATE,
    PAYER_AT_CHEMO,
    PAYER_AT_RADIATION,
    PAYER_AT_SCT,
    LAST_ANY_TX_DATE,
    enrollment_duration_days,
    # Timing derivation (D-12)
    DAYS_DX_TO_CHEMO,
    DAYS_DX_TO_RADIATION,
    DAYS_DX_TO_SCT,
    # Surveillance modality flags (D-01 through D-04)
    matches("^(HAD|FIRST|N)_(MAMMOGRAM|BREAST_MRI|ECHO|STRESS_TEST|ECG|MUGA|PFT|TSH|CBC|CRP|ALT|AST|ALP|GGT|BILIRUBIN|PLATELETS|FOBT)"),
    # Survivorship encounter flags (D-05 through D-10)
    starts_with("HAD_ENC_"),
    starts_with("N_ENC_"),
    starts_with("FIRST_ENC_"),
    HAS_POST_TX_ENCOUNTERS
  )

# Snapshot: Final cohort (per SNAP-02)
saveRDS(hl_cohort, file.path(CONFIG$cache$cohort_dir, "cohort_final.rds"), compress = TRUE)
message(glue("  Snapshot: cohort_final.rds ({nrow(hl_cohort)} rows, {ncol(hl_cohort)} cols)"))

# ==============================================================================
# SECTION 5: ATTRITION SUMMARY ----
# ==============================================================================

message("\n", strrep("=", 60))
message("HL COHORT SUMMARY")
message(strrep("=", 60))

message(glue("\nTotal patients: {nrow(hl_cohort)}"))
message(glue("  HL_VERIFIED=1: {sum(hl_cohort$HL_VERIFIED == 1)} | HL_VERIFIED=0: {sum(hl_cohort$HL_VERIFIED == 0)}"))

message("\n--- Payer Distribution ---")
payer_dist <- hl_cohort %>%
  count(PAYER_CATEGORY_PRIMARY, name = "n") %>%
  arrange(desc(n))
for (i in seq_len(nrow(payer_dist))) {
  message(glue("  {payer_dist$PAYER_CATEGORY_PRIMARY[i]}: {payer_dist$n[i]}"))
}

message("\n--- Treatment Flags ---")
message(glue("  Chemotherapy: {sum(hl_cohort$HAD_CHEMO == 1)} ({round(100 * mean(hl_cohort$HAD_CHEMO), 1)}%)"))
message(glue("  Radiation: {sum(hl_cohort$HAD_RADIATION == 1)} ({round(100 * mean(hl_cohort$HAD_RADIATION), 1)}%)"))
message(glue("  SCT: {sum(hl_cohort$HAD_SCT == 1)} ({round(100 * mean(hl_cohort$HAD_SCT), 1)}%)"))

message("\n--- Treatment-Anchored Payer ---")
message(glue("  PAYER_AT_CHEMO: {sum(!is.na(hl_cohort$PAYER_AT_CHEMO))} assigned, {sum(is.na(hl_cohort$PAYER_AT_CHEMO))} NA"))
message(glue("  PAYER_AT_RADIATION: {sum(!is.na(hl_cohort$PAYER_AT_RADIATION))} assigned, {sum(is.na(hl_cohort$PAYER_AT_RADIATION))} NA"))
message(glue("  PAYER_AT_SCT: {sum(!is.na(hl_cohort$PAYER_AT_SCT))} assigned, {sum(is.na(hl_cohort$PAYER_AT_SCT))} NA"))

message("\n--- Demographics ---")
message(glue("  Age at enrollment start: median {median(hl_cohort$age_at_enr_start, na.rm = TRUE)}, range [{min(hl_cohort$age_at_enr_start, na.rm = TRUE)}, {max(hl_cohort$age_at_enr_start, na.rm = TRUE)}]"))
message(glue("  Enrollment duration: median {median(hl_cohort$enrollment_duration_days, na.rm = TRUE)} days"))

message("\n--- Sites ---")
site_dist <- hl_cohort %>%
  count(SOURCE, name = "n") %>%
  arrange(desc(n))
for (i in seq_len(nrow(site_dist))) {
  message(glue("  {site_dist$SOURCE[i]}: {site_dist$n[i]}"))
}

message("\n--- Surveillance Modalities ---")
surv_modalities <- c("MAMMOGRAM", "BREAST_MRI", "ECHO", "STRESS_TEST", "ECG", "MUGA", "PFT", "TSH", "CBC")
for (mod in surv_modalities) {
  had_col <- paste0("HAD_", mod)
  if (had_col %in% names(hl_cohort)) {
    n <- sum(hl_cohort[[had_col]] == 1, na.rm = TRUE)
    message(glue("  {mod}: {n} patients ({round(100*n/nrow(hl_cohort), 1)}%)"))
  }
}

message("\n--- Lab Results ---")
lab_types <- c("CRP", "ALT", "AST", "ALP", "GGT", "BILIRUBIN", "PLATELETS", "FOBT")
for (lab in lab_types) {
  had_col <- paste0("HAD_", lab)
  if (had_col %in% names(hl_cohort)) {
    n <- sum(hl_cohort[[had_col]] == 1, na.rm = TRUE)
    message(glue("  {lab}: {n} patients ({round(100*n/nrow(hl_cohort), 1)}%)"))
  }
}

message("\n--- Survivorship Encounters ---")
message(glue("  Non-acute care (L1): {sum(hl_cohort$HAD_ENC_NONACUTE_CARE == 1, na.rm = TRUE)} patients"))
message(glue("  Cancer-related (L2): {sum(hl_cohort$HAD_ENC_CANCER_RELATED == 1, na.rm = TRUE)} patients"))
message(glue("  Cancer provider (L3): {sum(hl_cohort$HAD_ENC_CANCER_PROVIDER == 1, na.rm = TRUE)} patients"))
message(glue("  Survivorship (L4): {sum(hl_cohort$HAD_ENC_SURVIVORSHIP == 1, na.rm = TRUE)} patients"))

message("\n--- Timing ---")
message(glue("  DAYS_DX_TO_CHEMO: median {median(hl_cohort$DAYS_DX_TO_CHEMO, na.rm = TRUE)} days"))
message(glue("  DAYS_DX_TO_RADIATION: median {median(hl_cohort$DAYS_DX_TO_RADIATION, na.rm = TRUE)} days"))
message(glue("  DAYS_DX_TO_SCT: median {median(hl_cohort$DAYS_DX_TO_SCT, na.rm = TRUE)} days"))

# ==============================================================================
# SECTION 9: ATTRITION SUMMARY (CHRT-02)
# ==============================================================================

message("\n--- Attrition Log ---")
print(attrition_log)

# Snapshot: Attrition log (per SNAP-02)
saveRDS(attrition_log, file.path(CONFIG$cache$cohort_dir, "attrition_log.rds"), compress = TRUE)
message(glue("  Snapshot: attrition_log.rds ({nrow(attrition_log)} rows, {ncol(attrition_log)} cols)"))

# Create output directory
dir.create(file.path(CONFIG$output_dir, "cohort"), showWarnings = FALSE, recursive = TRUE)

output_path <- file.path(CONFIG$output_dir, "cohort", "hl_cohort.csv")
write_csv(hl_cohort, output_path)
message(glue("\nCohort saved to: {output_path}"))
message(glue("Rows: {nrow(hl_cohort)}, Columns: {ncol(hl_cohort)}"))
message(glue("Columns: {paste(names(hl_cohort), collapse = ', ')}"))

message("\n", strrep("=", 60))
message("Cohort building complete")
message(strrep("=", 60))

# ==============================================================================
# End of 04_build_cohort.R
# ==============================================================================
