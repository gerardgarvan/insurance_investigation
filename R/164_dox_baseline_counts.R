# ==============================================================================
# 164_dox_baseline_counts.R — Phase 164 Task 2: Baseline doxorubicin counts
# ==============================================================================
# PURPOSE: Before applying the Task 3 drug-name normalization, record raw string
#   counts for doxorubicin / Adriamycin / liposomal variants so Task 5 can
#   reconcile that patient counts are unchanged and merged row-drops are explained.
#
# INPUTS:
#   treatment_episode_detail.rds (from R/26 / R/27) — must PREDATE the Phase 164
#   alias changes (i.e., R/27 and R/26 not yet re-run since 00_config was edited).
#
# OUTPUTS:
#   output/164_dox_baseline_counts.rds  — per-string patient/episode counts
#   output/164_dox_baseline_counts.csv  — same, human-readable
#
# RUN: source("R/164_dox_baseline_counts.R") on HiPerGator BEFORE re-running
#   R/27 -> R/26 with the Phase 164 aliases. Keep the output; Task 5 diffs it.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
})

source("R/00_config.R")

# ── 1. Locate and load treatment episode detail ──────────────────────────────
# CONFIG has no top-level cache_dir; the cache lives at CONFIG$cache$cache_dir.
# Check the likely save locations and use the first that exists.
candidate_paths <- c(
  file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds"),
  file.path(CONFIG$cache$cache_dir,   "treatment_episode_detail.rds"),
  file.path(CONFIG$output_dir,        "treatment_episode_detail.rds")
)
detail_path <- candidate_paths[file.exists(candidate_paths)][1]
if (is.na(detail_path)) {
  stop(glue(
    "Cannot find treatment_episode_detail.rds. Checked:\n  ",
    paste(candidate_paths, collapse = "\n  "),
    "\nConfirm the saveRDS() path in R/26 and add it to candidate_paths."
  ))
}
message(glue("Using: {detail_path} (modified {format(file.mtime(detail_path), '%Y-%m-%d %H:%M')})"))

detail <- readRDS(detail_path)

required_cols <- c("patient_id", "drug_name", "episode_start", "episode_stop")
missing_cols  <- setdiff(required_cols, names(detail))
if (length(missing_cols) > 0) {
  stop(glue("treatment_episode_detail is missing column(s): {paste(missing_cols, collapse = ', ')}"))
}
message(glue("Loaded treatment_episode_detail: {nrow(detail)} rows, {n_distinct(detail$patient_id)} patients"))

# ── 2. Identify doxorubicin-related strings in drug_name ─────────────────────
# The detail RDS has one row per treatment event; drug_name is a single string
# (already resolved via canonicalize_drug_name / DRUG_NAME_ALIASES in R/26).
DOX_PATTERN  <- "adriamycin|doxorubicin|doxil|caelyx|lipodox|liposom"
LIPO_PATTERN <- "doxil|caelyx|lipodox|liposom"

dox_rows <- detail %>%
  filter(!is.na(drug_name) & drug_name != "") %>%
  filter(str_detect(tolower(drug_name), DOX_PATTERN))

message(glue("Doxorubicin-related rows: {nrow(dox_rows)} across {n_distinct(dox_rows$patient_id)} patients"))

# Guard: if every token is already the bare canonical "Doxorubicin", the RDS was
# probably rebuilt after the Phase 164 alias change and is not a true baseline.
non_canonical <- dox_rows %>% filter(drug_name != "Doxorubicin")
if (nrow(dox_rows) > 0 && nrow(non_canonical) == 0) {
  warning(paste(
    "All doxorubicin tokens are already 'Doxorubicin'. The RDS may postdate the",
    "Phase 164 alias change; restore a pre-change copy before trusting this baseline."
  ))
}

# ── 3. Count per raw string ───────────────────────────────────────────────────
per_string <- dox_rows %>%
  group_by(raw_string = drug_name) %>%
  summarise(
    n_rows     = n(),
    n_patients = n_distinct(patient_id),
    n_episodes = n_distinct(paste(patient_id, episode_start, episode_stop)),
    .groups    = "drop"
  ) %>%
  mutate(is_liposomal = str_detect(tolower(raw_string), LIPO_PATTERN)) %>%
  arrange(desc(n_rows))

message("\nPer-string counts:")
print(per_string, n = Inf)

# ── 4. Liposomal breakdown ────────────────────────────────────────────────────
liposomal_rows <- dox_rows %>% filter(str_detect(tolower(drug_name), LIPO_PATTERN))

n_lipo_patients <- n_distinct(liposomal_rows$patient_id)
n_lipo_episodes <- n_distinct(paste(liposomal_rows$patient_id, liposomal_rows$episode_start, liposomal_rows$episode_stop))

# Episode windows with BOTH a liposomal AND a conventional token
# (these collapse to one Doxorubicin bar after mapping).
episode_flags <- dox_rows %>%
  group_by(patient_id, episode_start, episode_stop) %>%
  summarise(
    n_dox_tokens = n_distinct(drug_name),
    has_lipo     = any(str_detect(tolower(drug_name), LIPO_PATTERN)),
    has_conv     = any(!str_detect(tolower(drug_name), LIPO_PATTERN)),
    .groups      = "drop"
  )

both_in_same_window <- episode_flags %>% filter(has_lipo & has_conv)

# Episode windows with 2+ distinct doxorubicin tokens of any kind (brand/generic
# or liposomal/conventional) — the full set of expected merges in Task 5.
multi_token_windows <- episode_flags %>% filter(n_dox_tokens > 1)

message(glue(
  "\nLiposomal rows: {nrow(liposomal_rows)} rows | {n_lipo_patients} patients | {n_lipo_episodes} episodes",
  "\nEpisode windows with BOTH liposomal AND conventional dox: {nrow(both_in_same_window)}",
  "\nEpisode windows with 2+ distinct dox tokens (expected merges): {nrow(multi_token_windows)}"
))

# ── 5. Overall doxorubicin patient / episode counts (any variant) ────────────
n_dox_patients_total <- n_distinct(dox_rows$patient_id)
n_dox_episodes_total <- nrow(episode_flags)
message(glue("Total patients with any doxorubicin variant: {n_dox_patients_total}"))
message(glue("Total episode windows with any doxorubicin variant: {n_dox_episodes_total}"))

# ── 6. Build and save baseline summary ───────────────────────────────────────
baseline <- list(
  source_path           = detail_path,
  source_mtime          = file.mtime(detail_path),
  per_string            = per_string,
  n_dox_patients_total  = n_dox_patients_total,
  n_dox_episodes_total  = n_dox_episodes_total,
  n_lipo_patients       = n_lipo_patients,
  n_lipo_episodes       = n_lipo_episodes,
  n_both_lipo_conv      = nrow(both_in_same_window),
  n_multi_token_windows = nrow(multi_token_windows),
  both_in_same_window   = both_in_same_window,
  multi_token_windows   = multi_token_windows,
  run_date              = Sys.Date()
)

out_dir  <- CONFIG$output_dir
rds_path <- file.path(out_dir, "164_dox_baseline_counts.rds")
csv_path <- file.path(out_dir, "164_dox_baseline_counts.csv")

saveRDS(baseline, rds_path)
write.csv(per_string, csv_path, row.names = FALSE)

message(glue("\nBaseline saved:\n  {rds_path}\n  {csv_path}"))
message("Run this script BEFORE re-running R/27 -> R/26 with the Phase 164 aliases.")
