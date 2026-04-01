# ==============================================================================
# 04_build_cohort.R -- Build HL cohort with attrition logging
# ==============================================================================
#
# Composes named filter predicates into a sequential filter chain, adds treatment
# flags, calculates ages, and assembles the final patient-level HL cohort dataset.
#
# Requirements: CHRT-01 (named predicates), CHRT-02 (attrition logging), CHRT-03 (ICD matching)
#
# Filter chain order (per D-01):
#   1. has_hodgkin_diagnosis() -- identify HL patients from DIAGNOSIS table
#   2. with_enrollment_period() -- require at least one enrollment record
#   3. exclude_missing_payer() -- remove NA/Unknown/Unavailable payer categories
#   4. Tag treatment flags (HAD_CHEMO, HAD_RADIATION, HAD_SCT) -- identification only, not exclusion
#
# Output:
#   - hl_cohort tibble in R environment
#   - output/cohort/hl_cohort.csv
#   - attrition_log data frame in R environment (consumed by Phase 4 waterfall)
#
# Usage:
#   source("R/04_build_cohort.R")
#
# ==============================================================================

source("R/02_harmonize_payer.R")  # Loads 01_load_pcornet.R -> 00_config.R -> utils
source("R/03_cohort_predicates.R")  # Named predicates + treatment flag functions

library(dplyr)
library(lubridate)
library(glue)
library(readr)

message("\n", strrep("=", 60))
message("HL Cohort Building Pipeline")
message(strrep("=", 60))

# ==============================================================================
# SECTION 2: COHORT SELECTION (matches Python pipeline logic)
# ==============================================================================
#
# Python's encounter_payer_summary assumes all patients in the extract are HL
# and filters only by enrollment. We match that logic here but add an HL_VERIFIED
# flag so downstream analyses can filter if needed.

# Initialize attrition tracking (CHRT-02)
attrition_log <- init_attrition_log()

# Step 0: Initial population from DEMOGRAPHIC (one row per patient)
cohort <- pcornet$DEMOGRAPHIC %>%
  select(ID, SOURCE, SEX, RACE, HISPANIC, BIRTH_DATE)
attrition_log <- log_attrition(attrition_log, "Initial population", n_distinct(cohort$ID))

# Step 1: Build HL_SOURCE and HL_VERIFIED flag (but do NOT filter)
# Runs the same HL identification logic to tag patients, then retains all
hl_source_map <- cohort %>%
  select(ID) %>%
  distinct() %>%
  left_join(
    pcornet$DIAGNOSIS %>%
      filter(is_hl_diagnosis(DX, DX_TYPE)) %>%
      distinct(ID) %>%
      mutate(has_dx = TRUE),
    by = "ID"
  ) %>%
  left_join(
    {
      tr_all <- bind_rows(
        if (!is.null(pcornet$TUMOR_REGISTRY1) && "HISTOLOGICAL_TYPE" %in% names(pcornet$TUMOR_REGISTRY1))
          pcornet$TUMOR_REGISTRY1 %>% filter(is_hl_histology(HISTOLOGICAL_TYPE)) %>% distinct(ID) else tibble(ID = character()),
        if (!is.null(pcornet$TUMOR_REGISTRY2) && "MORPH" %in% names(pcornet$TUMOR_REGISTRY2))
          pcornet$TUMOR_REGISTRY2 %>% filter(is_hl_histology(MORPH)) %>% distinct(ID) else tibble(ID = character()),
        if (!is.null(pcornet$TUMOR_REGISTRY3) && "MORPH" %in% names(pcornet$TUMOR_REGISTRY3))
          pcornet$TUMOR_REGISTRY3 %>% filter(is_hl_histology(MORPH)) %>% distinct(ID) else tibble(ID = character())
      ) %>% distinct(ID) %>% mutate(has_tr = TRUE)
    },
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

# Step 2: with_enrollment_period() (matches Python: enrolled patients only)
cohort <- cohort %>% with_enrollment_period()
attrition_log <- log_attrition(attrition_log, "Has enrollment record", n_distinct(cohort$ID))

# ==============================================================================
# SECTION 3: ENROLLMENT AGGREGATION (D-10 age calculation)
# ==============================================================================

message("\n--- Enrollment Aggregation ---")

# Get primary site enrollment only (D-13: primary site strategy)
enrollment_primary <- pcornet$ENROLLMENT %>%
  inner_join(
    pcornet$DEMOGRAPHIC %>% select(ID, SOURCE),
    by = c("ID", "SOURCE")
  )

# Aggregate enrollment dates per patient
enrollment_dates <- enrollment_primary %>%
  group_by(ID) %>%
  summarise(
    enr_start_date = min(ENR_START_DATE, na.rm = TRUE),
    enr_end_date = max(ENR_END_DATE, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    enrollment_duration_days = as.numeric(enr_end_date - enr_start_date)
  )

# Join enrollment dates and calculate ages (D-10)
cohort <- cohort %>%
  left_join(enrollment_dates, by = "ID") %>%
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

message(glue("  Patients with first_hl_dx_date: {sum(!is.na(cohort$first_hl_dx_date))}"))
message(glue("  Patients missing first_hl_dx_date: {sum(is.na(cohort$first_hl_dx_date))}"))

# ==============================================================================
# SECTION 5: JOIN PAYER SUMMARY FIELDS (D-09)
# ==============================================================================

message("\n--- Payer Summary ---")

cohort <- cohort %>%
  left_join(
    payer_summary %>%
      select(ID, PAYER_CATEGORY_PRIMARY, PAYER_CATEGORY_AT_FIRST_DX,
             DUAL_ELIGIBLE, PAYER_TRANSITION, N_ENCOUNTERS, N_ENCOUNTERS_WITH_PAYER),
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
source("R/10_treatment_payer.R")

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

message(glue("  DAYS_DX_TO_CHEMO: median {median(cohort$DAYS_DX_TO_CHEMO, na.rm = TRUE)} days (N={sum(!is.na(cohort$DAYS_DX_TO_CHEMO))})"))
message(glue("  DAYS_DX_TO_RADIATION: median {median(cohort$DAYS_DX_TO_RADIATION, na.rm = TRUE)} days (N={sum(!is.na(cohort$DAYS_DX_TO_RADIATION))})"))
message(glue("  DAYS_DX_TO_SCT: median {median(cohort$DAYS_DX_TO_SCT, na.rm = TRUE)} days (N={sum(!is.na(cohort$DAYS_DX_TO_SCT))})"))

# ==============================================================================
# SECTION 6.65: AGE AT DX, AGE GROUP, DX YEAR, POST-TX ENCOUNTER FLAG
# ==============================================================================

message("\n--- Age & DX Year Derivation ---")

cohort <- cohort %>%
  mutate(
    age_at_dx = as.integer(
      time_length(interval(BIRTH_DATE, first_hl_dx_date), "years")
    ),
    AGE_GROUP = case_when(
      age_at_dx >= 0  & age_at_dx <= 17 ~ "0-17",
      age_at_dx >= 18 & age_at_dx <= 39 ~ "18-39",
      age_at_dx >= 40 & age_at_dx <= 64 ~ "40-64",
      age_at_dx >= 65                    ~ "65+",
      TRUE                               ~ NA_character_
    ),
    DX_YEAR = year(first_hl_dx_date)
  )

message(glue("  Age at diagnosis: median {median(cohort$age_at_dx, na.rm = TRUE)}, range [{min(cohort$age_at_dx, na.rm = TRUE)}, {max(cohort$age_at_dx, na.rm = TRUE)}]"))
age_grp_dist <- cohort %>% filter(!is.na(AGE_GROUP)) %>% count(AGE_GROUP)
for (i in seq_len(nrow(age_grp_dist))) {
  message(glue("  {age_grp_dist$AGE_GROUP[i]}: {age_grp_dist$n[i]}"))
}

# ==============================================================================
# SECTION 6.7: SURVEILLANCE MODALITY FLAGS (D-01, D-02, D-03, D-04)
# ==============================================================================

message("\n--- Surveillance Modality Detection ---")
source("R/13_surveillance.R")

post_dx_date_map <- cohort %>% select(ID, first_hl_dx_date)
surveillance_flags <- assemble_surveillance_flags(post_dx_date_map)

cohort <- cohort %>%
  left_join(surveillance_flags, by = "ID")

# ==============================================================================
# SECTION 6.8: SURVIVORSHIP ENCOUNTER CLASSIFICATION (D-05 through D-10)
# ==============================================================================

message("\n--- Survivorship Encounter Classification ---")
source("R/14_survivorship_encounters.R")

survivorship_flags <- classify_survivorship_encounters(post_dx_date_map)

cohort <- cohort %>%
  left_join(survivorship_flags, by = "ID")

# Post-treatment encounter flag: Yes/No based on any non-acute post-dx encounter
cohort <- cohort %>%
  mutate(
    HAS_POST_TX_ENCOUNTERS = if_else(
      coalesce(HAD_ENC_NONACUTE_CARE, 0L) == 1L, "Yes", "No"
    )
  )

message(glue("\n  Post-treatment encounters: {sum(cohort$HAS_POST_TX_ENCOUNTERS == 'Yes', na.rm = TRUE)} Yes, {sum(cohort$HAS_POST_TX_ENCOUNTERS == 'No', na.rm = TRUE)} No"))

# ==============================================================================
# SECTION 7: FINAL COHORT ASSEMBLY (D-09 column order)
# ==============================================================================

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

# ==============================================================================
# SECTION 8: COHORT SUMMARY (console output)
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

# ==============================================================================
# SECTION 10: CSV OUTPUT (D-11)
# ==============================================================================

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
