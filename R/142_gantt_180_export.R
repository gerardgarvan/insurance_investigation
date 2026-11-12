# Phase 143: reads treatment_episodes_180_enriched.rds (R/28 run with p143_out_suffix="_180_enriched").
# Do NOT read treatment_episodes_180.rds directly — that file lacks the enrichment columns.

# ==============================================================================
# Phase 142: 180-Day Gantt CSV Export
# ==============================================================================
#
# Purpose:
#   Produce 180-day Gantt CSV files with the same schema as gantt_episodes.csv /
#   gantt_detail.csv (R/52), using treatment_episodes_180.rds and
#   treatment_episode_detail_180.rds produced by R/26 Section 5C.
#
# Inputs:
#   - cache/outputs/treatment_episodes_180.rds      (Phase 142, R/26 Section 5C)
#   - cache/outputs/treatment_episode_detail_180.rds (Phase 142, R/26 Section 5C)
#   - cache/outputs/code_descriptions.rds           (Phase 48b)
#   - cache/outputs/validated_death_dates.rds        (Phase 59)
#   - output/confirmed_hl_cohort.rds                (Phase 55)
#   - output/tables/cancer_summary.csv              (Phase 115: 7-day confirmed data)
#
# Outputs:
#   - output/gantt_episodes_180.csv  (26 columns, same schema as gantt_episodes.csv + Phase 199 flags)
#   - output/gantt_detail_180.csv    (14 columns, same schema as gantt_detail.csv)
#
# Requirements: EP-180-01, EP-180-02
# D-01: Gap window = from episode_start (same logic as 90-day, confirmed §0c 2026-08-14)
# D-02: Semicolons for multi-value field separators (inherited from R/52 clean_multi_value)
# D-03: Output filenames use *_180.csv suffix
#
# Note: Enrichment columns (cancer_category, drug_group, code_type, source_table,
# sct_cross_use_flag, episode_dx_*) are derived from the upstream pipeline in
# treatment_episodes.rds. Because the 180-day RDS is produced directly by R/26
# Section 5C without passing through R/60-63/R/91/R/112, those columns will be
# absent and fall back to the same guard-clause defaults as R/52. The output is
# still valid for comparing episode-window definitions.
#
# Standalone script — run interactively or via Rscript from the project root:
#   Rscript R/142_gantt_180_export.R
# Not registered in R/39_run_all_investigations.R (deliberate: this is a
# comparison/analysis aid, not a pipeline artifact regenerated on every run).
# ==============================================================================


# --- SECTION 1: SETUP AND CONFIGURATION ----

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(lubridate)
  library(DBI)
  library(duckdb)
})
# utils_death.R and utils_activity.R auto-sourced via R/00_config.R

source("R/00_config.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_dates.R")
source("R/utils/utils_cancer.R")

# Input paths
EPISODES_RDS         <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes_180_enriched.rds")
DETAIL_RDS           <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail_180.rds")
DESCRIPTIONS_RDS     <- file.path(CONFIG$cache$outputs_dir, "code_descriptions.rds")
VALIDATED_DEATHS_RDS <- file.path(CONFIG$cache$outputs_dir, "validated_death_dates.rds")
COHORT_RDS           <- file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds")
# reads R/45 raw cancer_summary.csv -- matches delivered outputs as of 2026-11-03 (R/52, R/142)
CANCER_SUMMARY_CSV   <- build_output_path("tables", "cancer_summary.csv")
CUTOFF_DATE <- as.Date(Sys.getenv("HL_CUTOFF_DATE", "2025-12-31"))  # study cutoff for death credibility check

# Output paths
OUTPUT_EPISODES <- file.path(CONFIG$output_dir, "gantt_episodes_180.csv")
OUTPUT_DETAIL   <- file.path(CONFIG$output_dir, "gantt_detail_180.csv")

# Schema vectors — identical to R/52 (EP-180-01, EP-180-02)
EPISODES_SCHEMA <- c(
  "patient_id", "treatment_type", "episode_number",
  "episode_start", "episode_stop", "episode_length_days",
  "distinct_dates_in_episode",
  "triggering_codes", "drug_names", "triggering_code_descriptions",
  "cancer_category", "is_hodgkin",
  "drug_group",
  "code_type", "source_table", "sct_cross_use_flag",
  "episode_dx_codes", "episode_dx_categories",
  "episode_dx_7day_confirmed", "age_at_episode",
  # Phase 192.1: autoimmune diagnosis flag columns (+2 columns, now 22 total)
  "has_autoimmune_dx", "first_autoimmune_dx_date",
  # Phase 192.2: ICD-9/10 code system column (+1 column, now 23 total)
  "autoimmune_dx_code_system",
  # Phase 199: + immune_flag, ever_brentuximab, immune_flag_dx (+3 columns, now 26 total)
  "immune_flag", "ever_brentuximab", "immune_flag_dx"
)

DETAIL_SCHEMA <- c(
  "patient_id", "treatment_type", "treatment_date",
  "triggering_code", "drug_name", "episode_number",
  "episode_start", "episode_stop",
  "triggering_code_description",
  "cancer_category", "is_hodgkin",
  "code_type", "source_table", "sct_cross_use_flag"
)

# SAFE-01: Fail fast if 180-day RDS files are missing
assert_rds_exists(EPISODES_RDS, script_name = "R/142")
assert_rds_exists(DETAIL_RDS,   script_name = "R/142")


# --- SECTION 2: LOAD INPUT DATA ----

message("=== Phase 142: 180-Day Gantt Export ===\n")

episodes <- readRDS(EPISODES_RDS)
# Phase 199 fix: the Phase 197-01 guard stopifnot("is_first_line" %in% names(episodes))
# was removed here. is_first_line is created by R/29 for the 90-day treatment_episodes.rds
# only; treatment_episodes_180_enriched.rds is built by R/28 (p143_out_suffix) and never
# passes through R/29, so the guard could never pass. R/142 does not use is_first_line.
message(glue("  Loaded {format(nrow(episodes), big.mark = ',')} 180-day episode rows"))

assert_df_valid(episodes, "treatment_episodes_180",
  required_cols = c("patient_id", "treatment_type", "episode_start", "episode_stop"),
  script_name = "R/142")

detail <- readRDS(DETAIL_RDS)
message(glue("  Loaded {format(nrow(detail), big.mark = ',')} 180-day detail rows"))

assert_df_valid(detail, "treatment_episode_detail_180",
  required_cols = c("patient_id", "treatment_type", "treatment_date", "triggering_code"),
  script_name = "R/142")



# --- SECTION 2B: 7-DAY CONFIRMED CATEGORIES LOOKUP (Phase 115) ---

message("\n--- Building patient-level 7-day confirmed categories lookup ---")

patient_7day_categories <- NULL
if (file.exists(CANCER_SUMMARY_CSV)) {
  cancer_summary_raw <- read.csv(CANCER_SUMMARY_CSV, stringsAsFactors = FALSE)
  message(glue("  Loaded cancer_summary.csv: {nrow(cancer_summary_raw)} patient-code rows"))

  confirmed_rows <- cancer_summary_raw %>%
    filter(two_or_more_unique_dates_gt_7 == 1) %>%
    mutate(category = classify_codes(cancer_code))

  patient_7day_categories <- confirmed_rows %>%
    filter(!is.na(category)) %>%
    group_by(ID) %>%
    summarise(
      confirmed_categories = list(sort(unique(category))),
      .groups = "drop"
    )

  message(glue("  Patients with 7-day confirmed categories: {nrow(patient_7day_categories)}"))
} else {
  message("  WARNING: cancer_summary.csv not found. episode_dx_7day_confirmed will be empty.")
}


# --- SECTION 2C: DEMOGRAPHIC BIRTH DATE LOOKUP ---

message("\n--- Loading DEMOGRAPHIC birth dates for age_at_episode ---")

birth_dates <- NULL
masked_ids  <- character(0)
tryCatch({
  open_pcornet_con()
  birth_dates <- get_pcornet_table("DEMOGRAPHIC") %>%
    select(ID, BIRTH_DATE) %>%
    collect() %>%
    mutate(BIRTH_DATE = parse_pcornet_date(BIRTH_DATE)) %>%
    filter(!is.na(BIRTH_DATE))
  close_pcornet_con()
  n_masked <- sum(year(birth_dates$BIRTH_DATE) == 1900)
  if (n_masked > 0) {
    message(glue("  {n_masked} patients have 1900 placeholder birth date — age will be set to 90"))
    masked_ids <- birth_dates$ID[year(birth_dates$BIRTH_DATE) == 1900]
  }
  message(glue("  Loaded {nrow(birth_dates)} patients with valid birth dates"))
}, error = function(e) {
  message(glue("  WARNING: Could not load DEMOGRAPHIC birth dates: {conditionMessage(e)}"))
  try(close_pcornet_con(), silent = TRUE)
})


# --- SECTION 3: CODE DESCRIPTION LOOKUP ----

code_descriptions <- NULL
if (file.exists(DESCRIPTIONS_RDS)) {
  assert_rds_exists(DESCRIPTIONS_RDS, script_name = "R/142")
  code_descriptions <- readRDS(DESCRIPTIONS_RDS)
  message(glue("  Loaded {format(length(code_descriptions), big.mark = ',')} code descriptions"))
} else {
  message("  WARNING: code_descriptions.rds not found. Description columns will be empty.")
}

lookup_description <- function(code) {
  if (is.null(code_descriptions) || is.na(code) || code == "") return("")
  if (code %in% names(code_descriptions)) return(code_descriptions[[code]])
  return("")
}

map_codes_to_descriptions <- function(codes_str) {
  if (is.na(codes_str) || codes_str == "") return("")
  codes <- str_split(codes_str, ",")[[1]]
  paste(sapply(codes, lookup_description, USE.NAMES = FALSE), collapse = ",")
}


# --- SECTION 4: SELECT AND ORDER COLUMNS ----

message("\n--- Building export tables ---")

episodes_export <- episodes %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, triggering_codes,
    encounter_ids, drug_names, drug_group
  ) %>%
  mutate(
    triggering_code_descriptions = sapply(triggering_codes, map_codes_to_descriptions, USE.NAMES = FALSE)
  ) %>%
  left_join(
    episodes %>% select(
      patient_id, episode_number, treatment_type,
      cancer_category, is_hodgkin, cancer_link_method,
      code_type, source_table, sct_cross_use_flag,
      episode_dx_codes, episode_dx_categories
    ),
    by = c("patient_id", "episode_number", "treatment_type")
  ) %>%
  mutate(
    cancer_category = ifelse(is.na(cancer_category), "", cancer_category),
    is_hodgkin      = ifelse(is.na(is_hodgkin), FALSE, is_hodgkin)
  ) %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, triggering_codes,
    encounter_ids, drug_names, triggering_code_descriptions,
    cancer_category, is_hodgkin, cancer_link_method,
    drug_group,
    code_type, source_table, sct_cross_use_flag,
    episode_dx_codes, episode_dx_categories
  )

message(glue("  Built episodes_export: {format(nrow(episodes_export), big.mark = ',')} rows, {ncol(episodes_export)} columns"))

episodes_v2_cols <- episodes %>%
  select(
    patient_id, treatment_type, episode_number, cancer_category, is_hodgkin,
    cancer_link_method, code_type, source_table, sct_cross_use_flag
  )

detail_export <- detail %>%
  select(
    patient_id, treatment_type, treatment_date, triggering_code,
    ENCOUNTERID, drug_name,
    episode_number, episode_start, episode_stop
  ) %>%
  mutate(
    triggering_code_description = sapply(triggering_code, lookup_description, USE.NAMES = FALSE)
  ) %>%
  left_join(episodes_v2_cols, by = c("patient_id", "treatment_type", "episode_number")) %>%
  mutate(
    cancer_category = ifelse(is.na(cancer_category), "", cancer_category),
    is_hodgkin      = ifelse(is.na(is_hodgkin), FALSE, is_hodgkin)
  ) %>%
  select(
    patient_id, treatment_type, treatment_date, triggering_code,
    ENCOUNTERID, drug_name,
    episode_number, episode_start, episode_stop,
    triggering_code_description,
    cancer_category, is_hodgkin, cancer_link_method,
    code_type, source_table, sct_cross_use_flag
  )

message(glue("  Built detail_export: {format(nrow(detail_export), big.mark = ',')} rows, {ncol(detail_export)} columns"))


# --- Phase 115: episode_dx_7day_confirmed ---

if (!is.null(patient_7day_categories)) {
  get_confirmed_subset <- function(patient_id_val, dx_categories_str) {
    if (is.na(dx_categories_str) || dx_categories_str == "") return("")
    ep_cats <- str_trim(str_split(dx_categories_str, ",")[[1]])
    ep_cats <- ep_cats[ep_cats != ""]
    if (length(ep_cats) == 0) return("")
    patient_row <- patient_7day_categories %>% filter(ID == patient_id_val)
    if (nrow(patient_row) == 0) return("")
    confirmed <- patient_row$confirmed_categories[[1]]
    matched   <- intersect(ep_cats, confirmed)
    if (length(matched) == 0) return("")
    paste(sort(matched), collapse = ",")
  }

  episodes_export <- episodes_export %>%
    mutate(
      episode_dx_7day_confirmed = mapply(
        get_confirmed_subset,
        patient_id, episode_dx_categories,
        USE.NAMES = FALSE
      )
    )
  n_with_confirmed <- sum(episodes_export$episode_dx_7day_confirmed != "", na.rm = TRUE)
  message(glue("  Phase 115: {n_with_confirmed} episodes with 7-day confirmed dx categories"))
} else {
  episodes_export <- episodes_export %>%
    mutate(episode_dx_7day_confirmed = "")
}

# --- Phase 115: age_at_episode ---

if (!is.null(birth_dates)) {
  episodes_export <- episodes_export %>%
    left_join(birth_dates, by = c("patient_id" = "ID")) %>%
    mutate(
      age_at_episode = as.integer(floor(
        as.numeric(difftime(episode_start, BIRTH_DATE, units = "days")) / 365.25
      ))
    ) %>%
    select(-BIRTH_DATE) %>%
    mutate(age_at_episode = ifelse(patient_id %in% masked_ids, 90L, age_at_episode))
  message(glue("  Phase 115: {sum(!is.na(episodes_export$age_at_episode))}/{nrow(episodes_export)} episodes with age_at_episode"))
} else {
  episodes_export <- episodes_export %>%
    mutate(age_at_episode = NA_integer_)
  message("  Phase 115: age_at_episode defaulted to NA (no DEMOGRAPHIC data)")
}


# --- SECTION 4B: DEATH PSEUDO-TREATMENT ROWS ---
# [161-07 audit] Updated: death marker uses death_date_resolved (resolve_death_date, grace 30).
# Patients with implausible death dates get NA resolved dates and are excluded from the marker.

if (file.exists(VALIDATED_DEATHS_RDS)) {
  message("\n--- Building Death pseudo-treatment rows ---")
  assert_rds_exists(VALIDATED_DEATHS_RDS, script_name = "R/142")
  validated_deaths <- readRDS(VALIDATED_DEATHS_RDS)

  # Resolve death dates using the shared canonical utility (161-07).
  con_death <- DBI::dbConnect(duckdb::duckdb(), dbdir = CONFIG$cache$duckdb_path, read_only = TRUE)
  tryCatch({
    death_id_tbl <- validated_deaths %>% distinct(ID)
    activity_for_death <- get_last_activity(con_death, death_id_tbl, CUTOFF_DATE)

    death_raw_tbl <- validated_deaths %>%
      filter(!is.na(DEATH_DATE)) %>%
      select(ID, DEATH_DATE, DEATH_SOURCE)

    resolved_deaths <- resolve_death_date(death_raw_tbl, activity_for_death, grace_days = 30L)
  }, finally = {
    DBI::dbDisconnect(con_death, shutdown = TRUE)
  })

  n_raw      <- nrow(validated_deaths %>% filter(!is.na(DEATH_DATE)))
  n_resolved <- sum(!is.na(resolved_deaths$death_date_resolved))
  message(glue("  Death dates: {n_raw} raw -> {n_resolved} credible (resolve_death_date grace=30)"))
  if (n_raw != n_resolved)
    message(glue("  {n_raw - n_resolved} implausible death date(s) excluded from 180d Gantt marker"))

  death_data <- resolved_deaths %>%
    filter(!is.na(death_date_resolved)) %>%
    transmute(ID, DEATH_DATE = death_date_resolved)

  if (nrow(death_data) > 0) {
    death_episodes <- death_data %>%
      mutate(
        patient_id = ID, treatment_type = "Death", episode_number = 1L,
        episode_start = DEATH_DATE, episode_stop = DEATH_DATE,
        episode_length_days = 0L, distinct_dates_in_episode = 1L,
        triggering_codes = "", encounter_ids = "", drug_names = "",
        triggering_code_descriptions = "", cancer_category = "",
        is_hodgkin = FALSE, cancer_link_method = "none", drug_group = "",
        code_type = "", source_table = "", sct_cross_use_flag = "",
        episode_dx_codes = NA_character_, episode_dx_categories = NA_character_,
        episode_dx_7day_confirmed = ""
      )

    if (!is.null(birth_dates)) {
      death_episodes <- death_episodes %>%
        left_join(birth_dates, by = c("patient_id" = "ID")) %>%
        mutate(age_at_episode = as.integer(floor(
          as.numeric(difftime(episode_start, BIRTH_DATE, units = "days")) / 365.25
        ))) %>%
        select(-BIRTH_DATE) %>%
        mutate(age_at_episode = ifelse(patient_id %in% masked_ids, 90L, age_at_episode))
    } else {
      death_episodes <- death_episodes %>% mutate(age_at_episode = NA_integer_)
    }

    death_episodes <- death_episodes %>%
      select(
        patient_id, treatment_type, episode_number,
        episode_start, episode_stop, episode_length_days,
        distinct_dates_in_episode, triggering_codes,
        encounter_ids, drug_names, triggering_code_descriptions,
        cancer_category, is_hodgkin, cancer_link_method, drug_group,
        code_type, source_table, sct_cross_use_flag,
        episode_dx_codes, episode_dx_categories,
        episode_dx_7day_confirmed, age_at_episode
      )

    death_detail <- death_data %>%
      mutate(
        patient_id = ID, treatment_type = "Death", treatment_date = DEATH_DATE,
        triggering_code = "", ENCOUNTERID = NA_character_, drug_name = "",
        episode_number = 1L, episode_start = DEATH_DATE, episode_stop = DEATH_DATE,
        triggering_code_description = "", cancer_category = "", is_hodgkin = FALSE,
        cancer_link_method = "none", code_type = "", source_table = "",
        sct_cross_use_flag = ""
      ) %>%
      select(
        patient_id, treatment_type, treatment_date, triggering_code,
        ENCOUNTERID, drug_name, episode_number, episode_start, episode_stop,
        triggering_code_description, cancer_category, is_hodgkin, cancer_link_method,
        code_type, source_table, sct_cross_use_flag
      )

    episodes_export <- bind_rows(episodes_export, death_episodes) %>%
      arrange(patient_id, episode_start, treatment_type)
    detail_export <- bind_rows(detail_export, death_detail) %>%
      arrange(patient_id, treatment_date, treatment_type)

    message(glue("  Added {nrow(death_episodes)} Death episode rows"))
    message(glue("  Added {nrow(death_detail)} Death detail rows"))
  } else {
    message("  No validated death dates found — skipping Death rows")
  }
} else {
  message("  WARNING: validated_death_dates.rds not found — skipping Death rows")
}


# --- SECTION 4C: HL DIAGNOSIS PSEUDO-TREATMENT ROWS ---

if (file.exists(COHORT_RDS)) {
  message("\n--- Building HL Diagnosis pseudo-treatment rows ---")
  assert_rds_exists(COHORT_RDS, script_name = "R/142")
  hl_cohort  <- readRDS(COHORT_RDS)
  hl_dx_data <- hl_cohort %>% filter(!is.na(first_hl_dx_date)) %>% select(ID, first_hl_dx_date)

  if (nrow(hl_dx_data) > 0) {
    hl_dx_episodes <- hl_dx_data %>%
      mutate(
        patient_id = ID, treatment_type = "HL Diagnosis", episode_number = 1L,
        episode_start = first_hl_dx_date, episode_stop = first_hl_dx_date,
        episode_length_days = 0L, distinct_dates_in_episode = 1L,
        triggering_codes = "", encounter_ids = "", drug_names = "",
        triggering_code_descriptions = "", cancer_category = "Hodgkin Lymphoma",
        is_hodgkin = TRUE, cancer_link_method = "none", drug_group = "",
        code_type = "", source_table = "", sct_cross_use_flag = "",
        episode_dx_codes = NA_character_, episode_dx_categories = NA_character_,
        episode_dx_7day_confirmed = ""
      )

    if (!is.null(birth_dates)) {
      hl_dx_episodes <- hl_dx_episodes %>%
        left_join(birth_dates, by = c("patient_id" = "ID")) %>%
        mutate(age_at_episode = as.integer(floor(
          as.numeric(difftime(episode_start, BIRTH_DATE, units = "days")) / 365.25
        ))) %>%
        select(-BIRTH_DATE) %>%
        mutate(age_at_episode = ifelse(patient_id %in% masked_ids, 90L, age_at_episode))
    } else {
      hl_dx_episodes <- hl_dx_episodes %>% mutate(age_at_episode = NA_integer_)
    }

    hl_dx_episodes <- hl_dx_episodes %>%
      select(
        patient_id, treatment_type, episode_number,
        episode_start, episode_stop, episode_length_days,
        distinct_dates_in_episode, triggering_codes,
        encounter_ids, drug_names, triggering_code_descriptions,
        cancer_category, is_hodgkin, cancer_link_method, drug_group,
        code_type, source_table, sct_cross_use_flag,
        episode_dx_codes, episode_dx_categories,
        episode_dx_7day_confirmed, age_at_episode
      )

    hl_dx_detail <- hl_dx_data %>%
      mutate(
        patient_id = ID, treatment_type = "HL Diagnosis",
        treatment_date = first_hl_dx_date, triggering_code = "",
        ENCOUNTERID = NA_character_, drug_name = "", episode_number = 1L,
        episode_start = first_hl_dx_date, episode_stop = first_hl_dx_date,
        triggering_code_description = "", cancer_category = "Hodgkin Lymphoma",
        is_hodgkin = TRUE, cancer_link_method = "none",
        code_type = "", source_table = "", sct_cross_use_flag = ""
      ) %>%
      select(
        patient_id, treatment_type, treatment_date, triggering_code,
        ENCOUNTERID, drug_name, episode_number, episode_start, episode_stop,
        triggering_code_description, cancer_category, is_hodgkin, cancer_link_method,
        code_type, source_table, sct_cross_use_flag
      )

    episodes_export <- bind_rows(episodes_export, hl_dx_episodes) %>%
      arrange(patient_id, episode_start, treatment_type)
    detail_export <- bind_rows(detail_export, hl_dx_detail) %>%
      arrange(patient_id, treatment_date, treatment_type)

    message(glue("  Added {nrow(hl_dx_episodes)} HL Diagnosis episode rows"))
    message(glue("  Added {nrow(hl_dx_detail)} HL Diagnosis detail rows"))
  } else {
    message("  No HL diagnosis dates found — skipping HL Diagnosis rows")
  }
} else {
  message("  WARNING: confirmed_hl_cohort.rds not found — skipping HL Diagnosis rows")
}


# --- SECTION 4C2: AUTOIMMUNE DIAGNOSIS FLAGS (Phase 192.1/192.2, AUTOIMMUNE-FLAG-03/04) ---
# Patient-level has_autoimmune_dx (logical), first_autoimmune_dx_date (Date),
# and autoimmune_dx_code_system (character: "ICD-9", "ICD-10", "Both", NA)
# appended as columns 21-23. Identical logic to R/52 Section 4C2.
# PRE1922 baselines already saved by R/52 (run R/52 before R/142).

message("\n--- Building autoimmune diagnosis flags ---")

aim_full <- build_autoimmune_dx_flags(
  unique(episodes_export$patient_id),
  sentinel = SENTINEL_CUTOFF
)

aim <- aim_full |>
  dplyr::select(patient_id = ID, has_autoimmune_dx, first_autoimmune_dx_date, autoimmune_dx_code_system)

n0 <- nrow(episodes_export)
episodes_export <- dplyr::left_join(episodes_export, aim, by = "patient_id")
stopifnot("autoimmune join must not change row count" = nrow(episodes_export) == n0)

fmt_sup <- function(n) if (n >= 1L && n <= 10L) "<11" else format(n, big.mark = ",")
n_pts_true   <- sum(aim_full$has_autoimmune_dx)
n_qc_no_date <- sum(aim_full$qc_qualifying_no_valid_date)
message(glue("  Autoimmune flags: {fmt_sup(n_pts_true)} patients with has_autoimmune_dx = TRUE"))
message(glue("  QC qualifying-no-valid-date: {fmt_sup(n_qc_no_date)} patients"))
# Phase 192.2: flag now covers ICD-9 and ICD-10; autoimmune_dx_code_system labels each patient.
message("  KEY/QC: Autoimmune flag covers ICD-9 and ICD-10 codes. autoimmune_dx_code_system is ICD-9 / ICD-10 / Both / NA per patient.")

# QC: code system breakdown (counts 1-10 shown as "<11")
n_icd9  <- sum(aim_full$autoimmune_dx_code_system == "ICD-9",  na.rm = TRUE)
n_icd10 <- sum(aim_full$autoimmune_dx_code_system == "ICD-10", na.rm = TRUE)
n_both  <- sum(aim_full$autoimmune_dx_code_system == "Both",   na.rm = TRUE)
message(glue("  autoimmune_dx_code_system breakdown (patient-level):"))
message(glue("    ICD-9  : {fmt_sup(n_icd9)}"))
message(glue("    ICD-10 : {fmt_sup(n_icd10)}"))
message(glue("    Both   : {fmt_sup(n_both)}"))


# --- SECTION 4D: DATA QUALITY CLEANUP ----

message("\n--- Section 4D: Data Quality Cleanup ---")

episodes_export <- episodes_export %>%
  mutate(
    triggering_codes              = sapply(triggering_codes,              clean_multi_value, USE.NAMES = FALSE),
    drug_names                    = sapply(drug_names, function(dn) {
      if (is.na(dn) || dn == "" || dn == "NA") return("")
      parts <- str_trim(str_split(dn, ",")[[1]])
      parts <- parts[parts != "" & parts != "NA" & !is.na(parts)]
      parts <- canonicalize_drug_name(parts)
      parts <- sort(unique(parts[!is.na(parts) & parts != ""]))
      if (length(parts) == 0) return("")
      paste(parts, collapse = ";")
    }, USE.NAMES = FALSE),
    triggering_code_descriptions  = sapply(triggering_code_descriptions,  clean_multi_value, USE.NAMES = FALSE),
    code_type                     = sapply(code_type,                     clean_multi_value, USE.NAMES = FALSE),
    source_table                  = sapply(source_table,                  clean_multi_value, USE.NAMES = FALSE),
    episode_dx_codes              = sapply(episode_dx_codes,              clean_multi_value, USE.NAMES = FALSE),
    episode_dx_categories         = sapply(episode_dx_categories,         clean_multi_value, USE.NAMES = FALSE),
    episode_dx_7day_confirmed     = sapply(episode_dx_7day_confirmed,     clean_multi_value, USE.NAMES = FALSE),
    drug_group                    = sapply(drug_group,                    clean_multi_value, USE.NAMES = FALSE)
  )

detail_export <- detail_export %>%
  mutate(
    triggering_code             = sapply(triggering_code,             clean_multi_value, USE.NAMES = FALSE),
    triggering_code_description = sapply(triggering_code_description, clean_multi_value, USE.NAMES = FALSE),
    code_type                   = sapply(code_type,                   clean_multi_value, USE.NAMES = FALSE),
    source_table                = sapply(source_table,                clean_multi_value, USE.NAMES = FALSE)
  )

message("  Multi-value fields cleaned (separator: semicolon, deduped, blanks dropped)")

# Fill pseudo-treatment descriptions
episodes_export <- episodes_export %>%
  mutate(triggering_code_descriptions = case_when(
    treatment_type %in% c("Death", "HL Diagnosis") &
      (triggering_code_descriptions == "" | is.na(triggering_code_descriptions)) ~ treatment_type,
    TRUE ~ triggering_code_descriptions
  ))
detail_export <- detail_export %>%
  mutate(triggering_code_description = case_when(
    treatment_type %in% c("Death", "HL Diagnosis") &
      (triggering_code_description == "" | is.na(triggering_code_description)) ~ treatment_type,
    TRUE ~ triggering_code_description
  ))

# NA -> empty string
episodes_export <- episodes_export %>%
  mutate(across(where(is.character), ~ ifelse(is.na(.) | . == "NA", "", .)))
detail_export <- detail_export %>%
  mutate(across(where(is.character), ~ ifelse(is.na(.) | . == "NA", "", .)))

# Blank cancer_category -> "Unlinked"
episodes_export <- episodes_export %>%
  mutate(cancer_category = ifelse(cancer_category == "", "Unlinked", cancer_category))
detail_export <- detail_export %>%
  mutate(cancer_category = ifelse(cancer_category == "", "Unlinked", cancer_category))

# Derive is_hodgkin from cancer_category
episodes_export <- episodes_export %>%
  mutate(is_hodgkin = str_detect(cancer_category, "Hodgkin") & !str_detect(cancer_category, "Non-Hodgkin"))
detail_export <- detail_export %>%
  mutate(is_hodgkin = str_detect(cancer_category, "Hodgkin") & !str_detect(cancer_category, "Non-Hodgkin"))

message("  NA converted to empty; cancer_category filled; is_hodgkin derived")

# --- Phase 199: drug-family matching for immune_flag / ever_brentuximab ---
# drug_names tokens come from two sources (MEDICATION_LOOKUP title-cased names and
# R/27 RxNorm names), and DRUG_NAME_ALIASES has no Rituximab/Methotrexate/Brentuximab
# entries. Variants such as "Methotrexate Sodium", "Rituximab (Truxima)",
# "Rituximab/Hyaluronidase" or lowercase "methotrexate" would be missed by an exact
# match. Tokens are therefore matched by case-insensitive prefix and mapped to the
# config label on a COPY passed to build_immune_flags(). The drug_names column
# written to the CSV is NOT changed, so the PRE199 regression is unaffected.
IMMUNE_DRUG_FAMILY_PATTERNS <- c(
  stats::setNames("^rituximab",    IMMUNE_FLAG_DRUGS[1]),  # "Rituximab"
  stats::setNames("^methotrexate", IMMUNE_FLAG_DRUGS[2]),  # "Methotrexate"
  stats::setNames("^brentuximab",  BRENTUXIMAB_DRUG)       # "Brentuximab Vedotin"
)
stopifnot("IMMUNE_FLAG_DRUGS order must be Rituximab, Methotrexate" =
            identical(tolower(IMMUNE_FLAG_DRUGS), c("rituximab", "methotrexate")))

normalize_family_tokens <- function(dn_str) {
  if (is.na(dn_str) || dn_str == "") return("")
  toks <- trimws(strsplit(dn_str, ";", fixed = TRUE)[[1]])
  for (lab in names(IMMUNE_DRUG_FAMILY_PATTERNS)) {
    toks[grepl(IMMUNE_DRUG_FAMILY_PATTERNS[[lab]], toks, ignore.case = TRUE)] <- lab
  }
  toks <- toks[toks != ""]
  if (length(toks) == 0) return("")
  paste(sort(unique(toks)), collapse = ";")
}

# --- D-03 label discovery: confirm canonical Rituximab / Methotrexate / Brentuximab tokens ---
# Print distinct tokens matching any of the three drug names (patient counts, suppressed).
# If BRENTUXIMAB_DRUG is still a TODO placeholder, stop() and show tokens.
{
  if (grepl("TODO", BRENTUXIMAB_DRUG, fixed = TRUE)) {
    all_tokens <- unlist(strsplit(episodes_export$drug_names, ";"))
    # base grep(): use ignore.case (stringr::regex() options are ignored by base grep)
    hits <- unique(trimws(grep(
      "rituximab|methotrexate|brentuximab",
      all_tokens, value = TRUE, ignore.case = TRUE
    )))
    stop(glue(
      "BRENTUXIMAB_DRUG is still a TODO. Canonical tokens found:\n",
      paste(hits, collapse = "\n"),
      "\nSet BRENTUXIMAB_DRUG in R/00_config.R and re-run."
    ))
  }
  message("\n--- D-03: Rituximab / Methotrexate / Brentuximab token discovery ---")
  token_df <- episodes_export |>
    dplyr::select(patient_id, drug_names) |>
    dplyr::mutate(
      tokens = strsplit(drug_names, ";")
    ) |>
    tidyr::unnest(tokens) |>
    dplyr::mutate(tokens = trimws(tokens)) |>
    dplyr::filter(grepl("rituximab|methotrexate|brentuximab", tokens, ignore.case = TRUE)) |>
    dplyr::group_by(tokens) |>
    dplyr::summarise(n_patients = dplyr::n_distinct(patient_id), .groups = "drop") |>
    dplyr::arrange(tokens)
  if (nrow(token_df) == 0) {
    message("  No matching tokens found.")
  } else {
    # Show which flag family each raw token is counted under (case-insensitive prefix match)
    token_df$family <- vapply(token_df$tokens, function(t) {
      hit <- names(IMMUNE_DRUG_FAMILY_PATTERNS)[vapply(
        IMMUNE_DRUG_FAMILY_PATTERNS, function(p) grepl(p, t, ignore.case = TRUE), logical(1))]
      if (length(hit) == 0) "(not counted)" else hit[1]
    }, character(1))
    for (i in seq_len(nrow(token_df))) {
      message(glue("  token={token_df$tokens[i]}  -> {token_df$family[i]}  n_patients={fmt_sup(token_df$n_patients[i])}"))
    }
    n_variant <- sum(token_df$tokens != token_df$family & token_df$family != "(not counted)")
    if (n_variant > 0)
      message(glue("  NOTE (D-199-01): {n_variant} name variant(s) counted under their drug family above."))
  }
  message(glue("  IMMUNE_FLAG_DRUGS = {paste(IMMUNE_FLAG_DRUGS, collapse=', ')}"))
  message(glue("  BRENTUXIMAB_DRUG  = {BRENTUXIMAB_DRUG}"))
}

# --- SECTION 4C3: IMMUNE FLAG AND BRENTUXIMAB FLAG ---

message("\n--- Section 4C3: Immune flag and Brentuximab flag ---")

# Family-normalized copy of drug_names (see normalize_family_tokens above); one or
# more rows per patient. build_immune_flags() must collapse to one row per patient.
dn <- episodes_export |>
  dplyr::distinct(patient_id, drug_names) |>
  dplyr::mutate(drug_names = vapply(drug_names, normalize_family_tokens, character(1), USE.NAMES = FALSE)) |>
  dplyr::distinct()
imm_full <- build_immune_flags(unique(episodes_export$patient_id), dn)
stopifnot(
  "build_immune_flags: one row per patient" = !anyDuplicated(imm_full$patient_id),
  "build_immune_flags: covers every patient" =
    setequal(imm_full$patient_id, unique(episodes_export$patient_id))
)
imm <- imm_full |> dplyr::select(patient_id, immune_flag, ever_brentuximab, immune_flag_dx)
n0 <- nrow(episodes_export)
episodes_export <- dplyr::left_join(episodes_export, imm, by = "patient_id") |>
  dplyr::mutate(
    dplyr::across(c(immune_flag, ever_brentuximab), ~ dplyr::coalesce(.x, FALSE)),
    immune_flag_dx = dplyr::coalesce(immune_flag_dx, "")
  )
stopifnot(
  "immune_flag_dx non-blank iff immune_flag" =
    all((episodes_export$immune_flag_dx != "") == episodes_export$immune_flag),
  "immune join must not change row count" =
    nrow(episodes_export) == n0
)

# D-09 QC console block
{
  ep_pt <- episodes_export |> dplyr::distinct(patient_id, immune_flag, ever_brentuximab, immune_flag_dx,
                                               has_autoimmune_dx)
  ep_imm <- dplyr::left_join(ep_pt,
    imm_full |> dplyr::select(patient_id, has_rituximab, has_methotrexate, has_immune_flag_dx,
                               qc_immune_dx_no_valid_date),
    by = "patient_id"
  )

  n_rituximab     <- sum(ep_imm$has_rituximab,    na.rm = TRUE)
  n_methotrexate  <- sum(ep_imm$has_methotrexate, na.rm = TRUE)
  n_both_drugs    <- sum(ep_imm$has_rituximab & ep_imm$has_methotrexate, na.rm = TRUE)
  n_imm_dx        <- sum(ep_imm$has_immune_flag_dx, na.rm = TRUE)
  n_immune_flag   <- sum(ep_imm$immune_flag, na.rm = TRUE)
  n_case1_only    <- sum( ep_imm$has_rituximab & !ep_imm$has_methotrexate & ep_imm$immune_flag, na.rm = TRUE)
  n_case2_only    <- sum(!ep_imm$has_rituximab &  ep_imm$has_methotrexate & ep_imm$immune_flag, na.rm = TRUE)
  n_both_cases    <- sum( ep_imm$has_rituximab &  ep_imm$has_methotrexate & ep_imm$immune_flag, na.rm = TRUE)
  n_no_valid_date <- sum(ep_imm$qc_immune_dx_no_valid_date & (ep_imm$has_rituximab | ep_imm$has_methotrexate), na.rm = TRUE)
  n_brentuximab   <- sum(ep_imm$ever_brentuximab, na.rm = TRUE)

  message("\n  === D-09 QC: immune_flag / ever_brentuximab ===")
  message(glue("  Patients with Rituximab:               {fmt_sup(n_rituximab)}"))
  message(glue("  Patients with Methotrexate:            {fmt_sup(n_methotrexate)}"))
  message(glue("  Patients with both drugs:              {fmt_sup(n_both_drugs)}"))
  message(glue("  Patients with IMMUNE_FLAG dx:          {fmt_sup(n_imm_dx)}"))
  message(glue("  immune_flag = TRUE:                    {fmt_sup(n_immune_flag)}"))
  message(glue("    Case 1 only (Rituximab, no MTX):     {fmt_sup(n_case1_only)}"))
  message(glue("    Case 2 only (MTX, no Rituximab):     {fmt_sup(n_case2_only)}"))
  message(glue("    Both cases (Rituximab AND MTX):      {fmt_sup(n_both_cases)}"))
  message(glue("  Drug-exposed, qualifying dx, no valid date (D-05/D-199-03): {fmt_sup(n_no_valid_date)}"))
  message(glue("  ever_brentuximab = TRUE:               {fmt_sup(n_brentuximab)}"))

  # Label counts among immune_flag = TRUE patients
  if (n_immune_flag > 0) {
    immune_pts_dx <- ep_imm |>
      dplyr::filter(immune_flag) |>
      dplyr::mutate(labels = strsplit(immune_flag_dx, "; ")) |>
      tidyr::unnest(labels) |>
      dplyr::filter(trimws(labels) != "") |>
      dplyr::group_by(labels) |>
      dplyr::summarise(n = dplyr::n_distinct(patient_id), .groups = "drop") |>
      dplyr::arrange(dplyr::desc(n))
    message("  immune_flag_dx label counts (D-199-04):")
    for (i in seq_len(nrow(immune_pts_dx))) {
      message(glue("    {immune_pts_dx$labels[i]}: {fmt_sup(immune_pts_dx$n[i])}"))
    }
    n_multi_label <- sum(
      vapply(strsplit(ep_imm$immune_flag_dx[ep_imm$immune_flag], "; "), length, integer(1)) > 1L
    )
    message(glue("  Patients with >1 label: {fmt_sup(n_multi_label)}"))
  }

  # Cross-tab immune_flag x has_autoimmune_dx
  message("  Cross-tab immune_flag x has_autoimmune_dx (sanity check):")
  ct <- table(immune_flag = ep_imm$immune_flag, has_autoimmune_dx = ep_imm$has_autoimmune_dx)
  for (r in rownames(ct)) {
    for (cc in colnames(ct)) {
      message(glue("    immune_flag={r}, has_autoimmune_dx={cc}: {fmt_sup(ct[r, cc])}"))
    }
  }
  n_flag_not_aim <- sum(ep_imm$immune_flag & !ep_imm$has_autoimmune_dx, na.rm = TRUE)
  if (n_flag_not_aim > 0) {
    message(glue("  WARNING: {fmt_sup(n_flag_not_aim)} patients have immune_flag=TRUE but has_autoimmune_dx=FALSE"))
    message("  (These patients have an IMMUNE_FLAG code not in AUTOIMMUNE_DX_CODES — investigate.)")
  } else {
    message("  immune_flag=TRUE is a subset of has_autoimmune_dx=TRUE (expected).")
  }
}

# Column trimming — drop encounter_ids, cancer_link_method, ENCOUNTERID (same as R/52)
episodes_export <- episodes_export %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days, distinct_dates_in_episode,
    triggering_codes, drug_names, triggering_code_descriptions,
    cancer_category, is_hodgkin, drug_group,
    code_type, source_table, sct_cross_use_flag,
    episode_dx_codes, episode_dx_categories,
    episode_dx_7day_confirmed, age_at_episode,
    # Phase 192.1: autoimmune diagnosis flag columns (+2 columns, now 22 total)
    has_autoimmune_dx, first_autoimmune_dx_date,
    # Phase 192.2: code system label (+1 column, now 23 total)
    autoimmune_dx_code_system,
    # Phase 199: immune flag, brentuximab flag, immune dx labels (+3 columns, now 26 total)
    immune_flag, ever_brentuximab, immune_flag_dx
  )

detail_export <- detail_export %>%
  select(
    patient_id, treatment_type, treatment_date,
    triggering_code, drug_name, episode_number,
    episode_start, episode_stop, triggering_code_description,
    cancer_category, is_hodgkin,
    code_type, source_table, sct_cross_use_flag
  )

message(glue("  Columns trimmed: {ncol(episodes_export)} episode cols, {ncol(detail_export)} detail cols"))

# Schema verification
if (!identical(colnames(episodes_export), EPISODES_SCHEMA)) {
  missing <- setdiff(EPISODES_SCHEMA, colnames(episodes_export))
  extra   <- setdiff(colnames(episodes_export), EPISODES_SCHEMA)
  stop(glue("Episodes schema mismatch: missing=[{paste(missing, collapse=', ')}], extra=[{paste(extra, collapse=', ')}]"))
}
if (!identical(colnames(detail_export), DETAIL_SCHEMA)) {
  missing <- setdiff(DETAIL_SCHEMA, colnames(detail_export))
  extra   <- setdiff(colnames(detail_export), DETAIL_SCHEMA)
  stop(glue("Detail schema mismatch: missing=[{paste(missing, collapse=', ')}], extra=[{paste(extra, collapse=', ')}]"))
}

message(glue("  Schema verification: PASSED ({length(EPISODES_SCHEMA)} episode cols, {length(DETAIL_SCHEMA)} detail cols)"))


# --- SECTION 5: WRITE CSV OUTPUTS ----

message("\n--- Writing 180-day CSV outputs ---")

# PRE199 baseline: save the 23-column file before overwriting (keep-if-exists; re-run safe).
pre199 <- file.path(CONFIG$output_dir, "internal", "gantt_episodes_180_PRE199.csv")
if (!file.exists(pre199)) {
  if (file.exists(OUTPUT_EPISODES)) {
    # Guard: baseline must be the 23-column file
    base_check <- read.csv(OUTPUT_EPISODES, nrows = 1)
    stopifnot("PRE199 baseline must have 23 columns" = ncol(base_check) == 23L)
    file.copy(OUTPUT_EPISODES, pre199, overwrite = FALSE)
    message(glue("  PRE199 baseline saved: {pre199}"))
  } else {
    message("  PRE199 baseline skipped: OUTPUT_EPISODES does not yet exist.")
  }
} else {
  message(glue("  PRE199 baseline exists (kept): {pre199}"))
}

write.csv(episodes_export, OUTPUT_EPISODES, row.names = FALSE, na = "")
message(glue("  Wrote {OUTPUT_EPISODES}"))
message(glue("    {format(nrow(episodes_export), big.mark = ',')} rows, {ncol(episodes_export)} columns"))

# Phase 199 regression: verify the 23 original columns are unchanged vs PRE199 baseline.
if (file.exists(pre199)) {
  message("\n--- Phase 199 regression check ---")
  base_reg <- read.csv(pre199,       colClasses = "character")
  new_reg  <- read.csv(OUTPUT_EPISODES, colClasses = "character")
  stopifnot(
    "regression: row count unchanged"        = nrow(new_reg)  == nrow(base_reg),
    "regression: col 1-23 names unchanged"   = identical(names(new_reg)[1:23], names(base_reg))
  )
  # Multiset comparison: sorted pasted rows of first 23 columns
  base_rows <- sort(do.call(paste, base_reg[, 1:23, drop = FALSE]))
  new_rows  <- sort(do.call(paste, new_reg[,  1:23, drop = FALSE]))
  if (!identical(base_rows, new_rows)) {
    diffs <- which(base_rows != new_rows)
    stop(glue("Phase 199 regression FAIL: {length(diffs)} row(s) differ in original 23 columns.
Example diff (first mismatch):
  PRE199: {base_rows[diffs[1]]}
  NEW:    {new_rows[diffs[1]]}"))
  }
  message("Phase 199 regression: PASS (23 original columns unchanged)")
}

write.csv(detail_export, OUTPUT_DETAIL, row.names = FALSE, na = "")
message(glue("  Wrote {OUTPUT_DETAIL}"))
message(glue("    {format(nrow(detail_export), big.mark = ',')} rows, {ncol(detail_export)} columns"))


ep90_check  <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds"))


# --- SECTION 6: FINAL SUMMARY ----

message("\n=== 180-Day Gantt Export Complete ===\n")
ep90_path <- file.path(CONFIG$output_dir, "gantt_episodes.csv")
if (file.exists(ep90_path)) {
  ep90 <- read.csv(ep90_path, nrows = 0)
  # Phase 199: the 180-day file has 3 extra trailing columns; compare the shared first 23.
  message(glue("  Schema match vs gantt_episodes.csv (first 23 cols): {identical(names(ep90), EPISODES_SCHEMA[1:23])}"))
}
message(glue("  Episodes:  {OUTPUT_EPISODES}"))
message(glue("  Detail:    {OUTPUT_DETAIL}"))


# Phase 143 D-04: fill-rate parity check
message("\n=== Phase 143 D-04: Fill-rate parity check ===")
g90  <- readr::read_csv(file.path(CONFIG$output_dir, "gantt_episodes.csv"),     show_col_types = FALSE, col_types = readr::cols(.default = readr::col_character()))
g180 <- readr::read_csv(file.path(CONFIG$output_dir, "gantt_episodes_180.csv"), show_col_types = FALSE, col_types = readr::cols(.default = readr::col_character()))
enrich_cols <- c("drug_group","code_type","source_table",
                 "episode_dx_codes","episode_dx_categories","episode_dx_7day_confirmed")
fillrate <- function(d, col) mean(!is.na(d[[col]]) & trimws(d[[col]]) != "")
cmp <- data.frame(
  column   = enrich_cols,
  fill_90  = round(100 * vapply(enrich_cols, function(col) fillrate(g90,  col), numeric(1)), 1),
  fill_180 = round(100 * vapply(enrich_cols, function(col) fillrate(g180, col), numeric(1)), 1)
)
cmp$delta <- cmp$fill_180 - cmp$fill_90
print(cmp)
stopifnot("enrichment did not populate the 180-day file" = all(cmp$fill_180 > 0))
message("Fill-rate parity check: PASS")

# D-05: Death and Proton Therapy must be invariant across windows
ep180_check <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episodes_180_enriched.rds"))
n_death_90   <- sum(ep90_check$treatment_type  == "Death",          na.rm = TRUE)
n_death_180  <- sum(ep180_check$treatment_type == "Death",          na.rm = TRUE)
n_proton_90  <- sum(ep90_check$treatment_type  == "Proton Therapy", na.rm = TRUE)
n_proton_180 <- sum(ep180_check$treatment_type == "Proton Therapy", na.rm = TRUE)
cat(sprintf("Death:  %d at 90d, %d at 180d\n",  n_death_90,  n_death_180))
cat(sprintf("Proton: %d at 90d, %d at 180d\n", n_proton_90, n_proton_180))
if (n_death_90 != n_death_180)   warning("Death episode count changed across windows — see 143-DISCOVERY.md death anomaly section")
if (n_proton_90 != n_proton_180) stop("Proton Therapy episode count changed — this should be impossible")
