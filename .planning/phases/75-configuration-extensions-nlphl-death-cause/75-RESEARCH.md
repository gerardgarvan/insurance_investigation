# Phase 75: Configuration Extensions (NLPHL & Death Cause) - Research

**Researched:** 2026-06-02
**Domain:** ICD-10 classification logic, configuration pattern extension, R unit testing
**Confidence:** HIGH

## Summary

Phase 75 extends the configuration layer (`R/00_config.R`) with two independent enhancements: (1) NLPHL classification logic using 4-character prefix matching to distinguish C81.0 from C81.x codes, and (2) death cause mapping from ICD-10 codes to clinical categories. Both follow existing patterns in the codebase (named vectors, 3-char prefix lookup). The NLPHL extension requires modifying `classify_codes()` in `R/utils/utils_cancer.R` to implement prefix length priority (4-char before 3-char fallback). Unit tests validate mutual exclusivity using the existing smoke test framework pattern.

**Primary recommendation:** Implement 4-char prefix matching as a conditional check before the existing 3-char lookup. Use WHO/CDC standard cause-of-death groupings (30-40 categories) for DEATH_CAUSE_MAP. Follow smoke test patterns (check() function with message/condition pairs) for mutual exclusivity validation.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CANCER-01 | NLPHL (C81.0 / 201.4x) broken out from Hodgkin Lymphoma as distinct category in CANCER_SITE_MAP, classify_codes(), and all downstream outputs including Gantt | 4-char prefix matching enables C810 → NLPHL before C81 → classical HL; ICD-9 NLPHL codes (201.4x) handled via separate list check |
| DEATH-01 | Cause of death data quality profiled (completeness, coding, payer stratification) before integration | DEATH_CAUSE_MAP provides standardized categorization; profiling implementation deferred to Phase 78 |
| DEATH-02 | Cause of death included in outputs (conditional on DEATH-01 showing acceptable data quality) | Configuration layer (this phase) enables downstream use in Phase 78 |
| QUAL-01 | All new/modified scripts follow v2.0 standards (styler formatting, lintr compliance, checkmate assertions, documentation headers, smoke test updates) | Smoke test patterns established in R/88_smoke_test_comprehensive.R; assertion helpers available in R/utils/utils_assertions.R |

</phase_requirements>

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**NLPHL Category Naming**
- **D-01:** NLPHL category label = `"NLPHL"` (short clinical abbreviation, concise in tables)
- **D-02:** Classical HL category label = `"Hodgkin Lymphoma (non-NLPHL)"` (explicitly signals exclusion of NLPHL)
- **D-03:** No roll-up constant in config. Downstream scripts combine NLPHL + non-NLPHL when needed. Keep CANCER_SITE_MAP atomic.

**Death Cause Grouping**
- **D-04:** All-cause detailed grouping scheme (~30-40 category groups covering cancer subtypes and all major non-cancer causes)
- **D-05:** Explicit `"Unknown or Unspecified"` category for empty/invalid codes — makes missingness visible in output tables rather than silent NA
- **D-06:** 3-char ICD-10 prefixes as map keys — same pattern as CANCER_SITE_MAP (e.g., `"C81" = "Hodgkin Lymphoma"`, `"I25" = "Ischemic Heart Disease"`)
- **D-07:** DEATH_CAUSE_MAP as a separate top-level named vector in R/00_config.R — follows existing convention (CANCER_SITE_MAP, TIER_MAPPING, AMC_PAYER_LOOKUP)

**ICD-9 NLPHL Scope**
- **D-08:** ICD9_NLPHL_CODES = 201.40 through 201.48 (9 site-specific codes) plus parent code 201.4 (10 codes total). Mirrors ICD-10 approach of including all C81.0x codes.
- **D-09:** Single `classify_codes()` function with dual logic — 4-char prefix first (C810 → NLPHL), then 3-char fallback for ICD-10; ICD9_NLPHL_CODES list check for ICD-9. One function handles everything (simpler API for 15 downstream scripts).

### Claude's Discretion

None — all gray areas resolved by user.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Existing codebase dependency; used for string operations (substr) in classify_codes() |
| stringr | 1.5.1+ | String operations | Existing codebase pattern; may be useful for ICD code normalization if needed |
| glue | 1.8.0+ | String interpolation | Existing smoke test dependency; used for test messages |

**Note:** No new package dependencies required. All functionality implementable with base R (substr, named vector lookup, %in% operator).

### Testing Infrastructure
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| checkmate | 1.0.0+ | Assertion validation | Already loaded in R/00_config.R; use for input validation |
| glue | 1.8.0+ | Test message formatting | Follow existing smoke test pattern from R/88_smoke_test_comprehensive.R |

**Installation:**
None required — all dependencies already in project.

## Architecture Patterns

### Recommended Configuration Structure

**Location:** `R/00_config.R` (extend existing file, do not create new files)

**Section organization:**
```r
# ==============================================================================
# SECTION N: CANCER CLASSIFICATION ----
# ==============================================================================

# ICD-9 NLPHL Codes
# WHY separate list: ICD-9 codes don't use prefix matching — checked via %in%
# operator. ICD-10 codes use 4-char then 3-char prefix hierarchy.
ICD9_NLPHL_CODES <- c(
  "201.4",   # Parent code (no site digit)
  "201.40", "201.41", "201.42", "201.43", "201.44",
  "201.45", "201.46", "201.47", "201.48"
)

# Cancer Site Classification Map
# UPDATED: C810 and C81 entries modified for NLPHL breakout
# NOTE: C810 must be checked BEFORE C81 in classify_codes() function
CANCER_SITE_MAP <- c(
  # ... existing entries ...

  # Hodgkin Lymphoma (4-char prefix for NLPHL, then 3-char for classical)
  "C810" = "NLPHL",  # Nodular lymphocyte predominant HL (C81.0x codes)
  "C81" = "Hodgkin Lymphoma (non-NLPHL)",  # All other C81.xx codes

  # ... remaining entries ...
)

# ==============================================================================
# SECTION N+1: DEATH CAUSE CLASSIFICATION ----
# ==============================================================================

# Death Cause Classification Map
# Maps 3-character ICD-10 prefixes to standardized cause-of-death categories.
# Based on WHO Mortality Database and CDC NCHS 113 Selected Causes groupings.
# Used by Phase 78 death data profiling and output generation.
#
# WHY 3-char prefixes: Matches CANCER_SITE_MAP pattern; balances specificity
# (too granular = 50+ cancer subcategories) with utility (too broad = "all cancer").
#
# Sources:
# - WHO Mortality Database: https://platform.who.int/mortality/about/list-of-causes-and-corresponding-icd-10-codes
# - CDC NCHS 113 Selected Causes: https://ibis.doh.nm.gov/resource/ICDCodes.html
DEATH_CAUSE_MAP <- c(
  # Infectious and Parasitic Diseases (A00-B99)
  # ... entries ...

  # Neoplasms (C00-D48)
  # ... cancer-specific entries ...

  # Circulatory (I00-I99)
  # ... cardiovascular entries ...

  # Respiratory (J00-J98)
  # ... respiratory entries ...

  # External Causes (V01-Y89)
  # ... injury entries ...

  # Unknown/Missing
  # Default category for empty, invalid, or unmappable codes
  "UNK" = "Unknown or Unspecified"
)
```

### Pattern 1: Hierarchical Prefix Matching (4-char before 3-char)

**What:** Check longer prefixes before shorter ones to enable subcategory breakouts while maintaining backward compatibility.

**When to use:** When a 3-character ICD-10 category (e.g., C81) contains a subcategory (e.g., C81.0) that requires separate classification.

**Example:**
```r
# Source: Project-specific pattern based on ICD-10 hierarchical structure
# ICD-10 structure: 3-char category, 4-char subcategory (after decimal)
# Reference: https://www.bfarm.de/EN/Code-systems/Classifications/ICD/ICD-10-WHO/Tabular-list/codestructure.html

classify_codes <- function(codes) {
  # Initialize result vector
  categories <- character(length(codes))

  # Strategy: Check 4-char prefix first (subcategory), then 3-char (category)
  # This enables C810 → NLPHL before C81 → classical HL

  prefix4 <- substr(codes, 1, 4)
  prefix3 <- substr(codes, 1, 3)

  # Try 4-char match first (ICD-10 subcategory level)
  match4 <- CANCER_SITE_MAP[prefix4]

  # Fallback to 3-char match (ICD-10 category level)
  match3 <- CANCER_SITE_MAP[prefix3]

  # Priority: 4-char match if available, else 3-char match
  categories <- ifelse(!is.na(match4), match4, match3)

  # ICD-9 special handling: Check full code against ICD9_NLPHL_CODES list
  # WHY separate check: ICD-9 codes don't follow dotted format (201.40 not 201.4.0)
  # so prefix matching doesn't work cleanly
  is_icd9_nlphl <- codes %in% ICD9_NLPHL_CODES
  categories[is_icd9_nlphl] <- "NLPHL"

  # Return unname() to remove any residual names from vector indexing
  unname(categories)
}
```

**Why this pattern:**
- ICD-10 is hierarchical: 3-char = category, 4-char = subcategory, 5+ = finer detail
- Standard CANCER_SITE_MAP uses 3-char keys for broad categories (C50 = Breast)
- NLPHL breakout requires 4-char specificity (C810 = NLPHL vs C811-C819 = classical)
- Checking 4-char first prevents C81.0x codes from incorrectly matching C81 entry
- Fallback to 3-char preserves existing behavior for all non-NLPHL codes

### Pattern 2: Named Vector Lookup for Configuration Constants

**What:** Store classification mappings as top-level named character vectors in `R/00_config.R`.

**When to use:** Any mapping from codes (ICD, payer, tier) to human-readable categories that multiple scripts need.

**Example:**
```r
# Existing pattern from R/00_config.R (line 413, 299)
CANCER_SITE_MAP <- c(
  "C50" = "Breast",
  "C81" = "Hodgkin Lymphoma",
  # ... 322 more entries
)

AMC_PAYER_LOOKUP <- c(
  "AARP" = "Commercial",
  "AETNA" = "Commercial",
  # ... ~50 entries
)

# New addition following same pattern
DEATH_CAUSE_MAP <- c(
  "I25" = "Ischemic Heart Disease",
  "C81" = "Hodgkin Lymphoma",
  # ... ~30-40 entries
)
```

**Why this pattern:**
- R named vectors support O(1) lookup via `map[key]`
- Single definition eliminates duplication (previous issue: CANCER_SITE_MAP duplicated in 11 scripts)
- Easy to extend (add entries without changing function signatures)
- Human-readable (keys = codes, values = categories)
- No external file dependencies (avoids runtime xlsx/CSV loading)

### Pattern 3: Smoke Test Validation

**What:** Lightweight pass/fail checks using `check()` function that increments global `passed`/`failed` counters.

**When to use:** Structural validation, configuration integrity checks, cross-reference validation.

**Example:**
```r
# Source: R/88_smoke_test_comprehensive.R existing pattern (lines 44-52)

# Global counters (defined at file top)
passed <- 0L
failed <- 0L

check <- function(description, condition) {
  if (condition) {
    message(glue("  PASS: {description}"))
    passed <<- passed + 1L
  } else {
    message(glue("  FAIL: {description}"))
    failed <<- failed + 1L
  }
}

# NLPHL mutual exclusivity test (new addition)
message("\n[X/17] NLPHL classification mutual exclusivity...")

# Test data: codes that should classify as NLPHL
nlphl_icd10 <- c("C810", "C8100", "C8109", "C810A")
nlphl_icd9 <- c("201.4", "201.40", "201.48")

# Test data: codes that should classify as classical HL (non-NLPHL)
classical_icd10 <- c("C811", "C8110", "C812", "C819", "C8190")
classical_icd9 <- c("201.0", "201.5", "201.9")

# Classify all codes
nlphl_results <- classify_codes(nlphl_icd10)
nlphl_icd9_results <- classify_codes(nlphl_icd9)
classical_results <- classify_codes(classical_icd10)
classical_icd9_results <- classify_codes(classical_icd9)

# Check mutual exclusivity: no NLPHL codes classified as classical HL
check(
  "NLPHL ICD-10 codes classify as 'NLPHL' not 'Hodgkin Lymphoma (non-NLPHL)'",
  all(nlphl_results == "NLPHL")
)

check(
  "NLPHL ICD-9 codes classify as 'NLPHL'",
  all(nlphl_icd9_results == "NLPHL")
)

check(
  "Classical HL ICD-10 codes classify as 'Hodgkin Lymphoma (non-NLPHL)' not 'NLPHL'",
  all(classical_results == "Hodgkin Lymphoma (non-NLPHL)")
)

check(
  "Classical HL ICD-9 codes classify as 'Hodgkin Lymphoma (non-NLPHL)' not 'NLPHL'",
  all(classical_icd9_results == "Hodgkin Lymphoma (non-NLPHL)")
)

# Check no overlap: a single code cannot produce both classifications
all_hl_codes <- c(nlphl_icd10, nlphl_icd9, classical_icd10, classical_icd9)
all_results <- classify_codes(all_hl_codes)
nlphl_count <- sum(all_results == "NLPHL")
classical_count <- sum(all_results == "Hodgkin Lymphoma (non-NLPHL)")

check(
  glue("NLPHL + classical HL counts sum to total HL codes ({nlphl_count} + {classical_count} = {length(all_hl_codes)})"),
  (nlphl_count + classical_count) == length(all_hl_codes)
)
```

### Anti-Patterns to Avoid

- **Don't create separate files for configuration:** All lookup maps go in `R/00_config.R` (existing pattern)
- **Don't use data frames for simple lookups:** Named vectors are faster and simpler for key→value mappings
- **Don't check 3-char prefix before 4-char:** C81.00 would match "C81" before "C810", breaking NLPHL detection
- **Don't use `testthat::test_that()` in smoke tests:** Project uses custom `check()` function with global counters (simpler, no external framework)
- **Don't load DEATH_CAUSE_MAP from external file:** Centralize in R/00_config.R to avoid runtime dependencies and git-out-of-sync risk
- **Don't silently return NA for unknown cause codes:** Use explicit "Unknown or Unspecified" category per D-05

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ICD-10 comorbidity scoring | Custom Charlson/Elixhauser implementation | `icd` or `comorbidity` R packages | Edge cases in hierarchical condition exclusions, version-specific mappings |
| Comprehensive ICD-10 validation | Regex patterns for valid codes | `icd::is_valid()` from icd package | Handles version-specific code ranges, decimal placement rules, deprecated codes |
| WHO/CDC standardized groupings | Custom 113-category mapping | Reference official grouping schemas | CDC periodically updates category definitions; custom mappings go stale |

**Key insight:** This phase doesn't need heavy ICD tooling — simple prefix matching suffices. But if future phases require comorbidity indices or formal ICD validation, use established packages rather than building from scratch.

## Common Pitfalls

### Pitfall 1: Order-Dependent Lookup Failure

**What goes wrong:** Adding "C810" entry to CANCER_SITE_MAP but not updating `classify_codes()` logic causes C810 codes to match "C81" entry first, returning "Hodgkin Lymphoma (non-NLPHL)" instead of "NLPHL".

**Why it happens:** Named vector lookup `CANCER_SITE_MAP[prefix3]` uses first match. If both "C810" and "C81" keys exist but function only checks 3-char prefix, "C81" always wins.

**How to avoid:**
1. Implement 4-char check BEFORE 3-char check in `classify_codes()`
2. Add unit test that verifies C810 → "NLPHL" and C811 → "Hodgkin Lymphoma (non-NLPHL)"
3. Test with real code examples from both categories

**Warning signs:**
- Smoke test fails on NLPHL classification
- Downstream scripts (Phase 77) show zero NLPHL patients despite C81.0x codes in data
- Cancer site frequency table shows all Hodgkin cases as "Hodgkin Lymphoma (non-NLPHL)"

### Pitfall 2: ICD-9 vs ICD-10 Format Confusion

**What goes wrong:** Treating ICD-9 code "201.40" like ICD-10 dotted format "C81.0" causes incorrect prefix extraction.

**Why it happens:** ICD-9 uses decimal point as part of the code (201.40 = 5 chars including dot). ICD-10 uses dotted format for display only (C81.0 stored as C810). Different data sources may store with/without dots.

**How to avoid:**
1. Use separate `ICD9_NLPHL_CODES` list for exact matching via `%in%` operator
2. Don't rely on `substr(code, 1, 5)` for ICD-9 — use full code comparison
3. Document assumption: ICD-10 codes stored without dots (C8100 not C81.00)

**Warning signs:**
- ICD-9 201.40-201.48 codes not classified as NLPHL
- `classify_codes()` returns NA for valid ICD-9 NLPHL codes
- Unit test passes for ICD-10 but fails for ICD-9 examples

### Pitfall 3: Incomplete Death Cause Coverage

**What goes wrong:** Creating DEATH_CAUSE_MAP with only 10-15 major categories leaves 60%+ of death records classified as "Unknown or Unspecified" even when valid ICD-10 codes exist.

**Why it happens:** Simple grouping (e.g., all cancers = "Cancer", all cardiovascular = "Cardiovascular") uses 2-char prefixes (C00-C99 → "Cancer") but user specified 3-char keys. Incomplete category list misses common causes (accidents, diabetes, kidney disease).

**How to avoid:**
1. Use WHO/CDC standard groupings as reference (~30-40 categories minimum)
2. Cover ALL ICD-10 chapters: A-B (infectious), C-D48 (neoplasms), I (circulatory), J (respiratory), K (digestive), N (genitourinary), V-Y (external causes), R99 (ill-defined)
3. Verify coverage with real data during Phase 78 profiling — if >20% fall into "Unknown", expand map
4. Document sources: WHO Mortality Database and CDC NCHS 113 Selected Causes

**Warning signs:**
- Phase 78 profiling shows >40% "Unknown or Unspecified" despite non-missing DEATH_CAUSE field
- Cause-of-death output tables dominated by single "Unknown" category
- Payer stratification impossible due to insufficient category granularity

### Pitfall 4: Double-Counting in Mutual Exclusivity Tests

**What goes wrong:** Testing that "no patient has both NLPHL and classical HL" by checking diagnosis table, but same patient has C810 (NLPHL) and C811 (classical HL) in different encounters — test incorrectly flags as failure.

**Why it happens:** Mutual exclusivity applies to CLASSIFICATION of a single code, not patient-level diagnosis history. A patient can have multiple cancer types over time.

**How to avoid:**
1. Test at CODE level not PATIENT level: `classify_codes("C810")` must return "NLPHL", never "Hodgkin Lymphoma (non-NLPHL)"
2. Check that NLPHL codes and classical HL codes produce different category values
3. Verify sum(NLPHL count) + sum(classical count) = sum(all HL code classifications) — no code produces both

**Warning signs:**
- Test failure messages referencing "patient" or "PATID" instead of code strings
- False positive failures when patients have documented transformation (NLPHL → classical HL conversion, rare but possible)
- Test logic joins DIAGNOSIS table instead of just calling `classify_codes()` with example codes

## Code Examples

Verified patterns from project codebase and ICD-10 standards:

### Hierarchical Prefix Matching

```r
# Source: Derived from existing classify_codes() in R/utils/utils_cancer.R (line 36)
# Extended to support 4-char-before-3-char lookup

classify_codes <- function(codes) {
  # Extract prefixes at different lengths
  prefix4 <- substr(codes, 1, 4)  # Subcategory level (e.g., C810)
  prefix3 <- substr(codes, 1, 3)  # Category level (e.g., C81)

  # Attempt 4-char match first (more specific)
  match4 <- CANCER_SITE_MAP[prefix4]

  # Fallback to 3-char match (broader category)
  match3 <- CANCER_SITE_MAP[prefix3]

  # Use 4-char result if available, else 3-char
  categories <- ifelse(!is.na(match4), match4, match3)

  # Special case: ICD-9 NLPHL codes (exact match required)
  is_icd9_nlphl <- codes %in% ICD9_NLPHL_CODES
  categories[is_icd9_nlphl] <- "NLPHL"

  unname(categories)
}
```

### Death Cause Mapping Structure (30-40 Categories)

```r
# Source: WHO Mortality Database (https://platform.who.int/mortality/about/list-of-causes-and-corresponding-icd-10-codes)
# CDC NCHS 113 Selected Causes (https://ibis.doh.nm.gov/resource/ICDCodes.html)

DEATH_CAUSE_MAP <- c(
  # === INFECTIOUS AND PARASITIC DISEASES (A00-B99) ===
  "A00" = "Cholera",
  "A01" = "Typhoid and Paratyphoid Fevers",
  "A15" = "Tuberculosis (Respiratory)",
  "A16" = "Tuberculosis (Respiratory)",
  "A17" = "Tuberculosis (Nervous System)",
  "A18" = "Tuberculosis (Other Organs)",
  "A19" = "Miliary Tuberculosis",
  "B20" = "HIV Disease",
  "B21" = "HIV Disease",
  "B22" = "HIV Disease",
  "B23" = "HIV Disease",
  "B24" = "HIV Disease",

  # === NEOPLASMS (C00-D48) ===
  # Digestive organs
  "C15" = "Esophageal Cancer",
  "C16" = "Stomach Cancer",
  "C18" = "Colon Cancer",
  "C19" = "Colon Cancer",
  "C20" = "Rectal Cancer",
  "C22" = "Liver Cancer",
  "C25" = "Pancreatic Cancer",

  # Respiratory
  "C33" = "Tracheal Cancer",
  "C34" = "Lung Cancer",

  # Breast and reproductive
  "C50" = "Breast Cancer",
  "C53" = "Cervical Cancer",
  "C54" = "Uterine Cancer",
  "C55" = "Uterine Cancer",
  "C56" = "Ovarian Cancer",
  "C61" = "Prostate Cancer",

  # Hematologic
  "C81" = "Hodgkin Lymphoma",
  "C82" = "Non-Hodgkin Lymphoma",
  "C83" = "Non-Hodgkin Lymphoma",
  "C84" = "Non-Hodgkin Lymphoma",
  "C85" = "Non-Hodgkin Lymphoma",
  "C90" = "Multiple Myeloma",
  "C91" = "Leukemia",
  "C92" = "Leukemia",
  "C93" = "Leukemia",
  "C94" = "Leukemia",
  "C95" = "Leukemia",

  # Other cancers
  "C43" = "Melanoma",
  "C44" = "Non-Melanoma Skin Cancer",
  "C64" = "Kidney Cancer",
  "C67" = "Bladder Cancer",
  "C71" = "Brain Cancer",

  # === CIRCULATORY DISEASES (I00-I99) ===
  "I20" = "Angina Pectoris",
  "I21" = "Acute Myocardial Infarction",
  "I22" = "Acute Myocardial Infarction",
  "I23" = "Acute Myocardial Infarction Complications",
  "I24" = "Acute Ischemic Heart Disease",
  "I25" = "Chronic Ischemic Heart Disease",
  "I50" = "Heart Failure",
  "I60" = "Hemorrhagic Stroke",
  "I61" = "Hemorrhagic Stroke",
  "I63" = "Ischemic Stroke",
  "I64" = "Stroke (Unspecified)",
  "I11" = "Hypertensive Heart Disease",
  "I13" = "Hypertensive Heart and Kidney Disease",

  # === RESPIRATORY DISEASES (J00-J98) ===
  "J12" = "Viral Pneumonia",
  "J13" = "Pneumococcal Pneumonia",
  "J14" = "Pneumonia Due to Hemophilus Influenzae",
  "J15" = "Bacterial Pneumonia",
  "J16" = "Pneumonia (Other Organisms)",
  "J17" = "Pneumonia (Other Diseases)",
  "J18" = "Pneumonia (Unspecified)",
  "J40" = "Chronic Bronchitis",
  "J41" = "Chronic Bronchitis",
  "J42" = "Chronic Bronchitis",
  "J43" = "Emphysema",
  "J44" = "Chronic Obstructive Pulmonary Disease",

  # === DIGESTIVE DISEASES (K00-K92) ===
  "K25" = "Gastric Ulcer",
  "K26" = "Duodenal Ulcer",
  "K70" = "Alcoholic Liver Disease",
  "K72" = "Hepatic Failure",
  "K73" = "Chronic Hepatitis",
  "K74" = "Liver Fibrosis and Cirrhosis",

  # === GENITOURINARY DISEASES (N00-N98) ===
  "N17" = "Acute Kidney Failure",
  "N18" = "Chronic Kidney Disease",
  "N19" = "Kidney Failure (Unspecified)",

  # === EXTERNAL CAUSES (V01-Y89) ===
  "V01" = "Pedestrian Accident",
  "V02" = "Pedestrian Accident",
  "V03" = "Pedestrian Accident",
  "V04" = "Pedestrian Accident",
  "V12" = "Pedal Cyclist Accident",
  "V13" = "Pedal Cyclist Accident",
  "V40" = "Motor Vehicle Occupant Accident",
  "V41" = "Motor Vehicle Occupant Accident",
  "V42" = "Motor Vehicle Occupant Accident",
  "V43" = "Motor Vehicle Occupant Accident",
  "V44" = "Motor Vehicle Occupant Accident",
  "V45" = "Motor Vehicle Occupant Accident",
  "V46" = "Motor Vehicle Occupant Accident",
  "V47" = "Motor Vehicle Occupant Accident",
  "V48" = "Motor Vehicle Occupant Accident",
  "V49" = "Motor Vehicle Occupant Accident",
  "W00" = "Fall on Same Level (Ice/Snow)",
  "W01" = "Fall on Same Level (Slipping/Tripping)",
  "W18" = "Fall (Other)",
  "W19" = "Fall (Unspecified)",
  "X40" = "Accidental Poisoning",
  "X41" = "Accidental Poisoning",
  "X42" = "Accidental Poisoning",
  "X43" = "Accidental Poisoning",
  "X44" = "Accidental Poisoning",
  "X60" = "Intentional Self-Harm (Poisoning)",
  "X61" = "Intentional Self-Harm (Poisoning)",
  "X70" = "Intentional Self-Harm (Hanging)",
  "X71" = "Intentional Self-Harm (Drowning)",
  "X72" = "Intentional Self-Harm (Firearm)",
  "X73" = "Intentional Self-Harm (Firearm)",
  "X74" = "Intentional Self-Harm (Firearm)",
  "Y87" = "Assault",

  # === ILL-DEFINED (R00-R99) ===
  "R54" = "Senility",
  "R99" = "Ill-Defined and Unknown Cause of Mortality",

  # === ENDOCRINE/METABOLIC (E00-E88) ===
  "E10" = "Type 1 Diabetes Mellitus",
  "E11" = "Type 2 Diabetes Mellitus",
  "E14" = "Diabetes Mellitus (Unspecified)",
  "E66" = "Obesity",

  # === NERVOUS SYSTEM (G00-G98) ===
  "G20" = "Parkinson's Disease",
  "G30" = "Alzheimer's Disease",

  # === CONGENITAL (Q00-Q99) ===
  "Q20" = "Congenital Heart Malformations",
  "Q21" = "Congenital Heart Malformations",
  "Q22" = "Congenital Heart Malformations",
  "Q23" = "Congenital Heart Malformations",
  "Q24" = "Congenital Heart Malformations",

  # === PERINATAL (P00-P96) ===
  "P00" = "Perinatal Conditions",
  "P01" = "Perinatal Conditions",
  "P02" = "Perinatal Conditions",
  "P20" = "Perinatal Respiratory Disorders",
  "P21" = "Perinatal Respiratory Disorders",
  "P22" = "Perinatal Respiratory Disorders",

  # === DEFAULT for unmapped codes ===
  "UNK" = "Unknown or Unspecified"
)
```

### Mutual Exclusivity Unit Test

```r
# Source: Extended from R/88_smoke_test_comprehensive.R existing check() pattern

message("\n[18/17] NLPHL classification mutual exclusivity...")

# Define test vectors
nlphl_icd10 <- c("C810", "C8100", "C8105", "C8109")
nlphl_icd9 <- c("201.4", "201.40", "201.45", "201.48")
classical_icd10 <- c("C811", "C8110", "C812", "C8120", "C819", "C8190")
classical_icd9 <- c("201.0", "201.00", "201.5", "201.50", "201.9", "201.90")

# Classify codes
nlphl_10_results <- classify_codes(nlphl_icd10)
nlphl_9_results <- classify_codes(nlphl_icd9)
classical_10_results <- classify_codes(classical_icd10)
classical_9_results <- classify_codes(classical_icd9)

# Test 1: NLPHL codes return "NLPHL" category
check(
  "ICD-10 C81.0x codes classify as 'NLPHL'",
  all(nlphl_10_results == "NLPHL", na.rm = TRUE)
)

check(
  "ICD-9 201.4x codes classify as 'NLPHL'",
  all(nlphl_9_results == "NLPHL", na.rm = TRUE)
)

# Test 2: Classical HL codes return "Hodgkin Lymphoma (non-NLPHL)" category
check(
  "ICD-10 C81.1-C81.9 codes classify as 'Hodgkin Lymphoma (non-NLPHL)'",
  all(classical_10_results == "Hodgkin Lymphoma (non-NLPHL)", na.rm = TRUE)
)

check(
  "ICD-9 201.0-201.9 (except 201.4) codes classify as 'Hodgkin Lymphoma (non-NLPHL)'",
  all(classical_9_results == "Hodgkin Lymphoma (non-NLPHL)", na.rm = TRUE)
)

# Test 3: Mutual exclusivity — no code produces both categories
all_codes <- c(nlphl_icd10, nlphl_icd9, classical_icd10, classical_icd9)
all_results <- classify_codes(all_codes)

nlphl_count <- sum(all_results == "NLPHL", na.rm = TRUE)
classical_count <- sum(all_results == "Hodgkin Lymphoma (non-NLPHL)", na.rm = TRUE)
total_hl <- length(all_codes)

check(
  glue("No code classified as both NLPHL and classical HL ({nlphl_count} + {classical_count} = {total_hl})"),
  (nlphl_count + classical_count) == total_hl
)

# Test 4: Verify CANCER_SITE_MAP contains both entries
check(
  "CANCER_SITE_MAP contains 'C810' = 'NLPHL' entry",
  "C810" %in% names(CANCER_SITE_MAP) && CANCER_SITE_MAP["C810"] == "NLPHL"
)

check(
  "CANCER_SITE_MAP contains 'C81' = 'Hodgkin Lymphoma (non-NLPHL)' entry",
  "C81" %in% names(CANCER_SITE_MAP) && CANCER_SITE_MAP["C81"] == "Hodgkin Lymphoma (non-NLPHL)"
)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Duplicate CANCER_SITE_MAP in 11 scripts | Single definition in R/00_config.R | Phase 71 (2026-06-01) | Eliminated ~2,860 lines of duplicate code |
| Manual `substr()` in each script | Central `classify_codes()` function | Phase 71 | DRY principle, single API |
| testthat framework for tests | Custom check() function with global counters | Phase 74 (v2.0 cleanup) | Simpler, no external dependency |

**Deprecated/outdated:**
- Multiple definitions of cancer site map: Consolidated in Phase 71
- ICD-9 support was de-emphasized but retained for historical data (OneFlorida+ contains pre-2015 records)

## Open Questions

1. **DEATH table cause field name in PCORnet v7.0**
   - What we know: PCORnet v7.0 DEATH table added in Phase 57; currently only DEATH_DATE, DEATH_SOURCE, DEATH_MATCH_CONFIDENCE loaded per `R/01_load_pcornet.R`
   - What's unclear: Whether PCORnet v7.0 includes a DEATH_CAUSE or DEATH_CAUSE_CODE field, or if cause data requires linkage to another table
   - Recommendation: Phase 78 data profiling will identify available fields. If no cause field exists in current data, DEATH_CAUSE_MAP remains unused (future-proofing for when cause data becomes available). Document assumption in config comment: "DEATH_CAUSE_MAP prepared for future cause-of-death field; not used if DEATH table lacks cause code column."

2. **Granularity of death cause categories (30 vs 40 vs 113)**
   - What we know: User specified "~30-40 category groups". WHO has 3 major groups (infectious/noncommunicable/injury). CDC has 113 Selected Causes, 50 Leading Causes, 39 Selected Causes.
   - What's unclear: Exact balance between granularity (e.g., separating lung vs colon cancer) and simplicity (all cancers = "Cancer")
   - Recommendation: Start with ~35-40 categories covering major subcategories within each ICD chapter. Phase 78 profiling validates coverage by checking what % of actual death records fall into "Unknown or Unspecified". If >20%, expand map. If tables become unwieldy, consolidate rare categories.

3. **ICD-9 vs ICD-10 transition cutoff in OneFlorida+ data**
   - What we know: US transitioned to ICD-10 Oct 1, 2015. OneFlorida+ contains data back to ~2011 (based on Phase 18 notes about pre-2015 codes).
   - What's unclear: Whether DEATH table cause codes (if present) use ICD-9, ICD-10, or mixed depending on death year
   - Recommendation: If DEATH_CAUSE field exists, Phase 78 should check code format distribution. If mixed, extend classify function to detect format (ICD-9 = starts with digit, ICD-10 = starts with letter). Document assumption in RESEARCH.md: "DEATH_CAUSE_MAP uses ICD-10 keys; ICD-9 codes require translation or separate map if found."

## Environment Availability

Phase 75 is configuration-only with no external dependencies beyond existing R packages. No environment availability audit needed.

## Project Constraints (from CLAUDE.md)

**Technology stack:**
- R 4.4.2+ on HiPerGator (module load R/4.4.2)
- tidyverse 2.0.0+ ecosystem (dplyr, stringr, lubridate)
- vroom 1.7.0+ for CSV loading (not used in this phase)
- renv 1.1.4+ for package management

**Code style requirements:**
- Named predicate functions for filtering logic (not applicable to this phase — config only)
- No opaque one-liners
- Documentation headers required
- styler formatting and lintr compliance (QUAL-01)
- checkmate assertions for defensive coding

**Existing patterns to follow:**
- Top-level named vectors in R/00_config.R for lookup maps (AMC_PAYER_LOOKUP line 299, CANCER_SITE_MAP line 413)
- Section headers with `# SECTION N: NAME ----` format
- Auto-sourcing from R/utils/ (classify_codes loaded automatically via `source("R/00_config.R")`)
- Custom smoke test check() function (not testthat framework)

**Key constraints:**
- MUST maintain compatibility with 15 downstream scripts that call `classify_codes()` — function signature cannot change
- MUST follow payer mapping pattern from Phase 36 (AMC_PAYER_LOOKUP) for DEATH_CAUSE_MAP structure
- MUST update smoke test count in summary message (currently "[1/17]...[17/17]" becomes "[1/18]...[18/18]")

## Sources

### Primary (HIGH confidence)

**ICD-10 Structure and Hierarchy:**
- [ICD-10 Code Structure (BfArM)](https://www.bfarm.de/EN/Code-systems/Classifications/ICD/ICD-10-WHO/Tabular-list/codestructure.html) - 3-char category, 4-char subcategory hierarchy
- [Understanding ICD-10-CM (Clinical Architecture)](https://clinicalarchitecture.com/understanding-icd-10-cm/) - Code length and specificity rules
- [ICD-10-CM Official Guidelines (CMS)](https://www.cms.gov/files/document/fy-2026-icd-10-cm-coding-guidelines.pdf) - Coding conventions

**WHO/CDC Death Cause Classification:**
- [WHO Mortality Database Cause Categories](https://platform.who.int/mortality/about/list-of-causes-and-corresponding-icd-10-codes) - Standard groupings for communicable, noncommunicable, injuries
- [CDC NCHS 113 Selected Causes (NM-IBIS)](https://ibis.doh.nm.gov/resource/ICDCodes.html) - Standard mortality grouping system
- [CDC Multiple Cause of Death Data](https://wonder.cdc.gov/mcd.html) - ICD-10 death coding standards
- [CDC Instructions for Classifying Underlying Cause-of-Death, ICD-10, 2025](https://www.cdc.gov/nchs/nvss/manuals/2025/2a-2025.html) - Official coding manual

**Project Codebase:**
- `R/00_config.R` (line 413) - CANCER_SITE_MAP existing pattern
- `R/00_config.R` (line 299) - AMC_PAYER_LOOKUP existing pattern
- `R/00_config.R` (line 164) - ICD_CODES list with hl_icd10 and hl_icd9
- `R/utils/utils_cancer.R` (line 36) - classify_codes() current implementation
- `R/88_smoke_test_comprehensive.R` - check() function pattern (lines 44-52), DRY validation (lines 503-517)

### Secondary (MEDIUM confidence)

**R Testing Frameworks:**
- [testthat package (CRAN)](https://cran.r-project.org/web/packages/testthat/testthat.pdf) - Unit testing framework (not used in this project, but reference for assertion patterns)
- [testthat documentation](https://testthat.r-lib.org/) - Testing best practices

**R ICD Packages (for reference, not dependencies):**
- [icd package (GitHub)](https://github.com/jackwasey/icd) - ICD-9/ICD-10 comorbidity tools
- [icd package documentation](https://jackwasey.github.io/icd/) - Classification and validation functions
- [comorbidity package (CRAN)](https://cran.r-project.org/web/packages/comorbidity/comorbidity.pdf) - Charlson/Elixhauser scores

### Tertiary (LOW confidence, marked for validation)

**PCORnet CDM Specification:**
- [PCORnet CDM v7.0 Specification (PDF)](https://pcornet.org/wp-content/uploads/2025/05/PCORnet_Common_Data_Model_v70_2025_05_01.pdf) - DEATH table field definitions (PDF extraction failed, needs manual verification)
- PCORnet official documentation not fully accessible via automated tools — manual review recommended for DEATH_CAUSE field name confirmation

**ICD-10 Code Repositories:**
- [ICD-10 Data](https://www.icd10data.com/) - Searchable ICD-10 codes (commercial site, use for spot-checking only)

## Metadata

**Confidence breakdown:**
- ICD-10 hierarchical structure (3-char vs 4-char): HIGH - Official WHO/CMS documentation confirmed
- WHO/CDC death cause groupings: HIGH - Official mortality database specifications
- Existing project patterns (named vectors, smoke tests): HIGH - Direct codebase inspection
- PCORnet DEATH table fields: MEDIUM - Table added in Phase 57 but cause field not yet confirmed in actual data
- Coverage adequacy of 30-40 categories: MEDIUM - Will be validated during Phase 78 profiling

**Research date:** 2026-06-02
**Valid until:** 90 days (2026-09-02) — ICD-10 codes and mortality groupings are stable; annual updates occur Oct 1 but don't invalidate existing codes
