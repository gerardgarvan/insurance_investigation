# ==============================================================================
# PCORnet Payer Variable Investigation (R Pipeline)
# Script: 15_generate_documentation.R
# Purpose: Auto-generate comprehensive variable documentation (D-15, D-16, D-17, D-18)
# ==============================================================================
#
# D-15: Produces both .md (source of truth) and .docx (sharing copy) outputs
# D-16: Covers all pipeline variables: treatment, surveillance, labs, survivorship,
#        payer, cohort definition, and timing
# D-17: Reads code lists programmatically from 00_config.R (stays in sync with code)
# D-18: Methodology only -- no patient counts, run statistics, or data-specific results.
#        All numeric values reflect code list counts, not patient counts.
#
# Usage:
#   source("R/15_generate_documentation.R")
#   # Outputs written to output/docs/Treatment_Variable_Documentation.md
#   #                   and output/docs/Treatment_Variable_Documentation.docx
#
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Load dependencies and config
# ------------------------------------------------------------------------------

source("R/00_config.R")

if (!requireNamespace("glue", quietly = TRUE)) {
  stop("Package 'glue' is required. Install with: install.packages('glue')")
}
if (!requireNamespace("rmarkdown", quietly = TRUE)) {
  stop("Package 'rmarkdown' is required. Install with: install.packages('rmarkdown')")
}

library(glue)

# ------------------------------------------------------------------------------
# 2. Create output directory
# ------------------------------------------------------------------------------

docs_dir <- file.path(CONFIG$output_dir, "docs")
dir.create(docs_dir, showWarnings = FALSE, recursive = TRUE)

# ------------------------------------------------------------------------------
# 3. Helper: format code list for display
#    Returns: "CODE1, CODE2, ... (N total)" with truncation if >8 items
# ------------------------------------------------------------------------------

fmt_codes <- function(codes, max_show = 8) {
  if (is.null(codes) || length(codes) == 0) return("(none)")
  n <- length(codes)
  if (n <= max_show) {
    paste0(paste(codes, collapse = ", "), glue(" ({n} total)"))
  } else {
    shown <- paste(head(codes, max_show), collapse = ", ")
    paste0(shown, glue(", ... ({n} total)"))
  }
}

fmt_codes_bullet <- function(codes, max_show = 8) {
  if (is.null(codes) || length(codes) == 0) return("  - (none)")
  n <- length(codes)
  if (n <= max_show) {
    paste(paste0("  - ", codes), collapse = "\n")
  } else {
    shown_lines <- paste(paste0("  - ", head(codes, max_show)), collapse = "\n")
    paste0(shown_lines, glue("\n  - ... ({n - max_show} more; {n} total)"))
  }
}

# ------------------------------------------------------------------------------
# 4. Build markdown content
# ------------------------------------------------------------------------------

md <- character(0)

# ---- YAML front matter (required for rmarkdown::render to produce .docx) -----
md <- c(md,
  "---",
  'title: "PCORnet Hodgkin Lymphoma Pipeline -- Variable Documentation"',
  'date: "`r Sys.Date()`"',
  "output: word_document",
  "---",
  ""
)

# ==============================================================================
# Section 1: Title and metadata
# ==============================================================================

md <- c(md,
  "# PCORnet Hodgkin Lymphoma Pipeline -- Variable Documentation",
  "",
  glue("**Generated:** {Sys.Date()}"),
  "**Pipeline version:** Phase 10",
  "**Data source:** PCORnet CDM v6.0+ (Mailhot HL Cohort Extract, 2025-09-15)",
  "**Note:** This document is methodology-only. It describes variable definitions,",
  "detection logic, and code lists. It does not contain patient counts or results.",
  ""
)

# ==============================================================================
# Section 2: Cohort Definition
# ==============================================================================

n_icd10 <- length(ICD_CODES$hl_icd10)
n_icd9  <- length(ICD_CODES$hl_icd9)
n_histology <- length(ICD_CODES$hl_histology)

md <- c(md,
  "---",
  "",
  "## Section 2: Cohort Definition",
  "",
  "### Filter Chain",
  "",
  "The analysis cohort is built by applying the following sequential filters:",
  "",
  "1. **DEMOGRAPHIC** -- All patients with any record in the CDM",
  "2. **has_hodgkin_diagnosis** -- Patients with at least one HL diagnosis",
  "   (ICD-10-CM C81.xx, ICD-9-CM 201.xx, or ICD-O-3 histology in TUMOR_REGISTRY)",
  "3. **with_enrollment_period** -- Patients with a valid enrollment period",
  "   (at least 30 continuous days of enrollment coverage)",
  "4. **exclude_missing_payer** -- Patients with at least one encounter that has",
  "   a non-sentinel payer value (removes records with payer = NI/UN/OT for all encounters)",
  "",
  "### Hodgkin Lymphoma Identification Codes",
  "",
  glue("- **ICD-10-CM codes:** {n_icd10} codes in the C81.xx range"),
  "  - Subtypes: Nodular lymphocyte predominant (C81.0x), Nodular sclerosis (C81.1x),",
  "    Mixed cellularity (C81.2x), Lymphocyte depleted (C81.3x), Lymphocyte-rich (C81.4x),",
  "    Other classical (C81.7x), Unspecified (C81.9x), In remission variants (C81.xA)",
  glue("- **ICD-9-CM codes:** {n_icd9} codes in the 201.xx range"),
  "  - Includes parent codes without anatomic site digit (e.g., 201.2 not 201.20)",
  "  - Subtypes: Paragranuloma (201.0x), Granuloma (201.1x), Sarcoma (201.2x),",
  "    Lymphocytic-histiocytic predominance (201.4x), Nodular sclerosis (201.5x),",
  "    Mixed cellularity (201.6x), Lymphocytic depletion (201.7x), Unspecified (201.9x)",
  glue("- **ICD-O-3 histology codes (TUMOR_REGISTRY):** {n_histology} morphology codes in range 9650-9667"),
  glue("  - Codes: {fmt_codes(ICD_CODES$hl_histology)}"),
  "",
  "### HL Source Tracking Variable",
  "",
  "| Variable | Values | Description |",
  "|----------|--------|-------------|",
  "| HL_SOURCE | `DIAGNOSIS only` | Patient identified via DIAGNOSIS table only |",
  "| HL_SOURCE | `TR only` | Patient identified via TUMOR_REGISTRY only |",
  "| HL_SOURCE | `Both` | Patient identified in both DIAGNOSIS and TUMOR_REGISTRY |",
  "| HL_SOURCE | `Neither` | No HL evidence found; patient excluded |",
  "| HL_VERIFIED | `1` | Patient has any HL evidence (included in cohort) |",
  "| HL_VERIFIED | `0` | No HL evidence; excluded |",
  ""
)

# ==============================================================================
# Section 3: Demographics and Enrollment
# ==============================================================================

md <- c(md,
  "---",
  "",
  "## Section 3: Demographics and Enrollment",
  "",
  "### Demographic Variables",
  "",
  "| Variable | Source Table | Description |",
  "|----------|-------------|-------------|",
  "| SEX | DEMOGRAPHIC | Patient sex (M/F/UN/NI/OT per PCORnet CDM) |",
  "| RACE | DEMOGRAPHIC | Patient race (coded per PCORnet v6.0 race typology) |",
  "| HISPANIC | DEMOGRAPHIC | Hispanic ethnicity indicator (Y/N/R/UN/NI/OT) |",
  "",
  "### Enrollment Variables",
  "",
  "| Variable | Source Table | Description |",
  "|----------|-------------|-------------|",
  "| age_at_enr_start | ENROLLMENT | Patient age at enrollment period start (years) |",
  "| age_at_enr_end | ENROLLMENT | Patient age at enrollment period end (years) |",
  "| enrollment_duration_days | ENROLLMENT | Total enrollment duration (integer days) |",
  "| first_hl_dx_date | DIAGNOSIS / TUMOR_REGISTRY | Date of earliest HL diagnosis record |",
  ""
)

# ==============================================================================
# Section 4: Payer Variables
# ==============================================================================

md <- c(md,
  "---",
  "",
  "## Section 4: Payer Variables",
  "",
  "### Payer Category System",
  "",
  "Payer categories use a 9-category harmonization scheme matching the Python pipeline:",
  paste0("**Categories:** ", paste(PAYER_MAPPING$categories, collapse = ", ")),
  "",
  "**Dual-eligible detection (encounter-level):**",
  "- Primary = Medicare (prefix 1) AND secondary = Medicaid (prefix 2), OR",
  "- Primary = Medicaid AND secondary = Medicare, OR",
  glue("- Primary or secondary in exact-match codes: {paste(PAYER_MAPPING$dual_eligible_codes, collapse = ', ')}"),
  "",
  "**Sentinel values** (trigger fallback to secondary payer):",
  glue("- {paste(PAYER_MAPPING$sentinel_values, collapse = ', ')} -- treated as missing primary payer"),
  "",
  "**Unavailable codes:**",
  glue("- {paste(PAYER_MAPPING$unavailable_codes, collapse = ', ')} -- map to 'Unavailable' category"),
  "",
  "### Patient-Level Payer Summary Variables",
  "",
  "| Variable | Description |",
  "|----------|-------------|",
  "| PAYER_CATEGORY_PRIMARY | Mode of 9-category payer across all encounters for the patient |",
  "| PAYER_CATEGORY_AT_FIRST_DX | Payer category at the encounter closest to first HL diagnosis date |",
  "| DUAL_ELIGIBLE | 0/1 flag: patient has at least one encounter with Medicare+Medicaid evidence |",
  "| PAYER_TRANSITION | 0/1 flag: patient's payer category changed over time (at least two distinct categories) |",
  "| N_ENCOUNTERS | Total number of encounters for the patient |",
  "| N_ENCOUNTERS_WITH_PAYER | Number of encounters with a non-sentinel payer value |",
  ""
)

# ==============================================================================
# Section 5: Treatment Variables
# ==============================================================================

# Code counts
n_chemo_hcpcs         <- length(TREATMENT_CODES$chemo_hcpcs)
n_chemo_rxnorm        <- length(TREATMENT_CODES$chemo_rxnorm)
n_chemo_icd9          <- length(TREATMENT_CODES$chemo_icd9)
n_chemo_icd10pcs      <- length(TREATMENT_CODES$chemo_icd10pcs_prefixes)
n_chemo_dx_icd10      <- length(TREATMENT_CODES$chemo_dx_icd10)
n_chemo_dx_icd9       <- length(TREATMENT_CODES$chemo_dx_icd9)
n_chemo_drg           <- length(TREATMENT_CODES$chemo_drg)
n_chemo_revenue       <- length(TREATMENT_CODES$chemo_revenue)

n_rad_cpt             <- length(TREATMENT_CODES$radiation_cpt)
n_rad_icd9            <- length(TREATMENT_CODES$radiation_icd9)
n_rad_icd10pcs        <- length(TREATMENT_CODES$radiation_icd10pcs_prefixes)
n_rad_dx_icd10        <- length(TREATMENT_CODES$radiation_dx_icd10)
n_rad_dx_icd9         <- length(TREATMENT_CODES$radiation_dx_icd9)
n_rad_drg             <- length(TREATMENT_CODES$radiation_drg)
n_rad_revenue         <- length(TREATMENT_CODES$radiation_revenue)

n_sct_cpt             <- length(TREATMENT_CODES$sct_cpt)
n_sct_hcpcs           <- length(TREATMENT_CODES$sct_hcpcs)
n_sct_icd9            <- length(TREATMENT_CODES$sct_icd9)
n_sct_icd10pcs        <- length(TREATMENT_CODES$sct_icd10pcs)
n_sct_dx_icd10        <- length(TREATMENT_CODES$sct_dx_icd10)
n_sct_drg             <- length(TREATMENT_CODES$sct_drg)
n_sct_revenue         <- length(TREATMENT_CODES$sct_revenue)
n_cart_icd10pcs       <- length(TREATMENT_CODES$cart_icd10pcs_prefixes)

md <- c(md,
  "---",
  "",
  "## Section 5: Treatment Variables",
  "",
  "Treatment flags (HAD_CHEMO, HAD_RADIATION, HAD_SCT) are 0/1 indicators",
  "derived from evidence across multiple PCORnet CDM tables. Primary evidence",
  "comes from TUMOR_REGISTRY date columns; supplemental evidence comes from",
  "PROCEDURES and other tables.",
  "",
  "### 5.1 Chemotherapy",
  "",
  "| Variable | Description |",
  "|----------|-------------|",
  "| HAD_CHEMO | 0/1 flag: patient has any chemotherapy evidence |",
  "| FIRST_CHEMO_DATE | Date of earliest chemotherapy evidence |",
  "",
  "**Detection sources and code counts:**",
  "",
  "| Source | Code System | Count | Codes |",
  "|--------|-------------|-------|-------|",
  glue("| TUMOR_REGISTRY | DT_CHEMO / CHEMO_START_DATE_SUMMARY | Date fields | TR1/TR2/TR3 date columns |"),
  glue("| PROCEDURES | HCPCS (J-codes) | {n_chemo_hcpcs} | {fmt_codes(TREATMENT_CODES$chemo_hcpcs)} |"),
  glue("| PRESCRIBING / DISPENSING / MED_ADMIN | RXNORM CUIs | {n_chemo_rxnorm} | {fmt_codes(TREATMENT_CODES$chemo_rxnorm)} |"),
  glue("| PROCEDURES | ICD-9-CM Volume 3 (PX_TYPE='09') | {n_chemo_icd9} | {fmt_codes(TREATMENT_CODES$chemo_icd9)} |"),
  glue("| PROCEDURES | ICD-10-PCS prefixes (PX_TYPE='10') | {n_chemo_icd10pcs} | {fmt_codes(TREATMENT_CODES$chemo_icd10pcs_prefixes)} |"),
  glue("| DIAGNOSIS | ICD-10-CM Z codes | {n_chemo_dx_icd10} | {fmt_codes(TREATMENT_CODES$chemo_dx_icd10)} |"),
  glue("| DIAGNOSIS | ICD-9-CM V codes | {n_chemo_dx_icd9} | {fmt_codes(TREATMENT_CODES$chemo_dx_icd9)} |"),
  glue("| ENCOUNTER | MS-DRG codes | {n_chemo_drg} | {fmt_codes(TREATMENT_CODES$chemo_drg)} |"),
  glue("| PROCEDURES | Revenue codes (PX_TYPE='RE') | {n_chemo_revenue} | {fmt_codes(TREATMENT_CODES$chemo_revenue)} |"),
  "",
  "### 5.2 Radiation Therapy",
  "",
  "| Variable | Description |",
  "|----------|-------------|",
  "| HAD_RADIATION | 0/1 flag: patient has any radiation therapy evidence |",
  "| FIRST_RADIATION_DATE | Date of earliest radiation therapy evidence |",
  "",
  "**Detection sources and code counts:**",
  "",
  "| Source | Code System | Count | Codes |",
  "|--------|-------------|-------|-------|",
  glue("| TUMOR_REGISTRY | DT_RAD | Date fields | TR2/TR3 date columns |"),
  glue("| PROCEDURES | CPT codes | {n_rad_cpt} | {fmt_codes(TREATMENT_CODES$radiation_cpt)} |"),
  glue("| PROCEDURES | ICD-9-CM Volume 3 (PX_TYPE='09') | {n_rad_icd9} | {fmt_codes(TREATMENT_CODES$radiation_icd9)} |"),
  glue("| PROCEDURES | ICD-10-PCS prefixes (PX_TYPE='10') | {n_rad_icd10pcs} | {fmt_codes(TREATMENT_CODES$radiation_icd10pcs_prefixes)} |"),
  glue("| DIAGNOSIS | ICD-10-CM Z codes | {n_rad_dx_icd10} | {fmt_codes(TREATMENT_CODES$radiation_dx_icd10)} |"),
  glue("| DIAGNOSIS | ICD-9-CM V codes | {n_rad_dx_icd9} | {fmt_codes(TREATMENT_CODES$radiation_dx_icd9)} |"),
  glue("| ENCOUNTER | MS-DRG codes | {n_rad_drg} | {fmt_codes(TREATMENT_CODES$radiation_drg)} |"),
  glue("| PROCEDURES | Revenue codes (PX_TYPE='RE') | {n_rad_revenue} | {fmt_codes(TREATMENT_CODES$radiation_revenue)} |"),
  "",
  "### 5.3 Stem Cell Transplant (SCT)",
  "",
  "| Variable | Description |",
  "|----------|-------------|",
  "| HAD_SCT | 0/1 flag: patient has any SCT evidence (autologous or allogeneic) |",
  "| FIRST_SCT_DATE | Date of earliest SCT evidence |",
  "",
  "**Detection sources and code counts:**",
  "",
  "| Source | Code System | Count | Codes |",
  "|--------|-------------|-------|-------|",
  glue("| TUMOR_REGISTRY | DT_HTE (hematologic transplant/endocrine) | Date fields | TR2/TR3 date columns |"),
  glue("| PROCEDURES | CPT codes | {n_sct_cpt} | {fmt_codes(TREATMENT_CODES$sct_cpt)} |"),
  glue("| PROCEDURES | HCPCS S-codes (Phase 10) | {n_sct_hcpcs} | {fmt_codes(TREATMENT_CODES$sct_hcpcs)} |"),
  glue("| PROCEDURES | ICD-9-CM Volume 3 (PX_TYPE='09') | {n_sct_icd9} | {fmt_codes(TREATMENT_CODES$sct_icd9)} |"),
  glue("| PROCEDURES | ICD-10-PCS exact codes (PX_TYPE='10') | {n_sct_icd10pcs} | {fmt_codes(TREATMENT_CODES$sct_icd10pcs)} |"),
  glue("| DIAGNOSIS | ICD-10-CM Z/T codes | {n_sct_dx_icd10} | {fmt_codes(TREATMENT_CODES$sct_dx_icd10)} |"),
  glue("| ENCOUNTER | MS-DRG codes | {n_sct_drg} | {fmt_codes(TREATMENT_CODES$sct_drg)} |"),
  glue("| PROCEDURES | Revenue codes (PX_TYPE='RE') | {n_sct_revenue} | {fmt_codes(TREATMENT_CODES$sct_revenue)} |"),
  "",
  "### 5.4 CAR T-Cell / Immunotherapy (supplemental)",
  "",
  glue("CAR T-cell and advanced immunotherapy ICD-10-PCS prefix codes ({n_cart_icd10pcs} prefixes, Phase 10):"),
  glue("- {fmt_codes(TREATMENT_CODES$cart_icd10pcs_prefixes)}"),
  "- Used to capture DRG 016 (Autologous BMT w CC/MCC or T-cell immunotherapy) evidence",
  ""
)

# ==============================================================================
# Section 6: Treatment-Anchored Payer Variables
# ==============================================================================

md <- c(md,
  "---",
  "",
  "## Section 6: Treatment-Anchored Payer Variables",
  "",
  "For each treatment type, payer is captured at the time of treatment using",
  "a +/-30 day window around the first treatment date.",
  "",
  "| Variable | Treatment | Window | Description |",
  "|----------|-----------|--------|-------------|",
  "| PAYER_AT_CHEMO | Chemotherapy | FIRST_CHEMO_DATE +/-30 days | Mode payer category across encounters in window |",
  "| PAYER_AT_RADIATION | Radiation | FIRST_RADIATION_DATE +/-30 days | Mode payer category across encounters in window |",
  "| PAYER_AT_SCT | Stem cell transplant | FIRST_SCT_DATE +/-30 days | Mode payer category across encounters in window |",
  "",
  "**Computation:** For all ENCOUNTER rows within the window, the effective payer",
  "is determined per encounter (primary if non-sentinel, else secondary). The mode",
  "(most frequent) payer category is assigned to the patient for that treatment type.",
  "If no encounters fall within the window, the variable is NA.",
  ""
)

# ==============================================================================
# Section 7: Timing Variables
# ==============================================================================

md <- c(md,
  "---",
  "",
  "## Section 7: Timing Variables (D-12)",
  "",
  "Timing variables measure the interval from first HL diagnosis to first treatment.",
  "These capture treatment initiation delays and are used for time-to-treatment analysis.",
  "",
  "| Variable | Formula | Description |",
  "|----------|---------|-------------|",
  "| DAYS_DX_TO_CHEMO | FIRST_CHEMO_DATE - first_hl_dx_date | Integer days from diagnosis to first chemotherapy |",
  "| DAYS_DX_TO_RADIATION | FIRST_RADIATION_DATE - first_hl_dx_date | Integer days from diagnosis to first radiation |",
  "| DAYS_DX_TO_SCT | FIRST_SCT_DATE - first_hl_dx_date | Integer days from diagnosis to first SCT |",
  "",
  "**Notes:**",
  "- Negative values indicate the treatment evidence predates the recorded diagnosis date",
  "  (possible for TUMOR_REGISTRY dates vs DIAGNOSIS table entries)",
  "- NA when patient has no evidence of the given treatment type",
  ""
)

# ==============================================================================
# Section 8: Surveillance Modalities
# ==============================================================================

surv_names <- names(SURVEILLANCE_CODES)
modality_groups <- unique(sub("_(cpt|hcpcs|icd10pcs|icd10_dx|loinc)$", "", surv_names))

md <- c(md,
  "---",
  "",
  "## Section 8: Surveillance Modalities (D-01, D-03, D-04)",
  "",
  "Surveillance variables detect post-diagnosis monitoring procedures. All surveillance",
  "flags use a detection window of **post-diagnosis** (after first_hl_dx_date).",
  "",
  "For each modality:",
  "- **HAD_{MODALITY}:** 0/1 flag -- patient had at least one of this procedure post-diagnosis",
  "- **FIRST_{MODALITY}_DATE:** Date of earliest procedure post-diagnosis",
  "- **N_{MODALITY}:** Count of procedures post-diagnosis",
  "",
  glue("Total surveillance code lists: {length(surv_names)} code sub-lists across {length(modality_groups)} modalities"),
  ""
)

# Document each modality
modality_info <- list(
  mammogram       = list(label = "Mammogram",          table = "PROCEDURES",                   systems = c("CPT/HCPCS", "ICD-10-PCS")),
  breast_mri      = list(label = "Breast MRI",         table = "PROCEDURES",                   systems = c("CPT", "HCPCS", "ICD-10-PCS")),
  echo            = list(label = "Echocardiogram",     table = "PROCEDURES / DIAGNOSIS",        systems = c("CPT", "ICD-10-PCS", "ICD-10-CM screening Z code")),
  stress_test     = list(label = "Stress Test",        table = "PROCEDURES",                   systems = c("CPT (nuclear cardiology)")),
  ecg             = list(label = "Electrocardiogram",  table = "PROCEDURES / DIAGNOSIS",        systems = c("CPT", "ICD-10-CM screening Z code")),
  muga            = list(label = "MUGA",               table = "PROCEDURES",                   systems = c("CPT", "ICD-10-PCS")),
  pft             = list(label = "Pulmonary Function Test", table = "PROCEDURES / DIAGNOSIS",  systems = c("CPT", "ICD-10-CM screening Z code")),
  tsh             = list(label = "TSH",                table = "PROCEDURES / LAB_RESULT_CM",   systems = c("CPT", "HCPCS", "LOINC")),
  cbc             = list(label = "CBC",                table = "PROCEDURES / LAB_RESULT_CM",   systems = c("CPT", "HCPCS", "LOINC"))
)

for (mod_key in names(modality_info)) {
  info <- modality_info[[mod_key]]
  # Gather all code sub-lists for this modality
  mod_lists <- SURVEILLANCE_CODES[grepl(paste0("^", mod_key, "_"), names(SURVEILLANCE_CODES))]

  md <- c(md,
    glue("### 8.{which(names(modality_info) == mod_key)} {info$label}"),
    "",
    glue("**Source table(s):** {info$table}"),
    glue("**Code systems:** {paste(info$systems, collapse = ', ')}"),
    ""
  )

  md <- c(md, "| Code System | Count | Sample Codes |",
              "|-------------|-------|--------------|")
  for (list_name in names(mod_lists)) {
    sys_suffix <- sub(paste0("^", mod_key, "_"), "", list_name)
    sys_label <- toupper(gsub("_", "-", sys_suffix))
    codes <- mod_lists[[list_name]]
    md <- c(md, glue("| {sys_label} | {length(codes)} | {fmt_codes(codes, max_show = 5)} |"))
  }
  md <- c(md, "")
}

# ==============================================================================
# Section 9: Lab Results
# ==============================================================================

lab_names <- names(LAB_CODES)
lab_groups <- unique(sub("_(cpt|loinc)$", "", lab_names))

md <- c(md,
  "---",
  "",
  "## Section 9: Lab Results (D-02)",
  "",
  "Lab result variables detect post-diagnosis laboratory tests. Source table is",
  "LAB_RESULT_CM matched via LOINC codes (primary) and PROCEDURES via CPT codes",
  "(supplemental). Detection window: **post-diagnosis** (after first_hl_dx_date).",
  "",
  "For each lab type:",
  "- **HAD_{LAB}:** 0/1 flag -- patient had at least one lab result of this type post-diagnosis",
  "- **FIRST_{LAB}_DATE:** Date of earliest lab result post-diagnosis",
  "- **N_{LAB}:** Count of lab results post-diagnosis",
  "",
  glue("Total lab code lists: {length(lab_names)} code sub-lists across {length(lab_groups)} lab types"),
  "",
  "| Lab Type | Code Systems | LOINC Count | CPT Count | Sample LOINC Codes |",
  "|----------|-------------|-------------|-----------|-------------------|"
)

lab_display <- list(
  crp        = "CRP (C-Reactive Protein)",
  alt        = "ALT (Alanine Aminotransferase)",
  ast        = "AST (Aspartate Aminotransferase)",
  alp        = "ALP (Alkaline Phosphatase)",
  ggt        = "GGT (Gamma-Glutamyl Transferase)",
  bilirubin  = "Bilirubin (Total)",
  platelets  = "Platelets",
  fobt       = "FOBT (Fecal Occult Blood Test)",
  tsh        = "TSH (Thyroid Stimulating Hormone)",
  cbc        = "CBC (Complete Blood Count)"
)

for (lab_key in names(lab_display)) {
  loinc_codes <- LAB_CODES[[paste0(lab_key, "_loinc")]]
  cpt_codes   <- LAB_CODES[[paste0(lab_key, "_cpt")]]
  n_loinc <- if (is.null(loinc_codes)) 0 else length(loinc_codes)
  n_cpt   <- if (is.null(cpt_codes))   0 else length(cpt_codes)
  sample  <- if (n_loinc > 0) fmt_codes(loinc_codes, max_show = 3) else "(none)"
  systems <- c(
    if (n_loinc > 0) "LOINC",
    if (n_cpt > 0)   "CPT"
  )
  md <- c(md,
    glue("| {lab_display[[lab_key]]} | {paste(systems, collapse = '/')} | {n_loinc} | {n_cpt} | {sample} |")
  )
}

md <- c(md, "")

# ==============================================================================
# Section 10: Survivorship Encounter Classification
# ==============================================================================

n_oncology_nucc   <- length(PROVIDER_SPECIALTIES$cancer_oncology)
n_hist_icd9       <- length(SURVIVORSHIP_CODES$personal_history_icd9)
n_hist_icd10      <- length(SURVIVORSHIP_CODES$personal_history_icd10)

md <- c(md,
  "---",
  "",
  "## Section 10: Survivorship Encounter Classification (D-05 through D-10)",
  "",
  "Survivorship encounters are classified into four hierarchical levels.",
  "Each level is a strict subset of the previous level.",
  "All levels are restricted to **post-diagnosis** encounters (after first_hl_dx_date).",
  "",
  "### Level 1: ENC_NONACUTE_CARE",
  "",
  "**Definition:** Ambulatory (AV) or Telehealth (TH) encounters post-diagnosis.",
  "",
  "| Variable | Description |",
  "|----------|-------------|",
  "| HAD_ENC_NONACUTE | 0/1 flag: patient had any Level 1 encounter |",
  "| N_ENC_NONACUTE | Count of Level 1 encounters |",
  "| FIRST_ENC_NONACUTE_DATE | Date of earliest Level 1 encounter |",
  "",
  "### Level 2: ENC_CANCER_RELATED",
  "",
  "**Definition:** Level 1 encounters that also have an HL diagnosis code on the encounter.",
  glue("- HL ICD-10 codes used: {n_icd10} C81.xx codes (ICD_CODES$hl_icd10)"),
  glue("- HL ICD-9 codes used: {n_icd9} 201.xx codes (ICD_CODES$hl_icd9)"),
  "",
  "| Variable | Description |",
  "|----------|-------------|",
  "| HAD_ENC_CANCER_RELATED | 0/1 flag: patient had any Level 2 encounter |",
  "| N_ENC_CANCER_RELATED | Count of Level 2 encounters |",
  "| FIRST_ENC_CANCER_RELATED_DATE | Date of earliest Level 2 encounter |",
  "",
  "### Level 3: ENC_CANCER_PROVIDER",
  "",
  "**Definition:** Level 2 encounters where the provider has an oncology NUCC taxonomy code.",
  "",
  glue("**Oncology provider specialties ({n_oncology_nucc} NUCC codes):**"),
  ""
)

for (code in PROVIDER_SPECIALTIES$cancer_oncology) {
  md <- c(md, glue("- `{code}`"))
}

md <- c(md,
  "",
  "| Variable | Description |",
  "|----------|-------------|",
  "| HAD_ENC_CANCER_PROVIDER | 0/1 flag: patient had any Level 3 encounter |",
  "| N_ENC_CANCER_PROVIDER | Count of Level 3 encounters |",
  "| FIRST_ENC_CANCER_PROVIDER_DATE | Date of earliest Level 3 encounter |",
  "",
  "### Level 4: ENC_SURVIVORSHIP",
  "",
  "**Definition:** Level 3 encounters where a personal history code (chemotherapy/radiation)",
  "appears on the encounter diagnosis list.",
  "",
  glue("**Personal history ICD-9-CM codes ({n_hist_icd9} codes):**"),
  ""
)

for (code in SURVIVORSHIP_CODES$personal_history_icd9) {
  md <- c(md, glue("- `{code}`"))
}

md <- c(md,
  "",
  glue("**Personal history ICD-10-CM codes ({n_hist_icd10} codes):**"),
  ""
)

for (code in SURVIVORSHIP_CODES$personal_history_icd10) {
  md <- c(md, glue("- `{code}`"))
}

md <- c(md,
  "",
  "**Note (D-09 / DX_TYPE filter):** ICD-9 personal history codes (V87.4x) are validated",
  "using DX_TYPE = '09' to prevent ICD-10 era false matches. ICD-10 codes validated with",
  "DX_TYPE = '10'. This prevents V87.4x-like codes from matching across coding eras.",
  "",
  "| Variable | Description |",
  "|----------|-------------|",
  "| HAD_ENC_SURVIVORSHIP | 0/1 flag: patient had any Level 4 encounter |",
  "| N_ENC_SURVIVORSHIP | Count of Level 4 encounters |",
  "| FIRST_ENC_SURVIVORSHIP_DATE | Date of earliest Level 4 encounter |",
  ""
)

# ==============================================================================
# Section 11: Pending / Deferred Variables
# ==============================================================================

md <- c(md,
  "---",
  "",
  "## Section 11: Pending / Deferred Variables",
  "",
  "The following variables are identified in the analysis design but not yet",
  "implemented in the pipeline. They are documented here for completeness.",
  "",
  "### 11.1 Surveillance Strategy -- Pending Modalities",
  "",
  "The following surveillance items from the VariableDetails.xlsx 'Surveillance Strategy'",
  "sheet do not yet have confirmed code lists and are pending code research:",
  "",
  "1. Colonoscopy / colorectal screening",
  "2. Bone density / DEXA scan",
  "3. Liver function monitoring (comprehensive metabolic panel)",
  "4. Lipid panel / cardiovascular risk screening",
  "5. HbA1c / diabetes screening",
  "6. Fertility evaluation / reproductive health",
  "7. Neuropsychological evaluation",
  "8. Dental examination",
  "9. Vision screening / ophthalmologic exam",
  "10. Second malignancy screening (site-specific, beyond mammogram/colonoscopy)",
  "",
  "### 11.2 Adriamycin / Doxorubicin Variables (Deferred)",
  "",
  "Separate detection of Adriamycin/doxorubicin (as a distinct ABVD component) is deferred",
  "pending access to SEER*Rx drug reference database for comprehensive RXNORM CUI list.",
  "Currently doxorubicin is captured within the broader chemotherapy flag (RXNORM CUI 3639).",
  "",
  "### 11.3 NDC-Based Drug Matching (Deferred)",
  "",
  "National Drug Code (NDC) matching for PRESCRIBING and DISPENSING tables is deferred.",
  "NDC codes change frequently and require a maintained NDC-to-ingredient crosswalk.",
  "Current pipeline uses RXNORM CUI matching which is more stable.",
  "",
  "### 11.4 Treatment Type Post-Diagnosis Factor (Superseded)",
  "",
  "A planned factor variable `treatment_type_post_dx` (None / Chemo only / Radiation only /",
  "Both / SCT) was superseded by individual HAD_CHEMO, HAD_RADIATION, HAD_SCT flags.",
  "The individual flags are more flexible for multi-treatment analyses.",
  ""
)

# ==============================================================================
# 5. Write markdown file
# ==============================================================================

md_path <- file.path(docs_dir, "Treatment_Variable_Documentation.md")
writeLines(md, md_path)
message(glue("Markdown documentation written to: {md_path}"))
message(glue("Total lines: {length(md)}"))

# ==============================================================================
# 6. Render to .docx via rmarkdown (D-15)
# ==============================================================================

# The markdown file includes YAML front matter (title, date, output: word_document)
# so rmarkdown::render can convert it directly to .docx.

docx_path <- file.path(docs_dir, "Treatment_Variable_Documentation.docx")

tryCatch({
  rmarkdown::render(
    input         = md_path,
    output_format = rmarkdown::word_document(),
    output_file   = "Treatment_Variable_Documentation.docx",
    output_dir    = docs_dir,
    quiet         = TRUE
  )
  message(glue("Word documentation written to: {docx_path}"))
}, error = function(e) {
  message(glue("WARNING: Could not render .docx -- {conditionMessage(e)}"))
  message("The .md file is the source of truth and was written successfully.")
  message("To render manually: rmarkdown::render('", md_path, "')")
})

message("Documentation generation complete.")
