# ==============================================================================
# 62_tiered_date_level.R -- Tiered payer at the date level
# ==============================================================================
#
# Purpose: Expand treatment episodes to daily rows and assign payer tier per
#   patient+date using 3-tier fill cascade (encounter match, date match, modal fill).
#
# Inputs:
#   - treatment_episodes.rds (episode_start, episode_stop per patient+type)
#   - get_pcornet_table("ENCOUNTER"): payer fields for tiering
#   - get_pcornet_table("ENROLLMENT"): FLM enrollment spans for fallback
#   - AMC_PAYER_LOOKUP from R/00_config.R
#
# Outputs: 3 CSV files in output/tables/:
#   - date_tier_detail.csv (one row per patient per calendar date with fill_method)
#   - date_tier_summary.csv (tier frequency across all dates)
#   - date_tier_summary_by_type.csv (tier frequency per treatment type)
#
# Dependencies: Sources R/00_config.R. Requires treatment_episodes.rds from R/26.
#
# Requirements: Daily-level payer assignment for treatment episode analysis.
#
# Standalone script -- NOT part of the main pipeline sequence.
# ==============================================================================

# ==============================================================================
# SECTION 1: Setup and Tier Configuration ----
# ==============================================================================
# WHY 3-tier fill cascade:
#   - Direct encounter match (fill_method="encounter"): most reliable -- patient had
#     an encounter on that date with a known payer tier
#   - Same-date match (fill_method="filled"): forward/backward fill from nearby
#     encounters within the same treatment episode -- assumes payer continuity
#   - Modal fill (fill_method="enrollment_flm"): for dates with zero encounters,
#     use FLM enrollment spans as fallback (FLM = Florida Medicaid claims)
#   - Cascade ensures every patient-date gets a payer assignment, with explicit
#     fill_method tracking data quality
# WHY daily expansion:
#   - Treatment episodes span multiple days (e.g., 2024-01-01 to 2024-01-31)
#   - Payer may change during the episode (loss of coverage, plan switch, etc.)
#   - Daily granularity enables per-day payer analysis and detects mid-episode transitions

source("R/00_config.R")
library(dplyr)
library(glue)
library(readr)
library(tidyr)

# Load tables if not already loaded (RDS mode)
if (!USE_DUCKDB && !exists("pcornet")) source("R/01_load_pcornet.R")
# DuckDB mode: open connection if needed
if (USE_DUCKDB && !exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}

message(glue("\n{strrep('=', 70)}"))
message("TIERED PAYER -- DATE LEVEL")
message("Per-calendar-date tier assignment within treatment episodes")
message(glue("{strrep('=', 70)}\n"))

# ==========================================================================
# TIER HIERARCHY (same as Phase 45 / script 36, per Amy Crisp framework)
# Lower rank = higher priority.
# ==========================================================================
TIER_MAPPING <- list(
  Medicaid     = 1L,
  Medicare     = 2L,
  Private      = 3L,
  "Other govt" = 4L,
  Other        = 5L,
  "Self-pay"   = 6L,
  Uninsured    = 7L,
  Missing      = 8L
)

# CODE_TO_TIER() provided by R/utils_payer.R (via R/00_config.R)

# ==============================================================================
# SECTION 2: Load Episode Data (Phase 44) ----
# ==============================================================================

message("--- Loading treatment episodes (Phase 44) ---")

episodes_path <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
if (!file.exists(episodes_path)) {
  stop(glue("Missing required file: {episodes_path}\nRun R/44a_treatment_episodes.R first."))
}

episodes <- readRDS(episodes_path)
message(glue("Episodes loaded: {format(nrow(episodes), big.mark=',')} episodes across {n_distinct(episodes$patient_id)} patients"))

# ==============================================================================
# SECTION 3: Expand Episodes to Calendar Days ----
# ==============================================================================

message("\n--- Expanding episodes to calendar days ---")

# For each episode row, generate seq.Date(episode_start, episode_stop, by="day")
date_grid <- episodes %>%
  select(patient_id, treatment_type, episode_number, episode_start, episode_stop) %>%
  mutate(
    n_days = as.integer(episode_stop - episode_start) + 1L
  ) %>%
  uncount(n_days) %>%
  group_by(patient_id, treatment_type, episode_number) %>%
  mutate(date = episode_start + row_number() - 1L) %>%
  ungroup() %>%
  select(patient_id, treatment_type, episode_number, date)

expected_days <- sum(as.integer(episodes$episode_stop - episodes$episode_start) + 1L)
message(glue("Expanded to {format(nrow(date_grid), big.mark=',')} patient-dates (expected: {format(expected_days, big.mark=',')})"))

if (nrow(date_grid) != expected_days) {
  warning(glue("Row count mismatch! Got {nrow(date_grid)}, expected {expected_days}"))
}

# ==============================================================================
# SECTION 4: Tier ENCOUNTER Table (reuse Phase 45 logic verbatim) ----
# ==============================================================================

message("\n--- Loading and tiering ENCOUNTER table ---")

enc_raw <- get_pcornet_table("ENCOUNTER") %>% materialize()
message(glue("Total encounters loaded: {format(nrow(enc_raw), big.mark=',')}"))

enc <- enc_raw %>%
  mutate(
    PAYER_TYPE_PRIMARY   = as.character(PAYER_TYPE_PRIMARY),
    PAYER_TYPE_SECONDARY = as.character(PAYER_TYPE_SECONDARY),
    SOURCE               = as.character(SOURCE),
    # Effective payer: primary if valid, else secondary, else NA
    effective_payer = case_when(
      !is.na(PAYER_TYPE_PRIMARY) & nchar(trimws(PAYER_TYPE_PRIMARY)) > 0 &
        !PAYER_TYPE_PRIMARY %in% PAYER_MAPPING$sentinel_values ~ PAYER_TYPE_PRIMARY,
      !is.na(PAYER_TYPE_SECONDARY) & nchar(trimws(PAYER_TYPE_SECONDARY)) > 0 &
        !PAYER_TYPE_SECONDARY %in% PAYER_MAPPING$sentinel_values ~ PAYER_TYPE_SECONDARY,
      TRUE ~ NA_character_
    ),
    # Map to AMC 8-category: direct lookup + prefix fallback
    payer_category = {
      looked_up <- AMC_PAYER_LOOKUP[effective_payer]
      prefix_cat <- case_when(
        startsWith(effective_payer, "1") ~ "Medicare",
        startsWith(effective_payer, "2") ~ "Medicaid",
        startsWith(effective_payer, "5") | startsWith(effective_payer, "6") ~ "Private",
        startsWith(effective_payer, "3") | startsWith(effective_payer, "4") ~ "Other govt",
        startsWith(effective_payer, "7") ~ "Private",
        startsWith(effective_payer, "8") ~ "Uninsured",
        startsWith(effective_payer, "9") ~ "Other",
        TRUE ~ "Other"
      )
      result <- if_else(!is.na(looked_up), looked_up, prefix_cat)
      if_else(is.na(effective_payer), "Missing", result)
    },
    # Map to tier
    tier = CODE_TO_TIER(payer_category),
    # Override with special codes 93/14
    tier = coalesce(
      case_when(
        PAYER_TYPE_PRIMARY %in% c("93", "14") ~ "Medicaid",
        PAYER_TYPE_SECONDARY %in% c("93", "14") ~ "Medicaid",
        TRUE ~ NA_character_
      ),
      tier
    ),
    # FLM source override
    tier = if_else(SOURCE == "FLM" & !is.na(SOURCE), "Medicaid", tier),
    # Safety net
    tier = if_else(is.na(tier), "Missing", tier),
    tier_rank = unlist(TIER_MAPPING[tier]),
    tier_rank = if_else(is.na(tier_rank), 8L, tier_rank)
  )

# Dedup to best tier per patient+date (lowest tier_rank wins)
enc_date_tier <- enc %>%
  filter(!is.na(ADMIT_DATE)) %>%
  mutate(date = as.Date(ADMIT_DATE)) %>%
  group_by(ID, date) %>%
  slice_min(tier_rank, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(patient_id = ID, date, enc_tier = tier, enc_tier_rank = tier_rank)

message(glue("Encounter-date tiers: {format(nrow(enc_date_tier), big.mark=',')} unique patient-dates"))

# ==============================================================================
# SECTION 5: Left-Join Encounter Tiers to Expanded Dates ----
# ==============================================================================

message("\n--- Joining encounter tiers to date grid ---")

date_joined <- date_grid %>%
  left_join(enc_date_tier, by = c("patient_id", "date"))

n_matched <- sum(!is.na(date_joined$enc_tier))
n_total <- nrow(date_joined)
message(glue("Direct encounter match: {format(n_matched, big.mark=',')} / {format(n_total, big.mark=',')} dates ({round(100 * n_matched / n_total, 1)}%)"))

# Transfer encounter tier columns
date_joined <- date_joined %>%
  mutate(
    tier = enc_tier,
    tier_rank = enc_tier_rank,
    fill_method = if_else(!is.na(enc_tier), "encounter", NA_character_)
  ) %>%
  select(-enc_tier, -enc_tier_rank)

# ==============================================================================
# SECTION 6: Forward/Backward Fill Within Episodes ----
# ==============================================================================

message("\n--- Forward/backward fill within episodes ---")

date_filled <- date_joined %>%
  group_by(patient_id, treatment_type, episode_number) %>%
  arrange(date, .by_group = TRUE) %>%
  # Fill tier and tier_rank down then up within each episode
  fill(tier, tier_rank, .direction = "downup") %>%
  ungroup() %>%
  # Mark filled rows

  mutate(
    fill_method = case_when(
      !is.na(fill_method)           ~ fill_method,    # already "encounter"
      !is.na(tier)                  ~ "filled",        # was filled by tidyr::fill
      TRUE                          ~ "no_data"        # still NA after fill
    )
  )

n_filled <- sum(date_filled$fill_method == "filled", na.rm = TRUE)
n_no_data <- sum(date_filled$fill_method == "no_data", na.rm = TRUE)
message(glue("After fill: {format(n_filled, big.mark=',')} dates filled from nearby encounters"))
message(glue("Remaining gaps: {format(n_no_data, big.mark=',')} dates with no encounter data in episode"))

# ==============================================================================
# SECTION 7: Enrollment FLM Fallback for Remaining NAs ----
# ==============================================================================

if (n_no_data > 0) {
  message("\n--- Enrollment FLM fallback for remaining gaps ---")

  enr_raw <- get_pcornet_table("ENROLLMENT") %>% materialize()

  # Identify FLM enrollment spans per patient
  enr_flm <- enr_raw %>%
    filter(SOURCE == "FLM") %>%
    mutate(
      enr_start = as.Date(ENR_START_DATE),
      enr_end   = as.Date(ENR_END_DATE)
    ) %>%
    filter(!is.na(enr_start)) %>%
    select(patient_id = ID, enr_start, enr_end)

  # For no_data rows, check if patient had FLM enrollment covering that date
  no_data_rows <- date_filled %>%
    filter(fill_method == "no_data") %>%
    select(patient_id, treatment_type, episode_number, date)

  # Join to FLM enrollment spans and check date coverage
  flm_matches <- no_data_rows %>%
    inner_join(enr_flm, by = "patient_id", relationship = "many-to-many") %>%
    filter(date >= enr_start & (date <= enr_end | is.na(enr_end))) %>%
    distinct(patient_id, treatment_type, episode_number, date) %>%
    mutate(flm_covered = TRUE)

  n_flm <- nrow(flm_matches)
  message(glue("FLM enrollment covers {format(n_flm, big.mark=',')} of {format(n_no_data, big.mark=',')} gap dates"))

  # Apply FLM fallback: Medicaid for FLM-covered, Missing for rest
  date_filled <- date_filled %>%
    left_join(flm_matches, by = c("patient_id", "treatment_type", "episode_number", "date")) %>%
    mutate(
      tier = case_when(
        fill_method != "no_data"         ~ tier,
        flm_covered & !is.na(flm_covered) ~ "Medicaid",
        TRUE                             ~ "Missing"
      ),
      tier_rank = case_when(
        fill_method != "no_data"         ~ tier_rank,
        flm_covered & !is.na(flm_covered) ~ 1L,
        TRUE                             ~ 8L
      ),
      fill_method = case_when(
        fill_method != "no_data"         ~ fill_method,
        flm_covered & !is.na(flm_covered) ~ "enrollment_flm",
        TRUE                             ~ "no_data"
      )
    ) %>%
    select(-flm_covered)

  n_flm_assigned <- sum(date_filled$fill_method == "enrollment_flm", na.rm = TRUE)
  n_still_missing <- sum(date_filled$fill_method == "no_data", na.rm = TRUE)
  message(glue("Assigned via FLM enrollment: {format(n_flm_assigned, big.mark=',')}"))
  message(glue("Still missing: {format(n_still_missing, big.mark=',')}"))

  # Final safety net: ensure no NAs remain
  date_filled <- date_filled %>%
    mutate(
      tier = if_else(is.na(tier), "Missing", tier),
      tier_rank = if_else(is.na(tier_rank), 8L, tier_rank),
      fill_method = if_else(is.na(fill_method), "no_data", fill_method)
    )
} else {
  message("\n--- No gaps to fill via enrollment fallback ---")
}

# ==============================================================================
# SECTION 8: Write Outputs ----
# ==============================================================================

output_dir <- file.path(CONFIG$output_dir, "tables")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# --- Detail CSV: one row per patient-date ---
detail <- date_filled %>%
  select(patient_id, treatment_type, episode_number, date, tier, tier_rank, fill_method) %>%
  arrange(patient_id, treatment_type, episode_number, date)

detail_path <- file.path(output_dir, "date_tier_detail.csv")
write_csv(detail, detail_path)
message(glue("\nWritten: date_tier_detail.csv ({format(nrow(detail), big.mark=',')} rows)"))

# --- Summary CSV: tier frequency across all dates ---
tier_order <- names(TIER_MAPPING)

summary_all <- detail %>%
  count(tier, name = "n_patient_dates") %>%
  mutate(pct = round(100 * n_patient_dates / sum(n_patient_dates), 2)) %>%
  arrange(match(tier, tier_order))

summary_path <- file.path(output_dir, "date_tier_summary.csv")
write_csv(summary_all, summary_path)
message(glue("Written: date_tier_summary.csv ({nrow(summary_all)} rows)"))

# --- Summary by treatment type ---
summary_by_type <- detail %>%
  group_by(treatment_type) %>%
  count(tier, name = "n_patient_dates") %>%
  mutate(pct = round(100 * n_patient_dates / sum(n_patient_dates), 2)) %>%
  ungroup() %>%
  arrange(treatment_type, match(tier, tier_order))

summary_type_path <- file.path(output_dir, "date_tier_summary_by_type.csv")
write_csv(summary_by_type, summary_type_path)
message(glue("Written: date_tier_summary_by_type.csv ({nrow(summary_by_type)} rows)"))

# ==============================================================================
# SECTION 9: Console Summary ----
# ==============================================================================

message(glue("\n{strrep('=', 70)}"))
message("TIERED PAYER (DATE LEVEL) -- SUMMARY")
message(glue("{strrep('=', 70)}"))

message(glue("\nTotal patient-dates: {format(nrow(detail), big.mark=',')}"))
message(glue("Unique patients: {format(n_distinct(detail$patient_id), big.mark=',')}"))
message(glue("Treatment types: {paste(unique(detail$treatment_type), collapse=', ')}"))

# Fill method distribution
message("\nFill method distribution:")
fill_dist <- detail %>%
  count(fill_method, name = "n") %>%
  mutate(pct = round(100 * n / sum(n), 1)) %>%
  arrange(desc(n))
for (i in seq_len(nrow(fill_dist))) {
  row <- fill_dist[i, ]
  message(glue("  {format(row$fill_method, width=15)} : {format(row$n, big.mark=',', width=10)} ({row$pct}%)"))
}

# Tier distribution
message("\nTier distribution (all dates):")
for (i in seq_len(nrow(summary_all))) {
  row <- summary_all[i, ]
  message(glue("  {format(row$tier, width=10)} : {format(row$n_patient_dates, big.mark=',', width=10)} ({row$pct}%)"))
}

message(glue("\nCSV files written to {output_dir}/:"))
message("  date_tier_detail.csv            (one row per patient per calendar date)")
message("  date_tier_summary.csv           (tier frequency across all dates)")
message("  date_tier_summary_by_type.csv   (tier frequency per treatment type)")

message(glue("\n{strrep('=', 70)}"))
message("END OF TIERED PAYER (DATE LEVEL)")
message(glue("{strrep('=', 70)}"))

# ==============================================================================
# Script end
# ==============================================================================
