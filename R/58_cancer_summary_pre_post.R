# ==============================================================================
# Phase 58: Cancer Summary - Pre/Post HL Counts
# ==============================================================================
# Creates cancer_summary_table_pre_post.xlsx -- a two-sheet styled workbook
# showing per-cancer-code patient counts split by timing relative to first HL
# diagnosis date (pre-HL, post-HL, both). Population is the confirmed 7-day HL
# cohort. Counts only, no percentages. C81 excluded since it is the anchor diagnosis.
#
# This script answers the clinical question "what other cancers did HL patients
# have before vs after their HL diagnosis?" by splitting baseline cancer summary
# metrics into temporal partitions relative to each patient's first HL diagnosis date.
#
# Inputs:
#   - output/confirmed_hl_cohort.rds (Phase 55 output: ID, first_hl_dx_date, first_hl_dx_source)
#   - output/tables/cancer_summary.csv (Phase 55 output: for baseline metrics)
#   - DIAGNOSIS DuckDB table (for per-code pre/post/both counts)
#
# Outputs:
#   - output/tables/cancer_summary_table_pre_post.xlsx (two-sheet styled workbook)
#   - output/tables/cancer_summary_table_pre_post.csv (companion CSV)
#
# Usage:
#   Rscript R/58_cancer_summary_pre_post.R
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP
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

# Define paths
INPUT_RDS        <- file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds")
INPUT_CSV        <- file.path(CONFIG$output_dir, "tables", "cancer_summary.csv")
OUTPUT_TABLE_XLSX <- file.path(CONFIG$output_dir, "tables", "cancer_summary_table_pre_post.xlsx")
OUTPUT_CSV       <- file.path(CONFIG$output_dir, "tables", "cancer_summary_table_pre_post.csv")

dir.create(dirname(OUTPUT_TABLE_XLSX), showWarnings = FALSE, recursive = TRUE)

# Sentinel date cutoff (per D-11)
SENTINEL_CUTOFF <- as.Date("1910-01-01")

message("=== Phase 58: Cancer Summary - Pre/Post HL Counts ===")
message(glue("Input RDS:          {INPUT_RDS}"))
message(glue("Input CSV:          {INPUT_CSV}"))
message(glue("Output Table XLSX:  {OUTPUT_TABLE_XLSX}"))
message(glue("Output CSV:         {OUTPUT_CSV}"))
message(glue("Sentinel cutoff:    {SENTINEL_CUTOFF}"))

# ==============================================================================
# SECTION 2: PREFIX_MAP AND classify_codes()
# ==============================================================================
# Copied from R/55 lines 69-338 for script independence (all 309 entries)

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
# SECTION 3: LOAD INPUTS
# ==============================================================================

message(glue("\nLoading confirmed HL cohort from {INPUT_RDS}..."))
confirmed_hl_cohort <- readRDS(INPUT_RDS)
n_total_confirmed <- nrow(confirmed_hl_cohort)
message(glue("  Total confirmed HL patients: {format(n_total_confirmed, big.mark=',')}"))

# Filter to patients with non-NA first_hl_dx_date (same pattern as R/56)
n_with_date <- sum(!is.na(confirmed_hl_cohort$first_hl_dx_date))
n_excluded_na_date <- sum(is.na(confirmed_hl_cohort$first_hl_dx_date))
message(glue("  Patients with non-NA first_hl_dx_date: {format(n_with_date, big.mark=',')}"))
message(glue("  Patients excluded (NA first_hl_dx_date): {format(n_excluded_na_date, big.mark=',')}"))

confirmed_hl_cohort <- confirmed_hl_cohort %>%
  filter(!is.na(first_hl_dx_date))

message(glue("  Post-filter cohort size: {format(nrow(confirmed_hl_cohort), big.mark=',')} patients"))

# Load baseline cancer_summary.csv (for baseline metrics per D-01)
message(glue("\nLoading baseline {INPUT_CSV}..."))
cancer_summary <- read.csv(INPUT_CSV, stringsAsFactors = FALSE)
n_loaded <- nrow(cancer_summary)
message(glue("  Loaded {format(n_loaded, big.mark=',')} patient-code rows"))

# Filter cancer_summary: remove D-codes, remove C81, filter to confirmed cohort
cancer_summary <- cancer_summary %>%
  filter(!str_detect(cancer_code, "^D")) %>%
  filter(!str_detect(cancer_code, "^C81")) %>%
  inner_join(confirmed_hl_cohort %>% select(ID), by = "ID")

message(glue("  After D-code removal, C81 removal, and cohort filter: {format(nrow(cancer_summary), big.mark=',')} rows"))
message(glue("  Unique patients: {format(n_distinct(cancer_summary$ID), big.mark=',')}"))
message(glue("  Unique codes: {format(n_distinct(cancer_summary$cancer_code), big.mark=',')}"))

# ==============================================================================
# SECTION 4: QUERY DIAGNOSIS FOR RAW DATE ROWS
# ==============================================================================

message("\nQuerying DIAGNOSIS for C-code diagnosis rows...")

cohort_ids <- confirmed_hl_cohort$ID

dx_raw <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^C")) %>%
  select(ID, DX_norm, DX_DATE) %>%
  collect() %>%
  filter(ID %in% cohort_ids)

message(glue("  Retrieved {format(nrow(dx_raw), big.mark=',')} C-code diagnosis rows for cohort"))

# Exclude sentinel dates (per D-11)
n_sentinel <- sum(!is.na(dx_raw$DX_DATE) & dx_raw$DX_DATE < SENTINEL_CUTOFF)
message(glue("  Sentinel/invalid DX_DATE rows (before {SENTINEL_CUTOFF}): {n_sentinel} -- excluding"))

dx_raw <- dx_raw %>%
  filter(is.na(DX_DATE) | DX_DATE >= SENTINEL_CUTOFF)

message(glue("  After sentinel exclusion: {format(nrow(dx_raw), big.mark=',')} rows"))

# Exclude C81 rows from dx_raw (per D-09)
n_before_c81_removal <- nrow(dx_raw)
dx_raw <- dx_raw %>%
  filter(!str_detect(DX_norm, "^C81"))
n_removed_c81 <- n_before_c81_removal - nrow(dx_raw)

message(glue("  C81 rows excluded: {format(n_removed_c81, big.mark=',')} ({format(nrow(dx_raw), big.mark=',')} remaining)"))

# ==============================================================================
# SECTION 5: COMPUTE PRE/POST/BOTH SETS
# ==============================================================================

message("\nComputing pre/post/both patient-code sets...")

# Join dx_raw with confirmed_hl_cohort to get first_hl_dx_date per row
dx_with_hl_date <- dx_raw %>%
  inner_join(confirmed_hl_cohort %>% select(ID, first_hl_dx_date), by = "ID") %>%
  filter(!is.na(DX_DATE))

message(glue("  Rows with valid DX_DATE: {format(nrow(dx_with_hl_date), big.mark=',')}"))

# Pre-HL: DX_DATE <= first_hl_dx_date (same-day included per D-08)
dx_pre_hl <- dx_with_hl_date %>%
  filter(DX_DATE <= first_hl_dx_date)

# Post-HL: DX_DATE > first_hl_dx_date (strict > per D-08)
dx_post_hl <- dx_with_hl_date %>%
  filter(DX_DATE > first_hl_dx_date)

message(glue("  Pre-HL rows: {format(nrow(dx_pre_hl), big.mark=',')}"))
message(glue("  Post-HL rows: {format(nrow(dx_post_hl), big.mark=',')}"))

# Compute patient-code pairs per temporal set (per D-04)
patients_pre <- dx_pre_hl %>%
  distinct(ID, DX_norm) %>%
  rename(cancer_code = DX_norm)

patients_post <- dx_post_hl %>%
  distinct(ID, DX_norm) %>%
  rename(cancer_code = DX_norm)

patients_both <- patients_pre %>%
  inner_join(patients_post, by = c("ID", "cancer_code"))

message(glue("  Pre-HL patient-code pairs: {format(nrow(patients_pre), big.mark=',')} ({format(n_distinct(patients_pre$ID), big.mark=',')} patients)"))
message(glue("  Post-HL patient-code pairs: {format(nrow(patients_post), big.mark=',')} ({format(n_distinct(patients_post$ID), big.mark=',')} patients)"))
message(glue("  Both (intersection): {format(nrow(patients_both), big.mark=',')} patient-code pairs ({format(n_distinct(patients_both$ID), big.mark=',')} patients)"))

# Aggregate counts by code
pre_counts <- patients_pre %>%
  group_by(cancer_code) %>%
  summarise(pre_hl_count = n_distinct(ID), .groups = "drop")

post_counts <- patients_post %>%
  group_by(cancer_code) %>%
  summarise(post_hl_count = n_distinct(ID), .groups = "drop")

both_counts <- patients_both %>%
  group_by(cancer_code) %>%
  summarise(both_count = n_distinct(ID), .groups = "drop")

message(glue("  Pre-HL codes: {nrow(pre_counts)}"))
message(glue("  Post-HL codes: {nrow(post_counts)}"))
message(glue("  Both codes: {nrow(both_counts)}"))

# ==============================================================================
# SECTION 6: COMPUTE BASELINE METRICS
# ==============================================================================

message("\nComputing baseline metrics from cancer_summary...")

# Code-level baseline metrics (already filtered to confirmed cohort, no D-codes, no C81)
code_baseline <- cancer_summary %>%
  group_by(cancer_code) %>%
  summarise(
    total_patients  = n_distinct(ID),
    confirmed_2date = n_distinct(ID[two_or_more_unique_dates == 1]),
    confirmed_7day  = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]),
    .groups = "drop"
  )

message(glue("  Baseline code summary: {nrow(code_baseline)} codes"))

# Query DuckDB record counts per code (filtered to confirmed cohort IDs, excluding C81)
message("\nQuerying DIAGNOSIS for record counts...")

dx_record_counts <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^C")) %>%
  filter(!str_detect(DX_norm, "^C81")) %>%
  group_by(DX_norm) %>%
  summarise(total_records = n(), .groups = "drop") %>%
  collect()

message(glue("  Record counts for {nrow(dx_record_counts)} codes"))

# Add category via classify_codes()
code_baseline <- code_baseline %>%
  mutate(category = classify_codes(cancer_code))

# Handle unclassified codes
n_unclassified <- sum(is.na(code_baseline$category))
if (n_unclassified > 0) {
  unclass_codes <- unique(code_baseline$cancer_code[is.na(code_baseline$category)])
  message(glue("  WARNING: {n_unclassified} codes unclassified"))
  message(glue("    Codes: {paste(head(unclass_codes, 20), collapse=', ')}"))
  code_baseline$category[is.na(code_baseline$category)] <- "Unclassified"
}

# ==============================================================================
# SECTION 7: MERGE AND BUILD CODE-LEVEL TABLE
# ==============================================================================

message("\nBuilding code-level summary table...")

code_summary <- code_baseline %>%
  left_join(pre_counts, by = "cancer_code") %>%
  left_join(post_counts, by = "cancer_code") %>%
  left_join(both_counts, by = "cancer_code") %>%
  left_join(dx_record_counts, by = c("cancer_code" = "DX_norm")) %>%
  mutate(
    pre_hl_count  = replace(pre_hl_count, is.na(pre_hl_count), 0L),
    post_hl_count = replace(post_hl_count, is.na(post_hl_count), 0L),
    both_count    = replace(both_count, is.na(both_count), 0L),
    total_records = replace(total_records, is.na(total_records), 0L)
  )

# Select columns per D-07 ordering
code_summary <- code_summary %>%
  select(cancer_code, category, total_patients, confirmed_2date, confirmed_7day,
         pre_hl_count, post_hl_count, both_count, total_records) %>%
  arrange(desc(total_patients))

message(glue("  Code summary: {nrow(code_summary)} rows"))

# ==============================================================================
# SECTION 8: BUILD CATEGORY-LEVEL TABLE
# ==============================================================================

message("\nAggregating to category level...")

category_summary <- code_summary %>%
  group_by(category) %>%
  summarise(
    total_patients  = sum(total_patients),
    confirmed_2date = sum(confirmed_2date),
    confirmed_7day  = sum(confirmed_7day),
    pre_hl_count    = sum(pre_hl_count),
    post_hl_count   = sum(post_hl_count),
    both_count      = sum(both_count),
    total_records   = sum(total_records),
    .groups = "drop"
  ) %>%
  arrange(desc(total_patients))

message(glue("  Category summary: {nrow(category_summary)} rows"))

# Build totals rows
totals_category <- tibble(
  category        = "TOTAL",
  total_patients  = sum(category_summary$total_patients),
  confirmed_2date = sum(category_summary$confirmed_2date),
  confirmed_7day  = sum(category_summary$confirmed_7day),
  pre_hl_count    = sum(category_summary$pre_hl_count),
  post_hl_count   = sum(category_summary$post_hl_count),
  both_count      = sum(category_summary$both_count),
  total_records   = sum(category_summary$total_records)
)

totals_code <- tibble(
  cancer_code     = "TOTAL",
  category        = "",
  total_patients  = sum(code_summary$total_patients),
  confirmed_2date = sum(code_summary$confirmed_2date),
  confirmed_7day  = sum(code_summary$confirmed_7day),
  pre_hl_count    = sum(code_summary$pre_hl_count),
  post_hl_count   = sum(code_summary$post_hl_count),
  both_count      = sum(code_summary$both_count),
  total_records   = sum(code_summary$total_records)
)

# ==============================================================================
# SECTION 9: WRITE XLSX OUTPUT
# ==============================================================================

message(glue("\nWriting {OUTPUT_TABLE_XLSX}..."))

# Styling constants (same as R/55 per D-16)
DARK_HEADER_FILL <- "FF374151"
WHITE_FONT       <- "FFFFFFFF"
TITLE_FONT_COLOR <- "FF1F2937"
TOTALS_FILL      <- "FFE5E7EB"

wb <- wb_workbook()

# ---------------------------------------------------------------------------
# Sheet 1: "Category Summary" (per D-06, D-15)
# ---------------------------------------------------------------------------
SHEET1 <- "Category Summary"
wb$add_worksheet(SHEET1)

# Row 1: Title
wb$add_data(sheet = SHEET1, x = "Cancer Summary Table - Pre/Post HL Diagnosis (By Category)",
            start_row = 1, start_col = 1)
wb$add_font(sheet = SHEET1, dims = "A1",
            name = "Calibri", size = 16, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$merge_cells(sheet = SHEET1, dims = "A1:H1")

# Row 2: Headers (per D-06 ordering)
headers1 <- c(
  "Cancer Site Category",
  "Total Patients",
  "Confirmed (2+ Dates)",
  "Confirmed (7-Day Gap)",
  "Pre-HL",
  "Post-HL",
  "Both",
  "Total Records"
)
for (i in seq_along(headers1)) {
  wb$add_data(sheet = SHEET1, x = headers1[i], start_row = 2, start_col = i)
}
wb$add_fill(sheet = SHEET1, dims = "A2:H2", color = wb_color(DARK_HEADER_FILL))
wb$add_font(sheet = SHEET1, dims = "A2:H2",
            name = "Calibri", size = 11, bold = TRUE,
            color = wb_color(WHITE_FONT))

# Freeze pane
wb$freeze_pane(sheet = SHEET1, first_active_row = 3, first_active_col = 1)

# Data rows starting at row 3
data_start1 <- 3
n_data1     <- nrow(category_summary)
data_end1   <- data_start1 + n_data1 - 1

wb$add_data(sheet = SHEET1, x = as.data.frame(category_summary),
            start_row = data_start1, col_names = FALSE)

# Number formatting: All count columns use "#,##0" (per D-05)
wb$add_numfmt(sheet = SHEET1, dims = glue("B{data_start1}:H{data_end1}"), numfmt = "#,##0")

# Totals row
totals_row1 <- data_end1 + 1
wb$add_data(sheet = SHEET1, x = as.data.frame(totals_category),
            start_row = totals_row1, col_names = FALSE)
wb$add_fill(sheet = SHEET1,
            dims  = glue("A{totals_row1}:H{totals_row1}"),
            color = wb_color(TOTALS_FILL))
wb$add_font(sheet = SHEET1,
            dims  = glue("A{totals_row1}:H{totals_row1}"),
            name  = "Calibri", size = 11, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$add_numfmt(sheet = SHEET1,
              dims  = glue("B{totals_row1}:H{totals_row1}"),
              numfmt = "#,##0")

# Footnote row
footnote_row1 <- totals_row1 + 2
footnote_text1 <- glue("Population: Confirmed 7-day HL cohort ({nrow(confirmed_hl_cohort)} patients). Pre: DX_DATE <= first_hl_dx_date. Post: DX_DATE > first_hl_dx_date. Both: patient had code pre AND post. C81 excluded.")
wb$add_data(sheet = SHEET1,
            x = footnote_text1,
            start_row = footnote_row1, start_col = 1)
wb$add_font(sheet = SHEET1, dims = glue("A{footnote_row1}"),
            name = "Calibri", size = 10, italic = TRUE,
            color = wb_color("FF6B7280"))
wb$merge_cells(sheet = SHEET1, dims = glue("A{footnote_row1}:H{footnote_row1}"))

# Column widths
wb$set_col_widths(sheet = SHEET1, cols = 1:8,
                  widths = c(40, 14, 18, 18, 10, 10, 10, 14))

# ---------------------------------------------------------------------------
# Sheet 2: "Code Summary" (per D-07, D-15)
# ---------------------------------------------------------------------------
SHEET2 <- "Code Summary"
wb$add_worksheet(SHEET2)

# Row 1: Title
wb$add_data(sheet = SHEET2, x = "Cancer Summary Table - Pre/Post HL Diagnosis (By ICD-10 Code)",
            start_row = 1, start_col = 1)
wb$add_font(sheet = SHEET2, dims = "A1",
            name = "Calibri", size = 16, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$merge_cells(sheet = SHEET2, dims = "A1:I1")

# Row 2: Headers (per D-07 ordering)
headers2 <- c(
  "ICD-10 Code",
  "Cancer Site Category",
  "Total Patients",
  "Confirmed (2+ Dates)",
  "Confirmed (7-Day Gap)",
  "Pre-HL",
  "Post-HL",
  "Both",
  "Total Records"
)
for (i in seq_along(headers2)) {
  wb$add_data(sheet = SHEET2, x = headers2[i], start_row = 2, start_col = i)
}
wb$add_fill(sheet = SHEET2, dims = "A2:I2", color = wb_color(DARK_HEADER_FILL))
wb$add_font(sheet = SHEET2, dims = "A2:I2",
            name = "Calibri", size = 11, bold = TRUE,
            color = wb_color(WHITE_FONT))

# Freeze pane
wb$freeze_pane(sheet = SHEET2, first_active_row = 3, first_active_col = 1)

# Data rows starting at row 3
data_start2 <- 3
n_data2     <- nrow(code_summary)
data_end2   <- data_start2 + n_data2 - 1

wb$add_data(sheet = SHEET2, x = as.data.frame(code_summary),
            start_row = data_start2, col_names = FALSE)

# Number formatting: All count columns use "#,##0" (per D-05)
wb$add_numfmt(sheet = SHEET2, dims = glue("C{data_start2}:I{data_end2}"), numfmt = "#,##0")

# Totals row
totals_row2 <- data_end2 + 1
wb$add_data(sheet = SHEET2, x = as.data.frame(totals_code),
            start_row = totals_row2, col_names = FALSE)
wb$add_fill(sheet = SHEET2,
            dims  = glue("A{totals_row2}:I{totals_row2}"),
            color = wb_color(TOTALS_FILL))
wb$add_font(sheet = SHEET2,
            dims  = glue("A{totals_row2}:I{totals_row2}"),
            name  = "Calibri", size = 11, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$add_numfmt(sheet = SHEET2,
              dims  = glue("C{totals_row2}:I{totals_row2}"),
              numfmt = "#,##0")

# Footnote row
footnote_row2 <- totals_row2 + 2
footnote_text2 <- glue("Population: Confirmed 7-day HL cohort ({nrow(confirmed_hl_cohort)} patients). Pre: DX_DATE <= first_hl_dx_date. Post: DX_DATE > first_hl_dx_date. Both: patient had code pre AND post. C81 excluded.")
wb$add_data(sheet = SHEET2,
            x = footnote_text2,
            start_row = footnote_row2, start_col = 1)
wb$add_font(sheet = SHEET2, dims = glue("A{footnote_row2}"),
            name = "Calibri", size = 10, italic = TRUE,
            color = wb_color("FF6B7280"))
wb$merge_cells(sheet = SHEET2, dims = glue("A{footnote_row2}:I{footnote_row2}"))

# Column widths
wb$set_col_widths(sheet = SHEET2, cols = 1:9,
                  widths = c(14, 40, 14, 18, 18, 10, 10, 10, 14))

# ---------------------------------------------------------------------------
# Save workbook
# ---------------------------------------------------------------------------
wb$save(OUTPUT_TABLE_XLSX)

message(glue("  Wrote {OUTPUT_TABLE_XLSX}"))
message(glue("    Sheet '{SHEET1}': {n_data1} data rows + 1 totals row"))
message(glue("    Sheet '{SHEET2}': {n_data2} data rows + 1 totals row"))

# ==============================================================================
# SECTION 10: WRITE COMPANION CSV
# ==============================================================================

message(glue("\nWriting companion CSV to {OUTPUT_CSV}..."))

write.csv(code_summary, OUTPUT_CSV, row.names = FALSE)
message(glue("  Wrote {OUTPUT_CSV} ({nrow(code_summary)} rows)"))

# ==============================================================================
# SECTION 11: CLEANUP
# ==============================================================================

close_pcornet_con()

message("\n=== Phase 58 complete ===")
message(glue("  Code summary: {nrow(code_summary)} cancer codes"))
message(glue("  Category summary: {nrow(category_summary)} cancer site categories"))
message(glue("  Pre-HL patient count: {totals_category$pre_hl_count}"))
message(glue("  Post-HL patient count: {totals_category$post_hl_count}"))
message(glue("  Both (intersection): {totals_category$both_count}"))
