# ==============================================================================
# Phase 40: Cancer Site Frequency (Rewrite)
# ==============================================================================
# Bottom-up approach: classify every cancer code that appears in the data using
# ICD-10 prefix rules defined directly in code. No external xlsx dependency.
#
# Categories based on SEER/NCI site groupings mapped to ICD-10-CM prefixes.
#
# Inputs:
#   - DIAGNOSIS DuckDB table (ICD-10 codes)
#   - TUMOR_REGISTRY_ALL DuckDB table (ICD-O-3 topography codes)
#
# Outputs:
#   - output/tables/cancer_site_frequency.xlsx (styled workbook)
#     Sheet 1 "By Category": patient/record counts per category per source
#     Sheet 2 "All Codes": every code with its assigned category (verification)
#
# Usage:
#   Rscript R/40_cancer_site_frequency.R
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")

OUTPUT_PATH <- file.path(CONFIG$output_dir, "tables", "cancer_site_frequency.xlsx")
dir.create(dirname(OUTPUT_PATH), showWarnings = FALSE, recursive = TRUE)

message("=== Phase 40: Cancer Site Frequency ===")
message(glue("Output: {OUTPUT_PATH}"))

# ==============================================================================
# SECTION 1: DEFINE CANCER SITE CATEGORIES
# ==============================================================================
# Each 3-character ICD-10 prefix maps to a cancer site category.
# Based on SEER/NCI site groupings.  Prefix matching via substr(code, 1, 3).
#
# Sources:
#   - SEER Site Recode ICD-O-3/WHO 2008
#   - ICD-10-CM Chapter 2 (C00-D49)
# ==============================================================================

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

message(glue("Defined {length(unique(PREFIX_MAP))} cancer site categories covering {length(PREFIX_MAP)} prefixes"))

# ==============================================================================
# SECTION 2: CLASSIFICATION FUNCTION
# ==============================================================================

#' Classify ICD-10 or ICD-O-3 codes into cancer site categories
#' @param codes Character vector of normalized codes (uppercase, no dots)
#' @return Character vector of category names (NA for unclassified)
classify_codes <- function(codes) {
  prefix3 <- substr(codes, 1, 3)
  categories <- unname(PREFIX_MAP[prefix3])
  categories
}

# ==============================================================================
# SECTION 3: LOAD AND CLASSIFY ICD-10 DIAGNOSIS CODES
# ==============================================================================

message("\nLoading DIAGNOSIS table (ICD-10 only, all patients)...")

dx_icd10 <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  select(ID, DX) %>%
  collect()

message(glue("  Total ICD-10 DIAGNOSIS rows: {format(nrow(dx_icd10), big.mark=',')}"))

# Normalize codes
dx_icd10 <- dx_icd10 %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\.")))

# Filter to neoplasm codes only (C00-D49)
dx_cancer <- dx_icd10 %>%
  filter(str_detect(DX_norm, "^[CD]"))

message(glue("  Neoplasm codes (C/D): {format(nrow(dx_cancer), big.mark=',')} rows"))

# Classify
dx_cancer <- dx_cancer %>%
  mutate(category = classify_codes(DX_norm))

n_unclassified <- sum(is.na(dx_cancer$category))
if (n_unclassified > 0) {
  unclass_codes <- dx_cancer %>% filter(is.na(category)) %>% pull(DX_norm) %>% unique()
  message(glue("  WARNING: {n_unclassified} rows ({length(unclass_codes)} unique codes) unclassified"))
  message(glue("    Codes: {paste(head(unclass_codes, 20), collapse=', ')}"))
  # Label them for visibility
  dx_cancer <- dx_cancer %>%
    mutate(category = ifelse(is.na(category), "Unclassified", category))
}

# Aggregate by category
icd10_by_cat <- dx_cancer %>%
  group_by(category) %>%
  summarise(
    patients = n_distinct(ID),
    records  = n(),
    .groups  = "drop"
  ) %>%
  mutate(source = "ICD-10")

message(glue("  ICD-10 classified into {nrow(icd10_by_cat)} categories"))

# Code-level detail for Sheet 2
icd10_codes_detail <- dx_cancer %>%
  group_by(code = DX_norm, category) %>%
  summarise(
    patients = n_distinct(ID),
    records  = n(),
    .groups  = "drop"
  ) %>%
  mutate(source = "ICD-10") %>%
  arrange(category, code)

# ==============================================================================
# SECTION 4: LOAD AND CLASSIFY ICD-O-3 TOPOGRAPHY CODES
# ==============================================================================

message("\nLoading TUMOR_REGISTRY_ALL table (topography codes)...")

tr_all_lazy <- get_pcornet_table("TUMOR_REGISTRY_ALL")
tr_cols <- colnames(tr_all_lazy)

# Find topography column(s)
site_candidates <- intersect(c("SITE_CODE", "SITE", "PRIMARY_SITE",
                                "TOPOGRAPHY_CODE", "ICDOSITE"), tr_cols)
message(glue("  Topography column candidates: {paste(site_candidates, collapse=', ')}"))

if (length(site_candidates) == 0) {
  message("  WARNING: No topography column found. ICD-O-3 counts will be 0.")
  icdo3_by_cat <- tibble(category = character(), patients = integer(),
                         records = integer(), source = character())
  icdo3_codes_detail <- tibble(code = character(), category = character(),
                               patients = integer(), records = integer(),
                               source = character())
} else {
  coalesce_expr <- rlang::parse_expr(
    paste0("coalesce(", paste(site_candidates, collapse = ", "), ")")
  )
  tr_topo <- tr_all_lazy %>%
    mutate(topo_raw = !!coalesce_expr) %>%
    select(ID, topo_raw) %>%
    filter(!is.na(topo_raw)) %>%
    collect()

  message(glue("  Total TUMOR_REGISTRY rows with topography: {format(nrow(tr_topo), big.mark=',')}"))

  # Normalize: uppercase, remove dots, prepend C if missing
  tr_topo <- tr_topo %>%
    mutate(
      topo_norm = toupper(str_remove_all(topo_raw, "\\.")),
      # Prepend "C" for bare numeric codes (e.g., "77" -> "C77")
      topo_norm = ifelse(str_detect(topo_norm, "^[0-9]"),
                         paste0("C", topo_norm),
                         topo_norm)
    )

  # Classify
  tr_topo <- tr_topo %>%
    mutate(category = classify_codes(topo_norm))

  n_unclass_tr <- sum(is.na(tr_topo$category))
  if (n_unclass_tr > 0) {
    unclass_tr <- tr_topo %>% filter(is.na(category)) %>% pull(topo_norm) %>% unique()
    message(glue("  WARNING: {n_unclass_tr} rows ({length(unclass_tr)} unique codes) unclassified"))
    message(glue("    Codes: {paste(head(unclass_tr, 20), collapse=', ')}"))
    tr_topo <- tr_topo %>%
      mutate(category = ifelse(is.na(category), "Unclassified", category))
  }

  # Aggregate by category
  icdo3_by_cat <- tr_topo %>%
    group_by(category) %>%
    summarise(
      patients = n_distinct(ID),
      records  = n(),
      .groups  = "drop"
    ) %>%
    mutate(source = "ICD-O-3")

  message(glue("  ICD-O-3 classified into {nrow(icdo3_by_cat)} categories"))

  # Code-level detail for Sheet 2
  icdo3_codes_detail <- tr_topo %>%
    group_by(code = topo_norm, category) %>%
    summarise(
      patients = n_distinct(ID),
      records  = n(),
      .groups  = "drop"
    ) %>%
    mutate(source = "ICD-O-3") %>%
    arrange(category, code)
}

# ==============================================================================
# SECTION 5: COMBINE RESULTS
# ==============================================================================

message("\nCombining results...")

# Category-level summary: one row per category per source
summary_long <- bind_rows(icd10_by_cat, icdo3_by_cat)

# Ensure all categories that appear in either source are present in both
all_cats <- unique(summary_long$category)
all_sources <- c("ICD-10", "ICD-O-3")

full_grid <- expand.grid(category = all_cats, source = all_sources,
                         stringsAsFactors = FALSE) %>%
  as_tibble()

summary_long <- full_grid %>%
  left_join(summary_long, by = c("category", "source")) %>%
  mutate(
    patients = ifelse(is.na(patients), 0L, as.integer(patients)),
    records  = ifelse(is.na(records),  0L, as.integer(records))
  )

# Sort by category order, then source
cat_rank <- match(summary_long$category, CATEGORY_ORDER)
# Categories not in CATEGORY_ORDER get sorted to end
cat_rank[is.na(cat_rank)] <- 999L
summary_long <- summary_long %>%
  mutate(cat_rank = cat_rank) %>%
  arrange(cat_rank, source) %>%
  select(-cat_rank)

# Totals
total_icd10_patients <- n_distinct(dx_cancer$ID)
total_icdo3_patients <- if (exists("tr_topo")) n_distinct(tr_topo$ID) else 0L

totals_long <- tibble(
  category = c("TOTAL", "TOTAL"),
  source   = c("ICD-10", "ICD-O-3"),
  patients = c(total_icd10_patients, total_icdo3_patients),
  records  = c(
    sum(filter(summary_long, source == "ICD-10")$records),
    sum(filter(summary_long, source == "ICD-O-3")$records)
  )
)

message("")
message("=== COUNT SUMMARY ===")
message(glue("ICD-10:  {format(total_icd10_patients, big.mark=',')} unique patients, {format(totals_long$records[1], big.mark=',')} records"))
message(glue("ICD-O-3: {format(total_icdo3_patients, big.mark=',')} unique patients, {format(totals_long$records[2], big.mark=',')} records"))

# Spot-check Hodgkin Lymphoma
hl_rows <- summary_long %>% filter(category == "Hodgkin Lymphoma")
if (nrow(hl_rows) > 0) {
  for (r in seq_len(nrow(hl_rows))) {
    message(glue("  Hodgkin Lymphoma ({hl_rows$source[r]}): {format(hl_rows$patients[r], big.mark=',')} patients, {format(hl_rows$records[r], big.mark=',')} records"))
  }
}

# Code-level detail (both sources combined)
all_codes_detail <- bind_rows(icd10_codes_detail, icdo3_codes_detail) %>%
  select(code, category, source, patients, records)

# Sort by category order then code
code_rank <- match(all_codes_detail$category, CATEGORY_ORDER)
code_rank[is.na(code_rank)] <- 999L
all_codes_detail <- all_codes_detail %>%
  mutate(cat_rank = code_rank) %>%
  arrange(cat_rank, source, code) %>%
  select(-cat_rank)

# ==============================================================================
# SECTION 6: WRITE STYLED XLSX
# ==============================================================================

message("")
message(glue("Writing styled xlsx to {OUTPUT_PATH}..."))

DARK_HEADER_FILL <- "FF374151"
WHITE_FONT       <- "FFFFFFFF"
TITLE_FONT_COLOR <- "FF1F2937"
TOTALS_FILL      <- "FFE5E7EB"

wb <- wb_workbook()

# ---------------------------------------------------------------------------
# Sheet 1: By Category
# ---------------------------------------------------------------------------
SHEET1 <- "By Category"
wb$add_worksheet(SHEET1)

# Row 1: Title
wb$add_data(sheet = SHEET1, x = "Cancer Site Frequency - All Patients",
            start_row = 1, start_col = 1)
wb$add_font(sheet = SHEET1, dims = "A1",
            name = "Calibri", size = 16, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$merge_cells(sheet = SHEET1, dims = "A1:D1")

# Row 2: Headers
headers1 <- c("Cancer Site Category", "Source", "Patients", "Records")
for (i in seq_along(headers1)) {
  wb$add_data(sheet = SHEET1, x = headers1[i], start_row = 2, start_col = i)
}
wb$add_fill(sheet = SHEET1, dims = "A2:D2", color = wb_color(DARK_HEADER_FILL))
wb$add_font(sheet = SHEET1, dims = "A2:D2",
            name = "Calibri", size = 11, bold = TRUE,
            color = wb_color(WHITE_FONT))

# Freeze pane
wb$freeze_pane(sheet = SHEET1, first_active_row = 3, first_active_col = 1)

# Data rows
data_start <- 3
n_data     <- nrow(summary_long)
data_end   <- data_start + n_data - 1

wb$add_data(sheet = SHEET1, x = as.data.frame(summary_long),
            start_row = data_start, col_names = FALSE)
wb$add_numfmt(sheet = SHEET1, dims = glue("C{data_start}:D{data_end}"),
              numfmt = "#,##0")

# Totals rows
totals_start <- data_end + 1
totals_end   <- totals_start + nrow(totals_long) - 1
wb$add_data(sheet = SHEET1, x = as.data.frame(totals_long),
            start_row = totals_start, col_names = FALSE)
wb$add_fill(sheet = SHEET1,
            dims  = glue("A{totals_start}:D{totals_end}"),
            color = wb_color(TOTALS_FILL))
wb$add_font(sheet = SHEET1,
            dims  = glue("A{totals_start}:D{totals_end}"),
            name  = "Calibri", size = 11, bold = TRUE,
            color = wb_color(TITLE_FONT_COLOR))
wb$add_numfmt(sheet = SHEET1,
              dims  = glue("C{totals_start}:D{totals_end}"),
              numfmt = "#,##0")

# Column widths
wb$set_col_widths(sheet = SHEET1, cols = 1:4, widths = c(42, 12, 14, 14))

# ---------------------------------------------------------------------------
# Sheet 2: All Codes (verification)
# ---------------------------------------------------------------------------
SHEET2 <- "All Codes"
wb$add_worksheet(SHEET2)

headers2 <- c("Code", "Category", "Source", "Patients", "Records")
for (i in seq_along(headers2)) {
  wb$add_data(sheet = SHEET2, x = headers2[i], start_row = 1, start_col = i)
}
wb$add_fill(sheet = SHEET2, dims = "A1:E1", color = wb_color(DARK_HEADER_FILL))
wb$add_font(sheet = SHEET2, dims = "A1:E1",
            name = "Calibri", size = 11, bold = TRUE,
            color = wb_color(WHITE_FONT))

if (nrow(all_codes_detail) > 0) {
  wb$add_data(sheet = SHEET2, x = as.data.frame(all_codes_detail),
              start_row = 2, col_names = FALSE)
  code_end <- 1 + nrow(all_codes_detail)
  wb$add_numfmt(sheet = SHEET2, dims = glue("D2:E{code_end}"), numfmt = "#,##0")
}

wb$freeze_pane(sheet = SHEET2, first_active_row = 2, first_active_col = 1)
wb$set_col_widths(sheet = SHEET2, cols = 1:5, widths = c(14, 42, 12, 12, 12))

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------
wb$save(OUTPUT_PATH)

message(glue("Wrote {OUTPUT_PATH}"))
message(glue("  Sheet '{SHEET1}': {n_data} data rows + {nrow(totals_long)} total rows"))
message(glue("  Sheet '{SHEET2}': {nrow(all_codes_detail)} code-level rows"))

message("")
message("=== Phase 47 Cancer Site Frequency Complete ===")
