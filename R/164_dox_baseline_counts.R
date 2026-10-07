# ==============================================================================
# 164_dox_baseline_counts.R — Phase 164 Task 2: Baseline doxorubicin counts
# ==============================================================================
# PURPOSE: Before applying the Task 3 drug-name normalization, record raw string
#   counts for doxorubicin / Adriamycin / liposomal variants so Task 5 can
#   reconcile that patient counts are unchanged and merged row-drops are explained.
#
# INPUTS:
#   treatment_episode_detail.rds (from R/26 / R/27)
#
# OUTPUTS:
#   output/164_dox_baseline_counts.rds  — per-string patient/episode counts
#   output/164_dox_baseline_counts.csv  — same, human-readable
#
# RUN: source("R/164_dox_baseline_counts.R")  on HiPerGator BEFORE applying the
#   Phase 164 alias changes. Keep the output; Task 5 will diff against it.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(purrr)
})

source("R/00_config.R")

# ── 1. Load treatment episode detail ─────────────────────────────────────────
detail_path <- file.path(CONFIG$cache_dir, "treatment_episode_detail.rds")
if (!file.exists(detail_path)) {
  stop(glue("Cannot find treatment_episode_detail.rds at: {detail_path}"))
}
detail <- readRDS(detail_path)
message(glue("Loaded treatment_episode_detail: {nrow(detail)} rows, {n_distinct(detail$ID)} patients"))

# ── 2. Identify doxorubicin-related strings in drug_names ────────────────────
DOX_PATTERN <- "adriamycin|doxorubicin|doxil|caelyx|liposom"

# Each row can have multiple semicolon-separated drug names. Expand them.
drug_rows <- detail %>%
  filter(!is.na(drug_names) & drug_names != "") %>%
  mutate(drug_list = str_split(drug_names, ";\\s*|,\\s*")) %>%
  tidyr::unnest(drug_list) %>%
  mutate(drug_list = str_trim(drug_list)) %>%
  filter(drug_list != "")

dox_rows <- drug_rows %>%
  filter(str_detect(tolower(drug_list), DOX_PATTERN))

message(glue("Doxorubicin-related drug-name tokens: {nrow(dox_rows)} rows across {n_distinct(dox_rows$ID)} patients"))

# ── 3. Count per raw string ───────────────────────────────────────────────────
per_string <- dox_rows %>%
  group_by(raw_string = drug_list) %>%
  summarise(
    n_rows         = n(),
    n_patients     = n_distinct(ID),
    n_episodes     = n_distinct(paste(ID, episode_start, episode_stop)),
    .groups        = "drop"
  ) %>%
  arrange(desc(n_rows))

message("\nPer-string counts:")
print(per_string, n = Inf)

# ── 4. Liposomal breakdown ────────────────────────────────────────────────────
LIPO_PATTERN <- "doxil|caelyx|liposom"
liposomal_rows <- dox_rows %>%
  filter(str_detect(tolower(drug_list), LIPO_PATTERN))

conventional_rows <- dox_rows %>%
  filter(!str_detect(tolower(drug_list), LIPO_PATTERN))

n_lipo_patients    <- n_distinct(liposomal_rows$ID)
n_lipo_episodes    <- n_distinct(paste(liposomal_rows$ID, liposomal_rows$episode_start, liposomal_rows$episode_stop))

# Patients / episodes that have BOTH a liposomal AND a conventional record in
# the same episode window (these are the rows that will collapse after mapping).
both_in_same_window <- dox_rows %>%
  group_by(ID, episode_start, episode_stop) %>%
  summarise(
    has_lipo = any(str_detect(tolower(drug_list), LIPO_PATTERN)),
    has_conv = any(!str_detect(tolower(drug_list), LIPO_PATTERN)),
    .groups  = "drop"
  ) %>%
  filter(has_lipo & has_conv)

message(glue(
  "\nLiposomal rows: {nrow(liposomal_rows)} rows | {n_lipo_patients} patients | {n_lipo_episodes} episodes",
  "\nPatient-episodes with BOTH liposomal AND conventional dox: {nrow(both_in_same_window)}"
))

# ── 5. Overall doxorubicin patient count (any variant) ───────────────────────
n_dox_patients_total <- n_distinct(dox_rows$ID)
message(glue("Total patients with any doxorubicin variant: {n_dox_patients_total}"))

# ── 6. Build and save baseline summary ───────────────────────────────────────
baseline <- list(
  per_string            = per_string,
  n_dox_patients_total  = n_dox_patients_total,
  n_lipo_patients       = n_lipo_patients,
  n_lipo_episodes       = n_lipo_episodes,
  n_both_lipo_conv      = nrow(both_in_same_window),
  both_in_same_window   = both_in_same_window,
  run_date              = Sys.Date()
)

out_dir <- CONFIG$output_dir
rds_path <- file.path(out_dir, "164_dox_baseline_counts.rds")
csv_path <- file.path(out_dir, "164_dox_baseline_counts.csv")

saveRDS(baseline, rds_path)
write.csv(per_string, csv_path, row.names = FALSE)

message(glue("\nBaseline saved:\n  {rds_path}\n  {csv_path}"))
message("Run this script BEFORE applying Phase 164 alias changes.")
