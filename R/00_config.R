# ==============================================================================
# PCORnet Payer Variable Investigation (R Pipeline)
# Configuration File
# ==============================================================================
#
# This file defines all project-wide configuration including:
#   - Data paths (HiPerGator /orange and /blue directories)
#   - PCORnet CDM table paths (9 primary tables for loading)
#   - ICD code lists (150 Hodgkin Lymphoma diagnosis codes)
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

# Extract date for current PCORnet CDM data pull (Mailhot_V1_20250915)
# Update this when a new extract arrives. Used for ingest log filenames.
EXTRACT_DATE <- "2025-09-15"

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
  ),

  # ---------------------------------------------------------------------------
  # RDS Cache Settings (Phase 15)
  # ---------------------------------------------------------------------------
  # Persistent RDS cache for loaded PCORnet tables. After first CSV parse,
  # tables are serialized to .rds files. Subsequent runs load from cache
  # if the .rds file is newer than the source CSV (file.mtime() comparison).
  #
  # IMPORTANT: cache_dir is GITIGNORED and must NOT be a repo-internal path.
  # See .gitignore: /blue/erin.mobley-hl.bcu/clean/ is excluded from git.
  # RDS files are 100MB-2GB each; committing them would break the repository.
  cache = list(
    # Base RDS cache directory (gitignored: /blue/erin.mobley-hl.bcu/clean/)
    # IMPORTANT: cache_dir is GITIGNORED and must NOT be a repo-internal path.
    # RDS files are 100MB-2GB each; committing them would break the repository.
    cache_dir    = "/blue/erin.mobley-hl.bcu/clean/rds",
    force_reload = FALSE,   # Set to TRUE to bypass cache and re-parse all CSVs

    # Phase 15: Raw PCORnet table cache
    raw_dir      = "/blue/erin.mobley-hl.bcu/clean/rds/raw",

    # Phase 16: Cohort filter step snapshots
    cohort_dir   = "/blue/erin.mobley-hl.bcu/clean/rds/cohort",

    # Phase 16: Figure/table backing data snapshots
    outputs_dir  = "/blue/erin.mobley-hl.bcu/clean/rds/outputs",

    # Phase 29: DuckDB file storage (gitignored via /blue/erin.mobley-hl.bcu/clean/)
    duckdb_dir   = "/blue/erin.mobley-hl.bcu/clean/duckdb",
    duckdb_path  = "/blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb"
  )
)

# ------------------------------------------------------------------------------
# 1.5 BACKEND SELECTION (Phase 30, default flipped Phase 32)
# ------------------------------------------------------------------------------
# Toggle between RDS in-memory tibbles and DuckDB lazy SQL queries.
# FALSE = RDS mode: tables loaded via pcornet$TABLE_NAME list
# TRUE  = DuckDB mode (default): tables accessed via get_pcornet_table() returning tbl_dbi
#
# When TRUE, open_pcornet_con() is called automatically in 01_load_pcornet.R.
# All downstream scripts use get_pcornet_table() for backend-transparent access.
#
# DEPRECATION NOTICE (Phase 32, 2026-04-23):
#   RDS mode (USE_DUCKDB = FALSE) is retained for backward compatibility and
#   bisecting against historical behavior. It will be removed in a future milestone.
#   New scripts should use DuckDB mode exclusively.
#   See docs/DUCKDB_MIGRATION_GUIDE.md for the migration pattern.
USE_DUCKDB <- TRUE

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
# 3. ICD CODE LISTS (150 Hodgkin Lymphoma diagnosis codes)
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

  # ICD-9-CM: 201.xx (72 site-specific + 8 parent codes + 1 bare parent = 81 total)
  # 8 subtypes × 9 anatomic sites (0-8) + parent codes without site digit
  # No 201.3x in ICD-9-CM (gap in Hodgkin coding)
  #
  # Anatomic site codes: 0=unspecified, 1=head/neck, 2=intrathoracic,
  # 3=intra-abdominal, 4=axilla/upper limb, 5=inguinal/lower limb,
  # 6=intrapelvic, 7=spleen, 8=multiple sites
  hl_icd9 = c(
    # Phase 18: Added "201" (unspecified parent, no subtype digit) found in gap analysis
    # for 1 Neither patient at site LNK. Bare 3-digit code did not match 4-5 digit variants.
    "201",

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
# 4. PAYER MAPPING RULES (AMC 8-category system)
# ------------------------------------------------------------------------------
#
# Category assignment uses a direct code-to-category lookup table derived from
# payer_primary_codes_frequency_AMC.xlsx (Amy Crisp framework).
# "New Category" column overrides "Category" column where non-blank.
#
# Effective payer (per encounter): primary if valid, else secondary if valid
# Sentinel values (trigger fallback to secondary): null, "", "NI", "UN", "OT"
#
# 8 categories: Medicaid, Medicare, Private, Other govt, Other, Self-pay,
#               Uninsured, Missing
#
# Key differences from prior 9-category system:
#   - "Dual eligible" removed — code 14 maps to Medicaid
#   - "Other government" renamed to "Other govt"
#   - "No payment / Self-pay" split: 81 → Self-pay, 8/821 → Uninsured
#   - "Unknown" and "Unavailable" merged into "Missing"
#   - NI, UN, 9999 → Missing (were Unknown/Unavailable)
#   - OT → Other (was Unknown)
#   - 311 (TRICARE) → Private (was Other govt)
#   - Prefix 7 → Private (was Other)
# ------------------------------------------------------------------------------

# Direct code-to-category lookup from AMC spreadsheet
# Source: payer_primary_codes_frequency_AMC.xlsx (New Category overrides Category)
AMC_PAYER_LOOKUP <- c(
  # Medicaid codes
  "219"   = "Medicaid",    # Medicaid Managed Care Other
  "29"    = "Medicaid",    # Medicaid Other
  "14"    = "Medicaid",    # Dual Eligibility Medicare/Medicaid Organization
  "141"   = "Medicaid",    # Dual Eligibility (subcode)
  "142"   = "Medicaid",    # Dual Eligibility (subcode)
  "211"   = "Medicaid",    # Medicaid HMO
  "213"   = "Medicaid",    # Medicaid PCCM
  "21"    = "Medicaid",    # Medicaid (Managed Care)
  "2"     = "Medicaid",    # Medicaid
  "23"    = "Medicaid",    # Medicaid/SCHIP
  "25"    = "Medicaid",    # Medicaid - Out of State

  # Medicare codes
  "1"     = "Medicare",    # Medicare
  "19"    = "Medicare",    # Medicare Other
  "11"    = "Medicare",    # Medicare (Managed Care)
  "111"   = "Medicare",    # Medicare HMO

  # Private codes
  "6"     = "Private",     # Blue Cross/Blue Shield
  "5"     = "Private",     # Private Health Insurance
  "511"   = "Private",     # Commercial Managed Care - HMO
  "51"    = "Private",     # Managed Care (Private)
  "52"    = "Private",     # Private Health Insurance - Indemnity
  "71"    = "Private",     # HMO
  "513"   = "Private",     # Commercial Managed Care - POS
  "7"     = "Private",     # Managed Care, Unspecified
  "521"   = "Private",     # Commercial Indemnity
  "623"   = "Private",     # BC Medicare Supplemental Plan
  "512"   = "Private",     # Commercial Managed Care - PPO
  "529"   = "Private",     # Private health insurance - other commercial Indemnity
  "311"   = "Private",     # TRICARE (CHAMPUS) — reclassified from Other govt per AMC

  # Missing codes
  "NI"    = "Missing",     # No information — reclassified from Uninsured per AMC
  "9999"  = "Missing",     # Unavailable / No Payer Specified — reclassified per AMC
  "UN"    = "Missing",     # Unknown — reclassified from Uninsured per AMC
  "99"    = "Missing",     # Unavailable (short code)
  "UNKNOWN" = "Missing",   # Unknown (text form)

  # Other codes
  "OT"    = "Other",       # Other
  "95"    = "Other",       # Worker's Compensation
  "9"     = "Other",       # Miscellaneous/other
  "92"    = "Other",       # Other (Non-government)
  "96"    = "Other",       # Auto Insurance

  # Self-pay codes
  "81"    = "Self-pay",    # Self-pay — split from Uninsured per AMC

  # Uninsured codes
  "821"   = "Uninsured",   # Charity
  "8"     = "Uninsured",   # No payment from Organization/Agency/Program

  # Other govt codes
  "382"   = "Other govt",  # Federal, State, Local not specified - FFS
  "349"   = "Other govt",  # Other
  "3"     = "Other govt",  # Other Government (excl. Corrections)
  "32126" = "Other govt",  # Other Federal Agency
  "32121" = "Other govt",  # Fee Basis
  "32"    = "Other govt",  # Department of Veterans Affairs
  "44"    = "Other govt"   # Corrections Unknown Level
)

PAYER_MAPPING <- list(
  # Sentinel values (trigger fallback to secondary payer when appearing as primary)
  sentinel_values = c("NI", "UN", "OT"),

  # Dual-eligible codes (kept for informational DUAL_ELIGIBLE flag, not for category override)
  dual_eligible_codes = c("14", "141", "142"),

  # Prefix-based fallback (for codes not found in AMC_PAYER_LOOKUP)
  prefix_fallback = list(
    "1" = "Medicare",
    "2" = "Medicaid",
    "3" = "Other govt",
    "4" = "Other govt",
    "5" = "Private",
    "6" = "Private",
    "7" = "Private",
    "8" = "Uninsured",
    "9" = "Other"
  ),

  # 8 standard categories (AMC framework)
  categories = c(
    "Medicaid",
    "Medicare",
    "Private",
    "Other govt",
    "Other",
    "Self-pay",
    "Uninsured",
    "Missing"
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
  treatment_window_days = 30,

  # Date range validation bounds (used in 01_load_pcornet.R date validation)
  # Catches SAS epoch (1899-12-30) and Excel epoch (1900-01-01) sentinels as lower bound
  # Upper bound is end of data collection period
  date_range_min = as.Date("1901-01-01"),
  date_range_max = as.Date("2025-03-31")
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
    "J9299",    # Nivolumab (Opdivo)
    "J9017",   # Phase 39: J9017
    "J9019",   # Phase 39: J9019
    "J9021",   # Phase 39: J9021
    "J9022",   # Phase 39: J9022
    "J9025",   # Phase 39: J9025
    "J9030",   # Phase 39: J9030
    "J9033",   # Phase 39: J9033
    "J9034",   # Phase 39: J9034
    "J9035",   # Phase 39: J9035
    "J9036",   # Phase 39: J9036
    "J9039",   # Phase 39: J9039
    "J9041",   # Phase 39: J9041
    "J9043",   # Phase 39: J9043
    "J9045",   # Phase 39: J9045
    "J9047",   # Phase 39: J9047
    "J9050",   # Phase 39: J9050
    "J9055",   # Phase 39: J9055
    "J9057",   # Phase 39: J9057
    "J9058",   # Phase 39: J9058
    "J9060",   # Phase 39: J9060
    "J9065",   # Phase 39: J9065
    "J9070",   # Phase 39: J9070
    "J9071",   # Phase 39: J9071
    "J9073",   # Phase 39: J9073
    "J9075",   # Phase 39: J9075
    "J9098",   # Phase 39: J9098
    "J9100",   # Phase 39: J9100
    "J9118",   # Phase 39: J9118
    "J9119",   # Phase 39: J9119
    "J9145",   # Phase 39: J9145
    "J9150",   # Phase 39: J9150
    "J9171",   # Phase 39: J9171
    "J9173",   # Phase 39: J9173
    "J9178",   # Phase 39: J9178
    "J9179",   # Phase 39: J9179
    "J9181",   # Phase 39: J9181
    "J9185",   # Phase 39: J9185
    "J9190",   # Phase 39: J9190
    "J9196",   # Phase 39: J9196
    "J9200",   # Phase 39: J9200
    "J9201",   # Phase 39: J9201
    "J9202",   # Phase 39: J9202
    "J9204",   # Phase 39: J9204
    "J9206",   # Phase 39: J9206
    "J9207",   # Phase 39: J9207
    "J9208",   # Phase 39: J9208
    "J9209",   # Phase 39: J9209
    "J9217",   # Phase 39: J9217
    "J9218",   # Phase 39: J9218
    "J9223",   # Phase 39: J9223
    "J9228",   # Phase 39: J9228
    "J9230",   # Phase 39: J9230
    "J9245",   # Phase 39: J9245
    "J9246",   # Phase 39: J9246
    "J9250",   # Phase 39: J9250
    "J9260",   # Phase 39: J9260
    "J9261",   # Phase 39: J9261
    "J9263",   # Phase 39: J9263
    "J9264",   # Phase 39: J9264
    "J9265",   # Phase 39: J9265
    "J9266",   # Phase 39: J9266
    "J9267",   # Phase 39: J9267
    "J9268",   # Phase 39: J9268
    "J9271",   # Phase 39: J9271
    "J9280",   # Phase 39: J9280
    "J9286",   # Phase 39: J9286
    "J9293",   # Phase 39: J9293
    "J9301",   # Phase 39: J9301
    "J9302",   # Phase 39: J9302
    "J9304",   # Phase 39: J9304
    "J9305",   # Phase 39: J9305
    "J9306",   # Phase 39: J9306
    "J9307",   # Phase 39: J9307
    "J9308",   # Phase 39: J9308
    "J9309",   # Phase 39: J9309
    "J9310",   # Phase 39: J9310
    "J9311",   # Phase 39: J9311
    "J9312",   # Phase 39: J9312
    "J9315",   # Phase 39: J9315
    "J9317",   # Phase 39: J9317
    "J9319",   # Phase 39: J9319
    "J9321",   # Phase 39: J9321
    "J9330",   # Phase 39: J9330
    "J9340",   # Phase 39: J9340
    "J9349",   # Phase 39: J9349
    "J9351",   # Phase 39: J9351
    "J9354",   # Phase 39: J9354
    "J9355",   # Phase 39: J9355
    "J9358",   # Phase 39: J9358
    "J9359",   # Phase 39: J9359
    "J9370",   # Phase 39: J9370
    "J9371",   # Phase 39: J9371
    "J9390",   # Phase 39: J9390
    "J9395",   # Phase 39: J9395
    "J9999"    # Phase 39: J9999
  ),

  # Chemotherapy RXNORM CUIs for PRESCRIBING table matching
  # ABVD regimen base ingredients (RxNorm concept IDs)
  chemo_rxnorm = c(
    "3639",    # Doxorubicin
    "11213",   # Bleomycin
    "67228",   # Vinblastine
    "3946",     # Dacarbazine
    "239178",   # Phase 40: vinblastine sulfate 1 MG/ML Injectable S
    "1657195",   # Phase 40: 10 ML nivolumab 10 MG/ML Injection
    "1791591",   # Phase 40: ifosfamide 3000 MG Injection [Ifex]
    "207588",   # Phase 40: procarbazine 50 MG Oral Capsule [Matulan
    "1991412",   # Phase 40: 24 ML nivolumab 10 MG/ML Injection
    "134547",   # Phase 40: bendamustine
    "1799305",   # Phase 40: DOXOrubicin  IV infusion,
    "1147327",   # Phase 40: brentuximab vedotin 50 MG Injection [Adc
    "1657750",   # Phase 40: 4 ML pembrolizumab 25 MG/ML Injection
    "105585",   # Phase 40: methotrexate 2.5 MG Oral Tablet
    "1863354",   # Phase 40: 2 ML vincristine sulfate 1 MG/ML Injecti
    "1790115",   # Phase 40: 10 ML doxorubicin hydrochloride liposome
    "1655960",   # Phase 40: 2 ML methotrexate 25 MG/ML Injection
    "1791598",   # Phase 40: ifosfamide IV infusion
    "1946772",   # Phase 40: methotrexate 25 MG/ML Injectable Solutio
    "3098",   # Phase 40: dacarbazine
    "1147324",   # Phase 40: Adcetris
    "311627",   # Phase 40: METHOTREXATE SODIUM (PF) 25 MG/ML  CUSTO
    "1734921",   # Phase 40: cyclophosphamide 2000 MG Injection
    "2105",   # Phase 40: carmustine
    "11198",   # Phase 40: vinblastine
    "1114693",   # Phase 40: bendamustine hydrochloride
    "105587",   # Phase 40: methotrexate 2.5 MG Oral Tablet [Maxtrex
    "1544390",   # Phase 40: 0.35 ML methotrexate 50 MG/ML Auto-Injec
    "1657196",   # Phase 40: 10 ML nivolumab 10 MG/ML Injection [Opdi
    "1657751",   # Phase 40: 4 ML pembrolizumab 25 MG/ML Injection [K
    "1726673",   # Phase 40: bleomycin 15 UNT Injection
    "1790099",   # Phase 40: 10 ML doxorubicin hydrochloride 2 MG/ML 
    "1734919",   # Phase 40: cyclophosphamide 1000 MG Injection
    "894900",   # Phase 40: VINCRISTINE SULFATE 1 MG/ML IV CUSTOM CO
    "637543",   # Phase 40: CYCLOPHOSPHAMIDE  CUSTOM COMPONENT IJ SO
    "1597876",   # Phase 40: nivolumab
    "314167",   # Phase 40: procarbazine 50 MG Oral Capsule
    "1734340",   # Phase 40: etoposide 100 MG Injection
    "1863349",   # Phase 40: vinCRIStine
    "1791593",   # Phase 40: ifosfamide 1000 MG Injection
    "2568661",   # Phase 40: 5 ML cyclophosphamide 200 MG/ML Injectio
    "1541215",   # Phase 40: Methotrexate Sodium 2.5 MG Oral Tablet
    "5657",   # Phase 40: ifosfamide
    "1791588",   # Phase 40: ifosfamide 3000 MG Injection
    "1790097",   # Phase 40: 5 ML doxorubicin hydrochloride 2 MG/ML I
    "1805001",   # Phase 40: bendamustine hydrochloride 100 MG Inject
    "1790127",   # Phase 40: 25 ML doxorubicin hydrochloride liposome
    "1991413",   # Phase 40: 24 ML nivolumab 10 MG/ML Injection [Opdi
    "1191138",   # Phase 40: doxorubicin hydrochloride 2 MG/ML Inject
    "1731338",   # Phase 40: dacarbazine 200 MG Injection
    "1791597",   # Phase 40: 60 ML ifosfamide 50 MG/ML Injection
    "1719000",   # Phase 40: gemcitabine 200 MG Injection
    "1799307",   # Phase 40: DOXOrubicin  IV infusion,
    "1726097",   # Phase 40: bendamustine hydrochloride 25 MG/ML Inje
    "1790103",   # Phase 40: doxorubicin hydrochloride 10 MG Injectio
    "1655956",   # Phase 40: 40 ML methotrexate 25 MG/ML Injection
    "1437713",   # Phase 40: mechlorethamine 0.00016 MG/MG Topical Ge
    "11202",   # Phase 40: vincristine
    "6851",   # Phase 40: methotrexate
    "1655968",   # Phase 40: 8 ML methotrexate 25 MG/ML Injection
    "1544398",   # Phase 40: 0.5 ML methotrexate 50 MG/ML Auto-Inject
    "1147320",   # Phase 40: brentuximab vedotin
    "309311",   # Phase 40: cisplatin 1 MG/ML Injectable Solution
    "1734917",   # Phase 40: cyclophosphamide 500 MG Injection
    "310973",   # Phase 40: IFOSFAMIDE 3 G IV SOLR CUSTOM COMPONENT
    "283510",   # Phase 40: methotrexate 15 MG Oral Tablet
    "1544388",   # Phase 40: 0.3 ML methotrexate 50 MG/ML Auto-Inject
    "1863355",   # Phase 40: 2 ML vincristine sulfate 1 MG/ML Injecti
    "1719003",   # Phase 40: gemcitabine 1000 MG Injection
    "1726102",   # Phase 40: bendamustine hydrochloride 25 MG/ML Inje
    "597195",   # Phase 40: carboplatin 10 MG/ML Injectable Solution
    "206831",   # Phase 40: etoposide 20 MG/ML Injectable Solution [
    "197687",   # Phase 40: etoposide 50 MG Oral Capsule
    "4179",   # Phase 40: etoposide
    "309638",   # Phase 40: DACARBAZINE 200 MG IV CUSTOM COMPONENT  
    "1720975",   # Phase 40: 52.6 ML gemcitabine 38 MG/ML Injection
    "1657193",   # Phase 40: Nivolumab
    "1719013",   # Phase 40: gemcitabine IV infusion
    "205821",   # Phase 40: CISplatin IV infusion
    "1147323",   # Phase 40: brentuximab vedotin 50 MG Injection
    "1790100",   # Phase 40: 25 ML doxorubicin hydrochloride 2 MG/ML 
    "686161",   # Phase 40: carboplatin 10 MG/ML Injectable Solution
    "1863347",   # Phase 40: 1 ML vincristine sulfate 1 MG/ML Injecti
    "1731340",   # Phase 40: dacarbazine 100 MG Injection
    "1657749",   # Phase 40: pembrolizumab 50 MG Injection [Keytruda]
    "1655959",   # Phase 40: 10 ML methotrexate 25 MG/ML Injection
    "1437969",   # Phase 40: cyclophosphamide 50 MG Oral Capsule
    "1622",   # Phase 40: bleomycin
    "105604",   # Phase 40: procarbazine 50 MG Oral Capsule [Natulan
    "310248",   # Phase 40: etoposide 20 MG/ML Injectable Solution
    "1863343",   # Phase 40: 1 ML vincristine sulfate 1 MG/ML Injecti
    "226719",   # Phase 40: etoposide 100 MG Injection [Etopophos]
    "1998783",   # Phase 40: gemcitabine 100 MG/ML Injectable Solutio
    "1657192",   # Phase 40: 4 ML nivolumab 10 MG/ML Injection [Opdiv
    "1790098",   # Phase 40: DOXOrubicin  IV infusion,
    "2555",   # Phase 40: cisplatin
    "105586",   # Phase 40: methotrexate 10 MG Oral Tablet
    "1921592",   # Phase 40: methotrexate 2.5 MG/ML Oral Solution
    "2001102",   # Phase 40: ADRIAMYCIN IV
    "309012",   # Phase 40: carmustine 100 MG Injection
    "287734",   # Phase 40: methotrexate sodium
    "308770",   # Phase 40: Bleomycin Sulfate For Inj 30 Unit
    "8702",   # Phase 40: procarbazine
    "3002",   # Phase 40: cyclophosphamide
    "311625",   # Phase 40: methotrexate 1000 MG Injection
    "1657190",   # Phase 40: 4 ML nivolumab 10 MG/ML Injection
    "1790129",   # Phase 40: doxorubicin hydrochloride liposome 2 MG/
    "308771",   # Phase 40: Bleomycin Sulfate For Inj 30 Unit
    "1726676",   # Phase 40: bleomycin 30 UNT Injection
    "197550",   # Phase 40: cyclophosphamide 50 MG Oral Tablet
    "1441411",   # Phase 40: 0.4 ML methotrexate 37.5 MG/ML Auto-Inje
    "283511"    # Phase 40: methotrexate 5 MG Oral Tablet
  ),

  # AMA CPT Radiation Oncology Chapter Structure (Codes 77261-77799)
  # ---------------------------------------------------------------
  # TreatmentVariables.docx specifies the full radiology range 70010-79999.
  # The AMA CPT Manual divides this range as follows:
  #   70010-76499  Diagnostic Radiology (X-ray, CT, MRI, angiography)
  #   76506-76999  Diagnostic Ultrasound
  #   77001-77067  Radiological Guidance + Mammography (imaging, not treatment)
  #   77261-77299  Radiation Treatment Planning (clinical simulation)
  #   77295-77370  Medical Radiation Physics, Dosimetry, Treatment Devices
  #   77371-77499  Radiation Treatment Delivery (EBRT, IMRT, SRS, SBRT, proton)
  #   77520-77525  Proton Beam Treatment Delivery (subset of above range)
  #   77600-77620  Hyperthermia (thermal adjunct to radiation)
  #   77750-77799  Clinical Brachytherapy
  #   78000-78999  Nuclear Medicine (mostly diagnostic; 78800-78816 are therapeutic)
  #
  # RECOMMENDATION: Use 77261-77799 (radiation oncology chapter only), not 70010-79999.
  # The pipeline uses 77261-77799 codes exclusively — imaging codes are excluded by design.
  radiation_cpt = c(
    # --- Treatment Planning (77261-77299) ---
    "77261",   # Therapeutic radiology treatment planning; simple
    "77262",   # Therapeutic radiology treatment planning; intermediate
    "77263",   # Therapeutic radiology treatment planning; complex
    "77280",   # Therapeutic radiology simulation-aided field setting; simple
    "77285",   # Therapeutic radiology simulation-aided field setting; intermediate
    "77290",   # Therapeutic radiology simulation-aided field setting; complex
    "77293",   # Respiratory motion management simulation

    # --- Physics, Dosimetry & Treatment Devices (77295-77370) ---
    "77295",   # 3-dimensional radiotherapy plan, including dose-volume histograms
    "77300",   # Basic radiation dosimetry calculation
    "77301",   # Intensity modulated radiotherapy plan (IMRT)
    "77306",   # Teletherapy isodose plan; simple
    "77307",   # Teletherapy isodose plan; complex
    "77310",   # Teletherapy isodose plan; brachytherapy isodose calc, simple (DELETED)
    "77315",   # Teletherapy isodose plan; brachytherapy isodose calc, complex (DELETED)
    "77316",   # Brachytherapy isodose plan; simple
    "77318",   # Brachytherapy isodose plan; complex
    "77321",   # Special teletherapy port plan
    "77331",   # Special dosimetry (TLD, calorimetry, etc.)
    "77332",   # Treatment devices, simple
    "77333",   # Treatment devices, intermediate
    "77334",   # Treatment devices, complex
    "77336",   # Continuing medical physics consultation
    "77338",   # Multi-leaf collimator (MLC) device design and fabrication
    "77370",   # Special medical radiation physics consultation

    # --- Treatment Delivery (77371-77499) ---
    "77371",   # SRS, multi-source Gamma Knife (DELETED 2026)
    "77372",   # SRS, linear accelerator based (DELETED 2026)
    "77373",   # Stereotactic body radiation therapy (SBRT), treatment delivery
    "77385",   # IMRT delivery, simple
    "77386",   # IMRT delivery, complex
    "77387",   # Guidance for radiation treatment delivery (IGRT)
    "77399",   # Unlisted procedure, radiation treatment delivery
    "77401",   # External beam radiation delivery, surface/orthovoltage (DELETED 2026; historical claims only)
    "77402",   # Radiation treatment delivery, intermediate (2026 new code)
    "77404",   # Radiation treatment delivery; single area, 6-10 MeV (DELETED 2015)
    "77407",   # Radiation treatment delivery, simple (2026 new code)
    "77408",   # Radiation treatment delivery; 2 separate areas, 3+ ports, 6-10 MeV (DELETED 2015)
    "77412",   # Radiation treatment delivery, complex (2026 new code)
    "77413",   # Radiation treatment delivery; 3+ areas, custom blocking, 6-10 MeV (DELETED 2015)
    "77414",   # Radiation treatment delivery; 3+ areas, custom blocking, 11-19 MeV (DELETED 2015)
    "77416",   # Radiation treatment delivery; 3+ areas, complex, 20+ MeV (DELETED 2015)
    "77417",   # Port film(s) per treatment session (portal imaging) (DELETED 2026)
    "77418",   # Radiation treatment delivery, IMRT (intensity modulated) (DELETED 2015)
    "77421",   # Stereoscopic x-ray guidance for target localization (DELETED 2015)
    "77427",   # Radiation treatment management (weekly, per 5 fractions) - most common
    "77431",   # Radiation treatment management, 1-4 treatments (end-of-course)
    "77432",   # Stereotactic radiation treatment management of cranial lesion
    "77435",   # Stereotactic body radiation therapy (SBRT) management
    "77470",   # Special treatment procedure (total body irradiation, hemibody irradiation)

    # --- Proton Beam Treatment Delivery (77520-77525) ---
    "77520",   # Proton treatment delivery; simple, without compensation
    "77522",   # Proton treatment delivery; simple, with compensation
    "77523",   # Proton treatment delivery; intermediate
    "77525",   # Proton treatment delivery; complex

    # --- Hyperthermia (77600-77620) ---
    "77605",   # Hyperthermia, externally generated; deep (DELETED)

    # --- Brachytherapy (77750-77799) ---
    "77750",   # Infusion or instillation of radioelement solution
    "77763",   # Interstitial radiation source application; complex
    "77768",   # Intracavitary radiation source application; complex
    "77770",   # Remote afterloading high dose rate brachytherapy; 1 channel
    "77771",   # Remote afterloading high dose rate brachytherapy; 2-12 channels
    "77772",   # Remote afterloading high dose rate brachytherapy; over 12 channels
    "77785",   # Remote afterloading brachytherapy; 1-4 sources/ribbons, complex (DELETED)

    # --- CMS G-codes: Radiation Delivery (DELETED 2026) ---
    "G6012",   # Radiation treatment delivery, 3D conformal, intermediate (DELETED 2026)
    "G6013",   # Radiation treatment delivery, 3D conformal, complex (DELETED 2026)
    "G6015"    # Radiation treatment delivery, IMRT, complex (DELETED 2026)
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
    "3E00X05",  # Antineoplastic into skin/mucous membranes, external approach
    "3E01305",  # Antineoplastic into subcutaneous tissue, percutaneous
    "3E0130M",  # Monoclonal antibody antineoplastic into subcutaneous tissue, percutaneous
    "3E02305",  # Antineoplastic into muscle, percutaneous
    "3E03005",  # Antineoplastic into peripheral vein, open
    "3E03305",  # Antineoplastic into peripheral vein, percutaneous
    "3E0330M",  # Monoclonal antibody antineoplastic into peripheral vein, percutaneous
    "3E04005",  # Antineoplastic into central vein, open
    "3E04305",  # Antineoplastic into central vein, percutaneous
    "3E0430M",  # Monoclonal antibody antineoplastic into central vein, percutaneous
    "3E05305",  # Antineoplastic into peripheral artery, percutaneous
    "3E0530M",  # Monoclonal antibody antineoplastic into peripheral artery, percutaneous
    "3E06305",  # Antineoplastic into central artery, percutaneous
    "3E0630M",  # Monoclonal antibody antineoplastic into central artery, percutaneous
    "3E0D705",  # Antineoplastic into mouth/pharynx, via natural opening
    "3E0G305",  # Antineoplastic into upper GI, percutaneous
    "3E0L305",  # Antineoplastic into pleural cavity, percutaneous
    "3E0Q305",  # Antineoplastic into cranial/peripheral nerves, percutaneous
    "3E0R305"   # Antineoplastic into spinal canal, percutaneous (intrathecal chemo)
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
    "XW043N7",   # Lisocabtagene maraleucel, central vein
    "XW033A3",   # Phase 39: no description
    "XW033B3",   # Phase 39: no description
    "XW033C3",   # Phase 39: no description
    "XW033C6",   # Phase 39: no description
    "XW033D6",   # Phase 39: no description
    "XW033E5",   # Phase 39: no description
    "XW033H5",   # Phase 39: no description
    "XW033H6",   # Phase 39: no description
    "XW043A7",   # Phase 39: no description
    "XW043B3",   # Phase 39: no description
    "XW043C3",   # Phase 39: no description
    "XW043C6",   # Phase 39: no description
    "XW043E5",   # Phase 39: no description
    "XW043H5",   # Phase 39: no description
    "XW043P9"    # Phase 39: no description
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
  immunotherapy_drg = c(
    "018"    # Chimeric Antigen Receptor (CAR) T-cell Immunotherapy
  ),

  # Revenue codes (PROCEDURES table PX_TYPE = "RE")

  # Supportive Care RXNORM codes (Phase 40: drug investigation)
  supportive_care_rxnorm = c(
    "1812194",   # Phase 40: 1 ML dexamethasone phosphate 4 MG/ML Inj
    "2057212",   # Phase 40: 1 ML filgrastim-aafi 0.3 MG/ML Injection
    "197582",   # Phase 40: dexamethasone 4 MG Oral Tablet
    "731181",   # Phase 40: 0.4 ML darbepoetin alfa 0.1 MG/ML Prefil
    "338036",   # Phase 40: pegfilgrastim
    "403886",   # Phase 40: Palonosetron HCl IV Soln 0.25 MG/5ML (Ba
    "240912",   # Phase 40: granisetron 1 MG/ML Injectable Solution
    "404465",   # Phase 40: aprepitant 80 MG Oral Capsule [Emend]
    "29225",   # Phase 40: Ondansetron HCl - 8 MG Oral Tablet
    "1728055",   # Phase 40: 5 ML palonosetron 0.05 MG/ML Injection
    "2048025",   # Phase 40: 0.6 ML pegfilgrastim-jmdb 10 MG/ML Prefi
    "197577",   # Phase 40: dexamethasone 0.5 MG Oral Tablet
    "343033",   # Phase 40: dexamethasone 0.75 MG Oral Tablet
    "727544",   # Phase 40: 0.8 ML filgrastim 0.6 MG/ML Prefilled Sy
    "2057218",   # Phase 40: 1.6 ML filgrastim-aafi 0.3 MG/ML Injecti
    "283838",   # Phase 40: darbepoetin alfa
    "2047621",   # Phase 40: 1 ML epoetin alfa-epbx 40000 UNT/ML Inje
    "357280",   # Phase 40: Emend
    "727537",   # Phase 40: 0.5 ML filgrastim 0.6 MG/ML Prefilled Sy
    "1442681",   # Phase 40: 0.5 ML tbo-filgrastim 0.6 MG/ML Prefille
    "1947301",   # Phase 40: 2 ML palonosetron 0.125 MG/ML Injection
    "343040",   # Phase 40: dexamethasone 0.75 MG Oral Tablet [Decad
    "312086",   # Phase 40: ondansetron 8 MG Oral Tablet
    "2549331",   # Phase 40: 0.6 ML pegfilgrastim 10 MG/ML Injection
    "1649963",   # Phase 40: 1.6 ML filgrastim 0.3 MG/ML Injection
    "731184",   # Phase 40: 1 ML darbepoetin alfa 0.5 MG/ML Prefille
    "998032",   # Phase 40: ondansetron 8 MG Oral Film [Zuplenz]
    "6314",   # Phase 40: dexAMETHasone Sodium Phosphate 10 MG/ML 
    "731227",   # Phase 40: 0.4 ML darbepoetin alfa 0.1 MG/ML Prefil
    "68442",   # Phase 40: filgrastim
    "876690",   # Phase 40: ondansetron 4 mg oral tablet, disintegra
    "105694",   # Phase 40: epoetin alfa
    "309682",   # Phase 40: dexamethasone 0.001 MG/MG / tobramycin 0
    "312085",   # Phase 40: ondansetron 0.8 MG/ML Oral Solution
    "2057216",   # Phase 40: 0.8 ML filgrastim-aafi 0.6 MG/ML Prefill
    "1995155",   # Phase 40: 18 ML aprepitant 7.2 MG/ML Injection [Ci
    "240377",   # Phase 40: 1 ML epoetin alfa 3000 UNT/ML Injection
    "1605075",   # Phase 40: 0.8 ML filgrastim-sndz 0.6 MG/ML Prefill
    "105392",   # Phase 40: dexamethasone 0.5 MG Oral Tablet [Decadr
    "70561",   # Phase 40: palonosetron
    "1721690",   # Phase 40: 1 ML epoetin alfa 10000 UNT/ML Injection
    "403810",   # Phase 40: aprepitant 80 MG Oral Capsule
    "1731077",   # Phase 40: fosaprepitant 150 MG Injection
    "1812095",   # Phase 40: 1 ML dexamethasone phosphate 4 MG/ML Pre
    "239999",   # Phase 40: 1 ML epoetin alfa 4000 UNT/ML Injection
    "727542",   # Phase 40: 0.6 ML pegfilgrastim 10 MG/ML Prefilled 
    "2057209",   # Phase 40: 1 ML filgrastim-aafi 0.3 MG/ML Injection
    "26237",   # Phase 40: granisetron
    "208591",   # Phase 40: dexamethasone 1 MG/ML / neomycin 3.5 MG/
    "1731082",   # Phase 40: fosaprepitant 150 MG Injection [Emend In
    "795716",   # Phase 40: {12 (dexamethasone 0.75 MG Oral Tablet [
    "998035",   # Phase 40: ondansetron 4 MG Oral Film [Zuplenz]
    "1728050",   # Phase 40: 1.5 ML palonosetron 0.05 MG/ML Injection
    "283504",   # Phase 40: ondansetron 2 MG/ML Injectable Solution
    "240449",   # Phase 40: Filgrastim Inj 300 MCG/ML
    "727545",   # Phase 40: 0.8 ML filgrastim 0.6 MG/ML Prefilled Sy
    "1734399",   # Phase 40: 1 ML granisetron 1 MG/ML Injection
    "197583",   # Phase 40: dexamethasone 6 MG Oral Tablet
    "310599",   # Phase 40: granisetron 1 MG Oral Tablet
    "792710",   # Phase 40: Epoetin Alfa Inj 10000 Unit/ML
    "2549333",   # Phase 40: 0.6 ML pegfilgrastim 10 MG/ML Injection 
    "2463735",   # Phase 40: epoetin alfa-epbx 20000 UNT/ML Injectabl
    "644278",   # Phase 40: aprepitant 40 MG Oral Capsule [Emend]
    "213475",   # Phase 40: 1 ML epoetin alfa 40000 UNT/ML Injection
    "2056929",   # Phase 40: 5 ML palonosetron 0.05 MG/ML Prefilled S
    "208588",   # Phase 40: dexamethasone 1 MG/ML / neomycin 3.5 MG/
    "104897",   # Phase 40: ondansetron injection
    "731174",   # Phase 40: 0.4 ML darbepoetin alfa 0.5 MG/ML Prefil
    "1605071",   # Phase 40: 0.5 ML filgrastim-sndz 0.6 MG/ML Prefill
    "1649946",   # Phase 40: 1 ML filgrastim 0.3 MG/ML Injection [Neu
    "1998482",   # Phase 40: {21 (dexamethasone 1.5 MG Oral Tablet) }
    "309679",   # Phase 40: dexamethasone 0.001 MG/MG / neomycin 0.0
    "2048020",   # Phase 40: 0.6 ML pegfilgrastim-jmdb 10 MG/ML Prefi
    "197579",   # Phase 40: dexamethasone 1 MG Oral Tablet
    "2102705",   # Phase 40: 0.6 ML pegfilgrastim-cbqv 10 MG/ML Prefi
    "1442683",   # Phase 40: 0.8 ML tbo-filgrastim 0.6 MG/ML Prefille
    "2595961",   # Phase 40: 0.8 ML filgrastim-ayow 0.6 MG/ML Prefill
    "239998",   # Phase 40: 1 ML epoetin alfa 2000 UNT/ML Injection
    "825005",   # Phase 40: 168 HR granisetron 0.129 MG/HR Transderm
    "2260704",   # Phase 40: 0.6 ML pegfilgrastim-bmez 10 MG/ML Prefi
    "208601",   # Phase 40: dexamethasone 0.001 MG/MG / neomycin 0.0
    "197580",   # Phase 40: dexamethasone 1.5 MG Oral Tablet
    "208602",   # Phase 40: dexamethasone 0.001 MG/MG / neomycin 0.0
    "349274",   # Phase 40: 1 ML darbepoetin alfa 0.04 MG/ML Injecti
    "2260709",   # Phase 40: 0.6 ML pegfilgrastim-bmez 10 MG/ML Prefi
    "64695",   # Phase 40: Ondansetron 4 MG Oral Tablet Disintegrat
    "754508",   # Phase 40: {1 (aprepitant 125 MG Oral Capsule) / 2 
    "1649944",   # Phase 40: 1 ML filgrastim 0.3 MG/ML Injection
    "2047600",   # Phase 40: 1 ML epoetin alfa-epbx 2000 UNT/ML Injec
    "26225",   # Phase 40: ondansetron
    "2469340",   # Phase 40: 0.6 ML pegfilgrastim-apgf 10 MG/ML Prefi
    "2047612",   # Phase 40: 1 ML epoetin alfa-epbx 4000 UNT/ML Injec
    "731176",   # Phase 40: 0.42 ML darbepoetin alfa 0.06 MG/ML Pref
    "901649",   # Phase 40: dexamethasone 0.1 MG/ML Oral Solution [B
    "1740467",   # Phase 40: 2 ML ondansetron 2 MG/ML Injection
    "104896",   # Phase 40: ondansetron
    "104894",   # Phase 40: ondansetron 4 MG Disintegrating Oral Tab
    "309683",   # Phase 40: dexamethasone 1 MG/ML / tobramycin 3 MG/
    "759696",   # Phase 40: {12 (dexamethasone 0.75 MG Oral Tablet) 
    "205717",   # Phase 40: dexamethasone 6 MG Oral Tablet [Decadron
    "2057205",   # Phase 40: 0.5 ML filgrastim-aafi 0.6 MG/ML Prefill
    "403811",   # Phase 40: aprepitant 125 MG Oral Capsule
    "205712",   # Phase 40: dexamethasone 4 MG Oral Tablet [Decadron
    "1605066",   # Phase 40: 0.5 ML filgrastim-sndz 0.6 MG/ML Prefill
    "876693",   # Phase 40: ondansetron
    "1721684",   # Phase 40: 1 ML epoetin alfa 10000 UNT/ML Injection
    "2048018",   # Phase 40: pegfilgrastim-jmdb
    "1433771",   # Phase 40: 0.8 ML tbo-filgrastim 0.6 MG/ML Prefille
    "1812079",   # Phase 40: 1 ML dexamethasone phosphate 10 MG/ML In
    "730044",   # Phase 40: 0.5 ML darbepoetin alfa 0.2 MG/ML Prefil
    "2463731",   # Phase 40: epoetin alfa-epbx 10000 UNT/ML Injectabl
    "212447",   # Phase 40: ondansetron
    "205669",   # Phase 40: dexamethasone 1 MG/ML Ophthalmic Suspens
    "241999",   # Phase 40: epoetin alfa 20000 UNT/ML Injectable Sol
    "2047606",   # Phase 40: 1 ML epoetin alfa-epbx 3000 UNT/ML Injec
    "1605064",   # Phase 40: filgrastim-sndz
    "759697",   # Phase 40: {35 (dexamethasone 1.5 MG Oral Tablet) }
    "1314133",   # Phase 40: 2 ML ondansetron 2 MG/ML Prefilled Syrin
    "731179",   # Phase 40: 0.6 ML darbepoetin alfa 0.5 MG/ML Prefil
    "358255",   # Phase 40: aprepitant
    "1605074",   # Phase 40: 0.8 ML filgrastim-sndz 0.6 MG/ML Prefill
    "403908",   # Phase 40: ciprofloxacin 3 MG/ML / dexamethasone 1 
    "242706",   # Phase 40: 1 ML epoetin alfa 40000 UNT/ML Injection
    "2261802",   # Phase 40: dexamethasone 20 MG Oral Tablet
    "644088",   # Phase 40: aprepitant 40 MG Oral Capsule
    "313947",   # Phase 40: Neomycin-Polymyxin-Dexamethasone Ophth O
    "2057200",   # Phase 40: 0.5 ML filgrastim-aafi 0.6 MG/ML Prefill
    "404466",   # Phase 40: aprepitant 125 MG Oral Capsule [Emend]
    "755976",   # Phase 40: dexamethasone 0.1 MG/ML Oral Solution [D
    "2047623",   # Phase 40: 1 ML epoetin alfa-epbx 40000 UNT/ML Inje
    "205913",   # Phase 40: epoetin alfa 10000 UNT/ML Injectable Sol
    "6316",   # Phase 40: dexAMETHasone Sodium Phosphate 4 MG/ML I
    "998033",   # Phase 40: ondansetron 4 MG Oral Film
    "312087",   # Phase 40: ondansetron 8 MG Disintegrating Oral Tab
    "727535",   # Phase 40: 0.5 ML filgrastim 0.6 MG/ML Prefilled Sy
    "404630",   # Phase 40: ciprofloxacin 3 MG/ML / dexamethasone 1 
    "1490065",   # Phase 40: raloxifene hydrochloride 60 MG Oral Tabl
    "1649964",   # Phase 40: 1.6 ML filgrastim 0.3 MG/ML Injection [N
    "309696",   # Phase 40: dexamethasone phosphate 10 MG/ML Injecta
    "3264",   # Phase 40: dexamethasone
    "198052",   # Phase 40: ondansetron 4 MG Oral Tablet
    "309680",   # Phase 40: dexamethasone 1 MG/ML / neomycin 3.5 MG/
    "1728052",   # Phase 40: palonosetron injection
    "731167",   # Phase 40: 0.3 ML darbepoetin alfa 0.2 MG/ML Prefil
    "825003",   # Phase 40: 168 HR granisetron 0.129 MG/HR Transderm
    "349275",   # Phase 40: 1 ML darbepoetin alfa 0.06 MG/ML Injecti
    "2047591",   # Phase 40: 1 ML epoetin alfa-epbx 10000 UNT/ML Inje
    "1116927",   # Phase 40: dexamethasone phosphate 4 MG/ML Injectab
    "309686",   # Phase 40: dexamethasone 0.1 MG/ML Oral Solution
    "309692",   # Phase 40: dexamethasone 1 MG/ML Ophthalmic Suspens
    "240000",   # Phase 40: epoetin alfa 10000 UNT/ML Injectable Sol
    "847225",   # Phase 40: {21 (dexamethasone 1.5 MG Oral Tablet) }
    "2469335",   # Phase 40: 0.6 ML pegfilgrastim-apgf 10 MG/ML Prefi
    "208813",   # Phase 40: dexamethasone 1 MG/ML / tobramycin 3 MG/
    "1995150",   # Phase 40: 18 ML aprepitant 7.2 MG/ML Injection
    "349273",   # Phase 40: 1 ML darbepoetin alfa 0.025 MG/ML Inject
    "1998481",   # Phase 40: {49 (dexamethasone 1.5 MG Oral Tablet) }
    "226343",   # Phase 40: dexamethasone phosphate 1 MG/ML Ophthalm
    "309698",   # Phase 40: Dexamethasone Sodium Phosphate Inj 4 MG/
    "197581",   # Phase 40: dexamethasone 2 MG Oral Tablet
    "104895",   # Phase 40: Zofran 4 mg oral tablet
    "309684",   # Phase 40: dexamethasone 1 MG/ML Oral Solution
    "2102703",   # Phase 40: 0.6 ML pegfilgrastim-cbqv 10 MG/ML Prefi
    "727539",   # Phase 40: 0.6 ML pegfilgrastim 10 MG/ML Prefilled 
    "2101459",   # Phase 40: 1 ML tbo-filgrastim 0.3 MG/ML Injection 
    "2469333",   # Phase 40: pegfilgrastim-apgf
    "2057215",   # Phase 40: 0.8 ML filgrastim-aafi 0.6 MG/ML Prefill
    "754509",   # Phase 40: {1 (aprepitant 125 MG Oral Capsule [Emen
    "1433768",   # Phase 40: 0.5 ML tbo-filgrastim 0.6 MG/ML Prefille
    "849115",   # Phase 40: dexamethasone 0.5 MG/ML / tobramycin 3 M
    "2101456"    # Phase 40: 1 ML tbo-filgrastim 0.3 MG/ML Injection
  ),


  # Immunotherapy RXNORM codes (Phase 40: drug investigation)
  immunotherapy_rxnorm = c(
    "1094836",   # Phase 40: ipilimumab 5 MG/ML Injectable Solution
    "891815",   # Phase 40: ascorbic acid 113 MG / beta carotene 716
    "891790",   # Phase 40: ascorbic acid 226 MG / beta carotene 143
    "1919507",   # Phase 40: 2.4 ML durvalumab 50 MG/ML Injection
    "1090823",   # Phase 40: ascorbic acid / beta carotene / copper s
    "1313925",   # Phase 40: alpha-tocopherol acetate 30 UNT / ascorb
    "1248142",   # Phase 40: ascorbic acid 120 MG / beta carotene 270
    "891716",   # Phase 40: ascorbic acid 200 MG / beta carotene 100
    "2479140",   # Phase 40: 4.6 ML lisocabtagene maraleucel 70000000
    "1792780",   # Phase 40: 20 ML atezolizumab 60 MG/ML Injection
    "1090824",   # Phase 40: ascorbic acid 60 MG / beta carotene 5000
    "891793"    # Phase 40: ascorbic acid 226 MG / beta carotene 143
  ),


  # SCT-related RXNORM codes (Phase 40: drug investigation)
  sct_rxnorm = c(
    "1740865",   # Phase 40: 2 ML fludarabine phosphate 25 MG/ML Inje
    "253113",   # Phase 40: 10 ML busulfan 6 MG/ML Injection
    "1660004",   # Phase 40: thiotepa 100 MG Injection
    "284425",   # Phase 40: 10 ML busulfan 6 MG/ML Injection [Busulf
    "197919",   # Phase 40: melphalan 2 MG Oral Tablet
    "876399",   # Phase 40: melphalan 50 MG Injection [Alkeran]
    "1740864",   # Phase 40: fludarabine phosphate 50 MG Injection
    "311487"    # Phase 40: melphalan 50 MG Injection
  ),

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
# 5.5b TREATMENT TYPE DEFINITIONS (Phase quick: centralized from duplicate script definitions)
# ------------------------------------------------------------------------------

# Standard treatment types for analysis (used across treatment inventory, duration, episode scripts)
TREATMENT_TYPES <- c("Chemotherapy", "Radiation", "SCT", "Immunotherapy")

# Treatment type colors for xlsx styling (8-char hex with FF alpha prefix)
# Canonical 6-category palette covering all treatment analysis needs
TREATMENT_TYPE_COLORS <- list(
  Chemotherapy      = list(fill = "FFDCEEFB", font = "FF0B5394"),   # light blue / dark blue
  Radiation         = list(fill = "FFDDF4E1", font = "FF274E13"),   # light green / dark green
  SCT               = list(fill = "FFFFF4D6", font = "FF7F6000"),   # light yellow / dark olive
  Immunotherapy     = list(fill = "FFE8DCF4", font = "FF4C1D7A"),   # light purple / dark purple
  `Supportive Care` = list(fill = "FFD5F5F0", font = "FF0E6655"),   # light teal / dark teal
  Unrelated         = list(fill = "FFF3F4F6", font = "FF6B7280")    # light gray / medium gray
)

# Treatment episode window threshold (max days from episode start to define cycle boundary)
# Used by duration/episode analysis (Phase 43, 44)
GAP_THRESHOLD <- 90

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
source("R/utils_snapshot.R")  # Phase 16: snapshot helper
source("R/utils_duckdb.R")    # Phase 30: backend abstraction helpers
source("R/utils_treatment.R")  # Phase quick: shared treatment helpers
source("R/utils_payer.R")      # Quick 260518-i3w: shared payer helpers

# ==============================================================================
# End of configuration
# ==============================================================================
