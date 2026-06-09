# ==============================================================================
# 28_episode_classification.R -- Episode-Level Cancer Linkage and Regimen Detection
# ==============================================================================
# Purpose:     Episode-level cancer linkage (ENCOUNTERID + 30-day temporal fallback)
#              with regimen detection (ABVD, BV+AVD, Nivo+AVD) for chemotherapy episodes.
#              Phase 78: Added triggering_code_description and drug_group columns.
#              Phase 91: Added 5 xlsx metadata columns (medication_name, code_type,
#              source_table, treatment_line, sct_cross_use_flag) for Gantt v2 export.
#
# Inputs:      treatment_episodes.rds, treatment_episode_detail.rds, PCORnet DIAGNOSIS,
#              code_descriptions.rds (Phase 48b), DRUG_GROUPINGS (R/00_config.R),
#              all_codes_resolved2.xlsx (Phase 91: treatment metadata)
#
# Outputs:     cache/outputs/treatment_episodes.rds (modified with cancer linkage + code enrichments + xlsx metadata),
#              output/episode_classification_audit.xlsx, output/episode_classification_audit.csv,
#              output/unresolved_codes_for_review.xlsx (Phase 91: TBD codes for SME review)
#
# Dependencies: R/00_config.R, R/utils/utils_duckdb.R, CANCER_SITE_MAP (R/00_config.R),
#               classify_codes() (R/utils/utils_cancer.R), DRUG_GROUPINGS (R/00_config.R),
#               load_xlsx_lookups() (R/utils/utils_xlsx_lookups.R, Phase 91)
#
# Requirements: Phase 61 encounter-level cancer linkage + regimen detection,
#               CANCER-03 (Phase 78): per-episode code descriptions and drug groups,
#               GANTT-01 through GANTT-05 (Phase 91): xlsx metadata enrichment
#
# WHY ENCOUNTERID linkage first: Most reliable connection between treatment and
# cancer diagnosis. Encounter context (same admission, same visit) provides
# clinical certainty vs date-only proximity.
#
# WHY 30-day temporal fallback: When ENCOUNTERID missing/unreliable, clinical
# proximity (diagnosis within 30 days before treatment) provides reasonable linkage.
# Backward-only window prevents future diagnoses linking to past treatments.
#
# WHY specific drug combinations for regimens: ABVD/BV+AVD/Nivo+AVD have distinct
# drug fingerprints (4-drug combos). Dropped-agent tolerance (AVD without bleomycin)
# handles real-world practice variation (RATHL trial standard).
#
# DECISION TRACEABILITY:
#   D-01: Primary linkage via direct ENCOUNTERID match (treatment episode ENCOUNTERID → DIAGNOSIS.ENCOUNTERID)
#   D-02: Temporal fallback: 30-day backward window from episode_start
#   D-03: Temporal fallback is backward-only (DX_DATE <= episode_start)
#   D-04: Multiple diagnoses per encounter: prefer "Hodgkin Lymphoma" over others
#   D-05: Malignant C-codes only; D-codes excluded from linkage
#   D-06: is_hodgkin derived from cancer_category, not patient-level flag
#   D-07: Second cancer confirmation for audit (7-day separation, per LINK-04)
#   D-08: Unmatched episodes get cancer_category = NA, cancer_link_method = "none"
#   D-09: Regimen detection applies only to treatment_type == "Chemotherapy"
#   D-10: Drug detection via case-insensitive substring match on drug_names
#   D-11: AVD variant (dropped bleomycin) counts as ABVD (RATHL trial standard)
#   D-12: Added-agent disqualification (ABVD + extra chemo agent → NA)
#   D-13: BV+AVD requires episode_start >= 2019-01-01; Nivo+AVD >= 2024-01-01
#   D-14: Non-matching chemotherapy episodes get regimen_label = NA
#   D-19: J-code fallback: episodes without drug_names use J9xxx billing codes from
#         triggering_codes for regimen detection (J9000=dox, J9040=bleo, J9360=vin,
#         J9130=dac, J9042=brex, J9299=nivo). Drug_names detection takes priority.
#   D-20: Added-agent disqualification for J-codes uses count of distinct J9xxx codes
#   D-15: treatment_episodes.rds modified in-place (readRDS → enrich → saveRDS)
#   D-16: Final column order: patient_id through regimen_label (was 15 columns, now 22 per Phase 91)
#   D-17: Multi-sheet audit xlsx following R/59 pattern with openxlsx2
#   D-18: Flat CSV export for episode classification results
#   D-78-05: triggering_code_description via code_descriptions.rds lookup (Phase 48b)
#   D-78-06: drug_group via DRUG_GROUPINGS named vector lookup (Phase 77)
#   D-78-07: Comma-separated parallel mapping (triggering_codes at R/28 uses commas pre-Phase 64)
#   D-78-08: Unmapped codes get NA per-code position in both new columns
#
# INPUTS:
#   - cache/outputs/treatment_episodes.rds (from R/44a + R/60)
#   - cache/outputs/treatment_episode_detail.rds (from R/44a + R/60)
#   - DuckDB DIAGNOSIS table (via get_pcornet_table)
#   - cache/outputs/code_descriptions.rds (Phase 48b: code -> description lookup)
#
# OUTPUTS:
#   - cache/outputs/treatment_episodes.rds (modified with 11 new columns: 4 Phase 61-62 + 2 Phase 78 + 5 Phase 91)
#   - output/episode_classification_audit.xlsx (5 sheets)
#   - output/episode_classification_audit.csv (flat export)
#   - output/unresolved_codes_for_review.xlsx (Phase 91: TBD codes for SME review)
#
# ==============================================================================

# SECTION 1: SETUP AND CONFIGURATION ----

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(lubridate)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_dates.R")
source("R/utils/utils_xlsx_lookups.R")  # Phase 91: xlsx metadata lookups

# Output paths
OUTPUT_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
DETAIL_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds")
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "episode_classification_audit.xlsx")
OUTPUT_CSV <- file.path(CONFIG$output_dir, "episode_classification_audit.csv")

message("=== Phase 61: Episode Classification - Cancer Linkage and Regimen Detection ===")
message("\nInputs:")
message(glue("  - {OUTPUT_RDS}"))
message(glue("  - {DETAIL_RDS}"))
message(glue("  - DuckDB DIAGNOSIS table"))
message("\nOutputs:")
message(glue("  - {OUTPUT_RDS} (enriched with 4 columns)"))
message(glue("  - {OUTPUT_XLSX}"))
message(glue("  - {OUTPUT_CSV}"))

# --- Phase 91: Load reference lookups for metadata enrichment ---
xlsx_lookups <- load_xlsx_lookups()


# --- SECTION 2: CANCER SITE CLASSIFICATION ---

# CANCER_SITE_MAP and classify_codes() provided by R/00_config.R + R/utils/utils_cancer.R

# has_drug: helper for regimen detection via resolved drug names
has_drug <- function(drug_names, drug_substring) {
  str_detect(tolower(drug_names), fixed(tolower(drug_substring)))
}

# has_jcode: helper for regimen detection via J-code billing codes in triggering_codes
# J-codes are drug-specific HCPCS codes (e.g., J9000 = doxorubicin)
has_jcode <- function(triggering_codes, jcode) {
  str_detect(triggering_codes, fixed(jcode))
}

# Count distinct J9xxx codes in triggering_codes (for added-agent disqualification)
count_j9_codes <- function(triggering_codes) {
  codes <- str_split(triggering_codes, ",")
  sapply(codes, function(x) sum(str_detect(x, "^J9\\d")))
}


# --- SECTION 3: LOAD DATA ---

message("\n--- Loading treatment episodes and detail ---")

# SAFE-01: Validate input RDS artifacts
assert_rds_exists(OUTPUT_RDS, script_name = "R/28")
assert_rds_exists(DETAIL_RDS, script_name = "R/28")

episodes <- readRDS(OUTPUT_RDS)
message(glue("  Loaded treatment_episodes.rds: {nrow(episodes)} episodes"))

episode_detail <- readRDS(DETAIL_RDS)
message(glue("  Loaded treatment_episode_detail.rds: {nrow(episode_detail)} detail rows"))

# SAFE-02: Validate data frame structure
assert_df_valid(episodes, "treatment_episodes",
                required_cols = c("patient_id", "treatment_type", "episode_number",
                                  "episode_start", "episode_stop"),
                script_name = "R/28")
assert_df_valid(episode_detail, "treatment_episode_detail",
                required_cols = c("patient_id", "treatment_type", "treatment_date"),
                script_name = "R/28")

USE_DUCKDB <- TRUE
open_pcornet_con()


# --- SECTION 4: CANCER LINKAGE ---

message("\n--- Cancer Linkage: ENCOUNTERID + Temporal Fallback ---")

# Step 4a: Extract unique encounter IDs from episodes
episode_encounters <- episodes %>%
  filter(!is.na(encounter_ids) & encounter_ids != "") %>%
  mutate(encounter_ids_list = str_split(encounter_ids, ",")) %>%
  tidyr::unnest(cols = encounter_ids_list) %>%
  filter(!is.na(encounter_ids_list) & encounter_ids_list != "") %>%
  select(patient_id, treatment_type, episode_number, ENCOUNTERID = encounter_ids_list)

message(glue("  Episode encounters extracted: {nrow(episode_encounters)} encounter IDs from {n_distinct(paste(episode_encounters$patient_id, episode_encounters$treatment_type, episode_encounters$episode_number))} episodes"))

# Step 4b: Query DIAGNOSIS table via DuckDB
dx_data <- get_pcornet_table("DIAGNOSIS") %>%
  select(ID, ENCOUNTERID, DX, DX_DATE, DX_TYPE, PDX) %>%
  collect() %>%
  mutate(DX_DATE = parse_pcornet_date(DX_DATE)) %>%
  filter(str_sub(DX, 1, 1) == "C") %>%
  filter(!is.na(DX_DATE))

message(glue("  DIAGNOSIS query: {nrow(dx_data)} C-code rows with DX_DATE"))

# Step 4c: Direct ENCOUNTERID match (D-01)
dx_with_encounter <- dx_data %>%
  filter(!is.na(ENCOUNTERID) & ENCOUNTERID != "")

encounter_linked <- episode_encounters %>%
  inner_join(dx_with_encounter, by = "ENCOUNTERID", relationship = "many-to-many") %>%
  mutate(
    prefix = str_sub(DX, 1, 3),
    cancer_category = classify_codes(DX)
  ) %>%
  group_by(patient_id, treatment_type, episode_number) %>%
  arrange(desc(cancer_category == "Hodgkin Lymphoma"), .by_group = TRUE) %>%
  slice(1) %>%
  ungroup() %>%
  mutate(cancer_link_method = "encounter_id") %>%
  select(patient_id, treatment_type, episode_number, cancer_category, cancer_link_method)

n_encounter_linked <- nrow(encounter_linked)
message(glue("  Direct ENCOUNTERID match: {n_encounter_linked} episodes linked"))

# Step 4d: Temporal fallback for unlinked episodes (D-02, D-03)
unlinked_episodes <- episodes %>%
  anti_join(encounter_linked, by = c("patient_id", "treatment_type", "episode_number"))

message(glue("  Unlinked episodes for temporal fallback: {nrow(unlinked_episodes)}"))

# Get all diagnosis rows for unlinked patients
unlinked_patients <- unique(unlinked_episodes$patient_id)
dx_for_unlinked <- dx_data %>%
  filter(ID %in% unlinked_patients)

# Temporal matching
temporal_linked <- unlinked_episodes %>%
  left_join(dx_for_unlinked, by = c("patient_id" = "ID"), relationship = "many-to-many") %>%
  filter(!is.na(DX_DATE)) %>%
  filter(DX_DATE <= episode_start) %>%
  mutate(days_before = as.numeric(episode_start - DX_DATE)) %>%
  filter(days_before <= 30) %>%
  mutate(
    prefix = str_sub(DX, 1, 3),
    cancer_category = classify_codes(DX)
  ) %>%
  group_by(patient_id, treatment_type, episode_number) %>%
  arrange(days_before, desc(cancer_category == "Hodgkin Lymphoma"), .by_group = TRUE) %>%
  slice(1) %>%
  ungroup() %>%
  mutate(cancer_link_method = "closest_date") %>%
  select(patient_id, treatment_type, episode_number, cancer_category, cancer_link_method)

n_temporal_linked <- nrow(temporal_linked)
message(glue("  Temporal fallback (30-day backward): {n_temporal_linked} episodes linked"))

# Step 4e: Combine and merge back to episodes
cancer_linkage <- bind_rows(encounter_linked, temporal_linked)

# Drop columns from prior run to avoid .x/.y suffixes on re-run
cols_from_linkage <- intersect(names(cancer_linkage), names(episodes))
cols_from_linkage <- setdiff(cols_from_linkage, c("patient_id", "treatment_type", "episode_number"))
if (length(cols_from_linkage) > 0) {
  episodes <- episodes %>% select(-all_of(cols_from_linkage))
}

episodes <- episodes %>%
  left_join(cancer_linkage, by = c("patient_id", "treatment_type", "episode_number")) %>%
  mutate(
    cancer_link_method = if_else(is.na(cancer_link_method), "none", cancer_link_method),
    is_hodgkin = (!is.na(cancer_category) & cancer_category == "Hodgkin Lymphoma")
  )

n_none <- sum(episodes$cancer_link_method == "none")
message(glue("  Linkage summary: {n_encounter_linked} encounter_id, {n_temporal_linked} closest_date, {n_none} none"))

# Step 4f: Second cancer confirmation (D-07, LINK-04) - for audit only
all_dx_by_patient <- dx_data %>%
  mutate(
    prefix = str_sub(DX, 1, 3),
    cancer_category = classify_codes(DX)
  ) %>%
  filter(!is.na(cancer_category) & cancer_category != "Hodgkin Lymphoma") %>%
  group_by(ID, cancer_category) %>%
  summarise(
    n_diagnoses = n(),
    min_dx_date = min(DX_DATE, na.rm = TRUE),
    max_dx_date = max(DX_DATE, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(days_span = as.numeric(max_dx_date - min_dx_date)) %>%
  filter(days_span >= 7)

n_confirmed_second <- nrow(all_dx_by_patient)
message(glue("  Second cancer confirmation: {n_confirmed_second} patient-cancer pairs with 2+ diagnoses 7+ days apart"))

confirmed_second_cancers <- all_dx_by_patient

close_pcornet_con()


# --- SECTION 5: REGIMEN DETECTION ---

message("\n--- Regimen Detection: ABVD, BV+AVD, Nivo+AVD ---")

# Filter to chemotherapy episodes only
chemo_episodes <- episodes %>%
  filter(treatment_type == "Chemotherapy") %>%
  filter(!is.na(drug_names) & drug_names != "")

message(glue("  Chemotherapy episodes with drug names: {nrow(chemo_episodes)} / {sum(episodes$treatment_type == 'Chemotherapy')} total chemo"))

# Step 5b: Drug detection flags (D-10)
chemo_regimens <- chemo_episodes %>%
  mutate(
    has_dox = has_drug(drug_names, "doxorubicin"),
    has_bleo = has_drug(drug_names, "bleomycin"),
    has_vin = has_drug(drug_names, "vinblastine"),
    has_dac = has_drug(drug_names, "dacarbazine"),
    has_brex = has_drug(drug_names, "brentuximab"),
    has_nivo = has_drug(drug_names, "nivolumab")
  )

# Step 5c: Count unique drugs for added-agent disqualification (D-12)
chemo_regimens <- chemo_regimens %>%
  mutate(
    n_unique_drugs = if_else(
      drug_names == "" | is.na(drug_names),
      0L,
      as.integer(str_count(drug_names, ",") + 1)
    )
  )

# Step 5d: Regimen classification with case_when (D-10, D-11, D-12, D-13, D-14)
chemo_regimens <- chemo_regimens %>%
  mutate(
    regimen_label = case_when(
      # BV+AVD: brentuximab + dox + vin + dac, no bleomycin, exactly 4 drugs, post-2019 (D-10, D-13)
      has_brex & has_dox & has_vin & has_dac & !has_bleo & n_unique_drugs == 4L &
        episode_start >= as.Date("2019-01-01") ~ "BV+AVD",

      # Nivo+AVD: nivolumab + dox + vin + dac, no bleomycin, exactly 4 drugs, post-2024 (D-10, D-13)
      has_nivo & has_dox & has_vin & has_dac & !has_bleo & n_unique_drugs == 4L &
        episode_start >= as.Date("2024-01-01") ~ "Nivo+AVD",

      # ABVD (full): all 4 drugs, no brentuximab, no nivolumab, max 4 drugs (D-10, D-12)
      has_dox & has_bleo & has_vin & has_dac & !has_brex & !has_nivo & n_unique_drugs <= 4L ~ "ABVD",

      # AVD variant (dropped bleomycin): dox + vin + dac, no bleo, no brentuximab, no nivolumab,
      # max 3 drugs (D-11 — RATHL trial standard of care)
      has_dox & has_vin & has_dac & !has_bleo & !has_brex & !has_nivo & n_unique_drugs <= 3L ~ "ABVD",

      # Non-matching chemotherapy episodes (D-14)
      TRUE ~ NA_character_
    )
  ) %>%
  select(-starts_with("has_"), -n_unique_drugs)

# Step 5e: Merge drug_names-based regimen_label back to full episodes
regimen_assignments <- chemo_regimens %>%
  select(patient_id, treatment_type, episode_number, regimen_label)

# Drop regimen_label from prior run to avoid .x/.y suffixes on re-run
if ("regimen_label" %in% names(episodes)) {
  episodes <- episodes %>% select(-regimen_label)
}

episodes <- episodes %>%
  left_join(regimen_assignments, by = c("patient_id", "treatment_type", "episode_number"))

n_drug_abvd <- sum(episodes$regimen_label == "ABVD", na.rm = TRUE)
n_drug_bv <- sum(episodes$regimen_label == "BV+AVD", na.rm = TRUE)
n_drug_nivo <- sum(episodes$regimen_label == "Nivo+AVD", na.rm = TRUE)
n_drug_total <- n_drug_abvd + n_drug_bv + n_drug_nivo

message(glue("  Drug-name regimen detection: {n_drug_abvd} ABVD, {n_drug_bv} BV+AVD, {n_drug_nivo} Nivo+AVD ({n_drug_total} total)"))

# --- Step 5f: J-code fallback for episodes still without regimen_label ---
# J-codes are drug-specific HCPCS billing codes (J9000=doxorubicin, J9040=bleomycin, etc.)
# These appear in triggering_codes for ~42% of chemo episodes that lack resolved drug_names.

message("\n  J-code fallback for unclassified chemo episodes...")

chemo_no_regimen <- episodes %>%
  filter(treatment_type == "Chemotherapy") %>%
  filter(is.na(regimen_label)) %>%
  filter(!is.na(triggering_codes) & triggering_codes != "") %>%
  filter(str_detect(triggering_codes, "J9"))

message(glue("  Chemo episodes without regimen but with J9 codes: {nrow(chemo_no_regimen)}"))

if (nrow(chemo_no_regimen) > 0) {
  jcode_regimens <- chemo_no_regimen %>%
    mutate(
      has_dox = has_jcode(triggering_codes, "J9000"),
      has_bleo = has_jcode(triggering_codes, "J9040"),
      has_vin = has_jcode(triggering_codes, "J9360"),
      has_dac = has_jcode(triggering_codes, "J9130"),
      has_brex = has_jcode(triggering_codes, "J9042"),
      has_nivo = has_jcode(triggering_codes, "J9299"),
      n_j9_codes = count_j9_codes(triggering_codes)
    ) %>%
    mutate(
      jcode_regimen = case_when(
        # BV+AVD via J-codes: brentuximab + dox + vin + dac, no bleomycin, post-2019
        has_brex & has_dox & has_vin & has_dac & !has_bleo & n_j9_codes == 4L &
          episode_start >= as.Date("2019-01-01") ~ "BV+AVD",

        # Nivo+AVD via J-codes: nivolumab + dox + vin + dac, no bleomycin, post-2024
        has_nivo & has_dox & has_vin & has_dac & !has_bleo & n_j9_codes == 4L &
          episode_start >= as.Date("2024-01-01") ~ "Nivo+AVD",

        # ABVD (full) via J-codes: all 4 ABVD drugs, no brentuximab, no nivolumab, max 4 J9 codes
        has_dox & has_bleo & has_vin & has_dac & !has_brex & !has_nivo & n_j9_codes <= 4L ~ "ABVD",

        # AVD variant via J-codes: dox + vin + dac, no bleo, no brex, no nivo, max 3 J9 codes
        has_dox & has_vin & has_dac & !has_bleo & !has_brex & !has_nivo & n_j9_codes <= 3L ~ "ABVD",
        TRUE ~ NA_character_
      )
    ) %>%
    filter(!is.na(jcode_regimen)) %>%
    select(patient_id, treatment_type, episode_number, jcode_regimen)

  n_jcode_abvd <- sum(jcode_regimens$jcode_regimen == "ABVD")
  n_jcode_bv <- sum(jcode_regimens$jcode_regimen == "BV+AVD")
  n_jcode_nivo <- sum(jcode_regimens$jcode_regimen == "Nivo+AVD")
  n_jcode_total <- nrow(jcode_regimens)

  message(glue("  J-code regimen detection: {n_jcode_abvd} ABVD, {n_jcode_bv} BV+AVD, {n_jcode_nivo} Nivo+AVD ({n_jcode_total} total)"))

  # Merge J-code regimens into episodes (only where regimen_label is still NA)
  if (nrow(jcode_regimens) > 0) {
    episodes <- episodes %>%
      left_join(jcode_regimens, by = c("patient_id", "treatment_type", "episode_number")) %>%
      mutate(
        regimen_label = if_else(is.na(regimen_label) & !is.na(jcode_regimen), jcode_regimen, regimen_label)
      ) %>%
      select(-jcode_regimen)
  }
} else {
  message("  No chemo episodes with J9 codes found for fallback detection.")
}

# --- Step 5g: Final regimen summary ---
n_abvd <- sum(episodes$regimen_label == "ABVD", na.rm = TRUE)
n_bv <- sum(episodes$regimen_label == "BV+AVD", na.rm = TRUE)
n_nivo <- sum(episodes$regimen_label == "Nivo+AVD", na.rm = TRUE)
n_total_labeled <- n_abvd + n_bv + n_nivo
n_unclassified_chemo <- sum(episodes$treatment_type == "Chemotherapy" & is.na(episodes$regimen_label))
n_non_chemo <- sum(episodes$treatment_type != "Chemotherapy")

message(glue("\n  Final regimen detection (drug_names + J-code fallback):"))
message(glue("    ABVD: {n_abvd} (drug_names: {n_drug_abvd}, J-code: {n_abvd - n_drug_abvd})"))
message(glue("    BV+AVD: {n_bv} (drug_names: {n_drug_bv}, J-code: {n_bv - n_drug_bv})"))
message(glue("    Nivo+AVD: {n_nivo} (drug_names: {n_drug_nivo}, J-code: {n_nivo - n_drug_nivo})"))
message(glue("    Total labeled: {n_total_labeled} / {n_total_labeled + n_unclassified_chemo} chemo ({round(n_total_labeled / (n_total_labeled + n_unclassified_chemo) * 100, 1)}%)"))
message(glue("    Unclassified chemo: {n_unclassified_chemo}, Non-chemo: {n_non_chemo}"))


# --- SECTION 5B: CODE DESCRIPTION AND DRUG GROUP MAPPING ----

message("\n--- Adding triggering code descriptions and drug groups ---")

# Step 5B-1: Load code_descriptions.rds
DESCRIPTIONS_RDS <- file.path(CONFIG$cache$outputs_dir, "code_descriptions.rds")
code_descriptions <- NULL
if (file.exists(DESCRIPTIONS_RDS)) {
  code_descriptions <- readRDS(DESCRIPTIONS_RDS)
  message(glue("  Loaded {length(code_descriptions)} code descriptions"))
} else {
  message("  WARNING: code_descriptions.rds not found. triggering_code_description will be NA.")
}

# Step 5B-2: Define mapping helpers (D-78-05, D-78-06, D-78-07, D-78-08)

# lookup_description: map single code to human-readable name from code_descriptions.rds
lookup_description <- function(code) {
  if (is.null(code_descriptions) || is.na(code) || code == "") return(NA_character_)
  if (code %in% names(code_descriptions)) return(code_descriptions[[code]])
  return(NA_character_)  # D-78-08: unmapped codes get NA
}

# lookup_drug_group: map single code to category from DRUG_GROUPINGS
lookup_drug_group <- function(code) {
  if (is.na(code) || code == "") return(NA_character_)
  if (code %in% names(DRUG_GROUPINGS)) return(DRUG_GROUPINGS[[code]])
  return(NA_character_)  # D-78-08: unmapped codes get NA
}

# map_codes_to_descriptions: map comma-separated codes to comma-separated descriptions (D-78-07)
# NOTE: triggering_codes at R/28 stage uses commas (pre-Phase 64 cleanup to semicolons)
map_codes_to_descriptions <- function(codes_str) {
  if (is.na(codes_str) || codes_str == "") return(NA_character_)
  codes <- str_split(codes_str, ",")[[1]]
  descriptions <- sapply(codes, lookup_description, USE.NAMES = FALSE)
  paste(descriptions, collapse = ",")
}

# map_codes_to_drug_groups: map comma-separated codes to comma-separated groups (D-78-07)
map_codes_to_drug_groups <- function(codes_str) {
  if (is.na(codes_str) || codes_str == "") return(NA_character_)
  codes <- str_split(codes_str, ",")[[1]]
  groups <- sapply(codes, lookup_drug_group, USE.NAMES = FALSE)
  paste(groups, collapse = ",")
}

# Step 5B-3: Apply mapping to episodes
episodes <- episodes %>%
  mutate(
    triggering_code_description = sapply(triggering_codes, map_codes_to_descriptions, USE.NAMES = FALSE),
    drug_group = sapply(triggering_codes, map_codes_to_drug_groups, USE.NAMES = FALSE)
  )

# Step 5B-4: Log mapping results
n_with_desc <- sum(!is.na(episodes$triggering_code_description) & episodes$triggering_code_description != "", na.rm = TRUE)
n_with_group <- sum(!is.na(episodes$drug_group) & episodes$drug_group != "", na.rm = TRUE)
message(glue("  triggering_code_description populated: {n_with_desc}/{nrow(episodes)} episodes"))
message(glue("  drug_group populated: {n_with_group}/{nrow(episodes)} episodes"))


# --- SECTION 5C: XLSX METADATA ENRICHMENT (Phase 91, GANTT-01 through GANTT-05) ---

message("\n--- Adding xlsx metadata (medication names, code types, source tables, treatment line, cross-use flags) ---")

# Step 5C-1: Define helper functions for metadata mapping

# map_codes_to_xlsx_metadata: map comma-separated triggering_codes to comma-separated metadata
# Matches triggering_codes positional order (per D-04)
map_codes_to_xlsx_metadata <- function(codes_str, lookup_vec) {
  if (is.na(codes_str) || codes_str == "") return(NA_character_)
  codes <- str_split(codes_str, ",")[[1]]
  values <- sapply(codes, function(c) {
    val <- lookup_vec[c]
    if (is.null(val) || is.na(val)) NA_character_ else val
  }, USE.NAMES = FALSE)
  paste(values, collapse = ",")
}

# aggregate_treatment_line: aggregate F/S/E/N labels with priority F > S > E > N (per D-03)
# Returns single value per episode, NOT a parallel list (per D-05)
aggregate_treatment_line <- function(codes_str, lookup_vec) {
  if (is.na(codes_str) || codes_str == "") return(NA_character_)
  codes <- str_split(codes_str, ",")[[1]]
  labels <- sapply(codes, function(c) {
    val <- lookup_vec[c]
    if (is.null(val) || is.na(val)) NA_character_ else val
  }, USE.NAMES = FALSE)
  labels <- labels[!is.na(labels)]
  if (length(labels) == 0) return(NA_character_)
  # Priority: F > S > E > N (per D-03)
  if ("F" %in% labels) return("F")
  if ("S" %in% labels) return("S")
  if ("E" %in% labels) return("E")
  if ("N" %in% labels) return("N")
  return(NA_character_)
}

# aggregate_cross_use_flag: any-positive flag logic (per D-09)
# Most specific non-NA flag wins
aggregate_cross_use_flag <- function(codes_str, lookup_vec) {
  if (is.na(codes_str) || codes_str == "") return(NA_character_)
  codes <- str_split(codes_str, ",")[[1]]
  flags <- sapply(codes, function(c) {
    val <- lookup_vec[c]
    if (is.null(val) || is.na(val)) NA_character_ else val
  }, USE.NAMES = FALSE)
  flags <- flags[!is.na(flags) & flags != ""]
  if (length(flags) > 0) return(flags[1])
  return(NA_character_)
}

# aggregate_immuno_confidence: any-questionable flag logic (per D-12, Phase 93)
# If ANY triggering code in the episode is questionable, the episode gets the flag
aggregate_immuno_confidence <- function(codes_str, lookup_vec) {
  if (is.na(codes_str) || codes_str == "") return(NA_character_)
  codes <- str_split(codes_str, ",")[[1]]
  flags <- sapply(codes, function(c) {
    val <- lookup_vec[c]
    if (is.null(val) || is.na(val)) NA_character_ else val
  }, USE.NAMES = FALSE)
  flags <- flags[!is.na(flags) & flags != ""]
  if (length(flags) > 0) return(flags[1])
  return(NA_character_)
}

# Step 5C-2: Record pre-enrichment row count for validation
pre_enrichment_count <- nrow(episodes)

# Step 5C-3: Apply 5 new columns via mutate (per D-04 and D-05)
episodes <- episodes %>%
  mutate(
    # GANTT-01: Medication names (parallel comma list per D-04)
    medication_name = sapply(triggering_codes, map_codes_to_xlsx_metadata,
                             lookup_vec = xlsx_lookups$medications, USE.NAMES = FALSE),

    # GANTT-02: Code types (parallel comma list per D-04)
    code_type = sapply(triggering_codes, map_codes_to_xlsx_metadata,
                       lookup_vec = xlsx_lookups$code_types, USE.NAMES = FALSE),

    # GANTT-03: Source tables (parallel comma list per D-04)
    source_table = sapply(triggering_codes, map_codes_to_xlsx_metadata,
                          lookup_vec = xlsx_lookups$source_tables, USE.NAMES = FALSE),

    # GANTT-04: Treatment line (single aggregated value per D-03, D-05)
    treatment_line = sapply(triggering_codes, aggregate_treatment_line,
                            lookup_vec = xlsx_lookups$line_labels, USE.NAMES = FALSE),

    # GANTT-05: Cross-use flag (any-positive aggregation per D-09)
    sct_cross_use_flag = sapply(triggering_codes, aggregate_cross_use_flag,
                                lookup_vec = xlsx_lookups$cross_use_flags, USE.NAMES = FALSE)
  )

# Step 5C-4: Validate row count preserved (Pitfall 1 prevention)
assert_true(nrow(episodes) == pre_enrichment_count,
            .var.name = glue("[R/28 ERROR] Enrichment changed row count: {pre_enrichment_count} -> {nrow(episodes)}"))

# Step 5C-5: Log enrichment results
n_with_med <- sum(!is.na(episodes$medication_name) & episodes$medication_name != "", na.rm = TRUE)
n_with_line <- sum(!is.na(episodes$treatment_line) & episodes$treatment_line != "", na.rm = TRUE)
n_with_cross <- sum(!is.na(episodes$sct_cross_use_flag) & episodes$sct_cross_use_flag != "", na.rm = TRUE)
message(glue("  medication_name populated: {n_with_med}/{nrow(episodes)} episodes"))
message(glue("  code_type populated: {sum(!is.na(episodes$code_type))}/{nrow(episodes)} episodes"))
message(glue("  source_table populated: {sum(!is.na(episodes$source_table))}/{nrow(episodes)} episodes"))
message(glue("  treatment_line populated: {n_with_line}/{nrow(episodes)} episodes"))
message(glue("  sct_cross_use_flag populated: {n_with_cross}/{nrow(episodes)} episodes"))


# --- Step 5D: Phase 93 -- Temporal context + confidence flags (IMMU-01, IMMU-02) ---
# These are annotations only -- treatment_type stays unchanged (D-13)
# Aggregation rules: is_sct_conditioning_context = boolean annotation on Chemotherapy only
# immuno_confidence = any-positive categorical flag from QUESTIONABLE_IMMUNO_CODES

message("\n--- Phase 93: Temporal context and confidence flag enrichment ---")

# Step 5D-1: Compute SCT conditioning temporal context (D-01, D-02, D-03, D-04)
# For each patient, find SCT episode start dates
sct_dates <- episodes %>%
  filter(treatment_type == "Stem Cell Transplant") %>%
  select(patient_id, sct_start = episode_start)

n_sct_patients <- n_distinct(sct_dates$patient_id)
message(glue("  Found {nrow(sct_dates)} SCT episodes across {n_sct_patients} patients"))

# For chemotherapy episodes, check if any start within 30 days before an SCT episode (D-01)
if (nrow(sct_dates) > 0) {
  chemo_context <- episodes %>%
    filter(treatment_type == "Chemotherapy") %>%
    select(patient_id, episode_number, episode_start) %>%
    left_join(sct_dates, by = "patient_id", relationship = "many-to-many") %>%
    mutate(
      days_to_sct = as.numeric(sct_start - episode_start),
      is_within_window = !is.na(days_to_sct) & days_to_sct >= 0 & days_to_sct <= 30
    ) %>%
    group_by(patient_id, episode_number) %>%
    summarise(
      is_sct_conditioning_context = any(is_within_window, na.rm = TRUE),
      days_to_nearest_sct = if_else(
        any(!is.na(days_to_sct) & days_to_sct >= 0),
        as.integer(min(days_to_sct[days_to_sct >= 0], na.rm = TRUE)),
        NA_integer_
      ),
      .groups = "drop"
    )
} else {
  # No SCT episodes in cohort -- all chemotherapy episodes get FALSE
  chemo_context <- episodes %>%
    filter(treatment_type == "Chemotherapy") %>%
    select(patient_id, episode_number) %>%
    mutate(
      is_sct_conditioning_context = FALSE,
      days_to_nearest_sct = NA_integer_
    )
}

# Step 5D-2: Join temporal context back to episodes
# Pre-join row count for validation
pre_phase93_count <- nrow(episodes)

episodes <- episodes %>%
  left_join(chemo_context, by = c("patient_id", "episode_number")) %>%
  mutate(
    # D-04: NA for non-chemotherapy episodes; FALSE if chemo but no nearby SCT
    is_sct_conditioning_context = case_when(
      treatment_type != "Chemotherapy" ~ NA,
      is.na(is_sct_conditioning_context) ~ FALSE,
      TRUE ~ is_sct_conditioning_context
    ),
    # D-03: days_to_nearest_sct is RDS-only (not exported to Gantt CSVs)
    days_to_nearest_sct = case_when(
      treatment_type != "Chemotherapy" ~ NA_integer_,
      TRUE ~ days_to_nearest_sct
    )
  )

# Validate row count preserved (Pitfall 2 prevention)
assert_true(nrow(episodes) == pre_phase93_count,
            .var.name = glue("[R/28 ERROR] Phase 93 temporal join changed row count: {pre_phase93_count} -> {nrow(episodes)}"))

# Step 5D-3: Compute immuno_confidence from QUESTIONABLE_IMMUNO_CODES (D-09, D-10, D-12)
episodes <- episodes %>%
  mutate(
    immuno_confidence = sapply(triggering_codes, aggregate_immuno_confidence,
                               lookup_vec = QUESTIONABLE_IMMUNO_CODES, USE.NAMES = FALSE)
  )

# Step 5D-4: Log Phase 93 enrichment results
n_conditioning <- sum(episodes$is_sct_conditioning_context == TRUE, na.rm = TRUE)
n_confidence <- sum(!is.na(episodes$immuno_confidence), na.rm = TRUE)
n_vitamin <- sum(episodes$immuno_confidence == "questionable-vitamin", na.rm = TRUE)
n_cart <- sum(episodes$immuno_confidence == "questionable-CAR-T vs immunotherapy", na.rm = TRUE)
message(glue("  Conditioning context: {n_conditioning} chemo episodes within 30d before SCT"))
message(glue("  Confidence flags: {n_confidence} episodes ({n_vitamin} vitamin, {n_cart} CAR-T)"))


# --- SECTION 6: SAVE ENRICHED RDS ---

message("\n--- Saving enriched treatment_episodes.rds ---")

# Final column order (was 22 columns Phase 91, now 25 columns per Phase 93)
episodes <- episodes %>%
  select(
    patient_id, treatment_type, episode_number, episode_start, episode_stop,
    episode_length_days, distinct_dates_in_episode, historical_flag,
    triggering_codes, encounter_ids, drug_names,
    cancer_category, cancer_link_method, is_hodgkin, regimen_label,
    triggering_code_description, drug_group,
    medication_name, code_type, source_table, treatment_line, sct_cross_use_flag,
    # --- Phase 93: Temporal context + confidence flags (IMMU-01, IMMU-02) ---
    is_sct_conditioning_context, days_to_nearest_sct, immuno_confidence
  )

saveRDS(episodes, OUTPUT_RDS)
message(glue("  Saved enriched treatment_episodes.rds: {nrow(episodes)} episodes, {ncol(episodes)} columns"))

# Verify column presence
stopifnot(all(c("cancer_category", "cancer_link_method", "is_hodgkin", "regimen_label",
                "triggering_code_description", "drug_group",
                "medication_name", "code_type", "source_table", "treatment_line",
                "sct_cross_use_flag", "is_sct_conditioning_context", "days_to_nearest_sct",
                "immuno_confidence") %in% names(episodes)))


# --- SECTION 6B: TBD CODE EXPORT FOR SME REVIEW (Phase 91, D-07) ---

message("\n--- Exporting unresolved TBD codes for SME review ---")

# Identify codes with TBD/questionable classification
# These are codes in xlsx where treatment_line or cross_use_flag suggest unresolved status
unresolved_codes <- tibble(
  code = character(),
  current_category = character(),
  medication_name = character(),
  classification_question = character()
)

# Check for any codes where xlsx metadata suggests TBD status
all_xlsx_codes <- names(xlsx_lookups$medications)
for (code in all_xlsx_codes) {
  line_val <- xlsx_lookups$line_labels[code]
  cross_val <- xlsx_lookups$cross_use_flags[code]
  med_name <- xlsx_lookups$medications[code]
  category <- if (code %in% names(DRUG_GROUPINGS)) DRUG_GROUPINGS[code] else NA_character_

  is_tbd <- FALSE
  question <- ""

  if (!is.na(line_val) && str_detect(line_val, regex("TBD|\\?", ignore_case = TRUE))) {
    is_tbd <- TRUE
    question <- paste0(question, "Treatment line unresolved (current: ", line_val, "). ")
  }
  if (!is.na(cross_val) && str_detect(cross_val, regex("TBD|\\?", ignore_case = TRUE))) {
    is_tbd <- TRUE
    question <- paste0(question, "Cross-use classification unresolved (current: ", cross_val, "). ")
  }

  if (is_tbd) {
    unresolved_codes <- bind_rows(unresolved_codes, tibble(
      code = code,
      current_category = as.character(category),
      medication_name = as.character(med_name),
      classification_question = str_trim(question)
    ))
  }
}

if (nrow(unresolved_codes) > 0) {
  tbd_wb <- wb_workbook()
  tbd_wb$add_worksheet("Unresolved Codes")
  tbd_wb$add_data(sheet = "Unresolved Codes", x = unresolved_codes, start_row = 1)
  tbd_wb$set_col_widths(sheet = "Unresolved Codes", cols = 1:4, widths = "auto")

  tbd_output <- file.path(CONFIG$output_dir, "unresolved_codes_for_review.xlsx")
  tbd_wb$save(tbd_output)
  message(glue("  Exported {nrow(unresolved_codes)} unresolved codes to {tbd_output}"))
} else {
  message("  No unresolved TBD codes found in xlsx lookups")
}


# --- SECTION 7: AUDIT OUTPUT ---

message("\n--- Creating audit workbook ---")

wb <- wb_workbook()

# ---------- SHEET 1: Linkage Summary ----------

wb$add_worksheet("Linkage Summary")

# Title row (A1)
wb$add_data(
  sheet = "Linkage Summary", x = "Episode Classification Audit",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Linkage Summary", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Linkage Summary", dims = "A1:C1")

# Subtitle row (A2)
subtitle <- glue("Generated: {Sys.Date()} | Total episodes: {nrow(episodes)}")
wb$add_data(sheet = "Linkage Summary", x = subtitle, start_row = 2, start_col = 1)
wb$add_font(
  sheet = "Linkage Summary", dims = "A2",
  name = "Calibri", size = 10, color = wb_color("FF6B7280")
)
wb$merge_cells(sheet = "Linkage Summary", dims = "A2:C2")

# Summary table starting row 4
linkage_summary <- tibble(
  Metric = c(
    "Total episodes",
    "Linked via ENCOUNTERID",
    "Linked via temporal fallback",
    "Unlinked"
  ),
  Count = c(
    nrow(episodes),
    n_encounter_linked,
    n_temporal_linked,
    n_none
  ),
  Percent = c(
    100.0,
    round(100 * n_encounter_linked / nrow(episodes), 1),
    round(100 * n_temporal_linked / nrow(episodes), 1),
    round(100 * n_none / nrow(episodes), 1)
  )
)

wb$add_data(sheet = "Linkage Summary", x = linkage_summary, start_row = 4, start_col = 1)

# Header styling
wb$add_font(
  sheet = "Linkage Summary", dims = "A4:C4",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)
wb$add_fill(
  sheet = "Linkage Summary", dims = "A4:C4",
  color = wb_color("FF1F2937")
)

# Freeze and autofit
wb$freeze_pane(sheet = "Linkage Summary", first_active_row = 5)
wb$set_col_widths(sheet = "Linkage Summary", cols = 1:3, widths = "auto")


# ---------- SHEET 2: Cancer Categories ----------

wb$add_worksheet("Cancer Categories")

cancer_category_freq <- episodes %>%
  group_by(cancer_category) %>%
  summarise(
    n_episodes = n(),
    n_patients = n_distinct(patient_id),
    .groups = "drop"
  ) %>%
  mutate(
    pct_episodes = round(100 * n_episodes / nrow(episodes), 1),
    pct_patients = round(100 * n_patients / n_distinct(episodes$patient_id), 1)
  ) %>%
  arrange(desc(n_episodes))

# Title
wb$add_data(
  sheet = "Cancer Categories", x = "Cancer Category Distribution",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Cancer Categories", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Cancer Categories", dims = "A1:E1")

# Data
wb$add_data(sheet = "Cancer Categories", x = cancer_category_freq, start_row = 3, start_col = 1)

# Header styling
wb$add_font(
  sheet = "Cancer Categories", dims = "A3:E3",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)
wb$add_fill(
  sheet = "Cancer Categories", dims = "A3:E3",
  color = wb_color("FF1F2937")
)

wb$freeze_pane(sheet = "Cancer Categories", first_active_row = 4)
wb$set_col_widths(sheet = "Cancer Categories", cols = 1:5, widths = "auto")


# ---------- SHEET 3: Regimen Distribution ----------

wb$add_worksheet("Regimen Distribution")

regimen_freq <- episodes %>%
  filter(treatment_type == "Chemotherapy") %>%
  group_by(regimen_label) %>%
  summarise(
    n_episodes = n(),
    n_patients = n_distinct(patient_id),
    .groups = "drop"
  ) %>%
  mutate(
    pct_chemo_episodes = round(100 * n_episodes / sum(episodes$treatment_type == "Chemotherapy"), 1)
  ) %>%
  arrange(desc(n_episodes))

# Title
wb$add_data(
  sheet = "Regimen Distribution", x = "Chemotherapy Regimen Distribution",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Regimen Distribution", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Regimen Distribution", dims = "A1:D1")

# Data
wb$add_data(sheet = "Regimen Distribution", x = regimen_freq, start_row = 3, start_col = 1)

# Header styling
wb$add_font(
  sheet = "Regimen Distribution", dims = "A3:D3",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)
wb$add_fill(
  sheet = "Regimen Distribution", dims = "A3:D3",
  color = wb_color("FF1F2937")
)

wb$freeze_pane(sheet = "Regimen Distribution", first_active_row = 4)
wb$set_col_widths(sheet = "Regimen Distribution", cols = 1:4, widths = "auto")


# ---------- SHEET 4: Second Cancer Confirmation ----------

wb$add_worksheet("Second Cancer Confirmation")

# Title
wb$add_data(
  sheet = "Second Cancer Confirmation", x = "Second Cancer Confirmation (7-day separation)",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Second Cancer Confirmation", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Second Cancer Confirmation", dims = "A1:F1")

# Data
second_cancer_export <- confirmed_second_cancers %>%
  rename(patient_id = ID) %>%
  select(patient_id, cancer_category, n_diagnoses, min_dx_date, max_dx_date, days_span)

wb$add_data(sheet = "Second Cancer Confirmation", x = second_cancer_export, start_row = 3, start_col = 1)

# Header styling
wb$add_font(
  sheet = "Second Cancer Confirmation", dims = "A3:F3",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)
wb$add_fill(
  sheet = "Second Cancer Confirmation", dims = "A3:F3",
  color = wb_color("FF1F2937")
)

wb$freeze_pane(sheet = "Second Cancer Confirmation", first_active_row = 4)
wb$set_col_widths(sheet = "Second Cancer Confirmation", cols = 1:6, widths = "auto")


# ---------- SHEET 5: Unlinked Episodes ----------

wb$add_worksheet("Unlinked Episodes")

unlinked_export <- episodes %>%
  filter(cancer_link_method == "none") %>%
  select(patient_id, treatment_type, episode_number, episode_start, encounter_ids, drug_names)

# Title
wb$add_data(
  sheet = "Unlinked Episodes", x = "Episodes Without Cancer Diagnosis Linkage",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Unlinked Episodes", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Unlinked Episodes", dims = "A1:F1")

# Data
wb$add_data(sheet = "Unlinked Episodes", x = unlinked_export, start_row = 3, start_col = 1)

# Header styling
wb$add_font(
  sheet = "Unlinked Episodes", dims = "A3:F3",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)
wb$add_fill(
  sheet = "Unlinked Episodes", dims = "A3:F3",
  color = wb_color("FF1F2937")
)

wb$freeze_pane(sheet = "Unlinked Episodes", first_active_row = 4)
wb$set_col_widths(sheet = "Unlinked Episodes", cols = 1:6, widths = "auto")


# Save workbook
wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)
message(glue("  Saved audit workbook: {OUTPUT_XLSX}"))


# ---------- CSV Export ----------

message("\n--- Creating flat CSV export ---")

write.csv(episodes, OUTPUT_CSV, row.names = FALSE)
# ==============================================================================
# SECTION 2: OUTPUT ----
# ==============================================================================

message(glue("  Saved CSV: {OUTPUT_CSV}"))


# --- FINAL SUMMARY ---

message("\n=== Phase 61 Complete ===")
message(glue("  Episodes enriched: {nrow(episodes)}"))
message(glue("  Cancer linkage: {n_encounter_linked} encounter_id, {n_temporal_linked} closest_date, {n_none} none"))
message(glue("  Hodgkin episodes: {sum(episodes$is_hodgkin)}"))
message(glue("  Regimens: {n_abvd} ABVD, {n_bv} BV+AVD, {n_nivo} Nivo+AVD"))
message(glue("  Outputs: treatment_episodes.rds (enriched), {basename(OUTPUT_XLSX)}, {basename(OUTPUT_CSV)}"))
