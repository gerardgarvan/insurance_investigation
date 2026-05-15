# Technology Stack

**Project:** PCORnet CDM Payer Analysis Pipeline (R)
**Researched:** 2026-04-21 (v1.6 milestone additions)
**Environment:** RStudio on UF HiPerGator (HPC SLURM scheduler)
**Confidence:** HIGH (core additions); MEDIUM (docx parsing approach)

---

## Baseline Stack (Validated — Do Not Re-research)

The following are already installed and in use on HiPerGator. No changes needed.

| Technology | Version | Purpose |
|------------|---------|---------|
| R | 4.4.2+ | Base language |
| tidyverse (dplyr, stringr, ggplot2, lubridate, purrr) | 2.0.0+ | Core data manipulation ecosystem |
| duckdb + DBI | 0.10+ | Backend data access |
| openxlsx2 | 1.x | Styled xlsx output |
| readxl | 1.4.3+ | xlsx input (already used in R/35, R/42) |
| officer | 0.6.x | PPTX generation |
| glue, janitor, scales, here | latest | Utilities |

---

## New Capabilities Required for v1.6

Three distinct new technical capabilities are needed. Each is addressed below.

---

## Capability 1: Cross-referencing TreatmentVariables_2024.07.17.docx Against R/00_config.R

### What This Is

Extracting code lists from a Word document (TreatmentVariables_2024.07.17.docx) and comparing them against the `TREATMENT_CODES` vectors in `R/00_config.R`. The goal is a gap analysis: codes in the docx but not in config, and codes in config but not in docx.

### Recommended Approach: docxtractr

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| docxtractr | 0.6.5 | Extract tables from .docx files | Purpose-built for this exact task; read_docx() + docx_extract_tbl() returns data.frames directly; zero post-processing needed to get a tidy code list |

**Why docxtractr over officer for this task:**
- `officer::docx_summary()` extracts all document elements (paragraphs, tables, headers) into a flat data.frame requiring manual filtering to isolate table rows. More flexible but noisier.
- `docxtractr::docx_extract_tbl()` extracts a specific table directly as a clean data.frame with `header = TRUE` for column name handling. Correct tool for structured tables containing code lists.
- TreatmentVariables_2024.07.17.docx contains treatment code tables (confirmed by prior Phase 10 work using this file for code lookups). docxtractr's table-specific API is cleaner.

**officer is already installed** (used by R/11_generate_pptx.R and R/22). Use it only if TreatmentVariables contains narrative text rather than structured tables — then `officer::docx_summary()` to extract paragraph text would be appropriate.

**Confidence:** HIGH — docxtractr 0.6.5 is current CRAN (verified 2026-04-21), stable since 2020, in active use.

### Installation

```r
install.packages("docxtractr")
```

### Core Usage Pattern

```r
library(docxtractr)

doc <- read_docx("TreatmentVariables_2024.07.17.docx")

# Discover tables
docx_tbl_count(doc)
docx_describe_tbls(doc)

# Extract specific table (e.g., table 1 = radiation codes)
radiation_ref <- docx_extract_tbl(doc, tbl_number = 1, header = TRUE)

# Compare against TREATMENT_CODES$radiation_cpt from R/00_config.R
gaps_in_config   <- setdiff(radiation_ref$code, TREATMENT_CODES$radiation_cpt)
gaps_in_docx     <- setdiff(TREATMENT_CODES$radiation_cpt, radiation_ref$code)
```

**Note:** Table numbering in TreatmentVariables_2024.07.17.docx must be discovered at runtime with `docx_tbl_count()` and `docx_describe_tbls()`. Do not hardcode table indices without inspection — Phase 10 used this file interactively (codes were transcribed manually). This is the first programmatic extraction.

---

## Capability 2: Cancer Site Frequency Analysis (CancerSiteCategories.xlsx ICD Codes)

### What This Is

Reading CancerSiteCategories.xlsx, which contains ICD-O-3 topography codes and/or ICD-10-CM codes grouped by cancer site category, then joining those codes against PCORnet DIAGNOSIS and TUMOR_REGISTRY tables to produce frequency counts by site category.

### ICD-O-3 vs ICD-10-CM Code Format — Critical Distinction

**ICD-O-3 topography codes** (used in TUMOR_REGISTRY): Format `C##.#` (e.g., `C81.9`, `C32.0`). These are anatomic site codes. Ranges from C00.0 to C80.9. Already used in this pipeline — `utils_icd.R` handles ICD-O-3 histology codes (9650-9667 range). Site codes in TUMOR_REGISTRY appear as character strings.

**ICD-10-CM diagnosis codes** (used in DIAGNOSIS table): Format `C##.##` (e.g., `C81.10`). Clinically applied diagnosis codes used for billing. Already normalized in `utils_icd.R`.

CancerSiteCategories.xlsx likely stores code ranges (e.g., `C81-C96`, `C00.0-C14.8`) rather than individual codes — the xlsx must be inspected to confirm format at runtime.

### Recommended Approach: readxl + stringr (No New Packages)

**Do not use the `icd` package.** It was archived from CRAN on 2020-10-06 due to unresolved check problems. Installing from GitHub (`jackwasey/icd`) would introduce an unmanaged dependency on HiPerGator where network access to GitHub may not be available during analysis runs. The package is also unmaintained ("New maintainer/owner needed" per GitHub README).

**Do not use `ICD10gm`.** It is the German ICD-10 modification (ICD-10-GM), not ICD-10-CM. Its `icd_expand()` function covers German-specific code trees and would produce incorrect results for US clinical codes.

**Use readxl + stringr instead.** The pipeline already uses this combination effectively (e.g., R/35 uses `readxl::read_excel()` for payer cross-reference). ICD code range parsing for this use case requires only prefix matching — which `stringr::str_starts()` handles cleanly. No additional packages are needed.

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| readxl | 1.4.3+ | Read CancerSiteCategories.xlsx | Already in pipeline; `read_excel()` with `sheet=` and `skip=` handles any layout |
| stringr | 1.5.1+ | Parse and match ICD code ranges | `str_starts()` for prefix matching; `str_extract()` for parsing range notation; already in pipeline |
| dplyr | 1.2.0+ | Frequency aggregation | `group_by()` + `summarise()` for site category counts; already in pipeline |

**No new packages required for this capability.**

### ICD Range Parsing Strategy

CancerSiteCategories.xlsx stores ranges in one of two likely formats:

**Format A — Prefix ranges** (e.g., `C81`, `C82-C86`):
```r
# Expand "C82-C86" to vector of prefixes c("C82","C83","C84","C85","C86")
parse_prefix_range <- function(range_str) {
  if (str_detect(range_str, "-")) {
    parts <- str_split_1(range_str, "-")
    letter  <- str_extract(parts[1], "^[A-Z]")
    start_n <- as.integer(str_extract(parts[1], "[0-9]+"))
    end_n   <- as.integer(str_extract(parts[2], "[0-9]+"))
    paste0(letter, start_n:end_n)
  } else {
    range_str
  }
}

# Match DIAGNOSIS.DX against expanded prefixes
dx %>%
  filter(hl_cohort) %>%
  mutate(matches_site = str_starts(DX, site_prefix)) %>%
  group_by(site_category) %>%
  summarise(n_patients = n_distinct(PATID), n_records = n())
```

**Format B — Dotted decimal ranges** (e.g., `C00.0-C14.8`): Parse start/end codes, then filter with `DX >= start & DX <= end` after standardizing to undotted form (consistent with `utils_icd.R`'s existing normalization).

**Which format CancerSiteCategories.xlsx uses must be verified at runtime.** The xlsx must be read and inspected before writing the parsing logic. Budget one inspection step in the phase plan.

### Integration with Existing Pipeline

- TUMOR_REGISTRY1/2/3 contain `SITE_CD` (ICD-O-3 topography) and `HISTOLOGY_CD` — query site codes against CancerSiteCategories ICD-O-3 ranges
- DIAGNOSIS table contains `DX` (ICD-10-CM / ICD-9-CM) and `DX_TYPE` — query against ICD-10-CM ranges
- Both tables accessible via `get_pcornet_table()` abstraction (DuckDB backend)
- Cohort filter (`hl_cohort` PATID set) applies before frequency count to scope to HL patients

---

## Capability 3: Radiation CPT Audit (70010-79999 Imaging vs Treatment Classification)

### What This Is

Auditing the CPT range 70010-79999 to confirm which codes in PROCEDURES are radiation treatment vs. diagnostic imaging, and to produce a documented classification with cited exclusion rationale.

### No New Packages Needed

This is a classification and documentation task using CPT code numeric ranges. The existing dplyr + stringr + openxlsx2 stack is sufficient.

### Authoritative CPT Sub-Range Classification (MEDIUM confidence — from ASTRO/CMS sources)

The AMA CPT radiology section (70010-79999) divides into these subsections relevant to the audit:

| Code Range | Category | Treatment? | Action |
|------------|----------|------------|--------|
| 70010-76499 | Diagnostic Radiology (imaging) | NO | Exclude — diagnostic imaging |
| 76506-76999 | Diagnostic Ultrasound | NO | Exclude — diagnostic imaging |
| 77001-77022 | Radiologic Guidance | NO | Exclude — guidance, not treatment |
| 77046-77067 | Mammography | NO | Exclude — screening/diagnostic |
| 77071-77092 | Bone/Joint Studies | NO | Exclude — diagnostic |
| 77261-77263 | Clinical Treatment Planning | PLANNING ONLY | Exclude — plan creation, no radiation delivered |
| 77280-77293 | Simulation | PLANNING ONLY | Exclude — simulation, no radiation delivered |
| 77295-77370 | Medical Radiation Physics, Dosimetry, Treatment Devices | PLANNING ONLY | Exclude — physics calculations, device fabrication |
| 77371-77387 | Stereotactic Radiation Treatment Delivery | YES — TREATMENT | Include |
| 77399-77417 | Radiation Treatment Delivery (external beam) | YES — TREATMENT | Include |
| 77423-77425 | Neutron Beam Treatment Delivery | YES — TREATMENT | Include |
| 77427-77432 | Radiation Treatment Management | YES — TREATMENT | Include (management of active treatment course) |
| 77435 | SBRT treatment management | YES — TREATMENT | Include |
| 77469-77470 | Intraoperative radiation treatment | YES — TREATMENT | Include |
| 77520-77525 | Proton Beam Treatment | YES — TREATMENT | Include (confirm in TREATMENT_CODES) |
| 77600-77620 | Hyperthermia | ADJUNCT | Flag for review — adjunct to radiation |
| 77750-77799 | Brachytherapy | YES — TREATMENT | Include |
| 78012-79999 | Nuclear Medicine | NO | Exclude — diagnostic/therapeutic nuclear medicine |

**2026 code changes (ASTRO-confirmed):** 77385 and 77386 (IMRT delivery technique-based codes) were deleted January 1, 2026. Replaced by complexity-based codes 77402 (simple/level 1), 77407 (intermediate/level 2), 77412 (complex/level 3). Already reflected in `TREATMENT_CODES$radiation_cpt` in `R/00_config.R`.

**Proton therapy:** 77520-77525 are in the treatment delivery subsection. Confirm they are in `TREATMENT_CODES$radiation_cpt` — current config (reviewed 2026-04-21) does NOT include them. This is a gap to flag.

### Implementation Pattern

```r
# In new audit script (e.g., R/46_radiation_cpt_audit.R)
# Uses existing get_pcornet_table() + dplyr, no new packages

procedures <- get_pcornet_table("PROCEDURES") %>%
  filter(PATID %in% hl_patids) %>%
  filter(PX_TYPE == "CH") %>%                          # CPT/HCPCS
  filter(str_detect(PX, "^7[0-9]{4}$")) %>%            # 70000-79999 range
  collect()

# Classify using numeric range
audit <- procedures %>%
  mutate(px_num = as.integer(PX)) %>%
  mutate(cpt_class = case_when(
    px_num >= 70010 & px_num <= 76499 ~ "Diagnostic Imaging — EXCLUDE",
    px_num >= 77261 & px_num <= 77370 ~ "RT Planning/Physics — EXCLUDE",
    px_num >= 77371 & px_num <= 77470 ~ "RT Treatment Delivery — INCLUDE",
    px_num >= 77520 & px_num <= 77525 ~ "Proton Beam — INCLUDE (verify in config)",
    px_num >= 77750 & px_num <= 77799 ~ "Brachytherapy — INCLUDE",
    px_num >= 78012 & px_num <= 79999 ~ "Nuclear Medicine — EXCLUDE",
    TRUE ~ "Other — Review"
  ))
```

---

## Triggering Codes Column (Treatment Episodes Output)

### No New Packages

Adding triggering codes to treatment episode CSV output (R/44) requires only dplyr joins against the existing treatment code match records. The `utils_treatment.R` helper functions already track source codes. This is a data transformation using existing stack — no new libraries.

---

## Summary: New Package Requirements for v1.6

| Package | Version | New? | Purpose |
|---------|---------|------|---------|
| docxtractr | 0.6.5 | YES — add to renv | Extract code tables from TreatmentVariables_2024.07.17.docx |
| readxl | 1.4.3+ | NO — already present | Read CancerSiteCategories.xlsx (already used in R/35, R/42) |
| stringr | 1.5.1+ | NO — already present | ICD range parsing |
| dplyr | 1.2.0+ | NO — already present | All aggregation and joins |
| openxlsx2 | current | NO — already present | Styled output workbooks |

**One new package total: docxtractr 0.6.5.**

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `icd` package | Archived from CRAN 2020-10-06, unmaintained, GitHub install unreliable on HiPerGator | readxl + stringr prefix matching |
| `ICD10gm` package | German ICD-10-GM codes, not US ICD-10-CM/ICD-O-3 | readxl + stringr prefix matching |
| `officer` for docx table extraction | `docx_summary()` returns flat element list requiring manual table isolation | docxtractr `docx_extract_tbl()` |
| Hardcoded CPT sub-range assumptions | CPT code structure must be verified against current AMA/CMS guidance; sub-ranges shift across years | Case_when with explicit numeric boundaries + source citation comment |
| AMA CPT manual for code descriptions | Copyrighted; cannot embed descriptions programmatically from AMA | CMS NCCI Policy Manual (public domain); ASTRO coding guidance; NLM/RxNorm API (already used in R/39-40) |

---

## Installation (v1.6 delta only)

```r
# On HiPerGator — interactive session only (not in SLURM script)
install.packages("docxtractr")  # 0.6.5

# Snapshot renv to capture the new dependency
renv::snapshot()
```

---

## Version Compatibility

| Package | Version | Compatible With | Notes |
|---------|---------|-----------------|-------|
| docxtractr 0.6.5 | 2020-07-05 | R 3.5.0+, xml2 1.3.0+ | Depends on xml2 (already a tidyverse transitive dependency); no conflicts with existing stack |
| readxl 1.4.3 | existing | openxlsx2, dplyr | No version conflicts; `read_excel()` and `wb_load()` serve different read contexts |

---

## Sources

- [docxtractr CRAN package page](https://cran.r-project.org/web/packages/docxtractr/index.html) — version 0.6.5, confirmed current (accessed 2026-04-21) **HIGH confidence**
- [docxtractr RDocumentation](https://www.rdocumentation.org/packages/docxtractr/versions/0.6.5) — function signatures verified **HIGH confidence**
- [icd CRAN archived status](https://cran.r-project.org/package=icd) — archived 2020-10-06 confirmed via search (accessed 2026-04-21) **HIGH confidence**
- [ICD10gm CRAN package](https://cran.r-project.org/web/packages/ICD10gm/ICD10gm.pdf) — German ICD-10-GM, not US ICD-10-CM/ICD-O-3 **HIGH confidence**
- [PMC: 2026 CMS Radiation Oncology Treatment Delivery Codes](https://pmc.ncbi.nlm.nih.gov/articles/PMC12842826/) — 2026 code changes (77402/77407/77412), deletion of 77385/77386 confirmed **HIGH confidence**
- [ASTRO Process of Care — Treatment Preparation](https://www.astro.org/practice-support/reimbursement/coding/coding-guidance/coding-faqs-and-tips/process-of-care) — planning/simulation codes 77261-77290 confirmed non-treatment **HIGH confidence**
- [medicalbillersandcoders.com: Radiology Billing Codes](https://www.medicalbillersandcoders.com/blog/understand-the-basics-of-radiology-billing-codes/) — 70010-79999 subsection boundaries **MEDIUM confidence** (industry source, not AMA official)
- [medicalbillersandcoders.com: Radiation Oncology Codes Part 1](https://www.medicalbillersandcoders.com/blog/radiation-oncology-codes-part-1/) — 77261-77799 subsection breakdown **MEDIUM confidence**
- [SEER ICD-O-3 Site Codes format](https://training.seer.cancer.gov/head-neck/abstract-code-stage/codes.html) — C##.# format confirmed **HIGH confidence**

---

*Stack research for: PCORnet HL Pipeline v1.6 — Treatment Code Validation & Cancer Site Analysis*
*Researched: 2026-04-21*
*Supersedes: STACK.md dated 2026-03-24 (baseline stack unchanged; this adds v1.6 capability-specific entries)*
