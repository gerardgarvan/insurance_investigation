# ==============================================================================
# Phase 46: Treatment Code Cross-Reference Gap Report
# ==============================================================================
#
# Produces a two-way gap report comparing hardcoded reference code lists
# (from TreatmentVariables_2024.07.17.docx, Treatment_Variable_Documentation.docx,
# PCS Codes Cancer Tx.xlsx, ComprehensiveSurgeryCodes.xlsx, MSDRGs.xlsx)
# against the live TREATMENT_CODES config in R/00_config.R.
#
# Purpose:
#   - Audit/communication artifact: shows exactly what the reference documents
#     specify vs. what the pipeline actually uses.
#   - Both directions: codes in reference but not config (potential additions),
#     and codes in config but not reference (pipeline extensions).
#   - Per-gap-code patient and encounter counts from PROCEDURES data on HiPerGator.
#
# Inputs:
#   - R/00_config.R (TREATMENT_CODES named list -- "config" side)
#   - R/01_load_pcornet.R (DuckDB-backed PROCEDURES access)
#   - Hardcoded reference data (extracted from docx/xlsx sources -- see Section 2)
#
# Outputs:
#   - output/tables/treatment_cross_reference.xlsx (5-sheet styled workbook)
#     Sheet 1: "Summary" -- per-type counts + radiation CPT range narrative
#     Sheet 2: "Chemotherapy"
#     Sheet 3: "Radiation"
#     Sheet 4: "SCT"
#     Sheet 5: "Immunotherapy"
#
# Usage:
#   Rscript R/46b_treatment_cross_reference.R
#
# Decisions implemented:
#   D-01: All 4 active treatment types (chemo, radiation, SCT, immunotherapy)
#   D-02: Both TreatmentVariables_2024.07.17.docx and Treatment_Variable_Documentation.docx merged
#   D-03: External xlsx files (PCS Codes Cancer Tx.xlsx, ComprehensiveSurgeryCodes.xlsx, MSDRGs.xlsx)
#   D-04/D-05: Radiation CPT compared at range level, not individual code expansion
#   D-11: Styled multi-sheet xlsx, one sheet per type plus summary
#   D-12: Each sheet shows both directions (in-ref-not-config, in-config-not-ref)
#   D-13: Phase 45 audit-added codes annotated
#   D-14: Patient/encounter counts from PROCEDURES for gap codes
#   D-15/D-16: All reference data hardcoded (not parsed at runtime)
#
# Requirements: TXREF-01
# Phase 46 Plan 01 -- treatment-code-cross-reference
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(purrr)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")

OUTPUT_PATH <- file.path(CONFIG$output_dir, "tables", "treatment_cross_reference.xlsx")
dir.create(dirname(OUTPUT_PATH), showWarnings = FALSE, recursive = TRUE)

message("=== Phase 46: Treatment Code Cross-Reference Gap Report ===")
message(glue("Output: {OUTPUT_PATH}"))

# ==============================================================================
# SECTION 2: HARDCODED REFERENCE DATA
# ==============================================================================
# Source: Merged from TreatmentVariables_2024.07.17.docx, Treatment_Variable_Documentation.docx,
#         PCS Codes Cancer Tx.xlsx (125 ICD-10-PCS chemo codes, all treatment type = "chemo"),
#         ComprehensiveSurgeryCodes.xlsx (surgical/cancer site codes only, no tx classification),
#         MSDRGs.xlsx (DRG codes per type: SCT=014/016/017, chemo=837-848, rad=849)
#
# Decisions D-02, D-03, D-15, D-16: All reference data hardcoded. Docx content
# is static (dated 2024.07.17). External xlsx files read once at plan execution
# time and codes transcribed here.
#
# Reference structure mirrors TREATMENT_CODES in R/00_config.R:
#   chemotherapy, radiation, sct, immunotherapy

REFERENCE_CODES <- list(

  # ============================================================================
  # CHEMOTHERAPY
  # ============================================================================
  # Source: TreatmentVariables_2024.07.17.docx -- 6 categories including
  #   chemo HCPCS J-codes, ICD-9-CM procedure codes, ICD-10-PCS administration
  #   codes, DRG codes, revenue codes.
  # Source: Treatment_Variable_Documentation.docx -- adds Q-codes (Q0083-Q0085),
  #   additional ICD-10-PCS antineoplastic prefixes, doxorubicin detail.
  # Source: PCS Codes Cancer Tx.xlsx -- 125 ICD-10-PCS codes (Section 3E
  #   Administration/Antineoplastic across many body sites), all type = "chemo"
  # Source: MSDRGs.xlsx -- DRG 837, 838, 839, 846, 847, 848 (type = "chemo")
  chemotherapy = list(

    # HCPCS J-codes (injectable chemo drugs; J9000-J9999 range)
    # TreatmentVariables_2024.07.17.docx: "HCPCS Level II J-codes for chemotherapy"
    # Specifies J9000-J9999 as a category range for injectable antineoplastic drugs.
    # Treatment_Variable_Documentation.docx: adds Q0083-Q0085 (chemotherapy toxicity
    # administration add-ons), doxorubicin detail (J9000 explicitly named).
    hcpcs_jcodes = c(
      # Original ABVD regimen codes
      "J9000",   # Doxorubicin HCl (Adriamycin)
      "J9040",   # Bleomycin sulfate
      "J9360",   # Vinblastine sulfate
      "J9130",   # Dacarbazine (DTIC)
      "J9042",   # Brentuximab vedotin (Adcetris)
      "J9299"    # Nivolumab (Opdivo)
    ),

    # Q-codes from Treatment_Variable_Documentation.docx
    # These are chemotherapy administration monitoring codes (HCPCS Level II Q-codes)
    q_codes = c(
      "Q0083",   # Chemotherapy administration, push technique
      "Q0084",   # Chemotherapy administration, infusion technique
      "Q0085"    # Chemotherapy administration, both push and infusion
    ),

    # ICD-9-CM Volume 3 procedure codes
    # TreatmentVariables_2024.07.17.docx: 99.25, 99.28
    icd9_codes = c(
      "99.25",   # Injection or infusion of cancer chemotherapeutic substance
      "99.28"    # Injection or infusion of immunotherapy
    ),

    # ICD-10-PCS prefixes (Section 3E Administration, Antineoplastic qualifier 5)
    # TreatmentVariables_2024.07.17.docx: 3E03305, 3E04305, 3E05305, 3E06305
    # Treatment_Variable_Documentation.docx: same core 4 prefixes for IV routes
    # PCS Codes Cancer Tx.xlsx: 125 broader administration codes across all body sites
    # (3E00-3EYY range; many routes including subcutaneous, muscle, cavity, CSF, etc.)
    # Config uses 4 key IV-route prefixes: 3E03305, 3E04305, 3E05305, 3E06305
    # Reference doc lists those same 4 as primary.
    icd10pcs_prefixes = c(
      "3E03305",  # Antineoplastic into peripheral vein, percutaneous
      "3E04305",  # Antineoplastic into central vein, percutaneous
      "3E05305",  # Antineoplastic into peripheral artery, percutaneous
      "3E06305"   # Antineoplastic into central artery, percutaneous
    ),

    # Additional ICD-10-PCS codes from PCS Codes Cancer Tx.xlsx
    # These are the 125 broader chemo PCS codes across all body sites (beyond the
    # 4 core IV-route prefixes used in config). Included as reference-only codes
    # to surface coverage gaps.
    pcs_xlsx_additional = c(
      # Section 3E0 -- Introduction routes beyond the 4 core prefixes
      "3E00X05",  # Skin/Mucous Membranes, External
      "3E00X0M",  # Skin/Mucous Membranes, Monoclonal Antibody, External
      "3E01305",  # Subcutaneous Tissue, Percutaneous
      "3E0130M",  # Subcutaneous Tissue, Monoclonal Antibody, Percutaneous
      "3E02305",  # Muscle, Percutaneous
      "3E0230M",  # Muscle, Monoclonal Antibody, Percutaneous
      "3E03005",  # Peripheral Vein, Open
      "3E0300M",  # Peripheral Vein, Monoclonal Antibody, Open
      "3E0330M",  # Peripheral Vein, Monoclonal Antibody, Percutaneous
      "3E04005",  # Central Vein, Open
      "3E0400M",  # Central Vein, Monoclonal Antibody, Open
      "3E0430M",  # Central Vein, Monoclonal Antibody, Percutaneous
      "3E05005",  # Peripheral Artery, Open
      "3E0500M",  # Peripheral Artery, Monoclonal Antibody, Open
      "3E0530M",  # Peripheral Artery, Monoclonal Antibody, Percutaneous
      "3E06005",  # Central Artery, Open
      "3E0600M",  # Central Artery, Monoclonal Antibody, Open
      "3E06305",  # Central Artery, Percutaneous (also in core prefixes)
      "3E0630M",  # Central Artery, Monoclonal Antibody, Percutaneous
      "3E07005",  # Coronary Artery, Open
      "3E0700M",  # Coronary Artery, Monoclonal Antibody, Open
      "3E07305",  # Coronary Artery, Percutaneous
      "3E0730M",  # Coronary Artery, Monoclonal Antibody, Percutaneous
      "3E08305",  # Heart, Percutaneous
      "3E0830M",  # Heart, Monoclonal Antibody, Percutaneous
      "3E09005",  # Nose, Open
      "3E09705",  # Nose, Via Natural/Artificial Opening
      "3E0A305",  # Bone Marrow, Percutaneous
      "3E0A30M",  # Bone Marrow, Monoclonal Antibody, Percutaneous
      "3E0B305",  # Ear, Percutaneous
      "3E0B705",  # Ear, Via Natural/Artificial Opening
      "3E0C305",  # Eye, Percutaneous
      "3E0D305",  # Mouth/Pharynx, Percutaneous
      "3E0D705",  # Mouth/Pharynx, Via Natural/Artificial Opening
      "3E0D805",  # Mouth/Pharynx, Via Natural/Artificial Opening Endoscopic
      "3E0E005",  # Respiratory Tract, Open
      "3E0E305",  # Respiratory Tract, Percutaneous
      "3E0E705",  # Respiratory Tract, Via Natural/Artificial Opening
      "3E0E7JM",  # Respiratory Tract, Monoclonal Antibody
      "3E0E805",  # Respiratory Tract, Via Natural/Artificial Opening Endoscopic
      "3E0F305",  # Gastrointestinal Tract, Percutaneous
      "3E0F705",  # Gastrointestinal Tract, Via Natural/Artificial Opening
      "3E0F805",  # Gastrointestinal Tract, Endoscopic
      "3E0G305",  # Upper GI, Percutaneous
      "3E0G705",  # Upper GI, Via Natural/Artificial Opening
      "3E0G805",  # Upper GI, Endoscopic
      "3E0H305",  # Upper GI Mucosa, Percutaneous
      "3E0H705",  # Upper GI Mucosa, Via Natural/Artificial Opening
      "3E0H805",  # Upper GI Mucosa, Endoscopic
      "3E0J305",  # Biliary/Pancreatic Tract, Percutaneous
      "3E0J705",  # Biliary/Pancreatic Tract, Via Natural/Artificial Opening
      "3E0J805",  # Biliary/Pancreatic Tract, Endoscopic
      "3E0K305",  # Genitourinary Tract, Percutaneous
      "3E0K705",  # Genitourinary Tract, Via Natural/Artificial Opening
      "3E0K805",  # Genitourinary Tract, Endoscopic
      "3E0L305",  # Pleural Cavity, Percutaneous
      "3E0M305",  # Peritoneal Cavity, Percutaneous
      "3E0N305",  # Female Reproductive, Percutaneous
      "3E0N705",  # Female Reproductive, Via Natural/Artificial Opening
      "3E0N805",  # Female Reproductive, Endoscopic
      "3E0P305",  # Male Reproductive, Percutaneous
      "3E0P705",  # Male Reproductive, Via Natural/Artificial Opening
      "3E0Q005",  # Cranial Cavity/Brain, Open
      "3E0Q00M",  # Cranial Cavity/Brain, Monoclonal Antibody, Open
      "3E0Q305",  # Cranial Cavity/Brain, Percutaneous
      "3E0Q30M",  # Cranial Cavity/Brain, Monoclonal Antibody, Percutaneous
      "3E0Q705",  # Cranial Cavity/Brain, Via Natural/Artificial Opening
      "3E0Q70M",  # Cranial Cavity/Brain, Monoclonal Antibody, Via Natural Opening
      "3E0R305",  # Spinal Canal, Percutaneous
      "3E0R30M",  # Spinal Canal, Monoclonal Antibody, Percutaneous
      "3E0S305",  # Epidural Space, Percutaneous
      "3E0S30M",  # Epidural Space, Monoclonal Antibody, Percutaneous
      "3E0U305",  # Joints, Percutaneous
      "3E0U30M",  # Joints, Monoclonal Antibody, Percutaneous
      "3E0V305",  # Bones, Percutaneous
      "3E0V30M",  # Bones, Monoclonal Antibody, Percutaneous
      "3E0W305",  # Lymphatics, Percutaneous
      "3E0W30M",  # Lymphatics, Monoclonal Antibody, Percutaneous
      "3E0Y305",  # Pericardial Cavity, Percutaneous
      "3E0Y30M",  # Pericardial Cavity, Monoclonal Antibody, Percutaneous
      "3E0Y705",  # Pericardial Cavity, Via Natural/Artificial Opening
      "3E0Y70M"   # Pericardial Cavity, Monoclonal Antibody, Via Natural Opening
    ),

    # MS-DRG codes -- Source: MSDRGs.xlsx + TreatmentVariables_2024.07.17.docx
    drg_codes = c(
      "837",   # Chemo w acute leukemia as SDx or high-dose chemo agent w MCC
      "838",   # Chemo w acute leukemia as SDx w CC or high-dose chemo agent
      "839",   # Chemo w acute leukemia as SDx w/o CC/MCC
      "846",   # Chemo w hematologic malignancy as SDx w MCC
      "847",   # Chemo w hematologic malignancy as SDx w CC
      "848"    # Chemo w hematologic malignancy as SDx w/o CC/MCC
    ),

    # Revenue codes -- TreatmentVariables_2024.07.17.docx
    revenue_codes = c(
      "0331",   # Chemo - injected
      "0332",   # Chemo - oral
      "0335"    # Chemo - IV push
    )
  ),

  # ============================================================================
  # RADIATION
  # ============================================================================
  # Source: TreatmentVariables_2024.07.17.docx -- specifies CPT 70010-79999
  #   as "radiology CPT codes" (full AMA radiology chapter range).
  # Source: Treatment_Variable_Documentation.docx -- specifies same range,
  #   adds ICD-10-CM Z51.0 encounter code, explicitly lists ICD-9 and
  #   ICD-10-PCS Section D prefixes.
  # Source: MSDRGs.xlsx -- DRG 849 (type = "rad")
  # Note: No radiation codes appear in PCS Codes Cancer Tx.xlsx or
  #   ComprehensiveSurgeryCodes.xlsx (those files contain chemo PCS and
  #   surgical/cancer-site codes respectively).
  radiation = list(

    # CPT range -- D-04/D-05: Range-level narrative only (not individual codes)
    # Docx specifies: 70010-79999 (full AMA radiology chapter)
    # Config covers:  77261-77799 (radiation oncology sub-chapter only)
    # Phase 45 audit confirmed: codes outside 77261-77799 are diagnostic imaging
    # or nuclear medicine -- not radiation treatment. See radiation_cpt_range_narrative.
    cpt_range_narrative = list(
      list(
        docx_says     = "CPT 70010-79999 (full AMA radiology chapter)",
        config_covers = "CPT 77261-77799 (radiation oncology sub-chapter, 63 codes post-Phase-45)",
        gap           = "70010-77260, 77800-79999",
        rationale     = paste0(
          "AMA CPT chapter structure: 70010-76499 = Diagnostic Radiology; ",
          "76506-76999 = Diagnostic Ultrasound; 77001-77067 = Radiological Guidance; ",
          "77261-77799 = Radiation Oncology (only therapeutic radiation); ",
          "78000-78999 = Nuclear Medicine. ",
          "Phase 45 audit confirmed: all radiation treatment codes found in PROCEDURES ",
          "data fall within 77261-77799. Exclusion of 70010-77260 and 77800-79999 is intentional."
        )
      )
    ),

    # ICD-9-CM procedure codes -- TreatmentVariables_2024.07.17.docx
    icd9_codes = c(
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

    # ICD-10-PCS prefixes (Section D = Radiation Therapy)
    # TreatmentVariables_2024.07.17.docx + Treatment_Variable_Documentation.docx:
    # Section D, Body System 7 (Lymphatic and Hematologic System)
    icd10pcs_prefixes = c(
      "D70",   # Beam Radiation, lymphatic/hematologic
      "D71",   # Brachytherapy, lymphatic/hematologic
      "D72",   # Stereotactic Radiosurgery, lymphatic/hematologic
      "D7Y"    # Other Radiation, lymphatic/hematologic
    ),

    # ICD-10-CM encounter codes -- Treatment_Variable_Documentation.docx
    dx_icd10 = c(
      "Z51.0"    # Encounter for antineoplastic radiation therapy
    ),

    # ICD-9-CM diagnosis codes -- TreatmentVariables_2024.07.17.docx
    dx_icd9 = c(
      "V58.0"    # Encounter for radiotherapy
    ),

    # MS-DRG codes -- Source: MSDRGs.xlsx + TreatmentVariables_2024.07.17.docx
    drg_codes = c(
      "849"    # Radiotherapy
    ),

    # Revenue codes -- TreatmentVariables_2024.07.17.docx
    revenue_codes = c(
      "0330",   # Therapeutic radiology (general classification)
      "0333"    # Radiation therapy
    )
  ),

  # ============================================================================
  # SCT (Stem Cell Transplant)
  # ============================================================================
  # Source: TreatmentVariables_2024.07.17.docx -- CPT codes 38230-38243,
  #   HCPCS S2140/S2142/S2150, ICD-9-CM 41.0x, ICD-10-PCS Section 302xx,
  #   DRG 014/016/017.
  # Source: Treatment_Variable_Documentation.docx -- confirms same codes,
  #   adds omidubicel new technology codes (XW1xx).
  # Source: MSDRGs.xlsx -- DRG 014, 016, 017 (type = "SCT")
  # Source: ComprehensiveSurgeryCodes.xlsx -- contains surgical ICD-9 codes
  #   like 41.xx (bone marrow harvest/transplant). These overlap with sct_icd9.
  sct = list(

    # CPT codes -- TreatmentVariables_2024.07.17.docx
    cpt_codes = c(
      "38230",   # Bone marrow harvesting (Python pipeline)
      "38232",   # Bone marrow harvesting (Python pipeline)
      "38240",   # Allogeneic HPC transplantation
      "38241",   # Autologous HPC transplantation
      "38242",   # Allogeneic donor lymphocyte infusion (DLI)
      "38243"    # Allogeneic HPC boost
    ),

    # HCPCS S-codes -- TreatmentVariables_2024.07.17.docx
    hcpcs_codes = c(
      "S2140",   # Cord blood harvesting for transplantation, allogeneic
      "S2142",   # Cord blood-derived stem-cell transplantation, allogeneic
      "S2150"    # Bone marrow or blood-derived stem cells; allogeneic or autologous
    ),

    # ICD-9-CM procedure codes -- TreatmentVariables_2024.07.17.docx
    icd9_codes = c(
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

    # ICD-10-PCS codes -- TreatmentVariables_2024.07.17.docx + Treatment_Variable_Documentation.docx
    # Section 302xx = Administration/Transfusion/Hematopoietic Stem Cells
    # Config uses exact 7-char codes (not prefix matching, per established decision)
    icd10pcs_codes = c(
      # Open approach (0) -- peripheral vein
      "30230C0",  # Autologous HPC (genetically modified), peripheral vein, open
      "30230G0",  # Autologous bone marrow, peripheral vein, open
      "30230X0",  # Autologous cord blood stem cells, peripheral vein, open
      "30230Y0",  # Autologous HPC, peripheral vein, open
      # Open approach (0) -- central vein
      "30240C0",  # Autologous HPC (genetically modified), central vein, open
      "30240G0",  # Autologous bone marrow, central vein, open
      "30240X0",  # Autologous cord blood stem cells, central vein, open
      "30240Y0",  # Autologous HPC, central vein, open
      # Percutaneous approach (3) -- peripheral vein, autologous
      "30233C0",  # Autologous HPC (genetically modified), peripheral vein, percutaneous
      "30233G0",  # Autologous HPC, peripheral vein, percutaneous
      "30233X0",  # Autologous cord blood stem cells, peripheral vein, percutaneous
      "30233Y0",  # Autologous HPC (other), peripheral vein, percutaneous
      # Percutaneous approach (3) -- central vein, autologous
      "30243C0",  # Autologous HPC (genetically modified), central vein, percutaneous
      "30243G0",  # Autologous HPC, central vein, percutaneous
      "30243X0",  # Autologous cord blood stem cells, central vein, percutaneous
      "30243Y0",  # Autologous HPC (other), central vein, percutaneous
      # Nonautologous (1) -- peripheral and central vein, percutaneous
      "30233G1",  # Nonautologous HPC, peripheral vein, percutaneous
      "30233X1",  # Nonautologous cord blood stem cells, peripheral vein, percutaneous
      "30233Y1",  # Nonautologous HPC (other), peripheral vein, percutaneous
      "30243G1",  # Nonautologous HPC, central vein, percutaneous
      "30243X1",  # Nonautologous cord blood stem cells, central vein, percutaneous
      "30243Y1",  # Nonautologous HPC (other), central vein, percutaneous
      # Allogeneic related (2) and unrelated (3) -- peripheral vein
      "30233G2",  # Allogeneic related bone marrow, peripheral vein, percutaneous
      "30233G3",  # Allogeneic unrelated bone marrow, peripheral vein, percutaneous
      "30233U2",  # Allogeneic related T-cell depleted bone marrow, peripheral vein
      "30233U3",  # Allogeneic unrelated T-cell depleted bone marrow, peripheral vein
      "30233X2",  # Allogeneic related cord blood stem cells, peripheral vein
      "30233X3",  # Allogeneic unrelated cord blood stem cells, peripheral vein
      "30233Y2",  # Allogeneic related HPC, peripheral vein, percutaneous
      "30233Y3",  # Allogeneic unrelated HPC, peripheral vein, percutaneous
      # Allogeneic related (2) and unrelated (3) -- central vein
      "30243G2",  # Allogeneic related bone marrow, central vein, percutaneous
      "30243G3",  # Allogeneic unrelated bone marrow, central vein, percutaneous
      "30243U2",  # Allogeneic related T-cell depleted bone marrow, central vein
      "30243U3",  # Allogeneic unrelated T-cell depleted bone marrow, central vein
      "30243X2",  # Allogeneic related cord blood stem cells, central vein
      "30243X3",  # Allogeneic unrelated cord blood stem cells, central vein
      "30243Y2",  # Allogeneic related HPC, central vein, percutaneous
      "30243Y3",  # Allogeneic unrelated HPC, central vein, percutaneous
      # Embryonic stem cells
      "30230AZ",  # Embryonic stem cells, peripheral vein, open
      "30233AZ",  # Embryonic stem cells, peripheral vein, percutaneous
      "30240AZ",  # Embryonic stem cells, central vein, open
      "30243AZ",  # Embryonic stem cells, central vein, percutaneous
      # New technology (XW1xx) -- Omidubicel (Treatment_Variable_Documentation.docx)
      "XW133C8",  # Transfusion of Omidubicel into Peripheral Vein, Percutaneous Approach
      "XW143C8"   # Transfusion of Omidubicel into Central Vein, Percutaneous Approach
    ),

    # MS-DRG codes -- Source: MSDRGs.xlsx + TreatmentVariables_2024.07.17.docx
    drg_codes = c(
      "014",   # Allogeneic bone marrow transplant
      "016",   # Autologous BMT w CC/MCC or T-cell immunotherapy
      "017"    # Autologous BMT w/o CC/MCC
    ),

    # Revenue codes -- TreatmentVariables_2024.07.17.docx
    revenue_codes = c(
      "0362",   # Organ transplant - other than kidney (includes SCT)
      "0815"    # Allogeneic stem cell acquisition/donor services
    )
  ),

  # ============================================================================
  # IMMUNOTHERAPY (CAR T and related)
  # ============================================================================
  # Source: TreatmentVariables_2024.07.17.docx -- ICD-10-PCS XW03x codes
  #   for CAR T-cell immunotherapy (Section X New Technology).
  # Source: Treatment_Variable_Documentation.docx -- adds DRG 018, confirms
  #   XW prefix codes for CAR T.
  # Note: ComprehensiveSurgeryCodes.xlsx and PCS Codes Cancer Tx.xlsx do not
  #   contain immunotherapy-specific codes.
  immunotherapy = list(

    # ICD-10-PCS XW prefix codes -- TreatmentVariables_2024.07.17.docx
    # Config stores as exact 7-char codes (called "prefixes" in config naming)
    cart_icd10pcs = c(
      "XW033C7",  # Autologous engineered CAR T-cell, peripheral vein
      "XW033G7",  # Allogeneic engineered CAR T-cell, peripheral vein
      "XW033H7",  # Axicabtagene ciloleucel, peripheral vein
      "XW033J7",  # Tisagenlecleucel immunotherapy, peripheral vein
      "XW033K7",  # Idecabtagene vicleucel immunotherapy, peripheral vein
      "XW033L7",  # Lifileucel immunotherapy, peripheral vein
      "XW033M7",  # Brexucabtagene autoleucel, peripheral vein
      "XW033N7",  # Lisocabtagene maraleucel, peripheral vein
      "XW043C7",  # Autologous engineered CAR T-cell, central vein
      "XW043G7",  # Allogeneic engineered CAR T-cell, central vein
      "XW043H7",  # Axicabtagene ciloleucel, central vein
      "XW043J7",  # Tisagenlecleucel immunotherapy, central vein
      "XW043K7",  # Idecabtagene vicleucel immunotherapy, central vein
      "XW043L7",  # Lifileucel immunotherapy, central vein
      "XW043M7",  # Brexucabtagene autoleucel, central vein
      "XW043N7"   # Lisocabtagene maraleucel, central vein
    ),

    # DRG codes -- Treatment_Variable_Documentation.docx + MSDRGs.xlsx context
    # Note: DRG 018 is T-cell immunotherapy DRG, defined in TREATMENT_CODES$immunotherapy_drg.
    drg_codes = c(
      "018"    # Chimeric antigen receptor T-cell immunotherapy
    )
  )
)

# ==============================================================================
# SECTION 3: PHASE 45 ANNOTATION VECTOR
# ==============================================================================
# D-13: These 42 codes were added via Phase 45 audit (commit f4de3c5) after
# confirming they appear in PROCEDURES data as radiation treatment codes.
# They appear in config but not in the original reference documents (which
# predate the Phase 45 expansion). They should be annotated, not flagged as gaps.

PHASE45_ADDED_CODES <- c(
  # Treatment Planning (77261-77299) -- all added Phase 45
  "77261", "77262", "77263", "77280", "77285", "77290", "77293",
  # Physics, Dosimetry & Treatment Devices (77295-77370) -- all added Phase 45
  "77295", "77300", "77301", "77306", "77307", "77310", "77315",
  "77316", "77318", "77321", "77331", "77332", "77333", "77334",
  "77336", "77338", "77370",
  # Treatment Delivery (77371-77499) -- added Phase 45
  "77371", "77372", "77373", "77385", "77386", "77387", "77399",
  "77407", "77412", "77427",
  # Proton Beam -- added Phase 45
  "77525",
  # Hyperthermia -- added Phase 45
  "77605",
  # Brachytherapy -- added Phase 45
  "77750", "77763", "77768", "77770", "77771", "77772", "77785",
  # CMS G-codes -- added Phase 45
  "G6012", "G6013", "G6015"
)

message(glue("Reference data loaded: {length(PHASE45_ADDED_CODES)} Phase 45 annotation codes"))

# ==============================================================================
# SECTION 4: COMPARISON FUNCTIONS
# ==============================================================================

#' Compare two code lists and return both directions of set difference.
#' @param reference_codes Character vector of reference document codes
#' @param config_codes Character vector of pipeline config codes
#' @return Named list: in_ref_not_config, in_config_not_ref
compare_code_lists <- function(reference_codes, config_codes) {
  list(
    in_ref_not_config = setdiff(reference_codes, config_codes),
    in_config_not_ref = setdiff(config_codes, reference_codes)
  )
}

#' Build a gap tibble from comparison results.
#' @param comparison Result from compare_code_lists()
#' @param code_category Label for this code category (e.g., "HCPCS J-codes")
#' @param source_document Source reference document name
#' @return tibble with columns: code, direction, code_category, source_document, annotation
build_gap_tibble <- function(comparison, code_category, source_document) {
  rows <- list()

  if (length(comparison$in_ref_not_config) > 0) {
    rows[[1]] <- tibble::tibble(
      code            = comparison$in_ref_not_config,
      direction       = "In Reference, Not Config",
      code_category   = code_category,
      source_document = source_document,
      annotation      = NA_character_
    )
  }

  if (length(comparison$in_config_not_ref) > 0) {
    annotation_vals <- ifelse(
      comparison$in_config_not_ref %in% PHASE45_ADDED_CODES,
      "Added via Phase 45 audit -- confirmed treatment codes in patient data",
      NA_character_
    )
    rows[[2]] <- tibble::tibble(
      code            = comparison$in_config_not_ref,
      direction       = "In Config, Not Reference",
      code_category   = code_category,
      source_document = source_document,
      annotation      = annotation_vals
    )
  }

  if (length(rows) == 0) return(tibble::tibble(
    code = character(), direction = character(), code_category = character(),
    source_document = character(), annotation = character()
  ))

  dplyr::bind_rows(rows)
}

# ==============================================================================
# SECTION 5: RUN COMPARISONS
# ==============================================================================

message("Running code list comparisons...")

# ---------------------------------------------------------------------------
# CHEMOTHERAPY GAPS
# ---------------------------------------------------------------------------
chemo_gaps <- dplyr::bind_rows(
  # HCPCS J-codes: reference specifies 6 original codes; config has 96
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$chemotherapy$hcpcs_jcodes, TREATMENT_CODES$chemo_hcpcs),
    "HCPCS J-codes", "TreatmentVariables_2024.07.17.docx"
  ),
  # Q-codes: reference specifies Q0083-Q0085; config does not have these
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$chemotherapy$q_codes, TREATMENT_CODES$chemo_hcpcs),
    "HCPCS Q-codes (admin)", "Treatment_Variable_Documentation.docx"
  ),
  # ICD-9 procedure codes
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$chemotherapy$icd9_codes, TREATMENT_CODES$chemo_icd9),
    "ICD-9-CM procedure codes", "TreatmentVariables_2024.07.17.docx"
  ),
  # ICD-10-PCS prefixes (core 4 IV-route prefixes)
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$chemotherapy$icd10pcs_prefixes, TREATMENT_CODES$chemo_icd10pcs_prefixes),
    "ICD-10-PCS prefixes (core 4)", "TreatmentVariables_2024.07.17.docx"
  ),
  # DRG codes
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$chemotherapy$drg_codes, TREATMENT_CODES$chemo_drg),
    "MS-DRG codes", "MSDRGs.xlsx / TreatmentVariables_2024.07.17.docx"
  ),
  # Revenue codes
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$chemotherapy$revenue_codes, TREATMENT_CODES$chemo_revenue),
    "Revenue codes", "TreatmentVariables_2024.07.17.docx"
  ),
  # PCS Codes Cancer Tx.xlsx additional codes (beyond the 4 core prefixes)
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$chemotherapy$pcs_xlsx_additional, TREATMENT_CODES$chemo_icd10pcs_prefixes),
    "ICD-10-PCS (PCS Codes Cancer Tx.xlsx -- 80 additional routes)", "PCS Codes Cancer Tx.xlsx"
  )
)

# Add RxNorm note row (D-14 note: RxNorm not in reference docs)
rxnorm_note <- tibble::tibble(
  code            = NA_character_,
  direction       = "Config Only (Not in Reference Scope)",
  code_category   = "RxNorm CUIs",
  source_document = "N/A",
  annotation      = glue("RxNorm CUIs: {length(TREATMENT_CODES$chemo_rxnorm)} codes in config; ",
                          "not specified in reference documents (drug lookup-derived, Phase 40)")
)
chemo_gaps <- dplyr::bind_rows(chemo_gaps, rxnorm_note)

message(glue("  Chemotherapy: {nrow(chemo_gaps)} gap rows"))

# ---------------------------------------------------------------------------
# RADIATION GAPS
# ---------------------------------------------------------------------------
# D-04/D-05: CPT range compared at range level only (narrative row, no setdiff)
# Individual CPT codes in config (77261-77799) are compared against what
# the reference documents would list IF they enumerated individual codes.
# Since reference says "70010-79999" as a range, we produce a narrative.

# For non-CPT code categories, run direct setdiff comparisons:
radiation_gaps <- dplyr::bind_rows(
  # ICD-9 codes
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$radiation$icd9_codes, TREATMENT_CODES$radiation_icd9),
    "ICD-9-CM procedure codes", "TreatmentVariables_2024.07.17.docx"
  ),
  # ICD-10-PCS prefixes
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$radiation$icd10pcs_prefixes, TREATMENT_CODES$radiation_icd10pcs_prefixes),
    "ICD-10-PCS prefixes (Section D)", "TreatmentVariables_2024.07.17.docx"
  ),
  # ICD-10-CM encounter codes (Z51.0 is in config as radiation_dx_icd10)
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$radiation$dx_icd10, TREATMENT_CODES$radiation_dx_icd10),
    "ICD-10-CM encounter codes (Z-codes)", "Treatment_Variable_Documentation.docx"
  ),
  # ICD-9-CM diagnosis codes (V58.0)
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$radiation$dx_icd9, TREATMENT_CODES$radiation_dx_icd9),
    "ICD-9-CM diagnosis codes (V-codes)", "TreatmentVariables_2024.07.17.docx"
  ),
  # DRG codes
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$radiation$drg_codes, TREATMENT_CODES$radiation_drg),
    "MS-DRG codes", "MSDRGs.xlsx / TreatmentVariables_2024.07.17.docx"
  ),
  # Revenue codes
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$radiation$revenue_codes, TREATMENT_CODES$radiation_revenue),
    "Revenue codes", "TreatmentVariables_2024.07.17.docx"
  )
)

# Add CPT range narrative row (D-04/D-05)
rng <- REFERENCE_CODES$radiation$cpt_range_narrative[[1]]
cpt_narrative_row <- tibble::tibble(
  code            = NA_character_,
  direction       = "Range-Level Comparison (D-04/D-05)",
  code_category   = "CPT codes",
  source_document = "TreatmentVariables_2024.07.17.docx",
  annotation      = glue(
    "RANGE NARRATIVE: {rng$docx_says}. ",
    "Config covers: {rng$config_covers}. ",
    "Gap rationale: {rng$rationale}"
  )
)
radiation_gaps <- dplyr::bind_rows(cpt_narrative_row, radiation_gaps)

# Add Phase 45 config codes that are config-only vs. the reference range
# (These would appear as "config not in reference" for CPT, but since we
# compare at range level, we add a summary annotation row instead)
phase45_annotation_row <- tibble::tibble(
  code            = NA_character_,
  direction       = "Config Only (Phase 45 Audit Additions)",
  code_category   = "CPT codes",
  source_document = "Phase 45 audit (R/45b_radiation_cpt_audit.R)",
  annotation      = glue(
    "Phase 45 audit added {length(PHASE45_ADDED_CODES)} radiation CPT codes ",
    "({sum(str_detect(PHASE45_ADDED_CODES, '^G'))} G-codes, ",
    "{sum(!str_detect(PHASE45_ADDED_CODES, '^G'))} CPT codes). ",
    "All confirmed as radiation treatment codes present in PROCEDURES data. ",
    "Total config radiation_cpt codes: {length(TREATMENT_CODES$radiation_cpt)}."
  )
)
radiation_gaps <- dplyr::bind_rows(radiation_gaps, phase45_annotation_row)

message(glue("  Radiation: {nrow(radiation_gaps)} gap rows"))

# ---------------------------------------------------------------------------
# SCT GAPS
# ---------------------------------------------------------------------------
sct_gaps <- dplyr::bind_rows(
  # CPT codes
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$sct$cpt_codes, TREATMENT_CODES$sct_cpt),
    "CPT codes", "TreatmentVariables_2024.07.17.docx"
  ),
  # HCPCS S-codes
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$sct$hcpcs_codes, TREATMENT_CODES$sct_hcpcs),
    "HCPCS S-codes", "TreatmentVariables_2024.07.17.docx"
  ),
  # ICD-9 codes
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$sct$icd9_codes, TREATMENT_CODES$sct_icd9),
    "ICD-9-CM procedure codes", "TreatmentVariables_2024.07.17.docx"
  ),
  # ICD-10-PCS codes (exact 7-char)
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$sct$icd10pcs_codes, TREATMENT_CODES$sct_icd10pcs),
    "ICD-10-PCS codes (7-char exact)", "TreatmentVariables_2024.07.17.docx / Treatment_Variable_Documentation.docx"
  ),
  # DRG codes
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$sct$drg_codes, TREATMENT_CODES$sct_drg),
    "MS-DRG codes", "MSDRGs.xlsx / TreatmentVariables_2024.07.17.docx"
  ),
  # Revenue codes
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$sct$revenue_codes, TREATMENT_CODES$sct_revenue),
    "Revenue codes", "TreatmentVariables_2024.07.17.docx"
  )
)

message(glue("  SCT: {nrow(sct_gaps)} gap rows"))

# ---------------------------------------------------------------------------
# IMMUNOTHERAPY GAPS
# ---------------------------------------------------------------------------
# immunotherapy_drg from TREATMENT_CODES (DRG 018 = CAR T-cell immunotherapy)
immuno_drg_config <- TREATMENT_CODES$immunotherapy_drg

immuno_gaps <- dplyr::bind_rows(
  # CAR T ICD-10-PCS codes
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$immunotherapy$cart_icd10pcs, TREATMENT_CODES$cart_icd10pcs_prefixes),
    "ICD-10-PCS XW codes (CAR T)", "TreatmentVariables_2024.07.17.docx"
  ),
  # DRG codes
  build_gap_tibble(
    compare_code_lists(REFERENCE_CODES$immunotherapy$drg_codes, immuno_drg_config),
    "MS-DRG codes", "Treatment_Variable_Documentation.docx"
  )
)

message(glue("  Immunotherapy: {nrow(immuno_gaps)} gap rows"))

# ==============================================================================
# SECTION 6: DUCKDB PATIENT/ENCOUNTER COUNTS (D-14)
# ==============================================================================
# For "In Reference, Not Config" codes (actual gaps): query PROCEDURES to get
# patient_count and encounter_count. These show whether gap codes appear in data.

message("Querying PROCEDURES for patient/encounter counts on gap codes...")

# Collect all unique gap codes (direction = "In Reference, Not Config")
# Only meaningful for PROCEDURES-searchable codes (CPT, HCPCS, ICD-9, ICD-10-PCS)
all_gaps <- dplyr::bind_rows(
  chemo_gaps, radiation_gaps, sct_gaps, immuno_gaps
)

gap_codes_to_query <- all_gaps %>%
  dplyr::filter(
    direction == "In Reference, Not Config",
    !is.na(code),
    nchar(code) > 0
  ) %>%
  dplyr::distinct(code) %>%
  dplyr::pull(code)

if (length(gap_codes_to_query) > 0) {
  message(glue("  Querying {length(gap_codes_to_query)} gap codes in PROCEDURES..."))

  proc_counts <- tryCatch({
    get_pcornet_table("PROCEDURES") %>%
      dplyr::filter(PX %in% gap_codes_to_query) %>%
      dplyr::group_by(code = PX) %>%
      dplyr::summarise(
        patient_count   = dplyr::n_distinct(ID),
        encounter_count = dplyr::n(),
        .groups = "drop"
      ) %>%
      dplyr::collect()
  }, error = function(e) {
    message(glue("  WARNING: PROCEDURES query failed: {e$message}"))
    message("  Patient/encounter counts will not be available.")
    tibble::tibble(code = character(), patient_count = integer(), encounter_count = integer())
  })

  message(glue("  Found {nrow(proc_counts)} gap codes with data in PROCEDURES"))
} else {
  message("  No gap codes to query (all reference codes already in config)")
  proc_counts <- tibble::tibble(code = character(), patient_count = integer(), encounter_count = integer())
}

# Join counts onto gap tibbles
add_counts <- function(gaps_df) {
  gaps_df %>%
    dplyr::left_join(proc_counts, by = "code") %>%
    dplyr::mutate(
      # For "In Reference, Not Config" rows: coalesce NA to 0 (code exists in
      # reference but had 0 occurrences in PROCEDURES -- still a real count)
      patient_count   = dplyr::if_else(direction != "In Reference, Not Config",
                                        NA_integer_,
                                        dplyr::coalesce(patient_count, 0L)),
      encounter_count = dplyr::if_else(direction != "In Reference, Not Config",
                                        NA_integer_,
                                        dplyr::coalesce(encounter_count, 0L))
    )
}

chemo_gaps_final    <- add_counts(chemo_gaps)
radiation_gaps_final <- add_counts(radiation_gaps)
sct_gaps_final      <- add_counts(sct_gaps)
immuno_gaps_final   <- add_counts(immuno_gaps)

# ==============================================================================
# SECTION 7: STYLED XLSX OUTPUT (D-11)
# ==============================================================================

message(glue("Writing styled xlsx to {OUTPUT_PATH}..."))

# Color scheme (consistent with project patterns from Phase 44/45)
DARK_HEADER_FILL  <- "FF374151"
WHITE_FONT        <- "FFFFFFFF"
TITLE_FONT_COLOR  <- "FF1F2937"
# Direction-based row colors
IN_REF_NOT_CONFIG_FILL <- "FFFCE4EC"   # Light pink -- reference has it, config doesn't
IN_CONFIG_NOT_REF_FILL <- "FFE8F5E9"   # Light green -- config has it, reference doesn't
CONFIG_ONLY_FILL       <- "FFFEF9E7"   # Light yellow -- config-only notes (RxNorm, Phase 45)
NARRATIVE_FILL         <- "FFF3E5F5"   # Light purple -- range narrative rows
ANNOTATION_FILL        <- "FFFBE9E7"   # Light orange -- Phase 45 annotations
PHASE45_FILL           <- "FFF1F8E9"   # Very light green -- Phase 45 added codes

SHEET_COLORS <- list(
  chemotherapy  = list(fill = "FFD32F2F", font = "FFFFFFFF"),   # Red
  radiation     = list(fill = "FF1565C0", font = "FFFFFFFF"),   # Blue
  sct           = list(fill = "FF2E7D32", font = "FFFFFFFF"),   # Green
  immunotherapy = list(fill = "FF6A1B9A", font = "FFFFFFFF")    # Purple
)

# Column headers for detail sheets
DETAIL_HEADERS <- c("Code", "Direction", "Code Category", "Source Document",
                     "Patient Count", "Encounter Count", "Annotation")
N_DETAIL_COLS <- length(DETAIL_HEADERS)

# Helper to write a detail sheet
write_detail_sheet <- function(wb, sheet_name, gaps_df, type_label, colors) {

  wb$add_worksheet(sheet_name)

  # Row 1: Title
  title_text <- glue("Treatment Code Cross-Reference: {type_label}")
  wb$add_data(sheet = sheet_name, x = as.character(title_text),
              start_row = 1, start_col = 1)
  wb$add_font(sheet = sheet_name, dims = "A1",
              name = "Calibri", size = 16, bold = TRUE, color = wb_color(TITLE_FONT_COLOR))
  wb$merge_cells(sheet = sheet_name, dims = glue("A1:{int2col(N_DETAIL_COLS)}1"))

  # Row 2: Type header bar
  subtitle <- glue(
    "{type_label} -- ",
    "{sum(gaps_df$direction == 'In Reference, Not Config', na.rm=TRUE)} in reference not config | ",
    "{sum(gaps_df$direction == 'In Config, Not Reference', na.rm=TRUE)} in config not reference"
  )
  wb$add_data(sheet = sheet_name, x = as.character(subtitle),
              start_row = 2, start_col = 1)
  wb$add_fill(sheet = sheet_name, dims = glue("A2:{int2col(N_DETAIL_COLS)}2"),
              color = wb_color(colors$fill))
  wb$add_font(sheet = sheet_name, dims = glue("A2:{int2col(N_DETAIL_COLS)}2"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color(colors$font))
  wb$merge_cells(sheet = sheet_name, dims = glue("A2:{int2col(N_DETAIL_COLS)}2"))

  # Row 3: Column headers
  for (i in seq_along(DETAIL_HEADERS)) {
    wb$add_data(sheet = sheet_name, x = DETAIL_HEADERS[i], start_row = 3, start_col = i)
  }
  wb$add_fill(sheet = sheet_name, dims = glue("A3:{int2col(N_DETAIL_COLS)}3"),
              color = wb_color(DARK_HEADER_FILL))
  wb$add_font(sheet = sheet_name, dims = glue("A3:{int2col(N_DETAIL_COLS)}3"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color(WHITE_FONT))

  # Rows 4+: Data
  write_df <- gaps_df %>%
    dplyr::mutate(
      patient_count_fmt   = dplyr::if_else(!is.na(patient_count),
                                           format(patient_count, big.mark = ","), ""),
      encounter_count_fmt = dplyr::if_else(!is.na(encounter_count),
                                           format(encounter_count, big.mark = ","), ""),
      annotation = dplyr::if_else(is.na(annotation), "", annotation),
      code       = dplyr::if_else(is.na(code), "", code)
    ) %>%
    dplyr::select(code, direction, code_category, source_document,
                  patient_count_fmt, encounter_count_fmt, annotation) %>%
    as.data.frame()

  if (nrow(write_df) > 0) {
    wb$add_data(sheet = sheet_name, x = write_df, start_row = 4, col_names = FALSE)

    # Conditional row coloring
    for (i in seq_len(nrow(write_df))) {
      row_i <- 3L + i
      row_dims <- glue("A{row_i}:{int2col(N_DETAIL_COLS)}{row_i}")
      dir_val <- write_df$direction[i]
      ann_val <- ifelse(is.na(write_df$annotation[i]), "", write_df$annotation[i])

      fill_color <- if (grepl("In Reference, Not Config", dir_val)) {
        IN_REF_NOT_CONFIG_FILL
      } else if (grepl("Phase 45 audit", ann_val)) {
        PHASE45_FILL
      } else if (grepl("In Config, Not Reference", dir_val)) {
        IN_CONFIG_NOT_REF_FILL
      } else if (grepl("Range-Level", dir_val)) {
        NARRATIVE_FILL
      } else {
        CONFIG_ONLY_FILL
      }

      wb$add_fill(sheet = sheet_name, dims = row_dims, color = wb_color(fill_color))
    }
  }

  # Column widths
  wb$set_col_widths(sheet = sheet_name, cols = 1:N_DETAIL_COLS,
                    widths = c(15, 28, 32, 38, 14, 16, 60))
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# Create workbook with 5 sheets
# ---------------------------------------------------------------------------

wb <- wb_workbook()

# ---------------------------------------------------------------------------
# Sheet 1: Summary
# ---------------------------------------------------------------------------

SHEET_SUMMARY <- "Summary"
wb$add_worksheet(SHEET_SUMMARY)

# Title
wb$add_data(sheet = SHEET_SUMMARY,
            x = "Treatment Code Cross-Reference: Summary",
            start_row = 1, start_col = 1)
wb$add_font(sheet = SHEET_SUMMARY, dims = "A1",
            name = "Calibri", size = 18, bold = TRUE, color = wb_color(TITLE_FONT_COLOR))
wb$merge_cells(sheet = SHEET_SUMMARY, dims = "A1:G1")

# Subtitle
wb$add_data(sheet = SHEET_SUMMARY,
            x = glue("Gap report comparing reference documents (docx + xlsx) against TREATMENT_CODES config. Generated: {Sys.Date()}"),
            start_row = 2, start_col = 1)
wb$merge_cells(sheet = SHEET_SUMMARY, dims = "A2:G2")
wb$add_font(sheet = SHEET_SUMMARY, dims = "A2",
            name = "Calibri", size = 10, color = wb_color("FF6B7280"))

# Section: Legend
legend_row <- 4L
wb$add_data(sheet = SHEET_SUMMARY, x = "COLOR LEGEND", start_row = legend_row, start_col = 1)
wb$add_font(sheet = SHEET_SUMMARY, dims = glue("A{legend_row}"),
            name = "Calibri", size = 11, bold = TRUE)
wb$add_fill(sheet = SHEET_SUMMARY,
            dims = glue("A{legend_row+1}:C{legend_row+1}"),
            color = wb_color(IN_REF_NOT_CONFIG_FILL))
wb$add_data(sheet = SHEET_SUMMARY, x = "In Reference, Not Config (potential addition to pipeline)",
            start_row = legend_row + 1, start_col = 1)
wb$merge_cells(sheet = SHEET_SUMMARY, dims = glue("A{legend_row+1}:G{legend_row+1}"))
wb$add_fill(sheet = SHEET_SUMMARY,
            dims = glue("A{legend_row+2}:C{legend_row+2}"),
            color = wb_color(IN_CONFIG_NOT_REF_FILL))
wb$add_data(sheet = SHEET_SUMMARY, x = "In Config, Not Reference (pipeline addition beyond original spec)",
            start_row = legend_row + 2, start_col = 1)
wb$merge_cells(sheet = SHEET_SUMMARY, dims = glue("A{legend_row+2}:G{legend_row+2}"))
wb$add_fill(sheet = SHEET_SUMMARY,
            dims = glue("A{legend_row+3}:C{legend_row+3}"),
            color = wb_color(PHASE45_FILL))
wb$add_data(sheet = SHEET_SUMMARY, x = "In Config, Not Reference -- Phase 45 audit addition (confirmed in patient data)",
            start_row = legend_row + 3, start_col = 1)
wb$merge_cells(sheet = SHEET_SUMMARY, dims = glue("A{legend_row+3}:G{legend_row+3}"))

# Section: Per-type summary table
summary_header_row <- legend_row + 5L
summary_headers <- c("Treatment Type", "In Ref Not Config", "In Config Not Ref",
                      "Phase 45 Annotated", "Config Codes", "Ref Code Count", "Notes")
for (i in seq_along(summary_headers)) {
  wb$add_data(sheet = SHEET_SUMMARY, x = summary_headers[i],
              start_row = summary_header_row, start_col = i)
}
wb$add_fill(sheet = SHEET_SUMMARY,
            dims = glue("A{summary_header_row}:{int2col(length(summary_headers))}{summary_header_row}"),
            color = wb_color(DARK_HEADER_FILL))
wb$add_font(sheet = SHEET_SUMMARY,
            dims = glue("A{summary_header_row}:{int2col(length(summary_headers))}{summary_header_row}"),
            name = "Calibri", size = 11, bold = TRUE, color = wb_color(WHITE_FONT))

# Summary data rows
summary_data <- list(
  c(
    "Chemotherapy",
    as.character(sum(chemo_gaps_final$direction == "In Reference, Not Config", na.rm=TRUE)),
    as.character(sum(chemo_gaps_final$direction == "In Config, Not Reference", na.rm=TRUE)),
    as.character(sum(chemo_gaps_final$direction == "In Config, Not Reference" &
                       !is.na(chemo_gaps_final$annotation) &
                       grepl("Phase 45", chemo_gaps_final$annotation), na.rm=TRUE)),
    as.character(length(TREATMENT_CODES$chemo_hcpcs)),
    as.character(length(REFERENCE_CODES$chemotherapy$hcpcs_jcodes)),
    glue("{length(TREATMENT_CODES$chemo_rxnorm)} RxNorm CUIs in config (not in reference docs -- drug-lookup derived)")
  ),
  c(
    "Radiation",
    as.character(sum(radiation_gaps_final$direction == "In Reference, Not Config", na.rm=TRUE)),
    as.character(sum(radiation_gaps_final$direction == "In Config, Not Reference", na.rm=TRUE)),
    as.character(sum(radiation_gaps_final$direction == "In Config, Not Reference" &
                       !is.na(radiation_gaps_final$annotation) &
                       grepl("Phase 45", radiation_gaps_final$annotation), na.rm=TRUE)),
    as.character(length(TREATMENT_CODES$radiation_cpt)),
    paste0("Range: 70010-79999"),
    glue("CPT compared at range level per D-04/D-05. {length(PHASE45_ADDED_CODES)} codes added via Phase 45 audit.")
  ),
  c(
    "SCT",
    as.character(sum(sct_gaps_final$direction == "In Reference, Not Config", na.rm=TRUE)),
    as.character(sum(sct_gaps_final$direction == "In Config, Not Reference", na.rm=TRUE)),
    as.character(sum(sct_gaps_final$direction == "In Config, Not Reference" &
                       !is.na(sct_gaps_final$annotation) &
                       grepl("Phase 45", sct_gaps_final$annotation), na.rm=TRUE)),
    as.character(length(TREATMENT_CODES$sct_cpt) + length(TREATMENT_CODES$sct_hcpcs) +
                   length(TREATMENT_CODES$sct_icd10pcs)),
    as.character(length(REFERENCE_CODES$sct$icd10pcs_codes)),
    "ICD-10-PCS uses exact 7-char matching (not prefix) per Phase 38 decision"
  ),
  c(
    "Immunotherapy",
    as.character(sum(immuno_gaps_final$direction == "In Reference, Not Config", na.rm=TRUE)),
    as.character(sum(immuno_gaps_final$direction == "In Config, Not Reference", na.rm=TRUE)),
    as.character(sum(immuno_gaps_final$direction == "In Config, Not Reference" &
                       !is.na(immuno_gaps_final$annotation) &
                       grepl("Phase 45", immuno_gaps_final$annotation), na.rm=TRUE)),
    as.character(length(TREATMENT_CODES$cart_icd10pcs_prefixes)),
    as.character(length(REFERENCE_CODES$immunotherapy$cart_icd10pcs)),
    "Config has 31 XW codes (Phase 39 expanded); reference specifies 16 core CAR T codes"
  )
)

summary_colors <- c(SHEET_COLORS$chemotherapy$fill, SHEET_COLORS$radiation$fill,
                     SHEET_COLORS$sct$fill, SHEET_COLORS$immunotherapy$fill)

for (i in seq_along(summary_data)) {
  row_i <- summary_header_row + i
  for (j in seq_along(summary_data[[i]])) {
    wb$add_data(sheet = SHEET_SUMMARY, x = summary_data[[i]][j],
                start_row = row_i, start_col = j)
  }
  wb$add_font(sheet = SHEET_SUMMARY,
              dims = glue("A{row_i}:{int2col(length(summary_headers))}{row_i}"),
              name = "Calibri", size = 10, bold = TRUE, color = wb_color("FFFFFFFF"))
  wb$add_fill(sheet = SHEET_SUMMARY,
              dims = glue("A{row_i}:{int2col(length(summary_headers))}{row_i}"),
              color = wb_color(summary_colors[i]))
}

# Radiation CPT range narrative section (D-04/D-05)
narrative_header_row <- summary_header_row + length(summary_data) + 2L
wb$add_data(sheet = SHEET_SUMMARY,
            x = "RADIATION CPT RANGE NARRATIVE (D-04/D-05)",
            start_row = narrative_header_row, start_col = 1)
wb$add_font(sheet = SHEET_SUMMARY, dims = glue("A{narrative_header_row}"),
            name = "Calibri", size = 12, bold = TRUE)
wb$merge_cells(sheet = SHEET_SUMMARY,
               dims = glue("A{narrative_header_row}:G{narrative_header_row}"))

rng <- REFERENCE_CODES$radiation$cpt_range_narrative[[1]]
narrative_text <- glue(
  "Reference documents specify: {rng$docx_says}.\n",
  "Pipeline config covers: {rng$config_covers}.\n",
  "Gap codes not in config: {rng$gap}.\n",
  "Rationale: {rng$rationale}"
)
wb$add_data(sheet = SHEET_SUMMARY, x = as.character(narrative_text),
            start_row = narrative_header_row + 1, start_col = 1)
wb$merge_cells(sheet = SHEET_SUMMARY,
               dims = glue("A{narrative_header_row+1}:G{narrative_header_row+1}"))
wb$add_fill(sheet = SHEET_SUMMARY,
            dims = glue("A{narrative_header_row+1}:G{narrative_header_row+1}"),
            color = wb_color(NARRATIVE_FILL))

wb$set_col_widths(sheet = SHEET_SUMMARY, cols = 1:7,
                  widths = c(18, 20, 20, 20, 16, 18, 70))

# ---------------------------------------------------------------------------
# Sheets 2-5: Detail sheets per treatment type
# ---------------------------------------------------------------------------

write_detail_sheet(wb, "Chemotherapy",  chemo_gaps_final,    "Chemotherapy",  SHEET_COLORS$chemotherapy)
write_detail_sheet(wb, "Radiation",     radiation_gaps_final, "Radiation",     SHEET_COLORS$radiation)
write_detail_sheet(wb, "SCT",           sct_gaps_final,      "SCT",           SHEET_COLORS$sct)
write_detail_sheet(wb, "Immunotherapy", immuno_gaps_final,   "Immunotherapy", SHEET_COLORS$immunotherapy)

# ---------------------------------------------------------------------------
# Save workbook
# ---------------------------------------------------------------------------

wb$save(OUTPUT_PATH)
message(glue("Wrote {OUTPUT_PATH}"))

# ==============================================================================
# SECTION 8: CONSOLE SUMMARY
# ==============================================================================

message("")
message("=== CROSS-REFERENCE SUMMARY ===")

all_types <- list(
  list(name = "Chemotherapy",  gaps = chemo_gaps_final),
  list(name = "Radiation",     gaps = radiation_gaps_final),
  list(name = "SCT",           gaps = sct_gaps_final),
  list(name = "Immunotherapy", gaps = immuno_gaps_final)
)

for (t in all_types) {
  n_in_ref     <- sum(t$gaps$direction == "In Reference, Not Config", na.rm = TRUE)
  n_in_config  <- sum(t$gaps$direction == "In Config, Not Reference", na.rm = TRUE)
  n_phase45    <- sum(t$gaps$direction == "In Config, Not Reference" &
                       !is.na(t$gaps$annotation) & grepl("Phase 45", t$gaps$annotation), na.rm = TRUE)

  # Highlight if any reference-only codes have patient data
  with_data <- t$gaps %>%
    dplyr::filter(direction == "In Reference, Not Config", !is.na(patient_count), patient_count > 0)

  message(glue("{t$name}:"))
  message(glue("  In Reference, Not Config: {n_in_ref} codes"))
  message(glue("  In Config, Not Reference: {n_in_config} codes ({n_phase45} Phase 45 annotated)"))

  if (nrow(with_data) > 0) {
    message(glue("  ** ACTIONABLE: {nrow(with_data)} reference-only code(s) found in patient data:"))
    for (i in seq_len(min(5, nrow(with_data)))) {
      message(glue("     {with_data$code[i]} -- {format(with_data$patient_count[i], big.mark=',')} patients, ",
                   "{format(with_data$encounter_count[i], big.mark=',')} encounters"))
    }
  }
}

message("")
message("=== Phase 46 Treatment Code Cross-Reference Complete ===")
message(glue("Output: {OUTPUT_PATH}"))
message(glue("Sheets: Summary, Chemotherapy, Radiation, SCT, Immunotherapy"))
