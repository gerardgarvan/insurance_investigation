# ==============================================================================
# 58_co_administration_analysis.R -- Single-Agent Co-Administration Analysis
# ==============================================================================
#
# Purpose:
#   Identify single-agent chemotherapy encounters and find all co-administered
#   chemotherapies within a +/-30-day window. Detects fragmented regimen patterns
#   where multi-drug regimens (ABVD, BV+AVD) appear as separate single-agent
#   billing events instead of being billed together. Directly answers team
#   questions about single-agent chemo patterns.
#
# Inputs:
#   - cache/outputs/treatment_episode_detail.rds (encounter-level grain:
#     patient_id, treatment_type, treatment_date, triggering_code, ENCOUNTERID,
#     drug_name, episode_number, episode_start, episode_stop, historical_flag)
#   - cache/outputs/treatment_episodes.rds (episode-level with regimen_label
#     from R/28; used to exclude regimen-classified encounters per D-05)
#   - data/reference/all_codes_resolved_next_tables_v2.1.xlsx (sub-category
#     mappings: Chemotherapy column C = medication name)
#
# Outputs:
#   - output/co_administration_analysis.xlsx (2-sheet workbook:
#     Sheet 1 = "Co-Administration Detail" (COADMIN-01),
#     Sheet 2 = "Pattern Summary" (COADMIN-02))
#
# Phase 102 Decisions (Single-Agent Co-Administration Analysis):
#   D-01: "Single-agent" = one chemo triggering_code per patient-date
#   D-02: Include encounters with drug_name = NA (use triggering_code)
#   D-03: +/-30-day window; exclude self-matches (ENCOUNTERID != i.ENCOUNTERID)
#   D-04: Chemo-to-chemo only (filter treatment_type == "Chemotherapy")
#   D-05: Exclude regimen-classified encounters (anti_join on regimen_label)
#   D-06: Two-sheet xlsx: "Co-Administration Detail" + "Pattern Summary"
#   D-07: Detail table: one row per (index encounter, co-admin drug) pair
#   D-08: Show both human-readable drug name AND triggering_code
#   D-09: Script R/58 in drug grouping decade, reads treatment_episode_detail.rds
#   D-10: Investigation script -- no saveRDS, no upstream modification
#
# Dependencies:
#   - R/00_config.R (CONFIG paths, CODE_SUBCATEGORY_MAP, TREATMENT_CODES,
#     DRUG_GROUPINGS)
#   - R/utils/utils_assertions.R (assert_rds_exists, assert_df_valid)
#   - openxlsx2 (multi-sheet xlsx output)
#   - data.table (temporal self-join with cartesian product)
#   - dplyr, glue, stringr
#
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP AND CONFIGURATION ----
# ==============================================================================

# Clear stale log handler from previous source() in same session
try(close(.log_con), silent = TRUE)
tryCatch(globalCallingHandlers(NULL), error = function(e) NULL)

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(openxlsx2)
  library(data.table)
  library(checkmate)
})

source("R/00_config.R")
source("R/utils/utils_assertions.R")

# --- Define file paths ---
DETAIL_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds")
EPISODES_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
REFERENCE_XLSX <- "data/reference/all_codes_resolved_next_tables_v2.1.xlsx"
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "co_administration_analysis.xlsx")

# --- Log console output to file ---
LOG_FILE <- file.path(CONFIG$output_dir, "58_co_administration_analysis.log")
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

message("=== Phase 102: Single-Agent Co-Administration Analysis ===")
message()
message(glue("  Detail RDS: {DETAIL_RDS}"))
message(glue("  Episodes RDS: {EPISODES_RDS}"))
message(glue("  Reference: {REFERENCE_XLSX}"))
message(glue("  Output: {OUTPUT_XLSX}"))
message()


# ==============================================================================
# SECTION 2: LOAD AND FILTER DATA ----
# ==============================================================================

message("--- Loading and filtering data ---")

# Validate inputs exist
assert_rds_exists(DETAIL_RDS, script_name = "R/58")
assert_rds_exists(EPISODES_RDS, script_name = "R/58")

# Load treatment_episode_detail.rds (encounter-level grain)
detail <- readRDS(DETAIL_RDS)
assert_df_valid(
  detail,
  name = "treatment_episode_detail",
  required_cols = c("patient_id", "treatment_type", "treatment_date",
                    "triggering_code", "ENCOUNTERID", "episode_number",
                    "drug_name"),
  script_name = "R/58"
)
message(glue("  Total detail rows loaded: {nrow(detail)}"))

# Load treatment_episodes.rds (episode-level with regimen_label)
episodes <- readRDS(EPISODES_RDS)
message(glue("  Total episode rows loaded: {nrow(episodes)}"))

# D-04: Filter to Chemotherapy treatment_type only
chemo_detail <- detail %>%
  filter(treatment_type == "Chemotherapy")
message(glue("  Chemotherapy-only rows: {nrow(chemo_detail)}"))

# D-05: Exclude encounters already classified as part of a multi-agent regimen
# (regimen_label = ABVD, BV+AVD, or Nivo+AVD from R/28)
regimen_encounters <- episodes %>%
  filter(!is.na(regimen_label)) %>%
  select(patient_id, episode_number)

n_before_regimen_excl <- nrow(chemo_detail)
chemo_detail <- chemo_detail %>%
  anti_join(regimen_encounters, by = c("patient_id", "episode_number"))
n_after_regimen_excl <- nrow(chemo_detail)

message(glue("  Regimen-classified encounters excluded: {n_before_regimen_excl - n_after_regimen_excl}"))
message(glue("  Chemotherapy encounters after regimen exclusion: {n_after_regimen_excl}"))
message(glue("  Unique patients in filtered chemo detail: {n_distinct(chemo_detail$patient_id)}"))


# ==============================================================================
# SECTION 3: BUILD SUB-CATEGORY MAPPINGS ----
# ==============================================================================

message()
message("--- Building sub-category mappings from reference xlsx ---")

assert_file_exists(REFERENCE_XLSX, .var.name = "[R/58 ERROR] Reference XLSX")
ref_wb <- wb_load(REFERENCE_XLSX)

# Chemo: code -> medication name (column C, "Medication")
# Reuse R/57 Section 3 pattern
chemo_sheet <- wb_to_df(ref_wb, sheet = "Chemotherapy", start_row = 2)
chemo_map <- setNames(as.character(chemo_sheet[[3]]), as.character(chemo_sheet[[1]]))
chemo_map <- chemo_map[!is.na(names(chemo_map)) & !is.na(chemo_map)]
message(glue("  Chemo sub-categories: {length(unique(chemo_map))} medications from {length(chemo_map)} codes"))

# D-08: Multi-tier drug name resolution
# Tier 1: xlsx reference (chemo_map)
# Tier 2: CODE_SUBCATEGORY_MAP from R/00_config.R
# Tier 3: drug_name from RDS if available
# Tier 4: triggering_code as fallback
resolve_drug_name <- function(code, drug_name_col) {
  # Tier 1: xlsx reference
  if (code %in% names(chemo_map)) return(chemo_map[[code]])
  # Tier 2: CODE_SUBCATEGORY_MAP
  if (code %in% names(CODE_SUBCATEGORY_MAP)) return(CODE_SUBCATEGORY_MAP[[code]])
  # Tier 3: drug_name from RDS if available
  if (!is.na(drug_name_col) && drug_name_col != "") return(drug_name_col)
  # Tier 4: code itself as fallback
  return(code)
}


# ==============================================================================
# SECTION 4: IDENTIFY SINGLE-AGENT ENCOUNTERS (D-01, D-02) ----
# ==============================================================================

message()
message("--- Identifying single-agent encounters ---")

# D-01: Group by (patient_id, treatment_date) to count distinct chemo codes
# per patient-date. Single-agent = exactly 1 unique triggering_code on that date.
single_agent_base <- chemo_detail %>%
  group_by(patient_id, treatment_date) %>%
  mutate(n_chemo_codes_on_date = n_distinct(triggering_code)) %>%
  ungroup() %>%
  filter(n_chemo_codes_on_date == 1)

message(glue("  Rows with single-agent chemo on date: {nrow(single_agent_base)}"))

# D-02: Include encounters with drug_name = NA (use triggering_code as identifier)
# Keep one representative row per (patient_id, treatment_date, triggering_code, ENCOUNTERID)
single_agent_encounters <- single_agent_base %>%
  distinct(patient_id, treatment_date, triggering_code, drug_name,
           ENCOUNTERID, episode_number)

message(glue("  Single-agent encounters identified: {nrow(single_agent_encounters)}"))
message(glue("  Unique patients with single-agent encounters: {n_distinct(single_agent_encounters$patient_id)}"))

n_na_drug_name <- sum(is.na(single_agent_encounters$drug_name))
message(glue("  Encounters with NA drug_name (using triggering_code): {n_na_drug_name}"))


# ==============================================================================
# SECTION 5: TEMPORAL SELF-JOIN (+/-30-DAY WINDOW) (D-03) ----
# ==============================================================================

message()
message("--- Performing temporal self-join (+/-30-day window) ---")

# Convert to data.table for efficient cartesian join
single_dt <- as.data.table(single_agent_encounters)
all_chemo_dt <- as.data.table(
  chemo_detail %>%
    distinct(patient_id, treatment_date, triggering_code, drug_name, ENCOUNTERID)
)

setkey(single_dt, patient_id)
setkey(all_chemo_dt, patient_id)

message(glue("  Single-agent encounters for join: {nrow(single_dt)}"))
message(glue("  All chemo encounters for join: {nrow(all_chemo_dt)}"))

# Cartesian join on patient_id, then filter by date window
coadmin_dt <- single_dt[all_chemo_dt,
  on = .(patient_id),
  allow.cartesian = TRUE,
  nomatch = NULL
]

message(glue("  Cartesian product rows (same patient): {nrow(coadmin_dt)}"))

# D-03: Filter to +/-30-day window, exclude self-matches
coadmin_dt <- coadmin_dt[
  abs(as.numeric(difftime(i.treatment_date, treatment_date, units = "days"))) <= 30 &
  ENCOUNTERID != i.ENCOUNTERID
]

# Signed days_apart: negative = co-admin occurred before index encounter
coadmin_dt[, days_apart := as.integer(as.numeric(difftime(i.treatment_date, treatment_date, units = "days")))]

# Convert back to tibble for dplyr pipeline
coadmin_pairs <- as_tibble(coadmin_dt)

message(glue("  Co-administration pairs found: {nrow(coadmin_pairs)}"))
message(glue("  Unique patients with co-admin: {n_distinct(coadmin_pairs$patient_id)}"))


# ==============================================================================
# SECTION 6: BUILD DETAIL TABLE (COADMIN-01, D-07, D-08) ----
# ==============================================================================

message()
message("--- Building detail table ---")

# Resolve human-readable drug names for both index and co-admin drugs
# D-08: Show both drug name AND triggering_code
coadmin_detail <- coadmin_pairs %>%
  rowwise() %>%
  mutate(
    index_drug_name = resolve_drug_name(triggering_code, drug_name),
    coadmin_drug_name = resolve_drug_name(i.triggering_code, i.drug_name)
  ) %>%
  ungroup()

# D-07: Select and rename columns for the detail table
detail_table <- coadmin_detail %>%
  transmute(
    patient_id,
    index_encounter_id = ENCOUNTERID,
    index_treatment_date = treatment_date,
    index_triggering_code = triggering_code,
    index_drug_name,
    coadmin_encounter_id = i.ENCOUNTERID,
    coadmin_treatment_date = i.treatment_date,
    coadmin_triggering_code = i.triggering_code,
    coadmin_drug_name,
    days_apart
  ) %>%
  arrange(patient_id, index_treatment_date, abs(days_apart))

message(glue("  Detail table: {nrow(detail_table)} rows, {n_distinct(detail_table$patient_id)} patients"))


# ==============================================================================
# SECTION 7: BUILD PATTERN SUMMARY TABLE (COADMIN-02) ----
# ==============================================================================

message()
message("--- Building pattern summary table ---")

# Create sorted drug pairs to avoid A+B / B+A duplication
# Use pmin/pmax for alphabetical ordering of drug pairs
pattern_summary <- detail_table %>%
  mutate(
    drug_A = pmin(index_drug_name, coadmin_drug_name),
    drug_B = pmax(index_drug_name, coadmin_drug_name)
  ) %>%
  group_by(drug_A, drug_B) %>%
  summarise(
    n_instances = n(),
    n_patients = n_distinct(patient_id),
    mean_days_apart = round(mean(abs(days_apart)), 1),
    .groups = "drop"
  ) %>%
  arrange(desc(n_instances))

message(glue("  Unique drug pair patterns: {nrow(pattern_summary)}"))

# Log top 10 patterns
top_n_display <- min(10, nrow(pattern_summary))
if (top_n_display > 0) {
  message("  Top co-administration patterns:")
  for (i in seq_len(top_n_display)) {
    message(glue("    {pattern_summary$drug_A[i]} + {pattern_summary$drug_B[i]}: {pattern_summary$n_instances[i]} instances, {pattern_summary$n_patients[i]} patients"))
  }
}


# ==============================================================================
# SECTION 8: WRITE XLSX OUTPUT (D-06) ----
# ==============================================================================

message()
message("--- Writing xlsx output ---")

# D-06: Two-sheet xlsx
wb <- wb_workbook()

# Sheet 1: Co-Administration Detail (COADMIN-01)
wb$add_worksheet("Co-Administration Detail")
wb$add_data("Co-Administration Detail", detail_table, start_row = 1, col_names = TRUE)

# Sheet 2: Pattern Summary (COADMIN-02)
wb$add_worksheet("Pattern Summary")
wb$add_data("Pattern Summary", pattern_summary, start_row = 1, col_names = TRUE)

wb$save(OUTPUT_XLSX)
message(glue("  Saved output: {OUTPUT_XLSX}"))


# ==============================================================================
# SECTION 9: CONSOLE SUMMARY ----
# ==============================================================================

message()
message("=== Summary ===")
message(glue("  Total chemo encounters loaded: {nrow(detail %>% filter(treatment_type == 'Chemotherapy'))}"))
message(glue("  Encounters excluded (regimen-classified): {n_before_regimen_excl - n_after_regimen_excl}"))
message(glue("  Single-agent encounters identified: {nrow(single_agent_encounters)}"))
message(glue("  Encounters with co-administered drugs found: {n_distinct(detail_table$index_encounter_id)}"))
message(glue("  Total co-administration pairs in detail table: {nrow(detail_table)}"))
message(glue("  Unique drug pair patterns in summary table: {nrow(pattern_summary)}"))
message()

# Top 5 most common pairings
top_5_display <- min(5, nrow(pattern_summary))
if (top_5_display > 0) {
  message("  Top 5 most common pairings:")
  for (i in seq_len(top_5_display)) {
    message(glue("    {i}. {pattern_summary$drug_A[i]} + {pattern_summary$drug_B[i]}: {pattern_summary$n_instances[i]} instances ({pattern_summary$n_patients[i]} patients)"))
  }
}

message()
message(glue("  Output file: {OUTPUT_XLSX}"))
message(glue("  Log file: {LOG_FILE}"))
message()
message("Done.")

try(close(.log_con), silent = TRUE)
