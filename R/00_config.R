# ==============================================================================
# PCORnet Payer Variable Investigation (R Pipeline)
# Configuration File
# ==============================================================================
#
# This file defines all project-wide configuration including:
#   - Data paths (HiPerGator /orange and /blue directories)
#   - PCORnet CDM table paths (9 primary tables for loading)
#   - ICD code lists (149 Hodgkin Lymphoma diagnosis codes)
#   - Payer mapping rules (9-category system matching Python pipeline)
#   - Analysis parameters (thresholds for cohort filtering)
#
# Source this file at the start of any analysis script:
#   source("R/00_config.R")
#
# Utility functions (parse_pcornet_date, attrition logging) are auto-sourced
# at the end of this file.
#
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. DATA PATHS
# ------------------------------------------------------------------------------

CONFIG <- list(
  # Data directory: Raw PCORnet CDM CSV files (Mailhot HL cohort extract 2025-09-15)
  data_dir = "/orange/erin.mobley-hl.bcu/Mailhot_V1_20250915",

  # Project directory: R scripts and workspace
  project_dir = "/blue/erin.mobley-hl.bcu/R",

  # Output directory: Figures, tables, cohort files
  output_dir = "output",

  # Performance tuning (vroom multi-threaded CSV loading)
  # Match to SLURM --cpus-per-task allocation (Open OnDemand RStudio: 16 cores)
  performance = list(
    num_threads = 16
  )
)

# ------------------------------------------------------------------------------
# 2. PCORNET CDM TABLE PATHS
# ------------------------------------------------------------------------------

# Primary load set: 11 tables
# - 6 standard CDM tables: ENROLLMENT, DIAGNOSIS, PROCEDURES, PRESCRIBING,
#   ENCOUNTER, DEMOGRAPHIC
# - 3 TUMOR_REGISTRY tables: contain HL-specific diagnosis dates (DATE_OF_DIAGNOSIS)
#   and treatment dates (DT_CHEMO, DT_RAD, etc.)
# - 2 medication tables (Phase 9): DISPENSING, MED_ADMIN for expanded treatment detection
#
# File naming pattern: TABLE_Mailhot_V1.csv
# Example: ENROLLMENT_Mailhot_V1.csv

PCORNET_TABLES <- c(
  "ENROLLMENT",
  "DIAGNOSIS",
  "PROCEDURES",
  "PRESCRIBING",
  "ENCOUNTER",
  "DEMOGRAPHIC",
  "TUMOR_REGISTRY1",
  "TUMOR_REGISTRY2",
  "TUMOR_REGISTRY3",
  "DISPENSING",       # Phase 9: expanded treatment detection
  "MED_ADMIN",        # Phase 9: expanded treatment detection
  "LAB_RESULT_CM",    # Phase 10: surveillance lab values (LOINC-based matching)
  "PROVIDER"          # Phase 10: oncology provider specialty matching
)

# Build full paths as named character vector
# Usage: PCORNET_PATHS$ENROLLMENT, PCORNET_PATHS$DIAGNOSIS, etc.
PCORNET_PATHS <- setNames(
  file.path(CONFIG$data_dir, paste0(PCORNET_TABLES, "_Mailhot_V1.csv")),
  PCORNET_TABLES
)

# NOTE: Patient ID column is "ID" (not "PATID") across all tables
# NOTE: SOURCE column = partner/site identifier (AMS, UMI, FLM, VRT)

# ------------------------------------------------------------------------------
# 3. ICD CODE LISTS (149 Hodgkin Lymphoma diagnosis codes)
# ------------------------------------------------------------------------------

ICD_CODES <- list(
  # ICD-10-CM: C81.xx (77 codes total)
  # 7 subtypes × 10 anatomic sites (0-9) + lymphocyte-rich (C81.4x, 10 codes)
  # No C81.5x or C81.6x in ICD-10-CM
  #
  # Anatomic site codes: 0=unspecified, 1=head/face/neck, 2=intrathoracic,
  # 3=intra-abdominal, 4=axilla/upper limb, 5=inguinal/lower limb,
  # 6=intrapelvic, 7=spleen, 8=other sites, 9=extranodal/solid organ
  hl_icd10 = c(
    # C81.0x: Nodular lymphocyte predominant Hodgkin lymphoma
    "C81.00", "C81.01", "C81.02", "C81.03", "C81.04", "C81.05", "C81.06", "C81.07", "C81.08", "C81.09",

    # C81.1x: Nodular sclerosis classical Hodgkin lymphoma
    "C81.10", "C81.11", "C81.12", "C81.13", "C81.14", "C81.15", "C81.16", "C81.17", "C81.18", "C81.19",

    # C81.2x: Mixed cellularity classical Hodgkin lymphoma
    "C81.20", "C81.21", "C81.22", "C81.23", "C81.24", "C81.25", "C81.26", "C81.27", "C81.28", "C81.29",

    # C81.3x: Lymphocyte depleted classical Hodgkin lymphoma
    "C81.30", "C81.31", "C81.32", "C81.33", "C81.34", "C81.35", "C81.36", "C81.37", "C81.38", "C81.39",

    # C81.4x: Lymphocyte-rich classical Hodgkin lymphoma
    "C81.40", "C81.41", "C81.42", "C81.43", "C81.44", "C81.45", "C81.46", "C81.47", "C81.48", "C81.49",

    # C81.7x: Other classical Hodgkin lymphoma
    "C81.70", "C81.71", "C81.72", "C81.73", "C81.74", "C81.75", "C81.76", "C81.77", "C81.78", "C81.79",

    # C81.9x: Hodgkin lymphoma, unspecified
    "C81.90", "C81.91", "C81.92", "C81.93", "C81.94", "C81.95", "C81.96", "C81.97", "C81.98", "C81.99",

    # C81.xA: Hodgkin lymphoma, in remission (FY2025 ICD-10-CM, effective Oct 2024)
    # Found in OneFlorida+ data — 15 "Neither" patients had C81.9A missed by original list
    "C81.0A", "C81.1A", "C81.2A", "C81.3A", "C81.4A", "C81.7A", "C81.9A"
  ),

  # ICD-9-CM: 201.xx (72 site-specific + 8 parent codes = 80 total)
  # 8 subtypes × 9 anatomic sites (0-8) + parent codes without site digit
  # No 201.3x in ICD-9-CM (gap in Hodgkin coding)
  #
  # Anatomic site codes: 0=unspecified, 1=head/neck, 2=intrathoracic,
  # 3=intra-abdominal, 4=axilla/upper limb, 5=inguinal/lower limb,
  # 6=intrapelvic, 7=spleen, 8=multiple sites
  hl_icd9 = c(
    # 201.x: Parent codes without anatomic site digit
    # Some sites (FLM, TMA) code without the 5th digit — "201.2" not "201.20"
    # Found in OneFlorida+ data: 3 patients missed due to short codes
    "201.0", "201.1", "201.2", "201.4", "201.5", "201.6", "201.7", "201.9",

    # 201.0x: Hodgkin's paragranuloma
    "201.00", "201.01", "201.02", "201.03", "201.04", "201.05", "201.06", "201.07", "201.08",

    # 201.1x: Hodgkin's granuloma
    "201.10", "201.11", "201.12", "201.13", "201.14", "201.15", "201.16", "201.17", "201.18",

    # 201.2x: Hodgkin's sarcoma
    "201.20", "201.21", "201.22", "201.23", "201.24", "201.25", "201.26", "201.27", "201.28",

    # 201.4x: Lymphocytic-histiocytic predominance
    "201.40", "201.41", "201.42", "201.43", "201.44", "201.45", "201.46", "201.47", "201.48",

    # 201.5x: Nodular sclerosis
    "201.50", "201.51", "201.52", "201.53", "201.54", "201.55", "201.56", "201.57", "201.58",

    # 201.6x: Mixed cellularity
    "201.60", "201.61", "201.62", "201.63", "201.64", "201.65", "201.66", "201.67", "201.68",

    # 201.7x: Lymphocytic depletion
    "201.70", "201.71", "201.72", "201.73", "201.74", "201.75", "201.76", "201.77", "201.78",

    # 201.9x: Hodgkin's disease, unspecified
    "201.90", "201.91", "201.92", "201.93", "201.94", "201.95", "201.96", "201.97", "201.98"
  ),

  # ICD-O-3 Histology codes for Hodgkin Lymphoma (morphology codes 9650-9667)
  # Used for TUMOR_REGISTRY table matching (TR1: HISTOLOGICAL_TYPE, TR2/TR3: MORPH)
  # Reference: SEER ICD-O-3 Hematopoietic and Lymphoid code lists
  #
  # 9650: Hodgkin lymphoma, NOS
  # 9651: Hodgkin lymphoma, lymphocyte-rich
  # 9652: Hodgkin lymphoma, mixed cellularity, NOS
  # 9653: Hodgkin lymphoma, lymphocytic depletion, NOS
  # 9654: Hodgkin lymphoma, lymphocytic depletion, diffuse fibrosis
  # 9655: Hodgkin lymphoma, lymphocytic depletion, reticular
  # 9659: Nodular lymphocyte predominant Hodgkin lymphoma
  # 9661: Hodgkin granuloma (obsolete)
  # 9662: Hodgkin sarcoma (obsolete)
  # 9663: Hodgkin lymphoma, nodular sclerosis, NOS
  # 9664: Hodgkin lymphoma, nodular sclerosis, cellular phase
  # 9665: Hodgkin lymphoma, nodular sclerosis, grade 1
  # 9667: Hodgkin lymphoma, nodular sclerosis, grade 2
  hl_histology = c(
    "9650", "9651", "9652", "9653", "9654", "9655", "9659",
    "9661", "9662", "9663", "9664", "9665", "9667"
  )
)

# ------------------------------------------------------------------------------
# 4. PAYER MAPPING RULES (9-category system)
# ------------------------------------------------------------------------------
#
# This mapping replicates the Python pipeline's payer harmonization logic.
# Reference: C:\cygwin64\home\Owner\Data loading and cleaing\docs\PAYER_VARIABLES_AND_CATEGORIES.md
#
# Categories are assigned by prefix (PCORnet typology) with exact-match overrides
# for dual-eligible, unavailable, and unknown codes.
#
# Dual-eligible detection (encounter-level):
#   - Primary=Medicare (prefix 1) AND secondary=Medicaid (prefix 2), OR
#   - Primary=Medicaid AND secondary=Medicare, OR
#   - Primary OR secondary in {14, 141, 142}
#
# Effective payer (per encounter): primary if valid, else secondary if valid
# Sentinel values (trigger fallback to secondary): null, "", "NI", "UN", "OT"
# NOTE: 99/9999 are NOT sentinel values by default (map to "Unavailable" instead)
#
# ------------------------------------------------------------------------------
# R vs Python Payer Mapping Comparison (D-04, Phase 6 Plan 02)
# ------------------------------------------------------------------------------
# Source: payer_mapping_audit.csv from 07_diagnostics.R on HiPerGator
#
# Category               | R pipeline | Python pipeline | Notes
# -----------------------|------------|-----------------|------
# Medicaid               |   43.66%   |     TBD         | Largest category
# Private                |   28.58%   |     TBD         |
# Dual eligible          |   11.01%   |     TBD         | Encounter-level cross-payer detection
# Medicare               |    8.91%   |     TBD         |
# No payment / Self-pay  |    3.16%   |     TBD         |
# Unavailable            |    2.43%   |     TBD         |
# Other government       |    1.43%   |     TBD         |
# Other                  |    0.82%   |     TBD         |
# Unknown                |    ---     |     TBD         | (not in audit output, likely 0%)
#
# NOTE: Exact parity with Python pipeline not required (D-04). R pipeline is
# exploratory. Differences expected from: different dual-eligible detection
# thresholds, encounter vs enrollment-level aggregation, sentinel value handling,
# and patient-level vs encounter-level payer assignment.
#
# HL identification context (hl_identification_venn.csv):
#   19 "Neither" patients excluded by Plan 01's HL_SOURCE tracking.
#   Most patients are "DIAGNOSIS only" (no TR data for most sources).
#   Both DIAGNOSIS and TR: 721 patients (LNK, ORL, UFH only).
# ------------------------------------------------------------------------------

PAYER_MAPPING <- list(
  # Prefix-based mapping (PCORnet typology)
  medicare_prefix = "1",
  medicaid_prefix = "2",
  private_prefix = c("5", "6"),
  other_gov_prefix = c("3", "4"),  # Includes 41 (Corrections Federal)
  no_payment_prefix = "8",
  other_prefix = c("7", "9"),      # 9 excludes 99/9999 (handled separately)

  # Exact-match overrides
  unavailable_codes = c("99", "9999"),
  unknown_codes = c("NI", "UN", "OT", "UNKNOWN"),
  dual_eligible_codes = c("14", "141", "142"),

  # Sentinel values (trigger fallback to secondary payer when appearing as primary)
  sentinel_values = c("NI", "UN", "OT"),

  # 9 standard categories (for reference/validation)
  categories = c(
    "Medicare",
    "Medicaid",
    "Dual eligible",
    "Private",
    "Other government",
    "No payment / Self-pay",
    "Other",
    "Unavailable",
    "Unknown"
  )
)

# ------------------------------------------------------------------------------
# 5. ANALYSIS PARAMETERS
# ------------------------------------------------------------------------------

CONFIG$analysis <- list(
  # Minimum enrollment days for cohort inclusion
  min_enrollment_days = 30,

  # Diagnosis date window (±days around first HL diagnosis for payer assignment)
  dx_window_days = 30,

  # Treatment window (±days around treatment start/end for payer assignment)
  treatment_window_days = 30
)

# ------------------------------------------------------------------------------
# 5.5 TREATMENT CODE LISTS (for treatment flag detection)
# ------------------------------------------------------------------------------
#
# Used by 03_cohort_predicates.R to identify chemotherapy, radiation, and SCT
# evidence in PROCEDURES (CPT/HCPCS, ICD-9-CM, ICD-10-PCS, revenue codes),
# PRESCRIBING (RXNORM), DISPENSING (RXNORM), MED_ADMIN (RXNORM),
# DIAGNOSIS (Z/V codes), and ENCOUNTER (DRG codes) tables.
#
# Primary treatment evidence comes from TUMOR_REGISTRY date columns:
#   - TR1: CHEMO_START_DATE_SUMMARY (chemo), no DT_RAD column
#   - TR2/TR3: DT_CHEMO, DT_RAD, DT_HTE (hematologic transplant/endocrine)
# Supplemental evidence comes from PROCEDURES and PRESCRIBING codes below.
#
# ICD procedure codes (PX_TYPE "09" for ICD-9-CM Volume 3, "10" for ICD-10-PCS)
# for all three treatment types added in Phase 8 Plan 01.
#
# Per D-07: HAD_SCT covers both autologous and allogeneic (single flag).
#
# Sources:
#   - Radiation CPT: CMS 2026 complexity-based codes (77385/77386 deleted 2026-01-01)
#   - SCT CPT: ASBMT coding guidelines (38240-38243)
#   - Chemo RXNORM: ABVD regimen components (standard first-line HL treatment)
#   - Chemo HCPCS: J-code range for injectable chemotherapy drugs
#   - ICD-9-CM Vol 3: chemo (99.25), radiation (92.2x, 92.3x, 92.41), SCT (41.0x)
#   - ICD-10-PCS: chemo (3E0 series antineoplastic), radiation (D7 series), SCT (302 series HPC)

TREATMENT_CODES <- list(
  # Chemotherapy HCPCS J-codes (injectable chemo drugs commonly used in HL)
  # ABVD regimen: Doxorubicin (J9000), Bleomycin (J9040), Vinblastine (J9360), Dacarbazine (J9130)
  # Additional HL agents: Brentuximab vedotin (J9042), Nivolumab (J9299)
  chemo_hcpcs = c(
    "J9000",   # Doxorubicin HCl (Adriamycin)
    "J9040",   # Bleomycin sulfate
    "J9360",   # Vinblastine sulfate
    "J9130",   # Dacarbazine (DTIC)
    "J9042",   # Brentuximab vedotin (Adcetris)
    "J9299"    # Nivolumab (Opdivo)
  ),

  # Chemotherapy RXNORM CUIs for PRESCRIBING table matching
  # ABVD regimen base ingredients (RxNorm concept IDs)
  chemo_rxnorm = c(
    "3639",    # Doxorubicin
    "11213",   # Bleomycin
    "67228",   # Vinblastine
    "3946"     # Dacarbazine
  ),

  # Radiation therapy CPT codes (active treatment, not planning-only)
  # 2026 complexity-based codes replaced technique-based codes (77385/77386 deleted)
  radiation_cpt = c(
    "77401",   # External beam radiation delivery (Python pipeline)
    "77402",   # Radiation treatment delivery, intermediate (2026 new code)
    "77407",   # Radiation treatment delivery, simple (2026 new code)
    "77412",   # Radiation treatment delivery, complex (2026 new code)
    "77427"    # Radiation treatment management (weekly, per 5 fractions) - most common
  ),

  # Stem cell transplant CPT codes (autologous + allogeneic per D-07)
  sct_cpt = c(
    "38230",   # Bone marrow harvesting (Python pipeline)
    "38232",   # Bone marrow harvesting (Python pipeline)
    "38240",   # Allogeneic HPC transplantation
    "38241",   # Autologous HPC transplantation
    "38242",   # Allogeneic donor lymphocyte infusion (DLI)
    "38243"    # Allogeneic HPC boost
  ),

  # Stem cell transplant HCPCS codes (Phase 10: added from VariableDetails.xlsx)
  sct_hcpcs = c(
    "S2140",   # Cord blood harvesting for transplantation, allogeneic
    "S2142",   # Cord blood-derived stem-cell transplantation, allogeneic
    "S2150"    # Bone marrow or blood-derived stem cells; allogeneic or autologous
  ),

  # --- ICD Procedure Codes (D-02, D-04: all PX_TYPE values) ---

  # Chemotherapy ICD-9-CM Volume 3 (PX_TYPE = "09")
  chemo_icd9 = c(
    "99.25",   # Injection or infusion of cancer chemotherapeutic substance
    "99.28"    # Injection or infusion of immunotherapy (D-07)
  ),

  # Chemotherapy ICD-10-PCS (PX_TYPE = "10")
  # Section 3 Administration, Root Operation Introduction, Qualifier 5 = Antineoplastic
  # Prefix-matched in 10_treatment_payer.R via str_starts() -- store prefixes only
  chemo_icd10pcs_prefixes = c(
    "3E03305",  # Antineoplastic into peripheral vein, percutaneous
    "3E04305",  # Antineoplastic into central vein, percutaneous
    "3E05305",  # Antineoplastic into peripheral artery, percutaneous
    "3E06305"   # Antineoplastic into central artery, percutaneous
  ),

  # Radiation therapy ICD-9-CM Volume 3 (PX_TYPE = "09")
  radiation_icd9 = c(
    "92.20",   # Infusion of liquid brachytherapy radioisotope
    "92.21",   # Superficial radiation
    "92.22",   # Orthovoltage radiation
    "92.23",   # Radioisotopic teleradiotherapy
    "92.24",   # Teleradiotherapy using photons
    "92.25",   # Teleradiotherapy using electrons
    "92.26",   # Teleradiotherapy of other particulate radiation
    "92.27",   # Implantation or insertion of radioactive elements
    "92.29",   # Other radiotherapeutic procedure
    "92.30",   # Stereotactic radiosurgery, NOS
    "92.31",   # Single source photon radiosurgery
    "92.32",   # Multi-source photon radiosurgery (Gamma Knife)
    "92.33",   # Particulate radiosurgery
    "92.41"    # Intra-operative electron radiation therapy (IERT)
  ),

  # Radiation therapy ICD-10-PCS prefixes (PX_TYPE = "10")
  # Section D Radiation Therapy, Body System 7 Lymphatic and Hematologic
  # Prefix-matched in 10_treatment_payer.R via str_starts()
  radiation_icd10pcs_prefixes = c(
    "D70",     # Beam Radiation, lymphatic/hematologic
    "D71",     # Brachytherapy, lymphatic/hematologic
    "D72",     # Stereotactic Radiosurgery, lymphatic/hematologic
    "D7Y"      # Other Radiation, lymphatic/hematologic
  ),

  # Stem cell transplant ICD-9-CM Volume 3 (PX_TYPE = "09")
  sct_icd9 = c(
    "41.00",   # Bone marrow transplant, NOS
    "41.01",   # Autologous bone marrow transplant without purging
    "41.02",   # Allogeneic bone marrow transplant with purging
    "41.03",   # Allogeneic bone marrow transplant without purging
    "41.04",   # Autologous hematopoietic stem cell transplant without purging
    "41.05",   # Allogeneic hematopoietic stem cell transplant without purging
    "41.06",   # Cord blood stem cell transplant
    "41.07",   # Autologous hematopoietic stem cell transplant with purging
    "41.08",   # Allogeneic hematopoietic stem cell transplant with purging
    "41.09"    # Autologous bone marrow transplant with purging
  ),

  # Stem cell transplant ICD-10-PCS (PX_TYPE = "10")
  # Section 3 Administration, Root Operation Transfusion, Substance = Hematopoietic Stem Cells
  # Phase 10: Expanded from VariableDetails.xlsx to include open approach (3023x/3024x),
  # allogeneic related/unrelated (G2/G3, U2/U3, X2/X3, Y2/Y3), and new technology (XW1xx) codes.
  # Nonautologous variants (G1, X1, Y1) retained from Phase 9 original list.
  sct_icd10pcs = c(
    # Open approach (0) -- added from VariableDetails.xlsx
    "30230C0",  # Autologous HPC (genetically modified), peripheral vein, open
    "30230G0",  # Autologous bone marrow, peripheral vein, open
    "30230X0",  # Autologous cord blood stem cells, peripheral vein, open
    "30230Y0",  # Autologous HPC, peripheral vein, open
    "30240C0",  # Autologous HPC (genetically modified), central vein, open
    "30240G0",  # Autologous bone marrow, central vein, open
    "30240X0",  # Autologous cord blood stem cells, central vein, open
    "30240Y0",  # Autologous HPC, central vein, open
    # Percutaneous approach (3) -- autologous
    "30233C0",  # Autologous HPC (genetically modified), peripheral vein, percutaneous
    "30233G0",  # Autologous HPC, peripheral vein, percutaneous
    "30233X0",  # Autologous cord blood stem cells, peripheral vein, percutaneous
    "30233Y0",  # Autologous HPC (other), peripheral vein, percutaneous
    "30243C0",  # Autologous HPC (genetically modified), central vein, percutaneous
    "30243G0",  # Autologous HPC, central vein, percutaneous
    "30243X0",  # Autologous cord blood stem cells, central vein, percutaneous
    "30243Y0",  # Autologous HPC (other), central vein, percutaneous
    # Percutaneous approach (3) -- nonautologous (from Phase 9 original list)
    "30233G1",  # Nonautologous HPC, peripheral vein, percutaneous
    "30233X1",  # Nonautologous cord blood stem cells, peripheral vein, percutaneous
    "30233Y1",  # Nonautologous HPC (other), peripheral vein, percutaneous
    "30243G1",  # Nonautologous HPC, central vein, percutaneous
    "30243X1",  # Nonautologous cord blood stem cells, central vein, percutaneous
    "30243Y1",  # Nonautologous HPC (other), central vein, percutaneous
    # Allogeneic related (2) and unrelated (3) -- added from VariableDetails.xlsx
    "30233G2",  # Allogeneic related bone marrow, peripheral vein, percutaneous
    "30233G3",  # Allogeneic unrelated bone marrow, peripheral vein, percutaneous
    "30233U2",  # Allogeneic related T-cell depleted bone marrow, peripheral vein, percutaneous
    "30233U3",  # Allogeneic unrelated T-cell depleted bone marrow, peripheral vein, percutaneous
    "30233X2",  # Allogeneic related cord blood stem cells, peripheral vein, percutaneous
    "30233X3",  # Allogeneic unrelated cord blood stem cells, peripheral vein, percutaneous
    "30233Y2",  # Allogeneic related HPC, peripheral vein, percutaneous
    "30233Y3",  # Allogeneic unrelated HPC, peripheral vein, percutaneous
    "30243G2",  # Allogeneic related bone marrow, central vein, percutaneous
    "30243G3",  # Allogeneic unrelated bone marrow, central vein, percutaneous
    "30243U2",  # Allogeneic related T-cell depleted bone marrow, central vein, percutaneous
    "30243U3",  # Allogeneic unrelated T-cell depleted bone marrow, central vein, percutaneous
    "30243X2",  # Allogeneic related cord blood stem cells, central vein, percutaneous
    "30243X3",  # Allogeneic unrelated cord blood stem cells, central vein, percutaneous
    "30243Y2",  # Allogeneic related HPC, central vein, percutaneous
    "30243Y3",  # Allogeneic unrelated HPC, central vein, percutaneous
    # Embryonic stem cells (added from VariableDetails.xlsx)
    "30230AZ",  # Embryonic stem cells, peripheral vein, open
    "30233AZ",  # Embryonic stem cells, peripheral vein, percutaneous
    "30240AZ",  # Embryonic stem cells, central vein, open
    "30243AZ",  # Embryonic stem cells, central vein, percutaneous
    # New technology (XW1xx) -- Omidubicel (added from VariableDetails.xlsx)
    "XW133C8",  # Transfusion of Omidubicel into Peripheral Vein, Percutaneous Approach
    "XW143C8"   # Transfusion of Omidubicel into Central Vein, Percutaneous Approach
  ),

  # CAR T-cell and other immunotherapies ICD-10-PCS (DRG 018)
  # Phase 10: Added from VariableDetails.xlsx (codes with * denote prefix patterns)
  # Prefix-matched in treatment scripts via str_starts()
  cart_icd10pcs_prefixes = c(
    "XW033C7",  # Autologous engineered chimeric antigen receptor T-cell immunotherapy, peripheral vein
    "XW033G7",  # Allogeneic engineered chimeric antigen receptor T-cell, peripheral vein
    "XW033H7",  # Axicabtagene ciloleucel, peripheral vein
    "XW033J7",  # Tisagenlecleucel immunotherapy, peripheral vein
    "XW033K7",  # Idecabtagene vicleucel immunotherapy, peripheral vein
    "XW033L7",  # Lifileucel immunotherapy, peripheral vein
    "XW033M7",  # Brexucabtagene autoleucel, peripheral vein
    "XW033N7",  # Lisocabtagene maraleucel, peripheral vein
    "XW043C7",  # Autologous engineered chimeric antigen receptor T-cell, central vein
    "XW043G7",  # Allogeneic engineered chimeric antigen receptor T-cell, central vein
    "XW043H7",  # Axicabtagene ciloleucel, central vein
    "XW043J7",  # Tisagenlecleucel immunotherapy, central vein
    "XW043K7",  # Idecabtagene vicleucel immunotherapy, central vein
    "XW043L7",  # Lifileucel immunotherapy, central vein
    "XW043M7",  # Brexucabtagene autoleucel, central vein
    "XW043N7"   # Lisocabtagene maraleucel, central vein
  ),

  # --- Phase 9: Expanded detection codes (D-09, D-10, D-11) ---

  # Diagnosis-based treatment evidence (ICD-10-CM Z/T codes, ICD-9-CM V codes)
  chemo_dx_icd10 = c(
    "Z51.11",   # Encounter for antineoplastic chemotherapy
    "Z51.12"    # Encounter for antineoplastic immunotherapy
  ),
  chemo_dx_icd9 = c(
    "V58.11",   # Encounter for antineoplastic chemotherapy
    "V58.12"    # Encounter for antineoplastic immunotherapy
  ),
  radiation_dx_icd10 = c(
    "Z51.0"     # Encounter for antineoplastic radiation therapy
  ),
  radiation_dx_icd9 = c(
    "V58.0"     # Encounter for radiotherapy
  ),
  sct_dx_icd10 = c(
    "Z94.84",   # Stem cells transplant status
    "T86.5",    # Complications of stem cell transplant
    "T86.09",   # Other complications of bone marrow transplant
    "Z48.290",  # Encounter for aftercare following bone marrow transplant
    "T86.0"     # Complications of bone marrow transplant (per D-09 in CONTEXT.md)
  ),

  # MS-DRG treatment evidence (ENCOUNTER table DRG column)
  chemo_drg = c(
    "837",   # Chemo w/o acute leukemia as SDx w MCC
    "838",   # Chemo w/o acute leukemia as SDx w CC
    "839",   # Chemo w/o acute leukemia as SDx w/o CC/MCC
    "846",   # Chemo w hematologic malignancy as SDx w MCC
    "847",   # Chemo w hematologic malignancy as SDx w CC
    "848"    # Chemo w hematologic malignancy as SDx w/o CC/MCC
  ),
  radiation_drg = c(
    "849"    # Radiotherapy
  ),
  sct_drg = c(
    "014",   # Allogeneic bone marrow transplant
    "016",   # Autologous BMT w CC/MCC or T-cell immunotherapy
    "017"    # Autologous BMT w/o CC/MCC
    # NOTE: DRG 015 deleted FY2012, omitted per research pitfall 4
  ),

  # Revenue codes (PROCEDURES table PX_TYPE = "RE")
  chemo_revenue = c(
    "0331",   # Chemo - injected
    "0332",   # Chemo - oral
    "0335"    # Chemo - IV push
  ),
  radiation_revenue = c(
    "0330",   # General classification (therapeutic radiology)
    "0333"    # Radiation therapy
  ),
  sct_revenue = c(
    "0362",   # Organ transplant - other than kidney (includes SCT)
    "0815"    # Allogeneic stem cell acquisition/donor services
  )
)

# ------------------------------------------------------------------------------
# 5.6 SURVEILLANCE CODES (Phase 10) -- transcribed from VariableDetails.xlsx "Surveillance Strategy"
# ------------------------------------------------------------------------------
#
# 9 modalities: Mammogram, Breast MRI, Echocardiogram, Stress test,
# Electrocardiogram, MUGA, Pulmonary function test, TSH, CBC
#
# Code systems present per modality:
#   Mammogram:         CPT, ICD-10-PCS
#   Breast MRI:        CPT, HCPCS, ICD-10-PCS
#   Echocardiogram:    CPT, ICD-10-PCS, ICD-10 (screening Z code)
#   Stress test:       CPT (nuclear cardiology)
#   Electrocardiogram: CPT, ICD-10 (screening Z code)
#   MUGA:              CPT, ICD-10-PCS
#   PFT:               CPT, ICD-10 (screening Z code)
#   TSH:               CPT, HCPCS, LOINC
#   CBC:               CPT, HCPCS, LOINC
#
# Source: VariableDetails.xlsx "Surveillance Strategy" sheet (2025 extract)
SURVEILLANCE_CODES <- list(
  # Mammogram
  mammogram_cpt = c(
    "77063",   # Bilateral screening mammogram with tomosynthesis (screening)
    "77067",   # Bilateral screening mammogram with tomosynthesis (variant)
    "77062",   # Bilateral diagnostic mammogram with tomosynthesis
    "77066",   # Bilateral diagnostic mammogram with tomosynthesis (variant)
    "77061",   # Unilateral diagnostic mammogram with tomosynthesis
    "77065",   # Unilateral diagnostic mammogram with tomosynthesis (variant)
    "G0279"    # HCPCS: Diagnostic tomosynthesis mammogram (Medicare benefit)
  ),
  mammogram_icd10pcs = c(
    "BH00ZZZ",  # Plain Radiography of Right Breast
    "BH01ZZZ",  # Plain Radiography of Left Breast
    "BH02ZZZ"   # Plain Radiography of Bilateral Breasts
  ),

  # Breast MRI
  breast_mri_cpt = c(
    "77046",   # MRI breast without contrast, unilateral
    "77048",   # MRI breast without and with contrast, unilateral
    "77047",   # MRI breast without contrast, bilateral
    "77049"    # MRI breast without and with contrast, bilateral
  ),
  breast_mri_hcpcs = c(
    "C8903",   # MRI breast without contrast, unilateral
    "C8905",   # MRI breast without and with contrast, unilateral
    "C8906",   # MRI breast without contrast, bilateral
    "C8908"    # MRI breast without and with contrast, bilateral
  ),
  breast_mri_icd10pcs = c(
    "BH30ZZZ",  # MRI of Right Breast without contrast
    "BH31ZZZ",  # MRI of Left Breast without contrast
    "BH32ZZZ",  # MRI of Bilateral Breasts without contrast
    "BH30Y0Z",  # MRI of Right Breast with other contrast
    "BH31Y0Z",  # MRI of Left Breast with other contrast
    "BH32Y0Z"   # MRI of Bilateral Breasts with other contrast
  ),

  # Echocardiogram
  echo_cpt = c(
    "93306",   # Echocardiography, complete with doppler and color flow
    "93307",   # Echocardiography, complete without doppler
    "93308",   # Echocardiography, limited or follow-up
    "93350",   # Stress echocardiography (exercise or pharmacological)
    "93351",   # Stress echocardiography with contrast
    "93352"    # Stress echocardiography, additional contrast (add-on)
  ),
  echo_icd10pcs = c(
    "X2JAX47"  # Measurement of Cardiac Output using Echocardiography, New Technology
  ),
  echo_icd10_dx = c(
    "Z13.6"    # Encounter for screening for cardiovascular disorders
  ),

  # Stress test (nuclear cardiology)
  stress_test_cpt = c(
    "78451",   # Myocardial perfusion imaging, SPECT, single study at rest or stress
    "78452"    # Myocardial perfusion imaging, SPECT, multiple studies at rest and stress
  ),

  # Electrocardiogram
  ecg_cpt = c(
    "93000",   # Electrocardiogram, routine ECG with 12 leads; with interpretation and report
    "93005",   # Electrocardiogram, routine ECG, tracing only
    "93010",   # Electrocardiogram, routine ECG, interpretation and report only
    "93015",   # Cardiovascular stress test with ECG monitoring and supervision
    "93016",   # Cardiovascular stress test, physician supervision only
    "93017",   # Cardiovascular stress test, tracing only
    "93018",   # Cardiovascular stress test, interpretation and report only
    "93040",   # Rhythm ECG, 1-3 leads; with interpretation and report
    "93041",   # Rhythm ECG, 1-3 leads; tracing only
    "93042"    # Rhythm ECG, 1-3 leads; interpretation and report only
  ),
  ecg_icd10_dx = c(
    "Z13.6"    # Encounter for screening for cardiovascular disorders
  ),

  # MUGA (Multiple Gated Acquisition scan)
  muga_cpt = c(
    "78472",   # Cardiac blood pool imaging, gated equilibrium, planar; single study at rest
    "78473",   # Cardiac blood pool imaging, gated equilibrium, planar; multiple studies
    "78481",   # Cardiac blood pool imaging, first pass technique; single study at rest
    "78483",   # Cardiac blood pool imaging, first pass technique; multiple studies
    "78494",   # Cardiac blood pool imaging, gated equilibrium, SPECT; single study
    "78496"    # Cardiac blood pool imaging, gated equilibrium with wall motion study
  ),
  muga_icd10pcs = c(
    "C21G1ZZ",  # Planar Nuclear Medicine Imaging of Heart using Technetium 99m
    "C22G1ZZ"   # Tomographic Nuclear Medicine Imaging of Heart using Technetium 99m
  ),

  # Pulmonary function test
  pft_cpt = c(
    "94010",   # Spirometry (FVC, FEV1, FEF)
    "94011",   # Spirometry measurement, pediatric patients
    "94012",   # Spirometry measurement, pediatric patients, minimum 2 curves
    "94060",   # Spirometry with bronchodilator response
    "94070",   # Bronchospasm provocation evaluation with multiple spirometric determinations
    "94150",   # Vital capacity, total
    "94200",   # Maximum breathing capacity (MVV or MBC)
    "94375",   # Respiratory flow volume loop
    "94726",   # Plethysmography for determination of lung volumes and airway resistance
    "94727",   # Gas dilution techniques for determination of lung volumes
    "94729"    # Diffusing capacity (DLCO)
  ),
  pft_icd10_dx = c(
    "Z13.83"   # Encounter for screening for respiratory disorder NEC
  ),

  # Thyroid stimulating hormone (TSH)
  tsh_cpt = c(
    "84443"    # Thyroid stimulating hormone (TSH) assay
  ),
  tsh_hcpcs = c(
    "224576"   # TSH lab test (Medicare clinical lab code)
  ),
  tsh_loinc = c(
    "11580-8", # Thyrotropin [Units/volume] in Serum or Plasma
    "3024-7"   # Thyrotropin [Units/volume] in Serum or Plasma (variant)
  ),

  # Complete blood count (CBC)
  cbc_cpt = c(
    "85025",   # Blood count; complete (CBC), automated (Hgb, Hct, RBC, WBC and platelet count)
    "85027"    # Blood count; complete (CBC), automated (RBC, WBC, Hgb, Hct, MCV, MCH, MCHC)
  ),
  cbc_hcpcs = c(
    "G0306",   # CBC without differential (Medicare preventive service)
    "G0307"    # CBC with differential (Medicare preventive service)
  ),
  cbc_loinc = c(
    "58410-2", # CBC panel - Blood by Automated count
    "57021-8", # CBC W Auto Differential panel - Blood
    "57782-5", # CBC W Ordered Manual Differential panel - Blood
    "57022-6", # CBC W Differential panel - Blood (unspecified method)
    "24364-2"  # CBC panel - Blood (alternate)
  )
)

# ------------------------------------------------------------------------------
# 5.7 LAB CODES (Phase 10) -- transcribed from VariableDetails.xlsx "Labs" sheet
# ------------------------------------------------------------------------------
#
# Lab types: CRP, ALT, AST, ALP, GGT, Bilirubin, Platelets, FOBT
# TSH and CBC LOINC codes are included here (duplicated from SURVEILLANCE_CODES
# for convenience in lab-specific queries)
#
# Note: platelets LOINC 777-3 is broad (covers all platelet count methods).
# APRI Index (86465-2) and PDF (80563-0) are derived/calculated values included
# for completeness as they appear in the Labs sheet.
#
# Source: VariableDetails.xlsx "Labs" sheet (2025 extract)
LAB_CODES <- list(
  # C-reactive protein
  crp_cpt   = c("86141"),     # CRP, high sensitivity (cardiac)
  crp_loinc = c("30522-7"),   # C-Reactive Protein, Cardiac (high sensitivity)

  # Liver function tests -- ALT
  alt_cpt   = c("84460"),     # Alanine amino transferase (ALT/SGPT)
  alt_loinc = c("1742-6"),    # ALT [Enzymatic activity/volume] in Serum or Plasma

  # Liver function tests -- AST
  ast_cpt   = c("84450"),     # Aspartate amino transferase (AST/SGOT)
  ast_loinc = c("1920-8"),    # AST [Enzymatic activity/volume] in Serum or Plasma

  # Alkaline phosphatase
  alp_cpt   = c("84075"),     # Alkaline phosphatase
  alp_loinc = c("6768-6"),    # ALP [Enzymatic activity/volume] in Serum or Plasma

  # GGT (gamma-glutamyl transferase)
  ggt_cpt   = c("82977"),     # Glutamyltransferase, gamma (GGT)
  ggt_loinc = c("2324-2"),    # GGT [Enzymatic activity/volume] in Serum or Plasma

  # Bilirubin
  bilirubin_cpt   = c("82247"),             # Bilirubin, total
  bilirubin_loinc = c(
    "1975-2",   # Bilirubin, Total [Mass/volume] in Serum or Plasma
    "1968-7",   # Bilirubin Fraction, Neonatal
    "1971-1"    # Bili, Indirect, Neonatal
  ),

  # Platelets (from Labs sheet -- no CPT listed)
  platelets_loinc = c(
    "777-3",    # Platelets [#/volume] in Blood by Automated count
    "86465-2",  # APRI Index (APRI = AST/Platelet Ratio Index, derived value)
    "80563-0"   # PDF (platelet distribution function, derived value)
  ),

  # Fecal occult blood test (FOBT)
  fobt_cpt   = c("82274"),     # Blood, occult, by immunoassay (FOBT, iFOBT)
  fobt_loinc = c("29771-3"),   # Hemoglobin.gastrointestinal [Presence] in Stool by Immunoassay

  # TSH (duplicated from SURVEILLANCE_CODES for lab query convenience)
  tsh_loinc = c(
    "11580-8", # Thyrotropin [Units/volume] in Serum or Plasma
    "3024-7"   # Thyrotropin [Units/volume] in Serum or Plasma (variant)
  ),

  # CBC (duplicated from SURVEILLANCE_CODES for lab query convenience)
  cbc_loinc = c(
    "58410-2", # CBC panel - Blood by Automated count
    "57021-8", # CBC W Auto Differential panel - Blood
    "57782-5", # CBC W Ordered Manual Differential panel - Blood
    "57022-6", # CBC W Differential panel - Blood (unspecified method)
    "24364-2"  # CBC panel - Blood (alternate)
  )
)

# ------------------------------------------------------------------------------
# 5.8 SURVIVORSHIP CODES (Phase 10) -- personal history codes per D-09
# ------------------------------------------------------------------------------
#
# Used by 14_survivorship_encounters.R to identify patients with personal history
# of chemotherapy/radiation (cancer survivor status).
#
# ICD-9-CM V codes and ICD-10-CM Z codes for personal history of chemotherapy,
# radiation, and antineoplastic therapy.
#
# Source: RESEARCH.md D-09 verified NUCC/ICD codes
SURVIVORSHIP_CODES <- list(
  personal_history_icd9 = c(
    "V87.41",  # Personal history of antineoplastic chemotherapy
    "V87.42",  # Personal history of monoclonal drug therapy
    "V87.43",  # Personal history of estrogen therapy
    "V87.46",  # Personal history of immunosuppression therapy
    "V15.3"    # Personal history of irradiation
  ),
  personal_history_icd10 = c(
    "Z92.21",  # Personal history of antineoplastic chemotherapy
    "Z92.22",  # Personal history of monoclonal drug therapy
    "Z92.23",  # Personal history of estrogen therapy
    "Z92.25",  # Personal history of immunosuppression therapy
    "Z92.3"    # Personal history of irradiation
  )
)

# ------------------------------------------------------------------------------
# 5.9 PROVIDER SPECIALTIES (Phase 10) -- NUCC taxonomy codes per D-10
# ------------------------------------------------------------------------------
#
# Used by 14_survivorship_encounters.R and 13_surveillance.R to identify
# oncology provider encounters (surveillance visits with oncology providers).
#
# NUCC taxonomy codes sourced from RESEARCH.md verified NUCC Health Care Provider
# Taxonomy Code Set (effective 2025).
PROVIDER_SPECIALTIES <- list(
  cancer_oncology = c(
    "207RH0000X",  # Internal Medicine: Hematology
    "207RH0003X",  # Internal Medicine: Hematology & Oncology
    "207RX0202X",  # Internal Medicine: Medical Oncology
    "2085R0001X",  # Radiology: Radiation Oncology
    "2086X0206X",  # Surgery: Surgical Oncology
    "2080P0207X"   # Pediatrics: Pediatric Hematology-Oncology
  )
)

# ------------------------------------------------------------------------------
# 6. AUTO-SOURCE UTILITY FUNCTIONS
# ------------------------------------------------------------------------------

# Load date parsing and attrition logging utilities
# These are sourced automatically when 00_config.R is loaded
source("R/utils_dates.R")
source("R/utils_attrition.R")
source("R/utils_icd.R")

# ==============================================================================
# End of configuration
# ==============================================================================
