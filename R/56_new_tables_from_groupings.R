# ==============================================================================
# 56_new_tables_from_groupings.R -- Drug Grouping Summary Tables
# ==============================================================================
#
# Purpose:
#   Generate two drug grouping summary tables matching all_codes_resolved_next_tables.xlsx
#   Sheet1 template. Table 1 breaks down by sub-category (Chemo by medication name,
#   Radiation by type, SCT by type, Immunotherapy as one group) with cancer-only
#   diagnosis codes and encounter counts. Table 2 shows all treatments per encounter.
#
# Inputs:
#   - cache/outputs/treatment_episodes.rds (from R/28, 17 columns including
#     triggering_codes, cancer_category, drug_group, encounter_ids)
#   - data/reference/all_codes_resolved_next_tables_v2.1.xlsx (sub-category mappings:
#     Chemo column C = medication, Radiation column G = type, SCT column G = type)
#   - DuckDB DIAGNOSIS table (for raw ICD cancer codes per encounter)
#   - R/00_config.R (DRUG_GROUPINGS, CANCER_SITE_MAP, CONFIG paths)
#
# Outputs:
#   - output/drug_grouping_tables.xlsx (2-sheet workbook:
#     Sheet 1 = "Treatment Sub-Category Summary", Sheet 2 = "Encounter Treatment Summary")
#
# Dependencies:
#   - R/00_config.R (DRUG_GROUPINGS, CANCER_SITE_MAP, CONFIG paths)
#   - R/utils/utils_assertions.R (assert_rds_exists, assert_df_valid, warn_row_count)
#   - R/utils/utils_duckdb.R (open_pcornet_con, get_pcornet_table)
#   - openxlsx2 (multi-sheet xlsx output)
#
# Requirements:
#   - TREAT-03: Two new summary tables matching all_codes_resolved_next_tables.xlsx
#     Sheet1 templates with sub-category-level and encounter-level summaries
#   - QUAL-01: v2.0 script standards (documentation, assertions, section structure)
#
# Decision Traceability:
#   - D-01: Filter out NA cancer_codes rows from both tables (Phase 81)
#   - D-03: Add category column as first column in Table 1 (Phase 81)
#   - D-04: Category derived from DRUG_GROUPINGS per-code lookup, fallback to treatment_type
#   - D-05: Sort Table 1 by category, then desc(encounter_count) (Phase 81)
#   - D-09: 3-tier lookup: xlsx -> CODE_SUBCATEGORY_MAP -> code-type fallback (Phase 81)
#   - D-12: Single xlsx output with 2 sheets matching templates
#   - D-13: Table 1: category | sub_category | treatment_code | code_type | cancer_codes | encounter_count
#     Chemo by medication (xlsx col C), Radiation by type (xlsx col G),
#     SCT by type (xlsx col G), Immunotherapy as one group
#   - D-14: Table 2: all_treatments | cancer_codes | encounter_count
#   - D-15: Cancer codes = cancer/neoplasm ICD codes only (not all diagnoses),
#     semicolon-separated
#   - D-16: Data source = treatment_episodes.rds + DuckDB DIAGNOSIS join via encounter_ids
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

EPISODES_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
REFERENCE_XLSX <- "data/reference/all_codes_resolved_next_tables_v2.1.xlsx"
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "drug_grouping_tables.xlsx")

# --- Log console output to file ---
LOG_FILE <- file.path(CONFIG$output_dir, "56_new_tables_from_groupings.log")
.log_con <- file(LOG_FILE, open = "wt")

globalCallingHandlers(
  message = function(m) {
    cat(format(Sys.time(), "[%Y-%m-%d %H:%M:%S] "),
        conditionMessage(m),
        file = .log_con, sep = "")
    flush(.log_con)
  }
)

message("=== Phase 79: Drug Grouping Summary Tables ===")
message()
message(glue("  Episodes: {EPISODES_RDS}"))
message(glue("  Reference: {REFERENCE_XLSX}"))
message(glue("  Output: {OUTPUT_XLSX}"))
message()


# SECTION 2: LOAD AND VALIDATE INPUT DATA ----

message("--- Loading treatment episodes ---")

assert_rds_exists(EPISODES_RDS, script_name = "R/56")
episodes <- readRDS(EPISODES_RDS)

assert_df_valid(
  episodes,
  name = "treatment_episodes",
  required_cols = c("patient_id", "treatment_type", "triggering_codes", "cancer_category", "encounter_ids"),
  script_name = "R/56"
)

message(glue("  Loaded {nrow(episodes)} treatment episodes"))
message(glue("  Treatment types: {paste(unique(episodes$treatment_type), collapse = ', ')}"))


# SECTION 3: BUILD SUB-CATEGORY MAPPINGS FROM REFERENCE XLSX ----

message()
message("--- Building sub-category mappings from reference xlsx ---")

assert_file_exists(REFERENCE_XLSX, .var.name = "[R/56 ERROR] Reference XLSX")
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


# SECTION 4: PREPARE CANCER-ONLY CODES FROM ENCOUNTER LINKAGE ----

message()
message("--- Extracting cancer-only ICD codes from encounter linkage ---")

# Build cancer code prefix set from CANCER_SITE_MAP (ICD-10: C00-C96, D00-D49)
# plus ICD-9 neoplasm range (140-239)
cancer_prefixes_icd10 <- names(CANCER_SITE_MAP)
# ICD-9 neoplasm prefixes (140.x-239.x)
cancer_prefixes_icd9 <- as.character(140:239)

message(glue("  Cancer prefixes: {length(cancer_prefixes_icd10)} ICD-10, {length(cancer_prefixes_icd9)} ICD-9"))

# Helper: check if diagnosis codes are cancer/neoplasm codes (vectorized)
is_cancer_code <- function(dx) {
  dx_clean <- str_remove(dx, "\\.")  # Remove dots for prefix matching
  # ICD-10: single regex from all prefixes
  icd10_pattern <- paste0("^(", paste(cancer_prefixes_icd10, collapse = "|"), ")")
  icd10_match <- str_detect(dx_clean, icd10_pattern)
  # ICD-9: 3-char prefix lookup (already vectorized)
  icd9_match <- substr(dx_clean, 1, 3) %in% cancer_prefixes_icd9

  icd10_match | icd9_match
}

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

# Aggregate cancer codes per encounter (semicolon-separated per D-15)
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
pre_join_rows <- nrow(episodes)

episode_dx <- episodes %>%
  mutate(episode_row = row_number()) %>%
  left_join(episode_cancer, by = "episode_row") %>%
  select(-episode_row)

warn_row_count(
  episode_dx,
  name = "episode_dx_joined",
  min_expected = pre_join_rows,
  max_expected = pre_join_rows * 1.1,
  script_name = "R/56"
)

message(glue("  Joined cancer codes to episodes: {nrow(episode_dx)} rows (expected {pre_join_rows})"))

n_missing_cancer <- sum(is.na(episode_dx$cancer_codes))
if (n_missing_cancer > 0) {
  message(glue("  NOTE: {n_missing_cancer} episodes without cancer diagnosis codes"))
}


# SECTION 5: TABLE 1 -- SUB-CATEGORY SUMMARY ----

message()
message("--- Building Table 1: Sub-Category Summary ---")

# Split triggering_codes into individual codes and map to sub-categories
episode_codes <- episode_dx %>%
  mutate(code_list = str_split(triggering_codes, ",\\s*")) %>%
  unnest(code_list) %>%
  filter(!is.na(code_list), code_list != "") %>%
  rename(treatment_code = code_list) %>%
  mutate(category = ifelse(
    treatment_code %in% names(DRUG_GROUPINGS),
    DRUG_GROUPINGS[treatment_code],
    treatment_type  # fallback for codes not in DRUG_GROUPINGS
  ))

# Build code-type lookup vectors from TREATMENT_CODES for sub-category fallback
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

# Assign sub-category based on treatment type and code
episode_codes <- episode_codes %>%
  mutate(
    sub_category = case_when(
      # Tier 1: xlsx reference sub-categories (most authoritative)
      treatment_code %in% names(code_to_subcategory) ~ code_to_subcategory[treatment_code],

      # Tier 2: CODE_SUBCATEGORY_MAP supplement (per D-09)
      treatment_code %in% names(CODE_SUBCATEGORY_MAP) ~ CODE_SUBCATEGORY_MAP[treatment_code],

      # Tier 3: Code-type fallback labels (only for codes in neither lookup)
      # Immunotherapy (use category from DRUG_GROUPINGS, not treatment_type)
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

# Derive code_type: what kind of code is each treatment_code?
# Build combined vectors across all treatment categories for code-type classification
all_hcpcs <- c(TREATMENT_CODES$chemo_hcpcs, TREATMENT_CODES$immunotherapy_hcpcs,
               TREATMENT_CODES$sct_hcpcs)
all_cpt <- c(TREATMENT_CODES$radiation_cpt, TREATMENT_CODES$sct_cpt)
all_rxnorm <- c(TREATMENT_CODES$chemo_rxnorm, TREATMENT_CODES$immunotherapy_rxnorm,
                TREATMENT_CODES$sct_rxnorm)
all_drg <- c(TREATMENT_CODES$chemo_drg, TREATMENT_CODES$radiation_drg,
             TREATMENT_CODES$immunotherapy_drg, TREATMENT_CODES$sct_drg)
all_revenue <- c(TREATMENT_CODES$chemo_revenue, TREATMENT_CODES$radiation_revenue,
                 TREATMENT_CODES$sct_revenue)
all_icd10pcs <- c(TREATMENT_CODES$chemo_icd10pcs_prefixes, TREATMENT_CODES$sct_icd10pcs,
                  TREATMENT_CODES$cart_icd10pcs_prefixes)
all_icd9_proc <- c(TREATMENT_CODES$chemo_icd9, TREATMENT_CODES$radiation_icd9,
                   TREATMENT_CODES$sct_icd9)
all_dx_icd10 <- c(TREATMENT_CODES$chemo_dx_icd10, TREATMENT_CODES$radiation_dx_icd10,
                  TREATMENT_CODES$immunotherapy_dx_icd10)
all_dx_icd9 <- c(TREATMENT_CODES$chemo_dx_icd9, TREATMENT_CODES$radiation_dx_icd9,
                 TREATMENT_CODES$immunotherapy_dx_icd9)
# Radiation ICD-10-PCS uses prefix pattern matching
all_rad_icd10pcs_pattern <- paste0("^(", paste(TREATMENT_CODES$radiation_icd10pcs_prefixes, collapse = "|"), ")")

episode_codes <- episode_codes %>%
  mutate(
    code_type = case_when(
      treatment_code %in% all_dx_icd10 ~ "ICD-10-CM",
      treatment_code %in% all_dx_icd9 ~ "ICD-9-CM",
      treatment_code %in% all_hcpcs ~ "HCPCS",
      treatment_code %in% all_cpt ~ "CPT",
      treatment_code %in% all_rxnorm ~ "RxNorm",
      treatment_code %in% all_icd10pcs ~ "ICD-10-PCS",
      str_detect(treatment_code, all_rad_icd10pcs_pattern) ~ "ICD-10-PCS",
      treatment_code %in% all_icd9_proc ~ "ICD-9 Procedure",
      treatment_code %in% all_drg ~ "DRG",
      treatment_code %in% all_revenue ~ "Revenue",
      TRUE ~ "Unknown"
    )
  )

# Log codes classified by code type (not in xlsx but identified from TREATMENT_CODES)
n_code_typed <- sum(str_detect(episode_codes$sub_category, "HCPCS|RxNorm|Encounter Dx|Procedure|DRG|Revenue|CPT|CAR-T"))
if (n_code_typed > 0) {
  message(glue("  Classified {n_code_typed} code instances by code type (not in reference xlsx)"))
}

# Log truly unmapped codes (not in xlsx AND not in TREATMENT_CODES)
n_unmapped <- sum(str_detect(episode_codes$sub_category, "unmapped"))
if (n_unmapped > 0) {
  message(glue("  WARNING: {n_unmapped} code instances not in xlsx or TREATMENT_CODES"))
  unmapped_codes <- episode_codes %>%
    filter(str_detect(sub_category, "unmapped")) %>%
    distinct(treatment_type, treatment_code) %>%
    head(20)
  for (i in seq_len(nrow(unmapped_codes))) {
    message(glue("    {unmapped_codes$treatment_type[i]}: {unmapped_codes$treatment_code[i]}"))
  }
}

# Log CODE_SUBCATEGORY_MAP resolution stats
n_tier1 <- sum(episode_codes$treatment_code %in% names(code_to_subcategory))
n_tier2 <- sum(
  !episode_codes$treatment_code %in% names(code_to_subcategory) &
  episode_codes$treatment_code %in% names(CODE_SUBCATEGORY_MAP)
)
n_remaining_fallback <- sum(str_detect(episode_codes$sub_category, "no xlsx mapping|no mapping|unmapped|other|RxNorm|DRG|Revenue|Encounter Dx|Procedure|CAR-T"))
message(glue("  Sub-category resolution: {n_tier1} xlsx, {n_tier2} CODE_SUBCATEGORY_MAP, {n_remaining_fallback} code-type fallback"))

# Custom category sort order (logical treatment sequence, not alphabetical)
category_order <- c("Chemotherapy", "Immunotherapy", "Radiation", "SCT")

# Aggregate: one row per sub_category + cancer_codes combination
table1 <- episode_codes %>%
  filter(!is.na(cancer_codes)) %>%  # Per D-01: exclude rows without cancer diagnosis codes
  mutate(category = factor(category, levels = category_order)) %>%  # Per D-05: custom sort order
  group_by(category, sub_category, treatment_code, code_type, cancer_codes) %>%
  summarise(encounter_count = n(), .groups = "drop") %>%
  arrange(category, desc(encounter_count)) %>%  # Per D-05: category first, then desc count
  mutate(category = as.character(category))  # Convert back from factor for xlsx output

message(glue("  Table 1: {nrow(table1)} rows across {n_distinct(table1$sub_category)} sub-categories"))

# Log per sub-category totals
subcat_summary <- table1 %>%
  group_by(sub_category) %>%
  summarise(total = sum(encounter_count), rows = n(), .groups = "drop") %>%
  arrange(desc(total))

for (i in seq_len(min(nrow(subcat_summary), 20))) {
  message(glue("    {subcat_summary$sub_category[i]}: {subcat_summary$total[i]} encounters, {subcat_summary$rows[i]} rows"))
}
if (nrow(subcat_summary) > 20) {
  message(glue("    ... and {nrow(subcat_summary) - 20} more sub-categories"))
}


# SECTION 6: TABLE 2 -- ENCOUNTER TREATMENT SUMMARY ----

message()
message("--- Building Table 2: Encounter Treatment Summary ---")

# For each episode: combine all triggering_codes into "all treatments in encounter"
table2 <- episode_dx %>%
  filter(!is.na(cancer_codes)) %>%  # Per D-01: exclude rows without cancer diagnosis codes
  mutate(all_treatments = triggering_codes) %>%
  group_by(all_treatments, cancer_codes) %>%
  summarise(encounter_count = n(), .groups = "drop") %>%
  arrange(desc(encounter_count))

message(glue("  Table 2: {nrow(table2)} unique treatment-set x cancer-code combinations"))
message(glue("  Unique treatment sets: {n_distinct(table2$all_treatments)}"))


# SECTION 7: WRITE XLSX OUTPUT (per D-12) ----

message()
message("--- Writing multi-sheet XLSX output ---")

wb <- wb_workbook()

# Sheet 1: Sub-Category Summary
wb$add_worksheet("Treatment Sub-Category Summary")
wb$add_data("Treatment Sub-Category Summary", table1, start_row = 1, col_names = TRUE)

# Sheet 2: Encounter Treatment Summary
wb$add_worksheet("Encounter Treatment Summary")
wb$add_data("Encounter Treatment Summary", table2, start_row = 1, col_names = TRUE)

wb$save(OUTPUT_XLSX)
message()
message(glue("Saved: {OUTPUT_XLSX}"))


# SECTION 8: CONSOLE SUMMARY ----

message()
message("=== Summary ===")
message(glue("  Total episodes processed: {nrow(episodes)}"))
message(glue("  Episodes with cancer codes: {sum(!is.na(episode_dx$cancer_codes))}"))
message(glue("  Episodes without cancer codes: {n_missing_cancer}"))
message(glue("  Total diagnosis records: {nrow(dx_data)}"))
message(glue("  Cancer diagnosis records: {nrow(dx_cancer)}"))
message()
message(glue("  Table 1 (Sub-Category Summary):"))
message(glue("    Total rows: {nrow(table1)}"))
message(glue("    Categories: {paste(unique(table1$category), collapse = ', ')}"))
message(glue("    Sub-categories: {n_distinct(table1$sub_category)}"))
message()
message(glue("  Table 2 (Encounter Treatment Summary):"))
message(glue("    Total rows: {nrow(table2)}"))
message(glue("    Unique treatment sets: {n_distinct(table2$all_treatments)}"))
message()
message("Done.")

close(.log_con)
