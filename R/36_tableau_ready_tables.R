# ==============================================================================
# 36_tableau_ready_tables.R -- Tableau-Ready Data Tables (TABLE-1 and TABLE-2)
# ==============================================================================
#
# Purpose:
#   Generate two Tableau-ready xlsx files for Amy's interactive exploration:
#   TABLE-1: Each treatment encounter mapped to all associated cancer diagnosis
#            codes (comma-separated) with human-readable category names.
#   TABLE-2: Chemotherapy agents collapsed by date per patient, with merged
#            cancer codes per patient-date, for Tableau date-level drug analysis.
#
# Inputs:
#   - cache/outputs/treatment_episode_detail.rds (from R/26, per-encounter grain:
#     patient_id, treatment_type, treatment_date, triggering_code, ENCOUNTERID,
#     drug_name, episode_number)
#   - DuckDB DIAGNOSIS table (for raw ICD cancer codes per encounter)
#   - data/reference/all_codes_resolved_next_tables_v2.1.xlsx (medication name
#     mappings: Chemotherapy sheet column C = medication name)
#   - R/00_config.R (CANCER_SITE_MAP, ICD9_CANCER_SITE_MAP, CODE_SUBCATEGORY_MAP)
#
# Outputs:
#   - output/tableau_table1_encounter_cancer_codes.xlsx (TABLE-1: one row per
#     treatment encounter with comma-separated cancer DX codes)
#   - output/tableau_table2_chemo_drugs_by_class.xlsx (TABLE-2: chemo-only
#     encounters with individual medication names and drug class)
#
# Phase 106 Decisions:
#   D-01: TABLE-1 covers treatment encounters only (from treatment_episode_detail.rds)
#   D-02: Cancer codes use COMMA separator (per meeting notes line 75), NOT semicolons
#   D-03: TABLE-1 columns: PATID, ENCOUNTERID, treatment_date, treatment_type,
#          cancer_codes, cancer_category_names
#   D-04: TABLE-2 medication names via 3-tier cascade: xlsx reference -> CODE_SUBCATEGORY_MAP -> fallback
#   D-05: TABLE-2 includes only Chemotherapy encounters (filter treatment_type == "Chemotherapy")
#   D-06: TABLE-2 columns: PATID, treatment_date, agents, cancer_codes,
#          cancer_category_names (per Phase 111 D-05)
#   D-07: Both tables self-contained with treatment context columns
#   D-08: Separate xlsx files (not combined workbook) for clearer purpose
#   D-09: Raw counts without HIPAA suppression (internal investigation files)
#
# Dependencies:
#   - R/00_config.R (CANCER_SITE_MAP, ICD9_CANCER_SITE_MAP, CODE_SUBCATEGORY_MAP, CONFIG paths)
#   - R/utils/utils_assertions.R (assert_rds_exists, assert_df_valid)
#   - R/utils/utils_duckdb.R (open_pcornet_con, get_pcornet_table)
#   - R/utils/utils_cancer.R (is_cancer_code shared utility)
#   - openxlsx2 (xlsx output)
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
TABLE1_XLSX <- file.path(CONFIG$output_dir, "tableau_table1_encounter_cancer_codes.xlsx")
TABLE2_XLSX <- file.path(CONFIG$output_dir, "tableau_table2_chemo_drugs_by_class.xlsx")

# --- Log console output to file ---
LOG_FILE <- file.path(CONFIG$output_dir, "36_tableau_ready_tables.log")
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

message("=== Phase 106: Tableau-Ready Data Tables (TABLE-1 and TABLE-2) ===")
message()
message(glue("  Detail RDS:      {DETAIL_RDS}"))
message(glue("  Reference XLSX:  {REFERENCE_XLSX}"))
message(glue("  TABLE-1 output:  {TABLE1_XLSX}"))
message(glue("  TABLE-2 output:  {TABLE2_XLSX}"))
message()


# SECTION 2: LOAD AND VALIDATE INPUT DATA ----

message("--- Loading treatment episode detail (encounter-level) ---")

assert_rds_exists(DETAIL_RDS, script_name = "R/36")
detail <- readRDS(DETAIL_RDS)

assert_df_valid(
  detail,
  name = "treatment_episode_detail",
  required_cols = c("patient_id", "treatment_type", "treatment_date",
                    "triggering_code", "ENCOUNTERID", "episode_number"),
  script_name = "R/36"
)

message(glue("  Loaded {nrow(detail)} detail rows (one per date+code+encounter)"))
message(glue("  Treatment types: {paste(unique(detail$treatment_type), collapse = ', ')}"))
message(glue("  Unique patients: {n_distinct(detail$patient_id)}"))
message(glue("  Unique encounters: {n_distinct(detail$ENCOUNTERID[!is.na(detail$ENCOUNTERID)])}"))


# SECTION 3: EXTRACT CANCER CODES PER ENCOUNTER ----

message()
message("--- Extracting cancer codes per encounter ---")

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

message(glue("  Filtered to {nrow(dx_cancer)} cancer diagnosis records ({round(100 * nrow(dx_cancer) / max(nrow(dx_data), 1), 1)}% of total)"))
message(glue("  Unique cancer codes: {n_distinct(dx_cancer$DX)}"))

# Aggregate cancer codes per encounter with COMMA separator (per D-02, meeting notes line 75)
# WHY comma not semicolon: Meeting notes explicitly request "comma-separated" format
# for Tableau's built-in Split function which defaults to comma delimiter.
encounter_dx <- dx_cancer %>%
  group_by(ENCOUNTERID) %>%
  summarise(
    cancer_codes = paste(sort(unique(DX)), collapse = ","),
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
# Helper: split comma-separated codes, map each to category, sort descending, rejoin
# WHY split on comma: TABLE-1 uses comma separator (D-02), unlike R/57's semicolons
map_cancer_codes_to_categories <- function(cancer_codes_str) {
  if (is.na(cancer_codes_str) || cancer_codes_str == "") return(NA_character_)

  codes <- str_split(cancer_codes_str, ",")[[1]]

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

  # Remove NAs, keep unique, sort ascending (Phase 112 D-09: universal A-Z), collapse with commas
  categories <- categories[!is.na(categories)]
  if (length(categories) == 0) return(NA_character_)

  paste(sort(unique(categories)), collapse = ",")
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


# SECTION 4: BUILD TABLE-1 (Encounter Cancer Codes) ----

message()
message("--- Building TABLE-1: Encounter Cancer Codes (D-01, D-02, D-03) ---")

# Filter to rows with valid ENCOUNTERID (treatment encounters only, per D-01)
# One row per unique combination of encounter columns (per D-02)
table1 <- detail_dx %>%
  filter(!is.na(ENCOUNTERID), ENCOUNTERID != "") %>%
  select(patient_id, ENCOUNTERID, treatment_date, treatment_type,
         cancer_codes, cancer_category_names) %>%
  distinct() %>%
  rename(PATID = patient_id) %>%
  arrange(PATID, treatment_date, treatment_type)

message(glue("  TABLE-1 rows: {nrow(table1)}"))
message(glue("  TABLE-1 unique encounters: {n_distinct(table1$ENCOUNTERID)}"))
message(glue("  TABLE-1 unique patients: {n_distinct(table1$PATID)}"))
message(glue("  TABLE-1 treatment types: {paste(unique(table1$treatment_type), collapse = ', ')}"))


# SECTION 5: BUILD TABLE-2 (Chemo Drugs by Class) ----

message()
message("--- Building TABLE-2: Chemo Agents by Date (Phase 111: D-01 through D-07) ---")

# Use MEDICATION_LOOKUP from R/00_config.R (canonical reference Excel mappings)
message(glue("  MEDICATION_LOOKUP entries: {length(MEDICATION_LOOKUP)} codes"))

# Filter detail_dx to Chemotherapy only (per D-05)
chemo_detail <- detail_dx %>%
  filter(treatment_type == "Chemotherapy") %>%
  filter(!is.na(triggering_code), triggering_code != "") %>%
  filter(!is.na(ENCOUNTERID), ENCOUNTERID != "")

message(glue("  Chemo detail rows (with triggering_code): {nrow(chemo_detail)}"))

# Resolve medication names using 3-tier cascade (per D-04):
#   Tier 1: MEDICATION_LOOKUP from R/00_config.R (canonical reference Excel) -- most authoritative
#   Tier 2: CODE_SUBCATEGORY_MAP from R/00_config.R (supplement)
#   Tier 3: Fallback label with raw code
chemo_detail <- chemo_detail %>%
  mutate(medication_name = case_when(
    triggering_code %in% names(MEDICATION_LOOKUP) ~ MEDICATION_LOOKUP[triggering_code],
    triggering_code %in% names(CODE_SUBCATEGORY_MAP) ~ CODE_SUBCATEGORY_MAP[triggering_code],
    TRUE ~ paste0("Chemo code ", triggering_code)
  ))

# Build TABLE-2: one row per patient+date, agents collapsed (Phase 111 D-01 through D-07)
# Drop ENCOUNTERID (D-01: meaningless at date grain), drug_class (D-02: always "Chemotherapy"),
# treatment_type (D-02: always "Chemotherapy")
# Collapse medication_name -> agents: alphabetically sorted, deduplicated, comma-separated (D-06, D-07)
# Merge cancer_codes across encounters sharing same patient+date: split, union, dedup (D-03)
# Merge cancer_category_names across encounters sharing same patient+date (D-04)
table2 <- chemo_detail %>%
  group_by(patient_id, treatment_date) %>%
  summarise(
    agents = paste(sort(unique(na.omit(medication_name))), collapse = ","),
    cancer_codes = {
      all_codes <- unique(na.omit(unlist(strsplit(cancer_codes, ","))))
      if (length(all_codes) == 0) NA_character_ else paste(sort(all_codes), collapse = ",")
    },
    cancer_category_names = {
      all_cats <- unique(na.omit(unlist(strsplit(cancer_category_names, ","))))
      if (length(all_cats) == 0) NA_character_ else paste(sort(all_cats), collapse = ",")
    },
    .groups = "drop"
  ) %>%
  rename(PATID = patient_id) %>%
  arrange(PATID, treatment_date)

message(glue("  TABLE-2 rows (patient-date grain): {nrow(table2)}"))
message(glue("  TABLE-2 unique patients: {n_distinct(table2$PATID)}"))
message(glue("  TABLE-2 date range: {min(table2$treatment_date)} to {max(table2$treatment_date)}"))
n_unique_agents <- n_distinct(unlist(strsplit(table2$agents, ",")))
message(glue("  TABLE-2 unique agents across all rows: {n_unique_agents}"))

# Show agent combination frequency
combo_freq <- table2 %>%
  count(agents, sort = TRUE) %>%
  head(10)
message("  Top 10 agent combinations:")
for (i in seq_len(nrow(combo_freq))) {
  message(glue("    {combo_freq$agents[i]}: {combo_freq$n[i]} patient-dates"))
}


# SECTION 6: WRITE XLSX OUTPUT ----

message()
message("--- Writing TABLE-1 and TABLE-2 xlsx output ---")

# Write TABLE-1 as separate xlsx (per D-08)
wb1 <- wb_workbook()
wb1$add_worksheet("Encounter Cancer Codes")
wb1$add_data("Encounter Cancer Codes", table1, start_row = 1, col_names = TRUE)
wb1$save(TABLE1_XLSX)
message(glue("  Saved TABLE-1: {TABLE1_XLSX}"))
message(glue("    File size: {file.info(TABLE1_XLSX)$size} bytes"))

# Write TABLE-2 as separate xlsx (per D-08)
wb2 <- wb_workbook()
wb2$add_worksheet("Chemo Agents by Date")
wb2$add_data("Chemo Agents by Date", table2, start_row = 1, col_names = TRUE)
wb2$save(TABLE2_XLSX)
message(glue("  Saved TABLE-2: {TABLE2_XLSX}"))
message(glue("    File size: {file.info(TABLE2_XLSX)$size} bytes"))


# SECTION 7: SUMMARY AND CLEANUP ----

message()
message("=== Phase 106 Summary ===")
message(glue("  TABLE-1 (Encounter Cancer Codes):"))
message(glue("    Rows:             {nrow(table1)}"))
message(glue("    Unique encounters: {n_distinct(table1$ENCOUNTERID)}"))
message(glue("    Unique patients:   {n_distinct(table1$PATID)}"))
message(glue("    Treatment types:   {paste(unique(table1$treatment_type), collapse = ', ')}"))
message()
message(glue("  TABLE-2 (Chemo Agents by Date, Phase 111):"))
message(glue("    Rows (patient-date grain): {nrow(table2)}"))
message(glue("    Unique patients:           {n_distinct(table2$PATID)}"))
message(glue("    Unique agents:             {n_distinct(unlist(strsplit(table2$agents, ',')))}"))

message()

# Sanity check: TABLE-2 patients should be a subset of TABLE-1 patients
# (all chemo patients should have treatment encounters in TABLE-1)
t2_patients <- unique(table2$PATID)
t1_patients <- unique(table1$PATID)
t2_not_in_t1 <- setdiff(t2_patients, t1_patients)
if (length(t2_not_in_t1) > 0) {
  warning(glue("[R/36 WARNING] {length(t2_not_in_t1)} TABLE-2 patients not found in TABLE-1 -- data consistency issue"))
} else {
  message(glue("  Sanity check PASSED: all {length(t2_patients)} TABLE-2 patients found in TABLE-1 ({length(t1_patients)} total patients)"))
}

message()
message(glue("  Output files:"))
message(glue("    {TABLE1_XLSX}"))
message(glue("    {TABLE2_XLSX}"))
message()
message("Done.")

try(close(.log_con), silent = TRUE)
