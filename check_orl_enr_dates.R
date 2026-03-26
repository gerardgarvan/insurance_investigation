# ==============================================================================
# check_orl_enr_dates.R -- Check if all ORL enrollment records have impossible dates
# ==============================================================================
# Questions:
#   1. Do ALL ORL enrollment records have impossible (out-of-range) ENR dates?
#   2. If so, are they all the same date?
# ==============================================================================

source("R/01_load_pcornet.R")

library(dplyr)
library(glue)

enr <- pcornet$ENROLLMENT

# Date range used by the pipeline (from 01_load_pcornet.R validation)
date_range_min <- as.Date("1900-01-01")
date_range_max <- as.Date("2025-03-31")

# --- 1. ORL enrollment overview ---
orl_enr <- enr %>% filter(SOURCE == "ORL")
message(glue("\n=== ORL Enrollment Overview ==="))
message(glue("Total ORL enrollment rows: {nrow(orl_enr)}"))
message(glue("Unique ORL patients: {n_distinct(orl_enr$ID)}"))

# --- 2. Check ENR_START_DATE ---
message(glue("\n--- ENR_START_DATE ---"))
message(glue("  NA: {sum(is.na(orl_enr$ENR_START_DATE))}"))
message(glue("  Before {date_range_min}: {sum(orl_enr$ENR_START_DATE < date_range_min, na.rm = TRUE)}"))
message(glue("  After {date_range_max}: {sum(orl_enr$ENR_START_DATE > date_range_max, na.rm = TRUE)}"))
message(glue("  In range: {sum(orl_enr$ENR_START_DATE >= date_range_min & orl_enr$ENR_START_DATE <= date_range_max, na.rm = TRUE)}"))
message(glue("  Min: {min(orl_enr$ENR_START_DATE, na.rm = TRUE)}"))
message(glue("  Max: {max(orl_enr$ENR_START_DATE, na.rm = TRUE)}"))

# Distinct start dates
start_dates <- sort(unique(orl_enr$ENR_START_DATE[!is.na(orl_enr$ENR_START_DATE)]))
message(glue("  Distinct values ({length(start_dates)}): {paste(head(start_dates, 20), collapse = ', ')}"))

# --- 3. Check ENR_END_DATE ---
message(glue("\n--- ENR_END_DATE ---"))
message(glue("  NA: {sum(is.na(orl_enr$ENR_END_DATE))}"))
message(glue("  Before {date_range_min}: {sum(orl_enr$ENR_END_DATE < date_range_min, na.rm = TRUE)}"))
message(glue("  After {date_range_max}: {sum(orl_enr$ENR_END_DATE > date_range_max, na.rm = TRUE)}"))
message(glue("  In range: {sum(orl_enr$ENR_END_DATE >= date_range_min & orl_enr$ENR_END_DATE <= date_range_max, na.rm = TRUE)}"))
message(glue("  Min: {min(orl_enr$ENR_END_DATE, na.rm = TRUE)}"))
message(glue("  Max: {max(orl_enr$ENR_END_DATE, na.rm = TRUE)}"))

# Distinct end dates
end_dates <- sort(unique(orl_enr$ENR_END_DATE[!is.na(orl_enr$ENR_END_DATE)]))
message(glue("  Distinct values ({length(end_dates)}): {paste(head(end_dates, 20), collapse = ', ')}"))

# --- 4. Are the impossible dates all the same? ---
impossible_end <- orl_enr %>% filter(ENR_END_DATE > date_range_max)
if (nrow(impossible_end) > 0) {
  message(glue("\n--- Impossible ENR_END_DATE (>{date_range_max}) ---"))
  message(glue("  Count: {nrow(impossible_end)}"))
  message(glue("  Distinct dates: {n_distinct(impossible_end$ENR_END_DATE)}"))
  impossible_freq <- impossible_end %>% count(ENR_END_DATE, sort = TRUE)
  for (i in seq_len(nrow(impossible_freq))) {
    message(glue("    {impossible_freq$ENR_END_DATE[i]}: {impossible_freq$n[i]} rows"))
  }
}

impossible_start <- orl_enr %>% filter(ENR_START_DATE < date_range_min | ENR_START_DATE > date_range_max)
if (nrow(impossible_start) > 0) {
  message(glue("\n--- Impossible ENR_START_DATE ---"))
  message(glue("  Count: {nrow(impossible_start)}"))
  impossible_start_freq <- impossible_start %>% count(ENR_START_DATE, sort = TRUE)
  for (i in seq_len(nrow(impossible_start_freq))) {
    message(glue("    {impossible_start_freq$ENR_START_DATE[i]}: {impossible_start_freq$n[i]} rows"))
  }
}

# --- 5. Compare ORL vs other sources ---
message(glue("\n--- Impossible ENR_END_DATE by SOURCE ---"))
impossible_by_source <- enr %>%
  filter(ENR_END_DATE > date_range_max) %>%
  count(SOURCE, sort = TRUE)
for (i in seq_len(nrow(impossible_by_source))) {
  message(glue("  {impossible_by_source$SOURCE[i]}: {impossible_by_source$n[i]} rows"))
}

# Total enrollment rows per source (for context)
message(glue("\n--- Total enrollment rows by SOURCE ---"))
total_by_source <- enr %>% count(SOURCE, sort = TRUE)
for (i in seq_len(nrow(total_by_source))) {
  pct_impossible <- 0
  imp_n <- impossible_by_source %>% filter(SOURCE == total_by_source$SOURCE[i]) %>% pull(n)
  if (length(imp_n) > 0) pct_impossible <- round(100 * imp_n / total_by_source$n[i], 1)
  message(glue("  {total_by_source$SOURCE[i]}: {total_by_source$n[i]} total, {pct_impossible}% impossible"))
}
