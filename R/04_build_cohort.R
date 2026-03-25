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
# SECTION 2: FILTER CHAIN WITH ATTRITION LOGGING
# ==============================================================================

# Initialize attrition tracking (CHRT-02)
attrition_log <- init_attrition_log()

# Step 0: Initial population from DEMOGRAPHIC (one row per patient)
cohort <- pcornet$DEMOGRAPHIC %>%
  select(ID, SOURCE, SEX, RACE, HISPANIC, BIRTH_DATE)
attrition_log <- log_attrition(attrition_log, "Initial population", n_distinct(cohort$ID))

# Step 1: has_hodgkin_diagnosis() (D-01 first filter)
cohort <- cohort %>% has_hodgkin_diagnosis()
attrition_log <- log_attrition(attrition_log, "Has HL diagnosis (ICD-9/10)", n_distinct(cohort$ID))

# Step 2: with_enrollment_period() (D-03: any enrollment, no min days)
cohort <- cohort %>% with_enrollment_period()
attrition_log <- log_attrition(attrition_log, "Has enrollment record", n_distinct(cohort$ID))

# Step 3: exclude_missing_payer() (D-04: remove NA/Unknown/Unavailable)
cohort <- cohort %>% exclude_missing_payer(payer_summary)
attrition_log <- log_attrition(attrition_log, "Valid payer category", n_distinct(cohort$ID))

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
# SECTION 7: FINAL COHORT ASSEMBLY (D-09 column order)
# ==============================================================================

message("\n--- Final Cohort Assembly ---")

hl_cohort <- cohort %>%
  select(
    ID,
    SOURCE,
    SEX,
    RACE,
    HISPANIC,
    age_at_enr_start,
    age_at_enr_end,
    first_hl_dx_date,
    PAYER_CATEGORY_PRIMARY,
    PAYER_CATEGORY_AT_FIRST_DX,
    DUAL_ELIGIBLE,
    PAYER_TRANSITION,
    N_ENCOUNTERS,
    N_ENCOUNTERS_WITH_PAYER,
    HAD_CHEMO,
    HAD_RADIATION,
    HAD_SCT,
    enrollment_duration_days
  )

# ==============================================================================
# SECTION 8: COHORT SUMMARY (console output)
# ==============================================================================

message("\n", strrep("=", 60))
message("HL COHORT SUMMARY")
message(strrep("=", 60))

message(glue("\nTotal patients: {nrow(hl_cohort)}"))

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
