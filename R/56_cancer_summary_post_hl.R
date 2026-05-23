# ==============================================================================
# Phase 56: Cancer Summary - Post-HL Temporal Filtering
# ==============================================================================
# Creates post-HL cancer summary variants filtered to cancer diagnoses occurring
# AFTER each patient's first HL diagnosis date, with EXPLORATORY labeling and
# a side-by-side Comparison sheet.
#
# This script queries the DuckDB DIAGNOSIS table directly for raw date rows,
# applies temporal filtering (DX_DATE > first_hl_dx_date), and re-aggregates
# patient-code metrics. It does NOT modify baseline R/55 outputs.
#
# Inputs:
#   - output/confirmed_hl_cohort.rds (Phase 55 output: ID, first_hl_dx_date, first_hl_dx_source)
#   - output/tables/cancer_summary.csv (Phase 55 output: description lookup only)
#   - output/tables/cancer_summary_table.xlsx (Phase 55 output: baseline counts for Comparison)
#   - DIAGNOSIS DuckDB table (raw DX_DATE rows for temporal filtering)
#
# Outputs:
#   - output/tables/cancer_summary_post_hl.csv (patient-code level, 7 columns)
#   - output/tables/cancer_summary_post_hl.xlsx (single flat sheet, EXPLORATORY)
#   - output/tables/cancer_summary_table_post_hl.xlsx (3-sheet styled workbook)
#
# Usage:
#   Rscript R/56_cancer_summary_post_hl.R
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

# Define input/output paths
INPUT_CSV          <- file.path(CONFIG$output_dir, "tables", "cancer_summary.csv")
INPUT_RDS          <- file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds")
BASELINE_TABLE_XLSX <- file.path(CONFIG$output_dir, "tables", "cancer_summary_table.xlsx")
OUTPUT_CSV         <- file.path(CONFIG$output_dir, "tables", "cancer_summary_post_hl.csv")
OUTPUT_XLSX        <- file.path(CONFIG$output_dir, "tables", "cancer_summary_post_hl.xlsx")
OUTPUT_TABLE_XLSX  <- file.path(CONFIG$output_dir, "tables", "cancer_summary_table_post_hl.xlsx")

dir.create(dirname(OUTPUT_CSV), showWarnings = FALSE, recursive = TRUE)

# Sentinel date cutoff -- any DX_DATE before this is considered invalid/sentinel
SENTINEL_CUTOFF <- as.Date("1910-01-01")

message("=== Phase 56: Cancer Summary - Post-HL Temporal Filtering ===")
message(glue("Input RDS:          {INPUT_RDS}"))
message(glue("Input CSV:          {INPUT_CSV}"))
message(glue("Baseline Table:     {BASELINE_TABLE_XLSX}"))
message(glue("Output CSV:         {OUTPUT_CSV}"))
message(glue("Output XLSX:        {OUTPUT_XLSX}"))
message(glue("Output Table XLSX:  {OUTPUT_TABLE_XLSX}"))
message(glue("Sentinel cutoff:    {SENTINEL_CUTOFF}"))

# ==============================================================================
# SECTION 2: PREFIX_MAP AND classify_codes()
# ==============================================================================
# Copied from R/55 lines 69-338 for script independence.
# All 309 entries including D-codes are retained (input data has no D-codes,
# but full map is kept for completeness and consistency).

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

# Count patients with valid (non-NA) first_hl_dx_date
n_with_date <- sum(!is.na(confirmed_hl_cohort$first_hl_dx_date))
n_excluded_na_date <- sum(is.na(confirmed_hl_cohort$first_hl_dx_date))
message(glue("  Patients with non-NA first_hl_dx_date: {format(n_with_date, big.mark=',')}"))
message(glue("  Patients excluded (NA first_hl_dx_date): {format(n_excluded_na_date, big.mark=',')}"))

# D-06: Filter to only patients with valid first_hl_dx_date
confirmed_hl_cohort <- confirmed_hl_cohort %>%
  filter(!is.na(first_hl_dx_date))

message(glue("  Post-filter cohort size: {format(nrow(confirmed_hl_cohort), big.mark=',')} patients"))

# Load baseline cancer_summary.csv (for description lookup ONLY -- not for temporal filtering)
message(glue("\nLoading baseline {INPUT_CSV} (for description lookup)..."))
cancer_summary_baseline <- read.csv(INPUT_CSV, stringsAsFactors = FALSE)
message(glue("  Baseline cancer_summary: {format(nrow(cancer_summary_baseline), big.mark=',')} rows, {format(n_distinct(cancer_summary_baseline$ID), big.mark=',')} patients"))

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

# Exclude sentinel/invalid dates (DX_DATE before 1910-01-01)
# confirmed_hl_cohort.rds already has 1900 sentinels nullified in first_hl_dx_date,
# but the raw DIAGNOSIS table may still contain 1900-01-01 or other pre-1910 dates
n_sentinel <- sum(!is.na(dx_raw$DX_DATE) & dx_raw$DX_DATE < SENTINEL_CUTOFF)
message(glue("  Sentinel/invalid DX_DATE rows (before {SENTINEL_CUTOFF}): {n_sentinel} -- excluding"))

dx_raw <- dx_raw %>%
  filter(is.na(DX_DATE) | DX_DATE >= SENTINEL_CUTOFF)

message(glue("  After sentinel exclusion: {format(nrow(dx_raw), big.mark=',')} rows"))

# ==============================================================================
# SECTION 5: APPLY TEMPORAL FILTER (DX_DATE > first_hl_dx_date)
# ==============================================================================

message("\nApplying temporal filter: DX_DATE > first_hl_dx_date (strict >)...")

# Join with confirmed_hl_cohort to get first_hl_dx_date per row
dx_with_hl_date <- dx_raw %>%
  inner_join(confirmed_hl_cohort %>% select(ID, first_hl_dx_date), by = "ID")

n_before_filter <- nrow(dx_with_hl_date)

# Filter out rows with NA DX_DATE (cannot compare NA dates)
dx_with_hl_date <- dx_with_hl_date %>%
  filter(!is.na(DX_DATE))

n_after_na_removal <- nrow(dx_with_hl_date)
n_na_dx_date <- n_before_filter - n_after_na_removal

# Apply strict > filter (same-day diagnoses excluded per clinical temporal precedence)
dx_post_hl <- dx_with_hl_date %>%
  filter(DX_DATE > first_hl_dx_date)

n_after_filter <- nrow(dx_post_hl)
n_excluded_temporal <- n_after_na_removal - n_after_filter
n_patients_post_hl <- n_distinct(dx_post_hl$ID)

message(glue("  Total rows before filter: {format(n_before_filter, big.mark=',')}"))
message(glue("  Rows with NA DX_DATE removed: {format(n_na_dx_date, big.mark=',')}"))
message(glue("  Rows excluded by temporal filter: {format(n_excluded_temporal, big.mark=',')}"))
message(glue("  Post-HL rows remaining: {format(n_after_filter, big.mark=',')}"))
message(glue("  Post-HL patients: {format(n_patients_post_hl, big.mark=',')}"))

# ==============================================================================
# SECTION 6: RE-AGGREGATE PATIENT-CODE METRICS
# ==============================================================================

message("\nRe-aggregating patient-code metrics from post-HL rows...")

cancer_summary_post_hl <- dx_post_hl %>%
  distinct(ID, DX_norm, DX_DATE) %>%
  group_by(ID, DX_norm) %>%
  summarise(
    unique_dates_total = as.integer(n_distinct(DX_DATE[!is.na(DX_DATE)])),
    two_or_more_unique_dates = as.integer(n_distinct(DX_DATE[!is.na(DX_DATE)]) >= 2),
    two_or_more_unique_dates_gt_7 = as.integer({
      dates <- DX_DATE[!is.na(DX_DATE)]
      ud <- unique(dates)
      if (length(ud) >= 2) {
        as.numeric(max(ud) - min(ud)) >= 7
      } else {
        FALSE
      }
    }),
    unique_dates_with_sep_gt_7 = {
      dates <- unique(sort(DX_DATE[!is.na(DX_DATE)]))
      if (length(dates) < 2) {
        0L
      } else {
        span <- as.numeric(max(dates) - min(dates))
        if (span < 7) {
          0L
        } else {
          n <- length(dates)
          has_7day_sep <- logical(n)
          for (k in seq_len(n)) {
            diffs <- abs(as.numeric(dates[k] - dates[-k]))
            has_7day_sep[k] <- any(diffs >= 7)
          }
          as.integer(sum(has_7day_sep))
        }
      }
    },
    .groups = "drop"
  ) %>%
  rename(cancer_code = DX_norm)

message(glue("  Patient-code rows: {format(nrow(cancer_summary_post_hl), big.mark=',')}"))
message(glue("  Unique patients: {format(n_distinct(cancer_summary_post_hl$ID), big.mark=',')}"))
message(glue("  Unique codes: {format(n_distinct(cancer_summary_post_hl$cancer_code), big.mark=',')}"))

# ==============================================================================
# SECTION 7: ADD DESCRIPTIONS AND CATEGORY
# ==============================================================================

message("\nAdding descriptions and categories...")

# Build description lookup from baseline cancer_summary.csv
baseline_desc <- cancer_summary_baseline %>%
  distinct(cancer_code, description)

# Add category and description
cancer_summary_post_hl <- cancer_summary_post_hl %>%
  left_join(baseline_desc, by = "cancer_code") %>%
  mutate(
    category = classify_codes(cancer_code),
    description = if_else(is.na(description), category, description)
  )

# Handle unclassified codes
n_unclassified <- sum(is.na(cancer_summary_post_hl$category))
if (n_unclassified > 0) {
  unclass_codes <- unique(cancer_summary_post_hl$cancer_code[is.na(cancer_summary_post_hl$category)])
  message(glue("  WARNING: {n_unclassified} rows ({length(unclass_codes)} unique codes) unclassified"))
  message(glue("    Codes: {paste(head(unclass_codes, 20), collapse=', ')}"))
  cancer_summary_post_hl$category[is.na(cancer_summary_post_hl$category)] <- "Unclassified"
}

message(glue("  Post-HL patient count: {format(n_distinct(cancer_summary_post_hl$ID), big.mark=',')}"))
message(glue("  Post-HL code count: {format(n_distinct(cancer_summary_post_hl$cancer_code), big.mark=',')}"))
message(glue("  Post-HL row count: {format(nrow(cancer_summary_post_hl), big.mark=',')}"))

# ==============================================================================
# SECTION 8: QUERY RECORD COUNTS FROM DIAGNOSIS (DuckDB)
# ==============================================================================

message("\nComputing post-HL record counts...")

# Scope record counts to post-HL rows only
dx_post_hl_records <- dx_post_hl %>%
  group_by(DX_norm) %>%
  summarise(record_count = n(), .groups = "drop")

cancer_summary_post_hl <- cancer_summary_post_hl %>%
  left_join(dx_post_hl_records, by = c("cancer_code" = "DX_norm")) %>%
  mutate(record_count = ifelse(is.na(record_count), 0L, as.integer(record_count)))

message(glue("  Total post-HL records across all codes: {format(sum(cancer_summary_post_hl$record_count), big.mark=',')}"))

# ==============================================================================
# SECTION 9: CATEGORY-LEVEL AGGREGATION
# ==============================================================================

message("\nAggregating to category level (post-HL)...")

category_summary_post_hl <- cancer_summary_post_hl %>%
  group_by(category) %>%
  summarise(
    total_patients        = n_distinct(ID),
    confirmed_2date       = n_distinct(ID[two_or_more_unique_dates == 1]),
    pct_confirmed_2date   = n_distinct(ID[two_or_more_unique_dates == 1]) / n_distinct(ID),
    confirmed_7day        = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]),
    pct_confirmed_7day    = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]) / n_distinct(ID),
    mean_unique_dates     = mean(unique_dates_total, na.rm = TRUE),
    median_unique_dates   = median(unique_dates_total, na.rm = TRUE),
    mean_dates_7day_sep   = mean(unique_dates_with_sep_gt_7, na.rm = TRUE),
    median_dates_7day_sep = median(unique_dates_with_sep_gt_7, na.rm = TRUE),
    total_records         = sum(record_count, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(total_patients))

message(glue("  Category summary: {nrow(category_summary_post_hl)} rows"))

# ==============================================================================
# SECTION 10: CODE-LEVEL AGGREGATION
# ==============================================================================

message("Aggregating to code level (post-HL)...")

code_summary_post_hl <- cancer_summary_post_hl %>%
  group_by(cancer_code, category) %>%
  summarise(
    total_patients        = n_distinct(ID),
    confirmed_2date       = n_distinct(ID[two_or_more_unique_dates == 1]),
    pct_confirmed_2date   = n_distinct(ID[two_or_more_unique_dates == 1]) / n_distinct(ID),
    confirmed_7day        = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]),
    pct_confirmed_7day    = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]) / n_distinct(ID),
    mean_unique_dates     = mean(unique_dates_total, na.rm = TRUE),
    median_unique_dates   = median(unique_dates_total, na.rm = TRUE),
    mean_dates_7day_sep   = mean(unique_dates_with_sep_gt_7, na.rm = TRUE),
    median_dates_7day_sep = median(unique_dates_with_sep_gt_7, na.rm = TRUE),
    total_records         = sum(record_count, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(total_patients))

message(glue("  Code summary: {nrow(code_summary_post_hl)} rows"))

# Build totals rows (same pattern as R/55 lines 570-597)
totals_category_post_hl <- tibble(
  category              = "TOTAL",
  total_patients        = sum(category_summary_post_hl$total_patients),
  confirmed_2date       = sum(category_summary_post_hl$confirmed_2date),
  pct_confirmed_2date   = NA_real_,
  confirmed_7day        = sum(category_summary_post_hl$confirmed_7day),
  pct_confirmed_7day    = NA_real_,
  mean_unique_dates     = NA_real_,
  median_unique_dates   = NA_real_,
  mean_dates_7day_sep   = NA_real_,
  median_dates_7day_sep = NA_real_,
  total_records         = sum(category_summary_post_hl$total_records)
)

totals_code_post_hl <- tibble(
  cancer_code           = "TOTAL",
  category              = "",
  total_patients        = sum(code_summary_post_hl$total_patients),
  confirmed_2date       = sum(code_summary_post_hl$confirmed_2date),
  pct_confirmed_2date   = NA_real_,
  confirmed_7day        = sum(code_summary_post_hl$confirmed_7day),
  pct_confirmed_7day    = NA_real_,
  mean_unique_dates     = NA_real_,
  median_unique_dates   = NA_real_,
  mean_dates_7day_sep   = NA_real_,
  median_dates_7day_sep = NA_real_,
  total_records         = sum(code_summary_post_hl$total_records)
)

# ==============================================================================
# SECTION 11: WRITE OUTPUTS
# ==============================================================================

message(glue("\nWriting outputs..."))

# -----------------------------------------------
# 11a. Write cancer_summary_post_hl.csv (7-column format)
# -----------------------------------------------
cancer_summary_post_hl_output <- cancer_summary_post_hl %>%
  select(
    ID,
    cancer_code,
    description,
    two_or_more_unique_dates,
    two_or_more_unique_dates_gt_7,
    unique_dates_total,
    unique_dates_with_sep_gt_7
  )

write.csv(cancer_summary_post_hl_output, OUTPUT_CSV, row.names = FALSE)
message(glue("  Wrote {OUTPUT_CSV} ({nrow(cancer_summary_post_hl_output)} rows)"))

# -----------------------------------------------
# 11b. Write cancer_summary_post_hl.xlsx (single flat sheet, EXPLORATORY)
# -----------------------------------------------
wb_flat <- wb_workbook()
SHEET_FLAT <- "EXPLORATORY - Cancer Summary"
wb_flat$add_worksheet(SHEET_FLAT)

# Write data with headers
wb_flat$add_data(sheet = SHEET_FLAT, x = as.data.frame(cancer_summary_post_hl_output),
                 start_row = 1, col_names = TRUE)

# Integer number format for columns 4-7
if (nrow(cancer_summary_post_hl_output) > 0) {
  last_row_flat <- 1 + nrow(cancer_summary_post_hl_output)
  wb_flat$add_numfmt(sheet = SHEET_FLAT,
                     dims = glue("D2:G{last_row_flat}"), numfmt = "0")
}

# Auto column widths
wb_flat$set_col_widths(sheet = SHEET_FLAT, cols = 1:7, widths = "auto")

# Freeze top row
wb_flat$freeze_pane(sheet = SHEET_FLAT, first_row = TRUE)

# D-05: Footnote row with bias warning
footnote_row_flat <- last_row_flat + 2
wb_flat$add_data(sheet = SHEET_FLAT,
                 x = "Note: Post-HL filter introduces potential immortal time bias. Use for exploratory comparison only.",
                 start_row = footnote_row_flat, start_col = 1)
wb_flat$add_font(sheet = SHEET_FLAT, dims = glue("A{footnote_row_flat}"),
                 name = "Calibri", size = 10, italic = TRUE,
                 color = wb_color("FF6B7280"))
wb_flat$merge_cells(sheet = SHEET_FLAT, dims = glue("A{footnote_row_flat}:G{footnote_row_flat}"))

wb_flat$save(OUTPUT_XLSX)
message(glue("  Wrote {OUTPUT_XLSX}"))

# -----------------------------------------------
# 11c. Write cancer_summary_table_post_hl.xlsx (three-sheet styled workbook)
# -----------------------------------------------

# Styling constants (same as R/55)
DARK_HEADER_FILL <- "FF374151"
WHITE_FONT       <- "FFFFFFFF"
TITLE_FONT_COLOR <- "FF1F2937"
TOTALS_FILL      <- "FFE5E7EB"

wb <- wb_workbook()

# ---------------------------------------------------------------------------
# Sheet 1: "EXPLORATORY - Category Summary" (per D-04)
# ---------------------------------------------------------------------------
SHEET1 <- "EXPLORATORY - Category Summary"
wb$add_worksheet(SHEET1)

# Row 1: Title
wb$add_data(sheet = SHEET1, x = "Cancer Summary Table - By Category (POST-HL DIAGNOSES ONLY)",
            start_row = 1, start_col = 1)
wb$add_font(sheet = SHEET1, dims = "A1",
            name = "Calibri", size = 16, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$merge_cells(sheet = SHEET1, dims = "A1:K1")

# Row 2: Headers (same 11 headers as R/55 Sheet 1)
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
wb$add_font(sheet = SHEET1, dims = "A2:K2",
            name = "Calibri", size = 11, bold = TRUE,
            color = wb_color(WHITE_FONT))

# Freeze pane
wb$freeze_pane(sheet = SHEET1, first_active_row = 3, first_active_col = 1)

# Data rows starting at row 3
data_start1 <- 3
n_data1     <- nrow(category_summary_post_hl)
data_end1   <- data_start1 + n_data1 - 1

wb$add_data(sheet = SHEET1, x = as.data.frame(category_summary_post_hl),
            start_row = data_start1, col_names = FALSE)

# Number formatting (same as R/55)
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
wb$add_data(sheet = SHEET1, x = as.data.frame(totals_category_post_hl),
            start_row = totals_row1, col_names = FALSE)
wb$add_fill(sheet = SHEET1,
            dims  = glue("A{totals_row1}:K{totals_row1}"),
            color = wb_color(TOTALS_FILL))
wb$add_font(sheet = SHEET1,
            dims  = glue("A{totals_row1}:K{totals_row1}"),
            name  = "Calibri", size = 11, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$add_numfmt(sheet = SHEET1,
              dims  = glue("B{totals_row1}:B{totals_row1}"),
              numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET1,
              dims  = glue("C{totals_row1}:C{totals_row1}"),
              numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET1,
              dims  = glue("E{totals_row1}:E{totals_row1}"),
              numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET1,
              dims  = glue("K{totals_row1}:K{totals_row1}"),
              numfmt = "#,##0")

# D-05: Footnote row with bias warning
footnote_row1 <- totals_row1 + 2
wb$add_data(sheet = SHEET1,
            x = "Note: Post-HL filter introduces potential immortal time bias. Use for exploratory comparison only.",
            start_row = footnote_row1, start_col = 1)
wb$add_font(sheet = SHEET1, dims = glue("A{footnote_row1}"),
            name = "Calibri", size = 10, italic = TRUE,
            color = wb_color("FF6B7280"))
wb$merge_cells(sheet = SHEET1, dims = glue("A{footnote_row1}:K{footnote_row1}"))

# Column widths
wb$set_col_widths(sheet = SHEET1, cols = 1:11,
                  widths = c(40, 14, 18, 14, 18, 14, 16, 16, 18, 18, 14))

# ---------------------------------------------------------------------------
# Sheet 2: "EXPLORATORY - Code Summary" (per D-04)
# ---------------------------------------------------------------------------
SHEET2 <- "EXPLORATORY - Code Summary"
wb$add_worksheet(SHEET2)

# Row 1: Title
wb$add_data(sheet = SHEET2, x = "Cancer Summary Table - By ICD-10 Code (POST-HL DIAGNOSES ONLY)",
            start_row = 1, start_col = 1)
wb$add_font(sheet = SHEET2, dims = "A1",
            name = "Calibri", size = 16, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$merge_cells(sheet = SHEET2, dims = "A1:L1")

# Row 2: Headers (same 12 headers as R/55 Sheet 2)
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
wb$add_font(sheet = SHEET2, dims = "A2:L2",
            name = "Calibri", size = 11, bold = TRUE,
            color = wb_color(WHITE_FONT))

# Freeze pane
wb$freeze_pane(sheet = SHEET2, first_active_row = 3, first_active_col = 1)

# Data rows starting at row 3
data_start2 <- 3
n_data2     <- nrow(code_summary_post_hl)
data_end2   <- data_start2 + n_data2 - 1

wb$add_data(sheet = SHEET2, x = as.data.frame(code_summary_post_hl),
            start_row = data_start2, col_names = FALSE)

# Number formatting (same as R/55)
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
wb$add_data(sheet = SHEET2, x = as.data.frame(totals_code_post_hl),
            start_row = totals_row2, col_names = FALSE)
wb$add_fill(sheet = SHEET2,
            dims  = glue("A{totals_row2}:L{totals_row2}"),
            color = wb_color(TOTALS_FILL))
wb$add_font(sheet = SHEET2,
            dims  = glue("A{totals_row2}:L{totals_row2}"),
            name  = "Calibri", size = 11, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$add_numfmt(sheet = SHEET2,
              dims  = glue("C{totals_row2}:C{totals_row2}"),
              numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET2,
              dims  = glue("D{totals_row2}:D{totals_row2}"),
              numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET2,
              dims  = glue("F{totals_row2}:F{totals_row2}"),
              numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET2,
              dims  = glue("L{totals_row2}:L{totals_row2}"),
              numfmt = "#,##0")

# D-05: Footnote row with bias warning
footnote_row2 <- totals_row2 + 2
wb$add_data(sheet = SHEET2,
            x = "Note: Post-HL filter introduces potential immortal time bias. Use for exploratory comparison only.",
            start_row = footnote_row2, start_col = 1)
wb$add_font(sheet = SHEET2, dims = glue("A{footnote_row2}"),
            name = "Calibri", size = 10, italic = TRUE,
            color = wb_color("FF6B7280"))
wb$merge_cells(sheet = SHEET2, dims = glue("A{footnote_row2}:L{footnote_row2}"))

# Column widths
wb$set_col_widths(sheet = SHEET2, cols = 1:12,
                  widths = c(14, 40, 14, 18, 14, 18, 14, 16, 16, 18, 18, 14))

# ---------------------------------------------------------------------------
# Sheet 3: "Comparison" (per D-03)
# ---------------------------------------------------------------------------
SHEET3 <- "Comparison"
wb$add_worksheet(SHEET3)

# Row 1: Title
wb$add_data(sheet = SHEET3, x = "Baseline vs Post-HL Comparison - By Cancer Site Category",
            start_row = 1, start_col = 1)
wb$add_font(sheet = SHEET3, dims = "A1",
            name = "Calibri", size = 16, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$merge_cells(sheet = SHEET3, dims = "A1:E1")

# Row 2: Headers
headers3 <- c(
  "Cancer Site Category",
  "Baseline Patients",
  "Post-HL Patients",
  "Delta",
  "% Retained"
)
for (i in seq_along(headers3)) {
  wb$add_data(sheet = SHEET3, x = headers3[i], start_row = 2, start_col = i)
}
wb$add_fill(sheet = SHEET3, dims = "A2:E2", color = wb_color(DARK_HEADER_FILL))
wb$add_font(sheet = SHEET3, dims = "A2:E2",
            name = "Calibri", size = 11, bold = TRUE,
            color = wb_color(WHITE_FONT))

# Freeze pane
wb$freeze_pane(sheet = SHEET3, first_active_row = 3, first_active_col = 1)

# Build comparison_df by reading baseline counts from cancer_summary_table.xlsx
# R/55 writes: Row 1 = title (merged), Row 2 = headers, Row 3+ = data
# Use start_row = 2 to skip title row and use row 2 (headers) as column names
baseline_raw <- openxlsx2::read_xlsx(BASELINE_TABLE_XLSX, sheet = "Category Summary", start_row = 2)

baseline_category <- baseline_raw %>%
  filter(`Cancer Site Category` != "TOTAL" & !is.na(`Cancer Site Category`)) %>%
  select(category = `Cancer Site Category`, baseline_patients = `Total Patients`) %>%
  mutate(baseline_patients = as.integer(baseline_patients))

comparison_df <- category_summary_post_hl %>%
  select(category, post_hl_patients = total_patients) %>%
  full_join(baseline_category, by = "category") %>%
  mutate(
    baseline_patients = ifelse(is.na(baseline_patients), 0L, baseline_patients),
    post_hl_patients = ifelse(is.na(post_hl_patients), 0L, post_hl_patients)
  ) %>%
  mutate(
    delta = post_hl_patients - baseline_patients,
    pct_retained = if_else(baseline_patients > 0L,
                           as.numeric(post_hl_patients) / as.numeric(baseline_patients),
                           NA_real_)
  ) %>%
  arrange(desc(baseline_patients))

message(glue("  Comparison: {nrow(comparison_df)} categories"))

# Data rows starting at row 3
data_start3 <- 3
n_data3     <- nrow(comparison_df)
data_end3   <- data_start3 + n_data3 - 1

wb$add_data(sheet = SHEET3, x = as.data.frame(comparison_df),
            start_row = data_start3, col_names = FALSE)

# Number formatting
# Columns B, C (integer counts): "#,##0"
wb$add_numfmt(sheet = SHEET3, dims = glue("B{data_start3}:B{data_end3}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET3, dims = glue("C{data_start3}:C{data_end3}"), numfmt = "#,##0")
# Column D (delta, signed integer): "#,##0"
wb$add_numfmt(sheet = SHEET3, dims = glue("D{data_start3}:D{data_end3}"), numfmt = "#,##0")
# Column E (percentage): "0.0%"
wb$add_numfmt(sheet = SHEET3, dims = glue("E{data_start3}:E{data_end3}"), numfmt = "0.0%")

# Info rows below data (per D-06 and sentinel tracking)
info_start <- data_end3 + 2
wb$add_data(sheet = SHEET3,
            x = glue("Patients excluded (NA first_hl_dx_date): {n_excluded_na_date}"),
            start_row = info_start, start_col = 1)
wb$add_font(sheet = SHEET3, dims = glue("A{info_start}"),
            name = "Calibri", size = 10, italic = TRUE,
            color = wb_color("FF6B7280"))

wb$add_data(sheet = SHEET3,
            x = "Temporal filter: DX_DATE > first_hl_dx_date (strict, excludes same-day)",
            start_row = info_start + 1, start_col = 1)
wb$add_font(sheet = SHEET3, dims = glue("A{info_start + 1}"),
            name = "Calibri", size = 10, italic = TRUE,
            color = wb_color("FF6B7280"))

wb$add_data(sheet = SHEET3,
            x = glue("Sentinel dates excluded (DX_DATE < {SENTINEL_CUTOFF}): {n_sentinel}"),
            start_row = info_start + 2, start_col = 1)
wb$add_font(sheet = SHEET3, dims = glue("A{info_start + 2}"),
            name = "Calibri", size = 10, italic = TRUE,
            color = wb_color("FF6B7280"))

# Column widths
wb$set_col_widths(sheet = SHEET3, cols = 1:5,
                  widths = c(40, 18, 18, 10, 14))

# ---------------------------------------------------------------------------
# Save workbook
# ---------------------------------------------------------------------------
wb$save(OUTPUT_TABLE_XLSX)

message(glue("  Wrote {OUTPUT_TABLE_XLSX}"))
message(glue("    Sheet '{SHEET1}': {n_data1} data rows + 1 totals row"))
message(glue("    Sheet '{SHEET2}': {n_data2} data rows + 1 totals row"))
message(glue("    Sheet '{SHEET3}': {n_data3} comparison rows"))

# ==============================================================================
# SECTION 12: CLEANUP
# ==============================================================================

close_pcornet_con()

message("\n=== Phase 56 complete ===")
message(glue("  Post-HL cancer summary: {format(n_distinct(cancer_summary_post_hl$ID), big.mark=',')} patients, {format(nrow(cancer_summary_post_hl), big.mark=',')} rows"))
message(glue("  Baseline files UNCHANGED (cancer_summary.csv, cancer_summary_table.xlsx)"))
