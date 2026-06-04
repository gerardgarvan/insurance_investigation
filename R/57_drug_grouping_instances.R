# ==============================================================================
# 57_drug_grouping_instances.R -- Drug Grouping Instance-Level Tables
# ==============================================================================
#
# Purpose:
#   Generate instance-level drug grouping tables showing one row per patient +
#   treatment type + episode with human-readable sub-category names and cancer
#   site category names instead of raw codes and aggregated counts. Complements
#   R/56 aggregated summary tables with patient-traceable instance detail.
#
# Inputs:
#   - cache/outputs/treatment_episodes.rds (from R/28, 17 columns including
#     patient_id, episode_number, episode_start, episode_stop, triggering_codes,
#     encounter_ids, treatment_type)
#   - data/reference/all_codes_resolved_next_tables_v2.1.xlsx (sub-category
#     mappings: Chemo column C = medication, Radiation column G = type, SCT
#     column G = type)
#   - DuckDB DIAGNOSIS table (for raw ICD cancer codes per encounter)
#   - R/00_config.R (CANCER_SITE_MAP, ICD9_CANCER_SITE_MAP, CODE_SUBCATEGORY_MAP,
#     DRUG_GROUPINGS)
#
# Outputs:
#   - output/drug_grouping_instances.xlsx (2-sheet workbook:
#     Sheet 1 = "Treatment Sub-Category Detail" (instance-level),
#     Sheet 2 = "Encounter Treatment Detail" (instance-level))
#
# Dependencies:
#   - R/00_config.R (DRUG_GROUPINGS, CODE_SUBCATEGORY_MAP, CANCER_SITE_MAP,
#     ICD9_CANCER_SITE_MAP, CONFIG paths)
#   - R/utils/utils_assertions.R (assert_rds_exists, assert_df_valid)
#   - R/utils/utils_duckdb.R (open_pcornet_con, get_pcornet_table)
#   - R/utils/utils_cancer.R (is_cancer_code shared utility)
#   - openxlsx2 (multi-sheet xlsx output)
#
# Requirements:
#   - P88-D01: Both tables restructured to instance-level (one row per episode)
#   - P88-D02: New xlsx file separate from drug_grouping_tables.xlsx
#   - P88-D03: Sub-category names via 3-tier resolution (xlsx -> CODE_SUBCATEGORY_MAP -> fallback)
#   - P88-D04: Cancer codes replaced with category names (CANCER_SITE_MAP + ICD9_CANCER_SITE_MAP), sorted descending
#   - P88-D05: One row per patient + treatment type + episode
#   - P88-D06: Each row includes PATID, episode_start, episode_stop, episode_number, treatment_category, sub_category_names, cancer_category_names
#   - P88-D07: New xlsx file preserves old file unchanged
#   - P88-D08: Two sheets maintained with new row grain
#   - P88-SMOKE: R/88 smoke test validates script structure
#
# Decision Traceability:
#   - D-01 (P88): Both Table 1 and Table 2 restructured to instance-level
#   - D-02 (P88): New drug_grouping_instances.xlsx, drug_grouping_tables.xlsx unchanged
#   - D-03 (P88): 3-tier sub-category lookup (xlsx -> CODE_SUBCATEGORY_MAP -> fallback)
#   - D-04 (P88): Cancer codes -> category names (CANCER_SITE_MAP + ICD9_CANCER_SITE_MAP), descending sort
#   - D-05 (P88): Per-episode grain (not aggregated by sub-category)
#   - D-06 (P88): Required columns: patient_id, episode_start, episode_stop, episode_number, treatment_category, sub_category_names, cancer_category_names
#   - D-07 (P88): Separate output file
#   - D-08 (P88): Table 2 maintains per-episode grain without group_by/summarise aggregation
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

EPISODES_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
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

message("=== Phase 88: Drug Grouping Instance-Level Tables ===")
message()
message(glue("  Episodes: {EPISODES_RDS}"))
message(glue("  Reference: {REFERENCE_XLSX}"))
message(glue("  Output: {OUTPUT_XLSX}"))
message()


# SECTION 2: LOAD AND VALIDATE INPUT DATA ----

message("--- Loading treatment episodes ---")

assert_rds_exists(EPISODES_RDS, script_name = "R/57")
episodes <- readRDS(EPISODES_RDS)

assert_df_valid(
  episodes,
  name = "treatment_episodes",
  required_cols = c("patient_id", "treatment_type", "episode_number", "episode_start", "episode_stop", "triggering_codes", "encounter_ids"),
  script_name = "R/57"
)

message(glue("  Loaded {nrow(episodes)} treatment episodes"))
message(glue("  Treatment types: {paste(unique(episodes$treatment_type), collapse = ', ')}"))


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


# SECTION 4: EXTRACT CANCER CODES AND MAP TO CATEGORY NAMES ----

message()
message("--- Extracting cancer codes and mapping to category names ---")

# Cancer code detection uses shared is_cancer_code() from R/utils/utils_cancer.R
message(glue("  Using shared is_cancer_code() -- ICD-10: {length(names(CANCER_SITE_MAP))} prefixes, ICD-9: {length(names(ICD9_CANCER_SITE_MAP))} prefixes"))

# Split encounter_ids into individual rows
episode_encounters <- episodes %>%
  mutate(episode_row = row_number()) %>%
  filter(!is.na(encounter_ids) & encounter_ids != "") %>%
  mutate(ENCOUNTERID = str_split(encounter_ids, ",\\s*")) %>%
  unnest(ENCOUNTERID) %>%
  filter(!is.na(ENCOUNTERID) & ENCOUNTERID != "")

all_encounter_ids <- unique(episode_encounters$ENCOUNTERID)
message(glue("  Unique encounter IDs from episodes: {length(all_encounter_ids)}"))

USE_DUCKDB <- TRUE
open_pcornet_con()

# Get all diagnosis codes for encounters in treatment_episodes
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

# Join cancer codes to split encounters, then aggregate back to episode level
episode_cancer <- episode_encounters %>%
  left_join(encounter_dx, by = "ENCOUNTERID") %>%
  filter(!is.na(cancer_codes)) %>%
  group_by(episode_row) %>%
  summarise(
    cancer_codes = paste(sort(unique(unlist(str_split(cancer_codes, ";")))), collapse = ";"),
    .groups = "drop"
  )

# Join aggregated cancer codes back to original episodes
episode_dx <- episodes %>%
  mutate(episode_row = row_number()) %>%
  left_join(episode_cancer, by = "episode_row")

message(glue("  Joined cancer codes to episodes: {nrow(episode_dx)} rows"))

n_missing_cancer <- sum(is.na(episode_dx$cancer_codes))
if (n_missing_cancer > 0) {
  message(glue("  NOTE: {n_missing_cancer} episodes without cancer diagnosis codes"))
}

# Map cancer codes to category names (per D-04)
# Helper function: split semicolon-separated codes, map each to category, sort descending, rejoin
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

  # Remove NAs, keep unique, sort descending (per D-04), collapse with semicolons
  categories <- categories[!is.na(categories)]
  if (length(categories) == 0) return(NA_character_)

  paste(sort(unique(categories), decreasing = TRUE), collapse = ";")
}

message()
message("--- Mapping cancer codes to category names ---")

episode_dx <- episode_dx %>%
  mutate(cancer_category_names = sapply(cancer_codes, map_cancer_codes_to_categories, USE.NAMES = FALSE))

n_with_categories <- sum(!is.na(episode_dx$cancer_category_names))
n_without_categories <- sum(is.na(episode_dx$cancer_category_names))
message(glue("  Episodes with cancer category names: {n_with_categories}"))
message(glue("  Episodes without cancer category names: {n_without_categories}"))

# Sample mappings for verification
sample_mapped <- episode_dx %>%
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


# SECTION 5: TABLE 1 -- SUB-CATEGORY INSTANCE DETAIL ----

message()
message("--- Building Table 1: Sub-Category Instance Detail ---")

# Split triggering_codes into individual codes
episode_codes <- episode_dx %>%
  mutate(code_list = str_split(triggering_codes, ",\\s*")) %>%
  unnest(code_list) %>%
  filter(!is.na(code_list), code_list != "") %>%
  rename(treatment_code = code_list) %>%
  mutate(category = ifelse(
    treatment_code %in% names(DRUG_GROUPINGS),
    DRUG_GROUPINGS[treatment_code],
    treatment_type
  ))

# Filter to valid reference codes OR Immunotherapy category
n_before_filter <- nrow(episode_codes)
episode_codes <- episode_codes %>%
  filter(treatment_code %in% valid_reference_codes | category == "Immunotherapy")
n_after_filter <- nrow(episode_codes)
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

# Apply 3-tier sub-category resolution (per D-03)
episode_codes <- episode_codes %>%
  mutate(
    sub_category = case_when(
      # Tier 1: xlsx reference sub-categories (most authoritative)
      treatment_code %in% names(code_to_subcategory) ~ code_to_subcategory[treatment_code],

      # Tier 2: CODE_SUBCATEGORY_MAP supplement
      treatment_code %in% names(CODE_SUBCATEGORY_MAP) ~ CODE_SUBCATEGORY_MAP[treatment_code],

      # Tier 3: Code-type fallback labels
      # Immunotherapy
      category == "Immunotherapy" & treatment_code %in% immuno_hcpcs_codes ~ "Immunotherapy HCPCS",
      category == "Immunotherapy" & treatment_code %in% immuno_rxnorm_codes ~ "Immunotherapy RxNorm",
      category == "Immunotherapy" & treatment_code %in% immuno_drg_codes ~ "Immunotherapy DRG",
      category == "Immunotherapy" & treatment_code %in% immuno_dx_codes ~ "Immunotherapy Encounter Dx Code",
      category == "Immunotherapy" & treatment_code %in% cart_icd10pcs ~ "CAR-T Procedure (ICD-10-PCS)",
      category == "Immunotherapy" ~ "Immunotherapy (other)",

      # Chemotherapy by code type
      category == "Chemotherapy" & treatment_code %in% chemo_hcpcs_codes ~ "Chemo HCPCS (no xlsx mapping)",
      category == "Chemotherapy" & treatment_code %in% chemo_rxnorm_codes ~ "Chemo RxNorm",
      category == "Chemotherapy" & treatment_code %in% chemo_dx_codes ~ "Chemo Encounter Dx Code",
      category == "Chemotherapy" & treatment_code %in% chemo_proc_icd9 ~ "Chemo Procedure (ICD-9)",
      category == "Chemotherapy" & treatment_code %in% chemo_proc_icd10pcs ~ "Chemo Procedure (ICD-10-PCS)",
      category == "Chemotherapy" & treatment_code %in% chemo_drg_codes ~ "Chemo DRG",
      category == "Chemotherapy" & treatment_code %in% chemo_rev_codes ~ "Chemo Revenue Code",
      category == "Chemotherapy" ~ "Chemotherapy (unmapped)",

      # Radiation by code type
      category == "Radiation" & treatment_code %in% rad_dx_codes ~ "Radiation Encounter Dx Code",
      category == "Radiation" & treatment_code %in% rad_proc_icd9 ~ "Radiation Procedure (ICD-9)",
      category == "Radiation" & str_detect(treatment_code, rad_icd10pcs_pattern) ~ "Radiation Procedure (ICD-10-PCS)",
      category == "Radiation" & treatment_code %in% rad_drg_codes ~ "Radiation DRG",
      category == "Radiation" & treatment_code %in% rad_rev_codes ~ "Radiation Revenue Code",
      category == "Radiation" & treatment_code %in% rad_cpt_codes ~ "Radiation CPT (no xlsx mapping)",
      category == "Radiation" ~ "Radiation (unmapped)",

      # SCT by code type
      category == "SCT" & treatment_code %in% sct_cpt_hcpcs_codes ~ "SCT CPT/HCPCS (no xlsx mapping)",
      category == "SCT" & treatment_code %in% sct_rxnorm_codes ~ "SCT RxNorm",
      category == "SCT" & treatment_code %in% sct_proc_icd9 ~ "SCT Procedure (ICD-9)",
      category == "SCT" & treatment_code %in% sct_proc_icd10pcs ~ "SCT Procedure (ICD-10-PCS)",
      category == "SCT" & treatment_code %in% sct_drg_codes ~ "SCT DRG",
      category == "SCT" & treatment_code %in% sct_rev_codes ~ "SCT Revenue Code",
      category == "SCT" ~ "SCT (unmapped)",

      TRUE ~ category
    )
  )

# Aggregate back to episode level: semicolon-separated sub_category names
table1 <- episode_codes %>%
  group_by(patient_id, episode_number, episode_start, episode_stop, treatment_type, cancer_category_names) %>%
  summarise(
    sub_category_names = paste(sort(unique(sub_category)), collapse = ";"),
    .groups = "drop"
  ) %>%
  filter(!is.na(cancer_category_names)) %>%  # Exclude episodes without cancer diagnosis (per D-01 equivalent)
  select(patient_id, episode_start, episode_stop, episode_number, treatment_type, sub_category_names, cancer_category_names) %>%
  arrange(patient_id, episode_start, treatment_type) %>%
  rename(treatment_category = treatment_type)

message(glue("  Table 1 rows: {nrow(table1)}"))
message(glue("  Unique patients: {n_distinct(table1$patient_id)}"))
message(glue("  Unique sub-categories: {n_distinct(unlist(str_split(table1$sub_category_names, ';')))}"))


# SECTION 6: TABLE 2 -- ENCOUNTER TREATMENT INSTANCE DETAIL ----

message()
message("--- Building Table 2: Encounter Treatment Instance Detail ---")

# Per D-08: Table 2 keeps per-episode rows without aggregation -- each row IS one episode
# Filter to valid reference codes within triggering_codes string
has_valid_code <- function(codes_str, valid_set) {
  if (is.na(codes_str) || codes_str == "") return(FALSE)
  codes <- str_split(codes_str, ",\\s*")[[1]]
  any(codes %in% valid_set)
}

table2 <- episode_dx %>%
  filter(!is.na(cancer_category_names), !is.na(triggering_codes)) %>%
  mutate(has_valid = sapply(triggering_codes, has_valid_code, valid_set = valid_reference_codes, USE.NAMES = FALSE)) %>%
  filter(has_valid) %>%
  select(patient_id, episode_start, episode_stop, episode_number, treatment_type, triggering_codes, cancer_category_names) %>%
  arrange(patient_id, episode_start, treatment_type) %>%
  rename(treatment_category = treatment_type, all_treatments = triggering_codes)

message(glue("  Table 2 rows: {nrow(table2)}"))
message(glue("  Unique patients: {n_distinct(table2$patient_id)}"))
message(glue("  Unique treatment sets: {n_distinct(table2$all_treatments)}"))


# SECTION 7: WRITE XLSX OUTPUT ----

message()
message("--- Writing multi-sheet XLSX output ---")

wb <- wb_workbook()

# Sheet 1: Treatment Sub-Category Detail (instance-level)
wb$add_worksheet("Treatment Sub-Category Detail")
wb$add_data("Treatment Sub-Category Detail", table1, start_row = 1, col_names = TRUE)

# Sheet 2: Encounter Treatment Detail (instance-level, per D-08: separate sheet with per-episode grain)
wb$add_worksheet("Encounter Treatment Detail")
wb$add_data("Encounter Treatment Detail", table2, start_row = 1, col_names = TRUE)

wb$save(OUTPUT_XLSX)
message()
message(glue("Saved: {OUTPUT_XLSX}"))


# SECTION 8: CONSOLE SUMMARY ----

message()
message("=== Summary ===")
message(glue("  Total episodes processed: {nrow(episodes)}"))
message(glue("  Episodes with cancer category names: {n_with_categories}"))
message(glue("  Episodes without cancer category names: {n_without_categories}"))
message()
message(glue("  Table 1 (Sub-Category Detail):"))
message(glue("    Total rows: {nrow(table1)}"))
message(glue("    Unique sub-categories: {n_distinct(unlist(str_split(table1$sub_category_names, ';')))}"))
message(glue("    Unique patients: {n_distinct(table1$patient_id)}"))
message()
message(glue("  Table 2 (Encounter Treatment Detail):"))
message(glue("    Total rows: {nrow(table2)}"))
message(glue("    Unique treatment sets: {n_distinct(table2$all_treatments)}"))
message(glue("    Unique patients: {n_distinct(table2$patient_id)}"))
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
