# ==============================================================================
# Phase 4: Cancer Site Confirmation with 7-Day Separation
# ==============================================================================
# Validates cancer site diagnosis codes by requiring diagnosis dates at least
# 7 calendar days apart per code per patient before counting the code as
# "confirmed."
#
# Two confirmation levels (per D-01, D-03):
#   1. Exact Code:  C81.10 must have dates spanning 7+ days (7-day gap)
#   2. Prefix Level: any C81.* code on dates spanning 7+ days confirms C81
#
# Data: DIAGNOSIS table only, ICD-10 codes (DX_TYPE == "10"), DX_DATE (per D-03, D-04)
#
# Output: output/tables/cancer_site_confirmation_7day.xlsx
#   Sheet 1 "Exact Code (7-Day Gap)":   per-category confirmation at exact ICD-10 code level
#   Sheet 2 "Prefix Level (7-Day Gap)": per-category confirmation at 3-char prefix level
#
# Usage:
#   Rscript R/51_cancer_site_confirmation_7day.R
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")

OUTPUT_PATH <- file.path(CONFIG$output_dir, "tables", "cancer_site_confirmation_7day.xlsx")
dir.create(dirname(OUTPUT_PATH), showWarnings = FALSE, recursive = TRUE)

message("=== Phase 4: Cancer Site Confirmation with 7-Day Separation ===")
message(glue("Output: {OUTPUT_PATH}"))

# ==============================================================================
# SECTION 1: PREFIX_MAP and CATEGORY_ORDER
# ==============================================================================
# Copied from R/50_cancer_site_confirmation.R for script independence

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
# SECTION 2: LOAD AND CLASSIFY DIAGNOSIS DATA
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
  unclass_codes <- dx_cancer %>% filter(is.na(category)) %>% pull(DX_norm) %>% unique()
  message(glue("  WARNING: {n_unclassified} rows ({length(unclass_codes)} unique codes) unclassified"))
  dx_cancer <- dx_cancer %>%
    mutate(category = ifelse(is.na(category), "Unclassified", category))
}

message(glue("  ICD-10 classified into {n_distinct(dx_cancer$category)} categories"))

# ==============================================================================
# SECTION 3: EXACT CODE CONFIRMATION WITH 7-DAY GAP (per D-03, D-06)
# ==============================================================================

message("\n=== EXACT CODE CONFIRMATION (7-DAY GAP) ===")

# Step 1: Total patients per exact code
total_exact <- dx_cancer %>%
  group_by(DX_norm, category) %>%
  summarise(total_patients = n_distinct(ID), .groups = "drop")

message(glue("  Total unique codes: {nrow(total_exact)}"))

# Step 2: Confirmed patients per exact code -- patient has dates spanning 7+ days for the same exact DX_norm
# 7-day span: max(date) - min(date) >= 7 days (per D-06)
confirmed_exact <- dx_cancer %>%
  filter(!is.na(DX_DATE)) %>%
  distinct(ID, DX_norm, DX_DATE, category) %>%   # Deduplicate per Pitfall 3
  group_by(ID, DX_norm) %>%
  filter(as.numeric(max(DX_DATE) - min(DX_DATE)) >= 7) %>%
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

# Step 4: Order by CATEGORY_ORDER, then by code within category
cat_rank <- setNames(seq_along(CATEGORY_ORDER), CATEGORY_ORDER)
summary_exact <- summary_exact %>%
  mutate(rank = ifelse(category %in% names(cat_rank), cat_rank[category], 999L)) %>%
  arrange(rank, DX_norm) %>%
  select(DX_norm, category, total_patients, confirmed_patients, unconfirmed_patients, confirmation_rate)

total_confirmed_exact <- sum(summary_exact$confirmed_patients)
overall_rate_exact <- total_confirmed_exact / sum(summary_exact$total_patients)

message(glue("  Total codes with patients: {nrow(summary_exact)}"))
message(glue("  Total confirmed patients (exact code, 7-day gap): {format(total_confirmed_exact, big.mark=',')}"))
message(glue("  Overall confirmation rate (exact, 7-day gap): {scales::percent(overall_rate_exact, accuracy=0.1)}"))

# ==============================================================================
# SECTION 4: PREFIX LEVEL CONFIRMATION WITH 7-DAY GAP (per D-03, D-06)
# ==============================================================================

message("\n=== PREFIX LEVEL CONFIRMATION (7-DAY GAP) ===")

# Step 1: Add prefix3 column
dx_prefix <- dx_cancer %>%
  mutate(prefix3 = substr(DX_norm, 1, 3))

# Step 2: Total patients per category (same as exact, but recomputed from prefix perspective for consistency)
total_prefix <- dx_prefix %>%
  group_by(category) %>%
  summarise(total_patients = n_distinct(ID), .groups = "drop")

# Step 3: Confirmed patients -- patient has dates spanning 7+ days for the same prefix3 (per Pitfall 2 -- group by prefix, not exact code)
# 7-day span: max(date) - min(date) >= 7 days (per D-06)
confirmed_prefix <- dx_prefix %>%
  filter(!is.na(DX_DATE)) %>%
  distinct(ID, prefix3, DX_DATE, category) %>%   # Deduplicate
  group_by(ID, prefix3) %>%
  filter(as.numeric(max(DX_DATE) - min(DX_DATE)) >= 7) %>%
  ungroup() %>%
  group_by(category) %>%
  summarise(confirmed_patients = n_distinct(ID), .groups = "drop")

# Step 4: Join and compute (same pattern as exact)
summary_prefix <- total_prefix %>%
  left_join(confirmed_prefix, by = "category") %>%
  mutate(
    confirmed_patients = ifelse(is.na(confirmed_patients), 0L, as.integer(confirmed_patients)),
    unconfirmed_patients = total_patients - confirmed_patients,
    confirmation_rate = confirmed_patients / total_patients
  ) %>%
  filter(total_patients > 0) %>%
  mutate(rank = ifelse(category %in% names(cat_rank), cat_rank[category], 999L)) %>%
  arrange(rank) %>%
  select(-rank)

total_confirmed_prefix <- sum(summary_prefix$confirmed_patients)
overall_rate_prefix <- total_confirmed_prefix / sum(summary_prefix$total_patients)

message(glue("  Total categories with patients: {nrow(summary_prefix)}"))
message(glue("  Total confirmed patients (prefix, 7-day gap): {format(total_confirmed_prefix, big.mark=',')}"))
message(glue("  Overall confirmation rate (prefix, 7-day gap): {scales::percent(overall_rate_prefix, accuracy=0.1)}"))

# ==============================================================================
# SECTION 5: TOTALS ROWS
# ==============================================================================

totals_exact <- tibble(
  DX_norm = "TOTAL",
  category = "",
  total_patients = sum(summary_exact$total_patients),
  confirmed_patients = sum(summary_exact$confirmed_patients),
  unconfirmed_patients = sum(summary_exact$unconfirmed_patients),
  confirmation_rate = NA_real_
)

totals_prefix <- tibble(
  category = "TOTAL",
  total_patients = sum(summary_prefix$total_patients),
  confirmed_patients = sum(summary_prefix$confirmed_patients),
  unconfirmed_patients = sum(summary_prefix$unconfirmed_patients),
  confirmation_rate = NA_real_
)

# ==============================================================================
# SECTION 6: WRITE STYLED XLSX (per D-02, D-07)
# ==============================================================================

message("")
message(glue("Writing styled xlsx to {OUTPUT_PATH}..."))

DARK_HEADER_FILL <- "FF374151"
WHITE_FONT       <- "FFFFFFFF"
TITLE_FONT_COLOR <- "FF1F2937"
TOTALS_FILL      <- "FFE5E7EB"

wb <- wb_workbook()

# ---------------------------------------------------------------------------
# Sheet 1: "Exact Code (7-Day Gap)"
# ---------------------------------------------------------------------------
SHEET1 <- "Exact Code (7-Day Gap)"
wb$add_worksheet(SHEET1)

# Row 1: Title
wb$add_data(sheet = SHEET1, x = "Cancer Site Confirmation - Exact Code (7-Day Gap)",
            start_row = 1, start_col = 1)
wb$add_font(sheet = SHEET1, dims = "A1",
            name = "Calibri", size = 16, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$merge_cells(sheet = SHEET1, dims = "A1:F1")

# Row 2: Headers
headers1 <- c("ICD-10 Code", "Cancer Site Category", "Total Patients", "Confirmed Patients", "Unconfirmed Patients", "Confirmation Rate")
for (i in seq_along(headers1)) {
  wb$add_data(sheet = SHEET1, x = headers1[i], start_row = 2, start_col = i)
}
wb$add_fill(sheet = SHEET1, dims = "A2:F2", color = wb_color(DARK_HEADER_FILL))
wb$add_font(sheet = SHEET1, dims = "A2:F2",
            name = "Calibri", size = 11, bold = TRUE,
            color = wb_color(WHITE_FONT))

# Freeze pane
wb$freeze_pane(sheet = SHEET1, first_active_row = 3, first_active_col = 1)

# Data rows
data_start <- 3
n_data     <- nrow(summary_exact)
data_end   <- data_start + n_data - 1

wb$add_data(sheet = SHEET1, x = as.data.frame(summary_exact),
            start_row = data_start, col_names = FALSE)
wb$add_numfmt(sheet = SHEET1, dims = glue("C{data_start}:E{data_end}"),
              numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET1, dims = glue("F{data_start}:F{data_end}"),
              numfmt = "0.0%")

# Totals rows
totals_start <- data_end + 1
wb$add_data(sheet = SHEET1, x = as.data.frame(totals_exact),
            start_row = totals_start, col_names = FALSE)
wb$add_fill(sheet = SHEET1,
            dims  = glue("A{totals_start}:F{totals_start}"),
            color = wb_color(TOTALS_FILL))
wb$add_font(sheet = SHEET1,
            dims  = glue("A{totals_start}:F{totals_start}"),
            name  = "Calibri", size = 11, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$add_numfmt(sheet = SHEET1,
              dims  = glue("C{totals_start}:E{totals_start}"),
              numfmt = "#,##0")

# Column widths
wb$set_col_widths(sheet = SHEET1, cols = 1:6, widths = c(14, 42, 14, 16, 18, 16))

# ---------------------------------------------------------------------------
# Sheet 2: "Prefix Level (7-Day Gap)"
# ---------------------------------------------------------------------------
SHEET2 <- "Prefix Level (7-Day Gap)"
wb$add_worksheet(SHEET2)

# Row 1: Title
wb$add_data(sheet = SHEET2, x = "Cancer Site Confirmation - Prefix Level (7-Day Gap)",
            start_row = 1, start_col = 1)
wb$add_font(sheet = SHEET2, dims = "A1",
            name = "Calibri", size = 16, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$merge_cells(sheet = SHEET2, dims = "A1:E1")

# Row 2: Headers
headers2 <- c("Cancer Site Category", "Total Patients", "Confirmed Patients", "Unconfirmed Patients", "Confirmation Rate")
for (i in seq_along(headers2)) {
  wb$add_data(sheet = SHEET2, x = headers2[i], start_row = 2, start_col = i)
}
wb$add_fill(sheet = SHEET2, dims = "A2:E2", color = wb_color(DARK_HEADER_FILL))
wb$add_font(sheet = SHEET2, dims = "A2:E2",
            name = "Calibri", size = 11, bold = TRUE,
            color = wb_color(WHITE_FONT))

# Freeze pane
wb$freeze_pane(sheet = SHEET2, first_active_row = 3, first_active_col = 1)

# Data rows
data_start2 <- 3
n_data2     <- nrow(summary_prefix)
data_end2   <- data_start2 + n_data2 - 1

wb$add_data(sheet = SHEET2, x = as.data.frame(summary_prefix),
            start_row = data_start2, col_names = FALSE)
wb$add_numfmt(sheet = SHEET2, dims = glue("B{data_start2}:D{data_end2}"),
              numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET2, dims = glue("E{data_start2}:E{data_end2}"),
              numfmt = "0.0%")

# Totals rows
totals_start2 <- data_end2 + 1
wb$add_data(sheet = SHEET2, x = as.data.frame(totals_prefix),
            start_row = totals_start2, col_names = FALSE)
wb$add_fill(sheet = SHEET2,
            dims  = glue("A{totals_start2}:E{totals_start2}"),
            color = wb_color(TOTALS_FILL))
wb$add_font(sheet = SHEET2,
            dims  = glue("A{totals_start2}:E{totals_start2}"),
            name  = "Calibri", size = 11, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$add_numfmt(sheet = SHEET2,
              dims  = glue("B{totals_start2}:D{totals_start2}"),
              numfmt = "#,##0")

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
message("=== Phase 4 Cancer Site Confirmation (7-Day Gap) Complete ===")
