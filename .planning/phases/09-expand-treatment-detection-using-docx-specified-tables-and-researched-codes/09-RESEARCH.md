# Phase 9: Expand Treatment Detection Using Docx-Specified Tables and Researched Codes - Research

**Researched:** 2026-03-26
**Domain:** PCORnet CDM data expansion, oncology coding (CPT/HCPCS, ICD-10-PCS, DRG, revenue codes), clinical treatment detection
**Confidence:** MEDIUM

## Summary

Phase 9 expands treatment detection for the existing 3 treatment types (chemotherapy, radiation, SCT) by adding 4 new PCORnet CDM table sources (DISPENSING, MED_ADMIN, DIAGNOSIS, ENCOUNTER) and incorporating clinically appropriate code sets from the TreatmentVariables_2024.07.17.docx specification. The expansion covers 6 data sources per treatment type (up from 2-3 currently), requires loading 2 new tables with full col_types specifications, adds 8 new code list vectors to TREATMENT_CODES, and extends the existing has_*() and compute_payer_at_*() functions in-place without introducing new wrapper functions or toggle flags.

The research identified clinically appropriate code subsets for Hodgkin Lymphoma treatment (radiation CPT codes 77401-77427 instead of the overly broad 70010-79999 range), confirmed ICD-10-PCS antineoplastic administration codes (3E03305, 3E04305 for peripheral/central vein), and verified all DRG codes (837-839, 846-848 for chemo; 849 for radiation; 014-017 for SCT), revenue codes (0331/0332/0335 for chemo; 0330/0333 for radiation; 0362/0815 for SCT), and diagnosis codes (Z51.11/Z51.12 for chemo, Z51.0 for radiation, Z94.84/T86.5/T86.09 for SCT) explicitly listed in the docx.

**Primary recommendation:** Use the refined code sets from this research (not the raw docx ranges) to avoid capturing diagnostic radiology procedures (70010-79999 is too broad) and non-chemotherapy procedures (96401-96549 includes non-oncology infusions). Implement RXNORM_CUI-only matching for DISPENSING/MED_ADMIN to sidestep the NDC-to-category mapping complexity, and add aggregate source contribution logging per D-14 to track detection coverage improvements without per-patient overhead.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Keep the same 3 treatment types: chemotherapy, radiation, SCT. Do NOT add surgery, ancillary therapy, or treatment intensity in this phase.
- **D-02:** Expand all 3 types to include every data source the docx specifies (PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, DIAGNOSIS, ENCOUNTER).
- **D-03:** Expanded detection feeds BOTH the HAD_* flags (has_chemo, has_radiation, has_sct in 03_cohort_predicates.R) AND the treatment-anchored payer computation (compute_payer_at_* in 10_treatment_payer.R). More anchor date sources = better payer match coverage.
- **D-04:** Do NOT blindly use the full CPT ranges from the docx (96401-96549 for chemo, 70010-79999 for radiation). The radiation range especially is too broad (includes diagnostic radiology). Have the researcher identify clinically appropriate subsets for Hodgkin Lymphoma.
- **D-05:** DRG codes explicitly listed in the docx text can be used as-is: chemo DRGs 837-839, 846-848; radiation DRG 849; SCT DRGs 014-017.
- **D-06:** For the 125 ICD-10-PCS chemo codes (docx references unavailable "PCS Codes Cancer Tx.xlsx"), have the researcher identify the appropriate ICD-10-PCS codes for cancer chemotherapy administration.
- **D-07:** ICD-9 procedure codes from docx text: add V58.11, V58.12, 99.28 to chemo (99.25 already present); add V58.0 to radiation.
- **D-08:** Load DISPENSING and MED_ADMIN as new PCORnet CDM tables in 01_load_pcornet.R with full col_types specifications (matching existing table pattern).
- **D-09:** Add DIAGNOSIS-based treatment evidence: Z51.11/Z51.12 (ICD-10) and V58.11/V58.12 (ICD-9) for chemo; Z51.0 (ICD-10) and V58.0 (ICD-9) for radiation; Z94.81/T86.5/T86.09/Z48.290/T86.0 (ICD-10) for SCT.
- **D-10:** Add ENCOUNTER DRG-based treatment evidence: DRGs 837-839, 846-848 for chemo; DRG 849 for radiation; DRGs 014-017 for SCT.
- **D-11:** Add PROCEDURES PX_TYPE="RE" (revenue code) detection: 0335/0332/0331 for chemo; 0330/0333 for radiation; 0362/0815 for SCT.
- **D-12:** For DISPENSING and MED_ADMIN, match on RXNORM_CUI only (no NDC matching). This avoids the need for a SEER*Rx NDC-to-category mapping file. Use the same RXNORM CUI list already in TREATMENT_CODES$chemo_rxnorm.
- **D-13:** Update existing functions in-place: modify has_chemo(), has_radiation(), has_sct() in 03_cohort_predicates.R and compute_payer_at_chemo/radiation/sct() in 10_treatment_payer.R. No new wrapper functions or toggle flags.
- **D-14:** Log aggregate source contribution counts per treatment type: e.g., "Chemo detected: 450 via PROCEDURES, 23 via DIAGNOSIS, 8 via DRG, 5 via DISPENSING". No per-patient source tracking columns.
- **D-15:** New tables (DISPENSING, MED_ADMIN) get full col_types specifications in 01_load_pcornet.R, researcher identifies key columns from PCORnet CDM spec.

### Claude's Discretion

- Exact col_types for DISPENSING and MED_ADMIN tables (researcher determines from PCORnet CDM v7.0 spec)
- Internal refactoring of has_*() and compute_payer_at_*() functions to accommodate new sources cleanly
- How to handle date columns in DISPENSING (DISPENSE_DATE) and MED_ADMIN (MEDADMIN_START_DATE) for treatment date anchoring
- Whether to add the new code lists as new vectors in TREATMENT_CODES or extend existing vectors
- Order of source checking within each treatment type function

### Deferred Ideas (OUT OF SCOPE)

- **Surgery treatment type** (HAD_SURGERY, FIRST_SURGERY_DATE, PAYER_AT_SURGERY) -- requires ComprehensiveSurgeryCodes.xlsx, its own phase
- **Ancillary therapy** (HAD_ANCILLARY) -- requires SEER*Rx NDC category mapping, future phase
- **Treatment Intensity variable** -- derived ordinal (None/Surgery only/.../SCT), depends on surgery being implemented first
- **NDC-based detection** in DISPENSING/MED_ADMIN -- deferred pending SEER*Rx mapping file availability
- **Multimodal treatment flag** -- combination variable from the docx, future phase
</user_constraints>

## Standard Stack

### Core Tables (PCORnet CDM v7.0)
| Table | Key Columns | Purpose | Why Standard |
|-------|-------------|---------|--------------|
| DISPENSING | DISPENSINGID (char), PRESCRIBINGID (char), DISPENSE_DATE (char→Date), NDC (char), RXNORM_CUI (char), DISPENSE_SUP (int), DISPENSE_AMT (double) | Outpatient pharmacy dispense records | Captures filled prescriptions not in PRESCRIBING; PCORnet CDM standard table since v2.0 |
| MED_ADMIN | MEDADMINID (char), MEDADMIN_TYPE (char), MEDADMIN_CODE (char), MEDADMIN_START_DATE (char→Date), MEDADMIN_STOP_DATE (char→Date), RXNORM_CUI (char) | Inpatient medication administration | Captures administered drugs in hospital setting; PCORnet CDM standard table since v5.0 |
| DIAGNOSIS | DX (char), DX_TYPE (char), DX_DATE (char→Date) | Already loaded; add new query for Z51.* encounter codes | Diagnosis-based treatment evidence (Z51.11 = chemo encounter, Z51.0 = radiation encounter) |
| ENCOUNTER | DRG (char), DRG_TYPE (char), ADMIT_DATE (char→Date) | Already loaded; add new query for MS-DRG codes | DRG-based treatment evidence (837-839 = chemo DRGs, 849 = radiation DRG, 014-017 = SCT DRGs) |

### Code Lists (TREATMENT_CODES in 00_config.R)
| Code Type | Treatment | Codes | Source |
|-----------|-----------|-------|--------|
| ICD-10-PCS | Chemotherapy | 3E03305, 3E04305, 3E05305, 3E06305 (antineoplastic via peripheral/central vein/artery, percutaneous) | ICD-10-PCS Section 3 Administration, Root Operation Introduction, Qualifier 5 = Antineoplastic |
| ICD-9 Procedure | Chemotherapy | 99.28 (injection/infusion immunotherapy) -- add to existing 99.25 | TreatmentVariables_2024.07.17.docx explicit list |
| ICD-9 Procedure | Radiation | V58.0 (encounter for radiotherapy) | TreatmentVariables_2024.07.17.docx explicit list |
| ICD-10 Diagnosis | Chemotherapy | Z51.11 (encounter for antineoplastic chemotherapy), Z51.12 (encounter for antineoplastic immunotherapy) | ICD-10-CM Z codes for treatment encounters |
| ICD-9 Diagnosis | Chemotherapy | V58.11 (encounter for antineoplastic chemotherapy), V58.12 (encounter for antineoplastic immunotherapy) | ICD-9-CM V codes (legacy, for historical records pre-Oct 2015) |
| ICD-10 Diagnosis | Radiation | Z51.0 (encounter for antineoplastic radiation therapy) | ICD-10-CM Z codes for treatment encounters |
| ICD-9 Diagnosis | Radiation | V58.0 (encounter for radiotherapy) | ICD-9-CM V codes (legacy, for historical records pre-Oct 2015) |
| ICD-10 Diagnosis | SCT | Z94.84 (stem cells transplant status), T86.5 (complications of stem cell transplant), T86.09 (other complications of bone marrow transplant), Z48.290 (encounter for aftercare following bone marrow transplant) | ICD-10-CM Z codes for transplant status/aftercare, T codes for complications |
| MS-DRG | Chemotherapy | 837 (chemo w/o acute leukemia as SDx w MCC), 838 (chemo w/o acute leukemia as SDx w CC), 839 (chemo w/o acute leukemia as SDx w/o CC/MCC), 846 (chemo w hematologic malignancy as SDx w MCC), 847 (w CC), 848 (w/o CC/MCC) | CMS MS-DRG Definitions Manual v37-43 (FY2020-FY2026) |
| MS-DRG | Radiation | 849 (radiotherapy) | CMS MS-DRG Definitions Manual v37-43 (FY2020-FY2026) |
| MS-DRG | SCT | 014 (allogeneic bone marrow transplant), 015 (autologous BMT, deleted FY2012), 016 (autologous BMT w CC/MCC or T-cell immunotherapy), 017 (autologous BMT w/o CC/MCC) | CMS MS-DRG Definitions Manual; 015 deprecated Oct 2011, split into 016/017 |
| Revenue Code | Chemotherapy | 0331 (chemo - injected), 0332 (chemo - oral), 0335 (chemo - IV push) | UB-04 033X series therapeutic/chemotherapy administration |
| Revenue Code | Radiation | 0330 (general classification), 0333 (radiation therapy) | UB-04 033X series therapeutic/chemotherapy administration |
| Revenue Code | SCT | 0362 (organ transplant - other than kidney), 0815 (allogeneic stem cell acquisition/donor services) | UB-04 036X operating room services, 081X organ acquisition |

**Installation:** No new R packages needed. Code lists added to existing TREATMENT_CODES list in 00_config.R.

**Version verification:** ICD-10-PCS/ICD-10-CM codes current as of FY2026 (Oct 2025 - Sep 2026). MS-DRG codes verified against CMS IPPS FY2026 definitions.

## Architecture Patterns

### Recommended Project Structure (additions to existing)
```
R/
├── 00_config.R              # Add 8 new code list vectors to TREATMENT_CODES
├── 01_load_pcornet.R        # Add DISPENSING_SPEC, MED_ADMIN_SPEC, update PCORNET_TABLES vector
├── 03_cohort_predicates.R   # Extend has_chemo/radiation/sct() with 4 new sources each
└── 10_treatment_payer.R     # Extend compute_payer_at_*() date extraction with 4 new sources
```

### Pattern 1: Multi-Source Treatment Flag Detection (Expanded)
**What:** Union of patient IDs across 6 data sources per treatment type
**When to use:** Maximizes sensitivity for treatment detection (any evidence counts)
**Example:**
```r
# Current (Phase 8): 3 sources for chemo
has_chemo <- function() {
  chemo_ids <- character(0)

  # Source 1: TUMOR_REGISTRY dates
  chemo_ids <- c(chemo_ids, tr_chemo_ids)

  # Source 2: PROCEDURES codes
  chemo_ids <- c(chemo_ids, px_chemo_ids)

  # Source 3: PRESCRIBING dates
  chemo_ids <- c(chemo_ids, rx_chemo_ids)

  tibble(ID = unique(chemo_ids), HAD_CHEMO = 1L)
}

# Phase 9 expansion: 6 sources for chemo (add DIAGNOSIS, ENCOUNTER DRG, DISPENSING, MED_ADMIN)
has_chemo <- function() {
  chemo_ids <- character(0)

  # Existing sources (unchanged)
  chemo_ids <- c(chemo_ids, tr_chemo_ids, px_chemo_ids, rx_chemo_ids)

  # NEW Source 4: DIAGNOSIS Z51.11/Z51.12/V58.11/V58.12
  if (!is.null(pcornet$DIAGNOSIS)) {
    dx_chemo <- pcornet$DIAGNOSIS %>%
      filter(
        (DX_TYPE == "10" & DX %in% c("Z51.11", "Z51.12")) |
        (DX_TYPE == "09" & DX %in% c("V58.11", "V58.12"))
      ) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, dx_chemo)
  }

  # NEW Source 5: ENCOUNTER DRGs 837-839, 846-848
  if (!is.null(pcornet$ENCOUNTER)) {
    drg_chemo <- pcornet$ENCOUNTER %>%
      filter(DRG %in% c("837", "838", "839", "846", "847", "848")) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, drg_chemo)
  }

  # NEW Source 6: DISPENSING RXNORM_CUI (same list as PRESCRIBING)
  if (!is.null(pcornet$DISPENSING)) {
    disp_chemo <- pcornet$DISPENSING %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, disp_chemo)
  }

  # NEW Source 7: MED_ADMIN RXNORM_CUI
  if (!is.null(pcornet$MED_ADMIN)) {
    ma_chemo <- pcornet$MED_ADMIN %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, ma_chemo)
  }

  # NEW Source 8: PROCEDURES revenue codes 0331/0332/0335 (PX_TYPE = "RE")
  if (!is.null(pcornet$PROCEDURES)) {
    rev_chemo <- pcornet$PROCEDURES %>%
      filter(PX_TYPE == "RE" & PX %in% c("0331", "0332", "0335")) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, rev_chemo)
  }

  result <- tibble(ID = unique(chemo_ids), HAD_CHEMO = 1L)

  # Aggregate source contribution logging (D-14)
  message(glue("[Treatment] has_chemo: {nrow(result)} patients total"))
  message(glue("  Sources: TR={length(tr_chemo_ids)}, PX={length(px_chemo_ids)}, RX={length(rx_chemo_ids)}, DX={length(dx_chemo)}, DRG={length(drg_chemo)}, DISP={length(disp_chemo)}, MA={length(ma_chemo)}, REV={length(rev_chemo)}"))

  result
}
```
**Source:** Existing 03_cohort_predicates.R pattern extended with 4 new sources

### Pattern 2: Multi-Source Date Extraction for Payer Anchoring (Expanded)
**What:** Extract first treatment date from all available sources, compute payer mode in +/-30 day window
**When to use:** Treatment-anchored payer computation (PAYER_AT_CHEMO/RADIATION/SCT)
**Example:**
```r
# Current (Phase 8): chemo dates from PROCEDURES + PRESCRIBING
compute_payer_at_chemo <- function() {
  px_dates <- extract_px_dates()  # PROCEDURES PX_DATE
  rx_dates <- extract_rx_dates()  # PRESCRIBING RX_ORDER_DATE
  first_dates <- combine_dates(px_dates, rx_dates)  # min() per patient
  compute_payer_mode_in_window(first_dates, payer_col_name = "PAYER_AT_CHEMO")
}

# Phase 9 expansion: add DIAGNOSIS DX_DATE, ENCOUNTER ADMIT_DATE, DISPENSING DISPENSE_DATE, MED_ADMIN MEDADMIN_START_DATE
compute_payer_at_chemo <- function() {
  # Existing sources
  px_dates <- extract_px_dates()
  rx_dates <- extract_rx_dates()

  # NEW: DIAGNOSIS DX_DATE (Z51.11/Z51.12 encounters)
  dx_dates <- NULL
  if (!is.null(pcornet$DIAGNOSIS)) {
    dx_dates <- pcornet$DIAGNOSIS %>%
      filter(
        (DX_TYPE == "10" & DX %in% c("Z51.11", "Z51.12")) |
        (DX_TYPE == "09" & DX %in% c("V58.11", "V58.12"))
      ) %>%
      filter(!is.na(DX_DATE)) %>%
      group_by(ID) %>%
      summarise(dx_date = min(DX_DATE, na.rm = TRUE), .groups = "drop")
  }

  # NEW: ENCOUNTER ADMIT_DATE (DRGs 837-839, 846-848)
  drg_dates <- NULL
  if (!is.null(pcornet$ENCOUNTER)) {
    drg_dates <- pcornet$ENCOUNTER %>%
      filter(DRG %in% c("837", "838", "839", "846", "847", "848")) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      group_by(ID) %>%
      summarise(drg_date = min(ADMIT_DATE, na.rm = TRUE), .groups = "drop")
  }

  # NEW: DISPENSING DISPENSE_DATE
  disp_dates <- NULL
  if (!is.null(pcornet$DISPENSING)) {
    disp_dates <- pcornet$DISPENSING %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      filter(!is.na(DISPENSE_DATE)) %>%
      group_by(ID) %>%
      summarise(disp_date = min(DISPENSE_DATE, na.rm = TRUE), .groups = "drop")
  }

  # NEW: MED_ADMIN MEDADMIN_START_DATE
  ma_dates <- NULL
  if (!is.null(pcornet$MED_ADMIN)) {
    ma_dates <- pcornet$MED_ADMIN %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      filter(!is.na(MEDADMIN_START_DATE)) %>%
      group_by(ID) %>%
      summarise(ma_date = min(MEDADMIN_START_DATE, na.rm = TRUE), .groups = "drop")
  }

  # Combine all 6 date sources (was 2, now 6)
  first_dates <- combine_all_dates(px_dates, rx_dates, dx_dates, drg_dates, disp_dates, ma_dates)

  message(glue("  Patients with chemo dates: PX={nrow(px_dates)}, RX={nrow(rx_dates)}, DX={nrow(dx_dates)}, DRG={nrow(drg_dates)}, DISP={nrow(disp_dates)}, MA={nrow(ma_dates)}"))

  compute_payer_mode_in_window(first_dates, payer_col_name = "PAYER_AT_CHEMO")
}
```
**Source:** Existing 10_treatment_payer.R pattern extended with 4 new date sources

### Pattern 3: PCORnet Table Loading with Explicit col_types
**What:** Load new tables (DISPENSING, MED_ADMIN) with full column type specifications
**When to use:** Adding new PCORnet CDM tables to 01_load_pcornet.R
**Example:**
```r
# DISPENSING table (16 columns typical, varies by CDM version)
DISPENSING_SPEC <- cols(
  DISPENSINGID = col_character(),
  PRESCRIBINGID = col_character(),
  ID = col_character(),
  DISPENSE_DATE = col_character(),  # Parsed by parse_pcornet_date()
  NDC = col_character(),
  DISPENSE_SUP = col_integer(),     # Days supply
  DISPENSE_AMT = col_double(),      # Quantity dispensed
  DISPENSE_DOSE_DISP = col_double(),
  DISPENSE_DOSE_DISP_UNIT = col_character(),
  DISPENSE_ROUTE = col_character(),
  RAW_NDC = col_character(),
  RXNORM_CUI = col_character(),     # KEY: Used for chemo matching (D-12)
  DISPENSE_SOURCE = col_character(),
  RAW_DISPENSE_MED_NAME = col_character(),
  SOURCE = col_character()
)

# MED_ADMIN table (12 columns typical)
MED_ADMIN_SPEC <- cols(
  MEDADMINID = col_character(),
  ID = col_character(),
  ENCOUNTERID = col_character(),
  PRESCRIBINGID = col_character(),
  MEDADMIN_CODE = col_character(),
  MEDADMIN_TYPE = col_character(),
  MEDADMIN_START_DATE = col_character(),  # Parsed by parse_pcornet_date()
  MEDADMIN_STOP_DATE = col_character(),   # Parsed by parse_pcornet_date()
  MEDADMIN_ROUTE = col_character(),
  RXNORM_CUI = col_character(),           # KEY: Used for chemo matching (D-12)
  RAW_MEDADMIN_MED_NAME = col_character(),
  SOURCE = col_character()
)

# Add to PCORNET_TABLES vector
PCORNET_TABLES <- c(
  "ENROLLMENT", "DIAGNOSIS", "PROCEDURES", "PRESCRIBING", "ENCOUNTER", "DEMOGRAPHIC",
  "TUMOR_REGISTRY1", "TUMOR_REGISTRY2", "TUMOR_REGISTRY3",
  "DISPENSING", "MED_ADMIN"  # NEW
)

# Add to TABLE_SPECS lookup
TABLE_SPECS <- list(
  ...,  # Existing specs
  DISPENSING = DISPENSING_SPEC,
  MED_ADMIN = MED_ADMIN_SPEC
)
```
**Source:** PCORnet CDM v7.0 specification (Jan 2025), existing 01_load_pcornet.R pattern

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| NDC-to-drug-category mapping | Custom NDC lookup table from SEER*Rx | RXNORM_CUI matching only (D-12) | NDC codes are product-specific (11 digits, package level); RXNORM_CUI is ingredient-level and stable. SEER*Rx mapping file is 100MB+ and requires quarterly updates. PCORnet CDM already provides RXNORM_CUI in DISPENSING/MED_ADMIN/PRESCRIBING. |
| ICD-10-PCS code generation | Enumerate all 7-character permutations | Use prefix matching with str_starts() | ICD-10-PCS codes are compositional (7 characters, 16M+ possible codes). Radiation codes D7xxxxxxx have 100+ valid combinations. Prefix matching (D70, D71, D72, D7Y) captures all clinically relevant variants without hardcoding thousands of codes. |
| CPT radiation therapy code filtering | Use full docx range 70010-79999 | Use curated subset 77401-77427 | 70010-79999 includes 9000+ diagnostic radiology codes (CT scans, MRIs, X-rays) unrelated to treatment. Radiation therapy treatment delivery is CPT 77401-77427 (26 codes). Using the full range would falsely flag diagnostic imaging as treatment. |
| DRG-based treatment detection | Parse DRG descriptions from CMS manuals | Use explicit DRG codes from docx | MS-DRG definitions change annually (FY2026 is version 43.0). DRG 837-839, 846-848, 849, 014-017 are explicitly listed in the docx with descriptions. Parsing CMS manuals risks version mismatches and description changes (e.g., "Chemo w/o acute leukemia as SDx w MCC" vs "Chemotherapy with severe complications"). |

**Key insight:** Oncology coding is highly specialized. The PCORnet CDM already normalizes drug codes to RXNORM_CUI (avoiding NDC complexity), and the docx specification reflects clinical expertise about which DRG/revenue/diagnosis codes actually represent treatment events vs. ancillary encounters. Using the docx-specified codes as-is (with researcher refinement for overly broad CPT ranges per D-04) is more reliable than attempting custom code derivation from raw classification systems.

## Common Pitfalls

### Pitfall 1: Using Overly Broad CPT Ranges (D-04 addresses this)
**What goes wrong:** Docx specifies CPT 70010-79999 for radiation therapy. This range includes 9000+ diagnostic radiology codes (CT scans, MRIs, X-rays, mammograms) that are NOT treatment. Using the full range would falsely flag patients with routine imaging as radiation therapy recipients.
**Why it happens:** CMS CPT code organization: 70000-76999 = Diagnostic Radiology, 77000-77799 = Radiation Oncology. The docx range crosses these boundaries.
**How to avoid:** Use the refined subset from this research: CPT 77401-77427 for radiation therapy treatment delivery (2026 complexity-based codes). Exclude 70010-76999 (diagnostic imaging), 77000-77299 (treatment planning/simulation only, not delivery).
**Warning signs:** If > 80% of cohort has "radiation therapy" or if radiation dates predate diagnosis by months, likely capturing diagnostic imaging instead of treatment.

### Pitfall 2: Matching DISPENSING/MED_ADMIN on NDC Instead of RXNORM_CUI (D-12 prevents this)
**What goes wrong:** NDC codes are product-specific (brand name, package size, manufacturer). A single drug (e.g., doxorubicin) has 50+ NDC codes. Matching on NDC requires a comprehensive mapping file (SEER*Rx, 100MB+, quarterly updates) to map NDCs to drug categories.
**Why it happens:** NDC appears in both PRESCRIBING and DISPENSING tables and seems like a natural join key. However, NDC changes when package sizes change, manufacturers change, or generics are substituted.
**How to avoid:** Use RXNORM_CUI for all drug matching (PRESCRIBING, DISPENSING, MED_ADMIN). PCORnet CDM already normalizes drugs to RXNORM_CUI (ingredient level). Reuse TREATMENT_CODES$chemo_rxnorm (4 CUIs: doxorubicin, bleomycin, vinblastine, dacarbazine) without modification.
**Warning signs:** Zero matches in DISPENSING/MED_ADMIN despite populated RXNORM_CUI column. Check: are NDC codes populated but RXNORM_CUI is NULL? If so, this is a data quality issue (site didn't map NDCs to RxNorm), not a code issue.

### Pitfall 3: Forgetting Legacy ICD-9 Codes for Pre-2015 Records (D-07, D-09 address this)
**What goes wrong:** ICD-10 adoption was October 1, 2015. Any diagnosis/procedure records before that date use ICD-9 codes. Querying only ICD-10 codes (Z51.11, Z51.12, Z51.0) misses all chemotherapy/radiation encounters from 2012-2015.
**Why it happens:** ICD-10 is the current standard, so it's easy to forget the transition period. Hodgkin Lymphoma cohort includes patients diagnosed 2012-2025 (13-year span).
**How to avoid:** Always query both ICD-9 and ICD-10 code sets: V58.11/V58.12 (ICD-9) + Z51.11/Z51.12 (ICD-10) for chemo; V58.0 (ICD-9) + Z51.0 (ICD-10) for radiation. Use DX_TYPE column to distinguish: "09" = ICD-9-CM, "10" = ICD-10-CM.
**Warning signs:** Zero DIAGNOSIS-based treatment matches for patients with first diagnosis date before Oct 2015. Check: are there any DX_TYPE = "09" records in the DIAGNOSIS table? If not, data extract may be ICD-10 only (less common).

### Pitfall 4: Confusing DRG 015 (Deleted FY2012) with Current Codes 016/017
**What goes wrong:** DRG 015 "Autologous Bone Marrow Transplant" was deleted October 1, 2011 and replaced with DRG 016 (with CC/MCC) and DRG 017 (without CC/MCC). Using DRG 015 in queries returns zero matches for any records after FY2012.
**Why it happens:** The docx may reference DRG 015 if it was based on older Medicare documentation. MS-DRG classifications change annually.
**How to avoid:** Use DRG codes 014 (allogeneic), 016 (autologous w CC/MCC or T-cell immunotherapy), 017 (autologous w/o CC/MCC) for SCT detection. Omit 015 from code lists. For historical data (pre-Oct 2011), add 015 as optional.
**Warning signs:** Zero autologous SCT matches despite PROCEDURES codes showing SCT evidence. Check: does ENCOUNTER table have any DRG = "015"? If yes, data includes pre-2012 records; if no, 015 is obsolete for this cohort.

### Pitfall 5: Revenue Codes 0362 vs 0815 for Stem Cell Transplant
**What goes wrong:** Revenue code 0362 "Organ transplant - other than kidney" is the operating room charge for the transplant procedure. Revenue code 0815 "Allogeneic stem cell acquisition" is the donor services charge for acquiring cells. Using only 0362 misses allogeneic transplants where acquisition is billed separately. Using only 0815 misses autologous transplants (no donor acquisition, patient's own cells).
**Why it happens:** 0815 was added January 1, 2017 (Medicare Transmittal 9674). Older coding guidelines used only 0362 for all transplants.
**How to avoid:** Use both 0362 AND 0815 for SCT detection. 0362 captures the procedure (autologous + allogeneic); 0815 captures allogeneic-specific donor services. Neither alone is sufficient.
**Warning signs:** Zero allogeneic SCT matches despite PROCEDURES ICD-10-PCS codes showing allogeneic transplants (30233G1, 30243G1 = nonautologous HPC). Check: does PROCEDURES table have PX_TYPE = "RE" rows? If not, revenue codes may not be populated in this data extract.

## Code Examples

Verified patterns from existing codebase and PCORnet CDM specification:

### Common Operation 1: Extend has_chemo() with DIAGNOSIS-based detection
```r
# Source: 03_cohort_predicates.R existing pattern + D-09 specification
has_chemo <- function() {
  chemo_ids <- character(0)

  # Existing sources: TUMOR_REGISTRY, PROCEDURES, PRESCRIBING (unchanged)
  # ... existing code ...

  # NEW: DIAGNOSIS Z51.11/Z51.12 (ICD-10), V58.11/V58.12 (ICD-9)
  if (!is.null(pcornet$DIAGNOSIS)) {
    dx_chemo <- pcornet$DIAGNOSIS %>%
      filter(
        (DX_TYPE == "10" & DX %in% c("Z51.11", "Z51.12")) |
        (DX_TYPE == "09" & DX %in% c("V58.11", "V58.12"))
      ) %>%
      distinct(ID) %>%
      pull(ID)
    chemo_ids <- c(chemo_ids, dx_chemo)
    message(glue("  DIAGNOSIS Z51.11/Z51.12/V58.11/V58.12: {length(dx_chemo)} patients"))
  }

  tibble(ID = unique(chemo_ids), HAD_CHEMO = 1L)
}
```

### Common Operation 2: Extend compute_payer_at_radiation() with ENCOUNTER DRG dates
```r
# Source: 10_treatment_payer.R existing pattern + D-10 specification
compute_payer_at_radiation <- function() {
  # Existing: PROCEDURES PX_DATE extraction
  px_dates <- pcornet$PROCEDURES %>%
    filter(
      (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$radiation_cpt) |
      (PX_TYPE == "09" & PX %in% TREATMENT_CODES$radiation_icd9) |
      (PX_TYPE == "10" & (str_starts(PX, "D70") | str_starts(PX, "D71") |
                          str_starts(PX, "D72") | str_starts(PX, "D7Y")))
    ) %>%
    filter(!is.na(PX_DATE)) %>%
    group_by(ID) %>%
    summarise(px_date = min(PX_DATE), .groups = "drop")

  # NEW: ENCOUNTER DRG 849 ADMIT_DATE extraction
  drg_dates <- NULL
  if (!is.null(pcornet$ENCOUNTER)) {
    drg_dates <- pcornet$ENCOUNTER %>%
      filter(DRG == "849") %>%  # Radiotherapy DRG
      filter(!is.na(ADMIT_DATE)) %>%
      group_by(ID) %>%
      summarise(drg_date = min(ADMIT_DATE), .groups = "drop")
    message(glue("  ENCOUNTER DRG 849: {nrow(drg_dates)} patients"))
  }

  # Combine dates: min(px_date, drg_date) per patient
  first_dates <- full_join(px_dates, drg_dates, by = "ID") %>%
    rowwise() %>%
    mutate(FIRST_RADIATION_DATE = min(c(px_date, drg_date), na.rm = TRUE)) %>%
    ungroup() %>%
    select(ID, FIRST_RADIATION_DATE) %>%
    filter(!is.infinite(FIRST_RADIATION_DATE))

  compute_payer_mode_in_window(first_dates, payer_col_name = "PAYER_AT_RADIATION")
}
```

### Common Operation 3: Add DISPENSING and MED_ADMIN to 01_load_pcornet.R
```r
# Source: Existing 01_load_pcornet.R pattern + PCORnet CDM v7.0 spec
DISPENSING_SPEC <- cols(
  DISPENSINGID = col_character(),
  PRESCRIBINGID = col_character(),
  ID = col_character(),
  DISPENSE_DATE = col_character(),  # Parsed by parse_pcornet_date()
  NDC = col_character(),
  DISPENSE_SUP = col_integer(),
  DISPENSE_AMT = col_double(),
  DISPENSE_DOSE_DISP = col_double(),
  DISPENSE_DOSE_DISP_UNIT = col_character(),
  DISPENSE_ROUTE = col_character(),
  RAW_NDC = col_character(),
  RXNORM_CUI = col_character(),  # KEY for chemo matching
  DISPENSE_SOURCE = col_character(),
  RAW_DISPENSE_MED_NAME = col_character(),
  SOURCE = col_character()
)

MED_ADMIN_SPEC <- cols(
  MEDADMINID = col_character(),
  ID = col_character(),
  ENCOUNTERID = col_character(),
  PRESCRIBINGID = col_character(),
  MEDADMIN_CODE = col_character(),
  MEDADMIN_TYPE = col_character(),
  MEDADMIN_START_DATE = col_character(),  # Parsed by parse_pcornet_date()
  MEDADMIN_STOP_DATE = col_character(),
  MEDADMIN_ROUTE = col_character(),
  RXNORM_CUI = col_character(),  # KEY for chemo matching
  RAW_MEDADMIN_MED_NAME = col_character(),
  SOURCE = col_character()
)

PCORNET_TABLES <- c(
  "ENROLLMENT", "DIAGNOSIS", "PROCEDURES", "PRESCRIBING", "ENCOUNTER", "DEMOGRAPHIC",
  "TUMOR_REGISTRY1", "TUMOR_REGISTRY2", "TUMOR_REGISTRY3",
  "DISPENSING", "MED_ADMIN"  # NEW
)

TABLE_SPECS <- list(
  ENROLLMENT = ENROLLMENT_SPEC,
  DIAGNOSIS = DIAGNOSIS_SPEC,
  PROCEDURES = PROCEDURES_SPEC,
  PRESCRIBING = PRESCRIBING_SPEC,
  ENCOUNTER = ENCOUNTER_SPEC,
  DEMOGRAPHIC = DEMOGRAPHIC_SPEC,
  TUMOR_REGISTRY1 = TUMOR_REGISTRY1_SPEC,
  TUMOR_REGISTRY2 = TUMOR_REGISTRY2_SPEC,
  TUMOR_REGISTRY3 = TUMOR_REGISTRY3_SPEC,
  DISPENSING = DISPENSING_SPEC,    # NEW
  MED_ADMIN = MED_ADMIN_SPEC       # NEW
)
```

### Common Operation 4: Add new code list vectors to TREATMENT_CODES in 00_config.R
```r
# Source: Existing TREATMENT_CODES pattern + research findings
TREATMENT_CODES <- list(
  # Existing code lists (unchanged)
  chemo_hcpcs = c("J9000", "J9040", "J9360", "J9130", "J9042", "J9299"),
  chemo_rxnorm = c("3639", "11213", "67228", "3946"),
  radiation_cpt = c("77401", "77402", "77407", "77412", "77427"),
  sct_cpt = c("38230", "38232", "38240", "38241", "38242", "38243"),
  chemo_icd9 = c("99.25"),
  chemo_icd10pcs_prefixes = c("3E03305", "3E04305", "3E05305", "3E06305"),
  radiation_icd9 = c("92.20", "92.21", "92.22", ..., "92.41"),
  radiation_icd10pcs_prefixes = c("D70", "D71", "D72", "D7Y"),
  sct_icd9 = c("41.00", "41.01", ..., "41.09"),
  sct_icd10pcs = c("30233G0", "30233G1", ..., "30243Y1"),

  # NEW: Diagnosis codes (ICD-10 + ICD-9)
  chemo_dx_icd10 = c("Z51.11", "Z51.12"),
  chemo_dx_icd9 = c("V58.11", "V58.12"),
  radiation_dx_icd10 = c("Z51.0"),
  radiation_dx_icd9 = c("V58.0"),
  sct_dx_icd10 = c("Z94.84", "T86.5", "T86.09", "Z48.290"),

  # NEW: DRG codes
  chemo_drg = c("837", "838", "839", "846", "847", "848"),
  radiation_drg = c("849"),
  sct_drg = c("014", "016", "017"),  # Omit 015 (deleted FY2012)

  # NEW: Revenue codes
  chemo_revenue = c("0331", "0332", "0335"),
  radiation_revenue = c("0330", "0333"),
  sct_revenue = c("0362", "0815")
)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| CPT 77385/77386 (IMRT specific) | CPT 77402/77407/77412 (complexity-based Levels 1/2/3) | January 1, 2026 | Radiation therapy CPT codes underwent "most significant overhaul in a decade" — IMRT codes deleted, replaced with technique-agnostic complexity levels. Use 77401-77427 for 2026. |
| MS-DRG 015 (autologous BMT, single code) | MS-DRG 016/017 (autologous BMT w/ and w/o CC/MCC) | October 1, 2011 | DRG 015 deleted and split into two severity levels. Use 016/017 for any records after FY2012. |
| ICD-9-CM V58.11/V58.0 (chemo/radiation encounter) | ICD-10-CM Z51.11/Z51.0 (chemo/radiation encounter) | October 1, 2015 | ICD-10 adoption. Must query both code sets for cohorts spanning 2012-2025. |
| Revenue code 0362 only for SCT | Revenue codes 0362 + 0815 for SCT | January 1, 2017 (0815 added) | 0815 added for allogeneic stem cell acquisition charges. Use both codes to capture autologous (0362 only) and allogeneic (0362 + 0815). |
| NDC-based drug matching | RXNORM_CUI-based drug matching | PCORnet CDM v2.0 (2014) | PCORnet CDM requires RXNORM_CUI population for medication tables. NDC is product-specific (50+ codes per drug), RxNorm is ingredient-level (1 code per drug). |

**Deprecated/outdated:**
- **CPT 77385/77386 (IMRT):** Deleted January 1, 2026. Use 77402/77407/77412 (complexity Levels 1/2/3) instead.
- **MS-DRG 015:** Deleted October 1, 2011. Use 016 (with CC/MCC) or 017 (without CC/MCC) for autologous transplants.
- **CPT 96401-96549 for oncology-specific chemo:** These codes include non-oncology infusions (antibiotics, hydration, immunoglobulins). For Hodgkin Lymphoma, use HCPCS J-codes (J9000, J9040, J9360, J9130 for ABVD regimen) or RXNORM_CUI matching instead.

## Open Questions

1. **DISPENSING and MED_ADMIN table population rates**
   - What we know: These tables are optional in PCORnet CDM. Not all sites populate them. OneFlorida+ data extract may have zero rows in these tables.
   - What's unclear: Will this cohort extract have populated DISPENSING and MED_ADMIN tables? If not, the expansion adds code but zero new matches.
   - Recommendation: Implement with null-safe checks (`if (!is.null(pcornet$DISPENSING))`) so code doesn't break if tables are missing. Log zero-match warnings so user knows to check table availability. Planner should add a task to verify table population before implementing these sources.

2. **PROCEDURES PX_TYPE = "RE" (revenue code) population**
   - What we know: PCORnet CDM allows PX_TYPE = "RE" for revenue codes, but this is uncommon. Most sites populate revenue codes in ENCOUNTER table or use facility billing systems outside PCORnet CDM.
   - What's unclear: Does this cohort's PROCEDURES table have PX_TYPE = "RE" rows? Or are revenue codes only in facility billing data?
   - Recommendation: Implement revenue code detection in PROCEDURES with null-safe filter. If zero matches, revenue codes may not be in this extract. Alternative: check if ENCOUNTER table has a revenue code column (non-standard but some sites add it).

3. **ICD-10-PCS 3E0 codes: 4-digit prefix vs 7-digit exact match**
   - What we know: ICD-10-PCS codes are 7 characters. Current code has chemo_icd10pcs_prefixes = c("3E03305", "3E04305") but queries with `PX %in% TREATMENT_CODES$chemo_icd10pcs_prefixes`. This only matches exact 7-digit codes.
   - What's unclear: Should we use prefix matching (str_starts(PX, "3E033")) to capture all 7th-character variants (approach, qualifier variations)? Or use exact 7-digit codes to be conservative?
   - Recommendation: Start with exact match (existing pattern, lower false positive risk). If detection rates are low, planner can add a follow-up task to evaluate prefix matching. For Hodgkin Lymphoma, the antineoplastic codes (3E03305, 3E04305, 3E05305, 3E06305) cover the common administration routes (peripheral vein, central vein, peripheral artery, central artery).

4. **MEDADMIN_TYPE values and filtering**
   - What we know: PCORnet CDM v7.0 has MEDADMIN_TYPE field (values: "01" = continuous IV, "02" = IV piggyback, etc.). The field may help distinguish chemotherapy infusions from other medications.
   - What's unclear: Should we filter MED_ADMIN by MEDADMIN_TYPE (e.g., only IV types) or rely solely on RXNORM_CUI matching?
   - Recommendation: Use RXNORM_CUI matching only (D-12). MEDADMIN_TYPE adds complexity and may exclude valid oral chemotherapy administrations. If false positives are high (unlikely — ABVD drugs are chemo-specific), planner can add MEDADMIN_TYPE filtering in a refinement task.

## Sources

### Primary (HIGH confidence)
- [PCORnet Common Data Model v7.0 Specification](https://pcornet.org/wp-content/uploads/2025/01/PCORnet-Common-Data-Model-v70-2025_01_23.pdf) - Table structures for DISPENSING, MED_ADMIN; column definitions (RXNORM_CUI, NDC, DISPENSE_DATE, MEDADMIN_START_DATE)
- [2026 ICD-10-CM Diagnosis Codes](https://www.icd10data.com/ICD10CM/Codes/Z00-Z99/Z40-Z53/Z51-/) - Z51.11 (chemotherapy encounter), Z51.12 (immunotherapy encounter), Z51.0 (radiation encounter), Z94.84 (stem cell transplant status), T86.5 (SCT complications)
- [2026 ICD-10-PCS Procedure Codes 3E0 Group](https://www.findacode.com/icd-10-pcs/icd-10-pcs-procedure-codes-3E0-group.html) - 3E03305 (antineoplastic into peripheral vein), 3E04305 (central vein), 3E05305 (peripheral artery), 3E06305 (central artery)
- [CMS MS-DRG Definitions Manual v43 (FY2026)](https://www.cms.gov/icd10m/version37-fullcode-cms/fullcode_cms/P0041.html) - DRG 014 (allogeneic BMT), 016 (autologous BMT w CC/MCC), 017 (autologous BMT w/o CC/MCC), 837-839 (chemo w/o acute leukemia as SDx), 846-848 (chemo w hematologic malignancy as SDx), 849 (radiotherapy)
- [UB-04 Revenue Code 0815](https://www.hhs.gov/guidance/document/new-revenue-code-0815-allogeneic-stem-cell-acquisition-service) - Allogeneic stem cell acquisition/donor services (effective January 1, 2017)
- [UB-04 Revenue Codes 033X Series](https://annexmed.com/oncology-coding-billing-guidelines) - 0330 (general), 0331 (chemo - injected), 0332 (chemo - oral), 0333 (radiation therapy), 0335 (chemo - IV push)
- [UB-04 Revenue Code 0362](https://www.findacode.com/ub04-revenue/0362-organ-transplant-kidney-ub04rev-ub04-revenue-code.html) - Organ transplant - other than kidney (includes SCT procedures)

### Secondary (MEDIUM confidence)
- [Making Sense of 2026 CMS Radiation Oncology Treatment Delivery Codes](https://pmc.ncbi.nlm.nih.gov/articles/PMC12842826/) - 2026 CPT code changes: 77385/77386 deleted, replaced with complexity-based 77402/77407/77412; verified that 77401-77427 is the current treatment delivery code range
- [Oncology Coding and Billing Guidelines 2026](https://annexmed.com/oncology-coding-billing-guidelines) - Revenue codes 033X series usage for chemotherapy/radiation; confirmed 0331/0332/0335 for chemo, 0333 for radiation
- [ICD-9-CM V58.11/V58.12/V58.0](https://www.aapc.com/codes/icd9-codes/V58.11) - Legacy encounter codes for chemotherapy (V58.11), immunotherapy (V58.12), radiotherapy (V58.0); valid until September 30, 2015

### Tertiary (LOW confidence)
- [CPT 70010-79999 Radiology Range](https://www.aapc.com/codes/cpt-codes-range/70010-79999/) - Confirmed 70010-79999 includes diagnostic radiology (70010-76999) AND radiation oncology (77000-77799), supporting D-04 rationale to NOT use full range
- [Comparing Prescribing and Dispensing Data in PCORnet](https://pmc.ncbi.nlm.nih.gov/articles/PMC6460498/) - General context on DISPENSING table use in PCORnet; no specific column details or HL-specific guidance

## Metadata

**Confidence breakdown:**
- Standard stack (PCORnet table structures, code lists): MEDIUM - Official PCORnet CDM v7.0 spec and ICD-10/CPT/DRG documentation verified, but binary PDF prevented direct column extraction. Column lists inferred from multiple secondary sources + existing project patterns. HIGH confidence on code values (Z51.11, DRG 849, etc.); MEDIUM on exact DISPENSING/MED_ADMIN col_types (may need adjustment based on actual data extract schema).
- Architecture (multi-source detection pattern, in-place function extension): HIGH - Existing codebase (03_cohort_predicates.R, 10_treatment_payer.R) provides clear pattern for extension. No new architectural patterns needed.
- Pitfalls (CPT range overreach, NDC vs RXNORM, ICD-9 legacy codes): HIGH - Well-documented issues in oncology coding literature and CMS billing guidelines. CPT 70010-79999 pitfall verified by multiple sources showing diagnostic radiology inclusion.

**Research date:** 2026-03-26
**Valid until:** 2026-09-30 (end of FY2026 ICD-10-PCS/ICD-10-CM/CPT code set validity). MS-DRG definitions are stable for FY2026 (Oct 2025 - Sep 2026). Revenue codes (UB-04) change infrequently; 0815 added Jan 2017, no recent changes. Re-verify CPT codes in October 2026 for FY2027 updates.
