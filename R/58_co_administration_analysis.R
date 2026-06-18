# ==============================================================================
# 58_co_administration_analysis.R -- Single-Agent Co-Administration Analysis
# ==============================================================================
#
# Purpose:
#   Identify single-agent chemotherapy dates (after removing non-specific ICD9
#   codes) and find all co-administered chemotherapies within a +/-30-day window.
#   Detects fragmented regimen patterns where multi-drug regimens (ABVD, BV+AVD)
#   appear as separate single-agent billing events instead of being billed together.
#   Directly answers team questions about single-agent chemo patterns.
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
# Phase 109 Decisions (ICD9 Filtering + Date-Grain Analysis):
#   D-01: Remove non-specific ICD9 procedure codes from triggering_code pool
#         before single-agent detection (99.25, 99.28 from TREATMENT_CODES$chemo_icd9)
#   D-02: Encounters where ONLY triggering code is a non-specific ICD9 code are
#         excluded entirely (patient-dates with only non-specific codes lost)
#   D-03: Single-agent detection at date grain: deduplicate to unique (patient_id,
#         treatment_date, specific_triggering_code), single-agent = exactly 1 unique
#         specific code per patient-date
#   D-04: Temporal self-join at date grain with triggering_code != i.triggering_code
#         (different agent, not different encounter)
#   D-05: "Single-agent" = one specific chemo triggering_code per patient-date after
#         ICD9 filtering (updated from Phase 102 D-01)
#   D-06: Replace existing co_administration_analysis.xlsx, same 2-sheet structure
#   D-07: Detail columns: patient_id, index_date, index_drug_code, index_drug_name,
#         coadmin_date, coadmin_drug_code, coadmin_drug_name, days_apart
#
# Phase 102 Decisions (Carried Forward, Unchanged):
#   +/-30-day window (Phase 102 D-03)
#   Chemo-to-chemo only (Phase 102 D-04)
#   Exclude regimen-classified encounters (Phase 102 D-05)
#   Two-sheet xlsx output (Phase 102 D-06)
#   Show both drug name and triggering_code (Phase 102 D-08)
#   Self-contained investigation script, no upstream modification (Phase 102 D-10)
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

message("=== Phase 109: Single-Agent Co-Administration Analysis (Date-Grain) ===")
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

# D-04 (carried forward): Filter to Chemotherapy treatment_type only
chemo_detail <- detail %>%
  filter(treatment_type == "Chemotherapy")
message(glue("  Chemotherapy-only rows: {nrow(chemo_detail)}"))

# D-05 (carried forward): Exclude encounters already classified as part of a multi-agent regimen
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

# --- Phase 109 D-01: Remove non-specific ICD9 procedure codes ---
# ICD9-CM Vol 3 codes 99.25 and 99.28 indicate "chemo happened" but do NOT
# identify which agent. They inflate distinct-code counts without adding
# agent-level information, blurring single-agent detection.
NON_SPECIFIC_ICD9 <- TREATMENT_CODES$chemo_icd9  # c("99.25", "99.28")
n_before_icd9 <- nrow(chemo_detail)
n_icd9_rows <- sum(chemo_detail$triggering_code %in% NON_SPECIFIC_ICD9)
message(glue("  Rows with non-specific ICD9 codes (99.25, 99.28): {n_icd9_rows}"))

# Remove non-specific ICD9 rows from the pool
chemo_detail_specific <- chemo_detail %>%
  filter(!(triggering_code %in% NON_SPECIFIC_ICD9))

# D-02: Check how many patient-dates lose ALL codes after ICD9 removal
# (patient-dates where the ONLY code was a non-specific ICD9)
dates_before <- chemo_detail %>%
  distinct(patient_id, treatment_date) %>%
  nrow()
dates_after <- chemo_detail_specific %>%
  distinct(patient_id, treatment_date) %>%
  nrow()
dates_lost <- dates_before - dates_after

message(glue("  Rows after removing non-specific ICD9 codes: {nrow(chemo_detail_specific)}"))
message(glue("  Patient-dates with ONLY non-specific ICD9 codes (excluded per D-02): {dates_lost}"))
message(glue("  Patient-dates remaining with specific codes: {dates_after}"))


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

# D-08 (carried forward): Multi-tier drug name resolution
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
# SECTION 4: IDENTIFY SINGLE-AGENT DATES (D-03, D-05) ----
# ==============================================================================

message()
message("--- Identifying single-agent dates (date grain) ---")

# D-03/D-05: Deduplicate to unique (patient_id, treatment_date, triggering_code)
# then count distinct specific codes per patient-date.
# Single-agent = exactly 1 unique specific chemo code on that date.
date_code_combos <- chemo_detail_specific %>%
  distinct(patient_id, treatment_date, triggering_code, drug_name)

single_agent_dates <- date_code_combos %>%
  group_by(patient_id, treatment_date) %>%
  mutate(n_specific_codes_on_date = n_distinct(triggering_code)) %>%
  ungroup() %>%
  filter(n_specific_codes_on_date == 1) %>%
  select(-n_specific_codes_on_date)

message(glue("  Unique (patient, date, code) combos: {nrow(date_code_combos)}"))
message(glue("  Single-agent patient-dates identified: {nrow(single_agent_dates)}"))
message(glue("  Unique patients with single-agent dates: {n_distinct(single_agent_dates$patient_id)}"))

n_na_drug_name <- sum(is.na(single_agent_dates$drug_name))
message(glue("  Patient-dates with NA drug_name (using triggering_code): {n_na_drug_name}"))


# ==============================================================================
# SECTION 5: TEMPORAL SELF-JOIN (+/-30-DAY WINDOW) (D-04) ----
# ==============================================================================

message()
message("--- Performing temporal self-join (+/-30-day window, date grain) ---")

# Convert to data.table for efficient cartesian join
single_dt <- as.data.table(single_agent_dates)
# All specific chemo data at date grain for the co-admin pool
all_chemo_dt <- as.data.table(date_code_combos)

setkey(single_dt, patient_id)
setkey(all_chemo_dt, patient_id)

message(glue("  Single-agent dates for join: {nrow(single_dt)}"))
message(glue("  All specific chemo date-code combos for join: {nrow(all_chemo_dt)}"))

# Cartesian join on patient_id, then filter by date window
coadmin_dt <- single_dt[all_chemo_dt,
  on = .(patient_id),
  allow.cartesian = TRUE,
  nomatch = NULL
]

message(glue("  Cartesian product rows (same patient): {nrow(coadmin_dt)}"))

# D-04: Filter to +/-30-day window, exclude same-agent matches
# Co-administration = a DIFFERENT chemo agent within +/-30 days.
# Same agent on different dates is repeat dosing, not co-administration.
coadmin_dt <- coadmin_dt[
  abs(as.numeric(difftime(i.treatment_date, treatment_date, units = "days"))) <= 30 &
  triggering_code != i.triggering_code
]

# Signed days_apart: negative = co-admin occurred before index date
coadmin_dt[, days_apart := as.integer(as.numeric(difftime(i.treatment_date, treatment_date, units = "days")))]

# Convert back to tibble for dplyr pipeline
coadmin_pairs <- as_tibble(coadmin_dt)

message(glue("  Co-administration pairs found: {nrow(coadmin_pairs)}"))
message(glue("  Unique patients with co-admin: {n_distinct(coadmin_pairs$patient_id)}"))


# ==============================================================================
# SECTION 6: BUILD DETAIL TABLE (COADMIN-01, D-07) ----
# ==============================================================================

message()
message("--- Building detail table (date grain) ---")

# Resolve human-readable drug names for both index and co-admin drugs
coadmin_detail <- coadmin_pairs %>%
  rowwise() %>%
  mutate(
    index_drug_name = resolve_drug_name(triggering_code, drug_name),
    coadmin_drug_name = resolve_drug_name(i.triggering_code, i.drug_name)
  ) %>%
  ungroup()

# D-07: Date-grain detail columns -- no encounter IDs
detail_table <- coadmin_detail %>%
  transmute(
    patient_id,
    index_date = treatment_date,
    index_drug_code = triggering_code,
    index_drug_name,
    coadmin_date = i.treatment_date,
    coadmin_drug_code = i.triggering_code,
    coadmin_drug_name,
    days_apart
  ) %>%
  arrange(patient_id, index_date, abs(days_apart))

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
message(glue("  Rows excluded (non-specific ICD9 codes): {n_icd9_rows}"))
message(glue("  Patient-dates lost (only had non-specific ICD9): {dates_lost}"))
message(glue("  Single-agent patient-dates identified: {nrow(single_agent_dates)}"))
message(glue("  Patient-dates with co-administered drugs found: {n_distinct(paste(detail_table$patient_id, detail_table$index_date))}"))
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
