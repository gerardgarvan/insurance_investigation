# Phase 8: Add Insurance Mode Around Treatment Types - Research

**Researched:** 2026-03-25
**Domain:** Treatment identification from PCORnet procedures/prescribing tables and temporal window-based payer mode calculation
**Confidence:** MEDIUM

## Summary

This phase computes payer mode within ±30 day windows around first treatment dates for chemotherapy, radiation therapy, and stem cell transplant. The implementation mirrors the existing `PAYER_CATEGORY_AT_FIRST_DX` pattern from `02_harmonize_payer.R` but anchors on treatment procedure dates instead of diagnosis dates.

**Key findings:**
- Existing code provides complete template: `PAYER_CATEGORY_AT_FIRST_DX` computation in `02_harmonize_payer.R` §4c is directly reusable with different anchor dates
- PCORnet PROCEDURES table PX_TYPE values confirmed: "09" (ICD-9-CM), "10" (ICD-10-PCS), "CH" (CPT/HCPCS combined)
- ICD procedure codes needed: comprehensive code lists identified for all three treatment types across ICD-9-CM and ICD-10-PCS
- Mode calculation pattern already handles ties via `arrange(desc(n), payer_category) %>% slice(1)` — deterministic tie-breaking by alphabetical order
- Temporal window joins use `inner_join()` + `filter(abs(days_from_date) <= window)` pattern already proven in codebase

**Primary recommendation:** Create standalone `10_treatment_payer.R` script with three nearly-identical functions (one per treatment type), each following the exact §4c pattern: (1) extract first treatment date from PROCEDURES/PRESCRIBING, (2) join to encounters with valid payer, (3) filter ±30 day window, (4) compute mode via group_by + slice. Source in `04_build_cohort.R` §6.5 (new subsection between treatment flags and final assembly).

## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Anchor the ±30 day window on PX_DATE from the PROCEDURES table (not TUMOR_REGISTRY dates)
- **D-02:** Include ALL procedure code types: PX_TYPE == "CH" (HCPCS/CPT) AND PX_TYPE == "09" (ICD-9 procedure) AND PX_TYPE == "10" (ICD-10-PCS)
- **D-03:** For chemotherapy specifically, also anchor on RX_ORDER_DATE from PRESCRIBING table when RXNORM_CUI matches chemo codes — more anchor points for chemo
- **D-04:** Will need to add ICD-9-CM and ICD-10-PCS procedure code lists for chemo, radiation, and SCT to 00_config.R TREATMENT_CODES
- **D-05:** Use the FIRST treatment procedure date per patient per treatment type as the window anchor (mirrors PAYER_CATEGORY_AT_FIRST_DX pattern)
- **D-06:** Capture first treatment dates as output columns: FIRST_CHEMO_DATE, FIRST_RADIATION_DATE, FIRST_SCT_DATE
- **D-07:** Payer mode computed from encounters within ±30 days of that first date, using CONFIG$analysis$treatment_window_days (already defined as 30)
- **D-08:** Add new columns directly to hl_cohort in 04_build_cohort.R: PAYER_AT_CHEMO, PAYER_AT_RADIATION, PAYER_AT_SCT, FIRST_CHEMO_DATE, FIRST_RADIATION_DATE, FIRST_SCT_DATE
- **D-09:** Create new standalone script (e.g., 10_treatment_payer.R) with functions, sourced by 04_build_cohort.R
- **D-10:** Column naming follows existing pattern: PAYER_AT_CHEMO / PAYER_AT_RADIATION / PAYER_AT_SCT (consistent with PAYER_CATEGORY_AT_FIRST_DX)
- **D-11:** When a patient has treatment evidence but no encounters with valid payer within ±30 days, set payer column to NA (honest about missing data)
- **D-12:** Log match counts per treatment type: "PAYER_AT_CHEMO: N matched, M no encounters in window (NA)" — consistent with existing pipeline logging style

### Claude's Discretion
- ICD-9-CM and ICD-10-PCS procedure code selection for chemo, radiation, and SCT
- Internal function structure within 10_treatment_payer.R
- Exact placement of the source() call and column joins in 04_build_cohort.R
- Whether to reuse existing `encounters` object from 02_harmonize_payer.R or re-query

### Deferred Ideas
None — discussion stayed within phase scope

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation and joins | Already used throughout pipeline; temporal window joins via `inner_join()` + `filter()` |
| lubridate | 1.9.3+ | Date arithmetic | Calculate `days_from_treatment = as.numeric(ADMIT_DATE - first_treatment_date)` for window filtering |
| glue | 1.8.0+ | Logging messages | Consistent with existing attrition logging: `message(glue("..."))` |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| stringr | 1.5.1+ | String operations (optional) | Only if ICD procedure code normalization needed (unlikely for PROCEDURES table PX field) |
| readr | 2.2.0+ | CSV output (optional) | Only if diagnostic CSVs needed (not required by phase) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| dplyr temporal join | data.table non-equi join | 10x faster but violates "named predicate" readability requirement |
| Manual mode calculation | DescTools::Mode() | External dependency for trivial operation already implemented in codebase |
| Separate encounters reload | Reuse existing `encounters` object | Reloading wastes memory; `encounters` already has `payer_category` and `ADMIT_DATE` |

**Installation:**
No new packages needed — all libraries already installed per Phase 1.

## Architecture Patterns

### Recommended Project Structure
```
R/
├── 10_treatment_payer.R  # New: treatment-anchored payer mode functions
├── 04_build_cohort.R     # Modified: source 10_*, join new columns
└── 00_config.R           # Modified: add ICD-9/10-PCS procedure codes to TREATMENT_CODES
```

### Pattern 1: First Treatment Date Extraction
**What:** Combine PROCEDURES (PX_DATE) and PRESCRIBING (RX_ORDER_DATE for chemo only) to find earliest treatment date per patient per treatment type
**When to use:** Once per treatment type (chemo, radiation, SCT)
**Example:**
```r
# Source: Adapted from R/02_harmonize_payer.R §3 (first HL diagnosis date pattern)
# PROCEDURES: all three treatment types
px_chemo_dates <- pcornet$PROCEDURES %>%
  filter(
    (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) |
    (PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9) |
    (PX_TYPE == "10" & PX %in% TREATMENT_CODES$chemo_icd10pcs)
  ) %>%
  group_by(ID) %>%
  summarise(first_chemo_date_px = min(PX_DATE, na.rm = TRUE), .groups = "drop")

# PRESCRIBING: chemo only (D-03)
rx_chemo_dates <- pcornet$PRESCRIBING %>%
  filter(!is.na(RXNORM_CUI) & RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
  group_by(ID) %>%
  summarise(first_chemo_date_rx = min(RX_ORDER_DATE, na.rm = TRUE), .groups = "drop")

# Combine and take earliest
first_chemo <- px_chemo_dates %>%
  full_join(rx_chemo_dates, by = "ID") %>%
  mutate(FIRST_CHEMO_DATE = pmin(first_chemo_date_px, first_chemo_date_rx, na.rm = TRUE)) %>%
  select(ID, FIRST_CHEMO_DATE)
```

### Pattern 2: Temporal Window Join with Mode Calculation
**What:** Join encounters to treatment dates, filter ±30 days, compute payer mode
**When to use:** Once per treatment type after first treatment date extracted
**Example:**
```r
# Source: Direct copy from R/02_harmonize_payer.R §4c (PAYER_CATEGORY_AT_FIRST_DX)
window_days <- CONFIG$analysis$treatment_window_days  # 30

payer_at_chemo <- encounters %>%
  filter(!is.na(effective_payer) &
         nchar(trimws(effective_payer)) > 0 &
         !effective_payer %in% PAYER_MAPPING$sentinel_values) %>%
  inner_join(first_chemo, by = "ID") %>%
  mutate(days_from_treatment = as.numeric(ADMIT_DATE - FIRST_CHEMO_DATE)) %>%
  filter(!is.na(days_from_treatment) & abs(days_from_treatment) <= window_days) %>%
  group_by(ID, payer_category) %>%
  summarise(n = n(), .groups = "drop") %>%
  arrange(ID, desc(n), payer_category) %>%  # Tie-breaking: alphabetical
  group_by(ID) %>%
  slice(1) %>%
  ungroup() %>%
  select(ID, PAYER_AT_CHEMO = payer_category)
```

### Pattern 3: Function Wrapper for Reusability
**What:** Wrap Patterns 1+2 into single function per treatment type
**When to use:** Recommended to reduce code duplication
**Example:**
```r
# Source: New pattern (follows existing named function convention from 03_cohort_predicates.R)
#' Compute payer mode at first chemotherapy
#' @return Tibble with columns: ID, FIRST_CHEMO_DATE, PAYER_AT_CHEMO
compute_payer_at_chemo <- function() {
  # Pattern 1: Extract first chemo date (PROCEDURES + PRESCRIBING)
  first_chemo <- extract_first_chemo_date()  # Helper function

  # Pattern 2: Temporal window join + mode
  payer_at_chemo <- compute_payer_mode_at_date(
    first_dates = first_chemo,
    date_col = "FIRST_CHEMO_DATE",
    payer_col = "PAYER_AT_CHEMO"
  )

  # Join dates and payer together
  first_chemo %>%
    left_join(payer_at_chemo, by = "ID")
}
```

### Anti-Patterns to Avoid
- **Don't reload PROCEDURES/PRESCRIBING within function:** Already loaded in `pcornet` list by `01_load_pcornet.R`, reloading wastes I/O
- **Don't use `slice_min()` for mode:** Returns ALL ties; existing `arrange(desc(n)) %>% slice(1)` is deterministic and proven
- **Don't compute window in join condition:** Use `filter()` after join for readability and debuggability
- **Don't forget NA handling:** `pmin(..., na.rm = TRUE)` when combining dates; `filter(!is.na(days_from_treatment))` when windowing

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Mode calculation with ties | Custom tie-breaking logic | `arrange(desc(n), payer_category) %>% slice(1)` | Already implemented in §4c; alphabetical tie-breaking is deterministic and auditable |
| Temporal window joins | Custom date comparison loops | `inner_join() + filter(abs(days_from_date) <= window)` | Proven pattern in §4c; readable, debuggable, fast enough for 10K patients |
| First date aggregation | Row-by-row min tracking | `group_by(ID) %>% summarise(min(date, na.rm = TRUE))` | dplyr's grouped summarise is optimized and handles NA correctly |
| Empty window handling | Custom NA-fill logic | `left_join()` naturally returns NA when no match | R's join semantics handle missing matches correctly (D-11) |

**Key insight:** Every operation needed for this phase is already implemented in `02_harmonize_payer.R` §4c (PAYER_CATEGORY_AT_FIRST_DX). The entire phase is "copy §4c, change the anchor date source, repeat 3 times."

## Common Pitfalls

### Pitfall 1: PX_TYPE Value Confusion
**What goes wrong:** Assuming "CH" means "chemo" when it actually means "CPT/HCPCS combined"
**Why it happens:** PCORnet v7.0 collapsed CPT and HCPCS into single "CH" category; unintuitive naming
**How to avoid:** Always filter `PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs` (code list is specific, PX_TYPE is generic)
**Warning signs:** Picking up non-chemo procedures like surgeries (CPT includes all outpatient procedures); validate first treatment date distributions match clinical expectations

### Pitfall 2: ICD-9 vs ICD-10-PCS Date Cutoff
**What goes wrong:** Using only ICD-10-PCS codes misses pre-2015 treatments
**Why it happens:** ICD-10-PCS adopted October 1, 2015; older procedures coded in ICD-9-CM Volume 3
**How to avoid:** Include BOTH `PX_TYPE == "09"` (ICD-9-CM) and `PX_TYPE == "10"` (ICD-10-PCS) filters (D-02)
**Warning signs:** Patients diagnosed before 2015 with no treatment dates found; sudden drop in treatment counts pre-2015

### Pitfall 3: Diagnostic vs Therapeutic Procedure Codes
**What goes wrong:** Including diagnostic procedures (e.g., radiation imaging) inflates treatment counts
**Why it happens:** CPT codes overlap between diagnostic and therapeutic intent
**How to avoid:** Use narrow, treatment-specific code lists validated against clinical guidelines (NCCN, ASBMT)
**Warning signs:** Treatment dates significantly earlier than diagnosis dates; >95% treatment rates (unrealistic for cancer cohort)

### Pitfall 4: Mode Ties Not Deterministic
**What goes wrong:** Using `slice_min(n, n=1, with_ties=FALSE)` returns arbitrary tie winner, non-reproducible
**Why it happens:** Default tie-breaking in some dplyr functions is non-deterministic
**How to avoid:** Use `arrange(desc(n), payer_category) %>% slice(1)` — alphabetical secondary sort ensures reproducibility
**Warning signs:** Payer mode changes between identical runs; difficult-to-debug "flaky" pipeline behavior

### Pitfall 5: Empty Windows Not Logged
**What goes wrong:** Silent NA assignment when no encounters in ±30 days; users don't know why payer is missing
**Why it happens:** `left_join()` silently returns NA when no match
**How to avoid:** Log match counts (D-12): `n_matched <- sum(!is.na(payer_at_chemo$PAYER_AT_CHEMO)); message(glue("{n_matched} matched, {nrow(first_chemo) - n_matched} no encounters in window"))`
**Warning signs:** High NA rates (>20%) without logged explanation; confusion about "why so many missing payers?"

### Pitfall 6: RX_ORDER_DATE ≠ Treatment Start Date
**What goes wrong:** Treating prescription order date as exact treatment date misses administration delays
**Why it happens:** PRESCRIBING table captures order, not administration; actual start may be days/weeks later
**How to avoid:** Accept this as data limitation (acknowledged in PCORnet CDM); use PRESCRIBING as supplemental signal only (D-03: chemo has both PROCEDURES and PRESCRIBING)
**Warning signs:** Chemo "first dates" weeks before hospital admission; prescriptions ordered but never filled

### Pitfall 7: Reloading Encounters Instead of Reusing
**What goes wrong:** Re-filtering ENCOUNTER table instead of reusing `encounters` object from `02_harmonize_payer.R`
**Why it happens:** Not realizing `encounters` is already in R environment with `payer_category` computed
**How to avoid:** Check `02_harmonize_payer.R` §2 — `encounters` object has everything needed (ID, ADMIT_DATE, payer_category, effective_payer)
**Warning signs:** Duplicate compute_effective_payer() calls; memory usage spikes; slow execution

## Code Examples

Verified patterns from existing codebase:

### Example 1: Extract First Treatment Date (Multi-Source)
```r
# Source: Adapted from R/02_harmonize_payer.R §3 (first_dx pattern)
# Radiation therapy example (two sources: PROCEDURES only, no PRESCRIBING)

# Get earliest radiation from PROCEDURES (all PX_TYPE values per D-02)
rad_px_dates <- pcornet$PROCEDURES %>%
  filter(
    (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$radiation_cpt) |
    (PX_TYPE == "09" & PX %in% TREATMENT_CODES$radiation_icd9) |
    (PX_TYPE == "10" & PX %in% TREATMENT_CODES$radiation_icd10pcs)
  ) %>%
  filter(!is.na(PX_DATE)) %>%
  group_by(ID) %>%
  summarise(FIRST_RADIATION_DATE = min(PX_DATE, na.rm = TRUE), .groups = "drop")

message(glue("Patients with radiation procedure dates: {nrow(rad_px_dates)}"))
```

### Example 2: Temporal Window Join + Mode Calculation
```r
# Source: Direct copy from R/02_harmonize_payer.R §4c
# Compute PAYER_AT_RADIATION using existing encounters object

window_days <- CONFIG$analysis$treatment_window_days  # 30

payer_at_rad <- encounters %>%
  # Filter to valid payers only (same as §4c)
  filter(!is.na(effective_payer) &
         nchar(trimws(effective_payer)) > 0 &
         !effective_payer %in% PAYER_MAPPING$sentinel_values) %>%
  # Join to first radiation dates
  inner_join(rad_px_dates, by = "ID") %>%
  # Calculate days from treatment
  mutate(days_from_treatment = as.numeric(ADMIT_DATE - FIRST_RADIATION_DATE)) %>%
  # Filter to ±30 day window
  filter(!is.na(days_from_treatment) & abs(days_from_treatment) <= window_days) %>%
  # Count encounters per patient per payer category
  group_by(ID, payer_category) %>%
  summarise(n = n(), .groups = "drop") %>%
  # Mode: highest count, alphabetical tie-breaking
  arrange(ID, desc(n), payer_category) %>%
  group_by(ID) %>%
  slice(1) %>%
  ungroup() %>%
  select(ID, PAYER_AT_RADIATION = payer_category)

# Log match counts (D-12)
n_matched <- sum(!is.na(payer_at_rad$PAYER_AT_RADIATION))
n_no_match <- nrow(rad_px_dates) - n_matched
message(glue("PAYER_AT_RADIATION: {n_matched} matched, {n_no_match} no encounters in window (NA)"))
```

### Example 3: Join Treatment Dates and Payer to Cohort
```r
# Source: R/04_build_cohort.R §7 (final assembly pattern)
# Add FIRST_RADIATION_DATE and PAYER_AT_RADIATION columns

hl_cohort <- hl_cohort %>%
  left_join(
    rad_px_dates %>% select(ID, FIRST_RADIATION_DATE),
    by = "ID"
  ) %>%
  left_join(
    payer_at_rad %>% select(ID, PAYER_AT_RADIATION),
    by = "ID"
  )

# Verify join results
message(glue("  Patients with FIRST_RADIATION_DATE: {sum(!is.na(hl_cohort$FIRST_RADIATION_DATE))}"))
message(glue("  Patients with PAYER_AT_RADIATION: {sum(!is.na(hl_cohort$PAYER_AT_RADIATION))}"))
```

## ICD Procedure Code Lists

### Chemotherapy Codes

**ICD-10-PCS (Section 3: Administration, Root Operation: Introduction):**
- 3E0 series: Introduction of substances into body systems
- Key qualifier: Antineoplastic (character 6)
- Example codes (full list requires CMS 2026 ICD-10-PCS manual):
  - 3E03305: Introduction of antineoplastic into peripheral vein, percutaneous approach
  - 3E04305: Introduction of antineoplastic into central vein, percutaneous approach
- **Recommendation:** Use broad qualifier-based matching: filter ICD-10-PCS codes starting with "3E0" AND containing qualifier "5" (antineoplastic) in character 6

**ICD-9-CM Volume 3:**
- 99.25: Injection or infusion of cancer chemotherapeutic substance
- **Note:** Single comprehensive code covers all chemotherapy administration routes

### Radiation Therapy Codes

**ICD-10-PCS (Section D: Radiation Therapy):**
- D7 series: Lymphatic and Hematologic System radiation
  - D70: Beam Radiation
  - D71: Brachytherapy
  - D72: Stereotactic Radiosurgery
  - D7Y: Other Radiation (plaque radiation)
- Example codes:
  - D7013ZZ: Beam radiation of neck lymphatics, photons 1-10 MeV
  - D7023ZZ: Beam radiation of axilla lymphatics, photons 1-10 MeV
- **Recommendation:** Use prefix matching: filter ICD-10-PCS codes starting with "D70", "D71", "D72", or "D7Y" for lymphatic/hematologic radiation

**ICD-9-CM Volume 3:**
- 92.2x: Therapeutic radiology and nuclear medicine
  - 92.20: Infusion of liquid brachytherapy radioisotope
  - 92.21: Superficial radiation
  - 92.22: Orthovoltage radiation
  - 92.23: Radioisotopic teleradiotherapy
  - 92.24: Teleradiotherapy using photons
  - 92.25: Teleradiotherapy using electrons
  - 92.26: Teleradiotherapy of other particulate radiation
  - 92.27: Implantation or insertion of radioactive elements
  - 92.29: Other radiotherapeutic procedure
- 92.3x: Stereotactic radiosurgery
  - 92.30: Stereotactic radiosurgery, not otherwise specified
  - 92.31: Single source photon radiosurgery
  - 92.32: Multi-source photon radiosurgery (Gamma Knife)
  - 92.33: Particulate radiosurgery
- 92.41: Intra-operative electron radiation therapy (IERT)

### Stem Cell Transplant Codes

**ICD-10-PCS (Section 30: Administration, Root Operation: Transfusion):**
- 302 series: Transfusion into circulatory system
  - Character 5 substance: Hematopoietic Stem Cells
- Key codes:
  - 30233G0: Autologous hematopoietic stem cells, peripheral vein, percutaneous
  - 30233G1: Nonautologous hematopoietic stem cells, peripheral vein, percutaneous
  - 30243Y0: Autologous hematopoietic stem cells, central vein, percutaneous
  - 30243Y1: Nonautologous hematopoietic stem cells, central vein, percutaneous
  - 30233X0: Autologous cord blood stem cells, peripheral vein, percutaneous
- **Recommendation:** Use character-based matching: filter codes starting with "302" AND containing "G" (hematopoietic stem cells) or "X" (cord blood stem cells) or "Y" (hematopoietic stem cells, other notation)

**ICD-9-CM Volume 3:**
- 41.0x: Bone marrow or hematopoietic stem cell transplant
  - 41.00: Bone marrow transplant, not otherwise specified
  - 41.01: Autologous bone marrow transplant without purging
  - 41.02: Allogeneic bone marrow transplant with purging
  - 41.03: Allogeneic bone marrow transplant without purging
  - 41.04: Autologous hematopoietic stem cell transplant without purging
  - 41.05: Allogeneic hematopoietic stem cell transplant without purging
  - 41.06: Cord blood stem cell transplant
  - 41.07: Autologous hematopoietic stem cell transplant with purging
  - 41.08: Allogeneic hematopoietic stem cell transplant with purging
  - 41.09: Autologous bone marrow transplant with purging

### Implementation Notes

1. **Code list storage:** Add three new entries to `TREATMENT_CODES` in `00_config.R`:
   - `chemo_icd9 = c("99.25")`
   - `chemo_icd10pcs = c("3E03305", "3E04305", ...)` — full list or regex pattern "^3E0.*5$"
   - `radiation_icd9 = c("92.20", "92.21", ..., "92.41")`
   - `radiation_icd10pcs = c("D70", "D71", "D72", "D7Y")` — prefix match
   - `sct_icd9 = c("41.00", "41.01", ..., "41.09")`
   - `sct_icd10pcs = c("30233G0", "30233G1", ...)` — full list or pattern match

2. **ICD-10-PCS prefix matching:** For radiation (D7 series) and chemo (3E0 series), consider using `str_starts(PX, "D70") | str_starts(PX, "D71") | ...` instead of exhaustive code lists (thousands of anatomic site permutations)

3. **Validation:** Cross-reference first treatment dates against TUMOR_REGISTRY dates (DT_CHEMO, DT_RAD, DT_HTE) to verify code lists capture expected procedures

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Separate CPT and HCPCS PX_TYPE values | Combined "CH" category | PCORnet CDM v7.0 (Jan 2025) | Simplifies filtering but loses granularity (can't distinguish CPT vs HCPCS) |
| ICD-9-CM Volume 3 procedures | ICD-10-PCS | Oct 1, 2015 (US mandate) | Must include BOTH for longitudinal cohorts spanning transition |
| Manual mode calculation | dplyr grouped summarise + slice | dplyr 1.0.0+ (May 2020) | slice(1) after arrange() is now idiomatic; slice_min/max handle ties differently |
| Equi-joins only | Non-equi joins via join_by() | dplyr 1.1.0 (Jan 2023) | Could use `join_by(closest(date))` but existing `inner_join + filter` is clearer |

**Deprecated/outdated:**
- `slice_min(with_ties = TRUE)`: Returns ALL ties, not deterministic; use `arrange() %>% slice(1)` for reproducible mode
- ICD-10-PCS radiation codes 77385/77386: Deleted effective Jan 1, 2026; replaced with complexity-based codes (77407, 77412, etc.) — affects CPT only, not ICD-10-PCS
- PX_TYPE values "C2", "C3", "C4": Deprecated in PCORnet v7.0; CPT Category I/II/III collapsed into "CH"

## Open Questions

1. **PRESCRIBING RX_ORDER_DATE accuracy**
   - What we know: RX_ORDER_DATE is prescription order date, not administration date
   - What's unclear: Median lag between order and first administration (days? weeks?)
   - Recommendation: Accept as data limitation; use PRESCRIBING as supplemental chemo signal only (D-03), not sole source

2. **ICD-10-PCS character-based filtering complexity**
   - What we know: ICD-10-PCS codes are 7-character alphanumeric with positional semantics
   - What's unclear: Whether PCORnet sites store full 7-character codes or abbreviated formats
   - Recommendation: Verify PX field format in actual data (e.g., "3E03305" vs "3E0-33-05"); use `str_detect()` patterns if abbreviated

3. **Payer mode stability within ±30 days**
   - What we know: Mode assumes single dominant payer within window
   - What's unclear: How often do patients have 50/50 split (e.g., 2 Medicare encounters, 2 Medicaid encounters in 60-day window)?
   - Recommendation: Log tie counts during implementation; if >10% ties, consider secondary metric (earliest encounter payer) or wider window

4. **Treatment dates earlier than diagnosis dates**
   - What we know: Chemotherapy/radiation can start before formal HL diagnosis (emergency treatment)
   - What's unclear: How to interpret payer mode when treatment precedes diagnosis by >30 days
   - Recommendation: Do NOT filter out pre-diagnosis treatments; allow negative `days_from_dx` in downstream analysis (users may want to study pre-diagnosis treatment patterns)

## Sources

### Primary (HIGH confidence)
- PCORnet CDM v7.0 Specification (Jan 2025): [PDF](https://pcornet.org/wp-content/uploads/2025/01/PCORnet-Common-Data-Model-v70-2025_01_23.pdf) — PROCEDURES table structure, PX_TYPE values, PRESCRIBING table
- Existing codebase (`R/02_harmonize_payer.R` §4c, `R/03_cohort_predicates.R` §2, `R/04_build_cohort.R` §6-7): Direct template for all implementation patterns
- [ICD-9-CM Vol 3 Procedure Codes](https://www.findacode.com/icd-9/icd-9-v3-procedure-codes.html): Chemotherapy (99.25), radiation (92.2x, 92.3x), SCT (41.0x)
- [ICD-10-PCS Codes 2026](https://www.icd10data.com/ICD10PCS/Codes): Chemotherapy (3E0 series), radiation (D7 series), SCT (302 series)

### Secondary (MEDIUM confidence)
- [dplyr slice() reference](https://dplyr.tidyverse.org/reference/slice.html): Tie-handling behavior with_ties parameter
- [dplyr arrange() reference](https://dplyr.tidyverse.org/reference/arrange.html): Multi-column tie-breaking
- [ICD-10-PCS Radiation Therapy Section](https://www.icd10data.com/ICD10PCS/Codes/D): D7 lymphatic/hematologic codes
- [ICD-10-PCS Stem Cell Transfusion](https://www.icd10data.com/ICD10PCS/Codes/3/0/2/3/30233X0): Hematopoietic stem cell codes
- [PCORnet PRESCRIBING RxNorm guidance](https://data-models-service.research.chop.edu/models/pcornet/6.0.0): RXNORM_CUI mapping strategy

### Tertiary (LOW confidence — flagged for validation)
- WebSearch: "PX_TYPE CH 09 10" suggests "CH" = HCPCS/CPT, "09" = ICD-9-CM, "10" = ICD-10-PCS — NOT verified in official PCORnet documentation (PDF extraction failed)
- WebSearch: ABVD regimen (doxorubicin, bleomycin, vinblastine, dacarbazine) — clinical validation needed for comprehensive chemo code list
- WebSearch: Diagnostic vs therapeutic procedure distinction — general coding guidance, not PCORnet-specific

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All libraries already in use, no new dependencies
- Architecture patterns: HIGH — Exact template exists in `02_harmonize_payer.R` §4c
- ICD procedure codes: MEDIUM — Code lists identified from authoritative sources (CMS ICD-10-PCS, FindACode ICD-9-CM) but not clinically validated for HL-specific treatment capture
- Pitfalls: MEDIUM-HIGH — Based on general claims data coding experience and PCORnet documentation, but not HL-specific
- PX_TYPE values: MEDIUM — Confirmed via WebSearch and PCORnet references, but official v7.0 PDF content not fully verified

**Research date:** 2026-03-25
**Valid until:** 30 days (stable domain — ICD codes and dplyr patterns change infrequently)

---

**Ready for planning:** All five research domains investigated. Planner can create PLAN.md with tasks for:
1. Add ICD-9/10-PCS code lists to `00_config.R`
2. Create `10_treatment_payer.R` with three payer-at-treatment functions
3. Modify `04_build_cohort.R` to source new script and join columns
4. Verify first treatment date distributions and payer mode match rates
