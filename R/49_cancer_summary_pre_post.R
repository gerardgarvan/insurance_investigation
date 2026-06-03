# ==============================================================================
# Phase 49: Cancer Summary - Pre/Post HL Counts
# ==============================================================================
#
# Purpose:
#   Create pre/post HL cancer summary showing patient counts split by timing
#   relative to first HL diagnosis date (before vs after vs both)
#
# Inputs:
#   - output/confirmed_hl_cohort.rds (Phase 47 output: ID, first_hl_dx_date, first_hl_dx_source)
#   - output/tables/cancer_summary.csv (Phase 47 output: for baseline metrics)
#   - DIAGNOSIS DuckDB table (for per-code pre/post/both counts)
#
# Outputs:
#   - output/tables/cancer_summary_table_pre_post.xlsx (two-sheet styled workbook)
#   - output/tables/cancer_summary_table_pre_post.csv (companion CSV)
#
# Dependencies:
#   - 00_config (CONFIG paths, PREFIX_MAP for classification)
#   - 01_load_pcornet (DuckDB connection, get_pcornet_table)
#
# Requirements:
#   DOC-01, DOC-02, DOC-03
#
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(openxlsx2)
  library(lubridate)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")

# SECTION 0: INPUT VALIDATION ----
# SAFE-02: Validate DIAGNOSIS table is available
assert_df_valid(
  pcornet$DIAGNOSIS, "DIAGNOSIS",
  required_cols = c("ID", "DX", "DX_TYPE", "DX_DATE"),
  script_name = "R/49"
)

# Define paths
INPUT_RDS <- file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds")
INPUT_CSV <- file.path(CONFIG$output_dir, "tables", "cancer_summary.csv")
OUTPUT_TABLE_XLSX <- build_output_path("tables", "cancer_summary_table_pre_post.xlsx")
OUTPUT_CSV <- build_output_path("tables", "cancer_summary_table_pre_post.csv")

# V2 outputs (Phase 77: 7-day filtered, per D-09/D-10)
OUTPUT_TABLE_V2_XLSX <- build_output_path("tables", "cancer_summary_table_pre_post_v2_7day.xlsx")
OUTPUT_CSV_V2 <- build_output_path("tables", "cancer_summary_table_pre_post_v2_7day.csv")
OUTPUT_RDS_V2 <- build_output_path("tables", "cancer_summary_table_pre_post_v2_7day.rds")

# Sentinel date cutoff (per D-11)
SENTINEL_CUTOFF <- as.Date("1910-01-01")

message("=== Phase 77: Cancer Summary - Pre/Post HL Counts (Dual Output) ===")
message(glue("Input RDS:          {INPUT_RDS}"))
message(glue("Input CSV:          {INPUT_CSV}"))
message(glue("V1 Output XLSX:     {OUTPUT_TABLE_XLSX}"))
message(glue("V1 Output CSV:      {OUTPUT_CSV}"))
message(glue("V2 Output XLSX:     {OUTPUT_TABLE_V2_XLSX}"))
message(glue("V2 Output CSV:      {OUTPUT_CSV_V2}"))
message(glue("V2 Output RDS:      {OUTPUT_RDS_V2}"))
message(glue("Sentinel cutoff:    {SENTINEL_CUTOFF}"))

# CANCER_SITE_MAP and classify_codes() provided by R/00_config.R + R/utils/utils_cancer.R

message(glue("Defined {length(unique(CANCER_SITE_MAP))} cancer site categories covering {length(CANCER_SITE_MAP)} prefixes"))

# ==============================================================================
# SECTION 3: LOAD INPUTS ----
# ==============================================================================

# SAFE-01: Validate input RDS exists
assert_rds_exists(INPUT_RDS, script_name = "R/49")

message(glue("\nLoading confirmed HL cohort from {INPUT_RDS}..."))
confirmed_hl_cohort <- readRDS(INPUT_RDS)
n_total_confirmed <- nrow(confirmed_hl_cohort)
message(glue("  Total confirmed HL patients: {format(n_total_confirmed, big.mark=',')}"))

# Separate: full cohort for baseline stats, date-subset for pre/post/both
n_with_date <- sum(!is.na(confirmed_hl_cohort$first_hl_dx_date))
n_missing_date <- sum(is.na(confirmed_hl_cohort$first_hl_dx_date))
message(glue("  Patients with known first_hl_dx_date: {format(n_with_date, big.mark=',')}"))
message(glue("  Patients with missing first_hl_dx_date: {format(n_missing_date, big.mark=',')}"))

cohort_with_dates <- confirmed_hl_cohort %>%
  filter(!is.na(first_hl_dx_date))

message(glue("  Full cohort (baseline stats): {format(n_total_confirmed, big.mark=',')} patients"))
message(glue("  Date subset (pre/post/both): {format(nrow(cohort_with_dates), big.mark=',')} patients"))

# --- HL diagnosis date diagnostics (C81 rows for confirmed cohort) ---
message("\nHL Diagnosis Date Check (C81 rows for confirmed cohort):")

hl_c81_dx <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  select(ID, DX, DX_DATE) %>%
  collect() %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^C81")) %>%
  filter(ID %in% confirmed_hl_cohort$ID)

n_with_c81_dx <- n_distinct(hl_c81_dx$ID)
n_no_c81_dx <- n_total_confirmed - n_with_c81_dx
message(glue("  Cohort patients with any C81 dx row:   {format(n_with_c81_dx, big.mark=',')}"))
message(glue("  Cohort patients with NO C81 dx row:    {format(n_no_c81_dx, big.mark=',')}"))

hl_c81_with_date <- hl_c81_dx %>% filter(!is.na(DX_DATE))
n_valid_c81_date <- n_distinct(hl_c81_with_date$ID)
n_no_c81_date <- n_with_c81_dx - n_valid_c81_date
message(glue("  With valid C81 DX_DATE:                {format(n_valid_c81_date, big.mark=',')}"))
message(glue("  With NO valid C81 DX_DATE:             {format(n_no_c81_date, big.mark=',')}"))

n_c81_7day <- hl_c81_with_date %>%
  distinct(ID, DX_DATE) %>%
  group_by(ID) %>%
  filter(n() >= 2, as.numeric(max(DX_DATE) - min(DX_DATE)) >= 7) %>%
  ungroup() %>%
  pull(ID) %>%
  n_distinct()

message(glue("  With 2+ unique dates, 7-day span:      {format(n_c81_7day, big.mark=',')}"))
message(glue("  Rate (of cohort):                      {scales::percent(n_c81_7day / n_total_confirmed, accuracy=0.1)}"))
message(glue("  Rate (of those with date):             {scales::percent(n_c81_7day / n_valid_c81_date, accuracy=0.1)}"))

# --- Phase 77 CANCER-01: NLPHL vs Classical HL diagnostic split ---
hl_nlphl <- hl_c81_dx %>% filter(str_detect(DX_norm, "^C810"))
hl_classical <- hl_c81_dx %>% filter(!str_detect(DX_norm, "^C810"))

n_with_nlphl <- n_distinct(hl_nlphl$ID)
n_with_classical <- n_distinct(hl_classical$ID)
n_with_both <- length(intersect(unique(hl_nlphl$ID), unique(hl_classical$ID)))

message(glue("  NLPHL (C81.0x) patients:             {format(n_with_nlphl, big.mark=',')}"))
message(glue("  Classical HL (C81.1-C81.9) patients:  {format(n_with_classical, big.mark=',')}"))
message(glue("  Overlap (both NLPHL + classical):     {format(n_with_both, big.mark=',')}"))

if (n_with_both > 0) {
  warning(glue("[R/49 WARNING] {n_with_both} patients have both NLPHL and classical HL codes -- clinically valid but flagged for review"))
}

rm(hl_nlphl, hl_classical, hl_c81_dx, hl_c81_with_date)

# Load baseline cancer_summary.csv (for baseline metrics per D-01)
# SAFE-01: Validate input CSV exists
checkmate::assert_file_exists(INPUT_CSV, access = "r",
  .var.name = glue("[R/49 ERROR] Cancer summary CSV -- run R/47 first"))

message(glue("\nLoading baseline {INPUT_CSV}..."))
cancer_summary <- read.csv(INPUT_CSV, stringsAsFactors = FALSE)
n_loaded <- nrow(cancer_summary)
message(glue("  Loaded {format(n_loaded, big.mark=',')} patient-code rows"))

# Filter cancer_summary: remove D-codes, filter to FULL confirmed cohort (keep C81 for baseline stats)
cancer_summary <- cancer_summary %>%
  filter(!str_detect(cancer_code, "^D")) %>%
  inner_join(confirmed_hl_cohort %>% select(ID), by = "ID")

message(glue("  After D-code removal and cohort filter: {format(nrow(cancer_summary), big.mark=',')} rows"))
message(glue("  Unique patients: {format(n_distinct(cancer_summary$ID), big.mark=',')}"))
message(glue("  Unique codes: {format(n_distinct(cancer_summary$cancer_code), big.mark=',')}"))

# --- Phase 77 CANCER-02: V2 7-day filtered dataset (per D-01) ---
cancer_summary_v2 <- cancer_summary %>%
  filter(two_or_more_unique_dates_gt_7 == 1)

v2_n_rows <- nrow(cancer_summary_v2)
v2_n_patients <- n_distinct(cancer_summary_v2$ID)
v2_n_codes <- n_distinct(cancer_summary_v2$cancer_code)

message(glue("\n  V2 (7-day filtered): {format(v2_n_rows, big.mark=',')} rows"))
message(glue("  V2 unique patients: {format(v2_n_patients, big.mark=',')}"))
message(glue("  V2 unique codes: {format(v2_n_codes, big.mark=',')}"))

# CANCER-02 / D-04: Assert total v2 population within tolerance range
checkmate::assert_int(
  as.integer(v2_n_patients),
  lower = 6300L, upper = 6500L,
  .var.name = glue("[R/49 CANCER-02 ERROR] V2 7-day total population expected 6300-6500, got {v2_n_patients}")
)
message(glue("  V2 population assertion PASSED: {v2_n_patients} in [6300, 6500]"))

# ==============================================================================
# SECTION 4: QUERY DIAGNOSIS FOR RAW DATE ROWS ----
# ==============================================================================

message("\nQuerying DIAGNOSIS for C-code diagnosis rows...")

# Use full cohort for DuckDB query; pre/post filtering happens in Section 5
cohort_ids <- confirmed_hl_cohort$ID

dx_raw <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^C")) %>%
  select(ID, DX_norm, DX_DATE) %>%
  collect() %>%
  filter(ID %in% cohort_ids)

message(glue("  Retrieved {format(nrow(dx_raw), big.mark=',')} C-code diagnosis rows for cohort"))

# Exclude sentinel dates (per D-11)
n_sentinel <- sum(!is.na(dx_raw$DX_DATE) & dx_raw$DX_DATE < SENTINEL_CUTOFF)
message(glue("  Sentinel/invalid DX_DATE rows (before {SENTINEL_CUTOFF}): {n_sentinel} -- excluding"))

dx_raw <- dx_raw %>%
  filter(is.na(DX_DATE) | DX_DATE >= SENTINEL_CUTOFF)

message(glue("  After sentinel exclusion: {format(nrow(dx_raw), big.mark=',')} rows"))

# Exclude C81 rows from dx_raw (per D-09)
n_before_c81_removal <- nrow(dx_raw)
dx_raw <- dx_raw %>%
  filter(!str_detect(DX_norm, "^C81"))
n_removed_c81 <- n_before_c81_removal - nrow(dx_raw)

message(glue("  C81 rows excluded: {format(n_removed_c81, big.mark=',')} ({format(nrow(dx_raw), big.mark=',')} remaining)"))

# ==============================================================================
# SECTION 5: COMPUTE PRE/POST/BOTH SETS ----
# ==============================================================================

message("\nComputing pre/post/both patient-code sets...")

# Join dx_raw with cohort_with_dates (only patients with known HL date) for temporal split
dx_with_hl_date <- dx_raw %>%
  inner_join(cohort_with_dates %>% select(ID, first_hl_dx_date), by = "ID") %>%
  filter(!is.na(DX_DATE))

message(glue("  Rows with valid DX_DATE: {format(nrow(dx_with_hl_date), big.mark=',')}"))

# Pre-HL: DX_DATE <= first_hl_dx_date (same-day included per D-08)
dx_pre_hl <- dx_with_hl_date %>%
  filter(DX_DATE <= first_hl_dx_date)

# Post-HL: DX_DATE > first_hl_dx_date (strict > per D-08)
dx_post_hl <- dx_with_hl_date %>%
  filter(DX_DATE > first_hl_dx_date)

message(glue("  Pre-HL rows: {format(nrow(dx_pre_hl), big.mark=',')}"))
message(glue("  Post-HL rows: {format(nrow(dx_post_hl), big.mark=',')}"))

# Compute patient-code pairs per temporal set (per D-04)
patients_pre <- dx_pre_hl %>%
  distinct(ID, DX_norm) %>%
  rename(cancer_code = DX_norm)

patients_post <- dx_post_hl %>%
  distinct(ID, DX_norm) %>%
  rename(cancer_code = DX_norm)

patients_both <- patients_pre %>%
  inner_join(patients_post, by = c("ID", "cancer_code"))

message(glue("  Pre-HL patient-code pairs: {format(nrow(patients_pre), big.mark=',')} ({format(n_distinct(patients_pre$ID), big.mark=',')} patients)"))
message(glue("  Post-HL patient-code pairs: {format(nrow(patients_post), big.mark=',')} ({format(n_distinct(patients_post$ID), big.mark=',')} patients)"))
message(glue("  Both (intersection): {format(nrow(patients_both), big.mark=',')} patient-code pairs ({format(n_distinct(patients_both$ID), big.mark=',')} patients)"))

# Aggregate counts by code
pre_counts <- patients_pre %>%
  group_by(cancer_code) %>%
  summarise(pre_hl_count = n_distinct(ID), .groups = "drop")

post_counts <- patients_post %>%
  group_by(cancer_code) %>%
  summarise(post_hl_count = n_distinct(ID), .groups = "drop")

both_counts <- patients_both %>%
  group_by(cancer_code) %>%
  summarise(both_count = n_distinct(ID), .groups = "drop")

message(glue("  Pre-HL codes: {nrow(pre_counts)}"))
message(glue("  Post-HL codes: {nrow(post_counts)}"))
message(glue("  Both codes: {nrow(both_counts)}"))

# ==============================================================================
# PHASE 77: DRY HELPER FUNCTIONS ----
# ==============================================================================

# --- Phase 77: DRY helper for code-level summary (reused for v1 and v2) ---
compute_code_baseline <- function(cs_df, label) {
  message(glue("\nComputing baseline metrics ({label})..."))
  cb <- cs_df %>%
    group_by(cancer_code) %>%
    summarise(
      total_patients = n_distinct(ID),
      confirmed_2date = n_distinct(ID[two_or_more_unique_dates == 1]),
      pct_confirmed_2date = n_distinct(ID[two_or_more_unique_dates == 1]) / n_distinct(ID),
      confirmed_7day = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]),
      pct_confirmed_7day = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]) / n_distinct(ID),
      mean_unique_dates = mean(unique_dates_total, na.rm = TRUE),
      median_unique_dates = median(unique_dates_total, na.rm = TRUE),
      mean_dates_7day_sep = mean(unique_dates_with_sep_gt_7, na.rm = TRUE),
      median_dates_7day_sep = median(unique_dates_with_sep_gt_7, na.rm = TRUE),
      .groups = "drop"
    )
  message(glue("  {label}: {nrow(cb)} codes"))
  return(cb)
}

compute_category_summary <- function(cs_df, label) {
  message(glue("\nAggregating to category level ({label})..."))
  cat_sum <- cs_df %>%
    mutate(category = classify_codes(cancer_code)) %>%
    group_by(category) %>%
    summarise(
      total_patients = n_distinct(ID),
      confirmed_2date = n_distinct(ID[two_or_more_unique_dates == 1]),
      pct_confirmed_2date = n_distinct(ID[two_or_more_unique_dates == 1]) / n_distinct(ID),
      confirmed_7day = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]),
      pct_confirmed_7day = n_distinct(ID[two_or_more_unique_dates_gt_7 == 1]) / n_distinct(ID),
      mean_unique_dates = mean(unique_dates_total, na.rm = TRUE),
      median_unique_dates = median(unique_dates_total, na.rm = TRUE),
      mean_dates_7day_sep = mean(unique_dates_with_sep_gt_7, na.rm = TRUE),
      median_dates_7day_sep = median(unique_dates_with_sep_gt_7, na.rm = TRUE),
      .groups = "drop"
    )
  cat_sum$category[is.na(cat_sum$category)] <- "Unclassified"
  message(glue("  {label}: {nrow(cat_sum)} categories"))
  return(cat_sum)
}

# ==============================================================================
# SECTION 6: COMPUTE BASELINE METRICS ----
# ==============================================================================

message("\nComputing baseline metrics from cancer_summary...")

# Code-level baseline metrics (already filtered to confirmed cohort, no D-codes; C81 included)
code_baseline <- compute_code_baseline(cancer_summary, "V1 unfiltered")

# Query DuckDB record counts per code (including C81)
message("\nQuerying DIAGNOSIS for record counts...")

dx_record_counts <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^C")) %>%
  select(ID, DX_norm) %>%
  collect() %>%
  filter(ID %in% cohort_ids) %>%
  group_by(DX_norm) %>%
  summarise(total_records = n(), .groups = "drop")

message(glue("  Record counts for {nrow(dx_record_counts)} codes"))

# Add category via classify_codes()
code_baseline <- code_baseline %>%
  mutate(category = classify_codes(cancer_code))

# Handle unclassified codes
n_unclassified <- sum(is.na(code_baseline$category))
if (n_unclassified > 0) {
  unclass_codes <- unique(code_baseline$cancer_code[is.na(code_baseline$category)])
  message(glue("  WARNING: {n_unclassified} codes unclassified"))
  message(glue("    Codes: {paste(head(unclass_codes, 20), collapse=', ')}"))
  code_baseline$category[is.na(code_baseline$category)] <- "Unclassified"
}

# ==============================================================================
# SECTION 7: MERGE AND BUILD CODE-LEVEL TABLE ----
# ==============================================================================

message("\nBuilding code-level summary table...")

code_summary <- code_baseline %>%
  left_join(pre_counts, by = "cancer_code") %>%
  left_join(post_counts, by = "cancer_code") %>%
  left_join(both_counts, by = "cancer_code") %>%
  left_join(dx_record_counts, by = c("cancer_code" = "DX_norm")) %>%
  mutate(
    total_records = coalesce(total_records, 0L),
    # C81 codes keep NA for pre/post/both (anchor diagnosis); others get 0
    pre_hl_count  = if_else(str_detect(cancer_code, "^C81"), NA_integer_, coalesce(as.integer(pre_hl_count), 0L)),
    post_hl_count = if_else(str_detect(cancer_code, "^C81"), NA_integer_, coalesce(as.integer(post_hl_count), 0L)),
    both_count    = if_else(str_detect(cancer_code, "^C81"), NA_integer_, coalesce(as.integer(both_count), 0L))
  )

# Select columns: R/55 baseline stats + pre/post/both + total records
code_summary <- code_summary %>%
  select(
    cancer_code, category, total_patients, confirmed_2date, pct_confirmed_2date,
    confirmed_7day, pct_confirmed_7day, mean_unique_dates, median_unique_dates,
    mean_dates_7day_sep, median_dates_7day_sep, pre_hl_count, post_hl_count,
    both_count, total_records
  ) %>%
  arrange(desc(total_patients))

message(glue("  Code summary: {nrow(code_summary)} rows"))

# ==============================================================================
# SECTION 8: BUILD CATEGORY-LEVEL TABLE ----
# ==============================================================================

message("\nAggregating to category level...")

# Compute category-level base stats from patient-level data (same approach as R/55)
category_summary <- compute_category_summary(cancer_summary, "V1 unfiltered")

# Add category-level pre/post/both using UNIQUE patients per category (not summing code counts)
# Summing code-level counts would double-count patients with multiple codes in the same category
cat_pre_by_category <- patients_pre %>%
  mutate(category = classify_codes(cancer_code)) %>%
  group_by(category) %>%
  summarise(pre_hl_count = n_distinct(ID), .groups = "drop")

cat_post_by_category <- patients_post %>%
  mutate(category = classify_codes(cancer_code)) %>%
  group_by(category) %>%
  summarise(post_hl_count = n_distinct(ID), .groups = "drop")

cat_both_by_category <- patients_both %>%
  mutate(category = classify_codes(cancer_code)) %>%
  group_by(category) %>%
  summarise(both_count = n_distinct(ID), .groups = "drop")

# Total records can be summed (it's row counts, not patients)
cat_records <- code_summary %>%
  group_by(category) %>%
  summarise(total_records = sum(total_records), .groups = "drop")

category_summary <- category_summary %>%
  left_join(cat_pre_by_category, by = "category") %>%
  left_join(cat_post_by_category, by = "category") %>%
  left_join(cat_both_by_category, by = "category") %>%
  left_join(cat_records, by = "category") %>%
  mutate(
    # Hodgkin Lymphoma (non-NLPHL) and NLPHL stay NA (C81 excluded from pre/post); others get 0 if no matches
    pre_hl_count  = if_else(category %in% c("Hodgkin Lymphoma (non-NLPHL)", "NLPHL"), NA_integer_, coalesce(as.integer(pre_hl_count), 0L)),
    post_hl_count = if_else(category %in% c("Hodgkin Lymphoma (non-NLPHL)", "NLPHL"), NA_integer_, coalesce(as.integer(post_hl_count), 0L)),
    both_count    = if_else(category %in% c("Hodgkin Lymphoma (non-NLPHL)", "NLPHL"), NA_integer_, coalesce(as.integer(both_count), 0L))
  ) %>%
  arrange(desc(total_patients))

# Handle unclassified in category_summary
category_summary$category[is.na(category_summary$category)] <- "Unclassified"

message(glue("  Category summary: {nrow(category_summary)} rows"))

# Build totals rows using UNIQUE patients (not sums of per-code/category counts)
totals_category <- tibble(
  category              = "TOTAL",
  total_patients        = n_distinct(cancer_summary$ID),
  confirmed_2date       = n_distinct(cancer_summary$ID[cancer_summary$two_or_more_unique_dates == 1]),
  pct_confirmed_2date   = NA_real_,
  confirmed_7day        = n_distinct(cancer_summary$ID[cancer_summary$two_or_more_unique_dates_gt_7 == 1]),
  pct_confirmed_7day    = NA_real_,
  mean_unique_dates     = NA_real_,
  median_unique_dates   = NA_real_,
  mean_dates_7day_sep   = NA_real_,
  median_dates_7day_sep = NA_real_,
  pre_hl_count          = as.integer(n_distinct(patients_pre$ID)),
  post_hl_count         = as.integer(n_distinct(patients_post$ID)),
  both_count            = as.integer(n_distinct(patients_both$ID)),
  total_records         = sum(category_summary$total_records)
)

totals_code <- tibble(
  cancer_code           = "TOTAL",
  category              = "",
  total_patients        = n_distinct(cancer_summary$ID),
  confirmed_2date       = n_distinct(cancer_summary$ID[cancer_summary$two_or_more_unique_dates == 1]),
  pct_confirmed_2date   = NA_real_,
  confirmed_7day        = n_distinct(cancer_summary$ID[cancer_summary$two_or_more_unique_dates_gt_7 == 1]),
  pct_confirmed_7day    = NA_real_,
  mean_unique_dates     = NA_real_,
  median_unique_dates   = NA_real_,
  mean_dates_7day_sep   = NA_real_,
  median_dates_7day_sep = NA_real_,
  pre_hl_count          = as.integer(n_distinct(patients_pre$ID)),
  post_hl_count         = as.integer(n_distinct(patients_post$ID)),
  both_count            = as.integer(n_distinct(patients_both$ID)),
  total_records         = sum(code_summary$total_records)
)

# ==============================================================================
# SECTION 8b: V2 (7-DAY FILTERED) TABLES ----
# ==============================================================================
# Phase 77 CANCER-02: Same aggregation logic applied to filtered dataset
# IMPORTANT: Pre/post/both counts are ALSO filtered to 7-day confirmed
# patient-code pairs, so counts are consistent with total_patients.

message("\n--- V2 (7-day filtered) Tables ---")

code_baseline_v2 <- compute_code_baseline(cancer_summary_v2, "V2 7-day filtered")

# Add category and classify
code_baseline_v2 <- code_baseline_v2 %>%
  mutate(category = classify_codes(cancer_code))
n_unclassified_v2 <- sum(is.na(code_baseline_v2$category))
if (n_unclassified_v2 > 0) {
  code_baseline_v2$category[is.na(code_baseline_v2$category)] <- "Unclassified"
}

# --- V2 pre/post/both: filter to 7-day confirmed patient-code pairs ---
# Only count a patient as pre/post/both for a code if they meet the 7-day
# gap threshold for that code (i.e., appear in cancer_summary_v2).
v2_valid_pairs <- cancer_summary_v2 %>%
  distinct(ID, cancer_code)

message(glue("  V2 valid patient-code pairs: {format(nrow(v2_valid_pairs), big.mark=',')}"))

patients_pre_v2 <- patients_pre %>%
  semi_join(v2_valid_pairs, by = c("ID", "cancer_code"))

patients_post_v2 <- patients_post %>%
  semi_join(v2_valid_pairs, by = c("ID", "cancer_code"))

patients_both_v2 <- patients_both %>%
  semi_join(v2_valid_pairs, by = c("ID", "cancer_code"))

message(glue("  V2 pre-HL patient-code pairs: {format(nrow(patients_pre_v2), big.mark=',')} ({format(n_distinct(patients_pre_v2$ID), big.mark=',')} patients)"))
message(glue("  V2 post-HL patient-code pairs: {format(nrow(patients_post_v2), big.mark=',')} ({format(n_distinct(patients_post_v2$ID), big.mark=',')} patients)"))
message(glue("  V2 both (intersection): {format(nrow(patients_both_v2), big.mark=',')} patient-code pairs ({format(n_distinct(patients_both_v2$ID), big.mark=',')} patients)"))

# Code-level pre/post/both counts (V2 filtered)
pre_counts_v2 <- patients_pre_v2 %>%
  group_by(cancer_code) %>%
  summarise(pre_hl_count = n_distinct(ID), .groups = "drop")

post_counts_v2 <- patients_post_v2 %>%
  group_by(cancer_code) %>%
  summarise(post_hl_count = n_distinct(ID), .groups = "drop")

both_counts_v2 <- patients_both_v2 %>%
  group_by(cancer_code) %>%
  summarise(both_count = n_distinct(ID), .groups = "drop")

# V2 code summary: join with V2-filtered pre/post/both counts
code_summary_v2 <- code_baseline_v2 %>%
  left_join(pre_counts_v2, by = "cancer_code") %>%
  left_join(post_counts_v2, by = "cancer_code") %>%
  left_join(both_counts_v2, by = "cancer_code") %>%
  left_join(dx_record_counts, by = c("cancer_code" = "DX_norm")) %>%
  mutate(
    total_records = coalesce(total_records, 0L),
    pre_hl_count  = if_else(str_detect(cancer_code, "^C81"), NA_integer_, coalesce(as.integer(pre_hl_count), 0L)),
    post_hl_count = if_else(str_detect(cancer_code, "^C81"), NA_integer_, coalesce(as.integer(post_hl_count), 0L)),
    both_count    = if_else(str_detect(cancer_code, "^C81"), NA_integer_, coalesce(as.integer(both_count), 0L))
  ) %>%
  select(
    cancer_code, category, total_patients, confirmed_2date, pct_confirmed_2date,
    confirmed_7day, pct_confirmed_7day, mean_unique_dates, median_unique_dates,
    mean_dates_7day_sep, median_dates_7day_sep, pre_hl_count, post_hl_count,
    both_count, total_records
  ) %>%
  arrange(desc(total_patients))

# V2 category summary
category_summary_v2 <- compute_category_summary(cancer_summary_v2, "V2 7-day filtered")

# Category-level pre/post/both using V2-filtered patient sets (unique patients per category)
cat_pre_by_category_v2 <- patients_pre_v2 %>%
  mutate(category = classify_codes(cancer_code)) %>%
  group_by(category) %>%
  summarise(pre_hl_count = n_distinct(ID), .groups = "drop")

cat_post_by_category_v2 <- patients_post_v2 %>%
  mutate(category = classify_codes(cancer_code)) %>%
  group_by(category) %>%
  summarise(post_hl_count = n_distinct(ID), .groups = "drop")

cat_both_by_category_v2 <- patients_both_v2 %>%
  mutate(category = classify_codes(cancer_code)) %>%
  group_by(category) %>%
  summarise(both_count = n_distinct(ID), .groups = "drop")

cat_records_v2 <- code_summary_v2 %>%
  group_by(category) %>%
  summarise(total_records = sum(total_records), .groups = "drop")

category_summary_v2 <- category_summary_v2 %>%
  left_join(cat_pre_by_category_v2, by = "category") %>%
  left_join(cat_post_by_category_v2, by = "category") %>%
  left_join(cat_both_by_category_v2, by = "category") %>%
  left_join(cat_records_v2, by = "category") %>%
  mutate(
    pre_hl_count  = if_else(category %in% c("Hodgkin Lymphoma (non-NLPHL)", "NLPHL"), NA_integer_, coalesce(as.integer(pre_hl_count), 0L)),
    post_hl_count = if_else(category %in% c("Hodgkin Lymphoma (non-NLPHL)", "NLPHL"), NA_integer_, coalesce(as.integer(post_hl_count), 0L)),
    both_count    = if_else(category %in% c("Hodgkin Lymphoma (non-NLPHL)", "NLPHL"), NA_integer_, coalesce(as.integer(both_count), 0L))
  ) %>%
  arrange(desc(total_patients))

# V2 totals (using V2-filtered patient sets)
totals_category_v2 <- tibble(
  category              = "TOTAL",
  total_patients        = n_distinct(cancer_summary_v2$ID),
  confirmed_2date       = n_distinct(cancer_summary_v2$ID[cancer_summary_v2$two_or_more_unique_dates == 1]),
  pct_confirmed_2date   = NA_real_,
  confirmed_7day        = n_distinct(cancer_summary_v2$ID[cancer_summary_v2$two_or_more_unique_dates_gt_7 == 1]),
  pct_confirmed_7day    = NA_real_,
  mean_unique_dates     = NA_real_,
  median_unique_dates   = NA_real_,
  mean_dates_7day_sep   = NA_real_,
  median_dates_7day_sep = NA_real_,
  pre_hl_count          = as.integer(n_distinct(patients_pre_v2$ID)),
  post_hl_count         = as.integer(n_distinct(patients_post_v2$ID)),
  both_count            = as.integer(n_distinct(patients_both_v2$ID)),
  total_records         = sum(category_summary_v2$total_records)
)

totals_code_v2 <- tibble(
  cancer_code           = "TOTAL",
  category              = "",
  total_patients        = n_distinct(cancer_summary_v2$ID),
  confirmed_2date       = n_distinct(cancer_summary_v2$ID[cancer_summary_v2$two_or_more_unique_dates == 1]),
  pct_confirmed_2date   = NA_real_,
  confirmed_7day        = n_distinct(cancer_summary_v2$ID[cancer_summary_v2$two_or_more_unique_dates_gt_7 == 1]),
  pct_confirmed_7day    = NA_real_,
  mean_unique_dates     = NA_real_,
  median_unique_dates   = NA_real_,
  mean_dates_7day_sep   = NA_real_,
  median_dates_7day_sep = NA_real_,
  pre_hl_count          = as.integer(n_distinct(patients_pre_v2$ID)),
  post_hl_count         = as.integer(n_distinct(patients_post_v2$ID)),
  both_count            = as.integer(n_distinct(patients_both_v2$ID)),
  total_records         = sum(code_summary_v2$total_records)
)

# --- D-03: V1 vs V2 comparison table (console only) ---
comparison <- code_baseline %>%
  select(cancer_code, v1_patients = total_patients) %>%
  left_join(
    code_baseline_v2 %>% select(cancer_code, v2_patients = total_patients),
    by = "cancer_code"
  ) %>%
  mutate(
    v2_patients = coalesce(v2_patients, 0L),
    delta = v2_patients - v1_patients,
    pct_change = if_else(v1_patients > 0, delta / v1_patients, NA_real_)
  ) %>%
  arrange(desc(abs(delta)))

message("\n=== V1 vs V2 Population Deltas (Top 15 by absolute delta) ===")
message("  V1 = unfiltered baseline | V2 = 7-day confirmed")
print(head(comparison, 15))
message(glue("\n  V1 total unique patients: {n_distinct(cancer_summary$ID)}"))
message(glue("  V2 total unique patients: {n_distinct(cancer_summary_v2$ID)}"))
message(glue("  Net delta: {n_distinct(cancer_summary_v2$ID) - n_distinct(cancer_summary$ID)}"))

# ==============================================================================
# SECTION 9: WRITE XLSX OUTPUT ----
# ==============================================================================

message(glue("\nWriting {OUTPUT_TABLE_XLSX}..."))

# Styling constants (same as R/55 per D-16)
DARK_HEADER_FILL <- "FF374151"
WHITE_FONT <- "FFFFFFFF"
TITLE_FONT_COLOR <- "FF1F2937"
TOTALS_FILL <- "FFE5E7EB"

wb <- wb_workbook()

# ---------------------------------------------------------------------------
# Sheet 1: "Category Summary" (14 columns A-N)
# ---------------------------------------------------------------------------
SHEET1 <- "Category Summary"
wb$add_worksheet(SHEET1)

# Row 1: Title
wb$add_data(
  sheet = SHEET1, x = "Cancer Summary Table - Pre/Post HL Diagnosis (By Category)",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = SHEET1, dims = "A1",
  name = "Calibri", size = 16, bold = TRUE,
  color = wb_color(TITLE_FONT_COLOR)
)
wb$merge_cells(sheet = SHEET1, dims = "A1:N1")

# Row 2: Headers
headers1 <- c(
  "Cancer Site Category",
  "Total Patients",
  "Confirmed (2+ Dates)",
  "Rate (2+ Dates)",
  "Confirmed (7-Day Gap)",
  "Rate (7-Day Gap)",
  "Mean Unique Dates",
  "Median Unique Dates",
  "Mean Dates (7-Day Sep)",
  "Median Dates (7-Day Sep)",
  "Pre-HL",
  "Post-HL",
  "Both",
  "Total Records"
)
for (i in seq_along(headers1)) {
  wb$add_data(sheet = SHEET1, x = headers1[i], start_row = 2, start_col = i)
}
wb$add_fill(sheet = SHEET1, dims = "A2:N2", color = wb_color(DARK_HEADER_FILL))
wb$add_font(
  sheet = SHEET1, dims = "A2:N2",
  name = "Calibri", size = 11, bold = TRUE,
  color = wb_color(WHITE_FONT)
)

# Freeze pane
wb$freeze_pane(sheet = SHEET1, first_active_row = 3, first_active_col = 1)

# Data rows starting at row 3
data_start1 <- 3
n_data1 <- nrow(category_summary)
data_end1 <- data_start1 + n_data1 - 1

wb$add_data(
  sheet = SHEET1, x = as.data.frame(category_summary),
  start_row = data_start1, col_names = FALSE
)

# Number formatting (matching R/55 pattern + pre/post/both)
# B, C, E (integer counts): "#,##0"
wb$add_numfmt(sheet = SHEET1, dims = glue("B{data_start1}:B{data_end1}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET1, dims = glue("C{data_start1}:C{data_end1}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET1, dims = glue("E{data_start1}:E{data_end1}"), numfmt = "#,##0")
# D, F (percentage rates): "0.0%"
wb$add_numfmt(sheet = SHEET1, dims = glue("D{data_start1}:D{data_end1}"), numfmt = "0.0%")
wb$add_numfmt(sheet = SHEET1, dims = glue("F{data_start1}:F{data_end1}"), numfmt = "0.0%")
# G, H, I, J (mean/median decimals): "0.0"
wb$add_numfmt(sheet = SHEET1, dims = glue("G{data_start1}:G{data_end1}"), numfmt = "0.0")
wb$add_numfmt(sheet = SHEET1, dims = glue("H{data_start1}:H{data_end1}"), numfmt = "0.0")
wb$add_numfmt(sheet = SHEET1, dims = glue("I{data_start1}:I{data_end1}"), numfmt = "0.0")
wb$add_numfmt(sheet = SHEET1, dims = glue("J{data_start1}:J{data_end1}"), numfmt = "0.0")
# K, L, M (pre/post/both counts): "#,##0"
wb$add_numfmt(sheet = SHEET1, dims = glue("K{data_start1}:K{data_end1}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET1, dims = glue("L{data_start1}:L{data_end1}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET1, dims = glue("M{data_start1}:M{data_end1}"), numfmt = "#,##0")
# N (total records): "#,##0"
wb$add_numfmt(sheet = SHEET1, dims = glue("N{data_start1}:N{data_end1}"), numfmt = "#,##0")

# Totals row
totals_row1 <- data_end1 + 1
wb$add_data(
  sheet = SHEET1, x = as.data.frame(totals_category),
  start_row = totals_row1, col_names = FALSE
)
wb$add_fill(
  sheet = SHEET1,
  dims = glue("A{totals_row1}:N{totals_row1}"),
  color = wb_color(TOTALS_FILL)
)
wb$add_font(
  sheet = SHEET1,
  dims = glue("A{totals_row1}:N{totals_row1}"),
  name = "Calibri", size = 11, bold = TRUE,
  color = wb_color(TITLE_FONT_COLOR)
)
wb$add_numfmt(sheet = SHEET1, dims = glue("B{totals_row1}:B{totals_row1}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET1, dims = glue("C{totals_row1}:C{totals_row1}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET1, dims = glue("E{totals_row1}:E{totals_row1}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET1, dims = glue("K{totals_row1}:K{totals_row1}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET1, dims = glue("L{totals_row1}:L{totals_row1}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET1, dims = glue("M{totals_row1}:M{totals_row1}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET1, dims = glue("N{totals_row1}:N{totals_row1}"), numfmt = "#,##0")

# Footnote row
footnote_row1 <- totals_row1 + 2
footnote_text1 <- glue("Baseline stats: full confirmed 7-day HL cohort ({n_total_confirmed} patients). Pre/Post/Both: {nrow(cohort_with_dates)} patients with known first_hl_dx_date. Pre: DX_DATE <= first_hl_dx_date. Post: DX_DATE > first_hl_dx_date. Both: patient had code pre AND post. C81 pre/post/both left blank (anchor diagnosis).")
wb$add_data(
  sheet = SHEET1,
  x = footnote_text1,
  start_row = footnote_row1, start_col = 1
)
wb$add_font(
  sheet = SHEET1, dims = glue("A{footnote_row1}"),
  name = "Calibri", size = 10, italic = TRUE,
  color = wb_color("FF6B7280")
)
wb$merge_cells(sheet = SHEET1, dims = glue("A{footnote_row1}:N{footnote_row1}"))

# Column widths
wb$set_col_widths(
  sheet = SHEET1, cols = 1:14,
  widths = c(40, 14, 18, 14, 18, 14, 16, 16, 18, 18, 10, 10, 10, 14)
)

# ---------------------------------------------------------------------------
# Sheet 2: "Code Summary" (15 columns A-O)
# ---------------------------------------------------------------------------
SHEET2 <- "Code Summary"
wb$add_worksheet(SHEET2)

# Row 1: Title
wb$add_data(
  sheet = SHEET2, x = "Cancer Summary Table - Pre/Post HL Diagnosis (By ICD-10 Code)",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = SHEET2, dims = "A1",
  name = "Calibri", size = 16, bold = TRUE,
  color = wb_color(TITLE_FONT_COLOR)
)
wb$merge_cells(sheet = SHEET2, dims = "A1:O1")

# Row 2: Headers
headers2 <- c(
  "ICD-10 Code",
  "Cancer Site Category",
  "Total Patients",
  "Confirmed (2+ Dates)",
  "Rate (2+ Dates)",
  "Confirmed (7-Day Gap)",
  "Rate (7-Day Gap)",
  "Mean Unique Dates",
  "Median Unique Dates",
  "Mean Dates (7-Day Sep)",
  "Median Dates (7-Day Sep)",
  "Pre-HL",
  "Post-HL",
  "Both",
  "Total Records"
)
for (i in seq_along(headers2)) {
  wb$add_data(sheet = SHEET2, x = headers2[i], start_row = 2, start_col = i)
}
wb$add_fill(sheet = SHEET2, dims = "A2:O2", color = wb_color(DARK_HEADER_FILL))
wb$add_font(
  sheet = SHEET2, dims = "A2:O2",
  name = "Calibri", size = 11, bold = TRUE,
  color = wb_color(WHITE_FONT)
)

# Freeze pane
wb$freeze_pane(sheet = SHEET2, first_active_row = 3, first_active_col = 1)

# Data rows starting at row 3
data_start2 <- 3
n_data2 <- nrow(code_summary)
data_end2 <- data_start2 + n_data2 - 1

wb$add_data(
  sheet = SHEET2, x = as.data.frame(code_summary),
  start_row = data_start2, col_names = FALSE
)

# Number formatting (matching R/55 pattern + pre/post/both)
# C, D, F (integer counts): "#,##0"
wb$add_numfmt(sheet = SHEET2, dims = glue("C{data_start2}:C{data_end2}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET2, dims = glue("D{data_start2}:D{data_end2}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET2, dims = glue("F{data_start2}:F{data_end2}"), numfmt = "#,##0")
# E, G (percentage rates): "0.0%"
wb$add_numfmt(sheet = SHEET2, dims = glue("E{data_start2}:E{data_end2}"), numfmt = "0.0%")
wb$add_numfmt(sheet = SHEET2, dims = glue("G{data_start2}:G{data_end2}"), numfmt = "0.0%")
# H, I, J, K (mean/median decimals): "0.0"
wb$add_numfmt(sheet = SHEET2, dims = glue("H{data_start2}:H{data_end2}"), numfmt = "0.0")
wb$add_numfmt(sheet = SHEET2, dims = glue("I{data_start2}:I{data_end2}"), numfmt = "0.0")
wb$add_numfmt(sheet = SHEET2, dims = glue("J{data_start2}:J{data_end2}"), numfmt = "0.0")
wb$add_numfmt(sheet = SHEET2, dims = glue("K{data_start2}:K{data_end2}"), numfmt = "0.0")
# L, M, N (pre/post/both counts): "#,##0"
wb$add_numfmt(sheet = SHEET2, dims = glue("L{data_start2}:L{data_end2}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET2, dims = glue("M{data_start2}:M{data_end2}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET2, dims = glue("N{data_start2}:N{data_end2}"), numfmt = "#,##0")
# O (total records): "#,##0"
wb$add_numfmt(sheet = SHEET2, dims = glue("O{data_start2}:O{data_end2}"), numfmt = "#,##0")

# Totals row
totals_row2 <- data_end2 + 1
wb$add_data(
  sheet = SHEET2, x = as.data.frame(totals_code),
  start_row = totals_row2, col_names = FALSE
)
wb$add_fill(
  sheet = SHEET2,
  dims = glue("A{totals_row2}:O{totals_row2}"),
  color = wb_color(TOTALS_FILL)
)
wb$add_font(
  sheet = SHEET2,
  dims = glue("A{totals_row2}:O{totals_row2}"),
  name = "Calibri", size = 11, bold = TRUE,
  color = wb_color(TITLE_FONT_COLOR)
)
wb$add_numfmt(sheet = SHEET2, dims = glue("C{totals_row2}:C{totals_row2}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET2, dims = glue("D{totals_row2}:D{totals_row2}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET2, dims = glue("F{totals_row2}:F{totals_row2}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET2, dims = glue("L{totals_row2}:L{totals_row2}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET2, dims = glue("M{totals_row2}:M{totals_row2}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET2, dims = glue("N{totals_row2}:N{totals_row2}"), numfmt = "#,##0")
wb$add_numfmt(sheet = SHEET2, dims = glue("O{totals_row2}:O{totals_row2}"), numfmt = "#,##0")

# Footnote row
footnote_row2 <- totals_row2 + 2
footnote_text2 <- glue("Baseline stats: full confirmed 7-day HL cohort ({n_total_confirmed} patients). Pre/Post/Both: {nrow(cohort_with_dates)} patients with known first_hl_dx_date. Pre: DX_DATE <= first_hl_dx_date. Post: DX_DATE > first_hl_dx_date. Both: patient had code pre AND post. C81 pre/post/both left blank (anchor diagnosis).")
wb$add_data(
  sheet = SHEET2,
  x = footnote_text2,
  start_row = footnote_row2, start_col = 1
)
wb$add_font(
  sheet = SHEET2, dims = glue("A{footnote_row2}"),
  name = "Calibri", size = 10, italic = TRUE,
  color = wb_color("FF6B7280")
)
wb$merge_cells(sheet = SHEET2, dims = glue("A{footnote_row2}:O{footnote_row2}"))

# Column widths
wb$set_col_widths(
  sheet = SHEET2, cols = 1:15,
  widths = c(14, 40, 14, 18, 14, 18, 14, 16, 16, 18, 18, 10, 10, 10, 14)
)

# ---------------------------------------------------------------------------
# Save workbook
# ---------------------------------------------------------------------------
wb$save(OUTPUT_TABLE_XLSX)

message(glue("  Wrote {OUTPUT_TABLE_XLSX}"))
message(glue("    Sheet '{SHEET1}': {n_data1} data rows + 1 totals row"))
message(glue("    Sheet '{SHEET2}': {n_data2} data rows + 1 totals row"))

# ==============================================================================
# SECTION 9b: WRITE V2 XLSX OUTPUT ----
# ==============================================================================

message(glue("\nWriting {OUTPUT_TABLE_V2_XLSX}..."))

wb_v2 <- wb_workbook()

# ---------------------------------------------------------------------------
# Sheet 1: "Category Summary" (14 columns A-N)
# ---------------------------------------------------------------------------
SHEET1_V2 <- "Category Summary"
wb_v2$add_worksheet(SHEET1_V2)

# Row 1: Title
wb_v2$add_data(
  sheet = SHEET1_V2, x = "Cancer Summary Table - Pre/Post HL Diagnosis (By Category) - 7-Day Confirmed",
  start_row = 1, start_col = 1
)
wb_v2$add_font(
  sheet = SHEET1_V2, dims = "A1",
  name = "Calibri", size = 16, bold = TRUE,
  color = wb_color(TITLE_FONT_COLOR)
)
wb_v2$merge_cells(sheet = SHEET1_V2, dims = "A1:N1")

# Row 2: Headers
for (i in seq_along(headers1)) {
  wb_v2$add_data(sheet = SHEET1_V2, x = headers1[i], start_row = 2, start_col = i)
}
wb_v2$add_fill(sheet = SHEET1_V2, dims = "A2:N2", color = wb_color(DARK_HEADER_FILL))
wb_v2$add_font(
  sheet = SHEET1_V2, dims = "A2:N2",
  name = "Calibri", size = 11, bold = TRUE,
  color = wb_color(WHITE_FONT)
)

# Freeze pane
wb_v2$freeze_pane(sheet = SHEET1_V2, first_active_row = 3, first_active_col = 1)

# Data rows starting at row 3
data_start1_v2 <- 3
n_data1_v2 <- nrow(category_summary_v2)
data_end1_v2 <- data_start1_v2 + n_data1_v2 - 1

wb_v2$add_data(
  sheet = SHEET1_V2, x = as.data.frame(category_summary_v2),
  start_row = data_start1_v2, col_names = FALSE
)

# Number formatting (matching R/55 pattern + pre/post/both)
wb_v2$add_numfmt(sheet = SHEET1_V2, dims = glue("B{data_start1_v2}:B{data_end1_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET1_V2, dims = glue("C{data_start1_v2}:C{data_end1_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET1_V2, dims = glue("E{data_start1_v2}:E{data_end1_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET1_V2, dims = glue("D{data_start1_v2}:D{data_end1_v2}"), numfmt = "0.0%")
wb_v2$add_numfmt(sheet = SHEET1_V2, dims = glue("F{data_start1_v2}:F{data_end1_v2}"), numfmt = "0.0%")
wb_v2$add_numfmt(sheet = SHEET1_V2, dims = glue("G{data_start1_v2}:G{data_end1_v2}"), numfmt = "0.0")
wb_v2$add_numfmt(sheet = SHEET1_V2, dims = glue("H{data_start1_v2}:H{data_end1_v2}"), numfmt = "0.0")
wb_v2$add_numfmt(sheet = SHEET1_V2, dims = glue("I{data_start1_v2}:I{data_end1_v2}"), numfmt = "0.0")
wb_v2$add_numfmt(sheet = SHEET1_V2, dims = glue("J{data_start1_v2}:J{data_end1_v2}"), numfmt = "0.0")
wb_v2$add_numfmt(sheet = SHEET1_V2, dims = glue("K{data_start1_v2}:K{data_end1_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET1_V2, dims = glue("L{data_start1_v2}:L{data_end1_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET1_V2, dims = glue("M{data_start1_v2}:M{data_end1_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET1_V2, dims = glue("N{data_start1_v2}:N{data_end1_v2}"), numfmt = "#,##0")

# Totals row
totals_row1_v2 <- data_end1_v2 + 1
wb_v2$add_data(
  sheet = SHEET1_V2, x = as.data.frame(totals_category_v2),
  start_row = totals_row1_v2, col_names = FALSE
)
wb_v2$add_fill(
  sheet = SHEET1_V2,
  dims = glue("A{totals_row1_v2}:N{totals_row1_v2}"),
  color = wb_color(TOTALS_FILL)
)
wb_v2$add_font(
  sheet = SHEET1_V2,
  dims = glue("A{totals_row1_v2}:N{totals_row1_v2}"),
  name = "Calibri", size = 11, bold = TRUE,
  color = wb_color(TITLE_FONT_COLOR)
)
wb_v2$add_numfmt(sheet = SHEET1_V2, dims = glue("B{totals_row1_v2}:B{totals_row1_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET1_V2, dims = glue("C{totals_row1_v2}:C{totals_row1_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET1_V2, dims = glue("E{totals_row1_v2}:E{totals_row1_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET1_V2, dims = glue("K{totals_row1_v2}:K{totals_row1_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET1_V2, dims = glue("L{totals_row1_v2}:L{totals_row1_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET1_V2, dims = glue("M{totals_row1_v2}:M{totals_row1_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET1_V2, dims = glue("N{totals_row1_v2}:N{totals_row1_v2}"), numfmt = "#,##0")

# Footnote row
footnote_row1_v2 <- totals_row1_v2 + 2
footnote_text1_v2 <- glue("V2: Filtered to patients with two_or_more_unique_dates_gt_7 == 1. Baseline stats: 7-day confirmed cohort ({v2_n_patients} patients). Pre/Post/Both: {nrow(cohort_with_dates)} patients with known first_hl_dx_date. Pre: DX_DATE <= first_hl_dx_date. Post: DX_DATE > first_hl_dx_date. Both: patient had code pre AND post. C81 pre/post/both left blank (anchor diagnosis).")
wb_v2$add_data(
  sheet = SHEET1_V2,
  x = footnote_text1_v2,
  start_row = footnote_row1_v2, start_col = 1
)
wb_v2$add_font(
  sheet = SHEET1_V2, dims = glue("A{footnote_row1_v2}"),
  name = "Calibri", size = 10, italic = TRUE,
  color = wb_color("FF6B7280")
)
wb_v2$merge_cells(sheet = SHEET1_V2, dims = glue("A{footnote_row1_v2}:N{footnote_row1_v2}"))

# Column widths
wb_v2$set_col_widths(
  sheet = SHEET1_V2, cols = 1:14,
  widths = c(40, 14, 18, 14, 18, 14, 16, 16, 18, 18, 10, 10, 10, 14)
)

# ---------------------------------------------------------------------------
# Sheet 2: "Code Summary" (15 columns A-O)
# ---------------------------------------------------------------------------
SHEET2_V2 <- "Code Summary"
wb_v2$add_worksheet(SHEET2_V2)

# Row 1: Title
wb_v2$add_data(
  sheet = SHEET2_V2, x = "Cancer Summary Table - Pre/Post HL Diagnosis (By ICD-10 Code) - 7-Day Confirmed",
  start_row = 1, start_col = 1
)
wb_v2$add_font(
  sheet = SHEET2_V2, dims = "A1",
  name = "Calibri", size = 16, bold = TRUE,
  color = wb_color(TITLE_FONT_COLOR)
)
wb_v2$merge_cells(sheet = SHEET2_V2, dims = "A1:O1")

# Row 2: Headers
for (i in seq_along(headers2)) {
  wb_v2$add_data(sheet = SHEET2_V2, x = headers2[i], start_row = 2, start_col = i)
}
wb_v2$add_fill(sheet = SHEET2_V2, dims = "A2:O2", color = wb_color(DARK_HEADER_FILL))
wb_v2$add_font(
  sheet = SHEET2_V2, dims = "A2:O2",
  name = "Calibri", size = 11, bold = TRUE,
  color = wb_color(WHITE_FONT)
)

# Freeze pane
wb_v2$freeze_pane(sheet = SHEET2_V2, first_active_row = 3, first_active_col = 1)

# Data rows starting at row 3
data_start2_v2 <- 3
n_data2_v2 <- nrow(code_summary_v2)
data_end2_v2 <- data_start2_v2 + n_data2_v2 - 1

wb_v2$add_data(
  sheet = SHEET2_V2, x = as.data.frame(code_summary_v2),
  start_row = data_start2_v2, col_names = FALSE
)

# Number formatting (matching R/55 pattern + pre/post/both)
wb_v2$add_numfmt(sheet = SHEET2_V2, dims = glue("C{data_start2_v2}:C{data_end2_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET2_V2, dims = glue("D{data_start2_v2}:D{data_end2_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET2_V2, dims = glue("F{data_start2_v2}:F{data_end2_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET2_V2, dims = glue("E{data_start2_v2}:E{data_end2_v2}"), numfmt = "0.0%")
wb_v2$add_numfmt(sheet = SHEET2_V2, dims = glue("G{data_start2_v2}:G{data_end2_v2}"), numfmt = "0.0%")
wb_v2$add_numfmt(sheet = SHEET2_V2, dims = glue("H{data_start2_v2}:H{data_end2_v2}"), numfmt = "0.0")
wb_v2$add_numfmt(sheet = SHEET2_V2, dims = glue("I{data_start2_v2}:I{data_end2_v2}"), numfmt = "0.0")
wb_v2$add_numfmt(sheet = SHEET2_V2, dims = glue("J{data_start2_v2}:J{data_end2_v2}"), numfmt = "0.0")
wb_v2$add_numfmt(sheet = SHEET2_V2, dims = glue("K{data_start2_v2}:K{data_end2_v2}"), numfmt = "0.0")
wb_v2$add_numfmt(sheet = SHEET2_V2, dims = glue("L{data_start2_v2}:L{data_end2_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET2_V2, dims = glue("M{data_start2_v2}:M{data_end2_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET2_V2, dims = glue("N{data_start2_v2}:N{data_end2_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET2_V2, dims = glue("O{data_start2_v2}:O{data_end2_v2}"), numfmt = "#,##0")

# Totals row
totals_row2_v2 <- data_end2_v2 + 1
wb_v2$add_data(
  sheet = SHEET2_V2, x = as.data.frame(totals_code_v2),
  start_row = totals_row2_v2, col_names = FALSE
)
wb_v2$add_fill(
  sheet = SHEET2_V2,
  dims = glue("A{totals_row2_v2}:O{totals_row2_v2}"),
  color = wb_color(TOTALS_FILL)
)
wb_v2$add_font(
  sheet = SHEET2_V2,
  dims = glue("A{totals_row2_v2}:O{totals_row2_v2}"),
  name = "Calibri", size = 11, bold = TRUE,
  color = wb_color(TITLE_FONT_COLOR)
)
wb_v2$add_numfmt(sheet = SHEET2_V2, dims = glue("C{totals_row2_v2}:C{totals_row2_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET2_V2, dims = glue("D{totals_row2_v2}:D{totals_row2_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET2_V2, dims = glue("F{totals_row2_v2}:F{totals_row2_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET2_V2, dims = glue("L{totals_row2_v2}:L{totals_row2_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET2_V2, dims = glue("M{totals_row2_v2}:M{totals_row2_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET2_V2, dims = glue("N{totals_row2_v2}:N{totals_row2_v2}"), numfmt = "#,##0")
wb_v2$add_numfmt(sheet = SHEET2_V2, dims = glue("O{totals_row2_v2}:O{totals_row2_v2}"), numfmt = "#,##0")

# Footnote row
footnote_row2_v2 <- totals_row2_v2 + 2
footnote_text2_v2 <- glue("V2: Filtered to patients with two_or_more_unique_dates_gt_7 == 1. Baseline stats: 7-day confirmed cohort ({v2_n_patients} patients). Pre/Post/Both: {nrow(cohort_with_dates)} patients with known first_hl_dx_date. Pre: DX_DATE <= first_hl_dx_date. Post: DX_DATE > first_hl_dx_date. Both: patient had code pre AND post. C81 pre/post/both left blank (anchor diagnosis).")
wb_v2$add_data(
  sheet = SHEET2_V2,
  x = footnote_text2_v2,
  start_row = footnote_row2_v2, start_col = 1
)
wb_v2$add_font(
  sheet = SHEET2_V2, dims = glue("A{footnote_row2_v2}"),
  name = "Calibri", size = 10, italic = TRUE,
  color = wb_color("FF6B7280")
)
wb_v2$merge_cells(sheet = SHEET2_V2, dims = glue("A{footnote_row2_v2}:O{footnote_row2_v2}"))

# Column widths
wb_v2$set_col_widths(
  sheet = SHEET2_V2, cols = 1:15,
  widths = c(14, 40, 14, 18, 14, 18, 14, 16, 16, 18, 18, 10, 10, 10, 14)
)

# ---------------------------------------------------------------------------
# Save V2 workbook
# ---------------------------------------------------------------------------
wb_v2$save(OUTPUT_TABLE_V2_XLSX)

message(glue("  Wrote {OUTPUT_TABLE_V2_XLSX}"))
message(glue("    Sheet '{SHEET1_V2}': {n_data1_v2} data rows + 1 totals row"))
message(glue("    Sheet '{SHEET2_V2}': {n_data2_v2} data rows + 1 totals row"))

# ==============================================================================
# SECTION 10: WRITE COMPANION CSV ----
# ==============================================================================

message(glue("\nWriting companion CSV to {OUTPUT_CSV}..."))

write.csv(code_summary, OUTPUT_CSV, row.names = FALSE)
message(glue("  Wrote {OUTPUT_CSV} ({nrow(code_summary)} rows)"))

# ==============================================================================
# SECTION 10b: WRITE V2 CSV AND RDS ----
# ==============================================================================

# --- V2 CSV and RDS outputs (Phase 77, per D-09) ---
message(glue("\nWriting V2 companion files..."))
write.csv(code_summary_v2, OUTPUT_CSV_V2, row.names = FALSE)
message(glue("  Wrote {OUTPUT_CSV_V2} ({nrow(code_summary_v2)} rows)"))

# Save V2 RDS (includes both code and category summaries)
v2_output <- list(
  code_summary = code_summary_v2,
  category_summary = category_summary_v2,
  totals_code = totals_code_v2,
  totals_category = totals_category_v2,
  metadata = list(
    filter = "two_or_more_unique_dates_gt_7 == 1",
    total_patients = v2_n_patients,
    created = Sys.time(),
    phase = "77"
  )
)
saveRDS(v2_output, OUTPUT_RDS_V2)
message(glue("  Wrote {OUTPUT_RDS_V2}"))

# ==============================================================================
# SECTION 11: CLEANUP ----
# ==============================================================================

close_pcornet_con()

message("\n=== Phase 77 complete (dual output) ===")
message(glue("  V1 code summary: {nrow(code_summary)} codes, {n_distinct(cancer_summary$ID)} patients"))
message(glue("  V2 code summary: {nrow(code_summary_v2)} codes, {v2_n_patients} patients (7-day filtered)"))
message(glue("  Category summary: {nrow(category_summary)} categories"))
message(glue("  NLPHL diagnostics reported in Section 3"))
