# ==============================================================================
# payer_frequency_from_resolved.R -- Payer frequency from resolved detail
# ==============================================================================
#
# Reads payer_resolved_detail_all.csv (output of 36_tiered_same_day_payer.R)
# and produces a simple frequency table of resolved payer categories.
#
# Output: Prints frequency table to console and writes
#         output/tables/payer_resolved_frequency.csv
#
# Usage: source("R/payer_frequency_from_resolved.R")
# ==============================================================================

library(dplyr)
library(readr)
library(glue)

# --- Load resolved detail ---
input_path <- file.path("output", "tables", "payer_resolved_detail_all.csv")
stopifnot(file.exists(input_path))

resolved <- read_csv(input_path, show_col_types = FALSE)
message(glue("Loaded {nrow(resolved)} patient-date rows from {input_path}"))

# --- Frequency of resolved payer (patient-date level) ---
payer_freq <- resolved %>%
  count(resolved_payer, name = "n_patient_dates") %>%
  arrange(desc(n_patient_dates)) %>%
  mutate(pct = round(100 * n_patient_dates / sum(n_patient_dates), 1))

message("\n--- Resolved Payer Frequency (all patient-dates) ---")
print(payer_freq, n = Inf)

# --- Write output ---
output_path <- file.path("output", "tables", "payer_resolved_frequency.csv")
write_csv(payer_freq, output_path)
message(glue("\nWritten: {output_path}"))
