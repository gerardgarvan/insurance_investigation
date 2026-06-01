# ==============================================================================
# Phase 61 Plan 01: Episode Classification - Cancer Linkage and Regimen Detection
# ==============================================================================
#
# PURPOSE:
#   Replace patient-level cancer linkage (R/49) with encounter-level precision for
#   RDS artifacts. Link cancer diagnoses to specific treatment episodes via
#   ENCOUNTERID with temporal fallback. Label chemotherapy episodes with regimen
#   names (ABVD, BV+AVD, Nivo+AVD) using drug composition matching.
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
#   D-16: Final column order: patient_id through regimen_label (15 columns total)
#   D-17: Multi-sheet audit xlsx following R/59 pattern with openxlsx2
#   D-18: Flat CSV export for episode classification results
#
# INPUTS:
#   - cache/outputs/treatment_episodes.rds (from R/44a + R/60)
#   - cache/outputs/treatment_episode_detail.rds (from R/44a + R/60)
#   - DuckDB DIAGNOSIS table (via get_pcornet_table)
#
# OUTPUTS:
#   - cache/outputs/treatment_episodes.rds (modified with 4 new columns)
#   - output/episode_classification_audit.xlsx (5 sheets)
#   - output/episode_classification_audit.csv (flat export)
#
# ==============================================================================

# --- SECTION 1: SETUP AND CONFIGURATION ---

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


# --- SECTION 2: PREFIX_MAP AND HELPERS ---

# PREFIX_MAP: Copied from R/49 for script independence (project pattern — see also R/53, R/54, R/55)
PREFIX_MAP <- c(
  # --- Solid tumors by anatomical site ---

  # 1. Lip, Oral Cavity and Pharynx (C00-C14)
  "C00" = "Lip, Oral Cavity and Pharynx",
  "C01" = "Lip, Oral Cavity and Pharynx",
  "C02" = "Lip, Oral Cavity and Pharynx",
  "C03" = "Lip, Oral Cavity and Pharynx",
  "C04" = "Lip, Oral Cavity and Pharynx",
  "C05" = "Lip, Oral Cavity and Pharynx",
  "C06" = "Lip, Oral Cavity and Pharynx",
  "C07" = "Lip, Oral Cavity and Pharynx",
  "C08" = "Lip, Oral Cavity and Pharynx",
  "C09" = "Lip, Oral Cavity and Pharynx",
  "C10" = "Lip, Oral Cavity and Pharynx",
  "C11" = "Lip, Oral Cavity and Pharynx",
  "C12" = "Lip, Oral Cavity and Pharynx",
  "C13" = "Lip, Oral Cavity and Pharynx",
  "C14" = "Lip, Oral Cavity and Pharynx",

  # 2. Esophagus (C15)
  "C15" = "Esophagus",

  # 3. Stomach (C16)
  "C16" = "Stomach",

  # 4. Small Intestine (C17)
  "C17" = "Small Intestine",

  # 5. Colon incl. rectosigmoid junction (C18-C19)
  "C18" = "Colon",
  "C19" = "Colon",

  # 6. Rectum (C20)
  "C20" = "Rectum",

  # 7. Anus (C21)
  "C21" = "Anus",

  # 8. Liver (C22)
  "C22" = "Liver",

  # 9. Pancreas (C25)
  "C25" = "Pancreas",

  # 10. Other Digestive (gallbladder, biliary, other) (C23-C24, C26)
  "C23" = "Other Digestive",
  "C24" = "Other Digestive",
  "C26" = "Other Digestive",

  # 11. Nasal Cavity, Middle Ear, Sinuses (C30-C31)
  "C30" = "Nasal Cavity, Middle Ear, Sinuses",
  "C31" = "Nasal Cavity, Middle Ear, Sinuses",

  # 12. Larynx (C32)
  "C32" = "Larynx",

  # 13. Lung and Bronchus (C33-C34)
  "C33" = "Lung and Bronchus",
  "C34" = "Lung and Bronchus",

  # 14. Other Respiratory/Intrathoracic (C37-C39)
  "C37" = "Other Respiratory/Intrathoracic",
  "C38" = "Other Respiratory/Intrathoracic",
  "C39" = "Other Respiratory/Intrathoracic",

  # 15. Bone (C40-C41)
  "C40" = "Bone",
  "C41" = "Bone",

  # 16. Melanoma of Skin (C43)
  "C43" = "Melanoma of Skin",

  # 17. Other Skin incl. Merkel cell (C44, C4A)
  "C44" = "Other Skin",
  "C4A" = "Other Skin",

  # 18. Mesothelioma (C45)
  "C45" = "Mesothelioma",

  # 19. Kaposi Sarcoma (C46)
  "C46" = "Kaposi Sarcoma",

  # 20. Soft Tissue / Peripheral Nerves (C47-C49)
  "C47" = "Soft Tissue",
  "C48" = "Soft Tissue",
  "C49" = "Soft Tissue",

  # 21. Breast (C50)
  "C50" = "Breast",

  # 22. Cervix Uteri (C53)
  "C53" = "Cervix Uteri",

  # 23. Corpus Uteri (C54-C55)
  "C54" = "Corpus Uteri",
  "C55" = "Corpus Uteri",

  # 24. Ovary (C56)
  "C56" = "Ovary",

  # 25. Other Female Genital (C51-C52, C57-C58)
  "C51" = "Other Female Genital",
  "C52" = "Other Female Genital",
  "C57" = "Other Female Genital",
  "C58" = "Other Female Genital",

  # 26. Prostate (C61)
  "C61" = "Prostate",

  # 27. Testis (C62)
  "C62" = "Testis",

  # 28. Other Male Genital (C60, C63)
  "C60" = "Other Male Genital",
  "C63" = "Other Male Genital",

  # 29. Kidney and Renal Pelvis (C64-C65)
  "C64" = "Kidney and Renal Pelvis",
  "C65" = "Kidney and Renal Pelvis",

  # 30. Bladder (C67)
  "C67" = "Bladder",

  # 31. Other Urinary (C66, C68)
  "C66" = "Other Urinary",
  "C68" = "Other Urinary",

  # 32. Eye and Orbit (C69)
  "C69" = "Eye and Orbit",

  # 33. Brain and CNS (C70-C72)
  "C70" = "Brain and CNS",
  "C71" = "Brain and CNS",
  "C72" = "Brain and CNS",

  # 34. Thyroid (C73)
  "C73" = "Thyroid",

  # 35. Other Endocrine (C74-C75)
  "C74" = "Other Endocrine",
  "C75" = "Other Endocrine",

  # 36. Ill-Defined Sites (C76)
  "C76" = "Ill-Defined Sites",

  # 37. Unknown Primary Site (C80)
  "C80" = "Unknown Primary Site",

  # --- Secondary/metastatic ---

  # 38. Lymph Nodes (secondary) (C77)
  "C77" = "Lymph Nodes (Secondary)",

  # 39. Secondary - Respiratory/Digestive (C78)
  "C78" = "Secondary - Respiratory/Digestive",

  # 40. Secondary - Other Sites (C79)
  "C79" = "Secondary - Other Sites",

  # --- Neuroendocrine ---

  # 41. Neuroendocrine Tumors (C7A, C7B)
  "C7A" = "Neuroendocrine Tumors",
  "C7B" = "Neuroendocrine Tumors",

  # --- Hematologic malignancies ---

  # 42. Hodgkin Lymphoma (C81)
  "C81" = "Hodgkin Lymphoma",

  # 43. Non-Hodgkin Lymphoma (C82-C86, C88)
  "C82" = "Non-Hodgkin Lymphoma",
  "C83" = "Non-Hodgkin Lymphoma",
  "C84" = "Non-Hodgkin Lymphoma",
  "C85" = "Non-Hodgkin Lymphoma",
  "C86" = "Non-Hodgkin Lymphoma",
  "C88" = "Non-Hodgkin Lymphoma",

  # 44. Multiple Myeloma / Plasma Cell (C90)
  "C90" = "Multiple Myeloma",

  # 45. Lymphoid Leukemia (C91)
  "C91" = "Lymphoid Leukemia",

  # 46. Myeloid and Monocytic Leukemia (C92-C93)
  "C92" = "Myeloid and Monocytic Leukemia",
  "C93" = "Myeloid and Monocytic Leukemia",

  # 47. Other Leukemia (C94-C95)
  "C94" = "Other Leukemia",
  "C95" = "Other Leukemia",

  # 48. Other Hematopoietic (C96)
  "C96" = "Other Hematopoietic",

  # --- D-codes: neoplasm-related ---

  # 49. In Situ Neoplasms (D00-D09)
  "D00" = "In Situ Neoplasms",
  "D01" = "In Situ Neoplasms",
  "D02" = "In Situ Neoplasms",
  "D03" = "In Situ Neoplasms",
  "D04" = "In Situ Neoplasms",
  "D05" = "In Situ Neoplasms",
  "D06" = "In Situ Neoplasms",
  "D07" = "In Situ Neoplasms",
  "D09" = "In Situ Neoplasms",

  # 50. Benign Neoplasms (D10-D36, D3A)
  "D10" = "Benign Neoplasms",
  "D11" = "Benign Neoplasms",
  "D12" = "Benign Neoplasms",
  "D13" = "Benign Neoplasms",
  "D14" = "Benign Neoplasms",
  "D15" = "Benign Neoplasms",
  "D16" = "Benign Neoplasms",
  "D17" = "Benign Neoplasms",
  "D18" = "Benign Neoplasms",
  "D19" = "Benign Neoplasms",
  "D20" = "Benign Neoplasms",
  "D21" = "Benign Neoplasms",
  "D22" = "Benign Neoplasms",
  "D23" = "Benign Neoplasms",
  "D24" = "Benign Neoplasms",
  "D25" = "Benign Neoplasms",
  "D26" = "Benign Neoplasms",
  "D27" = "Benign Neoplasms",
  "D28" = "Benign Neoplasms",
  "D29" = "Benign Neoplasms",
  "D30" = "Benign Neoplasms",
  "D31" = "Benign Neoplasms",
  "D32" = "Benign Neoplasms",
  "D33" = "Benign Neoplasms",
  "D34" = "Benign Neoplasms",
  "D35" = "Benign Neoplasms",
  "D36" = "Benign Neoplasms",
  "D3A" = "Benign Neoplasms",

  # 51. Uncertain Behavior Neoplasms (D37-D44, D48)
  "D37" = "Uncertain Behavior Neoplasms",
  "D38" = "Uncertain Behavior Neoplasms",
  "D39" = "Uncertain Behavior Neoplasms",
  "D40" = "Uncertain Behavior Neoplasms",
  "D41" = "Uncertain Behavior Neoplasms",
  "D42" = "Uncertain Behavior Neoplasms",
  "D43" = "Uncertain Behavior Neoplasms",
  "D44" = "Uncertain Behavior Neoplasms",
  "D48" = "Uncertain Behavior Neoplasms",

  # 52. MDS / Myeloproliferative (D45-D47) -- clinically important
  "D45" = "MDS / Myeloproliferative",
  "D46" = "MDS / Myeloproliferative",
  "D47" = "MDS / Myeloproliferative",

  # 53. Unspecified Behavior Neoplasms (D49)
  "D49" = "Unspecified Behavior Neoplasms",

  # --- ICD-O-3 only: hematopoietic site (not in ICD-10) ---
  "C42" = "Hematopoietic System (ICD-O-3)"
)

# classify_codes: derive category from cancer_code using PREFIX_MAP
classify_codes <- function(codes) {
  prefixes <- substr(toupper(codes), 1, 3)
  categories <- PREFIX_MAP[prefixes]
  unname(categories)
}

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

if (!file.exists(OUTPUT_RDS)) {
  stop(glue("Input file not found: {OUTPUT_RDS}. Run R/44a and R/60 first."))
}
if (!file.exists(DETAIL_RDS)) {
  stop(glue("Input file not found: {DETAIL_RDS}. Run R/44a and R/60 first."))
}

episodes <- readRDS(OUTPUT_RDS)
message(glue("  Loaded treatment_episodes.rds: {nrow(episodes)} episodes"))

episode_detail <- readRDS(DETAIL_RDS)
message(glue("  Loaded treatment_episode_detail.rds: {nrow(episode_detail)} detail rows"))

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
  inner_join(dx_with_encounter, by = "ENCOUNTERID") %>%
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
  left_join(dx_for_unlinked, by = c("patient_id" = "ID")) %>%
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
      has_dox  = has_jcode(triggering_codes, "J9000"),
      has_bleo = has_jcode(triggering_codes, "J9040"),
      has_vin  = has_jcode(triggering_codes, "J9360"),
      has_dac  = has_jcode(triggering_codes, "J9130"),
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


# --- SECTION 6: SAVE ENRICHED RDS ---

message("\n--- Saving enriched treatment_episodes.rds ---")

# Final column order (D-16)
episodes <- episodes %>%
  select(
    patient_id, treatment_type, episode_number, episode_start, episode_stop,
    episode_length_days, distinct_dates_in_episode, historical_flag,
    triggering_codes, encounter_ids, drug_names,
    cancer_category, cancer_link_method, is_hodgkin, regimen_label
  )

saveRDS(episodes, OUTPUT_RDS)
message(glue("  Saved enriched treatment_episodes.rds: {nrow(episodes)} episodes, {ncol(episodes)} columns"))

# Verify column presence
stopifnot(all(c("cancer_category", "cancer_link_method", "is_hodgkin", "regimen_label") %in% names(episodes)))


# --- SECTION 7: AUDIT OUTPUT ---

message("\n--- Creating audit workbook ---")

wb <- wb_workbook()

# ---------- SHEET 1: Linkage Summary ----------

wb$add_worksheet("Linkage Summary")

# Title row (A1)
wb$add_data(sheet = "Linkage Summary", x = "Episode Classification Audit",
            start_row = 1, start_col = 1)
wb$add_font(sheet = "Linkage Summary", dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Linkage Summary", dims = "A1:C1")

# Subtitle row (A2)
subtitle <- glue("Generated: {Sys.Date()} | Total episodes: {nrow(episodes)}")
wb$add_data(sheet = "Linkage Summary", x = subtitle, start_row = 2, start_col = 1)
wb$add_font(sheet = "Linkage Summary", dims = "A2",
            name = "Calibri", size = 10, color = wb_color("FF6B7280"))
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
wb$add_font(sheet = "Linkage Summary", dims = "A4:C4",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
wb$add_fill(sheet = "Linkage Summary", dims = "A4:C4",
            color = wb_color("FF1F2937"))

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
wb$add_data(sheet = "Cancer Categories", x = "Cancer Category Distribution",
            start_row = 1, start_col = 1)
wb$add_font(sheet = "Cancer Categories", dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Cancer Categories", dims = "A1:E1")

# Data
wb$add_data(sheet = "Cancer Categories", x = cancer_category_freq, start_row = 3, start_col = 1)

# Header styling
wb$add_font(sheet = "Cancer Categories", dims = "A3:E3",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
wb$add_fill(sheet = "Cancer Categories", dims = "A3:E3",
            color = wb_color("FF1F2937"))

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
wb$add_data(sheet = "Regimen Distribution", x = "Chemotherapy Regimen Distribution",
            start_row = 1, start_col = 1)
wb$add_font(sheet = "Regimen Distribution", dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Regimen Distribution", dims = "A1:D1")

# Data
wb$add_data(sheet = "Regimen Distribution", x = regimen_freq, start_row = 3, start_col = 1)

# Header styling
wb$add_font(sheet = "Regimen Distribution", dims = "A3:D3",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
wb$add_fill(sheet = "Regimen Distribution", dims = "A3:D3",
            color = wb_color("FF1F2937"))

wb$freeze_pane(sheet = "Regimen Distribution", first_active_row = 4)
wb$set_col_widths(sheet = "Regimen Distribution", cols = 1:4, widths = "auto")


# ---------- SHEET 4: Second Cancer Confirmation ----------

wb$add_worksheet("Second Cancer Confirmation")

# Title
wb$add_data(sheet = "Second Cancer Confirmation", x = "Second Cancer Confirmation (7-day separation)",
            start_row = 1, start_col = 1)
wb$add_font(sheet = "Second Cancer Confirmation", dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Second Cancer Confirmation", dims = "A1:F1")

# Data
second_cancer_export <- confirmed_second_cancers %>%
  rename(patient_id = ID) %>%
  select(patient_id, cancer_category, n_diagnoses, min_dx_date, max_dx_date, days_span)

wb$add_data(sheet = "Second Cancer Confirmation", x = second_cancer_export, start_row = 3, start_col = 1)

# Header styling
wb$add_font(sheet = "Second Cancer Confirmation", dims = "A3:F3",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
wb$add_fill(sheet = "Second Cancer Confirmation", dims = "A3:F3",
            color = wb_color("FF1F2937"))

wb$freeze_pane(sheet = "Second Cancer Confirmation", first_active_row = 4)
wb$set_col_widths(sheet = "Second Cancer Confirmation", cols = 1:6, widths = "auto")


# ---------- SHEET 5: Unlinked Episodes ----------

wb$add_worksheet("Unlinked Episodes")

unlinked_export <- episodes %>%
  filter(cancer_link_method == "none") %>%
  select(patient_id, treatment_type, episode_number, episode_start, encounter_ids, drug_names)

# Title
wb$add_data(sheet = "Unlinked Episodes", x = "Episodes Without Cancer Diagnosis Linkage",
            start_row = 1, start_col = 1)
wb$add_font(sheet = "Unlinked Episodes", dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Unlinked Episodes", dims = "A1:F1")

# Data
wb$add_data(sheet = "Unlinked Episodes", x = unlinked_export, start_row = 3, start_col = 1)

# Header styling
wb$add_font(sheet = "Unlinked Episodes", dims = "A3:F3",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
wb$add_fill(sheet = "Unlinked Episodes", dims = "A3:F3",
            color = wb_color("FF1F2937"))

wb$freeze_pane(sheet = "Unlinked Episodes", first_active_row = 4)
wb$set_col_widths(sheet = "Unlinked Episodes", cols = 1:6, widths = "auto")


# Save workbook
wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)
message(glue("  Saved audit workbook: {OUTPUT_XLSX}"))


# ---------- CSV Export ----------

message("\n--- Creating flat CSV export ---")

write.csv(episodes, OUTPUT_CSV, row.names = FALSE)
message(glue("  Saved CSV: {OUTPUT_CSV}"))


# --- FINAL SUMMARY ---

message("\n=== Phase 61 Complete ===")
message(glue("  Episodes enriched: {nrow(episodes)}"))
message(glue("  Cancer linkage: {n_encounter_linked} encounter_id, {n_temporal_linked} closest_date, {n_none} none"))
message(glue("  Hodgkin episodes: {sum(episodes$is_hodgkin)}"))
message(glue("  Regimens: {n_abvd} ABVD, {n_bv} BV+AVD, {n_nivo} Nivo+AVD"))
message(glue("  Outputs: treatment_episodes.rds (enriched), {basename(OUTPUT_XLSX)}, {basename(OUTPUT_CSV)}"))
