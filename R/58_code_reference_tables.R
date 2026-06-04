# ==============================================================================
# 58_code_reference_tables.R -- Code Reference Lookup (Cancer + Treatment)
# ==============================================================================
#
# Purpose:
#   Generate a two-sheet xlsx providing human-readable reference for every code
#   appearing in the cancer summary and drug grouping output tables.
#   Sheet 1: Cancer diagnosis codes with ICD type and site category.
#   Sheet 2: Treatment codes with code system type and description.
#
# Inputs:
#   - output/tables/cancer_summary_table_pre_post.xlsx ("Code Summary" sheet)
#   - output/drug_grouping_tables.xlsx ("Treatment Sub-Category Summary" sheet)
#   - cache/outputs/code_descriptions.rds (optional; built by R/42)
#   - R/00_config.R (CANCER_SITE_MAP, ICD9_CANCER_SITE_MAP, CODE_SUBCATEGORY_MAP)
#   - R/utils/utils_cancer.R (classify_codes)
#
# Outputs:
#   - output/tables/code_reference.xlsx (2-sheet workbook)
#
# Dependencies:
#   - R/00_config.R, R/utils/utils_cancer.R
#   - openxlsx2
#
# ==============================================================================

# SECTION 1: SETUP ----

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/utils/utils_cancer.R")  # classify_codes()

CANCER_XLSX    <- file.path(CONFIG$output_dir, "tables", "cancer_summary_table_pre_post.xlsx")
DRUG_XLSX      <- file.path(CONFIG$output_dir, "drug_grouping_tables.xlsx")
REFERENCE_XLSX <- "data/reference/all_codes_resolved_next_tables_v2.1.xlsx"
DESC_RDS       <- file.path(CONFIG$cache$outputs_dir, "code_descriptions.rds")
OUTPUT_XLSX    <- file.path(CONFIG$output_dir, "tables", "code_reference.xlsx")

message("=== Code Reference Tables ===")
message()


# SECTION 2: BUILD TREATMENT CODE DESCRIPTIONS ----

message("--- Loading treatment code descriptions ---")

# Try loading pre-built code_descriptions.rds (built by R/42)
if (file.exists(DESC_RDS)) {
  code_desc <- readRDS(DESC_RDS)
  message(glue("  Loaded {length(code_desc)} descriptions from code_descriptions.rds"))
} else {
  message("  code_descriptions.rds not found; building from config sources")
  code_desc <- character(0)
}

# Supplement with hardcoded radiation descriptions (same as R/42 Source 3)
radiation_hardcoded <- c(
  "77401" = "External beam radiation delivery, surface/orthovoltage (DELETED 2026)",
  "77402" = "Radiation treatment delivery; simple",
  "77404" = "Radiation treatment delivery; single area, 6-10 MeV (DELETED 2015)",
  "77407" = "Radiation treatment delivery; intermediate",
  "77408" = "Radiation treatment delivery; 2 separate areas, 3+ ports, 6-10 MeV (DELETED 2015)",
  "77412" = "Radiation treatment delivery; complex",
  "77413" = "Radiation treatment delivery; 3+ separate areas, custom blocking, 6-10 MeV (DELETED 2015)",
  "77414" = "Radiation treatment delivery; 3+ separate areas, custom blocking, 11-19 MeV (DELETED 2015)",
  "77416" = "Radiation treatment delivery; 3+ separate areas, complex, 20+ MeV (DELETED 2015)",
  "77417" = "Port film(s) per treatment session / portal imaging (DELETED 2026)",
  "77418" = "Radiation treatment delivery, IMRT (DELETED 2015)",
  "77421" = "Stereoscopic x-ray guidance for target localization (DELETED 2015)",
  "77427" = "Radiation treatment management, weekly (per 5 fractions)",
  "77431" = "Radiation treatment management, 1-4 treatments (end-of-course)",
  "77432" = "Stereotactic radiation treatment management of cranial lesion",
  "77435" = "Stereotactic body radiation therapy (SBRT) management",
  "77470" = "Special treatment procedure (total body irradiation, hemibody irradiation)",
  "77520" = "Proton treatment delivery; simple, without compensation",
  "77522" = "Proton treatment delivery; simple, with compensation",
  "77523" = "Proton treatment delivery; intermediate",
  "77525" = "Proton treatment delivery; complex",
  "G6003" = "Radiation treatment delivery, IMRT (1+ sessions, DELETED 2026)",
  "G6004" = "Radiation treatment delivery, IMRT (subsequent sessions, DELETED 2026)",
  "G6005" = "Radiation treatment delivery, electron beam; simple (DELETED 2026)",
  "G6006" = "Radiation treatment delivery, electron beam; intermediate (DELETED 2026)",
  "G6007" = "Radiation treatment delivery, electron beam; complex (DELETED 2026)",
  "G6008" = "Radiation treatment delivery; simple, 2D (DELETED 2026)",
  "G6009" = "Radiation treatment delivery; intermediate, 2D (DELETED 2026)",
  "G6010" = "Radiation treatment delivery; complex, 2D (DELETED 2026)",
  "G6011" = "Radiation treatment delivery; simple, 3D (DELETED 2026)",
  "G6012" = "Radiation treatment delivery; intermediate, 3D (DELETED 2026)",
  "G6013" = "Radiation treatment delivery; complex, 3D (DELETED 2026)",
  "G6014" = "Radiation treatment delivery, IMRT; simple (DELETED 2026)",
  "G6015" = "Radiation treatment delivery, IMRT; complex (DELETED 2026)",
  "G6016" = "Radiation treatment delivery; custom blocks (DELETED 2026)"
)

# Supplement with config curated descriptions (same as R/42 Source 4)
config_descriptions <- c(
  "J9000" = "Doxorubicin HCl (Adriamycin)",
  "J9040" = "Bleomycin sulfate",
  "J9360" = "Vinblastine sulfate",
  "J9130" = "Dacarbazine (DTIC)",
  "J9042" = "Brentuximab vedotin (Adcetris)",
  "J9299" = "Nivolumab (Opdivo)",
  "3639"  = "Doxorubicin",
  "11213" = "Bleomycin",
  "67228" = "Vinblastine",
  "3946"  = "Dacarbazine",
  "38230" = "Bone marrow harvesting",
  "38232" = "Bone marrow harvesting",
  "38240" = "Allogeneic HPC transplantation",
  "38241" = "Autologous HPC transplantation",
  "38242" = "Allogeneic donor lymphocyte infusion (DLI)",
  "38243" = "Allogeneic HPC boost",
  "S2140" = "Cord blood harvesting for transplantation, allogeneic",
  "S2142" = "Cord blood-derived stem-cell transplantation, allogeneic",
  "S2150" = "Bone marrow or blood-derived stem cells; allogeneic or autologous",
  "77261" = "Therapeutic radiology treatment planning; simple",
  "77262" = "Therapeutic radiology treatment planning; intermediate",
  "77263" = "Therapeutic radiology treatment planning; complex",
  "77280" = "Therapeutic radiology simulation-aided field setting; simple",
  "77285" = "Therapeutic radiology simulation-aided field setting; intermediate",
  "77290" = "Therapeutic radiology simulation-aided field setting; complex",
  "77293" = "Respiratory motion management simulation",
  "77295" = "3-dimensional radiotherapy plan, including dose-volume histograms",
  "77300" = "Basic radiation dosimetry calculation",
  "77301" = "Intensity modulated radiotherapy plan (IMRT)",
  "77306" = "Teletherapy isodose plan; simple",
  "77307" = "Teletherapy isodose plan; complex",
  "77310" = "Teletherapy isodose plan; brachytherapy isodose calc, simple (DELETED)",
  "77315" = "Teletherapy isodose plan; brachytherapy isodose calc, complex (DELETED)",
  "77316" = "Brachytherapy isodose plan; simple",
  "77318" = "Brachytherapy isodose plan; complex",
  "77321" = "Special teletherapy port plan",
  "77331" = "Special dosimetry (TLD, calorimetry, etc.)",
  "77332" = "Treatment devices, simple",
  "77333" = "Treatment devices, intermediate",
  "77334" = "Treatment devices, complex",
  "77336" = "Continuing medical physics consultation",
  "77338" = "Multi-leaf collimator (MLC) device design and fabrication",
  "77370" = "Special medical radiation physics consultation",
  "77371" = "SRS, multi-source Gamma Knife (DELETED 2026)",
  "77372" = "SRS, linear accelerator based (DELETED 2026)",
  "77373" = "Stereotactic body radiation therapy (SBRT), treatment delivery",
  "77385" = "IMRT delivery, simple",
  "77386" = "IMRT delivery, complex",
  "77387" = "Guidance for radiation treatment delivery (IGRT)",
  "77399" = "Unlisted procedure, radiation treatment delivery",
  "77605" = "Hyperthermia, externally generated; deep (DELETED)",
  "77750" = "Infusion or instillation of radioelement solution",
  "77763" = "Interstitial radiation source application; complex",
  "77768" = "Intracavitary radiation source application; complex",
  "77770" = "Remote afterloading high dose rate brachytherapy; 1 channel",
  "77771" = "Remote afterloading high dose rate brachytherapy; 2-12 channels",
  "77772" = "Remote afterloading high dose rate brachytherapy; over 12 channels",
  "77785" = "Remote afterloading brachytherapy; 1-4 sources/ribbons, complex (DELETED)",
  "99.25" = "Injection or infusion of cancer chemotherapeutic substance",
  "99.28" = "Injection or infusion of immunotherapy",
  "92.20" = "Infusion of liquid brachytherapy radioisotope",
  "92.21" = "Superficial radiation",
  "92.22" = "Orthovoltage radiation",
  "92.23" = "Radioisotopic teleradiotherapy",
  "92.24" = "Teleradiotherapy using photons",
  "92.25" = "Teleradiotherapy using electrons",
  "92.26" = "Teleradiotherapy of other particulate radiation",
  "92.27" = "Implantation or insertion of radioactive elements",
  "92.29" = "Other radiotherapeutic procedure",
  "92.30" = "Stereotactic radiosurgery, NOS",
  "92.31" = "Single source photon radiosurgery",
  "92.32" = "Multi-source photon radiosurgery (Gamma Knife)",
  "92.33" = "Particulate radiosurgery",
  "92.41" = "Intra-operative electron radiation therapy (IERT)",
  "41.00" = "Bone marrow transplant, NOS",
  "41.01" = "Autologous bone marrow transplant without purging",
  "41.02" = "Allogeneic bone marrow transplant with purging",
  "41.03" = "Allogeneic bone marrow transplant without purging",
  "41.04" = "Autologous hematopoietic stem cell transplant without purging",
  "41.05" = "Allogeneic hematopoietic stem cell transplant without purging",
  "41.06" = "Cord blood stem cell transplant",
  "41.07" = "Autologous hematopoietic stem cell transplant with purging",
  "41.08" = "Allogeneic hematopoietic stem cell transplant with purging",
  "41.09" = "Autologous bone marrow transplant with purging",
  "Z51.11" = "Encounter for antineoplastic chemotherapy",
  "Z51.12" = "Encounter for antineoplastic immunotherapy",
  "V58.11" = "Encounter for antineoplastic chemotherapy",
  "V58.12" = "Encounter for antineoplastic immunotherapy",
  "Z51.0"  = "Encounter for antineoplastic radiation therapy",
  "V58.0"  = "Encounter for radiotherapy",
  "Z94.84" = "Stem cells transplant status",
  "T86.5"  = "Complications of stem cell transplant",
  "T86.09" = "Other complications of bone marrow transplant",
  "Z48.290" = "Encounter for aftercare following bone marrow transplant",
  "T86.0"  = "Complications of bone marrow transplant",
  "837" = "DRG: Chemo w/o acute leukemia as SDx w MCC",
  "838" = "DRG: Chemo w/o acute leukemia as SDx w CC",
  "839" = "DRG: Chemo w/o acute leukemia as SDx w/o CC/MCC",
  "846" = "DRG: Chemo w hematologic malignancy as SDx w MCC",
  "847" = "DRG: Chemo w hematologic malignancy as SDx w CC",
  "848" = "DRG: Chemo w hematologic malignancy as SDx w/o CC/MCC",
  "849" = "DRG: Radiotherapy",
  "014" = "DRG: Allogeneic bone marrow transplant",
  "016" = "DRG: Autologous BMT w CC/MCC or T-cell immunotherapy",
  "017" = "DRG: Autologous BMT w/o CC/MCC",
  "018" = "DRG: Chimeric Antigen Receptor (CAR) T-cell Immunotherapy",
  "3E00X05" = "Antineoplastic into skin/mucous membranes, external approach",
  "3E01305" = "Antineoplastic into subcutaneous tissue, percutaneous",
  "3E0130M" = "Monoclonal antibody antineoplastic into subcutaneous tissue",
  "3E02305" = "Antineoplastic into muscle, percutaneous",
  "3E03005" = "Antineoplastic into peripheral vein, open",
  "3E03305" = "Antineoplastic into peripheral vein, percutaneous",
  "3E0330M" = "Monoclonal antibody antineoplastic into peripheral vein, percutaneous",
  "3E04005" = "Antineoplastic into central vein, open",
  "3E04305" = "Antineoplastic into central vein, percutaneous",
  "3E0430M" = "Monoclonal antibody antineoplastic into central vein, percutaneous",
  "3E05305" = "Antineoplastic into peripheral artery, percutaneous",
  "3E0530M" = "Monoclonal antibody antineoplastic into peripheral artery, percutaneous",
  "3E06305" = "Antineoplastic into central artery, percutaneous",
  "3E0630M" = "Monoclonal antibody antineoplastic into central artery, percutaneous",
  "3E0D705" = "Antineoplastic into mouth/pharynx, via natural opening",
  "3E0G305" = "Antineoplastic into upper GI, percutaneous",
  "3E0L305" = "Antineoplastic into pleural cavity, percutaneous",
  "3E0Q305" = "Antineoplastic into cranial/peripheral nerves, percutaneous",
  "3E0R305" = "Antineoplastic into spinal canal, percutaneous (intrathecal chemo)",
  "3E0R30M" = "Monoclonal antibody antineoplastic into spinal canal, percutaneous",
  "3E0S305" = "Antineoplastic into epidural space, percutaneous",
  "3E0W305" = "Antineoplastic into lymphatics, percutaneous",
  "3E0W30M" = "Monoclonal antibody antineoplastic into lymphatics, percutaneous",
  "D70"  = "Beam Radiation, lymphatic/hematologic",
  "D71"  = "Brachytherapy, lymphatic/hematologic",
  "D72"  = "Stereotactic Radiosurgery, lymphatic/hematologic",
  "D7Y"  = "Other Radiation, lymphatic/hematologic",
  "30230C0" = "Autologous HPC (genetically modified), peripheral vein, open",
  "30230G0" = "Autologous bone marrow, peripheral vein, open",
  "30230X0" = "Autologous cord blood stem cells, peripheral vein, open",
  "30230Y0" = "Autologous HPC, peripheral vein, open",
  "30240C0" = "Autologous HPC (genetically modified), central vein, open",
  "30240G0" = "Autologous bone marrow, central vein, open",
  "30240X0" = "Autologous cord blood stem cells, central vein, open",
  "30240Y0" = "Autologous HPC, central vein, open",
  "30233C0" = "Autologous HPC (genetically modified), peripheral vein, percutaneous",
  "30233G0" = "Autologous HPC, peripheral vein, percutaneous",
  "30233X0" = "Autologous cord blood stem cells, peripheral vein, percutaneous",
  "30233Y0" = "Autologous HPC (other), peripheral vein, percutaneous",
  "30243C0" = "Autologous HPC (genetically modified), central vein, percutaneous",
  "30243G0" = "Autologous HPC, central vein, percutaneous",
  "30243X0" = "Autologous cord blood stem cells, central vein, percutaneous",
  "30243Y0" = "Autologous HPC (other), central vein, percutaneous",
  "30233G1" = "Nonautologous HPC, peripheral vein, percutaneous",
  "30233X1" = "Nonautologous cord blood stem cells, peripheral vein, percutaneous",
  "30233Y1" = "Nonautologous HPC (other), peripheral vein, percutaneous",
  "30243G1" = "Nonautologous HPC, central vein, percutaneous",
  "30243X1" = "Nonautologous cord blood stem cells, central vein, percutaneous",
  "30243Y1" = "Nonautologous HPC (other), central vein, percutaneous",
  "30233G2" = "Allogeneic related bone marrow, peripheral vein, percutaneous",
  "30233G3" = "Allogeneic unrelated bone marrow, peripheral vein, percutaneous",
  "30233U2" = "Allogeneic related T-cell depleted bone marrow, peripheral vein, percutaneous",
  "30233U3" = "Allogeneic unrelated T-cell depleted bone marrow, peripheral vein, percutaneous",
  "30233X2" = "Allogeneic related cord blood stem cells, peripheral vein, percutaneous",
  "30233X3" = "Allogeneic unrelated cord blood stem cells, peripheral vein, percutaneous",
  "30233Y2" = "Allogeneic related HPC, peripheral vein, percutaneous",
  "30233Y3" = "Allogeneic unrelated HPC, peripheral vein, percutaneous",
  "30243G2" = "Allogeneic related bone marrow, central vein, percutaneous",
  "30243G3" = "Allogeneic unrelated bone marrow, central vein, percutaneous",
  "30243U2" = "Allogeneic related T-cell depleted bone marrow, central vein, percutaneous",
  "30243U3" = "Allogeneic unrelated T-cell depleted bone marrow, central vein, percutaneous",
  "30243X2" = "Allogeneic related cord blood stem cells, central vein, percutaneous",
  "30243X3" = "Allogeneic unrelated cord blood stem cells, central vein, percutaneous",
  "30243Y2" = "Allogeneic related HPC, central vein, percutaneous",
  "30243Y3" = "Allogeneic unrelated HPC, central vein, percutaneous",
  "30230AZ" = "Embryonic stem cells, peripheral vein, open",
  "30233AZ" = "Embryonic stem cells, peripheral vein, percutaneous",
  "30240AZ" = "Embryonic stem cells, central vein, open",
  "30243AZ" = "Embryonic stem cells, central vein, percutaneous",
  "XW133C8" = "Transfusion of Omidubicel into Peripheral Vein, Percutaneous",
  "XW143C8" = "Transfusion of Omidubicel into Central Vein, Percutaneous",
  "XW033C7" = "Autologous CAR T-cell immunotherapy, peripheral vein",
  "XW033G7" = "Allogeneic CAR T-cell, peripheral vein",
  "XW033H7" = "Axicabtagene ciloleucel, peripheral vein",
  "XW033J7" = "Tisagenlecleucel immunotherapy, peripheral vein",
  "XW033K7" = "Idecabtagene vicleucel immunotherapy, peripheral vein",
  "XW033L7" = "Lifileucel immunotherapy, peripheral vein",
  "XW033M7" = "Brexucabtagene autoleucel, peripheral vein",
  "XW033N7" = "Lisocabtagene maraleucel, peripheral vein",
  "XW043C7" = "Autologous CAR T-cell immunotherapy, central vein",
  "XW043G7" = "Allogeneic CAR T-cell, central vein",
  "XW043H7" = "Axicabtagene ciloleucel, central vein",
  "XW043J7" = "Tisagenlecleucel immunotherapy, central vein",
  "XW043K7" = "Idecabtagene vicleucel immunotherapy, central vein",
  "XW043L7" = "Lifileucel immunotherapy, central vein",
  "XW043M7" = "Brexucabtagene autoleucel, central vein",
  "XW043N7" = "Lisocabtagene maraleucel, central vein"
)

# Merge: code_descriptions.rds (if loaded) < radiation_hardcoded < config_descriptions
# Later entries win on duplicate keys
all_desc <- c(code_desc, radiation_hardcoded, config_descriptions)
all_desc <- all_desc[!duplicated(names(all_desc), fromLast = TRUE)]
message(glue("  Total description entries: {length(all_desc)}"))

# Load chemo medication names from reference xlsx (column A = code, column C = Medication)
message()
message("--- Loading chemo medication names from reference xlsx ---")
ref_wb <- wb_load(REFERENCE_XLSX)
chemo_sheet <- wb_to_df(ref_wb, sheet = "Chemotherapy", start_row = 2)
chemo_med_map <- setNames(as.character(chemo_sheet[[3]]), as.character(chemo_sheet[[1]]))
chemo_med_map <- chemo_med_map[!is.na(names(chemo_med_map)) & !is.na(chemo_med_map)]
message(glue("  Chemo medication descriptions: {length(chemo_med_map)} codes"))


# SECTION 3: CANCER CODES SHEET ----

message()
message("--- Building cancer codes reference ---")

cancer_wb <- wb_load(CANCER_XLSX)
# Row 1 = merged title, Row 2 = headers, Row 3+ = data; use positional indexing
# Column A (1) = Cancer Code, Column B (2) = Category (per R/49 headers)
cancer_raw <- wb_to_df(cancer_wb, sheet = "Code Summary", start_row = 3, col_names = FALSE)

# Extract unique cancer codes (exclude TOTAL row)
cancer_codes <- cancer_raw %>%
  rename(cancer_code = 1, category = 2) %>%
  filter(!is.na(cancer_code), cancer_code != "TOTAL") %>%
  mutate(cancer_code = as.character(cancer_code), category = as.character(category)) %>%
  distinct(cancer_code, category) %>%
  mutate(
    code_type = case_when(
      str_detect(cancer_code, "^[CD]") ~ "ICD-10-CM",
      str_detect(cancer_code, "^[12]")  ~ "ICD-9-CM",
      TRUE ~ "Unknown"
    )
  ) %>%
  select(code = cancer_code, code_type, description = category) %>%
  arrange(code_type, code)

message(glue("  Unique cancer codes: {nrow(cancer_codes)}"))
message(glue("  ICD-10-CM: {sum(cancer_codes$code_type == 'ICD-10-CM')}"))
message(glue("  ICD-9-CM: {sum(cancer_codes$code_type == 'ICD-9-CM')}"))


# SECTION 4: TREATMENT CODES SHEET ----

message()
message("--- Building treatment codes reference ---")

drug_wb <- wb_load(DRUG_XLSX)
drug_raw <- wb_to_df(drug_wb, sheet = "Treatment Sub-Category Summary")

# Extract unique treatment codes with their code_type and category
treatment_codes <- drug_raw %>%
  filter(!is.na(treatment_code)) %>%
  distinct(treatment_code, code_type, category, sub_category) %>%
  mutate(
    # Chemo: use medication name from reference xlsx (highest priority)
    # Non-chemo: all_desc > CODE_SUBCATEGORY_MAP > sub_category fallback
    description = case_when(
      category == "Chemotherapy" & treatment_code %in% names(chemo_med_map) ~ chemo_med_map[treatment_code],
      treatment_code %in% names(all_desc) ~ all_desc[treatment_code],
      treatment_code %in% names(CODE_SUBCATEGORY_MAP) ~ CODE_SUBCATEGORY_MAP[treatment_code],
      TRUE ~ sub_category
    )
  ) %>%
  select(code = treatment_code, code_type, category, description) %>%
  arrange(category, code)

n_with_desc <- sum(treatment_codes$description != "" & !is.na(treatment_codes$description))
message(glue("  Unique treatment codes: {nrow(treatment_codes)}"))
message(glue("  With descriptions: {n_with_desc} ({round(100 * n_with_desc / nrow(treatment_codes), 1)}%)"))

# Log per-category counts
cat_counts <- treatment_codes %>% count(category)
for (i in seq_len(nrow(cat_counts))) {
  message(glue("    {cat_counts$category[i]}: {cat_counts$n[i]} codes"))
}


# SECTION 5: WRITE XLSX ----

message()
message("--- Writing code_reference.xlsx ---")

wb <- wb_workbook()

wb$add_worksheet("Cancer Codes")
wb$add_data("Cancer Codes", cancer_codes, start_row = 1, col_names = TRUE)

wb$add_worksheet("Treatment Codes")
wb$add_data("Treatment Codes", treatment_codes, start_row = 1, col_names = TRUE)

wb$save(OUTPUT_XLSX)

message(glue("  Saved: {OUTPUT_XLSX}"))
message(glue("  Sheet 1 (Cancer Codes): {nrow(cancer_codes)} rows"))
message(glue("  Sheet 2 (Treatment Codes): {nrow(treatment_codes)} rows"))
message()
message("Done.")
