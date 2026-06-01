# =============================================================================
# Phase 43 Verification: Treatment Duration Sanity Checks
# =============================================================================
# Loads the treatment_durations.rds artifact and runs clinical plausibility
# checks, structural validation, and anomaly detection.
#
# Run after R/25_treatment_durations.R to verify outputs.
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(tidyr)
})

source("R/00_config.R")

RDS_PATH <- file.path(CONFIG$cache$outputs_dir, "treatment_durations.rds")

if (!file.exists(RDS_PATH)) {
  stop(glue("RDS not found: {RDS_PATH}\nRun R/25_treatment_durations.R first."))
}

d <- readRDS(RDS_PATH)

message("=== Phase 43 Verification: Treatment Duration Checks ===\n")

# --- 1. Structure check ---
message("--- 1. Structure ---")
expected_cols <- c("ID", "treatment_type", "first_treatment_date",
                   "last_treatment_date", "overall_span_days",
                   "distinct_treatment_dates", "episode_count")
missing_cols <- setdiff(expected_cols, colnames(d))
if (length(missing_cols) > 0) {
  message(glue("  FAIL: Missing columns: {paste(missing_cols, collapse=', ')}"))
} else {
  message(glue("  OK: All {length(expected_cols)} expected columns present"))
}
message(glue("  Rows: {nrow(d)} | Unique patients: {n_distinct(d$ID)}"))
message(glue("  Types present: {paste(sort(unique(d$treatment_type)), collapse=', ')}"))

expected_types <- c("Chemotherapy", "Immunotherapy", "Radiation", "SCT")
missing_types <- setdiff(expected_types, unique(d$treatment_type))
if (length(missing_types) > 0) {
  message(glue("  WARN: Missing types: {paste(missing_types, collapse=', ')}"))
}

# --- 2. Per-type summary stats ---
message("\n--- 2. Per-Type Summary ---")
type_summary <- d %>%
  group_by(treatment_type) %>%
  summarise(
    n_patients      = n(),
    median_span     = median(overall_span_days),
    q1_span         = quantile(overall_span_days, 0.25),
    q3_span         = quantile(overall_span_days, 0.75),
    min_span        = min(overall_span_days),
    max_span        = max(overall_span_days),
    pct_single_date = round(100 * mean(distinct_treatment_dates == 1), 1),
    median_dates    = median(distinct_treatment_dates),
    max_dates       = max(distinct_treatment_dates),
    median_episodes = median(episode_count),
    max_episodes    = max(episode_count),
    .groups = "drop"
  )

for (i in seq_len(nrow(type_summary))) {
  r <- type_summary[i, ]
  message(glue("\n  {r$treatment_type} (n={r$n_patients}):"))
  message(glue("    Span (days):  median={r$median_span}, IQR=[{r$q1_span}, {r$q3_span}], range=[{r$min_span}, {r$max_span}]"))
  message(glue("    Dates:        median={r$median_dates}, max={r$max_dates}"))
  message(glue("    Episodes:     median={r$median_episodes}, max={r$max_episodes}"))
  message(glue("    Single-date:  {r$pct_single_date}% of patients"))
}

# --- 3. Data quality checks ---
message("\n\n--- 3. Data Quality Checks ---")

# Negative spans
neg_span <- d %>% filter(overall_span_days < 0)
if (nrow(neg_span) > 0) {
  message(glue("  FAIL: {nrow(neg_span)} rows with negative span"))
  print(neg_span %>% select(ID, treatment_type, first_treatment_date,
                            last_treatment_date, overall_span_days))
} else {
  message("  OK: No negative spans")
}

# Last date before first date
date_flip <- d %>% filter(last_treatment_date < first_treatment_date)
if (nrow(date_flip) > 0) {
  message(glue("  FAIL: {nrow(date_flip)} rows where last_date < first_date"))
} else {
  message("  OK: All last_date >= first_date")
}

# Zero-span but multiple dates (impossible)
zero_multi <- d %>% filter(overall_span_days == 0 & distinct_treatment_dates > 1)
if (nrow(zero_multi) > 0) {
  message(glue("  WARN: {nrow(zero_multi)} rows with span=0 but multiple distinct dates"))
  message("        (All dates on same day from different sources?)")
} else {
  message("  OK: No span=0 with multiple dates")
}

# Episodes > distinct dates (impossible)
ep_gt_dates <- d %>% filter(episode_count > distinct_treatment_dates)
if (nrow(ep_gt_dates) > 0) {
  message(glue("  FAIL: {nrow(ep_gt_dates)} rows where episodes > distinct dates"))
} else {
  message("  OK: Episodes <= distinct dates for all rows")
}

# Duplicate patient-type combos
dupes <- d %>% count(ID, treatment_type) %>% filter(n > 1)
if (nrow(dupes) > 0) {
  message(glue("  FAIL: {nrow(dupes)} duplicate patient-type combinations"))
} else {
  message("  OK: One row per patient per type (no duplicates)")
}

# Future dates
future <- d %>% filter(last_treatment_date > Sys.Date())
if (nrow(future) > 0) {
  message(glue("  WARN: {nrow(future)} rows with treatment dates in the future"))
} else {
  message("  OK: No future dates")
}

# Very old dates (before 2000 -- likely sentinel or error)
old <- d %>% filter(first_treatment_date < as.Date("2000-01-01"))
if (nrow(old) > 0) {
  message(glue("  WARN: {nrow(old)} rows with first_treatment_date before 2000"))
  old %>%
    count(treatment_type) %>%
    mutate(msg = glue("        {treatment_type}: {n}")) %>%
    pull(msg) %>%
    walk(message)
} else {
  message("  OK: No dates before 2000")
}

# --- 3b. Pre-2000 date deep dive ---
old_rows <- d %>% filter(first_treatment_date < as.Date("2000-01-01"))
if (nrow(old_rows) > 0) {
  message("\n--- 3b. Pre-2000 Date Deep Dive ---")
  message(glue("  {nrow(old_rows)} patients with first_treatment_date before 2000\n"))

  # By type
  message("  By treatment type:")
  old_rows %>%
    count(treatment_type, sort = TRUE) %>%
    mutate(msg = glue("    {treatment_type}: {n}")) %>%
    pull(msg) %>%
    walk(message)

  # Date distribution
  message("\n  Earliest dates:")
  old_rows %>%
    arrange(first_treatment_date) %>%
    head(20) %>%
    mutate(msg = glue("    {ID}  {treatment_type}  first={first_treatment_date}  last={last_treatment_date}  span={overall_span_days}d  dates={distinct_treatment_dates}  episodes={episode_count}")) %>%
    pull(msg) %>%
    walk(message)

  # Are these sentinel dates (e.g. 1900-01-01, 1800-01-01)?
  message("\n  Date histogram (pre-2000):")
  old_rows %>%
    mutate(decade = paste0(10 * (as.integer(format(first_treatment_date, "%Y")) %/% 10), "s")) %>%
    count(decade, sort = FALSE) %>%
    arrange(decade) %>%
    mutate(msg = glue("    {decade}: {n}")) %>%
    pull(msg) %>%
    walk(message)

  # Do these patients also have post-2000 last_treatment_date? (would mean
  # the pre-2000 date is pulling the span way out)
  bridge <- old_rows %>% filter(last_treatment_date >= as.Date("2000-01-01"))
  message(glue("\n  Bridge patients (first<2000, last>=2000): {nrow(bridge)}"))
  if (nrow(bridge) > 0) {
    message("    These patients have a pre-2000 first date but post-2000 last date,")
    message("    creating artificially inflated spans.")
    bridge %>%
      arrange(first_treatment_date) %>%
      head(10) %>%
      mutate(msg = glue("    {ID}  {treatment_type}  {first_treatment_date} -> {last_treatment_date}  span={overall_span_days}d")) %>%
      pull(msg) %>%
      walk(message)
  }

  # Patients where BOTH first and last are pre-2000
  both_old <- old_rows %>% filter(last_treatment_date < as.Date("2000-01-01"))
  message(glue("\n  Both dates pre-2000: {nrow(both_old)}"))
  if (nrow(both_old) > 0) {
    both_old %>%
      arrange(first_treatment_date) %>%
      head(10) %>%
      mutate(msg = glue("    {ID}  {treatment_type}  {first_treatment_date} -> {last_treatment_date}  span={overall_span_days}d")) %>%
      pull(msg) %>%
      walk(message)
  }

  # Impact on summary stats: what do stats look like WITHOUT pre-2000 dates?
  message("\n  Impact: stats WITH vs WITHOUT pre-2000 patients:")
  for (type in intersect(TREATMENT_TYPES, unique(old_rows$treatment_type))) {
    all_type  <- d %>% filter(treatment_type == type)
    clean_type <- all_type %>% filter(first_treatment_date >= as.Date("2000-01-01"))
    n_removed <- nrow(all_type) - nrow(clean_type)

    s_all   <- all_type %>% summarise(med = median(overall_span_days), mx = max(overall_span_days))
    s_clean <- clean_type %>% summarise(med = median(overall_span_days), mx = max(overall_span_days))

    message(glue("    {type} ({n_removed} removed):"))
    message(glue("      Before: median={s_all$med}, max={s_all$mx}"))
    message(glue("      After:  median={s_clean$med}, max={s_clean$mx}"))
  }
}

# --- 4. Clinical plausibility flags ---
message("\n--- 4. Clinical Plausibility ---")

# Chemo spans > 2 years (unusual for HL)
if ("Chemotherapy" %in% d$treatment_type) {
  long_chemo <- d %>% filter(treatment_type == "Chemotherapy", overall_span_days > 730)
  message(glue("  Chemo > 2 years:    {nrow(long_chemo)} patients"))
}

# Radiation spans > 6 months (unusual)
if ("Radiation" %in% d$treatment_type) {
  long_rad <- d %>% filter(treatment_type == "Radiation", overall_span_days > 180)
  message(glue("  Radiation > 6 months: {nrow(long_rad)} patients"))
}

# SCT spans > 1 year (SCT is typically a single event)
if ("SCT" %in% d$treatment_type) {
  long_sct <- d %>% filter(treatment_type == "SCT", overall_span_days > 365)
  message(glue("  SCT > 1 year:       {nrow(long_sct)} patients"))
}

# Very high episode counts
high_ep <- d %>% filter(episode_count >= 5)
if (nrow(high_ep) > 0) {
  message(glue("  5+ episodes:        {nrow(high_ep)} patient-type rows"))
  high_ep %>%
    count(treatment_type) %>%
    mutate(msg = glue("        {treatment_type}: {n}")) %>%
    pull(msg) %>%
    walk(message)
} else {
  message("  5+ episodes:        0")
}

# --- 5. Cross-type overlap ---
message("\n--- 5. Cross-Type Patient Overlap ---")
patient_types <- d %>%
  distinct(ID, treatment_type) %>%
  count(ID, name = "n_types")

type_dist <- patient_types %>% count(n_types, name = "n_patients")
for (i in seq_len(nrow(type_dist))) {
  message(glue("  {type_dist$n_types[i]} type(s): {type_dist$n_patients[i]} patients"))
}

multi_type <- patient_types %>% filter(n_types > 1)
if (nrow(multi_type) > 0) {
  message(glue("\n  Multi-type patients: {nrow(multi_type)}"))
  # Show which combinations
  combos <- d %>%
    filter(ID %in% multi_type$ID) %>%
    group_by(ID) %>%
    summarise(types = paste(sort(treatment_type), collapse = " + "), .groups = "drop") %>%
    count(types, sort = TRUE)
  for (i in seq_len(min(nrow(combos), 10))) {
    message(glue("    {combos$types[i]}: {combos$n[i]}"))
  }
}

# --- 6. Output file checks ---
message("\n--- 6. Output Files ---")
xlsx_path <- file.path(CONFIG$output_dir, "treatment_durations.xlsx")
png_path  <- file.path(CONFIG$output_dir, "treatment_duration_distributions.png")

# check_file() provided by R/utils_treatment.R (via R/00_config.R)
check_file(RDS_PATH, "RDS artifact")
check_file(xlsx_path, "XLSX report")
check_file(png_path, "Distribution PNG")

message("\n=== Verification Complete ===")
