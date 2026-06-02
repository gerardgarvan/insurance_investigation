# ==============================================================================
# 47_cancer_summary_refined.R
# ==============================================================================
# Purpose: Refined cancer summary: removes D-codes (in-situ/benign), enforces HL
#          cohort confirmation status, computes first HL diagnosis date per patient.
#          Consolidates R/45+R/46 output generation into single source of truth.
#
# Inputs:  output/tables/cancer_summary.csv (Phase 45 output from R/45)
#          DIAGNOSIS DuckDB table (C81 cohort confirmation, record counts)
#          TUMOR_REGISTRY_ALL DuckDB table (first HL diagnosis date)
#
# Outputs: output/tables/cancer_summary.csv (overwritten: D-codes removed, HL cohort only)
#          output/tables/cancer_summary.xlsx (overwritten: single flat sheet)
#          output/tables/cancer_summary_table.xlsx (overwritten: two-sheet styled workbook)
#          output/confirmed_hl_cohort.rds (for Phase 56, 57 consumption)
#
# Dependencies: R/00_config.R, R/01_load_pcornet.R
#
# Requirements: CREF-01: Remove D-codes (in-situ/benign neoplasms)
#               CREF-02: Filter to patients with 2+ C81 codes 7+ days apart
#               CREF-03: Compute first HL diagnosis date (DIAGNOSIS + TUMOR_REGISTRY)
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP ----
# ==============================================================================
# WHY D-codes are removed: D-codes (D00-D48) represent in-situ, benign, and
#   uncertain-behavior neoplasms -- clinically distinct from invasive cancer (C-codes).
#   Removing D-codes focuses the summary on malignant neoplasms only.
#
# WHY HL cohort confirmation is enforced: Ensures only patients meeting cohort
#   criteria (2+ C81 codes 7+ days apart) are included in refined summary, eliminating
#   incidental or rule-out HL diagnoses.
#
# WHY first HL diagnosis date is computed: Anchor point for temporal analysis in
#   downstream scripts (R/48 post-HL, R/49 pre/post partitioning).
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(openxlsx2)
  library(lubridate)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")

# Define output paths
INPUT_CSV <- file.path(CONFIG$output_dir, "tables", "cancer_summary.csv")
OUTPUT_CSV <- file.path(CONFIG$output_dir, "tables", "cancer_summary.csv")
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "tables", "cancer_summary.xlsx")
OUTPUT_TABLE_XLSX <- file.path(CONFIG$output_dir, "tables", "cancer_summary_table.xlsx")
OUTPUT_RDS <- file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds")

dir.create(dirname(OUTPUT_CSV), showWarnings = FALSE, recursive = TRUE)

message("=== Phase 8: Cancer Summary Refined (D-code removal + HL cohort confirmation) ===")
message(glue("Input CSV:  {INPUT_CSV}"))
message(glue("Output CSV: {OUTPUT_CSV}"))
message(glue("Output XLSX: {OUTPUT_XLSX}"))
message(glue("Output Table XLSX: {OUTPUT_TABLE_XLSX}"))
message(glue("Output RDS: {OUTPUT_RDS}"))

# ==============================================================================
# SECTION 2: PREFIX_MAP AND classify_codes()
# ==============================================================================
# Copied from R/54_cancer_summary_table.R (lines 51-311) for script independence.
# All 309 entries including D-codes are needed because classify_codes() is called
# on the input data before D-code filtering.

PREFIX_MAP <- c(
  # --- Solid tumors by anatomical site ---

  # 1. Lip, Oral Cavity and Pharynx (C00-C14)
  "C00" = "Lip, Oral Cavity and Pharynx",
  "C01" = "Lip, Oral Cavity and Pharynx",
  "C02" = "Lip, Oral Cavity and Pharynx",
  "C03" = "Lip, Oral Cavity and Pharynx",
  "C04" = "Lip, Oral Cavity and Pharynx",
  "C05" = "Lip, Oral Cavity and Pharynx",
  "C06" = "Lip, Oral Cavity and Pharynx",
  "C07" = "Lip, Oral Cavity and Pharynx",
  "C08" = "Lip, Oral Cavity and Pharynx",
  "C09" = "Lip, Oral Cavity and Pharynx",
  "C10" = "Lip, Oral Cavity and Pharynx",
  "C11" = "Lip, Oral Cavity and Pharynx",
  "C12" = "Lip, Oral Cavity and Pharynx",
  "C13" = "Lip, Oral Cavity and Pharynx",
  "C14" = "Lip, Oral Cavity and Pharynx",

  # 2. Esophagus (C15)
  "C15" = "Esophagus",

  # 3. Stomach (C16)
  "C16" = "Stomach",

  # 4. Small Intestine (C17)
  "C17" = "Small Intestine",

  # 5. Colon incl. rectosigmoid junction (C18-C19)
  "C18" = "Colon",
  "C19" = "Colon",

  # 6. Rectum (C20)
  "C20" = "Rectum",

  # 7. Anus (C21)
  "C21" = "Anus",

  # 8. Liver (C22)
  "C22" = "Liver",

  # 9. Pancreas (C25)
  "C25" = "Pancreas",

  # 10. Other Digestive (gallbladder, biliary, other) (C23-C24, C26)
  "C23" = "Other Digestive",
  "C24" = "Other Digestive",
  "C26" = "Other Digestive",

  # 11. Nasal Cavity, Middle Ear, Sinuses (C30-C31)
  "C30" = "Nasal Cavity, Middle Ear, Sinuses",
  "C31" = "Nasal Cavity, Middle Ear, Sinuses",

  # 12. Larynx (C32)
  "C32" = "Larynx",

  # 13. Lung and Bronchus (C33-C34)
  "C33" = "Lung and Bronchus",
  "C34" = "Lung and Bronchus",

  # 14. Other Respiratory/Intrathoracic (C37-C39)
  "C37" = "Other Respiratory/Intrathoracic",
  "C38" = "Other Respiratory/Intrathoracic",
  "C39" = "Other Respiratory/Intrathoracic",

  # 15. Bone (C40-C41)
  "C40" = "Bone",
  "C41" = "Bone",

  # 16. Melanoma of Skin (C43)
  "C43" = "Melanoma of Skin",

  # 17. Other Skin incl. Merkel cell (C44, C4A)
  "C44" = "Other Skin",
  "C4A" = "Other Skin",

  # 18. Mesothelioma (C45)
  "C45" = "Mesothelioma",

  # 19. Kaposi Sarcoma (C46)
  "C46" = "Kaposi Sarcoma",

  # 20. Soft Tissue / Peripheral Nerves (C47-C49)
  "C47" = "Soft Tissue",
  "C48" = "Soft Tissue",
  "C49" = "Soft Tissue",

  # 21. Breast (C50)
  "C50" = "Breast",

  # 22. Cervix Uteri (C53)
  "C53" = "Cervix Uteri",

  # 23. Corpus Uteri (C54-C55)
  "C54" = "Corpus Uteri",
  "C55" = "Corpus Uteri",

  # 24. Ovary (C56)
  "C56" = "Ovary",

  # 25. Other Female Genital (C51-C52, C57-C58)
  "C51" = "Other Female Genital",
  "C52" = "Other Female Genital",
  "C57" = "Other Female Genital",
  "C58" = "Other Female Genital",

  # 26. Prostate (C61)
  "C61" = "Prostate",

  # 27. Testis (C62)
  "C62" = "Testis",

  # 28. Other Male Genital (C60, C63)
  "C60" = "Other Male Genital",
  "C63" = "Other Male Genital",

  # 29. Kidney and Renal Pelvis (C64-C65)
  "C64" = "Kidney and Renal Pelvis",
  "C65" = "Kidney and Renal Pelvis",

  # 30. Bladder (C67)
  "C67" = "Bladder",

  # 31. Other Urinary (C66, C68)
  "C66" = "Other Urinary",
  "C68" = "Other Urinary",

  # 32. Eye and Orbit (C69)
  "C69" = "Eye and Orbit",

  # 33. Brain and CNS (C70-C72)
  "C70" = "Brain and CNS",
  "C71" = "Brain and CNS",
  "C72" = "Brain and CNS",

  # 34. Thyroid (C73)
  "C73" = "Thyroid",

  # 35. Other Endocrine (C74-C75)
  "C74" = "Other Endocrine",
  "C75" = "Other Endocrine",

  # 36. Ill-Defined Sites (C76)
  "C76" = "Ill-Defined Sites",

  # 37. Unknown Primary Site (C80)
  "C80" = "Unknown Primary Site",

  # --- Secondary/metastatic ---

  # 38. Lymph Nodes (secondary) (C77)
  "C77" = "Lymph Nodes (Secondary)",

  # 39. Secondary - Respiratory/Digestive (C78)
  "C78" = "Secondary - Respiratory/Digestive",

  # 40. Secondary - Other Sites (C79)
  "C79" = "Secondary - Other Sites",

  # --- Neuroendocrine ---

  # 41. Neuroendocrine Tumors (C7A, C7B)
  "C7A" = "Neuroendocrine Tumors",
  "C7B" = "Neuroendocrine Tumors",

  # --- Hematologic malignancies ---

  # 42. Hodgkin Lymphoma (C81)
  "C81" = "Hodgkin Lymphoma",

  # 43. Non-Hodgkin Lymphoma (C82-C86, C88)
  "C82" = "Non-Hodgkin Lymphoma",
  "C83" = "Non-Hodgkin Lymphoma",
  "C84" = "Non-Hodgkin Lymphoma",
  "C85" = "Non-Hodgkin Lymphoma",
  "C86" = "Non-Hodgkin Lymphoma",
  "C88" = "Non-Hodgkin Lymphoma",

  # 44. Multiple Myeloma / Plasma Cell (C90)
  "C90" = "Multiple Myeloma",

  # 45. Lymphoid Leukemia (C91)
  "C91" = "Lymphoid Leukemia",

  # 46. Myeloid and Monocytic Leukemia (C92-C93)
  "C92" = "Myeloid and Monocytic Leukemia",
  "C93" = "Myeloid and Monocytic Leukemia",

  # 47. Other Leukemia (C94-C95)
  "C94" = "Other Leukemia",
  "C95" = "Other Leukemia",

  # 48. Other Hematopoietic (C96)
  "C96" = "Other Hematopoietic",

  # --- D-codes: neoplasm-related ---

  # 49. In Situ Neoplasms (D00-D09)
  "D00" = "In Situ Neoplasms",
  "D01" = "In Situ Neoplasms",
  "D02" = "In Situ Neoplasms",
  "D03" = "In Situ Neoplasms",
  "D04" = "In Situ Neoplasms",
  "D05" = "In Situ Neoplasms",
  "D06" = "In Situ Neoplasms",
  "D07" = "In Situ Neoplasms",
  "D09" = "In Situ Neoplasms",

  # 50. Benign Neoplasms (D10-D36, D3A)
  "D10" = "Benign Neoplasms",
  "D11" = "Benign Neoplasms",
  "D12" = "Benign Neoplasms",
  "D13" = "Benign Neoplasms",
  "D14" = "Benign Neoplasms",
  "D15" = "Benign Neoplasms",
  "D16" = "Benign Neoplasms",
  "D17" = "Benign Neoplasms",
  "D18" = "Benign Neoplasms",
  "D19" = "Benign Neoplasms",
  "D20" = "Benign Neoplasms",
  "D21" = "Benign Neoplasms",
  "D22" = "Benign Neoplasms",
  "D23" = "Benign Neoplasms",
  "D24" = "Benign Neoplasms",
  "D25" = "Benign Neoplasms",
  "D26" = "Benign Neoplasms",
  "D27" = "Benign Neoplasms",
  "D28" = "Benign Neoplasms",
  "D29" = "Benign Neoplasms",
  "D30" = "Benign Neoplasms",
  "D31" = "Benign Neoplasms",
  "D32" = "Benign Neoplasms",
  "D33" = "Benign Neoplasms",
  "D34" = "Benign Neoplasms",
  "D35" = "Benign Neoplasms",
  "D36" = "Benign Neoplasms",
  "D3A" = "Benign Neoplasms",

  # 51. Uncertain Behavior Neoplasms (D37-D44, D48)
  "D37" = "Uncertain Behavior Neoplasms",
  "D38" = "Uncertain Behavior Neoplasms",
  "D39" = "Uncertain Behavior Neoplasms",
  "D40" = "Uncertain Behavior Neoplasms",
  "D41" = "Uncertain Behavior Neoplasms",
  "D42" = "Uncertain Behavior Neoplasms",
  "D43" = "Uncertain Behavior Neoplasms",
  "D44" = "Uncertain Behavior Neoplasms",
  "D48" = "Uncertain Behavior Neoplasms",

  # 52. MDS / Myeloproliferative (D45-D47) -- clinically important
  "D45" = "MDS / Myeloproliferative",
  "D46" = "MDS / Myeloproliferative",
  "D47" = "MDS / Myeloproliferative",

  # 53. Unspecified Behavior Neoplasms (D49)
  "D49" = "Unspecified Behavior Neoplasms",

  # --- ICD-O-3 only: hematopoietic site (not in ICD-10) ---
  "C42" = "Hematopoietic System (ICD-O-3)"
)

#' Classify ICD-10 codes into cancer site categories
#' @param codes Character vector of normalized codes (uppercase, no dots)
#' @return Character vector of category names (NA for unclassified)
classify_codes <- function(codes) {
  prefix3 <- substr(codes, 1, 3)
  categories <- unname(PREFIX_MAP[prefix3])
  categories
}

message(glue("Defined {length(unique(PREFIX_MAP))} cancer site categories covering {length(PREFIX_MAP)} prefixes"))

# ==============================================================================
# SECTION 3: LOAD AND FILTER INPUT DATA (CREF-01)
# ==============================================================================

message(glue("\nLoading {INPUT_CSV}..."))

cancer_summary <- read.csv(INPUT_CSV, stringsAsFactors = FALSE)
n_loaded <- nrow(cancer_summary)
message(glue("  Loaded {format(n_loaded, big.mark=',')} patient-code rows"))

# Remove D-codes per CREF-01
n_before_dcode_removal <- nrow(cancer_summary)
cancer_summary <- cancer_summary %>%
  filter(!str_detect(cancer_code, "^D"))
n_removed_dcodes <- n_before_dcode_removal - nrow(cancer_summary)

message(glue("Removed {format(n_removed_dcodes, big.mark=',')} D-code rows ({format(nrow(cancer_summary), big.mark=',')} remaining)"))
message(glue("  Unique patients after D-code removal: {format(n_distinct(cancer_summary$ID), big.mark=',')}"))
message(glue("  Unique codes after D-code removal: {format(n_distinct(cancer_summary$cancer_code), big.mark=',')}"))

# ==============================================================================
# SECTION 4: COHORT CONFIRMATION -- C81 codes, 7-day gap (CREF-02)
# ==============================================================================

message("\nQuerying DIAGNOSIS for C81 cohort confirmation...")

# Query all C81 diagnosis codes from DuckDB
dx_c81 <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^C81")) %>%
  select(ID, DX_norm, DX_DATE) %>%
  collect()

message(glue("  Found {format(nrow(dx_c81), big.mark=',')} C81 diagnosis rows"))

# Deduplicate before date span calculation (Pitfall 1)
# Group by ID only (not per sub-code) -- different C81 sub-codes count toward threshold together
confirmed_patients <- dx_c81 %>%
  filter(!is.na(DX_DATE)) %>%
  distinct(ID, DX_DATE) %>%
  group_by(ID) %>%
  filter(as.numeric(max(DX_DATE) - min(DX_DATE)) >= 7) %>%
  ungroup() %>%
  distinct(ID)

message(glue("Confirmed HL cohort: {format(nrow(confirmed_patients), big.mark=',')} patients (2+ C81 codes, 7-day gap)"))

# ==============================================================================
# SECTION 5: COMPUTE FIRST HL DIAGNOSIS DATE (CREF-03)
# ==============================================================================

message("\nComputing first HL diagnosis date from DIAGNOSIS and TUMOR_REGISTRY...")

# DIAGNOSIS earliest C81 date per patient (reuse dx_c81 from Section 4)
dx_dates <- dx_c81 %>%
  filter(!is.na(DX_DATE)) %>%
  group_by(ID) %>%
  summarise(first_dx_date_diagnosis = min(DX_DATE, na.rm = TRUE), .groups = "drop")

message(glue("  DIAGNOSIS: {format(nrow(dx_dates), big.mark=',')} patients with C81 dates"))

# TUMOR_REGISTRY earliest DATE_OF_DIAGNOSIS per patient
tr_tbl <- tryCatch(get_pcornet_table("TUMOR_REGISTRY_ALL"), error = function(e) NULL)
if (!is.null(tr_tbl) && "DATE_OF_DIAGNOSIS" %in% colnames(tr_tbl)) {
  tr_dates <- tr_tbl %>%
    filter(!is.na(DATE_OF_DIAGNOSIS)) %>%
    group_by(ID) %>%
    summarise(first_dx_date_tr = min(DATE_OF_DIAGNOSIS, na.rm = TRUE), .groups = "drop") %>%
    collect()
  message(glue("  TUMOR_REGISTRY: {format(nrow(tr_dates), big.mark=',')} patients with diagnosis dates"))
} else {
  tr_dates <- data.frame(ID = character(), first_dx_date_tr = as.Date(character()), stringsAsFactors = FALSE)
  message("  TUMOR_REGISTRY: table not found or missing DATE_OF_DIAGNOSIS column")
}

# Compute TRUE minimum with source attribution (per D-05)
first_dx <- dx_dates %>%
  full_join(tr_dates, by = "ID") %>%
  mutate(
    first_hl_dx_date = pmin(first_dx_date_diagnosis, first_dx_date_tr, na.rm = TRUE),
    first_hl_dx_source = case_when(
      is.na(first_dx_date_diagnosis) & !is.na(first_dx_date_tr) ~ "TUMOR_REGISTRY",
      !is.na(first_dx_date_diagnosis) & is.na(first_dx_date_tr) ~ "DIAGNOSIS",
      !is.na(first_dx_date_diagnosis) & !is.na(first_dx_date_tr) &
        first_dx_date_diagnosis == first_dx_date_tr ~ "Both",
      !is.na(first_dx_date_diagnosis) & !is.na(first_dx_date_tr) &
        first_dx_date_diagnosis < first_dx_date_tr ~ "DIAGNOSIS",
      !is.na(first_dx_date_diagnosis) & !is.na(first_dx_date_tr) &
        first_dx_date_tr < first_dx_date_diagnosis ~ "TUMOR_REGISTRY",
      TRUE ~ NA_character_
    )
  ) %>%
  select(ID, first_hl_dx_date, first_hl_dx_source)

# Nullify 1900 sentinel dates (Pitfall 3)
n_sentinel <- sum(year(first_dx$first_hl_dx_date) == 1900L, na.rm = TRUE)
if (n_sentinel > 0) {
  message(glue("  Nullifying {n_sentinel} sentinel first-diagnosis dates (year 1900)"))
  first_dx <- first_dx %>%
    mutate(first_hl_dx_date = if_else(year(first_hl_dx_date) == 1900L, as.Date(NA), first_hl_dx_date))
}

# Log source distribution
source_dist <- first_dx %>%
  filter(!is.na(first_hl_dx_source)) %>%
  count(first_hl_dx_source, name = "n_patients")
message("  First HL diagnosis source distribution:")
for (i in seq_len(nrow(source_dist))) {
  message(glue("    {source_dist$first_hl_dx_source[i]}: {format(source_dist$n_patients[i], big.mark=',')}"))
}

# ==============================================================================
# SECTION 6: SAVE CONFIRMED HL COHORT RDS (D-10)
# ==============================================================================

# Inner join confirmed_patients with first_dx to get only confirmed patients with their dates
confirmed_hl_cohort <- confirmed_patients %>%
  inner_join(first_dx, by = "ID") %>%
  select(ID, first_hl_dx_date, first_hl_dx_source)

saveRDS(confirmed_hl_cohort, OUTPUT_RDS)
message(glue("\nSaved confirmed HL cohort to {OUTPUT_RDS} ({nrow(confirmed_hl_cohort)} patients)"))

# ==============================================================================
# SECTION 7: FILTER CANCER SUMMARY TO CONFIRMED COHORT
# ==============================================================================

n_patients_before_cohort_filter <- n_distinct(cancer_summary$ID)
n_rows_before_cohort_filter <- nrow(cancer_summary)

# Inner join to keep only confirmed HL cohort patients
cancer_summary <- cancer_summary %>%
  inner_join(confirmed_patients, by = "ID")

n_patients_after_cohort_filter <- n_distinct(cancer_summary$ID)
n_rows_after_cohort_filter <- nrow(cancer_summary)

message(glue("\nFiltered to confirmed HL cohort:"))
message(glue("  Patients: {format(n_patients_before_cohort_filter, big.mark=',')} -> {format(n_patients_after_cohort_filter, big.mark=',')}"))
message(glue("  Rows: {format(n_rows_before_cohort_filter, big.mark=',')} -> {format(n_rows_after_cohort_filter, big.mark=',')}"))

# Add category column via classify_codes()
cancer_summary$category <- classify_codes(cancer_summary$cancer_code)

# Handle unclassified codes
n_unclassified <- sum(is.na(cancer_summary$category))
if (n_unclassified > 0) {
  unclass_codes <- unique(cancer_summary$cancer_code[is.na(cancer_summary$category)])
  message(glue("  WARNING: {n_unclassified} rows ({length(unclass_codes)} unique codes) unclassified"))
  message(glue("    Codes: {paste(head(unclass_codes, 20), collapse=', ')}"))
  cancer_summary$category[is.na(cancer_summary$category)] <- "Unclassified"
}

# ==============================================================================
# SECTION 8: QUERY RECORD COUNTS FROM DIAGNOSIS (DuckDB)
# ==============================================================================

message("\nQuerying DIAGNOSIS for record counts...")

dx_record_counts <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^C")) %>%
  group_by(DX_norm) %>%
  summarise(record_count = n(), .groups = "drop") %>%
  collect()

message(glue("  Found record counts for {nrow(dx_record_counts)} unique codes"))

# Left join record counts to cancer_summary
cancer_summary <- cancer_summary %>%
  left_join(dx_record_counts, by = c("cancer_code" = "DX_norm")) %>%
  mutate(record_count = ifelse(is.na(record_count), 0L, as.integer(record_count)))

message(glue("  Total records across all codes: {format(sum(cancer_summary$record_count), big.mark=',')}"))

# ==============================================================================
# SECTION 9: CATEGORY-LEVEL AGGREGATION
# ==============================================================================

message("\nAggregating to category level...")

category_summary <- cancer_summary %>%
  group_by(category) %>%
  summarise(
    total_patients = n_distinct(ID),
    confirmed_2date = n_distinct(ID[two_or_more_unique_dates == 1]),
    pct_confirmed_2date = n_distinct(ID[two_or_more_unique_dates == 1]) / n_distinct(ID),
    confirmed_7day = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]),
    pct_confirmed_7day = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]) / n_distinct(ID),
    mean_unique_dates = mean(unique_dates_total, na.rm = TRUE),
    median_unique_dates = median(unique_dates_total, na.rm = TRUE),
    mean_dates_7day_sep = mean(unique_dates_with_sep_gt_7, na.rm = TRUE),
    median_dates_7day_sep = median(unique_dates_with_sep_gt_7, na.rm = TRUE),
    total_records = sum(record_count, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(total_patients))

message(glue("  Category summary: {nrow(category_summary)} rows"))

# ==============================================================================
# SECTION 10: CODE-LEVEL AGGREGATION
# ==============================================================================

message("Aggregating to code level...")

code_summary <- cancer_summary %>%
  group_by(cancer_code, category) %>%
  summarise(
    total_patients = n_distinct(ID),
    confirmed_2date = n_distinct(ID[two_or_more_unique_dates == 1]),
    pct_confirmed_2date = n_distinct(ID[two_or_more_unique_dates == 1]) / n_distinct(ID),
    confirmed_7day = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]),
    pct_confirmed_7day = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]) / n_distinct(ID),
    mean_unique_dates = mean(unique_dates_total, na.rm = TRUE),
    median_unique_dates = median(unique_dates_total, na.rm = TRUE),
    mean_dates_7day_sep = mean(unique_dates_with_sep_gt_7, na.rm = TRUE),
    median_dates_7day_sep = median(unique_dates_with_sep_gt_7, na.rm = TRUE),
    total_records = sum(record_count, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(total_patients))

message(glue("  Code summary: {nrow(code_summary)} rows"))

# Build totals rows
totals_category <- tibble(
  category              = "TOTAL",
  total_patients        = sum(category_summary$total_patients),
  confirmed_2date       = sum(category_summary$confirmed_2date),
  pct_confirmed_2date   = NA_real_,
  confirmed_7day        = sum(category_summary$confirmed_7day),
  pct_confirmed_7day    = NA_real_,
  mean_unique_dates     = NA_real_,
  median_unique_dates   = NA_real_,
  mean_dates_7day_sep   = NA_real_,
  median_dates_7day_sep = NA_real_,
  total_records         = sum(category_summary$total_records)
)

totals_code <- tibble(
  cancer_code           = "TOTAL",
  category              = "",
  total_patients        = sum(code_summary$total_patients),
  confirmed_2date       = sum(code_summary$confirmed_2date),
  pct_confirmed_2date   = NA_real_,
  confirmed_7day        = sum(code_summary$confirmed_7day),
  pct_confirmed_7day    = NA_real_,
  mean_unique_dates     = NA_real_,
  median_unique_dates   = NA_real_,
  mean_dates_7day_sep   = NA_real_,
  median_dates_7day_sep = NA_real_,
  total_records         = sum(code_summary$total_records)
)

# ==============================================================================
# SECTION 11: WRITE OUTPUTS
# ==============================================================================

message(glue("\nWriting outputs..."))

# -----------------------------------------------
# 11a. Write cancer_summary.csv (7-column format)
# -----------------------------------------------
cancer_summary_output <- cancer_summary %>%
  select(
    ID,
    cancer_code,
    description,
    two_or_more_unique_dates,
    two_or_more_unique_dates_gt_7,
    unique_dates_total,
    unique_dates_with_sep_gt_7
  )

write.csv(cancer_summary_output, OUTPUT_CSV, row.names = FALSE)
message(glue("  Wrote {OUTPUT_CSV} ({nrow(cancer_summary_output)} rows)"))

# -----------------------------------------------
# 11b. Write cancer_summary.xlsx (single flat sheet)
# -----------------------------------------------
wb_flat <- wb_workbook()
wb_flat$add_worksheet("Cancer Summary")

# Write data with headers
wb_flat$add_data(
  sheet = "Cancer Summary", x = as.data.frame(cancer_summary_output),
  start_row = 1, col_names = TRUE
)

# Integer number format for columns 4-7
if (nrow(cancer_summary_output) > 0) {
  last_row <- 1 + nrow(cancer_summary_output)
  wb_flat$add_numfmt(
    sheet = "Cancer Summary",
    dims = glue("D2:G{last_row}"), numfmt = "0"
  )
}

# Auto column widths
wb_flat$set_col_widths(sheet = "Cancer Summary", cols = 1:7, widths = "auto")

# Freeze top row
wb_flat$freeze_pane(sheet = "Cancer Summary", first_row = TRUE)

wb_flat$save(OUTPUT_XLSX)
message(glue("  Wrote {OUTPUT_XLSX}"))

# -----------------------------------------------
# 11c. Write cancer_summary_table.xlsx (two-sheet styled workbook)
# -----------------------------------------------

# Styling constants (same as R/54)
DARK_HEADER_FILL <- "FF374151"
WHITE_FONT <- "FFFFFFFF"
TITLE_FONT_COLOR <- "FF1F2937"
TOTALS_FILL <- "FFE5E7EB"

wb <- wb_workbook()

# ---------------------------------------------------------------------------
# Sheet 1: "Category Summary"
# ---------------------------------------------------------------------------
SHEET1 <- "Category Summary"
wb$add_worksheet(SHEET1)

# Row 1: Title
wb$add_data(
  sheet = SHEET1, x = "Cancer Summary Table - By Category",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = SHEET1, dims = "A1",
  name = "Calibri", size = 16, bold = TRUE,
  color = wb_color(TITLE_FONT_COLOR)
)
wb$merge_cells(sheet = SHEET1, dims = "A1:K1")

# Row 2: Headers
headers1 <- c(
  "Cancer Site Category",
  "Total Patients",
  "Confirmed (2+ Dates)",
  "Rate (2+ Dates)",
  "Confirmed (7-Day Gap)",
  "Rate (7-Day Gap)",
  "Mean Unique Dates",
  "Median Unique Dates",
  "Mean Dates (7-Day Sep)",
  "Median Dates (7-Day Sep)",
  "Total Records"
)
for (i in seq_along(headers1)) {
  wb$add_data(sheet = SHEET1, x = headers1[i], start_row = 2, start_col = i)
}
wb$add_fill(sheet = SHEET1, dims = "A2:K2", color = wb_color(DARK_HEADER_FILL))
wb$add_font(
  sheet = SHEET1, dims = "A2:K2",
  name = "Calibri", size = 11, bold = TRUE,
  color = wb_color(WHITE_FONT)
)

# Freeze pane
wb$freeze_pane(sheet = SHEET1, first_active_row = 3, first_active_col = 1)

# Data rows starting at row 3
data_start1 <- 3
n_data1 <- nrow(category_summary)
data_end1 <- data_start1 + n_data1 - 1

wb$add_data(
  sheet = SHEET1, x = as.data.frame(category_summary),
  start_row = data_start1, col_names = FALSE
)

# Number formatting
# Columns B, C, E (integer counts): "#,##0"
wb$add_numfmt(sheet = SHEET1, dims = glue("B{data_start1}:B{data_end1}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET1, dims = glue("C{data_start1}:C{data_end1}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET1, dims = glue("E{data_start1}:E{data_end1}"), numfmt = "#,##0")
# Columns D, F (percentage rates): "0.0%"
wb$add_numfmt(sheet = SHEET1, dims = glue("D{data_start1}:D{data_end1}"), numfmt = "0.0%")
wb$add_numfmt(sheet = SHEET1, dims = glue("F{data_start1}:F{data_end1}"), numfmt = "0.0%")
# Columns G, H, I, J (mean/median decimals): "0.0"
wb$add_numfmt(sheet = SHEET1, dims = glue("G{data_start1}:G{data_end1}"), numfmt = "0.0")
wb$add_numfmt(sheet = SHEET1, dims = glue("H{data_start1}:H{data_end1}"), numfmt = "0.0")
wb$add_numfmt(sheet = SHEET1, dims = glue("I{data_start1}:I{data_end1}"), numfmt = "0.0")
wb$add_numfmt(sheet = SHEET1, dims = glue("J{data_start1}:J{data_end1}"), numfmt = "0.0")
# Column K (total records): "#,##0"
wb$add_numfmt(sheet = SHEET1, dims = glue("K{data_start1}:K{data_end1}"), numfmt = "#,##0")

# Totals row
totals_row1 <- data_end1 + 1
wb$add_data(
  sheet = SHEET1, x = as.data.frame(totals_category),
  start_row = totals_row1, col_names = FALSE
)
wb$add_fill(
  sheet = SHEET1,
  dims = glue("A{totals_row1}:K{totals_row1}"),
  color = wb_color(TOTALS_FILL)
)
wb$add_font(
  sheet = SHEET1,
  dims = glue("A{totals_row1}:K{totals_row1}"),
  name = "Calibri", size = 11, bold = TRUE,
  color = wb_color(TITLE_FONT_COLOR)
)
wb$add_numfmt(
  sheet = SHEET1,
  dims = glue("B{totals_row1}:B{totals_row1}"),
  numfmt = "#,##0"
)
wb$add_numfmt(
  sheet = SHEET1,
  dims = glue("C{totals_row1}:C{totals_row1}"),
  numfmt = "#,##0"
)
wb$add_numfmt(
  sheet = SHEET1,
  dims = glue("E{totals_row1}:E{totals_row1}"),
  numfmt = "#,##0"
)
wb$add_numfmt(
  sheet = SHEET1,
  dims = glue("K{totals_row1}:K{totals_row1}"),
  numfmt = "#,##0"
)

# Column widths
wb$set_col_widths(
  sheet = SHEET1, cols = 1:11,
  widths = c(40, 14, 18, 14, 18, 14, 16, 16, 18, 18, 14)
)

# ---------------------------------------------------------------------------
# Sheet 2: "Code Summary"
# ---------------------------------------------------------------------------
SHEET2 <- "Code Summary"
wb$add_worksheet(SHEET2)

# Row 1: Title
wb$add_data(
  sheet = SHEET2, x = "Cancer Summary Table - By ICD-10 Code",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = SHEET2, dims = "A1",
  name = "Calibri", size = 16, bold = TRUE,
  color = wb_color(TITLE_FONT_COLOR)
)
wb$merge_cells(sheet = SHEET2, dims = "A1:L1")

# Row 2: Headers
headers2 <- c(
  "ICD-10 Code",
  "Cancer Site Category",
  "Total Patients",
  "Confirmed (2+ Dates)",
  "Rate (2+ Dates)",
  "Confirmed (7-Day Gap)",
  "Rate (7-Day Gap)",
  "Mean Unique Dates",
  "Median Unique Dates",
  "Mean Dates (7-Day Sep)",
  "Median Dates (7-Day Sep)",
  "Total Records"
)
for (i in seq_along(headers2)) {
  wb$add_data(sheet = SHEET2, x = headers2[i], start_row = 2, start_col = i)
}
wb$add_fill(sheet = SHEET2, dims = "A2:L2", color = wb_color(DARK_HEADER_FILL))
wb$add_font(
  sheet = SHEET2, dims = "A2:L2",
  name = "Calibri", size = 11, bold = TRUE,
  color = wb_color(WHITE_FONT)
)

# Freeze pane
wb$freeze_pane(sheet = SHEET2, first_active_row = 3, first_active_col = 1)

# Data rows starting at row 3
data_start2 <- 3
n_data2 <- nrow(code_summary)
data_end2 <- data_start2 + n_data2 - 1

wb$add_data(
  sheet = SHEET2, x = as.data.frame(code_summary),
  start_row = data_start2, col_names = FALSE
)

# Number formatting
# Columns C, D, F (integer counts): "#,##0"
wb$add_numfmt(sheet = SHEET2, dims = glue("C{data_start2}:C{data_end2}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET2, dims = glue("D{data_start2}:D{data_end2}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET2, dims = glue("F{data_start2}:F{data_end2}"), numfmt = "#,##0")
# Columns E, G (percentage rates): "0.0%"
wb$add_numfmt(sheet = SHEET2, dims = glue("E{data_start2}:E{data_end2}"), numfmt = "0.0%")
wb$add_numfmt(sheet = SHEET2, dims = glue("G{data_start2}:G{data_end2}"), numfmt = "0.0%")
# Columns H, I, J, K (mean/median decimals): "0.0"
wb$add_numfmt(sheet = SHEET2, dims = glue("H{data_start2}:H{data_end2}"), numfmt = "0.0")
wb$add_numfmt(sheet = SHEET2, dims = glue("I{data_start2}:I{data_end2}"), numfmt = "0.0")
wb$add_numfmt(sheet = SHEET2, dims = glue("J{data_start2}:J{data_end2}"), numfmt = "0.0")
wb$add_numfmt(sheet = SHEET2, dims = glue("K{data_start2}:K{data_end2}"), numfmt = "0.0")
# Column L (total records): "#,##0"
wb$add_numfmt(sheet = SHEET2, dims = glue("L{data_start2}:L{data_end2}"), numfmt = "#,##0")

# Totals row
totals_row2 <- data_end2 + 1
wb$add_data(
  sheet = SHEET2, x = as.data.frame(totals_code),
  start_row = totals_row2, col_names = FALSE
)
wb$add_fill(
  sheet = SHEET2,
  dims = glue("A{totals_row2}:L{totals_row2}"),
  color = wb_color(TOTALS_FILL)
)
wb$add_font(
  sheet = SHEET2,
  dims = glue("A{totals_row2}:L{totals_row2}"),
  name = "Calibri", size = 11, bold = TRUE,
  color = wb_color(TITLE_FONT_COLOR)
)
wb$add_numfmt(
  sheet = SHEET2,
  dims = glue("C{totals_row2}:C{totals_row2}"),
  numfmt = "#,##0"
)
wb$add_numfmt(
  sheet = SHEET2,
  dims = glue("D{totals_row2}:D{totals_row2}"),
  numfmt = "#,##0"
)
wb$add_numfmt(
  sheet = SHEET2,
  dims = glue("F{totals_row2}:F{totals_row2}"),
  numfmt = "#,##0"
)
wb$add_numfmt(
  sheet = SHEET2,
  dims = glue("L{totals_row2}:L{totals_row2}"),
  numfmt = "#,##0"
)

# Column widths
wb$set_col_widths(
  sheet = SHEET2, cols = 1:12,
  widths = c(14, 40, 14, 18, 14, 18, 14, 16, 16, 18, 18, 14)
)

# ---------------------------------------------------------------------------
# Save workbook
# ---------------------------------------------------------------------------
wb$save(OUTPUT_TABLE_XLSX)

message(glue("  Wrote {OUTPUT_TABLE_XLSX}"))
message(glue("    Sheet '{SHEET1}': {n_data1} data rows + 1 totals row"))
message(glue("    Sheet '{SHEET2}': {n_data2} data rows + 1 totals row"))

# ==============================================================================
# SECTION 12: CLEANUP
# ==============================================================================

close_pcornet_con()

# ==============================================================================
# SECTION 2: OUTPUT ----
# ==============================================================================

message("\n=== Phase 8 complete ===")
