# ==============================================================================
# 85_test_episodes.R -- Treatment episode verification
# ==============================================================================
#
# Purpose:
#   Verification script: structural, data quality, historical flag, and clinical
#   plausibility checks for treatment_episodes.rds output. WHY historical flag
#   validation: Dates before 2000 are flagged as potentially erroneous -- PCORnet
#   data starts around 2010 for most sites.
#
# Inputs:
#   - cache/outputs/treatment_episodes.rds from R/26
#
# Outputs:
#   - Console output (PASS/FAIL per check)
#
# Dependencies:
#   - R/00_config.R, R/26_treatment_episodes.R
#
# Requirements:
#   - (verification script; no specific requirements)
#
# Usage:
#   source("R/85_test_episodes.R")
#
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
})

source("R/00_config.R")
n# ==============================================================================
# SECTION 1: SETUP ----
# ==============================================================================

RDS_PATH <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")

if (!file.exists(RDS_PATH)) {
  stop(glue("RDS not found: {RDS_PATH}\nRun R/26_treatment_episodes.R first."))
}

d <- readRDS(RDS_PATH)

message("=== Phase 44 Verification: Treatment Episode Checks ===\n")
n# ==============================================================================
# SECTION 2: EXECUTION ----
# ==============================================================================

# --- 1. STRUCTURE CHECK ---
message("--- 1. Structure ---")
expected_cols <- c("patient_id", "treatment_type", "episode_number",
                   "episode_start", "episode_stop", "episode_length_days",
                   "distinct_dates_in_episode", "historical_flag")
missing_cols <- setdiff(expected_cols, colnames(d))
if (length(missing_cols) > 0) {
  message(glue("  FAIL: Missing columns: {paste(missing_cols, collapse=', ')}"))
} else {
  message(glue("  OK: All {length(expected_cols)} expected columns present"))
}

message(glue("  Rows: {nrow(d)} | Unique patients: {n_distinct(d$patient_id)}"))
message(glue("  Types present: {paste(sort(unique(d$treatment_type)), collapse=', ')}"))

expected_types <- c("Chemotherapy", "Immunotherapy", "Radiation", "SCT")
missing_types <- setdiff(expected_types, unique(d$treatment_type))
if (length(missing_types) > 0) {
  message(glue("  WARN: Missing types: {paste(missing_types, collapse=', ')}"))
}

# Column type verification
message("\n  Column types:")
message(glue("    patient_id: {class(d$patient_id)[1]}"))
message(glue("    episode_number: {class(d$episode_number)[1]}"))
message(glue("    episode_start: {class(d$episode_start)[1]}"))
message(glue("    episode_stop: {class(d$episode_stop)[1]}"))
message(glue("    episode_length_days: {class(d$episode_length_days)[1]}"))
message(glue("    distinct_dates_in_episode: {class(d$distinct_dates_in_episode)[1]}"))
message(glue("    historical_flag: {class(d$historical_flag)[1]}"))

if (class(d$patient_id)[1] != "character") {
  message("  FAIL: patient_id should be character")
}
if (!class(d$episode_start)[1] %in% c("Date")) {
  message("  FAIL: episode_start should be Date")
}
if (!class(d$episode_stop)[1] %in% c("Date")) {
  message("  FAIL: episode_stop should be Date")
}
if (class(d$historical_flag)[1] != "logical") {
  message("  FAIL: historical_flag should be logical")
}


# --- 2. PER-TYPE SUMMARY STATS ---
message("\n--- 2. Per-Type Summary ---")
type_summary <- d %>%
  group_by(treatment_type) %>%
  summarise(
    n_patients = n_distinct(patient_id),
    n_episodes = n(),
    n_historical = sum(historical_flag),
    pct_historical = round(100 * mean(historical_flag), 1),
    median_length = median(episode_length_days),
    max_length = max(episode_length_days),
    median_dates = median(distinct_dates_in_episode),
    max_dates = max(distinct_dates_in_episode),
    max_episode_number = max(episode_number),
    .groups = "drop"
  )

for (i in seq_len(nrow(type_summary))) {
  r <- type_summary[i, ]
  message(glue("\n  {r$treatment_type} (patients={r$n_patients}, episodes={r$n_episodes}):"))
  message(glue("    Historical:       {r$n_historical} episodes ({r$pct_historical}%)"))
  message(glue("    Episode length:   median={r$median_length}, max={r$max_length} days"))
  message(glue("    Dates/episode:    median={r$median_dates}, max={r$max_dates}"))
  message(glue("    Max episode num:  {r$max_episode_number}"))
}


# --- 3. DATA QUALITY CHECKS ---
message("\n\n--- 3. Data Quality Checks ---")

# Negative episode_length_days
neg_length <- d %>% filter(episode_length_days < 0)
if (nrow(neg_length) > 0) {
  message(glue("  FAIL: {nrow(neg_length)} rows with negative episode_length_days"))
  print(head(neg_length))
} else {
  message("  OK: No negative episode_length_days")
}

# episode_stop before episode_start
date_flip <- d %>% filter(episode_stop < episode_start)
if (nrow(date_flip) > 0) {
  message(glue("  FAIL: {nrow(date_flip)} rows where episode_stop < episode_start"))
} else {
  message("  OK: All episode_stop >= episode_start")
}

# Zero length but multiple dates
zero_multi <- d %>% filter(episode_length_days == 0 & distinct_dates_in_episode > 1)
if (nrow(zero_multi) > 0) {
  message(glue("  WARN: {nrow(zero_multi)} rows with length=0 but multiple distinct dates"))
  message("        (All dates on same day from different sources?)")
} else {
  message("  OK: No length=0 with multiple dates")
}

# Episode numbering contiguity check
message("\n  Checking episode numbering contiguity per patient per type...")
contiguity <- d %>%
  group_by(patient_id, treatment_type) %>%
  summarise(n_ep = n(), max_ep = max(episode_number), .groups = "drop") %>%
  filter(n_ep != max_ep)

if (nrow(contiguity) > 0) {
  message(glue("  FAIL: {nrow(contiguity)} patient-type combos have non-contiguous episode numbers"))
  print(head(contiguity, 10))
} else {
  message("  OK: Episode numbering is contiguous (n_episodes == max(episode_number))")
}

# Duplicate patient-type-episode combos
dupes <- d %>% count(patient_id, treatment_type, episode_number) %>% filter(n > 1)
if (nrow(dupes) > 0) {
  message(glue("  FAIL: {nrow(dupes)} duplicate patient-type-episode combinations"))
  print(head(dupes))
} else {
  message("  OK: No duplicate patient-type-episode combinations")
}

# Future dates
future <- d %>% filter(episode_stop > Sys.Date())
if (nrow(future) > 0) {
  message(glue("  WARN: {nrow(future)} rows with episode_stop in the future"))
} else {
  message("  OK: No future dates")
}

# historical_flag consistency check
cutoff <- as.Date("2012-01-01")
flag_inconsistent <- d %>%
  mutate(expected_flag = episode_stop < cutoff) %>%
  filter(historical_flag != expected_flag)

if (nrow(flag_inconsistent) > 0) {
  message(glue("  FAIL: {nrow(flag_inconsistent)} rows with inconsistent historical_flag"))
  message("        (historical_flag doesn't match episode_stop < 2012-01-01)")
  print(head(flag_inconsistent))
} else {
  message("  OK: historical_flag consistent with episode_stop < 2012-01-01")
}


# --- 4. HISTORICAL DATE ANALYSIS ---
message("\n--- 4. Historical Date Analysis ---")

historical_episodes <- d %>% filter(historical_flag)

if (nrow(historical_episodes) == 0) {
  message("  No historical episodes found (all data >= 2012-01-01)")
} else {
  message(glue("  {nrow(historical_episodes)} historical episodes found\n"))

  # Count by type
  message("  By treatment type:")
  historical_episodes %>%
    count(treatment_type, sort = TRUE) %>%
    mutate(msg = glue("    {treatment_type}: {n}")) %>%
    pull(msg) %>%
    purrr::walk(message)

  # Decade distribution
  message("\n  Decade distribution:")
  historical_episodes %>%
    mutate(decade = 10 * (as.integer(format(episode_start, "%Y")) %/% 10)) %>%
    count(decade) %>%
    arrange(decade) %>%
    mutate(msg = glue("    {decade}s: {n}")) %>%
    pull(msg) %>%
    purrr::walk(message)

  # Verify D-04: single-date historical episodes have start=stop and length=0
  single_date_hist <- historical_episodes %>%
    filter(distinct_dates_in_episode == 1)

  if (nrow(single_date_hist) > 0) {
    d04_violations <- single_date_hist %>%
      filter(episode_start != episode_stop | episode_length_days != 0)

    if (nrow(d04_violations) > 0) {
      message(glue("\n  FAIL: {nrow(d04_violations)} single-date historical episodes violate D-04"))
      message("        (Should have start=stop and length=0)")
      print(head(d04_violations))
    } else {
      message("\n  OK: Single-date historical episodes have start=stop and length=0 (D-04)")
    }
  }

  # Check for "bridge episodes" (start < 2012 AND stop >= 2012)
  bridge <- historical_episodes %>%
    filter(episode_start < cutoff & episode_stop >= cutoff)

  if (nrow(bridge) > 0) {
    message(glue("\n  WARN: {nrow(bridge)} bridge episodes span 2012 cutoff"))
    message("        (episode_start < 2012-01-01 but episode_stop >= 2012-01-01)")
    message("        These should be rare with 90-day gap splitting.")
    print(head(bridge))
  } else {
    message("\n  OK: No bridge episodes spanning 2012 cutoff")
  }
}


# --- 5. CROSS-REFERENCE WITH PHASE 43 ---
message("\n--- 5. Cross-Reference with Phase 43 ---")

RDS_43_PATH <- file.path(CONFIG$cache$outputs_dir, "treatment_durations.rds")
if (!file.exists(RDS_43_PATH)) {
  message("  SKIP: Phase 43 RDS not found (expected path: {RDS_43_PATH})")
} else {
  d43 <- readRDS(RDS_43_PATH)

  # Per-patient episode counts from Phase 44
  ep_counts_44 <- d %>%
    group_by(patient_id, treatment_type) %>%
    summarise(n_episodes_44 = n(), .groups = "drop")

  # Per-patient episode counts from Phase 43
  ep_counts_43 <- d43 %>%
    select(patient_id = ID, treatment_type, episode_count)

  # Merge and check
  merged <- left_join(ep_counts_44, ep_counts_43, by = c("patient_id", "treatment_type"))

  # Handle NAs (patients in 44 but not in 43, shouldn't happen)
  merged <- merged %>%
    mutate(episode_count = replace_na(episode_count, 0L))

  mismatches <- merged %>% filter(n_episodes_44 != episode_count)

  if (nrow(mismatches) > 0) {
    message(glue("  FAIL: {nrow(mismatches)} patient-type combos have mismatched episode counts"))
    message("        (Phase 44 episode count != Phase 43 episode_count)")
    print(head(mismatches, 20))
  } else {
    message("  OK: Phase 44 episode counts match Phase 43 episode_count field")
  }
}


# --- 6. OUTPUT FILE CHECKS ---
message("\n--- 6. Output Files ---")
xlsx_path <- file.path(CONFIG$output_dir, "treatment_episodes.xlsx")
csv_paths <- c(
  file.path(CONFIG$output_dir, "chemotherapy_episodes.csv"),
  file.path(CONFIG$output_dir, "radiation_episodes.csv"),
  file.path(CONFIG$output_dir, "sct_episodes.csv"),
  file.path(CONFIG$output_dir, "immunotherapy_episodes.csv")
)

# check_file() provided by R/utils_treatment.R (via R/00_config.R)

check_file(RDS_PATH, "RDS artifact (treatment_episodes.rds)")
check_file(xlsx_path, "XLSX report (treatment_episodes.xlsx)")
for (csv_path in csv_paths) {
  check_file(csv_path, basename(csv_path))
}


message("\n=== Phase 44 Verification Complete ===")
n# ==============================================================================
# SECTION 2: EXECUTION ----
# ==============================================================================
