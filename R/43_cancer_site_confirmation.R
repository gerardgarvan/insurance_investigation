# ==============================================================================
# 43_cancer_site_confirmation.R
# ==============================================================================
# Purpose: Confirm cancer site codes by requiring 2+ distinct diagnosis dates per
#          code per patient -- filters out single-encounter incidental findings.
#          Two confirmation levels: exact code and cancer site category.
#
# Inputs:  DIAGNOSIS DuckDB table (ICD-10 codes, DX_TYPE == "10", DX_DATE)
#
# Outputs: output/tables/cancer_site_confirmation.xlsx
#          - Sheet 1 "Exact Code": per-category confirmation at exact ICD-10 code level
#          - Sheet 2 "Cancer Site Category": per-category confirmation across all codes in category
#
# Dependencies: R/00_config.R, R/01_load_pcornet.R, CANCER_SITE_MAP (R/00_config.R),
#               classify_codes() (R/utils/utils_cancer.R)
#
# Requirements: Two confirmation levels (per D-01):
#               1. Exact Code: C81.10 must appear on 2+ distinct dates
#               2. Site Category: any code in same category on 2+ distinct dates
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")

# SECTION 0: INPUT VALIDATION ----
# SAFE-02: Validate DIAGNOSIS table is available
assert_df_valid(
  pcornet$DIAGNOSIS, "DIAGNOSIS",
  required_cols = c("ID", "DX", "DX_TYPE", "DX_DATE"),
  script_name = "R/43"
)

OUTPUT_PATH <- build_output_path("tables", "cancer_site_confirmation.xlsx")

message("=== Phase 3: Cancer Site Confirmation by Distinct Date Count ===")
message(glue("Output: {OUTPUT_PATH}"))

# CANCER_SITE_MAP and classify_codes() provided by R/00_config.R + R/utils/utils_cancer.R

# Desired display order for categories in the output
CATEGORY_ORDER <- c(
  "Lip, Oral Cavity and Pharynx",
  "Esophagus",
  "Stomach",
  "Small Intestine",
  "Colon",
  "Rectum",
  "Anus",
  "Liver",
  "Pancreas",
  "Other Digestive",
  "Nasal Cavity, Middle Ear, Sinuses",
  "Larynx",
  "Lung and Bronchus",
  "Other Respiratory/Intrathoracic",
  "Bone",
  "Melanoma of Skin",
  "Other Skin",
  "Mesothelioma",
  "Kaposi Sarcoma",
  "Soft Tissue",
  "Breast",
  "Cervix Uteri",
  "Corpus Uteri",
  "Ovary",
  "Other Female Genital",
  "Prostate",
  "Testis",
  "Other Male Genital",
  "Kidney and Renal Pelvis",
  "Bladder",
  "Other Urinary",
  "Eye and Orbit",
  "Brain and CNS",
  "Thyroid",
  "Other Endocrine",
  "Ill-Defined Sites",
  "Unknown Primary Site",
  "Lymph Nodes (Secondary)",
  "Secondary - Respiratory/Digestive",
  "Secondary - Other Sites",
  "Neuroendocrine Tumors",
  "Hodgkin Lymphoma",
  "Non-Hodgkin Lymphoma",
  "Multiple Myeloma",
  "Lymphoid Leukemia",
  "Myeloid and Monocytic Leukemia",
  "Other Leukemia",
  "Other Hematopoietic",
  "In Situ Neoplasms",
  "Benign Neoplasms",
  "Uncertain Behavior Neoplasms",
  "MDS / Myeloproliferative",
  "Unspecified Behavior Neoplasms",
  "Hematopoietic System (ICD-O-3)"
)

message(glue("Defined {length(unique(CANCER_SITE_MAP))} cancer site categories covering {length(CANCER_SITE_MAP)} prefixes"))

# ==============================================================================
# SECTION 2: LOAD AND CLASSIFY DIAGNOSIS DATA ----
# ==============================================================================

message("\nLoading DIAGNOSIS table (ICD-10 only, all patients)...")

dx_icd10 <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  select(ID, DX, DX_DATE) %>%
  collect()

message(glue("  Total ICD-10 DIAGNOSIS rows: {format(nrow(dx_icd10), big.mark=',')}"))

# Normalize codes (remove dots, uppercase)
dx_icd10 <- dx_icd10 %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\.")))

# Filter to neoplasm codes (C00-D49)
dx_cancer <- dx_icd10 %>%
  filter(str_detect(DX_norm, "^[CD]"))

message(glue("  Neoplasm codes (C/D): {format(nrow(dx_cancer), big.mark=',')} rows"))

# Classify by prefix
dx_cancer <- dx_cancer %>%
  mutate(category = classify_codes(DX_norm))

# Handle unclassified codes (label for visibility, same as R/47)
n_unclassified <- sum(is.na(dx_cancer$category))
if (n_unclassified > 0) {
  unclass_codes <- dx_cancer %>%
    filter(is.na(category)) %>%
    pull(DX_norm) %>%
    unique()
  message(glue("  WARNING: {n_unclassified} rows ({length(unclass_codes)} unique codes) unclassified"))
  dx_cancer <- dx_cancer %>%
    mutate(category = ifelse(is.na(category), "Unclassified", category))
}

message(glue("  ICD-10 classified into {n_distinct(dx_cancer$category)} categories"))

# ==============================================================================
# SECTION 3: EXACT CODE CONFIRMATION (PER D-01, LEVEL 1) ----
# ==============================================================================
# WHY 2+ distinct dates required: A single diagnosis date may represent an
#   incidental finding, rule-out diagnosis, or data entry error. Two distinct
#   dates indicate persistent clinical concern and independent confirmation.
#
# WHY distinct dates not distinct encounters: Same-day encounters at different
#   sites (e.g., clinic visit + lab) still count as one temporal confirmation
#   point. Only date separation provides meaningful temporal independence.
# ==============================================================================

message("\n=== EXACT CODE CONFIRMATION ===")

# Step 1: Total patients per exact code
total_exact <- dx_cancer %>%
  group_by(DX_norm, category) %>%
  summarise(total_patients = n_distinct(ID), .groups = "drop")

message(glue("  Total unique codes: {nrow(total_exact)}"))

# Step 2: Confirmed patients per exact code -- patient has 2+ distinct non-NA DX_DATE for the same exact DX_norm
confirmed_exact <- dx_cancer %>%
  filter(!is.na(DX_DATE)) %>%
  distinct(ID, DX_norm, DX_DATE, category) %>% # Deduplicate per Pitfall 3
  group_by(ID, DX_norm) %>%
  filter(n_distinct(DX_DATE) >= 2) %>%
  ungroup() %>%
  group_by(DX_norm, category) %>%
  summarise(confirmed_patients = n_distinct(ID), .groups = "drop")

# Step 3: Join and compute derived columns
summary_exact <- total_exact %>%
  left_join(confirmed_exact, by = c("DX_norm", "category")) %>%
  mutate(
    confirmed_patients = ifelse(is.na(confirmed_patients), 0L, as.integer(confirmed_patients)),
    unconfirmed_patients = total_patients - confirmed_patients,
    confirmation_rate = confirmed_patients / total_patients
  ) %>%
  filter(total_patients > 0)

# Step 4: Order by confirmation rate (highest first), then by total patients descending
summary_exact <- summary_exact %>%
  arrange(desc(confirmation_rate), desc(total_patients)) %>%
  select(DX_norm, category, total_patients, confirmed_patients, unconfirmed_patients, confirmation_rate)

total_confirmed_exact <- sum(summary_exact$confirmed_patients)
overall_rate_exact <- total_confirmed_exact / sum(summary_exact$total_patients)

message(glue("  Total codes with patients: {nrow(summary_exact)}"))
message(glue("  Total confirmed patients (exact code): {format(total_confirmed_exact, big.mark=',')}"))
message(glue("  Overall confirmation rate (exact): {scales::percent(overall_rate_exact, accuracy=0.1)}"))

# ==============================================================================
# SECTION 4: CANCER SITE CATEGORY CONFIRMATION (PER D-01, LEVEL 2) ----
# ==============================================================================

message("\n=== CANCER SITE CATEGORY CONFIRMATION ===")

# Step 1: Total patients per category
total_category <- dx_cancer %>%
  group_by(category) %>%
  summarise(total_patients = n_distinct(ID), .groups = "drop")

# Step 2: Confirmed patients -- patient has 2+ distinct non-NA DX_DATE for ANY code in the same cancer site category
confirmed_category <- dx_cancer %>%
  filter(!is.na(DX_DATE)) %>%
  distinct(ID, DX_DATE, category) %>% # Deduplicate (collapse across codes within category)
  group_by(ID, category) %>%
  filter(n_distinct(DX_DATE) >= 2) %>%
  ungroup() %>%
  group_by(category) %>%
  summarise(confirmed_patients = n_distinct(ID), .groups = "drop")

# Step 3: Join and compute
summary_category <- total_category %>%
  left_join(confirmed_category, by = "category") %>%
  mutate(
    confirmed_patients = ifelse(is.na(confirmed_patients), 0L, as.integer(confirmed_patients)),
    unconfirmed_patients = total_patients - confirmed_patients,
    confirmation_rate = confirmed_patients / total_patients
  ) %>%
  filter(total_patients > 0) %>%
  arrange(desc(confirmation_rate), desc(total_patients))

total_confirmed_category <- sum(summary_category$confirmed_patients)
overall_rate_category <- total_confirmed_category / sum(summary_category$total_patients)

message(glue("  Total categories with patients: {nrow(summary_category)}"))
message(glue("  Total confirmed patients (category): {format(total_confirmed_category, big.mark=',')}"))
message(glue("  Overall confirmation rate (category): {scales::percent(overall_rate_category, accuracy=0.1)}"))

# ==============================================================================
# SECTION 5: TOTALS ROWS ----
# ==============================================================================

totals_exact <- tibble(
  DX_norm = "TOTAL",
  category = "",
  total_patients = sum(summary_exact$total_patients),
  confirmed_patients = sum(summary_exact$confirmed_patients),
  unconfirmed_patients = sum(summary_exact$unconfirmed_patients),
  confirmation_rate = NA_real_
)

totals_category <- tibble(
  category = "TOTAL",
  total_patients = sum(summary_category$total_patients),
  confirmed_patients = sum(summary_category$confirmed_patients),
  unconfirmed_patients = sum(summary_category$unconfirmed_patients),
  confirmation_rate = NA_real_
)

# ==============================================================================
# SECTION 6: WRITE STYLED XLSX (PER D-02, D-07) ----
# ==============================================================================

message("")
message(glue("Writing styled xlsx to {OUTPUT_PATH}..."))

DARK_HEADER_FILL <- "FF374151"
WHITE_FONT <- "FFFFFFFF"
TITLE_FONT_COLOR <- "FF1F2937"
TOTALS_FILL <- "FFE5E7EB"

wb <- wb_workbook()

# ---------------------------------------------------------------------------
# Sheet 1: "Exact Code"
# ---------------------------------------------------------------------------
SHEET1 <- "Exact Code"
wb$add_worksheet(SHEET1)

# Row 1: Title
wb$add_data(
  sheet = SHEET1, x = "Cancer Site Confirmation - Exact Code Level",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = SHEET1, dims = "A1",
  name = "Calibri", size = 16, bold = TRUE,
  color = wb_color(TITLE_FONT_COLOR)
)
wb$merge_cells(sheet = SHEET1, dims = "A1:F1")

# Row 2: Headers
headers1 <- c("ICD-10 Code", "Cancer Site Category", "Total Patients", "Confirmed Patients", "Unconfirmed Patients", "Confirmation Rate")
for (i in seq_along(headers1)) {
  wb$add_data(sheet = SHEET1, x = headers1[i], start_row = 2, start_col = i)
}
wb$add_fill(sheet = SHEET1, dims = "A2:F2", color = wb_color(DARK_HEADER_FILL))
wb$add_font(
  sheet = SHEET1, dims = "A2:F2",
  name = "Calibri", size = 11, bold = TRUE,
  color = wb_color(WHITE_FONT)
)

# Freeze pane
wb$freeze_pane(sheet = SHEET1, first_active_row = 3, first_active_col = 1)

# Data rows
data_start <- 3
n_data <- nrow(summary_exact)
data_end <- data_start + n_data - 1

wb$add_data(
  sheet = SHEET1, x = as.data.frame(summary_exact),
  start_row = data_start, col_names = FALSE
)
wb$add_numfmt(
  sheet = SHEET1, dims = glue("C{data_start}:E{data_end}"),
  numfmt = "#,##0"
)
wb$add_numfmt(
  sheet = SHEET1, dims = glue("F{data_start}:F{data_end}"),
  numfmt = "0.0%"
)

# Totals rows
totals_start <- data_end + 1
wb$add_data(
  sheet = SHEET1, x = as.data.frame(totals_exact),
  start_row = totals_start, col_names = FALSE
)
wb$add_fill(
  sheet = SHEET1,
  dims = glue("A{totals_start}:F{totals_start}"),
  color = wb_color(TOTALS_FILL)
)
wb$add_font(
  sheet = SHEET1,
  dims = glue("A{totals_start}:F{totals_start}"),
  name = "Calibri", size = 11, bold = TRUE,
  color = wb_color(TITLE_FONT_COLOR)
)
wb$add_numfmt(
  sheet = SHEET1,
  dims = glue("C{totals_start}:E{totals_start}"),
  numfmt = "#,##0"
)

# Column widths
wb$set_col_widths(sheet = SHEET1, cols = 1:6, widths = c(14, 42, 14, 16, 18, 16))

# ---------------------------------------------------------------------------
# Sheet 2: "Cancer Site Category"
# ---------------------------------------------------------------------------
SHEET2 <- "Cancer Site Category"
wb$add_worksheet(SHEET2)

# Row 1: Title
wb$add_data(
  sheet = SHEET2, x = "Cancer Site Confirmation - Category Level",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = SHEET2, dims = "A1",
  name = "Calibri", size = 16, bold = TRUE,
  color = wb_color(TITLE_FONT_COLOR)
)
wb$merge_cells(sheet = SHEET2, dims = "A1:E1")

# Row 2: Headers
headers2 <- c("Cancer Site Category", "Total Patients", "Confirmed Patients", "Unconfirmed Patients", "Confirmation Rate")
for (i in seq_along(headers2)) {
  wb$add_data(sheet = SHEET2, x = headers2[i], start_row = 2, start_col = i)
}
wb$add_fill(sheet = SHEET2, dims = "A2:E2", color = wb_color(DARK_HEADER_FILL))
wb$add_font(
  sheet = SHEET2, dims = "A2:E2",
  name = "Calibri", size = 11, bold = TRUE,
  color = wb_color(WHITE_FONT)
)

# Freeze pane
wb$freeze_pane(sheet = SHEET2, first_active_row = 3, first_active_col = 1)

# Data rows
data_start2 <- 3
n_data2 <- nrow(summary_category)
data_end2 <- data_start2 + n_data2 - 1

wb$add_data(
  sheet = SHEET2, x = as.data.frame(summary_category),
  start_row = data_start2, col_names = FALSE
)
wb$add_numfmt(
  sheet = SHEET2, dims = glue("B{data_start2}:D{data_end2}"),
  numfmt = "#,##0"
)
wb$add_numfmt(
  sheet = SHEET2, dims = glue("E{data_start2}:E{data_end2}"),
  numfmt = "0.0%"
)

# Totals rows
totals_start2 <- data_end2 + 1
wb$add_data(
  sheet = SHEET2, x = as.data.frame(totals_category),
  start_row = totals_start2, col_names = FALSE
)
wb$add_fill(
  sheet = SHEET2,
  dims = glue("A{totals_start2}:E{totals_start2}"),
  color = wb_color(TOTALS_FILL)
)
wb$add_font(
  sheet = SHEET2,
  dims = glue("A{totals_start2}:E{totals_start2}"),
  name = "Calibri", size = 11, bold = TRUE,
  color = wb_color(TITLE_FONT_COLOR)
)
wb$add_numfmt(
  sheet = SHEET2,
  dims = glue("B{totals_start2}:D{totals_start2}"),
  numfmt = "#,##0"
)

# Column widths
wb$set_col_widths(sheet = SHEET2, cols = 1:5, widths = c(42, 14, 16, 18, 16))

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------
wb$save(OUTPUT_PATH)

message(glue("Wrote {OUTPUT_PATH}"))
message(glue("  Sheet '{SHEET1}': {n_data} data rows + 1 total row"))
message(glue("  Sheet '{SHEET2}': {n_data2} data rows + 1 total row"))

# Close DuckDB connection
close_pcornet_con()

message("")
message("=== Phase 3 Cancer Site Confirmation Complete ===")
