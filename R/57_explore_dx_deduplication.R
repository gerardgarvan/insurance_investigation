# ==============================================================================
# 57_explore_dx_deduplication.R -- Encounter-level Dx Code Co-Occurrence Analysis
# ==============================================================================
#
# Purpose:
#   Explore encounter-level co-occurrence of non-informative diagnosis codes
#   ("Encounter Dx" codes) with helpful/specific treatment codes. Validate
#   deduplication logic before production integration in R/56. Non-informative
#   codes are those with sub_category matching "Encounter Dx" pattern (e.g.,
#   "Chemo Encounter Dx Code", "Radiation Encounter Dx Code", "Immunotherapy
#   Encounter Dx Code"). These codes indicate treatment happened but don't name
#   the specific drug/procedure. When a helpful code exists in the same encounter,
#   count only the helpful code. When only dx codes exist (orphan encounters),
#   preserve them with dx_only=TRUE flag.
#
# Inputs:
#   - cache/outputs/treatment_episodes.rds (from R/28, 17 columns including
#     triggering_codes, cancer_category, encounter_ids)
#   - data/reference/all_codes_resolved_next_tables_v2.1.xlsx (sub-category mappings)
#   - DuckDB DIAGNOSIS table (for raw ICD cancer codes per encounter)
#   - R/00_config.R (DRUG_GROUPINGS, TREATMENT_CODES, CODE_SUBCATEGORY_MAP, CANCER_SITE_MAP)
#
# Outputs:
#   - Console diagnostic output: co-occurrence stats, orphan counts, Table 1 impact
#   - output/57_explore_dx_deduplication.log (console output log)
#
# Dependencies:
#   - R/00_config.R (DRUG_GROUPINGS, TREATMENT_CODES, CODE_SUBCATEGORY_MAP, CANCER_SITE_MAP)
#   - R/utils/utils_assertions.R (assert_rds_exists, assert_df_valid, warn_row_count)
#   - R/utils/utils_duckdb.R (open_pcornet_con, get_pcornet_table)
#   - openxlsx2 (xlsx reference file loading)
#
# Requirements:
#   - P82-EXPLORE: Standalone exploration script for encounter-level co-occurrence
#   - P82-COOCCUR: Check for helpful code partners within same encounter_id
#
# Decision Traceability:
#   - D-01: Non-informative = sub_category matching "Encounter Dx" pattern
#   - D-02: DRG, Revenue, procedure, HCPCS, CPT, RxNorm, ICD-10-PCS codes are informative
#   - D-03: Check for helpful partners within same encounter_id (not entire episode)
#   - D-04: Use existing episode_encounters from R/56 Section 4 for encounter granularity
#   - D-05: Orphan dx-only encounters get dx_only=TRUE flag, not excluded
#   - D-06: Preserve data completeness while making dx-only encounters filterable
#   - D-07: Exploration-first approach before production integration
#   - D-09: Diagnostic output: partner counts, orphan counts, before/after Table 1 impact
#   - D-10: Pattern matching (str_detect) rather than hardcoded lists for robustness
#   - D-12: Follow v2.0 code quality standards (styler, lintr, checkmate, documentation)
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

# --- Log console output to file ---
LOG_FILE <- file.path(CONFIG$output_dir, "57_explore_dx_deduplication.log")
.log_con <- file(LOG_FILE, open = "wt")

globalCallingHandlers(
  message = function(m) {
    cat(format(Sys.time(), "[%Y-%m-%d %H:%M:%S] "),
        conditionMessage(m),
        file = .log_con, sep = "")
    flush(.log_con)
  }
)

message("=== Phase 82 Plan 01: Encounter Dx Code Co-Occurrence Analysis ===")
message()
message(glue("  Episodes: {EPISODES_RDS}"))
message(glue("  Reference: {REFERENCE_XLSX}"))
message()


# SECTION 2: LOAD AND VALIDATE INPUT DATA ----

message("--- Loading treatment episodes ---")

assert_rds_exists(EPISODES_RDS, script_name = "R/57")
episodes <- readRDS(EPISODES_RDS)

assert_df_valid(
  episodes,
  name = "treatment_episodes",
  required_cols = c("patient_id", "treatment_type", "triggering_codes", "cancer_category", "encounter_ids"),
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


# SECTION 4: PREPARE ENCOUNTER-LEVEL DATA ----

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

# Split encounter_ids into individual rows (same as R/56 Section 4)
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
# IMPORTANT: Preserve episode_row for propagation to episode_codes
pre_join_rows <- nrow(episodes)

episode_dx <- episodes %>%
  mutate(episode_row = row_number()) %>%
  left_join(episode_cancer, by = "episode_row")
# DO NOT remove episode_row -- needed for encounter-level join in Section 6

warn_row_count(
  episode_dx,
  name = "episode_dx_joined",
  min_expected = pre_join_rows,
  max_expected = pre_join_rows * 1.1,
  script_name = "R/57"
)

message(glue("  Joined cancer codes to episodes: {nrow(episode_dx)} rows (expected {pre_join_rows})"))

n_missing_cancer <- sum(is.na(episode_dx$cancer_codes))
if (n_missing_cancer > 0) {
  message(glue("  NOTE: {n_missing_cancer} episodes without cancer diagnosis codes"))
}


# SECTION 5: BUILD EPISODE_CODES WITH SUB-CATEGORY CLASSIFICATION ----

message()
message("--- Building episode_codes with sub-category classification ---")

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

# Split triggering_codes into individual codes and map to sub-categories
# episode_dx already has episode_row from Section 4 -- propagate to episode_codes
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

# Assign sub-category based on treatment type and code (same 3-tier cascade as R/56)
episode_codes <- episode_codes %>%
  mutate(
    sub_category = case_when(
      # Tier 1: xlsx reference sub-categories (most authoritative)
      treatment_code %in% names(code_to_subcategory) ~ code_to_subcategory[treatment_code],

      # Tier 2: CODE_SUBCATEGORY_MAP supplement
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

message(glue("  Built episode_codes: {nrow(episode_codes)} code instances across {nrow(episode_dx)} episodes"))
message(glue("  Unique treatment codes: {n_distinct(episode_codes$treatment_code)}"))
message(glue("  Unique sub-categories: {n_distinct(episode_codes$sub_category)}"))


# SECTION 6: ENCOUNTER-LEVEL CO-OCCURRENCE ANALYSIS ----

message()
message("--- Performing encounter-level co-occurrence analysis ---")

# Step 1: Join episode_codes to episode_encounters to get encounter-level treatment codes
# episode_encounters has (episode_row, ENCOUNTERID) - one row per encounter per episode
# episode_codes has (episode_row, treatment_code, sub_category, ...) - one row per code per episode
# Join: every code in an episode appears in every encounter of that episode
episode_codes_enc <- episode_codes %>%
  inner_join(
    episode_encounters %>% select(episode_row, ENCOUNTERID),
    by = "episode_row",
    relationship = "many-to-many"
  )

message(glue("  Expanded to encounter level: {nrow(episode_codes_enc)} code instances across {n_distinct(episode_codes_enc$ENCOUNTERID)} encounters"))

# Step 2: Flag non-informative codes (per D-01, D-10: pattern matching, not hardcoded list)
episode_codes_enc <- episode_codes_enc %>%
  mutate(is_non_informative = str_detect(sub_category, "Encounter Dx"))

n_non_informative <- sum(episode_codes_enc$is_non_informative)
n_helpful <- sum(!episode_codes_enc$is_non_informative)

message(glue("  Non-informative (Encounter Dx) instances: {n_non_informative}"))
message(glue("  Helpful (specific treatment) instances: {n_helpful}"))

# Step 3: Per encounter, check if ANY helpful (non-dx) code exists (per D-03)
encounter_has_helpful <- episode_codes_enc %>%
  group_by(ENCOUNTERID) %>%
  summarise(has_helpful = any(!is_non_informative), .groups = "drop")

# Step 4: Join back and flag dx-only rows (per D-05)
episode_codes_enc <- episode_codes_enc %>%
  left_join(encounter_has_helpful, by = "ENCOUNTERID") %>%
  mutate(dx_only = is_non_informative & !has_helpful)

# Calculate co-occurrence stats
n_with_partner <- sum(episode_codes_enc$is_non_informative & episode_codes_enc$has_helpful)
n_orphan <- sum(episode_codes_enc$dx_only)
pct_with_partner <- round(100 * n_with_partner / (n_with_partner + n_orphan), 1)

# Unique encounter counts
n_encounters <- n_distinct(episode_codes_enc$ENCOUNTERID)
encounters_with_dx <- episode_codes_enc %>%
  filter(is_non_informative) %>%
  distinct(ENCOUNTERID) %>%
  nrow()

encounters_dx_only <- episode_codes_enc %>%
  group_by(ENCOUNTERID) %>%
  summarise(all_dx = all(is_non_informative), .groups = "drop") %>%
  filter(all_dx) %>%
  nrow()

encounters_mixed <- encounters_with_dx - encounters_dx_only


# SECTION 7: DIAGNOSTIC OUTPUT (per D-09) ----

message()
message("=== Encounter Dx Code Co-Occurrence Analysis ===")
message()
message(glue("Total treatment code instances (encounter-level): {nrow(episode_codes_enc)}"))
message(glue("Non-informative (Encounter Dx) instances: {n_non_informative}"))
message(glue("Helpful (specific treatment) instances: {n_helpful}"))
message()
message("--- Co-occurrence within same encounter (per D-03) ---")
message(glue("Encounter Dx codes WITH helpful partner (same encounter): {n_with_partner}"))
message(glue("Encounter Dx codes WITHOUT helpful partner (dx_only=TRUE): {n_orphan}"))
message(glue("Partner rate: {pct_with_partner}%"))
message()
message("--- Unique encounter counts ---")
message(glue("Total unique encounters: {n_encounters}"))
message(glue("Encounters with Encounter Dx codes: {encounters_with_dx}"))
message(glue("Encounters with ONLY Encounter Dx codes (dx-only): {encounters_dx_only}"))
message(glue("Encounters with both dx and helpful codes: {encounters_mixed}"))
message()
message("--- Table 1 impact (before vs after deduplication) ---")

# Build Table 1 "before" (original, same as R/56 current logic)
table1_before <- episode_codes %>%
  filter(!is.na(cancer_codes)) %>%
  group_by(category, sub_category, treatment_code, code_type, cancer_codes) %>%
  summarise(encounter_count = n(), .groups = "drop")

message(glue("Table 1 rows before deduplication: {nrow(table1_before)}"))

# Build Table 1 "after" (deduplicated: remove dx codes that have a helpful partner in same encounter)
# Aggregate back to episode level after encounter-level analysis
# A dx code is removable if, for ANY of its encounters, a helpful code co-exists
# Per D-05: keep orphan dx codes (no helpful partner) with dx_only flag
episode_codes_dedup <- episode_codes_enc %>%
  group_by(episode_row, treatment_code, sub_category, category, code_type, cancer_codes) %>%
  summarise(
    has_helpful_in_any_encounter = any(has_helpful & is_non_informative),
    is_non_informative = first(is_non_informative),
    dx_only = all(dx_only),  # dx_only only if ALL encounters for this code are dx-only
    .groups = "drop"
  ) %>%
  filter(!(is_non_informative & has_helpful_in_any_encounter))  # Remove dx codes with partner

table1_after <- episode_codes_dedup %>%
  filter(!is.na(cancer_codes)) %>%
  group_by(category, sub_category, treatment_code, code_type, cancer_codes, dx_only) %>%
  summarise(encounter_count = n(), .groups = "drop")

reduction <- nrow(table1_before) - nrow(table1_after)
pct_reduction <- round(100 * reduction / nrow(table1_before), 1)

message(glue("Table 1 rows after deduplication: {nrow(table1_after)}"))
message(glue("Reduction: {reduction} rows ({pct_reduction}%)"))


# SECTION 8: PER-CATEGORY BREAKDOWN ----

message()
message("--- Per-category deduplication impact ---")

category_order <- c("Chemotherapy", "Immunotherapy", "Radiation", "SCT")

for (cat in category_order) {
  n_before <- sum(table1_before$category == cat)
  n_after <- sum(table1_after$category == cat)
  cat_reduction <- n_before - n_after

  message(glue("  {cat}: {n_before} -> {n_after} rows ({cat_reduction} removed)"))
}


# SECTION 9: ORPHAN ENCOUNTER DETAIL ----

message()
message("--- Top 10 most common orphan (dx_only=TRUE) sub-categories ---")

orphan_summary <- episode_codes_enc %>%
  filter(dx_only) %>%
  count(category, sub_category, sort = TRUE) %>%
  head(10)

for (i in seq_len(nrow(orphan_summary))) {
  message(glue("  {i}. {orphan_summary$category[i]} - {orphan_summary$sub_category[i]}: {orphan_summary$n[i]} instances"))
}


# SECTION 10: CONSOLE SUMMARY ----

message()
message("=== Summary ===")
message(glue("  Non-informative Encounter Dx codes successfully identified via str_detect(sub_category, \"Encounter Dx\")"))
message(glue("  Encounter-level co-occurrence checked within same encounter_id (per D-03)"))
message(glue("  Orphan dx-only encounters preserved with dx_only flag (per D-05)"))
message(glue("  Table 1 deduplication reduces rows by {pct_reduction}%"))
message(glue("  Ready for integration into R/56"))
message()
message("Done.")

close(.log_con)
