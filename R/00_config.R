# ==============================================================================
# 00_config.R -- Project-wide configuration: data paths, ICD code lists, payer mapping rules, treatment codes, analysis parameters
# ==============================================================================
#
# Purpose:
#   Defines all project-wide configuration objects for the PCORnet Payer Variable
#   Investigation pipeline. Auto-sources all 8 utility modules from R/utils/ at
#   the end to provide shared functions (date parsing, attrition logging, DuckDB
#   access, ICD normalization, payer helpers, PPTX styling, snapshots, treatment
#   helpers) to every downstream script that sources this file.
#
# Inputs:
#   - None (configuration only)
#
# Outputs:
#   - None (defines configuration objects in memory)
#     - CONFIG: List with data_dir, cache paths, DuckDB paths, performance tuning
#     - PCORNET_TABLES: Vector of 14 table names to load
#     - PCORNET_PATHS: Named vector of full CSV file paths
#     - ICD_CODES: List of HL diagnosis codes (77 ICD-10 + 73 ICD-9 = 150 total)
#     - PAYER_MAPPING: AMC 8-category lookup table (direct code-to-category mapping)
#     - TREATMENT_CODES: Lists of CPT/HCPCS/NDC codes for 4 treatment types
#     - ANALYSIS_PARAMS: Thresholds for cohort filtering and HL diagnosis matching
#
# Dependencies:
#   - None (root configuration)
#   - Auto-sources R/utils/*.R at end: 8 utility modules loaded via list.files()
#
# Requirements: N/A (foundational configuration script)
#
# ==============================================================================

# ==============================================================================
# SECTION 0: ENVIRONMENT DETECTION ----
# ==============================================================================
# Auto-detect local testing (Windows) vs production HiPerGator (Linux).
# Override: Set R_TESTING_ENV=local in project-root .Renviron to force local mode.
# WHY env var first: Enables Linux VM testing without OS misdetection.
# WHY Windows default: Only Windows machines in the project are local dev boxes.
# Production safety: IS_LOCAL defaults to FALSE on Linux when env var is unset.

IS_LOCAL <- if (Sys.getenv("R_TESTING_ENV") != "") {
  # Explicit override from .Renviron or shell environment
  Sys.getenv("R_TESTING_ENV") == "local"
} else {
  # Auto-detect: Windows = local testing, Linux = HiPerGator production
  Sys.info()["sysname"] == "Windows"
}

# Log environment mode at startup (visible in RStudio console and SLURM logs)
if (IS_LOCAL) {
  message("================================================================================")
  message("LOCAL TESTING MODE")
  message("  OS: ", Sys.info()["sysname"])
  message("  Override: ", if (Sys.getenv("R_TESTING_ENV") != "") "R_TESTING_ENV=local" else "(auto-detected)")
  message("  Data: tests/fixtures/")
  message("  DuckDB: tempdir()/insurance_investigation_duckdb/pcornet_test.duckdb")
  message("  Threads: 1")
  message("================================================================================")
} else {
  message("================================================================================")
  message("PRODUCTION MODE (HiPerGator)")
  message("  OS: ", Sys.info()["sysname"])
  message("  Data: /orange/erin.mobley-hl.bcu/Mailhot_V1_20250915")
  message("  DuckDB: /blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb")
  message("  Threads: ", Sys.getenv("SLURM_CPUS_PER_TASK", unset = "16"), " (SLURM allocation)")
  message("================================================================================")
}

# Thread count: 1 core locally (avoid contention), SLURM allocation on HPC
THREAD_COUNT <- if (IS_LOCAL) {
  1L
} else {
  # Read SLURM allocation, fallback to 16 (Open OnDemand RStudio default)
  as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", unset = "16"))
}

# ==============================================================================
# SECTION 1: DATA PATHS ----
# ==============================================================================

# Extract date for current PCORnet CDM data pull (Mailhot_V1_20250915)
# Update this when a new extract arrives. Used for ingest log filenames.
EXTRACT_DATE <- "2025-09-15"

CONFIG <- list(
  # Data directory: tests/fixtures/ locally, /orange/ production path on HPC
  data_dir = if (IS_LOCAL) {
    file.path("tests", "fixtures")
  } else {
    "/orange/erin.mobley-hl.bcu/Mailhot_V1_20250915"
  },

  # Project directory
  project_dir = if (IS_LOCAL) {
    getwd()  # Local testing uses current working directory
  } else {
    "/blue/erin.mobley-hl.bcu/R"
  },

  # Output directory (same for both — local relative path)
  output_dir = "output",

  # Performance tuning (vroom multi-threaded CSV loading)
  performance = list(
    num_threads = THREAD_COUNT
  ),

  # ---------------------------------------------------------------------------
  # RDS Cache Settings (Phase 15)
  # ---------------------------------------------------------------------------
  # Persistent RDS cache for loaded PCORnet tables. After first CSV parse,
  # tables are serialized to .rds files. Subsequent runs load from cache
  # if the .rds file is newer than the source CSV (file.mtime() comparison).
  #
  # Local mode: Uses tempdir() for ephemeral cache (cleaned on R session exit).
  # Production: Uses /blue/ persistent storage (gitignored, 100MB-2GB per file).
  cache = list(
    cache_dir = if (IS_LOCAL) {
      file.path(tempdir(), "insurance_investigation_cache")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/rds"
    },

    force_reload = FALSE, # Set to TRUE to bypass cache and re-parse all CSVs

    # Phase 15: Raw PCORnet table cache
    raw_dir = if (IS_LOCAL) {
      file.path(tempdir(), "insurance_investigation_cache", "raw")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/rds/raw"
    },

    # Phase 16: Cohort filter step snapshots
    cohort_dir = if (IS_LOCAL) {
      file.path(tempdir(), "insurance_investigation_cache", "cohort")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/rds/cohort"
    },

    # Phase 16: Figure/table backing data snapshots
    outputs_dir = if (IS_LOCAL) {
      file.path(tempdir(), "insurance_investigation_cache", "outputs")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/rds/outputs"
    },

    # Phase 29: DuckDB file storage
    # Local: separate test database in tempdir() to avoid file locking conflicts
    # Production: /blue/ persistent storage (gitignored)
    duckdb_dir = if (IS_LOCAL) {
      file.path(tempdir(), "insurance_investigation_duckdb")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/duckdb"
    },

    duckdb_path = if (IS_LOCAL) {
      file.path(tempdir(), "insurance_investigation_duckdb", "pcornet_test.duckdb")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb"
    }
  )
)

# ==============================================================================
# SECTION 1b: AUTOMATIC DIRECTORY CREATION ----
# ==============================================================================
# Create output and cache directories at startup if they don't exist.
# WHY automatic: Avoids "cannot open file" errors on first run, especially
# in local mode where tempdir() paths don't pre-exist as subdirectories.
# WHY showWarnings = FALSE: Suppresses "directory already exists" noise.

required_dirs <- c(
  CONFIG$output_dir,
  file.path(CONFIG$output_dir, "figures"),
  file.path(CONFIG$output_dir, "tables"),
  file.path(CONFIG$output_dir, "cohort"),
  file.path(CONFIG$output_dir, "diagnostics"),
  file.path(CONFIG$output_dir, "logs"),
  CONFIG$cache$cache_dir,
  CONFIG$cache$raw_dir,
  CONFIG$cache$cohort_dir,
  CONFIG$cache$outputs_dir,
  CONFIG$cache$duckdb_dir
)

for (dir_path in required_dirs) {
  if (!dir.exists(dir_path)) {
    dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
  }
}

# ==============================================================================
# SECTION 2: BACKEND SELECTION ----
# ==============================================================================
# Phase 30 introduced DuckDB mode; default flipped to DuckDB in Phase 32
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

# ==============================================================================
# SECTION 3: PCORNET CDM TABLE PATHS ----
# ==============================================================================

# Primary load set: 14 tables
# - 7 standard CDM tables: ENROLLMENT, DIAGNOSIS, CONDITION, PROCEDURES,
#   PRESCRIBING, ENCOUNTER, DEMOGRAPHIC
# - 3 TUMOR_REGISTRY tables: contain HL-specific diagnosis dates (DATE_OF_DIAGNOSIS)
#   and treatment dates (DT_CHEMO, DT_RAD, etc.)
# - 2 medication tables (Phase 9): DISPENSING, MED_ADMIN for expanded treatment detection
#
# File naming pattern: TABLE_Mailhot_V1.csv
# Example: ENROLLMENT_Mailhot_V1.csv

PCORNET_TABLES <- c(
  "ENROLLMENT",
  "DIAGNOSIS",
  "CONDITION", # PCORnet CDM: diagnosed/self-reported health conditions
  "PROCEDURES",
  "PRESCRIBING",
  "ENCOUNTER",
  "DEMOGRAPHIC",
  "TUMOR_REGISTRY1",
  "TUMOR_REGISTRY2",
  "TUMOR_REGISTRY3",
  "DISPENSING", # Phase 9: expanded treatment detection
  "MED_ADMIN", # Phase 9: expanded treatment detection
  "LAB_RESULT_CM", # Phase 10: surveillance lab values (LOINC-based matching)
  "PROVIDER", # Phase 10: oncology provider specialty matching
  "DEATH" # Phase 57: death dates for Gantt chart endpoint
)

# Build full paths as named character vector
# Usage: PCORNET_PATHS$ENROLLMENT, PCORNET_PATHS$DIAGNOSIS, etc.
PCORNET_PATHS <- setNames(
  file.path(CONFIG$data_dir, paste0(PCORNET_TABLES, "_Mailhot_V1.csv")),
  PCORNET_TABLES
)

# Filename overrides: actual CSV names that don't match the {TABLE}_Mailhot_V1.csv pattern
PCORNET_PATHS[["LAB_RESULT_CM"]] <- file.path(CONFIG$data_dir, "LAB_RESULT_Mailhot_V1.csv")

# NOTE: Patient ID column is "ID" (not "PATID") across all tables
# NOTE: SOURCE column = partner/site identifier (AMS, UMI, FLM, VRT)

# ==============================================================================
# SECTION 4: ICD CODE LISTS ----
# ==============================================================================
# 150 Hodgkin Lymphoma diagnosis codes: 77 ICD-10-CM + 73 ICD-9-CM
#
# WHY these specific codes:
# - C81.xx (ICD-10): Official Hodgkin lymphoma code range per ICD-10-CM 2025
# - 201.xx (ICD-9): Legacy HL codes from pre-2015 diagnoses in the cohort
# - C81.xA remission codes added in Phase 18 after 15 patients were missed
# - Bare "201" parent code added in Phase 18 for 1 LNK patient with unspecified coding
# - 4-digit 201.x parent codes added for 3 patients from FLM/TMA sites using short codes

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

# ==============================================================================
# SECTION 4b: ICD-9 NLPHL CODE LIST ----
# ==============================================================================
# ICD-9 codes specific to Nodular Lymphocyte Predominant Hodgkin Lymphoma.
# Used by classify_codes() in R/utils/utils_cancer.R for exact-match ICD-9
# classification. WHY separate from ICD_CODES: These are a SUBSET of
# ICD_CODES$hl_icd9 used for NLPHL vs classical HL discrimination, not for
# cohort inclusion. ICD-10 NLPHL detection uses prefix matching (C810);
# ICD-9 requires exact matching because dotted format (201.40) doesn't
# support clean prefix extraction.
#
# Codes: 201.4 (parent) + 201.40-201.48 (site-specific) = 10 codes total
# Reference: ICD-9-CM Chapter 2, 201.4x Lymphocytic-histiocytic predominance

ICD9_NLPHL_CODES <- c(
  "201.4",                                              # Parent code (no site digit)
  "201.40", "201.41", "201.42", "201.43", "201.44",     # Site-specific codes
  "201.45", "201.46", "201.47", "201.48"                 # Site-specific codes
)

# ==============================================================================
# SECTION 5: PAYER MAPPING RULES ----
# ==============================================================================
# AMC 8-category system: Medicaid, Medicare, Private, Other govt, Other,
# Self-pay, Uninsured, Missing
#
# WHY this hierarchy (Medicaid > Medicare > Private > Other govt):
# - Dual-eligible patients (Medicare+Medicaid) mapped to Medicaid per Amy Crisp's
#   clinical prioritization: Medicaid coverage determines treatment access/barriers
# - "Other govt" tier (rank 4) separates VA/TRICARE from generic "Other" for analysis
# - Direct code-to-category lookup table eliminates runtime xlsx dependency (Phase 36)
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
  "219" = "Medicaid", # Medicaid Managed Care Other
  "29" = "Medicaid", # Medicaid Other
  "14" = "Medicaid", # Dual Eligibility Medicare/Medicaid Organization
  "141" = "Medicaid", # Dual Eligibility (subcode)
  "142" = "Medicaid", # Dual Eligibility (subcode)
  "211" = "Medicaid", # Medicaid HMO
  "213" = "Medicaid", # Medicaid PCCM
  "21" = "Medicaid", # Medicaid (Managed Care)
  "2" = "Medicaid", # Medicaid
  "23" = "Medicaid", # Medicaid/SCHIP
  "25" = "Medicaid", # Medicaid - Out of State

  # Medicare codes
  "1" = "Medicare", # Medicare
  "19" = "Medicare", # Medicare Other
  "11" = "Medicare", # Medicare (Managed Care)
  "111" = "Medicare", # Medicare HMO

  # Private codes
  "6" = "Private", # Blue Cross/Blue Shield
  "5" = "Private", # Private Health Insurance
  "511" = "Private", # Commercial Managed Care - HMO
  "51" = "Private", # Managed Care (Private)
  "52" = "Private", # Private Health Insurance - Indemnity
  "71" = "Private", # HMO
  "513" = "Private", # Commercial Managed Care - POS
  "7" = "Private", # Managed Care, Unspecified
  "521" = "Private", # Commercial Indemnity
  "623" = "Private", # BC Medicare Supplemental Plan
  "512" = "Private", # Commercial Managed Care - PPO
  "529" = "Private", # Private health insurance - other commercial Indemnity
  "311" = "Private", # TRICARE (CHAMPUS) — reclassified from Other govt per AMC

  # Missing codes
  "NI" = "Missing", # No information — reclassified from Uninsured per AMC
  "9999" = "Missing", # Unavailable / No Payer Specified — reclassified per AMC
  "UN" = "Missing", # Unknown — reclassified from Uninsured per AMC
  "99" = "Missing", # Unavailable (short code)
  "UNKNOWN" = "Missing", # Unknown (text form)

  # Other codes
  "OT" = "Other", # Other
  "95" = "Other", # Worker's Compensation
  "9" = "Other", # Miscellaneous/other
  "92" = "Other", # Other (Non-government)
  "96" = "Other", # Auto Insurance

  # Self-pay codes
  "81" = "Self-pay", # Self-pay — split from Uninsured per AMC

  # Uninsured codes
  "821" = "Uninsured", # Charity
  "8" = "Uninsured", # No payment from Organization/Agency/Program

  # Other govt codes
  "382" = "Other govt", # Federal, State, Local not specified - FFS
  "349" = "Other govt", # Other
  "3" = "Other govt", # Other Government (excl. Corrections)
  "32126" = "Other govt", # Other Federal Agency
  "32121" = "Other govt", # Fee Basis
  "32" = "Other govt", # Department of Veterans Affairs
  "44" = "Other govt" # Corrections Unknown Level
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

# ==============================================================================
# SECTION 5b: CANCER SITE CLASSIFICATION MAP ----
# ==============================================================================
# 324-entry ICD-10/ICD-O-3 prefix-to-category mapping for cancer site
# classification. Based on SEER/NCI site groupings. Each 3-character prefix
# maps to a cancer category.
# Used by classify_codes() in R/utils/utils_cancer.R across 10+ scripts.
#
# WHY centralized here: Previously duplicated in 11 scripts (~2,860 lines of
# copies). Single definition eliminates drift risk and simplifies future
# category additions.
#
# Sources: SEER Site Recode ICD-O-3/WHO 2008, ICD-10-CM Chapter 2 (C00-D49)
# ==============================================================================

CANCER_SITE_MAP <- c(
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

  # 42. Hodgkin Lymphoma -- NLPHL breakout (C81.0 vs C81.1-C81.9)
  # NOTE: C810 (4-char) MUST be checked BEFORE C81 (3-char) in classify_codes()
  # per D-01/D-02. The function in R/utils/utils_cancer.R handles priority.
  "C810" = "NLPHL",                             # Nodular lymphocyte predominant HL (C81.0x)
  "C81" = "Hodgkin Lymphoma (non-NLPHL)",        # All other C81.xx (classical HL subtypes)

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

# ==============================================================================
# SECTION 5b2: ICD-9 CANCER SITE CLASSIFICATION MAP ----
# ==============================================================================
# ICD-9 equivalent of CANCER_SITE_MAP for pre-Oct-2015 diagnosis codes.
# 78-entry mapping from ICD-9-CM malignant neoplasm codes (140-209) to the same
# cancer site categories used in CANCER_SITE_MAP for ICD-10 codes. Enables
# cross-system cancer summary merging and consistent category assignment.
#
# Scope: Malignant neoplasms ONLY (140-209). Benign/in-situ/uncertain behavior
# codes (210-239) are deliberately EXCLUDED per D-02 decision -- these ICD-9
# codes mirror the D-code exclusion logic applied to ICD-10 data.
#
# Pattern: 3-digit prefix keys (e.g., "140", "162") for broad categories, plus
# 4-digit prefix keys (e.g., "2014") for Hodgkin lymphoma subcategory
# discrimination (NLPHL vs classical HL). Mirrors the C810/C81 4-char-before-3-char
# pattern in CANCER_SITE_MAP.
#
# Categories: Category strings match CANCER_SITE_MAP exactly to enable merging
# ICD-9 and ICD-10 summaries at the category level. Example: "Breast" (not
# "breast"), "Hodgkin Lymphoma (non-NLPHL)" (not "Classical HL").
#
# Source: ICD-9-CM Chapter 2 (Neoplasms) official structure from CMS.
#
# Entry count: 70 3-char entries (140-209) + 8 4-char entries (201.x subcategories)
# = 78 total entries
#
# WHY separate from CANCER_SITE_MAP: ICD-9 and ICD-10 use different code
# structures and granularities. Separate maps keep classification logic clean.
# classify_codes() in R/utils/utils_cancer.R checks both maps with proper
# priority cascade.
# ==============================================================================

ICD9_CANCER_SITE_MAP <- c(
  # --- Lip, Oral Cavity and Pharynx (140-149) ---
  "140" = "Lip, Oral Cavity and Pharynx",
  "141" = "Lip, Oral Cavity and Pharynx",
  "142" = "Lip, Oral Cavity and Pharynx",
  "143" = "Lip, Oral Cavity and Pharynx",
  "144" = "Lip, Oral Cavity and Pharynx",
  "145" = "Lip, Oral Cavity and Pharynx",
  "146" = "Lip, Oral Cavity and Pharynx",
  "147" = "Lip, Oral Cavity and Pharynx",
  "148" = "Lip, Oral Cavity and Pharynx",
  "149" = "Lip, Oral Cavity and Pharynx",

  # --- Digestive Organs (150-159) ---
  "150" = "Esophagus",
  "151" = "Stomach",
  "152" = "Small Intestine",
  "153" = "Colon",           # Colon
  "154" = "Rectum",          # Rectum/rectosigmoid/anus
  "155" = "Liver",           # Liver and intrahepatic bile ducts
  "156" = "Other Digestive", # Gallbladder and extrahepatic bile ducts
  "157" = "Pancreas",
  "158" = "Other Digestive", # Retroperitoneum and peritoneum
  "159" = "Other Digestive", # Other digestive, ill-defined

  # --- Respiratory and Intrathoracic (160-165) ---
  "160" = "Nasal Cavity, Middle Ear, Sinuses",
  "161" = "Larynx",
  "162" = "Lung and Bronchus",
  "163" = "Other Respiratory/Intrathoracic",  # Pleura
  "164" = "Other Respiratory/Intrathoracic",  # Thymus, heart, mediastinum
  "165" = "Other Respiratory/Intrathoracic",  # Other respiratory/intrathoracic
  # NOTE: ICD-9-CM codes 166-169 were never assigned (reserved gaps)

  # --- Bone, Connective Tissue, Skin, Breast (170-176) ---
  "170" = "Bone",
  "171" = "Soft Tissue",                      # Connective and other soft tissue
  "172" = "Melanoma of Skin",
  "173" = "Other Skin",                       # Other malignant neoplasm of skin
  "174" = "Breast",                           # Female breast
  "175" = "Breast",                           # Male breast
  "176" = "Kaposi Sarcoma",

  # --- Genitourinary Organs (179-189) ---
  "179" = "Corpus Uteri",                     # Uterus, unspecified
  "180" = "Cervix Uteri",
  "181" = "Other Female Genital",             # Placenta
  "182" = "Corpus Uteri",                     # Body of uterus
  "183" = "Ovary",                            # Ovary and other uterine adnexa
  "184" = "Other Female Genital",             # Other female genital
  "185" = "Prostate",
  "186" = "Testis",
  "187" = "Other Male Genital",               # Penis and other male genital
  "188" = "Bladder",
  "189" = "Kidney and Renal Pelvis",          # Kidney and other urinary

  # --- Other and Unspecified Sites (190-199) ---
  "190" = "Eye and Orbit",
  "191" = "Brain and CNS",
  "192" = "Brain and CNS",                    # Other nervous system
  "193" = "Thyroid",
  "194" = "Other Endocrine",                  # Other endocrine glands
  "195" = "Ill-Defined Sites",                # Other ill-defined sites
  "196" = "Lymph Nodes (Secondary)",          # Secondary/unspecified lymph nodes
  "197" = "Secondary - Respiratory/Digestive", # Secondary respiratory/digestive
  "198" = "Secondary - Other Sites",          # Secondary other sites
  "199" = "Unknown Primary Site",             # Unknown primary / disseminated

  # --- Lymphatic and Hematopoietic (200-209) ---
  "200" = "Non-Hodgkin Lymphoma",             # Lymphosarcoma and reticulosarcoma
  "202" = "Non-Hodgkin Lymphoma",             # Other lymphoid neoplasms

  # Hodgkin Lymphoma (201.x) with 4-char subcategory discrimination:
  # NOTE: 4-char keys (e.g., "2014") MUST be checked BEFORE 3-char key ("201")
  # in classify_codes() to enable NLPHL breakout. The function in
  # R/utils/utils_cancer.R handles priority via 4-tier cascade.
  "2014" = "NLPHL",                           # 201.4x lymphocytic-histiocytic predominance
  "2010" = "Hodgkin Lymphoma (non-NLPHL)",    # 201.0x paragranuloma (obsolete)
  "2011" = "Hodgkin Lymphoma (non-NLPHL)",    # 201.1x granuloma (obsolete)
  "2012" = "Hodgkin Lymphoma (non-NLPHL)",    # 201.2x sarcoma (obsolete)
  "2015" = "Hodgkin Lymphoma (non-NLPHL)",    # 201.5x nodular sclerosis
  "2016" = "Hodgkin Lymphoma (non-NLPHL)",    # 201.6x mixed cellularity
  "2017" = "Hodgkin Lymphoma (non-NLPHL)",    # 201.7x lymphocytic depletion
  "2019" = "Hodgkin Lymphoma (non-NLPHL)",    # 201.9x unspecified
  "201" = "Hodgkin Lymphoma (non-NLPHL)",     # 3-char fallback for any missed subcategory

  "203" = "Multiple Myeloma",                 # Multiple myeloma and immunoproliferative
  "204" = "Lymphoid Leukemia",
  "205" = "Myeloid and Monocytic Leukemia",   # Myeloid leukemia
  "206" = "Myeloid and Monocytic Leukemia",   # Monocytic leukemia
  "207" = "Other Leukemia",                   # Other specified leukemia
  "208" = "Other Leukemia",                   # Leukemia, unspecified cell type
  "209" = "Neuroendocrine Tumors"             # Neuroendocrine tumors
)

# ==============================================================================
# SECTION 5c: TIER HIERARCHY CONFIGURATION ----
# ==============================================================================
# Payer tier resolution hierarchy (per Amy Crisp framework).
# Lower rank = higher priority. Used for same-day, encounter-level, and
# date-level payer resolution in R/60-R/62.
#
# WHY this hierarchy order:
#   Medicaid > Medicare > Private > Other govt > Other > Self-pay >
#   Uninsured > Missing
#   - Medicaid has the most restrictive eligibility (strongest signal of
#     coverage status)
#   - Medicare indicates age 65+ or disability eligibility
#   - When a patient has multiple encounters on the same date with different
#     payers, we select the tier with the lowest rank (highest priority) as
#     the "true" payer
#
# WHY centralized here: Previously duplicated in R/60, R/61, R/62 identically.
# ==============================================================================

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

# ==============================================================================
# SECTION 5d: DEATH CAUSE CLASSIFICATION MAP ----
# ==============================================================================
# Maps 3-character ICD-10 prefixes to standardized cause-of-death categories.
# Based on WHO Mortality Database and CDC NCHS 113 Selected Causes groupings.
# Used by Phase 78 death data profiling and Gantt output generation.
#
# WHY 3-char prefixes: Matches CANCER_SITE_MAP pattern (D-06); balances
# specificity (too granular = 50+ cancer subcategories) with utility
# (too broad = "all cancer"). ~100 entries covering 30-40 categories.
#
# WHY separate constant: Follows AMC_PAYER_LOOKUP / CANCER_SITE_MAP pattern
# of top-level named vectors in R/00_config.R (D-07).
#
# WHY "Unknown or Unspecified": Makes missingness visible in output tables
# rather than silent NA (D-05). Applied when code is empty, invalid, or
# has no mapping in this vector.
#
# Sources:
# - WHO Mortality Database: https://platform.who.int/mortality
# - CDC NCHS 113 Selected Causes: https://ibis.doh.nm.gov/resource/ICDCodes.html

DEATH_CAUSE_MAP <- c(
  # === INFECTIOUS AND PARASITIC DISEASES (A00-B99) ===
  "A00" = "Cholera",
  "A01" = "Typhoid and Paratyphoid Fevers",
  "A15" = "Tuberculosis (Respiratory)",
  "A16" = "Tuberculosis (Respiratory)",
  "A17" = "Tuberculosis (Nervous System)",
  "A18" = "Tuberculosis (Other Organs)",
  "A19" = "Miliary Tuberculosis",
  "A40" = "Septicemia",
  "A41" = "Septicemia",
  "B15" = "Viral Hepatitis",
  "B16" = "Viral Hepatitis",
  "B17" = "Viral Hepatitis",
  "B18" = "Viral Hepatitis",
  "B19" = "Viral Hepatitis",
  "B20" = "HIV Disease",
  "B21" = "HIV Disease",
  "B22" = "HIV Disease",
  "B23" = "HIV Disease",
  "B24" = "HIV Disease",

  # === NEOPLASMS (C00-D48) ===
  # Digestive organs
  "C15" = "Esophageal Cancer",
  "C16" = "Stomach Cancer",
  "C17" = "Small Intestine Cancer",
  "C18" = "Colon Cancer",
  "C19" = "Colon Cancer",
  "C20" = "Rectal Cancer",
  "C21" = "Anal Cancer",
  "C22" = "Liver Cancer",
  "C23" = "Gallbladder Cancer",
  "C24" = "Biliary Tract Cancer",
  "C25" = "Pancreatic Cancer",

  # Respiratory
  "C33" = "Tracheal Cancer",
  "C34" = "Lung Cancer",

  # Bone and soft tissue
  "C40" = "Bone Cancer",
  "C41" = "Bone Cancer",
  "C45" = "Mesothelioma",
  "C46" = "Kaposi Sarcoma",
  "C47" = "Peripheral Nerve and Autonomic Nervous System Cancer",
  "C48" = "Retroperitoneal Cancer",
  "C49" = "Soft Tissue Cancer",

  # Skin
  "C43" = "Melanoma",
  "C44" = "Non-Melanoma Skin Cancer",

  # Breast and reproductive
  "C50" = "Breast Cancer",
  "C53" = "Cervical Cancer",
  "C54" = "Uterine Cancer",
  "C55" = "Uterine Cancer",
  "C56" = "Ovarian Cancer",
  "C57" = "Other Female Genital Cancer",
  "C61" = "Prostate Cancer",
  "C62" = "Testicular Cancer",

  # Urinary
  "C64" = "Kidney Cancer",
  "C65" = "Renal Pelvis Cancer",
  "C66" = "Ureter Cancer",
  "C67" = "Bladder Cancer",

  # CNS
  "C70" = "Meningeal Cancer",
  "C71" = "Brain Cancer",
  "C72" = "Spinal Cord Cancer",

  # Endocrine
  "C73" = "Thyroid Cancer",
  "C74" = "Adrenal Cancer",

  # Hematologic (matching CANCER_SITE_MAP categories)
  "C81" = "Hodgkin Lymphoma",
  "C82" = "Non-Hodgkin Lymphoma",
  "C83" = "Non-Hodgkin Lymphoma",
  "C84" = "Non-Hodgkin Lymphoma",
  "C85" = "Non-Hodgkin Lymphoma",
  "C86" = "Non-Hodgkin Lymphoma",
  "C88" = "Non-Hodgkin Lymphoma",
  "C90" = "Multiple Myeloma",
  "C91" = "Leukemia",
  "C92" = "Leukemia",
  "C93" = "Leukemia",
  "C94" = "Leukemia",
  "C95" = "Leukemia",
  "C96" = "Other Hematopoietic Cancer",

  # Other/unspecified neoplasms
  "D00" = "In Situ Neoplasms",
  "D01" = "In Situ Neoplasms",
  "D02" = "In Situ Neoplasms",
  "D03" = "In Situ Neoplasms",
  "D04" = "In Situ Neoplasms",
  "D05" = "In Situ Neoplasms",
  "D06" = "In Situ Neoplasms",
  "D07" = "In Situ Neoplasms",
  "D09" = "In Situ Neoplasms",

  # === BLOOD AND IMMUNE DISORDERS (D50-D89) ===
  "D50" = "Anemias",
  "D51" = "Anemias",
  "D52" = "Anemias",
  "D53" = "Anemias",
  "D60" = "Anemias",
  "D61" = "Anemias",
  "D62" = "Anemias",
  "D63" = "Anemias",
  "D64" = "Anemias",

  # === ENDOCRINE, NUTRITIONAL AND METABOLIC (E00-E88) ===
  "E10" = "Type 1 Diabetes Mellitus",
  "E11" = "Type 2 Diabetes Mellitus",
  "E13" = "Other Diabetes Mellitus",
  "E14" = "Diabetes Mellitus (Unspecified)",
  "E40" = "Malnutrition",
  "E41" = "Malnutrition",
  "E42" = "Malnutrition",
  "E43" = "Malnutrition",
  "E44" = "Malnutrition",
  "E46" = "Malnutrition",
  "E66" = "Obesity",

  # === MENTAL AND BEHAVIORAL DISORDERS (F00-F99) ===
  "F01" = "Dementia",
  "F02" = "Dementia",
  "F03" = "Dementia",
  "F10" = "Alcohol-Related Disorders",
  "F11" = "Opioid-Related Disorders",
  "F12" = "Cannabis-Related Disorders",
  "F14" = "Cocaine-Related Disorders",
  "F15" = "Stimulant-Related Disorders",
  "F19" = "Drug-Related Disorders",

  # === NERVOUS SYSTEM (G00-G98) ===
  "G20" = "Parkinson Disease",
  "G30" = "Alzheimer Disease",
  "G35" = "Multiple Sclerosis",
  "G40" = "Epilepsy",
  "G70" = "Myasthenia Gravis",

  # === CIRCULATORY DISEASES (I00-I99) ===
  "I10" = "Essential Hypertension",
  "I11" = "Hypertensive Heart Disease",
  "I12" = "Hypertensive Kidney Disease",
  "I13" = "Hypertensive Heart and Kidney Disease",
  "I20" = "Angina Pectoris",
  "I21" = "Acute Myocardial Infarction",
  "I22" = "Acute Myocardial Infarction",
  "I23" = "Acute Myocardial Infarction Complications",
  "I24" = "Acute Ischemic Heart Disease",
  "I25" = "Chronic Ischemic Heart Disease",
  "I26" = "Pulmonary Embolism",
  "I27" = "Pulmonary Heart Disease",
  "I42" = "Cardiomyopathy",
  "I44" = "Atrioventricular Block",
  "I45" = "Conduction Disorders",
  "I46" = "Cardiac Arrest",
  "I47" = "Paroxysmal Tachycardia",
  "I48" = "Atrial Fibrillation and Flutter",
  "I49" = "Other Cardiac Arrhythmias",
  "I50" = "Heart Failure",
  "I60" = "Hemorrhagic Stroke",
  "I61" = "Hemorrhagic Stroke",
  "I62" = "Hemorrhagic Stroke",
  "I63" = "Ischemic Stroke",
  "I64" = "Stroke (Unspecified)",
  "I67" = "Cerebrovascular Disease",
  "I70" = "Atherosclerosis",
  "I71" = "Aortic Aneurysm and Dissection",

  # === RESPIRATORY DISEASES (J00-J98) ===
  "J09" = "Influenza (Identified Virus)",
  "J10" = "Influenza (Identified Virus)",
  "J11" = "Influenza (Unidentified Virus)",
  "J12" = "Viral Pneumonia",
  "J13" = "Pneumococcal Pneumonia",
  "J14" = "Pneumonia (H. Influenzae)",
  "J15" = "Bacterial Pneumonia",
  "J16" = "Pneumonia (Other Organisms)",
  "J17" = "Pneumonia (Other Diseases)",
  "J18" = "Pneumonia (Unspecified)",
  "J40" = "Chronic Bronchitis",
  "J41" = "Chronic Bronchitis",
  "J42" = "Chronic Bronchitis",
  "J43" = "Emphysema",
  "J44" = "Chronic Obstructive Pulmonary Disease",
  "J45" = "Asthma",
  "J84" = "Interstitial Lung Disease",
  "J96" = "Respiratory Failure",

  # === DIGESTIVE DISEASES (K00-K93) ===
  "K25" = "Gastric Ulcer",
  "K26" = "Duodenal Ulcer",
  "K27" = "Peptic Ulcer",
  "K35" = "Acute Appendicitis",
  "K40" = "Inguinal Hernia",
  "K56" = "Intestinal Obstruction",
  "K70" = "Alcoholic Liver Disease",
  "K72" = "Hepatic Failure",
  "K73" = "Chronic Hepatitis",
  "K74" = "Liver Fibrosis and Cirrhosis",
  "K80" = "Cholelithiasis",
  "K85" = "Acute Pancreatitis",
  "K86" = "Chronic Pancreatitis",

  # === MUSCULOSKELETAL (M00-M99) ===
  "M80" = "Osteoporosis with Fracture",
  "M81" = "Osteoporosis without Fracture",

  # === GENITOURINARY DISEASES (N00-N99) ===
  "N17" = "Acute Kidney Failure",
  "N18" = "Chronic Kidney Disease",
  "N19" = "Kidney Failure (Unspecified)",
  "N40" = "Benign Prostatic Hyperplasia",

  # === PREGNANCY COMPLICATIONS (O00-O99) ===
  "O00" = "Pregnancy Complications",
  "O95" = "Obstetric Death",
  "O96" = "Obstetric Death",
  "O97" = "Obstetric Death",

  # === PERINATAL CONDITIONS (P00-P96) ===
  "P00" = "Perinatal Conditions",
  "P01" = "Perinatal Conditions",
  "P02" = "Perinatal Conditions",
  "P07" = "Prematurity",
  "P20" = "Perinatal Respiratory Disorders",
  "P21" = "Perinatal Respiratory Disorders",
  "P22" = "Perinatal Respiratory Disorders",
  "P36" = "Neonatal Sepsis",

  # === CONGENITAL MALFORMATIONS (Q00-Q99) ===
  "Q20" = "Congenital Heart Malformations",
  "Q21" = "Congenital Heart Malformations",
  "Q22" = "Congenital Heart Malformations",
  "Q23" = "Congenital Heart Malformations",
  "Q24" = "Congenital Heart Malformations",
  "Q25" = "Congenital Heart Malformations",

  # === SYMPTOMS AND ILL-DEFINED (R00-R99) ===
  "R54" = "Senility",
  "R99" = "Ill-Defined and Unknown Cause of Mortality",

  # === EXTERNAL CAUSES OF MORBIDITY (V01-Y89) ===
  # Transport accidents
  "V01" = "Transport Accident",
  "V02" = "Transport Accident",
  "V03" = "Transport Accident",
  "V04" = "Transport Accident",
  "V09" = "Transport Accident",
  "V12" = "Transport Accident",
  "V13" = "Transport Accident",
  "V19" = "Transport Accident",
  "V40" = "Transport Accident",
  "V41" = "Transport Accident",
  "V42" = "Transport Accident",
  "V43" = "Transport Accident",
  "V44" = "Transport Accident",
  "V45" = "Transport Accident",
  "V46" = "Transport Accident",
  "V47" = "Transport Accident",
  "V48" = "Transport Accident",
  "V49" = "Transport Accident",
  "V80" = "Transport Accident",
  "V87" = "Transport Accident",
  "V89" = "Transport Accident",

  # Falls
  "W00" = "Falls",
  "W01" = "Falls",
  "W06" = "Falls",
  "W07" = "Falls",
  "W08" = "Falls",
  "W09" = "Falls",
  "W10" = "Falls",
  "W11" = "Falls",
  "W12" = "Falls",
  "W13" = "Falls",
  "W14" = "Falls",
  "W15" = "Falls",
  "W16" = "Falls",
  "W17" = "Falls",
  "W18" = "Falls",
  "W19" = "Falls",

  # Accidental poisoning
  "X40" = "Accidental Poisoning",
  "X41" = "Accidental Poisoning",
  "X42" = "Accidental Poisoning",
  "X43" = "Accidental Poisoning",
  "X44" = "Accidental Poisoning",
  "X45" = "Accidental Poisoning",
  "X49" = "Accidental Poisoning",

  # Intentional self-harm
  "X60" = "Intentional Self-Harm",
  "X61" = "Intentional Self-Harm",
  "X62" = "Intentional Self-Harm",
  "X63" = "Intentional Self-Harm",
  "X64" = "Intentional Self-Harm",
  "X65" = "Intentional Self-Harm",
  "X66" = "Intentional Self-Harm",
  "X67" = "Intentional Self-Harm",
  "X68" = "Intentional Self-Harm",
  "X69" = "Intentional Self-Harm",
  "X70" = "Intentional Self-Harm",
  "X71" = "Intentional Self-Harm",
  "X72" = "Intentional Self-Harm",
  "X73" = "Intentional Self-Harm",
  "X74" = "Intentional Self-Harm",
  "X75" = "Intentional Self-Harm",
  "X76" = "Intentional Self-Harm",
  "X77" = "Intentional Self-Harm",
  "X78" = "Intentional Self-Harm",
  "X79" = "Intentional Self-Harm",
  "X80" = "Intentional Self-Harm",
  "X81" = "Intentional Self-Harm",
  "X82" = "Intentional Self-Harm",
  "X83" = "Intentional Self-Harm",
  "X84" = "Intentional Self-Harm",

  # Assault
  "X85" = "Assault",
  "X86" = "Assault",
  "X87" = "Assault",
  "X88" = "Assault",
  "X89" = "Assault",
  "X90" = "Assault",
  "X91" = "Assault",
  "X92" = "Assault",
  "X93" = "Assault",
  "X94" = "Assault",
  "X95" = "Assault",
  "X96" = "Assault",
  "X97" = "Assault",
  "X98" = "Assault",
  "X99" = "Assault",
  "Y00" = "Assault",
  "Y01" = "Assault",
  "Y02" = "Assault",
  "Y03" = "Assault",
  "Y04" = "Assault",
  "Y05" = "Assault",
  "Y06" = "Assault",
  "Y07" = "Assault",
  "Y08" = "Assault",
  "Y09" = "Assault",
  "Y87" = "Assault",

  # Other external causes
  "Y10" = "Event of Undetermined Intent",
  "Y11" = "Event of Undetermined Intent",
  "Y12" = "Event of Undetermined Intent",
  "Y13" = "Event of Undetermined Intent",
  "Y14" = "Event of Undetermined Intent",
  "Y15" = "Event of Undetermined Intent",
  "Y16" = "Event of Undetermined Intent",
  "Y17" = "Event of Undetermined Intent",
  "Y18" = "Event of Undetermined Intent",
  "Y19" = "Event of Undetermined Intent",
  "Y20" = "Event of Undetermined Intent",
  "Y21" = "Event of Undetermined Intent",
  "Y33" = "Event of Undetermined Intent",
  "Y34" = "Event of Undetermined Intent",

  # Complications of medical/surgical care
  "Y40" = "Complications of Medical Care",
  "Y41" = "Complications of Medical Care",
  "Y42" = "Complications of Medical Care",
  "Y43" = "Complications of Medical Care",
  "Y44" = "Complications of Medical Care",
  "Y83" = "Complications of Medical Care",
  "Y84" = "Complications of Medical Care",

  # === DEFAULT for unmapped codes ===
  "UNK" = "Unknown or Unspecified"
)

# ==============================================================================
# SECTION 5e: DRUG GROUPINGS ----
# ==============================================================================
# Treatment code groupings extracted from all_codes_resolved_next_tables.xlsx.
# Maps treatment codes (CPT/HCPCS/NDC/RXNORM/ICD-10-PCS) to treatment categories.
#
# WHY centralized: Phase 78 episode classification and Phase 79 frequency tables
# need these mappings. Avoids runtime xlsx dependency in downstream scripts.
# Follows AMC_PAYER_LOOKUP / CANCER_SITE_MAP pattern (named vector).
#
# Source: data/reference/all_codes_resolved_next_tables_v2.1.xlsx
# Extracted: Phase 77 (2026-06-02)
# Categories: Chemotherapy (183 codes), Radiation (15 codes), SCT (41 codes),
#            Immunotherapy (49 codes), Supportive Care (171 codes)
# Total: 454 treatment code mappings
# ==============================================================================

DRUG_GROUPINGS <- c(
  # Chemotherapy (183 codes)
  "J9354" = "Chemotherapy",
  "2001102" = "Chemotherapy",
  "J9017" = "Chemotherapy",
  "J9019" = "Chemotherapy",
  "J9021" = "Chemotherapy",
  "J9025" = "Chemotherapy",
  "J9030" = "Chemotherapy",
  "134547" = "Chemotherapy",
  "J9033" = "Chemotherapy",
  "J9034" = "Chemotherapy",
  "J9036" = "Chemotherapy",
  "J9058" = "Chemotherapy",
  "1114693" = "Chemotherapy",
  "1726097" = "Chemotherapy",
  "1726102" = "Chemotherapy",
  "1805001" = "Chemotherapy",
  "J9035" = "Chemotherapy",
  "1622" = "Chemotherapy",
  "1726673" = "Chemotherapy",
  "1726676" = "Chemotherapy",
  "308770" = "Chemotherapy",
  "308771" = "Chemotherapy",
  "J9039" = "Chemotherapy",
  "J9041" = "Chemotherapy",
  "J9043" = "Chemotherapy",
  "J9118" = "Chemotherapy",
  "597195" = "Chemotherapy",
  "686161" = "Chemotherapy",
  "J9045" = "Chemotherapy",
  "J9047" = "Chemotherapy",
  "2105" = "Chemotherapy",
  "309012" = "Chemotherapy",
  "J9050" = "Chemotherapy",
  "J9055" = "Chemotherapy",
  "205821" = "Chemotherapy",
  "2555" = "Chemotherapy",
  "309311" = "Chemotherapy",
  "J9060" = "Chemotherapy",
  "J9065" = "Chemotherapy",
  "J9057" = "Chemotherapy",
  "1437969" = "Chemotherapy",
  "1734917" = "Chemotherapy",
  "1734919" = "Chemotherapy",
  "1734921" = "Chemotherapy",
  "197550" = "Chemotherapy",
  "2568661" = "Chemotherapy",
  "3002" = "Chemotherapy",
  "637543" = "Chemotherapy",
  "J9070" = "Chemotherapy",
  "J9071" = "Chemotherapy",
  "J9073" = "Chemotherapy",
  "J9075" = "Chemotherapy",
  "J9098" = "Chemotherapy",
  "J9100" = "Chemotherapy",
  "1731338" = "Chemotherapy",
  "1731340" = "Chemotherapy",
  "309638" = "Chemotherapy",
  "3098" = "Chemotherapy",
  "J9145" = "Chemotherapy",
  "J9150" = "Chemotherapy",
  "J9171" = "Chemotherapy",
  "1191138" = "Chemotherapy",
  "1790097" = "Chemotherapy",
  "1790098" = "Chemotherapy",
  "1790099" = "Chemotherapy",
  "1790100" = "Chemotherapy",
  "1790103" = "Chemotherapy",
  "1790115" = "Chemotherapy",
  "1790127" = "Chemotherapy",
  "1790129" = "Chemotherapy",
  "1799305" = "Chemotherapy",
  "1799307" = "Chemotherapy",
  "J9321" = "Chemotherapy",
  "J9178" = "Chemotherapy",
  "J9179" = "Chemotherapy",
  "1734340" = "Chemotherapy",
  "197687" = "Chemotherapy",
  "206831" = "Chemotherapy",
  "226719" = "Chemotherapy",
  "310248" = "Chemotherapy",
  "4179" = "Chemotherapy",
  "J9181" = "Chemotherapy",
  "J9358" = "Chemotherapy",
  "J9200" = "Chemotherapy",
  "J9185" = "Chemotherapy",
  "J9190" = "Chemotherapy",
  "J9395" = "Chemotherapy",
  "1719000" = "Chemotherapy",
  "1719003" = "Chemotherapy",
  "1719013" = "Chemotherapy",
  "1720975" = "Chemotherapy",
  "1998783" = "Chemotherapy",
  "J9196" = "Chemotherapy",
  "J9201" = "Chemotherapy",
  "J9286" = "Chemotherapy",
  "J9202" = "Chemotherapy",
  "1791588" = "Chemotherapy",
  "1791591" = "Chemotherapy",
  "1791593" = "Chemotherapy",
  "1791597" = "Chemotherapy",
  "1791598" = "Chemotherapy",
  "310973" = "Chemotherapy",
  "5657" = "Chemotherapy",
  "J9208" = "Chemotherapy",
  "J9206" = "Chemotherapy",
  "J9207" = "Chemotherapy",
  "J9217" = "Chemotherapy",
  "J9218" = "Chemotherapy",
  "J9359" = "Chemotherapy",
  "J9223" = "Chemotherapy",
  "1437713" = "Chemotherapy",
  "J9230" = "Chemotherapy",
  "J9245" = "Chemotherapy",
  "J9246" = "Chemotherapy",
  "J9209" = "Chemotherapy",
  "105585" = "Chemotherapy",
  "105586" = "Chemotherapy",
  "105587" = "Chemotherapy",
  "1441411" = "Chemotherapy",
  "1541215" = "Chemotherapy",
  "1544388" = "Chemotherapy",
  "1544390" = "Chemotherapy",
  "1544398" = "Chemotherapy",
  "1655956" = "Chemotherapy",
  "1655959" = "Chemotherapy",
  "1655960" = "Chemotherapy",
  "1655968" = "Chemotherapy",
  "1921592" = "Chemotherapy",
  "1946772" = "Chemotherapy",
  "283510" = "Chemotherapy",
  "283511" = "Chemotherapy",
  "287734" = "Chemotherapy",
  "311625" = "Chemotherapy",
  "311627" = "Chemotherapy",
  "6851" = "Chemotherapy",
  "J9250" = "Chemotherapy",
  "J9260" = "Chemotherapy",
  "J9280" = "Chemotherapy",
  "J9293" = "Chemotherapy",
  "J9261" = "Chemotherapy",
  "J9999" = "Chemotherapy",
  "J9301" = "Chemotherapy",
  "J9302" = "Chemotherapy",
  "J9263" = "Chemotherapy",
  "J9264" = "Chemotherapy",
  "J9265" = "Chemotherapy",
  "J9267" = "Chemotherapy",
  "J9266" = "Chemotherapy",
  "J9304" = "Chemotherapy",
  "J9305" = "Chemotherapy",
  "J9306" = "Chemotherapy",
  "J9309" = "Chemotherapy",
  "J9307" = "Chemotherapy",
  "105604" = "Chemotherapy",
  "207588" = "Chemotherapy",
  "314167" = "Chemotherapy",
  "8702" = "Chemotherapy",
  "J9308" = "Chemotherapy",
  "J9310" = "Chemotherapy",
  "J9311" = "Chemotherapy",
  "J9312" = "Chemotherapy",
  "J9315" = "Chemotherapy",
  "J9318" = "Chemotherapy", # Replaces J9315 (romidepsin, non-lyophilized)
  "J9319" = "Chemotherapy",
  "J9317" = "Chemotherapy",
  "J9349" = "Chemotherapy",
  "J9330" = "Chemotherapy",
  "J9340" = "Chemotherapy",
  "J9341" = "Chemotherapy", # Replaces J9340 (thiotepa/Tepylute)
  "J9351" = "Chemotherapy",
  "J9355" = "Chemotherapy",
  "11198" = "Chemotherapy",
  "239178" = "Chemotherapy",
  "11202" = "Chemotherapy",
  "1863343" = "Chemotherapy",
  "1863347" = "Chemotherapy",
  "1863349" = "Chemotherapy",
  "1863354" = "Chemotherapy",
  "1863355" = "Chemotherapy",
  "894900" = "Chemotherapy",
  "J9370" = "Chemotherapy",
  "J9371" = "Chemotherapy",
  "J9390" = "Chemotherapy",

  # Radiation (15 codes)
  "77417" = "Radiation",
  "77470" = "Radiation",
  "77421" = "Radiation",
  "77413" = "Radiation",
  "77418" = "Radiation",
  "77414" = "Radiation",
  "77416" = "Radiation",
  "77435" = "Radiation",
  "77431" = "Radiation",
  "77432" = "Radiation",
  "77408" = "Radiation",
  "77404" = "Radiation",
  "77387" = "Radiation", # Replaces 77421
  "77385" = "Radiation", # Replaces 77418
  "77412" = "Radiation", # Replaces 77413, 77414, 77416

  # NOTE: 5 false-positive codes removed (v2.3 Phase 90, CLEAN-01):
  #   Z94.84 (transplant status), T86.5/T86.09 (transplant complications),
  #   Z48.290 (aftercare), HEMATOLOGIC_TRANSPLANT_AND_ENDOC (tumor registry flag)
  #   These are status/complication/aftercare codes, not procedures.
  #   Still used for cohort inclusion in R/10 has_sct() -- just no longer trigger episodes.

  # SCT (36 codes)
  "38241" = "SCT",
  "016" = "SCT",
  "30243Y0" = "SCT",
  "38240" = "SCT",
  "41.04" = "SCT",
  "0362" = "SCT",
  "30233Y0" = "SCT",
  "014" = "SCT",
  "41.05" = "SCT",
  "30243Y2" = "SCT",
  "0815" = "SCT",
  "30243Y3" = "SCT",
  "017" = "SCT",
  "38242" = "SCT",
  "30233Y2" = "SCT",
  "41.01" = "SCT",
  "41.03" = "SCT",
  "30243Y1" = "SCT",
  "30243C0" = "SCT",
  "30243G0" = "SCT",
  "30233Y1" = "SCT",
  "38230" = "SCT",
  "38232" = "SCT",
  "30233C0" = "SCT",
  "30243G2" = "SCT",
  "30233G0" = "SCT",
  "30233Y3" = "SCT",
  "38243" = "SCT",
  "41.07" = "SCT",
  "41.08" = "SCT",
  "30233X0" = "SCT",
  "30243G1" = "SCT",
  "30243G3" = "SCT",
  "30243U3" = "SCT",
  "30243X0" = "SCT",
  "41.06" = "SCT",

  # Immunotherapy (51 codes)
  # Checkpoint inhibitors and ADCs (moved from Chemotherapy)
  "J9022" = "Immunotherapy",   # Atezolizumab (anti-PD-L1)
  "J9119" = "Immunotherapy",   # Cemiplimab (anti-PD-1)
  "J9173" = "Immunotherapy",   # Durvalumab (anti-PD-L1)
  "J9204" = "Immunotherapy",   # Mogamulizumab (anti-CCR4)
  "J9228" = "Immunotherapy",   # Ipilimumab (anti-CTLA-4)
  "J9268" = "Immunotherapy",   # Pembrolizumab (anti-PD-1)
  "J9271" = "Immunotherapy",   # Pembrolizumab IV (anti-PD-1)
  "1147324" = "Immunotherapy", # Brentuximab Vedotin (anti-CD30 ADC)
  "1147320" = "Immunotherapy", # Brentuximab Vedotin (anti-CD30 ADC)
  "1147323" = "Immunotherapy", # Brentuximab Vedotin (anti-CD30 ADC)
  "1147327" = "Immunotherapy", # Brentuximab Vedotin (anti-CD30 ADC)
  "1597876" = "Immunotherapy", # Nivolumab (anti-PD-1)
  "1657190" = "Immunotherapy", # Nivolumab (anti-PD-1)
  "1657192" = "Immunotherapy", # Nivolumab (anti-PD-1)
  "1657193" = "Immunotherapy", # Nivolumab (anti-PD-1)
  "1657195" = "Immunotherapy", # Nivolumab (anti-PD-1)
  "1657196" = "Immunotherapy", # Nivolumab (anti-PD-1)
  "1991412" = "Immunotherapy", # Nivolumab (anti-PD-1)
  "1991413" = "Immunotherapy", # Nivolumab (anti-PD-1)
  "1657749" = "Immunotherapy", # Pembrolizumab (anti-PD-1)
  "1657750" = "Immunotherapy", # Pembrolizumab (anti-PD-1)
  "1657751" = "Immunotherapy", # Pembrolizumab (anti-PD-1)
  # Original Immunotherapy codes
  "1090823" = "Immunotherapy",
  "XW033E5" = "Immunotherapy",
  "1248142" = "Immunotherapy",
  "XW043B3" = "Immunotherapy",
  "XW043E5" = "Immunotherapy",
  "XW043C3" = "Immunotherapy",
  "XW033B3" = "Immunotherapy",
  "1313925" = "Immunotherapy",
  "1090824" = "Immunotherapy",
  "XW033H5" = "Immunotherapy",
  "XW033C3" = "Immunotherapy",
  "XW043P9" = "Immunotherapy",
  "891815" = "Immunotherapy",
  "891716" = "Immunotherapy",
  "XW033H6" = "Immunotherapy",
  "XW043H5" = "Immunotherapy",
  "XW033A3" = "Immunotherapy",
  "XW033C6" = "Immunotherapy",
  "XW033D6" = "Immunotherapy",
  "XW043A7" = "Immunotherapy",
  "XW043C6" = "Immunotherapy",
  "1094836" = "Immunotherapy",
  "891790" = "Immunotherapy",
  "1919507" = "Immunotherapy",
  "2479140" = "Immunotherapy",
  "1792780" = "Immunotherapy",
  "891793" = "Immunotherapy",
  # Immunotherapy encounter diagnosis codes
  "Z51.12" = "Immunotherapy", # Encounter for antineoplastic immunotherapy (ICD-10)
  "V58.12" = "Immunotherapy", # Encounter for antineoplastic immunotherapy (ICD-9)

  # Supportive Care (171 codes)
  "283504" = "Supportive Care",
  "104894" = "Supportive Care",
  "312086" = "Supportive Care",
  "312087" = "Supportive Care",
  "1812194" = "Supportive Care",
  "1740467" = "Supportive Care",
  "197582" = "Supportive Care",
  "198052" = "Supportive Care",
  "104896" = "Supportive Care",
  "1116927" = "Supportive Care",
  "1314133" = "Supportive Care",
  "104897" = "Supportive Care",
  "104895" = "Supportive Care",
  "1812095" = "Supportive Care",
  "876690" = "Supportive Care",
  "68442" = "Supportive Care",
  "309698" = "Supportive Care",
  "26225" = "Supportive Care",
  "1649944" = "Supportive Care",
  "205712" = "Supportive Care",
  "1731077" = "Supportive Care",
  "309696" = "Supportive Care",
  "2549331" = "Supportive Care",
  "727539" = "Supportive Care",
  "197581" = "Supportive Care",
  "1649963" = "Supportive Care",
  "876693" = "Supportive Care",
  "3264" = "Supportive Care",
  "727542" = "Supportive Care",
  "338036" = "Supportive Care",
  "1728055" = "Supportive Care",
  "240449" = "Supportive Care",
  "754508" = "Supportive Care",
  "727535" = "Supportive Care",
  "309686" = "Supportive Care",
  "26237" = "Supportive Care",
  "1649946" = "Supportive Care",
  "403811" = "Supportive Care",
  "1605074" = "Supportive Care",
  "403908" = "Supportive Care",
  "727544" = "Supportive Care",
  "197577" = "Supportive Care",
  "312085" = "Supportive Care",
  "2057209" = "Supportive Care",
  "404630" = "Supportive Care",
  "403810" = "Supportive Care",
  "197579" = "Supportive Care",
  "226343" = "Supportive Care",
  "309683" = "Supportive Care",
  "197583" = "Supportive Care",
  "1605066" = "Supportive Care",
  "310599" = "Supportive Care",
  "309679" = "Supportive Care",
  "208601" = "Supportive Care",
  "309680" = "Supportive Care",
  "1812079" = "Supportive Care",
  "358255" = "Supportive Care",
  "754509" = "Supportive Care",
  "403886" = "Supportive Care",
  "309692" = "Supportive Care",
  "309684" = "Supportive Care",
  "2057200" = "Supportive Care",
  "1649964" = "Supportive Care",
  "208591" = "Supportive Care",
  "2261802" = "Supportive Care",
  "242706" = "Supportive Care",
  "283838" = "Supportive Care",
  "1734399" = "Supportive Care",
  "197580" = "Supportive Care",
  "309682" = "Supportive Care",
  "1721684" = "Supportive Care",
  "2047591" = "Supportive Care",
  "205717" = "Supportive Care",
  "2463731" = "Supportive Care",
  "644088" = "Supportive Care",
  "2057218" = "Supportive Care",
  "727545" = "Supportive Care",
  "727537" = "Supportive Care",
  "105694" = "Supportive Care",
  "2549333" = "Supportive Care",
  "212447" = "Supportive Care",
  "2047600" = "Supportive Care",
  "755976" = "Supportive Care",
  "2057215" = "Supportive Care",
  "2048020" = "Supportive Care",
  "343033" = "Supportive Care",
  "240377" = "Supportive Care",
  "1605071" = "Supportive Care",
  "2469340" = "Supportive Care",
  "1490065" = "Supportive Care",
  "2102703" = "Supportive Care",
  "239998" = "Supportive Care",
  "208813" = "Supportive Care",
  "241999" = "Supportive Care",
  "730044" = "Supportive Care",
  "2057216" = "Supportive Care",
  "2102705" = "Supportive Care",
  "2048025" = "Supportive Care",
  "240912" = "Supportive Care",
  "2057212" = "Supportive Care",
  "825005" = "Supportive Care",
  "2469335" = "Supportive Care",
  "240000" = "Supportive Care",
  "404466" = "Supportive Care",
  "731179" = "Supportive Care",
  "205669" = "Supportive Care",
  "731174" = "Supportive Care",
  "239999" = "Supportive Care",
  "998032" = "Supportive Care",
  "2047621" = "Supportive Care",
  "404465" = "Supportive Care",
  "2260704" = "Supportive Care",
  "1728052" = "Supportive Care",
  "313947" = "Supportive Care",
  "2260709" = "Supportive Care",
  "208602" = "Supportive Care",
  "1442683" = "Supportive Care",
  "2595961" = "Supportive Care",
  "792710" = "Supportive Care",
  "1605075" = "Supportive Care",
  "731184" = "Supportive Care",
  "1947301" = "Supportive Care",
  "998033" = "Supportive Care",
  "1433771" = "Supportive Care",
  "2057205" = "Supportive Care",
  "731167" = "Supportive Care",
  "825003" = "Supportive Care",
  "1433768" = "Supportive Care",
  "2048018" = "Supportive Care",
  "2047612" = "Supportive Care",
  "731176" = "Supportive Care",
  "2463735" = "Supportive Care",
  "998035" = "Supportive Care",
  "70561" = "Supportive Care",
  "1442681" = "Supportive Care",
  "1998482" = "Supportive Care",
  "6316" = "Supportive Care",
  "759696" = "Supportive Care",
  "2047606" = "Supportive Care",
  "1605064" = "Supportive Care",
  "759697" = "Supportive Care",
  "2047623" = "Supportive Care",
  "205913" = "Supportive Care",
  "1995150" = "Supportive Care",
  "349275" = "Supportive Care",
  "847225" = "Supportive Care",
  "64695" = "Supportive Care",
  "349273" = "Supportive Care",
  "1998481" = "Supportive Care",
  "2101459" = "Supportive Care",
  "2469333" = "Supportive Care",
  "849115" = "Supportive Care",
  "901649" = "Supportive Care",
  "2056929" = "Supportive Care",
  "349274" = "Supportive Care",
  "1995155" = "Supportive Care",
  "731181" = "Supportive Care",
  "29225" = "Supportive Care",
  "357280" = "Supportive Care",
  "343040" = "Supportive Care",
  "6314" = "Supportive Care",
  "731227" = "Supportive Care",
  "105392" = "Supportive Care",
  "208588" = "Supportive Care",
  "1721690" = "Supportive Care",
  "1731082" = "Supportive Care",
  "795716" = "Supportive Care",
  "1728050" = "Supportive Care",
  "644278" = "Supportive Care",
  "213475" = "Supportive Care",
  "2101456" = "Supportive Care"
)

# Quick sanity check
message(glue("Defined {length(DRUG_GROUPINGS)} treatment code mappings across {length(unique(DRUG_GROUPINGS))} categories"))

# ==============================================================================
# SECTION 5d: TREATMENT CODE SUB-CATEGORY MAP ----
# ==============================================================================
# Maps treatment codes to readable sub-category names (medication/procedure).
# Used by R/56 as Tier 2 lookup after xlsx reference and before code-type fallbacks.
#
# WHY centralized: Per D-07, follows AMC_PAYER_LOOKUP/CANCER_SITE_MAP/DRUG_GROUPINGS
# pattern. Supplements xlsx reference mappings for codes not covered in the
# all_codes_resolved_next_tables_v2.1.xlsx sheets.
#
# Sources:
#   - HCPCS J-codes: CMS HCPCS code descriptions (drug injection codes)
#   - RxNorm CUIs: RxNorm concept preferred terms (extracted from TREATMENT_CODES comments)
#   - CPT codes: Procedure descriptions from TREATMENT_CODES comments
#   - ICD procedure/DRG/revenue codes: Group-level labels (too granular for specific names)
#
# Phase 81 (2026-06-03)
# ==============================================================================

CODE_SUBCATEGORY_MAP <- c(
  # Chemotherapy HCPCS J-codes (medication names from HCPCS code descriptions)
  "J9000" = "Doxorubicin",
  "J9017" = "Arsenic Trioxide",
  "J9019" = "Asparaginase",
  "J9021" = "Asparaginase (Erwinia)",
  "J9022" = "Atezolizumab",
  "J9025" = "Azacitidine",
  "J9030" = "BCG Live (Intravesical)",
  "J9033" = "Bendamustine (Treanda)",
  "J9034" = "Bendamustine (Bendeka)",
  "J9035" = "Bevacizumab",
  "J9036" = "Busulfan",
  "J9039" = "Blinatumomab",
  "J9040" = "Bleomycin",
  "J9041" = "Bortezomib",
  "J9042" = "Brentuximab Vedotin",
  "J9043" = "Cabazitaxel",
  "J9045" = "Carboplatin",
  "J9047" = "Carfilzomib",
  "J9050" = "Carmustine",
  "J9055" = "Cetuximab",
  "J9057" = "Copanlisib",
  "J9058" = "Crizotinib",
  "J9060" = "Cisplatin",
  "J9065" = "Cladribine",
  "J9070" = "Cyclophosphamide (100mg)",
  "J9071" = "Cyclophosphamide (200mg)",
  "J9073" = "Cyclophosphamide (500mg)",
  "J9075" = "Cyclophosphamide (1g)",
  "J9098" = "Cytarabine",
  "J9100" = "Cytarabine (500mg)",
  "J9118" = "Calaspargase Pegol",
  "J9119" = "Cemiplimab",
  "J9130" = "Dacarbazine",
  "J9145" = "Daratumumab",
  "J9150" = "Daunorubicin",
  "J9171" = "Docetaxel",
  "J9173" = "Durvalumab",
  "J9178" = "Epirubicin",
  "J9179" = "Eribulin",
  "J9181" = "Etoposide",
  "J9185" = "Fludarabine",
  "J9190" = "Fluorouracil",
  "J9196" = "Gemcitabine",
  "J9200" = "Floxuridine",
  "J9201" = "Gemcitabine (200mg)",
  "J9202" = "Goserelin",
  "J9204" = "Mogamulizumab",
  "J9206" = "Irinotecan",
  "J9207" = "Ixabepilone",
  "J9208" = "Ifosfamide",
  "J9209" = "Mesna",
  "J9217" = "Leuprolide",
  "J9218" = "Lurbinectedin",
  "J9223" = "Liposomal Doxorubicin",
  "J9228" = "Ipilimumab",
  "J9230" = "Mechlorethamine",
  "J9245" = "Melphalan (IV)",
  "J9246" = "Melphalan (Oral)",
  "J9250" = "Methotrexate (Sodium)",
  "J9260" = "Methotrexate (50mg)",
  "J9261" = "Nelarabine",
  "J9263" = "Oxaliplatin",
  "J9264" = "Paclitaxel",
  "J9265" = "Paclitaxel (Protein-Bound)",
  "J9266" = "Pegaspargase",
  "J9267" = "Paclitaxel (Abraxane)",
  "J9268" = "Pembrolizumab",
  "J9271" = "Pembrolizumab (IV)",
  "J9280" = "Mitomycin",
  "J9286" = "Peginterferon Alfa-2b",
  "J9293" = "Mitoxantrone",
  "J9299" = "Nivolumab",
  "J9301" = "Obinutuzumab",
  "J9302" = "Ofatumumab",
  "J9303" = "Paclitaxel",
  "J9304" = "Pemetrexed (NOS)",
  "J9305" = "Pemetrexed (Alimta)",
  "J9306" = "Pertuzumab",
  "J9307" = "Pralatrexate",
  "J9308" = "Ramucirumab",
  "J9309" = "Polatuzumab Vedotin",
  "J9310" = "Rituximab",
  "J9311" = "Rituximab/Hyaluronidase",
  "J9312" = "Rituximab (Truxima)",
  "J9315" = "Romidepsin",
  "J9317" = "Sacituzumab Govitecan",
  "J9318" = "Romidepsin (non-lyophilized)",
  "J9319" = "Tafasitamab",
  "J9321" = "Etoposide (Oral)",
  "J9330" = "Temsirolimus",
  "J9340" = "Thiotepa",
  "J9341" = "Thiotepa (Tepylute)",
  "J9349" = "Trastuzumab/Hyaluronidase",
  "J9351" = "Topotecan",
  "J9354" = "Ado-Trastuzumab Emtansine",
  "J9355" = "Trastuzumab",
  "J9358" = "Fam-Trastuzumab Deruxtecan",
  "J9359" = "Loncastuximab Tesirine",
  "J9360" = "Vinblastine",
  "J9370" = "Vincristine (1mg)",
  "J9371" = "Vincristine (2mg)",
  "J9390" = "Vinorelbine",
  "J9395" = "Fulvestrant",
  "J9999" = "Antineoplastic Drug (NOS)",

  # Chemotherapy RxNorm codes (base drug names from inline comments)
  "3639" = "Doxorubicin",
  "11213" = "Bleomycin",
  "67228" = "Vinblastine",
  "3946" = "Dacarbazine",
  "239178" = "Vinblastine",
  "1657195" = "Nivolumab",
  "1791591" = "Ifosfamide",
  "207588" = "Procarbazine",
  "1991412" = "Nivolumab",
  "134547" = "Bendamustine",
  "1799305" = "Doxorubicin",
  "1147327" = "Brentuximab Vedotin",
  "1657750" = "Pembrolizumab",
  "105585" = "Methotrexate",
  "1863354" = "Vincristine",
  "1790115" = "Doxorubicin (Liposomal)",
  "1655960" = "Methotrexate",
  "1791598" = "Ifosfamide",
  "1946772" = "Methotrexate",
  "3098" = "Dacarbazine",
  "1147324" = "Brentuximab Vedotin",
  "311627" = "Methotrexate",
  "1734921" = "Cyclophosphamide",
  "2105" = "Carmustine",
  "11198" = "Vinblastine",
  "1114693" = "Bendamustine",
  "105587" = "Methotrexate",
  "1544390" = "Methotrexate",
  "1657196" = "Nivolumab",
  "1657751" = "Pembrolizumab",
  "1726673" = "Bleomycin",
  "1790099" = "Doxorubicin",
  "1734919" = "Cyclophosphamide",
  "894900" = "Vincristine",
  "637543" = "Cyclophosphamide",
  "1597876" = "Nivolumab",
  "314167" = "Procarbazine",
  "1734340" = "Etoposide",
  "205821" = "Cisplatin",
  "1147323" = "Brentuximab Vedotin",
  "1790100" = "Doxorubicin",
  "686161" = "Carboplatin",
  "1863347" = "Vincristine",
  "1657749" = "Pembrolizumab",
  "1655959" = "Methotrexate",
  "1437969" = "Cyclophosphamide",
  "1622" = "Bleomycin",
  "105604" = "Procarbazine",
  "310248" = "Etoposide",
  "1863343" = "Vincristine",
  "226719" = "Etoposide",
  "1998783" = "Gemcitabine",
  "1657192" = "Nivolumab",
  "1790098" = "Doxorubicin",
  "2555" = "Cisplatin",
  "105586" = "Methotrexate",
  "1921592" = "Methotrexate",
  "2001102" = "Doxorubicin",
  "309012" = "Carmustine",
  "287734" = "Methotrexate",
  "308770" = "Bleomycin",
  "8702" = "Procarbazine",
  "3002" = "Cyclophosphamide",
  "311625" = "Methotrexate",
  "1657190" = "Nivolumab",
  "1790129" = "Doxorubicin (Liposomal)",
  "308771" = "Bleomycin",
  "1726676" = "Bleomycin",
  "197550" = "Cyclophosphamide",
  "1441411" = "Methotrexate",
  "283511" = "Methotrexate",
  "197687" = "Etoposide",
  "206831" = "Etoposide",
  "4179" = "Etoposide",
  "1719000" = "Fluorouracil",
  "1191138" = "Docetaxel",
  "1790097" = "Doxorubicin",
  "1731338" = "Cytarabine",
  "1731340" = "Dacarbazine",
  "309638" = "Dacarbazine",

  # Radiation CPT codes (procedure descriptions)
  "77261" = "Radiation Planning (Simple)",
  "77262" = "Radiation Planning (Intermediate)",
  "77263" = "Radiation Planning (Complex)",
  "77280" = "Radiation Simulation (Simple)",
  "77285" = "Radiation Simulation (Intermediate)",
  "77290" = "Radiation Simulation (Complex)",
  "77293" = "Respiratory Motion Management",
  "77295" = "3D Radiotherapy Plan",
  "77300" = "Radiation Dosimetry",
  "77301" = "IMRT Plan",
  "77306" = "Teletherapy Isodose (Simple)",
  "77307" = "Teletherapy Isodose (Complex)",
  "77310" = "Brachytherapy Isodose (Simple)",
  "77315" = "Brachytherapy Isodose (Complex)",
  "77316" = "Brachytherapy Plan (Simple)",
  "77318" = "Brachytherapy Plan (Complex)",
  "77321" = "Special Teletherapy Port",
  "77331" = "Special Dosimetry",
  "77332" = "Treatment Devices (Simple)",
  "77333" = "Treatment Devices (Intermediate)",
  "77334" = "Treatment Devices (Complex)",
  "77336" = "Medical Physics Consult",
  "77338" = "Multi-leaf Collimator Design",
  "77370" = "Medical Physics Consult (Special)",
  "77371" = "SRS (Gamma Knife)",
  "77372" = "SRS (Linac)",
  "77373" = "SBRT Delivery",
  "77385" = "IMRT Delivery (Simple)",
  "77386" = "IMRT Delivery (Complex)",
  "77387" = "Image Guidance (IGRT)",
  "77399" = "Radiation Delivery (Unlisted)",
  "77401" = "Surface Radiation Delivery",
  "77402" = "Radiation Delivery (Intermediate)",
  "77404" = "Radiation Delivery (6-10 MeV)",
  "77407" = "Radiation Delivery (Simple)",
  "77408" = "Radiation Delivery (2 Areas)",
  "77412" = "Radiation Delivery (Complex)",
  "77413" = "Radiation Delivery (3+ Areas, 6-10 MeV)",
  "77414" = "Radiation Delivery (3+ Areas, 11-19 MeV)",
  "77416" = "Radiation Delivery (3+ Areas, 20+ MeV)",
  "77417" = "Portal Imaging",
  "77418" = "IMRT Delivery (Legacy)",
  "77421" = "Stereoscopic X-ray Guidance",
  "77427" = "Radiation Treatment Management",
  "77431" = "Radiation Management (End-of-Course)",
  "77432" = "Stereotactic Cranial Management",
  "77435" = "SBRT Management",
  "77470" = "Special Radiation (TBI)",
  "77520" = "Proton Beam (Simple)",
  "77522" = "Proton Beam (Simple w/ Compensation)",
  "77523" = "Proton Beam (Intermediate)",
  "77525" = "Proton Beam (Complex)",
  "77605" = "Deep Hyperthermia",
  "77750" = "Brachytherapy (Radioelement)",
  "77763" = "Brachytherapy (Interstitial, Complex)",
  "77768" = "Brachytherapy (Intracavitary)",
  "77770" = "HDR Brachytherapy (1 Channel)",
  "77771" = "HDR Brachytherapy (2-12 Channels)",
  "77772" = "HDR Brachytherapy (12+ Channels)",
  "77785" = "Remote Afterloading Brachytherapy",
  "G6012" = "3D Conformal (Intermediate)",
  "G6013" = "3D Conformal (Complex)",
  "G6015" = "IMRT (Complex)",

  # SCT CPT/HCPCS codes
  "38230" = "Bone Marrow Harvesting",
  "38232" = "Bone Marrow Harvesting (Autologous)",
  "38240" = "Allogeneic HPC Transplantation",
  "38241" = "Autologous HPC Transplantation",
  "38242" = "Donor Lymphocyte Infusion (DLI)",
  "38243" = "Allogeneic HPC Boost",
  "S2140" = "Cord Blood Harvesting (Allogeneic)",
  "S2142" = "Cord Blood Transplantation",
  "S2150" = "Stem Cell Transplant (Allogeneic/Autologous)",

  # SCT RxNorm codes
  "1740865" = "Fludarabine",
  "253113" = "Busulfan",
  "1660004" = "Thiotepa",
  "284425" = "Busulfan (Busulfex)",
  "197919" = "Melphalan",
  "876399" = "Melphalan (Alkeran)",
  "1740864" = "Fludarabine",
  "311487" = "Melphalan",

  # Immunotherapy RxNorm codes
  "1094836" = "Ipilimumab",
  "891815" = "Multivitamin (Immunotherapy)",
  "891790" = "Multivitamin (Immunotherapy)",
  "1919507" = "Durvalumab",
  "1090823" = "Multivitamin (Immunotherapy)",
  "1313925" = "Multivitamin (Immunotherapy)",
  "1248142" = "Multivitamin (Immunotherapy)",
  "891716" = "Multivitamin (Immunotherapy)",
  "2479140" = "Lisocabtagene Maraleucel (CAR-T)",
  "1792780" = "Atezolizumab",
  "1090824" = "Multivitamin (Immunotherapy)",
  "891793" = "Multivitamin (Immunotherapy)",

  # DRG codes (group-level labels)
  "016" = "Autologous Bone Marrow Transplant (DRG)",
  "014" = "Allogeneic Bone Marrow Transplant (DRG)",
  "017" = "Bone Marrow Transplant w/ CC/MCC (DRG)",
  "018" = "Chimeric Antigen Receptor T-cell (DRG)",
  "837" = "Chemotherapy w/o Acute Leukemia (MCC)",
  "838" = "Chemotherapy w/o Acute Leukemia (CC)",
  "839" = "Chemotherapy w/o Acute Leukemia",
  "846" = "Chemotherapy w/ Hematologic Malignancy (MCC)",
  "847" = "Chemotherapy w/ Hematologic Malignancy (CC)",
  "848" = "Chemotherapy w/ Hematologic Malignancy",
  "849" = "Radiotherapy (DRG)",

  # Revenue codes (group-level labels)
  "0331" = "Chemotherapy (Injected)",
  "0332" = "Chemotherapy (Oral)",
  "0335" = "Chemotherapy (IV Push)",
  "0330" = "Therapeutic Radiology",
  "0333" = "Radiation Therapy",
  "0362" = "Organ Transplant (Includes SCT)",
  "0815" = "Allogeneic Stem Cell Acquisition",

  # ICD-9 procedure codes (group-level labels)
  "99.25" = "Chemo Injection/Infusion (ICD-9)",
  "99.28" = "Immunotherapy Infusion (ICD-9)",
  "41.00" = "Bone Marrow Transplant (NOS)",
  "41.01" = "Autologous BMT (No Purging)",
  "41.02" = "Allogeneic BMT (With Purging)",
  "41.03" = "Allogeneic BMT (No Purging)",
  "41.04" = "Autologous HPC (No Purging)",
  "41.05" = "Allogeneic HPC (No Purging)",
  "41.06" = "Cord Blood Transplant",
  "41.07" = "Autologous HPC (With Purging)",
  "41.08" = "Allogeneic HPC (With Purging)",
  "41.09" = "Autologous BMT (With Purging)",
  "92.20" = "Liquid Brachytherapy",
  "92.21" = "Superficial Radiation",
  "92.22" = "Orthovoltage Radiation",
  "92.23" = "Radioisotopic Teleradiotherapy",
  "92.24" = "Teleradiotherapy (Photons)",
  "92.25" = "Teleradiotherapy (Electrons)",
  "92.26" = "Teleradiotherapy (Particulate)",
  "92.27" = "Radioactive Element Implant",
  "92.29" = "Radiotherapy (Other)",
  "92.30" = "Stereotactic Radiosurgery (NOS)",
  "92.31" = "Single Source Photon Radiosurgery",
  "92.32" = "Multi-source Photon Radiosurgery (Gamma Knife)",
  "92.33" = "Particulate Radiosurgery",
  "92.41" = "Intra-operative Electron Radiation (IERT)",

  # ICD-10 encounter diagnosis codes
  "Z51.11" = "Chemotherapy Encounter",
  "Z51.12" = "Immunotherapy Encounter",
  "V58.11" = "Chemotherapy Encounter (ICD-9)",
  "V58.12" = "Immunotherapy Encounter (ICD-9)",
  "Z51.0" = "Radiation Encounter",
  "V58.0" = "Radiation Encounter (ICD-9)"
)

# Quick sanity check
message(glue("Defined {length(CODE_SUBCATEGORY_MAP)} code-to-subcategory mappings"))

# ==============================================================================
# SECTION 6: ANALYSIS PARAMETERS ----
# ==============================================================================

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

# ==============================================================================
# SECTION 7: TREATMENT CODE LISTS ----
# ==============================================================================
# For treatment flag detection: chemotherapy, radiation, SCT, immunotherapy, supportive care
#
# WHY these specific code sets:
# - Chemotherapy: ABVD is first-line HL standard-of-care; J9000-J9999 range covers
#   all injectable chemo drugs including BV+AVD and Nivo+AVD regimens
# - Radiation: Narrow CPT range (77385-77427) based on Phase 45 audit of 70010-79999
#   full radiology range; excludes diagnostic imaging (77065-77084), nuclear medicine
#   (78012-79999), and irrelevant modalities
# - SCT: 38240-38243 per ASBMT coding guidelines; covers both autologous and
#   allogeneic (single HAD_SCT flag per D-07)
# - ICD-9/ICD-10 procedure codes added Phase 8 to catch procedural coding from
#   pre-2015 records (ICD-9) and recent records (ICD-10-PCS)
#
# Used by 10_cohort_predicates.R to identify treatment evidence in 7 tables:
# PROCEDURES (CPT/HCPCS, ICD-9-CM, ICD-10-PCS, revenue codes), PRESCRIBING (RXNORM),
# DISPENSING (RXNORM), MED_ADMIN (RXNORM), DIAGNOSIS (Z/V codes), ENCOUNTER (DRG codes)
#
# Primary treatment evidence comes from TUMOR_REGISTRY date columns:
#   - TR1: CHEMO_START_DATE_SUMMARY (chemo), no DT_RAD column
#   - TR2/TR3: DT_CHEMO, DT_RAD, DT_HTE (hematologic transplant/endocrine)
# Supplemental evidence comes from PROCEDURES and PRESCRIBING codes below.
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
    "J9000", # Doxorubicin HCl (Adriamycin)
    "J9040", # Bleomycin sulfate
    "J9360", # Vinblastine sulfate
    "J9130", # Dacarbazine (DTIC)
    "J9017", # Phase 39: J9017
    "J9019", # Phase 39: J9019
    "J9021", # Phase 39: J9021
    "J9025", # Phase 39: J9025
    "J9030", # Phase 39: J9030
    "J9033", # Phase 39: J9033
    "J9034", # Phase 39: J9034
    "J9035", # Phase 39: J9035
    "J9036", # Phase 39: J9036
    "J9039", # Phase 39: J9039
    "J9041", # Phase 39: J9041
    "J9043", # Phase 39: J9043
    "J9045", # Phase 39: J9045
    "J9047", # Phase 39: J9047
    "J9050", # Phase 39: J9050
    "J9055", # Phase 39: J9055
    "J9057", # Phase 39: J9057
    "J9058", # Phase 39: J9058
    "J9060", # Phase 39: J9060
    "J9065", # Phase 39: J9065
    "J9070", # Phase 39: J9070
    "J9071", # Phase 39: J9071
    "J9073", # Phase 39: J9073
    "J9075", # Phase 39: J9075
    "J9098", # Phase 39: J9098
    "J9100", # Phase 39: J9100
    "J9118", # Phase 39: J9118
    "J9145", # Phase 39: J9145
    "J9150", # Phase 39: J9150
    "J9171", # Phase 39: J9171
    "J9178", # Phase 39: J9178
    "J9179", # Phase 39: J9179
    "J9181", # Phase 39: J9181
    "J9185", # Phase 39: J9185
    "J9190", # Phase 39: J9190
    "J9196", # Phase 39: J9196
    "J9200", # Phase 39: J9200
    "J9201", # Phase 39: J9201
    "J9202", # Phase 39: J9202
    "J9206", # Phase 39: J9206
    "J9207", # Phase 39: J9207
    "J9208", # Phase 39: J9208
    "J9209", # Phase 39: J9209
    "J9217", # Phase 39: J9217
    "J9218", # Phase 39: J9218
    "J9223", # Phase 39: J9223
    "J9230", # Phase 39: J9230
    "J9245", # Phase 39: J9245
    "J9246", # Phase 39: J9246
    "J9250", # Phase 39: J9250
    "J9260", # Phase 39: J9260
    "J9261", # Phase 39: J9261
    "J9263", # Phase 39: J9263
    "J9264", # Phase 39: J9264
    "J9265", # Phase 39: J9265
    "J9266", # Phase 39: J9266
    "J9267", # Phase 39: J9267
    "J9280", # Phase 39: J9280
    "J9286", # Phase 39: J9286
    "J9293", # Phase 39: J9293
    "J9301", # Phase 39: J9301
    "J9302", # Phase 39: J9302
    "J9304", # Phase 39: J9304
    "J9305", # Phase 39: J9305
    "J9306", # Phase 39: J9306
    "J9307", # Phase 39: J9307
    "J9308", # Phase 39: J9308
    "J9309", # Phase 39: J9309
    "J9310", # Phase 39: J9310
    "J9311", # Phase 39: J9311
    "J9312", # Phase 39: J9312
    "J9315", # Phase 39: J9315
    "J9317", # Phase 39: J9317
    "J9319", # Phase 39: J9319
    "J9321", # Phase 39: J9321
    "J9330", # Phase 39: J9330
    "J9340", # Phase 39: J9340
    "J9349", # Phase 39: J9349
    "J9351", # Phase 39: J9351
    "J9354", # Phase 39: J9354
    "J9355", # Phase 39: J9355
    "J9358", # Phase 39: J9358
    "J9359", # Phase 39: J9359
    "J9370", # Phase 39: J9370
    "J9371", # Phase 39: J9371
    "J9390", # Phase 39: J9390
    "J9395", # Phase 39: J9395
    "J9999" # Phase 39: J9999
  ),

  # Chemotherapy RXNORM CUIs for PRESCRIBING table matching
  # ABVD regimen base ingredients (RxNorm concept IDs)
  chemo_rxnorm = c(
    "3639", # Doxorubicin
    "11213", # Bleomycin
    "67228", # Vinblastine
    "3946", # Dacarbazine
    "239178", # Phase 40: vinblastine sulfate 1 MG/ML Injectable S
    "1791591", # Phase 40: ifosfamide 3000 MG Injection [Ifex]
    "207588", # Phase 40: procarbazine 50 MG Oral Capsule [Matulan
    "134547", # Phase 40: bendamustine
    "1799305", # Phase 40: DOXOrubicin  IV infusion,
    "105585", # Phase 40: methotrexate 2.5 MG Oral Tablet
    "1863354", # Phase 40: 2 ML vincristine sulfate 1 MG/ML Injecti
    "1790115", # Phase 40: 10 ML doxorubicin hydrochloride liposome
    "1655960", # Phase 40: 2 ML methotrexate 25 MG/ML Injection
    "1791598", # Phase 40: ifosfamide IV infusion
    "1946772", # Phase 40: methotrexate 25 MG/ML Injectable Solutio
    "3098", # Phase 40: dacarbazine
    "311627", # Phase 40: METHOTREXATE SODIUM (PF) 25 MG/ML  CUSTO
    "1734921", # Phase 40: cyclophosphamide 2000 MG Injection
    "2105", # Phase 40: carmustine
    "11198", # Phase 40: vinblastine
    "1114693", # Phase 40: bendamustine hydrochloride
    "105587", # Phase 40: methotrexate 2.5 MG Oral Tablet [Maxtrex
    "1544390", # Phase 40: 0.35 ML methotrexate 50 MG/ML Auto-Injec
    "1726673", # Phase 40: bleomycin 15 UNT Injection
    "1790099", # Phase 40: 10 ML doxorubicin hydrochloride 2 MG/ML
    "1734919", # Phase 40: cyclophosphamide 1000 MG Injection
    "894900", # Phase 40: VINCRISTINE SULFATE 1 MG/ML IV CUSTOM CO
    "637543", # Phase 40: CYCLOPHOSPHAMIDE  CUSTOM COMPONENT IJ SO
    "314167", # Phase 40: procarbazine 50 MG Oral Capsule
    "1734340", # Phase 40: etoposide 100 MG Injection
    "1863349", # Phase 40: vinCRIStine
    "1791593", # Phase 40: ifosfamide 1000 MG Injection
    "2568661", # Phase 40: 5 ML cyclophosphamide 200 MG/ML Injectio
    "1541215", # Phase 40: Methotrexate Sodium 2.5 MG Oral Tablet
    "5657", # Phase 40: ifosfamide
    "1791588", # Phase 40: ifosfamide 3000 MG Injection
    "1790097", # Phase 40: 5 ML doxorubicin hydrochloride 2 MG/ML I
    "1805001", # Phase 40: bendamustine hydrochloride 100 MG Inject
    "1790127", # Phase 40: 25 ML doxorubicin hydrochloride liposome
    "1191138", # Phase 40: doxorubicin hydrochloride 2 MG/ML Inject
    "1731338", # Phase 40: dacarbazine 200 MG Injection
    "1791597", # Phase 40: 60 ML ifosfamide 50 MG/ML Injection
    "1719000", # Phase 40: gemcitabine 200 MG Injection
    "1799307", # Phase 40: DOXOrubicin  IV infusion,
    "1726097", # Phase 40: bendamustine hydrochloride 25 MG/ML Inje
    "1790103", # Phase 40: doxorubicin hydrochloride 10 MG Injectio
    "1655956", # Phase 40: 40 ML methotrexate 25 MG/ML Injection
    "1437713", # Phase 40: mechlorethamine 0.00016 MG/MG Topical Ge
    "11202", # Phase 40: vincristine
    "6851", # Phase 40: methotrexate
    "1655968", # Phase 40: 8 ML methotrexate 25 MG/ML Injection
    "1544398", # Phase 40: 0.5 ML methotrexate 50 MG/ML Auto-Inject
    "309311", # Phase 40: cisplatin 1 MG/ML Injectable Solution
    "1734917", # Phase 40: cyclophosphamide 500 MG Injection
    "310973", # Phase 40: IFOSFAMIDE 3 G IV SOLR CUSTOM COMPONENT
    "283510", # Phase 40: methotrexate 15 MG Oral Tablet
    "1544388", # Phase 40: 0.3 ML methotrexate 50 MG/ML Auto-Inject
    "1863355", # Phase 40: 2 ML vincristine sulfate 1 MG/ML Injecti
    "1719003", # Phase 40: gemcitabine 1000 MG Injection
    "1726102", # Phase 40: bendamustine hydrochloride 25 MG/ML Inje
    "597195", # Phase 40: carboplatin 10 MG/ML Injectable Solution
    "206831", # Phase 40: etoposide 20 MG/ML Injectable Solution [
    "197687", # Phase 40: etoposide 50 MG Oral Capsule
    "4179", # Phase 40: etoposide
    "309638", # Phase 40: DACARBAZINE 200 MG IV CUSTOM COMPONENT
    "1720975", # Phase 40: 52.6 ML gemcitabine 38 MG/ML Injection
    "1719013", # Phase 40: gemcitabine IV infusion
    "205821", # Phase 40: CISplatin IV infusion
    "1790100", # Phase 40: 25 ML doxorubicin hydrochloride 2 MG/ML
    "686161", # Phase 40: carboplatin 10 MG/ML Injectable Solution
    "1863347", # Phase 40: 1 ML vincristine sulfate 1 MG/ML Injecti
    "1731340", # Phase 40: dacarbazine 100 MG Injection
    "1655959", # Phase 40: 10 ML methotrexate 25 MG/ML Injection
    "1437969", # Phase 40: cyclophosphamide 50 MG Oral Capsule
    "1622", # Phase 40: bleomycin
    "105604", # Phase 40: procarbazine 50 MG Oral Capsule [Natulan
    "310248", # Phase 40: etoposide 20 MG/ML Injectable Solution
    "1863343", # Phase 40: 1 ML vincristine sulfate 1 MG/ML Injecti
    "226719", # Phase 40: etoposide 100 MG Injection [Etopophos]
    "1998783", # Phase 40: gemcitabine 100 MG/ML Injectable Solutio
    "1790098", # Phase 40: DOXOrubicin  IV infusion,
    "2555", # Phase 40: cisplatin
    "105586", # Phase 40: methotrexate 10 MG Oral Tablet
    "1921592", # Phase 40: methotrexate 2.5 MG/ML Oral Solution
    "2001102", # Phase 40: ADRIAMYCIN IV
    "309012", # Phase 40: carmustine 100 MG Injection
    "287734", # Phase 40: methotrexate sodium
    "308770", # Phase 40: Bleomycin Sulfate For Inj 30 Unit
    "8702", # Phase 40: procarbazine
    "3002", # Phase 40: cyclophosphamide
    "311625", # Phase 40: methotrexate 1000 MG Injection
    "1790129", # Phase 40: doxorubicin hydrochloride liposome 2 MG/
    "308771", # Phase 40: Bleomycin Sulfate For Inj 30 Unit
    "1726676", # Phase 40: bleomycin 30 UNT Injection
    "197550", # Phase 40: cyclophosphamide 50 MG Oral Tablet
    "1441411", # Phase 40: 0.4 ML methotrexate 37.5 MG/ML Auto-Inje
    "283511" # Phase 40: methotrexate 5 MG Oral Tablet
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
    "77261", # Therapeutic radiology treatment planning; simple
    "77262", # Therapeutic radiology treatment planning; intermediate
    "77263", # Therapeutic radiology treatment planning; complex
    "77280", # Therapeutic radiology simulation-aided field setting; simple
    "77285", # Therapeutic radiology simulation-aided field setting; intermediate
    "77290", # Therapeutic radiology simulation-aided field setting; complex
    "77293", # Respiratory motion management simulation

    # --- Physics, Dosimetry & Treatment Devices (77295-77370) ---
    "77295", # 3-dimensional radiotherapy plan, including dose-volume histograms
    "77300", # Basic radiation dosimetry calculation
    "77301", # Intensity modulated radiotherapy plan (IMRT)
    "77306", # Teletherapy isodose plan; simple
    "77307", # Teletherapy isodose plan; complex
    "77310", # Teletherapy isodose plan; brachytherapy isodose calc, simple (DELETED)
    "77315", # Teletherapy isodose plan; brachytherapy isodose calc, complex (DELETED)
    "77316", # Brachytherapy isodose plan; simple
    "77318", # Brachytherapy isodose plan; complex
    "77321", # Special teletherapy port plan
    "77331", # Special dosimetry (TLD, calorimetry, etc.)
    "77332", # Treatment devices, simple
    "77333", # Treatment devices, intermediate
    "77334", # Treatment devices, complex
    "77336", # Continuing medical physics consultation
    "77338", # Multi-leaf collimator (MLC) device design and fabrication
    "77370", # Special medical radiation physics consultation

    # --- Treatment Delivery (77371-77499) ---
    "77371", # SRS, multi-source Gamma Knife (DELETED 2026)
    "77372", # SRS, linear accelerator based (DELETED 2026)
    "77373", # Stereotactic body radiation therapy (SBRT), treatment delivery
    "77385", # IMRT delivery, simple
    "77386", # IMRT delivery, complex
    "77387", # Guidance for radiation treatment delivery (IGRT)
    "77399", # Unlisted procedure, radiation treatment delivery
    "77401", # External beam radiation delivery, surface/orthovoltage (DELETED 2026; historical claims only)
    "77402", # Radiation treatment delivery, intermediate (2026 new code)
    "77404", # Radiation treatment delivery; single area, 6-10 MeV (DELETED 2015)
    "77407", # Radiation treatment delivery, simple (2026 new code)
    "77408", # Radiation treatment delivery; 2 separate areas, 3+ ports, 6-10 MeV (DELETED 2015)
    "77412", # Radiation treatment delivery, complex (2026 new code)
    "77413", # Radiation treatment delivery; 3+ areas, custom blocking, 6-10 MeV (DELETED 2015)
    "77414", # Radiation treatment delivery; 3+ areas, custom blocking, 11-19 MeV (DELETED 2015)
    "77416", # Radiation treatment delivery; 3+ areas, complex, 20+ MeV (DELETED 2015)
    "77417", # Port film(s) per treatment session (portal imaging) (DELETED 2026)
    "77418", # Radiation treatment delivery, IMRT (intensity modulated) (DELETED 2015)
    "77421", # Stereoscopic x-ray guidance for target localization (DELETED 2015)
    "77427", # Radiation treatment management (weekly, per 5 fractions) - most common
    "77431", # Radiation treatment management, 1-4 treatments (end-of-course)
    "77432", # Stereotactic radiation treatment management of cranial lesion
    "77435", # Stereotactic body radiation therapy (SBRT) management
    "77470", # Special treatment procedure (total body irradiation, hemibody irradiation)

    # --- Proton Beam Treatment Delivery (77520-77525) ---
    "77520", # Proton treatment delivery; simple, without compensation
    "77522", # Proton treatment delivery; simple, with compensation
    "77523", # Proton treatment delivery; intermediate
    "77525", # Proton treatment delivery; complex

    # --- Hyperthermia (77600-77620) ---
    "77605", # Hyperthermia, externally generated; deep (DELETED)

    # --- Brachytherapy (77750-77799) ---
    "77750", # Infusion or instillation of radioelement solution
    "77763", # Interstitial radiation source application; complex
    "77768", # Intracavitary radiation source application; complex
    "77770", # Remote afterloading high dose rate brachytherapy; 1 channel
    "77771", # Remote afterloading high dose rate brachytherapy; 2-12 channels
    "77772", # Remote afterloading high dose rate brachytherapy; over 12 channels
    "77785", # Remote afterloading brachytherapy; 1-4 sources/ribbons, complex (DELETED)

    # --- CMS G-codes: Radiation Delivery (DELETED 2026) ---
    "G6012", # Radiation treatment delivery, 3D conformal, intermediate (DELETED 2026)
    "G6013", # Radiation treatment delivery, 3D conformal, complex (DELETED 2026)
    "G6015" # Radiation treatment delivery, IMRT, complex (DELETED 2026)
  ),

  # Stem cell transplant CPT codes (autologous + allogeneic per D-07)
  sct_cpt = c(
    "38230", # Bone marrow harvesting (Python pipeline)
    "38232", # Bone marrow harvesting (Python pipeline)
    "38240", # Allogeneic HPC transplantation
    "38241", # Autologous HPC transplantation
    "38242", # Allogeneic donor lymphocyte infusion (DLI)
    "38243" # Allogeneic HPC boost
  ),

  # Stem cell transplant HCPCS codes (Phase 10: added from VariableDetails.xlsx)
  sct_hcpcs = c(
    "S2140", # Cord blood harvesting for transplantation, allogeneic
    "S2142", # Cord blood-derived stem-cell transplantation, allogeneic
    "S2150" # Bone marrow or blood-derived stem cells; allogeneic or autologous
  ),

  # --- ICD Procedure Codes (D-02, D-04: all PX_TYPE values) ---

  # Chemotherapy ICD-9-CM Volume 3 (PX_TYPE = "09")
  chemo_icd9 = c(
    "99.25", # Injection or infusion of cancer chemotherapeutic substance
    "99.28" # Injection or infusion of immunotherapy (D-07)
  ),

  # Chemotherapy ICD-10-PCS (PX_TYPE = "10")
  # Section 3 Administration, Root Operation Introduction, Qualifier 5 = Antineoplastic
  # Prefix-matched in 10_treatment_payer.R via str_starts() -- store prefixes only
  chemo_icd10pcs_prefixes = c(
    "3E00X05", # Antineoplastic into skin/mucous membranes, external approach
    "3E01305", # Antineoplastic into subcutaneous tissue, percutaneous
    "3E0130M", # Monoclonal antibody antineoplastic into subcutaneous tissue, percutaneous
    "3E02305", # Antineoplastic into muscle, percutaneous
    "3E03005", # Antineoplastic into peripheral vein, open
    "3E03305", # Antineoplastic into peripheral vein, percutaneous
    "3E0330M", # Monoclonal antibody antineoplastic into peripheral vein, percutaneous
    "3E04005", # Antineoplastic into central vein, open
    "3E04305", # Antineoplastic into central vein, percutaneous
    "3E0430M", # Monoclonal antibody antineoplastic into central vein, percutaneous
    "3E05305", # Antineoplastic into peripheral artery, percutaneous
    "3E0530M", # Monoclonal antibody antineoplastic into peripheral artery, percutaneous
    "3E06305", # Antineoplastic into central artery, percutaneous
    "3E0630M", # Monoclonal antibody antineoplastic into central artery, percutaneous
    "3E0D705", # Antineoplastic into mouth/pharynx, via natural opening
    "3E0G305", # Antineoplastic into upper GI, percutaneous
    "3E0L305", # Antineoplastic into pleural cavity, percutaneous
    "3E0Q305", # Antineoplastic into cranial/peripheral nerves, percutaneous
    "3E0R305", # Antineoplastic into spinal canal, percutaneous (intrathecal chemo)
    "3E0R30M", # Monoclonal antibody antineoplastic into spinal canal, percutaneous
    "3E0S305", # Antineoplastic into epidural space, percutaneous
    "3E0W305", # Antineoplastic into lymphatics, percutaneous
    "3E0W30M" # Monoclonal antibody antineoplastic into lymphatics, percutaneous
  ),

  # Radiation therapy ICD-9-CM Volume 3 (PX_TYPE = "09")
  radiation_icd9 = c(
    "92.20", # Infusion of liquid brachytherapy radioisotope
    "92.21", # Superficial radiation
    "92.22", # Orthovoltage radiation
    "92.23", # Radioisotopic teleradiotherapy
    "92.24", # Teleradiotherapy using photons
    "92.25", # Teleradiotherapy using electrons
    "92.26", # Teleradiotherapy of other particulate radiation
    "92.27", # Implantation or insertion of radioactive elements
    "92.29", # Other radiotherapeutic procedure
    "92.30", # Stereotactic radiosurgery, NOS
    "92.31", # Single source photon radiosurgery
    "92.32", # Multi-source photon radiosurgery (Gamma Knife)
    "92.33", # Particulate radiosurgery
    "92.41" # Intra-operative electron radiation therapy (IERT)
  ),

  # Radiation therapy ICD-10-PCS prefixes (PX_TYPE = "10")
  # Section D Radiation Therapy, Body System 7 Lymphatic and Hematologic
  # Prefix-matched in 10_treatment_payer.R via str_starts()
  radiation_icd10pcs_prefixes = c(
    "D70", # Beam Radiation, lymphatic/hematologic
    "D71", # Brachytherapy, lymphatic/hematologic
    "D72", # Stereotactic Radiosurgery, lymphatic/hematologic
    "D7Y" # Other Radiation, lymphatic/hematologic
  ),

  # Stem cell transplant ICD-9-CM Volume 3 (PX_TYPE = "09")
  sct_icd9 = c(
    "41.00", # Bone marrow transplant, NOS
    "41.01", # Autologous bone marrow transplant without purging
    "41.02", # Allogeneic bone marrow transplant with purging
    "41.03", # Allogeneic bone marrow transplant without purging
    "41.04", # Autologous hematopoietic stem cell transplant without purging
    "41.05", # Allogeneic hematopoietic stem cell transplant without purging
    "41.06", # Cord blood stem cell transplant
    "41.07", # Autologous hematopoietic stem cell transplant with purging
    "41.08", # Allogeneic hematopoietic stem cell transplant with purging
    "41.09" # Autologous bone marrow transplant with purging
  ),

  # Stem cell transplant ICD-10-PCS (PX_TYPE = "10")
  # Section 3 Administration, Root Operation Transfusion, Substance = Hematopoietic Stem Cells
  # Phase 10: Expanded from VariableDetails.xlsx to include open approach (3023x/3024x),
  # allogeneic related/unrelated (G2/G3, U2/U3, X2/X3, Y2/Y3), and new technology (XW1xx) codes.
  # Nonautologous variants (G1, X1, Y1) retained from Phase 9 original list.
  sct_icd10pcs = c(
    # Open approach (0) -- added from VariableDetails.xlsx
    "30230C0", # Autologous HPC (genetically modified), peripheral vein, open
    "30230G0", # Autologous bone marrow, peripheral vein, open
    "30230X0", # Autologous cord blood stem cells, peripheral vein, open
    "30230Y0", # Autologous HPC, peripheral vein, open
    "30240C0", # Autologous HPC (genetically modified), central vein, open
    "30240G0", # Autologous bone marrow, central vein, open
    "30240X0", # Autologous cord blood stem cells, central vein, open
    "30240Y0", # Autologous HPC, central vein, open
    # Percutaneous approach (3) -- autologous
    "30233C0", # Autologous HPC (genetically modified), peripheral vein, percutaneous
    "30233G0", # Autologous HPC, peripheral vein, percutaneous
    "30233X0", # Autologous cord blood stem cells, peripheral vein, percutaneous
    "30233Y0", # Autologous HPC (other), peripheral vein, percutaneous
    "30243C0", # Autologous HPC (genetically modified), central vein, percutaneous
    "30243G0", # Autologous HPC, central vein, percutaneous
    "30243X0", # Autologous cord blood stem cells, central vein, percutaneous
    "30243Y0", # Autologous HPC (other), central vein, percutaneous
    # Percutaneous approach (3) -- nonautologous (from Phase 9 original list)
    "30233G1", # Nonautologous HPC, peripheral vein, percutaneous
    "30233X1", # Nonautologous cord blood stem cells, peripheral vein, percutaneous
    "30233Y1", # Nonautologous HPC (other), peripheral vein, percutaneous
    "30243G1", # Nonautologous HPC, central vein, percutaneous
    "30243X1", # Nonautologous cord blood stem cells, central vein, percutaneous
    "30243Y1", # Nonautologous HPC (other), central vein, percutaneous
    # Allogeneic related (2) and unrelated (3) -- added from VariableDetails.xlsx
    "30233G2", # Allogeneic related bone marrow, peripheral vein, percutaneous
    "30233G3", # Allogeneic unrelated bone marrow, peripheral vein, percutaneous
    "30233U2", # Allogeneic related T-cell depleted bone marrow, peripheral vein, percutaneous
    "30233U3", # Allogeneic unrelated T-cell depleted bone marrow, peripheral vein, percutaneous
    "30233X2", # Allogeneic related cord blood stem cells, peripheral vein, percutaneous
    "30233X3", # Allogeneic unrelated cord blood stem cells, peripheral vein, percutaneous
    "30233Y2", # Allogeneic related HPC, peripheral vein, percutaneous
    "30233Y3", # Allogeneic unrelated HPC, peripheral vein, percutaneous
    "30243G2", # Allogeneic related bone marrow, central vein, percutaneous
    "30243G3", # Allogeneic unrelated bone marrow, central vein, percutaneous
    "30243U2", # Allogeneic related T-cell depleted bone marrow, central vein, percutaneous
    "30243U3", # Allogeneic unrelated T-cell depleted bone marrow, central vein, percutaneous
    "30243X2", # Allogeneic related cord blood stem cells, central vein, percutaneous
    "30243X3", # Allogeneic unrelated cord blood stem cells, central vein, percutaneous
    "30243Y2", # Allogeneic related HPC, central vein, percutaneous
    "30243Y3", # Allogeneic unrelated HPC, central vein, percutaneous
    # Embryonic stem cells (added from VariableDetails.xlsx)
    "30230AZ", # Embryonic stem cells, peripheral vein, open
    "30233AZ", # Embryonic stem cells, peripheral vein, percutaneous
    "30240AZ", # Embryonic stem cells, central vein, open
    "30243AZ", # Embryonic stem cells, central vein, percutaneous
    # New technology (XW1xx) -- Omidubicel (added from VariableDetails.xlsx)
    "XW133C8", # Transfusion of Omidubicel into Peripheral Vein, Percutaneous Approach
    "XW143C8" # Transfusion of Omidubicel into Central Vein, Percutaneous Approach
  ),

  # CAR T-cell and other immunotherapies ICD-10-PCS (DRG 018)
  # Phase 10: Added from VariableDetails.xlsx (codes with * denote prefix patterns)
  # Prefix-matched in treatment scripts via str_starts()
  cart_icd10pcs_prefixes = c(
    "XW033C7", # Autologous engineered chimeric antigen receptor T-cell immunotherapy, peripheral vein
    "XW033G7", # Allogeneic engineered chimeric antigen receptor T-cell, peripheral vein
    "XW033H7", # Axicabtagene ciloleucel, peripheral vein
    "XW033J7", # Tisagenlecleucel immunotherapy, peripheral vein
    "XW033K7", # Idecabtagene vicleucel immunotherapy, peripheral vein
    "XW033L7", # Lifileucel immunotherapy, peripheral vein
    "XW033M7", # Brexucabtagene autoleucel, peripheral vein
    "XW033N7", # Lisocabtagene maraleucel, peripheral vein
    "XW043C7", # Autologous engineered chimeric antigen receptor T-cell, central vein
    "XW043G7", # Allogeneic engineered chimeric antigen receptor T-cell, central vein
    "XW043H7", # Axicabtagene ciloleucel, central vein
    "XW043J7", # Tisagenlecleucel immunotherapy, central vein
    "XW043K7", # Idecabtagene vicleucel immunotherapy, central vein
    "XW043L7", # Lifileucel immunotherapy, central vein
    "XW043M7", # Brexucabtagene autoleucel, central vein
    "XW043N7", # Lisocabtagene maraleucel, central vein
    "XW033A3", # Phase 39: no description
    "XW033B3", # Phase 39: no description
    "XW033C3", # Phase 39: no description
    "XW033C6", # Phase 39: no description
    "XW033D6", # Phase 39: no description
    "XW033E5", # Phase 39: no description
    "XW033H5", # Phase 39: no description
    "XW033H6", # Phase 39: no description
    "XW043A7", # Phase 39: no description
    "XW043B3", # Phase 39: no description
    "XW043C3", # Phase 39: no description
    "XW043C6", # Phase 39: no description
    "XW043E5", # Phase 39: no description
    "XW043H5", # Phase 39: no description
    "XW043P9" # Phase 39: no description
  ),

  # --- Phase 9: Expanded detection codes (D-09, D-10, D-11) ---

  # Diagnosis-based treatment evidence (ICD-10-CM Z/T codes, ICD-9-CM V codes)
  chemo_dx_icd10 = c(
    "Z51.11" # Encounter for antineoplastic chemotherapy
  ),
  chemo_dx_icd9 = c(
    "V58.11" # Encounter for antineoplastic chemotherapy
  ),
  immunotherapy_dx_icd10 = c(
    "Z51.12" # Encounter for antineoplastic immunotherapy
  ),
  immunotherapy_dx_icd9 = c(
    "V58.12" # Encounter for antineoplastic immunotherapy
  ),
  radiation_dx_icd10 = c(
    "Z51.0" # Encounter for antineoplastic radiation therapy
  ),
  radiation_dx_icd9 = c(
    "V58.0" # Encounter for radiotherapy
  ),

  # MS-DRG treatment evidence (ENCOUNTER table DRG column)
  chemo_drg = c(
    "837", # Chemo w/o acute leukemia as SDx w MCC
    "838", # Chemo w/o acute leukemia as SDx w CC
    "839", # Chemo w/o acute leukemia as SDx w/o CC/MCC
    "846", # Chemo w hematologic malignancy as SDx w MCC
    "847", # Chemo w hematologic malignancy as SDx w CC
    "848" # Chemo w hematologic malignancy as SDx w/o CC/MCC
  ),
  radiation_drg = c(
    "849" # Radiotherapy
  ),
  sct_drg = c(
    "014", # Allogeneic bone marrow transplant
    "016", # Autologous BMT w CC/MCC or T-cell immunotherapy
    "017" # Autologous BMT w/o CC/MCC
    # NOTE: DRG 015 deleted FY2012, omitted per research pitfall 4
  ),
  immunotherapy_drg = c(
    "018" # Chimeric Antigen Receptor (CAR) T-cell Immunotherapy
  ),

  # Revenue codes (PROCEDURES table PX_TYPE = "RE")

  # Supportive Care RXNORM codes (Phase 40: drug investigation)
  supportive_care_rxnorm = c(
    "1812194", # Phase 40: 1 ML dexamethasone phosphate 4 MG/ML Inj
    "2057212", # Phase 40: 1 ML filgrastim-aafi 0.3 MG/ML Injection
    "197582", # Phase 40: dexamethasone 4 MG Oral Tablet
    "731181", # Phase 40: 0.4 ML darbepoetin alfa 0.1 MG/ML Prefil
    "338036", # Phase 40: pegfilgrastim
    "403886", # Phase 40: Palonosetron HCl IV Soln 0.25 MG/5ML (Ba
    "240912", # Phase 40: granisetron 1 MG/ML Injectable Solution
    "404465", # Phase 40: aprepitant 80 MG Oral Capsule [Emend]
    "29225", # Phase 40: Ondansetron HCl - 8 MG Oral Tablet
    "1728055", # Phase 40: 5 ML palonosetron 0.05 MG/ML Injection
    "2048025", # Phase 40: 0.6 ML pegfilgrastim-jmdb 10 MG/ML Prefi
    "197577", # Phase 40: dexamethasone 0.5 MG Oral Tablet
    "343033", # Phase 40: dexamethasone 0.75 MG Oral Tablet
    "727544", # Phase 40: 0.8 ML filgrastim 0.6 MG/ML Prefilled Sy
    "2057218", # Phase 40: 1.6 ML filgrastim-aafi 0.3 MG/ML Injecti
    "283838", # Phase 40: darbepoetin alfa
    "2047621", # Phase 40: 1 ML epoetin alfa-epbx 40000 UNT/ML Inje
    "357280", # Phase 40: Emend
    "727537", # Phase 40: 0.5 ML filgrastim 0.6 MG/ML Prefilled Sy
    "1442681", # Phase 40: 0.5 ML tbo-filgrastim 0.6 MG/ML Prefille
    "1947301", # Phase 40: 2 ML palonosetron 0.125 MG/ML Injection
    "343040", # Phase 40: dexamethasone 0.75 MG Oral Tablet [Decad
    "312086", # Phase 40: ondansetron 8 MG Oral Tablet
    "2549331", # Phase 40: 0.6 ML pegfilgrastim 10 MG/ML Injection
    "1649963", # Phase 40: 1.6 ML filgrastim 0.3 MG/ML Injection
    "731184", # Phase 40: 1 ML darbepoetin alfa 0.5 MG/ML Prefille
    "998032", # Phase 40: ondansetron 8 MG Oral Film [Zuplenz]
    "6314", # Phase 40: dexAMETHasone Sodium Phosphate 10 MG/ML
    "731227", # Phase 40: 0.4 ML darbepoetin alfa 0.1 MG/ML Prefil
    "68442", # Phase 40: filgrastim
    "876690", # Phase 40: ondansetron 4 mg oral tablet, disintegra
    "105694", # Phase 40: epoetin alfa
    "309682", # Phase 40: dexamethasone 0.001 MG/MG / tobramycin 0
    "312085", # Phase 40: ondansetron 0.8 MG/ML Oral Solution
    "2057216", # Phase 40: 0.8 ML filgrastim-aafi 0.6 MG/ML Prefill
    "1995155", # Phase 40: 18 ML aprepitant 7.2 MG/ML Injection [Ci
    "240377", # Phase 40: 1 ML epoetin alfa 3000 UNT/ML Injection
    "1605075", # Phase 40: 0.8 ML filgrastim-sndz 0.6 MG/ML Prefill
    "105392", # Phase 40: dexamethasone 0.5 MG Oral Tablet [Decadr
    "70561", # Phase 40: palonosetron
    "1721690", # Phase 40: 1 ML epoetin alfa 10000 UNT/ML Injection
    "403810", # Phase 40: aprepitant 80 MG Oral Capsule
    "1731077", # Phase 40: fosaprepitant 150 MG Injection
    "1812095", # Phase 40: 1 ML dexamethasone phosphate 4 MG/ML Pre
    "239999", # Phase 40: 1 ML epoetin alfa 4000 UNT/ML Injection
    "727542", # Phase 40: 0.6 ML pegfilgrastim 10 MG/ML Prefilled
    "2057209", # Phase 40: 1 ML filgrastim-aafi 0.3 MG/ML Injection
    "26237", # Phase 40: granisetron
    "208591", # Phase 40: dexamethasone 1 MG/ML / neomycin 3.5 MG/
    "1731082", # Phase 40: fosaprepitant 150 MG Injection [Emend In
    "795716", # Phase 40: {12 (dexamethasone 0.75 MG Oral Tablet [
    "998035", # Phase 40: ondansetron 4 MG Oral Film [Zuplenz]
    "1728050", # Phase 40: 1.5 ML palonosetron 0.05 MG/ML Injection
    "283504", # Phase 40: ondansetron 2 MG/ML Injectable Solution
    "240449", # Phase 40: Filgrastim Inj 300 MCG/ML
    "727545", # Phase 40: 0.8 ML filgrastim 0.6 MG/ML Prefilled Sy
    "1734399", # Phase 40: 1 ML granisetron 1 MG/ML Injection
    "197583", # Phase 40: dexamethasone 6 MG Oral Tablet
    "310599", # Phase 40: granisetron 1 MG Oral Tablet
    "792710", # Phase 40: Epoetin Alfa Inj 10000 Unit/ML
    "2549333", # Phase 40: 0.6 ML pegfilgrastim 10 MG/ML Injection
    "2463735", # Phase 40: epoetin alfa-epbx 20000 UNT/ML Injectabl
    "644278", # Phase 40: aprepitant 40 MG Oral Capsule [Emend]
    "213475", # Phase 40: 1 ML epoetin alfa 40000 UNT/ML Injection
    "2056929", # Phase 40: 5 ML palonosetron 0.05 MG/ML Prefilled S
    "208588", # Phase 40: dexamethasone 1 MG/ML / neomycin 3.5 MG/
    "104897", # Phase 40: ondansetron injection
    "731174", # Phase 40: 0.4 ML darbepoetin alfa 0.5 MG/ML Prefil
    "1605071", # Phase 40: 0.5 ML filgrastim-sndz 0.6 MG/ML Prefill
    "1649946", # Phase 40: 1 ML filgrastim 0.3 MG/ML Injection [Neu
    "1998482", # Phase 40: {21 (dexamethasone 1.5 MG Oral Tablet) }
    "309679", # Phase 40: dexamethasone 0.001 MG/MG / neomycin 0.0
    "2048020", # Phase 40: 0.6 ML pegfilgrastim-jmdb 10 MG/ML Prefi
    "197579", # Phase 40: dexamethasone 1 MG Oral Tablet
    "2102705", # Phase 40: 0.6 ML pegfilgrastim-cbqv 10 MG/ML Prefi
    "1442683", # Phase 40: 0.8 ML tbo-filgrastim 0.6 MG/ML Prefille
    "2595961", # Phase 40: 0.8 ML filgrastim-ayow 0.6 MG/ML Prefill
    "239998", # Phase 40: 1 ML epoetin alfa 2000 UNT/ML Injection
    "825005", # Phase 40: 168 HR granisetron 0.129 MG/HR Transderm
    "2260704", # Phase 40: 0.6 ML pegfilgrastim-bmez 10 MG/ML Prefi
    "208601", # Phase 40: dexamethasone 0.001 MG/MG / neomycin 0.0
    "197580", # Phase 40: dexamethasone 1.5 MG Oral Tablet
    "208602", # Phase 40: dexamethasone 0.001 MG/MG / neomycin 0.0
    "349274", # Phase 40: 1 ML darbepoetin alfa 0.04 MG/ML Injecti
    "2260709", # Phase 40: 0.6 ML pegfilgrastim-bmez 10 MG/ML Prefi
    "64695", # Phase 40: Ondansetron 4 MG Oral Tablet Disintegrat
    "754508", # Phase 40: {1 (aprepitant 125 MG Oral Capsule) / 2
    "1649944", # Phase 40: 1 ML filgrastim 0.3 MG/ML Injection
    "2047600", # Phase 40: 1 ML epoetin alfa-epbx 2000 UNT/ML Injec
    "26225", # Phase 40: ondansetron
    "2469340", # Phase 40: 0.6 ML pegfilgrastim-apgf 10 MG/ML Prefi
    "2047612", # Phase 40: 1 ML epoetin alfa-epbx 4000 UNT/ML Injec
    "731176", # Phase 40: 0.42 ML darbepoetin alfa 0.06 MG/ML Pref
    "901649", # Phase 40: dexamethasone 0.1 MG/ML Oral Solution [B
    "1740467", # Phase 40: 2 ML ondansetron 2 MG/ML Injection
    "104896", # Phase 40: ondansetron
    "104894", # Phase 40: ondansetron 4 MG Disintegrating Oral Tab
    "309683", # Phase 40: dexamethasone 1 MG/ML / tobramycin 3 MG/
    "759696", # Phase 40: {12 (dexamethasone 0.75 MG Oral Tablet)
    "205717", # Phase 40: dexamethasone 6 MG Oral Tablet [Decadron
    "2057205", # Phase 40: 0.5 ML filgrastim-aafi 0.6 MG/ML Prefill
    "403811", # Phase 40: aprepitant 125 MG Oral Capsule
    "205712", # Phase 40: dexamethasone 4 MG Oral Tablet [Decadron
    "1605066", # Phase 40: 0.5 ML filgrastim-sndz 0.6 MG/ML Prefill
    "876693", # Phase 40: ondansetron
    "1721684", # Phase 40: 1 ML epoetin alfa 10000 UNT/ML Injection
    "2048018", # Phase 40: pegfilgrastim-jmdb
    "1433771", # Phase 40: 0.8 ML tbo-filgrastim 0.6 MG/ML Prefille
    "1812079", # Phase 40: 1 ML dexamethasone phosphate 10 MG/ML In
    "730044", # Phase 40: 0.5 ML darbepoetin alfa 0.2 MG/ML Prefil
    "2463731", # Phase 40: epoetin alfa-epbx 10000 UNT/ML Injectabl
    "212447", # Phase 40: ondansetron
    "205669", # Phase 40: dexamethasone 1 MG/ML Ophthalmic Suspens
    "241999", # Phase 40: epoetin alfa 20000 UNT/ML Injectable Sol
    "2047606", # Phase 40: 1 ML epoetin alfa-epbx 3000 UNT/ML Injec
    "1605064", # Phase 40: filgrastim-sndz
    "759697", # Phase 40: {35 (dexamethasone 1.5 MG Oral Tablet) }
    "1314133", # Phase 40: 2 ML ondansetron 2 MG/ML Prefilled Syrin
    "731179", # Phase 40: 0.6 ML darbepoetin alfa 0.5 MG/ML Prefil
    "358255", # Phase 40: aprepitant
    "1605074", # Phase 40: 0.8 ML filgrastim-sndz 0.6 MG/ML Prefill
    "403908", # Phase 40: ciprofloxacin 3 MG/ML / dexamethasone 1
    "242706", # Phase 40: 1 ML epoetin alfa 40000 UNT/ML Injection
    "2261802", # Phase 40: dexamethasone 20 MG Oral Tablet
    "644088", # Phase 40: aprepitant 40 MG Oral Capsule
    "313947", # Phase 40: Neomycin-Polymyxin-Dexamethasone Ophth O
    "2057200", # Phase 40: 0.5 ML filgrastim-aafi 0.6 MG/ML Prefill
    "404466", # Phase 40: aprepitant 125 MG Oral Capsule [Emend]
    "755976", # Phase 40: dexamethasone 0.1 MG/ML Oral Solution [D
    "2047623", # Phase 40: 1 ML epoetin alfa-epbx 40000 UNT/ML Inje
    "205913", # Phase 40: epoetin alfa 10000 UNT/ML Injectable Sol
    "6316", # Phase 40: dexAMETHasone Sodium Phosphate 4 MG/ML I
    "998033", # Phase 40: ondansetron 4 MG Oral Film
    "312087", # Phase 40: ondansetron 8 MG Disintegrating Oral Tab
    "727535", # Phase 40: 0.5 ML filgrastim 0.6 MG/ML Prefilled Sy
    "404630", # Phase 40: ciprofloxacin 3 MG/ML / dexamethasone 1
    "1490065", # Phase 40: raloxifene hydrochloride 60 MG Oral Tabl
    "1649964", # Phase 40: 1.6 ML filgrastim 0.3 MG/ML Injection [N
    "309696", # Phase 40: dexamethasone phosphate 10 MG/ML Injecta
    "3264", # Phase 40: dexamethasone
    "198052", # Phase 40: ondansetron 4 MG Oral Tablet
    "309680", # Phase 40: dexamethasone 1 MG/ML / neomycin 3.5 MG/
    "1728052", # Phase 40: palonosetron injection
    "731167", # Phase 40: 0.3 ML darbepoetin alfa 0.2 MG/ML Prefil
    "825003", # Phase 40: 168 HR granisetron 0.129 MG/HR Transderm
    "349275", # Phase 40: 1 ML darbepoetin alfa 0.06 MG/ML Injecti
    "2047591", # Phase 40: 1 ML epoetin alfa-epbx 10000 UNT/ML Inje
    "1116927", # Phase 40: dexamethasone phosphate 4 MG/ML Injectab
    "309686", # Phase 40: dexamethasone 0.1 MG/ML Oral Solution
    "309692", # Phase 40: dexamethasone 1 MG/ML Ophthalmic Suspens
    "240000", # Phase 40: epoetin alfa 10000 UNT/ML Injectable Sol
    "847225", # Phase 40: {21 (dexamethasone 1.5 MG Oral Tablet) }
    "2469335", # Phase 40: 0.6 ML pegfilgrastim-apgf 10 MG/ML Prefi
    "208813", # Phase 40: dexamethasone 1 MG/ML / tobramycin 3 MG/
    "1995150", # Phase 40: 18 ML aprepitant 7.2 MG/ML Injection
    "349273", # Phase 40: 1 ML darbepoetin alfa 0.025 MG/ML Inject
    "1998481", # Phase 40: {49 (dexamethasone 1.5 MG Oral Tablet) }
    "226343", # Phase 40: dexamethasone phosphate 1 MG/ML Ophthalm
    "309698", # Phase 40: Dexamethasone Sodium Phosphate Inj 4 MG/
    "197581", # Phase 40: dexamethasone 2 MG Oral Tablet
    "104895", # Phase 40: Zofran 4 mg oral tablet
    "309684", # Phase 40: dexamethasone 1 MG/ML Oral Solution
    "2102703", # Phase 40: 0.6 ML pegfilgrastim-cbqv 10 MG/ML Prefi
    "727539", # Phase 40: 0.6 ML pegfilgrastim 10 MG/ML Prefilled
    "2101459", # Phase 40: 1 ML tbo-filgrastim 0.3 MG/ML Injection
    "2469333", # Phase 40: pegfilgrastim-apgf
    "2057215", # Phase 40: 0.8 ML filgrastim-aafi 0.6 MG/ML Prefill
    "754509", # Phase 40: {1 (aprepitant 125 MG Oral Capsule [Emen
    "1433768", # Phase 40: 0.5 ML tbo-filgrastim 0.6 MG/ML Prefille
    "849115", # Phase 40: dexamethasone 0.5 MG/ML / tobramycin 3 M
    "2101456" # Phase 40: 1 ML tbo-filgrastim 0.3 MG/ML Injection
  ),


  # Immunotherapy HCPCS J-codes (moved from chemo_hcpcs)
  immunotherapy_hcpcs = c(
    "J9022", # Atezolizumab (anti-PD-L1)
    "J9042", # Brentuximab vedotin (anti-CD30 ADC)
    "J9119", # Cemiplimab (anti-PD-1)
    "J9173", # Durvalumab (anti-PD-L1)
    "J9204", # Mogamulizumab (anti-CCR4)
    "J9228", # Ipilimumab (anti-CTLA-4)
    "J9268", # Pembrolizumab (anti-PD-1)
    "J9271", # Pembrolizumab IV (anti-PD-1)
    "J9299"  # Nivolumab (anti-PD-1)
  ),

  # Immunotherapy RXNORM codes (Phase 40: drug investigation + moved from chemo_rxnorm)
  immunotherapy_rxnorm = c(
    "1094836", # Phase 40: ipilimumab 5 MG/ML Injectable Solution
    "891815", # Phase 40: ascorbic acid 113 MG / beta carotene 716
    "891790", # Phase 40: ascorbic acid 226 MG / beta carotene 143
    "1919507", # Phase 40: 2.4 ML durvalumab 50 MG/ML Injection
    "1090823", # Phase 40: ascorbic acid / beta carotene / copper s
    "1313925", # Phase 40: alpha-tocopherol acetate 30 UNT / ascorb
    "1248142", # Phase 40: ascorbic acid 120 MG / beta carotene 270
    "891716", # Phase 40: ascorbic acid 200 MG / beta carotene 100
    "2479140", # Phase 40: 4.6 ML lisocabtagene maraleucel 70000000
    "1792780", # Phase 40: 20 ML atezolizumab 60 MG/ML Injection
    "1090824", # Phase 40: ascorbic acid 60 MG / beta carotene 5000
    "891793", # Phase 40: ascorbic acid 226 MG / beta carotene 143
    # Moved from chemo_rxnorm (checkpoint inhibitors + ADCs)
    "1147320", # Brentuximab vedotin (anti-CD30 ADC)
    "1147323", # Brentuximab vedotin 50 MG Injection
    "1147324", # Brentuximab vedotin (Adcetris)
    "1147327", # Brentuximab vedotin 50 MG Injection [Adcetris]
    "1597876", # Nivolumab (anti-PD-1)
    "1657190", # Nivolumab 10 MG/ML Injection
    "1657192", # Nivolumab 10 MG/ML Injection [Opdivo]
    "1657193", # Nivolumab
    "1657195", # Nivolumab 10 MG/ML Injection
    "1657196", # Nivolumab 10 MG/ML Injection [Opdivo]
    "1657749", # Pembrolizumab 50 MG Injection [Keytruda]
    "1657750", # Pembrolizumab 25 MG/ML Injection
    "1657751", # Pembrolizumab 25 MG/ML Injection [Keytruda]
    "1991412", # Nivolumab 10 MG/ML Injection
    "1991413"  # Nivolumab 10 MG/ML Injection [Opdivo]
  ),


  # SCT-related RXNORM codes (Phase 40: drug investigation)
  sct_rxnorm = c(
    "1740865", # Phase 40: 2 ML fludarabine phosphate 25 MG/ML Inje
    "253113", # Phase 40: 10 ML busulfan 6 MG/ML Injection
    "1660004", # Phase 40: thiotepa 100 MG Injection
    "284425", # Phase 40: 10 ML busulfan 6 MG/ML Injection [Busulf
    "197919", # Phase 40: melphalan 2 MG Oral Tablet
    "876399", # Phase 40: melphalan 50 MG Injection [Alkeran]
    "1740864", # Phase 40: fludarabine phosphate 50 MG Injection
    "311487" # Phase 40: melphalan 50 MG Injection
  ),
  chemo_revenue = c(
    "0331", # Chemo - injected
    "0332", # Chemo - oral
    "0335" # Chemo - IV push
  ),
  radiation_revenue = c(
    "0330", # General classification (therapeutic radiology)
    "0333" # Radiation therapy
  ),
  sct_revenue = c(
    "0362", # Organ transplant - other than kidney (includes SCT)
    "0815" # Allogeneic stem cell acquisition/donor services
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
    "77063", # Bilateral screening mammogram with tomosynthesis (screening)
    "77067", # Bilateral screening mammogram with tomosynthesis (variant)
    "77062", # Bilateral diagnostic mammogram with tomosynthesis
    "77066", # Bilateral diagnostic mammogram with tomosynthesis (variant)
    "77061", # Unilateral diagnostic mammogram with tomosynthesis
    "77065", # Unilateral diagnostic mammogram with tomosynthesis (variant)
    "G0279" # HCPCS: Diagnostic tomosynthesis mammogram (Medicare benefit)
  ),
  mammogram_icd10pcs = c(
    "BH00ZZZ", # Plain Radiography of Right Breast
    "BH01ZZZ", # Plain Radiography of Left Breast
    "BH02ZZZ" # Plain Radiography of Bilateral Breasts
  ),

  # Breast MRI
  breast_mri_cpt = c(
    "77046", # MRI breast without contrast, unilateral
    "77048", # MRI breast without and with contrast, unilateral
    "77047", # MRI breast without contrast, bilateral
    "77049" # MRI breast without and with contrast, bilateral
  ),
  breast_mri_hcpcs = c(
    "C8903", # MRI breast without contrast, unilateral
    "C8905", # MRI breast without and with contrast, unilateral
    "C8906", # MRI breast without contrast, bilateral
    "C8908" # MRI breast without and with contrast, bilateral
  ),
  breast_mri_icd10pcs = c(
    "BH30ZZZ", # MRI of Right Breast without contrast
    "BH31ZZZ", # MRI of Left Breast without contrast
    "BH32ZZZ", # MRI of Bilateral Breasts without contrast
    "BH30Y0Z", # MRI of Right Breast with other contrast
    "BH31Y0Z", # MRI of Left Breast with other contrast
    "BH32Y0Z" # MRI of Bilateral Breasts with other contrast
  ),

  # Echocardiogram
  echo_cpt = c(
    "93306", # Echocardiography, complete with doppler and color flow
    "93307", # Echocardiography, complete without doppler
    "93308", # Echocardiography, limited or follow-up
    "93350", # Stress echocardiography (exercise or pharmacological)
    "93351", # Stress echocardiography with contrast
    "93352" # Stress echocardiography, additional contrast (add-on)
  ),
  echo_icd10pcs = c(
    "X2JAX47" # Measurement of Cardiac Output using Echocardiography, New Technology
  ),
  echo_icd10_dx = c(
    "Z13.6" # Encounter for screening for cardiovascular disorders
  ),

  # Stress test (nuclear cardiology)
  stress_test_cpt = c(
    "78451", # Myocardial perfusion imaging, SPECT, single study at rest or stress
    "78452" # Myocardial perfusion imaging, SPECT, multiple studies at rest and stress
  ),

  # Electrocardiogram
  ecg_cpt = c(
    "93000", # Electrocardiogram, routine ECG with 12 leads; with interpretation and report
    "93005", # Electrocardiogram, routine ECG, tracing only
    "93010", # Electrocardiogram, routine ECG, interpretation and report only
    "93015", # Cardiovascular stress test with ECG monitoring and supervision
    "93016", # Cardiovascular stress test, physician supervision only
    "93017", # Cardiovascular stress test, tracing only
    "93018", # Cardiovascular stress test, interpretation and report only
    "93040", # Rhythm ECG, 1-3 leads; with interpretation and report
    "93041", # Rhythm ECG, 1-3 leads; tracing only
    "93042" # Rhythm ECG, 1-3 leads; interpretation and report only
  ),
  ecg_icd10_dx = c(
    "Z13.6" # Encounter for screening for cardiovascular disorders
  ),

  # MUGA (Multiple Gated Acquisition scan)
  muga_cpt = c(
    "78472", # Cardiac blood pool imaging, gated equilibrium, planar; single study at rest
    "78473", # Cardiac blood pool imaging, gated equilibrium, planar; multiple studies
    "78481", # Cardiac blood pool imaging, first pass technique; single study at rest
    "78483", # Cardiac blood pool imaging, first pass technique; multiple studies
    "78494", # Cardiac blood pool imaging, gated equilibrium, SPECT; single study
    "78496" # Cardiac blood pool imaging, gated equilibrium with wall motion study
  ),
  muga_icd10pcs = c(
    "C21G1ZZ", # Planar Nuclear Medicine Imaging of Heart using Technetium 99m
    "C22G1ZZ" # Tomographic Nuclear Medicine Imaging of Heart using Technetium 99m
  ),

  # Pulmonary function test
  pft_cpt = c(
    "94010", # Spirometry (FVC, FEV1, FEF)
    "94011", # Spirometry measurement, pediatric patients
    "94012", # Spirometry measurement, pediatric patients, minimum 2 curves
    "94060", # Spirometry with bronchodilator response
    "94070", # Bronchospasm provocation evaluation with multiple spirometric determinations
    "94150", # Vital capacity, total
    "94200", # Maximum breathing capacity (MVV or MBC)
    "94375", # Respiratory flow volume loop
    "94726", # Plethysmography for determination of lung volumes and airway resistance
    "94727", # Gas dilution techniques for determination of lung volumes
    "94729" # Diffusing capacity (DLCO)
  ),
  pft_icd10_dx = c(
    "Z13.83" # Encounter for screening for respiratory disorder NEC
  ),

  # Thyroid stimulating hormone (TSH)
  tsh_cpt = c(
    "84443" # Thyroid stimulating hormone (TSH) assay
  ),
  tsh_hcpcs = c(
    "224576" # TSH lab test (Medicare clinical lab code)
  ),
  tsh_loinc = c(
    "11580-8", # Thyrotropin [Units/volume] in Serum or Plasma
    "3024-7" # Thyrotropin [Units/volume] in Serum or Plasma (variant)
  ),

  # Complete blood count (CBC)
  cbc_cpt = c(
    "85025", # Blood count; complete (CBC), automated (Hgb, Hct, RBC, WBC and platelet count)
    "85027" # Blood count; complete (CBC), automated (RBC, WBC, Hgb, Hct, MCV, MCH, MCHC)
  ),
  cbc_hcpcs = c(
    "G0306", # CBC without differential (Medicare preventive service)
    "G0307" # CBC with differential (Medicare preventive service)
  ),
  cbc_loinc = c(
    "58410-2", # CBC panel - Blood by Automated count
    "57021-8", # CBC W Auto Differential panel - Blood
    "57782-5", # CBC W Ordered Manual Differential panel - Blood
    "57022-6", # CBC W Differential panel - Blood (unspecified method)
    "24364-2" # CBC panel - Blood (alternate)
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
  crp_cpt = c("86141"), # CRP, high sensitivity (cardiac)
  crp_loinc = c("30522-7"), # C-Reactive Protein, Cardiac (high sensitivity)

  # Liver function tests -- ALT
  alt_cpt = c("84460"), # Alanine amino transferase (ALT/SGPT)
  alt_loinc = c("1742-6"), # ALT [Enzymatic activity/volume] in Serum or Plasma

  # Liver function tests -- AST
  ast_cpt = c("84450"), # Aspartate amino transferase (AST/SGOT)
  ast_loinc = c("1920-8"), # AST [Enzymatic activity/volume] in Serum or Plasma

  # Alkaline phosphatase
  alp_cpt = c("84075"), # Alkaline phosphatase
  alp_loinc = c("6768-6"), # ALP [Enzymatic activity/volume] in Serum or Plasma

  # GGT (gamma-glutamyl transferase)
  ggt_cpt = c("82977"), # Glutamyltransferase, gamma (GGT)
  ggt_loinc = c("2324-2"), # GGT [Enzymatic activity/volume] in Serum or Plasma

  # Bilirubin
  bilirubin_cpt = c("82247"), # Bilirubin, total
  bilirubin_loinc = c(
    "1975-2", # Bilirubin, Total [Mass/volume] in Serum or Plasma
    "1968-7", # Bilirubin Fraction, Neonatal
    "1971-1" # Bili, Indirect, Neonatal
  ),

  # Platelets (from Labs sheet -- no CPT listed)
  platelets_loinc = c(
    "777-3", # Platelets [#/volume] in Blood by Automated count
    "86465-2", # APRI Index (APRI = AST/Platelet Ratio Index, derived value)
    "80563-0" # PDF (platelet distribution function, derived value)
  ),

  # Fecal occult blood test (FOBT)
  fobt_cpt = c("82274"), # Blood, occult, by immunoassay (FOBT, iFOBT)
  fobt_loinc = c("29771-3"), # Hemoglobin.gastrointestinal [Presence] in Stool by Immunoassay

  # TSH (duplicated from SURVEILLANCE_CODES for lab query convenience)
  tsh_loinc = c(
    "11580-8", # Thyrotropin [Units/volume] in Serum or Plasma
    "3024-7" # Thyrotropin [Units/volume] in Serum or Plasma (variant)
  ),

  # CBC (duplicated from SURVEILLANCE_CODES for lab query convenience)
  cbc_loinc = c(
    "58410-2", # CBC panel - Blood by Automated count
    "57021-8", # CBC W Auto Differential panel - Blood
    "57782-5", # CBC W Ordered Manual Differential panel - Blood
    "57022-6", # CBC W Differential panel - Blood (unspecified method)
    "24364-2" # CBC panel - Blood (alternate)
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
    "V87.41", # Personal history of antineoplastic chemotherapy
    "V87.42", # Personal history of monoclonal drug therapy
    "V87.43", # Personal history of estrogen therapy
    "V87.46", # Personal history of immunosuppression therapy
    "V15.3" # Personal history of irradiation
  ),
  personal_history_icd10 = c(
    "Z92.21", # Personal history of antineoplastic chemotherapy
    "Z92.22", # Personal history of monoclonal drug therapy
    "Z92.23", # Personal history of estrogen therapy
    "Z92.25", # Personal history of immunosuppression therapy
    "Z92.3" # Personal history of irradiation
  )
)

# ------------------------------------------------------------------------------
# 5.5b TREATMENT TYPE DEFINITIONS (Phase quick: centralized from duplicate script definitions)
# ------------------------------------------------------------------------------

# Standard treatment types for analysis (used across treatment inventory, duration, episode scripts)
TREATMENT_TYPES <- c("Chemotherapy", "Radiation", "SCT", "Immunotherapy")

# Treatment type colors for xlsx styling (8-char hex with FF alpha prefix)
# Canonical palette covering all treatment analysis and Gantt visualization needs
TREATMENT_TYPE_COLORS <- list(
  Chemotherapy      = list(fill = "FFDCEEFB", font = "FF0B5394"), # light blue / dark blue
  Radiation         = list(fill = "FFDDF4E1", font = "FF274E13"), # light green / dark green
  SCT               = list(fill = "FFFFF4D6", font = "FF7F6000"), # light yellow / dark olive
  Immunotherapy     = list(fill = "FFE8DCF4", font = "FF4C1D7A"), # light purple / dark purple
  `HL Diagnosis`    = list(fill = "FFFFF0D6", font = "FF8B6914"), # light gold / dark gold
  Death             = list(fill = "FFFDE8E8", font = "FF991B1B"), # light red / dark red
  `Supportive Care` = list(fill = "FFD5F5F0", font = "FF0E6655"), # light teal / dark teal
  Unrelated         = list(fill = "FFF3F4F6", font = "FF6B7280") # light gray / medium gray
)

# Treatment types recognized as part of the Gantt treatment category
# Includes standard treatments + HL Diagnosis (Gantt timeline marker treated as treatment)
GANTT_TREATMENT_TYPES <- c(TREATMENT_TYPES, "HL Diagnosis")

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
    "207RH0000X", # Internal Medicine: Hematology
    "207RH0003X", # Internal Medicine: Hematology & Oncology
    "207RX0202X", # Internal Medicine: Medical Oncology
    "2085R0001X", # Radiology: Radiation Oncology
    "2086X0206X", # Surgery: Surgical Oncology
    "2080P0207X" # Pediatrics: Pediatric Hematology-Oncology
  )
)

# ==============================================================================
# SECTION 7b: DEFENSIVE CODING LIBRARY ----
# ==============================================================================
# WHY load checkmate here: Per D-04, checkmate is loaded once in 00_config.R.
# Since every production script sources 00_config.R (directly or via chain),
# checkmate assertions are available everywhere without per-script library() calls.
# The 5 assertion helpers in R/utils/utils_assertions.R use checkmate functions.
library(checkmate)

# ==============================================================================
# SECTION 8: AUTO-SOURCE UTILITY FUNCTIONS ----
# ==============================================================================
# Load all utility modules from R/utils/ subfolder.
# New utils files added in future phases are auto-discovered (D-04).
#
# WHY auto-sourcing: Every downstream script sources R/00_config.R to get access
# to config constants. Auto-sourcing utils here ensures that shared functions
# (date parsing, attrition logging, DuckDB access, ICD normalization, payer helpers,
# PPTX styling, snapshots, treatment helpers) are available in every script
# without requiring 8 individual source() calls.

utils_files <- list.files(
  path = "R/utils",
  pattern = "\\.R$",
  full.names = TRUE
)

if (length(utils_files) == 0) {
  warning("No utility files found in R/utils/ -- expected at least 8 modules")
} else {
  invisible(lapply(utils_files, source))
  message(sprintf("Loaded %d utility modules from R/utils/", length(utils_files)))
}

# ==============================================================================
# End of configuration
# ==============================================================================
