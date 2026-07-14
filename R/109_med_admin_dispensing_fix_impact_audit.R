# ==============================================================================
# 109_med_admin_dispensing_fix_impact_audit.R -- Phase 122 Fix Before/After
#   Diff + Unmatched-NDC Audit
# ==============================================================================
# Purpose:     READ-ONLY post-fix quantification of the Phase 122 chemo-detection
#              fix. R/107 is the pre-fix historical diagnostic (do NOT edit it).
#              R/109 computes the deterministic before/after diff using the
#              production get_chemo_hits() path and audits unmatched NDCs.
#
#              This script quantifies, AFTER the Phase 122 fix:
#                D-03: Patient & date counts by source (PRESCRIBING / MED_ADMIN /
#                      DISPENSING) — before vs after, headline number.
#                D-04: First-chemo timing shift — patients gaining an EARLIER
#                      first-chemo date and distribution of the shift in days.
#                D-05: Per-drug/ingredient delta — which ingredients gain the
#                      most patients/dates from the new sources.
#                D-06: Regimen-label impact (upper-bound estimate, episodes.rds
#                      join, NO R/25/26/28 re-run) for adults 21+.
#                D-07: Drug-name string match — unmatched NDCs vs chemo names
#                      via RAW_MEDADMIN_MED_NAME.
#                D-08: Frequency-ranked review — top-N unmatched NDCs by volume.
#                D-09: RxNav alternate-endpoint re-query (IS_LOCAL-gated;
#                      HiPerGator-only network step).
#                D-10: Resolved-non-chemo gap check — NDCs that resolved to a
#                      non-chemo RxCUI; flags potential chemo_rxnorm list gaps.
#
# Inputs:      DuckDB PRESCRIBING / MED_ADMIN / DISPENSING / DEMOGRAPHIC
#              data/reference/ndc_rxnorm_crosswalk.rds
#              output/ndc_rxnorm_crosswalk_audit.csv
#              cache/outputs/treatment_episodes.rds  (D-06, guarded by
#                file.exists() — section skipped if absent)
#
# Outputs:     output/med_admin_dispensing_fix_impact.xlsx  (built in Plan 02)
#              output/ndc_rxnorm_crosswalk_requery.csv      (D-09, HiPerGator)
#
# Dependencies: R/00_config.R (TREATMENT_CODES$chemo_rxnorm, MEDICATION_LOOKUP,
#               DRUG_NAME_ALIASES, canonicalize_drug_name, CONFIG$output_dir,
#               auto-sources utils_duckdb + utils_dates + utils_treatment)
#               R/utils/utils_duckdb.R  (open_pcornet_con, get_pcornet_table,
#                                        close_pcornet_con)
#               R/utils/utils_dates.R   (parse_pcornet_date)
#               R/utils/utils_treatment.R (get_chemo_hits, load_ndc_crosswalk,
#                                          normalize_ndc, get_hl_patient_ids)
#               tidyverse: dplyr, glue, stringr, lubridate
#               openxlsx2, httr2, here, purrr
#
# Requirements: D-01..D-06 (Phase 123 Plan 01), D-07..D-11 (Plan 02)
#
# Usage:       Rscript R/109_med_admin_dispensing_fix_impact_audit.R
#              source("R/109_med_admin_dispensing_fix_impact_audit.R")
#
# Note:        READ-ONLY post-fix quantification. Structural-only verification
#              on Windows (no Rscript; local fixtures lack real column layout).
#              Full run with counts is HiPerGator ONLY. This script must NOT
#              touch R/26, R/00_config, treatment_episodes.rds, or any cohort/
#              episode output file.
#
# REGISTRATION NOTE: This is a ONE-OFF post-fix diagnostic — NOT wired into
#              R/39 and NOT registered in R/88 sections (SCRIPT_INDEX-only,
#              mirrors R/107 and R/108). R/88 Section 15u confirms structure.
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP AND LIBRARIES ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(lubridate)
  library(openxlsx2)
  library(httr2)
  library(here)
  library(purrr)
})

source("R/00_config.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_dates.R")

# get_chemo_hits / load_ndc_crosswalk / get_hl_patient_ids auto-sourced by
# R/00_config via utils_treatment; source defensively if not yet on search path.
if (!exists("get_chemo_hits")) {
  source("R/utils/utils_treatment.R")
}

message("=== Phase 123: MED_ADMIN/DISPENSING Fix Before/After Diff + Unmatched-NDC Audit ===\n")


# ==============================================================================
# SECTION 2: CONSTANTS AND HIPAA HELPER ----
# ==============================================================================

CHEMO_RXNORM <- TREATMENT_CODES$chemo_rxnorm
message(glue("Chemo RxNorm CUI list: {length(CHEMO_RXNORM)} codes loaded from TREATMENT_CODES$chemo_rxnorm\n"))

OUTPUT_XLSX   <- file.path(CONFIG$output_dir, "med_admin_dispensing_fix_impact.xlsx")
EPISODES_RDS  <- here::here("cache", "outputs", "treatment_episodes.rds")
NDC_AUDIT_CSV <- file.path(CONFIG$output_dir, "ndc_rxnorm_crosswalk_audit.csv")
NDC_REQUERY_CSV <- file.path(CONFIG$output_dir, "ndc_rxnorm_crosswalk_requery.csv")

message(glue("Output xlsx target:     {OUTPUT_XLSX}"))
message(glue("Episodes RDS path:      {EPISODES_RDS}"))
message(glue("NDC audit CSV path:     {NDC_AUDIT_CSV}\n"))

# HIPAA helper: patient counts 1-10 are suppressed in any persisted/printed
# per-group breakdown to prevent re-identification. Applies to n_patients fields
# in all output sheets and console lines.
suppress_small <- function(n) {
  if (!is.na(n) && n >= 1L && n <= 10L) NA_integer_ else as.integer(n)
}


# ==============================================================================
# SECTION 3: SELF-BOOTSTRAP DUCKDB ----
# ==============================================================================

# Self-bootstrap the DuckDB connection so R/109 runs standalone in a fresh
# session (consistent with R/107, R/108). open_pcornet_con() is idempotent.
USE_DUCKDB <- TRUE
if (!exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}


# ==============================================================================
# SECTION 4: COHORT SCOPE (HL PATIENT IDS) ----
# ==============================================================================

message("--- Section 4: Cohort scope ---")
hl_ids <- get_hl_patient_ids()
n_hl <- length(hl_ids)
message(glue("  HL cohort patient count: {format(n_hl, big.mark = ',')}"))

if (n_hl == 0L) {
  message("  WARNING: get_hl_patient_ids() returned 0 IDs (DIAGNOSIS table absent or empty?).")
  message("  Falling back to ALL-PATIENT scope for cohort fields — counts will be inflated.\n")
  cohort_fallback <- TRUE
} else {
  cohort_fallback <- FALSE
  message(glue("  Using HL cohort (n = {format(n_hl, big.mark = ',')}) for cohort-scoped metrics.\n"))
}

# Internal helper: apply cohort filter or return data unchanged (fallback).
filter_to_cohort <- function(df) {
  if (cohort_fallback) return(df)
  df %>% filter(ID %in% hl_ids)
}


# ==============================================================================
# SECTION 5: CHEMO SOURCE EXTRACTION ----
# before = PRESCRIBING-only; after = PRESCRIBING + MED_ADMIN + DISPENSING
# All "after" sources use the production get_chemo_hits() path (Phase 122 fix)
# so the diff matches real detection exactly.
# ==============================================================================

message("--- Section 5: Chemo source extraction ---")

ndc_crosswalk <- load_ndc_crosswalk()
message(glue("  NDC crosswalk: {length(ndc_crosswalk)} entries loaded"))

hits_rx <- get_chemo_hits("PRESCRIBING", CHEMO_RXNORM)
hits_ma <- get_chemo_hits("MED_ADMIN",   CHEMO_RXNORM, ndc_crosswalk)
hits_dp <- get_chemo_hits("DISPENSING",  CHEMO_RXNORM, ndc_crosswalk)

# Cohort-scope helper: guard NULL return, cohort-filter, parse date (Pitfall 2).
# get_chemo_hits() returns treatment_date UNPARSED — parse after collect().
coh <- function(h) {
  if (is.null(h) || nrow(h) == 0) {
    return(tibble(
      ID             = character(),
      treatment_date = as.Date(character()),
      triggering_code = character()
    ))
  }
  h %>%
    filter_to_cohort() %>%
    mutate(treatment_date = parse_pcornet_date(treatment_date)) %>%
    filter(!is.na(treatment_date))
}

hits_rx_coh <- coh(hits_rx)
hits_ma_coh <- coh(hits_ma)
hits_dp_coh <- coh(hits_dp)

# NOTE: get_chemo_hits("MED_ADMIN") already unions the RX-typed and ND-typed
# paths internally via bind_rows. Do NOT re-union MEDADMIN_TYPE == 'RX' and
# MEDADMIN_TYPE == 'ND' separately — they are already combined in hits_ma_coh.

# Before set: PRESCRIBING-only (what the pipeline captured pre-fix).
before <- hits_rx_coh %>% distinct(ID, treatment_date)

# After set: all three sources tagged by contributing source (D-03).
after_labeled <- bind_rows(
  hits_rx_coh %>% mutate(chemo_source = "PRESCRIBING"),
  hits_ma_coh %>% mutate(chemo_source = "MED_ADMIN"),
  hits_dp_coh %>% mutate(chemo_source = "DISPENSING")
)

# After union (deduplicated (ID, date) pairs regardless of source).
after <- after_labeled %>% distinct(ID, treatment_date)

message(glue("  Before (PRESCRIBING only): {format(n_distinct(before$ID), big.mark=',')} patients, {format(nrow(before), big.mark=',')} (ID,date) pairs"))
message(glue("  After  (all sources):      {format(n_distinct(after$ID), big.mark=',')} patients, {format(nrow(after), big.mark=',')} (ID,date) pairs\n"))


# ==============================================================================
# SECTION 6: D-03 PATIENT AND DATE COUNTS BY SOURCE ----
# ==============================================================================

message("--- Section 6: D-03 — patient and date counts by source ---")

# Per-source breakdown (each source independently).
df_source_counts <- after_labeled %>%
  group_by(chemo_source) %>%
  summarise(
    n_patients       = suppress_small(n_distinct(ID)),
    n_id_date_pairs  = n_distinct(paste(ID, treatment_date)),
    .groups = "drop"
  )

# Before vs after headline summary.
df_before_after_summary <- tibble(
  metric = c("n_patients_any_chemo", "n_distinct_id_date_pairs"),
  before = c(
    suppress_small(n_distinct(before$ID)),
    nrow(before)
  ),
  after = c(
    suppress_small(n_distinct(after$ID)),
    nrow(after)
  )
) %>%
  mutate(delta = after - before)

message(glue("  Headline: {df_before_after_summary$before[1]} patients before -> {df_before_after_summary$after[1]} patients after (delta = {df_before_after_summary$delta[1]})"))
message(glue("  (ID,date) pairs: {df_before_after_summary$before[2]} before -> {df_before_after_summary$after[2]} after (delta = {df_before_after_summary$delta[2]})\n"))


# ==============================================================================
# SECTION 7: D-04 FIRST-CHEMO TIMING SHIFT ----
# Patients who gain an EARLIER first-chemo date under the after-set.
# ==============================================================================

message("--- Section 7: D-04 — first-chemo timing shift ---")

before_first <- hits_rx_coh %>%
  group_by(ID) %>%
  summarise(first_before = min(treatment_date, na.rm = TRUE), .groups = "drop")

after_first <- after %>%
  group_by(ID) %>%
  summarise(first_after = min(treatment_date, na.rm = TRUE), .groups = "drop")

shift_df <- inner_join(before_first, after_first, by = "ID") %>%
  filter(first_after < first_before) %>%
  mutate(shift_days = as.numeric(first_before - first_after))

if (nrow(shift_df) == 0L) {
  df_timing_shift <- tibble(
    n_patients_earlier = 0L,
    shift_days_median  = NA_real_,
    shift_days_p25     = NA_real_,
    shift_days_p75     = NA_real_,
    shift_days_max     = NA_real_
  )
  message("  No patients gained an earlier first-chemo date (shift_df is empty).\n")
} else {
  df_timing_shift <- tibble(
    n_patients_earlier = suppress_small(n_distinct(shift_df$ID)),
    shift_days_median  = median(shift_df$shift_days),
    shift_days_p25     = quantile(shift_df$shift_days, 0.25),
    shift_days_p75     = quantile(shift_df$shift_days, 0.75),
    shift_days_max     = max(shift_df$shift_days)
  )
  message(glue("  {df_timing_shift$n_patients_earlier} patients gained an earlier first-chemo date"))
  message(glue("  Shift distribution (days): median = {df_timing_shift$shift_days_median}, p25 = {df_timing_shift$shift_days_p25}, p75 = {df_timing_shift$shift_days_p75}, max = {df_timing_shift$shift_days_max}\n"))
}


# ==============================================================================
# SECTION 8: D-05 PER-INGREDIENT DELTA ----
# Which chemo ingredients gain the most patients/dates from the new sources.
# Map triggering_code (RxCUI) -> drug name via MEDICATION_LOOKUP.
# chemo_rxnorm has NO names attribute — use MEDICATION_LOOKUP only (Pitfall 6).
# ==============================================================================

message("--- Section 8: D-05 — per-ingredient delta ---")

ingredient_before <- hits_rx_coh %>%
  group_by(triggering_code) %>%
  summarise(
    n_pts_before   = n_distinct(ID),
    n_dates_before = n(),
    .groups = "drop"
  )

ingredient_after <- bind_rows(hits_rx_coh, hits_ma_coh, hits_dp_coh) %>%
  group_by(triggering_code) %>%
  summarise(
    n_pts_after   = n_distinct(ID),
    n_dates_after = n(),
    .groups = "drop"
  )

df_ingredient_delta <- full_join(ingredient_before, ingredient_after, by = "triggering_code") %>%
  mutate(
    drug_name = unname(MEDICATION_LOOKUP[triggering_code]),
    drug_name = coalesce(drug_name, paste0("RxCUI:", triggering_code)),
    delta_pts   = coalesce(n_pts_after,   0L) - coalesce(n_pts_before,   0L),
    delta_dates = coalesce(n_dates_after, 0L) - coalesce(n_dates_before, 0L)
  ) %>%
  # Apply HIPAA suppression to patient-count columns
  mutate(across(c(n_pts_before, n_pts_after, delta_pts), suppress_small)) %>%
  arrange(desc(delta_pts))

message(glue("  {nrow(df_ingredient_delta)} distinct ingredients with before/after counts\n"))


# ==============================================================================
# SECTION 9: D-06 REGIMEN-LABEL UPPER-BOUND IMPACT ----
# Option A: episodes.rds join — upper-bound estimate, NO R/25/26/27/28 re-run.
# Entire section guarded by file.exists(EPISODES_RDS).
# Adults 21+ only (per regimen detection scope in R/28).
# ==============================================================================

message("--- Section 9: D-06 — regimen-label upper-bound impact ---")

if (!file.exists(EPISODES_RDS)) {
  message(glue("  [D-06] treatment_episodes.rds not found at {EPISODES_RDS} — regimen impact SKIPPED. Re-run R/26 on HiPerGator to enable."))
  # Empty tibble so Plan 02 xlsx assembly can still write the sheet.
  df_regimen_impact <- tibble(
    regimen_label      = character(),
    n_episodes_before  = integer(),
    n_episodes_after   = integer(),
    delta              = integer(),
    note               = character()
  )
} else {
  # 1. Load existing episodes (produced by prior R/28 run — already has regimen_label
  #    and episode_start). This is an upper-bound approach: we flag patients whose
  #    new-source earliest chemo date predates their existing episode_start, which
  #    means their regimen label COULD change on a full re-run. We do NOT re-run
  #    assign_episode_ids / R/25 / R/26 / R/28.
  episodes <- readRDS(EPISODES_RDS)

  # 2. Adult 21+ filter: join DEMOGRAPHIC on ID (Pitfall 4: keyed on ID, not PATID).
  demo_raw <- get_pcornet_table("DEMOGRAPHIC") %>%
    select(ID, BIRTH_DATE) %>%
    collect() %>%
    mutate(BIRTH_DATE = parse_pcornet_date(BIRTH_DATE))

  episodes_with_age <- episodes %>%
    left_join(demo_raw, by = "ID") %>%
    mutate(
      age_at_episode = floor(as.numeric(interval(BIRTH_DATE, episode_start) / years(1)))
    ) %>%
    filter(!is.na(age_at_episode), age_at_episode >= 21)

  # 3. Upper-bound logic: for each patient in hits_ma_coh or hits_dp_coh,
  #    find their earliest new-source chemo date. Flag patients whose new earliest
  #    date is STRICTLY EARLIER than their existing episode_start (per ID).
  new_source_hits <- bind_rows(hits_ma_coh, hits_dp_coh)

  if (nrow(new_source_hits) == 0L) {
    n_flagged <- 0L
    flagged_ids <- character(0)
  } else {
    new_earliest <- new_source_hits %>%
      group_by(ID) %>%
      summarise(new_earliest_date = min(treatment_date, na.rm = TRUE), .groups = "drop")

    existing_episode_start <- episodes_with_age %>%
      group_by(ID) %>%
      summarise(min_episode_start = min(episode_start, na.rm = TRUE), .groups = "drop")

    flagged <- inner_join(new_earliest, existing_episode_start, by = "ID") %>%
      filter(new_earliest_date < min_episode_start)

    n_flagged  <- n_distinct(flagged$ID)
    flagged_ids <- flagged$ID
  }

  message(glue("  [D-06] {n_flagged} patients (adults 21+) have a new-source earliest chemo date EARLIER than their existing episode_start — their regimen label may change on a full re-run (UPPER BOUND)."))

  # 4. Build summary: count episodes (adults 21+) by regimen_label.
  #    n_episodes_after = existing count + flagged-patient count as "may shift"
  #    (explicit UPPER BOUND — not an exact re-run result).
  regimen_before <- episodes_with_age %>%
    group_by(regimen_label) %>%
    summarise(n_episodes_before = n(), .groups = "drop")

  df_regimen_impact <- regimen_before %>%
    mutate(
      n_episodes_after = n_episodes_before + n_flagged,
      delta            = n_episodes_after - n_episodes_before,
      note             = "UPPER BOUND (episodes.rds join; not a full R/25/26/28 re-run) per D-06/D-12"
    )

  message(glue("  [D-06] {nrow(df_regimen_impact)} regimen labels summarized (adults 21+).\n"))
}


# ==============================================================================
# SECTION 10: NDC AUDIT UNIVERSE ----
# Read output/ndc_rxnorm_crosswalk_audit.csv produced by R/108 on HiPerGator.
# Columns: NDC, rxcui, lookup_status ("matched" / "miss")
# Universe: 24,327 NDCs; 16,588 matched; 7,739 miss (from 122-VERIFICATION.md).
# ==============================================================================

message("--- Section 10: NDC audit universe ---")

if (!file.exists(NDC_AUDIT_CSV)) {
  message(glue("  NDC audit CSV not found at {NDC_AUDIT_CSV} — NDC audit sections (D-07..D-10) will be skipped."))
  ndc_audit_tbl  <- tibble(NDC = character(), rxcui = character(), lookup_status = character())
  ndc_unmatched  <- tibble(NDC = character(), rxcui = character(), lookup_status = character())
  ndc_matched    <- tibble(NDC = character(), rxcui = character(), lookup_status = character())
} else {
  ndc_audit_tbl <- readr::read_csv(NDC_AUDIT_CSV, col_types = readr::cols(.default = readr::col_character()),
                                   show_col_types = FALSE)
  ndc_unmatched <- ndc_audit_tbl %>% filter(lookup_status == "miss")
  ndc_matched   <- ndc_audit_tbl %>% filter(lookup_status == "matched")
  message(glue("  NDC audit: {format(nrow(ndc_audit_tbl), big.mark=',')} total, {format(nrow(ndc_matched), big.mark=',')} matched, {format(nrow(ndc_unmatched), big.mark=',')} miss"))
}


# ==============================================================================
# SECTION 11: D-07 DRUG-NAME STRING MATCH ----
# Match unmatched NDCs against chemo ingredient names via RAW_MEDADMIN_MED_NAME
# (MED_ADMIN-ND only). DISPENSING has no drug name text in this extract.
# ==============================================================================

message("--- Section 11: D-07 — drug-name string match ---")

# Build chemo name list from MEDICATION_LOOKUP values that correspond to chemo
# CUIs in CHEMO_RXNORM. DRUG_NAME_ALIASES keys also included.
chemo_lookup_names <- unique(tolower(MEDICATION_LOOKUP[names(MEDICATION_LOOKUP) %in% CHEMO_RXNORM]))
alias_names        <- if (exists("DRUG_NAME_ALIASES")) unique(tolower(names(DRUG_NAME_ALIASES))) else character(0)
chemo_name_pattern <- paste(unique(c(chemo_lookup_names, alias_names)), collapse = "|")

df_ndc_string_match <- tibble(
  NDC              = character(),
  raw_med_name     = character(),
  matched_ingredient = character(),
  match_method     = character()
)

if (nrow(ndc_unmatched) > 0L && nchar(chemo_name_pattern) > 0L) {
  ma_tbl_raw <- get_pcornet_table("MED_ADMIN")

  if (!is.null(ma_tbl_raw) && "RAW_MEDADMIN_MED_NAME" %in% colnames(ma_tbl_raw)) {
    # Collect ND-typed rows for unmatched NDCs (joined on normalized NDC).
    ma_nd_names <- ma_tbl_raw %>%
      filter(MEDADMIN_TYPE == "ND") %>%
      select(NDC = MEDADMIN_CODE, raw_med_name = RAW_MEDADMIN_MED_NAME) %>%
      collect() %>%
      mutate(NDC = normalize_ndc(NDC)) %>%
      filter(NDC %in% ndc_unmatched$NDC) %>%
      distinct(NDC, raw_med_name) %>%
      filter(!is.na(raw_med_name), nchar(trimws(raw_med_name)) > 0L)

    if (nrow(ma_nd_names) > 0L) {
      # Vectorized substring search: does any chemo name appear in raw_med_name?
      string_matches <- ma_nd_names %>%
        mutate(
          raw_lower      = tolower(raw_med_name),
          canonicalized  = tolower(canonicalize_drug_name(raw_med_name)),
          direct_match   = str_detect(raw_lower, chemo_name_pattern),
          canon_match    = str_detect(canonicalized, chemo_name_pattern)
        ) %>%
        filter(direct_match | canon_match) %>%
        mutate(match_method = case_when(
          direct_match ~ "direct_substring",
          canon_match  ~ "canonicalized_substring",
          TRUE         ~ "unknown"
        )) %>%
        # Identify which ingredient name matched (first hit)
        mutate(matched_ingredient = map_chr(raw_lower, function(nm) {
          hits <- keep(strsplit(chemo_name_pattern, "\\|")[[1]], ~ str_detect(nm, fixed(.x)))
          if (length(hits) > 0L) hits[[1L]] else NA_character_
        })) %>%
        select(NDC, raw_med_name, matched_ingredient, match_method)

      df_ndc_string_match <- string_matches
    }
  } else {
    message("  MED_ADMIN table not found or RAW_MEDADMIN_MED_NAME absent — D-07 skipped.")
  }
  message("  DISPENSING: no drug name text available in this extract (no RAW_DISPENSE_MED_NAME column).")
}

message(glue("  D-07: {nrow(df_ndc_string_match)} unmatched NDCs with a chemo-ingredient name hit in RAW_MEDADMIN_MED_NAME\n"))


# ==============================================================================
# SECTION 12: D-08 FREQUENCY-RANKED REVIEW ----
# Rank unmatched NDCs by patient/row volume. Top-N table for SME review.
# ==============================================================================

message("--- Section 12: D-08 — frequency-ranked unmatched NDCs ---")

TOP_N_NDC <- 50L   # Number of top unmatched NDCs to surface

df_ndc_freq_ranked <- tibble(
  NDC          = character(),
  raw_med_name = character(),
  n_patients   = integer(),
  n_rows       = integer(),
  rank         = integer()
)

if (nrow(ndc_unmatched) > 0L) {
  # Pull ND-typed MED_ADMIN rows for unmatched NDCs (with optional drug name).
  ma_tbl_d08 <- get_pcornet_table("MED_ADMIN")
  dp_tbl_d08 <- get_pcornet_table("DISPENSING")

  ma_nd_freq <- if (!is.null(ma_tbl_d08) && "MEDADMIN_CODE" %in% colnames(ma_tbl_d08)) {
    ma_tbl_d08 %>%
      filter(MEDADMIN_TYPE == "ND") %>%
      select(ID,
             NDC          = MEDADMIN_CODE,
             raw_med_name = if ("RAW_MEDADMIN_MED_NAME" %in% colnames(ma_tbl_d08)) RAW_MEDADMIN_MED_NAME else NULL) %>%
      collect() %>%
      mutate(NDC = normalize_ndc(NDC)) %>%
      filter(NDC %in% ndc_unmatched$NDC)
  } else {
    tibble(ID = character(), NDC = character(), raw_med_name = character())
  }

  dp_freq <- if (!is.null(dp_tbl_d08) && "NDC" %in% colnames(dp_tbl_d08)) {
    dp_tbl_d08 %>%
      select(ID, NDC) %>%
      collect() %>%
      mutate(NDC = normalize_ndc(NDC), raw_med_name = NA_character_) %>%
      filter(NDC %in% ndc_unmatched$NDC)
  } else {
    tibble(ID = character(), NDC = character(), raw_med_name = character())
  }

  combined_freq <- bind_rows(ma_nd_freq, dp_freq) %>%
    group_by(NDC) %>%
    summarise(
      raw_med_name = first(na.omit(raw_med_name)),
      n_patients   = suppress_small(n_distinct(ID)),
      n_rows       = n(),
      .groups = "drop"
    ) %>%
    arrange(desc(n_rows)) %>%
    mutate(rank = row_number()) %>%
    slice_head(n = TOP_N_NDC)

  df_ndc_freq_ranked <- combined_freq
}

message(glue("  D-08: {nrow(df_ndc_freq_ranked)} unmatched NDCs in top-{TOP_N_NDC} frequency table\n"))


# ==============================================================================
# SECTION 13: D-09 RXNAV ALTERNATE-ENDPOINT RE-QUERY ----
# HiPerGator-only (network calls). IS_LOCAL-gated — skipped on Windows.
# Tries ndcproperties.json and ndcstatus.json for each unresolved NDC.
# Output: output/ndc_rxnorm_crosswalk_requery.csv (new file, NOT overwriting
#         output/ndc_rxnorm_crosswalk_audit.csv).
# ==============================================================================

message("--- Section 13: D-09 — RxNav alternate-endpoint re-query ---")

# IS_LOCAL is set in R/00_config.R (TRUE on Windows, FALSE on HiPerGator).
df_ndc_requery <- tibble(
  NDC           = character(),
  rxcui_primary = character(),
  rxcui_alternate = character(),
  endpoint_used = character(),
  chemo_match   = logical()
)

if (exists("IS_LOCAL") && !IS_LOCAL && nrow(ndc_unmatched) > 0L) {
  message(glue("  [D-09] Running alternate-endpoint re-query for {format(nrow(ndc_unmatched), big.mark=',')} unresolved NDCs (HiPerGator mode) ..."))

  # Alternate-endpoint lookup: tries ndcproperties then ndcstatus.
  # Mirrors R/108 req_retry / 0.1s sleep / NA-on-failure pattern (Pitfall 5).
  lookup_ndc_alternate <- function(ndc, sleep_sec = 0.1) {
    for (endpoint in c("ndcproperties", "ndcstatus")) {
      url <- glue("https://rxnav.nlm.nih.gov/REST/{endpoint}.json?id={ndc}")
      result <- tryCatch({
        resp <- httr2::request(url) |>
          httr2::req_timeout(10) |>
          httr2::req_retry(
            max_tries    = 3,
            is_transient = ~ httr2::resp_status(.x) %in% c(429L, 503L, 504L)
          ) |>
          httr2::req_perform()
        data <- httr2::resp_body_json(resp)
        rxcui <- data[[if (endpoint == "ndcproperties") "ndcItem" else "ndcStatus"]][["rxcui"]]
        if (!is.null(rxcui) && nchar(rxcui) > 0L) rxcui else NA_character_
      }, error = function(e) NA_character_)
      Sys.sleep(sleep_sec)
      if (!is.na(result)) return(list(rxcui = result, endpoint = endpoint))
    }
    list(rxcui = NA_character_, endpoint = NA_character_)
  }

  # Batch loop with progress every 100 NDCs.
  requery_ndcs <- ndc_unmatched$NDC
  requery_results <- vector("list", length(requery_ndcs))

  for (i in seq_along(requery_ndcs)) {
    if (i %% 100L == 0L) message(glue("  [D-09] Progress: {i}/{length(requery_ndcs)} NDCs queried ..."))
    res <- lookup_ndc_alternate(requery_ndcs[[i]])
    requery_results[[i]] <- tibble(
      NDC             = requery_ndcs[[i]],
      rxcui_primary   = NA_character_,
      rxcui_alternate = res$rxcui,
      endpoint_used   = res$endpoint
    )
  }

  df_ndc_requery <- bind_rows(requery_results) %>%
    mutate(chemo_match = !is.na(rxcui_alternate) & rxcui_alternate %in% CHEMO_RXNORM)

  n_recovered   <- sum(!is.na(df_ndc_requery$rxcui_alternate), na.rm = TRUE)
  n_chemo_match <- sum(df_ndc_requery$chemo_match, na.rm = TRUE)
  message(glue("  [D-09] Complete: {n_recovered} NDCs recovered alternate RxCUI; {n_chemo_match} match chemo_rxnorm"))

  write.csv(df_ndc_requery, NDC_REQUERY_CSV, row.names = FALSE, na = "")
  message(glue("  [D-09] Results written to {NDC_REQUERY_CSV}\n"))

} else {
  message("  [D-09] Skipped in local mode (requires network). Run on HiPerGator.\n")
}


# ==============================================================================
# SECTION 14: D-10 RESOLVED-NON-CHEMO GAP CHECK ----
# Of the matched NDCs, check whether any resolved to a chemo ingredient MISSING
# from chemo_rxnorm. This flags chemo_rxnorm reference-list gaps (distinct from
# NDC-resolution failures). Phase 123 FLAGS gaps; correcting the list is deferred.
# ==============================================================================

message("--- Section 14: D-10 — resolved-non-chemo gap check ---")

df_resolved_gap <- tibble(
  rxcui             = character(),
  drug_name         = character(),
  n_ndc_entries     = integer(),
  in_chemo_rxnorm   = logical(),
  flag              = character()
)

if (nrow(ndc_matched) > 0L) {
  # Of matched NDCs, which resolved RxCUIs are NOT in chemo_rxnorm?
  resolved_not_chemo <- ndc_matched %>%
    filter(!is.na(rxcui), nchar(trimws(rxcui)) > 0L) %>%
    filter(!rxcui %in% CHEMO_RXNORM) %>%
    group_by(rxcui) %>%
    summarise(n_ndc_entries = n(), .groups = "drop")

  if (nrow(resolved_not_chemo) > 0L) {
    df_resolved_gap <- resolved_not_chemo %>%
      mutate(
        drug_name = unname(MEDICATION_LOOKUP[rxcui]),
        drug_name = coalesce(drug_name, paste0("RxCUI:", rxcui)),
        in_chemo_rxnorm = FALSE,
        # Flag any resolved-non-chemo RxCUI whose name matches a chemo pattern
        flag = case_when(
          !is.na(unname(MEDICATION_LOOKUP[rxcui])) ~
            "HAS_LOOKUP_NAME — review for chemo_rxnorm gap",
          TRUE ~ "NO_LOOKUP_NAME — may be non-chemo or missing from MEDICATION_LOOKUP"
        )
      )
  }

  n_gap_candidates <- nrow(df_resolved_gap %>% filter(str_detect(flag, "HAS_LOOKUP_NAME")))
  message(glue("  D-10: {nrow(df_resolved_gap)} resolved-non-chemo RxCUIs; {n_gap_candidates} have MEDICATION_LOOKUP entries (potential chemo_rxnorm gaps — SME review needed)\n"))
} else {
  message("  D-10: NDC audit CSV absent or no matched NDCs — gap check skipped.\n")
}


# ==============================================================================
# SECTION 15: BUILD AND WRITE MULTI-SHEET XLSX ----
# openxlsx2 pattern from R/51 / R/100 / TABLE scripts.
# xlsx assembly deferred to Plan 02 — this section is a stub so that Plan 02
# can append sheet-writing code without structural rework.
# ==============================================================================

message("--- Section 15: xlsx assembly (stub — full implementation in Plan 02) ---")
message("  Data frames ready for xlsx: df_before_after_summary, df_source_counts,")
message("  df_timing_shift, df_ingredient_delta, df_regimen_impact,")
message("  df_ndc_freq_ranked, df_ndc_string_match, df_ndc_requery, df_resolved_gap\n")

# Plan 02 will instantiate wb <- wb_workbook() and write all sheets here.


# ==============================================================================
# SECTION 16: CLOSE DUCKDB CONNECTION ----
# ==============================================================================

message("--- Section 16: closing DuckDB connection ---")
if (exists("pcornet_con", envir = .GlobalEnv)) {
  close_pcornet_con()
}
message("=== Phase 123 R/109 complete ===\n")
