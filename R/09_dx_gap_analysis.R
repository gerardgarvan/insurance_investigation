# ==============================================================================
# 09_dx_gap_analysis.R -- Diagnosis gap analysis for excluded "Neither" patients
# ==============================================================================
#
# Purpose: Investigate the ~19 patients excluded as "Neither" (no HL evidence
#          in DIAGNOSIS or TUMOR_REGISTRY tables) to characterize the data gap
#          and determine whether pipeline changes are warranted.
#
# Decisions referenced: D-01 through D-10 from Phase 7 Context
#   D-01: Pull all DIAGNOSIS records for Neither patients, filter to lymphoma/cancer codes
#   D-02: Cross-reference ENROLLMENT and TUMOR_REGISTRY for each patient
#   D-03: Site-level stratification of gap patterns
#   D-04: Not used (reserved)
#   D-05: Per-patient gap classification (phantom, coding gap, non-HL codes, etc.)
#   D-06: Not used (reserved)
#   D-07: Three CSV outputs (all dx, lymphoma subset, patient summary)
#   D-08: Console summary with site stratification
#   D-09: Recommendation based on findings (expand codes OR report only)
#   D-10: Read excluded_no_hl_evidence.csv as input (depends on full pipeline)
#
# Usage: source("R/09_dx_gap_analysis.R")
#
# Dependencies: Requires full pipeline run first (reads excluded_no_hl_evidence.csv)
#
# ==============================================================================

source("R/01_load_pcornet.R")  # Loads config, utils, and all PCORnet tables

library(dplyr)
library(readr)
library(stringr)
library(janitor)
library(glue)

message("\n", strrep("=", 60))
message("NEITHER PATIENTS GAP ANALYSIS")
message(strrep("=", 60))

# ==============================================================================
# SECTION 1: Load excluded patients (per D-10)
# ==============================================================================

message("\n--- Loading Excluded Patients ---")

excl_path <- file.path(CONFIG$output_dir, "cohort", "excluded_no_hl_evidence.csv")

# Check file exists
if (!file.exists(excl_path)) {
  stop("No excluded patients found. Run the full pipeline first (source R/04_build_cohort.R).")
}

excluded_patients <- read_csv(excl_path, show_col_types = FALSE)

# Validate data
if (nrow(excluded_patients) == 0) {
  stop("excluded_no_hl_evidence.csv exists but has 0 rows. Run the full pipeline first.")
}

# Log count and sites
message(glue("Loaded {nrow(excluded_patients)} excluded patients"))
n_sites <- length(unique(excluded_patients$SOURCE))
sites_str <- paste(sort(unique(excluded_patients$SOURCE)), collapse = ", ")
message(glue("Sites ({n_sites}): {sites_str}"))

# ==============================================================================
# SECTION 2: DIAGNOSIS table exploration (per D-01)
# ==============================================================================

message("\n--- DIAGNOSIS Table Exploration ---")

# Filter DIAGNOSIS to only the Neither patients
neither_dx <- pcornet$DIAGNOSIS %>%
  semi_join(excluded_patients, by = "ID") %>%
  select(ID, DX, DX_TYPE, DX_DATE, DX_SOURCE, ADMIT_DATE, SOURCE)

# Log counts
n_dx_patients <- n_distinct(neither_dx$ID)
message(glue("Found {nrow(neither_dx)} diagnosis records for {n_dx_patients} Neither patients"))

# Check for patients with ZERO diagnosis records
no_dx_patients <- excluded_patients %>%
  anti_join(neither_dx, by = "ID")

message(glue("Patients with ZERO diagnosis records: {nrow(no_dx_patients)}"))

# --- Lymphoma/cancer code filtering ---

# Normalize DX codes
neither_dx <- neither_dx %>%
  mutate(DX_normalized = normalize_icd(DX))

# Define lymphoma/cancer ICD patterns
# ICD-10: C81-C96 (lymphomas and related cancers)
lymphoma_icd10_pattern <- "^C(8[1-9]|9[0-6])"
# ICD-9: 200-208 (lymphomas and leukemias)
lymphoma_icd9_pattern <- "^20[0-8]"

# Filter to lymphoma/cancer codes
neither_lymphoma <- neither_dx %>%
  filter(
    (DX_TYPE == "10" & str_detect(DX_normalized, lymphoma_icd10_pattern)) |
    (DX_TYPE == "09" & str_detect(DX_normalized, lymphoma_icd9_pattern))
  )

n_lymphoma_patients <- n_distinct(neither_lymphoma$ID)
message(glue("Found {nrow(neither_lymphoma)} lymphoma/cancer codes for {n_lymphoma_patients} patients"))

# Check if any are actual HL codes (would indicate pipeline bug)
neither_lymphoma <- neither_lymphoma %>%
  mutate(is_hl = is_hl_diagnosis(DX, DX_TYPE))

n_hl_codes <- sum(neither_lymphoma$is_hl, na.rm = TRUE)
if (n_hl_codes > 0) {
  message(glue("  WARNING: {n_hl_codes} HL codes found in Neither patients -- PIPELINE BUG!"))
  # Show the problematic codes
  hl_found <- neither_lymphoma %>%
    filter(is_hl) %>%
    select(ID, DX, DX_TYPE, SOURCE) %>%
    head(10)
  print(hl_found)
} else {
  message("  No HL codes detected in lymphoma subset (expected)")
}

# ==============================================================================
# SECTION 3: ENROLLMENT cross-reference (per D-02, D-05)
# ==============================================================================

message("\n--- ENROLLMENT Cross-Reference ---")

# Get enrollment records for Neither patients
patient_enrollment <- pcornet$ENROLLMENT %>%
  semi_join(excluded_patients, by = "ID") %>%
  group_by(ID, SOURCE) %>%
  summarise(
    has_enrollment = TRUE,
    enr_start = min(ENR_START_DATE, na.rm = TRUE),
    enr_end = max(ENR_END_DATE, na.rm = TRUE),
    n_enrollment_records = n(),
    .groups = "drop"
  ) %>%
  mutate(
    enr_days = as.numeric(enr_end - enr_start)
  )

# Left join to excluded_patients to preserve patients without enrollment
patient_enrollment_full <- excluded_patients %>%
  select(ID, SOURCE) %>%
  left_join(patient_enrollment, by = c("ID", "SOURCE")) %>%
  mutate(
    has_enrollment = coalesce(has_enrollment, FALSE),
    n_enrollment_records = coalesce(n_enrollment_records, 0L)
  )

n_with_enr <- sum(patient_enrollment_full$has_enrollment)
n_without_enr <- sum(!patient_enrollment_full$has_enrollment)
message(glue("Patients WITH enrollment: {n_with_enr}"))
message(glue("Patients WITHOUT enrollment: {n_without_enr}"))

# ==============================================================================
# SECTION 4: TUMOR_REGISTRY exploration (per D-02)
# ==============================================================================

message("\n--- TUMOR_REGISTRY Exploration ---")

# Check all three TR tables for ANY records (not just HL histology matches)
tr_results <- list()

# TR1
if (!is.null(pcornet$TUMOR_REGISTRY1)) {
  tr1_ids <- pcornet$TUMOR_REGISTRY1 %>%
    semi_join(excluded_patients, by = "ID") %>%
    distinct(ID) %>%
    mutate(tr_table = "TR1")
  tr_results <- c(tr_results, list(tr1_ids))
  message(glue("  TR1: {nrow(tr1_ids)} patients with records"))
} else {
  message("  TR1: table not loaded")
}

# TR2
if (!is.null(pcornet$TUMOR_REGISTRY2)) {
  tr2_ids <- pcornet$TUMOR_REGISTRY2 %>%
    semi_join(excluded_patients, by = "ID") %>%
    distinct(ID) %>%
    mutate(tr_table = "TR2")
  tr_results <- c(tr_results, list(tr2_ids))
  message(glue("  TR2: {nrow(tr2_ids)} patients with records"))
} else {
  message("  TR2: table not loaded")
}

# TR3
if (!is.null(pcornet$TUMOR_REGISTRY3)) {
  tr3_ids <- pcornet$TUMOR_REGISTRY3 %>%
    semi_join(excluded_patients, by = "ID") %>%
    distinct(ID) %>%
    mutate(tr_table = "TR3")
  tr_results <- c(tr_results, list(tr3_ids))
  message(glue("  TR3: {nrow(tr3_ids)} patients with records"))
} else {
  message("  TR3: table not loaded")
}

# Combine TR results
if (length(tr_results) > 0) {
  tr_summary <- bind_rows(tr_results) %>%
    group_by(ID) %>%
    summarise(
      has_tr_record = TRUE,
      tr_tables = paste(unique(tr_table), collapse = "+"),
      .groups = "drop"
    )
} else {
  tr_summary <- tibble(
    ID = character(),
    has_tr_record = logical(),
    tr_tables = character()
  )
}

n_with_tr <- nrow(tr_summary)
n_without_tr <- nrow(excluded_patients) - n_with_tr
message(glue("Total patients WITH TR records: {n_with_tr}"))
message(glue("Total patients WITHOUT TR records: {n_without_tr}"))

# ==============================================================================
# SECTION 5: Gap classification (per D-05)
# ==============================================================================

message("\n--- Gap Classification ---")

# Build patient summary
patient_summary <- excluded_patients %>%
  select(ID, SOURCE, HL_SOURCE) %>%
  # Join diagnosis counts
  left_join(
    neither_dx %>% count(ID, name = "n_diagnoses"),
    by = "ID"
  ) %>%
  # Join lymphoma code counts
  left_join(
    neither_lymphoma %>% count(ID, name = "n_lymphoma_codes"),
    by = "ID"
  ) %>%
  # Join enrollment info
  left_join(
    patient_enrollment_full %>% select(ID, has_enrollment, enr_days, n_enrollment_records),
    by = "ID"
  ) %>%
  # Join TR info
  left_join(tr_summary, by = "ID") %>%
  # Coalesce NAs to 0/FALSE
  mutate(
    n_diagnoses = coalesce(n_diagnoses, 0L),
    n_lymphoma_codes = coalesce(n_lymphoma_codes, 0L),
    has_enrollment = coalesce(has_enrollment, FALSE),
    enr_days = coalesce(enr_days, NA_real_),
    n_enrollment_records = coalesce(n_enrollment_records, 0L),
    has_tr_record = coalesce(has_tr_record, FALSE),
    tr_tables = coalesce(tr_tables, "none")
  ) %>%
  # Apply gap classification
  mutate(
    gap_classification = case_when(
      n_diagnoses == 0 & !has_enrollment ~ "Phantom record (no dx, no enrollment)",
      n_diagnoses == 0 & has_enrollment ~ "Coding gap (enrollment exists, zero dx)",
      n_lymphoma_codes > 0 ~ "Has lymphoma/cancer codes (not HL-specific)",
      n_diagnoses > 0 & !has_tr_record ~ "Non-HL diagnoses only (no TR backup)",
      has_tr_record & n_diagnoses == 0 ~ "TR record exists but no dx codes",
      has_tr_record & n_diagnoses > 0 ~ "Non-HL dx + non-HL TR",
      TRUE ~ "Uncategorized (requires manual review)"
    )
  ) %>%
  select(
    ID, SOURCE, HL_SOURCE,
    n_diagnoses, n_lymphoma_codes,
    has_enrollment, enr_days, n_enrollment_records,
    has_tr_record, tr_tables,
    gap_classification
  )

# ==============================================================================
# SECTION 6: Console summary (per D-08)
# ==============================================================================

message("\n", strrep("=", 60))
message("NEITHER PATIENTS GAP ANALYSIS SUMMARY")
message(strrep("=", 60))

message(glue("\nTotal excluded patients: {nrow(excluded_patients)}"))
message(glue("Sites: {sites_str}"))

message("\n--- Diagnosis Coverage ---")
n_with_dx <- sum(patient_summary$n_diagnoses > 0)
n_without_dx <- sum(patient_summary$n_diagnoses == 0)
message(glue("  Patients with ANY dx codes: {n_with_dx}"))
message(glue("  Patients with ZERO dx codes: {n_without_dx}"))
message(glue("  Total dx records: {nrow(neither_dx)}"))
message(glue("  Lymphoma/cancer codes found: {nrow(neither_lymphoma)}"))

message("\n--- Enrollment Coverage ---")
message(glue("  Patients with enrollment: {sum(patient_summary$has_enrollment)}"))
message(glue("  Patients without enrollment: {sum(!patient_summary$has_enrollment)}"))

message("\n--- TUMOR_REGISTRY Coverage ---")
message(glue("  Patients with TR records: {sum(patient_summary$has_tr_record)}"))
message(glue("  Patients without TR records: {sum(!patient_summary$has_tr_record)}"))

message("\n--- Gap Classification ---")
gap_counts <- patient_summary %>%
  count(gap_classification) %>%
  arrange(desc(n))

for (i in seq_len(nrow(gap_counts))) {
  message(glue("  {gap_counts$gap_classification[i]}: {gap_counts$n[i]}"))
}

message("\n--- Gap Classification by Site ---")
gap_by_site <- patient_summary %>%
  tabyl(SOURCE, gap_classification) %>%
  adorn_totals(c("row", "col"))

print(gap_by_site)

# If any lymphoma codes found, show the specific codes
if (nrow(neither_lymphoma) > 0) {
  message("\n--- Lymphoma/Cancer Codes Found ---")
  distinct_codes <- neither_lymphoma %>%
    distinct(DX, DX_TYPE) %>%
    arrange(DX_TYPE, DX)

  for (i in seq_len(nrow(distinct_codes))) {
    icd_label <- if_else(distinct_codes$DX_TYPE[i] == "10", "ICD-10", "ICD-9")
    message(glue("  {distinct_codes$DX[i]} ({icd_label})"))
  }
}

# Recommendation line (per D-09)
message("\n--- Recommendation ---")
if (nrow(neither_lymphoma) == 0) {
  message("No lymphoma/cancer codes found in Neither patients. Gap is a data quality")
  message("limitation, not a code list issue. No pipeline changes recommended.")
} else {
  message("Lymphoma/cancer codes found -- review neither_lymphoma_codes.csv to determine")
  message("if HL identification expansion is warranted.")
}

message("\n", strrep("=", 60))

# ==============================================================================
# SECTION 7: CSV outputs (per D-07)
# ==============================================================================

message("\n--- Writing CSV Outputs ---")

# Create diagnostics directory
diag_dir <- file.path(CONFIG$output_dir, "diagnostics")
dir.create(diag_dir, showWarnings = FALSE, recursive = TRUE)

# Write all diagnoses
write_csv(neither_dx, file.path(diag_dir, "neither_all_diagnoses.csv"))
message(glue("Wrote {nrow(neither_dx)} rows to neither_all_diagnoses.csv"))

# Write lymphoma subset
write_csv(neither_lymphoma, file.path(diag_dir, "neither_lymphoma_codes.csv"))
message(glue("Wrote {nrow(neither_lymphoma)} rows to neither_lymphoma_codes.csv"))

# Write patient summary
write_csv(patient_summary, file.path(diag_dir, "neither_patient_summary.csv"))
message(glue("Wrote {nrow(patient_summary)} rows to neither_patient_summary.csv"))

message(glue("\nAll outputs saved to {diag_dir}/"))

# ==============================================================================
# End of 09_dx_gap_analysis.R
# ==============================================================================
