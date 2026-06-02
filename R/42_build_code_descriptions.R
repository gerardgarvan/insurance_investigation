# =============================================================================
# 42_build_code_descriptions.R
# =============================================================================
# Purpose: Build static named character vector mapping treatment codes to
#          human-readable descriptions. Combines 4 sources in precedence order
#          (last source wins on duplicates).
#
# Inputs:  cache/outputs/unmatched_codes_classified.rds (Phase 39 CPT/HCPCS NLM API)
#          cache/outputs/unmatched_ndc_classified.rds (Phase 40 NDC/RXNORM RxNorm API)
#          Hardcoded radiation CPT descriptions (retired codes, 31 entries)
#          R/00_config.R inline comments (original curated codes)
#
# Outputs: cache/outputs/code_descriptions.rds (named character vector)
#
# Dependencies: R/00_config.R
#
# Requirements: Decision traceability maintained:
#               D-01: Static lookup from existing sources, no NLM API at runtime
#               D-02: Output as code_descriptions.rds named character vector
#               D-05: Missing descriptions handled downstream (empty string)
# =============================================================================


# --- SECTION 1: SETUP ----

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
})

source("R/00_config.R")

# Input paths
HCPCS_RDS <- file.path(CONFIG$output_dir, "unmatched_codes_classified.rds")
NDC_RDS <- file.path(CONFIG$output_dir, "unmatched_ndc_classified.rds")

# Output path
OUTPUT_RDS <- file.path(CONFIG$cache$outputs_dir, "code_descriptions.rds")

# SECTION 0: INPUT VALIDATION ----
# SAFE-01: Validate classified code RDS files exist
assert_rds_exists(HCPCS_RDS, script_name = "R/42")
assert_rds_exists(NDC_RDS, script_name = "R/42")

message("=== Phase 02: Build Code Description Lookup ===\n")


# --- SECTION 2: SOURCE 1 (PHASE 39 RDS - CPT/HCPCS CODES) ----

hcpcs_classified <- readRDS(HCPCS_RDS)
hcpcs_classified <- hcpcs_classified %>%
  filter(!is.na(description), description != "", description != "No description found")

hcpcs_lookup <- setNames(hcpcs_classified$description, hcpcs_classified$code)
message(glue("  Source 1 (Phase 39 CPT/HCPCS): {length(hcpcs_lookup)} descriptions"))


# --- SECTION 3: SOURCE 2 (PHASE 40 RDS - NDC/RXNORM CODES) ----

ndc_classified <- readRDS(NDC_RDS)
ndc_classified <- ndc_classified %>%
  filter(!is.na(drug_name), drug_name != "")

ndc_lookup <- setNames(ndc_classified$drug_name, ndc_classified$code)
message(glue("  Source 2 (Phase 40 NDC/RXNORM): {length(ndc_lookup)} descriptions"))


# --- SECTION 4: SOURCE 3 (HARDCODED RADIATION CPT - RETIRED CODES) ----

radiation_hardcoded <- c(
  "77401" = "External beam radiation delivery, surface/orthovoltage (DELETED 2026; historical claims only)",
  "77402" = "Radiation treatment delivery; simple (complexity-based, 2026 new code)",
  "77404" = "Radiation treatment delivery; single area, 6-10 MeV (DELETED 2015)",
  "77407" = "Radiation treatment delivery; intermediate (complexity-based, 2026 new code)",
  "77408" = "Radiation treatment delivery; 2 separate areas, 3+ ports, 6-10 MeV (DELETED 2015)",
  "77412" = "Radiation treatment delivery; complex (complexity-based, 2026 new code)",
  "77413" = "Radiation treatment delivery; 3+ separate areas, custom blocking, 6-10 MeV (DELETED 2015)",
  "77414" = "Radiation treatment delivery; 3+ separate areas, custom blocking, 11-19 MeV (DELETED 2015)",
  "77416" = "Radiation treatment delivery; 3+ separate areas, complex, 20+ MeV (DELETED 2015)",
  "77417" = "Port film(s) per treatment session / portal imaging (DELETED 2026, bundled into delivery)",
  "77418" = "Radiation treatment delivery, IMRT — intensity modulated (DELETED 2015)",
  "77421" = "Stereoscopic x-ray guidance for target localization (DELETED 2015, replaced by 77387)",
  "77427" = "Radiation treatment management, weekly — per 5 fractions",
  "77431" = "Radiation treatment management, 1-4 treatments (end-of-course)",
  "77432" = "Stereotactic radiation treatment management of cranial lesion",
  "77435" = "Stereotactic body radiation therapy (SBRT) management",
  "77470" = "Special treatment procedure (total body irradiation, hemibody irradiation)",
  "77520" = "Proton treatment delivery; simple, without compensation",
  "77522" = "Proton treatment delivery; simple, with compensation",
  "77523" = "Proton treatment delivery; intermediate",
  "77525" = "Proton treatment delivery; complex",
  "G6003" = "Radiation treatment delivery, IMRT — 1 or more sessions (DELETED 2026)",
  "G6004" = "Radiation treatment delivery, IMRT — subsequent sessions (DELETED 2026)",
  "G6005" = "Radiation treatment delivery using electron beam — simple (DELETED 2026)",
  "G6006" = "Radiation treatment delivery using electron beam — intermediate (DELETED 2026)",
  "G6007" = "Radiation treatment delivery using electron beam — complex (DELETED 2026)",
  "G6008" = "Radiation treatment delivery; simple, 2D (DELETED 2026)",
  "G6009" = "Radiation treatment delivery; intermediate, 2D (DELETED 2026)",
  "G6010" = "Radiation treatment delivery; complex, 2D (DELETED 2026)",
  "G6011" = "Radiation treatment delivery; simple, 3D (DELETED 2026)",
  "G6012" = "Radiation treatment delivery; intermediate, 3D (DELETED 2026)",
  "G6013" = "Radiation treatment delivery; complex, 3D (DELETED 2026)",
  "G6014" = "Radiation treatment delivery, IMRT — simple (DELETED 2026)",
  "G6015" = "Radiation treatment delivery, IMRT — complex (DELETED 2026)",
  "G6016" = "Radiation treatment delivery; custom blocks (DELETED 2026)"
)

message(glue("  Source 3 (R/45 radiation hardcoded): {length(radiation_hardcoded)} descriptions"))


# --- SECTION 5: SOURCE 4 (R/00_CONFIG.R CURATED CODES) ----
# WHY 4-source precedence order: API results provide broad coverage but lower
#   accuracy; hardcoded descriptions target specific gaps (retired codes); manual
#   config comments are most accurate but fewest -- later sources override earlier
#   to ensure highest-quality descriptions win. Per D-01, D-02.
# ---

config_descriptions <- c(
  # Chemo HCPCS (ABVD regimen, lines 417-422)
  "J9000" = "Doxorubicin HCl (Adriamycin)",
  "J9040" = "Bleomycin sulfate",
  "J9360" = "Vinblastine sulfate",
  "J9130" = "Dacarbazine (DTIC)",
  "J9042" = "Brentuximab vedotin (Adcetris)",
  "J9299" = "Nivolumab (Opdivo)",

  # Chemo RXNORM (ABVD base ingredients, lines 523-526)
  "3639" = "Doxorubicin",
  "11213" = "Bleomycin",
  "67228" = "Vinblastine",
  "3946" = "Dacarbazine",

  # SCT CPT (lines 735-741)
  "38230" = "Bone marrow harvesting",
  "38232" = "Bone marrow harvesting",
  "38240" = "Allogeneic HPC transplantation",
  "38241" = "Autologous HPC transplantation",
  "38242" = "Allogeneic donor lymphocyte infusion (DLI)",
  "38243" = "Allogeneic HPC boost",

  # SCT HCPCS (lines 745-748)
  "S2140" = "Cord blood harvesting for transplantation, allogeneic",
  "S2142" = "Cord blood-derived stem-cell transplantation, allogeneic",
  "S2150" = "Bone marrow or blood-derived stem cells; allogeneic or autologous",

  # Radiation CPT treatment planning (lines 656-662)
  "77261" = "Therapeutic radiology treatment planning; simple",
  "77262" = "Therapeutic radiology treatment planning; intermediate",
  "77263" = "Therapeutic radiology treatment planning; complex",
  "77280" = "Therapeutic radiology simulation-aided field setting; simple",
  "77285" = "Therapeutic radiology simulation-aided field setting; intermediate",
  "77290" = "Therapeutic radiology simulation-aided field setting; complex",
  "77293" = "Respiratory motion management simulation",

  # Radiation CPT physics/dosimetry (lines 665-681)
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

  # Radiation CPT treatment delivery (lines 684-702)
  "77371" = "SRS, multi-source Gamma Knife (DELETED 2026)",
  "77372" = "SRS, linear accelerator based (DELETED 2026)",
  "77373" = "Stereotactic body radiation therapy (SBRT), treatment delivery",
  "77385" = "IMRT delivery, simple",
  "77386" = "IMRT delivery, complex",
  "77387" = "Guidance for radiation treatment delivery (IGRT)",
  "77399" = "Unlisted procedure, radiation treatment delivery",

  # Radiation CPT hyperthermia + brachytherapy (lines 716-725)
  "77605" = "Hyperthermia, externally generated; deep (DELETED)",
  "77750" = "Infusion or instillation of radioelement solution",
  "77763" = "Interstitial radiation source application; complex",
  "77768" = "Intracavitary radiation source application; complex",
  "77770" = "Remote afterloading high dose rate brachytherapy; 1 channel",
  "77771" = "Remote afterloading high dose rate brachytherapy; 2-12 channels",
  "77772" = "Remote afterloading high dose rate brachytherapy; over 12 channels",
  "77785" = "Remote afterloading brachytherapy; 1-4 sources/ribbons, complex (DELETED)",

  # Chemo ICD-9 (lines 753-756)
  "99.25" = "Injection or infusion of cancer chemotherapeutic substance",
  "99.28" = "Injection or infusion of immunotherapy",

  # Radiation ICD-9 (lines 789-803)
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

  # SCT ICD-9 (lines 817-827)
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

  # Diagnosis codes (lines 927-947)
  "Z51.11" = "Encounter for antineoplastic chemotherapy",
  "Z51.12" = "Encounter for antineoplastic immunotherapy",
  "V58.11" = "Encounter for antineoplastic chemotherapy",
  "V58.12" = "Encounter for antineoplastic immunotherapy",
  "Z51.0" = "Encounter for antineoplastic radiation therapy",
  "V58.0" = "Encounter for radiotherapy",
  "Z94.84" = "Stem cells transplant status",
  "T86.5" = "Complications of stem cell transplant",
  "T86.09" = "Other complications of bone marrow transplant",
  "Z48.290" = "Encounter for aftercare following bone marrow transplant",
  "T86.0" = "Complications of bone marrow transplant",

  # DRG codes (lines 951-969)
  "837" = "Chemo w/o acute leukemia as SDx w MCC",
  "838" = "Chemo w/o acute leukemia as SDx w CC",
  "839" = "Chemo w/o acute leukemia as SDx w/o CC/MCC",
  "846" = "Chemo w hematologic malignancy as SDx w MCC",
  "847" = "Chemo w hematologic malignancy as SDx w CC",
  "848" = "Chemo w hematologic malignancy as SDx w/o CC/MCC",
  "849" = "Radiotherapy",
  "014" = "Allogeneic bone marrow transplant",
  "016" = "Autologous BMT w CC/MCC or T-cell immunotherapy",
  "017" = "Autologous BMT w/o CC/MCC",
  "018" = "Chimeric Antigen Receptor (CAR) T-cell Immunotherapy",

  # ICD-10-PCS chemo prefixes (lines 762-784)
  "3E00X05" = "Antineoplastic into skin/mucous membranes, external approach",
  "3E01305" = "Antineoplastic into subcutaneous tissue, percutaneous",
  "3E0130M" = "Monoclonal antibody antineoplastic into subcutaneous tissue, percutaneous",
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

  # Radiation ICD-10-PCS prefixes (lines 808-813)
  "D70" = "Beam Radiation, lymphatic/hematologic",
  "D71" = "Brachytherapy, lymphatic/hematologic",
  "D72" = "Stereotactic Radiosurgery, lymphatic/hematologic",
  "D7Y" = "Other Radiation, lymphatic/hematologic",

  # SCT ICD-10-PCS codes (lines 835-884)
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
  "XW133C8" = "Transfusion of Omidubicel into Peripheral Vein, Percutaneous Approach",
  "XW143C8" = "Transfusion of Omidubicel into Central Vein, Percutaneous Approach",

  # CAR-T ICD-10-PCS (lines 891-906)
  "XW033C7" = "Autologous engineered chimeric antigen receptor T-cell immunotherapy, peripheral vein",
  "XW033G7" = "Allogeneic engineered chimeric antigen receptor T-cell, peripheral vein",
  "XW033H7" = "Axicabtagene ciloleucel, peripheral vein",
  "XW033J7" = "Tisagenlecleucel immunotherapy, peripheral vein",
  "XW033K7" = "Idecabtagene vicleucel immunotherapy, peripheral vein",
  "XW033L7" = "Lifileucel immunotherapy, peripheral vein",
  "XW033M7" = "Brexucabtagene autoleucel, peripheral vein",
  "XW033N7" = "Lisocabtagene maraleucel, peripheral vein",
  "XW043C7" = "Autologous engineered chimeric antigen receptor T-cell, central vein",
  "XW043G7" = "Allogeneic engineered chimeric antigen receptor T-cell, central vein",
  "XW043H7" = "Axicabtagene ciloleucel, central vein",
  "XW043J7" = "Tisagenlecleucel immunotherapy, central vein",
  "XW043K7" = "Idecabtagene vicleucel immunotherapy, central vein",
  "XW043L7" = "Lifileucel immunotherapy, central vein",
  "XW043M7" = "Brexucabtagene autoleucel, central vein",
  "XW043N7" = "Lisocabtagene maraleucel, central vein"
)

message(glue("  Source 4 (R/00_config.R curated): {length(config_descriptions)} descriptions"))


# --- SECTION 6: COMBINE ALL SOURCES ----

# Precedence order: API results (lowest) -> hardcoded (medium) -> config (highest)
# Later sources overwrite earlier for duplicate keys
all_descriptions <- c(hcpcs_lookup, ndc_lookup, radiation_hardcoded, config_descriptions)

message(glue("\n  Combined: {length(all_descriptions)} total entries"))
message(glue("  Unique codes: {length(unique(names(all_descriptions)))} (duplicates resolved by precedence)"))

# Deduplicate by keeping last occurrence (precedence order)
all_descriptions <- all_descriptions[!duplicated(names(all_descriptions), fromLast = TRUE)]


# --- SECTION 7: SAVE RDS ----

saveRDS(all_descriptions, OUTPUT_RDS)
message(glue("\n  Saved {length(all_descriptions)} code descriptions to {OUTPUT_RDS}"))


# --- SECTION 8: SUMMARY ----

message("\n=== Phase 02 Lookup Build Complete ===")
message(glue("  Phase 39 CPT/HCPCS: {length(hcpcs_lookup)}"))
message(glue("  Phase 40 NDC/RXNORM: {length(ndc_lookup)}"))
message(glue("  R/45 radiation:      {length(radiation_hardcoded)}"))
message(glue("  R/00_config curated: {length(config_descriptions)}"))
message(glue("  Final lookup:        {length(all_descriptions)} unique code descriptions"))
message(glue("\n  Output: {OUTPUT_RDS}"))
