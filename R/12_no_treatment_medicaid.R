# ==============================================================================
# 12_no_treatment_medicaid.R -- Profile patients with Medicaid + no treatment
# ==============================================================================
#
# Investigates patients who have Medicaid as primary payer but no evidence of
# chemotherapy, radiation, or stem cell transplant across all detection sources.
#
# Per user request: NO HIPAA suppression — exact counts printed regardless of
# cell size.
#
# Dependencies:
#   - 04_build_cohort.R must be sourced first (produces hl_cohort, pcornet,
#     encounters, payer_summary in the global environment)
#   - 10_treatment_payer.R sourced via 04_build_cohort.R
#
# Usage:
#   source("R/04_build_cohort.R")
#   source("R/12_no_treatment_medicaid.R")
#
# ==============================================================================

library(dplyr)
library(glue)
library(lubridate)
library(stringr)
library(readr)

message("\n", strrep("=", 60))
message("No-Treatment Medicaid Patient Investigation")
message(strrep("=", 60))

# ==============================================================================
# SECTION 1: IDENTIFY NO-TREATMENT MEDICAID PATIENTS
# ==============================================================================

# No HIPAA suppression — print exact counts
fmt <- function(n, total) {
  pct <- round(100 * n / total, 1)
  paste0(n, " (", pct, "%)")
}

# Filter: Medicaid primary payer AND no treatment flags
no_tx_medicaid <- hl_cohort %>%
  filter(
    PAYER_CATEGORY_PRIMARY == "Medicaid",
    HAD_CHEMO == 0,
    HAD_RADIATION == 0,
    HAD_SCT == 0
  )

# Context: all Medicaid patients and all no-treatment patients
all_medicaid <- hl_cohort %>% filter(PAYER_CATEGORY_PRIMARY == "Medicaid")
all_no_tx <- hl_cohort %>% filter(HAD_CHEMO == 0 & HAD_RADIATION == 0 & HAD_SCT == 0)

n_cohort <- nrow(hl_cohort)
n_medicaid <- nrow(all_medicaid)
n_no_tx <- nrow(all_no_tx)
n_target <- nrow(no_tx_medicaid)

message(glue("\n--- Population Context ---"))
message(glue("  Total cohort:                    {n_cohort}"))
message(glue("  All Medicaid:                    {fmt(n_medicaid, n_cohort)}"))
message(glue("  All no-treatment:                {fmt(n_no_tx, n_cohort)}"))
message(glue("  No-treatment + Medicaid:         {fmt(n_target, n_cohort)}"))
message(glue("  % of Medicaid with no treatment: {round(100 * n_target / n_medicaid, 1)}%"))
message(glue("  % of no-treatment that are Medicaid: {round(100 * n_target / n_no_tx, 1)}%"))

# ==============================================================================
# SECTION 2: HL VERIFICATION SOURCE
# ==============================================================================

message(glue("\n--- HL Verification Source ---"))
hl_source_dist <- no_tx_medicaid %>%
  count(HL_SOURCE, name = "n") %>%
  arrange(desc(n))
for (i in seq_len(nrow(hl_source_dist))) {
  message(glue("  {hl_source_dist$HL_SOURCE[i]}: {fmt(hl_source_dist$n[i], n_target)}"))
}

hl_verified_dist <- no_tx_medicaid %>%
  count(HL_VERIFIED, name = "n") %>%
  arrange(desc(n))
message(glue("  HL_VERIFIED=1: {sum(no_tx_medicaid$HL_VERIFIED == 1)} | HL_VERIFIED=0: {sum(no_tx_medicaid$HL_VERIFIED == 0)}"))

# ==============================================================================
# SECTION 3: DIAGNOSIS DATE ANALYSIS
# ==============================================================================

message(glue("\n--- Diagnosis Date Analysis ---"))

n_has_dx_date <- sum(!is.na(no_tx_medicaid$first_hl_dx_date))
n_missing_dx_date <- sum(is.na(no_tx_medicaid$first_hl_dx_date))
message(glue("  Has first_hl_dx_date: {n_has_dx_date} ({round(100 * n_has_dx_date / n_target, 1)}%)"))
message(glue("  Missing first_hl_dx_date: {n_missing_dx_date} ({round(100 * n_missing_dx_date / n_target, 1)}%)"))

if (n_has_dx_date > 0) {
  dx_dates <- no_tx_medicaid %>% filter(!is.na(first_hl_dx_date))
  message(glue("  Earliest diagnosis: {min(dx_dates$first_hl_dx_date)}"))
  message(glue("  Latest diagnosis:   {max(dx_dates$first_hl_dx_date)}"))
  message(glue("  Median diagnosis:   {median(dx_dates$first_hl_dx_date)}"))

  # Diagnosis year distribution
  dx_year_dist <- dx_dates %>%
    mutate(dx_year = year(first_hl_dx_date)) %>%
    count(dx_year, name = "n") %>%
    arrange(dx_year)

  message(glue("\n  Diagnosis year distribution:"))
  for (i in seq_len(nrow(dx_year_dist))) {
    message(glue("    {dx_year_dist$dx_year[i]}: {fmt(dx_year_dist$n[i], n_has_dx_date)}"))
  }
}

# Compare with Medicaid patients WHO DO have treatment
tx_medicaid <- hl_cohort %>%
  filter(
    PAYER_CATEGORY_PRIMARY == "Medicaid",
    (HAD_CHEMO == 1 | HAD_RADIATION == 1 | HAD_SCT == 1)
  )

message(glue("\n  --- Comparison: Medicaid WITH treatment ---"))
n_tx_med <- nrow(tx_medicaid)
n_tx_has_dx <- sum(!is.na(tx_medicaid$first_hl_dx_date))
if (n_tx_has_dx > 0) {
  tx_dx <- tx_medicaid %>% filter(!is.na(first_hl_dx_date))
  message(glue("  N = {n_tx_med}"))
  message(glue("  Has dx date: {n_tx_has_dx} ({round(100 * n_tx_has_dx / n_tx_med, 1)}%)"))
  message(glue("  Earliest: {min(tx_dx$first_hl_dx_date)} | Latest: {max(tx_dx$first_hl_dx_date)} | Median: {median(tx_dx$first_hl_dx_date)}"))
}

# ==============================================================================
# SECTION 4: PAYER AT FIRST DIAGNOSIS
# ==============================================================================

message(glue("\n--- Payer at First Diagnosis ---"))
dx_payer_dist <- no_tx_medicaid %>%
  mutate(PAYER_CATEGORY_AT_FIRST_DX = coalesce(PAYER_CATEGORY_AT_FIRST_DX, "Unknown")) %>%
  count(PAYER_CATEGORY_AT_FIRST_DX, name = "n") %>%
  arrange(desc(n))
for (i in seq_len(nrow(dx_payer_dist))) {
  message(glue("  {dx_payer_dist$PAYER_CATEGORY_AT_FIRST_DX[i]}: {fmt(dx_payer_dist$n[i], n_target)}"))
}

# ==============================================================================
# SECTION 5: DEMOGRAPHICS
# ==============================================================================

message(glue("\n--- Demographics ---"))

# Sex
sex_dist <- no_tx_medicaid %>%
  count(SEX, name = "n") %>%
  arrange(desc(n))
message("  Sex:")
for (i in seq_len(nrow(sex_dist))) {
  message(glue("    {sex_dist$SEX[i]}: {fmt(sex_dist$n[i], n_target)}"))
}

# Race
race_dist <- no_tx_medicaid %>%
  count(RACE, name = "n") %>%
  arrange(desc(n))
message("  Race:")
for (i in seq_len(nrow(race_dist))) {
  message(glue("    {race_dist$RACE[i]}: {fmt(race_dist$n[i], n_target)}"))
}

# Hispanic
hisp_dist <- no_tx_medicaid %>%
  count(HISPANIC, name = "n") %>%
  arrange(desc(n))
message("  Hispanic:")
for (i in seq_len(nrow(hisp_dist))) {
  message(glue("    {hisp_dist$HISPANIC[i]}: {fmt(hisp_dist$n[i], n_target)}"))
}

# Age at enrollment start
message(glue("\n  Age at enrollment start:"))
age_vals <- no_tx_medicaid$age_at_enr_start
message(glue("    Mean: {round(mean(age_vals, na.rm = TRUE), 1)}"))
message(glue("    Median: {median(age_vals, na.rm = TRUE)}"))
message(glue("    Range: [{min(age_vals, na.rm = TRUE)}, {max(age_vals, na.rm = TRUE)}]"))
message(glue("    IQR: [{quantile(age_vals, 0.25, na.rm = TRUE)}, {quantile(age_vals, 0.75, na.rm = TRUE)}]"))

# Age bins
age_bin_dist <- no_tx_medicaid %>%
  mutate(age_bin = case_when(
    age_at_enr_start < 18 ~ "<18",
    age_at_enr_start < 30 ~ "18-29",
    age_at_enr_start < 45 ~ "30-44",
    age_at_enr_start < 65 ~ "45-64",
    TRUE ~ "65+"
  )) %>%
  mutate(age_bin = factor(age_bin, levels = c("<18", "18-29", "30-44", "45-64", "65+"))) %>%
  count(age_bin, name = "n")
message("  Age groups:")
for (i in seq_len(nrow(age_bin_dist))) {
  message(glue("    {age_bin_dist$age_bin[i]}: {fmt(age_bin_dist$n[i], n_target)}"))
}

# ==============================================================================
# SECTION 6: SITE (SOURCE) DISTRIBUTION
# ==============================================================================

message(glue("\n--- Site Distribution ---"))
site_dist <- no_tx_medicaid %>%
  count(SOURCE, name = "n") %>%
  arrange(desc(n))

# Also get site totals for context
site_totals <- hl_cohort %>% count(SOURCE, name = "total")

site_comparison <- site_dist %>%
  left_join(site_totals, by = "SOURCE") %>%
  mutate(pct_of_site = round(100 * n / total, 1))

for (i in seq_len(nrow(site_comparison))) {
  r <- site_comparison[i, ]
  message(glue("  {r$SOURCE}: {r$n} no-tx Medicaid / {r$total} total ({r$pct_of_site}% of site)"))
}

# ==============================================================================
# SECTION 7: ENROLLMENT CHARACTERISTICS
# ==============================================================================

message(glue("\n--- Enrollment ---"))
message(glue("  Enrollment duration (days):"))
enr_vals <- no_tx_medicaid$enrollment_duration_days
message(glue("    Mean: {round(mean(enr_vals, na.rm = TRUE), 0)}"))
message(glue("    Median: {median(enr_vals, na.rm = TRUE)}"))
message(glue("    Range: [{min(enr_vals, na.rm = TRUE)}, {max(enr_vals, na.rm = TRUE)}]"))

# Enrollment duration bins
enr_bin_dist <- no_tx_medicaid %>%
  mutate(enr_bin = case_when(
    enrollment_duration_days < 30 ~ "<30 days",
    enrollment_duration_days < 180 ~ "30-179 days",
    enrollment_duration_days < 365 ~ "180-364 days",
    enrollment_duration_days < 730 ~ "1-2 years",
    enrollment_duration_days < 1825 ~ "2-5 years",
    TRUE ~ "5+ years"
  )) %>%
  mutate(enr_bin = factor(enr_bin, levels = c("<30 days", "30-179 days", "180-364 days",
                                                "1-2 years", "2-5 years", "5+ years"))) %>%
  count(enr_bin, name = "n")
message("  Enrollment duration groups:")
for (i in seq_len(nrow(enr_bin_dist))) {
  message(glue("    {enr_bin_dist$enr_bin[i]}: {fmt(enr_bin_dist$n[i], n_target)}"))
}

# ==============================================================================
# SECTION 8: ENCOUNTER PATTERNS
# ==============================================================================

message(glue("\n--- Encounter Patterns ---"))
message(glue("  Total encounters (N_ENCOUNTERS):"))
enc_vals <- no_tx_medicaid$N_ENCOUNTERS
message(glue("    Mean: {round(mean(enc_vals, na.rm = TRUE), 1)}"))
message(glue("    Median: {median(enc_vals, na.rm = TRUE)}"))
message(glue("    Range: [{min(enc_vals, na.rm = TRUE)}, {max(enc_vals, na.rm = TRUE)}]"))

message(glue("  Encounters with payer (N_ENCOUNTERS_WITH_PAYER):"))
enc_payer_vals <- no_tx_medicaid$N_ENCOUNTERS_WITH_PAYER
message(glue("    Mean: {round(mean(enc_payer_vals, na.rm = TRUE), 1)}"))
message(glue("    Median: {median(enc_payer_vals, na.rm = TRUE)}"))

# Encounter bins
enc_bin_dist <- no_tx_medicaid %>%
  mutate(enc_bin = case_when(
    N_ENCOUNTERS == 0 ~ "0",
    N_ENCOUNTERS <= 5 ~ "1-5",
    N_ENCOUNTERS <= 10 ~ "6-10",
    N_ENCOUNTERS <= 25 ~ "11-25",
    N_ENCOUNTERS <= 50 ~ "26-50",
    TRUE ~ "51+"
  )) %>%
  mutate(enc_bin = factor(enc_bin, levels = c("0", "1-5", "6-10", "11-25", "26-50", "51+"))) %>%
  count(enc_bin, name = "n")
message("  Encounter count groups:")
for (i in seq_len(nrow(enc_bin_dist))) {
  message(glue("    {enc_bin_dist$enc_bin[i]}: {fmt(enc_bin_dist$n[i], n_target)}"))
}

# ==============================================================================
# SECTION 9: DUAL ELIGIBLE AND PAYER TRANSITIONS
# ==============================================================================

message(glue("\n--- Dual Eligible & Payer Transitions ---"))
n_dual <- sum(no_tx_medicaid$DUAL_ELIGIBLE == 1)
n_transition <- sum(no_tx_medicaid$PAYER_TRANSITION == 1)
message(glue("  Dual eligible (any encounter): {fmt(n_dual, n_target)}"))
message(glue("  Payer transition (>1 category): {fmt(n_transition, n_target)}"))

# ==============================================================================
# SECTION 10: ENCOUNTER TYPE BREAKDOWN (from raw encounter data)
# ==============================================================================

message(glue("\n--- Encounter Types (from ENCOUNTER table) ---"))

target_ids <- no_tx_medicaid$ID

if ("ENC_TYPE" %in% names(encounters)) {
  enc_type_dist <- encounters %>%
    filter(ID %in% target_ids) %>%
    count(ENC_TYPE, name = "n") %>%
    arrange(desc(n))

  n_enc_total <- sum(enc_type_dist$n)
  for (i in seq_len(nrow(enc_type_dist))) {
    message(glue("  {enc_type_dist$ENC_TYPE[i]}: {fmt(enc_type_dist$n[i], n_enc_total)}"))
  }
} else {
  message("  ENC_TYPE column not available in encounters")
}

# ==============================================================================
# SECTION 11: DIAGNOSIS CODES — WHAT HL CODES DO THESE PATIENTS HAVE?
# ==============================================================================

message(glue("\n--- HL Diagnosis Codes ---"))

hl_dx_detail <- pcornet$DIAGNOSIS %>%
  filter(ID %in% target_ids) %>%
  filter(is_hl_diagnosis(DX, DX_TYPE)) %>%
  count(DX, DX_TYPE, name = "n_records") %>%
  arrange(desc(n_records))

n_hl_records <- sum(hl_dx_detail$n_records)
message(glue("  Total HL diagnosis records: {n_hl_records}"))
message(glue("  Unique HL codes: {nrow(hl_dx_detail)}"))
message(glue("  Top 15 codes:"))
for (i in seq_len(min(15, nrow(hl_dx_detail)))) {
  r <- hl_dx_detail[i, ]
  message(glue("    {r$DX} (type={r$DX_TYPE}): {r$n_records} records"))
}

# Number of distinct HL dx codes per patient
dx_per_patient <- pcornet$DIAGNOSIS %>%
  filter(ID %in% target_ids) %>%
  filter(is_hl_diagnosis(DX, DX_TYPE)) %>%
  group_by(ID) %>%
  summarise(n_dx_records = n(), n_distinct_codes = n_distinct(DX), .groups = "drop")

message(glue("\n  HL dx records per patient:"))
message(glue("    Mean: {round(mean(dx_per_patient$n_dx_records, na.rm = TRUE), 1)}"))
message(glue("    Median: {median(dx_per_patient$n_dx_records, na.rm = TRUE)}"))
message(glue("    Range: [{min(dx_per_patient$n_dx_records)}, {max(dx_per_patient$n_dx_records)}]"))

# ==============================================================================
# SECTION 12: NEAR-MISS TREATMENT ANALYSIS
# ==============================================================================
# Check if these patients have ANY procedure/prescribing records at all,
# even if not matching known treatment codes

message(glue("\n--- Near-Miss Treatment Analysis ---"))

# Any procedures at all?
if (!is.null(pcornet$PROCEDURES)) {
  n_with_any_px <- pcornet$PROCEDURES %>%
    filter(ID %in% target_ids) %>%
    distinct(ID) %>%
    nrow()
  message(glue("  Patients with ANY procedure record: {fmt(n_with_any_px, n_target)}"))

  # Top procedure types
  px_type_dist <- pcornet$PROCEDURES %>%
    filter(ID %in% target_ids) %>%
    count(PX_TYPE, name = "n") %>%
    arrange(desc(n))
  message("  Procedure types:")
  for (i in seq_len(nrow(px_type_dist))) {
    message(glue("    PX_TYPE={px_type_dist$PX_TYPE[i]}: {px_type_dist$n[i]} records"))
  }
}

# Any prescribing records?
if (!is.null(pcornet$PRESCRIBING)) {
  n_with_any_rx <- pcornet$PRESCRIBING %>%
    filter(ID %in% target_ids) %>%
    distinct(ID) %>%
    nrow()
  message(glue("  Patients with ANY prescribing record: {fmt(n_with_any_rx, n_target)}"))
}

# Any dispensing records?
if (!is.null(pcornet$DISPENSING)) {
  n_with_any_disp <- pcornet$DISPENSING %>%
    filter(ID %in% target_ids) %>%
    distinct(ID) %>%
    nrow()
  message(glue("  Patients with ANY dispensing record: {fmt(n_with_any_disp, n_target)}"))
}

# ==============================================================================
# SECTION 13: DIAGNOSIS DATE vs ENROLLMENT WINDOW
# ==============================================================================

message(glue("\n--- Diagnosis Date vs Enrollment Window ---"))

dx_enr_analysis <- no_tx_medicaid %>%
  filter(!is.na(first_hl_dx_date)) %>%
  left_join(
    pcornet$ENROLLMENT %>%
      inner_join(pcornet$DEMOGRAPHIC %>% select(ID, SOURCE), by = c("ID", "SOURCE")) %>%
      group_by(ID) %>%
      summarise(
        enr_start = min(ENR_START_DATE, na.rm = TRUE),
        enr_end = max(ENR_END_DATE, na.rm = TRUE),
        .groups = "drop"
      ),
    by = "ID"
  ) %>%
  mutate(
    dx_before_enr = first_hl_dx_date < enr_start,
    dx_after_enr = first_hl_dx_date > enr_end,
    dx_during_enr = first_hl_dx_date >= enr_start & first_hl_dx_date <= enr_end,
    days_dx_to_enr_start = as.numeric(first_hl_dx_date - enr_start),
    days_dx_to_enr_end = as.numeric(enr_end - first_hl_dx_date)
  )

n_dx_enr <- nrow(dx_enr_analysis)
message(glue("  Patients with dx date + enrollment: {n_dx_enr}"))
message(glue("  Dx BEFORE enrollment start: {fmt(sum(dx_enr_analysis$dx_before_enr, na.rm = TRUE), n_dx_enr)}"))
message(glue("  Dx DURING enrollment:       {fmt(sum(dx_enr_analysis$dx_during_enr, na.rm = TRUE), n_dx_enr)}"))
message(glue("  Dx AFTER enrollment end:    {fmt(sum(dx_enr_analysis$dx_after_enr, na.rm = TRUE), n_dx_enr)}"))

# For those diagnosed during enrollment: how long from dx to enrollment end?
during <- dx_enr_analysis %>% filter(dx_during_enr == TRUE)
if (nrow(during) > 0) {
  message(glue("\n  Among diagnosed DURING enrollment (N={nrow(during)}):"))
  message(glue("    Days from dx to enrollment end:"))
  message(glue("      Mean: {round(mean(during$days_dx_to_enr_end, na.rm = TRUE), 0)}"))
  message(glue("      Median: {median(during$days_dx_to_enr_end, na.rm = TRUE)}"))
  message(glue("      <30 days remaining: {sum(during$days_dx_to_enr_end < 30, na.rm = TRUE)}"))
  message(glue("      <90 days remaining: {sum(during$days_dx_to_enr_end < 90, na.rm = TRUE)}"))
  message(glue("      <180 days remaining: {sum(during$days_dx_to_enr_end < 180, na.rm = TRUE)}"))
}

# ==============================================================================
# SECTION 14: CSV OUTPUT
# ==============================================================================

output_dir <- file.path(CONFIG$output_dir, "investigation")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# Full patient list
output_path <- file.path(output_dir, "no_treatment_medicaid_patients.csv")
write_csv(no_tx_medicaid, output_path)
message(glue("\n  Patient list saved to: {output_path}"))
message(glue("  Rows: {nrow(no_tx_medicaid)}, Columns: {ncol(no_tx_medicaid)}"))

# Diagnosis date detail
dx_detail_out <- no_tx_medicaid %>%
  select(ID, SOURCE, HL_SOURCE, HL_VERIFIED, first_hl_dx_date,
         PAYER_CATEGORY_PRIMARY, PAYER_CATEGORY_AT_FIRST_DX,
         age_at_enr_start, enrollment_duration_days,
         N_ENCOUNTERS, N_ENCOUNTERS_WITH_PAYER) %>%
  arrange(first_hl_dx_date)

output_path2 <- file.path(output_dir, "no_treatment_medicaid_dx_dates.csv")
write_csv(dx_detail_out, output_path2)
message(glue("  Dx date detail saved to: {output_path2}"))

message("\n", strrep("=", 60))
message("No-Treatment Medicaid investigation complete")
message(strrep("=", 60))

# ==============================================================================
# End of 12_no_treatment_medicaid.R
# ==============================================================================
