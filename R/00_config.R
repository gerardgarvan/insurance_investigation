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
  output_dir = "output"
)

# ------------------------------------------------------------------------------
# 2. PCORNET CDM TABLE PATHS
# ------------------------------------------------------------------------------

# Primary load set: 9 tables
# - 6 standard CDM tables: ENROLLMENT, DIAGNOSIS, PROCEDURES, PRESCRIBING,
#   ENCOUNTER, DEMOGRAPHIC
# - 3 TUMOR_REGISTRY tables: contain HL-specific diagnosis dates (DATE_OF_DIAGNOSIS)
#   and treatment dates (DT_CHEMO, DT_RAD, etc.)
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
  "TUMOR_REGISTRY3"
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
    "C81.90", "C81.91", "C81.92", "C81.93", "C81.94", "C81.95", "C81.96", "C81.97", "C81.98", "C81.99"
  ),

  # ICD-9-CM: 201.xx (72 codes total)
  # 8 subtypes × 9 anatomic sites (0-8)
  # No 201.3x in ICD-9-CM (gap in Hodgkin coding)
  #
  # Anatomic site codes: 0=unspecified, 1=head/neck, 2=intrathoracic,
  # 3=intra-abdominal, 4=axilla/upper limb, 5=inguinal/lower limb,
  # 6=intrapelvic, 7=spleen, 8=multiple sites
  hl_icd9 = c(
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
# evidence in PROCEDURES (CPT/HCPCS) and PRESCRIBING (RXNORM) tables.
#
# Primary treatment evidence comes from TUMOR_REGISTRY date columns:
#   - TR1: CHEMO_START_DATE_SUMMARY (chemo), no DT_RAD column
#   - TR2/TR3: DT_CHEMO, DT_RAD, DT_HTE (hematologic transplant/endocrine)
# Supplemental evidence comes from PROCEDURES and PRESCRIBING codes below.
#
# Per D-07: HAD_SCT covers both autologous and allogeneic (single flag).
#
# Sources:
#   - Radiation CPT: CMS 2026 complexity-based codes (77385/77386 deleted 2026-01-01)
#   - SCT CPT: ASBMT coding guidelines (38240-38243)
#   - Chemo RXNORM: ABVD regimen components (standard first-line HL treatment)
#   - Chemo HCPCS: J-code range for injectable chemotherapy drugs

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
    "77427",   # Radiation treatment management (weekly, per 5 fractions) - most common
    "77407",   # Radiation treatment delivery, simple (2026 new code)
    "77412",   # Radiation treatment delivery, complex (2026 new code)
    "77402"    # Radiation treatment delivery, intermediate (2026 new code)
  ),

  # Stem cell transplant CPT codes (autologous + allogeneic per D-07)
  sct_cpt = c(
    "38240",   # Allogeneic HPC transplantation
    "38241",   # Autologous HPC transplantation
    "38242",   # Allogeneic donor lymphocyte infusion (DLI)
    "38243"    # Allogeneic HPC boost
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
