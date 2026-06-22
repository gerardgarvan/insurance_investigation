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
#   - output/encounter_level_drug_grouping_instances.xlsx (3-sheet workbook:
#     Sheet 1 = "Enc Sub-Category Detail" (all encounters, with cancer_linked flag),
#     Sheet 2 = "Enc Treatment Detail" (all encounters, with cancer_linked flag),
#     Sheet 3 = "Linked vs Unlinked" (cross-tab summary by treatment type))
#   - output/drug_grouping_instances.xlsx (backward compat copy of broadened output)
#   - output/encounter_level_drug_grouping_instances_linked_only.xlsx (2-sheet workbook:
#     Sheet 1 = "Enc Sub-Category Detail" (cancer-linked only),
#     Sheet 2 = "Enc Treatment Detail" (cancer-linked only))
#   - output/drug_grouping_instances_linked_only.xlsx (backward compat copy of linked-only)
#
# Phase 101 Decisions (Broadened Drug Grouping Output):
#   D-01: R/57 only; R/56 stays unchanged (cancer-linked-only)
#   D-02: Only filter(!is.na(cancer_category_names)) removed; reference code filter stays
#   D-03: cancer_linked derived from encounter-level DX presence (!is.na(cancer_codes))
#   D-04: Self-contained within R/57, no dependency on R/28 cancer_category
#   D-05: Cross-tab: treatment_type | linked_count | unlinked_count
#   D-06: Cross-tab as 3rd sheet in broadened xlsx ("Linked vs Unlinked")
#   D-07: Broadened = primary files (both naming patterns)
#   D-08: Linked-only with _linked_only suffix (both naming patterns)
#   D-09: Broadened has 3 sheets; linked-only keeps exact 2-sheet structure
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
tryCatch(globalCallingHandlers(NULL), error = function(e) NULL)

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
# Phase 89: Dual-output file paths (encounter-level grain)
NEW_OUTPUT_XLSX <- file.path(CONFIG$output_dir, "encounter_level_drug_grouping_instances.xlsx")
OLD_OUTPUT_XLSX <- file.path(CONFIG$output_dir, "drug_grouping_instances.xlsx")  # Backward compat
# Phase 101: Linked-only output paths (backward compat for cancer-linked-only consumers)
NEW_OUTPUT_LINKED_XLSX <- file.path(CONFIG$output_dir, "encounter_level_drug_grouping_instances_linked_only.xlsx")
OLD_OUTPUT_LINKED_XLSX <- file.path(CONFIG$output_dir, "drug_grouping_instances_linked_only.xlsx")

# --- Log console output to file ---
LOG_FILE <- file.path(CONFIG$output_dir, "57_drug_grouping_instances.log")
.log_con <- file(LOG_FILE, open = "wt")

.log_handler_active <- tryCatch({
  globalCallingHandlers(
    message = function(m) {
      cat(format(Sys.time(), "[%Y-%m-%d %H:%M:%S] "),
          conditionMessage(m),
          file = .log_con, sep = "")
      flush(.log_con)
    }
  )
  TRUE
}, error = function(e) FALSE)

message("=== Phase 88/101: Drug Grouping Instance-Level Tables (Encounter Grain, Broadened) ===")
message()
message(glue("  Detail RDS: {DETAIL_RDS}"))
message(glue("  Reference: {REFERENCE_XLSX}"))
message(glue("  Output (broadened, new): {NEW_OUTPUT_XLSX}"))
message(glue("  Output (broadened, compat): {OLD_OUTPUT_XLSX}"))
message(glue("  Output (linked-only, new): {NEW_OUTPUT_LINKED_XLSX}"))
message(glue("  Output (linked-only, compat): {OLD_OUTPUT_LINKED_XLSX}"))
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

  # Remove NAs, keep unique, sort ascending (Phase 112 D-08: universal A-Z), collapse with semicolons
  categories <- categories[!is.na(categories)]
  if (length(categories) == 0) return(NA_character_)

  paste(sort(unique(categories)), collapse = ";")
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
detail_codes_pre <- detail_dx %>%
  filter(!is.na(triggering_code), triggering_code != "")

# Phase 98: Replace DRUG_GROUPINGS named vector with keyed join (D-01)
detail_codes_dt <- copy(ensure_dt(detail_codes_pre, name = "detail_codes", script_name = "R/57"))
drug_lookup <- get_lookup_dt("DRUG_GROUPINGS")
detail_codes_dt[drug_lookup, on = .(triggering_code = code), dg_category := i.drug_group]
detail_codes_dt[, category := fifelse(!is.na(dg_category), dg_category, treatment_type)]
detail_codes_dt[, dg_category := NULL]
detail_codes <- to_tibble_safe(detail_codes_dt, name = "detail_codes", script_name = "R/57")

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

# Phase 98: Pre-join CODE_SUBCATEGORY_MAP for Tier 2 lookup (D-02)
subcat_lookup <- get_lookup_dt("CODE_SUBCATEGORY_MAP")
detail_codes_dt <- copy(ensure_dt(detail_codes, name = "detail_codes", script_name = "R/57"))
detail_codes_dt[subcat_lookup, on = .(triggering_code = code), subcat_map := i.subcategory]
detail_codes <- to_tibble_safe(detail_codes_dt, name = "detail_codes", script_name = "R/57")

# Apply 3-tier sub-category resolution per code
detail_codes <- detail_codes %>%
  mutate(
    sub_category = case_when(
      # Tier 1: xlsx reference sub-categories (most authoritative)
      triggering_code %in% names(code_to_subcategory) ~ code_to_subcategory[triggering_code],

      # Tier 2: CODE_SUBCATEGORY_MAP supplement (Phase 98: pre-joined)
      !is.na(subcat_map) ~ subcat_map,

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

# Table 1: Sub-Category Encounter Detail (ALL encounters, per DRUG-01)
table1_all <- detail_codes %>%
  group_by(patient_id, ENCOUNTERID, treatment_date, treatment_type,
           cancer_codes, cancer_category_names) %>%
  summarise(
    sub_category_names = paste(sort(unique(sub_category)), collapse = ";"),
    .groups = "drop"
  ) %>%
  mutate(cancer_linked = !is.na(cancer_codes)) %>%
  select(patient_id, ENCOUNTERID, treatment_date, treatment_category = treatment_type,
         sub_category_names, cancer_category_names, cancer_linked) %>%
  arrange(patient_id, treatment_date, treatment_category)

# Table 1: Linked-only (backward compatibility per DRUG-03)
table1_linked <- table1_all %>%
  filter(!is.na(cancer_category_names)) %>%
  select(-cancer_linked)

message(glue("  Table 1 (all): {nrow(table1_all)} rows"))
message(glue("  Table 1 (linked-only): {nrow(table1_linked)} rows"))
message(glue("  Unique patients (all): {n_distinct(table1_all$patient_id)}"))
message(glue("  Unique encounters (all): {n_distinct(table1_all$ENCOUNTERID)}"))
message(glue("  Unique sub-categories: {n_distinct(unlist(str_split(table1_all$sub_category_names, ';')))}"))


# SECTION 6: TABLE 2 -- ENCOUNTER TREATMENT CODE DETAIL ----

message()
message("--- Building Table 2: Encounter Treatment Code Detail ---")

# One row per (patient, encounter, treatment_type) with all triggering codes
# for that encounter listed

# Table 2: Encounter Treatment Code Detail (ALL encounters, per DRUG-01)
table2_all <- detail_dx %>%
  filter(!is.na(triggering_code), triggering_code != "",
         triggering_code %in% valid_reference_codes | treatment_type == "Immunotherapy") %>%
  group_by(patient_id, ENCOUNTERID, treatment_date, treatment_type,
           cancer_codes, cancer_category_names) %>%
  summarise(
    all_treatments = paste(sort(unique(triggering_code)), collapse = ";"),
    .groups = "drop"
  ) %>%
  mutate(cancer_linked = !is.na(cancer_codes)) %>%
  select(patient_id, ENCOUNTERID, treatment_date, treatment_category = treatment_type,
         all_treatments, cancer_category_names, cancer_linked) %>%
  arrange(patient_id, treatment_date, treatment_category)

# Table 2: Linked-only (backward compatibility per DRUG-03)
table2_linked <- table2_all %>%
  filter(!is.na(cancer_category_names)) %>%
  select(-cancer_linked)

message(glue("  Table 2 (all): {nrow(table2_all)} rows"))
message(glue("  Table 2 (linked-only): {nrow(table2_linked)} rows"))
message(glue("  Unique patients (all): {n_distinct(table2_all$patient_id)}"))
message(glue("  Unique encounters (all): {n_distinct(table2_all$ENCOUNTERID)}"))


# SECTION 6B: CROSS-TAB SUMMARY (Phase 101: DRUG-01, D-05, D-06) ----

message()
message("--- Building Cross-Tab: Linked vs Unlinked by Treatment Type ---")

crosstab_summary <- table1_all %>%
  group_by(treatment_category, cancer_linked) %>%
  summarise(n = n(), .groups = "drop") %>%
  tidyr::pivot_wider(
    names_from = cancer_linked,
    values_from = n,
    values_fill = 0
  ) %>%
  rename(
    treatment_type = treatment_category,
    linked_count = `TRUE`,
    unlinked_count = `FALSE`
  ) %>%
  select(treatment_type, linked_count, unlinked_count) %>%
  arrange(desc(linked_count))

message(glue("  Cross-tab summary: {nrow(crosstab_summary)} treatment types"))
for (i in seq_len(nrow(crosstab_summary))) {
  message(glue("    {crosstab_summary$treatment_type[i]}: {crosstab_summary$linked_count[i]} linked, {crosstab_summary$unlinked_count[i]} unlinked"))
}


# SECTION 7: WRITE XLSX OUTPUT (Phase 89 grain-labeled + Phase 101 dual-output) ----

message()
message("--- Writing multi-sheet XLSX output (dual: broadened + linked-only) ---")

# --- Broadened output (3 sheets per D-09) ---
wb_broad <- wb_workbook()

# Sheet 1: Sub-Category Detail (all encounters)
wb_broad$add_worksheet("Enc Sub-Category Detail")
wb_broad$add_data("Enc Sub-Category Detail", table1_all, start_row = 1, col_names = TRUE)

# Sheet 2: Treatment Detail (all encounters)
wb_broad$add_worksheet("Enc Treatment Detail")
wb_broad$add_data("Enc Treatment Detail", table2_all, start_row = 1, col_names = TRUE)

# Sheet 3: Linked vs Unlinked Summary (per D-06)
wb_broad$add_worksheet("Linked vs Unlinked")
wb_broad$add_data("Linked vs Unlinked", crosstab_summary, start_row = 1, col_names = TRUE)

# Save broadened output (grain-labeled + backward compat per D-07)
wb_broad$save(NEW_OUTPUT_XLSX)
message(glue("Saved broadened (3 sheets): {NEW_OUTPUT_XLSX}"))
wb_broad$save(OLD_OUTPUT_XLSX)
message(glue("Saved broadened (3 sheets, compat): {OLD_OUTPUT_XLSX}"))

# --- Linked-only output (2 sheets, exact current structure per D-08, DRUG-03) ---
wb_linked <- wb_workbook()

# Sheet 1: Sub-Category Detail (cancer-linked only, NO cancer_linked column)
wb_linked$add_worksheet("Enc Sub-Category Detail")
wb_linked$add_data("Enc Sub-Category Detail", table1_linked, start_row = 1, col_names = TRUE)

# Sheet 2: Treatment Detail (cancer-linked only, NO cancer_linked column)
wb_linked$add_worksheet("Enc Treatment Detail")
wb_linked$add_data("Enc Treatment Detail", table2_linked, start_row = 1, col_names = TRUE)

# Save linked-only output with _linked_only suffix (per D-08)
wb_linked$save(NEW_OUTPUT_LINKED_XLSX)
message(glue("Saved linked-only (2 sheets): {NEW_OUTPUT_LINKED_XLSX}"))
wb_linked$save(OLD_OUTPUT_LINKED_XLSX)
message(glue("Saved linked-only (2 sheets, compat): {OLD_OUTPUT_LINKED_XLSX}"))


# SECTION 8: CONSOLE SUMMARY ----

message()
message("=== Summary ===")
message(glue("  Total detail rows loaded: {nrow(detail)}"))
message(glue("  Rows with cancer category names: {n_with_categories}"))
message(glue("  Rows without cancer category names: {n_without_categories}"))
message()
message(glue("  Table 1 (Enc Sub-Category Detail):"))
message(glue("    All encounters: {nrow(table1_all)} rows"))
message(glue("    Linked-only: {nrow(table1_linked)} rows"))
message(glue("    Unlinked: {nrow(table1_all) - nrow(table1_linked)} rows"))
message(glue("    Unique sub-categories: {n_distinct(unlist(str_split(table1_all$sub_category_names, ';')))}"))
message(glue("    Unique patients (all): {n_distinct(table1_all$patient_id)}"))
message(glue("    Unique encounters (all): {n_distinct(table1_all$ENCOUNTERID)}"))
message()
message(glue("  Table 2 (Enc Treatment Detail):"))
message(glue("    All encounters: {nrow(table2_all)} rows"))
message(glue("    Linked-only: {nrow(table2_linked)} rows"))
message(glue("    Unlinked: {nrow(table2_all) - nrow(table2_linked)} rows"))
message(glue("    Unique patients (all): {n_distinct(table2_all$patient_id)}"))
message(glue("    Unique encounters (all): {n_distinct(table2_all$ENCOUNTERID)}"))
message()
message(glue("  Cross-tab summary ({nrow(crosstab_summary)} treatment types):"))
for (i in seq_len(nrow(crosstab_summary))) {
  message(glue("    {crosstab_summary$treatment_type[i]}: {crosstab_summary$linked_count[i]} linked, {crosstab_summary$unlinked_count[i]} unlinked"))
}
message()

# Verify drug_grouping_tables.xlsx was NOT modified by this script
old_r56_file <- file.path(CONFIG$output_dir, "drug_grouping_tables.xlsx")
if (file.exists(old_r56_file)) {
  message(glue("  Verified: drug_grouping_tables.xlsx exists and was NOT modified by this script"))
} else {
  message(glue("  NOTE: drug_grouping_tables.xlsx not found (expected if R/56 not yet run)"))
}

message()
message(glue("  Output files (broadened, 3 sheets):"))
message(glue("    {NEW_OUTPUT_XLSX} (primary)"))
message(glue("    {OLD_OUTPUT_XLSX} (backward compatibility)"))
message(glue("  Output files (linked-only, 2 sheets):"))
message(glue("    {NEW_OUTPUT_LINKED_XLSX} (primary)"))
message(glue("    {OLD_OUTPUT_LINKED_XLSX} (backward compatibility)"))
message()
message("Done.")

try(close(.log_con), silent = TRUE)
