# =============================================================================
# Phase 01: Gantt Chart Data Export
# =============================================================================
# Combines treatment episode and episode detail RDS artifacts into two CSV files
# for third-party Gantt chart visualization.
#
# Decision traceability:
#   D-01: Two-table output (bars + ticks) with exact column specs
#   D-02: Detail table preserves one-row-per-code granularity
#   D-03: Separate rows by treatment type (concurrent as separate rows)
#   D-04: Full cohort (no filtering)
#   D-05: No payer tier data
#   D-06: CSV output only
#   D-07: Load from existing RDS artifacts
#   D-03 (Phase 02): triggering_code_description column in detail CSV
#   D-04 (Phase 02): triggering_code_descriptions column in episodes CSV (comma-separated, same order)
#   D-05 (Phase 02): Empty string for missing descriptions
#   D-06 (Phase 02): Description columns in CSVs only
#   D-01 (Phase 57): Cancer categories from cancer_summary.csv via PREFIX_MAP classification
#   D-02 (Phase 57): Comma-separated cancer_category column (matches triggering_codes pattern)
#   D-03 (Phase 57): is_hodgkin = TRUE when "Hodgkin Lymphoma" in cancer_category
#   D-04 (Phase 57): Death dates from DEATH table (DEATH_Mailhot_V1.csv)
#   D-05 (Phase 57): Full pipeline integration for DEATH (config + load spec + DuckDB)
#   D-06 (Phase 57): Death rows: treatment_type="Death", single-point, episode_length_days=0
#   D-07 (Phase 57): Death rows in BOTH gantt_episodes.csv and gantt_detail.csv
#   D-08 (Phase 57): 1900 sentinel date nullification on DEATH_DATE
#   D-01 (Phase 59): Impossible death dates excluded (death before earliest treatment)
#   D-02 (Phase 59): Impossible deaths REMOVED from Gantt CSVs (patient keeps treatment rows)
#   D-07 (Phase 59): HL Diagnosis treatment row in both CSVs (treatment_type="HL Diagnosis")
#   D-08 (Phase 59): HL Diagnosis rows for ALL patients with HL dx, not only confirmed 7-day cohort
#   D-09 (Phase 59): HL Diagnosis in treatment category for Gantt (date = min(DIAGNOSIS, TUMOR_REGISTRY))
#
# Inputs:
#   - cache/outputs/treatment_episodes.rds (episode-level)
#   - cache/outputs/treatment_episode_detail.rds (detail-level)
#   - cache/outputs/code_descriptions.rds (Phase 02: code -> description lookup)
#   - output/tables/cancer_summary.csv (Phase 55/57: cancer code -> category mapping)
#   - cache/outputs/confirmed_hl_cohort.rds (Phase 59: HL diagnosis dates for treatment rows)
#   - cache/outputs/validated_death_dates.rds (Phase 59: pre-validated death dates, impossible deaths excluded)
#
# Outputs:
#   - output/gantt_episodes.csv (bars: one row per patient/type/episode)
#   - output/gantt_detail.csv (ticks: one row per patient/date/code)
# =============================================================================


# --- SECTION 1: SETUP AND CONFIGURATION ---

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(lubridate)
})

source("R/00_config.R")
source("R/utils_duckdb.R")
source("R/utils_dates.R")

# Input paths: existing RDS artifacts from R/44a_treatment_episodes.R
EPISODES_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
DETAIL_RDS   <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds")

# Output paths: CSV files for third-party Gantt chart consumption
OUTPUT_EPISODES <- file.path(CONFIG$output_dir, "gantt_episodes.csv")
OUTPUT_DETAIL   <- file.path(CONFIG$output_dir, "gantt_detail.csv")

# Code description lookup (built by R/48b_build_code_descriptions.R)
DESCRIPTIONS_RDS <- file.path(CONFIG$cache$outputs_dir, "code_descriptions.rds")

# Cancer summary source (R/55 output, patient-code level with cancer_code column)
CANCER_SUMMARY_CSV <- file.path(CONFIG$output_dir, "tables", "cancer_summary.csv")

# Validated death dates (built by R/59_death_date_validation.R, Phase 59)
VALIDATED_DEATHS_RDS <- file.path(CONFIG$cache$outputs_dir, "validated_death_dates.rds")

# Confirmed HL cohort (built by R/55_cancer_summary_refined.R, Phase 55)
COHORT_RDS <- file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds")


# --- SECTION 2: LOAD INPUT DATA ---

message("=== Phase 01: Gantt Chart Data Export ===\n")

# Verify RDS artifacts exist before attempting to load
if (!file.exists(EPISODES_RDS)) {
  stop(glue("ERROR: {EPISODES_RDS} not found. Run R/44a_treatment_episodes.R first."))
}
if (!file.exists(DETAIL_RDS)) {
  stop(glue("ERROR: {DETAIL_RDS} not found. Run R/44a_treatment_episodes.R first."))
}

# Load episode-level data (bars: one row per patient/type/episode)
episodes <- readRDS(EPISODES_RDS)
message(glue("  Loaded {format(nrow(episodes), big.mark = ',')} episode rows"))

# Load detail-level data (ticks: one row per patient/date/code)
detail <- readRDS(DETAIL_RDS)
message(glue("  Loaded {format(nrow(detail), big.mark = ',')} detail rows"))


# --- SECTION 2B: LOAD AND AGGREGATE CANCER CATEGORIES (per D-01, D-02, D-03) ---

message("\n--- Loading cancer categories ---")

# Cancer summary CSV has columns: ID, cancer_code, description, ...
# It does NOT have a "category" column -- we must derive it via PREFIX_MAP
if (!file.exists(CANCER_SUMMARY_CSV)) {
  stop(glue("ERROR: {CANCER_SUMMARY_CSV} not found. Run R/55_cancer_summary_refined.R first."))
}

cancer_summary <- read.csv(CANCER_SUMMARY_CSV, stringsAsFactors = FALSE)
message(glue("  Loaded {format(nrow(cancer_summary), big.mark = ',')} cancer summary rows"))

# PREFIX_MAP: maps 3-character ICD-10-CM prefixes to cancer site categories
# Copied from R/55_cancer_summary_refined.R for script independence (project pattern)
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

# classify_codes: derive category from cancer_code using PREFIX_MAP
classify_codes <- function(codes) {
  prefixes <- substr(toupper(codes), 1, 3)
  categories <- PREFIX_MAP[prefixes]
  unname(categories)
}

# Derive category for each cancer code
cancer_summary$category <- classify_codes(cancer_summary$cancer_code)
cancer_summary$category[is.na(cancer_summary$category)] <- "Unclassified"

# Aggregate to patient level: comma-separated sorted list of distinct categories (per D-02)
# Alphabetical sort for reproducibility (Claude's discretion, see RESEARCH.md Pitfall 1)
cancer_categories_per_patient <- cancer_summary %>%
  group_by(ID) %>%
  summarise(
    cancer_category = paste(sort(unique(category)), collapse = ","),
    .groups = "drop"
  ) %>%
  mutate(
    is_hodgkin = str_detect(cancer_category, "Hodgkin Lymphoma")  # per D-03
  )

message(glue("  Cancer categories aggregated for {format(nrow(cancer_categories_per_patient), big.mark = ',')} patients"))
message(glue("  Hodgkin Lymphoma patients: {sum(cancer_categories_per_patient$is_hodgkin)}"))


# --- SECTION 2C: LOAD VALIDATED DEATH DATA (Phase 59: D-01, D-02) ---

message("\n--- Loading validated death dates (Phase 59) ---")

if (!file.exists(VALIDATED_DEATHS_RDS)) {
  warning("validated_death_dates.rds not found. Run R/59_death_date_validation.R first. Falling back to raw DEATH table.")
  # Fallback: original DuckDB loading pattern (backward compatibility)
  USE_DUCKDB <- TRUE
  open_pcornet_con()
  death_raw <- get_pcornet_table("DEATH")
  if (is.null(death_raw)) {
    warning("DEATH table not found in DuckDB. Death rows will be skipped.")
    death_data <- tibble(ID = character(), DEATH_DATE = as.Date(character()))
  } else {
    death_data <- death_raw %>%
      collect() %>%
      mutate(
        DEATH_DATE = parse_pcornet_date(DEATH_DATE),
        DEATH_DATE = if_else(year(DEATH_DATE) == 1900L, as.Date(NA), DEATH_DATE)
      ) %>%
      filter(!is.na(DEATH_DATE)) %>%
      select(ID, DEATH_DATE) %>%
      group_by(ID) %>%
      summarise(DEATH_DATE = min(DEATH_DATE), .groups = "drop")
  }
  close_pcornet_con()
} else {
  validated_deaths <- readRDS(VALIDATED_DEATHS_RDS)
  # Keep all patients but only use non-NA death dates (impossible deaths have DEATH_DATE = NA)
  death_data <- validated_deaths %>%
    filter(!is.na(DEATH_DATE)) %>%
    select(ID, DEATH_DATE)

  n_excluded <- sum(validated_deaths$death_valid == FALSE, na.rm = TRUE)
  message(glue("  Loaded validated death dates: {nrow(death_data)} valid, {n_excluded} impossible excluded (per D-02)"))
}

message(glue("  Patients with valid death dates for Gantt: {nrow(death_data)}"))


# --- SECTION 2D: LOAD HL COHORT FOR DIAGNOSIS ROWS (Phase 59: D-07, D-08) ---

message("\n--- Loading HL cohort for diagnosis treatment rows ---")

if (!file.exists(COHORT_RDS)) {
  warning("confirmed_hl_cohort.rds not found. Run R/55_cancer_summary_refined.R first. HL Diagnosis rows will be skipped.")
  hl_cohort <- tibble(
    ID = character(),
    first_hl_dx_date = as.Date(character()),
    first_hl_dx_source = character()
  )
} else {
  hl_cohort <- readRDS(COHORT_RDS)
  # Apply 1900 sentinel filtering to HL diagnosis dates (same pattern as death dates)
  hl_cohort <- hl_cohort %>%
    mutate(first_hl_dx_date = if_else(year(first_hl_dx_date) == 1900L, as.Date(NA), first_hl_dx_date)) %>%
    filter(!is.na(first_hl_dx_date))
  message(glue("  Loaded {nrow(hl_cohort)} HL patients with valid first diagnosis dates"))
}


# --- SECTION 3: VALIDATE COLUMN STRUCTURE ---

# Expected columns per D-01 (episode-level bars table)
expected_episode_cols <- c(
  "patient_id", "treatment_type", "episode_number",
  "episode_start", "episode_stop", "episode_length_days",
  "distinct_dates_in_episode", "historical_flag", "triggering_codes"
)

# Expected columns per D-01 (detail-level ticks table)
expected_detail_cols <- c(
  "patient_id", "treatment_type", "treatment_date", "triggering_code",
  "episode_number", "episode_start", "episode_stop", "historical_flag"
)

# Check for missing columns in episode data
missing_episode_cols <- setdiff(expected_episode_cols, colnames(episodes))
if (length(missing_episode_cols) > 0) {
  stop(glue("ERROR: Episodes RDS missing expected columns: {paste(missing_episode_cols, collapse = ', ')}"))
}

# Check for missing columns in detail data
missing_detail_cols <- setdiff(expected_detail_cols, colnames(detail))
if (length(missing_detail_cols) > 0) {
  stop(glue("ERROR: Detail RDS missing expected columns: {paste(missing_detail_cols, collapse = ', ')}"))
}

message("  Column validation passed")


# --- SECTION 3B: LOAD CODE DESCRIPTIONS (Phase 02) ---

if (!file.exists(DESCRIPTIONS_RDS)) {
  stop(glue("ERROR: {DESCRIPTIONS_RDS} not found. Run R/48b_build_code_descriptions.R first."))
}

code_descriptions <- readRDS(DESCRIPTIONS_RDS)
message(glue("  Loaded {format(length(code_descriptions), big.mark = ',')} code descriptions"))


# Helper: map a single code to its description (empty string if missing, per D-05)
lookup_description <- function(code) {
  if (is.na(code) || code == "") return("")
  if (code %in% names(code_descriptions)) return(code_descriptions[[code]])
  return("")
}

# Helper: map comma-separated codes to comma-separated descriptions (per D-04)
# Preserves input order — does NOT sort. Per RESEARCH.md Pitfall 1.
map_codes_to_descriptions <- function(codes_str) {
  if (is.na(codes_str) || codes_str == "") return("")
  codes <- str_split(codes_str, ",")[[1]]
  descriptions <- sapply(codes, lookup_description, USE.NAMES = FALSE)
  paste(descriptions, collapse = ",")
}


# --- SECTION 4: SELECT AND ORDER COLUMNS (per D-01) ---

# Episode-level bars table: 9 original columns + triggering_code_descriptions + cancer_category + is_hodgkin
episodes_export <- episodes %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, historical_flag, triggering_codes
  ) %>%
  mutate(
    triggering_code_descriptions = sapply(triggering_codes, map_codes_to_descriptions, USE.NAMES = FALSE)
  ) %>%
  left_join(cancer_categories_per_patient, by = c("patient_id" = "ID")) %>%
  mutate(
    cancer_category = ifelse(is.na(cancer_category), "", cancer_category),
    is_hodgkin = ifelse(is.na(is_hodgkin), FALSE, is_hodgkin)
  )

# Detail-level ticks table: 8 original columns + triggering_code_description + cancer_category + is_hodgkin
detail_export <- detail %>%
  select(
    patient_id, treatment_type, treatment_date, triggering_code,
    episode_number, episode_start, episode_stop, historical_flag
  ) %>%
  mutate(
    triggering_code_description = sapply(triggering_code, lookup_description, USE.NAMES = FALSE)
  ) %>%
  left_join(cancer_categories_per_patient, by = c("patient_id" = "ID")) %>%
  mutate(
    cancer_category = ifelse(is.na(cancer_category), "", cancer_category),
    is_hodgkin = ifelse(is.na(is_hodgkin), FALSE, is_hodgkin)
  )


# --- SECTION 4B: BUILD AND APPEND DEATH PSEUDO-TREATMENT ROWS (per D-06, D-07) ---

if (nrow(death_data) > 0) {
  message("\n--- Building death pseudo-treatment rows ---")

  # Join cancer categories to death data (Claude's discretion: Death rows get patient's categories)
  death_with_categories <- death_data %>%
    left_join(cancer_categories_per_patient, by = "ID") %>%
    mutate(
      cancer_category = ifelse(is.na(cancer_category), "", cancer_category),
      is_hodgkin = ifelse(is.na(is_hodgkin), FALSE, is_hodgkin)
    )

  # Build death rows for episodes table (per D-06)
  death_episodes <- death_with_categories %>%
    mutate(
      patient_id = ID,
      treatment_type = "Death",
      episode_number = 1L,
      episode_start = DEATH_DATE,
      episode_stop = DEATH_DATE,
      episode_length_days = 0L,
      distinct_dates_in_episode = 1L,
      historical_flag = FALSE,
      triggering_codes = "",
      triggering_code_descriptions = ""
    ) %>%
    select(
      patient_id, treatment_type, episode_number,
      episode_start, episode_stop, episode_length_days,
      distinct_dates_in_episode, historical_flag,
      triggering_codes, triggering_code_descriptions,
      cancer_category, is_hodgkin
    )

  # Build death rows for detail table (per D-06, D-07)
  death_detail <- death_with_categories %>%
    mutate(
      patient_id = ID,
      treatment_type = "Death",
      treatment_date = DEATH_DATE,
      triggering_code = "",
      episode_number = 1L,
      episode_start = DEATH_DATE,
      episode_stop = DEATH_DATE,
      historical_flag = FALSE,
      triggering_code_description = ""
    ) %>%
    select(
      patient_id, treatment_type, treatment_date,
      triggering_code, episode_number, episode_start,
      episode_stop, historical_flag,
      triggering_code_description,
      cancer_category, is_hodgkin
    )

  # Verify column alignment before binding (per RESEARCH.md Pitfall 4)
  expected_ep_cols <- colnames(episodes_export)
  death_ep_cols <- colnames(death_episodes)
  missing_in_death_ep <- setdiff(expected_ep_cols, death_ep_cols)
  extra_in_death_ep <- setdiff(death_ep_cols, expected_ep_cols)

  if (length(missing_in_death_ep) > 0) {
    stop(glue("Death episodes missing columns: {paste(missing_in_death_ep, collapse = ', ')}"))
  }
  if (length(extra_in_death_ep) > 0) {
    warning(glue("Death episodes has extra columns: {paste(extra_in_death_ep, collapse = ', ')}"))
  }

  expected_det_cols <- colnames(detail_export)
  death_det_cols <- colnames(death_detail)
  missing_in_death_det <- setdiff(expected_det_cols, death_det_cols)
  extra_in_death_det <- setdiff(death_det_cols, expected_det_cols)

  if (length(missing_in_death_det) > 0) {
    stop(glue("Death detail missing columns: {paste(missing_in_death_det, collapse = ', ')}"))
  }
  if (length(extra_in_death_det) > 0) {
    warning(glue("Death detail has extra columns: {paste(extra_in_death_det, collapse = ', ')}"))
  }

  # Append death rows (per D-07: both CSVs)
  episodes_export <- bind_rows(episodes_export, death_episodes) %>%
    arrange(patient_id, episode_start, treatment_type)

  detail_export <- bind_rows(detail_export, death_detail) %>%
    arrange(patient_id, treatment_date, treatment_type)

  message(glue("  Added {nrow(death_episodes)} death episode rows"))
  message(glue("  Added {nrow(death_detail)} death detail rows"))

} else {
  message("\n--- No valid death dates found; skipping death rows ---")
}


# --- SECTION 4C: BUILD AND APPEND HL DIAGNOSIS TREATMENT ROWS (Phase 59: D-07, D-08, D-09) ---

if (nrow(hl_cohort) > 0) {
  message("\n--- Building HL Diagnosis treatment rows ---")

  # HL Diagnosis rows for episodes table (per D-07, D-09: treatment category, date = min(DIAGNOSIS, TUMOR_REGISTRY))
  hl_dx_episodes <- hl_cohort %>%
    left_join(cancer_categories_per_patient, by = "ID") %>%
    mutate(
      cancer_category = ifelse(is.na(cancer_category), "Hodgkin Lymphoma", cancer_category),
      is_hodgkin = TRUE
    ) %>%
    mutate(
      patient_id = ID,
      treatment_type = "HL Diagnosis",
      episode_number = 1L,
      episode_start = first_hl_dx_date,
      episode_stop = first_hl_dx_date,
      episode_length_days = 0L,
      distinct_dates_in_episode = 1L,
      historical_flag = FALSE,
      triggering_codes = "",
      triggering_code_descriptions = ""
    ) %>%
    select(
      patient_id, treatment_type, episode_number,
      episode_start, episode_stop, episode_length_days,
      distinct_dates_in_episode, historical_flag,
      triggering_codes, triggering_code_descriptions,
      cancer_category, is_hodgkin
    )

  # HL Diagnosis rows for detail table (per D-07, D-09: treatment category)
  hl_dx_detail <- hl_cohort %>%
    left_join(cancer_categories_per_patient, by = "ID") %>%
    mutate(
      cancer_category = ifelse(is.na(cancer_category), "Hodgkin Lymphoma", cancer_category),
      is_hodgkin = TRUE
    ) %>%
    mutate(
      patient_id = ID,
      treatment_type = "HL Diagnosis",
      treatment_date = first_hl_dx_date,
      triggering_code = "",
      episode_number = 1L,
      episode_start = first_hl_dx_date,
      episode_stop = first_hl_dx_date,
      historical_flag = FALSE,
      triggering_code_description = ""
    ) %>%
    select(
      patient_id, treatment_type, treatment_date,
      triggering_code, episode_number, episode_start,
      episode_stop, historical_flag,
      triggering_code_description,
      cancer_category, is_hodgkin
    )

  # Verify column alignment before binding (same pattern as Death row validation)
  expected_ep_cols <- colnames(episodes_export)
  hl_dx_ep_cols <- colnames(hl_dx_episodes)
  missing_in_hl_dx_ep <- setdiff(expected_ep_cols, hl_dx_ep_cols)
  extra_in_hl_dx_ep <- setdiff(hl_dx_ep_cols, expected_ep_cols)

  if (length(missing_in_hl_dx_ep) > 0) {
    stop(glue("HL Diagnosis episodes missing columns: {paste(missing_in_hl_dx_ep, collapse = ', ')}"))
  }
  if (length(extra_in_hl_dx_ep) > 0) {
    warning(glue("HL Diagnosis episodes has extra columns: {paste(extra_in_hl_dx_ep, collapse = ', ')}"))
  }

  expected_det_cols <- colnames(detail_export)
  hl_dx_det_cols <- colnames(hl_dx_detail)
  missing_in_hl_dx_det <- setdiff(expected_det_cols, hl_dx_det_cols)
  extra_in_hl_dx_det <- setdiff(hl_dx_det_cols, expected_det_cols)

  if (length(missing_in_hl_dx_det) > 0) {
    stop(glue("HL Diagnosis detail missing columns: {paste(missing_in_hl_dx_det, collapse = ', ')}"))
  }
  if (length(extra_in_hl_dx_det) > 0) {
    warning(glue("HL Diagnosis detail has extra columns: {paste(extra_in_hl_dx_det, collapse = ', ')}"))
  }

  # Append HL Diagnosis treatment rows (per D-09: chronological order with other treatments)
  episodes_export <- bind_rows(episodes_export, hl_dx_episodes) %>%
    arrange(patient_id, episode_start, treatment_type)

  detail_export <- bind_rows(detail_export, hl_dx_detail) %>%
    arrange(patient_id, treatment_date, treatment_type)

  message(glue("  Added {nrow(hl_dx_episodes)} HL Diagnosis episode rows"))
  message(glue("  Added {nrow(hl_dx_detail)} HL Diagnosis detail rows"))

} else {
  message("\n--- No valid HL diagnosis dates found; skipping HL Diagnosis treatment rows ---")
}


# --- SECTION 5: WRITE CSV OUTPUTS ---

message("\n--- Writing CSV outputs ---")

write.csv(episodes_export, OUTPUT_EPISODES, row.names = FALSE)
message(glue("  Wrote {OUTPUT_EPISODES} ({format(nrow(episodes_export), big.mark = ',')} rows)"))

write.csv(detail_export, OUTPUT_DETAIL, row.names = FALSE)
message(glue("  Wrote {OUTPUT_DETAIL} ({format(nrow(detail_export), big.mark = ',')} rows)"))


# --- SECTION 6: FINAL SUMMARY ---

message("\n=== Phase 01 Complete ===")
message(glue("  Unique patients in episodes: {format(n_distinct(episodes_export$patient_id), big.mark = ',')}"))
message(glue("  Total episodes: {format(nrow(episodes_export), big.mark = ',')}"))
message(glue("  Total detail rows: {format(nrow(detail_export), big.mark = ',')}"))

# Phase 02 description coverage stats
detail_has_desc <- sum(detail_export$triggering_code_description != "", na.rm = TRUE)
detail_total <- sum(!is.na(detail_export$triggering_code) & detail_export$triggering_code != "", na.rm = TRUE)
message(glue("  Detail rows with descriptions: {format(detail_has_desc, big.mark = ',')} / {format(detail_total, big.mark = ',')} codes"))

# Phase 57 cancer category and death stats
message(glue("  Episodes with cancer_category: {sum(episodes_export$cancer_category != '', na.rm = TRUE)}"))
message(glue("  Episodes with is_hodgkin=TRUE: {sum(episodes_export$is_hodgkin, na.rm = TRUE)}"))
n_death_rows <- sum(episodes_export$treatment_type == "Death", na.rm = TRUE)
message(glue("  Death pseudo-treatment rows in episodes: {format(n_death_rows, big.mark = ',')}"))
n_hl_dx_rows <- sum(episodes_export$treatment_type == "HL Diagnosis", na.rm = TRUE)
message(glue("  HL Diagnosis treatment rows in episodes: {format(n_hl_dx_rows, big.mark = ',')}"))

message(glue("\n  Episode bars:  {OUTPUT_EPISODES}"))
message(glue("  Detail ticks:  {OUTPUT_DETAIL}"))
