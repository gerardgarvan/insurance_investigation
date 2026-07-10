# ==============================================================================
# 104_gantt_entire_history.R -- Gantt Entire History Projection (quick-260710-i1e)
# ==============================================================================
# Purpose:      Project output/gantt_lifespan.csv into gantt_entire_history.csv
#               (6 renamed columns). Re-derive the 7-day cancer column as the
#               UNION directly from output/gantt_episodes.csv (the source of
#               truth), asserting equality against lifespan's own column
#               (non-fatal). Five columns are direct passthroughs/renames from
#               the lifespan CSV; the sixth (cancer_7day_confirmed) is rebuilt
#               from the episodes-level data so it can never be a stale copy.
#
#               Blank cells stay blank on both read (na.strings="") and write
#               (na=""), never becoming the literal string "NA".
#
# Inputs:       output/gantt_lifespan.csv  (produced by R/101_gantt_lifespan_collapse.R)
#               output/gantt_episodes.csv  (produced by R/52_gantt_v2_export.R)
#
# Outputs:      output/gantt_entire_history.csv  (6 columns:
#                 patient_id, treatment_type, treatment_start, treatment_stop,
#                 drug_names, cancer_7day_confirmed)
#
# Dependencies: R/00_config.R (CONFIG$output_dir)
#               tidyverse ecosystem: dplyr, stringr, glue
#
# Requirements: quick task 260710-i1e
#
# Usage:        Rscript R/104_gantt_entire_history.R
#               source("R/104_gantt_entire_history.R")
#
# Note:         HiPerGator-only for RUNTIME (reads the real gantt CSVs produced
#               there). Structurally testable locally via grep/file-read.
#               Run R/52 and R/101 first to produce the input CSVs.
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP AND LIBRARIES ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
})

source("R/00_config.R")

message("=== quick-260710-i1e: Gantt Entire History Projection ===\n")


# ==============================================================================
# SECTION 2: CONSTANTS AND INPUT VALIDATION ----
# ==============================================================================

INPUT_LIFESPAN <- file.path(CONFIG$output_dir, "gantt_lifespan.csv")
INPUT_EPISODES <- file.path(CONFIG$output_dir, "gantt_episodes.csv")

# OUTPUT PATH: under output/ alongside the other Gantt exports.
OUTPUT <- file.path(CONFIG$output_dir, "gantt_entire_history.csv")

# Defensive: fail fast if either upstream Gantt export is missing.
stopifnot(file.exists(INPUT_LIFESPAN), file.exists(INPUT_EPISODES))

message(glue("  Inputs validated:\n    {INPUT_LIFESPAN}\n    {INPUT_EPISODES}\n"))

# Locked 6-column output order (with the 3 renames applied downstream).
ENTIRE_HISTORY_SCHEMA <- c(
  "patient_id", "treatment_type",
  "treatment_start", "treatment_stop",
  "drug_names", "cancer_7day_confirmed"
)

message(glue("  ENTIRE_HISTORY_SCHEMA defined: {length(ENTIRE_HISTORY_SCHEMA)} columns\n"))


# ==============================================================================
# SECTION 3: HELPER FUNCTIONS ----
# ==============================================================================

# clean_multi_value() + union_field() -- copied VERBATIM from
# R/101_gantt_lifespan_collapse.R (SECTION 3, lines 106-131). Standalone copies
# are documented here because R/101 does not export them. Behavior: dedup, drop
# blanks and literal "NA" tokens, sort, join with sep_out.
clean_multi_value <- function(field_str, sep_in = ",", sep_out = ";") {
  if (is.na(field_str) || field_str == "" || field_str == "NA") {
    return("")
  }

  values <- str_split(field_str, sep_in)[[1]]
  values <- str_trim(values)
  values <- values[values != "" & values != "NA" & !is.na(values)]
  values <- sort(unique(values))

  if (length(values) == 0) {
    return("")
  }
  paste(values, collapse = sep_out)
}

union_field <- function(x) {
  clean_multi_value(paste(x, collapse = ";"), sep_in = ";", sep_out = ";")
}


# ==============================================================================
# SECTION 4: LOAD INPUTS (blank-safe) ----
# ==============================================================================

message("--- Loading input CSVs (blank-safe: na.strings=\"\") ---")

# Read as character with na.strings="" so blank cells arrive as NA (never the
# string "NA") and no date/numeric coercion surprises occur.
lifespan_raw <- read.csv(INPUT_LIFESPAN, colClasses = "character", na.strings = "")
episodes_raw <- read.csv(INPUT_EPISODES, colClasses = "character", na.strings = "")

message(glue(
  "  gantt_lifespan.csv: {format(nrow(lifespan_raw), big.mark = ',')} rows, ",
  "{ncol(lifespan_raw)} columns"
))
message(glue(
  "  gantt_episodes.csv: {format(nrow(episodes_raw), big.mark = ',')} rows, ",
  "{ncol(episodes_raw)} columns"
))


# ==============================================================================
# SECTION 5: RE-DERIVE THE 7-DAY CANCER UNION FROM EPISODES ----
# ==============================================================================

# The 7-day cancer flag is the SOURCE OF TRUTH from the episodes-level data.
# Exclude pseudo-rows exactly like R/101 SECTION 5, then union
# episode_dx_7day_confirmed per (patient_id, treatment_type).
message("\n--- Re-deriving 7-day cancer union from gantt_episodes.csv ---")

cancer_union <- episodes_raw %>%
  filter(!treatment_type %in% c("Death", "HL Diagnosis")) %>%
  group_by(patient_id, treatment_type) %>%
  summarise(cancer_7day_confirmed = union_field(episode_dx_7day_confirmed), .groups = "drop")

message(glue(
  "  Episodes-derived union: {format(nrow(cancer_union), big.mark = ',')} ",
  "(patient_id x treatment_type) groups"
))


# ==============================================================================
# SECTION 5b: ASSERT episodes-derived union == lifespan's own column (NON-FATAL) ----
# ==============================================================================

# Build lifespan's own per-(patient_id, treatment_type) 7-day value through the
# SAME clean_multi_value pass (via union_field over its single value) so the
# comparison is apples-to-apples. Lifespan is already one row per
# (patient_id, treatment_type), but normalizing ensures identical token
# ordering/dedup before comparing.
lifespan_7day <- lifespan_raw %>%
  filter(!treatment_type %in% c("Death", "HL Diagnosis")) %>%
  group_by(patient_id, treatment_type) %>%
  summarise(lifespan_side = union_field(episode_dx_7day_confirmed), .groups = "drop")

mismatch_check <- cancer_union %>%
  rename(episodes_side = cancer_7day_confirmed) %>%
  full_join(lifespan_7day, by = c("patient_id", "treatment_type")) %>%
  mutate(
    # Treat NA-vs-"" as equal by coalescing both sides to "" first.
    episodes_side = ifelse(is.na(episodes_side), "", episodes_side),
    lifespan_side = ifelse(is.na(lifespan_side), "", lifespan_side)
  )

mismatches <- mismatch_check %>%
  filter(lifespan_side != episodes_side)

n_mismatch <- nrow(mismatches)

message(glue("  7-day union mismatch count (expect 0): {n_mismatch}"))

if (n_mismatch > 0) {
  # NON-FATAL: warn and show the first 10, but proceed using the EPISODES-derived
  # cancer_union as the source of truth (do NOT stop()).
  warning(glue(
    "[R/104] 7-day cancer union mismatch between episodes and lifespan: ",
    "{n_mismatch} (patient_id x treatment_type) group(s). ",
    "Proceeding with the EPISODES-derived union as source of truth."
  ))
  print(head(mismatches, 10))
}


# ==============================================================================
# SECTION 6: PROJECT LIFESPAN + JOIN + WRITE ----
# ==============================================================================

message("\n--- Projecting lifespan to 6 columns + joining episodes-derived union ---")

# Project lifespan to 5 columns with the 3 renames:
#   treatment_start <- episode_start, treatment_stop <- episode_stop.
#   patient_id / treatment_type / drug_names unchanged.
lifespan_proj <- lifespan_raw %>%
  transmute(
    patient_id,
    treatment_type,
    treatment_start = episode_start,
    treatment_stop  = episode_stop,
    drug_names
  )

# Attach the RE-DERIVED cancer_7day_confirmed (rename of episode_dx_7day_confirmed)
# from the episodes-derived union.
entire_history <- lifespan_proj %>%
  left_join(cancer_union, by = c("patient_id", "treatment_type")) %>%
  select(all_of(ENTIRE_HISTORY_SCHEMA))

# Schema verify (mirror R/101): exact column names and order.
stopifnot(identical(colnames(entire_history), ENTIRE_HISTORY_SCHEMA))

message("  Schema verification: PASSED (6 columns, exact order)")

# NA cleanup on EVERY column (all character here): blank cells stay blank and
# never render as the literal string "NA".
entire_history <- entire_history %>%
  mutate(across(everything(), ~ ifelse(is.na(.) | . == "NA", "", .)))

# Write blank-safe. Only OUTPUT is written -- the input CSVs are READ-ONLY.
write.csv(entire_history, OUTPUT, row.names = FALSE, na = "")

message(glue("  Wrote: {OUTPUT} ({format(nrow(entire_history), big.mark = ',')} rows)"))


# ==============================================================================
# SECTION 7: FINAL SUMMARY ----
# ==============================================================================

n_rows     <- nrow(entire_history)
n_patients <- n_distinct(entire_history$patient_id)
n_tx_types <- n_distinct(entire_history$treatment_type)

message(glue("\n--- Entire history export summary ---"))
message(glue("  Rows written:            {format(n_rows, big.mark = ',')}"))
message(glue("  Unique patients:         {format(n_patients, big.mark = ',')}"))
message(glue("  Unique treatment types:  {format(n_tx_types, big.mark = ',')}"))
message(glue("  7-day union mismatches:  {n_mismatch} (expect 0)"))
message(glue("  Output: {OUTPUT}"))

message("\nDone. (quick-260710-i1e)")
