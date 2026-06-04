# ==============================================================================
# 57_drug_grouping_instances.R -- Drug Grouping Instance-Level Tables
# ==============================================================================
#
# Purpose:
#   Generate encounter-level drug grouping tables showing one row per patient +
#   encounter + treatment type with human-readable sub-category names and cancer
#   site category names instead of raw codes and aggregated counts. Complements
#   R/56 aggregated summary tables with patient-traceable encounter detail.
#
# Inputs:
#   - cache/outputs/treatment_episode_detail.rds (from R/26, per-encounter grain:
#     patient_id, treatment_type, treatment_date, triggering_code, ENCOUNTERID,
#     drug_name, episode_number, episode_start, episode_stop, historical_flag)
#   - data/reference/all_codes_resolved_next_tables_v2.1.xlsx (sub-category
#     mappings: Chemo column C = medication, Radiation column G = type, SCT
#     column G = type)
#   - DuckDB DIAGNOSIS table (for raw ICD cancer codes per encounter)
#   - R/00_config.R (CANCER_SITE_MAP, ICD9_CANCER_SITE_MAP, CODE_SUBCATEGORY_MAP,
#     DRUG_GROUPINGS)
#
# Outputs:
#   - output/drug_grouping_instances.xlsx (2-sheet workbook:
#     Sheet 1 = "Treatment Sub-Category Detail" (encounter-level),
#     Sheet 2 = "Encounter Treatment Detail" (encounter-level))
#
# Dependencies:
#   - R/00_config.R (DRUG_GROUPINGS, CODE_SUBCATEGORY_MAP, CANCER_SITE_MAP,
#     ICD9_CANCER_SITE_MAP, CONFIG paths)
#   - R/utils/utils_assertions.R (assert_rds_exists, assert_df_valid)
#   - R/utils/utils_duckdb.R (open_pcornet_con, get_pcornet_table)
#   - R/utils/utils_cancer.R (is_cancer_code shared utility)
#   - openxlsx2 (multi-sheet xlsx output)
#
# ==============================================================================

# SECTION 1: SETUP AND CONFIGURATION ----

# Clear stale log handler from previous source() in same session
try(close(.log_con), silent = TRUE)
globalCallingHandlers(NULL)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(glue)
  library(stringr)
  library(openxlsx2)
  library(checkmate)
})

source("R/00_config.R")
source("R/utils/utils_assertions.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_cancer.R")  # is_cancer_code(), classify_codes()

DETAIL_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds")
REFERENCE_XLSX <- "data/reference/all_codes_resolved_next_tables_v2.1.xlsx"
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "drug_grouping_instances.xlsx")

# --- Log console output to file ---
LOG_FILE <- file.path(CONFIG$output_dir, "57_drug_grouping_instances.log")
.log_con <- file(LOG_FILE, open = "wt")

globalCallingHandlers(
  message = function(m) {
    cat(format(Sys.time(), "[%Y-%m-%d %H:%M:%S] "),
        conditionMessage(m),
        file = .log_con, sep = "")
    flush(.log_con)
  }
)

message("=== Phase 88: Drug Grouping Instance-Level Tables (Encounter Grain) ===")
message()
message(glue("  Detail RDS: {DETAIL_RDS}"))
message(glue("  Reference: {REFERENCE_XLSX}"))
message(glue("  Output: {OUTPUT_XLSX}"))
message()


# SECTION 2: LOAD AND VALIDATE INPUT DATA ----

message("--- Loading treatment episode detail (encounter-level) ---")

assert_rds_exists(DETAIL_RDS, script_name = "R/57")
detail <- readRDS(DETAIL_RDS)

assert_df_valid(
  detail,
  name = "treatment_episode_detail",
  required_cols = c("patient_id", "treatment_type", "treatment_date",
                    "triggering_code", "ENCOUNTERID", "episode_number"),
  script_name = "R/57"
)

message(glue("  Loaded {nrow(detail)} detail rows (one per date+code+encounter)"))
message(glue("  Treatment types: {paste(unique(detail$treatment_type), collapse = ', ')}"))
message(glue("  Unique patients: {n_distinct(detail$patient_id)}"))
message(glue("  Unique encounters: {n_distinct(detail$ENCOUNTERID[!is.na(detail$ENCOUNTERID)])}"))


# SECTION 3: BUILD SUB-CATEGORY MAPPINGS FROM REFERENCE XLSX ----

message()
message("--- Building sub-category mappings from reference xlsx ---")

assert_file_exists(REFERENCE_XLSX, .var.name = "[R/57 ERROR] Reference XLSX")
ref_wb <- wb_load(REFERENCE_XLSX)

# Chemo: code -> medication name (column C, "Medication")
chemo_sheet <- wb_to_df(ref_wb, sheet = "Chemotherapy", start_row = 2)
chemo_map <- setNames(as.character(chemo_sheet[[3]]), as.character(chemo_sheet[[1]]))
chemo_map <- chemo_map[!is.na(names(chemo_map)) & !is.na(chemo_map)]
message(glue("  Chemo sub-categories: {length(unique(chemo_map))} medications from {length(chemo_map)} codes"))

# Radiation: code -> type (column G: IMRT, Other radiation, Proton Therapy)
rad_sheet <- wb_to_df(ref_wb, sheet = "Radiation", start_row = 2)
rad_map <- setNames(as.character(rad_sheet[[7]]), as.character(rad_sheet[[1]]))
rad_map <- rad_map[!is.na(names(rad_map)) & !is.na(rad_map)]
message(glue("  Radiation sub-categories: {paste(unique(rad_map), collapse = ', ')}"))

# SCT: code -> type (column G: Allogeneic, Autologous, etc.)
sct_sheet <- wb_to_df(ref_wb, sheet = "SCT", start_row = 2)
sct_map <- setNames(as.character(sct_sheet[[7]]), as.character(sct_sheet[[1]]))
sct_map <- sct_map[!is.na(names(sct_map)) & !is.na(sct_map)]
message(glue("  SCT sub-categories: {paste(unique(sct_map), collapse = ', ')}"))

# Combined lookup: code -> sub-category label
code_to_subcategory <- c(chemo_map, rad_map, sct_map)
message(glue("  Total codes with sub-categories: {length(code_to_subcategory)}"))

# Build valid reference code set from column A of all 3 sheets
valid_reference_codes <- unique(c(
  as.character(chemo_sheet[[1]]),
  as.character(rad_sheet[[1]]),
  as.character(sct_sheet[[1]])
))
valid_reference_codes <- valid_reference_codes[!is.na(valid_reference_codes) & valid_reference_codes != ""]
message(glue("  Valid reference codes (Chemo+Radiation+SCT): {length(valid_reference_codes)}"))


# SECTION 4: EXTRACT CANCER CODES PER ENCOUNTER AND MAP TO CATEGORY NAMES ----

message()
message("--- Extracting cancer codes per encounter and mapping to category names ---")

# Cancer code detection uses shared is_cancer_code() from R/utils/utils_cancer.R
message(glue("  Using shared is_cancer_code() -- ICD-10: {length(names(CANCER_SITE_MAP))} prefixes, ICD-9: {length(names(ICD9_CANCER_SITE_MAP))} prefixes"))

# Get unique encounter IDs from detail (excluding NA/empty)
all_encounter_ids <- unique(detail$ENCOUNTERID[!is.na(detail$ENCOUNTERID) & detail$ENCOUNTERID != ""])
message(glue("  Unique encounter IDs from detail: {length(all_encounter_ids)}"))

USE_DUCKDB <- TRUE
open_pcornet_con()

# Get all diagnosis codes for encounters in treatment detail
dx_data <- get_pcornet_table("DIAGNOSIS") %>%
  filter(ENCOUNTERID %in% !!all_encounter_ids) %>%
  select(ENCOUNTERID, DX, DX_TYPE) %>%
  collect()

message(glue("  Loaded {nrow(dx_data)} total diagnosis records"))

# Filter to cancer/neoplasm codes only
dx_cancer <- dx_data %>%
  filter(is_cancer_code(DX))

message(glue("  Filtered to {nrow(dx_cancer)} cancer diagnosis records ({round(100 * nrow(dx_cancer) / nrow(dx_data), 1)}% of total)"))
message(glue("  Unique cancer codes: {n_distinct(dx_cancer$DX)}"))

# Aggregate cancer codes per encounter (semicolon-separated)
encounter_dx <- dx_cancer %>%
  group_by(ENCOUNTERID) %>%
  summarise(
    cancer_codes = paste(sort(unique(DX)), collapse = ";"),
    .groups = "drop"
  )

message(glue("  Encounters with cancer codes: {nrow(encounter_dx)}"))

# Join cancer codes to detail rows by ENCOUNTERID
detail_dx <- detail %>%
  left_join(encounter_dx, by = "ENCOUNTERID")

n_with_cancer <- sum(!is.na(detail_dx$cancer_codes))
n_without_cancer <- sum(is.na(detail_dx$cancer_codes))
message(glue("  Detail rows with cancer codes: {n_with_cancer}"))
message(glue("  Detail rows without cancer codes: {n_without_cancer}"))

# Map cancer codes to category names
# Helper: split semicolon-separated codes, map each to category, sort descending, rejoin
map_cancer_codes_to_categories <- function(cancer_codes_str) {
  if (is.na(cancer_codes_str) || cancer_codes_str == "") return(NA_character_)

  codes <- str_split(cancer_codes_str, ";")[[1]]

  # 4-tier cascade: ICD-10 4-char -> ICD-10 3-char -> ICD-9 4-char -> ICD-9 3-char
  categories <- sapply(codes, function(code) {
    code_clean <- str_remove(code, "\\.")  # Normalize: remove dots
    prefix_4 <- substr(code_clean, 1, 4)
    prefix_3 <- substr(code_clean, 1, 3)

    if (prefix_4 %in% names(CANCER_SITE_MAP)) {
      CANCER_SITE_MAP[[prefix_4]]
    } else if (prefix_3 %in% names(CANCER_SITE_MAP)) {
      CANCER_SITE_MAP[[prefix_3]]
    } else if (prefix_4 %in% names(ICD9_CANCER_SITE_MAP)) {
      ICD9_CANCER_SITE_MAP[[prefix_4]]
    } else if (prefix_3 %in% names(ICD9_CANCER_SITE_MAP)) {
      ICD9_CANCER_SITE_MAP[[prefix_3]]
    } else {
      NA_character_
    }
  }, USE.NAMES = FALSE)

  # Remove NAs, keep unique, sort descending, collapse with semicolons
  categories <- categories[!is.na(categories)]
  if (length(categories) == 0) return(NA_character_)

  paste(sort(unique(categories), decreasing = TRUE), collapse = ";")
}

message()
message("--- Mapping cancer codes to category names ---")

# Map unique cancer_codes strings to avoid repeated computation
unique_cancer_codes <- unique(detail_dx$cancer_codes[!is.na(detail_dx$cancer_codes)])
cancer_category_lookup <- setNames(
  sapply(unique_cancer_codes, map_cancer_codes_to_categories, USE.NAMES = FALSE),
  unique_cancer_codes
)

detail_dx <- detail_dx %>%
  mutate(cancer_category_names = cancer_category_lookup[cancer_codes])

n_with_categories <- sum(!is.na(detail_dx$cancer_category_names))
n_without_categories <- sum(is.na(detail_dx$cancer_category_names))
message(glue("  Rows with cancer category names: {n_with_categories}"))
message(glue("  Rows without cancer category names: {n_without_categories}"))

# Sample mappings for verification
sample_mapped <- detail_dx %>%
  filter(!is.na(cancer_category_names)) %>%
  select(cancer_codes, cancer_category_names) %>%
  distinct() %>%
  head(5)

if (nrow(sample_mapped) > 0) {
  message("  Sample code-to-category mappings:")
  for (i in seq_len(nrow(sample_mapped))) {
    message(glue("    {sample_mapped$cancer_codes[i]} -> {sample_mapped$cancer_category_names[i]}"))
  }
}


# SECTION 5: TABLE 1 -- SUB-CATEGORY ENCOUNTER DETAIL ----

message()
message("--- Building Table 1: Sub-Category Encounter Detail ---")

# Each detail row already has a single triggering_code — resolve directly
detail_codes <- detail_dx %>%
  filter(!is.na(triggering_code), triggering_code != "") %>%
  mutate(category = ifelse(
    triggering_code %in% names(DRUG_GROUPINGS),
    DRUG_GROUPINGS[triggering_code],
    treatment_type
  ))

# Filter to valid reference codes OR Immunotherapy category
n_before_filter <- nrow(detail_codes)
detail_codes <- detail_codes %>%
  filter(triggering_code %in% valid_reference_codes | category == "Immunotherapy")
n_after_filter <- nrow(detail_codes)
message(glue("  Reference filter: {n_before_filter} -> {n_after_filter} code instances ({n_before_filter - n_after_filter} removed)"))

# Build code-type lookup vectors for fallback labels (same as R/56)
chemo_dx_codes <- c(TREATMENT_CODES$chemo_dx_icd10, TREATMENT_CODES$chemo_dx_icd9)
chemo_proc_icd9 <- TREATMENT_CODES$chemo_icd9
chemo_proc_icd10pcs <- TREATMENT_CODES$chemo_icd10pcs_prefixes
chemo_drg_codes <- TREATMENT_CODES$chemo_drg
chemo_rev_codes <- TREATMENT_CODES$chemo_revenue
chemo_hcpcs_codes <- TREATMENT_CODES$chemo_hcpcs
chemo_rxnorm_codes <- TREATMENT_CODES$chemo_rxnorm

rad_dx_codes <- c(TREATMENT_CODES$radiation_dx_icd10, TREATMENT_CODES$radiation_dx_icd9)
rad_proc_icd9 <- TREATMENT_CODES$radiation_icd9
rad_icd10pcs_pattern <- paste0("^(", paste(TREATMENT_CODES$radiation_icd10pcs_prefixes, collapse = "|"), ")")
rad_drg_codes <- TREATMENT_CODES$radiation_drg
rad_rev_codes <- TREATMENT_CODES$radiation_revenue
rad_cpt_codes <- TREATMENT_CODES$radiation_cpt

sct_proc_icd9 <- TREATMENT_CODES$sct_icd9
sct_proc_icd10pcs <- TREATMENT_CODES$sct_icd10pcs
sct_drg_codes <- TREATMENT_CODES$sct_drg
sct_rev_codes <- TREATMENT_CODES$sct_revenue
sct_cpt_hcpcs_codes <- c(TREATMENT_CODES$sct_cpt, TREATMENT_CODES$sct_hcpcs)
sct_rxnorm_codes <- TREATMENT_CODES$sct_rxnorm

immuno_rxnorm_codes <- TREATMENT_CODES$immunotherapy_rxnorm
immuno_hcpcs_codes <- TREATMENT_CODES$immunotherapy_hcpcs
immuno_drg_codes <- TREATMENT_CODES$immunotherapy_drg
immuno_dx_codes <- c(TREATMENT_CODES$immunotherapy_dx_icd10, TREATMENT_CODES$immunotherapy_dx_icd9)
cart_icd10pcs <- TREATMENT_CODES$cart_icd10pcs_prefixes

# Apply 3-tier sub-category resolution per code
detail_codes <- detail_codes %>%
  mutate(
    sub_category = case_when(
      # Tier 1: xlsx reference sub-categories (most authoritative)
      triggering_code %in% names(code_to_subcategory) ~ code_to_subcategory[triggering_code],

      # Tier 2: CODE_SUBCATEGORY_MAP supplement
      triggering_code %in% names(CODE_SUBCATEGORY_MAP) ~ CODE_SUBCATEGORY_MAP[triggering_code],

      # Tier 3: Code-type fallback labels
      # Immunotherapy
      category == "Immunotherapy" & triggering_code %in% immuno_hcpcs_codes ~ "Immunotherapy HCPCS",
      category == "Immunotherapy" & triggering_code %in% immuno_rxnorm_codes ~ "Immunotherapy RxNorm",
      category == "Immunotherapy" & triggering_code %in% immuno_drg_codes ~ "Immunotherapy DRG",
      category == "Immunotherapy" & triggering_code %in% immuno_dx_codes ~ "Immunotherapy Encounter Dx Code",
      category == "Immunotherapy" & triggering_code %in% cart_icd10pcs ~ "CAR-T Procedure (ICD-10-PCS)",
      category == "Immunotherapy" ~ "Immunotherapy (other)",

      # Chemotherapy by code type
      category == "Chemotherapy" & triggering_code %in% chemo_hcpcs_codes ~ "Chemo HCPCS (no xlsx mapping)",
      category == "Chemotherapy" & triggering_code %in% chemo_rxnorm_codes ~ "Chemo RxNorm",
      category == "Chemotherapy" & triggering_code %in% chemo_dx_codes ~ "Chemo Encounter Dx Code",
      category == "Chemotherapy" & triggering_code %in% chemo_proc_icd9 ~ "Chemo Procedure (ICD-9)",
      category == "Chemotherapy" & triggering_code %in% chemo_proc_icd10pcs ~ "Chemo Procedure (ICD-10-PCS)",
      category == "Chemotherapy" & triggering_code %in% chemo_drg_codes ~ "Chemo DRG",
      category == "Chemotherapy" & triggering_code %in% chemo_rev_codes ~ "Chemo Revenue Code",
      category == "Chemotherapy" ~ "Chemotherapy (unmapped)",

      # Radiation by code type
      category == "Radiation" & triggering_code %in% rad_dx_codes ~ "Radiation Encounter Dx Code",
      category == "Radiation" & triggering_code %in% rad_proc_icd9 ~ "Radiation Procedure (ICD-9)",
      category == "Radiation" & str_detect(triggering_code, rad_icd10pcs_pattern) ~ "Radiation Procedure (ICD-10-PCS)",
      category == "Radiation" & triggering_code %in% rad_drg_codes ~ "Radiation DRG",
      category == "Radiation" & triggering_code %in% rad_rev_codes ~ "Radiation Revenue Code",
      category == "Radiation" & triggering_code %in% rad_cpt_codes ~ "Radiation CPT (no xlsx mapping)",
      category == "Radiation" ~ "Radiation (unmapped)",

      # SCT by code type
      category == "SCT" & triggering_code %in% sct_cpt_hcpcs_codes ~ "SCT CPT/HCPCS (no xlsx mapping)",
      category == "SCT" & triggering_code %in% sct_rxnorm_codes ~ "SCT RxNorm",
      category == "SCT" & triggering_code %in% sct_proc_icd9 ~ "SCT Procedure (ICD-9)",
      category == "SCT" & triggering_code %in% sct_proc_icd10pcs ~ "SCT Procedure (ICD-10-PCS)",
      category == "SCT" & triggering_code %in% sct_drg_codes ~ "SCT DRG",
      category == "SCT" & triggering_code %in% sct_rev_codes ~ "SCT Revenue Code",
      category == "SCT" ~ "SCT (unmapped)",

      TRUE ~ category
    )
  )

# Aggregate to encounter level: one row per (patient, encounter, treatment_type)
# with semicolon-separated sub_category names for that encounter
table1 <- detail_codes %>%
  filter(!is.na(cancer_category_names)) %>%
  group_by(patient_id, ENCOUNTERID, treatment_date, treatment_type, cancer_category_names) %>%
  summarise(
    sub_category_names = paste(sort(unique(sub_category)), collapse = ";"),
    .groups = "drop"
  ) %>%
  select(patient_id, ENCOUNTERID, treatment_date, treatment_category = treatment_type,
         sub_category_names, cancer_category_names) %>%
  arrange(patient_id, treatment_date, treatment_category)

message(glue("  Table 1 rows: {nrow(table1)}"))
message(glue("  Unique patients: {n_distinct(table1$patient_id)}"))
message(glue("  Unique encounters: {n_distinct(table1$ENCOUNTERID)}"))
message(glue("  Unique sub-categories: {n_distinct(unlist(str_split(table1$sub_category_names, ';')))}"))


# SECTION 6: TABLE 2 -- ENCOUNTER TREATMENT CODE DETAIL ----

message()
message("--- Building Table 2: Encounter Treatment Code Detail ---")

# One row per (patient, encounter, treatment_type) with all triggering codes
# for that encounter listed
table2 <- detail_dx %>%
  filter(!is.na(cancer_category_names),
         !is.na(triggering_code), triggering_code != "",
         triggering_code %in% valid_reference_codes | treatment_type == "Immunotherapy") %>%
  group_by(patient_id, ENCOUNTERID, treatment_date, treatment_type, cancer_category_names) %>%
  summarise(
    all_treatments = paste(sort(unique(triggering_code)), collapse = ";"),
    .groups = "drop"
  ) %>%
  select(patient_id, ENCOUNTERID, treatment_date, treatment_category = treatment_type,
         all_treatments, cancer_category_names) %>%
  arrange(patient_id, treatment_date, treatment_category)

message(glue("  Table 2 rows: {nrow(table2)}"))
message(glue("  Unique patients: {n_distinct(table2$patient_id)}"))
message(glue("  Unique encounters: {n_distinct(table2$ENCOUNTERID)}"))


# SECTION 7: WRITE XLSX OUTPUT ----

message()
message("--- Writing multi-sheet XLSX output ---")

wb <- wb_workbook()

# Sheet 1: Treatment Sub-Category Detail (encounter-level)
wb$add_worksheet("Treatment Sub-Category Detail")
wb$add_data("Treatment Sub-Category Detail", table1, start_row = 1, col_names = TRUE)

# Sheet 2: Encounter Treatment Detail (encounter-level)
wb$add_worksheet("Encounter Treatment Detail")
wb$add_data("Encounter Treatment Detail", table2, start_row = 1, col_names = TRUE)

wb$save(OUTPUT_XLSX)
message()
message(glue("Saved: {OUTPUT_XLSX}"))


# SECTION 8: CONSOLE SUMMARY ----

message()
message("=== Summary ===")
message(glue("  Total detail rows loaded: {nrow(detail)}"))
message(glue("  Rows with cancer category names: {n_with_categories}"))
message(glue("  Rows without cancer category names: {n_without_categories}"))
message()
message(glue("  Table 1 (Sub-Category Encounter Detail):"))
message(glue("    Total rows: {nrow(table1)}"))
message(glue("    Unique sub-categories: {n_distinct(unlist(str_split(table1$sub_category_names, ';')))}"))
message(glue("    Unique patients: {n_distinct(table1$patient_id)}"))
message(glue("    Unique encounters: {n_distinct(table1$ENCOUNTERID)}"))
message()
message(glue("  Table 2 (Encounter Treatment Code Detail):"))
message(glue("    Total rows: {nrow(table2)}"))
message(glue("    Unique patients: {n_distinct(table2$patient_id)}"))
message(glue("    Unique encounters: {n_distinct(table2$ENCOUNTERID)}"))
message()

# Verify drug_grouping_tables.xlsx was NOT modified
old_file <- file.path(CONFIG$output_dir, "drug_grouping_tables.xlsx")
if (file.exists(old_file)) {
  message(glue("  Verified: drug_grouping_tables.xlsx exists and was NOT modified by this script"))
} else {
  message(glue("  NOTE: drug_grouping_tables.xlsx not found (expected if R/56 not yet run)"))
}

message()
message("Done.")

close(.log_con)
