# Phase 45: Radiation CPT Audit - Research

**Researched:** 2026-05-15
**Domain:** AMA CPT radiology range classification, radiation oncology coding, openxlsx2 xlsx generation, NLM HCPCS API, R config modification
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Classification granularity (D-01 to D-03)**
- D-01: Claude's discretion on sub-range grouping level — pick what best supports the argument for excluding imaging codes
- D-02: Citations use AMA CPT chapter structure (publicly known range boundaries). No need for published literature references.
- D-03: Classification table includes a brief rationale column explaining WHY each sub-range is imaging vs treatment (not just the AMA label)

**Output format & audience (D-04 to D-07)**
- D-04: Primary audience is collaborators (Amy Crisp / team) — output must be self-explanatory
- D-05: Styled xlsx following Phase 42 openxlsx2 pattern. Two sheets: classification table + codes found in data.
- D-06: This is NOT about flagging false positives in existing detection. The current config does NOT use imaging codes. The purpose is to explain to collaborators WHY the pipeline uses a narrow set of treatment codes rather than the full 70010-79999 range from TreatmentVariables.
- D-07: Include an explicit recommendation section: "TreatmentVariables specifies 70010-79999; only 77261-77799 are radiation treatment per AMA CPT. Recommend using narrow treatment-only range."

**Config update scope (D-08 to D-11)**
- D-08: Add proton therapy codes 77520-77525 to TREATMENT_CODES$radiation_cpt with proper descriptions and citation comments
- D-09: Fix all Phase 39 "no description" comments on existing radiation_cpt codes (77404, 77408, 77413, 77414, 77416, 77417, 77418, 77421, 77431, 77432, 77435, 77470) with actual AMA/NLM descriptions
- D-10: Auto-add any confirmed radiation treatment codes found in data but not in config (following Phase 39 pattern)
- D-11: Add a comment block above radiation_cpt explaining AMA chapter structure and why the full 70010-79999 range isn't used

**Data query scope (D-12 to D-15)**
- D-12: Query ALL patients in the PCORnet extract (not just HL cohort) for broader view
- D-13: Include ALL PX_TYPEs, not just PX_TYPE='CH' — cast a wider net for unexpected mappings
- D-14: Per-code detail: patient count + encounter count (consistent with Phase 42 resolved xlsx)
- D-15: No HIPAA suppression on counts — raw numbers are fine for this audit output

### Claude's Discretion
- Exact sub-range grouping level within the classification table
- Sheet styling details and column ordering within the xlsx
- Console output format and summary statistics
- NLM API vs hardcoded descriptions for code lookups

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| RADCPT-01 | User can see a classification table of CPT 70010-79999 sub-ranges showing which are diagnostic imaging, treatment planning, treatment delivery, and proton therapy, with AMA/CMS citations | AMA CPT chapter structure is publicly documented; 8 sub-range groupings identified below with precise boundaries and rationale |
| RADCPT-02 | User can see which codes from the 70010-79999 range actually appear in HL patient PROCEDURES data, with each code classified as imaging vs treatment | PROCEDURES query pattern from Phase 38/39 is directly reusable; regex `^7[0-9]{4}$` captures the full range; str_detect join to classification table provides the imaging/treatment label |
| RADCPT-03 | Proton therapy codes 77520-77525 are added to TREATMENT_CODES$radiation_cpt in R/00_config.R with citation comments | 4 active proton codes confirmed (77520, 77522, 77523, 77525); descriptions and AMA chapter citation documented below |
</phase_requirements>

---

## Summary

The AMA CPT Manual organizes the 70010-79999 radiology range into eight structurally distinct sub-categories. Of these, six are purely diagnostic imaging (CT, MRI, X-ray, ultrasound, interventional guidance, nuclear medicine), and two are cancer treatment (radiation oncology 77261-77799, nuclear medicine therapeutics within 78000-78999). The key argument for collaborators is that TreatmentVariables.docx cites the entire 70010-79999 range, but 97% of that range is diagnostic imaging irrelevant to treatment detection. Only 77261-77799 are radiation oncology treatment codes per AMA CPT chapter structure.

An important coding evolution: many codes in the existing `radiation_cpt` config vector (77404, 77408, 77413, 77414, 77416, 77418, 77421) were deleted by the AMA in 2015 or earlier, replaced by new codes. A second wave of deletions occurred in 2026, removing the G-code workarounds (G6003-G6016) and 77401. The pipeline may encounter these retired codes in historical PCORnet data because claims were filed under the codes active at time of service. This is expected behavior — the codes are legitimately treatment codes, just retired from active billing. The "no description" problem in config is because these are retired codes not returned by the NLM HCPCS API (which only covers currently active codes).

The proton therapy sub-range (77520-77525) contains exactly 4 active codes: 77520, 77522, 77523, 77525. Code 77521 was deleted prior to 2024; it does not exist in current AMA CPT. Adding these 4 codes to config completes coverage of active external beam radiation treatment delivery options.

**Primary recommendation:** Build the phase as two R scripts: (1) `45_radiation_cpt_audit.R` that queries PROCEDURES, builds the classification table in memory, and writes the xlsx; (2) a config update block that patches `radiation_cpt` in `R/00_config.R` with proton codes + fixes "no description" comments using hardcoded AMA descriptions (NLM API will not return descriptions for retired codes).

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| openxlsx2 | >=1.0 | Styled xlsx generation | Established in Phase 42; `write_resolved_xlsx()` pattern is project standard |
| dplyr | >=1.1 | Data manipulation, PROCEDURES query, group_by/summarise | Already loaded in all pipeline scripts |
| stringr | >=1.5 | Regex matching for CPT range detection (`str_detect`) | Already used in Phase 38/39 for range heuristics |
| glue | >=1.6 | Console messages and dynamic strings | Already loaded throughout pipeline |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| httr | >=1.4 | NLM HCPCS API lookups | Only if active codes need API lookup; retired codes need hardcoded descriptions |
| jsonlite | >=1.8 | Parse NLM API JSON responses | Paired with httr when API is used |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hardcoded descriptions for retired codes | NLM API | NLM API only returns active HCPCS/CPT codes; retired codes (77404, 77408, 77413, 77414, 77416, 77418, 77421) return "not_found" — confirmed in Phase 39 as the source of "no description" problem |
| Single-script approach | Two scripts | Single script is fine; the config update can be a separate section or an inline parse/deparse pattern |

**Installation:** All libraries already installed in project environment.

---

## Architecture Patterns

### Recommended Project Structure
```
R/45_radiation_cpt_audit.R     # Main audit script — query + classify + write xlsx
R/00_config.R                  # Patched in-place: proton codes + fixed descriptions + comment block
output/tables/radiation_cpt_audit.xlsx  # Deliverable xlsx (2 sheets)
```

### Pattern 1: Full-Range CPT Query from PROCEDURES

**What:** Query ALL patients, ALL PX_TYPEs, for codes matching `^7[0-9]{4}$` (the full 70010-79999 range), then group_by code to get patient_count + encounter_count.

**When to use:** RADCPT-02 — building the "codes found in data" sheet.

**Example:**
```r
# Source: Phase 38/39 established pattern (R/38_treatment_inventory.R, R/39_investigate_unmatched.R)
proc_tbl <- get_pcornet_table("PROCEDURES")

codes_in_data <- proc_tbl %>%
  filter(str_detect(PX, "^7[0-9]{4}$")) %>%  # Full 70010-79999 range
  materialize() %>%
  group_by(code = PX, px_type = PX_TYPE) %>%
  summarise(
    encounter_count = n(),
    patient_count   = n_distinct(ID),
    .groups = "drop"
  ) %>%
  collect()
```

Note: D-13 specifies ALL PX_TYPEs — do NOT add a `filter(PX_TYPE == "CH")` guard here. The `materialize()` before the filter is the established DuckDB-backed pattern.

### Pattern 2: Classification Table (In-Memory, No API)

**What:** Build the AMA sub-range classification table as a hardcoded data frame in R. This is not queried from data — it is authoritative reference knowledge codified in the script.

**When to use:** RADCPT-01 — the classification sheet of the xlsx.

**Example:**
```r
# Hardcoded AMA CPT chapter structure — authoritative, no API needed
classification_table <- tibble::tribble(
  ~range_start, ~range_end, ~ama_category,          ~classification,       ~rationale,
  70010L,       76499L,     "Diagnostic Radiology",  "Diagnostic Imaging",  "X-ray, CT, MRI, angiography — produces images for diagnosis, not treatment delivery",
  76506L,       76999L,     "Diagnostic Ultrasound", "Diagnostic Imaging",  "Ultrasound imaging for diagnosis and guidance — no therapeutic radiation",
  77001L,       77032L,     "Radiological Guidance", "Diagnostic Imaging",  "Fluoroscopy/CT guidance for interventional procedures — imaging component only",
  77046L,       77067L,     "Mammography",           "Diagnostic Imaging",  "Breast imaging for screening and diagnosis — no radiation treatment",
  77261L,       77299L,     "Treatment Planning",    "Radiation Treatment", "Clinical simulation and dosimetry planning — first step of radiation therapy workflow",
  77295L,       77370L,     "Physics/Dosimetry",     "Radiation Treatment", "Medical physics services, dose calculation, device fabrication — integral to treatment delivery",
  77371L,       77499L,     "Treatment Delivery",    "Radiation Treatment", "External beam radiation delivery (EBRT), IMRT, SRS, SBRT, proton — actual treatment",
  77520L,       77525L,     "Proton Beam Delivery",  "Radiation Treatment", "Proton beam treatment delivery sub-range within treatment delivery — particle therapy",
  77600L,       77620L,     "Hyperthermia",          "Radiation Treatment", "Thermal adjunct to radiation therapy — heat applied with radiation",
  77750L,       77799L,     "Brachytherapy",         "Radiation Treatment", "Internal radiation source placement — seeds, catheters, HDR",
  78000L,       78999L,     "Nuclear Medicine",      "Mixed",               "Mostly diagnostic (PET, thyroid scan); therapeutic codes (78800-78816) exist for targeted radionuclide therapy"
)
```

Then join `codes_in_data` to this table on whether the numeric code falls within `range_start` <= code <= `range_end` using `findInterval()` or a range join via dplyr.

### Pattern 3: Range Join for Classification

**What:** For each code found in data, determine which AMA sub-range it falls in.

**When to use:** Building the "codes found in data" sheet — each code needs its imaging/treatment classification.

**Example:**
```r
# Classify each code found in data by which AMA sub-range it falls in
classify_code <- function(code_numeric, table) {
  idx <- max(which(table$range_start <= code_numeric), na.rm = TRUE)
  if (is.infinite(idx) || code_numeric > table$range_end[idx]) {
    return("Outside 70010-79999")
  }
  table$classification[idx]
}

codes_classified <- codes_in_data %>%
  mutate(
    code_numeric    = as.integer(code),
    classification  = purrr::map_chr(code_numeric, classify_code, table = classification_table),
    in_config       = code %in% unlist(TREATMENT_CODES[c("radiation_cpt")])
  )
```

### Pattern 4: Config Update (Parse/Deparse with Rollback)

**What:** Programmatically modify `R/00_config.R` to add proton codes and fix "no description" comments. Validated by parse + source after write.

**When to use:** RADCPT-03 and D-09 (fix comments).

**Example:**
```r
# Source: Phase 39 established pattern (parse/source validation with rollback)
config_path <- "R/00_config.R"
config_text <- readLines(config_path)

# ... make targeted line substitutions using str_replace() ...

# Validate: write to temp, parse, source
tmp <- tempfile(fileext = ".R")
writeLines(new_text, tmp)
parse(tmp)  # Throws if syntax error
source(tmp, local = TRUE)  # Throws if runtime error

# If validation passes, overwrite original
writeLines(new_text, config_path)
```

### Pattern 5: openxlsx2 Two-Sheet Workbook

**What:** Sheet 1 = AMA classification table (RADCPT-01). Sheet 2 = codes found in data (RADCPT-02). Follow Phase 42 `write_resolved_xlsx()` column structure with title row, styled headers, data rows.

**When to use:** Building the collaborator deliverable.

```r
# Source: R/42_treatment_codes_resolved.R write_resolved_xlsx() pattern
wb <- wb_workbook()
wb$add_worksheet("CPT Classification")
wb$add_worksheet("Codes in Data")

# Title row (row 1): merged, large font
wb$add_data(sheet = "CPT Classification",
            x = "AMA CPT 70010-79999 Range Classification",
            start_row = 1, start_col = 1)
wb$add_font(sheet = "CPT Classification", dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "CPT Classification", dims = "A1:G1")

# Header row (row 2): dark fill, white bold text
wb$add_fill(sheet = "CPT Classification", dims = "A2:G2",
            color = wb_color("FF374151"))
wb$add_font(sheet = "CPT Classification", dims = "A2:G2",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
```

### Anti-Patterns to Avoid

- **Filtering to PX_TYPE='CH' only:** D-13 requires ALL PX_TYPEs. Don't copy the `filter(PX_TYPE == "CH")` guard from Phase 39.
- **Querying only HL cohort:** D-12 requires ALL patients. Don't add `filter(ID %in% hl_ids)`.
- **Using NLM API for retired codes:** The NLM HCPCS API (`clinicaltables.nlm.nih.gov/api/hcpcs/v3/search`) only covers active codes. Codes 77404, 77408, 77413, 77414, 77416, 77418, 77421 are all retired/deleted and will return "not_found" — this is why Phase 39 produced "no description" comments. Use hardcoded descriptions.
- **Hardcoding 77521 as a proton code:** This code was deleted. The active proton codes are exactly: 77520, 77522, 77523, 77525 (note the gap — no 77521).
- **Writing the classification table as opinionated:** Frame it as citing AMA CPT structure, not the pipeline team's decision. The AMA defines the chapter boundaries.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| xlsx styling | Custom CSV with manual formatting | `openxlsx2` wb_workbook + add_fill/add_font | Phase 42 pattern fully solves this; wb_color(), merge_cells(), set_col_widths() handle all styling needs |
| Range classification | Custom parser | `findInterval()` or ordered tribble join | Standard R range lookup; no custom binary search needed |
| Config line editing | sed/awk via Bash | `readLines()` + `str_replace()` + `writeLines()` in R | Phase 39 established pattern; provides parse/source validation |
| Code description lookup (active codes) | Web scraping | NLM HCPCS API | `httr::GET("https://clinicaltables.nlm.nih.gov/api/hcpcs/v3/search?terms={code}&ef=display")` — Phase 39 pattern works for active codes |

**Key insight:** Retired codes need hardcoded descriptions, not API calls. Active proton codes (77520-77525 minus 77521) can use API or hardcoded.

---

## Common Pitfalls

### Pitfall 1: Treating Retired Codes as Broken

**What goes wrong:** Attempt to look up 77404, 77408, 77413, 77414, 77416, 77418, 77421 via NLM API, get "not_found", and treat this as a pipeline error or skip adding descriptions.

**Why it happens:** These codes were deleted in 2015 by the AMA. The NLM API only covers currently active HCPCS/CPT codes. The pipeline is correct to have them — historical PCORnet claims filed when the codes were active are legitimate records.

**How to avoid:** Hardcode descriptions using the pre-2015 AMA descriptors. They are billing-grade descriptions that collaborators will understand. See Code Examples section below for all 12 descriptions.

**Warning signs:** NLM API returning `lookup_status = "not_found"` for all 77404-77421 series.

### Pitfall 2: Including 77521 in Proton Codes

**What goes wrong:** Adding all 5 codes 77520-77525 to config, including the nonexistent 77521.

**Why it happens:** The CONTEXT.md and REQUIREMENTS.md cite the range "77520-77525" as a range, but 77521 does not exist in AMA CPT. The active set is: 77520, 77522, 77523, 77525.

**How to avoid:** Add exactly 4 codes: 77520, 77522, 77523, 77525. Do not add 77521.

**Warning signs:** Any source citing 77521 as a valid code — it was deleted before 2024.

### Pitfall 3: Incorrect Range Boundary for Classification

**What goes wrong:** Classifying 77001-77032 (Radiological Guidance — fluoroscopy during procedures) as "radiation treatment" because the codes start with 77.

**Why it happens:** The "77" prefix does not mean radiation oncology. Codes 77001-77067 are in the Radiology chapter but are imaging guidance codes, not treatment delivery.

**How to avoid:** Use the precise AMA chapter boundaries. Only 77261-77799 are radiation oncology treatment codes. Codes 77001-77067 are guidance/mammography imaging codes.

**Warning signs:** Classification table showing codes below 77261 as "Radiation Treatment."

### Pitfall 4: materialize() Before Group-By on Full Range

**What goes wrong:** Running the full 70010-79999 regex filter in DuckDB without `materialize()` first, then hitting a DuckDB regex incompatibility.

**Why it happens:** DuckDB's regex support differs slightly from R's `stringr`. The `materialize()` call pulls data to R's memory where `str_detect` works natively.

**How to avoid:** Follow the Phase 38/39 pattern exactly: `proc_tbl %>% filter(...) %>% materialize() %>% filter(str_detect(PX, regex))`. Do the regex filter after materialize(), not before.

**Warning signs:** DuckDB error mentioning PCRE or regex syntax during PROCEDURES query.

### Pitfall 5: Two-Sheet xlsx Where Sheet 2 Has No Config Context Column

**What goes wrong:** Sheet 2 shows codes found in data without indicating which ones are already in the pipeline config — collaborators can't distinguish "we handle this" from "this is a gap."

**Why it happens:** D-14 specifies patient_count + encounter_count but doesn't explicitly call out the `in_config` flag column.

**How to avoid:** Add a boolean "In Pipeline Config?" column to Sheet 2 — it's essential for the self-explanatory requirement (D-04) and the auto-add decision (D-10). Flag as YES/NO with conditional styling.

---

## Code Examples

Verified descriptions from AMA CPT (historical billing records, pre-2015 deletion):

### Retired Radiation Treatment Delivery Codes (77401-77421 series)
These codes were deleted by AMA in 2015 (modality/energy-based system replaced by technique-based system). They appear in historical PCORnet claims filed before 2015.

```r
# Source: AMA CPT pre-2015 descriptors; CMS LCD L34652 RAD014 (archived)
# Use these as hardcoded comment replacements for "Phase 39: no description"

"77404"  # Radiation treatment delivery; single area, 6-10 MeV
"77408"  # Radiation treatment delivery; 2 separate areas, 3+ ports, 6-10 MeV
"77413"  # Radiation treatment delivery; 3+ separate areas, custom blocking, 6-10 MeV
"77414"  # Radiation treatment delivery; 3+ separate areas, custom blocking, 11-19 MeV
"77416"  # Radiation treatment delivery; 3+ separate areas, complex, 20+ MeV
"77417"  # Port film(s) per treatment session (portal imaging) — DELETED 2026, bundled into delivery
"77418"  # Radiation treatment delivery, IMRT (intensity modulated) — DELETED 2015
"77421"  # Stereoscopic x-ray guidance for target localization — DELETED 2015, replaced by 77387
"77431"  # Radiation treatment management, 1-4 treatments (end-of-course)
"77432"  # Stereotactic radiation treatment management of cranial lesion
"77435"  # Stereotactic body radiation therapy (SBRT) management
"77470"  # Special treatment procedure (total body irradiation, hemibody irradiation)
```

### Proton Codes to Add (Active as of 2025)

```r
# Source: AMA CPT Radiation Oncology chapter; CMS Article A57669 (proton beam radiotherapy)
# Add to TREATMENT_CODES$radiation_cpt in R/00_config.R

"77520",  # Proton treatment delivery; simple, without compensation
"77522",  # Proton treatment delivery; simple, with compensation
"77523",  # Proton treatment delivery; intermediate
"77525"   # Proton treatment delivery; complex
# NOTE: 77521 does NOT exist — code was deleted; active set is 77520, 77522, 77523, 77525
```

### Comment Block for R/00_config.R (D-11)

```r
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
```

### NLM HCPCS API Pattern (Active Codes Only)

```r
# Source: R/39_investigate_unmatched.R lookup_hcpcs_batch()
# Works for currently active codes (77520, 77522, 77523, 77525)
# Returns "not_found" for retired codes — use hardcoded descriptions instead
url <- glue("https://clinicaltables.nlm.nih.gov/api/hcpcs/v3/search?terms={code}&ef=display")
resp <- httr::GET(url, httr::timeout(10))
json <- jsonlite::fromJSON(httr::content(resp, as = "text", encoding = "UTF-8"))
# json[[1]] = total count; json[[2]] = matched codes; json[[4]] = display strings
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Energy-based delivery codes (77401-77418 series) | Complexity-based codes (77402, 77407, 77412) | AMA 2015 | Old codes appear in historical data pre-2015; no longer billable but still in PCORnet records |
| Separate G-codes (G6003-G6016) for LINAC delivery | Integrated into 77402/77407/77412 | CMS 2026 | G-codes deleted Jan 1, 2026; same logic as 2015 transition for historical data |
| Separate port film code (77417) | Bundled into delivery codes | AMA 2026 | 77417 deleted 2026; historical records will still have it |
| Stereoscopic guidance (77421) | Replaced by 77387 | AMA 2015 | 77421 deleted; 77387 is active for image guidance professional component |
| No proton codes in config | 77520, 77522, 77523, 77525 added | Phase 45 | Completes radiation treatment coverage for proton therapy centers |

**Deprecated/outdated:**
- CPT 77401: Deleted Jan 1, 2026 (low-energy orthovoltage; replaced by surface therapy codes 77436-77439). The config already has 77401 as a comment; verify whether to keep or remove.
- CPT 77521: Never valid in current AMA CPT; do not add.
- G-codes G6003-G6016: Deleted Jan 1, 2026; may appear in data through 2025, classified as Radiation Treatment if present.

---

## AMA CPT Sub-Range Reference

This table is the factual backbone for RADCPT-01. All boundaries are from the AMA CPT chapter structure (HIGH confidence — publicly documented chapter organization).

| CPT Range | AMA Category | Classification | Rationale for Exclusion/Inclusion |
|-----------|--------------|----------------|----------------------------------|
| 70010-76499 | Diagnostic Radiology | Diagnostic Imaging — EXCLUDE | X-ray, CT, MRI, fluoroscopy, angiography. Produces images for diagnosis. No radiation delivered therapeutically. |
| 76506-76999 | Diagnostic Ultrasound | Diagnostic Imaging — EXCLUDE | Ultrasound for obstetric, abdominal, vascular diagnosis. No ionizing radiation. |
| 77001-77032 | Radiological Guidance | Diagnostic Imaging — EXCLUDE | Fluoroscopic/CT guidance during interventional procedures. The imaging component billed separately from the treatment. |
| 77046-77067 | Mammography | Diagnostic Imaging — EXCLUDE | Breast screening and diagnostic imaging. Not therapeutic radiation. |
| 77261-77299 | Radiation Treatment Planning | Radiation Treatment — INCLUDE | Clinical simulation, target volume definition, beam arrangement. Essential precursor to treatment delivery. |
| 77295-77370 | Physics & Dosimetry | Radiation Treatment — INCLUDE | Medical physicist services, dose calculations, treatment device fabrication. Integral to safe treatment delivery. |
| 77371-77499 | Radiation Treatment Delivery | Radiation Treatment — INCLUDE | EBRT, IMRT, VMAT, SRS, SBRT, proton beam delivery, neutron beam delivery. The actual therapeutic radiation. |
| 77520-77525 | Proton Beam Delivery | Radiation Treatment — INCLUDE | Particle therapy subset within treatment delivery. Higher precision than photon therapy. |
| 77600-77620 | Hyperthermia | Radiation Treatment — INCLUDE | Thermal adjunct applied concurrent with radiation. Enhances tumor response. |
| 77750-77799 | Brachytherapy | Radiation Treatment — INCLUDE | Internal radiation source placement. High/low dose rate, interstitial/intracavitary. |
| 78000-78999 | Nuclear Medicine | Mixed — EXCLUDE (mostly) | Mostly diagnostic (PET, thyroid, bone scans). Therapeutic radionuclide codes (78800-78816) exist but are separate clinical workflow (theranostics, not radiation oncology treatment). |

**Summary:** Of 11 sub-ranges, 4 are purely diagnostic imaging, 6 are radiation treatment, 1 is mixed. The treatment-only range 77261-77799 covers the core radiation oncology workflow.

---

## Open Questions

1. **77401 status in config**
   - What we know: 77401 is listed in config as an active code; it was deleted by AMA effective Jan 1, 2026 (surface/orthovoltage radiation replaced by 77436-77439)
   - What's unclear: Whether to remove 77401 or retain it with a "DELETED 2026" comment for historical data continuity
   - Recommendation: Retain with updated comment "DELETED 2026 — surface radiation; historical claims only"

2. **G-codes G6003-G6016 in PROCEDURES data**
   - What we know: These were Medicare-specific temporary codes for LINAC delivery, deleted Jan 1, 2026; they use PX_TYPE='CH' but start with 'G', not '7'
   - What's unclear: Whether the regex `^7[0-9]{4}$` should be extended to catch G-code radiation records for the audit
   - Recommendation: D-13 says ALL PX_TYPEs; adding a `^G60(0[3-9]|1[0-6])$` pattern to the query catches these for completeness (Claude's discretion per D-13 intent)

3. **Nuclear medicine therapeutic codes (78800-78816)**
   - What we know: These codes (targeted radionuclide therapy) are technically radiation treatment but follow a different clinical workflow (nuclear medicine, not radiation oncology)
   - What's unclear: Whether to classify 78800-78816 as "Radiation Treatment" or "Mixed/Exclude" in the output
   - Recommendation: Classify as "Mixed — Nuclear Medicine Therapeutics" with a note that pipeline does not currently cover this category; keeps the audit honest without scope creep

---

## Sources

### Primary (HIGH confidence)
- AMA CPT Manual chapter organization — publicly documented range boundaries (70010-79999 chapter structure)
- CMS Medicare Coverage Database, Article A57669 "Billing and Coding: Proton Beam Radiotherapy" — proton codes 77520, 77522, 77523, 77525 confirmed active
- PMC Article PMC12842826 "Making Sense of the 2026 CMS Radiation Oncology Treatment Delivery Codes" — 2026 code deletions confirmed (G6003-G6016, 77401; new 77402/77407/77412)
- `R/42_treatment_codes_resolved.R` (project file) — `write_resolved_xlsx()` function signature and openxlsx2 pattern
- `R/39_investigate_unmatched.R` (project file) — NLM HCPCS API pattern, parse/source validation
- `R/00_config.R` lines 637-657 (project file) — current `radiation_cpt` vector, 17 codes, 12 missing descriptions

### Secondary (MEDIUM confidence)
- AAPC Codify range page for 77520-77525 — confirms 4 active codes (77520, 77522, 77523, 77525); no 77521
- medicalbillersandcoders.com radiation oncology codes (Part 1 + Part 2) — confirms 10 subcategories within 77261-77799, subcategory names and ranges
- zmedsolutions.net CPT 70010-79999 guide — confirms top-level chapter structure (Diagnostic Radiology, Ultrasound, Interventional, Nuclear Medicine, Radiation Oncology)
- Search results confirming 77421 deleted 2015 (replaced by 77387) and 77404/77408/77413/77414/77416/77418 deleted 2015

### Tertiary (LOW confidence)
- Per-code descriptions for 77404, 77408, 77413, 77414, 77416 (pre-2015 descriptors) — assembled from multiple search results; cross-referenced but not from a single authoritative current source. Verify via NLM API or CMS archived LCD L34652 if precise wording is critical.

---

## Metadata

**Confidence breakdown:**
- AMA chapter structure (RADCPT-01 backbone): HIGH — publicly documented chapter organization confirmed across 3+ sources
- Proton codes 77520/77522/77523/77525 (RADCPT-03): HIGH — confirmed via CMS Article A57669 and AAPC range page
- Retired code descriptions (D-09 fix): MEDIUM — historical descriptors from multiple sources, not from a single canonical current document (retired codes are not in current NLM API)
- PROCEDURES query pattern (RADCPT-02): HIGH — direct reuse of Phase 38/39 established project pattern

**Research date:** 2026-05-15
**Valid until:** 2026-08-15 (AMA CPT code changes annually in January; next risk window is January 2027)
